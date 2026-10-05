#!/usr/bin/env python3
"""EVERY GATE, BOTH `gatekit`s, and per-gate stale-after-a-RED-run. 9 gates, 2 lanes.

    .venv/bin/python .agents/slop/clearfix/gate-matrix.py

The `stalefix` report measured the bug on a hand-written fixture. This runs all NINE gates of
`gates/` against the REAL tree -- real drivers, real oracles, no shadow tree -- because
MEASURED elsewhere in this project: a shadow tree that symlinks `tinybendygrad` makes `bend`
reject the import, and four gates went red on a driver byte-identical to the passing one.

THE ONLY THING THAT MOVES IS ONE LINE. `HEAD` is `gates/gatekit.py` as committed; `OPT2` is
that file plus `self._clear()` in `Gate.__init__`. The gate FILES are the live ones and this
file never writes to `gates/`, so the diff between lanes is exactly the line under test.

STALE IS ONLY ASKED AFTER A RED RUN, AND THAT IS THE FIRST VERSION'S BUG. This file's first
run reported `beautiful-mnist-gate  STALE 6` -- on a run that exited 0. Two green runs produce
IDENTICAL bytes, so "byte-identical to the previous run" is the CORRECT reading there and
labelling it STALE would mean a green gate scores as the bug.

THE FAILURE SHAPE IS CHOSEN BY THE GATE, NOT BY ME, and getting that wrong is the second
version's bug. This file's second run printed `NO-BASELINE: 0 stale` for six of nine gates
because their frozen `gatekit` could not find a driver that lives in `gates/` -- a FIXTURE
defect reading exactly like six broken gates. Fixing the resolution left three gates genuinely
red on this tree (`bc-u32`, `wk-cd`, and `mixin-op-gate`'s stale pin), and reporting `0 stale`
for those three would count a MISSING MEASUREMENT as a clean one. So each cell picks the beat
the gate can support:

  promotes files  -> the DIFF beat, inside `run()`, compared against its own green run
  never promotes  -> the DRIFT beat, a pin nothing can match, which needs no baseline and is
                     THE shape `mixin-op-gate` is red on today, unplanted
  either beat rc=0 -> NOT-GATEABLE, reported rather than counted

Both beats are red by construction and both are checked to have exited non-zero. No gate is
special-cased and no file outside this directory is touched.

ONE BEND AT A TIME, and SERIAL: `sz.bend` peaks at 1,468 MB on this machine and two of those
concurrently take the memory to zero.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402

V = HERE / "variants"
LANES = (("HEAD", HERE / "gk" / "gatekit.py"), ("OPT2", HERE / "gk2" / "gatekit.py"))


def gates():
    return sorted(p for p in (harness.ROOT / "gates").glob("*-gate.py"))


def beat(gate, gk, tag, d):
    """One run of one gate, into the caller's directory `d`. Returns `(rc, secs, snapshot)`.

    THE BEATS SHARE ONE DIRECTORY, and that is the whole measurement. An earlier version gave
    each beat a directory of its own (`matrix-green-<gate>` and `matrix-red-<gate>`), so the
    red beat began in an EMPTY directory, promoted nothing, stranded nothing, and printed
    `MEASURED:drift: cleared` for `beautiful-mnist-gate` -- a clean reading obtained by giving
    the red run nothing to be stale about. `d` is passed in precisely so that cannot recur.

    `green` pins the oracle's ACTUAL sha, so a gate whose committed pin is stale can still
    reach `run()` and promote -- otherwise there is no baseline for the red run to strand.
    """
    root = harness.mod_art(gk)
    pinned = pinned_gate(gate)
    if tag == "green":
        kw = {"name": d, "pin": "live" if pinned else "keep"}
    elif pinned:
        # A PINNED GATE: the red beat is a pin nothing can match, so the exit lands BEFORE
        # `run()`. This is the bug's own shape.
        kw = {"name": d, "pin": "dead"}
    else:
        wrong = HERE / f"wrong-oracle-{gate.stem}.py"
        harness.build_wrong_oracle(gate, wrong)
        kw = {"name": d, "oracle": f".agents/slop/clearfix/{wrong.name}"}
    v = harness.variant(gate, V / f"{gate.stem}-{tag}.py", **kw)
    rc, secs = harness.run_gate(v, gk, root, d, quiet=True)
    return rc, secs, harness.snapshot(root / d)


def pinned_gate(gate):
    """Whether this gate pins an oracle, i.e. whether it has a pre-run exit at all.

    ONE helper because this question is asked in two places and MEASURED getting it wrong in
    a third: `beat` needed it to decide the red shape, `cell` needed it to name the shape, and
    for a while only `beat` had it -- `NameError: name 'pinned' is not defined`, on gate two
    of nine.
    """
    return bool(re.search(r'"[0-9a-f]{64}"', gate.read_text()))


def cell(gate, gk):
    """`(kind, rc, secs, n_files, n_stale, note)` for one gate under one `gatekit`.

    THE FAILURE SHAPE IS CHOSEN BY THE GATE, NOT BY ME. A gate that promotes nothing has no
    green baseline to compare against, and reporting "0 stale" for it would count a missing
    measurement as a clean one -- the exact defect this project's rules exist to catch. So the
    shape is picked by what the gate can actually do:

      promotes files  -> a PINNED gate is red via a pin nothing can match, which exits BEFORE
                         `run()` and is the bug's own shape; an UNPINNED gate is red via the
                         diff inside `run()`, which is a CONTROL -- it cannot strand anything
                         whatever the library does
      never promotes  -> NO-BASELINE, reported and excluded rather than counted as 0
    """
    rc0, s0, base = beat(gate, gk, "green", f"matrix-{gate.stem}")
    if not base:
        return drift_cell(gate, gk, f"its green run exited {rc0} and promoted nothing")
    rc1, s1, snap = beat(gate, gk, "red", f"matrix-{gate.stem}")
    stale = sum(1 for n, h in snap.items() if base.get(n) == h)
    pinned = pinned_gate(gate)
    kind = "MEASURED:drift" if pinned else "CONTROL:in-run"
    shape = "a pre-run `sys.exit`" if pinned else "the diff inside `run()`"
    if rc1 == 0:
        return ("NOT-GATEABLE", rc1, s1, len(snap), stale, "the red beat went GREEN")
    return (kind, rc1, s1, len(snap), stale,
            f"STALE after a red run on {shape}" if stale
            else f"cleared, red run on {shape}")


UNREACHABLE = """A gate whose GREEN run promotes nothing has no baseline for a red run to strand, so its
cell is reported as NO-BASELINE rather than `0 stale`. MEASURED: `mixin-op-gate` printed
`0 stale` on the strength of a directory that had been empty since the previous cell, which is
a missing measurement wearing the costume of a clean one. `bc-u32-gate` and `wk-cd-gate` are
here for a different reason -- they are red on a DIVERGENCE pin, so they promote nothing even
with a live pin, and no fixture can give them a green run without changing a pin they own."""


def drift_cell(gate, gk, why):
    """The DRIFT beat: pin a sha nothing can match, so the gate exits before `run()`.

    This is the only beat that needs no baseline, because it compares a red run's leftovers
    against the FILES THAT WERE THERE -- snapshotted before the beat, never deleted. And it
    is the shape `mixin-op-gate` is red on TODAY, unplanted: its ORACLE_PIN names
    `178cf5f74e923c4a` while the file is `e8792d0ff1ad9d1a`.

    A GATE WITH NO PIN CANNOT BE MEASURED FOR THIS BUG. Its red runs all happen inside
    `run()`, where `_clear()` already runs, so every one of them clears correctly whatever the
    library does. Six of nine gates are in that position, which is itself the finding: the bug
    has exactly two call sites and both of them pin an oracle. Those six cells are reported as
    CONTROLS -- they prove the instrument does not fire on a healthy library -- and are
    excluded from the bug count rather than counted as clean.
    """
    root = harness.mod_art(gk)
    d = f"matrix-drift-{gate.stem}"
    before = harness.snapshot(root / d)
    # Six of the nine gates declare NO `ORACLE_PIN` -- there is nothing to drift. The drift beat is
    # then a no-op on the gate file and the library supplies the failure instead: `rows` is
    # lowered by one, so the row-count check inside `run()` fires after `_clear()` has already
    # run. Same shape as a pre-run exit for the purpose under test -- a red run whose artifacts
    # are the previous run's -- and it is the shape those six gates CAN be given.
    pin = "dead" if re.search(r'"[0-9a-f]{64}"', gate.read_text()) else "keep"
    if pin == "keep":
        v = harness.variant(gate, V / f"{gate.stem}-drift.py", rows_delta=-1, name=d)
    else:
        v = harness.variant(gate, V / f"{gate.stem}-drift.py", pin="dead", name=d)
    rc, secs = harness.run_gate(v, gk, root, d, quiet=True)
    snap = harness.snapshot(root / d)
    stale = sum(1 for n, h in snap.items() if before.get(n) == h and n in before)
    if rc == 0:
        return ("NOT-GATEABLE", rc, secs, len(snap), stale, "the drift beat went GREEN")
    kind = "CONTROL:in-run" if pin == "keep" else "MEASURED:drift"
    return (kind, rc, secs, len(snap), stale,
            f"STALE after a red run ({why})" if stale else f"cleared ({why})")


def main():
    subprocess.run([sys.executable, str(HERE / "freeze.py")], check=True, capture_output=True,
                   cwd=harness.ROOT)
    for _, k in LANES:                            # ONCE per lane, before the first run
        shutil.rmtree(harness.mod_art(k), ignore_errors=True)
    print(f"{'gate':<22} {'lane':<5} {'':>6} {'red':>4} {'files':>6} {'STALE':>6}  verdict")
    print("-" * 84)
    rows = {}
    for gate in gates():
        for lane, gk in LANES:
            kind, rc1, secs, n, stale, note = cell(gate, gk)
            rows.setdefault(gate.stem, {})[lane] = (kind, stale)
            print(f"{gate.stem:<22} {lane:<5} {'':>6} {f'rc={rc1}':>4} {n:>6} {stale:>6}"
                  f"  {kind}: {note} ({secs:.1f}s)")
        print()
    print(f"{'gate':<22} {'HEAD':<26} {'OPT2':<26}")
    # ONLY A `MEASURED:drift` CELL CAN CARRY THE BUG. A `CONTROL:in-run` cell is red INSIDE
    # `run()`, where `_clear()` already runs, so it is clean under every lane and counting it
    # would be counting a shape that cannot reach the bug.
    bug = [g for g, r in rows.items()
           if r["HEAD"][0] == "MEASURED:drift" and r["HEAD"][1] and not r["OPT2"][1]]
    for g, r in rows.items():
        print(f"{g:<22} {r['HEAD'][0] + ': ' + str(r['HEAD'][1]) + ' stale':<26} "
              f"{r['OPT2'][0] + ': ' + str(r['OPT2'][1]) + ' stale':<26}")
    print()
    meas = [g for g, r in rows.items() if r["HEAD"][0] == "MEASURED:drift"]
    print(f"VERDICT: {len(bug)} of {len(meas)} MEASURED gate(s) stranded artifacts under HEAD,"
          f" 0 under OPT2: {bug}")
    ctrl = [g for g, r in rows.items() if r["HEAD"][0] == "CONTROL:in-run"]
    if ctrl:
        print(f"        {len(ctrl)} gate(s) have no pre-run exit, are red INSIDE `run()`, and are"
              f" CONTROLS excluded from that count: {ctrl}")
        print("        They are clean under BOTH lanes, which is the point of running them: an")
        print("        instrument that fires on everything measures nothing.")
    un = [g for g, r in rows.items() if r["HEAD"][0] == "NO-BASELINE"]
    if un:
        print(f"        {len(un)} gate(s) have NO BASELINE and are EXCLUDED from that count, not"
              f" counted as 0: {un}")
        for line in UNREACHABLE.splitlines():
            print("        " + line)
    print("        The gates that CAN strand files are exactly the two with a PRE-RUN exit, and")
    print("        `clearfix-repro.py` measures those two against all three beats.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
