#!/usr/bin/env python3
"""Measure the staging primitives against a concurrent index resetter.

Runs in the throwaway colocated demo (never the real repo). Each test states a
claim, exercises it, and prints the measured outcome. `resetter()` simulates the
hazard exactly: it overwrites `.git/index` from HEAD, which is what any tool that
rewrites the shared index does.
"""
import os
import shutil
import subprocess
import tempfile

DEMO = os.path.join(tempfile.gettempdir(), "opencode", "jjhazard-primitives")
GITENV = dict(os.environ, GIT_AUTHOR_NAME="d", GIT_AUTHOR_EMAIL="d@e",
              GIT_COMMITTER_NAME="d", GIT_COMMITTER_EMAIL="d@e")


def git(*args, **kw):
    env = kw.pop("env", GITENV)
    p = subprocess.run(["git", *args], cwd=DEMO, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def staged(env=None):
    _, out, _ = git("diff", "--cached", "--name-only", env=env)
    return sorted(line for line in out.splitlines() if line)


def resetter():
    """Overwrite the shared index from HEAD: the hazard, in one line."""
    git("read-tree", "HEAD")


def fresh():
    shutil.rmtree(DEMO, ignore_errors=True)
    os.makedirs(DEMO)
    git("init", "-q")
    open(os.path.join(DEMO, "a.rows"), "w").write("a\n")
    git("add", "a.rows")
    git("commit", "-q", "-m", "base")


def main():
    fresh()

    # CLAIM: `git commit -- <untracked>` fails outright.
    open(os.path.join(DEMO, "u.rows"), "w").write("u\n")
    rc, out, err = git("commit", "--dry-run", "-m", "x", "--", "u.rows")
    print(f"[untracked pathspec commit] rc={rc} err={err!r} out={out!r}")

    # CLAIM: the shared index is wiped by the resetter.
    open(os.path.join(DEMO, "s.rows"), "w").write("s\n")
    git("add", "s.rows")
    before = staged()
    resetter()
    after = staged()
    print(f"[shared index vs resetter] staged {before} -> {after}  "
          f"{'WIPED (hazard confirmed)' if before and not after else 'intact'}")

    # CLAIM: a private GIT_INDEX_FILE is immune, because the resetter owns `.git/index`.
    priv = os.path.join(DEMO, ".git", "agent-index")
    penv = dict(GITENV, GIT_INDEX_FILE=priv)
    git("read-tree", "HEAD", env=penv)
    git("add", "--", "s.rows", env=penv)
    priv_before = staged(penv)
    resetter()
    priv_after = staged(penv)
    print(f"[private index vs resetter] staged {priv_before} -> {priv_after}  "
          f"{'SURVIVES' if priv_before == priv_after and priv_after else 'lost'}")

    # The safe one-command form: commit from the private index, limited to our paths.
    rc, out, err = git("commit", "-m", "agent: s.rows", "--", "s.rows", env=penv)
    print(f"[private-index commit] rc={rc} err={err!r}")
    _, show, _ = git("show", "--stat", "--oneline", "-1")
    print(f"[committed] {show.splitlines()[0] if show else ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
