#!/usr/bin/env python3
"""**THE **INCLUSIVE **TIME **OF **A **FUNCTION **AND **THE **EXCLUSIVE **BREAKDOWN **UNDER
**IT**, **FROM **A **V8 **CPU **PROFILE.**

**WHY.** THE TREE's OWN RULE: A COUNT WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT.
THE INSTRUMENTED CLOCKS (`profile-wgsl.py`) ARE INCLUSIVE AND COUNT A NESTED CALL TWICE, SO THIS
READS V8's OWN PROFILE's CALL TREE: A NODE'S SUBTREE IS ITS INCLUSIVE TIME, AND A NODE's OWN
SAMPLES ARE ITS EXCLUSIVE TIME.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/prof-incl.py <SUBSTRING> [TOPN]`

**THE **OUTPUT.** THE INCLUSIVE SHARE OF EVERY FUNCTION WHOSE NAME MATCHES, AND THE EXCLUSIVE
BREAKDOWN OF THE SUBTREE OF THE FIRST MATCH (THE OUTERMOST).
"""

import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
  want = sys.argv[1]
  topn = int(sys.argv[2]) if len(sys.argv) > 2 else 24
  profs = sorted((HERE / "prof").glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile in .agents/slop/wgslperf/prof")
  P = json.loads(profs[-1].read_text())
  byid = {x["id"]: x for x in P["nodes"]}
  hit = collections.Counter(P["samples"])
  total = sum(hit.values())

  def name(nid):
    cf = byid[nid]["callFrame"]
    return cf.get("functionName") or "(anonymous)"

  # THE SUBTREE SUM: THE NODE's OWN SAMPLES PLUS EVERY DESCENDANT's.
  def subtree(nid, memo={}):
    if nid in memo:
      return memo[nid]
    s = hit.get(nid, 0)
    for c in byid[nid].get("children", []):
      s += subtree(c)
    memo[nid] = s
    return s

  # THE MATCHING NODES, AND THE OUTERMOST ONE (A MATCH WITH NO MATCHING ANCESTOR).
  matches = [nid for nid in byid if want in name(nid)]
  outer = []
  for nid in matches:
    p = byid[nid].get("parents")
    ok = True
    stack = [c for c in byid[nid].get("children", [])]
    # THE ANCESTORS ARE FOUND BY WALKING FROM THE ROOT.
    par = {}
    for x in byid:
      for c in byid[x].get("children", []):
        par[c] = x
    a = par.get(nid)
    while a is not None:
      if want in name(a):
        ok = False
        break
      a = par.get(a)
    if ok:
      outer.append(nid)

  print(f"THE PROFILE: {profs[-1].name}  ({total:,} samples)")
  print(f"THE MATCHES FOR `{want}`: {len(matches)} nodes, {len(outer)} outermost")
  agg = collections.Counter()
  for nid in matches:
    agg[name(nid)] += subtree(nid)
  for nm, c in agg.most_common(12):
    print(f"  INCL {c:7,}  {100.0*c/total:5.1f}%  {nm}")
  if not outer:
    return
  root = max(outer, key=subtree)
  print(f"THE OUTERMOST MATCH: {name(root)}  ({subtree(root):,} samples, {100.0*subtree(root)/total:.1f}%)")
  ex = collections.Counter()
  stack = [root]
  seen = set()
  while stack:
    nid = stack.pop()
    if nid in seen:
      continue
    seen.add(nid)
    ex[name(nid)] += hit.get(nid, 0)
    stack.extend(byid[nid].get("children", []))
  sub = sum(ex.values())
  print(f"THE EXCLUSIVE BREAKDOWN UNDER IT ({sub:,} samples):")
  for nm, c in ex.most_common(topn):
    if c < 3:
      break
    print(f"  {c:7,}  {100.0*c/total:5.1f}%  {nm}")


if __name__ == "__main__":
  main()
