#!/usr/bin/env python3
"""THE PLANT. Two states of `checks/run-port-mm.sh`'s required input, and the two
verdicts must be DISTINGUISHABLE IN THE TOKEN AND THE EXIT CODE, not just in prose.

  ABSENT   the oracle is not there.  The gate's step 0 must REFUSE -- print
           `REFUSED, NOT A VERDICT` and exit 3 -- and must NOT read as a lane
           failure, because a missing record is not the port being broken.
  PRESENT  the oracle is there.  The gate must get PAST step 0 and start its
           lanes; it may then fail on whatever else is missing, and THAT is the
           point: the failure it reaches is a failure, not a refusal.

The real script is COPIED to a scratch ROOT (it asserts `pyproject.toml` +
`tinybendygrad/` and computes ROOT from its own path), and the portexec machinery
is left ABSENT on purpose, so the PRESENT run never reaches `bend`.  Running the
live gate would invoke `bend`, which this unit must not do; the precondition this
plant exercises is reached BEFORE any bend, so the scratch tree measures exactly
the state under test and nothing else.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REAL = ROOT / "checks/run-port-mm.sh"
GATE = REAL.read_text()
SCRATCH = Path(tempfile.mkdtemp(prefix="runsgate-plant-"))


def build():
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    (SCRATCH / "checks").mkdir(parents=True)
    (SCRATCH / "tinybendygrad").mkdir()
    (SCRATCH / "pyproject.toml").write_text("")
    (SCRATCH / ".venv" / "bin").mkdir(parents=True)
    (SCRATCH / ".venv/bin/python").symlink_to(ROOT / ".venv/bin/python")
    (SCRATCH / "checks/run-port-mm.sh").write_text(GATE)
    shutil.copy2(ROOT / "checks/e2e-mm-oracle.json", SCRATCH / "checks/e2e-mm-oracle.json")


def run(label, expect):
    r = subprocess.run(["zsh", str(SCRATCH / "checks/run-port-mm.sh"), str(SCRATCH / "work")],
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    refused = "REFUSED, NOT A VERDICT" in out
    first = next((ln.strip() for ln in out.splitlines() if ln.strip()), "")
    ok = (r.returncode == 3 and refused) if expect == "REFUSE" else \
         (r.returncode != 3 and not refused)
    print(f"  {label:8} exit={r.returncode} refused={refused}  "
          f"first= {first[:70]!r}")
    return ok


def main():
    build()
    print(f"PLANT  real gate {REAL.relative_to(ROOT)}, scratch ROOT {SCRATCH}")
    (SCRATCH / "checks/e2e-mm-oracle.json").unlink()          # ABSENT state
    absent_ok = run("ABSENT", "REFUSE")
    # PRESENT: restore the input and re-run.
    shutil.copy2(ROOT / "checks/e2e-mm-oracle.json", SCRATCH / "checks/e2e-mm-oracle.json")
    present_ok = run("PRESENT", "RUN")
    print()
    print("PLANT PASS" if (absent_ok and present_ok) else "PLANT FAIL",
          "-- ABSENT refused with 3 and PRESENT did not")
    return 0 if (absent_ok and present_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
