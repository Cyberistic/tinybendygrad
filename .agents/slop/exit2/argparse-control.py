#!/usr/bin/env python3
"""CONTROL: WHY `checks/differ.py` EXITS 2 WHEN THE EDGE RUNS IT BARE.

`gates/edge-trace.rows` carries the row
    checks/differ.py   RAN-UNASSIGNED   UNASSIGNED   UNASSIGNED(2)   2   ...
and `gates/edge-runner.py:386` says why: *"bare `differ.py` exits 2 because it has NO BARE
MODE -- it is a mode selector with four"*.

**`checks/differ.py` IS NOT RUN HERE.** It is on this unit's do-not-run list. What this file
reproduces is the SHAPE of `checks/differ.py:1892-1910` -- an `ArgumentParser` with
`add_subparsers(required=True)` -- in a scratch file of its own, so the exit code is observed
rather than assumed.

THE POINT OF THE CONTROL. `argparse` is the ONE mechanism by which an instrument reaches 2
WITHOUT ITS SOURCE MENTIONING 2. So the number 2 is a property of the CALLER's mistake, not
of the instrument's verdict, and a caller reading only `$?` cannot tell it from an
instrument that CHOSE 2.
"""
import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# THE SHAPE OF `checks/differ.py:1892-1910`: four subcommands, all required.
SCRATCH = HERE / "argparse-shape.py"
SCRATCH.write_text(
    "import argparse\n"
    "ap = argparse.ArgumentParser(prog='checks/differ.py')\n"
    "sub = ap.add_subparsers(dest='cmd', required=True)\n"
    "for name in ('run', 'repro', 'snap', 'plant'):\n"
    "    sub.add_parser(name)\n"
    "ap.parse_args()\n"
    "print('REACHED THE BODY -- argparse did not refuse')\n"
)


def main():
    r = subprocess.run([sys.executable, str(SCRATCH)], capture_output=True, text=True)
    print(f"bare invocation  : rc={r.returncode}")
    print(f"  stderr tail    : {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ''}")
    r2 = subprocess.run([sys.executable, str(SCRATCH), "run"], capture_output=True, text=True)
    print(f"valid invocation : rc={r2.returncode}  stdout={r2.stdout.strip()!r}")
    print()
    print("READING: argparse's OWN usage exit is 2. The instrument's own source never mentions")
    print("2 in this case, so a census that reads the source alone CANNOT see this path -- it")
    print("sees 'import argparse' and infers it. A caller reading only `$?` sees 2 and cannot")
    print("tell a MIS-CALLED instrument from one that CHOSE 2.")
    return 0 if r.returncode == 2 and r2.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
