import os, csv, sys

ROOT = "."
ORACLES = "oracles"

walked = []
for dirpath, dirnames, filenames in os.walk(ORACLES):
    for fn in filenames:
        if fn.endswith(".txt"):
            walked.append(os.path.join(dirpath, fn))
walked.sort()

plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))
plan_paths = sorted(r["path"] for r in plan)

print("walked:", len(walked))
print("plan:", len(plan_paths))
print("set equal:", set(walked) == set(plan_paths))
only_walk = sorted(set(walked) - set(plan_paths))
only_plan = sorted(set(plan_paths) - set(walked))
print("only in walk:", len(only_walk), only_walk[:10])
print("only in plan:", len(only_plan), only_plan[:10])

from collections import Counter
print("classes:", Counter(r["cls"] for r in plan))
print("probe:", Counter(r["probe"] for r in plan))
print("reach:", Counter(r["reach"] for r in plan))
# new paths
nps = [r["new_path"] for r in plan]
print("new_path dups:", [p for p, c in Counter(nps).items() if c > 1])
print("new_path == old (unchanged):", [r["path"] for r in plan if r["new_path"] == r["path"]])
