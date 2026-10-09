#!/usr/bin/env python3
"""rd_graph_census-gate.py -- A GRAPH CENSUS over `mixin/rand.bend`'s `_threefry_random_bits`.

    .venv/bin/python gates/rd_graph_census-gate.py

4 ROWS, THREE LANES, TWO DECLARED DIVERGENCES -- AND THOSE TWO ARE A DIFFERENT DEFECT.

THE POPULATION IS THE METHOD, SPLIT AS THE PORT SPLITS IT. `tinygrad/mixin/rand.py:12-15` is
ONE method; the port splits it into `rd_p64` (rand.py:13), `rd_tfb.three` (:14), `rd_tfb.cat`
(:15) and `rd_tfb` (:12). The census drives each of those that a `uint32` fixture reaches:
`p64`, `x` (`rd_tfb.x` IS `rd_p64(c1, c0)`), `three`, and `tfb` (the whole method, which
CPython's own `_threefry_random_bits` anchors).

WHAT IT ASSERTS. The port's toposort OP SEQUENCE against CPython's, byte-for-byte. The printer
is the port's OWN `M.mo_sig_t` (op.bend:1146) -- the deep toposort sequence, bare op names --
so a wrong node ANYWHERE in the graph moves a row and not only the root.

THE `rd_p64` OR DEFECT IS FIXED. The old `mo_bin` (`op.bend:540`) folded `y`'s arena and ASSUMED
`y` was the NEWEST operand; `rd_p64` puts the NEWER operand FIRST (`t = rd_shl32(rd_c64(hi))` is
`src[0]`, the shifted term), so the fold read an arena `t`'s index was not in and the OR came
back with `src[0]` = the NOOP bottom -- `p64`/`x` printed `5 NOOP/0 ... CAST/1 OR/2` against
CPython's `8 ... CONST/0 SHL/2 CAST/1 OR/2`. The fix merges the two operands' arenas
(`O.Arena.merge`, the same total spelling `tensor.bend`'s `tn_binop` uses), so `p64` and `x`
now match CPython byte-for-byte in all three lanes.

THE TWO DECLARED DIVERGENCES ARE A DIFFERENT, UNFIXED DEFECT AND THE PINS LOCK IT:

    three  CPython 20 ... ALLOC/0 SHRINK/3 STACK/0 RESHAPE/2 ...
           port    27 ... STACK/1 CONST/0 STACK/2 SHRINK/3 STACK/1 RESHAPE/2 ...
    tfb    CPython 26
           port    31

`rd_tfb.three` takes `key[1]` and `key[0]` through `rd_take.scalar` (rand.bend:402), and that
path is 5 nodes per take against CPython's 2: `rd_tail` (rand.bend:391) rebuilds its input
rather than returning its TAIL, so `rd_take.sz`/`rd_take.of` build a malformed SHRINK; and
`mxw_shrink` (movement.bend:1522) builds a one-element STACK where CPython's
`shape_to_shape_arg` (ops.py:106) builds a bare CONST. BOTH ARE OUTSIDE THIS GATE'S SUBJECT --
the OR ARENA RULE -- and the OR in `three` is the SAME `rd_p64` the `p64` row already confirms.
They are PINNED so a fix makes this gate RED and forces the pin to move, exactly as
`mo_graph_census` pinned its `permute0` NOOP.

EXIT STATUS: 0 all three lanes identical after the pins · 1 a lane took the wrong row count,
the oracle failed, the native compile failed, the lanes disagree, or a NOOP bottom appeared ·
3 a precondition was absent (the output directory, the substrate, or the oracle).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = ("p64", "x", "three", "tfb")

# (CPython's line, the port's line), pinned on both sides. THE TRAILING SPACE IS PART OF THE
# LINE: the port's `mo_sig` appends a separator after every op, so `want not in raw[lane]` in
# `gatekit` is an exact-string test and a pin without it would never match.
DIVERGES = {
    # A DIFFERENT DEFECT, not the OR one -- `rd_take.scalar`/`rd_tail` and `mxw_shrink`'s
    # one-element STACK. See the module docstring. The OR inside `three` is confirmed by `p64`.
    "three": ("three=20 ALLOC/0 CONST/0 ADD/2 CAST/1 CONST/0 SHL/2 CAST/1 OR/2 ALLOC/0 SHRINK/3 STACK/0 RESHAPE/2 CAST/1 SHL/2 CONST/0 SHRINK/3 RESHAPE/2 CAST/1 OR/2 THREEFRY/2 ",
              "three=27 ALLOC/0 CONST/0 ADD/2 CAST/1 CONST/0 SHL/2 CAST/1 OR/2 CAST/1 ALLOC/0 STACK/1 CONST/0 STACK/2 SHRINK/3 STACK/1 RESHAPE/2 STACK/0 RESHAPE/2 CAST/1 CAST/1 SHL/2 SHRINK/3 RESHAPE/2 RESHAPE/2 CAST/1 OR/2 THREEFRY/2 "),
    "tfb": ("tfb=26 ALLOC/0 CONST/0 ADD/2 CAST/1 CONST/0 SHL/2 CAST/1 OR/2 ALLOC/0 SHRINK/3 STACK/0 RESHAPE/2 CAST/1 SHL/2 CONST/0 SHRINK/3 RESHAPE/2 CAST/1 OR/2 THREEFRY/2 CAST/1 SHR/2 CAST/1 STACK/2 CONST/0 RESHAPE/2 ",
            "tfb=31 ALLOC/0 CONST/0 ADD/2 CAST/1 CONST/0 SHL/2 CAST/1 OR/2 CAST/1 ALLOC/0 STACK/1 CONST/0 STACK/2 SHRINK/3 STACK/1 RESHAPE/2 STACK/0 RESHAPE/2 CAST/1 CAST/1 SHL/2 SHRINK/3 RESHAPE/2 RESHAPE/2 CAST/1 OR/2 THREEFRY/2 SHR/2 CAST/1 STACK/2 RESHAPE/2 "),
}

GATE = Gate(
    "rd_graph_census-gate",
    bend="rd_graph_census.bend",
    oracle="rd_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_bottom() -> bool:
    """`NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP` in any row is an index read out of
    range -- which is EXACTLY the `rd_p64` OR defect this gate was written for. Read off the
    LANE'S OWN output, not a re-derivation: `mo_sig` prints each node's op, so a NOOP anywhere
    appears in `bd.out`. `gates/artifacts/` is `.gitignore`d but `gatekit` promotes `bd.out`
    on a PASS, so it is present exactly when this runs.
    """
    return "NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "rd_graph_census-gate: 4 rows, 3 lanes, 2 compared op sequences "
                        "(p64, x) match CPython byte-for-byte after the mo_bin arena-merge fix "
                        "and NO row has a NOOP bottom; 2 (three, tfb) are the PINNED "
                        "rd_take.scalar/rd_tail defect", checks=no_noop_bottom))
