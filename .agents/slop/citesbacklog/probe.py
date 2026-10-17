#!/usr/bin/env python3
"""Why did two needles full of parentheses reach `text`?  Ask the INSTRUMENT's own
`lane_bcd` + `needle_kind`, not a reimplementation of them.

usage: probe.py FILE:LINE [FILE:LINE ...]
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cites", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

for arg in sys.argv[1:]:
    rel, _, num = arg.rpartition(":")
    lines = cc.prose(rel, (ROOT / rel).read_text(errors="replace"))
    claims, _ = cc.lane_bcd(rel, lines)
    for c in claims:
        if str(c.get("at")) != num:
            continue
        print(f"--- {arg} lane={c['lane']}")
        for k in ("subject", "needle", "gap", "num", "unit", "delta", "anchor", "line_text"):
            if k in c:
                print(f"    {k:10} = {c[k]!r}")
        if "needle" in c:
            print(f"    {'KIND':10} = {cc.needle_kind(c['needle'], c.get('gap',''), c.get('line_text',''))!r}")