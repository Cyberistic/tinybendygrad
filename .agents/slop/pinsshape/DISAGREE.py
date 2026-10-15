#!/usr/bin/env python3
"""DISAGREE.py -- MEASUREMENT. What does `pins-shape-gate.py`'s `namer()` MISS that a
directory-wide literal scan sees?

`namer()` is `ast.parse`-only (`if f.suffix != ".py": continue`), and its pool is
`gates-pop.discover()`, which MEASURED returns 0 of the 58 `.bend` drivers under `gates/`.
So a table read by a `.bend` driver reports "named by nothing". This counts the disagreement.
"""

import os
import stat
import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "gates"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from POPULATION import owners_by_literal, owner_pool  # noqa: E402

import importlib.util  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GATES = ROOT / "gates"
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    s = importlib.util.spec_from_file_location("ps", GATES / "pins-shape-gate.py")
    ps = importlib.util.module_from_spec(s)
    s.loader.exec_module(ps)

tables = [p.name for p in sorted(GATES.iterdir())
          if p.suffix == ".rows" and not p.name.startswith(".")
          and stat.S_ISREG(os.lstat(p).st_mode)]

# WHAT THE GATE SEES
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    s2 = importlib.util.spec_from_file_location("gp", GATES / "gates-pop.py")
    gp = importlib.util.module_from_spec(s2)
    s2.loader.exec_module(gp)
    entries, libs = gp.discover(ROOT)
gate_pool = entries + [p for p in libs if p.suffix == ".py"]
gate_named = ps.namer(gate_pool)

# WHAT THE DIRECTORY SEES
dir_named = owners_by_literal(owner_pool(), tables)

print(f"# gate pool: {len(gate_pool)} (discover() -> {len(entries)} entries + "
      f"{len([p for p in libs if p.suffix == '.py'])} .py libs); "
      f"directory pool: {len(owner_pool())}")
print(f"# .bend under gates/: {len([p for p in GATES.glob('*.bend')])} -- of which discover() "
      f"returns {len([p for p in entries + libs if p.suffix == '.bend'])}\n")
print(f"{'table':34s} {'GATE SEES':28s} {'DIRECTORY SEES'}")
print("-" * 120)
n = 0
for t in tables:
    a, b = sorted(gate_named.get(t, set())), sorted(dir_named[t])
    flag = "  <<< DISAGREE" if set(a) != set(b) else ""
    if flag:
        n += 1
    print(f"{t:34s} {(','.join(a) or 'NONE')[:28]:28s} {','.join(b) or 'NONE'}{flag}")
print(f"\n# {n} of {len(tables)} table(s) have a DIFFERENT owner set under the two lookups.")