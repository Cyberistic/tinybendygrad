#!/usr/bin/env python3
"""bench.py -- CALIBRATION. How long does a Bend launch take, per shape?

    .venv/bin/python .agents/slop/mnist/bench.py

THE POINT. The brief's one gating measurement is "how long does one 28x28
MNIST forward pass take?". That number is a SUM OF LAUNCHES, and a launch's cost
depends on the kernel's shape, so the sum cannot be guessed -- it has to be
measured from the parts up. This measures:

  fixed     -- a 1-element add: the per-launch overhead (subprocess + hex
               round trip + interpreter start).
  dot784    -- (1,784) @ (784,10): 7840 MACs, ONE launch.
  conv28    -- (1,1,28,28) conv2d (1,1,3,3) p0: 676 output positions, 9 MACs
               each.
  conv28x4  -- (1,1,28,28) conv2d (4,1,3,3) p0: 2704 output positions, 9
               MACs each. The ONLY difference from conv28 is the channel count,
               so the pair separates "cost per output position" from "cost per
               MAC".

Everything runs on the PORT's BEND device, one at a time, never in the
background.
"""
import sys
import time

import numpy as np

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from harness import LAUNCHES, to_device_tensor, timed  # noqa: E402

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402


def run(name, build, device="BEND"):
    try:
        with Context(DEV=device):
            out, wall, launches = timed(device, build)
        ls = ", ".join(f"{l['secs']:.2f}s(nuops={l['nuops']},nbuf={l['nbufs']},g={l['gsize']})" for l in launches)
        print(f"{name:10s} wall={wall:8.3f}s launches={len(launches)} [{ls}]")
        return wall, launches
    except Exception as e:  # noqa: BLE001
        print(f"{name:10s} REFUSED {type(e).__name__}: {str(e)[:300]}")
        return None, []


def main():
    print("# calibration on the PORT's BEND device (ops_bend.py's BendDevice)")

    # a one-element add: the fixed per-launch cost.
    def fixed():
        a = Tensor([1.0], dtype=dtypes.float32).to("BEND").realize()
        b = Tensor([2.0], dtype=dtypes.float32).to("BEND").realize()
        return (a + b).tolist()

    run("fixed", fixed)

    # the dot: 7840 MACs in one launch.
    rng = np.random.default_rng(0)
    W = (rng.standard_normal((784, 10)) * 0.01).astype(np.float32)
    x = (rng.standard_normal((1, 784)) * 0.1).astype(np.float32)

    def dot784():
        Wt = Tensor(W).to("BEND").realize()
        xt = Tensor(x).to("BEND").realize()
        return (xt @ Wt).tolist()

    run("dot784", dot784)

    # the convs.
    for cout, nm in ((1, "conv28"), (4, "conv28x4")):
        w = (rng.standard_normal((cout, 1, 3, 3)) * 0.1).astype(np.float32)
        im = rng.random((1, 1, 28, 28)).astype(np.float32)

        def conv(w=w, im=im):
            Wt = Tensor(w).to("BEND").realize()
            it = Tensor(im).to("BEND").realize()
            return it.conv2d(Wt).tolist()

        run(nm, conv)

    return 0


if __name__ == "__main__":
    sys.exit(main())
