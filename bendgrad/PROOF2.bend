# PROOF2.bend -- the ALU/dtype half of the proof set.
#
# PROOF.bend holds the shape half (LAWS.bend sections I, II, III, VI, VII);
# this file holds the elementwise-decomposition half (IV) and the dtype half
# (V). LAWS/PROOF-ALL.bend imports both and is the aggregate gate.
#
# Every proof is `{==}`: a law names a def that IS that constructor tree, so
# both sides normalise to one term. What the proof buys is that alu.bend and
# spec.bend cannot drift from the tinyspec.tex table unnoticed.

import Base
import ./LAWS.bend as L

# ---------------------------------------------------------------------------
# IV. tinyspec.tex "Decomposed elementwise ops" (lines 188-208): each op is
# DEFINED in terms of the primitives above it, so each is reflexive.
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
# do not simply read src[0]. Each reduces to the right-hand side, so Where is
# reflexivity through one match and the rest are a constructor and its name.
# ---------------------------------------------------------------------------

# tinyspec.tex:272  CmpLt has dtype bool
def L.comparison_is_bool(a, b):
  {==}

# tinyspec.tex:272  CmpNe has dtype bool
def L.comparison_ne_is_bool(a, b):
  {==}

# tinyspec.tex:273  Where has dtype src[1].dtype
def L.where_takes_the_second_operand_dtype(p, a, b):
  {==}

# tinyspec.tex:277  Store is void
def L.store_is_void(buf, val, gate):
  {==}

# tinyspec.tex:274  Call is void
def L.call_is_void(body, args):
  {==}

# tinyspec.tex:275  Range has dtype index
def L.range_is_index(bound):
  {==}

# tinyspec.tex:59  Binary "has dtype uint8"
def L.binary_is_uint8(size):
  {==}
