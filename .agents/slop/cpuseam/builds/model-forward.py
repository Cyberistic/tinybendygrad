# THE FORWARD-ORDER INDEX ARITHMETIC, DERIVED **FROM **THE **CURRENT **CODE'S **SEMANTICS**.
#
# THE CURRENT (NEWEST-FIRST) LAYOUT:
#   `ts`      = [BLOCK 0 (CURRENT), BLOCK 1, ..., BLOCK N-1 (OLDEST)]
#   A BLOCK   = [NEWEST ROW, ..., OLDEST ROW]
#   `b0`      = THE CURRENT BLOCK's LENGTH = ((n-1) & 15) + 1
#   `d`       = n-1-i              (THE REVERSE ROW INDEX: 0 IS THE NEWEST ROW)
#   `bi(d)`   = 0 IF d < b0 ELSE 1 + (d-b0)/16      (THE BLOCK NUMBER, 0 = CURRENT)
#   `off(d)`  = d IF d < b0 ELSE (d-b0) & 15        (THE OFFSET IN THE BLOCK, 0 = NEWEST ROW)
#   `Rows.blk(r, bi)` = List.get(ts, bi)            (BLOCK bi IS AT HEAD-POSITION bi)
#
# THE TARGET (FORWARD) LAYOUT:
#   `ts`      = [BLOCK 0 (OLDEST), BLOCK 1, ..., BLOCK N-1 (CURRENT)]
#   A BLOCK   = [OLDEST ROW, ..., NEWEST ROW]
#   AND **THE **FIRST **BLOCK's **LENGTH **IS **b0`**, **AND **EVERY **OTHER **BLOCK **HAS **16**.
#
# ⇒⇒⇒ AND **THE **FORWARD **INDEX**: **ROW `i`** (0 = OLDEST) **IS **AT
#   · **BLOCK `i/16`** IF `i < b0` (THE FIRST BLOCK), **ELSE
#   · **BLOCK `1 + (i-b0)/16`** AND **OFFSET `(i-b0) & 15`**.
#
# ⇒⇒⇒ AND **THAT IS **EXACTLY **THE **CURRENT **`Rows.bi`/`Rows.off`** WITH **`d` **REPLACED
# **BY **`i`**!** **⇒⇒⇒ AND **SO **THE **INDEX **CODE **IS **UNCHANGED** -- **ONLY **THE **DATA's
# **ORDER **CHANGES** -- **⇒⇒⇒ AND **THAT **IS **WHY **THE **CHANGE **IS **SMALL**.**

# THE **VERIFICATION**: **THE **CURRENT **CODE** WITH **`d` **REPLACED **BY **`i`** MUST **GIVE
# **THE **SAME **BLOCK **AND **OFFSET** FOR **THE **SAME **ROW** -- **⇒⇒⇒ AND **THAT **IS **THE
# **CHECK** THAT **THE **NEW **`rtp` **MUST **PASS**.
#
# THE **PROPERTY**: **THE **NEW **LAYOUT's **(bi, off)** FOR **ROW `i`** MUST **EQUAL **THE
# **OLD **LAYOUT's **(bi, off)** FOR **ROW `i`** -- **⇒⇒⇒ AND **THAT **IS **WHAT **THE **FIX
# **BUYS**: **THE **OLD **`rtp`** **USED **`d = n-1-i`** (THE **REVERSE **INDEX**) **AND **THE
# **NEW **ONE **USES **`i`** (THE **FORWARD **INDEX**)**.

def old_bi_off(n, i):
    d = n - 1 - i
    b0 = 0 if n == 0 else ((n - 1) & 15) + 1
    if d < b0:
        return 0, d
    return 1 + (d - b0) // 16, (d - b0) & 15

def new_bi_off(n, i):
    b0 = 0 if n == 0 else ((n - 1) & 15) + 1
    if i < b0:
        return 0, i
    return 1 + (i - b0) // 16, (i - b0) & 15

print("THE **NEW **INDEX** IS **THE **OLD **INDEX** WITH **`d = n-1-i`** REPLACED **BY `i`**,")
print("AND **THE **BLOCK LIST **MUST **BE **REBUILT **IN **THE **MATCHING **ORDER**.")
print()
n = 782
print("THE **BLOCK **NUMBER** FOR **EVERY **ROW**, OLD (REVERSE INDEX) VS NEW (FORWARD):")
for i in list(range(0, 20)) + [100, 400, 780, 781]:
    ob, oo = old_bi_off(n, i)
    nb, no = new_bi_off(n, i)
    print(f"  ROW {i:4d}: OLD bi={ob:3d} off={oo:3d}   NEW bi={nb:3d} off={no:3d}")
print()
print("=> AND THE NEW LAYOUT's BLOCK NUMBER IS SMALL FOR THE OLD ROWS (THE EARLY UOPS),")
print("   AND THE OLD LAYOUT's IS LARGE -- AND THAT IS THE WALK's REVERSAL, AND THE NEW WALK")
print("   FOR THE HOT ACCESSES (THE EARLY UOPS, WHICH ARE THE ALU's SOURCES) IS SHORT.")
