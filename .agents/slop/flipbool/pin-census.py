#!/usr/bin/env python3
""".agents/slop/flipbool/pin-census.py -- STATIC. The other DENOMINATOR: how many rows of
`checks/disagree-gate.py`'s `PIN` are UN-DIAGNOSED.

`shape="BOTH"` and `fault="HARNESS+PORT"` are the same admission written in two columns: a
row nobody has established whose it is. `AGENTS.md` doctrine 1 says a population is the
GENERATOR'S OWN DECLARATION, LOADED BY PATH -- so this loads `PIN` from the gate itself
rather than grepping a second copy of the list. `checks/disagree-gate.py` is stdlib-only,
so the import is safe and does not touch the tree.

Output is `.rows`/`.md`, never `.txt`."""
import collections
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
GATE = HERE.parents[2] / "checks" / "disagree-gate.py"


def load_pin():
  spec = importlib.util.spec_from_file_location("disagree_gate", GATE)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod.PIN


def main() -> int:
  if not GATE.is_file():
    print(f"== REFUSED, NOT A VERDICT: gate absent: {GATE}", file=sys.stderr)
    return 3
  pin = load_pin()
  shapes = collections.Counter(p["shape"] for p in pin.values())
  faults = collections.Counter(p["fault"] for p in pin.values())
  print(f"# PIN rows (the generator's own declaration, loaded by path): {len(pin)}")
  for name in sorted(pin):
    p = pin[name]
    print(f"#   {name:<10} row={p['row']:<3} shape={p['shape']:<12} fault={p['fault']}")
  print(f"# shape tally : {dict(sorted(shapes.items()))}")
  print(f"# fault tally : {dict(sorted(faults.items()))}")
  undiagnosed = [n for n, p in pin.items()
                 if p["shape"] == "BOTH" or "HARNESS" in p["fault"]]
  print(f"# UN-DIAGNOSED (shape BOTH or fault names HARNESS): {len(undiagnosed)} {undiagnosed}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
