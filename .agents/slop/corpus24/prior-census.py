#!/usr/bin/env python3
"""prior-census.py -- DID THE 24 EVER GET REACHED? The `denom/rows-*.txt` cache is a
recorded census of a 25-GRAPH corpus, and three of those graphs are no longer in
`graphcmp.GRAPHS`. This reads that cache and asks, per op, whether some graph ever reached
it.

This is the test that separates "the port cannot do this" from "the corpus stopped asking".
`.agents/slop/DENOMINATOR.md` section 5 measured 25 graphs / 61 reached; the authority
`checks/corpus-figure.py` measures 22 / 53. **61 - 53 = 8, and there are exactly three graphs
missing from `GRAPHS`:** `allred`, `cdiv`, `late`. If the eight ops those graphs carried are
exactly the eight that moved, the corpus LOST coverage and did not gain a wall.

The cache is read, never written: `denom/census.py` writes `rows-<name>-{py,bend}.txt` into
ITS OWN directory, and re-running it would overwrite another unit's artifacts.

    env -u PYTHONPATH .venv/bin/python .agents/slop/corpus24/prior-census.py
"""
from __future__ import annotations

import collections
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
DEN = ROOT / ".agents/slop/denom"
sys.path.insert(0, str(ROOT / ".agents/slop"))


def main() -> int:
    import graphcmp as G
    G.load_tinygrad()
    from tinygrad.uop.ops import Ops

    ms = importlib.util.spec_from_file_location("cf", ROOT / "checks/corpus-figure.py")
    cf = importlib.util.module_from_spec(ms)
    ms.loader.exec_module(cf)
    gc = cf.load_graphcmp()
    live: set[str] = set()
    for g in sorted(gc.GRAPHS):
        try:
            live |= {n.op for n in gc.build(gc.emit_py(g, None), "py")[0].values()}
        except Exception:
            pass

    prior: dict[str, set[str]] = collections.defaultdict(set)
    cached = []
    for f in sorted(DEN.glob("rows-*-py.txt")):
        name = f.name[len("rows-"):-len("-py.txt")]
        cached.append(name)
        for ln in f.read_text().splitlines():
            if ln.strip():
                prior[G.unchunks(ln)[1]].add(name)

    allops = [o.name for o in Ops]
    missing = [o for o in allops if o not in live]
    print(f"# graphs live in GRAPHS          : {len(gc.GRAPHS)}")
    print(f"# graphs with a cached py census : {len(cached)}")
    print(f"# cache-only (NOT in GRAPHS)     : "
          f"{sorted(set(cached) - set(gc.GRAPHS))}")
    print(f"# denominator                    : {len(allops)}")
    print()
    print(f"{'OP (not reached now)':<18} {'IN PRIOR CENSUS?':<17} WHICH GRAPH(S)")
    was = 0
    for op in missing:
        g = prior.get(op, set())
        if g:
            was += 1
        print(f"{op:<18} {('YES' if g else 'no'):<17} {' '.join(sorted(g)) or '-'}")
    print()
    print(f"# of the {len(missing)} not reached NOW, previously reached: {was}")
    print(f"# never reached by either corpus                    : {len(missing) - was}")
    print(f"#   {' '.join(o for o in missing if o not in prior)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())