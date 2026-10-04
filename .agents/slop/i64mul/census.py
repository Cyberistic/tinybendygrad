#!/usr/bin/env python3
"""THE hi==lo CENSUS, and the rows each mutation does NOT move.

The libclang null-handle answers are 0, -1 and int64.min, and 0 and -1 have hi == lo,
so a half-swap is invisible on fixtures built only from those. This measures how many
fixtures here have hi != lo, and which rows a plant leaves untouched.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
HELPERS = f"{REPO}/tinybendygrad/helpers.bend"
BEND = f"{REPO}/bin/bend"
M = 1 << 32
W = 1 << 64

def run_gate():
    subprocess.run([sys.executable, "gen_gate.py"], cwd=HERE, capture_output=True)
    out = subprocess.run([BEND, "gate.bend"], cwd=HERE, capture_output=True, text=True)
    got = {}
    for ln in out.stdout.splitlines():
        m = re.match(r'^([ms]_[A-Za-z0-9_]+)=(\d+:\d+)$', ln)
        if m:
            got[m.group(1)] = m.group(2)
    return got

EXPECTED = dict(l.strip().split("=", 1) for l in open(f"{HERE}/expected.txt"))
BASE = open(HELPERS).read()
BASE_GOT = run_gate()
print("=== the gate is armed: baseline == the oracle on every row ===")
bad = [k for k in EXPECTED if BASE_GOT.get(k) != EXPECTED[k]]
print(f"rows_expected={len(EXPECTED)} rows_present={len(BASE_GOT)} disagree={len(bad)}")
assert not bad, bad[:5]

# ---- the fixtures, as (a, b) integer pairs, recovered from the generated gate ----
FIX = []
for ln in open(f"{HERE}/gate.bend"):
    m = re.match(r'\s*mrow\("(\w+)", (\d+), (\d+), (\d+), (\d+)\)', ln)
    if m:
        nm, ah, al, bh, bl = m.group(1), *map(int, m.groups()[1:])
        a = (ah << 32) | al
        b = (bh << 32) | bl
        FIX.append((nm, a, b))

print()
print("=== hi == lo census: which fixtures can see a half-swap at all ===")
def halves(v):
    u = v & (W - 1)
    return u >> 32, u & 0xFFFFFFFF
eq_both = [n for n, a, b in FIX if halves(a)[0] == halves(a)[1] and halves(b)[0] == halves(b)[1]]
ne_any = [n for n, a, b in FIX if n not in eq_both]
print(f"fixtures={len(FIX)}")
print(f"  BOTH operands hi==lo (blind to a half-swap): {len(eq_both)} -> {eq_both}")
print(f"  hi!=lo on at least one operand:              {len(ne_any)}")
print()
print("the three libclang sentinels, as word pairs:")
for lbl, v in [("0", 0), ("-1", -1), ("int64.min", -(1 << 63))]:
    h, l = halves(v)
    print(f"  {lbl:>10} -> {h}:{l}   hi==lo: {h == l}")

# a half-swap is `cross` landing in the low word; its rows are what matter
print()
print("=== which rows SEE each mutation (a plant that moves nothing is a blind spot) ===")
MUTS = [
    ("drop_carry", "disarm", "U32.shln(Bool.to_u32(U32.is_lt(cross, p10)), 16n)", "0"),
    ("carry_at_bit0", "disarm", "U32.shln(Bool.to_u32(U32.is_lt(cross, p10)), 16n)", "Bool.to_u32(U32.is_lt(cross, p10))"),
    ("cross_in_low_word", "disarm", "i64_of_hi_lo(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 0)", "i64_of_hi_lo(0, U32.add(U32.mul(al, bh), U32.mul(ah, bl)))"),
    ("no_carry_out_of_t", "disarm", "U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00)))", "U32.add(p11, carry)"),
    ("limbs_swapped", "disarm", "+al = U32.and(a, 65535)", "+al = U32.shrn(a, 16n)"),
    ("no_sign_flip", "disarm", "i64_neg(Bool.xor(i64_is_neg(a), i64_is_neg(b)), u64_mul(i64_abs(a), i64_abs(b)))", "u64_mul(i64_abs(a), i64_abs(b))"),
    ("plant_high_plus_one", "plant", "U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00)))", "U32.add(U32.add(U32.add(p11, carry), Bool.to_u32(U32.is_lt(t, p00))), 1)"),
    ("plant_cross_plus_one", "plant", "i64_of_hi_lo(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 0)", "i64_of_hi_lo(U32.add(U32.add(U32.mul(al, bh), U32.mul(ah, bl)), 1), 0)"),
]
try:
    for name, kind, frm, to in MUTS:
        assert frm in BASE, name
        open(HELPERS, "w").write(BASE.replace(frm, to, 1))
        g = run_gate()
        open(HELPERS, "w").write(BASE)
        moved = [k for k in EXPECTED if g.get(k) != EXPECTED[k]]
        unmoved = [k for k in EXPECTED if g.get(k) == EXPECTED[k]]
        print(f"{name} [{kind}]: moved={len(moved)} UNMOVED={len(unmoved)}")
        if not moved:
            print("   *** MOVED NOTHING -- blind spot, reason required ***")
finally:
    open(HELPERS, "w").write(BASE)
    subprocess.run([sys.executable, "gen_gate.py"], cwd=HERE, capture_output=True)

# rows that a HIGH-WORD-only bug cannot touch: both operands with hi == lo
print()
print("=== the half-swap census, concretely ===")
sentinel_rows = [f"m_{n}" for n, a, b in FIX
                 if halves(a)[0] == halves(a)[1] and halves(b)[0] == halves(b)[1]]
print(f"rows whose BOTH operands have hi==lo: {len(sentinel_rows)}")
for r in sentinel_rows:
    print(f"   {r}={EXPECTED.get(r)}")
print("A fixture set made only of these would answer the same under cross_in_low_word,")
print("which is why the set carries 80 random pairs and the 2**k +/- 1 ladder.")