#!/usr/bin/env python3
"""**THE **COMMENT **RULE**, **AND **THE **CENSUS **THAT **MEASURES **THE **PORT **AGAINST **IT**.

**THE **RULE** (THE **TREE's **OWN**, `AGENTS.md:16`): *"You must use concise, clean code. No hacks
should be used. **If you need to write a paragraph-long comment to justify your code, you are doing it
wrong.** Find a better way."* -- **⇒⇒† AND **THE **USER's **FORM**: **A **COMMENT **SHOULD **ONLY **BE
**THERE **IF **IT **SHORTLY **EXPLAINS **A **DIFFERENCE **OR **WHY **WE **ARE **DOING **SOMETHING
**WEIRD**.

**⇒⇒† AND **SO **A **COMMENT **EARNS **ITS **PLACE **IN **ONE **OF **THREE **WAYS**, **⇒⇒† AND **AND **IT
**EARNES **IT **IN **A **FEW **LINES**:

| THE **CLASS** | THE **TEST** |
|---|---|
| **DIFFERENCE** | **THE **COMMENT **SAYS **WHAT **THE **PORT **DOES **THAT **UPSTREAM **DOES **NOT** (⇒⇒† AND **IT
**NAMES **THE **UPSTREAM **LINE **IT **DEPARTS **FROM**) |
| **WEIRD** | **THE **COMMENT **SAYS **WHY **SOMETHING **LOOKS **WRONG **BUT **IS **NOT** (⇒⇒† AND **A
**SUBSTRATE **LIMIT**, **A **WORKAROUND**, **A **GOTCHA**) |
| **MEASURED** | **THE **COMMENT **CARRIES **THE **NUMBER **THAT **JUSTIFIES **THE **CODE** (⇒⇒† AND **A
**COMMENT **WITH **A **MEASUREMENT **IS **EVIDENCE**, **⇒⇒† AND **WITHOUT **IT **IT **IS **AN **OPINION**) |

**⇒⇒† AND **EVERYTHING **ELSE **IS **NARRATION** -- **⇒⇒† AND **NARRATION **IS **WHAT **GETS **CUT**:
**RESTATEMENTS **OF **WHAT **THE **CODE **DOES**, **THE **PORTING **PROCESS **("THIS **IS **A
**TRANSLATION **OF**", "**THE **RULE **IS **1:1**")**, **SECTION **HEADERS **THAT **RESTATE **THE **CODE's
**OWN **STRUCTURE**, **AND **ESSAYS **THAT **JUSTIFY **A **DEF **THE **READER **CAN **SEE **IS **RIGHT**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **A **WALK **OVER
**`tinybendygrad/` **FOR **THE **`.bend` **FILES**, **⇒⇒† AND **A **RUN **OF **CONTIGUOUS **`#` **LINES**
**IS **A **BLOCK** -- **⇒⇒† AND **NOT **A **HAND **LIST**.

**⇒⇒† AND **THE **OUTPUT **IS **A **ROW **FILE **OF **THE **BLOCKS **WITH **THEIR **VERDICT**, **⇒⇒† AND
**AND **IT **CAN **BE **READ **BY **A **HUMAN **AND **BY **A **SCRIPT**, **⇒⇒† AND **AND **THE **SCRIPT
**CAN **PRINT **THE **PER-FILE **MASS**, **⇒⇒† AND **SO **THE **CUT **IS **ASSIGNABLE**.
"""

import os
import pathlib
import re
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

# **THE **CITATION** -- **⇒⇒† AND **THE **PORT's **OWN **JOIN **KEY **WITH **UPSTREAM**: **A **COMMENT
# **THAT **DEPARTS **FROM **UPSTREAM **MUST **NAME **THE **LINE **IT **DEPARTS **FROM**.
CITE = re.compile(r"(?:tinygrad/)?[A-Za-z_][\w/]*\.py:\d+")

# **THE **DIFFERENCE **MARKERS** -- **⇒⇒† AND **THE **WORDS **THAT **SAY **"WE **ARE **NOT **DOING **WHAT
# **UPSTREAM **DOES"**.
DIFFERENCE = re.compile(
  r"\b(DIFFERENT|DIFFERS|NOT UPSTREAM|INSTEAD OF|INSTEAD,|UNLIKE|UPSTREAM SPELLS|UPSTREAM'S OWN|"
  r"WE DO NOT|THE PORT DOES NOT|DOES NOT HAVE|DOES NOT PORT|CONTRAST|OPPOSITE|EXCEPT THAT|"
  r"AND NOT|AND THE PORT|ONLY THE PORT|NOT THE SAME|WRONG|FALSE|STALE|BROKEN)\b")

# **THE **WEIRD **MARKERS** -- **⇒⇒† AND **A **SUBSTRATE **LIMIT **OR **A **WORKAROUND **IS **THE **PORT's
# **OWN **REASON **FOR **A **DIFFERENCE**.
WEIRD = re.compile(
  r"\b(BEND HAS|BEND'S|NO PROJECTION|CANNOT|CAN NOT|REFUSED|REFUSES|MUST BE SPELLED|NEEDS A|"
  r"IS A ONE|ONLY BECAUSE|BECAUSE THE|NO FUNCTION VALUE|NO CLOSURE|COMPUTED VALUE|"
  r"UNARY|WRAPS|SATURATES|IS AN ERROR|IS REFUSED|WALLS?|NOT PORTED|UNPORTED|TODO\(p[0-9]\)|"
  r"THE SUBSTRATE|SUBSTRATE|SURPRISINGLY|COUNTER-INTUITIVE|COUNTERINTUITIVE|NON-OBVIOUS|"
  r"THE TRAP|THE GOTCHA|HAZARD|WARNING|CAREFUL|IMPORTANT|NOTE THAT|"
  r"SCRUTINEE|SCRUTINE|MUST ONLY|ONLY IF|MAY ONLY|CANNOT|REFUSE|DENIED|ILLEGAL|"
  r"THE READER|WHAT LOOKS|LOOKS WRONG|IS NOT A BUG|WAS A BUG|THE WALL|"
  r"THE GOAL|THE CURE|IS THE POINT|WHY THIS|AND NOT|INSTEAD OF|RATHER THAN|"
  r"ONLY\s+\S+\s+MAY\s+ONLY|MAY\s+ONLY\s+\S+|MAY\s+ONLY\s+SCRUTINEE|"
  r"ONLY\s+SCRUTINEE)\b")

# **THE **MEASUREMENT **MARKERS** -- **⇒⇒† AND **THE **NUMBER **THAT **JUSTIFIES **THE **CODE**.
MEASURED = re.compile(
  r"\b(MEASURED|MS\b|MICROSECONDS|US\b|OBSERVED|COUNTED|VERDICT|RATIO|READS \d|THE COUNT|"
  r"\d+(\.\d+)? (CONS|CELLS|CALLS|TURNS|ROWS|LINES|PERCENT|%))\b")

# **THE **NARRATION **MARKERS** -- **⇒⇒† AND **THE **PORTING **PROCESS **AND **THE **CODE's **OWN
# **STRUCTURE **RESTATED**.
NARRATION = re.compile(
  r"\b(THIS FILE IS|WHAT THIS FILE IS|WHAT IS HERE|ITEM BY ITEM|1:1 RULING|TRANSLATION|"
  r"TRANSCRIPTION|ONE-TO-ONE|THE PORT IS A PORT OF|PORT OF|COUNTERPART|UPSTREAM'S FILE|"
  r"THE UPSTREAM FILE|SEE THE HEADER|AS UPSTREAM|THE PORT's COPY|RULE \d+ IS|THE \d+ (RULE|DEFS?))\b")


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


def verdict(text: str) -> str:
  """**THE **VERDICT **FOR **ONE **BLOCK**.

  **⇒⇒† AND **THE **ORDER **MATTERS**, **⇒⇒† AND **HERE **IS **WHY**: **A **CITATION **IS **A
  **DIFFERENCE's **PROOF**, **⇒⇒† AND **SO **IT **WINS**, **⇒⇒† AND **BUT **A **CITATION **PLUS **A
  **NARRATION **MARKER** (THE **PORTING **PROCESS) **IS **STILL **NARRATION** -- **⇒⇒† AND **SO **THE
  **NARRATION **TEST **RUNS **FIRST**.
  """
  if NARRATION.search(text) and not WEIRD.search(text) and not DIFFERENCE.search(text):
    return "NARRATION"
  if DIFFERENCE.search(text) or CITE.search(text):
    return "DIFFERENCE"
  if WEIRD.search(text):
    return "WEIRD"
  if MEASURED.search(text):
    return "MEASURED"
  return "NARRATION"


if __name__ == "__main__":
  only = sys.argv[1] if len(sys.argv) > 1 else ""
  counts = Counter()
  lines = Counter()
  per_file = {}
  for f, ln, blk in blocks():
    rel = str(f.relative_to(PORT))
    if only and not rel.startswith(only):
      continue
    v = verdict(" ".join(blk))
    counts[v] += 1
    lines[v] += len(blk)
    per_file.setdefault(rel, Counter())[v] += 1
  total = sum(counts.values())
  total_lines = sum(lines.values())
  keep = counts["DIFFERENCE"] + counts["WEIRD"] + counts["MEASURED"]
  keep_lines = lines["DIFFERENCE"] + lines["WEIRD"] + lines["MEASURED"]
  print(f"THE COMMENT BLOCKS: {total}  ({total_lines} lines)")
  print(f"{'CLASS':12s} {'BLOCKS':>7s} {'LINES':>7s} {'%BLOCKS':>8s}")
  for c in ("DIFFERENCE", "WEIRD", "MEASURED", "NARRATION"):
    print(f"{c:12s} {counts[c]:7d} {lines[c]:7d} {100*counts[c]/max(total,1):7.1f}%")
  print()
  print(f"THE KEEP SET: {keep} blocks ({100*keep/max(total,1):.1f}%), {keep_lines} lines "
        f"({100*keep_lines/max(total_lines,1):.1f}%)")
  print(f"THE NARRATION SET: {counts['NARRATION']} blocks ({100*counts['NARRATION']/max(total,1):.1f}%), "
        f"{lines['NARRATION']} lines ({100*lines['NARRATION']/max(total_lines,1):.1f}%)")
  if per_file:
    print()
    print("THE TOP FILES BY THE NARRATION MASS:")
    for f, c in sorted(per_file.items(), key=lambda kv: -kv[1]["NARRATION"])[:15]:
      if c["NARRATION"]:
        print(f"  {c['NARRATION']:5d} narration / {sum(c.values()):5d} total  {f}")
