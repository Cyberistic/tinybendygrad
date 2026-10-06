#!/usr/bin/env python3
"""tn_bitwise_not-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_bitwise_not`.

    .venv/bin/python gates/tn_bitwise_not-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the
claims that `tn_bitwise_not` (the bool arm of elementwise.py:145) does what
CPython's `Tensor.bitwise_not` does on a bool input: it builds the same
CAST-to-bool + CONST-True + CMPNE graph. The arith arms stay walled on the
dtype-fold + arith-ops seam, named in the wall text.

WHAT THIS IS FOR. Closes the third of the four `nn/__init__.bend:241` walls.
The remaining two: `where` (needs `_broadcasted`) and `square` (needs
`__mul__`).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "bitnot_op_is_cmpne",
    "bitnot_arg_is_anone",
    "bitnot_src_is_cast_and_true",
    "bitnot_cast_in_to_bool_cast",
    "bitnot_cast_arg_is_adt_bool",
    "bitnot_true_const_arg_is_cbool_true",
    "bitnot_does_not_mutate_input",
    "bitnot_is_reachable",
)

GATE = Gate(
    "tn_bitwise_not-gate",
    bend="tn_bitwise_not.bend",
    oracle="tn_bitwise_not-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_bitwise_not-gate: 8 rows, 3 lanes -- tn_bitwise_not's bool-arm "
                        "CMPNE/CAST/CONST graph (op/arg/srcs/inner nodes/input purity/reachability) "
                        "all agree with CPython's Tensor.bitwise_not for a bool input "
                        "(the arith arms stay WALL'd on the dtype-fold seam)"))