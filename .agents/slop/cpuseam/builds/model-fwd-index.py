# THE **FORWARD **LAYOUT's **INDEX**, **DERIVED **FROM **THE **CODE** (NOT FROM **A **MODEL**).
#
# **THE **LAYOUT** (MEASURED, `probe-block-count.py`, IN THE DAEMON, ON **THE **NEW **BUILD**):
# THE BLOCK LENGTHS ARE **[16, 16, ..., 16, 13]** -- THE OLDEST BLOCK IS AT THE HEAD AND THE
# CURRENT ONE AT THE TAIL, AND THE PARTIAL BLOCK (`b0` = 13 ROWS) IS THE LAST ONE.
#
# THE OLD BUILD's LAYOUT WAS **[13, 16, ..., 16]** (THE PARTIAL ONE AT THE HEAD).
#
# THE ROWS WITHIN A BLOCK ARE NEWEST-FIRST (MODE 1 PREPENDS), SO THE OLDEST ROW OF A BLOCK IS
# AT ITS TAIL.


def block_bases(n):
    """THE BLOCK's BASE ROW INDEXES, IN THE FORWARD LAYOUT.

    THE FIRST BLOCK HAS `b0` ROWS AND THE REST HAVE 16, AND THE OLDEST BLOCK IS AT THE HEAD.
    """
    b0 = 0 if n == 0 else ((n - 1) & 15) + 1
    bases = []
    cur = 0
    count = 1 + ((n - b0) // 16 if n > b0 else 0)
    for k in range(count):
        ln = b0 if k == 0 else 16
        bases.append((cur, ln))
        cur += ln
    return bases


def lookup(n, i):
    """THE ROW `i`'s (BLOCK, OFFSET) IN THE FORWARD LAYOUT.

    THE BLOCK's ROWS ARE NEWEST-FIRST, SO THE ROW `i` (OLDEST-FIRST WITHIN THE BLOCK) IS AT
    OFFSET `ln-1-(i-base)` FROM THE HEAD.
    """
    for bi, (base, ln) in enumerate(block_bases(n)):
        if base <= i < base + ln:
            return bi, ln - 1 - (i - base)
    return None, None


n = 781
b0 = ((n - 1) & 15) + 1
print(f"n={n}, b0={b0}, AND THE FIRST BLOCK HAS b0 ROWS AND THE REST 16:")
for i in [0, 1, 12, 13, 14, 16, 100, 780]:
    bi, off = lookup(n, i)
    print(f"  ROW {i:4d}: THE NEW BLOCK {bi}, THE OFFSET {off}")
print()
print("AND THE OLD LAYOUT's (bi, off) FOR THE SAME ROWS:")
for i in [0, 1, 12, 13, 14, 16, 100, 780]:
    d = n - 1 - i
    ob = 0 if d < b0 else 1 + (d - b0) // 16
    oo = d if d < b0 else (d - b0) & 15
    print(f"  ROW {i:4d}: THE OLD BLOCK {ob}, THE OFFSET {oo}")
print()
print("=>⇒⇒ AND THE NEW BLOCK's BASE GROWS FORWARD, AND THE HOT ACCESSES (THE EARLY ROWS)")
print("   ARE IN THE FIRST BLOCKS -- AND THE WALK IS THE BLOCK's POSITION, WHICH IS SMALL.")
