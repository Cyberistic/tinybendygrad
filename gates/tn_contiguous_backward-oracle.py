#!/usr/bin/env python3
"""tn_contiguous_backward-oracle.py -- CPython's answers to the 5 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_contiguous_backward-oracle.py

FIVE ROWS:
    contiguous_backward_op                    .contiguous_backward() sets op to CONTIGUOUS_BACKWARD.
    contiguous_backward_src_is_input          srcs are (self,).
    contiguous_backward_arg_is_anone          arg is None.
    contiguous_backward_does_not_mutate_input the input still has its original op.
    contiguous_backward_is_reachable          the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")
r = t.contiguous_backward()

print(f"contiguous_backward_op={int(r.uop.op is Ops.CONTIGUOUS_BACKWARD)}")
print(f"contiguous_backward_src_is_input={int(r.uop.src == (c,))}")
print(f"contiguous_backward_arg_is_anone={int(r.uop.arg is None)}")
print(f"contiguous_backward_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.CONTIGUOUS_BACKWARD)}")
print(f"contiguous_backward_is_reachable={int(1)}")
