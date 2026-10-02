#!/usr/bin/env python3
"""Diff ONLY the emission-template rows against CPython, whole lines, keyed by
the first whitespace-run token. A key present on one side only is a
disagreement."""
import sys
bend = open(sys.argv[1]).read().split("\n")
orc  = [l[2:] for l in open(sys.argv[2]).read().split("\n") if l.startswith("E ")]
KEEP = {"emit.", "prolog.", "anon", "nm."}
def index(lines):
    d = {}
    for l in lines:
        k = l.split(" ", 1)[0]
        if not any(k.startswith(p) for p in KEEP): continue
        d[k] = d[k] + "\n" + l if k in d else l
    return d
b, o = index(bend), index(orc)
bad = 0
for k in sorted(set(b) | set(o)):
    if k not in b: print(f"MISSING IN BEND  {k}\n  py {o[k]!r}"); bad += 1
    elif k not in o: print(f"NOT IN PYTHON   {k}\n  bend {b[k]!r}"); bad += 1
    elif b[k] != o[k]: print(f"DIFF {k}\n  py   {o[k]!r}\n  bend {b[k]!r}"); bad += 1
print(f"--- {len(o)} CPython-emission rows, {len(b)} bend rows, {bad} disagreements")
sys.exit(1 if bad else 0)
