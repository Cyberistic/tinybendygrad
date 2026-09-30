import Base
import ./LAWS.bend as L
import ./LAWS/spec.bend as S

# PROOF.bend -- the shape half of the proof set (LAWS.bend sections I, II, III,
# VI and VII).
#
# A proof is a def of the law's name whose parameters are that law's `for`
# binders IN ORDER. Seven of the thirteen are discharged here; six are left open
# with the reason recorded, and the reason is always the same shape:
#
#   `Sp.shape` can only reduce a node whose arm READS ITS OWN FIELDS. An arm that
#   has to case-split on ANOTHER node's shape -- Reduce's `Shape.drop`,
#   Stack's `Shape.prepend`, the ALU arms' `dims_zip_max` -- sits behind
#   `on_shape(Sp.shape(x), ...)` or `dims_zip_max(Sp.shape(a), Sp.shape(b))`,
#   and `Sp.shape(x)` is a CALL. A `match` may not open a call (PORTING.md
#   section 1.2), so those terms never reduce and the two sides of the law stay
#   apart however deep the tree is.
#
#   Under the old fuel budget every law was stuck for a second reason as well:
#   the fold computed `2*depth+1` and matched on it, so a symbolic depth never
#   reduced, and `case 1n+p:` shadowed `case 2n+p:` so the fold was the constant
#   None. Both defects are gone. See spec/depth.md.
#
# WHAT IS PROVED is still worth proving, and the proofs are trivial only because
# the `Sp.shape` arm IS the right-hand side -- `SpPermute`'s arm is literally
# `Sp.shape(t)`. They were mutation-tested: breaking each arm in turn fails the
# law it belongs to. See spec/shape-laws.md.

# tinyspec: "Reorder axes." The shape column is src[0].shape, and the arm is
# `Sp.shape(t)`, so both sides are the same term.
def L.permute_preserves_numel(t, order):
  {==}

# tinyspec: "Reverse along flagged axes." Same column, same arm.
def L.flip_preserves_numel(t, flags):
  {==}

# tinyspec Reshape: "prod s_k = prod s'_k". The arm is `Some{Shape.of(dst)}`, so
# the subject's count is `prod dst` -- which is the premise, verbatim. There is
# no derivation to add: the spec's constraint IS the goal once the fold runs.
def L.reshape_preserves_numel(t, dst, premise):
  premise

# The same fact from the other side, and it needs no premise.
def L.reshape_numel_is_the_new_shape(t, dst):
  {==}

# tinyspec Pad: "Place T at offset o_k in an invalid-filled output of shape
# s'_k", so the count is the output's.
def L.pad_numel_is_the_new_shape(t, off, size):
  {==}

# tinyspec Shrink: "Keep s'_k elements starting at offset o_k per axis", so the
# count is the narrowed shape's.
def L.shrink_numel_is_the_new_shape(t, off, size):
  {==}

# tinyspec Shrink is the "Inverse of Pad", in extent. As with Reshape, the
# subject's count is `prod size` and that is the premise.
def L.pad_shrink_round_trip(t, off, size, premise):
  premise

# OPEN -- STUCK, and the law is TRUE. The fold is total, so the premise now has
# a witness and the law is no longer vacuous; the conclusion is also not a
# restatement of the premise. What blocks it is that Stack's arm must prepend to
# the head's shape:
#
#     dims_prod(on_shape(Sp.shape(t), sh => Some{Shape.prepend(SN{n+1}, sh)}))
#
# `on_shape` has to case-split on `Sp.shape(t)`, which is a call, so the term
# stays as it is printed. A premise cannot be used as a rewrite rule either:
# a proof must have the GOAL's equation type, and this goal is
# `dims_prod(on_shape(...)) == n * dims_prod(Sp.shape(t))`, which is not the
# premise `shape_of(t) == Some{bs}`. Making it provable needs a law about
# `on_shape` or about `Sp.shape` of a Stack, not a rewrite here.
# law stack_numel_is_the_leading_axis_times_the_operands(t, rest, bs, premise)

# OPEN -- REFUTED, not merely stuck. The law says the reduced count EQUALS the
# original, and Reduce's arm is `Shape.drop(shape(t), n)`, which is tinyspec's
# "Reduce the first n axes of T": it removes elements, so the count divides
# rather than survives. `t` of shape (4,5,6) with `n = 1n` gives 30 against
# 120. The law's own NAME says "divides by", so the body was what is wrong.
#
# Both bodies are now corrected in LAWS.bend: this one asserts the division
# rather than equality. It remains OPEN -- the subject is `Shape.drop` applied to
# another fold's result, which a `match` cannot open. The law is TRUE.
# law reduce_numel_divides_by_the_reduced_axes(t, n)

# The previous law claimed the broadcast took the LEFT operand's shape, which
# tinyspec refutes: right-align and take the element-wise max, so (1,3) with
# (2,3) is (2,3). Renamed to broadcast_is_elementwise_max and restated as the max
# of the two counts, which is what the rule actually says.
#
# OPEN. The count is `dims_prod` of a `zip_max` of two symbolic shapes, and
# `zip_max` cannot reduce without knowing them.
# law broadcast_is_elementwise_max(a, b)

# OPEN -- STUCK, and the laws are TRUE. Each says the broadcast of two operands
# of equal shape is that shape, which is tinyspec's "all inputs same shape,
# output same shape". The subject normalises to
# `dims_zip_max(Sp.shape(a), Sp.shape(b))` against `Sp.shape(a)`, and the
# premise `Sp.shape(a) == Sp.shape(b)` cannot be used: a proof must have the
# goal's own equation type, and `zip_max` still cannot reduce on a symbolic
# shape even with both sides equal. A shape-level law saying
# `zip_max(s, s) == s` would settle all three at once.
# law add_is_elementwise(a, b, premise)
# law mul_is_elementwise(a, b, premise)
# law max_is_elementwise(a, b, premise)

# PROVEN, BUT VACUOUS BY CONSTRUCTION, and it was before the folds were fuelled:
# the conclusion restates the premise verbatim, so the premise IS the proof and
# the law cannot fail whatever the fold says. It is kept and proven because the
# spec states the constraint, but it pins no behaviour. Making it bite would
# need a law about the Store's own shape, not a restatement of its hypothesis.
def L.store_matches_its_buffer(buf, val, gate, premise):
  premise

# ===========================================================================
# Section VIII -- the shape algebra's own laws.
# ===========================================================================

# Base proves `Nat.max_ge_l` and `Nat.max_ge_r` but NOT `Nat.max(v, v) == v`, and
# `Shape.max_dim`'s SN arm is exactly `SN{Nat.max(v, v)}`, so the leaf fact has to
# be proved here. Induction on the Nat.
#
# Two syntax rules cost time and are worth writing down:
#   * a def with NO return type is a law proof, so a helper like this needs an
#     explicit `-> {Nat.max(v, v) == v : Nat}`, and `+v` so the binder is
#     reusable across the two occurrences;
#   * the `%proof : P` motive is written against the goal AFTER the match. In
#     the step case the goal is `1n+Nat.max(p, p) == 1n+p`, so P is
#     `{1n+Nat.max(p, p) == 1n+_ : Nat}` -- NOT the pre-match goal.
def nat_max_idem(+v: Nat) -> {Nat.max(v, v) == v : Nat}:
  match v:
    case 0n:
      {==}
    case 1n+p:
      %nat_max_idem(p) : {1n+Nat.max(p, p) == 1n+_ : Nat}
      {==}

# `max_dim` is idempotent. SS is a case split in the source and returns the
# first argument, so it is reflexive; SN reduces through `nat_max_idem`.
def L.max_dim_idempotent(x):
  match x:
    case S.SN{v}:
      %nat_max_idem(v) : {S.SN{Nat.max(v, v)} == S.SN{_} : S.Sdim}
      {==}
    case S.SS{p}:
      {==}

# `zip_max` is idempotent. This is the law the three elementwise laws in
# section VI were waiting on.
#
# The proof does NOT use `%` rewrites under the list constructor -- every motive
# shape for that was tried and silently accepted without firing. It uses
# congruence and transitivity instead, which is the way Bend wants it done.
#
# `Equal.cong(A, B, f, a, b, e)` congrues a UNARY function, so the cons is split
# in two: `cons_head` has the head fixed and lifts a proof about the TAIL,
# `cons_tail` has the tail fixed and lifts max_dim's proof. The two results share
# the middle term `md <> xs`, and `Equal.trans` does the substitution.
#
# `snoc` exists only because a bare `h <> t` in a call argument or a local's
# right-hand side is "cannot infer" -- the operator needs its type spelled out,
# and routing it through a typed def is less noise than annotating each use.
def snoc(h: S.Sdim, t: List<&2, S.Sdim>) -> List<&2, S.Sdim>:
  h <> t

# Cons with a FIXED head, so the function Equal.cong sees is unary in the tail.
def cons_head(h: S.Sdim) -> (List<&2, S.Sdim> -> List<&2, S.Sdim>):
  t => h <> t

# Cons with a FIXED tail, for the other direction.
def cons_tail(t: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):
  h => h <> t

def L.zip_max_idempotent(s):
  match s:
    case Nil{}:
      {==}
    case x <> xs:
      ih = L.zip_max_idempotent(xs)
      +md = S.Shape.max_dim(x, x)
      +mh = L.max_dim_idempotent(x)
      f1 = cons_head(md)
      f2 = cons_tail(xs)
      +zmx = S.zip_max(xs, xs)
      left = snoc(md, zmx)
      mid = snoc(md, xs)
      end = snoc(x, xs)
      c1 = Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, f1, zmx, xs, ih)
      c2 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f2, md, x, mh)
      Equal.trans(List<&2, S.Sdim>, left, mid, end, c1, c2)
