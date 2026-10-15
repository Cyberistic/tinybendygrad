#!/usr/bin/env python3
"""Per-file roll-up of `signals.rows` + `strlists.rows`, so every one of the discovered `*.py`
gets exactly ONE row. The classification column is a MECHANICAL default; `findings.rows` is the
hand-verified one and every row in it cites a file:line a reader can open.

usage: .venv/bin/python .agents/slop/shapecensus/rollup.py
"""
from __future__ import annotations

import collections
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main() -> int:
    sig = collections.defaultdict(collections.Counter)
    for line in (HERE / "signals.rows").read_text().splitlines():
        f, k = line.split("\t")[:2]
        sig[f][k] += 1
    lit = collections.defaultdict(list)
    for line in (HERE / "strlists.rows").read_text().splitlines():
        f, _, name, bind, it, _ = line.split("\t")[:6]
        lit[f].append(f"{name}@{bind}")
    files = sorted(sig)
    for f in files:
        counts = " ".join(f"{k}:{v}" for k, v in sorted(sig[f].items()))
        print(f"{f}\t{len(sig[f])}\t{counts}\t{','.join(lit.get(f, []))[:150]}")
    print(f"FILES\t{len(files)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())