#!/usr/bin/env python3
"""f2f-gate-diff.py -- dtype.bend's OWN `q*` gate rows against CPython's, name by name.

  f2f-gate-diff.py GATE.txt CPY.txt

THE NAME MAP IS NOT OPTIONAL. `dtype.bend`'s gate names its fixtures `q1`..`q7` and
`.agents/slop/f2f-fixtures.py` names the same seven `q1`..`q7` in the same order, so
this differ pairs them positionally THROUGH THE HEADER, not by string equality -- but
`f2f-fixtures.bend` (the PROBE) still names them `w1 n1 n2 f1 f2 x1 x2`, and
`.agents/slop/dd-oracle.py` owns `f1 f2 g3 g4 g6 g7` for the SAME defs with DIFFERENT
fixtures. A name collision here reads exactly like a real bug, so this file REFUSES to
run if the two sides do not have the same fixture set in the same order.

⚠ `qn` IS REPORTED SEPARATELY AND IS NOT COMPARABLE. `dtype.bend`'s `rows.put` prints
`Arena.next(answer) - from` in an arena that the `l2i` and `c*` rows have ALREADY
POPULATED, while CPython's `window()` counts nodes interned since a mark in a process
whose only earlier nodes are the two the fixture hook mints. Six of `q1`'s nodes were
already interned by an earlier row, so the port reads `q1n=20` where CPython reads 26 --
and that is the ARENA STATE, not a graph. `sig` and `k` are the cone and they ARE
comparable; `=` is the tree and it IS comparable. `n` is printed and not scored.

  sig  the cone's op/arity sequence -- `dd_cone` is a DEPTH-FIRST WALK FROM THE ROOT, so
       it RENUMBERS, and a wrong graph with no forward edge walks identically to a right
       one. It is necessary and not sufficient.
  k    the cone's CONSTANT sequence -- the only thing that separates two graphs over the
       same op sequence (`lab` prints a CAST as the bare word `CAST`).
  =    the answer tree -- `dd_tree` at the root.
"""
import sys

# `qn` and `qsig`/`qk`/`q=` are the compared rows. `qn` is printed, never scored.
SCORED = ("=", "sig", "k")
UNSCORED = ("n",)


def rows(path):
    out = {}
    for ln in open(path):
        ln = ln.strip()
        if not ln or "=" not in ln:
            continue
        k, _, v = ln.partition("=")
        if k and k[0].isalpha():
            out[k] = v
    return out


def main():
    p, q = rows(sys.argv[1]), rows(sys.argv[2])
    pn = [k for k in p if k.startswith("q") and k[1:].isdigit()]
    qn = [k for k in q if k.startswith("q") and k[1:].isdigit()]
    if len(pn) != len(qn):
        print(f"FIXTURE COUNT port={len(pn)} cpy={len(qn)} -- refusing, a name collision "
              f"manufactures disagreements", file=sys.stderr)
        return 2
    bad = 0
    for a, b in zip(pn, qn):
        if a != b:
            print(f"NAME ORDER {a} vs {b} -- refusing", file=sys.stderr)
            return 2
    for name in pn:
        for suf in SCORED + UNSCORED:
            k = name + suf
            if k not in p or k not in q:
                continue
            tag = "SCORED" if suf in SCORED else "unscored(arena state)"
            same = p[k] == q[k]
            if suf in SCORED and not same:
                bad += 1
                print(f"DISAGREE {k}\n  port {p[k]}\n  cpy  {q[k]}")
            else:
                print(f"{'ok      ' if same else 'ARENA-ONLY'} {k:<8} {tag:<22} {p[k][:78]}")
    scored = len(pn) * len(SCORED)
    print(f"TOTAL scored_rows={scored} DISAGREE={bad} unscored_rows={len(pn) * len(UNSCORED)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
