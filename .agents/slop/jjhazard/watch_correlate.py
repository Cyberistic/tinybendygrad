#!/usr/bin/env python3
"""Correlate index writes with jj's own operation writes and with git activity.

Timestamps every writer that could touch `.git/index`:
  - the index itself (inode/size/mtime)
  - the newest file in `.jj/repo/op_store/operations` (jj snapshots/imports)
  - `.jj/working_copy/tree_state`
  - the number of `git`/`jj` processes alive in this repo at sample time

A sample where the index inode/mtime advances AND the op-store mtime advances
AND no git process is running is a jj snapshot: the extension's server.
A sample where the index advances and a git process is running is a unit.

usage: watch_correlate.py [seconds] [interval_seconds]
"""
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GIT = os.path.join(ROOT, ".git")
OPS = os.path.join(ROOT, ".jj", "repo", "op_store", "operations")
TS = os.path.join(ROOT, ".jj", "working_copy", "tree_state")


def mtime_ns(path):
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return 0


def newest_mtime(d):
    try:
        names = os.listdir(d)
    except OSError:
        return 0
    return max((mtime_ns(os.path.join(d, n)) for n in names), default=0)


def git_procs():
    out = subprocess.run(["ps", "-Ao", "pid=,command="], capture_output=True, text=True).stdout
    n = 0
    for line in out.splitlines():
        if ROOT in line and ("/git " in line or " git " in line or "/jj " in line or " jj " in line):
            if "watch_correlate" in line or "branching server" in line:
                continue
            n += 1
    return n


def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
    print("t_s\tidx_ino\tidx_size\tidx_mtime_ns\top_mtime_ns\tts_mtime_ns\thead\tgit_procs")
    t0 = time.monotonic()
    while True:
        elapsed = time.monotonic() - t0
        st = os.stat(os.path.join(GIT, "index"))
        try:
            head = open(os.path.join(GIT, "HEAD")).read().strip()[:12]
        except OSError:
            head = "?"
        row = [f"{elapsed:.1f}", st.st_ino, st.st_size, st.st_mtime_ns,
               newest_mtime(OPS), mtime_ns(TS), head, git_procs()]
        print("\t".join(str(x) for x in row), flush=True)
        if elapsed >= secs:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
