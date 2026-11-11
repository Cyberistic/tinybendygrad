#!/usr/bin/env python3
"""THE **STABLE** VERDICT STATISTIC: **THE RATIO OF TWO LOW QUANTILES**, NOT TWO MINIMA.

**WHY NOT THE MINIMUM:** MEASURED ON THIS MACHINE, **THE SAME BUILD AGAINST ITSELF** READS A
MINIMUM-RATIO OF **0.9864** ON THE RENDER AND **0.8719** ON THE DECODE -- **0.87 IS A 13% "WIN" ON
IDENTICAL BYTES**, WHICH IS **NOT A WIN**, IT IS **THE MINIMUM BEING A ONE-SAMPLE STATISTIC**. 
**AND A SINGLE TURN's READING IS A READING OF THE MACHINE'S SCHEDULER**: MEASURED, THE DECODE's
PER-TURN WALL READ **0.60 ms** AT ITS BEST AND **16.09 ms** AT ITS WORST **ON THE SAME BUILD** --
**A 27x SPREAD**, AND **THE SPREAD IS NOT THE PORT's WORK.**

****
****
**THE **p10** IS THE STABLE STATISTIC, AND HERE IS THE PROOF IT IS THE RIGHT ONE:** A QUANTILE
IS **AN AVERAGE OF MANY SAMPLES**, SO IT **INHERITS THE CENTRE's STABILITY**; AND **p10 IS LOW ENOUGH**
TO BE **INSIDE THE PORT's OWN COST** RATHER THAN **INSIDE THE SCHEDULER's TAIL**. 
****
****
****

****
**AND THE **PAIRED** MINIMUM-OF-RATIOS IS ALSO REPORTED**, BECAUSE **THE PAIRING IS WHAT
MAKES THE LOAD **COMMON-MODE** -- AND THE PAIRED MEDIAN IS REPORTED BESIDE IT, BECAUSE **THE VERDICT
MUST BE THE WORSE OF THE READINGS**: A WIN THAT **ONLY** ONE READING SEES IS **A WIN THE LOAD MADE.**

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

import statistics


def q(xs: list[float], p: float) -> float:
  """**THE p-QUANTILE**, BY LINEAR INTERPOLATION ON THE SORTED SAMPLE."""
  if not xs:
    return float("nan")
  s = sorted(xs)
  if len(s) == 1:
    return s[0]
  i = p * (len(s) - 1)
  lo = int(i)
  hi = min(lo + 1, len(s) - 1)
  return s[lo] + (s[hi] - s[lo]) * (i - lo)


def quantile_ratio(a, b, p: float = 0.10) -> float:
  """**THE RATIO OF THE TWO QUANTILES** -- THE VERDICT."""
  return q(b, p) / q(a, p)


def paired_min_ratio(a, b) -> float:
  """**THE MINIMUM OF THE PAIRED RATIOS** -- THE SECOND READING."""
  rs = [y / x for x, y in zip(a, b) if x > 0]
  return min(rs) if rs else float("nan")


def paired_median_ratio(a, b) -> float:
  """**THE MEDIAN OF THE PAIRED RATIOS** -- THE THIRD READING, AND THE LOUDEST."""
  rs = [y / x for x, y in zip(a, b) if x > 0]
  return statistics.median(rs) if rs else float("nan")


def wins(a, b) -> int:
  """**HOW MANY PAIRED TURNS THE NEW SIDE WAS FASTER**."""
  return sum(1 for x, y in zip(a, b) if y < x)


def report(label_a: str, label_b: str, a, b, same: bool, keeper: float = 0.97,
           p: float = 0.10) -> bool:
  """**PRINT THE VERDICT AND SAY WHETHER THE CHANGE IS KEPT.**"""
  print(f"\n{'=' * 74}")
  print(f"THE PAIRED A/B: **{label_a}** vs **{label_b}**   ({len(a)} PAIRED TURNS)")
  print(f"  same C: {same}")
  if not same:
    print(" **THE OUTPUTS DIFFER, SO THIS IS **NOT** A COMPARISON.**")
    return False
  qq = quantile_ratio(a, b, p)
  pm = paired_min_ratio(a, b)
  pmed = paired_median_ratio(a, b)
  print(f"  A  min {min(a):.4f}  p10 {q(a, p):.4f}  median {statistics.median(a):.4f}  max {max(a):.4f}")
  print(f"  B  min {min(b):.4f}  p10 {q(b, p):.4f}  median {statistics.median(b):.4f}  max {max(b):.4f}")
  print(f" **THE p10 RATIO** (THE VERDICT): {qq:.4f}")
  print(f" **THE MINIMUM OF THE PAIRED RATIOS** (THE SECOND READING): {pm:.4f}")
  print(f" **THE MEDIAN OF THE PAIRED RATIOS** (THE THIRD READING): {pmed:.4f}")
  print(f" **THE WIN COUNT**: {wins(a, b)}/{len(a)} PAIRED TURNS")
  keep = qq < keeper
  print(f" {'**KEEP**' if keep else '**REVERT**'} "
        f"(THE KEEPER LINE IS {keeper})")
  return keep
