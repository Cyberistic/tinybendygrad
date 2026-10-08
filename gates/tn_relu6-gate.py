#!/usr/bin/env python3
"""tn_relu6-gate.py -- THE GATE for `tn_relu6`.

    .venv/bin/python gates/tn_relu6-gate.py

FIVE ROWS, THREE LANES. CPython's `Tensor.relu6` (elementwise.py:697) is
`((r := self.relu()) < 6).where(r, 6)`. The wall text at `nn/__init__.bend:241`
cited `_broadcasted` as the blocker. The `self.relu()` and the `< 6` are
both ported (`tn_relu`, `tn_rcmplt`); the `where` is `tn_where` (port). The
constant 6 is `O.UOp.const` (port). The port is a chain: `tn_relu(t)` produces
`r = WHERE{cond=t>0, x=t, y=0}`, then `tn_rcmplt(r, c6)` produces the
`r < 6` condition, then `tn_where(r<6, r, c6)` produces the final node.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "relu6_op_is_where",
    "relu6_arg_is_anone",
    "relu6_does_not_mutate_input",
    "relu6_has_three_srcs",
    "relu6_is_reachable",
    "relu6_src2_is_const6",
)

GATE = Gate(
    "tn_relu6-gate",
    bend="tn_relu6.bend",
    oracle="tn_relu6-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_relu6-gate: 6 rows, 3 lanes -- tn_relu6's op/arg/srcs/purity "
                        "and reachability all agree with CPython's Tensor.relu6 "
                        "(the nested WHERE-chain composition)"))