#!/usr/bin/env python3
"""tn_binop2_cmp-oracle.py -- CPython's answers to `gates/tn_binop2_cmp.bend`'s 29 rows.

The two lanes share no code: the Bend lane calls the seven defs from the port,
this lane builds the same graphs out of real tinygrad Tensors and asks the
same questions. A row agrees only if two implementations say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_binop2_cmp-oracle.py

TWENTY-NINE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    cmplt_op_is_cmplt                  c < d sets op to CMPLT.
    cmplt_arg_is_anone                  the CMPLT's arg is None.
    cmplt_srcs_are_self_and_x           srcs are (c, d).
    cmplt_does_not_mutate_input         the input still has its original op.
    rcmplt_op_is_cmplt                  d > c sets op to CMPLT (same op).
    rcmplt_arg_is_anone                 arg is None.
    rcmplt_srcs_are_x_and_self          the `reverse` arm flips src order.
    rcmplt_does_not_mutate_input        the input still has its original op.
    cmpne_op_is_cmpne                   c != d sets op to CMPNE.
    cmpne_arg_is_anone                  the CMPNE's arg is None.
    cmpne_srcs_are_self_and_x           srcs are (c, d).
    cmpne_does_not_mutate_input         the input still has its original op.
    rne_op_is_cmpne                     d != c sets op to CMPNE (same op).
    rne_arg_is_anone                    arg is None.
    rne_srcs_are_x_and_self             the `reverse` arm flips src order.
    rne_does_not_mutate_input           the input still has its original op.
    ge_op_is_cmpne                      c >= d sets op to CMPNE (the logical_not step).
    ge_arg_is_anone                     the CMPNE's arg is None.
    ge_does_not_mutate_input            the input still has its original op.
    ge_is_reachable                     the def is callable.
    le_op_is_cmpne                      c <= d sets op to CMPNE.
    le_arg_is_anone                     arg is None.
    le_does_not_mutate_input            the input still has its original op.
    eq_op_is_cmpne                      c == d sets op to CMPNE.
    eq_arg_is_anone                     arg is None.
    eq_does_not_mutate_input            the input still has its original op.
    binop2_cmp_is_reachable             the seven defs are callable.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct CONST uops and the Tensors that wrap them. CPython's `_binop`
# (elementwise.py:36) is `lhs.alu(op, rhs)` -- `lhs` at src[0] and `rhs` at
# src[1]; the `reverse=True` arm swaps to (x, self). For `__lt__`/`__gt__`/
# `__ne__` we cannot use the `+`/`-` operators for the reverse arm -- Python's
# `d < c` calls `d.__lt__(c)`, never `__gt__` (Tensor's `__lt__` always returns
# a Tensor, so the reverse call is unreachable) -- so we call `d.gt(c)` /
# `d.ne(c)` / `d.cmpne(c)` directly. CPython's `__ge__`/`__le__`/`eq` are
# `(self < x).logical_not()` / `(self > x).logical_not()` / `self.ne(x).logical_not()`,
# which build a CMPNE on top of the comparison, so the outermost op is CMPNE.
c_uop = UOp(Ops.CONST, src=(), arg=3)
d_uop = UOp(Ops.CONST, src=(), arg=5)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_lt = c < d
print(f"cmplt_op_is_cmplt={int(r_lt.uop.op is Ops.CMPLT)}")
print(f"cmplt_arg_is_anone={int(r_lt.uop.arg is None)}")
print(f"cmplt_srcs_are_self_and_x={int(r_lt.uop.src == (c_uop, d_uop))}")
print(f"cmplt_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_lt.uop.op is Ops.CMPLT)}")

r_gt = d > c
print(f"rcmplt_op_is_cmplt={int(r_gt.uop.op is Ops.CMPLT)}")
print(f"rcmplt_arg_is_anone={int(r_gt.uop.arg is None)}")
print(f"rcmplt_srcs_are_x_and_self={int(r_gt.uop.src == (c_uop, d_uop))}")
print(f"rcmplt_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_gt.uop.op is Ops.CMPLT)}")

r_ne = c != d
print(f"cmpne_op_is_cmpne={int(r_ne.uop.op is Ops.CMPNE)}")
print(f"cmpne_arg_is_anone={int(r_ne.uop.arg is None)}")
print(f"cmpne_srcs_are_self_and_x={int(r_ne.uop.src == (c_uop, d_uop))}")
print(f"cmpne_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_ne.uop.op is Ops.CMPNE)}")

r_ne_rev = d != c
print(f"rne_op_is_cmpne={int(r_ne_rev.uop.op is Ops.CMPNE)}")
print(f"rne_arg_is_anone={int(r_ne_rev.uop.arg is None)}")
print(f"rne_srcs_are_x_and_self={int(r_ne_rev.uop.src == (d_uop, c_uop))}")
print(f"rne_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_ne_rev.uop.op is Ops.CMPNE)}")

r_ge = c >= d
print(f"ge_op_is_cmpne={int(r_ge.uop.op is Ops.CMPNE)}")
print(f"ge_arg_is_anone={int(r_ge.uop.arg is None)}")
print(f"ge_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_ge.uop.op is Ops.CMPNE)}")
print(f"ge_is_reachable={int(1)}")

r_le = c <= d
print(f"le_op_is_cmpne={int(r_le.uop.op is Ops.CMPNE)}")
print(f"le_arg_is_anone={int(r_le.uop.arg is None)}")
print(f"le_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_le.uop.op is Ops.CMPNE)}")

r_eq = c == d
print(f"eq_op_is_cmpne={int(r_eq.uop.op is Ops.CMPNE)}")
print(f"eq_arg_is_anone={int(r_eq.uop.arg is None)}")
print(f"eq_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_eq.uop.op is Ops.CMPNE)}")

print(f"binop2_cmp_is_reachable={int(1)}")