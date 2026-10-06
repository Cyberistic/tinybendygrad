#!/usr/bin/env python3
"""Readers: EXACT (full path appears in another file) vs BASENAME-ONLY (may be a collision)."""
import subprocess, json, os, tempfile
from collections import defaultdict

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
rows = json.load(open(os.path.join(REPO, ".agents/slop/emptyblob/analysis.json")))
paths = [r["path"] for r in rows]

def grep_all(needles):
    with tempfile.NamedTemporaryFile("w", suffix=".pat", delete=False) as pf:
        pf.write("\n".join(sorted(set(needles))) + "\n")
        pat = pf.name
    out = subprocess.run(["git", "-C", REPO, "grep", "-n", "-F", "-f", pat, "--", "."],
                         capture_output=True, text=True).stdout
    os.unlink(pat)
    idx = defaultdict(list)
    for line in out.splitlines():
        parts = line.split(":", 2)
        if len(parts) >= 3:
            idx[parts[0]].append((parts[1], parts[2]))
    return idx

exact_idx = grep_all(paths)
base_idx = grep_all({os.path.basename(p) for p in paths})

def find(p, idx, needle):
    hits = []
    for f, lst in idx.items():
        if f == p:
            continue
        for ln, content in lst:
            if needle in content:
                hits.append(f"{f}:{ln}")
                break
        if len(hits) >= 3:
            break
    return sorted(hits)

for r in rows:
    p = r["path"]
    r["reader_exact"] = "; ".join(find(p, exact_idx, p)) or "-"
    r["reader_approx"] = "; ".join(find(p, base_idx, os.path.basename(p))) or "-"

json.dump(rows, open(os.path.join(REPO, ".agents/slop/emptyblob/analysis.json"), "w"), indent=2)
nx = sum(1 for r in rows if r["reader_exact"] != "-")
na = sum(1 for r in rows if r["reader_exact"] == "-" and r["reader_approx"] != "-")
nn = sum(1 for r in rows if r["reader_exact"] == "-" and r["reader_approx"] == "-")
print(f"exact-path reader: {nx}  basename-only(approx): {na}  no reader at all: {nn}  of {len(rows)}")
print("\nnotable exact readers:")
for r in rows:
    if r["reader_exact"] != "-":
        print(f"  {r['path']}  -> {r['reader_exact']}")
