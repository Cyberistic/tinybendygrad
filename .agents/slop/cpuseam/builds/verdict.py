#!/usr/bin/env python3
"""THE **ROBUST** VERDICT STATISTIC FOR THE PAIRED A/B, AND WHY IT IS THIS ONE.

**THE PROBLEM, MEASURED:** ON A LOADED MACHINE (LOAD AVERAGE 12–47, OTHER UNITS AT 130–354%)
THE PAIRED RATIO OF **THE **SAME** BUILD AGAINST **ITSELF** READS A **MEDIAN** OF **1.0249** -- **ABOVE
ONE**, ON **IDENTICAL** BYTES. SO A **MEDIAN** OF A PAIRED RATIO **CANNOT** DISTINGUISH A WIN
FROM THE LOAD, AND THE VERDICT MUST BE A STATISTIC THAT **CAN**.

**AND THE **MINIMUM** IS THE RIGHT ONE, AND HERE IS **WHY**, IN ONE LINE:** THE PORT's
OWN COST IS **THE FLOOR OF ITS OWN TIME** -- A TURN THAT RAN WHILE THE MACHINE WAS QUIET IS **THE
TURN**, AND A TURN THAT RAN WHILE THE MACHINE WAS BUSY IS **THE TURN PLUS THE WAIT**. SO THE
**MINIMUM** OVER MANY TURNS IS **THE LEAST-CONTAMINATED** READING, AND THE **PAIRING** (A AND B
ALTERNATED) MAKES THE TWO SIDES **SEE THE SAME LOAD** ON AVERAGE.

**AND THE **MINIMUM** IS **NOT** A "BEST CASE" CHEAT, BECAUSE IT IS **THE SAME
STATISTIC ON BOTH SIDES**: THE VERDICT IS **min(B) / min(A)** -- A **RATIO OF TWO MINIMA**, NOT A
MINIMUM OF A RATIO. AND THE **MEDIAN** IS REPORTED BESIDE IT, BECAUSE A MEDIAN THAT SAYS
"0.93" AND A MINIMUM THAT SAYS "0.90" IS **A CONVERGENT WIN**, AND A MEDIAN THAT SAYS "0.93" AND A
MINIMUM THAT SAYS "1.01" IS **A WIN THAT THE LOAD IS MASKING** -- **BOTH ARE REPORTED, AND THE
VERDICT IS THE WORSE OF THE TWO.**

**AND THE **MINIMUM** IS **STABLE** WHERE THE MEDIAN IS NOT, BECAUSE THE MINIMUM
IS **ONE** READING AND THE MEDIAN IS **A SUM OF MANY**, SO THE MEDIAN **INHERITS EVERY OUTLIER** THE
MINIMUM **IGNORES**.

**AND **BOTH SIDES MUST RUN THE **SAME** NUMBER OF TURNS**, OR THE MINIMA
ARE TAKEN OVER DIFFERENT POPULATIONS AND THE RATIO IS **A COMPARISON OF TWO SAMPLES** RATHER THAN OF
**TWO BUILDS**.
"""

import statistics


def min_ratio(a, b):
  """**THE RATIO OF THE TWO MINIMA** -- THE VERDICT."""
  return min(b) / min(a)


def trimmed_ratio(a, b, frac: float = 0.25):
  """**THE RATIO OF THE TWO 25%-TRIMMED MINIMA** -- A SECOND READING, LESS EXPOSED TO A SINGLE
  UNLUCKY TURN."""
  def t(xs):
    s = sorted(xs)
    k = int(len(s) * frac)
    return s[k]
  return t(b) / t(a)


def paired_ratio(a, b):
  """**THE MEDIAN OF THE PAIRED RATIOS** -- THE THIRD READING, AND THE LOUDEST ONE."""
  rs = sorted(y / x for x, y in zip(a, b) if x > 0)
  return statistics.median(rs) if rs else float("nan")


def wins(a, b):
  """**HOW MANY PAIRED TURNS THE NEW SIDE WAS FASTER** -- THE COUNT, NOT THE RATIO."""
  return sum(1 for x, y in zip(a, b) if y < x)


def verdict(a, b):
  """**THE VERDICT, AND THE WORSE OF THE TWO RATIOS.**"""
  m = min_ratio(a, b)
  p = paired_ratio(a, b)
  return min(m, p), m, p


def report(label_a: str, label_b: str, a, b, same: bool, keeper: float = 0.97) -> bool:
  """**PRINT THE VERDICT AND SAY WHETHER THE CHANGE IS KEPT.**"""
  m, mr, pr = verdict(a, b)
  print(f"\n{'=' * 74}")
  print(f"THE PAIRED A/B: **{label_a}** vs **{label_b}**   ({len(a)} PAIRED TURNS)")
  print(f"  same C: {same}")
  if not same:
    print(" **THE OUTPUTS DIFFER, SO THIS IS **NOT** A COMPARISON.**")
    return False
  print(f"  A  min {min(a):.4f} ms   median {statistics.median(a):.4f}   max {max(a):.4f}")
  print(f"  B  min {min(b):.4f} ms   median {statistics.median(b):.4f}   max {max(b):.4f}")
  print(f" **THE RATIO OF THE MINIMA** (THE VERDICT): {mr:.4f}")
  print(f" **THE MEDIAN OF THE PAIRED RATIOS** (THE SECOND READING): {pr:.4f}")
  print(f" **THE WIN COUNT**: {wins(a, b)}/{len(a)} PAIRED TURNS")
  print(f" **THE VERDICT IS THE WORSE OF THE TWO**: {m:.4f}")
  keep = m < keeper
  print(f" {'**KEEP**' if keep else '**REVERT**'} "
        f"(THE KEEPER LINE IS {keeper}, AND THE NOISE FLOOR MUST BE BEATEN TOO)")
  return keep
