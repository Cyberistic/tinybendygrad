# PROBE: the SAME ast rendered to BOTH tinygrad renderers, so the two arithmetic
# expressions can be compared term for term. e2e_mm.py already proved the GPU's
# INPUTS are bit-identical to CPython's, so any difference in the answer is in the
# arithmetic -- and "the arithmetic" is two different printed expressions.
import os, re
os.environ.setdefault("DEV", "CPU"); os.environ.setdefault("NO_MEMORY_PLANNER", "1")
os.environ.setdefault("BEAM", "0"); os.environ.setdefault("CACHELEVEL", "0")
import numpy as np
from tinygrad import Tensor
from tinygrad.codegen import to_program
from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.device import Device
from tinygrad.uop.ops import Ops, PatternMatcher, UPat
import tinygrad.engine.realize as RZ

class Patched(WGSLRenderer):
  string_rewrite = PatternMatcher([
    (UPat(Ops.STACK, name="x"),
     lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
  ]) + WGSLRenderer.string_rewrite

srcs = {}
orig = RZ.exec_kernel
def traced(ctx, call, ast, devices=None):
  resolved = RZ.resolve_params(call, ctx.input_uops)
  for device, (bufs, dv) in zip(devices or RZ.to_tuple(call.src[1].device),
                                RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
    var_vals = {**ctx.var_vals, **dv}
    g, l = ast.arg.launch_dims(var_vals)
    for name, r in (("clang", ClangRenderer(Device["CPU"])), ("wgsl", Patched(Device["CPU"]))):
      prg = to_program(ast.src[0], r)
      s = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
      srcs.setdefault(name, []).append((tuple(g), s[0] if s else None))
  return orig(ctx, call, ast, devices)

RZ.exec_kernel = traced
rng = np.random.RandomState(0x5EED)
A = Tensor(rng.randn(8, 8).astype(np.float32))
B = Tensor(rng.randn(8, 8).astype(np.float32))
Cm = Tensor(rng.randn(8, 8).astype(np.float32))
E = (A.matmul(B)).matmul(Cm).realize()
RZ.exec_kernel = orig
for name in ("clang", "wgsl"):
  for g, s in srcs.get(name, []):
    print(f"===== {name} global={g}")
    print(s)
