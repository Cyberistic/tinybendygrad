#!/usr/bin/env python3
"""resid2.py -- price the remaining `needle_kind` candidates, with the PASSes each silences named.

usage: .venv/bin/python .agents/slop/residual/resid2.py
"""
import importlib.util
import re
import warnings
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

ORIG = cc.needle_kind


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") if c.get("needle") is not None else f"#{c.get('num')}")


def run():
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    return [cc.judge(c) for c in cc.census(cc.committed())[0]]


def wrap(extra):
  def f(needle, gap="", line=""):
    if extra(needle, gap, line):
      return "text-refused"
    return ORIG(needle, gap, line)
  return f


CELL = re.compile(r"[A-Za-z]+(?:-[A-Za-z]+)*")
CAND = {
  "cell-label accepts hyphen": lambda n, g, l: (
      ORIG(n, g, l) == "text" and l.lstrip().startswith("|") and CELL.fullmatch(n.strip("*… "))
      and not any(c.isdigit() for c in n)),
  "OUTPUT reads the LINE not the gap": lambda n, g, l: bool(cc.OUTPUT.search(l))
      and ORIG(n, g, l) == "text",
  "DELTA verb anywhere on the line": lambda n, g, l: bool(cc.DELTA.search(l))
      and ORIG(n, g, l) == "text",
  "dotted-qualified name": lambda n, g, l: bool(re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+",
                                                              n.strip("*… ")))
      and ORIG(n, g, l) == "text",
  "shape: ellipsis / {n} / file:line": lambda n, g, l: bool(
      re.search(r"…|\{\w+\}$|^[A-Za-z_]\w*:[A-Za-z_]\w*$", n.strip("*… ")))
      and ORIG(n, g, l) == "text",
}

base = run()
b = defaultdict(Counter)
for c in base:
  b[key(c)][c.get("verdict")] += 1
bp = Counter(c.get("verdict") for c in base)
print(f"BASELINE: rows={len(base)} PASS={bp[cc.PASS]} FAIL={bp[cc.FAIL]} "
      f"REFUSED={bp[cc.REFUSED]} SKIP={bp[cc.SKIP]}")
print()
for label, extra in CAND.items():
  cc.needle_kind = wrap(extra)
  var = run()
  cc.needle_kind = ORIG
  v = defaultdict(Counter)
  for c in var:
    v[key(c)][c.get("verdict")] += 1
  keys = set(b) | set(v)
  retired = sum(max(0, b[k][cc.FAIL] - v[k][cc.FAIL]) for k in keys)
  silenced = sum(max(0, b[k][cc.PASS] - v[k][cc.PASS]) for k in keys)
  gained_f = sum(max(0, v[k][cc.FAIL] - b[k][cc.FAIL]) for k in keys)
  vp = Counter(c.get("verdict") for c in var)
  print(f"{label:36s} FAIL {bp[cc.FAIL]}->{vp[cc.FAIL]} N={retired} "
        f"(+{gained_f} new) | PASS {bp[cc.PASS]}->{vp[cc.PASS]} M={silenced} | "
        f"{'REFUTED' if silenced > retired else 'numerically passes'}")
  for k in sorted(keys, key=str):
    if b[k][cc.PASS] > v[k][cc.PASS]:
      print(f"      SILENCED-PASS {k[1]}:{k[2]} {k[3]} {k[4]!r}")
