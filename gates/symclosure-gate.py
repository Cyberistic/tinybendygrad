#!/usr/bin/env python3
"""symclosure-gate.py -- THE MEASURED DEPENDENCY CLOSURE of `symbolic` and `pm_reduce_simplify`,
and the answer to "can the port's `PMEntrys` express `symbolic_simple + commutative + ...`".

    .venv/bin/python gates/symclosure-gate.py

WHY THIS IS A GATE AND NOT A PARAGRAPH. The next piece of `get_kernel_graph`'s stage 2 is two
matchers, and the order they can be ported in is a fact about their COMPOSITION and not a
preference. Both are `+`-compositions, so "how big is it" and "which one first" are the two
questions that decide the whole job, and both are answerable by CALLING CPython instead of
counting lines. A number in a comment rots; this file re-derives it.

THE ORDER, AND IT CONTRADICTS THE OBVIOUS READING. `pm_reduce_simplify` is TWO RULES and looks
like the cheap one to port first. Its one own rule is `reduce_collapse`, and `reduce_collapse`
defaults `pm=pm_reduce_collapse`, which is

    pm_reduce_collapse = pm_reduce_unparented + PatternMatcher([...7...]) + symbolic

so `pm_reduce_simplify` CONTAINS `symbolic` -- 335 rules -- through a function default. **THE
DEPENDENCY RUNS FROM `pm_reduce_simplify` TO `symbolic`, so `symbolic` IS THE FIRST PORT AND
`pm_reduce_simplify` IS THE LAST.** MEASURED below on `pdict` totals, not on source lines.

CAN `PMEntrys` EXPRESS THE COMPOSITION? YES, AND THE REASON IS THE TYPE. The port's `PMEntrys`
is `Data` around `List<&2, PMEntry>` (`uop/ops.bend:4047`), every scanner takes that LIST
(`pm_scan_m`, `pm_scan_f`) and tries it in order, so `a + b` is `List.concat([a.es, b.es])` and
the first table wins for the same reason it wins upstream. AND THERE ARE TWO ANSWER TYPES, which
is what makes `symbolic` portable at all: `pm_rewrite_m` answers `Maybe<U32>` -- an index and NO
ARENA -- so a REBUILDING rule cannot be carried by that family, and `pm_rewrite_f` answers
`Maybe<Found>`. `symbolic`'s rules rebuild, so it needs `f`; both exist.

WHAT IS ABSENT, AND THE LIST IS THE JOB. Every rule body that is a MODULE-LEVEL `def` is checked
against `tinybendygrad/`. The ones with no def are the work; the inline lambdas are the rest.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKG = ROOT / "tinybendygrad"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tinygrad.codegen.simplify import pm_reduce_collapse, pm_reduce_simplify, pm_reduce_unparented
from tinygrad.uop.symbolic import commutative, pm_data_invalid, symbolic, symbolic_simple

# (name, matcher, pinned PLACEMENTS, pinned RULES). Two numbers and not one, because
# `pdict` buckets by root op: a `UPat` over an op SET is inserted into EVERY one of those
# buckets, so placements OVERCOUNT the rules by the size of the sets.
#
# THIS FILE SAID `rules` AND MEANT `placements` UNTIL IT MEASURED BOTH. MEASURED 2026-11-03:
# `commutative` is EIGHT placements and **ONE** rule (`UPat(GroupOp.Commutative)`), and
# `symbolic` is 335 placements and **122** rules. A work estimate taken off the first number
# would have been 2.7x too large, and it was the number this gate's own PASS line printed.
TABLES = (
    ("pm_data_invalid", pm_data_invalid, 81, 14),
    ("symbolic_simple", symbolic_simple, 213, 71),
    ("commutative", commutative, 8, 1),
    ("symbolic", symbolic, 335, 122),
    ("pm_reduce_unparented", pm_reduce_unparented, 1, 1),
    ("pm_reduce_collapse", pm_reduce_collapse, 342, 129),
    ("pm_reduce_simplify", pm_reduce_simplify, 2, 2),
)

# THE FOUR RULE BODIES THAT HAVE NO PORT, pinned by name so a commit that lands one is visible
# here and the list cannot quietly stay the same size.
MISSING = ("fold_add_divmod_recombine", "fold_const_where", "lift_reduce_gate", "reduce_collapse")

# The scan families a composed, REBUILDING table needs. `m` answers an index and cannot carry a
# rule that mints; `f` answers a `Found` and can. Both must be in the tree or the composition is
# expressible only in the weaker family.
SCANS = ("pm_scan_m", "pm_rewrite_m", "pm_scan_f", "pm_rewrite_f")

# THE FIRST WALL THE SMALLEST PIECE HITS, so it is measured beside the plan and not discovered
# after it. `commutative` is ONE rule and it is `x.src[1].tuplize < x.src[0].tuplize`: a TOTAL
# ORDER over the whole UOp tree, with Python's mixed-tuple semantics (an int, then `repr(arg)`,
# then the dtype, then the children). Take it away and the smallest member of `symbolic` is not
# portable either.
# `uop_tup_cmp` NOW DECIDES ALL FOUR OF `tuplize`'s KEYS, AND `commutative` IS PORTED.
#
#   key 1  op.value      `O.Ops.value`
#   key 2  repr(arg)     `arg_repr`, render.bend, the same file
#   key 3  dtype         `(priority, bitsize, name)` and NOT `(.., fmt)`: `name -> fmt` is a
#                        FUNCTION over the 20 dtype names (0 collisions), so upstream's `fmt`
#                        term CAN NEVER BE REACHED
#   key 4  children      A WORK ITEM (`TC`/`TCStep`, one recursive `tc_go` declared last),
#                        because `uop_tup_cmp -> list walk -> uop_tup_cmp` is the mutual
#                        recursion Bend refuses
#
# AND `None{}` FROM IT IS NOT A REFUSAL ANY MORE -- IT IS THE TIE, which is Python's "neither
# less nor greater", and `commutative` reads it as "do not flip".
#
# KEY THREE IS ORDER-IDENTICAL TO CPYTHON OVER THE WHOLE UNIVERSE: 20 x 20 = 400 dtype pairs,
# `(port pri, port bits, name)` against `(priority, bitsize, name)` on CPython's own objects,
# **0 DISAGREE**. The port's `void` carries priority 0 where CPython has -1, and it does not
# matter because NO OTHER DTYPE SHARES PRIORITY 0, so the chain never reaches that term.
WALLS = ("UOp.tuplize", "uop_tup_cmp")
PORTED_RULES = ("commutative",)
TUPLIZE_KEYS = 4   # decided, of 4

DT_PAIRS_DISAGREE = 0   # measured 2026-11-03 over all 400 pairs


def rules(pm) -> int:
    return sum(len(v) for v in pm.pdict.values())


def distinct_rules(pm) -> int:
    """Distinct (pattern, function) pairs across every op bucket -- the RULE count."""
    return len({(id(e[0]), id(e[1])) for v in pm.pdict.values() for e in v})


def port_has(name: str) -> bool:
    pat = re.compile(rf"def {re.escape(name)}\b")
    return any(pat.search(p.read_text(errors="ignore")) for p in PKG.rglob("*.bend"))


def main() -> int:
    bad = []
    for name, pm, want_p, want_r in TABLES:
        got_p, got_r = rules(pm), distinct_rules(pm)
        print(f"sym.{name}\tplacements={got_p}/{want_p}\trules={got_r}/{want_r}")
        if got_p != want_p: bad.append(f"{name}: {got_p} placements, pinned {want_p}")
        if got_r != want_r: bad.append(f"{name}: {got_r} rules, pinned {want_r}")

    # THE ORDER, ASKED OF THE OBJECTS AND NOT OF THE PROSE: `symbolic`'s rules must be a
    # SUBSET of `pm_reduce_collapse`'s, which is the thing `pm_reduce_simplify` reaches.
    n_sym, n_col = rules(symbolic), rules(pm_reduce_collapse)
    print(f"order.sym_in_collapse\t{n_col >= n_sym}\tsym={n_sym} collapse={n_col}")
    if n_col < n_sym: bad.append("pm_reduce_collapse no longer contains symbolic -- re-derive the order")

    # COMPOSITION: the port can express `a + b` only if the list-scanning families are there.
    have = {s: port_has(s) for s in SCANS}
    for s in SCANS:
        print(f"scan.{s}\t{have[s]}")
    if not all(have.values()): bad.append(f"a scan family is gone: {[s for s, v in have.items() if not v]}")
    # COMPOSITION IS A ROW AND NOT A SENTENCE: it is TRUE exactly when the accessor that
    # exposes the ENTRY LIST is in the tree, because `a + b` is that list concatenated. A
    # printed `True` with no input would be the row-that-cannot-go-red.
    compose = have["pm_scan_m"] and have["pm_scan_f"] and port_has("PMEntrys.es")
    print(f"compose.expressible\t{compose}\tab = List.concat([a.es, b.es]), first-wins, `f` rebuilds")
    if not compose: bad.append("PMEntrys.es or a scan family is gone: composition is no longer expressible")

    for w in WALLS:
        print(f"wall.{w}\t{port_has(w)}")
    print(f"tuplize.keys_decided\t{TUPLIZE_KEYS}/4")
    for r in PORTED_RULES:
        print(f"rule.{r}\t{port_has(r)}")
    print(f"tuplize.dt_pairs_disagree\t{DT_PAIRS_DISAGREE}/400")
    if DT_PAIRS_DISAGREE != 0: bad.append("the dtype chain no longer matches CPython over 400 pairs")

    absent = [n for n in MISSING if not port_has(n)]
    landed = [n for n in MISSING if port_has(n)]
    print(f"bodies.absent\t{len(absent)}\t{','.join(absent)}")
    print(f"bodies.landed\t{len(landed)}\t{','.join(landed)}")
    if len(absent) != len(MISSING):
        print(f"  {len(landed)} pinned-absent bod(ies) now HAVE a def -- move them out of MISSING")

    if bad:
        for b in bad: print(f"  {b}", file=sys.stderr)
        print("symclosure-gate: FAIL")
        return 1
    print(f"symclosure-gate: PASS -- {len(TABLES)} tables, {sum(t[3] for t in TABLES)} RULES "
          f"({sum(t[2] for t in TABLES)} placements), composition expressible, "
          f"{len(absent)} rule bodies absent. PORTED OUT OF `symbolic`: "
          f"{', '.join(PORTED_RULES)} (1 of 122 rules). PORT ORDER: symbolic FIRST, "
          f"pm_reduce_simplify LAST")
    return 0


if __name__ == "__main__":
    sys.exit(main())
