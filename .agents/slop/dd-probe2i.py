#!/usr/bin/env python3
"""dd-probe2i.py -- CPython GROUND TRUTH for the dtype.py:28-32 arm (CAST, long/ulong, int src).

Nothing here is transcribed: every printed fact is read out of CPython's own
`l2i` return value, and every dtype question is answered by asking tinygrad.
"""
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import dtype as DD


def val(u):
  """`val` only where tinygrad allows it; None otherwise. tinygrad/uop/ops.py:263
  asserts `val` is only for a CAST of a CONST, so asking for it elsewhere is a lie."""
  try:
    return u.val
  except Exception:
    return None


def node(u, d=0):
  pad = "  " * d
  print(f"{pad}{u.op.name} dtype={u.dtype} val={val(u)} arg={u.arg!r}")
  for i, s in enumerate(u.src):
    node(s, d + 1)


print("python dtypes.uints =", repr(dtypes.uints))
print("l2i_dt =", {k.name: v.name for k, v in DD.l2i_dt.items()})
print()

W = {dt: UOp.variable(f"w_{dt.name}", 0, 0, dt)
     for dt in (dtypes.i32, dtypes.u32, dtypes.bool, dtypes.f32)}

for tag, dt, xdt in (("lg2", dtypes.long, dtypes.i32), ("lg3", dtypes.long, dtypes.u32),
                     ("lg4", dtypes.long, dtypes.bool), ("lg6", dtypes.ulong, dtypes.i32)):
  r = DD.l2i(Ops.CAST, dt, W[xdt])
  roots = list(r) if isinstance(r, tuple) else [r]
  print(f"=== {tag}: CAST dt={dt.name} xdt={xdt.name}  -> {len(roots)} root(s)")
  for i, u in enumerate(roots):
    print(f"  root{i}:")
    node(u, 2)
  print()

import inspect
src = inspect.getsource(DD.l2i)
for n, line in enumerate(src.splitlines(), start=DD.l2i.__code__.co_firstlineno):
  if 25 <= n <= 40:
    print(f"dtype.py:{n}: {line}")