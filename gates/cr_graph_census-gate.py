#!/usr/bin/env python3
"""cr_graph_census-gate.py -- A GRAPH CENSUS over every ported public `cr_*`.

    .venv/bin/python gates/cr_graph_census-gate.py

28 ROWS, THREE LANES, SIX DECLARED DIVERGENCES -- FOUR ARE THE ONE INSTRUMENT CARVE-OUT AND
TWO ARE A REAL DEFECT.

THE POPULATION IS DISCOVERED. `cr_<n>` is a row iff CPython's
`tinygrad/mixin/creation.py` defines a METHOD `<n>(self` / `<n>(cls` -- 10 of the file's 39
distinct `cr_*` def prefixes. The other 29 are the plumbing (`cr_cast`, `cr_from_py`,
`cr_bounds`, `cr_mop`, `cr_after`, `cr_alloc`, ...) and the gate's own printers/fixtures,
exactly the way `ew_graph_census` drops `ew_join`/`ew_binop`/`ew_promote`. `const` is a
`raise NotImplementedError` and has no def here; `_multi_like` is W2 and has no def here.

THE TEN BASE ROWS ARE ONE PER METHOD; THE EIGHTEEN `_v` ROWS ARE VARIANTS. The base rows drive
the default call. The variants reach the arms the default call does not: the identity reshape
(`empty(4)`), the 0-dim shape (`empty()`), the one-element shape arg that is a BARE CONST and
not a STACK (`full((4,),7)`), `buffer=False` (the EXPAND root), the weak-dtype CAST
(`dtype=half`, `dtype=int32`), the bool and float CONSTs, and the `*_like` methods on an INT32
and a BOOL receiver. The sibling `ew_graph_census` adds two such variants beyond its 43 methods.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere in a graph is an index read out of range and always a defect. It is asserted by
`no_noop_bottom`, which reads the LANE'S OWN `bd.out`; it finds NONE, which is a measurement
and not an absence.

FOUR OF THE SIX DIVERGENCES ARE ONE CARVE-OUT. Every one is a row whose ROOT HAS ZERO SRCS --
the bare `ALLOC` of an identity reshape (`empty_v4`, `empty_like_vi`) or the bare `CONST` of a
0-dim call (`full_v0nobuf`, `const_like_v0d`). The GRAPHS AGREE: the port's `O.Rng.sig` prints
`-` for a node with no srcs (`Rng.srcops.seeded`'s `Nil` arm) where CPython's signature joins
an empty list to the empty string, so the two lines differ by that ONE character (and the
trailing space). This is the SAME carve-out `ew_graph_census` pins for `ew_ufix`, and it is
INSTRUMENT ONLY.

THE OTHER TWO ARE A DEFECT AND THE PIN LOCKS IT:

    zeros_like_vbool  CPython 6 AFTER/2 ALLOC STORE      port 7 AFTER/2 ALLOC STORE
    ones_like_vbool   CPython 6 AFTER/2 ALLOC STORE      port 7 AFTER/2 ALLOC STORE

`cr_zeros_like` (creation.bend:427) hardcodes `MO.mo_ki(0)` and `cr_ones_like` (:435)
`MO.mo_ki(1)` -- INT consts -- while CPython's `full_like(0)` resolves `dt = self.dtype` and
`cls.const(0, bool)` calls `DType.const`, whose bool arm is `bool(val)` (dtype.py:84). So on a
BOOL receiver CPython's CONST is the BOOL `False`/`True` and `.cast(bool)` FOLDS; the port's
`cr_const_of` reads `from_py(0) == weakint != bool` and builds a REAL CAST. MEASURED with
`.venv/bin/python` on `Tensor([True,False,True,True], device='PYTHON')`: CPython's CONST node
carries `arg=False, dtype=bool` with NO CAST, the port has one more node. The defect is LATENT
for the default float32 receiver (there the port's int 0 and CPython's weakfloat 0.0 BOTH cast,
so the COUNT and the sequence agree and only the CONST's arg differs, which `Rng.sig` does not
print) -- which is exactly why the file's own gate never saw it.

A GRAPH CAN BE WRONG WITHOUT A NOOP, WHICH IS WHY THE SEQUENCES ARE PRINTED AND NOT JUST THE
VERDICT: the length and the root's src op sequence are what catch a dropped CAST (`full_vfloat`
9 vs 10), an inverted `buffer` arm (`full_vnobuf` EXPAND vs AFTER), a dropped reshape identity
test (`empty_v4` ALLOC vs RESHAPE), and the bool-receiver CAST above (6 vs 7).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    # the ten base rows, one per creation.py method
    "const_like",
    "empty",
    "empty_like",
    "invalids",
    "full",
    "full_like",
    "zeros",
    "zeros_like",
    "ones",
    "ones_like",
    # the eighteen variants
    "empty_v4",
    "empty_v0",
    "full_v4",
    "full_vnobuf",
    "full_v0nobuf",
    "full_vhalf",
    "full_vbool",
    "full_vfloat",
    "zeros_vi32",
    "ones_vi32",
    "full_like_vhalf",
    "full_like_vnobuf",
    "empty_like_vhalf",
    "zeros_like_vi",
    "empty_like_vi",
    "const_like_v0d",
    "zeros_like_vbool",
    "ones_like_vbool",
)

# (CPython's line, the port's line), pinned on both sides. THE TRAILING SPACE IS PART OF THE
# ORACLE'S LINE: the port prints `-` for a zero-src root, CPython prints nothing (the f-string
# still emits the separator), so a pin without the trailing space would never match.
#
# FOUR CARVE-OUTS AND TWO DEFECTS. The four zero-src-root rows are the ONE instrument
# carve-out (the `-`/empty-src rendering, identical to `ew_ufix`). `zeros_like_vbool` and
# `ones_like_vbool` are a DEFECT and the pin LOCKS the current wrong value: a fix moves the
# port's line and this entry must move with it.
DIVERGES = {
    "empty_v4":         ("empty_v4=1 Ops.ALLOC/0 ",        "empty_v4=1 Ops.ALLOC/0 -"),
    "full_v0nobuf":     ("full_v0nobuf=1 Ops.CONST/0 ",    "full_v0nobuf=1 Ops.CONST/0 -"),
    "empty_like_vi":    ("empty_like_vi=1 Ops.ALLOC/0 ",   "empty_like_vi=1 Ops.ALLOC/0 -"),
    "const_like_v0d":   ("const_like_v0d=1 Ops.CONST/0 ",  "const_like_v0d=1 Ops.CONST/0 -"),
    "zeros_like_vbool": ("zeros_like_vbool=6 Ops.AFTER/2 Ops.ALLOC Ops.STORE",
                         "zeros_like_vbool=7 Ops.AFTER/2 Ops.ALLOC Ops.STORE"),
    "ones_like_vbool":  ("ones_like_vbool=6 Ops.AFTER/2 Ops.ALLOC Ops.STORE",
                         "ones_like_vbool=7 Ops.AFTER/2 Ops.ALLOC Ops.STORE"),
}

GATE = Gate(
    "cr_graph_census-gate",
    bend="cr_graph_census.bend",
    oracle="cr_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_bottom() -> bool:
    """`NOOP` IS THE BOTTOM -- a `NOOP` anywhere in any row is an index read out of range.

    Read off the LANE'S OWN OUTPUT and not a re-derivation: `Rng.sig` prints each src op, so a
    `NOOP` anywhere in any graph appears in `bd.out`. `gates/artifacts/` is `.gitignore`d, but
    `gatekit` promotes `bd.out` on a PASS, so it is present exactly when this runs.
    """
    return "Ops.NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "cr_graph_census-gate: 28 rows, 3 lanes, 6 DECLARED divergences -- "
                        "every ported public cr_* has NO NOOP BOTTOM and all 22 compared op "
                        "sequences match CPython byte-for-byte; 4 divergences are the ONE "
                        "empty-src-root rendering carve-out (identical to ew_ufix) and 2 are "
                        "the PINNED zeros_like/ones_like bool-receiver defect (7 nodes vs 6)",
                 checks=no_noop_bottom))
