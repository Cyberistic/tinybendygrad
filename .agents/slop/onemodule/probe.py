#!/usr/bin/env python3
"""probe.py -- re-measure all SIX instruments' populations AT ONE INSTANT, on this tree.

    .venv/bin/python .agents/slop/onemodule/probe.py            # the table
    .venv/bin/python .agents/slop/onemodule/probe.py --rows     # same, TSV to stdout

Every number is computed here from the instrument's OWN loader, loaded BY PATH, never
imported by a bindable name. Nothing is inherited from any report.

The point of running them in ONE process at ONE timestamp: the six counts in the brief
were taken at six different times on a tree four units were writing to, so the deltas
between them are of two kinds and they are indistinguishable in the brief -- a SCOPE
difference and a MOVEMENT difference. Running them together removes the second.
"""
from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]


def load(path: pathlib.Path, name: str):
    """BY PATH, never by name: an instrument loaded by a bindable name is an instrument
    whose population anybody can choose."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- 1. gates-pop.discover(): the CANDIDATE shared population -------------------------
def proj_discover(root=ROOT):
    m = load(root / "gates" / "gates-pop.py", "om_discover")
    entries, libs = m.discover(root)
    return {"entries": len(entries), "libs": len(libs),
            "paths": {str(p.relative_to(root)) for p in entries + libs},
            "entry_paths": {str(p.relative_to(root)) for p in entries},
            "homes": m.HOMES, "suffixes": m.SUFFIXES}


# ---- 2. gate-surface: the same discover(), plus the labelled walk CONTROL ------------
def proj_surface(root=ROOT):
    m = load(root / "gates" / "gate-surface.py", "om_surface")
    entries, libs = m.population(root)
    walk = m.walk_control(root, ("checks", "gates"))
    return {"entries": len(entries), "libs": len(libs),
            "paths": {str(p.relative_to(root)) for p in entries + libs},
            "entry_paths": {str(p.relative_to(root)) for p in entries},
            "walk": len(walk),
            "walk_paths": walk,
            "walk_minus_discover": sorted(walk - {str(p.relative_to(root)) for p in entries + libs}),
            "discover_minus_walk": sorted({str(p.relative_to(root)) for p in entries + libs} - walk)}


# ---- 3. coindependent/vocab.py: os.walk, RECURSIVE, over the two homes --------------
def proj_coindependent(root=ROOT):
    m = load(root / ".agents/slop/coindependent/vocab.py", "om_coind")
    rows = m.scan(root, m.HOMES)
    entries = [r for r in rows if r["reason"] in ("py-main", "sh")]
    exits = sorted({c for r in entries for c in r["exits"]})
    return {"rows": len(rows), "entries": len(entries), "libs": len(rows) - len(entries),
            "distinct_exits": len(exits), "exits": exits,
            "paths": {r["path"] for r in rows},
            "entry_paths": {r["path"] for r in entries},
            "homes": m.HOMES}


# ---- 4. pairs/census.py: WHOLE TREE string-lists. A DIFFERENT QUESTION --------------
def proj_pairs(root=ROOT):
    m = load(root / ".agents/slop/pairs/census.py", "om_pairs")
    w = m.shared(m.walk_all())
    t = m.shared(m.tracked())
    slop = {k: v for k, v in t.items() if all(".agents/slop/" in x for x in v)}
    live = {k: v for k, v in t.items() if not all(".agents/slop/" in x for x in v)}
    return {"whole_tree": len(w), "tracked": len(t), "slop_only": len(slop), "live": len(live),
            "skip": sorted(m.SKIP)}


# ---- 5. zerogate/derive.py: its OWN walk, re-asking coindependent's generator -------
def proj_zerogate(root=ROOT):
    m = load(root / ".agents/slop/zerogate/derive.py", "om_zero")
    # the module's own entry points
    fns = [n for n in dir(m) if callable(getattr(m, n)) and not n.startswith("_")]
    rows = getattr(m, "rows", None)
    return {"callables": sorted(fns), "rows_attr": type(rows).__name__,
            "top": sorted(m.__dict__.keys())}


# ---- 6. prune4/census.py: git ls-files. THE INDEX TRAP --------------------------------
def proj_prune4(root=ROOT):
    env = dict(os.environ, GIT_INDEX_FILE=".git/agent-index")
    a = subprocess.run(["git", "ls-files", "*.py"], cwd=root, capture_output=True,
                       text=True, env=env).stdout.split()
    env2 = dict(os.environ)
    env2.pop("GIT_INDEX_FILE", None)
    b = subprocess.run(["git", "ls-files", "*.py"], cwd=root, capture_output=True,
                       text=True, env=env2).stdout.split()
    return {"with_agent_index": len(a), "default_index": len(b),
            "with_agent_index_in_slop": len([x for x in a if x.startswith(".agents/slop/")]),
            "default_index_in_slop": len([x for x in b if x.startswith(".agents/slop/")])}


def main(argv):
    t0 = time.time()
    print(f"# ONE PROCESS, ONE TIMESTAMP: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
          f"  HEAD={subprocess.run(['git','rev-parse','--short','HEAD'],cwd=ROOT,capture_output=True,text=True).stdout.strip()}",
          file=sys.stderr)
    d = proj_discover()
    s = proj_surface()
    c = proj_coindependent()
    p = proj_pairs()
    z = proj_zerogate()
    q = proj_prune4()

    print(f"{'projection':34} {'files':>6} {'entries':>8}  scope")
    print(f"{'discover() [gates-pop]':34} {len(d['paths']):>6} {d['entries']:>8}  "
          f"iterdir over {d['homes']} {d['suffixes']}")
    print(f"{'gate-surface':34} {len(s['paths']):>6} {s['entries']:>8}  "
          f"discover() + os.walk CONTROL={s['walk']}")
    print(f"{'coindependent/vocab.py':34} {len(c['paths']):>6} {c['entries']:>8}  "
          f"os.walk RECURSIVE over {c['homes']}")
    # `pairs` answers a DIFFERENT question, so it has no `files`/`entries` to put in those columns.
    # The first version of this line printed `len(p['whole_tree'] and p['whole_tree'] and [])`, which
    # is 0 for every input -- a count that cannot fail, in the row about an instrument that is not
    # a file census at all. `'-'` is the honest cell; the numbers follow in the scope column.
    print(f"{'pairs/census.py':34} {'-':>6} {'-':>8}  "
          f"WHOLE TREE string-lists: {p['whole_tree']} walk / {p['tracked']} tracked "
          f"({p['live']} live, {p['slop_only']} slop-only)")
    print(f"{'zerogate/derive.py':34} {'-':>6} {'-':>8}  re-asks vocab.scan()")
    print(f"{'prune4/census.py':34} {'-':>6} {'-':>8}  git ls-files: "
          f"agent-index={q['with_agent_index']} default={q['default_index']}")

    if "--rows" in argv:
        print()
        print("path\tdiscover\tgate-surface\twalk_control\tcoindependent")
        allp = sorted(d["paths"] | s["walk_paths"] | c["paths"])
        for q2 in allp:
            print(f"{q2}\t{int(q2 in d['paths'])}\t{int(q2 in s['paths'])}\t"
                  f"{int(q2 in s['walk_paths'])}\t{int(q2 in c['paths'])}")
        print()
        print(f"# elapsed {time.time()-t0:.1f}s", file=sys.stderr)
        return 0

    print("\n--- DISAGREEMENT DECOMPOSITION (file sets, not counts) ---")
    D, S, W, C = d["paths"], s["paths"], s["walk_paths"], c["paths"]
    print(f"discover() == gate-surface ? {D == S}   (same function, so it MUST be)")
    print(f"discover() vs walk_control : |D-S|={len(D - W)} only-discover, "
          f"|W-D|={len(W - D)} only-walk")
    for x in sorted(W - D):
        print(f"    ONLY-WALK      {x}")
    print(f"discover() vs coindependent walk: |D-C|={len(D - C)} only-discover, "
          f"|C-D|={len(C - D)} only-walk")
    for x in sorted(D - C):
        print(f"    ONLY-DISCOVER  {x}")
    for x in sorted(C - D):
        print(f"    ONLY-WALKCI    {x}")
    print(f"\nzerogate derive.py top-level names: {z['top']}")
    print(f"elapsed {time.time()-t0:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))