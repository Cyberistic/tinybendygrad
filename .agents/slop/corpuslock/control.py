#!/usr/bin/env python3
"""THE CONTROL: WITH THE LOCK REMOVED, THE GATE's `run.gated` ROW GOES RED.

    .venv/bin/python .agents/slop/corpuslock/control.py

THE PLANT IS A COPY.  `checks/differ.py` is copied into a scratch tree and two lines are
edited IN THE COPY:

  * `take_lock` returns `None` without taking anything -- THE LOCK DOES NOT EXIST;
  * `_command` returns 0 without running -- so the second run neither refuses nor spends
    271 s compiling bends.

The gate is copied beside it, so the copy's `ROOT` is the scratch tree and the copy's
`singleton()` really does spawn the copy's `checks/differ.py run`.

WHAT IT PROVES.  A row that cannot go red is a label, and `differ.py`'s own PLANT 3 names
that shape.  The gate's `run.gated` row must read `SINGLETON` on the real tree and
`SHARED` here -- with the SAME comparator, the SAME control, and the same command.

THE REAL TREE IS NOT TOUCHED: every edit is on a copy under a temporary directory, and the
copy's summary is the real summary READ (never written).
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
SUMMARY = ROOT / "runs" / "graphcmp" / "D" / "D0-run-summary.txt"


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        (tmp / "checks").mkdir()
        (tmp / "gates").mkdir()
        shutil.copy2(ROOT / "checks" / "differ.py", tmp / "checks" / "differ.py")
        shutil.copy2(ROOT / "gates" / "corpusverdict-gate.py", tmp / "gates" / "corpusverdict-gate.py")
        shutil.copy2(ROOT / "gates" / "gatekit.py", tmp / "gates" / "gatekit.py")

        d = tmp / "checks" / "differ.py"
        src = d.read_text()
        edits = [
            ("    global _LOCK_FD\n    if _LOCK_FD is not None:",
             "    return None  # PLANTED: THE LOCK DOES NOT EXIST\n"
             "    global _LOCK_FD\n    if _LOCK_FD is not None:"),
            ("def _command(a):\n    if a.cmd == \"plant\":",
             "def _command(a):\n    return 0  # PLANTED: THE RUN DOES NOTHING\n"
             "    if a.cmd == \"plant\":"),
        ]
        for a, b in edits:
            assert src.count(a) == 1, (a, src.count(a))
            src = src.replace(a, b)
        d.write_text(src)

        p = subprocess.run([sys.executable, str(tmp / "gates" / "corpusverdict-gate.py"),
                            "--summary", str(SUMMARY)],
                           cwd=tmp, capture_output=True, text=True, timeout=300)
        rows = [ln for ln in p.stdout.splitlines() if ln.startswith(("run.gated", "control.singleton"))]
        for ln in rows:
            print(ln)
        ok = any("state=FAIL" in ln and "SHARED" in ln for ln in rows)
        print(f"# the planted gate rc={p.returncode}")
        print(f"# CONTROL {'PASSED' if ok else 'FAILED'} -- the row went RED without the lock")
        return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
