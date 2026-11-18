#!/usr/bin/env python3
"""**THE **TABLE-LIKE **COMMENT **BLOCKS** -- **THE **DATA **THAT **IS **IN **THE **WRONG **PLACE**.

**WHY:** **A **TABLE **IS **DATA**, **⇒⇒† AND **DATA **IN **A **COMMENT **BLOCK **IS **A **FILE **IN **THE
**WRONG **PLACE** -- **⇒⇒† AND **THE **TREE's **OWN **RULE** (**`AGENTS.md`**) **IS **NO **`.txt`**, **`.rows`
**FOR **ROW **DUMPS**, **`.md` **FOR **PROSE**, **⇒⇒† AND **AGENT **STATE **UNDER **`.agents/slop/`**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **A **WALK **OVER **`tinybendygrad/` **FOR
**THE **`.bend` **FILES**, **⇒⇒† AND **A **RUN **OF **CONTIGUOUS **`#` **LINES** **IS **A **BLOCK**, **⇒⇒† AND
**A **BLOCK **OF **12 **OR **MORE **LINES **THAT **LOOKS **LIKE **A **TABLE** **IS **A **TABLE**.

**⇒⇒† AND **THE **TABLE's **SHAPE**, **AND **THERE **ARE **TWO**:
  · **THE **PIPE-ROWS **FORM** (**`# | a | b |`**) **⇒⇒† AND **THAT **IS **A **ROW **DUMP** **⇒⇒† AND **IT
    **GOES **TO **A **`.rows` **FILE**.
  · **THE **PROSE **FORM** (**ONE **ROW **PER **LINE**, **OR **A **WORK **QUEUE**, **OR **AN **INVENTORY**, **OR
    **A **MUTATION **LEDGER**) **⇒⇒† AND **THAT **GOES **TO **A **`.md` **FILE**.
"""

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

# **THE **PIPE-ROW **MARKER** -- **⇒⇒† AND **THE **ROWS **OF **A **MARKDOWN **TABLE**.
PIPE = re.compile(r"^\s*#\s*\|")
# **THE **PROSE-TABLE **MARKERS** -- **⇒⇒† AND **THE **HEADINGS **THAT **NAME **A **LIST **OF **ROWS**.
PROSE = re.compile(
  r"(NOT PORTED, one line each|THE INVENTORY:|THE WORK QUEUE|THE MUTATION LEDGER|"
  r"EVERY \w+ IS |THE TABLE:|THE LIST:|ONE LINE EACH|THE ROWS:)", re.I)


def blocks():
  for dp, _, fns in os.walk(PORT):
    for fn in sorted(fns):
      if not fn.endswith(".bend"):
        continue
      f = pathlib.Path(dp) / fn
      lines = f.read_text().split("\n")
      i = 0
      while i < len(lines):
        if lines[i].strip().startswith("#"):
          j = i
          while j < len(lines) and lines[j].strip().startswith("#"):
            j += 1
          yield f, i + 1, lines[i:j]
          i = j
        else:
          i += 1


if __name__ == "__main__":
  lim = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 12
  found = []
  for f, ln, blk in blocks():
    if len(blk) < lim:
      continue
    text = " ".join(blk)
    pipe = sum(1 for l in blk if PIPE.match(l))
    if pipe >= max(3, len(blk) // 4):
      kind = "ROWS"
    elif PROSE.search(text):
      kind = "MD"
    else:
      continue
    rel = str(f.relative_to(ROOT))
    # **⇒⇒† AND **A **FILE's **FIRST **BLOCK **IS **ITS **HEADER**, **⇒⇒† AND **A **HEADER **IS **NOT **A
    # **TABLE **TO **MOVE** -- **⇒⇒† AND **IT **IS **A **HEADER **TO **CUT **TO **A **POINTER** (⇒⇒† AND
    # **THE **OTHER **AGENTS **CUT **THE **HEADERS**) -- **⇒⇒† AND **SO **THE **CENSUS **MARKS **IT**.
    is_header = ln <= 40 and all(l.strip().startswith('#') for l in blk[:1])
    found.append((len(blk), "HEADER" if is_header else kind, pipe, rel, ln))
  found.sort(reverse=True)
  total = sum(f[0] for f in found)
  print(f"THE TABLE-LIKE BLOCKS (>= {lim} lines): {len(found)}, {total} lines")
  print(f"{'LINES':>6} {'KIND':>5} {'PIPE':>5}  THE **SOURCE")
  for n, kind, pipe, rel, ln in found:
    print(f"{n:6d} {kind:>5} {pipe:5d}  {rel}:{ln}")
