#!/usr/bin/env python3
r"""ops_python_census-gate.py -- A CENSUS over `tinybendygrad/runtime/ops_python.bend`,
the port of `tinygrad/runtime/ops_python.py`.

    .venv/bin/python gates/ops_python_census-gate.py
    .venv/bin/python gates/ops_python_census-gate.py --refresh   # rewrites the pins

85 ROWS (84 census rows + `py-done=1`), THREE LANES, **0 DECLARED DIVERGENCES**,
AND SIX FINDINGS OF WHICH **A, B, C AND F ARE CLOSED** AND D AND E ARE OPEN AND
REPORTED. Every row is ANSWERED BY CPYTHON'S OWN PATH -- measured, and the oracle
is built so that it cannot be anything else.

WHY NO EXISTING INSTRUMENT APPLIES, and why this one is (4) + (3).

`ops_python.py` is the CPU reference EVALUATOR. It takes a `UOp` and answers a
value; it builds no graph, so the eleven op-sequence censuses beside this one have
no graph to read. It answers no dtype/shape/tensor property, so `fold_graph_census`
has no property to read and this is not its value axis either. `cstyle_render_census`
diffs a rendered STRING and `amd_dsl_census` diffs a (word, bytes, text) TRIPLE,
because those are what their layers return; this layer returns a `Target` field, a
`list[TensorCore]`, a `set[DType]`, an `AssertionError` TEXT and a `bytes`. So the
printed form is designed from those five returns and from nothing else (below), and
the census is the (DRIVER, NODE) product `amd_dsl_census` established: the DRIVER
axis is the port's own fixture-lane groups, the NODE axis is the rows they print.

WHAT THE PORT ITSELF ALREADY HAD, AND WHAT WAS MISSING. `ops_python.bend` HAS a
`main()`, and it branches: with a PACKET on the command line it is the EXECUTOR
(`Prog.launch`), with none it runs a FIXTURE LANE (`gate()` at ops_python.bend:2719)
that prints 84 `name=value` rows across five groups. **The port is therefore its own
driver and this gate needs no `.bend` of its own** -- `./bin/bend
tinybendygrad/runtime/ops_python.bend` with an empty argv, which `main.at`
(:2734) routes to `gate()`. Before this file existed, `grep -rl ops_python gates/*.py`
answered NOTHING: 0 of the tree's gates named this layer, and 84 rows the port
computes were compared to nothing.

THE PORT IS ITS OWN DRIVER, and it is now EDITED by this unit too. The first
version of this census read the lane the port already declares and changed no
line of it; findings A, B and C were all properties of that lane, and closing
them MEANT editing `tinybendygrad/runtime/ops_python.bend` -- eight rows that
read nothing, a header that denied two of them existed, and two defs nothing
called. The 85 row NAMES are unchanged, and `names_hold()` still derives both
populations independently, so an edit that added or renamed a row would be a red
run rather than a quietly different census.

THE PRINTED FORM, AND WHY EACH FIELD IS THE THING THE LAYER RETURNS.

    key=<str>        a `Target` field: device, renderer, arch. The EMPTY string is a
                     real answer -- `PythonRenderer.__init__`'s `else` arm (:178)
                     leaves `device` alone -- so `pyr_empty_device=` is a row with
                     no value after the `=` and it is still a row.
    key=<int>        a COUNT, where the layer returns a `list`: `len(tensor_cores)`.
    key=<0..8>       a TABLE ID, on the eleven `*_tid` rows. NOT a count, and this
                     is the port's own argument (ops_python.bend:2617): MEASURED,
                     `amd_rdna3`, `amd_cdna3` and `amd_rdna4` all answer 4 cores, so
                     three of tc.py's eight tables are indistinguishable by length
                     and `pyr_gfx1100_ncores`, `pyr_gfx942_ncores`, `pyr_gfx1201_ncores`
                     and `pyr_gfx1101_ncores` are all `4`. The tid row is the fact
                     `get_amd`'s dict is actually about.
    key=True|False   a PREDICATE, or a refusal (`pyr_emulate_bad*`, the three
                     `pywma_lookup_*_miss` rows -- ops_python.py:35 is `next()` over
                     a generator, so a miss is StopIteration and the row says NOT
                     found).
    key=<text>       an `AssertionError` MESSAGE, verbatim from ops_python.py:37/:38.
    key=<0|1|2|4>    a POSITION in an argument list, read off CPython's own bytecode
                     (`PythonDevice.__init__`'s `super().__init__` call).

THE INPUT AXIS, which is the point of an interpreter census. Every row is
(def x input). The inputs are the axes CPython's own ladders are DEFINED over and
they are not the same values the port happened to pick: `arch` runs over METAL,
gfx942, gfx950, gfx1200, gfx1201, an unknown gfx (tc.py:98's dict DEFAULT), sm_74
(below the ladder's bottom), sm_75, sm_86, sm_88 (one below the sm_80 rung), sm_89,
sm_90, `""` and `NOT_AN_ARCH`; `dtype` over 8; `EMULATE` over 4; `TensorCore` over
tc.py's real fragments. The boundary values are the rows that matter: `sm_88` is
what separates `>= 89` from `>= 88` and `sm_74` is what separates `[]` from `sm_75`,
and the port's own comments say those two rows exist because a mutation had already
moved nothing without them.

`grep -c OpsCAST tinybendygrad/runtime/ops_python.bend` = **3**, and this is the
class (b) trap answered rather than dodged. The three are `op_of`'s parser arm
(:486), `opname`'s printer arm (:1340) and `Prog.dispatch`'s interpreter arm (:2038)
-- all three a NAME or a DISPATCH, and none of them a cast being minted. The
never-folding-CAST defect of `uop/ops.bend:2919` therefore has no surface in this
file: there is no `O.UOp.new(...)` in it at all, because this layer does not build
UOps. The 3 is a measurement, not an absence.

THE ORACLE CALLS THE REAL PATH, because for an interpreter the temptation to
reimplement is maximal and the failure is silent. `gates/ops_python_census-oracle.py`
imports `tinygrad.runtime.ops_python` and constructs `PythonRenderer`,
`PythonDevice`, `PythonCompiler` and real `TensorCore`s. Its two hardest rows do
not transcribe anything: `wmma`'s two assertion STRINGS are caught out of a real
`wmma(...)` call whose fragments come from `tc.metal[0]` and from the one shipped
core with 32 elements per A lane, and `PythonDevice.__init__`'s argument ORDER is
read off that function's disassembly. A reimplementation here would agree with
itself, which is the exact failure `tn_bitwise_not` recorded (seven rows).

`ops_python.py` HAS NOT DRIFTED SINCE THE PIN `ad117c928^`. MEASURED, all three the
same: `git rev-parse HEAD:tinygrad/runtime/ops_python.py`,
`git rev-parse ad117c928:...` and `git rev-parse 'ad117c928^:...'` are all
`02687a3d`, so HEAD is the oracle and `pin_drift_hold()` records that so a later
re-vendor turns this red instead of quietly changing the subject. `tc.py` -- which
29 of the 85 rows read through `PythonRenderer.__init__` -- is checked the same way
and is also un-drifted at `9ba914d2`.

THE SIX FINDINGS. None of them is a disagreement between the two lanes; each is a
property of the PORT, re-measured on every run by a check below, so a later fix
turns the gate red and says the finding closed. **A, B, C AND F ARE NOW CLOSED**
and their checks pin the CLOSED state; D and E are open and are reported, not
fixed. Every number in what follows was measured on 2026-10-13.

  A. **EIGHT ROWS PRINTED A CONSTANT. CLOSED.** `literal_rows()` re-derives the
     population by parsing each row call's value expression: a bare `Nat`/`U32`, or
     a zero-argument call to a def whose body is itself a literal. It answered EIGHT
     -- `pywma_metal_dims0`, `pywma_metal_threads`, `pyc_is_b64decode`,
     `pyd_ctor_len`, `pyd_ctor_allocator`, `pyd_ctor_renderers`, `pyd_ctor_runtime`,
     `pyd_nrenderers` -- and all eight were RIGHT while being unreadable: they would
     still be right after tc.py changed a fragment width or ops_python.py reordered
     the ctor. Class (d), `amd_dsl_census`'s `String.eq("vdst","vdst")`, and the port's
     own comment conceded half of it ("all four things it passes are constants, so a
     row that read the fields would be reading the port's own tag numbering"). Each
     now READS its input, and the input is declared ONCE and shared:
       * `Core.d0(METAL_CORE(0))` and `Core.threads(METAL_CORE(0))` -- one
         `METAL_CORE(din)` carries `tc.metal[0]`, so the two rows and the four
         `core_find` fixtures can no longer disagree about the same fragment.
       * `DEV_POS(DEV_ALLOCATOR())` and `List.length(..., DEV_ARGS())` -- one
         `DEV_ARGS()` list is ops_python.py:186's argument order, and the rows
         SEARCH it. The tags moved to 10/11/12/13 so that a tag can never be a
         position by accident, which is what let the old 0/1/2 pass for readings.
       * `compile.is_b64decode(compile.transform())` -- the two names are declared
         separately and compared. THIS IS THE WEAKEST OF THE EIGHT and the header in
         the port says so: the oracle CALLS `compile` on eight fixtures and compares
         bytes, the port compares declared transform names, because the quartet fold
         is WALL 5 and the port cannot run it. The port's row is the weaker fact and
         the gate says which one it is rather than letting green read as verified.
     `literal_rows()` answers `[]`, and that is what `literal_rows_hold()` now pins.

  B. **THE HEADER SAID THERE ARE NO `pyc_*` ROWS, AND THERE WERE TWO. CLOSED.**
     ops_python.bend:2374 read "A row that disagrees with CPython is a row that
     encodes a bug, so there are NO `pyc_*` rows here at all" while :2660/:2661
     printed `pyc_is_b64decode` and `pyc_refused` -- same file, 285 lines apart.
     The header now says there are two, says what each one is, and says which of the
     two sides of the identity it can establish. `pyc_rows_hold()` re-measures both
     halves: the disclaimer must stay GONE and the two rows must stay the two.

  C. **TWO DEAD DEFS. CLOSED, BY DELETION.** `B64_EQ` (ops_python.bend:2381) was the
     `=` of a base64 alphabet whose decoder was abandoned mid-file -- WALL 5 -- and
     `prog.init` (:2572) returned `Nil{}`: it built neither of the two maps its own
     comment described, and nothing called it. Each had EXACTLY ONE mention on the
     file, its own definition. Neither was wired: the decoder is not coming back
     inside this unit, and `prog.init` had no reader because the lookup it claimed to
     describe is resolved in the PARSER, not in a table. Both deleted, and the one
     place the loss of `prog.init` actually mattered is FINDING F.

  D. **THE INTERPRETER HALF HAS NO ROWS IN THE POPULATION. STILL OPEN, AND THIS IS
     THE HONEST LIMIT.** `ops_python.py`'s `PythonProgram.__call__` is :52-157 --
     106 of 186 lines, 57% of the upstream file -- and every dispatch arm of it
     (`Prog.dispatch`, ops_python.bend:2019) is reachable through `main()` only with
     a PACKET on the command line, which is the EXECUTOR lane and not a value lane.
     MEASURED: the population this gate compares is 85 rows and 84 of them come from
     the five `t_*` bodies, none of which is a `Prog.dispatch` row. The `t_*` groups
     cover `PythonRenderer.__init__`, `supported_dtypes`, `PythonCompiler.compile`,
     `wmma`'s lookup and two assertions, and `PythonDevice.__init__` -- the
     renderer/compiler/device half. NOT CLOSED, and the reason is a missing trusted
     INSTRUMENT rather than a missing fixture list: the CPython lane would have to
     turn a v1 packet into real `UOp` objects, and the only reader of that wire in
     the tree stops where the uops begin -- `ops_bend.parse` (ops_bend.py:169)
     "only recovers the shape BendProgram needs to marshal buffers, which is why it
     stops at op names and index lists". Writing a wire -> `UOp` decoder inside this
     oracle is the reimplementation this oracle exists to avoid, and a hand-listed
     fixture set is what `AGENTS.md`'s doctrine 1 forbids. Closing it needs a second
     census whose fixture population is a GENERATOR that runs (`ops_bend.encode` over
     a rendered uop list), not a list anyone typed.

  E. **`Prog.dispatch` HAS NO `assert`-FOR AN UNREACHED ARM. REPORTED, NOT FIXED,
     AND IT IS A STRONGER CLAIM THAN CPYTHON'S.** CPython's :155 is
     `assert u in values, u` -- a PER-DISPATCH check. The port's catch-all is
     `case _: Prog.alu(p, u)` (ops_python.bend:2042) with no guard, which would be a
     silent wrong answer -- except that `op_of` (:481) has no `BINARY`, `CALL`,
     `WMMA` or `CUSTOM_FUNCTION` arm, so those uops parse to `None`, `Uop.of.op2`
     leaves the op unparsed, `Uop.refused` (:1087) is `kind >= 14` and
     `Prog.one.no` (:1149) sets `ok = False`, all before the arena is ever walked.
     MEASURED: `grep -c 'case "BINARY"\|case "CALL"\|case "WMMA"\|case "CUSTOM_FUNCTION"'`
     on the port answers 0. A PARSE-TIME refusal of the whole program beats a
     per-dispatch assertion, so this is deliberately NOT "fixed" into a weaker
     shape; `interpreter_hold()` now re-measures all FOUR links of it (the four
     missing arms, the unguarded catch-all, the `kind >= 14` threshold, and
     `Prog.one.no`'s `ok = False`) so the claim cannot rot silently. It is still
     checked by the parse and by no row here.

  F. **`Prog.dispatch`'s `OpsEND` ARM: CHECKED, AND IT IS SOUND. THE DEAD DEF WAS
     NOT ITS EVIDENCE.** :2025 is `case O.OpsEND{}: Prog.at(p, Uop.src1(u))` while
     CPython's :70 is `i = self.uop_to_index[u.src[1]]` -- an INDEX LOOKUP. The
     finding was that the two agree only because `prog.init`, a def nothing called,
     said so. Deleting `prog.init` did NOT invalidate the arm; it removed a comment
     that was citing a stub. The real evidence is live code on BOTH sides:
     `ops_bend.encode` builds `idx = {u: i for i, u in enumerate(uops)}`
     (ops_bend.py:135) -- the SAME comprehension as ops_python:49 -- and writes
     `str(idx[s]+1)` (ops_bend.py:142), so the wire's `<src>` field IS
     `uop_to_index[src] + 1`, which `Uop.of.sr` subtracts ONE FROM, ONCE, FOR EVERY
     SRC. MEASURED on a real `encode` output: the wire field equals
     `uop_to_index[src]+1` for every src of every uop, and on the END line the
     port's pc (2 - 1) equals `uop_to_index[END.src[1]]` (1). So the port resolves
     the lookup at PARSE, for every arm, and the END arm is not a special case.
     Still NOT REACHED by any row in this census.

EXIT STATUS: 0 all three lanes identical after the pins and every check holds · 1 a
lane took the wrong row count, the oracle failed, the native compile failed, the
lanes disagree, a pin moved, a population or a finding check failed · 3 a
precondition was absent (the pins file, the output directory, the substrate, or the
oracle).
"""
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import (BEND, PY, WARM, TMP, NOTICE, REFUSED, PASS, FAIL, DEAD,  # noqa: F401
                     VERDICT)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PINS = HERE / "ops_python_census-pins.rows"
ART = HERE / "artifacts" / "ops_python_census-gate"
PORT = ROOT / "tinybendygrad" / "runtime" / "ops_python.bend"
ORACLE = HERE / "ops_python_census-oracle.py"

ROWS = 85
PIN = "ad117c928^"          # the pin AGENTS.md names for a drifted file

# THE VENDORED FILES THE ROWS READ, and the BLOB each one must keep. `ops_python.py`
# is the subject; `tc.py` is read by 29 of the 85 rows through
# `PythonRenderer.__init__`, which is :171 `tc.get_amd` / :173 `tc.get_cuda` /
# :170 `tc.metal`. A gate that pinned only its subject would let tc.py move and
# report the port's stale numbers as a verdict.
VENDORED = ("tinygrad/runtime/ops_python.py", "tinygrad/renderer/tc.py")

# THE DRIVER AXIS, re-derived from `gate()`'s own body on every run -- never a list
# here. The ORDER is part of the contract: the lanes are diffed line by line.
GROUP_DEF = r"^def (t_[a-z0-9]+)\(\) -> IO\(Unit\):"


def _lines(s):
    return [l for l in s.splitlines() if l.strip()]


def report(name, bad):
    for b in bad:
        print(f"  {name}: {b}", file=sys.stderr)
    if not bad:
        print(f"  {name}: OK")
    return not bad


# ===========================================================================
# THE POPULATION. Re-derived from BOTH sides on every run, never a list here.
# ===========================================================================
def port_groups():
    """The `t_*` groups `gate()` calls, IN ORDER, by `re.findall` over `main()`'s
    body -- the same rule `amd_dsl_census-gate.py:groups_hold` uses."""
    src = PORT.read_text()
    body = src[src.index("def gate() -> IO(Unit):"):]
    return tuple(re.findall(r"<-\s+(t_[a-z0-9]+)\(\)", body))


def port_rows():
    """The port's own printed row NAMES, in order, by `re.findall` over the whole
    file, plus the `py-done=1` completion marker `gate()` prints last."""
    names = re.findall(r'^\s+(?:srow|urow|row)\("([^"]+)"', PORT.read_text(), re.M)
    return names + ["py-done=1"]


def oracle_rows():
    """The ORACLE's row names, by RUNNING it. `names_hold()` is what stops an
    oracle from quietly covering whatever the port happens to do."""
    r = subprocess.run([str(PY), str(ORACLE)], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        return None, f"the oracle failed rc={r.returncode}: {r.stderr.strip()[:300]}"
    names = [l.split("=", 1)[0] for l in r.stdout.splitlines() if "=" in l]
    # the completion MARKER is a row NAME and a row NAME on the port side, so it
    # has to be one on this side too: `py-done`, not `py-done=1`. It is the last
    # row in both lanes because both print it last.
    if names and names[-1] == "py-done":
        names[-1] = "py-done=1"
    return names, ""


def groups_hold() -> bool:
    """The DRIVER axis is `gate()`'s calls, and the `t_*` defs must BE those calls:
    a group nothing calls is a population of zero rows that still looks like a gate,
    and a def nothing calls is dead code in the middle of a census."""
    src = PORT.read_text()
    called = port_groups()
    declared = tuple(re.findall(GROUP_DEF, src, re.M))
    bad = []
    if not called:
        bad.append("gate() calls no t_* group -- the driver axis is empty")
    if set(declared) != set(called):
        bad.append(f"t_* defs are {declared}, gate() calls {called}")
    if len(set(called)) != len(called):
        bad.append(f"gate() calls a group twice: {called}")
    for g in called:
        mm = re.search(rf"^def {g}\(\) -> IO\(Unit\):\n(.*?)(?=^def |\Z)", src, re.M | re.S)
        if not mm:
            bad.append(f"{g} is called but not declared")
        elif '("' not in mm.group(1):
            bad.append(f"{g} prints no rows")
    return report("groups_hold", bad)


def names_hold() -> bool:
    """THE TWO POPULATIONS ARE EQUAL AND IN THE SAME ORDER."""
    want = port_rows()
    got, why = oracle_rows()
    bad = []
    if got is None:
        bad.append(why)
    elif len(got) != len(want):
        bad.append(f"the oracle emits {len(got)} rows, the port's body declares {len(want)}")
    else:
        for i, (a, b) in enumerate(zip(want, got)):
            if a != b:
                bad.append(f"row {i}: port {a!r}, oracle {b!r}")
                if len(bad) > 4:
                    break
    if len(want) != ROWS:
        bad.append(f"the port's body declares {len(want)} rows, the header says {ROWS - 1} + 1")
    return report("names_hold", bad)


def pin_drift_hold() -> bool:
    """`ops_python.py` and `tc.py` have NOT drifted. All three blobs of each must
    stay equal and the pins file records the values, so a later re-vendor that moves
    one turns this red instead of quietly changing what the oracle is measured
    against."""
    def blob(rev, rel):
        r = subprocess.run(["git", "rev-parse", "--short=8", f"{rev}:{rel}"],
                           capture_output=True, text=True, cwd=str(ROOT))
        return r.stdout.strip() if r.returncode == 0 else f"rc={r.returncode}"
    bad, text = [], PINS.read_text() if PINS.is_file() else ""
    for rel in VENDORED:
        head, vend, pin = blob("HEAD", rel), blob("ad117c928", rel), blob(PIN, rel)
        if not head:
            bad.append(f"HEAD:{rel} did not resolve")
        elif not (head == vend == pin):
            bad.append(f"{rel} HAS DRIFTED: HEAD {head}, ad117c928 {vend}, {PIN} {pin} -- "
                       f"the PIN is the truthful oracle and this gate's rows were measured "
                       f"against HEAD")
        elif head not in text:
            bad.append(f"the pins file does not record {rel}'s HEAD blob {head}")
    return report("pin_drift_hold", bad)


def _oracle_module():
    """The oracle imported as a MODULE, so its own declared constants can be
    cross-checked against the port's rather than trusted. `amd_dsl_census-gate.py`
    does this in `fixtures_hold` for the same reason."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("_opspy_oracle", str(ORACLE))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def tid_axis_hold() -> bool:
    """THE tid TRANSLATION, PINNED ON BOTH SIDES.

    The eleven `*_tid` rows print the id of the TABLE an arch selected. CPython has
    no such id -- it has the `list[TensorCore]` the arch selected -- so the oracle
    answers by IDENTITY against `tc.py`'s own module-level tables. That is the only
    translation in the census, so it is checked three ways: the port's nine
    `CORES_*` constants are 0..8 and nothing else, the oracle's table names are the
    SAME nine names, and every one of those names resolves in `vars(tc)` to a
    non-empty `list[TensorCore]`. A rename in tc.py, a renumbering in the port, or a
    tenth table is a red run, not a quiet zero."""
    try:
        m = _oracle_module()
    except Exception as e:                                          # noqa: BLE001
        return report("tid_axis_hold", [f"the oracle would not import: {e}"])
    src = PORT.read_text()
    const = [(n, int(v)) for n, v in re.findall(r"^def CORES_(\w+)\(\) -> U32: (\d+)$", src, re.M)]
    bad = []
    if sorted(v for _, v in const) != list(range(len(const))):
        bad.append(f"the port's CORES_* values are {sorted(v for _, v in const)}, "
                   f"expected 0..{len(const) - 1}")
    want = {n.lower() for n, _ in const} - {"none"}
    got = set(m.TC_TABLES)
    if want != got:
        bad.append(f"the oracle's tc tables {sorted(got)} are not the port's "
                   f"CORES_* names {sorted(want)}")
    if len(set(m.TC_TABLES.values())) != len(m.TC_TABLES) or 0 in m.TC_TABLES.values():
        bad.append(f"the oracle's tid values {sorted(m.TC_TABLES.values())} are not a "
                   f"distinct set above the empty-list id 0")
    sys.path.insert(0, str(ROOT))
    from tinygrad.renderer import tc
    from tinygrad.renderer.tc import TensorCore
    for nm, v in m.TC_TABLES.items():
        table = getattr(tc, nm, None)
        if not isinstance(table, list) or not table:
            bad.append(f"tc.{nm} is not a non-empty list -- a table was renamed or emptied")
        elif not all(isinstance(c, TensorCore) for c in table):
            bad.append(f"tc.{nm} is not a list of TensorCore")
    # if the empty table does not answer the port's CORES_NONE id
    if getattr(m, "TC_TABLES", {}).get("cuda_sm75") == 6 and m.tid_of([]) != 0:
        bad.append("the empty table does not answer the port's CORES_NONE id")
    # and THE EXTENT of the tc.py dependency, re-derived so the header's number is
    # a reading and not a recollection: 29 rows read `renderer.tensor_cores`
    # through `PythonRenderer.__init__` (the `*_ncores` and `*_tid` families) and
    # 14 more read `tc.py` directly (the `pywma_*` family), 43 of 85 in all.
    rows = re.findall(r'^\s+(?:srow|urow|row)\("([^"]+)"', src, re.M)
    via_init = [r for r in rows if r.endswith(("_ncores", "_tid"))]
    direct = [r for r in rows if r.startswith("pywma_")]
    if (len(via_init), len(direct)) != (29, 14):
        bad.append(f"tc.py is reached by {len(via_init)} rows through "
                   f"`PythonRenderer.__init__` and {len(direct)} directly, expected 29 "
                   f"and 14 -- the census's extent over tc.py changed")
    return report("tid_axis_hold", bad)


def ctor_axis_hold() -> bool:
    """THE ctor ORDER, read off CPython's bytecode, matched against
    `Compiled.__init__`'s SIGNATURE.

    `pyd_ctor_*` are positions, and a position is only a fact about `ops_python.py`
    if it is a position in the parameter list CPython actually has. So the oracle's
    `CTOR_PARAMS` (from `inspect.signature`) must be `allocator, renderers, runtime`
    in that order and `CTOR_NAMES[1:]` must name an object for each. A renamed
    parameter or a reordered ctor is a red run."""
    try:
        m = _oracle_module()
    except Exception as e:                                          # noqa: BLE001
        return report("ctor_axis_hold", [f"the oracle would not import: {e}"])
    bad = []
    if m.CTOR_PARAMS != ["allocator", "renderers", "runtime"]:
        bad.append(f"Compiled.__init__ takes {m.CTOR_PARAMS} after device, the census "
                   f"assumes ['allocator', 'renderers', 'runtime']")
    if m.CTOR_NAMES[:1] != ["device"]:
        bad.append(f"the ctor's first argument is {m.CTOR_NAMES[:1]}, expected ['device']")
    for nm, obj in m.CTOR_OBJECTS.items():
        if nm not in m.CTOR_PARAMS or obj not in m.CTOR_NAMES[1:]:
            bad.append(f"{nm}={obj} is not an argument of the ctor the oracle read")
    if sorted(m.CTOR_TAG.values()) != list(range(len(m.CTOR_TAG))):
        bad.append(f"the ctor tags {m.CTOR_TAG} are not a 0..n-1 enumeration")
    return report("ctor_axis_hold", bad)


# ---- FINDING A: the rows whose value is a CONSTANT, not a reading ------------
ROW_CALL = re.compile(r'^\s+(?:srow|urow|row)\("([^"]+)",\s*(.+?)\)\s*$', re.M)
CONST_CALL = re.compile(r'^(?:[\w]+\.)?([A-Za-z_]\w*)\(\)$')
CONST_VAL = re.compile(r"^[\s:]*(\d+n?|True\{\}|False\{\}|[A-Z][A-Z_0-9]*\(\))$")


def literal_rows():
    """THE EIGHT CONSTANT ROWS, DISCOVERED.

    A row reads its input when its value expression is a CALL WITH ARGUMENTS, or a
    field read off a value that came from one. A row that cannot is one of these
    two shapes: a bare `Nat`/`U32` literal, or a zero-argument call to a def whose
    own body is a literal. Both are re-derived here by parsing the port, and the
    set is asserted below, so a new constant row is a red run."""
    src = PORT.read_text()
    out = []
    for name, expr in ROW_CALL.findall(src):
        if re.fullmatch(r"\d+n?", expr.strip()):
            out.append(name)
            continue
        m = CONST_CALL.match(expr.strip())
        if not m:
            continue
        body = re.search(rf"^def (?:[\w]+\.)?{re.escape(m.group(1))}\([^)]*\)[^:]*:\s*(.+)$",
                         src, re.M)
        if body and CONST_VAL.match(body.group(1)):
            out.append(name)
    return sorted(out)


def literal_rows_hold() -> bool:
    """FINDING A, CLOSED. The same derivation, re-run on every run, now pinned as
    the EMPTY SET: not one row's value is a bare literal or a zero-argument call
    to a literal, so every row reads a declared input. What each of the eight now
    reads is recorded where it is declared -- `Core.d0(METAL_CORE(0))` /
    `Core.threads(METAL_CORE(0))` for tc.py's `tc.metal[0]` fragment,
    `DEV_POS(...)` and `List.length(..., DEV_ARGS())` for ops_python.py:186's ctor
    argument order, and `compile.is_b64decode(compile.transform())` for the
    transform `compile` applies. The set is re-derived, never listed here, so a
    NINTH constant row is a red run and so is a re-regression of any of the eight.
    """
    got = literal_rows()
    return report("literal_rows_hold",
                  [] if got == [] else [f"{len(got)} row(s) print a constant again: {got}"])


def pyc_rows_hold() -> bool:
    """FINDING B, class (g), CLOSED. ops_python.bend's header used to say there
    were NO `pyc_*` rows while :2660/:2661 printed two; it now says there are two
    and what each one is. Both halves are re-measured here: the disclaimer must be
    GONE (its return is a stale finding, not a new one) and the two rows must still
    be the two that are printed."""
    src = PORT.read_text()
    got = sorted(set(re.findall(r'row\("(pyc_[a-z0-9_]+)"', src)))
    bad = []
    if "`pyc_*` rows here at all" in src:
        bad.append("the header disclaims the pyc_* rows AGAIN -- finding B is back")
    if got != ["pyc_is_b64decode", "pyc_refused"]:
        bad.append(f"the pyc_* rows are {got}, expected ['pyc_is_b64decode', 'pyc_refused']")
    return report("pyc_rows_hold", bad)


def dead_defs_hold() -> bool:
    """FINDING C, CLOSED, and the check is the SHAPE rather than a pair of names:
    every `def` in the port that nothing else in the file mentions would show up
    as exactly one mention of its own identifier. `B64_EQ` (residue of the
    abandoned base64 decoder) and `prog.init` (a stub returning `Nil{}`, load-bearing
    in PROSE for `Prog.dispatch`'s END arm and called by nothing) each had one, and
    each was DELETED rather than wired: neither had a reader, and the END arm's
    evidence now lives in `Uop.of.sr`, where the lookup is actually resolved and
    beside the ENCODER's own `idx = {u: i for i, u in enumerate(uops)}`.
    Six other single-mention defs predate this gate and are NOT touched by it --
    `is_hspace`, `word_at`, `str_of`, `hex_str2`, `elemname`, `Uop.src0` -- so the
    check stays pinned on the two this finding named, at ZERO, and a re-add is red.
    """
    src = PORT.read_text()
    bad = []
    for nm in ("B64_EQ", "prog.init"):
        hits = len(re.findall(rf"\b{re.escape(nm)}\b", src))
        if hits != 0:
            bad.append(f"{nm} has {hits} mentions, expected 0 -- finding C is back")
    return report("dead_defs_hold", bad)


def interpreter_hold() -> bool:
    """FINDING E, class (f), checked structurally, and STRONGER than CPython's.
    CPython's :155 is `assert u in values, u` -- a PER-DISPATCH check. The port's
    catch-all `case _: Prog.alu(p, u)` (ops_python.bend:2042) is unguarded, which
    would be a silent wrong answer, EXCEPT that the refusal happens earlier and
    everywhere at once: `op_of` has no `BINARY`, `CALL`, `WMMA` or `CUSTOM_FUNCTION`
    arm, so those uops parse to `None`; `Uop.of.op2` leaves the op unparsed;
    `Uop.refused` is `kind >= 14`; and `Prog.one.no` clears `ok` -- all before the
    arena is ever walked. A parse-time refusal of the whole program beats a
    per-dispatch assertion, so this is not a weakening and must not be "fixed" into
    one. All FOUR links are re-measured here: if an arm is ever added to `op_of`, or
    the threshold moves, or `Prog.one.no` stops clearing `ok`, the dispatch has to
    learn to refuse and this goes red."""
    src = PORT.read_text()
    body = re.search(r"^def op_of\(nm: String\).*?(?=^def |\Z)", src, re.M | re.S).group(0)
    bad = []
    for op in ("BINARY", "CALL", "WMMA", "CUSTOM_FUNCTION"):
        if f'case "{op}"' in body:
            bad.append(f'op_of now has a "{op}" arm, and Prog.dispatch has no case for it')
    if 'case _: Prog.alu(p, u)' not in src:
        bad.append("Prog.dispatch's catch-all is gone -- FINDING E is stale")
    if "def Uop.refused(+u: Uop) -> Bool: U32.is_ge(Uop.kind(u), 14)" not in src:
        bad.append("Uop.refused is no longer `kind >= 14` -- the parse-time refusal "
                   "the catch-all's safety rests on has moved or is gone")
    # and the refusal must LAND: `Prog.one.no` is the arm an unparsed line takes,
    # and its whole body is `ok = False`.
    if not re.search(r"^def Prog\.one\.no\(\+b: Build\) -> Build:\n"
                     r"  Build\{[^\n]*False\{\}\}\s*$", src, re.M):
        bad.append("Prog.one.no no longer ends the Build with ok=False -- an unparsed "
                   "uop would no longer refuse the program")
    return report("interpreter_hold", bad)


# ===========================================================================
# THE DIVERGENCE POPULATION -- declared in a file beside the gate, PINNED on both
# sides, written by `--refresh` and by nothing else.
# ===========================================================================
def _pins():
    """`(DIVERGES, why)` -- the pins LOADED BY PATH. A MISSING file is a REFUSED
    precondition and an EMPTY one is a verdict; `pin_lines()` and
    `divergences_hold()` tell them apart."""
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must "
                      f"live in git, beside the gate. Run --refresh.")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 3:
            return None, f"{PINS.name}: a line is not row<TAB>oracle<TAB>port: {ln!r}"
        row, py_v, port_v = parts
        pins[row] = (f"{row}={py_v}", f"{row}={port_v}")
    return pins, ""


def pin_lines():
    """How many pins LINES the file carries -- which is NOT `len(DIVERGES)`."""
    if not PINS.is_file():
        return 0
    return sum(1 for ln in PINS.read_text().splitlines()
               if ln.strip() and not ln.startswith("#"))


DIVERGES, WHY = _pins()


def divergences_hold() -> bool:
    """Every pinned row really is a divergence, and the count is the measured one.
    Without this a pin list could grow to cover the whole census."""
    if DIVERGES is None:
        return report("divergences_hold", [WHY])
    want, _ = oracle_rows()
    bad = []
    if len(DIVERGES) != 0:
        bad.append(f"{len(DIVERGES)} pinned divergences, expected 0 -- if the census "
                   f"has grown one, give it a CLASS and a reason before pinning it")
    if pin_lines() != len(DIVERGES):
        bad.append(f"{pin_lines()} pins lines against {len(DIVERGES)} names")
    for row in DIVERGES:
        if want is not None and not any(l.split("=", 1)[0] == row for l in want):
            bad.append(f"pinned row {row!r} is not in the oracle's population")
    return report("divergences_hold", bad)


def checks_hold() -> bool:
    ok = True
    for fn in (groups_hold, names_hold, pin_drift_hold, tid_axis_hold, ctor_axis_hold,
               literal_rows_hold, pyc_rows_hold, dead_defs_hold, interpreter_hold,
               divergences_hold):
        ok = fn() and ok
    return ok


# ===========================================================================
# --refresh : rewrite the pins from a fresh pair of lanes. Its ONLY writer.
# ===========================================================================
# A divergence needs a CLASS before it can be pinned, or the pins file grows a
# difference nobody has explained. There is one class today, held empty, and
# `divergences_hold()` refuses any pin that does not land in one of these.
CLASSES = [
    # (class name, row-name pattern, why the two sides differ)
    ("UNEXPLAINED", r"^.*$",
     "NO CLASS. A row that differs here and does not match a declared pattern is a "
     "real divergence with no reason attached; `--refresh` refuses to pin it rather "
     "than record a difference nobody has looked at."),
]


def refresh() -> int:
    """REWRITE the pins from a fresh pair of lanes. Its ONLY writer.

    It does not go through `run()`, because a refresh is exactly what a run cannot
    do when the pins are wrong."""
    lanes = {}
    for tag, argv in (("py", [str(PY), str(ORACLE)]), ("bd", [str(BEND), str(PORT)])):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode != 0:
            print(f"--refresh: lane {tag} failed rc={r.returncode}: "
                  f"{(r.stderr or '').strip()[:200]}", file=sys.stderr)
            return 1
        lanes[tag] = [l for l in r.stdout.splitlines() if "=" in l]
    if len(lanes["py"]) != ROWS or len(lanes["bd"]) != ROWS:
        print(f"--refresh: row counts py={len(lanes['py'])} bd={len(lanes['bd'])}, "
              f"expected {ROWS}", file=sys.stderr)
        return 1
    by = {t: dict((l.split("=", 1)[0], l) for l in v) for t, v in lanes.items()}
    rows = []
    for l in lanes["py"]:
        name = l.split("=", 1)[0]
        if by["py"][name] == by["bd"].get(name):
            continue
        cls = next((c for c, pat, _ in CLASSES if c != "UNEXPLAINED" and re.search(pat, name)), None)
        if cls is None:
            print(f"--refresh: no class for {name!r} -- declare one before refreshing, "
                  f"or a new divergence is pinned with no reason", file=sys.stderr)
            return 1
        rows.append((cls, name, l.split("=", 1)[1], by["bd"][name].split("=", 1)[1]))
    out = [_header(len(rows)), ""]
    last = None
    for cls, name, pv, bv in rows:
        if cls != last:
            why = next(w for c, _, w in CLASSES if c == cls)
            out.append(f"# {cls} -- {sum(1 for r in rows if r[0] == cls)} rows. {why}")
            last = cls
        out.append(f"{name}\t{pv}\t{bv}")
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, "
          f"{ROWS - len(rows)} exact matches")
    return 0


def pins_blob(rel):
    r = subprocess.run(["git", "rev-parse", "--short=8", f"HEAD:{rel}"],
                       capture_output=True, text=True, cwd=str(ROOT))
    return r.stdout.strip() if r.returncode == 0 else "unknown"


def _header(n):
    return "\n".join(
        ["# ops_python_census-pins.rows -- GENERATED by",
         "# `ops_python_census-gate.py --refresh`, which is its ONLY writer. One TAB-",
         "# separated TRIPLE per line: the row NAME, the ORACLE's value, the PORT's.",
         "# Loaded by path by the gate and committed BESIDE it, because a gate's",
         "# declared divergences must live in git -- not in `gates/artifacts/`",
         "# (`.gitignore`d, and where one `rm -rf` takes them) and not in the",
         "# environment of whoever ran it last.",
         f"#",
         f"# {n} DIVERGENCES of {ROWS} ROWS. Each block is a CLASS, and each",
         "# class says WHY the two sides differ. A pin without a reason is a",
         "# weakened instrument; a divergence without a pin is a silent one.",
         "#",
         "# NO CLASS BLOCK APPEARS BECAUSE THERE IS NOTHING TO CLASSIFY: every row the",
         "# port's fixture lane prints is ANSWERED BY CPYTHON'S OWN PATH, and all 85",
         "# agree byte-for-byte. The file is still LOADED BY PATH and its emptiness is",
         "# still asserted by `divergences_hold()`, because \"zero declared",
         "# divergences\" is a claim that has to stay re-decidable: the first real",
         "# disagreement is refused by `--refresh` until a CLASS and a reason are",
         "# declared for it, which is the right order for a new divergence to meet.",
         "#",
         "# A ZERO-LENGTH FILE IS NOT A MISSING ONE. `_pins()` answers REFUSED for a",
         "# missing file and an empty one for an empty file, and only the second is a",
         "# verdict.",
         "#",
         f"# {VENDORED[0]} blob at HEAD / `ad117c928` / the pin `{PIN}`: "
         f"{pins_blob(VENDORED[0])}. The subject.",
         f"# {VENDORED[1]} blob, same three: {pins_blob(VENDORED[1])}. Read by 29 of the",
         f"# {ROWS} rows through `PythonRenderer.__init__` -- ops_python.py:170",
         f"# `tc.metal`, :173 `tc.get_cuda`, :171 `tc.get_amd` -- and by 14 more",
         f"# directly (the `pywma_*` family), 43 of {ROWS} in all, so a gate that pinned",
         "# only its subject would let it move and report the port's stale numbers as a",
         "# verdict. `pin_drift_hold()` re-measures all six on every run."])


if "--refresh" in sys.argv:
    sys.exit(refresh())

if not PINS.is_file():
    print(f"{PINS} is MISSING. A gate's declared divergences must live in git, "
          f"beside the gate:\n    .venv/bin/python {Path(__file__).name} --refresh",
          file=sys.stderr)
    sys.exit(REFUSED)


# WHY THIS GATE RUNS ITS OWN THREE LANES rather than `gatekit.Gate.run()`.
#
# `Gate` requires a `rows` count and a `compared` count as arguments, which for this
# census are the SAME number unless a divergence appears -- and the divergence
# population is a file whose size is not known until it is loaded. It also cannot
# carry "zero divergences is a claim that must be re-decidable", because
# `Gate.diverges` defaults to `{}` and an absent dict is indistinguishable from an
# empty one. Both are one-line problems with one-line answers and both were taken
# here instead: `_pins()` distinguishes MISSING from EMPTY, and `compared` is
# `ROWS - pin_lines()`. The PLUMBING -- BEND, PY, WARM, the `.tmp.` staging
# convention and promote-or-discard -- is gatekit's and `gatekit.py` is not edited.


def _staged(n):
    return ART / f"{TMP}{n}"


def lane(argv, name, rows=ROWS):
    """One lane, retried while it emits the wrong ROW COUNT -- `bend`'s machine
    stack overflows on roughly 1 run in 20 and prints nothing at all, which is
    indistinguishable from 'did not start'. A named failure says which STEP."""
    out = _staged(name)
    for _ in range(25):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode == 0 and len(_lines(r.stdout)) == rows:
            out.write_text(r.stdout)
            return True
        said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()
                          if l.strip() and not NOTICE.match(l.strip()))
        if said:
            break
    print(f"  lane {name} did not produce {rows} rows"
          + (f" -- {said}" if said else " in 25 tries (the flake)"), file=sys.stderr)
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
    print("  the substrate did not warm: `bend --check-only` never printed "
          f"{WARM!r}", file=sys.stderr)
    return False


def run():
    """PRODUCE THREE LANES, COMPARE THEM, AND SETTLE ON EVERY EXIT.

    `bd` is `./bin/bend tinybendygrad/runtime/ops_python.bend` with an EMPTY argv,
    which `main.at` (ops_python.bend:2734) routes to the fixture lane `gate()`; `bn`
    is the same program compiled with `-o` and run as a binary. Staging is
    gatekit's `.tmp.` convention and the promote-or-discard is its `_settle`, so a
    red run leaves neither a half-written artifact nor a temp.
    """
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

        lanes = {t: _lines(_staged(t).read_text()) for t in ("py.rows", "bd.out", "bn.out")}
        n0 = {t: len(v) for t, v in lanes.items()}
        if any(n != ROWS for n in n0.values()):
            print("  " + ", ".join(f"{t} has {n}" for t, n in n0.items())
                  + f", expected {ROWS}", file=sys.stderr)
            return DEAD if 0 in n0.values() else FAIL

        trip = [l.split("\t") for l in PINS.read_text().splitlines()
                if l.strip() and not l.startswith("#")]
        pinned = {row for row, _, _ in trip}
        want = {row: sum(1 for r, _, _ in trip if r == row) for row, _, _ in trip}
        kept = {t: [l for l in v if l.split("=", 1)[0] not in pinned] for t, v in lanes.items()}
        n = {t: len(v) for t, v in kept.items()}
        if len(set(n.values())) != 1 or n["py.rows"] != ROWS - sum(want.values()):
            print("  " + ", ".join(f"{t} kept {v}" for t, v in n.items())
                  + f", expected {ROWS - sum(want.values())} everywhere -- the exclusion "
                    f"list is stale", file=sys.stderr)
            return FAIL
        for tag in ("bd.out", "bn.out"):
            if kept[tag] != kept["py.rows"]:
                d = [(x, y) for x, y in zip(kept["py.rows"], kept[tag]) if x != y][:2]
                print(f"  DISAGREE ({tag}): {d}", file=sys.stderr)
                return FAIL
        # AND EVERY PIN IS STILL CHECKED, BY OCCURRENCE -- the exclusion removes a
        # row from the diff; it does not excuse it.
        for row, pv, bv in trip:
            for tag, text in (("py.rows", f"{row}={pv}"),
                              ("bd.out", f"{row}={bv}"), ("bn.out", f"{row}={bv}")):
                got = sum(1 for l in lanes[tag] if l == text)
                if got != want[row]:
                    print(f"  {tag}: {text!r} appears {got} times, the pins say "
                          f"{want[row]} -- a pin moved, or a duplicated row name was "
                          f"lost", file=sys.stderr)
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


SUMMARY = (f"ops_python_census: PASS -- {ROWS} rows x 3 lanes, "
           f"{ROWS - pin_lines()} exact, {pin_lines()} pinned; the port's own "
           f"fixture lane is the driver and it is byte-identical to CPython")


def main():
    code = run()
    if code == 0 and not checks_hold():
        code = 1
    print(SUMMARY if code == 0 else f"ops_python_census-gate: {VERDICT[code]}")
    return code


if __name__ == "__main__":
    sys.exit(main())