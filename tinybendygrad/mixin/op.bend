# mixin/op.bend -- tinygrad/mixin/op.py, LINES 1-997.
#
# ---------------------------------------------------------------------------
# THE SPLIT IN THIS FILE is the split the brief drew, and it is a DEF boundary:
#
#   SIDE A (this half, lines 1-997)   data, item, __getitem__, _getitem, arange,
#     linspace, eye, _tri, triu, tril, _pad_constant, pad_to, _pad_circular,
#     _pad_reflect_replicate, pad, dot, matmul, einsum, gradient, min, mean, var,
#     var_mean, std, std_mean, normalize, logsumexp, _softmax, softmax,
#     log_softmax, softmin, cat, _cumalu, _split_cumalu, cumsum, cumprod, cummax,
#     cummin, logcumsumexp, argmax, argmin, sort, argsort, topk
#
#   SIDE B (the other half, lines 998-1980)  allclose, one_hot, gather,
#     interpolate, scatter, masked_select, nonzero, sequential, linear, the pools,
#     the convolutions, layernorm, batchnorm, the losses, qr, svd, keccak, hash
#
# THE BOUNDARY IS LINE 997, and it is a def boundary: `topk` is op.py:976-996 and
# 997 is its closing blank line, so SIDE A ends on a whole def and SIDE B starts on
# `allclose` (op.py:998). NOTHING IS PORTED TWICE.
#
# ---------------------------------------------------------------------------
# WHAT IS PORTED, IN PYTHON'S ORDER, AND WHAT IS NOT.
#
# PORTED AND GATED: the reduction family -- `min` (op.py:473), `mean` (:496),
# `var` (:523), `var_mean` (:551), `std` (:568), `std_mean` (:592), `logsumexp`
# (:630), `_softmax` (:657), `softmax` (:663), `log_softmax` (:686), `softmin`
# (:709) -- and `max`/`sum`/`prod` (reduce.py:73/:20/:47), which they call. Plus
# the three dtype helpers their bodies read: `weak_dtype` (tinygrad/dtype.py:175),
# `sum_acc_dtype` (tinygrad/dtype.py:220) and the `commit_dtype` refusal (tinygrad/dtype.py:16).
#
# The `min`/`max`/`sum`/`prod` hoists are reduce.py's lines and they move back with
# `mixin/reduce.bend`. They are hoisted because `mixin/reduce.bend` does not exist
# yet, and `tensor.bend` already sets that precedent by hoisting `_mop` (ops.py:821)
# and `_rop` (ops.py:655). `mo_reduce` here IS `T.tn_rop` plus `_reduce`'s two lines
# around it (reduce.py:13-18), and `T.tn_rop` is the `_rop` hoist.
#
# ---------------------------------------------------------------------------
# THE EIGHT WALLS, each named at its Python line. All eight are missing SUBSTRATE;
# W9 below is a different animal, a measured DEFECT in substrate that is present.
#
#   W1 mixin/op.py:74 `_getitem` -- the index is Python's
#      `int|slice|Tensor|None|list|tuple|Ellipsis`, a SEVEN-WAY sum type of
#      heterogeneous payloads (movement.py:86 `_parse_view_index` matches on the
#      Python TYPE), and the body then threads a list of FIVE-FIELD DICTS
#      (op.py:82). Bend's sum types hold one value per arm, so the `Ellipsis`
#      sentinel and the slice triple have no spelling, and `raise IndexError` has
#      no form.
#   W2 mixin/op.py:413 `einsum` -- a STRING FORMULA. `formula.split("->")`,
#      `"".join(sorted(...))`, `s.index(c)`, `s.count(c)`, `s.replace(c, "", 2)`
#      and `string.ascii_letters` are five distinct string algebras over the
#      formula, plus `dict.fromkeys` and `merge_dicts` over letter->size. Bend's
#      `String.split` takes a Char separator, so `split("->")` and `split(",")` do
#      not exist, and this is a whole PARSER.
#   W3 mixin/op.py:450 `gradient` -- `compute_gradient` is `mixin/gradient.py:132`,
#      which `mixin/gradient.bend` records as `TODO(p3)` ITSELF: the shaped-edge
#      reduce needs `broadcast_axes` (ops.py:89) which reads `resolve` on a `Sint`,
#      and `uop/symbolic.py`'s `resolve` is not ported. A wall whose own port
#      names it is the cheapest kind of wall to accept.
#   W4 mixin/op.py:752 `_cumalu` -> mixin/movement.py:598 `_pool` -- `_pool` is
#      TWELVE lines of shape arithmetic (`ceildiv`, `smax`, `flatten`, `repeat`,
#      `shrink_to`, four reshapes, a permute) and `fold.bend`'s `dt_shape`
#      (fold.bend:1622-1625) leaves PERMUTE, EXPAND, PAD, SHRINK and FLIP
#      un-answered, because their `marg` needs `ssimplify`. So `_pool` is
#      BUILDABLE but not CHECKABLE, and everything that reaches it through
#      `arange` (op.py:166) inherits it: `cumsum` (:770), `cumprod` (:784),
#      `cummax` (:798), `cummin` (:816), `logcumsumexp` (:830), `eye` (:215),
#      `_tri` (:233), `triu` (:236), `tril` (:259), and `sort`'s index count
#      (:958).
#   W5 mixin/op.py:913 `sort` -> `.contiguous()` (elementwise.py:59) is
#      `graph_rewrite` (ops.py:1880), which is P3 and lives in another module.
#      The bitonic loop is four nested `for` loops over stage counts, which Bend
#      spells as a fuel-carrying self-call; that part is mechanical, which is why
#      the wall is named at `contiguous` and not at the loop.
#   W6 mixin/op.py:731 `cat` -- `stack`/`flatten` are ops over a VARIADIC
#      `*args` tuple, `_pad_constant` needs `identity_element` (ops.py:61, and
#      `identity_element` is not in ops.bend), and the shape arithmetic is
#      `itertools.accumulate` over `t.shape[dim]`.
#   W7 mixin/op.py:609 `normalize` -- see the PARITY row below. `sign`
#      (elementwise.py:901) needs `const_like` (creation.py) plus `_broadcast_to`
#      (movement.py:128), and `_broadcast_to` calls `broadcast_axes` (ops.py:89),
#      which is `resolve` on a `Sint` -- W3's wall, reached a second time. The
#      `p == 0` arm needs nothing but `ne`, so `mo_norm0` IS ported and gated;
#      the `p != 0` arm is `W7`.
#   W8 mixin/op.py:394 `matmul` / op.py:359 `dot` -- a WMMA lowering over
#      `UOp(Ops.WMMA, ...)` with a device-specific arg, and `dot`'s `permute +
#      reshape` contraction needs `resolve` (W3) to decide which `N` the WMMA
#      gets.
#
# `item` (op.py:22) and `data` (op.py:20) are NOT WALLS and are not ports:
# `data` is a `raise NotImplementedError` declaration and `item` reads host memory
# through it, which is the same device-state seam `tensor.bend` records as WALL 2.
#
# ---------------------------------------------------------------------------
# W9 -- TWO MEASURED DEFECTS IN `mixin/elementwise.bend`, both in `promote`
# (elementwise.py:24-34), and between them the reason this file spells its own
# `_broadcasted`. `elementwise.bend` is not owned here, so both are REPORTED and
# routed around rather than fixed in place.
#
#   W9a -- the ARENA. `ew_promote.b` used to build its reminted node as
#     `ew_of(ew_remint(4n, F.Folded.ar(fx), u, wd))`, and `F.Folded.ar(fx)` is the
#     arena as it was BEFORE `ew_remint` grew it, so the answer carried a stale
#     arena and an index that arena did not have. MEASURED on bend 2.0.34:
#     `ew_ne(f32_buffer, ECon{CInt 0})` printed
#         A| NOOP() BUFFER() CONST()i CMPNE(1,3,)   <- src1 is 3, the CMPNE ITSELF
#         B| NOOP() BUFFER() CONST()f CMPNE(1,2,)   <- the float path is right
#     and the int path's toposort answered `1 BUFFER/0`, because the self-edge is
#     already-visited: `ne(0)` on a FLOAT tensor was a graph with a CYCLE, and it
#     typechecked and ran. FIXED in the substrate while this file was being
#     written -- `ew_rebase` (elementwise.bend:209), on every arm that mints
#     nothing, which is the whole of the fix. `mo_arena` below is that one line,
#     kept because W9b means `mo_promote` is spelled here anyway.
#
#   W9b -- the MISSING CONJUNCT, and this one is OPEN. `ew_promote`
#     (elementwise.bend:378) hands `ew_promote.at` the weak test as `W.dt_weak(dt)`,
#     and `W.dt_weak` is the CLASS test ALONE (`weak_cls(S.Dt.cls(d))`, weak.bend).
#     elementwise.py:30 is
#         `if t.dtype in dtypes.weaks and t._uop.base.op is Ops.CONST:`
#     -- two conjuncts, and the second is the one that decides whether a weak
#     NON-CONST is reminted (kept weak) or CAST up to the out dtype.
#     `ew_promote` computes the base (`b = ew_base(fx, u)`) and passes it to
#     `is_invalid` and to nothing else, which is where `ew_is_const(fx, b)` went.
#     MEASURED: `normalize(p=0, dim=0)` builds
#     `MAX(CAST(int->weakfloat), CONST 1e-12) : weakfloat` and then `self / that`,
#     whose `_broadcasted` out dtype is float32 -- so CPython casts the weakfloat
#     MAX up (node 14 of its 17). Deleting the `is CONST` conjunct from
#     `mo_promote` -- i.e. routing every promotion in this file through
#     `E.ew_promote` -- makes `t_norm0` print 16 against CPython's 17, losing
#     exactly the `CAST/1` after `MAX/2` and nothing else in the file. So it is
#     `mo_promote`, and through it the whole `mo_bin`/`mo_sub`/`mo_where` family,
#     that is spelled here rather than called: they all promote.
#
# `t_bin_promote` is the row that pins the ARENA half, and it is four-sided --
# its own comment carries the measurement that found it was not.
#
# ---------------------------------------------------------------------------
# FIVE BEND RULES THIS FILE LEARNS, in the order it learned them.
#
#   1. A def body is ONE EXPRESSION and a `let` is affine, so anything used twice is
#      either a `+` parameter or a second CALL. Every dispatch below passes its
#      tests IN -- `keepdim`, `inv`, `wc`, `same`, `isid`, `uns`, `ok` -- because a
#      `match` may scrutinise a PARAMETER or a PATTERN BINDER and not a call.
#   2. THE ARENA A BUILD RETURNED IS NOT THE ARENA THAT WENT IN, and every def here
#      that builds returns a `Tensor`/`Found` carrying the GROWN arena. W9 is that
#      rule being broken one file over, and the rule is why `mo_reduce` re-folds
#      between its `cast` and its `rop` exactly the way `ew_promo2` does.
#   3. `Maybe` is a `Type` and cannot carry a `+`, and `F.fold.dt` /
#      `F.fold.shape` both answer one. So each reader here unwraps ONCE, and the
#      "fold cannot answer this node" arm is the honest default -- `S.void()` for a
#      dtype and `Nil{}` for a shape. Both are UNREACHABLE for the recipes below,
#      and the reason is worth stating because it is why the port is checkable at
#      all: none of them builds a PERMUTE/PAD/SHRINK/EXPAND/FLIP, which are the
#      five ops `dt_shape` defers (fold.bend:1622-1625). The movement op they do
#      build is RESHAPE, which `reshape_ds` (fold.bend:1537) answers, and REDUCE,
#      which `reduce_ds` (:1530) answers. MEASURED, both, over a BUFFER-rooted AND
#      over a RESHAPE-rooted source.
#   4. `commit_dtype` (tinygrad/dtype.py:16) answers a `Maybe` because `UOp._min_max`
#      (ops.py:1104) is not ported, and `mixin/dtype.bend` measures that refusal
#      rather than guessing. `_reduce` (reduce.py:14) reads it, so this file needs
#      it, and the honest totalisation is the node's OWN dtype -- which makes the
#      `cast` the identity. A weakint node is therefore NOT committed, and
#      `t_commit_weak` says so.
#   5. `U32.to_f32` and `F32.mul` are `law`s in `base.bend` and `tensor.bend`'s
#      header says they are unfilled and live code may not call them. MEASURED HERE,
#      on bend 2.0.34 as `./bin/bend` runs it: `F32.show(U32.to_f32(7))` prints `7`
#      and `F32.show(F32.mul(1.0e30, 1.0e30))` prints `inf` in BOTH lanes, and
#      `--check-only` says ALL PROOFS CHECK. So `mo_inf` and the float CONSTs the
#      recipes need are live. REPORTED, not fixed: `tinybendygrad/tensor.bend`'s
#      header carries the stale claim.
#
# ---------------------------------------------------------------------------
# THE GATE. `main` prints one row per claim, in Python's order, in the
# `name=<count> OP/<nsrc> ...` format `tinybendygrad/tensor.bend` uses, so the
# CPython oracle is a `toposort()` and the two lanes diff byte for byte. Nothing is
# executed; every row is the SIGNATURE of the lazy graph, which needs no device.
#
#   .venv/bin/python .agents/slop/mixin-op-gate.py           > /tmp/py.txt
#   ./bin/bend tinybendygrad/mixin/op.bend                  > /tmp/bd.txt
#   ./bin/bend tinybendygrad/mixin/op.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
#   diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt
#
# EVERY ROW IS DERIVED FROM CPYTHON rather than restated from this file, and three
# kinds of row exist because three kinds of bug are invisible to the others:
#
#   * the `n=` COUNT, which sees a dropped or duplicated node;
#   * the ORDER of the signature, which sees a reversed operand (`min`'s `-1` and
#     `-x`, `div`'s `a * b.reciprocal()`) -- two CONSTs print the SAME signature
#     either way round, so an order-only row would be invisible;
#   * the DTYPE/OP rows, which see what a signature prints nothing of.
#
# `t_commit_weak`, `t_bin_promote` and `t_rop_gap` are BEND-ONLY: they name a
# refusal or a defect rather than a graph Python can be asked for. They are listed
# here rather than filtered silently.
#
# THE TWO-RULES-CLAIM-ONE-NODE ROW is `t_two_rules`. `softmax` (op.py:663) and
# `log_softmax` (op.py:686) are TWO defs that both call `_softmax` (op.py:657), so
# the thirteen nodes `_softmax` builds are interned ONCE. `softmax` prints 15 and
# `log_softmax` prints 18 over a graph whose shared prefix is 13 nodes -- MEASURED on
# both sides: the first thirteen op names of the longer row are the shorter row minus
# its last two -- and the tails are `RECIPROCAL MUL` against `LOG2 CONST MUL MUL ADD`.
# The row prints BOTH signatures from ONE arena. See its own comment for the half of
# the claim that no arena can see: a DUPLICATED `_softmax` re-interns the same nodes,
# because the arena is a hashcons.
#
# ---------------------------------------------------------------------------
# THE MUTATION TABLE -- WHAT THE GATE SEES AND WHAT IT CANNOT. Seventeen one-token
# edits, each applied, each run through BOTH lanes, each diffed against the
# unmutated output and reverted from a byte snapshot:
#
#     .venv/bin/python .agents/slop/mixin-op-mutate.py
#
# Thirteen move something. Four do not, and all four are reported rather than
# dropped, because a table with no row that CANNOT move is a table of coincidences:
#
#   M6  reduce.py:45's trailing half/bfloat16/fp8 cast, inverted. NEGATIVE for a
#       float32 fixture, and the gate says so -- it is the only way to know the cast
#       is guarded rather than applied.
#   M7  `smax(n - correction, 0)` (helpers.py:65) with the saturation dropped. Both
#       arms agree at `correction=0`, which is what `t_var0c0` uses. A float32
#       fixture cannot see `smax`, and saying so is the measurement.
#   M8  `log_softmax` reading `_softmax`'s `e` instead of its `m` (op.py:706).
#       UNFALSIFIABLE, and structurally so rather than for want of a fixture:
#       `ss = e.sum(...)` already pulls `e` into the graph, so `m - ss.log()` and
#       `e - ss.log()` have the SAME node set, the same count and the same op
#       toposort, and differ in two src INDEXES. The two programs are
#       graph-isomorphic, so the CPython lane cannot separate them either -- tinygrad
#       does not constant-fold. The `softmax3_m/e/ss` rows (8/11/13 nodes) pin
#       `_softmax`'s three OUTPUTS; which of them `log_softmax` READS is verified by
#       reading op.py:706, and this mutation is what says the graph cannot.
#   M17 a CONTROL: a whitespace-only edit. Nothing moves, and that is the point.
#
# And one table row CHANGED THE TABLE. M10 -- dropping the arena re-wrap from
# `promote`'s `is_invalid` arm -- moved nothing, which was reported rather than
# explained away, and the reason turned out to be that `t_bin_promote` interned its
# invalid CONST the stale way (`mo_const_t`'s rule, in the row meant to test it), so
# the arm was never taken. The row was rebuilt and M10 now moves it. A mutation that
# moves nothing is a question; the question was worth asking.
#
# The measurement that built the rows is in each row's own comment: `mo_at`'s
# off-by-one (a head element's index is `len(t)`, and `RESHAPE(REDUCE, CONST(4))`
# and `RESHAPE(REDUCE, CONST(1))` print identically, so only `sh_sum0kd` saw it);
# `mo_reshape`'s one-element-RESHAPE fold gap; `mo_squeeze`'s negated test
# (movement.py:308); `mo_eqmul`'s `bool` against `int` (elementwise.py:613);
# `mo_exp`'s cast ordering.
#
# ---------------------------------------------------------------------------
# THE TWO HALVES SHARE THIS FILE. SIDE B must not re-declare any `mo_*` def, must
# not re-declare `main`, and must not touch anything above this line. Its own
# section goes below `main`, and its rows go in its own `mo2_*` printers.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../uop/weak.bend as W
import ./../tensor.bend as T
import ./dtype.bend as D
import ./elementwise.bend as E

# ===========================================================================
# THE READERS. Three of them, and each is a fold read with the fold's own
# "I cannot answer this node" as the default -- rule 3 in the header.
# `F.fold.dt` answers `Maybe<&2, S.Dt>` and `F.fold.shape` answers a DOUBLE
# `Maybe` (the outer is the fold, the inner is Python's own `None`), so the shape
# reader is two unwraps and the dtype reader is one.
# ===========================================================================

def mo_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

def mo_dims.put(m: Maybe<&2, List<&2, O.Sint>>) -> List<&2, O.Sint>:
  match m:
    case Some{ds}: ds
    case _: Nil{}

def mo_dims.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> List<&2, O.Sint>:
  match m:
    case Some{ds}: mo_dims.put(ds)
    case _: Nil{}

def mo_dims(+fx: F.Folded, i: U32) -> List<&2, O.Sint>:
  mo_dims.of(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), i))

# `self.ndim` (movement.py:25) -- `len(self.shape)`.
def mo_ndim(+fx: F.Folded, i: U32) -> Nat:
  List.length(&2, O.Sint, mo_dims(fx, i))

# `self.shape[k]` (movement.py:62) for a CONCRETE dim. `O.SI` is the image
# `F.sint_of` builds for every count under 2^31 and `H.lo32` is exact on one.
# `O.SU` is a dim that is a UOP, and `ssimplify` (ops.py:94, reached by
# `_shape`'s movement arms) is what turns one into a number; it is not ported.
# TODO(p3) mixin/op.py:62  self.shape[k] for a SYMBOLIC dim -- `O.SU` needs
#   `ssimplify`/`resolve` from `uop/symbolic.py` (P3, and W3's wall). The wall is
#   named at every user of this def, which is why `mo_dim_u32` answers 0 and not 1:
#   0 is what `Arena.src` gives for an out-of-range read, and a symbolic dim that
#   silently became 1 would be a WRONG shape rather than a missing one.
def mo_dim_u32(d: O.Sint) -> U32:
  match d:
    case O.SI{i}: H.lo32(i)
    case _: 0

def mo_dim_at(+fx: F.Folded, +i: U32, k: U32) -> U32:
  mo_dim_u32(Maybe.default(&2, O.Sint, List.get(&2, O.Sint, mo_dims(fx, i), U32.to_nat(k)), F.sint_of(1)))

# THE INDEX OF A HEAD ELEMENT, `i` in `enumerate(self.shape)`, and it is `len(t)` --
# the TAIL's length, because a pattern `case d <> t` leaves `t` one shorter than the
# scrutinee and the head sits at `len(t)`. It is a length rather than a threaded
# counter because a def body reads its parameters once each, and threading `i` would
# need it for the test AND for the increment.
#
# MEASURED: the first version said `len(ds) - len(t)`, which is `len(t) + 1`, and every
# index in every walk was off by one. `t_sum0kd` still printed the right four nodes --
# `RESHAPE(REDUCE, CONST(4))` has the same node COUNT and the same op names as
# `RESHAPE(REDUCE, CONST(1))` -- so the signature rows could not see it and the COUNT
# could not either. It is `sh_sum0kd` (the SHAPE row) that caught it.
def mo_at(+ds: List<&2, O.Sint>, +t: List<&2, O.Sint>) -> U32:
  U32.from_nat(List.length(&2, O.Sint, t))

# `tuple(range(n))` -- `permute`'s identity test (movement.py:214) and
# `_reduce`'s `range(self.ndim)` when `axis is None` (reduce.py:15) are the SAME list,
# so this is one def and both are calls.
# The SELF-CALL TAKES THE LIST FIRST and the countdown second, which is Bend's rule
# (a self-call must read left to right and the SHRINKING argument goes first) and is
# why `tensor.bend`'s `tn_rop.ne1` and `tn_sarg.acc` are both shaped this way. `i` is
# not a parameter at all: it is `len(acc)`, which is what `range(n)` is.
def mo_range.go(n: Nat, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: mo_range.go(p, List.append(&2, U32, acc, [U32.from_nat(List.length(&2, U32, acc))]))

def mo_range(n: Nat) -> List<&2, U32>: mo_range.go(n, Nil{})

# ===========================================================================
# THE CONSTS. `UOp.const` (ops.py:631) is a BARE CONST here because `dtypes.from_py`
# and `truncate` are P3 (ops.bend's own `TODO`), and every CONST this file builds is
# already the dtype Python would derive: an int literal is weakint and a float
# literal is weakfloat, which is exactly `dtypes.from_py`.
# ===========================================================================

def mo_ki(n: U32) -> O.Const: O.CInt{H.i64_of_i32(n)}

# A CONST NODE IN `t`'s ARENA, and it is a DEF rather than an inline
# `T.tn_new(T.Tensor.ar(t), O.Found.i(O.UOp.const(T.Tensor.ar(t), v)))` for a measured
# reason: arguments read LEFT TO RIGHT, so the inline form reads `Tensor.ar(t)` BEFORE
# the CONST is interned and hands back a Tensor whose arena is one node too short. The
# node then reads as the `NOOP` bottom, its dtype folds to `void`, and the promotion
# below silently takes its BOOL arm -- MEASURED, `t_mean0` printed
# `2 NOOP/0 CAST/1` and `t_min0` printed nothing at all. Every CONST this file builds
# goes through here.
def mo_const_t(+t: T.Tensor, v: O.Const) -> T.Tensor:
  +f = O.UOp.const(T.Tensor.ar(t), v)
  T.tn_new(O.Found.ar(f), O.Found.i(f))

# AND THE SAME FOR A CAST, for the same reason and with a bigger blast radius: written
# inline as `E.ew_cast(F.folded(Tensor.ar(d)), d, dt)` the FOLD is read BEFORE the `d`
# that grows the arena is built, so the CAST is interned into an arena that does not
# have its own source. MEASURED: `t_mean0` printed `2 NOOP/0 CAST/1` -- a CAST whose
# src is the arena's bottom node -- and `t_softmax0` lost its REDUCE to the same
# overwrite. `W.wk_cast_at` is `elementwise.bend`'s `ew_cast` callee
# (elementwise.bend:126), so this is a CALL and not a reimplementation.
# AND `mo_promote` NEEDS THE OTHER ONE, because a def that is handed a fold has to build
# in the fold's arena and not in `t`'s: `t` may be older than the operand that was
# interned after it. MEASURED: with `mo_cast_t` there, the promoted CAST of `norm0`'s
# `maximum` landed on the CONST's own index, `MAX(CAST, CAST)` had no source, and the
# toposort printed `2 CONST/0 MAX/2`. `W.wk_cast_at` is the `elementwise.bend` callee.
def mo_cast_in(+fx: F.Folded, +t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  +f = W.wk_cast_at(fx, T.Tensor.u(t), dt)
  T.tn_new(O.Found.ar(f), O.Found.i(f))

def mo_cast_t(+t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  mo_cast_in(F.folded(T.Tensor.ar(t)), t, dt)

# the I64 inside a shape CONST, which is what a `Sint` index is built from.
def mo_c_i64(v: O.Const) -> H.I64:
  match v:
    case O.CInt{i}: i
    case _: H.i64_of_i32(1)

# `1/math.log(2)` and `math.log(2)` -- elementwise.py:511 and :830. Both are the
# literals Python's module prints rather than an F32 computation, and rule 5 is why
# an F32 literal is available at all.
def mo_log2e() -> F32: 1.4426950408889634
def mo_ln2() -> F32: 0.6931471805599453

# `float("inf")` and `float("-inf")` -- elementwise.py:613. `F32.mul(1e30, 1e30)`
# overflows to infinity, which is `mixin/gradient.bend`'s `k_inf` and the same
# one-line spelling.
def mo_inf() -> F32: F32.mul(1.0e30, 1.0e30)
def mo_neginf() -> F32: F32.neg(mo_inf())

# `self.const_like(v)` (creation.py:71) is a bare CONST here for the same reason,
# and it is only reached by `normalize`'s `p == 0` arm (W7).
# ===========================================================================
# THE DTYPE ARITHMETIC. `weak_dtype` (tinygrad/dtype.py:175) is `dtypes.weakfloat if
# is_float else dtypes.weakint if is_int else dtype`, and `is_float`/`is_int` both
# INCLUDE their weak member -- so the whole thing is a three-arm match on `Cls`
# with `CVoid` as the identity. It is `uop/weak.bend`'s `W.weak_dtype` and this is
# the CALL, not a second copy: the house rule is reuse, and elementwise.bend sets
# the precedent by reading `W.weak_dtype` for the very same predicate.
# ===========================================================================

# `commit_dtype` -- tinygrad/dtype.py:16, read through `mixin/dtype.bend`'s own `commit_dtype`,
# which is the same refusal `_min_max` (ops.py:1104) forces. The honest
# totalisation is the node's OWN dtype, which makes the `cast` the identity; a
# weakint node is therefore NOT committed and `t_commit_weak` says so. Rule 4.
def mo_commit_dt(+fx: F.Folded, +t: T.Tensor) -> S.Dt:
  Maybe.default(&1, S.Dt, D.commit_dtype(mo_dt(fx, T.Tensor.u(t)), None{}, None{}, S.int32()),
    mo_dt(fx, T.Tensor.u(t)))

# `sum_acc_dtype` -- tinygrad/dtype.py:220. The float arm reads `getenv("SUM_DTYPE",
# "float32")`, which is a `Config` read and `Config` is P6; the DEFAULT is float32
# and no caller in this file's range overrides it, which is the same argument
# fold.bend makes for `least_upper_float` (fold.bend:176).
# TODO(p3) tinygrad/dtype.py:220  sum_acc_dtype's `getenv("SUM_DTYPE")` -- a
#   `Config` read (P6). The default float32 is what `mo_sum_acc` uses and what every
#   gate fixture needs.
def mo_sum_acc.cls(cls: S.Cls, +dt: S.Dt) -> S.Dt:
  match cls:
    case S.CUint{}: F.least_upper.of(dt, S.uint32())
    case S.CSint{}: F.least_upper.of(dt, S.int32())
    case S.CBool{}: F.least_upper.of(dt, S.int32())
    case _: F.least_upper.of(dt, S.single())

def mo_sum_acc(+dt: S.Dt) -> S.Dt: mo_sum_acc.cls(S.Dt.cls(dt), dt)

# `dtypes.f16 | bfloat16 | *fp8s` -- reduce.py:45's trailing cast test. The fp8
# arms are `S.CFloat` at 8 bits, so the bit width is the discriminator.
def mo_downcast(+dt: S.Dt) -> Bool:
  Bool.or(D.md_dt_eq(dt, S.half()), Bool.or(D.md_dt_eq(dt, S.bfloat16()), U32.is_eq(S.Dt.bits(dt), 8)))

# ===========================================================================
# `promote` -- elementwise.py:29-33, and it is HERE rather than `E.ew_promote`
# because of W9: `ew_promote.b` (elementwise.bend:245) threads the pre-remint
# arena, so its int-CONST path builds a self-referential node. This is
# `elementwise.py`'s three arms with the arena threaded correctly, and `mo_weakconst`
# is its `t.dtype in dtypes.weaks and t._uop.base.op is Ops.CONST` test spelled as
# the two `Bool`s the caller passes in (rule 1).
#
#   `t._uop.base.is_invalid`                 -> return t
#   `weaks AND base.op is CONST`             -> the remint arm
#   `t.dtype == weak_dtype(out_dtype)`       -> return t
#   otherwise                               -> `t.cast(out_dtype)`
# ===========================================================================

def mo_weakconst.cls(cls: S.Cls, +isc: Bool) -> Bool:
  match cls:
    case S.CWeakInt{}: isc
    case S.CWeakFloat{}: isc
    case _: False{}

def mo_weakconst(+fx: F.Folded, +t: T.Tensor) -> Bool:
  mo_weakconst.cls(S.Dt.cls(W.wk_dt(fx, T.Tensor.u(t))), E.ew_is_const(fx, E.ew_base(fx, T.Tensor.u(t))))

# THE SAME NODE IN A NEWER ARENA, and it is one line. Every def here that is HANDED a
# fold (`mo_promote`, `mo_remint`) re-wraps its answer in `F.Folded.ar(fx)` rather than
# handing back the tensor it was given, because `wk_cast_at` answers a same-dtype cast
# with `Found{md_ar(fx), self}` and a fold is the only handle a caller has on the arena
# that must be current. Python has no equivalent because it has no arenas; here the
# difference is a graph or a NOOP, and it was measured six times before it was fixed.
def mo_arena(+ar: O.Arena, +t: T.Tensor) -> T.Tensor: T.tn_new(ar, T.Tensor.u(t))

# the remint arm, with the arena rule (rule 2). `E.ew_remint` builds in the arena it
# is GIVEN and returns the GROWN one; the only thing this has to add is to hand
# `O.Found.ar(f)` on instead of `F.Folded.ar(fx)`, which is the whole of W9's fix.
def mo_remint.at(same: Bool, +fx: F.Folded, +t: T.Tensor, +wd: S.Dt) -> T.Tensor:
  match same:
    case True{}: mo_arena(F.Folded.ar(fx), t)
    case _: +f = E.ew_remint(4n, F.Folded.ar(fx), T.Tensor.u(t), wd)
             T.tn_new(O.Found.ar(f), O.Found.i(f))

def mo_remint(+fx: F.Folded, +t: T.Tensor, +wd: S.Dt) -> T.Tensor:
  mo_remint.at(D.md_dt_eq(W.wk_dt(fx, T.Tensor.u(t)), wd), fx, t, wd)


# EVERY ARM RETURNS A TENSOR IN `fx`'s ARENA, and the first arm is `mo_arena` rather
# than `t` for that reason: `mo_promote` is called with a fold of the arena the OTHER
# operand has already grown, and an arm that hands `t` straight back hands back `t`'s
# OLDER arena with it. MEASURED: `mo_eqmul` promotes the `isinf` left-hand side through
# the remint arm (three new nodes) and then promotes the CONST `1`, whose `same` arm
# returns it unchanged with an arena eleven nodes short -- so the `MUL` was interned over
# the `eq` node it was supposed to consume, and `t_lse0` and `t_norm0` both printed an
# empty toposort. `mo_cast_in` is right by construction because `wk_cast_at` builds in
# `md_ar(fx)`.
def mo_promote.at(inv: Bool, wc: Bool, same: Bool, +fx: F.Folded, +t: T.Tensor, od: S.Dt, +wd: S.Dt) -> T.Tensor:
  match inv wc:
    case True{}  _       : mo_arena(F.Folded.ar(fx), t)
    case False{} True{}  : mo_remint.at(same, fx, t, wd)
    case False{} False{} : mo_cast_in(fx, t, od)

def mo_promote(+fx: F.Folded, +t: T.Tensor, +od: S.Dt) -> T.Tensor:
  +wd = W.weak_dtype(od)
  mo_promote.at(F.is_invalid(F.Folded.ar(fx), T.Tensor.u(t)), mo_weakconst(fx, t),
    D.md_dt_eq(W.wk_dt(fx, T.Tensor.u(t)), wd), fx, t, od, wd)

# ===========================================================================
# `_broadcasted` (elementwise.py:24-34) and `_binop` (:36), hoisted because W9 took
# `ew_binop` out of reach for a CONST that needs promoting -- which is EXACTLY what
# `mean`'s `div(denominator)` and `var`'s `div(smax(n-correction, 0))` do, since
# `denominator` is a Python `int`. `reverse=False` is the only arm any caller in this
# range reaches, so `x` is `self` and the swap is not written.
#
#   `y = self.ufix(y)`; `x, y = (self, y) if not reverse else (y, self)`
#   `out_dtype = least_upper_dtype(x.dtype, y.dtype)`; `return promote(x), promote(y)`
# ===========================================================================

# `_binop`'s node, SPELLED rather than `T.tn_alu`d, and for the same reason `mo_const_t`
# is spelled: `T.tn_alu(t, op, srcs)` takes its ARENA from `t` and its src ORDER from
# `[t] ++ srcs`, and the two promotions of a binop make those two arenas DIFFERENT.
# MEASURED: with `T.tn_alu(lhs, op, [rhs])` the node was interned into `lhs`'s arena,
# which is one node short of `rhs`'s, so it OVERWROTE the promoted right-hand operand
# and `MUL` ended up with `src = (BUFFER, MUL)`. The toposort of that graph is one node,
# so `t_min0` printed `1 BUFFER/0`. Passing the arena and the two indices makes the
# order and the arena independent, which is the whole of `UOp(op, src=(lhs, *rhs))`.
def mo_alu2(+ar: O.Arena, lhs: U32, op: O.Op, rhs: U32) -> T.Tensor:
  +f = O.UOp.new(ar, op, [lhs, rhs], O.ANone{}, O.TNone{})
  T.tn_new(O.Found.ar(f), O.Found.i(f))

def mo_alu3(+ar: O.Arena, c: U32, op: O.Op, x: U32, y: U32) -> T.Tensor:
  +f = O.UOp.new(ar, op, [c, x, y], O.ANone{}, O.TNone{})
  T.tn_new(O.Found.ar(f), O.Found.i(f))

def mo_bin_out(+fx: F.Folded, +t: T.Tensor, +y: T.Tensor) -> S.Dt:
  F.least_upper.of(W.wk_dt(fx, T.Tensor.u(t)), W.wk_dt(fx, T.Tensor.u(y)))

# THE FOLD IS TAKEN FROM `y`, NOT FROM A CALLER-SUPPLIED `F.Folded`, and that is the
# whole of the arena rule made unfalsifiable: Python's `_broadcasted` runs INSIDE
# `_binop`, so whatever built the operands has already grown the arena by the time the
# promotion reads a dtype. `+y` is the right-hand operand and is therefore the
# NEWEST node, so its arena is the one a dtype read must come from. The re-fold
# between the two promotions is `elementwise.bend`'s `ew_promo2` restated where W9
# forces a re-implementation.



# `lhs.alu(op, rhs)` is `UOp(op, src=(self, *src))` (tensor.py:116, ops.py:630), so
# `lhs` is `src[0]` -- and `T.tn_alu` puts its FIRST argument there. `t_min0` printed
# `CONST BUFFER MUL` where CPython prints `BUFFER CONST MUL` because of getting this
# backwards, which is the same class of bug as tensor.bend's M15 and is why the gate
# prints the ORDER of the signature and not a set of op names.
def mo_bin(+t: T.Tensor, op: O.Op, +y: T.Tensor) -> T.Tensor:
  +fx = F.folded(T.Tensor.ar(y))
  +od = mo_bin_out(fx, t, y)
  +l = mo_promote(fx, t, od)
  +r = mo_promote(F.folded(T.Tensor.ar(l)), y, od)
  mo_alu2(T.Tensor.ar(r), T.Tensor.u(l), op, T.Tensor.u(r))

# THE CONST-OPERAND HALF OF `_binop`, and it exists for W9. MEASURED: `E.ew_binop`
# with a weakINT constant builds a self-referential node (elementwise.bend:245 threads
# the pre-remint arena), so every `x * (-1)` -- `neg` (elementwise.py:82), and therefore
# `min` (op.py:494), `softmin` (op.py:729) and `var` -- came back as the BUFFER ITSELF.
# A FLOAT constant is not affected (`ew_promo`'s weak arm keeps a weak CONST weak, so
# nothing is minted), which is why `exp` and `where` were right and `neg` was not. So
# this def is `mo_bin` with the CONST interned here, and `t_bin_promote` is the row.
def mo_bin_c(+t: T.Tensor, op: O.Op, v: O.Const) -> T.Tensor:
  mo_bin(t, op, mo_const_t(t, v))

# `neg` (elementwise.py:82) -- `self * (-1)`, and the `-1` is the two's complement pair
# because `H.i64_of_i32` sign-EXTENDS a U32 and `-1` is not a U32 literal. The same
# spelling `elementwise.bend`'s `ew_neg` uses.
def mo_neg(+t: T.Tensor) -> T.Tensor: mo_bin_c(t, O.OpsMUL{}, mo_ki(4294967295))

# THE WHOLE `ew_binop` FAMILY, ON `mo_bin`. `ew_binop` is CORRECT when its left operand's
# promotion mints a node and WRONG when it does not: `ew_promo2`'s weak arm hands `t`
# straight back (elementwise.bend:243), so `Br.l` keeps `t`'s arena, and the `tn_alu`
# at the end of `ew_binop` then interns the node into an arena one node short of the
# right-hand side's and OVERWRITES it. MEASURED: `t_lse0` printed `2 BUFFER/0 REDUCE/1`
# where CPython prints 33 nodes, and the graph had a node whose src was itself. `mo_bin`
# re-wraps the left operand in the right operand's arena (`mo_arena`) and builds with an
# explicit `mo_alu2`, so both orders are right by construction. A float CONST is the
# other case where nothing is minted at all, so those two families are `mo_bin_c`.
def mo_neq(+t: T.Tensor, +y: T.Tensor) -> T.Tensor: mo_bin(t, O.OpsCMPNE{}, y)
def mo_neqc(+t: T.Tensor, v: O.Const) -> T.Tensor: mo_bin_c(t, O.OpsCMPNE{}, v)
def mo_or(+t: T.Tensor, +y: T.Tensor) -> T.Tensor: mo_bin(t, O.OpsOR{}, y)
def mo_add(+t: T.Tensor, +y: T.Tensor) -> T.Tensor: mo_bin(t, O.OpsADD{}, y)
def mo_mul(+t: T.Tensor, +y: T.Tensor) -> T.Tensor: mo_bin(t, O.OpsMUL{}, y)
def mo_maxc(+t: T.Tensor, f: F32) -> T.Tensor: mo_bin_c(t, O.OpsMAX{}, O.CFloat{f})

# `logical_not` -- elementwise.py:57 -- is `self.cast(dtypes.bool).ne(True)`, so it is a
# CAST and a CMPNE and NOT an `Ops.NEG`, and `eq(x)` is `ne(x).logical_not()`
# (elementwise.py:337).
def mo_notb(+t: T.Tensor) -> T.Tensor: mo_neqc(mo_cast_t(t, S.boolean()), O.CBool{True{}})
def mo_eqc(+t: T.Tensor, v: O.Const) -> T.Tensor: mo_notb(mo_neqc(t, v))

# `sub` -- elementwise.py:121-123. `a, b = self._broadcasted(x, reverse)` and then
# `return a.alu(Ops.ADD, -b)`, and the NOTE says "alu, not +: _broadcasted already
# promoted these, and a second promote would cast -b (only a weak CONST is kept weak)".
#
# IT IS SPELLED HERE AND NOT CALLED AS `E.ew_sub` FOR W9'S SECOND HALF, and the reason is
# the same one-word error as in `mo_alu2`: `ew_sub.of` (elementwise.bend:409) ends
# `T.tn_alu(a, Ops.ADD{}, [Tensor.u(b)])` where `a` is `t` UNCHANGED whenever the
# promotion is the identity, and `b = ew_neg(...)` has already grown the arena -- so the
# ADD is interned into an arena one node short and OVERWRITES the negated right-hand
# side, leaving the ADD with `src = (self, ADD)`. MEASURED: `t_softmax0` printed six
# nodes against CPython's fifteen, with the REDUCE missing from it.
def mo_sub(+t: T.Tensor, +y: T.Tensor) -> T.Tensor:
  +od = mo_bin_out(F.folded(T.Tensor.ar(y)), t, y)
  +a = mo_promote(F.folded(T.Tensor.ar(y)), t, od)
  +b = mo_neg(mo_promote(F.folded(T.Tensor.ar(y)), y, od))
  mo_alu2(T.Tensor.ar(b), T.Tensor.u(a), O.OpsADD{}, T.Tensor.u(b))

# `where(x, y)` -- elementwise.py:436-437. `x, y = self.ufix(x)._broadcasted(y)` and
# then `self.alu(Ops.WHERE, x, y)`. TWO ASYMMETRIES ARE LOAD-BEARING: the CONDITION is
# `self` and is NOT promoted, and only the SECOND operand is promoted -- and it is
# promoted against `x`, not against `self`. It is also spelled here rather than called
# as `E.ew_where` for the stale-arena reason `mo_sub` carries.
def mo_where(+t: T.Tensor, +x: T.Tensor, v: O.Const) -> T.Tensor:
  +k = mo_const_t(t, v)
  +b = mo_promote(F.folded(T.Tensor.ar(k)), k, mo_bin_out(F.folded(T.Tensor.ar(k)), x, k))
  mo_alu3(T.Tensor.ar(b), T.Tensor.u(t), O.OpsWHERE{}, T.Tensor.u(x), T.Tensor.u(b))

# `least_upper_dtype` is `F.least_upper.of` -- fold.bend's own lattice, the same one
# `promote`'s sibling `_broadcasted` reads, so it is a CALL.

# ===========================================================================
# THE MOVEMENT DISPATCH, hoisted. `mixin/movement.py`'s `_mop` is `ops.py:821`, and
# `tensor.bend` already hoisted it as `T.tn_mop` with its own notice -- so this file
# does NOT re-hoist it. What `movement.py` adds on top of `_mop` is the IDENTITY TEST
# on every one of its wrappers, and those tests are what this block ports, because a
# port that skipped them builds a RESHAPE where Python hands back `self` and every
# signature moves.
#
# THE ARENA RULE, SPELLED ONCE AND THEN NEVER AGAIN (rule 2): a def that BUILDS takes
# `+t: T.Tensor` and NOT a caller-supplied `+fx: F.Folded`, and it reads
# `F.folded(T.Tensor.ar(t))` itself. Python's mixins read `self.dtype` from a live
# tensor, so the fold and the node can never disagree; a Bend `Folded` is a separate
# value and WILL disagree the moment anything between the two grows the arena. Every
# one of the six bugs this file hit on the way to compiling was exactly that, and
# every one of them printed `NOOP/0` or a plausible-looking small number.
# ===========================================================================

# THE `List<&2, O.Sint>` IMAGE OF A SHAPE ARG, and it is here for a MEASURED reason.
# `mo_reshape`'s identity test is `ret.shape == self.shape` (movement.py:185), and the
# obvious spelling asks the fold for `ret`'s shape -- which does NOT always answer.
# MEASURED on bend 2.0.34: `fold.bend`'s `reshape_ds` (:1537) answers a RESHAPE whose
# shape arg is a STACK and does NOT answer one whose shape arg is a BARE CONST, and a
# one-element shape arg is a bare CONST (`tn_shape_arg.n`'s middle arm, tensor.bend:590).
# So `mo_dims` over `RESHAPE(REDUCE, CONST(1))` answers `Nil{}`, the identity test sees
# `() == ()`, and EVERY KEEPDIM REDUCE SILENTLY LOSES ITS RESHAPE -- `t_sum0kd` printed
# two nodes where CPython prints four, and nothing else in the file said so.
#
# The fix is BETTER than the fold, not a workaround: the shape being compared is the
# one THIS DEF BUILT, so it is already a `List<&2, O.Const>` and only the SOURCE's shape
# has to come from the fold. `mo_sints` is that one projection and no fold call is
# dropped -- `mo_dims` is still the source's shape, which the fold always answers for
# the nodes these recipes build.
def mo_sints.go(+ds: List<&2, O.Const>, acc: List<&2, O.Sint>) -> List<&2, O.Sint>:
  match ds:
    case Nil{}: acc
    case c <> t: mo_sints.go(t, List.append(&2, O.Sint, acc, [F.sint_of(H.lo32(mo_c_i64(c)))]))

def mo_sints(+ds: List<&2, O.Const>) -> List<&2, O.Sint>: mo_sints.go(ds, Nil{})

def mo_reshape.pick(same: Bool, +t: T.Tensor, +made: T.Tensor) -> T.Tensor:
  match same:
    case True{}: t
    case _: made

def mo_reshape(+t: T.Tensor, +ds: List<&2, O.Const>) -> T.Tensor:
  +n = T.tn_mop(T.Tensor.ar(t), T.Tensor.u(t), O.OpsRESHAPE{}, T.ADims{ds})
  +made = T.tn_new(O.Found.ar(n), O.Found.i(n))
  mo_reshape.pick(F.eq_sints(mo_sints(ds), mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))), t, made)

# `permute` -- movement.py:214. `order_arg != tuple(range(self.ndim))` is `O.eq_u32`
# against `range(ndim)` -- one call, and `ops.bend`'s own list equality rather than a
# second hand-written walk. It needs no fold at all, because the test is on the ORDER
# TUPLE and not on a shape.
def mo_permute.pick(isid: Bool, +t: T.Tensor, +ys: List<&2, U32>) -> T.Tensor:
  match isid:
    case True{}: t
    case _: T.tn_new(T.Tensor.ar(t), O.Found.i(T.tn_mop(T.Tensor.ar(t), T.Tensor.u(t), O.OpsPERMUTE{}, T.AOrder{ys})))

def mo_permute(+t: T.Tensor, +ys: List<&2, U32>) -> T.Tensor:
  mo_permute.pick(O.eq_u32(ys, mo_range(mo_ndim(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))), t, ys)

# `squeeze(dim)` -- movement.py:308. `self if not self.ndim or self.shape[dim] != 1
# else self.reshape(self.shape[:dim] + self.shape[dim+1:])`. The two arms are
# `ndim == 0` and `shape[dim] == 1`, so `keep` is their conjunction (rule 1).
#
# THE WALK IS `tensor.bend`'s `tn_rop.ne1` SHAPE and not a nested match: the self-call
# is the FIRST argument and the per-element choice is a `Bool.pick` over the `+`
# ACCUMULATOR, because `U32.is_eq(i, dim)` is a call and a `match` may not scrutinise
# one (rule 1). `Bool.pick` is strict, so the appended branch is built and discarded
# when `i == dim`; that costs a CONST and is what makes the walk terminate.
def mo_squeeze.go(+ds: List<&2, O.Sint>, +dim: U32, +acc: List<&2, O.Const>) -> List<&2, O.Const>:
  match ds:
    case Nil{}: acc
    case c <> +t: mo_squeeze.go(t, dim,
      Bool.pick(List<&2, O.Const>, U32.is_eq(mo_at(ds, t), dim), acc,
        List.append(&2, O.Const, acc, [mo_ki(mo_dim_u32(c))])))

def mo_squeeze_dims(+t: T.Tensor, +dim: U32) -> List<&2, O.Const>:
  mo_squeeze.go(mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)), dim, Nil{})

def mo_squeeze.pick(keep: Bool, +t: T.Tensor, +dim: U32) -> T.Tensor:
  match keep:
    case True{}: t
    case _: mo_reshape(t, mo_squeeze_dims(t, dim))

# THE TEST IS NEGATED, and movement.py:308 reads `return self if not self.ndim or
# self.shape[dim] != 1 else self.reshape(...)`. MEASURED: reading it the other way round
# made `squeeze` the IDENTITY on a shape-(1,) source -- which is the shape `_softmax` and
# `logsumexp` hand it -- and `t_lse0` printed 31 nodes against CPython's 33, missing
# exactly `STACK/0 RESHAPE/2`.
def mo_squeeze(+t: T.Tensor, +dim: U32) -> T.Tensor:
  +fx = F.folded(T.Tensor.ar(t))
  mo_squeeze.pick(Bool.not(Bool.or(Nat.is_eq(mo_ndim(fx, T.Tensor.u(t)), 0n),
    U32.is_eq(mo_dim_at(fx, T.Tensor.u(t), dim), 1))), t, dim)

# `_resolve_dim` -- movement.py:81. `return dim + total if dim < 0 else dim`. `neg` is
# the sign and `dim` the magnitude, so there is no I64 to unpack.
def mo_resolve(neg: Bool, +dim: U32, total: U32) -> U32:
  Bool.pick(U32, neg, U32.add(dim, total), dim)

# ===========================================================================
# THE REDUCE DISPATCH, hoisted. `mixin/reduce.py` does not exist as a `.bend` yet,
# so this block is its first four defs, and `tensor.bend` sets the precedent by
# hoisting `_rop` (ops.py:655) as `T.tn_rop`:
#
#   `_reduce` (reduce.py:13-18)
#     self = self.cast(self.commit_dtype())
#     axis = tuple(self._resolve_dim(x) for x in (range(self.ndim) if axis is None ...))
#     if self.ndim == 0: axis = ()
#     ret = self._rop(op, axis)
#     return ret.reshape(1 if i in axis else s ...) if keepdim else ret
#   `sum` (reduce.py:20-45), `prod` (:47-71), `max` (:73-94)
#
# `axis` is ALWAYS CONCRETE here. Every caller in this range passes a Python `int`, so
# `range(self.ndim)` and `make_tuple(axis, 1)` are both a one-element list and the
# `resolve` is `mo_resolve`. `axis is None` reaches `logsumexp` (op.py:654) and `mean`
# (op.py:519), where it is `range(ndim)` -- `mo_ax_all` spells that case, and it is
# `t_meanN` that says the two agree on a 1-D source and `t_mean0_2d` that says they
# do not on a 2-D one.
# ===========================================================================

# THE RESOLVED AXIS, and it is a LIST from here on because Python's `_reduce` makes it
# a tuple on its second line (reduce.py:15) and everything downstream reads the tuple.
# `zero` is `self.ndim == 0` (reduce.py:16) and is the one `Bool` the fold can compute.
def mo_axis0(zero: Bool, +axis: List<&2, U32>) -> List<&2, U32>:
  match zero:
    case True{}: Nil{}
    case _: axis

# `[mo_resolve(neg, axis, ndim)]` -- `make_tuple(axis, 1)` through `_resolve_dim`
# (reduce.py:15, movement.py:81).
def mo_ax(neg: Bool, +t: T.Tensor, +axis: U32) -> List<&2, U32>:
  [mo_resolve(neg, axis, U32.from_nat(mo_ndim(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))))]

# `range(self.ndim)`, which is what `axis is None` means (reduce.py:15).
def mo_ax_all(+t: T.Tensor) -> List<&2, U32>:
  mo_range(mo_ndim(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))

# THE KEEPDIM RESHAPE, `1 if i in axis else s for i,s in enumerate(self.shape)`
# (reduce.py:18). It is `RESHAPE` and the fold answers its shape (fold.bend:1537), so
# `mo_reshape`'s identity test sees the real shapes and `t_sum0kd` is the row. The
# membership test `i in axis` is a `Bool` because a `match` may not scrutinise a call
# (rule 1).
def mo_iaxis.go(axis: List<&2, U32>, +i: U32) -> Bool:
  match axis:
    case Nil{}: False{}
    case a <> rest: Bool.pick(Bool, U32.is_eq(a, i), True{}, mo_iaxis.go(rest, i))

def mo_iaxis(+axis: List<&2, U32>, i: U32) -> Bool: mo_iaxis.go(axis, i)

def mo_keep_one(inaxis: Bool, d: O.Sint) -> U32:
  Bool.pick(U32, inaxis, 1, mo_dim_u32(d))

def mo_keep_ds.go(+ds: List<&2, O.Sint>, +axis: List<&2, U32>, +acc: List<&2, O.Const>) -> List<&2, O.Const>:
  match ds:
    case Nil{}: acc
    case d <> +t: mo_keep_ds.go(t, axis,
      List.append(&2, O.Const, acc, [mo_ki(mo_keep_one(mo_iaxis(axis, mo_at(ds, t)), d))]))

def mo_keep_ds(+t: T.Tensor, +axis: List<&2, U32>) -> List<&2, O.Const>:
  mo_keep_ds.go(mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)), axis, Nil{})

# `_reduce` -- reduce.py:13-18. `self.cast(self.commit_dtype())`, then `_rop`, then the
# keepdim reshape.
# THE KEEPDIM TARGET IS `self.shape`, NOT `ret.shape` (reduce.py:18 reads
# `enumerate(self.shape)`), so the walk runs over the SOURCE and the reshape is applied
# to the RESULT. Passing the result instead is a one-word bug that deletes every
# keepdim reduce, because a reduced shape has no axis left in it to match.
def mo_reduce.keep(kd: Bool, +src: T.Tensor, +r: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  match kd:
    case True{}: mo_reshape(r, mo_keep_ds(src, axis))
    case _: r

def mo_reduce(kd: Bool, +t: T.Tensor, op: O.Op, +axis: List<&2, U32>) -> T.Tensor:
  +fx = F.folded(T.Tensor.ar(t))
  +a = mo_axis0(Nat.is_eq(mo_ndim(fx, T.Tensor.u(t)), 0n), axis)
  +c = mo_cast_t(t, mo_commit_dt(fx, t))
  +n = T.tn_rop(T.Tensor.ar(c), T.Tensor.u(c), op, a)
  mo_reduce.keep(kd, c, T.tn_new(O.Found.ar(n), O.Found.i(n)), a)

# `sum` -- reduce.py:20-45. `self.cast(sum_acc_dtype(self.commit_dtype()) if dtype is
# None else dtype)._reduce(Ops.ADD, axis, keepdim)`, then a cast back to `self.dtype`
# iff the dtype was defaulted AND `self.dtype` is half/bfloat16/fp8. `dtype` is always
# `None` from this range, so the test is `mo_downcast(self.dtype)` and it is passed IN.
def mo_sum.castback(uns: Bool, +t: T.Tensor) -> T.Tensor:
  match uns:
    case True{}: mo_cast_t(t, W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))
    case _: t

def mo_sum(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +uns = mo_downcast(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))
  +c = mo_cast_t(t, mo_sum_acc(mo_commit_dt(F.folded(T.Tensor.ar(t)), t)))
  mo_sum.castback(uns, mo_reduce(kd, c, O.OpsADD{}, axis))

# `prod` -- reduce.py:47-71. `self.cast(dtype if dtype is not None else self.dtype)
# ._reduce(Ops.MUL, axis, keepdim)`; `dtype` is `None` here so the cast is the
# identity, and `E.ew_cast` hands `t` back unchanged when the dtypes agree.
# NOT DEAD, DESPITE READING THAT WAY IN ITS OWN FILE: `mixin/reduce.bend` calls
# it as `M.mo_prod`. The per-file dead-def pruners cannot see that, because they
# read one file; see xdead in the cross-cutting pass's notes.
def mo_prod(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  mo_reduce(kd, t, O.OpsMUL{}, axis)

# `max` -- reduce.py:73-94. `self._reduce(Ops.MAX, axis, keepdim)`, one line, with no
# cast of its own: the `cast(self.commit_dtype())` is `_reduce`'s (reduce.py:14).
def mo_max(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  mo_reduce(kd, t, O.OpsMAX{}, axis)

# ===========================================================================
# THE RECIPES, in `mixin/op.py`'s order. Every one of them is its Python body with
# the calls above in place of the `mixin/reduce.py` / `mixin/movement.py` /
# `mixin/elementwise.py` methods it spells, and each carries the line it ports.
# ===========================================================================

# `reciprocal` -- elementwise.py:820. `self.alu(Ops.RECIPROCAL)`, and `E.ew_reciprocal`
# IS that one line, so this is the CALL -- elementwise.bend's own export, reused.
def mo_recip(+t: T.Tensor) -> T.Tensor: E.ew_reciprocal(t)

# `div` -- elementwise.py:229-259, the `rounding_mode is None` path, with a FLOAT
# right-hand side: `a, b = self._broadcasted(x, reverse)`; `if is_int(a.dtype) or
# a.dtype == bool: a = a.cast(default_float)`; `d = a.alu(Ops.MUL, b.reciprocal())`.
# `a` is always float32 by the time it gets here (`numerator` and `squares` are
# `cast(sum_acc_dtype(...))`), so the int arm is false and the cast is not built --
# which is precisely what the oracle's five-node `t_mean0` says.
# THE ORDER IS `_broadcasted` THEN `reciprocal` (elementwise.py:250-255), so the
# promotion has already lifted the weakint CONST to weakfloat by the time the
# RECIPROCAL is built. MEASURED: taking the reciprocal FIRST printed a `CAST/1` where
# CPython prints none -- `t_mean0` was 6 nodes against CPython's 5 -- because the
# promotion then had to CAST a RECIPROCAL instead of REMINTing a CONST. `mo_bin`'s own
# promotion is the identity on the already-promoted right-hand side, so spelling the
# promotion here is not a second one.
def mo_div(+t: T.Tensor, +c: T.Tensor) -> T.Tensor:
  +b = mo_promote(F.folded(T.Tensor.ar(c)), c, mo_bin_out(F.folded(T.Tensor.ar(c)), t, c))
  mo_bin(t, O.OpsMUL{}, mo_recip(b))

# `x.div(n)` for a Python `int` `n`, which is `mean`'s `denominator` and `var`'s
# `smax(n - correction, 0)`. `ufix` (ops.py:609) turns it into a weakint CONST and
# `promote` lifts it to `weakfloat`, so the node is `MUL(a, RECIPROCAL(const))` -- and
# `t_mean0` printing `REDUCE CONST RECIPROCAL MUL` rather than a `DIV` is the row that
# says so.
def mo_divn(+t: T.Tensor, n: U32) -> T.Tensor:
  mo_div(t, mo_const_t(t, mo_ki(n)))

# `prod([si for si, so in zip(shape, sum.shape) if resolve(si != so)])` (op.py:520,
# :547). The zip keeps the dims whose SIZE CHANGED, which is exactly the dims the
# reduce did not touch, so the walk multiplies `shape[i]` for every `i not in axis`.
# `Bool.pick` is strict and both arms are pure, which is why the multiply is not
# hoisted out -- the same shape `tensor.bend`'s `tn_rop.ne1` uses for its filter.
def mo_reduced.go(+ds: List<&2, O.Sint>, +axis: List<&2, U32>, +acc: U32) -> U32:
  match ds:
    case Nil{}: acc
    case d <> +t: mo_reduced.go(t, axis,
      Bool.pick(U32, mo_iaxis(axis, mo_at(ds, t)), U32.mul(acc, mo_dim_u32(d)), acc))

def mo_reduced(+t: T.Tensor, +axis: List<&2, U32>) -> U32:
  mo_reduced.go(mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)), axis, 1)

# `self.dtype if is_float(self.dtype) else float32` (op.py:518, :545).
def mo_out_dt(float: Bool, +t: T.Tensor) -> S.Dt:
  match float:
    case True{}: W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))
    case _: S.single()

# `mean` -- op.py:496-521.
#     output_dtype = self.dtype if is_float(self.dtype) else float32
#     numerator   = self.cast(sum_acc_dtype(self.commit_dtype())).sum(axis, keepdim)
#     denominator = prod([si for si, so in zip(self.shape, self.sum(axis, keepdim=True).shape)
#                         if resolve(si != so)])
#     return numerator.div(denominator).cast(output_dtype)
def mo_mean(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +od = mo_out_dt(S.Dt.is_float(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))), t)
  +n = mo_sum(kd, t, axis)
  mo_cast_t(mo_divn(n, mo_reduced(t, axis)), od)

# `var` -- op.py:523-549.
#     output_dtype = self.dtype if is_float(self.dtype) else float32
#     squares = (self - self.mean(axis, keepdim=True)).square()
#     n        = prod([si for si, so in zip(shape, squares.sum(axis, keepdim=True).shape)
#                    if resolve(si != so)])
#     numerator = squares.cast(sum_acc_dtype(squares.dtype)).sum(axis, keepdim)
#     return numerator.div(smax(n - correction, 0)).cast(output_dtype)
#
# `smax` is `max` from `tinygrad/helpers.py:65`, so `smax(n - correction, 0)` is
# `max(n - correction, 0)` and the subtraction must SATURATE at 0 rather than wrap --
# Python's `int` is unbounded and a `U32.sub` would turn `0 - 1` into 4294967295. The
# test is a `Bool` parameter because `U32.is_lt` is a call (rule 1).
def mo_n_minus.at(hi: Bool, +cor: U32, +n: U32) -> U32:
  match hi:
    case True{}: U32.sub(n, cor)
    case _: 0

def mo_n_minus(+cor: U32, +n: U32) -> U32: mo_n_minus.at(U32.is_lt(cor, n), cor, n)

def mo_var(kd: Bool, +cor: U32, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +od = mo_out_dt(S.Dt.is_float(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))), t)
  +m = mo_mean(True{}, t, axis)
  +s = E.ew_square(mo_sub(t, m))
  +c = mo_cast_t(s, mo_sum_acc(W.wk_dt(F.folded(T.Tensor.ar(s)), T.Tensor.u(s))))
  +nm = mo_sum(kd, c, axis)
  mo_cast_t(mo_divn(nm, mo_n_minus(cor, mo_reduced(s, axis))), od)

# `var_mean` -- op.py:551-566. `return self.var(axis, keepdim, correction),
# self.mean(axis, keepdim)`. TWO CALLS, and Python evaluates `var` FIRST, so the arena
# order -- and therefore `toposort` order -- is `var`'s nodes then `mean`'s, and
# `mean`'s are already in `var`'s graph because `var` calls it.
# `VarMean` is a two-field `Data` record because a `Data` record cannot hold a `Maybe`
# (gradient.bend's rule 15) and a TUPLE is not a type here.
type VarMean is Data:
  VarMean{v: T.Tensor, m: T.Tensor}

def mo_var_mean(+kd: Bool, +cor: U32, +t: T.Tensor, +axis: List<&2, U32>) -> VarMean:
  VarMean{mo_var(kd, cor, t, axis), mo_mean(kd, t, axis)}

def VarMean.v(x: VarMean) -> T.Tensor:
  match x:
    case VarMean{v, m}: v

def VarMean.m(x: VarMean) -> T.Tensor:
  match x:
    case VarMean{v, m}: m

# `std` -- op.py:568-590. `return self.var(axis, keepdim, correction).sqrt()`.
def mo_std(kd: Bool, +cor: U32, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  E.ew_sqrt(mo_var(kd, cor, t, axis))

# `std_mean` -- op.py:592-607. `return self.std(axis, keepdim, correction),
# self.mean(axis, keepdim)`.
type StdMean is Data:
  StdMean{s: T.Tensor, m: T.Tensor}

def mo_std_mean(+kd: Bool, +cor: U32, +t: T.Tensor, +axis: List<&2, U32>) -> StdMean:
  StdMean{mo_std(kd, cor, t, axis), mo_mean(kd, t, axis)}

def StdMean.s(x: StdMean) -> T.Tensor:
  match x:
    case StdMean{s, m}: s

def StdMean.m(x: StdMean) -> T.Tensor:
  match x:
    case StdMean{s, m}: m

# `normalize` -- op.py:609-628, the `p == 0` arm ONLY (W7).
#     den = self.ne(0).sum(dim, keepdim=True) if p == 0 else ...
#     return self / den.maximum(eps)
# `eps` is `1e-12`, which Bend's lexer does not accept as an F32 LITERAL (`1e-12`
# parses as an identifier), so it is written out: `0.000000000001`.
def mo_eps() -> F32: 0.000000000001

def mo_norm0(+axis: List<&2, U32>, +t: T.Tensor) -> T.Tensor:
  +d = mo_sum(True{}, mo_neqc(t, O.CFloat{0.0}), axis)
  mo_div(t, mo_maxc(d, mo_eps()))

# ===========================================================================
# `exp` -- elementwise.py:511, hoisted because `mixin/elementwise.bend` carries it as
# `TODO(p3) ... exp  -- 1/math.log(2)` and rule 5 MEASURED that an F32 literal is live.
#     self = self.cast(least_upper_float(self.dtype))
#     return self.cast(least_upper_dtype(self.dtype, float32)).mul(1/log(2)).exp2().cast(self.dtype)
# All three casts are the IDENTITY for a float32 source, which is why `t_softmax0`
# prints no CAST at all -- and that is a claim, so `t_exp_cast` is the row that pins
# it against a source that is NOT already float32.
# ===========================================================================
def mo_exp(+t: T.Tensor) -> T.Tensor:
  +a = mo_cast_t(t, F.least_upper_float(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))))
  +b = mo_cast_t(a, F.least_upper.of(W.wk_dt(F.folded(T.Tensor.ar(a)), T.Tensor.u(a)), S.single()))
  mo_cast_t(E.ew_exp2(mo_mul(b, mo_const_t(b, O.CFloat{mo_log2e()}))), W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))

# `log` -- elementwise.py:830. `return self.log2()*math.log(2)`.
def mo_log(+t: T.Tensor) -> T.Tensor:
  +l = E.ew_log2(t)
  mo_mul(l, mo_const_t(l, O.CFloat{mo_ln2()}))

# `isnan` -- elementwise.py:608. `self != self`, and `E.ew_ne(t, ETen{t})` IS that.
def mo_isnan(+t: T.Tensor) -> T.Tensor: mo_neq(t, t)

# `eq(x) * detect_positive` -- one arm of `isinf` (elementwise.py:613).
# THE CONST IS BUILT OFF `eq`, NOT OFF `t`, AND THAT IS THE RULE: `mo_const_t` interns
# into the arena of the tensor it is GIVEN, so it must be given the NEWEST one. MEASURED:
# writing `mo_mul(mo_eqc(t, v), mo_const_t(t, mo_ki(1)))` interned the CONST into `t`'s
# arena -- four nodes stale -- and `t_lse0` printed `1 NOOP/0`.
# THE `1` IS A Python `bool` AND NOT AN `int`: `detect_positive` (elementwise.py:613) is
# a `bool` parameter with the default `True`, so `ufix` makes a BOOL CONST and
# `least_upper_dtype(bool, bool)` is bool -- no promotion, no CAST. Writing `mo_ki(1)`
# made it a weakint CONST, the promote arm CAST the `eq` to weakint, and `t_lse0` printed
# 35 nodes against CPython's 33. MEASURED, and the COUNT is what said so.
def mo_eqmul(+t: T.Tensor, f: F32) -> T.Tensor:
  +eq = mo_eqc(t, O.CFloat{f})
  mo_mul(eq, mo_const_t(eq, O.CBool{True{}}))

# `isfinite` -- elementwise.py:623. `(self.isinf() | self.isnan()).logical_not()`.
# IT TAKES THE ARENA, AND IT RE-WRAPS `t` BEFORE EVERY USE, because the three reads of
# `t` are separated by builds and `mo_const_t` interns into `Tensor.ar` of whatever it
# is handed. MEASURED: `mo_eqmul(t, -inf)` with a seven-node `t` appended its CONST at
# index 7 and OVERWROTE the REDUCE, and `t_lse0` printed `0`. The re-wrap is the whole
# fix and it is why every build in this file is written as a `+` binding.
def mo_isfinite(+ar: O.Arena, +t: T.Tensor) -> T.Tensor:
  +em = mo_eqmul(mo_arena(ar, t), mo_inf())
  +ei = mo_eqmul(mo_arena(T.Tensor.ar(em), t), mo_neginf())
  +inf = mo_add(em, ei)
  mo_notb(mo_or(inf, mo_isnan(mo_arena(T.Tensor.ar(inf), t))))
# `(m if keepdim else m.squeeze(axis))` (op.py:655). `m.squeeze(axis)` reads
# `movement.py:308`, whose `dim` is the ORDINAL, and `axis` is already resolved, so the
# squeeze index is `axis[0]` -- and a one-element axis is the only one that reaches it.
def mo_first(+axis: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, axis, 0n), 0)

# IT TAKES THE ARENA BECAUSE `m` IS OLDER THAN THE `+ lg` THAT PRECEDES IT on
# op.py:655, and every build inside `mo_squeeze` reads `Tensor.ar` of whatever it is
# given. MEASURED: without the parameter the tail's `STACK/0 RESHAPE/2` was interned
# into a thirteen-node arena while the `log()` beside it had already made twenty-eight,
# and `t_lse0` printed `1 NOOP/0`.
def mo_lse.keep(kd: Bool, +ar: O.Arena, +m: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  match kd:
    case True{}: mo_arena(ar, m)
    case _: mo_squeeze(mo_arena(ar, m), mo_first(axis))

# `logsumexp` -- op.py:630-655.
#     m = (mx := self.max(axis, keepdim=True).detach()).isfinite().where(mx, 0)
#     return (self - m).exp().sum(axis, keepdim).log() + (m if keepdim else m.squeeze(axis))
# `isinf` is `self.eq(inf)*detect_positive + self.eq(-inf)*detect_negative`
# (elementwise.py:613) and `eq(x)` is `ne(x).logical_not()` (:337), i.e. `cast(bool)`
# (the identity on a bool) plus a CMPNE -- which is why each `eq` prints TWO CMPNEs and
# not one. The oracle's 33-node `t_lse0` is the measurement.
def mo_logsumexp(+kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +mx = E.ew_detach(mo_max(True{}, t, axis))
  +m = mo_where(mo_isfinite(T.Tensor.ar(mx), mx), mx, O.CFloat{0.0})
  +d = mo_exp(mo_sub(t, m))
  +lg = mo_log(mo_sum(kd, d, axis))
  mo_add(lg, mo_lse.keep(kd, T.Tensor.ar(lg), m, axis))

# `_softmax` -- op.py:657-661.
#     m  = self - self.max(axis=axis, keepdim=True).detach()
#     if dtype is not None: m = m.cast(dtype)
#     e  = m.exp()
#     return m, e, e.sum(axis=axis, keepdim=True)
# `dtype` is `None` from both of its callers, so the `cast` arm is not written. The
# answer is a THREE-armed record because a `Data` record cannot hold a `Maybe`
# (gradient.bend's rule 15) and there is no tuple type here.
type Softmax3 is Data:
  Softmax3{m: T.Tensor, e: T.Tensor, ss: T.Tensor}

# THE FIELD NAMES AND THE `+` LOCALS MUST NOT COLLIDE. A record constructor BINDS its
# own field names, so `Softmax3{m, e, ss}` with locals also called `m` and `e` built the
# record out of the CONSTRUCTOR's binders rather than the locals -- which typechecked,
# ran, and produced a graph with no REDUCE in it. MEASURED: `t_softmax0` printed seven
# nodes against CPython's fifteen and `t_logsoftmax0` printed one. The locals are `mm`
# and `ee` and they are the only place in this file where a name is chosen to avoid a
# collision rather than to describe what it holds.
def mo_softmax3(+t: T.Tensor, +axis: List<&2, U32>) -> Softmax3:
  +md = E.ew_detach(mo_max(True{}, t, axis))
  +mm = mo_sub(t, md)
  +ee = mo_exp(mm)
  Softmax3{mm, ee, mo_sum(True{}, ee, axis)}

# `softmax` -- op.py:663-684. `_, e, ss = self._softmax(axis, dtype)` and then
# `return e * ss.reciprocal()`.
def Softmax3.e(s: Softmax3) -> T.Tensor:
  match s:
    case Softmax3{m, e, ss}: e

def Softmax3.ss(s: Softmax3) -> T.Tensor:
  match s:
    case Softmax3{m, e, ss}: ss

# `e * ss.reciprocal()` -- `mo_alu2` rather than `E.ew_mul` for W9's reason, and with the
# RECIPROCAL BOUND FIRST for `mo_const_t`'s reason: written inline as
# `mo_alu2(Tensor.ar(ss), u(ee), OpsMUL{}, u(mo_recip(ss)))` the arena is read before
# the reciprocal is interned. MEASURED: `t_softmax0` printed eleven nodes against
# CPython's fifteen, missing exactly `REDUCE/1 RESHAPE/2 RECIPROCAL/1 MUL/2`.
def mo_softmax(+t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +sx = mo_softmax3(t, axis)
  +ee = Softmax3.e(sx)
  +ss = Softmax3.ss(sx)
  +r = mo_recip(ss)
  mo_alu2(T.Tensor.ar(r), T.Tensor.u(ee), O.OpsMUL{}, T.Tensor.u(r))

# `log_softmax` -- op.py:686-707. `m, _, ss = self._softmax(axis, dtype)` and then
# `return m - ss.log()`. It is `_softmax`'s `m`, NOT `softmax`'s `e`, which is the one
# line that distinguishes the two, and `t_two_rules` measures the sharing.
def Softmax3.m(s: Softmax3) -> T.Tensor:
  match s:
    case Softmax3{m, e, ss}: m

def mo_log_softmax(+t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +sx = mo_softmax3(t, axis)
  +mm = Softmax3.m(sx)
  mo_sub(mm, mo_log(Softmax3.ss(sx)))

# `softmin` -- op.py:709-729. `return (-self).softmax(axis, dtype)`.
def mo_softmin(+t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  mo_softmax(mo_neg(t), axis)

# `_inverse` -- elementwise.py:391. `-self if self.is_floating_point() else ~self`,
# and `is_floating_point` is `self.dtype.is_float`, which is `S.Dt.is_float`.
def mo_inverse(float: Bool, +t: T.Tensor) -> T.Tensor:
  match float:
    case True{}: mo_neg(t)
    case _: E.ew_bitwise_not(t)

# `min` -- op.py:473-494. `return self._inverse().max(axis=axis,
# keepdim=keepdim)._inverse()`. The two `_inverse`s are what make the signature
# `BUFFER CONST MUL REDUCE MUL` for a float source and `BUFFER CONST XOR REDUCE XOR`
# for an int one -- and a `min` that dropped the OUTER `_inverse` would print 4 nodes
# and still look plausible, so `t_min0` and `t_min0i` are the pair that sees it.
def mo_min(kd: Bool, +t: T.Tensor, +axis: List<&2, U32>) -> T.Tensor:
  +f = S.Dt.is_float(W.wk_dt(F.folded(T.Tensor.ar(t)), T.Tensor.u(t)))
  mo_inverse(f, mo_max(kd, mo_inverse(f, t), axis))

# ===========================================================================
# THE GATE. The printers first, because a def may only call defs declared above it
# and every row below calls these.
#
# `mo_sig` is `tensor.bend`'s `tn_sig` and `ew_sig` SPELLED, not aliased: the two live
# in files this one imports but their `IO(Unit)` printers are gate furniture, and a
# shared printer that lives in the SUBSTRATE cannot print a fixture whose arena came
# from here. The signature is a TOPOSORT with each node's op and src COUNT, and the
# COUNT is the first field of the row so a dropped or duplicated node is visible in
# the same place every time.
# ===========================================================================

def mo_sig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: mo_sig.go(t, ar, String.concat([acc,
      O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u)), " "]))

def mo_sig.of(+ar: O.Arena, i: U32) -> String:
  +xs = O.UOp.toposort(O.Arena.budget(ar), ar, i)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " ", mo_sig.go(xs, ar, "")])

def mo_sig(nm: String, +ar: O.Arena, i: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", mo_sig.of(ar, i)]))

def mo_sig_t(nm: String, +t: T.Tensor) -> IO(Unit):
  mo_sig(nm, T.Tensor.ar(t), T.Tensor.u(t))

# `mo_row` is a Bool row, for the three BEND-ONLY rows that name a refusal rather than
# a graph.
def mo_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# --- the fixtures. CPython's `Tensor([1.,2.,3.,4.], device='PYTHON')` is ONE
# BUFFER node (a `DATA` UOp over the list) and `Tensor([[1.,2.],[3.,4.]])` is that
# buffer RESHAPED, which is `BUFFER CONST STACK/2 RESHAPE/2`. Both spellings are
# measured against CPython's own `toposort` -- see `t_lit1d` and `t_lit2d`.

def mo_buf.arg(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  # slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile,
  # image, buffer, bind_on_realize, val -- ops.bend's `ParamArg`, in its order.
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def mo_buf4(+ar: O.Arena, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{mo_buf.arg(0, 4, dt)}, O.TNone{})

def mo_fx1d() -> T.Tensor:
  +b = mo_buf4(O.Arena.empty(), S.single())
  T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))

def mo_i1d() -> T.Tensor:
  +b = mo_buf4(O.Arena.empty(), S.int32())
  T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))

def mo_fx2d() -> T.Tensor:
  +b = mo_buf4(O.Arena.empty(), S.single())
  +x = T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))
  +r = T.tn_mop(T.Tensor.ar(x), T.Tensor.u(x), O.OpsRESHAPE{}, T.ADims{[mo_ki(2), mo_ki(2)]})
  T.tn_new(O.Found.ar(r), O.Found.i(r))

# --- 1-3: the fixtures themselves, and they are ROWS because a 2-D fixture that
# built the wrong shape would silently change every row below it.

def t_lit1d() -> IO(Unit): mo_sig_t("lit1d", mo_fx1d())
def t_lit2d() -> IO(Unit): mo_sig_t("lit2d", mo_fx2d())

# --- 4-7: the reduce hoist, in `mixin/reduce.py`'s order.

def t_max0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("max0", mo_max(False{}, x, mo_ax(False{}, x, 0)))
def t_sum0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("sum0", mo_sum(False{}, x, mo_ax(False{}, x, 0)))

# `t_rop_gap` is the ONE-SIDED row for `T.tn_rop`'s own refusal. `tn_rop.ne1.of`
# (tensor.bend:827) returns `None` when the fold cannot answer the source's SHAPE, and
# `tn_rop.reduce` then hands `self` back UNCHANGED -- no REDUCE node at all. For a
# BUFFER-rooted and a RESHAPE-rooted source the fold DOES answer it (MEASURED: fold
# fold.bend:1530/1537), so this row is False and prints False; the mutation that
# makes it print True is the one that removes the refusal, and no CPython row can see
# that because CPython never refuses.
def t_rop_gap() -> IO(Unit):
  +b = mo_fx2d()
  +f = T.tn_rop(T.Tensor.ar(b), T.Tensor.u(b), O.OpsADD{}, [1])
  mo_row("rop_gap", O.eq_op(O.Arena.op(O.Found.ar(f), O.Found.i(f)), O.OpsREDUCE{}))

# THE KEEPDIM ROW. `reduce.py:18`'s reshape is `1 if i in axis else s`, and the fold
# answers a RESHAPE's shape (fold.bend:1537), so the identity test in `mo_reshape`
# sees the real shapes. Without keepdim the REDUCE is the last node; with it the
# signature gains `CONST RESHAPE/2` and nothing else, and the COUNT is what says so.
def t_sum0kd() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("sum0kd", mo_sum(True{}, x, mo_ax(False{}, x, 0)))

# --- 8-10: `min`, and the pair that sees the outer `_inverse`.

def t_min0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("min0", mo_min(False{}, x, mo_ax(False{}, x, 0)))

def t_min0i() -> IO(Unit):
  +x = mo_i1d()
  mo_sig_t("min0i", mo_min(False{}, x, mo_ax(False{}, x, 0)))

def t_min0kd() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("min0kd", mo_min(True{}, x, mo_ax(False{}, x, 0)))

# --- 11-15: the mean family. `t_mean0` is the five-node row and it is the one that
# says `div` by a Python `int` is `MUL(x, RECIPROCAL(const))` and NOT a `DIV`.

def t_mean0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("mean0", mo_mean(False{}, x, mo_ax(False{}, x, 0)))

def t_mean0kd() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("mean0kd", mo_mean(True{}, x, mo_ax(False{}, x, 0)))

# `t_meanN` is `axis=None`, which is `range(ndim)` (reduce.py:15). For a 1-D source
# that is `[0]`, so the two rows are the SAME graph -- and printing both is the
# measurement, because a `mean` that read `axis` as given would agree here and
# disagree on the 2-D row.
def t_meanN() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("meanN", mo_mean(False{}, x, mo_ax_all(x)))

def t_mean0_2d() -> IO(Unit):
  +x = mo_fx2d()
  mo_sig_t("mean0_2d", mo_mean(False{}, x, mo_ax(False{}, x, 0)))

# `t_var0`, `t_var0c0` and `t_std0`. `correction=0` is `smax(n - 0, 0)` where
# `smax` is `max` and `min` from `tinygrad/helpers.py`, so the denominator CONST is
# the SAME interned node as `mean`'s -- which is why `var0c0` is 13 nodes and `var0`
# is 15 rather than 17.
def t_var0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("var0", mo_var(False{}, 1, x, mo_ax(False{}, x, 0)))

def t_var0c0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("var0c0", mo_var(False{}, 0, x, mo_ax(False{}, x, 0)))

def t_std0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("std0", mo_std(False{}, 1, x, mo_ax(False{}, x, 0)))

# --- 16-19: the pairs. `var_mean` and `std_mean` return TUPLES, so each gets two
# rows and the two halves are separate toposorts.

def t_varmean0_v() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("varmean0_v", VarMean.v(mo_var_mean(False{}, 1, x, mo_ax(False{}, x, 0))))

def t_varmean0_m() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("varmean0_m", VarMean.m(mo_var_mean(False{}, 1, x, mo_ax(False{}, x, 0))))

def t_stdmean0_s() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("stdmean0_s", StdMean.s(mo_std_mean(False{}, 1, x, mo_ax(False{}, x, 0))))

def t_stdmean0_m() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("stdmean0_m", StdMean.m(mo_std_mean(False{}, 1, x, mo_ax(False{}, x, 0))))

# --- 20-21: `normalize`'s `p == 0` arm (W7) and the `exp`/`log` casts it leans on.

def t_norm0() -> IO(Unit):
  +x = mo_fx2d()
  mo_sig_t("norm0", mo_norm0(mo_ax(False{}, x, 1), x))

# `t_exp_cast` is the row that pins the claim `t_softmax0` makes NEGATIVELY: `exp`'s
# three casts are the identity for a float32 source, so the softmax signature has no
# CAST in it. An int32 source is NOT float32, so `least_upper_float` and
# `least_upper_dtype(_, float32)` both mint a CAST and the row prints one.
def t_exp_cast() -> IO(Unit):
  +x = mo_i1d()
  mo_sig_t("exp_cast", mo_exp(x))

# --- 22-25: the softmax family, and `t_two_rules`.

def t_lse0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("lse0", mo_logsumexp(False{}, x, mo_ax(False{}, x, 0)))

def t_lse0kd() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("lse0kd", mo_logsumexp(True{}, x, mo_ax(False{}, x, 0)))

def t_softmax0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("softmax0", mo_softmax(x, mo_ax(False{}, x, 0)))

def t_logsoftmax0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("logsoftmax0", mo_log_softmax(x, mo_ax(False{}, x, 0)))

def t_softmin0() -> IO(Unit):
  +x = mo_fx1d()
  mo_sig_t("softmin0", mo_softmin(x, mo_ax(False{}, x, 0)))

# THE TWO-RULES-CLAIM-ONE-NODE ROW, and it is the row the brief asks for. `softmax`
# (op.py:663) and `log_softmax` (op.py:686) are TWO defs that both call `_softmax`
# (op.py:657), so the thirteen nodes `_softmax` builds are interned ONCE and the two
# results SHARE them. Both rows below are printed from ONE arena, and the sharing is
# visible in the printed text: the first THIRTEEN op names of `two_rules_lsm` are
# `two_rules_sm` with its last two removed, and the two tails are the difference.
#
#   * a `_softmax` that returned `m` in its `e` slot loses the whole `CONST MUL EXP2`
#     triple -- MEASURED, `softmax` prints 12 and `log_softmax` 15, and the
#     `softmax3_e` row collapses onto `softmax3_m`;
#   * a `_softmax` that forgot `.detach()` drops the `DETACH/1` and both rows lose a
#     node (M13).
#
# AND WHAT THIS ROW CANNOT SEE, which is the half worth writing down: the arena is a
# HASHCONS, so a `_softmax` DUPLICATED -- inlined into both callers, or spelled twice --
# re-interns the very same nodes and the union stays 20. MEASURED: CPython's
# `len({id(u) for u in a} | {id(u) for u in b})` is 20 against 15 + 18, and the arena
# here is 21 slots (`O.Arena.next`, the bottom included) for the same pair, so the
# thirteen are genuinely one object each. That number does not move under duplication,
# so the claim "ONE `_softmax`, called twice" rests on the ARENA not growing -- which
# is a property of `hashcons`, not of the port -- plus `t_softmax3`'s 8/11/13, which
# pin the three outputs as three DISTINCT nodes.
#
# `softmax` prints 15 and `log_softmax` prints 18, and 15 - 13 = 2 and 18 - 13 = 5,
# which is `RECIPROCAL MUL` for one and `LOG2 CONST MUL MUL ADD` for the other.
# BOTH ROWS IN ONE `IO.print`, because a def body is one expression and because the
# POINT of the row is that the two signatures come out of ONE arena -- if they came
# from two, the sharing would not be measured at all.
def t_two_rules.pair(+a: T.Tensor, +b: T.Tensor) -> IO(Unit):
  IO.print(String.concat(["two_rules_sm=", mo_sig.of(T.Tensor.ar(a), T.Tensor.u(a)),
    " two_rules_lsm=", mo_sig.of(T.Tensor.ar(b), T.Tensor.u(b))]))

def t_two_rules() -> IO(Unit):
  +x = mo_fx1d()
  +a = mo_softmax(x, mo_ax(False{}, x, 0))
  +b = mo_log_softmax(x, mo_ax(False{}, x, 0))
  t_two_rules.pair(a, b)

# --- `_softmax`'s THREE OUTPUTS, and they exist because M8 is otherwise invisible.
# `log_softmax` takes `_softmax`'s `m` and `softmax` takes its `e` (op.py:683/:706), and
# inside `log_softmax` alone the choice is UNFALSIFIABLE: `ss = e.sum(axis, keepdim=True)`
# already pulls `e` into the graph, so `m - ss.log()` and `e - ss.log()` have the SAME
# toposort -- same count, same ops, same order. Printing `m` and `e` on their own is what
# makes the difference visible, and it is 8 against 11 against 13.
def t_softmax3.go(+a: T.Tensor, +b: T.Tensor, +c: T.Tensor) -> IO(Unit):
  IO.print(String.concat(["softmax3_m=", mo_sig.of(T.Tensor.ar(a), T.Tensor.u(a)),
    " softmax3_e=", mo_sig.of(T.Tensor.ar(b), T.Tensor.u(b)),
    " softmax3_ss=", mo_sig.of(T.Tensor.ar(c), T.Tensor.u(c))]))

def t_softmax3() -> IO(Unit):
  +x = mo_fx1d()
  +s = mo_softmax3(x, mo_ax(False{}, x, 0))
  t_softmax3.go(Softmax3.m(s), Softmax3.e(s), Softmax3.ss(s))

# --- THE SHAPE ROWS, and they are here for a MEASURED reason. `t_sum0kd` printed the
# right four nodes with `RESHAPE(REDUCE, CONST(4))` where CPython prints
# `RESHAPE(REDUCE, CONST(1))` -- same count, same ops, WRONG SHAPE -- and neither the
# signature nor the count could see it, because the shape arg is a bare CONST and a
# signature prints only `CONST/0`. `mo_at`'s index was off by one (`len(ds) - len(t)`
# where the head sits at `len(t)`) and `sh_sum0kd` is the row that caught it.
#
# A signature cannot print a SHAPE because `O.Arena.arg` of a RESHAPE is a `ShapeArg`
# and printing it means reading the CONST list; these rows therefore print the folded
# shape and the folded dtype of a result, which is what a caller actually consumes.
def mo_shape.go(ds: List<&2, O.Sint>, acc: String) -> String:
  List.foldl(~&2, ~O.Sint, ~String, (a: String) => (d: O.Sint) => String.concat([a, "(", U32.show(mo_dim_u32(d)), ")"]), ds, acc)

def mo_shape.put(nm: String, sh: String, dt: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", sh, " ", dt]))

def mo_shape(nm: String, +fx: F.Folded, +i: U32) -> IO(Unit):
  mo_shape.put(nm, mo_shape.go(mo_dims(fx, i), ""), E.ew_dtnm(mo_dt(fx, i)))

def t_sh_sum0kd() -> IO(Unit):
  +x = mo_fx1d()
  +r = mo_sum(True{}, x, mo_ax(False{}, x, 0))
  mo_shape("sh_sum0kd", F.folded(T.Tensor.ar(r)), T.Tensor.u(r))

def t_sh_mean0() -> IO(Unit):
  +x = mo_fx1d()
  +r = mo_mean(False{}, x, mo_ax(False{}, x, 0))
  mo_shape("sh_mean0", F.folded(T.Tensor.ar(r)), T.Tensor.u(r))

def t_sh_lse0() -> IO(Unit):
  +x = mo_fx1d()
  +r = mo_logsumexp(False{}, x, mo_ax(False{}, x, 0))
  mo_shape("sh_lse0", F.folded(T.Tensor.ar(r)), T.Tensor.u(r))

def t_sh_lse0kd() -> IO(Unit):
  +x = mo_fx1d()
  +r = mo_logsumexp(True{}, x, mo_ax(False{}, x, 0))
  mo_shape("sh_lse0kd", F.folded(T.Tensor.ar(r)), T.Tensor.u(r))

def t_sh_norm0() -> IO(Unit):
  +x = mo_fx2d()
  +r = mo_norm0(mo_ax(False{}, x, 0), x)
  mo_shape("sh_norm0", F.folded(T.Tensor.ar(r)), T.Tensor.u(r))

# --- the four BEND-ONLY rows.

# `t_commit_weak` -- rule 4. `commit_dtype` (tinygrad/dtype.py:16) REFUSES a weakint node
# because `UOp._min_max` (ops.py:1104) is not ported, so `mo_commit_dt` hands back the
# node's OWN dtype and `_reduce`'s `cast` (reduce.py:14) is the identity. The row says
# so from the arena rather than from a comment: a weakint node's committed dtype is
# weakint.
def t_commit_weak() -> IO(Unit):
  +b = mo_buf4(O.Arena.empty(), S.single())
  +x = T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))
  +c = mo_const_t(x, mo_ki(3))
  mo_row("commit_weak", D.md_dt_eq(mo_commit_dt(F.folded(T.Tensor.ar(c)), c), W.wk_dt(F.folded(T.Tensor.ar(c)), T.Tensor.u(c))))

# `t_bin_promote` -- W9. `mo_promote` is `elementwise.py:29-33` with the arena threaded
# correctly, and this row is the ONE that says so. It is FOUR-SIDED: each of the two
# arms that are spelled "return `t`" is checked twice, once for the NODE it returns and
# once for the ARENA it returns it in. CPython cannot be asked for either answer -- Python
# has no arenas -- so this is a BEND-ONLY row and it is labelled as one.
#
# THE ORDER IS THE WHOLE ROW. `iv` is interned FIRST, so every node after it lands in a
# strictly NEWER arena and each fold handed to `mo_promote` is newer than the operand it
# is asked to promote -- which is the only situation in which `mo_arena` does anything.
#
# MEASURED, and it is why the order is written down rather than left to taste: built the
# other way round, `iv` was interned inline as
# `T.tn_new(T.Tensor.ar(x), O.Found.i(O.Uop.const(T.Tensor.ar(x), O.CInvalid{})))`, which
# reads `Tensor.ar(x)` BEFORE the CONST exists (the rule at `mo_const_t`), so the arena
# never grew -- `next=2` before and after, `is_invalid=False`, `Arena.op(.,2)` = the
# NOOP bottom -- the `is_invalid` arm was never taken at all, and the row passed while
# testing nothing. Via `mo_const_t` the same fixture reads `next=3 inv=True`, and the
# mutation that drops the re-wrap from that arm (M10) moves. A row that reads as
# coverage and is not is worse than no row.
def t_bin_promote() -> IO(Unit):
  +b = mo_buf4(O.Arena.empty(), S.single())
  +x = T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))
  +iv = mo_const_t(x, O.CInvalid{})
  +c = mo_const_t(iv, mo_ki(3))
  # `pi` is the `is_invalid` arm (:29) on an arena one node older than its fold,
  # `pw` the weak-CONST arm (:30) on one older than its own.
  +pi = mo_promote(F.folded(T.Tensor.ar(c)), iv, S.single())
  +pw = mo_promote(F.folded(T.Tensor.ar(pi)), c, S.single())
  mo_row("bin_promote", Bool.and(
    Bool.and(U32.is_eq(T.Tensor.u(pi), T.Tensor.u(iv)),
             U32.is_eq(O.Arena.next(T.Tensor.ar(pi)), O.Arena.next(T.Tensor.ar(c)))),
    Bool.and(Bool.not(U32.is_eq(T.Tensor.u(pw), T.Tensor.u(c))),
             U32.is_gt(O.Arena.next(T.Tensor.ar(pw)), O.Arena.next(T.Tensor.ar(c))))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_lit1d()
    b : Unit <- t_lit2d()
    c : Unit <- t_max0()
    d : Unit <- t_sum0()
    e : Unit <- t_sum0kd()
    f : Unit <- t_rop_gap()
    g : Unit <- t_min0()
    h : Unit <- t_min0i()
    i : Unit <- t_min0kd()
    j : Unit <- t_mean0()
    k : Unit <- t_mean0kd()
    l : Unit <- t_meanN()
    m : Unit <- t_mean0_2d()
    n : Unit <- t_var0()
    o : Unit <- t_var0c0()
    p : Unit <- t_std0()
    q : Unit <- t_varmean0_v()
    r : Unit <- t_varmean0_m()
    s : Unit <- t_stdmean0_s()
    u : Unit <- t_stdmean0_m()
    v : Unit <- t_norm0()
    w : Unit <- t_exp_cast()
    x : Unit <- t_lse0()
    y : Unit <- t_lse0kd()
    z : Unit <- t_softmax0()
    aa : Unit <- t_logsoftmax0()
    ab : Unit <- t_softmin0()
    ac : Unit <- t_two_rules()
    ad : Unit <- t_commit_weak()
    ad2 : Unit <- t_softmax3()
    ae : Unit <- t_sh_sum0kd()
    af : Unit <- t_sh_mean0()
    ag : Unit <- t_sh_lse0()
    ah : Unit <- t_sh_lse0kd()
    ai : Unit <- t_sh_norm0()
    t_bin_promote()

# ===========================================================================
# SIDE B's SECTION GOES BELOW THIS LINE.
# ===========================================================================