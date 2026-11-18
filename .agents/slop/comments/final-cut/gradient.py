import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/gradient.bend"

EDITS = [
  # ---- THE HEADER (39 lines) -> 14: what the file is, the ONE measured fact that shapes the
  # file (`dest` bound TWICE), and the answer's SHAPE.
  (1, 39, """# mixin/gradient.bend -- tinygrad/mixin/gradient.py. `pm_gradient` (the reverse-mode rule
# table) and `compute_gradient` (the walk that drives it).
#
# THE ONE MEASURED FACT IN THIS HEADER, and it is the reason the file exists in this shape:
# `mixin/gradient.py:101` binds the name `dest` TWICE.
#     (UPat(Ops.AFTER, src=(UPat(name="dest"), UPat(Ops.STORE, src=(UPat(name="dest"), UPat())))),
#      lambda ctx,dest: (None, ctx)),
# `dest` is `AFTER.src[0]` AND `AFTER.src[1].src[0]`, two different positions, so the rule
# matches only when they are the SAME node. `upat.py:100-105` emits the identity compare as
# an ordinary clause (`"{0} is {1}"`), and the interpreter states the same constraint as a
# store rejection. Without the check the rule matches strictly more nodes than Python does,
# and it still typechecks and still runs -- so it is LOAD-BEARING, not decorative. `gr_28`
# emits it; the `rebind`/`rebind_off` gate rows are the two-sided check, and `gr_29_nocheck`
# is the mutation that proves it. THE TAG SPACE is Python's own: 0..32 in `pm_gradient.pdict`
# insertion order, which is the compiled form (`UPAT_COMPILE=1` is the default, ops.py:1583).
# Tag 29 is the rebind, tags 27/28/30 are its AFTER siblings, and `t_claims` pins the COUNT.
#
# THE SHAPE OF A RULE'S ANSWER. Python's rule bodies return `tuple[UOp|None, ...]` and
# `rewrite` returns the FIRST non-`None`. Two facts follow: a rule that does not match
# returns `None` and the scan CONTINUES -- that is `O.Verdict`'s `VSkip`, a first-wins fold
# exactly as in `spec.bend`; and a rule that matches returns a list with `None` HOLES (`CMPLT`
# is `(None,None)`, `STORE` is `(None, ctx)`), and a hole is not a skip. So the answer is a
# `Data` record with a `List` field, not a `Maybe` of a list. `GFired{gs, ar}` is "matched,
# here are the per-src gradients" and `GSkip{}` is "no opinion, keep scanning". The `ar` field
# is the arena AFTER the rule grew it, because a gradient rule BUILDS nodes. `gs` uses index 0
# for a hole: index 0 is the arena's bottom node (`Arena.empty` spends it, ops.bend:1377
# symbol=Arena.empty) and `UOp.is_none(u) = U32.is_zero(u)` (ops.bend:1376 symbol=UOp.is_none),
# so 0 IS tinygrad's own "no uop" and the encoding is not an invention."""),

  # ---- the folded literals -- TWO PARAGRAPHS, the second one is the `-inf` SPELLING, which is
  # a DIFFERENCE and stays; the first is the promotion fact.
  (117, 128, """# the folded literals are bare CONSTs and that is not an omission. `UOp.const(v)` with
# NO dtype is `CFloat{v}` -> weakfloat and the `.cast(dtype)` at ops.py:632 is against `None`,
# so no CAST is built. Measured: `(math.pi/2 - c)` is `ADD(CONST, MUL(...))` where the CONST's
# dtype is `weakfloat` and the MUL's is `float` -- the promotion happens at the BINARY, not at
# the literal. `gconst` (which adds the CAST) is for `const_like`, which passes ctx's dtype
# EXPLICITLY. `sin_n` (10) and `log2_n` (8) are the rows.
# `-math.inf` -- gradient.py:77 `ret.const_like(-math.inf)`. There is no `inf` LITERAL in Bend
# (`-1.0e400` is a parse error, "expected : a term, observed : '-'"), and an f32 OVERFLOW is
# the honest way to spell it: `1e30 * 1e30` is `0x7F800000`, which IS f32 `+inf`
# (helpers.bend's `f32_exp_all_ones` reads exactly that bit pattern), and the negation is
# `-inf`. Measured, and `k_neginf_bits` below is the row that says so."""),

  # ---- the ints and the floats -- the LAST paragraph is the reason and it is the fact.
  (133, 141, """# the ints and the floats are different nodes, and this is load-bearing rather than
# pedantic. A CONST's dtype FOLLOWS its value (ops.py:632 `dtype or dtypes.from_py(b)`), so
# `UOp.const(0)` is `CInt{0}` -> weakint and `UOp.const(0.0)` is `CFloat{0.0}` -> float32.
# `least_upper(weakint, float32)` is float32 and not weakint, so a rule that folds the wrong
# one produces a gradient whose dtype -- and therefore whose value at the next node -- differs.
# Python's fold is dtype-INDEPENDENT (`const_like(0)` at a float ctx is `CFloat{0.0}`;
# `where(0, ctx)` at a float ctx is the same node), and the rules that need a genuine INT 0 are
# `TRUNC`'s and `MAX`'s `const_like(0)`, which are ctx-dtype CONSTs."""),

  # ---- the DEAD gbool def -- a BUG THAT WAS FOUND (a def claiming a CPython expression with no
  # caller). Keep that one sentence; the `UOp.const` paragraph is a separate fact.
  (183, 199, """# `mask.cast(dtypes.bool)` from `partial_store_gradient` (gradient.py:63) is NOT reached by
# any caller in this file. A `gbool` def once sat here and NOTHING called it (`grep -rn gbool`
# = this file only), so a def claiming a CPython expression with no caller is a claim of
# unknown value.
# `UOp.const(v)` -- ops.py:632. THE CAST IS NOT OPTIONAL, and this is MEASURED rather than
# read off:
#
#     return UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)
#
# so a CONST at a CONCRETE dtype is the TWO nodes `CAST(CONST)`, and only the three dtypes a
# CONST derives (bool/weakint/weakfloat) fold the cast away. Measured: `UOp.const(0.0,
# dtypes.f32)` has `op=CAST, nsrc=1` while `UOp.const(0.0, dtypes.weakfloat)` has `op=CONST,
# nsrc=0`. Every `const_like` in a rule body folds at `ctx.dtype`, which for the ALU rules is
# a CONCRETE float32, so every one emits a CAST pair -- which is why `trunc_n` is 2 and not 1."""),

  # ---- the `src[1]` order -- a CIRCULAR IMPORT, which IS a WEIRD, and the COPY is the point.
  (202, 213, """# THE ORDER AS A `src[1]` -- UPSTREAM's `_mop` (ops.py:784,790-791) BUILDS A PERMUTE AS
# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)`, AND `usrcs` IS
# `[shape_to_shape_arg(order)]` -- AND `shape_to_shape_arg` (ops.py:108-112) IS A `STACK` OF
# INTERNED CONSTs OR, FOR A LENGTH-1 ORDER, A BARE CONST.
#
# AND THIS IS A LOCAL COPY OF `mixin/movement.bend`'s `G.stkN`, AND THE COPY IS THE POINT:
# `mixin/gradient.bend` CANNOT IMPORT `mixin/movement.bend`, BECAUSE `mixin/movement.bend`
# IMPORTS `tensor.bend` AND `tensor.bend` IMPORTS `mixin/gradient.bend` -- AND A CIRCULAR
# IMPORT IS A COMPILE ERROR, SO THE HELPER IS HERE AND NOT SHARED."""),

  # ---- `neg` IS NOT Ops.NEG -- a DIFFERENCE, measured. Keep it whole.
  (258, 264, """# `neg` IS NOT `Ops.NEG`, and this is measured against the tree rather than read off.
# `elementwise.py:74-76` defines `neg` as `alu(Ops.NEG)`, but by the time a gradient rule sees
# the node the symbolic rules have rewritten NEG away: `UOp.const(1.0).neg()` has `op=MUL` with
# srcs `(CONST(1.0), CONST(-1.0))`, and Python's tree for the `RECIP` gradient (gradient.py:68
# `-ctx * ret * ret`) shows exactly that -- MULs and two `CONST(-1.0)`, no NEG anywhere.
# `Ops.NEG` exists in the enum and `schedule/` lowers it; emitting it here would build a graph
# Python never builds."""),

  # ---- the eq/ne/logical_not family -- a BUG THAT WAS FOUND (the OLD comment was written
  # against an OLDER upstream). Keep the measurement and the fact.
  (292, 315, """# THE `eq`/`ne`/`logical_not` FAMILY AT THE PIN, AND THE OLD COMMENT HERE WAS WRITTEN
# AGAINST AN OLDER UPSTREAM. MEASURED AT THE PIN `f5ac54685074`:
#
#   `tinygrad/mixin/elementwise.py:335-336`  `eq` IS `return self._binop(Ops.CMPEQ, x, False)`
#     -- ONE NODE, AND IT IS `CMPEQ`, AND THE OLD CLAIM "no elementwise.py method emits
#     [Ops.CMPEQ]" IS FALSE AT THE PIN.
#   `tinygrad/mixin/elementwise.py:332-333`  `ne` IS `self.eq(x).logical_not()`
#   `tinygrad/mixin/elementwise.py:49-57`    `logical_not` IS `self.cast(dtypes.bool).eq(False)`
#
# AND UPSTREAM's OWN GRADIENT AT THE PIN CONFIRMS IT INDEPENDENTLY:
# `tinygrad/mixin/gradient.py:12` IS `mask = ret.src[0].eq(ret).cast(...)`, `:16` IS
# `is_zero:=(x:=ret.src[0]).eq(0)`, `:78` IS `(x.eq(y)).where(ctx, ...)`, AND `:73` IS
# `(UPat((Ops.CMPLT, Ops.CMPEQ)), lambda: (None, None))` -- NO `CMPNE` ANYWHERE IN THE MAX OR
# POW GRADIENT."""),

  # ---- `x / y` IS NOT AN FDIV -- a DIFFERENCE, measured. Keep it whole.
  (342, 353, """# `x / y` IS NOT AN `FDIV` NODE, and this is the most surprising fact in the arithmetic of
# this file. `div` (elementwise.py:229-259) is
#
#     if is_int(a) and is_int(b): ...TRUNCDIV / DIV...
#     if is_int(a.dtype) or a.dtype is bool: a = a.cast(dtypes.default_float)
#     d = a.alu(Ops.MUL, b.reciprocal())
#
# so for two FLOATS it is `MUL(x, RECIP(y))` -- TWO nodes -- and `Ops.FDIV` is never emitted by
# `div` at all. Measured against Python: the `LOG2` gradient is `MUL, RECIP, MUL, CONST, CONST`
# and the `SQRT` gradient is `MUL, RECIP, MUL, SQRT, CONST, CONST`; neither contains an FDIV.
# `gradient.py:70` (`ctx / (...)`) and `:72` (`ctx / (ret*2)`) are the only `/` users."""),

  # ---- THE RULES -- the pattern-vs-body division is the fact.
  (359, 369, """# THE RULES. One def per tag, in `pm_gradient.pdict` order, each carrying its
# `gradient.py` line. A rule takes `+ar` (it may grow the arena), `ctx` (the incoming
# gradient -- `gradient.py:65` "ctx is grad_output") and `self` (the node being
# differentiated), and answers a `GRes`.
#
# A rule that does not match its pattern answers `GSkip{}`, and `rewrite` keeps scanning.
# Which tests belong to the PATTERN (and therefore to `gr_try`) and which belong to the BODY is
# Python's own division and it is preserved exactly: the compiled form puts every pattern
# conjunct in the `if`, and `_get_clause` (upat.py:158) emits `(_ret:=_fxn(...)) is not None`
# last. So `nsrc` tests and op tests are PATTERN tests, and a `const_like` or a shape
# computation is BODY work that happens after a match."""),

  # ---- rule 0 CAST -- the LAST TWO PARAGRAPHS ARE THE SAME FACT TWICE (the `ADt` arg is
  # `ret.src[0].dtype`).
  (372, 384, """# --- 0. CAST -- gradient.py:67. `(ctx.cast(ret.src[0].dtype),)`
#
# `ret.src[0].dtype` is a FOLD read (`UOp.dtype` is `recursive_property`, ops.py:225), so this
# is the ONE rule in the table that needs the fold rather than just the arena.
# `mixin/dtype.bend`'s `md_dt` is that reader and it is exactly what Python asks, so it is
# IMPORTED, not recopied -- and importing it costs this file nothing, because
# `mixin/dtype.bend` prints no foreign-code notice (`md_dt_imported` in ITS gate is the row,
# and it says so).
# The `ADt` arg is `ret.src[0].dtype` -- `ret` is the CAST, so this is the dtype of the node
# BELOW it, which for a CONST is that CONST's own natural dtype and NOT `ret.arg`.
# `F.fold.dt` is that read; ops.py:225 makes `dtype` a `recursive_property`, and fold.bend is
# the well-founded way to answer it here."""),

  # ---- rule 10 POW -- the LAST PARAGRAPH is a BUG THAT WAS FOUND (the split into zero/zcast/
  # zbare) and it stays; the middle is the measurement.
  (515, 533, """# --- 10. POW -- gradient.py:76-77.
#   (ctx * e.eq(0).where(e, e*b.pow(e-1)),
#    ctx * b.eq(0).where((e<0).where(ret.const_like(-math.inf), 0), ret*b.log2()*math.log(2.0)))
#
# The most complex rule in the table, and the one with the most nodes. Both halves are the
# standard f'(x^e) with the DEGENERATE cases pinned: d/dx x^0 = 0 needs the `e.eq(0)` branch
# to hand back `e` itself (which is 0), and d/de x^0 = x^0 * ln(x) needs the `b.eq(0)` branch
# to answer `-inf` when `e<0` and `0` otherwise. The `0` there is `k_fzero` and the `-inf` is
# `k_neginf`.
#
# `pow_n0`/`pow_n1` pin the tree SIZE -- 24 for `dx` and 29 for `de`, CPython's own numbers --
# because a rule that dropped a factor or a guard would still answer a VALUE (wrongly) and
# only the count would move.
# the zeros are all one bare node. `e.eq(0)`, `e < 0` and `where`'s untaken `0` all take the
# WEAK literal that `UOp.const(0)` derives (ops.py:632), so all three are the SAME interned
# `CONST/0` at `weakfloat` -- NOT a `CAST(CONST)`. MEASURED against CPython's own
# `pm_gradient` tree. An earlier revision split them into `zero` (cast), `zcast` (cast) and
# `zbare` (bare); Python makes no such distinction."""),

  # ---- rule 11 MAX -- the LAST TWO PARAGRAPHS ARE A BUG THAT WAS FOUND (the port built four
  # WHEREs and three CMPNEs, and the count rows could not see it). KEEP IT.
  (583, 612, """# --- 11. MAX -- gradient.py:78-79.
#   ((x>y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)),
#    (x<y).where(ctx, (x.eq(y)).where(ctx * 0.5, 0)))
#
# The gradient of a max goes to the larger argument; a TIE splits it evenly, which is the
# `ctx * 0.5` and is why `max_tie` is a separate gate row from `max_gt`.
#
# * `(x>y)` and `(x<y)` are the same op with the operands swapped, and only the outer ONE IS
# SWAPPED. *  `_binop(Ops.CMPLT, y, reverse=True)` (elementwise.py:323) puts `y` on the LEFT,
# so `(x>y)` is `CMPLT(y, x)` and `(x<y)` is `CMPLT(x, y)` -- MEASURED on CPython's own tree,
# both slots, 2026-10-31.
#
# * and the inner `(x.eq(y))` is the same node in both slots. *  upstream's rule body binds `x`
# and `y` ONCE and writes `(x.eq(y)).where(ctx * 0.5, 0)` in both arms, and `UOp` is
# hash-consed, so the second arm's `(x.eq(y))` IS the first arm's node. MEASURED on CPython's
# own tree, 2026-10-31: the two slots' inner WHEREs are the SAME `id()`, so the MAX gradient is
# 15 nodes and 3 WHEREs.
#
# - the port built four WHEREs and three CMPNEs, and `max_n0`/`max_n1` did not see IT. The
# port computed slot 1 from `(y.eq(x))` -- the operands SWAPPED -- which is a DIFFERENT node
# (CMPNE is not commutative), so the port built a SECOND inner WHERE. And the port's own count
# rows are blind to it: `size1` counts a shared subtree once PER PATH, so a duplicated inner
# WHERE costs exactly what a shared one costs, and `max_n0`/`max_n1` read 21 on both sides --
# MEASURED, on the defect and on the fix. A COUNT that is right and a STRUCTURE that is wrong
# is the failure a count cannot see, and `gates/gr_graph_census-gate.py` reads `max_eq_op`,
# which asks whether the mask's op is `CMPNE` -- TRUE for both spellings.
#
# - the fix is to build the inner once and swap only the outer."""),

  # ---- rule 14 REDUCE -- the TWO UPSTREAM WHY-S are the fact (the accumulation dtype and the
  # product-of-others). The FIRST paragraph's dispatch list is a table.
  (673, 710, """# --- 14. REDUCE -- gradient.py:82. `reduce_gradient(ctx, ret, ret.arg[0])`
#
# DISPATCHED, not inlined: the body is `reduce_gradient`, a top-level Python function with
# three arms keyed on the REDUCE's op (`gradient.py:8-18`), and all three need `_min_max` or
# `broadcast_axes`:
#   ADD (:9)  `ctx._broadcast_to(ret.src[0].shape)`  -- movement.py:128
#   MAX (:12) `mask/mask._rop(ADD, ...)`             -- `_rop` needs `resolve(shape[x]!=1)`
#   MUL (:18) `ret/safe_x` and a second `_rop`        -- same
# `_rop` (ops.py:655) reads `resolve(self.shape[x] != 1)`, which is a SYMBOLIC comparison and
# is `uop/symbolic.py`'s `resolve`, not ops.bend's. And `_broadcast_to` needs `broadcast_axes`
# (ops.py:89), which is also symbolic (`resolve(s == 1)`).
#
# THE TWO UPSTREAM WHY-S COMMENTS OF `reduce_gradient`, and they are the only place the
# ACCUMULATION DTYPE is not an arbitrary choice:
#
#   gradient.py:11 -- `mask = ret.src[0].eq(ret).cast(sum_acc_dtype(ctx.dtype))`. THE TIES ARE
#     COUNTED IN THE ACC DTYPE, and the reason is that the COUNT can OVERFLOW THE GRADIENT
#     DTYPE. `ctx.dtype` is the dtype of the incoming gradient, which for a float32 upstream
#     tensor is float32, and a float32 holds 2**24 exactly: a reduction over more than 16M
#     elements ties more than 2**24 times and the COUNT is wrong in float32 while it is right
#     in float64. `sum_acc_dtype` (tinygrad/dtype.py:217) picks the wider type, and the CAST
#     back to `ctx.dtype` happens AFTER the divide. So the ORDER is load-bearing: cast to the
#     acc dtype, count, divide, cast back.
#   gradient.py:15 -- `d(prod x)/dx_j = prod_{i!=j} x_i`: `ret/x_j` whenever `x_j != 0`, and
#     THE PRODUCT OF THE OTHERS otherwise. The reason `ret/x_j` is not enough on its own is
#     that ANY ZERO MAKES ret 0, and `0/0` is not the derivative of a product with a zero
#     factor -- it is the derivative of the product of the OTHER factors, which `ret/x_j`
#     cannot recover once `ret` has already been zeroed. So upstream computes BOTH: `safe_x`
#     replaces the zeros with 1 so `safe_x._rop(MUL)` is the product of the others, and
#     `zero_count` says HOW MANY zeros there are, so the `zero_count == 1` arm (exactly one
#     zero, so the other factors' product is the right derivative) and the `> 1` arm (the
#     derivative is 0) are separable.
# TODO(p3) mixin/gradient.py:8  reduce_gradient -- `_rop`'s `resolve(self.shape[x]!=1)` and
#   `_broadcast_to`'s `broadcast_axes` are both `resolve` on a `Sint`, and `symbolic.py`'s
#   `resolve` is not ported. Phase P3 owns `symbolic`."""),
]

apply(F, EDITS)
