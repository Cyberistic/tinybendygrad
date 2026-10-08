#!/usr/bin/env python3
"""tn_maximum-gate.py -- THE GATE for `tn_maximum`.

    .venv/bin/python gates/tn_maximum-gate.py

SEVEN ROWS, THREE LANES. CPython's `Tensor.maximum` (elementwise.py:378) is
`self._binop(Ops.MAX, x, False)`. The wall text at `nn/__init__.bend:241`
cited `_broadcasted` as the blocker. The no-broadcasting case (two same-
shape Tensors) reduces to `self.alu(MAX, x.uop)`, the same shape as
`tn_add` / `tn_mul`. THERE IS NO REVERSE ARM: CPython's `maximum` (elementwise.py:378) is
`self._binop(Ops.MAX, x, False)` with the `False` HARDCODED, and there is no `__rmax__`. The
`tn_rmaximum` this gate used to cover was not a port of anything and has been removed.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "max_op_is_max",
    "max_arg_is_anone",
    "max_does_not_mutate_input",
    "maximum_is_reachable",
)

GATE = Gate(
    "tn_maximum-gate",
    bend="tn_maximum.bend",
    oracle="tn_maximum-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_maximum-gate: 4 rows, 3 lanes -- tn_maximum "
                        "agrees with CPython's Tensor.maximum "
                        "(no-broadcasting case)"))