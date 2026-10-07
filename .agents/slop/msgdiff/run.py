#!/usr/bin/env python3
"""run.py -- regenerate the msgdiff evidence in this directory. Not a gate: a REPLAYER.

    .venv/bin/python .agents/slop/msgdiff/run.py

It runs the REAL commits (read-only) rather than synthetic ones, because the three defects this
gate exists for are already in history and a guard proven on them is worth more than a guard
proven on a fixture. Writes `verdicts.rows`, `plant.out`, `range.out`, `range.err`.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = ROOT / ".venv" / "bin" / "python"
GATE = ROOT / "gates" / "msgdiff-gate.py"

# sha -> (expected rc, what the case is)
CASES = {
    "00b101574": (3, "the real defect: message says it deleted oracles259/plants.py; the diff does not"),
    "169ee6ac8": (0, "honest meta-report: says the predecessor's deletion claim is FALSE"),
    "601e7929c": (0, "uncheckable: a dead pid 2368 and config keys in no file"),
    "2b4cc9e48": (0, "uncheckable: pid 2368 / 30543, the mass-delete guard's own message"),
    "3c4ceeea3": (0, "honest: moved oracles259 residue, and says 'MOVED, NOT DELETED'"),
    "9b55d16a4": (0, "honest: removed the strays, including elf.bend.mut"),
}


def run(*args):
    return subprocess.run([str(PY), str(GATE), *args], capture_output=True, text=True)


def main():
    rows = ["sha\texpected_rc\trc\ttoken\twhat"]
    for sha, (want, why) in CASES.items():
        r = run("check", sha)
        got = r.returncode
        tok = "REFUSED" if got == 3 else ("PASS" if got == 0 else f"rc{got}")
        rows.append(f"{sha}\t{want}\t{got}\t{tok}\t{why}")
        print(f"{sha} {tok} rc={got}")

    plant = run("--plant")
    (HERE / "plant.out").write_text(plant.stdout)
    (HERE / "plant.err").write_text(plant.stderr)
    rows.append(f"plant\t0\t{plant.returncode}\t"
                f"{'PASS' if plant.returncode == 0 else 'FAIL'}\t6 states: honest, false, "
                f"uncheckable, ack, count-false, count-honest")

    rg = run("range", "--since=2026-10-06T12:00", "HEAD")
    (HERE / "range.out").write_text(rg.stdout)
    (HERE / "range.err").write_text(rg.stderr)
    summary = rg.stdout.strip().splitlines()[-1] if rg.stdout.strip() else "(no output)"
    rows.append(f"range\t3\t{rg.returncode}\t{'REFUSED' if rg.returncode == 3 else 'PASS'}\t"
                f"{summary}")

    (HERE / "verdicts.rows").write_text("\n".join(rows) + "\n")
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
