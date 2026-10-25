#!/usr/bin/env python3
"""EVERY ROW THAT CHANGES CLASS, OLD -> NEW, ON THE FROZEN TREE.

    .venv/bin/python .agents/slop/pinwindow/dump.py NEAREST

The rule is named on the command line; `probe.py` holds the four candidates. For every
row whose CLASS changes, this prints the row's identity, its class before and after, the
claim tokens before and after, and the line the row was read from -- so a reader can
judge each move instead of counting it.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import probe  # noqa: E402  -- the four rules, and the shared corpus


def main() -> int:
  which = sys.argv[1] if len(sys.argv) > 1 else "NEAREST"
  fn = probe.RULES[which]
  base_up, _ = probe.run(probe.rule_old)
  up, _ = probe.run(fn)
  print(f"# OLD -> {which}: {len(up)} rows")
  moved = 0
  for b, a in zip(base_up, up):
    if probe.pc.row_class(b) == probe.pc.row_class(a):
      continue
    moved += 1
    print(f"{b['rel']}:{b['at']}  {b['subject']}:{b['lo']}"
          f"  {probe.pc.row_class(b)} -> {probe.pc.row_class(a)}")
    print(f"    toks: {b['toks']}  ->  {a['toks']}")
    print(f"    present_in_file: {b['present']}  ->  {a['present']}")
    print(f"    at_pin: {b['at_pin']} -> {a['at_pin']}   newest: "
          f"{(b['newest_rev'] or 'NONE')[:12]} -> {(a['newest_rev'] or 'NONE')[:12]}")
    print(f"    line: {b['line'][:150]}")
  print(f"# {moved} rows changed class")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
