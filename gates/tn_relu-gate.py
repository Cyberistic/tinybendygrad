#!/usr/bin/env python3
"""tn_relu-gate.py -- THE GATE for `tn_relu`.

    .venv/bin/python gates/tn_relu-gate.py

FIVE ROWS, THREE LANES. CPython's `Tensor.relu` (elementwise.py:674) is
`(self > 0).where(self, 0)`. The wall text at `nn/__init__.bend:241` cited
`_broadcasted` as the blocker for `where`. The `(self > 0)` is `tn_rcmplt`
(port), the `where(self, 0)` is `tn_where` (port), the `0` is `O.UOp.const`
(port). The port is a chain: `tn_rcmplt(t, c0)`, then `tn_where(gt0, t, c0t)`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "relu_op_is_where",
    "relu_arg_is_anone",
    "relu_does_not_mutate_input",
    "relu_has_three_srcs",
    "relu_is_reachable",
    "relu_src2_is_const0",
)

GATE = Gate(
    "tn_relu-gate",
    bend="tn_relu.bend",
    oracle="tn_relu-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_relu-gate: 6 rows, 3 lanes -- tn_relu's op/arg/srcs/purity "
                        "and reachability all agree with CPython's Tensor.relu "
                        "(the WHERE-chain composition; _broadcasted seam still "
                        "walls the broadcasting case)"))