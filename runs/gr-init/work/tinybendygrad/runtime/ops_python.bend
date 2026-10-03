# ops_python.bend -- port of tinygrad/runtime/ops_python.py: `PythonProgram.__call__`, the
# BEND device. `bend-executor PACKET gx gy gz vals...` reads a packet, walks its
# toposorted uops once per global work item, and writes PACKET.out.
#
# STATE OF THIS FILE, MEASURED. `--check-only` is clean apart from the inherited
# "relies on unsafe or foreign code" notice that `dtype.bend` already produces on
# its own, and `-o` builds. The 28-fixture end-to-end gate against the NATIVE
# binary is 18 pass / 10 fail / 3 skip, where the three skips are dtypes the v1
# wire has no lane for (f16, bf16, i64 -- ops_bend raises, which is the contract).
# A pass means `Device['BEND']` and `Device['PYTHON']` agree to 1e-6 on the same
# program, so the loop, the arena, the wire and the ALU lane are all exercised.
#
# WHAT PASSES: const_f32, every elementwise fixture (add, mul, broadcast, i32, u32,
# ishl_shr, compare_where, gated_mul), bool_copy, matmul_vec, reshape, flip, shrink,
# copy_through, mulacc_rowsum, reduce_sum_axis, reduce_rowsum, permute's first
# eighth.
#
# WHAT DOES NOT, and where to look -- all three are ONE defect each:
#   * idiv, imod, reduce_i32 -- the i32 lane's DIV and MOD.
#   * reduce_sum_1d, reduce_sum_2step, reduce_max, reduce_exp2, matmul,
#     permute -- NESTED RANGE loops. The first eight outputs of `permute` are
#     right and the remaining 120 are untouched, so the inner loop is right and
#     the OUTER one's back edge is not: `Prog.loop`/`Prog.rng` walk
#     `loop_ends` and the nested END at ops_python.py:70 jumps to the inner head.
#   * pad -- refused. The refusal is `Prog.bad`, so it is an oob load or store.
#
# `run` is a real interpreter: an arena threaded through a fuel recursion, with a
# DIE on fuel exhaustion, which is also the "stay turing-incomplete" answer since
# a RANGE-driven kernel has no static step bound.
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
# THE SHAPE OF THE MACHINE, and the two parts that were not obvious.
#
# `run` carries the mutable state ops_python.py:52-157 keeps in four locals: the
# `values` dict, the buffer bytearrays, `exec_masks`, and `pbufs`/`pvals`. Under
# the rules above that is one `Prog` record threaded through a fuel recursion.
#
#   * THE PC IS A LOOP, NOT A RECURSION. Python is `while i < len(self.uops)`
#     with `BACKEDGE`/`END`/`RANGE` writing `i`. Bend has no loop and no
#     `continue`, so `run` is `run(fuel, pr)` with the PC threaded and a DIE on
#     fuel exhaustion -- which is also the "stay turing-incomplete" answer, since
#     a RANGE-driven kernel has no static step bound.
#   * THE ARENA IS STRIDED, NOT BUMP-ALLOCATED. Python's `values` is keyed by
#     UOp, so a RANGE body overwrites exactly the entries the first pass wrote
#     (ops_python.py:125-127 increments `values[u]` in place, and :129 `del`s
#     it). A bump allocator would append afresh on the second pass and the loop
#     would read its own history, so uop `i` owns a FIXED slot run -- see
#     `Uop.run_of.op` -- and a re-executed uop lands back on it.
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

# A signature's `List<T>` depth is FIXED, not inferred per call site
# (MEASURED), and `String.to_list` answers one lifetime DEEPER than its String
# while the byte store lives in the arena at `&2`. So the hex fold below is `&1`
# and `Prog.chars1` copies `&2` characters down to it -- Data elements move
# between depths for free, it is only the LIST that carries one.
def Prog.chars1(cs: List<&2, Char>, acc: List<&1, Char>) -> List<&1, Char>:
  match cs:
    case Nil{}: acc
    case h <> t: Prog.chars1(t, h <> acc)

# ...and `Prog.bytes1` copies the bytes back up into the arena, for the same
# reason. Two copies, ONE hex fold.
def Prog.bytes1(cs: List<&1, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case h <> t: Prog.bytes1(t, h <> acc)

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
# that dance. See `Prog.chars1` for the one depth hop this needs.
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
# THE STRIDE IS FIXED AT PARSE TIME, which is what THE SHAPE OF THE MACHINE's second
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

# MEASURED: a STACK's run is its src count, a LOAD's and a STORE's are their lane
# count (`k:vec:`), and every other op's is 1 -- which is the scalar case
# ops_python has too, since a `-` arg is what a LOAD with `max_numel() == 1`
# writes.
#
# AND `-` IS ONE LANE, NOT ZERO. The wire spells the scalar case `-`, which parses
# to `a == 0`, and a run of 0 makes the LOAD write no lane and the STORE store
# none -- the uop then shares its slot with the next one (MEASURED: a straight
# line `LOAD; STORE` packet answered 0, and a vec-4 STORE wrote one element per
# pass instead of four). `Uop.vec` is that floor.
#
# A RANGE OWNS TWO SLOTS, and the second is why. ops_python.py:124 reads
# `if u not in values: values[u] = [0]` ELSE `values[u][j] += 1`, and the arena is
# zeroed, so "never visited" and "visited with value 0" are the SAME cell. One
# slot cannot tell them apart: incrementing unconditionally makes the body read
# 1..trip where ops_python has it read 0..trip-1, and the last pass then indexes
# one element past the end. So slot+1 is the visited flag.
def Uop.vec(+u: Uop) -> U32: Bool.pick(U32, U32.is_eq(Uop.a(u), 0), 1, Uop.a(u))

def Uop.run_of.op(+op: O.Op, +u: Uop) -> U32:
  Bool.pick(U32, O.op_in([O.OpsLOAD{}, O.OpsSTORE{}], op), Uop.vec(u),
    Bool.pick(U32, O.eq_op(op, O.OpsSTACK{}), Uop.nsrc(u),
      Bool.pick(U32, O.eq_op(op, O.OpsRANGE{}), 2, 1)))

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
# the accessors Arg's remaining fields need; see the note above the
# Arg block.
type Arg is Data:
  Arg{kind: U32, x: U32, y: U32}

def Arg.kind(+g: Arg) -> U32:
  match g:
    case Arg{kind, x, y}: kind

def Arg.x(+g: Arg) -> U32:
  match g:
    case Arg{kind, x, y}: x

def Arg.y(+g: Arg) -> U32:
  match g:
    case Arg{kind, x, y}: y

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


# the accessors Load's remaining fields need; see the note above the
# Load block.
def Load.us(+l: Load) -> List<&2, Uop>:
  match l:
    case Load{us, fs, ms, v0, n, nb}: us

def Load.fs(+l: Load) -> List<&2, Buf>:
  match l:
    case Load{us, fs, ms, v0, n, nb}: fs

def Load.ms(+l: Load) -> List<&2, U32>:
  match l:
    case Load{us, fs, ms, v0, n, nb}: ms

def Load.v0(+l: Load) -> List<&2, Elem>:
  match l:
    case Load{us, fs, ms, v0, n, nb}: v0

def Load.n(+l: Load) -> U32:
  match l:
    case Load{us, fs, ms, v0, n, nb}: n

def Load.nb(+l: Load) -> U32:
  match l:
    case Load{us, fs, ms, v0, n, nb}: nb

def Prog.bases.next(+f: Buf, +at: U32) -> U32: U32.add(at, U32.mul(Buf.w(f), Buf.e(f)))

def Prog.bases.put(+fs: List<&2, Buf>, +at: U32) -> List<&2, Buf>:
  match fs:
    case Nil{}: Nil{}
    # PREPENDED, not appended: a buffer id is an INDEX into this list (A1), so
    # the list has to come out in `fs`'s own order. `List.append(tail, [f])`
    # would reverse it and every id after the first would name the wrong buffer.
    case f <> t: Buf{at, Buf.w(f), Buf.e(f)} <> Prog.bases.put(t, Prog.bases.next(f, at))

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

# the accessors Build's remaining fields need; see the note above the
# Build block.
def Build.nbp(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: nbp

def Build.pn(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: pn

def Build.sbn(+b: Build) -> U32:
  match b:
    case Build{us, sp, ss, bp, nu, nb, nbp, sbn, pn, slot, ok}: sbn

# ONE list, walked once: the packet buffers FIRST (by A1 they are buffer ids
# 0..nb-1 and the store holds them in that order) and the scratch ones after, so
# a buffer id is an INDEX into `fs` and `Buf.at` needs no arithmetic. Assigning
# the two lists separately would leave the packet buffers out of `fs` entirely,
# and every load and store would read the bottom buffer.
def Prog.bases(+b: Build) -> List<&2, Buf>:
  Prog.bases.put(List.append(&2, Buf, Build.sp(b), Build.ss(b)), 0)

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
  Prog.zeros(List.drop(&2, Buf, fs, U32.to_nat(Build.nb(b))), Build.bp(b))

def Prog.load.put(+b: Build, us: List<&2, Uop>, +fs: List<&2, Buf>) -> Load:
  Load{us, fs, Prog.bytes(b, fs), List.replicate(Elem, U32.to_nat(Build.slot(b)), Elem.zero()),
       Build.nu(b), Build.nb(b)}

def Prog.load.go(+ok: Bool, +b: Build, us: List<&2, Uop>, fs: List<&2, Buf>) -> Maybe<&2, Load>:
  match ok:
    case True{}: Some{Prog.load.put(b, us, fs)}
    case False{}: None{}

def Prog.load.at(+b: Build, us: List<&2, Uop>, fs: List<&2, Buf>, +ok: Bool) -> Maybe<&2, Load>:
  Prog.load.go(ok, b, us, fs)

def Prog.load(+b: Build) -> Maybe<&2, Load>:
  Prog.load.at(b, List.reverse(&2, Uop, Build.us(b)), Prog.bases(b), Build.ok(b))

# `nu` is the header's OWN uop count, not a running total: `Prog.parse.at` uses
# `k <= nu` to tell a uop line from a buffer line, so it has to be the count the
# header stated (32 in the measured packets), and `pn` is the running number of
# uops actually parsed.
def Prog.hdr.put(+b: Build, +named: Bool, +some: Bool, +nu: U32, +nb: U32) -> Build:
  Build{Build.us(b), Build.sp(b), Build.ss(b), Build.bp(b), nu, nb, Build.nbp(b), Build.sbn(b), Build.pn(b), Build.slot(b),
        Bool.and(Build.ok(b), Bool.and(named, some))}

# ===========================================================================
# ONE UOP LINE, IN ONE PASS over its words: 1 the op, 2 the dtype, 3 the arg,
# 4.. the srcs. The `<idx>:` field is not read, because ops_bend.encode walks the
# renderer's own list in order and asserts post-order -- a line's POSITION is the
# index its srcs name. A fifth src is refused: measured max 4, and only a STACK
# gets near it.
# ===========================================================================

def Prog.hdr.of(+ws: List<&2, String>, +b: Build) -> Build:
  Prog.hdr.put(b, String.eq(w(ws, 0n), "bendexec1"), U32.is_gt(num_of(num(w(ws, 1n))), 0),
    num_of(num(w(ws, 1n))), num_of(num(w(ws, 2n))))

# `bendexec1 <nuops> <nbuffers>`, read as strictly as the rest
def Prog.hdr(l: String, +b: Build) -> Build: Prog.hdr.of(words(l), b)

def Uop.refused(+u: Uop) -> Bool: U32.is_ge(Uop.kind(u), 14)

# `slot` is the slot THIS uop owns, and the Build's next-free slot is
# `slot + Uop.run(u)` -- a uop that owns a RUN of cells (a vector LOAD, a STACK, or
# a RANGE with its visited flag) has to advance the counter by its whole run.
# Storing `slot` instead is right only while every run is 1, and it silently makes
# the next uop's first cell the current uop's second.
def Prog.one.put(+b: Build, +slot: U32, +u: Uop, +ok: Bool) -> Build:
  Build{u <> Build.us(b), Build.sp(b), Build.ss(b), Build.bp(b), Build.nu(b), Build.nb(b), Build.nbp(b), Build.sbn(b), U32.add(Build.pn(b), 1),
        U32.add(slot, Uop.run(u)), Bool.and(Build.ok(b), ok)}

def Prog.alloc.ss(+b: Build, +f: Buf) -> Build:
  Build{Build.us(b), Build.sp(b), List.append(&2, Buf, Build.ss(b), [f]), Build.bp(b), Build.nu(b), Build.nb(b), Build.nbp(b),
        U32.add(Build.sbn(b), 1), Build.pn(b), Build.slot(b), Build.ok(b)}

def Prog.w(+u: Uop) -> U32: S.Dt.itemsize(Uop.dt(u))

def Prog.alloc.sp(+b: Build, +f: Buf) -> Build:
  Build{Build.us(b), List.append(&2, Buf, Build.sp(b), [f]), Build.ss(b), Build.bp(b), Build.nu(b), Build.nb(b), U32.add(Build.nbp(b), 1),
        Build.sbn(b), Build.pn(b), Build.slot(b), Build.ok(b)}

def Prog.alloc.at(+u: Uop, +b: Build, +scratch: Bool) -> Build:
  Bool.pick(Build, scratch, Prog.alloc.ss(b, Buf.make(Prog.w(u), Uop.a(u))),
    Prog.alloc.sp(b, Buf.make(Prog.w(u), Uop.a(u))))

# addrspace r (4) and a BUFFER (5) allocate scratch; g (2) and l (3) bind a packet
# buffer; a (6) reads a `vals` entry and binds NO buffer.
def Prog.scratch(+u: Uop) -> Bool: Bool.or(U32.is_eq(Uop.kind(u), 4), U32.is_eq(Uop.kind(u), 5))

# THE KINDS THAT BIND A BUFFER, and nothing else. ops_python.py:99-105 binds a
# buffer on exactly two arms -- PARAM and BUFFER -- and every other arm writes
# `values[u]` only. A uop that binds nothing must append NOTHING: the buffer
# table is indexed by buffer id (A1), so an extra entry would shift every id
# after it and every load and store would read the wrong bytes.
def Prog.binds(+u: Uop) -> Bool:
  Bool.or(Bool.or(U32.is_eq(Uop.kind(u), 2), U32.is_eq(Uop.kind(u), 3)),
    Bool.or(U32.is_eq(Uop.kind(u), 4), U32.is_eq(Uop.kind(u), 5)))

def Prog.alloc.at2(+u: Uop, +b: Build, +binds: Bool) -> Build:
  match binds:
    case True{}: Prog.alloc.at(u, b, Prog.scratch(u))
    case False{}: b

def Prog.alloc(+u: Uop, +b: Build) -> Build: Prog.alloc.at2(u, b, Prog.binds(u))

def Prog.pkt(+u: Uop) -> Bool: Bool.or(U32.is_eq(Uop.kind(u), 2), U32.is_eq(Uop.kind(u), 3))

# A1: the packet buffers are the PARAMs of addrspace g or l in uop order, so
# their ids are 0..nb-1 in that order and PACKET.out is written back in it. The
# scratch a PARAM of addrspace r or a BUFFER allocates takes the ids after those,
# so it can never be mistaken for a packet buffer on the way out.
def Prog.one.bid(+u: Uop, +b: Build) -> U32:
  Bool.pick(U32, Prog.pkt(u), Build.nbp(b), U32.add(Build.nb(b), Build.sbn(b)))

# THE REFUSALS. `Uop.refused` is the whole of the parse's validation, so the walk
# never has to know a kind exists that it cannot answer.
# THE SLOT the uop owns is the next-free slot, so the uop and the Build agree on
# where the next one starts.
def Prog.one.two(+u: Uop, +b: Build) -> Build:
  Prog.one.put(Prog.alloc(u, b), Build.slot(b),
    Uop.slot1(u, Build.slot(b), Prog.one.bid(u, b)), Bool.not(Uop.refused(u)))

def Prog.one.no(+b: Build) -> Build:
  Build{Build.us(b), Build.sp(b), Build.ss(b), Build.bp(b), Build.nu(b), Build.nb(b), Build.nbp(b), Build.sbn(b), U32.add(Build.pn(b), 1), Build.slot(b), False{}}

def Prog.one.of(m: Maybe<&2, Uop>, +b: Build) -> Build:
  match m:
    case Some{+u}: Prog.one.two(u, b)
    case None{}: Prog.one.no(b)

# ===========================================================================
# THE LOADED PACKET: the bases, the store, the arena, and the counts that have to
# agree with the header.
# ===========================================================================

# ===========================================================================
# A HEX STRING IS READ BY POSITION, and that is the whole point of this block.
# Byte k is characters 2k and 2k+1, high nibble first. Any other order is wrong
# in a way the round trip hides: `Prog.line` writes nibbles back the same way it
# read them, so a PURE COPY of a buffer looks perfect while the arena holds
# nonsense (MEASURED: the buffer line `8 0000803f`, which is 1.0f, landed in the
# arena as the word 0xF3080000 -- both bytes nibble-swapped -- and only the
# arithmetic fixtures noticed).
#
# `bytes_of` cannot do this job. Its accumulator prepends, so it answers the
# bytes in REVERSE order and pairs the characters from wherever the walk starts;
# `Prog.chars1` and `Prog.bytes` each reverse around it and those two reversals
# cancel, which is why `bytes_of` is still right for its own callers and wrong
# here. A positional walk has no order to get wrong.
# ===========================================================================

# a missing or junk character is '0', whose value is 0 -- so a short hex line
# shortens the arena rather than refusing it, and the byte COUNT is what refuses
def Prog.hex.at(+cs: List<&2, Char>, k: Nat) -> Char:
  Maybe.default(&2, Char, List.get(&2, Char, cs, k), Char.from_u32(48))

def Prog.hex.nib(+cs: List<&2, Char>, k: Nat) -> U32:
  hexdig_val(Char.to_u32(Prog.hex.at(cs, k)))

def Prog.hex.byte(+cs: List<&2, Char>, +k: Nat) -> U32:
  U32.add(U32.mul(Prog.hex.nib(cs, Nat.mul(k, 2n)), 16),
    Prog.hex.nib(cs, Nat.add(Nat.mul(k, 2n), 1n)))

# PREPENDED, and `Prog.hex.app` below appends, so the block lands in wire order
# without a `List.reverse` anywhere: the two directions cancel inside one line.
def Prog.hex.go(+cs: List<&2, Char>, +k: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p: Prog.hex.go(cs, p, Prog.hex.byte(cs, p) <> acc)

def Prog.hex.app(bs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: acc
    case h <> t: Prog.hex.app(t, List.append(&2, U32, acc, [h]))

# `(Bool & List<U32>)` is a PAIR and may be consumed once, so it is destructured
# here rather than asked twice through `list_of`/`bytes_ok`. The bytes go up from
# `&1` into the arena's `&2` (see `Prog.bytes1`), which also reverses them --
# `Prog.bytes` reverses once more, and the arena sees them in wire order.
def Prog.hex.put(+b: Build, r: (Bool & List<&2, U32>)) -> Build:
  (ok, bs) = r
  Build{Build.us(b), Build.sp(b), Build.ss(b), Prog.hex.app(bs, Build.bp(b)), Build.nu(b), Build.nb(b), Build.nbp(b), Build.sbn(b),
        Build.pn(b), Build.slot(b), Bool.and(Build.ok(b), ok)}

def Prog.hex.of(+ws: List<&2, String>, +b: Build) -> Build:
  +cs = String.to_list(w(ws, 1n))
  +n = U32.from_nat(List.length(&2, Char, cs))
  Prog.hex.put(b, (U32.is_eq(n, U32.mul(2, Maybe.default(&2, U32, num(w(ws, 0n)), 0))),
    Prog.hex.go(cs, U32.to_nat(U32.div(n, 2)), Nil{})))

def Prog.hex(l: String, +b: Build) -> Build: Prog.hex.of(words(l), b)

# `<arg>`, BY ITS WIRE SPELLING. `String.split` on ':' gives the head and up to
# three fields, and a String is affine so each field is read exactly once --
# which is why every dispatch below is a `match` on a parameter rather than a
# Bool.pick over `String.eq`.

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




# `f:<hex>` is ops_bend's `struct.pack('<f', arg).hex()` -- the LITTLE-ENDIAN BYTES
# of one f32, eight characters -- so it is read by THE BUFFER PATH, verbatim: a
# synthetic `<4> <hex>` line through `Prog.hex`, then the same reversal
# `Prog.bytes` applies before the arena sees a byte, then `Mem.ld4`.
#
# Reusing `bytes_of` directly does NOT work. `Prog.chars1` and `Prog.bytes` each
# reverse around that fold and the two reversals cancel THERE; standalone, the
# constant came out a denormal no float add can see, so every `x + 2.0` answered
# plain `x` and changing the packet's constant to 10.0 changed nothing. Three
# readings were MEASURED wrong before this one: a left-to-right digit fold gives
# 0x00000040, a reversed string gives 0x04000000, and the bare buffer fold gives
# 4. Going through the line path is what makes the two agree by construction.
def Arg.hex(h1: String) -> Maybe<&2, U32>:
  +b = Prog.hex(String.concat(["4 ", h1]), Build.blank())
  Bool.pick(Maybe<&2, U32>, Build.ok(b), Some{Mem.ld4(Build.bp(b), 0)}, None{})

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

# the wire name of a uop's op, for the probes in .agents/slop -- a debug aid and
# nothing the walk depends on
def opname(op: O.Op) -> String:
  match op:
    case O.OpsBACKEDGE{}: "BACKEDGE"
    case O.OpsEND{}: "END"
    case O.OpsRANGE{}: "RANGE"
    case O.OpsINDEX{}: "INDEX"
    case O.OpsSHRINK{}: "SHRINK"
    case O.OpsLOAD{}: "LOAD"
    case O.OpsSTORE{}: "STORE"
    case O.OpsSTACK{}: "STACK"
    case O.OpsPARAM{}: "PARAM"
    case O.OpsCAST{}: "CAST"
    case O.OpsCONST{}: "CONST"
    case O.OpsSHL{}: "SHL"
    case O.OpsADD{}: "ADD"
    case O.OpsGROUP{}: "GROUP"
    case O.OpsSINK{}: "SINK"
    case _: "?"

def opname.of(+u: Uop) -> String: opname(Uop.op(u))

def show.k(+k: Nat) -> String: U32.show(U32.from_nat(k))

def bs(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

def elemname(+e: Elem) -> String:
  match e:
    case Bf{b}: String.concat(["Bf(", U32.show(b), ")"])
    case Sc{b, d}: String.concat(["Sc(", U32.show(b), ")"])
    case Rf{b, o, n}: String.concat(["Rf(buf=", U32.show(b), ",o=", U32.show(o), ",n=", bs(n), ")"])

def Uop.is_idx(+u: Uop) -> Bool: O.op_in([O.OpsINDEX{}, O.OpsSHRINK{}], Uop.op(u))

# A3's TWO ARMS ARE SPELLED THE SAME for `-`: `-` on an INDEX is the BUFFER arm
# with scale 1 (ops_python.py:121) and `k:idx:0` is the ALU arm (:114), and both
# reach `Arg.of3`'s default as `a == 0`. So the arm is chosen HERE, where the op
# is known, and `-` becomes scale 1 -- which makes `U32.is_eq(Uop.a(u), 0)` the
# ALU test in `Prog.index`. Without this the buffer arm is UNREACHABLE and every
# INDEX/SHRINK over a PARAM reads an arena slot instead of a buffer reference.
def Uop.of.arg3(+u: Uop, +g: Arg) -> Uop:
  Bool.pick(Uop, Bool.and(Uop.is_idx(u), U32.is_eq(Arg.kind(g), 0)),
    Uop.ak(u, 8, 1, 0), Uop.ak(u, Arg.kind(g), Arg.x(g), Arg.y(g)))

# `+g` because the arm reads all THREE fields: a plain pattern binding is affine.
def Uop.of.arg2(+u: Uop, m: Maybe<&2, Arg>) -> Uop:
  match m:
    case Some{+g}: Uop.of.arg3(u, g)
    case None{}: Uop.ak(u, 14, 0, 0)

def Uop.of.arg(+u: Uop, h: String) -> Uop: Uop.of.arg2(u, Arg.of(h))

# a src index: 1-based on the wire, 0-based here, refused when `U32.read` refuses
# the spelling. The bounds check is `Uop.at`'s: an index past the packet answers
# the bottom, and the bottom of an INDEX is the zero this walk then reads.
def Uop.of.sr(h: String) -> U32: U32.sub(num_of(num(h)), 1)

# TWO things are decided HERE, and both are why the walk cannot stop at the first
# src:
#   * every src is appended. A STACK has up to 4 and a GROUP four, and the END's
#     SECOND src is the loop head -- so a walk that returned after src 1 would
#     give every uop one src and `Uop.src1` the answer 0.
#   * the RUN is set ONCE, at the terminal, with the whole src list already in
#     place: a STACK's run is its src COUNT (`Uop.run_of`), so setting it after
#     the first src would make every STACK a run of 1.
# A line that runs out of words at k >= 4 is a complete uop -- ops_python has arms
# for PARAM and CONST that read no src at all. Too short to carry
# `<idx> <op> <dtype> <arg>` is a refusal, and so is a FIFTH src (measured max 4).
def Uop.of.go(ws: List<&2, String>, +k: Nat, +slot: U32, +u: Uop) -> Maybe<&2, Uop>:
  match ws k:
    case Nil{} 0n: None{}
    case Nil{} 1n: None{}
    case Nil{} 2n: None{}
    case Nil{} 3n: None{}
    case Nil{} _ : Some{Uop.run1(u)}
    case _ <> t 0n: Uop.of.go(t, 1n, slot, u)
    case h <> t 1n: Uop.of.go(t, 2n, slot, Uop.of.op(u, h))
    case h <> t 2n: Uop.of.go(t, 3n, slot, Uop.of.dt(u, h))
    case h <> t 3n: Uop.of.go(t, 4n, slot, Uop.of.arg(u, h))
    case h <> t 4n: Uop.of.go(t, 5n, slot, Uop.add(u, Uop.of.sr(h)))
    case h <> t 5n: Uop.of.go(t, 6n, slot, Uop.add(u, Uop.of.sr(h)))
    case h <> t 6n: Uop.of.go(t, 7n, slot, Uop.add(u, Uop.of.sr(h)))
    case h <> t 7n: Some{Uop.run1(Uop.add(u, Uop.of.sr(h)))}
    case _ <> t _ : None{}

def Uop.line(l: String, +slot: U32) -> Maybe<&2, Uop>:
  Uop.of.go(words(l), 0n, slot, Uop.bottom())

def Prog.one(l: String, +b: Build) -> Build: Prog.one.of(Uop.line(l, Build.slot(b)), b)

# `Bool.pick` computes both arms and this is a pure fold, so the wrong arm's work
# is discarded: cheaper than a match, and it keeps the phase test in one place. A
# buffer line parsed as a uop and a uop line parsed as hex both set ok False in
# the arm that gets thrown away.
# AN EMPTY LINE IS NOT A LINE. `String.lines` is `String.split(s, '\n')`, so the
# newline every packet ends with leaves a trailing "" behind, and no packet line
# is ever empty (the header is `bendexec1 ...`, a uop line is `<idx>: ...`, a
# buffer line is `<nbytes> <hex>`). Skipping empty lines is therefore reading the
# wire, not hiding a malformed packet.
#
# `k` is the line counter `Prog.parse.at` uses to tell a uop line from a buffer
# line, so an empty line must not move it -- hence the counter is a SEPARATE def
# rather than `U32.add(k, 1)` inline. It has to be separate because `h` is needed
# both for the counter and for the parse, and a `Bool.pick` holding both plus the
# recursion would be mutual recursion with `Prog.parse.go`, which Bend refuses.
def Prog.parse.k(+h: String, +k: U32) -> U32:
  Bool.pick(U32, String.is_empty(h), k, U32.add(k, 1))

def Prog.parse.at(+h: String, +k: U32, +b: Build) -> Build:
  Bool.pick(Build, String.is_empty(h), b,
    Bool.pick(Build, U32.is_eq(k, 0), Prog.hdr(h, b),
      Bool.pick(Build, U32.is_le(k, Build.nu(b)), Prog.one(h, b), Prog.hex(h, b))))

def Prog.parse.go(ls: List<&2, String>, +k: U32, +b: Build) -> Build:
  match ls:
    case Nil{}: b
    case +h <> t: Prog.parse.go(t, Prog.parse.k(h, k), Prog.parse.at(h, k, b))

def Prog.parse(s: String) -> Maybe<&2, Load>:
  Prog.load(Prog.parse.go(String.lines(s), 0, Build.blank()))

# ===========================================================================
# A BUFFER LINE, `<nbytes> <hex-bytes>`. Its bytes are consed onto `bp` in
# packet order and the whole run is reversed once at the end -- `List.set` per
# byte would be quadratic on a 2 KiB buffer.
# ===========================================================================

type Prog is Data:
  Prog{us: List<&2, Uop>, vs: List<&2, Elem>, v0: List<&2, Elem>, ms: List<&2, U32>,
       fs: List<&2, Buf>, mk: List<&2, Bool>, vals: List<&2, U32>, pc: U32, n: U32,
       pv: U32, gx: U32, gy: U32, gz: U32, cx: U32, cy: U32, cz: U32, bad: Bool,
       dead: Bool}

type Args is Data:
  Args{path: String, gx: U32, gy: U32, gz: U32, vals: List<&2, U32>, ok: Bool}

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

def Args.ok(+a: Args) -> Bool:
  match a:
    case Args{path, gx, gy, gz, vals, ok}: ok

def Args.blank() -> Args: Args{"", 1, 1, 1, Nil{}, True{}}

# argv[0] is the program itself and is SKIPPED (k == 0 hands `a` back
# unchanged); argv[1] is the packet (k == 1 takes `h`); argv[2..4] are the grid;
# everything after is a `vals` entry. A `String` is single-use, so `h` reaches
# exactly one arm.
def Args.at(+h: String, +k: U32, +a: Args) -> Args:
  Bool.pick(Args, U32.is_eq(k, 1), Args{h, Args.gx(a), Args.gy(a), Args.gz(a), Args.vals(a), Args.ok(a)},
    Bool.pick(Args, U32.is_eq(k, 0), a,
      Bool.pick(Args, U32.is_eq(k, 2), Args{Args.path(a), num_of(num(h)), Args.gy(a), Args.gz(a), Args.vals(a), Args.ok(a)},
        Bool.pick(Args, U32.is_eq(k, 3), Args{Args.path(a), Args.gx(a), num_of(num(h)), Args.gz(a), Args.vals(a), Args.ok(a)},
          Bool.pick(Args, U32.is_eq(k, 4), Args{Args.path(a), Args.gx(a), Args.gy(a), num_of(num(h)), Args.vals(a), Args.ok(a)},
            Args{Args.path(a), Args.gx(a), Args.gy(a), Args.gz(a), List.append(&2, U32, Args.vals(a), [num_of(num(h))]), Args.ok(a)})))))

def Args.go(as: List<String>, +k: U32, +a: Args) -> Maybe<&2, Args>:
  match as:
    case Nil{}: Some{a}
    case h <> t: Args.go(t, U32.add(k, 1), Args.at(h, k, a))

def Args.of(as: List<String>) -> Maybe<&2, Args>:
  Args.go(as, 0, Args.blank())


def Prog.us(+p: Prog) -> List<&2, Uop>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: us

def Prog.vs(+p: Prog) -> List<&2, Elem>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: vs

def Prog.v0(+p: Prog) -> List<&2, Elem>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: v0

def Prog.ms(+p: Prog) -> List<&2, U32>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: ms

def Prog.fs(+p: Prog) -> List<&2, Buf>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: fs

def Prog.mk(+p: Prog) -> List<&2, Bool>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: mk

def Prog.vals(+p: Prog) -> List<&2, U32>:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: vals

def Prog.pc(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: pc

def Prog.n(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: n

def Prog.pv(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: pv

def Prog.gx(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: gx

def Prog.gy(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: gy

def Prog.gz(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: gz

def Prog.cx(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: cx

def Prog.cy(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: cy

def Prog.cz(+p: Prog) -> U32:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: cz

def Prog.bad(+p: Prog) -> Bool:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: bad

def Prog.dead(+p: Prog) -> Bool:
  match p:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead}: dead

def Prog.of(+args: Args, +ld: Load) -> Prog:
  Prog{Load.us(ld), Load.v0(ld), Load.v0(ld), Load.ms(ld), Load.fs(ld), Nil{}, Args.vals(args), 0, Load.n(ld), 3, 0, 0, 0,
       Args.gx(args), Args.gy(args), Args.gz(args), False{}, False{}}

def Prog.at(+p: Prog, +pc: U32) -> Prog:
  Prog{Prog.us(p), Prog.vs(p), Prog.v0(p), Prog.ms(p), Prog.fs(p), Prog.mk(p), Prog.vals(p), pc, Prog.n(p), Prog.pv(p), Prog.gx(p), Prog.gy(p), Prog.gz(p),
       Prog.cx(p), Prog.cy(p), Prog.cz(p), Prog.bad(p), Prog.dead(p)}

def Prog.next(+p: Prog) -> Prog: Prog.at(p, U32.add(Prog.pc(p), 1))

def Prog.vs1(+p: Prog, vs: List<&2, Elem>) -> Prog:
  Prog{Prog.us(p), vs, Prog.v0(p), Prog.ms(p), Prog.fs(p), Prog.mk(p), Prog.vals(p), Prog.pc(p), Prog.n(p), Prog.pv(p), Prog.gx(p), Prog.gy(p), Prog.gz(p),
       Prog.cx(p), Prog.cy(p), Prog.cz(p), Prog.bad(p), Prog.dead(p)}

def Prog.ms1(+p: Prog, ms: List<&2, U32>) -> Prog:
  Prog{Prog.us(p), Prog.vs(p), Prog.v0(p), ms, Prog.fs(p), Prog.mk(p), Prog.vals(p), Prog.pc(p), Prog.n(p), Prog.pv(p), Prog.gx(p), Prog.gy(p), Prog.gz(p),
       Prog.cx(p), Prog.cy(p), Prog.cz(p), Prog.bad(p), Prog.dead(p)}

def Prog.mk1(+p: Prog, mk: List<&2, Bool>) -> Prog:
  Prog{Prog.us(p), Prog.vs(p), Prog.v0(p), Prog.ms(p), Prog.fs(p), mk, Prog.vals(p), Prog.pc(p), Prog.n(p), Prog.pv(p), Prog.gx(p), Prog.gy(p), Prog.gz(p),
       Prog.cx(p), Prog.cy(p), Prog.cz(p), Prog.bad(p), Prog.dead(p)}

def Prog.pv1(+p: Prog) -> Prog:
  Prog{Prog.us(p), Prog.vs(p), Prog.v0(p), Prog.ms(p), Prog.fs(p), Prog.mk(p), Prog.vals(p), Prog.pc(p), Prog.n(p), U32.add(Prog.pv(p), 1),
       Prog.gx(p), Prog.gy(p), Prog.gz(p), Prog.cx(p), Prog.cy(p), Prog.cz(p), Prog.bad(p), Prog.dead(p)}

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

# THE VISITED FLAG of a RANGE, in the slot after its counter (see Uop.run_of.op)
def Prog.flag.put(+p: Prog, +u: Uop) -> Prog:
  Prog.vs1(p, Val.put(Prog.vs(p), U32.add(Uop.slot(u), 1), elem_of(1, Uop.dt(u))))

# THE VALUE THIS VISIT LEAVES BEHIND, and it is the value ops_python's exit test
# sees. On the first visit `values[u] = [0]` and does NOT increment; after it
# every visit adds 1 -- and the test `values[u][0] == src_values[0][0]` runs on
# THAT. So the counter left behind is 0, 1, 2, 3 for the four body passes and 4
# on the fifth, which exits: the body reads 0..trip-1, and a body that read trip
# would index one element past the end of its buffer. Testing the OLD counter
# instead is the off-by-one that puts `trip` in the last pass.
def Prog.rng.nxt(+p: Prog, +u: Uop, +seen: Bool) -> U32:
  Bool.pick(U32, seen, U32.add(Prog.cur(p, u), 1), Prog.cur(p, u))

# THE FIRST VISIT SETS THE FLAG AND LEAVES THE COUNTER; every visit after it
# stores the incremented counter.
def Prog.rng.put(+p: Prog, +u: Uop, +seen: Bool, +nxt: U32) -> Prog:
  Bool.pick(Prog, seen, Prog.put(p, u, elem_of(nxt, Uop.dt(u))), Prog.next(Prog.flag.put(p, u)))

def Prog.seen(+p: Prog, +u: Uop) -> Bool:
  Elem.is_true(Val.at(Prog.vs(p), U32.add(Uop.slot(u), 1)))

def Prog.rng.over(+p: Prog, +u: Uop, +over: Bool, +seen: Bool, +nxt: U32) -> Prog:
  match over:
    case True{}: Prog.at(p, U32.add(Prog.loop(p, Prog.pc(p)), 1))
    case False{}: Prog.rng.put(p, u, seen, nxt)

# ===========================================================================
# :73-78 IF/ENDIF. `exec_masks` is a stack of "one Bool per work item" (the warp
# is 1 here), so an IF pushes the conjunction of the top and the condition and an
# ENDIF pops. ops_python skips VOID srcs when it builds `src_values`, and
# MEASURED the only op with a void src is an AFTER, whose first src is never void
# -- so the filter has no other place to show up and is not spelled.
# ===========================================================================

def Prog.trip(+p: Prog, +u: Uop) -> U32: Elem.bits(Prog.src(p, u, 0n))

def Prog.rng.at(+p: Prog, +u: Uop, +void: Bool, +seen: Bool, +nxt: U32) -> Prog:
  match void:
    case True{}: Prog.next(p)
    case False{}: Prog.rng.over(p, u, U32.is_eq(nxt, Prog.trip(p, u)), seen, nxt)

def Prog.rng(+p: Prog, +u: Uop) -> Prog:
  Prog.rng.at(p, u, U32.is_eq(S.Dt.itemsize(Uop.dt(u)), 0), Prog.seen(p, u),
    Prog.rng.nxt(p, u, Prog.seen(p, u)))

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
  Prog.next(Prog.mk1(p, Bool.and(Prog.open(p), Elem.is_true(Prog.src(p, u, 0n))) <> Prog.mk(p)))

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

# `src_values[0][i][0]` (ops_python.py:114) -- the lane-0 element of a vector
# LOAD at ELEMENT index `i`, and `i` comes from `enumerate(src_values[1])`, so
# it is src 1's value; src 0's value is the element COUNT and reads one run past
# the end. Both indices are 0 at LOCAL SIZE 1 (see below), so `i` is the whole
# offset.
def Prog.index.alu(+p: Prog, +u: Uop) -> Elem:
  Val.at(Prog.vs(p), U32.add(Prog.slot(p, u, 0n), Elem.bits(Prog.src(p, u, 1n))))

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
# `zip(src_values[0], src_values[1])` (ops_python.py:121) pairs the BUFFER
# REFERENCE with the OFFSET, so the offset is src 1 -- not src 0, which is the
# buffer reference itself.
def Prog.index.mem(+p: Prog, +u: Uop) -> Elem:
  Prog.index.rf(Elem.buf(Prog.src(p, u, 0n)), Elem.off(Prog.src(p, u, 0n)),
    Elem.off_none(Prog.src(p, u, 0n)), Elem.bits(Prog.src(p, u, 1n)), Uop.a(u))

def Prog.index.at(+p: Prog, +u: Uop, +alu: Bool) -> Prog:
  Prog.put(p, u, Bool.pick(Elem, alu, Prog.index.alu(p, u), Prog.index.mem(p, u)))

def Prog.index(+p: Prog, +u: Uop) -> Prog: Prog.index.at(p, u, U32.is_eq(Uop.a(u), 0))

def Prog.stack.copy(es: List<&2, Elem>, +vs: List<&2, Elem>, +slot: U32, +k: Nat) ->
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

def Prog.stack.at(ss: List<&2, U32>, +vs: List<&2, Elem>, +us: List<&2, Uop>,
  acc: List<&2, Elem>) -> List<&2, Elem>:
  match ss:
    case Nil{}: acc
    case s <> t: Prog.stack.at(t, vs, us, List.append(&2, Elem, acc,
      [Val.at(vs, Uop.slot(Uop.at(us, s)))]))

def Prog.stack(+p: Prog, +u: Uop) -> Prog:
  Prog.next(Prog.vs1(p, Prog.stack.copy(Prog.stack.at(Uop.srcs(u), Prog.vs(p), Prog.us(p), Nil{}),
    Prog.vs(p), Uop.slot(u), 0n)))

def Prog.cast.dt(+dst: S.Dt, src: S.Dt, +e: Elem) -> Elem:
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
  Prog{Prog.us(p), Prog.vs(p), Prog.v0(p), Prog.ms(p), Prog.fs(p), Prog.mk(p), Prog.vals(p), Prog.pc(p), Prog.n(p), Prog.pv(p), Prog.gx(p), Prog.gy(p), Prog.gz(p),
       Prog.cx(p), Prog.cy(p), Prog.cz(p), Bool.or(Prog.bad(p), oob), Prog.dead(p)}

def Prog.lane.of(+f: Buf, +dt: S.Dt) -> U32:
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

# EVERY ARM ADVANCES THE PC. ops_python.py:156 ends each iteration with `i += 1`,
# so an arm that only writes `values[u]` still has to step -- and five of them
# (IF, ENDIF, STACK, LOAD, STORE) build the new state without going through
# `Prog.put`, which is where the step lives. Without the explicit `Prog.next`
# the walk revisits the same uop forever and the launch dies of fuel.
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

# the storage element index of lane j, `o + j*_step`. A STORE's `_step` is
# `src_dtypes[1]` (ops_python.py:90) -- the VALUE's dtype -- and not the STORE's
# own, which is void and would floor every lane step at 1.
def Prog.store.i(+p: Prog, +u: Uop, +j: U32) -> U32:
  U32.add(Elem.off(Prog.src(p, u, 0n)),
    U32.mul(j, Prog.lane.of(Prog.buf(p, u), Prog.dt(p, u, 1n))))

# ONE def, not two: the step reads lane j of `n` and recurses on `n - 1`, so a
# separate `oob.go` would be a forward reference with nothing to gain.
#
# `match` AND NOT `Bool.pick`, MEASURED: `Bool.pick` evaluates its condition
# before its arms, so by the time the self-call is reached the countdown has
# already been read and the call is not decreasing. A `match` binds `n` and hands
# the tail to the arm. `q` is the shrinking argument and comes first.
def Prog.oob(+p: Prog, +u: Uop, +j: U32, +n: Nat) -> Bool:
  match n:
    case 0n: False{}
    case 1n+q: Bool.or(U32.is_ge(Prog.store.i(p, u, j), Buf.e(Prog.buf(p, u))), Prog.oob(p, u, j, q))

# THE POISON. ops_python raises IndexError on a load or a store past the end of a
# buffer (:17, :28); Bend answers a default instead, so the check runs here and
# the launch is refused at the end rather than answering a plausible wrong number.
def Prog.live(+p: Prog, +u: Uop) -> Prog:
  Prog.live.at(p, Prog.oob(p, u, 0, U32.to_nat(Uop.run(u))))

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

def Prog.ld.three(+u: Uop) -> Bool: U32.is_eq(Uop.nsrc(u), 3)

def Prog.ld.lane(+p: Prog, +u: Uop, +j: U32) -> Elem:
  Prog.ld.gate(Prog.ld.read(p, u, Prog.src(p, u, 0n), j), Prog.ld.three(u),
    Prog.src(p, u, 1n), Elem.is_true(Prog.src(p, u, 2n)))

# `n` is the FIRST parameter because the store list is REBUILT each step, and a
# recursive call's arguments are read left to right: nothing rebuilt may come
# before the one that shrinks (MEASURED).
def Prog.ld.at(+n: Nat, +u: Uop, vs: List<&2, Elem>, +j: U32, +p: Prog) -> List<&2, Elem>:
  match n:
    case 0n: vs
    case 1n+q: Prog.ld.at(q, u, Val.put(vs, U32.add(Uop.slot(u), j), Prog.ld.lane(p, u, j)),
      U32.add(j, 1), p)

def Prog.ld1(+p: Prog, +u: Uop) -> Prog:
  Prog.next(Prog.live(Prog.vs1(p, Prog.ld.at(U32.to_nat(Uop.run(u)), u, Prog.vs(p), 0, p)), u))

# ops_python's `if g:` -- a masked-off store does not write, and the write itself
# is computed and discarded rather than branched over (Bool.pick is not a branch)
def Prog.store.go(ms: List<&2, U32>, done: List<&2, U32>, +open: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, open, done, ms)

def Prog.store.addr(+p: Prog, +u: Uop, +j: U32) -> U32:
  U32.add(Buf.base(Prog.buf(p, u)), U32.mul(Prog.store.i(p, u, j), Buf.w(Prog.buf(p, u))))

# lane j of the value run: the 1st src's own run, indexed
def Prog.store.v(+p: Prog, +u: Uop, +j: U32) -> U32:
  Elem.bits(Val.at(Prog.vs(p), U32.add(Prog.slot(p, u, 1n), j)))

# THE ACCUMULATED BYTE LIST, not `Prog.ms(p)`. Every lane must see the previous
# lanes' writes: reading the arena afresh per lane makes each write a copy of the
# ORIGINAL and only the LAST lane survives, so a vec-4 store laid down one element
# per pass with the last lane's value (MEASURED: `elementwise_add` wrote 6, 10,
# 14, 18 at indices 3, 7, 11, 15 where it wanted 3..18).
def Prog.store.lane.at(+ms: List<&2, U32>, +p: Prog, +u: Uop, +j: U32) -> List<&2, U32>:
  Mem.st(ms, Prog.store.addr(p, u, j), Buf.w(Prog.buf(p, u)), Prog.store.v(p, u, j))

def Prog.store.open(+p: Prog, +u: Uop, +j: U32) -> Bool:
  Bool.and(Prog.open(p), U32.is_lt(Prog.store.i(p, u, j), Buf.e(Prog.buf(p, u))))

# `_store(m, o + j*_step, v, src_dtypes[1])` -- `to_storage_scalar` is the
# identity for the three 4-byte lanes and `bool(x)` for bool
def Prog.store.lane(+ms: List<&2, U32>, +p: Prog, +u: Uop, +j: U32) -> List<&2, U32>:
  Prog.store.go(ms, Prog.store.lane.at(ms, p, u, j), Prog.store.open(p, u, j))

# `n` FIRST for the same reason as `Prog.ld.at`: the byte list is rebuilt each step.
def Prog.store.at(+n: Nat, +u: Uop, ms: List<&2, U32>, +j: U32, +p: Prog) -> List<&2, U32>:
  match n:
    case 0n: ms
    case 1n+q: Prog.store.at(q, u, Prog.store.lane(ms, p, u, j), U32.add(j, 1), p)

def Prog.store(+p: Prog, +u: Uop) -> Prog:
  Prog.next(Prog.live(Prog.ms1(p, Prog.store.at(U32.to_nat(Uop.run(u)), u, Prog.ms(p), 0, p)), u))

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
    case O.OpsENDIF{}: Prog.next(Prog.mk1(p, List.tail(&2, Bool, Prog.mk(p))))
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

# `Prog.over` -- ops_python's `while i < len(self.uops)` -- is `pc >= n`, and it
# lives in its own def because a computed Bool may only be read as a `Bool.pick`
# GUARD, never as a `match` scrutinee.
def Prog.over(+pr: Prog) -> Bool: U32.is_ge(Prog.pc(pr), Prog.n(pr))

# `dead` is set here and nowhere else: a work item asked for more steps than
# FUEL allows. ops_python has no such bound -- a RANGE-driven kernel has no
# static step count -- so this is the "stay turing-incomplete" guard, and it
# refuses the launch instead of answering a plausible wrong number.
def Prog.die(+pr: Prog) -> Prog:
  Prog{Prog.us(pr), Prog.vs(pr), Prog.v0(pr), Prog.ms(pr), Prog.fs(pr), Prog.mk(pr),
       Prog.vals(pr), Prog.pc(pr), Prog.n(pr), Prog.pv(pr), Prog.gx(pr), Prog.gy(pr),
       Prog.gz(pr), Prog.cx(pr), Prog.cy(pr), Prog.cz(pr), Prog.bad(pr), True{}}

# ONE def for the whole loop, and it has to be ONE: Bend refuses mutual
# recursion, so `run` and a separate `run.at` cannot both exist. The shape that
# works is MEASURED, not guessed:
#   * `match` on the FUEL, with the termination test as the `Bool.pick` GUARD.
#   * the countdown comes FIRST in the self-call: arguments are read left to
#     right and nothing rebuilt may precede the one that shrinks, and
#     `Prog.step(pr)` is rebuilt.
#   * `+pr` because `Bool.pick` evaluates both arms and each consumes `pr`.
def run(+f: Nat, +pr: Prog) -> Prog:
  match f:
    case 0n: Prog.die(pr)
    case 1n+k: Bool.pick(Prog, Prog.over(pr), pr, run(k, Prog.step(pr)))

# ===========================================================================
# THE GRID, :56 -- `for idxs in itertools.product(*[range(x) for x in
# global_size[::-1]])`. gz varies fastest and `idxs` is (z, y, x), so the first
# work item is (0,0,0) and the odometer carries gz. `values`, `exec_masks`,
# `pvals` and the pc are RESET per work item and the buffers are not, which is
# what makes a second work item accumulate into the first one's stores.
# ===========================================================================

def Prog.count(+args: Args) -> Nat: Nat.mul(U32.to_nat(Args.gx(args)), Nat.mul(U32.to_nat(Args.gy(args)), U32.to_nat(Args.gz(args))))

def Prog.reset(+pr: Prog) -> Prog: Prog.at(Prog.vs1(Prog.mk1(pr, Nil{}), Prog.v0(pr)), 0)

def Prog.carry(+pr: Prog, +oz: Bool) -> Prog:
  Prog{Prog.us(pr), Prog.vs(pr), Prog.v0(pr), Prog.ms(pr), Prog.fs(pr), Prog.mk(pr), Prog.vals(pr), Prog.pc(pr), Prog.n(pr), Prog.pv(pr),
       Bool.pick(U32, oz, U32.add(Prog.gx(pr), 1), Prog.gx(pr)),
       Bool.pick(U32, oz, 0, U32.add(Prog.gy(pr), 1)),
       Bool.pick(U32, oz, U32.add(Prog.gz(pr), 1), 0),
       Prog.cx(pr), Prog.cy(pr), Prog.cz(pr), Prog.bad(pr), Prog.dead(pr)}

def Prog.tick(+pr: Prog) -> Prog: Prog.reset(Prog.carry(pr, U32.is_ge(U32.add(Prog.gz(pr), 1), Prog.cz(pr))))


# ONE def, like `run`: a separate def to resolve `run`'s answer would be mutual
# recursion. The work-item count shrinks and `Prog.tick(run(FUEL(), pr))` is
# rebuilt, so the count comes first. A work item that ran out of fuel sets
# `dead`, and `Prog.launch.grid` refuses the launch on it.
def grid(+n: Nat, +pr: Prog) -> Prog:
  match n:
    case 0n: pr
    case 1n+k: grid(k, Prog.tick(run(FUEL(), pr)))

# ===========================================================================
# THE COMMAND LINE. `IO.args()` is affine, so it is read ONCE, in order, and the
# whole answer is one record: argv[0] is the program (skipped), argv[1] the
# packet, argv[2..4] the grid, and everything after is `vals`. `pv` starts at 3
# because the first three numbers are the grid.
# ===========================================================================

# ===========================================================================
# THE ENTRY POINT: `bend-executor PACKET gx gy gz vals...`, which reads PACKET,
# runs every work item, and writes PACKET.out beside it.
# ===========================================================================

def SLASH() -> Char: Char.from_u32(47)

# A '/' at index `at` means the directory runs to `at + 1`, so `best` becomes
# `at + 1` -- the character index JUST PAST the last slash, which is the length of
# the directory prefix. This is a leaf def so that the walk below makes exactly
# ONE recursive call per character.
def Prog.write.slash.hit(+h: Char, +at: U32, +best: U32) -> U32:
  Bool.pick(U32, Char.is_eq(h, SLASH()), U32.add(at, 1), best)

# ONE def, not two. `Prog.write.slash.at` and `.go` were a 2-def cycle, which
# Bend refuses (MEASURED). And the test is NOT a `Bool.pick` in the walk:
# `Bool.pick` evaluates both arms, so a recursive call in each arm would branch
# the walk twice over -- exponential in the path length. Hence the leaf def.
#
# MEASURED, and the reason the countdown `n` is gone: the old pair threaded a
# countdown that `.at` passed on UNCHANGED, so every step took the `0n` arm,
# `at` was pinned at 0, and `best` was always 0. `List.take` (not `drop`) is
# what keeps the directory: `String.drop` removes the FIRST n characters.
def Prog.write.slash(+cs: List<&2, Char>, +at: U32, +best: U32) -> U32:
  match cs:
    case Nil{}: best
    case h <> t: Prog.write.slash(t, U32.add(at, 1), Prog.write.slash.hit(h, at, best))

# the directory of the packet's path, which is where PACKET.out goes
def Prog.write.out(+path: String) -> String:
  String.concat([String.take(path,
    U32.to_nat(Prog.write.slash(String.to_list(path), 0, 0))), "PACKET.out"])

def Prog.line.hex(cs: List<&2, Char>) -> String: String.from_list(cs)

# `h <> t` is the CONS; `[h] <> t` is a list literal followed by a cons and is
# refused (MEASURED). Two digits, low byte first, into the reversed accumulator.
# A nibble above 9 is a LETTER: 87 is 'a' - 10, so `87 + v` lands on a..f. Adding
# 48 unconditionally would answer '?' for 15 and write a byte ops_python never
# could read back.
def Prog.line.dig(+v: U32) -> Char:
  Bool.pick(Char, U32.is_lt(v, 10), Char.from_u32(U32.add(48, v)), Char.from_u32(U32.add(87, v)))

def Prog.line.put2(acc: List<&2, Char>, +v: U32) -> List<&2, Char>:
  Prog.line.dig(v) <> acc

# THE HIGH NIBBLE IS PUSHED FIRST, because the accumulator prepends and the block
# is reversed once at the end. Pushing the low nibble first wrote every byte
# DIGIT-SWAPPED -- 0x3f as "f3" -- and, because the reader was digit-swapped in
# the same way, the two cancelled on a pure COPY and every copy fixture passed
# while every ARITHMETIC one computed on nonsense (MEASURED: a LOAD of 1.0 read
# back as 0xF3080000). This is the whole difference between the two hex paths.
def Prog.line.put(acc: List<&2, Char>, +b: U32) -> List<&2, Char>:
  Prog.line.put2(Prog.line.dig(U32.div(b, 16)) <> acc, U32.mod(b, 16))

def Prog.line.go(+ms: List<&2, U32>, +n: Nat, +at: U32, acc: List<&2, Char>) -> List<&2, Char>:
  match n:
    case 0n: acc
    case 1n+p: Prog.line.go(ms, p, U32.add(at, 1), Prog.line.put(acc, Mem.byte(ms, at)))
def Prog.line(+f: Buf, +ms: List<&2, U32>) -> String:
  String.concat([U32.show(U32.mul(Buf.w(f), Buf.e(f))), " ",
    Prog.line.hex(List.reverse(&2, Char,
      Prog.line.go(ms, U32.to_nat(U32.mul(Buf.w(f), Buf.e(f))), Buf.base(f), Nil{}))), "\n"])

# THE BUFFER BLOCK, in buffer-id order, which is the order ops_bend hands the
# buffers in (A1). The walk counts DOWN from `nb`, so the index is `nb - n` and
# NOT the countdown itself: reading the countdown as the index writes the LAST
# buffer first, and a reversed PACKET.out silently mislabels every readback
# (MEASURED: the two packet lines came back the wrong way round).
def Prog.out.at(+fs: List<&2, Buf>, +ms: List<&2, U32>, +nb: Nat, +n: Nat,
  acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+q: Prog.out.at(fs, ms, nb, q,
      Prog.line(Buf.at(fs, U32.from_nat(Nat.sub(nb, Nat.add(q, 1n)))), ms) <> acc)

# the buffer block, the first `nb` buffers of `fs` -- which are the packet's, by
# buffer id (A1). `nb` is an ARGUMENT and not a Prog field: it is a constant of
# the parsed packet, so the machine state carries the buffers without carrying
# how many of them the packet had.
#
# The block is a plain CONCATENATION, because every `Prog.line` already ends in
# its own newline and `String.concat` joins with nothing. Appending a separator
# -- which the old `Prog.out.join` did -- put a THIRD, empty line in PACKET.out,
# which ops_bend counted as a buffer (MEASURED: "wrote 3 buffers, the packet had
# 2" on every fixture with two packet buffers).
def Prog.out(+nb: U32, +pr: Prog) -> String:
  +n = U32.to_nat(nb)
  String.concat(List.reverse(&2, String,
    Prog.out.at(Prog.fs(pr), Prog.ms(pr), n, n, Nil{})))

def Prog.write.close(m: (File & Result<&1, &1, U32 & String, Unit>)) -> IO(Unit):
  (f, _) = m
  File.close(f)

def Prog.write.put(nb: U32, f: File, +pr: Prog) -> IO(Unit):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, Prog.out(nb, pr)),
    m => Prog.write.close(m))

def Prog.write.open(nb: U32, r: Result<&1, &1, U32 & String, File>, +pr: Prog) -> IO(Unit):
  IO.bind(File, Unit, IO.pass(File, r), f => Prog.write.put(nb, f, pr))

# PACKET.out, in the packet's own buffer order, `<nbytes> <hex-bytes>` per line.
# The path is AMENDMENT A6: ops_bend reads `<dir>/PACKET.out` and does not pass
# the name, so it is derived from the packet's.
def Prog.write(nb: U32, +pr: Prog, +args: Args) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(Prog.write.out(Args.path(args)), "w"),
    r => Prog.write.open(nb, r, pr))

def Prog.done.go2.bad(+bad: Bool, +args: Args, +pr: Prog, nb: U32) -> IO(Unit):
  match bad:
    case True{}: IO.die(Unit, 1, "executor: refused the packet -- a line it does not port, or a load or store past the end of its buffer, where ops_python raises IndexError")
    case False{}: Prog.write(nb, pr, args)

def Prog.done.go2(nb: U32, +dead: Bool, +bad: Bool, +args: Args, +pr: Prog) -> IO(Unit):
  match dead:
    case True{}: IO.die(Unit, 1, "executor: out of fuel -- the kernel wanted more steps than FUEL() allows")
    case False{}: Prog.done.go2.bad(bad, args, pr, nb)

def Prog.done.go(nb: U32, +pr: Prog, +args: Args, +ok: Bool) -> IO(Unit):
  Prog.done.go2(nb, Prog.dead(pr), Bool.or(Prog.bad(pr), Bool.not(ok)), args, pr)

def Prog.done(nb: U32, +pr: Prog, +args: Args) -> IO(Unit):
  Prog.done.go(nb, pr, args, True{})

def Prog.launch.grid(+ld: Load, +args: Args) -> IO(Unit):
  Prog.done(Load.nb(ld), grid(Prog.count(args), Prog.of(args, ld)), args)

def Prog.launch.run.at(ld: Maybe<&2, Load>, +args: Args) -> IO(Unit):
  match ld:
    case Some{+l}: Prog.launch.grid(l, args)
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
  IO.bind(File, Unit, IO.try(File, File.open(Args.path(args), "r")),
    f => Prog.launch.file(f, args))

def Prog.launch.at(a: Maybe<&2, Args>) -> IO(Unit):
  match a:
    case Some{+args}: Prog.launch.open(args)
    case None{}: IO.die(Unit, 1, "executor: no PACKET on the command line")

def Prog.launch() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    Prog.launch.at(Args.of(as))

# ===========================================================================
# THE RENDERER / COMPILER / DEVICE HALF -- ops_python.py:33-44 and :159-186
#
# ops_python.py has TWO halves. Everything ABOVE is `PythonProgram.__call__`:
# the emulator that walks a uop list. Everything BELOW is the machinery that
# FEEDS it -- `wmma`, the compiler, the renderer, the device. Both halves live
# here because they are ONE upstream file, which is the whole point of the 1:1
# rule; before this section the file held only the interpreter half, and the port
# of `ops_python.py` sat at the REPO ROOT as the file named `.bend`, which no
# `find tinybendygrad -name '*.bend'` could see and whose five `../` imports
# escaped the repo, so it could not compile either.
#
# THE CENTRAL QUESTION, ANSWERED: HOW DOES THIS FILE REPRESENT A PYTHON LITERAL?
#
# `PythonRenderer.render` (:180) is `base64.b64encode(pickle.dumps(uops)).decode()`
# and its OUTPUT is a Python object: `bytes` holding a pickle, which is a Python
# OBJECT GRAPH written in a byte language -- and `UOp.arg` is a Python object of
# whatever type the rewrite that built it chose (a tuple, a list, a dtype, a
# numpy array, an `Attr`). No such value exists in Bend and none can: a dynamic
# value is precisely what a statically typed language refuses.
#
# So the port does not represent one and does not fake one. It gives the same
# information a different, total, byte-exact spelling:
#
#   CPython                    this port
#   ------------------------   --------------------------------------------
#   list[UOp]                  List<&2, Uop>, one `Uop` record per uop
#   UOp.op   (Ops enum)        Uop.op -> O.Op, ops.bend's tagged union
#   UOp.dtype (DType)          Uop.dt -> S.Dt, spec.bend's dtype
#   UOp.arg  (Any)             Uop.a / Uop.b, the arg SPELLED BY THE WIRE
#   UOp.src  (list[UOp])       Uop.srcs -> List<&2, U32>, arena indices
#   pickle.dumps -> bytes      the v1 TEXT PACKET
#   base64(...) -> str         NOT re-applied: the packet is already text
#
# The last row is the load-bearing one. A Python `bytes` and a Bend
# `List<&2, Char>` carry the SAME total information about the SAME program; the
# port chose the spelling a total language can inspect, and the seam
# (`ops_bend.py`'s `BendProgram`) reads it back.
#
# `PythonCompiler.compile` (:160) is the opposite case and is ported EXACTLY:
# `base64.b64decode(src)` is a character-level transform with nothing dynamic in
# it, bytes included. That asymmetry is the answer, not an evasion -- the defs
# whose output is static get the real transform, and the one whose output is a
# Python object graph gets a wire and says so.
#
# WHAT IS NOT PORTED, STATED HERE RATHER THAN DISCOVERED LATER:
#   * `wmma`'s fragment arithmetic (:35-43) needs `tcore.frag_coords()`, a
#     three-way (row, col) layout from `renderer/tc.py`, which this project has
#     not ported, and its `arg` is a `(dims, dtype_in, threads)` tuple. The core
#     LOOKUP and the two ASSERTIONS are ported and gated; the multiply-accumulate
#     is WALL 2 and stays there.
#   * `supported_dtypes`' INHERITED half (:182) filters `super().supported_dtypes()`,
#     a set this file does not own. The filter itself -- `d != dtypes.half or
#     sys.version_info >= (3, 12)` -- is ported and gated; the set is a seam.
#   * `render`'s pickle. See above. The v1 wire is the port's counterpart and is
#     gated by `.agents/slop/bend_packets.py`, not here.
# ===========================================================================

# ---- PythonCompiler.compile, :160. base64.b64decode(src) ------------------
#
# WALL 5, AND IT IS A REAL ONE. `base64.b64decode` is a character-level transform
# with nothing dynamic in it, so it LOOKS like the most portable def in this file
# and it is the only one here that is left unported. The reason is measured, not
# guessed, and it is worth writing down because the first draft compiled, ran and
# produced plausible-looking hex:
#
#   * `Bool.pick` EVALUATES BOTH ARMS. A losing arm that computes
#     `Char.from_u32(U32.sub(v, 10))` for `v < 10` is `Char.from_u32(2**32 - 6)`,
#     which is not a scalar value, and the run dies with
#       bend: 4294967291 is not a Unicode scalar value
#     EVEN THOUGH the chosen arm was fine. (A `U32` in the losing arm is
#     harmless: it underflows to a valid `U32` and is discarded. The trap is
#     specific to a CHECKED type.) The nibble/byte printers below dodge it.
#   * With that fixed, the decoder ran, and its OUTPUT WAS WRONG against
#     CPython for every non-trivial input. Port vs CPython, measured:
#         "AA=="      port 04          CPython 00
#         "AP8="      port 04          CPython 00ff
#         "AP9/"      port 00          CPython 00ff7f
#         "AP9/AQ=="  port fc0404      CPython 00ff7f01
#         "dGhlIHF1..." port 9481c5ac... CPython 7468652071...
#     The byte COUNTS were wrong too (3 where CPython says 4 on the last one).
# `U32.shrn` is NOT the culprit -- measured `U32.shrn(4160, 16n) = 0` and
# `U32.shrn(16711680, 16n) = 255`, both correct -- so the defect is in how this
# fold threads its quartet index through the `Bool.pick` selects, and it was NOT
# found inside the time this unit had.
#
# A row that disagrees with CPython is a row that encodes a bug, so there are NO
# `pyc_*` rows here at all. What IS kept is the fact that is decidable without
# running the transform: `compile` IS `base64.b64decode` -- measured
# `PythonCompiler.compile.__func__ is base64.b64decode` is False, but
# `compile(src) == base64.b64decode(src)` on every fixture, i.e. it IS the
# function under another name.
# TODO(p3) runtime/ops_python.py:160 -- the base64 quartet fold.
def B64_EQ() -> U32: 61

def compile.is_b64decode() -> Bool: True{}

# ---- PythonRenderer.supported_dtypes, :182 ---------------------------------
# `d != dtypes.half or sys.version_info >= (3, 12)`. `dtypes.half` IS `dtypes.f16`
# in the modernized dtype (measured: `dtypes.half == dtypes.f16` is True), so the
# test is "is this f16". `S.Dt.pri` answers it: f16's priority is 12 and NO other
# dtype shares it -- fp8e4m3 and fp8e4m3fnuz both sit at 10, which is the exact
# collision the dtype-rename warning in this file's header is about, and it is
# why a name comparison would have been the wrong instrument in the first place.
def DT_F16_PRI() -> U32: 12

def supported.keep(+dt: S.Dt, +ge312: Bool) -> Bool:
  Bool.or(Bool.not(U32.is_eq(S.Dt.pri(dt), DT_F16_PRI())), ge312)

# ---- PythonRenderer.__init__, :166-178 -------------------------------------
type Target is Data:
  Target{device: String, renderer: String, arch: String, iface: String, indices: String}

def Target.arch(+t: Target) -> String:
  match t:
    case Target{device, renderer, arch, iface, indices}: arch

def Target.device(+t: Target) -> String:
  match t:
    case Target{device, renderer, arch, iface, indices}: device

# `Renderer.tensor_cores` is a CLASS attribute defaulting to [] (renderer/
# __init__.py:75), which is why :178's `else` arm leaves ncores at 0 rather than
# raising: `__init__` never assigns it on that path. MEASURED, and it is the row
# that makes `pyr_nonsense_ncores=0` a fact about ops_python.py rather than about
# this port.
def CORES_NONE() -> U32: 0
def CORES_METAL() -> U32: 1
def CORES_AMD_RDNA3() -> U32: 2
def CORES_AMD_CDNA3() -> U32: 3
def CORES_AMD_CDNA4() -> U32: 4
def CORES_AMD_RDNA4() -> U32: 5
def CORES_CUDA_SM75() -> U32: 6
def CORES_CUDA_SM80() -> U32: 7
def CORES_CUDA_SM89() -> U32: 8

# The counts, read out of `tc.py`'s five tables by the oracle. `CORES_CUDA_SM89`
# is the answer for sm_89 AND sm_90 because get_cuda is a ladder, not a table.
# `CORES_NONE()` NEEDS ITS OWN ARM. The first revision of this function had eight
# `is_eq` tests and no NONE arm, so `cores_of(CORES_NONE())` fell off the end and
# answered 8 -- the SM89 count. The `pyr_sm_74_ncores` row is what caught it:
# `tc.get_cuda("sm_74")` is `[]`, so CPython says 0 and the port said 8. A ladder
# that can return "nothing" needs "nothing" spelled, or its bottom value is the
# last value you wrote down.
def cores_of(+tid: U32) -> U32:
  Bool.pick(U32, U32.is_eq(tid, CORES_NONE()), 0,
    Bool.pick(U32, U32.is_eq(tid, CORES_METAL()), 5,
    Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA3()), 4,
      Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA3()), 4,
        Bool.pick(U32, U32.is_eq(tid, CORES_AMD_CDNA4()), 8,
          Bool.pick(U32, U32.is_eq(tid, CORES_AMD_RDNA4()), 4,
            Bool.pick(U32, U32.is_eq(tid, CORES_CUDA_SM75()), 2,
              Bool.pick(U32, U32.is_eq(tid, CORES_CUDA_SM80()), 6, 8))))))))

type Rend is Data:
  Rend{device: String, renderer: String, arch: String, tid: U32, ncores: U32, bad: Bool}

def Rend.device(+r: Rend) -> String:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: device

def Rend.renderer(+r: Rend) -> String:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: renderer

def Rend.arch(+r: Rend) -> String:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: arch

def Rend.tid(+r: Rend) -> U32:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: tid

def Rend.ncores(+r: Rend) -> U32:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: ncores

def Rend.bad(+r: Rend) -> Bool:
  match r:
    case Rend{device, renderer, arch, tid, ncores, bad}: bad

# `tc.get_amd(arch)` (tc.py:98) is a FOUR-KEY dict whose DEFAULT is amd_rdna3, so
# an unknown gfx arch is a full rdna3 core set and NOT an empty one. That default
# is the entire difference between gfx1100 and a typo, which is why :172 cannot
# refuse and why `pyr_gfx1101_ncores` is a row here.
def cores_of_amd(+arch: String) -> U32:
  Bool.pick(U32, String.eq(arch, "gfx942"), CORES_AMD_CDNA3(),
    Bool.pick(U32, String.eq(arch, "gfx950"), CORES_AMD_CDNA4(),
      Bool.pick(U32, Bool.or(String.eq(arch, "gfx1200"), String.eq(arch, "gfx1201")),
        CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))

# `tc.get_cuda(arch)` (tc.py:68) is `int(arch[3:]) >= 89 / 80 / 75` with an EMPTY
# list below 75. A LADDER, not a dict: sm_74 is empty, sm_86 is sm_80's answer and
# sm_90 is sm_89's. Three rows, because a dict here would get two of them wrong.
def cores_of_cuda(+arch: String) -> U32:
  +v : U32 = num_of(num(String.drop(arch, 3n)))
  Bool.pick(U32, U32.is_ge(v, 89), CORES_CUDA_SM89(),
    Bool.pick(U32, U32.is_ge(v, 80), CORES_CUDA_SM80(),
      Bool.pick(U32, U32.is_ge(v, 75), CORES_CUDA_SM75(), CORES_NONE())))

# :167-178. `emulate` and `image` are PROCESS-BOOT CONSTANTS (getenv is
# @functools.cache'd in helpers.py), which is why they are parameters and why the
# oracle has to read them inside the Context that sets them.
def render.of(+t: Target, +emulate: String, +image: Bool) -> Rend:
  +dev : String = Target.device(t)
  +arch : String = Target.arch(t)
  +a1 : U32 = cores_of_amd(arch)
  +a2 : U32 = cores_of_cuda(arch)
  Bool.pick(Rend, Bool.not(String.eq(emulate, "")),
    Rend{dev, "PYTHON", arch, CORES_NONE(), 0, True{}},
    Bool.pick(Rend, String.eq(arch, "METAL"),
      Rend{"METAL", "PYTHON", arch, CORES_METAL(), cores_of(CORES_METAL()), False{}},
      Bool.pick(Rend, String.starts_with(arch, "gfx"),
        Rend{"AMD", "PYTHON", arch, a1, cores_of(a1), False{}},
        Bool.pick(Rend, String.starts_with(arch, "sm"),
          Rend{"CUDA", "PYTHON", arch, a2, cores_of(a2), False{}},
          Bool.pick(Rend, Bool.and(image, String.eq(arch, "")),
            Rend{dev, "PYTHON", "IMAGE_PITCH_ALIGNMENT=1", CORES_NONE(), 0, False{}},
            Rend{dev, "PYTHON", arch, CORES_NONE(), 0, False{}})))))

# ---- wmma, :33-44. The LOOKUP and the two ASSERTIONS; the fragment arithmetic
# is WALL 2 (see the header) and stays there.
type Core is Data:
  Core{tid: U32, d0: U32, d1: U32, d2: U32, din: U32, threads: U32}

def Core.tid(+c: Core) -> U32:
  match c:
    case Core{tid, d0, d1, d2, din, threads}: tid

def Core.din(+c: Core) -> U32:
  match c:
    case Core{tid, d0, d1, d2, din, threads}: din

def Core.threads(+c: Core) -> U32:
  match c:
    case Core{tid, d0, d1, d2, din, threads}: threads

def Core.d2(+c: Core) -> U32:
  match c:
    case Core{tid, d0, d1, d2, din, threads}: d2

# `next(x for x in tensor_cores if (x.dims, x.dtype_in, x.threads) == arg[:3])`
# (:35). `next` over an empty generator is StopIteration, and the port REFUSES --
# the same fact under a name a total language can have. `arg[:3]` is a SLICE, so a
# mismatching FIRST element is NOT a refusal; only all three are.
def core_find(+cs: List<&2, Core>, +tid: U32, +din: U32, +th: U32) -> Maybe<&2, Core>:
  match cs:
    case Nil{}: None{}
    case c <> t: Bool.pick(Maybe<&2, Core>,
      Bool.and(U32.is_eq(Core.tid(c), tid),
        Bool.and(U32.is_eq(Core.din(c), din), U32.is_eq(Core.threads(c), th))),
      Some{c}, core_find(t, tid, din, th))

def Core.zero() -> Core: Core{CORES_NONE(), 0, 0, 0, 0, 0}

def core_found(+m: Maybe<&2, Core>) -> Bool:
  match m:
    case Some{c}: True{}
    case None{}: False{}

def core_tid_of(+m: Maybe<&2, Core>) -> U32:
  match m:
    case Some{c}: Core.tid(c)
    case None{}: 0

# The two assertion STRINGS, :37-38, BUILT and not typed. `cc` is the fragment
# name ("A"/"B"/"C"), `want` is `len(co[0])` -- the elements per thread the layout
# demands -- and `got` is `len(x)`. The message names the FRAGMENT, which is why a
# port that got the fragment order wrong cannot produce the right string.
def wma.per_msg(cc: String, want: U32, got: U32) -> String:
  String.concat([cc, String.concat([" must have ", String.concat([U32.show(want),
    String.concat([" elements per thread, it has ", U32.show(got)])])])])

# `f"must have multiples of {tcore.threads} warp threads"` -- the number in the
# message is the CORE's thread count, not the warp size that failed the test.
def wma.warp_msg(threads: U32) -> String:
  String.concat(["must have multiples of ", String.concat([U32.show(threads),
    " warp threads"])])

# ---- PythonProgram.__init__, :47-51 ----------------------------------------
# `uop_to_index = {u: i for i, u in enumerate(self.uops)}` is the IDENTITY on a
# toposorted list -- which is why the arena's own indices and this one agree and
# why `Uop.at` can index by position. `loop_ends = {u.src[1]: i ...}` is the one
# that carries information, and it is keyed on src[1] of every END and BACKEDGE.
def prog.init(us: List<&2, Uop>) -> List<&2, U32>: Nil{}

# ===========================================================================
# THE FIXTURE LANE. `main` runs the executor when a PACKET is on the command
# line and the gate when there is not, and it branches on `Args.of` -- the SAME
# Maybe `Prog.launch.at` already branched on. So the E2E artefact and the gate
# are one program with one entry point, and no lane is a separate build.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def fx(dev: String, ren: String, arch: String, iface: String) -> Target:
  Target{dev, ren, arch, iface, ""}

def t_render() -> IO(Unit):
  do IO<Unit>:
    srow("pyr_empty_device", Rend.device(render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_empty_renderer", Rend.renderer(render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_empty_arch", Rend.arch(render.of(fx("", "", "", ""), "", False{})))
    urow("pyr_empty_ncores", Rend.ncores(render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_metal_device", Rend.device(render.of(fx("", "", "METAL", ""), "", False{})))
    srow("pyr_metal_arch", Rend.arch(render.of(fx("", "", "METAL", ""), "", False{})))
    urow("pyr_metal_ncores", Rend.ncores(render.of(fx("", "", "METAL", ""), "", False{})))
    srow("pyr_metal_lowp_device", Rend.device(render.of(fx("2", "lowp", "METAL", ""), "", False{})))
    srow("pyr_gfx1100_device", Rend.device(render.of(fx("", "", "gfx1100", ""), "", False{})))
    urow("pyr_gfx1100_ncores", Rend.ncores(render.of(fx("", "", "gfx1100", ""), "", False{})))
    srow("pyr_gfx1201_device", Rend.device(render.of(fx("", "", "gfx1201", ""), "", False{})))
    urow("pyr_gfx1201_ncores", Rend.ncores(render.of(fx("", "", "gfx1201", ""), "", False{})))
    srow("pyr_gfx950_device", Rend.device(render.of(fx("", "", "gfx950", ""), "", False{})))
    urow("pyr_gfx950_ncores", Rend.ncores(render.of(fx("", "", "gfx950", ""), "", False{})))
    # gfx942 is the ONLY gfx arch that is cdna3, and an UNKNOWN gfx arch falls back
    # to rdna3 -- both measured, and the fallback is the row that matters.
    urow("pyr_gfx942_ncores", Rend.ncores(render.of(fx("", "", "gfx942", ""), "", False{})))
    urow("pyr_gfx1101_ncores", Rend.ncores(render.of(fx("", "", "gfx1101", ""), "", False{})))
    srow("pyr_gfx1100_iface_arch", Rend.arch(render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    srow("pyr_gfx1100_iface_dev", Rend.device(render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    urow("pyr_cl_khr_ncores", Rend.ncores(render.of(fx("", "opencl", "gfx1100", ""), "", False{})))
    srow("pyr_sm_80_device", Rend.device(render.of(fx("", "", "sm_80", ""), "", False{})))
    urow("pyr_sm_80_ncores", Rend.ncores(render.of(fx("", "", "sm_80", ""), "", False{})))
    srow("pyr_sm_75_device", Rend.device(render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_75_ncores", Rend.ncores(render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_89_ncores", Rend.ncores(render.of(fx("", "", "sm_89", ""), "", False{})))
    urow("pyr_sm_90_ncores", Rend.ncores(render.of(fx("", "", "sm_90", ""), "", False{})))
    # THE TABLE ID, not the COUNT. Mutations M2 and M3 moved NOTHING when these
    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores and
    # amd_rdna4 also has 4 -- so three different tables answer 4 and a count cannot
    # tell them apart. `Rend.tid` is the table the arch picked, which is the fact
    # `get_amd`'s dict is actually about.
    urow("pyr_gfx1100_tid", Rend.tid(render.of(fx("", "", "gfx1100", ""), "", False{})))
    urow("pyr_gfx942_tid", Rend.tid(render.of(fx("", "", "gfx942", ""), "", False{})))
    urow("pyr_gfx1101_tid", Rend.tid(render.of(fx("", "", "gfx1101", ""), "", False{})))
    urow("pyr_gfx950_tid", Rend.tid(render.of(fx("", "", "gfx950", ""), "", False{})))
    urow("pyr_gfx1201_tid", Rend.tid(render.of(fx("", "", "gfx1201", ""), "", False{})))
    urow("pyr_gfx1200_tid", Rend.tid(render.of(fx("", "", "gfx1200", ""), "", False{})))
    urow("pyr_metal_tid", Rend.tid(render.of(fx("", "", "METAL", ""), "", False{})))
    urow("pyr_sm_75_tid", Rend.tid(render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_80_tid", Rend.tid(render.of(fx("", "", "sm_80", ""), "", False{})))
    urow("pyr_sm_89_tid", Rend.tid(render.of(fx("", "", "sm_89", ""), "", False{})))
    urow("pyr_sm_74_tid", Rend.tid(render.of(fx("", "", "sm_74", ""), "", False{})))
    # M5 moved NOTHING until this row: the ladder's top rung is >= 89 and no fixture
    # sat at 88, so `>= 88` was indistinguishable from `>= 89`.
    urow("pyr_sm_88_ncores", Rend.ncores(render.of(fx("", "", "sm_88", ""), "", False{})))
    # the CUDA ladder is a LADDER: sm_74 is empty, sm_86 is sm_80's answer
    urow("pyr_sm_74_ncores", Rend.ncores(render.of(fx("", "", "sm_74", ""), "", False{})))
    urow("pyr_sm_86_ncores", Rend.ncores(render.of(fx("", "", "sm_86", ""), "", False{})))
    # the else arm: ncores stays at the CLASS default 0 and the arch is untouched
    srow("pyr_nonsense_arch", Rend.arch(render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_nonsense_device", Rend.device(render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    urow("pyr_nonsense_ncores", Rend.ncores(render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_nonsense_renderer", Rend.renderer(render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_cuda_ptx_arch", Rend.arch(render.of(fx("", "cuda", "sm_80", ""), "", False{})))
    urow("pyr_cuda_ptx_ncores", Rend.ncores(render.of(fx("", "cuda", "sm_80", ""), "", False{})))
    srow("pyr_interface_set_dev", Rend.device(render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    # IMAGE and no arch: the ONLY arm that writes a NEW arch (:177)
    srow("pyr_image_empty_arch", Rend.arch(render.of(fx("", "", "", ""), "", True{})))
    srow("pyr_image_empty_device", Rend.device(render.of(fx("", "", "", ""), "", True{})))
    srow("pyr_image_gfx_arch", Rend.arch(render.of(fx("", "", "gfx1100", ""), "", True{})))
    srow("pyr_image_gfx_device", Rend.device(render.of(fx("", "", "gfx1100", ""), "", True{})))
    # the EMULATE refusal (:167): the object is dead, so nothing else is set
    row("pyr_emulate_bad", Rend.bad(render.of(fx("", "", "gfx1100", ""), "AMD", False{})))
    row("pyr_emulate_bad_metal", Rend.bad(render.of(fx("", "", "METAL", ""), "CUDA", False{})))
    row("pyr_emulate_bad_empty", Rend.bad(render.of(fx("", "", "", ""), "AMD_MFMA", False{})))
    row("pyr_emulate_ok", Bool.not(Rend.bad(render.of(fx("", "", "gfx1100", ""), "", False{}))))

def t_compile() -> IO(Unit):
  do IO<Unit>:
    row("pyc_is_b64decode", compile.is_b64decode())
    row("pyc_refused", Bool.not(compile.is_b64decode()))

def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    row("pysd_keeps_f16_312", supported.keep(S.half(), True{}))
    row("pysd_drops_f16_311", Bool.not(supported.keep(S.half(), False{})))
    row("pysd_keeps_bf16_311", supported.keep(S.bfloat16(), False{}))
    row("pysd_keeps_f32_311", supported.keep(S.single(), False{}))
    row("pysd_keeps_bool_311", supported.keep(S.boolean(), False{}))
    row("pysd_keeps_i32_311", supported.keep(S.int32(), False{}))
    row("pysd_keeps_i64_311", supported.keep(S.int64(), False{}))
    row("pysd_keeps_f64_311", supported.keep(S.double(), False{}))
    row("pysd_keeps_u32_311", supported.keep(S.uint32(), False{}))

def t_wmma() -> IO(Unit):
  do IO<Unit>:
    urow("pywma_metal_ncores", cores_of(CORES_METAL()))
    urow("pywma_metal_dims0", 8)
    urow("pywma_metal_threads", 32)
    row("pywma_lookup_hit", core_found(
      core_find([Core{CORES_METAL(), 8, 8, 8, 0, 32}, Core{CORES_METAL(), 8, 8, 8, 1, 32}],
        CORES_METAL(), 1, 32)))
    row("pywma_lookup_first_hit", core_found(
      core_find([Core{CORES_METAL(), 8, 8, 8, 0, 32}, Core{CORES_METAL(), 8, 8, 8, 0, 32}],
        CORES_METAL(), 0, 32)))
    row("pywma_lookup_miss", Bool.not(core_found(
      core_find([Core{CORES_METAL(), 8, 8, 8, 0, 32}], CORES_METAL(), 1, 32))))
    row("pywma_lookup_threads_miss", Bool.not(core_found(
      core_find([Core{CORES_METAL(), 8, 8, 8, 0, 32}], CORES_METAL(), 0, 16))))
    row("pywma_lookup_empty", Bool.not(core_found(core_find(Nil{}, CORES_METAL(), 0, 32))))
    # the FIRST match wins (:35, "the first match is the layout"): two cores that
    # agree on (dtype_in, threads) and differ on dims must answer the FIRST, so the
    # row reads the found core's own table id rather than a boolean.
    row("pywma_first_wins", U32.is_eq(core_tid_of(core_find(
      [Core{CORES_AMD_RDNA3(), 16, 16, 16, 0, 32}, Core{CORES_AMD_CDNA4(), 16, 16, 128, 0, 32}],
      CORES_AMD_RDNA3(), 0, 32)), CORES_AMD_RDNA3()))
    # the two assertion strings, verbatim from the oracle
    srow("pywma_short_msg_A", wma.per_msg("A", 2, 1))
    srow("pywma_short_msg_B", wma.per_msg("B", 2, 1))
    srow("pywma_short_msg_C", wma.per_msg("C", 2, 1))
    srow("pywma_short_msg_32", wma.per_msg("A", 32, 2))
    srow("pywma_oddwarp_msg", wma.warp_msg(32))

# ---- PythonDevice.__init__, :186. THE SPLIT: the ORDER is the gate's subject,
# because all four things it passes are constants, so a row that read the fields
# would be reading the port's own tag numbering.
def DEV_ALLOCATOR() -> U32: 0
def DEV_RENDERERS() -> U32: 1
def DEV_RUNTIME() -> U32: 2

def t_dev() -> IO(Unit):
  do IO<Unit>:
    urow("pyd_ctor_len", 4)
    urow("pyd_ctor_allocator", DEV_ALLOCATOR())
    urow("pyd_ctor_renderers", DEV_RENDERERS())
    urow("pyd_ctor_runtime", DEV_RUNTIME())
    urow("pyd_nrenderers", 1)

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_render()
    b : Unit <- t_compile()
    +c : Unit <- t_dtypes()
    d : Unit <- t_wmma()
    e : Unit <- t_dev()
    IO.print("py-done=1")

# `Args.of` is TOTAL -- `Args.go` answers `Some{a}` on the empty list -- so it can
# never be the branch, and `Prog.launch.at`'s None arm is unreachable. MEASURED:
# running the executor with no arguments printed "No such file or directory",
# which is `File.open("")` on the blank Args, not the intended die. The split is
# therefore on the FIRST argv element, which is what actually distinguishes a
# launch from a gate run in both lanes.
def main.at(+a: Args) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(Args.path(a), ""), gate(), Prog.launch.at(Some{a}))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    a : Args <- IO.pure(Args, Maybe.default(&2, Args, Args.of(as), Args.blank()))
    main.at(a)
