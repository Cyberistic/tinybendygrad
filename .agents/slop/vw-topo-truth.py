#!/usr/bin/env python3
"""vw-topo-truth.py -- CPython's node count and toposort walk for the SAME fixture
`.agents/slop/vw-topo-probe.bend` builds, CALLED. This is the other half of the localisation.

THE QUESTION. `dv_where`'s node `v` is reachable twice (src[0] of `cm` and src[1] of `t`), and
the port prints `And(v >= 0, v <= 15)` twice where CPython prints it once. Three counts decide
WHICH SIDE duplicates, and they are the same three the Bend probe prints:

    arena_nodes   how many DISTINCT UOps the fixture reaches (tinygrad hash-conses, so this is
                  a set size and cannot over-count)
    walk_len      len(toposort(...)) -- ops.py:297's `cache`, which is a DICT, so a repeat is
                  impossible there, and a length above arena_nodes IS the port's duplication
    walk_ops      the walk in order, `rank:OPNAME`, so a repeat NAMES ITSELF instead of
                  arriving as a bare number

`ops.py:297-309` is the reference implementation and it has THREE branches, not two:

    node, visited = stack.pop()
    if node in cache: continue            # <- the third branch, on EVERY pop
    if not visited:
      if gate is None or gate(node): push (node, True) + srcs
    else: cache[node] = None

Run twice; the differ refuses a single run.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad.dtype import Invalid, dtypes  # noqa: E402
from tinygrad.uop.ops import Ops, UOp  # noqa: E402


def gate(x):
  """`validate.py:83-84`, verbatim."""
  return x.op not in {Ops.AFTER, Ops.SHRINK, Ops.ALLOC, Ops.BUFFER} and \
      (x.dtype in dtypes.ints + (dtypes.bool, dtypes.weakint) or x.op is Ops.SINK)


def fixture():
  """`dv_where.of` (validate.bend:2109) re-typed in tinygrad's own constructors, which is the
  correspondence the port's fixture has to have. The oracle's `dv_where` row is this graph,
  and `v` being src of BOTH `cm` and `t` is the whole reason the row is hard."""
  v = UOp.variable("v", 0, 15, dtype=dtypes.int32)
  cm = UOp(Ops.CMPLT, (v, UOp.const(8)))
  return UOp(Ops.WHERE, (cm, v, UOp.const(Invalid)))


def main():
  t = fixture()
  g = UOp.const(True)
  # `validate.py:83-84` VERBATIM, both arguments: `UOp.sink(*uops)` over (idx, gate) and the
  # `[:-1]` that drops the LAST element, which is the SINK. `sink(t)` ALONE is a different walk
  # and prints one op fewer -- the gate's CONST -- so it is spelled out here rather than
  # abbreviated.
  walk = list(UOp.sink(t, g).toposort(gate=gate))[:-1]
  reach = set(UOp.sink(t, g).toposort(gate=None))
  # The SINK IS NOT A FIXTURE NODE -- it is minted by `sink()` -- so it is excluded, and the
  # raw count is printed too so the exclusion is visible rather than applied.
  nodes = {u for u in reach if u.op is not Ops.SINK}
  rank = {u: i for i, u in enumerate(sorted(nodes, key=str))}
  print(f"arena_nodes_raw={len(reach)}")
  print(f"arena_nodes={len(nodes)}")
  print("arena_slots=[%s]" % " ".join(f"{rank[u]}:{u.op.name} " for u in sorted(nodes, key=rank.get)))
  print(f"walk_len={len(walk)}")
  print("walk_ops=[%s]" % " ".join(f"{rank[u]}:{u.op.name} " for u in walk))
  print(f"walk_seq={' '.join(str(u.op) for u in walk)} ")
  print(f"walk_is_set={len(walk) == len(set(walk))}")


if __name__ == "__main__":
  main()