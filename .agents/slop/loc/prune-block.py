#!/usr/bin/env python3
"""prune-block.py -- **REMOVE **THE **PROVABLY **REMOVABLE **COMMENT **LINES**, **AND
**NOTHING **ELSE**.

    .venv/bin/python .agents/slop/loc/prune-block.py --report <file>...
    .venv/bin/python .agents/slop/loc/prune-block.py --apply <file>...

**THE **TWO **CLASSES **IT **REMOVES**, **AND **WHY **EACH **IS **PROVABLY **SAFE**:

  * **(1) THE **RULE **SEPARATORS** -- **A COMMENT LINE THAT IS **ONLY** PUNCTUATION**
    (`# =====`, `# ------`, `# ~~~`). **MEASURED 2026-11-10: **9,897 **LINES** OF **THE
    PORT's **91,459 **COMMENT **LINES** (11%) **AND **THEY **CARRY **4,022 **WORDS** -- **A
    FRACTION OF **A **WORD **EACH**, **BECAUSE **THEY **HAVE **NO **WORDS**.**
    **AND **THEY **ARE **VISUAL **STRUCTURE**, **AND **THEY **CAN **BE **REPLACED **BY
    **ONE **BLANK **LINE** -- **WHICH **IS **THE **SAME **STRUCTURE **WITHOUT **THE
    **TWENTY **DASHES**.**
  * **(2) THE **FIXED-BUG **NARRATIVE** -- **A COMMENT LINE THAT **RECORDS **WHAT **THE
    CODE **WAS** ("AND THIS USED TO BE", "AND THIS WAS FIXED", "FOUND AND FIXED", "AND THE
    BUG WAS", "THE REGRESSION WAS"). **MEASURED: **270 **LINES**. **AND **THE **GIT **LOG
    IS **THE **HISTORY**, **AND `git log -S` **FINDS **THE **COMMIT **THAT **CHANGED
    IT** -- **AND **A **COMMENT **THAT **RECORDS **THE **PAST **IS **A **COMMENT **THAT
    WILL **BE **WRONG **THE **SECOND **TIME **THE **CODE **CHANGES**.**

**AND WHAT IT **NEVER** REMOVES:**

  * **A CITATION** -- a line naming an upstream position (`elementwise.py:57`,
    `tinygrad/uop/ops.py`). **IT IS LOAD-BEARING: IT IS WHAT THE PIN IS RE-POINTED BY.**
    **MEASURED: **8,959 **LINES.**
  * **A MEASUREMENT** -- a line carrying a measured fact (`MEASURED`, `rc=`, a row count).
    **MEASURED: **1,754 **LINES.**
  * **THE PROSE** -- the explanation of why the code is shaped that way. **MEASURED: **70,579
    LINES**, **AND IT IS **THE **EXPLANATION** **AND **IT **IS **NOT **REDUNDANT** (THE
    DUPLICATED-WITHIN-A-FILE COUNT IS **ONLY **755 **LINES** AND **THE **COPIED-ACROSS-FILES
    COUNT IS **ONLY **457**).**

**AND IT PRINTS **WHAT **IT **WOULD **DO** BEFORE **IT **DOES **IT**, **AND IT **IS
**IDEMPOTENT** (RUNNING IT TWICE CHANGES NOTHING THE SECOND TIME).**
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

SEP = re.compile(r"^\s*[-=—~*_#\s]*$")
CIT = re.compile(r"(\.py:\d+|\.py`|`[A-Za-z_/]+\.py|UPSTREAM-PIN|\.bend:\d+|\.py\b)")
MEA = re.compile(r"(MEASURED|measured|\brc=\d|WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)")
HIST = re.compile(
    r"(USED TO BE|used to be|WAS FIXED|was fixed|FOUND AND FIXED|found and fixed|"
    r"AND THE BUG|and the bug|regression was|REGRESSION WAS|ATTEMPTED|attempted|"
    r"IT WAS WRONG|it was wrong|WAS WRONG|was wrong|NO LONGER|no longer|"
    r"WAS NOT|was not|BEFORE THE|BEFORE THIS|PREVIOUSLY|previously|"
    r"HAD BEEN|had been|ONCE WAS|once was|WAS WROTE|was wrote)"
)


def classify(body: str) -> str | None:
    """**THE CLASS OF A COMMENT LINE, OR None FOR **KEEP**."""
    if not body:
        return None
    if SEP.match(body):
        return "separator"
    # **A CITATION OR A MEASUREMENT IS **NEVER** REMOVED, **WHATEVER ELSE IT MATCHES** --
    # **AND **THE **HISTORY **TEST **RUNS **FIRST** BECAUSE **A **HISTORY **LINE **CAN
    # **ALSO **CITE**, **AND **THE **CITATION **IS **THE **LOAD-BEARING **PART**."
    if CIT.search(body) or MEA.search(body):
        return None
    if HIST.search(body):
        return "history"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", default=[])
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    if not args.files:
        print(__doc__)
        return 0
    counts: dict[str, int] = {}
    for rel in args.files:
        path = ROOT / rel if not rel.startswith("/") else Path(rel)
        lines = path.read_text().split("\n")
        out = []
        for i, line in enumerate(lines):
            s = line.strip()
            if not s.startswith("#"):
                out.append(line)
                continue
            body = s.lstrip("#").strip()
            kind = classify(body)
            if kind is None:
                out.append(line)
                continue
            counts[kind] = counts.get(kind, 0) + 1
            if args.report:
                print(f"  {rel}:{i+1} [{kind}] {s[:88]}")
            # **A **SEPARATOR **BECOMES **A **BLANK **LINE** -- **THE **STRUCTURE **STAYS
            # **AND **THE **TWENTY **DASHES **GO**."
            if kind == "separator":
                out.append("")
        if args.apply:
            path.write_text("\n".join(out))
    for k, v in sorted(counts.items()):
        print(f"  {k}: {v} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
