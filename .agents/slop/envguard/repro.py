#!/usr/bin/env python3
"""Reproduce env-precond.py's absence crash WITHOUT touching the live tree.

WHY A MIRROR AND NOT A MOVE. `runs/graphcmp/D/` is another unit's live artifact, and
the live tree is mid-run. So this builds a temp ROOT that is byte-identical to the
one the gate expects -- the three PINS sources are SYMLINKED to the real files, and
`checks/env-precond.py` is COPIED so its `parents[1]` resolves to the mirror -- and
then drives the real CLI with `runs/graphcmp/D` absent. Same code, same file:line,
same exception; the real tree is read-only.

TWO STATES, because a guard proves nothing without the other half:
  ABSENT  -- no runs/graphcmp/D at all
  PRESENT -- runs/graphcmp/D symlinked to the real one
"""
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

REAL = pathlib.Path(__file__).resolve().parents[3]
PINS = ("checks/differ.py", ".agents/slop/graphcmp.py", ".agents/slop/graphcmp-oracle.py")
PY = REAL / ".venv" / "bin" / "python"
GATE = "checks/env-precond.py"


def mirror(absent: bool) -> pathlib.Path:
    td = pathlib.Path(tempfile.mkdtemp(prefix="envprecond-"))
    for rel in PINS:
        dst = td / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(REAL / rel, dst)
    (td / "checks").mkdir(parents=True, exist_ok=True)
    shutil.copy2(REAL / GATE, td / GATE)
    if not absent:
        (td / "runs/graphcmp").mkdir(parents=True, exist_ok=True)
        os.symlink(REAL / "runs/graphcmp/D", td / "runs/graphcmp/D")
    return td


def run(td: pathlib.Path, *argv: str) -> tuple[int, str, str]:
    r = subprocess.run([str(PY), str(td / GATE), *argv], capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def main() -> int:
    for absent in (True, False):
        state = "ABSENT" if absent else "PRESENT"
        td = mirror(absent)
        try:
            print(f"===== state={state} : {td}  (runs/graphcmp/D {'MISSING' if absent else 'symlinked'})")
            for argv in (["--check"], ["--record"], ["--declare"]):
                rc, out, err = run(td, *argv)
                exc = next((l.strip() for l in err.splitlines() if l.strip().endswith("Error")
                            or l.strip().startswith("FileNotFoundError")
                            or "Error:" in l.strip()), "")
                print(f"  {argv[0]:<10} rc={rc}  stdout[0]={out.splitlines()[:1]}  "
                      f"traceback={'YES' if 'Traceback' in err else 'no'}"
                      + (f"  {err.strip().splitlines()[-1]}" if err.strip() else ""))
                if "Traceback (most recent call last)" in err:
                    frame = [l for l in err.splitlines() if l.strip().startswith("File \"")]
                    print(f"      RAISER: {frame[-1].strip() if frame else '?'}  ->  {err.strip().splitlines()[-1]}")
            print()
        finally:
            shutil.rmtree(td)
    return 0


if __name__ == "__main__":
    sys.exit(main())
