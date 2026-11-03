#!/usr/bin/env python3
"""floor.py -- the PER-REALIZE cost of the two lanes, measured by SLOPE, on a kernel too small to matter.

    .venv/bin/python .agents/slop/parity/floor.py [--rounds 15]

WHY THIS EXISTS. `gap.py` compares whole workloads and asks whether 1.0 sits inside the interquartile range.
At 16x16 the kernel is small enough that the launch path dominates, so the band is +-4% of ~30 ms and a
0.3 ms per-realize difference between the lanes is INVISIBLE to that test: it is smaller than the spread
it is being measured against. This instrument measures the small end directly.

THE MEASUREMENT IS A SLOPE, NOT A TOTAL. For each lane, time N and 4N realizations of the same trivial
program and take (t(4N) - t(N)) / (3N). The intercept -- interpreter start-up, imports, tensor allocation,
the first compile -- cancels, so what is left is the marginal cost of ONE realize: graph build, schedule
cache lookup, kernel cache lookup, launch, execute. A slope difference between the lanes is port overhead
that no whole-workload ratio at the bottom of the size range could resolve.

BOTH LANES BUILD A NEW LAZY GRAPH PER CALL, exactly as a caller does, so neither gets to skip graph
construction. tinygrad caches the compiled kernel and the schedule on the uop hash, so the amortised cost
is the honest per-call cost.

AND THE PROGRAM IS `a + b` ON 64 ELEMENTS: 1/16 of a cache line, four blocks of 16 lanes, one store per
lane. Whatever the slopes are, they are not the arithmetic.
"""
import os
import statistics
import sys
import time

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
os.environ.pop("BEND_C", None)
os.environ.pop("BEND_PORT_C", None)

import numpy as np  # noqa: E402
import ops_bend  # noqa: E402

sys.modules["tinygrad.runtime.ops_bend"] = ops_bend
from tinygrad import Context, Tensor  # noqa: E402

N_SMALL, N_BIG = 100, 400


def _program(dev: str):
  """A trivial kernel, built on `dev` and realized once so the first compile is outside the window."""
  with Context(DEV=dev):
    a = Tensor(np.arange(64, dtype=np.float32), device=dev)
    b = Tensor(np.arange(64, dtype=np.float32) + 1, device=dev)
    a.realize()
    b.realize()
    got = (a + b).realize().numpy()
  assert np.allclose(got, np.arange(64) * 2 + 1), f"{dev}: wrong answer {got[:4]}"
  return a, b


def _block(a, b, n: int) -> float:
  t0 = time.perf_counter()
  for _i in range(n):
    (a + b).realize()
  return time.perf_counter() - t0


def slope_us(dev: str) -> float:
  a, b = _program(dev)
  _block(a, b, 20)                     # warm the caches outside the window
  return (_block(a, b, N_BIG) - _block(a, b, N_SMALL)) / (N_BIG - N_SMALL) * 1e6


def main() -> int:
  ap_rounds = 15
  for i, arg in enumerate(sys.argv):
    if arg == "--rounds":
      ap_rounds = int(sys.argv[i + 1])
  print(f"# 64-element add, slope over {N_BIG - N_SMALL} calls after {N_SMALL} (microseconds per realize)")
  print(f"{'round':>5} {'BEND us':>9} {'CPU us':>9} {'BEND/CPU':>9}")
  ratios, bends, cpus = [], [], []
  for r in range(1, ap_rounds + 1):
    if r % 2:
      bm, cm = slope_us("BEND"), slope_us("CPU")
    else:
      cm, bm = slope_us("CPU"), slope_us("BEND")
    bends.append(bm)
    cpus.append(cm)
    ratios.append(bm / cm)
    print(f"{r:>5} {bm:>9.1f} {cm:>9.1f} {bm / cm:>9.4f}")
  ratios.sort()
  q1 = ratios[len(ratios) // 4]
  q3 = ratios[(3 * len(ratios)) // 4]
  above = sum(1 for x in ratios if x > 1.0)
  print(f"BEND median {statistics.median(bends):.1f} us  CPU median {statistics.median(cpus):.1f} us")
  print(f"BEND/CPU median {statistics.median(ratios):.4f}  spread {ratios[0]:.4f}-{ratios[-1]:.4f}")
  print(f"rounds where BEND is SLOWER than CPU: {above} of {len(ratios)}")
  print(f"ratio quartiles Q1 {q1:.4f}  Q3 {q3:.4f}")
  inside = q1 <= 1.0 <= q3
  print(f"1.0 INSIDE the interquartile range: {inside}"
        + ("" if inside else "  -> the gap is outside the spread"))
  return 0


if __name__ == "__main__":
  sys.exit(main())
