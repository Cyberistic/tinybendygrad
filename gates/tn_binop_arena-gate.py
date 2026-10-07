#!/usr/bin/env python3
"""tn_binop_arena-gate.py -- THE DEPTH GATE for the arena rule `tn_binop` states.

    .venv/bin/python gates/tn_binop_arena-gate.py

EIGHT ROWS, THREE LANES, ZERO DIVERGENCES. This gate asks ONE question of `tn_add`: does
`src[1]` name the operand the CALLER passed, when that operand sits at depth N in its OWN
arena? IT NOW ANSWERS 1 AT EVERY DEPTH, and it used to answer 0 at depths 1 and 2 -- which
is why the three `diverges` this gate used to declare are GONE. `O.Arena.merge`
(`ops.bend`, beside `UOp.new`) re-interns the right operand's arena into the left one's and
re-mints its index, so the sibling case has a common descendant and the corruption cannot
occur.

WHY IT EXISTS. The 18 reverse-dispatch binops USED TO build with `tn_alu(lhs, OP, [rhs.u])`,
which builds in `lhs.ar` and reads `rhs.u` THERE; they now build with `tn_binop`, which
merges first. Every other binop gate in this directory makes both operands bare consts from
`O.Arena.empty()`, so both land at index 0 and the old read was right BY COINCIDENCE -- `0`
is a legal index in `lhs.ar`. MEASURED over `gates/*.bend`: 30 call sites pass two operands
and every one is a two-bare-const pair, depth 0. Depth is what this gate varies.

THE INDEX TRAP, and why the rows compare OPS. At depth 1 `Tensor.u(rhs)` is 1 and
`Arena.src(ar, i, 1)` is ALSO 1 -- the ADD's own slot -- so an index comparison answers 1 at
every depth while the graph is corrupt. MEASURED. `src1_is_caller_operand_*` compares the
`Op`, and that is what drops to 0.

THE WALL THIS GATE USED TO CARRY IS CLOSED, and the closure is visible HERE rather than in a
claim. Before the merge, `src1_op_is_noop_at2` was 1 in the port and 0 in CPython -- the
bottom, read out of range. It is 0 in both now.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "src1_is_caller_operand_at0",
    "src1_is_caller_operand_at1",
    "src1_is_caller_operand_at2",
    "src1_op_is_const_at0",
    "src1_op_is_noop_at2",
    "src0_is_caller_lhs_at0",
    "src0_is_caller_lhs_at1",
    "src0_is_caller_lhs_at2",
)

GATE = Gate(
    "tn_binop_arena-gate",
    bend="tn_binop_arena.bend",
    oracle="tn_binop_arena-oracle.py",
    rows=len(ROWS),
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_binop_arena-gate: 8 rows, 3 lanes, 0 divergences -- src[1] "
                        "names the caller's operand at depths 0, 1 AND 2; the "
                        "sibling-arena wall is CLOSED by O.Arena.merge"))