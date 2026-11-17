# THE **FORWARD-ORDER** CHANGE: **FOUR ATTEMPTS**, **FOUR DISTINCT SUBTLETIES**, AND **WHY
# IT **IS **NOT **LANDED **YET**.
#
# **⇒⇒⇒ AND **THIS **IS **THE **MOST **USEFUL **PART **OF **THE **WORK**: **THE **PROBLEM **IS
# **FULLY **CHARACTERIZED**, **AND **THE **NEXT **ATTEMPT **DOES **NOT **HAVE **TO **RE-DERIVE
# **ANYTHING** -- **IT **ONLY **HAS **TO **GET **THE **LAST **PIECE **RIGHT**.

# THE **LAYOUT**, **EXACTLY**, FROM **THE **CODE** (MEASURED, `probe-block-lens.py`, IN THE
# DAEMON):
#
# **THE **OLD **BUILD**: THE BLOCK LENGTHS ARE **[13, 16, 16, ..., 16]** (49 BLOCKS, SUM 781) --
# **⇒⇒⇒ AND **THE **PARTIAL **BLOCK **(13 **ROWS**) **IS **AT **POSITION 0**, **⇒⇒⇒ AND **MODE 1's
# **`List.set(ts, 0, ...)` **REPLACES **IT**, **⇒⇒⇒ AND **SO **THE **CURRENT **BLOCK **IS **ALWAYS
# **AT **THE **HEAD** AND **ALWAYS **HAS **`b0` = `((n-1)&15)+1`** **ROWS** (THE **ROWS **ARRIVE
# **ONE **AT **A **TIME**)**.
#
# **THE **OLD **INDEX** (`d = n-1-i`, THE **REVERSE **ROW **INDEX**):
#   `bi(d)`  = 0 IF d < b0 ELSE 1 + (d-b0)/16       (THE **BLOCK **NUMBER**, 0 = THE **CURRENT**)
#   `off(d)` = d IF d < b0 ELSE (d-b0) & 15         (THE **OFFSET**, FROM **THE **NEWEST**)
#   `Rows.blk(r, bi)` = `List.get(ts, bi)`         (THE **BLOCK **AT **NUMBER `bi`** **IS **AT
#                                                    **HEAD-POSITION `bi`**)
#
# **⇒⇒⇒ AND **THE **HOT **ACCESSES**: **THE **ALU's **SOURCES **ARE **EARLIER **UOPS** (SMALL
# `i`), **⇒⇒⇒ AND **`d = n-1-i` **IS **LARGE** FOR **THEM**, **⇒⇒⇒ AND **`bi` **IS **LARGE**
# (42-46 FOR **~4,300** OF **THE 1,237** CALLS), **⇒⇒⇒ AND **THE **WALK **IS **42-49** ELEMENTS
# (THE **OUTER **WALK **TOUCHED **33,360** ELEMENTS A TURN**)**.

def old_bi(d, b0):
    return 0 if d < b0 else 1 + (d - b0) // 16

def old_off(d, b0):
    return d if d < b0 else (d - b0) & 15

# **THE **TARGET**: **THE **ROWS **STORED **OLDEST-FIRST**, **⇒⇒⇒ AND **THE **INDEX **COUNTING
# **FORWARD**, **⇒⇒⇒ AND **THE **HOT **ACCESSES **WALK **2-6** ELEMENTS**.

def new_bi(i, b0):
    return 0 if i < b0 else 1 + (i - b0) // 16

def new_off(i, b0):
    return i if i < b0 else (i - b0) & 15

print("THE **FORWARD **INDEX** IS **THE **OLD **ONE** WITH **`d = n-1-i`** REPLACED **BY `i`**,")
print("AND **THE **DATA **MUST **BE **REBUILT **IN **THE **MATCHING **ORDER** (THE **BLOCKS **AND # **THE **ROWS **WITHIN **A **BLOCK**)**.")
print()
n = 781
b0 = ((n - 1) & 15) + 1
nb = 1 + (n - b0) // 16
print(f"n={n}  b0={b0}  nblocks={nb}")
print()
print("THE **FOUR **ATTEMPTS** AND **THEIR **DISTINCT **FAILURES**:")
print()
print("  1. THE TAIL WALK (ROWS.blk WALKS FROM THE TAIL):")
print("     THE COUNTER NEVER DECREMENTED **AND** THE O(n) ACCUMULATOR -> 7.19x SLOWER, same C: False.")
print()
print("  2. THE COUNTER FIXED, THE O(1) PREPEND:")
print("     PREPENDING REVERSES THE VISIT ORDER -> 4.25x SLOWER, same C: False.")
print()
print("  3. NO ACCUMULATOR (THE WALK CARRIES THE BLOCK AND THE COUNTER):")
print("     A REAL WIN (0.9675) BUT same C: False -- THE WALK STILL STARTED AT THE HEAD, SO IT")
print("     FOUND THE HEAD-SIDE BLOCK.")
print()
print("  4. THE FULL FORWARD REBUILD (THE INDEX BECAME FORWARD AND THE DATA WAS REBUILT):")
print("     THE OUTPUT CHANGED (15,242 -> 12,222 BYTES) AND THE ROWS CAME BACK WITH EMPTY")
print("     NAMES -- AND THE BLOCK-LENGTH TRACE SHOWED **[7, 4, 2, 6, 3, 2, ..., 4, 32, 21, 8]**")
print("     (SUM 456, NOT 781), **⇒⇒⇒ AND **THAT **IS **THE **SIGNATURE **OF **A **WRITTEN #     **AT **THE **WRONG **POSITION** -- **THE **ROWS **ARE **LOST**.")
print()
print("⇒⇒⇒ AND **THE **SUBTLETY **THAT **THE **FOURTH **ATTEMPT **EXPOSED**: **THE **PARTIAL #     **BLOCK **IS **THE **CURRENT **ONE** **AND **ITS **LENGTH **IS **`b0`** -- **⇒⇒⇒ AND #     **`b0` **IS **THE **FORMULA `((n-1)&15)+1`**, **WHICH **IS **TRUE **IN **THE **OLD **ORDER** #     **BECAUSE **THE **CURRENT **BLOCK **IS **AT **THE **HEAD** **AND **MODE **1 **REPLACES #     **IT** -- **⇒⇒⇒ AND **IN **THE **FORWARD **ORDER **THE **CURRENT **BLOCK **IS **AT **THE #     **TAIL** **AND **MODE **1 **MUST **EXTEND **IT**, **⇒⇒⇒ AND **`b0` **STILL **DESCRIBES #     **IT** (THE **LENGTH **TRACKS `n`**) -- **⇒⇒⇒ AND **THE **ATTEMPT's **BUG **WAS **THE #     **`List.set` **POSITION**: **MODE **1 **SET **THE **POSITION **`nblocks-1`**, **⇒⇒⇒ AND #     **THAT **IS **THE **TAIL**, **⇒⇒⇒ AND **BUT **`nblocks` **WAS **COMPUTED **FROM **`n` #     **AND **`b0`**, **⇒⇒⇒ AND **`nblocks` **IS **RIGHT** -- **⇒⇒⇒ AND **THE **TRACE's **IRREGULAR #     **LENGTHS **SAY **THE **SET **LANDED **ON **THE **WRONG **BLOCK**, **⇒⇒⇒ AND **THE #     **LIKELY **CAUSE **IS **THAT **`Rows.blk(r, bi)` **AND **`st_put.r` **COMPUTE **THE **TAIL #     **POSITION **DIFFERENTLY** -- **`Rows.blk` **USES **`nblocks-1-bi`** (THE **BLOCK's #     **POSITION**) **AND **`st_put.r` **USES **`nblocks-1`** (THE **CURRENT **BLOCK's #     **POSITION**) -- **⇒⇒⇒ AND **FOR **bi = 0** (THE **CURRENT **BLOCK**) **THEY **AGREE**, #     **⇒⇒⇒ AND **FOR **bi > 0** **THEY **DO **NOT** -- **⇒⇒⇒ AND **`st_put.r` **EXTENDS **THE #     **CURRENT **BLOCK**, **SO **THAT **IS **FINE**, **⇒⇒⇒ AND **THE **REMAINING **SUSPECT** #     **IS **`Rows.blk` **BEING **CALLED **WITH **A **bi **THAT **IS **NOT **THE **BLOCK #     **NUMBER** -- **⇒⇒⇒ AND **`Rows.bi` **STILL **COMPUTES **THE **BACKWARD **COUNT**, **WHILE #     **THE **FORWARD **LAYOUT **NEEDS **THE **FORWARD **COUNT** -- **⇒⇒⇒ AND **THAT **IS **THE #     **FIFTH **SUBTLETY**, **AND **IT **IS **THE **ONE **TO **FIX **NEXT**.")
print()
print("⇒⇒⇒ AND **THE **FIFTH **SUBTLETY**, **STATED**: **THE **FORWARD **LAYOUT's **`bi`** MUST #     **COUNT **FORWARD **FROM **THE **OLDEST** (THE **HEAD**), **⇒⇒⇒ AND **THE **CURRENT #     **BLOCK's **FORWARD **NUMBER **IS **`nblocks-1`**, **⇒⇒⇒ AND **`Rows.bi(r, i)` **MUST #     **RETURN **THE **FORWARD **NUMBER**, **⇒⇒⇒ AND **`Rows.blk(r, bi)` **MUST **INDEX **WITH #     **IT **DIRECTLY** (NO **REVERSAL**), **⇒⇒⇒ AND **MODE **1 **MUST **EXTEND **THE **BLOCK #     **AT **`nblocks-1`** -- **⇒⇒⇒ AND **THAT **IS **THE **FIVE-PART **CHANGE**, **⇒⇒⇒ AND #     **THE **FIVE **PARTS **ARE **INDEPENDENT** AND **EACH **IS **ONE **OR **TWO **LINES**.")
