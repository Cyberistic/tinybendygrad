#!/usr/bin/env python3
"""census.py -- THE OPS-REACHED NUMBER, from DATA, over every graph graphcmp.py knows.

The denominator is `len(list(Ops))`, MEASURED by CPython at run time. The numerator is the
union of the op census of every GRAPH in `graphcmp.GRAPHS`, emitted on the py side -- i.e.
the ops upstream can actually put in a graph the corpus builds. Nothing is transcribed.
"""
import sys, pathlib, collections
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3]))   # the tinygrad tree
import graphcmp as G

G.os.environ["DEV"] = "CPU"
G.load_tinygrad()
G.COMM = G.commutative()
with G.Context(NO_COLOR=1):
  per = {}
  for name in sorted(G.GRAPHS):
    try:
      rows = G.emit_py(name, None)
    except Exception as e:                      # a graph that cannot be built is a WALL
      per[name] = ("WALL", type(e).__name__, str(e)[:140])
      continue
    recs = {r[1:]: G.unchunks(r) for r in rows}
    ops = collections.Counter(f[1] for f in recs.values())
    per[name] = ("OK", len(rows), ops)
  total = collections.Counter()
  bad = []
  print(f"# graphs={len(G.GRAPHS)}  denominator len(list(Ops))={len(list(G.Ops))}")
  for name, v in per.items():
    if v[0] == "WALL":
      print(f"#   {name:<10} WALL {v[1]}: {v[2]}")
      bad.append(name)
      continue
    n, ops = v[1], v[2]
    total.update(ops)
    print(f"#   {name:<10} rows={n:<4} ops={len(ops):<3} {dict(sorted(ops.items()))}")
  print(f"# UNION ops reached = {len(total)} of {len(list(G.Ops))}")
  print(f"# per-op node counts: {dict(sorted(total.items()))}")
  miss = sorted(set(o.name for o in G.Ops) - set(total))
  print(f"# NOT REACHED ({len(miss)}): {miss}")
  print(f"# WALLS: {bad}")
