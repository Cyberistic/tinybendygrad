#!/usr/bin/env python3
"""BOTH HALVES OF THE CENSUS: it must fire on the offending shape and stay quiet on the fix.

A check that only ever fires has not been shown to still bite (`plant_shape`'s rule in
`graphcmp.py`). So the same detector is run twice on two spellings of the SAME fact:

    BEFORE  same = "same" if a == b else f"PY-BEND OPs DIFFER: {a ^ b}";  print(same)
    AFTER   same = "same" if a == b else f"PY-BEND OPs DIFFER: {sorted(a ^ b)}"; print(same)

and once on the real pre-fix oracle (`46c52f30d^`), which is the site the sort closed. It
prints PASS/FAIL per check and exits non-zero on any FAIL.
"""
from __future__ import annotations

import ast
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import census  # noqa: E402

BEFORE = 'def f(a, b):\n  same = "same" if a == b else f"PY-BEND OPs DIFFER: {a ^ b}"\n  print(same)\n'
AFTER = 'def f(a, b):\n  same = "same" if a == b else f"PY-BEND OPs DIFFER: {sorted(a ^ b)}"\n  print(same)\n'


def flags(src: str) -> list[str]:
    tree = ast.parse(src)
    par = census.parents(tree)
    bound = census.name_bound_order_bearing(tree, par)
    out = []
    for node in census.emit_sites(tree):
        hits = {m for sub in ast.walk(node)
                if (m := census.order_bearing(sub)) and not census.guarded(sub, par)}
        hits |= {f"via name {n.id}" for n in ast.walk(node)
                 if isinstance(n, ast.Name) and n.id in bound and not census.guarded(n, par)}
        out += sorted(hits)
    return out


def main() -> int:
    checks = [
        ("BEFORE the sort (the offending shape) FLAGS", bool(flags(BEFORE)), flags(BEFORE)),
        ("AFTER the sort (the fix) is QUIET", not flags(AFTER), flags(AFTER)),
    ]
    old = subprocess.run(["git", "show", "46c52f30d^:.agents/slop/graphcmp-oracle.py"],
                         cwd=census.ROOT, capture_output=True, text=True)
    if old.returncode == 0:
        checks.append(("the REAL pre-fix oracle FLAGS", bool(flags(old.stdout)),
                       flags(old.stdout)))
    print("CENSUS PLANTS -- both halves of the detector")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
    bad = sum(not c[1] for c in checks)
    print(f"PLANT: {'GREEN' if not bad else 'RED'} ({len(checks) - bad}/{len(checks)})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
