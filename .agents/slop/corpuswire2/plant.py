#!/usr/bin/env python3
"""Two-state plant for the corpus/artifact check in `checks/corpus-figure.py`'s `run_health`.

`runs/graphcmp/D/` is never touched. Two throwaway roots are built under
`.agents/slop/corpuswire2/plant/`, each holding a COPY of the figure and its two sibling
loaders (`devpin.py`, `differ.py`), a SYMLINK to the real `.agents/` (so `graphcmp.py`,
`GRAPHS` and `load_tinygrad` behave identically) and its OWN `runs/graphcmp/D/D0-run-summary.txt`.

The only variable between the two roots is the artifact's `graphs=` value, which `run_health`
now compares to the LIVE corpus (`len(gc.GRAPHS) == 34`):

  real  the recorded summary byte-for-byte, `graphs=25`  -> MUST be RED, naming the gap
  agree `graphs=25` -> `graphs=34`, nothing else moved      -> MUST be GREEN, 17 of 17

The tree is moving: `len(gc.GRAPHS)` is read from the symlinked `.agents/slop/graphcmp.py`,
so this plant is correct only while the corpus is 34. A corpus growth makes BOTH states red
(the real one already is) -- which is the property the change exists to have.
"""
from __future__ import annotations
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
PY = str(ROOT / ".venv/bin/python")


def make_root(base: pathlib.Path, name: str, summary_text: str) -> pathlib.Path:
    # THE ROOTS LIVE IN A TEMPDIR, NOT UNDER THE REPO: the summary's own name is
    # `D0-run-summary.txt`, and a `.txt` anywhere the sweep can see it is a rule violation
    # regardless of whether it is a fixture.
    root = base / name
    (root / "checks").mkdir(parents=True)
    for f in ("corpus-figure.py", "devpin.py", "differ.py"):
        shutil.copy2(ROOT / "checks" / f, root / "checks" / f)
    (root / ".agents").symlink_to(ROOT / ".agents")
    d = root / "runs/graphcmp/D"
    d.mkdir(parents=True)
    (d / "D0-run-summary.txt").write_text(summary_text)
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
    assert "graphs=25" in real, "the artifact under plant does not carry graphs=25"
    agree = real.replace("graphs=25", "graphs=34", 1)
    assert agree != real

    before = SUMMARY.read_bytes()
    with tempfile.TemporaryDirectory(prefix="corpuswire2-plant-") as td:
        base = pathlib.Path(td)
        rc_red, line_red = run(make_root(base, "real", real))
        rc_green, line_green = run(make_root(base, "agree", agree))
    assert SUMMARY.read_bytes() == before, "runs/graphcmp/D/ WAS MUTATED -- abort"

    print(f"RED STATE   (artifact graphs=25, corpus declares 34): rc={rc_red}")
    print(f"  {line_red}")
    print(f"GREEN STATE (artifact graphs=34, corpus declares 34): rc={rc_green}")
    print(f"  {line_green}")
    ok = (rc_red == 1 and "**FAILED**" in line_red
          and "graphs=25 but the corpus DECLARES 34" in line_red
          and rc_green == 0 and "OK -- 17 of 17 pins green" in line_green)
    print(f"PLANT: {'TWO STATES DISTINGUISHABLE' if ok else 'AMBIGUOUS -- FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
