#!/usr/bin/env python3
"""Plant `checks/no-txt.py`'s guard in five states and report the verdict token from `$?`.

The guard is not a side-effect of the files it excuses: STATE A plants a fresh `.txt` the
carve-outs do not name and the guard must SEE it. STATE B removes it. STATE C and D prove each
carve-out is the DECLARED NAME and not the DIRECTORY or the SHAPE. STATE E proves the 0-byte
carve-out LAPSES the moment its file gains content -- the property that keeps a declaration from
going stale behind a writer.

    .venv/bin/python .agents/slop/txtresidual/probe.py
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = str(Path(__file__).resolve().parents[3])
GUARD = ["python", "checks/no-txt.py"]
PY = os.path.join(ROOT, ".venv/bin/python")


def run_guard() -> tuple[int, str]:
    p = subprocess.run([PY, *GUARD[1:]], cwd=ROOT, capture_output=True, text=True)
    return p.returncode, p.stdout


def names(out: str) -> list[str]:
    return [ln.strip() for ln in out.splitlines() if ln.startswith("    ") and ln.strip()]


def state(label: str, path: str, content: bytes | None) -> tuple[int, str]:
    full = os.path.join(ROOT, path)
    if content is None:
        if os.path.exists(full):
            os.unlink(full)
    else:
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(content)
    rc, out = run_guard()
    seen = path in names(out)
    print(f"{label:<46} rc={rc}  {'SEEN' if seen else 'silent'}")
    return rc, out


def main() -> int:
    ok = True
    fresh = "tinybendygrad/txtresidual-probe.txt"
    orphan = "runs/graphcmp/D/ORPHAN.txt"
    empty = "oracles/txtresidual-empty-probe.txt"
    bd = "oracles/rows-bd.txt"
    bd_before = open(os.path.join(ROOT, bd), "rb").read()

    # A: a fresh .txt the carve-outs do not name -> the guard must SEE it.
    rc, out = state("A fresh .txt (must be SEEN)", fresh, b"x\n")
    ok &= rc == 1 and fresh in names(out)
    # B: removed -> the guard must be silent about it.
    rc, out = state("B removed (must be silent)", fresh, None)
    ok &= fresh not in names(out)
    # C: an orphan under the graphcmp DIR but not in declared() -> still HARD.
    rc, out = state("C orphan under runs/graphcmp/D (must be SEEN)", orphan, b"x\n")
    ok &= rc == 1 and orphan in names(out)
    state("C removed", orphan, None)
    # D: an EMPTY .txt whose NAME is not in LEFT_EMPTY -> still HARD.
    rc, out = state("D empty but undeclared (must be SEEN)", empty, b"")
    ok &= rc == 1 and empty in names(out)
    state("D removed", empty, None)
    # E: give the DECLARED 0-byte remnant content -> the carve-out must LAPSE.
    rc, out = state("E declared remnant gains content (must be SEEN)", bd, b"one row\n")
    ok &= rc == 1 and bd in names(out)
    with open(os.path.join(ROOT, bd), "wb") as f:      # restore the tracked 0 bytes exactly
        f.write(bd_before)

    rc, out = run_guard()
    restored = open(os.path.join(ROOT, bd), "rb").read() == bd_before
    print(f"{'ZZ restored (must be CLEAN)':<46} rc={rc}  rows-bd bytes intact={restored}")
    ok &= rc == 0 and restored
    print(f"\nVERDICT: {'FIVE STATES DISTINGUISHABLE' if ok else 'AMBIGUOUS -- FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
