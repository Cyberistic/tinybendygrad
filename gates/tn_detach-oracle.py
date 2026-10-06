#!/usr/bin/env python3
"""tn_detach-oracle.py -- CPython's answers to `gates/tn_detach.bend`'s five rows.

The two lanes share no code: the Bend lane calls `tn_detach` from the port, this lane
builds the same graph out of real tinygrad Tensors and asks the same questions. A
row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_detach-oracle.py

FIVE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    detach_op_is_detach          .detach() sets op to DETACH.
    detach_src_is_input          .detach() sets srcs to (self,).
    detach_arg_is_anone          .detach() sets arg to None.
    detach_does_not_mutate_input the input still has its original op.
    detach_is_reachable          the def is callable (the wall was 0 defs).
"""

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Build a bare CONST{4} (NOT `UOp.const`, which wraps in CAST).
c = UOp(Ops.CONST, src=(), arg=4)
# Wrap in a Tensor -- `Tensor(UOp)` is the public constructor.
t = Tensor(c, device="PYTHON")
r = t.detach()

print(f"detach_op_is_detach={int(r.uop.op is Ops.DETACH)}")
print(f"detach_src_is_input={int(r.uop.src == (c,))}")
print(f"detach_arg_is_anone={int(r.uop.arg is None)}")
print(f"detach_does_not_mutate_input={int(c.op is Ops.CONST and r.uop.op is Ops.DETACH)}")
print(f"detach_is_reachable={int(1)}")
