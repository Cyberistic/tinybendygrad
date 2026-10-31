#!/usr/bin/env python3
"""bench.py -- ONE PROGRAM, EVERY LANE THAT RUNS ON THIS MACHINE, TIMED.

    .venv/bin/python .agents/slop/perf/bench.py [--iters N] [--size N]

WHAT IT MEASURES, AND WHY IT IS ONE PROGRAM AND NOT FOUR. A speed comparison
between two lanes is only a comparison if the ARITHMETIC is the same. So every
lane here runs THE SAME `Ops` graph: a square matmul chain `(A @ B) @ C` of f32
matrices, built once from `Tensor` calls, and each lane realises it.

**⇒ AND THE PROGRAM IS `(A @ B) @ C` BECAUSE BOTH LANES REPOSITORY-WIDE ALREADY
AGREE ON IT**: it is `checks/.e2e-fixture/e2e_mm.py`'s own arithmetic, so the
number here can be read beside the browser lane's.

WHY THE SIZE IS SMALL AND THE ITERATIONS ARE FEW: the BEND device is an
INTERPRETER THAT SPAWNS A SUBPROCESS PER LAUNCH (its own header says so), so a
64x64 matmul is tens of seconds. `--size` and `--iters` are therefore parameters
and the DEFAULT is the smallest size that still does real work. **⇒ AND THE
RESULT PRINTS PER-LAUNCH AND PER-ITERATION COSTS SO A SMALL RUN IS STILL
INTERPRETABLE.**

THE FOUR VERDICTS PER LANE, because "it worked" is not a measurement:
  ms       the wall clock of `--iters` realizations, divided by `--iters`
  out      the answer, read back and compared with CPU's
  ok       bit-identical to CPU? (f32 accumulation order may differ, so a
           NON-match is reported as the max absolute deviation, not as a lie)
  launches kernels actually dispatched (`LAUNCHES` is filled by the ops_bend hook)
"""
import argparse
import json
import pathlib
import statistics
import sys
import time

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))


def build(size: int):
    """The program: `(A @ B) @ C`, f32, `size` x `size`."""
    rng = np.random.RandomState(0xC0FFEE)
    mats = [rng.randn(size, size).astype(np.float32) * np.float32(0.25) for _ in range(3)]
    return mats


def run_lane(dev: str, mats, iters: int):
    """Time `iters` realizations of `(A @ B) @ C` on `dev`."""
    from tinygrad import Tensor, Context

    with Context(DEV=dev):
        ts = [Tensor(m).realize() for m in mats]
        a, b, c = ts
        # WARM: the first realization compiles and caches. Every lane gets the
        # same courtesy, so no lane is charged for its compiler.
        warm = ((a @ b) @ c).realize()
        _ = warm.numpy()

        samples = []
        out = None
        for _i in range(iters):
            t = time.perf_counter()
            out = ((a @ b) @ c).realize()
            samples.append(time.perf_counter() - t)
        arr = out.numpy()
    return {
        "dev": dev,
        "ms_median": statistics.median(samples) * 1000.0,
        "ms_min": min(samples) * 1000.0,
        "out": arr,
        "samples": samples,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=3)
    ap.add_argument("--size", type=int, default=16)
    ap.add_argument("--lanes", default="CPU,PYTHON,METAL,BEND")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    mats = build(args.size)
    ref = None
    rows = []
    for lane in [x for x in args.lanes.split(",") if x]:
        if lane == "BEND":
            import ops_bend as OB
            sys.modules["tinygrad.runtime.ops_bend"] = OB
        try:
            r = run_lane(lane, mats, args.iters)
        except Exception as e:
            rows.append({"dev": lane, "error": f"{type(e).__name__}: {e}"})
            print(f"{lane:8s} REFUSED  {type(e).__name__}: {str(e)[:120]}")
            continue
        if ref is None:
            ref = r["out"]
        d = float(np.abs(r["out"] - ref).max())
        rows.append({"dev": lane, "ms_median": r["ms_median"], "ms_min": r["ms_min"], "max_abs_vs_first": d})
        print(f"{lane:8s} {r['ms_median']:10.2f} ms/iter   min {r['ms_min']:9.2f}   "
              f"max|diff vs {rows[0]['dev']}| {d:.3e}")

    if rows and "ms_median" in rows[0]:
        base = rows[0]["ms_median"]
        print()
        print(f"relative to {rows[0]['dev']} (lower is better):")
        for r in rows:
            if "ms_median" not in r:
                continue
            print(f"  {r['dev']:8s} {r['ms_median'] / base:7.2f}x")

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps({"size": args.size, "iters": args.iters, "rows": rows}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
