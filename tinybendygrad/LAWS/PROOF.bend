import Base
import ../LAWS.bend as L
import ./spec.bend as S
import ./alu.bend as A

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

# Append two lists.
def append(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>) -> List<&2, S.Sdim>:
  match a:
    case Nil{}: b
    case x <> xs: snoc(x, append(xs, b))

# A cons in the MIDDLE: the head and the tail are FIXED and the element is the
# ARGUMENT.  `cons_head` fixes the head and `cons_tail` fixes the tail, so
# neither can rewrite an element in the middle of a list -- and a law about a
# three-axis shape needs exactly that.
def cons_mid(h: S.Sdim, t: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):
  m => snoc(h, snoc(m, t))

# A cons at an ARBITRARY POSITION: the PREFIX is fixed, the element is the
# ARGUMENT and the SUFFIX is fixed.
def cons_at(prefix: List<&2, S.Sdim>, suffix: List<&2, S.Sdim>) -> (S.Sdim -> List<&2, S.Sdim>):
  x => append(prefix, snoc(x, suffix))

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
#
# AND THESE ARE THE THREE CASES OF `pick_dim` ITSELF, read as a MATCH on the
# count -- so the proof is the reduction and not a derivation.
def pick_dim_one_right(a: Nat) -> {S.pick_dim(a, 1n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n:
      {==}
    case 1n+1n+p:
      {==}

def pick_dim_one_left(b: Nat) -> {S.pick_dim(1n, b) == b : Nat}:
  {==}

def pick_dim_same(a: Nat) -> {S.pick_dim(a, a) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n:
      {==}
    case 1n+1n+p:
      {==}

# THE BROADCAST'S PER-AXIS VALUE, and it is the fact the spec's compositions
# need: the broadcast of `(M,K,1)` and `(1,K,N)` is `(M,K,N)`.
#
# AND THE PROOF IS AN INDUCTION on the two lists, with the THREE `pick_dim`
# CASES as its steps -- `pick_dim(M,1)` is `M`, `pick_dim(K,K)` is `K` and
# `pick_dim(1,N)` is `N`.
def elem_pick_gemm(m: Nat, k: Nat, n: Nat) -> {S.elem_pick([S.SN{m}, S.SN{k}, S.SN{1n}], [S.SN{1n}, S.SN{k}, S.SN{n}]) == [S.SN{m}, S.SN{k}, S.SN{n}] : List<&2, S.Sdim>}:
  # THE THREE AXES, ONE AT A TIME, AND THE MATCH IS ON THE COUNT SO THE
  # REDUCTION CAN HAPPEN.  `elem_pick` reads `pick_dim(va, vb)` per axis, and
  # `pick_dim` reduces only when the compiler can see the SHAPE of its two
  # arguments -- so each count is matched to a constructor first.
  #
  # AND THE MATCH ORDER IS THE ORDER OF FIRST USE -- m, then k, then n -- because
  # a binder cannot be matched after a LATER binder has been matched, and the
  # `pick_dim_same` HINT is LAST in every branch because a binder cannot be
  # matched after a local statement.
  match m:
    case 0n:
      match k:
        case 0n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n+1n+q:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
    case 1n:
      match k:
        case 0n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n+1n+q:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
    case 1n+1n+p:
      match k:
        case 0n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}
        case 1n+1n+q:
          match n:
            case 0n:
              {==}
            case 1n:
              {==}
            case 1n+1n+r:
              {==}

# AND THE `max_dim` VERSION OF THE THREE CASES, and they are what the
# COMPOSITION's goal needs: the broadcast's shape is built from `Shape.max_dim`,
# and `max_dim` IS `pick_dim` for two concrete dims.
def max_dim_one_right(a: S.Sdim) -> {S.Shape.max_dim(a, S.SN{1n}) == a : S.Sdim}:
  match a:
    case S.SN{v}:
      match v:
        case 0n:
          {==}
        case 1n:
          {==}
        case 1n+1n+p:
          {==}
    case S.SS{_}:
      {==}

def max_dim_one_left(b: S.Sdim) -> {S.Shape.max_dim(S.SN{1n}, b) == b : S.Sdim}:
  match b:
    case S.SN{v}:
      match v:
        case 0n:
          {==}
        case 1n:
          {==}
        case 1n+1n+p:
          {==}
    case S.SS{_}:
      {==}

def max_dim_same(a: S.Sdim) -> {S.Shape.max_dim(a, a) == a : S.Sdim}:
  match a:
    case S.SN{v}:
      match v:
        case 0n:
          {==}
        case 1n:
          {==}
        case 1n+1n+p:
          {==}
    case S.SS{_}:
      {==}

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

# V-ter-bis. The ALU OPS' DTYPE, which the spec's table gives as one row for
# the family: "ALU unary & src[0].dtype" and "Other binary & src[0].dtype".
def L.recip_takes_the_source_dtype(a):
  {==}

def L.trunc_takes_the_source_dtype(a):
  {==}

def L.add_takes_the_source_dtype(a, b):
  {==}

def L.mul_takes_the_source_dtype(a, b):
  {==}

def L.max_takes_the_source_dtype(a, b):
  {==}

def L.mod_takes_the_source_dtype(a, b):
  {==}

def L.idiv_takes_the_source_dtype(a, b):
  {==}

def L.xor_takes_the_source_dtype(a, b):
  {==}

def L.or_takes_the_source_dtype(a, b):
  {==}

def L.and_takes_the_source_dtype(a, b):
  {==}

def L.shr_takes_the_source_dtype(a, b):
  {==}

def L.shl_takes_the_source_dtype(a, b):
  {==}

def L.contiguous_backward_takes_the_source_dtype(a):
  {==}

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

# V-quater. THE MIN_MAX COLUMN, and the spec's FOURTH derived property.
#
# The two cells that need no NUMBER: "src[0]" and "dtype range".
def L.movement_preserves_min_max(a):
  {==}

def L.copy_preserves_min_max(buf, dev):
  {==}

def L.after_preserves_min_max(buf, deps):
  {==}

def L.bitcast_takes_the_dtype_range(a, dt):
  {==}

# V-quinquies. The SHAPE column for the ops the spec pins it on.
def L.buffer_shape_is_its_size(size, dt, dev, addr):
  {==}

def L.alloc_shape_is_its_size(size, dt, dev, addr):
  {==}

def L.const_shape_is_empty(v, dt):
  {==}

def L.load_shape_is_the_buffer_shape(buf, alt, gate):
  {==}

def L.copy_shape_is_the_buffer_shape(buf, dev):
  {==}

def L.cast_preserves_shape(t, dt):
  {==}

def L.bitcast_preserves_shape(t, dt):
  {==}

def L.range_shape_is_empty(bound):
  {==}

# AND THE PARAM's SHAPE, which the spec's column gives as "$(n)$ from src, or
# $()$".
def L.param_shape_is_its_size(size, dt, dev):
  {==}

# AND THE UNSHARD's SHAPE, WHICH IS NOT THE SPEC's -- the port answers
# "src[0]" WHOLE and the spec says "each a_k x n_k".
def L.unshard_preserves_the_source_shape(t, ranges, axes):
  {==}

# AND THE INDEX FAMILY'S SHAPE, which the spec's column gives as "remaining
# dims".
def L.index_of_no_operands_keeps_the_base_shape(t):
  {==}

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
#
# Each of the three is the SAME two steps -- rewrite `b`'s shape into `a`'s with
# the premise, then `zip_max(s, s) == s` lifted through `Shape.of` and `Some` --
# so the algebra is done once, in `zip_maybe_idem` above, and these three are one
# call each.
#
# NOT VACUOUS. The conclusion is not the premise: the subject is a broadcast of
# two INDEPENDENT shapes that happen to be equal, and it is wrong when they are
# not -- which is what `zip_max_idempotent` being a real theorem buys.
# `List.drop` of ZERO is the list itself, which is the base case the reduce's
# own unfolding lands on.  AND IT HAS TO RECURSE, because `List.drop` matches
# the list's head and a VARIABLE list is not a constructor: MEASURED, the
# one-step version is REFUSED with "expected: List.drop(...), observed: l".
def drop_zero(l: List<&2, S.Sdim>) -> {List.drop(&2, S.Sdim, l, 0n) == l : List<&2, S.Sdim>}:
  match l:
    case Nil{}:
      {==}
    case h <> t:
      ih = drop_zero(t)
      {==}


# THE REDUCE's FOLD, for a TWO-AXIS shape: the shape of a reduce is its input's
# shape with the first axis DROPPED, and `List.drop` of one is the tail.
def reduce_two(k: Nat, d: Nat) -> {S.Sp.shape.reduce(Some{S.Shape.of([S.SN{k}, S.SN{d}])}, 1n) == Some{S.Shape.of([S.SN{d}])} : Maybe<&2, S.Shape>}:
  {==}


# AND THE THIRD BROADCAST LEMMA: `(K, D)` WITH `(1, D)` IS `(K, D)` -- THE
# PRODUCT's BROADCAST, WHERE THE MASK IS THE LEFT OPERAND.  AND THE TWO AXES
# ARE `pick_dim(k, 1)` (WHICH IS `k`) AND `pick_dim(d, d)` (WHICH IS `d`).

# The `SN` constructor, as a FUNCTION, so `Equal.cong` can use it.
def sn_of(n: Nat) -> S.Sdim:
  S.SN{n}


# A ONE-ELEMENT LIST EQUALITY FROM A DIM EQUALITY, and it is a congruence
# under the cons with a fixed head.
def one_eq(a: S.Sdim, b: S.Sdim, e: {a == b : S.Sdim}) -> {snoc(a, Nil{}) == snoc(b, Nil{}) : List<&2, S.Sdim>}:
  +nil : List<&2, S.Sdim> = Nil{}
  f = cons_tail(nil)
  Equal.cong(S.Sdim, List<&2, S.Sdim>, f, a, b, e)

# A `Nat` EQUALITY LIFTED TO A DIM EQUALITY, because the BROADCAST's AXES ARE
# DIMs AND THE `pick_dim` FACTS ARE ABOUT COUNTS.  AND IT IS A CONGRUENCE UNDER
# THE `SN` CONSTRUCTOR, because `SN{a}` AND `SN{b}` ARE NOT DEFINITIONALLY
# EQUAL UNLESS `a` AND `b` ARE.
def sn_eq(a: Nat, b: Nat, e: {a == b : Nat}) -> {S.SN{a} == S.SN{b} : S.Sdim}:
  f = sn_of
  Equal.cong(Nat, S.Sdim, f, a, b, e)
def elem_pick_prod_mask(+k: Nat, +d: Nat) -> {S.elem_pick(snoc(S.SN{k}, snoc(S.SN{d}, Nil{})), snoc(S.SN{1n}, snoc(S.SN{d}, Nil{}))) == snoc(S.SN{k}, snoc(S.SN{d}, Nil{})) : List<&2, S.Sdim>}:
  # AND THE TWO AXES ARE TWO CONGRUENCES: THE FIRST UNDER A CONS WITH A FIXED
  # TAIL (`pick_dim(k, 1)` IS `k`) AND THE SECOND UNDER A CONS WITH A FIXED
  # HEAD (`pick_dim(d, d)` IS `d`).
  pr = pick_dim_one_right(k)
  ps = pick_dim_same(d)
  # AND THE WHOLE LIST, BY CONGRUENCE UNDER THE CONS WITH THE FIXED TAIL.
  +e : List<&2, S.Sdim> = Nil{}
  +t = snoc(S.SN{d}, e)
  pr1 = sn_eq(S.pick_dim(k, 1n), k, pr)
  ps1 = sn_eq(S.pick_dim(d, d), d, ps)
  # AND THE TWO AXES ARE REWRITTEN ONE AT A TIME, AND EACH REWRITE'S FUNCTION
  # FIXES THE OTHER AXIS -- SO THE FIRST REWRITE FIXES THE TAIL AND THE SECOND
  # FIXES THE HEAD.
  #
  # AND THE FIRST REWRITE IS UNDER A CONS WITH A FIXED TAIL, SO ITS TWO LISTS
  # ARE THE TWO WITH THE REWRITTEN TAIL.
  +tl = snoc(S.SN{d}, e)
  f1 = cons_tail(tl)
  c1 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f1, S.SN{S.pick_dim(k, 1n)}, S.SN{k}, pr1)
  # AND THE CHAIN, AND IT IS TWO STEPS: THE TAIL'S REWRITE RELATES THE FULLY
  # UNREWRITTEN LIST TO THE ONE WITH THE REWRITTEN TAIL, AND `c1` RELATES THAT
  # ONE TO THE ANSWER.
  +l0 = snoc(S.SN{S.pick_dim(k, 1n)}, snoc(S.SN{S.pick_dim(d, d)}, e))
  +l1 = snoc(S.SN{S.pick_dim(k, 1n)}, snoc(S.SN{d}, e))
  +l3 = snoc(S.SN{k}, snoc(S.SN{d}, e))
  # AND THE TAIL's REWRITE IS A CONGRUENCE UNDER THE PORT's `cons_at` -- WHICH
  # FIXES A PREFIX AND A SUFFIX AND TAKES THE ELEMENT AS ITS ARGUMENT -- SO ITS
  # ARGUMENT IS THE TAIL AND THE PREFIX IS THE HEAD.
  +pre = snoc(S.SN{S.pick_dim(k, 1n)}, e)
  f3 = cons_at(pre, e)
  c3 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f3, S.SN{S.pick_dim(d, d)}, S.SN{d}, ps1)
  Equal.trans(List<&2, S.Sdim>, l0, l1, l3, c3, c1)



# THE BROADCAST FOLD's UNFOLDING FOR TWO CONCRETE DIM LISTS: the fold of two
# `Some` shapes is `Some{Shape.of(zip_max(...))}`.
def zip_max_unfold(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>) -> {S.dims_zip_max(Some{S.Shape.of(a)}, Some{S.Shape.of(b)}) == Some{S.Shape.of(S.zip_max(a, b))} : Maybe<&2, S.Shape>}:
  {==}


# THE FOLD's ANSWER, LIFTED FROM THE `zip_max` FORM TO THE `elem_pick` FORM, and
# it is a CONGRUENCE under the fold with the two concrete shapes as its
# arguments.
def zip_max_to_elem(a: List<&2, S.Sdim>, b: List<&2, S.Sdim>, e: {S.zip_max(a, b) == S.elem_pick(a, b) : List<&2, S.Sdim>}) -> {S.dims_zip_max(Some{S.Shape.of(a)}, Some{S.Shape.of(b)}) == Some{S.Shape.of(S.elem_pick(a, b))} : Maybe<&2, S.Shape>}:
  # AND THE LIST EQUALITY IS LIFTED INTO THE SHAPE AND THEN INTO THE `Maybe`.
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(a, b), S.elem_pick(a, b), e)
  c2 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(a, b)), S.Shape.of(S.elem_pick(a, b)), c1)
  c2


# THE BROADCAST FOLD OF A SHAPE WITH A CONCRETE ONE, and of TWO SHAPES, as
# FUNCTIONS, so `Equal.cong` can relate the fold over the law's PREMISES to the
# fold over the CONCRETE shapes.
def fold_of_two(a: Maybe<&2, S.Shape>, b: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:
  S.dims_zip_max(a, b)

def fold_two(a: Maybe<&2, S.Shape>, b: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:
  S.dims_zip_max(a, b)


# THE BROADCAST FOLD, CURRIED: the first operand is fixed and the second is
# the argument, so `Equal.cong` can use it.
def fold_of(a: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):
  b => S.dims_zip_max(a, b)


# THE BROADCAST FOLD WITH ITS SECOND OPERAND FIXED, so the ARGUMENT is the
# FIRST operand -- the mask's shape.
def fold_first(b: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):
  a => S.dims_zip_max(a, b)


# The shape whose dims are a given list, named so `Equal.cong` can use it as
# a function.
def sh_of(l: List<&2, S.Sdim>) -> S.Shape:
  S.Sh{l}

# The `Some` of a shape, as a FUNCTION, so `Equal.cong` can use it: the port's
# `some_shape` is a `def` and a `def` does not unfold inside a congruence's
# conclusion -- MEASURED, the congruence then concludes `some_shape(a) ==
# some_shape(b)` where the goal says `Some{a} == Some{b}`.
def some_of_sh(sh: S.Shape) -> Maybe<&2, S.Shape>:
  Some{sh}


# THE `Maybe` VERSION OF `some_of_sh`, so `Equal.cong` CAN USE IT: THE SHAPE
# INSIDE THE `Some` IS THE ARGUMENT.
def some_of_maybe(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:
  match m:
    case Some{sh}: Some{sh}
    case None{}: None{}



# A PROBE: WHAT IS `List.drop([n, n], 1n)`?
def probe_drop(n: Nat) -> {List.drop(&2, S.Sdim, [S.SN{n}, S.SN{n}], 1n) == [S.SN{n}] : List<&2, S.Sdim>}:
  {==}


# THE DROP of ONE IS THE TAIL, and it is the port's own `List.drop` rule.
def drop_one_two(n: Nat) -> {List.drop(&2, S.Sdim, [S.SN{n}, S.SN{n}], 1n) == [S.SN{n}] : List<&2, S.Sdim>}:
  {==}

# The identity on a dim list, so `Equal.cong` can rewrite a list in place.
def elem_pick_of(l: List<&2, S.Sdim>) -> List<&2, S.Sdim>:
  l

# The reduce of a shape, as a FUNCTION, so `Equal.cong` can relate two
# reductions: the product's shape is `Some{Sh{[K, D]}}` by the law's premise,
# so the reduce of the product's shape is the reduce of that.
def reduce_of(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:
  S.Sp.shape.reduce(m, 1n)


# VI-ter. THE SPEC's GATHER COMPOSITION, and the claim is the NET SHAPE.
#
# tinyspec's "Common Ops as Compositions":
#
#   # gather: out[i] = T[idx[i]]. one-hot mask along gather axis, then reduce
#   def gather(T, idx):
#
# AND THE PROOF IS ONE `%` USE AND A CHAIN, and a `%` use REWRITES THE GOAL
# -- MEASURED, SEE `.agents/slop/loc/bend-proof-rules.md`: the fit check is
# `P(b, e) <= goal`, so THE MOTIVE IS "THE GOAL, WITH THE RIGHT-HAND SIDE
# REPLACED BY THE HOLE", and the new goal is `P(a, {==})`.
def L.gather_composition_has_the_gather_axis_shape(t, idx, k, d, pos, idxr, mask, tr, prod, out, pa, pb, pm, ptr, pp, cmask, cprod, cout, ca, ca2, cb, cc, same1, same2):
  # AND THE SHAPES' DIM LISTS, and the law's premises NAME them.
  +dp = snoc(S.SN{k}, snoc(S.SN{1n}, Nil{}))
  +di = snoc(S.SN{1n}, snoc(S.SN{d}, Nil{}))
  +dm = snoc(S.SN{k}, snoc(S.SN{d}, Nil{}))
  # THE MASK's SHAPE: the comparison's answer is the `zip_max` of its two
  # operands' shapes, and `bcast_axes` says `zip_max` is `elem_pick`.
  ih = bcast_axes(dp, di, ca, cb, same1)
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(dp, di), S.elem_pick(dp, di), ih)
  c2 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(dp, di)), S.Shape.of(S.elem_pick(dp, di)), c1)
  # AND THE PRODUCT's SHAPE: the same fold, with `(K, 1)` and the mask.
  ih2 = bcast_axes(dp, dm, ca2, cc, same2)
  c3 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(dp, dm), S.elem_pick(dp, dm), ih2)
  c4 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(dp, dm)), S.Shape.of(S.elem_pick(dp, dm)), c3)
  # AND THE EVIDENCE: THE REDUCE OF THE PRODUCT's SHAPE, and the product's
  # shape is `Some{Sh{[K, D]}}` BY THE LAW's PREMISE -- so the reduce of the
  # product's shape is the reduce of that, and the reduce of THAT is `(D,)`.
  rf = reduce_two(k, d)
  cr = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, reduce_of, S.Sp.shape(prod), Some{S.Shape.of([S.SN{k}, S.SN{d}])}, pp)
  # AND THE EVIDENCE IS ONE FACT, AND ITS RIGHT ENDPOINT IS THE GOAL's
  # RIGHT-HAND SIDE -- so the use's FIT CHECK PASSES -- AND ITS LEFT ENDPOINT
  # BECOMES THE NEW GOAL.
  ev = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape.reduce(S.Sp.shape(prod), 1n), S.Sp.shape.reduce(Some{S.Shape.of([S.SN{k}, S.SN{d}])}, 1n), Some{S.Shape.of([S.SN{d}])}, cr, rf)
  # AND THE `%` USE: the motive is the goal with the RIGHT-HAND SIDE replaced
  # by the hole, and the evidence's RIGHT endpoint IS the goal's right-hand
  # side -- so the fit check passes -- and the evidence's LEFT endpoint becomes
  # the NEW GOAL.
  %ev : {S.Sp.shape(out) == _ : Maybe<&2, S.Shape>}
  # AND THE NEW GOAL IS `{shape_of(out) == shape_of(SpReduce{prod, ...})}`, AND
  # THE BODY PROVES IT: the output IS the reduce.
  c5 = Equal.cong(S.Sp, Maybe<&2, S.Shape>, S.Sp.shape, out, S.SpReduce{prod, Nil{}, S.SpInvalid{}, 1n}, cout)
  %c5 : {S.Sp.shape(out) == _ : Maybe<&2, S.Shape>}
  {==}

# VI-quater. THE SPEC's SCATTER_ADD COMPOSITION, and the claim is the
# BROADCAST's shape.
#
# AND THE PROOF IS THE GATHER's PROOF WITH ONE OPERAND CHANGED: the mask's
# broadcast is `(K, 1)` with `(1, D)` and the product's is `(K, D)` with
# `(1, D)`.
def L.scatter_add_composition_broadcasts_to_the_key_shape(pos, idxr, valr, mask, prod, k, d, pa, pb, pv, pm, pp, cmask, cprod, ca, cb, cb2, cc, same1, same2):
  # AND THE SHAPES' DIM LISTS, and the law's premises NAME them.
  +dp = snoc(S.SN{k}, snoc(S.SN{1n}, Nil{}))
  +di = snoc(S.SN{1n}, snoc(S.SN{d}, Nil{}))
  +dm = snoc(S.SN{k}, snoc(S.SN{d}, Nil{}))
  # THE MASK's SHAPE: the comparison's answer is the `zip_max` of its two
  # operands' shapes, and `bcast_axes` says `zip_max` is `elem_pick`.
  ih = bcast_axes(dp, di, ca, cb, same1)
  c1 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.zip_max(dp, di), S.elem_pick(dp, di), ih)
  c2 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(S.zip_max(dp, di)), S.Shape.of(S.elem_pick(dp, di)), c1)
  # AND THE PRODUCT's SHAPE: the same fold, with the MASK and `(1, D)`.
  ih2 = bcast_axes(dm, di, cc, cb2, same2)
  # AND THE FOLD IS HEAD-ZIP, SO THE MASK IS ITS FIRST OPERAND -- AND A
  # CONGRUENCE THAT REPLACES AN OPERAND FIXES THE OTHERS.  SO THE ORDER IS:
  # `val`'s SHAPE IS REPLACED FIRST, AND THEN THE MASK's.
  #
  # AND EACH CONGRUENCE NEEDS ITS OWN PREMISE, BECAUSE A FACT CAN BE CONSUMED
  # ONLY ONCE.
  fv = fold_of(S.Sp.shape(mask))
  c4e = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, fv, S.Sp.shape(valr), Some{S.Shape.of(di)}, pv)
  fm = fold_first(Some{S.Shape.of(di)})
  c4f = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, fm, S.Sp.shape(mask), Some{S.Shape.of(dm)}, pm)
  # AND THE PRODUCT's SHAPE IS THE FOLD (BY THE CONSTRUCTION), AND THE FOLD
  # OVER THE CONCRETE SHAPES IS THE ELEM_PICK FORM (BY THE BROADCAST's LEMMA),
  # AND THAT IS THE CONCRETE ANSWER (BY THE LEMMA).
  #
  # AND THE LEMMA IS THE THIRD BROADCAST LEMMA: `(K, D)` WITH `(1, D)` IS
  # `(K, D)` -- THE PRODUCT's BROADCAST, WHERE THE MASK IS THE LEFT OPERAND.
  em = elem_pick_prod_mask(k, d)
  c5 = Equal.cong(List<&2, S.Sdim>, List<&2, S.Sdim>, elem_pick_of, S.elem_pick(dm, di), dm, em)
  c6b = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, S.elem_pick(dm, di), dm, c5)
  +ans = S.Shape.of([S.SN{k}, S.SN{d}])
  c6d = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_of_sh, S.Sh{S.elem_pick(dm, di)}, ans, c6b)
  c4d2 = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, some_of_maybe, Some{S.Sh{S.elem_pick(dm, di)}}, Some{ans}, c6d)
  # AND THE FOLD OVER THE CONCRETE SHAPES IS THE ELEM_PICK FORM.
  c4d = zip_max_to_elem(dm, di, ih2)
  # AND THE CHAIN.
  cp = Equal.cong(S.Sp, Maybe<&2, S.Shape>, S.Sp.shape, prod, S.SpMul{mask, valr}, cprod)
  ev = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape(prod), S.dims_zip_max(S.Sp.shape(mask), S.Sp.shape(valr)), S.dims_zip_max(S.Sp.shape(mask), Some{S.Shape.of(di)}), cp, c4e)
  ev2 = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape(prod), S.dims_zip_max(S.Sp.shape(mask), Some{S.Shape.of(di)}), S.dims_zip_max(Some{S.Shape.of(dm)}, Some{S.Shape.of(di)}), ev, c4f)
  ev4 = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape(prod), S.dims_zip_max(Some{S.Shape.of(dm)}, Some{S.Shape.of(di)}), Some{ans}, ev2, c4d2)
  %ev4 : {S.Sp.shape(prod) == _ : Maybe<&2, S.Shape>}
  # AND THE BODY IS `{==}`: THE USE's NEW GOAL IS REFLEXIVE, BECAUSE THE
  # EVIDENCE's LEFT ENDPOINT IS `shape(prod)` ITSELF.
  {==}

# THE REDUCE's FOLD OVER A TWO-AXIS SHAPE OF EQUAL AXES, and the answer is the
# one-axis shape.
# VI-quinquies. THE SPEC's PREFIX_SUM COMPOSITION, and the claim is the NET
# SHAPE.
#
# AND THE PROOF IS THE GATHER's PROOF WITH ONE STEP'S FOLD INSTEAD OF TWO
# BROADCASTS: THE REDUCE's FOLD IS THE SHAPE WITH THE FIRST AXIS DROPPED, AND
# THE WINDOWS' SHAPE IS `(n, n)`.
def L.prefix_sum_composition_has_the_input_shape(t, n, padded, tiled, trimmed, windows, out, spadded, stiled, strimmed, swindows, sout, pt, ppadded, ptiled, ptrimmed, pwindows, pout, cpad, cwin, cout, ca):
  # AND THE WINDOWS' DIM LIST, AND THE LAW's PREMISE NAMES IT.
  +dw = snoc(S.SN{n}, snoc(S.SN{n}, Nil{}))
  # AND THE REDUCE's FOLD: the shape of a reduce is its input's shape with the
  # first axis DROPPED -- and the input is the WINDOWS, whose shape is `(n, n)`.
  # AND THE EVIDENCE: THE REDUCE OF THE WINDOWS' SHAPE, AND THE WINDOWS' SHAPE
  # IS `Some{Sh{[n, n]}}` BY THE LAW's PREMISE -- so the reduce of the
  # windows' shape is the reduce of that, and the reduce of THAT IS `(n,)`,
  # DEFINITIONALLY: MEASURED, THE PORT's OWN `reduce_two` IS `{==}` FOR THE
  # SAME SHAPE.
  cp = Equal.cong(S.Sp, Maybe<&2, S.Shape>, S.Sp.shape, out, S.SpReduce{windows, Nil{}, S.SpInvalid{}, 1n}, cout)
  cr = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, reduce_of, S.Sp.shape(windows), Some{S.Shape.of([S.SN{n}, S.SN{n}])}, pwindows)
  ev = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape.reduce(S.Sp.shape(windows), 1n), S.Sp.shape.reduce(Some{S.Shape.of([S.SN{n}, S.SN{n}])}, 1n), Some{S.Shape.of([S.SN{n}])}, cr, reduce_two(n, n))
  # AND THE `%` USE: the motive is the goal with the RIGHT-HAND SIDE replaced
  # by the hole, and the evidence's RIGHT endpoint IS the goal's right-hand
  # side -- so the fit check passes -- and the evidence's LEFT endpoint becomes
  # the NEW GOAL.
  %ev : {S.Sp.shape(out) == _ : Maybe<&2, S.Shape>}
  # AND THE BODY: THE OUTPUT IS THE REDUCE.
  cp



# AND THE NEGATED CONSTANT's EQUALITY, and it is the port's own decomposition:
# `neg(a)` IS `Mul(a, one)`.
def alu_neg_one_eq() -> {A.neg(A.one()) == S.SpMul{A.one(), A.one()} : S.Sp}:
  {==}

# AND THE CONSTANT's OWN SHAPE ARM, and it is the port's own law.
def const_shape() -> {S.Sp.shape(A.one()) == Some{S.Shape.empty()} : Maybe<&2, S.Shape>}:
  {==}

# AND THE IDENTITY ON A `Maybe<Shape>`, so a congruence can relate the fold's
# answer to the shape it is.
def id_maybe(m: Maybe<&2, S.Shape>) -> Maybe<&2, S.Shape>:
  m

# AND THE CURRIED FOLD: ONE FUNCTION PER FIXED OPERAND, so `Equal.cong` CAN
# USE THEM -- A CONGRUENCE's FUNCTION IS UNARY.  AND THE FOLD IS
# `dims_zip_max`, WHICH ANSWERS `Some{Shape.of(zip_max(...))}`.
def zip_max_first(a: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):
  b => S.dims_zip_max(a, b)

def zip_max_second(b: Maybe<&2, S.Shape>) -> (Maybe<&2, S.Shape> -> Maybe<&2, S.Shape>):
  a => S.dims_zip_max(a, b)

# AND THE NEGATED CONSTANT, and it is the port's own `A.neg(A.one())`.
def alu_neg_one() -> S.Sp:
  A.neg(A.one())
# VI-sex. THE SPEC's ARANGE COMPOSITION, and the claim is the NET SHAPE.
#
# AND THE PROOF NEEDS NO BROADCAST LEMMA, AND THAT IS A MEASURED FACT: the
# broadcast of `(n,)` WITH `()` IS UNEQUAL-LENGTH, AND THE PORT's `elem_pick`
# TRUNCATES AT THE SHORTER LIST WHILE `zip_max` KEEPS THE LONGER's REMAINDER --
# SO THE TWO DISAGREE AND THE PORT's `bcast_axes` LEMMA DOES NOT APPLY.
#
# BUT THE FOLD's OWN ANSWER IS ENOUGH: `zip_max([n], [])` IS `[n]` BY `zip_max`'s
# OWN RULE (`case Nil{}: a`), SO THE CLAIM IS DEFINITIONAL.
def L.arange_composition_has_the_expanded_shape(n, one, reshaped, expanded, summed, out, sone, sreshaped, sexpanded, ssummed, sout, pone, preshaped, pexpanded, psummed, pout, cones, creshape, cexpand, cout):
  # AND THE CONSTANT one's SHAPE IS EMPTY -- "A scalar constant with shape ()" --
  # AND THE SUM's SHAPE IS `(n)`.
  +se = S.Shape.empty()
  +sn = S.Shape.of([S.SN{n}])
  # AND THE BROADCAST OF `(n)` WITH `()` IS UNEQUAL-LENGTH, AND THE PORT's
  # `elem_pick` TRUNCATES AT THE SHORTER LIST WHILE `zip_max` KEEPS THE
  # LONGER's REMAINDER -- SO THE PORT's `bcast_axes` LEMMA DOES NOT APPLY.
  # BUT `zip_max([n], [])` IS `[n]` BY `zip_max`'s OWN RULE (`case Nil{}: a`),
  # SO THE CLAIM IS DEFINITIONAL AND NO LEMMA IS NEEDED.
  #
  # AND THE CHAIN IS FIVE STEPS: THE OUTPUT's SHAPE IS THE SUBTRACT's FOLD (BY
  # THE CONSTRUCTION), THE SUBTRACT IS `Add(summed, Neg(one))` AND `Neg(one)` IS
  # `Mul(one, one)` (BY THE PORT's OWN DECOMPOSITIONS), THE CONSTANT's SHAPE IS
  # EMPTY (BY THE CONSTANT's OWN ARM), AND THE ADD's FOLD IS THE `zip_max` OF
  # THE TWO OPERANDS' SHAPES (BY THE FOLD).
  c1 = Equal.cong(S.Sp, Maybe<&2, S.Shape>, S.Sp.shape, out, A.sub(summed, A.one()), cout)
  # AND THE NEGATED CONSTANT IS THE PORT's OWN `Mul(one, one)`.
  c2 = Equal.cong(S.Sp, Maybe<&2, S.Shape>, S.Sp.shape, alu_neg_one(), S.SpMul{A.one(), A.one()}, alu_neg_one_eq)
  # AND THE NEGATED CONSTANT's SHAPE IS THE `zip_max` OF THE TWO CONSTANTS'
  # SHAPES -- AND BOTH ARE EMPTY.
  c3 = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, zip_max_first(S.Sp.shape(A.one())), S.Sp.shape(A.one()), Some{se}, const_shape)
  c4 = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, zip_max_first(S.Sp.shape(A.one())), S.Sp.shape(alu_neg_one()), Some{se}, c3)
  # AND THE ADD's FOLD IS THE `zip_max` OF THE SUM's SHAPE AND THE NEGATED
  # CONSTANT's, AND WITH AN EMPTY ONE THE ANSWER IS THE SUM's.
  c5 = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, zip_max_second(S.Sp.shape(alu_neg_one())), S.Sp.shape(summed), Some{sn}, psummed)
  c6 = Equal.cong(Maybe<&2, S.Shape>, Maybe<&2, S.Shape>, id_maybe, S.dims_zip_max(S.Sp.shape(summed), S.Sp.shape(alu_neg_one())), Some{sn}, c5)
  ev = Equal.trans(Maybe<&2, S.Shape>, S.Sp.shape(out), S.dims_zip_max(S.Sp.shape(summed), S.Sp.shape(alu_neg_one())), Some{sn}, c1, c6)
  %ev : {S.Sp.shape(out) == _ : Maybe<&2, S.Shape>}
  {==}
# VI-oct. THE INDEX FAMILY's SHAPE, AND THE PROOF IS ONE STEP: THE FOLD IS
# A CONCATENATION AND A DROP, SO NEITHER IS A ZIP AND NO INDUCTION IS NEEDED.
#
# AND THE OLD NOTE SAID THE INDUCTION WAS NEEDED -- "the zip's shape and the
# drop's shape together" -- AND THAT WAS TRUE OF A DIFFERENT FOLD.  THE FOLD IS
# `Shape.of(append(index_dims, drop_n(base_dims, k)))`, SO IT IS A
# CONCATENATION AND A DROP.
#
# AND THE `%` USES CASCADE: EACH ONE REPLACES ONE SLOT OF THE FOLD's `pre`, AND
# THE NEXT ONE's MOTIVE REFLECTS THE REPLACEMENT -- AND THE MOTIVE IS THE GOAL
# WITH THAT SLOT REPLACED BY THE HOLE, SO THE FIT CHECK IS THE GOAL.

def L.index_one_with_an_empty_shape_removes_the_base_dim(t, a, st, pt, pa):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{S.Shape.empty()}, pa)
  %spa : {S.Sp.shape.index(_, S.Sp.shape(t), 1n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 1n))} : Maybe<&2, S.Shape>}
  spt = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{st}, pt)
  %spt : {S.Sp.shape.index(Some{S.Shape.empty()}, _, 1n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 1n))} : Maybe<&2, S.Shape>}
  {==}

def L.index_two_with_empty_shapes_removes_two_base_dims(t, a, b, st, pt, pa, pb):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{S.Shape.empty()}, pa)
  %spa : {S.Sp.shape.index(S.dims_append(_, S.Sp.shape(b)), S.Sp.shape(t), 2n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 2n))} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{S.Shape.empty()}, pb)
  %spb : {S.Sp.shape.index(S.dims_append(Some{S.Shape.empty()}, _), S.Sp.shape(t), 2n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 2n))} : Maybe<&2, S.Shape>}
  spt = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{st}, pt)
  %spt : {S.Sp.shape.index(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), _, 2n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 2n))} : Maybe<&2, S.Shape>}
  {==}

def L.index_three_with_empty_shapes_removes_three_base_dims(t, a, b, c, st, pt, pa, pb, pc):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{S.Shape.empty()}, pa)
  %spa : {S.Sp.shape.index(S.dims_append(S.dims_append(_, S.Sp.shape(b)), S.Sp.shape(c)), S.Sp.shape(t), 3n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 3n))} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{S.Shape.empty()}, pb)
  %spb : {S.Sp.shape.index(S.dims_append(S.dims_append(Some{S.Shape.empty()}, _), S.Sp.shape(c)), S.Sp.shape(t), 3n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 3n))} : Maybe<&2, S.Shape>}
  spc = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(c), Some{S.Shape.empty()}, pc)
  %spc : {S.Sp.shape.index(S.dims_append(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), _), S.Sp.shape(t), 3n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 3n))} : Maybe<&2, S.Shape>}
  spt = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{st}, pt)
  %spt : {S.Sp.shape.index(S.dims_append(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), Some{S.Shape.empty()}), _, 3n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 3n))} : Maybe<&2, S.Shape>}
  {==}

def L.index_four_with_empty_shapes_removes_four_base_dims(t, a, b, c, d, st, pt, pa, pb, pc, pd):
  spa = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(a), Some{S.Shape.empty()}, pa)
  %spa : {S.Sp.shape.index(S.dims_append(S.dims_append(S.dims_append(_, S.Sp.shape(b)), S.Sp.shape(c)), S.Sp.shape(d)), S.Sp.shape(t), 4n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 4n))} : Maybe<&2, S.Shape>}
  spb = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(b), Some{S.Shape.empty()}, pb)
  %spb : {S.Sp.shape.index(S.dims_append(S.dims_append(S.dims_append(Some{S.Shape.empty()}, _), S.Sp.shape(c)), S.Sp.shape(d)), S.Sp.shape(t), 4n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 4n))} : Maybe<&2, S.Shape>}
  spc = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(c), Some{S.Shape.empty()}, pc)
  %spc : {S.Sp.shape.index(S.dims_append(S.dims_append(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), _), S.Sp.shape(d)), S.Sp.shape(t), 4n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 4n))} : Maybe<&2, S.Shape>}
  spd = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(d), Some{S.Shape.empty()}, pd)
  %spd : {S.Sp.shape.index(S.dims_append(S.dims_append(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), Some{S.Shape.empty()}), _), S.Sp.shape(t), 4n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 4n))} : Maybe<&2, S.Shape>}
  spt = Equal.sym(Maybe<&2, S.Shape>, S.Sp.shape(t), Some{st}, pt)
  %spt : {S.Sp.shape.index(S.dims_append(S.dims_append(S.dims_append(Some{S.Shape.empty()}, Some{S.Shape.empty()}), Some{S.Shape.empty()}), Some{S.Shape.empty()}), _, 4n) == Some{S.Shape.of(S.drop_n(S.Shape.to_dims(st), 4n))} : Maybe<&2, S.Shape>}
  {==}

# VI-bis. THE SPEC'S OWN COMPOSITION, and the shape it claims.
#
# tinyspec's "Common Ops as Compositions": "def gemm(A, B): M,K = A.shape; _,N =
# B.shape; return (A.reshape(M,K,1) * B.reshape(1,K,N)).sum(1)".
def L.gemm_broadcasts_to_the_three_axis_shape(m, k, n, ma, mb, same):
  # THE GOAL IS ABOUT THE BROADCAST'S SHAPE, and the broadcast's shape is
  # `zip_max` of the two dims lists -- and `zip_max` builds its head with
  # `Shape.max_dim` while `elem_pick` builds its head with `pick_dim`, and for
  # two CONCRETE dims those are the same function.  So the three axes are three
  # `max_dim` facts, and each is one of the port's `max_dim` lemmas.
  #
  # AND EACH AXIS IS ONE CONGRUENCE, and each congruence's FUNCTION fixes
  # everything EXCEPT the axis it rewrites:
  #
  # AND THE THREE DIMS ARE BOUND WITH `+`, because each is READ MORE THAN ONCE
  # -- once in the goal, once in its lemma and once in the lists -- and a value
  # that is read twice must be bound with `+`.
  +mm = m
  +kk = k
  +nn = n
  +d1 = S.Shape.max_dim(mm, S.SN{1n})
  +d2 = S.Shape.max_dim(kk, kk)
  +d3 = S.Shape.max_dim(S.SN{1n}, nn)
  a1 = max_dim_one_right(mm)
  a2 = max_dim_same(kk)
  a3 = max_dim_one_left(nn)
  # AND THE EMPTY LIST IS BOUND ONCE, because a `Nil{}` INSIDE A CALL ARGUMENT
  # is a parse error -- the constructor's braces are read as a call's -- and
  # because the operator needs its type spelled out.
  +e : List<&2, S.Sdim> = Nil{}
  # THE LAST AXIS: the tail is EMPTY and the prefix is the first two axes.
  +t3 = e
  +pre3 = snoc(mm, snoc(kk, e))
  f3 = cons_at(pre3, t3)
  c3 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f3, d3, nn, a3)
  # THE MIDDLE AXIS: the tail is the LAST axis and the head is the FIRST.
  +t2 = snoc(d3, e)
  f2 = cons_mid(mm, t2)
  c2 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f2, d2, kk, a2)
  # AND THE FIRST AXIS: the tail is the last TWO axes.
  +t1 = snoc(d2, snoc(d3, e))
  f1 = cons_tail(t1)
  c1 = Equal.cong(S.Sdim, List<&2, S.Sdim>, f1, d1, mm, a1)
  # AND THE THREE ARE CHAINED: `c1` concludes `p1 == q1` (the head rewritten),
  # `c2` concludes `q1 == q2` (the middle rewritten) and `c3` concludes
  # `q2 == p4` (the last rewritten).  `Equal.trans` chains two facts at a time,
  # so the whole equality is `c1` and then `q1 == p4`.
  +p1 = snoc(d1, snoc(d2, snoc(d3, e)))
  +q1 = snoc(mm, snoc(d2, snoc(d3, e)))
  +q2 = snoc(mm, snoc(kk, snoc(d3, e)))
  +p4 = snoc(mm, snoc(kk, snoc(nn, e)))
  e2 = Equal.trans(List<&2, S.Sdim>, q1, q2, p4, c2, c3)
  e3 = Equal.trans(List<&2, S.Sdim>, p1, q1, p4, c1, e2)
  # AND THE WHOLE LIST, by congruence under `of_shape` and then under
  # `some_shape` -- the two wrappers the goal has on either side.
  c4 = Equal.cong(List<&2, S.Sdim>, S.Shape, of_shape, p1, p4, e3)
  c5 = Equal.cong(S.Shape, Maybe<&2, S.Shape>, some_shape, S.Shape.of(p1), S.Shape.of(p4), c4)
  c5

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
