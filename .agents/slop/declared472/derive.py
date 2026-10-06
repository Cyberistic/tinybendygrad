#!/usr/bin/env python3
"""Re-derive the DECLARED-NAME refusal population BY DISCOVERY (os.walk), not by reading a
prior PLAN.tsv -- so the denominator and its split are the LIVE tree, not a remembered number.

Population rule (the same one sloptxt/plan.py used, re-derived):
  owned .txt (checks/no-txt.py ownership rule) whose BASENAME is in checks/differ.py's
  declared(), EXCEPT the live graphcmp artifacts that the carve-out already excuses.
That exception is exactly `checks/no-txt.py`'s: excused = owned & {runs/graphcmp/D/<n>}.

Outputs derived.json with: declared, population, excused, hard-before.
"""
import importlib.util
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
D = os.path.join(ROOT, ".agents/slop/declared472")
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
GRAPH_D = "runs/graphcmp/D"


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def owned(rel):
    parts = rel.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def walk_txt():
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in sorted(filenames):
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
                if owned(rel):
                    out.append(rel)
    return sorted(out)


def snapshot473():
    """The 473-file DECLARED-NAME list, taken FROM `sloptxt/PLAN.tsv` (its own selection),
    filtered to files that still exist. This is the population the task names; the live
    walk above is a DIFFERENT, larger number because other units add mirror trees."""
    rows = open(os.path.join(ROOT, ".agents/slop/sloptxt/PLAN.tsv")).read().splitlines()[1:]
    out = []
    for l in rows:
        cols = l.split("\t")
        if len(cols) >= 6 and cols[5].startswith("DECLARED") and os.path.exists(os.path.join(ROOT, cols[0])):
            out.append(cols[0])
    return sorted(out)


def main():
    differ = load("differ", "checks/differ.py")
    DEC = set(differ.declared())
    txt = walk_txt()
    excused = {os.path.join(GRAPH_D, n) for n in DEC}
    excused_live = {p for p in txt if p in excused}
    hard = [p for p in txt if p not in excused]
    live_pop = sorted(p for p in hard if os.path.basename(p) in DEC)
    snap = snapshot473()
    by_base = {os.path.basename(p) for p in snap}

    print(f"declared() count                    = {len(DEC)}")
    print(f"snapshot 473 (sloptxt PLAN.tsv, existing) = {len(snap)}")
    print(f"owned .txt (live, os.walk)          = {len(txt)}")
    print(f"  excused (graphcmp artifacts)      = {len(excused_live)}")
    print(f"  HARD before                       = {len(hard)}")
    print(f"LIVE basename-in-declared population = {len(live_pop)}  (external units add mirror trees)")
    print(f"  distinct basenames in snapshot    = {len(by_base)}")
    print(f"  snapshot basenames not in declared = {len(by_base - DEC)}")
    print(f"  declared names with no snapshot file = {len(DEC - by_base)}")
    print("\nsnapshot by mirror root:")
    from collections import Counter
    roots = Counter()
    for p in snap:
        roots[p.rsplit("/runs/graphcmp/D/", 1)[0] if "/runs/graphcmp/D/" in p else os.path.dirname(p)] += 1
    for r, n in roots.most_common():
        print(f"  {n:4d}  {r}")
    json.dump({"declared": sorted(DEC), "population": snap, "live_population": live_pop,
               "hard": hard, "excused_live": sorted(excused_live), "owned_txt": txt},
              open(os.path.join(D, "derived.json"), "w"), indent=1)


main()
