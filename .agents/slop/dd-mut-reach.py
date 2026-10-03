#!/usr/bin/env python3
"""dd-mut-reach.py -- REACHABILITY of every def in a .bend file from the gate.

A mutation that moves no rows is only a THEOREM when the mutated code is
UNREACHABLE, and "I looked and could not find a caller" is not a proof.  This
answers it by construction: it computes the call graph from `main` and prints the
defs the gate cannot reach.  Pair it with dd-mut-proof.py, which DELETES the
call and shows the rows do not move.

usage: dd-mut-reach.py FILE.bend [root_def]
"""
import re
import sys

src = open(sys.argv[1]).read()
lines = src.splitlines()

DEFS = {}
for i, ln in enumerate(lines):
    m = re.match(r"^def ([A-Za-z_][A-Za-z0-9_.]*)\(", ln)
    if m:
        DEFS[m.group(1)] = i

# A def's body runs from its `def` line to the next line that starts in column
# 0 with a non-space, non-comment character.  `main` is last in the file, so the
# "next line" rule has to fall back to end-of-file or it reads as an empty body
# and the whole graph collapses.
BODY = {}
for name, start in DEFS.items():
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j] and not lines[j][0].isspace() and not lines[j].startswith("#"):
            end = j
            break
    BODY[name] = "\n".join(lines[start:end])

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*")


def uses(body):
    """Every name QUALIFIED or bare that is followed by `(`, plus every dotted
    `A.b` selector (an accessor call such as `Cd.r0(c)`).  A bare `f2f` before a
    dot is NOT a use of `f2f`: `f2f.sel(...)` is a use of `f2f.sel`."""
    out = set()
    for m in re.finditer(r"(^|[^.\w])(%s)\s*\(" % NAME.pattern, body, re.M):
        out.add(m.group(2))
    for m in re.finditer(r"(?<=[^\w.])([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.]+)", body):
        out.add(m.group(1))
        # `A.b.c` is a use of `A.b` and of `A`, and the file may define either.
        parts = m.group(1).split(".")
        for i in range(1, len(parts)):
            out.add(".".join(parts[:i]))
    return out


root = sys.argv[2] if len(sys.argv) > 2 else "main"
seen, stack = set(), [root]
while stack:
    n = stack.pop()
    if n in seen:
        continue
    seen.add(n)
    for u in uses(BODY.get(n, "")):
        if u in DEFS and u not in seen:
            stack.append(u)

print("%s: %d defs, %d reachable from `%s`" % (sys.argv[1], len(DEFS), len(seen), root))
un = sorted((DEFS[n], n) for n in DEFS if n not in seen)
print("UNREACHABLE (%d):" % len(un))
for ln, n in un:
    print("  line %-5d %s" % (ln + 1, n))