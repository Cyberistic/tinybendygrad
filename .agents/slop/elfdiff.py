#!/usr/bin/env python3
# elfdiff.py -- diff the Bend gate against the CPython oracle, WHOLE `name=value`
# LINES, not row names.
#
# A name-comparing harness reported 0 for all 30 mutations in one unit and 0 for
# all 68 in another, so the unit of comparison is the line. A row present on one
# side and absent on the other is a MISMATCH, not an ignorable extra -- with ONE
# exception, stated here so it cannot be mistaken for a fudge: the oracle carries
# rows for port code that is WRITTEN BUT NOT YET GATED, and those are reported as
# a named coverage gap and are not compared. What is compared is the intersection,
# and a port row with NO oracle row is a hard failure.
#
#     ./bin/bend tinybendygrad/runtime/support/elf.bend > a.txt
#     cat .agents/slop/elf_rows.txt .agents/slop/elf_reloc_probe.txt > oracle.txt
#     python3 .agents/slop/elfdiff.py a.txt oracle.txt
#
# EXIT 0 = every compared row agrees, 1 = a difference or an unknown port row.

import sys
from collections import Counter

def load(p):
    d = {}
    for line in open(p):
        line = line.rstrip("\n")
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k] = v
    return d

def family(k):
    # `elf_sec_e64_hdrtxt` -> `elf_sec`; `elf_rcp_R_X86_64_PC32_near_len` -> `elf_rcp`
    p = k.split("_")
    return "_".join(p[:2]) if k.startswith("elf_") and len(p) > 1 else k

def main():
    bend = load(sys.argv[1])
    orac = load(sys.argv[2])
    if not bend:
        print("FATAL: the bend side emitted ZERO rows. That is not a pass.")
        sys.exit(1)
    unknown = sorted(set(bend) - set(orac))
    want = {k: orac[k] for k in bend if k in orac}
    ungated = sorted(set(orac) - set(bend))
    diffs = [(k, bend.get(k), want[k]) for k in sorted(want) if bend[k] != want[k]]
    print(f"bend rows: {len(bend)}  oracle rows: {len(orac)}  compared: {len(want)}")
    print(f"differences: {len(diffs)}")
    for k, a, b in diffs:
        print(f"  {k}\n    bend   = {a}\n    oracle = {b}")
    if unknown:
        print(f"FATAL: {len(unknown)} port rows the oracle does not know: {unknown[:5]}")
    if ungated:
        c = Counter(family(k) for k in ungated)
        print(f"COVERAGE GAP: {len(ungated)} oracle rows the port does NOT emit "
              f"(written but ungated):")
        for f in sorted(c):
            print(f"    {f}: {c[f]}")
    sys.exit(1 if diffs or unknown or not bend else 0)

main()
