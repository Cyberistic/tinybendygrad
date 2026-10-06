#!/usr/bin/env python3
"""Detect that the git index was reset out from under a caller.

A `visualjj` VS Code server (`dist/bin/jj branching server`) runs a snapshot
loop for this colocated jj repo. When any worktree file changes it snapshots the
working copy, then exports it to git: it overwrites `.git/index` with the
working-copy tree and moves `.git/HEAD` to the working-copy commit. Any staging
a caller did between its `git add` and its `git commit` is gone — silently,
because `git diff --cached` is then empty *relative to the commit HEAD was moved
to*. Nothing warns the caller.

This guard makes that drift visible. It fingerprints the two things the reset
moves — the staged set and HEAD — and refuses when either has changed.

    .venv/bin/python checks/git-index-guard.py snap
        INDEX-BASELINE <token> HEAD <sha> STAGED <n>

    .venv/bin/python checks/git-index-guard.py check --expect <token>
        INDEX-OK <token>                       exit 0
        INDEX-DRIFT <old> -> <new>             exit 1
        INDEX-REFUSED: no --expect <token>     exit 3
        INDEX-DEAD: <git failure>              exit 5

Reads use `git --no-optional-locks` so the guard never writes the index itself —
a guard that refreshes the index is part of the hazard, not a check on it.

WHY HEAD IS IN THE TOKEN: a reset makes the staged set empty *and* moves HEAD to
the commit that already contains the work, so staged-empty -> staged-empty alone
reads as agreement. The HEAD half is what names the reset.
"""
import hashlib
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5


def git(*args: str) -> tuple[int, str]:
    try:
        p = subprocess.run(
            ["git", "--no-optional-locks", "-C", ROOT, *args],
            capture_output=True, text=True,
        )
    except FileNotFoundError:
        return 127, "git not found"
    return p.returncode, p.stdout


def fingerprint() -> tuple[str | None, str, str]:
    """(token, head, error). token is None on an unreadable repository."""
    rc, head = git("rev-parse", "HEAD")
    if rc != 0:
        return None, "", "not a git repository or no HEAD"
    rc, staged = git("diff", "--cached", "--name-status", "-z")
    if rc != 0:
        return None, "", "git diff --cached failed"
    head = head.strip()
    entries = [e for e in staged.split("\0") if e]
    body = "\n".join(["head", head, "staged", str(len(entries)), *entries])
    return hashlib.sha256(body.encode()).hexdigest(), head, ""


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("snap", "check"):
        sys.stderr.write("usage: git-index-guard.py (snap | check --expect <token>)\n")
        return REFUSED

    token, head, err = fingerprint()
    if token is None:
        print(f"INDEX-DEAD: {err}")
        return DEAD

    if argv[0] == "snap":
        rc, staged = git("diff", "--cached", "--name-only")
        n = len([line for line in staged.splitlines() if line])
        print(f"INDEX-BASELINE {token} HEAD {head[:12]} STAGED {n}")
        return PASS

    expect = argv[argv.index("--expect") + 1] if "--expect" in argv else None
    if not expect:
        print("INDEX-REFUSED: no --expect <token>; run `snap` immediately after staging")
        return REFUSED
    if token == expect:
        print(f"INDEX-OK {token} HEAD {head[:12]}")
        return PASS
    # Re-read the pieces so the drift is named, not just reported as a hash mismatch.
    current = fingerprint()[0]
    print(f"INDEX-DRIFT {expect} -> {current} HEAD {head[:12]}")
    return FAIL


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
