"""The wire fit, BEFORE vs AFTER the cons-walk fix, on the pre-fix and post-fix executor binaries.

A 1-uop packet with no loop and an `n`-byte buffer: the executor decodes the input hex line and
re-encodes the whole buffer to PACKET.out.  Fresh subprocess per launch, min of `--reps`.

usage: .venv/bin/python bench_bytes.py [--reps N] [sizes...]
"""
import pathlib
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
OLD = pathlib.Path.home() / "Library/Caches/tinygrad/bend-executor-970cbc1d5f288c9a"
NEW = pathlib.Path((HERE / "EXE").read_text().strip())


def minimal(nbytes: int) -> str:
    return (f"bendexec1 1 1\n1: PARAM f32 k:param:{nbytes}:g\n"
            f"{nbytes} {'00' * nbytes}\n")


def launch(exe: pathlib.Path, pkt: str) -> float:
    d = pathlib.Path(tempfile.mkdtemp())
    (d / "PACKET.in").write_text(pkt)
    t = time.perf_counter()
    r = subprocess.run([str(exe), str(d / "PACKET.in"), "1", "1", "1"], capture_output=True, text=True)
    dt = time.perf_counter() - t
    assert r.returncode == 0, (exe.name, r.returncode, r.stderr[:300])
    return dt


def main():
    argv = sys.argv[1:]
    reps = 2
    if argv and argv[0] == "--reps":
        reps, argv = int(argv[1]), argv[2:]
    sizes = [int(x) for x in argv] or [1024, 2048, 4096, 8192, 16384, 32768]
    print(f"min of {reps} fresh subprocesses per cell")
    print(f"{'bytes':>9} | {'OLD ms':>10} {'NEW ms':>10} | {'speedup':>8}")
    for n in sizes:
        pkt = minimal(n)
        old = min(launch(OLD, pkt) for _ in range(reps)) * 1000
        new = min(launch(NEW, pkt) for _ in range(reps)) * 1000
        print(f"{n:>9} | {old:>10.2f} {new:>10.2f} | {old / new:>7.1f}x")


if __name__ == "__main__":
    main()
