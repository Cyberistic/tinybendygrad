#!/usr/bin/env python3
"""**THE **LOST **MARKERS** -- **THE **DIFFERENCE-MARKER **LINES **THE **RULE **DROPS**, **PRINTED **IN
**FULL**, **⇒⇒† AND **A **CUT **THAT **DROPS **THE **EVIDENCE **IS **NOT **A **CUT**.

**⇒⇒† AND **A **DIFFERENCE **MARKER **IS **A **LINE **THAT **SAYS **WHAT **THE **PORT **DOES **THAT
**UPSTREAM **DOES **NOT**, **⇒⇒† AND **A **LINE **THAT **CARRIES **ONE **IS **STILL **A **FACT**, **⇒⇒†
**AND **A **FACT **WITHOUT **ITS **PRECEDENT **IS **A **FRAGMENT**, **⇒⇒† AND **SO **THE **READER
**CANNOT **USE **IT**."""

import importlib.util
import pathlib
import subprocess
import sys

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
  out, i = [], 0
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


def main():
  for n in FILES:
    before = subprocess.run(["git", "show", f"{BASE}:tinybendygrad/uop/{n}.bend"],
                            capture_output=True, text=True, check=True).stdout
    after = cut(before)
    kept = {l.strip().lstrip("#").strip() for l in after.split("\n") if l.strip().startswith("#")}
    for l in before.split("\n"):
      s = l.strip().lstrip("#").strip()
      if not s or not cc.DIFFERENCE.search(s):
        continue
      if s in kept:
        continue
      print(f"{n}: {s}")


if __name__ == "__main__":
  main()
