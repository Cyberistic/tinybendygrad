#!/usr/bin/env python3
"""Post-change measurement: per affected directory, tracked before vs now, and
what the freed set did. before.lsfiles is the pre-change `git ls-files` dump.
Read-only except reading the index; does not touch the tree.
"""
import collections
import os
import subprocess


def ls_files(path=None):
    cmd = ["git", "ls-files", "-z"]
    if path:
        cmd += ["--", path]
    out = subprocess.run(cmd, capture_output=True, text=True,
                         check=True).stdout
    return set(p for p in out.split("\0") if p)


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True, check=True).stdout.strip()
    with open(os.path.join(root, ".agents/slop/gitignore/before-lsfiles.rows")) as fh:
        before = set(l for l in fh.read().splitlines() if l)
    now = ls_files()
    print(f"total_before={len(before)} total_now={len(now)} delta={len(now)-len(before)}")
    added = now - before
    removed = before - now
    print(f"added={len(added)} removed={len(removed)}")
    print(f"added_under_runs={sum(1 for p in added if '/runs/' in p or p.startswith('runs/'))}")
    print(f"added_not_runs={len(added) - sum(1 for p in added if '/runs/' in p or p.startswith('runs/'))}")

    # per affected directory (the freed groups), tracked before vs now
    dirs = [
        ".agents/slop/e2epy/fixtures",
        ".agents/slop/checkshells/runs",
        ".agents/slop/figure2/plant",
        ".agents/slop/differverdict/pristine",
        ".agents/slop/figurefix",
        ".agents/slop/declared473",
        ".agents/slop/corpuswire",
        "runs",
    ]
    for d in dirs:
        b = sum(1 for p in before if p == d or p.startswith(d + "/"))
        n = sum(1 for p in now if p == d or p.startswith(d + "/"))
        print(f"dir={d} tracked_before={b} tracked_now={n}")


if __name__ == "__main__":
    main()
