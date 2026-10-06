#!/usr/bin/env python3
"""Demonstrate, deterministically and in a throwaway repo, what one tick of the
visualjj `jj branching server` does to a colocated git index.

The real server cannot be triggered on demand (its stdin/stdout are VS Code's,
it holds no listening socket). So this runs the SAME engine — the extension's
bundled `jj` — with the SAME entry point the server's snapshot loop uses
(`jj branching snapshot`), against a fresh colocated repo, and records the index
and HEAD before and after. Nothing here touches the real repository.
"""
import os
import shutil
import subprocess
import tempfile

JJ = ("/Users/cyberistic/.vscode/extensions/visualjj.visualjj-0.35.4-darwin-arm64"
      "/dist/bin/jj")
DEMO = os.path.join(tempfile.gettempdir(), "opencode", "jjhazard-demo")


def run(*args, cwd=DEMO, env=None):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=env)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def state(label):
    _, head, _ = run("git", "rev-parse", "HEAD")
    _, staged, _ = run("git", "diff", "--cached", "--name-only")
    _, reflog, _ = run("git", "log", "-g", "--oneline", "-1")
    count = len([line for line in staged.splitlines() if line])
    print(f"{label}: STAGED={count} HEAD={head[:12]}")
    for line in staged.splitlines():
        print(f"    staged: {line}")
    return count, head, reflog


def main():
    shutil.rmtree(DEMO, ignore_errors=True)
    os.makedirs(DEMO)
    env = dict(os.environ, GIT_AUTHOR_NAME="demo", GIT_AUTHOR_EMAIL="d@e",
               GIT_COMMITTER_NAME="demo", GIT_COMMITTER_EMAIL="d@e")

    run("git", "init", "-q", env=env)
    with open(os.path.join(DEMO, "tracked.rows"), "w") as fh:
        fh.write("base\n")
    run("git", "add", "tracked.rows", env=env)
    run("git", "commit", "-q", "-m", "base", env=env)

    rc, out, err = run(JJ, "git", "init", "--colocate", env=env)
    print(f"jj git init --colocate rc={rc} {out} {err}".strip())

    with open(os.path.join(DEMO, "new.rows"), "w") as fh:
        fh.write("new\n")
    run("git", "add", "new.rows", env=env)
    before = state("BEFORE (after `git add new.rows`)")

    # Make the worktree dirty so jj has something to snapshot.
    with open(os.path.join(DEMO, "tracked.rows"), "a") as fh:
        fh.write("dirty\n")

    rc, out, err = run(JJ, "branching", "snapshot", env=env)
    print(f"jj branching snapshot rc={rc} out={out[:200]} err={err[:200]}".strip())

    after = state("AFTER  (after one `jj branching snapshot` — a server tick)")
    print(f"index-reset: staged {before[0]} -> {after[0]}, HEAD {before[1][:12]} -> {after[1][:12]}")
    print(f"reflog action after tick: {after[2]}")
    print("VERDICT: " + ("INDEX-RESET-REPRODUCED" if after[0] != before[0] else "NO-RESET"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
