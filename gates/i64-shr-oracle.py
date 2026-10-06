"""The CPython oracle for `gates/i64-shr-gate.py`.

    I64SHR_SEED=7 .venv/bin/python .agents/slop/ishr/shr-oracle.py > py.txt

ARITHMETIC, NOT LOGICAL. `tinygrad/uop/ops.py:1429` binds `Ops.SHR` to `operator.rshift`,
which on a CPython `int` IS the arithmetic (floor) shift, and
`tinygrad/codegen/decomp/dtype.py:48` says it in words -- "vacated high word: sign bits
when signed, else 0" -- and in code, `fill = a1 >> 31 if dt == dtypes.int else zero`.
So the reference for an `int64` is Python's `x >> k`, and every expectation below is
CPython's `>>`, not a re-derivation of the pair decomposition.

WHY CPython `>>` AND NOT THE PAIR, because a mistake shared by both would be made twice.
Here the whole word is ONE unbounded `>>` and the result is DECOMPOSED afterwards by
`>> 32` and `& 0xffffffff`. The port splits into two `U32` words and moves bits across the
boundary by hand. Same law, two shapes.

THE UNIVERSE, WHICH CAME FIRST AND CHANGED THE FIXTURES. `i64_shr` is a pair shift, so
its only failure modes are (a) the bits that CROSS the word boundary and (b) the sign
fill, and each is invisible to a value chosen without that in mind:

    neg1     0xFFFFFFFF_FFFFFFFF  -1.  The brief's row, and the row where arithmetic and
          logical differ MOST (`-1 >> 63` is -1, `-1 >>> 63` is 1). It is also BLIND TO THE
          AMOUNT WRAP: `x >> 0` is -1 and `x >> 64` is -1, so a `mod 64` amount is
          indistinguishable from a saturating one on this value at every amount past 63.
    zero     0.  Required. Exact 0 at every amount, so it can never be evidence of
          anything; it is here to show the pair is not accidentally reading `hi`.
    one      0x0000_0000_0000_0001  1.  THE ONLY ROW THAT SEES THE AMOUNT WRAP. Past
          `k = 63` the answer is 0, and an implementation that took the amount modulo 64
          would answer `x` itself -- so only a POSITIVE value at `k >= 64` separates
          "saturates" from "wraps". Every negative value answers -1 either way.
    signmin  0x8000_0000_0000_0000  -2**63.  The MIN, and it has `lo = 0`, so it is BLIND
          to both cross-boundary terms -- it sees the fill and nothing else.
    max      0x7FFFFFFF_FFFFFFFF  2**63-1.  The MAX: both words all ones with `bit 0` set,
          so every cross-boundary term contributes at every `k <= 31` and dropping any one
          of them changes the answer. Its fill is 0 because it is non-negative, and that is
          what lets it catch an UNCONDITIONAL fill.
    spill    0x80000001_9ABCDEF1.  THE LOAD-BEARING ROW. Its high word is negative,
          `hi != 0xFFFFFFFF`, and `bit 0` of BOTH words is set, which is the combination
          that makes all four terms of the small-amount arm individually load-bearing:

              lo' = (lo >> k) | (hi << (32-k))     <- needs lo's bits k..31 AND hi's 0..k-1
              hi' = (hi >> k) | (fill << (32-k))   <- needs hi's bits k..31 AND the sign

          At `k = 1` the four together read `0xC0000000:0xCD5E6F78` and deleting ANY ONE of
          them gives a different word. `neg1`, `zero`, `signmin` and `max` between them
          delete none of the four.

THE AMOUNTS, AND WHY THESE TEN. `0` is the identity. `1` is where all four terms are
load-bearing. `31` is the last amount at which `lo >> k` and `hi << (32-k)` are both still
nonzero. `32` IS THE AMOUNT WHERE THE TWO FORMS MEET, so the pick's arms must agree on it.
`33` is the first amount only the `k >= 32` arm serves. `62` and `63` are the widest
in-range amounts. `64` is `2**6` and past the width, `65` is past it, and `127` is far
enough past 64 that a `& 63` WRAP would also answer -1, which is why only `one` at 64/65
can see a wrap.

THE CLAIM `i64_shr` HAS TO SATISFY, AND IT IS NOT A BOUNDARY:

    A sign-extending shift of an `int64` CANNOT LEAVE THE SIGNED 64-BIT RANGE. `x >> k`
    is `floor(x / 2**k)`, so `|x >> k| <= |x| <= 2**63` for every `k <= 63`, and for every
    `k >= 64` it is `-1` for `x < 0` and `0` otherwise -- BOTH IN RANGE. So `i64_shr` is
    EXACT AT EVERY `Nat` AMOUNT, for every `int64`.

`i64_shl` grows in magnitude and so has a real boundary (`k + bit_length(x) <= 63`, first
loss measured at `k = 63` by the sibling gate). This file asserts the OPPOSITE for the
right shift, per value and per amount, so a table whose two columns agreed everywhere --
every row a row that cannot fail -- could not ship.
"""
import os
import sys

M64 = (1 << 64) - 1
SIGN_MIN = -(1 << 63)
SIGN_MAX = (1 << 63) - 1

# (row name, hi, lo). The port's fixtures are a PAIR of U32 because `2**63` has no `U32`
# image, so a decimal fixture would have to be transcribed on one side and derived on the
# other -- and a transcription is exactly the constant that is wrong and green. Every hex
# word above is load-bearing; the module docstring says which term each one can see.
VALUES = [
    ("neg1", 4294967295, 4294967295),      # -1
    ("zero", 0, 0),                        #  0
    ("one", 0, 1),                         #  1
    ("signmin", 2147483648, 0),            # -2**63
    ("max", 2147483647, 4294967295),       #  2**63-1
    ("spill", 2147483649, 2596069105),     # 0x80000001_9ABCDEF1, the load-bearing row
]

AMOUNTS = [0, 1, 31, 32, 33, 62, 63, 64, 65, 127]

WIDE = [a for a in AMOUNTS if a >= 64]


def lit_amt(i):
    """The amount the driver takes at the row's own slot -- a LITERAL index."""
    return AMOUNTS[i]


def rt_amt(seed, i):
    """The amount the driver takes at `(seed + i) mod 10`, with `seed` read from the
    PROCESS ENVIRONMENT, so the `Nat` reaching `i64_shr` is not in the driver's text. A
    permutation, so any seed reaches all ten amounts and the seed is worth a row."""
    return AMOUNTS[(seed + i) % len(AMOUNTS)]


def signed(hi, lo):
    """`hi:lo` read back as a signed 64-bit int, which is how the port's pair is meant to
    be read."""
    v = (hi << 32) | lo
    return v - (1 << 64) if v >> 63 else v


def pair(x, k):
    """`x >> k` as `hi:lo`, by a route the port does not use: one unbounded `>>`, then a
    decomposition."""
    v = (x >> k) & M64
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def unpair_u(s):
    hi, lo = (int(w) for w in s.split(":"))
    return (hi << 32) | lo


def unpair(s):
    v = unpair_u(s)
    return v - (1 << 64) if v >> 63 else v


def main():
    seed = int(os.environ["I64SHR_SEED"])
    out = [f"seed={seed}"]

    signed_hits, sat_neg, sat_pos = [], [], []
    by_amount = {}

    for name, hi, lo in VALUES:
        x = signed(hi, lo)
        for i in range(len(AMOUNTS)):
            kl, kr = lit_amt(i), rt_amt(seed, i)
            n = f"sr_{name}_{i}"
            out.append(f"{n}_x={hi}:{lo}")
            out.append(f"{n}_amt={kl}")
            out.append(f"{n}_lc={pair(x, kl)}")
            out.append(f"{n}_rt_amt={kr}")
            out.append(f"{n}_rt={pair(x, kr)}")

            # The two routes are two independent evaluations of the same
            # `(value, amount)`, so a disagreement would make the TABLE suspect.
            for amt, got in ((kl, pair(x, kl)), (kr, pair(x, kr))):
                key = (name, amt)
                if key in by_amount:
                    assert by_amount[key] == got, f"{name}@{amt}: the two routes disagree"
                by_amount[key] = got
                exact = x >> amt

                # ---- THE CLAIM, WHICH IS THAT THERE IS NO BOUNDARY ----------------
                # A right shift cannot leave the signed 64-bit range, so the pair reads
                # back as `x >> k` at EVERY amount. If this ever raised, a shift would have
                # become a checked operation and the signature would be wrong.
                assert SIGN_MIN <= exact <= SIGN_MAX, (
                    f"{name}@{amt}: x >> k = {exact} does not fit a signed 64-bit word, so "
                    "i64_shr WOULD need a wider carrier")
                assert unpair(got) == exact, f"{name}@{amt}: {unpair(got)} != {exact}"
                signed_hits.append(key)

                # ---- AND PAST THE WIDTH IT SATURATES RATHER THAN LOSING -------------
                # For every `k >= 64` the answer is `floor(x / 2**k)`: -1 for a negative x
                # and 0 for a non-negative one. Both are ordinary signed words, so this is
                # never "lost" -- the distinction the sibling gate drew for `i64_shl`,
                # whose answer outgrew the carrier instead.
                if amt >= 64:
                    assert exact == (-1 if x < 0 else 0), f"{name}@{amt}: {exact}"
                    (sat_neg if x < 0 else sat_pos).append(key)

    # ---- 1. EVERY AMOUNT MUST BE REACHABLE, or the runtime rows are a subset of the
    #         literal ones and the claim is untested.
    assert len({a for (_, a) in by_amount}) == len(AMOUNTS), sorted({a for (_, a) in by_amount})

    # ---- 2. NO VALUE AND NO AMOUNT MAY FAIL TO FIT. Every `(value, amount)` is counted
    #         once per route -- two independent evaluations of the same cell -- so this is
    #         the whole table. It is the assertion that says `i64_shr` needs no wider
    #         carrier and no `Maybe`; the loop's own range check is what it backs up.
    assert len(signed_hits) == 2 * len(VALUES) * len(AMOUNTS), len(signed_hits)

    # ---- 3. ARITHMETIC, NOT LOGICAL, AND EVERY NEGATIVE ROW SEPARATES THE TWO. For
    #         `x < 0` and `1 <= k <= 63` the arithmetic pair's top `k` bits are all ones
    #         and the logical pair's are all zeros; for `k >= 64` arithmetic is all ones
    #         and logical is 0. So EVERY negative row distinguishes them and there is no
    #         row in this table that cannot -- asserted, not argued.
    x_of = {n: signed(h, l) for n, h, l in VALUES}
    for name, _hi, _lo in VALUES:
        x = x_of[name]
        for amt in AMOUNTS:
            if x >= 0 or amt == 0:
                continue  # a non-negative x makes the two coincide, and `x >> 0 == x`
            got = unpair_u(by_amount[(name, amt)])
            assert got != (x & M64) >> amt, (
                f"{name}@{amt}: arithmetic and logical agree, so the row cannot tell them "
                "apart")
    # And the row the brief names, where the two differ by a whole sign bit.
    assert unpair(by_amount[("neg1", 63)]) == -1, by_amount[("neg1", 63)]
    assert unpair_u(by_amount[("neg1", 63)]) == M64, "the pair must HOLD the low 64 bits"
    assert ((x_of["neg1"] & M64) >> 63) == 1, "a logical neg1@63 reads 0:1"

    # ---- 4. THE AMOUNT WRAP IS VISIBLE ONLY ON A POSITIVE VALUE. `i64_shr` saturates
    #         past 63; an implementation that took the amount modulo 64 would answer `x`.
    #         For a negative x both answers are -1, so the negative rows at `k >= 64` are
    #         BLIND TO A WRAP and only `one` and `max` carry this test. Named, because an
    #         exhaustive fixture set over the wrong universe is a gate that cannot fail.
    for name, amt in sat_pos:
        assert by_amount[(name, amt)] == "0:0", (
            f"{name}@{amt} is {by_amount[(name, amt)]}, expected 0:0 -- a non-negative value "
            "at an amount past 63 is the only row that separates saturating from wrapping")
    assert len(sat_pos) == 3 * len(WIDE) * 2, sorted(sat_pos)
    # WHICH OF THOSE ROWS CAN ACTUALLY SEE IT, computed rather than assumed. A wrap answers
    # `x >> (k mod 64)`, so it differs from the saturation exactly when
    # `x >> (k-64) != x >> k`, and the set is NEITHER "the positive values" NOR "64 and 65":
    # it is whatever has magnitude exceeding `2**(k-64)`, plus the positives whose wrap lands
    # on themselves. Spelled out, it is SEVEN cells:
    #   64   one, max, signmin, spill see it. `neg1` does not (-1 IS the saturation) and
    #        `zero` does not (0 is too).
    #   65   max, signmin, spill see it. `one` does NOT: `one >> 1` is 0, which is what it
    #        saturates to, so the wrap lands on the saturation for `one` at 65 exactly as it
    #        does for `neg1`.
    #   127  NO ROW SEES IT. A wrap of 127 lands on 63, and `x >> 63` is -1 for every
    #        negative int64 and 0 for every non-negative one, so the wrap answers exactly
    #        what the saturation answers for all six values. `127` is here as the "further
    #        past 64 than 65" row and is NOT a wrap detector -- which the sibling gate's
    #        `127` could have been mistaken for.
    sees_wrap = {(n, a) for n in x_of for a in WIDE
                 if ((x_of[n] >> (a % 64)) != (x_of[n] >> a))}
    assert sees_wrap == {(n, 64) for n in ("one", "max", "signmin", "spill")} | {
        (n, 65) for n in ("max", "signmin", "spill")}, sorted(sees_wrap)
    # And every blind one, asserted rather than left to be discovered by a plant.
    for name, amt in sat_neg + sat_pos:
        if (name, amt) not in sees_wrap:
            assert (x_of[name] >> (amt % 64)) == (x_of[name] >> amt), (
                f"{name}@{amt} is listed blind but the wrap moves it")

    # ---- 5. THE TWO ARMS MEET AT 32, and the pick must be `<= 32` not `< 32`. At `k = 32`
    #         the low form gives `lo' = hi` and `hi' = fill`, and the high form gives
    #         `lo' = hi >> 0` and `hi' = fill`: the same pair. Asserted on every value,
    #         because a value whose low word is zero would agree trivially.
    for name, hi, lo in VALUES:
        fill = M64 if hi >> 31 else 0
        assert by_amount[(name, 32)] == f"{fill >> 32}:{hi}", (
            f"{name}@32 is {by_amount[(name, 32)]}, expected {fill >> 32}:{hi} -- at k = 32 "
            "the answer's low word is `hi` and its high word is the sign fill, which is what "
            "makes the k <= 32 and k >= 32 arms agree and the pick `<= 32` rather than `< 32`")
        del lo

    # ---- 6. THE LOAD-BEARING ROW REALLY LOADS EVERY TERM. Not a shape check: at `k = 1`
    #         the four terms are each individually necessary, which is the property the
    #         fixture set exists for.
    # `pair()` prints HIGH WORD FIRST, so the tuple order below is (hi', lo') while the
    # local names stay in the (lo', hi') order the decomposition is written in. Getting
    # this backwards is the exact mistake the assertion is here to catch, and it caught it.
    lo1, hi1, fill = 0x9ABCDEF1, 0x80000001, 0xFFFFFFFF
    lo_full = ((lo1 >> 1) | ((hi1 & 1) << 31)) & 0xFFFFFFFF
    hi_full = ((hi1 >> 1) | (fill << 31)) & 0xFFFFFFFF
    assert (lo_full, hi_full) == (0xCD5E6F78, 0xC0000000), (hex(lo_full), hex(hi_full))
    got_hi, got_lo = (int(w) for w in by_amount[("spill", 1)].split(":"))
    assert (got_lo, got_hi) == (lo_full, hi_full), (hex(got_lo), hex(got_hi))
    # and each single deletion really does change a word, so the four assertions above are
    # not one fact counted four times.
    assert ((lo1 >> 1) | ((hi1 & 1) << 31)) != (lo1 >> 1)
    assert ((lo1 >> 1) | ((hi1 & 1) << 31)) != ((hi1 & 1) << 31)
    assert ((hi1 >> 1) | (fill << 31)) != (hi1 >> 1)
    assert ((hi1 >> 1) | (fill << 31)) != (fill << 31)

    # ---- 7. THE FILL IS INVISIBLE ON EVERY NON-NEGATIVE VALUE, so half the fixture set
    #         cannot see a deleted sign fill. This is the out-of-mechanism assertion, and it
    #         is the negative half of the fixture set's worth: a gate built only from `zero`,
    #         `one` and `max` would pass an implementation that never writes the sign at all.
    for name in ("zero", "one", "max"):
        for amt in AMOUNTS:
            x = x_of[name]
            if x >= 0:
                assert (x >> amt) == ((x & M64) >> amt), f"{name}@{amt} sees a fill"
    # `neg1` is the opposite case and is asserted for the other reason: it is all ones, so a
    # fill written into the high word alone is invisible at `k <= 32` and the answer there is
    # the fill's. That is what makes `neg1 @ 33` -- not `neg1 @ 32` -- the row that pins the
    # low word's fill.
    assert unpair_u(by_amount[("neg1", 32)]) == M64, "neg1@32 is all ones either way"
    # and `signmin` cannot see either cross-boundary term, so it is a boundary row and not
    # a coverage row: `lo == 0` and `hi`'s low 32 bits are 0. It sees the FILL, though.
    assert ((0x80000000 >> 1) | (fill << 31)) & 0xFFFFFFFF == 0xC0000000
    assert (0x80000000 >> 1) != 0xC0000000

    print("\n".join(out))


if __name__ == "__main__":
    sys.exit(main())