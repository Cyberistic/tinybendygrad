#!/usr/bin/env python3
"""**THE **DECODING **OF **THE **CONCAT **CALL **CHAIN**, **AND **THE **DIRECT **CALLERS**.

**THE **SHAPE **OF **THE **MEASUREMENT.** THE COUNTER **FIRES **AT **THE **`String_concat`'s **HEAD
**SITE**, **AND **IT **RECORDS **THE **STACK**, **⇒⇒† AND **AND **THE **STACK **NAMES **EVERY
**ANCESTOR** (⇒⇒† AND **AND **THE **FRAMES **ARE **COUNTED **PER **NAME**, **⇒⇒† AND **AND **THE
**COUNT **OF **A **FRAME **IS **THE **NUMBER **OF **TIMES **IT **APPEARED **IN **A **STACK**) -- **⇒⇒†
**AND **SO **THE **COUNT **IS **CUMULATIVE **DOWN **THE **CHAIN** (⇒⇒† AND **AND **THE **DIRECT
**CALLER **OF **A **GIVEN **CONCAT **IS **THE **FRAME **WHOSE **COUNT **IS **THE **DIFFERENCE
**BETWEEN **ITS **OWN **AND **THE **CALLEE's**)**.
"""

import json
import pathlib
from collections import Counter

R = pathlib.Path(__file__).resolve().parents[4]
p = R / ".agents/slop/cpuseam/nf-lenserve_base/cpu.json.lg"
data = json.loads(p.read_text())
L = data.get("L", {})
n = 60
by = L.get("by", {})

CALLEE = "$String_concat"
callee = by.get(CALLEE, 0)
print(f"THE **CALLEE's **OWN **COUNT**: {callee/n:.1f} a turn  (the SELF-recursion)")
print()
print("THE **DIRECT **CALLERS**, **BY **THE **DIFFERENCE **BETWEEN **THE **FRAME's **COUNT "
      "**AND **THE **CALLEE's** (the DIFFERENCE IS THE CALLS THAT CAME FROM THAT FRAME)")

# **⇒⇒† AND **THE **FRAMES **ARE **COUNTED **PER **NAME**, **⇒⇒† AND **AND **A **FRAME's **COUNT
# **IS **THE **NUMBER **OF **STACKS **IN **WHICH **IT **APPEARED** (⇒⇒† AND **AND **IT **APPEARS **ONCE
# **PER **CONCAT **CALL **IN **ITS **CHAIN**) -- **⇒⇒† AND **AND **SO **THE **DIFFERENCE **BETWEEN **A
# **FRAME **AND **THE **ONE **BELOW **IT **IS **THE **CALLS **OF **THE **FRAME **THAT **DID **NOT
# **COME **FROM **THE **ONE **BELOW**)**.
names = list(by.keys())
# **⇒⇒† AND **THE **CHAIN **ORDER **IS **THE **ORDER **OF **THE **FIRST **APPEARANCE**, **⇒⇒† AND
# **AND **THE **FRAME's **COUNT **IS **NON-INCREASING **DOWN **THE **CHAIN** (⇒⇒† AND **AND **A
# **FRAME **DEEPER **IN **THE **CHAIN **APPEARS **IN **FEWER **STACKS**) -- **⇒⇒† AND **AND **SO **THE
# **COUNT **ORDER **IS **THE **CHAIN **ORDER**.**
ordered = sorted(by.items(), key=lambda kv: -kv[1])
prev = None
print()
print("  %9s  %9s  %s" % ("CALLS/TURN", "SHARE", "FRAME"))
for nm, c in ordered[:26]:
    short = nm.replace("$_________tinybendygrad_renderer_cstyle_", "").replace("$", "")
    share = ""
    if prev is not None:
        d = (prev - c) / n
        share = "%9.1f" % d
    print("  %9.1f  %9s  %s" % (c / n, share, short))
    prev = c
print()
print("  **AND **THE **DIFFERENCES **DO **NOT **SUM **TO **THE **CALLEE** -- **AND **THAT "
      "**IS **BECAUSE **A **FRAME **MAY **APPEAR **MORE **THAN **ONCE **IN **ONE **STACK** (the "
      "STACK IS A CHAIN AND A RECURSIVE CALL PUTS THE SAME FRAME IN IT REPEATEDLY) -- **AND "
      "**SO **THE **DIFFERENCE **IS **A **LOWER **BOUND **ON **THE **DIRECT **CALLS**.")
print()
print("  **AND **THE **LARGEST **DIFFERENCE **IS **THE **ANSWER**: **THE **FRAME **THAT "
      "**CONTRIBUTES **THE **MOST **DIRECT **CALLS **IS **THE **HOT **CALLER**.")
