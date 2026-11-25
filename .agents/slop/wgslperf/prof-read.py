#!/usr/bin/env python3
"""**THE **EXCLUSIVE **TIME **PER **FUNCTION**, **FROM **A **V8 **CPU **PROFILE.**

**WHY.** THE INSTRUMENTED CLOCKS (`hot-prof.py`) ARE INCLUSIVE, SO A NESTED CALL IS COUNTED
TWICE, AND THE FOLD's SHARE OF THE TURN CANNOT BE READ OFF THEM. V8's OWN PROFILE HAS THE
EXCLUSIVE TIME, AND THE PROFILE IS OF THE COMPILED FORM -- THE SAME FORM THE PAGE RUNS.

**THE **READING.** THE PROFILE'S `nodes` CARRY A `hitCount` AND THE `samples` ARRAY SAYS WHEN
THE PROFILER WAS LOOKING, SO THE SELF TIME OF A FUNCTION IS THE NUMBER OF SAMPLES WHOSE NODE
IS THAT FUNCTION. THE TREE's OWN RULE: A COUNT WITHOUT THE COMMAND THAT PRODUCED IT IS NOT A
MEASUREMENT, SO THE COMMAND IS IN THE DOCSTRING.
"""

import collections
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def main():
  profs = sorted((HERE / "prof").glob("*.cpuprofile"))
  if not profs:
    raise SystemExit("WARN: no profile in .agents/slop/wgslperf/prof")
  P = json.loads(profs[-1].read_text())
  byid = {n["id"]: n for n in P["nodes"]}
  hit = collections.Counter()
  for s in P["samples"]:
    hit[s] += 1
  # THE SELF TIME IS THE SAMPLES THAT LANDED ON THE NODE ITSELF.
  rows = []
  for nid, c in hit.items():
    n = byid.get(nid)
    if not n:
      continue
    cf = n["callFrame"]
    name = cf.get("functionName") or "(anonymous)"
    url = cf.get("url") or ""
    rows.append((c, name, url.split("/")[-1]))
  rows.sort(reverse=True)
  total = sum(c for c, _, _ in rows)
  print(f"THE PROFILE: {profs[-1].name}  ({total:,} samples)")
  print("THE EXCLUSIVE TIME:")
  for c, name, url in rows[:28]:
    if c < 3:
      break
    print(f"  {c:7,}  {100.0*c/total:5.1f}%  {name}  [{url}]")


if __name__ == "__main__":
  main()
