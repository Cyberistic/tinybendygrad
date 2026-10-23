#!/usr/bin/env python3
"""Probe specific citations named in the task."""
import json
from pathlib import Path
HERE = Path(__file__).resolve().parent
rows = json.loads((HERE / "classified.json").read_text())
want = [
 ("tinybendygrad/codegen/decomp/dtype.bend", 73),
 ("tinybendygrad/codegen/decomp/dtype.bend", 99),
 ("tinybendygrad/codegen/decomp/dtype.bend", 138),
 ("tinybendygrad/codegen/decomp/dtype.bend", 150),
 ("tinybendygrad/codegen/__init__.bend", 40),
]
for rel, at in want:
    for r in rows:
        if r["rel"] == rel and r["at"] == at:
            print(f"--- {rel}:{at}  subject={r['subject']} path={r['path']} lo={r['lo']} hi={r['hi']}")
            print(f"    toks={r['toks']} present={ {t:v for t,v in r['present'].items()} }")
            print(f"    old at_pin={r['old']['at_pin']} newest={r['old']['newest'][:12]}")
            print(f"    new at_pin={r['new']['at_pin']} newest={r['new']['newest'][:12]}")
            print(f"    line: {r['line'][:170]}")
