#!/usr/bin/env python3
"""tn_lshift_rshift-oracle.py -- CPython's answers to the 9 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_lshift_rshift-oracle.py

NINE ROWS:
    lshift_op_is_shl                 .lshift(x) sets op to SHL.
    lshift_arg_is_anone              arg is None.
    lshift_does_not_mutate_input     the input still has its original op.
    rlshift_op_is_shl                __rlshift__ also sets op to SHL.
    rlshift_arg_is_anone              same, arg is None.
    rlshift_does_not_mutate_input     same, input unchanged.
    rshift_op_is_shr                 .rshift(x) sets op to SHR.
    rshift_arg_is_anone              same, arg is None.
    rshift_does_not_mutate_input     same, input unchanged.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")

r_l = t.lshift(t)
print(f"lshift_op_is_shl={int(r_l.uop.op is Ops.SHL)}")
print(f"lshift_arg_is_anone={int(r_l.uop.arg is None)}")
print(f"lshift_does_not_mutate_input={int(c.op is Ops.CONST and r_l.uop.op is Ops.SHL)}")

r_rl = t.__rlshift__(t)
print(f"rlshift_op_is_shl={int(r_rl.uop.op is Ops.SHL)}")
print(f"rlshift_arg_is_anone={int(r_rl.uop.arg is None)}")
print(f"rlshift_does_not_mutate_input={int(c.op is Ops.CONST and r_rl.uop.op is Ops.SHL)}")

r_r = t.rshift(t)
print(f"rshift_op_is_shr={int(r_r.uop.op is Ops.SHR)}")
print(f"rshift_arg_is_anone={int(r_r.uop.arg is None)}")
print(f"rshift_does_not_mutate_input={int(c.op is Ops.CONST and r_r.uop.op is Ops.SHR)}")
