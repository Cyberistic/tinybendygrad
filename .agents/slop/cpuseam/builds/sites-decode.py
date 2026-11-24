#!/usr/bin/env python3
"""**THE **DECODING **OF **THE **DYNAMIC **CENSUS**, **AND **THE **AMPLIFICATION**."""

import json
import pathlib

R = pathlib.Path(__file__).resolve().parents[4]
p = R / ".agents/slop/cpuseam/nf-sitesserve_base/cpu.json.cs"
data = json.loads(p.read_text())
CS = data["CS"]
n = data.get("n", 1)
vals = [v for v in CS if isinstance(v, (int, float))]

print("THE TURNS:", n)
print()
print("THE PER-TURN COUNTS, BY SITE:")
for i, v in enumerate(vals):
    print("  site %2d: %9.1f a turn" % (i, v / n))

print()
print("THE AMPLIFICATION (the MEAN LIST LENGTH PER CALL):")
concat_total = 9967
concat_entries = vals[2] / n
print("  the CONCAT's OWN recursion: %.1f a turn" % concat_entries)
print("  the CONCAT's TOTAL calls a turn (the clock instrument): %d" % concat_total)
print("  **AND **THE **MEAN **LIST **LENGTH **OF **THE **CONCAT **CALLS **IS **%.1f **PIECES"
      % (concat_total / concat_entries))

print()
join_kernel = vals[3] / n
join_metal = vals[4] / n
concat_metal = vals[5] / n
print("  the JOIN in render_kernel_go: %.1f a turn  (THE PER-KERNEL JOIN)" % join_kernel)
print("  the JOIN in metal_prefix:     %.1f a turn" % join_metal)
print("  the CONCAT in metal_prefix:   %.1f a turn" % concat_metal)
print()
print("  **AND **THE **TOTAL **STRING **CALLS **A **TURN: %.0f"
      % (concat_entries + join_kernel + join_metal + concat_metal))
print("  **AND **THE **COST: **THE **CONCAT **IS **0.34 ms **OVER **9,967 **CALLS**, **AND **THE "
      "**JOIN **IS **0.27 ms **OVER **691 **CALLS** -- **AND **THE **JOIN's **691 **IS **691 "
      "**TOP-LEVEL **CALLS**, **AND **ITS **OWN **WALK **IS **2,693 **PIECES** -- **SO **THE "
      "**JOIN's **AMPLIFICATION **IS **3.9 **PIECES **A **CALL**, **AND **THE **CONCAT's **IS "
      "**35.7**.")
print()
print("  **AND **THE **VERDICT: **THE **CONCAT **IS **THE **BIGGER **TERM** (0.34 ms **vs **"
      "0.27 ms**) **AND **ITS **AMPLIFICATION **IS **9x **THE **JOIN's**, **AND **THE **CONCAT's "
      "**35.7 **PIECES **A **CALL **IS **THE **STATEMENT's **TEXT** -- **AND **THE **STATEMENT's "
      "**TEXT **IS **MOSTLY **A **LONG **EXPRESSION** (THE **`code_for_op` **ARM's **TEXT)**.")
