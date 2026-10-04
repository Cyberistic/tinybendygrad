#!/usr/bin/env python3
"""probe3.py -- THE CANDIDATE GRAPHS, measured on the py side, so the bend builder has a
node count and a census to write against. Every candidate is upstream's OWN construction --
the eager Tensor API and `UOp.group` -- never a hand-spelled `UOp(Ops.X, ...)`.
"""
from __future__ import annotations
import collections
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
import graphcmp as G  # noqa: E402

G.os.environ["DEV"] = "CPU"
G.load_tinygrad()
G.COMM = G.commutative()
UOp, dtypes, Ops = G.UOp, G.dtypes, G.Ops

REACHED = set()
for _n in G.GRAPHS:
  for _r in G.emit_py(_n, None):
    REACHED.add(G.unchunks(_r)[1])


def show(label, ast):
  c = collections.Counter(n.op.name for n in ast.toposort())
  new = sorted(set(c) - REACHED)
  print(f"# {label:<14} rows={len(list(ast.toposort())):<4} ops={len(c):<3} NEW={new}")
  print(f"#     census={dict(sorted(c.items()))}")
  print(f"#     ops-sequence={[n.op.name for n in ast.toposort()]}")
  return new


with G.Context(NO_COLOR=1):
  from tinygrad import Tensor
  f = lambda *s: Tensor.empty(*s, dtype=dtypes.float)
  i = lambda *s: Tensor.empty(*s, dtype=dtypes.int)
  a = f(4, 3)
  ia = i(4, 3)

  # ---- ALU: elementwise UNARY ops over ONE ALLOC. Fewest nodes per new op.
  alu = UOp.group(a.sqrt().uop, a.reciprocal().uop, (a ** a).uop, a.log2().uop,
                  a.exp2().uop, a.sin().uop, a.trunc().uop, a.detach().uop)
  new_alu = show("alu", alu)

  # ---- BIT: the integer-typed elementwise ops. Its own ALLOCs because a CAST is needed.
  bit = UOp.group((ia << ia).uop, (ia >> ia).uop, (ia // ia).uop, (ia % ia).uop)
  new_bit = show("bit", bit)

  # ---- WHERE + the broadcast.
  whr = UOp.group(a.where(a, a).uop, (a < a).uop)
  new_whr = show("where", whr)

  # ---- MOVE: the movement ops the corpus has not reached.
  mov = UOp.group(a.pad(((0, 1), (0, 2))).uop, a.flip(0).uop,
                  f(8, 8).shrink(((1, 4), (2, 5))).uop,
                  a.contiguous_backward().uop, a.bitcast(dtypes.int).uop)
  new_mov = show("move", mov)

  allnew = sorted(set(new_alu) | set(new_bit) | set(new_whr) | set(new_mov))
  print(f"# UNION of the four: {len(allnew)} new -> {len(REACHED)}+{len(allnew)}="
        f"{len(REACHED | set(allnew))} of {len(list(Ops))}")
  print(f"#   {allnew}")
  print(f"#   still not reached: {sorted(set(o.name for o in Ops) - REACHED - set(allnew))}")
