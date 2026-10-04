#!/usr/bin/env python3
"""Q1 -- WHAT `(a*b).sum().gradient(a,b)` ACTUALLY IS, measured by CALLING CPython.

Nothing here is typed. Every number this unit will put in `graphcmp.py` comes out of this
file, run under `DEV=NULL`, `PYTHONPATH` removed.

WHAT IS BEING ASKED. Three questions, in order, and each one can come back "no":

  Q1a  does the eager route run at all with no device, no Buffer, no realize?
  Q1b  what is the OP CENSUS of the backward graph, and which of CAST/CONST/EXPAND are in
       it? (Two of the three are expected to be ALREADY reached by the 16 forward graphs --
       `CAST 8/3` and `CONST 36/16` in graphcmp-LIMITS.md §5 -- so the interesting number is
       how many of the three this graph ADDS, not how many it has.)
  Q1c  is the result a single root? `Tensor.gradient` answers a TUPLE, and the differ needs
       ONE root to toposort, so the root has to be a GROUP -- and a GROUP is a node the
       corpus already reaches, so it costs nothing new.

And the two facts that decide whether the fixture is buildable on the bend side at all:

  Q1d  the node count and the op sequence in TOPOSORT ORDER, because `graphcmp.py` prints
       `src` as child INDICES into exactly that order and the bend side has to number its
       arena the same way for the two canonical files to be byte-comparable.
  Q1e  every node's eight fields, through `graphcmp.py`'s OWN emitter -- not through a
       second walk. A second walk is how a count forks.
"""
import collections
import os
import sys

os.environ.setdefault("DEV", "NULL")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import graphcmp as G                                        # noqa: E402


def main() -> int:
  G.load_tinygrad()
  G.COMM = G.commutative()
  from tinygrad import Tensor

  # ---- Q1a: does it run at all, and with what does it start? ---------------------
  a = Tensor.empty(4, 3)
  b = Tensor.empty(3, 4)
  print("q1a_a_op=%s a_dtype=%s a_shape=%s" % (a.uop.op.name, a.uop.dtype.name, a.uop.shape))
  print("q1a_b_op=%s b_dtype=%s b_shape=%s" % (b.uop.op.name, b.uop.dtype.name, b.uop.shape))
  s = (a @ b).sum()
  print("q1a_sum_op=%s sum_shape=%s sum_dtype=%s" % (s.uop.op.name, s.uop.shape, s.uop.dtype.name))
  ga, gb = s.gradient(a, b)
  print("q1a_ga_op=%s ga_shape=%s ga_dtype=%s" % (ga.uop.op.name, ga.uop.shape, ga.uop.dtype.name))
  print("q1a_gb_op=%s gb_shape=%s gb_dtype=%s" % (gb.uop.op.name, gb.uop.shape, gb.uop.dtype.name))

  # ---- Q1c: the ROOT. `gradient` answers a tuple; the differ needs one root. -------
  root = UOp_group(ga.uop, gb.uop)
  ts = list(root.toposort())
  print("q1c_root_op=%s n_src=%d n_nodes=%d" % (root.op.name, len(root.src), len(ts)))
  print("q1c_opseq=%s" % " ".join("%s/%d" % (n.op.name, len(n.src)) for n in ts))
  census = collections.Counter(n.op.name for n in ts)
  print("q1c_census=%s" % " ".join("%s=%d" % kv for kv in sorted(census.items())))

  # ---- Q1b: CAST / CONST / EXPAND, and what the FORWARD corpus already reaches ------
  forward = {"CAST", "CONST", "EXPAND"}
  reached = set()
  for g in sorted(G.GRAPHS):
    reached |= set(census_names(g))
  print("q1b_wanted=%s" % " ".join(sorted(forward)))
  print("q1b_in_bw=%s" % " ".join("%s=%s" % (o, "YES" if o in census else "no") for o in sorted(forward)))
  print("q1b_already_reached_by_the_16_forward_graphs=%s" % " ".join(
    "%s=%s" % (o, "YES" if o in reached else "no") for o in sorted(forward)))
  print("q1b_forward_ops_n=%d" % len(reached))
  print("q1b_with_bw_ops_n=%d" % len(reached | set(census)))

  # ---- Q1e: the eight fields, through graphcmp.py's OWN emitter -------------------
  # `G.emit_py` takes a GRAPH NAME and reads it out of `G.GRAPHS`; this probe needs to
  # emit an ARBITRARY UOp. It calls `G.row_of` -- the differ's OWN per-node emitter, the
  # same call `emit_py` makes at graphcmp.py:1407 -- rather than re-deriving the fields,
  # because a SECOND walk is how a count forks. The arena-index rule is copied verbatim
  # from `emit_py`'s docstring: toposort POSITION, counted from 1 (the port spends index 0
  # on its arena bottom).
  def rows_of(u):
    lst = list(u.toposort())
    ix = {id(n): i + 1 for i, n in enumerate(lst)}
    return [G.row_of(n, i + 1, ix) for i, n in enumerate(lst)]

  rows = rows_of(root)
  print("q1e_rows=%d" % len(rows))
  for ln in rows:
    f = G.unchunks(ln)
    print("q1e_row id=%s op=%-8s dtype=%-8s shape=%-12s depth=%s tag=%s arg=%s src=%s"
          % (f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7]))

  # ---- and the ledger over those rows, which is the acceptance criterion ----------
  led = G.ledger(rows)
  print("q1e_ledger=%s" % " ".join("%s=%d" % kv for kv in sorted(led.items())))
  # ---- MULTI-PARENT, because a backward graph is a DAG by construction ------------
  nodes, _, _ = G.build(rows, "py")
  print("q1e_multiparent=%s" % (", ".join(G.multiparent(nodes)) or "none -- a TREE"))
  print("q1e_symdims=%s" % [n.nid for n in G.symdims(nodes)])
  return 0


def UOp_group(*xs):
  from tinygrad.uop.ops import UOp
  return UOp.group(*xs)


def census_names(graph: str) -> set:
  return {G.unchunks(ln)[1] for ln in G.emit_py(graph, None)}


if __name__ == "__main__":
  sys.exit(main())