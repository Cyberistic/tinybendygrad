#!/usr/bin/env python3
"""**THE **CUT **PLAN** -- **THE **PARAGRAPHS **THE **RULE **CUTS**, **WITH **THEIR **TEXT**,
**⇒⇒† AND **IT **NEVER **WRITES**."""
import importlib.util, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
_spec = importlib.util.spec_from_file_location("ta", ROOT/".agents/slop/comments/trim-apply.py")
ta = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ta)
_cc = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(_cc); _cc.loader.exec_module(cc)
CITE = ta.CITE
MEAS = ta.MEASURED
WALL = re.compile(r"\b(WALL\b|BLOCKED|REFUSED|REFUSES|CANNOT|CAN NOT|MUST BE|MUST ONLY|IS NOT A|ARE NOT|WRONG|STALE|BROKEN)\b")
DIFF = ta.DIFFERENCE
ITEM = re.compile(r"^\s*#\s*(?:[-*+]\s+|\d+[.)]\s+)")
BUGREC = re.compile(r"\b(BUG|DEFECT|TOMBSTONE|WAS WRONG|WERE WRONG|FIRST GATE RUN|FOUND AND|REGRESSION|MISCOUNT|WAS NOT\b|HASTHE|A MIS-)\b", re.I)
def keep(p):
  t = " ".join(p)
  return bool(CITE.search(t) or MEAS.search(t) or WALL.search(t) or DIFF.search(t))
def paragraphs(blk):
  out, cur = [], []
  for line in blk:
    if line.strip() == "#":
      if cur: out.append(cur)
      out.append([line]); cur = []
    else: cur.append(line)
  if cur: out.append(cur)
  return out
only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
tot = 0; n = 0
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    if len(blk) <= 6: continue
    for p in paragraphs(blk):
      if all(l.strip() == "#" for l in p): continue
      if keep(p): continue
      if any(ITEM.match(l) for l in p): continue
      t = " ".join(p)
      if BUGREC.search(t): continue
      body = [l for l in p if l.strip() != "#"]
      k = ta.sentence_end(body, 0) if body else len(p)
      if len(p) - k < 2: continue
      n += 1; tot += len(p) - k
      print(f"--- {rel}:{ln}  {len(p)}L -> {k}L")
      for i, l in enumerate(p): print(f"   {'K' if i < k else 'C'} |{l}")
print(f"PARAGRAPHS {n}  LINES {tot}")
