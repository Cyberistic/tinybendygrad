#!/usr/bin/env python3
"""tn_and_or_xor-gate.py -- THE GATE for `tn_and` / `tn_rand` / `tn_or` /
`tn_ror` / `tn_xor` / `tn_rxor`.

    .venv/bin/python gates/tn_and_or_xor-gate.py

TWENTY-FIVE ROWS, THREE LANES. CPython's `Tensor.__and__` (elementwise.py:285,
via `bitwise_and` at :159) is `self._binop(Ops.AND, x, False)`. For two
Tensors of the same shape (the no-broadcasting case the wall text at
`nn/__init__.bend:241` cited as the blocker) `_broadcasted` is identity and
the body reduces to `_binop`'s shape (elementwise.py:36) with `MUL` replaced
by `AND`: `__and__` is `self.alu(AND, x)` -- srcs `(self, x)`. The
`reverse=True` arm swaps: `__rand__` is `x.alu(AND, self)` -- srcs
`(x, self)`. `__or__`/`__ror__`/ `__xor__`/`__rxor__` are the same shape
with `Ops.OR` / `Ops.XOR` instead of `Ops.AND`. The wall at
`nn/__init__.bend:241` named `_broadcasted` as the blocker; with
`tn_and` / `tn_rand` / `tn_or` / `tn_ror` / `tn_xor` / `tn_rxor` ported,
the no-broadcasting case of all six dunders is covered. The broadcasting
case stays walled on `_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    # tn_and -- elementwise.py:285, via bitwise_and at :159.
    "and_op_is_and",                          # tn_and sets op to AND.
    "and_arg_is_anone",                       # the AND's arg is None.
    "and_srcs_are_self_and_x",                # the AND's srcs are (self, x).
    "and_does_not_mutate_input",              # the input still has its original op.
    # tn_rand -- elementwise.py:309, reverse arm.
    "rand_op_is_and",                         # tn_rand sets op to AND (same op).
    "rand_arg_is_anone",                      # arg is None.
    "rand_srcs_are_x_and_self",               # the `reverse` arm flips src order.
    "rand_does_not_mutate_input",             # the input still has its original op.
    # tn_or -- elementwise.py:288, via bitwise_or at :173.
    "or_op_is_or",                            # tn_or sets op to OR.
    "or_arg_is_anone",                        # the OR's arg is None.
    "or_srcs_are_self_and_x",                 # the OR's srcs are (self, x).
    "or_does_not_mutate_input",               # the input still has its original op.
    # tn_ror -- elementwise.py:312, reverse arm.
    "ror_op_is_or",                           # tn_ror sets op to OR (same op).
    "ror_arg_is_anone",                       # arg is None.
    "ror_srcs_are_x_and_self",                # the `reverse` arm flips src order.
    "ror_does_not_mutate_input",              # the input still has its original op.
    # tn_xor -- elementwise.py:291, via bitwise_xor at :187.
    "xor_op_is_xor",                          # tn_xor sets op to XOR.
    "xor_arg_is_anone",                       # the XOR's arg is None.
    "xor_srcs_are_self_and_x",                # the XOR's srcs are (self, x).
    "xor_does_not_mutate_input",              # the input still has its original op.
    # tn_rxor -- elementwise.py:315, reverse arm.
    "rxor_op_is_xor",                         # tn_rxor sets op to XOR (same op).
    "rxor_arg_is_anone",                      # arg is None.
    "rxor_srcs_are_x_and_self",               # the `reverse` arm flips src order.
    "rxor_does_not_mutate_input",             # the input still has its original op.
    "and_or_xor_is_reachable",                # the six defs are callable.
)

GATE = Gate(
    "tn_and_or_xor-gate",
    bend="tn_and_or_xor.bend",
    oracle="tn_and_or_xor-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_and_or_xor-gate: 25 rows, 3 lanes -- tn_and, tn_rand, "
                        "tn_or, tn_ror, tn_xor, and tn_rxor all agree with CPython's "
                        "Tensor.__and__ / __rand__ / __or__ / __ror__ / __xor__ / __rxor__ "
                        "(op/arg/srcs/purity on the no-broadcasting case; the "
                        "broadcasting case stays walled on _broadcasted)"))
