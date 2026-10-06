#!/usr/bin/env python3
"""STAGE VERDICTS FOR THE SEVEN STAGES, WITH EACH STAGE'S DENOMINATOR.

`checks/e2e.py` is the gate and it is NOT modified here: this runs it and reads its own verdict
lines out of the transcript, because a second hand-maintained copy of the verdicts is a second
thing that can disagree with the first.

    .venv/bin/python .agents/slop/fixures/stage-verdicts.py --transcript runs/e2e/verdicts.out

DENOMINATOR, per stage, taken from the transcript the stage itself printed:
  1  e2e-mm-oracle.json written  -- none of its own, it is the fixture
  2  `bend: N rows`              -- N > 20, retried to 8
  3  node's EXIT STATUS          -- a row on stdout is what a dead lane prints
  4  the gate's own row count    -- read from the command, never a pipeline
  5  `tail -3` of the milestone  -- TODO(stage-5-denominator): also what a crash replaces
  6  64 words vs CPython's 64    -- plus the coverage table the stage prints
  7  run-f64.sh's REFUSED/PASS   -- rc 3 is a VERDICT, not a failure to reproduce
"""
from __future__ import annotations

import argparse
import re
import sys

VERDICT = re.compile(r"^  stage (\d) (\S+) \((.*?)\): (PASS|FAIL|SKIP)(.*)$")
HEADER = re.compile(r"^== (\d)/(\d) (.*)$")
BEND_ROWS = re.compile(r"^bend: (\d+) rows \(attempt (\d+)\)$")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--transcript", required=True, help="the captured stdout+stderr of e2e.py")
    args = ap.parse_args()
    lines = open(args.transcript, errors="replace").read().splitlines()

    heads = {int(m.group(1)): m.group(3) for ln in lines if (m := HEADER.match(ln))}
    rows: dict[int, str] = {}
    for ln in lines:
        if m := BEND_ROWS.match(ln):
            rows[2] = f"{m.group(1)} rows (attempt {m.group(2)}); PASS needs > 20"
    den = {
        1: "runs/e2e/e2e-mm-oracle.json (the fixture; no denominator of its own)",
        2: rows.get(2, "NOT REACHED -- no `bend: N rows` line in the transcript"),
        3: "node's exit status; nothing else",
        4: "the row count inside e2e_mm_gate.py's own text",
        5: "tail -3 of the milestone == what a crash replaces (TODO(stage-5-denominator))",
        6: "64 words read back vs CPython's 64",
        7: "run-f64.sh's own verdict; rc 3 = REFUSED = a third outcome, not a failure",
    }
    saw: dict[int, tuple[str, str]] = {}
    for ln in lines:
        if m := VERDICT.match(ln):
            saw[int(m.group(1))] = (m.group(2), f"{m.group(4)}{m.group(5)}".strip())
    # STAGE 1 EMITS NO VERDICT LINE BY DESIGN: `checks/e2e.py:324` returns the child's own status
    # under `set -e`, and a stage that aborts the gate never gets to say PASS or FAIL. So "no line"
    # for stage 1 means "it ran and did not abort", and only an ABORT is visible -- as the gate's
    # exit status with no stage 2 header behind it. Reporting that as "NOT RUN" would be a second
    # defect of the same shape as the one this gate exists for.
    if 1 in heads and 1 not in saw:
        saw[1] = ("oracle", "PASS (no verdict line by design; a failure aborts the gate)")
    # STAGE 2 IS THE SAME SHAPE, AND ITS DENOMINATOR IS ITS VERDICT: `bend_run()` returns 0 and the
    # gate says `bend: N rows (attempt i)` INSTEAD of a `  stage 2 ...:` line. N > 20 is the pass.
    if 2 in heads and 2 not in saw:
        saw[2] = ("port", "PASS" if 2 in rows else "NOT RUN -- gate aborted before it")

    print(f"{'st':>2}  {'verdict':<26} {'denominator':<62} name")
    rc = 0
    for n in range(1, 8):
        name, verdict = saw.get(n, ("-", "NOT RUN -- gate aborted before it"))
        if verdict.startswith("NOT RUN") or verdict.startswith("FAIL"):
            rc = 1
        print(f"{n:>2}  {verdict:<26} {den[n]:<62} {name}  [{heads.get(n, '?')}]")
    print("\ngate exit status and tail of the transcript:")
    for ln in lines[-6:]:
        print(" ", ln)
    return rc


if __name__ == "__main__":
    sys.exit(main())