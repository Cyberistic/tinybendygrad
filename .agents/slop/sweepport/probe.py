#!/usr/bin/env python3
"""Probe: where `--plan`'s wall time goes, and the port's non-KEEP-CITED rows."""
from __future__ import annotations

import collections
import importlib.util
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("sweep", os.path.join(ROOT, "checks", "sweep.py"))
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)


def main() -> int:
    clock = time.time
    t0 = clock()
    tracked = sweep.tracked_files(ROOT)
    t1 = clock()
    files = sweep.walk_residue(ROOT)
    t2 = clock()
    copies = sweep.residue_copies(ROOT, [r for r, _ in files])
    t3 = clock()
    decl = sweep.declared_names()
    t4 = clock()
    cf = sweep.committed_files(ROOT, copies)
    t5 = clock()
    print(f"# tracked_files      {t1-t0:7.2f}s  ({len(tracked)} paths)")
    print(f"# walk_residue       {t2-t1:7.2f}s  ({len(files)} rows)")
    print(f"# residue_copies     {t3-t2:7.2f}s  ({len(copies)} copies)")
    print(f"# declared_names     {t4-t3:7.2f}s  ({len(decl)} names)")
    print(f"# committed_files    {t5-t4:7.2f}s  ({len(cf)} corpus files)")

    # Reuse the measured results so the TOTAL is the sum of the phases, not a second pass.
    sweep.tracked_files = lambda root=ROOT: tracked
    sweep.residue_copies = lambda root, rows: copies
    sweep.committed_files = lambda root=ROOT, copies=None: cf
    f = sweep.facts(ROOT)
    t6 = clock()
    print(f"# facts() TOTAL      {t6-t0:7.2f}s  (phases above + classify setup)")

    for rel in sweep.port_files(f.root):
        v = sweep.verdict_for(rel, f.mentioned, f, set())
        if not v.startswith("KEEP-CITED"):
            print(f"# PORT {v[:90]:90s} {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
