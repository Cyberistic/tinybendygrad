#!/usr/bin/env python3
"""tn_pow-gate.py -- THE GATE for `tn_pow` / `tn_rpow` in
`tinybendygrad/tensor.bend`.

    .venv/bin/python gates/tn_pow-gate.py

NINE ROWS, THREE LANES. CPython's `Tensor.__pow__` (elementwise.py:569, via
`pow` at :548) is
`base, exponent = self._broadcasted(x, reverse=reverse);
 if isinstance(exponent, ConstType): ...
 return base.alu(Ops.POW, exponent)`.
For two Tensors of the same shape (the no-broadcasting case the wall text
at `nn/__init__.bend:241+` cited as the blocker) `_broadcasted` is the
identity and the `isinstance(exponent, ConstType)` guard is unreachable
(both `exponent` and `self` are Tensors), so the body reduces to
`_binop`'s shape (elementwise.py:36) with `MUL` replaced by `POW`:
`__pow__` is `self.alu(POW, x)` -- srcs `(self, x)`. The `reverse=True`
arm swaps: `__rpow__` is `x.alu(POW, self)` -- srcs `(x, self)`. CPython
also has a `Tensor.pow(x, reverse=False)` (elementwise.py:548) which is
the same `_binop` body, and the `__pow__` dunder simply calls
`self.pow(x)` (elementwise.py:569). With `tn_pow` / `tn_rpow` ported at
`tensor.bend:673-682`, the no-broadcasting case of both dunders is
covered. The broadcasting case stays walled on `_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "pow_op_is_pow",                           # tn_pow sets op to POW.
    "pow_arg_is_anone",                        # the POW's arg is None.
    "pow_srcs_are_self_and_x",                 # the POW's srcs are (self, x).
    "pow_does_not_mutate_input",               # the input still has its original op.
    "rpow_op_is_pow",                          # tn_rpow sets op to POW (same op).
    "rpow_arg_is_anone",                       # arg is None.
    "rpow_srcs_are_x_and_self",                # the `reverse` arm flips src order.
    "rpow_does_not_mutate_input",              # the input still has its original op.
    "pow_is_reachable",                        # the two defs are callable.
)

GATE = Gate(
    "tn_pow-gate",
    bend="tn_pow.bend",
    oracle="tn_pow-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_pow-gate: 9 rows, 3 lanes -- tn_pow and tn_rpow "
                        "both agree with CPython's Tensor.__pow__ / __rpow__ "
                        "(op/arg/srcs/purity on the no-broadcasting case; the "
                        "broadcasting case stays walled on _broadcasted)"))
