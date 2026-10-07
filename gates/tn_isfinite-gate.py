#!/usr/bin/env python3
"""tn_isfinite-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_isfinite`.

    .venv/bin/python gates/tn_isfinite-gate.py

SIX ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_isfinite` does what CPython's `Tensor.isfinite` (elementwise.py:623) does:
`(self.isinf() | self.isnan()).logical_not()`.

`src[0]` IS NOT A SHARED ROW. It is CAST in the port -- `tn_logical_not` keeps the explicit
`cast(bool)` -- and OR in CPython, which folds the identity bool cast out. That difference is
recorded at `mixin/elementwise.bend`'s `isfinite` block rather than asserted away.

THE `src1_is_*` ROWS EXIST BECAUSE `op` / `arg` / `nsrc` CANNOT SEE THE BUG THEY CAUGHT.
`logical_not` was building its CMPNE in the arena as it stood BEFORE the `CONST{True}` was
interned; `Arena` is an immutable `Data` value (`ops.bend:1255`), so `Found.ar` snapshots,
and the CMPNE landed on the slot the const index names -- a node that was its own `src[1]`.
The graph typechecked and every op/arg/nsrc row answered 1.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "isfinite_op_is_cmpne",
    "isfinite_arg_is_anone",
    "isfinite_has_two_top_srcs",
    "isfinite_is_reachable",
    "isfinite_src1_is_const",
    "isfinite_src1_is_not_self",
)

GATE = Gate(
    "tn_isfinite-gate",
    bend="tn_isfinite.bend",
    oracle="tn_isfinite-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_isfinite-gate: 6 rows, 3 lanes -- tn_isfinite's CMPNE/2-srcs "
                        "graph (op/arg/nsrc/reachability + src[1] is the CONST and is not "
                        "the node itself) all agree with CPython's Tensor.isfinite; the "
                        "src[0] CAST-vs-OR fold is recorded at mixin/elementwise.bend"))