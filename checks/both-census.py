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
Rows are cached beside this file as `both-rows-<graph>-<side>.rows` because the bend side
runs the compiler and `--check-only`-style empty-output failures are indistinguishable
from "no rows": `emit_bend` already retries 5x and RAISES on 0 rows, which is why the
cache is only written after a non-empty row set.
"""
import sys, pathlib, collections, argparse

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# `3f0e70ff1` MOVED this file from `.agents/slop/arith/` to `checks/`, ONE level shallower, and
# carried the constant across without recomputing it -- so `parents[2]` became
# `/Users/cyberistic/src`, which MEASURED holds only `tries/`.  Both `sys.path.insert` lines above
# were WRONG HERE FOR DIFFERENT REASONS, and `census.py` is this file's fixed TWIN (a copy, so the
# two cannot share a cache): at the old depth `HERE.parent` was `.agents/slop`, which held
# `graphcmp`, and `parents[2]` was the tinygrad tree.  Neither is reachable from `checks/`.
REPO = HERE.parents[0]


def refuse(*why: str) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE the `sys.path` manipulation and before the `graphcmp` import, because under bare
  `python3` the wrong root made THAT import raise `ModuleNotFoundError`, and an assertion
  DOWNSTREAM of what it asserts cannot turn an exception into a refusal."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FOURTH relocation is a refusal rather than a traceback: the substrate
# this file's root claim rests on, and the one module it imports.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
_GRAPH = REPO / ".agents" / "slop" / "graphcmp.py"
if not _GRAPH.is_file():
  refuse(f"input absent: {_GRAPH}")

sys.path.insert(0, str(REPO))                    # the tinygrad tree
sys.path.insert(0, str(_GRAPH.parent))           # `graphcmp`; reachable from NEITHER above
import graphcmp as G


def ops_of(rows: list[str]) -> collections.Counter:
  """The op census of one side's rows. `row_of` writes `nid op dtype shape ...`, so field 1
  is the op -- the same read `reach/census.py` makes, and the differ's own `ops_census`
  reads the same field. Kept as one function so both instruments cannot drift."""
  recs = {r[1:]: G.unchunks(r) for r in rows}
  return collections.Counter(f[1] for f in recs.values())


def side(name: str, which: str, dev: str, fresh: bool) -> tuple[str, int, collections.Counter | None, str]:
  # `.rows`, and a `both-` PREFIX, and both for a MEASURED reason: fixing the root made this
  # gate REACHABLE for the first time since `3f0e70ff1`, and the cache it writes landed in
  # `checks/` as `rows-<graph>-<side>.txt` -- which `checks/no-txt.py` exits 1 on outright.
  # MEASURED, one run: `python3 checks/both-census.py --only=schedule --fresh` produced
  # `checks/rows-schedule-bend.txt` and nothing else.  The prefix is `checks/census.py`'s own
  # reason for existing at all ("running it would OVERWRITE this unit's rows"), so the two
  # caches must not share a name either.
  cache = HERE / f"both-rows-{name}-{which}.rows"
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