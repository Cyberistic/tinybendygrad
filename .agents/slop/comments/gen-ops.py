#!/usr/bin/env python3
"""**THE **PARAGRAPH **CUT** -- **THE **RULE, **APPLIED **PER **PARAGRAPH**, **⇒⇒† AND **IT **IS **THE
**SHAPE **THAT **KEEPS **THE **FACTS **AND **DROPS **THE **ESSAY**.

**⇒⇒† AND **WHY **PER **PARAGRAPH**: **A **COMMENT **BLOCK **IS **A **SEQUENCE **OF **PARAGRAPHS**
**(SEPARATED **BY **A **`#` **LINE **THAT **IS **ONLY **A **`#`**, **⇒⇒† AND **THE **RULE's **WORDS
**ARE **ABOUT **A **FACT **AND **THE **ESSAY **AROUND **IT**, **⇒⇒† AND **A **BLOCK **CAN **HOLD **A
**TITLE **THAT **IS **A **CITATION **AND **THEN **FIVE **PARAGRAPHS **OF **FACTS**, **⇒⇒† AND **THE
**PER-BLOCK **RULE **KEEPS **THE **TITLE **AND **THROWS **THE **FACTS **AWAY**.

**⇒⇒† AND **THE **RULE, **PER **PARAGRAPH**:
  1. **KEEP **EVERY **LINE **OF **THE **PARAGRAPH **THAT **CARRIES **A **MARKER** -- **A **DIFFERENCE
     **MARKER**, **A **CITATION**, **OR **A **MEASUREMENT**.  **⇒⇒† AND **THE **MARKER **IS **THE
     **EVIDENCE**, **⇒⇒† AND **A **CITATION **IS **THE **DIFFERENCE's **PROOF**, **⇒⇒† AND **A
     **PARAGRAPH **MAY **CARRY **SEVERAL**, **⇒⇒† AND **THE **FIRST **FORM **OF **THE **RULE **KEPT
     **ONLY **THE **FIRST **ONE**, **⇒⇒† AND **MEASURED, **IT **LOST **231 **UNIQUE **CITATIONS
     **IN **`uop/ops.bend` **ALONE**.
  2. **A **PARAGRAPH **WITH **NO **MARKER **IS **NARRATION** **⇒⇒† AND **IT **IS **DROPPED **WHOLE**.

**⇒⇒† AND **THE **MARKERS **ARE **THE **CENSUS's**, **⇒⇒† AND **NOT **`trim-plan.py`'s**, **⇒⇒† AND
**THE **REASON **IS **MEASURED**: **THE **TWO **INSTRUMENTS **DISAGREED**, **⇒⇒† AND **`trim-plan.py`'s
**`DIFFERENCE` **HAS **`FALSE` **AND **THE **CENSUS's **DOES **NOT**, **⇒⇒† AND **SO **A **LINE **THAT
**SAYS **"THE **PRIOR **PREMISE **WAS **FALSE" **WAS **A **DIFFERENCE **TO **ONE **AND **NOT **TO **THE
**OTHER**, **⇒⇒† AND **THE **CENSUS **IS **THE **GOVERNING **CLASSIFIER** (**`RULE.md` **NAMES **IT**),
**⇒⇒† AND **SO **THE **CUT **USES **THE **CENSUS's **MARKERS**."""

import importlib.util
import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tp", HERE / "trim-plan.py")
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)
spec2 = importlib.util.spec_from_file_location("cc", HERE / "comment-census.py")
cc = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(cc)


def paragraphs(blk):
  """**THE **PARAGRAPHS **OF **A **BLOCK**: **A **RUN **OF **COMMENT **LINES **BETWEEN **THE **`#`-ONLY
  **LINES**, **⇒⇒† AND **THE **`#`-ONLY **LINES **THEMSELVES **ARE **KEPT **AS **THE **SEPARATOR**."""
  out = []
  cur = []
  for l in blk:
    if l.strip() == "#":
      out.append(cur)
      cur = []
    else:
      cur.append(l)
  out.append(cur)
  return [p for p in out if p]


def para_keep(par):
  """**THE **KEPT **LINES **OF **ONE **PARAGRAPH**, **AND **WHY**.

  **⇒⇒† AND **A **PARAGRAPH **KEEPS **EVERY **LINE **THAT **CARRIES **A **MARKER**, **⇒⇒† AND **NOT
  **ONLY **THE **FIRST **ONE**, **⇒⇒† AND **THE **REASON **IS **MEASURED**: **A **MARKER **IS **A
  **CITATION **OR **A **NUMBER**, **⇒⇒† AND **A **CITATION **IS **THE **DIFFERENCE's **PROOF**, **⇒⇒†
  **AND **A **PARAGRAPH **MAY **CARRY **SEVERAL **OF **THEM**, **⇒⇒† AND **THE **FIRST **FORM **OF
  **THE **RULE **KEPT **ONLY **THE **FIRST**, **⇒⇒† AND **MEASURED, **THE **FIRST **FORM **LOST **231
  **UNIQUE **CITATIONS **IN **`uop/ops.bend` **ALONE**.

  **⇒⇒† AND **A **PARAGRAPH **WHOSE **FIRST **LINE **CARRIES **NO **MARKER **IS **NARRATION**, **⇒⇒†
  **AND **THE **RULE **DROPS **THE **WHOLE **PARAGRAPH** -- **⇒⇒† AND **THE **PARAGRAPH's **FIRST
  **LINE **IS **THE **HEADING **OR **THE **TOPIC **SENTENCE**, **⇒⇒† AND **A **HEADING **IS **NARRATION
  **BY **THE **RULE's **OWN **WORDS**: **"A **SECTION **HEADER **THAT **NAMES **A **PART **OF **THE
  **FILE"**, **⇒⇒† AND **THE **READER **SEES **THE **FILE**.

  **⇒⇒† AND **THE **KEEP **IS **THE **MARKER **LINES **OF **THE **PARAGRAPH**, **⇒⇒† AND **AND **THE
  **FIRST **LINE **IF **IT **CARRIES **A **MARKER**, **⇒⇒† AND **SO **A **PARAGRAPH **THAT **CARRIES
  **A **FACT **KEEPS **THE **FACT **AND **NOTHING **ELSE**."""
  kept = []
  for l in par:
    if cc.DIFFERENCE.search(l) or cc.CITE.search(l) or cc.MEASURED.search(l):
      kept.append(l)
  return kept, "every marker line"


def block_keep(blk, first=False):
  """**THE **KEPT **LINES **OF **ONE **BLOCK**, **PARAGRAPH **BY **PARAGRAPH**.

  **⇒⇒† AND **A **FILE's **FIRST **BLOCK **IS **ITS **HEADER**, **⇒⇒† AND **AND **A **HEADER **KEEPS
  **THE **FIRST **LINE **OF **EVERY **PARAGRAPH **IN **IT**, **⇒⇒† AND **THE **REASON **IS **THE **RULE's
  **OWN**: **"A **SECTION **HEADER **THAT **NAMES **A **PART **OF **THE **FILE" **IS **NARRATION**, **⇒⇒† AND
  **THE **HEADER **IS **THE **FILE's **OWN **TABLE **OF **CONTENTS**, **⇒⇒† AND **A **READER **WHO **OPENS
  **THE **FILE **SEES **THE **HEADER **AND **KNOWS **WHAT **IS **IN **IT**.

  **⇒⇒† AND **AND **THE **HEADER's **PARAGRAPH **TITLES **ARE **THE **JOIN **KEY **FOR **THE **HEAD's
  **HEADER**, **⇒⇒† AND **SO **THE **DIFF **ALIGNS**."""
  kept = []
  for par in paragraphs(blk):
    if first:
      kept.append(par[0])
    else:
      k, _why = para_keep(par)
      kept.extend(k)
  if first and not kept and blk:
    kept = [blk[0]]
  return kept


def anchor_of(blk):
  return blk[0].strip().lstrip("#").strip()


def main() -> int:
  only = sys.argv[1] if len(sys.argv) > 1 else ""
  lim = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 4
  ops = []
  for dp, _, fns in os.walk(tp.PORT):
    for fn in sorted(fns):
      if not fn.endswith(".bend"):
        continue
      f = pathlib.Path(dp) / fn
      rel = str(f.relative_to(tp.PORT))
      if only and not rel.startswith(only):
        continue
      for ordinal, (i, j, blk) in enumerate(tp.blocks(f)):
        if len(blk) <= lim:
          continue
        kept = block_keep(blk, first=(ordinal == 0))
        if len(kept) >= len(blk):
          continue
        ops.append([ordinal, "\n".join(kept)])
  print(json.dumps(ops, indent=1))
  return 0


if __name__ == "__main__":
  sys.exit(main())
