#!/usr/bin/env python3
"""THE 16 ROWS THAT TELL THE TWO NEAREST-VARIANTS APART.

    .venv/bin/python .agents/slop/pinwindow/diff_rules.py

`NEAREST` (the reference implementation's rule, with no distance cutoff) and
`NEAREST+CUTOFF-1` (the same, and a name farther than `_NEAREST` from EVERY citation on
a line that carries SEVERAL citations belongs to NONE of them) differ on the rows this
prints.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import probe  # noqa: E402


def main() -> int:
  a_up, _ = probe.run(probe.rule_nearest)
  b_up, _ = probe.run(probe.rule_nearest_cutoff1)
  print(f"# NEAREST vs NEAREST+CUTOFF-1: {len(a_up)} rows")
  n = 0
  for a, b in zip(a_up, b_up):
    if a["toks"] == b["toks"] and probe.pc.row_class(a) == probe.pc.row_class(b):
      continue
    n += 1
    print(f"{a['rel']}:{a['at']}  {a['subject']}:{a['lo']}")
    print(f"    NEAREST      : {probe.pc.row_class(a):26s} toks={a['toks']}")
    print(f"    NEAREST+CUT1 : {probe.pc.row_class(b):26s} toks={b['toks']}")
    print(f"    line: {a['line'][:160]}")
  print(f"# {n} rows differ")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
