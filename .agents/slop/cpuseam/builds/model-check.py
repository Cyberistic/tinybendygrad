def old_index(n, i):
    d = n - 1 - i
    b0 = 0 if n == 0 else ((n - 1) & 15) + 1
    bi = 0 if d < b0 else 1 + (d - b0) // 16
    off = d if d < b0 else (d - b0) & 15
    return bi, off

def new_index(n, i):
    f = 16 if n % 16 == 0 else n % 16
    bi = 0 if i < f else 1 + (i - f) // 16
    off = i if i < f else (i - f) & 15
    return bi, off

# THE **WHOLE-ROW **INDEX **OF **THE **ROW **A **BLOCK **HOLDS **AT **A **GIVEN **OFFSET**.
# THE OLD LAYOUT: THE BLOCK AT POSITION `bi` HOLDS THE ROWS (16*bi .. 16*bi+16) OF THE **REVERSED**
#   ROW LIST, SO ITS OFFSET `off` (FROM THE NEWEST) IS THE **WHOLE-ROW** INDEX
#   `(n-1) - (16*bi + off)` ... **⇒⇒⇒ AND **THE **NEW **LAYOUT**: THE BLOCK AT POSITION `bi`
#   HOLDS THE ROWS (16*bi .. 16*bi+16) OF THE **FORWARD** ROW LIST, SO ITS OFFSET `no` (FROM THE
#   OLDEST) IS THE **WHOLE-ROW** INDEX `16*bi + no` (WITH THE FIRST BLOCK's SHORTER LENGTH).
#
# ⇒⇒⇒ AND **THE **CHECK** IS: **THE **WHOLE-ROW **INDEX **MUST **BE **THE **SAME **ROW** IN
# **BOTH** -- **⇒⇒⇒ AND **THAT **IS **WHAT **THE **OFFSET **REVERSAL **BUYS**.

print("THE **OFFSET **MUST **BE **REVERSED **WITHIN **THE **BLOCK** (THE **NEW **OFFSET **IS")
print("`len-1-off`), AND THE **BLOCK **NUMBER** **MUST **BE **REVERSED **TOO** (THE **NEW")
print("**BLOCK's **POSITION** IS **THE **OLD **ONE's **MIRROR**) -- **⇒⇒⇒ AND **THE **CHECK** IS")
print("**THAT **THE **WHOLE-ROW **INDEX **IS **THE **SAME **ROW** IN **BOTH**.")
print()

for n in [32, 100, 782]:
    f = 16 if n % 16 == 0 else n % 16
    print(f"n={n}, THE FIRST BLOCK's LENGTH f={f}:")
    for i in [0, 1, 15, 16, 100, n - 1]:
        ob, oo = old_index(n, i)
        nb, no = new_index(n, i)
        # THE **OLD **WHOLE-ROW **INDEX**: **THE **BLOCK AT POSITION `ob` HOLDS THE **REVERSED**
        # **ROWS**, SO ITS **OFFSET `oo` **FROM **THE **NEWEST** IS **THE **ROW
        # `(n-1) - (16*ob + oo)`** (WITH THE **FIRST **BLOCK's **SHORTER **LENGTH**).
        old_base = 0 if ob == 0 else (f + 16 * (ob - 1))
        old_row = old_base + (f - 1 - oo) if ob == 0 else old_base + (16 - 1 - oo)
        # THE **NEW **WHOLE-ROW **INDEX**: **THE **BLOCK AT POSITION `nb` HOLDS THE **FORWARD**
        # **ROWS**, SO ITS **OFFSET `no` **FROM **THE **OLDEST** IS **`16*nb + no`** (WITH THE
        # **FIRST **BLOCK's **SHORTER **LENGTH**).
        new_base = 0 if nb == 0 else (f + 16 * (nb - 1))
        new_row = new_base + no
        ok = "OK" if old_row == new_row else "MISMATCH"
        print(f"  ROW {i:4d}: OLD (bi={ob:3d}, off={oo:3d}) -> ROW {old_row:4d}   "
              f"NEW (bi={nb:3d}, off={no:3d}) -> ROW {new_row:4d}   {ok}")
    print()
