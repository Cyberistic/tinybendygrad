#!/usr/bin/env python3
"""render-gate-oracle-gate.py -- THE ORACLE'S OWN GATE: it RUNS, its SUBJECT IS PINNED, and
it still answers what the tree recorded.

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
    this oracle's subject is a REVISION -- and a revision that moves silently changes every
    row.  ⚠ AND THE SUBJECT IS A **HYBRID**: TWO revisions, because the two things this
    lane measures moved in OPPOSITE directions and never met.  `ParamArg` lost its `size`
    field on 2026-10-06 (`72f98ffe0`) and `pyrender` was deleted on 2026-10-05
    (`81157efb0`), so NO single upstream revision has both.  THE ORACLE DISCOVERS the pair
    (see its own docstring) and REPORTS it on stderr as `# subject: ops=<sha> render=<sha>`;
    THIS GATE CHECKS **BOTH** REVISIONS, and the message says WHICH ONE MOVED.

  3 THE ROWS ARE THE TREE'S RECORDED ROWS.  `checks/rn-orc.rows` is the tree's own capture
    of this oracle's output, and the oracle's 124 rows are BYTE-IDENTICAL to it.  This is a
    PIN ON THE ANSWER, not a change-detector: it goes RED when the answer moves, which is
    the only thing a pin is for.  A capture that is not there, or an oracle that prints
    zero rows, is a REFUSAL -- "0 rows compared" is not a pass.

THE PIN IS TWO COMMITS, AND THE SUBJECT IS DERIVED FROM BOTH.

    RENDER_REMOVED_BY  `81157efb0` deleted `pyrender`, so its PARENT is the revision whose
                       `tinygrad/uop/render.py` still renders this lane.
    OPS_INCOMPATIBLE_AT `efb4cc8cb` flipped `UOp.toposort`'s `enter_calls` default and
                       BROKE the pyrender-era renderer, so the revision before it that last
                       touched `tinygrad/uop/ops.py` is the last `ops.py` the renderer can
                       still run -- and it is also the last one whose `ParamArg` has no
                       `size`, because upstream moved the size into the buffer's `src[0]`.

⚠ THE PIN IS NOT THE VENDORED TREE'S PIN.  `.agents/UPSTREAM-PIN.md`'s `5c2bf39d6c4b`
(2026-10-20) has `enter_calls=False`, so ITS `ops.py` cannot run the pyrender-era renderer
at all -- MEASURED, the three `pyr_call_*` rows become `!error` -- and its `KernelInfo` has
an `optimized` field and its `ProgramInfo` calls its third field `params`, so the pin's
`ops.py` answers `arg_repr AKern` and `arg_repr AProgr` DIFFERENTLY FROM THE PORT, which
prints the 2026-10-05 shapes.  A HYBRID BUILT ON THE PIN IS A HYBRID THAT DISAGREES WITH
THE PORT ON FIVE ROWS.  THE PIN HERE IS A PIN OF THE *SUBJECT*, NOT OF THE VENDORED TREE.

THE PLANT, WITH ITS CONTROL, ON COPIES.  `--plant green` runs the SAME CHECK against an
UNMODIFIED COPY of the oracle and requires it to PASS; `--plant red` corrupts ONE ROW in a
COPY and requires the same check to FAIL; `--plant refused` runs THREE REFUSAL ARMS, each
on its own COPY, and requires each to be REFUSED rather than answered:

    an UNRESOLVABLE subject        the upstream ref does not exist;
    a WRONG-REVISION file          one file of the hybrid comes from a revision that does
                                   not define `pyrender` -- it must REFUSE, not answer
                                   DIFFERENT ROWS;
    a SHADOWED subject             the vendored `tinygrad/` wins the import -- it must
                                   REFUSE, not answer from the wrong tree.

NOTHING IN THE TREE IS TOUCHED: every copy lives in a temp directory that is removed on the
way out.
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
OPS = "tinygrad/uop/ops.py"

# THE PIN.  TWO COMMITS, TWO ROLES, BECAUSE THE SUBJECT IS A HYBRID OF TWO REVISIONS.
#
# `81157efb0` ("use render_uir instead of pyrender" #18622, 2026-10-05) DELETED `pyrender`,
# so the revision whose `tinygrad/uop/render.py` still renders this lane is its PARENT.
# MEASURED: `git rev-parse 81157efb0^` = `ccae837c70301e3dab3ba8ea4db454249ad8f7e8`.
RENDER_REMOVED_BY = "81157efb016472d010098482c66caa4e7c17ffe2"
#
# `efb4cc8cb` ("toposort does not enter CALL bodies by default" #18645, 2026-10-09) FLIPPED
# `UOp.toposort`'s `enter_calls` default, and that is what BROKE the pyrender-era renderer:
# `pyrender` calls `ast.toposort()` and then renders the CALL's BODY, so with the flipped
# default the body is not in the toposort and `ctx[body]` is a `KeyError` -- MEASURED at the
# vendored pin, the three `pyr_call_*` rows answer `!error` instead of `False`.  THE
# REVISION BEFORE IT THAT LAST TOUCHED `tinygrad/uop/ops.py` IS THEREFORE THE OPS
# REVISION, and it is also the last `ops.py` whose `ParamArg` has no `size` -- upstream moved
# the size out of `ParamArg` into the buffer's `src[0]` on 2026-10-06 (`72f98ffe0`), and the
# port's `ParamArg` record cannot hold one.
OPS_INCOMPATIBLE_AT = "efb4cc8cb8478926e77f522f3dba9bf0d8ffaff9"

# THE ORACLE'S OWN DECLARATION OF ITS SUBJECT, on stderr.  It is the oracle's interface, and
# it is a line the oracle PRINTS, not a line this gate infers.  TWO REVISIONS, so TWO
# GROUPS: a subject that is ONE revision is a subject that moved.
SUBJECT_RX = re.compile(r"^# subject: ops=([0-9a-f]{40}) render=([0-9a-f]{40})\b", re.M)


def refuse(*why):
  """exit 3 = REFUSED, and NOT a verdict -- `checks/rn-gate.py`'s rule, in this file's idiom."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


def git(*args):
  p = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True)
  if p.returncode != 0:
    refuse(f"git {' '.join(args)} -> rc={p.returncode}: {p.stderr.strip()}")
  return p.stdout.strip()


def expected_subject():
  """(ops_rev, render_rev) -- the PINNED PAIR, derived from the TWO pin constants.

  THE RENDER REVISION is the parent of the commit that deleted `pyrender`: that commit is
  the CAUSE, and the revision is derived from it, so the pin is a constant that code
  consults rather than a hash somebody wrote down beside a comment.

  THE OPS REVISION is the last revision before the commit that BROKE the renderer which
  touched `tinygrad/uop/ops.py`.  `git rev-list <anchor> -- <path>` lists exactly the
  revisions that CHANGED the path, newest first, so the anchor is the first of them (the
  anchor IS the commit that broke it) and the second is the revision before it."""
  render_rev = git("rev-parse", f"{RENDER_REMOVED_BY}^")
  anchor = git("rev-parse", OPS_INCOMPATIBLE_AT)
  ops_rev = next((r for r in git("rev-list", anchor, "--", OPS).split() if r != anchor), None)
  if ops_rev is None:
    refuse(f"no upstream revision before {OPS_INCOMPATIBLE_AT} touched {OPS} -- the pinned ops "
           "revision cannot be derived")
  return ops_rev, render_rev


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
  ops_rev, render_rev = expected_subject()
  got_ops, got_render = subject.group(1), subject.group(2)
  lines.append(f"ops subject  : {got_ops}   (pinned {ops_rev})")
  lines.append(f"render subject: {got_render}   (pinned {render_rev})")
  if got_ops != ops_rev:
    lines.append(f"THE OPS SUBJECT MOVED: the oracle answered from {got_ops} and the pinned "
                 f"ops revision is {ops_rev} -- every row below is a different question")
    return "FAIL", lines
  if got_render != render_rev:
    lines.append(f"THE RENDER SUBJECT MOVED: the oracle answered from {got_render} and the "
                 f"pinned render revision is {render_rev} -- every row below is a different "
                 "question")
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


def expect_refusal(label, mutate):
  """(ok, detail) for ONE refusal arm: the COPY must exit 3 and say REFUSED.

  A LANE THAT CANNOT RUN IS REFUSED, NOT PASS.  AND A LANE THAT ANSWERS FROM THE WRONG
  SUBJECT MUST NOT ANSWER AT ALL: the arms below are the ways this oracle's subject can go
  wrong, and each of them must produce a REFUSAL and not a set of different rows."""
  d, dst = copy_of_oracle(mutate)
  try:
    rc, out, err = run_oracle(dst)
    refused = rc == 3 and "REFUSED" in err
    detail = (f"rc={rc}  {err.strip().splitlines()[-1][:160] if err.strip() else '(no stderr)'}"
              if rc != 3 else err.strip().splitlines()[-1][:160])
    return refused, detail
  finally:
    shutil.rmtree(d, ignore_errors=True)


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
    # THREE ARMS, THREE WAYS THE SUBJECT CAN GO WRONG, ALL OF THEM REFUSED.
    arms = [
      ("an UNRESOLVABLE subject",
       ('UPSTREAM = "refs/remotes/upstream/master"',
        'UPSTREAM = "refs/remotes/upstream/NO-SUCH-REF"')),
      ("a WRONG-REVISION file in the hybrid",
       ("RENDER_REV = resolve_render()", "RENDER_REV = resolve_ops()")),
      ("a SHADOWED subject (the vendored tree wins the import)",
       ("sys.path.insert(0, DEST)", "sys.path.insert(0, REPO)")),
    ]
    ok = True
    for label, mutate in arms:
      good, detail = expect_refusal(label, mutate)
      ok &= good
      print(f"PLANT refused: {label} -- expected REFUSED (rc=3), "
            f"{'got it' if good else 'DID NOT GET IT'}: {detail}")
    return 3 if ok else 1
  refuse(f"unknown plant {mode!r}")


def main():
  ap = argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
  ap.add_argument("--plant", choices=["green", "red", "refused"], default=None,
                  help="self-test: the control, the planted copy, and the three unrunnable lanes")
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
VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
PLANTS = {0: ["--plant", "green"], 1: ["--plant", "red"], 3: ["--plant", "refused"]}

if __name__ == "__main__":
  sys.exit(main())
