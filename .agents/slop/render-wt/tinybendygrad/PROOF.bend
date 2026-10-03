import Base
import ./LAWS.bend as L
import ./LAWS/spec.bend as S

# PROOF.bend -- the shape half of the proof set (LAWS.bend sections I, II, III,
# VI, VII and VIII).
#
# A proof is a def of the law's name whose parameters are that law's `for`
# binders IN ORDER.
#
# ORDER IS THE WHOLE FILE, because a def may only call a def DECLARED ABOVE it.
# The shape algebra -- section VIII's two laws, and the Maybe-level lemmas the
# section II and VI laws are built from -- therefore comes FIRST and the law
# proofs follow it. Nothing else in the repo is order-sensitive in this way,
# because nothing else here is a helper.
#
# TWO laws remain open. `broadcast_is_elementwise_max` is FALSE as written
# (a symbolic axis counts as 0). `reduce_numel_divides_by_the_reduced_axes`
# was false for two independent reasons, both measured and both fixed in the
# contract: `drop_n` dropped `n+1`, and the multiplier was the kept product
# rather than `List.take(dims, n)`. The corrected statement is true on the
# measured cases and unproven here. Both are marked where they would go.
#
#   `Sp.shape` can only reduce a node whose arm READS ITS OWN FIELDS. An arm that
#   has to case-split on ANOTHER node's shape -- Reduce's `Shape.drop`,
#   Stack's `Shape.prepend`, the ALU arms' `dims_zip_max` -- sits behind
#   `on_shape(Sp.shape(x), ...)` or `dims_zip_max(Sp.shape(a), Sp.shape(b))`,
#   and `Sp.shape(x)` is a CALL. A `match` may not scrutinise a call (see
#   `.agents/slop/notes/bend2-constraints.md` around line 4352, and rule 1.2's
#   note on scrutinees), so those terms never reduce however deep the tree is.
#   That is why each law closed by induction closes through a HELPER whose
#   parameter is the shape -- `zip_maybe_idem`, `stack_numel_go` -- and not in
#   the law body: the law's binder is symbolic and a helper's is not.
#   `PORTING.md`, cited here before, DOES NOT EXIST in this repo: it is prep-work
#   item 3 of `.agents/slop/plans/00-master-plan.md` and was never written. Four
#   other files cite it too.
#
#   Under the old fuel budget every law was stuck for a second reason as well:
#   the fold computed `2*depth+1` and matched on it, so a symbolic depth never
#   reduced, and `case 1n+p:` shadowed `case 2n+p:` so the fold was the constant
#   None. Both defects are gone. See spec/depth.md.
#
# WHAT IS PROVED is still worth proving, and several proofs are one-liners only
# because the `Sp.shape` arm IS the right-hand side -- `SpPermute`'s arm is
# literally `Sp.shape(t)`. Those were mutation-tested: breaking each arm in turn
# fails the law it belongs to. See spec/shape-laws.md.

# ===========================================================================
# Section VIII -- the shape algebra's own laws, and the Maybe-level lemmas the
# section II and VI laws are built from.
#
# A law's shape binder is SYMBOLIC, and `match` may not scrutinise a call, so
# neither `zip_max` nor `on_shape` can be opened inside a law body. Each helper
# below takes the shape as a PARAMETER and does the induction there; the law
# proof is then one application. All three are stated as equations with an
# explicit `-> {a == b : T}` rather than as `def name(...)` law proofs, because
# a def with no return type is an attempt to fill a law of that name.
# ===========================================================================

# Base proves `Nat.max_ge_l` and `Nat.max_ge_r` but NOT `Nat.max(v, v) == v`, and
# `Shape.max_dim`'s SN arm is exactly `SN{Nat.max(v, v)}`, so the leaf fact has to
# be proved here. Induction on the Nat.
#
# Two syntax rules cost time and are worth writing down:
#   * a def with NO return type is a law proof, so a helper like this needs an
#     explicit `-> {Nat.max(v, v) == Nat}`, and `+v` so the binder is reusable
#     across the two occurrences;
#   * the `%proof : P` motive is written against the goal AFTER the match. In the
#     step case the goal is `1n+Nat.max(p, p) == 1n+p`, so P is
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

# `zip_max` is idempotent, by structural induction on the dim list: the base case
# is `zip_max(Nil{}, Nil{}) == Nil{}` and the step conses `max_dim(x, x)` onto the
# induction hypothesis for the tail.
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

# `zip_max(s, s) == s` lifted one constructor at a time -- which is what the three
# elementwise laws in section VI need. Two constructors stand between the dim list
# and those laws' conclusions, `Shape.of` and `Some`, and each is UNARY, which is
# exactly what `Equal.cong` wants, so it is two congruences and no motive.
#
# `S.Shape.of` cannot be handed to `Equal.cong` as a value: its parameter is
# `+xs`, so its type is `(+List<&2, S.Sdim> -> Shape)` and not the
# `List<&2, S.Sdim> -> Shape` the congr signature asks for. `of_shape` re-spells
# it as an ordinary unary function, and that wrapper is the only reason it exists.
def of_shape(ds: List<&2, S.Sdim>) -> S.Shape:
  S.Shape.of(ds)

# `Some` likewise, and for the same reason -- a constructor has to be NAMED to be
# passed as a function.
def some_shape(sh: S.Shape) -> Maybe<&2, S.Shape>:
  Some{sh}

def zip_maybe_idem(m: Maybe<&2, S.Shape>) -> {S.dims_zip_max(m, m) == m : Maybe<&2, S.Shape>}:
  match m:
    case None{}:
      {==}
    case Some{sh}:
      match sh:
        case S.Sh{+ds}:
          ih = L.zip_max_idempotent(ds)
          c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(ds, ds), ds, ih)
          c2 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(ds, ds)), S.Shape.of(ds), c1)
          c2

# `Nat.mul` matches on its FIRST argument (`Nat.mul(0n, b) = 0n`,
# `Nat.mul(1n+p, b) = Nat.add(b, Nat.mul(p, b))`), so `Nat.mul(k, 0n)` is stuck on
# a symbolic `k`. The shapeless Stack case needs exactly `k * 0n == 0n`, and
# `nat_mul_zero_r` is that fact, by induction on the Nat -- the same shape and the
# same reason for existing as `nat_max_idem`.
def nat_mul_zero_r(k: Nat) -> {Nat.mul(k, 0n) == 0n : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      nat_mul_zero_r(p)

# tinyspec Stack: "Join along a newly created leading axis". `Sp.shape.stack`
# prepends `SN{k}` and `dim_of(SN{k})` is `k`, so a leading axis of `k` multiplies
# the element count by `k` -- which is the whole law, at any `k`.
#
# `Some{sh}` is `{==}`, because the count of the prepended list is
# `Nat.mul(k, prod(ds))` on both sides. `None{}` needs `Equal.sym`, because the
# goal there is `0n == Nat.mul(k, 0n)`: the other way round from the helper's.
def stack_numel_go(k: Nat, m: Maybe<&2, S.Shape>) -> {S.dims_prod(S.Sp.shape.stack(m, k)) == Nat.mul(k, S.dims_prod(m)) : Nat}:
  match m:
    case None{}:
      Equal.sym(Nat, Nat.mul(k, 0n), 0n, nat_mul_zero_r(k))
    case Some{sh}:
      match sh:
        case S.Sh{+ds}:
          {==}

# ===========================================================================
# The law proofs.
# ===========================================================================

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

# tinyspec Stack: "Join along a newly created leading axis", so the count is the
# OPERAND COUNT times the head's count, and the operand count is `1n + |rest|`.
#
# The premise is NOT used, and that is the point: the law holds for every `bs`,
# including those where the premise has no witness at all (a shapeless head). The
# old note here claimed the premise was needed to open `on_shape`; it never was.
# `stack_numel_go` is the identity that makes it unnecessary, so the law body is
# that helper at `k = 1n + length(rest)`.
def L.stack_numel_is_the_leading_axis_times_the_operands(t, rest, bs, premise):
  stack_numel_go(Nat.add(List.length(&2, S.Sp, rest), 1n), S.Sp.shape(t))

# OPEN. The statement is the measured one: `reduced_numel * prod(take(dims, n))
# == numel`. It is not `{==}` from here. `reduced_numel` sits behind
# `Sp.shape.reduce`, and `n` is a symbolic binder, so `List.drop`/`List.take`
# do not reduce. Not closed. Not false: see the foot of this file.
# law reduce_numel_divides_by_the_reduced_axes(t, n)

# OPEN -- AND THE LAW IS FALSE as written, not merely stuck. `dim_of(SS{x})` is
# `0n` in spec.bend, so the count of a shape carrying a symbolic axis is `0n`,
# and the law is universally quantified over `Sp`, which admits one. The
# counterexamples are at the foot of this file, printed by
# `.agents/slop/ind/p3.bend`.
#
# It does hold for the literal shapes the name describes -- (2,3) with (3,3) is 9
# against 9 -- and fails as soon as either operand carries a symbolic axis or a
# zero. Restricting the quantifier, or restating it over `Shape` rather than over
# a count, is a `LAWS.bend` change: owner ruling. Not closed.
# law broadcast_is_elementwise_max(a, b)

# tinyspec's elementwise column: "all inputs same shape, output same shape".
#
# Each of the three is the SAME two steps -- rewrite `b`'s shape into `a`'s with
# the premise, then `zip_max(s, s) == s` lifted through `Shape.of` and `Some` --
# so the algebra is done once, in `zip_maybe_idem` above, and these three are one
# call each.
#
# NOT VACUOUS. The conclusion is not the premise: the subject is a broadcast of
# two INDEPENDENT shapes that happen to be equal, and it is wrong when they are
# not -- which is what `zip_max_idempotent` being a real theorem buys.
def L.add_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

def L.mul_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

def L.max_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

# PROVEN, BUT VACUOUS BY CONSTRUCTION, and it was before the folds were fuelled:
# the conclusion restates the premise verbatim, so the premise IS the proof and
# the law cannot fail whatever the fold says. It is kept and proven because the
# spec states the constraint, but it pins no behaviour. Making it bite would
# need a law about the Store's own shape, not a restatement of its hypothesis.
def L.store_matches_its_buffer(buf, val, gate, premise):
  premise

# ===========================================================================
# THE TWO LAWS LEFT OPEN. `p3.bend` is the pre-fix measurement. The reduce
# law's term has since been corrected; broadcast has not. The measurement that
# decided the fix is `.agents/slop/ind/dropn-measure.bend`, against the live
# tree and against `List.drop` (Base's contract, not a call to the helper):
#
#     AS WRITTEN, drop_n dropping n+1:   t=(4,) n=0  1==4 False;  (4,5,6) n=1  36==120 False
#     drop exact n, body unchanged:      t=(4,) n=0  16==4 False; (4,5,6) n=1  900==120 False
#     drop exact n, multiplier take(n):  t=(4,) n=0  4==4 True;   (4,5,6) n=1  120==120 True
#     drop exact n, multiplier take(n+1): t=(4,) n=0 16==4 False; (4,5,6) n=1  600==120 False
#
# `take(n+1)` was the compensation for the off-by-one, not the contract. The
# body is now `prod(List.take(dims, n))`. `drop_n` is `List.drop`. The Index
# rank defect is closed by that same change: an arity-1 Index over rank 3 is
# rank 2, pinned by `spec.bend`'s gate (`idx1_rank3=2`). Those literals are
# tinygrad's shapes from `.agents/slop/ind/dropn-oracle.py`, not `drop_n`.
#
# `broadcast_is_elementwise_max(a, b)`:
#
#     a=(2,3) b=(3,3)    LHS=9   RHS=9      True    <- the case the name describes
#     a=(SS,5) b=(3,7)   LHS=21  RHS=0      False
#     a=(5,0) b=(3,)     LHS=3   RHS=0      False
#
# `dim_of(SS{x})` is `0n`, so a shape carrying a symbolic axis has count `0n`, and
# the law is quantified over `Sp`, which admits one. It is right about the literal
# shapes it names and wrong about the range it quantifies over.
#
# The reduce law's contract is corrected, not weakened: the new term is what
# tinyspec and tinygrad say, and it is still unproven. Broadcast is untouched
# and still false as quantified. Closing it by restricting the quantifier is
# an owner ruling; a proof that did it by weakening the statement would assert
# less than tinygrad does.
# ===========================================================================