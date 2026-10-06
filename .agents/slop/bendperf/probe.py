"""Capture every Bend executor launch (full argv + packet + wall) for a minimal Tensor op.

Run under DEV=BEND. Writes each launch as <dir>/launch-<op>-<n>/  (packet + argv + timing).
Nothing outside .agents/slop/bendperf/.  argv is the fact bendsuite's time_launch.py dropped
(it saved only PACKET.in, so the grid could not be replayed); the grid is on argv, so it must
be kept to separate startup from per-work-item cost.

usage: DEV=BEND .venv/bin/python probe.py <n> [ones|add|copy]
"""
import json
import pathlib
import subprocess
import sys
import time

import tinygrad.runtime.ops_bend as ob

HERE = pathlib.Path(__file__).resolve().parent
_orig = subprocess.run
_n = [0]
OP = sys.argv[2] if len(sys.argv) > 2 else "ones"


def run(cmd, *a, **k):
    t = time.perf_counter()
    r = _orig(cmd, *a, **k)
    dt = time.perf_counter() - t
    pkt = pathlib.Path(str(cmd[1]))
    d = HERE / f"launch-{OP}-{_n[0]:03d}"
    d.mkdir(exist_ok=True)
    if pkt.exists():
        (d / "PACKET.in").write_text(pkt.read_text())
        out = pkt.parent / "PACKET.out"
        if out.exists():
            (d / "PACKET.out").write_text(out.read_text())
    (d / "argv.json").write_text(json.dumps([str(x) for x in cmd]))
    (d / "wall").write_text(f"{dt:.6f}\n")
    print(f"launch {_n[0]:03d} {dt:.4f}s rc={r.returncode} grid/args={list(map(str, cmd[2:]))}")
    sys.stdout.flush()
    _n[0] += 1
    return r


ob.subprocess.run = run

if __name__ == "__main__":
    from tinygrad import Tensor

    n = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    t = time.perf_counter()
    if OP == "add":
        (Tensor.ones(n).contiguous() + Tensor.ones(n).contiguous()).realize()
    elif OP == "copy":
        Tensor.ones(n).contiguous().realize()
    else:
        Tensor.ones(n, n).contiguous().realize()
    print(f"[{OP}] n={n} total {time.perf_counter() - t:.4f}s launches={_n[0]}")
