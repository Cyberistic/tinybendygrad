import os
os.environ["DEV"]="CPU"
from tinygrad import Tensor, dtypes
import tinygrad.uop.ops as opm
from tinygrad.uop.ops import UOp, Ops, AxisType

print("--- PYLITERAL with a plain UOp literal ---")
c4 = UOp.const(4)
p = UOp(Ops.PYLITERAL, (), (c4,))
print("op:", p.op.name, "arg:", p.arg, "nsrc:", len(p.src), "src:", p.src)
print("argstr:", p.argstr())
print("arg elem types:", [type(x).__name__ for x in p.arg])
print("src empty:", len(p.src)==0)
print("c4 in p.toposort():", c4 in p.toposort())
print("repr:", repr(p))

print()
print("--- MSELECT with a UOp matcher ---")
try:
  m = UOp(Ops.MSELECT, (c4,), (c4,))
  print("ok", m.op.name, m.arg, m.src)
except Exception as e:
  print("raised", type(e).__name__, e)

print()
print("--- CONST with bytes ---")
cb = UOp(Ops.CONST, (), (b"hello",), dtypes.void)
print("op:", cb.op.name, "dtype:", cb.dtype.name, "arg:", cb.arg, "len:", len(cb.arg))
print("argstr:", cb.argstr())
print("byte Const atoms:", [atom for atom in (Ops.BINARY,)])
try:
  print("UOp.const(b'hello').op =", UOp.const(b"hello").op.name)
except Exception as e:
  print("UOp.const(bytes) raised", type(e).__name__, e)
