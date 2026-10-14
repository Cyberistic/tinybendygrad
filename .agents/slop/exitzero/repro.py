#!/usr/bin/env python3
"""Reproduce the two inherited defects in `checks/substrate.py`, with the exact strings.

DEFECT 2 (live, no plant): `tally["none"] > 0` AND `findings == 0` -> prints
`SUBSTRATE CLEAN ... each judged by its OWN instrument` and exits 0. Any file the router
cannot judge reaches this: a `.py`, or a `.c` whose context produced nothing.

DEFECT 1 (-n short-circuit): `-n` skips a routed file BEFORE the instrument is consulted
(`if opts.names_only and inst != "none": ... continue`), so a DEAD lane is invisible in `-n`
and only the full run prints `NO INSTRUMENT`. The plant points the `cc` probe at an absent
path (`checks/c-context.bend` renamed aside, restored in `finally`) and runs the SAME file
both ways.

PYTHON ONLY; `bend` is never run (the plant makes `Ctx.ok()` short-circuit on the missing
probe). Live tree restored; nothing staged.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROBE = ROOT / "checks/c-context.bend"
HIDDEN = ROOT / "checks/.c-context.bend.PLANTOFF"
PY = ".venv/bin/python"
OUT = ROOT / ".agents/slop/exitzero"


def run(*args: str) -> tuple[int, str]:
    r = subprocess.run([PY, "checks/substrate.py", *args], cwd=ROOT,
                       capture_output=True, text=True)
    return r.returncode, r.stdout


def verdict_lines(out: str) -> list[str]:
    keys = ("NO INSTRUMENT", "SKIP-VERDICT", "SUBSTRATE CLEAN", "NAMES CLEAN",
            "SUBSTRATE NOT CLEAN", "ROUTE", "POPULATION", "UNJUDGED")
    return [l for l in out.splitlines() if any(l.startswith(k) for k in keys)]


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    # ---- DEFECT 2, live: a class with no instrument at all --------------------
    rc, out = run("checks/substrate.py")
    (OUT / "defect2-no-instrument-forced.out").write_text(out)
    print("== DEFECT 2 (live; `.py` has no instrument class) ==")
    print(f"   rc={rc}")
    for l in verdict_lines(out):
        print(f"   {l[:120]}")
    print(f"   -> CLEAN printed? {'SUBSTRATE CLEAN' in out}   rc==0? {rc == 0}")
    print()

    # ---- DEFECT 1, planted: point the cc probe at an absent path --------------
    if not PROBE.exists():
        print("!! probe absent before the plant; refusing to run the plant")
        return 1
    rc_live_full, out_live = (None, "")
    try:
        os.rename(PROBE, HIDDEN)
        rc_full, out_full = run("tinybendygrad/runtime/sz.c")
        rc_n, out_n = run("-n", "tinybendygrad/runtime/sz.c")
    finally:
        os.rename(HIDDEN, PROBE)
    (OUT / "defect1-plant-full.out").write_text(out_full)
    (OUT / "defect1-plant-n.out").write_text(out_n)

    print("== DEFECT 1 (planted: `checks/c-context.bend` absent -> cc lane DEAD) ==")
    print("   FULL run on sz.c:")
    print(f"     rc={rc_full}")
    for l in verdict_lines(out_full):
        print(f"     {l[:120]}")
    print("   -n run on the SAME file:")
    print(f"     rc={rc_n}")
    for l in verdict_lines(out_n):
        print(f"     {l[:120]}")
    print(f"   -> full: NO INSTRUMENT+'SUBSTRATE CLEAN'? "
          f"{'NO INSTRUMENT' in out_full and 'SUBSTRATE CLEAN' in out_full}  rc==0? {rc_full == 0}")
    print(f"   -> -n hides the dead lane? "
          f"{'NO INSTRUMENT' not in out_n}  (SKIP-VERDICT only)  rc==0? {rc_n == 0}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
