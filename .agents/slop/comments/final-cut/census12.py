#!/usr/bin/env python3
"""**THE **CENSUS **FOR **THE **TWELVE **FILES**, **BEFORE **AND **AFTER**, **PER **CLASS**.

**⇒⇒† AND **THE **BEFORE **IS **THE **BASE **COMMIT **`1c0ffde95`** (⇒⇒† AND **THE **COMMIT **I
**STARTED **FROM**), **⇒⇒† AND **THE **AFTER **IS **MY **FINAL **COMMIT **`84494174d`**.
"""
import importlib.util
import pathlib
import subprocess
import sys
from collections import Counter

ROOT = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
spec = importlib.util.spec_from_file_location("cc", ROOT / ".agents/slop/comments/comment-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

FILES = ["tensor.bend", "mixin/gradient.bend", "helpers.bend", "codegen/decomp/dtype.bend",
         "runtime/ops_python.bend", "schedule/rangeify.bend", "engine/realize.bend",
         "mixin/movement.bend", "schedule/__init__.bend", "mixin/op.bend", "schedule/multi.bend",
         "runtime/ops_metal.bend"]

BASE = "1c0ffde95"
AFTER = "84494174d"


def census(rev: str) -> dict:
  out = {}
  for f in FILES:
    text = subprocess.run(["git", "show", f"{rev}:tinybendygrad/{f}"],
                          capture_output=True, text=True, cwd=ROOT).stdout
    lines = text.split("\n")
    i = 0
    c = Counter()
    l = Counter()
    while i < len(lines):
      if lines[i].strip().startswith("#"):
        j = i
        while j < len(lines) and lines[j].strip().startswith("#"):
          j += 1
        v = cc.verdict(" ".join(lines[i:j]))
        c[v] += 1
        l[v] += j - i
        i = j
      else:
        i += 1
    out[f] = (c, l, sum(c.values()), sum(l.values()))
  return out


b = census(BASE)
a = census(AFTER)
print(f"THE BEFORE IS {BASE} AND THE AFTER IS {AFTER}.\n")
print(f"{'FILE':30s} {'BLOCKS':>17s} {'LINES':>19s}")
print(f"{'':30s} {'BEFORE':>8s} {'AFTER':>8s} {'BEFORE':>9s} {'AFTER':>9s}")
tb = ta = lb = la = 0
for f in FILES:
  cb, lcb, nb, nlb = b[f]
  ca, lca, na, nla = a[f]
  tb += nb
  ta += na
  lb += nlb
  la += nla
  print(f"{f:30s} {nb:8d} {na:8d} {nlb:9d} {nla:9d}")
print(f"{'TOTAL':30s} {tb:8d} {ta:8d} {lb:9d} {la:9d}   (THE CUT: {lb - la} LINES)")
print()
print("PER CLASS, and the KEEP SET is what the rule keeps:")
kbc = kac = kbl = kal = 0
for f in FILES:
  cb, lcb, _, _ = b[f]
  ca, lca, _, _ = a[f]
  print(f"{f}")
  for v in ("DIFFERENCE", "WEIRD", "MEASURED", "NARRATION"):
    print(f"   {v:12s} blocks {cb[v]:4d} -> {ca[v]:4d}   lines {lcb[v]:5d} -> {lca[v]:5d}")
    if v != "NARRATION":
      kbc += cb[v]
      kac += ca[v]
      kbl += lcb[v]
      kal += lca[v]
print()
print(f"THE KEEP SET (DIFFERENCE + WEIRD + MEASURED): blocks {kbc} -> {kac}, lines {kbl} -> {kal}")
print(f"THE NARRATION SET: blocks {tb - kbc} -> {ta - kac}, lines {lb - kbl} -> {la - kal}")
