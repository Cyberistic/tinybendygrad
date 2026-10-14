#!/usr/bin/env python3
"""ptx_render_census-gate.py -- A RENDER CENSUS over `tinybendygrad/renderer/ptx.bend`.

    .venv/bin/python gates/ptx_render_census-gate.py

557 ROWS, THREE LANES (CPython, bend interpreted, bend compiled), 62 DECLARED DIVERGENCES
IN THREE GROUPS. Run `--refresh` to rewrite `gates/ptx_render_census-pins.rows`; that is
its ONLY writer, and a file nothing can write is a file nothing can check.

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

  GROUP 2 -- `<f>.mod`, 31 rows. CARVE-OUT, and the shape is the point. `string_rewrite` is
    NOT PORTED, so the module cannot be compared; a divergence that says so in one pinned
    string per fixture is the honest record, and the pin means the day the port grows a
    module this gate goes red until the row leaves DIVERGES. Five of the thirty-one are not
    `ABSENT` but `PORT-ANSWERED` (`f31`, `f32`, `f33`, `f34`) or `PORT-REFUSED:INDEX`
    (`f08`): CPython refused and the port did not, which is GROUP 1 reaching the walk.

  GROUP 3 -- the walk, 6 rows. FINDING, NOT A CARVE-OUT. `ptx.bend:502` is
    `case 2: Wal.rput(w, rg_at(w, 0))`, and `rg_at(w, 0)` reads `Wal.r[0]` -- STEP ZERO --
    where ptx.py:189 and ptx.py:204 both read `r[u.src[0]]`, i.e. `Wal.r[refs[0]]`. Every
    one of `ptx.bend`'s OWN twenty-five fixtures puts the aliased node at index 0 (MEASURED:
    `f12_after_ss` is `BUFFER, AFTER(refs=[0]), SINK`), which is why the defect survived a
    green gate. This axis does not: `gates/ptx_render_census-gen.py` reads the src indices
    off CPython's own graph, so `f12_after`'s AFTER carries `refs=[4, 4]` and a LOAD of a
    SPECIAL carries `refs=[3]`. The port answers `NONE` where CPython answers a register,
    and `f10_loads.r9` (`{%g0, %g1, %g2}`) is the cascade -- a STACK built from three
    registers the walk never produced.
    THE FIX IS `rg_at(w, Wk.refs(s)[0])`, i.e. the port needs a `refs`-aware reader where
    `rg_pick` has one; and the pin must come out of DIVERGES when it lands.

WHAT THE DIFF CANNOT SEE, AND WHAT IS SAID INSTEAD
---------------------------------------------------
Two empty lanes would agree on every row, so `claims_hold()` reads the PORT'S OWN `bd.out`
and asserts structural facts no other row produces: the `fmt` boundary pair
(`mov.b32` two tabs, `selp.f32` one), the five EMPTY dtype answers, the `barrier` with its
tab spelled, and the six walk rows that are `NONE` where CPython has a register. A check
never seen to fail is not a check, so `gates/ptx_render_census-mutate.py` carries thirteen
mutations -- including THREE THAT MUTATE THIS GATE'S OWN GUARDS, which is the only way to
show `names_hold`, `axis_hold` and `claims_hold` go red rather than being decoration.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import Gate, gate, PY, BEND  # noqa: E402

ORACLE = HERE / "ptx_render_census-oracle.py"
DRIVER = HERE / "ptx_render_census.bend"
AXIS = HERE / "ptx_render_census_axis.bend"
PINS = HERE / "ptx_render_census-pins.rows"

# 515 rows. The count is DERIVED, never typed: `ROWS = len(run_oracle())` would make the
# count follow the population instead of pinning it, and a count that cannot go wrong is a
# count that cannot catch. So it is asserted instead, and the assertion names the census.
ROWS = 557
N_DIVERGES = 62

# --------------------------------------------------------------------------
# THE DIVERGENCES, generated ONCE from a real run and then FROZEN here. The three
# groups are listed separately so the CHECK can assert the SIZES: a group that grows
# silently is a group nobody read.
# --------------------------------------------------------------------------
# GROUP 1 -- the dtype tables. port -> (REFUSE spelling, what the port answers).
DTYPES_ABSENT = {"void": ("pred", "u8", "pred"), "bf16": ("", "", ""),
                 "fp8e4m3": ("", "", ""), "fp8e5m2": ("", "", ""),
                 "fp8e4m3fnuz": ("", "", ""), "fp8e5m2fnuz": ("", "", "")}
WEAKINT = ("pred", "u8", "pred")


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
            "f32_weakfloat", "f33_bf16cast", "f34_boolalu", "f35_loadvec", "f36_regstore"]
REFUSALS = {"f08_refuse": "PORT-REFUSED:INDEX", "f31_weakint": "PORT-ANSWERED",
            "f32_weakfloat": "PORT-ANSWERED", "f33_bf16cast": "PORT-ANSWERED",
            "f34_boolalu": "PORT-ANSWERED",
            # f35 IS THE SIXTH, AND IT IS NOT A PORT DEFECT: ptx.py:224 refuses an
            # UN-INDEXED PARAM load, and the PORT ALSO refuses -- both because there is no
            # INDEX for ptx.py's LOAD rules to match. It is here so the census's count of
            # refusals is six rather than five and a seventh is red.
            "f35_loadvec": "PORT-ANSWERED"}

# GROUP 3 -- the walk's alias arm.
# GROUP 3a -- the alias arm reads `Wal.r[0]` where ptx.py:189/204 read `Wal.r[refs[0]]`.
ALIAS = {"f07_reuse.r4": "%g0", "f10_loads.r4": "%g0", "f10_loads.r6": "%g1",
         "f10_loads.r8": "%g2", "f10_loads.r9": "{%g0, %g1, %g2}", "f12_after.r5": "%alu_f32_0"}
# GROUP 3b -- GROUP 1 REACHING THE WALK: the five registers the port allocates where
# ptx.py:181 refuses. THESE ARE THE FINDING'S ACTUAL STRINGS.
WEAK = {"f31_weakint.r1": "%ridx_pred_0", "f32_weakfloat.r2": "%alu__0",
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


def _lines(text):
    return [l for l in text.splitlines() if l.strip()]


def run_oracle():
    return _lines(subprocess.run([str(PY), str(ORACLE)], capture_output=True,
                                 text=True, check=True).stdout)


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
    d.update(dtype_divergences())
    d.update({k: (f"{k}={v}", f"{k}=NONE") for k, v in ALIAS.items()})
    d.update({k: (f"{k}=NONE", f"{k}={v}") for k, v in WEAK.items()})
    d.update(module_divergences({l.split("=", 1)[0]: l.split("=", 1)[1]
                                 for l in run_oracle()}))
    return d


DIVERGES = build_divergences()
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
        bad.append(f"the oracle emits {len(pn)} named rows, the census declares {ROWS}")
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
    """THE FIXTURE AXIS, THREE WITNESSES. The census's `fixtures()`, the GENERATED axis's
    `# FIXTURES` line, and the census's REFUSAL column against CPython's own refusals.

    Every one of the three is a text read or a run, never a hand list, and the REFUSAL
    column is the only ADMITTED axis in the file: "which of these graphs does CPython
    refuse" is not something any call RETURNS, so the generator asks by CALLING `render` and
    this check asks again from the oracle's own `.mod=REFUSE:` rows. A sixth refusal on one
    side and not the other is red here, and not a silent extra row in the diff.
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
    if bad:
        print("ptx_render_census-gate: AXIS: " + "; ".join(bad), file=sys.stderr)
    return not bad


def claims_hold() -> bool:
    """STRUCTURAL FACTS, read off the PORT'S OWN `bd.out`.

    Two lanes that both emit `""` agree, so a diff cannot see a renderer that renders
    nothing. Every claim here is a string NO OTHER ROW PRODUCES:
      * the `fmt` BOUNDARY PAIR -- `mov.b32` is seven characters and gets TWO tabs,
        `selp.f32` is eight and gets ONE, and nothing else separates ptx.py:164's rule;
      * the five EMPTY dtype answers -- an empty value next to a row name is the whole
        claim, and `gatekit._lines` would otherwise have nothing to say about it;
      * `barrier` with its TAB spelled rather than emitted;
      * the six GROUP-3 walk rows, which must read `NONE` for as long as the pin stands.
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
            "fmt_18": "$RAW", "fmt_17": "\\tbar.sync\\t0;",
            "tyo_11": "", "mto_11": "", "cto_11": "", "tyo_14": "", "tyo_17": "",
            "barrier": "bar.sync\\t0;",
            "f07_reuse.r4": "NONE", "f10_loads.r9": "NONE", "f12_after.r5": "NONE",
            "f31_weakint.r1": "%ridx_pred_0", "f32_weakfloat.r2": "%alu__0",
            "f33_bf16cast.r1": "%cast__0",
            "f35_loadvec.r1": "{%val_f32_0, %val_f32_1, %val_f32_2, %val_f32_3}",
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
    lines = _lines(PINS.read_text())
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
    body = _lines(PINS.read_text())[1:] if PINS.exists() else []
    rows = [(t, r, v) for t, r, v in (l.split("\t") for l in body)]
    for lane, name in (("py", "py.rows"), ("bd", "bd.out"), ("bn", "bn.out")):
        got, _ = rows_of(d / name)
        rows += [(lane, k, v) for k, v in got.items()]
    rows.sort(key=lambda x: (x[1], x[0]))
    PINS.write_text("\n".join(["lane\trow\tvalue"] + ["\t".join(r) for r in rows]) + "\n")
    print(f"--refresh: wrote {len(rows)} pin rows to {PINS}")
    return 0


if __name__ == "__main__":
    if "--refresh" in sys.argv:
        sys.exit(refresh_pins())
    make_gate()
    assert len(DIVERGES) == N_DIVERGES, f"DIVERGES holds {len(DIVERGES)}, the file says {N_DIVERGES}"
    assert GATE.compared == ROWS - N_DIVERGES == 495
    sys.exit(gate(make_gate(),
                  "ptx_render_census-gate: 557 rows, 3 lanes byte-identical over the walk and "
                  "the SEAM, 62 DECLARED divergences in three groups -- 18 are the dtype "
                  "tables answering `pred` or the EMPTY STRING where ptx.py:181 raises "
                  "KeyError (the PTX form of the AMDWORD32 defect, REACHABLE through "
                  "UOp.range's default weakint) and FIVE MORE are the registers the port "
                  "then allocates where CPython refuses (`%alu__0`, `%cast__0`, "
                  "`%ridx_pred_0`); 33 are the un-ported string_rewrite; and 6 are "
                  "ptx.bend:502's alias arm reading Wal.r[0] where ptx.py:189 reads "
                  "r[u.src[0]] -- invisible to all 25 of ptx.bend's own fixtures because "
                  "every one of them puts the aliased node at index 0",
                  checks=lambda: (names_hold() and axis_hold() and claims_hold() and pins_hold())))