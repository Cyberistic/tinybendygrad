import os
os.environ["DEV"]="CPU"
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg

t = Tensor.empty(4,3)
print("before realize:", [(n.op.name, len(n.src)) for n in t.uop.toposort()])
t.realize()
print("after  realize:", [(n.op.name, len(n.src)) for n in t.uop.toposort()])
found=False
for n in t.uop.toposort():
  if n.op is Ops.BUFFER:
    a = n.arg
    print()
    print("BUFFER arg type:", type(a).__name__)
    print("  buffer:", type(a.buffer).__name__, "repr:", repr(a.buffer)[:160])
    print("  buffer attrs:", [x for x in dir(a.buffer) if not x.startswith('_')][:30])
    print("  size:", a.size, "device:", a.device, "dtype:", a.dtype.name)
    print("  NAMED fields:", list(vars(a).keys()))
    print("  what graphcmp.py emits today: 'realized' + 'i' + str(a.buffer)")
    print("    ->", ("realized"+"i"+str(a.buffer))[:200])
    found=True
    break
print("found BUFFER:", found)
