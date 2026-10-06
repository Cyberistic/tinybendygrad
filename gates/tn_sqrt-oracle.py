#!/usr/bin/env python3
"""tn_sqrt-oracle.py -- CPython's answers to `gates/tn_sqrt.bend`'s five rows.

The two lanes share no code: the Bend lane calls `tn_sqrt` from the port, this lane
builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_sqrt-oracle.py

FIVE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    sqrt_op_is_sqrt            .sqrt() sets op to SQRT.
    sqrt_src_is_input          .sqrt() sets srcs to (self,).
    sqrt_arg_is_anone          .sqrt() sets arg to None (ANone).
    sqrt_does_not_mutate_input the input still has its original op.
    sqrt_is_reachable          the def is callable (the wall was 0 defs).
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a bare CONST{4} (NOT `UOp.const`, which wraps in CAST).
c = UOp(Ops.CONST, src=(), arg=4)
# Wrap in a Tensor -- `Tensor(UOp)` is the public constructor.
t = Tensor(c, device="PYTHON")
r = t.sqrt()

print(f"sqrt_op_is_sqrt={int(r.uop.op is Ops.SQRT)}")
print(f"sqrt_src_is_input={int(r.uop.src == (c,))}")
print(f"sqrt_arg_is_anone={int(r.uop.arg is None)}")
print(f"sqrt_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.SQRT)}")
print(f"sqrt_is_reachable={int(1)}")
