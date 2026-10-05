#!/usr/bin/env python
"""IS THE STALE-ARTIFACT BUG ALIVE? Runs ONE repro against TWO gatekits and prints both.

    .venv/bin/python .agents/slop/stalefix/stale-repro.py            # both sides
    .venv/bin/python .agents/slop/stalefix/stale-repro.py old        # one side

THE CLAIM UNDER TEST, verbatim from `lost/RECOVERED.md` §2:

  > A FAILED GATE RUN LEFT THE PREVIOUS RUN'S `bd.txt` IN PLACE, SO A DIFF AFTER A RED RUN
  > DIFFED THE LAST *GREEN* RUN. Same shape as `bend -o` leaving the previous exe.

So the instrument is not "does the gate fail" -- a gate is SUPPOSED to fail. The instrument is
**what the artifact directory holds after the red run**, and every scenario here is therefore
built in the same three beats:

    1. a GREEN run, so the directory holds a complete, correct, previous-run output set;
    2. the same gate with ONE input broken, so the run goes RED;
    3. a listing of what is still on disk, split into STALE (byte-identical to beat 1, so a
       reader would diff the last green run), FRESH (written by the red run, which is
       harmless), and TEMP (a dot-file a staging fix left behind, which is the bug the lost
       unit's FIRST fix had and its own scenario 2 caught).

A LEFTOVER COUNT IS NOT THE CLAIM, and neither is "the gate exited 1". A red run that leaves
its OWN fresh bytes behind is correct behaviour; a red run that leaves the PREVIOUS run's bytes
is the failure. Beat 1 exists so beat 3 can say WHICH, by content and not by count.

WHY TWO SCENARIOS, NOT ONE. The first fix at this bug staged the lanes and promoted them on the
success path only, and it PASSED scenario 1 -- a mid-run failure never reaches the promote. It
left a staged temp behind in scenario 2, where the failure comes after the staging. One
scenario proves one exit path; the two red runs below fail at two different points on purpose.

WHY A SYNTHETIC FIXTURE. The real drivers measure real graphs and peak at 1,368 / 1,531 / 734 MB,
and `sz.bend` at 1,468 MB. This one prints three rows, typechecks in a tenth of a second and
compiles to a 177 MB binary, so the matrix below costs seconds and can be re-run by hand. It is
NOT a weaker test: the bug is entirely about WHERE BYTES LAND, which a three-row fixture
reproduces exactly.

WHY BOTH MODULES ARE LOADED RATHER THAN THE FIX BEING PROVED BY INSPECTION. `gatekit-old.py` is a
frozen copy of `gates/gatekit.py` as it stood when this repro was written, byte for byte, so the
OLD column is the live tree and the NEW column is the working tree after the fix. Both are
loaded by path with `importlib` because `Gate` reads `BEND`, `PY` and `ART` from module globals
at call time; those three are re-pointed per side and nothing else is patched. `_resolve()` is
unaffected, because both inputs are given as ABSOLUTE paths, which it returns unchanged.

EXIT. 0 when the NEW side matches the claim and the OLD side does not -- i.e. when the repro
still discriminates. 1 otherwise, INCLUDING when the bug is gone from both sides, because a
repro that cannot tell the two apart is not evidence.
"""
import contextlib
import hashlib
import importlib.util
import io
import shutil
import sys
import time
from pathlib import Path

FIX = Path(__file__).resolve().parent
ROOT = FIX.parent.parent.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
SCRATCH = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/stalefix-repro")

GREEN = (FIX / "green.bend", FIX / "oracle.py")
# a DETERMINISTIC type error. MEASURED: `bend --check-only` answers rc=1 with 0 bytes on stdout
# and `SOME PROOFS FAIL / Error: / - expected : a defined name` on stderr. That is the shape the
# old flake guard could not tell apart from `bend`'s machine-stack flake.
TYPED = (FIX / "broken.bend", FIX / "oracle.py")
# the driver is fine and the ORACLE is short by one row, so the failure is the row count --
# AFTER the warm check, the oracle lane, both port lanes and the native compile.
SHORT = (FIX / "green.bend", FIX / "oracle-short.py")

SCENARIOS = [
    ("S0 green   ", GREEN, True,
     "no defect. Proves the FIX IS NOT A VERDICT CHANGE: both sides must still pass here, and "
     "must still publish the same seven artifacts."),
    ("S1 typeerr ", TYPED, False,
     "fails in `_warm`, before any lane. Nothing of this run reaches disk, so EVERY leftover is "
     "the previous green run's."),
    ("S2 shortrow", SHORT, False,
     "fails on the row count, after every lane wrote. The `.sub` files are never reached, so "
     "they keep the previous run's bytes while `py.txt` already holds this run's."),
]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def snapshot(d):
    """name -> sha256 for every FILE in the directory. `Path.exists()` follows symlinks, so
    this asks `is_file()` on a walked name and never calls `exists()` on the entry."""
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(d.iterdir()) if p.is_file()} if d.is_dir() else {}


def run_gate(mod, art, bend, oracle, wipe=True):
    """One `Gate.run()`, with `_say`'s stderr captured.

    `wipe=False` is the beat that MATTERS: the second run of a scenario must find the first
    run's artifacts exactly as the first run left them. An earlier version of this harness
    emptied the directory here, which deleted the previous run's output before the gate could
    fail over it -- and the bug under test is precisely that the gate leaves it behind. A repro
    that removes the state it is measuring reports the bug absent in both columns.
    """
    if wipe:
        shutil.rmtree(art, ignore_errors=True)
    art.mkdir(parents=True, exist_ok=True)
    mod.ART, mod.BEND, mod.PY = art, BEND, PY
    gate = mod.Gate("repro", bend=str(bend), oracle=str(oracle), rows=3)
    err = io.StringIO()
    t0 = time.monotonic()
    with contextlib.redirect_stderr(err):
        rc = gate.run()
    return rc, err.getvalue().strip(), time.monotonic() - t0


def side(label, mod, art):
    print(f"--- {label} ---")
    checks = []
    for name, (bend, oracle), green_run, why in SCENARIOS:
        rc, msg, dt = run_gate(mod, art, bend, oracle)
        left = snapshot(art / "repro")
        if green_run:
            checks.append([rc == 0, len(left) == 7,
                           not any(n.startswith(".tmp.") for n in left), True])
            print(f"{name} rc={rc}  {dt:5.2f}s  LEFT={'|'.join(sorted(left)) or 'NOTHING'}")
            print(f"{'':9} {why}")
            continue
        # THE THREE BEATS. A green run first, so `stale` means something: STALE is byte-identical
        # to a complete correct previous run, and that is the state a diff after a red run reads.
        run_gate(mod, art, *GREEN)
        before = snapshot(art / "repro")
        rc, msg, dt = run_gate(mod, art, bend, oracle, wipe=False)
        left = snapshot(art / "repro")
        stale = sorted(n for n, h in left.items() if before.get(n) == h)
        fresh = sorted(n for n in left if n not in stale)
        temp = sorted(n for n in left if n.startswith(".tmp."))
        checks.append([rc == 1, not left, not left, not temp])
        print(f"{name} rc={rc}  {dt:5.2f}s")
        print(f"{'':9} said: {msg.splitlines()[-1] if msg else '(nothing)'}")
        print(f"{'':9} LEFT={'|'.join(sorted(left)) or 'NOTHING'}")
        print(f"{'':9} STALE the last GREEN run's bytes={'|'.join(stale) or 'NOTHING'}")
        print(f"{'':9} FRESH this RED run's bytes={'|'.join(fresh) or 'NOTHING'}")
        print(f"{'':9} TEMP left by a staging fix={'|'.join(temp) or 'NOTHING'}")
        print(f"{'':9} {why}")
    # A side passes only if EVERY scenario matched, and the red scenarios additionally held the
    # two things the fix promises: the directory is EMPTY and no staged temp survived.
    return all(all(c) for c in checks), checks


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else "both"
    shutil.rmtree(SCRATCH, ignore_errors=True)
    sides = [("NEW gates/gatekit.py", ROOT / "gates" / "gatekit.py", SCRATCH / "new"),
             ("OLD gatekit-old.py", FIX / "gatekit-old.py", SCRATCH / "old")]
    if want != "both":
        sides = [s for s in sides if s[0].startswith(want.upper())]
    print("# the claim: a FAILED run must leave no previous run's bytes behind, and must not\n"
          "# leave a staged temp either.  A gate is SUPPOSED to fail; the question is the disk.\n")
    done = [(label, *side(label, load(f"gatekit{i}", path), art))
            for i, (label, path, art) in enumerate(sides)]
    print("\n  side                     S0 rc=0  S0 7 files | red rc=1  red EMPTY  red no-TEMP  "
          "VERDICT")
    for label, ok, checks in done:
        red = checks[1:]
        cells = [checks[0][0], checks[0][1]]
        cells += [all(c[i] for c in red) for i in (0, 1, 3)]
        print(f"  {label:24}" + "".join(f"{'yes':>11}" if v else f"{'NO':>11}" for v in cells)
              + f"  {'holds the claim' if ok else 'REPRODUCES THE BUG'}")
    if len(done) < 2:
        print("\n# one side only -- the discriminating comparison needs both")
        return 0
    new_ok = next(ok for label, ok, _ in done if label.startswith("NEW"))
    old_ok = next(ok for label, ok, _ in done if label.startswith("OLD"))
    verdict = new_ok and not old_ok
    print("\n# VERDICT: "
          + ("DISCRIMINATES -- the fix holds and the old code does not" if verdict
             else "DOES NOT DISCRIMINATE -- read the columns above"))
    return 0 if verdict else 1


if __name__ == "__main__":
    sys.exit(main())
