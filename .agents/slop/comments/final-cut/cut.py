#!/usr/bin/env python3
"""**THE **CUT **APPLIER**: **REPLACE **A **LINE **RANGE **WITH **NEW **TEXT**, **BY **LINE
**NUMBER**, **IN **A **`.bend` **FILE**.

**WHY **THIS **SHAPE**: **THE **CUT **IS **A **HUMAN **JUDGEMENT **PER **BLOCK**, **⇒⇒† AND **A
**REGEXP **OR **A **SUFFIX **MATCH **CANNOT **MAKE **IT**, **⇒⇒† AND **SO **THE **VERDICT **IS
**WRITTEN **OUT **AND **THE **TOOL **IS **DUMB**: **IT **MOVES **LINES **AND **NOTHING **ELSE**.

**⇒⇒† AND **IT **IS **A **BARE-EDIT **TOOL **ON **PURPOSE**: **IT **CANNOT **DECIDE **WHAT **A
**COMMENT **SAYS**, **⇒⇒† AND **THE **READER **IS **THE **JUDGE**, **⇒⇒† AND **THE **DIFF **IS
**THE **PROOF**.

**⇒⇒† AND **THE **LINE **NUMBERS **ARE **1-BASED **AND **COUNT **THE **ORIGINAL **FILE**, **⇒⇒† AND
**THE **REPLACEMENTS **ARE **APPLIED **FROM **THE **BOTTOM **UP**, **⇒⇒† AND **SO **A **REPLACEMENT
**DOES **NOT **MOVE **THE **LINES **OF **A **LATER **ONE**.
"""

import pathlib
import sys


def apply(path: str, edits: list[tuple[int, int, str]]) -> None:
  """**EDITS **ARE **`(start, end, new_text)`**, **1-BASED **AND **INCLUSIVE**, **AND **THE **RANGE
  **IS **THE **BLOCK'S **WHOLE **SPAN**."""
  p = pathlib.Path(path)
  lines = p.read_text().split("\n")
  for start, end, new in sorted(edits, key=lambda e: -e[0]):
    body = new.split("\n") if new else []
    lines[start - 1:end] = body
  p.write_text("\n".join(lines))
  print(f"{path}: {len(edits)} block(s) rewritten")


if __name__ == "__main__":
  raise SystemExit("this module is imported by a per-file script")
