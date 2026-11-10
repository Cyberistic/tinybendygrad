#!/usr/bin/env python3
"""helpers-gap-oracle.py -- THE CPYTHON ORACLE for `helpers-gap.bend`.

    .venv/bin/python .agents/slop/helpers-device-shrink/helpers-gap-oracle.py

**WHAT IT IS.** The expectations for the `tinybendygrad/helpers.bend` defs that
NO EXISTING GATE COVERS -- `i64_mul`, `gcd`, `u64_divmod`, `i64_abs`,
`i64_not`, `i64_neg`, `cdiv_i64`, `cmod_i64`, `floordiv_i32`, `floormod_i32`,
`cdiv_i32`, `cmod_i32`, `ceildiv_i32`, `round_up_i32`, `round_down_i32` and
`next_power2`.

**AND WHERE THE EXPECTATIONS COME FROM.** CPython's OWN arithmetic, and CPython's
OWN `math.gcd`. **AND EVERY 64-BIT ANSWER IS CPython's UNBOUNDED INTEGER
MODULO 2**64** -- because the port's PAIR IS 64 BITS WIDE AND THE WRAP IS THE
WIDTH RATHER THAN A CHOICE.** So `i64_mul` is `(a * b) % 2**64` rendered as a
SIGNED value, and `u64_divmod` is the unsigned quotient and remainder of
`a % 2**64` by `b % 2**64`.

**AND WHY THE ORACLE DOES NOT CALL `tinygrad/helpers.py`.** It could not: the
defs under test do not exist there. `i64_mul` is the port's OWN two's-complement
multiply on a 64-bit pair, and upstream has no such def -- MEASURED,
`grep -rn 'i64_mul' tinygrad/` is 0 hits. What upstream DOES have is
`cdiv(x, y) = abs(x)//abs(y)*(1,-1)[x*y<0] if y != 0 else 0` and
`cmod(x, y) = x-cdiv(x,y)*y` (helpers.py:74-75) and `floordiv` / `floormod`
(:77-78) and `ceildiv` (:66-69) and `round_up` / `round_down` (:70-71) and
`next_power2` (:72) and `math.gcd`. **SO THE 32-BIT AND THE cdiv/cmod ROWS
COMPARE THE PORT AGAINST UPSTREAM'S OWN SPELLING, AND THE 64-BIT ROWS COMPARE
IT AGAINST CPython's UNBOUNDED ARITHMETIC** -- which is the only oracle for a
64-bit value CPython does not have a def for.

**THE 32-BIT ROWS ARE THE INTERESTING ONES**, because a 32-bit signed value
CAN be spelled in CPython and upstream's spelling is exact. `floordiv` FLOORS
and `cdiv` TRUNCATES, and they differ on every negative dividend, and the two
are different FUNCTIONS upstream -- picking the wrong one is a wrong answer,
not a slower right one.

**AND THE FIXTURE SET IS THE UNIVERSE** -- int64.min, -1, 0, 1, 2**62,
2**63-1, 2**32-1 and the pair (1, 2596069104) whose two words are BOTH nonzero
and different -- because those are the values where a sign bit, a truncation
and a wrap disagree. A fixture set of small positive numbers cannot see any of
it.
"""

import math

M64 = 1 << 64
S64 = 1 << 63


def s64(x: int) -> str:
    """**THE PORT's `i64_text`** -- and it is NOT a decimal: helpers.bend says
    so -- "An I64 prints as its two words, so a value never has to leave U32 to
    be read. `hi:lo` rather than a decimal because 2^63 has no U32 image, and a
    dump the oracle can diff line for line is worth more here than a prettier
    one." SO THE ORACLE PRINTS **THE PAIR** AND THE PAIR IS THE COMPARISON, AND
    A SIGNED DECIMAL WOULD BE A DIFFERENT SHAPE THAT COULD HIDE A WORD-SWAP."""
    v = x % M64
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def u64(x: int) -> int:
    """**THE UNSIGNED 64-BIT VALUE** -- the magnitude the port's `u64_divmod`
    divides."""
    return x % M64


def i64_mul(a: int, b: int) -> int:
    """**THE PORT's `i64_mul`**: the two's-complement product, mod 2**64,
    signed."""
    v = (u64(a) * u64(b)) % M64
    if v >= S64:
        v -= M64
    return v


def u64_divmod(a: int, b: int) -> tuple[int, int]:
    """**THE PORT's `u64_divmod`**: the UNSIGNED pair division. **AND THE
    ZERO-DIVISOR ANSWER IS THE DIVIDEND** -- the port's `u64_divmod.of`
    answers the dividend for the remainder when the divisor is zero, and the
    port's prose says so: "the zero divisor answers the DIVIDEND for the
    remainder, by the same rule the unsigned magnitude division uses"."""
    ua, ub = u64(a), u64(b)
    if ub == 0:
        return 0, ua
    return ua // ub, ua % ub


def cdiv(x: int, y: int) -> int:
    """**UPSTREAM'S `cdiv`** -- helpers.py:74, verbatim:
    `abs(x)//abs(y)*(1,-1)[x*y<0] if y != 0 else 0`."""
    if y == 0:
        return 0
    q = abs(x) // abs(y)
    return -q if (x * y < 0) else q


def cmod(x: int, y: int) -> int:
    """**UPSTREAM'S `cmod`** -- helpers.py:75, verbatim: `x-cdiv(x,y)*y`."""
    return x - cdiv(x, y) * y


def floordiv(x: int, y: int) -> int:
    """**UPSTREAM'S `floordiv`** -- helpers.py:77, verbatim: `x//y if y != 0
    else 0`."""
    return x // y if y != 0 else 0


def floormod(x: int, y: int) -> int:
    """**UPSTREAM'S `floormod`** -- helpers.py:78, verbatim: `x-floordiv(x,y)*y`."""
    return x - floordiv(x, y) * y


def ceildiv(num: int, amt: int) -> int:
    """**UPSTREAM'S `ceildiv`** -- helpers.py:66-69. The port's `ceildiv_i32` is
    `-(num // -amt)`, which is upstream's NON-UOp arm verbatim:
    `int(ret) if isinstance((ret:=-(num//-amt)), float) else ret`.

    **AND THE ZERO DIVISOR IS **THE PORT's DOCUMENTED DIVERGENCE**:** upstream
    RAISES `ZeroDivisionError` and the port's `floordiv_i32` GUARDS IT AND
    ANSWERS 0 -- helpers.bend says so: "Python raises ZeroDivisionError for
    x//0; tinygrad guards floordiv and cdiv with `if y != 0 else 0` but NOT
    ceildiv or round_up, which raise. Bend is total, so the guarded reading (0)
    is the one every zero-divisor def here answers." SO THE ORACLE ANSWERS 0
    FOR THE ZERO DIVISOR AND THE ROW IS NAMED `ceil_7_0` SO A READER CAN SEE
    THAT IT IS THE DIVERGENT ONE."""
    if amt == 0:
        return 0
    return -(num // -amt)


def round_up(num: int, amt: int) -> int:
    """**UPSTREAM'S `round_up`** -- helpers.py:70, verbatim: `(num+amt-1)//amt
    * amt`."""
    return (num + amt - 1) // amt * amt


def round_down(num: int, amt: int) -> int:
    """**UPSTREAM'S `round_down`** -- helpers.py:71, verbatim: `-round_up(-num,
    amt)`."""
    return -round_up(-num, amt)


def next_power2(x: int) -> int:
    """**UPSTREAM'S `next_power2`** -- helpers.py:72, verbatim: `1 if x == 0
    else 1 << (x - 1).bit_length()`."""
    return 1 if x == 0 else 1 << (x - 1).bit_length()


# ===========================================================================
# THE FIXTURES -- and they are the SAME numbers the Bend driver uses.
# ===========================================================================

ZERO = 0
ONE = 1
TWO = 2
THREE = 3
FIVE = 5
SEVEN = 7
TEN = 10
TWELVE = 12
HUNDRED = 100
TWO_FIFTY_FIVE = 255
EIGHTEEN = 18
NEG1 = -1
NEG7 = -7
MIN64 = -(1 << 63)
MAX64 = (1 << 63) - 1
P62 = 1 << 62
LOHI = (1 << 32) + 2596069104

# ---- the 32-bit values, as SIGNED integers (the port takes the bit pattern)
I32 = {
    "7": 7, "2": 2, "0": 0, "neg7": -7, "neg2": -2,
    "8": 8, "12": 12, "255": 255, "100": 100, "1000": 1000,
    "256": 256, "257": 257,
}


def rows() -> list[tuple[str, str]]:
    r: list[tuple[str, str]] = []

    # ---- `i64_mul`
    for nm, a, b in [
        ("mul_1_1", ONE, ONE),
        ("mul_2_3", TWO, THREE),
        ("mul_neg1_1", NEG1, ONE),
        ("mul_neg1_neg1", NEG1, NEG1),
        ("mul_min_1", MIN64, ONE),
        ("mul_min_min", MIN64, MIN64),
        ("mul_max_max", MAX64, MAX64),
        ("mul_p62_4", P62, 4),
        ("mul_lohi_lohi", LOHI, LOHI),
        ("mul_0_max", ZERO, MAX64),
        ("mul_neg7_3", NEG7, THREE),
    ]:
        r.append((nm, s64(i64_mul(a, b))))

    # ---- `gcd`: NON-NEGATIVE by guarantee, and `gcd(0,0)` is 0.
    for nm, a, b in [
        ("gcd_12_18", TWELVE, EIGHTEEN),
        ("gcd_18_12", EIGHTEEN, TWELVE),
        ("gcd_0_0", ZERO, ZERO),
        ("gcd_0_5", ZERO, FIVE),
        ("gcd_5_0", FIVE, ZERO),
        ("gcd_neg_neg", -TWELVE, -EIGHTEEN),
        ("gcd_neg_pos", -TWELVE, EIGHTEEN),
        ("gcd_min_min", MIN64, MIN64),
        ("gcd_min_2", MIN64, TWO),
        ("gcd_1_1", ONE, ONE),
        ("gcd_255_10", TWO_FIFTY_FIVE, TEN),
        ("gcd_min_3", MIN64, THREE),
    ]:
        r.append((nm, s64(math.gcd(a, b))))

    # ---- `u64_divmod`
    for nm, a, b in [
        ("udm_100_7", HUNDRED, SEVEN),
        ("udm_100_10", HUNDRED, TEN),
        ("udm_min_1", MIN64, ONE),
        ("udm_max_1", MAX64, ONE),
        ("udm_lohi_255", LOHI, TWO_FIFTY_FIVE),
        ("udm_0_7", ZERO, SEVEN),
        ("udm_100_0", HUNDRED, ZERO),
        ("udm_min_0", MIN64, ZERO),
    ]:
        q, rr = u64_divmod(a, b)
        r.append((nm + "_q", s64(q)))
        r.append((nm + "_r", s64(rr)))

    # ---- `cdiv_i64` / `cmod_i64`: upstream's `cdiv` / `cmod` ON THE PAIR.
    for nm, a, b in [
        ("cdiv_7_2", SEVEN, TWO),
        ("cdiv_neg7_2", NEG7, TWO),
        ("cdiv_neg7_neg2", NEG7, -TWO),
        ("cdiv_7_neg2", SEVEN, -TWO),
        ("cdiv_0_2", ZERO, TWO),
        ("cdiv_7_0", SEVEN, ZERO),
    ]:
        r.append((nm, s64(cdiv(a, b))))
    for nm, a, b in [
        ("cmod_7_2", SEVEN, TWO),
        ("cmod_neg7_2", NEG7, TWO),
        ("cmod_neg7_neg2", NEG7, -TWO),
        ("cmod_7_0", SEVEN, ZERO),
    ]:
        r.append((nm, s64(cmod(a, b))))

    # ---- `i64_abs` / `i64_not` / `i64_neg`.
    r.append(("abs_neg7", s64(abs(NEG7))))
    r.append(("abs_min", s64(abs(MIN64))))
    r.append(("abs_7", s64(abs(SEVEN))))
    r.append(("not_neg1", s64(~NEG1)))
    r.append(("not_0", s64(~ZERO)))
    r.append(("not_7", s64(~SEVEN)))
    r.append(("neg_7", s64(-SEVEN)))
    r.append(("neg_min", s64(-MIN64)))

    # ---- the 32-bit rows: the port's bit pattern rendered as the signed
    # decimal, and CPython's answer rendered the same way.
    for nm, x, y in [
        ("fdiv_7_2", 7, 2),
        ("fdiv_neg7_2", -7, 2),
        ("fdiv_7_neg2", 7, -2),
        ("fdiv_neg7_neg2", -7, -2),
        ("fmod_7_2", 7, 2),
        ("fmod_neg7_2", -7, 2),
        ("fmod_7_neg2", 7, -2),
        ("fmod_neg7_neg2", -7, -2),
        ("cdiv32_7_2", 7, 2),
        ("cdiv32_neg7_2", -7, 2),
        ("cdiv32_7_neg2", 7, -2),
        ("cdiv32_neg7_neg2", -7, -2),
        ("cmod32_7_2", 7, 2),
        ("cmod32_neg7_2", -7, 2),
        ("cmod32_7_neg2", 7, -2),
        ("cmod32_neg7_neg2", -7, -2),
    ]:
        if nm.startswith("fdiv"):
            v = floordiv(x, y)
        elif nm.startswith("fmod"):
            v = floormod(x, y)
        elif nm.startswith("cdiv32"):
            v = cdiv(x, y)
        else:
            v = cmod(x, y)
        r.append((nm, str(v)))

    # ---- `ceildiv_i32` / `round_up_i32` / `round_down_i32`.
    r.append(("ceil_7_2", str(ceildiv(7, 2))))
    r.append(("ceil_neg7_2", str(ceildiv(-7, 2))))
    r.append(("ceil_8_2", str(ceildiv(8, 2))))
    r.append(("ceil_0_2", str(ceildiv(0, 2))))
    r.append(("ceil_7_0", str(ceildiv(7, 0))))
    r.append(("rup_7_2", str(round_up(7, 2))))
    r.append(("rup_neg7_2", str(round_up(-7, 2))))
    r.append(("rup_8_2", str(round_up(8, 2))))
    r.append(("rdown_7_2", str(round_down(7, 2))))
    r.append(("rdown_neg7_2", str(round_down(-7, 2))))
    r.append(("rdown_8_2", str(round_down(8, 2))))

    # ---- `next_power2`.
    for nm, x in [
        ("np2_0", 0), ("np2_1", 1), ("np2_2", 2), ("np2_3", 3), ("np2_4", 4),
        ("np2_5", 5), ("np2_100", 100), ("np2_255", 255), ("np2_256", 256),
        ("np2_257", 257), ("np2_1000", 1000),
    ]:
        r.append((nm, str(next_power2(x))))

    return r


def main() -> int:
    for k, v in rows():
        print(f"{k}={v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
