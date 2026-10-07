#!/usr/bin/env python3
"""Q2 part 2, measured: the citations exist but at a DIFFERENT PATH.

The .bend prose cites `.agents/slop/ag-oracle.txt`; the file is `oracles/ag-oracle.txt`. So the
basename IS cited -- the inherited 'named by nothing' premise counted a name whose PATH moved, and
a literal basename search against the wrong tree answers 0. For each of the 259: find a tracked
file with the SAME BASENAME anywhere else, and compare sha256.

Three classes, and they are different findings:
  MOVED      the only other copy is byte-identical -> a move, citations are STALE-ROOTED
  COPIED     the only other copy differs           -> a copy, two live-ish versions
  UNIQUE     no other copy anywhere                -> nothing cites this name at all
"""
import hashlib
import os
import pathlib
from collections import Counter

ROOT = pathlib.Path(".").resolve()
SKIP = {".git", "references", "node_modules", "__pycache__", ".venv"}

by_base = {}
for dp, dns, fns in os.walk(ROOT):
    dns[:] = [d for d in dns if d not in SKIP]
    for f in fns:
        by_base.setdefault(f, []).append(pathlib.Path(dp) / f)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 16), b""):
            h.update(c)
    return h.hexdigest()


def main():
    txts = sorted(p for p in (ROOT / "oracles").rglob("*.txt") if p.is_file())
    cls = Counter()
    out = []
    for t in txts:
        rel = str(t.relative_to(ROOT))
        others = [p for p in by_base.get(t.name, []) if p != t]
        if not others:
            cls["UNIQUE"] += 1
            out.append((rel, "UNIQUE", [], ""))
            continue
        h = sha(t)
        same = [str(p.relative_to(ROOT)) for p in others if sha(p) == h]
        diff = [str(p.relative_to(ROOT)) for p in others if sha(p) != h]
        if same and not diff:
            cls["MOVED"] += 1
            out.append((rel, "MOVED", same, []))
        elif diff and not same:
            cls["COPIED"] += 1
            out.append((rel, "COPIED", [], diff))
        else:
            cls["MIXED"] += 1
            out.append((rel, "MIXED", same, diff))
    print(dict(cls), f"total {len(txts)}")
    import json
    pathlib.Path(".agents/slop/oracles259/othercopies.json").write_text(json.dumps(out, indent=1))
    # BUG FOUND AND FIXED HERE, RECORDED BECAUSE IT IS EXACTLY THE CLASS THIS TASK IS ABOUT: the
    # first version appended the DIFF list into the "same" slot for the COPIED branch, so the
    # classification was right and the LABEL was a lie -- `oracles/rows-bd.txt` printed as
    # "same: schedule-bodies/rows-bd.txt" when the two are 0 bytes against 1131 and differ. A
    # census whose columns are mislabelled is a census nobody can audit. Slots are now named.
    for kind in ("MOVED", "MIXED", "COPIED"):
        sel = [o for o in out if o[1] == kind]
        print(f"\n===== {kind} ({len(sel)}) =====")
        for rel, _, same, diff in sel[:400]:
            print(f"  {rel}")
            print(f"      IDENTICAL-TO: {same}")
            print(f"      DIFFERS-FROM: {diff}")


main()
