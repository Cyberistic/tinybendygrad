#!/usr/bin/env python3
"""Depth fold over ONE captured lane text: count LOGICAL rows and how many carry rn-gate.py's
exact SEP.  Read-only over the file it is handed; prints one line per lane."""
import pathlib, sys

SEP = "]   py=["
D = {"[": 1, "]": -1}

for arg in sys.argv[1:]:
  depth, rows, sep_rows, wrapped = 0, 0, 0, False
  lines = pathlib.Path(arg).read_text().splitlines()
  for line in lines:
    if not line.strip():
      continue
    is_row = depth == 0 and not wrapped
    if is_row:
      rows += 1
      if SEP in line:
        sep_rows += 1
    wrapped = depth == 0 and line.lstrip().startswith("py=")
    for c in line:
      depth += D.get(c, 0)
  print(f"{arg}\tphysical={len(lines)}\tlogical={rows}\twith_EXACT_SEP={sep_rows}")