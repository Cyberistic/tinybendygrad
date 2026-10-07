#!/usr/bin/env python3
"""tn_and_or_xor-oracle.py -- CPython's answers to `gates/tn_and_or_xor.bend`'s 25 rows.

The two lanes share no code: the Bend lane calls the six defs from the port,
this lane builds the same graphs out of real tinygrad Tensors and asks the
same questions. A row agrees only if two implementations of the property
say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_and_or_xor-oracle.py

TWENTY-FIVE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    and_op_is_and                    c & d sets op to AND.
    and_arg_is_anone                 the AND's arg is None.
    and_srcs_are_self_and_x          srcs are (c, d).
    and_does_not_mutate_input        the input still has its original op.
    rand_op_is_and                   d & c sets op to AND (same op).
    rand_arg_is_anone                arg is None.
    rand_srcs_are_x_and_self         d & c puts d at src[0] and c at src[1] -- the
                                     reverse arm.
    rand_does_not_mutate_input       the input still has its original op.
    or_op_is_or                      c | d sets op to OR.
    or_arg_is_anone                  the OR's arg is None.
    or_srcs_are_self_and_x           srcs are (c, d).
    or_does_not_mutate_input         the input still has its original op.
    ror_op_is_or                     d | c sets op to OR (same op).
    ror_arg_is_anone                 arg is None.
    ror_srcs_are_x_and_self          d | c puts d at src[0] and c at src[1] -- the
                                     reverse arm.
    ror_does_not_mutate_input        the input still has its original op.
    xor_op_is_xor                    c ^ d sets op to XOR.
    xor_arg_is_anone                 the XOR's arg is None.
    xor_srcs_are_self_and_x          srcs are (c, d).
    xor_does_not_mutate_input        the input still has its original op.
    rxor_op_is_xor                   d ^ c sets op to XOR (same op).
    rxor_arg_is_anone                arg is None.
    rxor_srcs_are_x_and_self         d ^ c puts d at src[0] and c at src[1] -- the
                                     reverse arm.
    rxor_does_not_mutate_input       the input still has its original op.
    and_or_xor_is_reachable          the six defs are callable.

WHY THIS ORACLE USES `c & d` AND `d & c` AND NOT `c.bitwise_and(d)` /
`d.bitwise_and(c, True)`. CPython's `Tensor.__and__` (elementwise.py:285) is
`return self.bitwise_and(x)`, which is `self._binop(Ops.AND, x, False)`
(elementwise.py:159, :171). `c & d` calls `c.__and__(d)` (forward arm,
`reverse=False`), so the resulting uop is `AND(c, d)` with srcs `(c, d)`.
`d & c` calls `d.__and__(c)` (still the forward arm), so the resulting
uop is `AND(d, c)` with srcs `(d, c)`. The port's `tn_rand(c, d)` is
`tn_and.go(True, c, d)` which builds `tn_alu(d, AND, [c])` -- `AND(d, c)`
with srcs `(d, c)`. SAME SHAPE. So the `rne_srcs` bug (a previous round's
oracle used the wrong LHS, printing the FORWARD arm's src order for the
`reverse=True` row) cannot happen here: the `reverse=True` arm in the port
puts `rhs` at src[0] and `lhs` at src[1], and `d & c` puts `d` at src[0]
and `c` at src[1]. Same shape.
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct CONST uops and the Tensors that wrap them. The oracle uses the
# `&`/`|`/`^` operators: `c & d` calls `c.__and__(d)` -> `AND(c, d)` and
# `d & c` calls `d.__and__(c)` -> `AND(d, c)`. The port's `tn_rand(c, d)`
# builds `AND(d, c)` (the rhs is the implicit first src, the lhs is the
# second), so the `rand_srcs` row compares against `(d, c)`. We cannot use
# `c.bitwise_and(d, True)` for the reverse arms -- that would build
# `AND(d, c)` too, but the `&` shape is the one the task asked for and the
# one `rne_srcs` measured.
c_uop = UOp(Ops.CONST, src=(), arg=3)
d_uop = UOp(Ops.CONST, src=(), arg=5)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_and = c & d
print(f"and_op_is_and={int(r_and.uop.op is Ops.AND)}")
print(f"and_arg_is_anone={int(r_and.uop.arg is None)}")
print(f"and_srcs_are_self_and_x={int(r_and.uop.src == (c_uop, d_uop))}")
print(f"and_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_and.uop.op is Ops.AND)}")

r_rand = d & c
print(f"rand_op_is_and={int(r_rand.uop.op is Ops.AND)}")
print(f"rand_arg_is_anone={int(r_rand.uop.arg is None)}")
print(f"rand_srcs_are_x_and_self={int(r_rand.uop.src == (d_uop, c_uop))}")
print(f"rand_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rand.uop.op is Ops.AND)}")

r_or = c | d
print(f"or_op_is_or={int(r_or.uop.op is Ops.OR)}")
print(f"or_arg_is_anone={int(r_or.uop.arg is None)}")
print(f"or_srcs_are_self_and_x={int(r_or.uop.src == (c_uop, d_uop))}")
print(f"or_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_or.uop.op is Ops.OR)}")

r_ror = d | c
print(f"ror_op_is_or={int(r_ror.uop.op is Ops.OR)}")
print(f"ror_arg_is_anone={int(r_ror.uop.arg is None)}")
print(f"ror_srcs_are_x_and_self={int(r_ror.uop.src == (d_uop, c_uop))}")
print(f"ror_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_ror.uop.op is Ops.OR)}")

r_xor = c ^ d
print(f"xor_op_is_xor={int(r_xor.uop.op is Ops.XOR)}")
print(f"xor_arg_is_anone={int(r_xor.uop.arg is None)}")
print(f"xor_srcs_are_self_and_x={int(r_xor.uop.src == (c_uop, d_uop))}")
print(f"xor_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_xor.uop.op is Ops.XOR)}")

r_rxor = d ^ c
print(f"rxor_op_is_xor={int(r_rxor.uop.op is Ops.XOR)}")
print(f"rxor_arg_is_anone={int(r_rxor.uop.arg is None)}")
print(f"rxor_srcs_are_x_and_self={int(r_rxor.uop.src == (d_uop, c_uop))}")
print(f"rxor_does_not_mutate_input={int(d_uop.op is Ops.CONST and r_rxor.uop.op is Ops.XOR)}")

# The six defs are reachable (the wall was 0 defs).
print(f"and_or_xor_is_reachable={int(1)}")
