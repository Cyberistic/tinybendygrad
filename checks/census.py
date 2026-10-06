#!/usr/bin/env python
"""DENOM census -- reach for BOTH sides, caching into THIS unit's own directory.

WHY A COPY AND NOT `checks/both-census.py`: both now sit in `checks/`, so that script's
cache is `checks/rows-<graph>-<side>.txt` -- the SAME DIRECTORY as this one's, so running
it would OVERWRITE this unit's rows, and `.txt` is an extension `checks/no-txt.py`
forbids outright (it exits 1 on the tree as it stands).  A copy, so the two cannot share
a cache; own cache, own output.  Read-only use of its ideas.  Everything it does that
matters is here: both sides emitted, the py-only/bend-only split, the denominator MEASURED
at run time as `len(list(Ops))`, and a WALL reported as a WALL and never counted as a zero.
"""
import sys, pathlib, collections, argparse

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# The pair of constants was copied VERBATIM (same `# the tinygrad tree` comment) from
# `.agents/slop/arith/both-census.py:24`, where BOTH were correct: at that depth
# `parents[0]` was `.agents/slop`, which held `graphcmp`, and `parents[2]` was the tinygrad
# tree.  `3f0e70ff1` moved the copy to `checks/`, ONE level shallower, and carried both
# constants across without recomputing them -- so `parents[2]` became `/Users/cyberistic/src`,
# which MEASURED holds only `tries/`: no tinygrad, no graphcmp, no tinybendygrad.  One
# constant stayed live by luck (this repo IS the tinygrad tree); the other became a NO-OP
# THAT LOOKS LIKE A FIX -- `sys.path.insert` of a directory holding no importable module.
# `graphcmp` was NEVER reachable from `checks/`: the dead copy in `checks/` was already
# dead at `3f0e70ff1`, so `import graphcmp` raised and no one could see which line was to blame.
REPO = HERE.parents[0]


def refuse(*why: str) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE the `sys.path` manipulation and before the `graphcmp` import, because under
  bare `python3` the wrong root made THAT import raise `ModuleNotFoundError` -- and an
  assertion DOWNSTREAM of what it asserts cannot turn an exception into a refusal.  The
  unfixed tree did exactly that: rc 1 and a traceback, which carries no denominator and so
  counts nowhere."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FOURTH relocation is a refusal rather than a third exception:
# the substrate this file's root claim rests on, and the one module it imports.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
_GRAPH = REPO / ".agents" / "slop" / "graphcmp.py"
if not _GRAPH.is_file():
  refuse(f"input absent: {_GRAPH}")

sys.path.insert(0, str(REPO))                    # the tinygrad tree
sys.path.insert(0, str(_GRAPH.parent))           # `graphcmp`; reachable from NEITHER above
import graphcmp as G


def ops_of(rows):
  recs = {r[1:]: G.unchunks(r) for r in rows}
  return collections.Counter(f[1] for f in recs.values())


def side(name, which, dev, fresh):
  # `.rows`, and it was `.txt` until 2026-10-06: these ARE expected values -- one lane's rows,
  # cached so a re-run does not re-pay for it -- which is the thing `.rows` names in this project.
  # Read and written here and nowhere else, so the extension is this file's own business.
  cache = HERE / f"rows-{name}-{which}.rows"
  if cache.exists() and not fresh:
    rows = [ln for ln in cache.read_text().splitlines() if ln.strip()]
    return ("CACHE", len(rows), ops_of(rows), set())
  try:
    rows = G.emit_py(name, None) if which == "py" else G.emit_bend(dev, name)[0]
  except Exception as e:
    return ("WALL", 0, None, set())
  if not rows:                     # THE TRAP: 0 rows is not a census, it is a failure
    return ("WALL", 0, None, set())
  cache.write_text("\n".join(rows) + "\n")
  return ("OK", len(rows), ops_of(rows), set())


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--dev", default="CPU")
  ap.add_argument("--only", default=None)
  ap.add_argument("--fresh", action="store_true")
  a = ap.parse_args()
  G.os.environ["DEV"] = a.dev
  G.load_tinygrad()
  G.COMM = G.commutative()
  names = sorted(G.GRAPHS) if a.only is None else a.only.split(",")
  py, bn, walls = set(), set(), []
  for n in names:
    st, nr, c, _ = side(n, "py", a.dev, a.fresh)
    st2, nr2, c2, _ = side(n, "bend", a.dev, a.fresh)
    if c: py |= set(c)
    if c2: bn |= set(c2)
    if st == "WALL" or st2 == "WALL": walls.append(n)
    print(f"# {n:<10} py={st:<6}{nr:<5} bend={st2:<6}{nr2:<5}", flush=True)
  denom = len(list(G.Ops))
  print()
  print(f"graphs      : {len(names)}")
  print(f"denominator : {denom}   (measured len(list(Ops)))")
  print(f"reached PY  : {len(py)}")
  print(f"reached BEND: {len(bn)}")
  print(f"reached BOTH: {len(py & bn)}")
  print(f"py-only     : {sorted(py - bn)}")
  print(f"bend-only   : {sorted(bn - py)}")
  print(f"WALLS       : {walls}")
  print(f"NEITHER     : {len(denom and set(o.name for o in G.Ops) - (py | bn))}")
  print("NEITHER-list:" + " ".join(sorted(set(o.name for o in G.Ops) - (py | bn))))
  return 0


if __name__ == "__main__":
  sys.exit(main())
