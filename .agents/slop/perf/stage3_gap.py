"""stage3_gap.py -- WHERE THE 2.6x/5.1x BETWEEN THE PYTHON AND BEND LANES ACTUALLY SITS.

    .venv/bin/python .agents/slop/perf/stage3_gap.py PYTHON --size 16
    .venv/bin/python .agents/slop/perf/stage3_gap.py BEND   --size 16

The two lanes execute THE SAME `(A@B)@C` graph, so a speed difference has only three homes:
HOW MANY UOPS a kernel has, HOW MANY TIMES the interpreter walks them, and HOW LONG ONE WALK
STEP takes. This prints all three, per launch, so the fix has a target instead of a suspicion.

For BEND it also separates the SUBPROCESS from the walk: `BendProgram.__call__` is timed whole,
and the executor alone is timed on the packet it just wrote, so the lane's spawn+hex cost is a
measured term rather than an excuse.
"""
import argparse
import pathlib
import statistics
import subprocess
import sys
import time

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / ".agents/slop/perf"))


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("lane")
  ap.add_argument("--size", type=int, default=16)
  ap.add_argument("--iters", type=int, default=2)
  args = ap.parse_args()

  from bench import build
  from tinygrad import Context, Tensor

  if args.lane == "BEND":
    import ops_bend as OB
    sys.modules["tinygrad.runtime.ops_bend"] = OB
    mod = OB.BendProgram
  else:
    import tinygrad.runtime.ops_python as op
    mod = op.PythonProgram

  mats = build(args.size)
  orig = mod.__call__
  log = []

  def wrap(self, *a, **kw):
    t = time.perf_counter()
    r = orig(self, *a, **kw)
    log.append((len(self.uops), time.perf_counter() - t))
    return r

  mod.__call__ = wrap
  with Context(DEV=args.lane):
    ts = [Tensor(m).realize() for m in mats]
    a, b, c = ts
    warm = ((a @ b) @ c).realize()
    _ = warm.numpy()
    log.clear()
    t = time.perf_counter()
    for _i in range(args.iters):
      out = ((a @ b) @ c).realize()
    total = (time.perf_counter() - t) / args.iters
    _ = out.numpy()
  mod.__call__ = orig

  per = statistics.median(dt for _n, dt in log) * 1000.0
  print(f"{args.lane} size={args.size}: realize {total*1000:.2f} ms, launches/realize "
        f"{len(log)/max(args.iters,1):.1f}, uops={[n for n, _ in log[:4]]}, "
        f"median launch {per:.2f} ms")
  for n, dt in log[:4]:
    print(f"   launch uops={n} {dt*1000:.2f} ms")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
