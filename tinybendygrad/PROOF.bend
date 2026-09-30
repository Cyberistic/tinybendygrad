import Base
import ./LAWS.bend as L
import ./LAWS/spec.bend as S

# PROOF.bend -- the shape half of the proof set.
#
# Proves a law in ./LAWS.bend by a def of the same name whose parameters are
# that law's `for` binders IN ORDER. So a law that now quantifies a depth budget
# `for +depth: Nat` is proven by a def whose FIRST parameter is that budget, and
# the budget leads every helper in LAWS.bend for the same reason.
#
# WHY SO MANY ARE OPEN. Both folds in LAWS/spec.bend are fuelled, and
# `Sp.shape(s, depth)` computes its fuel as `2*depth+1` before matching on it.
# Two consequences, both measured against the pinned 2.0.34 compiler, and both
# in LAWS/spec.bend rather than in this file:
#
#   1. A SYMBOLIC budget never reduces. The scrutinee `2*depth+1` is a computed
#      value, and a match may not open one, so `Sp.shape.item` stays stuck and
#      the two sides of a law sit on two different stuck terms. Case analysis on
#      `depth` does not help: Nat is unary, so every split leaves a case with a
#      free `p` in the fuel, and induction on the depth binder does not apply
#      either -- the induction hypothesis is about fuel `2p+1` while the goal
#      carries `2p+3`.
#
#   2. The `case 2n+p:` arm of BOTH folds is DEAD. `case 1n+p:` is tried first
#      and matches every successor, so the pair arm is never reached and the
#      fuel only ever decrements to `0n`, which answers None. So
#      `Sp.shape` and `Sp.dtype` are the CONSTANT None for every operand and
#      every budget. A law proved against them is proved against a constant.
#
# Every def below that would have been `{==}` is therefore left OPEN, with the
# reason recorded. A green gate over those would be a gate over a constant
# function, which is worse than a red one.

# --- Open: the fuel is computed from the budget, so nothing reduces. --------
# See (1) above. The two sides are
#   dims_prod(Sp.shape.item(2p+3, One{SpPermute{t, order}}))  and
#   dims_prod(Sp.shape.item(2p+3, One{t}))
# two different stuck terms.
# law permute_preserves_numel(depth, t, order)

# See (1). Same two stuck terms, with SpFlip in place of SpPermute.
# law flip_preserves_numel(depth, t, flags)

# See (1). The premise is no help either: it too reduces to a stuck
# `dims_prod(Sp.shape.item(2p+3, One{t}))`, which the subject does not contain.
# law reshape_preserves_numel(depth, t, dst, premise)

# See (1), and note the law is ALSO refuted, not merely stuck: at depth 0n the
# fold answers None, so the claim is `0n == S.prod(dst)`, which is false for
# any non-empty dst. The spec's own premise `prod dst = numel_of(t)` cannot be
# satisfied under a fold that reports no element count at all.
# law reshape_numel_is_the_new_shape(depth, t, dst)

# See (1), and also refuted: Pad's shape column IS `size`, so the claim is
# `S.prod(size) == 0n` at the only budget that reduces. False for size = [2].
# law pad_numel_is_the_new_shape(depth, t, off, size)

# See (1), and refuted for the same reason as Pad: Shrink's shape column is also
# `size`, so the claim is `S.prod(size) == 0n`.
# law shrink_numel_is_the_new_shape(depth, t, off, size)

# See (1). The premise shares the budget, as the law requires, and still cannot
# be used: it is stuck, and it is stuck in the same place the subject is.
# law pad_shrink_round_trip(depth, t, off, size, premise)

# UNPROVABLE, AND VACUOUS, AND THE PREMISE IS UNINHABITED. The premise asks the
# fold for t's shape, and by (2) the fold answers None for every t, so
# `shape_of(depth, t) == Some{bs}` has no witness: the law is true only because
# its hypothesis is empty. Even with a working fold the conclusion would still
# need (1). This is the law the brief flagged: it compares the fold against
# itself, and the premise only ever buys the checker a rewrite it cannot use.
# law stack_numel_is_the_leading_axis_times_the_operands(depth, t, rest, bs, premise)

# See (1). Reduce's shape column drops the first k axes, so both sides sit on a
# stuck `Sp.shape.item`, one on `One{SpReduce{...}}` and one on `One{t}`.
# law reduce_numel_divides_by_the_reduced_axes(depth, t, ranges, op, n)

# See (1). Broadcast is zip_max of the two operand shapes, so the left-hand
# side is a stuck `Sp.shape.item` on `One{SpAdd{a, b}}` and the right is one on
# `One{a}`. The law also over-claims: tinyspec's rule is right-align and take
# the element-wise max, which is `a` only when the two agree.
# law broadcast_takes_the_left_shape(depth, a, b)

# See (1). Both sides are a stuck `Sp.dtype.item` at the same computed fuel,
# one on `One{SpDetach{a}}` and one on `One{a}`.
# law detach_preserves_dtype(depth, a)

# See (1), with `dims_prod` around each stuck shape.
# law detach_preserves_numel(depth, a)

# See (1) for the subject; the premise is stuck in the same place, so it cannot
# be used as a rewrite. Also note the law over-claims: the shape column says
# "all inputs same shape", so the conclusion holds under the premise, but the
# premise and conclusion are asked at the one shared budget the law fixes.
# law add_is_elementwise(depth, a, b, premise)
# law mul_is_elementwise(depth, a, b, premise)
# law max_is_elementwise(depth, a, b, premise)

# PROVEN, BUT VACUOUS BY CONSTRUCTION, and it was before the folds were fuelled:
# the conclusion restates the premise verbatim, so the premise IS the proof and
# the law cannot fail whatever the fold says. It is kept and proven because the
# spec states the constraint, but it pins no behaviour. Making it bite would
# need a law about the Store's own shape, not a restatement of its hypothesis.
def L.store_matches_its_buffer(depth, buf, val, gate, premise):
  premise
