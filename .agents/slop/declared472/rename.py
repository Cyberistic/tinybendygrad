#!/usr/bin/env python3
"""The only live mutation: `os.rename` (never `git mv`) each rename candidate from PLAN.tsv.

SKIP set (NOT renamed), stated and reproducible:
  * any file whose PLAN.tsv `note` begins `SKIP` -- a committed code file names it by a
    distinctive >=2-component path suffix, OR a committed copytree-then-read driver reads it.
Nothing is deleted. `--dry` prints without moving.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
PLAN = os.path.join(ROOT, ".agents/slop/declared472/PLAN.tsv")


def main():
    dry = "--dry" in sys.argv
    rows = open(PLAN).read().splitlines()[1:]
    moved, kept = [], []
    for line in rows:
        path, cls, rule, ref, new, note = line.split("\t")
        if note:
            kept.append((path, note))
            continue
        src, dst = os.path.join(ROOT, path), os.path.join(ROOT, new)
        assert not os.path.exists(dst), f"target exists: {new}"
        if not dry:
            os.rename(src, dst)
        moved.append((path, new, cls))
    print(f"{'WOULD MOVE' if dry else 'MOVED'} {len(moved)}  KEPT {len(kept)}")
    if dry:
        for p, n, c in moved[:10]:
            print(f"  {p} -> {n}  [{c}]")
        for p, note in kept:
            print(f"  KEEP {p}  <- {note.split(';')[0]}")


main()
