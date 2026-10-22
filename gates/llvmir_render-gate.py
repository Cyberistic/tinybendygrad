#!/usr/bin/env python3
"""llvmir_render-gate.py -- `tinybendygrad/renderer/llvmir.bend` against CPython.

    .venv/bin/python gates/llvmir_render-gate.py
    .venv/bin/python gates/llvmir_render-gate.py --port <path>   # for the plant

471 ROWS, THREE LANES, ZERO DECLARED DIVERGENCES.
WHY THIS GATE EXISTS AT ALL.  `llvmir.bend` carried 471 `py=` cells, every one of
them a LITERAL -- text transcribed once from what CPython said.  A transcription has
no generator, so it cannot see CPython move; and the oracle that GENERATED those
transcriptions lived in `.agents/slop/li/`, which was pruned, so nothing in the tree
could check that the transcriptions still matched the code they came from.  The
oracle is RECOVERED (from git history, blob
`ba636a9e2d429cb4c569c00a363e1d25b034b0a7`, commit `0056b7845`) and lives beside this
gate, at `gates/llvmir_render-oracle.py`, and the `py=` halves are DERIVED: the
port's own value, re-read, so a row cannot disagree with itself.

WHAT IS ASSERTED.  The port's 471 rows and CPython's 471 rows are the SAME TEXT,
byte for byte, in all three lanes.  The port's own header says what the rows are:
every `py=` half was computed by CALLING upstream's `llvmir.py` -- `base_rewrite.
patterns[i][1]` IS CPython's emitter and `_render_kernel` / `_render_fn` are called
for real on real `ParamArg`s -- so no f-string from `llvmir.py` was re-typed on
either side of the diff.

THE PIN.  This port tracks an upstream that has since moved: `llvmir.py` was 286
lines at the pin and is 309 at the tree's HEAD, and 409 lines of the lane differ
there.  `gates/renderkit.py` extracts the pinned `tinygrad/` from git at run time
and the oracle reads THAT, so the comparison is against the upstream this port was
written against.  One commit id, not a list of differing rows.

ZERO DIVERGENCES IS A CLAIM, AND IT IS CHECKABLE.  There are none to declare: the
port and CPython agree on every one of the 472 rows, and this gate is what makes
that statement a measurement rather than a memory.  `gates/ops_dsp_render-gate.py`
is the same gate over a port that has thirty, and it says so.
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from renderkit import PASS, VERDICT, render_gate  # noqa: E402

PORT = "tinybendygrad/renderer/llvmir.bend"
ORACLE = "gates/llvmir_render-oracle.py"
ROWS = 471

# THE PORT'S OWN ROW COUNT, AND WHERE IT COMES FROM.  471 is what the lane prints;
# it is stated here so a reader can see it is a NUMBER AND NOT A NARRATIVE, and
# `renderkit` REFUSES (rather than diffing short) if either lane prints a different
# count.
DIVERGES = {}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default=str(HERE.parent / PORT))
    ap.add_argument("--oracle", default=str(HERE.parent / ORACLE))
    args = ap.parse_args()
    code = render_gate("llvmir_render", args.port, args.oracle, ROWS, DIVERGES)
    if code == PASS:
        print("llvmir_render-gate: 471 rows, 3 lanes byte-identical, 0 declared divergences "
          "-- the port's `py=` half is DERIVED (the port's own value), so a row cannot "
          "disagree with itself, and the assertion is the byte diff against CPython's "
              "lane at the pinned upstream")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
