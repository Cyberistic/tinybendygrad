#!/usr/bin/env python3
"""probe2.py -- the WALLS from probe-ops.py, re-spelled, plus the remaining op-constructor
routes. Same rule: a candidate is a CALL, a failure is a printed WALL.
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
Ops, UOp, dtypes = G.Ops, G.UOp, G.dtypes

REACHED = set()
for _n in G.GRAPHS:
  for _r in G.emit_py(_n, None):
    REACHED.add(G.unchunks(_r)[1])
NOTREACHED = sorted(o.name for o in Ops if o.name not in REACHED)


def probe(label, fn):
  try:
    ast = fn()
    if isinstance(ast, list):
      ast = UOp.group(*ast)          # `UOp.mstack`/`mselect` answer a LIST (measured)
  except Exception as e:
    print(f"# {label:<26} WALL {type(e).__name__}: {' '.join(str(e).split())[:120]}")
    return None
  c = collections.Counter(n.op.name for n in ast.toposort())
  new = sorted(set(c) & set(NOTREACHED))
  print(f"# {label:<26} rows={len(list(ast.toposort())):<4} NEW={new}")
  print(f"#     census={dict(sorted(c.items()))}")
  return ast


with G.Context(NO_COLOR=1):
  from tinygrad import Tensor
  print(f"# NOT reached ({len(NOTREACHED)}): {NOTREACHED}")
  T = lambda *s: Tensor.empty(*s, dtype=dtypes.float)
  I = lambda *s: Tensor.empty(*s, dtype=dtypes.int)
  probe("flip(0)", lambda: T(4, 3).flip(0).uop)
  probe("shrink", lambda: T(8, 8).shrink(((1, 4), (2, 5))).uop)
  probe("mstack", lambda: UOp.mstack([T(4, 3).uop, T(4, 3).uop]))
  probe("mselect", lambda: UOp.mselect(T(4, 3).uop, T(4, 3).uop, T(4, 3).uop))
  probe("rewrite_error", lambda: UOp(Ops.REWRITE_ERROR, (T(4, 3).uop,), None))
  probe("source", lambda: UOp(Ops.SOURCE, (), None))
  probe("mulacc", lambda: UOp(Ops.MULACC, (T(4, 3).uop, T(4, 3).uop, T(4, 3).uop), None))
  probe("custom", lambda: UOp(Ops.CUSTOM, (T(4, 3).uop, T(4, 3).uop), None))
  probe("customi", lambda: UOp(Ops.CUSTOMI, (), None))
  probe("custom_function", lambda: UOp(Ops.CUSTOM_FUNCTION, (T(4, 3).uop,),
                                       __import__("tinygrad.uop.ops", fromlist=["x"]).CustomFunction("myfn", dtypes.void)))
  probe("cdiv", lambda: I(4, 3).div(I(4, 3)).uop)
  probe("cmod", lambda: I(4, 3).mod(I(4, 3)).uop)
  probe("fdiv-op", lambda: UOp(Ops.FDIV, (T(4, 3).uop, T(4, 3).uop), None))
  probe("flip-op", lambda: UOp(Ops.FLIP, (T(4, 3).uop,), (0,)))
  probe("getaddr", lambda: UOp(Ops.GETADDR, (T(4, 3).uop,), (T(4, 3).uop, dtypes.int)))
  probe("stage", lambda: UOp(Ops.STAGE, (T(4, 3).uop,), None))
  probe("unshard", lambda: UOp(Ops.UNSHARD, (T(4, 3).uop,), (None, None)))
  probe("threefry-op", lambda: UOp(Ops.THREEFRY, (T(4, 3).cast(dtypes.uint32).uop,
                                                 T(4, 3).cast(dtypes.uint32).uop,
                                                 T(4, 3).cast(dtypes.uint32).uop), None))
  probe("program", lambda: __import__("tinygrad.uop.ops", fromlist=["x"]).ProgramInfo(
    (16, 16), (1, 1), (), (), (), ()))
  probe("pyconst-arg", lambda: UOp(Ops.PYLITERAL, (), (4,)))
  probe("cumulative-ish: mm", lambda: (T(4, 4) @ T(4, 4)).uop)
  probe("matmul-wmma", lambda: (T(4, 4, 16) @ T(4, 16, 4)).uop)
  probe("conv2d", lambda: T(1, 3, 8, 8).conv2d(T(1, 4, 3, 3)).uop)
  probe("maxpool", lambda: T(1, 3, 8, 8).max_pool2d().uop)
  probe("dot_general-4d", lambda: (T(2, 4, 8, 8) @ T(2, 4, 8, 8)).uop)
  probe("rsub", lambda: (T(4, 3) - 2.0).uop)
  probe("mul-scalar", lambda: (T(4, 3) * 2.0).uop)
  probe("neg-int", lambda: (-I(4, 3)).uop)
  probe("abs", lambda: T(4, 3).abs().uop)
  probe("exp", lambda: T(4, 3).exp().uop)
  probe("relu", lambda: T(4, 3).relu().uop)
  probe("sign", lambda: T(4, 3).sign().uop)
  probe("erf", lambda: T(4, 3).erf().uop)
  probe("cast-bool", lambda: T(4, 3).cast(dtypes.bool).uop)
  probe("cmpeq-op", lambda: UOp(Ops.CMPEQ, (T(4, 3).uop, T(4, 3).uop), None))
  probe("pad-nopad", lambda: T(4, 3).pad(((0, 0), (0, 0))).uop)
