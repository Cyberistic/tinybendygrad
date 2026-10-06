#!/usr/bin/env python3
"""Sample git index + jj working-copy state on a timer, with no git/jj command.

Reads ONLY filesystem metadata (stat) and .git/HEAD bytes. Never invokes git or
jj, so any change it observes is produced by another process.

usage: watch_index.py [seconds] [interval_seconds]
prints TSV rows: t_s  index_ino  index_size  index_mtime_ns  lock  head
"""
import os
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GIT = os.path.join(ROOT, ".git")
WC = os.path.join(ROOT, ".jj", "working_copy")

def sample():
    out = {}
    for name, path in (
        ("index", os.path.join(GIT, "index")),
        ("head", os.path.join(GIT, "HEAD")),
        ("tree_state", os.path.join(WC, "tree_state")),
        ("checkout", os.path.join(WC, "checkout")),
    ):
        try:
            st = os.stat(path)
            out[name] = (st.st_ino, st.st_size, st.st_mtime_ns)
        except FileNotFoundError:
            out[name] = (0, 0, 0)
    out["lock"] = os.path.exists(os.path.join(GIT, "index.lock"))
    return out

def main():
    secs = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
    print("t_s\tindex_ino\tindex_size\tindex_mtime_ns\tlock\thead")
    t0 = time.monotonic()
    end = t0 + secs
    while True:
        now = time.monotonic()
        s = sample()
        try:
            head = open(os.path.join(GIT, "HEAD")).read().strip()[:12]
        except OSError:
            head = "?"
        row = [f"{now - t0:.1f}", s["index"][0], s["index"][1], s["index"][2], int(s["lock"]), head]
        print("\t".join(str(x) for x in row), flush=True)
        if now >= end:
            break
        time.sleep(interval)

if __name__ == "__main__":
    main()
