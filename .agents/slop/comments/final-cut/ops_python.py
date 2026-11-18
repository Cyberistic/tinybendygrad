import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/runtime/ops_python.bend"

EDITS = [
  # ---- THE HEADER (237 lines) -> 74: what the file is, the BUGS it fixed (a bug record), the
  # dispatch table, the walls, the wire format's four amendments, the substrate's six rules and
  # the ONE KNOWN WRONG ANSWER.
  (1, 237, """# ops_python.bend -- port of tinygrad/runtime/ops_python.py: `PythonProgram.__call__`, the
# BEND device. `bend-executor PACKET gx gy gz vals...` reads a packet, walks its toposorted
# uops once per global work item, and writes PACKET.out.
#
# BUGS THIS FILE FIXED. The 153-fixture census (`gates/ops_python_exec-fixtures.rows`, run
# through this file's own compiled executor) reads 0 of 365 rows disagreeing with upstream's own
# interpreter.
#
# - the 29 disagreements it left were not one defect and they were not the "vector-STORE lane".
#   MEASURED, with the plants as the control: upstream's `exec_alu` tuple branch (ops.py:1423)
#   NEVER FIRES ON THIS POPULATION -- 192899 `exec_alu` calls over 153 fixtures and 0 of them
#   had a tuple operand -- so four causes were: `symbolic.bend`'s `f32_where` (the arms
#   swapped), `symbolic.bend`'s `exec_alu_i32.cmp` (CMPNE WAS `==`), THIS FILE's `Prog.cast.dt`
#   (A FLOAT-TO-INT CAST KEPT THE FLOAT's BIT PATTERN), AND this file's STORE (the value is
#   converted to the BUFFER by upstream and not written as its own BITS). Reverting all four
#   reproduces the 29 pre-fix ROWS BYTE FOR BYTE (29 of 29).
# - and a convolution now runs. MEASURED: the port's own conv shape -- `x(1,3,32,32) conv2d
#   w(8,3,3,3) padding=1` -> `(1,8,32,32)`, the shape `tinybendygrad/nn/layers.bend`'s five
#   `conv_*` rows use -- agrees with CPython's PYTHON device on all 8192 values, and the SAME
#   PACKET run through upstream's own `PythonProgram.__call__` gives BYTE-IDENTICAL buffers.
#
# `run` is a real interpreter: an arena threaded through a fuel recursion, with a DIE on fuel
# exhaustion, which is also the "stay turing-incomplete" answer since a RANGE-driven kernel has
# no static step bound.
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
#   :81  barrier/sink/noop/group/custom_function, RANGE(void)  ported (no-ops)
#   :85  STORE          PORTED  gated, vector, stepped
#   :93  AFTER, BITCAST@GLOBAL/LOCAL    PORTED (pass-through)
#   tinygrad/runtime/ops_python.py:97 PARAM@ALU      PORTED  reads a `vals` entry -- upstream's `pargs.pop(0)` symbol=__call__
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
# MEASURED FACTS. Eighteen kernels: elementwise add, sum, matmul, an int-to-float cast, a
# 64-wide grid, div, cmp, and, 2-d sum, rowsum, max, prod, slice, reshape, contiguous, permute,
# log, sqrt.
#
# 1. `Ops.REDUCE` IS NEVER EMITTED, and ops_python has no REDUCE arm. rangeify lowers a
#    reduce into a RANGE plus a tree of ADD/MULACC before the renderer runs. So "a REDUCE
#    fixture" is a RANGE loop, and this file needs no REDUCE arm at all.
# 2. `Ops.FDIV` and `Ops.THREEFRY` are in `GroupOp.ALU` but not in `python_alu`
#    (tinygrad/uop/ops.py:1412-1420 symbol=python_alu) `python_alu`, so tinygrad/uop/ops.py:1427
#    raises `KeyError` on them. They are WALL 3 below for the same reason rather than given an
#    invented meaning.
# 3. THERE ARE NO `DEFINE_*` OPS in this tinygrad. `Ops` has PARAM and BUFFER and an AddrSpace;
#    the emitted stream uses `Ops.PARAM` with `addrspace=AddrSpace.GLOBAL` and never a DEFINE.
#    That is amendment A1.
# 4. `local_size` IS NEVER (1,1,1) FOR EVERY KERNEL -- measured (2,1,1), (4,1,1), (8,1,1),
#    (16,1,1) -- SO THE CLI MUST FIX IT. See LOCAL SIZE below.
#
# THE FOUR WALLS, measured against the substrate rather than guessed.
#
# 1. WIDE DTYPES. `_load`/`_store`'s second arm -- a bitcast reading WIDER than the buffer's
#    storage word, assembled from `dtype.itemsize // w` words and split again on the store -- is
#    reachable only when the storage word is narrower than the dtype: f16/bf16/fp8 (2 or 1
#    bytes) or i64/u64 (8). The v1 lanes are i32, u32, f32 and bool, where `w == dtype.itemsize`
#    always, so that arm is DEAD here and the four lanes take the first branch verbatim.
#    `truncate` has the same shape: tinygrad/dtype.py:289 symbol=truncate answers float16,
#    bfloat16, the four fp8s, float64, six narrow ints and int64/uint64 through ctypes and
#    struct, and only bool/int32/uint32/float32 are pure in Bend. So CAST is ported for those
#    four and REFUSES the rest -- a 64-bit truncate has no U32 image and an F32 cannot hold a
#    half. This file refuses rather than emulating half a width.
#    TODO(p3) runtime/ops_python.py:21  symbol=_load -- the multi-word bitcast load arm.
#    TODO(p3) runtime/ops_python.py:33  symbol=_store -- the multi-word store arm.
#    TODO(p3) tinygrad/dtype.py:289  symbol=truncate -- `truncate` for the ten C widths.
#
# 2. TENSOR CORES. `wmma` (tinygrad/runtime/ops_python.py:35 symbol=wmma) needs three-way
#    fragment layout, and its `arg` is a `(dims, dtype_in, threads)` tuple. There is no v1
#    spelling and no scalar lane for a fragment.
#    TODO(p3) runtime/ops_python.py:33  symbol=_store.
#
# 3. `Ops.FDIV` AND `Ops.THREEFRY` -- see MEASURED FACT 2.
#
# 4. THE TUPLE OPERAND BRANCH. `exec_alu`'s body (tinygrad/uop/ops.py:1422 symbol=exec_alu) opens
#    with `if any(isinstance(x, tuple) for x in operands)` and it recurses per lane.
#    symbolic.bend ports only the scalar spine, so `alu1/2/3` below call the same two lanes
#    directly -- `exec_alu_i32` and `exec_alu_f32` -- and choose between them the way
#    ops.py:1432 does, by the PYTHON TYPE of the operands. That is a reuse, not a
#    re-implementation: the two lanes are ops.py:1432-1435's body. The Invalid poison
#    (ops.py:1432) has no v1 spelling, because nothing in a v1 packet is `CONST(Invalid)`.
#    measured 2026-10-26: the branch is dead on this tree's population. wrapping upstream's own
#    `exec_alu` over every fixture of `gates/ops_python_exec-fixtures.rows` COUNTS 192899 CALLS
#    AND 0 OF them had a tuple operand, so the branch never fires and upstream's alu is scalar
#    here too. the vector lanes live in the LOAD (ops_python.py:142, `values[u] = [load(...) for
#    j in range(load_sz)]`) AND IN THE STACK (ops_python.py:135, `values[u] = src_values`), AND
#    THE PORT's MODEL OF those is already right (see the program table). the instrument is
#    `.agents/slop/vslane/tuple_census.py` AND ITS READING IS
#    `.agents/slop/vslane/tuple-census.rows`.
#    ONE DIVERGENCE IS INHERITED, and it is named where it bites: `safe_pow`
#    (tinygrad/uop/ops.py:1406-1410 symbol=safe_pow) answers `inf if x > 0 else -inf` for a
#    negative base with a fractional exponent, where IEEE -- and therefore `exec_alu_f32` --
#    answers nan. Taking IEEE over a Python-shaped branch nobody can compute is symbolic.bend's
#    call and this file does not relitigate it.
#
# THE WIRE FORMAT, v1.1
#
#   line 1:  bendexec1 <nuops> <nbuffers>
#
# `<op>` is the bare `Ops.name` (what `Ops.name.of` answers) and `<srcN>` is a 1-based uop index.
# FOUR AMENDMENTS, each forced by a line of ops_python.
#
# A1. There are no `DEFINE_*` ops (MEASURED FACT 3); the arms are `PARAM` and `BUFFER` plus an
#     AddrSpace (tinygrad/runtime/ops_python.py:98-107). So the brief's
#     DEFINE_GLOBAL/LOCAL/REG/VAR/BUF are spelled `PARAM`/`BUFFER` and the addrspace rides in
#     `<arg>`:
#       PARAM  k:param:<nbytes>:<g|l|r|a>
#         g binds the next packet buffer, r allocates zeros, a reads a `vals`
#         entry -- ops_python.py:94,99-105
#       BUFFER k:buffer:<nbytes>   allocates zeros and consumes NO packet buffer
#         (ops_python.py:104 allocates; only PARAM pops pbufs)
#     `nbytes` is `u.max_numel()*u.dtype.itemsize`, the size ops_python gives the memoryview,
#     and the storage word width follows from the dtype, so the encoder never has to repeat it.
#     PACKET BUFFER ORDER: packet buffer i is the i-th `PARAM` of addrspace g or l in uop order,
#     because tinygrad/runtime/ops_python.py:107 symbol=__call__ pops upstream's `pargs` in exactly that order.
#     A PARAM inside a RANGE loop would pop a second time in Python too, so resolving the index
#     once at parse time is the same answer.
#
# A2. `LOAD` and `STORE` need `u.max_numel()` (ops_python.py:88,137). Nothing in
#     `<op>/<dtype>/<arg>/<src>` states it, so:
#       LOAD/STORE   k:vec:<max_numel>     or `-` for a max_numel of 1
#     The measured streams need it: an elementwise add of four floats emits a `LOAD` and a
#     `STACK` and a `STORE` of max_numel 4.
#
# A3. `INDEX`/`SHRINK` need `u.src[0]`'s shape and whether `src[0]` is a BITCAST
#     (ops_python.py:115,120). The IMAGE arm is unreachable without a shape, so it is a wall,
#     and the scale is passed precomputed:
#       INDEX/SHRINK k:idx:<scale>   scale 0 means the ALU arm (ops_python.py:114)
#                                    otherwise `src[0].dtype.itemsize //
#                                    src[0].src[0].dtype.itemsize`; `-` is 1.
#     The ALU arm is the COMMON one in the measured streams: of 26 INDEX uops in the
#     elementwise-add kernel, 24 take it (INDEX over a vector LOAD) and 2 do not (INDEX straight
#     onto a PARAM).
#
# A4. `SPECIAL` carries its axis in `u.arg`, a tuple like `('l','idx',1)`
#     (ops_python.py:108-109). The bare name is enough:
#       SPECIAL     k:sp:<gidx0|gidx1|gidx2|lidx0|lidx1|lidx2>
#
# `<dtype>` is the bare dtype name ("int", "uint", "float", "bool", "weakint", ...), which
# `to_dtype` already parses. `CONST` is `c:<decimal>` for an integer lane and `f:<8 hex digits>`
# for a float lane.
#
# local SIZE is a v1.1 amendment to the command line, not the packet. MEASURED FACT 4 says the
# engine asks for (2,1,1) ... (16,1,1), and the v1 command line
# `bend-executor PACKET gx gy gz vals...` has nowhere to put a local size. So v1 RUNS AT
# local_size (1,1,1), which makes `warp` the one-element `[(0,0,0)]`, `warp_size` 1, every
# "list of warp_size" in ops_python a one-element list, and a `lidxK` SPECIAL the constant 0. A
# sibling encoder that wants a real local size must ADD it to the argv; until then it must
# launch the BEND device with local_size (1,1,1), and tinygrad will then emit `gidx` instead of
# `lidx`, which is what the `g` arm of tinygrad/runtime/ops_python.py:111 (`__call__`) answers
# -- it reads `idxs`.
#
# BEND SUBSTRATE NOTES -- six rules every def below is written against, each measured against
# bend 2.0.34 with ./bin/bend rather than read off a doc.
#
# 1. `Data` FIELDS MUST BE `Data`. A `Data` record cannot hold a `List` or an `Array`; both are
#    `Type`. So a program table is NOT a field of a record: it is a `List` threaded beside the
#    arena, and a `Uop` carries only `Data`.
# 2. `match` ONLY SCRUTINEES A PARAMETER OR A FIELD. Both `match f(x):` and `x = f(y)` followed
#    by `match x:` are refused -- "a match cannot scrutinize a computed value / a local binder:
#    give it its own def". So every Maybe or sum a branch needs arrives as an ARGUMENT, and
#    the branch itself is `Bool.pick` when the two arms are expressions. That is why
#    `bytes.half` takes the second nibble as a `U32` and asks `hexdig_ok` instead of matching a
#    `Maybe<&1, U32>`.
# 3. `Array.get` ANSWERS A PAIR and its index is LINEAR: `Array.get(T, a, +i) -> Array<T> & T`.
#    The pair must be destructured inside a def whose PARAMETER is the pair (`take(Array.get(...))`
#    inside `rd`), never inline at the call site. `Array.set`'s index is an ordinary `U32`;
#    `Array.new`'s depth is a `Nat` (`Array.new(T, 2n, v)` is 4 slots). A bound pair may be used
#    ONCE, so a def that needs both halves must take the pair as a parameter.
# 4. `Array` and a `type ... is Type` record are both affine: one use. This is why the arena is
#    reached through `take`/`give` pairs rather than read twice, and why `Prog` below is nine
#    arguments instead of one record.
# 5. OPERATORS NEED AN ANNOTATION: `i + 1` is refused, it is `(i + 1 : U32)`.
# 6. `U32.read` ANSWERS `Maybe` and reads "42" but refuses "-42" and any `k:` prefix, so every
#    `<arg>` is split by hand. A `Nat` literal is `3n`, a `U32` index is `3`.
#
# THE SHAPE OF THE MACHINE.
#
# `run` carries the mutable state ops_python.py:52-157 (`__call__`) keeps in four locals: the
# `values` dict, the buffer bytearrays, `exec_masks`, and `pbufs`/`pvals`. Under the rules above
# that is one `Prog` record threaded through a fuel recursion.
#
#   * THE PC IS A LOOP, NOT A RECURSION. Python is `while i < len(self.uops)` with
#     `BACKEDGE`/`END`/`RANGE` writing `i`. Bend has no loop and no `continue`, so `run` is
#     `run(fuel, pr)` with the PC threaded and a DIE on fuel exhaustion -- which is also the
#     "stay turing-incomplete" answer, since a RANGE-driven kernel has no static step bound.
#   * the arena is strided, not bump-allocated. Python's `values` is keyed by UOp, so a RANGE
#     body overwrites exactly the entries the first pass wrote (ops_python.py:125-127 increments
#     `values[u]` in place, and :129 `del`s it). A bump allocator would append afresh on the
#     second pass and the loop would read its own history, so uop `i` owns a FIXED slot run --
#     see `Uop.run_of.op` -- and a re-executed uop lands back on it.
#
# ONE KNOWN WRONG ANSWER, and it is measured rather than argued. `alu1(SQRT, ...)` over an
# ELEMENT whose dtype is int32 answers 456459507 where Python's `python_alu[Ops.SQRT](16)` is
# `math.sqrt(16)` = 4.0 (1082130432). The row is in .agents/slop/exec_gate.bend, printed as
# KNOWN-FAIL so it cannot be mistaken for a pass. `op_is_mathy` sends SQRT to the float lane and
# `f_of` reads the 16 as 16.0, so the fault is inside the lane input, not the lane choice.
# TODO(p3) runtime/ops_python.py:138  symbol=__call__ -- the float lane's input for an int dtype."""),
]

apply(F, EDITS)
