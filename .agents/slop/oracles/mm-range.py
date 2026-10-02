#!/usr/bin/env python
# mm-range.py -- MEASUREMENT ONLY. How far do `_min_max` bounds actually go?
#
# Python's ints are arbitrary precision. Bend 2.0.34 has no I64, so the honest
# question is not "is i64 big" but "DOES ANY BOUND EXCEED i64". This walks real
# tinygrad graphs and records, per node, the magnitude of each bound and whether
# it leaves the signed-64 range. Two numbers decide the port:
#   OVER_I64 = nodes where |bound| > 2**63-1  (unrepresentable in the pair)
#   MAX_BITS = the largest bit_length seen
import sys, collections
sys.path.insert(0, '.')
from tinygrad import Tensor, dtypes            # noqa: E402
from tinygrad.uop.ops import UOp, Ops          # noqa: E402

I64_MAX = 2**63 - 1
I64_MIN = -(2**63)


def walk(tag, root):
  over = []
  maxbits = 0
  kinds = collections.Counter()
  n = 0
  for u in root.uop.toposort():
    try:
      lo, hi = u._min_max
    except Exception:
      kinds[f'{u.op.name}:RAISE'] += 1
      continue
    n += 1
    kinds[f'{u.op.name}:{type(lo).__name__}'] += 1
    for v in (lo, hi):
      if isinstance(v, int) and not isinstance(v, bool):
        maxbits = max(maxbits, v.bit_length())
        if v > I64_MAX or v < I64_MIN:
          over.append((u.op.name, u.dtype.name, str(v)))
  print(f"{tag:28s} nodes={n:5d} maxbitlen={maxbits:4d} OVER_I64={len(over)}")
  for o in over[:4]:
    print(f"    OVER: op={o[0]} dt={o[1]} val={o[2]}")
  return over, maxbits, kinds


tally = collections.Counter()
allover = 0
maxb = 0


def go(tag, root):
  global allover, maxb
  over, mb, kinds = walk(tag, root)
  tally.update(kinds)
  allover += len(over)
  maxb = max(maxb, mb)


# --- a spread of real graphs -------------------------------------------------
from tinygrad import Device  # noqa: E402
import os
os.environ['DEV'] = 'NULL'
print("device:", Device.DEFAULT)

go("cast", Tensor([1, 2, 3]).cast(dtypes.f32))
go("cast_half", Tensor([1, 2, 3]).cast(dtypes.f16))
go("matmul", Tensor.randn(4, 8).real.to(torch := None) if False else Tensor.randn(8, 8) @ Tensor.randn(8, 8))
go("conv", Tensor.randn(1, 4, 8, 8).conv2d(Tensor.randn(4, 4, 3, 3)).relu())
go("sum", Tensor.randn(4, 4).sum())
go("arange", Tensor.arange(10))
go("arange_mul", Tensor.arange(10) * 3)
go("arange_floordiv", Tensor.arange(10).floordiv(3))
go("cat", Tensor.cat([Tensor.randn(2, 2), Tensor.randn(2, 2)]))
go("slice", Tensor.randn(4, 4)[:, 1:3])
go("expand", Tensor.randn(1, 4).expand(4, 4))
go("permute", Tensor.randn(4, 8).permute((1, 0)))
go("pad", Tensor.randn(2, 2).pad((0, 2)))
go("softmax", Tensor.randn(4, 4).softmax())
go("matmul_big", Tensor.randn(64, 64) @ Tensor.randn(64, 64))
go("nn_linear", Tensor.randn(32, 64) @ Tensor.randn(64, 128) + Tensor.randn(128))
go("where", Tensor.randn(4).where(Tensor.randn(4) > 0, Tensor.randn(4)))
go("repeat", Tensor.randn(4).repeat(16))
go("cumsum", Tensor.randn(4, 4).cumsum(0))
go("interp", Tensor.randn(1, 1, 4, 4).interpolate((8, 8)))
go("t_allocs", Tensor.randn(4, 4).contiguous())

print()
print("=== TOTAL OVER_I64 =", allover, " MAXBITLEN =", maxb)
print()
print("=== op kinds x bound type (which ops produce float bounds) ===")
for k, n in sorted(tally.items()):
  print(f"  {k:34s} {n}")