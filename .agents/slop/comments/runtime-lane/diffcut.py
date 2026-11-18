#!/usr/bin/env python3
"""**THE **DIFF **CUT **DETECTOR** -- **⇒⇒† AND **A **DIFF **IS **THE **ONLY **WITNESS
**THAT **CAN **SAY **"A **LINE **WAS **REMOVED **FROM **BETWEEN **THESE **TWO **LINES"**,
**⇒⇒† AND **THE **CURRENT **TEXT **CANNOT**.

**⇒⇒† AND **THE **TEST**: **IN **A **DIFF **HUNK**, **A **`-` **LINE **WHOSE **PREVIOUS
**CONTEXT **LINE **AND **NEXT **CONTEXT **LINE **ARE **BOTH **`+` **OR **CONTEXT**, **⇒⇒† AND
**THE **`-` **LINES **BETWEEN **THEM **ARE **THE **CUT**, **⇒⇒† AND **THE **SURVIVING
**NEIGHBOURS **ARE **NOW **ADJACENT **AND **THE **PARAGRAPH **IS **A **FRAGMENT**."""
import subprocess, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[4]
import importlib.util
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)

def fragments(rel, path):
  """**THE **CUT **FRAGMENT's **TWO **SURVIVING **NEIGHBOURS**, **FROM **THE **DIFF**."""
  d = subprocess.run(["git","log","-p","--format=@@@%H","--",path], cwd=ROOT, capture_output=True, text=True).stdout
  out = []
  cur = None
  for line in d.split("\n"):
    if line.startswith("@@@"):
      cur = [line[3:], []]; out.append(cur)
    elif cur is not None: cur[1].append(line)
  hits = []
  for cid, body in out:
    # **⇒⇒† AND **THE **HUNKS**.
    hunk = None
    for l in body:
      if l.startswith("@@"):
        hunk = []
      elif hunk is not None:
        hunk.append(l)
      if hunk is not None and hunk and hunk[-1].startswith("@@"):
        pass
    # **⇒⇒† AND **A **SIMPLER **PASS**: **WALK **THE **BODY **AND **FIND **A **`-` **RUN
    # **THAT **IS **FLANKED **BY **NON-`-` **LINES**.
    for i, l in enumerate(body):
      if not l.startswith("-"): continue
      if l.startswith("---"): continue
      # **⇒⇒† AND **THE **RUN **OF **`-` **LINES**.
      j = i
      while j < len(body) and body[j].startswith("-") and not body[j].startswith("---"): j += 1
      before = body[i-1] if i > 0 else ""
      after = body[j] if j < len(body) else ""
      if before and after and not before.startswith("-") and not after.startswith("-"):
        if before.startswith("+") or after.startswith("+") or (before.startswith(" ") and after.startswith(" ")):
          hits.append((cid, before[1:].strip(), after[1:].strip(), [x[1:].strip() for x in body[i:j]]))
      i = j
  return hits

only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    hits = fragments(rel, "tinybendygrad/" + rel)
    if not hits: continue
    # **⇒⇒† AND **THE **SURVIVING **NEIGHBOURS **ARE **NOW **ADJACENT **IN **THE **FILE**.
    texts = [l.strip().lstrip("#").strip() for l in blk]
    for cid, before, after, cut in hits:
        b, a = before.lstrip("#").strip(), after.lstrip("#").strip()
        for i in range(len(texts)-1):
            if texts[i] == b and texts[i+1] == a:
                print(f"{rel}:{ln+i}  CUT {len(cut)} LINE(S) BETWEEN:")
                print(f"{'':>{len(rel)+4}}  BEFORE: {b[:110]}")
                for c in cut: print(f"{'':>{len(rel)+4}}    CUT: {c[:110]}")
                print(f"{'':>{len(rel)+4}}  AFTER:  {a[:110]}")
                print(f"{'':>{len(rel)+4}}  FROM: {cid[:10]}")
                break
