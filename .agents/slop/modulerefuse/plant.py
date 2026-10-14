#!/usr/bin/env python3
"""PLANTS FOR THE GATES THAT CAN BE PLANTED, BOTH DIRECTIONS, PROVED NOT VACUOUS.

    .venv/bin/python .agents/slop/modulerefuse/plant.py

WHAT CAN BE PLANTED, MEASURED BY `restore.py`:
  nl-gate-noguard.py   AGREES with its subject restored  -> GREEN is reachable
  nl-gate.py           AGREES with its subject restored  -> GREEN is reachable
  rn-gate.py           rc=1, and the lane failure is BEND, not a disagreement
  gate.py              NOTHING RESTORABLE -- `checks/drive.mjs` has NO BLOB in ANY REF
  hermetic-census.py   NOTHING RESTORABLE -- `isolate.py` has no blob where the gate looks

**THE SUBJECT IS RESTORED, NEVER PLANTED.** A plant that supplies its own oracle would be testing
a fixture, not the gate; and a plant whose fixture is a row name the gate never emits proves
nothing -- `zerogate`'s own disclosure, and the reason this file asserts TWO DIRECTIONS and one
VACUOUSNESS PROBE rather than one green run.

THE VACUOUSNESS PROBE, AND IT IS THE POINT OF THE FILE. `nl-gate-noguard.py:96-100` compares
`set(pr) & set(orr)`, so a lane with NO shared names compares NOTHING and `not disagree` is
vacuously true: MEASURED above, with the oracle restored but its output empty, it printed
`gated 0   agree 0   disagree []` and `AGREE`, rc 0. **That is a gate exiting 0 having measured
nothing, which `AGENTS.md` calls worse than no gate because it is trusted.** So every plant here
asserts the DENOMINATOR, not the verdict: a green that gated 0 rows is a FAIL of this harness even
though it is a PASS of the gate. `zerogate` disclosed two first plants that were green-only and
proved nothing; this is the same failure caught by construction rather than by luck.

THE REFUSAL DIRECTION IS PLANTED TOO, and it is the one that was missing: with the subject ABSENT
each gate answers rc=3 and names the path. Asserted against the live tree, so it is a measurement
rather than a claim.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 600

SUBJECT = ".agents/slop/nl/nl-oracle.py"
REV = "371cc64c9^"
PLANTABLE = ["checks/nl-gate-noguard.py", "checks/nl-gate.py"]

# THE DENOMINATOR ROW. `gated N` with N=0 is agreement over nothing, so it is scored a FAIL of
# THIS HARNESS however green the gate is. The number is PARSED, never assumed: a plant that
# asserts a hardcoded 205 would keep passing after the row set changed, which is
# `zerogate`'s second bad plant wearing a different hat.
GATED = re.compile(r"gated (\d+)")


def run(path, argv):
    """`(rc, out, gated)` where `out` is BOTH streams, joined.

    **BOTH STREAMS, AND THE FIRST VERSION READ ONLY STDOUT** -- so the refusal assertion asked
    whether `input absent` was in stdout, and every gate prints its refusal to STDERR. Two
    plants went red for a reason that had nothing to do with the gates, which is the same lesson
    `gatekit._said` records: stdout and stderr are not interchangeable and a test that reads the
    wrong one cannot fail for the right reason.
    """
    r = subprocess.run([str(PY), str(path), *argv], cwd=ROOT, capture_output=True,
                       text=True, timeout=TIMEOUT)
    out = (r.stdout or "") + (r.stderr or "")
    m = GATED.search(out)
    return r.returncode, out, (int(m.group(1)) if m else None)


def restore(subject):
    b = subprocess.run(["git", "show", f"{REV}:{subject}"], cwd=ROOT,
                       capture_output=True, text=True)
    if b.returncode != 0 or not b.stdout:
        return None
    tgt = ROOT / subject
    existed = tgt.exists()
    tgt.parent.mkdir(parents=True, exist_ok=True)
    tgt.write_text(b.stdout)
    return tgt, existed


def drop(tgt, existed):
    if not existed:
        tgt.unlink(missing_ok=True)


def main():
    rc = 0
    checks = []
    with tempfile_dir() as td:
        empty_oracle = Path(td) / "oracle.rows"
        empty_oracle.write_text("")            # a lane with ZERO rows, not a missing file

        # ---- DIRECTION 1: the refusal, on the live tree, subject ABSENT ----------
        for rel in PLANTABLE:
            code, out, _g = run(ROOT / rel, [])
            named = "input absent" in (out or "")
            checks.append((f"REFUSED, subject absent: {rel}",
                           code == 3 and named,
                           f"rc={code}, names the absent path={named}"))
            if code == 3:
                sys.stdout.write(f"    refusal says: {out.strip()[:110]}\n")

        # ---- DIRECTION 2: GREEN, subject restored, both lanes real ---------------
        for rel in PLANTABLE:
            r = restore(SUBJECT)
            if r is None:
                checks.append((f"GREEN: {rel}", False, "subject has no blob"))
                continue
            tgt, existed = r
            try:
                code, out, gated = run(ROOT / rel, [])
                real = gated is not None and gated > 0
                checks.append((f"GREEN, and it GATED ROWS: {rel}",
                               code == 0 and real and "AGREE" in out,
                               f"rc={code} gated={gated} (0 would be agreement over NOTHING)"))
                if gated:
                    sys.stdout.write(f"    {rel} gated {gated} row(s) and said "
                                     f"{'AGREE' if 'AGREE' in out else 'BROKEN'}\n")
            finally:
                drop(tgt, existed)

        # ---- DIRECTION 3: THE VACUOUSNESS PROBE. Empty oracle lane, subject present.
        # The gate PASSES. This harness must NOT count that as a pass.
        tgt, existed = restore(SUBJECT)
        if tgt is None:
            checks.append(("VACUOUS green is caught", False, "no blob"))
        else:
            try:
                code, out, gated = run(ROOT / rel if False else ROOT / PLANTABLE[0],
                                       ["--oracle-stdout", str(empty_oracle)])
                vac = code == 0 and (gated == 0)
                checks.append((
                    "VACUOUS green is CAUGHT: an empty oracle lane makes nl-gate-noguard.py "
                    "answer rc=0 and 'AGREE' having gated 0 rows,\n"
                    "       so the DENOMINATOR is the assertion and the verdict alone is not",
                    vac,
                    f"rc={code} gated={gated} -- the gate says AGREE and it means NOTHING; this "
                    f"harness scores it {gated}"))
                sys.stdout.write(f"    with an EMPTY oracle lane: rc={code} gated={gated} "
                                 f"verdict-line="
                                 f"{[l for l in out.splitlines() if 'AGREE' in l][:1]}\n")
            finally:
                drop(tgt, existed)

    print("\nPLANTS -- three directions, each with its own denominator\n")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    green = sum(1 for _n, ok, _g in checks if ok)
    print(f"\nPLANTS: {'GREEN' if rc == 0 else 'RED'} ({green}/{len(checks)})")
    return rc


class tempfile_dir:
    """A scratch directory OUTSIDE the repo, because `AGENTS.md`'s no-`.txt` rule and the
    pre-approved temp dir both say the same thing: a fixture written into the tree is a file
    somebody later has to know about."""

    def __enter__(self):
        import tempfile
        self._t = tempfile.TemporaryDirectory(
            dir="/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode")
        return self._t.name

    def __exit__(self, *a):
        self._t.cleanup()


if __name__ == "__main__":
    sys.exit(main())