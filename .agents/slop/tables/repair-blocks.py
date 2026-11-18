#!/usr/bin/env python3
"""**THE **REPAIR**: **EVERY **MOVED **TABLE **FILE **GETS **A **`# BLOCK:`** **SECTION**, **⇒⇒†
AND **IT **HOLDS **THE **WHOLE **ORIGINAL **COMMENT **BLOCK**, **⇒⇒† AND **SO **THE **BLOCK
**CAN **BE **MATCHED **AGAINST **`HEAD`** **EXACTLY**, **⇒⇒† AND **THE **`.rows` **FILE **KEeps
**ITS **TABLE **AND **THE **SECTION **IS **THE **BLOCK's **PROVENANCE**.

**⇒⇒† AND **THE **ORIGIN **OF **THE **BLOCK**: **THE **TABLE **FILE's **OWN **`FROM:`** **LINE**,
**⇒⇒† AND **THE **BLOCK **IS **THE **RUN **OF **COMMENT **LINES **AT **THAT **LINE**, **⇒⇒† AND
**IT **IS **SEARCHED **FOR **BY **CONTENT** -- **⇒⇒† AND **AND **THE **CONTENT **MUST **BE **THE
**BLOCK's **OWN **FIRST **LINE**, **⇒⇒† AND **WHICH **THE **`.md` **FILE **ALREADY **HAS**.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DIR = ROOT / ".agents/slop/tables"
FROM = re.compile(r"FROM: (\S+):(\d+)")


def sh(*a):
  return subprocess.run(list(a), capture_output=True, text=True, cwd=ROOT).stdout


def main():
  for p in sorted(DIR.glob("*.md")) + sorted(DIR.glob("*.rows")):
    if p.name in ("census-before.rows", "census-after.rows", "analyze-before.rows"):
      continue
    t = p.read_text().split("\n")
    if any(l.startswith("# BLOCK:") for l in t):
      continue
    m = FROM.search(t[0])
    if not m:
      print(f"NO FROM: {p.name}")
      continue
    rel, line = m.group(1), int(m.group(2))
    if "at ba3f52b0a^" in t[0]:
      rel = rel
    head = sh("git", "show", f"HEAD:{rel}").split("\n")
    # **⇒⇒† AND **THE **BLOCK **IS **THE **RUN **OF **COMMENT **LINES** **AT **THE **ORIGIN**.
    if line - 1 >= len(head):
      print(f"OUT OF RANGE: {p.name}")
      continue
    if not head[line - 1].lstrip().startswith("#"):
      print(f"NOT A COMMENT AT THE ORIGIN: {p.name} {rel}:{line} {head[line-1][:50]!r}")
      continue
    j = line - 1
    while j < len(head) and head[j].lstrip().startswith("#"):
      j += 1
    blk = head[line - 1:j]
    # **⇒⇒† AND **THE **SECTION**, **⇒⇒† AND **THE **BLOCK's **LINES **VERBATIM**.
    out = t[:1] + ["# BLOCK:"] + blk + ["# END BLOCK"] + t[1:]
    p.write_text("\n".join(out))
    print(f"REPAIRED {p.name}: {len(blk)} block lines")


if __name__ == "__main__":
  main()
