#!/usr/bin/env python3
"""tn_nary_arena-gate.py -- THE DEPTH GATE for the THREE-operand node.

    .venv/bin/python gates/tn_nary_arena-gate.py

TWELVE ROWS, THREE LANES, ZERO DIVERGENCES. `gates/tn_binop_arena-gate.py` covers the
two-operand node; this covers `OpsWHERE`, which has THREE operands that may live in three
unrelated arenas -- a shape `tn_binop` cannot reach.

WHAT IT CAUGHT. `tn_where` was `tn_alu(cond, WHERE, [x.u, y.u])`, reading both src indices in
`cond.ar`. Measured in the port with `y` at depth 1 in its own arena: `3 Ops.WHERE/3 Ops.CONST
Ops.CONST Ops.NOOP` -- `src[2]` was the bottom. `tn_threefry` had the same defect with two
operands (`3 Ops.THREEFRY/2 Ops.CONST Ops.NOOP`). Both merge first now.

WHY DEPTH IS THE ONLY THING THAT VARIES. Every other gate in this directory builds both (or
all three) operands from `O.Arena.empty()`, so every operand sits at index 0 and a raw index
read lands on a legal slot by accident. `no_src_is_noop_at_*` is the row that names the
failure mode directly: `Ops.NOOP` is the bottom, and an out-of-range read answers it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "where_src0_is_caller_at_d1",
    "where_src1_is_caller_at_d1",
    "where_src2_is_caller_at_d1",
    "where_src0_is_caller_at_d0",
    "where_src1_is_caller_at_d0",
    "where_src2_is_caller_at_d0",
    "where_all_three_at_depth1",
    "where_no_src_is_noop_at_d1",
    "where_no_src_is_noop_at_d0",
    "threefry_src1_is_caller_at_d1",
    "threefry_src0_is_caller_at_d1",
    "threefry_no_src_is_noop_at_d1",
)

GATE = Gate(
    "tn_nary_arena-gate",
    bend="tn_nary_arena.bend",
    oracle="tn_nary_arena-oracle.py",
    rows=len(ROWS),
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_nary_arena-gate: 12 rows, 3 lanes, 0 divergences -- tn_where's "
                        "THREE operands and tn_threefry's two are re-minted before they are "
                        "read, at depth 0 and depth 1; no src is ever the NOOP bottom"))