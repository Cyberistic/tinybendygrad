"""The CPython half of probe-471.bend: `store(INDEX, gate.where(load(INDEX), alt))` through the
vendored tinygrad's own `symbolic.sym`.

    .venv/bin/python .agents/slop/sym92/probe-471.py
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym

b = UOp.variable("b", 0, 10, dtype=dtypes.int32)
i0 = UOp.const(0, dtypes.int32)
ix = UOp(Ops.INDEX, src=(b, i0))
ld = UOp(Ops.LOAD, src=(ix,))
g = b < 5                                  # a BOOL node, not a bool PARAM
alt = UOp.const(7, dtypes.int32)
st = UOp(Ops.STORE, src=(ix, g.where(ld, alt)))
print("store_where_load_then=%r" % sym.rewrite(st))
