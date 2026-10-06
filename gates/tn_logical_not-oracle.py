#!/usr/bin/env python3
"""tn_logical_not-oracle.py -- CPython's answers to `gates/tn_logical_not.bend`'s four rows.

The two lanes share no code: the Bend lane calls `tn_logical_not` from the port, this
lane builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_logical_not-oracle.py

FOUR ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    logical_not_op_is_cmpne                   .logical_not() builds a CMPNE.
    logical_not_arg_is_anone                   the CMPNE's arg is None.
    logical_not_does_not_mutate_input          the input still has its original op.
    logical_not_is_reachable                  the def is callable (the wall was 0 defs).
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a CONST{True} and wrap in a Tensor. CPython's `.logical_not` is
# `self.cast(dtypes.bool).ne(True)`, which on a bool input is identity.
c = UOp(Ops.CONST, src=(), arg=True)
t = Tensor(c, device="PYTHON")
r = t.logical_not()

print(f"logical_not_op_is_cmpne={int(r.uop.op is Ops.CMPNE)}")
print(f"logical_not_arg_is_anone={int(r.uop.arg is None)}")
print(f"logical_not_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.CMPNE)}")
print(f"logical_not_is_reachable={int(1)}")
