# PROBE 2: the float4 STACK shim from trace_forward.py, and a SIZE SWEEP -- how
# many workgroups does tinygrad's matmul schedule actually want?
import base64, os, re
os.environ.setdefault("DEV", "CPU"); os.environ.setdefault("NO_MEMORY_PLANNER", "1")
os.environ.setdefault("BEAM", "0"); os.environ.setdefault("CACHELEVEL", "0")
import numpy as np
from tinygrad import Tensor
from tinygrad.codegen import to_program
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.device import Device
from tinygrad.uop.ops import Ops, PatternMatcher, UPat
import tinygrad.engine.realize as RZ

ENTRY_RE = re.compile(r"@compute[^\n]*\bfn\s+(\w+)\s*\(", re.M)

class Patched(WGSLRenderer):
  """trace_forward.py's GAP 2 verbatim: a float4 STACK reaches
  CStyleLanguage.string_rewrite with `float4 = None` and crashes. The arity is
  the stack's own src count and the element type `type_map[x.dtype]`, NOT
  `render_type(x)` -- a GLOBAL source renders as `var<storage,read_write>f32`,
  which WGSL has no `vec<...>` of."""
  string_rewrite = PatternMatcher([
    (UPat(Ops.STACK, name="x"),
     lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
  ]) + WGSLRenderer.string_rewrite

renderer = Patched(Device["CPU"])
orig = RZ.exec_kernel

def make_traced(out):
  def traced(ctx, call, ast, devices=None):
    resolved = RZ.resolve_params(call, ctx.input_uops)
    for device, (bufs, device_vars) in zip(devices or RZ.to_tuple(call.src[1].device),
                                            RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
      g, l = ast.arg.launch_dims(var_vals := {**ctx.var_vals, **device_vars})
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
        rec["wgsl"] = None; rec["wgslError"] = f"{type(e).__name__}: {e}"
      out.append(rec)
    return orig(ctx, call, ast, devices)
  return traced

for (M, K, N) in [(8,8,8), (16,16,16), (32,32,32), (64,64,64), (8,8,4)]:
  out = []
  RZ.exec_kernel = make_traced(out)
  rng = np.random.RandomState(0x5EED)
  A = Tensor(rng.randn(M, K).astype(np.float32)); B = Tensor(rng.randn(K, N).astype(np.float32))
  C = A.matmul(B).realize()
  RZ.exec_kernel = orig
  print(f"=== {M}x{K}x{N}: {len(out)} launch(es)")
  for r in out:
    print(f"    global={r['global']} local={r['local']} bufs={r['bufs']} entry={r.get('entry')} "
          f"wgsl={len(r['wgsl'] or '')}B err={r.get('wgslError')}")
  if out and out[0].get("wgsl"):
    print("    " + out[0]["wgsl"].replace("\n", "\n    ")[:1800])
