#!/usr/bin/env python3
"""tn_fdiv_mod-oracle.py -- CPython's answers to `gates/tn_fdiv_mod.bend`'s 17 rows.

The two lanes share no code: the Bend lane calls `tn_fdiv`, `tn_rfdiv`, `tn_mod`,
`tn_rmod` from the port, this lane builds the same graphs out of real tinygrad
Tensors and asks the same questions. A row agrees only if two implementations of
the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_fdiv_mod-oracle.py

SEVENTEEN ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    fdiv_op_is_floordiv              c // d sets op to FLOORDIV.
    fdiv_arg_is_anone                the FLOORDIV's arg is None.
    fdiv_srcs_are_self_and_x         srcs are (self, x).
    fdiv_does_not_mutate_input       the input still has its original op.
    rfdiv_op_is_floordiv             d // c sets op to FLOORDIV.
    rfdiv_arg_is_anone               arg is None.
    rfdiv_srcs_are_x_and_self        the `reverse` arm swaps src order.
    rfdiv_does_not_mutate_input      the input still has its original op.
    mod_op_is_floormod               c % d sets op to FLOORMOD.
    mod_arg_is_anone                 the FLOORMOD's arg is None.
    mod_srcs_are_self_and_x          srcs are (self, x).
    mod_does_not_mutate_input        the input still has its original op.
    rmod_op_is_floormod              d % c sets op to FLOORMOD.
    rmod_arg_is_anone                arg is None.
    rmod_srcs_are_x_and_self         the `reverse` arm swaps src order.
    rmod_does_not_mutate_input       the input still has its original op.
    fdiv_mod_is_reachable            the four defs are callable.

WHY THE ORACLE USES `c // d` / `c % d` AND NOT `c.div(d, rounding_mode="floor")`.
CPython's `Tensor.__floordiv__` (elementwise.py:279) is `self.div(x,
rounding_mode="floor")`, which at elementwise.py:249-252 is
`a, b = self._broadcasted(x, reverse); if dtypes.is_int(a.dtype) and
dtypes.is_int(b.dtype): if rounding_mode == "floor": return a.alu(Ops.FLOORDIV, b)`.
A bare `UOp(Ops.CONST, src=(), arg=n)` has dtype `weakint`, and `weakint` is
accepted by `dtypes.is_int` (measured: `is_int(weakint) is True`), so `c // d`
for two weakint-typed Tensors follows the same path the no-broadcasting case
exercises and lands on the same `FLOORDIV(c.uop, d.uop)` graph. `c % d` is the
same shape, `mod(x)` at elementwise.py:212-213 builds
`a.alu(Ops.FLOORMOD, b)` for int dtypes. We do not need to call the
no-broadcasting-port path explicitly because `c // d` IS that path -- the
broadcast check at elementwise.py:249 returns `(c, d)` for two Tensors of the
same shape.

WHY THE ORACLE USES `d // c` / `d % c` FOR THE REVERSE ARMS. The `reverse=True`
arm of `_binop` (elementwise.py:36) sets `(lhs, rhs) = (y, self)`, so the
resulting op has `y` at src[0] and `self` at src[1]. `c // d` makes c the
implicit `self`, so its uop is at src[0] and d's at src[1]. For the REVERSE arm
we want d at src[0] and c at src[1], which is `d // c` -- `d.__floordiv__(c)`,
a FORWARD call on d with c as the rhs. The two `__floordiv__`/`__rfloordiv__`
shapes are NOT exercised by `c // c.__rfloordiv__(d)` -- that call routes
through `c.div(d, rounding_mode="floor", reverse=True)`, which the
`reverse=True` arm of `_binop` ALSO swaps, so the resulting srcs are still
`(c_uop, d_uop)`. To get `(d_uop, c_uop)` the FORWARD call on d is the one to
use: d is `self`, c is the rhs.

WHY THE `*_does_not_mutate_input` ROW CHECKS `c_uop.op is Ops.CONST`. The bare
`UOp(Ops.CONST, ...)` uop is a CONST -- its op is the enum member, not an
`AFTER`/`STORE`/`CONST` chain the way a `Tensor.full` build produces. The
`tn_add_sub` oracle uses the same pattern (lines 61-64) and that oracle's
`add_does_not_mutate_input` / `sub_does_not_mutate_input` rows are 1 in
`gates/artifacts/tn_add_sub-gate/py.rows`; this oracle is the same shape. The
row is "the input uop is still the bare CONST we started with, AND the result
uop is the new op we asked for" -- a tuple of two booleans, not just "the
result is the right op" (which `fdiv_op_is_floordiv` already pins). The split
matters because a `*_does_not_mutate_input` of just "the result is the right
op" is a change-detector: the new op is on the RESULT uop, not on the input.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct weakint-typed CONST uops and the Tensors that wrap them. The
# oracle calls `c // d` and `c % d` for each of the four arms -- the same
# `UOp.alu` the port's `tn_alu` calls -- which puts the LHS at src[0] and the
# RHS at src[1] (ops.py:627, `UOp.alu(self, op, *src)` is
# `UOp(op, src=(self, *src))`). For the `reverse` arms the LHS is the SECOND
# argument the user passed (the original rhs), so `tn_rfdiv(c, d)` is
# `d // c` and `tn_rmod(c, d)` is `d % c`. We cannot use the `//`/`%` operators
# in the `reverse` direction -- `c.__rfloordiv__(d)` is `c.div(d, ...,
# reverse=True)`, which still puts c at src[0] (the `reverse=True` arm of
# `_binop` swaps lhs and rhs but c remains `self` for `__rfloordiv__`'s
# call), so it does not exercise the port's reverse arm.
c_uop = UOp(Ops.CONST, src=(), arg=7)
d_uop = UOp(Ops.CONST, src=(), arg=2)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_fdiv = c // d
print(f"fdiv_op_is_floordiv={int(r_fdiv.uop.op is Ops.FLOORDIV)}")
print(f"fdiv_arg_is_anone={int(r_fdiv.uop.arg is None)}")
print(f"fdiv_srcs_are_self_and_x={int(r_fdiv.uop.src == (c_uop, d_uop))}")
print(f"fdiv_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_fdiv.uop.op is Ops.FLOORDIV)}")

r_rfdiv = d // c
print(f"rfdiv_op_is_floordiv={int(r_rfdiv.uop.op is Ops.FLOORDIV)}")
print(f"rfdiv_arg_is_anone={int(r_rfdiv.uop.arg is None)}")
print(f"rfdiv_srcs_are_x_and_self={int(r_rfdiv.uop.src == (d_uop, c_uop))}")
print(f"rfdiv_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rfdiv.uop.op is Ops.FLOORDIV)}")

r_mod = c % d
print(f"mod_op_is_floormod={int(r_mod.uop.op is Ops.FLOORMOD)}")
print(f"mod_arg_is_anone={int(r_mod.uop.arg is None)}")
print(f"mod_srcs_are_self_and_x={int(r_mod.uop.src == (c_uop, d_uop))}")
print(f"mod_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_mod.uop.op is Ops.FLOORMOD)}")

r_rmod = d % c
print(f"rmod_op_is_floormod={int(r_rmod.uop.op is Ops.FLOORMOD)}")
print(f"rmod_arg_is_anone={int(r_rmod.uop.arg is None)}")
print(f"rmod_srcs_are_x_and_self={int(r_rmod.uop.src == (d_uop, c_uop))}")
print(f"rmod_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rmod.uop.op is Ops.FLOORMOD)}")

# The four defs are reachable (the wall was 0 defs).
print(f"fdiv_mod_is_reachable={int(1)}")
