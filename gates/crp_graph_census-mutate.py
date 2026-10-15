#!/usr/bin/env python3
"""Mutation harness for `crp_graph_census-gate.py`.

    .venv/bin/python gates/crp_graph_census-mutate.py            # the whole table
    .venv/bin/python gates/crp_graph_census-mutate.py C1 C2      # only these labels

ONE JOB: prove each of the gate's claims has a mutation, and prove the POPULATION and AXIS
guards speak when the population or the fixture axis is wrong. Four kinds are kept apart,
because a mutation that finds nothing is a COVERAGE GAP and a mutation that cannot compile is
a DEAD DEF, and neither is a pass:

    VALUE        one row's ANSWER moves on the port lane.
    POPULATION   the ROW SET moves -- a family is dropped, a prefix is renamed, a pin is
                 deleted. This is what catches a guard that stopped speaking.
    AXIS         the FIXTURE AXES drift while the row COUNT can stay put.
    GUARD        the gate's OWN `*_hold` is mutated and must go red. A check never seen to
                 fail is not a check, and this gate carries ten of them.

THE PINS SHAPE IS ASSERTED BEFORE ANYTHING IS COUNTED, because a tally parser that assumes a
shape reports what it found rather than what is there. `decomp_value-pins.rows` is the
measured precedent: it is `row/fam<TAB>verdict<TAB>value` and its verdict column holds `same`
175 TIMES, so a parser that counted its second column reported 452 declared divergences where
the truth is 254. `crp_graph_census-pins.rows` is a DIFFERENT shape -- FOUR fields, with a
CLASS in column 2 and a RENDERED VALUE in columns 3 and 4 -- and `amd_dsl_census-pins.rows`
is a THIRD (`row<TAB>oracle<TAB>port`, three fields). `assert_pins()` below fails LOUDLY on
either shape being wrong, and it also refuses a bare verdict token in a value column, so a
pins file that grew one cannot be counted as a set of rendered values.

EVERY COPY LIVES BESIDE ITS ORIGINAL, never in a tmpdir: `creation.bend` does
`import ./dtype.bend` RELATIVE TO ITS OWN PATH and the driver does
`import ./../tinybendygrad/mixin/creation.bend`, so a copy anywhere else answers
"the substrate did not warm" -- a REFUSED exit for the wrong reason, and a harness that calls
that "the mutation was found" has learned nothing. The tree's own four files are NEVER
written.

THE MUTATED ROWS ARE READ BEFORE THE GATE RUNS. `gatekit` EMPTIES `gates/artifacts/` at the
start of every run and unlinks whatever it staged when the run was not green, so reading the
rows afterwards compares the BASE against itself and every mutation reports "moved nothing".

GUARD MUTATIONS REUSE THE LANES INSTEAD OF REBUILDING THEM, and that is stated rather than
implied: they import the mutated gate copy and call `checks_hold()` against the artifacts the
unmutated baseline run left behind, because a guard reads lanes and the lanes are not what the
guard mutation touched. Every other kind runs the whole gate.
"""
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GATE = HERE / "crp_graph_census-gate.py"
ORACLE = HERE / "crp_graph_census-oracle.py"
DRIVER = HERE / "crp_graph_census.bend"
PINS = HERE / "crp_graph_census-pins.rows"
PORT = ROOT / "tinybendygrad" / "mixin" / "creation.bend"
SPEC = ROOT / "tinybendygrad" / "LAWS" / "spec.bend"

# THE MUTATED COPIES. `MUT_PORT` sits beside `creation.bend` because creation.bend imports
# `./dtype.bend` and `./op.bend` beside itself; `MUT_DRIVER` sits beside the gate because the
# driver imports the substrate the same way and because gatekit resolves its inputs beside the
# gate first.
# THE NAMES ARE CHOSEN, NOT COSMETIC. `bend` REFUSES AN IMPORT PATH WHOSE FIRST SEGMENT
# STARTS WITH A DOT -- MEASURED, a dot-prefixed copy answers `expected : an import path of
# plain names (letters, digits, _ and -; the hub's files import the hub's)`, which is a
# REFUSED exit for the wrong reason and a harness that reads that as "the mutation was
# found" has learned nothing. `*mut.bend` is in `.gitignore` (line 36), so the two `.bend`
# copies cannot be swept into a commit if a run is killed; the `.py`/`.rows` copies beside
# the gate are transient in the same way and are unlinked in `finally`.
MUT_PORT = PORT.with_name("creation-mut.bend")
MUT_DRIVER = HERE / "crp-mut-driver.bend"
MUT_ORACLE = HERE / "crp-mut-oracle.py"
MUT_PINS = HERE / "crp-mut-pins.rows"
MUT_SPEC = SPEC.with_name("spec-mut.bend")
MUT_GATE = HERE / "crp-mut-gate.py"
MUT_RUN = HERE / "crp-mut-run.py"
MUT_ART = HERE / "crp-mut-art"
COPIES = (MUT_PORT, MUT_DRIVER, MUT_ORACLE, MUT_PINS, MUT_SPEC, MUT_GATE, MUT_RUN, MUT_ART)
ART = HERE / "artifacts" / "crp_graph_census-gate"

# `creation.bend` is imported BY PATH from the driver, so a mutated PORT is only compiled if
# the driver copy is told to import the copy. Rewriting the import is the whole coupling, and
# it is asserted on both sides: a driver that stopped importing `creation.bend` is a harness
# that would mutate a file nothing reads and report every mutation GREEN.
DRIVER_IMPORT = "import ./../tinybendygrad/mixin/creation.bend as C"
DRIVER_MUT_IMPORT = f"import ./../tinybendygrad/mixin/{MUT_PORT.name} as C"

VERDICT_TOKENS = {"same", "DIFFER", "DIFF", "AGREE", "MATCH", "EXACT"}


def assert_pins(path, nfields, value_columns, label_columns=()):
    """THE PINS SHAPE, OR LOUDLY NOTHING. `(name, col, value)` per row plus the field count.

    A harness that reads a pins file of the wrong shape and reports what it counted has
    produced a number with no meaning, which is the one failure mode this assertion exists to
    stop: `decomp_value-pins.rows` carries `same` in its verdict column 175 times, and a
    parser that added up column 2 there reported 452 declared divergences where the truth is
    254.
    """
    rows, bad = [], []
    for i, ln in enumerate(path.read_text().splitlines()):
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != nfields:
            bad.append(f"line {i + 1} has {len(parts)} fields, not {nfields}: {ln!r}")
            continue
        for c in value_columns:
            if not parts[c].strip():
                bad.append(f"line {i + 1} column {c + 1} is EMPTY -- a pinned value that is "
                           f"not a rendered value is not a pin")
            elif parts[c] in VERDICT_TOKENS:
                bad.append(f"line {i + 1} column {c + 1} is the VERDICT TOKEN "
                           f"{parts[c]!r}, not a rendered value -- this is the "
                           f"`decomp_value` shape and counting it is how 452 became 254")
        rows.append(parts)
    if bad:
        print(f"{path.name}: THE PINS SHAPE IS NOT WHAT THIS HARNESS EXPECTS -- "
              f"{nfields} fields, value columns "
              f"{tuple(c + 1 for c in value_columns)}:\n  "
              + "\n  ".join(bad[:6]), file=sys.stderr)
        raise SystemExit(2)
    return rows


def _write_mutations(port=None, driver=None, oracle=None, pins=None, spec=None):
    MUT_PORT.write_text(PORT.read_text() if port is None else port)
    MUT_ORACLE.write_text(ORACLE.read_text() if oracle is None else oracle)
    MUT_PINS.write_text(PINS.read_text() if pins is None else pins)
    MUT_SPEC.write_text(SPEC.read_text() if spec is None else spec)
    src = DRIVER.read_text() if driver is None else driver
    if DRIVER_IMPORT not in src:
        raise SystemExit(f"{DRIVER}: the creation.bend import {DRIVER_IMPORT!r} is gone -- "
                         f"this harness rewrites it and cannot")
    MUT_DRIVER.write_text(src.replace(DRIVER_IMPORT, DRIVER_MUT_IMPORT))


def _runner(gate_path, checks_only):
    """A driver script that imports the gate COPY and points its module constants at the
    mutated files.

    `DIVERGES` IS READ AT IMPORT TIME, so overriding `m.PINS` alone would leave the mutated
    pins unused and every pins mutation a silent green. `GATE` is a `Gate` OBJECT BUILT AT
    IMPORT TIME too, so its `rows`/`compared`/`diverges` are re-derived here EXACTLY as
    `crp_graph_census-gate.py:842-849` derives them -- that is a RE-DERIVATION from the mutated
    files, not a weakening, and without it a pins mutation would red on a stale row count
    instead of on the divergence it is about.

    **AND IMPORTING THIS GATE EMPTIES ITS OWN ARTIFACT DIRECTORY.** `gatekit.Gate.__init__`
    calls `_clear()`, and `crp_graph_census-gate.py:842` builds `GATE = Gate(...)` at MODULE
    SCOPE -- so the destruction happens at `exec_module`, before any check runs and whether or
    not the gate is ever run. **MEASURED: 11 of 11 guard mutations reported
    `names_hold: bd printed 0 rows` until the lanes were snapshotted around the import**, so
    every guard was red and ten of them were red for a reason that had nothing to do with the
    mutation. `amd_dsl_census-gate.py` does NOT have this shape -- its `run()` owns the
    clearing, not its module scope -- which is why its guards report their own reasons.
    """
    head = ("import importlib.util, sys, re, shutil\nfrom pathlib import Path\n"
            "art, snap = Path(%r), Path(%r)\n"
            "if art.is_dir():\n"
            "    shutil.rmtree(snap, ignore_errors=True)\n"
            "    shutil.copytree(art, snap)\n"
            "spec = importlib.util.spec_from_file_location('g', %r)\n"
            "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
            "if snap.is_dir():\n"
            "    shutil.rmtree(art, ignore_errors=True)\n"
            "    shutil.copytree(snap, art)\n"
            "    shutil.rmtree(snap, ignore_errors=True)\n"
            % (str(ART), str(MUT_ART), str(gate_path)))
    if checks_only:
        return head + "sys.exit(0 if m.checks_hold() else 1)\n"
    # `crp_graph_census-gate.py` has NO `main()`: its module scope ends in
    # `sys.exit(gate(GATE, "...", checks=checks_hold))` under `if __name__ == "__main__"`, and
    # this runner imports it under the name `g`, so that block does not fire. The gate call is
    # therefore made HERE, on the same `GATE` object and the same `checks_hold` the gate's own
    # last line would have used. The SUMMARY text is the harness's -- it is the only thing this
    # harness substitutes, and `gate()`'s exit code does not read it.
    body = (
        f"m.PORT = Path({str(MUT_PORT)!r})\nm.DRIVER = Path({str(MUT_DRIVER)!r})\n"
        f"m.ORACLE = Path({str(MUT_ORACLE)!r})\nm.PINS = Path({str(MUT_PINS)!r})\n"
        f"m.SPEC = Path({str(MUT_SPEC)!r})\n"
        "m.DIVERGES, m.WHY = m._pins()\n"
        "if m.DIVERGES is None:\n"
        "    print(m.WHY, file=sys.stderr); sys.exit(3)\n"
        "m.ROWS = len(m.expected_rows())\n"
        "m.GATE.rows = m.ROWS\n"
        "m.GATE.compared = m.ROWS - len(m.DIVERGES)\n"
        "m.GATE.diverges = {r: v for r, (_c, v) in m.DIVERGES.items()}\n"
        "m.GATE.bend = m.DRIVER\n"
        "m.GATE.oracle = m.ORACLE\n"
        f"sys.path.insert(0, {str(HERE)!r})\n"
        "from gatekit import gate\n"
        "sys.exit(gate(m.GATE,\n"
        "             f'crp_graph_census-gate (MUTATED COPY): {m.ROWS} rows, '\n"
        "             f'{m.ROWS - len(m.DIVERGES)} compared, {len(m.DIVERGES)} declared',\n"
        "             checks=m.checks_hold))\n")
    return head + body


def _clean():
    for p in COPIES:
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)
        else:
            p.unlink(missing_ok=True)


def run_gate(gate_text=None, checks_only=False):
    """`(rc, stdout+stderr)` for the gate against the mutated tree. `gate_text` replaces the
    gate's OWN source, which is what a GUARD mutation is."""
    if gate_text is not None:
        MUT_GATE.write_text(gate_text)
    else:
        MUT_GATE.write_text(GATE.read_text())
    MUT_RUN.write_text(_runner(MUT_GATE, checks_only))
    try:
        r = subprocess.run([sys.executable, str(MUT_RUN)], capture_output=True, text=True,
                           cwd=str(ROOT))
        return r.returncode, r.stdout + r.stderr
    finally:
        MUT_RUN.unlink(missing_ok=True)


def lane_rows(argv):
    """The lane's lines, AS A LIST, read MYSELF and BEFORE the gate runs -- `gatekit` EMPTIES
    `gates/artifacts/` at the start of every run and unlinks what it staged when the run was
    not green, so reading the rows afterwards compares the BASE against itself and every
    mutation reports "moved nothing". That is this harness's own version of class (e): a test
    that does not read its input."""
    r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        return None, ((r.stderr or r.stdout).strip().splitlines() or ["no output"])[-1:]
    return [l for l in r.stdout.splitlines() if "=" in l], []


def bare(sig):
    """THE PRE-REPAIR PRINTER: every `[...]` dropped. `OP/NSRC` is exactly what
    `tok.arg` (driver:174-179) printed for an `ADt` before the `ADt` arm existed, and what
    `crp_graph_census-oracle.py`'s `tok` printed for every op but CONST and ALLOC.

    IT IS WHAT MAKES A CLAIM ABOUT THE PRINTER FALSIFIABLE. A mutation can move a row
    WITHOUT the new `CAST/1[<dt>]` token being the reason, and the way to tell is to run
    the SAME comparison with the argument dropped: `MOVED > 0` with `BARE == 0` is the
    repair's own doing, and `MOVED == BARE` is a mutation the old printer already caught.
    `gates/decomp_graph_census-mutate.py:147` is the sibling instrument and the reason is
    the same one."""
    return ",".join(tok.split("[", 1)[0] for tok in sig.split(","))


def moved_bare(base, got):
    """THE POSITIONAL COUNT UNDER `bare()`, or `None` when a lane is dead. Same shape as
    `moved` on purpose: a DEAD lane must read as dead here too rather than as 0."""
    if got is None or len(got) != len(base):
        return None
    return sum(1 for a, b in zip(base, got) if bare(a.split("=", 1)[1]) != bare(b.split("=", 1)[1]))


def moved(base, got):
    """`(moved, appeared, vanished)` POSITIONALLY when the lengths agree -- which is how
    `gatekit` diffs, so a RENAMED row counts as a moved row rather than as an appearance --
    and as a MULTISET OF NAMES BY A COUNT when they do not. MEASURED WHY THE SECOND HALF
    MATTERS: dropping a dtype family from the ORACLE leaves the port lane byte identical, so a
    reader that only looks for CHANGED VALUES answers "0 rows moved" for a mutation that
    removed twenty of them -- and the first version of this harness did exactly that."""
    if got is None:
        return 0, [], sorted({l.split("=", 1)[0] for l in base})
    if len(got) == len(base):
        return sum(1 for a, b in zip(base, got) if a != b), [], []
    bn = Counter(l.split("=", 1)[0] for l in base)
    gn = Counter(l.split("=", 1)[0] for l in got)
    return 0, sorted((gn - bn).elements()), sorted((bn - gn).elements())


# THE TABLE. `(label, kind, file, find, replace)`. `file` is one of port/driver/oracle/pins/
# spec/gate, and every `find` is ASSERTED UNIQUE before it is applied, so a mutation that
# silently stopped matching is a REFUSED entry and not a green one.
MUTATIONS = [
    # ---------------------------------------------------------------- VALUE
    ("V1 cr_cast_dt's True arm answers dt -- the PRE-FIX predicate", "VALUE", "port",
     "    case True{}: cr_from_py(O.CInvalid{})",
     "    case True{}: dt"),
    ("V2 cr_cast_dt's `_` arm answers the REPLACEMENT dtype", "VALUE", "port",
     "    case _:       dt",
     "    case _:       cr_from_py(O.CInvalid{})"),
    ("V3 cr_from_py's CInvalid arm answers weakint", "VALUE", "port",
     "    case O.CInvalid{}: S.boolean()",
     "    case O.CInvalid{}: S.weakint()"),
    ("V4 cr_from_py's CFloat arm answers weakint", "VALUE", "port",
     "    case O.CFloat{f}:  S.weakfloat()",
     "    case O.CFloat{f}:  S.weakint()"),
    ("V5 the fold predicate is TRUE -- every const is a BARE const", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(True{}, T.tn_const(ar, v), de)"),
    ("V6 cr_after builds the AFTER in a FRESH arena (stale arena, class (a))", "VALUE", "port",
     "  T.tn_alu.put(O.UOp.new(O.Found.ar(s), O.OpsAFTER{}, [T.Tensor.u(r), O.Found.i(s)], O.ANone{}, O.TNone{}))",
     "  T.tn_alu.put(O.UOp.new(O.Arena.empty(), O.OpsAFTER{}, [T.Tensor.u(r), O.Found.i(s)], O.ANone{}, O.TNone{}))"),
    ("V7 cr_cval1's int arm is 2, not 1", "VALUE", "port",
     "    case _: MO.mo_ki(1)",
     "    case _: MO.mo_ki(2)"),
    ("V8 cr_cval0's bool arm is True, not False", "VALUE", "port",
     "    case True{}: O.CBool{False{}}",
     "    case True{}: O.CBool{True{}}"),

    # ------------------------------------------- THE COUPLING OF `de`, AND THE POINT
    # `cr_const_of` hands ONE value `de` to TWO uses: the fold test's right-hand side and
    # the CAST's `ADt` argument, and the fix's claim is that they cannot disagree. C1 breaks
    # ONLY the second, C2 breaks ONLY the first, C3 breaks both, and C4 does C1 with
    # `opscast_hold`'s source-text assertion removed -- because C1's RED, if it has one at
    # all, may be coming from a check that reads the gate's expectation of the SPELLING rather
    # than from a row, and those are different instruments.
    ("C1 the CAST's ADt argument reads dt -- ONE use of de broken", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), dt)"),
    ("C2 the fold test reads dt -- the OTHER use of de broken", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, dt), T.tn_const(ar, v), de)"),
    ("C3 BOTH uses read dt -- the pre-fix line written out loud", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, dt), T.tn_const(ar, v), dt)"),
    # C1 AGAIN, AND `opscast_hold` -- WHICH CHECKS THE SPELLING OF THE LINE C1 BREAKS -- TOLD
    # TO EXPECT THE C1 SPELLING. If C1's red came from a ROW, C4 is green. If C1's red came
    # from `opscast_hold` matching a literal, C4 is green too, and then the red C1 produced was
    # never a statement about the two uses of `de` at all. The sixth field of an entry is an
    # OPTIONAL `(old, new)` patch applied to THE GATE ITSELF alongside the port edit.
    ("C4 C1 with opscast_hold expecting the C1 spelling -- the rows, alone", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), dt)",
     ('("cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",',
      '("cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), dt)",')),
    # C5 IS THE QUANTITATIVE FORM OF C4, AND IT IS THE MUTATION THE PRINTER REPAIR MADE
    # LIVE. `tok.arg` used to match `APy` and `AParam` and answer everything else with
    # `tok.of(a, u, False{}, "")` -- so a CAST's `ADt` printed as the bare token `CAST/1` --
    # and `crp_graph_census-oracle.py`'s `tok` did the same with `f"{u.op.name}/{len(u.src)}"`.
    # MEASURED ON THE BASE LANES: 118 `CAST/1` occurrences and 0 of them carried an argument,
    # on BOTH sides, and the PREDICTION THIS ENTRY USED TO CARRY -- "hardcoding it to the
    # WRONG dtype at every minted CAST must move nothing" -- WAS TRUE THEN AND IS FALSE NOW.
    # `tok.arg` grew its `ADt` arm and the oracle grew its `isinstance(u.arg, DType)` arm, so
    # `BARE == 0` and `MOVED == 118` is the printer's own doing. THE PREDICTION IS KEPT AS
    # A `BARE` READING BECAUSE `MOVED-BARE` IS THE PRE-REPAIR INSTRUMENT: a reader who
    # believes this comment can check it by running the same mutation under `bare()`.
    ("C5 every minted CAST's ADt is hardcoded boolean -- 118 wrong arguments", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), S.boolean())"),
    # C6 IS C1 WITH THE WRONG REPLACEMENT, AND THE PAIR IS THE MEASUREMENT. C1 answers `dt`,
    # C6 answers `c0` -- the CONST's OWN DERIVED dtype, which is the OTHER operand of the
    # fold test. `dt == de` at EVERY minted CAST, so C1 is invisible; `c0 != de` at every one
    # of them, so C6 is not. IF C6 MOVES ROWS AND C1 DOES NOT, THEN THE THIRD ARGUMENT OF
    # `cr_cast` IS IN THE TOKEN AND `de`'s SECOND USE IS THE VACUOUS ONE -- which is the
    # claim the printer was added to test, and it is now a number rather than an argument.
    ("C6 the CAST's ADt argument reads c0 -- the fold test's OTHER operand", "VALUE", "port",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",
     "  cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), c0)"),

    # ------------------------------------------------- THE PRINTER, ON BOTH LANES
    # C5 SAYS THE `ADt` IS NOW IN A TOKEN. THESE TWO SAY WHICH LANE PUT IT THERE, and they
    # are the pair that stops a printer from being load-bearing on ONE side only: with only
    # the port's arm, the two lanes would DISAGREE on all 118 casts and the gate would be
    # RED for a printer difference rather than for a port difference, which is the
    # `tn_bitwise_not` failure wearing a census's clothes.
    ("D1 the DRIVER's printer loses its ADt arm -- 118 bare tokens on the port lane",
     "VALUE", "driver",
     '    case O.ADt{d}:    tok.of(a, u, True{}, String.concat([tok.plain(a, u), '
     '"[", T.dt_name(d), "]"]))\n', ""),
    ("D2 the ORACLE's printer loses its DType arm -- 118 bare tokens on CPython's lane",
     "VALUE", "oracle",
     '    if isinstance(u.arg, DType):\n        return f"{u.op.name}/{len(u.src)}'
     '[{u.arg.name}]"\n', ""),

    # ------------------------------------------------------------ POPULATION
    ("P1 the driver walks NO dtypes for the `cl` family", "POPULATION", "driver",
     '    e : Unit <- fam.go(4n, "cl", dts())',
     '    e : Unit <- fam.go(4n, "cl", Nil{})'),
    ("P2 the driver RENAMES the `cl` prefix (same count, new names)", "POPULATION", "driver",
     '    e : Unit <- fam.go(4n, "cl", dts())',
     '    e : Unit <- fam.go(4n, "q1", dts())'),
    ("P3 the driver's `shp()` LOSES a shape", "POPULATION", "driver",
     "def shp() -> List<&2, List<&2, U32>>: [[], [4], [2, 3], [2, 3, 4]]",
     "def shp() -> List<&2, List<&2, U32>>: [[], [4], [2, 3]]"),
    ("P4 the ORACLE loses a dtype family", "POPULATION", "oracle",
     'FAMS = ("zl", "ol", "fl", "el", "cl", "f", "iv", "z", "eb")',
     'FAMS = ("zl", "ol", "fl", "el", "cl", "f", "iv", "z")'),
    ("P5 the ORACLE loses a shape", "POPULATION", "oracle",
     "SHAPES = ((), (4,), (2, 3), (2, 3, 4))",
     "SHAPES = ((), (4,), (2, 3))"),
    # P6 DELETES THE WHOLE LINE. The first version replaced `"el_weakint\tW3-BOUNDS\t"` with
    # the empty string, which left the two VALUES as a TWO-field line, and `_pins()` answered
    # REFUSED -- the right instrument, for the wrong reason: it never reached the question,
    # which is what happens when a pins file is the declared divergence and the pin is gone.
    ("P6 the pins DELETE the one declared divergence", "POPULATION", "pins",
     "el_weakint\tW3-BOUNDS\tALLOC/0[i32 sz=6 GLOBAL bind=True],CONST/0[2:weakint],"
     "CONST/0[3:weakint],STACK/2,RESHAPE/2\tALLOC/0[i64 sz=6 GLOBAL bind=True],"
     "CONST/0[2:weakint],CONST/0[3:weakint],STACK/2,RESHAPE/2\n", ""),
    ("P6b the pins RENAME the one declared divergence", "POPULATION", "pins",
     "el_weakint\tW3-BOUNDS\t", "el_weakintX\tW3-BOUNDS\t"),
    ("P7 the pins EDIT the port's value for the one divergence", "POPULATION", "pins",
     "STACK/2,RESHAPE/2\n", "STACK/2,RESHAPE/2,MOVEMENT/2\n"),
    ("P8 spec.bend GAINS a dtype (the discovered population grows by 9)", "POPULATION",
     "spec",
     'def double() -> Dt: Dt{15, 64, CFloat{}, "f64"}',
     'def double() -> Dt: Dt{15, 64, CFloat{}, "f64"}\ndef f8e4m3() -> Dt: Dt{16, 8, '
     'CFloat{}, "f8e4m3"}'),

    # ----------------------------------------------------------------- AXIS
    ("X1 the oracle's SHAPE axis moves to (2,3,4)", "AXIS", "oracle",
     "SHAPE = (2, 3)", "SHAPE = (2, 3, 4)"),
    ("X2 the oracle's receiver is BUFFERED, so weakint is an i32 receiver", "AXIS", "oracle",
     "    return Tensor.zeros(SHAPE, dtype=dt, buffer=False, device=DEV)",
     "    return Tensor.zeros(SHAPE, dtype=dt, device=DEV)"),
    ("X3 spec.bend's dtype PRIORITY axis moves, every row still matching", "AXIS", "spec",
     'def int32() -> Dt: Dt{5, 32, CSint{}, "i32"}',
     'def int32() -> Dt: Dt{15, 32, CSint{}, "i32"}'),

    # ---------------------------------------------------------------- GUARD
    # One mutation per `*_hold`, each of which makes the check's OWN claim false on a
    # healthy tree. `checks_only=True` is deliberate and is recorded in the report: the lanes
    # are what the baseline run left in `gates/artifacts/crp_graph_census-gate/`, and a guard
    # mutation does not touch them.
    ("G1 names_hold: the discovered tail is 8, not 7", "GUARD", "gate",
     "TAIL = 7                     # the six `in_*` rows and `ctl_2`",
     "TAIL = 8                     # the six `in_*` rows and `ctl_2`"),
    ("G2 methods_hold: `_multi_like` is no longer declared unported", "GUARD", "gate",
     'MISSING = {"_multi_like": "W2, the multi-device arm (creation.py:16-20); `cr_full_like` "\n'
     '                          "is single-device and the tuple arm is a TODO(p3) at "\n'
     '                          "creation.bend:414",\n           "const": "a '
     '`raise NotImplementedError` (creation.py:12), a @staticmethod, and so "\n'
     '                    "neither regex matches it; it has no def and no graph"}',
     'MISSING = {"const": "a `raise NotImplementedError` (creation.py:12), a @staticmethod, '
     'and so "\n                    "neither regex matches it; it has no def and no graph"}'),
    ("G3 dtypes_hold: no dtype field is declared off", "GUARD", "gate",
     'PRI_OFF = {"void"}', "PRI_OFF = set()"),
    ("G4 receiver_hold: the buffered CONTROL asserts the wrong half", "GUARD", "gate",
     "        if dt is dtypes.weakint and Tensor0(dt, buffered=True).dtype is dt:",
     "        if dt is dtypes.weakint and Tensor0(dt, buffered=False).dtype is dt:"),
    ("G5 frompy_hold: the CInvalid witness is claimed by a row that does not hold it",
     "GUARD", "gate",
     'witness = {"CInvalid": ("iv_bool", "CONST/0[Invalid:"),',
     'witness = {"CInvalid": ("cl_bool", "CONST/0[Invalid:"),'),
    ("G6 opscast_hold: the fold test is expected in its PRE-FIX spelling", "GUARD", "gate",
     '("cr_cast(D.md_dt_eq(c0, de), T.tn_const(ar, v), de)",',
     '("cr_cast(D.md_dt_eq(c0, dt), T.tn_const(ar, v), dt)",'),
    # G7 POINTS THE BODY COMPARISON AT A DEF THAT ACTUALLY MOVED. The first version moved the
    # PIN to `ad117c928` and was GREEN -- and measuring why is the reading: `UOp.const` and
    # `UOp.toposort` are byte-identical between `ad117c928^` and HEAD (505 and 702 bytes,
    # MEASURED), which IS this gate's own claim, so extracting either of them twice cannot
    # disagree and the assertion cannot fail on a healthy tree. `UOp.param_like` is 735 bytes
    # at the pin and 777 at HEAD (MEASURED), so naming it makes the comparison a real one.
    ("G7 drift_hold: the BODY comparison is pointed at a def that drifted", "GUARD", "gate",
     '(r"^  def toposort\\(self, gate.*?(?=^  def topovisit)", "UOp.toposort")',
     '(r"^  def param_like\\(self.*?(?=^  def )", "UOp.param_like")'),
    # G7b IS A DELIBERATE WEAKENING AND IS EXPECTED GREEN: `tinygrad/helpers.py` HAS drifted
    # since the pin (the gate's header says so), so removing one entry from `VENDORED` silences
    # a real and recorded finding, and nothing turns red. That is the reading, not a pass.
    ("G7b drift_hold: one DRIFTED file is dropped from VENDORED (a WEAKENING, expected GREEN)",
     "GUARD", "gate",
     'VENDORED = ("tinygrad/mixin/creation.py", "tinygrad/uop/ops.py", "tinygrad/dtype.py",\n'
     '            "tinygrad/helpers.py", "tinygrad/mixin/dtype.py", "tinygrad/mixin/movement.py",\n'
     '            "tinygrad/tensor.py")',
     'VENDORED = ("tinygrad/mixin/creation.py", "tinygrad/dtype.py",\n'
     '            "tinygrad/mixin/dtype.py", "tinygrad/mixin/movement.py",\n'
     '            "tinygrad/tensor.py")'),
    ("G8 classes_hold: the W3 relation is i32 -> i8 rather than i32 -> i64", "GUARD", "gate",
     'pv.replace("ALLOC/0[i32", "ALLOC/0[i64") != bv',
     'pv.replace("ALLOC/0[i32", "ALLOC/0[i8") != bv'),
    ("G9 fold_axis_hold: the fold set is read off the `iv_` family, not `f_`", "GUARD", "gate",
     '    bare = [d for d in dts if "CAST/1" not in py.get(f"f_{d}", "")]\n'
     '    casty = [d for d in dts if "CAST/1" in py.get(f"f_{d}", "")]',
     '    bare = [d for d in dts if "CAST/1" not in py.get(f"iv_{d}", "")]\n'
     '    casty = [d for d in dts if "CAST/1" in py.get(f"iv_{d}", "")]'),
    ("G10 no_noop_bottom: the bottom is spelled EXPAND", "GUARD", "gate",
     '        for l in _lines(f.read_text()):\n'
     '            if "=" in l and "NOOP" in l.split("=", 1)[1]:',
     '        for l in _lines(f.read_text()):\n'
     '            if "=" in l and "EXPAND" in l.split("=", 1)[1]:'),
    # G11 AND G12 ARE FOR THE TWO CHECKS THE PRINTER REPAIR MADE STRONGER. A check that has
    # never been seen to fail is not a check, and these two halves did not exist before.
    # G11 LOOSENS `SPEC_NM`'s CAPTURE so it reads twenty EMPTY names, which must be a red run
    # rather than twenty rows that happen to agree.
    ("G11 dtypes_hold: the nm capture is loosened to a zero-width class", "GUARD", "gate",
     'r\'^def [a-z_0-9]+\\(\\) -> Dt: Dt\\{[0-9]+, [0-9]+, \\w+\\{\\}, "([^"]+)"\\}\', re.M)',
     'r\'^def [a-z_0-9]+\\(\\) -> Dt: Dt\\{[0-9]+, [0-9]+, \\w+\\{\\}, "[^"]*"\\}\', re.M)'),
    # G12 AND G13 ASSERT NUMBERS THAT DID NOT EXIST BEFORE EITHER: the `iv_` rows' zero casts
    # and their nineteen `de != dt` cells. Both are the row-visible half of FINDING 1b.
    ("G12 fold_axis_hold: the iv_ count is 20, not 19", "GUARD", "gate",
     "if req_diff != 19:", "if req_diff != 20:"),
    ("G13 fold_axis_hold: the casting rows' TARGET is not checked", "GUARD", "gate",
     'elif f"CAST/1[{d}]" not in py[f"f_{d}"]:',
     'elif f"CAST/1[zzz]" not in py[f"f_{d}"]:'),
]

SOURCES = {"port": PORT, "driver": DRIVER, "oracle": ORACLE, "pins": PINS, "spec": SPEC,
           "gate": GATE}


def main(argv):
    pins = assert_pins(PINS, 4, (2, 3), (1,))
    classes = sorted({p[1] for p in pins})
    print(f"crp pins shape ASSERTED: 4 fields, column 2 is a CLASS in {classes}, columns 3 "
          f"and 4 are rendered values; {len(pins)} pin(s)\n")

    want = [m for m in MUTATIONS if not argv or m[0].split()[0] in argv]
    # GUARDS FIRST, AND THE ORDER IS LOAD-BEARING. A guard mutation reads the lanes in
    # `gates/artifacts/crp_graph_census-gate/`, and `gatekit` EMPTIES that directory at the
    # start of every run and leaves it EMPTY when the run was not green -- so a guard mutation
    # that runs after a red input mutation reads an EMPTY artifact and goes red on
    # `names_hold: bd printed 0 rows`, which is a REFUSED-for-the-wrong-reason verdict about a
    # check that had nothing to do with the mutation. MEASURED: the first full run did exactly
    # that for 10 of 11 guards.
    want.sort(key=lambda m: m[1] != "GUARD")
    width = max(len(m[0]) for m in want)
    kinds, moved_any, zero, zero_red, refused, guards, guard_fail, notrun = \
        {}, 0, [], [], 0, 0, 0, []
    try:
        _write_mutations()          # the UNMUTATED copies: every path must EXIST, because a
        # missing one is a REFUSED exit for the wrong reason and a baseline that is
        # REFUSED proves nothing about any mutation.
        rc0, out0 = run_gate()
        base_bd, why = lane_rows([str(ROOT / "bin" / "bend"), str(DRIVER)])
        base_py, _ = lane_rows([str(ROOT / ".venv" / "bin" / "python"), str(ORACLE)])
        if rc0 != 0 or base_bd is None or base_py is None:
            print(f"crp_graph_census-gate: the UNMUTATED tree is rc={rc0} and the lanes are "
                  f"{len(base_bd or [])} / {len(base_py or [])}, so every mutation below would "
                  f"be meaningless\n{out0}{why}")
            return 1
        print(f"UNMUTATED  rc={rc0}  bd={len(base_bd)} rows  py={len(base_py)} rows  "
              f"{sum(1 for a, b in zip(base_py, base_bd) if a != b)} divergence(s)\n")
        for entry in want:
            label, kind, f, old, new = entry[:5]
            gate_patch = entry[5] if len(entry) > 5 else None
            kinds[kind] = kinds.get(kind, 0) + 1
            mv, ap, va = 0, [], []
            src = SOURCES[f].read_text()
            if src.count(old) != 1:
                print(f"  {label:<{width}}  [{kind}]  REFUSED: the pattern occurs "
                      f"{src.count(old)} times, expected 1")
                refused += 1
                continue
            gtext = None
            if gate_patch is not None:
                # The gate is patched ALONG WITH the input, and BOTH patterns are asserted
                # unique -- a gate patch that matched twice would silently edit the wrong
                # occurrence and produce a green that means nothing.
                if GATE.read_text().count(gate_patch[0]) != 1:
                    print(f"  {label:<{width}}  [{kind}]  REFUSED: the GATE pattern occurs "
                          f"{GATE.read_text().count(gate_patch[0])} times, expected 1")
                    refused += 1
                    continue
                gtext = GATE.read_text().replace(*gate_patch)
            text = src.replace(old, new)
            if f == "gate":
                rc, out = run_gate(gate_text=text, checks_only=True)
                guards += 1
                if rc != 0:
                    guard_fail += 1
                print(f"  {label:<{width}}  [GUARD]  rc={rc}  "
                      + ("RED  the guard speaks" if rc
                         else "GREEN  <-- THE CHECK DID NOT FIRE"))
            else:
                _write_mutations(**{f: text})
                bd, w = lane_rows([str(ROOT / "bin" / "bend"), str(MUT_DRIVER)])
                py, _ = lane_rows([str(ROOT / ".venv" / "bin" / "python"), str(MUT_ORACLE)])
                mv, ap, va = moved(base_bd, bd)
                br = moved_bare(base_bd, bd)
                if py is not None and py != base_py:
                    pm, pa, pv = moved(base_py, py)
                    mv, ap, va = mv + pm, ap + pa, va + pv
                    qb = moved_bare(base_py, py)
                    br = None if br is None or qb is None else br + qb
                rc, out = run_gate(gate_text=gtext)
                n = mv + len(ap) + len(va)
                if n:
                    moved_any += 1
                elif rc == 0:
                    zero.append(label)
                else:
                    # MOVED NOTHING AND STILL WENT RED. This is the reading that matters and
                    # the reason the two lists are separate: the mutation was caught by a
                    # check that does not read a row -- `opscast_hold` matching the gate's
                    # expectation of the SPELLING, in C1's case -- so the ROWS said nothing
                    # about it and only the guard did.
                    zero_red.append(label)
                if bd is None:
                    notrun.append(label)
                print(f"  {label:<{width}}  [{kind}]  rc={rc} "
                      + ("RED" if rc else "GREEN  <-- THE MUTATION WAS NOT FOUND")
                      + f"  {n} rows moved"
                      + (f"  bare={br}" if br is not None else "  bare=DEAD-LANE")
                      + (f", {len(ap)} appeared" if ap else "")
                      + (f", {len(va)} vanished" if va else "")
                      + (f", bend rc!=0 -- {w[0][:70]}" if bd is None else ""))
            said = [ln.strip() for ln in out.splitlines()
                    if ln.strip() and ": OK" not in ln
                    and not ln.lstrip().startswith(("UNMUTATED", "crp_graph_census-mutate",
                                                    "crp pins"))
                    and any(k in ln for k in ("_hold:", "DISAGREE", "REFUSED", "rows,",
                                              "is not '", "COMPARED", "not the pin",
                                              "disagree"))]
            for ln in said[:3]:
                print(f"      {ln[:170]}")
            for lbl, xs in (("APPEARED", ap), ("VANISHED", va)):
                if xs:
                    print(f"      {lbl} {', '.join(xs[:8])}"
                          + (f" (+{len(xs) - 8})" if len(xs) > 8 else ""))
    finally:
        _clean()
    print(f"\ncrp_graph_census-mutate: {kinds} by kind; {moved_any} of "
          f"{len(want) - guards} input mutations moved rows; {len(zero)} moved NOTHING at "
          f"rc=0 (a coverage gap or a dead def); {len(zero_red)} moved nothing but still went "
          f"RED (caught by a check that does not read a row); {len(notrun)} did not compile; "
          f"{refused} refused on a non-unique pattern; "
          f"{guard_fail} of {guards} guard mutations went red")
    for z in zero:
        print(f"  MOVED NOTHING AT rc=0: {z}")
    for z in zero_red:
        print(f"  MOVED NOTHING, RED ANYWAY (no row saw it): {z}")
    for z in notrun:
        print(f"  DID NOT COMPILE: {z}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))