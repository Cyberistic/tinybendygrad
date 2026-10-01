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

def w32(u: U32) -> Word(32n):
  match u:
    case U32{data}: data

def f32_of(u: U32) -> F32: F32{w32(u)}

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

def word_at(i: U32, ws: List<&2, String>) -> Maybe<&2, String>:
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
def bytes.fin(ok: Bool, live: Bool, acc: List<U32>) -> (Bool & List<U32>):
  match live:
    case True{}: (False{}, acc)
    case False{}: (ok, acc)

def bytes.acc(ok: Bool, c: U32, pend: U32, acc: List<U32>) -> List<U32>:
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

def is_f(e: Elem) -> Bool:
  match e:
    case Sc{b, d}: S.Dt.is_float(d)
    case _: False{}

def elem_c(e: Elem) -> O.Const:
  match e:
    case Sc{b, d}: elem_c.dt(d, b)
    case _: O.CInvalid{}

def bits_of(+c: O.Const) -> U32:
  match c:
    case O.CInt{i}: H.lo32(i)
    case O.CFloat{f}: F32.bits(f)
    case O.CBool{b}: Bool.to_u32(b)
    case _: 0

def elem_of(b: U32, d: S.Dt) -> Elem: Sc{b, d}

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

def f_of(+e: Elem) -> F32:
  match e:
    case Sc{b, d}: f32_of(b)
    case _: 0.0

def ci_of(e: Elem) -> U32: b_of(e)

def cf_of(e: Elem) -> F32: f_of(e)

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
# THE ENTRY POINT. It REFUSES rather than answering wrongly: the interpreter loop
# is not in this file yet (see THE REMAINING WORK), and a device that computed
# a plausible wrong number would be worse than one that says so.
# ===========================================================================

def run() -> IO(Unit):
  IO.die(Unit, 1, String.concat(["executor: the interpreter loop is not built yet; see ",
    "runtime/executor.bend THE REMAINING WORK. The wire format, op table, packet",
    " reader and ALU lane above are done and compile."]))

def main() -> IO(Unit):
  run()