"""Is the executor's cost per ELEMENT, or per BYTE of wire (hex round-trip)?  Separate them.

A minimal packet with NO loop and a buffer of `n` bytes: the executor still reads the input
hex line, decodes it to storage, and re-encodes the whole buffer to PACKET.out.  If that is the
cost, time rises with `n` even though the kernel does nothing.

usage: .venv/bin/python bench_bytes.py [sizes...]
"""
import pathlib
import subprocess
import sys
import time

EXE = pathlib.Path.home() / "Library/Caches/tinygrad" / "bend-executor-970cbc1d5f288c9a"
HERE = pathlib.Path(__file__).resolve().parent


def minimal(nbytes: int) -> str:
    return (f"bendexec1 1 1\n1: PARAM f32 k:param:{nbytes}:g\n"
            f"{nbytes} {'00' * nbytes}\n")


def launch(pkt: str, grid=(1, 1, 1)) -> float:
    d = HERE / "tmp"
    d.mkdir(exist_ok=True)
    (d / "PACKET.in").write_text(pkt)
    t = time.perf_counter()
    r = subprocess.run([str(EXE), str(d / "PACKET.in"), *map(str, grid)],
                       capture_output=True, text=True)
    dt = time.perf_counter() - t
    assert r.returncode == 0, (r.returncode, r.stderr[:300])
    return dt


if __name__ == "__main__":
    sizes = [int(x) for x in sys.argv[1:]] or [16, 64, 1024, 4096, 16384, 65536]
    print(f"{'bytes':>8} {'best_s':>9} {'us_per_byte':>12}")
    for n in sizes:
        b = min(launch(minimal(n)) for _ in range(3))
        print(f"{n:>8} {b:>9.4f} {b / n * 1e6:>12.3f}")
