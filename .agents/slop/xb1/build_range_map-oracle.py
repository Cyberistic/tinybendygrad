#!/usr/bin/env python3
"""xb2/build_range_map-oracle.py -- the CPython answer for `build_range_map`'s
membership test, MEASURED at upstream HEAD (and at the pin), because agent-core.md
is blunt about it: never TYPE a row's expected value, and agreement between a port
and a hand-typed oracle is one mistake copied.

Run at both ends:
    git show 6c3d401cf324:tinygrad/{uop/ops.py,codegen/__init__.py} > a pristine tree, then
    PYTHONPATH=<tree> python3 this.py
"""
import sys
from tinygrad.uop.ops import Ops, UOp, AxisType
from tinygrad.codegen import build_range_map
import tinygrad.uop.ops as O

print(f"AxisType members ({len(list(AxisType))}): "
      + ", ".join(a.name for a in AxisType), file=sys.stderr)
print(f"has UNROLL: {hasattr(AxisType, 'UNROLL')}   has REDUCE: {hasattr(AxisType, 'REDUCE')}", file=sys.stderr)

src = sys.argv[1] if len(sys.argv) > 1 else "3,UPCAST"
n, at = int(src.split(",")[0]), src.split(",")[1]
print(f"signature: build_range_map(sink) with sink = a UOp.range({n}, 0, AxisType.{at})", file=sys.stderr)


class FakeAT:
  """A Range with an axis_type the real enum may no longer have. UNROLL/REDUCE were
  DELETED upstream, so at HEAD they are not constructible -- which is the answer."""

u = UOp.range(n, 0, getattr(AxisType, at))
ctx = build_range_map(u)
print(f"build_range_map(UOp.range({n}, 0, AxisType.{at})) -> len={len(ctx)}  keys={list(ctx)}")
# the negative control: a RANGE whose axis_type is NOT in the set
u2 = UOp.range(n, 1, AxisType.LOOP)
print(f"control  build_range_map(UOp.range({n}, 1, AxisType.LOOP)) -> len={len(build_range_map(u2))}")