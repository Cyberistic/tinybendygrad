#!/usr/bin/env python3
"""Emit counts.tsv: the three buckets the brief asks for, over the 473.

Rules, stated:
  named-by-reader   target basename appears LITERALLY in a committed code file (CODE_EXT);
                    file:line of the first such hit.  (readers.json `full`+`weak`)
  declared-only     target basename appears in NO committed code file; it is constructed by
                    `checks/differ.py`'s f-strings and owned only by `declared()`.
  named-by-nothing  basename not in declared() either -- measured 0, because plan.py:89 selected
                    the 473 precisely by `basename in declared()`.
Also reports, per mirror tree, whether a committed file OPENS that tree by path (the strict
"reader" sense). Only plant.py:54 opens D-live.
"""
import json
import os
import subprocess
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
D = os.path.join(ROOT, ".agents/slop/declared473")


def main():
    der = json.load(open(os.path.join(D, "derived.json")))
    rd = json.load(open(os.path.join(D, "readers.json")))
    refused = der["refused"]
    declared = set(der["declared"])
    named = dict(rd["full"])
    named.update(rd["weak"])

    rows = []
    for t in refused:
        first = (named.get(t) or [""])[0]
        bucket = "named-by-reader" if first else (
            "named-by-nothing" if os.path.basename(t) not in declared else "declared-only")
        rows.append((t, bucket, first))
    with open(os.path.join(D, "counts.tsv"), "w") as fh:
        fh.write("path\tbucket\treader\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")

    c = Counter(r[1] for r in rows)
    for k in ("named-by-reader", "declared-only", "named-by-nothing"):
        print(f"{k:18s} = {c.get(k, 0)}")
    print("\nreaders of the 140 named-by-reader files (distinct file:line -> count):")
    rc = Counter(r[2].rsplit(":", 1)[0] for r in rows if r[2])
    for f, n in rc.most_common():
        print(f"  {n:4d}  {f}")

    # strict sense: which mirror TREE is opened by name?
    print("\nstrict: committed code that OPENS a mirror tree by path:")
    for f in subprocess.run(["git", "-C", ROOT, "grep", "-n", "D-live", "--", "*.py"],
                            capture_output=True, text=True).stdout.splitlines():
        print("  " + f)


main()
