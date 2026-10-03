# PROBE 4: WHAT DOES THE GLOBAL SIZE EVER LOOK LIKE? Every bare matmul came back
# global=[1,1,1] local=[1,1,1] -- one workgroup, one invocation, the whole matmul
# unrolled into a double loop. That is a real computation but it exercises no
# dispatch geometry. So: batched matmul, an elementwise chain, and a big relu,
# to find a launch whose global size is bigger than 1 in some axis.
import os, re
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

def show(label):
  print(f"--- {label}: {len(out)} launch(es)")
  for r in out:
    print(f"      global={r['global']} local={r['local']} nbufs={len(r['bufs'])} sizes={[b[0] for b in r['bufs']]}"
          f" vals={r['vals']} entry={r.get('entry')} wgsl={len(r['wgsl'] or '')}B err={r.get('wgslError')}")
  out.clear()

rng = np.random.RandomState(0x5EED)
RZ.exec_kernel = traced

a4 = Tensor(rng.randn(4, 8, 8).astype(np.float32)); b4 = Tensor(rng.randn(4, 8, 8).astype(np.float32))
c4 = a4.matmul(b4).realize()
show("batched 4x(8x8 @ 8x8)")

x = Tensor(rng.randn(64, 64).astype(np.float32)); y = x.relu().realize()
show("relu 64x64")

s = Tensor(rng.randn(8, 8).astype(np.float32)); t = Tensor(rng.randn(8, 8).astype(np.float32))
u = (s.matmul(t)).realize(); v = (u * u + u).softmax(-1).realize()
show("chain mm -> (x*x+x) -> softmax  8x8")
