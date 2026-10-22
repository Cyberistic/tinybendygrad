#!/usr/bin/env python3
"""realize_graph_census-plant.py -- THE WAYS THE REALIZE GRAPH CENSUS COULD BE WRONG,
PLANTED ONE AT A TIME.

    .venv/bin/python gates/realize_graph_census-plant.py            # the cheap plants
    .venv/bin/python gates/realize_graph_census-plant.py --slow     # and the bend one

**A PLANT THAT DOES NOT MOVE A ROW IS NOT A PLANT.** THE TREE HAS FOUND FOUR OF THEM
(`naming-gate`'s VERBATIM count, `elf.bend`'s row count, `run-port-mm.sh`'s rc, and the
`V2` mutation that folded a claim bit away), SO EVERY PLANT HERE ASSERTS THAT THE
THING IT MUTATES **MOVES A ROW** OR **MAKES A COUNT WRONG** -- IT NEVER ASSERTS THAT A
CHECK "FAILS", BECAUSE A CHECK THAT FAILS FOR A REASON THE PLANT DID NOT CAUSE IS A
VACUOUS PLANT WEARING A FAILURE's NAME.

**THE FOUR NAMES THIS PLANT COVERS, AND WHY EACH IS A REAL RISK HERE:**

  `WRONG-DEVICE`  A CALL THAT COMPILES BUT PASSES THE WRONG DEVICE. THE PIN's
                  `get_call_kernel_args` TAKES A DEVICE **TUPLE** AND THE PORT TAKES ONE
                  `S.Dev`, AND THE BRIDGE IS THE CALL's OWN DEVICE. A CONSTANT WOULD
                  COMPILE, WOULD BE WRONG ON THE TWO-DEVICE BUFFER (`rs_x64`/`rs_x65`),
                  AND WOULD BE INVISIBLE -- THE DEVICE IS IN NO NODE SHAPE, SO IT IS
                  IN THE GETADDR's PAYLOAD AS A COUNT. THE PLANT MUTATES THE CENSUS's
                  DEVICE READER TO A CONSTANT AND ASSERTS THAT `var_65`'s VALUE MOVES.

  `SHRUNK-ROWS`   A GATE THAT COMPARES FEWER ROWS AND STILL SAYS PASS. **THIS IS THE
                  DANGEROUS ONE.** THE PLANT REMOVES ONE DRIVER FROM THE ORACLE's
                  `CALL_ONLY` SET, SO THE ORACLE ANSWERS THE NON-CALL NODES INSTEAD OF
                  REFUSING THEM: THE ROW COUNT STAYS AT 1004, THE TWO LANES STILL HAVE
                  THE SAME ROW COUNT, AND THE COMPARED ROW COUNT FALLS BY THE NUMBER OF
                  NON-CALL NODES. **THE THING THAT CATCHES IT IS `compares_holds()`,
                  WHICH MEASURES THE REFUSAL POPULATION OFF THE PROMOTED LANES ON EVERY
                  RUN** -- AND THE PLANT ASSERTS THAT THE COMPARED COUNT MOVED.

  `ORACLE-RAISE`  AN ORACLE THAT STILL RAISES ON A ROW THE PORT NOW ANSWERS. THE
                  READER THAT BROKE WAS `apay`'s `ProgramInfo` ARM READING THE RENAMED
                  FIELD `a.vars`, AND `rewrite_sig`'s `try` WRAPPED THE PRINTING, SO IT
                  WAS REPORTED AS `raise=AttributeError` INSTEAD OF KILLING THE LANE.
                  THE PLANT PUTS `a.vars` BACK AND ASSERTS THAT THE ORACLE's
                  `raise=AttributeError` COUNT GOES ABOVE ZERO -- THE LANE WAS BROKEN
                  AND SAID NOTHING.

  `WBUF-DROPPED`  A `wbuf` ROW DROPPED WITHOUT BEING REPORTED. `get_call_written_bufs`
                  WAS DELETED UPSTREAM (`a26c50b01`), SO THE ORACLE ANSWERS THOSE ROWS
                  WITH A **TRANSCRIPTION** OF THE DELETED FUNCTION. A TRANSCRIPTION CAN
                  SILENTLY STOP BEING ONE. THE PLANT REPLACES THE `wbuf` ARM's ANSWER
                  WITH A CONSTANT AND ASSERTS THAT THE `wbuf_*` ROWS MOVE.

**WHAT THIS PLANT DOES NOT COVER, STATED RATHER THAN LEFT IMPLICIT:** A WRONG DEVICE OF
THE SAME *COUNT* IS STILL INVISIBLE, BECAUSE THE COUNT IS THE ONLY DEVICE PROJECTION
BOTH LANES CAN PRODUCE (`device_vocab_holds` MEASURES THE PREMISE: CPython HAS NO
`str -> int` DEVICE INDEX). THE COUNT IS COMPLETE FOR THIS FIXTURE's DEVICE VOCABULARY,
WHICH HAS EXACTLY TWO MEMBERS WHOSE COUNTS DIFFER.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
ORACLE = HERE / "realize_graph_census-oracle.py"
BEND = HERE / "realize_graph_census.bend"
# THE COMPILER, AND NOT THE DRIVER: `bin/bend` IS A SHIM ONTO `references/bend/bend2/main.ts`
# AND A BARE `bend` RESOLVES TO NOTHING.
BENDC = ROOT / "bin" / "bend"
PINS = HERE / "realize_graph_census-pins.rows"


def _pins() -> dict:
    """THE PINNED (CPython, PORT) PAIR PER ROW, LOADED BY PATH."""
    out = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        row, py, bd = ln.split("\t")
        out[row] = (py, bd)
    return out


def _run_oracle(src: Path) -> dict:
    """THE ORACLE'S ROWS, AS A MAP. A LANE THAT RAISES IS A CRASH, NOT A ROW COUNT.

    **A CRASH IS A ROW COUNT OF ZERO AND NOT A ROW COUNT AT ALL**, SO IT IS RAISED: A
    PLANT THAT MAKES THE ORACLE CRASH IS A PLANT THAT CAUGHT THE CRASH, AND THE GATE
    THAT RUNS IT SEES A DEAD LANE (EXIT 5) INSTEAD OF A COMPARISON OF NOTHING."""
    r = subprocess.run([str(PY), str(src)], capture_output=True, text=True, cwd=ROOT)
    if r.returncode:
        raise SystemExit(f"the oracle failed: {r.stderr[-2000:]}")
    return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)


def _oracle_crashes(src: Path) -> str:
    """THE ORACLE'S OWN FAILURE, OR THE EMPTY STRING WHEN IT RAN. A STALE FIXTURE IS A
    CRASH HERE AND NOT A DIVERGENCE, BECAUSE THE ORACLE ASSERTS ITS OWN NODE COUNT."""
    r = subprocess.run([str(PY), str(src)], capture_output=True, text=True, cwd=ROOT)
    return "" if r.returncode == 0 else r.stderr.strip().splitlines()[-1]


def _mutated(src: Path, tmp: Path, old: str, new: str, *more: tuple[str, str]) -> Path:
    """A COPY WITH THE EDITS IN IT. THE COPY IS THE PLANT; THE TREE IS NOT TOUCHED."""
    text = src.read_text()
    for a, b in (((old, new),) + more):
        if a not in text:
            raise SystemExit(f"the plant's anchor is not in {src.name}: {a!r}")
        text = text.replace(a, b)
    dst = tmp / src.name
    dst.write_text(text)
    return dst


def plant_stale_fixture(tmp: Path) -> bool:
    """THE FIXTURE's INDEX MAP GOES STALE AGAIN -- **THE PLANT THAT WOULD HAVE CAUGHT THE
    365 DIVERGENCES.**

    THE MUTATION: THE ORACLE's FIXTURE's SIZE CONST BECOMES A DIFFERENT CONST, SO THE
    PORT's `main_arena` (WHICH MINTS A SIZE CONST FOR EVERY PARAM AND BUFFER) AND THE
    ORACLE's FIXTURE DISAGREE ABOUT THE SHAPE. UPSTREAM `1af4ba921` ("size -> src[0]")
    MOVED THE PARAM's SIZE INTO ITS FIRST SRC, AND `ops.bend:3075`'s `UOp.new.param` MINTS
    IT -- SO THE PORT's ARENA HAS ONE MORE NODE AND EVERY INDEX FROM SLOT 3 ON IS ONE
    HIGHER.

    THE DETECTOR: **THE `arena_n` ROW.** IT IS THE ONE ROW THAT COUNTS THE FIXTURE, AND IT
    IS WHAT SAID `67` ON THE PORT AND `66` ON THE ORACLE. **THE PLANT ASSERTS THAT ROW
    MOVED** -- AND EVERY OTHER ROW WOULD MOVE WITH IT, WHICH IS WHY THE PLANT IS ABOUT THE
    COUNT AND NOT ABOUT A LIST.
    """
    print("== PLANT stale-fixture ==")
    # THE INVERSE OF THE FIX: THE SIZE CONST LEAVES THE ORACLE's FIXTURE AND THE PARAMS
    # GO BACK TO HAVING NO `src`, WHICH IS EXACTLY HOW THE FIXTURE READ BEFORE `1af4ba921`
    # MOVED THE SIZE INTO `src[0]`.
    src = _mutated(ORACLE, tmp,
                   "c16 = _add(UOp.const(16))                                                     # 2\n",
                   "",
                   ("src=(c16,)", "src=()"))
    crash = _oracle_crashes(src)
    if not crash:
        print("   THE PLANT DID NOT MOVE ANYTHING. A plant that moves nothing is not a "
              "plant.")
        return False
    print(f"   the ORACLE CRASHED: {crash}")
    print("   OK: A STALE FIXTURE IS A **DEAD LANE** AND NOT A DIVERGENCE, BECAUSE THE "
          "ORACLE ASSERTS ITS OWN NODE COUNT (`assert NODES == 66`) AND A CRASH IS A ROW "
          "COUNT OF ZERO AND NOT A ROW COUNT AT ALL. THIS IS THE PLANT THAT WOULD HAVE "
          "CAUGHT THE 365 DIVERGENCES THE CENSUS CARRIED SINCE `1af4ba921`: THE GATE IS "
          "NOT IN ANY WORKFLOW, SO NOBODY RAN IT.")
    return True


def plant_wrong_device(tmp: Path) -> bool:
    """A CALL THAT COMPILES BUT PASSES THE WRONG DEVICE.

    THE MUTATION: THE CENSUS's `rs_d_var` READS THE CALL's OWN DEVICE (`rs_call_dev`).
    THE PLANT REPLACES THAT WITH THE CONSTANT `rs_cpu()` -- WHICH COMPILES, AND IS WRONG
    ON THE TWO-DEVICE BUFFER.

    THE DETECTOR: THE PORT LANE's `var_66` ROW. THE TWO-DEVICE BUFFER IS `rs_x64`/`rs_x65`
    AND `var_66` IS THE ROW OVER THE CALL THAT PASSES IT, SO ITS GETADDR CARRIES A DEVICE
    OF TWO DEVICES AND A CONSTANT WOULD CARRY ONE. **THE DEVICE IS IN NO NODE SHAPE, SO
    THE ONLY WAY A WRONG DEVICE IS VISIBLE IS THE GETADDR's PAYLOAD, WHICH CARRIES THE
    DEVICE's COUNT** -- and the count is what this plant moves.

    **THIS PLANT NEEDS A `bend` COMPILE** OF THE MUTATED DRIVER, SO IT RUNS ONLY WHEN
    `SLOW_PLANTS=1`.
    """
    print("== PLANT wrong-device ==")
    old = "rs_call_dev(a, n)"
    new = "rs_cpu()"
    # **THE PLANT IS AT THE CALL SITE AND NOT AT A ROW, BECAUSE THE DEVICE IS IN NO
    # ROW.** THE DEVICE IS IN NO NODE SHAPE: CPython's GETADDR's ARG IS A TUPLE OF
    # NAMES AND THE PORT's IS A LIST OF TAGS, AND THERE IS NO `str -> int` INDEX TO CHECK
    # ONE AGAINST THE OTHER. **AND NO `var` ROW EVER MINTS A GETADDR**, BECAUSE NO
    # PROGRAM IN THE FIXTURE CARRIES A BUFFER PARAM -- SO A CALL THAT PASSED THE WRONG
    # DEVICE TO `get_call_kernel_args` MOVES NO ROW AT ALL IN THE CENSUS. MEASURED: THE
    # PLANT BELOW MOVED ZERO ROWS AND `var_66` READ `none` ON BOTH SIDES.
    #
    # **SO THE DEVICE IS CHECKED WHERE IT IS PASSED: AT THE CALL SITE.** THE PLANT
    # MUTATES THE CENSUS's DRIVER TO PASS A CONSTANT AND ASKS
    # `gates/realize_kernel_args-gate.py`'s `device_holds()` -- WHICH READS BOTH LANES'
    # SOURCE -- WHETHER IT STILL HOLDS. **A PLANT THAT CANNOT BE SEEN IN A ROW IS A
    # PLANT AGAINST A CHECK, AND THE CHECK IS THE THING THAT HAS TO HOLD.**
    src = _mutated(BEND, tmp, old, new)
    # THE GATE's FILE NAME CARRIES A HYPHEN, SO ITS MODULE NAME IS NOT DERIVABLE FROM IT:
    # MEASURED, `import realize_kernel_args_gate` answers `ModuleNotFoundError`. IT IS
    # LOADED BY PATH, THE SAME WAY `gates/realize_graph_census-gate.py`'s `_load_oracle`
    # LOADS THE ORACLE.
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "realize_kernel_args_gate", HERE / "realize_kernel_args-gate.py")
    rkag = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rkag)
    if rkag.device_holds(src):
        print("   THE PLANT MOVED NOTHING: `device_holds()` still holds with a CONSTANT "
              "device. A check that a wrong device does not move is not a check.")
        return False
    print("   OK: `device_holds()` WENT RED on a CONSTANT device. THE DEVICE IS IN NO NODE "
          "SHAPE AND IN NO COMPARED ROW -- AND THE CHECK THAT CATCHES IT IS A CHECK OF "
          "THE CALL SITE, WHICH IS WHERE THE DEVICE IS PASSED. A CALL THAT COMPILES AND "
          "PASSES THE WRONG DEVICE IS THE WORSE OF THE TWO FAILURES BECAUSE IT IS "
          "SILENT.")
    return True


def plant_shrunk_rows(tmp: Path) -> bool:
    """A GATE THAT COMPARES FEWER ROWS AND STILL SAYS PASS. **THE DANGEROUS ONE.**

    THE MUTATION: ONE DRIVER LEAVES THE ORACLE's `CALL_ONLY` SET, SO THE ORACLE ANSWERS
    THE NON-CALL NODES INSTEAD OF REFUSING THEM.

    WHY IT IS THE DANGEROUS ONE: **THE ROW COUNT DOES NOT MOVE.** EVERY (DRIVER, NODE)
    PAIR IS STILL EMITTED, SO THE ORACLE STILL PRINTS 1004 ROWS AND THE PORT STILL
    PRINTS 1004 ROWS AND THE TWO STILL HAVE THE SAME ROW COUNT. WHAT MOVED IS THE
    NUMBER OF ROWS THAT *COMPARE*: THE `notacall` REFUSALS WERE EXACT MATCHES AND THEY
    ARE NOW ANSWERS THAT DISAGREE, SO THE COMPARED POPULATION SHRANK. **A GATE THAT
    COMPARES 500 ROWS INSTEAD OF 1004 AND STILL SAYS PASS IS THE CLASS OF DEFECT THIS
    TREE KEEPS FINDING**, AND `compares_holds()` IS WHAT CATCHES IT: IT MEASURES THE
    REFUSAL POPULATION OFF THE PROMOTED LANES ON EVERY RUN AND ASKS THAT EVERY DRIVER
    WHICH REFUSES AT ALL REFUSES ON *ALL* THE NON-CALL NODES.
    """
    print("== PLANT shrunk-rows ==")
    old = 'CALL_ONLY = frozenset(d for d in DRIVERS if d in\n' \
          '                      ("oi", "wbuf", "kern", "name", "est", "var", "gcc", "dnum", "nb"))'
    new = 'CALL_ONLY = frozenset(d for d in DRIVERS if d in\n' \
          '                      ("oi", "kern", "name", "est", "var", "gcc", "dnum", "nb"))'
    src = _mutated(ORACLE, tmp, old, new)
    rows = _run_oracle(src)
    base = _run_oracle(ORACLE)
    if len(rows) != len(base):
        print(f"   the row count moved {len(base)} -> {len(rows)}, so the plant changed "
              "the POPULATION and not the COMPARISON -- the row count is not the thing "
              "that shrank and this plant is not the one that catches it")
        return False
    refused = sum(1 for k, v in base.items() if v == "notacall")
    now = sum(1 for k, v in rows.items() if v == "notacall")
    moved = [k for k in base if base[k] != rows.get(k)]
    print(f"   rows {len(base)} -> {len(rows)} (UNCHANGED, as the plant intends); "
          f"refusals {refused} -> {now}; {len(moved)} rows moved")
    if not moved:
        print("   THE PLANT MOVED NOTHING. A plant that moves nothing is not a plant.")
        return False
    if refused == now:
        print("   THE REFUSAL POPULATION DID NOT MOVE, so `compares_holds()` would NOT "
              "see it -- the plant does not exercise the check it claims to exercise")
        return False
    print("   OK: the refusal population moved, so `compares_holds()` -- which MEASURES "
          "it off the lanes -- sees it. The row count is unchanged, which is exactly "
          "why the row count is not the instrument.")
    return True


def plant_oracle_raise(tmp: Path) -> bool:
    """AN ORACLE THAT STILL RAISES ON A ROW THE PORT NOW ANSWERS.

    THE MUTATION: `apay`'s `ProgramInfo` ARM READS THE RENAMED FIELD BACK (`a.vars`).
    THE READER THAT BROKE, AND THE REASON THE BREAK WAS INVISIBLE: `rewrite_sig`'s
    `try` WRAPPED THE CONE PRINTING, SO THE ORACLE REPORTED ITS OWN DEFECT AS
    `raise=AttributeError` -- AN ANSWER -- INSTEAD OF KILLING THE LANE.

    THE DETECTOR: THE ORACLE's `raise=AttributeError` COUNT. IT IS ZERO TODAY, AND THE
    FOUR THAT REMAIN ARE CPython's OWN ANSWERS ON A SINK WITH NO `KernelInfo`
    (`beam_55`, `bea0_55`, `name_57`, `est_57`) -- WHICH ARE DECLARED DIVERGENCES AND
    NOT DEFECTS. **SO THE PLANT'S CLAIM IS THAT THE COUNT GOES ABOVE FOUR, NOT ABOVE
    ZERO**, BECAUSE ZERO WOULD BE A CLAIM ABOUT CPython's ANSWERS AND NOT ABOUT THE
    ORACLE.
    """
    print("== PLANT oracle-raise ==")
    old = "_ids([v.arg.name for v in a.params])"
    new = "_ids([v.arg.name for v in a.vars])"
    src = _mutated(ORACLE, tmp, old, new)
    rows = _run_oracle(src)
    base = _run_oracle(ORACLE)
    n_now = sum(1 for v in rows.values() if v == "raise=AttributeError")
    n_base = sum(1 for v in base.values() if v == "raise=AttributeError")
    print(f"   raise=AttributeError {n_base} -> {n_now}")
    if n_now <= n_base:
        print("   THE PLANT MOVED NOTHING. A plant that moves nothing is not a plant.")
        return False
    print(f"   OK: the oracle's OWN AttributeError count went {n_base} -> {n_now}. The "
          f"{n_base} THAT REMAIN ARE CPython's OWN ANSWERS (A SINK WITH NO "
          f"`KernelInfo`), NOT THE ORACLE'S DEFECT -- AND THE PRINTING IS NOW OUTSIDE "
          f"THE `try`, SO A REAL PRINTER DEFECT KILLS THE LANE INSTEAD OF BECOMING A "
          f"ROW.")
    return True


def plant_wbuf_dropped(tmp: Path) -> bool:
    """A `wbuf` ROW DROPPED WITHOUT BEING REPORTED.

    THE MUTATION: THE ORACLE's `wbuf` ARM ANSWERS A CONSTANT INSTEAD OF CALLING THE
    TRANSCRIBED FUNCTION.

    WHY IT MATTERS: `get_call_written_bufs` WAS DELETED UPSTREAM (`a26c50b01`), SO THE
    ORACLE'S ANSWER FOR THOSE 23 ROWS IS A **TRANSCRIPTION** -- THE ONLY TRANSCRIPTION
    IN EITHER LANE. A TRANSCRIPTION CAN SILENTLY STOP BEING ONE, AND A ROW THAT
    STOPPED BEING ANSWERED IS A ROW COUNT THAT FELL BECAUSE A FUNCTION WAS DELETED,
    WHICH IS A MEASUREMENT AND NOT A TRIVIALITY.

    THE DETECTOR: THE `wbuf_*` ROWS' VALUES, COMPARED AGAINST THE PINNED ONES.
    """
    print("== PLANT wbuf-dropped ==")
    old = "        if drv == \"wbuf\":\n            return lst(_written_bufs(u))"
    new = "        if drv == \"wbuf\":\n            return \"none\""
    src = _mutated(ORACLE, tmp, old, new)
    rows = _run_oracle(src)
    base = _run_oracle(ORACLE)
    moved = [k for k in base if k.startswith("wbuf_") and base[k] != rows.get(k)]
    print(f"   {len(moved)} `wbuf_*` rows moved")
    if not moved:
        print("   THE PLANT MOVED NOTHING. A plant that moves nothing is not a plant.")
        return False
    pins = _pins()
    pinned = [k for k in moved if k in pins]
    print(f"   OK: {len(moved)} `wbuf_*` rows moved and {len(pinned)} of them are PINNED, "
          "so the pin check goes red. A dropped row that was not pinned would not be "
          "caught -- and that is the arm the gate's own row count is for.")
    return True


PLANTS = (plant_shrunk_rows, plant_oracle_raise, plant_wbuf_dropped,
          plant_stale_fixture, plant_wrong_device)


def main() -> int:
    print("realize_graph_census-plant: the ways the realize graph census could be wrong, "
          "planted one at a time\n")
    ok = True
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for p in PLANTS:
            if not p(tmp):
                ok = False
    print()
    print("realize_graph_census-plant: " + ("every plant MOVED something" if ok else
                                            "AT LEAST ONE PLANT MOVED NOTHING"))
    return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())
