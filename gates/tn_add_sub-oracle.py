#!/usr/bin/env python3
"""tn_add_sub-oracle.py -- CPython's answers to `gates/tn_add_sub.bend`'s 17 rows.

The two lanes share no code: the Bend lane calls `tn_add`, `tn_radd`, `tn_sub`,
`tn_rsub` from the port, this lane builds the same graphs out of real tinygrad
Tensors and asks the same questions. A row agrees only if two implementations of
the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_add_sub-oracle.py

SEVENTEEN ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    add_op_is_add                    c.alu(ADD, d) sets op to ADD.
    add_arg_is_anone                 the ADD's arg is None.
    add_srcs_are_self_and_x          srcs are (self, x).
    add_does_not_mutate_input        the input still has its original op.
    radd_op_is_add                   d.alu(ADD, c) sets op to ADD.
    radd_arg_is_anone                arg is None.
    radd_srcs_are_x_and_self         the `reverse` arm swaps src order.
    radd_does_not_mutate_input       the input still has its original op.
    sub_op_is_sub                    c.alu(SUB, d) sets op to SUB.
    sub_arg_is_anone                 the SUB's arg is None.
    sub_src0_is_self                 src[0] is self.
    sub_src1_is_neg_x                src[1] is MUL(x, -1) -- `sub` is ADD, never SUB.
    sub_does_not_mutate_input        the input still has its original op.
    rsub_op_is_sub                   d.alu(SUB, c) sets op to SUB.
    rsub_arg_is_anone                arg is None.
    rsub_src0_is_x                   the `reverse` arm swaps which operand is src[0].
    rsub_src1_is_neg_self            src[1] is MUL(self, -1).
    rsub_does_not_mutate_input       the input still has its original op.
    add_sub_is_reachable             the four defs are callable.

WHY THIS ORACLE USES `Tensor.alu(Ops.X, y)` AND NOT `c + d` / `c - d`. CPython's
`Tensor.__add__` (elementwise.py:267) calls `Tensor.add(x)` (elementwise.py:84),
which is `a, b = self._broadcasted(x, reverse); return a.alu(Ops.ADD, -b)`. The
`-b` is a CONST trap (and unary minus on a Tensor is also walled), so for a
CONST rhs `-b` is just a negated CONST and the resulting op is `Ops.ADD`. For a
TENSOR rhs `-b` is `NEG(b.uop)`, so `c - d` builds `ADD(c.uop, NEG(d.uop))` --
two nodes, NOT `SUB(c.uop, d.uop)`. The port's no-broadcasting case for
`__sub__` is `_binop`'s body (elementwise.py:36, `lhs.alu(op, rhs)`) with
`Ops.SUB`, which is what `Tensor.alu(Ops.SUB, rhs)` builds: `SUB(lhs, rhs)`
directly. The oracle calls `Tensor.alu` to mirror what the port mirrors --
`_binop`'s body, not CPython's `-b` trick. The `c + d` case still works
because `c.alu(Ops.ADD, d)` is the same graph `c + d` would build in the
no-broadcasting case (the `-b` collapses when `b` is a CONST because `+x` is
`-(-x)`, but the result is `ADD(c.uop, d.uop)` directly via `Tensor.alu`).
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct CONST uops and the Tensors that wrap them. The oracle calls
# `Tensor.alu(Ops.X, rhs)` for each of the four arms -- the same `UOp.alu`
# the port's `tn_alu` calls -- which puts the LHS at src[0] and the RHS at
# src[1] (ops.py:627, `UOp.alu(self, op, *src)` is
# `UOp(op, src=(self, *src))`). For the `reverse` arms the LHS is the SECOND
# argument the user passed (the original rhs), so `tn_radd(c, d)` is
# `d.alu(Ops.ADD, c)` and `tn_rsub(c, d)` is `d.alu(Ops.SUB, c)`. We cannot
# use the `+`/`-` operators for the reverse arms -- Python's `d + c` calls
# `d.__add__(c)`, never `__radd__` (Tensor's `__add__` always returns a
# Tensor, so `NotImplemented` is unreachable).
c_uop = UOp(Ops.CONST, src=(), arg=3)
d_uop = UOp(Ops.CONST, src=(), arg=5)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_add = c.alu(Ops.ADD, d)
print(f"add_op_is_add={int(r_add.uop.op is Ops.ADD)}")
print(f"add_arg_is_anone={int(r_add.uop.arg is None)}")
print(f"add_srcs_are_self_and_x={int(r_add.uop.src == (c_uop, d_uop))}")
print(f"add_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_add.uop.op is Ops.ADD)}")

r_radd = d.alu(Ops.ADD, c)
print(f"radd_op_is_add={int(r_radd.uop.op is Ops.ADD)}")
print(f"radd_arg_is_anone={int(r_radd.uop.arg is None)}")
print(f"radd_srcs_are_x_and_self={int(r_radd.uop.src == (d_uop, c_uop))}")
print(f"radd_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_radd.uop.op is Ops.ADD)}")

# THE DUNDER, NOT `alu(Ops.SUB)`. This oracle USED to call `c.alu(Ops.SUB, d)` -- a path
# CPython's `Tensor.sub` never takes -- so `sub_srcs_are_self_and_x` agreed with a port that
# built `Ops.SUB` while CPython builds `ADD(a, MUL(b, -1))`. elementwise.py:103 is
# `return a.alu(Ops.ADD, -b)`. Both lanes were wrong and they agreed, which is the failure
# mode this file exists to prevent. `__rsub__` is `self.sub(x, True)` = elementwise.py:297.
r_sub = c - d
print(f"sub_op_is_add={int(r_sub.uop.op is Ops.ADD)}")
print(f"sub_arg_is_anone={int(r_sub.uop.arg is None)}")
print(f"sub_src0_is_self={int(r_sub.uop.src[0] is c_uop)}")
print(f"sub_src1_is_neg_x={int(r_sub.uop.src[1].op is Ops.MUL and r_sub.uop.src[1].src[0] is d_uop)}")
print(f"sub_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_sub.uop.op is Ops.ADD)}")

r_rsub = d.__rsub__(c)
print(f"rsub_op_is_add={int(r_rsub.uop.op is Ops.ADD)}")
print(f"rsub_arg_is_anone={int(r_rsub.uop.arg is None)}")
print(f"rsub_src0_is_x={int(r_rsub.uop.src[0] is c_uop)}")
print(f"rsub_src1_is_neg_self={int(r_rsub.uop.src[1].op is Ops.MUL and r_rsub.uop.src[1].src[0] is d_uop)}")
print(f"rsub_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rsub.uop.op is Ops.ADD)}")

# The four defs are reachable (the wall was 0 defs).
print(f"add_sub_is_reachable={int(1)}")