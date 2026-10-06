#!/usr/bin/env python3
"""DIFF THE WHOLE `name=value` LINE for a renderer gate, and SAY WHAT IS COVERED.

WHY WHOLE LINES. Two units lost complete mutation tables to a harness that
compared ROW NAMES: a name-comparing harness reported 0 for all 30 mutations in
one unit and 0 for all 68 in another, because every row kept its name and only
its value moved. So this splits ONCE at the first `=` and compares the halves.

A row in one side and not the other is a MISSING or an EXTRA and is always
counted. They are NOT failures -- a renderer port gates a chosen slice of a
1605-row oracle, and pretending the other 1006 rows agree would be a lie -- but
they are printed, so "1006 not covered" is visible rather than assumed.

    usage: .venv/bin/python .agents/slop/rend_gate.py PORT.txt ORACLE.txt [--show N]
"""
import sys
from pathlib import Path


def parse(path):
  out = {}
  for line in Path(path).read_text().splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k] = v
  return out


port_p, orc_p = sys.argv[1], sys.argv[2]
show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 40
port, orc = parse(port_p), parse(orc_p)
common = sorted(set(port) & set(orc))
bad = [(k, port[k], orc[k]) for k in common if port[k] != orc[k]]
for k, a, b in bad[:show]:
  print(f"MISMATCH {k}\n  port   {a}\n  oracle {b}")
if len(bad) > show:
  print(f"... and {len(bad) - show} more mismatches")
print(f"GATED {len(common)} rows: {len(common) - len(bad)} agree, {len(bad)} disagree")
print(f"NOT COVERED {len(set(orc) - set(port))} oracle rows the port does not print")
print(f"PORT ONLY  {len(set(port) - set(orc))} rows the oracle does not produce")
sys.exit(1 if bad else 0)