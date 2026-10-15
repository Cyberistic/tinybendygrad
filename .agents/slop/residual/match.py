#!/usr/bin/env python3
"""match.py -- reconcile the residual NEW FAILs against failaudit's 65 hand labels.

usage: .venv/bin/python .agents/slop/residual/match.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def norm(a: str) -> str:
  a = a.strip()
  return a[1:] if a.startswith(".") else a


labels = {}
for line in (ROOT / ".agents/slop/failaudit/handlabels.rows").read_text().splitlines():
  f = line.split("\t")
  labels[norm(f[2])] = f[1]

rows = (ROOT / ".agents/slop/residual/new-after.rows").read_text().splitlines()
kept, gone, unlab = [], [], []
for line in rows:
  f = line.split("\t")
  if len(f) < 6 or f[2] != "suffix-index":
    continue
  a = norm(f[3])
  lab = labels.get(a, "?")
  (kept if lab != "?" else unlab).append((a, f[3], lab, f[5]))
seen = {norm(k[0]) for k in kept} | {norm(u[0]) for u in unlab}
gone = [(k, v) for k, v in labels.items() if k not in seen]
print(f"NEW FAILs now = {len(kept) + len(unlab)}  labelled = {len(kept)}  unlabelled = {len(unlab)}")
print(f"of the 65 hand labels, GONE = {len(gone)}")
print("\n-- categories of the surviving labelled NEW FAILs --")
from collections import Counter
print(Counter(k[2] for k in kept))
print("\n-- GONE labels (anchor, label) --")
for k, v in gone:
  print(f"  {v:13s} {k}")
print("\n-- UNLABELLED survivors (anchor, needle) --")
for u in unlab:
  print(f"  {u[1]:45s} {u[3]!r}")
