#!/usr/bin/env python3
"""Mutation harness for `realize_graph_census-gate.py`, which HAD NONE.

    .venv/bin/python gates/realize_graph_census-mutate.py           # all four kinds
    .venv/bin/python gates/realize_graph_census-mutate.py --phase 2 # guards only, no bend

A mutation reading answers ONE question: does this gate say anything about its own claims, or
only about the absence of a mutation? A mutation that moves nothing is a DELIVERABLE -- a
COVERAGE GAP (the row exists, nothing reads the field) or a DEAD DEF (nothing calls it) --
and the report says which, by name.

THE FOUR KINDS ARE REPORTED APART BECAUSE THEY FAIL DIFFERENTLY:

  VALUE       one row's ANSWER moves. Catches a port regression on a row that exists.
  POPULATION  the ROW SET moves: a node vanishes, a driver name duplicates, a pin is dropped.
              THIS IS THE KIND THAT FINDS INSTRUMENT BLINDNESS.
  AXIS        the FIXTURE AXES drift. A fixture axis can drift with EVERY ROW STILL MATCHING,
              which no value comparison can see.
  GUARD       one of the gate's own TEN checks is driven with a world it must reject. The
              gate file is NEVER EDITED: each guard is exercised by corrupting what it
              watches (a source file it re-derives, or the lane rows it reads), which is
              stronger evidence than editing the check -- it shows the check REJECTS a world,
              not that the check's text changed.
  VACUOUS     **A FIFTH KIND, AND IT IS THE ONE THAT EXCUSES NOTHING BY ITSELF.** A mutation
              that cannot move any row because no row reaches the branch it edits is not a
              coverage gap -- it is a declared blindness -- and from the outside the two
              read IDENTICALLY: green at rc=0, zero rows moved. `V2` sat in the unclassified
              bucket for a session and the reason turned out to be the PRINTER, so an
              unlabelled green is a place a finding goes to die. An entry that declares
              itself `VACUOUS` is printed as such, with its reason, and counted APART from
              the ones that were not found.

TWO PHASES, AND WHY. PHASE 1 mutates a source, runs the two lanes BY HAND, counts the rows
that moved, and then runs the real gate. PHASE 2 runs no `bend` at all: it drives each guard
on INJECTED rows, because `gatekit.gate()` short-circuits -- `g.run()` must PASS before
`checks` is ever called -- so a guard whose subject is also what `run()` compares can never
be shown to speak through an end-to-end run. Both phases call the gate's OWN defs; neither
edits the gate.

THE TWO COPIES LIVE BESIDE THE ORIGINALS AND THE TREE'S OWN FILES ARE NEVER WRITTEN. Three
measured reasons, and the third is this harness's own bug caught before it ran:
  * `realize.bend` imports `./../helpers.bend` RELATIVE TO ITS OWN PATH, so a copy anywhere
    else cannot resolve them and answers "the substrate did not warm" -- a REFUSED exit for
    the wrong reason, and a harness that reports "the mutation was found" because the file
    could not be compiled has learned nothing. The PORT copy is therefore
    `tinybendygrad/engine/realize-mut.bend` (NO leading dot: a dot-prefixed import target is
    refused, `Error: - expected : an import path of plain names`, MEASURED in
    `cstyle_render_census-mutate.py:51-55`) and the DRIVER copy is `gates/realize-mut-driver.bend`,
    because the driver reaches the port by that same relative import and must live in `gates/`.
  * `kern_blind_holds()` re-derives its two claims by reading `(HERE / "realize_graph_census.bend")`
    and `(HERE / "realize_graph_census-oracle.py")` AS TEXT, and `drivers_hold()` reads
    `PORT.read_text()`. A harness that ran the staged copies without pointing `m.HERE` and
    `m.PORT` at them would have driven both guards against the UNMUTATED sources and reported
    them as silent. So `m.HERE` is redirected at a staging DIRECTORY holding the three
    mutated files under their real names, and `m.PORT` at the port copy.
  * `gatekit.ART` is the MODULE-level global `Gate.__init__` builds its output directory
    from, and `Gate.__init__` EMPTIES that directory before any check can fail. Left alone,
    every one of these runs would clear `gates/artifacts/realize_graph_census-gate/`, which
    is another agent's lane to read. `gatekit.ART` is therefore repointed BEFORE the gate
    module is executed -- and it has to be, because `Gate(...)` is constructed at the gate
    module's own import time, two dozen lines above any `if __name__` this harness could
    reach. Repointing the attribute and then importing the gate is the only ordering that
    works, and getting it backwards clears the real directory.

NO FIXTURE IN HERE ALLOCATES PER ROW. `decomp_value`'s fixture generator minted
`bytes(4390684688)` per launch and filled a 926 GiB volume. Nothing below builds a list whose
size is a row count; the only allocation sized by the population is the lane row dict
the harness reads back from a captured lane, and it is built ONCE per phase.

THE EXPECTED LANE WIDTH IS `declared_rows()` -- THE GATE'S OWN `ROWS[0]`, READ BY PATH --
and not a number written here. It was `974` in this file until the census grew to 1004
rows, and a literal like that is `checks/sweep.py`'s `LIVE_UNITS`: it agrees with itself
for as long as nobody notices and then refuses a correct run.

MEMORY. One `bend` process at a time, never two, because AGENTS.md's precondition is the SUM
of the concurrently running files' peak RSS and `.agents/slop/peakrss/census.rows` reads
`realize.bend` at 559 MB -- a driver that reaches it is larger, and the gate's own measured
peak is 1.37 GiB (see `--mem`). The harness reports its own steady-state RSS and the elapsed
time for the whole run, because a harness that reports neither cannot be compared with the
`bytes(4.3e9)` incident.
"""
import importlib.util
import json
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"

GATE = HERE / "realize_graph_census-gate.py"
ORACLE = HERE / "realize_graph_census-oracle.py"
DRIVER = HERE / "realize_graph_census.bend"
PORT = ROOT / "tinybendygrad" / "engine" / "realize.bend"
PINS = HERE / "realize_graph_census-pins.rows"

# THE STAGING NAMES. `realize-mut.bend` BESIDE the port (no dot -- see the header), the
# driver copy in `gates/` because its relative imports resolve from there, and a staging
# DIRECTORY under `gates/` holding the three files under their REAL names so that `m.HERE`
# can be pointed at it and every `HERE / "<name>"` read inside the gate finds a mutant.
MUT_PORT = ROOT / "tinybendygrad" / "engine" / "realize-mut.bend"
MUT_DRIVER = HERE / "realize-mut-driver.bend"
MUT_ORACLE = HERE / "realize-mut-oracle.py"
STAGE = HERE / ".realize-mut-stage"
MUT_ART = ROOT / "gates" / "artifacts" / "realize-mut"
RUN = HERE / ".realize-mut-run.py"
GUARDS = HERE / ".realize-mut-guards.py"
CFG = HERE / ".realize-mut-cfg.json"
LANES = MUT_ART / "lanes"

DRIVER_IMPORT = "import ./../tinybendygrad/engine/realize.bend as RZ"
DRIVER_MUT_IMPORT = "import ./../tinybendygrad/engine/realize-mut.bend as RZ"

# THE TEN CHECKS `gate()` chains, IN ITS OWN ORDER. `and` SHORT-CIRCUITS, so an
# end-to-end run only ever hears the FIRST failure; PHASE 2 calls each on its own, which is
# the entire reason it exists. `arms_all_reached` is named in the gate's own prose and in
# `no_bottom_value`'s docstring and IS NOT A DEF (MEASURED, `grep -c 'def arms_all_reached'`
# is 0): it is the `arm_* == 0` loop folded into `no_bottom_value`. `rows_hold` and
# `pin_lines()` are named in the BRIEF and ARE NOT IN THE FILE at all (both 0) -- the row
# count is `gatekit.Gate._lane`'s and the pin count is `_pins()`'s.
#
# **`RUN_TAIL`'S CHAIN WAS EIGHT OF THE GATE'S NINE** -- `axis_hold` was missing from it, so
# phase 1's end-to-end run never heard the driver-axis guard while phase 2 drove it happily,
# and the two halves of this harness disagreed about what the gate checks. `RUN_TAIL` now
# spells the gate's own chain, and `argkinds_hold` (added with the `arg` payload) is in both.
CHECKS = ("classes_hold", "no_bottom_value", "drivers_hold", "axis_hold", "calls_hold",
          "pin_drift_holds", "compares_holds", "kern_blind_holds", "argkinds_hold",
          "ret_is_uop_fixed_holds")

# THE TWO GENERATED RUNNERS. Both repoint `gatekit.ART` BEFORE the gate module is executed
# (see the header's third reason), both re-derive `DIVERGES` from the staged pins because it
# is read at the gate module's IMPORT time, and both leave the tree they were given.
PREAMBLE = """\
import contextlib, importlib.util, io, json, sys
from pathlib import Path
GATES, MUT_ART = Path({gates!r}), Path({art!r})
sys.path.insert(0, str(GATES))
import gatekit
gatekit.ART = MUT_ART                      # BEFORE the import: Gate(...) clears its own dir
cfg = json.loads(Path({cfg!r}).read_text())
spec = importlib.util.spec_from_file_location("rgz", GATES / "realize_graph_census-gate.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.HERE, m.PORT = Path(cfg["here"]), Path(cfg["port"])
# `PINS` IS A MODULE CONSTANT, NOT `HERE`-RELATIVE, and that is the FOURTH of this
# harness's own wiring bugs. `_pins()` reads `PINS.is_file()` and `PINS.read_text()`, so
# repointing `m.HERE` at the staging directory -- which DOES redirect
# `kern_blind_holds`'s driver and oracle reads and `_load_oracle`'s -- does NOT redirect
# the pins file, and the pin-COUNT assertion read the unmutated file and stayed green.
# MEASURED: G30 ("the pins file gains a row no class declares") reported SILENT, and the
# reason is that no row had been added to the file it was reading. The fix is one line and
# the class of bug is the tree's own: a constant captured at import cannot see a later
# rebinding of the thing it was derived from.
m.PINS = Path(cfg["pins"])
# `ART` IS THE GATE-NAMED DIRECTORY, not the artifacts ROOT: the gate's own line reads
# `ART = HERE / "artifacts" / "realize_graph_census-gate"` and `_lane` looks for
# `ART / "bd.out"`, so pointing `m.ART` at the ROOT makes every check answer "the promoted
# lanes are not there" while `m.GATE.dir` (set from `gatekit.ART / name`) is correct. Two
# constants, one meaning -- MEASURED, not reasoned: the first two runs of this harness
# failed on exactly this and the message named a missing lane rather than a wrong path.
m.ART = MUT_ART / "realize_graph_census-gate"
m.GATE.dir = m.ART
m.GATE.bend, m.GATE.oracle = Path(cfg["driver"]), Path(cfg["oracle"])
m.DIVERGES, m.WHY = m._pins()
if m.DIVERGES is not None:
    m.GATE.diverges, m.GATE.compared = m.DIVERGES, m.ROWS[0] - len(m.DIVERGES)
"""


def _runner(which, tail, rows=None):
    """Write the generated runner. THE CONFIG IS WRITTEN HERE, BY BOTH, because a runner
    that reads a config nobody wrote fails on a missing file -- and this harness's own
    first two runs died exactly there, which is why the writing lives with the writing of
    the runner rather than in one of the two callers."""
    CFG.write_text(json.dumps({**cfg(MUT_DRIVER, MUT_ORACLE, MUT_PORT), "rows": rows or {}}))
    (RUN if which == "run" else GUARDS).write_text(PREAMBLE.format(
        gates=str(HERE), art=str(MUT_ART), cfg=str(CFG)) + tail)
    return RUN if which == "run" else GUARDS


RUN_TAIL = """
checks = (lambda: (m.classes_hold() and m.no_bottom_value() and m.drivers_hold()
                   and m.axis_hold() and m.calls_hold() and m.pin_drift_holds()
                   and m.compares_holds() and m.kern_blind_holds() and m.argkinds_hold()
                   and m.ret_is_uop_fixed_holds()))
if m.DIVERGES is None:
    print("REFUSED, NOT A VERDICT: " + m.WHY, file=sys.stderr); sys.exit(3)
sys.exit(m.gate(m.GATE, "mutant", checks=checks))
"""

GUARDS_TAIL = """
rows = cfg["rows"]
m._lane = lambda name: rows.get(name)
# THE LANES ARE WRITTEN FROM INSIDE THE RUNNER, AND THAT IS THE THIRD OF THIS HARNESS'S OWN
# WIRING BUGS. `Gate.__init__` EMPTIES `gatekit.ART / name` at MODULE IMPORT -- the gate
# constructs its `Gate` two dozen lines above any `__main__`, and `_clear()` runs there --
# so a harness that writes the lanes BEFORE importing the gate has them deleted before the
# first check runs, and `no_bottom_value`, which asks `(ART / lane).is_file()` rather than
# calling `_lane`, answers False SILENTLY. MEASURED: three attempts, the third isolated it,
# and the symptom each time was the same -- one guard permanently red with no message.
m.ART.mkdir(parents=True, exist_ok=True)
for lane, vals in rows.items():
    (m.ART / lane).write_text("".join(f"%%s=%%s\\n" %% (k, v) for k, v in vals.items()))
# `pins_hold` IS NOT A DEF IN THE GATE. The pin-COUNT assertion is `_pins()` returning
# None, which makes the gate module REFUSE (exit 3) instead of running, so it is asserted
# here under the name the claim deserves rather than skipped because it has no def. Likewise
# `rows_hold` and `pin_lines()`, both named in the brief and ABSENT (grep -c 'def' is 0
# for each): the row count is `gatekit.Gate._lane`'s and the pin count is `_pins()`'s.
CHECKS9 = %r + ("pins_hold",)
out = {}
for nm in CHECKS9:
    if nm == "pins_hold":
        out[nm] = [m.DIVERGES is not None, [m.WHY] if m.WHY else []]
        continue
    buf = io.StringIO()
    # A GUARD THAT RAISES IS A VERDICT AND NOT AN ABSENCE. `classes_hold` SUBSCRIPTS the
    # lane (`port[r]`, `cpy[r]`) where `no_bottom_value` uses `.get(r, "bottom")`, so a lane
    # that is missing a row a class names takes `classes_hold` down with `KeyError` -- and
    # because `gate()` chains TEN checks with `and`, the crash hides the other NINE.
    # MEASURED on P2 (two drivers taking the name `beam`): the whole guard pass died and
    # reported nothing, which is a worse reading than the true one. The runner records the
    # exception as a RED verdict NAMED `EXC`, because a guard that cannot answer is
    # exactly the thing this harness is here to name, and a harness that dies on it has
    # learned nothing.
    try:
        with contextlib.redirect_stdout(buf):
            ok = getattr(m, nm)()
        out[nm] = [bool(ok), [l for l in buf.getvalue().splitlines() if l.strip()][:2]]
    except Exception as e:                                    # noqa: BLE001
        said = [l for l in buf.getvalue().splitlines() if l.strip()][:2]
        out[nm] = [False, ["EXC %%s: %%s" %% (type(e).__name__, e)] + said[:1]]
print("GUARDS " + json.dumps(out))
""" % (CHECKS,)


def unstage():
    """Remove every copy, INCLUDING the `__pycache__` that `_load_oracle()` creates inside
    `STAGE/` -- CPython writes the bytecode next to the source it loaded, and `pin_drift_holds`
    loads the STAGED oracle by path on every guard run, so the directory is never empty.
    Removing the TREE rather than iterating it is what makes that survivable."""
    for p in (MUT_PORT, MUT_DRIVER, MUT_ORACLE, RUN, GUARDS, CFG):
        p.unlink(missing_ok=True)
    shutil.rmtree(STAGE, ignore_errors=True)


def stage(driver=None, oracle=None, pins=None, port=None):
    """Write the mutant copies. `None` means "the original, byte for byte".

    THE DRIVER IS WRITTEN TWICE, and the second copy is the reason this function exists.
    `kern_blind_holds()` and `drivers_hold()` re-derive their populations by READING
    `(HERE / "realize_graph_census.bend")` and `PORT` as TEXT, so `STAGE/` carries the
    driver under its REAL name (for `m.HERE` to find) while `gates/realize-mut-driver.bend`
    carries the import-rewritten copy (for `bend` to run, whose relative imports only
    resolve from `gates/`).
    """
    drv = DRIVER.read_text() if driver is None else driver
    assert drv.count(DRIVER_IMPORT) == 1, "the driver's import of the port is not unique"
    STAGE.mkdir(exist_ok=True)
    (STAGE / "realize_graph_census.bend").write_text(drv)
    MUT_DRIVER.write_text(drv.replace(DRIVER_IMPORT, DRIVER_MUT_IMPORT))
    for name, text in (("realize_graph_census-oracle.py",
                        ORACLE.read_text() if oracle is None else oracle),
                       ("realize_graph_census-pins.rows",
                        PINS.read_text() if pins is None else pins)):
        (STAGE / name).write_text(text)
    MUT_ORACLE.write_text(ORACLE.read_text() if oracle is None else oracle)
    MUT_PORT.write_text(PORT.read_text() if port is None else port)


def cfg(driver, oracle, port):
    return {"here": str(STAGE), "port": str(port), "driver": str(driver),
            "oracle": str(oracle), "pins": str(STAGE / "realize_graph_census-pins.rows")}


def rows_of(text):
    return {k: v for k, v in (l.split("=", 1) for l in text.splitlines() if "=" in l)}


def capture_lanes():
    """`(py_rows, bd_rows)` from the mutant's OWN oracle and driver, run BY HAND.

    NOT read out of `gates/artifacts/`, and that is measured, not preferred: `gatekit`
    EMPTIES a gate's output directory before any check can fail and UNLINKS what it staged
    when the run was not green, so a RED run leaves no lane file at all. Running the two
    lanes directly is what makes the row count independent of the verdict, which is the
    whole point: a mutation that moves rows must be COUNTED, not inferred from an rc.

    ONE `bend` AT A TIME. Never two.
    """
    o = subprocess.run([str(PY), str(MUT_ORACLE)], capture_output=True, text=True, cwd=str(ROOT))
    b = subprocess.run([str(BEND), str(MUT_DRIVER)], capture_output=True, text=True, cwd=str(ROOT))
    return rows_of(o.stdout), rows_of(b.stdout), o.returncode, b.returncode


def run_gate():
    r = subprocess.run([str(PY), str(_runner("run", RUN_TAIL))],
                       capture_output=True, text=True, cwd=str(ROOT))
    return r.returncode, (r.stdout + r.stderr).strip()


def run_guards(rows):
    """`(name -> (ok, said))` for all ten checks, EACH DRIVEN ON ITS OWN.

    `rows` maps a lane file name to that lane's rows. `bn.out` is given `bd.out`'s rows:
    `bn` is the COMPILED run of the same program, so any way it could differ is already a
    `DISAGREE (bn)` in phase 1, and phase 2's job is to attribute a verdict to a guard
    rather than to re-derive a second lane.

    THE ROWS ARE ALSO WRITTEN AS FILES, and that is a fix rather than belt-and-braces.
    `no_bottom_value` does NOT go through `_lane` alone: it checks `(ART / lane).is_file()`
    and only then calls `_lane`, so injecting rows by monkeypatching `_lane` left it
    answering False with NO MESSAGE. MEASURED: it came back red on THIRTY OF THIRTY
    mutations, including the ones aimed at other guards, and one guard's permanent red is
    exactly how a mutation reading turns into noise -- and into a harness that agrees with
    itself about thirty findings it never made. The files are written by the generated
    runner AFTER the gate module is imported, because `Gate.__init__` empties that
    directory at import; see `GUARDS_TAIL`.
    """
    r = subprocess.run([str(PY), str(_runner("guards", GUARDS_TAIL, rows))],
                       capture_output=True, text=True, cwd=str(ROOT))
    for ln in r.stdout.splitlines():
        if ln.startswith("GUARDS "):
            return json.loads(ln[7:])
    # A runner that said nothing is NOT "no guard went red". Reporting an EMPTY result as
    # thirty silent guards is this harness's own version of class (e): a verdict inferred
    # from the absence of evidence. MEASURED -- the first run of this printed all thirty as
    # silent because the generated runner raised `NameError: contextlib` before printing,
    # and the summary agreed with it.
    raise RuntimeError("the guard runner printed no verdicts: "
                       + (r.stderr.strip() or r.stdout.strip())[-400:])


def moved(base, now):
    """`(changed, appeared, vanished)` -- a row that APPEARS or VANISHES is a mutation that
    MOVED, not one that failed to compile."""
    return ({k for k in set(base) & set(now) if base[k] != now[k]},
            sorted(set(now) - set(base)), sorted(set(base) - set(now)))


# ============================================================================ PHASE 1
# (label, kind, [(file, find, replace), ...]). `file` is "port", "driver", "oracle", "pins";
# an entry may touch TWO files, which is how the AXIS mutation that has to move both lanes
# together is written. `find` must be a UNIQUE substring -- an anchor appearing twice would
# mutate an unrelated arm and the reading would name the wrong row, so an entry whose anchor
# is not unique is REFUSED and reported rather than applied.
PHASE1 = [
    # ---------------------------------------------------------------- VALUE -- the port
    ("V1 `get_call_arg_uops` reverts to the op-CONDITIONAL slice (realize.py:15's "
     "UNCONDITIONAL `src[1:]` undone in the FIRST of its two sites)", "VALUE",
     [("port", "def get_call_arg_uops(+ar: O.Arena, call: U32) -> List<&2, U32>:\n"
               "  rz_arg_uops.go(ar, O.Arena.src_from(ar, call, 1), Nil{})",
       "def get_call_arg_uops(+ar: O.Arena, call: U32) -> List<&2, U32>:\n"
       "  rz_arg_uops.go(ar, O.Arena.src_without_body(ar, call), Nil{})")]),
    # **THIS ONE WAS VACUOUS AND NO LONGER IS.** It moved ZERO of the 974 rows at rc=0 and
    # was reported as a coverage gap; the cause was the PRINTER, not the fixture.
    # `rs_d_beam` printed `Bool.and(claimed, index != 0)` as a single `"0"`, and the default
    # this mutation changes is read only by `bm_zero` -- the CLAIM -- on the one node whose
    # rewrite is the identity, so the claim moved and the printed answer did not.
    # `<claim><fired>` prints `10` at the current default and `00` at this one, so this
    # moves `beam_55` and `bea0_55`. MEASURED after the change.
    ("V2 `rz_kernel_beam` DEFAULTS a KernelInfo-less SINK to 1 (SINK_NO_KI's wrong answer)",
     "VALUE",
     [("port", "def rz_kernel_beam(a: O.Arg) -> U32:\n  match a:\n"
               "    case O.AKernel{+ki}: O.KernelInfo.beam(ki)\n    case _: 0",
       "def rz_kernel_beam(a: O.Arg) -> U32:\n  match a:\n"
       "    case O.AKernel{+ki}: O.KernelInfo.beam(ki)\n    case _: 1")]),
    ("V3 `rz_res.slot` reads `slot + 1` (realize.py:131's `inputs[b.arg.slot]`, off by one)",
     "VALUE",
     [("port", "def rz_res.slot(ar: O.Arena, b: U32) -> U32:\n"
               "  PArg.slot(PArg.of(O.Arena.arg(ar, b)))",
       "def rz_res.slot(ar: O.Arena, b: U32) -> U32:\n"
       "  U32.add(PArg.slot(PArg.of(O.Arena.arg(ar, b))), 1)")]),
    ("V4 `bm_zero` never tests the beam, so `pm_beam` fires on a SINK that already carries one",
     "VALUE",
     [("port", "def bm_zero(+ar: O.Arena, +self: U32) -> Bool:\n"
               "  U32.is_eq(rz_kernel_beam(O.Arena.arg(ar, rz_body(ar, self))), 0)",
       "def bm_zero(+ar: O.Arena, +self: U32) -> Bool:\n  True{}")]),
    ("V5 `va_claim` forgets the SINK conjunct, so `pm_validate`'s tag 0 claims every CALL",
     "VALUE",
     [("port", "def va_claim(+ar: O.Arena, +self: U32) -> Bool:\n"
               "  Bool.and(O.op_is(ar, self, O.OpsCALL{}), "
               "O.op_is(ar, O.Arena.src(ar, self, 0), O.OpsSINK{}))",
       "def va_claim(+ar: O.Arena, +self: U32) -> Bool:\n  O.op_is(ar, self, O.OpsCALL{})")]),
    ("V6 `has_dnum` starts its walk already-TRUE", "VALUE",
     [("port", "def has_dnum(+ar: O.Arena, +call: U32) -> Bool:\n"
               "  rz_dnum.go(ar, O.UOp.toposort(rz_res_fuel(ar), ar, rz_body(ar, call)), False{})",
       "def has_dnum(+ar: O.Arena, +call: U32) -> Bool:\n"
       "  rz_dnum.go(ar, O.UOp.toposort(rz_res_fuel(ar), ar, rz_body(ar, call)), True{})")]),
    ("V7 `gn_body`'s PROGRAM arm answers no name (`get_call_name`'s PROGRAM dispatch)",
     "VALUE",
     [("port", "    case O.OpsPROGRAM{}: gn_kernel(ar, rz_body(ar, call))",
       "    case O.OpsPROGRAM{}: None{}")]),
    # ------------------------------------------------------ VALUE -- the port lane's PRINTER
    ("V8 `rs_s1.slot` drops the `@<slot>` suffix (the `md_graph_census` repair)", "VALUE",
     [("driver", "def rs_s1.slot(op: O.Op, sl: U32, s: String) -> String:\n  match op:\n"
                 "    case O.OpsPARAM{}: String.concat([s, \"@\", U32.show(sl)])\n"
                 "    case O.OpsBUFFER{}: String.concat([s, \"@\", U32.show(sl)])\n    case _: s",
       "def rs_s1.slot(op: O.Op, sl: U32, s: String) -> String:\n  match op:\n"
       "    case O.OpsPARAM{}: s\n    case O.OpsBUFFER{}: s\n    case _: s")]),
    ("V9 `rs_is_view` drops the MSTACK arm, so `res_52` loses its `<-` depth", "VALUE",
     [("driver", "    case O.OpsMSTACK{}: True{}\n    case O.OpsGETADDR{}: True{}",
       "    case O.OpsMSTACK{}: False{}\n    case O.OpsGETADDR{}: True{}")]),
    # -------------------------------------------------------------------- DEAD-DEF PROBES
    ("Z1 `va_1` is a DEAD DEF: its body answers `VSkip` (the gate says so; this re-measures)",
     "DEAD-DEF",
     [("port", "def va_1(+ar: O.Arena, +self: U32) -> O.Verdict:\n  fl_0(ar, self)",
       "def va_1(+ar: O.Arena, +self: U32) -> O.Verdict:\n  O.VSkip{}")]),
    # VACUOUS BY CONSTRUCTION, and it is a DECLARED BLINDNESS rather than a coverage gap. The
    # anchor is `realize.py:18`'s own slice and the port's own comment says every caller
    # passes a CALL, so the two spellings are the same VALUE wherever the port is run. The
    # reason no row can reach the difference: `get_call_var_uops` is driven by `var`, which
    # is CALL-only on BOTH lanes because `u.body` raises for a non-CALL, and for a CALL
    # `O.Arena.src_from(ar, call, 1)` and `Arena.src_without_body(ar, call)` ARE one value.
    # Closing it needs a BUFFER whose `src[0]` is a BOUND VAR -- `b0`/`b1` over `CONST 3`
    # cannot witness it, because `is_bound_var` drops a CONST either way -- AND a driver
    # that passes `prg` explicitly. That driver is honest (`realize.py`'s signature takes
    # `prg`) and is recorded in the commit as NOT DONE here.
    ("Z2 `rz_bound_map` -- SRC_BODY's SECOND fix site -- reverts to the op-conditional slice",
     "VACUOUS",
     [("port", "def rz_bound_map(+ar: O.Arena, call: U32) -> List<&2, Bnd>:\n"
               "  rz_bound.walk(ar, O.Arena.src_from(ar, call, 1), Nil{})",
       "def rz_bound_map(+ar: O.Arena, call: U32) -> List<&2, Bnd>:\n"
       "  rz_bound.walk(ar, O.Arena.src_without_body(ar, call), Nil{})")]),
    ("Z3 `rs_cval`'s non-`CInt` arm (a float CONST) is never taken", "DEAD-DEF",
     [("driver", "    case O.CInt{i}: rs_cval.cint(i)\n    case _: \"f\"",
       "    case O.CInt{i}: rs_cval.cint(i)\n    case _: \"0\"")]),
    # -- THE MULTI-DEVICE ROW, AND IT IS THE ONLY MUTATION THAT PROVES `rs_x64`/`rs_x65`
    #    ARE NOT DECORATION. Before them every device in the fixture was a scalar `S.D1`, so
    #    `dev_tags`'s `Dn` arm -- `realize.bend:652` -- was DEAD and nothing could say so.
    ("V10 `dev_tags`'s `Dn` arm drops the second device, so `kern` answers a COUNT of 1 for "
     "a two-device buffer", "VALUE",
     [("port", "  match d:\n    case S.D1{tag}: [tag]\n    case S.Dn{tags}: tags",
            "  match d:\n    case S.D1{tag}: [tag]\n    case S.Dn{tags}: [0]")]),
    # ---------------------------------------------------------------------- POPULATION
    ("P1 node 63 stops being minted: `arena_n` moves 66 -> 65 and the 15 `*_63` rows answer "
     "something else, while the `rows` COUNT is unchanged", "POPULATION",
     [("driver", "def rs_x63(+ar: O.Arena) -> O.Found:\n  rs_call(\"vv\", ar, [7, 3, 62, 42])",
       "def rs_x63(+ar: O.Arena) -> O.Found:\n  rs_x61(ar)")]),
    ("P2 two drivers take the name `beam`: 65 `bea0_*` rows AND `b_bea0` VANISH (66), and 65 "
     "`beam_*` DUPLICATE while the row COUNT still matches", "POPULATION",
     [("driver", "    case 6: \"bea0\"", "    case 6: \"beam\"")]),
    ("P3 `rs_arms_n()` drops an arm: one `arm_*` row VANISHES", "POPULATION",
     [("driver", "def rs_arms_n() -> Nat: 12n", "def rs_arms_n() -> Nat: 11n")]),
    ("P4 `rs_n()` drops a node: 1004 rows become 989", "POPULATION",
     [("driver", "def rs_n() -> Nat: 65n", "def rs_n() -> Nat: 64n")]),
    ("P5 the pins file loses ONE declared divergence", "POPULATION",
     [("pins", "res_63\tres_63=BUFFER/1@0[g0:-]+GETADDR/1<-BUFFER/1@1[g1:-]+CONST/0[1]\t"
               "res_63=BUFFER/1@0[g0:-]+GETADDR/1<-PARAM/0@0[g0:-]+CONST/0[1]\n", "")]),
    ("P6 one pin's PORT VALUE is edited (someone typed it wrong)", "POPULATION",
     [("pins", "res_63=BUFFER/1@0[g0:-]+GETADDR/1<-PARAM/0@0[g0:-]+CONST/0[1]\n",
       "res_63=BUFFER/1@0[g0:-]+GETADDR/1<-PARAM/0@1[g0:-]+CONST/0[1]\n")]),
    ("P7 one pin's CPython value is edited", "POPULATION",
     [("pins", "res_63=BUFFER/1@0[g0:-]+GETADDR/1<-BUFFER/1@1[g1:-]+CONST/0[1]\t",
       "res_63=BUFFER/1@0[g0:-]+GETADDR/1<-BUFFER/1@0[g1:-]+CONST/0[1]\t")]),
    ("P8 `rs_drv_name` RENAMES a driver: 63 rows vanish and 63 appear under a new name",
     "POPULATION",
     [("driver", "    case 2: \"res\"", "    case 2: \"resolve\"")]),
    # ------------------------------------------------------------------------------ AXIS
    ("X1 the PORT lane's `inputs` are the two BUFFERs in the OTHER order", "AXIS",
     [("driver", "def rs_inputs() -> List<&2, U32>:\n  [10, 9]",
       "def rs_inputs() -> List<&2, U32>:\n  [9, 10]")]),
    ("X2 BOTH lanes' `inputs` become the two PARAMs: the fixture axis the gate's own "
     "prose predicts makes `res_63` AGREE", "AXIS",
     [("driver", "def rs_inputs() -> List<&2, U32>:\n  [10, 9]",
       "def rs_inputs() -> List<&2, U32>:\n  [2, 3]"),
      ("oracle", "return lst(RZ.resolve_params(u, (b1, b0)))",
       "return lst(RZ.resolve_params(u, (g1, g0)))")]),
    ("X3 the `beam` driver's ctx is 3, not 7 (`bea0` at 0 is unchanged)", "AXIS",
     [("driver", "    case 5: rs_d_beam(ar, n, 7)", "    case 5: rs_d_beam(ar, n, 3)")]),
    ("X4 BOTH fixtures' `CONST(3)` becomes `CONST(4)`: an axis drift on which every row "
     "STILL MATCHES", "AXIS",
     [("port", "+n1 = O.UOp.const(a0, O.CInt{H.i64_of_i32(3)})",
       "+n1 = O.UOp.const(a0, O.CInt{H.i64_of_i32(4)})"),
      ("oracle", "c3 = _add(UOp.const(3))", "c3 = _add(UOp.const(4))")]),
    # **STILL VACUOUS, AND THE `arg` PAYLOAD DID NOT UN-VACUOUS IT. THE CAUSE IS MEASURED AND IT
    # IS NOT THE PRINTER.** `KernelInfo.beam`'s VALUE -- as opposed to "is it zero" -- is in
    # no row: the `:b=` suffix prints the REWRITTEN sink's beam, which is the ctx (7 or 0), never
    # the fixture's, so `grep -c 'b=2$' bd.out` is 0 and `grep -c 'b=' bd.out` is 9, all of them
    # `b=7` or `b=0` from a ctx. `rs_pay`'s `AKernel` arm prints `SINK/0[k2:<beam>]` now, so
    # the PRINTER objection is answered -- and the mutation STILL moves ZERO rows, because
    # **NO PORT ANSWER NAMES `k2` AT ALL**: `grep -c k2 bd.out` is **0** against **1** on the
    # CPython lane (`val_24`, whose cone names `SINK/0[k2:2]`). The reason is FIXTURE
    # REACHABILITY and not the printer: `k2` is `cK2`'s body, `pm_beam`'s claim is `beam == 0`,
    # so every driver that would carry it either REFUSES it (a non-CALL) or answers `00`, and
    # `get_call_arg_uops` drops `src[0]`. **A printer that prints a field nothing reads is a
    # printer limit; a printer that prints a field nothing can REACH is a coverage gap, and the
    # two read identically from here.** Closing it needs a driver whose answer contains node 8,
    # and that is a NEW ROW -- `ROWS = 1004` is asserted in four places and this is not the
    # census-shape decision that belongs to a fixture change.
    #
    # **THE 30-EVEN ROWS OF THIS ENTRY THAT DID MOVE ARE THE OTHER HALF:** `V4`, `V7`, `V10`
    # and the three `bn`/pin mutations. So `KernelInfo.beam`'s value is now visible WHERE A
    # ROW REACHES IT, which is the honest form of the claim.
    ("X5 BOTH fixtures' `k2` SINK carries beam 5, not 2 -- VACUOUS BY FIXTURE REACHABILITY, "
     "NOT BY THE PRINTER (`grep -c k2 bd.out` is 0 and 1 on the CPython lane)", "VACUOUS",
     [("port", "O.AKernel{kernel_info(\"k2\", 2)}", "O.AKernel{kernel_info(\"k2\", 5)}"),
      ("oracle", "k2 = _add(UOp(Ops.SINK, src=(), arg=_ki(\"k2\", 2)))",
       "k2 = _add(UOp(Ops.SINK, src=(), arg=_ki(\"k2\", 5)))")]),
    # -------------------------------------------------------------------- THE `arg` PAYLOAD
    # **THE PAYLOAD'S ARMS, ONE MUTATION EACH, AND THE ANSWER IS NOT "THEY ALL MOVE".** A
    # payload is a printer, and a printer's arms are exactly the defs a fixture can leave
    # UNREACHED, so each of the two halves is measured on its own rather than assumed.
    #
    # `rs_pay.pa`'s `val` half IS reached: `bn` (node 5) carries `val=4` and MEASURED
    # `grep -c '\[n:4\]' bd.out` is 2, so dropping the `val` half turns `PARAM/0@2[n:4]` into
    # `PARAM/0@2[n]` and `vn`/`bn` become indistinguishable -- which is the whole defect the
    # box names, re-created on purpose. `rs_pay.pi`'s three index lists are reached through
    # every cone that CONTAINS a PROGRAM, and there are 10 such rows on the port lane.
    ("V11 `rs_pay.pa` DROPS the ParamArg's BOUND VALUE, so a bound and an unbound variable of "
     "the same name print alike (`4` is `bn`'s `val`; `grep -c '\\[n:4\\]' bd.out` is 2)", "VALUE",
     [("driver", "      rs_pay.box(String.concat([rs_opt_str(name), \":\", rs_opt_const(val)]))",
       "      rs_pay.box(rs_opt_str(name))")]),
    # **V12 IS A LANE FAILURE AND NOT A READING, AND THAT IS THE SEVENTH CAUSE.** The `String`
    # locals `g`/`o`/`i` cannot be assigned a bare literal in bend -- `expected : an annotated
    # term (cannot infer)` -- so the first form did not compile and the lane VANISHED (1004
    # rows, `rc=3` = REFUSED). Measured here with `bend --check-only` rather than inferred: the
    # sweep's `bd rc=1, 1004 VANISHED` line and a refusal are the same event read twice.
    # The three `globals;outs;ins` halves ARE reached on the port lane -- ten rows carry a
    # PROGRAM token, MEASURED `grep -c 'PROGRAM/1\\[' bd.out` = 2 and `grep -c 'STORE/2\\['
    # bd.out` = 2 -- so this arm is live; it is its MUTATION that does not compile.
    # **V12'S FIRST TWO FORMS WERE LANE FAILURES, NOT READINGS, AND THE SECOND IS THE MORE
    # INTERESTING ONE.** (i) Assigning a bare `String` literal to `g`/`o`/`i` is
    # `expected : an annotated term (cannot infer)` and does not compile. (ii) The fix -- feed
    # `rs_ids` an EMPTY list instead -- DOES compile (`ALL PROOFS CHECK`) and then MOVES 2
    # ROWS: `flat_27` and `val_27`, which are the only two answers whose cone contains a
    # PROGRAM whose `globals;outs;ins` are not all-empty. So `get_call_outs_ins`'s two index
    # lists are in exactly TWO tokens on this census and the arm is live -- narrowly. **A
    # mutation that does not compile and a mutation nobody reads are ONE LINE in this sweep,
    # and getting that wrong would have put a live arm in the dead list.**
    ("V12 `rs_pay.pi` prints `vars` but empties `globals;outs;ins`, so `get_call_outs_ins`'s "
     "two lists are in no cone again -- MEASURED 2 rows, `flat_27` and `val_27`", "VALUE",
     [("driver", "      g = rs_ids(rs_fuel(ar), globals, \"\", True{})\n"
                 "      o = rs_ids(rs_fuel(ar), outs, \"\", True{})\n"
                 "      i = rs_ids(rs_fuel(ar), ins, \"\", True{})\n"
                 "      v = rs_pay.var(rs_fuel(ar), ar, vars, \"\", True{})",
       "      g = rs_ids(rs_fuel(ar), Nil{}, \"\", True{})\n"
       "      o = rs_ids(rs_fuel(ar), Nil{}, \"\", True{})\n"
       "      i = rs_ids(rs_fuel(ar), Nil{}, \"\", True{})\n"
       "      v = rs_pay.var(rs_fuel(ar), ar, vars, \"\", True{})")]),
    # **A SEVENTH DISTINCT CAUSE OF ZERO, MEASURED HERE AND IT IS NOT ANY OF THE SIX.** The
    # FIRST FORM OF `V11` passed `rs_opt_str`'s own `String` RESULT back into `rs_opt_str`,
    # which takes a `Maybe<&2, String>`: `bend` REFUSED the lane (`bd rc=1`, 1004 rows
    # VANISHED, gate `rc=3`). A mutation that does not COMPILE and a mutation nobody reads read
    # identically as "0 rows moved" from outside, and the harness reported both as one line.
    # It is listed here because it is a shape this sweep can produce and a report must name.
    # DEAD ARM: `rs_pay.ax` prints the RANGE's axis, and MEASURED on the promoted lane
    # `grep -c 'RANGE/' bd.out` is **0** -- the fixture's one RANGE is `rg` (node 28) and no
    # driver's ANSWER CONTAINS it, because `get_call_arg_uops` drops `src[0]` and no rewrite
    # mints a RANGE. So the arm is reached by no row and its spelling cannot be wrong. That
    # is a COVERAGE GAP in the FIXTURE and not a printer limit, and the fix is a row whose
    # answer contains node 28 -- NOT DONE, and named here rather than left to be found again.
    ("Z4 `rs_pay.ax` is a DEAD ARM: no row's answer contains a RANGE (`grep -c 'RANGE/' "
     "bd.out` is 0), so its spelling is unchecked", "DEAD-DEF",
     [("driver", "  Bool.pick(String, O.eq_axis(at, O.AXIS_DEVICE{}), \"d\", \"-\")",
       "  Bool.pick(String, O.eq_axis(at, O.AXIS_DEVICE{}), \"-\", \"-\")")]),
    # THE SAME VERDICT FOR A SECOND ARM, AND IT IS WORTH NAMING BECAUSE THE TWO ARE THE SAME
    # FACT: an arg kind only reaches a token if some ANSWER CONTAINS A NODE OF THAT KIND.
    # `CUSTOM_FUNCTION` is the arg of `cV`/`cE` (nodes 21/22) and `get_call_arg_uops` drops
    # `src[0]`, so MEASURED `grep -c 'CUSTOM_FUNCTION/' bd.out` is **0** -- while on the
    # CPython lane it is 7, inside `val_*`'s cones. So this arm is live on ONE lane and dead
    # on the other, which is a fact about the FIXTURE and about VAL_BODY (the port has no
    # `pm_validate` body, so it answers the claim bit and prints no cone at all).
    ("Z5 `rs_pay`'s `ACustom` arm is DEAD ON THE PORT LANE (`CUSTOM_FUNCTION/` is 0 in "
     "`bd.out`, 7 in `py.rows`): it is live on one side only", "DEAD-DEF",
     [("driver", "    case O.ACustom{cf}: rs_pay.box(O.CustomFunction.name(cf))",
       "    case O.ACustom{cf}: rs_pay.box(\"?\")")]),
]

# ============================================================================ PHASE 2
# GUARD MUTATIONS. Nothing here edits the gate. Each entry corrupts WHAT A GUARD WATCHES --
# a source file it re-derives its population from, or the lane rows it reads -- and the
# reading is that guard's own return value. A guard that cannot be made to fail is reported
# as such, because a check that has never been seen to fail is not a check.
#
# `rows` is a `lane -> {row: value}` patch layered over the BASELINE rows, so a guard that
# reads a lane is driven on a lane and a guard that reads a source is driven on a source.
PHASE2 = [
    # -- `classes_hold`: every class's claim, checked on the promoted lanes.
    ("G1 classes_hold: one `SRC_BODY_FIXED` row goes back to disagreeing", "GUARD",
     {"bd.out": {"arg_9": "TAMPERED"}}, None),
    ("G2 classes_hold: a `BOTTOM` row answers a value read off the arena", "GUARD",
     {"bd.out": {"b_arg": "CONST/0[3]"}}, None),
    ("G3 classes_hold: a `NAME_ARM` row answers something other than `none`", "GUARD",
     {"bd.out": {"name_18": "0"}}, None),
    ("G4 classes_hold: a `VAL_BODY` row answers neither claim bit", "GUARD",
     {"bd.out": {"val_23": "2"}}, None),
    ("G5 classes_hold: `kern_53` is no longer the declared SINK-in-the-arg-slot pair",
     "GUARD", {"bd.out": {"kern_53": "1"}}, None),
    ("G6 classes_hold: a `SINK_NO_KI` row stops being the declared pair", "GUARD",
     {"bd.out": {"beam_55": "1"}}, None),
    ("G7 classes_hold: a `SLOT_MISS` row stops being the declared pair", "GUARD",
     {"bd.out": {"res_20": "none"}}, None),
    ("G8 classes_hold: `wbuf_60` is no longer the declared MSELECT wall", "GUARD",
     {"bd.out": {"wbuf_60": "none"}}, None),
    ("G9 classes_hold: `res_63` is no longer the declared GETADDR drift pair", "GUARD",
     {"bd.out": {"res_63": "BUFFER/1@0[g0:-]+GETADDR/1<-PARAM/0@0[g0:-]+CONST/0[1]@0"}}, None),
    ("G10 classes_hold: a `RET_IS_UOP_FIXED` ctx-0 row stops being `10`", "GUARD",
     {"bd.out": {"bea0_23": "11:CALL/2[l],SINK/0[k1:0]"}}, None),
    # -- `no_bottom_value`: slot 0 and the arm-coverage rows, on BOTH port lanes.
    ("G11 no_bottom_value: the BOTTOM slot answers a value", "GUARD",
     {"bd.out": {"b_arg": "CONST/0[3]"}}, None),
    ("G12 no_bottom_value: an `arm_*` coverage row is ZERO (a tag no node reaches)", "GUARD",
     {"bd.out": {"arm_MSELECT": "0"}}, None),
    ("G13 no_bottom_value: the COMPILED lane disagrees where the interpreted one does not",
     "GUARD", {"bn.out": {"b_nb": "CONST/0[3]"}}, None),
    # -- `ret_is_uop_fixed_holds`: FINDING 2's regression row, both halves.
    ("G14 ret_is_uop_fixed_holds: no ctx-7 row FIRED (a fix that dropped every rewrite)",
     "GUARD", {"bd.out": {r: "00" for r in
                          ("beam_23", "beam_49", "beam_50", "beam_51", "beam_52", "beam_53",
                           "beam_61", "beam_63")}}, None),
    ("G15 ret_is_uop_fixed_holds: a ctx-7 row fired but no longer carries `b=7`", "GUARD",
     {"bd.out": {"beam_23": "11:CALL/2[l],SINK/0[k1:3],PARAM/0@0[g0:-]:b=3"}}, None),
    ("G16 ret_is_uop_fixed_holds: a ctx-0 `bea0_*` row stopped answering `10`", "GUARD",
     {"bd.out": {"bea0_49": "11:CALL/3[vs],SINK/0[k1:0]"}}, None),
    ("G16b ret_is_uop_fixed_holds: NO row is REFUSED, so a claim that fires on everything "
     "would pass the ctx-0 check alone", "GUARD",
     {"bd.out": "@all:00->10"}, None),
    # -- `calls_hold`: the ONE hand-written index list in the file, re-derived from lanes.
    #    THE TAMPER DIRECTION MATTERS and was wrong on the first two attempts: `calls_hold`
    #    asserts `(rows["oi_%d" % n] == "notacall") == (n not in CALLS)`, so editing a row
    #    that is ALREADY `notacall` cannot make it disagree -- both sides become True. It has
    #    to be a NON-CALL node (1) whose row stops being `notacall`, which makes the two sides
    #    differ. MEASURED, the first two entries were aimed at `oi_23`/`oi_24`, which are CALLS,
    #    and both read silent.
    ("G17 calls_hold: the CPython lane DRIVES a non-CALL node it must refuse (`oi_1`)",
     "GUARD", {"py.rows": {"oi_1": "0"}}, None),
    ("G18 calls_hold: the PORT lane DRIVES a non-CALL node it must refuse (`oi_1`)",
     "GUARD", {"bd.out": {"oi_1": "0"}}, None),
    # -- `compares_holds`: the refusal population, measured. BOTH ENTRIES ARE TAMPERED AT A
    #    NON-CALL INDEX, and the first attempt used node 23 -- a CALL -- which
    #    `compares_holds` never looks at, because its loop is `for n in nc`. MEASURED: both
    #    read SILENT, and the reading was a harness bug rather than a guard hole. This is the
    #    same shape as G17/G18 and the third time: a tamper aimed at the wrong half of the
    #    population measures nothing and looks exactly like a guard that never speaks.
    ("G19 compares_holds: `nb` refuses on a SUBSET of the non-CALLs (`nb_1` answers `1`)",
     "GUARD", {"py.rows": {"nb_1": "1"}}, None),
    ("G20 compares_holds: a refused row is refused by the CPython lane alone (`est_1`)",
     "GUARD", {"bd.out": {"est_1": "0"}}, None),
    ("G21 compares_holds: a bottom row no longer reads `bottom` on the CPython lane",
     "GUARD", {"py.rows": {"b_res": "none"}}, None),
    # -- `pin_drift_holds`: THE PIN RUNS ON EVERY PASS. NOT MUTATED -- driven instead.
    ("G22 pin_drift_holds: the pin's row `res_63` no longer equals the port's", "GUARD",
     {"bd.out": {"res_63": "BUFFER/1@0[g0:-]+GETADDR/1<-BUFFER/1@1[g1:-]+CONST/0[1]"}}, None),
    ("G23 pin_drift_holds: the pin ALSO answers `res_52`, so 'only one arm' is wrong",
     "GUARD", {"bd.out": {"res_52": "BUFFER/1@0[g0:-]+MSTACK/2<-BUFFER/1@1[g1:-]"}}, None),
# -- `kern_blind_holds`: a SOURCE claim on the driver's `S.Dn{[...]}` and the oracle's
    #    `("DISK", "CPU")`, AND a LANE claim on `kern_65`. **G24's old anchor was
    #    `rs_cpu`'s `S.D1{0}` and G25's was `device="CPU"`, and BOTH ARE SILENT against the
    #    current check** -- it no longer asks "is there exactly one device", because there
    #    is a second one on purpose now. A guard mutation aimed at what the guard stopped
    #    watching measures nothing and reads exactly like a guard that never speaks, which
    #    is the third time this harness has made that mistake, so both anchors were
    #    re-aimed at what it watches NOW.
    ("G24 kern_blind_holds: the PORT fixture's two tags are NOT distinct", "GUARD",
     None, ("driver", "def rs_duo() -> S.Dev:\n  S.Dn{[6, 0]}",
             "def rs_duo() -> S.Dev:\n  S.Dn{[6, 6]}")),
    ("G25 kern_blind_holds: the CPython fixture's multi-device parts from ('DISK', 'CPU')",
     "GUARD", None,
     ("oracle", '_buf_dev(3, "g2", ("DISK", "CPU"))',
      '_buf_dev(3, "g2", ("CUDA", "CPU"))')),
    ("G25b kern_blind_holds: the promoted PORT lane's `kern_65` is not 2", "GUARD",
     {"bd.out": {"kern_65": "1"}}, None),
    ("G25c kern_blind_holds: the CPython lane's `kern_65` is not 2", "GUARD",
     {"py.rows": {"kern_65": "1"}}, None),
    # -- `axis_hold`: THE DRIVER AXIS, READ BACK FROM FOUR PLACES. Five mutations, one per
    #    site plus the ORDER, because a check that reads four places and can only be made to
    #    fail by editing one of them has not been shown to read the other three.
    ("G31 axis_hold: the bend lane's `rs_drv_name` RENAMES a driver the oracle still spells "
     "its own way", "GUARD", None,
     ("driver", '    case 2: "res"', '    case 2: "resolve"')),
    ("G32 axis_hold: the ORACLE's `DRIVERS` renames a driver the bend lane still spells its "
     "own way", "GUARD", None,
     ("oracle", 'DRIVERS = ("arg", "nb", "res", "flat"', 'DRIVERS = ("arg", "nb", "RES", "flat"')),
    ("G33 axis_hold: `rs_drv_name` REORDERS two arms, so arm N no longer names the driver at "
     "index N", "GUARD", None,
     ("driver", '    case 0: "arg"\n    case 1: "nb"', '    case 0: "nb"\n    case 1: "arg"')),
    ("G34 axis_hold: `rs_call_only` flips one arm, so the PORT and the oracle disagree about "
     "which drivers are CALL-only", "GUARD", None,
     ("driver", "    case 3: False{}\n    case 4: False{}",
      "    case 3: True{}\n    case 4: False{}")),
    ("G35 axis_hold: the oracle's `drive` ladder loses an arm, so that driver would answer "
     "`raise=NoDriver`", "GUARD", None,
     ("oracle", '        if drv == "nb":\n            return nb_sig(u)\n', "")),
    # -- `no_bottom_value`: the beam claim bit IS an answer and is accepted as one, so the
    #    mutation has to be a CONE to be a stale-arena read. Aimed at the old single-bit
    #    `"0"` it reads SILENT after the two-bit printer, which is why it is spelled this way.
    ("G35b no_bottom_value: the BOTTOM slot answers a beam CONE", "GUARD",
     {"bd.out": {"b_beam": "11:CALL/2[l],SINK/0[k1:7],PARAM/0@0[g0:-]:b=7"}}, None),
    # -- `drivers_hold`: the DRIVER AXIS, re-derived from `realize.bend` and `realize.py`.
    ("G26 drivers_hold: `realize.bend` loses a `*_table` driver", "GUARD", None,
     ("port", "def flatten_table() -> O.PMEntrys:", "def flatten_tab() -> O.PMEntrys:")),
    ("G27 drivers_hold: `realize.bend` loses the `+ar: O.Arena` on an entry point", "GUARD",
     None, ("port", "def resolve_params(fuel: Nat, +ar: O.Arena, +call: U32, "
                    "+inputs: List<&2, U32>) -> RList:",
            "def resolve_params(fuel: Nat, ar: O.Arena, +call: U32, "
            "+inputs: List<&2, U32>) -> RList:")),
    ("G28 drivers_hold: `realize.bend` grows a SEVENTEENTH `case O.Ops*` arm", "GUARD", None,
     ("port", "def rz_arm(op: O.Op) -> U32:\n  match op:\n    case O.OpsMSELECT{}: 0",
      "def rz_arm(op: O.Op) -> U32:\n  match op:\n    case O.OpsGETADDR{}: 4\n"
      "    case O.OpsMSELECT{}: 0")),
    ("G29 drivers_hold: `realize.bend` grows a TENTH ladder owning a `case O.Ops*`",
     "GUARD", None,
     ("port", "def rz_arm(op: O.Op) -> U32:\n  match op:\n    case O.OpsMSELECT{}: 0",
      "def rz_extra(op: O.Op) -> U32:\n  match op:\n    case O.OpsGETADDR{}: 4\n"
      "    case _: 0\n\n"
      "def rz_arm(op: O.Op) -> U32:\n  match op:\n    case O.OpsMSELECT{}: 0")),
    # -- THE PIN-COUNT ASSERTION. `_pins()` returns None and the gate module REFUSES (3)
    #    rather than running. Reported as `pins_hold`, which is NOT a def in the gate: the
    #    brief names `rows_hold` and `pin_lines()` and NEITHER IS IN THE FILE (both 0), so
    #    the runner asserts the claim the gate actually makes.
    ("G30 the pin-COUNT assertion: the pins file gains a row no class declares", "GUARD",
     None, ("pins", "res_63\tres_63=", "res_63_X\tres_63_X=")),
    # -- `argkinds_hold`: NO LANE MAY PRINT `[?]`, AND THE GUARD'S SUBJECT IS A LANE, NOT A
#    SOURCE. **THE FIRST TAMPER WAS SILENT TWICE, FOR TWO DIFFERENT REASONS, AND BOTH ARE
#    WORTH NAMING.** (i) The first aimed at `rs_pay`'s `ACustom` arm, which is a DEAD ARM on the
#    port lane (`Z5` measures it: `grep -c 'CUSTOM_FUNCTION/' bd.out` is 0), so the placeholder
#    reached no row. (ii) The second aimed at the ORACLE'S `ACustom` arm -- a lane that does
#    print `CUSTOM_FUNCTION/1[validate]`, seven times -- and was ALSO silent, because PHASE 2
#    DRIVES THE CHECKS ON INJECTED LANE ROWS AND THE ORACLE IS NEVER RUN: a source edit only
#    reaches the checks that RE-DERIVE their population from that source (`axis_hold`,
#    `kern_blind_holds`, `drivers_hold`), and `argkinds_hold` reads the lane text. So the
#    tamper must be a LANE ROW, and that is the third time this harness has aimed at the wrong
#    KIND of subject rather than at the wrong half of a population.
    # ... AND THE ROW CHOSEN HAS TO BE ONE NOBODY ELSE READS. The first row tried was `arg_9`,
    # which is in `SRC_BODY_FIXED` -- `classes_hold` reads it FIRST and `and`-chains, so the
    # run went red on `classes_hold` and `argkinds_hold` never got to speak. That is the
    # harness's own lesson (`GUARDS_TAIL` records `classes_hold` SUBSCRIPTS the lane where
    # `no_bottom_value` uses `.get`) applied in reverse: a row another guard owns cannot
    # demonstrate this guard. `arm_MSELECT` is read by `no_bottom_value` (a `0` check) and by
    # nothing else, so `PROGRAM/1[-;0,1;0,1][?]` is that row's shape plus a placeholder.
    ("G36 argkinds_hold: a promoted lane carries the `[?]` placeholder in a row no other "
     "guard reads (`arm_MSELECT`)", "GUARD",
     {"bd.out": {"arm_MSELECT": "PROGRAM/1[-;0,1;0,1][?]"}}, None),
    # -- `compares_holds`'s CROSS-CHECK, WHICH IS THE HALF NOBODY HAS MUTATED. The guard
    #    measures `refused` off the lanes and compares it with the number the VERDICT LINE
    #    DERIVES from the oracle's own `CALL_ONLY` times `NONCALL`. The tamper drops one
    #    member of `CALL_ONLY`, which does NOT change what the lanes refuse (the lanes
    #    decide from the node's OWN OP TAG) and so leaves the measured `refused` at 378
    #    while the derived claim drops to 336. A cross-check that cannot disagree with the
    #    thing it cross-checks is not a cross-check.
    ("G37 compares_holds: the DERIVED refusal count and the MEASURED one disagree, because "
     "the oracle's `CALL_ONLY` lost a member the lanes still honour", "GUARD", None,
     ("oracle", "CALL_ONLY = frozenset(d for d in DRIVERS if d in\n"
                "                      (\"oi\", \"wbuf\", \"kern\", \"name\", \"est\", \"var\", "
                "\"gcc\", \"dnum\", \"nb\"))",
      "CALL_ONLY = frozenset(d for d in DRIVERS if d in\n"
      "                      (\"oi\", \"wbuf\", \"kern\", \"name\", \"est\", \"var\", "
      "\"gcc\", \"dnum\"))")),
]


def _gate_module():
    """THE GATE, LOADED BY PATH, WITH `gatekit.ART` REPOINTED FIRST.

    `gatekit.ART` is repointed BEFORE the import because the gate module constructs its
    `Gate` at import time and `Gate.__init__` empties that directory; without this the
    harness's own bookkeeping would delete `gates/artifacts/realize_graph_census-gate/`.
    """
    sys.path.insert(0, str(HERE))
    import gatekit
    gatekit.ART = MUT_ART
    spec = importlib.util.spec_from_file_location("rgz_decl", GATE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def declared_divergences():
    """`set(DIVERGING)` -- THE GATE'S OWN DECLARATION, LOADED BY PATH, IN THIS PROCESS.

    A harness that counts the pins file's own rows has learned only that the file agrees
    with itself -- `decomp_value-pins.rows` records `same` AND `DIFFER` verdicts in ONE
    column and a tally that counted both reported 452 declared divergences against a truth
    of 254.
    """
    mod = _gate_module()
    if mod.DIVERGES is None:
        raise RuntimeError("the gate declares no divergences: " + mod.WHY)
    return set(mod.DIVERGING)


def declared_rows():
    """`ROWS[0]` -- THE EXPECTED LANE WIDTH, READ OFF THE GATE AND NOT WRITTEN HERE.

    It was `974` in this file until the census grew to 1004 rows, and a literal like that
    is `checks/sweep.py`'s `LIVE_UNITS`: it agrees with itself for as long as nobody
    notices, and then it refuses a correct run. `gates/realize_graph_census-gate.py:727`
    compared `len(base_bd) != 974` and would have said "THE BASELINE DOES NOT REPRODUCE"
    about a green tree.
    """
    return _gate_module().ROWS[0]


def src_of(which):
    return {"port": PORT, "driver": DRIVER, "oracle": ORACLE, "pins": PINS}[which]


def apply_edits(edits):
    """`edits` -> `{which: text}`, or `None` when an anchor is not unique. REFUSED, not
    silently skipped: a mutation whose pattern stopped matching is an entry the report has
    to account for, not a green one."""
    out = {}
    for which, find, repl in edits:
        text = src_of(which).read_text()
        if text.count(find) != 1:
            return None
        out[which] = text.replace(find, repl)
    return out


def phase1(base_py, base_bd, only=None):
    width = max(len(m[0]) for m in PHASE1)
    moved_n = green = exc = vacuous = 0
    caught = [0]                       # CAUGHT is not MOVED: three mutations below move no
                                       # row and are still caught, because they move a PIN
    for label, kind, edits in PHASE1:
        if only and only not in label:
            continue
        new = apply_edits(edits)
        if new is None:
            print(f"  {label:<{width}}  REFUSED -- an anchor is not unique; NOT RUN")
            green += 1
            continue
        try:
            stage(driver=new.get("driver"), oracle=new.get("oracle"),
                  pins=new.get("pins"), port=new.get("port"))
            py, bd, pyrc, bdrc = capture_lanes()
            ch, app, van = moved(base_bd, bd)
            rc, out = run_gate()
            # INSIDE THE `try`, and that is the FIFTH of this harness's own wiring bugs: the
            # guard pass needs the staged copies -- `drivers_hold` READS `PORT` -- and the
            # first run of phase 1 called it after `unstage()` and died with
            # `FileNotFoundError: realize-mut.bend` on the very first mutation. A `finally`
            # that cleans up before the last reader has read is a teardown, not a guard.
            guards = {n: said for n, (ok, said) in
                      run_guards({"py.rows": py, "bd.out": bd,
                                  "bn.out": bd}).items() if not ok}
            exc += sum(1 for s in guards.values() if s and s[0].startswith("EXC "))
        finally:
            unstage()
        moved_n += 1 if (ch or app or van) else 0
        caught[0] += 0 if (rc == 0 and not guards) else 1
        why = ("rc=%d lane rc=(py %d, bd %d) %d changed%s%s"
               % (rc, pyrc, bdrc, len(ch),
                  ", %d APPEARED" % len(app) if app else "",
                  ", %d VANISHED" % len(van) if van else ""))
        print(f"  {label:<{width}}  [{kind}] {why}")
        if ch:
            print(f"      moved: {', '.join(sorted(ch)[:10])}"
                  + (f" (+{len(ch) - 10} more)" if len(ch) > 10 else ""))
        if app:
            print(f"      APPEARED: {', '.join(app[:8])}")
        if van:
            print(f"      VANISHED: {', '.join(van[:8])}"
                  + (f" (+{len(van) - 8} more)" if len(van) > 8 else ""))
        if guards:
            print(f"      GUARDS RED: {', '.join(sorted(guards))}"
                  + (f"  ({sum(1 for s in guards.values() if s and s[0].startswith('EXC '))} "
                     f"of them by EXCEPTION, not by a verdict)" if any(
                      s and s[0].startswith("EXC ") for s in guards.values()) else ""))
            for n in sorted(guards):
                for ln in guards[n][:1]:
                    print(f"        {ln[:150]}")
        elif rc == 0:
            # "GREEN at rc=0 <-- the mutation was NOT found" IS A FINDING, and it is a
            # COVERAGE GAP and a DEAD BRANCH and a VACUOUS MUTATION three different things.
            # The three read identically from here, so the harness cannot tell them apart
            # and must not pretend to: an entry that DECLARES itself `VACUOUS` is printed
            # as such, with its reason in the entry, and is counted apart from the
            # unclassified ones. That is the whole point -- `V2` sat in the second bucket
            # for a session and the reason turned out to be a PRINTER, so a bucket nobody
            # re-examines is a place a finding goes to die.
            if kind == "VACUOUS":
                print("      VACUOUS BY CONSTRUCTION, declared in the entry: no row can "
                      "reach the difference. NOT counted as a coverage gap.")
                vacuous += 1
            else:
                print("      GREEN at rc=0  <-- the mutation was NOT found")
                green += 1
    return moved_n, green, exc, caught[0], vacuous


def phase2(base_py, base_bd, only=None):
    width = max(len(m[0]) for m in PHASE2)
    silent = 0
    # THE BASELINE, THROUGH THIS DRIVER. All ten checks on the untouched lanes must be
    # GREEN, or every reading below is a red that was already there. It is asserted here
    # rather than assumed: the first run of this file reported `no_bottom_value` red on
    # thirty of thirty mutations for exactly this reason and nothing said so. The copies
    # are staged around it because `drivers_hold` READS `PORT`, so the unmutated reading
    # needs the unmutated copy to exist.
    try:
        stage()
        base = run_guards({"py.rows": base_py, "bd.out": base_bd, "bn.out": base_bd})
    finally:
        unstage()
    dirty = sorted(n for n, (ok, _) in base.items() if not ok)
    if dirty:
        print(f"  REFUSED: {dirty} are RED ON THE UNMUTATED LANES, so no mutation reading "
              f"below would mean anything:")
        for n in dirty:
            for ln in base[n][1][:2]:
                print(f"      {ln[:150]}")
        return 99
    print(f"  all {len(base)} checks GREEN on the unmutated lanes, so a red below is one "
          f"this harness made")
    for label, kind, patch, edit in PHASE2:
        if only and only not in label:
            continue
        new = apply_edits([edit]) if edit else {}
        if edit and new is None:
            print(f"  {label:<{width}}  REFUSED -- the anchor is not unique; NOT RUN")
            silent += 1
            continue
        try:
            stage(driver=new.get("driver"), oracle=new.get("oracle"),
                  pins=new.get("pins"), port=new.get("port"))
            rows = {"py.rows": dict(base_py), "bd.out": dict(base_bd),
                    "bn.out": dict(base_bd)}
            for lane, vals in (patch or {}).items():
                # `"@all:<value>-><replacement>"` IS EVERY ROW OF THAT LANE WHOSE BASELINE
                # VALUE IS `<value>`, SET TO `<replacement>`. A guard that holds a SHAPE
                # ("some row fired AND some row was refused") cannot be broken by a
                # six-row patch, and a six-row patch that reads SILENT looks exactly like a
                # guard that never speaks -- `compares_holds`' own comment above records
                # the third time this harness aimed at the wrong size. The population is
                # DISCOVERED from that lane's own captured rows rather than hand-listed,
                # because a 57-name literal is a second place for the census's shape to rot.
                if isinstance(vals, str):
                    was, _, now = vals.removeprefix("@all:").partition("->")
                    src = base_py if lane == "py.rows" else base_bd
                    vals = {r: now for r, v in src.items() if v == was}
                rows[lane].update(vals)
            guards = run_guards(rows)
        finally:
            unstage()
        red = {n: said for n, (ok, said) in guards.items() if not ok}
        if not red:
            print(f"  {label:<{width}}  [{kind}] NOTHING WENT RED  <-- the guard is silent")
            silent += 1
            continue
        print(f"  {label:<{width}}  [{kind}] RED: {', '.join(sorted(red))}")
        for n in sorted(red):
            for ln in red[n][:1]:
                print(f"      {ln[:150]}")
    return silent


def main():
    argv = sys.argv[1:]
    t0 = time.time()
    print("== PHASE 0: the baseline, and THE PINS FILE'S OWN SHAPE")
    pins = [l for l in PINS.read_text().splitlines() if l.strip() and not l.startswith("#")]
    bad = [l for l in pins if len(l.split("\t")) != 3]
    if bad:
        print(f"REFUSED: {len(bad)} pins rows are not 3 TAB-separated fields, e.g. {bad[0][:80]!r}. "
              f"A harness that parses a pins file must ASSERT ITS SHAPE FIRST -- "
              f"`decomp_graph_census-pins.rows` records `same` AND `DIFFER` in one column and "
              f"a tally that counted both reported 452 declared divergences where the truth "
              f"is 254.")
        return 1
    stage()
    base_py, base_bd, pyrc, bdrc = capture_lanes()
    rc0, out0 = run_gate()
    unstage()
    print(f"-- unmutated: gate rc={rc0}, py rows={len(base_py)} (rc {pyrc}), "
          f"bd rows={len(base_bd)} (rc {bdrc}), pins data rows={len(pins)} "
          f"(all 3 fields)")
    want_rows = declared_rows()
    if rc0 != 0 or len(base_py) != want_rows or len(base_bd) != want_rows:
        print(f"-- THE BASELINE DOES NOT REPRODUCE; every reading below would be about a "
              f"broken harness (the gate's own ROWS is {want_rows}, read off it by path):"
              f"\n{out0[-800:]}")
        return 1
    # THE DIVERGENCE POPULATION IS THE GATE'S OWN DECLARATION, LOADED BY PATH -- never a
    # count written here, which is how a hand-maintained number goes stale un-noticed. And
    # every pins row's NAME is checked against it, so a pins file carrying a row no class
    # declares is caught by the SHAPE CHECK rather than by a downstream `KeyError`.
    declared = set(declared_divergences())
    undeclared = sorted({l.split("\t")[0] for l in pins} - declared)
    if undeclared:
        print(f"REFUSED: the pins file carries {len(undeclared)} rows the gate's own class "
              f"tuples do not declare: {undeclared[:6]}")
        return 1
    print(f"-- the gate's own `_pins()` declares {len(declared)} divergences and every pins "
          f"row names one of them")

    moved_n = silent = boom = vacuous = 0
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1]
    if "--phase" not in argv or "1" in argv:
        print("\n== PHASE 1: VALUE / POPULATION / AXIS -- each one runs both lanes and the gate")
        moved_n, green, boom, caught_n, vacuous = phase1(base_py, base_bd, only)
        silent += green
    if "--phase" not in argv or "2" in argv:
        print("\n== PHASE 2: GUARD -- no bend; each check is driven with a world it must reject")
        quiet = phase2(base_py, base_bd, only)
        if quiet == 99:
            return 1                     # the baseline itself is red; nothing below is a finding
        silent += quiet
    # `ru_maxrss` is BYTES on Darwin and KIBIBYTES on Linux, and multiplying by 1024
    # unconditionally reports a 33 GiB harness on a machine with 16 GiB of RAM in it.
    # MEASURED: the first run of this printed `steady-state RSS 33648 MiB`. The unit is
    # read from `sys.platform` rather than assumed.
    scale = 1 if sys.platform == "darwin" else 1024
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * scale
    kids = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss * scale
    print(f"\n== harness steady-state RSS {rss/2**20:.1f} MiB, largest child "
          f"{kids/2**20:.0f} MiB ({kids/2**30:.2f} GiB -- one `bend` at a time, and the "
          f"gate's own measured peak for this driver), {time.time() - t0:.0f}s wall for "
          f"the whole run")
    if "--phase" not in argv or "1" in argv:
        print(f"== {moved_n} of {len(PHASE1)} lane mutations moved a row, and {caught_n} of "
              f"{len(PHASE1)} were CAUGHT (a pins mutation moves no row and is still caught, "
              f"so 'moved' and 'caught' are counted apart rather than conflated)")
        print(f"== {vacuous} of them are DECLARED VACUOUS -- unreachable by construction, "
              f"named with the reason in the entry -- and are NOT counted in the "
              f"{silent} found-nothing below, because a stated ceiling and an undiscovered "
              f"gap are not the same finding")
    print(f"== {silent} entries found NOTHING (a coverage gap or a dead def, named above "
          f"rather than hidden) -- {len(PHASE1) + len(PHASE2)} mutations in the full run")
    if boom:
        print(f"== {boom} GUARD(S) ANSWERED BY RAISING rather than by a verdict -- those are "
              f"GATE BUGS, named above as `EXC <Type>: <msg>`, and a chained `and` means "
              f"each one hides every check after it")
    return 1 if silent else 0


if __name__ == "__main__":
    raise SystemExit(main())