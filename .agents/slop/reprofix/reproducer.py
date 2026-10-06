#!/usr/bin/env python3
"""The minimal reproducer for `D0-coverage-census.txt: 2 runs DIFFER`, with NO `bend`.

It reads the op SETS out of the canonical files `runs/graphcmp/D` ALREADY holds -- one wire
row per node, so `novel = py_ops ^ bend_ops` is recomputed here exactly as
`graphcmp-oracle.py:233` computes it -- and renders `novel` BOTH ways:

    RAW     repr(novel)          <- what the oracle printed before commit 46c52f30d
    SORTED  repr(sorted(novel))  <- what it prints now

It prints one sha256 per rendering. Run twice under two `PYTHONHASHSEED` values: RAW's hash
moves with the seed (a `set` of strings iterates in hash order) and SORTED's does not. That
is the whole finding -- a SEED fixes the order on one interpreter, a SORT fixes it on all.

    for s in 1 2; do PYTHONHASHSEED=$s .venv/bin/python .agents/slop/reprofix/reproducer.py; done
"""
from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "runs/graphcmp/D"
sys.path.insert(0, str(ROOT / ".agents/slop"))
import graphcmp as G  # noqa: E402

GRAPHS = ("allred", "cdiv", "flip", "late")


def ops(path: Path) -> set[str]:
    txt = path.read_text()
    return {G.unchunks(ln)[1] for ln in txt.splitlines() if ln.strip()}


def main() -> int:
    raw, srt = [], []
    for g in GRAPHS:
        novel = ops(D / f"D2-canon-py-{g}.txt") ^ ops(D / f"D2-canon-bend-{g}.txt")
        raw.append(f"  {g:<7} {novel}")
        srt.append(f"  {g:<7} {sorted(novel)}")
    h = lambda ls: hashlib.sha256("\n".join(ls).encode()).hexdigest()
    print(f"PYTHONHASHSEED={os.environ.get('PYTHONHASHSEED', 'unset')}")
    print(f"  RAW    sha256={h(raw)}")
    print(f"  SORTED sha256={h(srt)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
