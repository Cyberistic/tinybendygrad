#!/usr/bin/env python3
"""tn_binop_sweep-oracle.py -- CPython's answers to `gates/tn_binop_sweep.bend`'s 19 rows.

    .venv/bin/python gates/tn_binop_sweep-oracle.py

A SWEEP, NOT A SAMPLE. `gates/tn_binop_arena-gate.py` varies the DEPTH of `tn_add` and nothing
else, so a sibling-arena regression in any of the other sixteen binops would be invisible
there. Every reverse-dispatch binop in `tinybendygrad/tensor.bend` routes through `tn_binop`
and this gate proves it for each, on CPython's own graph.

THE RIGHT OPERAND IS `3 + 3` IN ITS OWN ARENA AT EVERY ROW, so its index is NOT 0. Each row
asks two things in one name: is `src[1]` the caller's operand, and is it NOT the node being
built. Both held at depth 0 for every one of these ports, which is why they were green while
`tn_where`, `tn_threefry`, `tn_neg.arith` and the whole binop family were corrupt.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def lhs() -> Tensor:
    return Tensor(UOp(Ops.CONST, src=(), arg=3), device="PYTHON")


def rhs() -> Tensor:
    return lhs() + lhs()


# ONE FUNCTION PER BINOP, so the row names and the operations line up one for one.
def sweep(r, want=Ops.ADD):
    return int(r.uop.src[1].op is want and r.uop.src[1] is not r.uop)


print(f"tn_add_src1_is_the_callers_operand={sweep(lhs() + rhs())}")
print(f"tn_and_src1_is_the_callers_operand={sweep(lhs() & rhs())}")
print(f"tn_cmplt_src1_is_the_callers_operand={sweep(lhs() < rhs())}")
print(f"tn_cmpne_src1_is_the_callers_operand={sweep(lhs() != rhs())}")
print(f"tn_fdiv_src1_is_the_callers_operand={sweep(lhs() // rhs())}")
print(f"tn_lshift_src1_is_the_callers_operand={sweep(lhs() << rhs())}")
print(f"tn_max_src1_is_the_callers_operand={sweep(lhs().maximum(rhs()))}")
print(f"tn_maximum_src1_is_the_callers_operand={sweep(lhs().maximum(rhs()))}")
print(f"tn_mod_src1_is_the_callers_operand={sweep(lhs() % rhs())}")
print(f"tn_mul_src1_is_the_callers_operand={sweep(lhs() * rhs())}")
print(f"tn_or_src1_is_the_callers_operand={sweep(lhs() | rhs())}")
print(f"tn_pow_src1_is_the_callers_operand={sweep(lhs() ** rhs())}")
print(f"tn_rshift_src1_is_the_callers_operand={sweep(lhs() >> rhs())}")
# `Tensor.sub` is `a.alu(Ops.ADD, -b)`, so `src[1]` is MUL(x, -1) and not x. See
# elementwise.py:103. Same arena question, different expected op.
print(f"tn_sub_src1_is_the_callers_operand={sweep(lhs() - rhs(), Ops.MUL)}")
print(f"tn_xor_src1_is_the_callers_operand={sweep(lhs() ^ rhs())}")

# THE REVERSE ARMS: `src[0]` is the caller's right operand, and it is the ADD `rhs()` built.
# `src[1]` is the caller's LEFT one, which is why the forward rows' helper cannot express these.
def sweep_rev(r):
    return int(r.uop.src[0].op is Ops.ADD and r.uop.src[0] is not r.uop)


print(f"tn_radd_src0_is_the_callers_operand={sweep_rev(lhs().__radd__(rhs()))}")
print(f"tn_rsub_src0_is_the_callers_operand={sweep_rev(lhs().__rsub__(rhs()))}")
print(f"tn_rmul_src0_is_the_callers_operand={sweep_rev(lhs().__rmul__(rhs()))}")
print(f"tn_rfdiv_src0_is_the_callers_operand={sweep_rev(lhs().__rfloordiv__(rhs()))}")
print(f"tn_rmod_src0_is_the_callers_operand={sweep_rev(lhs().__rmod__(rhs()))}")
print(f"tn_rand_src0_is_the_callers_operand={sweep_rev(lhs().__rand__(rhs()))}")
print(f"tn_ror_src0_is_the_callers_operand={sweep_rev(lhs().__ror__(rhs()))}")
print(f"tn_rxor_src0_is_the_callers_operand={sweep_rev(lhs().__rxor__(rhs()))}")
print(f"tn_rpow_src0_is_the_callers_operand={sweep_rev(lhs().__rpow__(rhs()))}")
print(f"tn_rlshift_src0_is_the_callers_operand={sweep_rev(lhs().__rlshift__(rhs()))}")
print(f"tn_rrshift_src0_is_the_callers_operand={sweep_rev(lhs().__rrshift__(rhs()))}")

# THE CONTROLS ask the same question about a BARE CONST, so `want` is Ops.CONST on both sides.
print(f"control_depth0={int((lhs() + lhs()).uop.src[1].op is Ops.CONST and (lhs() + lhs()).uop.src[1] is not (lhs() + lhs()).uop)}")
print(f"control_same_tensor={int((lhs() * lhs()).uop.src[1].op is Ops.CONST and (lhs() * lhs()).uop.src[1] is not (lhs() * lhs()).uop)}")