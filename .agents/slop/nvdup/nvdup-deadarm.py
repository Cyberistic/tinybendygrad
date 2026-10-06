#!/usr/bin/env python3
r"""nvdup-deadarm.py -- A CENSUS OF `row()` SITES THAT NEVER EXECUTE.  The guard for the defect a
multiplicity census is structurally blind to.

    .venv/bin/python .agents/slop/nvdup/nvdup-deadarm.py            # the census
    .venv/bin/python .agents/slop/nvdup/nvdup-deadarm.py --selftest  # the matrix, with a DISARM

WHY IT EXISTS, MEASURED.  `nv-oracle.py:1159`'s `row("nv_reloc_bad_refused", "False")` is inside a
`try:` whose preceding line is a list comprehension that aborts on its SECOND element.  The line
never runs, so the name is emitted `True` and `True` and the multiplicity census reports a plain
P1 duplicate of equal values.  **The dead arm costs ZERO duplicate measurements**, because it
emits no row -- so every duplicate instrument in this project, including this one's own
`dup-gate.py`, reads it as clean.  The row it was written to carry, a negative case, was never
emitted and never existed.

TWO CENSUSES, BOTH RUN, AND THEY SEE DIFFERENT THINGS:

  SITE census   a `row(` line in the SOURCE that the tracer never saw execute  -> a dead arm
  LINE census   a name printed more than once in the LANE                      -> a duplicate

The second is `dup-gate.py`'s, re-run here rather than imported, and the reason it is re-run is
the matrix: the `longhand` cell plants a duplicate that BYPASSES `row()` entirely, and it is the
only cell where the site census reports 0 and the line census reports 1.  One instrument cannot
replace the other, and saying so is the point.

THE SELECTOR IS TEXTUAL (`^\s*row\(`), AND THAT IS ITS LIMIT, MEASURED IN THE MATRIX.  A row
appended as `ROWS.append((...))` is invisible to the site census.  The `longhand` cell exists so
that limit is a printed number and not a surprise.
"""
import argparse, contextlib, io, os, pathlib, re, runpy, subprocess, sys, tempfile
from collections import Counter

REPO = pathlib.Path(__file__).resolve().parents[3]
ORACLE = REPO / ".agents/slop" / "nv-oracle.py"
SITE = re.compile(r"^\s*row\(")
PY = sys.executable

PLANT_ANCHOR = '\nif __name__ == "__main__":\n'


def trace(path):
  """(`executed_row_call_sites`, `printed_lane_text`), from the file actually RUNNING."""
  captured = []

  def tracer(frame, event, arg):
    if frame.f_code.co_filename != str(path):
      return None
    if event == "line" and frame.f_code.co_name == "row":
      loc = frame.f_locals
      if "nm" in loc and "v" in loc:
        captured.append((frame.f_back.f_lineno, loc["nm"], str(loc["v"])))
    return tracer

  lane = io.StringIO()
  old_argv, sys.argv = sys.argv, [str(path)]
  sys.settrace(tracer)
  try:
    # the subprocess run above already proved this source executes, so stderr from a second
    # in-process run is noise: tinygrad prints `#  nv_encode_lines = ...` on import.
    with contextlib.redirect_stdout(lane), contextlib.redirect_stderr(io.StringIO()):
      runpy.run_path(str(path), run_name="__main__")
  finally:
    sys.settrace(None)
    sys.argv = old_argv
  return captured, lane.getvalue()


def census(source_text, label):
  """Write the source to `$TMPDIR`, RUN it there, and measure both censuses.  The repo tree is
  never patched by this file -- the live oracle is only ever read."""
  with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
    f.write(source_text)
    tmp = pathlib.Path(f.name)
  try:
    env = dict(os.environ, PYTHONPATH=str(REPO))
    r = subprocess.run([PY, str(tmp)], cwd=REPO, capture_output=True, text=True, env=env)
    if r.returncode != 0:
      raise SystemExit(f"{label}: oracle exited {r.returncode}\n{r.stderr[-900:]}")
    executed, lane = trace(tmp)
  finally:
    tmp.unlink()
  sites = {i for i, l in enumerate(source_text.splitlines(), 1) if SITE.match(l)}
  done = {ln for ln, _, _ in executed}
  names = [l.split("=", 1)[0] for l in lane.splitlines() if "=" in l]
  c = Counter(names)
  return {"label": label, "sites": sorted(sites), "dead": sorted(sites - done),
          "called": len(executed), "rows": len(names), "dup": {k: v for k, v in c.items() if v > 1},
          "lane": lane}


def report(g):
  print(f"  {g['label']:<10} distinct row() LINES in source={len(g['sites']):>3}   row() CALLS "
        f"executed={g['called']:>3} (>= lines: a loop calls one line many times)   "
        f"DEAD SITES={len(g['dead'])}   lane rows={g['rows']:>3}   "
        f"DUPLICATE NAMES={len(g['dup'])}")
  for ln in g["dead"]:
    print(f"      DEAD SITE  line {ln}   a row() that exists in the source and NEVER EXECUTES")


def selftest(src):
  """Five cells, each with its EXPECTATION printed beside its MEASUREMENT.  The DISARM is the
  first one: the real file, unplanted, must report 0 -- a control whose base is hardcoded 0
  cannot prove that it would have fired."""
  base = census(src, "clean")
  # ⚠ THE PLANT GOES **BEFORE** THE ANCHOR, NOT AFTER IT.  The anchor carries the
  # `if __name__ == "__main__":` line itself, so appending the plant to it drops the plant INSIDE
  # that block and the file's real body then lands at the wrong indent --
  # `IndentationError: expected an indented block after 'if'`, which is what the first run of this
  # selftest printed.  A selftest that cannot run is not a control, and this one was broken for a
  # reason that had nothing to do with the defect it was built to detect.
  dead_plant = ('try:\n'
                '    1 / 0\n'
                '    row("nv_plant_dead", "unreached")\n'
                'except ZeroDivisionError:\n'
                '    row("nv_plant_live", "reached")\n')
  live_plant = 'row("nv_plant_live2", "reached")\n'
  dup_plant = 'row("nv_reloc_kind_n", 3)\n'
  longhand = 'ROWS.append(("nv_reloc_kind_n", "3"))\n'
  if src.count(PLANT_ANCHOR) != 1:
    raise SystemExit(f"plant anchor matched {src.count(PLANT_ANCHOR)} times, expected 1")
  for name, plant in (("dead", dead_plant), ("live", live_plant), ("dup", dup_plant),
                      ("longhand", longhand)):
    cells[name] = census(src.replace(PLANT_ANCHOR, plant + PLANT_ANCHOR, 1), name)
  print("[selftest] DISARM first: the UNPLANTED real file.  A control whose base is typed 0 is a")
  print("           control that cannot fire, so the base is measured and printed with the cells.")
  report(base)
  for name in ("dead", "live", "dup", "longhand"):
    report(cells[name])
  b = len(base["dead"])
  checks = [
    ("DISARM: the unplanted real file has NO dead site (0)", len(base["dead"]) == 0),
    ("DEAD: a row() in an unreachable try-arm IS seen (0 -> 1)",
     len(cells["dead"]["dead"]) == b + 1 and len(cells["dead"]["dup"]) == 0),
    ("LIVE: a row() that DOES execute is not called dead (0)", len(cells["live"]["dead"]) == b),
    ("DUP: a duplicate is NOT a dead site -- site census stays 0, LINE census rises to 1",
     len(cells["dup"]["dead"]) == b and len(cells["dup"]["dup"]) == 1),
    ("LONGHAND: a duplicate that BYPASSES row() escapes the site census and the LINE census "
     "catches it -- the two censuses are not substitutes",
     len(cells["longhand"]["dead"]) == b and len(cells["longhand"]["dup"]) == 1),
  ]
  print()
  ok = True
  for desc, got in checks:
    print(f"  [{'PASS' if got else 'FAIL'}] {desc}: {got}")
    ok = ok and got
  print(f"DEADARM SELFTEST {'OK' if ok else 'FAILED'}")
  return ok


cells = {}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--file", help="census a DIFFERENT copy of the oracle, read-only -- the "
                                 "pre-fix copy is how the 4 dead arms are shown to have "
                                 "been 4 and not 0")
  a = ap.parse_args()
  src = pathlib.Path(a.file).read_text() if a.file else ORACLE.read_text()
  which = a.file or ORACLE.name
  if a.selftest:
    return 0 if selftest(src) else 1
  g = census(src, which)
  print(f"CENSUS OF DEAD MEASUREMENT SITES IN {which}")
  print(f"  sha256(source) = {__import__('hashlib').sha256(src.encode()).hexdigest()[:16]}")
  report(g)
  print("\n  a DEAD SITE emits nothing, so it costs 0 duplicate measurements and is invisible to")
  print("  every multiplicity census.  That is why it needs its own census.")
  return 1 if g["dead"] else 0


if __name__ == "__main__":
  sys.exit(main())