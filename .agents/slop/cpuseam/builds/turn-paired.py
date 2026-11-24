#!/usr/bin/env python3
"""**THE **SHIPPED **DAEMON **TURN**, **WALL **CLOCK**, **BETWEEN **TWO **BUILDS** -- **⇒⇒† AND **AND
**THIS **IS **THE **NUMBER **THE **USER **CARES **ABOUT** (⇒⇒† AND **AND **THE **RENDER's **SHAPE
**IS **A **PART **OF **A **TURN**)**.

**⇒⇒† AND **THE **TURN **IS **MEASURED **FROM **THE **WRITE **OF **THE **FRAME **TO **THE **FRAME's
**ANSWER** (⇒⇒† AND **AND **THE **DAEMON's **OWN **`@@END`**)**.
"""

import pathlib
import statistics
import sys
import time

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import portc  # noqa: E402
import noisefloor  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"


def turn_times(path: pathlib.Path, tag: str, n: int = 120):
  d = noisefloor.Daemon(path, tag)
  d.start()
  time.sleep(1.0)
  ts = []
  for _ in range(n):
    t0 = time.perf_counter()
    d.turn()
    ts.append((time.perf_counter() - t0) * 1000)
  time.sleep(0.2)
  d.stop()
  return ts


def main():
  a = BUILD / (sys.argv[1] if len(sys.argv) > 1 else "serve_base.js")
  b = BUILD / (sys.argv[2] if len(sys.argv) > 2 else "serve_reorder.js")
  # **⇒⇒† AND **THE **TWO **RUNS **ARE **ALTERNATED** (⇒⇒† AND **A **PAIRED **A/B**)**.
  da = noisefloor.Daemon(a, "tbase")
  db = noisefloor.Daemon(b, "tnew")
  da.start()
  db.start()
  time.sleep(1.0)
  ta, tb = [], []
  for _ in range(120):
    t0 = time.perf_counter()
    da.turn()
    ta.append((time.perf_counter() - t0) * 1000)
    t0 = time.perf_counter()
    db.turn()
    tb.append((time.perf_counter() - t0) * 1000)
  time.sleep(0.2)
  da.stop()
  db.stop()

  A = sorted(ta)
  B = sorted(tb)
  print()
  print(f"THE **SHIPPED **TURN** ({a.name} vs {b.name}), 120 paired turns:")
  print("  A: min %.4f  median %.4f  mean %.4f ms" % (A[0], A[len(A) // 2], statistics.mean(A)))
  print("  B: min %.4f  median %.4f  mean %.4f ms" % (B[0], B[len(B) // 2], statistics.mean(B)))
  print()
  print("  THE RATIO OF THE TWO MINIMA:  %.4f" % (B[0] / A[0]))
  print("  THE RATIO OF THE TWO MEDIANS: %.4f" % (B[len(B) // 2] / A[len(A) // 2]))
  print("  THE RATIO OF THE TWO MEANS:   %.4f" % (statistics.mean(B) / statistics.mean(A)))
  n = min(len(ta), len(tb))
  ratios = sorted(tb[i] / ta[i] for i in range(n))
  print("  THE MEDIAN OF THE PAIRED RATIOS: %.4f" % ratios[len(ratios) // 2])


if __name__ == "__main__":
  main()
