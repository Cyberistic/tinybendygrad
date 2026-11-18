<!-- FROM: tinybendygrad/uop/ops.bend:5125 -->
# BLOCK:
# THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason.
#
# THESE ARE NOT DEFS, ON PURPOSE. A def whose body answers a placeholder would be
# a stub, and the brief for this file rules stubs out: a stub hides the wall, and
# the wall is the thing this unit exists to find. So each entry is the Python
# name, its line, and the constraint that stops it being written today.
# `rg "TODO(p3)" tinybendygrad/uop/ops.bend` is the work queue and the line
# numbers are the Python's, so the queue diffs against ops.py line for line.
#
# THE TWO CONSTRAINTS, and both are Bend rules rather than choices.
#
#   A. A self-call must pass a FIELD of its own parameter. The arena's "field" is
#      a U32 read back out of a store, which the checker cannot see as a subterm.
#      Measured: `def f(u: U32): case _: f(U32.sub(u, 1))` is refused with
#      "expected : a decreasing self-call". So every property fold over the graph
#      -- dtype, _shape, device, addrspace, _ranges, _min_max, key, axis, marg,
#      ended_ranges, bool_slice, backward_slice, trace_num, tuplize, vmin, vmax --
#      has no legal recursion as written. `toposort` above DOES work, because its
#      recursion is on a WORKLIST: a list tail of its own parameter, with the node
#      being visited as a payload. The property folds have no such payload.
#
#   B. Mutual recursion is refused, and tinygrad's folds are a cycle.
#      `dtype_from_uop` reads `src[0]._shape` (the INDEX arm's image test) and
#      `_shape` reads `src[0].dtype` (the BITCAST arm's itemsize ratio); and
#      `simplify()` calls `graph_rewrite`, whose rules call `dtype` and `shape`.
#      Python breaks that cycle with `recursive_property`'s memo on
#      `node.__dict__`, which this port does not have -- see the header, point 5.
#
# so the folds do not fit in one BEND module as the python is written. The fix is
# known and it is not a hack: fold dtype and shape together into ONE def that
# answers the pair, drive it with a Kahn worklist (the shape `toposort` above
# already has), and keep `graph_rewrite` out of that module, because nothing in
# the rewrite engine may call back into the fold. That is a P3 design decision
# and it is written down in spec/ops.md.
# ops.py:1-500. WHERE EACH NAME ACTUALLY LIVES NOW.
#
# lies: the def was already written, in ANOTHER file, and the queue was the only
# thing that did not know it. `rg "TODO(p3)"` is the work queue, so a stale entry
# is not a note -- it is work that gets done twice, or a name the next agent
# re-derives from scratch. So every ops.py line in [1, 500] is now in exactly one
# of three buckets, and the two that are PORTED have no queue line at all:
#
#   PORTED HERE         a real def in this file, with its rows.
#   PORTED ELSEWHERE    a real def in the named file, with its rows. The queue
#                       entry is DELETED, not deferred: the wall is not this
#                       file's to clear, and writing it here would be a second
#                       implementation of a thing that already has one.
#   STILL A WALL        a Bend rule no arrangement in THIS file beats. Kept in
#                       the queue WITH the rule, so the next agent does not spend
#                       an hour rediscovering it.
# PORTED HERE, 2026-10-03. Four defs, above `pm_r_sink`:
#     bsl.go, UOp.backward_slice (ops.py:280), UOp.backward_slice_with_self (:286)
#     op_in_bsl.go, UOp.op_in_backward_slice_with_self (:289)
# They are BELOW the toposort they are written in terms of, and Python has them
# above it, because Bend has no forward references. Gated by `bsl_<tag>` and
# `bsws_<tag>` over four fixtures plus six `bsop_<tag>_*` Booleans: 14 rows, three
# lanes, byte-identical. The `call` and `nest` fixtures are the ones that carry
# `enter_calls=False`; `bsl_chain` would agree with a plain `toposort`.
# PORTED ELSEWHERE -- `uop/render.bend`, which IMPORTS this file, so nothing here
# can call it and nothing here should re-implement it.
#     ops.py:18  AxisType.__repr__   -> axis_repr        (render.bend:550)
#     ops.py:41  ParamArg.__repr__   -> paramarg_repr    (render.bend:501)
#     ops.py:269 UOp.__repr__        -> pretty_print, render.bend's `pyrender`
# The first two are reached by `arg_repr`'s `ARange` and `AParam` arms, which is
# where the mutation table's `arg_repr ARng` / `arg_repr AParam` labels point; the
# third IS `UOp.__repr__`'s whole body (`return pretty_print(self)`) and it carries
# 25 CPython-compared rows of its own. `repr` is a rendering concern, so
# render.bend is where it belongs.
# PORTED ELSEWHERE -- `uop/fold.bend`, the Kahn worklist the block above this one
# describes, and the reason the entries below are walls and not chores.
#     ops.py:329 UOp._shape        -> fold.shape.of / dt_shape  (fold.bend:882)
#     ops.py:456 UOp.shape         -> UOp.shape                (fold.bend:3994)
#     ops.py:470 UOp.ended_ranges  -> UOp.ended_ranges         (fold.bend:3969)
# `UOp.dtype` came with them, and `dtype` is what every remaining entry below reads.
# STILL A WALL. Each names the rule, and each is ALSO in the NOT PORTED block at
# the foot of this file, where the reason is longer.
# TODO(p3) ops.py:76  def srender
#   `x.render()` is render.bend's and `str(x)` is its `const_repr`. Both live in
#   the file that imports this one, so the two-arm dispatch cannot be written here.
# TODO(p3) ops.py:1169  def sym_infer
#   `exec` in `_sym_fxn` builds Python source from the graph and runs it in a
#   namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`. Bend has no
#   `eval`, so this needs a C effect that compiles a lambda or a tree-walking
#   interpreter. P3/P6.
# WALL(p3) ops.py:212  def __init__ -- BLOCKED. STORE A FUNCTION IN A DATA FIELD -- `recursive_property.__init__` keeps `self.fxn`. The
#   port's own note at the `t_*` block says a function value in a FIELD forces `Type`, not
#   `Data`, MEASURED. (A function as a PARAMETER is fine -- `bend guide:69` says functions may
#   be stored, passed and returned, and `Maybe.map` already takes one.)
# TODO(p3) ops.py:216  def __get__
#   `recursive_property` stores a FUNCTION in a record field (`self.fxn = fxn`),
#   and a function value in a field forces `Type`, not `Data` -- measured, and the
#   reason the rule tables in this file are linear. The `__get__` half is the memo
#   the header's point 5 drops, and its GATE is `self.nm not in node.__dict__`:
#   a memo-less port cannot answer that, because the predicate is vacuously true
#   for every node and the "gate" would visit the whole slice unconditionally.
# WALL(p3) ops.py:240  def __del__ -- BLOCKED. NO GARBAGE COLLECTOR TO CALL IT. `bend guide:646` -- "values are affine, a `match` frees
#   the node it opens" -- so there is no `__del__` hook and nothing for it to remove itself
#   from. The `ucache` it deletes from is Python's, and this port's interner is
#   `intern.find`'s direct comparison, not a table a node has to leave.
#   Refcount-driven eviction from `ucache`. The arena is monotone, so nothing is
#   ever evicted and there is nothing to port.
# WALL(p3) ops.py:244  def __reduce__ -- BLOCKED. THE PICKLE PROTOCOL. `return UOp, (op, src, arg, tag, metadata)` is a `__reduce__`: an
#   instruction to Python's `pickle`. Nothing in the port serialises a live UOp, so there is
#   no protocol to implement.
#   Pickling. A `U32` index and an `Arena` are not picklable objects, and this
#   file has no process boundary to pickle across.
# TODO(p3) ops.py:261  def key
#   `hashlib.sha256` over `str((op, dtype, arg))` and the srcs' keys concatenated.
#   Two walls: the digest is a C effect (`tinygrad/runtime/`'s), and the string
#   half reads `dtype`, which is `fold.bend`'s -- so neither half is writable here.
# wall(p3) ops.py:284  def _bool_slice -- blocked. needs `fold`'s walk and a dtype predicate, so it lives downstream of this file like
#   `_eval`, `param_noshape` and `wk_is_virtual` do -- `dt_is_bool` is in `mixin/dtype.bend`
#   and this file cannot import it (`ops.bend:87`). Its only consumer is a marker of its own:
#   `uop/symbolic.bend:3045 symbol=fx_ne0` records that `fold_where_closure` needs `bool_slice` AND
#   `substitute`, so porting this alone closes nothing downstream. THE INTERNING DOES MAKE
#   IT CHEAPER THAN CPYTHON'S: two structurally equal nodes share an arena index, so the
#   `frozenset[UOp]` is a deduped index list and needs no hash.
# TODO(p3) ops.py:287  def bool_slice
#   A `recursive_property` over the srcs, gated on `self.dtype is dtypes.bool`.
#   `dtype` is `fold.bend`'s, so both halves belong to the worklist beside it; and
#   `bool_slice`'s `| {self}` is a self-reference the fold has to add OUTSIDE its
#   own memo, which is what Python's comment above the property says.
# wall(p3) ops.py:316  def tuplize -- blocked. the mechanism is replaced, not missing. `tuplize` builds `(op.value, repr(arg), dtype, *(src
#   tuplize))` to KEY CPython's `ucache`; this port's interner is `intern.find`, a direct
#   comparison over `Arena.nodes`, so there is no hash table for a key to serve. Its two
#   consumers are outside ops.py anyway -- `codegen/late/linearizer.py:36` (a sort) and
#   `uop/symbolic.py:225` (a rewrite rule) -- and neither is ported.
#   `_UOpTuple((op.value, repr(arg), self.dtype) plus every src's tuplize)`:
#   `dtype` again, plus a `recursive_property` over the srcs, plus the sort it
#   feeds. `repr(arg)` is render.bend's `arg_repr`, so this is three files deep.
# TODO(p3) ops.py:444  def shard_shape
# TODO(p3) ops.py:450  def max_shard_shape
#   `shard_shape` reads `self.device` (fold), `self.axis` (fold) and `self.shape`
#   (fold), and `max_shard_shape` is `to_max_shape(shard_shape)`, a fold over a
#   `Sint` list. Every input is the worklist's, so these are fold.bend's rows;
#   `schedule/multi.bend` is the caller and it inlines what it can today.
# PORTED -- `ops.py:481 _ranges` and `ops.py:495 ranges` are `fold.bend`'s
# `Ranged` / `UOp.ranges` (fold.bend:5067 symbol=UOp.ranges), 12 `rg_*` rows byte-identical to
# CPython. The reason these two carried for a month -- "Dict set algebra over the
# with a membership test, and `ended_ranges` is ported too (uop/fold.bend:2837 symbol=ended_of).
# TODO(p3) ops.py:479  def ranges
#   Dict set algebra over the fold's memo: union every src's ranges, then `pop` the
#   ones the ended ranges close. The wall is named where it is HIT --
#   `schedule/rangeify.bend:204 symbol=rf_in_ranges`, whose `rf_in_ranges` is the standing stub.
# TODO(p3) ops.py:495  def simplify
#   # * uop evaluation *
# DONE(p3) ops.py:92 def ssimplify -- `ssimplify_of` and `UOp.ssimplify_val` /
#   `UOp.ssimplify_is_val`, with `cval_arg` (written for `pop_const`) as the value reader. Gated at
#   `gates/ops-core-gate.py` in SIX rows over THREE fixtures, and the third fixture is the one
#   that makes the other two mean something: a CAST of a PARAM satisfies neither of CPython's
#   conditions, so CPython hands the NODE back -- a THIRD answer, neither a value nor an absence.
#
#   IT DOES NOT NEED `simplify`, which is the finding rather than a convenience. `simplify` is a
#   documented wall in this file (`ops.py:511`, "* uop evaluation *") and 3,679 lines of
#   partial symbolic work sit behind it, so anything that truly required a rewriter would be
#   stuck on the largest subsystem here. But a CONST is already reduced, so `simplify` is the
#   IDENTITY on it, and the CAST arm's test is a SHAPE test on the node rather than a rewrite.
#   What is left out is `ret.dtype.const(...)` -- the dtype round trip -- and `wk_dt` already
#   answers a node's dtype, so the value half is the whole of the discriminating claim.
#   Planted: a reader that answers `none` for everything fails `ss_const_val` and
#   `ss_cast_const_val` and nothing else.
# done(p3) ops.py:521 def _eval -- and it was misfiled here, which is the finding. `_eval` needs
#   the node's dtype AND its two bounds, and this file imports only `Base`, `helpers` and
#   `LAWS/spec`, while `UOp.vmin`/`vmax` are in `fold.bend` and the node-level dtype reader is in
#   `weak.bend` -- and BOTH of those import `ops.bend`. So the def sits DOWNSTREAM of the file
#   that wanted it: an import edge, not a language limit, and the same relocation
#   `wk_commit_dtype` already got. It is now `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` in
#   `weak.bend`, gated at `gates/wk-eval-gate.py`: 16 rows, 3 lanes, 15 identical to CPython and
#   ONE documented divergence.
# TODO(p3) ops.py:511  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
#   `bool_on_i32`).
# TODO(p3) ops.py:512  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
#   `int_on_range`).
# TODO(p3) ops.py:513  def __float__  -- DONE, same gate (`float_weakfloat`,
#   `float_on_i32`).
# TODO(p3) ops.py:514  def substitute
# TODO(p3) ops.py:521  def __index__
#   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking
# TODO(p3) ops.py:526  def trace_num
# WALL(p3) ops.py:563  def __getitem__ -- BLOCKED. PYTHON'S SLICE PROTOCOL. The body calls `super(UOp, self).__getitem__(idx)`,
#   `argfix`, `_normalize_indices`, `slice` objects and `self.shape[i]`. A slice is a Python
#   runtime object with `start`/`stop`, and Bend has no slicing syntax to normalise.
# done(p3) ops.py:597 def _uop -- and the honest answer is that there is nothing to
#   WRITE. CPython's is `def _uop(self) -> UOp: return self`, which is the IDENTITY, and
#   it is the identity because `Tensor` SUBCLASSES `UOp`. This port's
#   `type Tensor is Data: Tensor{ar, uop, is_param, grad}` (`tensor.bend:186`) is a RECORD
#   WRAPPING a U32 index, so it is not a UOp -- and the port's node reference is already a
#   `Found`, which IS the UOp reference. There is no unwrap on this side to perform.
#   the tensor side of the same name is ported and gated elsewhere: `tensor.bend:192-195`
#   names `Tensor.u` as `_uop -- tensor.py:118` and every graph-building method there
#   reads that field in place of `self.uop`. So the NAME is done, from the side that has
#   something to do.
# done(p3) ops.py:599 def _wrap_uop -- same reason, and it is the stronger one.
#   CPython's is `@classmethod def _wrap_uop(cls, u: UOp) -> UOp: return u`, so it returns
#   its argument UNCHANGED. It exists at all because `Tensor` subclasses `UOp`: without the
#   subclassing, a `UOp` passed where a `Tensor` is expected would not be one, and this
#   would have to convert rather than hand back. The port has no such gap -- `Tensor` is a
#   record wrapping a `U32` and a `Found` is a `U32` plus an arena -- so there is no
#   coercion to bridge and no def to write. a marker that asks for a function which is
#   CORRECTLY ABSENT IS A WALL, NOT A GAP, and the reason it was a marker at all is that
#   nobody had written down WHICH kind it was.
# TODO(p3) ops.py:581  def const_like
# TODO(p3) ops.py:587  def ufix
# TODO(p3) ops.py:594  def store
# TODO(p3) ops.py:603  def ins
# TODO(p3) ops.py:604  def contract
#   # cast, except for CONST, in which case rebuild a new CONST at the dtype
# TODO(p3) ops.py:621  def cconst
#   ops.py:610 -- a FORCED CAST is needed for bool because the ordinary cast
#   folds at bool, so `UOp.const` cannot state that width.
# TODO(p3) ops.py:630  def wmma
#   ops.py:622 -- the input dtype lives in the arg, not in `src[0].dtype`,
#   because a BITCAST rewrite changes the src dtype.
# PORTED -- `ops.py:652 _rop` is `tensor.bend`'s `tn_rop`, which is
# `tensor.bend:1822` symbol=tn_rop.
# TODO(p3) ops.py:644  def invalid
# DONE(p3) ops.py:664 def valid -- `UOp.where` and `UOp.valid_of` above, gated at
#   `gates/ops-core-gate.py` in FOUR rows. `where` is `mixin/elementwise.py:426`'s
#   `self.alu(Ops.WHERE, x, y)`, i.e. `UOp(Ops.WHERE, src=(cond, x, y))`, and it is the constructor
#   `UOp.valid_of` is one line on top of.
#
#   defs, could not read their own src fields back, and reverted them as "an unverifiable
#   constructor". The truth is the arena rule this project already records: each `UOp.const` grows
#   the arena and answers a node in the GROWN one, so reading an index against the original `ar0`
#   finds a different node -- I read `ANone{}` out of three srcs that were there all along. MEASURED
#   with a probe: threaded wrongly, all three read `ANone{}`; threaded right,
#   `cbool:True|cbool:True|cinvalid`.
#
#   so the rule for this whole file is narrower than i wrote it last time. Three defs moved
#   downstream because `ops.bend` cannot name `fold.bend`'s bounds or import `dtype.bend`. THIS one
#   needed neither: it was a bug in the CALLER's arena discipline, and the def was always writable
#   here. "Cannot read it back" is not evidence that it cannot be written.
#   PLANTED: swapping the two trailing srcs fails `valid_src1` and `valid_src2` together.
# TODO(p3) ops.py:646  def get_idx
# TODO(p3) ops.py:652  def reduce
# TODO(p3) ops.py:661  def overflows
#   `def overflows(self, dtype: DType) -> bool: return self.vmin < dtype.min or
#   dtype.max < self.vmax`. Two comparisons and no minting, which is why it looks
#   like the cheapest def on this list. It is not, and the reason is a QUESTION
#   rather than a wall:
#
#   CPython's `vmin`/`vmax` are concrete ints. This port's are
#   `Maybe<&2, Bnd>` (`uop/fold.bend`:4498), and `Bnd` is
#   `Bnd{inf} | BndInt{neg, mag} | BndFlt{v}` -- an INTEGER OR A FLOAT OR AN
#   INFINITY, symbolically. So `vmin < dtype.min` is not one comparison, it is a
#   comparison over that union, and the honest answer to "is `vmin` below the dtype
#   minimum" when `vmin` is SYMBOLIC is neither True nor False: it may be undecidable
#   until the range table resolves it.
#
#   `Bool` has no third value, and defaulting unknown to False makes the port assert
#   a range is SAFE when it has not been shown to be. That is the one failure mode a
#   dtype fold must not have, and it is why this is not ported as a one-liner with
#   `Bool.or(lt(...), lt(...))`.
#
#   The shape it needs: a THREE-valued predicate over `Bnd` (below / provably not
#   below / unresolved), and a decision about what the two-valued public answer does
#   with the third -- almost certainly "not overflowing is a MAYBE, and every caller
#   that needs certainty has to say so".
#
#   `bnd.lt` DOES exist -- `fold.bend:3266`, with `bnd.eq` at `:3317` -- and an
#   narrower and stranger than "add an ordering": `bnd.lt` is a TWO-valued TOTAL
#   answer over `BndInt`, and what is missing is the third.
#
#   AND `dt_max` IS NOT A SUBSTITUTE FOR IT. `dtype.bend`'s `dt_max` answers
#   `int64.max` for `uint64` -- the `i64_max_u` fallthrough, `dtype.bend:366-375` --
#   which is documented as safe only because that bound is read as `hi <= max`.
#   `uint64.max` is `2**64-1` and `int64.max` is `2**63-1`, so borrowing the table
#   here would make every `uint64` bound wrong by a factor of two. This needs `Bnd`.
#   P3, with `vmin`/`vmax`.
# WALL(p3) ops.py:670  def unshard -- BLOCKED. `def _shard` IS ABSENT -- checked as a definition, comments excluded. `unshard` builds a
#   UNSHARD and `_shard` is the constructor it shares with `shard` below.
#   ops.py:663-665 -- an UNSHARD carries one sharding RANGE per sharded axis;
#   the range need not be DEVICE, so a LOCAL range may shard a tile.
#   # * multi-device helpers *
# WALL(p3) ops.py:690  def bounds -- BLOCKED. `def max_numel` IS ABSENT, and `bounds` also reads `self.axis` and a device COUNT
#   (`len(self.device)`, on the `Dev` tag). It is a `itertools.accumulate` + `pairwise`
#   over per-axis shapes.
# TODO(p3) ops.py:715  def axis
# TODO(p3) ops.py:728  def _shard
# WALL(p3) ops.py:734  def shard -- BLOCKED. `def _shard` IS ABSENT -- the same one `unshard` needs. `copy_to_device` IS present, so
#   this is one missing constructor rather than a missing subsystem.
#   `def param_like` IS ABSENT, and `store_call`'s body is two of them:
# TODO(p3) ops.py:746  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.
#   a device is a `U32` tag here, not a string: `type Dev is Data: D1{tag: U32}`. So a device name has no prefix to test, and the two below are exactly a `startswith`:
# TODO(p3) ops.py:755  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
# TODO(p3) ops.py:756  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
#   # little helpers
# PORTED -- `ops.py:818 _mop` is `tensor.bend`'s `tn_mop`, which is
# `tensor.bend:1685` symbol=tn_mop.
# TODO(p3) ops.py:835  def new_buffer
# TODO(p3) ops.py:843  def from_buffer
#   ops.py:821 -- both the storage identity and the dtype interpretation are
#   part of the UOp key; a buffer reused under another dtype is another node.
#   `def canonicalize_device` and `def is_disk_device` ARE BOTH ABSENT, and both start with one:
# TODO(p3) ops.py:849  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
# TODO(p3) ops.py:867  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.
# TODO(p3) ops.py:855  def _frompy
# DONE(p3) ops.py:902 def is_virtual -- `wk_is_virtual` in `weak.bend`, `no_dev` beside it.
#   `device is None or dtype in weaks`, and the device half needs a node that CARRIES a `Dev`:
#   `fold.bend`'s `mw_pa` hard-codes `ParamArg`'s device field to `None{}`.
#   the claim that no DEF in the port sets it was FALSE. measured 2026-10-30:
#   `renderer/__init__.bend:441` builds a `ParamArg` with `device = Some{S.D1{0}}`, and
#   `fold.bend`'s `device_of.param` reads `O.ParamArg.device(pa)`, so a node that CARRIES a
#   device was reachable all along. The rows are `gates/wk-isvirt-gate.py` -- 5 rows, 3 lanes,
#   0 divergences, and three mutations that each move the row they name.
# TODO(p3) ops.py:931  def contiguous_view
#   `def contiguous_view` IS ABSENT, and both of these ask it first:
# TODO(p3) ops.py:941  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
# TODO(p3) ops.py:957  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.
# wall(p3) -- storage, device and alloc. no live `Buffer` -- there is no `type Buffer is Data` anywhere in the port and zero `Buffer{` constructors. tinygrad's Buffer is an allocated object with a `realized` field and a `memory`
# TODO(p3) ops.py:950  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
# TODO(p3) ops.py:988  def realized  -- BLOCKED, and ANSWERS a Buffer.
# TODO(p3) ops.py:999  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
# TODO(p3) ops.py:757  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.
# TODO(p3) ops.py:974  def buffer
# PORTED -- `ops.py:1015 UOp.variable` is `UOp.variable` (this file), four `vrn_*`
# rows byte-identical to CPython on all three lanes via
# `sh .agents/slop/ops-vrn-gate.sh`, with six mutations in
# `.agents/slop/ops-vrn-mutate.py` each moving EXACTLY the rows it names.
#
# IT WAS BLOCKED ON A NAME, NOT ON A SUBSTRATE. CPython writes `slot=-1` and this
# file's `ParamArg.slot` is a `U32`, so the def needed a name for "no POSITIONAL
# slot" and the file that OWNS the field had none -- while `function.bend`,
# `codegen/kernel.bend`, `codegen/late/linearizer.bend` and `uop/symbolic.bend` had
# each invented one. `ParamArg.no_slot()` (this file) is the single name, landed the
# commit before, and this def is the first thing it unblocked.
#
# `is_variable` (ops.py:1020) is STILL BLOCKED and this does not change that: its
# fifth conjunct is `self._shape == ()` and `Node{op, src, arg, tag}` has no shape
# field. The `vrn_*` rows print `nsrc` as the closest honest proxy and the `is_
# variable` marker says why that is not the same question.
#   ops.py:1020  def is_variable
#     `self.op is Ops.PARAM and isinstance(self.arg, ParamArg) and self.arg.vmin_vmax
#     is not None and self.arg.addrspace is AddrSpace.ALU and self._shape == ()`.
#     FOUR of the five conjuncts are functions of `Node{op, src, arg, tag}`. The
#     fifth is not, and that is the whole of the wall: this arena's Node has NO
#     SHAPE FIELD. `Arena{nodes, shp}`'s `shp` is the arena's own table, not a
#     per-node shape, so `self._shape` has nowhere to be read from.
#
#     A four-of-five port is not a partial port, it is a WRONG ANSWER: it returns
#     True for a PARAM with a src, which is not a scalar, which upstream says is
#     not a Variable. Every caller of `is_bound_var`, `unbound` and `bind` would
#     then take the Variable path on a non-Variable. So the four readable
#     conjuncts are NOT landed, and `expr` -- the one def of the lattice whose
#     answer is a function of the ARG ALONE -- is landed instead.
#
#     Unblocking it is a substrate change, not a port: `Node` needs a shape, or an
#     accessor that derives one. P3, with the shape work `uop/fold.bend` already
#     owns for the fold.
#   ops.py:1025  def is_bound_var
#     `self.is_variable and self.arg.val is not None`. The second conjunct is two
#     fields of a `ParamArg` and both are readable; the first is `is_variable`
#     above. Gated on it, not on anything of its own.
#   ops.py:1032  def bind
#     `assert self.is_variable and not self.is_bound_var; uval = UOp.const(val) ...
#     return self.replace(arg=replace(self.arg, val=uval.val))`. THREE dependencies
#     and none of them is this def: `is_variable` (the shape wall), `self.vmin <=
#     uval.vmin and uval.vmax <= self.vmax` (`uop/fold.bend`'s `vmin`/`vmax` over
#     the range table) and `uval.divides(self.arg.multiple_of)` (ops.py:1069, not
#     ported). `self.replace` is `UOp.new` and needs no port -- the arena IS the
#     intern table -- which is the one part of this def that is ready.
#   ops.py:1039  def unbound
#     `assert self.is_variable; return self.replace(arg=replace(self.arg, val=None),
#     tag=None)`. The REWRITE is two field writes, both readable, and `replace` is
#     `UOp.new`, so the def itself is nearly free. It is gated on the assert only,
#     and the assert is `is_variable`: without that conjunct the def would clear
#     `val` on nodes upstream refuses to touch, and a gate that cannot see the
#     difference is not a gate.
#   ops.py:1043  def unbind
#     `assert self.is_bound_var; return self.unbound(), self.arg.val`. Both halves
#     are the two defs above, including the assert.
#   ops.py:1046  def unbind_all
#     `{x: x.unbound() for x in self.backward_slice_with_self if x.is_bound_var}` and
#     then `self.substitute(bound, walk=True)`. The slice and the dict build are
#     `bsl.go`'s shape and readable; `substitute` (ops.py:514 symbol=UOp.substitute) is not ported, and
#     the dict is keyed by a `UOp` in Python, which in this arena means keyed by an
#     INDEX whose validity is a session property. P3, with `substitute`.
#   ops.py:1049  def variables
#     Walks the backward slice collecting `x.unbound() if x.is_variable else x` and
#     an `_device_num` Variable per DEVICE RANGE, then `sorted(ret, key=lambda v:
#     (v.arg.name or "", v.arg.slot))`. The sort key is `(Maybe<String>, U32)` and
#     the `or ""` is Python's `None`-sorts-first, which this port has to state
#     rather than inherit. Gated on `is_variable` and on the shape wall.
# * uop symbolic stuff *
# AND `const_factor` IS DONE -- MEASURED 2026-11-08: `def UOp.const_factor(fuel, ar, i) ->
# H.I64` IS AT `:7752` AND `def UOp.divides(fuel, ar, v, i) -> Dv` IS AT `:7972`. THE `TODO`
# that used to stand here was stale against a `DONE` NOTE eleven lines below it, and a `TODO`
# beside a `DONE` for the same DEF is a ledger that disagrees with itself.
# DONE(p3) ops.py:1048 def const_factor -- `UOp.const_factor` above, FLATTENED: the def and
#   its fold are not mutually recursive once the arms are read (a STACK/ADD contributes the
#   gcd identity and every other node is a leaf), so `cf.walk` is a FUEL-bounded worklist.
#   The "Bend cannot express that" probe below was measuring the OBVIOUS spelling.
# DONE(p3) ops.py:1082 def pop_const -- `UOp.pop_const_val` / `UOp.pop_const_hits` above, with
#   `cval_arg`. Gated at `gates/ops-core-gate.py` in EIGHT rows over FOUR fixtures, and the
#   fixtures are built so the def's TWO conditions fail SEPARATELY: a second src that is not a
#   CONST, and a `MUL` popped as an `ADD`. Planted -- dropping the `op` comparison from
#   `pop_const_hits` fails exactly `pop_mul_const_hits` and nothing else, which is what says the
#   op is COMPARED rather than assumed. The value is a `Const` and not an `H.I64`: an I64-only
#   reader recorded a divergence on the float fixture that was really just a narrow type, and
#   `pop_const` returns whatever the CONST carries.
# TODO(p3) ops.py:1073  def gcd
# TODO(p3) ops.py:1079  def divide_exact
# TODO(p3) ops.py:1090  def vmin
# TODO(p3) ops.py:1092  def vmax
# TODO(p3) ops.py:1106  def _min_max
# TODO(p3) ops.py:1168  def _sym_fxn
# TODO(p3) ops.py:1169  def sym_infer
# TODO(p3) ops.py:1173  def render
# TODO(p3) ops.py:1181  def render_uir  -- upstream's `pyrender` was DELETED before this pin.
#   `def view_as` IS ABSENT, and the alloc family ends in one:
# TODO(p3) ops.py:1188  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
# TODO(p3) ops.py:1194  def alloc_like  -- BLOCKED, and delegates to `alloc`.
# TODO(p3) ops.py:1206  def placeholder  -- BLOCKED, and ends `view_as`.
# TODO(p3) ops.py:1208  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.
# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). The def, its fixture,
# its four rows and its gate landed inside a CONCURRENT agent's commit rather than
# one of mine, so the history does not attribute them; the write-up is here and at
# the gate, which is where a reader lands anyway. Four `set_*` rows
# byte-identical to CPython on all three lanes via `sh .agents/slop/ops-set-gate.sh`,
# with TWO negative controls that are the two bugs below.
#
#   # set is store+end+after
#   def set(self:UOp, val:UOp|ConstType, end:UOp|tuple[UOp, ...]|list[UOp]=()) -> UOp:
#     return self.src[0].after(self.store(val).end(*argfix(end)))
#
# Upstream's own comment says the whole of it, so the def has no logic: it is a
# COMPOSITION, and the only things a row can test are that the three pieces are
# wired in this ORDER and that `argfix`'s empty arm is honoured. The number of
# `end` operands is the only input that varies, so it is the only thing the family
# varies. `argfix` is already ported as `argfix1`/`argfix2`/`argfix_seq`
# (helpers.bend:536-543), so `end` is a `Maybe<&2, List<&2, U32>>` and not a node.
#
# TWO BUGS, AND BOTH COMPILED.
#
#   THE STALE ARENA. The first draft was
#       +e = UOp.end(ar, Found.i(s), ...)          -- `ar`, the CALLER's
#   and `UOp.store` MINTS, so `s` lives in a GROWN arena and `Found.i(s)` read out
#   of `ar` indexes the wrong arena. It typechecked and answered
#   `Ops.AFTER(Ops.BUFFER Ops.AFTER)` where CPython answers
#   `Ops.AFTER(Ops.BUFFER Ops.STORE)`. That is the failure mode bend2-constraints
#   names, and `UOp.copy_to_device` above is the fix in one line: thread the
#   previous step's `Found.ar`. The first negative control reintroduces it.
#
#   THE SUBJECT IS A STORE. The first fixture was a BUFFER and CPython raised
#   `IndexError: tuple index out of range`, because `set` is called ON a store and
#   `src[0]` is the store's target. A fixture that does not reach the code is a
#   fixture that cannot fail, and this one looked like a red gate.
#
# and a printer that was three drafts worse than it needed to be: a recursive
# `deep` needing a closer that knows its own depth, a `Bool.pick` for the first
# separator, and a fold that opened a paren in the accumulator. The file already
# had the shape under another name (`Rng.srcops.go`'s `+first` flag). Grep for
# the IDIOM before writing the INSTANCE.
#   # set is store+end+after
# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `THE PORT's `uop/ops.bend` HEADER` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. the rule is not "those three were misfiled" but "a DEF needing a dtype predicate or a
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   the other two arms are not ported and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and `view_as` IS ABSENT FROM THE PORT
#   (so is `unique_num`). Checked, not assumed.
# TODO(p3) ops.py:1228  def param_like
# TODO(p3) ops.py:1236  def view_as
# custom_function -- ops.py:1258 upstream. `UOp(Ops.CUSTOM_FUNCTION, src=src,
# arg=CustomFunction(name, dtype))`. The pin's spelling was ops.py:1256 and took no
# dtype, because there was no `CustomFunction` to hold one.
# `dtype=dtypes.void` is upstream's DEFAULT and Bend has no default argument, so `dt`
# is required here and `CustomFunction.of(name)` builds the void-dtype value.
# `UOp.call` below is NOT PORTED, so nothing in this file consumes the dtype yet:
# `dtype_from_uop` is not ported either (the folds do not fit, see the header).
# END BLOCK

# THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason.
#
# THESE ARE NOT DEFS, ON PURPOSE. A def whose body answers a placeholder would be
# a stub, and the brief for this file rules stubs out: a stub hides the wall, and
# the wall is the thing this unit exists to find. So each entry is the Python
# name, its line, and the constraint that stops it being written today.
# `rg "TODO(p3)" tinybendygrad/uop/ops.bend` is the work queue and the line
# numbers are the Python's, so the queue diffs against ops.py line for line.
#
# THE TWO CONSTRAINTS, and both are Bend rules rather than choices.
#
#   A. A self-call must pass a FIELD of its own parameter. The arena's "field" is
#      a U32 read back out of a store, which the checker cannot see as a subterm.
#      Measured: `def f(u: U32): case _: f(U32.sub(u, 1))` is refused with
#      "expected : a decreasing self-call". So every property fold over the graph
#      -- dtype, _shape, device, addrspace, _ranges, _min_max, key, axis, marg,
#      ended_ranges, bool_slice, backward_slice, trace_num, tuplize, vmin, vmax --
#      has no legal recursion as written. `toposort` above DOES work, because its
#      recursion is on a WORKLIST: a list tail of its own parameter, with the node
#      being visited as a payload. The property folds have no such payload.
#
#   B. Mutual recursion is refused, and tinygrad's folds are a cycle.
#      `dtype_from_uop` reads `src[0]._shape` (the INDEX arm's image test) and
#      `_shape` reads `src[0].dtype` (the BITCAST arm's itemsize ratio); and
#      `simplify()` calls `graph_rewrite`, whose rules call `dtype` and `shape`.
#      Python breaks that cycle with `recursive_property`'s memo on
#      `node.__dict__`, which this port does not have -- see the header, point 5.
#
# so the folds do not fit in one BEND module as the python is written. The fix is
# known and it is not a hack: fold dtype and shape together into ONE def that
# answers the pair, drive it with a Kahn worklist (the shape `toposort` above
# already has), and keep `graph_rewrite` out of that module, because nothing in
# the rewrite engine may call back into the fold. That is a P3 design decision
# and it is written down in spec/ops.md.
# ops.py:1-500. WHERE EACH NAME ACTUALLY LIVES NOW.
#
# lies: the def was already written, in ANOTHER file, and the queue was the only
# thing that did not know it. `rg "TODO(p3)"` is the work queue, so a stale entry
# is not a note -- it is work that gets done twice, or a name the next agent
# re-derives from scratch. So every ops.py line in [1, 500] is now in exactly one
# of three buckets, and the two that are PORTED have no queue line at all:
#
#   PORTED HERE         a real def in this file, with its rows.
#   PORTED ELSEWHERE    a real def in the named file, with its rows. The queue
#                       entry is DELETED, not deferred: the wall is not this
#                       file's to clear, and writing it here would be a second
#                       implementation of a thing that already has one.
#   STILL A WALL        a Bend rule no arrangement in THIS file beats. Kept in
#                       the queue WITH the rule, so the next agent does not spend
#                       an hour rediscovering it.
# PORTED HERE, 2026-10-03. Four defs, above `pm_r_sink`:
#     bsl.go, UOp.backward_slice (ops.py:280), UOp.backward_slice_with_self (:286)
#     op_in_bsl.go, UOp.op_in_backward_slice_with_self (:289)
# They are BELOW the toposort they are written in terms of, and Python has them
# above it, because Bend has no forward references. Gated by `bsl_<tag>` and
# `bsws_<tag>` over four fixtures plus six `bsop_<tag>_*` Booleans: 14 rows, three
# lanes, byte-identical. The `call` and `nest` fixtures are the ones that carry
# `enter_calls=False`; `bsl_chain` would agree with a plain `toposort`.
# PORTED ELSEWHERE -- `uop/render.bend`, which IMPORTS this file, so nothing here
# can call it and nothing here should re-implement it.
#     ops.py:18  AxisType.__repr__   -> axis_repr        (render.bend:550)
#     ops.py:41  ParamArg.__repr__   -> paramarg_repr    (render.bend:501)
#     ops.py:269 UOp.__repr__        -> pretty_print, render.bend's `pyrender`
# The first two are reached by `arg_repr`'s `ARange` and `AParam` arms, which is
# where the mutation table's `arg_repr ARng` / `arg_repr AParam` labels point; the
# third IS `UOp.__repr__`'s whole body (`return pretty_print(self)`) and it carries
# 25 CPython-compared rows of its own. `repr` is a rendering concern, so
# render.bend is where it belongs.
# PORTED ELSEWHERE -- `uop/fold.bend`, the Kahn worklist the block above this one
# describes, and the reason the entries below are walls and not chores.
#     ops.py:329 UOp._shape        -> fold.shape.of / dt_shape  (fold.bend:882)
#     ops.py:456 UOp.shape         -> UOp.shape                (fold.bend:3994)
#     ops.py:470 UOp.ended_ranges  -> UOp.ended_ranges         (fold.bend:3969)
# `UOp.dtype` came with them, and `dtype` is what every remaining entry below reads.
# STILL A WALL. Each names the rule, and each is ALSO in the NOT PORTED block at
# the foot of this file, where the reason is longer.
# TODO(p3) ops.py:76  def srender
#   `x.render()` is render.bend's and `str(x)` is its `const_repr`. Both live in
#   the file that imports this one, so the two-arm dispatch cannot be written here.
# TODO(p3) ops.py:1169  def sym_infer
#   `exec` in `_sym_fxn` builds Python source from the graph and runs it in a
#   namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`. Bend has no
#   `eval`, so this needs a C effect that compiles a lambda or a tree-walking
#   interpreter. P3/P6.
# WALL(p3) ops.py:212  def __init__ -- BLOCKED. STORE A FUNCTION IN A DATA FIELD -- `recursive_property.__init__` keeps `self.fxn`. The
#   port's own note at the `t_*` block says a function value in a FIELD forces `Type`, not
#   `Data`, MEASURED. (A function as a PARAMETER is fine -- `bend guide:69` says functions may
#   be stored, passed and returned, and `Maybe.map` already takes one.)
# TODO(p3) ops.py:216  def __get__
#   `recursive_property` stores a FUNCTION in a record field (`self.fxn = fxn`),
#   and a function value in a field forces `Type`, not `Data` -- measured, and the
#   reason the rule tables in this file are linear. The `__get__` half is the memo
#   the header's point 5 drops, and its GATE is `self.nm not in node.__dict__`:
#   a memo-less port cannot answer that, because the predicate is vacuously true
#   for every node and the "gate" would visit the whole slice unconditionally.
# WALL(p3) ops.py:240  def __del__ -- BLOCKED. NO GARBAGE COLLECTOR TO CALL IT. `bend guide:646` -- "values are affine, a `match` frees
#   the node it opens" -- so there is no `__del__` hook and nothing for it to remove itself
#   from. The `ucache` it deletes from is Python's, and this port's interner is
#   `intern.find`'s direct comparison, not a table a node has to leave.
#   Refcount-driven eviction from `ucache`. The arena is monotone, so nothing is
#   ever evicted and there is nothing to port.
# WALL(p3) ops.py:244  def __reduce__ -- BLOCKED. THE PICKLE PROTOCOL. `return UOp, (op, src, arg, tag, metadata)` is a `__reduce__`: an
#   instruction to Python's `pickle`. Nothing in the port serialises a live UOp, so there is
#   no protocol to implement.
#   Pickling. A `U32` index and an `Arena` are not picklable objects, and this
#   file has no process boundary to pickle across.
# TODO(p3) ops.py:261  def key
#   `hashlib.sha256` over `str((op, dtype, arg))` and the srcs' keys concatenated.
#   Two walls: the digest is a C effect (`tinygrad/runtime/`'s), and the string
#   half reads `dtype`, which is `fold.bend`'s -- so neither half is writable here.
# wall(p3) ops.py:284  def _bool_slice -- blocked. needs `fold`'s walk and a dtype predicate, so it lives downstream of this file like
#   `_eval`, `param_noshape` and `wk_is_virtual` do -- `dt_is_bool` is in `mixin/dtype.bend`
#   and this file cannot import it (`ops.bend:87`). Its only consumer is a marker of its own:
#   `uop/symbolic.bend:3045 symbol=fx_ne0` records that `fold_where_closure` needs `bool_slice` AND
#   `substitute`, so porting this alone closes nothing downstream. THE INTERNING DOES MAKE
#   IT CHEAPER THAN CPYTHON'S: two structurally equal nodes share an arena index, so the
#   `frozenset[UOp]` is a deduped index list and needs no hash.
# TODO(p3) ops.py:287  def bool_slice
#   A `recursive_property` over the srcs, gated on `self.dtype is dtypes.bool`.
#   `dtype` is `fold.bend`'s, so both halves belong to the worklist beside it; and
#   `bool_slice`'s `| {self}` is a self-reference the fold has to add OUTSIDE its
#   own memo, which is what Python's comment above the property says.
# wall(p3) ops.py:316  def tuplize -- blocked. the mechanism is replaced, not missing. `tuplize` builds `(op.value, repr(arg), dtype, *(src
#   tuplize))` to KEY CPython's `ucache`; this port's interner is `intern.find`, a direct
#   comparison over `Arena.nodes`, so there is no hash table for a key to serve. Its two
#   consumers are outside ops.py anyway -- `codegen/late/linearizer.py:36` (a sort) and
#   `uop/symbolic.py:225` (a rewrite rule) -- and neither is ported.
#   `_UOpTuple((op.value, repr(arg), self.dtype) plus every src's tuplize)`:
#   `dtype` again, plus a `recursive_property` over the srcs, plus the sort it
#   feeds. `repr(arg)` is render.bend's `arg_repr`, so this is three files deep.
# TODO(p3) ops.py:444  def shard_shape
# TODO(p3) ops.py:450  def max_shard_shape
#   `shard_shape` reads `self.device` (fold), `self.axis` (fold) and `self.shape`
#   (fold), and `max_shard_shape` is `to_max_shape(shard_shape)`, a fold over a
#   `Sint` list. Every input is the worklist's, so these are fold.bend's rows;
#   `schedule/multi.bend` is the caller and it inlines what it can today.
# PORTED -- `ops.py:481 _ranges` and `ops.py:495 ranges` are `fold.bend`'s
# `Ranged` / `UOp.ranges` (fold.bend:5067 symbol=UOp.ranges), 12 `rg_*` rows byte-identical to
# CPython. The reason these two carried for a month -- "Dict set algebra over the
# with a membership test, and `ended_ranges` is ported too (uop/fold.bend:2837 symbol=ended_of).
# TODO(p3) ops.py:479  def ranges
#   Dict set algebra over the fold's memo: union every src's ranges, then `pop` the
#   ones the ended ranges close. The wall is named where it is HIT --
#   `schedule/rangeify.bend:204 symbol=rf_in_ranges`, whose `rf_in_ranges` is the standing stub.
# TODO(p3) ops.py:495  def simplify
#   # * uop evaluation *
# DONE(p3) ops.py:92 def ssimplify -- `ssimplify_of` and `UOp.ssimplify_val` /
#   `UOp.ssimplify_is_val`, with `cval_arg` (written for `pop_const`) as the value reader. Gated at
#   `gates/ops-core-gate.py` in SIX rows over THREE fixtures, and the third fixture is the one
#   that makes the other two mean something: a CAST of a PARAM satisfies neither of CPython's
#   conditions, so CPython hands the NODE back -- a THIRD answer, neither a value nor an absence.
#
#   IT DOES NOT NEED `simplify`, which is the finding rather than a convenience. `simplify` is a
#   documented wall in this file (`ops.py:511`, "* uop evaluation *") and 3,679 lines of
#   partial symbolic work sit behind it, so anything that truly required a rewriter would be
#   stuck on the largest subsystem here. But a CONST is already reduced, so `simplify` is the
#   IDENTITY on it, and the CAST arm's test is a SHAPE test on the node rather than a rewrite.
#   What is left out is `ret.dtype.const(...)` -- the dtype round trip -- and `wk_dt` already
#   answers a node's dtype, so the value half is the whole of the discriminating claim.
#   Planted: a reader that answers `none` for everything fails `ss_const_val` and
#   `ss_cast_const_val` and nothing else.
# done(p3) ops.py:521 def _eval -- and it was misfiled here, which is the finding. `_eval` needs
#   the node's dtype AND its two bounds, and this file imports only `Base`, `helpers` and
#   `LAWS/spec`, while `UOp.vmin`/`vmax` are in `fold.bend` and the node-level dtype reader is in
#   `weak.bend` -- and BOTH of those import `ops.bend`. So the def sits DOWNSTREAM of the file
#   that wanted it: an import edge, not a language limit, and the same relocation
#   `wk_commit_dtype` already got. It is now `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` in
#   `weak.bend`, gated at `gates/wk-eval-gate.py`: 16 rows, 3 lanes, 15 identical to CPython and
#   ONE documented divergence.
# TODO(p3) ops.py:511  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
#   `bool_on_i32`).
# TODO(p3) ops.py:512  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
#   `int_on_range`).
# TODO(p3) ops.py:513  def __float__  -- DONE, same gate (`float_weakfloat`,
#   `float_on_i32`).
# TODO(p3) ops.py:514  def substitute
# TODO(p3) ops.py:521  def __index__
#   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking
# TODO(p3) ops.py:526  def trace_num
# WALL(p3) ops.py:563  def __getitem__ -- BLOCKED. PYTHON'S SLICE PROTOCOL. The body calls `super(UOp, self).__getitem__(idx)`,
#   `argfix`, `_normalize_indices`, `slice` objects and `self.shape[i]`. A slice is a Python
#   runtime object with `start`/`stop`, and Bend has no slicing syntax to normalise.
# done(p3) ops.py:597 def _uop -- and the honest answer is that there is nothing to
#   WRITE. CPython's is `def _uop(self) -> UOp: return self`, which is the IDENTITY, and
#   it is the identity because `Tensor` SUBCLASSES `UOp`. This port's
#   `type Tensor is Data: Tensor{ar, uop, is_param, grad}` (`tensor.bend:186`) is a RECORD
#   WRAPPING a U32 index, so it is not a UOp -- and the port's node reference is already a
#   `Found`, which IS the UOp reference. There is no unwrap on this side to perform.
#   the tensor side of the same name is ported and gated elsewhere: `tensor.bend:192-195`
#   names `Tensor.u` as `_uop -- tensor.py:118` and every graph-building method there
#   reads that field in place of `self.uop`. So the NAME is done, from the side that has
#   something to do.
# done(p3) ops.py:599 def _wrap_uop -- same reason, and it is the stronger one.
#   CPython's is `@classmethod def _wrap_uop(cls, u: UOp) -> UOp: return u`, so it returns
#   its argument UNCHANGED. It exists at all because `Tensor` subclasses `UOp`: without the
#   subclassing, a `UOp` passed where a `Tensor` is expected would not be one, and this
#   would have to convert rather than hand back. The port has no such gap -- `Tensor` is a
#   record wrapping a `U32` and a `Found` is a `U32` plus an arena -- so there is no
#   coercion to bridge and no def to write. a marker that asks for a function which is
#   CORRECTLY ABSENT IS A WALL, NOT A GAP, and the reason it was a marker at all is that
#   nobody had written down WHICH kind it was.
# TODO(p3) ops.py:581  def const_like
# TODO(p3) ops.py:587  def ufix
# TODO(p3) ops.py:594  def store
# TODO(p3) ops.py:603  def ins
# TODO(p3) ops.py:604  def contract
#   # cast, except for CONST, in which case rebuild a new CONST at the dtype
# TODO(p3) ops.py:621  def cconst
#   ops.py:610 -- a FORCED CAST is needed for bool because the ordinary cast
#   folds at bool, so `UOp.const` cannot state that width.
# TODO(p3) ops.py:630  def wmma
#   ops.py:622 -- the input dtype lives in the arg, not in `src[0].dtype`,
#   because a BITCAST rewrite changes the src dtype.
# PORTED -- `ops.py:652 _rop` is `tensor.bend`'s `tn_rop`, which is
# `tensor.bend:1822` symbol=tn_rop.
# TODO(p3) ops.py:644  def invalid
# DONE(p3) ops.py:664 def valid -- `UOp.where` and `UOp.valid_of` above, gated at
#   `gates/ops-core-gate.py` in FOUR rows. `where` is `mixin/elementwise.py:426`'s
#   `self.alu(Ops.WHERE, x, y)`, i.e. `UOp(Ops.WHERE, src=(cond, x, y))`, and it is the constructor
#   `UOp.valid_of` is one line on top of.
#
#   defs, could not read their own src fields back, and reverted them as "an unverifiable
#   constructor". The truth is the arena rule this project already records: each `UOp.const` grows
#   the arena and answers a node in the GROWN one, so reading an index against the original `ar0`
#   finds a different node -- I read `ANone{}` out of three srcs that were there all along. MEASURED
#   with a probe: threaded wrongly, all three read `ANone{}`; threaded right,
#   `cbool:True|cbool:True|cinvalid`.
#
#   so the rule for this whole file is narrower than i wrote it last time. Three defs moved
#   downstream because `ops.bend` cannot name `fold.bend`'s bounds or import `dtype.bend`. THIS one
#   needed neither: it was a bug in the CALLER's arena discipline, and the def was always writable
#   here. "Cannot read it back" is not evidence that it cannot be written.
#   PLANTED: swapping the two trailing srcs fails `valid_src1` and `valid_src2` together.
# TODO(p3) ops.py:646  def get_idx
# TODO(p3) ops.py:652  def reduce
# TODO(p3) ops.py:661  def overflows
#   `def overflows(self, dtype: DType) -> bool: return self.vmin < dtype.min or
#   dtype.max < self.vmax`. Two comparisons and no minting, which is why it looks
#   like the cheapest def on this list. It is not, and the reason is a QUESTION
#   rather than a wall:
#
#   CPython's `vmin`/`vmax` are concrete ints. This port's are
#   `Maybe<&2, Bnd>` (`uop/fold.bend`:4498), and `Bnd` is
#   `Bnd{inf} | BndInt{neg, mag} | BndFlt{v}` -- an INTEGER OR A FLOAT OR AN
#   INFINITY, symbolically. So `vmin < dtype.min` is not one comparison, it is a
#   comparison over that union, and the honest answer to "is `vmin` below the dtype
#   minimum" when `vmin` is SYMBOLIC is neither True nor False: it may be undecidable
#   until the range table resolves it.
#
#   `Bool` has no third value, and defaulting unknown to False makes the port assert
#   a range is SAFE when it has not been shown to be. That is the one failure mode a
#   dtype fold must not have, and it is why this is not ported as a one-liner with
#   `Bool.or(lt(...), lt(...))`.
#
#   The shape it needs: a THREE-valued predicate over `Bnd` (below / provably not
#   below / unresolved), and a decision about what the two-valued public answer does
#   with the third -- almost certainly "not overflowing is a MAYBE, and every caller
#   that needs certainty has to say so".
#
#   `bnd.lt` DOES exist -- `fold.bend:3266`, with `bnd.eq` at `:3317` -- and an
#   narrower and stranger than "add an ordering": `bnd.lt` is a TWO-valued TOTAL
#   answer over `BndInt`, and what is missing is the third.
#
#   AND `dt_max` IS NOT A SUBSTITUTE FOR IT. `dtype.bend`'s `dt_max` answers
#   `int64.max` for `uint64` -- the `i64_max_u` fallthrough, `dtype.bend:366-375` --
#   which is documented as safe only because that bound is read as `hi <= max`.
#   `uint64.max` is `2**64-1` and `int64.max` is `2**63-1`, so borrowing the table
#   here would make every `uint64` bound wrong by a factor of two. This needs `Bnd`.
#   P3, with `vmin`/`vmax`.
# WALL(p3) ops.py:670  def unshard -- BLOCKED. `def _shard` IS ABSENT -- checked as a definition, comments excluded. `unshard` builds a
#   UNSHARD and `_shard` is the constructor it shares with `shard` below.
#   ops.py:663-665 -- an UNSHARD carries one sharding RANGE per sharded axis;
#   the range need not be DEVICE, so a LOCAL range may shard a tile.
#   # * multi-device helpers *
# WALL(p3) ops.py:690  def bounds -- BLOCKED. `def max_numel` IS ABSENT, and `bounds` also reads `self.axis` and a device COUNT
#   (`len(self.device)`, on the `Dev` tag). It is a `itertools.accumulate` + `pairwise`
#   over per-axis shapes.
# TODO(p3) ops.py:715  def axis
# TODO(p3) ops.py:728  def _shard
# WALL(p3) ops.py:734  def shard -- BLOCKED. `def _shard` IS ABSENT -- the same one `unshard` needs. `copy_to_device` IS present, so
#   this is one missing constructor rather than a missing subsystem.
#   `def param_like` IS ABSENT, and `store_call`'s body is two of them:
# TODO(p3) ops.py:746  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.
#   a device is a `U32` tag here, not a string: `type Dev is Data: D1{tag: U32}`. So a device name has no prefix to test, and the two below are exactly a `startswith`:
# TODO(p3) ops.py:755  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
# TODO(p3) ops.py:756  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
#   # little helpers
# PORTED -- `ops.py:818 _mop` is `tensor.bend`'s `tn_mop`, which is
# `tensor.bend:1685` symbol=tn_mop.
# TODO(p3) ops.py:835  def new_buffer
# TODO(p3) ops.py:843  def from_buffer
#   ops.py:821 -- both the storage identity and the dtype interpretation are
#   part of the UOp key; a buffer reused under another dtype is another node.
#   `def canonicalize_device` and `def is_disk_device` ARE BOTH ABSENT, and both start with one:
# TODO(p3) ops.py:849  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
# TODO(p3) ops.py:867  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.
# TODO(p3) ops.py:855  def _frompy
# DONE(p3) ops.py:902 def is_virtual -- `wk_is_virtual` in `weak.bend`, `no_dev` beside it.
#   `device is None or dtype in weaks`, and the device half needs a node that CARRIES a `Dev`:
#   `fold.bend`'s `mw_pa` hard-codes `ParamArg`'s device field to `None{}`.
#   the claim that no DEF in the port sets it was FALSE. measured 2026-10-30:
#   `renderer/__init__.bend:441` builds a `ParamArg` with `device = Some{S.D1{0}}`, and
#   `fold.bend`'s `device_of.param` reads `O.ParamArg.device(pa)`, so a node that CARRIES a
#   device was reachable all along. The rows are `gates/wk-isvirt-gate.py` -- 5 rows, 3 lanes,
#   0 divergences, and three mutations that each move the row they name.
# TODO(p3) ops.py:931  def contiguous_view
#   `def contiguous_view` IS ABSENT, and both of these ask it first:
# TODO(p3) ops.py:941  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
# TODO(p3) ops.py:957  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.
# wall(p3) -- storage, device and alloc. no live `Buffer` -- there is no `type Buffer is Data` anywhere in the port and zero `Buffer{` constructors. tinygrad's Buffer is an allocated object with a `realized` field and a `memory`
# TODO(p3) ops.py:950  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
# TODO(p3) ops.py:988  def realized  -- BLOCKED, and ANSWERS a Buffer.
# TODO(p3) ops.py:999  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
# TODO(p3) ops.py:757  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.
# TODO(p3) ops.py:974  def buffer
# PORTED -- `ops.py:1015 UOp.variable` is `UOp.variable` (this file), four `vrn_*`
# rows byte-identical to CPython on all three lanes via
# `sh .agents/slop/ops-vrn-gate.sh`, with six mutations in
# `.agents/slop/ops-vrn-mutate.py` each moving EXACTLY the rows it names.
#
# IT WAS BLOCKED ON A NAME, NOT ON A SUBSTRATE. CPython writes `slot=-1` and this
# file's `ParamArg.slot` is a `U32`, so the def needed a name for "no POSITIONAL
# slot" and the file that OWNS the field had none -- while `function.bend`,
# `codegen/kernel.bend`, `codegen/late/linearizer.bend` and `uop/symbolic.bend` had
# each invented one. `ParamArg.no_slot()` (this file) is the single name, landed the
# commit before, and this def is the first thing it unblocked.
#
# `is_variable` (ops.py:1020) is STILL BLOCKED and this does not change that: its
# fifth conjunct is `self._shape == ()` and `Node{op, src, arg, tag}` has no shape
# field. The `vrn_*` rows print `nsrc` as the closest honest proxy and the `is_
# variable` marker says why that is not the same question.
#   ops.py:1020  def is_variable
#     `self.op is Ops.PARAM and isinstance(self.arg, ParamArg) and self.arg.vmin_vmax
#     is not None and self.arg.addrspace is AddrSpace.ALU and self._shape == ()`.
#     FOUR of the five conjuncts are functions of `Node{op, src, arg, tag}`. The
#     fifth is not, and that is the whole of the wall: this arena's Node has NO
#     SHAPE FIELD. `Arena{nodes, shp}`'s `shp` is the arena's own table, not a
#     per-node shape, so `self._shape` has nowhere to be read from.
#
#     A four-of-five port is not a partial port, it is a WRONG ANSWER: it returns
#     True for a PARAM with a src, which is not a scalar, which upstream says is
#     not a Variable. Every caller of `is_bound_var`, `unbound` and `bind` would
#     then take the Variable path on a non-Variable. So the four readable
#     conjuncts are NOT landed, and `expr` -- the one def of the lattice whose
#     answer is a function of the ARG ALONE -- is landed instead.
#
#     Unblocking it is a substrate change, not a port: `Node` needs a shape, or an
#     accessor that derives one. P3, with the shape work `uop/fold.bend` already
#     owns for the fold.
#   ops.py:1025  def is_bound_var
#     `self.is_variable and self.arg.val is not None`. The second conjunct is two
#     fields of a `ParamArg` and both are readable; the first is `is_variable`
#     above. Gated on it, not on anything of its own.
#   ops.py:1032  def bind
#     `assert self.is_variable and not self.is_bound_var; uval = UOp.const(val) ...
#     return self.replace(arg=replace(self.arg, val=uval.val))`. THREE dependencies
#     and none of them is this def: `is_variable` (the shape wall), `self.vmin <=
#     uval.vmin and uval.vmax <= self.vmax` (`uop/fold.bend`'s `vmin`/`vmax` over
#     the range table) and `uval.divides(self.arg.multiple_of)` (ops.py:1069, not
#     ported). `self.replace` is `UOp.new` and needs no port -- the arena IS the
#     intern table -- which is the one part of this def that is ready.
#   ops.py:1039  def unbound
#     `assert self.is_variable; return self.replace(arg=replace(self.arg, val=None),
#     tag=None)`. The REWRITE is two field writes, both readable, and `replace` is
#     `UOp.new`, so the def itself is nearly free. It is gated on the assert only,
#     and the assert is `is_variable`: without that conjunct the def would clear
#     `val` on nodes upstream refuses to touch, and a gate that cannot see the
#     difference is not a gate.
#   ops.py:1043  def unbind
#     `assert self.is_bound_var; return self.unbound(), self.arg.val`. Both halves
#     are the two defs above, including the assert.
#   ops.py:1046  def unbind_all
#     `{x: x.unbound() for x in self.backward_slice_with_self if x.is_bound_var}` and
#     then `self.substitute(bound, walk=True)`. The slice and the dict build are
#     `bsl.go`'s shape and readable; `substitute` (ops.py:514 symbol=UOp.substitute) is not ported, and
#     the dict is keyed by a `UOp` in Python, which in this arena means keyed by an
#     INDEX whose validity is a session property. P3, with `substitute`.
#   ops.py:1049  def variables
#     Walks the backward slice collecting `x.unbound() if x.is_variable else x` and
#     an `_device_num` Variable per DEVICE RANGE, then `sorted(ret, key=lambda v:
#     (v.arg.name or "", v.arg.slot))`. The sort key is `(Maybe<String>, U32)` and
#     the `or ""` is Python's `None`-sorts-first, which this port has to state
#     rather than inherit. Gated on `is_variable` and on the shape wall.
# * uop symbolic stuff *
# AND `const_factor` IS DONE -- MEASURED 2026-11-08: `def UOp.const_factor(fuel, ar, i) ->
# H.I64` IS AT `:7752` AND `def UOp.divides(fuel, ar, v, i) -> Dv` IS AT `:7972`. THE `TODO`
# that used to stand here was stale against a `DONE` NOTE eleven lines below it, and a `TODO`
# beside a `DONE` for the same DEF is a ledger that disagrees with itself.
# DONE(p3) ops.py:1048 def const_factor -- `UOp.const_factor` above, FLATTENED: the def and
#   its fold are not mutually recursive once the arms are read (a STACK/ADD contributes the
#   gcd identity and every other node is a leaf), so `cf.walk` is a FUEL-bounded worklist.
#   The "Bend cannot express that" probe below was measuring the OBVIOUS spelling.
# DONE(p3) ops.py:1082 def pop_const -- `UOp.pop_const_val` / `UOp.pop_const_hits` above, with
#   `cval_arg`. Gated at `gates/ops-core-gate.py` in EIGHT rows over FOUR fixtures, and the
#   fixtures are built so the def's TWO conditions fail SEPARATELY: a second src that is not a
#   CONST, and a `MUL` popped as an `ADD`. Planted -- dropping the `op` comparison from
#   `pop_const_hits` fails exactly `pop_mul_const_hits` and nothing else, which is what says the
#   op is COMPARED rather than assumed. The value is a `Const` and not an `H.I64`: an I64-only
#   reader recorded a divergence on the float fixture that was really just a narrow type, and
#   `pop_const` returns whatever the CONST carries.
# TODO(p3) ops.py:1073  def gcd
# TODO(p3) ops.py:1079  def divide_exact
# TODO(p3) ops.py:1090  def vmin
# TODO(p3) ops.py:1092  def vmax
# TODO(p3) ops.py:1106  def _min_max
# TODO(p3) ops.py:1168  def _sym_fxn
# TODO(p3) ops.py:1169  def sym_infer
# TODO(p3) ops.py:1173  def render
# TODO(p3) ops.py:1181  def render_uir  -- upstream's `pyrender` was DELETED before this pin.
#   `def view_as` IS ABSENT, and the alloc family ends in one:
# TODO(p3) ops.py:1188  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
# TODO(p3) ops.py:1194  def alloc_like  -- BLOCKED, and delegates to `alloc`.
# TODO(p3) ops.py:1206  def placeholder  -- BLOCKED, and ends `view_as`.
# TODO(p3) ops.py:1208  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.
# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). The def, its fixture,
# its four rows and its gate landed inside a CONCURRENT agent's commit rather than
# one of mine, so the history does not attribute them; the write-up is here and at
# the gate, which is where a reader lands anyway. Four `set_*` rows
# byte-identical to CPython on all three lanes via `sh .agents/slop/ops-set-gate.sh`,
# with TWO negative controls that are the two bugs below.
#
#   # set is store+end+after
#   def set(self:UOp, val:UOp|ConstType, end:UOp|tuple[UOp, ...]|list[UOp]=()) -> UOp:
#     return self.src[0].after(self.store(val).end(*argfix(end)))
#
# Upstream's own comment says the whole of it, so the def has no logic: it is a
# COMPOSITION, and the only things a row can test are that the three pieces are
# wired in this ORDER and that `argfix`'s empty arm is honoured. The number of
# `end` operands is the only input that varies, so it is the only thing the family
# varies. `argfix` is already ported as `argfix1`/`argfix2`/`argfix_seq`
# (helpers.bend:536-543), so `end` is a `Maybe<&2, List<&2, U32>>` and not a node.
#
# TWO BUGS, AND BOTH COMPILED.
#
#   THE STALE ARENA. The first draft was
#       +e = UOp.end(ar, Found.i(s), ...)          -- `ar`, the CALLER's
#   and `UOp.store` MINTS, so `s` lives in a GROWN arena and `Found.i(s)` read out
#   of `ar` indexes the wrong arena. It typechecked and answered
#   `Ops.AFTER(Ops.BUFFER Ops.AFTER)` where CPython answers
#   `Ops.AFTER(Ops.BUFFER Ops.STORE)`. That is the failure mode bend2-constraints
#   names, and `UOp.copy_to_device` above is the fix in one line: thread the
#   previous step's `Found.ar`. The first negative control reintroduces it.
#
#   THE SUBJECT IS A STORE. The first fixture was a BUFFER and CPython raised
#   `IndexError: tuple index out of range`, because `set` is called ON a store and
#   `src[0]` is the store's target. A fixture that does not reach the code is a
#   fixture that cannot fail, and this one looked like a red gate.
#
# and a printer that was three drafts worse than it needed to be: a recursive
# `deep` needing a closer that knows its own depth, a `Bool.pick` for the first
# separator, and a fold that opened a paren in the accumulator. The file already
# had the shape under another name (`Rng.srcops.go`'s `+first` flag). Grep for
# the IDIOM before writing the INSTANCE.
#   # set is store+end+after
# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `THE PORT's `uop/ops.bend` HEADER` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. the rule is not "those three were misfiled" but "a DEF needing a dtype predicate or a
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   the other two arms are not ported and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and `view_as` IS ABSENT FROM THE PORT
#   (so is `unique_num`). Checked, not assumed.
# TODO(p3) ops.py:1228  def param_like
# TODO(p3) ops.py:1236  def view_as
# custom_function -- ops.py:1258 upstream. `UOp(Ops.CUSTOM_FUNCTION, src=src,
# arg=CustomFunction(name, dtype))`. The pin's spelling was ops.py:1256 and took no
# dtype, because there was no `CustomFunction` to hold one.
# `dtype=dtypes.void` is upstream's DEFAULT and Bend has no default argument, so `dt`
# is required here and `CustomFunction.of(name)` builds the void-dtype value.
# `UOp.call` below is NOT PORTED, so nothing in this file consumes the dtype yet:
# `dtype_from_uop` is not ported either (the folds do not fit, see the header).
