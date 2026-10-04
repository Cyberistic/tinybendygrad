#!/usr/bin/env python3
"""One repo-wide md5 index, so "is this the only copy?" is a lookup and not a re-scan.

Re-measuring by re-hashing the tree per question is how a 10-minute answer becomes a
10-minute answer times N. This walks once, skips `references/` and `.venv` (vendored and
untracked-by-intent), and prints every blob whose bytes occur EXACTLY ONCE anywhere in the
repo -- which is the only definition of "somebody's only copy" that survives a copy-paste.

    usage: onlycopies.py [--min-bytes N]
"""
from __future__ import annotations
import collections
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SKIP = {"references", ".venv", ".git", "node_modules", "__pycache__"}


def main(argv: list[str]) -> int:
    minb = 1024
    if "--min-bytes" in argv:
        minb = int(argv[argv.index("--min-bytes") + 1])

    where: dict[str, list[tuple[str, int]]] = collections.defaultdict(list)
    for dirpath, dirnames, files in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in files:
            p = os.path.join(dirpath, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            try:
                sz = os.path.getsize(p)
            except OSError:
                continue
            if sz < minb:
                continue
            h = hashlib.md5()
            try:
                with open(p, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        h.update(chunk)
            except OSError:
                continue
            where[h.hexdigest()].append((os.path.relpath(p, ROOT), sz))

    uniq = {h: v for h, v in where.items() if len(v) == 1}
    tot = sum(v[0][1] for v in uniq.values())
    print(f"# distinct blobs {len(where)}   occurring exactly once {len(uniq)}   "
          f"bytes in unique-only blobs {tot/1048576:.1f} MB")
    print(f"# SKIPPED dirs: {', '.join(sorted(SKIP))}\n")
    for h, v in sorted(uniq.items(), key=lambda kv: -kv[1][0][1]):
        print(f"{h[:12]} {v[0][1]:10d}  {v[0][0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))