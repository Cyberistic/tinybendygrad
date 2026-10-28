#!/usr/bin/env python3
"""at.py -- THE CONSTRUCTS OF A TARGET FILE, BY LINE.  The lookup the gate itself uses.

Usage:  at.py <rel> <line> [<line> ...]
        at.py --sym <rel> <name> [...]     # where is a name DECLARED

`rel` is relative to `tinybendygrad/`.
"""
from __future__ import annotations
import os, re, sys

PORT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tinybendygrad"))
BEND_DECL = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")
BEND_VARIANT = re.compile(r"^\s+([A-Z][A-Za-z0-9_]*)\{")


def body(rel):
    p = os.path.join(PORT, rel)
    return open(p, encoding="utf-8").read().split("\n")


def constructs(rel):
    b = body(rel)
    out = []
    decls = [(i, BEND_DECL.match(l).group(1)) for i, l in enumerate(b, 1) if BEND_DECL.match(l)]
    for k, (decl, name) in enumerate(decls):
        nxt = decls[k + 1][0] if k + 1 < len(decls) else len(b) + 1
        end = decl
        for j in range(decl, nxt - 1):
            if b[j].strip() and not b[j].startswith(" "):
                break
            if b[j].strip():
                end = j + 1
        start = decl
        j = decl - 2
        while j >= 0 and b[j].lstrip().startswith("#"):
            start = j + 1
            j -= 1
        out.append((name, decl, start, end))
    in_type = False
    for i, raw in enumerate(b, 1):
        if raw.startswith("type ") and " is" in raw:
            in_type = True
            continue
        if raw and not raw.startswith(" "):
            in_type = False
            continue
        if in_type:
            m = BEND_VARIANT.match(raw)
            if m:
                out.append((m.group(1), i, i, i))
    return out


def main():
    if sys.argv[1] == "--sym":
        rel = sys.argv[2]
        cs = constructs(rel)
        for name in sys.argv[3:]:
            hits = [(d, s, e) for (n, d, s, e) in cs if n == name]
            print(f"{rel} {name} -> {hits}")
        return 0
    rel = sys.argv[1]
    cs = constructs(rel)
    for line in [int(x) for x in sys.argv[2:]]:
        best = None
        for (n, d, s, e) in cs:
            if s <= line <= e:
                best = (n, d, s, e)
        b = body(rel)
        print(f"--- {rel}:{line}")
        for i in range(max(1, line - 4), min(len(b), line + 4) + 1):
            mark = ">>" if i == line else "  "
            print(f"  {mark} {i}: {b[i-1]}")
        print(f"  CONSTRUCT: {best}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
