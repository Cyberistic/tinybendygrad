#!/usr/bin/env python3
"""Diff the Bend gate against CPython, WHOLE name=value LINES, never row
names.  The expectations all come from ag-oracle.txt, which ag-oracle.py
produced by CALLING autogen.gen / reading the module under test.

Usage: python3 ag-diff.py <bend-output> <oracle.txt>
"""
import sys, re
bend = open(sys.argv[1]).read().split("\n")
orc = open(sys.argv[2]).read().split("\n")

# ---- build the CPython expectation set -------------------------------------
exp = {}
for l in orc:
    if l.startswith("tmap "):
        k, v = l[5:].split(" = ", 1); exp["tmap " + k] = v
    elif l.startswith("rule ") and " => " in l:
        m = re.match(r"rule (\d+) : (.*) => (.*)$", l)
        if m: exp[f"rule {m.group(1)}"] = (m.group(2), m.group(3))
    elif re.match(r"^(uints|ints|fps|specs|arc) ", l):
        k, v = l.split(" ", 1); exp[k] = v

# ---- build the Bend row set ------------------------------------------------
got = {}
for l in bend:
    if l.startswith("tmap "):
        k, v = l[5:].split(" = ", 1); got["tmap " + k] = v
    elif l.startswith("rule ") and " => " in l:
        m = re.match(r"rule (\d+) : (.*) => (.*)$", l)
        if m: got[f"rule {m.group(1)}"] = (m.group(2), m.group(3))
    elif re.match(r"^(uints|ints|fps|specs|arc) ", l):
        k, v = l.split(" ", 1); got[k] = v

bad = 0
for k in sorted(set(exp) | set(got)):
    e, g = exp.get(k, "<MISSING>"), got.get(k, "<MISSING>")
    # a rule's PATTERN may span a real newline in both; normalise for comparison
    if isinstance(e, tuple): e = tuple(x.replace("\n", "\\n") for x in e)
    if isinstance(g, tuple): g = tuple(x.replace("\n", "\\n") for x in g)
    if e != g:
        print(f"DIFF {k}\n  py   {e}\n  bend {g}"); bad += 1
print(f"--- {len(exp)} CPython-traced rows, {len(got)} bend rows, {bad} disagreements")
sys.exit(1 if bad else 0)
