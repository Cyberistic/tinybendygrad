#!/usr/bin/env python3
"""dd-probe-ops.py -- what tinygrad's OWN operator overloads build, called live.

Each case is printed twice: the AST-ish shape the PORT models, and the op/nsrc
sequence of the node CPython actually returned. Nothing transcribed.
"""
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass


ORDER = []
_CALL = UOpMetaClass.__call__


def _call(cls, op, src=(), arg=None, tag=None, metadata=None):
  r = _CALL(cls, op, tuple(s._uop for s in src), arg, tag, metadata)
  if id(r) not in _SEEN:
    _SEEN.add(id(r))
    ORDER.append(r)
  return r


_SEEN = set()
UOpMetaClass.__call__ = _call


def show(tag, u, d=0, seen=None):
  seen = set() if seen is None else seen
  pad = "  " * d
  if id(u) in seen:
    print(f"{pad}SHARED {u.op.name}")
    return
  seen.add(id(u))
  arg = f" arg={u.arg!r}" if u.op is Ops.CONST else (f" name={u.arg.name}" if u.op is Ops.PARAM else "")
  print(f"{pad}{u.op.name} dt={u.dtype}{arg}")
  for s in u.src:
    show(tag, s, d + 1, seen)


a0 = UOp.variable("a0", 0, 0, dtypes.u32)
b0 = UOp.variable("b0", 0, 0, dtypes.u32)
n = (b0 & 31).cast(dtypes.uint)
print("=== `31 - n` as dtype.py:43 writes it, with n = (b0 & 31).cast(dtypes.uint)")
r = 31 - n
show("rsub", r)
print("   op sequence:", ",".join(f"{u.op.name}/{len(u.src)}" for u in ORDER))
print()

ORDER.clear(); _SEEN.clear()
print("=== `n.__rsub__(31)`")
show("rsub2", n.__rsub__(31))
print("   op sequence:", ",".join(f"{u.op.name}/{len(u.src)}" for u in ORDER))
print()

ORDER.clear(); _SEEN.clear()
print("=== `n * -1` (elementwise.py:82 neg)")
show("neg", n * -1)
print()

ORDER.clear(); _SEEN.clear()
print("=== `b0 & 31`")
show("band", b0 & 31)
print()

ORDER.clear(); _SEEN.clear()
print("=== `n.cast(dtypes.uint)`")
show("cast", n.cast(dtypes.uint))
print()

ORDER.clear(); _SEEN.clear()
print("=== `a0u >> 1`")
show("shr1", a0 >> 1)
print()

ORDER.clear(); _SEEN.clear()
print("=== `a1u << 1`")
show("shl1", a0 << 1)
print()

ORDER.clear(); _SEEN.clear()
x32 = UOp.variable("x32", 0, 0, dtypes.u32)
z = UOp.const(0, dtypes.uint32)
print("=== `(b0 >= 32)`")
show("ge", b0 >= 32)
print()

ORDER.clear(); _SEEN.clear()
print("=== `(b0 >= 32).logical_not()`")
show("ge.not", (b0 >= 32).logical_not())
print()

ORDER.clear(); _SEEN.clear()
cc = (b0 >= 32).logical_not().cast(dtypes.uint)
print("=== `(b0 >= 32).logical_not().cast(dtypes.uint)`")
show("cond", cc)
print()

ORDER.clear(); _SEEN.clear()
print("=== `UOp.const(-1, dtypes.uint32)`")
show("m1", UOp.const(-1, dtypes.uint32))
print("   .val =", UOp.const(-1, dtypes.uint32).val, " inner arg =", UOp.const(-1, dtypes.uint32).src[0].arg)
print()

ORDER.clear(); _SEEN.clear()
print("=== `UOp.const(-1, dtypes.int32)`")
show("m1i", UOp.const(-1, dtypes.int32))
print("   .val =", UOp.const(-1, dtypes.int32).val, " inner arg =", UOp.const(-1, dtypes.int32).src[0].arg)
print()

ORDER.clear(); _SEEN.clear()
print("=== `UOp.const(4294967295, dtypes.uint32)`")
show("m1u", UOp.const(4294967295, dtypes.uint32))
print("   .val =", UOp.const(4294967295, dtypes.uint32).val, " inner arg =",
      UOp.const(4294967295, dtypes.uint32).src[0].arg)
print()

ORDER.clear(); _SEEN.clear()
print("=== `UOp.const(2**32, dtypes.float32)`  (dtype.py:34's `x / 2**32` after promote)")
f = UOp.const(2**32, dtypes.float32)
show("f2_32", f)
try:
  print("   .val =", f.val, " inner arg =", f.src[0].arg)
except Exception as e:
  print("   val err", e)