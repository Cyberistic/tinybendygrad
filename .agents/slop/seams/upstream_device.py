#!/usr/bin/env python3
"""upstream_device.py -- UPSTREAM's DEVICE behaviour, MEASURED.

    .venv/bin/python .agents/slop/seams/upstream_device.py CPU 2
    .venv/bin/python .agents/slop/seams/upstream_device.py METAL 2

WHAT IT MEASURES.  The same MNIST forward pass that `cpu_metal.py` runs, on
CPython's OWN device -- `CPU` or `METAL` -- with upstream's own renderer, and
it answers three questions the port's audit needs answered by a number rather
than by a paragraph:

  1. HOW MANY METAL KERNELS UPSTREAM COMPILES for one image, how many are
     DISTINCT, and how big is the MSL it generates.  `DEBUG=4` prints the MSL;
     this counts the programs and the bytes.
  2. HOW MANY KERNELS ARE SCHEDULED per realize, and whether the second image
     hits the schedule cache.
  3. WHAT EACH KERNEL COSTS -- `DEBUG=2`'s `*** METAL <n> <name> ... tm <t>` rows.

ONE DEVICE AT A TIME: the device is an argument, so the two lanes never run in
the same process and never contend.

WHY THE MODEL RUNS IN A CHILD PROCESS.  tinygrad's DEBUG printer writes
through Python's `print`, but the pipeline's own progress lines are written by
other machinery, and `contextlib.redirect_stdout` catches only the former.
A CHILD PROCESS with its two streams pointed at a FILE catches both, and the
file is what the parent then counts -- so the counts are made on the bytes the
run actually wrote, not on an interception that might have missed some.

THE CHILD IS THIS SAME FILE, with `--child`.  It prints the logits; the parent
counts the kernels and prints the summary.
"""
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
MNIST = HERE.parent / "mnist"
DUMP = HERE / "device_dump.out"

KERNEL_RE = re.compile(r"kernel void (\w+)")
C_RE = re.compile(r"^void (r_\w+)\(", re.M)
ROW_RE = re.compile(r"\*\*\* METAL\s+(\d+)\s+(\S+)\s+arg\s+(\d+).*?tm\s+([\d.]+)us/\s*([\d.]+)ms")
SCHED_RE = re.compile(r"scheduled\s+(\d+) kernels in\s+([\d.]+) ms \|\s*(CACHE MISS|cache hit)")
LOGIT_RE = re.compile(r"^# img (\d+) pred=(\d+) secs=([\d.]+) logits=(.*)$", re.M)


def child(device: str, n: int) -> int:
    sys.path.insert(0, str(MNIST))
    os.environ["DEV"] = device
    os.environ["DEBUG"] = "4"          # print the generated MSL
    os.environ["JIT"] = "0"
    import numpy as np
    from tinygrad import Tensor, Context
    from model import Model, load_weights

    X = np.load(MNIST / "data" / "mnist_test_images.npy", allow_pickle=False)[:n]
    with Context(DEV=device):
        m = Model()
    load_weights(m, MNIST / "weights.npz")
    import time
    for i in range(n):
        with Context(DEV=device):
            x = Tensor(X[i:i + 1].astype(np.float32) / 255.0).realize()
            t0 = time.perf_counter()
            logits = m(x)
            dt = time.perf_counter() - t0
        print(f"# img {i} pred={int(logits.argmax(axis=1).item())} secs={dt:.6f} "
              f"logits={','.join(repr(float(v)) for v in logits.flatten().tolist())}")
    return 0


def main() -> int:
    device = sys.argv[1] if len(sys.argv) > 1 else "METAL"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    if len(sys.argv) > 3 and sys.argv[3] == "--child":
        return child(device, n)

    with open(DUMP, "w") as dump:
        rc = subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()), device, str(n), "--child"],
                            cwd=HERE.parent.parent.parent, stdout=dump, stderr=subprocess.STDOUT).returncode
    text = DUMP.read_text()
    names = KERNEL_RE.findall(text) or C_RE.findall(text)
    rows = ROW_RE.findall(text)
    sched = SCHED_RE.findall(text)
    if rc != 0:
        print(f"# child rc={rc}")
    for num, pred, secs, lg in LOGIT_RE.findall(text):
        print(f"# img {num} pred={pred} secs={secs} logits={lg}")
    print(f"# device={device} n={n} programs={len(names)} "
          f"distinct_kernels={len(set(names))} rendered_bytes={len(text)} "
          f"metal_launches={len(rows)}")
    print(f"# distinct: {', '.join(sorted(set(names)))}")
    print(f"# scheduled: {sched}")
    for num, name, arg, us, ms in rows:
        print(f"#   METAL {num:>4} {name} arg={arg} tm={us}us/{ms}ms")
    print(f"# msl_dump={DUMP.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
