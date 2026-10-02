#!/usr/bin/env python3
"""DELETE EVERY DUPLICATE `def NAME` BLOCK, keeping the LAST one.

Bend's "expected : a fresh name (duplicate declaration: X)" is the loudest error
in the toolchain and the easiest to create by accident: `.agents/slop/dsl_gen.py`
regenerates the gate body from its marker down and injects a fixture file above
it, so a fixture written by hand between two generator runs ends up declared
TWICE and the file will not compile. Which of the two survives is arbitrary, so
this drops the earlier copies and keeps the injected one -- the injected file is
the one the next generator run reproduces, and keeping the other would make the
fix evaporate on the next run.

    usage: .venv/bin/python .agents/slop/bend_dedup.py FILE
"""
import re
import sys
from collections import Counter
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text().split("\n")
names = [m.group(1) for m in re.finditer(r"(?m)^def ([A-Za-z_][A-Za-z_0-9]*)\(", "\n".join(lines))]
dups = {k for k, v in Counter(names).items() if v > 1}
if not dups:
  print("no duplicate defs")
  sys.exit(0)

starts = [i for i, l in enumerate(lines) if re.match(r"^def [A-Za-z_][A-Za-z_0-9]*\(", l)]
starts.append(len(lines))
blocks = {}
for a, b in zip(starts, starts[1:]):
  name = re.match(r"^def ([A-Za-z_][A-Za-z_0-9]*)\(", lines[a]).group(1)
  blocks.setdefault(name, []).append((a, b))

drop = set()
for name, spans in blocks.items():
  if name in dups and len(spans) > 1:
    for a, b in spans[:-1]:
      drop.update(range(a, b))
path.write_text("\n".join(l for i, l in enumerate(lines) if i not in drop))
print(f"dropped {len(drop)} lines; {len(dups)} duplicated names")