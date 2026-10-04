#!/usr/bin/env python3
"""rows.py -- PRINT THE PY SIDE'S ROWS for a candidate, one per line, decoded. This is how
the bend builder is written: the arena index IS the toposort position and the ids are
load-bearing for graphcmp-run.sh's byte-identity step, so the builder must be written in
exactly this order.

    python3 rows.py <name>        # runs the candidate in a FRESH process (slot counter)
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
import graphcmp as G  # noqa: E402

G.os.environ["DEV"] = "CPU"
G.load_tinygrad()
G.COMM = G.commutative()
UOp, dtypes = G.UOp, G.dtypes


def g_alu():
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  return UOp.group(a.sqrt().uop, a.reciprocal().uop, (a ** a).uop, a.log2().uop,
                   a.exp2().uop, a.sin().uop, a.trunc().uop, a.detach().uop)


def g_bit():
  from tinygrad import Tensor
  ia = Tensor.empty(4, 3, dtype=dtypes.int)
  return UOp.group((ia << ia).uop, (ia >> ia).uop, (ia // ia).uop, (ia % ia).uop)


def g_where():
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  # `(a < a)` NOT `a`: MEASURED, `a.where(a, a)` RAISES inside the emitter --
  # `dtype_from_uop`'s WHERE arm (tinygrad/uop/ops.py:158) reads `if src[0].dtype !=
  # dtypes.bool: raise RuntimeError(...)`, and `row_of` reads `.dtype` for EVERY node.
  # The earlier probe missed it because it counted `n.op.name` only and never touched
  # `.dtype`, so a candidate that cannot be EMITTED looked reachable. That is the
  # "measured on a property nothing reads" trap and it is why every candidate here is
  # checked through `emit_py`, not through a hand-rolled census.
  return UOp.group((a < a).where(a, a).uop, (a < a).uop)


def g_move():
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  return UOp.group(a.pad(((0, 1), (0, 2))).uop, a.flip(0).uop,
                   Tensor.empty(8, 8).shrink(((1, 4), (2, 5))).uop,
                   a.contiguous_backward().uop, a.bitcast(dtypes.int).uop)


CAND = {"alu": g_alu, "bit": g_bit, "where": g_where, "move": g_move}

if __name__ == "__main__":
  name = sys.argv[1]
  G.GRAPHS[name] = CAND[name]
  with G.Context(NO_COLOR=1):
    for r in G.emit_py(name, None):
      f = G.unchunks(r)
      print(f"{f[0]:>3} {f[1]:<18} dt={f[2]:<10} shape={f[3]:<12} depth={f[4]} "
            f"tag={f[5]:<4} arg={f[6]:<60} src={f[7]}")
