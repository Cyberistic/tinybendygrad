#!/usr/bin/env python3
"""pincheck.py -- A PIN'S OWN COUNT AGAINST ITS OWN TOPOSORT.

    .venv/bin/python .agents/slop/randcensus/pincheck.py

`cr_g` prints the node count and the toposort FROM THE SAME LIST
(`tinybendygrad/mixin/creation.bend:631-634`: `U32.show(List.length(xs))` and
`cr_topo(xs, ar)`), so a lane's count and its toposort token count are EQUAL BY
CONSTRUCTION.  A pin whose two disagree therefore CANNOT be satisfied by ANY lane --
it is a pin that cannot fail, because it can never pass.

This is the check that catches a hand-transcribed pin, and it is state-independent:
it needs no lane at all.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
_spec = importlib.util.spec_from_file_location("rand_census_gate", ROOT / "gates" / "rand_census-gate.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

OLD_PORT = {}
try:
  from oldpins import OLD as OLD_PORT  # noqa: E402
except ImportError:
  pass


def count_and_tokens(line):
  head, _, topo = line.partition(" topo=")
  n = int(head.split("=", 1)[1].split(" ", 1)[0])
  return n, topo.split()


bad = 0
print("== THE GATE'S PINS AS THEY STAND NOW")
for row, (py, port) in _mod.DIVERGES.items():
  for lane, line in (("py", py), ("port", port)):
    n, toks = count_and_tokens(line)
    ok = (n == len(toks))
    bad += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'BAD '} {lane:<4} {row:<12} claims {n} nodes, toposort carries {len(toks)} tokens")

if OLD_PORT:
  print("== THE PORT PINS AS THE GATE CARRIED THEM AT HEAD 13fbb54fe")
  for row, line in OLD_PORT.items():
    n, toks = count_and_tokens(line)
    ok = (n == len(toks))
    bad += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'BAD '} port {row:<12} claims {n} nodes, toposort carries {len(toks)} tokens")

print(f"\n== PINS THAT CANNOT BE SATISFIED BY ANY LANE: {bad}")
sys.exit(1 if bad else 0)
