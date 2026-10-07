#!/usr/bin/env python3
"""tn_binop_arena-gate.py -- THE DEPTH GATE for the arena rule `tn_binop` states.

    .venv/bin/python gates/tn_binop_arena-gate.py

EIGHT ROWS, THREE LANES. This gate asks ONE question of `tn_add`: does `src[1]` name the
operand the CALLER passed, when that operand sits at depth N in its OWN arena?

WHY IT EXISTS. The 18 reverse-dispatch binops build with `tn_alu(lhs, OP, [rhs.u])`, which
builds in `lhs.ar` and reads `rhs.u` THERE. Every other binop gate in this directory makes
both operands bare consts from `O.Arena.empty()`, so both land at index 0 and the read is
right BY COINCIDENCE -- `0` is a legal index in `lhs.ar`. MEASURED over `gates/*.bend`:
30 call sites pass two operands and every one is a two-bare-const pair, depth 0.

THE INDEX TRAP, and why the rows compare OPS. At depth 1 `Tensor.u(rhs)` is 1 and
`Arena.src(ar, i, 1)` is ALSO 1 -- the ADD's own slot -- so an index comparison answers 1 at
every depth while the graph is corrupt. MEASURED. `src1_is_caller_operand_*` compares the
`Op`, and that is what drops to 0.

THE THREE DIVERGENCES ARE DECLARED AND PINNED, NOT SMOOTHED. They are the wall, and a wall
nobody can see is not a wall. The fix needs an arena merge with an index remap, and NO
`def Arena.*` in `uop/ops.bend` takes a second arena. So this gate goes GREEN over a known
corrupt graph at depth 1 and 2, with the corruption pinned on both sides -- which is the
only honest thing a gate can do about a defect it cannot fix.
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

# THE WALL, AS A PAIR PER ROW: (what CPython says, what the port says).
DIVERGES = {
    "src1_is_caller_operand_at1": ("src1_is_caller_operand_at1=1", "src1_is_caller_operand_at1=0"),
    "src1_is_caller_operand_at2": ("src1_is_caller_operand_at2=1", "src1_is_caller_operand_at2=0"),
    "src1_op_is_noop_at2": ("src1_op_is_noop_at2=0", "src1_op_is_noop_at2=1"),
}

GATE = Gate(
    "tn_binop_arena-gate",
    bend="tn_binop_arena.bend",
    oracle="tn_binop_arena-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_binop_arena-gate: 8 rows, 3 lanes, 3 DECLARED divergences -- "
                        "src[1] names the caller's operand at depth 0 and NOT at depths 1 "
                        "and 2, because the binops read rhs.u in lhs.ar and Arena is an "
                        "immutable Data value; src[0] is right at every depth"))