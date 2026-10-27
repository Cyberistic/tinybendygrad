#!/usr/bin/env python3
"""run.py -- THE END-TO-END RUN. Read the data, run the model, report a number.

    .venv/bin/python .agents/slop/mnist/run.py cpython [N]   # CPython's own numbers
    .venv/bin/python .agents/slop/mnist/run.py bend   [N]   # the PORT's numbers
    .venv/bin/python .agents/slop/mnist/run.py both   [N]   # both, compared per image

WHAT "END TO END" MEANS HERE, PRECISELY. Four things have to happen for one
number to be an end-to-end number, and each one is a thing that can be missing:

  1. THE DATA IS READ FROM A `.npy` FILE. `mnist_npy()` reads the four files
     `.agents/slop/mnist/prepare_npy.py` wrote. The port's own `.npy` path is in
     `tinybendygrad/nn/datasets.bend`.
  2. THE DATA LANDS ON THE DEVICE. `to_device_tensor` normalises to float32
     in [0,1] and realises the tensor ON the device under test.
  3. THE MODEL RUNS ON THE DEVICE, and its OUTPUT COMES BACK. `BendProgram.
     __call__` reads `PACKET.out` and copies the STORE-reachable buffers into
     the host views, so `.tolist()` on a Bend tensor is the executor's output
     arriving. THE DEVICE READ IS NOT A NEW SUBSYSTEM.
  4. THE NUMBER IS COMPARED AGAINST CPython's OWN NUMBER, on the same data
     and the same weights, image by image.

THE DENOMINATOR IS ALWAYS PRINTED. An accuracy without "of N" is a label.
"""
import pathlib
import sys
import time

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.nn.state import load_state_dict, get_state_dict  # noqa: E402

from harness import LAUNCHES, mnist_npy  # noqa: E402
from model import Model, load_weights  # noqa: E402

WEIGHTS = HERE / "weights.npz"


def build(device: str) -> Model:
    with Context(DEV=device):
        m = Model()
    load_weights(m, WEIGHTS)
    return m


def images(device: str, X: np.ndarray) -> Tensor:
    """the DATA, on the device."""
    with Context(DEV=device):
        t = Tensor(X.astype(np.float32) / 255.0).realize()
    return t


def forward(m: Model, x: Tensor):
    """the MODEL, on the device. Returns (logits, argmax) -- the argmax is the
    graph-level `Tensor.argmax(axis=1)`, which is the thing that produces the
    accuracy."""
    with Context(DEV=m_device_of(m)):
        logits = m(x)
        am = logits.argmax(axis=1)
        return logits.tolist(), am.tolist()


def m_device_of(m: Model) -> str:
    return next(iter(get_state_dict(m).values())).device


def run_device(device: str, X: np.ndarray, y: np.ndarray, per_image: bool):
    m = build(device)
    x = images(device, X)
    out = []
    for i in range(X.shape[0]):
        LAUNCHES.clear()
        t0 = time.perf_counter()
        with Context(DEV=device):
            logits = m(x[i:i + 1])
            am = int(logits.argmax(axis=1).item())
            lg = [float(v) for v in logits.flatten().tolist()]
        dt = time.perf_counter() - t0
        out.append({"i": i, "pred": am, "label": int(y[i]), "secs": dt,
                    "launches": len(LAUNCHES),
                    "launch_secs": [round(l["secs"], 3) for l in LAUNCHES],
                    "launch_ops": [l["ops"][:70] for l in LAUNCHES],
                    "launch_bufs": [l["bufs"] for l in LAUNCHES],
                    "nuops": [l["nuops"] for l in LAUNCHES],
                    "logits": lg})
        if per_image:
            print(f"  img {i:4d} pred={am} label={int(y[i])} {dt:8.3f}s "
                  f"launches={len(LAUNCHES)} {out[-1]['launch_secs']}", flush=True)
    return out


def summarize(rows, n_total):
    if not rows:
        return "no rows"
    correct = sum(1 for r in rows if r["pred"] == r["label"])
    secs = [r["secs"] for r in rows]
    return (f"accuracy {correct}/{len(rows)} = {100.0 * correct / len(rows):.2f}% "
            f"of the {n_total} test images; per-image {min(secs):.2f}s..{max(secs):.2f}s, "
            f"mean {sum(secs) / len(secs):.2f}s")


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "both"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    X, y = mnist_npy("test", n)
    print(f"# device=PYTHON(cpython) n={n} images {X.shape}", flush=True)

    cp_rows = None
    if mode in ("cpython", "both"):
        t0 = time.perf_counter()
        cp_rows = run_device("PYTHON", X, y, per_image=False)
        print(f"# CPython: {summarize(cp_rows, n)} wall={time.perf_counter() - t0:.2f}s", flush=True)

    if mode in ("bend", "both"):
        print(f"# device=BEND (the PORT's executor) n={n}", flush=True)
        bd_rows = run_device("BEND", X, y, per_image=True)
        print(f"# BEND: {summarize(bd_rows, n)}", flush=True)
        if cp_rows is not None:
            agree = sum(1 for a, b in zip(bd_rows, cp_rows) if a["pred"] == b["pred"])
            print(f"# ARGMAX AGREEMENT: {agree}/{len(bd_rows)} images", flush=True)
            md = max(abs(x - y) for a, b in zip(bd_rows, cp_rows) for x, y in zip(a["logits"], b["logits"]))
            bits = sum(1 for a, b in zip(bd_rows, cp_rows)
                       for x, y in zip(a["logits"], b["logits"]) if x == y)
            tot = sum(len(a["logits"]) for a in bd_rows)
            print(f"# LOGITS: {bits}/{tot} BIT-IDENTICAL to CPython's; "
                  f"max |bend - cpython| = {md:.3e}", flush=True)
        (HERE / f"bend_rows_{n}.rows").write_text(
            "# bend_rows.rows -- generated by .agents/slop/mnist/run.py\n"
            "# columns: i pred label secs launches launch_secs logits\n"
            + "\n".join(
                f"{r['i']} {r['pred']} {r['label']} {r['secs']:.3f} {r['launches']} "
                f"{','.join(str(s) for s in r['launch_secs'])} "
                + " ".join(repr(v) for v in r["logits"])
                for r in bd_rows) + "\n")
        (HERE / f"bend_kernels_{n}.rows").write_text(
            "# bend_kernels.rows -- generated by .agents/slop/mnist/run.py\n"
            "# the per-launch kernel identity of the FIRST image\n"
            "# columns: launch seconds nuops buffer_bytes op_runlength\n"
            + "\n".join(
                f"{k} {bd_rows[0]['launch_secs'][k]} {bd_rows[0]['nuops'][k]} "
                f"{bd_rows[0]['launch_bufs'][k]} {bd_rows[0]['launch_ops'][k]}"
                for k in range(len(bd_rows[0]["launch_secs"]))) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
