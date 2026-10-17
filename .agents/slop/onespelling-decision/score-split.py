#!/usr/bin/env python3
"""READ-ONLY. Score the proposed SPLIT against the precision audit's OWN hand labels.

The audit (`.agents/slop/onespelling-precision/sample.rows`, 46 rows, labelled at HEAD 03500a2620)
already decided TRUE/FALSE for 40 `prose-basename-citation` rows.  A proposed branch rule is only
worth anything if it agrees with those labels.  This joins the audit's prose sites to the branch
`split.py` computed at 7a826eb70a, and reports the 2x2 -- so "the SPLIT is better" is a number or
it is nothing.

Note the JOIN is not free: the labels were made at 03500a2620 and the branches at 7a826eb70a, and
the tree moved (248 -> 251 -> 253 prose rows).  Every label whose basename no longer appears in
`split.rows` is reported as UNJOINED rather than counted as agreement or as disagreement.
"""
from __future__ import annotations

import os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE = os.path.join(ROOTDIR := os.path.dirname(HERE), "onespelling-precision", "sample.rows")

branch: dict[str, str] = {}
with open(os.path.join(HERE, "split.rows")) as fh:
    next(fh)
    for line in fh:
        f = line.rstrip("\n").split("\t")
        branch[f[0]] = f[8]

cross = Counter()
unjoined: list[str] = []
with open(SAMPLE) as fh:
    next(fh)
    for line in fh:
        f = line.rstrip("\n").split("\t")
        if f[0] != "prose-basename-citation":
            continue
        base = f[1].split(":", 1)[1]
        b = branch.get(base)
        if b is None:
            unjoined.append(base)
            continue
        cross[(b, f[2])] += 1

print(f"hand labels joined to branches : {sum(cross.values())} of 40 prose labels")
if unjoined:
    print(f"UNJOINED (basename gone at the newer HEAD) : {len(unjoined)} {sorted(unjoined)}")
for b in ("POSITIVE", "SUGGESTED"):
    t, f = cross[(b, "TRUE")], cross[(b, "FALSE")]
    n = t + f
    print(f"  branch {b:<9} : TRUE {t:>2}  FALSE {f:>2}  n={n:<3} precision {t/n:.3f}" if n else
          f"  branch {b:<9} : TRUE  0  FALSE  0  n=0    NO DENOMINATOR")