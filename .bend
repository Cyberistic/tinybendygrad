# executor.bend -- tinygrad/runtime/ops_python.py `PythonProgram.__call__`, the
# BEND device. `bend-executor PACKET gx gy gz vals...` reads a packet, walks its
# toposorted uops once per global work item, and writes PACKET.out.
#
# STATE OF THIS FILE. The wire format, the op table, the packet reader and the
# ALU lane are here and compile. THE INTERPRETER LOOP IS NOT: `run` below is a
# refusal, not a stub that silently answers. Read THE REMAINING WORK before
# assuming any of this executes a packet, and read THE FOUR WALLS before
# assuming it ever will for a given dtype or op.
#
# ops_python.py's own header calls itself "the living definition of uops", and
# this file ports the ONE function that gives those uops their meaning. The
# inventory below is honest about what each arm of the `__call__` dispatch
# became here.
#
#   ops_python.py:15-31   _load/_store/_step        PORTED (the v1 lanes)
#   ops_python.py:33-44   wmma                      WALL  (tensor cores)
#   ops_python.py:52-157  PythonProgram.__call__    arm by arm, below
#
# THE DISPATCH, in ops_python.py's order, each arm with its line:
#
#   :67  BACKEDGE       PORTED  the loop head
#   :70  END            PORTED
#   :73  IF             PORTED  exec_masks, one Bool per work item at warp 1
#   :77  ENDIF          PORTED
#   :81  BARRIER/SINK/NOOP/GROUP/CUSTOM_FUNCTION, RANGE(void)  PORTED (no-ops)
#   :85  STORE          PORTED  gated, vector, stepped
#   :93  AFTER, BITCAST@GLOBAL/LOCAL    PORTED (pass-through)
#   :94  PARAM@ALU      PORTED  reads a `vals` entry
#   :95  PARAM, BUFFER  PORTED  binds a buffer, or allocates zeros
#   :106 BINARY         WALL  ops_python.py:106 -- `memoryview(u.arg)` is raw
#                              bytes carried inside the UOp, with no wire spelling
#   :107 SPECIAL        PORTED  'g' from the grid; 'l' is 0 at warp 1
#   :110 CONST          PORTED
#   :111 INDEX, SHRINK  PORTED for the ALU and buffer arms; WALL for the
#                              is_image_shape arm, which needs `_shape`
#   :123 RANGE          PORTED  the counter lives in its own arena slot
#   :132 STACK          PORTED
#   :133 BITCAST        PORTED  v1 lanes only (Python asserts equal itemsize)
#   :134 CAST           PORTED  v1 lanes only, see THE WIDE DTYPES
#   :136 LOAD           PORTED  scalar, vector, and the gated arm
#   :143 CALL           WALL  ops_python.py:143 -- a ctypes FFI call into a
#                              loaded shared object; not a uop the emulator
#                              can answer without the library
#   :150 WMMA           WALL  ops_python.py:150, as briefed
#   :151 GroupOp.ALU    PORTED, by REUSING symbolic.bend's two lanes
#
# ===========================================================================
# MEASURED FACTS. Every claim below was read out of a real render, not inferred
# from the source. The harness is .agents/slop/exec_probe*.py: it hooks
# `PythonRenderer.render`, dumps the uop list ops_python's `__call__` receives,
# and spies on the `global_size`/`local_size` kwargs. Eighteen kernels: elementwise
# add, sum, matmul, an int-to-float cast, a 64-wide grid, div, cmp, and, 2-d sum,
# rowsum, max, prod, slice, reshape, contiguous, permute, log, sqrt.
#
# 1. `Ops.REDUCE` IS NEVER EMITTED, and ops_python has no REDUCE arm. rangeify
#    lowers a reduce into a RANGE plus a tree of ADD/MULACC before the renderer
#    runs. So "a REDUCE fixture" is a RANGE loop, and this file needs no REDUCE
#    arm at all.
# 2. `Ops.FDIV` AND `Ops.THREEFRY` ARE IN `GroupOp.ALU` BUT NOT IN `python_alu`
#    (ops.py:1417-1424), so ops_python.py:154 raises `KeyError` on them. They are
#    WALL 3 below for the same reason rather than given an invented meaning.
# 3. THERE ARE NO `DEFINE_*` OPS in this tinygrad. `Ops` has PARAM and BUFFER and
#    an AddrSpace; the emitted stream uses `Ops.PARAM` with
#    `addrspace=AddrSpace.GLOBAL` and never a DEFINE. That is amendment A1.
# 4. `local_size` IS NEVER (1,1,1) FOR EVERY KERNEL -- measured (2,1,1), (4,1,1),
#    (8,1,1), (16,1,1) -- SO THE CLI MUST FIX IT. See LOCAL SIZE below.
#
# ===========================================================================
# THE FOUR WALLS, measured against the substrate rather than guessed.
#
# 1. WIDE DTYPES. `_load`/`_store`'s second arm -- a bitcast reading WIDER than
#    the buffer's storage word, assembled from `dtype.itemsize // w` words and
#    split again on the store -- is reachable only when the storage word is
#    narrower than the dtype: f16/bf16/fp8 (2 or 1 bytes) or i64/u64 (8). The v1
#    lanes are i32, u32, f32 and bool, where `w == dtype.itemsize` always, so
#    that arm is DEAD here and the four lanes take the first branch verbatim.
#    `truncate` has the same shape: dtype.py:296-297 answers float16, bfloat16,
#    the four fp8s, float64, six narrow ints and int64/uint64 through ctypes and
#    struct, and only bool/int32/uint32/float32 are pure in Bend. So CAST is
#    ported for those four and REFUSES the rest -- a 64-bit truncate has no U32
#    image and an F32 cannot hold a half. This file refuses rather than
#    emulating half a width.
#    TODO(p3) runtime/ops_python.py:18 -- the multi-word bitcast load arm.
#    TODO(p3) runtime/ops_python.py:30 -- the multi-word store arm.
#    TODO(p3) runtime/ops_python.py:135 -- `truncate` for the ten C widths.
#
# 2. TENSOR CORES. `wmma` (ops_python.py:33) needs `tcore.frag_coords()` and a
#    three-way fragment layout, and its `arg` is a `(dims, dtype_in, threads)`
#    tuple. There is no v1 spelling and no scalar lane for a fragment.
#    TODO(p3) runtime/ops_python.py:33.
#
# 3. `Ops.FDIV` AND `Ops.THREEFRY` -- see MEASURED FACT 2.
#
# 4. THE TUPLE OPERAND BRANCH. `exec_alu`'s first line (ops.py:1429) is
#    `if any(isinstance(x, tuple) for x in operands)` and it recurses per lane.
#    symbolic.bend ports only the scalar spine, so `alu1/2/3` below call the same
#    two lanes directly -- `exec_alu_i32` and `exec_alu_f32` -- and choose between
#    them the way ops.py:1432 does, by the PYTHON TYPE of the operands. That is a
#    reuse, not a re-implementation: the two lanes are ops.py:1432-1435's body.
#    The Invalid poison (ops.py:1432) has no v1 spelling, because nothing in a v1
#    packet is `CONST(Invalid)`.
#    ONE DIVERGENCE IS INHERITED, and it is named where it bites: `safe_pow`
#    (ops.py:1412) answers `inf if x > 0 else -inf` for a negative base with a
#    fractional exponent, where IEEE -- and therefore `exec_alu_f32` -- answers
#    nan. Taking IEEE over a Python-shaped branch nobody can compute is
#    symbolic.bend's call and this file does not relitigate it.
#
# ===========================================================================
# THE WIRE FORMAT, v1.1
#
# The v1 shape from the brief is kept:
#
#   line 1:  bendexec1 <nuops> <nbuffers>
#   uop:     <idx>: <op> <dtype|-> <arg|-> <src1> <src2> ...
#   buffer:  <nbytes> <hex-bytes>
#   out:     PACKET.out -- <nbuffers> lines of <nbytes> <hex-bytes>
#
# `<op>` is the bare `Ops.name` (what `Ops.name.of` answers) and `<srcN>` is a
# 1-based uop index. FOUR AMENDMENTS, each forced by a line of ops_python that
# this file ports.
#
# A1. There are no `DEFINE_*` ops (MEASURED FACT 3); the arms are `PARAM` and
#     `BUFFER` plus an AddrSpace (ops_python.py:99,105). So the brief's
#     DEFINE_GLOBAL/LOCAL/REG/VAR/BUF are spelled `PARAM`/`BUFFER` and the
#     addrspace rides in `<arg>`:
#       PARAM  k:param:<nbytes>:<g|l|r|a>
#         g binds the next packet buffer, r allocates zeros, a reads a `vals`
#         entry -- ops_python.py:94,99-105
#       BUFFER k:buffer:<nbytes>   allocates zeros and consumes NO packet buffer
#         (ops_python.py:104 allocates; only PARAM pops pbufs)
#     `nbytes` is `u.max_numel()*u.dtype.itemsize`, the size ops_python gives the
#     memoryview, and the storage word width follows from the dtype, so the
#     encoder never has to repeat it.
#     PACKET BUFFER ORDER: packet buffer i is the i-th `PARAM` of addrspace g or l
#     in uop order, because ops_python.py:104 pops `pbufs` in exactly that order.
#     A PARAM inside a RANGE loop would pop a second time in Python too, so
#     resolving the index once at parse time is the same answer.
#
# A2. `LOAD` and `STORE` need `u.max_numel()` (ops_python.py:88,137). Nothing in
#     `<op>/<dtype>/<arg>/<src>` states it, so:
#       LOAD/STORE   k:vec:<max_numel>     or `-` for a max_numel of 1
#     The measured streams need it: an elementwise add of four floats emits a
#     `LOAD` and a `STACK` and a `STORE` of max_numel 4.
#
# A3. `INDEX`/`SHRINK` need `u.src[0]`'s shape and whether `src[0]` is a BITCAST
#     (ops_python.py:115,120). The IMAGE arm is unreachable without a shape, so it
#     is a wall, and the scale is passed precomputed:
#       INDEX/SHRINK k:idx:<scale>   scale 0 means the ALU arm (ops_python.py:114)
#                                    otherwise `src[0].dtype.itemsize //
#                                    src[0].src[0].dtype.itemsize`; `-` is 1.
#     The ALU arm is the COMMON one in the measured streams: of 26 INDEX uops in
#     the elementwise-add kernel, 24 take it (INDEX over a vector LOAD) and 2 do
#     not (INDEX straight onto a PARAM).
#
# A4. `SPECIAL` carries its axis in `u.arg`, a tuple like `('l','idx',1)`
#     (ops_python.py:108-109). The bare name is enough:
#       SPECIAL     k:sp:<gidx0|gidx1|gidx2|lidx0|lidx1|lidx2>
#
# `<dtype>` is the bare dtype name ("int", "uint", "float", "bool", "weakint",
# ...), which `to_dtype` already parses. `CONST` is `c:<decimal>` for an integer
# lane and `f:<8 hex digits>` for a float lane.
#
# ===========================================================================
# LOCAL SIZE IS A v1.1 AMENDMENT TO THE COMMAND LINE, NOT THE PACKET.
#
# MEASURED FACT 4 says the engine asks for (2,1,1) ... (16,1,1), and the v1
# command line `bend-executor PACKET gx gy gz vals...` has nowhere to put a local
# size. So v1 RUNS AT local_size (1,1,1), which makes `warp` the one-element
# `[(0,0,0)]`, `warp_size` 1, every "list of warp_size" in ops_python a
# one-element list, and a `lidxK` SPECIAL the constant 0. A sibling encoder that
# wants a real local size must ADD it to the argv; until then it must launch the
# BEND device with local_size (1,1,1), and tinygrad will then emit `gidx` instead
# of `lidx`, which is what the `g` arm of ops_python.py:108 answers.
#
# The consequence for the data model is large and it is why this file is shaped
# the way it is: `values[u]` in Python is a LIST over warp_size, and at warp 1
# that list is a singleton -- so a uop's value is a RUN of arena slots (1 for a
# scalar, `max_numel` for a vector LOAD, `len(srcs)` for a STACK) and `exec_masks`
# is a `List<Bool>` rather than a list of lists.
#
# ===========================================================================
# BEND SUBSTRATE NOTES -- six rules every def below is written against, each
# measured against bend 2.0.34 with ./bin/bend rather than read off a doc.
#
# 1. `Data` FIELDS MUST BE `Data`. A `Data` record cannot hold a `List` or an
#    `Array`; both are `Type`. So a program table is NOT a field of a record: it
#    is a `List` threaded beside the arena, and a `Uop` carries only `Data`.
# 2. `match` ONLY SCRUTINEES A PARAMETER OR A FIELD. Both `match f(x):` and
#    `x = f(y)` followed by `match x:` are refused -- "a match cannot
#    scrutinize a computed value / a local binder: give it its own def". So
#    every Maybe or sum a branch needs arrives as an ARGUMENT, and the branch
#    itself is `Bool.pick` when the two arms are expressions. That is why
#    `bytes.half` takes the second nibble as a `U32` and asks `hexdig_ok`
#    instead of matching a `Maybe<&1, U32>`.
# 3. `Array.get` ANSWERS A PAIR and its index is LINEAR: `Array.get(T, a, +i) ->
#    Array<T> & T`. The pair must be destructured inside a def whose PARAMETER is
#    the pair (`take(Array.get(...))` inside `rd`), never inline at the call site.
#    `Array.set`'s index is an ordinary `U32`; `Array.new`'s depth is a `Nat`
#    (`Array.new(T, 2n, v)` is 4 slots). A bound pair may be used ONCE, so a
#    def that needs both halves must take the pair as a parameter.
# 4. `Array` AND A `type ... is Type` RECORD ARE BOTH AFFINE: ONE USE. This is
#    why the arena is reached through `take`/`give` pairs rather than read twice,
#    and why `Prog` below is nine arguments instead of one record.
# 5. OPERATORS NEED AN ANNOTATION: `i + 1` is refused, it is `(i + 1 : U32)`.
# 6. `U32.read` ANSWERS `Maybe` and reads "42" but refuses "-42" and any `k:`
#    prefix, so every `<arg>` is split by hand. A `Nat` literal is `3n`, a `U32`
#    index is `3`.
#
# ===========================================================================
# THE REMAINING WORK, and why it is not here.
#
# `run` needs the mutable machine ops_python.py:52-157 keeps in four locals: the
# `values` dict, the buffer bytearrays, `exec_masks`, and `pbufs`/`pvals`. Under
# rules 1-4 that is an arena threaded through a fuel recursion, and the two
# remaining hard parts are named so they are not rediscovered:
#
#   * THE PC IS A LOOP, NOT A RECURSION. Python is `while i < len(self.uops)`
#     with `BACKEDGE`/`END`/`RANGE` writing `i`. Bend has no loop and no
#     `continue`, so `run` must be `run(fuel: Nat, ...)` with the PC threaded and
#     a DIE on fuel exhaustion -- which is also the "stay turing-incomplete"
#     answer, since a RANGE-driven kernel has no static step bound.
#   * THE ARENA MUST BE STRIDED, NOT BUMP-ALLOCATED. Python's `values` is keyed
#     by UOp, so a RANGE body overwrites exactly the entries the first pass
#     wrote (ops_python.py:125-127 increments `values[u]` in place, and :129
#     `del`s it). A bump allocator would append afresh on the second pass and
#     the loop would read its own history, so uop `i` must own a FIXED slot run
#     and a re-executed uop must land back on it.
# TODO(p3) runtime/ops_python.py:52 -- the interpreter loop.
#
# ONE KNOWN WRONG ANSWER, and it is measured rather than argued. `alu1(SQRT, ...)`
# over an ELEMENT whose dtype is int32 answers 456459507 where Python's
# `python_alu[Ops.SQRT](16)` is `math.sqrt(16)` = 4.0 (1082130432). The row is
# in .agents/slop/exec_gate.bend, printed as KNOWN-FAIL so it cannot be mistaken
# for a pass. `op_is_mathy` sends SQRT to the float lane and `f_of` reads the
# 16 as 16.0, so the fault is inside the lane input, not the lane choice.
# TODO(p3) runtime/ops_python.py:138 -- the float lane's input for an int dtype.

import Base
import ../helpers.bend as H
import ../LAWS/spec.bend as S
import ../dtype.bend as D
import ../uop/ops.bend as O
import ../uop/symbolic.bend as SY

# ===========================================================================
# F32 AND U32 SHARE A WORD. Bend reads an F32's bits with `F32.bits` and the
# constructor takes the Word payload, so both directions are pure. dtype.c calls
# the pair of them "the conversion seam"; the seam exists only because those
# helpers go through half and fp8, and v1 has neither.
#
# MEASURED: `F32{w32(1065353216)}` prints `1`, so the payload really is the
# pattern and `f32_of`/`F32.bits` are inverses.
# ===========================================================================

def w32(+u: U32) -> Word(32n):
  match u:
    case U32{data}: data

def f32_of(+u: U32) -> F32: F32{w32(u)}

# ===========================================================================
# THE VALUE DOMAIN. `values[u]` in Python is a list over `warp_size` whose
# elements are an int, a float, a memoryview or a `(memoryview, offset)` tuple,
# and for a vector LOAD or a STACK a list of such lists. At warp 1 (see LOCAL
# SIZE) the outer list is one element, so a uop's value is a RUN of elements.
#
# `S.Dt` travels with a scalar because Python's int/float distinction is what
# picks `exec_alu`'s lane AND what makes CAST sign-aware: ops_python.py:133 reads
# the SOURCE dtype, and a uint32 and an int32 hold the same 32 bits.
# ===========================================================================

type Elem is Data:
  # A scalar. `b` is the storage bit pattern, `d` the dtype it is read at.
  Sc{b: U32, d: S.Dt}
  # A bare memoryview -- what PARAM and BUFFER bind (ops_python.py:105).
  Bf{b: U32}
  # The `(memoryview, offset)` tuple INDEX and SHRINK build. `n` is
  # `offset is None`, which ops_python.py:19 turns into a 0.0 load.
  Rf{b: U32, o: U32, n: Bool}

def Elem.bits(+e: Elem) -> U32:
  match e:
    case Sc{b, d}: b
    case _: 0

def Elem.dt(+e: Elem) -> S.Dt:
  match e:
    case Sc{b, d}: d
    case _: S.void()

def Elem.is_scalar(+e: Elem) -> Bool:
  match e:
    case Sc{b, d}: True{}
    case _: False{}

# The `(buffer, offset)` of an element, with a bare memoryview reading as offset
# zero. ops_python.py:19/28 branch on `i is None` and :121 on
# `isinstance(m, tuple)`, so both spellings have to meet in one place.

def Elem.buf(+e: Elem) -> U32:
  match e:
    case Bf{b}: b
    case Rf{b, o, n}: b
    case _: 0

def Elem.off(+e: Elem) -> U32:
  match e:
    case Rf{b, o, n}: o
    case _: 0

def Elem.off_none(+e: Elem) -> Bool:
  match e:
    case Rf{b, o, n}: n
    case _: False{}

# ===========================================================================
# PACKET TEXT. `<nbytes> <hex-bytes>`, either case, two digits per byte, and the
# uop line's `<idx>:` field with its colon.
#
# `U32.read` answers `Maybe` and reads "42" but refuses "-42" (rule 6), so
# `num` treats "-" as 0 and every `<arg>` is split by hand.
# ===========================================================================

def is_hspace(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 32), Bool.or(U32.is_eq(c, 9), U32.is_eq(c, 13)))

# `str.split()` on a run of spaces, which is `String.split` plus the empty fields
# it leaves behind. `List.filter` is the filter, so the words come back in order
# and no accumulator is reversed.
def sp() -> Char: Char.from_u32(32)

def keep_word(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def words(s: String) -> List<&2, String>:
  List.filter(~String, ~keep_word, String.split(String.trim(s), sp()))

def word_at(+i: U32, ws: List<&2, String>) -> Maybe<&2, String>:
  List.get(&2, String, ws, U32.to_nat(i))

def str_of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: "-"

def num(s: String) -> Maybe<&2, U32>:
  U32.read(s)

def num_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

# word k of a line, `-` when the line is shorter -- which is also what a `-` arg
# is, so the two agree and no line can run off the end of its own words. It sits
# here with the rest of the packet text because `<arg>` (below) is its first user
# and every fold that reads a line reads it through it.
def w(+ws: List<&2, String>, +k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ws, k), "-")

# `hexdig` answers a Maybe through `Bool.pick`, and `hexdig_ok`/`hexdig_val` are
# the same table as the two tests a caller wants when it cannot match (rule 2).
def hexdig_is_digit(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57))

def hexdig_is_lower(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102))

def hexdig_is_upper(+c: U32) -> Bool: Bool.and(U32.is_ge(c, 65), U32.is_le(c, 70))

def hexdig_ok(+c: U32) -> Bool:
  Bool.or(hexdig_is_digit(c), Bool.or(hexdig_is_lower(c), hexdig_is_upper(c)))

def hexdig_val(+c: U32) -> U32:
  Bool.pick(U32, hexdig_is_digit(c), U32.sub(c, 48),
    Bool.pick(U32, hexdig_is_lower(c), U32.sub(c, 87), U32.sub(c, 55)))

def hexdig(+c: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, hexdig_ok(c), Some{hexdig_val(c)}, None{})

def hexdig_str(+v: U32) -> String:
  Bool.pick(String, U32.is_lt(v, 16), String.from_list([Char.from_u32(48), Char.from_u32(v)]),
    String.from_list([Char.from_u32(48), Char.from_u32(55)]))

def hex_str2(+v: U32) -> String:
  String.concat([hexdig_str(U32.div(v, 16)), hexdig_str(U32.mod(v, 16))])

# `<hex-bytes>` as a list of byte values, most significant nibble first. The
# answer is `(ok, bytes)` rather than a `Maybe` because a `Maybe` around a
# `List` costs two lifetime dances (the list inside a `Some` is a DIFFERENT
# lifetime from the one the caller asked for) and a malformed packet is a
# boolean, not a type.
#
# It is ONE self-recursive def -- Bend refuses mutual recursion -- so the fold
# carries the half-byte itself: `pend` is the high nibble waiting for its low one
# and `live` says there is one. A bad nibble clears `ok` and the walk keeps going,
# since it is a fixed number of characters either way. The accumulator prepends,
# so the characters are walked in REVERSE (`String.reverse`) and the bytes come
# out in order.
def bytes.fin(+ok: Bool, +live: Bool, acc: List<U32>) -> (Bool & List<U32>):
  match live:
    case True{}: (False{}, acc)
    case False{}: (ok, acc)

def bytes.acc(+ok: Bool, +c: U32, +pend: U32, acc: List<U32>) -> List<U32>:
  match ok:
    case True{}: U32.add(U32.mul(hexdig_val(pend), 16), hexdig_val(c)) <> acc
    case False{}: acc

def bytes.go(cs: List<Char>, acc: List<U32>, +ok: Bool, +pend: U32, +live: Bool) ->
  (Bool & List<U32>):
  match cs live:
    case Nil{} _: bytes.fin(ok, live, acc)
    case h <> t True{}:
      +c = Char.to_u32(h)
      +k = hexdig_ok(c)
      bytes.go(t, bytes.acc(k, c, pend, acc), Bool.and(ok, k), 0, False{})
    case h <> t False{}:
      bytes.go(t, acc, ok, Char.to_u32(h), True{})


# The caller reverses the string and hands over the characters: `String.to_list`
# answers a list one lifetime DEEPER than a `String` parameter, and taking the
# characters as a parameter of their own is what keeps the fold's type free of
# that dance.
def bytes_of(cs: List<Char>) -> (Bool & List<U32>):
  bytes.go(cs, Nil{}, True{}, 0, False{})


def bytes_ok(r: (Bool & List<U32>)) -> Bool:
  (ok, bs) = r
  ok

def list_of(r: (Bool & List<U32>)) -> List<U32>:
  (ok, bs) = r
  bs

# ===========================================================================
# THE OP TABLE. A wire name to an `O.Op`, and nothing for a name this file does
# not port -- which is how every wall above reaches a refusal rather than a
# guess.
# ===========================================================================

def op_of(nm: String) -> Maybe<&1, O.Op>:
  match nm:
    case "PARAM": Some{O.OpsPARAM{}}
    case "BUFFER": Some{O.OpsBUFFER{}}
    case "CONST": Some{O.OpsCONST{}}
    case "CAST": Some{O.OpsCAST{}}
    case "BITCAST": Some{O.OpsBITCAST{}}
    case "SPECIAL": Some{O.OpsSPECIAL{}}
    case "INDEX": Some{O.OpsINDEX{}}
    case "SHRINK": Some{O.OpsSHRINK{}}
    case "LOAD": Some{O.OpsLOAD{}}
    case "STORE": Some{O.OpsSTORE{}}
    case "STACK": Some{O.OpsSTACK{}}
    case "AFTER": Some{O.OpsAFTER{}}
    case "RANGE": Some{O.OpsRANGE{}}
    case "BACKEDGE": Some{O.OpsBACKEDGE{}}
    case "END": Some{O.OpsEND{}}
    case "IF": Some{O.OpsIF{}}
    case "ENDIF": Some{O.OpsENDIF{}}
    case "BARRIER": Some{O.OpsBARRIER{}}
    case "SINK": Some{O.OpsSINK{}}
    case "NOOP": Some{O.OpsNOOP{}}
    case "GROUP": Some{O.OpsGROUP{}}
    case "ADD": Some{O.OpsADD{}}
    case "SUB": Some{O.OpsSUB{}}
    case "MUL": Some{O.OpsMUL{}}
    case "MAX": Some{O.OpsMAX{}}
    case "MULACC": Some{O.OpsMULACC{}}
    case "NEG": Some{O.OpsNEG{}}
    case "AND": Some{O.OpsAND{}}
    case "OR": Some{O.OpsOR{}}
    case "XOR": Some{O.OpsXOR{}}
    case "SHL": Some{O.OpsSHL{}}
    case "SHR": Some{O.OpsSHR{}}
    case "CMPLT": Some{O.OpsCMPLT{}}
    case "CMPEQ": Some{O.OpsCMPEQ{}}
    case "CMPNE": Some{O.OpsCMPNE{}}
    case "CDIV": Some{O.OpsCDIV{}}
    case "CMOD": Some{O.OpsCMOD{}}
    case "FLOORDIV": Some{O.OpsFLOORDIV{}}
    case "FLOORMOD": Some{O.OpsFLOORMOD{}}
    case "LOG2": Some{O.OpsLOG2{}}
    case "EXP2": Some{O.OpsEXP2{}}
    case "SQRT": Some{O.OpsSQRT{}}
    case "RECIPROCAL": Some{O.OpsRECIPROCAL{}}
    case "SIN": Some{O.OpsSIN{}}
    case "POW": Some{O.OpsPOW{}}
    case "TRUNC": Some{O.OpsTRUNC{}}
    case "WHERE": Some{O.OpsWHERE{}}
    case _: None{}

# ===========================================================================
# THE ALU LANE. `exec_alu` -- ops.py:1427 -- with the tuple branch (WALL 4) and
# the Invalid poison left out, and the two numeric lanes REUSED from
# symbolic.bend.
#
# THE LANE FOLLOWS THE PYTHON TYPE OF THE OPERANDS, which is why `is_f` reads the
# ELEMENT and not the uop dtype: a CONST's weakint is a Python int and a LOAD's
# float is a Python float, and `1 + 2.5` is a float in Python (ops.py:1425's
# comment on the lane, restated at symbolic.bend:822).
#
# `Elem <-> O.Const` is three constructors and nothing else, so the reuse is
# lossless: `Sc` IS `O.Const`'s payload with a dtype attached.
# ===========================================================================

# A zero-extended 64-bit reading for a uint32, a sign-extended one for an int32:
# `from_storage_scalar` (ops_python.py:18) leaves exactly this difference between
# a `memoryview.cast('I')` and a `cast('i')`.
def ex_i64_of(+uns: Bool, +b: U32) -> H.I64:
  Bool.pick(H.I64, uns, H.i64_of_hi_lo(0, b), H.i64_of_i32(b))

def elem_c.dt(+d: S.Dt, +b: U32) -> O.Const:
  Bool.pick(O.Const, S.Dt.is_float(d), O.CFloat{f32_of(b)},
    Bool.pick(O.Const, S.Dt.is_bool(d), O.CBool{U32.is_ne(b, 0)},
      O.CInt{ex_i64_of(S.Dt.is_unsigned(d), b)}))

def is_f(+e: Elem) -> Bool:
  match e:
    case Sc{b, d}: S.Dt.is_float(d)
    case _: False{}

def elem_c(+e: Elem) -> O.Const:
  match e:
    case Sc{b, d}: elem_c.dt(d, b)
    case _: O.CInvalid{}

def bits_of(+c: O.Const) -> U32:
  match c:
    case O.CInt{i}: H.lo32(i)
    case O.CFloat{f}: F32.bits(f)
    case O.CBool{b}: Bool.to_u32(b)
    case _: 0

def elem_of(+b: U32, d: S.Dt) -> Elem: Sc{b, d}

def got(c: Maybe<&1, O.Const>, d: S.Dt) -> Elem:
  match c:
    case Some{v}: elem_of(bits_of(v), d)
    case None{}: elem_of(0, d)

# `python_alu` (ops.py:1417-1424) is a PYTHON-NUMBER table, so the ops whose
# result is a float whatever the operand type are the float lane always, and the
# rest follow the operands. LOG2/EXP2/SQRT/RECIPROCAL/SIN are `math.*` lambdas
# that return a float for an int argument, and POW is `safe_pow`.
def op_is_mathy(op: O.Op) -> Bool:
  O.op_in([O.OpsLOG2{}, O.OpsEXP2{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsSIN{},
    O.OpsPOW{}], op)

# `ops_python.py:126-127` increments `values[u][j]`, and :129 compares against
# `src_values[0][0]`, so the RANGE counter is the uop's OWN value and not a
# separate register. At warp 1 that is one U32 in the uop's arena run.
def b_of(+e: Elem) -> U32:
  match e:
    case Sc{b, d}: b
    case _: 0

# THE LANE INPUT IS A VALUE, NOT A BIT PATTERN. ops.py:1425 picks the lane from
# the PYTHON TYPE of the operand, so an int32 operand reaches `math.sqrt` as the
# NUMBER 16 -- and `U32.to_f32(16)` is 16.0 while `f32_of(16)` is the denormal
# whose bit pattern happens to be 16. MEASURED, and this is exec_gate's
# KNOWN-FAIL row: `alu1f(SQRT, single, Sc{16, int32})` answered 456459507 with
# `f32_of` and answers F32.bits(F32.sqrt(16.0)) = 1082130432 with this one. A
# float operand keeps the bit reading (`F32{b}` IS the value it was stored as),
# an int is read as a signed or unsigned integer, and `2^32 - b` has no U32
# spelling -- so the magnitude is `0 - b`, which wraps to exactly that.
def f32_i32(+b: U32) -> F32:
  Bool.pick(F32, U32.is_ge(b, 2147483648), F32.neg(U32.to_f32(U32.sub(0, b))), U32.to_f32(b))

def f_of.dt(+d: S.Dt, +b: U32) -> F32:
  Bool.pick(F32, S.Dt.is_float(d), f32_of(b),
    Bool.pick(F32, S.Dt.is_unsigned(d), U32.to_f32(b), f32_i32(b)))

def f_of(+e: Elem) -> F32:
  match e:
    case Sc{b, d}: f_of.dt(d, b)
    case _: 0.0

def ci_of(+e: Elem) -> U32: b_of(e)

def cf_of(+e: Elem) -> F32: f_of(e)

# THE LANE CALLS. `SY.exec_alu_i32` and `SY.exec_alu_f32` are called verbatim --
# they ARE ops.py:1432-1435's body, and reusing them is the point.
#
# WHY NOT `SY.exec_alu1/2/3`, which wrap the same two lanes with a selector? MEASURED:
# `symbolic.bend`'s `ci_fits` (symbolic.bend:840) is wired to `i64_big`
# (symbolic.bend:831), which asks "does NOT fit an i32" -- and `exec_alu.of2`
# (symbolic.bend:928) reads it as "fits", so the INTEGER lane is skipped for every
# small value. Measured: `SY.exec_alu2(Ops.MUL, int32, [CInt(6), CInt(7)])` answers
# `None{}`, and so has no `MUL` for an int at all. A fold that never fires is a
# safe fold; a DEVICE that answers `None{}` is a wrong device, so the two lanes
# are called directly and the selector -- the only part that differs from a fold --
# is the six defs below. symbolic.bend is read-only for this file, so the
# inversion is REPORTED, not fixed here.

def alu1i(+op: O.Op, +dt: S.Dt, +a: Elem) -> Elem:
  got(SY.exec_alu_i32(S.Dt.is_unsigned(dt), op, SY.I3{1, ci_of(a), 0, 0}), dt)

def alu1f(+op: O.Op, +dt: S.Dt, +a: Elem) -> Elem:
  got(SY.exec_alu_f32(op, 1, cf_of(a), 0.0, 0.0), dt)

def alu1(+op: O.Op, +dt: S.Dt, +a: Elem) -> Elem:
  Bool.pick(Elem, Bool.or(op_is_mathy(op), is_f(a)), alu1f(op, dt, a), alu1i(op, dt, a))




def alu2i(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem) -> Elem:
  got(SY.exec_alu_i32(S.Dt.is_unsigned(dt), op, SY.I3{2, ci_of(a), ci_of(b), 0}), dt)

def alu2f(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem) -> Elem:
  got(SY.exec_alu_f32(op, 2, cf_of(a), cf_of(b), 0.0), dt)

def alu2(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem) -> Elem:
  Bool.pick(Elem, Bool.or(op_is_mathy(op), Bool.or(is_f(a), is_f(b))),
    alu2f(op, dt, a, b), alu2i(op, dt, a, b))




def alu3i(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem, +c: Elem) -> Elem:
  got(SY.exec_alu_i32(S.Dt.is_unsigned(dt), op, SY.I3{3, ci_of(a), ci_of(b), ci_of(c)}), dt)

def alu3f(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem, +c: Elem) -> Elem:
  got(SY.exec_alu_f32(op, 3, cf_of(a), cf_of(b), cf_of(c)), dt)

def alu3(+op: O.Op, +dt: S.Dt, +a: Elem, +b: Elem, +c: Elem) -> Elem:
  Bool.pick(Elem, Bool.or(op_is_mathy(op), Bool.or(is_f(a), Bool.or(is_f(b), is_f(c)))),
    alu3f(op, dt, a, b, c), alu3i(op, dt, a, b, c))




# ===========================================================================
# THE PROGRAM TABLE. `self.uops` and `values` from ops_python, kept apart
# because they behave differently. The uop list is READ-ONLY for a whole launch
# -- a `List<&2, Uop>` is Data, so every lookup is free and copies nothing --
# while the values arena is a REBOUND list: `List.set` copies only the path it
# rebuilds, which is what keeps an assignment affordable.
#
# THE STRIDE IS FIXED AT PARSE TIME, which is what THE REMAINING WORK's second
# requirement was about. ops_python's `values` is keyed by UOp, so a RANGE body
# overwrites exactly the entries the first pass wrote and a bump allocator would
# let the second pass read its own history. So uop i owns the FIXED slot run
# `slot_i .. slot_i + run_i - 1`, assigned in uop order, and a re-executed uop
# lands back on its own slots.
#
# MEASURED over the 25 gate packets (1310 uops; .agents/slop/x-shape.py): every
# run is 1 except LOAD (its `k:vec:` count) and STACK (its src count, max 4). A
# vector LOAD's value in Python is `[[v]]*load_sz` -- a run of warp-runs -- and
# at warp 1 (see LOCAL SIZE) every inner run is length 1, so the FLAT run is
# `load_sz` and each consumer below reads it flat. The one shape that breaks
# that flattening is a LOAD whose pointer src is itself a run of several (a
# gather): measured none in 117 LOADs, longest pointer run 1. That is WALL 5.
# ===========================================================================

# `<arg>` decoded into a KIND and two numbers. The letters of A1 become kinds
# rather than a field, so the walk reads one number: 2/3 are a PARAM of addrspace
# g/l (which binds the next packet buffer), 4 is addrspace r and 5 is a BUFFER
# (both `bytearray` scratch), 6 is addrspace a (a `vals` entry), 8 is an
# INDEX/SHRINK scale and 9 a LOAD/STORE lane count -- the last two land in `run`
# at parse time and are never read again. 14 and 15 are the two refusals: a
# dtype or an op name this file does not port.
type Uop is Data:
  Uop{op: O.Op, dt: S.Dt, kind: U32, a: U32, b: U32, slot: U32, run: U32, srcs: List<&2, U32>}

def Uop.op(+u: Uop) -> O.Op:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: op

def Uop.dt(+u: Uop) -> S.Dt:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: dt

def Uop.kind(+u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: kind

def Uop.a(+u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: a

def Uop.b(+u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: b

def Uop.slot(+u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: slot

def Uop.run(+u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: run

def Uop.srcs(+u: Uop) -> List<&2, U32>:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, srcs}: srcs

# the k-th src, 0-based. A src past the four a packet may carry (measured max 4,
# and only a STACK gets near it) is refused at PARSE time, so the default of 0
# is only ever uop 0's index.
def Uop.nth(ss: List<&2, U32>, +k: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ss, k), 0)

def Uop.src0(+u: Uop) -> U32: Uop.nth(Uop.srcs(u), 0n)

def Uop.src1(+u: Uop) -> U32: Uop.nth(Uop.srcs(u), 1n)

def Uop.nsrc(+u: Uop) -> U32: U32.from_nat(List.length(&2, U32, Uop.srcs(u)))

# the lookup, with the countdown as a second scrutinee because a match takes
# only one: the list walks, the index counts down, and a walk off the end is None.
def Uop.at.go(us: List<&2, Uop>, +i: Nat) -> Maybe<&2, Uop>:
  match us i:
    case Nil{} _ : None{}
    case h <> t 0n: Some{h}
    case _ <> t 1n+p: Uop.at.go(t, p)

# THE BOTTOM is reached only by a packet whose own index count disagrees with
# its lines. It is a SINK, so a walk that reached it would advance the pc and
# run out of fuel -- a loud refusal, never a silent answer.
def Uop.bottom() -> Uop: Uop{O.OpsSINK{}, S.void(), 0, 0, 0, 0, 1, Nil{}}

def Uop.at(us: List<&2, Uop>, +i: U32) -> Uop:
  Maybe.default(&2, Uop, Uop.at.go(us, U32.to_nat(i)), Uop.bottom())

def Uop.of(+u: Uop, op: O.Op) -> Uop:
  Uop{op, Uop.dt(u), Uop.kind(u), Uop.a(u), Uop.b(u), Uop.slot(u), Uop.run(u), Uop.srcs(u)}

def Uop.dt1(+u: Uop, dt: S.Dt) -> Uop:
  Uop{Uop.op(u), dt, Uop.kind(u), Uop.a(u), Uop.b(u), Uop.slot(u), Uop.run(u), Uop.srcs(u)}

def Uop.ak(+u: Uop, +k: U32, +a: U32, +b: U32) -> Uop:
  Uop{Uop.op(u), Uop.dt(u), k, a, b, Uop.slot(u), Uop.run(u), Uop.srcs(u)}

def Uop.slot1(+u: Uop, +slot: U32, +b: U32) -> Uop:
  Uop{Uop.op(u), Uop.dt(u), Uop.kind(u), Uop.a(u), b, slot, Uop.run(u), Uop.srcs(u)}

def Uop.add(+u: Uop, +s: U32) -> Uop:
  Uop{Uop.op(u), Uop.dt(u), Uop.kind(u), Uop.a(u), Uop.b(u), Uop.slot(u), Uop.run(u),
      List.append(&2, U32, Uop.srcs(u), [s])}

def Uop.run2(+u: Uop, +run: U32) -> Uop:
  Uop{Uop.op(u), Uop.dt(u), Uop.kind(u), Uop.a(u), Uop.b(u), Uop.slot(u), run, Uop.srcs(u)}

# MEASURED: a STACK's run is its src count and a LOAD's is its lane count
# (`k:vec:`), and every other op's is 1 -- which is the scalar case ops_python
# has too, since a `-` arg is what a LOAD with `max_numel() == 1` writes.
def Uop.run_of.op(+op: O.Op, +u: Uop) -> U32:
  Bool.pick(U32, O.eq_op(op, O.OpsSTACK{}), Uop.nsrc(u),
    Bool.pick(U32, O.eq_op(op, O.OpsLOAD{}), Uop.a(u), 1))

def Uop.run_of(+u: Uop) -> U32: Uop.run_of.op(Uop.op(u), u)

def Uop.run1(+u: Uop) -> Uop: Uop.run2(u, Uop.run_of(u))

# ===========================================================================
# THE BUFFERS. The store is ONE flat byte list holding every buffer back to
# back, so a buffer is a base offset into it. `w` is the storage word in bytes
# -- `storage_fmt_for_dtype` (ops_python.py:96), 1 for bool and 4 for the other
# three -- and `e` the element count, so `_step` and the bounds check are the
# arithmetic ops_python does on `m.nbytes // len(m)`.
# ===========================================================================

type Buf is Data:
  Buf{base: U32, w: U32, e: U32}

def Buf.base(+f: Buf) -> U32:
  match f:
    case Buf{base, w, e}: base

def Buf.w(+f: Buf) -> U32:
  match f:
    case Buf{base, w, e}: w

def Buf.e(+f: Buf) -> U32:
  match f:
    case Buf{base, w, e}: e

def Buf.at(fs: List<&2, Buf>, +b: U32) -> Buf:
  Maybe.default(&2, Buf, List.get(&2, Buf, fs, U32.to_nat(b)), Buf{0, 4, 0})

def Buf.make(+w: U32, +n: U32) -> Buf: Buf{0, w, U32.div(n, w)}

# ===========================================================================
# THE VALUES ARENA AND THE STORE. `Val` is ops_python's `values[u]`, total and
# defaulting to a zero: the one slot that is legitimately unwritten is a RANGE
# counter, which ops_python initialises to 0 on its first visit.
# ===========================================================================

def Elem.zero() -> Elem: Sc{0, S.int32()}

def Elem.is_true(+e: Elem) -> Bool: Bool.and(Elem.is_scalar(e), U32.is_ne(Elem.bits(e), 0))

def Val.at(vs: List<&2, Elem>, +i: U32) -> Elem:
  Maybe.default(&2, Elem, List.get(&2, Elem, vs, U32.to_nat(i)), Elem.zero())

def Val.put(vs: List<&2, Elem>, +i: U32, +e: Elem) -> List<&2, Elem>:
  List.set(&2, Elem, vs, U32.to_nat(i), e)

def Mem.byte(ms: List<&2, U32>, +at: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ms, U32.to_nat(at)), 0)

def Mem.put(ms: List<&2, U32>, +at: U32, +v: U32) -> List<&2, U32>:
  List.set(&2, U32, ms, U32.to_nat(at), v)

# ===========================================================================
# THE STORE IS LITTLE-ENDIAN. `memoryview(bytearray).cast('I')` is NATIVE order
# and every platform this runs on is little-endian, so a word's four bytes are
# assembled low byte first; a 1-byte word (bool) is the byte itself.
# ===========================================================================

def Mem.ld4.go(+ms: List<&2, U32>, +n: Nat, +at: U32, +sh: Nat, +acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: Mem.ld4.go(ms, p, U32.add(at, 1), Nat.add(sh, 8n),
      U32.or(acc, U32.shln(Mem.byte(ms, at), sh)))


def Mem.ld4(ms: List<&2, U32>, +at: U32) -> U32: Mem.ld4.go(ms, 4n, at, 0n, 0)

def Mem.ld(+ms: List<&2, U32>, +at: U32, +w: U32) -> U32:
  Bool.pick(U32, U32.is_eq(w, 1), Mem.byte(ms, at), Mem.ld4(ms, at))

def Mem.st4.go(+n: Nat, +ms: List<&2, U32>, +at: U32, +sh: Nat, +v: U32) -> List<&2, U32>:
  match n:
    case 0n: ms
    case 1n+p: Mem.st4.go(p, Mem.put(ms, at, U32.and(U32.shrn(v, sh), 255)),
      U32.add(at, 1), Nat.add(sh, 8n), v)


def Mem.st4(ms: List<&2, U32>, +at: U32, +v: U32) -> List<&2, U32>: Mem.st4.go(4n, ms, at, 0n, v)

def Mem.st(+ms: List<&2, U32>, +at: U32, +w: U32, +v: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(w, 1), Mem.put(ms, at, Bool.to_u32(U32.is_ne(v, 0))),
    Mem.st4(ms, at, v))

# ===========================================================================
# `<arg>`, BY ITS WIRE SPELLING. `String.split` on ':' gives the head and up to
# three fields, and a String is affine so each field is read exactly once --
# which is why every dispatch below is a `match` on a parameter rather than a
# Bool.pick over `String.eq`.
# ===========================================================================

type Arg is Data:
  Arg{kind: U32, x: U32, y: U32}

def Arg.put(+k: U32, m: Maybe<&2, U32>) -> Maybe<&2, Arg>:
  match m:
    case Some{v}: Some{Arg{k, v, 0}}
    case None{}: None{}

def Arg.dec4(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case Some{v}: Some{U32.sub(0, v)}
    case None{}: None{}

def Arg.dec3(+ps: List<&2, String>, +neg: Bool) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, neg, Arg.dec4(num(w(ps, 1n))), num(w(ps, 0n)))

def Arg.dec2(+ps: List<&2, String>) -> Maybe<&2, U32>:
  Arg.dec3(ps, U32.is_eq(2, U32.from_nat(List.length(&2, String, ps))))

def Arg.dec(s: String) -> Maybe<&2, U32>: Arg.dec2(String.split(s, Char.from_u32(45)))

# The fold carries the accumulator rather than shifting on the way out, and the
# nibble test is a leaf rather than a Bool.pick inside an arm: a SELF-recursive
# def may not name a later def, so anything it calls has to be above it.
def Arg.hex.d(+h: Char, +acc: U32) -> U32:
  Bool.pick(U32, hexdig_ok(Char.to_u32(h)),
    U32.add(U32.shln(acc, 4n), hexdig_val(Char.to_u32(h))), acc)

def Arg.hex.go(+cs: List<&2, Char>, +n: Nat, +acc: U32) -> Maybe<&2, U32>:
  match cs n:
    case Nil{} _ : Some{acc}
    case h <> t 0n: Arg.hex.go(t, 1n, Arg.hex.d(h, acc))
    case h <> t 1n+p: Arg.hex.go(t, p, Arg.hex.d(h, acc))

def Arg.hex(s: String) -> Maybe<&2, U32>: Arg.hex.go(String.to_list(s), 0n, 0)

def Arg.letter.of(+c: U32, +v: U32) -> Maybe<&2, Arg>:
  Bool.pick(Maybe<&2, Arg>, U32.is_lt(c, 3), Some{Arg{U32.add(2, c), v, 0}},
    Bool.pick(Maybe<&2, Arg>, U32.is_eq(c, 3), Some{Arg{6, v, 0}}, None{}))

def Arg.letter(l: String) -> U32:
  match l:
    case "g": 0
    case "l": 1
    case "r": 2
    case "a": 3
    case _: 4

def Arg.param2(l: String, m: Maybe<&2, U32>) -> Maybe<&2, Arg>:
  match m:
    case Some{v}: Arg.letter.of(Arg.letter(l), v)
    case None{}: None{}

def Arg.param(n: String, l: String) -> Maybe<&2, Arg>: Arg.param2(l, num(n))

def Arg.sp(nm: String) -> String:
  match nm:
    case "gidx0": "0"
    case "gidx1": "1"
    case "gidx2": "2"
    case "lidx0": "3"
    case "lidx1": "4"
    case "lidx2": "5"
    case _: "9"

def Arg.k(h1: String, h2: String, h3: String) -> Maybe<&2, Arg>:
  match h1:
    case "param": Arg.param(h2, h3)
    case "buffer": Arg.put(5, num(h2))
    case "vec": Arg.put(9, num(h2))
    case "idx": Arg.put(8, num(h2))
    case "sp": Arg.put(7, num(Arg.sp(h2)))
    case _: None{}

def Arg.of3(h0: String, h1: String, h2: String, h3: String) -> Maybe<&2, Arg>:
  match h0:
    case "c": Arg.put(1, Arg.dec(h1))
    case "f": Arg.put(1, Arg.hex(h1))
    case "k": Arg.k(h1, h2, h3)
    case _: Some{Arg{0, 0, 0}}

def Arg.of2(+ps: List<&2, String>) -> Maybe<&2, Arg>:
  Arg.of3(w(ps, 0n), w(ps, 1n), w(ps, 2n), w(ps, 3n))

def Arg.of(a: String) -> Maybe<&2, Arg>: Arg.of2(String.split(a, Char.from_u32(58)))


# ===========================================================================
# THE PARSE. One fold over `String.lines`, because that is the only order the
# wire has: the header, then the uops, then the buffers. The fold carries a
# `Build` -- the uops reversed, the packet bytes reversed, the two buffer tables
# in buffer-id order, the running slot, and `ok`.
#
# `ok` rather than a refusal at each step, because a fold cannot carry a
# `Maybe` and a malformed packet IS a boolean (the same reason `bytes_of` answers
# a pair). The IO layer turns it into the die, naming the count that disagreed.
# ===========================================================================

type Build is Data:
  Build{us: List<&2, Uop>, sp: List<&2, Buf>, ss: List<&2, Buf>, bp: List<&2, U32>,
        nu: U32, nb: U32, nbp: U32, sbn: U32, pn: U32, slot: U32, ok: Bool}

def Build.blank() -> Build: Build{Nil{}, Nil{}, Nil{}, Nil{}, 0, 0, 0, 0, 0, 0, True{}}

# what a parsed packet is: the program, its buffers, the store, and the zeroed
# arena. No grid and no `vals` -- those are per launch, so they arrive later.
type Load is Data:
  Load{us: List<&2, Uop>, fs: List<&2, Buf>, ms: List<&2, U32>, v0: List<&2, Elem>,
       n: U32, nb: U32}

def Prog.bases.next(+f: Buf, +at: U32) -> U32: U32.add(at, U32.mul(Buf.w(f), Buf.e(f)))

def Prog.bases.put(+fs: List<&2, Buf>, +at: U32) -> List<&2, Buf>:
  match fs:
    case Nil{}: Nil{}
    case f <> t: List.append(&2, Buf, Prog.bases.put(t, Prog.bases.next(f, at)),
      [Buf{at, Buf.w(f), Buf.e(f)}])

def Prog.bases.ss(+fs: List<&2, Buf>, +at: U32) -> List<&2, Buf>:
  Prog.bases.put(fs, at)
def Prog.bases.total(+fs: List<&2, Buf>, +at: U32) -> U32:
  match fs:
    case Nil{}: at
    case f <> t: Prog.bases.total(t, Prog.bases.next(f, at))

# A `Build` field is readable as `b.x` inside a record literal but not as an
# ARGUMENT, so the fields the parse hands to another def have accessors. The
# defs are laid out by hand because Bend refuses a forward reference, and a
# topological sort of this file keeps moving them.
def Build.us(+b: Build) -> List<&2, Uop>:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: us

def Build.ok(+b: Build) -> Bool:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: ok

def Build.slot(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: slot

def Build.nu(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: nu

def Build.nb(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: nb

def Build.bp(+b: Build) -> List<&2, U32>:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: bp

def Build.sp(+b: Build) -> List<&2, Buf>:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: sp

def Build.ss(+b: Build) -> List<&2, Buf>:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: ss
def Prog.bases(+b: Build) -> List<&2, Buf>:
  Prog.bases.ss(Build.ss(b), Prog.bases.total(Build.sp(b), 0))
def Prog.bases.sp(+fs: List<&2, Buf>, +at: U32) -> List<&2, Buf>:
  Prog.bases.put(fs, at)

def Prog.pad(+n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: Prog.pad(p, 0 <> acc)

def Prog.zeros(+fs: List<&2, Buf>, acc: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: Prog.zeros(t, Prog.pad(U32.to_nat(Buf.e(f)), acc))

# THE STORE: the packet's bytes in packet order, then `nbytes` zeros for each
# scratch buffer (ops_python.py:101,104 allocate `bytearray(n)`, and two scratch
# buffers must not share bytes). The zeros' order inside their region is not
# observable -- they are all zero -- so they are prepended, which is the cheap
# direction.
def Prog.bytes(+b: Build, fs: List<&2, Buf>) -> List<&2, U32>:
  Prog.zeros(List.drop(&2, Buf, fs, U32.to_nat(Build.nb(b))),
    List.reverse(&2, U32, Build.bp(b)))

def Prog.load.put(+b: Build, us: List<&2, Uop>, +fs: List<&2, Buf>) -> Load:
  Load{us, fs, Prog.bytes(b, fs), List.replicate(Elem, U32.to_nat(Build.slot(b)), Elem.zero()),
       U32.add(Build.nu(b), 1), Build.nb(b)}

def Prog.load.go(+ok: Bool, +b: Build, us: List<&2, Uop>, fs: List<&2, Buf>) -> Maybe<&2, Load>:
  match ok:
    case True{}: Some{Prog.load.put(b, us, fs)}
    case False{}: None{}

def Prog.load.at(+b: Build, us: List<&2, Uop>, fs: List<&2, Buf>, +ok: Bool) -> Maybe<&2, Load>:
  Prog.load.go(ok, b, us, fs)

def Prog.load(+b: Build) -> Maybe<&2, Load>:
  Prog.load.at(b, List.reverse(&2, Uop, Build.us(b)), Prog.bases(b), Build.ok(b))

def Prog.hdr.put(+b: Build, +named: Bool, +some: Bool, +nb: U32) -> Build:
  Build{b.us, b.sp, b.ss, b.bp, U32.add(b.nu, 1), nb, b.nbp, b.sbn, b.pn, b.slot,
        Bool.and(b.ok, Bool.and(named, some))}

# ===========================================================================
# ONE UOP LINE, IN ONE PASS over its words: 1 the op, 2 the dtype, 3 the arg,
# 4.. the srcs. The `<idx>:` field is not read, because ops_bend.encode walks the
# renderer's own list in order and asserts post-order -- a line's POSITION is the
# index its srcs name. A fifth src is refused: measured max 4, and only a STACK
# gets near it.
# ===========================================================================

def Prog.hdr.of(+ws: List<&2, String>, +b: Build) -> Build:
  Prog.hdr.put(b, String.eq(w(ws, 0n), "bendexec1"), U32.is_gt(num_of(num(w(ws, 1))), 0),
    num_of(num(w(ws, 2))))

# `bendexec1 <nuops> <nbuffers>`, read as strictly as the rest
def Prog.hdr(l: String, +b: Build) -> Build: Prog.hdr.of(words(l), b)

def Uop.refused(+u: Uop) -> Bool: U32.is_ge(Uop.kind(u), 14)

def Prog.one.put(+b: Build, +slot: U32, +u: Uop, +ok: Bool) -> Build:
  Build{u <> b.us, b.sp, b.ss, b.bp, b.nu, b.nb, b.nbp, b.sbn, U32.add(b.pn, 1), slot,
        Bool.and(b.ok, ok)}

def Prog.alloc.ss(+b: Build, +f: Buf) -> Build:
  Build{b.us, b.sp, List.append(&2, Buf, b.ss, [f]), b.bp, b.nu, b.nb, b.nbp,
        U32.add(b.sbn, 1), b.pn, b.slot, b.ok}

def Prog.w(+u: Uop) -> U32: S.Dt.itemsize(Uop.dt(u))

def Prog.alloc.sp(+b: Build, +f: Buf) -> Build:
  Build{b.us, List.append(&2, Buf, b.sp, [f]), b.ss, b.bp, b.nu, b.nb, U32.add(b.nbp, 1),
        b.sbn, b.pn, b.slot, b.ok}

def Prog.alloc.at(+u: Uop, +b: Build, +scratch: Bool) -> Build:
  Bool.pick(Build, scratch, Prog.alloc.ss(b, Buf.make(Prog.w(u), Uop.a(u))),
    Prog.alloc.sp(b, Buf.make(Prog.w(u), Uop.a(u))))

def Prog.scratch(+u: Uop) -> Bool: Bool.or(U32.is_eq(Uop.kind(u), 4), U32.is_eq(Uop.kind(u), 5))

def Prog.alloc(+u: Uop, +b: Build) -> Build: Prog.alloc.at(u, b, Prog.scratch(u))

def Prog.pkt(+u: Uop) -> Bool: Bool.or(U32.is_eq(Uop.kind(u), 2), U32.is_eq(Uop.kind(u), 3))

# A1: the packet buffers are the PARAMs of addrspace g or l in uop order, so
# their ids are 0..nb-1 in that order and PACKET.out is written back in it. The
# scratch a PARAM of addrspace r or a BUFFER allocates takes the ids after those,
# so it can never be mistaken for a packet buffer on the way out.
def Prog.one.bid(+u: Uop, +b: Build) -> U32:
  Bool.pick(U32, Prog.pkt(u), b.nbp, U32.add(b.nb, b.sbn))

# THE REFUSALS. `Uop.refused` is the whole of the parse's validation, so the walk
# never has to know a kind exists that it cannot answer.
def Prog.one.two(+u: Uop, +b: Build) -> Build:
  Prog.one.put(Prog.alloc(u, b), U32.add(b.slot, Uop.run(u)),
    Uop.slot1(u, Uop.slot(u), Prog.one.bid(u, b)), Bool.not(Uop.refused(u)))

def Prog.one.no(+b: Build) -> Build:
  Build{b.us, b.sp, b.ss, b.bp, b.nu, b.nb, b.nbp, b.sbn, U32.add(b.pn, 1), b.slot, False{}}

def Prog.one.of(m: Maybe<&2, Uop>, +b: Build) -> Build:
  match m:
    case Some{u}: Prog.one.two(u, b)
    case None{}: Prog.one.no(b)

def Uop.line(l: String, +slot: U32) -> Maybe<&2, Uop>:
  Uop.line.go(words(l), 0n, slot, Uop.bottom())

def Prog.one(l: String, +b: Build) -> Build: Prog.one.of(Uop.line(l, b.slot), b)

def Prog.hex.put.go(cs: List<U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case h <> t: Prog.hex.put.go(t, h <> acc)

# ===========================================================================
# THE LOADED PACKET: the bases, the store, the arena, and the counts that have to
# agree with the header.
# ===========================================================================

def Prog.hex.put(b: Build, r: (Bool & List<U32>)) -> Build:
  Build{b.us, b.sp, b.ss, Prog.hex.put.go(list_of(r), b.bp), b.nu, b.nb, b.nbp, b.sbn,
        b.pn, b.slot, Bool.and(b.ok, bytes_ok(r))}

def Prog.hex.of(+ws: List<&2, String>, +b: Build) -> Build:
  Prog.hex.put(b, bytes_of(String.to_list(w(ws, 1n))))

def Prog.hex(l: String, +b: Build) -> Build: Prog.hex.of(words(l), b)

# `Bool.pick` computes both arms and this is a pure fold, so the wrong arm's work
# is discarded: cheaper than a match, and it keeps the phase test in one place. A
# buffer line parsed as a uop and a uop line parsed as hex both set ok False in
# the arm that gets thrown away.
def Prog.parse.at(l: String, +k: U32, +b: Build) -> Build:
  Bool.pick(Build, U32.is_eq(k, 0), Prog.hdr(l, b),
    Bool.pick(Build, U32.is_le(k, b.nu), Prog.one(l, b), Prog.hex(l, b)))

def Prog.parse.go(ls: List<&2, String>, +k: U32, +b: Build) -> Build:
  match ls:
    case Nil{}: b
    case l <> t: Prog.parse.go(t, U32.add(k, 1), Prog.parse.at(l, k, b))

def Prog.parse(s: String) -> Maybe<&2, Load>:
  Prog.load(Prog.parse.go(String.lines(s), 0, Build.blank()))

def Uop.of.op2(+u: Uop, m: Maybe<&1, O.Op>) -> Uop:
  match m:
    case Some{op}: Uop.of(u, op)
    case None{}: Uop.ak(u, 15, 0, 0)

def Uop.of.op(+u: Uop, h: String) -> Uop: Uop.of.op2(u, op_of(h))

def Uop.of.dt2(+u: Uop, m: Maybe<&1, S.Dt>) -> Uop:
  match m:
    case Some{dt}: Uop.dt1(u, dt)
    case None{}: Uop.ak(u, 14, 0, 0)

def Uop.of.dt(+u: Uop, h: String) -> Uop: Uop.of.dt2(u, D.to_dtype(h))

def Uop.of.arg2(+u: Uop, m: Maybe<&2, Arg>) -> Uop:
  match m:
    case Some{g}: Uop.ak(u, Arg.kind(g), Arg.x(g), Arg.y(g))
    case None{}: Uop.ak(u, 14, 0, 0)

# ===========================================================================
# A BUFFER LINE, `<nbytes> <hex-bytes>`. Its bytes are consed onto `bp` in
# packet order and the whole run is reversed once at the end -- `List.set` per
# byte would be quadratic on a 2 KiB buffer.
# ===========================================================================

def Uop.of.arg(+u: Uop, h: String) -> Uop: Uop.of.arg2(u, Arg.of(h))

# a src index: 1-based on the wire, 0-based here, refused when `U32.read` refuses
# the spelling. The bounds check is `Uop.at`'s: an index past the packet answers
# the bottom, and the bottom of an INDEX is the zero this walk then reads.
def Uop.of.sr(h: String) -> U32: U32.sub(num_of(num(h)), 1)

def Uop.of.go(ws: List<&2, String>, +k: Nat, +slot: U32, +u: Uop) -> Maybe<&2, Uop>:
  match ws k:
    case Nil{} _ : None{}
    case _ <> t 0n: Uop.line.go(t, 1n, slot, u)
    case h <> t 1n: Uop.line.go(t, 2n, slot, Uop.of.op(u, h))
    case h <> t 2n: Uop.line.go(t, 3n, slot, Uop.of.dt(u, h))
    case h <> t 3n: Uop.line.go(t, 4n, slot, Uop.of.arg(u, h))
    case h <> t 4n: Some{Uop.run1(Uop.add(u, Uop.of.sr(h)))}
    case h <> t 5n: Some{Uop.run1(Uop.add(u, Uop.of.sr(h)))}
    case h <> t 6n: Some{Uop.run1(Uop.add(u, Uop.of.sr(h)))}
    case h <> t 7n: Some{Uop.run1(Uop.add(u, Uop.of.sr(h)))}
    case _ <> t _ : None{}

type Prog is Data:
  Prog{us: List<&2, Uop>, vs: List<&2, Elem>, v0: List<&2, Elem>, ms: List<&2, U32>,
       fs: List<&2, Buf>, mk: List<&2, Bool>, vals: List<&2, U32>, pc: U32, n: U32,
       pv: U32, gx: U32, gy: U32, gz: U32, cx: U32, cy: U32, cz: U32, bad: Bool}

def Prog.of(+args: Args, +ld: Load) -> Prog:
  Prog{ld.us, ld.v0, ld.v0, ld.ms, ld.fs, Nil{}, args.vals, 0, ld.n, 3, 0, 0, 0,
       args.gx, args.gy, args.gz, False{}}

def Prog.at(+p: Prog, +pc: U32) -> Prog:
  Prog{p.us, p.vs, p.v0, p.ms, p.fs, p.mk, p.vals, pc, p.n, p.pv, p.gx, p.gy, p.gz,
       p.cx, p.cy, p.cz, p.bad}

def Prog.next(+p: Prog) -> Prog: Prog.at(p, U32.add(p.pc, 1))

def Prog.us(+p: Prog) -> List<&2, Uop>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: us

def Prog.vs(+p: Prog) -> List<&2, Elem>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: vs

def Prog.v0(+p: Prog) -> List<&2, Elem>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: v0

def Prog.ms(+p: Prog) -> List<&2, U32>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: ms

def Prog.fs(+p: Prog) -> List<&2, Buf>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: fs

def Prog.mk(+p: Prog) -> List<&2, Bool>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: mk

def Prog.vals(+p: Prog) -> List<&2, U32>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: vals

def Prog.pc(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: pc

def Prog.n(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: n

def Prog.pv(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: pv

def Prog.gx(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: gx

def Prog.gy(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: gy

def Prog.gz(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: gz

def Prog.cy(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: cy

def Prog.cz(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: cz

def Prog.bad(+p: Prog) -> Bool:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad}: bad

def Prog.vs1(+p: Prog, vs: List<&2, Elem>) -> Prog:
  Prog{p.us, vs, p.v0, p.ms, p.fs, p.mk, p.vals, p.pc, p.n, p.pv, p.gx, p.gy, p.gz,
       p.cx, p.cy, p.cz, p.bad}

def Prog.ms1(+p: Prog, ms: List<&2, U32>) -> Prog:
  Prog{p.us, p.vs, p.v0, ms, p.fs, p.mk, p.vals, p.pc, p.n, p.pv, p.gx, p.gy, p.gz,
       p.cx, p.cy, p.cz, p.bad}

def Prog.mk1(+p: Prog, mk: List<&2, Bool>) -> Prog:
  Prog{p.us, p.vs, p.v0, p.ms, p.fs, mk, p.vals, p.pc, p.n, p.pv, p.gx, p.gy, p.gz,
       p.cx, p.cy, p.cz, p.bad}

def Prog.pv1(+p: Prog) -> Prog:
  Prog{p.us, p.vs, p.v0, p.ms, p.fs, p.mk, p.vals, p.pc, p.n, U32.add(p.pv, 1),
       p.gx, p.gy, p.gz, p.cx, p.cy, p.cz, p.bad}

# `values[v]` for the k-th src: one arena read and one program read, which is
# what a step costs.
def Prog.src(+p: Prog, +u: Uop, +k: Nat) -> Elem:
  Val.at(Prog.vs(p), Uop.slot(Uop.at(Prog.us(p), Uop.nth(Uop.srcs(u), k))))

# the run of the k-th src, for the two places ops_python reads a src's RUN
# rather than its value: a STACK's elements and a STORE's lanes.
def Prog.slot(+p: Prog, +u: Uop, +k: Nat) -> U32:
  Uop.slot(Uop.at(Prog.us(p), Uop.nth(Uop.srcs(u), k)))

# `src_dtypes[k]`, which ops_python reads for a LOAD and a STORE
def Prog.dt(+p: Prog, +u: Uop, +k: Nat) -> S.Dt:
  Uop.dt(Uop.at(Prog.us(p), Uop.nth(Uop.srcs(u), k)))

def Prog.backedge.at(+p: Prog, +u: Uop, +c: Bool) -> Prog:
  match c:
    case True{}: Prog.at(p, Uop.src1(u))
    case False{}: Prog.next(p)

# ===========================================================================
# :51 `loop_ends` -- `{u.src[1]: i for i, u in enumerate(uops) if u.op in {END,
# BACKEDGE}}`, so the LAST end of a RANGE wins. Measured: exactly one end per
# RANGE in all 25 packets, which is why first == last and why a scan is enough.
# ===========================================================================

def Prog.backedge(+p: Prog, +u: Uop) -> Prog:
  Prog.backedge.at(p, u, Elem.is_true(Prog.src(p, u, 2n)))

def Prog.loop.hit(+at: U32, +hit: U32, +yes: Bool) -> U32:
  match yes:
    case True{}: at
    case False{}: hit

# ===========================================================================
# :123-131 RANGE. The counter is the uop's OWN slot (:126-127 increments it in
# place), it starts at 0, and reaching src[0] jumps PAST the loop's end (:130).
# `del values[u]` is skipped and is not observable: nothing jumps back to a RANGE
# except its own end, which is the one being left.
#
# A RANGE of dtype void is the no-op of :81 and the wire spells its dtype, so the
# void case is a Bool on the way in. `Dt.itemsize` is 0 exactly for void.
# ===========================================================================

def Prog.loop.end(+u: Uop) -> Bool: O.op_in([O.OpsEND{}, O.OpsBACKEDGE{}], Uop.op(u))

def Prog.loop.at(+u: Uop, +r: U32, +hit: U32, +i: U32) -> U32:
  Prog.loop.hit(i, hit, Bool.and(Prog.loop.end(u), U32.is_eq(Uop.src1(u), r)))

def Prog.loop.go(us: List<&2, Uop>, +r: U32, +hit: U32, +i: U32) -> U32:
  match us:
    case Nil{}: hit
    case u <> t: Prog.loop.go(t, r, Prog.loop.at(u, r, hit, i), U32.add(i, 1))

def Prog.loop(+p: Prog, +r: U32) -> U32: Prog.loop.go(Prog.us(p), r, 0, 0)

def Prog.put(+p: Prog, +u: Uop, +e: Elem) -> Prog:
  Prog.next(Prog.vs1(p, Val.put(Prog.vs(p), Uop.slot(u), e)))

# ===========================================================================
# :67-68 BACKEDGE -- `i = uop_to_index[u.src[1]] if values[u.src[2]][0] else
# i+1`. The condition is src 2 and the loop head is src 1.
# ===========================================================================

def Prog.cur(+p: Prog, +u: Uop) -> U32: Elem.bits(Val.at(Prog.vs(p), Uop.slot(u)))

def Prog.rng.over(+p: Prog, +u: Uop, +over: Bool) -> Prog:
  match over:
    case True{}: Prog.at(p, U32.add(Prog.loop(p, Prog.pc(p)), 1))
    case False{}: Prog.put(p, u, elem_of(U32.add(Prog.cur(p, u), 1), Uop.dt(u)))

# ===========================================================================
# :73-78 IF/ENDIF. `exec_masks` is a stack of "one Bool per work item" (the warp
# is 1 here), so an IF pushes the conjunction of the top and the condition and an
# ENDIF pops. ops_python skips VOID srcs when it builds `src_values`, and
# MEASURED the only op with a void src is an AFTER, whose first src is never void
# -- so the filter has no other place to show up and is not spelled.
# ===========================================================================

def Prog.trip(+p: Prog, +u: Uop) -> U32: Elem.bits(Prog.src(p, u, 0n))

def Prog.rng.at(+p: Prog, +u: Uop, +void: Bool) -> Prog:
  match void:
    case True{}: Prog.next(p)
    case False{}: Prog.rng.over(p, u, U32.is_eq(Prog.cur(p, u), Prog.trip(p, u)))

def Prog.rng(+p: Prog, +u: Uop) -> Prog: Prog.rng.at(p, u, U32.is_eq(S.Dt.itemsize(Uop.dt(u)), 0))

# the store gate of :87 and the load gate of :24: `exec_masks[-1]`, which is True
# when nothing is masked
def Prog.open(+p: Prog) -> Bool:
  Maybe.default(&2, Bool, List.get(&2, Bool, Prog.mk(p), 0n), True{})

# ===========================================================================
# :94, :99-105 PARAM and BUFFER. A PARAM of addrspace a reads a `vals` entry
# (:94); every other PARAM and a BUFFER bind buffer id `b`, which A1 resolved at
# parse time. Both are re-bound on every visit, which is what a re-executed uop
# must do.
# ===========================================================================

def Prog.ifs(+p: Prog, +u: Uop) -> Prog:
  Prog.mk1(p, Bool.and(Prog.open(p), Elem.is_true(Prog.src(p, u, 0n))) <> Prog.mk(p))

def Prog.val(+p: Prog) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Prog.vals(p), U32.to_nat(Prog.pv(p))), 0)

# ===========================================================================
# :107-109 SPECIAL. `'g'` reads `idxs[2-int(u.arg[-1])]` and `'l'` reads the warp,
# which is `[(0,0,0)]` here, so a lidx is the constant 0 (see LOCAL SIZE).
# ===========================================================================

def Prog.param.at(+p: Prog, +u: Uop, +is_vals: Bool) -> Prog:
  match is_vals:
    case True{}: Prog.put(Prog.pv1(p), u, elem_of(Prog.val(p), Uop.dt(u)))
    case False{}: Prog.put(p, u, Bf{Uop.b(u)})

def Prog.param(+p: Prog, +u: Uop) -> Prog: Prog.param.at(p, u, U32.is_eq(Uop.kind(u), 6))

def Prog.idx(+gx: U32, +gy: U32, +gz: U32, +a: U32) -> U32:
  Bool.pick(U32, U32.is_eq(a, 0), gx, Bool.pick(U32, U32.is_eq(a, 1), gy,
    Bool.pick(U32, U32.is_eq(a, 2), gz, 0)))

# ===========================================================================
# :111-122 INDEX and SHRINK. `k:idx:0` is ops_python's ALU arm -- src[0] is an ALU
# value, so `src_values[0][i][t]` picks element i of a vector LOAD, and t is 0 at
# warp 1. Otherwise src[0] is a buffer reference and the wire's scale is the
# BITCAST ratio of :120, already computed; the third src (55 of 317 measured) is
# the shrink's limit, which ops_python never reads, so neither does this.
# ===========================================================================

def Prog.special(+p: Prog, +u: Uop) -> Prog:
  Prog.put(p, u, elem_of(Prog.idx(Prog.gx(p), Prog.gy(p), Prog.gz(p), Uop.a(u)), Uop.dt(u)))

# `src_values[0][i][0]` -- the flat run of a vector LOAD indexed by the scalar
def Prog.index.alu(+p: Prog, +u: Uop) -> Elem:
  Val.at(Prog.vs(p), U32.add(Prog.slot(p, u, 0n), Prog.trip(p, u)))

def Prog.index.rf(+b: U32, +o: U32, +n: Bool, +i: U32, +scale: U32) -> Elem:
  Rf{b, U32.add(o, U32.mul(i, scale)), n}

# ===========================================================================
# :132 STACK -- `values[u] = src_values`, so a run of the srcs' first elements.
# Measured max 4 srcs and never a vector LOAD among them, which is what keeps the
# flattening (see THE PROGRAM TABLE).
# ===========================================================================

# `(m[0], m[1] + o*scale) if isinstance(m, tuple) else (m, o*scale)` -- ONE
# spelling, because `Elem.off` of a bare Bf is 0 and `Elem.off_none` of a Bf is
# False, which is exactly what the two arms of that line compute.
def Prog.index.mem(+p: Prog, +u: Uop) -> Elem:
  Prog.index.rf(Elem.buf(Prog.src(p, u, 0n)), Elem.off(Prog.src(p, u, 0n)),
    Elem.off_none(Prog.src(p, u, 0n)), Prog.trip(p, u), Uop.a(u))

def Prog.index.at(+p: Prog, +u: Uop, +alu: Bool) -> Prog:
  Prog.put(p, u, Bool.pick(Elem, alu, Prog.index.alu(p, u), Prog.index.mem(p, u)))

def Prog.index(+p: Prog, +u: Uop) -> Prog: Prog.index.at(p, u, U32.is_eq(Uop.a(u), 0))

def Prog.stack.copy(es: List<&2, Elem>, vs: List<&2, Elem>, slot: U32, k: Nat) ->
  List<&2, Elem>:
  match es:
    case Nil{}: vs
    case e <> t: Prog.stack.copy(t, Val.put(vs, U32.add(slot, U32.from_nat(k)), e),
      slot, Nat.add(k, 1n))

# ===========================================================================
# :93 AFTER, :133 BITCAST, :134 CAST.
#
# An AFTER is a pass-through of its first non-void src. A BITCAST is the same
# bits at the target dtype -- for the four lanes `assert
# itemsize(in) == itemsize(out)` holds and `truncate` is the identity -- so it is
# the CAST arm with no conversion. The one thing this cannot say is a BITCAST of
# addrspace GLOBAL or LOCAL, which ops_python passes through WITHOUT changing the
# dtype (:93) and which the wire does not spell: see AMENDMENT A6.
# ===========================================================================

def Prog.stack.at(ss: List<&2, U32>, vs: List<&2, Elem>, us: List<&2, Uop>,
  acc: List<&2, Elem>) -> List<&2, Elem>:
  match ss:
    case Nil{}: acc
    case s <> t: Prog.stack.at(t, vs, us, List.append(&2, Elem, acc,
      [Val.at(vs, Uop.slot(Uop.at(us, s)))]))

def Prog.stack(+p: Prog, +u: Uop) -> Prog:
  Prog.vs1(p, Prog.stack.copy(Prog.stack.at(Uop.srcs(u), Prog.vs(p), Prog.us(p), Nil{}),
    Prog.vs(p), Uop.slot(u), 0n))

def Prog.cast.dt(dst: S.Dt, src: S.Dt, +e: Elem) -> Elem:
  Bool.pick(Elem, S.Dt.is_bool(dst), elem_of(Bool.to_u32(Elem.is_true(e)), dst),
    Bool.pick(Elem, S.Dt.is_float(dst), elem_of(F32.bits(f_of(e)), dst),
      Bool.pick(Elem, S.Dt.is_float(src), elem_of(F32.bits(F32.trunc(f_of(e))), dst),
        elem_of(Elem.bits(e), dst))))

# ===========================================================================
# :136-142 LOAD. `k:vec:n` is the flat run of n lanes (A2), and lane j reads the
# pointer of src[0] at `+ j*_step`. A THREE-src LOAD is ops_python.py:24's gated
# form: the lane is `alt` where src[2] is false. Measured 116 one-src and one
# three-src LOAD; ops_python reads only src[0] of a two-src LOAD, so a two-src
# LOAD walks the same lane path as a one-src one.
# ===========================================================================

def Prog.cast.at(+p: Prog, +u: Uop, dst: S.Dt, src: S.Dt) -> Prog:
  Prog.put(p, u, Prog.cast.dt(dst, src, Prog.src(p, u, 0n)))

# `truncate.get(u.dtype)(u.dtype.const(x))` -- `bool(x)`, `c_float(x)` or
# `c_int(x)`. For the four lanes that is a value conversion, and an int wrap is
# already the U32 bit pattern; an int SOURCE is the identity, because routing it
# through F32 would round a value above 2^24.
def Prog.cast(+p: Prog, +u: Uop) -> Prog: Prog.cast.at(p, u, Uop.dt(u), Prog.dt(p, u, 0n))

def Prog.bitcast(+p: Prog, +u: Uop) -> Prog: Prog.cast(p, u)

def Prog.live.at(+p: Prog, +oob: Bool) -> Prog:
  Prog{p.us, p.vs, p.v0, p.ms, p.fs, p.mk, p.vals, p.pc, p.n, p.pv, p.gx, p.gy, p.gz,
       p.cx, p.cy, p.cz, Bool.or(p.bad, oob)}

def Prog.lane.of(+f: Buf, dt: S.Dt) -> U32:
  Bool.pick(U32, U32.is_lt(S.Dt.itemsize(dt), Buf.w(f)), 1,
    U32.div(S.Dt.itemsize(dt), Buf.w(f)))

# ===========================================================================
# :85-91 STORE. `u.max_numel() > 1` walks the value run, and `zip` pairs it with
# the ONE pointer of src[0] and with the gate, so lane j writes element j of the
# value run at `o + j*_step`. A value run LONGER than the pointer run (measured:
# a vec 4 LOAD feeding a vec 1 STORE, four of them) stores its FIRST element
# only -- which is what zip's truncation gives, and why the flat run is read the
# same way here.
# ===========================================================================

# THE BUFFER A MEMORY OP TOUCHES: src[0] is a buffer reference in every measured
# LOAD and STORE (an INDEX/SHRINK of a PARAM, or a pass-through of one).
def Prog.buf(+p: Prog, +u: Uop) -> Buf: Buf.at(Prog.fs(p), Elem.buf(Prog.src(p, u, 0n)))

# ===========================================================================
# :151-154 GroupOp.ALU. The two asserts of :152-153 are dropped: they are
# invariants the scheduler upholds, and breaking one is a wrong packet rather
# than a wrong device. The arity is the src count, exactly as `zip(*src_values)`
# gives it. `Bool.pick` computes both arms, so all three arities are evaluated and
# one is kept -- the alternative is a match on the op, which would read the arity
# off a table instead of off the packet.
# ===========================================================================

# `_step(m, dtype)` -- ops_python.py:21, storage elements per lane. It is 1 for
# every v1 lane, and it is spelled out rather than assumed so that a buffer whose
# storage word is narrower than the dtype still indexes the way ops_python does.
def Prog.lane(+p: Prog, +u: Uop) -> U32:
  Prog.lane.of(Prog.buf(p, u), Uop.dt(u))

# the storage element index of lane j, `o + j*_step` (ops_python.py:24, :90)
def Prog.store.i(+p: Prog, +u: Uop, +j: U32) -> U32:
  U32.add(Elem.off(Prog.src(p, u, 0n)), U32.mul(j, Prog.lane(p, u)))

def Prog.oob.go(+p: Prog, +u: Uop, +n: Nat, +j: U32) -> Bool:
  Bool.or(U32.is_ge(Prog.store.i(p, u, j), Buf.e(Prog.buf(p, u))), Prog.oob(p, u, n, j))

def Prog.oob(+p: Prog, +u: Uop, +n: Nat, +j: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(n, 0), False{}, Prog.oob.go(p, u, U32.sub(n, 1), j))

# THE POISON. ops_python raises IndexError on a load or a store past the end of a
# buffer (:17, :28); Bend answers a default instead, so the check runs here and
# the launch is refused at the end rather than answering a plausible wrong number.
def Prog.live(+p: Prog, +u: Uop) -> Prog:
  Prog.live.at(p, Prog.oob(p, u, U32.to_nat(Uop.run(u)), 0))

def Prog.ld.gate(+got: Elem, +three: Bool, +alt: Elem, +open: Bool) -> Elem:
  Bool.pick(Elem, Bool.and(three, Bool.not(open)), alt, got)

def Prog.word.dt(dt: S.Dt, +word: U32) -> U32:
  Bool.pick(U32, S.Dt.is_bool(dt), Bool.to_u32(U32.is_ne(word, 0)), word)

# `from_storage_scalar` -- the identity for the three 4-byte lanes, `bool(x)` for
# bool -- and an out-of-range index is ops_python's IndexError, which answers zero
# here and is POISONED by the caller.
def Prog.word.ok(+word: U32, +inb: Bool, dt: S.Dt) -> U32:
  Bool.pick(U32, inb, Prog.word.dt(dt, word), 0)

# `_load(m, i, dtype)` -- ops_python.py:15-19, first arm. The index is in
# STORAGE elements, so the byte address is `base + i*w`.
def Prog.ld(+p: Prog, +f: Buf, +i: U32, dt: S.Dt) -> U32:
  Prog.word.ok(Mem.ld(Prog.ms(p), U32.add(Buf.base(f), U32.mul(i, Buf.w(f))), Buf.w(f)),
    U32.is_lt(i, Buf.e(f)), dt)

def Prog.ld.read(+p: Prog, +u: Uop, +ptr: Elem, +j: U32) -> Elem:
  elem_of(Prog.ld(p, Buf.at(Prog.fs(p), Elem.buf(ptr)),
    U32.add(Elem.off(ptr), U32.mul(j, Prog.lane(p, u))), Uop.dt(u)), Uop.dt(u))

def Prog.ld.three(+u: Uop) -> Bool: U32.eq(Uop.nsrc(u), 3)

def Prog.ld.lane(+p: Prog, +u: Uop, +j: U32) -> Elem:
  Prog.ld.gate(Prog.ld.read(p, u, Prog.src(p, u, 0n), j), Prog.ld.three(u),
    Prog.src(p, u, 1n), Elem.is_true(Prog.src(p, u, 2n)))

def Prog.ld.at(+u: Uop, vs: List<&2, Elem>, +n: Nat, +j: U32, +p: Prog) -> List<&2, Elem>:
  match n:
    case 0n: vs
    case 1n+q: Prog.ld.at(u, Val.put(vs, U32.add(Uop.slot(u), j), Prog.ld.lane(p, u, j)),
      q, U32.add(j, 1), p)

def Prog.ld1(+p: Prog, +u: Uop) -> Prog:
  Prog.live(Prog.vs1(p, Prog.ld.at(u, Prog.vs(p), U32.to_nat(Uop.run(u)), 0, p)), u)

# ops_python's `if g:` -- a masked-off store does not write, and the write itself
# is computed and discarded rather than branched over (Bool.pick is not a branch)
def Prog.store.go(ms: List<&2, U32>, done: List<&2, U32>, +open: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, open, done, ms)

def Prog.store.addr(+p: Prog, +u: Uop, +j: U32) -> U32:
  U32.add(Buf.base(Prog.buf(p, u)), U32.mul(Prog.store.i(p, u, j), Buf.w(Prog.buf(p, u))))

# lane j of the value run: the 1st src's own run, indexed
def Prog.store.v(+p: Prog, +u: Uop, +j: U32) -> U32:
  Elem.bits(Val.at(Prog.vs(p), U32.add(Prog.slot(p, u, 1n), j)))

def Prog.store.lane.at(+p: Prog, +u: Uop, +j: U32) -> List<&2, U32>:
  Mem.st(Prog.ms(p), Prog.store.addr(p, u, j), Buf.w(Prog.buf(p, u)), Prog.store.v(p, u, j))

def Prog.store.open(+p: Prog, +u: Uop, +j: U32) -> Bool:
  Bool.and(Prog.open(p), U32.is_lt(Prog.store.i(p, u, j), Buf.e(Prog.buf(p, u))))

# `_store(m, o + j*_step, v, src_dtypes[1])` -- `to_storage_scalar` is the
# identity for the three 4-byte lanes and `bool(x)` for bool
def Prog.store.lane(+p: Prog, +u: Uop, +j: U32) -> List<&2, U32>:
  Prog.store.go(Prog.ms(p), Prog.store.lane.at(p, u, j), Prog.store.open(p, u, j))

def Prog.store.at(+u: Uop, ms: List<&2, U32>, +n: Nat, +j: U32, +p: Prog) -> List<&2, U32>:
  match n:
    case 0n: ms
    case 1n+q: Prog.store.at(u, Prog.store.go(ms, Prog.store.lane(p, u, j),
      Prog.store.open(p, u, j)), q, U32.add(j, 1), p)

def Prog.store(+p: Prog, +u: Uop) -> Prog:
  Prog.live(Prog.ms1(p, Prog.store.at(u, Prog.ms(p), U32.to_nat(Uop.run(u)), 0, p)), u)

def Prog.after(+p: Prog, +u: Uop) -> Prog: Prog.put(p, u, Prog.src(p, u, 0n))

def Prog.alu.at(+p: Prog, +u: Uop, +one: Bool, +two: Bool) -> Prog:
  Prog.put(p, u, Bool.pick(Elem, one, alu1(Uop.op(u), Uop.dt(u), Prog.src(p, u, 0n)),
    Bool.pick(Elem, two, alu2(Uop.op(u), Uop.dt(u), Prog.src(p, u, 0n), Prog.src(p, u, 1n)),
      alu3(Uop.op(u), Uop.dt(u), Prog.src(p, u, 0n), Prog.src(p, u, 1n), Prog.src(p, u, 2n)))))

# ===========================================================================
# THE INTERPRETER LOOP. One recursion per instruction: Bend has no loop and no
# `continue`, so `run` IS the `while i < len(self.uops)` of ops_python.py:62.
#
# FUEL is the bound, and running out of it is a loud refusal rather than a wrong
# answer -- a RANGE-driven kernel has no static step count, and this is also the
# "stay turing-incomplete" answer. MEASURED: the worst of the 25 gate packets runs
# 17953 steps (a 16x16 matmul), and a 1e6-deep recursion compiles and runs in
# 30 ms (.agents/slop/x-deep.bend), so the fuel below is two orders of magnitude
# above the measured need and three below the depth that was timed.
# ===========================================================================

def Prog.alu(+p: Prog, +u: Uop) -> Prog:
  Prog.alu.at(p, u, U32.is_eq(Uop.nsrc(u), 1), U32.is_eq(Uop.nsrc(u), 2))

def Prog.dispatch(+p: Prog, +u: Uop, op: O.Op) -> Prog:
  match op:
    case O.OpsBARRIER{}: Prog.next(p)
    case O.OpsSINK{}: Prog.next(p)
    case O.OpsNOOP{}: Prog.next(p)
    case O.OpsGROUP{}: Prog.next(p)
    case O.OpsEND{}: Prog.at(p, Uop.src1(u))
    case O.OpsBACKEDGE{}: Prog.backedge(p, u)
    case O.OpsRANGE{}: Prog.rng(p, u)
    case O.OpsIF{}: Prog.ifs(p, u)
    case O.OpsENDIF{}: Prog.mk1(p, List.tail(&2, Bool, Prog.mk(p)))
    case O.OpsPARAM{}: Prog.param(p, u)
    case O.OpsBUFFER{}: Prog.put(p, u, Bf{Uop.b(u)})
    case O.OpsCONST{}: Prog.put(p, u, elem_of(Uop.a(u), Uop.dt(u)))
    case O.OpsSPECIAL{}: Prog.special(p, u)
    case O.OpsINDEX{}: Prog.index(p, u)
    case O.OpsSHRINK{}: Prog.index(p, u)
    case O.OpsSTACK{}: Prog.stack(p, u)
    case O.OpsBITCAST{}: Prog.bitcast(p, u)
    case O.OpsCAST{}: Prog.cast(p, u)
    case O.OpsLOAD{}: Prog.ld1(p, u)
    case O.OpsSTORE{}: Prog.store(p, u)
    case O.OpsAFTER{}: Prog.after(p, u)
    case _: Prog.alu(p, u)

def Prog.run(+p: Prog, +u: Uop) -> Prog: Prog.dispatch(p, u, Uop.op(u))

# THE STEP. One arm per line of ops_python's `__call__`, in its order.
def Prog.step(+p: Prog) -> Prog: Prog.run(p, Uop.at(Prog.us(p), Prog.pc(p)))

def FUEL() -> Nat: 4000000n

def run(+f: Nat, +pr: Prog) -> Maybe<&1, Prog>:
  match f:
    case 0n: None{}
    case 1n+k: run.at(pr, U32.is_ge(Prog.pc(pr), Prog.n(pr)), k)

def run.at(+pr: Prog, +over: Bool, +f: Nat) -> Maybe<&1, Prog>:
  match over:
    case True{}: Some{pr}
    case False{}: run(f, Prog.step(pr))

# ===========================================================================
# THE GRID, :56 -- `for idxs in itertools.product(*[range(x) for x in
# global_size[::-1]])`. gz varies fastest and `idxs` is (z, y, x), so the first
# work item is (0,0,0) and the odometer carries gz. `values`, `exec_masks`,
# `pvals` and the pc are RESET per work item and the buffers are not, which is
# what makes a second work item accumulate into the first one's stores.
# ===========================================================================

def Prog.count(+args: Args) -> Nat: Nat.mul(args.gx, Nat.mul(args.gy, args.gz))

def grid(+n: Nat, +pr: Prog) -> Maybe<&1, Prog>:
  match n:
    case 0n: None{}
    case 1n+k: grid.at(run(FUEL(), pr), k)

def Prog.reset(+pr: Prog) -> Prog: Prog.at(Prog.vs1(Prog.mk1(pr, Nil{}), pr.v0), 0)

# ===========================================================================
# THE COMMAND LINE. `IO.args()` is affine, so it is read ONCE, in order, and the
# whole answer is one record: argv[0] is the program (skipped), argv[1] the
# packet, argv[2..4] the grid, and everything after is `vals`. `pv` starts at 3
# because the first three numbers are the grid.
# ===========================================================================

def Prog.carry(+pr: Prog, +oz: Bool) -> Prog:
  Prog{pr.us, pr.vs, pr.v0, pr.ms, pr.fs, pr.mk, pr.vals, pr.pc, pr.n, pr.pv,
       Bool.pick(U32, oz, U32.add(pr.gx, 1), pr.gx),
       Bool.pick(U32, oz, 0, U32.add(pr.gy, 1)),
       Bool.pick(U32, oz, U32.add(pr.gz, 1), 0),
       pr.cx, pr.cy, pr.cz, pr.bad}

def Prog.tick(+pr: Prog) -> Prog: Prog.reset(Prog.carry(pr, U32.is_ge(U32.add(Prog.gz(pr), 1), Prog.cz(pr))))

def grid.at(m: Maybe<&1, Prog>, +n: Nat) -> Maybe<&1, Prog>:
  match m:
    case Some{pr}: grid(n, Prog.tick(pr))
    case None{}: None{}

type Args is Data:
  Args{path: String, gx: U32, gy: U32, gz: U32, vals: List<&2, U32>, ok: Bool}

def Args.blank() -> Args: Args{"", 1, 1, 1, Nil{}, True{}}

def Args.path(+a: Args) -> String:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: path

def Args.gx(+a: Args) -> U32:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: gx

def Args.gy(+a: Args) -> U32:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: gy

def Args.gz(+a: Args) -> U32:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: gz

def Args.vals(+a: Args) -> List<&2, U32>:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: vals

def Args.at(h: String, +k: U32, +a: Args) -> Args:
  Bool.pick(Args, U32.is_eq(k, 1), Args{a.path, a.gx, a.gy, a.gz, a.vals, a.ok},
    Bool.pick(Args, U32.is_eq(k, 0), a,
      Bool.pick(Args, U32.is_eq(k, 2), Args{a.path, num_of(num(h)), a.gy, a.gz, a.vals, a.ok},
        Bool.pick(Args, U32.is_eq(k, 3), Args{a.path, a.gx, num_of(num(h)), a.gz, a.vals, a.ok},
          Bool.pick(Args, U32.is_eq(k, 4), Args{a.path, a.gx, a.gy, num_of(num(h)), a.vals, a.ok},
            Args{a.path, a.gx, a.gy, a.gz, List.append(&2, U32, a.vals, [num_of(num(h))]), a.ok})))))

# ===========================================================================
# THE ENTRY POINT: `bend-executor PACKET gx gy gz vals...`, which reads PACKET,
# runs every work item, and writes PACKET.out beside it.
# ===========================================================================

def Args.go(as: List<String>, +k: U32, +a: Args) -> Maybe<&2, Args>:
  match as:
    case Nil{}: Some{a}
    case h <> t: Args.go(t, U32.add(k, 1), Args.at(h, k, a))

def Args.of(as: List<String>) -> Maybe<&2, Args>:
  Args.go(as, 0, Args.blank())

def Prog.write.slash.at(+h: Char, t: List<Char>, +n: Nat, +at: U32, +best: U32) -> U32:
  Bool.pick(U32, Char.is_eq(h, Char.from_u32(47)), Prog.write.slash.go(t, n, U32.add(at, 1), at),
    Prog.write.slash.go(t, n, U32.add(at, 1), best))

def Prog.write.slash.go(cs: List<Char>, +n: Nat, +at: U32, +best: U32) -> U32:
  match cs n:
    case Nil{} _ : best
    case h <> t 0n: Prog.write.slash.at(h, t, 0n, 0, best)
    case h <> t 1n+p: Prog.write.slash.at(h, t, p, U32.add(at, 1), best)

# the character index just past the last '/', or 0 when there is none
def Prog.write.slash(path: String) -> U32:
  Prog.write.slash.go(String.to_list(path), 0n, 0, 0)

def Prog.write.out(path: String) -> String:
  String.concat([String.drop(path, U32.to_nat(Prog.write.slash(path))), "PACKET.out"])

def Prog.out.join(ls: List<&2, String>, sep: String) -> String:
  String.concat(List.append(&2, String, List.reverse(&2, String, ls), [sep]))

def Prog.line.hex(cs: List<&2, Char>) -> String: String.from_list(cs)

def Prog.line.put2(acc: List<&2, Char>, +v: U32) -> List<&2, Char>:
  [Char.from_u32(U32.add(48, v))] <> acc# two digits, low byte first into the reversed accumulator
def Prog.line.put(acc: List<&2, Char>, +b: U32) -> List<&2, Char>:
  Prog.line.put2([Char.from_u32(U32.add(48, U32.mod(b, 16)))] <> acc, U32.div(b, 16))

def Prog.line.go(+ms: List<&2, U32>, +n: Nat, +at: U32, acc: List<&2, Char>) -> List<&2, Char>:
  match n:
    case 0n: acc
    case 1n+p: Prog.line.go(ms, p, U32.add(at, 1), Prog.line.put(acc, Mem.byte(ms, at)))
def Prog.line(+f: Buf, +ms: List<&2, U32>) -> String:
  String.concat([U32.show(U32.mul(Buf.w(f), Buf.e(f))), " ",
    String.from_list(Prog.line.hex(List.reverse(&2, Char,
      Prog.line.go(ms, U32.to_nat(U32.mul(Buf.w(f), Buf.e(f))), Buf.base(f), Nil{})))), "\n"])

def Prog.out.at(+fs: List<&2, Buf>, +ms: List<&2, U32>, n: Nat, acc: List<&2, String>) ->
  List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p: Prog.out.at(fs, ms, p, Prog.line(Buf.at(fs, U32.from_nat(p)), ms) <> acc)

# the buffer block, the first `nb` buffers of `fs` -- which are the packet's, by
# buffer id (A1)
def Prog.out(+pr: Prog) -> String:
  Prog.out.join(Prog.out.at(Prog.fs(pr), Prog.ms(pr), U32.to_nat(Prog.nb(pr)), Nil{}), "\n")

def Prog.write.close(m: (File & Result<&1, &1, U32 & String, Unit>)) -> IO(Unit):
  (f, _) = m
  File.close(f)

def Prog.write.put(f: File, +pr: Prog) -> IO(Unit):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, Prog.out(pr)),
    m => Prog.write.close(m))

def Prog.write.open(r: Result<&1, &1, U32 & String, File>, +pr: Prog) -> IO(Unit):
  IO.bind(File, Unit, IO.pass(File, r), f => Prog.write.put(f, pr))

# PACKET.out, in the packet's own buffer order, `<nbytes> <hex-bytes>` per line.
# The path is AMENDMENT A6: ops_bend reads `<dir>/PACKET.out` and does not pass
# the name, so it is derived from the packet's.
def Prog.write(+pr: Prog, +args: Args) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(Prog.write.out(args.path), "w"),
    r => Prog.write.open(r, pr))

def Prog.done.go2(+bad: Bool, +args: Args, +pr: Prog) -> IO(Unit):
  match bad:
    case True{}: IO.die(Unit, 1, "executor: refused the packet -- a line it does not port, or a load or store past the end of its buffer, where ops_python raises IndexError")
    case False{}: Prog.write(pr, args)

def Prog.done.go(+pr: Prog, +args: Args, +ok: Bool) -> IO(Unit):
  Prog.done.go2(Bool.or(Prog.bad(pr), Bool.not(ok)), args, pr)

def Prog.done(m: Maybe<&1, Prog>, +args: Args) -> IO(Unit):
  match m:
    case Some{pr}: Prog.done.go(pr, args, True{})
    case None{}: IO.die(Unit, 1, "executor: out of fuel -- the kernel wanted more steps than FUEL() allows")

def Prog.launch.grid(+ld: Load, +args: Args) -> IO(Unit):
  Prog.done(grid(Prog.count(args), Prog.of(args, ld)), args)

def Prog.launch.run.at(ld: Maybe<&2, Load>, +args: Args) -> IO(Unit):
  match ld:
    case Some{l}: Prog.launch.grid(l, args)
    case None{}: IO.die(Unit, 1, "executor: refused the packet -- a dtype, an op, an `<arg>` or a src index that this file does not port")

def Prog.launch.run(text: String, +args: Args) -> IO(Unit):
  Prog.launch.run.at(Prog.parse(text), args)

def Prog.launch.pkt.go(f: File, r: Result<&1, &1, U32 & String, String>, +args: Args) -> IO(Unit):
  match r:
    case Done{text}: IO.bind(Unit, Unit, File.close(f), _ => Prog.launch.run(text, args))
    case Fail{error}: IO.bind(Unit, Unit, File.close(f),
      _ => IO.die(Unit, 1, "executor: the packet could not be read"))

def Prog.launch.pkt(m: (File & Result<&1, &1, U32 & String, String>), args: Args) -> IO(Unit):
  (f, r) = m
  Prog.launch.pkt.go(f, r, args)

def Prog.launch.file(f: File, +args: Args) -> IO(Unit):
  IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824),
    m => Prog.launch.pkt(m, args))

def Prog.launch.open(+args: Args) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(args.path, "r"),
    r => Prog.launch.file(IO.pass(File, r), args))

def Prog.launch.at(a: Maybe<&2, Args>) -> IO(Unit):
  match a:
    case Some{args}: Prog.launch.open(args)
    case None{}: IO.die(Unit, 1, "executor: no PACKET on the command line")

def Prog.launch() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    return Prog.launch.at(Args.of(as))

def main() -> IO(Unit): Prog.launch()

