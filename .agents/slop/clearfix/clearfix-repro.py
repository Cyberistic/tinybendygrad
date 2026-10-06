#!/usr/bin/env python3
"""THE REPRO: a gate's early `sys.exit` outlives the run that wrote the artifacts.

    .venv/bin/python .agents/slop/clearfix/clearfix-repro.py

THREE LANES, THREE BEATS, TWO GATES. A cell is `(exit status, what the artifact directory
held afterwards)`, and "what it held" is a sha256 against the SAME LANE'S OWN previous green
run -- never a count, because a count cannot tell "its own bytes" from "the last good run's
bytes", which is the whole claim.

  NOW   frozen pre-fix gate + gatekit as committed     -- the bug as it stands
  FIX   the LIVE gate, UNEDITED + gatekit + `_clear()` in `Gate.__init__`

THE FIX LANE EDITS NO GATE FILE, AND THAT IS THE CLAIM, NOT AN OMISSION. Option 2 is
`_clear()` moved to `Gate.__init__`, so a gate that constructs its `Gate` and then does
whatever it likes -- including `sys.exit(2)` before `run()` -- has already emptied the
directory. The FIX lane therefore runs `gates/mixin-op-gate.py` exactly as committed, against
the repaired library, and asserts the stranding exit no longer strands. An earlier version of
this file ran the live gate against the UNREPAIRED library and reported "the fix did not
survive", which was true and uninformative: there was no fix in it.

  A0 green      pin intact, so `run()` reaches its end and promotes. Establishes the bytes.
                Not a staleness beat -- see the note on the green row in the table.
  A1 drift      pin dead, so `oracle_drift` fires and `sys.exit(2)` fires BEFORE `run()`.
                THIS IS THE BUG. Expected NOW: every file STALE. Expected FIX/OPT2: EMPTY.
  A2 disagree   the CPython lane emits one COMPARED row's value changed, so the DIFF fires
                INSIDE `run()` after every lane wrote. THE NEGATIVE CONTROL, and it is what
                proves the instrument can move: if A2 read STALE the same way A1 does, then
                A1 would be reporting "red run" rather than "the last green run's bytes".

WHY THREE LANES AND NOT TWO. FIX runs the live gate UNEDITED against the repaired library, so
it shows the mechanism rather than a patch: the same early `sys.exit(2)` that defeats NOW
defeats nothing, because the directory was emptied at CONSTRUCTION and no exit after that can
put a file back. OPT2 runs the FROZEN PRE-FIX gate against the repaired library, which is the
same claim from the other side -- the repair does not depend on this gate having been updated,
so it is still a repair after the next precondition check is added above the drift check.

THE ONE GREEN BEAT PER LANE IS NOT REDUNDANT. `Gate.run()` opens with `_clear()`, so after
A1 or A2 the directory is empty and A0 has to run again; that is the gate clearing its own
output, which is the thing under test, not the harness deleting anything. Nothing is removed
between beats at all. The scratch root is emptied once, before the first beat, and never
again.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import harness  # noqa: E402

VAR = HERE / "variants"
GK, GK2 = HERE / "gk" / "gatekit.py", HERE / "gk2" / "gatekit.py"
GATES = ("mixin-op-gate", "beautiful-mnist-gate")
LANES = ("NOW", "FIX", "OPT2")

# NO SHARED SCRATCH ROOT, AND THAT IS A FIX. MEASURED: two invocations of this file ran at
# once against one shared root, and the first beat's `rmtree` deleted the other run's STAGED
# `.tmp.gate.bin` mid-compile -- `ld` answered `open() ... errno=2` and the run reported a gate
# failure that never happened. The recurring harness defect in its purest form: a harness that
# deletes the state under test produces a confident wrong answer, and it did so here while I
# was the one running it. Each `gatekit` COPY now names its own artifact root from its own
# directory (`freeze.py`), so a collision needs two mistakes rather than one, and no lane can
# be handed a root its `gatekit` will not write to.
#
# WHY A LANE'S DIRECTORY IS ITS OWN. `Gate`'s name IS its directory, so two lanes sharing a
# `gatekit` share the state under test and the second lane's "green" baseline would be the
# first lane's leftovers. FIX and OPT2 share `gk2`'s root and are told apart by the renamed
# `Gate` alone, so their beats are INTERLEAVED per gate rather than run as one block and then
# the other. NOW has `gk` to itself.
ART = {"NOW": HERE / "gk" / "gk-artifacts", "FIX": HERE / "gk2" / "gk2-artifacts",
       "OPT2": HERE / "gk2" / "gk2-artifacts"}


def base_file(gate, lane):
    live = harness.ROOT / "gates" / f"{gate}.py"
    frozen = HERE / "frozen-prefix" / f"{gate}.py"
    return (frozen if lane in ("NOW", "OPT2") else live), frozen


def beat(gate, lane, kind):
    """One beat: build the variant, run it, and score what is left. Never deletes anything."""
    src, frozen = base_file(gate, lane)
    # FIX is the LIVE gate and OPT2 the FROZEN one, and BOTH run the REPAIRED library, because
    # the repair is in `gatekit`: a lane on the committed `gk` would be testing nothing. `gk`
    # and `gk2` differ by exactly one line in `Gate.__init__`.
    gk = GK if lane == "NOW" else GK2
    d = ART[lane] / f"{lane.lower()}-{gate}"
    # WHICH FILE IS UNDER TEST, printed rather than implied. A lane that silently ran the
    # wrong file would produce a table that reads like a measurement of the repair.
    which = ("the frozen pre-fix gate" if src == frozen else
             "the LIVE gate, byte-identical to pre-fix" if src.read_bytes() == frozen.read_bytes()
             else "the LIVE gate, EDITED from pre-fix")
    if kind == "green":
        v = harness.variant(src, VAR / f"{lane}-{gate}-green.py", pin="live")
    elif kind == "drift":
        v = harness.variant(src, VAR / f"{lane}-{gate}-drift.py", pin="dead")
    else:
        # pin="live" is REQUIRED here, not decoration. On this tree `mixin-op-gate`'s pin is
        # stale as committed, so a disagree beat that kept it would exit 2 on the drift check
        # and never reach `run()` -- and the control would have measured the drift path twice
        # instead of measuring the inside-of-run() path at all.
        v = harness.variant(src, VAR / f"{lane}-{gate}-disagree.py", pin="live",
                            oracle=f".agents/slop/clearfix/wrong-oracle-{gate}.py")
    # `name=` renames the `Gate`, which IS its directory. NOW and FIX share one `gatekit` and
    # therefore one artifact ROOT, so without this the FIX lane's green baseline would be the
    # NOW lane's leftovers -- a harness that cannot tell whose bytes it is reading.
    v = harness.variant(v, VAR / f"{lane}-{gate}-{kind}.py", name=d.name)
    rc, secs = harness.run_gate(v, gk, ART[lane], d.name, quiet=True)
    return rc, secs, harness.snapshot(d), harness.gate_output(), which, v


def main():
    print("== 0. NOISE, BEFORE THE DISCRIMINATOR IS USED")
    print("   `bend` answers every --check-only, green included, on stderr. Recorded on a")
    print("   HEALTHY run below: anything left after the notice would be `bend` TALKING.")
    print()

    subprocess.run([sys.executable, str(HERE / "freeze.py")], check=True, capture_output=True,
                   cwd=harness.ROOT)          # rebuilds gk/ and gk2/ from HEAD
    for k in set(ART.values()):              # ONCE each, before the first beat
        shutil.rmtree(k, ignore_errors=True)
    green_secs, failures = {}, []

    for gate in GATES:
        harness.build_wrong_oracle(harness.ROOT / "gates" / f"{gate}.py",
                                   HERE / f"wrong-oracle-{gate}.py")
        print(f"== {gate}")
        cells, base, noise = {}, {}, None
        for lane in LANES:
            rc0, s0, snap0, (out0, err0), _, _ = beat(gate, lane, "green")
            base[lane] = snap0
            cells[(lane, "green")] = (rc0, s0, harness.verdict(snap0, snap0))
            if rc0 != 0:
                failures.append(f"{gate}/{lane} A0 green did not exit 0 (rc={rc0})")
            if noise is None:
                # MEASURED BEFORE THE DISCRIMINATOR IS USED, ON STDERR AND ON A HEALTHY RUN:
                # how many bytes are there, and how many survive stripping the notice? A
                # guard that asks "is stderr non-empty" cannot tell a green run from a
                # speaking one, so it discriminates nothing while looking as if it does.
                noise = (len(err0), len(harness.said(err0)))
        for kind, want in (("drift", 2), ("disagree", 1)):
            for lane in LANES:
                if kind == "disagree" and lane == "OPT2":
                    continue                                # the control, once per shape
                rc, secs, snap, (out, err), which, _ = beat(gate, lane, kind)
                cells[(lane, kind)] = (rc, secs, harness.verdict(snap, base[lane]))
                print(f"   lane {lane}: {which}, {harness.sha(base_file(gate, lane)[0])[:12]}")
                said_all = harness.said(err)
                if rc != want:
                    failures.append(f"{gate}/{lane} {kind} exited {rc}, expected {want}; "
                                    f"stderr said {said_all}")
        # THE DISCRIMINATION, asserted rather than asserted-about.
        now = cells[("NOW", "drift")][2]
        if not any(w == "STALE" for w in now.values()):
            failures.append(f"{gate}: NOW/A1 left nothing STALE -- the instrument did not see "
                            f"the bug, so its verdict on FIX/A1 means nothing")
        for lane in ("FIX", "OPT2"):
            if cells[(lane, "drift")][2]:
                failures.append(f"{gate}: {lane}/A1 left {harness.line(cells[(lane,'drift')][2])} "
                                f"-- the fix did not survive the early exit")
        for lane in ("NOW", "FIX"):
            if cells[(lane, "disagree")][2]:
                failures.append(f"{gate}: {lane}/A2 left files -- the control did not move, so a "
                                f"STALE reading on A1 would have meant nothing")
        print(f"   stderr on a HEALTHY run, MEASURED THROUGH THE GATE: {noise[0]} bytes, {noise[1]} line(s)"
              f" after stripping the notice -- and `bend` alone writes 42 bytes of it on EVERY"
              f" invocation, green included, so a guard asking about\n   the GATE's stderr is"
              f" measuring a different thing from a guard asking about bend's.")
        print(f"   artifacts (7, named): {'  '.join(sorted(base['NOW']))}")
        print(f"   A0 green   rc={cells[('NOW','green')][0]}  "
              f"{len(base['NOW'])} files  ({cells[('NOW','green')][1]:.0f}s)")
        print()
        for kind, want in (("green", 0), ("drift", 2), ("disagree", 1)):
            label = {"green": "A0 green    ", "drift": "A1 drift   ",
                     "disagree": "A2 disagree"}[kind]
            print(f"   {label} (want rc={want})")
            for lane in LANES:
                if (lane, kind) not in cells:
                    print(f"     {lane:<5} --")
                    continue
                rc, secs, v = cells[(lane, kind)]
                # A GREEN ROW'S "7/7 STALE" IS NOT A FINDING. The A0 beat compares a run's
                # files against ITSELF (`verdict(snap, snap)`), so every file reads STALE by
                # construction -- two runs of a green gate produce identical bytes. Printing
                # that count in a column headed STALE would score a healthy run as the bug, so
                # the green row reports a FILE COUNT and the red rows report STALE.
                if kind == "green":
                    print(f"     {lane:<5} rc={rc}  {len(v)} files promoted"
                          f"   (identity against itself; NOT a staleness verdict)")
                    continue
                stale = sum(1 for w in v.values() if w == "STALE")
                mark = "" if lane != "NOW" or kind != "drift" else "   <== THE BUG"
                print(f"     {lane:<5} rc={rc}  {stale}/{len(v)} STALE  "
                      f"{harness.line(v)[:80]}{mark}")
            print()
        green_secs[gate] = cells[("NOW", "green")][1]

        # CLAUSE II'S BLIND SPOT, from ITS OWN AST, on the gate FILES it never reads.
        pre, tot, runline, cl = harness.call_site_exits(base_file(gate, "FIX")[0])
        pre_f, _, _, clf = harness.call_site_exits(HERE / "frozen-prefix" / f"{gate}.py")
        print(f"   clause II reads gates/gatekit.py and counts exits INSIDE run(); this gate's")
        print(f"   stranding exit is at line {runline - 6}..{runline - 1}, BEFORE run() at line"
              f" {runline}. Call-site census, denominator {tot} exits:")
        print(f"     pre-fix gate : {pre}/{tot} exits before run(), clears before run()={clf}")
        print(f"     live gate    : {pre}/{tot} exits before run(), clears before run()={cl}")
        print(f"   Both can strand the same 7 files. A clause that reads only the library")
        print(f"   cannot see either number, so it is green or red for a reason unrelated to it.")

    print("== 1. WHAT THE EARLY EXIT COSTS vs WHAT ROUTING IT THROUGH `run()` COSTS")
    print("   Option 1 says to remove the early exit and let the drift path fall through to")
    print("   `run()`. `run()` is three `bend` processes, so that is the price of the refusal.")
    print("   Bounded, and the VERDICT TOKEN is parsed rather than the exit status -- rc 3 is a")
    print("   memory kill and rc 1 is a refusal, and both are non-zero.")
    for label, argv in (("the refusal (drift, pin dead)",
                         [str(VAR / "NOW-mixin-op-gate-drift.py")]),
                        ("a GREEN run of the same gate",
                         [str(VAR / "NOW-mixin-op-gate-green.py")])):
        # PYTHONPATH points at the FROZEN copy. Without it the variant imports `gates/`'s
        # live gatekit and writes into `gates/artifacts/` -- and the first version of this
        # line did exactly that, reporting `rc=1 peak-RSS=2MB` from an ImportError and
        # calling it a measurement. A bounded run is only a measurement if it ran the gate.
        r = subprocess.run([str(harness.ROOT / ".venv" / "bin" / "python"), "checks/bounded.py",
                            "--seconds", "900", "--mb", "2048", "--",
                            str(harness.ROOT / ".venv" / "bin" / "python"), *argv],
                           capture_output=True, text=True, cwd=harness.ROOT,
                           env={**os.environ, "PYTHONPATH": str(HERE / "gk")})
        # BOTH STREAMS, because `checks/bounded.py:140` prints its verdict line to STDOUT
        # while its own failure path prints to stderr, and reading only stdout reported
        # "NO TOKEN" for a run that had in fact completed -- a measurement of the wrong stream
        # looking exactly like a measurement of nothing.
        tok = next((l for l in (r.stdout + r.stderr).splitlines()
                    if l.startswith("[bounded] ")), "NO TOKEN -- the run did not complete")
        print(f"   {label:<30} {tok}")
    print("   And bmn, whose measured peak is 1,531 MB against a 2,048 MB ceiling and which the")
    print("   brief records as a coin flip at that ceiling: routing a 2 MB refusal through three")
    print("   `bend` processes to LEARN the pin moved is not a safety improvement, it is a new")
    print("   way to be killed. Option 1 is therefore rejected on cost, not on taste.")
    print()

    print("VERDICT: " + ("REPRO HOLDS" if not failures else "REPRO DID NOT HOLD"))
    for f in failures:
        print("   " + f)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())