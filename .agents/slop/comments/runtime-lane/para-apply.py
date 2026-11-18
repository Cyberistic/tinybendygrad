#!/usr/bin/env python3
"""**THE **PARAGRAPH **APPLIER** -- **CUT **AT **PARAGRAPH **GRANULARITY**, **⇒⇒† AND **KEEP
**THE **PARAGRAPHS **THAT **CARRY **A **MARKER**.

**⇒⇒† AND **THE **SAFETY **PROPERTY**: **A **KEPT **PARAGRAPH **IS **A **PREFIX **OF **THE
**ORIGINAL**, **⇒⇒† AND **SO **A **KEPT **LINE **IS **NEVER **REWRITTEN**, **⇒⇒† AND **ONLY
**WHOLE **COMMENT **LINES **ARE **DELETED**.

**⇒⇒† AND **THE **RULE**:
  * **A **PARAGRAPH **WITH **NO **MARKER **IS **CUT **TO **ITS **FIRST **SENTENCE** -- **⇒⇒†
    **AND **IF **THAT **FIRST **SENTENCE **IS **THE **WHOLE **PARAGRAPH**, **⇒⇒† AND **THE
    **PARAGRAPH **GOES **ENTIRELY**.
  * **A **PARAGRAPH **WITH **A **MARKER **IS **KEPT** -- **⇒⇒† AND **THE **ESSAY **AROUND
    **THE **FACT **IS **THE **NEXT **STEP**, **BY **HAND**.
  * **A **LIST **IS **KEPT **WHOLE **IF **ANY **OF **ITS **ITEMS **CARRIES **A **MARKER**.
  * **A **PARAGRAPH **THAT **OPENS **WITH **A **LEAD-IN **AND **WHOSE **BODY **WAS **CUT**
    **IS **CUT **WHOLE**, **⇒⇒† AND **A **HEADER **WITH **NO **BODY **IS **WORSE **THAN
    **NOTHING**.

**⇒⇒† AND **IT **NEVER **WRITES** -- **⇒⇒† AND **IT **PRINTS **THE **PLAN**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
_spec = importlib.util.spec_from_file_location("ta", ROOT/".agents/slop/comments/trim-apply.py")
ta = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ta)
_cc = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(_cc); _cc.loader.exec_module(cc)

def paragraphs(blk):
  out, cur = [], []
  for line in blk:
    if line.strip() == "#":
      if cur: out.append(cur)
      out.append([line]); cur = []
    else: cur.append(line)
  if cur: out.append(cur)
  return out

def marker(p):
  return any(ta.is_marker(l) for l in p if l.strip() != "#")

def first_sentence(p):
  body = [l for l in p if l.strip() != "#"]
  if not body: return len(p)
  return ta.sentence_end(body, 0)

def plan(blk):
  """**THE **KEPT **LINE **COUNT **OF **A **BLOCK**, **BY **PARAGRAPH**."""
  kept = 0
  for p in paragraphs(blk):
    if all(l.strip() == "#" for l in p): continue
    if marker(p): kept += len(p); continue
    kept += min(len(p), first_sentence(p))
  return kept

only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
tot_b = tot_a = 0
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    if len(blk) <= 6: continue
    k = plan(blk)
    if k >= len(blk): continue
    tot_b += len(blk); tot_a += k
    print(f"{len(blk):5d} -> {k:5d}  {rel}:{ln}")
print(f"BLOCKS {tot_b} -> {tot_a}")
