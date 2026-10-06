#!/usr/bin/env python3
"""Two-state plant for `checks/corpus-figure.py`, on COPIES.

`runs/graphcmp/D/` is never touched: two throwaway roots are built under
`.agents/slop/figure2/plant/`, each holding a COPY of the figure, its two sibling
loaders (`devpin.py`, `differ.py`), a SYMLINK to the real `.agents` (so
`graphcmp.py` and `load_tinygrad` behave identically) and its OWN
`runs/graphcmp/D/D0-run-summary.txt`.

The only variable between the two roots is ONE pin in that summary:
`selfcheck`, a space-bearing PIN THAT CARRIES THE RUN'S VERDICT
(`"# SELFCHECK: OK"`). It is the exact shape the old `^(\\S+)=(\\S+)$` regex could
not parse. REAL = the recorded summary byte-for-byte; BROKEN = the one token
`OK` -> `FAIL`. Both states are run with the same interpreter and `DEV=CPU`.
"""
from __future__ import annotations
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
PLANT = HERE / "plant"
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
PY = str(ROOT / ".venv/bin/python")

# THE TWO ROOTS AND THE SUMMARY EACH CARRIES. `checks/corpus-figure.py` reads
# `runs/graphcmp/D/D0-run-summary.txt` under its OWN root, so each shadow root must carry that
# exact path/name or the plant tests nothing. DECLARED here, USED by `make_root`/`main`, and
# `checks/no-txt.py` loads `declared()` by path -- so the carve-out for these two forced `.txt`
# moves WITH the name instead of going stale behind it.
ROOTS = ("real", "broken")
SUMMARY_REL = "runs/graphcmp/D/D0-run-summary.txt"


def declared() -> set[str]:
    """The `.txt` this plant writes, repo-relative. `checks/no-txt.py` loads it by path."""
    return {str((PLANT / r / SUMMARY_REL).relative_to(ROOT)) for r in ROOTS}


def make_root(name: str, summary_text: str) -> pathlib.Path:
    root = PLANT / name
    if root.exists():
        shutil.rmtree(root)
    (root / "checks").mkdir(parents=True)
    for f in ("corpus-figure.py", "devpin.py", "differ.py"):
        shutil.copy2(ROOT / "checks" / f, root / "checks" / f)
    (root / ".agents").symlink_to(ROOT / ".agents")
    d = root / SUMMARY_REL
    d.parent.mkdir(parents=True)
    d.write_text(summary_text)
    return root


def run(root: pathlib.Path) -> tuple[int, str]:
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {
        "DEV": "CPU", "LC_ALL": "C"}
    got = subprocess.run([PY, str(root / "checks/corpus-figure.py")],
                         env=env, capture_output=True, text=True)
    line = next((ln for ln in got.stdout.splitlines() if ln.startswith("RUN HEALTH")), "")
    return got.returncode, line


def main() -> int:
    real = SUMMARY.read_text()
    assert "selfcheck=# SELFCHECK: OK" in real, "the pin under plant is not in the summary"
    broken = real.replace("selfcheck=# SELFCHECK: OK", "selfcheck=# SELFCHECK: FAIL", 1)
    assert broken != real

    # THE REAL SUMMARY IS NOT MUTATED -- prove it before and after.
    before = SUMMARY.read_bytes()
    rc_green, line_green = run(make_root(ROOTS[0], real))
    rc_red, line_red = run(make_root(ROOTS[1], broken))
    assert SUMMARY.read_bytes() == before, "runs/graphcmp/D/ WAS MUTATED -- abort"

    print(f"GREEN STATE (real pin)   : rc={rc_green}")
    print(f"  {line_green}")
    print(f"RED STATE   (selfcheck->FAIL): rc={rc_red}")
    print(f"  {line_red}")
    ok = rc_green == 0 and "OK -- 17 of 17 pins green" in line_green \
        and rc_red == 1 and "**FAILED**" in line_red and "selfcheck=# SELFCHECK: FAIL" in line_red
    print(f"PLANT: {'TWO STATES DISTINGUISHABLE' if ok else 'AMBIGUOUS -- FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
