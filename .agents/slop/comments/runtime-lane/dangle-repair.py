#!/usr/bin/env python3
"""**THE **DANGLING-SENTENCE **REPAIR** -- **RESTORE **THE **MISSING **TAIL **OF **EVERY
**CUT **SENTENCE**, **⇒⇒† AND **THE **TAIL **COMES **FROM **THE **FILE's **OWN **HISTORY**,
**⇒⇒† AND **THE **COMMIT **THAT **CUT **IT **IS **NAMED**.

**⇒⇒† AND **IT **NEVER **WRITES** -- **⇒⇒† AND **IT **PRINTS **THE **TAIL**, **⇒⇒† AND **A
**HUMAN **APPLIES **IT**."""
import subprocess, pathlib, re, sys, collections, functools
ROOT = pathlib.Path(__file__).resolve().parents[4]
import importlib.util
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
CONT = re.compile(r"[.!?:,]\s*$|[\)\]\}`'\"_]\s*$|\b(AND|OR|BUT|THE|A|AN|OF|TO|FOR|WITH|IS|WAS|THAT|IT)\s*$", re.I)

def dangles():
  out = []
  for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith("runtime/"): continue
    if len(blk) < 2: continue
    if sum(1 for l in blk if l.strip().startswith("# |")) >= 3: continue
    if any(l.strip().startswith("# ---") for l in blk): continue
    last = blk[-1].strip(); body = last.lstrip("#").strip()
    if not body or CONT.search(body): continue
    out.append((rel, ln + len(blk) - 1, blk[-1]))
  return out

@functools.lru_cache(maxsize=None)
def history(rel):
  path = "tinybendygrad/" + rel
  d = subprocess.run(["git","log","-p","--format=@@@%H","--",path], cwd=ROOT, capture_output=True, text=True).stdout
  commits, cur = [], None
  for line in d.split("\n"):
    if line.startswith("@@@"):
      cur = [line[3:], []]; commits.append(cur)
    elif cur is not None: cur[1].append(line)
  commits.reverse()
  return commits

@functools.lru_cache(maxsize=None)
def tail_for(rel, txt):
  """**THE **MISSING **TAIL **OF **THE **SENTENCE**, **FROM **THE **FILE's **OWN **HISTORY**."""
  for cid, body in history(rel):
    added = [l[1:] for l in body if l.startswith("+") and not l.startswith("+++")]
    for i, a in enumerate(added):
      if a.strip() == txt.strip():
        if i+1 < len(added):
          nxt = added[i+1]
          if nxt.strip().startswith("#"): return cid, nxt
        return cid, None
  return None, None

if __name__ == "__main__":
  for rel, ln, line in dangles():
    cid, tail = tail_for(rel, line)
    print(f"{rel}:{ln}")
    print(f"    LINE: {line.strip()[:150]}")
    if tail:
      print(f"    TAIL: {tail.strip()[:150]}")
      print(f"    FROM: {cid[:10]}")
    else:
      print("    NO TAIL FOUND")
    print()
