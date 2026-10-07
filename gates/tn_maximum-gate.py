#!/usr/bin/env python3
"""tn_maximum-gate.py -- THE GATE for `tn_maximum` / `tn_rmaximum`.

    .venv/bin/python gates/tn_maximum-gate.py

SEVEN ROWS, THREE LANES. CPython's `Tensor.maximum` (elementwise.py:378) is
`self._binop(Ops.MAX, x, False)`. The wall text at `nn/__init__.bend:241`
cited `_broadcasted` as the blocker. The no-broadcasting case (two same-
shape Tensors) reduces to `self.alu(MAX, x.uop)`, the same shape as
`tn_add` / `tn_mul`. The reverse arm is `__rmax__`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "max_op_is_max",
    "max_arg_is_anone",
    "max_does_not_mutate_input",
    "rmax_op_is_max",
    "rmax_arg_is_anone",
    "rmax_does_not_mutate_input",
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
    sys.exit(main(GATE, "tn_maximum-gate: 7 rows, 3 lanes -- tn_maximum / tn_rmaximum "
                        "both agree with CPython's Tensor.maximum / __rmax__ "
                        "(no-broadcasting case)"))