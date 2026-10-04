#!/usr/bin/env python3
"""oracle-live.py -- WHICH row-call SITES IN AN ORACLE ACTUALLY EXECUTE.

WHY. `unobservable-gr-oracle.py` defines `q4()` and `__main__` calls only
`q1(); q2(); q3()`. Two of that oracle's values were credited to CPython having
been transcribed out of `q4`'s SOURCE by a harness that never ran it -- they
happened to be right, and the provenance claim was false. Nothing in a static
scan can see that, because a static scan has no opinion about whether a function
is called.

So this runs the oracle under a line tracer restricted to the oracle's own file
and reports, per row-call site, whether its line executed. No name matching and
no second row reader: the question is about LINES, and lines are what the tracer
gives. (Row names contain spaces, so a name-matching approach would also be the
wrong tool -- `rebase-gate.py`'s `rows()` is the only sanctioned name reader and
it is not needed here.)

    .venv/bin/python .agents/slop/oracle-live.py .agents/slop/nv-oracle.py
    .venv/bin/python .agents/slop/oracle-live.py .agents/slop/nv-oracle.py --run2

`--run2` runs the oracle a second time and reports whether the two runs emit
byte-identical output. A single run is not evidence: `hand_typed` rows are
constants, so two runs of a wrong oracle agree perfectly with each other.
"""
from __future__ import annotations

import argparse
import io
import contextlib
import pathlib
import runpy
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
sys.path.insert(0, str(SLOP))
from importlib import import_module  # noqa: E402

audit = import_module("handtyped-audit")


def trace_run(oracle: pathlib.Path) -> tuple[set[int], set[str], str, str]:
  """(executed lines, entered local function names, stdout, stderr).

  The function-name set is the `q4()` check. `unobservable-gr-oracle.py` is the
  measured instance from the brief: `q4()` is DEFINED at :198, `__main__` calls
  only `q1(); q2(); q3()`, and the three rows `q4` would print -- `gr.sink_*` --
  had their values credited to CPython by a harness that never ran it. They were
  right. The provenance claim was false, and only "did this function run" can
  tell you.
  """
  seen: set[int] = set()
  entered: set[str] = set()
  target = str(oracle.resolve())

  def local(frame, event, arg):
    if event == "line" and frame.f_code.co_filename == target:
      seen.add(frame.f_lineno)
    return local

  def glob(frame, event, arg):
    if event == "call":
      if frame.f_code.co_filename == target:
        entered.add(frame.f_code.co_name)
      return local
    return None

  old = sys.gettrace()
  sys.settrace(glob)
  try:
    with contextlib.redirect_stdout(buf_out := io.StringIO()), \
         contextlib.redirect_stderr(buf_err := io.StringIO()):
      runpy.run_path(target, run_name="__main__")
  finally:
    sys.settrace(old)
  return seen, entered, buf_out.getvalue(), buf_err.getvalue()


def local_defs(oracle: pathlib.Path) -> dict[str, int]:
  import ast
  tree = ast.parse(oracle.read_text(errors="replace"))
  out = {}
  for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      out.setdefault(n.name, n.lineno)
  return out


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("oracle")
  ap.add_argument("--run2", action="store_true")
  ap.add_argument("--show-dead", action="store_true")
  a = ap.parse_args()

  oracle = pathlib.Path(a.oracle).resolve()
  scan = audit.scan(oracle)
  sites = scan["rows"]

  seen, entered, out1, err1 = trace_run(oracle)

  print("=" * 96)
  print(f"ORACLE LIVE-SITE CENSUS -- {oracle.relative_to(SLOP)}")
  print("=" * 96)
  defs = local_defs(oracle)
  uncalled = sorted((n, l) for n, l in defs.items()
                    if n not in entered and not n.startswith("__"))
  print(f"  defs in this oracle            : {len(defs)}")
  print(f"  defs NEVER ENTERED by a run   : {len(uncalled)}")
  for n, l in uncalled:
    print(f"      DEAD DEF  {n}  (defined at :{l})")
  if not sites:
    print(f"  (no `row()` call sites -- this oracle prints prose, so the line "
          f"census below is about the dead defs)")
  else:
    live = [x for x in sites if x["lineno"] in seen]
    dead = [x for x in sites if x["lineno"] not in seen]
    dl = [x for x in dead if x["defect"]]
    ll = [x for x in live if x["defect"]]
    print(f"  row call sites                : {len(sites)}")
    print(f"  sites whose LINE executed     : {len(live)}")
    print(f"  sites whose line NEVER ran    : {len(dead)}")
    print(f"  DEFECT sites, live            : {len(ll)}")
    print(f"  DEFECT sites, NEVER EXECUTED  : {len(dl)}")
  print(f"  rows emitted by the run       : {len(out1.splitlines())}")
  print(f"  stderr bytes                  : {len(err1)}")
  if err1.strip():
    print("  stderr head:", err1.strip().splitlines()[:3])

  if a.run2:
    seen2, entered2, out2, _ = trace_run(oracle)
    print(f"  run2 rows                     : {len(out2.splitlines())}")
    print(f"  run1 == run2 BYTE IDENTICAL   : {out1 == out2}")
    print(f"  run1 lines == run2 lines      : {seen == seen2}")
    print(f"  run1 defs  == run2 defs      : {entered == entered2}")

  dl = [x for x in sites if x["lineno"] not in seen and x["defect"]]
  if dl:
    print()
    print("  DEAD DEFECT SITES -- a value no run of this oracle produced.")
    print("  A conversion of one of these proves nothing until it is made live.")
    print("  Each is the NO-RAISE arm of a try/except whose other arm DID run, so")
    print("  the pair -- not this line -- is the assertion. See the report.")
    for x in dl:
      print(f"    :{x['lineno']:<5} {x['kind']:8} {x['name']:34} = "
            f"{x['value_src'][:44]}")
  if a.show_dead:
    print()
    print("  ALL DEAD SITES (derived ones too):")
    for x in [y for y in sites if y["lineno"] not in seen]:
      print(f"    :{x['lineno']:<5} {x['kind']:8} {x['name'][:36]:36} = "
            f"{x['value_src'][:44]}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())