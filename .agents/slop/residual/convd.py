#!/usr/bin/env python3
"""convd.py -- price a lane-D guard: a number that matches `wc -l` and not `splitlines()`
on a file with no trailing newline is a CONVENTION mismatch, so REFUSE it instead of FAIL.

N = FAIL rows retired   M = PASS rows silenced (0 by construction: widening cannot
remove a PASS, so the row that matters is how many are RETIRED and whether any new FAIL
appears).

usage: .venv/bin/python .agents/slop/residual/convd.py
"""
import importlib.util
import warnings
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

ORIG = cc.judge
TEXT: dict[str, str | None] = {}
REAL_READ = cc.read


def read(rel):
  t = REAL_READ(rel)
  TEXT[rel] = t
  return t


def judge(c):
  r = ORIG(c)
  if c["lane"] != "D" or r.get("verdict") != cc.FAIL:
    return r
  t = TEXT.get(c["subject"])
  if t and not t.endswith("\n") and t.count("\n") == c["num"]:
    return {**r, "verdict": cc.REFUSED, "needle_kind": "wc-l-convention",
            "evidence": f"{c['subject']}: {c['num']} is the NEWLINE count and "
                        f"{len(t.splitlines())} is the line count (no trailing newline)"}
  return r


def run():
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    return [cc.judge(c) for c in cc.census(cc.committed())[0]]


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") if c.get("needle") is not None else f"#{c.get('num')}")


base = run()
cc.read, cc.judge = read, judge
var = run()
b = Counter(c["verdict"] for c in base)
v = Counter(c["verdict"] for c in var)
B, V = {}, {}
for c in base:
  B.setdefault(key(c), Counter())[c["verdict"]] += 1
for c in var:
  V.setdefault(key(c), Counter())[c["verdict"]] += 1
keys = set(B) | set(V)
retired = sum(max(0, B.get(k, Counter())[cc.FAIL] - V.get(k, Counter())[cc.FAIL]) for k in keys)
silenced = sum(max(0, B.get(k, Counter())[cc.PASS] - V.get(k, Counter())[cc.PASS]) for k in keys)
print(f"BASELINE PASS={b[cc.PASS]} FAIL={b[cc.FAIL]} REFUSED={b[cc.REFUSED]} SKIP={b[cc.SKIP]}")
print(f"VARIANT  PASS={v[cc.PASS]} FAIL={v[cc.FAIL]} REFUSED={v[cc.REFUSED]} SKIP={v[cc.SKIP]}")
print(f"N (FAIL retired) = {retired}   M (PASS silenced) = {silenced}")
for k in sorted(keys, key=str):
  if B.get(k, Counter())[cc.FAIL] > V.get(k, Counter())[cc.FAIL]:
    print(f"  RETIRED  {k[0]} {k[1]}:{k[2]} {k[3]} #{k[4]}")

