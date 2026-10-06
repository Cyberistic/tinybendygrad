"""Reproduce bendperf's 291x: `walkbench` sums n U32s by `List.get(xs,i)` (idx) vs a cons walk (walk),
on the real bend compiler (the prebuilt Mach-O).  Min of `--reps`, seconds.

usage: .venv/bin/python walk.py [--reps N] [ns...]
"""
import pathlib
import subprocess
import sys
import time

EXE = pathlib.Path(__file__).resolve().parent.parent / "bendperf" / "walkbench"


def best(n: int, mode: str, reps: int) -> float:
    b = None
    for _ in range(reps):
        t = time.perf_counter()
        r = subprocess.run([str(EXE), str(n), mode], capture_output=True, text=True)
        dt = time.perf_counter() - t
        assert r.returncode == 0, r.stderr[-300:]
        b = dt if b is None else min(b, dt)
    return b


def main():
    argv = sys.argv[1:]
    reps = 3
    if argv and argv[0] == "--reps":
        reps, argv = int(argv[1]), argv[2:]
    ns = [int(x) for x in argv] or [1024, 4096, 8192, 16384]
    print(f"min of {reps}; the prebuilt walkbench Mach-O (a native run, not a bend process)")
    print(f"{'n':>7} {'idx_s':>9} {'walk_s':>9} {'ratio':>8}")
    for n in ns:
        i, w = best(n, "idx", reps), best(n, "walk", reps)
        print(f"{n:>7} {i:>9.4f} {w:>9.4f} {i / w:>7.1f}x")


if __name__ == "__main__":
    main()
