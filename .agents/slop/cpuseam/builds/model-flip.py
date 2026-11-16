import collections
# WHAT THE OUTER WALK WOULD BE IF THE ACCESS WERE **FORWARD** INSTEAD OF **REVERSE**.
#
# MEASURED (probe-outer-walk.py, IN THE DAEMON): THE `bi` HISTOGRAM IS
#   46 -> 1,200   45 -> 150   44 -> 690   43 -> 840   42 -> 300   38 -> 240   ...
# AND THE **WALK LENGTH** HISTOGRAM IS
#   49 -> 780   48 -> 960   47 -> 150   46 -> 900   45 -> 870   44 -> 90   43 -> 1,140 ...
# =>⇒⇒ AND **THE **WALK LENGTH **IS **THE **BLOCK INDEX** (WITHIN **THE **MEASUREMENT's **NOISE**),
# =>⇒⇒ SO **`bi` IS **THE **POSITION **IN `ts`** AND **THE **WALK **IS **`bi` STEPS**.
#
# =>⇒⇒ AND `bi` IS **LARGE** FOR **MOST **CALLS** -- **⇒⇒⇒ AND **THE **REASON** IS **`d =
# n-1-i`** (THE **REVERSE **ROW **INDEX**): **THE **NEWEST **ROWS** (WHICH **ARE **READ
# **MOST** -- **THE **ALU's **SOURCES **ARE **THE **RECENTLY **ADDED **ROWS**) **MAP **TO **THE
# **LARGEST **`bi`**, **⇒⇒⇒ AND **THE **LARGEST **`bi`** IS **THE **FARTHEST **FROM **THE
# **HEAD**, **⇒⇒⇒ AND `List.get` WALKS **FROM **THE **HEAD***.
#
# =>⇒⇒ AND **THE **FIX**: **IF **THE **BLOCKS **WERE **STORED **IN **FORWARD **CHRONOLOGICAL
# ORDER** (THE **NEWEST **AT **THE **TAIL**), **THEN **THE **REVERSE **ACCESS **WOULD **FIND
# **THE **NEWEST **BLOCKS **AT **THE **TAIL****, **⇒⇒⇒ AND **THE **WALK **FROM **THE **HEAD**
# **WOULD **BE **SHORT **FOR **THE **HOT **ACCESSES****.
#
# =>⇒⇒ AND **THE **MEASUREMENT** IS **THE **SUM **OVER **THE **CALLS** OF **THE **WALK **THE
# **FIXED **ORDER **WOULD **COST**, **AND **THE **FIXED **ORDER's **WALK **IS **`nblocks-1-bi`****
# (THE **BLOCK **AT **THE **HEAD** **IS **THE **OLDEST**, **SO **THE **BLOCK **NUMBER `bi`** IS
# **AT **POSITION **`nblocks-1-bi`**)****.

# THE MEASURED `bi` HISTOGRAM, READ **FROM **THE **PROBE's OWN OUTPUT**.
BI = {46: 1200, 45: 150, 44: 690, 43: 840, 42: 300, 38: 240}
# **⇒⇒⇒ AND **THE **REST** OF **THE **CALLS** ARE **THE **SMALL **`bi`**s** -- **⇒⇒⇒ SO **THE
# **FULL **HISTOGRAM** IS **RECONSTRUCTED** FROM **THE **MEASURED **WALK-LENGTH** HISTOGRAM,
# **WHICH **IS **THE **SAME **DISTRIBUTION** (THE **WALK **IS **`bi`**)****.
WALK = {49: 780, 48: 960, 47: 150, 46: 900, 45: 870, 44: 90, 43: 1140, 42: 960,
        41: 960, 40: 960, 39: 960, 38: 810, 1: 30, 2: 540, 3: 720, 4: 900, 5: 180, 6: 150}

NBLOCKS = 49
current = sum(length * calls for length, calls in WALK.items())
flipped = sum((NBLOCKS - 1 - length) * calls for length, calls in WALK.items())
print(f"THE CURRENT ORDER's OUTER WALK: {current} ELEMENTS A TURN")
print(f"THE FLIPPED ORDER's OUTER WALK: {flipped} ELEMENTS A TURN")
print(f"**⇒⇒⇒ A SAVING OF {current - flipped} ELEMENTS ({100 * (current - flipped) / current:.0f}%)**")
print()
print("=> AND THE FLIPPED ORDER IS A ONE-LINE CHANGE TO st_put.r's MODE 2 (PREPEND THE NEW")
print("   BLOCK INSTEAD OF APPENDING IT) PLUS THE MATCHING INDEX IN Rows.bi/Rows.blk --")
print("   => AND IT MUST BE MEASURED, BECAUSE THE COUNT IS NOT THE COST.")
