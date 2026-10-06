#!/usr/bin/env python3
"""Materialise the frozen copies the repro compares against, and print their sha256.

    .venv/bin/python .agents/slop/clearfix/freeze.py

THREE FIXTURES, and each exists for a stated reason:

  frozen-prefix/<gate>.py   `git show HEAD:gates/<gate>.py`, BYTE FOR BYTE. This is THE
                            pre-fix gate, so "before" stays reproducible after the live file
                            is edited. MEASURED: a repro whose baseline is the working copy
                            of the thing it is measuring has no before at all.
  gk/gatekit.py             `gates/gatekit.py` AS COMMITTED, with three module-level lines
                            repointed so its ARTIFACTS land in a scratch root of this
                            harness's choosing. Not an edit to behaviour: every run-visible
                            line is identical, and the sha of the source it came from is
                            printed so the pairing is checkable.
  gk2/gatekit.py            the same file plus ONE line -- `self._clear()` in `Gate.__init__`
                            -- which is OPTION 2 of the three answers, as a diff. Applying it
                            to a FROZEN COPY rather than to the live file is deliberate:
                            `gates/gatekit.py` belongs to another unit, so the change is
                            measured here and REPORTED there.

WHY A FROZEN gatekit AND NOT THE LIVE ONE. MEASURED mid-build: a second unit was editing
`gates/gatekit.py` (renaming `.txt` to `.rows`/`.out`) and had just emptied all nine
`gates/artifacts/*` directories while this harness was taking its first measurement. A
measurement whose instrument is being rewritten underneath it is a measurement of the
rewrite, so this freezes the instrument and says which one it froze.

THE ARTIFACT ROOT IS THE SCRATCH ROOT, NOT `gates/artifacts/`, for the same reason plus one
more: the state under test IS the leftover files, and a tree that another actor is emptying
makes "leftover" unreadable. One `CLEARFIX_ART` env var, set by the harness, read once.
"""
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / "bin" / "bend").is_file())

# The live gate's artifact root, repointed. `ART` is the only one of the three that decides
# WHERE a run writes, and where it writes is the variable under test -- so each copy is given
# its OWN root derived from its OWN directory, with no env var and no coordination. An env var
# was the first attempt and it is wrong twice over: two copies sharing one variable collided
# MEASURED (one beat's `rmtree` deleted the other's staged `.tmp.gate.bin` mid-compile), and a
# variable a reader must set is a variable a reader will forget.
REP = ('HERE = Path(__file__).resolve().parent\n'
       'ROOT = next(p for p in HERE.parents if (p / "bin" / "bend").is_file())\n'
       'ART = HERE / "{name}-artifacts"')
LIVE = "HERE = Path(__file__).resolve().parent\nROOT = HERE.parent\nART = HERE / \"artifacts\""

# OPTION 2, as one line. `_clear()` is already the method `run()` opens with; this moves the
# call to construction, so the directory is empty before ANY check in ANY caller can fail.
MK = "        self.dir.mkdir(parents=True, exist_ok=True)"
OPT2 = MK + "\n        self._clear()   # OPTION 2"

# `Gate._resolve` searches HERE, then ROOT. HERE is this copy's OWN directory, so a driver
# that lives BESIDE THE REAL GATE -- `gates/ew-consts.bend`, `gates/ew-explog.bend`,
# `gates/wk-cd.bend`, `gates/wk-f32.bend`, and each gate's `-oracle.py` -- is not there, and
# the search falls through to a path that does not exist. MEASURED as six of nine gates
# answering `bend said: no such file: .../clearfix/gk/ew-consts.bend`, which is a FIXTURE
# defect that reads exactly like six broken gates -- the shape this project keeps punishing.
# Adding `gates/` to the search list makes the copy resolve drivers as the live module does.
# It is the only other line changed, and no line that decides a verdict is touched.
RESOLVE = ("        for base in (HERE, ROOT):", '        for base in (HERE, ROOT, ROOT / "gates"):')

GATES = ("mixin-op-gate.py", "beautiful-mnist-gate.py")


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def head(rel):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:{rel}"],
                       capture_output=True, text=True, check=True)
    return r.stdout


def write(p, body):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)
    return sha(p)


def main():
    gk = head("gates/gatekit.py")
    if LIVE not in gk:
        sys.exit(f"freeze: the three repointed lines are not in HEAD:gates/gatekit.py verbatim --\n"
                 f"        the anchor moved, so this fixture would silently patch nothing.")
    for anchor, why in ((LIVE, "HERE/ROOT/ART"), (MK, "Gate.__init__'s mkdir"),
                        (RESOLVE[0], "Gate._resolve's search list")):
        if anchor not in gk:
            sys.exit(f"freeze: the anchor for {why} is gone from HEAD:gates/gatekit.py -- this\n"
                     f"        fixture would silently patch nothing, which is worse than failing.")
    for d in ("gk", "gk2", "frozen-prefix"):
        shutil.rmtree(HERE / d, ignore_errors=True)

    print(f"source   gates/gatekit.py  {sha(ROOT / 'gates' / 'gatekit.py')}  (live, may move)")
    print(f"source   HEAD:gates/gatekit.py  {sha_bytes(gk)}")
    out = []
    for name in ("gk", "gk2"):
        body = gk.replace(LIVE, REP.format(name=name), 1).replace(*RESOLVE, 1)
        if name == "gk2":
            body = body.replace(MK, OPT2, 1)
        out.append((f"{name}/gatekit.py", write(HERE / name / "gatekit.py", body)))
    for g in GATES:
        out.append((f"frozen-prefix/{g}", write(HERE / "frozen-prefix" / g, head(f"gates/{g}"))))
    print()
    for rel, h in out:
        print(f"{h}  {rel}")
    print()
    print("gk2/gatekit.py is gk/gatekit.py plus ONE line. `diff`:")
    d = subprocess.run(["diff", "-u", str(HERE / "gk" / "gatekit.py"),
                        str(HERE / "gk2" / "gatekit.py")], capture_output=True, text=True)
    for line in d.stdout.splitlines():
        if line.startswith(("+", "-", "@")):
            print("   " + line)
    live = gk
    for line in subprocess.run(
            ["diff", "-u", "/dev/stdin", str(HERE / "gk" / "gatekit.py")],
            input=live, capture_output=True, text=True).stdout.splitlines():
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
            print(f"   vs HEAD:gates/gatekit.py: {line}")
    live = {g: sha(ROOT / "gates" / g) for g in GATES}
    print()
    for g in GATES:
        f = sha(HERE / "frozen-prefix" / g)
        print(f"{g}: live={live[g][:16]}  frozen-prefix={f[:16]}  "
              + ("BYTE-IDENTICAL" if live[g] == f else "DIVERGED -- the live gate was edited"))


def sha_bytes(s):
    return hashlib.sha256(s.encode()).hexdigest()


if __name__ == "__main__":
    os.environ.setdefault("CLEARFIX_ART", str(HERE / "artifacts"))
    main()