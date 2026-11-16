# gates/search-gate.bend -- the gate driver for `tinybendygrad/codegen/opt/search.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/opt/search.bend as P

import ./../tinybendygrad/codegen/opt/postrange.bend as PR
import ./../tinybendygrad/uop/ops.bend as O
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# THE GATE. Every row is DERIVED FROM CPython, so a row can be wrong. The
# reference values are in the header.
#
# `zero_un9` AND `zero_red0` ARE GONE, and their DELETION is the point. Both asked
# has, so they asserted facts about BEND-ONLY CONSTRUCTS and could never disagree
# with CPython -- the worst kind of row. `P.tgt_kinds`, `tgt_*`, `byop_*` and
# `zero_n_*` replace them: those are read off CPython's REAL table and they fail if
# the deleted 60-entry group comes back under any name. The two arms survive only as
# `P.zero_variant.dead`, which is BEND-ONLY and says so, and which NO row asks -- a
# deleted member's answer has nothing to compare against, and `ops.bend` takes the
# same position on `axv_REDUCE` / `axv_UNROLL`.
#
# `zero_lcl8` IS NEW AND IT IS NOT REDUNDANT WITH `zero_lcl7` / `zero_lcl9`. Those
# two sit either side of 8 only on ONE side: `lcl7 = 1` and `lcl9 = 0` are both
# satisfied by a ladder whose LOCAL bound is 8, 7 or 9, because axis 8 is never
# asked about. Widening the bound to 9 -- which puts an amt-0 entry on an axis the
# table has none for, a WIDENING and therefore a silent one -- moved NOTHING before
# this row existed. `zero_lcl8` is the one-axis-from-its-opposite pair the brief asks
# for, and `zero_up9`/`zero_up10` already had that pair for UPCAST.

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("acts_n", P.acts_n(P.CFG.def()))
    b : Unit <- row("acts_n_padto", P.acts_n(P.CFG.padto()))
    c : Unit <- row("acts_zero", P.acts_zero())
    d : Unit <- row("grp_up", P.grp.up())
    e : Unit <- row("grp_lcl", P.grp.lcl())
    f : Unit <- row("grp_lcl_top", P.grp.lcl_top())
    g : Unit <- row("grp_padto", P.grp.padto(P.CFG.padto_on(P.CFG.padto())))
    h : Unit <- row("grp_split32", P.grp.split32())
    i : Unit <- row("grp_tc0", P.grp.tc0())
    j : Unit <- row("grp_tc", P.grp.tc())
    k : Unit <- row("grp_swap", P.grp.swap())
    l : Unit <- row("tgt_kinds", P.tgt_kinds())
    m : Unit <- row("tgt_up", P.tgt_up())
    n : Unit <- row("tgt_lcl", P.tgt_lcl())
    o : Unit <- row("tgt_split", P.tgt_split())
    p : Unit <- row("byop_split", P.tgt_split())
    q : Unit <- row("byop_tc", P.byop.tc())
    r : Unit <- row("byop_swap", P.byop.swap())
    s : Unit <- row("byop_padto", P.byop.padto(P.CFG.padto_on(P.CFG.def())))
    t : Unit <- row("zero_n_up", P.zero_n.up())
    u : Unit <- row("zero_n_lcl", P.zero_n.lcl())
    v : Unit <- row("zero_max_up", P.zero_max.up())
    w : Unit <- row("zero_max_lcl", P.zero_max.lcl())
    x : Unit <- row("zero_top_n", P.zero_top_n())
    y : Unit <- row("zero_up0", P.b2u(P.zero_variant(O.AXIS_UPCAST{}, False{}, 0)))
    z : Unit <- row("zero_up9", P.b2u(P.zero_variant(O.AXIS_UPCAST{}, False{}, 9)))
    a1 : Unit <- row("zero_up10", P.b2u(P.zero_variant(O.AXIS_UPCAST{}, False{}, 10)))
    b1 : Unit <- row("zero_lcl7", P.b2u(P.zero_variant(O.AXIS_LOCAL{}, False{}, 7)))
    c1 : Unit <- row("zero_lcl8", P.b2u(P.zero_variant(O.AXIS_LOCAL{}, False{}, 8)))
    d1 : Unit <- row("zero_lcl9", P.b2u(P.zero_variant(O.AXIS_LOCAL{}, False{}, 9)))
    e1 : Unit <- row("zero_top0", P.b2u(P.zero_variant(O.AXIS_LOCAL{}, True{}, 0)))
    f1 : Unit <- row("zero_top9", P.b2u(P.zero_variant(O.AXIS_LOCAL{}, True{}, 9)))
    g1 : Unit <- row("dropped", P.plus_dropped())
    h1 : Unit <- row("drop_ok", P.b2u(P.drop(False{}, False{})))
    i1 : Unit <- row("drop_seen", P.b2u(P.drop(True{}, True{})))
    j1 : Unit <- row("keep_ok", P.b2u(P.drop(True{}, False{})))
    k1 : Unit <- row("least_lo", P.least_of(True{}, 5, 9))
    row("least_hi", P.least_of(False{}, 5, 9))

# THE MEASURED MUTATION TABLE. 21 mutations, 20 localised, 1 blind spot with a reason.
# Re-measured 2026-10-03 by `.agents/slop/mutate.py`, which diffs whole `name=value`
# lines and treats a zero-row run as a failed run rather than a verdict.
#
#   mutation                                   rows that moved

#   `P.grp.up`      60 -> 61                     grp_up P.tgt_up P.tgt_split byop_split P.acts_n acts_n_padto
#   `P.grp.lcl`     64 -> 63                     grp_lcl P.tgt_lcl P.tgt_split byop_split P.acts_n acts_n_padto
#   `P.grp.lcl_top` 64 -> 63                     grp_lcl_top P.tgt_lcl P.tgt_split byop_split P.acts_n acts_n_padto
#   `P.grp.padto`   True 7 -> 8                  grp_padto acts_n_padto
#   `P.grp.split32` 1 -> 2                       grp_split32 P.tgt_lcl P.tgt_split byop_split P.acts_n acts_n_padto
#   `P.grp.tc0`     1 -> 2                       grp_tc0 byop_tc P.acts_n acts_n_padto
#   `P.grp.tc`      9 -> 8                       grp_tc byop_tc P.acts_n acts_n_padto
#   `P.grp.swap`    10 -> 9                      grp_swap byop_swap P.acts_n acts_n_padto
#   the 60 UPCAST entries re-attributed to
#     LOCAL, TOTAL HELD AT 209                 P.tgt_up P.tgt_split byop_split
#   the 10 SWAP entries re-attributed to
#     TC, TOTAL HELD AT 209                    byop_tc
#   `P.tgt_kinds`   2 -> 3                       P.tgt_kinds
#   `P.zero_n.up`   10 -> 11                     zero_n_up zero_max_up P.acts_zero zero_up10
#   `P.zero_n.lcl`  8 -> 7                       zero_n_lcl zero_max_lcl P.acts_zero zero_lcl7
#   `P.zero_top_n`  0 -> 1                       P.zero_top_n
#   ladder reads `P.zero_max` (UPCAST)           zero_up9
#   ladder reads `P.zero_max` (LOCAL)            zero_lcl7
#   `P.zero_variant` allows top=True             zero_top0
#   `P.zero_variant.dead` treats REDUCE as LOCAL NONE   <- THE BLIND SPOT, below
#   `drop_ok` inverted                         drop_ok keep_ok
#   `P.min2` returns the larger                  least_lo
#   `P.plus_dropped` subtracts 3 not 4           dropped
#
# the three total-preserving mutations are the point of the census, and each is one
# LINE so the compensating edit cannot be what hides the disagreement. `P.acts_n` does
# NOT move for any of them; something else does. That is the difference between "the
# table has 209 entries" and "the table has THESE 209 entries", and it is the reason
# `P.tgt_kinds` and the `tgt_*` / `byop_*` / `zero_n_*` rows exist at all.
#
# `P.zero_n.up` / `P.zero_n.lcl` moving a ladder row is also the point. `P.acts_zero` used to
# be `U32.add(U32.add(10, 10), 8)` and `P.zero_variant` used to carry its own literal
# `10`, and the two had already drifted -- the count carried a UNROLL term the ladder
# did not. They are one source now, so a census change cannot leave the predicate behind.
#
# the blind spot, reported rather than closed. `P.zero_variant.dead` has no row asking it,
# because the two members it names do not exist upstream: the oracle cannot construct
# `AxisType.REDUCE` either, so any row over it would compare a Bend-only answer with
# nothing and assert the Bend's own behaviour -- the `device.bend` `sig=0 4 5` shape.
# What DOES cover the rebase that would make the dead arm matter is `P.tgt_kinds`: a
# rebase that reinstates UNROLL has to add its `amt = 0` group too, and that moves
# `P.tgt_kinds` 2 -> 3. `uop/ops.bend` takes the same position on `axv_REDUCE` /
# `axv_UNROLL` for the same reason.
#
# the off-by-one that was real. Both "ladder reads `zero_max`" rows are here because the
# refactor made that mistake once: `P.zero_max.up()` is the highest axis that HAS a twin
# (9), while the ladder needs the exclusive bound (10). Reading the former printed
# `ax < 9`, which is `zero_up9` 1 -> 0 and `zero_lcl7` 1 -> 0 -- two rows, immediately,
# the moment the census was introduced. `P.zero_max.*` is reported, not consumed.
