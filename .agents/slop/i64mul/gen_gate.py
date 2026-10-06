#!/usr/bin/env python3
"""i64_mul gate generator. Emits gate.bend (fixtures) and expected.txt (CPython).

NO EXPECTATION IS TYPED BY HAND. Every row's expected `hi:lo` is computed here by
calling CPython, and every fixture is emitted as a pair of U32 literals.
"""
import sys, os, random

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
from tinygrad.helpers import cdiv, cmod, floordiv, floormod  # noqa: E402

W = 1 << 64
S = 1 << 63
def w(v):
    v &= W - 1
    return f"{v >> 32}:{v & 0xFFFFFFFF}"
def sgn(v):
    v &= W - 1
    return v - W if v >= S else v

# ---- fixtures --------------------------------------------------------------
M = 1 << 32
FIX = []
def add(name, a, b):
    assert -(1 << 63) <= a < (1 << 63) and -(1 << 63) <= b < (1 << 63), (name, a, b)
    assert 0 <= (a & (W - 1)) >> 32 <= M - 1 and 0 <= (a & (W - 1)) & (M - 1) <= M - 1
    FIX.append((name, a, b))

add("f_min_min", -S, -S)              # both signs of int64.min
add("f_min_max", -S, S - 1)
add("f_max_min", S - 1, -S)
add("f_max_max", S - 1, S - 1)
add("f_min_one", -S, 1)
add("f_min_neg1", -S, -1)
add("f_max_one", S - 1, 1)
add("f_max_neg1", S - 1, -1)
add("f_zero_zero", 0, 0)
add("f_zero_one", 0, 1)
add("f_one_zero", 1, 0)
add("f_zero_min", 0, -S)
add("f_zero_max", 0, S - 1)
add("f_one_one", 1, 1)
add("f_one_neg1", 1, -1)
add("f_neg1_one", -1, 1)
add("f_neg1_neg1", -1, -1)
add("f_neg1_min", -1, -S)             # the -x that does not exist for int64.min
add("f_min_neg1_of_min", -S, -1)
for k in (0, 1, 2, 8, 15, 16, 17, 31, 32, 33, 62, 63):
    for d in (-1, 0, 1):
        v = (1 << k) + d
        if -(1 << 63) <= v < (1 << 63):
            add(f"f_pow{k}_{'m' if d < 0 else ('p' if d > 0 else 'z')}", v, v)
            add(f"f_pow{k}_{'m' if d < 0 else ('p' if d > 0 else 'z')}_x3", v, 3)
            add(f"f_pow{k}_{'m' if d < 0 else ('p' if d > 0 else 'z')}_xm3", v, -3)
# products that CARRY OUT OF BIT 63 (magnitude > 2**63, so the exact answer does
# not fit an i64 and the wrap is the whole question)
CARRY = [
    ("f_carry_2p62x4", 1 << 62, 4),
    ("f_carry_2p62x2", 1 << 62, 2),
    # NOTE 2**63 is NOT a representable i64, so "magnitude 2**63" is only
    # reachable as int64.min, whose PAIR is 2**63. f_min_x* covers it.
    ("f_carry_minx2", -S, 2),
    ("f_carry_minx3", -S, 3),
    ("f_carry_ffff_ffff", M - 1, M - 1),
    ("f_carry_2p32sq", 1 << 32, 1 << 32),
    ("f_carry_2p32x2p33", 1 << 32, 1 << 33),
    ("f_carry_minxmin_1", -S, -S - 0),
    ("f_carry_2p62xm4", 1 << 62, -4),
    ("f_carry_3p62", (1 << 62) + (1 << 62) // 3 * 2, 3),
    ("f_carry_2p40sq", 1 << 40, 1 << 40),
    ("f_carry_2p48sq", 1 << 48, 1 << 48),
    ("f_carry_2p31sq_x3", 1 << 31, (1 << 31) * 3),
    ("f_carry_neg_carry", -(1 << 62), -4),
]
for nm, a, b in CARRY:
    add(nm, a, b)
# neighbours of the extremes (a saturated magnitude is the interesting case)
for nm, a, b in [("f_maxm1_min", S - 2, -S), ("f_maxm1_one", S - 2, 1),
                 ("f_minp1_min", -S + 1, -S), ("f_minp1_max", -S + 1, S - 1),
                 ("f_max_negmax", S - 1, -(S - 1)), ("f_min_neg2", -S, -2)]:
    add(nm, a, b)

random.seed(20261004)
for i in range(60):
    add(f"f_rnd{i}", random.randrange(-S, S), random.randrange(-S, S))
for i in range(20):
    add(f"f_rndbig{i}", random.randrange(-S, S), random.randrange(1 << 20, S))

# ---- expected, from CPython ------------------------------------------------
def wrap(a, b):
    ua, ub = a & (W - 1), b & (W - 1)
    return (ua * ub) % W
def signed_wrap(a, b):
    return sgn(sgn(a) * sgn(b))

EXP = []
for nm, a, b in FIX:
    ua, ub = a & (W - 1), b & (W - 1)
    EXP.append(f"m_{nm}={w(wrap(a, b))}")
    EXP.append(f"s_{nm}={w(signed_wrap(a, b))}")

# ---- the .bend -------------------------------------------------------------
OUT = os.path.dirname(os.path.abspath(__file__))
HEADER = open(os.path.join(OUT, "hdr.bend")).read()

rows = []
for nm, a, b in FIX:
    ah, al = (a & (W - 1)) >> 32, (a & (W - 1)) & (M - 1)
    bh, bl = (b & (W - 1)) >> 32, (b & (W - 1)) & (M - 1)
    rows.append(f'    mrow("{nm}", {ah}, {al}, {bh}, {bl})')
    rows.append(f'    srow("{nm}", {ah}, {al}, {bh}, {bl})')

MAIN = "\n".join([
    "def mrow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):",
    "  IO.print(String.concat([\"m_\", nm, \"=\", H.i64_text(H.u64_mul(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))",
    "",
    "def srow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):",
    "  IO.print(String.concat([\"s_\", nm, \"=\", H.i64_text(H.i64_mul(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))",
    "",
    "def main() -> IO(Unit):",
    "  do IO<Unit>:",
    *rows,
    "",
])
open(os.path.join(OUT, "gate.bend"), "w").write(HEADER + MAIN)
open(os.path.join(OUT, "expected.txt"), "w").write("\n".join(EXP) + "\n")
print(f"fixtures={len(FIX)} rows_expected={len(EXP)}")