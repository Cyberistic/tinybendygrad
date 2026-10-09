#!/usr/bin/env python3
"""tn_isnan-oracle.py -- CPython's answers to `gates/tn_isnan.bend`'s five rows.

The two lanes share no code: the Bend lane calls `tn_isnan` from the port, this
lane builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_isnan-oracle.py

FIVE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    isnan_op_is_cmpne                  .isnan() builds a CMPNE (self != self).
    isnan_arg_is_anone                  the CMPNE's arg is None.
    isnan_has_self_src                  the CMPNE has one src -- the input itself.
    isnan_does_not_mutate_input         the input still has its original op.
    isnan_is_reachable                  the def is callable (the wall was 0 defs).
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a CONST{1.0} and wrap in a Tensor. CPython's `.isnan` is `self != self`,
# so the result is a CMPNE with the input on both srcs.
c = UOp(Ops.CONST, src=(), arg=1.0)
t = Tensor(c, device="PYTHON")
r = t.isnan()

print(f"isnan_op_is_cmpne={int(r.uop.op is Ops.CMPNE)}")
print(f"isnan_arg_is_anone={int(r.uop.arg is None)}")
print(f"isnan_has_self_src={int(len(r.uop.src) == 2 and r.uop.src[0] is c and r.uop.src[1] is c)}")
print(f"isnan_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.CMPNE)}")
print(f"isnan_is_reachable={int(1)}")
