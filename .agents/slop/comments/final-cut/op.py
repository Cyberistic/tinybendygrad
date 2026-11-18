import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/op.bend"

EDITS = [
  # ---- THE 206-LINE BLOCK: THE EIGHT WALLS (a LIST) MOVES OUT, W9a/W9b STAY (THEY ARE THE
  # OPEN BUG), THE FIVE BEND RULES STAY, THE GATE STAYS, THE MUTATION TABLE'S FOUR ROWS THAT
  # MOVE NOTHING STAY (THEY ARE THE FACT), AND THE PROSE GOES.
  (40, 245, """# THE EIGHT WALLS, each named at its Python line, ARE IN
# `.agents/slop/tables/mixin-op-40.md`. All eight are missing SUBSTRATE.
#
# `item` (op.py:22) and `data` (op.py:20) are NOT WALLS and are not ports: `data` is a `raise
# NotImplementedError` declaration and `item` reads host memory through it, which is the same
# device-state seam `tensor.bend` records as WALL 2.
#
# W9 -- TWO MEASURED DEFECTS IN `mixin/elementwise.bend`, both in `promote`
# (elementwise.py:24-34), and between them the reason this file spells its own `_broadcasted`.
# `elementwise.bend` is not owned here, so both are REPORTED and routed around rather than fixed
# in place.
#
#   W9a -- the ARENA. `ew_promote.b` used to build its reminted node as
#     `ew_of(ew_remint(4n, F.Folded.ar(fx), u, wd))`, and `F.Folded.ar(fx)` is the arena as it was
#     BEFORE `ew_remint` grew it, so the answer carried a stale arena and an index that arena did
#     not have. MEASURED on bend 2.0.34: `ew_ne(f32_buffer, ECon{CInt 0})` printed
#         A| NOOP() BUFFER() CONST()i CMPNE(1,3,)   <- src1 is 3, the CMPNE ITSELF
#         B| NOOP() BUFFER() CONST()f CMPNE(1,2,)   <- the float path is right
#     and the int path's toposort answered `1 BUFFER/0`, because the self-edge is already-visited:
#     `ne(0)` on a FLOAT tensor was a graph with a CYCLE, and it typechecked and ran. FIXED in the
#     substrate while this file was being written -- `ew_rebase` (elementwise.bend:230
#     symbol=ew_rebase), on every arm that mints nothing, which is the whole of the fix. `mo_arena`
#     below is that one line, kept because W9b means `mo_promote` is spelled here anyway.
#
#   W9b -- the MISSING CONJUNCT, and this one is OPEN. `ew_promote`
#     (mixin/elementwise.bend:355 symbol=ew_promote) hands `ew_promote.at` the weak test as
#     `W.dt_weak(dt)`, and `W.dt_weak` is the CLASS test ALONE (`weak_cls(S.Dt.cls(d))`,
#     weak.bend). elementwise.py:30 is
#         `if t.dtype in dtypes.weaks and t._uop.base.op is Ops.CONST:`
#     -- two conjuncts, and the second is the one that decides whether a weak NON-CONST is
#     reminted (kept weak) or CAST up to the out dtype. `ew_promote` computes the base
#     (`b = ew_base(fx, u)`) and passes it to `is_invalid` and to nothing else, which is where
#     `ew_is_const(fx, b)` went. MEASURED: `normalize(p=0, dim=0)` builds
#     `MAX(CAST(int->weakfloat), CONST 1e-12) : weakfloat` and then `self / that`, whose
#     `_broadcasted` out dtype is float32 -- so CPython casts the weakfloat MAX up (node 14 of its
#     17). Deleting the `is CONST` conjunct from `mo_promote` -- i.e. routing every promotion in
#     this file through `E.ew_promote` -- makes `t_norm0` print 16 against CPython's 17, losing
#     exactly the `CAST/1` after `MAX/2` and nothing else in the file. So it is `mo_promote`, and
#     through it the whole `mo_bin`/`mo_sub`/`mo_where` family, that is spelled here rather than
#     called: they all promote.
#
# `t_bin_promote` is the row that pins the ARENA half, and it is four-sided.
#
# FIVE BEND RULES THIS FILE LEARNS, in the order it learned them.
#
#   1. A def body is ONE EXPRESSION and a `let` is affine, so anything used twice is either a `+`
#      parameter or a second CALL. Every dispatch below passes its tests IN -- `keepdim`, `inv`,
#      `wc`, `same`, `isid`, `uns`, `ok` -- because a `match` may scrutinise a PARAMETER or a
#      PATTERN BINDER and not a call.
#   2. the arena a build returned is not the arena that went in, and every def here that builds
#      returns a `Tensor`/`Found` carrying the GROWN arena. W9 is that rule being broken one
#      file over, and the rule is why `mo_reduce` re-folds between its `cast` and its `rop`
#      exactly the way `ew_promo2` does.
#   3. `Maybe` is a `Type` and cannot carry a `+`, and `F.fold.dt` / `F.fold.shape` both answer
#      one. So each reader here unwraps ONCE, and the "fold cannot answer this node" arm is the
#      honest default -- `S.void()` for a dtype and `Nil{}` for a shape. Both are UNREACHABLE for
#      the recipes below, and the reason is worth stating because it is why the port is checkable
#      at all: none of them builds a PERMUTE/PAD/SHRINK/EXPAND/FLIP, which are the five ops
#      `dt_shape` defers (fold.bend:2644 symbol=dt_shape). The movement op they do build is
#      RESHAPE, which `reshape_ds` (fold.bend:2228 symbol=reshape_ds) answers, and REDUCE, which
#      `reduce_ds` (fold.bend:2239 symbol=reduce_ds) answers. MEASURED, both, over a BUFFER-rooted
#      AND over a RESHAPE-rooted source.
#   4. `commit_dtype` (tinygrad/mixin/dtype.py:16) answers a `Maybe` because `UOp._min_max`
#      (ops.py:239 symbol=dtype) is not ported, and `mixin/dtype.bend` measures that refusal
#      rather than guessing. `_reduce` (reduce.py:13 symbol=_reduce) reads it, so this file needs
#      it, and the honest totalisation is the node's OWN dtype -- which makes the `cast` the
#      identity. A weakint node is therefore NOT committed, and `t_commit_weak` says so.
#   5. `U32.to_f32` and `F32.mul` are `law`s in `base.bend` and `tensor.bend`'s header says they
#      are unfilled and live code may not call them. MEASURED HERE, on bend 2.0.34 as `./bin/bend`
#      runs it: `F32.show(U32.to_f32(7))` prints `7` and `F32.show(F32.mul(1.0e30, 1.0e30))` prints
#      `inf` in BOTH lanes, and `--check-only` says ALL PROOFS CHECK. So `mo_inf` and the float
#      CONSTs the recipes need are live. REPORTED, not fixed: `tinybendygrad/tensor.bend`'s header
#      carries the stale claim.
#
# THE GATE. `main` prints one row per claim, in Python's order, in the
# `name=<count> OP/<nsrc> ...` format `tinybendygrad/tensor.bend` uses, so the CPython oracle is a
# `toposort()` and the two lanes diff byte for byte. Nothing is executed; every row is the
# SIGNATURE of the lazy graph, which needs no device.
#
#   .venv/bin/python .agents/slop/mixin-op-gate.py           > /tmp/py.txt
#   ./bin/bend tinybendygrad/mixin/op.bend                  > /tmp/bd.txt
#   ./bin/bend tinybendygrad/mixin/op.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
#   diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt
#
# EVERY ROW IS DERIVED FROM CPYTHON rather than restated from this file, and three kinds of row
# exist because three kinds of bug are invisible to the others:
#
#   * the `n=` COUNT, which sees a dropped or duplicated node;
#   * the ORDER of the signature, which sees a reversed operand (`min`'s `-1` and `-x`, `div`'s
#     `a * b.reciprocal()`) -- two CONSTs print the SAME signature either way round, so an
#     order-only row would be invisible;
#   * the DTYPE/OP rows, which see what a signature prints nothing of.
#
# `t_commit_weak`, `t_bin_promote` and `t_rop_gap` are BEND-ONLY: they name a refusal or a defect
# rather than a graph Python can be asked for. They are listed here rather than filtered silently.
#
# the two-rules-claim-one-node row is `t_two_rules`. `softmax` (op.py:663) and `log_softmax`
# (op.py:686 symbol=log_softmax) are TWO defs that both call `_softmax`, so the thirteen nodes
# `_softmax` (op.py:657 symbol=_softmax) builds are interned ONCE. `log_softmax` prints 18 over a
# graph whose shared prefix is 13 nodes -- MEASURED on both sides: the first thirteen op names of
# the longer row are the shorter row minus its last two -- and the tails are `RECIP MUL` against
# `LOG2 CONST MUL MUL ADD`. The row prints BOTH signatures from ONE arena. See its own comment for
# the half of the claim that no arena can see: a DUPLICATED `_softmax` re-interns the same nodes,
# because the arena is a hashcons.
#
# the mutation table -- what the gate sees and what it cannot. Seventeen one-token edits, each
# applied, each run through BOTH lanes, each diffed against the unmutated output and reverted from
# a byte snapshot:
#
#     .venv/bin/python .agents/slop/mixin-op-mutate.py
#
# Thirteen move something. Four do not, and all four are reported rather than dropped, because a
# table with no row that CANNOT move is a table of coincidences:
#
#   M6  reduce.py:45's trailing half/bfloat16/fp8 cast, inverted. NEGATIVE for a float32 fixture,
#       and the gate says so -- it is the only way to know the cast is guarded rather than applied.
#   M7  `smax(n - correction, 0)` (uop/ops.py:74 symbol=smax) with the saturation dropped. Both
#       arms agree at `correction=0`, which is what `t_var0c0` uses. A float32 fixture cannot see
#       `smax`, and saying so is the measurement.
#   M8  `log_softmax` reading `_softmax`'s `e` instead of its `m` (op.py:706). UNFALSIFIABLE, and
#       structurally so rather than for want of a fixture: `ss = e.sum(...)` already pulls `e` into
#       the graph, so `m - ss.log()` and `e - ss.log()` have the SAME node set, the same count and
#       the same op toposort, and differ in two src INDEXES. The two programs are graph-isomorphic,
#       so the CPython lane cannot separate them either -- tinygrad does not constant-fold. The
#       `softmax3_m/e/ss` rows (8/11/13 nodes) pin `_softmax`'s three OUTPUTS; which of them
#       `log_softmax` READS is verified by reading op.py:706, and this mutation is what says the
#       graph cannot.
#   M17 a CONTROL: a whitespace-only edit. Nothing moves, and that is the point.
#
# And one table row CHANGED THE TABLE. M10 -- dropping the arena re-wrap from `promote`'s
# `is_invalid` arm -- moved nothing, which was reported rather than explained away, and the reason
# turned out to be that `t_bin_promote` interned its invalid CONST the stale way (`mo_const_t`'s
# rule, in the row meant to test it), so the arm was never taken. The row was rebuilt and M10 now
# moves it. A mutation that moves nothing is a question; the question was worth asking.
#
# The measurement that built the rows is in each row's own comment: `mo_at`'s off-by-one (a head
# element's index is `len(t)`, and `RESHAPE(REDUCE, CONST(4))` and `RESHAPE(REDUCE, CONST(1))`
# print identically, so only `sh_sum0kd` saw it); `mo_reshape`'s one-element-RESHAPE fold gap;
# `mo_squeeze`'s negated test (upstream's `squeeze`, mixin/movement.py:301); `mo_eqmul`'s `bool`
# against the port's own `int` (upstream's `isinf`, mixin/elementwise.py:611); `mo_exp`'s cast
# ordering.
#
# the two halves share this file. side b must not re-declare any `mo_*` def, must not re-declare
# `main`, and must not touch anything above this line. Its own section goes below `main`, and its
# rows go in its own `mo2_*` printers."""),
]

apply(F, EDITS)
