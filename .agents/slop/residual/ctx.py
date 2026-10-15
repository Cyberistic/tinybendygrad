#!/usr/bin/env python3
"""Print the claiming source line for every row of a fails file.

usage: .venv/bin/python .agents/slop/residual/ctx.py <fails.rows> [col0-filter]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
rows = Path(sys.argv[1])
want = sys.argv[2] if len(sys.argv) > 2 else ""
for i, line in enumerate(rows.read_text().splitlines(), 1):
  f = line.split("\t")
  if len(f) < 6:
    continue
  lane, anchor, subject, needle, evid = f[0], f[1], f[2], f[3], f[4]
  if want and lane != want:
    continue
  path, _, ln = anchor.rpartition(":")
  try:
    src = (ROOT / path).read_text(errors="replace").splitlines()[int(ln) - 1]
  except (OSError, IndexError, ValueError):
    src = "<no such line>"
  print(f"{i}\t{lane}\t{anchor}\t{subject}\t{needle[:70]}\t{src.strip()[:150]}")
