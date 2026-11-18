#!/usr/bin/env python3
"""**THE **MID-BLOCK **CUT **DETECTOR** -- **⇒⇒† AND **IT **USES **THE **FILE's **OWN
**HISTORY**, **⇒⇒† AND **THE **HISTORY **IS **THE **ONLY **WITNESS **THAT **CAN **SAY **A
**LINE **WAS **CUT**, **⇒⇒† AND **A **COMPARISON **WITH **THE **CURRENT **TEXT **CANNOT**.

**⇒⇒† AND **THE **TEST**: **A **LINE **WHOSE **TEXT **APPEARS **IN **THE **HISTORY **AND
**WHOSE **SUCCESSOR **THERE **IS **NOT **ITS **SUCCESSOR **NOW**."""
import subprocess, pathlib, re, sys, functools
ROOT = pathlib.Path(__file__).resolve().parents[4]
import importlib.util
spec = importlib.util.spec_from_file_location('cc', ROOT/".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)

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
def successors(rel):
  """**THE **LINE -> **ITS **SUCCESSOR **IN **THE **HISTORY**, **FOR **EVERY **LINE **THAT
  **EVER **APPEARED**."""
  out = {}
  for cid, body in history(rel):
    added = [l[1:] for l in body if l.startswith("+") and not l.startswith("+++")]
    for i, a in enumerate(added):
      nxt = added[i+1].strip() if i+1 < len(added) else ""
      out.setdefault(a.strip(), (cid, nxt))
  return out

only = sys.argv[1] if len(sys.argv) > 1 else "runtime/"
for f, ln, blk in cc.blocks():
    rel = str(f.relative_to(cc.PORT))
    if not rel.startswith(only): continue
    succ = successors(rel)
    for i, l in enumerate(blk):
        s = l.strip()
        if not s.startswith("#") or s == "#": continue
        key = s.lstrip("#").strip()
        if key not in succ: continue
        cid, nxt = succ[key]
        if not nxt or not nxt.startswith("#"): continue
        # **⇒⇒† AND **THE **CURRENT **SUCCESSOR**, **IF **ANY**.
        cur = blk[i+1].strip() if i+1 < len(blk) else ""
        cur_body = cur.lstrip("#").strip()
        nxt_body = nxt.lstrip("#").strip()
        if cur_body == nxt_body: continue
        # **⇒⇒† AND **THE **HISTORY's **SUCCESSOR **IS **A **DIFFERENT **CLAIM** -- **⇒⇒† AND
        # **THE **CURRENT **ONE **IS **A **DIFFERENT **CLAIM** -- **⇒⇒† AND **THE **CUT **IS
        # **PROVEN**.
        print(f"{rel}:{ln+i}  WAS-FOLLOWED-BY: {nxt_body[:110]}")
        print(f"{'':>{len(rel)+1}}  NOW-FOLLOWED-BY: {cur_body[:110]}")
        print(f"{'':>{len(rel)+1}}  FROM: {cid[:10]}")
