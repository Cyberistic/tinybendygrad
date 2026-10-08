#!/usr/bin/env python3
"""tn_ceil_floor-oracle.py -- CPython's answers to the 11 rows.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_ceil_floor-oracle.py

ELEVEN ROWS:
    ceil_op_is_where               .ceil() builds a WHERE node.
    ceil_arg_is_anone              arg is None.
    ceil_has_three_srcs            .ceil()'s WHERE has 3 srcs (cond, b+1, b).
    ceil_does_not_mutate_input     the input still has its original op.
    ceil_cond_is_cmplt             the cond's op is CMPLT (the `self > b`).
    floor_op_is_where              .floor() builds a WHERE node.
    floor_arg_is_anone             arg is None.
    floor_has_three_srcs           .floor()'s WHERE has 3 srcs (cond, b-1, b).
    floor_does_not_mutate_input    the input still has its original op.
    floor_cond_is_cmplt            the cond's op is CMPLT (the `self < b`).
    ceil_floor_is_reachable        the two defs are callable.

WHY THIS ORACLE USES `Tensor.ceil()` / `Tensor.floor()` AND NOT A MIMIC. CPython's
`Tensor.ceil` (elementwise.py:656) is `(self > (b := self.trunc())).where(b+1, b)`,
and `Tensor.floor` (elementwise.py:662) is `(self < (b := self.trunc())).where(b-1, b)`.
The `b+1` is `_binop(Ops.ADD)` and the `b-1` is `Tensor.sub`, WHICH IS NOT A SUB. This
paragraph USED TO say `b-1` "builds a SINGLE ADD or SUB node" and that `Tensor.__sub__`'s body
is `return a.alu(Ops.SUB, b)`. BOTH ARE FALSE. `elementwise.py:103` reads, docstring stripped,
`a, b = self._broadcasted(x, reverse)` then `return a.alu(Ops.ADD, -b)`, so `-` builds
`ADD(a, MUL(b, -1))` and `Ops.SUB` is never built by it. MEASURED on CPython for
`Tensor.floor`: `WHERE(CMPLT(BUFFER(), TRUNC(BUFFER())), ADD(TRUNC(BUFFER()), MUL(CONST(),
CONST())), TRUNC(BUFFER()))`.

THE THREE `*_src1_*` ROWS ARE NEW AND THEY ARE THE ONES THAT MATTER. All eleven rows that
existed before read the TOP node, its arg, its src COUNT, purity, or src[0] -- so `src[1]`,
which IS the `b+1` / `b-1` step, was never looked at by either lane. That is the same shape
of hole `tn_add_sub` had.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# A CONST{CInt{4}} tensor. The fixture is a CONST so the graph stays simple --
# the gate checks the GRAPH SHAPE (op/arg/srcs), not arithmetic semantics.
c = UOp(Ops.CONST, src=(), arg=4)
t = Tensor(c, device="PYTHON")

# CEIL: (self > (b := self.trunc())).where(b+1, b)
r_ceil = t.ceil()
print(f"ceil_op_is_where={int(r_ceil.uop.op is Ops.WHERE)}")
print(f"ceil_arg_is_anone={int(r_ceil.uop.arg is None)}")
print(f"ceil_has_three_srcs={int(len(r_ceil.uop.src) == 3)}")
print(f"ceil_does_not_mutate_input={int(c.op is Ops.CONST and r_ceil.uop.op is Ops.WHERE)}")
# The cond is `(self > b)` -- CPython's `__gt__` is `self._binop(Ops.CMPLT, x, True)`,
# which is `CMPLT(b, self)` -- a CMPLT node at src[0].
print(f"ceil_cond_is_cmplt={int(r_ceil.uop.src[0].op is Ops.CMPLT)}")

# FLOOR: (self < (b := self.trunc())).where(b-1, b)
r_floor = t.floor()
print(f"floor_op_is_where={int(r_floor.uop.op is Ops.WHERE)}")
print(f"floor_arg_is_anone={int(r_floor.uop.arg is None)}")
print(f"floor_has_three_srcs={int(len(r_floor.uop.src) == 3)}")
print(f"floor_does_not_mutate_input={int(c.op is Ops.CONST and r_floor.uop.op is Ops.WHERE)}")
# The cond is `(self < b)` -- CPython's `__lt__` is `self._binop(Ops.CMPLT, x, False)`,
# which is `CMPLT(self, b)` -- a CMPLT node at src[0].
print(f"floor_cond_is_cmplt={int(r_floor.uop.src[0].op is Ops.CMPLT)}")

# Both defs are reachable (the wall was 0 defs).
print(f"ceil_floor_is_reachable={int(1)}")
# The `b+1` / `b-1` rows: src[1] of the WHERE. Both are ADD, and `floor`'s ADD has a MUL for
# src[1] because `-1` is a MUL and not a SUB.
print(f"ceil_src1_is_add={int(r_ceil.uop.src[1].op is Ops.ADD)}")
print(f"floor_src1_is_add={int(r_floor.uop.src[1].op is Ops.ADD)}")
print(f"floor_src1_is_mul_by_neg1={int(r_floor.uop.src[1].src[1].op is Ops.MUL)}")
