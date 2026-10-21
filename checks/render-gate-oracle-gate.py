#!/usr/bin/env python3
"""render-gate-oracle-gate.py -- THE ORACLE'S OWN GATE: it RUNS, it is PINNED, and it still
answers what the tree recorded.

    .venv/bin/python checks/render-gate-oracle-gate.py
    .venv/bin/python checks/render-gate-oracle-gate.py --plant green
    .venv/bin/python checks/render-gate-oracle-gate.py --plant red
    .venv/bin/python checks/render-gate-oracle-gate.py --plant refused

WHAT THIS IS NOT.  `checks/rn-gate.py` ALREADY COMPARES THE ORACLE'S ROWS TO THE PORT'S ROWS
-- that is its whole job (`judge()` at `checks/rn-gate.py:322`, the `ORACLE` it runs at
`:74`).  THIS FILE DOES NOT BUILD A SECOND PORT-VERSUS-ORACLE COMPARISON, because a second
reader is how this project got a two-round contradiction between two gates ("156 forked
readers already exist", `checks/rn-gate.py:118`).  WHAT IS MISSING IS THE ORACLE'S OWN
HEALTH: nothing in the tree asked whether `checks/render-gate-oracle.py` can run AT ALL, and
after the 2026-10-17 re-vendor `86c4f1343` it could not -- it raised
`ImportError: cannot import name 'pyrender' from 'tinygrad.uop.render'` and every lane that
named it was REFUSED rather than red.

THE THREE CHECKS, AND WHY EACH ONE IS FALSIFIABLE.

  1 THE ORACLE RUNS.  A LANE THAT CANNOT RUN IS REFUSED, NOT PASS -- `exit 3`, and the
    refusal is a VERDICT ABOUT THE SUBJECT, not about the tree's health.  An oracle that
    prints nothing and exits 0 is the failure `gates/gatekit.py:59` exists for (`DEAD` is
    not a zero and not a pass).

  2 THE SUBJECT IS PINNED.  `pyrender` was DELETED UPSTREAM (`81157efb0`, 2026-10-05), so
    this oracle's subject is a REVISION, and a revision that moves silently changes every
    row.  The oracle DISCOVERS it (see its own docstring) and REPORTS it on stderr as
    `# subject: upstream <sha>`; this gate checks that sha against
    `git rev-parse 81157efb0^` -- the parent of the commit that deleted the function, which
    is the LAST upstream revision that had it.  THE PIN IS A CONSTANT THAT CODE CONSULTS,
    which is the difference between a pin and a comment.

  3 THE ROWS ARE THE TREE'S RECORDED ROWS.  `checks/rn-orc.rows` is the tree's own capture
    of this oracle's output, and the oracle's 124 rows are BYTE-IDENTICAL to it.  This is a
    PIN ON THE ANSWER, not a change-detector: it goes RED when the answer moves, which is
    the only thing a pin is for.  A capture that is not there, or an oracle that prints
    zero rows, is a REFUSAL -- "0 rows compared" is not a pass.

THE PLANT, WITH ITS CONTROL, ON COPIES.  `--plant green` runs the SAME CHECK against an
UNMODIFIED COPY of the oracle and requires it to PASS; `--plant red` corrupts ONE ROW in a
COPY and requires the same check to FAIL; `--plant refused` breaks the COPY's subject
resolution and requires the COPY to REFUSE.  NOTHING IN THE TREE IS TOUCHED: every copy
lives in a temp directory that is removed on the way out.
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
ORACLE = REPO / "checks" / "render-gate-oracle.py"
CAPTURE = REPO / "checks" / "rn-orc.rows"
PY = str(REPO / ".venv/bin/python")

# THE PIN.  Upstream deleted `pyrender` in this commit ("use render_uir instead of pyrender",
# #18622, 2026-10-05), so the last upstream revision that HAD the function is its PARENT,
# and that parent is the subject this oracle imports.  MEASURED: `git rev-parse
# 81157efb0^` = `ccae837c70301e3dab3ba8ea4db454249ad8f7e8`, and the oracle's 124 rows at
# that revision are byte-identical to `checks/rn-orc.rows`.
REMOVED_BY = "81157efb016472d010098482c66caa4e7c17ffe2"

# THE ORACLE'S OWN DECLARATION OF ITS SUBJECT, on stderr.  It is the oracle's interface, and
# it is a line the oracle PRINTS, not a line this gate infers.
SUBJECT_RX = re.compile(r"^# subject: upstream ([0-9a-f]{40})\b", re.M)


def refuse(*why):
  """exit 3 = REFUSED, and NOT a verdict -- `checks/rn-gate.py`'s rule, in this file's idiom."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


def git(*args):
  p = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True)
  if p.returncode != 0:
    refuse(f"git {' '.join(args)} -> rc={p.returncode}: {p.stderr.strip()}")
  return p.stdout.strip()


def run_oracle(path):
  """(rc, stdout, stderr) for the oracle at `path`, run the way the gate runs it."""
  p = subprocess.run([PY, str(path), "--gate"], cwd=REPO, capture_output=True, text=True,
                     timeout=600)
  return p.returncode, p.stdout, p.stderr


def check(path, capture=CAPTURE):
  """('PASS'|'FAIL'|'REFUSED', lines) for the oracle at `path`.

  `REFUSED` is returned for a lane that cannot run, and it is NOT a failure of the tree."""
  if not path.is_file():
    return "REFUSED", [f"the oracle is not at {path}"]
  if not capture.is_file():
    return "REFUSED", [f"the tree's capture of this oracle is absent: {capture}"]
  want = capture.read_text()
  rc, got, err = run_oracle(path)
  lines = []
  if rc != 0:
    lines.append(f"the oracle exited rc={rc}: {err.strip()[-200:]}")
    return "REFUSED", lines
  subject = SUBJECT_RX.search(err)
  if subject is None:
    return "REFUSED", [f"the oracle did not report its subject: {err.strip()[-200:]}"]
  expected = git("rev-parse", f"{REMOVED_BY}^")
  lines.append(f"subject   : {subject.group(1)}   (expected {expected})")
  if subject.group(1) != expected:
    lines.append(f"THE SUBJECT MOVED: the oracle answered from {subject.group(1)} and the "
                 f"subject is {expected} -- every row below is a different question")
    return "FAIL", lines
  lines.append(f"rows      : {len(got.splitlines())}   captured: {len(want.splitlines())}")
  if not got.splitlines():
    return "REFUSED", lines + ["the oracle printed ZERO rows -- 0 rows compared is not a pass"]
  if got == want:
    lines.append("the oracle's rows are BYTE-IDENTICAL to the tree's capture")
    return "PASS", lines
  diff = [i for i, (a, b) in enumerate(zip(got.splitlines(), want.splitlines()), 1) if a != b]
  lines.append(f"the oracle's rows DIFFER from the tree's capture on {len(diff)} line(s): {diff[:8]}")
  return "FAIL", lines


def copy_of_oracle(mutate=None):
  """A COPY of the oracle in a temp dir, optionally mutated.  The tree is never touched.

  `mutate` is (old, new) and its application is ASSERTED: a plant that silently changed
  nothing would report the same verdict as a plant that worked, and those are opposites."""
  d = pathlib.Path(tempfile.mkdtemp(prefix="render-gate-oracle-gate-"))
  dst = d / ORACLE.name
  shutil.copy2(ORACLE, dst)
  if mutate is not None:
    old, new = mutate
    text = dst.read_text()
    if text.count(old) != 1:
      shutil.rmtree(d, ignore_errors=True)
      refuse(f"the plant's mutation matched {text.count(old)} line(s), not 1 -- a plant that "
             "changes nothing cannot be told from a plant that worked")
    dst.write_text(text.replace(old, new))
  return d, dst


def plant(mode):
  """The PLANT, and its CONTROL.  Both run on COPIES; the tree is not touched."""
  if mode == "green":
    d, dst = copy_of_oracle()
    try:
      status, lines = check(dst)
      print(f"PLANT green: the control -- an UNMODIFIED COPY of the oracle -- expected PASS, "
            f"got {status}")
      print("\n".join(lines))
      return 0 if status == "PASS" else 1
    finally:
      shutil.rmtree(d, ignore_errors=True)
  if mode == "red":
    # ONE ROW, ONE CHARACTER.  `sint_show 7` is a row the oracle COMPUTES from a lambda; the
    # copy answers `8` instead, so the copy's rows stop matching the tree's capture and the
    # same check that passes on the control must fail here.
    d, dst = copy_of_oracle(('row("sint_show 7", lambda: "7")', 'row("sint_show 7", lambda: "8")'))
    try:
      status, lines = check(dst)
      print(f"PLANT red: a COPY of the oracle with ONE row corrupted -- expected FAIL, got {status}")
      print("\n".join(lines))
      return 1 if status == "FAIL" else 0
    finally:
      shutil.rmtree(d, ignore_errors=True)
  if mode == "refused":
    # A LANE THAT CANNOT RUN IS REFUSED, NOT PASS.  The copy cannot resolve a subject, so it
    # refuses, and this gate REPORTS THE REFUSAL rather than calling it green.
    d, dst = copy_of_oracle(('UPSTREAM = "refs/remotes/upstream/master"',
                             'UPSTREAM = "refs/remotes/upstream/NO-SUCH-REF"'))
    try:
      rc, _, err = run_oracle(dst)
      print(f"PLANT refused: a COPY of the oracle whose subject cannot be resolved -- expected "
            f"rc=3 (REFUSED), got rc={rc}")
      print(err.strip()[-300:])
      return 3 if rc == 3 else 1
    finally:
      shutil.rmtree(d, ignore_errors=True)
  refuse(f"unknown plant {mode!r}")


def main():
  ap = argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--plant", choices=["green", "red", "refused"], default=None,
                  help="self-test: the control, the planted copy, and the unrunnable lane")
  args = ap.parse_args()
  if args.plant is not None:
    return plant(args.plant)
  if not ORACLE.is_file():
    refuse(f"the oracle is not at {ORACLE}")
  status, lines = check(ORACLE)
  print("\n".join(lines))
  print(f"ORACLE GATE: {status}")
  return {"PASS": 0, "FAIL": 1, "REFUSED": 3}[status]


# THE VERDICT SURFACE, DECLARED.  `gates/gate-surface.py` reads these by AST -- never by
# import, because import RUNS a gate -- and then EXECUTES each plant and requires the
# observed rc to equal the declared one.  So these three argv are not decoration: each one
# reaches the exit code it names.
EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--plant", "green"], 1: ["--plant", "red"], 3: ["--plant", "refused"]}

if __name__ == "__main__":
  sys.exit(main())
