#!/usr/bin/env python3
"""wgsl_render_census-gate.py -- A RENDER CENSUS over
`tinybendygrad/renderer/wgsl.bend`, the port of `tinygrad/renderer/wgsl.py`.

    .venv/bin/python gates/wgsl_render_census-gate.py
    .venv/bin/python gates/wgsl_render_census-gate.py --refresh   # rewrites the pins

227 ROWS (the port's own `main()`), THREE LANES, 213 EXACT MATCHES AND
14 DECLARED DIVERGENCES IN 6 CLASSES. `string_rewrite` -- the renderer's
LARGEST surface, seventeen rules at wgsl.py:65-93 -- had NO ROWS AT ALL until
2026-10-14 and has 38 now; `rules_hold()` below is what says so on every run.
THE SEVENTEEN PATTERNS LANDED, SO THE SEVENTEEN `srneg` ROWS ARE EXACT MATCHES
AND NOT PINS: see the `RETIRED` constant, which is emitted into the pins header
because `--refresh` rewrites that header and had already eaten eight stories
written into it by hand.

WHICH INSTRUMENT, AND WHY THIS LAYER NEEDS ITS OWN.

The three that exist measure three different things. `gates/*_graph_census*`
compare an OP SEQUENCE; `gates/fold_graph_census*` compare a VALUE;
`gates/cstyle_render_census*` compare a rendered STRING but reach the renderer's
dispatch TABLES through eight ported C functions and are written for a
`CStyleLanguage` with SIX device classes. `gates/amd_dsl_census*` compare a
TRIPLE -- `(packed word, byte image, text)` -- because that is what an
expression algebra returns.

`wgsl.py` returns a FOURTH thing, and the printed form is designed from what it
returns rather than borrowed. MEASURED: `is_packed` returns a `bool`,
`packed_field` returns a `(UOp, UOp, int)` TRIPLE whose third element is an
`int`, `packed_store` returns a `UOp` whose `wmask` is a NODE and not an integer
at all, `is_nan` returns a `bool` over five INTEGERS buried in its own graph,
`type_map` / `code_for_op` / `code_for_workitem` / `render_cast` / `buf_map` /
`render_load` return STRINGS, `global_max` / `local_max` are `(int, int, int)`,
`supported_dtypes` is a `set[DType]`, and `render_kernel` returns the WHOLE
WGSL MODULE -- 700 characters with real newlines in it. So this is instrument
(4), a STRING census whose rows are the layer's OWN RETURN VALUES, printed as

    name=value

in each answer's own canonical text, with a module's newlines spelled `\\n` and
a refusal spelled `REFUSE:KeyError` / `GRAPH:...`. NEVER a prefix, never a
length, never a hash: `ops.bend`'s `Rng.sig` prints a 3-op prefix and no arg
and a deep node swap printed identically on both sides until a deeper printer
was used, and the same trap for a renderer is a `render_kernel` row that prints
its first line. `rk mixed` is 700 characters on ONE line and the line carries
all of them.

THE POPULATION IS DISCOVERED, ON BOTH SIDES, ON EVERY RUN, AND MUST AGREE.
`names_hold()` runs this gate's oracle and runs `wgsl.bend`, then asserts the
two row-NAME lists are EQUAL AND IN THE SAME ORDER -- so a row present on one
side only is red BEFORE any value is compared, and a row that quietly stopped
being printed is red too. `fixtures_hold()` goes one level further: it re-reads
the port's own fixture AXES out of `wgsl.bend`'s source text
(`r_pk8("uchar", S.uint8(), ...)`, `r_wm(255, 0, ...)`, `r_cfo1(O.OpsSQRT{})`,
`r_sd1("shader-f16")`, ...) and compares them to the oracle's axes name for name
and IN ORDER. That is the answer to "an oracle that covers whatever the port
happens to do is not an oracle": the axes are declared on BOTH sides and a
drift on either side is red.

`tinygrad/renderer/wgsl.py` HAS MOVED SINCE THE PIN `ad117c928^`, AND THE MOVE
TOUCHES WHAT THE ROWS READ. The blob was `02d7fdea` at `ad117c928^` and is
`c7121333` at HEAD; `git diff ad117c928^ HEAD -- tinygrad/renderer/wgsl.py` is
6 insertions and 6 deletions, and TWO of them are BEHAVIOUR: `string_rewrite`'s
rule 2 lost its negative-const arm (`f"bitcast<u32>({c.val})" if c.val < 0
else ...` became an unconditional `f"{c.val&0xFFFFFFFF}u"`) and the
`packed_rmw` store pattern gained a `CAST` on its source. **SO THE 227 ROWS
ARE A CAPTURE TAKEN AGAINST THE OLDER BYTES, AND THE ROW DIFF IS WHAT
RE-DECIDES THEM** -- the pin below is a TRIPWIRE on the bytes the oracle
imports, not a claim that the capture is current.

THE PIN IS A PIN ON BYTES, NOT ON A COMMIT, and it is checked against the
WORKING TREE. The old check compared `git rev-parse <rev>:<path>` at three
revisions, which answers a question about COMMITS and not about the file
`import tinygrad` opens, so a working tree whose bytes differ from every
revision it named still passed -- and it demanded that all three blobs be
EQUAL, which is a claim about the vendored tree and not about this gate's
rows. `DRIFT_PIN` holds the sha256 of the bytes the ORACLE IMPORTS and
`gates/gatekit.py:oracle_drift` re-measures them on every run -- the same
house mechanism `gates/ops_python_census-gate.py`,
`gates/onnx_census-gate.py`, `gates/rand_census-gate.py` and
`gates/state_census-gate.py` use.

**THE PIN AND THE OUTPUT CHECK ARE TWO INDEPENDENT FACTS, and neither is the
other.** The PIN checks the BYTES of the five `tinygrad/` files the oracle
imports: it is a fact about the INPUTS, and it goes red when a re-vendor
touches a byte of them -- including a comment, which is a fact about the file
and not about the behaviour. The OUTPUT CHECK is the 227-row diff between the
port's lane and CPython's oracle, and it is a fact about BEHAVIOUR: it goes
red when the port is wrong, and it stays green when a byte of `wgsl.py`
changes in a way no row reads. A pin that named the rows' own values would be
the same fact twice and could not fail; this one cannot, because its value is
a LITERAL in this file and the file the oracle opens is a different thing
from the rows it prints.

`grep -c OpsCAST tinybendygrad/renderer/wgsl.bend` = **3**, and all three are
triaged rather than counted by `never_folding_cast_hold()`:

  * `:334` `prw_cast` -- a PATTERN TEST (`op(ar,c) == OpsCAST{}`). Correct use.
  * `:575` `ssimp`    -- a PATTERN TEST (`op(ar,x) == OpsCAST{} && ss_is(src0)`).
  * `:838` `f_cast_dt` -- the ONE that MINTS, and it calls `O.UOp.new` DIRECTLY
    rather than `O.UOp.cast` (`ops.bend:2919`), so it mints whatever the
    arguments are. This is class (b), the never-folding CAST, and it is a
    FIXTURE defect with a measured consequence -- see FINDING 1 below.

THE FOUR DIVERGENCE CLASSES. Each is measured, each has a reason, and none of
them is a formatting slip.

  * `UNHANDLED_ARM` -- `code_for_op LOAD/MAX/POW`. `WGSLRenderer.code_for_op`
    is `{**CStyleLanguage.code_for_op, Ops.WHERE: ...}`, so an op with no arm is
    a `KeyError` in CPython. Bend is total, and the port answers
    `UNHANDLED(Ops.LOAD)` -- a call to nothing, which cannot compile. CARVE-OUT,
    and the RIGHT totalization: the same port answers `(A/B)` for FDIV, which
    is a different totalization of the SAME exception (see FINDING 2).
  * `MISSING_ARM` -- `code_for_op FDIV`. MEASURED: `Ops.FDIV` is in
    `ClangRenderer.code_for_op` and NOT in `WGSLRenderer.code_for_op`, and
    `wgsl.bend:441-448` records the same measurement. `axes_hold()` re-derives
    the set difference on every run and asserts it is EXACTLY `{Ops.FDIV}`, so
    "one missing arm, not five" stays a fact.
  * `WMASK_IS_GRAPH` -- `wmask m_s` (6). `wgsl.py:18` is
    `((mask << shift_am) ^ 0xFFFFFFFF).cast(u32)` and `shift_am` is
    `bidx.src[1] // elems % elems * width`, SYMBOLIC for any index the compiler
    does not know. CPython therefore has NO integer for a chosen shift; the
    port's `ps_wmask` is its CONSTANT-FOLDING and the six rows pin folded values
    CPython never computes. CARVE-OUT. The oracle's cell reads `GRAPH:` and
    carries the two CONSTs CPython WROTE, so `0xFFFFFFFF` and the mask are
    pinned on CPython's authority even though the product is not.
  * `U32_WIDTH` -- `nan_mask double`, `nan_thr double`. `wgsl.py:36`'s mask is
    `2**63-1` and its threshold is `2047 << 52`; a U32 holds `2**32-1`, so the
    Bend lane says 4294967295 and 0. The port's own header
    (`wgsl.bend:292-299`) says the width is unreachable because WGSL's
    `type_map` has no double and `supported_dtypes` returns none.
    CARVE-OUT, declared and left printing.
  * `INDEXERROR_TOTALIZED` -- `workitem l3`. `'xyz'[int(x)]` is an INDEX and 3
    is past the end of a three-character string; CPython raises `IndexError` and
    the port answers "" for the whole call (`wgsl.bend:375-378` records that the
    None arm is unreachable because `codegen/gpudims.py:37` builds `x` as 0..2).

THE FIVE `SELFCHECK_STALE` ROWS WERE FIXED AT THE SOURCE, so the class is now
EMPTY, and that is a finding rather than an omission. `wgsl.bend` printed each
row as `nm = [got]   py=[want]` where `want` was "CPython's value, measured
2026-10-01 on this `tinygrad/` by `.agents/slop/wgsl-oracle.py`" -- a file that
is GONE, so nothing regenerated the column. Five rows routed through `dt_name`
and recorded the C spellings where this `tinygrad/` answers the rust ones:

    nan_uint float    port says [u32]  the port's OWN py= said [unsigned int]
    nan_uint half     port says [u16]  the port's OWN py= said [unsigned short]
    nan_uint double   port says [u64]  the port's OWN py= said [unsigned long]
    supported_dtypes          [bool,f32,i16,i32,i8,u16,u32,u8]
    supported_dtypes shader-f16 [bool,f16,f32,i16,i32,i8,u16,u32,u8]

MEASURED cause: `dtypes.uint32.name` is `'u32'` on this `tinygrad/`, not
`'unsigned int'`. THE PORT'S OWN VALUES WERE RIGHT ON ALL FIVE and its notes
were wrong, which is the opposite of a defect. So they were CORRECTED, not
pinned: `--refresh` on 2026-10-14 wrote `0 stale self-checks`, those five rows
became exact matches, and `selfcheck_hold()` now requires the stale set to be
EMPTY -- so a sixth stale note cannot enter unnoticed. The class stays declared
because it is a CATEGORY of pin, not a promise that a row is stale, and
`classes_hold()` explains the empty one at the place that would otherwise read
as a missing class.

THE FOUR FINDINGS, each FIXED OR LEFT ON PURPOSE, each measured, and each one
ALSO a check in `checks_hold()` so it keeps saying so after its author is gone.
THE PORT WAS BYTE-IDENTICAL FOR ALL FOUR until 2026-10-14 -- `git hash-object
tinybendygrad/renderer/wgsl.bend` was `0395f83a409131776dc35086fae3489a49a7191b`
-- and it is NOT any more, because three of the four are now defects that are
GONE rather than findings that are parked. That is the honest reason the file
changed, and it sits in the same sentence as the reason it did not before.

FINDING 1 -- FIXED 2026-10-14. `f_cast_dt` MINTS A CAST CPYTHON CANNOT BUILD,
and `ssimp` read it. MEASURED, three facts:

  (a) `mixin/dtype.py:36` is `return self if self.dtype == to_dtype(dtype) else
      ...`, so `UOp.cast` FOLDS when the dtypes agree, and
      `UOp.const(8).cast(weakint) is UOp.const(8)` is `True`. The only CONST is
      `weakint`, so casting it to `weakint` returns it and `CAST(weakint,
      CONST)` is UNBUILDABLE. `f_cast_dt` calls `O.UOp.new(..., OpsCAST{}, ...)`
      DIRECTLY -- not `O.UOp.cast` (`ops.bend:2919`) -- so it mints whatever it
      is handed, and `fx_mixed` hands it exactly that shape twice, for `l0` and
      `l1`.
  (b) `UOp.special(...)` has **ZERO** call sites in `tinygrad/` (it is defined
      at `ops.py:647` and called from nowhere), and the ONLY live SPECIAL
      construction is `codegen/gpudims.py:104`, `r.replace(op=Ops.SPECIAL, ...)`
      on a `RANGE` whose `src[0]` is `UOp.const(end, weakint)` -- a folded bare
      CONST. `UOp.range`'s bound therefore stays a CONST, and CPython's own
      printer agrees: `uop/render.py:91` spells a SPECIAL as
      `UPat(Ops.SPECIAL, src=(UPat(Ops.CONST),), ...)`. MEASURED:
      `UOp.special(8, "l0").src[0].op is Ops.CONST`.
  (c) So `ssimp`'s second arm (`op == OpsCAST{} && ss_is(src0)`, `wgsl.bend:575`)
      is UNREACHABLE from any CPython path, and `fx_mixed` is the only thing
      that reaches it. `wgsl.bend:843-844` says the fixture is "exactly as
      `codegen/gpudims.py:37` and `ops.py:1382` leave it"; `gpudims.py:37` is
      `get_grouped_dims`' return statement and constructs no SPECIAL, and
      `ops.py:1382` is `u.src[0].ssimplify()` reading that CONST.

AND THE ARM WAS ALSO WRONG ON THE CAST CPYTHON DOES BUILD, which is why both
halves were worth saying: `sint_to_uop(UOp.const(8, dtypes.int32))` is
`CAST(weakint, CAST(i32, CONST(8)))` -- a CHAIN of two -- its `src[0]` is a
CAST, so `ss_is(src0)` was False and `ssimp` took its `_ => 0` default and
answered 0, where CPython's `ssimplify` answers 8.

THE FIX, TWO EDITS. `ssimp` walks the CAST CHAIN with a fuel of 4 rather than
one step, because `ssimplify` folds through as many CASTs as there are; and
`fx_mixed` builds the shape `sint_to_uop` builds instead of the unbuildable one.
THE ROWS DO NOT CHANGE -- `rk_sz mixed` was `8,2` and is `8,2` -- AND THAT IS
THE POINT: on the NEW fixture the OLD `ssimp` would have answered `0,2`, so the
fixture change turned an untestable row into a test. MEASURED:
`gates/wgsl_render_census-mutate.py`'s M53 (`ss_go.go(2n, ...)`) moves
`rk_sz mixed` to `0,0` and `rk mixed`. `never_folding_cast_hold()` re-measures
the fold, CPython's three-node shape and CPython's answer every run, and it
reads the port's own `fx_mixed` TEXT so a revert is red rather than silent.

FINDING 2 -- FIXED 2026-10-14. ONE EXCEPTION, TWO TOTALIZATIONS.
`WGSLRenderer.code_for_op` is `{**CStyleLanguage.code_for_op, Ops.WHERE: ...}`,
so an op with no arm is a `KeyError`, and the port answered TWO DIFFERENT
THINGS for it: `UNHANDLED(Ops.X)` for LOAD/MAX/POW (a call to nothing, which
cannot compile -- correct) and `(A/B)` for FDIV (a rendered shader), while
`type_map`'s `case _:` arm answered `""` for ITS `KeyError` -- a SPELLING no
WGSL parser knows, which is the silent-wrong-answer shape the file itself calls
the dangerous one. THE FDIV ARM STAYS: it is a real rendering that upstream's
merge lost, and `axes_hold()` re-derives the set difference. THE `type_map` ARM
NOW ANSWERS `UNHANDLED(dtypes.f64)` -- the same shape as its sibling, naming its
cause, and impossible to compile. `type_map double` is still a pinned LANE
divergence, because CPython says `REFUSE:KeyError` and a Bend total function
cannot raise; what changed is that the pin's PORT column is now a REFUSAL rather
than a rendering. MEASURED: M54 (`type_map.miss` back to `""`) is red through
the pin check's "appears 0 times -- a pin moved".

FINDING 3 -- THE SET SHRANK FROM SEVEN TO FIVE. `wgsl.bend` had seven defs with
no call site, six of them defs the header claimed were PORTED. This is the
fault class `amd_dsl_census` records three times ("a def nothing calls is
invisible to every other check"), measured rather than inherited.
`dead_defs_hold()` names the exact set, so a def that gains a caller turns it
red rather than silently becoming checked.

  GONE -- `wi_axis`, and `wi_axis.of2` with it. It was the def the header named
    as the totalizer for `'xyz'[3]`, it called NOTHING, and the `None` arm of
    `code_for_workitem.ret` is what actually answers `""`. A def that describes
    a decision no def makes, next to the def that makes it.
  GONE -- `render_load`. It was "ported, called by nothing in this file, and
    ungated", and the string rule that calls it is `string_rewrite`, which WAS
    the wall. It has FOUR rows now: `sr lgate packed`, `sr lgate plain`,
    `sr load packed`, `sr load plain`.
  LEFT ON PURPOSE -- `is_packed_of`, `se_shift`, `w_numel`, `prw_of`. The first
    three are UOp READERS whose callers are the graph rules (`packed_load`,
    `packed_store`), which are the wall this file names; porting a reader with
    no caller is the same defect under a new name. `prw_of` is the interesting
    one and it is left BECAUSE THE MEASUREMENT SAYS THE HEADER IS WRONG:
    `packed_rmw`'s shape is `AND(LOAD(CAST(b, u32)), wmask)` -- `& UPat.var(...)`
    is `Ops.AND`, a BINARY pattern, NOT a bind -- so `prw_of`, which tests only
    the LOAD half, is a def nothing calls AND the full predicate is not ported.
    Fixing it is porting the `AND`, which is a different piece of work.

FINDING 4 -- FIXED AT THE SOURCE 2026-10-14, AND THE PINS DROPPED BECAUSE THE
DEFECT IS GONE. See the `SELFCHECK_STALE` paragraph above. A pin that moved
because the DEFECT was fixed is a pin whose defect no longer exists, and
deleting it is the finding rather than a weakening -- `selfcheck_hold()` still
runs and still requires the stale set to be EMPTY.

EXIT STATUS: 0 all three lanes identical after the pins and every class check
holds · 1 a lane took the wrong row count, a compile failed, the lanes
disagree, a pin moved, a population/axis/class check failed · 3 a precondition
was absent (the pins file, the artifact directory, the substrate, the oracle) ·
5 a lane ran and emitted nothing.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import (BEND, PY, WARM, TMP, NOTICE, REFUSED, PASS, FAIL, DEAD,  # noqa: F401
                     VERDICT, oracle_drift)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "wgsl_render_census-pins.rows"
ART = HERE / "artifacts" / "wgsl_render_census-gate"
PORT = ROOT / "tinybendygrad" / "renderer" / "wgsl.bend"
ORACLE = HERE / "wgsl_render_census-oracle.py"

ROWS = 227

# THE PIN, AS BYTES AND NOT AS A REVISION. These are the five `tinygrad/` files
# the ORACLE IMPORTS and the ROWS READ: `wgsl.py` is the subject (its
# `string_rewrite` rules and its renderer), `cstyle.py` because
# `WGSLRenderer` IS a `CStyleLanguage` and the oracle reads `base_rewrite`'s
# own patterns, `uop/ops.py` for `Ops`/`UOp`/`PatternMatcher`, `dtype.py` for
# `AddrSpace` and `dtypes`, and `helpers.py` for `Target`.
#
# THE VALUES ARE LITERALS, and they must stay literals. A pin re-derived from
# the file it checks is `sha256(x) == sha256(x)`: it cannot fail, and an
# instrument that cannot fail is worse than no instrument.
# `gates/blobpin-census-gate.py` MEASURES that claim over every pin site in
# the tree and fails a derived one.
#
# `gates/gatekit.py:oracle_drift` re-measures these on every run. It is the
# house mechanism, and it is the right one here for the reason the header says:
# a REVISION names a COMMIT, and the file the oracle opens is the one ON DISK.
DRIFT_PIN = {
  "tinygrad/renderer/wgsl.py":
    "84d1d17a116727e0decbc6f3da3b681fe698a92474388b87086df5ca38c19ecc",
  "tinygrad/renderer/cstyle.py":
    "3623cd9b6ad418affe8d6a093998cd931fd15ac2ae819abe724cf19f7275c5ea",
  "tinygrad/uop/ops.py":
    "d006eafbb1a6e8326e9310ebbce7b04143bd80cf636e90779c3a86f7e2826ba9",
  "tinygrad/dtype.py":
    "7800592dcccbdd5a5beaee889342b5f62790d37445938fe601416c8b76057926",
  "tinygrad/helpers.py":
    "eda095ab2c35d045e40523cf8f025543c45b012ff217ddeaed6143610330f308",
}

# THE BLOB THE ROWS WERE TAKEN AGAINST -- a RECORDED FACT, not a live reading.
# `git rev-parse HEAD:<path>` answers the blob at HEAD NOW, and a header that
# calls that "when these rows were taken" is a LABEL that rots: wgsl.py's blob
# was `02d7fdea` when the 227 rows were taken and is `c7121333` today.
ROWS_TAKEN_AT = {
  "tinygrad/renderer/wgsl.py": "02d7fdea",
}

# `string_rewrite`'s SEVENTEEN rules, by their INDEX in
# `WGSLRenderer.string_rewrite.patterns`. `rules_hold()` re-derives the length and
# each index's op and dtypes from CPython on every run, so this tuple is a claim
# the instrument checks and not a list the instrument trusts.
SR_RULES = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
# rule index -> the OPS that rule's `UPat` carries, in wgsl.py:65-93's order.
# Read off `WGSLRenderer.string_rewrite.patterns` and compared back to it on
# every run, so a rule inserted or removed upstream moves these and the gate
# says WHICH, instead of the seventeen silently sliding by one.
SR_OPS = {0: "CAST", 1: "NEG", 2: "CAST", 3: "CAST", 4: "CAST", 5: "BUFFER",
          6: "BITCAST", 7: "BITCAST", 8: "BITCAST", 9: "BITCAST", 10: "BITCAST",
          11: "BITCAST", 12: "LOAD", 13: "LOAD", 14: "STORE", 15: "STORE",
          16: "INDEX"}

# `wgsl.bend`'s OWN ROW FORMAT: `nm = [got]   py=[want]\n`, or `nm = [got]\n`
# for the three `rk_row` module rows which carry no `py=` half. This is the
# ONLY place the port's `[...]` and `py=[...]` spellings are decoded, and
# `norm_hold()` re-measures that every line decoded and that no VALUE contains
# the separator -- otherwise a `py=[` inside a WGSL module would be mistaken for
# the self-check tail and the lane would compare a truncated string.
SEP = " = ["
PYTAIL = re.compile(r"\]\s{3}py=\[.*\]$")


def norm(line):
    """`nm = [got]   py=[want]` -> `(nm=got, nm, got)`, or None when the line is
    not a row at all, so a DECODING failure is visible rather than silent.

    The two bracket pairs are read in ONE pass. A row WITH a self-check is
    `got]   py=[want]`, so cutting the tail leaves `got]`; a row WITHOUT one is
    `got]`, and its outer bracket is the same character. Cutting the tail and
    THEN requiring a trailing `]` rejects all 169 self-check rows -- MEASURED,
    that is what the first draft of this function did -- and the reason the two
    bracket pairs are handled together here and not by two independent strips.
    """
    if SEP not in line:
        return None
    i = line.index(SEP)
    name, rest = line[:i], line[i + len(SEP):]
    m = PYTAIL.search(rest)
    rest = rest[:m.start()] + "]" if m else rest
    if not rest.endswith("]"):
        return None
    return f"{name}={rest[:-1]}", name, rest[:-1]


def recorded_py(line):
    """The text inside the `py=[...]` tail `wgsl.bend` recorded for itself, or
    None when the row carries no self-check (`rk_row`'s three module rows)."""
    if not PYTAIL.search(line):
        return None
    return line[line.rindex("py=["):line.rindex("]")][len("py=["):]


# ===========================================================================
# THE POPULATION. Re-derived from BOTH sides on every run, never a list here.
# ===========================================================================
def _recorded(lines):
    out = {}
    for ln in lines:
        if not ln.strip() or SEP not in ln:
            continue
        out[ln[:ln.index(SEP)]] = recorded_py(ln)
    return out


def port_lane():
    """`(rows, recorded)` for the Bend lane: `rows` is `nm=got` per line and
    `recorded` is the `py=` half the port wrote beside it, or None."""
    raw = _lane_raw_or_empty("bd.out")
    rows, rec = [], {}
    for ln in raw:
        if not ln.strip():
            continue
        n = norm(ln)
        if n is None:
            rows.append(None)
            continue
        rows.append(n[0])
        rec[n[1]] = recorded_py(ln)
    return rows, rec


def _lane_raw(n):
    # The RAW lane file, staged or promoted. `run()`'s `finally` promotes
    # `.tmp.<name>` to `<name>` on success and DELETES it on failure, and
    # `checks_hold()` runs after `run()` -- so a reader that only looked for the
    # staged spelling found a file that no longer existed. MEASURED: that is
    # the FileNotFoundError this shape replaced. Staged first, promoted second,
    # because `--refresh` reads the file while it is staged and `run()`'s
    # checks read it after it has been promoted.
    s = _staged(n)
    if s.is_file():
        return s.read_text().splitlines()
    p = ART / n
    if p.is_file():
        return p.read_text().splitlines()
    raise FileNotFoundError(f"neither {s} nor {p} exists")


def _lane_raw_or_empty(n):
    try:
        return _lane_raw(n)
    except FileNotFoundError:
        # NEITHER: a run that failed before it wrote this lane. MEASURED:
        # raising out of a check CRASHES `checks_hold()` on a red run, so a
        # lane diff and a population drift could never be REPORTED together --
        # the guard would only ever speak when the thing it guards had already
        # passed. An empty list is the honest "this lane did not run", and the
        # checks that read it fail on their own terms instead of taking the
        # whole report down with them.
        return []


def oracle_lane():
    """`(rows, err)` -- the oracle's own output, by RUNNING it."""
    r = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True,
                       cwd=str(ROOT))
    if r.returncode != 0:
        return None, (f"the oracle failed rc={r.returncode}: "
                      f"{r.stderr.strip()[:300]}")
    return [l for l in r.stdout.splitlines() if l.strip()], ""


def norm_hold():
    """EVERY LINE OF THE BEND LANE DECODES, AND NO VALUE EATS THE SEPARATOR.

    A value that contained `   py=[` would have its tail stripped and the lane
    would compare a truncated string -- a green gate on a short row. MEASURED:
    none does, and this says so on every run instead of once in a comment.
    """
    bad = []
    raw = [l for l in _lane_raw_or_empty("bd.out") if l.strip()]
    if len(raw) != ROWS:
        bad.append(f"the bend lane printed {len(raw)} non-blank lines, "
                   f"expected {ROWS}")
    for ln in raw:
        n = norm(ln)
        if n is None:
            bad.append(f"undecodable row: {ln[:80]!r}")
        elif "   py=[" in n[2]:
            bad.append(f"the value of {n[1]!r} contains the py= separator")
    return report("norm_hold", bad)


def names_hold():
    """THE TWO POPULATIONS ARE EQUAL AND IN THE SAME ORDER.

    `wgsl.bend`'s rows are DISCOVERED by running it -- they are built by
    `String.concat` over a dozen helper calls, so no regex over its source can
    enumerate them without being a second implementation of them. The oracle's
    rows are discovered by running it. This check is what stops either side from
    quietly covering whatever the other does.
    """
    got, rec = port_lane()
    want, why = oracle_lane()
    bad = []
    if want is None:
        bad.append(why)
    elif got is None or len(got) != ROWS:
        bad.append(f"the port lane file has {len(got) if got else 0} rows, "
                   f"expected {ROWS}. A FAILED run deletes its staged lanes in "
                   f"`run()`'s `finally`, so on a red run this is 'the lane did "
                   f"not survive', not 'the port stopped printing rows' -- the "
                   f"DISAGREE line above is the real verdict")
    else:
        for i, (a, b) in enumerate(zip(got, want)):
            if a.split("=", 1)[0] != b.split("=", 1)[0]:
                bad.append(f"row {i}: port {a.split('=', 1)[0]!r}, "
                           f"oracle {b.split('=', 1)[0]!r}")
                if len(bad) > 4:
                    break
    return report("names_hold", bad)


# ===========================================================================
# THE FIXTURE AXES -- declared on BOTH sides and compared by TEXT.
# ===========================================================================
BEND_SRC = None


def src():
    global BEND_SRC
    if BEND_SRC is None:
        BEND_SRC = PORT.read_text()
    return BEND_SRC


def _oracle_mod():
    import importlib.util
    spec = importlib.util.spec_from_file_location("_wgsl_oracle", str(ORACLE))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def fixtures_hold():
    """THE PORT'S OWN FIXTURE AXES, re-read out of `wgsl.bend`'s TEXT, against
    the oracle's axes -- name for name and IN ORDER.

    This is the check that stops the six rows from becoming "the oracle agrees
    with the port about a fixture neither of them got from CPython". Every axis
    is written in `wgsl.bend` as a literal list of `r_*` calls, so each one is
    readable without running anything, and an axis that grows on one side only
    is red before a value is compared.
    """
    try:
        m = _oracle_mod()
    except Exception as e:                                        # noqa: BLE001
        return report("fixtures_hold", [f"the oracle would not import: {e}"])
    s = src()
    bad = []

    def check(label, want, pat):
        got = re.findall(pat, s, re.M)
        # `re.findall` returns STRINGS for a one-group pattern and TUPLES for a
        # multi-group one, and the oracle's axes are tuples or plain strings --
        # so both sides are normalised to tuples of strings before they are
        # compared. MEASURED: without this the one-group axes compared
        # `['SQRT', ...]` against `[('SQRT',), ...]` and said the axes differed
        # when they do not.
        def t(x):
            return tuple(x) if isinstance(x, tuple) else (x,)
        # EVERY ELEMENT IS A STRING ON BOTH SIDES. `re.findall` yields strings
        # and the oracle's axes hold ints, so comparing them raw said the axes
        # differed when they do not -- MEASURED, `SR_CU` printed
        # `('255', '0', '255')` against `('255', 0, 255)`. That is the third
        # shape of this mistake in this one check and it is the same mistake:
        # a side that is NORMALISED and a side that is not.
        g, w = [tuple(map(str, t(x))) for x in got], [tuple(map(str, t(x))) for x in want]
        if g != w:
            bad.append(f"{label}: port {g} oracle {w}")

    # `r_pk8("uchar", S.uint8(), ...)` -- the dtype axis of is_packed/buf_map.
    check("PK_DTS", [(n, c) for n, c in m.PK_DTS],
          r'r_pk8\("([^"]+)", S\.(\w+)\(\)')
    # `r_pf3("uchar", S.uint8(), ...)` -- packed_field's three integers.
    check("PF_DTS", [(n, c) for n, c in m.PF_DTS],
          r'r_pf3\("([^"]+)", S\.(\w+)\(\)')
    # `r_wm(255, 0, ...)` -- packed_store's wmask.
    check("WMASK_AXIS", [(str(a), str(b)) for a, b in m.WMASK_AXIS],
          r'r_wm\((\d+), (\d+),')
    # `r_ps("uchar 16", S.uint8(), S.AGlobal{}, 16, ...)`.
    check("PS_AXIS", [(n, c, a, str(k)) for n, c, a, k in m.PS_AXIS],
          r'r_ps\("([^"]+)", S\.(\w+)\(\), S\.(A\w+)\{\}, (\d+),')
    # `r_cfo1(O.OpsSQRT{}, ...)` -- code_for_op's arms, in the port's order.
    check("CFO_ARMS", m.CFO_ARMS, r'r_cfo1\(O\.Ops(\w+)\{\}')
    # `r_sd1("", ...)` / `r_sd1("shader-f16", ...)` -- supported_dtypes' arch.
    check("ARCHES", m.ARCHES, r'r_sd1\("([^"]*)"')
    # `r_rc1("uchar", S.uint8(), ...)` -- render_cast's dtypes.
    check("RC_DTS", [(n, c) for n, c in m.RC_DTS],
          r'r_rc1\("([^"]+)", S\.(\w+)\(\)')
    # `r_nan5("float", S.single(), ...)` and `r_nan_uint()`'s three.
    check("NAN_DTS", [(n, c) for n, c in m.NAN_DTS],
          r'r_nan5\("([^"]+)", S\.(\w+)\(\)')
    # `r("nan_uint float", dt_name(nan_uint(S.single())), ...)` -- spelled
    # inline rather than through an `r_*1` helper, so it needs its own pattern.
    check("NANU_DTS", [(n, c) for n, c in m.NANU_DTS],
          r'r\("nan_uint (\w+)", dt_name\(nan_uint\(S\.(\w+)\(\)\)\)')
    # `r_cu1("255", 0, 255, ...)` / `r_ci1(...)` -- `string_rewrite`'s two CONST
    # rules, whose fixture is a weakint CONST's value as an `I64`. The `hi`/`lo`
    # ARE THE AXIS and not a rendering: the port cannot tell -1 from 4294967295
    # as a `U32`, so the pair is what makes them two cases.
    check("SR_CU", [(n, h, l) for n, h, l in m.SR_CU],
          r'r_cu1\("(-?\d+)", (\d+), (\d+),')
    check("SR_CI", [(n, h, l) for n, h, l in m.SR_CI],
          r'r_ci1\("(-?\d+)", (\d+), (\d+),')
    # `r_sb1("global", "data0_16", S.uint8(), S.AGlobal{}, 16, ...)`.
    check("SR_BUF", [(n, bn, c, a, str(k)) for n, bn, c, a, k in m.SR_BUF],
          r'r_sb1\("([^"]+)", "([^"]+)", S\.(\w+)\(\), S\.(A\w+)\{\}, (\d+),')
    return report("fixtures_hold", bad)


def rules_hold():
    """`string_rewrite`'s POPULATION, re-derived from CPython, and the PORT's
    seventeen `sr_*` defs measured against it.

    `WGSLRenderer.string_rewrite` is `PatternMatcher([...17...]) + base_rewrite`,
    so `patterns[:17]` are wgsl's and `patterns[17:]` is `base_rewrite`'s. THIS
    CHECK SAYS SO on every run rather than leaving the seventeen to a comment,
    and it checks four things:

      (a) the seventeen exist and `base_rewrite` follows them, with both lengths
          measured;
      (b) each index's op and dtype set -- the port's rules claim to BE these
          patterns, and a rule that stops matching a dtype it used to match is a
          port defect this census cannot see through a string;
      (c) the port really has one `sr_*` def per rule, by NAME, so a rule that
          loses its def is red rather than silent;
      (d) each of the seventeen has AT LEAST ONE ROW, which is the difference
          between "the census could look" and "the census found no defect", and
          is what the `sr_*` block was added for.
    """
    sys.path.insert(0, str(ROOT))
    import tinygrad.renderer.wgsl as w
    from tinygrad.renderer.cstyle import base_rewrite
    # `patterns` is a list of `(UPat, fn)` PAIRS, so the pattern is `[0]`.
    # MEASURED: reading `pats[i].op` raised `AttributeError: 'tuple' object has
    # no attribute 'op'` -- the same shape of mistake twice in one check, and a
    # check that CRASHES reports nothing, so both are named here.
    pats = [p for p, _fxn in w.WGSLRenderer.string_rewrite.patterns]
    bad = []
    base = [p for p, _fxn in base_rewrite.patterns]
    if len(pats) - len(base) != len(SR_RULES):
        bad.append(f"string_rewrite has {len(pats) - len(base)} of its own rules, "
                   f"the table says {len(SR_RULES)}")
    # BOTH SIDES ARE UNWRAPPED. `patterns` holds `(UPat, fn)` PAIRS, and this
    # check unwraps both -- MEASURED: comparing the unwrapped wgsl patterns
    # against `base_rewrite.patterns` unwrapped on neither side printed "the tail
    # is NOT base_rewrite's" on a port with a byte-identical tail.
    if pats[len(SR_RULES):] != base:
        bad.append("string_rewrite's tail is NOT base_rewrite's own patterns")
    # (b) EACH RULE'S OP, against a table declared HERE and compared to CPython.
    # The first draft of this check asserted the op's NAME appeared in
    # `wgsl.bend`'s text, which is the oracle-that-reimplements-the-port failure
    # wearing a hat: six of the seventeen are BITCAST and the port spells NONE of
    # them `BITCAST` -- it spells `bitcast<u32>(`, which is the RENDERED form.
    # MEASURED: that version printed six reds for rules 6-11 on a green port.
    # What a rule's op IS is a fact about CPython, so it is compared to CPython.
    for i, want in SR_OPS.items():
        if i >= len(pats):
            bad.append(f"rule {i} does not exist")
            continue
        ops = ",".join(sorted(o.name for o in pats[i].op))
        if ops != want:
            bad.append(f"rule {i} is {ops}, the table says {want} -- a rule was "
                       f"inserted, removed or reordered above this one")
    s = src()
    # (c) one `sr_*` def per rule, and (d) at least one row per rule. `sr_load` is
    # in this list because rule 13 GOT A DEF when its `UPat.load(b)` pattern was
    # ported: it had none before, because rule 13's body IS `render_load` and a
    # pattern is not a body. MEASURED: rule 13's `srneg` row was the one that made
    # the absence a defect rather than an economy.
    defs = set(re.findall(r"^def ((?:sr_|\w+\.)?sr\w*)\s*[(<]", s, re.M))
    for need in ("sr_idx", "sr_neg", "sr_cbool", "sr_cuint", "sr_ci32", "sr_buffer",
                 "sr_bhalf", "sr_buchar", "sr_bchar", "sr_bushort", "sr_bshort",
                 "sr_bany", "sr_lgate", "sr_load", "sr_rmw", "sr_store", "sr_index"):
        if need not in defs:
            bad.append(f"wgsl.bend has no {need} def -- a string_rewrite rule "
                       f"lost its port")
    # (d) ROW COVERAGE. `r_sr_N` is a row GROUP and `N` is the FIRST rule index it
    # covers -- `r_sr_0` holds rules 0, 1 and 2 -- so the groups are read as
    # COVERING not as equalling: the first draft asserted `groups == SR_RULES`,
    # which is red for a port that groups rows and green for one that leaves a
    # rule's rows out of any group. MEASURED: it printed all seventeen red on a
    # port with 33 `sr` rows covering all seventeen. What is asserted is the two
    # things that actually matter: every group names a REAL rule, and every rule
    # is inside some group -- which is read off the row NAMES, and the row names
    # are compared end to end by `names_hold()` on both lanes.
    groups = [int(n) for n in re.findall(r"^def r_sr_(\d+)\(\)", s, re.M)]
    if sorted(groups) != sorted(set(groups)) or not set(groups) <= set(SR_RULES):
        bad.append(f"the row groups are {groups}, the rules are "
                   f"{list(SR_RULES)} -- a group names no rule, or is declared "
                   f"twice")
    if set(groups) != {0, 3, 5, 6, 12, 14, 16}:
        bad.append(f"the row groups are {sorted(groups)} -- a rule lost its rows")
    # (e) THE NEGATIVE COVERAGE. Every rule needs a `srneg` row too, and the rule
    # index is IN the row name precisely so this can be read off the port's own
    # text: `srneg N ...` for each N in SR_RULES, exactly one apiece. The
    # seventeen `sr` rows above say the two BODIES agree on seventeen fixtures;
    # these say what CPython's PATTERN does on a node it rejects, which is the
    # half the bodies cannot supply.
    negs = re.findall(r'r_srneg\((\d+),', s)
    if sorted(int(x) for x in negs) != sorted(SR_RULES):
        bad.append(f"the srneg rows cover rules {sorted(int(x) for x in negs)}, "
                   f"the rules are {list(SR_RULES)} -- a rule has no refusal row, "
                   f"or one is declared twice")
    return report("rules_hold", bad)


def axes_hold():
    """The axes that COULD be derived from CPython, re-derived.

    (a) `WGSLRenderer.code_for_op` minus the oracle's arm list is EXACTLY
        `{Ops.FDIV}` -- `wgsl.bend:443` claims "ONE missing arm, not five" and
        this is the measurement of it. A second op appearing or disappearing
        turns this red.
    (b) `WGSLRenderer.type_map` has nine entries, `code_for_workitem` has two
        keys, and `global_max`/`local_max` are three-int tuples -- the four
        shapes the port's constant rows read.
    (c) `AddrSpace` has four members and the port's three (`GLOBAL`, `LOCAL`,
        `REG`) are a subset of them.
    """
    try:
        m = _oracle_mod()
    except Exception as e:                                        # noqa: BLE001
        return report("axes_hold", [f"the oracle would not import: {e}"])
    import tinygrad.renderer.wgsl as w
    from tinygrad.dtype import AddrSpace
    from tinygrad.uop.ops import Ops
    bad = []
    have = set(w.WGSLRenderer.code_for_op)
    # THE CLAIM `wgsl.bend:443` MAKES is "clang - wgsl = ['Ops.FDIV'] ... so
    # this is ONE missing arm, not five", and it is a claim about the TWENTY-TWO
    # arms the port actually renders. `CFO_PROBES` are the three ops probed only
    # for the KeyError totalization, so the set difference is FDIV plus the
    # probes; the ARM set is what the claim is about.
    missing = {n for n in m.CFO_ARMS if getattr(Ops, n) not in have}
    if missing != set(m.CFO_PROBES) | {"FDIV"}:
        bad.append(f"code_for_op arms missing from CPython are "
                   f"{sorted(missing)}, expected "
                   f"{sorted(set(m.CFO_PROBES) | {'FDIV'})}")
    if len(have) != 21:
        bad.append(f"WGSLRenderer.code_for_op has {len(have)} arms, "
                   f"the pins say 21")
    if len(w.WGSLRenderer.type_map) != 9:
        bad.append(f"WGSLRenderer.type_map has {len(w.WGSLRenderer.type_map)} "
                   f"entries, expected 9")
    if sorted(w.WGSLRenderer.code_for_workitem) != ["g", "l"]:
        bad.append(f"code_for_workitem keys are "
                   f"{sorted(w.WGSLRenderer.code_for_workitem)}")
    for nm in ("global_max", "local_max"):
        v = getattr(w.WGSLRenderer, nm)
        if not (isinstance(v, tuple) and len(v) == 3):
            bad.append(f"{nm} is {v!r}, expected a 3-tuple")
    if not {"GLOBAL", "LOCAL", "REG"} <= {a.name for a in AddrSpace}:
        bad.append(f"AddrSpace members are {[a.name for a in AddrSpace]}")
    return report("axes_hold", bad)


def pin_drift_hold():
    """THE ORACLE'S BYTES, PINNED. The house mechanism, read by
    `gates/gatekit.py:oracle_drift` -- the same one `gates/onnx_census-gate.py`,
    `gates/rand_census-gate.py`, `gates/state_census-gate.py` and
    `gates/ops_python_census-gate.py` use.

    THE OLD CHECK WAS A REVISION COMPARISON and it was the wrong instrument
    twice over. It compared `git rev-parse <rev>:<path>` at `HEAD`, at
    `ad117c928` and at `ad117c928^`, which is a fact about COMMITS and not
    about the file `import tinygrad` opens, so a WORKING TREE whose bytes
    differ from every revision it named still passed. And it demanded that all
    three blobs be EQUAL, which is a claim about the vendored tree rather than
    about this gate's rows: wgsl.py moved `02d7fdea` -> `c7121333` and the
    check went red for a reason that had nothing to do with the 227 rows.

    THE PIN AND THE OUTPUT CHECK ARE NOT THE SAME FACT. This one checks the
    BYTES of the files the oracle imports -- the INPUTS. The 227-row diff
    checks the BEHAVIOUR -- the port's answers against CPython's. A byte
    change that no row reads leaves the diff green and this red; a port
    defect leaves this green and the diff red. Neither can stand in for the
    other, and neither is re-derived from the other.

    The pins file records the same values, so the pins file and this check
    cannot disagree about which bytes the rows were measured against."""
    bad = oracle_drift(DRIFT_PIN)
    text = PINS.read_text() if PINS.is_file() else ""
    for rel, want in DRIFT_PIN.items():
        if want not in text:
            bad.append(f"the pins file does not record {rel}'s pinned sha256 {want[:16]}")
    for rel, blob in ROWS_TAKEN_AT.items():
        if blob not in text:
            bad.append(f"the pins file does not record {rel}'s blob {blob} -- the bytes "
                       f"the rows were taken against")
    return report("pin_drift_hold", bad)


def never_folding_cast_hold():
    """FINDING 1, FIXED, and the fix is re-measured on every run.

    `mixin/dtype.py:36` is `return self if self.dtype == to_dtype(dtype) else
    self._wrap_uop(...)`, so `UOp.cast` FOLDS when the dtypes agree and a
    `CAST(weakint, CONST)` is UNBUILDABLE: the only CONST is weakint, and
    casting a weakint CONST to weakint returns the CONST. `wgsl.bend`'s
    `fx_mixed` USED TO build exactly that node, so its `ssimp` CAST arm was
    reachable only from a fixture CPython cannot produce.

    Three facts are re-measured here on every run:

      1. the fold still holds -- so the conclusion about the OLD fixture still
         follows, and if it ever stops holding the old fixture becomes legal and
         this check must be re-derived rather than trusted;
      2. `UOp.special(8, "l0").src[0]` is a bare CONST -- so a real `l0`'s bound
         is a CONST and `ssimp`'s CAST chain is unreachable from a real kernel,
         and the port's `fx_mixed` fixture is still the ONLY thing that reaches
         it. THE FIX DID NOT CHANGE THAT: it changed WHICH shape the fixture
         reaches it with, from one CPython cannot build to the one it does;
      3. the shape CPython builds for a non-weakint bound is
         `CAST(weakint, CAST(i32, CONST(8)))` and `ssimplify` answers 8 on it.
         THE PORT NOW ANSWERS 8 ON IT TOO -- `ssimp` walks the CAST CHAIN with a
         fuel of 4 rather than one step, and `fx_mixed` builds `sint_to_uop`'s
         shape. That is the fix, and this check says so by asserting the shape
         and the answer.

    And `grep -c OpsCAST tinybendygrad/renderer/wgsl.bend` is re-measured as 3,
    with each of the three lines named: two are pattern TESTS and one MINTS.
    """
    sys.path.insert(0, str(ROOT))
    from tinygrad.uop.ops import UOp, Ops, ssimplify, sint_to_uop
    from tinygrad import dtypes
    bad = []
    c = UOp.const(8)
    if c.dtype is not dtypes.weakint or c.cast(dtypes.weakint) is not c:
        bad.append("UOp.const(8).cast(weakint) no longer folds -- the "
                   "conclusion of FINDING 1 must be re-derived")
    real = UOp.special(8, "l0").src[0]
    if real.op is not Ops.CONST:
        bad.append(f"a real l0's bound is {real.op.name}, not CONST -- "
                   f"re-measure ssimp's reachability")
    cast = sint_to_uop(UOp.const(8, dtypes.int32))
    # THE SHAPE, stated as the CHAIN it is: `sint_to_uop` of a non-weakint CONST
    # is a CAST of a CAST, and the old check only asserted that `src[0]` is not
    # a CONST -- which is true of the WRONG fixture's CAST too, so it could not
    # tell the two nodes apart.
    chain = [cast]
    while chain[-1].op is Ops.CAST and chain[-1].src:
        chain.append(chain[-1].src[0])
    # THE SHAPE IS THREE NODES: `CAST(weakint, CAST(i32, CONST(8)))`. The first
    # draft walked only while the NEXT node was a CAST, so it stopped one short
    # and asserted `chain[-1]` was the CONST when the walk had already landed on
    # the inner CAST -- MEASURED: it printed `CAST -> CAST` on an unmoved tree.
    # The walk follows src[0] for as long as the CURRENT node is a CAST, so the
    # CONST is `chain[-1]` and the two CASTs are `chain[:2]`.
    if len(chain) != 3 or [p.op.name for p in chain] != ["CAST", "CAST", "CONST"] \
            or [p.dtype.name for p in chain] != ["weakint", "i32", "weakint"] \
            or ssimplify(cast) != 8:
        bad.append(f"sint_to_uop's shape moved: "
                   f"{' -> '.join(p.op.name for p in chain)} "
                   f"[{' -> '.join(p.dtype.name for p in chain)}], "
                   f"ssimplify {ssimplify(cast)}")
    # AND THE PORT'S FIXTURE IS THAT SHAPE, read off the PORT'S OWN TEXT -- so a
    # fixture that goes back to one CAST is red here rather than silent.
    if "f_cast_dt(f_cast_dt(" not in src() and "f_cast_dt(c2, S.int32())" not in src():
        bad.append("wgsl.bend's fx_mixed no longer builds the DOUBLE CAST "
                   "sint_to_uop builds -- FINDING 1's fix was reverted")
    n = len(re.findall(r"OpsCAST\{\}", src()))
    if n != 3:
        bad.append(f"wgsl.bend has {n} OpsCAST{{}} sites, expected 3")
    return report("never_folding_cast_hold", bad)


def dead_defs_hold():
    """FINDING 3: SEVEN of `wgsl.bend`'s 170 defs have NO call site, and six of
    them are the ones the header claims are PORTED.

    `main` is the entry point. The other six -- `is_packed_of`, `prw_of`,
    `render_load`, `se_shift`, `w_numel`, `wi_axis` -- are a def nothing calls,
    which is the fault class `amd_dsl_census` recorded twice and which its own
    `ALIGN_SHIFT` notes record a third time ("`a def nothing calls is invisible
    to every other check`"). `wgsl.bend:1224-1226` says of `render_load` that it
    "is ported, called by nothing in this file, and ungated"; this measures the
    rest of the set rather than leaving it to a reader.
    """
    names = set(re.findall(r"^def ([A-Za-z_0-9.]+)\s*[(<]", src(), re.M))
    stripped = re.sub(r"^def [A-Za-z_0-9.]+\s*[(<]", "def ", src(), flags=re.M)
    dead = set()
    for n in names:
        base = n.split(".")[-1]
        pats = [r"(?<![.\w])" + re.escape(base) + r"\s*[(<]"]
        if "." in n:
            pats.append(r"(?<![.\w])" + re.escape(n) + r"\s*[(<]")
        if sum(len(re.findall(p, stripped)) for p in pats) == 0:
            dead.add(n)
    # MEASURED 2026-10-14, and IT SHRANK, which is the point of the check. It was
    # SEVEN: `main` plus six defs the header claimed were PORTED. Two are gone
    # because a `string_rewrite` rule now calls them and two because the port
    # stopped claiming them:
    #   `wi_axis`      DELETED, with `wi_axis.of2`. It was the def the header
    #                  named as the totalizer for `'xyz'[3]`, it called NOTHING,
    #                  and `code_for_workitem.ret`'s `None` arm is what actually
    #                  answers "". A def that describes a decision no def makes.
    #   `render_load`  IS CALLED NOW, by rules 12 and 13 of `string_rewrite`,
    #                  which are `ctx.render_load(ctx[b], ...)` upstream -- so the
    #                  header's "ported, called by nothing, and ungated" was
    #                  TRUE of a wall that was not a wall.
    #   `prw_of`       STILL DEAD and STILL CLAIMED PORTED: `packed_rmw`'s shape
    #                  is `AND(LOAD(CAST(b, u32)), wmask)` -- `& UPat.var("wmask")`
    #                  is Ops.AND, a BINARY pattern, not a bind (wgsl.bend's own
    #                  comment on :39 says "the table's BIND, not a guard", and
    #                  that is WRONG). So `prw_of`, which tests only the LOAD half,
    #                  is a def nothing calls and the FULL predicate is not ported.
    #                  LEFT ALONE and left on the list, and the comment above is
    #                  the reason: fixing it is porting the `AND`.
    want = {"main", "is_packed_of", "prw_of", "se_shift", "w_numel"}
    if dead != want:
        bad = []
        if want - dead:
            bad.append(f"these defs now have a call site: "
                       f"{sorted(want - dead)} -- re-measure FINDING 3")
        if dead - want:
            bad.append(f"these defs have NO call site and are not on the list: "
                       f"{sorted(dead - want)} -- FINDING 3 changed shape")
        return report("dead_defs_hold", bad)
    return report("dead_defs_hold", [])


def selfcheck_hold():
    """FINDING 4: FIVE of the port's OWN recorded `py=` halves are STALE.

    `wgsl.bend:82-87` says the `py=` half of each row is "CPython's value,
    measured 2026-10-01 on this `tinygrad/` by `.agents/slop/wgsl-oracle.py`".
    That oracle is GONE -- MEASURED, `ls .agents/slop/wgsl-oracle.py` answers
    "No such file or directory" -- so nothing regenerates the column, and the
    vendored `tinygrad/` has moved `DType.name` to the rust spellings since.
    This check compares the recorded half against the oracle and requires the
    STALE SET to be exactly the pinned one: not zero (that would stop noticing
    it) and not everything (that would stop looking).
    """
    got, rec = port_lane()
    want, why = oracle_lane()
    bad = []
    if want is None or got is None:
        return report("selfcheck_hold", [why or "a lane did not run"])
    by = {l.split("=", 1)[0]: l.split("=", 1)[1] for l in want if "=" in l}
    stale = {n for n, v in rec.items() if v is not None and by.get(n) != v}
    pins = DIVERGES or {}
    lane = {row for row, v in pins.items() if v[2] == "LANE"}
    selfck = {row for row, v in pins.items() if v[2] == "SELFCHECK"}
    if lane & selfck:
        bad.append(f"these rows are pinned twice, once each way: "
                   f"{sorted(lane & selfck)}")
    if stale - lane != selfck:
        bad.append(f"the stale py= halves, less the lane divergences, are "
                   f"{sorted(stale - lane)}, the pins say {sorted(selfck)}")
    # The OTHER direction is INFORMATION, not a failure: `lane - stale` is the
    # set of rows whose recorded note IS CPython's answer and whose port value
    # knowingly is not. MEASURED it is exactly the two U32_WIDTH rows, and it
    # is the GOOD case -- wgsl.bend:1088-1094 says so in its own words.
    print(f"  selfcheck_hold: {len(stale)} stale notes = {len(stale & lane)} "
          f"lane rows whose note records the port's own totalization + "
          f"{len(selfck)} stale; and {len(lane - stale)} lane rows whose note "
          f"IS CPython's value and whose port value knowingly is not",
          file=sys.stderr)
    return report("selfcheck_hold", bad)


# ===========================================================================
# THE DIVERGENCE POPULATION -- declared here, PINNED on both sides, in a file
# beside the gate and written by `--refresh` and by nothing else.
# ===========================================================================
def _pins():
    """`(DIVERGES, why)` -- `row -> (oracle_line, port_line, kind)`, loaded BY
    PATH. `kind` is `LANE` for a row the two lanes disagree on and `SELFCHECK`
    for a row whose port value is RIGHT and whose recorded note is wrong; the
    two are excluded from different comparisons and neither is a silent row."""
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared "
                      f"divergences must live in git, beside the gate. "
                      f"Run --refresh.")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 4:
            return None, (f"{PINS.name}: a line is not "
                          f"row<TAB>oracle<TAB>port<TAB>kind: {ln!r}")
        row, py_v, port_v, kind = parts
        pins[row] = (f"{row}={py_v}", f"{row}={port_v}", kind)
    return pins, ""


def pin_lines():
    return sum(1 for ln in PINS.read_text().splitlines()
               if ln.strip() and not ln.startswith("#")) if PINS.is_file() else 0


DIVERGES, WHY = _pins()


def divergences_hold():
    """Every pinned row really is a divergence, and the counts are the measured
    ones. Without this a pin list could grow to cover the whole census."""
    if DIVERGES is None:
        return report("divergences_hold", [WHY])
    want, _ = oracle_lane()
    names = [l.split("=", 1)[0] for l in want] if want else []
    bad = []
    lane_n = sum(1 for v in DIVERGES.values() if v[2] == "LANE")
    self_n = sum(1 for v in DIVERGES.values() if v[2] == "SELFCHECK")
    if lane_n + self_n != pin_lines():
        bad.append(f"{len(DIVERGES)} pinned names under {pin_lines()} lines")
    for row in DIVERGES:
        if want and row not in names:
            bad.append(f"pinned row {row!r} is not in the oracle's population")
    got, rec = port_lane()
    by = {l.split("=", 1)[0]: l.split("=", 1)[1] for l in want} if want else {}
    for row, (py_line, _, kind) in DIVERGES.items():
        if kind == "SELFCHECK" and rec.get(row) is not None and \
                f"{rec[row]}" == by.get(row):
            bad.append(f"{row!r} is pinned as stale but its recorded py= "
                       f"already equals CPython's answer")
    return report("divergences_hold", bad)


CLASSES = [
    ("UNHANDLED_ARM", r"^code_for_op (LOAD|MAX|POW)$"),
    ("MISSING_ARM", r"^code_for_op FDIV$"),
    ("WMASK_IS_GRAPH", r"^wmask "),
    ("U32_WIDTH", r"^nan_(mask|thr) double$"),
    ("INDEXERROR_TOTALIZED", r"^workitem l3$"),
    ("TYPE_MAP_KEYERROR", r"^type_map double$"),
    ("SELFCHECK", r"^(nan_uint (float|half|double)|supported_dtypes )"),
]
CLASS_WHY = {
    "UNHANDLED_ARM": "WGSLRenderer.code_for_op is {**CStyleLanguage.code_for_op, "
                     "Ops.WHERE: ...}, so an op with no arm is a KeyError. The "
                     "port answers UNHANDLED(Ops.X) -- a call to nothing, which "
                     "cannot compile. The right totalization; see FINDING 2 for "
                     "why the SAME exception is answered differently by FDIV.",
    "MISSING_ARM": "Ops.FDIV is in ClangRenderer.code_for_op and NOT in "
                   "WGSLRenderer.code_for_op (wgsl.py:60 merges the BASE's "
                   "table, which has no FDIV), and the port adds one. "
                   "wgsl.bend:441-448 records the same measurement and "
                   "axes_hold() re-derives the set difference on every run.",
    "WMASK_IS_GRAPH": "wgsl.py:18 is ((mask << shift_am) ^ 0xFFFFFFFF).cast(u32) "
                      "and shift_am is SYMBOLIC, so CPython has no integer for "
                      "a chosen shift. The oracle's cell reads GRAPH: and "
                      "carries the two CONSTs CPython wrote; the port's is its "
                      "own CONSTANT-FOLDING of the same expression.",
    "U32_WIDTH": "wgsl.py:36's mask is 2**63-1 and its threshold is 2047 << 52. "
                 "A U32 holds 2**32-1. Unreachable from a WGSLRenderer: no "
                 "double in type_map and none in supported_dtypes.",
    "INDEXERROR_TOTALIZED": "'xyz'[int(x)] is an INDEX and 3 is past the end of "
                            "a 3-character string. The port answers \"\" for the "
                            "whole call; x is 0..2 by construction "
                            "(codegen/gpudims.py).",
    "TYPE_MAP_KEYERROR": "wgsl.py:62's type_map has NINE entries and "
                         "render_cast/buf_map index it with brackets, so "
                         "type_map[dtypes.double] RAISES. The port's catch-all "
                         "arm answers UNHANDLED(dtypes.f64) -- a call to a dtype "
                         "WGSL has no name for, which cannot compile. That is "
                         "FINDING 2 FIXED: the arm used to answer the EMPTY "
                         "STRING, a SPELLING no WGSL parser knows and the same "
                         "silent-wrong-answer shape FDIV's fallthrough had. "
                         "supported_dtypes keeps it unreachable from a real "
                         "kernel. The name is `dt_name`'s, which is "
                         "`DType.name`, which is why it reads `f64`.",
    # `RULE_TOTALIZED` IS NOT A CLASS AND THAT IS A FINDING, not an omission.
    # `string_rewrite` rules 0 and 14 both END in `else None` upstream, and
    # `None` is a CONTROL-FLOW state rather than a value: `PatternMatcher.rewrite`
    # reads it as "this rule does not apply" and tries the next one. A port that
    # answered `""` there would be UNCOMPARABLE rather than divergent -- the
    # oracle answers `None` and cannot answer `""` -- so the two rows would have
    # had no verdict at all, which is the quieter of the two failures. Naming the
    # state `NOMATCH` ON BOTH SIDES (`_sr_rewrite` maps Python's `None` to the
    # token the port spells) makes them comparable, and they then AGREE: `sr idx
    # plain` and `sr rmw plain` are EXACT MATCHES, so there is nothing to pin and
    # no class to declare. The token is chosen over `""` precisely because `""` is
    # a SPELLING a shader can hold -- FINDING 2.
    "SELFCHECK": "the port's OWN recorded py= half, which wgsl.bend:82-87 says "
                 "was measured 2026-10-01 by .agents/slop/wgsl-oracle.py. That "
                 "file is GONE, and this tinygrad/'s DType.name has moved to "
                 "the rust spellings since, so the recorded note is stale. The "
                 "PORT'S VALUE IS RIGHT on all five -- these are exact matches "
                 "in the lane comparison -- and the NOTE is wrong.",
}

REPORTED = []


def sr_dispatch_hold():
    """THE THIRTY-FIVE POSITIVE `sr` ROWS, RE-ASKED WHICH RULE CPython'S OWN
    MATCHER WOULD PICK. This is the 34/35 measurement, and it was a `.agents/slop`
    PROBE rather than a check until the fixtures were hoisted out of
    `g_string_rewrite` into the oracle's `sr_fixtures()` -- one declaration, read
    by the row printer AND by this.

    `PatternMatcher.rewrite` takes the FIRST pattern that matches, so "the rule
    this row is on" is a claim about the TABLE and not about a body, and a body
    agreeing with a body says nothing about it. So for every positive fixture the
    gate asks CPython `sr_first(u)` and compares with the row's rule index:

      * 34 of the 35 are the row's own rule -- the row is on the rule the table
        would reach, which is what makes the thirty-five rows thirty-five branch
        proofs rather than thirty-five spellings;
      * ONE IS NOT, and it is `rmw plain`: `UOp.store(idx_pl, vf)` is a packed
        store whose value is an ordinary CONST, so rule 14's `packed_rmw` pattern
        REFUSES it and the matcher FALLS THROUGH to rule 15. Asking rule 14 alone
        answers `None` and that is what the row says on both sides; dispatching
        answers `B = V;`. The fall-through is the finding, so it is ASSERTED
        rather than tolerated: a second fixture that falls through is red here.
    """
    m = _oracle_mod()
    fell = []
    for i, name, u, _p in m.sr_fixtures():
        first = m.sr_first(u)
        if first != i:
            fell.append(f"{name} ({i} -> {first})")
    if len(fell) == 1 and fell[0].startswith("rmw plain"):
        return report("sr_dispatch_hold", [])
    bad = [f"the fixtures CPython's matcher routes to a DIFFERENT rule are {fell}, "
           f"the table says exactly one: rmw plain. A row on a rule the table "
           f"would not reach is a SPELLING and not a proof."]
    if not fell:
        bad.append("rmw plain NO LONGER falls through -- re-measure the store-pair "
                   "order before believing the rest of this check")
    return report("sr_dispatch_hold", bad)


def report(name, bad):
    for b in bad:
        print(f"  {name}: {b}", file=sys.stderr)
    if not bad:
        print(f"  {name}: OK")
    return not bad


def classes_hold():
    """Every pinned row lands in EXACTLY ONE declared class, by the same
    patterns `--refresh` used, and each class carries its reason. A pin that
    moves between classes is a finding that changed shape; a pin with no class
    is a divergence nobody has explained."""
    if DIVERGES is None:
        return report("classes_hold", [WHY])
    bad = []
    got = {}
    for row, (_, _, _kind) in DIVERGES.items():
        hits = [c for c, pat in CLASSES if re.search(pat, row)]
        if not hits:
            bad.append(f"no class for {row!r}")
        elif len(hits) > 1:
            bad.append(f"{row!r} matches {hits}")
        else:
            got[hits[0]] = got.get(hits[0], 0) + 1
    # A CLASS WITH NO ROWS IS NOT A DEFECT, and the one class that is allowed to
    # be empty is `SELFCHECK`: it is a CATEGORY of pin, not a promise that some
    # row is stale. It had five rows on 2026-10-13 and ZERO on 2026-10-14, when
    # the five stale `py=` halves were CORRECTED at the source rather than
    # pinned -- the port's notes now read CPython's own spellings, so those rows
    # became exact matches and there is nothing left for the class to hold.
    # MEASURED: `--refresh` wrote `0 stale self-checks`, and the rows it dropped
    # are the five `nan_uint`/`supported_dtypes` notes. A pin that MOVED because
    # the DEFECT was fixed is a pin whose defect is gone, and deleting the pin is
    # the finding, not a weakening: `selfcheck_hold()` re-derives the stale set on
    # every run and a sixth stale note cannot enter unnoticed.
    # The other six are LANE classes and each must HAVE rows -- an empty one would
    # be a reason nobody needs.
    for c, _ in CLASSES:
        if c == "SELFCHECK":
            continue
        if c not in got:
            bad.append(f"the LANE class {c} has no rows -- a declared divergence "
                       f"class with nothing in it is a reason nobody needs")
    for c, _ in CLASSES:
        if c not in CLASS_WHY:
            bad.append(f"class {c} has no reason")
    return report("classes_hold", bad)


def checks_hold():
    ok = True
    for fn in (names_hold, norm_hold, rules_hold, fixtures_hold, axes_hold,
               pin_drift_hold, never_folding_cast_hold, dead_defs_hold,
               selfcheck_hold, divergences_hold, classes_hold, sr_dispatch_hold):
        ok = fn() and ok
    return ok


# ===========================================================================
# --refresh : rewrite the pins from a fresh pair of lanes. Its ONLY writer.
# ===========================================================================
def refresh():
    """REWRITE the pins from a fresh pair of lanes. Its ONLY writer.

    It does not go through the run loop, because a refresh is exactly what a run
    cannot do when the pins are wrong. The header is regenerated with it,
    because a pins file whose prose outlives its content is a second copy of
    the answer.
    """
    if not warm():
        print("--refresh: the substrate did not warm", file=sys.stderr)
        return 3
    ART.mkdir(parents=True, exist_ok=True)
    if not lane([str(BEND), str(PORT)], "bd.out"):
        return 5
    py = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True,
                        cwd=str(ROOT))
    if py.returncode != 0:
        print(f"--refresh: the oracle failed rc={py.returncode}: "
              f"{py.stderr.strip()[:200]}", file=sys.stderr)
        return 3
    pyrows = [l for l in py.stdout.splitlines() if "=" in l]
    got, rec = port_lane()
    if len(got) != ROWS or len(pyrows) != ROWS:
        print(f"--refresh: row counts py={len(pyrows)} bd={len(got)}, "
              f"expected {ROWS}", file=sys.stderr)
        return 1
    if any(l is None for l in got):
        print("--refresh: the bend lane has a line that is not a row "
              "(see norm_hold)", file=sys.stderr)
        return 1
    by_py = {l.split("=", 1)[0]: l for l in pyrows}
    lane_rows = []
    for line in got:
        name, val = line.split("=", 1)
        if by_py.get(name) != line:
            cls = next((c for c, pat in CLASSES if re.search(pat, name)), None)
            if cls is None:
                print(f"--refresh: no class for {name!r} -- declare one before "
                      f"refreshing, or a new divergence is pinned with no "
                      f"reason", file=sys.stderr)
                return 1
            lane_rows.append((cls, name, by_py[name].split("=", 1)[1], val,
                              "LANE"))
    # THE SELFCHECK ROWS: the port's value is RIGHT and its recorded note is
    # wrong. They are found by comparing the recorded `py=` half against the
    # oracle -- and the LANE divergences are SUBTRACTED first, because for
    # those rows the recorded `py=` IS the port's chosen answer (MEASURED: the
    # first `--refresh` run emitted 17 SELFCHECK rows of which 12 were the 14
    # LANE rows counted again, and two of them collided on a row NAME in the
    # pins dict, which is how this comment exists). So the SELFCHECK set is
    # `stale - lane`, and `selfcheck_hold()` re-derives it that way.
    lane_names = {r[1] for r in lane_rows}
    self_rows = []
    stale = set()
    for name, v in rec.items():
        if v is None:
            continue
        pv = by_py.get(name)
        if pv is not None and pv.split("=", 1)[1] != v:
            stale.add(name)
            if name in lane_names:
                continue
            cls = next((c for c, pat in CLASSES if re.search(pat, name)), None)
            if cls is None:
                print(f"--refresh: stale py= half on {name!r} has no class",
                      file=sys.stderr)
                return 1
            self_rows.append((cls, name, pv.split("=", 1)[1], v, "SELFCHECK"))
    if stale - lane_names != {r[1] for r in self_rows}:
        print(f"--refresh: the stale py= halves less the lane divergences are "
              f"{sorted(stale - lane_names)}, the SELFCHECK rows are "
              f"{sorted(r[1] for r in self_rows)}", file=sys.stderr)
        return 1
    print(f"--refresh: {len(stale)} stale py= halves = {len(stale & lane_names)} "
          f"lane rows whose note records the port's own totalization + "
          f"{len(self_rows)} stale; and {len(lane_names - stale)} lane rows "
          f"whose note IS CPython's value and whose port value knowingly is "
          f"not", file=sys.stderr)
    rows = lane_rows + self_rows
    order = {c: i for i, (c, *_r) in enumerate(CLASSES)}
    rows.sort(key=lambda r: (order[r[0]], r[1]))
    out = [_header(len(lane_rows), len(self_rows))]
    last = None
    for cls, name, pv, bv, kind in rows:
        if cls != last:
            out += ["", f"# {cls} -- {sum(1 for r in rows if r[0] == cls)} "
                        f"rows. {CLASS_WHY[cls]}"]
            last = cls
        out.append(f"{name}\t{pv}\t{bv}\t{kind}")
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(lane_rows)} lane "
          f"divergences, {len(self_rows)} stale self-checks, "
          f"{ROWS - len(lane_rows)} exact, {len(order)} classes")
    return 0


# THE CLASSES THAT HAVE BEEN RETIRED, AND WHY. `_header()` emits this, because
# `--refresh` REWRITES the header and a story written into the pins by hand is
# deleted by the next refresh -- MEASURED, and it happened: eight retired-class
# stories went that way before this was a constant. A divergence class whose rows
# all became EXACT MATCHES is not a weaker reason for being here, it is the
# strongest: the class existed to record that the two sides disagreed, and they
# stopped.
RETIRED = [
    ("PATTERN_UNPORTED (17 rows, retired 2026-10-14)",
     "`wgsl.bend` carried wgsl.py:65-93's seventeen rule BODIES and none of their "
     "`UPat`s, so the port had no predicate that could decline a node: each of the "
     "seventeen `srneg` rows drove a body on a node CPython's own `UPat.match` "
     "REJECTS -- the oracle asserted the rejection at the source, so the row was a "
     "refusal BY CONSTRUCTION -- and the port answered anyway. CARVE-OUT, and the "
     "right one at the time: not a wrong ANSWER but an absent REACHABILITY CHECK, "
     "and pinning it is what stopped the thirty-five `sr` rows from being read as "
     "thirty-five branch proofs. TWO OF THE SEVENTEEN WERE DANGEROUS RATHER THAN "
     "COSMETIC. `srneg 14 store u8` -- a PACKED store of an ordinary CONST -- is "
     "not a read-modify-write, `packed_rmw`'s `AND` was the whole of rule 14's "
     "pattern, and `sr_rmw` answered `atomicAnd(&B[1],W);` and DROPPED THE STORED "
     "VALUE. `srneg 15 store 3` -- a GATED store, three srcs -- fell to rule 15 "
     "and `sr_store` answered `B = V;` and DROPPED THE GATE. Both were "
     "unreachable from `render_kernel` as `wgsl.bend` drove it, and both would "
     "have been a silently wrong shader the moment a dispatcher handed them these "
     "nodes. THE PATTERNS LANDED: each rule now takes the fields its own `UPat` "
     "constrains -- the dtype for the eleven that name one, the op for the three "
     "whose rejecting node is a CONST, the src count for the four that divide on "
     "arity, and rule 6's `src=` clause -- and answers `NOMATCH`, the token "
     "CPython's `None` is spelled, so all seventeen rows are EXACT MATCHES rather "
     "than pins. Rule 13 ALSO GAINED A DEF (`sr_load`): its body was and is "
     "`render_load`, and a pattern is not a body. The rows stayed; the pins went. "
     "`sr pick bitcast`/`load`/`store` are the new rows that make the TABLE's "
     "order measurable, and `sr_dispatch_hold()` is the 34/35 check."),
    ("SELFCHECK_STALE (0 rows)", "see the SELFCHECK reason below -- kept declared "
     "because it is a CATEGORY of pin rather than a promise that a row is stale."),
]


def _header(n_lane, n_self):
    return "\n".join([
        "# wgsl_render_census-pins.rows -- GENERATED by",
        "# `wgsl_render_census-gate.py --refresh`, which is its ONLY writer. One",
        "# TAB-separated QUAD per line: the row NAME, the ORACLE's value, the",
        "# PORT's value, and the KIND (`LANE` the two disagree, `SELFCHECK` the",
        "# port is RIGHT and its own recorded note is wrong).",
        "# Loaded by path by the gate and committed BESIDE it, because a gate's",
        "# declared divergences must live in git -- not in `gates/artifacts/`",
        "# (`.gitignore`d, and where one `rm -rf` takes them) and not in the",
        "# environment of whoever ran it last.",
        f"#\n# {n_lane} LANE DIVERGENCES and {n_self} STALE SELF-CHECKS of "
        f"{ROWS} ROWS.",
        f"# {ROWS - n_lane} EXACT MATCHES.",
        "# Each block is a CLASS, and each class says WHY the two sides differ.",
        "# A pin without a reason is a weakened instrument; a divergence without",
        "# a pin is a silent one.",
        "#",
        "# THE PIN IS THE sha256 OF THE BYTES THE ORACLE IMPORTS, and it is the same",
        "# mechanism `gates/onnx_census-gate.py` and `gates/ops_python_census-gate.py`",
        "# use. It is NOT a git revision: a revision names a COMMIT, and the file the",
        "# oracle opens is the one ON DISK. `pin_drift_hold()` re-measures every one of",
        "# them on every run, against the WORKING TREE.",
        *[f"# {rel}: {sha}" for rel, sha in DRIFT_PIN.items()],
        "#",
        "# AND THE BYTES THE ROWS WERE TAKEN AGAINST, WHICH IS A DIFFERENT SET. A blob",
        "# id is a fact about a COMMIT and it is RECORDED here rather than read at",
        "# refresh time: `git rev-parse HEAD:<path>` answers the blob at HEAD NOW, and",
        "# a header that calls that \"when these rows were taken\" is a label that rots.",
        *[f"# {rel} blob when these rows were taken: {blob}"
          for rel, blob in ROWS_TAKEN_AT.items()],
        "#\n# RETIRED CLASSES -- emitted from the gate's `RETIRED` constant, because",
        "# `--refresh` rewrites this header and MEASURED, eight stories written here",
        "# by hand were deleted by the next refresh.",
    ] + [f"#\n# {name}\n#   {why}" for name, why in RETIRED])


# ===========================================================================
# THE THREE LANES. `gatekit`'s plumbing (BEND, PY, WARM, the `.tmp.` staging
# convention, promote-or-discard) is reused; the run loop is this file's,
# because the pins carry a KIND and `gatekit.Gate.diverges` is a name -> pair
# map with no place for one. `gatekit.py` is not edited.
# ===========================================================================
def _lines(s):
    return [l for l in s.splitlines() if l.strip()]


def _staged(n):
    return ART / f"{TMP}{n}"


def lane(argv, name, rows=ROWS):
    """One lane, retried while it emits the wrong ROW COUNT -- `bend`'s machine
    stack overflows on roughly 1 run in 20 and prints nothing at all, which is
    indistinguishable from 'did not start'. A named failure says which STEP.

    AND THE FLAKE IS NOT BLAMED FOR A DETERMINISTIC COUNT. The first draft ended
    every one of the 25 failures with `in 25 tries (the flake)` whenever the
    producer had said nothing on stderr -- and a mutation that DROPS A ROW does
    exactly that: `bend` succeeds, prints 226 lines and no stderr. MEASURED 2026-10-14
    on the `P1`/`P2` population mutations, whose whole subject is a wrong row count:
    the gate called that the flake, and a reader who believed it would file the two
    most important mutations of the file as transient noise. So the last exit status
    and the last count are both kept and the message says WHICH: a producer that
    RAN is deterministic, and only a producer that produced nothing or died is the
    flake.
    """
    out = _staged(name)
    said, last = "", None
    for _ in range(25):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        got = len(_lines(r.stdout))
        last = (r.returncode, got)
        if r.returncode == 0 and got == rows:
            out.write_text(r.stdout)
            return True
        said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()
                          if l.strip() and not NOTICE.match(l.strip()))
        if said:
            break
    why = ("the flake: it produced nothing" if last is None or last[1] == 0
           else f"DETERMINISTIC: it RAN and printed {last[1]} rows")
    print(f"  lane {name} emitted {last[1] if last else 0} rows, expected {rows}"
          + f" -- {why}" + (f" -- {said}" if said else " -- and said nothing on stderr"),
          file=sys.stderr)
    return False


def warm():
    """`--check-only`'s FIRST LINE, never its exit status: an EMPTY file
    typechecks (gatekit's `_warm`, and the reason it is there)."""
    for _ in range(25):
        r = subprocess.run([str(BEND), str(PORT), "--check-only"],
                           capture_output=True, text=True, cwd=str(ROOT))
        first = (r.stdout or "").splitlines()[:1]
        if first and first[0].strip() == WARM:
            return True
    print(f"  the substrate did not warm: `bend --check-only` never printed "
          f"{WARM!r}", file=sys.stderr)
    return False


def norm_lines(raw):
    """RAW lane lines -> `nm=value` lines. Returns None if a line does not
    decode, which is a FAILURE OF THE LANE and not of the diff."""
    out = []
    for ln in _lines("\n".join(raw)):
        if SEP not in ln:
            return None
        i = ln.index(SEP)
        name, rest = ln[:i], ln[i + len(SEP):]
        m = PYTAIL.search(rest)
        rest = rest[:m.start()] + "]" if m else rest
        if not rest.endswith("]"):
            return None
        out.append(f"{name}={rest[:-1]}")
    return out


def run():
    """PRODUCE THREE LANES, COMPARE THEM, AND SETTLE ON EVERY EXIT."""
    ok = False
    try:
        ART.mkdir(parents=True, exist_ok=True)
        for f in ART.iterdir():
            f.unlink()
        if not warm():
            return REFUSED
        if not lane([str(PY), str(ORACLE)], "py.rows"):
            return REFUSED
        if not lane([str(BEND), str(PORT)], "bd.out"):
            return DEAD
        binp = _staged("gate.bin")
        c = subprocess.run([str(BEND), str(PORT), "-o", str(binp)],
                           capture_output=True, text=True, cwd=str(ROOT))
        if c.returncode != 0:
            print(f"  the native compile failed: {(c.stderr or '').strip()[:200]}",
                  file=sys.stderr)
            return REFUSED
        if not lane([str(binp)], "bn.out"):
            return DEAD

        pyr = _lines("\n".join(_lane_raw_or_empty("py.rows")))
        lanes = {}
        for tag, f in (("bd.out", "bd.out"), ("bn.out", "bn.out")):
            v = norm_lines(_lane_raw_or_empty(f))
            if v is None:
                print(f"  {tag} has a line that is not a row", file=sys.stderr)
                return DEAD
            lanes[tag] = v
        n0 = {"py.rows": len(pyr), **{k: len(v) for k, v in lanes.items()}}
        if any(n != ROWS for n in n0.values()):
            print("  " + ", ".join(f"{t} has {n}" for t, n in n0.items())
                  + f", expected {ROWS}", file=sys.stderr)
            return DEAD if 0 in n0.values() else FAIL

        # THE LANE PINS ARE EXCLUDED ON BOTH SIDES -- a lane is never compared
        # on a row that is KNOWN to differ. The SELFCHECK pins are NOT excluded
        # on the port side, because their PORT value is the correct one.
        pinned_lane = {r for r, v in (DIVERGES or {}).items() if v[2] == "LANE"}
        kept = {t: [l for l in v if l.split("=", 1)[0] not in pinned_lane]
                for t, v in {"py.rows": pyr, **lanes}.items()}
        n = {t: len(v) for t, v in kept.items()}
        if len(set(n.values())) != 1:
            print("  " + ", ".join(f"{t} kept {v}" for t, v in n.items())
                  + " -- the exclusion list is stale", file=sys.stderr)
            return FAIL
        for tag in ("bd.out", "bn.out"):
            if kept[tag] != kept["py.rows"]:
                d = [(x, y) for x, y in zip(kept["py.rows"], kept[tag])
                     if x != y][:2]
                print(f"  DISAGREE ({tag}): {d}", file=sys.stderr)
                return FAIL
        # AND EVERY PIN IS STILL CHECKED -- the exclusion removes a row from
        # the diff; it does not excuse it.
        for row, (pv, bv, kind) in (DIVERGES or {}).items():
            # A LANE pin's port column is the port's VALUE; a SELFCHECK pin's
            # port column is the port's RECORDED NOTE, and its value is the
            # oracle's -- which is why it is an exact match at all. So the
            # value compared on the bend lanes is `pv` for SELFCHECK and `bv`
            # for LANE, and the note is checked separately below.
            port_text = bv if kind == "LANE" else pv
            for tag, text in (("py.rows", pv), ("bd.out", port_text),
                              ("bn.out", port_text)):
                n_hit = sum(1 for l in
                            (pyr if tag == "py.rows" else lanes[tag])
                            if l == text)
                if n_hit != 1:
                    print(f"  {tag}: {text!r} appears {n_hit} times, the pins "
                          f"say 1 -- a pin moved", file=sys.stderr)
                    return FAIL
            if kind == "SELFCHECK":
                note = bv.split("=", 1)[1]      # the pins store `row=note`
                for f in ("bd.out", "bn.out"):
                    rec = _recorded(_lane_raw_or_empty(f))
                    if rec.get(row) != note:
                        print(f"  {f}: {row!r} records {rec.get(row)!r}, the "
                              f"pins say {note!r} -- the port's OWN self-check "
                              f"half moved", file=sys.stderr)
                        return FAIL
        _staged("cmp.rows").write_text("\n".join(kept["py.rows"]) + "\n")
        ok = True
    finally:
        for t in ART.glob(f"{TMP}*"):
            if ok:
                t.replace(ART / t.name[len(TMP):])
            else:
                t.unlink()
    return 0 if ok else 1


LANE_N = sum(1 for v in (DIVERGES or {}).values() if v[2] == "LANE")
SELF_N = sum(1 for v in (DIVERGES or {}).values() if v[2] == "SELFCHECK")
SUMMARY = (f"wgsl_render_census: PASS -- {ROWS} rows x 3 lanes, "
           f"{ROWS - LANE_N} exact, {LANE_N} pinned lane divergences "
           f"in {len({c for c, _ in CLASSES if c != 'SELFCHECK'})} classes, "
           f"{SELF_N} stale self-checks")


def main():
    if "--refresh" in sys.argv:
        sys.exit(refresh())
    if not PINS.is_file():
        print(f"{PINS} is MISSING. A gate's declared divergences must live in "
              f"git, beside the gate:\n    {PY} "
              f"{Path(__file__).name} --refresh", file=sys.stderr)
        sys.exit(REFUSED)
    code = run()
    # THE CHECKS RUN EVEN WHEN THE LANES DISAGREE. `if code == 0 and ...` was
    # the shape this file started with and it is a defect: it means the
    # POPULATION guard only speaks when the population already agrees, so a
    # drift the lane diff happens to catch first is reported WITHOUT the guard
    # that says why. MEASURED, with two ADMITTED axes swapped on the oracle
    # side, the first draft printed one DISAGREE line and not one word from
    # `fixtures_hold`.
    if not checks_hold() and code == PASS:
        code = FAIL
    print(SUMMARY if code == 0 else f"wgsl_render_census-gate: {VERDICT[code]}")
    return code


if __name__ == "__main__":
    sys.exit(main())