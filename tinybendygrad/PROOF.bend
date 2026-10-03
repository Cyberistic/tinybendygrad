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
# TWO laws remain open. Both were previously recorded here as "stuck"; both are
# FALSE as written, each with a counterexample printed by
# `.agents/slop/ind/p3.bend` and set out in full at the foot of this file.
# Closing either one means editing `LAWS.bend` or `LAWS/spec.bend`, so it needs an
# owner ruling rather than a proof. `reduce_numel_divides_by_the_reduced_axes`
# and `broadcast_is_elementwise_max` are marked where they would go.
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

# OPEN -- AND THE LAW IS FALSE as written, not merely stuck. The multiplier
# `prod_of(drop_n(dims_of(t), n))` is the count of the axes that were KEPT; the
# count of the axes that were REMOVED is what the name describes, and with that
# term in place of this one the law is TRUE (measured at the foot of the file).
# Separately, `LAWS/spec.bend`'s `drop_n(ds, n)` drops `n + 1` dims rather than
# `n`, which no law covers. Both fixes touch `LAWS.bend` or `LAWS/spec.bend`, so
# they need an owner ruling rather than a proof here. Not closed.
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
# THE TWO LAWS LEFT OPEN, with the evidence. Both were recorded above as "stuck";
# both are false as written. `.agents/slop/ind/p3.bend` mirrors `LAWS.bend`'s
# helper bodies verbatim and evaluates each side on concrete nodes; its printed
# rows are saved in `.agents/slop/ind/p3-counterexamples.txt`, and bend's own
# elaboration of each goal is in `p6-open-goals.txt` and `p7-open-goals.txt`.
#
# `reduce_numel_divides_by_the_reduced_axes(t, n)`:
#
#     t=(4,)    n=0n    LHS=1   RHS=4      False
#     t=(4,5,6) n=1n    LHS=36  RHS=120    False
#
# so the law is `1n == 4n` and `36n == 120n`. The multiplier
# `prod(drop_n(dims_of(t), n))` is the count of the axes that were KEPT, not the
# axes that were REMOVED. Replace that one term with the product of the axes
# `drop_n` actually drops and the law is TRUE, measured:
#
#     multiplier = prod(List.take(dims_of(t), n + 1n))
#     t=(4,)    n=0n    LHS=4   RHS=4      True
#     t=(4,5,6) n=1n    LHS=120 RHS=120    True
#
# SECOND FINDING, and it is a real one: `LAWS/spec.bend`'s `drop_n(ds, n)` drops
# `n + 1` dims, not `n`. Measured, on (4,5,6): `n=0n` keeps 2 dims, `n=1n` keeps 1,
# `n=2n` keeps 0; Base's `List.drop` would keep 3, 2, 1. So `Shape.drop(sh, 0n)`
# removes an axis, against tinyspec's "Reduce the first n axes", and the same
# off-by-one reaches `Sp.shape.index`: an `Index` of arity 1 over a rank-3 base
# has rank 1, where tinyspec's `s.src[0].shape[len(s.src[1:]):]` says 2. No law
# covers `Index`'s shape, so the gate cannot see either.
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
# NEITHER is closed here on purpose. Closing either means editing `LAWS.bend` --
# the contract with tinygrad's behaviour, whose own header says the point of the
# file is that the CHECKER catches a port's change, not a proof -- or
# `LAWS/spec.bend`. Both are owner rulings. A proof that closed them by weakening
# the statement would be worse than the open claim: the file would then assert less
# than tinygrad does, and nothing would say so.
# ===========================================================================