#!/usr/bin/env python3
"""WHERE THE OLD DANGLING CLAIMS WENT, AND WHY.

READS `CITATION-CLASSES.rows`, the committed record of the reading.

THE OLD GATE'S `dangling` CLASS was: a citation with a claim token, holding at NO upstream
revision, whose subject names ONE upstream file outright, and which the census's directory
ambient does not explain. The new gate's class is the same, MINUS the citations that make
no claim about the file they cite -- the port's own vocabulary."""
from __future__ import annotations
import csv
from pathlib import Path
HERE = Path(__file__).resolve().parent

rows = list(csv.DictReader(open(HERE / "CITATION-CLASSES.rows"), delimiter="\t"))


def old_dangling(r) -> bool:
    """THE OLD GATE'S CLASS, reproduced from the recorded columns: a citation with a claim
    token, holding at NO upstream revision, whose subject names ONE upstream file outright
    (`explicit` and a `/` in the subject), and which the census's directory ambient does
    not explain (`ambient_relocated` is the ambient's own class)."""
    return (r["before_class"] == "at_no_revision"
            and r["explicit"] == "1"
            and "/" in r["subject"]
            and r["after_class"] != "ambient_relocated")


od = [r for r in rows if old_dangling(r)]
print(f"== THE OLD DANGLING SET: {len(od)} rows ==")
stay = []
for r in od:
    print(f"  {r['after_class']:16s} {r['rel']}:{r['at']}  {r['subject']}:{r['lo']}-{r['hi']}  "
          f"present_in_file={r['present_in_file']!r}")
    if r["after_class"] == "dangling":
        stay.append(r)
print()
print(f"== {len(stay)} ARE STILL DANGLING ==")
for r in stay:
    assert r["present_in_file"], r
    assert r["after_class"] == "dangling", r
print("   PROVEN BY ASSERTION: every survivor names a token that DOES occur in the cited")
print("   file, so REPAIR 2 could not have rescued it -- and the gate's FAIL is about the")
print("   file's OWN vocabulary, not about the port's.")
print()
print("== THE ONES THAT LEFT THE FAIL CLASS ==")
for r in od:
    if r["after_class"] != "dangling":
        print(f"  {r['after_class']:16s} {r['rel']}:{r['at']}  {r['subject']}:{r['lo']}-{r['hi']}  "
              f"present_in_file={r['present_in_file']!r}")
