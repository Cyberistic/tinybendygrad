#!/usr/bin/env python3
# elfdiff.py -- diff the Bend gate against the CPython oracle, WHOLE `name=value`
# LINES, not row names.
#
# A name-comparing harness reported 0 for all 30 mutations in one unit and 0 for
# all 68 in another, so the unit of comparison is the line. A row present on one
# side and absent on the other is a MISMATCH, not an ignorable extra.
#
#     ./bin/bend tinybendygrad/runtime/support/elf.bend > a.txt
#     python3 .agents/slop/elf_rows.py > b.txt
#     python3 .agents/slop/elfdiff.py a.txt b.txt
#
# EXIT 0 = identical, 1 = differences. The count is printed either way.

import sys

def load(p):
    d = {}
    for line in open(p):
        line = line.rstrip("\n")
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k] = v
    return d

def main():
    a = load(sys.argv[1])   # Bend
    b = load(sys.argv[2])   # CPython
    keys = sorted(set(a) | set(b))
    diffs = []
    for k in keys:
        va, vb = a.get(k), b.get(k)
        if va != vb:
            diffs.append((k, va, vb))
    print(f"bend rows: {len(a)}  oracle rows: {len(b)}  common: {len(set(a) & set(b))}")
    print(f"differences: {len(diffs)}")
    for k, va, vb in diffs:
        print(f"  {k}\n    bend   = {va}\n    oracle = {vb}")
    if not a:
        print("FATAL: the bend side emitted ZERO rows. That is not a pass.")
    sys.exit(1 if diffs or not a else 0)

main()