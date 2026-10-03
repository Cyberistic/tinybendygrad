#!/usr/bin/env python3
"""dd-mut-classify.py -- turn the measured table into the CLASSIFIED table.

The harness (dd-mutate.py) measures.  This file decides what a measurement MEANS,
and it is deliberately separate so a verdict can never be an accident of the code
that produced it.

THREE verdicts, and only three:

  MOVED   the mutation changed rows.  The gate has teeth here.
  THEOREM the mutation changed nothing AND there is a PROOF the mutated code is
          unreachable.  A proof is one of:
            - `unreachable`: renaming the enclosing def compiled and the gate
              output stayed byte-identical (dd-mut-proof.py)
            - `intercepted`: deleting the ARM compiled and the output stayed
              byte-identical (dd-mut-tether.py)
          Anything else is not a proof and does not belong here.
  REQUEST the mutation changed nothing and there is NO proof.  This is a request
          for a FIXTURE.  It is not a pass, not a coverage claim, and it must
          name the fixture that would close it.

A zero with no proof is a REQUEST by construction.  There is no fourth bucket and
no "probably fine".

usage: dd-mut-classify.py TABLE.tsv [PROOF.tsv ...]
  PROOF.tsv lines: `ID<TAB>PROOF<TAB>EVIDENCE`
"""
import sys

MOVED, SAME, DNC = "MOVED", "SAME", "DID-NOT-COMPILE"


def main():
    proofs = {}
    for path in sys.argv[2:]:
        for ln in open(path):
            ln = ln.rstrip("\n")
            if not ln or ln.startswith("#"):
                continue
            i, p, ev = (ln.split("\t") + ["", ""])[:3]
            proofs[i] = (p, ev)

    rows = []
    for ln in open(sys.argv[1]):
        i, verdict, n, moved = (ln.rstrip("\n").split("\t") + ["", "", ""])[:4]
        if i.startswith("C"):
            continue
        if verdict == MOVED:
            status, why = MOVED, "gate output changed"
        elif verdict == DNC:
            status, why = DNC, "the mutant is not a program (RULE B)"
        elif i in proofs:
            p, ev = proofs[i]
            status = "THEOREM" if p in ("unreachable", "intercepted") else "?"
            why = "%s: %s" % (p, ev)
        else:
            status, why = "REQUEST", "NO PROOF -- needs a fixture"
        rows.append((i, verdict, status, why))

    w = max(len(r[0]) for r in rows)
    print("%-*s  %-10s %-17s %s" % (w, "ID", "measured", "STATUS", "why"))
    for i, v, s, why in rows:
        print("%-*s  %-10s %-17s %s" % (w, i, v, s, why))
    n = lambda s: sum(1 for r in rows if r[2] == s)  # noqa: E731
    print("\n%d MOVED | %d THEOREM | %d REQUEST | %d DID-NOT-COMPILE"
          % (n(MOVED), n("THEOREM"), n("REQUEST"), n(DNC)))
    assert not [r for r in rows if r[2] == "?"], "a proof kind is not recognised"


main()