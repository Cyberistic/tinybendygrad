# PROBE: one matmul launch, traced out of tinygrad, with tinygrad's OWN WGSL.
# Staging probe for e2e_mm.py -- answers "is a single-launch matmul trace
# reachable" before any of it is written twice.
import base64, os, re, sys
from pathlib import Path

os.environ.setdefault("DEV", "CPU")
os.environ.setdefault("NO_MEMORY_PLANNER", "1")
os.environ.setdefault("BEAM", "0")
os.environ.setdefault("CACHELEVEL", "0")

import numpy as np
from tinygrad import Tensor
from tinygrad.codegen import to_program
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.device import Device
from tinygrad.uop.ops import Ops
import tinygrad.engine.realize as RZ

M = K = N = 8
ENTRY_RE = re.compile(r"@compute[^\n]*\bfn\s+(\w+)\s*\(", re.M)
renderer = WGSLRenderer(Device["CPU"])

launches = []
orig = RZ.exec_kernel

def traced(ctx, call, ast, devices=None):
  resolved = RZ.resolve_params(call, ctx.input_uops)
  for device, (bufs, device_vars) in zip(devices or RZ.to_tuple(call.src[1].device),
                                          RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
    var_vals = {**ctx.var_vals, **device_vars}
    g, l = ast.arg.launch_dims(var_vals)
    rec = {"global": list(g), "local": list(l),
           "bufs": [(b.size, str(b.dtype)) for b in bufs],
           "vals": list(ast.arg.vals(var_vals))}
    try:
      prg = to_program(ast.src[0], renderer)
      src = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
      rec["wgsl"] = src[0] if src else None
      m = ENTRY_RE.search(rec["wgsl"] or "")
      rec["entry"] = m.group(1) if m else str(prg.src[0].arg.function_name)
    except Exception as e:
      rec["wgsl"] = None
      rec["wgslError"] = f"{type(e).__name__}: {e}"
    launches.append(rec)
  return orig(ctx, call, ast, devices)

RZ._orig_exec_kernel = orig
RZ.exec_kernel = traced

rng = np.random.RandomState(0x5EED)
A = Tensor(rng.randn(M, K).astype(np.float32))
B = Tensor(rng.randn(K, N).astype(np.float32))
C = A.matmul(B).realize()

print("launches:", len(launches))
for i, r in enumerate(launches):
  print(f"  {i} global={r['global']} local={r['local']} bufs={r['bufs']} vals={r['vals']} "
        f"entry={r.get('entry')} wgsl={len(r['wgsl'] or '')}B err={r.get('wgslError')}")
  print("   b64 in :", base64.b64encode(bytes(A.uop.base.realized.as_memoryview(allow_zero_copy=True))).decode()[:40])
print("WGSL of launch 0:")
print(launches[0].get("wgsl"))
print("CPython answer C[0,:] =", C.numpy()[0])
print("shape", C.shape)
