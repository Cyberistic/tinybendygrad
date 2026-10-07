#!/usr/bin/env python3
"""Three-argv probe: what does each candidate do with (a) no argv, (b) --help, (c) a bad flag.

NO VERDICT IS INFERRED. Every cell is an OBSERVED exit code plus the first line of stderr, so
the module-scope/main() question is answered by what the PROCESS does, not by a column.

    .venv/bin/python .agents/slop/modulerefuse/probe.py            # all rows
    .venv/bin/python .agents/slop/modulerefuse/probe.py --write    # also .rows
"""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"

CANDIDATES = [
    "checks/gate.py",
    "checks/nl-gate.py",
    "checks/nl-gate-noguard.py",
    "checks/dup-gate.py",
    "checks/dup-census.py",
    "checks/rn-gate.py",
    "checks/hermetic-census.py",
    "checks/git-index-guard.py",
    "checks/norm_check.py",
    "checks/oracle_f64.py",
]

CASES = [("none", []), ("help", ["--help"]), ("bad", ["--no-such-flag-xyz"])]
TIMEOUT = 120


def probe(rel, argv):
    cmd = [str(PY), str(ROOT / rel), *argv]
    t0 = time.monotonic()
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", round(time.monotonic() - t0, 1)
    dt = round(time.monotonic() - t0, 1)
    err = [l for l in (r.stderr or "").splitlines() if l.strip()]
    return str(r.returncode), (err[0][:88] if err else ""), dt


def main():
    write = "--write" in sys.argv
    rows = []
    for rel in CANDIDATES:
        cells = [(name,) + probe(rel, argv) for name, argv in CASES]
        print(f"{rel}")
        for name, rc, err, dt in cells:
            print(f"   {name:5} rc={rc:>7}  {dt:>5}s  {err}")
        rows.append((rel, cells))
    if write:
        out = Path(__file__).parent / "probe.rows"
        out.write_text("".join(
            f"{rel}\t{name}\t{rc}\t{err}\n"
            for rel, cells in rows for name, rc, err, _dt in cells))
        print(f"\nwrote {out.name} ({len(rows) * len(CASES)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())