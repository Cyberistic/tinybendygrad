#!/usr/bin/env python3
"""oracle_py.py -- WHICH PYTHON RUNS THE CPYTHON ORACLES. Decided here, once.

MEASURED 2026-10-03, and the reason this file exists. `rebase-gate.py` spawned its
CPython lanes with `sys.executable`, so the gate's VERDICT was a function of the LAUNCHER
rather than of the port:

    .venv/bin/python .agents/slop/tensor-gate.py | wc -l   ->  30
    python3           .agents/slop/tensor-gate.py | wc -l   ->   0  ModuleNotFoundError

The editable tinygrad install exists ONLY in .venv (3.12): `.venv/lib/python3.12/
site-packages/__editable__.tinygrad-0.14.0.pth`. PATH's python3 is 3.14 and has no .pth
at all. From that one ambiguity came THREE contradictory published claims in one day --
"PYTHONPATH blocks the oracles" (true under python3), "it's an editable install so it
never blocks" (true under .venv), and "8 of 31 gates are BROKEN on every run, 707 rows
blocked", which is FALSE and was measured under the wrong interpreter. So the
interpreter is PINNED, not inherited: a harness that cannot resolve the REPO's tinygrad
refuses to run rather than reporting zero rows, because a lane that printed nothing is
indistinguishable from a port that agrees.

THE FALSE POSITIVE THAT MAKES CASUAL CHECKING USELESS. `python3 -c "import tinygrad"`
run from the repo root SUCCEEDS and prints this repo's tinygrad/__init__.py -- not
because there is an install, but because sys.path[0] is '' and a `tinygrad/` sits in the
cwd. Two wrong conclusions came from exactly that. probe() therefore runs the import with
`-I` (isolated: cwd and script dir off sys.path, PYTHON* env ignored) and with cwd=SLOP,
which has no tinygrad/ beside it. Under those conditions the ONLY way to import tinygrad
is a real install, so a probe that passes means what it says.

Why a pin and not merely a detection: a detection still lets the run proceed under a
different interpreter, so the verdict still varies with the launcher. Pinning makes
`.venv/bin/python rebase-gate.py` and `python3 rebase-gate.py` answer identically, which
is the property the gate was missing. Set ORACLE_PY to override, and it is probed the
same way -- an override that cannot import tinygrad is refused like any other.
"""
import os
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
VENV_PY = REPO / ".venv" / "bin" / "python"
WANT = REPO / "tinygrad" / "__init__.py"

_PROBE = "import tinygrad, sys; print(tinygrad.__file__); print(sys.version.split()[0])"


def refuse(why):
  """Loud, and exit 2 -- distinct from the gate's own exit 1, so a caller can tell 'this
  run never happened' from 'this run happened and found a broken port'."""
  sys.stderr.write(f"\n{why}\n  Nothing was checked.\n\n")
  raise SystemExit(2)


def _clean_env():
  """Drop PYTHON* so an inherited PYTHONPATH cannot make the probe answer for itself."""
  return {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}


def probe(exe):
  """(tinygrad_path, version, error) for `exe`. error is None on success. -I plus
  cwd=HERE is what makes this immune to the cwd false positive documented above."""
  try:
    c = subprocess.run([str(exe), "-I", "-c", _PROBE], cwd=HERE, env=_clean_env(),
                       capture_output=True, text=True, timeout=120)
  except OSError as e:
    return None, None, f"cannot execute: {e}"
  if c.returncode != 0:
    tail = (c.stderr.strip().splitlines() or ["no stderr"])[-1]
    return None, None, f"rc={c.returncode} {tail}"
  out = c.stdout.split()
  return out[0], (out[1] if len(out) > 1 else "?"), None


def resolve():
  """(exe, tinygrad_path, version). Exits 2 with the diagnosis if it cannot be done.

  The refusal names the interpreter it tried AND why it failed, because "the gate printed
  nothing" is not a verdict anybody can act on -- that ambiguity is the entire bug."""
  override = os.environ.get("ORACLE_PY")
  exe = shutil.which(override) if override else None
  if exe is None and override:
    refuse(f"ORACLE_PY is set to {override!r}, which is not an executable on PATH.")
  if exe is None:
    if not VENV_PY.exists():
      refuse(f"ORACLE PYTHON MISSING: {VENV_PY}\n"
             "  the CPython oracles import the EDITABLE tinygrad install, which exists only in\n"
             "  .venv (3.12). Recreate it (uv sync), or point ORACLE_PY at an interpreter whose\n"
             "  site-packages really has tinygrad.")
    exe = str(VENV_PY)
  path, version, err = probe(exe)
  if err:
    refuse(f"ORACLE PYTHON CANNOT IMPORT tinygrad: {exe}\n"
           f"  {err}\n"
           "  A lane that cannot import tinygrad prints ZERO rows, and zero rows is\n"
           "  indistinguishable from a port that agrees -- the failure this file exists to stop.\n"
           "  Refusing rather than reporting.")
  if pathlib.Path(path).resolve() != WANT:
    refuse(f"ORACLE PYTHON IMPORTS THE WRONG tinygrad: {exe}\n"
           f"  resolved {path}\n"
           f"  wanted  {WANT}\n"
           "  Every row this gate prints would be measured against a tree that is not the one\n"
           "  the port is ported from. Refusing.")
  return exe, path, version


def line(exe, path, version):
  """The provenance a verdict must carry: which interpreter, and what it resolved to."""
  return f"[oracle-py] {exe}  python {version}  tinygrad <- {path}"


def main():
  exe, path, version = resolve()
  print(line(exe, path, version))
  print(f"[oracle-py] launcher was {sys.executable} (pinned regardless)")


if __name__ == "__main__":
  main()