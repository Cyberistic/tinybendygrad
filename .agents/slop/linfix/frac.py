#!/usr/bin/env python3
"""frac.py -- the agreeing-rows fraction, BEFORE vs AFTER, per graph.

Pairs each graph's port rows against the SAME graph's CPython rows. A graph whose
two sides differ in COUNT cannot be scored row-for-row, so it is counted as its
py count over the max (arghalf/frac.py's rule), not as 0/N.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
graphs = sorted(p.stem for p in (root / "before-out" / "py").glob("*.rows"))
print("graph\trows\tpy\tbefore-agree\tafter-agree\tbefore\tafter\tstate")
tot = [0, 0, 0]
for g in graphs:
    py = [l for l in (root / "before-out" / "py" / f"{g}.rows").read_text().splitlines() if l.strip()]
    bef = [l for l in (root / "before-out" / f"{g}.rows").read_text().splitlines() if not l.startswith("#")]
    aft = [l for l in (root / "after-out" / f"{g}.rows").read_text().splitlines() if not l.startswith("#")]
    rows = max(len(py), len(bef), len(aft))
    if len(py) != len(bef) or len(py) != len(aft):
        b = a = f"{len(py)}/{rows}"
        state = "COUNT-MISMATCH"
    else:
        b = f"{sum(x == y for x, y in zip(py, bef))}/{rows}"
        a = f"{sum(x == y for x, y in zip(py, aft))}/{rows}"
        state = "AGREE" if a == f"{rows}/{rows}" else "DISAGREE"
    tot[0] += rows
    tot[1] += int(b.split("/")[0])
    tot[2] += int(a.split("/")[0])
    print(f"{g}\t{rows}\t{len(py)}\t{b}\t{a}\t{state}")
n = tot[0]
print(f"\nTOTAL\t{n} rows\tbefore {tot[1]}/{n} = {tot[1]/n:.4f}\tafter {tot[2]}/{n} = {tot[2]/n:.4f}")
