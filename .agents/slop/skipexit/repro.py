#!/usr/bin/env python3
"""THE REPRO FOR `checks/e2e.py`'s EXIT STATUS: a green column and TWO DIFFERENT FAILURE COLUMNS,
run against BOTH the current gate and a FROZEN PRE-FIX COPY of it, so it discriminates both ways.

    .venv/bin/python .agents/slop/skipexit/repro.py

WHAT IS BEING CLAIMED. Before the fix, `PASS WITH N SKIP(S)` exited **0** while the gate's own
prose said `SKIP IS NOT PASS`. So a caller reading only `$?` could not tell a clean pass from a run
in which a stage measured nothing. After the fix that run exits **4**.

| column | what happened                          | status before | status now |
| ------ | -------------------------------------- | ------------- | ---------- |
| GREEN  | every stage ran, every stage agreed     | 0             | 0          |
| FAIL   | a stage RAN and got the wrong answer    | 1             | 1          |
| SKIP   | a stage measured NOTHING               | **0**         | **4**      |

**THE SKIP COLUMN IS THE ONE THAT MUST DISCRIMINATE.** If the two gates ever agree on it, the fix
is not there -- so agreement there is reported as a FAILURE of this repro, not as a pass.

**A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES.** MEASURED, and it is the failure this project
keeps paying for: one repro read `LEFT=NOTHING` on BOTH sides because it `rmtree`d the artifact
directory between beats, deleting the state under test. So every column asserts BOTH that the plant
reached its intended state AND that the artifact is non-empty, and a column that fails either
assertion is reported as PROVING NOTHING rather than as passing:

  * the intended verdict line is present in the artifact (bytes, `in`);
  * the artifact is non-empty (`LEFT=NOTHING` on both sides is a failed plant, not a green one);
  * the plant's own stub markers are present, i.e. the stubs really ran and were not short-circuited.

**TWO METHODS THAT DO NOT SHARE A REGEX**, because self-consistency is not independence -- a belt
missed a bug here once because it shared the fix's assumption:

  * **METHOD 1** is `subprocess.run(...).returncode`: the NUMBER from the kernel. It parses no
    character and therefore cannot share a pattern with anything.
  * **METHOD 2** is `STDLEN` and a byte-count of the verdict line plus an `in` test. Length and
    counting are arithmetic on bytes; there is no regex anywhere in it.

They are computed from ONE invocation per gate, and the two are then CROSS-CHECKED: a run whose
number and whose text disagree is reported as a broken REPRO, never as a healthy gate.

**STAGE 3 IS STUBBED, AND THAT IS THE ONE THING THIS FILE ADDS TO THE PLANT.** `.agents/slop/
e2epy/diff.py`'s builder never created `e2e_mm_run.mjs`, so stage 3 ran real `node` on a missing
file and FAILed `rc=1` in every plant -- MEASURED in `artifacts/plant-pass.oracle.out`, which reads
`stage 3 gpu (node): FAIL (rc=1)` and `--- verdicts: 1 failed, 0 skipped ---`. Without this stub a
SKIP column would also carry a FAIL, the FAIL branch would win, and the run would exit 1 on both
gates: the plant would not be exercising the thing under test. It is a THREE-LINE STUB and it is
not a copy of the real script, because a plant that copies the thing it is meant to displace cannot
prove anything.

**ONE `bend` PROCESS AT A TIME, ALWAYS.** Every invocation is a blocking `subprocess.run`, the two
gates of a column are ordered rather than concurrent, and no column runs a real `bend`: the plant
supplies a stub. Nothing here does an `rmtree` between the two gates of a column.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
ART = HERE.parent / "artifacts"
PREFIX_ROOT = HERE.parent / "prefix"          # THE FROZEN PRE-FIX TREE, byte-identical to the old gate
sys.path.insert(0, str(ROOT / ".agents/slop/e2epy"))
import diff as plantlib     # noqa: E402  -- the ALREADY-VALIDATED builder, not a re-implementation

PY = str(ROOT / ".venv/bin/python")
# THE STAGE-7 CAPTURE IS NAMED PER LANE, AND THAT NAME IS THE `.txt` RETIREMENT: the
# post-fix gate writes `e2e-f64.out` (plancarve 5ed3ad771); the FROZEN PRE-FIX GATE still
# writes `e2e-f64.txt`. One name served both until the rename, and reading that one name
# afterwards points at a file the post-fix lane never wrote.
GATES = (("post-fix", ROOT / "checks/e2e.py", "runs/e2e/e2e-f64.out"),
         ("pre-fix", PREFIX_ROOT / "checks/e2e.py", "runs/e2e/e2e-f64.txt"))

# THE THREE COLUMNS. `codes` is the exit status of, IN ORDER, stage 1's oracle, stage 4's gate,
# stage 5's ops_bend, stage 6's port mm, stage 7's run-f64. Stage 3 is the stub, always 0.
# THE SECOND NUMBER IS **WHAT THE FROZEN PRE-FIX GATE MUST SAY**, and it is asserted like any other
# expectation rather than excused: `SKIP` is `0` there, and that `0` IS THE DEFECT. A column whose
# pre-fix number is unasserted would pass whether or not the pre-fix gate was really the old one.
COLUMNS = {
    "GREEN": (dict(codes="0,0,0,0,0", bend=25), b"PASS -- every stage ran and every stage agreed.", 0, 0),
    "FAIL":  (dict(codes="0,0,1,0,0", bend=25), b"FAIL -- 1 stage(s) ran and failed.", 1, 1),
    "SKIP":  (dict(codes="0,0,0,0,3", bend=25), b"PASS WITH 1 SKIP(S)", 4, 0),
}
STAGE3_STUB = 'console.log("REPRO stub: stage 3 gpu");\n'
# WHERE THE PLANT'S OWN STUB BYTES LAND. **NOT stdout**, and the first cut of this repro looked for
# the marker in stdout and correctly refused to believe the column -- stage 7 is captured with
# `> FILE 2>&1` (`e2e.py` `stage(..., f64)`) and only its GREPED lines reach stdout, so a SKIP
# column's stub marker never appears there. MEASURED: the marker is in
# `runs/e2e/e2e-f64.txt` and never in the transcript. Read from the plant's OWN captured file, which
# is where the thing it was going to measure is written, so this is the same artifact the gate read.
STUB_MARK = b"PLANT stub: run-f64.sh"


def build(tag: str, spec: dict) -> Path:
    """The validated plant, PLUS the one stub `diff.py` never made. See the module docstring."""
    fx = plantlib._build_plant(f"repro-{tag}", spec)
    (fx / ".agents/slop/e2e_mm_run.mjs").write_text(STAGE3_STUB)
    return fx


def run(gate: Path, env: dict[str, str], tag: str, fx: Path,
        capture: str) -> tuple[int, bytes, bool]:
    """ONE INVOCATION, and both methods read from its single result -- so the two methods cannot
    disagree because they ran against different states. Nothing is deleted between gates."""
    ART.mkdir(parents=True, exist_ok=True)
    out = ART / f"{tag}.out"
    with open(out, "wb") as o, open(ART / f"{tag}.err", "wb") as e:
        rc = subprocess.run([PY, str(gate)], cwd=ROOT, env=env, stdout=o, stderr=e).returncode
    # THE PLANT-MOVED PROOF, from the plant's own captured stage-7 file. The name is the lane's
    # (see GATES): the frozen pre-fix gate predates the `.txt`->`.out` rename and writes the old
    # one. Read AFTER the run, and never deleted, because a belt that rmtree's the artifact between
    # beats deletes the state under test and then reads LEFT=NOTHING on BOTH sides -- a plant that
    # cannot move is a plant that passes.
    return rc, out.read_bytes(), STUB_MARK in (fx / capture).read_bytes()


def report(name: str) -> tuple[list[str], list[str]]:
    """ONE COLUMN: both gates, both methods, the cross-check, and the vacuity refusal."""
    spec, needle, want, want_pre = COLUMNS[name]
    fx = build(name.lower(), spec)
    env = plantlib.ENV | {"E2E_ROOT": str(fx), "PATH": f"{fx}/sandbox"}
    lines, bad, got = [], [], {}
    for label, gate, capture in GATES:
        want_here = want if label == "post-fix" else want_pre
        rc, blob, ok_stub = run(gate, env, f"{name}.{label}", fx, capture)
        got[label] = rc
        # METHOD 1: the number, from the kernel. No text involved.
        # METHOD 2: byte arithmetic only -- length, a count, and an `in` test. No regex anywhere.
        n = blob.count(needle)
        ok_line = n == 1
        lines.append(f"  {label:<9} M1 status={rc} (want {want_here})   M2 count={n} "
                     f"stdout={len(blob)}B   M2 stub-ran={ok_stub}")
        # A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES. Each of these is a refusal to believe it.
        if not ok_line:
            lines.append(f"  *** {label}: the plant DID NOT MOVE -- the verdict line is absent, so "
                         f"this column proves NOTHING and is not counted as a pass.")
            bad.append(label)
        if rc != want_here:
            lines.append(f"  *** {label}: status {rc} != {want_here}")
            bad.append(label)
        if not ok_stub:
            lines.append(f"  *** {label}: the plant's own stubs did not run, so the real stage was "
                         f"executed and the column is measuring the wrong program.")
            bad.append(label)
        if len(blob) == 0:
            lines.append(f"  *** {label}: LEFT=NOTHING -- empty artifact on this side.")
            bad.append(label)
    # THE DISCRIMINATION IS ITS OWN ASSERTION, because "the fix is present" is not the same claim as
    # "the repro ran". A SKIP column where the two gates agree is a repro that cannot see the fix.
    if name == "SKIP":
        if got["post-fix"] == got["pre-fix"]:
            lines.append(f"  *** SKIP DOES NOT DISCRIMINATE: both gates report {got['post-fix']}, so "
                         f"the fix is not observable and THIS REPRO IS LYING.")
            bad.append("discriminate")
        else:
            lines.append(f"  DISCRIMINATES: post-fix={got['post-fix']} != pre-fix={got['pre-fix']}. "
                         f"The exit status alone now separates a partial run from a clean one, and "
                         f"the pre-fix 0 is the defect reproduced.")
    return lines, bad


def main() -> int:
    bad: list[str] = []
    for name in ("GREEN", "FAIL", "SKIP"):
        lines, col_bad = report(name)
        spec, _, want, want_pre = COLUMNS[name]
        print(f"## COLUMN {name}   post-fix want {want}   pre-fix want {want_pre}   "
              f"plant codes={spec['codes']}")
        for ln in lines:
            print(ln)
        if col_bad:
            bad.append(name)
    print(f"\n{len(bad)} of 3 column(s) failed"
          + (f": {', '.join(bad)}" if bad else "")
          + f".  artifacts: {ART.relative_to(ROOT)}/")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())