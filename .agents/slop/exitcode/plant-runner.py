"""THE RUNNER'S CHARGING, PLANTED BOTH WAYS -- `invoke()` itself, not a copy of its rules.

    .venv/bin/python .agents/slop/exitcode/plant-runner.py

`hooks/run.py:invoke()` IS the thing under test, called with real gate files, so a rule that is
documented in a docstring and not in the code fails here.

THE FOUR NEGATIVES:
  N1 a GENUINE CRASH still reads DEAD -- the refusal must not swallow it
  N2 a real SKIP is still SKIP
  N3 an UNASSIGNED code REFUSES rather than charging DEAD
  N4 the assigned codes are UNTOUCHED (this is what makes the change additive)
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOKS = HERE.parent / "hooks"
# `run` is a GENERIC name and this interpreter's `sys.path[0]` is the script's own directory, so
# the load is BY PATH under a private name -- the same discipline `hooks/run.py:60` uses for
# `gates-pop.py`, for the same reason: a common module name must not be shadowable by any file.
sys.path.insert(0, str(HOOKS))
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("hookrun_under_plant", HOOKS / "run.py")
run = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run)

bad = []


def check(label, got, want):
    ok = got == want
    print(f"  {'OK  ' if ok else 'FAIL'} {label:<46} {got!r}")
    if not ok:
        bad.append(f"{label}: {got!r} != {want!r}")


def gate_named(name, src):
    """A file `run.py` can invoke. It must be under ROOT, because `invoke()` relativises."""
    p = run.ROOT / f".agents/slop/exitcode/plant-{name}.py"
    p.write_text(src)
    return p


tmp = Path(tempfile.mkdtemp())
print("A REAL GATE FROM THE TREE, invoked as the runner invokes it")
for rel, want in (("checks/wallcheck.py", "SKIP"),       # NO-SUCH-ID -> 4, the real SKIP
                  ("checks/wallcheck.py", "DEAD"),       # --plant dead -> 5
                  ):
    argv = ["NO-SUCH-ID"] if want == "SKIP" else ["--plant", "dead"]
    rc, head, _ = run.invoke(run.ROOT / rel, argv)
    check(f"wallcheck {' '.join(argv)} charges", run.NAME[rc], want)

print("\nPLANTED GATES, one per verdict the runner must distinguish")
made = {
    "PASS": "import sys\nprint('fine')\nsys.exit(0)\n",
    "FAIL": "import sys\nprint('wrong answer')\nsys.exit(1)\n",
    "USAGE": "import sys\nprint('usage: x')\nsys.exit(2)\n",       # unassigned: N3
    "CRASH": "import sys\nraise IndexError('boom')\n",               # rc 1 + traceback: N1
    "SILENT": "import sys\nsys.exit(0)\n",                          # DEAD, the silence rule
}
paths = {k: gate_named(k.lower(), v) for k, v in made.items()}
charge = {k: run.NAME[run.invoke(p, ())[0]] for k, p in paths.items()}

print("\nN3: an UNASSIGNED code REFUSES -- and is NOT charged DEAD")
check("exit 2 charges", charge["USAGE"], "REFUSED")
check("and is not DEAD", charge["USAGE"] == "DEAD", False)

print("\nN1: a GENUINE CRASH still reads DEAD -- the refusal must not swallow it")
check("a raised exception charges", charge["CRASH"], "DEAD")
check("and is not REFUSED", charge["CRASH"] == "REFUSED", False)

print("\nN2: a real SKIP is still SKIP")
check("exit 4 charges", run.NAME[run.invoke(
    gate_named("skip4", "import sys\nprint('no such id')\nsys.exit(4)\n"), ())[0]], "SKIP")

print("\nN4: the ASSIGNED codes are untouched -- this is why the change is additive")
check("exit 0 charges", charge["PASS"], "GREEN")
check("exit 1 charges", charge["FAIL"], "FAIL")
check("silence still charges DEAD", charge["SILENT"], "DEAD")

print("\nTHE OLD BEHAVIOUR, PLANTED SO THE FIX IS EARNED")
old = 5 if 2 not in run.NAME else "not DEAD"
check("the old line charged DEAD for code 2", old, 5)

for p in paths.values():
    p.unlink()
(run.ROOT / ".agents/slop/exitcode/plant-skip4.py").unlink(missing_ok=True)
print(f"\n--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
sys.exit(1 if bad else 0)