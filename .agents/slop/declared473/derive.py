#!/usr/bin/env python3
"""Re-derive the two denominators: declared() and the 473 DECLARED-NAME refusals.

Rule per number:
  declared()   -> call checks/differ.py's own `declared()`, count the set.
  473          -> PLAN.tsv rows whose `note` column starts with "DECLARED" (plan.py:89-90).
The comparison is DISTINCT BASENAMES, because plan.py:89 tests `os.path.basename(t) in DEC`.
"""
import importlib.util
import json
import os
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def declared():
    spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks/differ.py"))
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    return set(d.declared())


def main():
    DEC = declared()
    rows = open(os.path.join(ROOT, ".agents/slop/sloptxt/PLAN.tsv")).read().splitlines()[1:]
    refused = []
    for l in rows:
        cols = l.split("\t")
        path, cls, rule, reader, new, note = cols
        if note.startswith("DECLARED"):
            refused.append((path, reader, cls))

    bases = Counter(os.path.basename(p) for p, _, _ in refused)
    distinct = set(bases)
    print(f"declared() count              = {len(DEC)}")
    print(f"PLAN.tsv DECLARED rows        = {len(refused)}")
    print(f"distinct basenames among 473  = {len(distinct)}")
    print(f"473 basenames not in declared = {len(distinct - DEC)}  {sorted(distinct - DEC)[:5]}")
    print(f"declared names not among 473  = {len(DEC - distinct)}  {sorted(DEC - distinct)[:5]}")
    print(f"declared names reused by >=2 files = {sum(1 for v in bases.values() if v > 1)}")
    print("top basenames by multiplicity:")
    for b, n in bases.most_common(8):
        print(f"  {n:4d}  {b}")

    n_reader = sum(1 for _, r, _ in refused if r.strip())
    print(f"\n473 with a committed reader in PLAN.tsv column = {n_reader}")
    print(f"473 with NO reader                             = {len(refused) - n_reader}")

    json.dump(
        {"declared": sorted(DEC), "refused": [p for p, _, _ in refused],
         "distinct_basenames": sorted(distinct), "bases": bases},
        open(os.path.join(ROOT, ".agents/slop/declared473/derived.json"), "w"),
        indent=1,
    )


main()
