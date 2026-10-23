#!/usr/bin/env python3
"""`one_run()` -- the in-process `run` -- and its plumbing, measured.

    .venv/bin/python .agents/slop/corpuslock/onerun.py

`checks/differ.py`'s `clean_run` used to spawn `differ.py run` as a SUBPROCESS. It cannot
any more: `run` holds the corpus lock, and the lock is held by the process that writes the
artifacts, so a `run` in a child would be a second writer.

THIS MEASURES THE PLUMBING WITHOUT A 271-SECOND CORPUS RUN: `cmd_run` is REPLACED by a
stub, and the three things `one_run()` promises are checked -- the return code comes back,
the child's two streams are swallowed unless the run FAILED, and an exception becomes a
non-zero code instead of a traceback that kills the `repro`.

The real `cmd_run` is exercised by `.agents/slop/corpuslock/plant.py`.
"""
import importlib.util
import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load():
    spec = importlib.util.spec_from_file_location("differ_onerun", ROOT / "checks/differ.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    differ = load()
    checks = []

    differ.cmd_run = lambda _a: (print("stdout from the run"), print("stderr from the run",
                                                                    file=sys.stderr), 0)[-1]
    out = io.StringIO()
    sys.stdout, keep = out, sys.stdout
    try:
        rc = differ.one_run()
    finally:
        sys.stdout = keep
    checks.append(("a successful run returns 0", rc == 0))
    checks.append(("the run's stdout is swallowed", "stdout from the run" not in out.getvalue()))
    checks.append(("the run's stderr is swallowed", "stderr from the run" not in out.getvalue()))

    differ.cmd_run = lambda _a: (print("the run failed"), print("why it failed", file=sys.stderr), 1)[-1]
    err = io.StringIO()
    sys.stderr, keep = err, sys.stderr
    try:
        rc = differ.one_run()
    finally:
        sys.stderr = keep
    checks.append(("a failed run returns its code", rc == 1))
    checks.append(("a failed run's stderr is RE-EMITTED", "why it failed" in err.getvalue()))

    def boom(_a):
        raise RuntimeError("the run exploded")

    differ.cmd_run = boom
    err = io.StringIO()
    sys.stderr, keep = err, sys.stderr
    try:
        rc = differ.one_run()
    finally:
        sys.stderr = keep
    checks.append(("an exception becomes a non-zero code, not a traceback", rc != 0))
    checks.append(("the exception is named", "the run exploded" in err.getvalue()))

    ok = True
    for why, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {why}")
        ok = ok and good
    print(f"one_run: {'GREEN' if ok else 'RED'} ({sum(g for _, g in checks)}/{len(checks)})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
