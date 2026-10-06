#!/usr/bin/env python3
"""OPSPY CORPUS RE-MEASURE.  Copy $T := ${TMPDIR}/opspy.  Run with zsh.

WHY THIS FILE EXISTS.  `backward-graph/BW-GRAPH.md` records "differ is 35 of 77"
for the backward graph and, beside it, flags the corpus figure as a 17-GRAPH
BASELINE.  The brief says the corpus is now 61 of 77.  This project's notes have
already falsified that family of figure twice -- 34 -> 35 of 77, then a
17-graph 59-of-77 -- so the number is a DEPENDENCY and is re-measured here.

WHAT IS MEASURED, AND WHY IT IS A UNION.  `graphcmp.py`'s differ prints
`ops-reached=<py>/<bend> of 77` PER GRAPH.  Summing those across graphs would
count `BUFFER` once per graph that has one, so the corpus figure is the set
UNION over per-graph op sets, computed here from `graphcmp`'s OWN `GRAPHS` and
its OWN `ops_census`, using the same node dicts the differ walks.  The
denominator is `len(Ops)`, read off the live `tinygrad.uop.ops.Ops`, so a new op
cannot age the answer silently -- which is exactly how the 34/35 pair happened.

`graphcmp.py` is NOT this unit's file and is not edited.  It is imported.
"""
import importlib.util, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("gc", ROOT / ".agents/slop/graphcmp.py")
gc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gc)

from tinygrad.uop.ops import Ops

NAMES = sorted(o.name for o in Ops)
print(f"# denominator: len(Ops) = {len(NAMES)}")
print(f"# graphs declared by graphcmp.GRAPHS = {len(gc.GRAPHS)}")

# graphcmp DEFERS every tinygrad import into `load()` (graphcmp.py:284-290) so the
# py side cannot build its graph on whatever device opens first.  Importing the
# module is therefore NOT enough -- MEASURED: without this call every one of the
# 25 graphs raises `NameError: name 'UOp' is not defined`, and a union over zero
# built graphs prints "0 of 77" beside a denominator that looks perfectly healthy.
# graphcmp injects its deferred tinygrad names into its OWN globals; a caller has to
# do the same, which is what `load_tinygrad` exists for.
gc.load_tinygrad()
for _n in ("AddrSpace","DType","dtypes","AxisType","Ops","ParamArg","UOp","GroupOp","Context"):
  globals()[_n] = getattr(gc, _n)

# The differ's own py-side node dict is `build(emit_py(g, None), "py")[0]`, so the
# union is taken through EXACTLY the path `diff` walks -- not a private rebuild that
# could drift from it.  `build` is graphcmp's node constructor (graphcmp.py:2397).
union: dict[str, int] = {}
per_graph = {}
broken: dict[str, str] = {}
for g in sorted(gc.GRAPHS):
  try:
    pnodes = gc.build(gc.emit_py(g, None), "py")[0]
  except Exception as e:
    # REPORTED, NOT FIXED: `graphcmp.py` is another unit's file.  A graph whose
    # builder raises contributes NO ops, and a corpus figure that silently drops
    # it would understate the coverage it claims, so a broken graph is PRINTED
    # and counted separately rather than skipped quietly.
    tb = e.__traceback__
    frame = tb.tb_frame
    while tb.tb_next: tb = tb.tb_next; frame = tb.tb_frame
    broken[g] = f"{type(e).__name__}: {e}  at {frame.f_code.co_filename.split('/')[-1]}:{frame.f_lineno}"
    continue
  c = gc.ops_census(pnodes)
  per_graph[g] = c
  for op, n in c.items():
    union[op] = union.get(op, 0) + n
  print(f"  {g:<10} nodes={len(pnodes):<4} distinct-ops={len(c)}")

print()
if broken:
  print(f"# {len(broken)} graph(s) FAILED TO BUILD and contribute 0 ops -- reported, not skipped:")
  for g, why in broken.items(): print(f"#   {g}: {why}")
  print()
print(f"# UNION over {len(per_graph)} built graphs of {len(gc.GRAPHS)} declared: "
      f"{len(union)} distinct ops of {len(NAMES)}")
print("# ops reached:", " ".join(sorted(union)))
missing = [n for n in NAMES if n not in union]
print(f"# NOT reached: {len(missing)}", " ".join(missing))
print()
print("# per-graph distinct-op counts, summed vs unioned -- the sum is what a")
print("# corpus figure would be if it added instead of unioned, and it is wrong:")
print(f"#   sum   = {sum(len(c) for c in per_graph.values())}")
print(f"#   union = {len(union)}")