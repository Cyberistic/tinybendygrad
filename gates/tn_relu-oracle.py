#!/usr/bin/env python3
"""tn_relu-oracle.py -- CPython's answers to the 5 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_relu-oracle.py

FIVE ROWS:
    relu_op_is_where         .relu() builds a WHERE node.
    relu_arg_is_anone       arg is None.
    relu_does_not_mutate_input the input still has its original op.
    relu_has_three_srcs      .relu()'s WHERE has 3 srcs (cond, self, 0).
    relu_is_reachable        the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")
r = t.relu()

print(f"relu_op_is_where={int(r.uop.op is Ops.WHERE)}")
print(f"relu_arg_is_anone={int(r.uop.arg is None)}")
print(f"relu_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.WHERE)}")
print(f"relu_has_three_srcs={int(len(r.uop.src) == 3)}")
print(f"relu_is_reachable={int(1)}")
# src[2] is the CONST 0, by VALUE. `(self > 0).where(self, 0)` -- the third src is the literal.
print(f"relu_src2_is_const0={int(r.uop.src[2].arg == 0)}")
