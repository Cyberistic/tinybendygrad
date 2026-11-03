#!/usr/bin/env python3
"""compile.py -- the COLD cost of a kernel: uop list -> C, then C -> a running binary.

    .venv/bin/python .agents/slop/parity/compile.py [--n 6] [--base 4001]

WHY THIS EXISTS. `gap.py` and `floor.py` both measure a WARM lane: tinygrad caches the compiled kernel on
the uop hash, so after the first realize the render and the compile are gone from the timing. That is the
right thing for a steady-state ratio and the WRONG thing for a model with K distinct kernels, which pays
the first cost K times and which neither instrument can see.

THE TWO LANES PAY DIFFERENT RENDERS. tinygrad's `ClangRenderer.render` is a Python function over the uop
list (sub-millisecond). The port's `portc.render` is a BEND BUILD of `cstyle.bend` per unique kernel, so
the render is ONE `bin/bend` invocation -- and that build's cost is the TYPECHECK OF THE CLOSURE, i.e. it
does not grow with the kernel. This measures both halves of the cold path on the same uop lists:

  CPU lane    first realize            (upstream render + clang + load)
  BEND single one kernel per build     (`portc.render`, the path the device uses)
  BEND batch  all kernels, one build   (`portc.render_many`)

Every port render is compared BYTE FOR BYTE against `ClangRenderer`'s C for the same uop list, so a fast
batch that emitted different C would be a failure here rather than a speed-up.
"""
import os
import sys
import time

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
sys.path.insert(0, ROOT + "/.agents/slop/cpuseam")
os.environ.pop("BEND_C", None)
os.environ.pop("BEND_PORT_C", None)
os.environ.setdefault("PARALLEL", "0")

import numpy as np  # noqa: E402
import ops_bend  # noqa: E402

sys.modules["tinygrad.runtime.ops_bend"] = ops_bend
from tinygrad import Context, Tensor  # noqa: E402
from tinygrad.renderer.cstyle import ClangRenderer  # noqa: E402

cap = []
_orig = ClangRenderer.render


def _grab(self, uops):
  """TIME the upstream render at its own call site, and keep its C as the oracle."""
  t0 = time.perf_counter()
  src = _orig(self, uops)
  cap.append((list(uops), src, (time.perf_counter() - t0) * 1e3))
  return src


def cold_kernels(base: int, n: int):
  """n DISTINCT sizes, so neither lane's content cache can answer: every kernel is a FIRST cost."""
  out = []
  with Context(DEV="CPU"):
    for i in range(n):
      size = base + i
      a = Tensor(np.arange(size, dtype=np.float32), device="CPU")
      b = Tensor(np.arange(size, dtype=np.float32) + 1, device="CPU")
      a.realize()
      b.realize()
      start = len(cap)
      t0 = time.perf_counter()
      got = (a + b).realize().numpy()
      dt = time.perf_counter() - t0
      assert np.allclose(got, np.arange(size) * 2 + 1), f"size {size}: wrong answer"
      out.append((size, dt, cap[start] if len(cap) > start else None))
  return out


def main() -> int:
  n, base = 6, 4001
  for i, arg in enumerate(sys.argv):
    if arg == "--n":
      n = int(sys.argv[i + 1])
    if arg == "--base":
      base = int(sys.argv[i + 1])
  ClangRenderer.render = _grab
  try:
    single = cold_kernels(base, n)
    batch = cold_kernels(base + 100, n)
  finally:
    ClangRenderer.render = _orig
  print(f"# {n} distinct kernels per lane: single at {base}.., batch at {base + 100}..")
  print(f"{'size':>6} {'CPU first realize ms':>21} {'upstream render ms':>19}")
  for size, dt, got in single:
    print(f"{size:>6} {dt * 1e3:>21.1f} {got[2] if got else float('nan'):>19.2f}")

  import portc
  print(f"\n{'size':>6} {'port SINGLE ms':>15} {'C identical':>12}")
  one_ms, ok = [], 0
  for size, _dt, got in single:
    uops, theirs, _ms = got
    t0 = time.perf_counter()
    ours = portc.render(uops)
    one_ms.append((time.perf_counter() - t0) * 1e3)
    ok += ours == theirs
    print(f"{size:>6} {one_ms[-1]:>15.1f} {str(ours == theirs):>12}")
  total_one = sum(one_ms)

  # THE LIVE PATH: the renderer is an artifact and each kernel is a `bun` run. This is the path the device
  # uses, and it is the only one a STREAMING caller (a real program) can use, because it never needs to know
  # the kernel after this one.
  print(f"\n{'size':>6} {'port LIVE ms':>13} {'C identical':>12}   (renderer prebuilt, one run each)")
  live_ms, live_ok = [], 0
  t0 = time.perf_counter()
  js = portc._live_js()
  boot = (time.perf_counter() - t0) * 1e3
  for size, _dt, got in batch:
    uops, theirs, _ms = got
    t0 = time.perf_counter()
    ours = portc.render_live(uops)
    live_ms.append((time.perf_counter() - t0) * 1e3)
    live_ok += ours == theirs
  total_live = sum(live_ms)
  print(f"{'-':>6} {total_live:>13.1f} {f'{live_ok}/{n}':>12}   (renderer artifact: {boot:.0f} ms if rebuilt)")
  print(f"# live:   {total_live:8.1f} ms for {n} kernels  ({total_live / n:6.1f} ms each)")

  t0 = time.perf_counter()
  cs = portc.render_many([got[0] for _s, _d, got in batch])
  total_batch = (time.perf_counter() - t0) * 1e3
  same = sum(1 for (_s, _d, got), ours in zip(batch, cs) if ours == got[1])
  print(f"\n{'size':>6} {'port BATCH ms':>13} {'C identical':>12}   (one build for all {n})")
  print(f"{'-':>6} {total_batch:>13.1f} {f'{same}/{n}':>12}")
  print(f"\n# single: {total_one:8.1f} ms for {n} kernels  ({total_one / n:6.1f} ms each)")
  print(f"# batch:  {total_batch:8.1f} ms for {n} kernels  ({total_batch / n:6.1f} ms each)"
        f"  -> {total_one / total_batch:.2f}x faster cold")
  print(f"# byte-identical to ClangRenderer: single {ok}/{n}, batch {same}/{n}, live {live_ok}/{n}")
  return 0 if ok == n and same == n and live_ok == n else 1


if __name__ == "__main__":
  sys.exit(main())
