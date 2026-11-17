#!/usr/bin/env python3
"""**THE **ORPHANED **`.bend` **MODULES** -- **THE **FILES **THAT **NOTHING **IMPORTS**.

**WHY:** THE **TREE's **OWN **RULE** IS **THAT **A **DEAD **PORT **IS **NOT **A **PORT**, **⇒⇒⇒ AND
**THE **MOST **EXPENSIVE **THING **THE **PORT **HAS **IS **CODE **THAT **NOTHING **CALLS** -- **⇒⇒⇒
**AND **THE **TREE's **OWN **PREVIOUS **AUDIT **(`gates/edge-reach-census.py`) **COUNTED **GATES,
**NOT **MODULES**.

**⇒⇒⇒ AND **THE **POPULATION **IS **DISCOVERED**, **NOT **LISTED** (DOCTRINE 1): **THE **FILES **ARE
**FOUND **BY **A **DIRECTORY **WALK** (`os.walk` + `endswith('.bend')`) **⇒⇒⇒ AND **THE **IMPORTERS
**ARE **FOUND **BY **A **REGEX **OVER **THE **TREE's **OWN **WRITE **SITES** (`^import`) -- **⇒⇒⇒ AND
**THE **LIST **OF **IMPORTED **PATHS **IS **RESOLVED **AGAINST **THE **WALK**, **⇒⇒⇒ AND **A **PATH
**THAT **IS **IMPORTED **BY **NOTHING **AND **IS **NOT **A **ROOT** **IS **AN **ORPHAN**.

**⇒⇒† AND **THE **ROOTS **ARE **THE **FILES **THE **GATES **AND **THE **HARNESSES **NAME**, **⇒⇒† AND
**A **FILE **THAT **NOBODY **NAMES **AND **NOBODY **IMPORTS **IS **DEAD **CODE** -- **⇒⇒† AND **THE
**ORPHAN **LIST **IS **THE **CLAIM **AND **THE **CENSUS **IS **THE **INSTRUMENT**.
"""

import os
import pathlib
import re
import sys

R = pathlib.Path(__file__).resolve().parents[3]
PORT = R / "tinybendygrad"

# **THE **IMPORT **LINE** -- **AND **THE **PATH **IT **NAMES** -- **⇒⇒⇒ AND **THE **FORM **IS
# **`import ./../helpers.bend as H`** (A **RELATIVE **PATH**) **⇒⇒⇒ AND **SO **THE **RESOLUTION **IS
# **AGAINST **THE **IMPORTING **FILE's **DIRECTORY**.
IMPORT = re.compile(r"^\s*import\s+(\S+)(?:\s+as\s+\S+)?\s*$")


def main() -> int:
  files = []
  for dirpath, _, filenames in os.walk(PORT):
    for fn in filenames:
      if fn.endswith(".bend"):
        files.append(pathlib.Path(dirpath) / fn)
  files.sort()

  imported_by: dict[str, list[str]] = {}
  for f in files:
    try:
      text = f.read_text()
    except Exception:
      continue
    for line in text.split("\n"):
      m = IMPORT.match(line)
      if not m:
        continue
      spec = m.group(1)
      if spec.startswith("./") or spec.startswith("../") or spec == ".":
        target = (f.parent / spec).resolve()
        # **⇒⇒† AND **THE **SPEC **MAY **OR **MAY **NOT **CARRY **THE **EXTENSION**
        if not target.exists() and target.with_suffix(".bend").exists():
          target = target.with_suffix(".bend")
        rel = str(target.relative_to(PORT.resolve())) if target.is_relative_to(PORT.resolve()) else str(target)
        imported_by.setdefault(rel, []).append(str(f.relative_to(PORT)))

  # **⇒⇒† AND **A **MODULE **MAY **BE **USED **WITHOUT **BEING **IMPORTED**: **THE **GATES **AND
  # **THE **HARNESSES **NAME **A **PATH **DIRECTLY** -- **⇒⇒† AND **SO **THE **ORPHAN **TEST **MUST
  # **BE **"NOTHING **IMPORTS **IT **AND **NO **GATE **NAMES **IT"**, **⇒⇒† AND **THE **GATE **SET **IS
  # **DISCOVERED** (**A **WALK **OVER **`gates/` **AND **`checks/`**), **NOT **LISTED**.
  named_by_gate = set()
  for d in (R / "gates", R / "checks"):
    if not d.exists():
      continue
    for dp, _, fns in os.walk(d):
      for fn in fns:
        if not fn.endswith((".py", ".sh", ".bend")):
          continue
        try:
          text = (pathlib.Path(dp) / fn).read_text(errors="ignore")
        except Exception:
          continue
        for f in files:
          rel = str(f.relative_to(PORT))
          if rel in text or rel.replace("/", "\\/") in text:
            named_by_gate.add(rel)

  orphans = []
  for f in files:
    rel = str(f.relative_to(PORT))
    if rel not in imported_by and rel not in named_by_gate:
      orphans.append((rel, len(f.read_text().split("\n"))))

  total_lines = sum(n for _, n in orphans)
  print(f"THE .bend MODULES: {len(files)}")
  print(f"THE ORPHANS (NOTHING IMPORTS THEM): {len(orphans)}  ({total_lines} lines)")
  print()
  for rel, n in sorted(orphans, key=lambda r: -r[1]):
    print(f"  {n:6d} lines  {rel}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
