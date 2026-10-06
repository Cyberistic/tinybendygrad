"""Time a single BEND launch and keep the packet, so the executor can be timed WITHOUT tinygrad.

Wraps ops_bend's subprocess.run. Writes PACKET.in to .agents/slop/bendsuite/pkt-<n>.in (input side
of ops_bend.py:219) and prints the executor wall time per launch. Run under DEV=BEND.
"""
import os
import pathlib
import sys
import time

import tinygrad.runtime.ops_bend as ob

HERE = pathlib.Path(__file__).resolve().parent
_orig_run = ob.subprocess.run
_n = [0]


def timed_run(cmd, *a, **k):
    # ops_bend builds [exe, pkt, gx, gy, gz, *vals]; cmd[1] is the PACKET.in path we want to keep.
    pkt = pathlib.Path(str(cmd[1])) if len(cmd) > 1 else None
    t = time.perf_counter()
    r = _orig_run(cmd, *a, **k)
    dt = time.perf_counter() - t
    if pkt is not None and pkt.exists():
        (HERE / f"pkt-{_n[0]}.in").write_text(pkt.read_text())
    print(f"[launch {_n[0]}] executor {dt:.3f}s rc={r.returncode} nlines={len(pkt.read_text().splitlines()) if pkt else -1}")
    sys.stdout.flush()
    _n[0] += 1
    return r


ob.subprocess.run = timed_run

from tinygrad import Tensor  # noqa: E402

size = int(sys.argv[1]) if len(sys.argv) > 1 else 4
t = time.perf_counter()
Tensor.ones(size, size).contiguous().realize()
print(f"ones({size},{size}) total {time.perf_counter() - t:.3f}s")
