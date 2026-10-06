#!/usr/bin/env python3
"""tn_trunc_reciprocal_threefry-gate.py -- THE GATE for the three one-liner ports.

    .venv/bin/python gates/tn_trunc_reciprocal_threefry-gate.py

NINE ROWS, THREE LANES. CPython's `Tensor.trunc` (elementwise.py:474) is
`return self.alu(Ops.TRUNC)`, `Tensor.reciprocal` (elementwise.py:460) is
`return self.alu(Ops.RECIPROCAL)`, and `Tensor.threefry(seed)` (elementwise.py:457)
is `return self.alu(Ops.THREEFRY, seed)`. The three ports mirror the same
`tn_alu` builder shape as `tn_sqrt`, `tn_detach`, `tn_contiguous_backward`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "trunc_op_is_trunc",
    "trunc_does_not_mutate_input",
    "reciprocal_op_is_reciprocal",
    "reciprocal_does_not_mutate_input",
    "threefry_op_is_threefry",
    "threefry_srcs_are_self_and_seed",
    "threefry_arg_is_anone",
    "trunc_is_reachable",
    "threefry_is_reachable",
)

GATE = Gate(
    "tn_trunc_reciprocal_threefry-gate",
    bend="tn_trunc_reciprocal_threefry.bend",
    oracle="tn_trunc_reciprocal_threefry-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_trunc_reciprocal_threefry-gate: 9 rows, 3 lanes -- "
                        "tn_trunc, tn_reciprocal, tn_threefry all agree with CPython "
                        "on op/src/arg/purity/reachability"))