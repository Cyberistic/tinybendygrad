#!/usr/bin/env python3
"""The corpus lock, measured: take it, refuse a second holder, release it.

    .venv/bin/python .agents/slop/corpuslock/probe.py

Nothing here writes an artifact.  The lock directory is the only thing it touches, and it
removes it on the way out.
"""
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load():
    spec = importlib.util.spec_from_file_location("differ_probe", ROOT / "checks/differ.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CHILD = """
import importlib.util, sys
from pathlib import Path
ROOT = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("differ_child", ROOT / "checks/differ.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
r = mod.take_lock()
print("REFUSED" if r else "HELD")
if r: print(r)
"""


def main() -> int:
    differ = load()
    print(f"lock path : {differ.CORPUS_LOCK.relative_to(ROOT)}")
    print(f"holder now : {differ.lock_holder()}")

    refusal = differ.take_lock()
    print(f"take_lock : {'REFUSED: ' + refusal if refusal else 'HELD (this process)'}")
    if refusal:
        return 1
    print(f"holder now : {differ.lock_holder()} (pid {os.getpid()})")

    again = differ.take_lock()
    print(f"take_lock : {'REFUSED: ' + again if again else 'HELD (re-entrant, same process)'}")

    p = subprocess.run([sys.executable, "-c", CHILD, str(ROOT)], capture_output=True, text=True)
    print(f"child     : rc={p.returncode}")
    print(p.stdout.rstrip())

    differ.drop_lock()
    print(f"after drop: {differ.lock_holder()}")

    p = subprocess.run([sys.executable, "-c", CHILD, str(ROOT)], capture_output=True, text=True)
    print(f"child     : {p.stdout.splitlines()[0] if p.stdout else p.stderr.strip()}")
    differ.drop_lock()
    return 0


if __name__ == "__main__":
    sys.exit(main())
