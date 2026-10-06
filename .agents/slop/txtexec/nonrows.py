import csv, os
plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))
print("=== non-rowdump rows ===")
for r in plan:
    if r["cls"] != "rowdump":
        sz = os.path.getsize(r["path"]) if os.path.exists(r["path"]) else -1
        print(f"{r['path']}\tcls={r['cls']}\tprobe={r['probe']}\tbytes={sz}\tplan_new={r['new_path']}")

print()
print("all new_path non-.rows:", sum(1 for r in plan if not r["new_path"].endswith(".rows")))
print("new_path == path[:-4]+'.rows' for all:",
      all(r["new_path"] == r["path"][:-4] + ".rows" for r in plan))
