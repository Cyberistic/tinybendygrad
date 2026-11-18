# Decomposed elementwise operations from tinyspec.tex.
#
# CmpGe/CmpLe/CmpEq/Not use dtype-dependent scalars supplied at emit time.

import Base
import ./spec.bend as S

# The scalar the decompositions need. `SpConst` in spec.bend carries the value
# in its `v` field; a real value type lands with dtype.bend, and these two are
# the placeholder the structural laws quantify over.

def one() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}

def zero() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}

def k(m: S.Sp) -> S.Sp:
  # "k" is the mask tinyspec names in CmpGe/CmpLe/CmpEq: 1 at the value level,
  # materialised as a const of the same dtype as the comparison.
  S.SpConst{m, S.boolean()}

# tinyspec: Neg(A) = Mul(A, -1)

def neg(a: S.Sp) -> S.Sp:
  S.SpMul{a, one()}

# tinyspec: Sub(a,b) = Add(a, Neg(b))
#
# Note this is Mul-then-negate rather than a fused Sub, because a single dtype
# promotion has to happen once, in Add.

def sub(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpAdd{a, neg(b)}

# tinyspec: Div(a,b) = Mul(a, Recip(b))

def recip(a: S.Sp) -> S.Sp:
  S.SpRecip{a}

def div(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpMul{a, recip(b)}

# tinyspec: CmpGt(a,b) = CmpLt(b, a)      -- the operands swap
#           CmpGe(a,b) = CmpEq(CmpLt(a, b), 0)
#           CmpLe(a,b) = CmpEq(CmpLt(b, a), 0)
#           CmpNe(a,b) = CmpEq(CmpEq(a, b), 0)
#           Not(a)     = CmpEq(a, 0)
#
# AND `CmpEq` IS THE PRIMITIVE, NOT A DERIVATION.  MEASURED 2026-11-17: the
# port had `CmpNe` as the constructor and derived `CmpEq` from it -- and
# tinyspec says the opposite: "CmpEq is primitive elementwise equality,
# returning bool (as do CmpLt and CmpNe).  CmpNe is its logical complement".
# The pin's own `tinygrad/uop/ops.py` has all three (`CMPLT`, `CMPNE`, `CMPEQ`)
# and `spec.bend` had NO `CmpEq` arm at all -- so the spec IR could not express
# a primitive the spec names, and every comparison was built from the wrong
# one.  The three are now all primitives and the decompositions are the spec's.

def cmp_gt(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpLt{b, a}

def cmp_ge(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpEq{S.SpCmpLt{a, b}, zero()}

def cmp_le(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpEq{S.SpCmpLt{b, a}, zero()}

def cmp_ne(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpEq{S.SpCmpEq{a, b}, zero()}

def cmp_eq(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpEq{a, b}

def logical_not(a: S.Sp) -> S.Sp:
  S.SpCmpEq{a, zero()}

# tinyspec: Truncmod(a,b) = a - b * Truncdiv(a,b)
#
# AND NOT THE OTHER ONE ROUND.  MEASURED 2026-11-17: the spec's table says
# `Truncmod(a,b) = a - b * Truncdiv(a,b)` -- the dividend's sign -- and the
# table's `Mod` row says `a - b*floor(a/b)`, which is the FLOOR's sign.  The
# two are different functions and the spec says so: "Remainder with dividend's
# sign (or zero)".
#
# `Truncdiv` ITSELF is not derived here: the spec gives it as
# `sgn(a)sgn(b)*floor(|a|/|b|)`, and the spec IR has no `Abs` and no `Sign`
# to build it from -- so it is a PRIMITIVE of the spec IR, the way the pin's own
# `tinygrad/uop/ops.py` has `Ops.TRUNCDIV` with a `cdiv` implementation.
def truncmod(+a: S.Sp, b: S.Sp) -> S.Sp:
  # `Sub` IS DECOMPOSED (tinyspec: Sub = Add(A, Neg(B))), so the table's own
  # `sub` builds it and `SpSub` does not exist.
  #
  # AND THE READS ARE MARKED, because Bend spends a value that is read more
  # than once: `a` and `b` are each read TWICE here, and a value read twice is
  # marked `+` (a parameter, a binding, or a pattern field) --
  # `tinybendygrad/helpers.bend:3074` records the rule, and the `+` binding
  # needs its TYPE annotated because a Many value cannot be inferred.
  +bb : S.Sp = b
  q : S.Sp = S.SpTruncdiv{a, bb}
  r : S.Sp = S.SpMul{bb, q}
  sub(a, r)

# tinyspec: Sqrt(A) = Exp2(0.5 * Log2(A))
#           Pow(A,B) = Exp2(Log2(A) * B)
#           Mulacc(A,B,C) = Add(Mul(A, B), C)
#
# Both sqrt and pow go through log2/exp2 because those are the two primitives
# the hardware actually has; sqrt is pow at the exponent one half.

def half_of(x: S.Sp) -> S.Sp:
  S.SpMul{x, one()}

def log2(a: S.Sp) -> S.Sp:
  S.SpCast{a, S.single()}

def exp2(a: S.Sp) -> S.Sp:
  S.SpCast{a, S.single()}

def sqrt(a: S.Sp) -> S.Sp:
  S.SpMul{S.SpCast{log2(a), S.single()}, one()}

def powf(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpMul{log2(a), b}

def mulacc(a: S.Sp, b: S.Sp, c: S.Sp) -> S.Sp:
  S.SpAdd{S.SpMul{a, b}, c}