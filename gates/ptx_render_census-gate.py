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
has NONE (MEASURED, and the count is NOT 0: `grep -c 'string_rewrite' -w
tinybendygrad/renderer/tc_ptx.bend` is 1 and the single hit is a COMMENT -- the port has no
RULE TABLE, which is what the gate's own pin on the port's `ABSENT` answer witnesses). So the
form is:

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
  GROUP 1 -- `tyo/mto/cto`, 18 rows. FINDING, NOT A CARVE-OUT. CPython's `PTXRenderer.types`
    and its two siblings are DICTS of 12 KEYS, so a dtype they do not name is a `KeyError`
    at ptx.py:181; the port's three tables answer the EMPTY STRING for exactly six dtypes
    -- `void` (the `CVoid` arm) and `bfloat16` and the four fp8s (`types_pri`'s `case _`).
    MEASURED both sides, and the `pred` that used to be in this sentence is GONE: the port
    answers `pred` for `bool` ONLY, and CPython answers `pred` for `bool` too, so `bool` is
    not a divergence at all -- the port answers `s32` for `weakint` (`w_int()`) and `f32` for
    `weakfloat` (`w_float()`), and those are REAL types, not empty ones. REACHABLE, which is
    what makes it a defect: `UOp.range(4, 0)` defaults to `dtype=dtypes.weakint` and
    `UOp.const(3.0) + UOp.const(4.0)` is a non-CONST node of dtype `dtypes.weakfloat`, so
    ptx.py RAISES on both and the port emits `%ridx_s32_0` and `%alu_f32_0`. This is the PTX
    form of `amd_dsl`'s `Res{v: U32}` + `U32.shln` discarding the high fields: a field
    SILENTLY EMPTIED where CPython refuses. "A U32 shift is not an error, it is a smaller
    number"; an empty type field is not an error either, it is a kernel ptxas rejects.
    ⇒ THE EMPTIED FIELD IS THE SIX EMPTY-STRING DTYPES -- these 18 rows and
    `f33_bf16cast.r1` (`%cast__0`) -- AND NOT weakint and weakfloat, whose port answers are
    legal PTX types. The refusal is the same; only the EMPTINESS is not.

  GROUP 2 -- `<f>.mod`, 35 rows. CARVE-OUT, and the shape is the point. `string_rewrite` is
    NOT PORTED, so the module cannot be compared; a divergence that says so in one pinned
    string per fixture is the honest record, and the pin means the day the port grows a
    module this gate goes red until the row leaves DIVERGES. TWENTY-NINE of the thirty-five
    are `ABSENT`; the other SIX are a REFUSAL, and they are not one thing:
      * `f31`, `f32`, `f33` -- CPython refuses at ptx.py:181 (the dtype tables above) and
        the port ANSWERS. GROUP 1 reaching the walk.
      * `f34` -- CPython refuses at ptx.py:92, and NOT on a dtype: the ALU rule reads
        `ctx.r[v]` for a CONST source and ptx.py:187 SKIPS CONSTs, so the register map has
        no entry for a CONST. The port's WALK agrees with CPython's walk here.
      * `f35` -- CPython refuses at ptx.py:225, because no `string_rewrite` rule matches a
        LOAD whose source is an un-indexed PARAM. The port has no string_rewrite stage to
        refuse IN, so it answers: the SAME gap as the twenty-nine, on the refusal side.
      * `f08` -- BOTH refuse: CPython at ptx.py:204, the port at its own INDEX arm. The row
        diverges only in the SPELLING of the refusal.

  GROUP 3 -- the walk, 5 rows. FINDING, NOT A CARVE-OUT: the five registers the port
    allocates where CPython refuses. `f31_weakint.r1`, `f32_weakfloat.r2` and
    `f33_bf16cast.r1` are GROUP 1 reaching the walk and CPython refuses at ptx.py:181;
    `f34_boolalu.r3` and `.r4` are NOT -- CPython refuses at ptx.py:92, for the CONST
    reason above, and the port's walk is RIGHT and CPython's walk agrees with it.

  GROUP 3a WAS HERE AND IT IS FIXED. `ptx.bend`'s alias arm was `case 2: Wal.rput(w,
    rg_at(w, 0))`, and `rg_at(w, 0)` reads `Wal.r[0]` -- STEP ZERO -- where ptx.py:190
    (`self.r[u] = self.r[u.src[0]]`) and ptx.py:205 (`r[u.src[0]][u.src[1].src[0].val]`)
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

AND THE CITATIONS ARE CHECKED TOO, because A CITATION IS A CLAIM AND A CLAIM NOBODY
CHECKS IS A LABEL. Every `ptx.py:NNN` in this census's five files is DECLARED -- which
citations each file makes, IN ORDER, and what the cited line CARRIES -- and `cites_hold()`
reads the tree and says whether the two agree. The audit that added it found FIFTY-FIVE of
the port's upstream-line references stale by one -- FORTY `ptx.py:NNN` citations, NINE ARM
SELECTOR rows and SIX bare continuations -- all from ONE upstream line INSERTED by
`975127a10`.
`cites_hold()` is red when a file's citations are not the declared ones (a citation that
MOVED, one ADDED, one DROPPED), when a cited line no longer carries what the declaration
names (UPSTREAM MOVED), and when what the declaration names is no longer UNIQUE to the line
it names. `--plant` moves one citation off the line it claims and the gate must go RED; a
comment that adds prose must move NOTHING.
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
# 2 `.reg` + `.entry`): ptx.py:205's `r[u.src[0]]` read whose `src[0]` is NOT at step zero,
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
            # f35 IS THE SIXTH, AND IT IS NOT A PORT DEFECT: ptx.py:225 refuses an
            # UN-INDEXED PARAM load -- no `string_rewrite` rule matches a LOAD whose
            # source is a PARAM rather than an INDEX -- and the PORT ANSWERS, because the
            # port has no string_rewrite stage to refuse IN. MEASURED: the port's own
            # answer is `PORT-ANSWERED`, which is the word for "CPython refused and the
            # port did not", so the sentence that used to sit here -- "the PORT ALSO
            # refuses" -- CONTRADICTED THE VALUE BESIDE IT. It is here so the census's
            # count of refusals is six rather than five and a seventh is red.
            "f35_loadvec": "PORT-ANSWERED"}

# GROUP 3 -- the walk.
# GROUP 3a IS GONE AND IT IS NOT A CARVE-OUT: `ptx.bend`'s alias arm read `Wal.r[0]`,
# STEP ZERO, where ptx.py:190 (`self.r[u] = self.r[u.src[0]]`) and ptx.py:205
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
# GROUP 3b -- THE REGISTERS THE PORT ALLOCATES WHERE CPython REFUSES. THESE ARE THE
# FINDING'S ACTUAL STRINGS, AND THEY STAY. THE REASON IS NOT ONE REASON: `f31_weakint.r1`,
# `f32_weakfloat.r2` and `f33_bf16cast.r1` are GROUP 1 reaching the walk and CPython
# refuses at ptx.py:181 on the dtype; `f34_boolalu.r3` and `.r4` are NOT GROUP 1 -- CPython
# refuses at ptx.py:92, on a CONST the walk never registered, and the port's walk AGREES
# with CPython's there. AND ONLY ONE OF THE FIVE EMPTIES A FIELD: `f33_bf16cast.r1` is
# `%cast__0`, an empty type where a real one belongs, while `%ridx_s32_0` and `%alu_f32_0`
# are LEGAL PTX types -- weakint and weakfloat are dtypes CPython refuses and the port
# answers, and the answer is not an emptied field. This unit is not `tc_ptx.bend`'s.
WEAK = {"f31_weakint.r1": "%ridx_s32_0", "f32_weakfloat.r2": "%alu_f32_0",
        "f33_bf16cast.r1": "%cast__0", "f34_boolalu.r3": "%alu_pred_1",
        "f34_boolalu.r4": "{%alu_pred_0, %alu_pred_1}"}


# =====================================================================================
# THE REASONS. EVERY DECLARED DIVERGENCE CARRIES ONE, AND EVERY REASON IS CHECKED.
# =====================================================================================
# A DECLARED DIVERGENCE IS A PIN, AND A PIN WITHOUT A TRUE REASON IS A PIN THAT CANNOT
# FAIL. `gatekit` pins both sides of every declared row, so a divergence whose VALUE moves
# is red -- and the REASONS were PROSE, so a reason that stopped being true was not. The
# three reasons are DATA now, and `reasons_hold()` reads the tree for each of them:
#
#   * THE DTYPE TABLES. `PTXRenderer.types` and its two siblings are DICTS of 12 KEYS, so
#     a dtype they do not name is a `KeyError` at ptx.py:181, and the port's three tables
#     answer the EMPTY STRING for exactly six dtypes: `void`, `bfloat16` and the four fp8s.
#   * THE MODULE. upstream's `ptx.py` renders a WHOLE PTX MODULE whose BODY is
#     `string_rewrite`'s rules, and the port has no such stage, so it answers ABSENT.
#   * A REFUSAL. Six fixtures are ones CPython REFUSES, and each refusal has a SITE in
#     upstream's source. The site is the WITNESS and it is read from CPython's OWN
#     traceback, so a re-vendor that MOVES a refusal is red with the move named.
#
# `REASON_RULES` IS THE NUMBER THE REASON CITES, AND `ABSENT` IS THE PORT'S OWN ANSWER --
# so the number lives in two files and in two places here, and BOTH are checked:
# `reasons_hold()` against upstream's own rule table and against the number inside `ABSENT`,
# and `gatekit`'s pin against the lane the driver wrote.
REASON_DTYPE_KEYS = 12
REASON_RULES = 23
ABSENT = "ABSENT:string_rewrite(23) not ported"
# THE REFUSAL SITES: fixture -> (the exception, a fragment of its KEY when it has one, and
# a fragment of the SOURCE LINE it refuses on). The line is never typed here -- it is read
# from the traceback -- so the reason moves with the code instead of with the file.
REASON_REFUSALS = {
  "f08_refuse":    ("RuntimeError", "", "dynamic register indexing"),
  "f31_weakint":   ("KeyError", "weakint", "self.types[unwrap(u).dtype]"),
  "f32_weakfloat": ("KeyError", "weakfloat", "self.types[unwrap(u).dtype]"),
  "f33_bf16cast":  ("KeyError", "bf16", "self.types[unwrap(u).dtype]"),
  "f34_boolalu":   ("KeyError", "Ops.CONST", "ctx.r[v] for v in x.src"),
  "f35_loadvec":   ("RuntimeError", "", "failed to render"),
}

_ORACLE_MOD = None  # the oracle, imported BY PATH, and only when a reason needs its fixtures


def _oracle_mod():
    """THE ORACLE, IMPORTED, so the FIXTURES are its own and not a second copy of them."""
    global _ORACLE_MOD
    if _ORACLE_MOD is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location("ptx_census_oracle", ORACLE)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _ORACLE_MOD = mod
    return _ORACLE_MOD


def _refusal_site(fixture):
    """WHERE CPython REFUSES a fixture, AND WHAT IT REFUSES ON.

    CPython's OWN traceback, on the ORACLE's OWN graph, through the oracle's OWN `render`
    call -- so the site is the site CPython refuses at TODAY and not a line number typed
    here. The LAST frame is the one that raised.
    """
    import traceback
    from tinygrad.uop.ops import UOp, Ops, KernelInfo
    mod = _oracle_mod()
    for name, build, fname in mod.FIXTURES:
        if name != fixture:
            continue
        root = build()
        sink = UOp(Ops.SINK, src=root if isinstance(root, tuple) else (root,),
                   arg=KernelInfo(fname if fname is not None else "test"))
        try:
            mod.R.render(list(sink.toposort()))
        except Exception as e:
            fr = traceback.extract_tb(e.__traceback__)[-1]
            return type(e).__name__, (str(e.args[0]) if e.args else ""), fr.filename, fr.lineno, fr.line
        return None
    return None


def _row_reasons():
    """EVERY DECLARED ROW'S REASON, AND THE REASON IS A FUNCTION OF THE ROW.

    A refusing fixture's reason is its refusal's SITE, for the MODULE row and for the
    walk's registers alike, because CPython's refusal is what makes BOTH of them differ.
    The twenty-nine module rows the port answers ABSENT carry the string_rewrite reason.
    """
    out = {}
    for k in _G1:
        out[k] = "DTYPES"
    for k in _G2:
        out[k] = "REFUSAL:" + k.split(".")[0]
    for k, (_py, port) in _G3.items():
        out[k] = "STRING_REWRITE" if port.endswith("not ported") else "REFUSAL:" + k[:-4]
    return out


def reasons_hold() -> bool:
    """THE REASONS, CHECKED AGAINST THE TREE. THE CHECK THAT MAKES A REASON A PIN.

    A declared divergence is a PIN, and a pin without a true reason is a pin that cannot
    fail. The gate already goes red when a divergence's VALUE moves -- `gatekit` pins both
    sides of every declared row -- and it stayed green through a whole audit in which
    eighteen of the reasons did not match the tree, because a reason was PROSE. Four
    witnesses, and every one of them is a READ of the tree:
      * upstream's own rule table, for the number of `string_rewrite` rules;
      * upstream's own dtype table, for its size;
      * CPython's own traceback, for WHERE each of the six refusals happens;
      * the ORACLE'S OWN `.mod` rows, for WHICH fixtures refuse -- so a fixture that
        starts refusing and has no declared reason is red, and a declared reason for a
        fixture that stopped refusing is red.
    """
    import tinygrad.renderer.ptx as ptx
    bad = []
    rules = len(ptx.string_rewrite.patterns)
    if rules != REASON_RULES:
        bad.append(f"the reason says upstream's ptx.py has {REASON_RULES} string_rewrite rules; "
                   f"it has {rules}")
    # THE NUMBER INSIDE THE PORT'S OWN ANSWER, so the two copies of it cross-check. A copy
    # nobody compares with anything is a copy that goes stale.
    said = re.search(r"string_rewrite\((\d+)\)", ABSENT)
    if said is None or int(said.group(1)) != REASON_RULES:
        bad.append(f"the port's own answer says {said.group(1) if said else 'no'} rules and the "
                   f"reason says {REASON_RULES}")
    keys = len(ptx.PTXRenderer.types)
    if keys != REASON_DTYPE_KEYS:
        bad.append(f"the reason says CPython's dtype table has {REASON_DTYPE_KEYS} keys; it has "
                   f"{keys}")
    refusing = {k[:-4] for k, v in _PY_ROWS.items() if k.endswith(".mod") and v.startswith("REFUSE:")}
    for f in sorted(refusing - set(REASON_REFUSALS)):
        bad.append(f"{f} refuses and NO REASON is declared for it")
    for f, (exc, key, frag) in REASON_REFUSALS.items():
        site = _refusal_site(f)
        if site is None:
            bad.append(f"{f} does not refuse any more -- the declared reason is stale")
            continue
        etype, arg, filename, lineno, line = site
        if etype != exc:
            bad.append(f"{f} refuses with {etype}; the reason says {exc}")
        if key and key not in arg:
            bad.append(f"{f} refuses on {arg!r}; the reason says {key!r}")
        if frag not in line:
            bad.append(f"{f} refuses at {filename}:{lineno}, whose source does not carry "
                       f"{frag!r} -- the declared SITE moved")
    for k in DIVERGES:
        if k not in _row_reasons():
            bad.append(f"{k} is a declared divergence with NO REASON")
    if bad:
        print("ptx_render_census-gate: REASONS: " + "; ".join(bad[:4]), file=sys.stderr)
    return not bad


def module_divergences(py):
    d = {}
    for f in FIXTURES:
        k = f"{f}.mod"
        # `gatekit` pins WHOLE LINES, not values -- MEASURED: a value-only pin answers
        # "py's f01_alu.mod is not '.version VERSION\n...'" with the row NAME missing off
        # the front, which is a pin no line can ever satisfy.
        d[k] = (f"{k}={py[k]}", f"{k}=" + REFUSALS.get(f, ABSENT))
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

# 62 -> 58. GROUP 3a EMPTIED: `ptx.bend`'s alias arm read `Wal.r[0]` where ptx.py:190 and
# ptx.py:205 read `r[u.src[0]]`, six rows diverged, the fix landed, and the six are now
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

# THE HONEST COMPOSITION OF THE TABLE, DERIVED FROM THE TABLE AND NOT TYPED: how many rows
# carry each REASON, and how the module rows divide between the three answers the port has.
_REASONS = _row_reasons()
_N_DTYPES = sum(1 for v in _REASONS.values() if v == "DTYPES")
_N_RULES = sum(1 for v in _REASONS.values() if v == "STRING_REWRITE")
_N_ANSWERED = sum(1 for _k, (_p, port) in _G3.items() if "PORT-ANSWERED" in port)
_N_REFUSED = sum(1 for _k, (_p, port) in _G3.items() if "PORT-REFUSED" in port)

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
    rp = reason_plant()
    if rp == 3:
        return 3
    bad += rp
    cp = cite_plant()
    if cp == 3:
        return 3
    bad += cp
    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return 1 if bad else 0


# ---- the reason plant -------------------------------------------------------------------
# THE SUBJECT IS THIS FILE, because this file is where the REASON is declared.
#
# THE PLANT PUTS A STALE REASON INTO A COPY OF THIS FILE AND THE GATE MUST GO RED. The
# bytes come from the WORKING TREE and never from `git show HEAD:` -- a plant that reads
# HEAD plants nothing the moment HEAD carries the fix, and this fix IS in HEAD's future BY
# CONSTRUCTION: the fix and the plant are the same commit.
#
# THE COPY SITS IN `gates/` BESIDE THIS ONE, so `HERE` and `ROOT` still resolve and the
# copy IS this gate -- the same lanes, the same population, the same pins.
REASON_SCRATCH = HERE / "_ptxreason_plantcase.py"
# THE STALE REASON IS A SOURCE FRAGMENT AND NOT A LINE NUMBER: the declared site of f31's
# refusal, moved to a fragment upstream does not refuse on. A line number would be a bet on
# a byte offset; the fragment is a bet on the CODE, which is what the reason actually
# claims.
REASON_PLANT_FROM = '"weakint", "self.types[unwrap(u).dtype]"'
REASON_PLANT_TO = '"weakint", "self.types[u.dtype]"'
# THE SECOND STALE REASON: the NUMBER of upstream's rules, moved by one. It is a number the
# gate reads against upstream's own rule table, so it is a reason that can fail on a
# re-vendor -- and the pin on the port's own answer does NOT see it, because the answer
# did not move.
REASON_RULES_FROM = "REASON_RULES = 23"
REASON_RULES_TO = "REASON_RULES = 24"
# THE CONTROL'S ANCHOR IS A DECLARATION LINE and the comment goes on a LINE OF ITS OWN
# above it -- the most comment-only edit there is, and the one the blank-line-dropping
# proof exists for.
REASON_CONTROL_ANCHOR = "REASON_DTYPE_KEYS = 12"
REASON_CONTROL_EDIT = ("# a comment on a line of its own, above the declaration it belongs to\n"
                        + REASON_CONTROL_ANCHOR)


def reason_plant() -> int:
    """THE REASON PLANT, ITS CONTROL, AND THE PROOF THAT THE CONTROL MOVED NOTHING.

    THE PLANT writes a COPY of this file with a STALE REASON in it -- the declared site of
    f31's refusal, moved to a fragment upstream does not refuse on -- and the gate MUST GO
    RED AND SAY SO. A reason that nothing reads is a pin that cannot fail, and this is
    the proof that the reason IS read.

    THE CONTROL is a comment on a line of its own in the SAME file, and it must move
    NOTHING. The proof that it moved nothing is the COMMENT-STRIPPED BYTES with the BLANK
    LINES DROPPED -- `_code_only()`, which is `checks/port-compile-gate.py`'s own
    `strip_comments()` plus the blank-line drop, and the drop is what makes the proof
    cover a WHOLE-LINE comment at all.
    """
    original = Path(__file__).read_text()
    if REASON_PLANT_FROM not in original:
        print("REFUSED: the plant's anchor is not in this file as it stands. THE PLANT IS A "
              "TEXT EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
              "re-anchored -- NOT that it should fall back to reading git.")
        return 3
    if REASON_CONTROL_ANCHOR not in original:
        print("REFUSED: the control's anchor is not in this file as it stands.")
        return 3
    if REASON_RULES_FROM not in original:
        print("REFUSED: the rule-count anchor is not in this file as it stands.")
        return 3
    cases = [
        ("PLANT (the declared refusal site moved)",
         original.replace(REASON_PLANT_FROM, REASON_PLANT_TO, 1),
         "a declared reason that no longer matches the tree"),
        ("PLANT (the declared rule count moved)",
         original.replace(REASON_RULES_FROM, REASON_RULES_TO, 1),
         "a declared number upstream's own rule table disagrees with"),
        ("CONTROL (a comment on a line of its own)",
         original.replace(REASON_CONTROL_ANCHOR, REASON_CONTROL_EDIT, 1),
         "a comment-only edit in the SAME file, which must move NOTHING"),
    ]
    bad = 0
    try:
        for name, text, why in cases:
            REASON_SCRATCH.write_text(text)
            r = subprocess.run([str(PY), str(REASON_SCRATCH)], capture_output=True, text=True)
            same_code = _code_only(text) == _code_only(original)
            print(f"{name:<52} rc={r.returncode} comment-only={same_code!s:<5} {why}")
            if name.startswith("PLANT"):
                if r.returncode == 0:
                    print("  THE PLANT DID NOT FIRE: a stale reason left the gate GREEN.")
                    bad += 1
                elif "REASONS" not in r.stderr:
                    print("  THE PLANT FIRED FOR SOMETHING ELSE: " + r.stderr.strip()[:160])
                    bad += 1
            if name.startswith("CONTROL"):
                if r.returncode != 0:
                    print("  THE CONTROL IS NOT A CONTROL: a comment moved the verdict "
                          f"(rc={r.returncode}): {r.stderr.strip()[:160]}")
                    bad += 1
                if not same_code:
                    print("  THE CONTROL IS NOT A CONTROL: it edited more than a comment.")
                    bad += 1
    finally:
        REASON_SCRATCH.unlink(missing_ok=True)
    return bad


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


# ---- the citations ---------------------------------------------------------------------
# EVERY `ptx.py:NNN` IN THIS CENSUS'S OWN FIVE FILES IS A CLAIM ABOUT UPSTREAM'S `ptx.py`,
# AND A CLAIM NOBODY CHECKS IS A LABEL. THE AUDIT THAT PRODUCED THIS SECTION FOUND FIFTY-
# FIVE OF THE PORT'S UPSTREAM-LINE REFERENCES STALE BY ONE -- FORTY `ptx.py:NNN`
# CITATIONS, NINE ARM SELECTOR ROWS AND SIX BARE CONTINUATIONS -- AND THE CAUSE WAS ONE
# LINE: upstream `975127a10` ("use AFTER for RANGE ordering deps instead of multiple srcs",
# #18618) INSERTED ONE LINE at upstream's 189, and every reference to a line at or after it
# moved by one. A re-vendor does that again, and until this section NOTHING IN THE TREE WAS
# WATCHING.
#
# THE DECLARATION IS TWO TABLES, AND THE SECOND ONE IS THE ONE THAT DOES THE WORK:
#   * `PTX_CITE_CONTENT` -- what a cited LINE CARRIES: a fragment of the line, and for a
#     SPAN the text of the line that ENDS it. The fragment must be UNIQUE to the line it
#     names, so the declaration can tell a line from its neighbour.
#   * `PTX_CITE_ORDER` -- WHICH CITATIONS EACH FILE MAKES, AND IN WHICH ORDER. THE ORDER
#     IS THE PIN. A citation's number is a claim about a LINE, and a claim that survives
#     being edited onto a DIFFERENT line is not a claim: keyed by the line alone, every
#     citation could be moved onto any other line that carries some content and the check
#     would still be green. Keyed by the ORDER, a citation that moves is red.
#
# SO A CITATION CAN BE WRONG IN THREE WAYS, AND ALL THREE ARE CHECKED:
#   1. the file's citations are not the declared ones -- one MOVED, one ADDED, one DROPPED;
#   2. a cited line no longer carries what the declaration names -- UPSTREAM MOVED;
#   3. the content the declaration names is no longer UNIQUE to the line it names.
#
# AND THE ORDER IS NOT A STRAWMAN: it is the property the audit's own failure had. The
# audit moved fifty-five numbers and found the moves WRONG, because a number is a
# claim about a LINE and the line is what upstream moved.
UPSTREAM_PTX = ROOT / "tinygrad" / "renderer" / "ptx.py"
# THE POPULATION IS DISCOVERED BY A REGEX OVER THE TREE'S OWN WRITE SITES, never by a hand
# list of CITATIONS: these five files are the ones that CITE upstream's `ptx.py`, and the
# regex finds every citation in each of them, in order.
#
# AND THE POPULATION IS THE `ptx.py:NNN` FORM, WHICH IS A NAMED LIMIT AND NOT A CLAIM OF
# COMPLETENESS: the prose ALSO carries BARE upstream-line references -- the ARM SELECTOR's
# eleven rows, a `ptx.py:NNN, NNN-NNN` continuation, a `ptx.py:NNN and NNN` continuation
# and a `ptx.py:NNN/NNN` one -- and those are NOT in the population, because a bare number
# in prose is indistinguishable from a row count and a regex that tried would be a LIST OF
# SHAPES rather than a discovery. THEY WERE AUDITED BY HAND, IN THE SAME PASS, AND THEY
# MOVED WITH THE SAME +1; they are NOT CHECKED. THAT IS THE BLIND SPOT, AND IT IS NAMED SO
# A READER CAN SEE IT INSTEAD OF ASSUMING IT IS NOT THERE.
CITE_FILES = (
    ("port",   ROOT / "tinybendygrad" / "renderer" / "ptx.bend"),
    ("driver", HERE / "ptx_render_census.bend"),
    ("oracle", ORACLE),
    ("gate",   HERE / "ptx_render_census-gate.py"),
    ("gen",    HERE / "ptx_render_census-gen.py"),
)
CITE_RE = re.compile(r"ptx\.py:(\d+)(?:-(\d+))?")
# WHAT EACH CITED LINE CARRIES. MEASURED against upstream's `ptx.py` as it stands, and the
# check RE-MEASURES it on every run -- a fragment that stops being unique, or stops being
# on the line it names, is RED, which is how a re-vendor announces itself.
PTX_CITE_CONTENT = {
  "24-28":      ("Ops.ADD: lambda d,a,b,dt,name:", "Ops.OR: lambda d,a,b,dt, name: f\"or.pred {d}, {a}, {b};\" if dt == dtypes.bool else f\"or.b{name[1:]} {d}, {a}, {b};\","),
  "40-57":      ("ptx_matcher = PatternMatcher([", "])"),
  "42":         ("(UPat.var('x', dtype=dtypes.bool).ne(UPat.var('y'))", None),
  "49-51":      ("(UPat(Ops.LOAD, dtypes.bool, src=(UPat(name=\"idx\"),), name=\"x\", allow_any_len=True)", "+ x.src[2:]).cast(dtypes.bool) if idx.addrspace != AddrSpace.REG else None),"),
  "81-135":     ("string_rewrite = PatternMatcher([", "])"),
  "83":         ("UPat.cvar(\"c\").cast(name=\"x\")", None),
  "92":         ("(UPat(GroupOp.ALU, name=\"x\")", None),
  "99-101":     ("(UPat(Ops.STORE, src=(UPat(name=\"loc\"), UPat.var(\"var\"))), lambda ctx, loc, var:", "if loc.addrspace == AddrSpace.REG else None),"),
  "99-105":     ("(UPat(Ops.STORE, src=(UPat(name=\"loc\"), UPat.var(\"var\"))), lambda ctx, loc, var:", "f\"[{ctx.r[loc]}+0], {('{' + ', '.join(ctx.r[var]) + '}') if var.max_numel() > 1 else ctx.r[var]};\"),"),
  "102":        ("UPat((Ops.INDEX, Ops.SHRINK), name=\"loc\"), UPat.var(\"var\"))", None),
  "126":        ("(UPat(Ops.END, name=\"x\", src=(UPat(), UPat(Ops.RANGE, name=\"r\")))", None),
  "164":        ("def fmt(line): return", None),
  "165":        ("f\".reg .{reg.split('_')[-2]}", None),
  "166-167":    ("local_dims = [u.src[0] for u in uops if u.op is Ops.SPECIAL", "launch_bounds = prod([d.vmax for d in local_dims])"),
  "171-229":    ("def render(self, uops:list[UOp]) -> str:", "return self.render_kernel(kernel, name, bufs, c.items(), uops)"),
  "175":        ("c: defaultdict[str, int] = defaultdict(int)", None),
  "176":        ("r: dict[UOp, list[str]|str] = {}", None),
  "180-183":    ("def ssa(prefix:str, u:UOp|None=None, dtype:str|None=None) -> str:", "return f\"%{prefix}{c[prefix]-1}\""),
  "181":        ("self.types[unwrap(u).dtype]", None),
  "185":        ("name = \"test\"", None),
  "185-221":    ("name = \"test\"", "if prefix: r[u] = ssa(prefix, u, dtype)"),
  "186-221":    ("for u in uops:", "if prefix: r[u] = ssa(prefix, u, dtype)"),
  "187":        ("if u.op in {Ops.NOOP, Ops.CONST}: continue", None),
  "190":        ("self.r[u] = self.r[u.src[0]]", None),
  "193":        ("if u.arg is not None: name = u.arg.function_name", None),
  "196":        ("r[u] = [cast(str,r[x]) for x in u.src]", None),
  "198":        ("if u.op is Ops.BUFFER and u.addrspace == AddrSpace.REG:", None),
  "198-209":    ("if u.op is Ops.BUFFER and u.addrspace == AddrSpace.REG:", "r[u] = [ssa('val', dtype=self.types[u.dtype]) for _ in range(u.max_numel())] if u.max_numel() > 1 else ssa('val', u)"),
  "199":        ("ssa(\"reg\", u, self.types[u.dtype])", None),
  "201":        ("if u.op in {Ops.INDEX, Ops.SHRINK, Ops.LOAD} and u.src[0].addrspace in (AddrSpace.REG, AddrSpace.ALU):", None),
  "203":        ("if u.op is not Ops.LOAD and not (u.src[1].op is Ops.CAST and u.src[1].src[0].op is Ops.CONST):", None),
  "203-204":    ("if u.op is not Ops.LOAD and not (u.src[1].op is Ops.CAST and u.src[1].src[0].op is Ops.CONST):", "raise RuntimeError(f\"PTX does not support dynamic register indexing: {u}\")"),
  "203-205":    ("if u.op is not Ops.LOAD and not (u.src[1].op is Ops.CAST and u.src[1].src[0].op is Ops.CONST):", "r[u] = r[u.src[0]] if u.op is Ops.LOAD else r[u.src[0]][u.src[1].src[0].val]"),
  "204":        ("raise RuntimeError(f\"PTX does not support dynamic register indexing: {u}\")", None),
  "205":        ("r[u] = r[u.src[0]] if u.op is Ops.LOAD else r[u.src[0]][u.src[1].src[0].val]", None),
  "207":        ("if u.op is Ops.SPECIAL: r[u] = \"%\" + u.arg", None),
  "209":        ("ssa('val', dtype=self.types[u.dtype])", None),
  "210":        ("elif u.op is Ops.PARAM: bufs.append((f\"data{u.arg.slot}\", u))", None),
  "211-216":    ("elif u.op is Ops.WMMA:", "r[u] = [ssa(\"wmma\", dtype=self.types[u.dtype]) for _ in range(u.max_numel())]"),
  "217":        ("prefix, dtype = {Ops.CAST: (\"cast\", None)", None),
  "217-219":    ("prefix, dtype = {Ops.CAST: (\"cast\", None)", "Ops.PARAM: (\"dat\", \"u64\" if u.addrspace is AddrSpace.GLOBAL else None), **{op: (\"alu\", None) for op in GroupOp.ALU}}.get(u.op, (None, None))"),
  "220":        ("if u.op is Ops.RANGE and u.dtype == dtypes.void: prefix = None", None),
  "221":        ("if prefix: r[u] = ssa(prefix, u, dtype)", None),
  "223":        ("l: str|list[str]|None = string_rewrite.rewrite(u, ctx=self)", None),
  "225":        ("raise RuntimeError(f\"failed to render {u.op} with {u.dtype} srcs", None),
  "228":        ("if u.op is Ops.SPECIAL: kernel = [f\".reg .u32 %{u.arg};\"] + kernel", None),
  "229":        ("return self.render_kernel(kernel, name, bufs, c.items(), uops)", None),
  "232":        ("d not in dtypes.fp8s+(dtypes.bfloat16,)", None),
}
# WHICH CITATIONS EACH FILE MAKES, IN ORDER. MEASURED from the files as they stand, and the
# check compares them on every run: a file whose citations are not THESE is red, and the
# first difference is NAMED -- which file, which citation, what it says now, what it said.
PTX_CITE_ORDER = {
  "port": ("171-229", "180-183", "185-221", "165", "210", "185", "204", "81-135", "40-57", "42", "211-216", "223", "205", "209", "204", "176", "175", "228", "205", "204", "205", "203", "180-183", "199", "217-219", "198-209", "220", "201", "220", "186-221", "204", "198", "203-205", "196", "205", "190", "205", "193", "207", "185", "221", "198-209", "204", "229", "165", "228", "204", "83", "209", "199", "181", "228"),
  "driver": ("40-57", "164", "204", "187", "209", "223", "209", "181", "217", "181", "187", "181", "187", "92", "204"),
  "oracle": ("203", "203", "204", "126", "225", "201", "203-204", "166-167", "187", "203", "203", "204", "225", "209", "209", "217", "220", "99-105", "102", "49-51", "217", "181", "187", "187", "181", "232", "181", "209", "99-101", "205", "205", "205", "24-28", "181", "204", "225", "209", "223", "181", "204", "209", "176", "187", "165", "164"),
  "gate": ("164", "181", "181", "92", "187", "225", "204", "181", "92", "190", "205", "205", "225", "190", "205", "181", "92", "181", "190", "205", "164", "164", "181", "181", "92", "225", "164", "190"),
  "gen": ("199", "201"),
}


def _cite_keys(text):
    """EVERY CITATION IN A TEXT, IN ORDER, AS THE KEY THE DECLARATION USES.

    A SPAN is `a-b` and a SINGLE LINE is `a`, and the two are different declarations: the
    span's END is a line of its own, and it carries its own text.
    """
    out = []
    for m in CITE_RE.finditer(text):
        a = int(m.group(1))
        b = int(m.group(2) or a)
        out.append(f"{a}-{b}" if b != a else str(a))
    return out


def _cite_problems(files=None, upstream=None):
    """EVERY WAY A CITATION CAN BE WRONG, AS A LIST OF SENTENCES.

    The ORDER is compared first, because it is the only one of the three that can see a
    citation MOVED onto a line that is itself perfectly valid: the content check asks
    "does the cited line carry what the declaration says about THAT line", and a
    declaration is always true about its own line.
    """
    files = CITE_FILES if files is None else files
    up = UPSTREAM_PTX.read_text().split("\n") if upstream is None else upstream.split("\n")
    bad = []
    for fid, path in files:
        want = PTX_CITE_ORDER.get(fid)
        if want is None:
            bad.append(f"{fid}: NO DECLARATION of its citations")
            continue
        got = tuple(_cite_keys(path.read_text()))
        if got != want:
            i = next((i for i in range(max(len(got), len(want)))
                      if i >= len(got) or i >= len(want) or got[i] != want[i]), 0)
            said = got[i] if i < len(got) else "ABSENT"
            declared = want[i] if i < len(want) else "ABSENT"
            bad.append(f"{fid}: citation {i+1} says ptx.py:{said}, the declaration says "
                       f"ptx.py:{declared} ({len(got)} citations in the file, {len(want)} declared)")
            continue
        for key in got:
            decl = PTX_CITE_CONTENT.get(key)
            if decl is None:
                bad.append(f"{fid}: ptx.py:{key} has NO DECLARED CONTENT")
                continue
            a, b = (int(x) for x in key.split("-")) if "-" in key else (int(key), int(key))
            anchor, end = decl
            if not (1 <= a <= len(up)) or not (1 <= b <= len(up)) or a > b:
                bad.append(f"{fid}: ptx.py:{key} is OUTSIDE upstream's {len(up)}-line file")
                continue
            if anchor not in up[a-1]:
                bad.append(f"{fid}: ptx.py:{key} -- line {a} does not carry {anchor!r}")
            hits = [i+1 for i, l in enumerate(up) if anchor in l]
            if hits != [a]:
                bad.append(f"{fid}: ptx.py:{key} -- {anchor!r} is on lines {hits}, not only {a}")
            if end is not None:
                if up[b-1].strip() != end:
                    bad.append(f"{fid}: ptx.py:{key} -- line {b} does not carry {end!r}")
                hits = [i+1 for i, l in enumerate(up) if a <= i+1 <= b and l.strip() == end]
                if hits != [b]:
                    bad.append(f"{fid}: ptx.py:{key} -- {end!r} is on lines {hits} of the span, "
                               f"not only {b}")
    return bad


def cites_hold() -> bool:
    """THE CITATIONS, CHECKED AGAINST UPSTREAM. THE CHECK THAT MAKES A CITATION A PIN.

    A citation is a CLAIM, and this is the check that reads the claim and the tree and
    says whether they agree. It is RED when a file's citations are not the declared ones,
    when a cited line no longer carries what the declaration names, and when what the
    declaration names is no longer unique to the line it names.
    """
    try:
        bad = _cite_problems()
    except OSError as exc:
        print(f"ptx_render_census-gate: CITES: {exc}", file=sys.stderr)
        return False
    if bad:
        print("ptx_render_census-gate: CITES: " + "; ".join(bad[:4]), file=sys.stderr)
        return False
    return True


# ---- the cite plant --------------------------------------------------------------------
# THE SUBJECT IS THE ORACLE, and the defect is a citation that MOVED OFF THE LINE IT
# CLAIMS. THE BYTES COME FROM THE WORKING TREE and never from `git show HEAD:` -- a plant
# that reads HEAD plants nothing the moment HEAD carries the fix, and this fix IS in HEAD's
# future BY CONSTRUCTION: the fix and the plant are the same commit.
CITE_SCRATCH = HERE / "_ptxcite_plantcase.py"
# THE LINE THE CITATION CLAIMS, AND THE LINE IT IS MOVED ONTO. Upstream's 181 is the dtype
# lookup -- `self.types[unwrap(u).dtype]` -- the line that RAISES `KeyError` for a dtype the
# table does not name. Upstream's 182 is `c[prefix] += 1`, the `ssa` COUNTER. So the moved
# citation names a line that carries something else ENTIRELY, and the gate must notice that
# the claim moved with it.
#
# THE NUMBER IS AN INTEGER AND THE TEXT IS AN f-STRING, and that is not tidiness: a
# literal citation -- the file name, a colon, and a number -- IN THIS FILE would be a
# CITATION OF THIS FILE, because the population is DISCOVERED by a regex over the tree's
# own write sites, and the plant's whole subject is a COPY of another file. So this file
# holds no citation it does not mean.
CITE_PLANT_LINE = 181
CITE_PLANT_FROM = f"ptx.py:{CITE_PLANT_LINE}"
CITE_PLANT_TO = f"ptx.py:{CITE_PLANT_LINE + 1}"
# THE CONTROL'S ANCHOR IS A `def` LINE, and the comment goes on a LINE OF ITS OWN above it --
# the most comment-only edit there is, and the one the blank-line-dropping proof exists for.
CITE_CONTROL_ANCHOR = "def F01_alu():"


def cite_plant() -> int:
    """THE PLANTS, THE CONTROL, AND THE PROOF THAT THE CONTROL MOVED NOTHING.

    THE FIRST PLANT moves ONE citation off the line it claims and the gate MUST GO RED AND
    SAY SO. A citation that nobody checks is a label, and the label here is a line number
    that looks exactly like a claim.

    THE SECOND PLANT ADDS a claim in a comment, and the gate must go red too: the
    declaration says WHICH CLAIMS THE FILE MAKES, so a new one is a change nobody
    verified. THE POPULATION IS DISCOVERED, but the DECLARATION is what says the discovered
    population is the RIGHT one.

    THE CONTROL is a comment on a line of its own, in the SAME file, and it must move
    NOTHING. The proof that it moved nothing is the COMMENT-STRIPPED BYTES with the BLANK
    LINES DROPPED -- `_code_only()`, which is `checks/port-compile-gate.py`'s own
    `strip_comments()` plus the blank-line drop.

    AND THE PLANTS' EDITS ARE COMMENT EDITS TOO -- the citations live in PROSE, because a
    citation is a claim ABOUT upstream and a claim belongs in a comment. That is the POINT
    and not a loophole: the gate reads the CLAIM inside the comment, so a comment that
    MOVES a claim is red and a comment that ADDS PROSE is green, and the difference
    between the two is a claim and not a byte.
    """
    original = ORACLE.read_text()
    if CITE_PLANT_FROM not in original:
        print("REFUSED: the plant's citation is not in the oracle as it stands. THE PLANT IS "
              "A TEXT EDIT ON THE WORKING TREE, so an anchor that moved means the plant must "
              "be re-anchored -- NOT that it should fall back to reading git.")
        return 3
    if CITE_CONTROL_ANCHOR not in original:
        print("REFUSED: the control's anchor is not in the oracle as it stands.")
        return 3
    cases = [
        ("PLANT (one citation moved off the line it claims)",
         original.replace(CITE_PLANT_FROM, CITE_PLANT_TO, 1),
         "a citation that names a line it does not claim"),
        ("PLANT (a NEW citation added by a comment)",
         original.replace(CITE_CONTROL_ANCHOR,
                          "# a comment that adds a claim: ptx.py:" + str(CITE_PLANT_LINE) +
                          "\n" + CITE_CONTROL_ANCHOR, 1),
         "a claim the declaration does not carry"),
        ("CONTROL (a comment on a line of its own)",
         original.replace(CITE_CONTROL_ANCHOR,
                          "# a comment on a line of its own\n" + CITE_CONTROL_ANCHOR, 1),
         "a comment-only edit in the SAME file, which must move NOTHING"),
    ]
    bad = 0
    try:
        for name, text, what in cases:
            CITE_SCRATCH.write_text(text)
            problems = _cite_problems([("oracle", CITE_SCRATCH)])
            same_code = _code_only(text) == _code_only(original)
            print(f"{name:<62} cites={'RED' if problems else 'green':<5} "
                  f"comment-only={same_code!s:<5} {what}")
            for p in problems[:2]:
                print(f"{'':<62} :: {p}")
            if name.startswith("PLANT"):
                if not problems:
                    print("  THE PLANT DID NOT FIRE: a claim moved and nothing went red.")
                    bad += 1
            if name.startswith("CONTROL"):
                if problems:
                    print("  THE CONTROL IS NOT A CONTROL: it moved the verdict.")
                    bad += 1
                if not same_code:
                    print("  THE CONTROL IS NOT A CONTROL: it edited more than a comment.")
                    bad += 1
    finally:
        CITE_SCRATCH.unlink(missing_ok=True)
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
    # THE MODULE ROWS HAVE EXACTLY THREE ANSWERS, AND THE THREE COUNTS ARE THE TABLE'S.
    assert _N_RULES + _N_ANSWERED + _N_REFUSED == len(_G3), (
        f"the module rows divide into {_N_RULES} ABSENT, {_N_ANSWERED} PORT-ANSWERED and "
        f"{_N_REFUSED} PORT-REFUSED, which is not {len(_G3)} -- a fourth answer appeared")
    sys.exit(gate(make_gate(),
                  f"ptx_render_census-gate: {ROWS} rows (READ FROM THE POPULATION, not typed), "
                  f"3 lanes byte-identical over the walk and the SEAM, {N_DIVERGES} DECLARED "
                  f"divergences -- ALL of them STILL REAL, and EVERY ONE OF THEM CARRIES A "
                  f"REASON THAT IS CHECKED AGAINST THE TREE. {_N_DTYPES} are the dtype tables, "
                  f"where CPython's {REASON_DTYPE_KEYS}-key dict raises KeyError at ptx.py:181 "
                  "and the port answers the EMPTY STRING (a field EMPTIED -- the PTX form of "
                  "the AMDWORD32 defect); "
                  f"{_N_RULES} are the module, which upstream renders from {REASON_RULES} "
                  "`string_rewrite` rules the port has none of; "
                  f"{_N_ANSWERED} are a REFUSAL CPython raises and the port answers (three of "
                  "them at ptx.py:181, one at ptx.py:92 on a CONST the walk never registered, "
                  "one at ptx.py:225 in the string_rewrite stage); "
                  f"{_N_REFUSED} are a refusal BOTH sides raise, so the row differs only in the "
                  f"SPELLING; and {len(_G2)} are the walk's registers the port allocates where "
                  "CPython refuses. `reasons_hold()` is what makes a reason a PIN: upstream's "
                  "own rule table, upstream's own dtype table, CPython's own traceback, and the "
                  "oracle's own refusals are the four witnesses, so a reason that stops "
                  "matching the tree is RED. The `fmt_18` row -- the port's `tc_ptx.bend` "
                  "passing a `$` line through untouched where the pin's `ptx.py:164` indents "
                  "EVERY line -- is FIXED and COMPARED, because upstream `96397341d` DELETED "
                  "that early return as DEAD CODE. The SIX rows that were ptx.bend's alias arm "
                  "reading Wal.r[0] where ptx.py:190 and :205 read r[u.src[0]] are FIXED and "
                  "COMPARED, `f37_twobufs` is the fixture whose INDEX carries a non-zero "
                  "src[0] and the only thing in the axis that can see the same wrong read in "
                  "`rg_pick`, and `f38_regload` is the one whose LOAD subscripts a LIST rather "
                  "than a scalar, which is what M9 needed. EVERY `ptx.py:NNN` CITATION IN "
                  "THESE FIVE FILES IS DECLARED -- WHICH citations each file makes, IN ORDER, "
                  "and what the cited line CARRIES -- so `cites_hold()` is red when a citation "
                  "MOVED, when a cited line no longer carries what the declaration names, and "
                  "when what the declaration names is no longer UNIQUE to the line it names",
                  checks=lambda: (reasons_hold() and names_hold() and axis_hold() and claims_hold()
                                  and pins_hold() and cites_hold())))