#!/usr/bin/env python3
"""Deterministic reproduction of the index reset, isolated per scenario.

Each scenario builds a fresh colocated repo with the extension's bundled `jj`
(the same engine its `branching server` runs), then exercises one invoker and
records whether `.git/index`'s staged set and `.git/HEAD` move.

The hazard is the mix: `git add` writes the shared `.git/index`, then ANY `jj`
operation that creates or exports commits rewrites it relative to a new HEAD.
"""
import os
import shutil
import subprocess
import tempfile

JJ = ("/Users/cyberistic/.vscode/extensions/visualjj.visualjj-0.35.4-darwin-arm64"
      "/dist/bin/jj")
BASE = os.path.join(tempfile.gettempdir(), "opencode", "jjhazard-scenarios")
ENV = dict(os.environ, GIT_AUTHOR_NAME="d", GIT_AUTHOR_EMAIL="d@e",
           GIT_COMMITTER_NAME="d", GIT_COMMITTER_EMAIL="d@e")


def git(cwd, *args):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, env=ENV)
    return p.returncode, p.stdout.strip()


def jj(cwd, *args):
    p = subprocess.run([JJ, *args], cwd=cwd, capture_output=True, text=True, env=ENV)
    return p.returncode, (p.stdout + p.stderr).strip()


def setup(name):
    d = os.path.join(BASE, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    git(d, "init", "-q")
    open(os.path.join(d, "base.rows"), "w").write("base\n")
    git(d, "add", "base.rows")
    git(d, "commit", "-q", "-m", "base")
    jj(d, "git", "init", "--colocate")
    return d


def probe(d):
    _, head = git(d, "rev-parse", "HEAD")
    _, staged = git(d, "diff", "--cached", "--name-only")
    _, reflog = git(d, "log", "-g", "--oneline", "-1")
    return head[:12], sorted(line for line in staged.splitlines() if line), reflog


def stage(d, fname):
    open(os.path.join(d, fname), "w").write("x\n")
    git(d, "add", fname)


def scenario(label, unit_git_commit, invoker):
    d = setup(label.replace(" ", "_"))
    if unit_git_commit:
        stage(d, "pre.rows")
        git(d, "commit", "-q", "-m", "unit git commit")
    stage(d, "change.rows")
    b = probe(d)
    jj(d, *invoker)
    a = probe(d)
    moved = "RESET" if a[1] != b[1] or a[0] != b[0] else "no-op"
    print(f"{label:38} staged {len(b[1])}->{len(a[1])}  HEAD {b[0]}->{a[0]}  {moved}")
    print(f"{'':38} reflog after: {a[2]}")
    return moved


def main():
    print("scenario                               result")
    print("-" * 78)
    scenario("git add; jj commit", False, ["commit", "-m", "jj"])
    scenario("git add; jj branching snapshot", False, ["branching", "snapshot"])
    scenario("git add; jj status", False, ["status"])
    scenario("unit git commit; git add; jj snapshot", True, ["branching", "snapshot"])
    scenario("unit git commit; git add; jj commit", True, ["commit", "-m", "jj"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
