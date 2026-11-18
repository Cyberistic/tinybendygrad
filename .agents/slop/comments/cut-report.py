#!/usr/bin/env python3
"""**THE **CUT's **REPORT** -- **THE **BEFORE/AFTER **CENSUS **OF **THE **`uop/` **FILES**, **AND **THE
**MARKERS **THAT **DIED**, **⇒⇒† AND **THE **MARKERS **ARE **THE **RULE's **EVIDENCE**, **⇒⇒† AND **A
**CUT **THAT **DROPS **THE **EVIDENCE **IS **NOT **A **CUT**.

**⇒⇒† AND **THE **BEFORE **IS **THE **BASE **`5de8a84f8`** (**THE **LAST **REVISION **BEFORE **ANY
**COMMENT **CUT**), **⇒⇒† AND **AND **THE **AFTER **IS **THE **WORKING **TREE**.
"""

import importlib.util
import pathlib
import subprocess
import sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("cc", HERE / "comment-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

FILES = ["__init__", "divandmod", "f32_repr", "fold", "movement", "ops",
         "render", "spec", "symbolic", "upat", "validate", "weak"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "5de8a84f8"


def census(lines):
  c, l = Counter(), Counter()
  i = 0
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
  return c, l


def markers(text):
  c, m, d = set(), set(), set()
  for l in text.split("\n"):
    s = l.strip().lstrip("#").strip()
    if not s:
      continue
    if cc.DIFFERENCE.search(s):
      d.add(s)
    if cc.CITE.search(s):
      c.add(s)
    if cc.MEASURED.search(s):
      m.add(s)
  return c, m, d


def main():
  tb = tl = tbk = tll = ab = al = abk = all_ = 0
  lc = lm = ld = 0
  print(f"{'FILE':16s} {'BASE-B':>7s} {'BASE-L':>7s} {'NOW-B':>7s} {'NOW-L':>7s} {'CUT%':>6s} "
        f"{'cites-':>7s} {'meas-':>6s} {'diff-':>6s}")
  for n in FILES:
    rel = f"tinybendygrad/uop/{n}.bend"
    before = subprocess.run(["git", "show", f"{BASE}:{rel}"], capture_output=True, text=True, check=True).stdout
    after = (ROOT / rel).read_text()
    _bc, bl = census(before.split("\n"))
    _ac, al2 = census(after.split("\n"))
    bls, als = sum(bl.values()), sum(al2.values())
    bc, bm, bd = markers(before)
    ac, am, ad = markers(after)
    lc += len(bc - ac)
    lm += len(bm - am)
    ld += len(bd - ad)
    tb += sum(_bc.values())
    tl += bls
    tbk += _bc["DIFFERENCE"] + _bc["WEIRD"] + _bc["MEASURED"]
    tll += bl["DIFFERENCE"] + bl["WEIRD"] + bl["MEASURED"]
    ab += sum(_ac.values())
    al += als
    abk += _ac["DIFFERENCE"] + _ac["WEIRD"] + _ac["MEASURED"]
    all_ += al2["DIFFERENCE"] + al2["WEIRD"] + al2["MEASURED"]
    print(f"{n:16s} {sum(_bc.values()):7d} {bls:7d} {sum(_ac.values()):7d} {als:7d} "
          f"{100*(bls-als)/bls:5.1f}% {len(bc-ac):7d} {len(bm-am):6d} {len(bd-ad):6d}")
  print(f"{'ALL':16s} {tb:7d} {tl:7d} {ab:7d} {al:7d} {100*(tl-al)/tl:5.1f}% "
        f"{lc:7d} {lm:6d} {ld:6d}")
  print()
  print(f"THE MASS: {tl} -> {al} comment lines  (the cut: {tl-al}, {100*(tl-al)/tl:.1f}%)")
  print(f"THE BLOCKS: {tb} -> {ab}")
  print(f"THE KEEP SET (DIFFERENCE/WEIRD/MEASURED): {tbk} blocks/{tll} lines -> "
        f"{abk} blocks/{all_} lines")
  print(f"THE MARKERS LOST: cites {lc}  measured {lm}  difference {ld}")


if __name__ == "__main__":
  main()
