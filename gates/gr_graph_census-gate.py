#!/usr/bin/env python3
"""gr_graph_census-gate.py -- A GRAPH CENSUS over the ported `pm_gradient` RULE TABLE.

    .venv/bin/python gates/gr_graph_census-gate.py

18 RULE ROWS + 14 WALK ROWS = 32 ROWS, THREE LANES, NO DECLARED DIVERGENCES -- ALL 32
ROWS MATCH CPYTHON. This is the `gradient.bend` peer of `gates/tn_graph_census-gate.py` /
`ew_*` / `mo_*` / `mx_*` / `cr_*`: the whole graph-building surface of the layer in one
artifact. The layer's own `main` prints self-derived node COUNTS (a `size1` measure with no
CPython lane and no harness); THIS drives each rule through the REAL matcher and diffs the
tree against CPython's, and drives the walk against CPython's `compute_gradient`/`_deepwalk`.

THE POPULATION IS DISCOVERED, AND IT IS THE TABLE'S OWN DECLARATION.

    grep -o '^def gr[a-z_0-9]*' tinybendygrad/mixin/gradient.bend | sort -u    # 48 names

The 48 are the 33 RULES `gr_0`..`gr_32` (one per entry of CPython's compiled `pm_gradient`), the
four `gr_29_*` sub-defs, the ten dispatcher helpers (`gr_table`, `gr_dispatch`, `gr_rewrite`,
`gr_scan`, `gr_try`, `gr_claimed`, `gr_rej`, `gr_ler`, `gr_e27`, `gr_e29`) and the builder
`grecip`. A RULE is `gr_<N>` for integer N; N ranges over CPython's OP-KEYED table, discovered
by `sum(len(v) for v in pm_gradient.pdict.values())` -- **33**, and the port's own `t_claims`
pins the same 33. (`len(pm_gradient.patterns)` is 32, the RAW list: `UPat((Ops.CMPLT,
Ops.CMPNE))` is ONE entry keyed under TWO ops, which is why the port has tags 7 AND 8.)

A rule is a ROW iff it ANSWERS A GRAPH. Of the 33:
  17 build at least one non-hole gradient: 0,1,2,3,4,5,6,9,10,11,12,13,16,18,26,29,31
   3 answer only holes, so there is NO toposort to print: 7 CMPLT, 8 CMPNE, 32 BITCAST
  13 are `GSkip{}` WALLS (no graph, TODO(p3)): 14,15,17,19,20,21,22,23,24,25,27,28,30
The 3 all-holes rules and the 13 walls FALL OUT: 16 of 33 dropped, 17 rows. `gr_0_r` is one
VARIANT (the CAST rule with a NON-identity target dtype), so 18 rule rows. THE WALK adds 14
rows -- `compute_gradient`/`_deepwalk` driven through the port's own `dag_*` readers, with
CPython's `compute_gradient` on the same DAG as the oracle. 32 rows in all. The `dag_*` defs
are READERS (they return U32/String/Bool/List, no graph), and the walk's `compute_gradient`
returns a `CState` table, not one graph, so neither is itself a rule row; the walk rows are the
graph census of their output, one per gradient key plus the walk's shape and its two counters.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere in a graph is an index read out of range and always a defect. `no_noop` reads the
LANE'S OWN `bd.out`; it finds none, which is a measurement and not an absence.

THE TWO DEFECTS THIS GATE FOUND, BOTH NOW CLOSED -- `DIVERGES` IS EMPTY. Neither was a
carve-out: the port answers CPython's tree on all 32 rows.

  `gr_0` -- THE IDENTITY-CAST FOLD. `gradient.py:67` is `ctx.cast(ret.src[0].dtype)` and
    `tinygrad/mixin/dtype.py:19` is `return self if self.dtype == dt else ...`, so an
    identity cast builds NO node. `gcast` (`gradient.bend:163`) minted UNCONDITIONALLY, so
    with the fixture's `CAST(CONST 1.0, int32)` -- whose src dtype IS ctx's f32 -- the port
    answered `CAST(src)` (`3 CONST/0 CAST/1 CAST/1`) where CPython answers the src itself
    (`2 CONST/0 CAST/1`). `gcast` now reads the SOURCE dtype from `F.folded` and folds on
    `O.eq_dt`, the same fold `mixin/dtype.bend`'s `cast_at` spells. `gr_0_r` is the
    control: a REAL cast, and both lanes still build it.

  `gr_10` -- THE POW GRADIENT. `gradient.py:76-77`. The port's `dx` was MISSING the `e *`
    factor (`WHERE`'s else was `b^(e-1)`, not `e*b^(e-1)`), and its `de` built a DEAD
    `MUL(ret, b)` then read `LOG2(b)` off `b`, DROPPING the `x^e` factor. Three constants
    were wrong too: `e.eq(0)`, `e<0` and `where`'s `0` are all ONE bare `CONST 0` (the port
    minted `CAST(CONST 0.0)`), and the `1` in `e-1` is a BARE `CONST 1.0` (the port minted
    `CAST(CONST 1.0)`). A rule that drops `x^e` from `d/de x^e` is numerically wrong for
    every nonzero base. The layer's own `pow_n0`/`pow_n1` rows now read `24`/`29`, the
    numbers the file's comment always claimed.

    AND THE EARLIER REVISION'S THIRD CLAIM WAS WRONG, so it is recorded rather than
    repeated: it said `gr_10.dx` spelled `e-1` as `gsub(o, e)` and computed `1-e`.
    MEASURED, `gsub(+ar, x, y)` is `x-y` and the call was `gsub(ar, e, o)`, i.e. `e-1` --
    the exponent was ALWAYS right; only the `e*` factor and the constants were wrong. An
    op-level printer cannot see an operand swap anyway, which is why the claim survived.

EXIT STATUS: 0 all three lanes identical, `NOOP`-free · 1 a lane took the wrong
row count, the oracle failed, the compile failed, or the lanes disagree · 3 a precondition was
absent · 5 `bend` ran and emitted no rows. `SKIP` (4) is not produced.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    "gr_0",
    "gr_0_r",
    "gr_1",
    "gr_2",
    "gr_3",
    "gr_4",
    "gr_5",
    "gr_6",
    "gr_9",
    "gr_10",
    "gr_11",
    "gr_12",
    "gr_13",
    "gr_16",
    "gr_18",
    "gr_26",
    "gr_29",
    "gr_31",
    # THE WALK -- `compute_gradient`/`_deepwalk`, driven through the port's own `dag_*`
    # readers. These rows are the ACCUMULATE (`dag_grad_a` = `5 root=ADD/2`, not the MUL) and
    # the walk's shape/counters, which the rule rows above cannot reach.
    "walk_sig",
    "walk_inpath",
    "walk_keys",
    "walk_grad_a",
    "walk_grad_b",
    "walk_grad_c",
    "walk_grad_p",
    "walk_grad_q",
    "walk_grad_r",
    "walk_walk_n",
    "walk_grads_n",
    "walk_skip_n",
    "walk_hole_n",
    "walk_n_inpath",
)

# EMPTY: both defects this gate found are closed, so there is nothing to exclude and the
# diff compares all 32 rows. It was `gr_0` (the identity-CAST fold) and `gr_10` (the POW
# gradient); `gradient.bend`'s `gcast` now folds and its `gr_10` now builds CPython's tree.
DIVERGES = {}

GATE = Gate(
    "gr_graph_census-gate",
    bend="gr_graph_census.bend",
    oracle="gr_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop() -> bool:
    """`NOOP` IS THE BOTTOM -- a `NOOP` anywhere in any gradient is an index read out of range.

    Read off the LANE'S OWN OUTPUT: the deep printer names every node's op, so a `NOOP` in any
    row appears in `bd.out`. `gates/artifacts/` is `.gitignore`d, but `gatekit` promotes `bd.out`
    on a PASS, so it is present exactly when this runs.
    """
    return "NOOP" not in (GATE.dir / "bd.out").read_text()


if __name__ == "__main__":
    sys.exit(gate(GATE, "gr_graph_census-gate: 32 rows, 3 lanes, NO divergences -- every "
                       "ported graph-producing pm_gradient rule is NOOP-free and ALL 18 deep "
                       "trees and all 14 walk rows match CPython byte-for-byte (gr_0's "
                       "identity-CAST fold and gr_10's POW gradient are both fixed)",
                 checks=no_noop))
