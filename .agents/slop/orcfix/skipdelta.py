#!/usr/bin/env python3
"""What does `code_files()`'s `skip` literal actually DO? Rebuild `readers()` under two states
-- with the hand-list entry and without -- and diff the reader map."""
from __future__ import annotations
import importlib.util, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("census", ROOT / "checks/oracle-txt-census.py")

def load():
    m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m); return m

m = load()
me = "checks/oracle-txt-census.py"
DEAD = ".agents/slop/oracles259/plants.py"


def code_files(extra_skip):
    skip = {me} | ({DEAD} if extra_skip else set())
    return [r for r in subprocess.run(["git", "ls-files"], cwd=ROOT,
            capture_output=True, text=True).stdout.split()
            if pathlib.Path(r).suffix in (".sh", ".py")
            and not r.startswith(("references/", "tinygrad/", ".agents/slop/oracletxt/"))
            and r not in skip]

with_ = code_files(True)
without = code_files(False)
added = sorted(set(without) - set(with_))
print(f"files excluded ONLY by the hand-list literal: {len(added)}")
for a in added:
    print(f"  {a}")
print(f"literal present on disk? {(ROOT/DEAD).exists()}")


def readers_with(files):
    m.code_files = lambda: [ROOT / f for f in files]
    return m.readers()

r_with, r_without = readers_with(with_), readers_with(without)
keys = set(r_with) | set(r_without)
changed = [k for k in sorted(keys) if r_with.get(k) != r_without.get(k)]
print(f"\nbasenames whose reader-list changes: {len(changed)}")
for k in changed:
    print(f"  {k}")
    print(f"    with:    {sorted(x[0] for x in r_with.get(k, []))}")
    print(f"    without: {sorted(x[0] for x in r_without.get(k, []))}")
