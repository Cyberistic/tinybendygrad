#!/usr/bin/env python3
"""Per-file evidence for the 24 `UNKNOWN:<needs>` rows of sweep.py's report-only port arm.

Reuses sweep's own functions (imports, never copies). Caches `committed_files` so Facts is built
with one corpus pass instead of two -- the same shape as sweepport/probe.py, which is why this
runs in ~70s and not ~140s. Read-only: writes nothing but stdout.

Run: .venv/bin/python .agents/slop/portunknown/probe.py
"""
from __future__ import annotations

import collections
import importlib.util
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("sweep", os.path.join(ROOT, "checks", "sweep.py"))
sweep = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(sweep)


def _tracked() -> set[str]:
    return sweep.tracked_files(ROOT)


def main() -> int:
    tracked = _tracked()
    files = sweep.walk_residue(ROOT)
    copies = sweep.residue_copies(ROOT, [r for r, _ in files])
    _cf_cache: list = []
    _real_committed = sweep.committed_files

    def committed_files(root: str = ROOT, c: set[str] | None = None) -> list:
        if not _cf_cache:
            _cf_cache.append(_real_committed(root, copies))
        return _cf_cache[0]

    sweep.tracked_files = lambda root=ROOT: tracked
    sweep.residue_copies = lambda root, rows: copies
    sweep.committed_files = committed_files
    f = sweep.facts(ROOT)

    buckets: collections.Counter = collections.Counter()
    print(f"# port files: {len(sweep.port_files(f.root))}")
    for rel in sweep.port_files(f.root):
        v = sweep.verdict_for(rel, f.mentioned, f, set())
        b = sweep.bucket(v)
        buckets[b] += 1
        if v.startswith(sweep.UNKNOWN):
            name = os.path.basename(rel)
            a = f.cites[0].get(name, set())
            bb = f.cites[1].get(name, set())
            outside = sorted(c for c in (a | bb) if not sweep.in_residue(c))
            inside = sorted(c for c in (a | bb) if sweep.in_residue(c))
            wit = sweep.witness_committed(rel, f.tracked, f.root)
            print(f"\nROW {rel}")
            print(f"  needs     = {v.partition(':')[2].split(' (')[0]}")
            print(f"  tracked   = {rel in f.tracked}")
            print(f"  ext       = {os.path.splitext(name)[1]}")
            print(f"  witness   = {wit}")
            print(f"  n_beltA={len(a)} n_beltB={len(bb)}")
            if a ^ bb:
                print(f"  only_A = {sorted(a - bb)}")
                print(f"  only_B = {sorted(bb - a)}")
            print(f"  citers_outside_residue = {outside}")
            print(f"  citers_inside_residue  = {sorted(inside)}")
    print(f"\n# buckets: {dict(buckets)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
