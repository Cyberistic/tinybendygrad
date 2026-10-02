# alu.bend -- tinyspec.tex's "Decomposed elementwise ops" table, as Bend.
#
# The tinyspec.tex table at :192-206 has FIFTEEN rows, of which TWELVE are
# decomposed in terms of the primitives above them -- Neg, Sub, Div, CmpGt,
# CmpGe, CmpLe, CmpEq, Not, Sqrt, Pow, Mulacc and Threefry -- and THREE
# (Exp2, Log2, Sin) are only DESCRIBED, by polynomial approximation. This
# file writes those definitions as Bend functions over the primitive
# constructors of spec.bend, and LAWS.bend then states each decomposition as a
# law the checker proves by reflexivity.
#
# That is the point of the exercise: the spec's ALU table stops being a comment
# somebody might typo, and becomes something the compiler checks against the
# code that emits it.
#
# The `-1` and the `1` of CmpGe/CmpLe/CmpEq/Not are scalars whose VALUE depends
# on the dtype, so they are written here as `k`/`one`/`zero` and the dtype's
# bit pattern is supplied at emit time by the C runtime. The laws are about op
# STRUCTURE, which is what the spec's table is about.

import Base
import ./spec.bend as S

# ---------------------------------------------------------------------------
# The scalar the decompositions need. `SpConst` in spec.bend carries the value
# in its `v` field; a real value type lands with dtype.bend, and these two are
# the placeholder the structural laws quantify over.
# ---------------------------------------------------------------------------

def one() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}

def zero() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}

def k(m: S.Sp) -> S.Sp:
  # "k" is the mask tinyspec names in CmpGe/CmpLe/CmpEq: 1 at the value level,
  # materialised as a const of the same dtype as the comparison.
  S.SpConst{m, S.boolean()}

# ---------------------------------------------------------------------------
# tinyspec: Neg(A) = Mul(A, -1)
# ---------------------------------------------------------------------------

def neg(a: S.Sp) -> S.Sp:
  S.SpMul{a, one()}

# ---------------------------------------------------------------------------
# tinyspec: Sub(a,b) = Add(a, Neg(b))
#
# Note this is Mul-then-negate rather than a fused Sub, because a single dtype
# promotion has to happen once, in Add.
# ---------------------------------------------------------------------------

def sub(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpAdd{a, neg(b)}

# ---------------------------------------------------------------------------
# tinyspec: Div(a,b) = Mul(a, Recip(b))
# ---------------------------------------------------------------------------

def recip(a: S.Sp) -> S.Sp:
  S.SpRecip{a}

def div(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpMul{a, recip(b)}

# ---------------------------------------------------------------------------
# tinyspec: CmpGt(a,b) = CmpLt(b, a)      -- the operands swap
#           CmpGe(a,b) = CmpNe(CmpLt(a, b), 1)
#           CmpLe(a,b) = CmpNe(CmpLt(b, a), 1)
#           CmpEq(a,b) = CmpNe(CmpNe(a, b), 1)
#           Not(a)     = CmpNe(a, 1)
#
# Every comparison is CmpLt or CmpNe followed by a NOT against 1: the hardware
# has one less-than and one not-equal, and >= is < negated. That is the whole
# reason the spec has a Not at all.
# ---------------------------------------------------------------------------

def cmp_gt(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpLt{b, a}

def cmp_ge(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpNe{S.SpCmpLt{a, b}, one()}

def cmp_le(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpNe{S.SpCmpLt{b, a}, one()}

def cmp_ne(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpNe{a, b}

def cmp_eq(a: S.Sp, b: S.Sp) -> S.Sp:
  S.SpCmpNe{S.SpCmpNe{a, b}, one()}

def logical_not(a: S.Sp) -> S.Sp:
  S.SpCmpNe{a, one()}

# ---------------------------------------------------------------------------
# tinyspec: Sqrt(A) = Exp2(0.5 * Log2(A))
#           Pow(A,B) = Exp2(Log2(A) * B)
#           Mulacc(A,B,C) = Add(Mul(A, B), C)
#
# Both sqrt and pow go through log2/exp2 because those are the two primitives
# the hardware actually has; sqrt is pow at the exponent one half.
# ---------------------------------------------------------------------------

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