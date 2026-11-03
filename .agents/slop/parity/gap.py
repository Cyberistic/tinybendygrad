#!/usr/bin/env python3
"""gap.py -- BEND (compiled, our renderer) against tinygrad's OWN CPU device, interleaved.

    .venv/bin/python .agents/slop/parity/gap.py [--size 32] [--iters 8] [--rounds 5]

WHY INTERLEAVED, AND WHY PER-ROUND RATIOS: this machine's load moves by tens of percent between
minutes, so a BEND block timed now and a CPU block timed a minute later measures the load, not the
lanes. Each ROUND times both lanes back to back and records a ratio; the spread of those ratios is the
thing that decides whether a gap is real.

WHAT IS EXCLUDED, ON PURPOSE: `portc`'s render build is a ONE-TIME ~1.2 s `bend -o <js>` per unique
kernel, cached by content. Every lane is warmed before timing, so that build is out of the window --
what remains is Program creation, kernel launch and the work itself.

THE WORKLOAD IS THE SAME PROGRAM IN BOTH LANES: `(a@b)@c` at `--size`, two launches per realize, built
from REALIZED buffers so tinygrad cannot constant-fold it away.
"""
import argparse
import statistics
import sys
import time

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
import numpy as np  # noqa: E402
import ops_bend  # noqa: E402

sys.modules["tinygrad.runtime.ops_bend"] = ops_bend
from tinygrad import Context, Tensor  # noqa: E402


def mats(size: int):
  # np arrays, not `.tolist()`: at 512 a list round-trip dominates the setup and is not part of anything
  # being measured.
  rng = np.random.default_rng(7)
  return [rng.random((size, size), dtype=np.float32) for _ in range(3)]


def conv_inputs(size: int):
  rng = np.random.default_rng(7)
  # 3 in-channels and 8 filters, so a conv at a given `size` does an order of magnitude more work than
  # the 1x4 version this started with -- the point of the larger sizes is to leave the launch floor.
  return (rng.random((1, 3, size, size), dtype=np.float32),
          rng.random((8, 3, 3, 3), dtype=np.float32))


def one(dev: str, iters: int) -> float:
  """median ms per realize, on `dev`, with the kernel already warm (render + compile done)."""
  with Context(DEV=dev):
    if dev_prog == "conv":
      x, w = (Tensor(v).realize() for v in conv_inputs(int(dev_size)))
      run = lambda: x.conv2d(w, padding=1).realize()   # noqa: E731
    else:
      ts = [Tensor(m).realize() for m in mats(int(dev_size))]
      a, b, c = ts
      run = lambda: ((a @ b) @ c).realize()            # noqa: E731
    _ = run().numpy()
    xs = []
    for _i in range(iters):
      t = time.perf_counter()
      out = run()
      xs.append((time.perf_counter() - t) * 1000.0)
    _ = out.numpy()
  return statistics.median(xs)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--size", type=int, default=32)
  ap.add_argument("--iters", type=int, default=8)
  ap.add_argument("--rounds", type=int, default=5)
  # ADDS A PROGRAM WHERE COMPUTE, NOT LAUNCH OVERHEAD, IS THE COST: at 16 and 32 both lanes read ~1.24 ms,
  # which is the signature of a fixed realize/launch floor rather than the lane's work.
  ap.add_argument("--prog", choices=("matmul", "conv"), default="matmul")
  args = ap.parse_args()
  global dev_size, dev_prog
  dev_size, dev_prog = args.size, args.prog

  # WARM BOTH LANES FIRST: the port's renderer build is one-time and must not land in a timed window.
  one("BEND", 2), one("CPU", 2)

  print(f"# prog {args.prog}  size {args.size}  iters {args.iters}  rounds {args.rounds}  (median ms per realize)")
  print(f"{'round':>5} {'BEND':>9} {'CPU':>9} {'BEND/CPU':>9}")
  ratios, bends, cpus = [], [], []
  for r in range(1, args.rounds + 1):
    # alternate the order so a drift in load cannot favour one lane
    if r % 2:
      bm, cm = one("BEND", args.iters), one("CPU", args.iters)
    else:
      cm, bm = one("CPU", args.iters), one("BEND", args.iters)
    ratios.append(bm / cm)
    bends.append(bm)
    cpus.append(cm)
    print(f"{r:5d} {bm:9.3f} {cm:9.3f} {bm/cm:9.4f}")
  print(f"\nBEND median {statistics.median(bends):.3f} ms  spread {min(bends):.3f}-{max(bends):.3f}")
  print(f"CPU  median {statistics.median(cpus):.3f} ms  spread {min(cpus):.3f}-{max(cpus):.3f}")
  print(f"BEND/CPU median {statistics.median(ratios):.4f}  spread {min(ratios):.4f}-{max(ratios):.4f}")
  above = sum(1 for x in ratios if x > 1.0)
  print(f"rounds where BEND is SLOWER than CPU: {above} of {len(ratios)}")
  # **THE DECISION RULE.** A gap is only evidence if it is OUTSIDE the run-to-run spread; otherwise the
  # two lanes are indistinguishable at this resolution and the honest reading is "no measurable headroom".
  q = sorted(ratios)
  q1, q3 = q[len(q) // 4], q[(3 * len(q)) // 4]
  lo_med, hi_med = min(q), max(q)
  print(f"ratio quartiles Q1 {q1:.4f}  Q3 {q3:.4f}")
  inside = q1 <= 1.0 <= q3
  print(f"1.0 INSIDE the interquartile range: {inside}"
        + ("  -> the gap does NOT exceed the spread" if inside else "  -> the gap is outside the spread"))
  return 0


dev_size, dev_prog = 32, "matmul"
if __name__ == "__main__":
  sys.exit(main())
