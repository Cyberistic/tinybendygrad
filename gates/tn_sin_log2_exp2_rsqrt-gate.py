#!/usr/bin/env python3
"""tn_sin_log2_exp2_rsqrt-gate.py -- THE GATE for the four ports.

    .venv/bin/python gates/tn_sin_log2_exp2_rsqrt-gate.py

ELEVEN ROWS, THREE LANES. CPython:
  - Tensor.sin            (elementwise.py:494): return self.alu(Ops.SIN)
  - Tensor.log2           (elementwise.py:531): return self.alu(Ops.LOG2)
  - Tensor.exp2           (elementwise.py:543): return self.alu(Ops.EXP2)
  - Tensor.rsqrt          (elementwise.py:820): return self.sqrt().reciprocal()

The first three are pure one-liners. `rsqrt` is a chain: `tn_sqrt(t)` produces
SQRT{src=[t]}, then `tn_alu(sqrt, O.OpsRECIPROCAL{}, Nil{})` wraps it in
RECIPROCAL{src=[sqrt]}. The wall text at `mixin/elementwise.bend:859` called
`rsqrt` "blocked on sqrt's own fold, not on a constant" -- that note is now
stale: the chain is built by `tn_alu`, not by a fold.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "sin_op_is_sin",
    "log2_op_is_log2",
    "exp2_op_is_exp2",
    "rsqrt_op_is_reciprocal",
    "rsqrt_arg_is_anone",
    "rsqrt_has_one_src",
    "sin_does_not_mutate_input",
    "sin_is_reachable",
    "log2_is_reachable",
    "exp2_is_reachable",
    "rsqrt_is_reachable",
)

GATE = Gate(
    "tn_sin_log2_exp2_rsqrt-gate",
    bend="tn_sin_log2_exp2_rsqrt.bend",
    oracle="tn_sin_log2_exp2_rsqrt-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_sin_log2_exp2_rsqrt-gate: 11 rows, 3 lanes -- "
                        "tn_sin, tn_log2, tn_exp2 (pure one-liners) and tn_rsqrt "
                        "(chained sqrt -> reciprocal) all agree with CPython"))