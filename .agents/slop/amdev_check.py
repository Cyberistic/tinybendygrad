#!/usr/bin/env python3
"""amdev_check.py -- diff amdev.bend's gate against CPython.

The Bend file prints `name=value` rows; `.agents/slop/amdev_py.txt` is what
CPython prints for the SAME claims. Only rows whose key appears in BOTH are
compared, and the counts of each are printed so a row that silently vanished
cannot pass by being absent from both sides.

    .venv/bin/python .agents/slop/amdev_check.py
"""
import sys

PY = '.agents/slop/amdev_py.txt'
BEND = '.agents/slop/amdev_interp.txt'

def load(p):
  d = {}
  for line in open(p):
    line = line.rstrip('\n')
    if '=' not in line: continue
    k, v = line.split('=', 1)
    if k in d: print(f"DUPLICATE KEY {k} in {p}")
    d[k] = v
  return d

def merge(*paths):
  d = {}
  for p in paths:
    for k, v in load(p).items():
      if k in d and d[k] != v: print(f"ORACLES DISAGREE on {k}: {d[k]} vs {v}")
      d[k] = v
  return d

py, bd = merge(PY, '.agents/slop/amdev_gate.txt'), load(BEND)
both = [k for k in bd if k in py]
bad = [(k, bd[k], py[k]) for k in both if bd[k] != py[k]]
print(f"bend rows: {len(bd)}   cpython rows: {len(py)}   compared: {len(both)}")
print(f"bend-only (no oracle row yet): {len([k for k in bd if k not in py])}")
for k in bd:
  if k not in py: print(f"  bend-only: {k}={bd[k]}")
if bad:
  print(f"\nMISMATCHES: {len(bad)}")
  for k, b, p in bad: print(f"  {k}: bend={b}  cpython={p}")
else:
  print(f"\nALL {len(both)} COMPARED ROWS AGREE WITH CPYTHON")
sys.exit(1 if bad else 0)