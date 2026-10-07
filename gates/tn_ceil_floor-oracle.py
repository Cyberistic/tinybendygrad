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
The `b+1` / `b-1` is `_binop`'s body (elementwise.py:36) with `Ops.ADD` / `Ops.SUB`,
which builds a SINGLE ADD or SUB node (not a chain of `+1` / `-1` -- the `-1` on a
CONST rhs is a CONST trap because `Tensor.__sub__`'s body is `a, b = self._broadcasted(x);
return a.alu(Ops.SUB, b)`, and for a CONST rhs the `-b` collapse to `a.alu(Ops.SUB, b)`).
The port follows the same shape: `tn_add(b, c1t)` builds `ADD(b, c1)`, the
`tn_where(gt, bp1, b)` builds `WHERE(gt, bp1, b)`, and the final node is a single
WHERE whose srcs are `(self>b, b+1, b)`. The oracle therefore calls `t.ceil()` /
`t.floor()` directly and asserts the GRAPH SHAPE -- op, arg, nsrcs, cond's op --
which is the same shape the port's row functions check.
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
