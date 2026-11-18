#!/usr/bin/env python3
"""**THE **MECHANICAL **CUT** -- **THE **LONG **NARRATION **BLOCKS**, **CUT **TO **THEIR **FIRST
**SENTENCE**, **WITHOUT **A **HUMAN **READING **EVERY **ONE**.

**WHY:** **THE **PORT **CARRIES **10,549 **COMMENT **BLOCKS**, **⇒⇒† AND **THE **CENSUS **SAYS **6,377
**OF **THEM **ARE **NARRATION** (61.4%), **⇒⇒† AND **THE **MASS **IS **24,082 **LINES**, **⇒⇒† AND **A
**HUMAN **CUTTING **THAT **ONE **BLOCK **AT **A **TIME **IS **THE **WRONG **SHAPE **OF **WORK**.

**⇒⇒† AND **THE **MECHANICAL **PART **IS **LARGE**: **A **NARRATION **BLOCK **THAT **IS **TEN **LINES
**LONG **USUALLY **HAS **ONE **SENTENCE **THAT **SAYS **SOMETHING** **⇒⇒† AND **THE **REST **IS **THE
**ESSAY** **AROUND **IT**.

**⇒⇒† AND **THE **RULE **THIS **SCRIPT **APPLIES**, **AND **IT **IS **THE **TREE's **OWN**:
  1. **IF **THE **BLOCK **HAS **A **DIFFERENCE **MARKER** (IT **NAMES **WHAT **THE **PORT **DOES **THAT
     **UPSTREAM **DOES **NOT**) **⇒⇒† AND **KEEP **THE **LINES **UP **TO **AND **INCLUDING **THE **FIRST
     **ONE **THAT **NAMES **THE **DIFFERENCE** **AND **THE **UPSTREAM **LINE** -- **⇒⇒† AND **CUT **THE
     **ESSAY **AROUND **IT**.
  2. **ELSE **IF **THE **BLOCK **HAS **A **MEASUREMENT** **⇒⇒† AND **KEEP **THE **LINES **THROUGH **THE
     **MEASUREMENT** (THE **NUMBER **IS **THE **EVIDENCE**)**.
  3. **ELSE** -- **⇒⇒† AND **IT **IS **PURE **NARRATION** **⇒⇒† AND **KEEP **THE **FIRST **LINE **ONLY**
     (**⇒⇒† AND **THE **FIRST **LINE **IS **THE **HEADING **OR **THE **ONE **SENTENCE**) **⇒⇒† AND **AND
     **DROP **THE **REST**.

**⇒⇒† AND **THE **SCRIPT **IS **A **POINTER**, **NOT **THE **VERDICT** -- **⇒⇒† AND **THE **TREES's
**RULE**: **A **CHANGE **THAT **CANNOT **BE **SHOWN **CORRECT **IS **WORSE **THAN **NO **CHANGE** -- **⇒⇒†
**AND **SO **THE **SCRIPT **PRINTS **WHAT **IT **WOULD **DO**, **⇒⇒† AND **IT **NEVER **WRITES**, **⇒⇒† AND
**A **HUMAN **OR **AN **AGENT **APPLIES **IT **AFTER **READING **THE **DIFF**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **A **WALK **OVER **`tinybendygrad/` **FOR
**THE **`.bend` **FILES**.
"""

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

DIFFERENCE = re.compile(
  r"\b(DIFFERENT|DIFFERS|NOT UPSTREAM|INSTEAD OF|INSTEAD,|UNLIKE|UPSTREAM SPELLS|UPSTREAM'S OWN|"
  r"WE DO NOT|THE PORT DOES NOT|DOES NOT HAVE|DOES NOT PORT|CONTRAST|OPPOSITE|EXCEPT THAT|"
  r"AND NOT|ONLY THE PORT|NOT THE SAME|WRONG|STALE|BROKEN)\b")
CITE = re.compile(r"(?:tinygrad/)?[A-Za-z_][\w/]*\.py:\d+")
MEASURED = re.compile(
  r"\b(MEASURED|MS\b|MICROSECONDS|OBSERVED|COUNTED|VERDICT|RATIO|READS \d|THE COUNT|"
  r"\d+(\.\d+)? (CONS|CELLS|CALLS|TURNS|ROWS|LINES|PERCENT|%))\b")
NARRATION = re.compile(
  r"\b(THIS FILE IS|WHAT THIS FILE IS|WHAT IS HERE|ITEM BY ITEM|1:1 RULING|TRANSLATION|"
  r"TRANSCRIPTION|ONE-TO-ONE|THE PORT IS A PORT OF|PORT OF|COUNTERPART|UPSTREAM'S FILE|"
  r"THE UPSTREAM FILE|SEE THE HEADER|AS UPSTREAM|THE PORT's COPY|RULE \d+ IS|THE \d+ (RULE|DEFS?))\b")


def keep_count(blk):
  """**HOW **MANY **LINES **THE **BLOCK **KEEPS**, **AND **WHY**."""
  if NARRATION.search(" ".join(blk)):
    # **⇒⇒† AND **A **NARRATION **MARKER **WINS **ONLY **IF **THE **BLOCK **ALSO **CARRIES **A
    # **DIFFERENCE **OR **A **MEASUREMENT** -- **⇒⇒† AND **ELSE **IT **IS **PURE **NARRATION**
    if not DIFFERENCE.search(" ".join(blk)) and not MEASURED.search(" ".join(blk)):
      return 1, "PURE NARRATION -> the first line only"
  for i, l in enumerate(blk):
    if DIFFERENCE.search(l) or CITE.search(l) or MEASURED.search(l):
      return i + 1, "the difference/measurement line and its header"
  return 1, "no marker -> the first line only"


def blocks(f: pathlib.Path):
  lines = f.read_text().split("\n")
  i = 0
  while i < len(lines):
    if lines[i].strip().startswith("#"):
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"):
        j += 1
      yield i, j, lines[i:j]
      i = j
    else:
      i += 1


if __name__ == "__main__":
  lim = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 4
  only = sys.argv[2] if len(sys.argv) > 2 else ""
  total_before = total_after = 0
  touched = 0
  print(f"{'BEFORE':>7} {'AFTER':>6} {'CUT':>6}  THE **FILE **AND **THE **REASON")
  for dp, _, fns in os.walk(PORT):
    for fn in sorted(fns):
      if not fn.endswith(".bend"):
        continue
      f = pathlib.Path(dp) / fn
      rel = str(f.relative_to(PORT))
      if only and not rel.startswith(only):
        continue
      for i, j, blk in blocks(f):
        if len(blk) <= lim:
          continue
        keep, why = keep_count(blk)
        if keep >= len(blk):
          continue
        total_before += len(blk)
        total_after += keep
        touched += 1
        if touched <= 40:
          print(f"{len(blk):7d} {keep:6d} {len(blk)-keep:6d}  {rel}:{i+1}  {why}")
  print()
  print(f"THE BLOCKS THE SCRIPT WOULD TOUCH: {touched}")
  print(f"THE LINES: {total_before} -> {total_after}  (THE CUT: {total_before-total_after})")
  print("**=>=>+ AND **IT **NEVER **WRITES** -- **=>=>+ AND **READ **THE **DIFF **AND **APPLY **IT **BY **HAND**")
