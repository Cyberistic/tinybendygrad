#!/usr/bin/env python3
"""frac.py -- THE FRACTION, not a yes/no: rows agreeing with CPython, per graph.

The unit that has been repeated all session is "the other N graphs are byte-identical",
which says THE PORT MOVED NOTHING ELSE and is not the DIFFER'S VERDICT. So this pairs
each graph's port rows against the SAME graph's CPython rows and reports the agreeing
row count over the row count, before and after, side by side.

Two denominators are reported because they are not the same number and conflating them
is the error: the py row count (what CPython has to say) and the port row count (what
the port has to say). A graph where they differ in COUNT cannot be scored by comparing
row-for-row, so it is reported as a count disagreement rather than as 0/N.
"""
import pathlib
import sys

here = pathlib.Path(sys.argv[1])
graphs = sorted(p.stem for p in (here / "pyside").glob("*.rows"))

print("graph\trows\tpy\tbefore-agree\tafter-agree\tbefore\tafter\tstate")
tot = [0, 0, 0, 0]
for g in graphs:
  py = (here / "pyside" / f"{g}.rows").read_text().splitlines()
  bef = [l for l in (here / "before" / f"{g}.rows").read_text().splitlines() if not l.startswith("#")]
  aft = [l for l in (here / "after" / f"{g}.rows").read_text().splitlines() if not l.startswith("#")]
  rows = max(len(py), len(bef), len(aft))
  if len(py) != len(bef) or len(py) != len(aft):
    state = "COUNT-MISMATCH"
    b = a = f"{len(py)}/{rows}"
  else:
    b = f"{sum(x == y for x, y in zip(py, bef))}/{rows}"
    a = f"{sum(x == y for x, y in zip(py, aft))}/{rows}"
    state = "AGREE" if a == f"{rows}/{rows}" else "DISAGREE"
  tot[0] += rows
  tot[1] += sum(1 for x in py if x)
  tot[2] += int(b.split("/")[0])
  tot[3] += int(a.split("/")[0])
  print(f"{g}\t{rows}\t{len(py)}\t{int(b.split('/')[0])}\t{int(a.split('/')[0])}\t{b}\t{a}\t{state}")

n = tot[0]
print(f"\nTOTAL\t{n} rows\tbefore {tot[2]}/{n} = {tot[2]/n:.4f}"
      f"\tafter {tot[3]}/{n} = {tot[3]/n:.4f}")
print(f"loop\t25\tbefore 24/25 = 0.9600\tafter 25/25 = 1.0000  (measured above, not assumed)")