import csv, os
from collections import Counter, defaultdict

plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))

# ext distribution by class
by_cls = defaultdict(Counter)
for r in plan:
    ext = os.path.splitext(r["new_path"])[1]
    by_cls[r["cls"]][ext] += 1
for cls, c in sorted(by_cls.items()):
    print(cls, dict(c))

print()
# non-.rows targets, full detail
for r in plan:
    if os.path.splitext(r["new_path"])[1] != ".rows":
        print(f"{r['path']}\t{r['cls']}\tprobe={r['probe']}\treach={r['reach']}\t-> {r['new_path']}")

print()
print("=== LIVE readers ===")
for r in plan:
    if r["reach"] == "LIVE":
        print(r["path"], "->", r["new_path"])
        print("  readers:", r["readers"])
print()
print("=== STALE readers ===")
for r in plan:
    if r["reach"] == "STALE":
        print(r["path"], "->", r["new_path"])
        print("  readers:", r["readers"])
