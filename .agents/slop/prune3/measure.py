#!/usr/bin/env python3
"""prune3/measure.py -- byte totals for a path, by `st_blocks`, lstat-based.

`os.path.getsize` follows a symlink and charges the target's size; this walk does
not. Directories count their own `st_blocks` too, so the total is a `du` number.

    .venv/bin/python .agents/slop/prune3/measure.py PATH...
"""
from __future__ import annotations

import os
import stat
import sys
from pathlib import Path


def walk(root: Path) -> dict[str, int]:
    files = links = dirs = other = 0
    blocks = 0
    for base, subdirs, names in os.walk(root):
        for d in subdirs:
            st = os.lstat(os.path.join(base, d))
            blocks += st.st_blocks
            dirs += 1
        for n in names:
            st = os.lstat(os.path.join(base, n))
            blocks += st.st_blocks
            if stat.S_ISLNK(st.st_mode):
                links += 1
            elif stat.S_ISREG(st.st_mode):
                files += 1
            else:
                other += 1
    return {"bytes": blocks * 512, "files": files, "links": links,
            "dirs": dirs, "other": other}


def main(argv: list[str]) -> int:
    for arg in argv:
        p = Path(arg)
        if not p.exists() and not p.is_symlink():
            print(f"{arg}\tMISSING")
            continue
        if p.is_file() or p.is_symlink():
            st = os.lstat(p)
            print(f"{arg}\t{st.st_blocks * 512}\tbytes\tfile")
            continue
        r = walk(p)
        print(f"{arg}\t{r['bytes']}\tbytes\t{r['files']} files\t{r['links']} links"
              f"\t{r['dirs']} dirs\t{r['other']} other")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
