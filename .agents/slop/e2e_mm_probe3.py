# PROBE 3: ONE SIZE PER PROCESS. probe2 reported "0 launches" for every size
# after the first, which is the cache trace_forward.py's header warns about
# ("a warm-up forward leaves the traced pass with ZERO launches"): the traced
# pass hits the linear cache. So the size sweep must not share a process.
# Usage: e2e_mm_probe3.py M K N
import os, re, sys
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
  string_rewrite = PatternMatcher([
    (UPat(Ops.STACK, name="x"),
     lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
  ]) + WGSLRenderer.string_rewrite

renderer = Patched(Device["CPU"])
orig = RZ.exec_kernel
out = []

def traced(ctx, call, ast, devices=None):
  resolved = RZ.resolve_params(call, ctx.input_uops)
  for device, (bufs, dv) in zip(devices or RZ.to_tuple(call.src[1].device),
                                RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
    g, l = ast.arg.launch_dims(var_vals := {**ctx.var_vals, **dv})
    rec = {"global": list(g), "local": list(l),
           "bufs": [(b.size, str(b.dtype)) for b in bufs], "vals": list(ast.arg.vals(var_vals))}
    try:
      prg = to_program(ast.src[0], renderer)
      src = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
      rec["wgsl"] = src[0] if src else None
      m = ENTRY_RE.search(rec["wgsl"] or "")
      rec["entry"] = m.group(1) if m else None
    except Exception as e:
      rec["wgsl"] = None; rec["wgslError"] = f"{type(e).__name__}: {e}"
    out.append(rec)
  return orig(ctx, call, ast, devices)

RZ.exec_kernel = traced
M, K, N = (int(v) for v in sys.argv[1:4])
rng = np.random.RandomState(0x5EED)
A = Tensor(rng.randn(M, K).astype(np.float32)); B = Tensor(rng.randn(K, N).astype(np.float32))
C = A.matmul(B).realize()
print(f"{M}x{K}x{N} csum={float(C.numpy().sum()):.6f} launches={len(out)}")
for r in out:
  print(f"  global={r['global']} local={r['local']} bufs={r['bufs']} entry={r.get('entry')} "
        f"wgsl={len(r['wgsl'] or '')}B err={r.get('wgslError')}")
