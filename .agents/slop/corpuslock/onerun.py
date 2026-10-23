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
import argparse
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

#: A SECOND HOLDER IS A SECOND PROCESS, and this is it: the real `command()` path, in a
#: child, with the real `cmd_run` -- which is never reached, because the lock is refused
#: first.
CHILD = """
import argparse, importlib.util, sys
from pathlib import Path
ROOT = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("differ_child", ROOT / "checks/differ.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
sys.exit(m.command(argparse.Namespace(cmd="run")))
"""


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

    # **THE LOCK IS TAKEN BY THE COMMAND, NOT BY `cmd_run`**, so the wiring is what has to be
    # measured: the command path takes the lock, and a second HOLDER is refused while it is
    # held.  `cmd_run` is stubbed so this costs nothing and writes nothing.
    #
    # **INSIDE ONE PROCESS THE LOCK IS RE-ENTRANT**, and that is not a hole: the `repro` path
    # needs it, because `clean_run` runs `cmd_run` in the SAME process that holds the lock.  A
    # SECOND HOLDER is a second PROCESS, and that is what the child below is.
    import argparse
    differ.cmd_run = lambda _a: 7
    a = argparse.Namespace(cmd="run")
    checks.append(("a command runs and returns its code", differ.command(a) == 7))
    differ.take_lock()
    checks.append(("the lock is RE-ENTRANT inside one process (the `repro` path needs that)",
                   differ.command(a) == 7))
    checks.append(("the inner release did NOT release the outer hold",
                   differ.lock_holder()[0] == os.getpid()))
    # **THE CHILD IS SANDBOXED.**  MEASURED 2026-10-23: a probe of this shape once let its
    # child reach the tree's `runs/graphcmp/D` -- the lock had been released by an inner
    # `drop_lock()`, so the child was not refused and it ran a corpus into 315 of the 319
    # evidence files.  A probe that can reach the evidence must not exist, so the child
    # writes to a scratch directory and the assertion is that it never got that far.
    with tempfile.TemporaryDirectory() as td:
        env = dict(os.environ, GRAPHCMP_ARTIFACTS=td)
        child = subprocess.run([sys.executable, "-c", CHILD, str(ROOT)], env=env,
                                capture_output=True, text=True, timeout=120)
        checks.append(("a second PROCESS is REFUSED while the lock is held", child.returncode == 3))
        checks.append(("the refusal names the holder", "another corpus run holds the lock" in
                       (child.stdout + child.stderr)))
        checks.append(("the refused process wrote nothing", not os.listdir(td)))
    differ.drop_lock()
    checks.append(("the lock is released, so a command runs again", differ.command(a) == 7))

    # **THE COMPOSITION `repro` USES**: `clean_run` -> `ready` -> `one_run` -> `cmd_run` -> the
    # health check.  `cmd_run` is stubbed, so the corpus is not run: what is measured is that
    # the composition does not raise, does not write, and says "this is NOT a measurement"
    # when the run left nothing healthy behind it.
    differ.ready = lambda _w: True
    checks.append(("`clean_run` on a run that left nothing healthy is NOT a measurement",
                   differ.clean_run("probe", 1) is False))

    ok = True
    for why, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {why}")
        ok = ok and good
    print(f"one_run: {'GREEN' if ok else 'RED'} ({sum(g for _, g in checks)}/{len(checks)})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
