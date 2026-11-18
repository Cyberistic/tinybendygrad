#!/usr/bin/env python3
"""**THE **SECTION **PLAN** -- **THE **LONG **SECTIONS **OF **THE **LANE**, **⇒⇒† AND **FOR
**EACH **ONE **IT **PRINTS **THE **SECTIONS **AND **WHICH **OF **THEM **THE **RULE **KEEPS**.

**⇒⇒† AND **THE **RULE **IS **THE **TREE's **OWN**:
  1. **A **SECTION **THAT **CARRIES **NO **DIFFERENCE, **NO **MEASUREMENT, **NO **CITATION
     **AND **NO **WEIRD **IS **NARRATION**, **⇒⇒† AND **IT **IS **CUT **TO **ITS **FIRST
     **SENTENCE**.
  2. **A **SECTION **THAT **CARRIES **ONE **IS **KEPT**, **⇒⇒† AND **THE **ESSAY **AROUND
     **THE **FACT **IS **CUT **INSIDE **IT**.

**⇒⇒† AND **IT **NEVER **WRITES**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
_spec = importlib.util.spec_from_file_location("ta", ROOT/".agents/slop/comments/trim-apply.py")
ta = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ta)
_cc = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(_cc); _cc.loader.exec_module(cc)

def sections(blk):
  out, cur = [], []
  for line in blk:
    if line.strip() == "#":
      if cur: out.append(cur)
      out.append([line]); cur = []
    else: cur.append(line)
  if cur: out.append(cur)
  return out

only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
tot_b = tot_a = 0
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    for sec in sections(blk):
        if len(sec) < 6: continue
        keep, why = ta.keep_count(sec)
        if keep >= len(sec): continue
        tot_b += len(sec); tot_a += keep
        print(f"{len(sec):5d} -> {keep:5d}  {rel}:{ln}  [{why}]")
print(f"SECTIONS {tot_b} -> {tot_a}")
