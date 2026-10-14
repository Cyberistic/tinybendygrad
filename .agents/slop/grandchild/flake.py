#!/usr/bin/env python3
"""Run `checks/bounded.py --selftest` N times, ONE AT A TIME, and record what failed.

Row shape, one per run: `run=<i> rc=<rc> token=<PASS|FAIL> load=<1-min loadavg> names=<...>`,
where `names` is the SEMI-COLON JOIN of the cases whose line said FAIL -- EMPTY on a green run,
so an empty field means "nothing failed" rather than "the field is missing".

ONE PROCESS AT A TIME, ALWAYS: this loop never overlaps itself and never runs beside another
selftest. It records `load` because a rate measured on a saturated host is a property of that
host, and a rate quoted without the load is a number with no scope.

    usage: .venv/bin/python .agents/slop/grandchild/flake.py N OUT.rows
"""
import os
import re
import subprocess
import sys
from pathlib import Path

SELFTEST = Path(__file__).resolve().parents[3] / "checks" / "bounded.py"
REPO = SELFTEST.parent.parent
SUMMARY = re.compile(r"=== selftest (PASS|FAIL): (\d+) case\(s\) run, (\d+) failed")
FAILED = re.compile(r"^\[\s*FAIL\] (.+)$", re.M)


def one(py: str) -> tuple[int, str, str]:
    r = subprocess.run([py, str(SELFTEST), "--selftest"], capture_output=True, text=True, cwd=REPO)
    out = r.stdout + r.stderr
    m = SUMMARY.search(out)
    # NO-SUMMARY IS ITS OWN VERDICT AND MUST NOT BE COUNTED AS A PASS: the first reading of this
    # driver ran 60 times with the repo root computed one level too shallow, every child exited 2
    # having printed nothing, and the summary still said "0 FAIL, rate 0.0000".
    return r.returncode, m.group(1) if m else "NO-SUMMARY", "; ".join(FAILED.findall(out))


def main() -> int:
    n, dest, py = int(sys.argv[1]), Path(sys.argv[2]), sys.executable
    rows = []
    with dest.open("w") as fh:
        fh.write("# run rc token load names\n")
        for i in range(1, n + 1):
            rc, token, names = one(py)
            rows.append((i, rc, token, names))
            fh.write(f"run={i} rc={rc} token={token} load={os.getloadavg()[0]:.2f} names={names}\n")
            fh.flush()
            print(f"run {i:3d} rc={rc} {token}" + (f"  <-- {names}" if names else ""), flush=True)
    bad = [r for r in rows if r[2] == "FAIL"]
    dead = [r for r in rows if r[2] != "PASS"]
    print(f"\n=== {len(rows)} runs, {len(bad)} FAIL, rate {len(bad) / len(rows):.4f}"
          + (f", and {len(dead)} runs produced no verdict at all" if dead else ""))
    for r in bad:
        print(f"    run {r[0]}: {r[3]}")
    return 1 if dead else 0


if __name__ == "__main__":
    sys.exit(main())