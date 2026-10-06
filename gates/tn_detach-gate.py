#!/usr/bin/env python3
"""tn_detach-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_detach`.

    .venv/bin/python gates/tn_detach-gate.py

FIVE ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_detach` does what CPython's `Tensor.detach` (elementwise.py:43) does:
`return self.alu(Ops.DETACH)`. The wall that lived at `nn/__init__.bend:241`
("`Tensor.detach` ... NOT a def in `tensor.bend`") was closed by porting the
one-liner that mirrors `tn_sqrt`'s shape: a single `tn_alu` call with
`OpsDETACH{}` and an empty src list.

WHAT THIS IS FOR. `tn_detach` is the second of the four methods the wall named.
`Tensor.where` and `Tensor.square` remain walled: `where` is
`self.alu(Ops.WHERE, x, y)` with a `_broadcasted` up-stream step, `square` is
`self * self` (the `__mul__` method is a separate wall, no arith ops are ported yet).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "detach_op_is_detach",          # .detach() sets op to DETACH.
    "detach_src_is_input",          # .detach() sets srcs to (self,).
    "detach_arg_is_anone",          # .detach() sets arg to None.
    "detach_does_not_mutate_input", # the input still has its original op.
    "detach_is_reachable",          # the def is callable (the wall was 0 defs).
)

GATE = Gate(
    "tn_detach-gate",
    bend="tn_detach.bend",
    oracle="tn_detach-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_detach-gate: 5 rows, 3 lanes -- tn_detach's op/src/arg set, "
                        "input purity and reachability all agree with CPython's "
                        "Tensor.detach (the one-line port closes the second of the four "
                        "Tensor methods nn/__init__.bend:241 named)"))