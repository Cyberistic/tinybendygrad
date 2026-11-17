import Base
import ../LAWS.bend as L
import ./spec.bend as S

# PROOF.bend -- THE PROOF SET, all thirty-four laws in ONE book.
#
# A proof is a def of the law's name whose parameters are that law's `for`
# binders IN ORDER.
#
# ONE FILE, AND IT WAS TWO BECAUSE OF A CONSTRAINT AND NOT A PLAN.  `bend`
# discharges a law by a `def` of the same name ANYWHERE IN THE BOOK, and allows
# ONE such def per book (`references/bend/bend2/bend.ts:2437` takes the law's
# own qualified name only while the law has no body), so a half-book reports the
# OTHER half's laws as open: the shape half alone reported 18 TODOs and the
# ALU/dtype half 16, and every one of those was a law the other half proved.
# The aggregate `PROOF-ALL.bend` imported both halves and was the one book whose
# closure held all thirty-four.
#
# MEASURED 2026-11-17: the two halves' sixty defs have NO NAME IN COMMON --
# forty-two here and eighteen there -- and NEITHER CALLS A DEF DECLARED LATER IN
# ITS OWN FILE, so ONE FILE holds both halves and the concatenation is
# ORDER-SAFE.  This file reports `ALL PROOFS CHECK` and the law census reads it
# `0 open / 34 filled`.
#
# ORDER is the whole file, because a def may only call a def DECLARED above it.
# The shape algebra -- section VIII's two laws, and the Maybe-level lemmas the
# section II and VI laws are built from -- therefore comes FIRST and the law
# proofs follow it. Nothing else in the repo is order-sensitive in this way,
# because nothing else here is a helper.
#
# THE SHAPE HALF (sections I, II, III, VI, VII and VIII) comes first, and the
# ALU/dtype half (IV and V) after it -- and the boundary is marked.  Every law
# this file owns is filled. Reduce is `reduced * prod(take(dims, n)) == numel`,
# proved by `reduce_numel_go`. Broadcast is restated: equal-length concrete
# shapes, each axis the non-1 size (`pick_dim`). The induction is `bcast_axes`.
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
#
# AND THE ALU/DTYPE HALF IS EASY WHERE THE SHAPE HALF WAS HARD. `Sp.dtype` reads
# at most one operand per arm, so no arm has to case-split on another node's
# result -- the shape half's one remaining obstacle does not arise here.  That is
# why the dtype half went green and the shape half needed the helpers above.
def nat_max_idem(+v: Nat) -> {Nat.max(v, v) == v : Nat}:
  match v:
    case 0n:
      {==}
    case 1n+p:
      %nat_max_idem(p) : {1n+Nat.max(p, p) == 1n+_ : Nat}
      {==}

# `max_dim` is idempotent. SS is a case split in the source and returns the
# first argument, so it is reflexive; SN reduces through `nat_max_idem`.
def pick_idem(v: Nat) -> {S.pick_dim(v, v) == v : Nat}:
  match v:
    case 0n:
      {==}
    case 1n:
      {==}
    case 1n+1n+p:
      {==}

def L.max_dim_idempotent(x):
  match x:
    case S.SN{v}:
      %pick_idem(v) : {S.SN{S.pick_dim(v, v)} == S.SN{_} : S.Sdim}
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

def nat_add_zero(x: Nat) -> {Nat.add(x, 0n) == x : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_add_zero(q) : {1n+Nat.add(q, 0n) == 1n+_ : Nat}
      {==}

def nat_add_assoc(x: Nat, +y: Nat, +z: Nat) -> {Nat.add(x, Nat.add(y, z)) == Nat.add(Nat.add(x, y), z) : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_add_assoc(q, y, z) : {1n+Nat.add(q, Nat.add(y, z)) == 1n+_ : Nat}
      {==}

def nat_add_succ_r(y: Nat, +p: Nat) -> {Nat.add(y, 1n+p) == 1n+Nat.add(y, p) : Nat}:
  match y:
    case 0n:
      {==}
    case 1n+q0:
      +q = q0
      ih = nat_add_succ_r(q, p)
      sih = Equal.sym(Nat, Nat.add(q, 1n+p), 1n+Nat.add(q, p), ih)
      %sih : {1n+_ == 2n+Nat.add(q, p) : Nat}
      {==}

def nat_add_comm(x: Nat, +y: Nat) -> {Nat.add(x, y) == Nat.add(y, x) : Nat}:
  match x:
    case 0n:
      Equal.sym(Nat, Nat.add(y, 0n), y, nat_add_zero(y))
    case 1n+p0:
      +p = p0
      ih = nat_add_comm(p, y)
      succ = nat_add_succ_r(y, p)
      ssucc = Equal.sym(Nat, Nat.add(y, 1n+p), 1n+Nat.add(y, p), succ)
      %ssucc : {1n+Nat.add(p, y) == _ : Nat}
      sih = Equal.sym(Nat, Nat.add(p, y), Nat.add(y, p), ih)
      %sih : {1n+_ == 1n+Nat.add(y, p) : Nat}
      {==}

def add_by(c: Nat) -> (Nat -> Nat):
  x => Nat.add(x, c)

def nat_add_swap(+x: Nat, +y: Nat, +z: Nat) -> {Nat.add(x, Nat.add(y, z)) == Nat.add(y, Nat.add(x, z)) : Nat}:
  left = nat_add_assoc(x, y, z)
  comm = nat_add_comm(x, y)
  mid = Equal.cong(Nat, Nat, add_by(z), Nat.add(x, y), Nat.add(y, x), comm)
  right = Equal.sym(Nat, Nat.add(y, Nat.add(x, z)), Nat.add(Nat.add(y, x), z), nat_add_assoc(y, x, z))
  step = Equal.trans(Nat, Nat.add(Nat.add(x, y), z), Nat.add(Nat.add(y, x), z), Nat.add(y, Nat.add(x, z)), mid, right)
  Equal.trans(Nat, Nat.add(x, Nat.add(y, z)), Nat.add(Nat.add(x, y), z), Nat.add(y, Nat.add(x, z)), left, step)

def nat_mul_one_r(k: Nat) -> {Nat.mul(k, 1n) == k : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      %nat_mul_one_r(q) : {Nat.add(1n, Nat.mul(q, 1n)) == Nat.add(1n, _) : Nat}
      {==}

def nat_mul_dist(x: Nat, +y: Nat, +z: Nat) -> {Nat.mul(Nat.add(x, y), z) == Nat.add(Nat.mul(x, z), Nat.mul(y, z)) : Nat}:
  match x:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      ih = nat_mul_dist(q, y, z)
      sih = Equal.sym(Nat, Nat.mul(Nat.add(q, y), z), Nat.add(Nat.mul(q, z), Nat.mul(y, z)), ih)
      %sih : {Nat.add(z, _) == Nat.add(Nat.add(z, Nat.mul(q, z)), Nat.mul(y, z)) : Nat}
      nat_add_assoc(z, Nat.mul(q, z), Nat.mul(y, z))

def nat_mul_assoc(a: Nat, +b: Nat, +c: Nat) -> {Nat.mul(a, Nat.mul(b, c)) == Nat.mul(Nat.mul(a, b), c) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      +q = p
      ih = nat_mul_assoc(q, b, c)
      dist = nat_mul_dist(b, Nat.mul(q, b), c)
      sdist = Equal.sym(Nat, Nat.mul(Nat.add(b, Nat.mul(q, b)), c), Nat.add(Nat.mul(b, c), Nat.mul(Nat.mul(q, b), c)), dist)
      %sdist : {Nat.add(Nat.mul(b, c), Nat.mul(q, Nat.mul(b, c))) == _ : Nat}
      sih = Equal.sym(Nat, Nat.mul(q, Nat.mul(b, c)), Nat.mul(Nat.mul(q, b), c), ih)
      %sih : {Nat.add(Nat.mul(b, c), _) == Nat.add(Nat.mul(b, c), Nat.mul(Nat.mul(q, b), c)) : Nat}
      {==}

def nat_mul_succ_r(b: Nat, +p: Nat) -> {Nat.mul(b, 1n+p) == Nat.add(b, Nat.mul(b, p)) : Nat}:
  match b:
    case 0n:
      {==}
    case 1n+q0:
      +q = q0
      ih = nat_mul_succ_r(q, p)
      sih = Equal.sym(Nat, Nat.mul(q, 1n+p), Nat.add(q, Nat.mul(q, p)), ih)
      %sih : {Nat.add(1n+p, _) == Nat.add(1n+q, Nat.add(p, Nat.mul(q, p))) : Nat}
      swap = nat_add_swap(p, q, Nat.mul(q, p))
      sswap = Equal.sym(Nat, Nat.add(p, Nat.add(q, Nat.mul(q, p))), Nat.add(q, Nat.add(p, Nat.mul(q, p))), swap)
      %sswap : {1n+_ == 1n+Nat.add(q, Nat.add(p, Nat.mul(q, p))) : Nat}
      {==}

def mul_by(c: Nat) -> (Nat -> Nat):
  x => Nat.mul(x, c)

def nat_mul_comm(a: Nat, +b: Nat) -> {Nat.mul(a, b) == Nat.mul(b, a) : Nat}:
  match a:
    case 0n:
      Equal.sym(Nat, Nat.mul(b, 0n), 0n, nat_mul_zero_r(b))
    case 1n+p0:
      +p = p0
      ih = nat_mul_comm(p, b)
      succ = nat_mul_succ_r(b, p)
      ssucc = Equal.sym(Nat, Nat.mul(b, 1n+p), Nat.add(b, Nat.mul(b, p)), succ)
      %ssucc : {Nat.add(b, Nat.mul(p, b)) == _ : Nat}
      sih = Equal.sym(Nat, Nat.mul(p, b), Nat.mul(b, p), ih)
      %sih : {Nat.add(b, _) == Nat.add(b, Nat.mul(b, p)) : Nat}
      {==}

def nat_mul_swap(+a: Nat, +b: Nat, +c: Nat) -> {Nat.mul(a, Nat.mul(b, c)) == Nat.mul(b, Nat.mul(a, c)) : Nat}:
  left = nat_mul_assoc(a, b, c)
  comm = nat_mul_comm(a, b)
  mid = Equal.cong(Nat, Nat, mul_by(c), Nat.mul(a, b), Nat.mul(b, a), comm)
  right = Equal.sym(Nat, Nat.mul(b, Nat.mul(a, c)), Nat.mul(Nat.mul(b, a), c), nat_mul_assoc(b, a, c))
  step = Equal.trans(Nat, Nat.mul(Nat.mul(a, b), c), Nat.mul(Nat.mul(b, a), c), Nat.mul(b, Nat.mul(a, c)), mid, right)
  Equal.trans(Nat, Nat.mul(a, Nat.mul(b, c)), Nat.mul(Nat.mul(a, b), c), Nat.mul(b, Nat.mul(a, c)), left, step)

def split(ds: List<&2, S.Sdim>, n: Nat) -> {Nat.mul(S.prod(List.drop(&2, S.Sdim, ds, n)), S.prod(List.take(&2, S.Sdim, ds, n))) == S.prod(ds) : Nat}:
  match ds:
    case Nil{}:
      {==}
    case d <> r:
      match n:
        case 0n:
          nat_mul_one_r(S.prod(d <> r))
        case 1n+p:
          +q = p
          +dd = d
          +rr = r
          ih = split(rr, q)
          dim = S.dim_of(dd)
          dropp = S.prod(List.drop(&2, S.Sdim, rr, q))
          takep = S.prod(List.take(&2, S.Sdim, rr, q))
          swapped = nat_mul_swap(dropp, dim, takep)
          sswap = Equal.sym(Nat, Nat.mul(dropp, Nat.mul(dim, takep)), Nat.mul(dim, Nat.mul(dropp, takep)), swapped)
          %sswap : {_ == Nat.mul(dim, S.prod(rr)) : Nat}
          sih = Equal.sym(Nat, Nat.mul(dropp, takep), S.prod(rr), ih)
          %sih : {Nat.mul(dim, _) == Nat.mul(dim, S.prod(rr)) : Nat}
          {==}

def reduce_numel_go(m: Maybe<&2, S.Shape>, n: Nat) -> {Nat.mul(S.dims_prod(S.Sp.shape.reduce(m, n)), S.prod(List.take(&2, S.Sdim, L.dims_of.go(m), n))) == S.dims_prod(m) : Nat}:
  match m:
    case None{}:
      {==}
    case Some{sh}:
      match sh:
        case S.Sh{ds}:
          split(ds, n)

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

# The law proofs.
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

# tinyspec Reduce: "remove the first n axes". The count of what remains times
# the product of the axes that were removed is the original count. The match
# lives in `reduce_numel_go` because a law binder is symbolic.
def L.reduce_numel_divides_by_the_reduced_axes(t, n):
  reduce_numel_go(S.Sp.shape(t), n)

def bcast_axes(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, ca: S.AllSN(a), cb: S.AllSN(b), same: S.SameLen(a, b)) -> {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}:
  match a:
    case Nil{}:
      match b:
        case Nil{}:
          {==}
        case _ <> _:
          match same:
    case S.SN{va} <> ra:
      match b:
        case Nil{}:
          match same:
        case S.SN{vb} <> rb:
          ih = bcast_axes(ra, rb, ca, cb, same)
          f = cons_head(S.SN{S.pick_dim(va, vb)})
          Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, f, S.zip_max(ra, rb), S.elem_pick(ra, rb), ih)
        case S.SS{_} <> _:
          match cb:
    case S.SS{_} <> _:
      match ca:

def L.broadcast_is_elementwise_max(a, b, sa, sb, pa, pb, same, ca, cb):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{sa}, pa)
  %spa : {S.dims_zip_max(_, S.Sp.shape(b)) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{sb}, pb)
  %spb : {S.dims_zip_max(Some{sa}, _) == Some{S.Sh{S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))}} : Maybe<&2, S.Shape>}
  ih = bcast_axes(S.Shape.to_dims(sa), S.Shape.to_dims(sb), ca, cb, same)
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(S.Shape.to_dims(sa), S.Shape.to_dims(sb)), S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb)), ih)
  Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(S.Shape.to_dims(sa), S.Shape.to_dims(sb))), S.Shape.of(S.elem_pick(S.Shape.to_dims(sa), S.Shape.to_dims(sb))), c1)

# V-ter. THE DEVICE COLUMN, and the spec's THIRD derived property.
#
# tinyspec: "Each UOp has five derived properties -- dtype, shape, device,
# addrspace, and min_max".  MEASURED 2026-11-17: the port had the dtype
# column and the shape column and NO device column.
def L.movement_preserves_device(a):
  {==}

def L.alu_preserves_device(a, b):
  {==}

def L.source_op_device_is_from_arg(size, dt, dev, addr):
  {==}

def L.copy_device_is_from_arg(buf, dev):
  {==}

def L.const_has_no_device(v, dt):
  {==}

def L.range_has_no_device(bound):
  {==}

def L.after_preserves_device(buf, deps):
  {==}

# AND THE CALL's device, which the spec gives as "first non-null src device".
def L.call_device_is_the_body_device(body, args):
  {==}

# AND THE STACK's device, which the spec's op table gives as "All shapes must
# match".
def L.stack_device_is_the_first_element_device(a, b):
  {==}

# AND THE MOVEMENT OPS' DTYPE, which the spec's table gives as one row for the
# whole family.
def L.reshape_preserves_dtype(t, src, dst):
  {==}

def L.permute_preserves_dtype(t, order):
  {==}

def L.expand_preserves_dtype(t, pre, total):
  {==}

def L.pad_preserves_dtype(t, off, size):
  {==}

def L.shrink_preserves_dtype(t, off, size):
  {==}

# AND THE TWO THAT ARE "from arg" AND NOT src[0]'s.
def L.bitcast_takes_the_target_dtype(t, dt):
  {==}

def L.cast_takes_the_target_dtype(t, dt):
  {==}

# AND THE TWO THE ALU CENSUS MEASURED AS UNPINNED.
def L.index_preserves_device(t, a):
  {==}

# AND THEIR DTYPE, which the spec's table gives as src[0].dtype for both.
def L.index_preserves_dtype(t, a):
  {==}

def L.reduce_preserves_dtype(t, ranges, op, n):
  {==}

def L.reduce_preserves_device(t, ranges, op, n):
  {==}

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

# AND THE COMPARISONS, WHICH THE SPEC'S TABLE PUTS IN THE SAME TABLE.  The
# shape fold's arms for `CmpLt`, `CmpEq` and `CmpNe` were UNPINNED -- the
# census named them -- and this is what pins them.
def L.cmp_lt_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

def L.cmp_eq_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

def L.cmp_ne_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

# AND THE INTEGER DIVISION PAIR, which the spec's derived-properties table
# covers as "Other binary" -- BROADCAST.
def L.truncdiv_is_elementwise(a, b, premise):
  %premise : {S.dims_zip_max(S.Sp.shape(a), _) == S.Sp.shape(a) : Maybe<&2, S.Shape>}
  ih = zip_maybe_idem(S.Sp.shape(a))
  %ih : {S.dims_zip_max(S.Sp.shape(a), S.Sp.shape(a)) == _ : Maybe<&2, S.Shape>}
  {==}

def L.truncmod_is_elementwise(a, b, premise):
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

# Both laws are closed. The measurements that justified the rulings:
#
# reduce, after `drop_n` became `List.drop` and the multiplier became
# `prod(List.take(dims, n))`: (4,) n=0 is 4==4; (4,5,6) n=1 is 120==120;
# n past the rank is 120==120; a symbolic axis is 0==0. `take(n+1)` is
# 16==4 and 600==120, false once drop is exact. `prod(drop)` is the kept
# product, 16==4 and 900==120, also false.
#
# broadcast count form, false as quantified: spec (SS,5)+(3,7) is 21==0;
# (5,0)+(3,) is 3==0; shapeless+(3,3) is 9==0. tinygrad (2,0)+(1,1) is a
# valid broadcast of shape (2, 0), so the count inequality is false there
# too. The axis rule on equal-length concrete shapes is what both do.

# ---------------------------------------------------------------------------
# THE ALU/DTYPE HALF (sections IV and V) -- the eighteen laws that the
# shape half above does not hold.  It comes AFTER the shape algebra
# because a def may only call a def DECLARED ABOVE it, and these
# proofs call no helper of their own.
#
# IV. tinyspec.tex "Decomposed elementwise ops" (lines 188-208): each op is
# DEFINED in terms of the primitives above it, so each is reflexive. No depth
# binder, then or now: none of these laws mentions shape_of, dtype_of or
# numel_of.
# tinyspec.tex:192  Neg = Mul(A, -1)
def L.neg_is_mul_by_minus_one(a):
  {==}

# tinyspec.tex:193  Sub = Add(A, Neg(B))
def L.sub_is_add_of_neg(a, b):
  {==}

# tinyspec.tex:194  Div = Mul(A, Recip(B))
def L.div_is_mul_by_recip(a, b):
  {==}

# tinyspec.tex:195  CmpGt = CmpLt(B, A)
def L.cmp_gt_is_cmp_lt_swapped(a, b):
  {==}

# tinyspec.tex:204  CmpGe = CmpEq(CmpLt(A, B), 0)
def L.cmp_ge_is_eq_of_cmp_lt(a, b):
  {==}

# tinyspec.tex:205  CmpLe = CmpEq(CmpLt(B, A), 0)
def L.cmp_le_is_eq_of_cmp_lt_swapped(a, b):
  {==}

# tinyspec.tex:206  CmpNe = CmpEq(CmpEq(A, B), 0)
def L.cmp_ne_is_eq_of_double_eq(a, b):
  {==}

# tinyspec.tex:173  CmpEq is PRIMITIVE elementwise equality
def L.cmp_eq_is_primitive(a, b):
  {==}

# tinyspec.tex:207  Not = CmpEq(A, 0)
def L.not_is_eq_zero(a):
  {==}

# tinyspec.tex:202  Truncmod = a - b * Truncdiv(a, b)
def L.truncmod_is_a_minus_b_times_truncdiv(a, b):
  {==}

# tinyspec.tex:205  Mulacc = Add(Mul(A, B), C)
def L.mulacc_is_add_of_mul(a, b, c):
  {==}

# V. tinyspec.tex "Derived Properties" dtype column: the arms of Sp.dtype that
# do not simply read src[0].
#
# All eight were OPEN and all eight are REFLEXIVE now. Before, the fold matched
# on a fuel it had computed as `2*depth+1` and its `case 2n+p:` arm was dead
# behind `case 1n+p:`, so every one of these compared None with Some{bool} or
# with None. The fold now reaches its own arm on the first call.
# tinyspec.tex:269  CmpLt, CmpNe: bool
def L.comparison_is_bool(a, b):
  {==}

def L.comparison_ne_is_bool(a, b):
  {==}

# THE COMPARISON THAT WAS MISSING.  MEASURED 2026-11-17: the spec IR had no
# `CmpEq` arm at all, so the spec's own primitive comparison -- the one
# tinyspec calls "primitive elementwise equality, returning bool (as do CmpLt
# and CmpNe)" -- could not be stated.
def L.comparison_eq_is_bool(a, b):
  {==}

# tinyspec.tex:271  Where: src[1].dtype. The arm is `Sp.dtype(b)`, so both
# sides are literally the same term.
def L.where_takes_the_second_operand_dtype(p, a, b):
  {==}

# tinyspec.tex:274  Store: void. "Output is void" is the arm `None{}`.
def L.store_is_void(buf, val, gate):
  {==}

# tinyspec.tex "A value Call is void" -- the arm is `None{}` again.
def L.call_is_void(body, args):
  {==}

# tinyspec.tex:275  Range: index
def L.range_is_index(bound):
  {==}

# tinyspec.tex "Binary: has dtype uint8"
def L.binary_is_uint8(size):
  {==}

# The marker ops are "identity on data": the arm is a tail call on the operand,
# so the subject and the premise normalise to one term.
def L.detach_preserves_dtype(a):
  {==}

# THE PASSTHROUGH OPS, WHOSE DTYPE THE SPEC'S TABLE GIVES AS src[0]'s.
def L.load_preserves_dtype(buf, alt, gate):
  {==}

def L.copy_preserves_dtype(buf, dev):
  {==}

def L.after_preserves_dtype(buf, deps):
  {==}

# AND THE TWO OPS THAT CAME WITH THE SPEC'S OWN DECOMPOSITIONS.
def L.truncdiv_preserves_dtype(a, b):
  {==}

def L.truncmod_preserves_dtype(a, b):
  {==}

# THE PASSTHROUGH OPS' SHAPE, and the spec says so in words.
def L.after_preserves_shape(buf, deps):
  {==}

def L.load_preserves_shape(buf, alt, gate):
  {==}

def L.copy_preserves_shape(buf, dev):
  {==}

def L.detach_preserves_numel(a):
  {==}
