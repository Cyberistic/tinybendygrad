#!/usr/bin/env python3
"""TWO-STATE DISCIPLINE, MEASURED. For each gate this unit could move, BOTH states are shown.

    .venv/bin/python .agents/slop/coindependent/twostate.py

`AGENTS.md`: *"A gate demonstrated only in its green state has been shown to do nothing."* The
control direction is the load-bearing half: a gate that is `ok` after an edit looks identical
whether it got stronger or was quietly weakened.

Each experiment names the TWO states and the EXACT change between them. Every plant writes only
under `.agents/slop/coindependent/` (this unit's own directory) or a `tempfile` tree, and every
plant that touches the working tree REMOVES what it wrote in a `finally`, so the tree is left as
found. NO `bend` IS STARTED. The verdict token and the exit status are both recorded, because
`CLEAN, rc=1` and `CLEAN, rc=0` are different measurements and the token alone would hide it.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = str(ROOT / ".venv" / "bin" / "python")
WORD = re.compile(r"\b(PASS|FAIL|REFUSED|SKIP|DEAD|OK|RED|GREEN|CLEAN|BROKEN|INCOMPLETE|"
                  r"NOT A VERDICT|UNMEASURABLE|STALE|rc=\d+)\b")


def run(argv, env=None):
    import os
    e = dict(os.environ)
    if env:
        e.update(env)
    r = subprocess.run([PY, *argv], cwd=ROOT, capture_output=True, text=True, timeout=60, env=e)
    toks = sorted(set(WORD.findall((r.stdout or "") + (r.stderr or ""))))
    return r.returncode, ",".join(toks), (r.stdout or "")[-300:]


def two_state_no_txt():
    """`checks/no-txt.py`: CLEAN at rest; RED when a `.txt` exists anywhere it walks.

    The plant is THIS UNIT'S OWN directory -- a path the gate owns (it `os.walk`s ROOT) and a
    path this unit is allowed to write. Removed in `finally`."""
    plant = HERE / "plant-should-be-named.txt"
    try:
        before = run(["checks/no-txt.py"])
        plant.write_text("planted by coindependent/twostate.py\n")
        after = run(["checks/no-txt.py"])
    finally:
        plant.unlink(missing_ok=True)
    restored = run(["checks/no-txt.py"])
    return [("no-txt", "at rest (no .txt)", before),
            ("no-txt", "planted .agents/slop/coindependent/plant-should-be-named.txt", after),
            ("no-txt", "plant removed (restored)", restored)]


def two_state_wallcheck():
    """`checks/wallcheck.py --selftest` is its own guard suite (green). A selection that matches
    nothing is the `4` its usage documents -- reachable with an id no row carries."""
    return [("wallcheck", "--selftest", run(["checks/wallcheck.py", "--selftest"])),
            ("wallcheck", "ids [NO-SUCH-WALL-ID]", run(["checks/wallcheck.py", "NO-SUCH-WALL-ID"]))]


def two_state_residue():
    return [("residue", "--plant", run(["checks/residue.py", "--plant"])),
            ("residue", "--disarm DELETE", run(["checks/residue.py", "--disarm", "DELETE"]))]


def two_state_env_precond():
    return [("env-precond", "--declare", run(["checks/env-precond.py", "--declare"])),
            ("env-precond", "--plant satisfied", run(["checks/env-precond.py", "--plant", "satisfied"])),
            ("env-precond", "--plant moved", run(["checks/env-precond.py", "--plant", "moved"])),
            ("env-precond", "--plant nonsense (bad arg)", run(["checks/env-precond.py", "--plant", "nonsense"]))]


def two_state_unowned():
    """`checks/unowned.py`: a `--why` on a path that is not a citation is a red with a reason."""
    return [("unowned", "at rest", run(["checks/unowned.py"])),
            ("unowned", "--why /nonexistent/coindependent", run(["checks/unowned.py", "--why", "/nonexistent/coindependent"]))]


def two_state_nvrows():
    return [(f"nvrows-deadrow-gate", f"--plant {k}",
             run(["checks/nvrows-deadrow-gate.py", "--plant", k]))
            for k in ("REVIVE", "ORPHAN", "SELF", "STRIP")]


def two_state_gatekit():
    return [("gatekit", "--plant (3 output-dir states)", run(["gates/gatekit.py", "--plant"]))]


def two_state_citation():
    """`checks/citation-gate.py` has NO argument parser: its argv entries are SCAN ROOTS. Plain
    (scan the tree) finds a citation that a rule added and removed -> RED; a root that does not
    exist scans 0 files and answers GREEN. Both states are real, and the green is VACUOUS -- a
    gate that goes green by being pointed at nothing is the `artefacts_ok()` shape."""
    return [("citation-gate", "at rest (scans the tree)", run(["checks/citation-gate.py"])),
            ("citation-gate", "root that does not exist", run(["checks/citation-gate.py", "--help"]))]


EXPERIMENTS = [two_state_no_txt, two_state_wallcheck, two_state_residue,
               two_state_env_precond, two_state_unowned, two_state_nvrows, two_state_gatekit,
               two_state_citation]


def main(argv):
    rows = []
    for fn in EXPERIMENTS:
        rows += fn()
    if "--rows" in argv:
        print("gate\tstate\trc\ttokens")
        for g, s, (rc, tok, _) in rows:
            print(f"{g}\t{s}\t{rc}\t{tok or '-'}")
        return 0
    print(f"{'gate':18} {'state':52} {'rc':4} tokens")
    for g, s, (rc, tok, _) in rows:
        print(f"{g:18} {s:52} {rc:4} {tok or '-'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
