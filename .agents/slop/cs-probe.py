#!/usr/bin/env python3
"""probe what CPython will let a kern2 / idx oracle call. Every question here is a
feasibility question, and a negative answer is a reason and not a bug."""
import sys, inspect
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops
from tinygrad.renderer import Renderer
from tinygrad.renderer.cstyle import (CStyleLanguage, OpenCLRenderer, ClangRenderer, MetalRenderer,
                                      CUDARenderer, HIPRenderer)

print("param sig:", inspect.signature(UOp.param))
print("uops_to_dtypes:", inspect.getsource(__import__('tinygrad.renderer.cstyle', fromlist=['x']).uops_to_dtypes))
print("is_image_shape:", inspect.getsource(__import__('tinygrad.renderer.cstyle', fromlist=['x']).is_image_shape))
print("strip_parens:", inspect.getsource(__import__('tinygrad.renderer.cstyle', fromlist=['x']).strip_parens))

# 1. type_map over dtypes.all -- THE tmap QUESTION. Does it raise?
CS = CStyleLanguage(Target("NULL"))
try:
  print("tmap.get:", ",".join(CS.type_map.get(dt, dt.name) for dt in dtypes.all))
except Exception as e:
  print("tmap.get RAISED", type(e).__name__, e)
try:
  print("tmap[]:", ",".join(CS.type_map[dt] for dt in dtypes.all))
except Exception as e:
  print("tmap[] RAISED", type(e).__name__, e)
print("dtypes.all:", [str(d) for d in dtypes.all])
print("in type_map:", [(str(d), d in CS.type_map) for d in dtypes.all])

# 2. code_for_workitem on the base -- {} per the comment
print("base code_for_workitem:", CS.code_for_workitem)

# 3. an ALU-space uop for render_index
print("AddrSpace members:", list(AddrSpace))
p = UOp.param(0, dtypes.f32, ())
print("param addrspace", p.addrspace, "max_numel", p.max_numel(), "arg", p.arg, "shape", p._shape)
try:
  pa = UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.ALU)
  print("ALU param ok:", pa.addrspace, pa.max_numel())
except Exception as e:
  print("ALU param RAISED", type(e).__name__, e)
try:
  pl = UOp.placeholder((4,), dtypes.f32, slot=2, addrspace=AddrSpace.LOCAL)
  print("LOCAL placeholder:", pl.addrspace, pl.max_numel(), pl._shape, pl.arg)
except Exception as e:
  print("LOCAL placeholder RAISED", type(e).__name__, e)

# 4. _wmma_name
print("wmma sig:", inspect.signature(__import__('tinygrad.renderer.cstyle', fromlist=['x'])._wmma_name))
print(inspect.getsource(__import__('tinygrad.renderer.cstyle', fromlist=['x'])._wmma_name))
print("wmma_args:", inspect.getsource(__import__('tinygrad.renderer.cstyle', fromlist=['x']).wmma_args))