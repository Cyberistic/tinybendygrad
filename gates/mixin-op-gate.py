#!/usr/bin/env python3
"""mixin-op-gate.py -- the Python gate for `tinybendygrad/mixin/op.bend`.

    .venv/bin/python gates/mixin-op-gate.py

WHAT IT GATES, AND THE DENOMINATOR THE VERDICT TRAVELS WITH, because a gate whose scope lives
in a comment is a gate nobody can check.

    36 rows, THREE LANES, and the DENOMINATOR IS 32.
      py    CPython, `.agents/slop/mixin-op-gate.py` -- 32 rows
      bd    the port, interpreted, `./bin/bend tinybendygrad/mixin/op.bend` -- 36 rows
      bn    the port, NATIVE, `bend -o` then run                       -- 36 rows
    32 rows are COMPARED byte for byte across all three lanes.
    4 rows are PORT-ONLY -- `rop_gap`, `exp_cast`, `commit_weak`, `bin_promote` -- and they are
    excluded BY NAME on both sides. The port emits 36 and CPython 32, so the count that is
    compared is 32 and the count that is printed is 32; the 4 are named at the foot of this
    file and their ABSENCE from the oracle is asserted too, because a gate that only checked the
    row would pass the moment CPython grew it and then the exclusion would be hiding a real
    comparison.

EXIT STATUS: 0 all three lanes identical · 1 a warm check failed, a lane took the wrong row
count, the oracle failed, the native compile failed, or the lanes disagree · 2 the frozen
oracle moved. **3 AND 4 ARE NOT VERDICTS AND THIS GATE NEVER RETURNS THEM**; see THE BOUND.

IT IS THE PORT OF `oracles/gateport/oracles/mixin-op-gate.sh`, and the rule the port had to satisfy was that
THE PYTHON REPRODUCES THE SHELL'S VERDICT ON EVERY INPUT OR IT DOES NOT MOVE. The shell body is
frozen verbatim at `gates/oracles/mixin-op-oracle.sh` and still runnable, because that rule
is only checkable while the shell exists; its sha256 is in ORACLE_PIN and is CHECKED IN CODE on
every run, because a pin in a comment is a pin that cannot fail.

WHAT MOVED AND WHAT DID NOT. The shell's lane files went to `/tmp/mop.{py,bd,bn}` and they go to
`gates/artifacts/mixin-op-gate/` now: `.agents/slop/` is being pruned and a gate whose OUTPUT
lives where the tree is clearing is a gate with a shelf life. The shell's `--check-only` was bare
under `set -e`, so a COLD driver ABORTED the gate at that line, and this is `warm="fatal"` for
the same reason -- but `beautiful-mnist-gate.py` ported the other shell, which ran the same
command `|| true`, so the two gates disagree about a cold driver because the two shells did.

THE BOUND, AND WHY IT IS NOT ONE. The shell bounded NOTHING here: `mixin-op-gate.sh:22` is
`./bin/bend ... --check-only` and there is no `alarm` and no `ulimit` in the file. `frombits/gate.sh`
uses `perl -e 'alarm 900'` on its own `bend` calls and that idiom bounds TIME and nothing else.
MEASURED peak RSS for this gate: 1,368 MB for the whole shell run. So a ceiling has to be chosen
and this gate does NOT choose one, because ANY ceiling is a verdict: `checks/bounded.py` returns
3 when it kills on memory and 4 when it kills on time, and neither is the status the shell's
lanes would produce, so bounding here would be a verdict change dressed as a safety improvement.
A ceiling ABOVE the measured maximum changes nothing on this tree and a ceiling BELOW it changes
the gate, and 1,368 MB is the number a later decision needs. TODO(GXR-12): run this gate under
`checks/bounded.py` at 2048 MB -- the substrate ceiling, above the measured maximum -- or do not
bound it at all. Half-measures here are how a gate learns to report green having run nothing.

ONE BEND AT A TIME. MEASURED 2026-10-05 on this machine: `sz.bend` peaks at 1,468 MB and
`renderer/nir.bend` at 1,435 MB, and two of those concurrently take the memory to zero. This
gate runs its three lanes in sequence and never in parallel, and `gates/README.md` says the same
about every gate in this directory.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, oracle_drift

# THE FROZEN SHELL ORACLE, PINNED IN CODE, AND CHECKED ON EVERY RUN. Same shape and same reason
# as `checks/substrate.py`'s ORACLE_PIN. The hash is of the ORACLE COPY, which is a byte-for-byte
# copy of the committed body -- no `*_ROOT` edit is needed here, because the copy sits at the same
# depth below the repo root and the copy's own `cd "$(dirname "$0")/../.."` therefore resolves
# into whichever tree it is run from. THAT IS WHAT MAKES IT USABLE AS A PLANT ORACLE:
# `checks/e2epy` and `lintable-gate.sh` both record that a $TMPDIR copy one level shallower
# cannot resolve a relative import, and this copy is at the same level.
ORACLE_PIN = {
    "gates/oracles/mixin-op-oracle.sh":
            # RE-FROZEN 2026-10-06. THE PIN NAMED `178cf5f74e92`, WHICH WAS CORRECT AT
    # `2f4ffc7a0` AND STOPPED BEING CORRECT WHEN **MY OWN** REPOINTING REWRITE CHANGED THE
    # SHELL'S BYTES IN `558b4c3a5`/`cf2d14fa4` WITHOUT RE-FREEZING. **BOTH EXTANT COPIES ARE
    # BYTE-IDENTICAL AT `e8792d0ff1ad`** (`.agents/slop/mixinop/` AND `oracles/gateport/oracles/`),
    # SO THE FILE IS CONSISTENT AND ONLY THE PIN WAS STALE.
    # **THIS IS THE SAME FAILURE AS THE `checks/e2e.py` PIN FIRING ON A TODO *COMMENT*: A PIN
    # GUARDS A FILE, AND ANY EDIT TO THAT FILE MUST MOVE THE PIN IN THE SAME COMMIT.**
    "e8792d0ff1ad9d1a0a6e11aae6b4d52b135ea6c5664dd05510cae868b834e0c6",
}

GATE = Gate(
    "mixin-op-gate",
    bend="tinybendygrad/mixin/op.bend",
    oracle=".agents/slop/mixin-op-gate.py",
    rows=36,
    compared=32,
    # THE FOUR, BY NAME, AND WHY BY NAME. These name a refusal or a defect rather than a graph,
    # so CPython cannot be asked for them; filtering by POSITION instead would drop whatever row
    # happens to sit fourth today and silently compare something else tomorrow.
    port_only=["rop_gap", "exp_cast", "commit_weak", "bin_promote"],
)

if __name__ == "__main__":
    if bad := oracle_drift(ORACLE_PIN):
        for line in bad:
            print(f"ORACLE DRIFT: {line}", file=sys.stderr)
        print("  the frozen shell oracle moved, so this run would compare against nothing. "
              "Restore it, or re-freeze it deliberately and update ORACLE_PIN -- do not delete "
              "the pin.", file=sys.stderr)
        sys.exit(2)
    ok = GATE.run() == 0
    # THE SHELL'S OWN LINES. `--check-only`'s stdout goes through to the reader in the shell,
    # because the shell does not capture it, and dropping it would make this artifact differ
    # from the oracle on the green path for no reason a reader could name.
    print(GATE.warm_out, end="" if GATE.warm_out.endswith("\n") else "\n")
    print(f"mixin-op-gate: {GATE.compared} shared rows, 3 lanes identical"
          if ok else "mixin-op-gate: FAILED")
    sys.exit(0 if ok else 1)
