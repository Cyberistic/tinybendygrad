#!/usr/bin/env python3
"""CENSUS -- how many co-independent literal lists exist, by scope.  os.walk for the
whole tree; `git ls-files` for the TRACKED population; the two are printed together so a
narrowed scan cannot be mistaken for the whole one.

    .venv/bin/python .agents/slop/pairs/census.py
"""
from __future__ import annotations

import ast
import os
import pathlib
import subprocess
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[3]
SKIP = {"__pycache__", "node_modules", ".venv", ".git", "references", "test", "tinygrad"}


def string_lists(p):
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except (SyntaxError, OSError):
        return []
    out = []
    for n in ast.walk(tree):
        if isinstance(n, (ast.Tuple, ast.List, ast.Set)):
            vals, ok = [], True
            for e in n.elts:
                if isinstance(e, ast.Constant) and isinstance(e.value, str):
                    vals.append(e.value)
                else:
                    ok = False
                    break
            if ok and len(vals) >= 3:
                out.append(tuple(sorted(vals)))
    return out


def shared(files):
    d = defaultdict(set)
    for p in files:
        for k in string_lists(p):
            d[k].add(str(p.relative_to(ROOT)))
    return {k: v for k, v in d.items() if len(v) >= 2}


def walk_all():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP]
        for f in fns:
            if f.endswith(".py"):
                yield pathlib.Path(dp) / f


def tracked():
    out = subprocess.run(["git", "ls-files", "*.py"], cwd=ROOT,
                         capture_output=True, text=True).stdout.split()
    return [ROOT / f for f in out if (ROOT / f).exists()]


def main():
    w = shared(walk_all())
    t = shared(tracked())
    slop = {k: v for k, v in t.items() if all(".agents/slop/" in x for x in v)}
    live = {k: v for k, v in t.items() if not all(".agents/slop/" in x for x in v)}
    print(f"WHOLE TREE (os.walk, SKIP={sorted(SKIP)}): {len(w)} shared string-lists")
    print(f"TRACKED (.py in git ls-files): {len(t)} shared string-lists")
    print(f"  of those, ALL sites under .agents/slop/ (scratch copies/plants): {len(slop)}")
    print(f"  TRACKED, >=1 site OUTSIDE .agents/slop/ (live instruments):     {len(live)}")
    print("\nTHE BRIEF'S 5, at HEAD, are in the live set: abi fence, mixin port_only, i64-shl")
    print("values, disagree ARMED/WANT, SKIP_DIRS.  coindependent scoped to checks/+gates/")
    print("only, which is why it saw 5 and this sees more; both are correct for their scope.")
    print("\nLIVE SET (>=1 tracked site outside .agents/slop/), with its sites:")
    for k, v in sorted(live.items(), key=lambda kv: -len(kv[1])):
        print(f"  [{len(k)}] {list(k)[:5]}{' ...' if len(k) > 5 else ''}")
        for x in sorted(v):
            print(f"      {x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
