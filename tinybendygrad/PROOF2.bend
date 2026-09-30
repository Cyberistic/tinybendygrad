# PROOF2.bend -- the ALU/dtype half of the proof set.
#
# PROOF.bend holds the shape half (LAWS.bend sections I, II, III, VI, VII);
# this file holds the elementwise-decomposition half (IV) and the dtype half
# (V). LAWS/PROOF-ALL.bend imports both and is the aggregate gate.
#
# Section IV is unaffected by the fuelled folds: those laws are DEFINED in
# terms of the op constructors, so a law names a def that IS that constructor
# tree, both sides normalise to one term, and `{==}` decides them. What the
# proof buys is that alu.bend and spec.bend cannot drift from the tinyspec.tex
# table unnoticed. All nine still check.
#
# Section V is the dtype fold, and it is fuelled, so it inherits PROOF.bend's
# two obstacles in full: a symbolic budget never reduces, and the `case 2n+p:`
# arm of `Sp.dtype.item` is dead behind `case 1n+p:`, making the fold the
# constant None. Those laws are left open with the reason recorded.

import Base
import ./LAWS.bend as L

# ---------------------------------------------------------------------------
# IV. tinyspec.tex "Decomposed elementwise ops" (lines 188-208): each op is
# DEFINED in terms of the primitives above it, so each is reflexive. No depth
# binder: none of these laws mentions shape_of, dtype_of or numel_of.
# ---------------------------------------------------------------------------

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

# tinyspec.tex:196  CmpGe = CmpNe(CmpLt(A, B), 1)
def L.cmp_ge_is_ne_of_cmp_lt(a, b):
  {==}

# tinyspec.tex:197  CmpLe = CmpNe(CmpLt(B, A), 1)
def L.cmp_le_is_ne_of_cmp_lt_swapped(a, b):
  {==}

# tinyspec.tex:198  CmpEq = CmpNe(CmpNe(A, B), 1)
def L.cmp_eq_is_double_neg(a, b):
  {==}

# tinyspec.tex:199  Not = CmpNe(A, 1)
def L.not_is_ne_one(a):
  {==}

# tinyspec.tex:205  Mulacc = Add(Mul(A, B), C)
def L.mulacc_is_add_of_mul(a, b, c):
  {==}

# ---------------------------------------------------------------------------
# V. tinyspec.tex "Derived Properties" dtype column: the arms of Sp.dtype that
# do not simply read src[0].
#
# All eight are OPEN. Each quantifies a depth budget, and each is blocked twice
# over -- see PROOF.bend for the two obstacles in full, both of which live in
# LAWS/spec.bend rather than here.
# ---------------------------------------------------------------------------

# REFUTED, not merely stuck. CmpLt's dtype column is bool, so at the one budget
# that reduces (depth 0n, fuel 1n) the fold answers None and the claim becomes
# None == Some{bool}. A fold that never reaches its own constructor arm cannot
# state a dtype law at all.
# law comparison_is_bool(depth, a, b)

# Refuted for the same reason as CmpLt: None == Some{bool}.
# law comparison_ne_is_bool(depth, a, b)

# STUCK, and over-claiming. Both sides are a stuck `Sp.dtype.item` at the same
# computed fuel, one on `One{SpWhere{p, a, b}}` and one on `One{b}`, so nothing
# reduces. Separately, tinyspec says Where's dtype is src[1]'s, and a fold that
# had to consult BOTH operands for shape would not have a single dtype to
# report; the two columns do not have to agree.
# law where_takes_the_second_operand_dtype(depth, p, a, b)

# STUCK. The claim is a stuck `Sp.dtype.item` on `One{SpStore{...}}` against
# None{}. It is true at depth 0n -- the fold answers None there for the wrong
# reason, having never matched the Store arm -- and undecidable for every
# symbolic budget.
# law store_is_void(depth, buf, val, gate)

# STUCK, and true for the wrong reason, exactly as Store is: the Call arm is
# below the dead `case 2n+p:`, so the fold answers None by decrementing, not by
# reading the arm that says "a value Call is void".
# law call_is_void(depth, body, args)

# REFUTED. Range's dtype column is index, so at the budget that reduces the
# claim is None == Some{index}.
# law range_is_index(depth, bound)

# REFUTED. Binary "has dtype uint8", so at the budget that reduces the claim is
# None == Some{uint8}.
# law binary_is_uint8(depth, size)
