#!/usr/bin/env python3
"""DEAD-DEF AUDIT for a .bend file: which top-level defs does nothing read?

Name-based and deliberately crude -- Bend's `def f.g` is called as `f.g`, so the
base name is what a use looks like -- but a CONSTANT is the case that matters:
`def X() -> U32: 13` with no reader is a number with no authority, which is exactly
the failure ops_nv shipped 33 of. A file whose header claims "305 blocks, 305
reachable, 0 dead" is worth re-measuring rather than trusting.

  usage: .venv/bin/python .agents/slop/dead-defs.py <file.bend> [...]
"""
import re, sys
from pathlib import Path

DEF = re.compile(r"^(?:def|type)\s+([A-Za-z_][A-Za-z_0-9]*)")
# identifiers a use can look like: bare, dotted, or called. `X()` / `X.y(` / `X.y`
USE = re.compile(r"(?<![A-Za-z_0-9.])([A-Za-z_][A-Za-z_0-9]*)")


def audit(path):
  text = Path(path).read_text()
  defs, order = {}, []
  lines = text.splitlines()
  for i, line in enumerate(lines, 1):
    m = DEF.match(line)
    if m and m.group(1) not in defs:
      defs[m.group(1)] = i
      order.append(m.group(1))
  imported = set()
  for a, b in re.findall(r"^import\s+(\S+)(?:\s+as\s+(\S+))?", text, re.M):
    imported.add(b or a.rsplit("/", 1)[-1].removesuffix(".bend"))
  # A def's own NAME is not a use of itself. Blank the name token in place -- do NOT
  # drop the whole line: most defs here are ONE LINE (`def q.submit.zero(n) -> U32:
  # D.round_up(n, ZERO_ALIGN())`) and dropping the line hides every constant they read.
  body = "\n".join(DEF.sub("  ", l) if DEF.match(l) else l for l in lines)
  used = set(USE.findall(body)) - imported
  dead = [n for n in order if n not in used]
  return defs, dead, len(order)


def main():
  bad = 0
  for p in sys.argv[1:]:
    defs, dead, n = audit(p)
    print(f"{Path(p).name}: {n} top-level defs, {len(dead)} never mentioned")
    for d in dead:
      ln = defs[d]
      src = Path(p).read_text().splitlines()[ln - 1].strip()
      print(f"  DEAD line {ln}: {src}")
    bad += len(dead)
  return 0


if __name__ == "__main__":
  sys.exit(main())
