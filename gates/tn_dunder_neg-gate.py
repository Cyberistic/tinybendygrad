#!/usr/bin/env python3
"""tn_dunder_neg-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_dunder_neg`.

    .venv/bin/python gates/tn_dunder_neg-gate.py

FIVE ROWS, THREE LANES. CPython's `Tensor.__neg__` (elementwise.py:261) is
`return self.neg()`. The port's `tn_neg` (tensor.bend:435) covers BOTH arms:
the bool arm goes through `tn_logical_not` (CMPNE), the arith arm goes through
`tn_neg.arith` (MUL with -1 const). `tn_dunder_neg` is a thin wrapper that
delegates to `tn_neg`. The five rows cover the bool op, the int op, the int
srcs, the input purity, and reachability. `Tensor.__neg__` is the unary-`-`
dunder and is implicitly ported by `Tensor.neg`'s port; this gate pins the
dunder's name.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "dunder_neg_bool_op_is_cmpne",       # bool input: .__neg__() builds a CMPNE (the neg/neg(bool) graph).
    "dunder_neg_int_op_is_mul",          # int input: .__neg__() builds a MUL (the neg/neg(arith) graph).
    "dunder_neg_int_srcs_are_self_and_m1", # the MUL's srcs are (self, -1 const).
    "dunder_neg_int_does_not_mutate_input", # the input still has its original op.
    "dunder_neg_is_reachable",           # the def is callable (the wall was 0 dunder ports).
)

GATE = Gate(
    "tn_dunder_neg-gate",
    bend="tn_dunder_neg.bend",
    oracle="tn_dunder_neg-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_dunder_neg-gate: 5 rows, 3 lanes -- tn_dunder_neg (the __neg__ "
                        "dunder wrapper) agrees with CPython on bool/arith op, arith srcs, "
                        "input purity and reachability (delegates to fully-ported tn_neg)"))