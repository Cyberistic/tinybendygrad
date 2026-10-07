#!/usr/bin/env python3
"""tn_where-oracle.py -- CPython's answers to the 5 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_where-oracle.py

FIVE ROWS:
    where_op_is_where            .where(x, y) sets op to WHERE.
    where_arg_is_anone          arg is None.
    where_srcs_are_cond_x_y     srcs are (cond, x, y).
    where_does_not_mutate_input the input still has its original op.
    where_is_reachable          the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

cond = Tensor(UOp(Ops.CONST, src=(), arg=True), device="PYTHON")
x = Tensor(UOp(Ops.CONST, src=(), arg=3), device="PYTHON")
y = Tensor(UOp(Ops.CONST, src=(), arg=5), device="PYTHON")
r = cond.where(x, y)

print(f"where_op_is_where={int(r.uop.op is Ops.WHERE)}")
print(f"where_arg_is_anone={int(r.uop.arg is None)}")
print(f"where_srcs_are_cond_x_y={int(len(r.uop.src) == 3 and r.uop.src[0] is cond.uop and r.uop.src[1] is x.uop and r.uop.src[2] is y.uop)}")
print(f"where_does_not_mutate_input={int(cond.uop.op is Ops.CONST and r.uop.op is Ops.WHERE)}")
print(f"where_is_reachable={int(1)}")
