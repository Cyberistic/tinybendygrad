#!/usr/bin/env python3
"""rng_graph_census-gate.py -- A GRAPH CENSUS over `tinybendygrad/schedule/rangeify.bend`'s
ELEVEN rule tables, and the FIRST gate this schedule layer has ever had.

    .venv/bin/python gates/rng_graph_census-gate.py

726 ROWS (11 TABLES x 66 NODES), THREE LANES, 44 DECLARED DIVERGENCES -- 38 of them WALLS and 6
of them an instrument carve-out, and NOW NONE THAT ARE FINDINGS. `rangeify.bend` ships its OWN
125-row `main` (`lay`, `ct_len`, `ct_root3..8`, `noopf_*`, `raf_*`, `ren_*`, `ab7_*`, `ct8*`, ...),
so the COUNTS, the claim counts and the reject-set lengths were gated. WHAT WAS NOT GATED WAS THE
GRAPH: no lane ever printed what a rule ANSWERS, so a rule that fired where CPython does not, or
fired and built a different node, was invisible. This is that lane. It found THREE such rows, and
ALL THREE ARE FIXED: the gate went RED on each pin before the pin was dropped, and the three rows
now agree with CPython byte for byte. See THE THREE FINDINGS at the foot.

THE POPULATION IS DISCOVERED, ON BOTH SIDES, AND THE ROWS ARE BUILT NOT LISTED. A ROW is a
(TABLE, NODE) pair. TABLE ranges over the port's eleven `*_table` defs -- `rb nic nv aprt sk gs ct
fb dg lb ab`, MEASURED `grep -c '^def [a-z]*_table' tinybendygrad/schedule/rangeify.bend` = 11 --
and NODE ranges over `rangeify.bend`'s own `G.ix`, whose length is 66 (that file's `lay` row,
`t_lay` at :1984). So `ROWS` below is a COMPREHENSION over those two, not a typed list, and
`rows=len(ROWS)` is 726. BOTH LANES EMIT ALL 726, refusals included, so the two row counts agree
BY CONSTRUCTION: a lane that filtered its own refusals would let a disagreement about WHICH pairs
fire hide inside the filter, and the first draft of this gate did exactly that. What it found is
that the count alone was hiding three rows -- see THE THREE FINDINGS at the foot.

THE ORACLE CALLS THE REAL CPYTHON METHOD. `gates/rng_graph_census-oracle.py` calls
`PatternMatcher.rewrite` -- the engine's own per-node dispatch, ops.py:1613-1619 -- on the REAL
module-scope matchers `rangeify.py` builds and hands to `graph_rewrite` in `get_kernel_graph`
(349-376), and it hands each table the ctx its own body demands. It reimplements no fold, no
claim test and no rule body, so it cannot agree with a port that is itself wrong.

THE 44 DIVERGENCES, CLASSIFIED. Every one is PINNED ON BOTH SIDES, and every pin's PYTHON side
carries the `rangeify.py` line its rule body is on -- MEASURED by asking each matcher's own
`pdict` which pattern fired, not by reading the tables and guessing.

  38 WALLS -- CPython fires, the port REFUSES. Each is a rule body `rangeify.bend` records as
  `# WALL(p3)` and answers `M.Hop{ar, 0}`, so this census cannot see it and does not pretend to.
  Grouped by the line MEASURED to fire:
    rangeify.py:131  `remove_bufferize`        2 rows  (rb_19, rb_51)  -- wall `UOp.substitute`
                                                                     over a ctx DICT (:2655)
    rangeify.py:114  `cleanup_dead_axes`       6 rows  (ct_17, ct_18,   -- wall `arg.removable`
                                                      ct_50, ct_53,      plus `UOp.ranges`
                                                      ct_54, ct_55)             (:2654)
    rangeify.py:116  `remove_noop_bufferize`   1 row   (ct_49)         -- wall `UOp.shrink`
                                                                     (:994)
    rangeify.py:242  `flatten_bufferize`       2 rows  (fb_18, ab_18) -- wall `apply_movement_op`
                                                                     (:1179)
    rangeify.py:253  `bufferize_to_store`      6 rows  (ab_17, ab_49,  -- wall `commit_dtype`,
                                                      ab_50, ab_53,      `sorted(ranges)`,
                                                      ab_54, ab_55)      `ParamArg`, `next(ctx)`
                                                                     (:2659)
    rangeify.py:261  RESHAPE through MSELECT   1 row   (ab_30)        -- wall `UOp.base` +
                                                                     `apply_movement_op` (:2661)
    rangeify.py:311  `debuf`                   7 rows  (dg_5, dg_6,   -- wall
                                                                     `LocalAddBufferContext.map`
                                                      dg_26, dg_30,            (:2662)
                                                      dg_47, dg_56, dg_57)
    rangeify.py:313  PARAM -> `debuf`          1 row   (dg_39)        -- the same `debuf` wall
    rangeify.py:319  `handle_after`            5 rows  (dg_14, dg_15, -- wall the ctx record plus
                                                      dg_16, dg_41,      `UOp.ranges` (:2663)
                                                      dg_42)
    rangeify.py:345  `split_store`             7 rows  (sk_11..sk_43) -- wall `graph_rewrite`
                                                                     INSIDE a rule (:2665)
  `ct_17`, `ct_18` and `ct_55` are the three where CPython itself RAISES (`ValueError: size
  mismatch, can't reshape`) -- `cleanup_dead_axes` reshapes a STAGE whose range is not in its
  buffer's range set, which the port's probe fixture allows and a real rangeified graph does not.
  The oracle records the exception's NAME rather than inventing an answer, and the port records
  its refusal. Both are answers; neither is smoothed.

  6 CARVE-OUTS, INSTRUMENT ONLY -- `rb_11`, `rb_32`, `ab_31`, `ab_41`, `aprt_34`, `dg_37`. The
  GRAPHS AGREE; the two lines differ by ONE character. `Rng.srcops` (ops.bend:5894) prints `-`
  for a node with NO srcs where CPython's `join` prints the empty string. This is the SAME
  carve-out `ew_graph_census` pins as `ew_ufix` and `md_graph_census` pins three times, and it is
  six rows here rather than one because a REWRITER answers src-free nodes far more often than a
  graph-builder does. NOTE THE SPACING IS PART OF THE PIN: CPython's side carries two spaces
  (`/0  arg=`), the port's a `-`, and `gatekit`'s `want not in raw[lane]` is an exact-line test.

  0 FINDINGS. THERE WERE THREE, AND ALL THREE ARE FIXED -- so this list is empty where it used to
  hold `ct_20`, `ab_28` and `ab_29`. They were DEFECTS rather than carve-outs (the port FIRED
  where CPython REFUSED), they were PINNED so that fixing one makes the gate RED, and each was
  RED on its own pin before the pin was dropped. `rangeify.bend` IS NO LONGER BYTE-IDENTICAL --
  three defs changed. Their measurement is in the block at the foot of this file.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON, AND IT IS NOT THE `NOOP` CLAIM. `NOOP` IS THE BOTTOM
(`Arena.bottom()`), and `tn_graph_census` asserts no lane answers one. THIS FILE CANNOT: `rb_1`
(rangeify.py:133) and `ab_8` (:268) DELIBERATELY answer `UOp(Ops.NOOP)`, and `rb_11`, `rb_32`,
`ab_31`, `ab_41` are those two rules working. A gate that asserted "no NOOP" here would be
asserting that two ported rules are broken. What IS asserted instead is `gs_and_lb_are_silent`:
the eleven tables produce 726 rows of which `gs` and `lb` contribute ZERO non-`none` answers --
the measurement `rangeify.bend:2667-2668` makes in prose -- checked off the lane's own output.

EXIT STATUS: 0 all three lanes identical after the pins · 1 a lane took the wrong row count, the
oracle failed, the native compile failed, the lanes disagree, or a pinned row moved · 3 a
precondition was absent (the output directory, the substrate, or the oracle).
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROOT = Path(__file__).resolve().parents[1]
RANGEIFY = ROOT / "tinybendygrad/schedule/rangeify.bend"

# **THE COMMENT ABOVE THIS LINE USED TO CLAIM BOTH NUMBERS WERE DISCOVERED AND NEITHER WAS.**
# It read "THE TWO DISCOVERY RULES ... Eleven is `grep -c '^def [a-z]*_table' ...` (MEASURED) ...
# Neither is typed from a table of rows", and then typed the eleven names out. Found by the
# `shapecensus` unit 2026-10-15: **a comment that asserts a measurement its own code does not
# perform is worse than no comment**, because a reader checks the claim and not the code.
#
# The first of the two is now actually discovered, by the command the comment quoted. MEASURED
# 2026-10-15: `re.findall` over `rangeify.bend` returns the same eleven names IN THE SAME ORDER as
# the tuple it replaced, so this is a change of MECHANISM and not of population -- and a twelfth
# `def <name>_table` now joins the census instead of being invisible.
#
# **AND A DISCOVERY THAT FINDS NOTHING MUST NOT BE A GREEN CENSUS.** If the pattern ever stops
# matching -- the file is renamed, the `def` shape changes, the path moves -- `TABLES` is empty,
# `ROWS` is empty, and a census over zero rows agrees with everything. That is the
# "0 disagreements over 0 comparisons" shape, so the empty case REFUSES instead.
TABLES = tuple(re.findall(r"^def ([a-z]+)_table", RANGEIFY.read_text(), re.M))
if not TABLES:
    print(f"rng_graph_census-gate: REFUSED -- no `def <name>_table` in {RANGEIFY}, so there are no "
          f"tables to census. A census over zero rows agrees with everything, and that is not a "
          f"verdict.", file=sys.stderr)
    raise SystemExit(3)
# 66 IS STILL TYPED. It is `rangeify.bend`'s own `G.ix` length, read off that file's `lay` row, and
# unlike the table names there is no `def` to discover -- an integer constant in the subject has to
# be PINS, not a walk. **A PIN AND A DISCOVERY ARE DIFFERENT INSTRUMENTS AND ONE MAY NOT
# IMITATE THE OTHER.** Re-pin it if `G.ix` grows; `TABLES` will not notice.
NODES = 66
ROWS = tuple(f"{t}_{n}" for t in TABLES for n in range(NODES))

# (CPython's line, the port's line), pinned on BOTH sides -- a PAIR, because a divergence is
# precisely where the two sides differ, and pinning one string can only ever describe half of
# it. 44 entries: 38 walls and 6 zero-src renderings. Every `py` pin carries the
# `rangeify.py` line its rule body is on, MEASURED by asking each matcher's own `pdict` which
# pattern fired; the map from those lines to `rangeify.bend`'s `# WALL(p3)` reasons is in this
# file's docstring above. THE THREE FINDINGS THAT USED TO BE HERE ARE GONE -- see the foot.
DIVERGES = {
    "rb_11": ("rb_11=1 Ops.NOOP/0  arg=none t=none", "rb_11=1 Ops.NOOP/0 - arg=none t=none"),
    "rb_19": ("rb_19=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "rb_19=none"),
    "rb_32": ("rb_32=1 Ops.NOOP/0  arg=none t=none", "rb_32=1 Ops.NOOP/0 - arg=none t=none"),
    "rb_51": ("rb_51=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "rb_51=none"),
    "aprt_34": ("aprt_34=1 Ops.PARAM/0  arg=other t=tuple", "aprt_34=1 Ops.PARAM/0 - arg=other t=tuple"),
    "sk_11": ("sk_11=4 Ops.CALL/1 Ops.SINK arg=other t=none", "sk_11=none"),
    "sk_12": ("sk_12=5 Ops.CALL/1 Ops.SINK arg=other t=none", "sk_12=none"),
    "sk_13": ("sk_13=7 Ops.CALL/2 Ops.SINK Ops.BUFFER arg=other t=none", "sk_13=none"),
    "sk_31": ("sk_31=8 Ops.CALL/2 Ops.SINK Ops.BUFFER arg=other t=none", "sk_31=none"),
    "sk_32": ("sk_32=7 Ops.CALL/2 Ops.SINK Ops.BUFFER arg=other t=none", "sk_32=none"),
    "sk_33": ("sk_33=9 Ops.CALL/3 Ops.SINK Ops.BUFFER Ops.BUFFER arg=other t=none", "sk_33=none"),
    "sk_43": ("sk_43=8 Ops.CALL/2 Ops.SINK Ops.BUFFER arg=other t=none", "sk_43=none"),
    "ct_17": ("ct_17=raise=ValueError", "ct_17=none"),
    "ct_18": ("ct_18=raise=ValueError", "ct_18=none"),
    "ct_49": ("ct_49=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "ct_49=none"),
    "ct_50": ("ct_50=11 Ops.EXPAND/2 Ops.RESHAPE Ops.CONST arg=none t=none", "ct_50=none"),
    "ct_53": ("ct_53=7 Ops.EXPAND/2 Ops.RESHAPE Ops.CONST arg=none t=none", "ct_53=none"),
    "ct_54": ("ct_54=8 Ops.EXPAND/2 Ops.RESHAPE Ops.CONST arg=none t=none", "ct_54=none"),
    "ct_55": ("ct_55=raise=ValueError", "ct_55=none"),
    "fb_18": ("fb_18=10 Ops.RESHAPE/2 Ops.STAGE Ops.STACK arg=none t=none", "fb_18=none"),
    "dg_5": ("dg_5=1 Ops.PARAM/0  arg=other t=none", "dg_5=none"),
    "dg_6": ("dg_6=1 Ops.PARAM/0  arg=other t=none", "dg_6=none"),
    "dg_14": ("dg_14=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "dg_14=none"),
    "dg_15": ("dg_15=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "dg_15=none"),
    "dg_16": ("dg_16=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "dg_16=none"),
    "dg_26": ("dg_26=1 Ops.PARAM/0  arg=other t=none", "dg_26=none"),
    "dg_30": ("dg_30=1 Ops.PARAM/0  arg=other t=none", "dg_30=none"),
    "dg_37": ("dg_37=1 Ops.PARAM/0  arg=other t=none", "dg_37=1 Ops.PARAM/0 - arg=other t=none"),
    "dg_39": ("dg_39=1 Ops.PARAM/0  arg=other t=none", "dg_39=none"),
    "dg_41": ("dg_41=1 Ops.NOOP/0  arg=none t=none", "dg_41=none"),
    "dg_42": ("dg_42=3 Ops.BUFFER/1 Ops.SPECIAL arg=other t=none", "dg_42=none"),
    "dg_47": ("dg_47=1 Ops.PARAM/0  arg=other t=none", "dg_47=none"),
    "dg_56": ("dg_56=3 Ops.RESHAPE/2 Ops.PARAM Ops.STACK arg=none t=none", "dg_56=none"),
    "dg_57": ("dg_57=1 Ops.PARAM/0  arg=other t=none", "dg_57=none"),
    "ab_17": ("ab_17=9 Ops.AFTER/2 Ops.ALLOC Ops.END arg=none t=none", "ab_17=none"),
    "ab_18": ("ab_18=10 Ops.RESHAPE/2 Ops.STAGE Ops.STACK arg=none t=none", "ab_18=none"),
    "ab_30": ("ab_30=4 Ops.MSTACK/2 Ops.BUFFER Ops.BUFFER arg=none t=none", "ab_30=none"),
    "ab_31": ("ab_31=1 Ops.NOOP/0  arg=none t=none", "ab_31=1 Ops.NOOP/0 - arg=none t=none"),
    "ab_41": ("ab_41=1 Ops.NOOP/0  arg=none t=none", "ab_41=1 Ops.NOOP/0 - arg=none t=none"),
    "ab_49": ("ab_49=10 Ops.AFTER/2 Ops.ALLOC Ops.END arg=none t=none", "ab_49=none"),
    "ab_50": ("ab_50=11 Ops.AFTER/2 Ops.ALLOC Ops.END arg=none t=none", "ab_50=none"),
    "ab_53": ("ab_53=9 Ops.CAST/1 Ops.AFTER arg=dt:weakint t=none", "ab_53=none"),
    "ab_54": ("ab_54=8 Ops.AFTER/2 Ops.ALLOC Ops.END arg=none t=none", "ab_54=none"),
    "ab_55": ("ab_55=9 Ops.AFTER/2 Ops.ALLOC Ops.END arg=none t=none", "ab_55=none"),
}

GATE = Gate(
    "rng_graph_census-gate",
    bend="rng_graph_census.bend",
    oracle="rng_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def gs_and_lb_are_silent() -> bool:
    """ELEVEN TABLES, NINE OF THEM SPEAK. `gs` and `lb` contribute ZERO answers over 66 nodes
    each, and `rangeify.bend:2667-2668` says why in prose: `gate_substitute` raises
    `BottomUpGate` (which `graph_rewrite` catches as "no rewrite", ops.py:1835) and
    `_limit_bufs` returns `None` at its second line whenever `MAX_KERNEL_BUFFERS` is unset.

    Checked off the LANE'S OWN OUTPUT, not a re-derivation, and the check is on the PORT side
    only: the claim is about this file's `gs_0` and `lb_0`, and the oracle lane independently
    measured the same zero (its 132 `gs_*`/`lb_*` rows are all `none`). A rule that STARTED
    answering would move this to False and fail the gate, which is the point -- two dead tables
    is a measurement, and a measurement that cannot change is not one.
    """
    rows = [l for l in (GATE.dir / "bd.out").read_text().splitlines() if "=" in l]
    return not any(l.split("=", 1)[0].startswith(("gs_", "lb_")) and l.split("=", 1)[1] != "none"
                   for l in rows)


if __name__ == "__main__":
    sys.exit(gate(GATE, "rng_graph_census-gate: 726 rows (11 tables x 66 nodes), 3 lanes, "
                        "44 DECLARED divergences -- 682 op sequences match CPython's byte for "
                        "byte; 38 are the # WALL(p3) rule bodies this file records as unported "
                        "(each pinned with the rangeify.py line MEASURED to fire) and 6 are the "
                        "zero-src `-` rendering. 0 FINDINGS: the three this gate found (ct_20, "
                        "ab_28, ab_29) are FIXED, each was RED on its pin first, and all three "
                        "rows now match; gs and lb answer nothing on 132 nodes, asserted",
                  checks=gs_and_lb_are_silent))

# ===========================================================================
# THE THREE FINDINGS, AND WHAT WAS DONE ABOUT THEM. `rangeify.bend` is NO LONGER
# BYTE-IDENTICAL. Each pin went RED on its own before it was dropped, and the only
# rows that moved, over the whole 726, were the three named below.
#
# FINDING 1 -- `ct_6` CLAIMED A TWO-SRC INDEX. `rangeify.py:122` is
#     (UPat(Ops.INDEX, src=(UPat.cvar().or_casted("c"),),), lambda c: c)
# and `UPat.__init__` (ops.py:1478-1481) sets `strict_length = not (allow_any_len or
# isinstance(src, UPat) or src is None)` -- a TUPLE `src` is strict, `required_len = 1`. So an
# INDEX with two srcs CANNOT match. MEASURED: reading the pattern gives
# `strict_length=True required_len=1`, and driving it, `pm_const_buffer_folding.rewrite`
# on the fixture's node 20 (`IXC = INDEX(C4, R0)`, two srcs) answers `None` while node 58
# (`CT8D = INDEX(MSTC)`, one src) answers.
# THE DEFECT WAS TWO HALVES AND BOTH ARE GONE. `ct_6` read ONLY
# `M.mp_is(ar, M.mp_src0(ar, self), OpsCONST{})` -- NO ARITY TEST AT ALL -- and
# `ct_6_pat`'s helper `rf_ix_1src` was `M.mp_nsrc_ge(ar, self, 1)`, AT LEAST ONE, against its
# own name, where CPython demands EXACTLY ONE. So on `INDEX(CONST 4, R0)` the port answered
# `CONST 4` and THREW THE RANGE AWAY: a wrong graph, not a bookkeeping difference, because a
# two-src INDEX over a CONST is exactly what `_mop_index` (prepare.py:67) produces.
# THE FIX: `rf_ix_1src` now reads `M.mp_nsrc_is(ar, self, 1)` -- the spelling `ct_6_casted`
# already used two lines above it -- and `ct_6` now CALLS `ct_6_pat`, so the body is gated by
# its own CLAIM. That second half is what also gives the body the `or_casted` arm, which it
# did not have: the claim is `(CONST | CAST-with-one-src)`, and a body that tested `CONST`
# alone could never reach the CAST alternative however the pattern was written.
# MEASURED, `ct_20`, one row, and nothing else in 726:
#     RED    bd's ct_20 is not 'ct_20=1 Ops.CONST/0 - arg=cint t=none'   (rc=1)
#     GREEN  ct_20=none                                                  (rc=0)
# `ct_20` is DROPPED from `DIVERGES`, not re-pinned: both lanes now print the same line.
# `nv`/`ct`/`fb`/`dg`/`lb`/`sk` rows were checked and did NOT move -- on this fixture a
# two-src INDEX whose `src[0]` is a CONST is node 20 and no other.
#
# FINDING 2, 3 -- the dispatchers omitted ops.py:1618's `ret is not uop`. The engine's clause
# is `if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret`, so an answer that is
# THE NODE ITSELF is dropped. `rangeify.bend` implemented that as `rf_self` and applied it
# at FOUR sites -- `rb_try`, `nic_dispatch`, `aprt_dispatch` and `ab_9`. `ab_dispatch` case 7
# (`ab_7`) DID NOT, and neither did `nv_dispatch`, `ct_dispatch`, `fb_dispatch`, `dg_dispatch`,
# `lb_dispatch` or `sk_dispatch`.
# MEASURED, on `CLS = CALL(SH1, C0)` (node 28) and `CLM = CALL(MST, C0)` (node 29): neither src
# is a RESHAPE, so `lambda k: k.replace(src=tuple(x.src[0] if x.op is Ops.RESHAPE else x))`
# rebuilds a node IDENTICAL to `k`; `UOp.new` HASH-CONSES, so the port's answer was the node's
# own index -- a legal, non-zero `Hop` -- and the row printed. CPython drops it and answers no
# rewrite. The port's `Hop` has no way to say "no answer" for a node that IS the answer except
# `rf_self`, and `ab_7` did not call it.
# THE FIX IS POSITION, NOT COUNT: `rf_self` now wraps the DISPATCH in the `True{}` arm of all
# ELEVEN `*_try.of`, which is where CPython applies it (inside `rewrite`, around `match`) and
# which is the shape `rb_try` already had. The three inner sites were REMOVED rather than kept,
# so `nic`/`aprt`/`ab` are covered by the same one clause as the other eight and a rule body can
# no longer forget it. MEASURED, two rows, and nothing else in 726:
#     RED    bd's ab_28 is not 'ab_28=8 Ops.CALL/2 Ops.SHRINK Ops.CONST arg=none t=none'  (rc=1)
#     GREEN  ab_28=none   ab_29=none                                                     (rc=0)
# `ab_28`/`ab_29` are DROPPED, not re-pinned: both lanes print `none`.
#
# CONSEQUENCE RANKING, because "FINDING" alone would be a label and not a measurement. `ab_28`/
# `ab_29` were the HARMLESS half: the answer is content-identical to the input, so no downstream
# graph changed -- a CONTRACT divergence from `PatternMatcher.rewrite`, not a wrong answer. Only
# `ct_20` was a wrong GRAPH, and it is the one that threw a range away. The eight dispatchers
# that carried the gap and did not fire (`nv`, `sk`, `ct`, `fb`, `dg`, `lb`) moved NO row, which
# is why the fix for them is a fix with no witness ON THIS FIXTURE: it is witnessed by `ab_28`/
# `ab_29` going green through the SAME clause, and by the fact that the census cannot produce a
# node on which the other eight would fire. A fixture node that could would be the next thing
# to add, and it is not added here.
# ===========================================================================
