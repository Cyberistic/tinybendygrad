#!/usr/bin/env python3
"""PLANT: the port arm's number must MOVE when its subject changes.

Two states over one fixture port tree under this unit's own directory; the arm is driven through
`port_report`/`port_files`'s `base` parameter, which exists for exactly this. Nothing under the real
`tinybendygrad/` is written.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("sweep", os.path.join(ROOT, "checks", "sweep.py"))
sweep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sweep)

FIX = os.path.join(ROOT, ".agents/slop/sweepport/plant-fixture")


def measure() -> tuple[dict, dict, int]:
    f = sweep.facts(ROOT)
    b, n, t = sweep.port_report(f, sweep.port_files(ROOT, base=FIX))
    return dict(b), dict(n), t


def main() -> int:
    shutil.rmtree(FIX, ignore_errors=True)
    os.makedirs(FIX)

    # STATE A -- one file a committed report names: the rules CAN classify it.
    with open(os.path.join(FIX, "LAWS.bend"), "w") as h:
        h.write("x\n")
    a_b, a_n, a_t = measure()

    # STATE B -- add a file nothing names: the rules CANNOT classify it -> UNKNOWN.
    with open(os.path.join(FIX, "orphan-xyzzy.bend"), "w") as h:
        h.write("y\n")
    b_b, b_n, b_t = measure()

    print("# PLANT: port arm, two states")
    print(f"#   state A: {a_t} files  buckets={a_b}  needs={a_n}")
    print(f"#   state B: {b_t} files  buckets={b_b}  needs={b_n}")
    moved = (a_b != b_b) or (a_t != b_t)
    changed = set(a_b) != set(b_b)
    print(f"#   funnel MOVED   ({a_t} -> {b_t} files): {moved}")
    print(f"#   verdict CHANGED ({sorted(a_b)} -> {sorted(b_b)}): {changed}")
    print(f"#   UNKNOWN ADDED   ({sum(a_n.values())} -> {sum(b_n.values())}): "
          f"{sum(b_n.values()) - sum(a_n.values())}")

    shutil.rmtree(FIX, ignore_errors=True)
    if not (moved and changed):
        print("# PLANT FAILED: the arm's number did not move with its subject")
        return 1
    print("# PLANT PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
