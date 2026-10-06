#!/usr/bin/env python3
"""The population BEFORE the rename, discovered from the pre-rename tree.

The working-tree walk returns 1 today (the rename landed). The pre-rename population is a
directory walk of commit b504abf77's `oracles/` tree -- 4d0a2b258^, the last commit holding
the `.txt` names. Compared against PLAN.tsv, which was written against that tree.
"""
import csv
import subprocess

PRE = "b504abf77"
out = subprocess.run(["git", "ls-tree", "-r", "--name-only", PRE, "--", "oracles"],
                     capture_output=True, text=True).stdout.split("\n")
walked = sorted(p for p in out if p.endswith(".txt"))
plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))
plan_paths = sorted(r["path"] for r in plan)

print(f"ref: {PRE} (4d0a2b258^)")
print("walked (.txt under oracles):", len(walked))
print("plan:", len(plan_paths))
print("set equal:", set(walked) == set(plan_paths))
print("only in walk:", sorted(set(walked) - set(plan_paths)))
print("only in plan:", sorted(set(plan_paths) - set(walked))[:10])
from collections import Counter
print("classes:", dict(Counter(r["cls"] for r in plan)))
print("reach:", dict(Counter(r["reach"] for r in plan)))
