#!/usr/bin/env python3
"""compare.py -- THE PORT's STAGES AGAINST CPython's, element by element.

    .venv/bin/python .agents/slop/seams/compare.py [PORT_FILE]

WHAT IT READS

    .agents/slop/seams/expected.rows   CPython's OWN device (`oracle_stages.py`),
                                      the eight stages, IEEE-754 hex
    .agents/slop/seams/port_stages.f32  the PORT's eight stages, float32
                                       little-endian, from `kernel_mnist.bend`

WHAT IT PRINTS, per stage: the element count, how many elements are BIT-IDENTICAL,
the largest ABSOLUTE difference, the largest RELATIVE difference (against the
largest magnitude in the stage), and the first index that differs.

THE GATE.  The exit status is the verdict and it CAN GO RED:

    0  every stage is within TOL_REL of CPython's, and the argmax agrees
    1  a stage is outside TOL_REL, or the argmax disagrees
    2  a stage's size is wrong
    3  the port's file is the wrong size

WHY A TOLERANCE AND NOT BIT-IDENTITY.  MEASURED, 2026-10-27, on the eight
stages of `kernel_mnist.bend`: 2715 of 3136 conv1 elements are BIT-IDENTICAL to
CPython's, and the ones that are not differ by at most 4.77e-07 absolute and
1.37e-07 relative.  The port accumulates a convolution in the source order
`c, ky, kx` and CPython's CPU backend runs an im2col GEMM, so the SUMS ADD UP IN
A DIFFERENT ORDER and float32 addition is not associative: the two answers differ
by a rounding step and no more.  A bit-identity gate would therefore be a gate
on the oracle's ACCUMULATION ORDER, not on the port's arithmetic, and it would
be red for a correct kernel.

WHY TOL_REL IS 1e-05.  The measured worst relative difference is 1.37e-07, and
the plant (`plant.py`, the tap count off by one) measures 1.37e-01.  The
threshold sits 73 times above the measured value and 13 700 times below the
plant's, so the gate is not tight enough to be flaky and not loose enough to
admit the defect it exists to catch.
"""
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent

STAGES = [
    ("conv1", 3136),
    ("relu1", 3136),
    ("pool1", 784),
    ("conv2", 1568),
    ("relu2", 1568),
    ("pool2", 392),
    ("flat", 392),
    ("logits", 10),
]

# The gate's threshold, and the measurement that set it.  See the header.
TOL_REL = 1e-05


def oracle() -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}
    for line in (HERE / "expected.rows").read_text().splitlines():
        if line.startswith("#"):
            continue
        name, shape, count, digest, hexs = line.split()
        assert int(count) == len(hexs) // 8, (name, count, len(hexs))
        bits = np.frombuffer(bytes.fromhex(hexs), dtype=">u4")
        # The oracle writes each float's IEEE-754 PATTERN as a big-endian u32
        # hex.  `frombuffer` reads those bytes as big-endian u32 VALUES, and
        # `.view` then reinterprets each value's own bits as a float32 -- so
        # the two steps are "decode the bytes" and "read the pattern", and
        # neither of them is a byte order guess.
        out[name] = bits.astype(np.uint32).view(np.float32).astype(np.float32)
        assert out[name].size == int(count), (name, out[name].size, count)
    return out


def port(path: pathlib.Path) -> dict[str, np.ndarray]:
    blob = path.read_bytes()
    want = 4 * sum(n for _, n in STAGES)
    if len(blob) != want:
        print(f"# FATAL: {path.name} is {len(blob)} bytes, the layout wants {want}")
        raise SystemExit(3)
    allv = np.frombuffer(blob, dtype="<f4")
    out, at = {}, 0
    for name, n in STAGES:
        out[name] = allv[at:at + n]
        at += n
    return out


def main() -> int:
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "port_stages.f32"
    ref = oracle()
    got = port(path)
    print(f"# oracle expected.rows, port {path.name} "
          f"({sum(4 * n for _, n in STAGES)} bytes), tol_rel={TOL_REL:g}")
    worst = 0.0
    red = []
    for name, n in STAGES:
        a, b = ref[name], got[name]
        if a.size != b.size:
            print(f"{name}: SIZE MISMATCH oracle {a.size} port {b.size}")
            return 2
        same = int((a.view(np.uint32) == b.view(np.uint32)).sum())
        diff = np.abs(a.astype(np.float64) - b.astype(np.float64))
        amax = float(np.abs(a).max())
        rel = float(diff.max() / amax) if amax > 0 else 0.0
        bad = np.nonzero(a.view(np.uint32) != b.view(np.uint32))[0]
        first = int(bad[0]) if bad.size else -1
        worst = max(worst, rel)
        if rel > TOL_REL:
            red.append(name)
        print(f"{name:7s} n={n:5d} bit_identical={same:5d}/{n:5d} "
              f"max_abs={diff.max():.9g} max_rel={rel:9g} first_diff_index={first}")
        if first >= 0:
            i = first
            print(f"         at {i}: oracle {a[i]!r} port {b[i]!r} "
                  f"oracle_bits={a.view(np.uint32)[i]:08x} port_bits={b.view(np.uint32)[i]:08x}")
    la, lb = ref["logits"], got["logits"]
    agree = int(la.argmax()) == int(lb.argmax())
    print(f"# argmax oracle {int(la.argmax())} port {int(lb.argmax())} agree={agree}")
    print("# oracle logits " + " ".join(f"{v:.6f}" for v in la))
    print("# port   logits " + " ".join(f"{v:.6f}" for v in lb))
    if not agree:
        red.append("argmax")
    if red:
        print(f"# VERDICT: RED -- outside tol_rel {TOL_REL:g}: {', '.join(red)}; "
              f"worst_rel={worst:g}")
        return 1
    print(f"# VERDICT: GREEN -- every stage within tol_rel {TOL_REL:g}; worst_rel={worst:g}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
