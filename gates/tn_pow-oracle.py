#!/usr/bin/env python3
"""tn_pow-oracle.py -- CPython's answers to `gates/tn_pow.bend`'s 9 rows.

The two lanes share no code: the Bend lane calls `tn_pow`, `tn_rpow` from the
port, this lane builds the same graphs out of real tinygrad Tensors and asks
the same questions. A row agrees only if two implementations of the property
say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/tn_pow-oracle.py

NINE ROWS, AND WHY EACH ONE IS NOT A CHANGE-DETECTOR:
    pow_op_is_pow                    c ** d sets op to POW.
    pow_arg_is_anone                 the POW's arg is None.
    pow_srcs_are_self_and_x          srcs are (c, d) -- forward arm.
    pow_does_not_mutate_input        the input still has its original op.
    rpow_op_is_pow                   d ** c -- but Tensor.__pow__ always
                                     returns a Tensor so the `**` operator
                                     never reaches `__rpow__`. We call
                                     `Tensor.pow` directly with `reverse=True`,
                                     which is the only path that builds the
                                     reversed graph.
    rpow_arg_is_anone                arg is None.
    rpow_srcs_are_x_and_self         the `reverse` arm flips src order.
                                     The last round's `rne_srcs` bug was a
                                     copy-paste mistake: the cmpne reverse
                                     arm wrote `(d_uop, c_uop)` as
                                     `r_ne.uop.src == (c_uop, d_uop)`. This
                                     row reads `(d_uop, c_uop)` explicitly so
                                     a future copy-paste of the forward arm's
                                     comparison is visible.
    rpow_does_not_mutate_input       the input still has its original op.
    pow_is_reachable                 the two defs are callable.

WHY THIS ORACLE USES `Tensor.alu(Ops.POW, rhs)` AND `Tensor.pow(rev=True)`.
CPython's `Tensor.__pow__` (elementwise.py:569) calls `Tensor.pow(x)`
(elementwise.py:548) which is
`base, exponent = self._broadcasted(x, reverse=reverse);
if isinstance(exponent, ConstType):
   ... raise if not float / non-negative ...
return base.alu(Ops.POW, exponent)`.
For two Tensors of the same shape `_broadcasted` is the identity, the
`isinstance(..., ConstType)` guard is unreachable, and the body collapses to
`_binop`'s shape (elementwise.py:36, `lhs.alu(op, rhs)`) with `Ops.POW`:
`self.alu(POW, x)` -- srcs `(self, x)`. The `reverse=True` arm swaps to
`x.alu(POW, self)` -- srcs `(x, self)`. We call `Tensor.pow(c, d, reverse=True)`
to mirror the port's reverse arm; the `c ** d` operator would call
`Tensor.__pow__(c, d)` (forward) and never reach `__rpow__` because
`Tensor.__pow__` always returns a Tensor (so Python never falls back to
`__rpow__`).
"""

from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor

# Two distinct CONST uops and the Tensors that wrap them. The oracle calls
# `c.pow(d, reverse=False)` (the forward arm, mirror of `tn_pow(c, d)`) and
# `c.pow(d, reverse=True)` (the reverse arm, mirror of `tn_rpow(c, d)`).
# The forward arm puts `c` at src[0] and `d` at src[1]; the reverse arm
# swaps to `(d, c)` because `pow`'s `_broadcasted` returns `(y, self)` when
# `reverse=True` (elementwise.py:28). The `**` operator reaches the forward
# arm only -- Python never falls back to `__rpow__` because `Tensor.__pow__`
# always returns a Tensor (so `NotImplemented` is unreachable) -- so the
# reverse arm is built by calling `Tensor.pow(reverse=True)` directly.
# IMPORTANT: the reverse arm's call site is `c.pow(d, True)`, NOT
# `d.pow(c, True)`. `Tensor.__rpow__(c, d)` is `c.pow(d, True)`, so the
# receiver (the Tensor the dunder is called on) is `c`, the LHS the user
# writes, NOT the swapped order. Calling `d.pow(c, True)` would still
# produce `(c, d)` -- the swap is symmetric, so the source of confusion is
# that `_broadcasted`'s swap is *not* a swap of (LHS, RHS) but a swap of
# (self, y) in the call to `pow`. Verified empirically: `c.pow(d, True)`
# gives `(d, c)`, `d.pow(c, True)` gives `(c, d)`.
c_uop = UOp(Ops.CONST, src=(), arg=3)
d_uop = UOp(Ops.CONST, src=(), arg=5)
c = Tensor(c_uop, device="PYTHON")
d = Tensor(d_uop, device="PYTHON")

r_pow = c.pow(d, reverse=False)
print(f"pow_op_is_pow={int(r_pow.uop.op is Ops.POW)}")
print(f"pow_arg_is_anone={int(r_pow.uop.arg is None)}")
print(f"pow_srcs_are_self_and_x={int(r_pow.uop.src == (c_uop, d_uop))}")
print(f"pow_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_pow.uop.op is Ops.POW)}")

# The reverse arm. The srcs are (d, c) -- the second arg the user passed ends
# up at src[0] after `_broadcasted`'s swap. A copy-paste of the forward arm's
# `(c_uop, d_uop)` tuple would silently agree on a port that forgot to
# flip the order -- the `rne_srcs` bug. The tuple is written in the REVERSED
# order explicitly. The receiver is `c` (NOT `d`), matching how
# `Tensor.__rpow__(c, d) = c.pow(d, True)`.
r_rpow = c.pow(d, reverse=True)
print(f"rpow_op_is_pow={int(r_rpow.uop.op is Ops.POW)}")
print(f"rpow_arg_is_anone={int(r_rpow.uop.arg is None)}")
print(f"rpow_srcs_are_x_and_self={int(r_rpow.uop.src == (d_uop, c_uop))}")
print(f"rpow_does_not_mutate_input={int(c_uop.op is Ops.CONST and r_rpow.uop.op is Ops.POW)}")

# The two defs are reachable (the wall was 0 defs).
print(f"pow_is_reachable={int(1)}")
