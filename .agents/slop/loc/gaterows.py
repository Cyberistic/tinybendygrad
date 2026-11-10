#!/usr/bin/env python3
"""gaterows.py -- THE ROW SET OF A `.bend` FILE, IN A CANONICAL ORDER.

    .venv/bin/python .agents/slop/loc/gaterows.py <file.bend>

**A ROW IS **A LINE THAT STARTS WITH AN IDENTIFIER AND A `=`** -- **AND THE
TREE HAS **TWO** SPELLINGS**, **MEASURED 2026-11-10**:

  * `name=value` -- `sqtt.bend`, `dsl.bend`, `ops_nv.bend`, `ops_qcom.bend` and
    `system.bend` (`sy_map_locked_linux=8192`).
  * `name = value   py=[value]` -- `ops_dsp.bend` (`dsp_sc_0000 = [0]   py=[0]`).

**AND THE BRIEF's REGEX (`^[A-Za-z][A-Za-z0-9_]*=`) **SEES NEITHER** OF
**THESE TWO SPELLINGS' TAILS**, **AND IT MATCHES **NO** `ops_dsp.bend` ROW AT
ALL** -- **MEASURED 2026-11-10: `rg '^[A-Za-z][A-Za-z0-9_]*='` OVER
`ops_dsp.bend`'s OUTPUT GAVE **0** ROWS **AND THE FILE HAS **496**.**  **SO
THE ROW SET MUST BE TAKEN **BY THE SHAPE**, **NOT BY ONE SPELLING.**

**AND THE ROW SET IS **SORTED** **SO THE DIFF IS ORDER-INDEPENDENT** -- **AND
THE SORT IS ON THE **WHOLE LINE**, **SO TWO ROWS WITH THE SAME NAME AND
DIFFERENT VALUES ARE BOTH KEPT** -- **AND **A ROW THAT CHANGED ITS VALUE IS A
DIFFERENCE**, **WHICH IS THE POINT.**
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# **A ROW: AN IDENTIFIER, **OPTIONAL SPACES**, `=`, **THEN ANYTHING**.**
ROW = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*=")


def rows_of(path: Path) -> list[str]:
    r = subprocess.run(
        [".venv/bin/python", "checks/bounded.py", "--mb", "3072", "--", "./bin/bend", str(path)],
        cwd=ROOT, capture_output=True, text=True, timeout=900)
    both = r.stdout + r.stderr
    out = []
    for line in both.splitlines():
        if ROW.match(line):
            out.append(line.rstrip())
    return sorted(out)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    for rel in sys.argv[1:]:
        for line in rows_of(ROOT / rel):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
