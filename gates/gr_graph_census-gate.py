#!/usr/bin/env python3
"""gr_graph_census-gate.py -- A GRAPH CENSUS over the ported `pm_gradient` RULE TABLE.

    .venv/bin/python gates/gr_graph_census-gate.py

18 RULE ROWS + 14 WALK ROWS = 32 ROWS, THREE LANES, TWO DECLARED DIVERGENCES -- ONE A
CARVE-OUT, ONE A DEFECT. This is the `gradient.bend` peer of `gates/tn_graph_census-gate.py` /
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

THE TWO DIVERGENCES, CLASSIFIED:

  `gr_0` -- A CARVE-OUT, INSTRUMENT ONLY. The rule is `ctx.cast(ret.src[0].dtype)`
    (gradient.py:67). CPython's `UOp.cast` FOLDS an identity cast
    (`tinygrad/mixin/dtype.py:19` `return self if self.dtype == dt else ...`), so with the
    fixture's `CAST(CONST 1.0, int32)` -- whose src dtype IS ctx's f32 -- CPython answers the
    src itself (`2 CONST/0 CAST/1`). The port's `gcast` (`gradient.bend:163`) is a plain node
    builder with NO fold, so it answers `CAST(src)` (`3 CONST/0 CAST/1 CAST/1`). Same value,
    one extra node. It is the identity-CAST fold the task names as legitimate. **REPORTED,
    NOT SMOOTHED: the port ALREADY HAS a folding cast -- `mixin/dtype.bend`'s `cast_at`
    (`cast_at.of`: `case True{}: Found{md_ar(fx), self}`) -- and `gradient.bend:161` claims
    `gcast` is "what `cast_at` already established". It is not, and `gr_0` is where that
    shows. `gr_0_r` is the control: a REAL cast, and both lanes build it.** A fix moves the
    port's `gr_0` line to CPython's and this pin must move with it.

  `gr_10` -- A DEFECT, NOT A CARVE-OUT. The rule is `gradient.py:76-77`. TWO things are wrong,
    both visible in the deep tree:
      * slot 0 (`dx`, `ctx * e.eq(0).where(e, e*b.pow(e-1))`): the port answers
        `ctx * (e==0).where(e, b^(e-1))` -- it is MISSING the `e *` factor (`WHERE`'s else is
        `b^d`, not `e*b^d`), and `gr_10.zero` (`gradient.bend:467`) builds `CAST(CONST 0.0)`
        where CPython builds a BARE `CONST 0.0`. The two errors CANCEL in the node COUNT
        (`15` both sides, which is why `Rng.sig` is blind) but the deep tree differs:
        port `... POW/2 WHERE/3 MUL/2`, CPython `... POW/2 MUL/2 WHERE/3 MUL/2`.
      * slot 1 (`de`, `ctx * b.eq(0).where((e<0).where(ret.const_like(-inf), 0),
        ret*b.log2()*math.log(2.0))`): the port builds `rb = MUL(ret, b)` and then NEVER USES
        IT (it calls `glog2(ar(rb), b)`, i.e. `LOG2(b)`), so the answer is `log2(b)*log2`
        where CPython has `ret*log2(b)*log2` -- the `ret` (`x^e`) factor is DROPPED and a DEAD
        `MUL(ret, b)` node is minted. The count says so: port 20, CPython 21, missing `POW`.
    A rule that drops `x^e` from `d/de x^e` is numerically wrong for every nonzero base.
    **AND ONE MORE, INVISIBLE TO ANY OP-LEVEL PRINTER (this deep one included): `gr_10.dx`
    spells `e-1` as `gsub(o, e)` (`gradient.bend:490`), and `gsub(x,y)` is `x-y`, so it
    computes `1-e`, not `e-1`. The operand swap changes the SRCs and not the op sequence --
    `ADD(o, MUL(e,-1.0))` and `ADD(e, MUL(o,-1.0))` have the SAME op multiset -- so neither
    `Rng.sig` nor this deep printer can see it; it is REPORTED here and measured by reading
    `gradient.bend:218-220` against `gradient.py:77`.** It is UNGATED elsewhere: the layer's
    own `pow_n0`/`pow_n1` rows read `23`/`25` where the file's own comment says `24`/`29`.

EXIT STATUS: 0 all three lanes identical after the pins, `NOOP`-free · 1 a lane took the wrong
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

# (CPython's line, the port's line), pinned on both sides. `gr_0` is the identity-CAST fold
# carve-out; `gr_10` LOCKS the current wrong POW answer so a fix makes the gate RED and forces
# this entry to move.
DIVERGES = {
    "gr_0": ("gr_0=2 CONST/0 CAST/1 ",
             "gr_0=3 CONST/0 CAST/1 CAST/1 "),
    "gr_10": ("gr_10=17 CONST/0 CAST/1 CONST/0 CAST/1 CONST/0 CMPNE/2 CONST/0 CMPNE/2 CONST/0 CAST/1 CONST/0 MUL/2 ADD/2 POW/2 MUL/2 WHERE/3 MUL/2  | 21 CONST/0 CAST/1 CONST/0 CAST/1 CONST/0 CMPNE/2 CONST/0 CMPNE/2 CONST/0 CAST/1 CMPLT/2 CONST/0 CAST/1 WHERE/3 POW/2 LOG2/1 MUL/2 CONST/0 MUL/2 WHERE/3 MUL/2 ",
              "gr_10=17 CONST/0 CAST/1 CONST/0 CAST/1 CONST/0 CAST/1 CMPNE/2 CONST/0 CMPNE/2 CONST/0 CAST/1 CONST/0 MUL/2 ADD/2 POW/2 WHERE/3 MUL/2  | 20 CONST/0 CAST/1 CONST/0 CAST/1 CONST/0 CAST/1 CMPNE/2 CONST/0 CMPNE/2 CONST/0 CAST/1 CMPLT/2 CONST/0 CAST/1 WHERE/3 LOG2/1 CONST/0 MUL/2 WHERE/3 MUL/2 "),
}

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
    sys.exit(gate(GATE, "gr_graph_census-gate: 32 rows, 3 lanes, 2 DECLARED divergences -- "
                       "every ported graph-producing pm_gradient rule is NOOP-free, 16 of 18 "
                       "deep trees and all 14 walk rows match CPython byte-for-byte; gr_0 is the "
                       "identity-CAST fold carve-out (the port's gcast does not fold) and gr_10 "
                       "LOCKS the POW defect (missing `e*`/`ret*` factors and a swapped `e-1`)",
                 checks=no_noop))
