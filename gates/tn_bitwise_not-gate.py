#!/usr/bin/env python3
"""tn_bitwise_not-gate.py -- THE GATE for `tinybendygrad/tensor.bend`'s `tn_bitwise_not`.

    .venv/bin/python gates/tn_bitwise_not-gate.py

EIGHT ROWS, THREE LANES -- CPython, bend interpreted, bend compiled -- over the
claims that `tn_bitwise_not` (the bool arm of elementwise.py:145) does what
CPython's `Tensor.bitwise_not` does on a bool input: it builds the same
CONST-True + CMPNE graph (the CAST folds away on a bool input -- CPython's
`cast` returns `self` when the dtype matches, `mixin/dtype.py:36`).

THE THREE-ARM DISPATCH IS NOW PORTED AND ONE ROW WITNESSES IT. `elementwise.py:156-157` is

    if self.dtype == dtypes.bool: return self.logical_not()
    return (self ^ self.dtype.max) if dtypes.is_unsigned(self.dtype) else (self ^ -1)

so `tn_bitwise_not` returns `Maybe<&2, Tensor>`. Rows 1-7 ALL use `mk_bitnot`'s BOOL fixture and
therefore all take the FIRST arm; the eighth row is signed, takes the `^ -1` arm, and asserts the
top op is XOR. THIS ROW WAS `True{}` -- IT COULD NOT FAIL.

WHAT THIS IS FOR. Closes the third of the four `nn/__init__.bend:241` walls.
The remaining two: `where` (needs `_broadcasted`) and `square` (needs
`__mul__`).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

# THE ROWS, NAMED ONCE.
ROWS = (
    "bitnot_op_is_cmpne",
    "bitnot_arg_is_anone",
    "bitnot_srcs_are_input_and_true",
    "bitnot_identity_cast_folded",
    "bitnot_input_is_bool",
    "bitnot_does_not_mutate_input",
    "bitnot_signed_takes_xor_arm",
)

GATE = Gate(
    "tn_bitwise_not-gate",
    bend="tn_bitwise_not.bend",
    oracle="tn_bitwise_not-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_bitwise_not-gate: 7 rows, 3 lanes -- six on the BOOL arm of the three-arm "
                        "dispatch at `elementwise.py:156-157` (op/arg/srcs/the identity-cast FOLD/"
                        "the fold's precondition/input purity) and one on the SIGNED `^ -1` arm. "
                        "The UNSIGNED arm is built but UNMEASURED: no fixture is unsigned, because "
                        "it takes a `CAST(..., u8)` first"))