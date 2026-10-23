#!/usr/bin/env python3
"""THE ROW-LEVEL MOVEMENT: every citation's class BEFORE and AFTER, on ONE frozen tree.

READS `CITATION-CLASSES.rows`, which is the committed record of the reading, so this
runs without the (deleted) raw per-gate rows files."""
from __future__ import annotations
import collections, csv
from pathlib import Path
HERE = Path(__file__).resolve().parent

moves: collections.Counter = collections.Counter()
detail: collections.defaultdict = collections.defaultdict(list)
rows = list(csv.DictReader(open(HERE / "CITATION-CLASSES.rows"), delimiter="\t"))
total = len(rows)
for r in rows:
    moves[(r["before_class"], r["after_class"])] += 1
    if r["before_class"] != r["after_class"]:
        detail[(r["before_class"], r["after_class"])].append(r)

print("== THE ROW-LEVEL MOVEMENT, ON ONE FROZEN TREE ==")
print(f"   {total} citations")
for (oc, nc), n in sorted(moves.items(), key=lambda t: (-t[1], t[0])):
    if n:
        print(f"  {oc:26s} -> {nc:26s}  {n:5d}")
print()
print("== EVERY ROW THAT MOVED ==")
for (oc, nc), rows in sorted(detail.items(), key=lambda t: t[0]):
    print(f"-- {oc} -> {nc}  ({len(rows)} rows)")
    for r in rows[:6]:
        print(f"     {r['rel']}:{r['at']} {r['subject']}:{r['lo']}-{r['hi']} "
              f"present_in_file={r['present_in_file']!r}")
    if len(rows) > 6:
        print(f"     ... ({len(rows)} rows)")
print()
HOLDING = ("at_pin", "only_older_revision")
leavers = [r for r in rows
           if r["before_class"] in HOLDING and r["after_class"] not in HOLDING]
print(f"== ROWS THAT LEFT THE HOLDING CLASSES: {len(leavers)} "
      f"(MUST BE 0 -- a holding claim implies the token is in the file, so it can never "
      f"become unverifiable) ==")
for r in leavers:
    print(f"     {r['rel']}:{r['at']} {r['subject']}:{r['lo']}-{r['hi']}")
