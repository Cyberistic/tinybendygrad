#!/usr/bin/env python3
"""divandmod-gate.py -- THE GATE for `tinybendygrad/uop/divandmod.bend`'s
`fold_divmod_general`.

    .venv/bin/python gates/divandmod-gate.py
    .venv/bin/python gates/divandmod-gate.py --plant

THE CLAIM.  The port's `remove_nested_mod` arm (`divandmod.py:27-35`) rewrites
`(a%k + b)%c` into `(a+b)%c` WHEN `c` DIVIDES `k`, AND IT DOES NOT REWRITE
OTHERWISE.  CPython IS THE ORACLE, AND THE TWO READ THE **SAME CASE FILE** --
`gates/divandmod-cases.rows` -- so the port and the oracle cannot be measuring
two different graphs, which is the defect a hand-written pair of fixtures has by
construction.

THE THREE ROWS, AND EACH IS A CLAIM:

    rmn_fires  `(x%4 + y)%2` -> `(x + y + 0)%2`.  2 DIVIDES 4, SO THE ARM FIRES.
    rmn_two    `(x%8 + y + z)%2` -> `(x + y + z + 0)%2`.  TWO NESTED MODS.
    zero       `(x%4 + y)%0` -> PYTHON RAISES `ZeroDivisionError`.

THE ANSWER IS THE **TREE** AND NOT A NUMBER, AND THE REASON IS MEASURED: THE
ARM's CLAIM IS ABOUT THE SHAPE OF THE REWRITE AND NOT ABOUT ITS VALUE, AND A
CONST/CONST ANSWER WOULD LOSE THE `+ 0` THAT THE ARM ADDS BACK.  THE FORM IS
THE PORT's OWN: `Ops.NAME` FOR AN OP, `P<name>` FOR A PARAM AND `CONST(v)`
FOR A CONST.

AND THE CONST/CONST ARM (`divandmod.py:12-13`) IS **NOT** HERE, AND THE REASON
IS MEASURED: UPSTREAM's `canonicalize` REWRITES `SUB` INTO
`ADD(x, MUL(MUL(q,y),C(-1)))`, SO THE TWO TREES DIFFER WHILE THE VALUES ARE
EQUAL.  **THE EXISTING GATE ALREADY COVERS THAT ARM BY VALUE**
(`gates/divandmod-gate.bend`'s `dmc.den`), SO A TREE COMPARISON THERE WOULD BE
A ROW THAT CAN NEVER PASS.

EXIT: 0 green · 1 red · 3 REFUSED (a precondition was absent) · 5 DEAD (it ran and
measured nothing).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# AND THE ROW COUNT IS **THE CASE FILE's OWN ROW COUNT** AND NOT A NUMBER
# ANYONE KEEPS IN STEP.  MEASURED 2026-11-24, `gates/divandmod-cases.rows` HELD
# FIVE AND THE LANE EMITTED FIVE; MEASURED 2026-11-25 IT HOLDS NINE (THE
# `factor_remainder` ARM ADDED FOUR) AND THE LANE EMITS NINE.  **THE COUNT IS
# READ FROM THE FILE** -- A HAND-KEPT COUNT IS A SECOND COPY OF A LIST A
# GENERATOR ALREADY OWNS, AND IT IS WHAT THE AGENT RULES CALL OUT BY NAME.
CASES = Path(__file__).resolve().parent / "divandmod-cases.rows"


def case_count():
    """THE CASE FILE's ROWS, AND A COMMENT OR A BLANK LINE IS NOT A ROW."""
    n = 0
    for raw in CASES.read_text().split("\n"):
        line = raw.strip()
        if line and not line.startswith("#"):
            n += 1
    return n


ROWS = case_count()

GATE = Gate(
    "divandmod-gate",
    bend="gates/divandmod-driver.bend",
    oracle="gates/divandmod-oracle.py",
    rows=ROWS,
    compared=ROWS,
    order="positional",
)

if __name__ == "__main__":
    sys.exit(main(GATE, f"divandmod-gate: {ROWS} rows compared -- the remove_nested_mod, "
                        "divide_by_gcd and factor_remainder arms agree with the CPython run"))
