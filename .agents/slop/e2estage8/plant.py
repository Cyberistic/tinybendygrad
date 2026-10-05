#!/usr/bin/env python3
"""PLANT AND DISARM FOR THE STAGE-8 RETIREMENT AND FOR THE ORACLE PIN.

    usage: .venv/bin/python .agents/slop/e2estage8/plant.py

NO `bend`, NO `node`, NO `cc`: every arm here is a text edit and a census over a stored transcript,
because a plant that needs the substrate is a plant that cannot tell a retirement from an outage.
Each arm states what it plants, the string it expects to see, and the exit status it must produce.

THE FIRST ATTEMPT AT THIS FIX BUILT THESE PLANTS AND NEVER MADE THE FIX: `.agents/slop/e2efix/`
left a 398-byte stub report, six unanswered deliverables, and a `plant8.cpython-312.pyc` with no
source, whose own expectation string was `RETIRED`. **A PLANT IS NOT A FIX, AND A `.pyc` IS NOT A
SOURCE.** So every arm below plants into a TEMPORARY COPY and asserts against the census, and the
shipped `checks/e2e.py` is only ever READ.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop/e2estage8"
GATE, VERDICTS = ROOT / "checks/e2e.py", HERE / "verdicts.py"
PRE = HERE / "artifacts/pre.port.out"   # a real 8-stage run, taken BEFORE the retirement
# THE CONTROL TRANSCRIPT IS A PLANT'S, NOT A TRANSCRIPT I WROTE: `plant-pass` is a real seven-stage
# run in which every stage printed its denominator, produced by `.agents/slop/e2epy/diff.py`, whose
# stubs print those lines on purpose. A hand-written transcript would prove only that the census can
# parse text I typed.
GREEN = ROOT / ".agents/slop/e2epy/artifacts/plant-pass.port.out"


def census(transcript: Path, gate: Path) -> tuple[int, str]:
    """`(exit status, stdout)` of the census over one transcript and one gate. The gate is passed by
    path precisely so a plant can be handed a COPY with the defect planted in it."""
    p = subprocess.run([sys.executable, str(VERDICTS), str(transcript), str(gate)],
                       capture_output=True, text=True, cwd=ROOT)
    return p.returncode, p.stdout + p.stderr


def arm(name: str, want_rc: int, want: str, gate: Path, transcript: Path = PRE) -> bool:
    rc, out = census(transcript, gate)
    ok = rc == want_rc and want in out
    print(f"  {'OK  ' if ok else 'FAIL'} {name:<40} rc={rc} (want {want_rc})")
    for ln in out.splitlines():
        if want in ln:
            print(f"         {ln}")
    if not ok:
        print(f"         *** expected a line containing: {want}")
    return ok


def planted(mutate) -> Path:
    """A COPY of the gate with `mutate` applied, so the shipped file is never written by a plant.

    **THE MUTATED TEXT MUST BE THE TEXT WRITTEN, AND THE FIRST CUT WROTE BACK THE ORIGINAL.** Every
    arm then "passed" for the wrong reason: the shipped gate, against the same transcript, already
    produces the string each arm expected. That is `RECOVERED.md` §7's trap exactly -- *a positive
    control that patched nothing is the one failure this gate cannot have* -- so the difference is
    asserted here rather than trusted."""
    tmp = Path(tempfile.mkdtemp(prefix="e2estage8-")) / "e2e.py"
    shutil.copy(GATE, tmp)
    before = tmp.read_text()
    after = mutate(before)
    assert after != before, "the plant changed nothing: a plant that changes nothing is a no-op"
    tmp.write_text(after)
    return tmp


def resurrect8(t: str) -> str:
    """THE DEFECT THIS FIX EXISTS TO KILL, verbatim in shape: `RETIRED` in the PROSE and stage 8
    emitted at the CODE line. Re-insert the emission -- the one line the retirement deleted."""
    anchor = '    say(f"--- verdicts: {FAILS} failed, {SKIPS} skipped ---")'
    assert anchor in t, "the retirement deleted the summary line too, which is not this plant's bug"
    return t.replace(anchor, f'    say("== 8/8 the JS dtype LANE under node")\n{anchor}')


def prose_says_live(t: str) -> str:
    """THE SAME DISAGREEMENT FROM THE OTHER SIDE, which is what a future re-pointing attempt
    produces: the PROSE claims stage 8 is live again and the CODE never brought it back. The census
    keys on the word `RETIRED`, so the plant must remove that word, not merely move it."""
    assert "**RETIRED" in t, "the prose row no longer says RETIRED, so this plant no longer plants"
    return t.replace("**RETIRED", "**LIVE, AND RE-POINTED AT")


def disarm(t: str) -> str:
    """A change that must NOT move the verdict: reword the retirement record. Without this arm a
    census that fails on any edit is a change-detector, and change-detector tests are harmful."""
    return t.replace("# STAGE 8, THE JAVASCRIPT LANE. RETIRED, NOT RE-POINTED, BECAUSE ITS",
                     "# Stage 8, the JavaScript lane: retired, not re-pointed, because its")


def main() -> int:
    print("PLANT AND DISARM -- the stage-8 retirement, and the oracle pin")
    bad = [
        # THE SHIPPED STATE, against a transcript that still has 8 stages: the gate and its own
        # artifact disagree, and that disagreement is what a reader would be misled by.
        arm("shipped, against an 8-stage run", 1,
            "CODE emits [] this transcript does not contain, and [8]", GATE),
        arm("PLANT prose says RETIRED, code emits stage 8", 1,
            "PROSE says [8] is RETIRED and this transcript contains it", planted(resurrect8)),
        arm("PLANT prose says LIVE, code has retired it", 1,
            "PROSE names [8] the CODE does not emit", planted(prose_says_live)),
        arm("DISARM a reworded retirement record", 1,
            "stage 8: DENOMINATOR 0", planted(disarm)),
        # THE CONTROL, AND IT IS WHAT MAKES THE FOUR ARMS ABOVE MEAN ANYTHING: a census that can only
        # exit 1 cannot distinguish a retirement from an outage. `plant-pass` is a REAL seven-stage
        # run whose every stage printed its denominator, so the whole census must PASS on it -- and
        # it is the LIVE tree's transcript that cannot do this today, for reasons that are three
        # deleted fixtures and not this retirement (see the report).
        arm("CONTROL 7 stages, 7 denominators, 3 agree", 0,
            "7 stage(s) emitted, 1 retired", GATE, GREEN),
    ]
    # THE PIN, PLANTED BY DELETING THE FROZEN ORACLE IN A TREE OF ITS OWN. `checks/e2e.py` resolves
    # its pin against `REPO`, the parent of its OWN `__file__`, so a copy of the gate in an otherwise
    # empty tree finds no oracle -- which is what a lost frozen oracle looks like from inside the
    # gate, and it must exit 3 BEFORE running a single stage. A pin nothing has ever seen fail is a
    # pin in a comment; `checks/differ.py` shipped one.
    box = Path(tempfile.mkdtemp(prefix="e2estage8-pin-"))
    (box / "checks").mkdir()
    shutil.copy(GATE, box / "checks/e2e.py")
    p = subprocess.run([sys.executable, str(box / "checks/e2e.py")], capture_output=True, text=True,
                       cwd=ROOT)
    pin_ok = p.returncode == 3 and "oracle-e2e.sh: MISSING" in p.stderr
    print(f"  {'OK  ' if pin_ok else 'FAIL'} {'PLANT the frozen oracle gone':<34} rc={p.returncode} "
          f"(want 3)")
    if not pin_ok:
        print(f"         {p.stderr.strip()[:160]}")
    bad.append(pin_ok)
    print(f"--- {sum(bad)} of {len(bad)} arm(s) behaved as required")
    return 0 if all(bad) else 1


if __name__ == "__main__":
    sys.exit(main())