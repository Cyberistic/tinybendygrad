#!/usr/bin/env python3
"""tn_graph_census-gate.py -- THE NOOP CENSUS over every ported `tn_*` public def.

    .venv/bin/python gates/tn_graph_census-gate.py

51 ROWS, THREE LANES, ONE DECLARED DIVERGENCE. `gates/tn_binop_sweep.bend` covers the
seventeen binops; `gates/tn_nary_arena.bend` covers the three-operand node. This covers the REST
of the ported surface in one artifact -- the unary ops, the compositions, THE ELEVEN REVERSE
ARMS THAT HAVE A CPYTHON COUNTERPART, and THE THREE `Maybe`-RETURNING DUNDERS (`__ge__`,
`__le__`, `__invert__`), which had NO GATE AT ALL before this and were the last ported defs
outside any artifact.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM -- `Arena.bottom()`, what
`Arena.node` answers for an index the arena does not hold. A `NOOP` anywhere in a graph is an
index read out of range and ALWAYS a defect, so the census prints every port's toposort op
sequence and a reader can see the bottom without a second lane. Four ports were found this way
-- `tn_relu`, `tn_relu6`, and the two const-wrappers under `tn_ceil` / `tn_floor` -- and they
are all clean now.

WHAT IT ASSERTS THAT NEEDS ONE. The op sequence itself, against CPython's graph for the method
each port mirrors. **FIFTY OF THE FIFTY-ONE ROWS ARE BYTE-IDENTICAL TO CPYTHON.** One is not.

`tn_isfinite` USED TO be five of six rows wrong for the bool `CAST` and is now ONE node SHORT,
which is a DIFFERENT divergence and not a smaller one. Those five were the identity bool
`CAST`: `logical_not` is
`self.cast(dtypes.bool).ne(True)` (elementwise.py:49), `cast` is `self if self.dtype ==
(dt:=to_dtype(dtype)) else ...alu(Ops.CAST, arg=dt)` (mixin/dtype.py:38) -- IT FOLDS on an
identity cast -- and the port built it with `O.UOp.cast`, which mints a node UNCONDITIONALLY
(ops.bend:2919). Every one of `tn_eq`, `tn_dunder_ge`, `tn_dunder_le`, `tn_dunder_invert` and
`tn_isfinite` is a `logical_not` over a node the fold already knows is `bool`, so CPython
built no CAST and the port built one. `tn_bitwise_not` was a SIXTH instance of the same thing
wearing a different hat: CPython's body has THREE arms (elementwise.py:156-157) and on a
non-bool input it is `self ^ -1`, so the port's bool-only shape was wrong on top of the cast.
Both are fixed in `tinybendygrad/tensor.bend`: `tn_logical_not` now folds its cast through
`D.cast_at`, and `tn_bitwise_not` dispatches on `tn_dtype`.

THE ONE ROW STILL DIVERGING, AND IT IS NOT THE CAST. `tn_isfinite` is 14 where CPython is
15, and the missing node is a **CONST leaf**, not a CAST: CPython's `self` is TWO distinct
uops in one graph. `_broadcasted`'s promote half is `return t if t.dtype ==
weak_dtype(out_dtype) else t._wrap_uop(remint(t._uop, dt))` (elementwise.py:29-31) -- "keep
weak CONST weak, might lift weakint -> weakfloat" -- so `self.eq(inf)` REMINTS the weakint
`CONST(4)` to a weakfloat `ConstFloat(4.0)` and `self != self` keeps the weakint one, and the
two hash-cons to different nodes. MEASURED, `.venv/bin/python` on `Tensor(UOp(Ops.CONST,
arg=4)).isfinite()`: the graph holds `CONST weakfloat 4.0` AND `CONST weakint 4`. The port's
`tn_isfinite` has ONE `CInt{4}` and reuses it for both halves. `remint` IS PORTED, as
`ew_remint` (`mixin/elementwise.bend:373`) -- and `mixin/elementwise.bend` IMPORTS
`tensor.bend`, so `tensor.bend` cannot call it without an import cycle. That is the wall, it
is named, and closing it means moving `remint` down to a module both can see.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT -- AND `tn_isfinite` IS THE ROW THAT PROVED IT. `Rng.sig` prints the toposort COUNT,
the TOP op and the TOP's srcs, so `17 Ops.CMPNE/2 Ops.CAST Ops.CONST` read as "one extra
CAST" was a claim about three slots and was wrong by TWO nodes net: three extra CASTs and one
MISSING CONST, which cancelled to +2 and hid each other for however long the pin stood. The
missing CONST was in the port all along and nothing could see it behind a CAST that was also
missing. THE COUNT IS THE HONEST COLUMN; THE PREFIX IS NOT.

`tn_ceil` computed `b + 4` for a `CInt{4}` input through a LEGAL index and showed no
bottom at all; only the value rows in `gates/tn_ceil_floor.bend` caught it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "tn_sqrt",
    "tn_detach",
    "tn_contiguous_backward",
    "tn_trunc",
    "tn_reciprocal",
    "tn_sin",
    "tn_log2",
    "tn_exp2",
    "tn_rsqrt",
    "tn_logical_not",
    "tn_bitwise_not",
    "tn_neg",
    "tn_dunder_neg",
    "tn_relu",
    "tn_relu6",
    "tn_square",
    "tn_ceil",
    "tn_floor",
    "tn_isnan",
    "tn_isfinite",
    "tn_add",
    "tn_and",
    "tn_cmplt",
    "tn_cmpne",
    "tn_fdiv",
    "tn_lshift",
    "tn_max",
    "tn_maximum",
    "tn_mod",
    "tn_mul",
    "tn_or",
    "tn_pow",
    "tn_rshift",
    "tn_sub",
    "tn_xor",
    "tn_eq",
    "tn_threefry",
    "tn_radd",
    "tn_rsub",
    "tn_rmul",
    "tn_rfdiv",
    "tn_rmod",
    "tn_rand",
    "tn_ror",
    "tn_rxor",
    "tn_rpow",
    "tn_rlshift",
    "tn_rrshift",
    "tn_dunder_ge",
    "tn_dunder_le",
    "tn_dunder_invert",
)

# (CPython's line, the port's line), pinned on both sides.
# ONE DIVERGENCE, and it is NOT the bool CAST that six rows used to carry: those six are
# fixed and their pins are gone. `tn_isfinite` is the port missing ONE `CONST` leaf, because
# `_broadcasted`'s promote half REMINTS the weakint `self` to a weakfloat for the `eq(+/-inf)`
# halves while `self != self` keeps the weakint one, and CPython therefore holds two nodes
# where the port holds one. See the module docstring; `remint` is ported but it is in
# `mixin/elementwise.bend`, which imports `tensor.bend`.
DIVERGES = {
    "tn_isfinite": ("tn_isfinite=15 Ops.CMPNE/2 Ops.OR Ops.CONST", "tn_isfinite=14 Ops.CMPNE/2 Ops.OR Ops.CONST"),
}

GATE = Gate(
    "tn_graph_census-gate",
    bend="tn_graph_census.bend",
    oracle="tn_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_graph_census-gate: 51 rows, 3 lanes, 1 DECLARED divergence -- "
                        "every ported tn_* has NO NOOP BOTTOM and 50 op sequences match CPython's "
                        "byte-for-byte; tn_isfinite carries the ONE missing CONST leaf, which is "
                        "the weakint->weakfloat remint of `self` that `_broadcasted` does and "
                        "tensor.bend cannot call"))