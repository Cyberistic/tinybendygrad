#!/usr/bin/env python3
"""isolate.py -- ONE graph, ONE side, in a FRESH PROCESS. The mechanism, and the only one.

WHY A PROCESS AND NOT A COUNTER RESET. `UOp.unique_num` (`tinygrad/uop/ops.py:839`, a
module-level `itertools.count`) is ONE piece of interpreter-global mutable state that leaks
into the row stream, through `Tensor.empty`'s `ParamArg(next(UOp.unique_num), ...)`
(`tinygrad/mixin/creation.py:41`) and out through `graphcmp.py:708` (`u(pa.slot)`).
Rebinding it to a fresh `count(0)` before each graph would make THIS corpus agree with a
fresh process -- measured, all 24 -- but it agrees for a reason nobody can check: I would be
betting that the set of interpreter globals which reach a row is exactly the ones I
enumerated. The failure mode of an enumeration is being incomplete, and incompleteness is
invisible by construction. A fresh process resets ALL of them without my having to name them,
so its completeness does not depend on my bookkeeping. It also costs `MEASURED 0.08 s` per
graph including the tinygrad import (24 graphs ~ 2 s), so the soundness is free here.

A RESET THAT ONLY MOVES THE SYMPTOM IS NAMED AS SUCH, not shipped: this file deliberately
does NOT reset the counter, because a reset would make the `late` slot look right while
leaving every other global exactly as coupled as it was.

THE SAME MECHANISM KILLS THE LATE-`DEV` CLASS. `DEV` is resolved when tinygrad is IMPORTED,
so a source-order `os.environ["DEV"]=...` is a convention every caller must remember. Here
`DEV` is in the child's ENVIRONMENT at process birth (`clean_env`, `graphcmp.py:1820`), so the
child has no line that could apply it late: it inherits the resolved flag before python starts.
Order becomes a property of the mechanism instead of a property of the reader's care.

THE BEND SIDE IS ALREADY ISOLATED and is left alone: `emit_bend` runs one `bend` subprocess per
graph (`graphcmp.py:1849`). Only the py side leaked, and only the py side is re-parented here.
"""
from __future__ import annotations
import sys, pathlib, subprocess

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]                               # hermetic/ -> slop/ -> .agents/ -> repo
sys.path.insert(0, str(REPO / ".agents" / "slop"))     # graphcmp, self-locating
sys.path.insert(0, str(REPO))                         # the tinygrad tree
import graphcmp as G

PY = str(REPO / ".venv" / "bin" / "python")           # NEVER a bare `python3`: graphcmp.py's
                                                       # `sys.path[0]` is its own directory, so
                                                       # `import graphcmp` would not resolve.


def _py(graph: str, dev: str) -> list[str]:
  """The child's whole job. `DEV` is already in the environment at process birth; this
  assignment restates it and is NOT what makes it land."""
  G.os.environ["DEV"] = dev
  G.load_tinygrad()
  G.COMM = G.commutative()
  with G.Context(NO_COLOR=1):
    return G.emit_py(graph, None)


def emit(graph: str, side: str, dev: str) -> list[str]:
  """One graph, one side, in a process that has never built another graph."""
  if side == "bend":
    return G.emit_bend(dev, graph)[0]                 # already one subprocess per graph
  c = subprocess.run([PY, __file__, "--graph", graph, "--side", side, "--dev", dev],
                     cwd=REPO, capture_output=True, text=True, env=G.clean_env(dev))
  rows = [ln for ln in c.stdout.splitlines() if ln.strip()]
  if not rows:                                         # 0 bytes is a FAILURE, never a verdict
    raise SystemExit(f"isolate: {graph}/{side} emitted 0 rows, rc={c.returncode}, "
                     f"stderr tail: {' '.join(c.stderr.split())[-200:] or '(empty)'}")
  return rows


if __name__ == "__main__":
  import argparse
  _a = argparse.ArgumentParser()
  for _f in ("graph", "side", "dev"):
    _a.add_argument(f"--{_f}", required=True)
  _a = _a.parse_args()
  if _a.side != "py":
    raise SystemExit(f"isolate: the child serves the PY side only (bend already forks per "
                     f"graph); refusing side={_a.side} rather than forking twice")
  sys.stdout.write("\n".join(_py(_a.graph, _a.dev)) + "\n")