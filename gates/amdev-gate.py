#!/usr/bin/env python3
"""amdev-gate.py -- the gate for `tinybendygrad/runtime/support/am/amdev.bend`.

    .venv/bin/python gates/amdev-gate.py

552 rows, all compared, 0 disagreements.

WHAT THE ROWS CLAIM. `amdev.py` is the AMDGPU device layer: the register
writes, the ring arithmetic, the doorbell strides and the firmware-name ladder.
Every row is a NUMBER or a NAME, and both are arithmetic over the hardware's
registers -- so the oracle is upstream's own answers.

THE ORACLE READS A RECORDED CPYTHON RUN BY PATH.
`oracles/tinybendygrad_runtime_support_am_amdev.bend.rows` holds the 564 lines
(552 rows and 12 blank separators), and
the oracle lane reads that file rather than transcribing it: a transcription of
552 rows is 552 places to be wrong, and this tree has measured that cost -- the
`renderer/cstyle.bend` unit shipped 215 hand-typed expectations and SEVENTEEN
were wrong.

THE LANES ARE ALIGNED BY ROW NAME, and the order is not a claim: the port groups
its rows by fixture and the oracle prints them in one sequence.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "amdev-gate",
    bend="gates/amdev-gate.bend",
    oracle="gates/amdev-oracle.py",
    # THE COUNT IS THE NON-EMPTY LINE COUNT: the port prints a blank line
    # between the `aids_*` families (12 of them) and `gatekit` counts the lines
    # that are not blank. MEASURED 2026-11-11: the gate asked for 564 and the
    # lane produced 552, and the gate said DEAD -- a count that includes the
    # separator blanks is a count of the wrong thing.
    rows=552,
    compared=552,
    order="by_name",
)

if __name__ == "__main__":
    sys.exit(main(GATE, "amdev-gate: 552 rows compared -- the AMDGPU register and "
                        "ring arithmetic agrees with the CPython run"))
