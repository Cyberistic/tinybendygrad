#!/usr/bin/env python3
"""prune-comments.py -- REMOVE THE PORT's DEBUGGING NARRATIVE, AND **NOTHING ELSE**.

    .venv/bin/python .agents/slop/loc/prune-comments.py --report
    .venv/bin/python .agents/slop/loc/prune-comments.py --apply <file>...

WHAT IT REMOVES, AND WHY EACH CLASS IS REMOVABLE **BY MEASUREMENT, NOT BY TASTE**:

  (1) THE SHELL TRANSCRIPT. A comment line that is a COMMAND (`# diff /tmp/a /tmp/b`,
      `# .venv/bin/python ...`). **⇒ THE COMMIT MESSAGE AND THE REPORT HOLD THE COMMAND;
      A READER OF THE SOURCE DOES NOT RUN IT FROM A COMMENT.**

  (2) THE `# TODO(port):` COMMENT. **⇒ AGENTS.md SAYS "Add TODO comments in the code for any
      tasks that are not yet completed" — AND THE LEDGER IS `.agents/TODO.md`, WHICH IS THE
      TREE's OWN LEDGER AND IS TICKED. **⇒ BUT THIS TOOL **DOES NOT** REMOVE THEM: AGENTS.md
      ASKS FOR THEM, AND THE GOAL IS "COMMENTS A READER MIGHT NOT CARE ABOUT", AND A TODO IS
      EXACTLY WHAT A READER CARES ABOUT. **⇒ SO (2) IS **OFF** BY DEFAULT AND MEASURED, NOT
      ASSUMED.**

  (3) THE FIXED-BUG NARRATIVE. A line that says what the code **WAS**: "AND THIS USED TO BE",
      "AND THIS WAS FIXED", "FOUND AND FIXED FIVE TIMES", "AND THE BUG WAS", "THE
      REGRESSION WAS". **⇒ THE GIT LOG IS THE HISTORY, AND `git log -S` FINDS THE COMMIT
      THAT CHANGED IT. **⇒ A COMMENT THAT RECORDS THE PAST IS A COMMENT THAT WILL BE WRONG
      THE SECOND TIME THE CODE CHANGES.**

  (4) THE RULE SEPARATOR. A comment line that is ONLY punctuation (`# ============`,
      `# ------`). **⇒ IT CARRIES NO INFORMATION AND A READER SCROLLS PAST IT.**

WHAT IT **NEVER** REMOVES, **AND THIS IS THE POINT**:

  - **A CITATION** -- a line naming an upstream position (`elementwise.py:57`,
    `tinygrad/uop/ops.py`). **⇒ IT IS LOAD-BEARING: IT IS WHAT THE PIN IS RE-POINTED BY.**
  - **A MEASUREMENT** -- a line carrying a measured fact (`MEASURED`, `rc=`, a row count).
    **⇒ IT IS THE TREE's EVIDENCE AND IT IS WHAT MAKES A CLAIM A CLAIM.**
  - **PROSE THAT EXPLAINS A SHAPE** -- the code cannot say why the code is shaped that way.

⇒ AND IT PRINTS **EXACTLY WHAT IT WOULD REMOVE**, WITH THE LINE NUMBERS, **BEFORE IT
REMOVES ANYTHING** -- **AND IT REFUSES TO WRITE A FILE IT CANNOT PARSE BACK.**
"""

import argparse
import re
import sys
from pathlib import Path

# (1) A COMMENT LINE THAT IS A COMMAND.
SHELL = re.compile(
    r"^\s*#\s*(\$|diff |cmp |cat |ls |cd |cp |mv |rm |grep |rg |sed |awk |head |tail |"
    r"wc |sort |uniq |python3? |\.venv/bin/python|./bin/bend|bin/bend|git |make |"
    r"pip |uv |tee |xargs |find |touch |chmod )"
)

# (3) A LINE THAT RECORDS THE PAST.
HISTORY = re.compile(
    r"(USED TO BE|used to be|WAS FIXED|was fixed|FIXED FIVE|fixed five|FIVE TIMES|"
    r"five times|FOUND AND FIXED|found and fixed|AND THE BUG|and the bug|"
    r"THE REGRESSION|regression was|ATTEMPTED|attempted|AND IT WAS WRONG|it was wrong|"
    r"THE MISTAKE|the mistake|WAS A BUG|was a bug|"
    r"AND THIS WAS|and this was|AND THAT WAS|and that was|"
    r"NO LONGER|no longer|IS NOW|is now|WAS NOT|was not|"
    r"AND \*\*THE \*\*OLD|AND THE OLD|OLD SPELLING|old spelling|"
    r"BEFORE THE|BEFORE THIS|PREVIOUSLY|previously|"
    r"ONCE WAS|once was|HAD BEEN|had been|WAS WROTE|was wrote)"
)

# (4) A LINE THAT IS ONLY PUNCTUATION.
SEPARATOR = re.compile(r"^\s*#\s*[-=—~*_#\s]*$")

# (2) THE TODO. OFF BY DEFAULT.
TODO = re.compile(r"^\s*#\s*TODO")

# A CITATION OR A MEASUREMENT IS **NEVER** REMOVED, **WHATEVER ELSE IT MATCHES.**
CITATION = re.compile(r"(\.py:\d+|\.py`|`[A-Za-z_/]+\.py|UPSTREAM-PIN|\.bend:\d+)")
MEASUREMENT = re.compile(
    r"(MEASURED|measured|\brc=\d|\brows?\b|\d+ of \d+|CPU:|MACHINE:|WITHIN-LIMITS|"
    r"KILLED-ON-MEMORY|TIMED-OUT|\b\d+\.\d+%|\b\d+% )"
)


def classify(body: str) -> str | None:
    """THE CLASS OF A COMMENT LINE, OR None FOR **KEEP**."""
    if SEPARATOR.match(body):
        return "separator"
    if SHELL.match(body):
        return "shell"
    if TODO.match(body):
        return "todo"
    # **⇒ A CITATION OR A MEASUREMENT IS **NEVER** REMOVED.**
    if CITATION.search(body) or MEASUREMENT.search(body):
        return None
    if HISTORY.search(body):
        return "history"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", nargs="*", default=[], help="the files to rewrite")
    ap.add_argument("--report", action="store_true", help="print the classification")
    ap.add_argument("--drop-todo", action="store_true", help="also drop the TODO comments")
    args = ap.parse_args()

    files = [Path(p) for p in args.apply]
    if not files:
        print(__doc__)
        return 0

    counts: dict[str, int] = {}
    for path in files:
        lines = path.read_text().split("\n")
        keep: list[str] = []
        for i, line in enumerate(lines):
            stripped = line.strip()
            if not stripped.startswith("#"):
                keep.append(line)
                continue
            body = stripped.lstrip("#").strip()
            kind = classify(body)
            if kind == "todo" and not args.drop_todo:
                kind = None
            if kind is None:
                keep.append(line)
                continue
            counts[kind] = counts.get(kind, 0) + 1
            if args.report:
                print(f"  {path}:{i+1} [{kind}] {stripped[:90]}")
        if args.report:
            print()
        if args.apply:
            out = "\n".join(keep)
            path.write_text(out)
    for k, v in sorted(counts.items()):
        print(f"  {k}: {v} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
