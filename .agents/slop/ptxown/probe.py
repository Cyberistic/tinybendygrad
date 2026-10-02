#!/usr/bin/env python3
import sys; sys.path.insert(0,'.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import Ops, UOp, PatternMatcher, ParamArg
from tinygrad.renderer import ptx as ptxmod
from tinygrad.helpers import Target
class Shell(ptxmod.PTXRenderer):
  def __init__(self, target): self.target = target
Shell.render = ptxmod.PTXRenderer.render
Shell.render_kernel = ptxmod.PTXRenderer.render_kernel
class _NoRewrite:
  def rewrite(self, u, ctx=None): return []
ptxmod.string_rewrite = _NoRewrite()

def buf(dt=dtypes.f32, slot=0, addr=AddrSpace.GLOBAL, size=4):
  return UOp(Ops.BUFFER, src=UOp.device_range_src("CUDA"), arg=ParamArg(slot, dt, size=size, addrspace=addr))
def prm(dt=dtypes.f32, slot=0, addr=AddrSpace.GLOBAL, size=4):
  return UOp(Ops.PARAM, arg=ParamArg(slot, dt, size=size, addrspace=addr))
def cast(x, dt): return UOp(Ops.CAST, (x,), dt)
I=lambda v, dt: cast(UOp(Ops.CONST, (), v), dt)
r = Shell(Target(interface="", device="CUDA", arch="sm_80"))
def show(nm, root):
  try:
    s = r.render(UOp.sink(root).toposort())
  except Exception as e:
    print(nm, "ERR", type(e).__name__, str(e)[:110]); return
  print(nm, "| regs:")
  for u in UOp.sink(root).toposort():
    v = r.r.get(u)
    if v is not None: print("   ", u.op.name, u.dtype.name, "->", v if isinstance(v,str) else "["+", ".join(v)+"]")
  print("   regs:", [l for l in s.split("\n") if ".reg" in l])

b = buf()
show("BUFFER", b)
show("PARAM", prm())
show("ADD", UOp(Ops.ADD, (b, I(1.0, dtypes.f32)), None))
show("ADD+ADD", UOp(Ops.ADD, (UOp(Ops.ADD, (b, I(1.0, dtypes.f32)), None), I(2.0, dtypes.f32)), None))
show("REGBUF", buf(addr=AddrSpace.REG, size=8))
show("SPECIAL", UOp(Ops.SPECIAL, (), (), ("l", 1)))
show("LOAD2", UOp(Ops.LOAD, (buf(size=8), UOp(Ops.SPECIAL, (), (), ("g", 0))), None))
show("STACK", UOp(Ops.STACK, (b, UOp(Ops.MUL, (b, I(1.0,dtypes.f32)), None)), None))
show("AFTER", UOp(Ops.AFTER, (b,), None))
show("CAST", cast(b, dtypes.i32))
show("NOOP", UOp(Ops.NOOP, (), None))