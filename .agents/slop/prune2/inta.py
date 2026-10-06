#!/usr/bin/env python
"""Discover the intent-to-add payload: files that exist on disk, are in the index
(git ls-files), but have NO blob in HEAD. That is the shape the last prune deleted
(frozen copies). Also classify untracked and in-HEAD. Emits .rows. Python only."""
import os, subprocess, collections

SLOP = ".agents/slop"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True).stdout


def main():
    head = set()
    for rec in git("ls-tree", "-r", "-z", "HEAD").split(b"\0"):
        if rec:
            head.add(rec.split(b"\t", 1)[1].decode())
    index = set(p for p in git("ls-files", "-z").split(b"\0") if p)
    index = set(p.decode() for p in index)

    stats = collections.defaultdict(lambda: collections.Counter())
    exts = collections.defaultdict(lambda: collections.Counter())
    for dp, dn, fn in os.walk(SLOP):
        for f in fn:
            fp = os.path.join(dp, f)
            if os.path.islink(fp):
                continue
            try:
                size = os.path.getsize(fp)
            except OSError:
                continue
            top = os.path.relpath(fp, SLOP).split(os.sep)[0]
            if fp in head:
                status = "IN_HEAD"
            elif fp in index:
                status = "INDEX_NOT_HEAD"
            else:
                status = "UNTRACKED"
            stats[top][status] += size
            stats[top][status + "_n"] += 1
    rows = sorted(stats.items(), key=lambda kv: -kv[1]["INDEX_NOT_HEAD"])
    print("dir\tinta_bytes\tinta_n\tuntracked_bytes\tinhead_bytes\tinhead_n")
    for top, c in rows[:25]:
        if c["INDEX_NOT_HEAD"] == 0 and c["UNTRACKED"] == 0:
            continue
        print(f"{top}\t{c['INDEX_NOT_HEAD']}\t{c['INDEX_NOT_HEAD_n']}\t"
              f"{c['UNTRACKED']}\t{c['IN_HEAD']}\t{c['IN_HEAD_n']}")
    ti = sum(c["INDEX_NOT_HEAD"] for c in stats.values())
    tn = sum(c["INDEX_NOT_HEAD_n"] for c in stats.values())
    print(f"# TOTAL index-not-head: {ti} B = {ti/1e6:.1f} MB across {tn} files")


if __name__ == "__main__":
    main()
