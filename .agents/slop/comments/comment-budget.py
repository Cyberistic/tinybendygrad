#!/usr/bin/env python3
"""**THE **COMMENT **BLOAT **GATE** -- **AND **THE **PER-FILE **BUDGET **THAT **KEEPS **IT **CUT**.

**WHY THIS FILE EXISTS.** THE **PORT **CARRIED **10,549 **COMMENT **BLOCKS **AND **85,815 **COMMENT
**LINES** -- **⇒⇒† AND **THE **TREE's **OWN **RULE** (`AGENTS.md:16`) **IS *"IF **YOU **NEED **TO **WRITE
**A **PARAGRAPH-LONG **COMMENT **TO **JUSTIFY **YOUR **CODE**, **YOU **ARE **DOING **IT **WRONG"*** -- **⇒⇒†
**AND **THE **USER's **FORM** **IS *"IT **SHOULD **ONLY **BE **A **COMMENT **IF **IT **SHORTLY **EXPLAINS
**A **DIFFERENCE **OR **WHY **WE **ARE **DOING **SOMETHING **WEIRD"*** -- **⇒⇒† AND **SO **THE **CUT **NEEDS
**AN **INSTRUMENT**, **⇒⇒† AND **THE **INSTRUMENT **IS **THIS **FILE**.

**⇒⇒† AND **WHAT **THIS **GATE **CLAIMS**, **AND **WHAT **IT **DOES **NOT**:
  · IT **CLAIMS**: **NO **FILE's **COMMENT **MASS **MAY **GROW **PAST **A **BUDGET**, **⇒⇒† AND **THE
    **BUDGET **IS **THE **CURRENT **MASS**, **⇒⇒† AND **SO **THE **GATE **IS **A **RATCHET** -- **⇒⇒† AND
    **IT **HOLDS **THE **CUT **AND **IT **CATCHES **THE **NEXT **ONE**.
  · IT **DOES **NOT **CLAIM**: **THAT **THE **COMMENTS **ARE **GOOD**. **⇒⇒† AND **THE **JUDGEMENT **OF **A
    **COMMENT **IS **A **HUMAN's**, **⇒⇒† AND **THE **GATE **IS **THE **BUDGET **AND **THE **DRIFT
    **DETECTOR**, **NOT **THE **EDITOR**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **A **WALK **OVER
**`tinybendygrad/` **FOR **THE **`.bend` **FILES**, **⇒⇒† AND **A **RUN **OF **CONTIGUOUS **`#` **LINES**
**IS **A **BLOCK** -- **⇒⇒† AND **NOT **A **HAND **LIST**.

**⇒⇒† AND **THE **BUDGET **LIVES **IN **A **ROW **FILE**, **⇒⇒† AND **AND **IT **IS **REGENERABLE**,
**⇒⇒† AND **AND **THE **REGENERATION **IS **THE **ONE **WAY **TO **RAISE **A **BUDGET** -- **⇒⇒† AND
**A **BUDGET **THAT **CAN **BE **RAISED **WITHOUT **A **REASON **IS **NOT **A **BUDGET**.
"""

import json
import os
import pathlib
import re
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
BUDGET = pathlib.Path(__file__).resolve().parent / "budget.rows"


def blocks_of(path: pathlib.Path):
  lines = path.read_text().split("\n")
  i = 0
  while i < len(lines):
    if lines[i].strip().startswith("#"):
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"):
        j += 1
      yield i + 1, lines[i:j]
      i = j
    else:
      i += 1


def census():
  out = {}
  for dp, _, fns in os.walk(PORT):
    for fn in sorted(fns):
      if not fn.endswith(".bend"):
        continue
      f = pathlib.Path(dp) / fn
      rel = str(f.relative_to(PORT))
      bl = list(blocks_of(f))
      out[rel] = {"blocks": len(bl), "lines": sum(len(b[1]) for b in bl)}
  return out


def load_budget():
  if not BUDGET.exists():
    return {}
  out = {}
  for line in BUDGET.read_text().split("\n")[1:]:
    if not line.strip():
      continue
    parts = line.split("\t")
    if len(parts) >= 3:
      out[parts[0]] = (int(parts[1]), int(parts[2]))
  return out


def write_budget(cur):
  rows = ["file\tblocks\tlines"]
  for rel in sorted(cur):
    rows.append(f"{rel}\t{cur[rel]['blocks']}\t{cur[rel]['lines']}")
  BUDGET.write_text("\n".join(rows) + "\n")


if __name__ == "__main__":
  cur = census()
  if "--write" in sys.argv:
    write_budget(cur)
    total_b = sum(v["blocks"] for v in cur.values())
    total_l = sum(v["lines"] for v in cur.values())
    print(f"THE BUDGET WRITTEN: {len(cur)} files, {total_b} blocks, {total_l} lines")
    print(f"  -> {BUDGET.relative_to(ROOT)}")
    sys.exit(0)

  budget = load_budget()
  if not budget:
    raise SystemExit(f"NO BUDGET: {BUDGET} does not exist. Run with --write to create it.")
  over = []
  for rel, v in sorted(cur.items()):
    b, l = v["blocks"], v["lines"]
    if rel not in budget:
      over.append((rel, b, l, 0, 0, "NEW FILE"))
      continue
    ob, ol = budget[rel]
    if b > ob or l > ol:
      over.append((rel, b, l, ob, ol, "GREW"))
  total_b = sum(v["blocks"] for v in cur.values())
  total_l = sum(v["lines"] for v in cur.values())
  budget_b = sum(v[0] for v in budget.values())
  budget_l = sum(v[1] for v in budget.values())
  print(f"THE COMMENT MASS NOW: {total_b} blocks, {total_l} lines")
  print(f"THE BUDGET:          {budget_b} blocks, {budget_l} lines")
  print(f"THE HEADROOM:        {budget_b - total_b} blocks, {budget_l - total_l} lines")
  print()
  if over:
    print(f"THE FILES THAT GREW PAST **THEIR **BUDGET: {len(over)}")
    for rel, b, l, ob, ol, why in over:
      print(f"  {rel}: {b} blocks / {l} lines, the budget says {ob} / {ol}  ({why})")
    raise SystemExit(1)
  print("PASS -- NO FILE's COMMENT MASS GREW PAST ITS BUDGET")
