#!/usr/bin/env python3
"""ab33.py -- the §33 A/B, INTERLEAVED, on the 405-uop wire.

    .venv/bin/python .agents/slop/parity/ab33.py [--rounds 12]

WHY A SEPARATE INSTRUMENT. The §33 change (one decimal conversion per constant instead of seven) was
committed with no resolved timing: the machine was at load average 13.8, where the same 57 ms command read
78-154 ms. This runs the comparison the way the tree's own noise notes require -- the two artifacts
INTERLEAVED inside one round, so a load spike lands on both, and the ORDER alternated, because a
consistently-first artifact pays whatever the machine was doing at the start of each round.

It reports min, p25 and median per artifact and the same three for the per-round RATIO, which is the only
figure that survives a moving machine: a ratio near 1.0 with a band across 1.0 is "no measured effect" and
the change should be reverted rather than kept on a story.
"""
import os
import pathlib
import statistics
import subprocess
import sys
import time

R = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
import portc  # noqa: E402

OUT = R / ".agents/slop/cpuseam/out"
OLD = OUT / "live-76aefb6fd1d89400.js"   # before §33: seven i64_dec per constant
NEW = OUT / "live-fb3577411c5cbe91.js"   # after §33: one
BUN = os.path.expanduser("~/.bun/bin/bun")


def one(js, chunks) -> float:
  t0 = time.perf_counter()
  subprocess.run([BUN, str(js), *chunks], capture_output=True)
  return (time.perf_counter() - t0) * 1e3


def main() -> int:
  rounds = 12
  for i, a in enumerate(sys.argv):
    if a == "--rounds":
      rounds = int(sys.argv[i + 1])
  chunks = portc._chunks((OUT / "wire405.txt").read_text())
  old, new, ratio = [], [], []
  for r in range(rounds):
    if r % 2:
      n = one(NEW, chunks)
      o = one(OLD, chunks)
    else:
      o = one(OLD, chunks)
      n = one(NEW, chunks)
    old.append(o)
    new.append(n)
    ratio.append(n / o)
  for label, xs in (("before(7x)", old), ("after (1x)", new)):
    xs_s = sorted(xs)
    print(f"{label}  min {xs_s[0]:6.1f}  p25 {xs_s[len(xs_s)//4]:6.1f}  median {statistics.median(xs):6.1f}")
  rs = sorted(ratio)
  print(f"ratio new/old  min {rs[0]:.4f}  p25 {rs[len(rs)//4]:.4f}  median {statistics.median(rs):.4f}"
        f"  max {rs[-1]:.4f}")
  print(f"rounds where the new artifact is faster: {sum(1 for x in ratio if x < 1.0)} of {len(ratio)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
