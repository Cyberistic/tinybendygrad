#!/usr/bin/env python3
"""mk.py -- WRITE A PATCH TABLE FROM PYTHON TUPLES.

    .venv/bin/python mk.py OUT.tsv  <<'PY'
    ("tinybendygrad/runtime/ops_cl.bend", 164, ":106 stores in", "the new line"),
    PY

The tuple is `(rel, at, guard, new_line)`. The guard is a SUBSTRING the line must
contain, so a patch written against a stale tree is refused rather than landing on the
wrong line. `at` is 1-based.

The output is a TSV, because a patch table is a TABLE and a table is `.rows`.
"""

from __future__ import annotations

import csv
import sys


def main() -> int:
  out = sys.argv[1]
  rows = []
  for line in sys.stdin:
    line = line.strip()
    if not line or line.startswith("#"):
      continue
    if line.endswith(","):
      line = line[:-1]
    rows.append(eval(line))  # noqa: S307 -- the table is written by this unit, in this file
  with open(out, "w", encoding="utf-8", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["rel", "at", "old", "new"])
    for rel, at, guard, new in rows:
      w.writerow([rel, at, guard, new])
  print(f"WROTE {len(rows)} row(s) -> {out}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
