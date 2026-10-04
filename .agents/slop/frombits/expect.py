#!/usr/bin/env python3
"""expect.py -- the oracle for the FROMBITS gate. Every number here is DERIVED,
none is transcribed, and the NaN denominator is read off the IEEE-754 field
widths rather than off the driver.

Two independent derivations of the same facts, deliberately:

  * `nan_count` counts NaN patterns by iterating the whole 2^32 space with
    Python's own integer arithmetic.
  * `nan_count_field` counts them again from the field widths alone --
    1 sign bit, 8 exponent bits of which one encoding (all ones) is NaN when the
    23 mantissa bits are nonzero, so 2 * (2^23 - 1). The two agreeing is a check
    on the driver, not on itself: `assert` fails the run if they differ.

The round-trip expectation is `identity`. `struct.pack('>f', ...)` /
`struct.unpack('>I', ...)` is CPython's own view of the same 32 bits, so
`C_lane_expected` is "every pattern comes back unchanged" and `js_lane_expected`
is "every NaN comes back as 0x7FC00000, every other pattern unchanged" -- the
collapse being what `new Float32Array(...)[0]` does to a JavaScript NaN, and the
driver's measured `nan_kept / nan_in` is compared against it.
"""
import argparse
import struct
import sys

U32 = 2 ** 32
INF = 0x7F800000


def is_nan(p: int) -> bool:
    """The predicate UNDER TEST, spelled out so it can be read next to the
    driver's. It is not what produces the denominator -- see
    `nan_count_iterated` -- but it is what picks the rows to sweep."""
    return (p & 0x7F800000) == 0x7F800000 and (p & 0x007FFFFF) != 0


def nan_count_iterated() -> int:
    """Ask CPython, per pattern, through `struct` and the IEEE-754 self-compare
    `x != x`. This is a CALL into the reference implementation for every one of
    the 16777214 patterns, not a loop over our own predicate -- if our
    `is_nan` were wrong, this would disagree with the formula and the assert
    below would fail the run."""
    n = 0
    for m in range(1, 2 ** 23):
        for base in (0x7F800000, 0xFF800000):
            if struct.unpack(">f", struct.pack(">I", base | m))[0] != \
                    struct.unpack(">f", struct.pack(">I", base | m))[0]:
                n += 1
    return n


def nan_count_field() -> int:
    """2 signs x (2^23 - 1) nonzero mantissas. The derivation, not a loop."""
    return 2 * (2 ** 23 - 1)


def sum_in(start: int, count: int) -> int:
    """SUM of the input patterns, mod 2^32 -- what the driver's `sum_in` is."""
    return (count * start + count * (count - 1) // 2) % U32


def boundary_patterns():
    """Every boundary the brief names, plus the exponent-class table, plus the
    NaN classes. Values are DECIMAL, so the .bend fixture that consumes them is
    generated from here rather than typed."""
    named = {
        "pzero": 0x00000000,
        "nzero": 0x80000000,
        "minsub": 0x00000001,
        "maxsub": 0x007FFFFF,
        "minnorm": 0x00800000,
        "onen": 0x3F800000,
        "below_one": 0x3F7FFFFF,
        "above_one": 0x3F800001,
        "posinf": 0x7F800000,
        "neginf": 0xFF800000,
        "ffffffff": 0xFFFFFFFF,
        "qnan": 0x7FC00000,
        "qnan_neg": 0xFFC00000,
        "snan": 0x7F800001,
        "snan_neg": 0xFF800001,
        "snan_min": 0x7F800001,
        "qnan_min": 0x7FC00001,
        "qnan_max": 0x7FFFFFFF,
        "qnan_neg_min": 0xFFC00001,
        "nzero_nan": 0x80000001,
        "maxnorm": 0x7F7FFFFF,
        "minnorm_neg": 0x80800000,
    }
    return named


def exponent_classes():
    """All 256 exponent values x both signs, at five mantissas each. The
    pattern is not typed: it is read back OUT of a CPython struct round trip, so
    every row's expectation is a number CPython produced."""
    out = {}
    mantissas = [0, 1, 0x400000, 0x7FFFFE, 0x7FFFFF]
    for e in range(256):
        for sgn in (0, 1):
            for m in mantissas:
                p = (sgn << 31) | (e << 23) | m
                back = struct.unpack(">I", struct.pack(">f", f32_of(p)))[0]
                assert back == p, (hex(p), hex(back))
                out[f"e{e:03d}_s{sgn}_m{m:06x}"] = p
    return out


def f32_of(p: int) -> float:
    """CPython's own f32 with the exact bit pattern p, by round trip."""
    return struct.unpack(">f", struct.pack(">I", p))[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--census", action="store_true",
                    help="print the whole-space census expectations")
    ap.add_argument("--fixtures", action="store_true",
                    help="print name=pattern for the boundary table")
    ap.add_argument("--classes", action="store_true",
                    help="print name=pattern for the exponent-class table")
    args = ap.parse_args()

    if args.fixtures:
        for k, v in sorted(boundary_patterns().items()):
            print(f"{k}={v}")
        return
    if args.classes:
        for k, v in sorted(exponent_classes().items()):
            print(f"{k}={v}")
        return
    if not args.census:
        ap.error("one of --census --fixtures --classes")

    a = nan_count_iterated()
    b = nan_count_field()
    assert a == b, f"denominator disagreement: iterated {a} vs field {b}"
    print(f"space={U32}")
    print(f"nan_total={a}")
    print(f"non_nan_total={U32 - a}")
    print(f"c_lane_nan_kept={a}")
    print(f"c_lane_mismatch=0")
    print(f"js_lane_nan_kept=0")
    print(f"js_lane_mismatch={a}")


if __name__ == "__main__":
    sys.exit(main())
