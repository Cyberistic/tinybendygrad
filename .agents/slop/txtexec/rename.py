#!/usr/bin/env python3
"""Execute the rename plan for the 259 `oracles/**/*.txt`, one class at a time.

Target extension is derived from the PLAN's `cls` column (the class->ext map the brief
names), NOT from the plan's `new_path` column, which is mechanically `path[:-4]+'.rows'`
for all 259 and disagrees with its own `cls` on 19 rows.

Deviations, each measured before execution:
  * 1 collision: oracles/fold-mut.py already exists and DIFFERS from fold-mut.txt.
    fold-mut.txt is the RUN REPORT of fold-mut.py (bytes start 'baseline: 27 rows'),
    not source -- its `probe` is `rows`, its plan new_path is `.rows`. -> .rows
  * ops-mutations.txt is likewise a mutation report (probe rows, planner said .rows). -> .rows
  * oracles/usb-arith-rows.bend.txt IS bend source (def t_wire...) and its .bend target is
    free -> .bend
  * oracles/rows-bd.txt is 0 bytes, UNCLASSIFIED -> LEFT as .txt
"""
import csv
import os
import subprocess
import sys
from collections import Counter

ROOT = os.getcwd()
PLAN = ".agents/slop/txt259/PLAN.tsv"

CLS_EXT = {
    "rowdump": ".rows",
    "crash-dump-in-txt": ".err",
    "rowdump?/md": ".md",
    "rowdump?/tsv": ".tsv",
    "source-in-txt": ".rows",   # see deviation: both are reports, not source
    "rowdump?/empty": None,     # leave
}
OVERRIDE = {
    "oracles/usb-arith-rows.bend.txt": "oracles/usb-arith-rows.bend",
}


def target(rel, cls):
    if rel in OVERRIDE:
        return OVERRIDE[rel]
    ext = CLS_EXT[cls]
    if ext is None:
        return None
    return rel[:-4] + ext


def run(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)


def main() -> int:
    rows = list(csv.DictReader(open(PLAN), delimiter="\t"))
    moved = Counter()
    skipped = []
    failures = []
    for r in sorted(rows, key=lambda r: r["cls"]):
        old, cls = r["path"], r["cls"]
        new = target(old, cls)
        if new is None:
            skipped.append((old, "UNCLASSIFIED/empty -- left as .txt"))
            continue
        if not os.path.exists(old):
            failures.append((old, "source absent"))
            continue
        if os.path.exists(new) and new != old:
            failures.append((old, f"target exists: {new}"))
            continue
        p = run(["git", "mv", old, new])
        if p.returncode != 0:
            failures.append((old, p.stderr.strip()))
        else:
            moved[cls] += 1

    print("RENAMED per class:")
    for cls, n in sorted(moved.items()):
        print(f"  {cls:20s} {n}")
    print(f"  TOTAL renamed: {sum(moved.values())}")
    print()
    print("SKIPPED:")
    for old, why in skipped:
        print(f"  {old}  ({why})")
    print()
    print("FAILURES:")
    for old, why in failures:
        print(f"  {old}  ({why})")
    print()

    # residual .txt under oracles/
    residual = []
    for dp, _, fns in os.walk("oracles"):
        for f in fns:
            if f.endswith(".txt"):
                residual.append(os.path.join(dp, f))
    residual.sort()
    print(f"RESIDUAL .txt under oracles/: {len(residual)}")
    for p in residual:
        print(f"  {p}  ({os.path.getsize(p)} B)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
