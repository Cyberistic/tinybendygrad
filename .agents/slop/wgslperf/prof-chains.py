#!/usr/bin/env python3
"""**THE **CALL **CHAINS **OF **A **FUNCTION's **SAMPLES**, **FROM **A **V8 **CPU **PROFILE.**

**WHY.** THE PROFILE's CALL TREE KNOWS WHO CALLED WHOM, AND THE TREE's OWN RULE IS THAT A COUNT
WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A MEASUREMENT. THIS READS THE CHAINS FROM THE
PROFILE's OWN TREE, SO IT SAYS WHICH CALL SITE OWNS THE COST.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/prof-chains.py <SUBSTRING> [TOPN]`
"""

import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
  want = sys.argv[1]
  topn = int(sys.argv[2]) if len(sys.argv) > 2 else 20
  profs = sorted((HERE / "prof").glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile in .agents/slop/wgslperf/prof")
  P = json.loads(profs[-1].read_text())
  byid = {x["id"]: x for x in P["nodes"]}
  par = {}
  for x in byid.values():
    for c in x.get("children", []):
      par[c] = x["id"]
  hit = collections.Counter(P["samples"])
  total = sum(hit.values())

  def nm(nid):
    return byid[nid]["callFrame"].get("functionName") or "(anonymous)"

  chains = collections.Counter()
  mine = 0
  for nid, c in hit.items():
    if want not in nm(nid):
      continue
    mine += c
    parts = []
    depth = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    p = par.get(nid)
    while p is not None and len(parts) < depth:
      parts.append(nm(p))
      p = par.get(p)
    chains[" <- ".join(parts)] += c
  print(f"THE PROFILE: {profs[-1].name}  ({total:,} samples)")
  print(f"THE SAMPLES ON `{want}`: {mine:,}  ({100.0*mine/total:.1f}%)")
  for ch, c in chains.most_common(topn):
    if c < 3:
      break
    print(f"  {c:6,}  {100.0*c/total:5.1f}%  {ch}")


if __name__ == "__main__":
  main()
