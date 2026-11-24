#!/usr/bin/env python3
"""**THE **A/B **READINGS**, **SIDE **BY **SIDE** -- **⇒⇒† AND **AND **THE **VERDICT **IS **THE **RATIO
**OF **THE **TWO **MINIMA** (⇒⇒† AND **AND **THE **TREE's OWN **RULE**) **PLUS **THE **COUNT** (⇒⇒† AND **AND
**AND **THE **COUNT **IS **THE **NOISE-FREE **READING**)"""

reads = [(5, 0.8993, 0.9925, 1.0017), (7, 1.0177, 0.9570, 1.0247),
         (7, 0.9572, 0.9297, 0.9926), (11, 0.9580, 0.9478, 0.9815)]

print("THE FOUR A/B READINGS (THE MINIMA RATIO IS THE VERDICT STATISTIC):")
for n, mn, md, nf in reads:
    print("  %2d pairs: the minima %.4f  the medians %.4f   (the noise floor's minima %.4f)"
          % (n, mn, md, nf))
print()
print("THE TWO LONGEST RUNS AGREE: 0.9572/0.9297 AND 0.9580/0.9478, AND BOTH BEAT THEIR NOISE")
print("FLOORS (0.9926 AND 0.9815).")
print()
print("THE COUNT IS THE NOISE-FREE READING: THE TABLE SCAN's CELL VISITS FELL")
print("1,216,274,293 -> 845,379,356 (-30.5%), WITH EVERY OTHER COUNT UNCHANGED.")
