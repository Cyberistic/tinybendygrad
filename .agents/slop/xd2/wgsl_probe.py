# .agents/slop/xd2/wgsl_probe.py -- can tinygrad emit REAL WGSL with no adapter?
#
# The browser lane's kernels should be tinygrad's own, not hand-written, or the
# gate against DEV=CPU proves nothing about tinygrad. `WebGpuDevice.__init__`
# needs the native Dawn binding, so the device is unreachable from CPython; but
# the RENDERER is not. `Compiled.renderer` picks from `Compiled.renderers`, and
# codegen's `pm_to_program` has a `do_render` arm that writes an Ops.SOURCE uop
# before anything is compiled. So: point the CPU device's renderer at WGSL and
# intercept Ops.SOURCE.
#
# Prints one WGSL kernel per line-ish block so the question is answered by output.

import os
os.environ.setdefault("DEV", "CPU")

import tinygrad.codegen as CG
from tinygrad import Device, Tensor
from tinygrad.renderer.wgsl import WGSLRenderer
from tinygrad.uop.ops import Ops

captured = []

class Stop(Exception): pass

def capture_compile(ctx, prg, source):
  # Ops.SOURCE's arg from do_render is the SOURCE STRING itself (do_assemble uses
  # a (name, code) tuple), so take the arg whole rather than arg[0].
  captured.append(str(source.arg))
  return None  # abort this step: the device then has no binary, which is fine, we already have the code

CG.pm_to_program = CG.PatternMatcher([
  (CG.UPat(Ops.PROGRAM, src=(CG.UPat(Ops.SINK, name="sink"),), name="prg"), CG.do_linearize),
  (CG.UPat(Ops.PROGRAM, src=(CG.UPat(Ops.SINK, name="sink"), CG.UPat(Ops.LINEAR, name="lin")), name="prg"), CG.do_estimates),
  (CG.UPat(Ops.PROGRAM, src=(CG.UPat(), CG.UPat(Ops.LINEAR, src=CG.UPat(Ops.INS), name="lin")), name="prg"), CG.do_assemble),
  (CG.UPat(Ops.PROGRAM, src=(CG.UPat(), CG.UPat(Ops.LINEAR, name="lin")), name="prg"), CG.do_render),
  (CG.UPat(Ops.PROGRAM, src=(CG.UPat(), CG.UPat(Ops.LINEAR), CG.UPat(Ops.SOURCE, name="source")), name="prg"), capture_compile),
])

dev = Device["CPU"]
dev.renderers = [WGSLRenderer]
dev.cached_renderer.clear()
print("renderer is now", type(dev.renderer).__name__)


def run(label, fn):
  del captured[:]
  try:
    fn()
  except Exception as e:
    print(f"[{label}] stopped after capture: {type(e).__name__} {e}")
  print(f"\n===== {label}: {len(captured)} kernel(s)")
  for src in captured:
    print("-" * 60)
    print(src)

from tinygrad import nn
run("add", lambda: (Tensor([1.0, 2.0, 3.0, 4.0]).realize() + 1.0).tolist())
run("matmul", lambda: (Tensor.ones(8, 8) @ Tensor.ones(8, 8)).tolist())
run("conv2d", lambda: nn.Conv2d(1, 4, 3)(Tensor.ones(1, 1, 8, 8)).tolist())
run("maxpool", lambda: Tensor.ones(1, 1, 8, 8).max_pool2d(2, 2).tolist())
run("relu", lambda: Tensor.ones(4, 4).relu().tolist())
