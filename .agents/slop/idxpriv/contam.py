#!/usr/bin/env python3
"""contam.py -- DOES `--only` BOUND A CONTAMINATED INDEX?  THE DECISIVE EXPERIMENT.

race.py showed 36 concurrent one-path commits on a SHARED index carry exactly one path each, so
concurrency alone does not reproduce the outage's 435-file sweep. So the sweep's input has to come
from somewhere else: the index itself, contaminated the way index-arm-gate.py names its shapes.

THE SHAPES, and where each one is planted from:
  FOREIGN-ADD   staged, not in HEAD          -- one unit's `git add` of new work
  DELETION      in HEAD, `git rm --cached`    -- the shape index-arm-gate calls destructive
  STALE         in HEAD, different blob       -- a staged modification
  INTENT        `git add --intent-to-add`     -- what `jj status` writes in a colocated repo

Each arm contaminates ONE shape, then commits ONE path with `--only` and prints the commit's path
count. A shape that `--only` carries is a route from the index into the commit; a shape it does not
is a shape `--only` already blocks.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

NFILES = 200
MINE = "mine.rows"


def git(root, *args, env, check=True):
    p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True,
                       env=env, check=False)
    if check and p.returncode:
        raise RuntimeError(f"git {' '.join(args)} rc={p.returncode}: {p.stderr.strip()}")
    return p


def build() -> Path:
    root = Path(tempfile.mkdtemp(prefix="contam-"))
    env = dict(os.environ, GIT_INDEX_FILE=str(root / ".git" / "probe-index"))
    git(root, "init", "-q", "-b", "main", env=env)
    git(root, "config", "user.email", "r@x", env=env)
    git(root, "config", "user.name", "r", env=env)
    for i in range(NFILES):
        (root / f"f{i:03d}.rows").write_text(f"base {i}\n")
    git(root, "add", "-A", env=env)
    git(root, "commit", "-qm", "seed", env=env)
    return root


def arm(shape: str) -> None:
    root = build()
    try:
        env = dict(os.environ, GIT_INDEX_FILE=str(root / ".git" / "probe-index"))
        if shape == "FOREIGN-ADD":
            for i in range(5):
                (root / f"other{i}.rows").write_text(f"someone else's work {i}\n")
            git(root, "add", "--", "other0.rows", "other1.rows", "other2.rows",
                "other3.rows", "other4.rows", env=env)
        elif shape == "DELETION":
            git(root, "rm", "--cached", "-q", "--", "f000.rows", "f001.rows", "f002.rows",
                "f003.rows", "f004.rows", env=env)
        elif shape == "STALE":
            for i in range(5):
                (root / f"f{i:03d}.rows").write_text(f"STALE WRITE {i}\n")
            git(root, "add", "--", *[f"f{i:03d}.rows" for i in range(5)], env=env)
        elif shape == "INTENT":
            for i in range(5):
                (root / f"fresh{i}.rows").write_text(f"fresh work {i}\n" * 100)
            git(root, "add", "--intent-to-add", "--", *[f"fresh{i}.rows" for i in range(5)], env=env)
        # My own work, exactly as AGENTS.md prescribes: add one path, commit --only that path.
        (root / MINE).write_text("my one path\n")
        git(root, "add", "--", MINE, env=env)
        r = git(root, "commit", "--only", "-m", f"one path over {shape}", "--", MINE,
                env=env, check=False)
        if r.returncode:
            print(f"SHAPE {shape:12s} commit rc={r.returncode}  "
                  f"{r.stderr.strip().splitlines()[0] if r.stderr.strip() else ''}")
            return
        sha = git(root, "rev-parse", "HEAD", env=env).stdout.strip()
        n = len(git(root, "show", "--numstat", "--format=", sha, env=env).stdout.strip().splitlines())
        carried = git(root, "show", "--name-only", "--format=", sha, env=env).stdout.split()
        verdict = "BOUNDED (1 path)" if n == 1 else f"*** SWEEP: {n} paths ***"
        print(f"SHAPE {shape:12s} {verdict:22s} carried: {', '.join(carried[:6])}")
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    for s in ("FOREIGN-ADD", "DELETION", "STALE", "INTENT"):
        arm(s)
