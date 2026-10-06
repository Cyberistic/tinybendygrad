"""The post-fix fit of `Tensor.ones(n,n).contiguous().realize()` under DEV=BEND, for larger n than
bench_tensor.py's cap: the wire is O(B) now, so whatever quadratic remains is the STORE path.

Fresh subprocess per cell, min of `--reps` (DEV is a process constant).

usage: .venv/bin/python fit.py [--reps N] [ns...]
"""
import os
import subprocess
import sys
import time

PROG = ("import time,sys;from tinygrad import Tensor;"
        "n=int(sys.argv[1]);t=time.perf_counter();"
        "Tensor.ones(n,n).contiguous().realize();print(time.perf_counter()-t)")


def one(n: int, reps: int) -> float:
    env = dict(os.environ, DEV="BEND")
    best = None
    for _ in range(reps):
        r = subprocess.run([".venv/bin/python", "-c", PROG, str(n)], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr[-400:]
        t = float(r.stdout.strip())
        best = t if best is None else min(best, t)
    return best


def main():
    argv = sys.argv[1:]
    reps = 2
    if argv and argv[0] == "--reps":
        reps, argv = int(argv[1]), argv[2:]
    ns = [int(x) for x in argv] or [64, 96, 128]
    print(f"min of {reps} fresh DEV=BEND processes; B = n*n*4 bytes")
    print(f"{'n':>5} {'B':>9} {'s':>9} {'us/elem':>10}")
    for n in ns:
        t = one(n, reps)
        print(f"{n:>5} {n * n * 4:>9} {t:>9.3f} {t / (n * n) * 1e6:>10.2f}")


if __name__ == "__main__":
    main()
