#!/usr/bin/env python3
"""THE ROW-LEVEL MOVEMENT, BEFORE -> AFTER, PAIRED BY INDEX.

    .venv/bin/python .agents/slop/pinwindow/diffrows.py

Both rows files were written by `gates/pin-cite-gate.py --rows` against THE SAME FROZEN
COPY of the port tree, so the pairing is exact: the census emits its rows in a fixed
order for a fixed tree, and the tree did not move between the two readings.

Every row whose CLASS changed is printed with its identity, its class before and after,
the claim tokens before and after, and the line the row was read from -- so a reader can
judge each move instead of counting it.
"""

from __future__ import annotations

import collections
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
COLS = ("rel", "at", "subject", "lo", "hi", "explicit", "at_pin", "newest_rev", "claim",
        "present_in_file", "class", "line", "absence", "absence_removed_at")


def read(path: Path) -> list[dict]:
  rows = []
  lines = path.read_text().splitlines()
  head = lines[0].split("\t")
  assert head == list(COLS), head
  for line in lines[1:]:
    if not line:
      continue
    rows.append(dict(zip(COLS, line.split("\t"))))
  return rows


def main() -> int:
  before = read(HERE / "before.rows")
  after = read(HERE / "after.rows")
  if len(before) != len(after):
    print(f"the two readings have different row counts: {len(before)} and {len(after)}")
    return 1
  changed = []
  for b, a in zip(before, after):
    if (b["rel"], b["at"], b["subject"], b["lo"]) != (a["rel"], a["at"], a["subject"], a["lo"]):
      print("the two readings are not row-aligned; the tree moved")
      return 1
    if b["class"] != a["class"]:
      changed.append((b, a))
  print(f"# {len(before)} rows, {len(changed)} changed class")
  tally = collections.Counter((b["class"], a["class"]) for b, a in changed)
  print("# class movement")
  for (x, y), n in sorted(tally.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"#   {x:28s} -> {y:28s} {n}")
  print()
  for b, a in changed:
    print(f"{b['rel']}:{b['at']}  {b['subject']}:{b['lo']}")
    print(f"    class : {b['class']} -> {a['class']}")
    print(f"    tokens: {b['claim']}  ->  {a['claim']}")
    print(f"    in_file:{b['present_in_file']}  ->  {a['present_in_file']}")
    print(f"    at_pin : {b['at_pin']} -> {a['at_pin']}    newest: "
          f"{(b['newest_rev'] or 'NONE')[:12]} -> {(a['newest_rev'] or 'NONE')[:12]}")
    print(f"    line  : {b['line'][:170]}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
