#!/usr/bin/env python3
"""CANDIDATE ROWS for `codegen/late/linearizer`'s order gate, scored by how many
of the seven fixture src-swaps they can SEE.

`order-lin-sweep.sh` established that CPython's answer moves 2..20 rows per
swap, so the information is in CPython. What is missing is a row the PORT can
compute that moves too. This script prints, for each candidate row, the value
under every swap, so a candidate is chosen on MEASURED movement rather than on
an argument about which one "should" work.

Candidates, and the port def each would use:

  DEGK  `tb_keys(lt_deg(ar, lt_lst()))`      -- `out_degree`'s KEY ORDER.
        linearizer.py:16-17 walks `reversed(lst)` and `u.src_without_body`,
        so the dict's insertion order is a function of BOTH orders. The port
        has `lt_deg` and `tb_keys` already; nothing else prints this.

  EDG   the src-index sequence of every node in `lst` order -- the arena's EDGE
        LIST. The most order-faithful row available, at the cost of a new
        printer in the port.

  SK    the SINK's src index sequence -- the DFS seed.

Usage:
  ORDER_LIN_SWAP=<swap> .venv/bin/python .agents/slop/order-lin-cand.py
"""
import os
import sys

sys.path.insert(0, '.')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("order_lin_probe", os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "order-lin-probe.py"))
_probe = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_probe)
lin_fixture = _probe.lin_fixture

SWAP = os.environ.get("ORDER_LIN_SWAP", "")


def main() -> int:
  from tinygrad.helpers import Context
  from tinygrad.uop.ops import Ops
  from tinygrad.codegen.late.linearizer import linearize
  ix, sk, sk2, rngs = lin_fixture(SWAP)
  with Context(TUPLE_ORDER=0):
    nl = linearize(sk)
  lst = list(sk.toposort(enter_calls=False).keys())
  pos = {u: i for i, u in enumerate(lst)}

  # `out_degree`, linearizer.py:11,16-17 -- the KEY ORDER is the claim.
  od = {}
  for u in reversed(lst):
    for s in u.src_without_body:
      od[s] = od.get(s, 0) + 1

  print("DEGK=" + " ".join(str(pos[u]) for u in od))
  print("DEGK=" + " ".join(str(pos[u]) for u in sorted(od, key=lambda u: -od[u])))
  print("EDG=" + " ".join("%d:%s" % (pos[u], ",".join(str(pos[s]) for s in u.src_without_body))
                          for u in lst))
  print("SK=" + " ".join(str(pos[s]) for s in sk.src))
  print("NLIST=" + " ".join(str(pos[u]) for u in nl))

  # THE ROW THAT GOES IN THE PORT: the arena's EDGE LIST, keyed by the arena's
  # OWN indices -- which are the oracle's `ix` values, because `put` spends the
  # same counter `ops.bend`'s `Arena.empty` does. The `lin` graph is walked in
  # `lst` order (the port's `lt_lst()`), and the `linc` graph in ITS `lst`
  # order (the port's `lt_lst_call()`), so the two rows differ only in the list.
  def edg(order):
    # THE ALPHABET IS THE POSITION IN THE DECLARED TOPOSORT. CPython derives it
    # from its own `toposort`; the port derives it from its own arena plus its
    # own literal node list. Neither side borrows the other's fixture, and the
    # CONST/CAST interning divergence stops mattering because the alphabet is a
    # position and not an arena index.
    ai = {u: i for i, u in enumerate(order)}
    return " ".join("%d:%s" % (ai[u], " ".join(str(ai[s]) for s in u.src_without_body))
                    for u in order)
  print("LINEDG=" + edg(lst))
  print("LINCEDG=" + edg(list(sk2.toposort(enter_calls=False).keys())))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
