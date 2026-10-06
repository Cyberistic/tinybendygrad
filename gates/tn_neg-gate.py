#!/usr/bin/env python3
"""tn_neg-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_neg`.

    .venv/bin/python gates/tn_neg-gate.py

SEVEN ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_neg` does what CPython's `Tensor.neg` (elementwise.py:74) does:
`return self.logical_not() if self.dtype == dtypes.bool else self * (-1)`. Both arms are
ported in the file: the bool arm IS `tn_logical_not` (CMPNE/CAST/CONST, already gated
at `tn_logical_not-gate.py`); the arith arm IS `tn_neg.arith` = `MUL(self, -1)`. The
dispatcher is `tn_neg.go`, keyed on the fold of `tn_dtype`, and `tn_neg.is_bool.of` is
the fold-to-bool bridge. The seven rows are the ones the spec lists, no more, no less.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "neg_bool_op_is_cmpne",           # bool input: result op is CMPNE.
    "neg_bool_arg_is_anone",          # the CMPNE's arg is None.
    "neg_int_op_is_mul",              # int input: result op is MUL.
    "neg_int_srcs_are_self_and_m1",   # the MUL's srcs are (self, -1 const).
    "neg_int_is_new_node",            # the result is a new node, not the input's uop.
    "neg_int_does_not_mutate_input",  # the input still has its original op.
    "neg_is_reachable",               # the def is callable (the wall was 0 defs).
)

GATE = Gate(
    "tn_neg-gate",
    bend="tn_neg.bend",
    oracle="tn_neg-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_neg-gate: 7 rows, 3 lanes -- tn_neg's bool arm (CMPNE/ANone) "
                        "and arith arm (MUL/srcs/self-no-mutation) all agree with "
                        "CPython's Tensor.neg (the two-arm dispatch closes the wall "
                        "that lived on the elementwise.py:74 boundary)"))
