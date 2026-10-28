#!/usr/bin/env python3
"""suggest.py -- FOR EACH SLICE ROW, THE TARGET'S CONSTRUCTS NEAR THE CITED LINE.

Reads the slice rows and prints, per row, the citing line in full, the target's
constructs whose SPAN contains or is near the cited line, and the names the citing
line's own text mentions (so a choice can be made).
"""
from __future__ import annotations
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "tinybendygrad"))
sys.path.insert(0, HERE)
from at import constructs, body  # noqa: E402

SLICE = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/bare.rows"


def main():
    only = set(sys.argv[1:])
    rows = list(csv.DictReader(open(SLICE), delimiter="\t"))
    for r in rows:
        if only and r["rel"] not in only:
            continue
        rel = r["rel"]
        tgt = r["target"]
        lo, hi = int(r["lo"]), int(r["hi"])
        print("=" * 100)
        print(f"REL {rel}:{r['at']}  ->  {r['subject']}:{lo}" + (f"-{hi}" if hi != lo else ""))
        print(f"  LINE: {r['line']}")
        print(f"  TIER: {r['tier']}  AT_LINE: {r['at_line']}")
        if not tgt:
            print("  TARGET: (none)")
            continue
        tgt = tgt[len("tinybendygrad/"):] if tgt.startswith("tinybendygrad/") else tgt
        if not os.path.exists(os.path.join(PORT, tgt)):
            print(f"  TARGET: (not a port file: {tgt})")
            continue
        cs = constructs(tgt)
        near = [(n, d, s, e) for (n, d, s, e) in cs if s <= hi + 12 and e >= lo - 12]
        print(f"  TARGET CONSTRUCTS NEAR:")
        for (n, d, s, e) in near:
            print(f"    {n}  decl={d} span={s}-{e}   {'<-- SPAN CONTAINS CITED LINE' if s <= lo <= e else ''}")
        b = body(tgt)
        print(f"  TARGET TEXT {lo}-{hi}:")
        for i in range(max(1, lo - 2), min(len(b), hi + 2) + 1):
            print(f"    {i}: {b[i-1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
