#!/usr/bin/env python3
"""Git-history probes for the citation classifier.

  * `historical_paths()` -- one `git rev-list --all --objects` dump -> the set of
    every path that existed in any commit (the brief's own 75,336-path figure).
  * `ever_existed(basename)` -- was this basename ever a tracked path?
  * `was_tracked(path)` -- exact historical path.

Emitted once as a TSV so the classifier does not re-shell per row.
"""
from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def historical_paths() -> dict[str, int]:
    out = subprocess.run(
        ["git", "rev-list", "--all", "--objects"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    paths: dict[str, int] = {}
    for line in out.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2:
            paths[parts[1]] = paths.get(parts[1], 0)
    return paths


def main() -> int:
    paths = historical_paths()
    bases: dict[str, int] = {}
    for p in paths:
        bases[os.path.basename(p)] = bases.get(os.path.basename(p), 0) + 1
    print("kind\tkey\tcount")
    for p in sorted(paths):
        print(f"path\t{p}\t1")
    for b, n in sorted(bases.items()):
        print(f"base\t{b}\t{n}")
    print(f"# total_paths={len(paths)} distinct_basenames={len(bases)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
