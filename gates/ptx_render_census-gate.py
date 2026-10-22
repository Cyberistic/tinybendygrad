#!/usr/bin/env python3
"""ptx_render_census-gate.py -- A RENDER CENSUS over `tinybendygrad/renderer/ptx.bend`.

    .venv/bin/python gates/ptx_render_census-gate.py
    .venv/bin/python gates/ptx_render_census-gate.py --refresh
    .venv/bin/python gates/ptx_render_census-gate.py --plant

THE ROW COUNT IS READ FROM THE POPULATION, NOT TYPED, and the PIN is
`gates/ptx_render_census-pins.rows`: THREE LANES (CPython, bend interpreted, bend compiled),
every row's whole value spelled out. Run `--refresh` to rewrite it; that is its ONLY writer,
and a file nothing can write is a file nothing can check. A POPULATION THAT GREW is red
there -- the pins file's own per-lane row count is asserted against the population's -- so
the count that used to live in this source no longer has to be edited by hand, and a
count that a regeneration moves is not a count that a regeneration can leave STALE.

58 DECLARED DIVERGENCES IN THREE GROUPS, and the number is DERIVED from the three
groups' own populations -- a hand-typed total is a second copy of the table's size, and
the copy is the part that goes stale.

579 -> 593 AND 58 -> 59, AND BOTH MOVED FOR ONE REASON. The axis was generated on 2026-10-15
against the tree's THEN-`tinygrad/`, and the 2026-10-16 re-vendor to upstream `002630241`
moved a BUFFER's size out of the `ParamArg` and into a size CONST SRC -- so CPython's own
graphs gained a node, and FIFTEEN of the thirty-seven fixtures gained one each. `f14_skips`
LOST one: upstream deleted `Ops.GROUP` (`4e0192eaf remove Ops.GROUP (#18637)`, 2026-10-06) and
the oracle's fixture no longer builds one, so the axis's `OpsGROUP{}` row was a fixture
against an upstream that no longer exists and the file DID NOT COMPILE. MEASURED: 593 - 579
= 14 = 15 gained - 1 lost, and the axis is now the generator's own output rather than a
transcription of an older upstream.

59 -> 58 IS THE OTHER HALF OF THAT SAME RE-VENDOR, AND IT IS FIXED. The 59th divergence was
GROUP 4, ONE row: `fmt_18`, the port's `tc_ptx.bend` passing a `$` line through untouched
where the pin's `ptx.py:164` indents EVERY line. Upstream `96397341d` ("dead code cleanups
[PR] (#18593)", 2026-10-03) DELETED that early return -- MEASURED, at that commit's parent
`ptx.py` held NO OTHER `$` (ONE occurrence in the whole file, the `fmt` line itself), so no
line could begin with `$` and the branch was DEAD CODE -- and the 2026-10-16 re-vendor moved
the tree PAST that commit. `tc_ptx.bend` no longer has `fmt_israw`, `fmt_18` is an ORDINARY
COMPARED row, and `claims_hold()` pins its value like every other row's.

WHY A FOURTH RENDER CENSUS, AND WHY THIS ONE IS DIFFERENT AGAIN.
`gates/cstyle_render_census*` diffs a rendered STRING for a C renderer.
`gates/wgsl_render_census*` diffs a whole WGSL MODULE.
`gates/amd_dsl_census*` diffs a TRIPLE, because that is what its layer returns.
`ptx.py` returns a WHOLE PTX MODULE, and the thing that decides the printed form is that
`PTXRenderer.render`'s BODY comes from TWENTY-THREE `string_rewrite` rules of which the port
has NONE (MEASURED: `grep -c 'string_rewrite' -w tinybendygrad/renderer/tc_ptx.bend` is 0 and
the single hit is a comment at `tc_ptx.bend:272`). So the form is:

  * EVERY ROW BOTH LANES CAN PRODUCE IS COMPARED, value = the WHOLE answer, TAB and LF
    spelled by `TP.esc` on the port side and by the same two substitutions on the oracle
    side. Never a prefix, never a length, never a hash -- `ops.bend`'s `Rng.sig` printed a
    3-op prefix and a deep node swap was invisible.
  * THE MODULE IS ONE ROW PER FIXTURE, `<f>.mod`, AND IT IS A DECLARED DIVERGENCE. The port
    answers `ABSENT:string_rewrite(23) not ported`, or `PORT-ANSWERED`, or
    `PORT-REFUSED:<op>`. An oracle that answered `""` there would AGREE with a port that
    answers `""`, which is why refusals in this census are LOUD and NAMED.
  * ONE ROW PER STEP for the walk, not one per ALLOCATION, and the step that allocated
    nothing says `NONE`. Both sides, or the populations differ by however many steps a
    fixture happens to skip.

THE POPULATION IS DISCOVERED BY RUNNING BOTH LANES. `names_hold()` asserts the two
row-NAME lists are EQUAL AND IN ORDER. `axis_hold()` reads the fixture axis out of
`ptx_render_census.bend`'s own `fixtures()` and out of the generated
`ptx_render_census_axis.bend` and compares those too, and asserts the census's REFUSAL
column against the ORACLE'S OWN `.mod=REFUSE:` rows -- three witnesses, one of them
CPython. Neither is a regex over a source that could drift without anyone noticing.

THE THREE DIVERGENCE GROUPS
---------------------------
  GROUP 1 -- `tyo/mto/cto`, 18 rows. FINDING, NOT A CARVE-OUT. `tc_ptx.bend`'s `types_pri`
    dispatches on `S.Dt.pri` and its `case _` arm is `""`; CPython's `PTXRenderer.types` is
    a dict and a missing dtype is a `KeyError` at ptx.py:181. MEASURED both sides:
    `weakint` -> the port says `pred`, `void` -> `pred` (both collide with `bool` on
    `pri == 0`), and `weakfloat`/`bfloat16`/the four fp8s -> `""`. REACHABLE, which is what
    makes it a defect: `UOp.range(4, 0)` defaults to `dtype=dtypes.weakint` and
    `UOp.const(3.0) + UOp.const(4.0)` is a non-CONST node of dtype `dtypes.weakfloat`, so
    ptx.py RAISES on both and the port emits `%ridx_pred_0` and `%alu__0`. This is the PTX
    form of `amd_dsl`'s `Res{v: U32}` + `U32.shln` discarding the high fields: a field
    SILENTLY EMPTIED where CPython refuses. "A U32 shift is not an error, it is a smaller
    number"; an empty type field is not an error either, it is a kernel ptxas rejects.

  GROUP 2 -- `<f>.mod`, 35 rows. CARVE-OUT, and the shape is the point. `string_rewrite` is
    NOT PORTED, so the module cannot be compared; a divergence that says so in one pinned
    string per fixture is the honest record, and the pin means the day the port grows a
    module this gate goes red until the row leaves DIVERGES. Five of the thirty-five are not
    `ABSENT` but `PORT-ANSWERED` (`f31`, `f32`, `f33`, `f34`) or `PORT-REFUSED:INDEX`
    (`f08`): CPython refused and the port did not, which is GROUP 1 reaching the walk.

  GROUP 3 -- the walk, 5 rows. FINDING, NOT A CARVE-OUT, and it is GROUP 1 REACHING THE
    WALK: the five registers the port allocates where ptx.py:181 refuses.

  GROUP 3a WAS HERE AND IT IS FIXED. `ptx.bend`'s alias arm was `case 2: Wal.rput(w,
    rg_at(w, 0))`, and `rg_at(w, 0)` reads `Wal.r[0]` -- STEP ZERO -- where ptx.py:189
    (`self.r[u] = self.r[u.src[0]]`) and ptx.py:204 (`r[u.src[0]][u.src[1].src[0].val]`)
    both read `r[u.src[0]]`, i.e. `Wal.r[refs[0]]`. SIX ROWS DIVERGED. Two reasons the
    defect survived a green gate, and BOTH are about the fixtures rather than the code:
      * all twenty-five of `ptx.bend`'s OWN fixtures put the aliased node at index 0, and
        every one of the four INDEX/SHRINK-on-REG nodes in this GENERATED axis did too --
        a REG `placeholder` has no srcs, so toposort always emitted it first, and step
        zero is the ONE value `rg_at(w, 0)` gets right. `f37_twobufs` is the fixture that
        broke the tie, and it was missing because a graph with a NON-ZERO `src[0]` for an
        INDEX needs TWO register buffers, and no fixture builder made one.
      * `f12_after` and `f10_loads` DID carry a non-zero `src[0]` and DID diverge -- so
        the census saw the defect from its first run and its 62 divergences were honest.
        The thing that hid it was that 62/557 reads as "this census has carve-outs".
    FIXED in `ptx.bend`: `rg_alias` and `rg_pick` both read `Wk.refs(s)`'s HEAD. The six
    rows left DIVERGES, are COMPARED rows now, and `claims_hold()` pins what each of them
    answers -- a fixed divergence cannot be guarded by the divergence table, because it is
    not in it any more.

WHAT THE DIFF CANNOT SEE, AND WHAT IS SAID INSTEAD
---------------------------------------------------
Two empty lanes would agree on every row, so `claims_hold()` reads the PORT'S OWN `bd.out`
and asserts structural facts no other row produces: the `fmt` boundary pair
(`mov.b32` two tabs, `selp.f32` one), the five EMPTY dtype answers, the `barrier` with its
tab spelled, and the eight walk rows the alias fix moved (`f37_twobufs.r3` is the one that
must NOT move). A check never seen to fail is not a check, so
`gates/ptx_render_census-mutate.py` carries thirteen
mutations -- including THREE THAT MUTATE THIS GATE'S OWN GUARDS, which is the only way to
show `names_hold`, `axis_hold` and `claims_hold` go red rather than being decoration.
"""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import Gate, gate, PY, BEND  # noqa: E402

ORACLE = HERE / "ptx_render_census-oracle.py"
DRIVER = HERE / "ptx_render_census.bend"
AXIS = HERE / "ptx_render_census_axis.bend"
GEN = HERE / "ptx_render_census-gen.py"
PINS = HERE / "ptx_render_census-pins.rows"


def _lines(text):
    return [l for l in text.splitlines() if l.strip()]


def run_oracle():
    """CPython's OWN rows, and the POPULATION this gate compares.

    It is HERE, above the constants that read it, because the row count is read from
    the population and a population that is read twice can be two populations.
    """
    return _lines(subprocess.run([str(PY), str(ORACLE)], capture_output=True,
                                 text=True, check=True).stdout)


# THE ROW COUNT IS READ FROM THE POPULATION, NEVER TYPED.  A COUNT IN THE SOURCE IS A
# SECOND COPY OF A FACT THE POPULATION ALREADY CARRIES, and it is the copy that goes
# STALE: MEASURED, this file said 579 while the population held 593, and nothing said so
# because the number was not compared with anything -- the gate was REFUSED on a compile
# error, so the count was never consulted, and the axis that disagreed with it was the
# axis's own stale copy.
#
# WHERE THE PIN WENT, AND WHY IT IS NOT LOST.  The pin is `gates/ptx_render_census-pins.rows`:
# 3 lanes x one row per population row, every VALUE spelled out, and `pins_hold()` compares
# every one of them with the live lanes.  A population that GAINS a row is red there (the
# pins file has no entry for it and the count check below fires), a population that LOSES
# one is red there (the pinned value is not in the lane), and a population that CHANGES a
# value is red there too.  So the count is derived from the population and the CONTENT is
# pinned by a file whose whole job is to pin it -- and `pins_hold()` also asserts the pins
# file's own per-lane row count, which is what makes a population that GREW red.
#
# 557 -> 579 was TWO fixtures. `f37_twobufs` adds 15 rows (10 `.r` + `.mod` + `.regn` +
# 2 `.reg` + `.entry`): ptx.py:204's `r[u.src[0]]` read whose `src[0]` is NOT at step zero,
# which no other INDEX/SHRINK in the axis had (MEASURED: a REG `placeholder` has no srcs,
# so toposort always emitted it first, and `u.src[0]` at index 0 is the ONE value
# `rg_at(w, 0)` gets right). `f38_regload` adds 7 (3 `.r` + `.mod` + `.regn` + `.reg` +
# `.entry`): a LOAD whose `src[0]` is a REG BUFFER, so its register is a LIST and
# `r[u.src[0]]` and `r[u.src[0]][0]` are DIFFERENT -- the shape M9 could not move.
# 579 -> 593 is THE RE-VENDOR, and it is +14 rows: FIFTEEN fixtures gained a node because
# upstream moved a BUFFER's size out of the arg and into a size CONST SRC, and `f14_skips`
# LOST one because upstream deleted `Ops.GROUP` and the oracle's fixture no longer builds
# one. 15 - 1 = 14, and 579 + 14 = 593. The axis is now the generator's own output, so the
# two numbers cannot disagree: `axis_hold()` checks the axis against the generator.
#
# THE POPULATION IS THE ORACLE'S OWN ROWS, read ONCE, because `build_divergences()` needs
# CPython's `.mod` text anyway and running the oracle twice is a second chance to get two
# different answers.
ORACLE_ROWS = run_oracle()
ROWS = len(ORACLE_ROWS)
# THE DIVERGENCE COUNT IS DERIVED, AND IT IS ASSIGNED BELOW, AFTER THE THREE GROUPS
# EXIST. The reason and the history are with the assignment.

# --------------------------------------------------------------------------
# THE DIVERGENCES, generated ONCE from a real run and then FROZEN here. The three
# groups are listed separately so the CHECK can assert the SIZES: a group that grows
# silently is a group nobody read.
# --------------------------------------------------------------------------
# GROUP 1 -- the dtype tables. port -> (REFUSE spelling, what the port answers).
DTYPES_ABSENT = {"void": ("", "", ""), "bf16": ("", "", ""),
                 "fp8e4m3": ("", "", ""), "fp8e5m2": ("", "", ""),
                 "fp8e4m3fnuz": ("", "", ""), "fp8e5m2fnuz": ("", "", "")}
WEAKINT = ("", "", "")


# GROUP 4 WAS HERE AND IT IS FIXED. `fmt_18` was the ONE row of a FOURTH group: the
# port's `tc_ptx.bend` had `fmt_israw`, a `line[0] == "$"` early return, and upstream
# `96397341d` ("dead code cleanups [PR] (#18593)", 2026-10-03) DELETED that early
# return -- MEASURED, at that commit's parent `ptx.py` held NO OTHER `$` (ONE occurrence
# in the whole file, the `fmt` line itself), so no line could begin with `$` and the
# branch was DEAD CODE. The 2026-10-16 re-vendor moved the tree PAST that commit and the
# port's `fmt` was stale against the pin: the port said `$RAW`, CPython said `\t$RAW`.
# `tc_ptx.bend` has no `fmt_israw` any more, so at the pin EVERY line is indented and
# `fmt_18` is an ORDINARY COMPARED row -- and `claims_hold()` below pins its value like
# every other row's.


def dtype_divergences():
    d = {}
    order = ["void", "bool", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64",
             "f16", "bf16", "f32", "f64", "fp8e4m3", "fp8e5m2", "fp8e4m3fnuz", "fp8e5m2fnuz"]
    for i, nm in enumerate(order):
        if nm == "void":
            t, m, c = WEAKINT
        elif nm in DTYPES_ABSENT:
            t, m, c = DTYPES_ABSENT[nm]
        else:
            continue
        for tag, got in (("tyo", t), ("mto", m), ("cto", c)):
            d[f"{tag}_{i}"] = (f"{tag}_{i}=REFUSE:KeyError({nm})", f"{tag}_{i}={got}")
    return d


# GROUP 2 -- the module. The port's three answers; CPython's is its whole return value.
MODULE_ABSENT = [n for n in FIXTURES] if False else None  # filled from the run below
FIXTURES = ["f01_alu", "f02_counter", "f03_cast5", "f04_end", "f05_regbuf4", "f06_regbuf1",
            "f07_reuse", "f08_refuse", "f09_special", "f09b_launch", "f10_loads",
            "f11_stack", "f12_after", "f13_param", "f14_skips", "f15_bidx", "f16_bitcast",
            "f17_u64", "f19_mixed", "f23_load1", "f24_range", "f25_rangevoid", "f26_store",
            "f27_loadbool", "f28_name", "f29_name2", "f30_noparam", "f31_weakint",
            "f32_weakfloat", "f33_bf16cast", "f34_boolalu", "f35_loadvec", "f36_regstore",
            "f37_twobufs", "f38_regload"]
REFUSALS = {"f08_refuse": "PORT-REFUSED:INDEX", "f31_weakint": "PORT-ANSWERED",
            "f32_weakfloat": "PORT-ANSWERED", "f33_bf16cast": "PORT-ANSWERED",
            "f34_boolalu": "PORT-ANSWERED",
            # f35 IS THE SIXTH, AND IT IS NOT A PORT DEFECT: ptx.py:224 refuses an
            # UN-INDEXED PARAM load, and the PORT ALSO refuses -- both because there is no
            # INDEX for ptx.py's LOAD rules to match. It is here so the census's count of
            # refusals is six rather than five and a seventh is red.
            "f35_loadvec": "PORT-ANSWERED"}

# GROUP 3 -- the walk.
# GROUP 3a IS GONE AND IT IS NOT A CARVE-OUT: `ptx.bend`'s alias arm read `Wal.r[0]`,
# STEP ZERO, where ptx.py:189 (`self.r[u] = self.r[u.src[0]]`) and ptx.py:204
# (`r[u.src[0]][u.src[1].src[0].val]`) both read `Wal.r[refs[0]]`. SIX ROWS DIVERGED --
# `f07_reuse.r4`, `f10_loads.r4`, `.r6`, `.r8`, `.r9` and `f12_after.r5`, the port
# answering `NONE` where CPython answers `%g0`/`%g1`/`%g2`/`{%g0, %g1, %g2}`/`%alu_f32_0`.
# `ptx.bend` now reads `Wk.refs(s)`'s HEAD in BOTH arms (`rg_alias` and `rg_pick`), the
# six rows are COMPARED like every other row, and `claims_hold()` below pins the answer
# EACH of them now gives -- so the fix is guarded in the same place the defect was.
# `f37_twobufs` was added in the same commit because the SAME wrong read was in `rg_pick`
# and NO fixture exercised it: MEASURED, reverting the `rg_pick` line alone moves 2 rows
# on the whole 579-row census and both are `f37_twobufs`, i.e. without the new fixture that
# half of the fix is a coverage gap that reads exactly like a correct edit. `f38_regload`
# is the OTHER such gap, and it is older: `M9` has moved zero rows since this census was
# first run, and the reason recorded for it -- "it moves nothing BECAUSE the alias arm
# already returns the wrong register" -- was true only while that arm was broken.
# GROUP 3b -- GROUP 1 REACHING THE WALK: the five registers the port allocates where
# ptx.py:181 refuses. THESE ARE THE FINDING'S ACTUAL STRINGS, AND THEY STAY: the dtype
# tables are still `types_pri`'s `case _ -> ""` and this unit is not `tc_ptx.bend`'s.
WEAK = {"f31_weakint.r1": "%ridx_s32_0", "f32_weakfloat.r2": "%alu_f32_0",
        "f33_bf16cast.r1": "%cast__0", "f34_boolalu.r3": "%alu_pred_1",
        "f34_boolalu.r4": "{%alu_pred_0, %alu_pred_1}"}


def module_divergences(py):
    d = {}
    for f in FIXTURES:
        k = f"{f}.mod"
        # `gatekit` pins WHOLE LINES, not values -- MEASURED: a value-only pin answers
        # "py's f01_alu.mod is not '.version VERSION\n...'" with the row NAME missing off
        # the front, which is a pin no line can ever satisfy.
        d[k] = (f"{k}={py[k]}", f"{k}=" + REFUSALS.get(f, "ABSENT:string_rewrite(23) not ported"))
    return d


def _pins_lines(text):
    """PINS rows are non-blank AND not a `#` comment, so a provenance line is never parsed as data.

    `_lines()` is deliberately NOT changed to do this: `run_oracle()` feeds it the oracle's STDOUT,
    whose `#` lines are content there. One filter for both would either drop oracle rows or let a
    comment be counted as a pin, and `pins_hold()` exists precisely because a half-parsed pins file
    is worse than a refused one.
    """
    return [l for l in text.splitlines() if l.strip() and not l.startswith("#")]


def rows_of(path):
    """`name=value` -> the dict, and the NAME LIST in order. Two questions, two answers.

    MEASURED, and the reason this is not a one-liner: the session's tally parser read 452
    divergences when the truth was 254 because one gate records `same` AND `DIFFER` in ONE
    column. So the names are taken from the `name=` PREFIX and never from a split on the
    first `=` of a free-form line.
    """
    out = {}
    order = []
    for l in _lines(path.read_text()):
        if "=" not in l:
            continue
        k, v = l.split("=", 1)
        out[k] = v
        order.append(k)
    return out, order


# THE THREE GROUPS, COMPUTED ONCE, and the count is their SUM. A group's MEMBERS are
# DISCOVERED -- the dtype list, the `WEAK` dict, the fixture list -- so the total is a fact
# about the table and the table's size is not a second copy of anything.
_PY_ROWS = {l.split("=", 1)[0]: l.split("=", 1)[1] for l in ORACLE_ROWS}
_G1 = dtype_divergences()
_G2 = {k: (f"{k}=NONE", f"{k}={v}") for k, v in WEAK.items()}
_G3 = module_divergences(_PY_ROWS)


def build_divergences():
    """Every group, in one place, at MODULE SCOPE -- and the reason is `Gate.__init__`.

    MEASURED: `Gate(...)` COPIES `diverges` (`self.diverges = dict(diverges or {})`), so
    a DIVERGES dict filled in AFTER the constructor is a dict the gate never sees. The
    first run of this file said "py has 491 COMPARED rows, expected 460" -- 460 plus the
    31 `.mod` rows that were still missing -- and the fix is to build the dict BEFORE the
    `Gate`, not to mutate it later.

    The `.mod` pins need CPython's OWN module text, so the oracle is run HERE, once. It is
    0.5 s, and running it a second time inside `names_hold()` is the price of a guard that
    reads a lane rather than a file.
    """
    d = {}
    d.update(_G1)
    d.update(_G2)
    d.update(_G3)
    return d


DIVERGES = build_divergences()

# 62 -> 58. GROUP 3a EMPTIED: `ptx.bend`'s alias arm read `Wal.r[0]` where ptx.py:189 and
# ptx.py:204 read `r[u.src[0]]`, six rows diverged, the fix landed, and the six are now
# COMPARED rows like the rest. +2 for `f37_twobufs.mod` and `f38_regload.mod`, which are
# GROUP 2 like every other `.mod`. 58 = 18 dtype + 5 weak registers + 35 `.mod`.
# 58 -> 59 WAS GROUP 4, and it was the SAME RE-VENDOR: upstream's `ptx.py:164` `fmt` LOST its
# `line[0] == "$"` early return (`return line if line[0]=="$" else "\t" + line.replace(...)`
# became `return "\t" + line.replace(...)`), so a `$` line is INDENTED by the pin and
# PASSED THROUGH by the port, whose `tc_ptx.bend` had `fmt_israw`. `fmt_18` is the
# `$RAW` probe: the port said `$RAW`, CPython said `\t$RAW`. A FINDING, NOT A CARVE-OUT --
# the port's `fmt` was stale against the pin -- and it was DECLARED so the exact wrong answer
# was pinned on both sides and a reader could see it.
# 59 -> 58 IS THAT FINDING FIXED. `tc_ptx.bend` has no `fmt_israw` any more, so `fmt_18` is
# an ORDINARY COMPARED row and the table is its three groups again.
#
# THE COUNT IS DERIVED, NOT TYPED, AND IT IS A DIFFERENT KIND OF NUMBER FROM `ROWS`.
# `ROWS` is a count of a DISCOVERABLE population (the oracle's own rows) and the house rule
# is that such a count is not a pin -- it is READ, and the pins file's own per-lane row count
# is what says so when the population moves. `N_DIVERGES` is the size of a HAND-DECLARED
# table: a JUDGMENT about which differences are accepted, each with its exact wrong answer
# pinned on BOTH sides. It was `59`, and it was a SECOND COPY of the table's size -- the
# copy being the part that goes stale. It is now the SUM OF THE THREE GROUPS, whose MEMBERS
# are each DISCOVERED from their own population (the dtype list, the `WEAK` dict, the fixture
# list), and the CHECK is that the TABLE IS EXACTLY THOSE GROUPS. That check is worth more
# than the literal it replaces: GROUP 4 was a row added OUTSIDE the three group builders, and
# under this formulation that row would have made the assert FIRE instead of quietly moving
# a hand-typed number.
N_DIVERGES = len(_G1) + len(_G2) + len(_G3)

GATE = None  # built by `gate()` / `refresh_pins()`, and NEVER at import time.


def names_hold() -> bool:
    """THE POPULATION GUARD. The two row-NAME lists, EQUAL AND IN ORDER.

    `wgsl_render_census-gate.py`'s `names_hold()`, and the reason it exists: the rows are
    built by recursions over lists and by `String.concat` over helpers, so NO regex over
    the source can enumerate them without becoming a second implementation of them. This
    RUNS both sides and compares the names. A row present on one side only is red BEFORE
    any value is compared.

    MUTATION P9 IN `ptx_render_census-mutate.py` DROPS A ROW ON ONE SIDE AND SAYS NOTHING
    MOVED THROUGH THE DIFF -- because a dropped `.r` row renumbers nothing and shifts no
    value -- and this is the check that catches it.
    """
    py_txt = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True)
    bd_txt = subprocess.run([str(BEND), str(DRIVER)], capture_output=True, text=True)
    if py_txt.returncode != 0 or bd_txt.returncode != 0:
        print("ptx_render_census-gate: a lane did not run", file=sys.stderr)
        return False
    _, pn = rows_of_text(py_txt.stdout)
    _, bn = rows_of_text(bd_txt.stdout)
    bad = []
    if len(pn) != ROWS:
        # `ROWS` IS READ FROM THE POPULATION -- from ANOTHER RUN of the oracle, taken when
        # this module was imported.  So this is not a tautology: it is the DETERMINISM
        # check, and a census whose own oracle answers differently twice is a census whose
        # population is not a set.  MEASURED, the oracle is deterministic; this says so on
        # every run rather than assuming it.
        bad.append(f"the oracle emits {len(pn)} named rows on this run, the population "
                   f"held {ROWS} on the run this module was imported with")
    if pn != bn:
        only_py = [x for x in pn if x not in bn]
        only_bd = [x for x in bn if x not in pn]
        if only_py or only_bd:
            bad.append(f"oracle-only {only_py[:4]} port-only {only_bd[:4]}")
        else:
            first = next(i for i, (a, b) in enumerate(zip(pn, bn)) if a != b)
            bad.append(f"SAME NAMES, DIFFERENT ORDER at index {first}: "
                       f"{pn[first]} vs {bn[first]}")
    if bad:
        print("ptx_render_census-gate: NAMES: " + "; ".join(bad), file=sys.stderr)
    return not bad


def rows_of_text(text):
    out, order = {}, []
    for l in _lines(text):
        if "=" not in l:
            continue
        k, v = l.split("=", 1)
        out[k] = v
        order.append(k)
    return out, order


def axis_hold() -> bool:
    """THE FIXTURE AXIS, FIVE WITNESSES. The census's `fixtures()`, the GENERATED axis's
    `# FIXTURES` line, the census's REFUSAL column against CPython's own refusals, the axis's
    UPSTREAM-PIN against the tree, and the axis's BYTES against the generator.

    Every one of the five is a text read or a run, never a hand list, and the REFUSAL
    column is the only ADMITTED axis in the file: "which of these graphs does CPython
    refuse" is not something any call RETURNS, so the generator asks by CALLING `render` and
    this check asks again from the oracle's own `.mod=REFUSE:` rows. A sixth refusal on one
    side and not the other is red here, and not a silent extra row in the diff.

    **AND THE LAST TWO ARE THE ONES THAT CATCH A STALE AXIS, WHICH IS WHAT ACTUALLY HAPPENED.**
    The axis was generated on 2026-10-15 against the tree's THEN-`tinygrad/`; the 2026-10-16
    re-vendor moved a BUFFER's size into a size CONST SRC, so CPython's graphs gained a node
    and the axis was stale by +14 rows -- and NOTHING SAID SO, because the axis's own bytes
    did not move and the gate that would have said so was REFUSED on a compile error. A
    FIXTURE AGAINST AN UNSTATED REVISION IS A FIXTURE AGAINST NOBODY, so the axis now STATES
    the upstream it was generated from, as a CONTENT PIN over the files the oracle READ
    (derived from the oracle's own imports, not a list), and this check compares it with the
    tree. The BYTE check is the second witness and it catches a hand-edit too: the axis is
    the generator's own output, and anything else is a file that describes some other
    upstream.
    """
    bad = []
    src = DRIVER.read_text()
    named = re.findall(r'one_at\("([a-z0-9_]+)",\s*(True\{\}|False\{\})', src)
    idx = [int(m) for m in re.findall(r'one_at\("[a-z0-9_]+",\s*(?:True\{\}|False\{\}),\s*(\d+)', src)]
    ax = AXIS.read_text()
    gen_names = re.search(r"^# FIXTURES (.+)$", ax, re.M)
    gen_ref = re.search(r"^# REFUSES (.+)$", ax, re.M)
    if not gen_names or not gen_ref:
        bad.append("the generated axis has no # FIXTURES / # REFUSES line")
    else:
        if gen_names.group(1).split() != [n for n, _ in named]:
            bad.append("the generated axis names a different fixture set than the census")
        if idx != list(range(len(named))):
            bad.append(f"the axis indices are {idx}, expected 0..{len(named) - 1}")
        census_ref = {n for n, r in named if r == "True{}"}
        gen_refs = set(gen_ref.group(1).split())
        if census_ref != gen_refs:
            bad.append(f"REFUSAL COLUMN census={sorted(census_ref)} generated={sorted(gen_refs)}")
        py, _ = rows_of_text(subprocess.run([str(PY), str(ORACLE)], capture_output=True,
                                            text=True).stdout)
        py_ref = {k[:-4] for k, v in py.items() if k.endswith(".mod") and v.startswith("REFUSE:")}
        if py_ref != gen_refs:
            bad.append(f"CPYTHON REFUSES {sorted(py_ref)}, the axis declares {sorted(gen_refs)}")
    bad += axis_pin_bad(ax)
    if bad:
        print("ptx_render_census-gate: AXIS: " + "; ".join(bad), file=sys.stderr)
    return not bad


def axis_pin_bad(ax: str) -> list[str]:
    """THE TWO STALENESS WITNESSES, and they answer DIFFERENT questions.

    THE PIN: every `# UPSTREAM-PIN <path> <sha256>` line in the axis, compared with the
    tree's current file. It NAMES the upstream file that moved, which is the answer a reader
    wants ("your upstream moved, regenerate the axis"), and it is the content pin the house
    already uses (`gates/gatekit.py:oracle_drift`): a revision STRING in a generated file is
    a transcription, and a transcription is true until the next re-vendor and false after it
    with nothing reading it.

    THE BYTES: the axis against what `gates/ptx_render_census-gen.py` produces NOW. The
    generator IS the axis's only writer, so anything else is a hand-edit or a stale file, and
    this says so in one comparison instead of arguing about which fixture moved.

    NEITHER IS A SECOND COPY OF THE PIN LIST: the pin lines are IN the axis, and the
    generator is run, not re-implemented.
    """
    bad = []
    pins = re.findall(r"^# UPSTREAM-PIN (\S+) ([0-9a-f]{64})$", ax, re.M)
    if not pins:
        bad.append("the axis states no UPSTREAM-PIN, so it names no upstream and a fixture "
                   "against an unstated revision is a fixture against nobody")
    for rel, want in pins:
        p = ROOT / rel
        if not p.is_file():
            bad.append(f"{rel}: the pinned upstream file is ABSENT")
            continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != want:
            bad.append(f"{rel}: {got[:16]} != pinned {want[:16]} -- the upstream MOVED under the "
                       f"axis; regenerate it with `gates/ptx_render_census-gen.py`")
    gen = subprocess.run([str(PY), str(GEN)], capture_output=True, text=True)
    if gen.returncode != 0:
        bad.append(f"the generator did not run (rc={gen.returncode}): {gen.stderr.strip()[:120]}")
    elif gen.stdout != ax:
        bad.append("the axis is NOT what the generator produces now -- it is STALE or "
                   "hand-edited; regenerate it with `gates/ptx_render_census-gen.py`")
    return bad


def claims_hold() -> bool:
    """STRUCTURAL FACTS, read off the PORT'S OWN `bd.out`.

    Two lanes that both emit `""` agree, so a diff cannot see a renderer that renders
    nothing. Every claim here is a string NO OTHER ROW PRODUCES:
      * the `fmt` BOUNDARY PAIR -- `mov.b32` is seven characters and gets TWO tabs,
        `selp.f32` is eight and gets ONE, and nothing else separates ptx.py:164's rule;
      * the five EMPTY dtype answers -- an empty value next to a row name is the whole
        claim, and `gatekit._lines` would otherwise have nothing to say about it;
      * `barrier` with its TAB spelled rather than emitted;
      * the EIGHT GROUP-3 walk rows. Six read `NONE` for as long as the pin stood and now
        read CPython's register; `f37_twobufs.r4` is the one that must NOT change. They
        are here because a fixed divergence leaves `DIVERGES` and becomes an ordinary
        COMPARED row -- which the DIFF does see, but only as one row among 593.
    """
    f = make_gate().dir / "bd.out"
    if not f.exists():
        return False
    rows, _ = rows_of(f)
    # THE BOUNDARY PAIR, and it is `fmt_0` vs `fmt_1`: `mov.b32` is SEVEN characters and
    # `fmt` gives it TWO tabs, `selp.f32` is EIGHT and gets ONE. `fmt_3`/`fmt_4` are the
    # same boundary on the BOOL arms (`and.pred` 8, `or.pred` 7) and `fmt_9`/`fmt_10` on
    # the integer arms, so one rule is pinned three times over.
    want = {"fmt_0": "\\tmov.b32\\t\\t%d, %a;", "fmt_1": "\\tselp.f32\\t%d, %b, %c, %a;",
            "fmt_4": "\\tor.pred\\t\\t%d, %a, %b;", "fmt_10": "\\tsetp.eq.s32\\t%d, %a, %b;",
            "fmt_18": "\\t$RAW", "fmt_17": "\\tbar.sync\\t0;",
            "tyo_11": "", "mto_11": "", "cto_11": "", "tyo_14": "", "tyo_17": "",
            "barrier": "bar.sync\\t0;",
            # GROUP 3a, NOW FIXED. These six read `NONE` for exactly as long as the pin
            # stood and now read CPython's register, so the check that watched the defect
            # is the check that watches the fix: a REGRESSION to `Wal.r[0]` answers `NONE`
            # here and turns this guard red, which the DIVERGES table can no longer do --
            # a fixed row leaves DIVERGES and becomes an ordinary COMPARED row.
            "f07_reuse.r4": "%g0", "f10_loads.r4": "%g0", "f10_loads.r6": "%g1",
            "f10_loads.r8": "%g2", "f10_loads.r9": "{%g0, %g1, %g2}",
            "f12_after.r5": "%alu_f32_0",
            # AND THE `rg_pick` HALF, WHICH HAD NO FIXTURE UNTIL `f37_twobufs`. THE THREE
            # ROWS BELOW MOVED BY ONE STEP, AND WHY IS THE SAME RE-VENDOR AS EVERYTHING ELSE:
            # upstream moved a BUFFER's size into a size CONST SRC, so the size CONST is now
            # step 0 and every INDEX in this fixture moved down one. `r8` is `r[5][1]` =
            # `%reg_f32_5`, the second INDEX's register; reading step zero now answers `NONE`
            # (step 0 is the size CONST, which allocates nothing) rather than `%reg_f32_1`,
            # so the discriminator is LOUDER than it was. `r9` is the STACK that consumes it.
            "f37_twobufs.r8": "%reg_f32_5", "f37_twobufs.r9": "{%reg_f32_2, %reg_f32_5}",
            # THE FIRST INDEX'S REGISTER, `r[1][2]` = `%reg_f32_2`. IT IS NO LONGER THE
            # "NEGATIVE" IT WAS: the old `r3` was `r[0][2]` and step zero WAS the buffer, so
            # the step-zero read was RIGHT for it and the fixture could pass by being
            # uniformly wrong. There is no such row left in this fixture -- step 0 is the
            # size CONST now -- and MEASURED, the step-zero regression (`rg_pick` reading
            # `Wal.r[0]`) moves SIX rows where it used to move TWO: `f05_regbuf4.r4`,
            # `f06_regbuf1.r4`, `f36_regstore.r4`, `f37_twobufs.r4`, `.r8` and `.r9`, all
            # to `NONE`. The fixture discriminates HARDER, and this row is one of the six.
            "f37_twobufs.r4": "%reg_f32_2",
            "f31_weakint.r1": "%ridx_s32_0", "f32_weakfloat.r2": "%alu_f32_0",
            "f33_bf16cast.r1": "%cast__0",
            # `f35_loadvec`'s LOAD IS STEP 2 NOW, NOT STEP 1, for the same reason: the
            # PARAM's size CONST is step 0 and the PARAM is step 1. The VALUE is unchanged --
            # a four-element LIST, which is the M9 shape (`f38_regload`'s LOAD subscripts a
            # LIST rather than a scalar). MEASURED, M9 moves `f38_regload.r2` (it was `.r1`).
            "f35_loadvec.r2": "{%val_f32_0, %val_f32_1, %val_f32_2, %val_f32_3}",
            "f31_weakint.mod": "PORT-ANSWERED", "f08_refuse.mod": "PORT-REFUSED:INDEX",
            "f05_regbuf4.reg0": "\\t.reg\\t\\t.f32 %reg_f32_<4>;",
            "f10_loads.reg2": "\\t.reg\\t\\t.u32 %g2;"}
    bad = {k: rows.get(k) for k, v in want.items() if rows.get(k) != v}
    if bad:
        print(f"ptx_render_census-gate: the port's own strings moved: {bad}", file=sys.stderr)
    return not bad


def pins_hold() -> bool:
    """THE PINS FILE'S COLUMN SHAPE IS ASSERTED BEFORE IT IS PARSED.

    MEASURED, and this is not a formality: the session's tally parser read 452 divergences
    when the truth was 254 because one gate records `same` AND `DIFFER` in ONE column. So
    the header is read first, and a file whose header is not `lane<TAB>row<TAB>value` is
    REFUSED rather than half-parsed. Three columns, exactly, on every line.
    """
    if not PINS.exists():
        print(f"ptx_render_census-gate: {PINS} is MISSING -- run --refresh", file=sys.stderr)
        return False
    lines = _pins_lines(PINS.read_text())
    if not lines or lines[0].split("\t") != ["lane", "row", "value"]:
        print(f"ptx_render_census-gate: pins header is {lines[0]!r}, expected "
              f"'lane\\trow\\tvalue'", file=sys.stderr)
        return False
    bad = [i for i, l in enumerate(lines[1:], start=2) if len(l.split("\t")) != 3]
    if bad:
        print(f"ptx_render_census-gate: pins lines {bad[:4]} are not three columns",
              file=sys.stderr)
        return False
    g = make_gate().dir
    raw = {}
    for t, fn in (("py", "py.rows"), ("bd", "bd.out"), ("bn", "bn.out")):
        got, _ = rows_of(g / fn)
        raw[t] = got
    miss = []
    for l in lines[1:]:
        lane, row, val = l.split("\t")
        got = raw[lane].get(row)
        if got != val:
            miss.append(f"{lane}:{row}={got!r} != pinned {val!r}")
    # THE PINS FILE'S OWN ROW COUNT, and it is the PIN for the count the source no longer
    # types.  `ROWS` is read from the POPULATION (the oracle's own rows), so a population
    # that GREW moves `ROWS` with it -- and the pins file, which was written against the
    # OLD population, is what says so.  WITHOUT THIS, a population that grew would be a
    # SILENT change: every pinned row would still match (the old rows are still there),
    # and the extra row would be compared against nothing.  THE COUNT IS NOT A NUMBER
    # ANYMORE, IT IS A FILE, AND A FILE CAN BE STALE.
    per_lane = {}
    for l in lines[1:]:
        lane = l.split("\t", 1)[0]
        per_lane[lane] = per_lane.get(lane, 0) + 1
    for lane, n in sorted(per_lane.items()):
        if n != ROWS:
            miss.append(f"{lane}: the pins file holds {n} rows, the population holds {ROWS} -- "
                        f"the population moved; refresh the pins with --refresh")
    if miss:
        print("ptx_render_census-gate: PINS: " + "; ".join(miss[:4]), file=sys.stderr)
    return not miss


def make_gate():
    """`Gate.__init__` EMPTIES `gates/artifacts/<name>/` -- MEASURED in `gatekit.py`'s own
    comment, and it is why `GATE` is built inside a function and not at module scope: a
    module-level `Gate(...)` runs `_clear()` during IMPORT, so `--refresh` would delete the
    very artifacts it is about to read. `gatekit` says this placement is the only one that
    works ("ONLY CONSTRUCTION IS BEFORE EVERY PATH") and this is the consumer-side half of
    the same lesson."""
    global GATE
    if GATE is None:
        GATE = Gate("ptx_render_census", bend="ptx_render_census.bend",
                    oracle="ptx_render_census-oracle.py", rows=ROWS,
                    compared=ROWS - N_DIVERGES, diverges=DIVERGES)
    return GATE


def refresh_pins():
    """THE ONLY WRITER of `ptx_render_census-pins.rows`. A pins file nothing can write is a
    pins file nothing can check, and a pins file a gate can rewrite by itself is not a pin."""
    d = HERE / "artifacts" / "ptx_render_census"      # NOT via `make_gate()`: see its note
    for name in ("py.rows", "bd.out", "bn.out"):
        if not (d / name).exists():
            print(f"--refresh needs a run first: {d / name} is missing", file=sys.stderr)
            return 3
    body = _pins_lines(PINS.read_text())[1:] if PINS.exists() else []
    # THE FILE IS REBUILT, NEVER APPENDED TO. MEASURED: the first `--refresh` KEPT the old
    # body and added the three lanes to it, so a second run produced every pin TWICE --
    # 3216 rows for 1071 distinct ones. `pins_hold()` still passed, because a duplicate is
    # a duplicate OF THE SAME VALUE, which is exactly the kind of noise a check that
    # iterates rather than compares will not notice. Deduped on `(lane, row)`, last wins.
    rows = {(t, r): v for t, r, v in (l.split("\t") for l in body)}
    emitted: dict[str, set[str]] = {}
    for lane, name in (("py", "py.rows"), ("bd", "bd.out"), ("bn", "bn.out")):
        got, _ = rows_of(d / name)
        emitted[lane] = set(got)
        rows.update({(lane, k): v for k, v in got.items()})
    # **AND A PIN FOR A ROW THAT NO LANE EMITS IS DROPPED, WHICH IS THE OTHER HALF OF
    # "REBUILT".** MEASURED: `f14_skips` LOST a node -- upstream deleted `Ops.GROUP`, so the
    # fixture's walk is one step shorter -- and the old file's `f14_skips.r8` survived the
    # merge because nothing in the lanes says that row does not exist. `pins_hold()` then
    # read `raw[lane].get("f14_skips.r8")` as `None` against a pinned `NONE` and the gate
    # went RED ON A ROW THAT DOES NOT EXIST. The merge exists so that a LANE THAT DID NOT
    # RUN keeps its pins; a row no lane emits is not that, so it is dropped -- and the
    # population of a pins file is the rows the lanes EMIT, which is what the file's own
    # header says the lanes are.
    every = set().union(*emitted.values()) if emitted else set()
    dropped = [k for k in list(rows) if k[1] not in every]
    for k in dropped:
        del rows[k]
    if dropped:
        print(f"--refresh: dropped {len(dropped)} pin(s) for rows no lane emits, e.g. "
              f"{sorted({r for _, r in dropped})[:4]}")
    # SORT BY (row, lane) AND WRITE lane, row, value -- MEASURED, the first version sorted
    # `(row, lane, value)` and then joined the tuple as it stood, so the file came out
    # `row<TAB>lane<TAB>value` while the header said `lane<TAB>row<TAB>value`. `pins_hold()`
    # asserted the HEADER and then read every line as if the header were true, so it failed
    # with a KeyError rather than a shape complaint, and the next `--refresh` re-read the
    # transposed columns and doubled the file. Writing the columns EXPLICITLY is the fix
    # and is also why `pins_hold()` asserts the header BEFORE it parses a single line.
    out = sorted(((r, l, v) for (l, r), v in rows.items()))
    # THE PROVENANCE LINE IS WRITTEN HERE, NOT PASTED INTO THE OUTPUT. `--refresh` rewrites this
    # file whole, so a header added by hand is erased by the next regeneration -- and
    # `gates/pins-shape-gate.py` asks every `gates/*.rows` to declare who writes it (`WRITER` matches
    # `GENERATED by ...`). A generated file's declaration has to come out of the generator.
    PINS.write_text("\n".join(["# GENERATED by `gates/ptx_render_census-gate.py --refresh`."
                                " THE ONLY WRITER.", "lane\trow\tvalue"]
                              + [f"{l}\t{r}\t{v}" for r, l, v in out]) + "\n")
    print(f"--refresh: wrote {len(out)} pin rows to {PINS}")
    return 0


# ---- the plant ---------------------------------------------------------------------------------
# THE PLANT IS A TEXT EDIT ON THE FILE AS IT STANDS NOW, NEVER A READ OF `git show HEAD:`.
# A plant that reads HEAD plants nothing the moment HEAD carries the defect's fix -- and
# THIS defect's fix is already in HEAD's future, because the fix IS "regenerate the axis".
# So the bytes come from the WORKING TREE and the edit is applied to them.
#
# THE ANCHOR IS THE WHOLE `ax14` HEADER AND ITS FIRST TWO ROWS, not one row: the `OpsNOOP`
# row is not unique (ax21 has one too), and an anchor that is not unique is an anchor that
# plants in two places at once. MEASURED, and the reason is in the header: the file is
# GENERATED, so the `ax14` block is a fixed shape the generator emits, and the plant puts
# back the row the generator no longer emits.
PLANT_ANCHOR = ('def ax14() -> List<&2, P.Wk>:\n'
                '  [  P.Wk{O.OpsNOOP{}, S.void(), S.Aalu{}, 1, "", [], 0, True{}},\n'
                '    P.Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},')
# THE PLANTED ROW IS THE ROW THE OLD AXIS HAD: `O.OpsGROUP{}`, the op upstream DELETED in
# `4e0192eaf remove Ops.GROUP (#18637)` (2026-10-06). It is not a plausible-looking op; it
# is the EXACT text that was there, because the question the plant asks is "does the
# compiler refuse a name the enum does not declare", and a made-up op would answer a
# different question.
PLANT_ROW = '    P.Wk{O.OpsGROUP{}, S.void(), S.Aalu{}, 1, "", [0, 0], 0, True{}},'
# THE CONTROL'S ANCHOR IS A LINE THAT CARRIES ONE STATEMENT, so a comment appended at its
# END cannot swallow anything. The two-part line is the `ax14` LIST OPEN plus its first
# element -- `  [  P.Wk{...},` -- and that is what SHAPE A below uses.
CONTROL_ANCHOR = '    P.Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},\n' \
                 '    P.Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},'
SCRATCH = HERE / "_ptxaxis_plantcase.bend"


def _code_only(text: str) -> str:
    """The file with every comment REMOVED and every blank line DROPPED.

    The comment removal is `checks/port-compile-gate.py`'s own `strip_comments()`, imported by
    path and not re-implemented -- it is the house's stripper and it knows that a `#` inside a
    string is not a comment. The BLANK-LINE DROP is this file's addition, and it is what makes
    the proof cover a WHOLE-LINE comment: a comment on its own line contributes a line that is
    empty once the comment is stripped, and comparing LINE LISTS would call that "not
    comment-only" -- which is the most comment-only edit there is.
    """
    pc = _load_port_compile()
    return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


def plant() -> int:
    """THE PLANT, THE CONTROL, AND THE TWO WRONG SHAPES OF A COMMENT-ONLY EDIT.

        .venv/bin/python gates/ptx_render_census-gate.py --plant

    THE PLANT puts `O.OpsGROUP{}` back and the COMPILE CHECK MUST GO RED. THE CONTROL is a
    comment of the same size on a line that carries ONE statement, and it must move
    NOTHING. The two wrong shapes are MEASURED, not assumed, because a control that edits
    more than it meant to is not a control:

      SHAPE A -- a comment BETWEEN the two parts of a line that carries two parts DELETES
      the second part. In bend a `#` runs to the end of the line, so a comment inserted
      between a list opener and its first element swallows the element, and the file still
      COMPILES -- which is the dangerous part: the comment-only proof is what catches it,
      and the compiler does not.
      SHAPE B -- a whole-line comment AT COLUMN 0 does NOT break a bend file. The parser
      skips whole-line comments, so the block below is untouched. MEASURED here, on this
      file, at the insertion point the shape names.

    THE COMPILE CHECK IS THE INSTRUMENT'S OWN, IMPORTED BY PATH from
    `checks/port-compile-gate.py` -- its `judge()` and its `strip_comments()`. A second copy
    of either would be a second copy of a population, and this file already carries one
    fault of that kind.
    """
    pc = _load_port_compile()
    original = AXIS.read_text()
    if PLANT_ANCHOR not in original:
        print("REFUSED: the plant's anchor is not in the axis as it stands. THE PLANT IS A TEXT "
              "EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
              "re-anchored -- NOT that it should fall back to reading git.")
        return 3
    cases = []
    # 1. THE PLANT: the compile error put back.
    cases.append(("PLANT", original.replace(PLANT_ANCHOR, PLANT_ANCHOR.replace(
        '    P.Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},',
        PLANT_ROW + '\n    P.Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},', 1)),
        "the op upstream deleted, constructed again"))
    # 2. THE CONTROL: a comment of the same size, on a line that carries ONE statement.
    cases.append(("CONTROL", original.replace(
        PLANT_ANCHOR,
        PLANT_ANCHOR + '  # control: a comment, same size, no code', 1),
        "a comment of the same size at the end of a one-statement line"))
    # 3. SHAPE A -- a comment BETWEEN the two parts of the two-part line. The first element
    #    of the `ax14` list is the second part, and it is DELETED.
    two_part = '  [  P.Wk{O.OpsNOOP{}, S.void(), S.Aalu{}, 1, "", [], 0, True{}},'
    if two_part in original:
        cases.append(("WRONG-SHAPE-A (comment between a list opener and its first element)",
                      original.replace(two_part, '  [  # a comment between the opener and the element',
                                       1),
                      "the second part of a two-part line is DELETED"))
    else:
        print("WRONG-SHAPE-A  NOT APPLICABLE, AND THAT IS A MEASUREMENT: the axis has no line "
              "that carries a list opener and its first element on one line.")
    # 4. SHAPE B -- a whole-line comment AT COLUMN 0, above an indented body.
    lines = original.split("\n")
    indent = next((i for i, ln in enumerate(lines)
                   if i > 0 and ln.startswith("  ") and lines[i - 1].strip()
                   and not lines[i - 1].lstrip().startswith("#")), None)
    if indent is not None:
        b = list(lines)
        b.insert(indent, "# a comment inserted at column 0")
        cases.append((f"WRONG-SHAPE-B (column-0 comment above line {indent + 1})",
                      "\n".join(b),
                      "a comment line at column 0, above an indented body"))
    else:
        print("WRONG-SHAPE-B  NOT APPLICABLE, AND THAT IS A MEASUREMENT: no indented body "
              "follows a non-comment line in the axis.")

    bad = 0
    for name, text, why in cases:
        SCRATCH.write_text(text)
        try:
            state, detail, _ = pc.judge(str(SCRATCH), 2048, 300)
        finally:
            SCRATCH.unlink(missing_ok=True)
        # A COMMENT-ONLY EDIT IS PROVED BY THE COMMENT-STRIPPED BYTES, not by the verdict --
        # and the proof drops BLANK LINES, because a WHOLE-LINE comment IS a blank line once
        # the comment is gone. MEASURED: without that, the most comment-only edit there is --
        # a comment on its own line -- reads as "not comment-only" for a difference of ONE
        # EMPTY LINE, and a control that is rejected for being a comment is a control that
        # proves nothing. A comment APPENDED to a line leaves no blank line at all, so both
        # shapes are covered by the same comparison.
        same_code = _code_only(text) == _code_only(original)
        print(f"{name:<62} verdict={state:<14} comment-only={same_code!s:<5} {why}")
        print(f"{'':<62} :: {detail[:110]}")
        if name == "PLANT":
            if state != "FINDING":
                print("  THE PLANT DID NOT FIRE: the compile check did not go red on the defect "
                      "it plants.")
                bad += 1
        if name == "CONTROL":
            if state != "COMPILES" or not same_code:
                print("  THE CONTROL IS NOT A CONTROL: it moved the verdict, or it edited more "
                      "than a comment.")
                bad += 1
        if name.startswith("WRONG-SHAPE-A") and same_code:
            print("  THE WRONG SHAPE DID NOT MISBEHAVE: it was comment-only after all, so it is "
                  "not a demonstration of anything.")
            bad += 1
        if name.startswith("WRONG-SHAPE-B") and state != "COMPILES":
            print("  THE WRONG SHAPE BROKE THE FILE, so it is not the shape this file tolerates.")
            bad += 1
    fp = fmt_plant()
    if fp == 3:
        return 3
    bad += fp
    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return 1 if bad else 0


# ---- the fmt plant ---------------------------------------------------------------------
# THE SUBJECT IS THE PORT, AND THE DEFECT IS THE ONE UPSTREAM DELETED.
#
# THE BYTES COME FROM THE WORKING TREE AND NEVER FROM `git show HEAD:`. A plant that reads
# HEAD plants nothing the moment HEAD carries the fix, and THIS fix IS IN HEAD'S FUTURE BY
# CONSTRUCTION: the fix and the plant are the same commit, so a HEAD-reading plant would
# plant NOTHING on the very commit that removes the defect.
#
# THE SCRATCH LIVES IN `gates/`, NOT IN `tinybendygrad/`. `bin/bend` resolves
# `import ./x.bend` relative to the IMPORTING FILE's own directory, so a copy of
# `tc_ptx.bend` has to sit where its own imports resolve -- and `tinybendygrad/` IS the
# substrate, so a scratch file left there would MOVE THE DIGEST. The copy's four imports
# are rewritten to reach the port's own files and the driver's ONE import line is rewritten
# to reach the copy: five lines of rewriting and NO hand-written axis.
FMT_PORT = ROOT / "tinybendygrad" / "renderer" / "tc_ptx.bend"
FMT_SCRATCH_PORT = HERE / "_ptxfmt_port_plantcase.bend"
FMT_SCRATCH_DRIVER = HERE / "_ptxfmt_driver_plantcase.bend"
FMT_DRIVER_IMPORT = "import ./../tinybendygrad/renderer/tc_ptx.bend as TP"
FMT_DRIVER_IMPORT_SCRATCH = "import ./_ptxfmt_port_plantcase.bend as TP"
FMT_PORT_IMPORTS = (("import ./../helpers.bend as H", "import ./../tinybendygrad/helpers.bend as H"),
                    ("import ./../LAWS/spec.bend as S", "import ./../tinybendygrad/LAWS/spec.bend as S"),
                    ("import ./../uop/ops.bend as O", "import ./../tinybendygrad/uop/ops.bend as O"),
                    ("import ./tc.bend as T", "import ./../tinybendygrad/renderer/tc.bend as T"))
# THE FIXED `fmt`, AND THE DEFECTIVE ONE. THE PLANT PUTS THE DEFECT BACK, AND IT PUTS BACK
# `fmt_israw` WITH IT, because the fix REMOVED that def: upstream deleted the `$` early
# return and the port deleted its reader with it.
FMT_FIXED = ('def fmt(+line: String) -> String:\n'
             '  String.concat([tab(), String.from_list(fmt_rep(String.to_list(line), '
             'fmt_rep_of(line), Nil{}))])')
FMT_DEFECT = ('def fmt_israw(+line: String) -> Bool: String.eq(String.take(line, 1n), "$")\n'
              '\n'
              'def fmt(+line: String) -> String:\n'
              '  Bool.pick(String, fmt_israw(line), line, String.concat([tab(), '
              'String.from_list(fmt_rep(String.to_list(line), fmt_rep_of(line), Nil{}))]))')
# THE CONTROL'S ANCHOR IS A `def` LINE, and the comment goes on a LINE OF ITS OWN above it.
# A whole-line comment is the MOST comment-only edit there is, and it is the one the
# blank-line-dropping proof exists for.
FMT_CONTROL_ANCHOR = ("def fmt_rep(+cs: List<&2, Char>, +rep: String, "
                      "+acc: List<&2, Char>) -> List<&2, Char>:")
FMT_CONTROL_EDIT = "# a comment inserted at column 0, above the def it belongs to\n" + FMT_CONTROL_ANCHOR


def _fmt_row(port_text):
    """The port's `fmt_18` row, MEASURED by running the CENSUS'S OWN DRIVER.

    The scratch driver is the gate's own driver with ONE import line swapped, so the axis,
    the row names and the comparison are the gate's own and not a second copy of them.
    """
    p = port_text
    for old, new in FMT_PORT_IMPORTS:
        if old not in p:
            return None, f"the port's import {old!r} is not in the file as it stands"
        p = p.replace(old, new, 1)
    d = DRIVER.read_text()
    if FMT_DRIVER_IMPORT not in d:
        return None, "the driver's import of `tc_ptx.bend` is not in the file as it stands"
    FMT_SCRATCH_PORT.write_text(p)
    FMT_SCRATCH_DRIVER.write_text(d.replace(FMT_DRIVER_IMPORT, FMT_DRIVER_IMPORT_SCRATCH, 1))
    from bendlock import bend_lock
    with bend_lock():
        r = subprocess.run([str(BEND), str(FMT_SCRATCH_DRIVER)], capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"the scratch driver did not run (rc={r.returncode}): {r.stderr.strip()[:120]}"
    for l in r.stdout.splitlines():
        if l.startswith("fmt_18="):
            return l.split("=", 1)[1], None
    return None, "the scratch driver emitted no `fmt_18` row"


def fmt_plant() -> int:
    """THE PORT PLANTED WITH THE DELETED UPSTREAM RULE, AND A COMMENT-ONLY CONTROL.

    THE PLANT puts upstream's DELETED `$` early return back into `tc_ptx.bend` and the
    `fmt_18` row MUST MOVE -- back to `$RAW`, the deleted rule's answer -- which is what
    makes `pins_hold()` red, because the pins file pins `bd.fmt_18` as the pin's value.

    THE CONTROL is a comment on a line of its own, and it must move NOTHING. The proof that
    it moved nothing is the COMMENT-STRIPPED BYTES with the BLANK LINES DROPPED -- the same
    proof the axis plant uses, and the same third finding: a whole-line comment IS a blank
    line once the comment is gone, so a comparison that keeps blank lines calls the most
    comment-only edit there is "not comment-only".

    THE TWO WRONG SHAPES OF A COMMENT-ONLY EDIT ARE MEASURED BY THE AXIS PLANT ABOVE, ON
    THE AXIS. They are properties of bend's comment handling and not of this file, and
    measuring them twice would be a second copy of a measurement.
    """
    original = FMT_PORT.read_text()
    if FMT_FIXED not in original:
        print("REFUSED: the port's `fmt` is not in the file as it stands. THE PLANT IS A TEXT "
              "EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
              "re-anchored -- NOT that it should fall back to reading git.")
        return 3
    if FMT_CONTROL_ANCHOR not in original:
        print("REFUSED: the control's anchor is not in the port as it stands.")
        return 3
    bad = 0
    try:
        want, why = _fmt_row(original)
        if want is None:
            print(f"REFUSED: the port as it stands answered no `fmt_18` row: {why}")
            return 3
        cases = [
            ("PLANT (upstream's DELETED `$` early return put back)",
             original.replace(FMT_FIXED, FMT_DEFECT, 1),
             "the rule upstream deleted, constructed again"),
            ("CONTROL (a comment on a line of its own)",
             original.replace(FMT_CONTROL_ANCHOR, FMT_CONTROL_EDIT, 1),
             "a comment-only edit, which must move NOTHING"),
        ]
        for name, text, what in cases:
            got, why = _fmt_row(text)
            if got is None:
                print(f"{name}: the scratch did not answer: {why}")
                bad += 1
                continue
            same_code = _code_only(text) == _code_only(original)
            print(f"{name:<62} fmt_18={got!r:<12} comment-only={same_code!s:<5} {what}")
            if name.startswith("PLANT"):
                if got == want:
                    print("  THE PLANT DID NOT FIRE: the row did not move.")
                    bad += 1
                elif got != "$RAW":
                    print(f"  THE PLANT MOVED THE ROW TO {got!r}, which is not the deleted rule's "
                          "answer ($RAW).")
                    bad += 1
            if name.startswith("CONTROL"):
                if got != want:
                    print("  THE CONTROL IS NOT A CONTROL: it moved the row.")
                    bad += 1
                if not same_code:
                    print("  THE CONTROL IS NOT A CONTROL: it edited more than a comment.")
                    bad += 1
    finally:
        FMT_SCRATCH_PORT.unlink(missing_ok=True)
        FMT_SCRATCH_DRIVER.unlink(missing_ok=True)
    return bad


def _load_port_compile():
    """`checks/port-compile-gate.py` BY PATH, for its `judge()` and its `strip_comments()`.

    The compile check is that file's, and it reads the VERDICT TOKEN rather than the exit
    status -- `AGENTS.md` records a unit that lost 425 rows by believing the status. Re-typing
    a second judge here would be a second copy of the question, and the two would drift.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location("port_compile", ROOT / "checks" / "port-compile-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


if __name__ == "__main__":
    if "--plant" in sys.argv:
        sys.exit(plant())
    if "--refresh" in sys.argv:
        sys.exit(refresh_pins())
    make_gate()
    assert len(DIVERGES) == N_DIVERGES, (
        f"the table holds {len(DIVERGES)} rows and its three groups hold {N_DIVERGES} -- a "
        "divergence was added OUTSIDE a group builder, or two groups share a row")
    # NO TYPED COUNT HERE EITHER.  `534` was a second copy of `ROWS - N_DIVERGES` and it
    # was stale for the same reason `593` was: a number in the source is a copy nobody
    # compares with anything.  The comparison is still ASSERTED -- it is the shape of the
    # gate, not the value -- but the value is computed.
    assert GATE.compared == ROWS - N_DIVERGES
    sys.exit(gate(make_gate(),
                  f"ptx_render_census-gate: {ROWS} rows (READ FROM THE POPULATION, not typed), "
                  f"3 lanes byte-identical over the walk and the SEAM, {N_DIVERGES} DECLARED "
                  f"divergences in THREE groups -- {len(_G1)} are the dtype tables answering "
                  "`pred` or the EMPTY STRING where ptx.py:181 raises KeyError (the PTX form "
                  "of the AMDWORD32 defect, REACHABLE through UOp.range's default weakint) "
                  f"and {len(_G2)} MORE are the registers the port then allocates where "
                  "CPython refuses (`%alu__0`, `%cast__0`, `%ridx_pred_0`); and "
                  f"{len(_G3)} are the un-ported string_rewrite. The `fmt_18` row -- the port's "
                  "`tc_ptx.bend` passing a `$` line through untouched where the pin's "
                  "`ptx.py:164` indents EVERY line -- is FIXED and COMPARED, because upstream "
                  "`96397341d` DELETED that early return as DEAD CODE. The SIX rows that were "
                  "ptx.bend's alias arm reading Wal.r[0] where ptx.py:189 and :204 read "
                  "r[u.src[0]] are FIXED and COMPARED, `f37_twobufs` is the fixture whose INDEX "
                  "carries a non-zero src[0] and the only thing in the axis that can see the "
                  "same wrong read in `rg_pick`, and `f38_regload` is the one whose LOAD "
                  "subscripts a LIST rather than a scalar, which is what M9 needed",
                  checks=lambda: (names_hold() and axis_hold() and claims_hold() and pins_hold())))