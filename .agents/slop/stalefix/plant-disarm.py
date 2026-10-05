#!/usr/bin/env python
"""PLANT a stale artifact set into a gate's output directory, then DISARM it by running the gate.

    .venv/bin/python .agents/slop/stalefix/plant-disarm.py

A claim that a run clears its own output is worth nothing until something has been left behind for
it to clear, so this plants bytes that CANNOT be mistaken for a run's own -- every planted file
carries the marker `PLANTED-BY-plant-disarm.py` -- and then asks two questions per site:

    armed?     is the plant still on disk?
    disarmed?  after one run of the gate, is every planted byte GONE and the directory holding
               exactly the generator's declared set?

TWO SITES, because they prove different halves of the fix.

  `gates/artifacts/wk-f32-gate/`  a REAL gate on the REAL tree, GREEN. This is the promote path:
      the planted files must be replaced by the run's OWN bytes, so this is where "staged then
      promoted" would show a mistake -- a run that promoted its temps onto the planted names would
      pass a test that only asked "were the markers gone".

  the repro gate                     a RED run. This is the discard path: nothing may be left,
      including a staged temp, because `_settle(False)` unlinks rather than promotes.

THE PLANTED SET IS THREE FILES, AND THE THIRD IS THE POINT: `bd.txt` is the published name the bug
was measured on, `gate.bin` is `bend -o`'s output, and `.tmp.bd.txt` is a temp left by a run that
was SIGKILLed. A `finally` cannot run under SIGKILL, so temps DO survive a killed run -- measured,
`gates/artifacts/beautiful-mnist-gate/` held `.tmp.bd.txt` and `.tmp.py.txt` after `bounded.py`
killed it at 2,130 MB. They are swept by the NEXT run's `_clear()`, which is what this plants one.
"""
import hashlib
import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

FIX = Path(__file__).resolve().parent
ROOT = FIX.parent.parent.parent
PY = ROOT / ".venv" / "bin" / "python"
PLANTED = b"PLANTED-BY-plant-disarm.py -- this is not a run's output\n"
PLANTS = ("bd.txt", "gate.bin", ".tmp.bd.txt")


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()[:12] if p.is_file() else None


def listing(d):
    return {q.name: sha(q) for q in sorted(d.iterdir()) if q.is_file()} if d.is_dir() else {}


def plant(d, note):
    d.mkdir(parents=True, exist_ok=True)
    for name in PLANTS:
        (d / name).write_bytes(PLANTED)
    print(f"  PLANTED into {d.relative_to(ROOT) if d.is_relative_to(ROOT) else d}: "
          + ", ".join(f"{n}={sha(d / n)}" for n in PLANTS) + f"   ({note})")
    return {n: sha(d / n) for n in PLANTS}


def disarm(label, d, before, run):
    print(f"  ARMED?   {'yes -- the plant is still on disk' if before else 'no'}")
    rc = run()
    now = listing(d)
    survivors = [n for n, h in before.items() if now.get(n) == h]
    fresh = sorted(n for n in now if not n.startswith(".tmp."))
    print(f"  run rc={rc}")
    print(f"  DISARMED? {'yes' if not survivors else 'NO -- ' + '|'.join(survivors) + ' survived'}"
          f"   published now: {'|'.join(fresh) or 'NOTHING'}")
    if any(n.startswith(".tmp.") for n in now):
        print(f"  TEMP LEFT {'|'.join(n for n in now if n.startswith('.'))}  <-- a settle that did "
              f"not run")
    return rc, not survivors, not any(n.startswith(".tmp.") for n in now)


def real_gate():
    print("\nA REAL GATE, GREEN: gates/artifacts/wk-f32-gate/")
    d = ROOT / "gates" / "artifacts" / "wk-f32-gate"
    before = plant(d, "the published name, bend -o's output, and a SIGKILL temp")
    rc, gone, notemp = disarm("real", d, before,
                              lambda: subprocess.run(
                                  [str(PY), str(ROOT / "gates" / "wk-f32-gate.py")],
                                  cwd=ROOT, capture_output=True).returncode)
    return rc == 0 and gone and notemp


def red_gate():
    print("\nA RED RUN: the repro gate, whose oracle is one row short")
    mod = importlib.util.spec_from_file_location("gk", ROOT / "gates" / "gatekit.py")
    gk = importlib.util.module_from_spec(mod)
    sys.modules["gk"] = gk
    mod.loader.exec_module(gk)
    art = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/"
               "stalefix-plant/repro")
    gk.ART, gk.BEND, gk.PY = art, ROOT / "bin" / "bend", PY

    def run(inputs):
        gate = gk.Gate("repro", bend=str(FIX / inputs[0]), oracle=str(FIX / inputs[1]), rows=3)
        return gate.run()

    run(("green.bend", "oracle.py"))           # a complete, correct previous run to leave behind
    d = art / "repro"
    before = plant(d, "on top of a GREEN run, so the red run has something stale to fail over")
    rc, gone, notemp = disarm("red", d, before,
                              lambda: run(("green.bend", "oracle-short.py")))
    return rc == 1 and gone and notemp


def main():
    print("# every planted byte carries PLANTED-BY-plant-disarm.py, so a survivor is unmistakable")
    ok = [real_gate(), red_gate()]
    print(f"\n# VERDICT: {'every plant disarmed, no temp survived' if all(ok) else 'A PLANT SURVIVED'}")
    return 0 if all(ok) else 1


if __name__ == "__main__":
    shutil.rmtree(Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/"
                       "stalefix-plant"), ignore_errors=True)
    sys.exit(main())
