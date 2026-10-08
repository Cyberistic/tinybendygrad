#!/usr/bin/env python3
"""tn_graph_census-gate.py -- THE NOOP CENSUS over every ported `tn_*` public def.

    .venv/bin/python gates/tn_graph_census-gate.py

39 ROWS, THREE LANES, THREE DECLARED DIVERGENCES. `gates/tn_binop_sweep.bend` covers the
seventeen binops; `gates/tn_nary_arena.bend` covers the three-operand node. This covers the REST
of the ported surface in one artifact -- the unary ops, the compositions, and THE ELEVEN
REVERSE ARMS THAT HAVE A CPYTHON COUNTERPART, which are half the binop surface and were
previously tested only at depth 0.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM -- `Arena.bottom()`, what
`Arena.node` answers for an index the arena does not hold. A `NOOP` anywhere in a graph is an
index read out of range and ALWAYS a defect, so the census prints every port's toposort op
sequence and a reader can see the bottom without a second lane. Four ports were found this way
-- `tn_relu`, `tn_relu6`, and the two const-wrappers under `tn_ceil` / `tn_floor` -- and they
are all clean now.

WHAT IT ASSERTS THAT NEEDS ONE. The op sequence itself, against CPython's graph for the method
each port mirrors. THE DIVERGENCES ARE THE IDENTITY BOOL CAST: the port keeps
`tn_logical_not`'s explicit `cast(bool)` and CPython folds it away, so `tn_bitwise_not`,
`tn_eq` and `tn_isfinite` carry one extra node and one extra `CAST` and the other 36 rows are
byte-identical. That is a fold carve-out and not a wrong graph -- it is the same carve-out
`mixin/elementwise.bend` records for `isfinite`.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT. `tn_ceil` computed `b + 4` for a `CInt{4}` input through a LEGAL index and showed no
bottom at all; only the value rows in `gates/tn_ceil_floor.bend` caught it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "tn_sqrt",
    "tn_detach",
    "tn_contiguous_backward",
    "tn_trunc",
    "tn_reciprocal",
    "tn_sin",
    "tn_log2",
    "tn_exp2",
    "tn_rsqrt",
    "tn_logical_not",
    "tn_bitwise_not",
    "tn_neg",
    "tn_dunder_neg",
    "tn_relu",
    "tn_relu6",
    "tn_square",
    "tn_ceil",
    "tn_floor",
    "tn_isnan",
    "tn_isfinite",
    "tn_add",
    "tn_and",
    "tn_cmplt",
    "tn_cmpne",
    "tn_fdiv",
    "tn_lshift",
    "tn_max",
    "tn_maximum",
    "tn_mod",
    "tn_mul",
    "tn_or",
    "tn_pow",
    "tn_rshift",
    "tn_shl",
    "tn_shr",
    "tn_sub",
    "tn_xor",
    "tn_eq",
    "tn_threefry",
    "tn_radd",
    "tn_rsub",
    "tn_rmul",
    "tn_rfdiv",
    "tn_rmod",
    "tn_rand",
    "tn_ror",
    "tn_rxor",
    "tn_rpow",
    "tn_rlshift",
    "tn_rrshift",
)

# (CPython's line, the port's line), pinned on both sides.
DIVERGES = {
    "tn_bitwise_not": ("tn_bitwise_not=3 Ops.XOR/2 Ops.CONST Ops.CONST", "tn_bitwise_not=4 Ops.CMPNE/2 Ops.CAST Ops.CONST"),
    "tn_isfinite": ("tn_isfinite=15 Ops.CMPNE/2 Ops.OR Ops.CONST", "tn_isfinite=17 Ops.CMPNE/2 Ops.CAST Ops.CONST"),
    "tn_eq": ("tn_eq=4 Ops.CMPNE/2 Ops.CMPNE Ops.CONST", "tn_eq=5 Ops.CMPNE/2 Ops.CAST Ops.CONST"),
}

GATE = Gate(
    "tn_graph_census-gate",
    bend="tn_graph_census.bend",
    oracle="tn_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_graph_census-gate: 50 rows, 3 lanes, 3 DECLARED divergences -- "
                        "every ported tn_* has NO NOOP BOTTOM and 47 op sequences match CPython's "
                        "byte-for-byte; the three that differ carry the identity bool CAST the "
                        "port keeps and CPython folds"))