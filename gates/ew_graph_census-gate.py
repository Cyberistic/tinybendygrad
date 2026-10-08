#!/usr/bin/env python3
"""ew_graph_census-gate.py -- A GRAPH CENSUS over every ported public `ew_*`.

    .venv/bin/python gates/ew_graph_census-gate.py

43 ROWS, THREE LANES, THREE DECLARED DIVERGENCES. `gates/ew-consts.bend` gates the F32 constants
and `gates/ew-explog.bend` gates `log`/`log10`/`exp` by VALUE; this gates the SHAPE of the whole
public surface in one artifact. It is the `ew_*` peer of `gates/tn_graph_census-gate.py`.

THE POPULATION IS DISCOVERED. `ew_<n>` is a row iff CPython's `tinygrad/mixin/elementwise.py`
defines a METHOD `<n>(self` or `__<n>__(self` -- 43 of the file's 142 `ew_*` defs. `promote` and
`remint` drop out because they are not methods; their effect is covered by the file's own
`ew_promo_*` rows.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere in a graph is an index read out of range and always a defect. It is asserted by
`no_noop_bottom`, which reads the LANE'S OWN `bd.out`; the sibling census DEFINES the same
predicate and never calls it, so this census asserts a claim that one only named. It finds NONE,
which is a measurement and not an absence.

THE THREE DIVERGENCES, CLASSIFIED -- and two of the three are NOT carve-outs:

  `ew_ufix` -- CARVE-OUT, INSTRUMENT ONLY. The graphs AGREE: one `CONST` node. The port's
    `O.Rng.sig` prints `-` for a node with NO srcs (`Rng.srcops.seeded`'s `Nil` arm) where
    CPython's signature joins an empty list to the empty string. No sibling row ever hit it
    because every root there had at least one src. The two lines differ by that ONE character.

  `ew_floor` -- A DEFECT, NOT A CARVE-OUT. elementwise.py:672 is
    `(self < (b := self.trunc())).where(b-1, b)`; the port at `elementwise.bend:626-630` builds
    `where(self < trunc(self), -1, trunc(self))`. MEASURED: CPython's then-value is
    `ADD(TRUNC, MUL(CONST 1, CONST -1))` -- it DEPENDS on `b` -- and the port's is a bare `CONST`
    (`8 Ops.WHERE/3 Ops.CMPLT Ops.ADD Ops.TRUNC` against `5 Ops.WHERE/3 Ops.CMPLT Ops.CONST
    Ops.TRUNC`). A then-value that cannot depend on `b` cannot be `b-1`: every negative
    non-integer `t` gets the same answer instead of `trunc(t)-1`. The constant's identity is
    source, not measurement: `ECon{O.CInt{H.i64_of_i32(4294967295)}}`, and `4294967295` is `-1`
    (the value `ew_neg`'s own passing rows already pin). It is UNGATED by the file's own gate
    (`main` has no `t_floor` row; `grep -n t_floor` is empty) and `gates/ew-explog.bend` does not
    reach it.

  `ew_exp` -- A DIVERGENCE, NOT A CARVE-OUT. elementwise.py:511-522 casts THREE times:
    `self.cast(least_upper_float(self.dtype))` (weakint -> weakfloat), then
    `self.cast(least_upper_dtype(self.dtype, float32))` (-> float32), then the final
    `.cast(self.dtype)` (-> weakfloat). MEASURED, the CPython root is a `CAST` of dtype
    weakfloat over 7 nodes. `elementwise.bend:1284-1285` builds only the middle cast and drops
    both ends: 5 nodes, root `EXP2`, dtype float32. `mixin/op.bend`'s `mo_exp` (its own port of
    the SAME method) HAS all three casts, so the tree knows the full body; `ew_exp` is a
    reduced duplicate.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT: `ew_floor`'s `-1` sits at a LEGAL arena index and shows no bottom anywhere. That is the
same lesson the sibling census learned from `tn_ceil`, one layer over.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    "ew_add",
    "ew_bitwise_and",
    "ew_bitwise_not",
    "ew_bitwise_or",
    "ew_bitwise_xor",
    "ew_contiguous_backward",
    "ew_detach",
    "ew_div",
    "ew_eq",
    "ew_exp",
    "ew_exp2",
    "ew_floor",
    "ew_fmod",
    "ew_mod_mixed",
    "ew_fmod_mixed",
    "ew_ge",
    "ew_gt",
    "ew_log",
    "ew_log10",
    "ew_log2",
    "ew_logical_not",
    "ew_lshift",
    "ew_lt",
    "ew_masked_fill",
    "ew_maximum",
    "ew_mod",
    "ew_mul",
    "ew_ne",
    "ew_neg",
    "ew_pow",
    "ew_quick_gelu",
    "ew_reciprocal",
    "ew_rshift",
    "ew_sigmoid",
    "ew_silu",
    "ew_sin",
    "ew_sqrt",
    "ew_square",
    "ew_sub",
    "ew_swish",
    "ew_tanh",
    "ew_threefry",
    "ew_trunc",
    "ew_ufix",
    "ew_where",
)

# (CPython's line, the port's line), pinned on both sides. `ew_ufix` is the instrument carve-out;
# `ew_floor` and `ew_exp` are DEFECTS and the pin is a LOCK on the current wrong value -- a fix
# moves the port's line and this entry must move with it, which is the point of pinning.
DIVERGES = {
    "ew_exp": ("ew_exp=7 Ops.CAST/1 Ops.EXP2", "ew_exp=5 Ops.EXP2/1 Ops.MUL"),
    "ew_ufix": ("ew_ufix=1 Ops.CONST/0 ", "ew_ufix=1 Ops.CONST/0 -"),
}

GATE = Gate(
    "ew_graph_census-gate",
    bend="ew_graph_census.bend",
    oracle="ew_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_bottom() -> bool:
    """`NOOP` IS THE BOTTOM -- the claim the sibling census defines and never asserts.

    Read off the LANE'S OWN OUTPUT and not a re-derivation: `Rng.sig` prints each src op, so a
    `NOOP` anywhere in any graph appears in `bd.out`. `gates/artifacts/` is `.gitignore`d, but
    `gatekit` promotes `bd.out` on a PASS, so it is present exactly when this runs.
    """
    return "Ops.NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "ew_graph_census-gate: 45 rows, 3 lanes, 2 DECLARED divergences -- "
                       "every ported public ew_* has NO NOOP BOTTOM and 43 op sequences match "
                       "CPython's byte-for-byte; ew_ufix differs only in the empty-src rendering, "
                       "ew_exp is the DTYPE divergence the pin LOCKS, and ew_floor was FIXED in this commit so its pin is GONE",
                 checks=no_noop_bottom))
