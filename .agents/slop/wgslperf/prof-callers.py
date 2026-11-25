#!/usr/bin/env python3
"""**THE **CALLERS **OF **A **FUNCTION**, **FROM **A **V8 **CPU **PROFILE.**

**WHY.** THE PROFILE HAS THE CALL TREE: EVERY NODE HAS A `children` ARRAY, SO THE SAMPLES THAT
LANDED ON A FUNCTION CAN BE ATTRIBUTED TO THE FUNCTION THAT CALLED IT. THE AGGREGATED PROFILE
SAYS `List.append` IS 18.6% OF THE TURN, AND AN APPEND IS O(n) IN THE LIST IT COPIES -- SO THE
CALLER MATTERS, AND THE PROFILE ALREADY KNOWS IT.

**THE **READING.** A NODE'S PARENT IS FOUND BY WALKING THE TREE FROM THE ROOT, AND THE SAMPLES
ARE ATTRIBUTED TO THE NEAREST ANCESTOR THAT MATCHES THE NAME ASKED FOR.
"""

import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
  want = sys.argv[1] if len(sys.argv) > 1 else "List_append"
  profs = sorted((HERE / "prof").glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile in .agents/slop/wgslperf/prof")
  P = json.loads(profs[-1].read_text())
  byid = {n["id"]: n for n in P["nodes"]}
  parent = {}
  for n in P["nodes"]:
    for c in n.get("children", []):
      parent[c] = n["id"]
  hit = collections.Counter(P["samples"])
  total = sum(hit.values())

  # THE CALLER OF A SAMPLE IS THE NEAREST STRICT ANCESTOR WHOSE NAME MATCHES.
  callers = collections.Counter()
  mine = 0
  for nid, c in hit.items():
    n = byid.get(nid)
    if not n:
      continue
    name = n["callFrame"].get("functionName") or "(anonymous)"
    if want not in name:
      continue
    mine += c
    p = parent.get(nid)
    who = "(the root)"
    while p is not None:
      pn = byid.get(p)
      if pn is None:
        break
      pname = pn["callFrame"].get("functionName") or "(anonymous)"
      if want not in pname:
        who = pname
        break
      p = parent.get(p)
    callers[who] += c
  print(f"THE PROFILE: {profs[-1].name}  ({total:,} samples)")
  print(f"THE SAMPLES ON `{want}`: {mine:,}  ({100.0*mine/total:.1f}%)")
  print("THE CALLERS:")
  for who, c in callers.most_common(18):
    if c < 2:
      break
    print(f"  {c:6,}  {100.0*c/total:5.1f}%  {who}")


if __name__ == "__main__":
  main()
