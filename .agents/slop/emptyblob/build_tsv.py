#!/usr/bin/env python3
"""Emit EMPTY.tsv (one row per HEAD-committed empty-blob path) from analysis.json."""
import json
import os
import csv

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
rows = json.load(open(os.path.join(REPO, ".agents/slop/emptyblob/analysis.json")))
out = os.path.join(REPO, ".agents/slop/emptyblob/EMPTY.tsv")
with open(out, "w", newline="") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["path", "blob", "on_disk_bytes", "class", "ever_nonempty",
                "reader_exact", "reader_basename_approx"])
    for r in sorted(rows, key=lambda r: (r["cls"], r["path"])):
        w.writerow([
            r["path"], r["blob"][:12], r["disk_bytes"], r["cls"],
            "yes" if r["ever_nonempty"] else "no",
            r.get("reader_exact", "-"), r.get("reader_approx", "-"),
        ])
print("wrote", out, len(rows), "rows")
