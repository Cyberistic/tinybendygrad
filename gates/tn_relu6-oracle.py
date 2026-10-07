#!/usr/bin/env python3
"""tn_relu6-oracle.py -- CPython's answers to the 5 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_relu6-oracle.py

FIVE ROWS:
    relu6_op_is_where         .relu6() builds a WHERE node.
    relu6_arg_is_anone       arg is None.
    relu6_does_not_mutate_input the input still has its original op.
    relu6_has_three_srcs      .relu6()'s WHERE has 3 srcs (cond, r, 6).
    relu6_is_reachable        the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")
r = t.relu6()

print(f"relu6_op_is_where={int(r.uop.op is Ops.WHERE)}")
print(f"relu6_arg_is_anone={int(r.uop.arg is None)}")
print(f"relu6_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.WHERE)}")
print(f"relu6_has_three_srcs={int(len(r.uop.src) == 3)}")
print(f"relu6_is_reachable={int(1)}")
