#!/usr/bin/env python3
"""Deterministic hazard reproduction.

1. stage a probe file with `git add`
2. record `git diff --cached --name-only` count, HEAD, index stat
3. change a file (NOT a git command) so the snapshot loop has something to see
4. poll without running jj: index stat, HEAD, cached count
5. report when / whether the staged set and HEAD move

Reads use `git --no-optional-locks` so the probe never writes the index itself.
"""
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PROBE = ".agents/slop/jjhazard/probe.rows"
SCRATCH = ".agents/slop/jjhazard/scratch.rows"


def git(*args, index=True):
    cmd = ["git", "--no-optional-locks", *args]
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)


def index_stat():
    st = os.stat(os.path.join(ROOT, ".git", "index"))
    return st.st_ino, st.st_size, st.st_mtime_ns


def head():
    return git("rev-parse", "HEAD").stdout.strip()[:12]


def staged():
    out = git("diff", "--cached", "--name-only").stdout
    names = [line for line in out.splitlines() if line]
    return names


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 120
    os.makedirs(os.path.join(ROOT, os.path.dirname(PROBE)), exist_ok=True)
    with open(os.path.join(ROOT, PROBE), "w") as fh:
        fh.write("probe row\n")
    git("add", "--", PROBE)
    names = staged()
    h0 = head()
    s0 = index_stat()
    print(f"T0 staged={len(names)} paths={names} HEAD={h0} index={s0}", flush=True)

    # Change a file so the snapshot loop sees a dirty worktree. Not a git command.
    baseline = "0"
    for i in range(1, 4):
        time.sleep(1)
        with open(os.path.join(ROOT, SCRATCH), "w") as fh:
            fh.write(f"scratch {i}\n")
    print(f"T0+3s touched {SCRATCH}", flush=True)

    t0 = time.monotonic()
    last = None
    while True:
        elapsed = time.monotonic() - t0
        s = index_stat()
        h = head()
        n = len(staged())
        row = (f"{elapsed:5.1f}", n, h, s[0], s[1])
        print("\t".join(str(x) for x in row), flush=True)
        if n != len(names) or h != h0:
            change = []
            if n != len(names):
                change.append(f"staged {len(names)}->{n}")
            if h != h0:
                change.append(f"HEAD {h0}->{h}")
            print("CHANGE DETECTED: " + "; ".join(change), flush=True)
            break
        if elapsed >= secs:
            print("NO CHANGE within window", flush=True)
            break
        time.sleep(5)


if __name__ == "__main__":
    main()
