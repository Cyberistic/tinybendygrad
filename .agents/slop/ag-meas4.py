#!/usr/bin/env python3
"""MEASUREMENT 4: how many `autogen/` constants have actually caused a real
port bug in THIS repo? Searched, not remembered.

A hit counts only when the repo's own record names a constant that came out of
`tinygrad/runtime/autogen/` (directly or through a device module that reads it)
and got a gate row WRONG because it was TRANSCRIBED rather than read.
"""
import re, os, subprocess, collections
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
# where a ported agent records its own bugs and its measurement tables
SOURCES = [".agents/TODO.md", ".agents/slop/notes/bend2-constraints.md",
           ".agents/slop/notes/upstream-bugs.md"] + \
    [f".agents/slop/{f}" for f in os.listdir(".agents/slop")
     if f.endswith(".md") or f.endswith(".txt")]
PAT = re.compile(r"autogen", re.I)
hits = []
for src in SOURCES:
    p = os.path.join(ROOT, src)
    if not os.path.exists(p): continue
    for i, l in enumerate(open(p, errors="replace")):
        if not PAT.search(l): continue
        hits.append((src, i + 1, l.rstrip()))
print(f"lines mentioning `autogen` in {len(SOURCES)} recorded sources: {len(hits)}")
print()
for src, n, l in hits:
    print(f"  {src}:{n}\n      {l[:150]}")
