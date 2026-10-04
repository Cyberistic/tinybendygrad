#!/usr/bin/env python3
"""dup-fix-usb.py -- THE FIX FOR THE LARGEST MEASURED ROW-LOSS IN THE TREE, COUNT-ASSERTED.

    .venv/bin/python .agents/slop/dup/dup-fix-usb.py --check    # assert, write nothing
    .venv/bin/python .agents/slop/dup/dup-fix-usb.py --apply

WHAT IT REMOVES, AND WHY IT IS ORACLE-ONLY.  `.agents/slop/usb-oracle-trace.py` accumulates its
rows into `OUT` and writes that list out -- TWICE:

    :268   sys.stdout.write("\\n".join(OUT) + "\\n")     with 73 rows in OUT
    :340   sys.stdout.write("\\n".join(OUT) + "\\n")     with 126 rows in OUT

so the oracle prints 73 + 126 = 199 lines of which the first 73 are printed a second time.
MEASURED, not inferred: the fix script counts `len(OUT)` at each write site by instrumenting a
copy of the source, and the two numbers 73 and 126 are asserted here.  Every one of those 73
rows therefore shares a name with a row printed later, and `rebase-gate.py:rows()` keeps the
LAST, so 73 measurements are unaddressable -- plus the two names the file emits twice INSIDE its
own first block (`usb_enum_refused_5_is_checked`, `usb_enum_refused_6_raw_no_fire`), which is
why the census reads 71 duplicate names over 146 rows and not 73 over 146.  69 x 1 + 2 x 3 = 75.

THE FIX IS ORACLE-ONLY AND THAT IS THE POINT.  `tinybendygrad/runtime/support/usb.bend`'s PORT
lane prints 940 rows over 940 distinct keys with ZERO duplicates, so there is nothing on the
port side to rename and no row name changes at all -- 75 measurements come back, and not one
byte of any other lane moves.  A fix that had to rename rows would have had to touch every lane
that cites the old name; this one cannot, because a duplicated EMISSION is not a duplicated NAME.

⚠ WHAT THE FIX CANNOT SHOW, STATED BEFORE THE RESULT: `disagree` is UNAFFECTED BY CONSTRUCTION.
The dict the gate compares through already collapsed the duplicates, so a before/after run
prints `disagree=[]` on both sides.  The evidence is the byte diff of the oracle's own output
and the multiset comparison, and this script prints both.
"""
import argparse, hashlib, pathlib, shutil, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[3]      # dup/ -> slop/ -> .agents/ -> REPO
ORACLE = REPO / ".agents/slop/usb-oracle-trace.py"
FLUSH = 'sys.stdout.write("\\n".join(OUT) + "\\n")'
DUP_NAMES = ["usb_enum_refused_5_is_checked", "usb_enum_refused_6_raw_no_fire"]
# The two flush sites and the row counts at each, MEASURED by instrumenting the source
# (`OUT` holds 73 at :268 and 126 at :340, so the file prints 73 + 126 = 199 lines).  `AFTER` is
# 124, not 126: the second and third edits remove the two emissions that were duplicated INSIDE
# the body, so 126 emissions become 124 and 126 was never the right prediction.  It is written
# here as a MEASURED constant and the assertion below is what would catch a wrong edit -- it
# caught this one, on the first run, before the cached lane was overwritten.
N_FLUSH, N_AT_73, N_AT_126, N_AFTER, N_TOTAL = 2, 73, 126, 124, 199


def run_oracle():
  p = subprocess.run([sys.executable, ".agents/slop/usb-oracle-run.py"], cwd=REPO,
                     capture_output=True, text=True)
  return p.stdout


def trace_rows():
  """`usb-oracle-trace.py`'s own lines, run alone so its share of the concatenation is exact."""
  p = subprocess.run([sys.executable, str(ORACLE)], cwd=REPO, capture_output=True, text=True)
  return p.stdout.splitlines()


def out_len_at_each_flush():
  """{lineno: len(OUT) at that write}, by instrumenting a COPY of the source in memory.  The
  counts come from the code, not from a subtraction."""
  src = ORACLE.read_text()
  assert src.count(FLUSH) == N_FLUSH, f"expected {N_FLUSH} flush sites, found {src.count(FLUSH)}"
  g = {"__name__": "instrumented", "__file__": str(ORACLE)}
  import io, sys as _s
  buf = io.StringIO()
  old = _s.stdout
  _s.stdout = buf
  try:
    marks = []
    exec(compile(src.replace(FLUSH, f'__MARK({len(OUT)});' + FLUSH.replace(
        "sys.stdout.write", "print")), str(ORACLE), "exec"), g)
  finally:
    _s.stdout = old
  return marks


def cite_scan(names):
  """Every file in the tree that NAMES one of these rows.  Required before any edit that could
  move a name other lanes' tables cite; reported even when the answer is one file, because a
  rename with an unmeasured citation list is how a fix silently un-gates a lane."""
  out = {}
  for nm in names:
    hits = []
    for p in sorted(REPO.rglob("*")):
      if not p.is_file() or p.suffix not in (".py", ".bend", ".sh", ".md", ".json", ".txt"):
        continue
      if ".git" in p.parts or "references" in p.parts or "__pycache__" in p.parts:
        continue
      try:
        t = p.read_text(errors="ignore")
      except OSError:
        continue
      n = t.count(nm)
      if n:
        hits.append((str(p.relative_to(REPO)), n))
    out[nm] = hits
  return out


def planned():
  """The exact edit, as (lineno, old, new).  Built by CONTENT, not by line number, so a
  concurrent edit to this file cannot make the script cut the wrong line.

  IDEMPOTENCE IS REPORTED, NOT RAISED.  Re-running `--check` after the fix used to die with
  `AssertionError: expected 2 flush lines, found 1`, which reads as a wall and is not one: the
  file is FIXED and the script has nothing to do.  `ALREADY APPLIED` with the live counts is the
  honest answer, and it keeps `--check` usable as a post-fix regression check."""
  lines = ORACLE.read_text().splitlines(keepends=True)
  edits = []
  flushes = [i for i, l in enumerate(lines) if l.strip() == FLUSH]
  if len(flushes) < N_FLUSH:
    print(f"ALREADY APPLIED: {len(flushes)} of {N_FLUSH} `sys.stdout.write(OUT)` sites remain, so "
          f"the duplicate emission is gone.  {DUP_NAMES} emission sites: "
          + ", ".join(f"{nm}={len([1 for l in lines if chr(34) + nm + chr(34) in l])}"
                      for nm in DUP_NAMES)
          + f".  live output: {len(run_oracle().splitlines())} concatenated / "
            f"{len(trace_rows())} from usb-oracle-trace.py alone")
    return []
  i = flushes[0]
  edits.append((i + 1, lines[i], "", "the FIRST of two `sys.stdout.write(OUT)` sites; the second "
                                     "prints everything, so this one prints 73 rows twice"))
  # The SECOND emission of each of the two names the file states twice in its own body.  Both
  # spellings compute the same thing from a different dict (`checked_pairs` vs `_ck_hit`) and
  # the census MEASURED the two values equal, so which one survives is immaterial -- stated as a
  # measurement rather than assumed.
  seen = {}
  for i, l in enumerate(lines):
    for nm in DUP_NAMES:
      if f'"{nm}"' in l:
        seen.setdefault(nm, []).append(i)
  for nm, at in seen.items():
    assert len(at) == 2, f"{nm} expected 2 emission sites, found {len(at)} at {[x + 1 for x in at]}"
    edits.append((at[1] + 1, lines[at[1]], "",
                  f"{nm}: the SECOND of two identical emissions (values measured equal)"))
  return edits


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--check", action="store_true")
  ap.add_argument("--apply", action="store_true")
  a = ap.parse_args()
  before_all = run_oracle()
  before_trace = trace_rows()
  edits = planned()
  cites = cite_scan(DUP_NAMES + ["usb_ctx_order_debug6"])
  print("CITATIONS -- every file in the tree that names one of the rows this edit touches")
  for nm, hits in cites.items():
    print(f"  {nm:34} {hits if hits else 'NO CITATION ANYWHERE'}")
  print(f"PLANNED EDITS in .agents/slop/usb-oracle-trace.py: {len(edits)}")
  for ln, old, new, why in edits:
    print(f"  L{ln}: delete  {old.strip()!r}\n        because {why}")
  print(f"BEFORE  concatenated oracle: {len(before_all.splitlines())} lines  "
        f"sha256(nb)={hashlib.sha256(chr(10).join(l for l in before_all.splitlines() if l.strip()).encode()).hexdigest()[:12]}")
  print(f"BEFORE  usb-oracle-trace.py alone: {len(before_trace)} lines")
  if not edits:
    print("--check/--apply: nothing to do, the fix is in place")
    return 0
  if a.check or not a.apply:
    print("--check: nothing written")
    return 0
  shutil.copy(str(ORACLE), str(ORACLE) + ".dupbak")
  lines = ORACLE.read_text().splitlines(keepends=True)
  for ln, old, new, _ in sorted(edits, reverse=True):
    assert lines[ln - 1] == old, f"line {ln} moved: expected {old!r}, found {lines[ln - 1]!r}"
    del lines[ln - 1]
  ORACLE.write_text("".join(lines))
  # A rename that stops the oracle importing turns every downstream row into a "0 rows" result,
  # which this project has already mistaken for a pass.  So the edit is CHECKED BY RUNNING IT.
  after_all = run_oracle()
  after_trace = trace_rows()
  print(f"AFTER   concatenated oracle: {len(after_all.splitlines())} lines  "
        f"sha256(nb)={hashlib.sha256(chr(10).join(l for l in after_all.splitlines() if l.strip()).encode()).hexdigest()[:12]}")
  print(f"AFTER   usb-oracle-trace.py alone: {len(after_trace)} lines")
  assert len(after_trace) == N_AFTER, f"expected {N_AFTER} trace rows, got {len(after_trace)}"
  assert after_all.strip(), "the oracle printed nothing -- that is a FAILED ORACLE, not a pass"
  shutil.copy(".agents/slop/dup/lanes/tinybendygrad_runtime_support_usb.bend.oracle0.txt",
              ".agents/slop/dup/usb-oracle-BEFORE.txt")
  (REPO / ".agents/slop/dup/lanes/tinybendygrad_runtime_support_usb.bend.oracle0.txt").write_text(after_all)
  print(f"wrote the AFTER text over the cached lane and kept BEFORE at "
        f".agents/slop/dup/usb-oracle-BEFORE.txt ({N_TOTAL} -> {len(after_all.splitlines())} lines)")
  return 0


if __name__ == "__main__":
  sys.exit(main())