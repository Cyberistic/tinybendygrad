# trace_forward.py -- the ORACLE, and the WGSL the browser lane replays.
#
# WHY THIS SHAPE. `WebGpuDevice.__init__` needs the native Dawn binding, so the
# WebGPU device is unreachable from CPython. But the RENDERER is not: codegen's
# `pm_to_program` renders to an Ops.SOURCE uop before anything is compiled, and
# `exec_kernel` (tinygrad/engine/realize.py:160) is the one place that knows
# every launch's binding order, dispatch geometry and buffer contents. So the
# browser lane replays a TRACE OF REAL KERNEL LAUNCHES rather than a hand-written
# WGSL approximation, and the numbers the browser must reproduce are CPU's.
#
# WHAT IT EMITS, into examples/webgpu/mnist/:
#   net.json   the program: buffers (weights + input, as u32 bit patterns),
#              kernels (tinygrad's WGSL, entry name, global/local, binding order)
#   oracle.json  the logits CPython actually produced, same bit patterns
#
# The model is examples/beautiful_mnist.py's OWN Model, imported, at eval
# (TRAINING=0) -- which is `get_test_acc`'s path at py:29-30, not a rewrite.

import base64, json, os, re, sys
from pathlib import Path

os.environ.setdefault("DEV", "CPU")
os.environ.setdefault("NO_MEMORY_PLANNER", "1")   # one storage per buffer: no aliasing to reason about
os.environ.setdefault("BEAM", "0")
os.environ.setdefault("CACHELEVEL", "0")   # the warm-up must not let the traced pass hit a cache

import numpy as np
from tinygrad import Tensor, Context
from tinygrad.codegen import to_program
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.device import Device
from tinygrad.uop.ops import Ops, PatternMatcher, UPat
from tinygrad import dtypes
import tinygrad.engine.realize as RZ

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from examples.beautiful_mnist import Model
from tinygrad.nn.state import get_parameters, get_state_dict

BS = int(os.environ.get("TRACE_BS", "1"))
OUT = Path(__file__).resolve().parents[3] / "examples/webgpu/mnist"

# --------------------------------------------------------------------------
# 1. THE TRACE. Wraps exec_kernel, so nothing about the schedule is re-derived.
# --------------------------------------------------------------------------

launches = []          # one record per kernel launch, in execution order
buffers = {}           # name -> {size, dtype, bits}
_seen = {}             # id(base buffer) -> name
_keep = []             # strong refs, so an id cannot be recycled onto another buffer
_written = set()       # buffer names some earlier launch in THIS trace wrote
_order = [0]
ENTRY_RE = re.compile(r"@compute[^\n]*\bfn\s+(\w+)\s*\(", re.M)

def bits_of(buf):
  """The buffer's bytes, base64'd. Still exactly the u32 words the gate is about:
  base64 is a transport, and the page reads them back as a Uint32Array, so a
  disagreement cannot be a rounding artefact of a printed decimal."""
  raw = bytes(buf.as_memoryview(allow_zero_copy=True))
  assert len(raw) % 4 == 0, f"{buf.dtype} has {buf.dtype.itemsize}-byte items, not 4"
  return base64.b64encode(raw).decode("ascii")

def name_of(buf):
  # `base` is the storage owner, so a view names as its allocation. The strong
  # ref is load-bearing: nothing else in the trace holds these Buffers, so CPython
  # frees them and hands the SAME id to the next allocation. Measured: without it
  # a recycled id made launch 11 report b0/b1 -- BatchNorm's running stats, which
  # TRAINING=0 provably does not touch -- as wildly wrong.
  key = id(buf.base)
  if key not in _seen:
    _seen[key] = f"b{_order[0]}"
    _order[0] += 1
    _keep.append(buf.base)
  return _seen[key]

class MNISTWGSL(WGSLRenderer):
  """WGSLRenderer plus EXACTLY TWO string-level shims, each covering a measured
  gap in tinygrad/renderer/wgsl.py. Neither touches the uop graph, the rewrites
  or the arithmetic: both only spell a uop tinygrad itself built.

  GAP 1 -- `code_for_op` has no Ops.FDIV. Measured: the key sets of
  ClangRenderer.code_for_op and WGSLRenderer.code_for_op differ by exactly
  Ops.FDIV in Clang's favour (cstyle.py:311 defines it, wgsl.py:60 does not), and
  this model hits it -- BatchNorm's eval-mode `rsqrt(running_var + eps)` is one
  FDIV per element, and without this line `render_alu` raises KeyError: Ops.FDIV.

  GAP 2 -- `float4` is None, so a float4 STACK raises
  "AttributeError: 'NoneType' object has no attribute 'replace'" at cstyle.py:53.
  `supports_float4 = False` (wgsl.py:58) is read in exactly ONE place,
  codegen/late/coalesce.py:143, and that only gates vectorised LOAD/STORE; a
  STACK built elsewhere still reaches string_rewrite. And it is not always
  WIDTH 4: measured, the max-pool kernel `r_320_10_2_2` stacks two f32, and a
  `vec4<f32>(a, b)` is rejected by WGSL with "no matching constructor for
  'vec4<f32>(f32, f32)'". So the vector's arity comes from the stack's own src
  count, and its element type from `type_map[x.dtype]` -- NOT from
  `render_type(x)`, which for a GLOBAL source is `var<storage,read_write>f32`,
  a type WGSL does not have inside `vec<...>`.
  """
  string_rewrite = PatternMatcher([
    (UPat(Ops.STACK, name="x"),
     lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
  ]) + WGSLRenderer.string_rewrite
  code_for_op = {**WGSLRenderer.code_for_op, Ops.FDIV: lambda a, b, dtype: f"({a}/{b})"}

# Declared after the class: Bend's own lesson from langs/NOTES.md applies here too,
# a dotted name used before it exists is a forward reference.
_renderer = MNISTWGSL(Device["CPU"])

def traced_exec_kernel(ctx, call, ast, devices=None):
  import tinygrad.uop.ops as U
  resolved = RZ.resolve_params(call, ctx.input_uops)
  rec = {"names": [], "global": None, "local": None, "wgsl": None, "entry": None, "bufs": []}
  for device, (bufs, device_vars) in zip(devices or RZ.to_tuple(call.src[1].device),
                                         RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
    var_vals = {**ctx.var_vals, **device_vars}
    prg_bufs = [b.ensure_allocated() for b in bufs]
    g, l = ast.arg.launch_dims(var_vals)
    rec["global"], rec["local"] = list(g), list(l)
    try:
      prg = to_program(ast.src[0], _renderer)          # the SAME ast, rendered to WGSL
      src = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
      rec["wgsl"] = src[0] if src else None
      # The entry point is read back out of the WGSL rather than from the uop
      # graph: that string is what the browser hands createComputePipeline, so
      # one source of truth decides both.
      m = ENTRY_RE.search(rec["wgsl"] or "")
      rec["entry"] = m.group(1) if m else str(prg.src[0].arg.function_name)
    except Exception as e:
      # A renderer that cannot express a uop the schedule built is a fact about
      # the MODEL, so name the launch rather than dropping the kernel silently.
      rec["wgsl"], rec["entry"] = None, None
      rec["wgslError"] = f"{type(e).__name__}: {e}"
      print(f"  !! WGSL render failed on global={list(g)} local={list(l)}: {type(e).__name__}: {e}", file=sys.stderr)
    for b in prg_bufs:
      n = name_of(b)
      if n not in buffers:
        buffers[n] = {"size": b.size, "dtype": str(b.dtype), "b64": bits_of(b)}
      rec["bufs"].append(n)
    rec["vals"] = list(ast.arg.vals(var_vals))
    rec["_bufs"] = prg_bufs
    # ProgramInfo.globals is position -> buffer slot and ProgramInfo.outs is a set
    # of slots, so the OUTPUT POSITIONS in this launch's `bufs` are the positions
    # whose slot is in outs. The page needs them: a buffer an earlier launch
    # already wrote does not need re-uploading, and a buffer nothing has written
    # does, and that distinction is the whole dataflow.
    out_slots = set(ast.arg.outs)
    rec["outs"] = [pos for pos, slot in enumerate(ast.arg.globals) if slot in out_slots]
  launches.append(rec)
  # Record the page's INPUTS for this launch: every bound buffer that no EARLIER
  # launch wrote. A buffer an earlier launch wrote is already correct on the GPU
  # by then, so re-uploading it would turn the replay into a memory dump instead
  # of a computation. A buffer nothing has written is a weight, the input image,
  # or a scalar, and its pre-state has to come from CPython.
  #
  # WHY NOT SIMPLY "the contents at first bind": tinygrad's allocator RECYCLES
  # (tinygrad/device.py:270, `if len(c:=self.cache[(size, options)]): return
  # c.pop()`), so one Buffer object can be a BatchNorm running_var at launch 0 and
  # a conv bias at launch 11. Measured: a first-bind snapshot made launch 11
  # disagree on four 32-element buffers that TRAINING=0 provably never writes.
  for i, b in enumerate(rec["_bufs"]):
    if i in rec["outs"]:
      continue
    if b.base.dtype.itemsize == 4: rec.setdefault("in", {})[name_of(b)] = bits_of(b)
  ets = RZ._orig_exec_kernel(ctx, call, ast, devices)
  # Read the buffers back AFTER the launch. A single end-of-program oracle says
  # only "17 kernels in, 0/10 logits right"; a per-launch snapshot says WHICH
  # kernel first diverged, which is the only useful thing to look at.
  for b in rec["_bufs"]:
    if b.base.dtype.itemsize == 4: rec.setdefault("after", {})[name_of(b)] = bits_of(b)
  _written.update(rec["bufs"][i] for i in rec["outs"])
  return ets

# --------------------------------------------------------------------------
# 2. THE MODEL, with weights fixed so the oracle is reproducible.
# --------------------------------------------------------------------------

def deterministic(model, seed=0xC0FFEE):
  """Fix the weights so the oracle is reproducible, WITHOUT touching BatchNorm's
  running statistics: an untrained BatchNorm has running_mean=0, running_var=1
  (nn/__init__.py), and eval-mode BatchNorm divides by sqrt(running_var + eps),
  so a random NEGATIVE running_var makes the whole forward pass NaN."""
  rng = np.random.RandomState(seed)
  for name, p in get_state_dict(model).items():
    # An untrained BatchNorm keeps running_mean=0 and running_var=1, which is
    # what nn/__init__.py constructs; randomizing them makes eval-mode BatchNorm
    # divide by sqrt(negative), and the whole forward pass is NaN.
    if "running_" in name or not dtypes.is_float(p.dtype):
      continue
    # A spread of magnitudes so relu/max/sum cannot pass on a constant tensor.
    v = rng.randn(p.numel()).astype(np.float32) * np.float32(0.1) + np.float32(0.01 * (1 + rng.randint(0, 3)))
    p.assign(Tensor(v.reshape(p.shape).copy()))

def main():
  OUT.mkdir(parents=True, exist_ok=True)
  model = Model()
  deterministic(model)
  x = Tensor(np.linspace(-0.5, 0.5, 1 * 1 * 28 * 28, dtype=np.float32).reshape(1, 1, 28, 28))
  # NO warm-up forward, and that is measured rather than stylistic. A warm-up
  # forward on this model leaves the traced pass with ZERO launches while still
  # returning finite logits: the traced pass has the identical AST, hits the
  # linear cache, and a zero-launch trace reads exactly like a model that
  # computes nothing. (Realising running_mean/running_var up front poisons it the
  # same way.) The BatchNorm init fills therefore stay in the trace, which is
  # correct anyway -- they define running_var's contents, which the model reads.

  # Installed AFTER the weights are fixed and the model is warm, so the trace is
  # the model's forward pass and nothing else.
  RZ._orig_exec_kernel = RZ.exec_kernel
  RZ.exec_kernel = traced_exec_kernel

  with Context(TRAINING=0):
    logits = model(x).realize()
    oracle = bits_of(logits.uop.base.realized)

  (OUT / "oracle.json").write_text(json.dumps({
    "bs": BS, "shape": list(logits.shape), "logits_b64": oracle,
    "note": "CPython tinygrad, DEV=CPU, TRAINING=0 (py:29-30 get_test_acc path), u32 bit patterns",
  }, indent=1) + "\n")

  for r in launches:
    r.pop("_bufs", None)
  (OUT / "net.json").write_text(json.dumps({
    "entry": {"input": list(x.shape), "output": list(logits.shape)},
    "buffers": buffers, "kernels": launches,
    "note": "kernel launches captured from tinygrad/engine/realize.py:160 exec_kernel; "
            "wgsl is tinygrad/renderer/wgsl.py WGSLRenderer on the same ast",
  }) + "\n")

  print(f"launches {len(launches)}  buffers {len(buffers)}  logits {list(logits.shape)}")
  for i, r in enumerate(launches):
    print(f"  {i:2d} {str(r.get('entry')):<12} global={r['global']} local={r['local']} bufs={r['bufs']} wgsl={len(r['wgsl'] or '')}B")
  print("logits_b64", oracle[:24], "...")

if __name__ == "__main__":
  main()
