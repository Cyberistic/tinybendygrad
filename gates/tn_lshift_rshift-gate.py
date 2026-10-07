#!/usr/bin/env python3
"""tn_lshift_rshift-gate.py -- THE GATE for `tn_lshift` / `tn_rlshift` / `tn_rshift`.

    .venv/bin/python gates/tn_lshift_rshift-gate.py

NINE ROWS, THREE LANES. CPython's `Tensor.lshift` (elementwise.py:347) and
`Tensor.rshift` (elementwise.py:355) are `self._binop(Ops.SHL/SHR, x,
False)`. Same shape as the recent `_binop` ports with `OpsSHL{}` /
`OpsSHR{}`. The reverse arms `__rlshift__` / `__rrshift__` are the
`reverse=True` cases. The broadcasting case stays walled on `_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "lshift_op_is_shl",
    "lshift_arg_is_anone",
    "lshift_does_not_mutate_input",
    "rlshift_op_is_shl",
    "rlshift_arg_is_anone",
    "rlshift_does_not_mutate_input",
    "rshift_op_is_shr",
    "rshift_arg_is_anone",
    "rshift_does_not_mutate_input",
)

GATE = Gate(
    "tn_lshift_rshift-gate",
    bend="tn_lshift_rshift.bend",
    oracle="tn_lshift_rshift-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_lshift_rshift-gate: 9 rows, 3 lanes -- tn_lshift / "
                        "tn_rlshift / tn_rshift all agree with CPython's "
                        "Tensor.lshift / __rlshift__ / rshift (no-broadcasting case)"))