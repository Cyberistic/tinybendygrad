#!/usr/bin/env python3
"""**THE **EXCLUSIVE **TIME **PER **FUNCTION **NAME**, **AGGREGATED**, **FROM **A **V8 **CPU
**PROFILE.**

**WHY.** V8's PROFILE HAS ONE NODE PER CALL SITE, SO A HOT FUNCTION APPEARS AS MANY ROWS; THE
AGGREGATION IS THE READING. THE TREE's OWN RULE: A COUNT WITHOUT THE COMMAND THAT PRODUCED IT IS
NOT A MEASUREMENT.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/prof-agg.py [N]`
"""

import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
  n = int(sys.argv[1]) if len(sys.argv) > 1 else 30
  profs = sorted((HERE / "prof").glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile in .agents/slop/wgslperf/prof")
  P = json.loads(profs[-1].read_text())
  byid = {x["id"]: x for x in P["nodes"]}
  hit = collections.Counter(P["samples"])
  total = sum(hit.values())
  agg = collections.Counter()
  for nid, c in hit.items():
    x = byid.get(nid)
    if not x:
      continue
    cf = x["callFrame"]
    name = cf.get("functionName") or "(anonymous)"
    url = (cf.get("url") or "").split("/")[-1]
    agg[(name, url)] += c
  print(f"THE PROFILE: {profs[-1].name}  ({total:,} samples)")
  print("THE EXCLUSIVE TIME, AGGREGATED BY FUNCTION NAME:")
  for (name, url), c in agg.most_common(n):
    if c < 3:
      break
    print(f"  {c:7,}  {100.0*c/total:5.1f}%  {name}  [{url}]")


if __name__ == "__main__":
  main()
