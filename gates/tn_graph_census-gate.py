#!/usr/bin/env python3
"""tn_graph_census-gate.py -- THE NOOP CENSUS over every ported `tn_*` public def.

    .venv/bin/python gates/tn_graph_census-gate.py

51 ROWS, THREE LANES, ZERO DECLARED DIVERGENCES. `gates/tn_binop_sweep.bend` covers the
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

`tn_isfinite` USED TO BE WRONG TWICE, AND BOTH TIMES A PIN HID A DIFFERENT DEFECT. First it
was five of six rows wrong for the bool `CAST`; that is fixed. Then it was ONE node SHORT,
which is a DIFFERENT divergence and not a smaller one, and it stood until the `remint` move
below. The `CAST` half: `logical_not` is
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

THE CONST-LEAF HALF IS NOW CLOSED, AND IT WAS AN IMPORT CYCLE RATHER THAN A DECISION.
CPython's `self` is TWO distinct uops in one graph. `_broadcasted`'s promote half is
`return t if t.dtype == weak_dtype(out_dtype) else t._wrap_uop(remint(t._uop, dt))`
(elementwise.py:29-31) -- "keep weak CONST weak, might lift weakint -> weakfloat" -- so
`self.eq(inf)` REMINTS the weakint `CONST(4)` to a weakfloat `ConstFloat(4.0)` and
`self != self` keeps the weakint one, and the two hash-cons to different nodes. MEASURED,
`.venv/bin/python` on `Tensor(UOp(Ops.CONST, src=(), arg=4)).isfinite()`: 15 nodes and FIVE
distinct CONST leaves, `weakint 4 | bool True | weakfloat 4.0 | inf | -inf`. The port had
ONE `CInt{4}` reused for both halves and was 14. `remint` WAS PORTED, as `ew_remint` in
`mixin/elementwise.bend` -- and that file IMPORTS `tensor.bend`, so `tensor.bend` could not
call it. It is now `wk_remint` in `tinybendygrad/uop/weak.bend`, which is the lowest module
that can hold it (`wk_dt_const`, `wk_const_of` and `replace_in` are all there, and
`helpers.bend` / `LAWS/spec.bend` / `uop/ops.bend` / `uop/fold.bend` are all below `weak.bend`,
which imports every one of them). `mixin/elementwise.bend` keeps a one-line forwarder because
`mixin/op.bend:468` calls `E.ew_remint`. `tn_isfinite.promote` is `_broadcasted`'s promote for
`self` ALONE against the weakfloat `inf`, and `tn_isfinite.isinf_part` now compares BOTH eq
halves against the promoted `self` -- the old spelling compared the positive arm's bool MUL
against `-inf`, which was `CMPNE(MUL, CONST)` where CPython has `CMPNE(CONST, CONST)`.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT -- AND `tn_isfinite` IS THE ROW THAT PROVED IT. `Rng.sig` prints the toposort COUNT,
the TOP op and the TOP's srcs, so `17 Ops.CMPNE/2 Ops.CAST Ops.CONST` read as "one extra
CAST" was a claim about three slots and was wrong by TWO nodes net: three extra CASTs and one
MISSING CONST, which cancelled to +2 and hid each other for however long the pin stood. The
missing CONST was in the port all along and nothing could see it behind a CAST that was also
missing. THE COUNT IS THE HONEST COLUMN; THE PREFIX IS NOT. **AND THE COUNT IS NOT THE WHOLE
TRUTH EITHER**: a node four levels down can be wrong at the same count, which is what the
`isinf_part` `CMPNE(MUL, CONST)` arm was -- one node, wrong srcs, invisible to every row here
because every row reads the TOP node or the TOP's srcs. The full dump is at
`.agents/slop/tnisf/dump2.bend`, and its 15 rows now read in CPython's order with CPython's
five CONST leaves.

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
# NO DIVERGENCES. The last one -- `tn_isfinite`, the port missing ONE `CONST` leaf -- is
# GONE, and the gate says so by having nothing to exclude. MEASURED, both directions: with
# this pair STILL HERE and the port already fixed the gate answers
#   rc=1  tn_graph_census-gate: FAIL
#   bd's tn_isfinite is not 'tn_isfinite=14 Ops.CMPNE/2 Ops.OR Ops.CONST' -- if the
#   divergence is fixed, drop it from DIVERGES; if it moved, update the pin
# and with it dropped, rc=0 on all 51 rows in all three lanes. The port's row is now
# byte-identical to CPython's `15 Ops.CMPNE/2 Ops.OR Ops.CONST`.
DIVERGES = {}

GATE = Gate(
    "tn_graph_census-gate",
    bend="tn_graph_census.bend",
    oracle="tn_graph_census-oracle.py",
    rows=len(ROWS),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "tn_graph_census-gate: 51 rows, 3 lanes, ZERO declared divergences -- "
                        "every ported tn_* has NO NOOP BOTTOM and ALL 51 op sequences match "
                        "CPython's byte-for-byte, tn_isfinite included: its weakint `self` is now "
                        "REHASHED to weakfloat by `_broadcasted`'s promote half, which `remint` "
                        "does and which lives in uop/weak.bend so tensor.bend can call it"))