#!/usr/bin/env python3
"""tn_ceil_floor-gate.py -- THE GATE for `tn_ceil` / `tn_floor`.

    .venv/bin/python gates/tn_ceil_floor-gate.py

ELEVEN ROWS, THREE LANES. CPython's `Tensor.ceil` (elementwise.py:656) is
`(self > (b := self.trunc())).where(b+1, b)`. CPython's `Tensor.floor`
(elementwise.py:662) is `(self < (b := self.trunc())).where(b-1, b)`. The
wall text at `nn/__init__.bend:241` cited `_broadcasted` as the blocker for
`where` and Tensor-arith as the blocker for `b+1` / `b-1`. With `tn_where`,
`tn_trunc`, `tn_rcmplt`, `tn_cmplt`, `tn_add`, `tn_sub` and `O.UOp.const`
all ported, the no-broadcasting case of both `ceil` and `floor` is built
by a 4-step chain: `b := tn_trunc(self)`, cond := `tn_rcmplt(self, b)` (for
ceil) or `tn_cmplt(self, b)` (for floor), `b±1 := tn_add(b, c1t)` (for ceil)
or `tn_sub(b, c1t)` (for floor), and the final `tn_where(cond, b±1, b)`. The
broadcasting case stays walled on `_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "ceil_op_is_where",
    "ceil_arg_is_anone",
    "ceil_has_three_srcs",
    "ceil_does_not_mutate_input",
    "ceil_cond_is_cmplt",
    "floor_op_is_where",
    "floor_arg_is_anone",
    "floor_has_three_srcs",
    "floor_does_not_mutate_input",
    "floor_cond_is_cmplt",
    "ceil_floor_is_reachable",
    "ceil_src1_is_add",
    "floor_src1_is_add",
    "floor_src1_is_mul_by_neg1",
)

GATE = Gate(
    "tn_ceil_floor-gate",
    bend="tn_ceil_floor.bend",
    oracle="tn_ceil_floor-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_ceil_floor-gate: 14 rows, 3 lanes -- tn_ceil and tn_floor "
                        "both agree with CPython's Tensor.ceil / Tensor.floor "
                        "(the WHERE-chain composition of trunc + cmplt + add/sub + "
                        "where; _broadcasted seam still walls the broadcasting case)"))
