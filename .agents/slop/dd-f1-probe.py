#!/usr/bin/env python3
# dd-f1-probe.py -- CALL CPython: what does `UOp.const(v, dt)` build, for every
# (value, dtype) pair the port's `dd_const.int` / `dd_cf` are asked for?
#
# The `dd_const.int` shape is `O.UOp.const(ar, CInt{w})` then `new(CAST)`, i.e.
# the port already believes every integer const is `CAST(CONST)`.  This probe
# says what the CONST's `arg` word is, which is what `lg2k`/`lg6k` compare.
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops

INT_DTS = [dtypes.int32, dtypes.uint32, dtypes.bool, dtypes.int64, dtypes.uint64]
VALUES = [-1, 0, 1, 31, 32, 63, 65535, 2**31 - 1, 2**31, 2**32 - 1]


def word(a):
    v = int(a)
    return v


print("%-12s %-8s %-34s %-6s %s" % ("value", "dtype", "repr", "op", "arg"))
for dt in INT_DTS:
    for v in VALUES:
        try:
            c = UOp.const(v, dt)
        except Exception as e:
            print("%-12s %-8s %s" % (v, dt.name, type(e).__name__))
            continue
        if c.op is Ops.CAST:
            print("%-12s %-8s %-34s %-6s %s" % (v, dt.name, repr(c), "CAST", repr(c.src[0].arg)))
        else:
            print("%-12s %-8s %-34s %-6s %s" % (v, dt.name, repr(c), c.op.name, repr(c.arg)))

# `const_like` is `self.const(val)` == `UOp.const(val, dtype=self.dtype)`.
a0 = UOp.variable("i320", 0, 0, dtypes.i32)
a1 = UOp.variable("i321", 0, 0, dtypes.i32)
for dt in (dtypes.int32, dtypes.uint32):
    lo = a0.cast(dt)
    for v in (-1, 0):
        n = lo.const_like(v)
        print(f"const_like({v}, {dt.name}) = {n!r}")
        if n.op is Ops.CAST:
            print(f"    inner CONST arg = {n.src[0].arg!r}  int = {int(n.src[0].arg)}")
