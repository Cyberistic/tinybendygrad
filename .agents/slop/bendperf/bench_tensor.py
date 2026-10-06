"""The throughput fit: a minimal Tensor fill under DEV=BEND and DEV=PYTHON, per size.

Each size is a FRESH process (DEV is a process constant in tinygrad), timed from before the
Tensor call to after realize().  Run with .venv/bin/python; it shells out to .venv/bin/python
with DEV set, because the device is selected at import.

usage: .venv/bin/python bench_tensor.py [op]
"""
import os
import subprocess
import sys
import time

PROG = (
    "import time;from tinygrad import Tensor;"
    "n=int(__import__('sys').argv[1]);t=time.perf_counter();"
    "{call}.realize();print(time.perf_counter()-t)"
)
OPS = {
    "ones": "Tensor.ones(n,n).contiguous()",
    "add": "(Tensor.ones(n,n).contiguous()+Tensor.ones(n,n).contiguous())",
    "copy": "Tensor.ones(n,n).contiguous()",
}
HERE = os.path.dirname(os.path.abspath(__file__))


def one(dev: str, op: str, n: int, reps: int = 2) -> float:
    env = dict(os.environ, DEV=dev)
    best = None
    for _ in range(reps):
        t = time.perf_counter()
        r = subprocess.run([".venv/bin/python", "-c", PROG.format(call=OPS[op]), str(n)],
                           capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr[-400:]
        best = min(best, float(r.stdout.strip())) if best is not None else float(r.stdout.strip())
    return best


if __name__ == "__main__":
    op = sys.argv[1] if len(sys.argv) > 1 else "ones"
    ns = [8, 16, 24, 32, 48, 64]
    print(f"op={op}   size = n x n")
    print(f"{'n':>4} {'elems':>7} {'bytes':>8} | {'BEND_s':>9} {'PY_s':>8} | {'BEND_us/elem':>12} {'PY_us/elem':>11}")
    for n in ns:
        e = n * n
        b = e * 4
        tb = one("BEND", op, n) if op != "add" or e <= 4096 else None
        tp = one("PYTHON", op, n)
        fb = f"{tb:9.4f}" if tb else "     skip"
        ub = f"{tb / e * 1e6:12.2f}" if tb else "        skip"
        print(f"{n:>4} {e:>7} {b:>8} | {fb:>9} {tp:8.4f} | {ub:>12} {tp / e * 1e6:11.2f}")
