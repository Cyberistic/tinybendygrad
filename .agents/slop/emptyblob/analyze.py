#!/usr/bin/env python3
"""Final: per-path history (ever non-empty?) + readers + empty-set transitions."""
import subprocess, json, os
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"

def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True)

d = json.load(open(os.path.join(REPO, ".agents/slop/emptyblob/classified.json")))
head_empty = [r for r in d["rows"] if r["cls"] == "HEAD-EMPTY"]
paths = [r["path"] for r in head_empty]

def per_path(p):
    commits = [c for c in git("log", "HEAD", "--format=%H", "--", p).stdout.splitlines() if c]
    ever = False
    if commits:
        inp = "\n".join(f"{c}:{p}" for c in commits) + "\n"
        r = subprocess.run(["git", "-C", REPO, "cat-file", "--batch-check"],
                           input=inp, capture_output=True, text=True)
        for line in r.stdout.splitlines():
            # <sha> blob <size>
            parts = line.split()
            if len(parts) == 3 and parts[2].isdigit() and int(parts[2]) > 0:
                ever = True
                break
    # readers
    hits = []
    for needle in (p, os.path.basename(p)):
        g = git("grep", "-n", "-F", "-e", needle, "--", ".")
        for line in g.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) >= 2 and parts[0] != p:
                hits.append(f"{parts[0]}:{parts[1]}")
        if hits:
            break
    return p, ever, len(commits), sorted(set(hits))[:3]

with ThreadPoolExecutor(max_workers=12) as ex:
    results = list(ex.map(per_path, paths))
res = {p: (ever, nc, rd) for p, ever, nc, rd in results}

def classify(p, ev):
    base = os.path.basename(p)
    if ev:  # ever non-empty -> a truncation, WHATEVER its name. `__init__.py` is NOT exempt.
        return "TRUNCATED"
    if base in ("__init__.py", "py.typed", ".gitkeep"):
        return "INTENTIONAL"
    if base.startswith("empty.") and "/fixtures/" in p:
        return "INTENTIONAL"
    if "/plant" in p or "plant" in base:
        return "INTENTIONAL"
    if base.endswith((".err", ".out", ".stdout", ".stderr")):
        return "SENTINEL/UNKNOWN"
    return "UNCLASSIFIED"

rows = []
for p in paths:
    ev, nc, rd = res[p]
    rows.append({"path": p, "blob": EMPTY, "disk_bytes": 0, "cls": classify(p, ev),
                 "ever_nonempty": ev, "n_commits": nc, "readers": "; ".join(rd)})
print(json.dumps(Counter(r["cls"] for r in rows), indent=2))
print("ever_nonempty:", sum(1 for r in rows if r["ever_nonempty"]))
json.dump(rows, open(os.path.join(REPO, ".agents/slop/emptyblob/analysis.json"), "w"), indent=2)
for lab in ("TRUNCATED", "UNCLASSIFIED"):
    print(f"\n=== {lab} ===")
    for r in rows:
        if r["cls"] == lab:
            print(f"  {r['path']}  readers[{r['readers']}]")
