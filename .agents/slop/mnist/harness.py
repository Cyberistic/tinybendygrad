#!/usr/bin/env python3
"""harness.py -- the shared instrument for the MNIST end-to-end run.

    .venv/bin/python .agents/slop/mnist/harness.py bench

WHAT IT IS. One module that:
  1. registers the PORT's BEND device with tinygrad's device registry
     (`sys.modules['tinygrad.runtime.ops_bend'] = OB` -- the same line
     `.agents/slop/convfix/probe.py:41` uses, and the reason `DEV='BEND'`
     resolves at all),
  2. reads the `.npy` files the host-side preparation produced,
  3. builds a model, and
  4. runs it on a named device, timing every kernel launch.

THE DEVICE READ IS NOT A NEW SUBSYSTEM. `ops_bend.py`'s `BendProgram.__call__`
reads `PACKET.out` back and copies the STORE-reachable buffers into the host
views, so a tensor realised on the BEND device reads its own values back. That
is the whole of the "device read" seam: it is the executor's output coming
back, and the CPython side already does exactly that.

THE TIMING IS PER LAUNCH, NOT PER MODEL. Every `BendProgram.__call__` is timed
and the per-launch numbers are kept, because "one MNIST forward pass" is a sum
of launches and the sum is only meaningful if the parts are named.
"""
import pathlib
import sys
import time

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

HERE = pathlib.Path(__file__).resolve().parent
DATA = HERE / "data"

from tinygrad import Tensor, Context  # noqa: E402

import ops_bend as OB  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

# every BEND launch, in order: (packet bytes, buffers, grid, seconds)
LAUNCHES = []
_ENABLE_HOOK = True


def _install_hook():
    _call = OB.BendProgram.__call__

    def call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), vals=(), wait=False, **kw):
        t0 = time.perf_counter()
        r = _call(self, *bufs, global_size=global_size, local_size=local_size, vals=vals, wait=wait, **kw)
        if _ENABLE_HOOK:
            LAUNCHES.append({
                "nuops": len(self.uops),
                "nbufs": self.nbufs,
                "gsize": tuple(global_size),
                "secs": time.perf_counter() - t0,
                "ops": _ops(self.src),
                "bufs": _bufs(self.src),
            })
        return r

    OB.BendProgram.__call__ = call


def _ops(packet: str) -> str:
    """the packet's op NAMES, in order, deduplicated into a run-length spelling.

    The packet is the WIRE, not the uops: `N: OP dtype arg srcs` per line, and
    the op name is the second field. The run-length spelling is what makes a
    kernel identifiable -- a conv is a long run of ALU ops inside four RANGEs,
    and a relu is one op repeated."""
    names = []
    for line in packet.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1].isalpha():
            names.append(parts[1])
    out = []
    for n in names:
        if out and out[-1][0] == n:
            out[-1][1] += 1
        else:
            out.append([n, 1])
    return ",".join(f"{n}x{c}" if c > 1 else n for n, c in out)


def _bufs(packet: str) -> str:
    """the packet's buffer sizes, in order -- the PARAM lines' byte counts. A
    kernel's OUTPUT size identifies it: a conv1 output is 4*28*28*4 bytes and a
    relu's is the same, and a pool's is a quarter of it."""
    out = []
    for line in packet.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 4 and parts[1] == "PARAM" and parts[3].startswith("k:param:"):
            out.append(parts[3].split(":")[2])
    return ",".join(out)


_install_hook()


# ---------------------------------------------------------------- data

def load_npy(name: str) -> np.ndarray:
    """the `.npy` files, read by numpy. The PORT reads them too -- see
    `tinybendygrad/nn/datasets.bend`'s `.npy` path -- but the port's own
    `ops_npy.bend` is a TRACE port (it records the mmap/mview/write calls and
    refuses the two upstream refusals), so the BYTES are read here and the
    port's path owns the SHAPE ARITHMETIC."""
    return np.load(DATA / name, allow_pickle=False)


def mnist_npy(split: str = "test", n: int | None = None):
    """(images, labels) as numpy, in upstream's own order and shape:
    images (N,1,28,28) uint8, labels (N,) uint8."""
    X = load_npy(f"mnist_{split}_images.npy")
    y = load_npy(f"mnist_{split}_labels.npy")
    if n is not None:
        X, y = X[:n], y[:n]
    return X, y


def to_device_tensor(arr: np.ndarray, device: str) -> Tensor:
    """numpy -> a Tensor ON THE DEVICE, as float32 normalised to [0,1].

    The cast to float32 and the /255 are the STANDARD MNIST normalisation and
    they happen ONCE, on the host, so the device sees the same numbers on both
    lanes. They are NOT the port's arithmetic -- they are the DATA.
    """
    t = Tensor(arr.astype(np.float32) / 255.0)
    return t.to(device).realize() if device != "PYTHON" else t.realize()


# ---------------------------------------------------------------- timing

def timed(device: str, fn):
    LAUNCHES.clear()
    t0 = time.perf_counter()
    out = fn()
    wall = time.perf_counter() - t0
    return out, wall, list(LAUNCHES)
