#!/usr/bin/env python3
"""TWO STATES FOR `plant.py`, IN THE ORDER THAT PROVES IT.

A plant that cannot go red is not a plant. This injects the PRE-FIX census behaviour -- the one the
old `census()` had -- into a census module the plant loads, and requires `plant_reach` to FAIL; it
then runs the same plant against an untouched census module and requires it to PASS. The only
difference between the two runs is the one function the fix introduced, `shared_tail`.

usage: .venv/bin/python .agents/slop/oracletxt/selftest.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("plant", HERE / "plant.py")


def run(p, m):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="oracletxt-selftest-"))
    try:
        return p.plant_reach(m, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def gate_rc(m):
    """Run the census's `--gate` branch over a tree whose only reader is a MOVED read."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="oracletxt-selftest-"))
    try:
        (tmp / "oracles/sub").mkdir(parents=True)
        (tmp / "oracles/sub/rows.txt").write_text("a=1\nb=2\n")
        (tmp / "gone/sub").mkdir(parents=True)
        reader = tmp / "reader.py"
        reader.write_text('OPEN = "gone/sub/rows.txt"\n')
        m.ROOT, m.ORACLES, m.code_files = tmp, tmp / "oracles", lambda: [reader]
        sys.argv = ["census", "--gate"]
        return m.main()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    p = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(p)

    # STATE 1 -- the PRE-FIX census: every absent-path reader was STALE. shared_tail always says the
    # sub-tree survived, so a namesake reads as a move and beat 2 must fail.
    broken = p.load()
    broken.shared_tail = lambda *_a: 2
    red = run(p, broken)

    # STATE 2 -- an untouched census module: the split holds, and the gate fires on the moved read.
    green_m = p.load()
    green = run(p, green_m)
    gate = gate_rc(green_m)

    ok = (not red) and green and gate == 1
    print(f"\n  {'PASS' if ok else 'FAIL'}  plant_reach is RED under the pre-fix census and GREEN "
          f"under the fix; `--gate` exits 1 on the moved read\n"
          f"        pre-fix: {'ALL GREEN -- the plant cannot go red!' if red else 'red; beat 2 caught the collapse'}"
          f"   fix: {'green' if green else 'RED'}   gate: rc={gate} (want 1)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
