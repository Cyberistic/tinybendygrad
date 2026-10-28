#!/usr/bin/env python3
"""where.py -- WHERE IS A CONSTRUCT DECLARED NOW, in ANY port file?

Usage:  where.py <name> [<name> ...]     # search every `.bend` under tinybendygrad/
"""
from __future__ import annotations
import os, re, sys

PORT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tinybendygrad"))
BEND_DECL = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")
BEND_VARIANT = re.compile(r"^\s+([A-Z][A-Za-z0-9_]*)\{")


def main():
    names = set(sys.argv[1:])
    for root, _d, files in os.walk(PORT):
        for f in sorted(files):
            if not f.endswith(".bend"):
                continue
            p = os.path.join(root, f)
            rel = os.path.relpath(p, PORT)
            body = open(p, encoding="utf-8").read().split("\n")
            in_type = False
            for i, raw in enumerate(body, 1):
                m = BEND_DECL.match(raw)
                if m and m.group(1) in names:
                    print(f"{rel}:{i}  {m.group(1)}")
                    names.discard(m.group(1))
                if raw.startswith("type ") and " is" in raw:
                    in_type = True
                    continue
                if raw and not raw.startswith(" "):
                    in_type = False
                    continue
                if in_type:
                    mv = BEND_VARIANT.match(raw)
                    if mv and mv.group(1) in names:
                        print(f"{rel}:{i}  {mv.group(1)}")
                        names.discard(mv.group(1))
    if names:
        print(f"NOT FOUND: {sorted(names)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
