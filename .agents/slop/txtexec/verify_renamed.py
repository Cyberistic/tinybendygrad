#!/usr/bin/env python3
"""Verify the rename against git's tree, not against the rename script's own report.

For every row of PLAN.tsv: the OLD name must exist at the pre-rename commit
b504abf77 and the NEW name must exist at the post-rename commit 4d0a2b258.
Class tally is reported, plus any row whose new name is absent from HEAD.
"""
import csv
import os
import subprocess
from collections import Counter

PRE = "b504abf77"
POST = "4d0a2b258"
OVERRIDE = {"oracles/usb-arith-rows.bend.txt": "oracles/usb-arith-rows.bend"}
CLS_EXT = {
    "rowdump": ".rows", "crash-dump-in-txt": ".err", "rowdump?/md": ".md",
    "rowdump?/tsv": ".tsv", "source-in-txt": ".rows", "rowdump?/empty": None,
}


def target(rel, cls):
    if rel in OVERRIDE:
        return OVERRIDE[rel]
    ext = CLS_EXT[cls]
    return None if ext is None else rel[:-4] + ext


def tree(ref):
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref, "--", "oracles"],
                         capture_output=True, text=True).stdout
    return set(out.split("\n"))


pre, post = tree(PRE), tree(POST)
plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))

renamed = Counter()
bad = []
skipped = []
for r in plan:
    old, cls = r["path"], r["cls"]
    new = target(old, cls)
    if new is None:
        skipped.append(old)
        continue
    if old not in pre:
        bad.append((old, "old absent at PRE"))
    elif new not in post:
        bad.append((new, "new absent at POST"))
    else:
        renamed[cls] += 1

print(f"PRE {PRE}: {len(pre)} paths under oracles")
print(f"POST {POST}: {len(post)} paths under oracles")
print(f"plan rows: {len(plan)}")
print()
print("RENAMED per class, verified against git tree:")
for cls, n in sorted(renamed.items()):
    print(f"  {cls:20s} {n}")
print(f"  TOTAL: {sum(renamed.values())}")
print()
print(f"skipped (left .txt): {skipped}")
print(f"bad: {bad}")
