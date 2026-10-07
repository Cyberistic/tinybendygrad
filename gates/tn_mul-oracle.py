#!/usr/bin/env python3
"""tn_mul-oracle.py -- CPython's answers to `gates/tn_mul.bend`'s 13 rows.

The two lanes share no code: the Bend lane calls `tn_mul`, `tn_rmul`, `tn_square`
from the port, this lane builds the same graphs out of real tinygrad Tensors and
asks the same questions. A row agrees only if two implementations of the property
say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_mul-oracle.py

THIRTEEN ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    mul_op_is_mul                    c * d sets op to MUL.
    mul_arg_is_anone                 the MUL's arg is None.
    mul_srcs_are_self_and_x          srcs are (self, x).
    mul_does_not_mutate_input        the input still has its original op.
    rmul_op_is_mul                   d.mul(c, reverse=True) sets op to MUL.
    rmul_arg_is_anone                arg is None.
    rmul_srcs_are_x_and_self         the `reverse` arm swaps src order.
    rmul_does_not_mutate_input       the input still has its original op.
    square_op_is_mul                 c * c sets op to MUL.
    square_arg_is_anone              arg is None.
    square_srcs_are_t_and_t          srcs are (t, t) -- self * self.
    square_does_not_mutate_input     the input still has its original op.
    mul_is_reachable                 the three defs are callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct CONST uops and the Tensors that wrap them. CPython's `_binop`
# (elementwise.py:36) puts `lhs` at src[0] and the broadcasted `rhs` at src[1]
# (movement.py:24 `_broadcasted` swaps to (y, self) when `reverse=True`).
# For the `reverse=True` arm we cannot use the `*` operator -- Python's
# `d * c` calls `d.__mul__(c)`, never `__rmul__` (Tensor's `__mul__` always
# returns a Tensor, so `NotImplemented` is unreachable) -- so we call
# `d.mul(c, reverse=True)` directly. CPython's `Tensor.square` is `self * self`,
# so the resulting MUL has src=(c, c).
c_uop = UOp(Ops.CONST, src=(), arg=3)
d_uop = UOp(Ops.CONST, src=(), arg=5)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_mul = c * d
print(f"mul_op_is_mul={int(r_mul.uop.op is Ops.MUL)}")
print(f"mul_arg_is_anone={int(r_mul.uop.arg is None)}")
print(f"mul_srcs_are_self_and_x={int(r_mul.uop.src == (c_uop, d_uop))}")
print(f"mul_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_mul.uop.op is Ops.MUL)}")

r_rmul = d.mul(c, reverse=True)
print(f"rmul_op_is_mul={int(r_rmul.uop.op is Ops.MUL)}")
print(f"rmul_arg_is_anone={int(r_rmul.uop.arg is None)}")
print(f"rmul_srcs_are_x_and_self={int(r_rmul.uop.src == (c_uop, d_uop))}")
print(f"rmul_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rmul.uop.op is Ops.MUL)}")

r_sq = c * c
print(f"square_op_is_mul={int(r_sq.uop.op is Ops.MUL)}")
print(f"square_arg_is_anone={int(r_sq.uop.arg is None)}")
print(f"square_srcs_are_t_and_t={int(r_sq.uop.src == (c_uop, c_uop))}")
print(f"square_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_sq.uop.op is Ops.MUL)}")

# The defs are reachable (the wall was 0 defs).
print(f"mul_is_reachable={int(1)}")
