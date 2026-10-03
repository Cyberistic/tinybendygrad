import os
os.environ["DEV"]="CPU"
import tinygrad
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, KernelInfo
import dataclasses

print("tree:", tinygrad.__file__)
print("KernelInfo fields:", [f.name for f in dataclasses.fields(KernelInfo)])
src = (UOp.const(4),)
k1 = KernelInfo(name="k", applied_opts=(1,2,3), opts_to_apply=(9,), beam=3)
s = UOp(Ops.SINK, src, k1)
print("sink:", s.op.name, "nsrc:", len(s.src), "dtype:", s.dtype.name, "shape RAISES (R in normal form)")
print("argstr:", s.argstr())
print()
print("--- real kernelized SINK ---")
t = (Tensor.empty(4,3) @ Tensor.empty(3,5)).realize()
from tinygrad.schedule import create_schedule
sched = create_schedule(t.uop)
k = __import__('tinygrad.schedule', fromlist=['kernelize']).kernelize(sched) if hasattr(__import__('tinygrad.schedule', fromlist=['kernelize']),'kernelize') else None
if k is None:
  import tinygrad.schedule as _S
  print('schedule attrs with ker:', [a for a in dir(_S) if 'ker' in a.lower()])
  raise SystemExit(0)
sinks = [n for n in k.toposort() if n.op is Ops.SINK]
print("n SINK:", len(sinks), "| nodes in kernelized graph:", len(list(k.toposort())))
for sk in sinks:
  ki = sk.arg
  print(" name:", ki.name, "| beam:", ki.beam)
  print(" applied_opts:", ki.applied_opts, "elem types:", [type(x).__name__ for x in ki.applied_opts])
  print(" opts_to_apply:", ki.opts_to_apply, "elem types:", [type(x).__name__ for x in (ki.opts_to_apply or ())])
  print(" argstr:", sk.argstr()[:200])
print()
print("--- is applied_opts ever non-empty / ever a named Option? ---")
import tinygrad.schedule.schedule as sch
print("grep for 'Option' in tinygrad:", os.popen("grep -rl 'class Option' tinygrad/ | head").read().strip() or "(none)")
