#!/usr/bin/env python3
"""nvdup-trace.py -- every `row()` CALL in `nv-oracle.py`, with its SOURCE LINE.

    .venv/bin/python .agents/slop/nvdup/nvdup-trace.py            # the table
    .venv/bin/python .agents/slop/nvdup/nvdup-trace.py --json     # machine form

WHAT IT DECIDES, AND WHY A GREP CANNOT.  The dup unit measured WHICH names repeat; this measures
WHICH EMISSION SITE produced each copy, which is the only thing that separates "the same
measurement printed twice" from "a DIFFERENT measurement printed under the same name".  Two
`row("nv_reloc_bad_refused", ...)` calls are textually different yet print the same output, and
one of the pair sits in a `try:` arm the run never enters -- a grep cannot say which arms
executed, and that is exactly the `nv_reloc_bad_refused` question.

NOTHING ON DISK IS EDITED, AND THE ORACLE IS NOT COPIED.  `runpy.run_path` runs the real file
under a line tracer; when the tracer sees a LINE event inside `row`, the bound `nm`/`v` are read
out of that frame and the CALL SITE comes from `f_back.f_lineno`.  `row`'s own body still runs, so
every value is CPython's answer and not this script's, and there is no second copy of the oracle
here that could drift from the one on disk.

Wrapping `row` by assignment was tried first and does NOT work, for a reason worth keeping: the
source's own `def row` at :29 reclaims the name on every exec, so the wrapper is gone before the
first row is emitted.  `sys.settrace` observes from outside and does not have that problem.

THE COUNT IS ASSERTED: one `row()` call must print exactly one line.  A `row` inside a
never-entered `except` would otherwise be silently absent and the surplus arithmetic wrong in the
direction that matters.
"""
import argparse, contextlib, io, json, pathlib, runpy, sys
from collections import defaultdict

REPO = pathlib.Path(__file__).resolve().parents[3]
ORACLE = REPO / ".agents/slop" / "nv-oracle.py"

captured = []


def tracer(frame, event, arg):
  """Line events for the oracle's own frames only.  Returning `None` for a foreign frame stops
  that frame's line events while leaving its call/return events cheap -- tracing every line of
  tinygrad's import would drown the handful of lines this measures."""
  if frame.f_code.co_filename != str(ORACLE):
    return None
  if event == "line" and frame.f_code.co_name == "row":
    loc = frame.f_locals
    if "nm" in loc and "v" in loc:
      captured.append((frame.f_back.f_lineno, loc["nm"], str(loc["v"])))
  return tracer


def classify(occ):
  """P1 or P2 decided from the VALUES, never from the name's shape."""
  return "P1 EQUAL-VALUES" if len({v for _, v in occ}) == 1 else "P2 DISTINCT-VALUES"


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--json", action="store_true")
  a = ap.parse_args()
  sys.argv = [str(ORACLE)]
  lane = io.StringIO()
  sys.settrace(tracer)
  try:
    with contextlib.redirect_stdout(lane):
      runpy.run_path(str(ORACLE), run_name="__main__")
  finally:
    sys.settrace(None)
  rows, printed = list(captured), lane.getvalue().splitlines()
  assert len(rows) == len(printed), f"{len(rows)} row() calls but {len(printed)} printed lines"
  byname = defaultdict(list)
  for ln, nm, v in rows:
    byname[nm].append((ln, v))
  dup = {k: v for k, v in byname.items() if len(v) > 1}
  p1 = sum(1 for occ in dup.values() if classify(occ).startswith("P1"))
  if a.json:
    print(json.dumps({"calls": len(rows), "printed_lines": len(printed),
                      "distinct_names": len(byname), "dup_names": len(dup),
                      "p1_equal_values": p1, "p2_distinct_values": len(dup) - p1,
                      "surplus": sum(len(v) - 1 for v in dup.values()),
                      "dups": {k: [{"line": l, "value": v} for l, v in occ]
                               for k, occ in dup.items()}}, indent=1))
    return 0
  print(f"row() CALLS ATTRIBUTED TO THEIR SOURCE LINE: {len(rows)}   printed lane lines: {len(printed)}")
  print(f"distinct names {len(byname)}   names emitted more than once {len(dup)}   "
        f"surplus rows {sum(len(v) - 1 for v in dup.values())}")
  print(f"  of those: P1 equal-values {p1}   P2 distinct-values {len(dup) - p1}")
  print()
  for nm in sorted(dup, key=lambda k: dup[k][0][0]):
    occ = dup[nm]
    print(f"{nm}  x{len(occ)}  {classify(occ)}")
    for ln, v in occ:
      print(f"    nv-oracle.py:{ln:<5} {nm}={v}")
  return 0


if __name__ == "__main__":
  sys.exit(main())