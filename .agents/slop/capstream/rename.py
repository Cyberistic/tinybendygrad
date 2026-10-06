#!/usr/bin/env python3
"""Rename the reader-free BASENAME-COLLISION `.txt` to `.out`, with `os.rename` (never `git mv`).

The NEITHER group this task names is EMPTY: `sloptxt` already moved all 19 renamable
CAPTURED-STREAM files (verified: `PLAN.tsv` old-set minus its 19 renamed == the fresh 350). So the
only files this unit may move are basename collisions that survived `sloptxt`'s basename reader
test -- a `.txt` whose basename a committed reader names, but only inside ANOTHER directory, so no
reader opens it. Each entry below was confirmed with `git grep -n "gate\\.txt"` over its own
directory (rc=1, no reader) and a full-path grep over non-census committed files.

ADMITTED HAND LIST (doctrine 1c): the two names are here because the test above could not be
stated as a discovery -- "a reader binds the basename to this directory" is not decidable by
regex. The list is two, and `rename.py --dry` prints exactly what it would move.

`.out`, not `.err`: both are captured stdout logs (a `--check-only` run, and a tree/hash banner),
with no traceback and no error headline.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
# (src, reason it is a collision)
MOVES = [
    (".agents/slop/dtypeb/gate.txt",
     "e2e_negctl.sh names `$NC/runs/e2e/gate.txt`; dtypeb/run.py reads gate_fp8.bend, not gate.txt"),
    (".agents/slop/fp8fix/gate.txt",
     "opsbend-milestone.sh names `$RUN/gate.txt`; fp8fix/run.sh reads $T/sweep-*.txt, not gate.txt"),
]


def main():
    dry = "--dry" in sys.argv
    for src, why in MOVES:
        dst = os.path.splitext(src)[0] + ".out"
        assert not os.path.exists(os.path.join(ROOT, dst)), f"collision: {dst} exists"
        assert os.path.exists(os.path.join(ROOT, src)), f"missing: {src}"
        print(f"{'WOULD ' if dry else ''}rename {src} -> {dst}\n    because {why}")
        if not dry:
            os.rename(os.path.join(ROOT, src), os.path.join(ROOT, dst))


if __name__ == "__main__":
    main()
