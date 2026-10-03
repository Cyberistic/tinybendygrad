#!/usr/bin/env python3
"""feasibility probe 2: can a CPython oracle call render_kernel / render_index /
_wmma_name / the HIP extern builders directly? A NO here is a reason with a name."""
import sys, inspect
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops
from tinygrad.renderer.cstyle import (CStyleLanguage, OpenCLRenderer, ClangRenderer, MetalRenderer,
                                      CUDARenderer, HIPRenderer)
from tinygrad.renderer.cstyle import _wmma_name, uops_to_dtypes, is_image_shape

def bare(cls, arch="TEST"):
  o = object.__new__(cls); o.target = Target(f"TEST {arch}"); return o
OCL, CLG, MTL, CUD, HIP = bare(OpenCLRenderer,"gfx000"), bare(ClangRenderer,"x86_64,znver2"), \
                        bare(MetalRenderer,"Apple M4"), bare(CUDARenderer,"sm_89"), bare(HIPRenderer,"gfx1100")
CS = CStyleLanguage(Target("NULL"))
print("kernel_typedef HIP:", repr(HIP.kernel_typedef))
print("kernel_typedef CUDA:", repr(CUD.kernel_typedef))
print("kernel_typedef BASE:", repr(CS.kernel_typedef), repr(CLG.kernel_typedef), repr(OCL.kernel_typedef), repr(MTL.kernel_typedef))

BODY = ["  float4 val0 = (*((float4*)((data1_4+0))));", "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]
def bufs(dtype=dtypes.f32, vol0=False):
  b0 = UOp.param(0, dtype, (), volatile=vol0)
  b1 = UOp.param(1, dtype, ())
  return [("data0_4", (b0, True)), ("data1_4", (b1, True))]

# --- 1. base, clang, opencl, metal, cuda, hip with uops=[] and prefix=None
for nm, r in (("BASE",CS),("CLANG",CLG),("OPENCL",OCL),("METAL",MTL),("CUDA",CUD),("HIP",HIP)):
  try:
    print(f"--- {nm} uops=[] prefix=None")
    print(repr(r.render_kernel("E_4", BODY, bufs(), [], None)))
  except Exception as e:
    print(f"--- {nm} RAISED {type(e).__name__}: {e}")

# --- 2. the half uop / special / nonfinite / vec fixtures
def alu(dtype, n):
  return UOp(Ops.CAST, (UOp.const(1).cast(dtypes.i32),), dtype, arg=None, src=())
half_alu = UOp(Ops.ADD, (UOp.const(1, dtypes.f16), UOp.const(2, dtypes.f16)), None)
print("half_alu:", half_alu, half_alu.dtype, half_alu.addrspace, half_alu._shape, half_alu.max_numel())
try:
  print("CUDA half:", repr(CUD.render_kernel("E_4", BODY, bufs(), [half_alu], None)))
except Exception as e: print("CUDA half RAISED", type(e).__name__, e)
try:
  print("HIP half:", repr(HIP.render_kernel("E_4", BODY, bufs(dtypes.half), [half_alu], None)))
except Exception as e: print("HIP half RAISED", type(e).__name__, e)
spec = UOp.special(UOp.const(3).cast(dtypes.i32), "g0")
print("special:", spec, spec.op, spec.dtype)
try:
  print("HIP spec:", repr(HIP.render_kernel("E_4", BODY, bufs(), [spec], None))[:300])
except Exception as e: print("HIP spec RAISED", type(e).__name__, e)
inf = UOp(Ops.CAST, (UOp.const(float('inf')),), dtypes.f32)
try:
  print("HIP inf:", repr(HIP.render_kernel("E_4", BODY, bufs(), [inf], None))[:400])
except Exception as e: print("HIP inf RAISED", type(e).__name__, e)
sqrt_h = UOp(Ops.SQRT, (UOp.const(1, dtypes.half),), None)
sqrt_f = UOp(Ops.SQRT, (UOp.const(1.0),), None)
try:
  print("HIP ocml:", repr(HIP.render_kernel("E_4", BODY, bufs(dtypes.half), [sqrt_h, sqrt_f], None))[:900])
except Exception as e: print("HIP ocml RAISED", type(e).__name__, e)
# vec: count 4 half
v4 = UOp(Ops.CAST, (UOp.const(1, dtypes.f16).view(4),), dtypes.half) if hasattr(UOp, 'view') else None
print("uops_to_dtypes([half_alu, sqrt_f, sqrt_h]):", uops_to_dtypes([half_alu, sqrt_f, sqrt_h]))
try:
  vecu = UOp.const(1, dtypes.half).reshape((4,)) if hasattr(UOp, 'reshape') else None
  print("vec const:", vecu, vecu.max_numel() if vecu else None)
except Exception as e: print("vec RAISED", type(e).__name__, e)

# --- 3. render_index with a hand-set ctx
alu_buf = UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.ALU)
i0 = UOp(Ops.CAST, (UOp.const(0),), dtypes.i32)
i1 = UOp(Ops.CAST, (UOp.const(1),), dtypes.i32)
CS.r = {alu_buf: "B", i0: "R"}
print("idx alu k0:", repr(CS.render_index(i0, alu_buf, i0)))
print("idx alu k1:", repr(CS.render_index(i1, alu_buf, i1)))
lane = UOp(Ops.INDEX, (i0,), dtypes.f32)
CS.r[lane] = "R"
print("idx lane:", repr(CS.render_index(lane, alu_buf, lane)))
reg_buf = UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.REG)
CS.r[reg_buf] = "B"
addi = UOp(Ops.CAST, (i0,), dtypes.i32)
CS.r[addi] = "R"
print("idx reg add:", repr(CS.render_index(addi, reg_buf, addi)))

# --- 4. _wmma_name
for dims, din, dout in (((16,16,16), dtypes.half, dtypes.half), ((16,16,16), dtypes.int8, dtypes.int8),
                        ((8,8,32), dtypes.bfloat16, dtypes.bfloat16), ((16,16,128), dtypes.fp8e4m3, dtypes.fp8e4m3)):
  srcs = [UOp.param(0, din, (16,16,16))]
  u = UOp(Ops.WMMA, srcs, dout, arg=__import__('tinygrad.uop.ops',fromlist=['x']).AWmma(list(dims), din, 32, []))
  try: print("wmma", dims, din, dout, "->", repr(_wmma_name(u)))
  except Exception as e: print("wmma RAISED", type(e).__name__, e)

# --- 5. buftypes through render_kernel's signature
for nm, r in (("BASE",CS),("CLANG",CLG),("CUDA",CUD)):
  u = UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.ALU)
  out = r.render_kernel("E", ["  ;"], [("v0", (u, True))], [], None)
  print(nm, "alu arg:", out.split("(")[1].split(")")[0])

# --- 6. does any DType .name contain a space at HEAD?
sp = [str(d) for d in dtypes.all if " " in d.name]
print("dtypes with a SPACE in .name:", sp)
import tinygrad.dtype as td
allnames = sorted({d.name for d in td.dtypes if hasattr(d,'name')})
print("ALL names at HEAD:", allnames)
print("names with space:", [n for n in allnames if " " in n])