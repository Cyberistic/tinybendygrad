#!/usr/bin/env python3
"""tn_where-gate.py -- THE GATE for `tn_where` (the no-broadcasting case).

    .venv/bin/python gates/tn_where-gate.py

FIVE ROWS, THREE LANES. CPython's `Tensor.where` (elementwise.py:426) is
`x, y = self.ufix(x)._broadcasted(y); return self.alu(Ops.WHERE, x, y)`. The
`_broadcasted` step is walled (fold reads and a `least_upper_dtype` helper), but
the no-broadcasting case reduces to `tn_alu(cond, WHERE, [x, y])`. The wall
text at `nn/__init__.bend:241` called `where` "needs `_broadcasted`" -- that
note is now stale for the no-broadcasting case. `tn_where` covers the
no-broadcasting case; the broadcasting case stays walled.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "where_op_is_where",
    "where_arg_is_anone",
    "where_srcs_are_cond_x_y",
    "where_does_not_mutate_input",
    "where_is_reachable",
)

GATE = Gate(
    "tn_where-gate",
    bend="tn_where.bend",
    oracle="tn_where-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_where-gate: 5 rows, 3 lanes -- tn_where's op/arg/srcs "
                        "set, input purity, and reachability all agree with CPython's "
                        "Tensor.where (the no-broadcasting case; broadcasting case "
                        "stays walled on _broadcasted)"))