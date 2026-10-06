#!/usr/bin/env python3
"""wk-cd-gate.py -- the CPython gate for `wk_commit_dtype`, the NODE-LEVEL reader that
nine of uop/weak.bend's markers said was missing.

    .venv/bin/python gates/wk-cd-gate.py

7 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- 6 IDENTICAL and ONE
DOCUMENTED DIVERGENCE (`cd_none`).

WHAT IS UNDER TEST. `tinygrad/mixin/dtype.py:16` is three lines:

    commit_int(self._uop.vmin, self._uop.vmax, default_int) if weakint else self.dtype

The port had the ARITHMETIC (`D.commit_dtype`, `mixin/dtype.bend`) and the BOUNDS
(`UOp.vmin`/`UOp.vmax`, `uop/fold.bend`). What was missing is the ONE call that joins them,
and it could not be written next to the arithmetic because `mixin/dtype.bend` does not
import `uop/weak.bend` while `wk_dt` lives here. So the wall those nine markers describe was
an IMPORT TOPOLOGY and not a language limit. MEASURED, the edge this adds
(`weak.bend -> mixin/dtype.bend`) closes no cycle: ops.bend, fold.bend and spec.bend all do
not import weak.bend.

THE GATE HAS TO CONTAIN TWO ROW-SETS OR IT PROVES NOTHING, and both were found by writing it:

  THE FIXTURE MUST BE A weakint PARAM. A PARAM whose dtype is int32 answers `i32` on EVERY
  row, because the weakint branch is not taken and `commit_dtype` returns `self.dtype`. The
  first oracle had seven rows of `i32`.

  THE ROWS THAT DISCRIMINATE ARE THE BIG ONES. `commit_int`'s ladder is
  `(default_int, dtypes.int, dtypes.long, ...)` and its first rung holds every range inside
  int32, so `cd_0_10`, `cd_neg5_5` and `cd_i32full` all answer i32 and say nothing.
  `cd_big_2p40` and `cd_one_2p40` do not fit and fall through to int64. A control that made
  the reader ignore its bounds turns this gate RED, so the rows are load-bearing.

THE DIVERGENCE IS NAMED AND PINNED. CPython answers `i64`; the port answers nothing, because
a PARAM with no `vmin_vmax` gives the bounds sweep no interval to report.
`wk_commit_dtype` is FAITHFUL here -- it hands `D.commit_dtype` exactly what
`UOp.vmin`/`UOp.vmax` gave it -- so the gap is the sweep's PARAM-with-no-bounds arm and not
the reader. Both sides' content is asserted, so it cannot change unnoticed in either
direction, and the port-side message says what to do if the sweep arm is ever fixed.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate as run_gate

GATE = Gate(
    "wk-cd-gate",
    bend="wk-cd.bend",
    oracle="wk-cd-oracle.py",
    rows=7,
    compared=7,
    pins=[
        ("py", "cd_big_2p40"),
        ("py", "cd_one_2p40"),
        ("bd", "cd_big_2p40"),
        ("bd", "cd_one_2p40"),
    ],
)

if __name__ == "__main__":
    sys.exit(run_gate(
        GATE, "wk-cd-gate: 7 rows identical, 3 lanes, 0 documented divergences -- the cd_none "
            "row that this gate was pinned on is closed (commit_dtype.weak now supplies the widest int64 "
            "range when bounds are unavailable, and commit_int answers i64 the same way CPython's commit_int does)"))
