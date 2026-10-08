#!/usr/bin/env python3
"""mx_graph_census-gate.py -- A GRAPH CENSUS over the ported public movement WRAPPERS.

    .venv/bin/python gates/mx_graph_census-gate.py

17 ROWS, THREE LANES, ONE DECLARED DIVERGENCE -- AND IT IS A DEFECT, NOT A CARVE-OUT.
`tinybendygrad/mixin/movement.bend` had NO gate over it at all; this drives every
graph-building public def once per fixture and prints its toposort OP SEQUENCE next to
CPython's for the method it mirrors.

THE POPULATION IS DISCOVERED, NOT LISTED, and the discovery is two filters:

    # (1) the public surface: 85
    grep -o '^def mx[a-z_0-9]*' tinybendygrad/mixin/movement.bend | sort -u | wc -l

    # (2) a METHOD PORT: strip mxw_/mxm_/mx_ and ask CPython's movement.py for the method
    #     -> 7: mxm_expand->expand, mxm_shape->shape, mxw_flip->flip, mxw_pad->pad,
    #            mxw_permute->permute, mxw_reshape->reshape, mxw_shrink->shrink
    # (3) a ROW: the def BUILDS a graph (its body calls O.UOp.new / returns T.Tensor)
    #     -> 5: mxw_reshape mxw_permute mxw_pad mxw_shrink mxw_flip

`mxm_shape` (`-> List<&2, U32>`) and `mxm_expand` (`-> Bool`) drop out at (3): they are
READERS of a graph (the `_shape` arms of ops.py, and a one-bit op test), so there is no
toposort to print and no CPython method BODY to diff against. The five that remain are
exactly the five methods `tinygrad/mixin/movement.py` gives an identity test; the rest of the
file is not ported as graph builders, so 5 is the whole surface and not a sample.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere in a graph is an index read out of range and always a defect. The `no_noop_bottom`
check reads the LANE'S OWN `bd.out`; it finds NONE, which is a measurement and not an absence.

WHAT IT ASSERTS THAT NEEDS CPYTHON. The op sequence itself. The fixture is the port's own
`MX.mxw_base()` on the port side and a raw `UOp.new_buffer("PYTHON", 256, float)` reshaped on
the CPython side -- MEASURED, the two are the same graph (`6 Ops.RESHAPE/2 Ops.BUFFER
Ops.STACK`) while `Tensor.empty(1,4,8,8)` is an ALLOC and would move every no-op row.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT: a PAD whose two shape STACKs are swapped keeps the root op, the src count and the
toposort length and moves only the no-op rows; the src OP SEQUENCE is the only field that
sees it.

THE ONE DECLARED DIVERGENCE IS A DEFECT AND IS PINNED SO IT CANNOT BE FORGOTTEN:

    reshape_256   CPython 8 Ops.RESHAPE/2 Ops.RESHAPE Ops.CONST
                  port    9 Ops.RESHAPE/2 Ops.RESHAPE Ops.STACK

`shape_to_shape_arg` (ops.py:106-110) is `src[0] if len(src) == 1 else UOp(Ops.STACK,
src=src)`, so CPython folds a ONE-ELEMENT shape arg to a BARE `CONST`. `mxw_stk`
(movement.bend:1254) is `G.mstack` UNCONDITIONALLY, so the port builds a `STACK` and carries
one extra node. It is the port's own `mxm_reshape1` case (movement.bend:922-927 names it: the
bare-CONST arg is a different node, and `mxm_as_shape` reads a bare CONST as the EMPTY list),
and `mixin/rand.bend` R3 records the same fact -- "fixed for PAD and SHRINK, NOT for RESHAPE"
-- and routes around it with a local `op_mop`. `mixin/rand.bend` calls `MX.mxw_reshape(t, [])`
and `MX.mxw_reshape(t, [1, ...])` on the `_pool` path, so the row is a LIVE path and not a
curiosity. It is pinned here rather than dropped, so that a fix makes this gate RED and forces
the pin to move. It is REPORTED, not smoothed.

EXIT STATUS: 0 all three lanes identical after the pin · 1 a lane took the wrong row count, the
oracle failed, the native compile failed, or the lanes disagree · 3 a precondition was absent
(the output directory, the substrate, or the oracle). `DEAD`/`SKIP` are `gatekit`'s 5/4 and
this gate does not produce them.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    "base",
    "reshape_1_2_8_16",
    "reshape_1_4_64",
    "reshape_noop",
    "reshape_256",
    "permute_1_0_2_3",
    "permute_3_1_2_0",
    "permute_noop",
    "pad_1_1",
    "pad_asy",
    "pad_noop",
    "shrink_1_1",
    "shrink_asy",
    "shrink_noop",
    "flip_0",
    "flip_01",
    "flip_noop",
)

# (CPython's line, the port's line), pinned on both sides. ONE ENTRY, AND IT IS A DEFECT AND
# NOT A CARVE-OUT -- the `mxw_stk` one-element shape arg, measured and classified below.
DIVERGES = {
    "reshape_256": ("reshape_256=8 Ops.RESHAPE/2 Ops.RESHAPE Ops.CONST",
                    "reshape_256=9 Ops.RESHAPE/2 Ops.RESHAPE Ops.STACK"),
}

GATE = Gate(
    "mx_graph_census-gate",
    bend="mx_graph_census.bend",
    oracle="mx_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_bottom() -> bool:
    """`NOOP` IS THE BOTTOM -- `Arena.bottom()`, an index read out of range.

    Read off the LANE'S OWN OUTPUT and not a re-derivation: `Rng.sig` prints each src op, so
    a `NOOP` anywhere in any graph appears in `bd.out`. `gates/artifacts/` is `.gitignore`d,
    but `gatekit` promotes `bd.out` on a PASS, so it is present exactly when this runs.
    """
    return "Ops.NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "mx_graph_census-gate: 17 rows, 3 lanes, 1 DECLARED divergence -- "
                       "every ported public movement wrapper has NO NOOP BOTTOM and 16 op "
                       "sequences match CPython's byte-for-byte; reshape_256 is the one-element "
                       "shape-arg defect (bare CONST vs STACK) the pin LOCKS",
                 checks=no_noop_bottom))
