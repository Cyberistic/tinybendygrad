#!/usr/bin/env python3
"""e2ecold.py -- THE COLD PATH OF A REAL PROGRAM, in both lanes.

    .venv/bin/python .agents/slop/parity/e2ecold.py --lane BEND --seed 0
    .venv/bin/python .agents/slop/parity/e2ecold.py --lane CPU  --seed 0

WHY THIS EXISTS. `gap.py` and `floor.py` measure a WARM lane. `compile.py` measures the RENDER in isolation.
Neither answers the question a person actually asks: when I run a program for the first time on this machine,
how long does it take before the answer comes out?

So this runs ONE program with several distinct kernels -- a matmul, a conv, a softmax, a reduce and an
elementwise chain -- in a FRESH PROCESS, with a `--seed` that shifts every shape so that no content cache
(portc's or tinygrad's) can answer: each kernel here is a FIRST cost. It prints the wall time and the number
of kernels that ran.

MEASURED LIMITATION, STATED: the portc JS artifact itself (`live.bend` built once) is kept across runs in
`out/`, exactly as a user's machine would keep it, so the one-time build is NOT in these numbers. The
`--cold-build` flag deletes it first for a true first-ever run.
"""
import os
import sys
import time


def main() -> int:
  lane, seed, cold_build = "BEND", 0, False
  for i, arg in enumerate(sys.argv):
    if arg == "--lane":
      lane = sys.argv[i + 1]
    if arg == "--seed":
      seed = int(sys.argv[i + 1])
    if arg == "--cold-build":
      cold_build = True

  ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
  sys.path.insert(0, ROOT)
  sys.path.insert(0, ROOT + "/.agents/slop/cpuseam")
  os.environ.pop("BEND_C", None)
  os.environ.pop("BEND_PORT_C", None)
  os.environ.setdefault("PARALLEL", "0")

  import numpy as np
  import ops_bend
  sys.modules["tinygrad.runtime.ops_bend"] = ops_bend
  from tinygrad import Context, Tensor
  from tinygrad.dtype import dtypes

  if cold_build and lane == "BEND":
    import portc
    for f in (portc.OUT).glob("live-*.js"):
      f.unlink()

  n = 40 + seed
  rng = np.random.default_rng(seed)
  kernels = {"n": 0}
  import tinygrad.engine.realize as _RZ
  _orig = _RZ.exec_kernel

  def _count(device, ast, *a, **k):
    kernels["n"] += 1
    return _orig(device, ast, *a, **k)

  _RZ.exec_kernel = _count
  t0 = time.perf_counter()
  with Context(DEV=lane):
    a = Tensor(rng.random((n, n), dtype=np.float32), device=lane)
    b = Tensor(rng.random((n, n), dtype=np.float32), device=lane)
    img = Tensor(rng.random((1, 3, n, n), dtype=np.float32), device=lane)
    w = Tensor(rng.random((4, 3, 3, 3), dtype=np.float32), device=lane)
    x = (a @ b).relu()
    y = img.conv2d(w, padding=1).max(axis=(2, 3))
    z = x.softmax(axis=1).cast(dtypes.half).cast(dtypes.float32)
    out = (z.sum(axis=0) + y.mean().expand(n, n)).realize().numpy()
  dt = (time.perf_counter() - t0) * 1e3
  _RZ.exec_kernel = _orig
  print(f"{lane:<5s} seed={seed:<3d} n={n:<3d} kernels={kernels['n']:<2d} "
        f"cold wall={dt:8.1f} ms  checksum={float(np.sum(out)):.4f}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
