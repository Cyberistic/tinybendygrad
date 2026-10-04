#!/usr/bin/env python3
"""EXACT f32 rounding for `ulp_probe.bend`, via `fractions.Fraction`.

Why exact and not `struct`: `struct.pack(">f", x)` rounds an f64, which is
DOUBLE-ROUNDING. For a quotient like 3/7 that is normally harmless, but the whole
point of this file is to tell two roundings apart, so the oracle must round the
EXACT rational once. CPython's `fractions` gives the exact value; the rounding
below is then done by integer arithmetic, so nothing is double-rounded.

Reference for the round-half-to-even rule: IEEE 754 binary32.

Run:  python3 .agents/slop/mathlib/expect4.py
"""
import pathlib
from fractions import Fraction

HERE = pathlib.Path(__file__).resolve().parent
P = 24  # binary32 significand precision, explicit bits


def f32_bits(fr: Fraction) -> int:
    """The binary32 bit pattern of an exact rational. Round-half-to-even, once."""
    if fr == 0:
        return 0
    neg = fr < 0
    if neg:
        fr = -fr
    # find e with 2^e <= fr < 2^(e+1)
    e = 0
    while Fraction(2) ** (e + 1) <= fr:
        e += 1
    while fr < Fraction(2) ** e:
        e -= 1
    # scale so the significand is an integer of P bits
    scaled = fr * Fraction(2) ** (P - 1 - e)
    n, d = scaled.numerator, scaled.denominator
    q, r = divmod(n, d)
    if 2 * r > d or (2 * r == d and q % 2 == 1):
        q += 1
    # renormalise on carry
    if q == 2 ** P:
        q //= 2
        e += 1
    frac_bits = q - 2 ** (P - 1)
    bits = ((e + 127) << 23) | frac_bits
    return bits | (1 << 31) if neg else bits


def main() -> int:
    rows = [
        ("3/7 correctly rounded f32", Fraction(3, 7)),
        ("3/7 as the decimal 0.42857143", Fraction("0.42857143")),
        ("3/7 as the decimal 0.42857142857142855", Fraction("0.42857142857142855")),
        ("sqrt(2)/sqrt(pi) is IRRATIONAL -- see below", Fraction(0)),
        # the one-ulp-up neighbours of sqrt2 and sqrt(pi), computed not typed
        ("2.5/1.25", Fraction(5, 2) / Fraction(5, 4)),
        ("6/3", Fraction(6, 3)),
    ]
    lines = []
    for nm, fr in rows:
        if fr == 0:
            lines.append(f"{nm:<48} (needs a real sqrt -- see expect3.py)")
        else:
            lines.append(f"{nm:<48} {f32_bits(fr):08x}")
    text = "\n".join(lines) + "\n"
    (HERE / "expect4.txt").write_text(text)
    print(text, end="")
    print()
    print("FIRST ATTEMPT AT THE DISCRIMINATOR FAILED, and it is worth recording:")
    print("  I picked the decimals 0.42857143 and 0.42857142857142855 expecting")
    print("  them to be ADJACENT f32 neighbours of 3/7. They are not -- both round")
    print("  to 3edb6db7, the same f32 as the exact quotient. So the pair could not")
    print("  have failed, which is agent-core.md's 'a list row whose elements are all")
    print("  equal cannot fail on an ordering bug' in a new costume. Rebuilt below by")
    print("  SEARCHING for literals that actually land on the neighbouring f32s.")
    print()
    a = f32_bits(Fraction(3, 7))
    print(f"  exact 3/7 -> {a:08x}")
    lo, hi = a - 1, a + 1
    print(f"  the two f32 neighbours are {lo:08x} and {hi:08x}")
    print()
    lo_dec = find_decimal_for(lo, Fraction(3, 7), -1)
    hi_dec = find_decimal_for(hi, Fraction(3, 7), +1)
    print("  DECISOR literals, FOUND BY SEARCH (these are what the probe must use):")
    print(f"    rounds to {lo:08x}: {lo_dec}")
    print(f"    rounds to {a:08x}: 3/7 itself")
    print(f"    rounds to {hi:08x}: {hi_dec}")
    out = [
        f"exact_3_7       {a:08x}",
        f"lo_neighbour    {lo:08x}  literal {lo_dec}",
        f"hi_neighbour    {hi:08x}  literal {hi_dec}",
    ]
    (HERE / "expect4.txt").write_text(
        "\n".join(lines) + "\n\n" + "\n".join(out) + "\n")
    return 0


def find_decimal_for(target: int, near: Fraction, sign: int) -> str:
    """A short decimal literal that rounds to the f32 bit pattern `target`.

    Searched, not typed: this is the fix for the discriminator that could not fail.
    """
    from decimal import Decimal, getcontext
    getcontext().prec = 40
    base = Decimal(near.numerator) / Decimal(near.denominator)
    for digits in range(1, 18):
        for delta_sign in (sign, -sign):
            step = Decimal(1).scaleb(-digits) * delta_sign
            for k in range(0, 40):
                cand = base + step * k
                if f32_bits(Fraction(cand)) == target:
                    return f"{cand:.{digits}f}"
    raise SystemExit(f"no decimal found for {target:08x}")


if __name__ == "__main__":
    raise SystemExit(main())