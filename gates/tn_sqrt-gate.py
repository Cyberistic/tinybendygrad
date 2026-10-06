#!/usr/bin/env python3
"""tn_sqrt-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_sqrt`.

    .venv/bin/python gates/tn_sqrt-gate.py

FIVE ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_sqrt` does what CPython's `Tensor.sqrt` (elementwise.py:480) does:
`return self.alu(Ops.SQRT)`. The wall that lived at `nn/__init__.bend:241`
("`Tensor.sqrt` ... NOT a def in `tensor.bend`") was closed by porting the one-liner.

WHAT THIS IS FOR. `tn_sqrt` is a `tn_alu` over `OpsSQRT{}` with an empty src list, and
`tn_alu` is the `alu` builder the file already has. CPython's `Tensor.sqrt` is
`self.alu(Ops.SQRT)`, and a 1-line `tn_sqrt` that calls `tn_alu(t, O.OpsSQRT{}, Nil{})`
matches it. Five rows cover the four properties a future unit might break (op, src,
arg, purity) plus the reachability row that names the wall.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "sqrt_op_is_sqrt",            # .sqrt() sets op to SQRT.
    "sqrt_src_is_input",          # .sqrt() sets srcs to (self,).
    "sqrt_arg_is_anone",          # .sqrt() sets arg to None.
    "sqrt_does_not_mutate_input", # the input still has its original op.
    "sqrt_is_reachable",          # the def is callable (the wall was 0 defs).
)

GATE = Gate(
    "tn_sqrt-gate",
    bend="tn_sqrt.bend",
    oracle="tn_sqrt-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_sqrt-gate: 5 rows, 3 lanes -- tn_sqrt's op/src/arg set, "
                        "input purity and reachability all agree with CPython's "
                        "Tensor.sqrt (the one-line port closes nn/__init__.bend:241)"))