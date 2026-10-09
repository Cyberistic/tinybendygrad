#!/usr/bin/env python3
"""tn_isnan-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_isnan`.

    .venv/bin/python gates/tn_isnan-gate.py

FIVE ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_isnan` does what CPython's `Tensor.isnan` (elementwise.py:603) does:
`return self != self`. The graph is a single CMPNE with the input tensor on both
srcs -- the same shape `mo_isnan` (`mixin/op.bend:986`) builds at the reduction
layer.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "isnan_op_is_cmpne",
    "isnan_arg_is_anone",
    "isnan_has_self_src",
    "isnan_does_not_mutate_input",
    "isnan_is_reachable",
)

GATE = Gate(
    "tn_isnan-gate",
    bend="tn_isnan.bend",
    oracle="tn_isnan-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_isnan-gate: 5 rows, 3 lanes -- tn_isnan's CMPNE/self-src "
                        "graph (op/arg/srcs/purity/reachability) all agree with "
                        "CPython's Tensor.isnan"))
