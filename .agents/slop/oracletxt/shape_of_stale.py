#!/usr/bin/env python3
"""Re-derive the STALE/ABSENT split over the RECORDED pre-rename population, from the census's own
rule. Reads `.agents/slop/oracles259/census.json` (259 rows, the census output before the rename)
and imports `shared_tail` from `checks/oracle-txt-census.py` BY PATH -- one definition, not a copy.

Reports both the reader-token split and the file-level verdict split, so the correction to the old
STALE count is a measurement and not a claim.
"""
from __future__ import annotations

import collections
import importlib.util
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)

rows = json.loads((ROOT / ".agents/slop/oracles259/census.json").read_text())

tok = collections.Counter()
files = collections.Counter()
for r in rows:
    moved = [t for t in r.get("stale", []) if C.shared_tail(t[1], r["path"]) >= 2]
    names = [t for t in r.get("stale", []) if C.shared_tail(t[1], r["path"]) < 2]
    tok["moved"] += len(moved)
    tok["namesake"] += len(names)
    if r.get("live") or r.get("shadow"):
        files["live-shadow"] += 1
    elif moved:
        files["stale"] += 1
    elif names:
        files["absent"] += 1

print(f"population: {len(rows)} `.txt` (pre-rename, committed census.json)")
print(f"reader tokens with an ABSENT path: {tok['moved'] + tok['namesake']}")
print(f"  moved (sub-tree survived)  STALE  : {tok['moved']}")
print(f"  basename-only (namesake)   ABSENT : {tok['namesake']}")
print("files, by verdict (LIVE/SHADOW dominate):")
print(f"  STALE  (a moved read, no live) : {files['stale']}")
print(f"  ABSENT (a namesake only)       : {files['absent']}")
print(f"  LIVE/SHADOW (outrank both)     : {files['live-shadow']}")
