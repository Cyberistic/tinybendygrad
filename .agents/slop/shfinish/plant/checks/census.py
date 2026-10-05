#!/usr/bin/env python
"""DENOM census -- reach for BOTH sides, caching into THIS unit's own directory.

WHY A COPY AND NOT `.agents/slop/arith/both-census.py`: that script's cache directory is
`HERE` = `.agents/slop/arith/`, so running it would OVERWRITE another unit's `rows-*.txt`.
Read-only use of its ideas, own cache, own output. Everything it does that matters is
here: both sides emitted, the py-only/bend-only split, the denominator MEASURED at run
time as `len(list(Ops))`, and a WALL reported as a WALL and never counted as a zero.
"""
import sys, pathlib, collections, argparse

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parents[2]))            # the tinygrad tree
import graphcmp as G


def ops_of(rows):
  recs = {r[1:]: G.unchunks(r) for r in rows}
  return collections.Counter(f[1] for f in recs.values())


def side(name, which, dev, fresh):
  cache = HERE / f"rows-{name}-{which}.txt"
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
