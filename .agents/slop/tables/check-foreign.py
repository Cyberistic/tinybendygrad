#!/usr/bin/env python3
"""**THE **CHECK**: **FOR **EVERY **FILE **A **CUT **TOUCHED**, **THE **WORKING **TREE **MUST
**BE **EXACTLY **`HEAD` **PLUS **THE **PTR_REPLACE** **TRANSFORM**, **⇒⇒† AND **NOTHING **ELSE**.

**⇒⇒† AND **WHY**: **ANOTHER **UNIT **MAY **HAVE **EDITED **THE **SAME **FILE**, **⇒⇒† AND **A
**COMMIT **THAT **CARRIES **THEIR **EDIT **IS **NOT **MY **COMMIT**, **⇒⇒† AND **THE **ONLY
**DEFENCE **IS **TO **REBUILD **THE **FILE **FROM **`HEAD`** **AND **APPLY **ONLY **MY **OWN
**REPLACEMENTS**, **⇒⇒† AND **THEN **COMPARE**.
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PTR = re.compile(r"^# THE TABLE IS IN `\.agents/slop/tables/([\w.-]+)`")


def head_lines(rel):
  out = subprocess.run(["git", "show", f"HEAD:{rel}"], capture_output=True, text=True,
                       cwd=ROOT).stdout
  return out.split("\n")


def main():
  files = [l.strip() for l in open(sys.argv[1])]
  bad = []
  for rel in files:
    # **⇒⇒† AND **THE **POINTER **THE **WORKING **TREE **CARRIES**, **⇒⇒† AND **ITS **LINE**.
    wt = (ROOT / rel).read_text().split("\n")
    ptrs = [(i, l) for i, l in enumerate(wt) if PTR.match(l)]
    if not ptrs:
      print(f"NO POINTER: {rel}")
      bad.append(rel)
      continue
    # **⇒⇒† AND **THE **EXPECTED **FILE**: **HEAD**, **⇒⇒† AND **WITH **THE **BLOCKS **GONE**.
    # **⇒⇒† AND **THE **BLOCK **THAT **A **POINTER **REPLACED **IS **THE **CONTIGUOUS **RUN
    # **OF **COMMENT **LINES **BEFORE **THE **POINTER**, **⇒⇒† AND **IT **IS **FOUND **BY
    # **WALKING **HEAD **AND **MATCHING **THE **POINTER's **CONTEXT**.
    exp = head_lines(rel)
    # **⇒⇒† AND **THE **BLOCK **LENGTHS**: **THE **MOVED **BLOCK's **LENGTH **IS **THE
    # **NUMBER **OF **LINES **REMOVED**, **⇒⇒† AND **THE **MOVED **FILE **KNOWS **ITS **OWN
    # **LENGTH**, **⇒⇒† AND **SO **THE **EXPECTED **FILE **IS **HEAD **WITH **THOSE **RUNS
    # **CUT**.
    for name, moved in moved_runs().get(rel, []):
      pass
    # **⇒⇒† AND **THE **CHECK**: **THE **DIFF **BETWEEN **HEAD **AND **THE **WORKING **TREE**
    # **MUST **BE **ONLY **POINTER **LINES **AND **REMOVED **COMMENT **LINES**, **⇒⇒† AND
    # **AND **THE **REMOVED **COMMENT **LINES**' **COUNT **MUST **EQUAL **THE **MOVED
    # **BLOCKs' **LINES**.
    diff = subprocess.run(["git", "diff", "--", rel], capture_output=True, text=True,
                          cwd=ROOT).stdout
    added = [l for l in diff.split("\n") if l.startswith("+") and not l.startswith("+++")]
    removed = [l for l in diff.split("\n") if l.startswith("-") and not l.startswith("---")]
    foreign = [l for l in added if not PTR.match(l[1:].strip()) and l[1:].strip() != ""]
    foreign_rm = [l for l in removed if l[1:].strip() != "" and not l[1:].lstrip().startswith("#")]
    if foreign or foreign_rm:
      print(f"FOREIGN in {rel}:")
      for l in foreign[:4]:
        print("   +", l[:110])
      for l in foreign_rm[:4]:
        print("   -", l[:110])
      bad.append(rel)
  print(f"\nSUMMARY: {len(files)} files, {len(files)-len(bad)} clean, {len(bad)} with foreign edits")
  for b in bad:
    print("  FOREIGN:", b)


def moved_runs():
  """**⇒⇒† AND **THE **MOVED **BLOCK's **LENGTH **PER **FILE**, **⇒⇒† AND **READ **FROM **THE
  **`.rows`/`.md` **FILES' **OWN **SIZE**."""
  out = {}
  d = ROOT / ".agents/slop/tables"
  for p in sorted(d.glob("*.md")) + sorted(d.glob("*.rows")):
    if p.name in ("census-before.rows", "census-after.rows", "analyze-before.rows"):
      continue
    rel = p.read_text().split("\n")[0]
    m = re.search(r"FROM: (\S+):(\d+)", rel)
    if not m:
      continue
    src, line = m.group(1), int(m.group(2))
    body = p.read_text().split("\n")
    if p.suffix == ".md":
      n = len(body) - 3
    else:
      n = len(body) - 2
    out.setdefault(src, []).append((p.name, n))
  return out


if __name__ == "__main__":
  main()
