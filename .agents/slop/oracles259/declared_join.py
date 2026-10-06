#!/usr/bin/env python3
"""Q3, measured: is any oracles/*.txt in differ.declared()?

declared() returns BARE names for runs/graphcmp/D only. Measure the join both ways:
  (a) full-path join, (b) basename join. If (b) > 0 while (a) == 0, the name is shared but the
  path is not, which is a different fact than "declared".
"""
import importlib.util
import os
import pathlib

ROOT = pathlib.Path(".").resolve()
spec = importlib.util.spec_from_file_location("differ", ROOT / "checks/differ.py")
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)

decl = differ.declared()
print(f"declared() size: {len(decl)}")

txts = sorted(p for p in (ROOT / "oracles").rglob("*.txt") if p.is_file())
print(f"oracles/*.txt: {len(txts)}")

D = "runs/graphcmp/D"
full = {os.path.join(D, n) for n in decl}

a = [str(p.relative_to(ROOT)) for p in txts if str(p.relative_to(ROOT)) in full]
print(f"(a) full-path join: {len(a)}")

decl_base = {n for n in decl}
b = [str(p.relative_to(ROOT)) for p in txts if p.name in decl_base]
print(f"(b) basename join: {len(b)}")
for x in b:
    print(f"    basename-only collision: {x}")

# And the reverse: what is declared, where does it live
missing = [n for n in decl if not (ROOT / D / n).exists()]
print(f"declared names with NO FILE on disk: {len(missing)} / {len(decl)}")
print("  sample:", sorted(missing)[:8])
