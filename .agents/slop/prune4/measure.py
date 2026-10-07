#!/usr/bin/env python3
"""prune4 measurement. lstat/st_blocks only. NEVER os.path.getsize.

prune2's lesson: getsize follows symlinks and charged a tree 1558 MB that du calls 71 MB.
So: st_blocks*512 (the disk cost du charges), and st_size (apparent size, no following).
Both are lstat values and are identical for symlinks.
"""
import os, sys, json


def walk(root):
    """Yield (path, lstat, kind). Never follows a symlink."""
    st = os.lstat(root)
    yield root, st, "root"
    stack = [root]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except (PermissionError, FileNotFoundError, OSError):
            continue
        for e in entries:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if e.is_symlink():
                yield e.path, st, "symlink"
            elif e.is_dir(follow_symlinks=False):
                yield e.path, st, "dir"
                stack.append(e.path)
            else:
                yield e.path, st, "file"


def measure(root):
    blocks = 0        # du's number
    size = 0          # apparent bytes, symlink target NOT followed
    nfiles = ndirs = nsym = 0
    for path, st, kind in walk(root):
        blocks += st.st_blocks
        size += st.st_size
        if kind == "file":
            nfiles += 1
        elif kind == "dir":
            ndirs += 1
        elif kind == "symlink":
            nsym += 1
    return dict(blocks=blocks, disk_bytes=blocks * 512, size_bytes=size,
                files=nfiles, dirs=ndirs, symlinks=nsym)


def getsize_would_say(root):
    """The wrong measurement, computed, so the report can quote the delta."""
    total = 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for n in filenames:
            p = os.path.join(dirpath, n)
            try:
                total += os.path.getsize(p)
            except OSError:
                pass
    return total


if __name__ == "__main__":
    for root in sys.argv[1:]:
        m = measure(root)
        print(json.dumps({"root": root, **m}))