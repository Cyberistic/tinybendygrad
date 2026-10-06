"""PLANT A CHANGE TO `checks/e2e.sh` AND SEE WHAT REACTS.

The question this answers decides the whole unit: **is `BODY_SHA` a guard or a comment?** Read the
history first (`.agents/slop/e2esh/history.py`) -- it says the pin has been paid for on every commit
so far, which is a fact about DISCIPLINE, not about whether the pin can see anything. So the pin is
given the two changes it is supposed to notice, one at a time:

  A. A COMMENT. Zero code, zero verdict, one line of prose appended.
  B. THE FIX ITSELF. The three-line root assertion the other sixteen `checks/*.sh` use.

and for each, three observers are asked what they did:

  1. `oracle_drift()` -- the pin, called directly, so the answer is a value and not an exit status.
  2. `checks/e2e.py` -- the gate, as a caller runs it. RUN ONLY WHEN (1) IS ALREADY TRUE, because
     `checks/e2e.py` is the seven-stage gate and running it launches `bend`, `node`, `cc` and a
     browser; when the pin has fired, `main()` returns 3 at line 358 having started nothing. That
     restraint is the whole reason the numbers below are cheap.
  3. `diff.py --sets plant-no-node` -- stdout FIDELITY of the port against the frozen oracle, over
     one fixture plant. No compiler, no browser, no GPU. If a change to `checks/e2e.sh` leaves this
     at `0 of 1 set(s) disagree`, then the live shell's bytes are not what fidelity is made of.

THE LIVE TREE IS RESTORED IN A `finally`, from the bytes read at entry, so a crash mid-measurement
leaves `checks/e2e.sh` exactly as it was found. Two methods that do not share a regex assert the
restoration: the sha256 AND the byte length.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
REPO = HERE.parents[3]
BODY = REPO / "checks" / "e2e.sh"
PY = str(REPO / ".venv/bin/python")

# The fix, as the sixteen siblings write it: `${0%/*}` is POSIX and spawns no process, the `case`
# arm is the `$0` with no slash in it, and the MARKERS are what assert the root rather than the
# arithmetic -- `REPO` is `dirname "$0"` up one either way, so only the markers can tell.
OLD_ROOT = 'ROOT=$(cd "$(dirname "$0")/../.." && pwd)\n'   # what HEAD had; kept for the prose only

# TWO PLANTS, AND THE SECOND ONE IS THE INTERESTING ONE. `A` is the pin's weakest case: one line of
# prose, no code, no verdict -- the change the pin is least entitled to notice. `B` is a change to
# the SUBJECT's own behaviour rather than to its text: drop one of the two root markers, so the
# preamble would accept a tree that is not this repository. A guard over a file's text should fire on
# both; a guard over what the file PRODUCES should fire on `B` and not on `A`.
PLANTS = {
    "A comment only": "\n# e2esh plant: one line of prose, no code.\n",
    "B one marker dropped": '[ -f "$ROOT/pyproject.toml" ] && [ -d "$ROOT/tinybendygrad" ] ||\n'
                            '  { echo "$0: not at the repo root (pwd $ROOT)" >&2; exit 2; }\n',
}
# The exact line `B` removes. Written out rather than pattern-matched, because a matcher that
# re-derives the text it is about to replace can silently replace nothing and pass.
DROP_MARKER = '[ -f "$ROOT/pyproject.toml" ] && [ -d "$ROOT/tinybendygrad" ] ||\n'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def drift() -> list[str]:
    """`checks/e2e.py`'s own pin check, imported rather than run, so the answer is a list."""
    src = (REPO / "checks" / "e2e.py").read_text()
    ns: dict = {"__file__": str(REPO / "checks" / "e2e.py"), "__name__": "e2epin"}
    exec(compile(src, str(REPO / "checks" / "e2e.py"), "exec"), ns)   # noqa: S102 -- it is our file
    return ns["oracle_drift"]()


def fidelity() -> str:
    """`diff.py`'s own summary line: how many of the sets disagree on stdout/exit/status."""
    out = subprocess.run([PY, str(REPO / ".agents/slop/e2epy/diff.py"), "--sets", "plant-no-node"],
                         cwd=REPO, capture_output=True, text=True)
    return [ln for ln in out.stdout.splitlines() if "disagree" in ln][-1]


def main() -> int:
    pristine = BODY.read_bytes()
    print(f"pristine checks/e2e.sh: {len(pristine)} bytes, sha256 {sha(pristine)[:16]}\n")
    try:
        print(f"unplanted: oracle_drift() -> {drift()}")
        print(f"unplanted: stdout fidelity -> {fidelity()}\n")

        for label, patch in PLANTS.items():
            if label.startswith("B"):
                text = pristine.decode()
                assert text.count(DROP_MARKER) == 1, "the assertion line this plant weakens is gone"
                planted = text.replace(DROP_MARKER, patch).encode()
            else:
                planted = pristine + patch.encode()
            BODY.write_bytes(planted)
            print(f"--- plant {label}: {len(pristine)} -> {len(planted)} bytes, "
                  f"sha256 {sha(planted)[:16]}")
            bad = drift()
            print(f"    1. oracle_drift()      -> {bad if bad else '[] (no drift)'}")
            if bad:
                r = subprocess.run([PY, str(REPO / "checks" / "e2e.py")], cwd=REPO,
                                   capture_output=True, text=True)
                head = [ln for ln in r.stderr.splitlines() if ln.strip()][:1]
                print(f"    2. checks/e2e.py      -> rc={r.returncode}  {head}")
                print(f"       (returned before stage 1: `main()` returns at e2e.py:358, no stage ran)")
            else:
                print("    2. checks/e2e.py      -> NOT RUN: the pin did not fire, so this call "
                      "would launch the seven stages")
            print(f"    3. stdout fidelity     -> {fidelity()}")
            BODY.write_bytes(pristine)
            print()
    finally:
        BODY.write_bytes(pristine)

    ok = sha(BODY.read_bytes()) == sha(pristine) and len(BODY.read_bytes()) == len(pristine)
    print(f"restored checks/e2e.sh: {len(pristine)} bytes, sha256 {sha(BODY.read_bytes())[:16]}"
          f"  -> {'RESTORED' if ok else 'RESTORATION FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())