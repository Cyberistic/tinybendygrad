#!/usr/bin/env python3
"""tn_mul-gate.py -- THE GATE for `tn_mul` / `tn_rmul` / `tn_square`.

    .venv/bin/python gates/tn_mul-gate.py

THIRTEEN ROWS, THREE LANES. CPython's `Tensor.__mul__` (elementwise.py:125) is
`return self._binop(Ops.MUL, x, reverse)`, where `_binop` (elementwise.py:36) is
`lhs, rhs = self._broadcasted(x, reverse); return lhs.alu(MUL, rhs)`. For two
Tensors of the same shape (the no-broadcasting case the wall text at
`nn/__init__.bend:241` cited as the blocker), `_broadcasted` is identity, so
`__mul__` is `self.alu(MUL, x)` -- srcs are `(self, x)`. The `reverse=True`
arm swaps: `lhs, rhs = (y, self)`, so `__rmul__` is `x.alu(MUL, self)` -- srcs
are `(x, self)`. The wall at `nn/__init__.bend:241` named `__mul__` as "a
separate wall (no arith ops are ported yet)"; with `tn_mul` / `tn_rmul`
ported, the body of `Tensor.square` (elementwise.py:575, `return self * self`)
collapses to `tn_mul(self, self)`. The port covers all three defs; the
broadcasting case stays walled on `_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "mul_op_is_mul",                       # tn_mul sets op to MUL.
    "mul_arg_is_anone",                    # the MUL's arg is None.
    "mul_srcs_are_self_and_x",             # the MUL's srcs are (self, x).
    "mul_does_not_mutate_input",           # the input still has its original op.
    "rmul_op_is_mul",                      # tn_rmul sets op to MUL (same op).
    "rmul_arg_is_anone",                   # arg is None.
    "rmul_srcs_are_x_and_self",            # the `reverse` arm flips src order.
    "rmul_does_not_mutate_input",          # the input still has its original op.
    "square_op_is_mul",                    # tn_square sets op to MUL.
    "square_arg_is_anone",                 # arg is None.
    "square_srcs_are_t_and_t",             # srcs are (t, t) -- self * self.
    "square_does_not_mutate_input",        # the input still has its original op.
    "mul_is_reachable",                    # the three defs are callable.
)

GATE = Gate(
    "tn_mul-gate",
    bend="tn_mul.bend",
    oracle="tn_mul-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_mul-gate: 13 rows, 3 lanes -- tn_mul, tn_rmul, and tn_square "
                        "all agree with CPython's Tensor.__mul__ / __rmul__ / .square() "
                        "(op/arg/srcs/purity on the no-broadcasting case; the broadcasting "
                        "case stays walled on _broadcasted)"))
