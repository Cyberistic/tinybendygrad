#!/usr/bin/env python3
"""tn_logical_not-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_logical_not`.

    .venv/bin/python gates/tn_logical_not-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the claims
that `tn_logical_not` does what CPython's `Tensor.logical_not` (elementwise.py:49) does:
`return self.cast(dtypes.bool).ne(True)`. The graph is identical to the BOOL ARM of
`tn_bitwise_not` (sibling elementwise methods at :49, :145).

THE FOUR `int_input_*` ROWS EXIST BECAUSE THE FIRST FOUR BLINDED. They all seed the
arena with `CBool{True{}}`, and `O.UOp.const` interns, so the `True` is already present
and the const index is the one both lanes name. The `int_input_*` rows seed `CInt{4}`,
and they are the rows that caught `Found.ar` snapshotting an immutable `Arena`
(`ops.bend:1255`) while the CMPNE was built in the PRE-const arena -- a CMPNE that was
its own `src[1]`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "logical_not_op_is_cmpne",
    "logical_not_arg_is_anone",
    "logical_not_does_not_mutate_input",
    "logical_not_is_reachable",
    "int_input_src1_is_const",
    "int_input_graph_has_2_srcs",
    "int_input_src1_is_not_self",
    "int_input_src0_is_cast",
)

GATE = Gate(
    "tn_logical_not-gate",
    bend="tn_logical_not.bend",
    oracle="tn_logical_not-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_logical_not-gate: 8 rows, 3 lanes -- tn_logical_not's "
                        "CMPNE/CAST/CONST graph on a bool AND an int input "
                        "(op/arg/purity/reachability/srcs/no-self-reference) all agree "
                        "with CPython's Tensor.logical_not"))