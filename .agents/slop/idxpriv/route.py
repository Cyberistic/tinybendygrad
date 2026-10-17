#!/usr/bin/env python3
"""route.py -- THE TWO REMAINING ROUTES FROM A SHARED INDEX INTO A COMMIT.

contam.py measured `--only` bounded against FOREIGN-ADD, DELETION, STALE and INTENT, and race.py
measured 36 concurrent one-path commits on one index carrying 1 path each. So neither a dirty index
nor concurrency alone reaches the 435-file sweep. Two routes remain:

  BARE      `git commit -F msg` with NO pathspec. This is what a unit gets when the pathspec is
            lost, and the arithmetic fits the outage exactly: the repair measured 252 additions +
            182 deletions + the commit's own 1 = 435.
  REWRITE   another process REPLACING the index file under a reader, the way `git add` (lock +
            rename) and `jj`'s colocation snapshot both do. A torn read is not a "shape", so no
            contamination arm can produce it.

Both arms use a SHARED index and both commit exactly ONE path, except BARE which commits none --
that difference IS the experiment.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

NFILES = 300


def git(root, *args, env, check=True):
    p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True,
                       env=env, check=False)
    if check and p.returncode:
        raise RuntimeError(f"git {' '.join(args)} rc={p.returncode}: {p.stderr.strip()}")
    return p


def build():
    root = Path(tempfile.mkdtemp(prefix="route-"))
    env = dict(os.environ, GIT_INDEX_FILE=str(root / ".git" / "agent-index"))
    git(root, "init", "-q", "-b", "main", env=env)
    git(root, "config", "user.email", "r@x", env=env)
    git(root, "config", "user.name", "r", env=env)
    for i in range(NFILES):
        (root / f"f{i:03d}.rows").write_text(f"base {i}\n")
    git(root, "add", "-A", env=env)
    git(root, "commit", "-qm", "seed", env=env)
    return root, env


def bare() -> None:
    """A commit with NO pathspec over another unit's staged work. The arithmetic test."""
    root, env = build()
    try:
        for i in range(9):
            (root / f"theirs{i}.rows").write_text(f"another unit's work {i}\n")
        git(root, "add", "--", *[f"theirs{i}.rows" for i in range(9)], env=env)
        git(root, "rm", "--cached", "-q", "--", *[f"f{i:03d}.rows" for i in range(9)], env=env)
        (root / "mine.rows").write_text("my one path\n")
        git(root, "add", "--", "mine.rows", env=env)
        r = subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", "bare, no pathspec"],
                           capture_output=True, text=True, env=env, check=False)
        if r.returncode:
            print(f"ROUTE BARE    rc={r.returncode}: {r.stderr.strip().splitlines()[0]}")
            return
        sha = git(root, "rev-parse", "HEAD", env=env).stdout.strip()
        carried = git(root, "show", "--name-only", "--format=", sha, env=env).stdout.split()
        print(f"ROUTE BARE    carried {len(carried)} paths on a commit that NAMED none "
              f"(9 foreign adds + 9 deletions + 1 own = 19 expected)")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def rewrite() -> None:
    """A concurrent writer replacing the SHARED index while `--only` commits run."""
    root, env = build()
    stop = threading.Event()

    def writer():
        """What `git add` and `jj` both do: stage this unit's work into the one shared index."""
        n = 0
        while not stop.is_set():
            n += 1
            p = root / f"w{n % 40}.rows"
            p.write_text(f"writer {n}\n")
            subprocess.run(["git", "-C", str(root), "add", "-A"], capture_output=True, env=env)
            time.sleep(0.01)

    t = threading.Thread(target=writer, daemon=True)
    t.start()
    try:
        sweeps = bounded = failed = 0
        for k in range(12):
            mine = f"mine{k}.rows"
            (root / mine).write_text(f"my one path {k}\n")
            subprocess.run(["git", "-C", str(root), "add", "--", mine], capture_output=True, env=env)
            r = subprocess.run(["git", "-C", str(root), "commit", "--only", "-q",
                                "-m", f"one path {k}", "--", mine],
                               capture_output=True, text=True, env=env, check=False)
            if r.returncode:
                failed += 1
                continue
            sha = git(root, "rev-parse", "HEAD", env=env).stdout.strip()
            n = len(git(root, "show", "--numstat", "--format=", sha, env=env).stdout.strip().splitlines())
            if n == 1:
                bounded += 1
            else:
                sweeps += 1
                print(f"    SWEEP {sha[:12]} carried {n} paths")
        print(f"ROUTE REWRITE under a concurrent index writer: SWEEP={sweeps} BOUNDED={bounded} "
              f"commit-rc-nonzero={failed} of 12")
    finally:
        stop.set()
        t.join(timeout=5)
        shutil.rmtree(root, ignore_errors=True)


def bare_isolated() -> None:
    """THE CONTROL FOR THE FIX. The bare commit is the only route that sweeps, so ask the only
    question that matters about a private index: does it stop ANOTHER UNIT'S STAGED WORK from
    riding out in MY commit? Same two units, same lost pathspec, same shared repository; the only
    difference is whether they share one index file."""
    for arm in ("shared", "private"):
        root = Path(tempfile.mkdtemp(prefix=f"bare-{arm}-"))
        try:
            env = dict(os.environ, GIT_INDEX_FILE=str(root / ".git" / (
                "agent-index" if arm == "shared" else "agent-index-mine")))
            git(root, "init", "-q", "-b", "main", env=env)
            git(root, "config", "user.email", "r@x", env=env)
            git(root, "config", "user.name", "r", env=env)
            (root / "base.rows").write_text("base\n")
            git(root, "add", "-A", env=env)
            git(root, "commit", "-qm", "seed", env=env)
            # The other unit stages 9 new paths into WHOSEVER index their env names.
            other_env = dict(env, GIT_INDEX_FILE=str(root / ".git" / (
                "agent-index" if arm == "shared" else "agent-index-theirs")))
            for i in range(9):
                (root / f"theirs{i}.rows").write_text(f"another unit's work {i}\n")
            git(root, "add", "-A", "--", *[f"theirs{i}.rows" for i in range(9)], env=other_env)
            # My unit stages 1 path into MY index and commits with the pathspec LOST.
            (root / "mine.rows").write_text("my one path\n")
            git(root, "add", "--", "mine.rows", env=env)
            r = subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", "bare"],
                               capture_output=True, text=True, env=env, check=False)
            if r.returncode:
                print(f"ISOLATED {arm:8s} rc={r.returncode}: {r.stderr.strip().splitlines()[0]}")
                continue
            sha = git(root, "rev-parse", "HEAD", env=env).stdout.strip()
            carried = git(root, "show", "--name-only", "--format=", sha, env=env).stdout.split()
            theirs = [c for c in carried if c.startswith("theirs")]
            print(f"ISOLATED {arm:8s} my bare commit carried {len(carried)} paths, "
                  f"{len(theirs)} of them the other unit's "
                  f"({'SWEEP' if theirs else 'ISOLATED'})")
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    bare()
    rewrite()
    bare_isolated()
