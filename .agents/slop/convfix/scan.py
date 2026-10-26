#!/usr/bin/env python3
"""WHICH CONV SHAPES RENDER A KERNEL WITH A LOCAL SCRATCH BUFFER?

    .venv/bin/python .agents/slop/convfix/scan.py

THE SCAN RENDERS, IT DOES NOT RUN: the hook raises right after the renderer has
produced the packet, so no executor is launched and the scan costs nothing but
the scheduler.

WHY IT MATTERS: a conv WITHOUT a scratch buffer never exercised the port's
byte-shift defect (the scratch is what put the zeros in the byte list), so the
small convs matched before the fix and the big one did not. A FIXTURE for the
conv lane has to be a conv that HAS the scratch, or it pins nothing.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402

import ops_bend as OB  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

CAP = []
_orig = OB.BendRenderer.render


def render(self, uops):
    CAP.append((list(uops), OB.BendRenderer.render.__doc__))
    raise RuntimeError("SCAN: the packet is captured; the launch is not needed")


def render(self, uops):  # noqa: F811
    CAP.append(list(uops))
    raise RuntimeError("SCAN")


OB.BendRenderer.render = render

SHAPES = [
    ((1, 1, 3, 3), (1, 1, 3, 3), 0),
    ((1, 1, 4, 4), (1, 1, 3, 3), 1),
    ((1, 2, 5, 5), (2, 2, 3, 3), 1),
    ((1, 3, 6, 6), (4, 3, 3, 3), 1),
    ((1, 3, 8, 8), (4, 3, 3, 3), 1),
    ((1, 3, 8, 8), (8, 3, 3, 3), 1),
    ((1, 3, 16, 16), (8, 3, 3, 3), 1),
    ((1, 3, 32, 32), (8, 3, 3, 3), 1),
]


def vals(n, seed=1.0):
    return [((i * 37) % 11 - 5) * seed + 0.5 for i in range(n)]


def main():
    for xs, ws, pad in SHAPES:
        xn = 1
        for d in xs:
            xn *= d
        wn = 1
        for d in ws:
            wn *= d
        CAP.clear()
        try:
            with Context(DEV='BEND'):
                x = Tensor(vals(xn), dtype=dtypes.float32).reshape(*xs).realize()
                w = Tensor(vals(wn, 0.25), dtype=dtypes.float32).reshape(*ws).realize()
                x.conv2d(w, padding=pad, stride=1).realize()
        except RuntimeError as e:
            if "SCAN" not in str(e):
                print(f"{xs} x {ws} p{pad}: {type(e).__name__}: {e}")
                continue
        for uops in CAP:
            nbuf = sum(1 for u in uops if u.op.name == "BUFFER")
            scratch = [u.arg for u in uops if u.op.name == "BUFFER"]
            print(f"{xs} x {ws} p{pad}: {len(uops)} uops, {nbuf} scratch BUFFER {scratch}")


if __name__ == '__main__':
    sys.exit(main())
