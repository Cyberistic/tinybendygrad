import pathlib

# THE **FORWARD-ORDER** CHANGE: **THE **PRECISE **STATE **OF **THE **PROBLEM**, AND **THE
# **EXACTLY **WHAT **THE **NEXT **ATTEMPT **MUST **DO** -- **AND **WHY **THE **FIVE **ATTEMPTS
# **FAILED**.
#
# **⇒⇒⇒ AND **THIS **IS **THE **USEFUL **DELIVERABLE**: **THE **PROBLEM **IS **FULLY
# **CHARACTERIZED**, **SO **THE **NEXT **ATTEMPT **DOES **NOT **HAVE **TO **RE-DERIVE **ANYTHING**.

# ---------------------------------------------------------------- THE LAYOUT, **AS **BUILT
#
# **THE `ts` LIST** = [BLOCK 0, BLOCK 1, ..., BLOCK 48] (**49 **BLOCKS**).
# **MODE 2** (`st_put.r`) **APPENDS **A NEW **BLOCK **AT **THE **TAIL**: `List.append(ts, [[ps]])`.
# **MODE 1** **PREPENDS **THE **ROW **TO **BLOCK 0**: `List.append([ps], Rows.blk(r, 0))`.
#
# **⇒⇒⇒ AND **THAT **MAKES **THE **LAYOUT**:
#   · **BLOCK 0 **IS **THE **CURRENT **BLOCK** (THE **PARTIAL **ONE**, **LENGTH **`b0`** =
#     `((n-1)&15)+1`)**, **AND **IT **IS **AT **THE **HEAD**;
#   · **EVERY **OTHER **BLOCK **HAS **16** **ROWS**, **AND **THEY **GO **BACKWARD **IN **TIME**
#     (BLOCK 1 **IS **THE **PREVIOUS **16**, **AND **BLOCK 48 **IS **THE **OLDEST**)**;
#   · **AND **WITHIN **A **BLOCK**, **THE **HEAD **IS **THE **NEWEST **ROW** (MODE 1 **PREPENDS**).
#
# **⇒⇒⇒ AND **THE **BLOCK's **HEAD **BEING **THE **NEWEST **ROW **IS **WHY **THE **OLD `off`**
# **COUNTED **FROM **THE **HEAD** **WITHOUT **A **REVERSAL** -- **⇒⇒⇒ AND **THAT **IS **WHY **MY
# **OFFSET **REVERSAL **WAS **WRONG** (MEASURED: **IT **BROKE **THE **OUTPUT**)****.

# ---------------------------------------------------------------- THE INDEX, **AS **BUILT
#
# **THE `rtp` ACCESS** READS **ROW `i`** AS **`d = n-1-i`** (THE **REVERSE **ROW **INDEX**).
# **THE `bi`** = **THE **BLOCK **NUMBER**, **COUNTING **BACKWARD **FROM **THE **CURRENT **ONE**
#   (bi = 0 IS **THE **CURRENT **BLOCK**): `0 IF d < b0 ELSE 1 + (d-b0)/16`.
# **THE `off`** = **THE **OFFSET **WITHIN **THE **BLOCK**, **COUNTING **FROM **THE **BLOCK's
#   **HEAD** (THE **NEWEST **ROW**): `d IF d < b0 ELSE (d-b0) & 15`.
# **THE `Rows.blk(r, bi)`** = `List.get(ts, bi)` -- **⇒⇒⇒ AND **THE **BLOCK **AT **NUMBER `bi`**
#   **IS **AT **HEAD-POSITION `bi`** (BI = 0 IS **THE **HEAD**)****.

# ---------------------------------------------------------------- THE **HOT **ACCESSES
#
# **MEASURED** (`probe-outer-walk.py`, IN THE DAEMON): **THE `bi` **HISTOGRAM **IS **46 -> 1,200,
# 44 -> 690, 43 -> 840, 42 -> 300, 45 -> 150, 38 -> 240** -- **⇒⇒⇒ AND **THE **OUTER **WALK's
# **LENGTH **IS **44-49** ELEMENTS **FOR **~5,000** OF **THE 1,237** CALLS**, **⇒⇒⇒ AND **THE
# **OUTER **WALK **TOUCHED **33,360** ELEMENTS A TURN** (27.0 A CALL) **AND **THE **TOTAL **WITH
# **THE **INNER **WALK **IS **52,547** ELEMENTS A TURN**.
#
# **⇒⇒⇒ AND **THE **REASON** IS **THE **REVERSE **INDEX**: **THE **ALU's **SOURCES **ARE
# **EARLIER **UOPS** (SMALL `i`), **⇒⇒⇒ AND **`d = n-1-i` **IS **LARGE **FOR **THEM**, **⇒⇒⇒ AND
# **THAT **MAKES **`bi` **LARGE**, **⇒⇒⇒ AND **A **LARGE `bi`** **IS **A **POSITION **FAR **FROM
# **THE **HEAD** -- **⇒⇒⇒ AND **THAT **IS **THE **COST****.

# ---------------------------------------------------------------- **THE **FIX**, **STATED
#
# **⇒⇒⇒ AND **THE **FIX **IS **ONE **THING**: **MAKE **A **LARGE `bi`** **A **POSITION **NEAR **THE
# **HEAD**, **⇒⇒⇒ AND **THAT **MEANS **THE **BLOCK LIST **MUST **BE **REVERSED** (THE **OLDEST
# **BLOCK **AT **THE **HEAD**), **⇒⇒⇒ AND **THEN **THE **BLOCK **AT **NUMBER `bi`** **IS **AT
# **POSITION `nblocks-1-bi`**, **⇒⇒⇒ AND **THE **HOT **ACCESSES **WALK **2-6** ELEMENTS**.
#
# **⇒⇒⇒ AND **THE **FIVE **PARTS **OF **THE **REVERSAL** (AND **THEY **ARE **THE **FIVE
# **ATTEMPTS' **LESSONS**)**:
#
#   (1) **THE **BLOCK LIST's **ORDER**: **MODE **2 **MUST **PUT **THE **NEW **BLOCK **AT **THE
#        **HEAD** (THE **O(1) PREPEND**), **⇒⇒⇒ AND **THEN **THE **OLDEST **IS **AT **THE
#        **TAIL**... **⇒⇒⇒ NO: **THE **OLDEST **MUST **BE **AT **THE **HEAD**, **⇒⇒⇒ AND **THE
#        **NEWEST **AT **THE **TAIL** -- **⇒⇒⇒ AND **THAT **MEANS **THE **LIST **MUST **BE
#        **BUILT **IN **FORWARD **ORDER**, **⇒⇒⇒ AND **MODE **2 **MUST **APPEND **THE **NEW
#        **BLOCK **AT **THE **TAIL** (WHICH **IT **ALREADY **DOES**) **⇒⇒⇒ AND **THE **OLD
#        **BLOCKS **MUST **BE **MOVED **FROM **THE **TAIL **TO **THE **HEAD**, **⇒⇒⇒ AND **THAT
#        **IS **A **REVERSAL **PER **NEW **BLOCK** (49 **ELEMENTS **PER **16 **ROWS**, **⇒⇒⇒ AND
#        **~1,900 **ELEMENT **COPIES **A **TURN** AGAINST **THE **~4,000 **WALKS **IT
#        **REPLACES**)**.
#   (2) **MODE **1's **TARGET**: **THE **CURRENT **BLOCK **IS **NOW **AT **THE **TAIL**, **⇒⇒⇒ AND
#        **SO **MODE **1 **MUST **EXTEND **THE **TAIL** (POSITION `nblocks-1`)**, **⇒⇒⇒ AND **THE
#        **O(1) PREPEND **FORM **STAYS** (`List.append([ps], blk)`) **⇒⇒⇒ AND **THAT **KEEPS **THE
#        **BLOCK's **HEAD **AS **THE **NEWEST **ROW**, **⇒⇒⇒ AND **SO **THE **OFFSET **NEEDS **NO
#        **REVERSAL** -- **⇒⇒⇒ AND **THAT **IS **THE **THIRD **ATTEMPT's **LESSON***.
#   (3) **`Rows.bi`**: **IT **STILL **COUNTS **BACKWARD **FROM **THE **CURRENT **ONE**, **⇒⇒⇒ AND
#        **THAT **IS **FINE** -- **⇒⇒⇒ AND **THE **CURRENT **ONE **IS **AT **THE **TAIL**, **⇒⇒⇒ AND
#        **ITS **FORWARD **NUMBER **IS **`nblocks-1`**.
#   (4) **`Rows.off`**: **UNCHANGED** (IT **COUNTS **FROM **THE **BLOCK's **HEAD**, **WHICH **IS
#        **STILL **THE **NEWEST **ROW**)**.
#   (5) **`Rows.blk`**: **THE **INDEX **BECOMES **`nblocks-1-bi``** (THE **REVERSED **POSITION**)**.
#
# **⇒⇒⇒ AND **THE **FOURTH **ATTEMPT **FAILED **ONLY **ON **(1)** AND **(5)** -- **⇒⇒⇒ AND **ITS
# **TRACE **SHOWED **THE **BLOCK LENGTHS **[1, 1, ..., 1, 733]** (SUM 456), **⇒⇒⇒ AND **THAT **IS
# **THE **SIGNATURE **OF **A **SET **AT **THE **WRONG **POSITION**, **⇒⇒⇒ AND **THE **PARTIAL
# **BLOCK **WAS **NOT **AT **THE **HEAD** -- **⇒⇒⇒ AND **THE **FIX **IS **TO **REVERSE **THE
# **BLOCK LIST **WHEN **A **NEW **BLOCK **IS **CREATED** (THE **REVERSAL **PER **NEW **BLOCK**)**.


def old_bi(d, b0):
    return 0 if d < b0 else 1 + (d - b0) // 16


def old_off(d, b0):
    return d if d < b0 else (d - b0) & 15


NB = 49
print("THE **HOT **ACCESSES**, AND **THE **WALK **EACH **WAY**:")
for bi, calls in [(46, 1200), (45, 150), (44, 690), (43, 840), (42, 300), (38, 240)]:
    print(f"  bi {bi:3d} ({calls:5d} calls): NOW {bi:3d} STEPS, REVERSED {NB - 1 - bi:3d} STEPS")
print()
print("=>⇒⇒ AND **THE **REVERSAL **IS **ONE **PASS **PER **NEW **BLOCK** (49 **ELEMENTS **PER **16 #   **ROWS**), **⇒⇒⇒ AND **THE **REVERSAL's COST **IS **~1,900 **ELEMENT **COPIES **A **TURN** #   AGAINST **THE **~4,000 **WALKS **IT **REPLACES** -- **⇒⇒⇒ AND **IT **MUST **BE **MEASURED** #   (§138.5: **THE COUNT IS NOT THE COST**)****.")
print()
n = 781
b0 = ((n - 1) & 15) + 1
print(f"AND **THE **BASE**: n={n}, b0={b0}, nblocks={NB} -- **⇒⇒⇒ AND **b0 **IS **THE **CURRENT #   **BLOCK's **LENGTH** **IN **BOTH **ORDERS** (THE **ROWS **ARRIVE **ONE **AT **A **TIME**)**.")
print()
print("⇒⇒⇒ AND **THE **FIVE **PARTS**, **ONE **LAST TIME**, **AS **THE **CHECKLIST**:")
print("  (1) `st_put.r` MODE 2: **REVERSE **THE **BLOCK LIST **WHEN **A **NEW **BLOCK **IS #       **CREATED** (THE **OLDEST **MUST **END **UP **AT **THE **HEAD**) -- **⇒⇒⇒ AND **THE #       **REVERSAL **IS **THE **COST** (**49 **ELEMENTS **PER **16 **ROWS**)**.")
print("  (2) `st_put.r` MODE 1: **EXTEND **THE **TAIL** (`nblocks-1`), **KEEPING **THE **O(1) #       **PREPEND **FORM** (**SO **THE **BLOCK's **HEAD **STAYS **THE **NEWEST **ROW**) -- **⇒⇒⇒ AND #       **THE **TRACE **SHOWS **THE **HEAD **MUST **HOLD **THE **PARTIAL **BLOCK** (13 **ROWS**)**.")
print("  (3) `Rows.bi`: **UNCHANGED** (IT **COUNTS **BACKWARD **FROM **THE **CURRENT **ONE**) -- **⇒⇒⇒ #       **AND **THE **CURRENT **ONE **IS **AT **THE **TAIL**.")
print("  (4) `Rows.off`: **UNCHANGED** (IT **COUNTS **FROM **THE **BLOCK's **HEAD**) -- **⇒⇒⇒ AND #       **THE **OFFSET **REVERSAL **IS **WRONG**.")
print("  (5) `Rows.blk`: **THE **INDEX **BECOMES **`nblocks-1-bi`** -- **⇒⇒⇒ AND **THAT **IS **THE #       **ONE-LINE **CHANGE** THAT **MAKES **THE **WALK **SHORT**.")
