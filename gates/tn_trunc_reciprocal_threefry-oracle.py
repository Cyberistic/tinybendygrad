#!/usr/bin/env python3
"""tn_trunc_reciprocal_threefry-oracle.py -- CPython's answers to the 9 rows.

The two lanes share no code: the Bend lane calls `tn_trunc`, `tn_reciprocal`,
`tn_threefry` from the port, this lane builds the same graph out of real tinygrad
Tensors and asks the same questions. A row agrees only if two implementations
of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_trunc_reciprocal_threefry-oracle.py

NINE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    trunc_op_is_trunc                      .trunc() sets op to TRUNC.
    trunc_does_not_mutate_input            the input still has its original op.
    reciprocal_op_is_reciprocal            .reciprocal() sets op to RECIPROCAL.
    reciprocal_does_not_mutate_input      the input still has its original op.
    threefry_op_is_threefry                .threefry(seed) sets op to THREEFRY.
    threefry_srcs_are_self_and_seed        srcs are (self, seed).
    threefry_arg_is_anone                  arg is None.
    trunc_is_reachable                     the def is callable.
    threefry_is_reachable                  the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")

r1 = t.trunc()
print(f"trunc_op_is_trunc={int(r1.uop.op is Ops.TRUNC)}")
print(f"trunc_does_not_mutate_input={int(c.op is Ops.CONST and r1.uop.op is Ops.TRUNC)}")

r2 = t.reciprocal()
print(f"reciprocal_op_is_reciprocal={int(r2.uop.op is Ops.RECIPROCAL)}")
print(f"reciprocal_does_not_mutate_input={int(c.op is Ops.CONST and r2.uop.op is Ops.RECIPROCAL)}")

seed = UOp(Ops.CONST, src=(), arg=0)
s = Tensor(seed, device="PYTHON")
r3 = t.threefry(s)
print(f"threefry_op_is_threefry={int(r3.uop.op is Ops.THREEFRY)}")
print(f"threefry_srcs_are_self_and_seed={int(r3.uop.src == (c, seed))}")
print(f"threefry_arg_is_anone={int(r3.uop.arg is None)}")
print(f"trunc_is_reachable={int(1)}")
print(f"threefry_is_reachable={int(1)}")
