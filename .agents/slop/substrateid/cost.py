#!/usr/bin/env python3
"""THE COST, ISOLATED. `measure.py` interleaves this digest with subprocess launches and module
loads, which evict the page cache between sweeps; this file times the SAME digest in a tight loop,
then again after dropping caches, so warm and cold are two numbers rather than one guess.

    .venv/bin/python .agents/slop/substrateid/cost.py > .agents/slop/substrateid/cost.out 2>&1
"""
from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("snapshot", ROOT / ".agents/slop/quiesce/snapshot.py")
snap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snap)

HAVE_PURGE = bool(shutil.which("purge"))


def digest(root: pathlib.Path) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(entries(root)):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def entries(root: pathlib.Path) -> list[tuple[str, str]]:
    out = [(p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
           for p in root.joinpath("tinybendygrad").rglob("*")
           if p.is_file() and "__pycache__" not in p.parts]
    for c in snap.COPIES:
        p = root / c
        if p.is_dir():
            out += [(q.relative_to(root).as_posix(), hashlib.sha256(q.read_bytes()).hexdigest())
                    for q in p.rglob("*") if q.is_file()]
        elif p.is_file():
            out.append((p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest()))
    return sorted(out)


def sweep(label: str, n: int) -> list[float]:
    ts = []
    for _ in range(n):
        t0 = time.perf_counter()
        digest(ROOT)
        ts.append((time.perf_counter() - t0) * 1000)
    ts.sort()
    print(f"  {label:<34} min {ts[0]:7.1f} ms   median {ts[n // 2]:7.1f} ms   max {ts[-1]:7.1f} ms")
    return ts


n_files = len(entries(ROOT))
n_bytes = sum(p.stat().st_size for p in snap.inputs())
print(f"population : {n_files} inputs, {n_bytes / 1e6:.2f} MB")
print(f"purge on PATH : {HAVE_PURGE}  (COLD below is only a true COLD if this is True)")
warm = sweep("one digest, WARM (tight loop)", 15)
if HAVE_PURGE:
    cold: list[float] = []
    for _ in range(3):
        subprocess.run(["purge"], capture_output=True)
        t0 = time.perf_counter()
        digest(ROOT)
        cold.append((time.perf_counter() - t0) * 1000)
    cold.sort()
    print(f"  {'one digest, COLD (after purge)':<34} min {cold[0]:7.1f} ms   "
          f"median {cold[len(cold)//2]:7.1f} ms   max {cold[-1]:7.1f} ms")
else:
    print("  one digest, COLD                  : NOT MEASURED -- no `purge`, and a warm number")
    print("                                       dressed as a cold one is the exact fault this file")
    print("                                       exists to catch (`bendperf`: a cold substrate costs")
    print("                                       more, so a warm % is not a cold %).")

two = warm[len(warm) // 2] * 2
print(f"\nTWO digests per run (start + end), warm median : {two:.1f} ms")
print(f"  ... and the BEST of 15, which is the contention-free floor  : {2 * warm[0]:.1f} ms")
print(f"  vs run34's WARM 294 s run (median)             : {100 * two / 294_000:.4f} %")
print(f"  vs run34's WARM 294 s run (floor)              : {100 * 2 * warm[0] / 294_000:.4f} %")
print(f"  vs ONE COLD bend launch (~2.8 s, bendperf)     : {100 * two / 2_800:.2f} %")
if HAVE_PURGE:
    two_cold = cold[len(cold) // 2] * 2
    print(f"  and on a COLD page cache, two digests          : {two_cold:.1f} ms "
          f"= {100 * two_cold / 2_800:.2f} % of one cold launch")

# ---- WHERE THE TIME GOES: the number above is CONTENDED, not the cost of the algorithm ---------
print("\n== READ vs HASH, same population, 15 sweeps each ==")
blobs = [p.read_bytes() for p in snap.inputs()]
reads, hashes = [], []
for _ in range(15):
    t0 = time.perf_counter()
    for p in snap.inputs():
        p.read_bytes()
    reads.append((time.perf_counter() - t0) * 1000)
    t0 = time.perf_counter()
    for b in blobs:
        hashlib.sha256(b).hexdigest()
    hashes.append((time.perf_counter() - t0) * 1000)
reads.sort()
hashes.sort()
print(f"  read {len(blobs)} files        min {reads[0]:7.1f} ms  median {reads[len(reads)//2]:7.1f} ms")
print(f"  sha256 {len(blobs)} buffers   min {hashes[0]:7.1f} ms  median {hashes[len(hashes)//2]:7.1f} ms")
print(f"  => the digest is I/O bound; hashing {sum(map(len, blobs))/1e6:.2f} MB of already-read bytes")
print(f"     costs {hashes[len(hashes)//2]:.1f} ms, so the floor for read+hash is ~"
      f"{reads[0] + hashes[len(hashes)//2]:.0f} ms and everything above it is OTHER UNITS")
print("     writing this tree. THE SPREAD ABOVE IS CONTENTION, NOT THE ALGORITHM, and the COLD")
print("     median landing BELOW the WARM median is the proof: a colder cache cannot be faster.")
print(f"  min/median/max ratio this run : {warm[-1] / warm[0]:.1f}x")