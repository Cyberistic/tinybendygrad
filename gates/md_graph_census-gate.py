#!/usr/bin/env python3
"""md_graph_census-gate.py -- A GRAPH CENSUS over the GRAPH-BUILDING methods of
`tinybendygrad/mixin/dtype.bend`.

    .venv/bin/python gates/md_graph_census-gate.py

22 ROWS, THREE LANES, FIVE DECLARED DIVERGENCES -- AND NONE OF THE FIVE IS A CODE DEFECT.
`gates/uop_cast-gate.py` gates `uop/ops.bend`'s `UOp.cast` by VALUE; this gates the SHAPE of
`mixin/dtype.bend`'s cast surface in one artifact. The two are different defs: the documented
`UOp.cast` "always builds a new node" deviation is in `ops.bend`, NOT here, and this census
confirms the identity arm of `cast_at` DOES fold.

THE POPULATION IS DISCOVERED, NOT LISTED. A port def is a row iff `tinygrad/mixin/dtype.py`
defines the method it mirrors. `DTypeMixin` has SIXTEEN names; THREE are abstract declarations
Python raises `NotImplementedError` from (`dtype`, `_uop`, `_wrap_uop`) and are not ports,
leaving THIRTEEN methods. THREE of those are READERS -- `commit_dtype` (a dtype), `element_size`
(an int), `is_floating_point` (a bool) build NO graph, so a graph census cannot print them and
they FALL OUT. TEN build a graph:

    cast -> cast_at          bitcast -> bitcast_at
    float -> cast_float      half  -> cast_half      int  -> cast_int
    bool  -> cast_bool       bfloat16 -> cast_bfloat16
    double -> cast_double    long  -> cast_long      short -> cast_short

The other 164 of the file's 177 defs are the plumbing (`md_dt`, `md_i64_*`, `commit_int.*`,
`strong_dtype*`, `md_weak*`, the `f_*` accessors), the gate's own rows (`t_*`, 93 of them),
its printers (`row`, `b`) and its fixtures (`g_fix`, `fx_wi*`), exactly the way the sibling
censuses drop `ew_join` / `cr_cast`.

WHAT IT ASSERTS. The port's toposort OP SEQUENCE **plus the root's arg dtype name** against
CPython's, for the method each def mirrors. The printer is the port's OWN `O.Rng.sig`
(`ops.bend:5897`); the ` arg=<name>` suffix is added because `Rng.sig` does NOT print an arg and
a CAST's whole point is its arg -- without it `cast_short` (i16) and `cast_int` (i32) are the
same line. CPython's `DType.name` and the port's `S.Dt` `nm` are the same table (f16/f32/i32/...),
measured.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere in a graph is an index read out of range and always a defect. It is asserted by
`no_noop_bottom`, which reads the LANE'S OWN `bd.out`. It finds NONE, which is a measurement.

THE FIVE DIVERGENCES, ALL CLASSIFIED -- every one is a REPRESENTATION difference, not a defect:

  cast_same_weakint, cast_wf_same, cast_bool_same -- CARVE-OUT, INSTRUMENT ONLY. The graphs
    AGREE: one `CONST` node, the identity arm. The port's `O.Rng.sig` prints `-` for a node with
    NO srcs (`Rng.srcops.seeded`'s `Nil` arm) where CPython's signature joins an empty list to
    the empty string. The two lines differ by that ONE character -- the same carve-out
    `ew_graph_census` pins as `ew_ufix`. THREE rows hit it here because three sources are CONSTs.

  bitcast_weak_src, bitcast_weak_dst -- CARVE-OUT, REPRESENTATION. `bitcast` RAISES
    `RuntimeError` on a weak dtype (`dtype.py:52`); the port models the raise as `None` (there is
    no Bend spelling for a `RuntimeError`), so the port prints `None` and CPython prints the
    exception's NAME. The refusal ARMS are the same arm; only the answer's carrier differs.

EXIT STATUS: 0 all three lanes identical after the pins · 1 a lane took the wrong row count, the
oracle failed, the native compile failed, or the lanes disagree · 3 a precondition was absent
(the output directory, the substrate, or the oracle). `DEAD`/`SKIP` are `gatekit`'s 5/4 and this
gate does not produce them.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    # `cast` (dtype.py:19 -> cast_at)
    "cast_weak_to_f32",
    "cast_same_weakint",
    "cast_weakfloat_to_i32",
    "cast_wf_same",
    "cast_bool_to_i32",
    "cast_concrete_to_f32",
    "cast_concrete_same",
    "cast_weak_to_weakfloat",
    # `bitcast` (dtype.py:38 -> bitcast_at)
    "bitcast_concrete_to_u32",
    "bitcast_concrete_same",
    "bitcast_weak_src",
    "bitcast_weak_dst",
    # the eight named casts (dtype.py:79-142)
    "cast_float",
    "cast_half",
    "cast_int",
    "cast_bool",
    "cast_bfloat16",
    "cast_double",
    "cast_long",
    "cast_short",
    # the two identity rows
    "cast_half_same",
    "cast_bool_same",
)

# (CPython's line, the port's line), pinned on both sides. THE TRAILING CONTENT IS PART OF THE
# LINE: the identity rows carry TWO spaces on CPython's side (`/0  arg=-`, an empty src join)
# and the port carries `-` (`/0 - arg=-`); `gatekit`'s `want not in raw[lane]` is an exact-line
# test, so a pin without the exact spacing would never match.
DIVERGES = {
    # the zero-src rendering: `Rng.srcops` prints `-`, CPython's join prints `""`.
    "cast_same_weakint": ("cast_same_weakint=1 Ops.CONST/0  arg=-",
                          "cast_same_weakint=1 Ops.CONST/0 - arg=-"),
    "cast_wf_same": ("cast_wf_same=1 Ops.CONST/0  arg=-",
                     "cast_wf_same=1 Ops.CONST/0 - arg=-"),
    "cast_bool_same": ("cast_bool_same=1 Ops.CONST/0  arg=-",
                       "cast_bool_same=1 Ops.CONST/0 - arg=-"),
    # the raise: CPython's `RuntimeError` vs the port's `None` refusal carrier.
    "bitcast_weak_src": ("bitcast_weak_src=RuntimeError", "bitcast_weak_src=None"),
    "bitcast_weak_dst": ("bitcast_weak_dst=RuntimeError", "bitcast_weak_dst=None"),
}

GATE = Gate(
    "md_graph_census-gate",
    bend="md_graph_census.bend",
    oracle="md_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_bottom() -> bool:
    """`NOOP` IS THE BOTTOM -- a `NOOP` in any row is an index read out of range.

    Read off the LANE'S OWN OUTPUT and not a re-derivation: `Rng.sig` prints each src op, so a
    `NOOP` anywhere in any graph appears in `bd.out`. `gates/artifacts/` is `.gitignore`d, but
    `gatekit` promotes `bd.out` on a PASS, so it is present exactly when this runs.
    """
    return "Ops.NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "md_graph_census-gate: 22 rows, 3 lanes, 10 graph-building dtype "
                        "methods -- no NOOP bottom, 17 op sequences match CPython byte-for-byte, "
                        "and the 5 divergences are ALL representation carve-outs (3 zero-src "
                        "renderings, 2 raise-vs-None refusals), NO defect",
                 checks=no_noop_bottom))
