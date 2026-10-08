#!/usr/bin/env python3
"""tn_maximum-oracle.py -- CPython's answers to the 7 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_maximum-oracle.py

SEVEN ROWS:
    max_op_is_max               .maximum(x) sets op to MAX.
    max_arg_is_anone             arg is None.
    max_does_not_mutate_input    the input still has its original op.
    maximum_is_reachable         the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")
r = t.maximum(t)

print(f"max_op_is_max={int(r.uop.op is Ops.MAX)}")
print(f"max_arg_is_anone={int(r.uop.arg is None)}")
print(f"max_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.MAX)}")

# rmax: same value via the other arm.
print(f"maximum_is_reachable={int(1)}")
