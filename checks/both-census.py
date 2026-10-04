#!/usr/bin/env python3
"""both-census.py -- the ops-reached number for BOTH SIDES, with the py-only/bend-only
SPLIT that makes it a coverage statement rather than a count.

ARITH-1. `reach/census.py` (the previous instrument) only counted the PY side, so "both
sides read 53" in `REACH.md` was not produced by an instrument that could have found the
two sides differing. This one emits every graph on BOTH sides and prints:

    reached PY       set of ops upstream puts in the py-side corpus
    reached BEND     set of ops the PORT puts in the bend-side corpus
    py-only  (bend MISSING)   -- the port's holes
    bend-only (py MISSING)    -- the port reaching things upstream's own emitter cannot
    reached BOTH             -- the honest coverage number

The denominator is `len(list(Ops))`, MEASURED by CPython at run time. Nothing transcribed.
Rows are cached under `.agents/slop/arith/rows-<graph>-<side>.txt` because the bend side
runs the compiler and `--check-only`-style empty-output failures are indistinguishable
from "no rows": `emit_bend` already retries 5x and RAISES on 0 rows, which is why the
cache is only written after a non-empty row set.
"""
import sys, pathlib, collections, argparse

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[2]))            # the tinygrad tree
import graphcmp as G


def ops_of(rows: list[str]) -> collections.Counter:
  """The op census of one side's rows. `row_of` writes `nid op dtype shape ...`, so field 1
  is the op -- the same read `reach/census.py` makes, and the differ's own `ops_census`
  reads the same field. Kept as one function so both instruments cannot drift."""
  recs = {r[1:]: G.unchunks(r) for r in rows}
  return collections.Counter(f[1] for f in recs.values())


def side(name: str, which: str, dev: str, fresh: bool) -> tuple[str, int, collections.Counter | None, str]:
  cache = HERE / f"rows-{name}-{which}.txt"
  if cache.exists() and not fresh:
    rows = [ln for ln in cache.read_text().splitlines() if ln.strip()]
    return ("CACHE", len(rows), ops_of(rows), "")
  try:
    rows = G.emit_py(name, None) if which == "py" else G.emit_bend(dev, name)[0]
  except Exception as e:                                     # a wall, not a count
    return ("WALL", 0, None, f"{type(e).__name__}: {' '.join(str(e).split())[:150]}")
  cache.write_text("\n".join(rows) + "\n")
  return ("OK", len(rows), ops_of(rows), "")


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--fresh", action="store_true", help="ignore the row cache and re-emit")
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--only", default=None, help="comma list of graphs, for a re-measure of one")
  a = ap.parse_args()

  G.os.environ["DEV"] = a.dev
  G.load_tinygrad()
  G.COMM = G.commutative()
  names = sorted(G.GRAPHS) if a.only is None else a.only.split(",")

  py_tot, bd_tot = collections.Counter(), collections.Counter()
  walls = []
  with G.Context(NO_COLOR=1):
    for name in names:
      for which, tot in (("py", py_tot), ("bend", bd_tot)):
        st, n, ops, err = side(name, which, a.dev, a.fresh)
        if st == "WALL":
          walls.append(f"{name}/{which}: {err}")
          print(f"#   {name:<10} {which:<4} WALL {err}")
          continue
        tot.update(ops)
        print(f"#   {name:<10} {which:<4} {st:<5} rows={n:<4} ops={len(ops):<3} "
              f"{dict(sorted(ops.items()))}")

  denom = len(list(G.Ops))
  py_set, bd_set = set(py_tot), set(bd_tot)
  both = py_set & bd_set
  print(f"#")
  print(f"# graphs in corpus      : {len(names)}")
  print(f"# ops UPSTREAM (denom) : {denom}   (measured len(list(Ops)))")
  print(f"# reached PY            : {len(py_set)}")
  print(f"# reached BEND          : {len(bd_set)}")
  print(f"# reached BOTH          : {len(both)}   <- the honest coverage number")
  print(f"# py-only  (bend MISSING): {sorted(py_set - bd_set)}")
  print(f"# bend-only (py MISSING) : {sorted(bd_set - py_set)}")
  print(f"# reached by NEITHER    : {denom - len(both)}")
  print(f"# NOT REACHED ({denom - len(both)}): "
        f"{sorted(set(o.name for o in G.Ops) - both)}")
  print(f"# WALLS: {walls}")
  return 0


if __name__ == "__main__":
  sys.exit(main())