#!/usr/bin/env python3
# renderer-oracle.py -- the CPython half of the gate for
# tinybendygrad/renderer/__init__.bend and tinybendygrad/renderer/cstyle.bend.
#
# Prints one row per claim, `name = [value]`, which is the same LINE the Bend
# lane prints.  diff the two and every claim holds iff the diff is empty.
#
#   ./bin/bend tinybendygrad/renderer/cstyle.bend > /tmp/bd.txt
#   python3 .agents/slop/tools/renderer-oracle.py cstyle > /tmp/py.txt
#   diff /tmp/bd.txt /tmp/py.txt
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops, KernelInfo, AxisType
from tinygrad.renderer import Renderer, Estimates, with_storage
from tinygrad.renderer.cstyle import (CStyleLanguage, OpenCLRenderer, ClangRenderer, MetalRenderer,
                                     CUDARenderer, HIPRenderer)

def R(nm, got):
  print(f"{nm} = [{got}]")

def alu(op, *xs):
  x = xs[0]
  for y in xs[1:]: x = x.alu(op, y)
  return x

def I(n): return UOp.const(n).cast(dtypes.int)

# ---------------------------------------------------------------- init.bend
def rows_init():
  r = Renderer(None)
  R("R.suffix", repr(r.suffix))
  R("R.supports_float4", repr(r.supports_float4))
  R("R.has_local", repr(r.has_local))
  R("R.has_shared", repr(r.has_shared))
  R("R.global_max", ",".join(str(x) for x in r.global_max))
  R("R.local_max", ",".join(str(x) for x in r.local_max))
  R("R.global_prod_max", repr(r.global_prod_max))
  R("R.shared_max", repr(r.shared_max))
  R("R.tensor_cores", repr(r.tensor_cores))
  R("R.extra_matcher", repr(r.extra_matcher))
  R("R.code_for_op", repr(r.code_for_op))
  R("R.supported_n", len(r.supported_dtypes()))
  R("R.supported", ",".join(sorted(str(d) for d in r.supported_dtypes())))
  R("dtypes.all", ",".join(sorted(str(d) for d in dtypes.all)))
  R("est.default", repr(Estimates()))
  R("est.add", repr(Estimates(2, 3, 4) + Estimates(10, 20, 30)))
  R("est.add0", repr(Estimates(0, 0, 0) + Estimates(1, 2, 3)))
  R("est.simplify", repr(Estimates(2, 3, 4).simplify()))
  R("est.simplify.type", type(Estimates(2, 3, 4).simplify().ops).__name__)
  R("ws.buffer", repr(with_storage(UOp.param(0, dtypes.float, 3), dtypes.half)))
  R("ws.global", repr(with_storage(UOp.param(1, dtypes.char, 2, addrspace=AddrSpace.GLOBAL), dtypes.half)))

# --------------------------------------------------------------- cstyle.bend
CS = CStyleLanguage(Target("NULL"))
# The device renderers build a COMPILER in __init__ (clang, nvrtc, hipcc), which
# is the runtime layer and not what this file gates. `object.__new__` skips
# __init__ entirely: every attribute `render` reads is a CLASS attribute, and
# `target` is the only instance one.
def _bare(cls, arch="TEST"):
  o = object.__new__(cls)
  o.target = Target(f"TEST {arch}")
  return o
OCL = _bare(OpenCLRenderer, "gfx000")
CLG = _bare(ClangRenderer, "x86_64,znver2")
MTL = _bare(MetalRenderer, "Apple M4")
CUD = _bare(CUDARenderer, "sm_89")

def render(sinks, r=CS): return r.render(UOp.sink(*sinks, arg=KernelInfo()).toposort())

def f_load_store():
  p0 = UOp.param(0, dtypes.float, 4)
  p1 = UOp.param(1, dtypes.float, 4)
  v = p0[I(0)].load()
  return [UOp.store(p1[I(0)], v + UOp.const(2.0).cast(dtypes.float))]

def f_alu():
  # nested binaries, so the strip_parens clause has something to strip: the
  # inner (a+b) KEEPS its parens when it is a right operand of + and LOSES them
  # when it is an operand of a lower-precedence op.
  p = UOp.param(0, dtypes.int, 2)
  a = p[I(0)].load()
  b = p[I(1)].load()
  t = alu(Ops.SUB, alu(Ops.ADD, a, b), alu(Ops.MUL, a, b))
  t = alu(Ops.XOR, alu(Ops.AND, a, b), alu(Ops.OR, a, b))
  t = alu(Ops.SHR, alu(Ops.SHL, a, b), t)
  t = alu(Ops.CMPNE, t, alu(Ops.CMPEQ, a, b))
  return [UOp.store(p[I(0)], t)]

def f_consts():
  # one cast per dtype in base_rewrite's const order; the default arm is int
  p = UOp.param(0, dtypes.float, 1)
  acc = None
  for dt in (dtypes.float, dtypes.half, dtypes.bfloat16, dtypes.double, dtypes.long, dtypes.ulong,
             dtypes.uint, dtypes.uchar, dtypes.ushort, dtypes.char, dtypes.short, dtypes.int,
             dtypes.bool):
    c = UOp.const(3, dt).cast(dtypes.float)
    acc = c if acc is None else acc + c
  return [UOp.store(p[I(0)], acc)]

def f_smem():
  # a LOCAL buffer: render_buffer declares it, render_index adds the offset
  smem = UOp.placeholder((4,), dtypes.float, slot=2, addrspace=AddrSpace.LOCAL)
  ix = smem[I(1)]
  return [UOp.store(ix, ix.load() + ix.load())]

def f_special():
  # SPECIAL needs a device that supplies code_for_workitem
  p = UOp.param(0, dtypes.float, 1)
  g = UOp.special(UOp.const(3).cast(dtypes.int), "g0")
  l = UOp.special(UOp.const(1).cast(dtypes.int), "l0")
  return [UOp.store(p[g], p[g].load() + p[l].load())]

def f_range():
  p = UOp.param(0, dtypes.float, 8)
  n = p[I(0)].load()
  rg = UOp.range(n, 0, AxisType.GLOBAL)
  return [UOp.store(p[rg], rg + rg)]

def f_cast():
  p = UOp.param(0, dtypes.int, 1)
  a = p[I(0)].load()
  return [UOp.store(p[I(0)], a.cast(dtypes.half).bitcast(dtypes.ushort).cast(dtypes.uint).cast(dtypes.int))]

def f_stack():
  p = UOp.param(0, dtypes.float, 2)
  return [UOp.store(p[I(0)], UOp.stack(p[I(0)].load(), p[I(1)].load()))]

def f_stack4():
  # the float4_style branch: STACK of four, which Clang renders as a brace init
  p = UOp.param(0, dtypes.float, 4)
  return [UOp.store(p[I(0)], UOp.stack(p[I(0)].load(), p[I(1)].load(), p[I(2)].load(), p[I(3)].load()))]

def rows_cstyle():
  R("k1_load_store", render(f_load_store()))
  R("k2_alu", render(f_alu()))
  R("k3_consts", render(f_consts()))
  R("k4_smem", render(f_smem()))
  R("k6_range", render(f_range()))
  R("k7_cast", render(f_cast()))
  R("k8_stack.clang", render(f_stack(), CLG))
  R("k8_stack4.clang", render(f_stack4(), CLG))
  R("k5_special.ocl", render(f_special(), OCL))
  for nm, r in (("clang", CLG), ("metal", MTL), ("cuda", CUD)):
    R(f"k1_load_store.{nm}", render(f_load_store(), r))
    R(f"k4_smem.{nm}", render(f_smem(), r))

if __name__ == "__main__":
  (rows_init if sys.argv[1] == "init" else rows_cstyle)()