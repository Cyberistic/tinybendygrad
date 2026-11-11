#!/usr/bin/env python3
"""blank.py -- collapse runs of blank lines to one.

    .venv/bin/python .agents/slop/loc/blank.py <path>...
    .venv/bin/python .agents/slop/loc/blank.py --report <path>...

One blank line separates things; the second one separates nothing and costs a
line, and this tree carries 3,831 of them in `tinybendygrad/` alone (measured
2026-11-11 over `git ls-tree -r HEAD -- tinybendygrad`).

What it will not touch: a run at the top of the file (a file's leading blank
line is nobody's separator) and the trailing newline, which stays exactly one.
Every edit is the deletion of a line that is blank, so a caller can prove the
change by checking that every removed line is empty.
"""

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def collapse(lines: list[str]) -> list[str]:
    out: list[str] = []
    for line in lines:
        if line.strip() == "" and out and out[-1].strip() == "":
            continue
        out.append(line)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", default=[])
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if not args.files:
        print(__doc__)
        return 0

    total = 0
    for rel in args.files:
        path = Path(rel) if Path(rel).is_absolute() else ROOT / rel
        text = path.read_text()
        lines = text.split("\n")
        out = collapse(lines)
        removed = len(lines) - len(out)
        total += removed
        if args.report:
            print(f"  {removed:4d}  {rel}")
        else:
            path.write_text("\n".join(out))
    print(f"  {total} blank lines removed", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
