#!/usr/bin/env python3
"""probe-ops.py -- WHICH of the 42 ops the corpus does not reach can upstream's OWN code
put in a graph? Every row below is a CALL, never a transcription: the candidate is written
as the tinygrad expression, built, toposorted, and the node ops are read off the result.

A candidate that raises is a WALL and is printed as one, because "this route does not
exist" and "this route exists and I spelled it wrong" are different findings.
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


def ops_of(a):
  if not isinstance(a, UOp):
    raise TypeError("not a UOp")
  return collections.Counter(n.op.name for n in a.toposort())


def probe(label, fn):
  """`fn` returns a UOp or raises. Everything printed is measured."""
  try:
    ast = fn()
  except Exception as e:
    print(f"# {label:<28} WALL {type(e).__name__}: {' '.join(str(e).split())[:120]}")
    return
  c = ops_of(ast)
  new = sorted(set(c) & set(NOTREACHED))
  print(f"# {label:<28} rows={len(list(ast.toposort())):<4} NEW={new}")
  print(f"#     census={dict(sorted(c.items()))}")


def T(*shape):
  from tinygrad import Tensor
  return Tensor.empty(*shape, dtype=dtypes.float)


with G.Context(NO_COLOR=1):
  from tinygrad import Tensor
  print(f"# denominator len(list(Ops))={len(list(Ops))}  reached={len(REACHED)}  "
        f"NOT reached ({len(NOTREACHED)}): {NOTREACHED}")
  print("# ---- UNARY / BINARY EAGER TENSOR OPS (upstream's own public API) ----")
  probe("sub", lambda: (T(4, 3) - T(4, 3)).uop)
  probe("neg", lambda: (-T(4, 3)).uop)
  probe("sqrt", lambda: T(4, 3).sqrt().uop)
  probe("reciprocal", lambda: T(4, 3).reciprocal().uop)
  probe("fdiv", lambda: (T(4, 3) / T(4, 3)).uop)
  probe("pow", lambda: (T(4, 3) ** T(4, 3)).uop)
  probe("log2", lambda: T(4, 3).log2().uop)
  probe("exp2", lambda: T(4, 3).exp2().uop)
  probe("sin", lambda: T(4, 3).sin().uop)
  probe("idiv", lambda: (T(4, 3).cast(dtypes.int) // T(4, 3).cast(dtypes.int)).uop)
  probe("mod", lambda: (T(4, 3).cast(dtypes.int) % T(4, 3).cast(dtypes.int)).uop)
  probe("floordiv-t", lambda: (T(4, 3).floor_div(T(4, 3).cast(dtypes.int))).uop)
  probe("floormod-t", lambda: (T(4, 3).floormod(T(4, 3).cast(dtypes.int))).uop)
  probe("shl", lambda: (T(4, 3).cast(dtypes.int) << T(4, 3).cast(dtypes.int)).uop)
  probe("shr", lambda: (T(4, 3).cast(dtypes.int) >> T(4, 3).cast(dtypes.int)).uop)
  probe("eq", lambda: (T(4, 3) == T(4, 3)).uop)
  probe("lt", lambda: (T(4, 3) < T(4, 3)).uop)
  probe("trunc", lambda: T(4, 3).trunc().uop)
  probe("round", lambda: T(4, 3).round().uop)
  probe("floor", lambda: T(4, 3).floor().uop)
  probe("ceil", lambda: T(4, 3).ceil().uop)
  probe("flip", lambda: T(4, 3).flip().uop)
  probe("contig", lambda: T(4, 8).contiguous().uop)
  probe("contig_backward", lambda: T(4, 8).contiguous_backward().uop)
  probe("shrink", lambda: T(8, 8).shrink((1, 4), (2, 5)).uop)
  probe("pad", lambda: T(4, 3).pad(((0, 1), (0, 2))).uop)
  probe("pad_to", lambda: T(4, 3).pad_to((6, 6)).uop)
  probe("bitcast", lambda: T(4, 3).bitcast(dtypes.int).uop)
  probe("detach", lambda: T(4, 3).detach().uop)
  probe("threefry", lambda: T(4, 3).threefry2x32(T(4, 3).cast(dtypes.uint32)).uop)
  probe("cumsum", lambda: T(4, 3).cumsum().uop)
  probe("where", lambda: T(4, 3).where(T(4, 3), T(4, 3)).uop)
  probe("mstack", lambda: UOp.mstack([T(4, 3).uop, T(4, 3).uop]).uop)
  probe("mselect", lambda: UOp.mselect(T(4, 3).uop, [T(4, 3).uop, T(4, 3).uop]).uop)
  probe("pyconst", lambda: UOp(Ops.PYLITERAL, src=(), arg=(4,)))
  probe("rewrite_error", lambda: UOp(Ops.REWRITE_ERROR, (T(4, 3).uop,), None).uop)
  probe("source", lambda: UOp(Ops.SOURCE, (), None).uop)
  probe("getaddr", lambda: T(4, 3).uop)
  probe("uns shard", lambda: T(4, 8).uop)
  probe("f64 const", lambda: T(4, 3).mul(T(4, 3)).uop)
  print("# ---- THE PORT/OP-SPECIFIC ONES ----")
  probe("wmma?", lambda: UOp(Ops.WMMA, src=(), arg=((4, 4), dtypes.half, 4, None)))
  probe("ins?", lambda: UOp(Ops.INS, src=(), arg=("imm", dtypes.uint32)))
  probe("allreduce", lambda: UOp(Ops.ALLREDUCE, (T(4, 8).uop,), (Ops.ADD, "CPU")))
  probe("mulacc", lambda: UOp(Ops.MULACC, (T(4, 3).uop, T(4, 3).uop, T(4, 3).uop), None).uop)
  probe("custom", lambda: UOp(Ops.CUSTOM, (T(4, 3).uop, T(4, 3).uop), None).uop)
