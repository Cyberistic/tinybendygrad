#!/usr/bin/env python3
"""dd-probe-intern.py -- does tinygrad's arena distinguish `CONST True` from `CONST 1`?

The port's `ops.bend` arena keys a node on its integer payload and has no dtype, so if
CPython has TWO nodes here the port cannot have both and every cone constant row that
contains both is structurally unreachable. Answered by CALLING, not by reading.
"""
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass

ORDER = []
_SEEN = set()
_CALL = UOpMetaClass.__call__


def _call(cls, op, src=(), arg=None, tag=None, metadata=None):
  r = _CALL(cls, op, tuple(s._uop for s in src), arg, tag, metadata)
  if id(r) not in _SEEN:
    _SEEN.add(id(r))
    ORDER.append(r)
  return r


UOpMetaClass.__call__ = _call

b = UOp.const(True, dtypes.bool)
i = UOp.const(1)
print("UOp.const(True, bool) =", b, "dtype", b.dtype, "arg", b.arg)
print("UOp.const(1)          =", i, "dtype", i.dtype, "arg", i.arg)
print("SAME NODE?", b is i)
print("ucache size after both:", len(UOpMetaClass.ucache))
print("True == 1 :", True == 1, " hash equal:", hash(True) == hash(1))
print()
print("b.src", b.src, " i.src", i.src)
print()
print("-- what `UOp.const(1, dtypes.u32)` looks like vs `UOp.const(1)`:")
print(UOp.const(1, dtypes.u32), "|", UOp.const(1))
print("SAME?", UOp.const(1, dtypes.u32) is UOp.const(1))
print()
print("-- UOpMetaClass keys (first 3):", list(UOpMetaClass.ucache.keys())[:3])
print()
print("-- two distinct CONST args equal as keys?")
print("ucache lookup True:", UOpMetaClass.ucache.get((Ops.CONST, (), True)))
print("ucache lookup 1   :", UOpMetaClass.ucache.get((Ops.CONST, (), 1)))