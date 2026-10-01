# mixin/reduce.bend -- tinygrad/mixin/reduce.py, ALL 138 LINES.
#
# ===========================================================================
# THE DEF MAP. Every def in `mixin/reduce.py`, and WHERE IT LIVES. Six of the
# seven are ALREADY PORTED and three of those six are IN OP.BEND, which is why
# this file does not re-declare them: duplicating a def that exists is the one
# failure mode that makes this unit a net negative.
#
#   reduce.py  def                     line    lives in
#   ---------  -----------------------  ------  ------------------------------
#   `_rop`     _rop                      10-11  HERE, `rc_rop`. The abstract
#                                                  `raise NotImplementedError`;
#                                                  the CONCRETE one is
#                                                  `T.tn_rop` (tensor.bend),
#                                                  which ports ops.py:655-665.
#   `_reduce`  _reduce                   13-18  op.bend `M.mo_reduce` (:794)
#                                                  + `mo_axis0`/`mo_ax`/`mo_ax_all`
#                                                  /`mo_keep_ds`/`mo_reduce.keep`
#   `sum`      sum (dtype=None arm)      20-45  op.bend `M.mo_sum` (:810)
#   `sum`      sum (dtype GIVEN arm)     44-45  HERE, `rc_sum_dt`
#   `prod`     prod (dtype=None arm)     47-71  op.bend `M.mo_prod` (:818)
#   `prod`     prod (dtype GIVEN arm)     71     HERE, `rc_prod_dt`
#   `max`      max                       73-94  op.bend `M.mo_max` (:823)
#   `any`      any                       96-116 HERE, `rc_any`
#   `all`      all                      118-138 HERE, `rc_all`
#
# AND THE ONE ARM OF `reduce.py:15` THAT op.bend DOES NOT HAVE: `axis` is
# `int | Sequence[int] | None`. op.bend's `mo_ax` (:752) builds a ONE-element
# list from a single `U32`, which is the `int` arm and the `None` arm
# (`mo_ax_all`, :756); a `Sequence[int]` is a LIST of axes, each through
# `_resolve_dim`, and that fold is HERE as `rc_axs`.
#
# ---------------------------------------------------------------------------
# WHICH OF op.bend's DEFS ARE CANDIDATES TO MOVE HERE. In this order.
#
#   MOVE 1 (cleanest). `mo_reduce` (:794) and its seven helpers -- `mo_axis0`
#     :745, `mo_ax` :752, `mo_ax_all` :756, `mo_iaxis.go` :764, `mo_iaxis` :769,
#     `mo_keep_one` :771, `mo_keep_ds.go` :774, `mo_keep_ds` :780,
#     `mo_reduce.keep` :789. Every one of those lines is a `reduce.py` line
#     (:13-18, :15, :18). They are reduce.py's dispatch and they are HERE, and
#     `mo_reduce` is the one def `rc_any`/`rc_all`/`rc_sum_dt`/`rc_prod_dt`
#     reach THROUGH `M.mo_max`/`M.mo_prod`. Moving them costs op.bend four call
#     sites (`mo_min` :1121, `mo_mean` :887, `mo_logsumexp` :1040, and `mo_sum`
#     :810 itself) and gains nothing except that reduce.py's lines live in
#     reduce.py's file. NOT DONE: it is a refactor of a green file for a
#     cosmetic gain, and op.bend is read-only to this unit.
#
#   MOVE 2 (contested). `mo_sum` :810, `mo_prod` :818, `mo_max` :823. Same
#     argument, but these three are load-BEARING inside op.bend -- `min` (:473)
#     is `-self.reduce(MAX)` spelled through `mo_max` and `mo_min` is the outer
#     `_inverse` pair -- so a move is a signature change on op.bend's hot path
#     rather than a rename.
#
#   STAYS IN op.bend. `mo_sum_acc` (:429), `mo_commit_dt` (:411),
#     `mo_downcast` (:433), `mo_cast_t` (:370), `mo_resolve` (:718). These are
#     `dtype.py:220`/`dtype.py:16`/`reduce.py:45`/`dtype.py:36`/`movement.py:81`
#     -- NOT reduce.py lines, so moving them here would be worse than leaving
#     them, because a def belongs in the file of the Python it ports.
#
#   STAYS IN tensor.bend. `T.tn_rop` (:867) and its twelve helpers are
#     `ops.py:655-665` (`UOp._rop`), which `tensor.bend` hoisted with the same
#     precedent (`_mop`, ops.py:821). `reduce.py:10` is the ABSTRACT `_rop`.
#
# ---------------------------------------------------------------------------
# THE FOUR THINGS THIS FILE ADDS, and each is a `reduce.py` line with no home.
#
#   1. `rc_any` / `rc_all` (reduce.py:116/:138). `self.bool().max(axis,
#      keepdim)` and `self.bool().prod(axis, keepdim)`. Two lines each in Python
#      and NOBODY had ported them: `mixin/op.py` never calls them, so no other
#      unit reached them by accident. `bool()` is `dtype.py:124`, `cast(dtypes.bool)`
#      -- one line, and `M.mo_cast_t` IS it (`wk_cast_at` under it).
#   2. `rc_sum_dt` / `rc_prod_dt` (reduce.py:44/:71, the `dtype is not None`
#      arm). `M.mo_sum`/`M.mo_prod` hard-code `dtype is None` -- op.bend's own
#      header says so ("`dtype` is always `None` from this range") -- so the
#      explicit-dtype arm of two of reduce.py's three numeric methods was
#      unported. It is not the same def with a different argument: with `dtype`
#      given, `sum` does NOT cast back to `self.dtype` (the `dtype is None and`
#      conjunct on reduce.py:45 fails), and that is a graph difference, not a
#      cosmetic one.
#   3. `rc_axs` (reduce.py:15, the `Sequence[int]` arm).
#   4. the gate.
#
# ---------------------------------------------------------------------------
# THE ARENA, and it is the whole reason `rc_any` is TWO defs and not one.
# `self.bool()` MINTS (a CAST) unless the dtype already agrees, and the `max`
# after it must build in the arena the CAST grew. `M.mo_cast_t` returns the
# GROWN pair and `M.mo_max` re-folds off the tensor it was handed, so the two
# calls compose -- MEASURED: `any0` is `3 BUFFER/0 CAST/1 REDUCE/1` against
# CPython's `3 BUFFER/0 CAST/1 REDUCE/1`, and the node COUNT is the check that
# the CAST landed in the arena the REDUCE reads.
#
# ---------------------------------------------------------------------------
# THE GATE. `main` prints one row per claim, in `reduce.py`'s order.
#
# ROW FORMAT, and it is `mo_shape`'s (op.bend:1395) with the REDUCE's own
# identity added, because a reduce over the WRONG AXIS has the right node count
# and the wrong answer:
#
#   <name>=<shape> <dtype> root=<OP>/<nsrc> red=<ROP>/<num_axes>| <n> <sig>
#
#   shape       `F.fold.shape` rendered `(2)(3)`, so `RESHAPE(REDUCE,CONST(4))`
#               and `RESHAPE(REDUCE,CONST(1))` are distinguishable -- they are
#               the SAME signature and a wrong keepdim shape is invisible to
#               every other column.
#   dtype       `F.fold.dt` rendered. The bool/int arm of `any`/`all` is where
#               this bites: `any` on a bool source is 2 nodes and on an int
#               source is 3, and the dtype column is what says which.
#   root        the ROOT's op and src count. This is the "collapse to the input"
#               detector: an identity reduce answers the SOURCE's op.
#   red         the REDUCE node's `AReduce{rop, num_axes}` -- the reduce's OWN
#               identity, read out of the arena, NOT out of this file. `num_axes`
#               is the axis count, so `sum(axis=(0,1))` and `sum(axis=0)` are
#               separated by a number no node count separates, and `red=none`
#               means the graph holds no REDUCE AT ALL, which is the honest
#               answer for the four collapse rows.
#   sig         `mo_sig`'s toposort with each node's op and src COUNT.
#
# reduce.py has NO argmin/argmax -- those are `mixin/op.py:863`/`:890` and they
# are not this file -- so the "does the result carry an index" column has no row
# here. `red=` is the same claim for a VALUE reduce and it is strictly stronger
# than a dtype test: it reads the op the REDUCE will actually run.
#
# NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph, so no
# device is needed and CPython is the oracle. The oracle is at
# $TMP/mixin-reduce-gate.py and it is DERIVED FROM CPython, never restated from
# this file -- a row restated from the port agrees with a wrong port.
#
#     .venv/bin/python $TMP/mixin-reduce-gate.py   > /tmp/py.txt
#     ./bin/bend tinybendygrad/mixin/reduce.bend    > /tmp/bd.txt
#     ./bin/bend tinybendygrad/mixin/reduce.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
#     diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt
#
# ---------------------------------------------------------------------------
# TWO MEASURED DEFECTS IN THE SUBSTRATE, REPORTED NOT FIXED. FOUR of this file's
# THIRTY-TWO rows are RED and every one of them is one of these two.
#
# --- DEFECT 1, `tensor.bend`'s `T.tn_rop`, THREE ROWS: `max_ax0_14`,
# --- `any_ax0_14`, `all_ax0_14`.
#
#   `T.tn_rop` (tensor.bend:867) ports `UOp._rop` (ops.py:655-665), and
#   ops.py:657-660 says:
#
#     reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1))
#     if not len(reduce_axis):
#       return self.reshape(tuple(s for i,s in enumerate(self.shape) if i not in axis))
#
#   So a reduce over a SIZE-ONE axis builds NO REDUCE and answers a RESHAPE to
#   `kept`. `tn_rop.ne1` (:821) filters correctly -- it DROPS the size-one axis
#   and hands `Nil{}` back -- but `tn_rop` (:867) routes on `tn_rop.len(axis)`,
#   the length of the axis list BEFORE the filter, so the `case 0n:` arm (:863,
#   which returns `self`) is unreachable on this shape. The REDUCE is therefore
#   built with `num_axes = 0` and the `kept` reshape is never built at all.
#
#   MEASURED, on `Tensor([1.,2.,3.,4.]).reshape(1,4).max(axis=0)`:
#
#     CPython   (4)   float root=RESHAPE/2 red=none   6 BUFFER CONST CONST STACK/2 RESHAPE/2 RESHAPE/2
#     the port  (1)(4) float root=REDUCE/1 red=MAX/0  6 BUFFER CONST CONST STACK/2 RESHAPE/2 REDUCE/1
#
#   **THE SAME NODE COUNT.** 6 against 6, the same srcop sequence, the same root
#   arity, and a wrong shape AND a wrong root op. This is the sharpest instance of
#   "the gate is shape + op, not a count" in the port so far: a count row prints
#   6 on both sides and calls it green.
#
#   The fix is one `Bool` and it is NOT in this file: `tn_rop` should route on the
#   FILTERED list's length rather than `tn_rop.len(axis)`, and then the existing
#   `case 0n:` arm answers `self.reshape(kept)` instead of `self`. `kept` is
#   `mo_keep_ds` (op.bend:780) with the axis EMPTY, which is the source's own dims.
#
# --- DEFECT 2, `op.bend`'s `mo_resolve`, ONE ROW: `sum_axs_neg`.
#
#   `mo_resolve` (op.bend:718) is `_resolve_dim` (movement.py:81),
#   `return dim + total if dim < 0 else dim`, and its own comment says "`neg` is
#   the sign and `dim` the magnitude, so there is no I64 to unpack". It then
#   computes `Bool.pick(U32, neg, U32.add(dim, total), dim)` -- which is
#   `|dim| + total`, and Python's answer is `dim_signed + total`, i.e.
#   `total - |dim|`. It is wrong for EVERY negative dim, and `op.bend`'s entire
#   gate passes `False{}`, so the negative arm has never been exercised. That is
#   the recorded "a gate that never calls the function under repair is blind"
#   note, re-measured on a function rather than a rule.
#
#   MEASURED: on a rank-1 source `mo_resolve(True, 1, 1)` answers `2` where
#   CPython's `sum(axis=-1)` resolves `-1 + 1 = 0`. The out-of-range axis is then
#   filtered as "shape is 1" by `tn_rop.ne1`, the reduce collapses, and the row
#   prints `red=ADD/0`.
#
#   The fix is one operator: `U32.sub(total, dim)` on the negative arm. (Or the
#   convention changes to two's complement, which the `+` already does -- but then
#   `neg` is redundant with the sign bit and the comment is wrong, and the two
#   cannot both be right. `U32.sub` is the reading the comment already claims.)
#
# THE ROWS STAY RED. They are the measurement, and closing them with the port's
# own answer would be a row that encodes the bug.
#
# ---------------------------------------------------------------------------
# THE MUTATION TABLE. SEVENTEEN one-token edits, each applied, each run through
# BOTH lanes, each diffed against the unmutated output ROW BY ROW (by the `name=`
# prefix, so a moved row is NAMED and not counted), and reverted from the
# in-memory source:
#
#     .venv/bin/python $TMP/mixin-reduce-mutate.py
#
# THIRTEEN MOVE SOMETHING AND FOUR DO NOT. All four are reported, because a table
# with no row that CANNOT move is a table of coincidences -- and three of the four
# are structural rather than a missing fixture.
#
#   M9  NOTHING. `rc_axs` PREPEND instead of APPEND. **UNFALSIFIABLE, and
#       structurally so, not for want of a fixture.** `sum_axs01` folds `rc_axs`
#       over a LIST OF LENGTH TWO, so the reversal really does happen; and
#       `UOp._rop` opens with `axis = tuple(sorted(axis))` (ops.py:656), which
#       `T.tn_rop.sorted` (tensor.bend:784) implements, so the reversed list is
#       sorted straight back and the two programs are the same function. A gate
#       that could see it would have to read `rc_axs`'s accumulator directly, and
#       that is a mutation of the GATE rather than of the code.
#   M14 NOTHING. `rc_rop` returns `self` instead of calling `T.tn_rop`. This is
#       the honest shape of reduce.py:10: `_rop` is `raise NotImplementedError`,
#       an ABSTRACT DECLARATION, and nothing in reduce.py calls it either -- every
#       caller goes through `_reduce`. So the def is unreachable here for the same
#       reason it is unreachable in Python, and the row that would gate it does not
#       exist in reduce.py to be written. Reported, not patched.
#   M16 NOTHING. The CONTROL: a whitespace-only edit. Nothing moves, and that is
#       the point.
#   M17 NOTHING. `rc_axs` drops the NEGATIVE arm of the resolve. **Blocked by
#       DEFECT 2, and the reason is worth stating exactly.** `sum_axs_neg` is
#       `axis=(-2,)` on a rank-2 source. Correct resolves to `0`; dropping `neg`
#       yields `2`. BOTH are what `mo_resolve` currently produces anyway -- `2` is
#       the buggy answer and `2` is the mutated one -- so the row cannot separate
#       them UNTIL `mo_resolve` is fixed. An earlier version of this row was
#       `axis=(-1,)` on a rank-1 source and had the same defect for the same
#       reason (`2` and `1` are both out of range); the rank-2 form is the one
#       kept because after the fix `0` is in range and `2` is not, so the row
#       becomes separating on the fix rather than needing to be rewritten.
#
# THE THREE SINGLE-ROW MUTATIONS, which is the strongest statement in the table:
#
#   M6  `rc_sum_dt`: ignore the given dtype            -> `sum_dt_i32`  alone
#   M7  `rc_prod_dt`: ignore the given dtype           -> `prod_dt_i32` alone
#   M11 `rc_arg.put`: FIRST-WINS -> LAST-WINS          -> `chain_any`   alone
#
# M11 is the one the table was BUILT for, and it is why `chain_any` exists. Every
# other row in this file holds ONE REDUCE, so first-wins and last-wins are the same
# function on all of them; `chain_any` is `any(axis=0).all(axis=0)` over a 2-D
# source, so the graph holds TWO REDUCEs with DIFFERENT ops and the policy is
# visible. MEASURED: `red=MAX/1` becomes `red=MUL/1` on that row and on no other.
# `sum(axis=0).sum(axis=0)` would NOT have worked -- two ADDs of one axis are
# `ADD/1` and `ADD/1`, and the policy is invisible.
#
# TWO MUTATIONS MOVE THE SAME ROW SET FOR DIFFERENT REASONS, which is the table
# saying out loud that the suite is weaker than the counts suggest. M10 (read
# `AAllred` instead of `AReduce`) and M18 (invert the `ok` guard) each move the
# SAME twenty-two rows and every one of them moves to `red=none` -- M10 because
# `AAllred` never matches a REDUCE's arg, M18 because the inverted guard never
# records anything. Neither is a substitute for the other and neither is evidence
# about `num_axes`; `num_axes` is set by `tensor.bend`, not here, and NO mutation
# IN THIS FILE can move it. `sum_axs01` (`red=ADD/2`) is the only row that varies
# that column, and it was added after the first table run for exactly this reason.
#
# M1 and M2 are the SAME edit applied to two symmetric defs, so they are not
# independent evidence -- they are one mutation measured twice. They moved 6 and 5
# rows, and the difference was a MISSING ROW (`all_ax0_14`) rather than a
# difference in the code; that row was added and the table re-run.
#
# M12 (`shape` column dropped) moves thirteen and M13 (`root` column dropped) moves
# all thirty-two, which is the shape/root split doing its job: `root` is the
# collapse detector and every row carries one, `shape` is only visible where the
# fold's answer differs from `()`.
#
# WHAT IS NOT HERE, and it is a gap in the FIXTURES rather than in the table:
# nothing in this file ever calls `rc_rop`, so `rc_rop` itself is ungated (M14);
# and `rc_axs` is only ever called with NON-NEGATIVE axes except for the one
# `sum_axs_neg` row, so the `Ax.neg` FIELD has exactly one row over it (M17).

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../uop/weak.bend as W
import ./../tensor.bend as T
import ./dtype.bend as D
import ./elementwise.bend as E
import ./op.bend as M

# ===========================================================================
# `rc_axs` -- reduce.py:15, the `Sequence[int]` arm.
#
#   axis = tuple(self._resolve_dim(x) for x in (range(self.ndim) if axis is None
#                                                   else make_tuple(axis, 1)))
#
# `mo_ax` (op.bend:752) is the `make_tuple(axis, 1)` -> `[resolve(axis)]` arm for
# ONE axis; this is the fold over a LIST of them. `make_tuple` on a tuple is the
# tuple, so `axis=(0,)` and `axis=0` are the same list and the same graph, which
# is the `sum_axs0` row.
#
# A DIM IS SIGNED and a `U32` cannot be, so it travels as a pair. That is
# `movement.bend`'s `Marg` shape and `device.bend`'s rule 3, and it is the only
# reason this is a fold and not `List.map`.
# ===========================================================================
type Ax is Data:
  Ax{neg: Bool, dim: U32}

def Ax.neg(a: Ax) -> Bool:
  match a:
    case Ax{neg, dim}: neg

def Ax.dim(a: Ax) -> U32:
  match a:
    case Ax{neg, dim}: dim

# `+td: U32` is the `U32`-is-`Data` half of the `+` rule (rand.bend rule 4 /
# rule 30): `td` is read twice in one arm -- once in `mo_resolve`, once in the
# self-call. It does NOT disturb the decrease check, because `td` is not the
# argument that shrinks; `t` is (bend2-constraints rule 29).
def rc_axs.go(+td: U32, xs: List<&2, Ax>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    # `+a` because `Ax.neg(a)` and `Ax.dim(a)` are two reads in ONE expression --
    # the render.bend `case +h <> t:` spelling, and `Ax` is `Data` so it is free.
    case +a <> t: rc_axs.go(td, t, List.append(&2, U32, acc,
      [M.mo_resolve(Ax.neg(a), Ax.dim(a), td)]))

# `total = self.ndim` is `_resolve_dim`'s `extra=0` total (movement.py:83), so it is
# the SOURCE's rank and not the caller's.
def rc_axs(+t: T.Tensor, xs: List<&2, Ax>) -> List<&2, U32>:
  rc_axs.go(U32.from_nat(M.mo_ndim(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))), xs, Nil{})

# ===========================================================================
# `rc_sum_dt` -- reduce.py:44-45 with `dtype` GIVEN.
#
#   ret = self.cast(sum_acc_dtype(self.commit_dtype()) if dtype is None else dtype)
#            ._reduce(Ops.ADD, axis, keepdim)
#   return ret.cast(self.dtype) if dtype is None and self.dtype in (half,bf16,*fp8s) else ret
#
# With `dtype` given the SECOND conjunct's `dtype is None` FAILS, so there is no
# cast back -- and that is the whole difference from `M.mo_sum`, which is why
# this is a def and not an alias. `sum_dt_i32` is the row: 3 nodes with a CAST,
# against CPython's 3.
# ===========================================================================
def rc_sum_dt(+t: T.Tensor, dt: S.Dt, kd: Bool, +axis: List<&2, U32>) -> T.Tensor:
  M.mo_reduce(kd, M.mo_cast_t(t, dt), O.OpsADD{}, axis)

# `rc_prod_dt` -- reduce.py:71, `self.cast(dtype if dtype is not None else
# self.dtype)._reduce(Ops.MUL, axis, keepdim)`. No second line: `prod` has no
# cast back at any dtype.
def rc_prod_dt(+t: T.Tensor, dt: S.Dt, kd: Bool, +axis: List<&2, U32>) -> T.Tensor:
  M.mo_reduce(kd, M.mo_cast_t(t, dt), O.OpsMUL{}, axis)

# ===========================================================================
# `rc_any` -- reduce.py:116. `return self.bool().max(axis, keepdim)`.
#
# `self.bool()` is `dtype.py:124`, `return self.cast(dtypes.bool)`, one line, and
# `M.mo_cast_t(t, S.boolean())` IS it. `M.mo_max` is `reduce.py:73-94`. So this
# is two substrate calls and nothing of its own -- which is the correct size for
# a Python line that is two calls.
#
# THE ORDER IS PYTHON'S: cast first, then the reduce. Reversed, `any_b` (a bool
# source, where the cast is the identity) would print `2 BUFFER/0 CAST/1
# REDUCE/1` against CPython's `2 BUFFER/0 REDUCE/1` and the elision would be
# gone -- and the row that sees it is `any_b`, not `any0`.
# ===========================================================================
def rc_any(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  M.mo_max(kd, M.mo_cast_t(t, S.boolean()), axis)

# `rc_all` -- reduce.py:138. `return self.bool().prod(axis, keepdim)`. `prod` is
# `Ops.MUL` and NOT `M.mo_sum`'s `sum_acc_dtype` cast -- that is the difference
# between `any`/`all` and it is a node count on a bool source: `prod_b` is 2
# nodes (bool stays bool) where `sum_b` is 3 (bool promotes to int32).
def rc_all(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  M.mo_prod(kd, M.mo_cast_t(t, S.boolean()), axis)

# `_rop` -- reduce.py:10-11. `raise NotImplementedError`: a DECLARATION, not a
# body, and Bend has no `raise`. The concrete one is `UOp._rop` (ops.py:655),
# `T.tn_rop` (tensor.bend:867), and this is the forwarding line so the reader of
# reduce.py finds the name where reduce.py has it.
def rc_rop(+ar: O.Arena, self: U32, op: O.Op, +axis: List<&2, U32>) -> O.Found:
  T.tn_rop(ar, self, op, axis)

# ===========================================================================
# THE GATE. The printers first, because a def may only call defs above it.
# ===========================================================================

# The REDUCE's own identity, out of the arena. `AReduce{rop, num_axes}` is a
# TWO-field record so the pattern names both, and every other `Arg` constructor
# is covered by the catch-all LAST (rules: "an arm after `case _:` is dead code",
# and "a record pattern must name every field").
#
# A `Maybe` CANNOT BE THE ACCUMULATOR (bend2-constraints, "A `Maybe` cannot be a
# fold's accumulator"), and a `Data` record cannot hold a `Maybe` field, so the
# answer travels as `Bool` + two `U32`s. `found=False` means "this graph holds
# no REDUCE", which is the CORRECT answer on the four collapse rows and not a
# default.
# `Op` is `Data` (ops.bend:101), so the op RIDES in the record rather than a
# `U32` tag -- one fewer reader and no round-trip through `Ops.value`, which
# would have been a second place to get the numbering wrong.
type RcRed is Data:
  RcRed{ok: Bool, op: O.Op, n: U32}

def RcRed.ok(r: RcRed) -> Bool:
  match r:
    case RcRed{ok, op, n}: ok

def RcRed.op(r: RcRed) -> O.Op:
  match r:
    case RcRed{ok, op, n}: op

def RcRed.n(r: RcRed) -> U32:
  match r:
    case RcRed{ok, op, n}: n

# THE STEP. `red` is the ACCUMULATOR's own verdict and it is a PARAMETER because
# a `match` may not scrutinise a call (rule 2), and `RcRed` is `Data` so `ok`
# travels beside the value rather than as a `Maybe` (rule 15). `O.Arena.arg` is
# in ARGUMENT position, which is legal, and `AReduce` names both of its fields.
def rc_arg.of(got: Bool, +a: O.Arg, +r: RcRed) -> RcRed:
  match got:
    case True{}: r
    case _: match a:
      case O.AReduce{rop, num_axes}: RcRed{True{}, rop, num_axes}
      case _: r

def rc_arg.put(got: Bool, +r: RcRed, +ar: O.Arena, u: U32) -> RcRed:
  rc_arg.of(got, O.Arena.arg(ar, u), r)

# THE SEARCH. One walk over the toposort, FIRST REDUCE WINS, and the walk is a
# self-call with the LIST first so the decrease check is satisfied by the tail.
# The op test is a Bool ARGUMENT and the arg read is a call ARGUMENT -- neither
# is a scrutinee, so neither needs a def of its own.
def rc_find.go(xs: List<&2, U32>, +ar: O.Arena, +acc: RcRed) -> RcRed:
  match xs:
    case Nil{}: acc
    case u <> t: rc_find.go(t, ar, rc_arg.put(RcRed.ok(acc), acc, ar, u))

def rc_find(+ar: O.Arena, i: U32) -> RcRed:
  rc_find.go(O.UOp.toposort(O.Arena.budget(ar), ar, i), ar, RcRed{False{}, O.OpsNOOP{}, 0})

# THE ROW. `mo_shape`'s shape string (op.bend:1395) and `mo_sig`'s signature
# (op.bend:1143) are REUSED -- they are defs in another file and Bend has no
# privacy -- so this is the three new columns and the assembly.
def rc_red_str(ok: Bool, +r: RcRed) -> String:
  match ok:
    case True{}: String.concat([O.Ops.name.of(RcRed.op(r)), "/", U32.show(RcRed.n(r))])
    case _: "none"

def rc_row(nm: String, +t: T.Tensor) -> IO(Unit):
  +ar = T.Tensor.ar(t)
  +i = T.Tensor.u(t)
  +fx = F.folded(ar)
  +rd = rc_find(ar, i)
  IO.print(String.concat([nm, "=", M.mo_shape.go(M.mo_dims(fx, i), ""), " ",
    E.ew_dtnm(W.wk_dt(fx, i)), " root=",
    String.concat([O.Ops.name.of(O.Arena.op(ar, i)), "/", U32.show(O.Arena.nsrc(ar, i))]),
    " red=", rc_red_str(RcRed.ok(rd), rd), "| ", M.mo_sig.of(ar, i)]))

def rc_row_b(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# --- the fixtures. `Tensor([1.,2.,3.,4.], device='PYTHON')` is ONE BUFFER, so
# op.bend's `mo_fx1d`/`mo_i1d`/`mo_buf4` ARE the fixtures and are reused rather
# than rebuilt. `lit1d`/`liti1d`/`litb1d`/`litf2d` are ROWS because a fixture
# that built the wrong dtype would silently change every row below it -- and the
# bool one is the fixture `any`/`all`'s elision is measured against.
def rc_b1d() -> T.Tensor:
  +b = M.mo_buf4(O.Arena.empty(), S.boolean())
  T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))

# THE 0-d SOURCE. `Tensor(7.0)` is `1 CONST/0` with dtype `weakfloat`, and it is
# the fixture for `reduce.py:16`'s `if self.ndim == 0: axis = ()` -- which
# `M.mo_axis0` (op.bend:745) answers by emptying the list. Every 0-d row is
# `2 CONST/0 CAST/1` with NO REDUCE, and that is the identity: `_rop`'s
# `reduce_axis` is empty so it returns the cast source unchanged.
def rc_z0() -> T.Tensor:
  +x = M.mo_fx1d()
  # A CONST IS A TENSOR in this port: `mo_const_t` returns one and its `.u` IS
  # the node index. `T.tn_new(ar, i)` would be the same value spelled as a pair.
  +c = M.mo_const_t(x, O.CFloat{7.0})
  c

# A SIZE-ONE SOURCE. `Tensor([1.,2.,3.,4.]).reshape(1,4)`, which is the fixture
# for the reduce over a NON-REDUCE axis: `ops.py:657`'s `resolve(self.shape[x]
# != 1)` empties `reduce_axis`, so `_rop` returns `self.reshape(kept)` and NO
# REDUCE is built. `red=none` is the row's whole claim.
def rc_14() -> T.Tensor:
  +x = M.mo_fx1d()
  +r = T.tn_mop(T.Tensor.ar(x), T.Tensor.u(x), O.OpsRESHAPE{}, T.ADims{[M.mo_ki(1), M.mo_ki(4)]})
  T.tn_new(O.Found.ar(r), O.Found.i(r))

# --- 1-4: the fixtures, as rows.
def t_lit1d() -> IO(Unit): rc_row("lit1d", M.mo_fx1d())
def t_liti1d() -> IO(Unit): rc_row("liti1d", M.mo_i1d())
def t_litb1d() -> IO(Unit): rc_row("litb1d", rc_b1d())
def t_litf2d() -> IO(Unit): rc_row("litf2d", M.mo_fx2d())

# --- 5-12: `any`/`all` (reduce.py:96-138), which nobody had ported.
#
# THE BOOL/INT PROMOTION PAIR. `any`/`all` cast to bool FIRST (dtype.py:124) and
# `any_b`/`all_b` are the cases where that cast is the IDENTITY, so they are 2
# nodes where `any_i`/`all_i` are 3. A `bool()` that always minted would make
# all four print 3 and the four rows would still be four green rows -- the pair
# is the whole point of them.
def t_any0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("any0", rc_any(False{}, x, M.mo_ax(False{}, x, 0)))
def t_all0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("all0", rc_all(False{}, x, M.mo_ax(False{}, x, 0)))
def t_any_b() -> IO(Unit):
  +x = rc_b1d()
  rc_row("any_b", rc_any(False{}, x, M.mo_ax(False{}, x, 0)))
def t_all_b() -> IO(Unit):
  +x = rc_b1d()
  rc_row("all_b", rc_all(False{}, x, M.mo_ax(False{}, x, 0)))
def t_any_i() -> IO(Unit):
  +x = M.mo_i1d()
  rc_row("any_i", rc_any(False{}, x, M.mo_ax(False{}, x, 0)))
def t_all_i() -> IO(Unit):
  +x = M.mo_i1d()
  rc_row("all_i", rc_all(False{}, x, M.mo_ax(False{}, x, 0)))

# `keepdim` through the bool cast, so the reshape's shape arg is on the far side
# of a CAST -- the pair that a signature alone cannot separate from `sum0kd`.
def t_any0kd() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("any0kd", rc_any(True{}, x, M.mo_ax(False{}, x, 0)))
def t_all0kd() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("all0kd", rc_all(True{}, x, M.mo_ax(False{}, x, 0)))

# --- 13-16: the `dtype is None` arms, called from HERE, so the row exercises
# `rc_any`'s reach-through as well as `reduce.py`'s own methods.
def t_sum0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("sum0", M.mo_sum(False{}, x, M.mo_ax(False{}, x, 0)))
def t_prod0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("prod0", M.mo_prod(False{}, x, M.mo_ax(False{}, x, 0)))
def t_max0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("max0", M.mo_max(False{}, x, M.mo_ax(False{}, x, 0)))

# THE BOOL-SOURCE PROMOTION PAIR for the OTHER two methods, and it is the pair
# that separates `prod` from `sum`: on a bool source `sum` promotes
# (`sum_acc_dtype` -> least_upper_dtype(bool,int32) = int32) and mints a CAST,
# while `prod` casts to `self.dtype` (bool) and mints NOTHING. CPython: `sum_b`
# is `3 BUFFER/0 CAST/1 REDUCE/1` and `prod_b` is `2 BUFFER/0 REDUCE/1`.
def t_sum_b() -> IO(Unit):
  +x = rc_b1d()
  rc_row("sum_b", M.mo_sum(False{}, x, M.mo_ax(False{}, x, 0)))
def t_prod_b() -> IO(Unit):
  +x = rc_b1d()
  rc_row("prod_b", M.mo_prod(False{}, x, M.mo_ax(False{}, x, 0)))

# --- 17-18: THE `dtype is not None` ARMS (reduce.py:44/:71). These are the defs
# that had no home, and `sum_dt_i32` is the row that says the given-dtype arm
# is a CAST to the GIVEN dtype and not `sum_acc_dtype`.
def t_sum_dt_i32() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("sum_dt_i32", rc_sum_dt(x, S.int32(), False{}, M.mo_ax(False{}, x, 0)))
def t_prod_dt_i32() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("prod_dt_i32", rc_prod_dt(x, S.int32(), False{}, M.mo_ax(False{}, x, 0)))

# --- 19: THE `Sequence[int]` ARM (reduce.py:15). `sum(axis=(0,))` must be the
# SAME GRAPH as `sum(axis=0)` -- `make_tuple` on a tuple is the tuple -- and the
# only thing that can tell a `rc_axs` that dropped an element is the shape, so
# this row and `sum0` are the pair.
def t_sum_axs0() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("sum_axs0", M.mo_sum(False{}, x, rc_axs(x, [Ax{False{}, 0}])))

# `num_axes = 2` IS THE ONLY ROW THAT HAS IT. Every other row in this file prints
# `red=OP/1` or `red=OP/0`, so the `num_axes` column is a CONSTANT over the rest
# of the gate -- and a column that never varies is a column no mutation can
# move. `axis=(0,1)` on the 2-D source is the row, and it is also the only one
# that folds `rc_axs` over a list of LENGTH TWO.
def t_sum_axs01() -> IO(Unit):
  +x = M.mo_fx2d()
  rc_row("sum_axs01", M.mo_sum(False{}, x, rc_axs(x, [Ax{False{}, 0}, Ax{False{}, 1}])))

# AND THE NEGATIVE AXIS, which is the only row in this file where `Ax.neg` is
# LOAD-BEARING. `_resolve_dim` (movement.py:81) is `dim + total if dim < 0 else
# dim`, so `axis=(-2,)` on a rank-2 source resolves to `0` and the graph is
# `sum2d_ax0`'s.
#
# THE RANK MATTERS AND IT COST A ROW. The first version of this row was
# `axis=(-1,)` on the rank-1 source, and it could not tell "the resolve is
# correct" from "`neg` was dropped" -- because `mo_resolve`'s negative arm is
# wrong (see the header), `(-1,)` resolves to `2` and dropping `neg` yields `1`,
# and on a rank-1 source BOTH ARE OUT OF RANGE and both collapse to `num_axes=0`.
# The two wrong answers are the same wrong answer, so mutation M17 moved nothing
# and the row was decoration. `(-2,)` on rank 2 is the fix: correct is `0`, and
# dropping `neg` gives `2`, which is out of range, so the row separates them.
def t_sum_axs_neg() -> IO(Unit):
  +x = M.mo_fx2d()
  rc_row("sum_axs_neg", M.mo_sum(False{}, x, rc_axs(x, [Ax{True{}, 2}])))

# --- 20-22: THE IDENTITY ROWS. Four cases, and a reduce gate without them
# cannot tell a correct implementation from one that always rebuilds.
#
# (a) `axis=()` -- `mo_ax` cannot spell it (it always builds one element) so it
#     is `Nil{}` written out, and `_rop`'s `reduce_axis` is empty so the answer
#     IS the source: root=BUFFER, `red=none`, ONE node. `any_empty` is the one
#     that still casts: `bool()` runs BEFORE `_rop`, so the answer is the CAST
#     and not the source, which is why these four rows are not interchangeable.
def t_sum_empty() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("sum_empty", M.mo_sum(False{}, x, Nil{}))
def t_max_empty() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("max_empty", M.mo_max(False{}, x, Nil{}))
def t_any_empty() -> IO(Unit):
  +x = M.mo_fx1d()
  rc_row("any_empty", rc_any(False{}, x, Nil{}))

# (b) `reduce.py:16`'s `if self.ndim == 0: axis = ()`, on the 0-d source. Five
#     rows because all five of reduce.py's methods go through the same line and
#     `M.mo_axis0` is op.bend's; the pair that pins `mo_axis0` is `max_z0` (no
#     cast, `M.mo_max`) against `sum_z0` (`M.mo_sum`'s `sum_acc_dtype` cast IS
#     the commit cast, so it is one CAST either way).
def t_max_z0() -> IO(Unit):
  +z = rc_z0()
  rc_row("max_z0", M.mo_max(False{}, z, M.mo_ax_all(z)))
def t_sum_z0() -> IO(Unit):
  +z = rc_z0()
  rc_row("sum_z0", M.mo_sum(False{}, z, M.mo_ax_all(z)))
def t_any_z0() -> IO(Unit):
  +z = rc_z0()
  rc_row("any_z0", rc_any(False{}, z, M.mo_ax_all(z)))

# (c) A REDUCE OVER A NON-REDUCE AXIS -- the size-one axis of `rc_14`. `ops.py`
# :657 filters it out of `reduce_axis`, so NO REDUCE is built and the answer is
# a RESHAPE of the source. `red=none` is the claim and `root=RESHAPE` is what a
# rebuild would get wrong.
def t_max_ax0_14() -> IO(Unit):
  +x = rc_14()
  rc_row("max_ax0_14", M.mo_max(False{}, x, M.mo_ax(False{}, x, 0)))
def t_any_ax0_14() -> IO(Unit):
  +x = rc_14()
  rc_row("any_ax0_14", rc_any(False{}, x, M.mo_ax(False{}, x, 0)))

# --- THE TWO-REDUCE ROW, and it is the only row that can see the GATE's
# first-wins guard. `rc_find` takes the FIRST REDUCE in the toposort and the
# guard that stops it being overwritten is the mutation that inverts `ok`; with
# one REDUCE per graph the two policies are the same function. Chaining two
# DIFFERENT reduces over the same source is the fixture that separates them, and
# `any(...).all(...)` rather than `sum(...).sum(...)` is what makes them
# separable: two ADDs of one axis are `ADD/1` and `ADD/1`, so first-wins and
# last-wins agree on the `red=` column, while a MAX and a MUL do not.
def t_chain_any() -> IO(Unit):
  +x = M.mo_fx2d()
  +a = rc_any(False{}, x, M.mo_ax(False{}, x, 0))
  rc_row("chain_any", rc_all(False{}, a, M.mo_ax(False{}, a, 0)))

# `all_ax0_14` is `any_ax0_14`'s twin and it exists for the symmetry M1/M2 need:
# with only `any_ax0_14` present, swapping MAX for MUL in `rc_any` moved FIVE
# rows and the same swap in `rc_all` moved FOUR, and the difference was a
# MISSING ROW rather than a difference in the code. Symmetric fixtures are not
# independent evidence -- they are the same mutation twice -- and the table says
# so; what they buy is that the two halves of the pair can be compared at all.
def t_all_ax0_14() -> IO(Unit):
  +x = rc_14()
  rc_row("all_ax0_14", rc_all(False{}, x, M.mo_ax(False{}, x, 0)))

# The last statement of a `do IO<Unit>` block must be a BARE TERM (renderer/
# __init__.bend rule 1), so the block ends on a call rather than on a `<-` bind.
def t_end() -> IO(Unit):
  IO.print("end")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_lit1d()
    b : Unit <- t_liti1d()
    c : Unit <- t_litb1d()
    d : Unit <- t_litf2d()
    e : Unit <- t_any0()
    f : Unit <- t_all0()
    g : Unit <- t_any_b()
    h : Unit <- t_all_b()
    i : Unit <- t_any_i()
    j : Unit <- t_all_i()
    k : Unit <- t_any0kd()
    l : Unit <- t_all0kd()
    m : Unit <- t_sum0()
    n : Unit <- t_prod0()
    o : Unit <- t_max0()
    p : Unit <- t_sum_b()
    q : Unit <- t_prod_b()
    r : Unit <- t_sum_dt_i32()
    s : Unit <- t_prod_dt_i32()
    u : Unit <- t_sum_axs0()
    u2 : Unit <- t_sum_axs01()
    u3 : Unit <- t_sum_axs_neg()
    v : Unit <- t_sum_empty()
    w : Unit <- t_max_empty()
    x : Unit <- t_any_empty()
    y : Unit <- t_max_z0()
    z : Unit <- t_sum_z0()
    aa : Unit <- t_any_z0()
    ab : Unit <- t_max_ax0_14()
    ac : Unit <- t_any_ax0_14()
    ad : Unit <- t_all_ax0_14()
    ae : Unit <- t_chain_any()
    t_end()