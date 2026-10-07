#!/usr/bin/env python3
"""tn_fdiv_mod-gate.py -- THE GATE for `tn_fdiv` / `tn_rfdiv` / `tn_mod` / `tn_rmod`.

    .venv/bin/python gates/tn_fdiv_mod-gate.py

SEVENTEEN ROWS, THREE LANES. CPython's `Tensor.__floordiv__` (elementwise.py:279,
`self.div(x, rounding_mode="floor")`) routes through `div` (elementwise.py:229)
which at :249-252 is `a, b = self._broadcasted(x, reverse); if
dtypes.is_int(a.dtype) and dtypes.is_int(b.dtype): if rounding_mode == "floor":
return a.alu(Ops.FLOORDIV, b)`. For two Tensors of the same shape (the
no-broadcasting case the wall text at `nn/__init__.bend:241` cited as the
blocker), `_broadcasted` is identity: `__floordiv__` is `self.alu(FLOORDIV, x)`
-- srcs `(self, x)`. The `reverse=True` arm swaps: `__rfloordiv__` is
`x.alu(FLOORDIV, self)` -- srcs `(x, self)`. CPython's `__mod__`
(elementwise.py:282, `self.mod(x)`) is the same shape with `Ops.FLOORMOD` via
`mod` at elementwise.py:212-213, and `__rmod__` is the `reverse=True` arm.
The wall at `nn/__init__.bend:241` named `_broadcasted` as the blocker; with
`tn_fdiv` / `tn_rfdiv` / `tn_mod` / `tn_rmod` ported, the no-broadcasting case
of all four dunders is covered. The broadcasting case stays walled on
`_broadcasted`. `__truediv__` (elementwise.py:276) is SKIPPED because its body
needs a `rounding_mode` argument the port does not track; the int-arm
(`rounding_mode="floor"`, FLOORDIV) IS ported, and the float-arm (the
`cast(default_float).alu(FDIV, b)` path past the int guard) is walled on the
dtype fold.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "fdiv_op_is_floordiv",                       # tn_fdiv sets op to FLOORDIV.
    "fdiv_arg_is_anone",                         # the FLOORDIV's arg is None.
    "fdiv_srcs_are_self_and_x",                  # the FLOORDIV's srcs are (self, x).
    "fdiv_does_not_mutate_input",                # the input still has its original op.
    "rfdiv_op_is_floordiv",                      # tn_rfdiv sets op to FLOORDIV (same op).
    "rfdiv_arg_is_anone",                        # arg is None.
    "rfdiv_srcs_are_x_and_self",                 # the `reverse` arm flips src order.
    "rfdiv_does_not_mutate_input",               # the input still has its original op.
    "mod_op_is_floormod",                        # tn_mod sets op to FLOORMOD.
    "mod_arg_is_anone",                          # the FLOORMOD's arg is None.
    "mod_srcs_are_self_and_x",                   # the FLOORMOD's srcs are (self, x).
    "mod_does_not_mutate_input",                 # the input still has its original op.
    "rmod_op_is_floormod",                       # tn_rmod sets op to FLOORMOD (same op).
    "rmod_arg_is_anone",                         # arg is None.
    "rmod_srcs_are_x_and_self",                  # the `reverse` arm flips src order.
    "rmod_does_not_mutate_input",                # the input still has its original op.
    "fdiv_mod_is_reachable",                     # the four defs are callable.
)

GATE = Gate(
    "tn_fdiv_mod-gate",
    bend="tn_fdiv_mod.bend",
    oracle="tn_fdiv_mod-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_fdiv_mod-gate: 17 rows, 3 lanes -- tn_fdiv, tn_rfdiv, "
                        "tn_mod, and tn_rmod all agree with CPython's "
                        "Tensor.__floordiv__ / __rfloordiv__ / __mod__ / __rmod__ "
                        "(op/arg/srcs/purity on the no-broadcasting case; the "
                        "broadcasting case stays walled on _broadcasted)"))
