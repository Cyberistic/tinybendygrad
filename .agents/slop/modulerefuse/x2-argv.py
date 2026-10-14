#!/usr/bin/env python3
"""The argv matrix, MEASURED. rc read from the process, never from a pipe.

    .venv/bin/python .agents/slop/modulerefuse/x2-argv.py

THE THREE ARGV CASES AND WHY ONLY THESE THREE. A gate's ENTRY has exactly three interesting points
before it measures anything: no argument at all, `--help` (which is what a reader lands on), and an
argument the gate does not accept. `AGENTS.md` opens every gate citation with "run `--help` before
trusting one", so `--help` is not a convenience here -- it is the reader's first contact, and a gate
whose `--help` answers 3 has a help that is a refusal.

`sys.exit(main())` and `sys.exit(main(sys.argv[1:]))` are both entry shapes; this file reports the
first line of stdout AND stderr SEPARATELY, because a sibling unit's first plant asserted
`input absent` in **stdout** while every one of these gates prints its refusal to **stderr**, and two
plants went red for that reason and not for the gates' reason.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 45

CASES = (("no argv", []), ("--help", ["--help"]), ("bad flag", ["--no-such-flag-9f3c"]))

TARGETS = sys.argv[1:] or [
    "checks/gate.py", "checks/nl-gate.py", "checks/nl-gate-noguard.py", "checks/dup-gate.py",
    "checks/dup-census.py", "checks/rn-gate.py", "checks/hermetic-census.py",
    "checks/git-index-guard.py", "checks/cl-port-gate.py", "checks/oracle_f64.py",
    "checks/norm_check.py", "checks/substrate.py",
]


def run(rel, argv):
    try:
        r = subprocess.run([str(PY), str(ROOT / rel), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "-", "-"
    out = next((l for l in (r.stdout or "").splitlines() if l.strip()), "")
    err = next((l for l in (r.stderr or "").splitlines() if l.strip()), "")
    return str(r.returncode), out, err


def main():
    print(f"{'gate':30} " + " ".join(f"{c[0]:>10}" for c in CASES) + "   first line (out|err)")
    print("-" * 132)
    for rel in TARGETS:
        cells, notes = [], []
        for _name, argv in CASES:
            rc, out, err = run(rel, argv)
            cells.append(rc)
            token = next((t for t in (out, err) if t), "")
            if token:
                notes.append(token[:56])
        same = len(set(cells)) == 1 and cells[0] not in ("TIMEOUT",)
        mark = "ALL-THREE-SAME" if same else "distinct"
        print(f"{rel:30} " + " ".join(f"{c:>10}" for c in cells) + f"   [{mark}] {notes[0] if notes else ''}")
    print("\n`ALL-THREE-SAME` means no argv can change the verdict: the three points a reader can "
          "reach are\nindistinguishable, which is the shape `AGENTS.md`'s --help prescription cannot "
          "see past.")
    return 0


if __name__ == "__main__":
    sys.exit(main())