#!/usr/bin/env python3
"""bcast-gate.py -- the gate for `_broadcast_to`, the dance `mixin/bcast.bend` hoisted.

    .venv/bin/python gates/bcast-gate.py

WHY IT EXISTS: `gradient.bend`'s `gbcast` and `movement.bend`'s `mxw_bcast` were TWO
implementations, and the gradient one carried the FULL target in the EXPAND where CPython
carries the NEW dims only (measured: `expand(1,10,49)` is `PERMUTE(EXPAND(x'))` with
`EXPAND.shape == (10,1,49)`, so the port's node carried `len(dst)+len(src)` dims -- rank 6 and
12 in the training fixture). The dance is now `mixin/bcast.bend` and both callers delegate, and
THIS GATE is what makes the shared def a claim rather than a refactor: neither `gates/*.bend`
nor `gates/movement-gate.bend` named `mxw_bcast` or `BC.bcast` before it.

THE ROWS ARE STRUCTURAL, not dimensional: `name=<result op>/<src0 op>/<src0 dims>`. The wrong
dance cannot produce them (its src0 op is always EXPAND and its src0 dims are wider), and the
identity pair pins that an equal shape mints NOTHING (`RESHAPE/BUFFER/6` is the caller's own
reshape, returned unchanged).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, PASS, gate as run_gate

GATE = Gate(
    "bcast-gate",
    bend="bcast-gate.bend",
    oracle="bcast-gate-oracle.py",
    rows=4,
    pins=[("py", "b_rank_up"), ("py", "b_size1"), ("py", "b_both"), ("py", "b_id"),
          ("bd", "b_rank_up"), ("bd", "b_size1"), ("bd", "b_both"), ("bd", "b_id")],
)

if __name__ == "__main__":
    sys.exit(run_gate(GATE, "bcast-gate: 4 rows, the dance agrees with CPython's expand"))
