#!/usr/bin/env python3
"""Two-state check of the landed fix in `checks/substrate.py`, PYTHON ONLY, `bend` never run.

BEFORE the fix (captured in `before-*.out`, by `repro.py`):
  * `.py` (no instrument)          -> `SUBSTRATE CLEAN ... each judged`, rc 0
  * `sz.c` with the probe GONE     -> `SUBSTRATE CLEAN ... each judged`, rc 0   (an instrument DEAD)
  * `-n` on the same `sz.c`        -> `SKIP-VERDICT`, `NAMES CLEAN`, rc 0        (the lane is HIDDEN)
AFTER:
  * `.py`                          -> `SUBSTRATE REFUSED`, rc 3, no `CLEAN`
  * `sz.c` with the probe GONE     -> `SUBSTRATE REFUSED`, rc 3, `NO INSTRUMENT`
  * `-n` on the same `sz.c`        -> `NO INSTRUMENT`, `SUBSTRATE REFUSED`, rc 3  (no longer hidden)
and a live `.c` pair (probe present) still reads `WARM`/`SUBSTRATE CLEAN`, rc 0.
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


def main() -> int:
    bad: list[str] = []

    def check(name: str, got: bool, want: bool) -> None:
        print(f"  {name:<52} {'OK' if got == want else 'UNEXPECTED'}")
        if got != want:
            bad.append(name)

    # 1. no-instrument class, live
    rc, out = run("checks/substrate.py")
    (OUT / "after-2-no-instrument-forced.out").write_text(out)
    check("no-instrument: rc==3", rc == 3, True)
    check("no-instrument: SUBSTRATE REFUSED", "SUBSTRATE REFUSED" in out, True)
    check("no-instrument: no SUBSTRATE CLEAN", "SUBSTRATE CLEAN" not in out, True)

    # 2. planted dead lane
    if not PROBE.exists():
        print("!! probe already absent; cannot run the plant safely")
        return 1
    try:
        os.rename(PROBE, HIDDEN)
        rc_f, out_f = run("tinybendygrad/runtime/sz.c")
        rc_n, out_n = run("-n", "tinybendygrad/runtime/sz.c")
    finally:
        os.rename(HIDDEN, PROBE)
    (OUT / "after-1-plant-full.out").write_text(out_f)
    (OUT / "after-1-plant-n.out").write_text(out_n)
    check("plant full: rc==3", rc_f == 3, True)
    check("plant full: NO INSTRUMENT + REFUSED",
          "NO INSTRUMENT" in out_f and "SUBSTRATE REFUSED" in out_f, True)
    check("plant full: no SUBSTRATE CLEAN", "SUBSTRATE CLEAN" not in out_f, True)
    check("plant -n: rc==3", rc_n == 3, True)
    check("plant -n: NO INSTRUMENT (was hidden)",
          "NO INSTRUMENT" in out_n and "SKIP-VERDICT" not in out_n, True)
    check("plant -n: no NAMES CLEAN", "NAMES CLEAN" not in out_n, True)

    # 3. live cc pair, unchanged
    rc_l, out_l = run("tinybendygrad/runtime/dtype.c", "tinybendygrad/runtime/sz.c")
    (OUT / "after-live-c.out").write_text(out_l)
    check("live cc pair: rc==0", rc_l == 0, True)
    check("live cc pair: CLEAN, no-instrument=0",
          "SUBSTRATE CLEAN" in out_l and "no-instrument=0" in out_l, True)

    print(f"\n-- {'ALL STATES OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
