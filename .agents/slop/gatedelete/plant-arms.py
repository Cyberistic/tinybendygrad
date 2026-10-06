#!/usr/bin/env python3
"""PLANT for `checks/disagree-gate.py`'s POSITIVE arm claim (`arms_wired`).

The five edits this unit landed leave the citation lane reading `ok` whether it got
STRONGER or was quietly WEAKENED -- identical output either way.  So the claim is moved:
the dispatcher text is mutated on a SCRATCH COPY (the real `.agents/slop/graphcmp.bend`
belongs to another unit) and the lane is required to go RED.

`arms_wired` is loaded BY PATH because the gate's filename is hyphenated and cannot be
imported as a module name.  Three subjects:

  1. the real dispatcher text                          -> no failure
  2. scratch: `allred`'s routing bite removed          -> failure (falls to g_matmul)
  3. scratch: `g_cdiv`'s definition renamed            -> failure (defined 0 times)

Exit 0 iff every subject answers as demanded; 1 otherwise.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATE = ROOT / "checks" / "disagree-gate.py"
BEND = ROOT / ".agents" / "slop" / "graphcmp.bend"


def load_arms_wired():
  spec = importlib.util.spec_from_file_location("disagree_gate", GATE)
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module.arms_wired


def main() -> int:
  arms_wired = load_arms_wired()
  real = BEND.read_text()

  # 1. THE CONTROL.  An intact dispatcher must pass, or the plant proves nothing.
  control = arms_wired(real)
  print(f"{'ok  ' if not control else 'FAIL'}  control (intact dispatcher): {control}")

  # 2. BREAK THE ROUTING.  Drop the bite that selects `g_allred()`; the name now falls
  #    through to `rows.pick3`'s bottom rung, `g_matmul()`, and is never compared.
  broke_route = real.replace('String.eq(name, "allred"), g_allred()',
                             'String.eq(name, "allred"), g_matmul()')
  assert broke_route != real, "the routing bite was not found; the plant is stale"
  r2 = arms_wired(broke_route)
  print(f"{'RED ' if r2 else 'FAIL'}  plant: allred arm un-routed -> {r2}")

  # 3. BREAK THE BUILDER.  A definition that is gone (or doubled) is the other half of
  #    the claim; it must go red too.
  broke_def = real.replace("def g_cdiv() -> O.Found:", "def g_cdiv_gone() -> O.Found:", 1)
  assert broke_def != real, "g_cdiv definition not found; the plant is stale"
  r3 = arms_wired(broke_def)
  print(f"{'RED ' if r3 else 'FAIL'}  plant: g_cdiv undefined   -> {r3}")

  ok = not control and bool(r2) and bool(r3)
  print("PLANT ARMS:", "OK -- the lane can go red" if ok else "BROKEN")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())
