#!/usr/bin/env python3
"""prune3/delete.py -- delete an explicit list of files, report st_blocks freed.

Guards: every path must (a) exist, (b) end in `.bin`, (c) NOT be tracked in HEAD,
(d) be matched by a `.gitignore` rule. Any failure aborts before unlinking.

    .venv/bin/python .agents/slop/prune3/delete.py PATH...
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def tracked(path: Path) -> bool:
    return subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", str(path)],
        capture_output=True).returncode == 0


def ignored(path: Path) -> bool:
    return subprocess.run(
        ["git", "check-ignore", "-q", "--", str(path)],
        capture_output=True).returncode == 0


def main(argv: list[str]) -> int:
    paths = [Path(a) for a in argv]
    for p in paths:
        if not p.is_file():
            print(f"ABORT not-a-file: {p}")
            return 1
        if p.suffix != ".bin":
            print(f"ABORT not-.bin: {p}")
            return 1
        if tracked(p):
            print(f"ABORT tracked-in-HEAD: {p}")
            return 1
        if not ignored(p):
            print(f"ABORT not-ignored: {p}")
            return 1
    freed = count = 0
    for p in paths:
        freed += os.lstat(p).st_blocks * 512
        count += 1
        os.unlink(p)
        print(f"deleted {p}")
    print(f"TOTAL freed {freed} bytes over {count} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
