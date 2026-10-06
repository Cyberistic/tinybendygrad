#!/usr/bin/env python
"""Measure .agents/slop by DISCOVERY: allocated bytes (symlink- and hardlink-aware),
file counts, and the SHAPE of each unit dir (which subdirs hold tree copies, mirrors,
row dumps). Emits .rows, never .txt. Python only; git is the only data source it shells."""
import os, sys, subprocess

ROOT = ".agents/slop"
MARKERS = ("tree", "working", "origin", "plant", "D-live", "runs",
           "artifacts", "fixtures", "pin-tree", "sandbox", ".venv")


def walk_sizes(path):
    """Allocated bytes via st_blocks*512, deduping hardlinks by (dev, ino)."""
    total, nfiles, seen = 0, 0, set()
    for dp, dn, fn in os.walk(path):
        names = list(fn) + [d for d in dn if os.path.islink(os.path.join(dp, d))]
        for name in names:
            fp = os.path.join(dp, name)
            try:
                st = os.lstat(fp)
            except OSError:
                continue
            key = (st.st_dev, st.st_ino)
            if st.st_ino and key in seen:
                continue
            seen.add(key)
            total += st.st_blocks * 512
            nfiles += 1
    return total, nfiles


def shape(path):
    names = set(os.listdir(path))
    flags = [m + "/" for m in MARKERS if m in names]
    exts = {}
    for dp, dn, fn in os.walk(path):
        for f in fn:
            e = os.path.splitext(f)[1] or "(noext)"
            exts[e] = exts.get(e, 0) + 1
    top = sorted(exts.items(), key=lambda kv: -kv[1])[:6]
    return ",".join(flags), ",".join("%s:%d" % kv for kv in top)


def main():
    dirs = []
    for name in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, name)
        if os.path.isdir(p):
            b, n = walk_sizes(p)
            dirs.append((b, n, name))
    dirs.sort(reverse=True)
    total = sum(d[0] for d in dirs)
    print(f"# measured {len(dirs)} unit dirs; total {total} B = {total/1e6:.1f} MB")
    print("bytes\tfiles\tdir\tshape\ttop_ext")
    for b, n, name in dirs[:15]:
        flags, exts = shape(os.path.join(ROOT, name))
        print(f"{b}\t{n}\t{name}\t{flags}\t{exts}")
    tb, tn = walk_sizes(ROOT)
    print(f"# whole {ROOT}: {tb} B = {tb/1e6:.1f} MB across {tn} entries (hardlink-deduped)")


if __name__ == "__main__":
    main()
