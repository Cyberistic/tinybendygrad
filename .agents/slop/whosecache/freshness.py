#!/usr/bin/env python
"""freshness.py -- does each corpus cache AGREE WITH ITS GENERATOR, today?

WHAT WENT WRONG FIRST, because the wrong number is the one that teaches the lesson.
An earlier run of this question in this unit called `graphcmp.emit_py` 34 times in ONE
process and reported `checks/rows/` as 2 fresh of 34.  That was WRONG, and it was wrong
because `UOp.unique_num` (`tinygrad/uop/ops.py:839`) is a module-level `itertools.count`
that reaches the row stream through `ParamArg(next(UOp.unique_num), ...)` and out through
`graphcmp.py:708`'s `u(pa.slot)`: graph 1 emits `P(i0,...)`, graph 2 emits `P(i13,...)`,
and by graph 34 every row carries a number no published artifact was ever going to contain.
`.agents/slop/hermetic/isolate.py` exists for exactly this and says so in its own header.
THE BEFORE-VALUES, ALL THREE WRONG THE SAME WAY, IN ONE PROCESS:
    checks/rows-FLAT  9 fresh / 25 stale of 34
    checks/both-FLAT  9 fresh / 25 stale of 34
    oracles          17 fresh /  8 stale of 34
    checks/rows/DIR   2 fresh / 25 stale of 34
So this file emits ONCE PER GRAPH IN A FRESH PROCESS, via the generator the project already
built for the purpose, and compares each cache against THAT.

The population is `graphcmp.GRAPHS` -- the generator's own declaration, loaded by path.
The bend lane is NOT re-emitted here: `emit_bend` costs a `bend` process per graph, and
`checks/hermetic-census.py --check` already does the whole bend lane with a real
denominator (`rc=3`, `39/68`). This file is the py lane only and says so in its own output."""
import os, pathlib, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "hermetic"))
sys.path.insert(0, str(ROOT / ".agents" / "slop"))
os.environ["DEV"] = "CPU"
import graphcmp as G            # noqa: E402
import isolate                 # noqa: E402  -- fresh process per graph, see its own header

CACHES = {
  "checks/rows-FLAT":  ROOT / "checks",
  "checks/both-FLAT":  ROOT / "checks",
  "oracles":           ROOT / "oracles",
  "checks/rows/DIR":   ROOT / "checks" / "rows",
}
DEV = "CPU"


def main():
  names = sorted(G.GRAPHS)
  held = collections.Counter()
  fresh = collections.Counter()
  stale = {k: [] for k in CACHES}
  absent = {k: [] for k in CACHES}
  for g in names:
    live = "\n".join(isolate.emit(g, "py", DEV)) + "\n"
    for label, d in CACHES.items():
      f = d / f"rows-{g}-py.rows"
      if not f.exists():
        absent[label].append(g)
        continue
      held[label] += 1
      if f.read_text() == live:
        fresh[label] += 1
      else:
        stale[label].append(g)
  print(f"PY-LANE FRESHNESS, one fresh process per graph, population len(graphcmp.GRAPHS)={len(names)}")
  print(f"{'cache':<20} {'held':>5} {'reproduce':>10} {'STALE':>6}  stale graphs")
  for label in CACHES:
    print(f"{label:<20} {held[label]:>5} {fresh[label]:>10} {len(stale[label]):>6}  "
          f"{' '.join(stale[label]) or '(none)'}")
  print()
  print("DENOMINATOR: 34 graphs x 1 lane (py).  The bend lane is NOT here; "
        "`checks/hermetic-census.py --check` carries it, at rc=3 and 39/68.")
  print("A cache with held=0 does not answer the question and is not scored.")
  return 0


if __name__ == "__main__":
  sys.exit(main())