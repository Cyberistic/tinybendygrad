#!/usr/bin/env python3
r"""ops_python_census-gate.py -- A CENSUS over `tinybendygrad/runtime/ops_python.bend`,
the port of `tinygrad/runtime/ops_python.py`.

    .venv/bin/python gates/ops_python_census-gate.py
    .venv/bin/python gates/ops_python_census-gate.py --refresh   # rewrites the pins

85 ROWS (84 census rows + `py-done=1`), THREE LANES, **0 DECLARED DIVERGENCES**,
AND SIX FINDINGS. Every row is ANSWERED BY CPYTHON'S OWN PATH -- measured, and the
oracle is built so that it cannot be anything else.

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

THE PORT STAYS BYTE-IDENTICAL. Not one line of `tinybendygrad/runtime/ops_python.bend`
is edited by this unit; the census reads the lane the port already declares.

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
turns the gate red and says the finding closed.

  A. **EIGHT ROWS PRINT A CONSTANT.** `literal_rows()` re-derives them by parsing
     each row call's value expression: a bare `Nat`/`U32`, or a zero-argument call
     to a def whose body is itself a literal. The eight are `pywma_metal_dims0`,
     `pywma_metal_threads`, `pyc_is_b64decode`, `pyc_refused`, `pyd_ctor_len`,
     `pyd_ctor_allocator`, `pyd_ctor_renderers`, `pyd_ctor_runtime` and
     `pyd_nrenderers` minus the one derived by negation -- MEASURED by the check,
     not asserted in prose. All eight are RIGHT today (`tc.metal[0].dims[0]` is 8,
     its threads is 32, `compile` IS `base64.b64decode`, the ctor arity is 4 and
     the ctor tags are 0/1/2), and every one of them would still be right after tc.py
     changed a fragment width or ops_python.py reordered the ctor. This is class
     (d) -- `amd_dsl_census`'s `String.eq("vdst","vdst")` -- and the port's own
     comment concedes half of it: ops_python.bend:2705 says "all four things it
     passes are constants, so a row that read the fields would be reading the port's
     own tag numbering". The CONSTANTS are the finding; the census cannot see them
     move, and only a mutation can.

  B. **THE HEADER SAYS THERE ARE NO `pyc_*` ROWS, AND THERE ARE TWO.** Class (g),
     and the sharpest one in this layer: ops_python.bend:2374 reads "A row that
     disagrees with CPython is a row that encodes a bug, so there are NO `pyc_*`
     rows here at all", and :2660/:2661 print `pyc_is_b64decode` and `pyc_refused`.
     `pyc_rows_hold()` re-measures the two on every run. The sentence is the dead
     premise; the rows it disclaims are live and both agree with CPython.

  C. **`B64_EQ` IS DEAD.** ops_python.bend:2381 defines it and `grep -n B64_EQ` on
     that file answers exactly ONE line -- the definition. It is the `=` of a base64
     alphabet with no decoder left, WALL 5 having been abandoned mid-file. Same for
     `prog.init` (:2572), one line, no caller.

  D. **THE INTERPRETER HALF HAS NO ROWS IN THE POPULATION.** This is the honest
     limit and it is the report's "what this census cannot see". `ops_python.py`'s
     `PythonProgram.__call__` is :52-157 -- 106 of 186 lines, 57% of the upstream
     file -- and every dispatch arm of it (`Prog.dispatch`, ops_python.bend:2019) is
     reachable through `main()` only with a PACKET on the command line, which is the
     EXECUTOR lane and not a value lane. MEASURED: the population this gate compares
     is 85 rows and `grep -c -E '(srow|urow|row)\\(' tinybendygrad/runtime/ops_python.bend`
     over the five `t_*` bodies is 84, none of which is a `Prog.dispatch` row. The
     `t_*` groups cover `PythonRenderer.__init__`, `supported_dtypes`,
     `PythonCompiler.compile`, `wmma`'s lookup and two assertions, and
     `PythonDevice.__init__` -- the renderer/compiler/device half. Censusing the
     evaluator half needs fixtures the PORT must declare (the port may not be edited
     here), or a driver that hand-lists them, and a hand list is what
     `AGENTS.md`'s doctrine 1 forbids.

  E. **`Prog.dispatch` HAS NO `assert`-FOR AN UNREACHED ARM.** Class (f): CPython's
     :155 is `assert u in values, u`. The port's catch-all is `case _: Prog.alu(p, u)`
     (ops_python.bend:2042) with no guard, which would be a silent wrong answer --
     EXCEPT that `op_of` (:481) has no `BINARY`, `CALL`, `WMMA` or
     `CUSTOM_FUNCTION` arm, so those uops parse to `None`, `Uop.of.op2` marks them
     `kind >= 14`, `Uop.refused` (:1087) is true and `Prog.one.no` (:1149) sets
     `ok = False` before the arena is ever walked. MEASURED: `grep -c 'case "BINARY"\|case "CALL"\|case "WMMA"\|case "CUSTOM_FUNCTION"'`
     on the port answers 0. The refusal is STRUCTURAL and early rather than
     per-dispatch, which is stronger -- but it is checked by the parse and not by
     this census.

  F. **`Prog.dispatch`'s `OpsEND` ARM DOES NOT DECODE ops_python.py:70's `i =`.**
     :2025 is `case O.OpsEND{}: Prog.at(p, Uop.src1(u))` while CPython is
     `i = self.uop_to_index[u.src[1]]`, i.e. an INDEX LOOKUP. On a toposorted arena
     the two agree only because `prog.init` (:2572) documents the identity -- and
     `prog.init` is the def FINDING C says has no caller. So the arm's correctness
     rests on a comment, not on a live invariant. NOT REACHED by any row here.

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
    """FINDING A. MEASURED, not asserted in prose, and pinned as an EXACT SET so a
    fix turns this red and says the finding closed."""
    got = literal_rows()
    want = ["pyc_is_b64decode", "pyd_ctor_allocator", "pyd_ctor_len", "pyd_ctor_renderers",
            "pyd_ctor_runtime", "pyd_nrenderers", "pywma_metal_dims0", "pywma_metal_threads"]
    return report("literal_rows_hold",
                  [] if got == want else [f"the constant rows are {got}, expected {want}"])


def pyc_rows_hold() -> bool:
    """FINDING B, class (g): ops_python.bend:2374 says there are NO `pyc_*` rows and
    there are two. Re-measured here so the header's dead premise is a red run when
    it stops being dead, and so a reader does not have to grep for it."""
    src = PORT.read_text()
    header = src[:src.index("def B64_EQ")]
    claims_none = "`pyc_*` rows here at all" in header
    got = sorted(set(re.findall(r'row\("(pyc_[a-z0-9_]+)"', src)))
    bad = []
    if not claims_none:
        bad.append("the header no longer disclaims the pyc_* rows -- finding B is stale")
    if got != ["pyc_is_b64decode", "pyc_refused"]:
        bad.append(f"the pyc_* rows are {got}, expected ['pyc_is_b64decode', 'pyc_refused']")
    return report("pyc_rows_hold", bad)


def dead_defs_hold() -> bool:
    """FINDING C: `B64_EQ` and `prog.init` are each defined once and called zero
    times. `prog.init` is load-bearing in prose -- ops_python.bend:2568 says
    `uop_to_index` is the identity and that is WHY `Uop.at` may index by position --
    and nothing calls it."""
    src = PORT.read_text()
    bad = []
    for nm in ("B64_EQ", "prog.init"):
        hits = len(re.findall(rf"\b{re.escape(nm)}\b", src))
        if hits != 1:
            bad.append(f"{nm} has {hits} mentions, expected exactly 1 (its definition)")
    return report("dead_defs_hold", bad)


def interpreter_hold() -> bool:
    """FINDING E, class (f), checked structurally: `op_of` has NO arm for the ops
    CPython dispatches and this port does not (`BINARY`, `CALL`, `WMMA`,
    `CUSTOM_FUNCTION`), so those uops are refused at PARSE time and
    `Prog.dispatch`'s unguarded `case _: Prog.alu` cannot answer for them. This is
    what makes the catch-all safe; if an arm is ever added the check goes red and
    the dispatch has to learn to refuse."""
    src = PORT.read_text()
    body = re.search(r"^def op_of\(nm: String\).*?(?=^def |\Z)", src, re.M | re.S).group(0)
    bad = []
    for op in ("BINARY", "CALL", "WMMA", "CUSTOM_FUNCTION"):
        if f'case "{op}"' in body:
            bad.append(f'op_of now has a "{op}" arm, and Prog.dispatch has no case for it')
    if 'case _: Prog.alu(p, u)' not in src:
        bad.append("Prog.dispatch's catch-all is gone -- FINDING E is stale")
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