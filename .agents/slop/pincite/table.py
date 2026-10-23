#!/usr/bin/env python3
"""The BEFORE/AFTER class table, from the cached classification."""
from __future__ import annotations
import collections, json
from pathlib import Path
HERE = Path(__file__).resolve().parent
rows = json.loads((HERE / "classified.json").read_text())

def classify(r, lane):
    """lane in ('old','new') -> the gate's own five classes."""
    h = r[lane]
    if not r["toks"]:
        return "uncheckable_no_claim_token"
    if h["at_pin"]:
        return "at_pin"
    if h["newest"]:
        return "only_older_revision"
    return "at_no_revision"

def table(lane, restrict=None):
    c = collections.Counter()
    for r in rows:
        if restrict and not restrict(r):
            continue
        c[classify(r, lane)] += 1
    return c

def dangling(rows_subset, lane):
    out = []
    for r in rows_subset:
        h = r[lane]
        if not r["toks"]:
            continue
        if h["at_pin"] or h["newest"]:
            continue
        if r["explicit"] and "/" in r["subject"]:
            out.append(r)
    return out

old = table("old")
new = table("new")
print("== CLASS TABLE (checkable citations) ==")
for k in ("at_pin", "only_older_revision", "at_no_revision", "uncheckable_no_claim_token"):
    print(f"  {k:32s} BEFORE {old.get(k,0):5d}   AFTER {new.get(k,0):5d}")
d_old = dangling(rows, "old")
d_new = dangling(rows, "new")
print(f"  {'dangling (one file outright)':32s} BEFORE {len(d_old):5d}   AFTER {len(d_new):5d}")
print()

# REPAIR 2: how many of the "at_no_revision" rows have NO token present in the file?
def present_anywhere(r):
    return any(r["present"].values())

print("== REPAIR 2 (VOCABULARY): token presence in the cited file ==")
nonew = [r for r in rows if not r["toks"]]
noTokFile = [r for r in rows if r["toks"] and not present_anywhere(r)]
partTokFile = [r for r in rows if r["toks"] and present_anywhere(r)]
print(f"  citations with NO claim token           : {len(nonew)}")
print(f"  tokens, NONE occurs in the cited file   : {len(noTokFile)}")
print(f"  tokens, at least one occurs             : {len(partTokFile)}")
print()

# After repair1+2, split the at_no_revision set into unverifiable vs still-red
after_nowhere = [r for r in rows if r["toks"] and not r["new"]["at_pin"] and not r["new"]["newest"]]
unver = [r for r in after_nowhere if not present_anywhere(r)]
still = [r for r in after_nowhere if present_anywhere(r)]
print("== AFTER REPAIRS: the at-no-revision set splits ==")
print(f"  UNVERIFIABLE (no token occurs in the file) : {len(unver)}")
print(f"  still at no revision (tokens DO occur)      : {len(still)}")
print(f"  of those, DANGLING (one file outright)      : {len(dangling(still,'new'))}")
print()
print("== the tokens of the still-red set (sample) ==")
for r in dangling(still, "new")[:40]:
    print(f"  {r['rel']}:{r['at']} {r['subject']}:{r['lo']}-{r['hi']} toks={r['toks']} present={[t for t,v in r['present'].items() if v]}")
