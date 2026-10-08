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
print(f"tn_shl_src1_is_the_callers_operand={sweep(lhs() << rhs())}")
print(f"tn_shr_src1_is_the_callers_operand={sweep(lhs() >> rhs())}")
# `Tensor.sub` is `a.alu(Ops.ADD, -b)`, so `src[1]` is MUL(x, -1) and not x. See
# elementwise.py:103. Same arena question, different expected op.
print(f"tn_sub_src1_is_the_callers_operand={sweep(lhs() - rhs(), Ops.MUL)}")
print(f"tn_xor_src1_is_the_callers_operand={sweep(lhs() ^ rhs())}")

# THE CONTROLS ask the same question about a BARE CONST, so `want` is Ops.CONST on both sides.
print(f"control_depth0={int((lhs() + lhs()).uop.src[1].op is Ops.CONST and (lhs() + lhs()).uop.src[1] is not (lhs() + lhs()).uop)}")
print(f"control_same_tensor={int((lhs() * lhs()).uop.src[1].op is Ops.CONST and (lhs() * lhs()).uop.src[1] is not (lhs() * lhs()).uop)}")