#!/usr/bin/env python3
"""find.py -- WHERE IS A CONSTRUCT DECLARED NOW?  A lookup over the port's own corpus.

Usage:  find.py <target-rel-path> <name> [<name> ...]
        find.py --at <target-rel-path> <line>     # what is AT that line

The population is DISCOVERED (os.walk), never named.
"""
from __future__ import annotations
import os, re, sys

PORT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tinybendygrad"))

BEND_DECL = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")


def bodies():
    out = {}
    for root, _d, files in os.walk(PORT):
        for f in files:
            if f.endswith(".bend"):
                p = os.path.join(root, f)
                out[os.path.relpath(p, PORT)] = open(p, encoding="utf-8").read().split("\n")
    return out


def main() -> int:
    B = bodies()
    if sys.argv[1] == "--at":
        rel, line = sys.argv[2], int(sys.argv[3])
        body = B[rel]
        decls = [(i, BEND_DECL.match(l).group(1)) for i, l in enumerate(body, 1) if BEND_DECL.match(l)]
        best = None
        for i, n in decls:
            if i <= line:
                best = (i, n)
            else:
                break
        print("at", rel, line, "->", best)
        # also the raw text
        for i in range(max(1, line - 3), min(len(body), line + 3) + 1):
            print(f"  {i}: {body[i-1]}")
        return 0
    rel = sys.argv[1]
    body = B[rel]
    for name in sys.argv[2:]:
        hits = [(i, BEND_DECL.match(l).group(1)) for i, l in enumerate(body, 1)
                if BEND_DECL.match(l) and BEND_DECL.match(l).group(1) == name]
        print(rel, name, hits)
    return 0


if __name__ == "__main__":
    sys.exit(main())
