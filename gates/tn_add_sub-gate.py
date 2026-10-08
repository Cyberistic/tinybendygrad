#!/usr/bin/env python3
"""tn_add_sub-gate.py -- THE GATE for `tn_add` / `tn_radd` / `tn_sub` / `tn_rsub`.

    .venv/bin/python gates/tn_add_sub-gate.py

SEVENTEEN ROWS, THREE LANES. CPython's `Tensor.__add__` (elementwise.py:267, via
`add` at :84) is `a, b = self._broadcasted(x, reverse); return a.alu(Ops.ADD,
-b)`. The `-b` is a CONST trap (and a unary minus on a Tensor is also walled),
so for two Tensors of the same shape (the no-broadcasting case the wall text
at `nn/__init__.bend:241` cited as the blocker) `_broadcasted` is identity and
the body reduces to `_binop`'s shape (elementwise.py:36) with `MUL` replaced by
`ADD`: `__add__` is `self.alu(ADD, x)` -- srcs `(self, x)`. The `reverse=True`
arm swaps: `__radd__` is `x.alu(ADD, self)` -- srcs `(x, self)`. CPython's
`__sub__` (elementwise.py:270, via `sub` at :103) and `__rsub__`
(elementwise.py:297) are the same shape with `Ops.SUB` instead of `Ops.ADD`.
The wall at `nn/__init__.bend:241` named `_broadcasted` as the blocker; with
`tn_add` / `tn_radd` / `tn_sub` / `tn_rsub` ported, the no-broadcasting case
of all four dunders is covered. The broadcasting case stays walled on
`_broadcasted`.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "add_op_is_add",                          # tn_add sets op to ADD.
    "add_arg_is_anone",                       # the ADD's arg is None.
    "add_srcs_are_self_and_x",                # the ADD's srcs are (self, x).
    "add_does_not_mutate_input",              # the input still has its original op.
    "radd_op_is_add",                         # tn_radd sets op to ADD (same op).
    "radd_arg_is_anone",                      # arg is None.
    "radd_srcs_are_x_and_self",               # the `reverse` arm flips src order.
    "radd_does_not_mutate_input",             # the input still has its original op.
    "sub_op_is_add",                          # tn_sub sets op to SUB.
    "sub_arg_is_anone",                       # the SUB's arg is None.
    "sub_src0_is_self",
    "sub_src1_is_neg_x",                # the SUB's srcs are (self, x).
    "sub_does_not_mutate_input",              # the input still has its original op.
    "rsub_op_is_add",                         # tn_rsub sets op to SUB (same op).
    "rsub_arg_is_anone",                      # arg is None.
    "rsub_src0_is_x",
    "rsub_src1_is_neg_self",               # the `reverse` arm flips src order.
    "rsub_does_not_mutate_input",             # the input still has its original op.
    "add_sub_is_reachable",                   # the four defs are callable.
)

GATE = Gate(
    "tn_add_sub-gate",
    bend="tn_add_sub.bend",
    oracle="tn_add_sub-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_add_sub-gate: 19 rows, 3 lanes -- tn_add, tn_radd, "
                        "tn_sub, and tn_rsub all agree with CPython's "
                        "Tensor.__add__ / __radd__ / __sub__ / __rsub__ "
                        "(op/arg/srcs/purity on the no-broadcasting case; the "
                        "broadcasting case stays walled on _broadcasted)"))