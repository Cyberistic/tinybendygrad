#!/usr/bin/env python3
"""decomp_graph_census-gate.py -- A GRAPH CENSUS over the graph-BUILDING half of
`tinybendygrad/codegen/decomp/dtype.bend`, and the FIRST gate that layer has ever had.

    .venv/bin/python gates/decomp_graph_census-gate.py
    .venv/bin/python gates/decomp_graph_census-gate.py --refresh   # rewrites the pins file

43 ROWS, THREE LANES, 26 EXACT MATCHES AND 17 DECLARED DIVERGENCES -- 11 PROMOTION, 2
REFUSALS, 2 UNBUILT ROWS (ONE ARM) AND 2 FINDINGS.

EVERY CAST AND BITCAST CARRIES ITS TARGET DTYPE IN THE TOKEN, `OP/NSRC[TARGET]`, AND THAT
IS A REPAIR WITH A MEASUREMENT BEHIND IT. Before this, `sig` printed the bare word `CAST/1`
for every cast in every row -- MEASURED, 453 `CAST/1` and 33 `BITCAST/1` on the port lane and
741 and 34 on CPython's, NONE of them carrying an argument -- so the 282 casts `classes_hold`
deletes were COUNTED and never READ, a `bool->u32` promotion and a `f32->i32` narrowing were
the same token, and `lg1`'s two adjacent casts (`CAST(i32->i64)` at index 1 and
`CAST(weakint->i32)` at index 2) were interchangeable to `witnesses()`, which measured ONE
alternative deletion witness for that row. MEASURED after: the token identifies each cast,
`witnesses()` measures ZERO alternative witnesses over the seven cones under `SHORT_CONE`, and
`gates/decomp_graph_census-mutate.py` A1 -- which breaks ONLY the `ADt` argument of the one
call `dtype.bend:593,637` hands to both the fold test and the CAST -- moves 5 rows with the
printer in place and 0 rows without it. THAT IS THE COUPLING `crp_graph_census-mutate.py`
could not see, and it is visible HERE because `decomp`'s own helpers mint the `ADt`;
`mixin/creation.bend`'s `de` is NOT on this gate's import closure, and the footer says so.

`dtype.bend` ships its OWN 208-row `gate()` (dtype.bend:3068), which prints each fixture's
tree, its intern count, its DEEP CONE and its constants. What was ungated was the GRAPH
AGAINST CPYTHON: nothing compared a cone to the one dtype.py builds, so a port that built a
different node agreed with itself. `op.bend` ships a 146-row `gate()` (:2171) with the same
gap. This gate is the CPython lane for the 43 of those rows that are a GRAPH.

THE POPULATION IS THE PORT'S OWN FIXTURE SET, AND THE RULE IS NOT THE `*_table` RULE.
`gates/rng_graph_census.bend`'s row is a (TABLE, NODE) pair whose TABLE axis is
`grep -c '^def [a-z]*_table'`. MEASURED: that count is **0** in every file of
`tinybendygrad/codegen/decomp/` -- `op.bend`, `dtype.bend`, `transcendental.bend`,
`transcendental_f32.bend`. decomp is a graph BUILDER, not a rewriter, so it has no dispatch
tables and the rng rule has nothing to range over; the substitute axis is the FIXTURE, and
the fixture population is the port's own `l2i.pick` (:2780, 33 arms), `dd_cmx.pick` (:2931,
8) and `f2f.pick` (:3053, 7). Thirty of `l2i.pick`'s arms read the word pool and three mint
a CONST, so the pool-fed set is 30 + 1 `unpack32` + 7 `f2f` = **38**, a SECOND `unpack32`
fixture is driven on purpose for 39 -- `uq`, over the pool's `i32` word, because `up` FOLDS
the BITCAST away and `gates/decomp_graph_census-mutate.py` A13 measured that breaking the
unfolded arm's `ADt` moved 0 of 38 rows -- and `l2i.const`'s THREE arms (`lgv lgw lgx`) are
driven for **42**, because they mint their CONST OUTSIDE `l2i` at `xdt` and so read no word of
the pool at all, and **`lgz` is driven for 43 AND IS NOT `l2i.pick`'s ARM AT ALL** -- it is a
cell of the `(dt, xdt)` product the port's own fixture table DECLINES, and the pool it is drawn
from is FED AND DECLINED: MEASURED over the 33 arms, `dt` ranges over {i32, i64, u64, u32, f32}
and `dd_wpool` has no f64 word, so `double` -- the only member of `spec.bend`'s own `Dt`
population with 64 bits AND `CFloat` (:742) -- reaches `l2i` from NO row. A population rule
keyed on "ARMS THAT READ THE POOL" cannot see it, which is
the same class as `amd_dsl_census`'s `VOP2_FIELDS` having no `src2`. THE COUNT IS THE PORT'S AND
IT IS NOW ASSERTED
TWICE: `gatekit` refuses the run if a lane disagrees with `ROWS`, and the mutate harness
refuses to compare against a base lane of any other length. BOTH BEND LANES EMIT EVERY ROW
including a refusal, so the two counts agree BY CONSTRUCTION and no exclusion list is
needed to make them meet. THE FIXTURE TABLE IS MIRRORED, NOT DISCOVERED -- the port's arms
and the oracle's are the same thirty rows index for index, which is the rng oracle's own
"the oracle MIRRORS it index for index" (`gates/rng_graph_census-oracle.py:46`), and `lgz` is
the ONE row where both sides hand-write a cell rather than mirror an arm.

`dd_cmx.pick`'s EIGHT ARMS ARE NOT ROWS HERE, AND THE REASON IS SHAPE AND NOT OMISSION. They
are the `c*` rows and they print `F(<bits>)` -- a scalar from `f2f_clamp_max` (dtype.bend:2920)
-- where this census prints a CONE. `unpack32` is a def this census can reach as a graph, and
it is now reached twice. `l2i.const` is reached three times, and those three rows are the
ONLY rows whose operand the census did not take out of the pool. `lgz` is the one row whose
CELL the pool's own table does not contain, and it is the only row that is not a deletion,
a refusal-by-both-sides, or a mirror of an arm -- see the footer's `lgz` block.

THE ORACLE CALLS THE REAL CPYTHON. Every row is a call into `tinygrad/codegen/decomp/` --
`l2i` (dtype.py:21), `unpack32` (:13), `f2f` (:101) -- on a fixture mirroring `l2i.pick`
index for index, over the port's own 24-node pool (`dd_wpool`, :2549). Nothing here
reimplements a decomposition. `gates/tn_bitwise_not-oracle.py`'s docstring is the
post-mortem for an oracle that hand-built `cast.ne(true_)` -- and IT HAPPENED TWICE HERE.

`tinygrad/codegen/decomp/` HAS NOT DRIFTED SINCE THE PIN. MEASURED, and it is the reason
HEAD is the oracle for this file: `git diff --stat 'ad117c928^' HEAD -- tinygrad/codegen/
decomp/` is EMPTY, the three working-tree blobs hash to the two commits' blobs
(`git hash-object` == `git rev-parse`) at `36907bf9d92af507840f6f1d2fdc9796762c03e0`
(op.py), `e1d9579c1bc0de9eb773d2104007b2adb6af1b63` (dtype.py) and
`62c319175e46dc5b0089bebf3a90a026de1f331d` (transcendental.py), and
`tinygrad/renderer/cstyle.py` -- which DID drift, 29 insertions and 26 deletions since the
same pin -- is the file `AGENTS.md` names. A disagreement that vanished under the pin would
have been the answer; nothing vanished, because nothing moved.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM -- `Arena.bottom()`, what
`Arena.node` answers for an index the arena does not hold -- so a `NOOP` in a cone is an
index read out of range and always a defect. **THIS GATE'S OWN FIRST DRAFT HAD SIX**: `q1`
through `q5` and `q7` printed `NOOP/0` because `dc_f2f1` read the cone off the arena it
HANDED IN rather than the one the ANSWER came back in, which is defect class (a), the
stale-arena self-loop. `no_noop_bottom` asserts the property, and the fix is in this gate's
own bend lane, not in the port.

THE 16 DIVERGENCES, CLASSIFIED BY A MEASUREMENT AND PINNED ON BOTH SIDES.

  11 PROMOTION CASTS -- `lg1 lg5 lga lgc lgd lge lgq lgr lgs lgt q5`, deleting 4, 1, 2, 1,
  1, 6, 69, 70, 63, 64 and 1 `CAST/1` entries. Each is VERIFIED to be a DELETION AND NOT A
  RESEMBLANCE: `deleted()` walks CPython's cone against the port's and REBUILDS the list, so
  the claim is that deleting exactly those N `CAST/1` entries reproduces the port's row
  token for token over the WHOLE cone -- 2500 entries for `lgq`, not a 3-op prefix. The census
  does NOT erase anything to manufacture the agreement: the oracle prints CPython AS BUILT and
  the difference is pinned.

  THE MECHANISM, MEASURED, AND IT IS NOT THE ONE THIS FILE USED TO NAME. The previous
  revision attributed these CASTs to "`UOp.__init__`'s `dtype_from_uop` and `_broadcasted`'s
  bool->int ... that `ops.bend`'s `UOp.new` does not run". **All three names are wrong, and a
  wrong reason is worse than none.** MEASURED on this checkout: `UOp` has NO `__init__` -- it is
  built by `UOpMetaClass.__call__` (`ops.py:197`), and the only `__init__` inside `class UOp`'s
  own source is the word in a comment at `ops.py:245`. `dtype_from_uop` (`ops.py:122`) RETURNS a
  `DType` and mints no node, so it cannot insert one. `_broadcasted` is not on `UOp` at all: the
  only `_broadcasted` on a UOp-shaped object is `UPat._broadcasted` (`ops.py:1534`), a pure
  reorder. The one that inserts is **`ElementwiseMixin._broadcasted`, `mixin/elementwise.py:24`**,
  and its inner `promote` returns `t.cast(out_dtype)` at `:32` and `remint(t._uop, dt)` at `:30`,
  with `out_dtype = least_upper_dtype(x.dtype, y.dtype)` at `:26`. So it is a general
  `least_upper_dtype` PROMOTION, not a "bool->int" special case, and the node it inserts sits on
  the Tensor-level binop -- which `codegen/decomp` never takes (see below).

  THE PORT HAS THE MECHANISM AND DOES NOT CALL IT, AND THAT IS THE MEASURED CAUSE.
  `mixin/elementwise.bend`'s `ew_promote` IS `promote`, `mixin/op.bend`'s `mo_bin` calls it
  through `mo_promote`, and both read the lattice out of `uop/fold.bend`'s hoisted
  `F.least_upper.of`. MEASURED: every ALU in `codegen/decomp` is built by `dd_add`/`dd_mul`/
  `dd_lt1`/... (`dtype.bend:410-440`), which are one-liners onto `T.tx_alu2`/`T.tx_alu3`, and
  `transcendental.bend:199,202` are `O.UOp.alu(ar, op, [x, y])` -- a raw ALU with pre-typed
  operands and no promotion anywhere. `grep -c OpsCAST tinybendygrad/codegen/decomp/*.bend` is
  20 in `dtype.bend` and 1 in `op.bend`, so the AMD unit's "0 here" does NOT hold for decomp;
  the 20 are casts decomp mints DELIBERATELY (`dd_cast_fold`, `dd_cf`, `dd_cast_bool`), which is
  a different thing from the casts it omits. The absence is STRUCTURAL, not a missing helper.

  2 REFUSALS -- `lgn` and `q6`. CPython raises `NotImplementedError` (dtype.py:81 for
  FLOORDIV, dtype.py:125 for `f2f`'s `else`) and the port declines. Both are answers and
  neither is smoothed; they differ in their TOKEN, which is a naming divergence and is
  pinned.

  2 UNBUILT ROWS, ONE ARM -- `lgu` and `lgz`, both `dtype.py:35-38`, the float-target CAST.
  `lgu` is `l2i(Ops.CAST, f32, f32)` and `lgz` is `l2i(Ops.CAST, f64, f32)`: same op, same
  source, same two pool words, and the ONLY difference is `dt`'s WIDTH. CPython builds a
  20-node `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` and the port returns `None`:
  `dtype.bend:2818` records this as "This arm is not built (header C)". `unported`, not
  dtype.py's exception name -- a different fact. AND THE TWO REFUSE FOR THE SAME REASON, WHICH
  IS MEASURED AND NOT ASSUMED: `l2i_cast.wide`'s `l2i_dt(dt)` is `None` for BOTH, because
  `l2i_dt` (dtype.bend:271-282) is CPython's `{long: int, ulong: uint}` and admits `CSint`/`CUint`
  only. `lgz` is therefore not a second shape of the same refusal -- it is the SAME refusal with
  `dd_is_long` returning the width CPython's guard is a MEMBERSHIP test on. See the footer's
  `dd_is_long` block, whose mechanism this row REFUTES.

  2 FINDINGS -- `q2` and `q3`, `f2f`'s narrowing arm onto fp8e4m3 and fp8e5m2. The port's
  cone is NOT a deletion of CPython's: CPython carries `CAST/1` x2, `CONST/0` x1 and
  `OR/2` x2 that the port does not, and the order of what is left differs too. See the
  block at the foot of this file.

EXIT STATUS: 0 all three lanes identical after the pins, every class check holds and no
lane read the NOOP bottom · 1 a lane took the wrong row count, the oracle failed, the native
compile failed, the lanes disagree, a pin moved, a class check failed, or a lane grew a
`NOOP` · 3 a precondition was absent (the pins file, the output directory, the substrate,
or the oracle).
"""

import hashlib
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, REFUSED, gate

# THE 43 ROWS, in the port's own order: `l2i.pick`'s thirty pool-fed arms, then `lgz` -- the one
# row that is NOT an arm, a cell of the `(dt, xdt)` product `l2i.pick` declines -- then `lgy`,
# `l2i.const`'s THREE (`lgv lgw lgx`, `l2i.pick`'s cases 28/29/30, whose CONST is minted OUTSIDE
# `l2i`), then `unpack32` TWICE -- `up` on the pool's u32 word and `uq` on its i32 word, the second
# so the BITCAST `ops.py:13` builds is in a row at all -- then `f2f.pick`'s seven. The COUNT is
# the file's, and the bend lane emits all 43 including refusals, so this is a MEASUREMENT of the
# lanes and not a typed inventory: `gatekit` refuses the run if a lane disagrees with it.
ROWS = ("lg1", "lg2", "lg3", "lg4", "lg5", "lg6", "lg7", "lg8", "lg9", "lga", "lgb", "lgc",
        "lgd", "lge", "lgf", "lgg", "lgh", "lgi", "lgj", "lgk", "lgl", "lgm", "lgn",
        "lgo", "lgq", "lgr", "lgs", "lgt", "lgu", "lgz", "lgy",
        "lgv", "lgw", "lgx",
        "up", "uq",
        "q1", "q2", "q3", "q4", "q5", "q6", "q7")

# THE CLASSIFICATION, HAND-DECLARED, AND EVERY NUMBER IN IT MEASURED. This tuple set IS the
# divergence POPULATION -- it is hand-written here, in git, and `decomp_graph_census-pins.rows`
# is checked against it in BOTH directions, so neither can drift alone. The previous version
# of this file had no such tuple set: it derived the population from the last run's own
# artifacts, which is a population read out of a swept directory and therefore a population
# that cannot be wrong.
#
# `PROMOTION_CASTS` is the claim that makes the class MEASURED rather than NAMED: deleting
# exactly this many `CAST/1` entries from CPython's cone reproduces the port's, over the
# whole cone, and `classes_hold` proves it on every run instead of believing this table.
PROMOTION_CASTS = {"lg1": 4, "lg5": 1, "lga": 2, "lgc": 1, "lgd": 1, "lge": 6,
                   "lgq": 69, "lgr": 70, "lgs": 63, "lgt": 64, "q5": 1}
# AND WHAT THOSE CASTS WERE CAST TO. MEASURED off the lanes at `7d1c9f0` -- this is not a
# transcription of the hand-written six-pair table this file used to carry at :514-521,
# which named `src->target` PAIRS and so needed a node's DTYPE, which NO row carries and no
# run of this gate has ever read. The deleted TARGET is in the row now (`decomp_graph_census
# .bend`'s `dc_tok` and the oracle's `s1`), so it is asserted on every run instead of being
# a claim about a file that measured it by hand.
#
# THE PREVIOUS TABLE AND THIS ONE DISAGREE, AND IT IS WORTH SAYING WHERE. It read
# `u32 263, i64 14, i32 5`; measured is `u32 263, i64 17, i32 2`. Three entries the old table
# called `i32` are `i64`. Its `3 weakint -> i32 (over CONST/0) ** NOT _broadcasted **` line is
# also the only one that can be checked against this: `lg1`'s surviving cast is `CAST/1[i32]`
# and its four deleted ones are all `i64`, so that line counted the port's OWN node as part of
# the 282 the class deletes, which it is not.
PROMOTION_TARGETS = {"lg1": {"i64": 4},
                     "lg5": {"i32": 1},
                     "lga": {"i64": 2},
                     "lgc": {"u32": 1},
                     "lgd": {"u32": 1},
                     "lge": {"i64": 5, "i32": 1},
                     "lgq": {"i64": 3, "u32": 66},
                     "lgr": {"i64": 3, "u32": 67},
                     "lgs": {"u32": 63},
                     "lgt": {"u32": 64},
                     "q5": {"u32": 1}}
WALL = ("lgn", "q6")
UNBUILT = ("lgu", "lgz")
FINDING = ("q2", "q3")
PROMOTION = tuple(PROMOTION_CASTS)
DIVERGING = PROMOTION + WALL + UNBUILT + FINDING

HERE = Path(__file__).resolve().parent
PINS = HERE / "decomp_graph_census-pins.rows"
ART = HERE / "artifacts" / "decomp_graph_census-gate"


def _pins():
    """`(DIVERGES, why)` -- the pins LOADED BY PATH, and the population they must agree with.

    The content comes from the file, the POPULATION comes from the tuples above, and the two
    are checked against each other here rather than one being derived from the other: a row
    pinned and not declared is a pin nothing will ever exclude, and a row declared and not
    pinned is an exclusion with no content behind it. Both are failures here.
    """
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live in "
                      f"git, not in its own output directory")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        row, py, bd = ln.split("\t")
        pins[row] = (py, bd)
    if set(pins) != set(DIVERGING):
        extra, gone = sorted(set(pins) - set(DIVERGING)), sorted(set(DIVERGING) - set(pins))
        return None, (f"the pins file and the declared classes disagree: pinned but not "
                      f"declared {extra}, declared but not pinned {gone}")
    return pins, ""


DIVERGES, WHY = _pins()


def _header(n_div, n_same):
    """THE HEADER, WITH ITS TWO COUNTS. A function and not a `str.format` TEMPLATE because
    the prose quotes `_pins()` returning `{}`, and both `format` and an f-string read that
    as a replacement field -- MEASURED, `IndexError: Replacement index 0` on the first
    `--refresh`. The sentence now says EMPTY DICT, which is also what it means."""
    return f"""# decomp_graph_census-pins.rows -- GENERATED by `decomp_graph_census-gate.py --refresh`,
# which is its ONLY writer. One TAB-separated triple per declared divergence:
# `<row>\\t<CPython's line>\\t<the port's line>`, i.e. the expected content on BOTH sides.
#
# {n_div} DIVERGENCES, {n_same} OF THE {len(ROWS)} ROWS AGREE EXACTLY. It is git-resident and beside the
# gate because `AGENTS.md`'s own rule is that a gate's required inputs live in git and not
# in `gates/artifacts/`: `gatekit` EMPTIES that directory before it runs and UNLINKS what
# it staged when the run was not green, so a divergence list read from there is destroyed
# by the first red run and there is then nothing left to edit. The version of this gate that
# arrived read `DIVERGES` from exactly that directory -- its `_pins()` -- and MEASURED on
# arrival it returned an EMPTY DICT, so the gate demanded all 38 rows agree, and `gatekit`'s
# `bad = [...] [:2]` printed only the FIRST TWO disagreements. There were SEVENTEEN.
#
# EACH COMMENT CARRIES ITS OWN SHA-256 PREFIX AND BYTE COUNT, so a reviewer sees a moved pin
# without reading a 16 000-character line. A pin somebody TYPED wrong makes the gate RED;
# a pin read back out of the last run's own output cannot be wrong, which is the only
# argument for reading it from there and the reason for not doing so.
"""


def refresh() -> int:
    """REWRITE `decomp_graph_census-pins.rows` from a fresh pair of lanes. Its only writer.

    It does NOT go through `Gate.run()`, because a refresh is exactly what a run cannot do
    when the pins are wrong: the whole point is to replace them. Both lanes are produced
    here and the divergence rows are whatever DISAGREES, so the population is a measurement
    of the pair -- and the header, the per-row class comment and the byte counts are
    rewritten with it, because a pins file whose prose outlives its content is a second
    document disagreeing with the first.
    """
    py = subprocess.run([str(PY), str(HERE / "decomp_graph_census-oracle.py")],
                        capture_output=True, text=True, cwd=HERE.parent)
    bd = subprocess.run([str(BEND), "gates/decomp_graph_census.bend"],
                        capture_output=True, text=True, cwd=HERE.parent)
    if py.returncode or bd.returncode:
        print(f"--refresh: a lane failed (py rc={py.returncode}, bd rc={bd.returncode}); "
              f"nothing written", file=sys.stderr)
        return 1
    got = {t: {l.split("=", 1)[0]: l for l in s.splitlines() if "=" in l}
           for t, s in (("py", py.stdout), ("bd", bd.stdout))}
    rows = [r for r in ROWS if got["py"].get(r) != got["bd"].get(r)]
    out = [_header(len(rows), len(ROWS) - len(rows))]
    for r in rows:
        cls = ("PROMOTION, %d CAST deleted, targets %s" % (
                   PROMOTION_CASTS[r],
                   " ".join(f"{k}x{v}" for k, v in sorted(PROMOTION_TARGETS[r].items())))
               if r in PROMOTION else
               "WALL, both sides refuse" if r in WALL else
               "UNBUILT ARM, dtype.py:35-38 builds it and l2i_dt(dt) is None"
               if r in UNBUILT else
               "FINDING, port is NOT a deletion of CPython's cone")
        out.append("# %-4s %-58s cpy %6d B %s | port %6d B %s" % (
            r, cls, len(got["py"][r]), hashlib.sha256(got["py"][r].encode()).hexdigest()[:12],
            len(got["bd"][r]), hashlib.sha256(got["bd"][r].encode()).hexdigest()[:12]))
        out.append("%s\t%s\t%s" % (r, got["py"][r], got["bd"][r]))
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, "
          f"{len(ROWS) - len(rows)} exact matches")
    return 0


def _lane(name):
    f = ART / name
    if not f.is_file():
        return None
    return {l.split("=", 1)[0]: l.split("=", 1)[1] for l in f.read_text().splitlines() if "=" in l}


def deleted(cpy, port):
    """`cpy` minus the entries that reproduce `port`, or `None` when it is not a deletion.

    A SUBSEQUENCE TEST IS NOT THE CLAIM. "The port's tokens appear in CPython's, in order"
    is true of far more than "CPython builds N more nodes", and a gate that stopped there
    would accept a port that had moved a node. This walks CPython's cone against the port's
    greedily, then REBUILDS the surviving list and compares it to the port's, so the
    returned list is a witness and not a guess.
    """
    ct, pt = cpy.split(","), port.split(",")
    out, dele, i, j = [], [], 0, 0
    while i < len(ct):
        if j < len(pt) and ct[i] == pt[j]:
            out.append(ct[i])
            j += 1
        else:
            dele.append(ct[i])
        i += 1
    return dele if j == len(pt) and out == pt else None


# THE SEARCH IS ONLY EXACT FOR A ROW SHORT ENOUGH TO RUN EVERY RUN. `witnesses` costs one
# O(len) rebuild per candidate. MEASURED per row: the seven rows under the cap cost 0.000 s IN
# TOTAL and the four over it cost 47.1 s between them (`lgq` 19.1, `lgs` 12.3, `lgr` 8.8,
# `lgt` 6.8) -- so the cap is not a share of the cost, it is ALL of it, and a gate must not pay
# 47 s for a printed observation. The cap is 200 TOKENS: `_lane()` hands back a STRING and
# `len()` of that is characters, so the row is split on `,` first -- MEASURED, reading it as
# tokens made the count 6 where it is 4, and a message that names the wrong unit is a lie.
# The cap covers `lg1 lg5 lga lgc lgd lge q5` and skips `lgq lgr lgs lgt`.
# THAT SKIP IS A LIMITATION OF THIS INSTRUMENT AND NOT A CLEAN BILL: nothing ON EVERY RUN says
# the four skipped rows' witness is unique. **IT IS NOW MEASURED OFF THE GATE AND IT HAS MOVED:
# ALL FOUR ADMIT ZERO ALTERNATIVE WITNESSES** (47.1 s, `lgq` 2500 tokens n=69 -> 0, `lgr` 2288
# n=70 -> 0, `lgs` 2459 n=63 -> 0, `lgt` 2248 n=64 -> 0). The previous revision of this comment
# said `lgr` and `lgq` each admit ONE; the `ADt` printer is what removed them, because each cast
# is a distinct STRING now and two adjacent ones are no longer interchangeable. So the eleven
# `PROMOTION` cones have a UNIQUE deletion witness each, 11 of 11, and what is still missing is
# only the EVERY-RUN half of it -- which the cap buys at 47 s a run and this gate will not pay.
# **THE `src`-ORDER PREMISE IS ALSO FALSE, AND IT IS MEASURED RATHER THAN ARGUED.** The recorded
# worry was that `OP/NSRC` "cannot pin order" because `src[0]` is read first. It pins order on
# every one of the 43 rows: the 26 exact rows by the lane DIFF, which is a line-for-line
# equality; the 17 divergences by VERBATIM PINS (`gatekit` asserts `want in raw[lane]` on the
# whole row string); and `classes_hold`'s `deleted()` is a SEQUENCE test that REBUILDS the
# surviving list and compares it -- MEASURED, swapping any two adjacent non-CAST tokens in a
# port line makes `deleted()` return `None` and the class check go RED, on `lg1`, `lgc`, `lgd`
# and `q2`. What `OP/NSRC` genuinely cannot carry is a node's dtype and a CONST's value, and
# those are named where they bite: the `q2` site above, and this file's own `q1` note.
SHORT_CONE = 200


def _cast_targets(tokens):
    """THE TARGET dtypes of a list of CAST tokens, as a Counter. The token is
    `OP/NSRC[TARGET]` where the arg is a DType, and the OP WORD is the test -- not
    `t == "CAST/1"`, which was the shape before the `ADt` was printed and which would now
    match nothing at all."""
    return Counter(t.split("[", 1)[1][:-1] for t in tokens)


def _is_cast(t):
    return t.split("/", 1)[0] == "CAST"


def witnesses(cpy, port, n):
    """HOW MANY SIZE-`n` CAST DELETIONS REPRODUCE `port`; `-1` when it is not a deletion.

    `deleted()` PROVES THE PORT IS A DELETION. It does not prove WHICH entries were deleted,
    and two ADJACENT casts were interchangeable to a left-greedy walk when `CAST/1` was ONE
    TOKEN. The `ADt` makes each of them a different string, so this search is the
    MEASUREMENT of that claim rather than an assertion of it. MEASURED over the seven rows
    under `SHORT_CONE` after the repair: `lg1` admits ZERO alternative witnesses, where before
    it admitted exactly one -- and the greedy walk demonstrably kept the WRONG node, because
    CPython's `lg1` cone carries `CAST(i32->i64)` at index 1 AND `CAST(weakint->i32)` at
    index 2 and the port's surviving node is the second (its own `dd_const.int`,
    dtype.bend:333). Printed, NOT FATAL: the class holds on every witness that exists.
    """
    ct, pt = cpy.split(","), port.split(",")
    d, i, j = [], 0, 0
    while i < len(ct):
        if j < len(pt) and ct[i] == pt[j]:
            j += 1
        else:
            d.append(i)
        i += 1
    if j != len(pt) or len(d) != n:
        return -1
    s, alt = set(d), 0
    for p in (k for k, t in enumerate(ct) if _is_cast(t) and k not in s):
        for g in d:
            if [t for k, t in enumerate(ct) if k not in (s - {g}) | {p}] == pt:
                alt += 1
                break
    return alt


def classes_hold() -> bool:
    """EVERY CLASS'S MEASURED CLAIM, CHECKED ON THE LANES THIS RUN JUST PROMOTED.

    The pins already make a moved row RED; this says WHY each row is allowed to differ, in
    the terms the class is defined by, so a divergence that keeps its text cannot silently
    change what it is. A gate that only pins differences is a gate that has forgotten what
    it is pinning.
    """
    port, cpy = _lane("bd.out"), _lane("py.rows")
    if port is None or cpy is None:
        print("  classes_hold: the promoted lanes are not there")
        return False
    ok = True
    for r, n in PROMOTION_CASTS.items():
        dele = deleted(cpy[r], port[r])
        if dele is None or len(dele) != n or not all(_is_cast(t) for t in dele):
            print(f"  {r} is not CPython minus exactly {n} CAST entries "
                  f"({'not a deletion' if dele is None else len(dele)})")
            ok = False
            continue
        got = _cast_targets(dele)
        if got != Counter(PROMOTION_TARGETS[r]):
            print(f"  {r}: the {n} deleted casts target {dict(sorted(got.items()))} and the "
                  f"class says {dict(sorted(PROMOTION_TARGETS[r].items()))} -- a moved target "
                  f"is the finding this class exists to catch")
            ok = False
            continue
        if len(cpy[r].split(",")) <= SHORT_CONE:
            alt = witnesses(cpy[r], port[r], n)
            if alt > 0:
                print(f"  {r}: {alt} alternative deletion witnesses -- the class is a COUNT "
                      f"plus a TARGET MULTISET for this row, not an identity")
    skipped = sum(len(cpy[r].split(",")) > SHORT_CONE for r in PROMOTION_CASTS)
    if skipped:
        print(f"  witnesses(): {skipped} of {len(PROMOTION_CASTS)} PROMOTION cones are over "
              f"{SHORT_CONE} tokens and were NOT searched -- their witness is unproven unique")
    for r in WALL:
        if (cpy[r], port[r]) != ("raise=NotImplementedError", "refused:unported"):
            print(f"  {r}: cpy={cpy[r]!r} port={port[r]!r}, not the declared refusal pair")
            ok = False
    for r in UNBUILT:
        if port[r] != "refused:unported" or cpy[r].split(",")[0] != "WHERE/3":
            print(f"  {r}: port={port[r]!r}, cpy starts {cpy[r].split(',')[0]!r}")
            ok = False
    for r in FINDING:
        if deleted(cpy[r], port[r]) is not None:
            print(f"  {r} is now a DELETION of CPython's cone -- the finding is fixed or the"
                  f" fixture moved; drop it from FINDING and re-pin, do not leave it here")
            ok = False
        extra = set(port[r].split(",")) - set(cpy[r].split(","))
        if extra:
            print(f"  {r}: the port holds {sorted(extra)} and CPython does not")
            ok = False
    return ok


def no_noop_bottom() -> bool:
    """`NOOP` IS `Arena.bottom()`, SO A `NOOP` IN A CONE IS AN OUT-OF-RANGE INDEX.

    Checked off BOTH PORT LANES' own output and not a re-derivation: the property is about
    what the port PRINTED. This gate's own first draft read six `q` cones off the arena it
    handed in instead of the one the answer came back in and printed `NOOP/0` for all six --
    defect class (a), the stale-arena self-loop, caught by the assertion rather than by a
    diff against CPython, because CPython has no `NOOP` to disagree with.
    """
    for lane in ("bd.out", "bn.out"):
        f = ART / lane
        if not f.is_file():
            return False
        for l in f.read_text().splitlines():
            if "=" in l and "NOOP" in l.split("=", 1)[1]:
                print(f"  {lane}: {l.split('=', 1)[0]} reads the BOTTOM")
                return False
    return True


if "--refresh" in sys.argv:
    sys.exit(refresh())
if DIVERGES is None:
    print(f"decomp_graph_census-gate: REFUSED, NOT A VERDICT: {WHY}", file=sys.stderr)
    sys.exit(REFUSED)

GATE = Gate(
    "decomp_graph_census-gate",
    bend="decomp_graph_census.bend",
    oracle="decomp_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


if __name__ == "__main__":
    n_cast = sum(PROMOTION_CASTS.values())
    sys.exit(gate(GATE, f"decomp_graph_census-gate: {len(ROWS)} rows (30 pool-fed l2i arms + 1 l2i cell "
                        f"l2i.pick does not list + 3 l2i.const arms + 2 unpack32 fixtures + 7 f2f "
                        f"pairs), 3 lanes, {len(ROWS) - len(DIVERGES)} deep cones match "
                        f"CPython byte-for-byte and {len(DIVERGING)} are DECLARED "
                        f"divergences -- {len(PROMOTION)} are the PROMOTION CASTS "
                        f"`ElementwiseMixin._broadcasted`'s `promote` mints "
                        f"(mixin/elementwise.py:24-32) and decomp's raw `O.UOp.alu` never does "
                        f"({n_cast} CAST entries, each verified by DELETING them from "
                        f"CPython's cone, rebuilding the port's, and checking the TARGET "
                        f"dtype each one was cast to), {len(WALL)} are refusals, "
                        f"{len(UNBUILT)} rows are the ONE unbuilt float-target CAST arm at two "
                        f"target widths, and q2/q3 ARE "
                        f"FINDINGS: f2f's narrowing arm is not a deletion of CPython's cone; no "
                        f"lane answers the NOOP bottom",
                  checks=lambda: classes_hold() and no_noop_bottom()))

# ===========================================================================
# WHAT THE (b) TRIAGE FOUND AT THREE `OpsCAST{}` SITES, AND WHY NONE OF THE THREE IS A
# CARVE-OUT. A tree-wide `grep -c OpsCAST` is NOT this answer -- most of its ~100 hits are
# pattern-matcher arms and rewrite rules where an identity fold would be WRONG -- so each
# site was read for its TARGET dtype against its SOURCE's. MEASURED in CPython with
# `UOp.const(b, dt)`, which `ops.py:634` says is `UOp(CONST, arg=dt.const(b)).cast(dt)`
# and "folds away at exactly the dtypes a CONST derives (bool/weakint/weakfloat)":
#
#   op.bend:209  `dc_cast(x, dt)` -- NOT FOLDABLE. Its four call sites are `dc_tf_half`
#                (:319, :320) and `dc_tf_join` (:326, :327), all inside `threefry2x32`
#                (op.py:40-41, :50), and every one of them casts BETWEEN two concrete
#                widths: `x.cast(uint32)` on a uint64, `(x >> 32).cast(uint32)`,
#                `xr[1].cast(uint64)` and `xr[0].cast(uint64)` on uint32s. MEASURED:
#                `param(u32).cast(u32).op` is `PARAM`, and none of the four sites is that
#                shape. This census does not drive `threefry2x32` at all, and the fold it
#                would need is not the one that is there.
#
#   dtype.bend:362  `dd_cf(v, dt)` -- NOT FOLDABLE. Its two callers (:1556, :1557) pass
#                `fr`, the SOURCE float of an `f2f` conversion, and every `f2f_dt` value
#                is a concrete width. MEASURED: `UOp.const(1.0, f32/f64/f16)` is a CAST
#                with one src -- the same node the port builds. Only `weakfloat` folds,
#                and `dd_cf` is never asked for it.
#
#   dtype.bend:333  `dd_const.int(v, dt)` -- A REAL FINDING OF CLASS (b), AND THIS CENSUS
#                CANNOT SEE IT. MEASURED: `UOp.const(0, int32/uint32/uint64/int64)` is a
#                CAST with one src -- the same node the port builds -- and
#                `UOp.const(0, bool)` and `UOp.const(0, weakint)` are a BARE `CONST`.
#                `dd_clike(ar, v, dt)` forwards its dtype unchanged (:369), and
#                `l2i_cast0.sgn` (:581) calls it with `xdt`, the SOURCE dtype -- and the
#                `lg4` fixture is `l2i(CAST, int64, <a bool word>, 2)`, so `l2i_cast0`
#                (:595-603) reaches `dd_const.int(..., S.boolean())` and mints the identity
#                CAST CPython folds away.
#                WHY IT IS INVISIBLE, and this is the part that matters: dtype.py:31 is
#                `if x.dtype is dtypes.bool or x.dtype in dtypes.uints: return lo,
#                lo.const_like(0)`, so CPython RETURNS BEFORE building dtype.py:32's
#                `(x < x.const_like(0)).where(...)`. The port computes `+s =
#                l2i_cast0.sgn(...)` UNCONDITIONALLY (:602) and then discards it in
#                `l2i_cast0.pick` (:588). Every node that branch mints is DEAD, and `lg4`'s
#                row matches CPython byte-for-byte -- which is the measurement that it is
#                dead rather than merely small. REACHABILITY IS FROM READING THE PORT, NOT
#                FROM A RUN; THE FOLD IS MEASURED.
#                `tinybendygrad/codegen/decomp/` IS LEFT BYTE-IDENTICAL. The folding
#                spelling is `W.wk_cast_at(F.folded(ar), ...)` (`mixin/dtype.bend:342`),
#                which needs a fold context, and it is worth less than it looks until
#                `l2i_cast0` stops building the branch it throws away.
# ===========================================================================
# THE TWO FINDINGS. `tinybendygrad/codegen/decomp/dtype.bend` IS LEFT BYTE-IDENTICAL;
# these are REPORTED, not fixed.
#
# FINDING 1, 2 -- `f2f`'s NARROWING ARM IS NOT A DELETION OF CPython's CONE, AND THE SITE IS
# NOW LOCATED TO TWO LINES. `q2` is `f2f(f32 -> fp8e4m3)` and `q3` is `f2f(f32 -> fp8e5m2)`,
# dtype.py:115-124, both DOWN. THE MISSING MULTISET IS IDENTICAL ON BOTH ROWS, so the
# localisation is done once and not twice: `CONST/0` x1, `CAST/1[u8]` x1, `OR/2` x2,
# `CAST/1[u32]` x1, and the port's multiset is a strict SUBSET of CPython's on both rows. THE
# PORT'S WALK IS NOT A SUBSEQUENCE OF CPython'S, so this is NOT a dedup artefact -- and the test
# discriminates, because `lgw`/`lgx` (which differ only by an order swap) DO pass it.
#
#   DEFECT 1, ONE TOKEN: `tinybendygrad/codegen/decomp/dtype.bend:1909`. `f2f.narrow` computes
#   `+nn = f2f.down.npat(...)` -- dtype.py:121's `nan`, CAST to `f2f_dt[to]` -- at :1907, and then
#   calls `f2f.down.tail(..., ii, nm, ts, to)` with **`nm`**, the `nan_MANTISSA`. `nn` is DEAD from
#   :1908 on, and `f2f.down.ocp`'s final line (:1877) puts `nm` in the `true` branch of
#   `is_nan.where(...)` where dtype.py:124 puts `nan`. THE PORT'S OWN WIDENING ARM HAS THE
#   PARAMETER: `f2f.ocp` (:1730) takes BOTH `+nm` and `+nn` and `f2f.up.tail` (:1740) threads `nn`
#   through, so the narrowing arm LOST a parameter the widening arm kept. `f2f.down.fnuz` (:1864)
#   does not need `nan` at all (dtype.py:123 returns `is_nan.where(shl(1, ts - 1), ...)`), which is
#   WHY `q5` IS A `PROMOTION` ROW AND NOT A FINDING -- the classification already said so before
#   the site was located.
#     MEASURED, AND IT IS NOT A SHAPE CLAIM. fp8e4m3's ONE NaN encoding is `0x7F` (MEASURED: the
#     only pattern in 0..127 satisfying the S.1111.111 rule); dtype.py:121's `nan` is
#     `sign | nan_mantissa | shl(shl(1, te) - 1, tm)` = `sign | 7 | 120` = **127 = the NaN**, and
#     the port's true branch is `nan_mantissa` = **7 = 0b00000111, WHICH IS NOT NaN**. So
#     `f2f(NaN, f32, fp8e4m3)` returns a small positive number where tinygrad returns NaN. That is
#     a THIRD WITNESS -- dtype.py's own constants and the fp8 NaN rule -- and not the port re-run.
#     MEASURED FIX, OFF-GATE, ON A COPY: the single substitution `nm` -> `nn` at :1909 moves
#     **2 OF 42 ROWS, `q2` AND `q3`, AND NOTHING ELSE**, and it removes FOUR of the five missing
#     tokens -- `q2` goes 52 -> 56 tokens against CPython's 57 and `q3` 53 -> 57 against 58, and
#     both cpy-only multisets collapse from five tokens to `{CAST/1[u32]: 1}`.
#
#   DEFECT 2, ONE NODE: `dtype.bend:1467`, `rne.go`'s `+g = dd_or(..., O.Found.i(e), O.Found.i(f))`.
#   `e` is dtype.py:99's `(v & ((1 << (s - 1)) - 1)).ne(0)`, a BOOL; `f` is `shr(v, s) & 1`; the OR
#   makes `e` the u32 one, which is `ElementwiseMixin._broadcasted`'s `promote` minting
#   `CAST/1[u32]`. MEASURED OFF `q2`'s CPython cone WITH THE FIELDS THE TOKEN CANNOT CARRY (a
# census token is `OP/NSRC[TARGET]`: no child's dtype, no CONST's value), node 49 is
# `CAST/1[u32]` over node 50 `CMPNE/2` -- that promotion, and the only `CAST/1[u32]` in the cone.
# So the LAST missing token is the SAME missing promotion the eleven `PROMOTION` rows record,
# reached through `f2f`'s narrowing arm and `rne` instead of `l2i`.
#
#   AND WHAT BOTH FIXES WOULD DO TO THE CLASSES, MEASURED SO IT IS NOT A GUESS: with defect 1
#   fixed, `deleted()` answers `['CAST/1[u32]']` on BOTH rows -- a one-CAST deletion. Fix defect 2
#   as well and `q2`/`q3` join the eleven `PROMOTION` rows at target `u32 x1` each and
#   **`FINDING` IS EMPTY**, which by this file's own rule means dropping it from the class tuples,
#   moving its story into the pins header and fixing the pin COUNT assertions in FOUR places.
#   NEITHER FIX IS LANDED: `tinybendygrad/codegen/decomp/` stays BYTE-IDENTICAL (this file's
#   standing policy), and half a fix makes `classes_hold` red on "q2 is now a DELETION ... drop it
#   from FINDING" -- a RED run, not a partial green one.
#
# WHAT WAS RULED OUT, BY MEASUREMENT RATHER THAN BY ARGUMENT:
#   * NOT THE ORACLE'S FIXTURE. This lane used to hand `f2f` a `float32` PARAM for every
#     row, which is neither `fr` nor `f2f_dt[fr]`, and that mistake accounted for two of
#     the three divergences this file used to carry: `q1` (a `CONST/0`) and `q5` (which
#     used to look like an extra `BITCAST/1` and is, with the fixture right, a PROMOTION
#     row like the ten `l2i` ones). MEASURED: building the fixture at `f2f_dt[fr]` -- the
#     dtype dtype.py:142 and :197 both pass, and the dtype `f2f.one` (:3043-3047) says so
#     in its own warning -- takes the row count from 17 divergences to 16 and `q1` to an
#     exact match. The BITCAST that was declared a port defect was the ORACLE's, folding
#     away in `mixin/dtype.py:53` because the lane's own `v` was already at `fr`. THAT IS
#     THE `tn_bitwise_not` POST-MORTEM A SECOND TIME, and it is why `f2f`'s fixture dtype
#     is a named, argued field of the oracle rather than a convenience.
#   * NOT THE PROMOTION CASTS. Those 11 rows are VERIFIED deletion-only by `deleted()`,
#     which rebuilds the surviving list; `q2`/`q3` fail that test, so the missing entries
#     are not `CAST/1` and the mechanism is a different one. `q1 q4 q7` are byte-identical,
#     which is what isolates the difference to the two NON-fnuz fp8 NARROWING targets --
#     `q5`, the fnuz one, took the fixture fix and now takes a promotion CAST.
#   * NOT A STALE ARENA. There is no `NOOP` in either row and no self-referential index;
#     `no_noop_bottom` is what says so on every run.
#
# WHAT THE CENSUS CANNOT SEE, NAMED BECAUSE IT IS WHAT LET THE ORACLE FIXTURE DEFECT LIVE
# AS A FINDING FOR AS LONG AS IT DID. A CONST's VALUE and DTYPE are in no node shape, so
# `sig` prints `CONST/0` for every constant whatever it holds. MEASURED on `q1`, whose row
# is byte-identical on both sides while its constants are not: CPython's cone carries
# `CONST(True)` at index 17 where the port's arena reads `C(1)`, and CPython carries a
# weakfloat `127.0` at index 14 AND a weakint `127` at index 21 where the port holds ONE
# `C(127)` serving both roles. `dtype.bend`'s own gate prints those constants as a `k=`
# row; this lane does not, and adding it is the next thing that would make a wrong constant
# visible here.
# ==========================================================================
# THE PROMOTION CLASS, GIVEN A MEASUREMENT INSTEAD OF A NAME. `classes_hold()` asserts
# "CPython minus exactly N CAST entries", AND A CAST'S TARGET DTYPE IS NOW IN THE TOKEN --
# `sig` printed `CAST/1` for every cast until this session, so the class could not tell a
# `bool->u32` promotion from a `f32->i32` narrowing, which is the same blind spot the block
# above names for a CONST's value and had never been named for a CAST's target.
# `PROMOTION_TARGETS` is that, asserted on every run.
#
# 282 DELETED ENTRIES, AND THE MEASURED TARGET MULTISET IS `u32 263, i64 17, i32 2`:
#   263  bool -> u32   `_broadcasted`'s `promote` over a CMPLT beside a word
#    17  ->  i64       3 on lgq, 3 on lgr, 5 on lge, 4 on lg1, 2 on lga
#     2  ->  i32       1 on lg5, 1 on lge
# AND IT IS NOT ALL THE SAME MECHANISM. THE PREVIOUS REVISION OF THIS BLOCK NAMED SIX
# `src->target` PAIRS AND READ `u32 263, i64 14, i32 5`. THREE ENTRIES IT CALLED `i32` ARE
# `i64`. That table needed each NODE's dtype, which NO row carries and which this gate has
# never read, so it could not have been checked; this one can be, every run. Its one checkable
# line, `3 weakint -> i32 (over CONST/0) ** NOT _broadcasted **`, was also WRONG IN A WAY
# THAT MATTERS: `lg1`'s surviving port cast is `CAST/1[i32]` and its four deleted ones are all
# `i64`, so that line counted the port's OWN node as one of the 282 the class deletes.
#
# `witnesses()` IS THE OTHER THING THE `ADt` BOUGHT, and it is a RESOLUTION rather than a
# capability: `lg1` admitted exactly one alternative deletion witness while every cast was the
# same token, and the greedy walk demonstrably kept the WRONG node -- CPython's `lg1` cone
# carries `CAST(i32->i64)` at index 1 AND `CAST(weakint->i32)` at index 2. MEASURED after the
# repair: ZERO alternative witnesses over the seven cones under `SHORT_CONE`, **and now over the
# four OVER it as well -- 11 of 11 -- re-measured off the gate at 47.1 s.**
#
# WHAT IS STILL NOT IN THE ROW, so the "not all the same mechanism" claim above is bounded:
# the SOURCE half of each pair. `PROMOTION_TARGETS` says what each deleted cast was cast TO;
# nothing here says what it was cast FROM, because `sig` prints a node's op, arity and CAST
# argument and not its dtype. `lge q5 lgc lgd` are dtype-identical on every kept node; `lg1`
# keeps 3 of 13 at a DIFFERENT dtype and `lg5` 1 of 14, so the port computes those
# intermediates NARROWER than CPython does, in exactly the MUL/CDIV/CMOD decompositions where
# intermediate width is load-bearing (dtype.py:55 sums three 32-bit products into the high
# word). WHETHER THAT IS A DEFECT IS NOT ANSWERABLE HERE, and saying so is the finding: this
# census compares SHAPES, CAST TARGETS and no VALUES. A numeric oracle would settle it; this
# gate has none.
# ===========================================================================
# TWO ARMS NO FIXTURE CAN REACH, MEASURED, AND ONE OF THEM IS WHY `uq` EXISTS. `A5` and `A13`
# of `gates/decomp_graph_census-mutate.py` BOTH MOVED 0 OF 38 ROWS WHEN THEY RAN, and the two
# answers are DIFFERENT and the difference is the point.
#
# `A13` -- `unpack32.bc`'s BITCAST `ADt` (dtype.bend:591) -- WAS A MISSING FIXTURE, and `uq` is
# it. The single `unpack32` row passed `xdt = u32`, the fold `O.eq_dt(xdt, S.uint32())` fired, and
# `up` is `AND/2,PARAM/0,CONST/0,FLOODIV/2,CONST/0` with NO BITCAST AT ALL -- so the node
# `ops.py:13` builds was in no row, which is the hole `dtype.bend:2824-2830` records for
# `l2i_cast3.bitc` and calls "live code with zero coverage". `uq` reads the pool's `i32` word at
# offset 4, the fold does not fire, the row is an EXACT MATCH on both sides, and `A13` NOW MOVES
# ONE ROW: `uq`. It is the `de` SHAPE in this file's own vocabulary -- a REQUESTED dtype that is
# not the receiver's, so the fold test is false and the `ADt` is read.
#
# `A5` -- `dd_cast_bool`'s `True` arm (dtype.bend:454) -- IS A DEAD ARM, AND THE QUANTITY IS
# MEASURED OVER THE WHOLE INPUT SPACE AND NOT ARGUED. `grep -n dd_cast_bool tinybendygrad/` is
# ONE call site, :626, inside `l2i_cast1.quo`, whose only caller is `l2i_cast1` (:641), whose
# only caller is `l2i_cast.got`'s `case 1` (:665). So the arm fires iff some cell of `l2i_cast`'s
# `(dt, xdt)` product has `sel == 1` AND `dd_is_bool(xdt)`. A CONSTRUCTION THAT PRINTS SAYS
# NOTHING ABOUT THAT, so the arm was never driven and the census's own rows cannot witness it
# either way. MEASURED, over the 400 cells of the port's own `Dt` product (DISCOVERED from
# `tinybendygrad/LAWS/spec.bend`'s `def <n>() -> Dt:` lines -- 20 distinct values, one alias
# `index() == weakint()` -- by `.agents/slop/decomppromo/dtdt.py --emit`, whose generated fixture
# `ax_boolarm.bend` builds NO NODE and only asks the selector):
#     cells with `sel == 1`                     24 of 400
#     cells with `dd_is_bool(xdt)`              20 of 400  (every one has `xdt = bool`)
#     the `sel` values those 20 cells carry     {0: 3, 2: 7, 3: 10}   -- NEVER 1
#     `sel == 1` AND `dd_is_bool(xdt)`           0 of 400
# `sel == 1` requires `dd_cast_sel`'s `lng == True` arm (dtype.bend:567-570), where
# `Bool.pick(U32, srcfl, 1, 0)` returns 1 only when `srcfl` -- `dd_is_float(xdt)` -- is TRUE,
# and `Cls.is_float` (spec.bend:134-140) and `Cls.is_bool` (:147-150) are DISJOINT `match`es over
# the SEVEN-member `Cls` datatype (spec.bend:67-74), so the two cannot both hold at one `xdt`.
# CPython AGREES FROM THE OTHER SIDE: dtype.py:33's arm is `dt in (long, ulong)` AFTER
# dtype.py:28's `uops[0].dtype not in dtypes.floats`, so `uops[0]` is always a float and
# `(uops[0] / 2**32)` has no bool operand for an `elementwise.py` `default_float` promotion to
# convert. **THE PORT'S COMMENT AT dtype.bend:644-648 -- "after `a.cast(default_float)` when `a`
# is a bool" -- NAMES A TRIGGER ITS OWN SELECTOR HAS ALREADY EXCLUDED**, and `:647` is the line
# that says so. Deleting the arm is a PORT change and is not made here. A5 is therefore a DEAD
# MUTATION BY REACHABILITY, not by coverage, and the two are different answers to different
# questions: `A13` moved a row because a fixture was missing, `A5` moves none because no cell of
# the input space can select it.
# ===========================================================================
# `de` IS NOT IN THIS GATE'S CONE, MEASURED, AND THAT IS WHY THE RECORDED FINDING ABOUT IT
# CANNOT BE CLOSED HERE. `mixin/creation.bend:242-245`'s `cr_const_of` hands ONE value `de` to
# the fold test's right-hand side and the CAST's `ADt` argument, and
# `crp_graph_census-mutate.py` (`51cceacd7`) measured that breaking only the second moved 0 of
# 207 rows, because nothing rendered a CAST's argument. THAT CAUSE IS FIXED HERE -- this
# census's printer now renders it -- but the COUPING is not on this gate's path at all:
# `codegen/decomp/dtype.bend` imports `Base`, `helpers.bend`, `LAWS/spec.bend`, `uop/ops.bend`,
# `./op.bend` and `./transcendental.bend` (dtype.bend:182-187) and NOT `tensor.bend` and NOT
# `mixin/creation.bend`; the CONSTs in these cones are minted by `uop/ops.bend:2961
# def UOp.const(ar, +v: Const)`, WHICH TAKES NO DTYPE, because the `.cast(dtype)` half of
# `ops.py:640` is a `TODO(p3)` at ops.bend:5084. MEASURED, the `ADt` this gate now prints is
# minted by `decomp`'s OWN helpers -- `dd_const.int` (dtype.bend:333), `dd_cf` (:362),
# `dd_cast_fold` (:449), `dd_cast_bool` (:454), `dd_bcast` (:387) and `op.bend:208 dc_cast` --
# and `decomp`'s own copy of the `de` shape is `dtype.bend:593,637`:
#     +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))
#            ^ the CAST's ADt                  ^ the fold test
# `gates/decomp_graph_census-mutate.py` A1 and A2 break those two uses apart and report rows
# moved. `crp_graph_census` is the gate that reaches `de`, it is not this gate, and closing
# the finding there is that gate's unit's work.
#
# THE ROW THE FINDING ASKSED FOR CANNOT EXIST, AND THAT IS MEASURED IN CPYTHON OVER TWELVE
# DTYPES. The ask was "a CONST that is `Invalid` and a requested dtype that is not the derived
# one, so `de != dt`, the fold does NOT fire, and a CAST with a load-bearing arg IS minted".
# `de != dt` HOLDS IFF `b is Invalid` (ops.py:630), and THEN `de = from_py(Invalid) = bool = c0`
# (dtype.py:102), so `eq_dt(c0, de)` is TRUE and the fold fires. MEASURED,
# `UOp.const(Invalid, dt)` is a BARE `CONST/0` with no cast at bool, uint8, int32, uint32, int64,
# float32, float64, half, bfloat16, weakint, weakfloat and void.
# AND THE PREMISE "EVERY ROW HAS `de == dt`, SO EVEN A PERFECT PRINTER SEES NOTHING" IS FALSE FOR
# THIS POPULATION: A3 (every `op.bend:208 dc_cast` `ADt` wrong) MOVES 15 ROWS and A1 MOVES 5,
# both with 0 under the printer as it was.
#
# THE THREE ARMS A POOL-FED POPULATION CANNOT SEE ARE NOW ROWS, AND THEY ARE ALL EXACT MATCHES.
# `l2i.pick`'s cases 28/29/30 mint their CONST OUTSIDE `l2i` (`l2i.const`, dtype.bend:2773, over
# `dd_const.int` at `xdt`) and hand it in, so a population rule keyed on "ARMS THAT READ THE WORD
# POOL" cannot see them -- the same class as `amd_dsl_census`'s `VOP2_FIELDS` having no `src2`.
# **`dc_lc1` is the template and `ROWS` carries them: 39 -> 42, 23 -> 26 exact matches, and the
# SAME 16 declared divergences. NOTHING WAS ADDED TO `DIVERGING`, SO NO NEW CLASS WAS NEEDED.**
#    lgv  CAST/1[i32],CAST/1[u32],CONST/0,CAST/1[i32]   byte-identical, both lanes
#    lgw  CAST/1[u32],CONST/0]                          byte-identical, both lanes
#    lgx  CAST/1[u32],CONST/0,CAST/1[u32],CONST/0]      byte-identical, both lanes
#
# THIS REFUTES THE PREVIOUS REVISION OF THIS FOOTER, WHICH SAID ALL THREE DIVERGED AND NAMED THE
# PORT'S HALF EXACTLY RIGHT. Its CPython half is `CAST/1[i32],CONST/0,WHERE/3,CMPLT/2,
# CAST/1[i32],CONST/0` for `lgv`, and that string is REPRODUCIBLE -- from
# `l2i(Ops.CAST, dtypes.int64, UOp.const(0, dtypes.INT32))`, an `i32` SOURCE, where dtype.py:31's
# `x.dtype in dtypes.uints` early return does not fire and the sign-extension cone at :32 is
# built. `l2i.const` passes `S.uint32()` (dtype.bend:2812/:2816/:2817) and `UOp.const(0, u32)`
# takes dtype.py:31, so there is no sign extension to disagree about. **THE CPython LANE WAS DRIVEN
# ON A DIFFERENT `xdt` FROM THE PORT LANE.** That is the `tn_bitwise_not` post-mortem a FOURTH
# time and it happened in this file's PROSE: a lane that could not answer was reported as one
# that had, and it would have cost TWO NEW CLASSES. THE THREE ROWS ARE ALSO WORTH HAVING for what
# they say about `de`: the CONST is already AT `xdt`, so `dd_const.int`'s CAST at :333 is not
# folded and the row carries `CAST/1[u32]` -- a target EQUAL to its source, the mirror image of
# `uq`'s target that is not. `lgw`/`lgx` are the pair that separates an order-keeping walker
# from a multiset: same two words, `lgx`'s cone is in the other order.
# ===========================================================================
# `dd_is_long` IS `bits == 64` AND CPYTHON'S GUARD IS A MEMBERSHIP TEST, SO `double` IS ADMITTED
# TO A `LONG` ARM IT NEVER REACHED. NEW, AND NOT IN ANY PIN. `dd_is_long` (dtype.bend:229-230) is
# `U32.is_eq(bits, 64)` and dtype.py:28/:33 both read `dt in (dtypes.long, dtypes.ulong)` -- a
# two-element SET, not a width. MEASURED over the WHOLE product of the port's own `Dt`
# population, DISCOVERED from `tinybendygrad/LAWS/spec.bend`'s own `def <n>() -> Dt:` lines (20
# distinct values plus one alias `index() == weakint()`), i.e. 400 cells:
#     `bits == 64`   answers True for {double, int64, uint64}  -- 3 of 20
#     `dt in (long, ulong)`  answers True for {int64, uint64}   -- 2 of 20
# `double` IS 64 bits wide and is NOT `long`.
#
# THE PREVIOUS REVISION OF THIS BLOCK NAMED THE CONSEQUENCE WRONG, AND A WRONG REASON IS WORSE
# THAN NONE, SO THE CORRECTION IS THE POINT. IT SAID: "the 20 cells with `dt == double` -- 12 at
# `sel == 0` and 8 at `sel == 1` -- ARE MISATTRIBUTED: they are not a second missing arm, they
# are `lgu`'s missing arm reached through a wrong guard ... THE SELECTOR MUST BE FIXED FIRST",
# and it named `l2i_cast.got`'s `case 2: None{}` (:667) as the blocker. **THE COUNTS ARE RIGHT
# AND THE INFERENCE IS WRONG. `sel` IS NOT WHAT DECIDES, AND IT IS NOW MEASURED THAT IT IS NOT,
# BY TWO SAME-`sel` OPPOSITE-ANSWER PAIRS. THE TWO ANSWERS ARE **ON-GATE ROWS** (`lg5` and `lgv`
# against `lgz`); ONLY THE TWO NUMBERS PER CELL ARE OFF-GATE
# (`.agents/slop/l2ipool/probe65.bend` prints `sel`/`is_long`/`srcfl`/`flt`/`l2i_dt` per cell,
# and `.agents/slop/l2ipool/probe64.bend` drives the eighth cell):
#     lg5  i64 <- f32   sel=1  l2i_dt=i32   -> BUILDS `l2i_cast1`, 14 port tokens
#     lgz  f64 <- f32   sel=1  l2i_dt=NONE  -> REFUSES
#     lgv  i64 <- u32   sel=0  l2i_dt=i32   -> BUILDS `l2i_cast0`
#     f64 <- u32        sel=0  l2i_dt=NONE  -> REFUSES
# Each pair differs in ONE field of `dt` -- its CLASS at 64 bits -- and agrees in the selector.
# SO ALL 20 `dt == double` CELLS REFUSE, NONE OF THEM REACHES `l2i_cast0` OR `l2i_cast1`, AND
# FIXING `dd_is_long` CHANGES NOTHING OBSERVABLE: `l2i_cast.ldt` (:680-683) routes `case 0`,
# `case 1` AND `case 2` all through `l2i_cast.wide` (:675-678), whose `match m` REFUSES ON
# `l2i_dt(dt) == None` -- ONE LINE BEFORE `l2i_cast.got` is ever entered, and therefore before
# `case 2: None{}` (:667) can be the blocker the previous revision named. `l2i_dt` (:271-282) is
# CPython's `{long: int, ulong: uint}` and admits `CSint`/`CUint` ONLY, so a 64-bit `CFloat` is
# a `KeyError` there for `f32` and `f64` alike.
#
# WHAT ACTUALLY HAS TO CHANGE, AND IT IS NOT LANDED. `l2i_cast.ldt` ALREADY HAS THE SHAPE THAT
# WOULD DO IT: `case 3` (:682) BYPASSES the `l2i_dt` guard entirely, which is why dtype.py:39's
# bitcast arm is reachable at `l2i_dt(dt) == None`. A `case 2:` at that same level is what f64
# needs -- and it needs a BODY, because `l2i_cast2` does not exist, so it is a second change and
# not a one-line edit. NEITHER IS LANDED HERE, FOR THE REASON THIS FILE ALREADY RECORDS TWICE:
# a half-fix that makes `classes_hold` RED ("`lgz` is now a DELETION ... drop it from UNBUILT")
# is not a half-fix, it is a new finding. `lgz` IS PINNED AS A REFUSAL INSTEAD, and it is LIVE:
# `gates/decomp_graph_census-mutate.py` A14 teaches `l2i_dt` a `CFloat` entry and MEASURES that
# exactly ONE row moves -- `lgz`, `refused:unported` becoming a 14-token `l2i_cast1` cone.
#
# Blast radius, measured: `grep -n dd_is_long tinybendygrad/` returns ONE non-comment site, :686,
# so `l2i_cast` is the whole of it -- AND `no l2i.pick arm has double for a TARGET, which is why
# 42 ROWS COULD NOT SEE IT. `lgz` IS THAT ROW: 43, `dc_l2i_pick`'s `case 29`, and the third member
# of the pool-fed-blindness class this file has now named three times.
# ===========================================================================
