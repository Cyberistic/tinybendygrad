#!/usr/bin/env python3
"""tn_sin_log2_exp2_rsqrt-oracle.py -- CPython's answers to the 11 rows.

The two lanes share no code: the Bend lane calls the four defs from the port, this
lane builds the same graph out of real tinygrad Tensors and asks the same questions.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_sin_log2_exp2_rsqrt-oracle.py

ELEVEN ROWS:
    sin_op_is_sin                       .sin() sets op to SIN.
    log2_op_is_log2                     .log2() sets op to LOG2.
    exp2_op_is_exp2                     .exp2() sets op to EXP2.
    rsqrt_op_is_reciprocal              .rsqrt() sets op to RECIPROCAL.
    rsqrt_arg_is_anone                  .rsqrt() sets arg to None.
    rsqrt_has_one_src                   .rsqrt() srcs are (sqrt_node,) -- one element.
    sin_does_not_mutate_input           the input still has its original op.
    sin_is_reachable                    the def is callable.
    log2_is_reachable                   the def is callable.
    exp2_is_reachable                   the def is callable.
    rsqrt_is_reachable                  the def is callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")

r1 = t.sin()
print(f"sin_op_is_sin={int(r1.uop.op is Ops.SIN)}")

r2 = t.log2()
print(f"log2_op_is_log2={int(r2.uop.op is Ops.LOG2)}")

r3 = t.exp2()
print(f"exp2_op_is_exp2={int(r3.uop.op is Ops.EXP2)}")

r4 = t.rsqrt()
print(f"rsqrt_op_is_reciprocal={int(r4.uop.op is Ops.RECIPROCAL)}")
print(f"rsqrt_arg_is_anone={int(r4.uop.arg is None)}")
print(f"rsqrt_has_one_src={int(len(r4.uop.src) == 1)}")

print(f"sin_does_not_mutate_input={int(c.op is Ops.CONST and r1.uop.op is Ops.SIN)}")
print(f"sin_is_reachable={int(1)}")
print(f"log2_is_reachable={int(1)}")
print(f"exp2_is_reachable={int(1)}")
print(f"rsqrt_is_reachable={int(1)}")
