#!/usr/bin/env python3
"""Recon: sweep.py's populations by discovery, and what a tinybendygrad/ arm would see.

Run: .venv/bin/python .agents/slop/sweepport/pop.py
Prints to stdout only; redirect to .out/.rows yourself.
"""
from __future__ import annotations

import collections
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("sweep", os.path.join(ROOT, "checks", "sweep.py"))
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)


def walk_all(base: str) -> list[str]:
    out = []
    for dirpath, _d, files in os.walk(os.path.join(ROOT, base)):
        for f in files:
            out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return out


def main() -> int:
    print("== POPULATIONS: where sweep.py walks, globs, or lists ==")
    print(f"RESIDUE_ROOTS (sweep.py:72)          = {sweep.RESIDUE_ROOTS}")
    print(f"NAMED_BY      (sweep.py:108-110)     = {sweep.NAMED_BY}")
    print(f"self_output_dirs (from AST)          = {sweep.self_output_dirs(ROOT)}")

    residue = sweep.walk_residue(ROOT)
    slop = [r for r, _ in residue if r.startswith(".agents" + os.sep)]
    runs = [r for r, _ in residue if r.startswith("runs" + os.sep)]
    print(f"\nwalk_residue (:556-572) os.walk over RESIDUE_ROOTS: {len(residue)} files "
          f"({len(slop)} under .agents/slop, {len(runs)} under runs)")

    print("\n== WHAT THE WALK MISSES ==")
    miss = walk_all("tinybendygrad")
    print(f"tinybendygrad/ (never in RESIDUE_ROOTS): {len(miss)} files")
    for top in ("tinygrad", "test", "docs", "examples", "checks", "gates", "oracles"):
        print(f"  {top}/: {len(walk_all(top))} files")

    print("\n== WHAT A tinybendygrad/ ARM WOULD SEE (current verdict_for rules) ==")
    f = sweep.facts(ROOT)
    verdicts = collections.Counter()
    needs = collections.Counter()
    for rel in miss:
        v = sweep.verdict_for(rel, f.mentioned, f, sweep.live_units(60, f.root))
        verdicts[sweep.bucket(v)] += 1
        if v.startswith(sweep.UNKNOWN):
            needs[v.partition(":")[2].split(" (")[0]] += 1
    for k, n in verdicts.most_common():
        print(f"  {k:14s} {n:6d}")
    print("  needs= breakdown:")
    for k, n in needs.most_common():
        print(f"    {k:40s} {n:6d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
