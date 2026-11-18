#!/usr/bin/env python3
"""**THE **RULE **REPLAY** -- **WHAT **THE **RULE **WOULD **DO **TO **A **GIVEN **REVISION**, **WITHOUT
**WRITING **ANYTHING**, **⇒⇒† AND **IT **REPORTS **THE **CUT **AND **THE **MARKERS **THAT **DIED**.

**⇒⇒† AND **THE **MARKERS **ARE **THE **RULE's **EVIDENCE**, **⇒⇒† AND **A **CUT **THAT **DROPS **THE
**EVIDENCE **IS **NOT **A **CUT**."""

import importlib.util
import pathlib
import subprocess
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("go", HERE / "gen-ops.py")
go = importlib.util.module_from_spec(spec)
spec.loader.exec_module(go)
spec2 = importlib.util.spec_from_file_location("cc", HERE / "comment-census.py")
cc = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(cc)

FILES = ["__init__", "divandmod", "f32_repr", "fold", "movement", "ops",
         "render", "spec", "symbolic", "upat", "validate", "weak"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "5de8a84f8"


def cut(text):
  lines = text.split("\n")
  out = []
  i = 0
  while i < len(lines):
    if lines[i].strip().startswith("#"):
      j = i
      while j < len(lines) and lines[j].strip().startswith("#"):
        j += 1
      out.extend(go.block_keep(lines[i:j]))
      i = j
    else:
      out.append(lines[i])
      i += 1
  return "\n".join(out)


def markers(text):
  cites, meas, diff = set(), set(), set()
  for l in text.split("\n"):
    s = l.strip().lstrip("#").strip()
    if not s:
      continue
    if cc.DIFFERENCE.search(s):
      diff.add(s)
    if cc.CITE.search(s):
      cites.add(s)
    if cc.MEASURED.search(s):
      meas.add(s)
  return cites, meas, diff


def main():
  tb = ta = 0
  lc = lm = ld = 0
  bb = ab = 0
  print(f"{'FILE':14s} {'BASE-L':>7s} {'NEW-L':>7s} {'CUT%':>6s} {'cite-':>6s} {'meas-':>6s} {'diff-':>6s}")
  for n in FILES:
    before = subprocess.run(["git", "show", f"{BASE}:tinybendygrad/uop/{n}.bend"],
                            capture_output=True, text=True, check=True).stdout
    after = cut(before)
    bc, bm, bd = markers(before)
    ac, am, ad = markers(after)
    bl = sum(1 for l in before.split("\n") if l.strip().startswith("#"))
    al = sum(1 for l in after.split("\n") if l.strip().startswith("#"))
    lc += len(bc - ac)
    lm += len(bm - am)
    ld += len(bd - ad)
    tb += bl
    ta += al
    print(f"{n:14s} {bl:7d} {al:7d} {100*(bl-al)/bl:5.1f}% {len(bc-ac):6d} {len(bm-am):6d} {len(bd-ad):6d}")
  print(f"{'ALL':14s} {tb:7d} {ta:7d} {100*(tb-ta)/tb:5.1f}% {lc:6d} {lm:6d} {ld:6d}")


if __name__ == "__main__":
  main()
