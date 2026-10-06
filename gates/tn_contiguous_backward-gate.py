#!/usr/bin/env python3
"""tn_contiguous_backward-gate.py -- THE GATE for `tn_contiguous_backward`.

    .venv/bin/python gates/tn_contiguous_backward-gate.py

FIVE ROWS, THREE LANES. CPython's `Tensor.contiguous_backward` (elementwise.py:68)
is `return self.alu(Ops.CONTIGUOUS_BACKWARD)`. The port mirrors the `tn_detach` /
`tn_sqrt` shape: a single `tn_alu` call with `OpsCONTIGUOUS_BACKWARD{}`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "contiguous_backward_op",
    "contiguous_backward_src_is_input",
    "contiguous_backward_arg_is_anone",
    "contiguous_backward_does_not_mutate_input",
    "contiguous_backward_is_reachable",
)

GATE = Gate(
    "tn_contiguous_backward-gate",
    bend="tn_contiguous_backward.bend",
    oracle="tn_contiguous_backward-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_contiguous_backward-gate: 5 rows, 3 lanes -- "
                        "tn_contiguous_backward's op/src/arg set, input purity and "
                        "reachability all agree with CPython's Tensor.contiguous_backward"))