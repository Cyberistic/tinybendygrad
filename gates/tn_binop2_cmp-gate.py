#!/usr/bin/env python3
"""tn_binop2_cmp-gate.py -- THE GATE for the comparison binop ports and their
derivations in `tinybendygrad/tensor.bend`.

    .venv/bin/python gates/tn_binop2_cmp-gate.py

TWENTY-NINE ROWS, THREE LANES. CPython:
  - Tensor.__lt__        (elementwise.py:321, _binop(CMPLT, x, False))
  - Tensor.__gt__        (elementwise.py:324, _binop(CMPLT, x, True))
  - Tensor.__ne__        (elementwise.py:339, via ne at :333 _binop(CMPNE, x, False))
  - Tensor.__ge__        (elementwise.py:327, (self < x).logical_not())
  - Tensor.__le__        (elementwise.py:330, (self > x).logical_not())
  - Tensor.eq            (elementwise.py:336, self.ne(x).logical_not())

Each is the no-broadcasting case (two CONSTs of the same shape, so
`_broadcasted` is identity). The first three are pure `_binop` ops (port the
body as `tn_alu(self, OP, [Tensor.u(x)])` with a `reverse` dispatcher); the
last three are derivations on `tn_logical_not` (gated 4/4 at
`gates/tn_logical_not-gate.py`). The broadcasting case stays walled on
`_broadcasted` for all six.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    # tn_cmplt -- elementwise.py:321.
    "cmplt_op_is_cmplt",
    "cmplt_arg_is_anone",
    "cmplt_srcs_are_self_and_x",
    "cmplt_does_not_mutate_input",
    # tn_rcmplt -- elementwise.py:324, reverse arm.
    "rcmplt_op_is_cmplt",
    "rcmplt_arg_is_anone",
    "rcmplt_srcs_are_x_and_self",
    "rcmplt_does_not_mutate_input",
    # tn_cmpne -- elementwise.py:339, via ne at :333.
    "cmpne_op_is_cmpne",
    "cmpne_arg_is_anone",
    "cmpne_srcs_are_self_and_x",
    "cmpne_does_not_mutate_input",
    # tn_dunder_ge -- elementwise.py:327, `(self < x).logical_not()`.
    "ge_op_is_cmpne",
    "ge_arg_is_anone",
    "ge_does_not_mutate_input",
    "ge_is_reachable",
    # tn_dunder_le -- elementwise.py:330, `(self > x).logical_not()`.
    "le_op_is_cmpne",
    "le_arg_is_anone",
    "le_does_not_mutate_input",
    # tn_eq -- elementwise.py:336, `self.ne(x).logical_not()`.
    "eq_op_is_cmpne",
    "eq_arg_is_anone",
    "eq_does_not_mutate_input",
    "binop2_cmp_is_reachable",
)

GATE = Gate(
    "tn_binop2_cmp-gate",
    bend="tn_binop2_cmp.bend",
    oracle="tn_binop2_cmp-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_binop2_cmp-gate: 29 rows, 3 lanes -- tn_cmplt, tn_rcmplt, "
                        "tn_cmpne (no-broadcast binop ports for __lt__/__gt__/"
                        "__ne__) and tn_dunder_ge, tn_dunder_le, tn_eq (chains through "
                        "tn_logical_not) all agree with CPython"))