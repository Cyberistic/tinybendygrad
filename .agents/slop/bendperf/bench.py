"""Attribute the BEND executor's cost from the OUTSIDE: synthetic packets run on the cached
executor binary, plus the real ones captured by probe.py.

The executor binary is a compiled Mach-O; running it is NOT a `bend` invocation (the compile
already happened, once, into tinygrad's cache).  So this file spawns no bend process and needs
no bounded.py -- it times the binary the device actually launches.

usage: .venv/bin/python bench.py <packet.in> [trips...]
"""
import pathlib
import statistics
import subprocess
import sys
import time

EXE = pathlib.Path.home() / "Library/Caches/tinygrad" / "bend-executor-970cbc1d5f288c9a"
HERE = pathlib.Path(__file__).resolve().parent


def parse(pkt: str):
    lines = pkt.splitlines()
    nuops = int(lines[0].split()[1])
    uops = lines[1:1 + nuops]
    bufs = lines[1 + nuops:]
    return uops, bufs


def trip_const(uops: list[str]) -> int:
    """Index (1-based) of the CONST the RANGE's trip reads: RANGE -> src0 -> src0."""
    for ln in uops:
        f = ln.split()
        if f[1] == "RANGE":
            head = f[0].rstrip(":")
            cast = int(f[4])                       # RANGE's src0
            csrc = uops[cast - 1].split()[4]       # that CAST's src0
            assert uops[int(csrc) - 1].split()[1] == "CONST", uops[int(csrc) - 1]
            return int(csrc)
    raise ValueError("no RANGE")


def variant(pkt: str, trip: int | None) -> str:
    """Rewrite ONLY the trip-count CONST the RANGE reads, to `trip`."""
    uops, bufs = parse(pkt)
    if trip is not None:
        k = trip_const(uops)
        f = uops[k - 1].split()
        uops = list(uops)
        uops[k - 1] = f"{f[0]} {f[1]} {f[2]} c:{trip}"
    return "\n".join([f"bendexec1 {len(uops)} {len(bufs)}"] + uops + bufs) + "\n"


def launch(pkt: str, grid=(1, 1, 1), label="") -> float:
    d = HERE / "tmp"
    d.mkdir(exist_ok=True)
    f = d / "PACKET.in"
    f.write_text(pkt)
    t = time.perf_counter()
    r = subprocess.run([str(EXE), str(f), *map(str, grid)], capture_output=True, text=True)
    dt = time.perf_counter() - t
    assert r.returncode == 0, (r.returncode, r.stderr[:400])
    return dt


def best(pkt: str, grid=(1, 1, 1), reps=3) -> float:
    return min(launch(pkt, grid) for _ in range(reps))


if __name__ == "__main__":
    src = pathlib.Path(sys.argv[1]).read_text()
    uops, bufs = parse(src)
    print(f"packet: {len(uops)} uops, {len(bufs)} buffers, {len(src)} bytes")
    for ln in uops:
        print("   ", ln)
    trips = [int(x) for x in sys.argv[2:]] or [0, 1, 4, 16, 64, 256, 1024]
    print(f"{'trip':>6} {'best_s':>9} {'per_iter_ms':>12}")
    base = None
    for tr in trips:
        dts = [launch(variant(src, tr)) for _ in range(3)]
        b = min(dts)
        if base is None:
            base = b
        slope = (b - base) / tr * 1000 if tr else 0
        print(f"{tr:>6} {b:>9.4f} {slope:>12.4f}   {[round(x,3) for x in dts]}")
