#!/usr/bin/env python3
"""cpu_metal.py -- CPython's OWN CPU and METAL devices, on the SAME model and the SAME weights.

    .venv/bin/python .agents/slop/seams/cpu_metal.py CPU 1
    .venv/bin/python .agents/slop/seams/cpu_metal.py METAL 1

ONE DEVICE AT A TIME. The device is a command-line argument, so the two lanes never
run in the same process and never contend.

WHAT IT MEASURES. The per-image forward-pass wall clock and the logits, so the
port's lane can be compared against CPython's on the SAME input and the SAME weights.
The ORACLE IS CPython's OWN DEVICE: upstream tinygrad's `ClangRenderer` -> `cc` ->
mmap for CPU, and `MetalRenderer` -> Metal -> the GPU for METAL.
"""
import pathlib
import sys
import time

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
MNIST = HERE.parent / "mnist"
sys.path.insert(0, str(MNIST))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.nn.state import load_state_dict, get_state_dict  # noqa: E402

from model import Model, load_weights  # noqa: E402

WEIGHTS = MNIST / "weights.npz"


def data(n: int):
    X = np.load(MNIST / "data" / "mnist_test_images.npy", allow_pickle=False)[:n]
    y = np.load(MNIST / "data" / "mnist_test_labels.npy", allow_pickle=False)[:n]
    return X, y


def main() -> int:
    device = sys.argv[1] if len(sys.argv) > 1 else "CPU"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    X, y = data(n)

    with Context(DEV=device):
        m = Model()
    load_weights(m, WEIGHTS)

    rows = []
    for i in range(X.shape[0]):
        with Context(DEV=device):
            x = Tensor(X[i:i + 1].astype(np.float32) / 255.0).realize()
            t0 = time.perf_counter()
            logits = m(x)
            am = int(logits.argmax(axis=1).item())
            lg = [float(v) for v in logits.flatten().tolist()]
            dt = time.perf_counter() - t0
        rows.append((i, am, int(y[i]), dt, lg))
        print(f"  img {i:4d} pred={am} label={int(y[i])} {dt:8.4f}s", flush=True)

    print(f"# device={device} n={X.shape[0]}")
    for i, am, lab, dt, lg in rows:
        print(f"# row i={i} pred={am} label={lab} secs={dt:.6f} "
              f"logits={','.join(repr(v) for v in lg)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
