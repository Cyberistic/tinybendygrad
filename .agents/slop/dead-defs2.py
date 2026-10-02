#!/usr/bin/env python3
"""DEAD-DEF AUDIT, comment-aware, for a .bend file.

The first version of this (slop/dead-defs.py) matched only the BASE name, so
`def rp.pair.hi` was scored alive by the hundreds of `rp.` uses and `def rp.acc`
was scored alive by the three COMMENTS that name it. It found 4 dead defs in a
file that had 26. This one matches the FULL dotted name and strips comments and
strings first, so a def has to be CALLED to count as alive.

A def is a number with no authority when nothing reads it: a constant nobody
quotes is a claim nobody can check, and a fold nobody calls is a proof nobody
read. Both are worse than the line they cost.

    python3 .agents/slop/dead-defs2.py tinybendygrad/runtime/support/nv/ip.bend
"""
import re, sys
from pathlib import Path

DEF = re.compile(r"^(def|type)\s+([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_0-9]+)*)")
# the entry point is called by the runtime, not by the file, so it is alive by
# being `main` and reporting it dead is a false positive on every file.
ENTRY = {'main'}


def strip(line):
  """Drop a `#` comment and a double-quoted string, so neither can keep a def alive."""
  out, in_str = [], False
  for i, ch in enumerate(line):
    if ch == '"' and (i == 0 or line[i - 1] != '\\'):
      in_str = not in_str
      continue
    if ch == '#' and not in_str:
      break
    if not in_str:
      out.append(ch)
  return ''.join(out)


def audit(path):
  lines = Path(path).read_text().splitlines()
  code = [strip(l) for l in lines]
  defs = [(m.group(2), i) for i, l in enumerate(code, 1) if (m := DEF.match(l))]
  # blank each def's OWN name in place but keep the rest of the line, which is where
  # most of these read their arguments (`def door.token_gb2(..) -> U32: U32.or(..)`)
  body = []
  for i, l in enumerate(code, 1):
    m = DEF.match(l)
    body.append((' ' * (len(m.group(1)) + 1) + l[m.end():]) if m else l)
  haystack = '\n'.join(body)
  dead = [(n, i) for n, i in defs
          if n not in ENTRY
          and not re.search(r'(?<![A-Za-z_0-9.])' + re.escape(n) + r'(?![A-Za-z_0-9])', haystack)]
  return lines, defs, dead


def main():
  bad = 0
  for p in sys.argv[1:]:
    lines, defs, dead = audit(p)
    print('%s: %d defs, %d never called' % (Path(p).name, len(defs), len(dead)))
    for n, i in dead:
      print('  line %-5d %-22s %s' % (i, n, lines[i - 1].strip()[:66]))
    bad += len(dead)
  return 1 if bad else 0


if __name__ == '__main__':
  sys.exit(main())
