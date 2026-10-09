#!/usr/bin/env python3
"""rd_graph_census-gate.py -- A GRAPH CENSUS over `mixin/rand.bend`'s `_threefry_random_bits`.

    .venv/bin/python gates/rd_graph_census-gate.py

4 ROWS, THREE LANES, NO DECLARED DIVERGENCE.

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

THE TWO DECLARED DIVERGENCES ARE FIXED AND THE PINS ARE GONE. `three` and `tfb` each carried a
malformed SHRINK on the `key[i]` path, and both rows now match CPython byte-for-byte:

    three  20 ... ALLOC/0 SHRINK/3 STACK/0 RESHAPE/2 CAST/1 SHL/2 CONST/0 SHRINK/3 RESHAPE/2 ...
    tfb    26 ... THREEFRY/2 CAST/1 SHR/2 CAST/1 STACK/2 CONST/0 RESHAPE/2

THREE DEFECTS WERE FIXED, all on the `_threefry_random_bits` path:
  * `rd_tail` (rand.bend:391) REBUILT its input -- the `go`/`acc` fold appended every element
    and handed back the list it was given -- instead of returning its TAIL, so `rd_take.sz`
    shrank with a two-element size arg and `rd_take.of` reshaped to `[0]` instead of `[]`. It is
    now the one-line `ds[1:]` (`viz/serve.bend`'s `vs.tail` shape).
  * `mxm_as_shape` (movement.bend) read a bare CONST shape arg as the EMPTY list, so the
    `mxw_stk.done` one-element fold's CONST could not be read back and the `mxw_reshape` after
    `rd_take`'s SHRINK folded as the identity. CPython's `as_shape` (ops.py:806) opens with
    `if self.op is Ops.CONST: return (self.val,)`, which is the arm the port was missing.
  * `rd_tfb.cat` (rand.bend:432) read `x` twice while `rd_c32(x)` grew `x`'s arena, so
    `rd_shr32(x)` built its SHR in the stale arena and `op_cat1`'s STACK named the SHR as
    `src[0]` -- the `x.cast(uint32)` was LOST. The shift is now re-wrapped into the cast's arena.

All three are OUTSIDE THIS GATE'S SUBJECT -- the OR ARENA RULE -- and the OR in `three` is the
SAME `rd_p64` the `p64` row already confirms.

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
# NO DECLARED DIVERGENCE: the `rd_take`/`rd_tail`, `mxm_as_shape` and `rd_tfb.cat` defects are
# fixed (see the module docstring), so every row is COMPARED.
DIVERGES = {}

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
    sys.exit(gate(GATE, "rd_graph_census-gate: 4 rows, 3 lanes, all 4 op sequences match "
                        "CPython byte-for-byte and NO row has a NOOP bottom (the `rd_take`/"
                        "`rd_tail`, `mxm_as_shape` and `rd_tfb.cat` defects are fixed, so the "
                        "two pins are dropped)", checks=no_noop_bottom))
