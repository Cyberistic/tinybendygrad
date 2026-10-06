#!/usr/bin/env python3
"""graphcmp-dbg-oracle.py -- DOES CPYTHON's OWN `DEBUG >= 1` SITE EVER FIRE HERE?

The DEBUG-level comparison in `graphcmp.py dbg` is PORT-AT-LEVEL-A against
PORT-AT-LEVEL-B. It is not port-against-CPython, and the reason has to be MEASURED and
counted rather than asserted, because "the oracle could not reach the subject" and "the
oracle agreed" look identical in a report.

The subject is `tinygrad/schedule/memory.py:59-60`:

    if DEBUG >= 1 and (omem:=sum(nbytes.values())/1e6) != (nmem:=sum(arena_sizes.values())/1e6):
      print(f"memory reduced from {omem:.2f} MB -> {nmem:.2f} MB, {len(first_appearance)} -> {len(arenas)} bufs")

It has a CONDITION beside the gate, so it is silent both when the level is too low AND
when the planner reduced nothing. This oracle builds N real graphs, realises each one at
`DEBUG=1`, and reports how many printed the line -- with the denominator, because a count
of 0 over 9 fixtures is a statement about 9 fixtures.

    env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-dbg-oracle.py
"""
from __future__ import annotations

import io
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MARK = "memory reduced from"

FIXTURES = {
  "mm4x3": "x = Tensor.empty(4,3); (x @ Tensor.empty(3,5)).realize()",
  "mm512": "(Tensor.empty(512,512) @ Tensor.empty(512,512)).realize()",
  "mm1000": "(Tensor.empty(1000,1000) @ Tensor.empty(1000,1000)).realize()",
  "add64_relu": "a = Tensor.empty(64,64)+Tensor.empty(64,64); (a @ a).relu().realize()",
  "chain4x3": "x = Tensor.empty(4,3); y = x @ x.T; z = y @ x; z.sum().realize()",
  "mm_then_two_mm": "a = Tensor.empty(512,512) @ Tensor.empty(512,512); "
                    "(a.relu() + (Tensor.empty(512,512) @ Tensor.empty(512,512))).realize()",
  "big_add_chain": "a = Tensor.empty(1024,1024)+Tensor.empty(1024,1024); "
                   "b = a.relu()+a; (b @ Tensor.empty(1024,8)).realize()",
  "conv_like": "import tinygrad.nn as nn; "
               "m = nn.Conv2d(3, 8, 3, padding=1); m(Tensor.empty(1,3,16,16)).realize()",
}


def run(src: str, level: str) -> tuple[str, int]:
  e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  e.update(LC_ALL="C", DEV="NULL", DEBUG=level)
  c = subprocess.run([os.path.join(REPO, ".venv/bin/python"), "-c",
                      "from tinygrad import Tensor\n" + src + "\nprint('DONE')"],
                     cwd=REPO, capture_output=True, text=True, env=e, timeout=900)
  return c.stdout, c.returncode


def main() -> int:
  print(f"# MARK searched for: {MARK!r}  (memory.py:59)")
  fired = failed = 0
  for name in sorted(FIXTURES):
    out, rc = run(FIXTURES[name], "1")
    hit = MARK in out
    fired += hit
    failed += rc != 0 or "DONE" not in out
    print(f"  {name:<16} DEBUG=1 rc={rc} line-fired={hit} done={'DONE' in out}")
  print(f"# FIXTURES={len(FIXTURES)}  FIRED={fired}  NOT-FIRED={len(FIXTURES) - fired}  "
        f"DID-NOT-COMPLETE={failed}")
  print("# READ: the `DEBUG >= 1` memory site is a CONDITIONAL print, so a fixture that does "
        "not fire is a fixture whose planner reduced nothing (or whose level was too low) "
        "-- it is NOT evidence the gate is unwired, and `debug-gate.bend`'s own `thr_mem=1` "
        "row is the measurement that the GATE is wired.")
  print("# CONSEQUENCE FOR graphcmp.py dbg: there is no CPython lane for the trace TEXT on "
        "this host, so `dbg` is a port-vs-port comparison across levels and says so. It is "
        "a first-class diff of a thing that DID move, not a corroboration of a value.")
  return 0


if __name__ == "__main__":
  sys.exit(main())