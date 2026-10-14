#!/usr/bin/env python3
""".agents/slop/slowgate/oracle_f64-plant.py -- THE `checks/oracle_f64.py` REFUSAL PLANT, RUN BY HAND.

    .venv/bin/python .agents/slop/slowgate/oracle_f64-plant.py            # expect REFUSED, exit 3
    .venv/bin/python .agents/slop/slowgate/oracle_f64-plant.py --expect N # N=0 to see it FAIL

Two cases and no others, because the claim is narrow:

  1. `python checks/oracle_f64.py` with NO argv must print `REFUSED`, exit 3, and print NO
     TRACEBACK. That is the exact command `gates/gate-surface.py` derives from `PLANTS = {3: []}`,
     so the plant `PLANTS` names and the defect being fixed are the same command.
  2. `python -c 'import oracle_f64'` under a FOREIGN `sys.argv` must NOT refuse. `checks/run-f64.sh:147`
     plants `import oracle_f64` into the harness copy of `portexec/oracle.py`, so this module is
     imported by a script whose argv is its own. A guard placed at module scope would break that
     lane and print a confident exit 3 naming the wrong file.

A GREEN HERE IS NOT THE LANE PASSING. This measures the refusal, not the f64 kernel, and it says so
on the last line: `gates/gate-surface.py` still reports `0` and `1` UNPLANTED for this file, and
that is the honest state -- neither can be synthesised without a real `mm-rows` off a port run.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
GATE = ROOT / "checks" / "oracle_f64.py"
IMPORT = (f"import sys; sys.path.insert(0, {str(ROOT / 'checks')!r}); "
          f"sys.argv = ['oracle.py', 'one-arg']; import oracle_f64; "
          f"print('imported with a foreign argv, refused =', oracle_f64.__name__)")


def run(cmd: list[str]) -> tuple[int, str]:
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=300)
    return r.returncode, r.stdout + r.stderr


def main() -> int:
    want = 0
    if len(sys.argv) > 2 and sys.argv[1] == "--expect":
        want = int(sys.argv[2])

    rc, blob = run([str(PY), str(GATE)])
    ok1 = (rc == 3 and "REFUSED" in blob and "Traceback" not in blob)
    print(f"[{'PASS' if ok1 else 'FAIL'}] NO ARGV: rc={rc} (want 3), REFUSED said={'REFUSED' in blob}, "
          f"traceback={'Traceback' in blob}")
    print("   " + blob.strip().replace("\n", "\n   "))

    rc2, blob2 = run([str(PY), "-c", IMPORT])
    ok2 = rc2 == 0 and "refused = oracle_f64" in blob2
    print(f"[{'PASS' if ok2 else 'FAIL'}] FOREIGN ARGV IMPORT: rc={rc2} (want 0), no refusal -- "
          f"`checks/run-f64.sh:147` imports this module and must not be broken by the guard")
    print("   " + blob2.strip().replace("\n", "\n   "))

    failed = (not ok1) + (not ok2)
    print(f"\n=== oracle_f64 refusal plant: {'PASS' if not failed else 'FAIL'} "
          f"(the f64 LANE is not measured here; 0 and 1 stay UNPLANTED) ===")
    return (1 if failed else 0) if want == 0 else want


if __name__ == "__main__":
    sys.exit(main())