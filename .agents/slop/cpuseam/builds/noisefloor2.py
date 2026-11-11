#!/usr/bin/env python3
"""**WHICH QUANTILE IS THE STABLE VERDICT?** MEASURED, ON **IDENTICAL** BYTES.

**THE QUESTION:** THE VERDICT MUST **NOT** FIRE ON **THE SAME BUILD AGAINST ITSELF**. 
SO THE FLOOR OF EACH CANDIDATE STATISTIC IS **MEASURED** HERE, BY RUNNING **THE SAME BUILD** TWICE
AND ASKING **HOW FAR FROM 1.0** EACH STATISTIC READS. **THE ONE WITH THE SMALLEST DEVIATION
FROM 1.0 IS THE ONE THAT CAN CARRY A VERDICT.**

****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
****
"""

import pathlib
import sys

R = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(R / ".agents/slop/cpuseam"))
sys.path.insert(0, str(R / ".agents/slop/cpuseam/builds"))
import verdict2 as V  # noqa: E402
import paired2 as P  # noqa: E402

BUILD = R / ".agents/slop/cpuseam/builds"

QUANTILES = (0.02, 0.05, 0.10, 0.20, 0.30, 0.50)


def main():
  turns = int(sys.argv[1]) if len(sys.argv) > 1 else 200
  js = BUILD / "serve_base.js"
  out_a = BUILD / "nq_a.js"
  out_b = BUILD / "nq_b.js"
  P.clocked(js, out_a)
  P.clocked(js, out_b)
  ra, rb, dc, dd, same = P.run(out_a, out_b, turns, tag="nq")
  print(f"THE NOISE FLOOR, **IDENTICAL** BYTES, {len(ra)} PAIRED TURNS, same C: {same}")
  for name, a, b in (("RENDER", ra, rb), ("DECODE", dc, dd)):
    print(f"\n  THE {name}:")
    print(f"    A min {min(a):.4f}  p05 {V.q(a, 0.05):.4f}  p10 {V.q(a, 0.10):.4f}  "
          f"median {V.q(a, 0.5):.4f}")
    print(f"    B min {min(b):.4f}  p05 {V.q(b, 0.05):.4f}  p10 {V.q(b, 0.10):.4f}  "
          f"median {V.q(b, 0.5):.4f}")
    print(f" THE RATIO AT EACH QUANTILE (1.0 = IDENTICAL):")
    for p in QUANTILES:
      r = V.quantile_ratio(a, b, p)
      dev = abs(r - 1.0)
      print(f"      p{int(p * 100):02d}  ratio {r:.4f}   |dev| {dev:.4f}")
    print(f" THE MINIMUM OF THE PAIRED RATIOS: {V.paired_min_ratio(a, b):.4f}  "
          f"|dev| {abs(V.paired_min_ratio(a, b) - 1.0):.4f}")
    print(f" THE MEDIAN OF THE PAIRED RATIOS: {V.paired_median_ratio(a, b):.4f}  "
          f"|dev| {abs(V.paired_median_ratio(a, b) - 1.0):.4f}")


if __name__ == "__main__":
  main()
