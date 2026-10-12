#!/usr/bin/env python3
"""decomp_graph_census-gate.py -- A GRAPH CENSUS over the graph-BUILDING half of
`tinybendygrad/codegen/decomp/dtype.bend`, and the FIRST gate that layer has ever had.

    .venv/bin/python gates/decomp_graph_census-gate.py
    .venv/bin/python gates/decomp_graph_census-gate.py --refresh   # rewrites the pins file

38 ROWS, THREE LANES, 22 EXACT MATCHES AND 16 DECLARED DIVERGENCES -- 11 PROMOTION, 2
REFUSALS, 1 UNBUILT ARM AND 2 FINDINGS.

`dtype.bend` ships its OWN 208-row `gate()` (dtype.bend:3068), which prints each fixture's
tree, its intern count, its DEEP CONE and its constants. What was ungated was the GRAPH
AGAINST CPYTHON: nothing compared a cone to the one dtype.py builds, so a port that built a
different node agreed with itself. `op.bend` ships a 146-row `gate()` (:2171) with the same
gap. This gate is the CPython lane for the 38 of those rows that are a GRAPH.

THE POPULATION IS THE PORT'S OWN FIXTURE SET, AND THE RULE IS NOT THE `*_table` RULE.
`gates/rng_graph_census.bend`'s row is a (TABLE, NODE) pair whose TABLE axis is
`grep -c '^def [a-z]*_table'`. MEASURED: that count is **0** in every file of
`tinybendygrad/codegen/decomp/` -- `op.bend`, `dtype.bend`, `transcendental.bend`,
`transcendental_f32.bend`. decomp is a graph BUILDER, not a rewriter, so it has no dispatch
tables and the rng rule has nothing to range over; the substitute axis is the FIXTURE, and
the fixture population is the port's own `l2i.pick` (:2780, 33 arms), `dd_cmx.pick` (:2931,
8) and `f2f.pick` (:3053, 7). Thirty of `l2i.pick`'s arms read the word pool and three mint
a CONST, so the pool-fed set is 30 + 1 `unpack32` + 7 `f2f` = **38**. BOTH BEND LANES EMIT ALL
38 including refusals, so the two counts agree BY CONSTRUCTION and no exclusion list is
needed to make them meet. THE FIXTURE TABLE IS MIRRORED, NOT DISCOVERED -- the port's arms
and the oracle's are the same thirty rows index for index, which is the rng oracle's own
"the oracle MIRRORS it index for index" (`gates/rng_graph_census-oracle.py:46`).

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
  token for token over the WHOLE cone -- 2500 entries for `lgq`, not a 3-op prefix. This is
  documented divergence A: `UOp.__init__`'s `dtype_from_uop` and `_broadcasted`'s bool->int
  insert promotion CASTs that `ops.bend`'s `UOp.new` does not run, so the trees here are the
  ones Python prints with those CASTs deleted. The census does NOT erase anything to
  manufacture the agreement: the oracle prints CPython AS BUILT and the difference is pinned.

  2 REFUSALS -- `lgn` and `q6`. CPython raises `NotImplementedError` (dtype.py:81 for
  FLOORDIV, dtype.py:125 for `f2f`'s `else`) and the port declines. Both are answers and
  neither is smoothed; they differ in their TOKEN, which is a naming divergence and is
  pinned.

  1 UNBUILT ARM -- `lgu`, `l2i(Ops.CAST, f32, f32)`, dtype.py:35-38. CPython builds a
  20-node `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` and the port returns `None`:
  `dtype.bend:2818` records this as "This arm is not built (header C)". `unported`, not
  dtype.py's exception name -- a different fact.

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
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, REFUSED, gate

# THE 38 ROWS, in the port's own order: `l2i.pick`'s thirty pool-fed arms, then
# `unpack32`, then `f2f.pick`'s seven. The COUNT is the file's, and the bend lane emits all
# 38 including refusals, so this is a MEASUREMENT of the lanes and not a typed inventory --
# `gatekit` refuses the run if a lane disagrees with it.
ROWS = ("lg1", "lg2", "lg3", "lg4", "lg5", "lg6", "lg7", "lg8", "lg9", "lga", "lgb", "lgc",
        "lgd", "lge", "lgf", "lgg", "lgh", "lgi", "lgj", "lgk", "lgl", "lgm", "lgn",
        "lgo", "lgq", "lgr", "lgs", "lgt", "lgu", "lgy",
        "up",
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
WALL = ("lgn", "q6")
UNBUILT = ("lgu",)
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
# {n_div} DIVERGENCES, {n_same} OF THE 38 ROWS AGREE EXACTLY. It is git-resident and beside the
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
        cls = ("PROMOTION, %d CAST/1 deleted" % PROMOTION_CASTS[r] if r in PROMOTION else
               "WALL, both sides refuse" if r in WALL else
               "UNBUILT ARM, dtype.py:35-38 builds it and dtype.bend:2818 does not"
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
        if dele is None or len(dele) != n or set(dele) != {"CAST/1"}:
            print(f"  {r} is not CPython minus exactly {n} CAST/1 entries "
                  f"({'not a deletion' if dele is None else len(dele)})")
            ok = False
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
    sys.exit(gate(GATE, f"decomp_graph_census-gate: 38 rows (30 l2i arms + unpack32 + 7 f2f "
                        f"pairs), 3 lanes, {len(ROWS) - len(DIVERGES)} deep cones match "
                        f"CPython byte-for-byte and {len(DIVERGING)} are DECLARED "
                        f"divergences -- {len(PROMOTION)} are the PROMOTION CASTS `ops.bend`'s "
                        f"`UOp.new` does not run (divergence A: {n_cast} `CAST/1` entries, each "
                        f"verified by DELETING them from CPython's cone and rebuilding the "
                        f"port's), {len(WALL)} are refusals, {len(UNBUILT)} is the unbuilt "
                        f"float-target CAST arm, and q2/q3 ARE FINDINGS: f2f's narrowing arm "
                        f"is not a deletion of CPython's cone; no lane answers the NOOP bottom",
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
# FINDING 1, 2 -- `f2f`'s NARROWING ARM IS NOT A DELETION OF CPython's CONE. `q2` is
# `f2f(f32 -> fp8e4m3)` and `q3` is `f2f(f32 -> fp8e5m2)`, dtype.py:115-124, both DOWN.
# MEASURED: CPython's cone carries `CAST/1` x2, `CONST/0` x1 and `OR/2` x2 that the port's
# does not (57 against 52 and 58 against 53 entries), the port carries NOTHING CPython
# lacks, and the residue is in a different order -- so it is not an extra node and it is not
# a missing one in place. It lives in dtype.py:118-124's `sign`/`nan`/`underflow`
# expressions, where the port builds `sign` at the TARGET's unsigned width and CPython
# builds it at `f2f_dt[fr]` and casts. THE EXACT SITE IS NOT LOCATED and naming one would be
# a guess; `f2f.down.inner` (:1862) and `f2f.down.ocp` (:1868) both call `P.dc_cast` on it,
# so the CAST IS PRESENT IN THE PORT TOO -- what differs is what it is cast FROM.
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
# ===========================================================================