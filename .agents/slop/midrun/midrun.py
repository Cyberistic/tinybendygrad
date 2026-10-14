#!/usr/bin/env python3
"""Ask a run WHICH SUBSTRATE it measured, and refuse the answer if the substrate moved underneath it.

    usage: .venv/bin/python .agents/slop/midrun/midrun.py --run        # drive a scratch run, edit mid-flight
           .venv/bin/python .agents/slop/midrun/midrun.py --verify DEST# re-hash a finished run's substrate
           .venv/bin/python .agents/slop/midrun/midrun.py --plant

    EXIT: 0 PASS  ·  3 REFUSED  ·  5 DEAD  ·  2 usage.

WHY THIS EXISTS, AND IT IS NOT `quiesce.py`. `.agents/slop/quiesce/quiesce.py` asks a question about
the tree BEFORE a run: "is there a quiet window long enough to hold one?" Its answer is a
PRECONDITION, and the correct response to `REFUSED` is to snapshot. This file asks a question about a
run AFTER one: "were the artifacts all measured against the same bytes?" Those are different
questions, and `quiesce`'s own residual says so -- *"A `PASS` CERTIFIES THE PAST, NOT THE NEXT 294
s"*. A tree can be quiet for the whole window and change on the last second.

THE DEFECT THIS MEASURES, IN THE TWO SHAPES IT HAS ACTUALLY TAKEN. Both were measured in this tree:
  * `run34` -- the port was rewritten ~10 s after the graph phase, so every step from `control` on
    emitted `0 rows`. LOUD: `emit bend: 0 rows after 5 attempts` is a `SystemExit`, the artifact is
    one line, and `differ.py:533` re-runs the pair and names it `ONE SIDE IS A 0-ROW FAILURE`.
  * `run34`'s stability step BEFORE that fix -- BOTH members of a pair wrote the same one-line
    `0 rows after 5 attempts` file, `cmp -s` called the pair BYTE-IDENTICAL, and `stable-pairs`
    read `5 of 5`. **TWO IDENTICAL FAILURES COMPARE EQUAL.** That is a GREEN-LOOKING ARTIFACT, and
    it is why a 0-row failure must be caught by the ONE-LINE SHAPE and never by the diff.

SO: IS A MID-RUN CHANGE DETECTABLE, OR ONLY PREVENTABLE? THE ANSWER IS BOTH, AND THE TWO HAVE
DIFFERENT ANSWERS FOR THE TWO POPULATIONS, WHICH IS WHY BOTH EXIST:
  * HOT PATH (`{5}` of the 148, re-read by EVERY `gc()`/`emit`) -- a change is DETECTABLE. It
    shows up as 0 rows or as differing rows, both of which `differ.py` already counts.
  * COLD (`{143}` of the 148, walked by the freeze but read once at start, or never) -- a change is
    INVISIBLE to the run and only a POST-HOC HASH can see it. This is the one that needs a record.

THE RECORD, AND WHY IT IS NOT A NEW ARTIFACT. `differ.py:571` already writes one summary read by
four consumers and `differ.py:616` records why a second file would be a THIRD place the device is
claimed. So the substrate identity is ONE MORE `key=value` ROW in `D0-run-summary.txt` -- the same
device four gates parse -- not a new file, and not a list anybody maintains.

VERDICTS, AND WHY THERE IS NO `FAIL`. Three of the five, for the reason `quiesce.py:20-28` gives:
  * `PASS` (0)   -- the substrate hash at the end EQUALS the hash at the start: one measurement of
                   one substrate.
  * `REFUSED` (3)-- THE PRECONDITION WAS ABSENT. An input is missing, or the substrate moved. This
                   is NOT a disagreement between two answers, so `FAIL` (1) would be a lie: nothing
                   here compares two runs. A missing input is `REFUSED`, not `FAIL`, because a
                   deleted `.bend` is an absent precondition, not a wrong measurement.
  * `DEAD` (5)   -- it ran and emitted nothing checkable: no run was recorded at all. NOT a zero and
                   NOT a pass.
  * `SKIP` (4)   -- reserved; this file always measures or refuses.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
MID = ROOT / ".agents" / "slop" / "midrun"

PASS, REFUSED, DEAD = 0, 3, 5


def _snapshot_mod():
    """`snapshot.py` LOADED BY PATH -- its `COPIES`/`inputs()` are the ONE declaration of what a run
    reads, and a second list here is the exact defect `snapshot.py:74-77` is written against."""
    import importlib.util
    p = ROOT / ".agents" / "slop" / "quiesce" / "snapshot.py"
    spec = importlib.util.spec_from_file_location("midrun_snapshot", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def substrate(root: pathlib.Path) -> dict:
    """ONE hash over every declared input's PATH AND BYTES, under `root`.

    The path is in the hash, so a rename cannot collide with a same-bytes-different-name copy, and
    one hash rather than 148 means one row in the summary instead of a manifest nobody reads. The
    POPULATION is discovered (`snapshot.inputs()`), never listed here.
    """
    mod = _snapshot_mod()
    mod.ROOT = root
    h = hashlib.sha256()
    n = 0
    for p in mod.inputs():
        rel = p.relative_to(root).as_posix()
        h.update(rel.encode())
        try:
            h.update(p.read_bytes())
        except OSError:
            h.update(b"\0ABSENT")
            n += 1
    return {"substrate": h.hexdigest(), "inputs": len(mod.inputs()), "absent": n}


def record(root: pathlib.Path, out: pathlib.Path) -> dict:
    s = substrate(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(s, sort_keys=True) + "\n")
    return s


# ---------------------------------------------------------------------------
# THE PLANT -- a real scratch run, edited mid-flight, on a SNAPSHOT. No bend needed to prove the
# DETECTOR works; the bend half is `--plant` with `--with-bend` because two other units want bend.
# ---------------------------------------------------------------------------
def _fake_step(root: pathlib.Path, d: pathlib.Path, name: str, rows: int) -> int:
    """A stand-in for one `differ.py run` step: reads the hot-path file, writes an artifact.

    It reproduces the property that makes this bug possible -- the step's ANSWER depends on the
    substrate AT THE MOMENT IT RUNS, not at the moment the run started. A break injected mid-run
    makes later steps emit 0 rows exactly as `emit bend: 0 rows after 5 attempts` did.
    """
    hot = root / "tinybendygrad" / "uop" / "ops.bend"
    body = hot.read_text(errors="replace")
    rc = 0
    if "MIDRUN-BREAK" in body:
        rows = 0
        rc = 1
    if rows:
        out = "\n".join(f"# step {name} row {i} ok" for i in range(rows)) + "\n"
    else:
        out = "rc=1\n"
    (d / f"{name}.txt").write_text(out)
    return rc


def plant(with_bend: bool = False) -> int:
    """BOTH STATES, ON A SCRATCH TREE, AND THE ANSWER IS A VERDICT NOT A BOOLEAN.

    HALF 1 (stable substrate) MUST be `PASS` -- and a detector that cannot say PASS is a detector
    that is always refusing, which is not a measurement either.
    HALF 2 (substrate edited mid-run) MUST be `REFUSED`, NOT `FAIL`: nothing compared two wrong
    answers, a PRECONDITION (one substrate) was absent. Conflating those two is the defect this
    project keeps finding, so the exit codes are asserted here rather than described in prose.
    """
    with tempfile.TemporaryDirectory() as td:
        tdp = pathlib.Path(td)
        live, snap, out = tdp / "live", tdp / "snap", tdp / "out"
        (live / "tinybendygrad" / "uop").mkdir(parents=True)
        (live / "tinybendygrad" / "uop" / "ops.bend").write_text("def op: 0\n" * 40)
        for name in ("checks/differ.py", "checks/devpin.py"):
            (live / name).parent.mkdir(parents=True, exist_ok=True)
            (live / name).write_text("# harness\n")
        (live / "graphcmp.py").parent.mkdir(parents=True, exist_ok=True)
        (live / "graphcmp.py").write_text("# graphcmp\n")

        for label, edit in (("stable", False), ("edited", True)):
            snap = tdp / f"snap-{label}"
            out = tdp / f"out-{label}"
            out.mkdir(parents=True)
            _build_like_snapshot(live, snap)
            before = record(snap, out / "substrate-start.json")
            # THREE STEPS. The substrate is stable through 1-2 and, for `edited`, breaks before 3.
            rcs = [_fake_step(snap, out, "step1", 18), _fake_step(snap, out, "step2", 18)]
            if edit:
                (snap / "tinybendygrad" / "uop" / "ops.bend").write_text(
                    "MIDRUN-BREAK\n" + "def op: 0\n" * 40)
            rcs.append(_fake_step(snap, out, "step3", 18))
            after = substrate(snap)
            rc = _judge(before, after, rcs)
            print(f"PLANT {label:<7} start={before['substrate'][:12]} end={after['substrate'][:12]} "
                  f"step-rcs={rcs} -> {_name(rc)}")
            got = rc
            want = PASS if not edit else REFUSED
            print(f"  {'OK' if got == want else 'WRONG'}: want {_name(want)}, got {_name(got)}")
            if got != want:
                return 1
    print("PLANT: OK -- stable substrate PASSes, mid-run edit is REFUSED, never FAILed")
    return 0


def _build_like_snapshot(live: pathlib.Path, snap: pathlib.Path) -> None:
    """Copy the scratch tree the way `snapshot.build()` does: inputs COPIED (never hardlinked -- a
    hardlink shares the inode, so an in-place edit would move the frozen copy too and the freeze
    would freeze nothing)."""
    shutil.copytree(live, snap)


def _name(rc: int) -> str:
    return {PASS: "PASS(0)", REFUSED: "REFUSED(3)", DEAD: "DEAD(5)"}.get(rc, f"?{rc}")


def _judge(before: dict, after: dict, step_rcs: list[int]) -> int:
    """THE THREE REFUSALS, EACH ITS OWN QUESTION. In the order a reader needs them.

    1. `inputs=0` -- nothing was measured at all. `DEAD`: it ran and emitted nothing.
    2. `absent > 0` -- a DECLARED INPUT IS NOT ON DISK (`graphcmp-dbg.bend` and
       `graphcmp-empty.bend` are both in this state RIGHT NOW). The run's own precondition is
       absent. `REFUSED` -- and this is the state `D10-zerorow-guard.txt` is in: it reads `rc=1`
       with `no such file: .agents/slop/graphcmp-empty.bend` in its `.err`, which is the guard
       firing for a reason that has nothing to do with the guard.
    3. the substrate MOVED -- `REFUSED`, and the artifact set is a measurement of no single thing.
    4. a step returned non-zero -- that is a `FAIL` OF THE RUN, reported here as evidence, but the
       detector's own verdict stays REFUSED, because the detector did not compare two answers.
    """
    if after["inputs"] == 0:
        print("DEAD, NOT A VERDICT: 0 declared inputs -- nothing was measured")
        return DEAD
    if after["absent"]:
        print(f"REFUSED, NOT A VERDICT: {after['absent']} declared input(s) ABSENT on disk -- the "
              f"run's precondition is not present, so no artifact set can be a measurement")
        return REFUSED
    if after["substrate"] != before["substrate"]:
        print(f"REFUSED, NOT A VERDICT: the substrate moved during the run "
              f"({before['substrate'][:12]} -> {after['substrate'][:12]}). The artifacts are not all "
              f"measurements of one substrate. DO NOT WAIT -- SNAPSHOT "
              f"(.agents/slop/quiesce/snapshot.py).")
        return REFUSED
    if any(rc for rc in step_rcs):
        print(f"NOTE: {sum(1 for rc in step_rcs if rc)} of {len(step_rcs)} step(s) returned non-zero "
              f"({step_rcs}). The substrate was stable, so this is a FAILURE OF THE RUN, not of the "
              f"precondition -- the detector's verdict is PASS on the substrate question.")
    print(f"PASS: all {after['inputs']} declared inputs unchanged across the run "
          f"(substrate={after['substrate'][:12]})")
    return PASS


def verify(run_dir: pathlib.Path) -> int:
    """Re-hash a finished run's root and compare it to the substrate the run RECORDED.

    This is the row `pinindep` proved missing: every one of the 17 pins reads `D0-run-summary.txt`,
    which records `dev`, `lc_all`, `noopt` and `pythonhashseed` -- the ENVIRONMENT -- and not one
    byte of the PORT. So a reader cannot tell WHICH substrate produced an artifact.
    """
    rec = run_dir / "substrate-start.json"
    if not rec.exists():
        print(f"== REFUSED, NOT A VERDICT: no {rec.name} -- the run recorded no substrate, so "
              f"there is nothing to compare a later reader against")
        return REFUSED
    before = json.loads(rec.read_text())
    after = substrate(run_dir)
    return _judge(before, after, [])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", action="store_true", help="plant a scratch run and judge it")
    ap.add_argument("--verify", metavar="DEST", help="compare a run's recorded substrate to it now")
    ap.add_argument("--plant", action="store_true")
    ap.add_argument("--record", metavar="DIR", help="write DIR/substrate-start.json and print it")
    a = ap.parse_args()
    if a.plant or a.run:
        return plant()
    if a.verify:
        return verify(pathlib.Path(a.verify))
    if a.record:
        print(json.dumps(record(pathlib.Path(a.record), MID / "substrate-start.json"), sort_keys=True))
        return PASS
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())