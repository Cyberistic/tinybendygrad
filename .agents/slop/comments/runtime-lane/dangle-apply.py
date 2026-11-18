#!/usr/bin/env python3
"""**APPLY **THE **RECOVERED **TAILS** -- **⇒⇒† AND **IT **NEVER **REWRITES **A **KEPT
**LINE**, **⇒⇒† AND **IT **ONLY **INSERTS **THE **MISSING **LINE**."""
import importlib.util, pathlib, sys, collections
ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT/".agents/slop/comments/runtime-lane"))
import dangle_repair as dr
byfile = collections.defaultdict(list)
for rel, ln, txt in dr.dangles(): byfile[rel].append((ln, txt))
for rel, items in sorted(byfile.items()):
  path = ROOT/"tinybendygrad"/rel
  lines = path.read_text().split("\n")
  n = 0
  for ln, txt in sorted(items, key=lambda x: -x[0]):
    cid, tail = dr.tail_for(rel, txt)
    if not tail: continue
    idx = ln - 1
    if idx >= len(lines) or lines[idx].strip() != txt.strip():
      print(f"SKIP (moved) {rel}:{ln}"); continue
    lines.insert(idx + 1, tail)
    n += 1
  if n:
    path.write_text("\n".join(lines))
    print(f"{rel}: {n} tail(s) restored")
