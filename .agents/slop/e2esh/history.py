"""HOW MANY COMMITS CHANGED `checks/e2e.sh` WITHOUT MOVING `BODY_SHA`?

That number decides whether the pin is a guard or a comment. For every commit that touched the
guarded file, this reads the `BODY_SHA` the pin held AT THAT COMMIT and compares it to the sha256
the file actually had there. A commit that changed the file and left the pin is a commit whose edit
the gate could not have noticed; a commit that changed both is the pin being paid for.

COMMITTED STATE ONLY: `git show <rev>:<path>` for both files, so a dirty working tree cannot
manufacture or hide a row. Exits 1 if the file ever moved under a pin that did not -- that is the
failure direction this repro has to be able to take.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys

BODY = "checks/e2e.sh"
PIN = "checks/e2e.py"


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout


def pin_at(rev: str) -> str | None:
    """`BODY_SHA` as `checks/e2e.py` held it at `rev`, or None if the pin did not exist yet."""
    try:
        src = git("show", f"{rev}:{PIN}").decode()
    except subprocess.CalledProcessError:
        return None
    for line in src.splitlines():
        if line.startswith("BODY_SHA = "):
            return line.split('"')[1]
    return None


def main() -> int:
    revs = git("log", "--format=%H", "--", BODY).decode().split()
    print(f"{len(revs)} commit(s) touched {BODY}\n")
    print(f"{'commit':<12} {'BODY_SHA at that commit':<18} {'file sha then':<18} verdict")

    unpaid = 0
    for rev in revs:
        want = pin_at(rev)
        got = hashlib.sha256(git("show", f"{rev}:{BODY}")).hexdigest()
        if want is None:
            verdict, unpaid = "no pin at this commit", unpaid
        elif want == got:
            verdict, unpaid = "pin MOVED with the file", unpaid
        else:
            unpaid += 1
            verdict = f"FILE MOVED, PIN DID NOT (stayed {want[:8]})"
        msg = git("log", "-1", "--format=%s", rev).decode().strip()[:60]
        print(f"{rev[:10]}  {str(want)[:16]:<18} {got[:16]:<18} {verdict}\n    {msg}")

    print(f"\ncommits that changed {BODY} without moving BODY_SHA: {unpaid}")
    return 1 if unpaid else 0


if __name__ == "__main__":
    sys.exit(main())