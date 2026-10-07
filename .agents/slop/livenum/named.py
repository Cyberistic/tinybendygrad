#!/usr/bin/env python3
"""For every count the tree already knows how to re-derive, find EVERY occurrence
in the three surfaces and classify that occurrence DATED or LIVE.

The rules are `.agents/slop/citeresolve/counts.py`'s (an existing instrument that
computes each value); this file joins its output to the prose that asserts it, by
VALUE.  An occurrence is DATED when its own line carries a calendar date, a clock
reading, or a past-tense cue; otherwise LIVE.

Populations:
  NAMED  = the (value, rule) pairs counts.py computes -> occurrences in the surfaces
  ALL    = every measure claim in `.agents/slop/livenum/nums.tsv` (the broad scan)
"""
from __future__ import annotations

import csv
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SURFACES = ("AGENTS.md", ".agents/TOOLS.md", ".agents/TODO.md")

DATE = re.compile(r"20\d\d-\d\d-\d\d")
CLOCK = re.compile(r"\b\d{1,2}:\d\d\b")
PAST = re.compile(
    r"\b(used to|before|earlier|previously|historical|no longer|had been|prior|"
    r"was \d|were \d|deleted|retired|pruned|superseded|renamed|old(?:ly)?|"
    r"read(?:s)? \d|at the parent|existed|frozen|stale|replaced)\b", re.I)


def kind(line: str) -> str:
    return "DATED" if (DATE.search(line) or CLOCK.search(line) or PAST.search(line)) else "LIVE"


def main() -> int:
    counts = subprocess.run(
        [os.path.join(ROOT, ".venv/bin/python"), ".agents/slop/citeresolve/counts.py"],
        cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
    rules = []
    for ln in counts[1:]:
        f = ln.split("\t")
        if len(f) == 3:
            rules.append((f[0], f[1], f[2]))

    print("claim\trule\tcurrent\tsurface\tline\tkind\tsource_line")
    n_live = n_dated = 0
    for claim, rule, cur in rules:
        val = re.match(r"(\d+)", cur)
        if not val:
            continue
        v = val.group(1)
        pat = re.compile(r"(?<![\w.])" + re.escape(v) + r"(?![\w.])")
        for rel in SURFACES:
            with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if not pat.search(line):
                        continue
                    k = kind(line)
                    if k == "LIVE":
                        n_live += 1
                    else:
                        n_dated += 1
                    print(f"{claim}\t{rule}\t{cur}\t{rel}\t{i}\t{k}\t{line.strip()[:170]}")
    print(f"# named-count occurrences: LIVE={n_live} DATED={n_dated}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
