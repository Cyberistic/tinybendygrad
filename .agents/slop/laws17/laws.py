#!/usr/bin/env python3
"""Enumerate the law proof backlog BY DISCOVERY, in the BOOK's own terms.

A `law NAME:` declares an obligation; a `def NAME(...)` discharges it.  Bend
discharges a law by a def of the same name ANYWHERE in the book (the import
closure of the root file), so the population of a gate is (laws in the closure)
and the filled set is (defs in the closure), matched by the def's LAST dotted
component.

    usage: .venv/bin/python .agents/slop/laws17/laws.py [ROOT ...]

With no ROOT, reports every book in the tree plus the three named gates.  Prints
one row per book: `open/filled/total  root`.  NO bend is run; this is the
discovery instrument the report compares the gate's number against.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TINY = os.path.join(REPO, "tinybendygrad")

LAW = re.compile(r"^law\s+(\w+)\s*:")
IMP = re.compile(r"^import\s+(\S+?)(?:\s+as\s+(\w+))?\s*$")
DEF = re.compile(r"^def\s+([\w.]+)\s*[(+:]")


def bend_files():
    out = []
    for dirpath, _, names in os.walk(TINY):
        for n in names:
            if n.endswith(".bend"):
                out.append(os.path.join(dirpath, n))
    return sorted(out)


def parse(path):
    laws, defs, imps = [], set(), []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = LAW.match(line)
            if m:
                laws.append(m.group(1))
            m = DEF.match(line)
            if m:
                defs.add(m.group(1).rsplit(".", 1)[-1])
            m = IMP.match(line)
            if m and m.group(1).startswith("."):
                imps.append(os.path.normpath(os.path.join(os.path.dirname(path), m.group(1))))
    return laws, defs, imps


def closure(root):
    seen, todo = set(), [os.path.abspath(root)]
    while todo:
        p = todo.pop()
        if p in seen or not p.endswith(".bend"):
            continue
        seen.add(p)
        # Base and other non-relative imports are external; skip unresolved.
        if not os.path.exists(p):
            seen.discard(p)
            continue
        _, _, imps = parse(p)
        todo.extend(imps)
    return seen


def book(root):
    files = closure(root)
    laws, defs = [], set()
    for p in sorted(files):
        fl, fd, _ = parse(p)
        laws.extend(fl)
        defs |= fd
    opened = [l for l in laws if l not in defs]
    return len(opened), len(laws) - len(opened), len(laws), opened


def main(argv):
    named = argv[1:] or [
        "tinybendygrad/LAWS.bend",
        "tinybendygrad/PROOF.bend",
        "tinybendygrad/PROOF2.bend",
        "tinybendygrad/LAWS/PROOF-ALL.bend",
    ]
    roots = named
    if not argv[1:]:
        roots += bend_files()
        roots = list(dict.fromkeys(roots))
    for r in roots:
        root = r if os.path.isabs(r) else os.path.join(REPO, r)
        if not os.path.exists(root):
            print(f"  MISSING {r}")
            continue
        o, f, t, opened = book(root)
        rel = os.path.relpath(root, REPO)
        print(f"{o:3d}/{f:3d}/{t:3d}  {rel}")
        if argv[1:]:
            for name in opened:
                print(f"        open: {name}")


if __name__ == "__main__":
    main(sys.argv)
