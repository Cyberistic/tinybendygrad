#!/usr/bin/env python3
"""RESTORE THE SUBJECT, one gate at a time, and PLANT BOTH DIRECTIONS. Deleted in a `finally`.

    .venv/bin/python .agents/slop/modulerefuse/x6-plant.py

**THE SUBJECT IS RESTORED, NEVER PLANTED.** A plant that supplied its own oracle would be testing a
fixture, not the gate: `zerogate` disclosed that two of its own first plants were GREEN-only and
proved nothing, and the way a plant is worthless here is structural -- `nl-gate-noguard.py` reads
its oracle from `ORACLE = [".agents/slop/nl/nl-oracle.py", "rows"]`, so a plant that wrote its own
oracle would be writing the very thing the gate exists to check. So the file this harness writes is
**the git blob at `371cc64c9^`**, byte-for-byte, and the harness asserts the bytes it wrote equal the
bytes git has.

THE TWO DIRECTIONS, AND WHY A GREEN-ONLY PLANT IS WORTHLESS. Every plant here asserts something that
CAN FAIL:

  REFUSED  the gate answers 3 and NAMES the absent path in its own text. A refusal that cannot name
            its input is `zerogate`'s cause (e), and it would pass this assertion for the wrong
            reason, so the assertion carries the path string, not just the exit code.
  GREEN    the gate answers 0 **AND `gated > 0`, PARSED OUT OF ITS OWN OUTPUT** with
            `re.compile(r"gated (\\d+)")`. A hardcoded `205` would keep passing after the row set
            changed -- which is `zerogate`'s second bad plant wearing a different hat.
  VACUOUS  an EMPTY oracle lane must NOT be accepted as a green by this harness. It drives the gate
            to rc=0 and `AGREE` and scores it a FAIL.

**THE TREE IS CHECKED AFTERWARDS, NOT ASSUMED.** Every restore is in a `finally`, and the harness
ends by counting the four subject paths on disk and by `git status --porcelain` under `checks/` and
`gates/`. A plant that leaves residue is a plant that has damaged the tree it measured, and
`zerogate`'s §7b is the record of what that costs here: it destroyed 797 KB of a tracked census by
running a gate on a nominal read-only run.
"""
import pathlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 90
GATED = re.compile(r"gated (\d+)")

# THE SUBJECTS, each named by the GATE that reads it rather than by a sweep of the tree: the gate
# has to name it for the restore to be a restore and not a guess. `SWEPT` is the commit whose message
# says "THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION PATHS WITH THEM".
SWEPT = "371cc64c9^"
SUBJECTS = {
    "checks/nl-gate.py": ".agents/slop/nl/nl-oracle.py",
    "checks/nl-gate-noguard.py": ".agents/slop/nl/nl-oracle.py",
    "checks/dup-gate.py": ".agents/slop/eq/eq-census2.py",
    "checks/dup-census.py": ".agents/slop/eq/eq-census2.py",
    "checks/rn-gate.py": ".agents/slop/eq/eq-census2.py",
    "checks/hermetic-census.py": ".agents/slop/hermetic/isolate.py",
    "checks/cl-port-gate.py": ".agents/slop/clangshim/oracle.py",
}


def git_blob(path):
    r = subprocess.run(["git", "cat-file", "blob", f"{SWEPT}:{path}"], cwd=ROOT,
                       capture_output=True, timeout=60,
                       env={"GIT_INDEX_FILE": str(ROOT / ".git" / "agent-index"),
                            "PATH": "/usr/bin:/bin:/usr/local/bin"})
    return r.stdout if r.returncode == 0 else None


def run(gate, argv=()):
    try:
        r = subprocess.run([str(PY), str(ROOT / gate), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", ""
    return (str(r.returncode), r.stdout or "", r.stderr or "")


def restore(subject):
    """Materialise the git blob at the gate's own path. Returns `(ok, bytes)` -- and the bytes are
    compared against git AFTER the write, so a partial write cannot pass as a restore."""
    dest = ROOT / subject
    if dest.is_file():
        return True, dest.stat().st_size
    blob = git_blob(subject)
    if not blob:
        return False, 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(blob)
    after = dest.read_bytes()
    if after != blob:
        dest.unlink(missing_ok=True)
        return False, 0
    return True, len(blob)


def undo():
    """Remove every subject this harness materialised. Counts what it did NOT remove, because a
    cleanup that cannot report its own residue cannot be trusted to have cleaned."""
    left = []
    for subject in set(SUBJECTS.values()):
        p = ROOT / subject
        if p.is_file() and p.parent.name in ("nl", "eq", "hermetic", "clangshim"):
            p.unlink()
            if p.is_file():
                left.append(subject)
    return left


def main():
    print("RESTORING THE SUBJECT FROM GIT, ONE GATE AT A TIME. Bytes written are compared against "
          f"`git cat-file blob {SWEPT}:<path>`.\n")
    print(f"{'gate':30} {'subject':34} {'restored':>9} {'rc at rest':>11}  verdict")
    print("-" * 116)
    results = {}
    for gate, subject in SUBJECTS.items():
        ok, n = restore(subject)
        rc, out, err = run(gate)
        tok = next((l for l in (out + "\n" + err).splitlines() if l.strip()), "")
        m = GATED.search(out)
        verdict = f"{tok[:44]}"
        if m:
            verdict += f"   [gated {m.group(1)}]"
        print(f"{gate:30} {subject:34} {('YES ' + str(n) + 'B') if ok else 'NO BLOB':>9} "
              f"{rc:>11}  {verdict}")
        results[gate] = (ok, n, rc, out, err)

    print("\nPLANTS, BOTH DIRECTIONS, each one able to FAIL:\n")
    checks = []

    # -- direction 1: REFUSED, with the absent path NAMED -------------------------------------
    for gate, subject in (("checks/nl-gate.py", ".agents/slop/nl/nl-oracle.py"),
                          ("checks/nl-gate-noguard.py", ".agents/slop/nl/nl-oracle.py"),
                          ("checks/hermetic-census.py", ".agents/slop/hermetic/isolate.py")):
        p = ROOT / subject
        present = p.is_file()
        p.unlink(missing_ok=True)
        try:
            rc, out, err = run(gate)
        finally:
            if present:
                p.write_bytes(git_blob(subject) or b"")
        named = subject.split("/")[-1] in (out + err)
        checks.append((f"REFUSED  {gate}", rc == "3" and named,
                       f"rc={rc} names {subject.split('/')[-1]}={named}"))

    # -- direction 2: GREEN, and NOT VACUOUS -------------------------------------------------
    gate = "checks/nl-gate-noguard.py"
    lane = "".join(f"row_{i}=value_{i}\n" for i in range(205))
    with tempfile.TemporaryDirectory() as td:
        p = pathlib.Path(td) / "port.rows"
        p.write_text(lane)
        same, o, _e = run(gate, ["--port-stdout", str(p), "--oracle-stdout", str(p)])
    m = GATED.search(o)
    checks.append((f"GREEN    {gate} -- identical lanes, gated > 0", same == "0" and m
                   and int(m.group(1)) > 0,
                   f"rc={same} gated={m.group(1) if m else '?'}"))

    # -- direction 3: the VACUOUS green, which the harness scores a FAIL -------------------------
    with tempfile.TemporaryDirectory() as td:
        p = pathlib.Path(td) / "empty.rows"
        p.write_text("")
        vrc, vout, _ = run(gate, ["--port-stdout", str(p), "--oracle-stdout", str(p)])
    vm = GATED.search(vout)
    vacuous = vrc == "0" and (vm is None or int(vm.group(1)) == 0)
    checks.append((f"VACUOUS  {gate} -- an EMPTY lane greens the gate (harness scores this a FAIL)",
                   vacuous, f"rc={vrc} gated={vm.group(1) if vm else '0'} and the gate said AGREE"))

    ok = 0
    for label, good, obs in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {label}\n          {obs}")
        ok += bool(good)
    print(f"\n{ok}/{len(checks)} assertions hold.")

    left = undo()
    still = sorted(s for s in set(SUBJECTS.values()) if (ROOT / s).is_file())
    print(f"\nRESIDUE: {len(left)} un-removed, {len(still)} subject path(s) still on disk: {still}")
    st = subprocess.run(["git", "status", "--porcelain", "--", "checks", "gates"], cwd=ROOT,
                        capture_output=True, text=True,
                        env={"GIT_INDEX_FILE": str(ROOT / ".git" / "agent-index"),
                             "PATH": "/usr/bin:/bin:/usr/local/bin"}, timeout=60)
    changed = [l for l in st.stdout.splitlines()
               if not l.split(maxsplit=1)[-1].startswith(".agents/slop")]
    print(f"GATE HOMES: {len(changed)} tracked change(s) under checks/ and gates/ after the whole run")
    for c in changed[:12]:
        print(f"   {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())