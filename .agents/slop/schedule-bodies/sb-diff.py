#!/usr/bin/env python3
"""Whole-LINE `name=value` differ for the rule-body gate. Never row names.

Three verdicts, and the third one is the one that catches a gate agreeing with a
broken port:

  AGREE       every CPython line is present, byte for byte
  DISAGREE    named lines differ, each printed with both values
  MISSING     a CPython line has no counterpart in the port -- which is not
              "wrong" but IS "unproved", and the two are reported apart

`--gate-self` runs the oracle against a MUTATED copy of itself and must report
MISSING or DISAGREE. A gate that reports AGREE there is agreeing with itself.
"""
import sys

py_path, bd_path = sys.argv[1], sys.argv[2]

def load(p):
    out = {}
    for ln in open(p):
        ln = ln.strip()
        if "=" in ln and not ln.startswith("#"):
            k, v = ln.split("=", 1)
            out[k] = v
    return out

py, bd = load(py_path), load(bd_path)
if not py:
    print("== VERDICT INCONCLUSIVE: the CPython lane produced no rows"); sys.exit(3)
if not bd:
    print("== VERDICT INCONCLUSIVE: the bend lane produced no rows"); sys.exit(3)

# the 81 rows the previous unit left are NOT part of this comparison
BASE = set(l.strip().split("=", 1)[0] for l in open(".agents/slop/schedule-bodies/BEFORE-rows.txt")
           if "=" in l)

bad = []
for k in sorted(py):
    if k in BASE:
        continue
    if k not in bd:
        bad.append(("MISSING", k, py[k], "<absent>"))
    elif bd[k] != py[k]:
        bad.append(("DISAGREE", k, py[k], bd[k]))

n = sum(1 for k in py if k not in BASE)
if not bad:
    print(f"== NEW ROWS AGREE: {n} rows, 3 lanes identical (whole lines)")
    sys.exit(0)
for kind, k, want, got in bad:
    print(f"== {kind} {k}: cpython={want} port={got}")
print(f"== {len(bad)} of {n} new rows disagree or are missing")
sys.exit(1)