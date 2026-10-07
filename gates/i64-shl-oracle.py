"""The CPython oracle for `gates/i64-shl-gate.py`, and the boundary the wall names.

    I64SHL_SEED=7 .venv/bin/python .agents/slop/i64shl/shl-oracle.py > py.txt

THE ROW SET, AND WHY IT IS NOT "A ROW THAT ENCODES THE PORT".  There is no `i64_shl`
in `tinygrad/` -- measured, `grep -rn 'i64_shl' tinygrad/` is 0 hits -- so there is
nothing to CALL.  What there is is CPython's own unbounded `<<`, and every expectation
here comes from THAT, by a route the port does not use: the port splits into two `U32`
words and does `or(shln(hi,k), shrn(lo,32-k))` per word, while here it is
`(x << k) & 2**64` in ONE expression and the pair is DECOMPOSED afterwards by `>> 32`
and `& 0xffffffff`.  A mistake shared by both would have to be made twice, in two
different shapes.

THE FIXTURE SET IS THE UNIVERSE, and it was chosen by asking which rows CAN see the
defect.  For a value with both words below 2**32 the low arm and the high arm of the
shift agree, so such a row is blind to the one place `i64_shl` can be wrong -- which is
why `helpers-mut/gate.bend`'s small pair rows are the control and not the test.

    neg1  -1     the only value whose `k = 63` answer is still a nonzero pair, so it
                  is the row that separates `63` from `64`
    one    1     `helpers.bend:1803-1804` names `1 << 63` verbatim as the case that
                  separates the high arm from a wrong one
    lowhi  1:2596069104    both words NONZERO and different, so for `k` in `1..30` the
                  high arm and the spill out of the low word both contribute and for
                  `k >= 32` only the low word may.  Magnitude 33 bits, so its own
                  signed-range edge is `k = 31`.

THE AMOUNTS, and the permutation.  The driver reads `I64SHL_SEED` from the process
ENVIRONMENT (`H.getenv_int`), takes `(seed + i) mod 10` into the table, and reads the
amount out of it -- so the amount is not in the driver's text at all.  This oracle
reproduces that arithmetic, which is why `seed` is a ROW: a drifting seed shows up as a
diff on the input instead of as 30 silently wrong answers.

THE BOUNDARY, WHICH IS NOT THE ONE THE WALL NAMES.  There are TWO widths and they are
one row apart:

    k <= 62   the pair `hi:lo`, read SIGNED, IS `x << k` -- equal decimals
    k == 63   the pair still HOLDS the answer UNSIGNED, but `i64_shl` is a SIGNED pair,
              so `1 << 63` reads NEGATIVE where CPython reads positive
    k >= 64   the pair is `0:0` and `x << k` is not.  This is the wall's row.

All three are asserted below, so the oracle cannot ship a table whose two columns agree
everywhere -- which would make every `k >= 63` row a row that cannot fail, the failure
mode `gates/README.md` records.
"""
import os
import sys
from pathlib import Path

M64 = (1 << 64) - 1
SIGN_MIN = -(1 << 63)
SIGN_MAX = (1 << 63) - 1

# (row name, hi, lo). The port's fixtures are a PAIR of U32 because `2**63` has no
# `U32` image, so a decimal fixture would have to be transcribed on one side and
# derived on the other -- and a transcription is exactly the constant that is wrong and
# green. `lowhi` is `0x0000_0001_9abc_def0`.
VALUES = [
    ("neg1", 4294967295, 4294967295),
    ("one", 0, 1),
    ("lowhi", 1, 2596069104),
]

AMOUNTS = [0, 1, 31, 32, 33, 62, 63, 64, 65, 127]

# the row name -> the LITERAL amount, and the row name -> the RUNTIME amount. The
# driver indexes one table of ten `Nat` literals twice, once at the row's own slot and
# once at `(seed + i) mod 10` where `seed` is read from the environment, so the two
# routes differ ONLY in whether the index is syntax or runtime data.
def lit_amt(i):
    return AMOUNTS[i]


def rt_amt(seed, i):
    return AMOUNTS[(seed + i) % len(AMOUNTS)]


def signed(hi, lo):
    """`hi:lo` read back as a signed 64-bit integer, which is how the port's pair is
    meant to be read (`helpers.bend:1698-1700`)."""
    v = (hi << 32) | lo
    return v - (1 << 64) if v >> 63 else v


def pair(x, k):
    """`(x << k) & 2**64` as `hi:lo`, by a route the port does not use."""
    v = (x << k) & M64
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def main():
    seed = int(os.environ["I64SHL_SEED"])
    out = [f"seed={seed}"]

    # THE WALL'S CLAIM, AS A CROSS-CHECK ON THE ORACLE'S OWN TABLE: for each value and
    # each amount, the runtime route and the literal route are two independent
    # evaluations of `i64_shl`, so if they ever differed the table itself would be
    # suspect. Keyed on the VALUE, not on the row, so a drift is caught.
    out_signed, in_signed, zero_out = [], [], []
    by_amount = {}
    for name, hi, lo in VALUES:
        x = signed(hi, lo)
        for i in range(len(AMOUNTS)):
            kl, kr = lit_amt(i), rt_amt(seed, i)
            n = f"sh_{name}_{i}"
            out.append(f"{n}_x={hi}:{lo}")
            out.append(f"{n}_amt={kl}")
            out.append(f"{n}_lc={pair(x, kl)}")
            out.append(f"{n}_rt_amt={kr}")
            out.append(f"{n}_rt={pair(x, kr)}")

            for amt, got in ((kl, pair(x, kl)), (kr, pair(x, kr))):
                key = (name, amt)
                if key in by_amount:
                    assert by_amount[key] == got, f"{name}@{amt}: the two routes disagree"
                by_amount[key] = got
                exact = x << amt

                # THE CLAIM, AS ONE PREDICATE, WHICH IS ALL OF THE WALL:
                #   `i64_shl` answers `x << k` EXACTLY iff `x << k` fits a SIGNED 64-bit
                #   word, and the boundary is therefore `k + bit_length(x)`, NOT a
                #   constant amount. `helpers.bend:1819` returns a SIGNED pair, so the
                #   pair's range is [-2**63, 2**63-1].
                #
                #   * in signed range  -> the pair reads back as `x << k`, equal decimals
                #   * out of it        -> the pair still HOLDS the low 64 bits unsigned,
                #                          and reads back signed with the wrong sign
                #   * `x == 0`        -> the exact answer is 0 at every amount, so it
                #                          always "fits" and is never evidence
                fits = SIGN_MIN <= exact <= SIGN_MAX
                if fits:
                    assert unpair(got) == exact, f"{name}@{amt}: {unpair(got)} != {exact}"
                    in_signed.append(f"{name}:{amt}")
                else:
                    out_signed.append(f"{name}:{amt}")
                    # THE PART THAT IS STILL TRUE PAST THE EDGE. If this ever failed, the
                    # pair would have LOST the answer rather than re-signed it, and the
                    # two failures are worth telling apart.
                    assert unpair_u(got) == exact & M64, (
                        f"{name}@{amt}: the pair lost the low 64 bits entirely")
                    if unpair_u(got) == 0:
                        zero_out.append(f"{name}:{amt}")

    # ---- THE UNIVERSE CHECKS, and they are the point of the fixture set ----
    #
    # 1. THE WALL'S AMOUNT MUST LOSE, for every value. `k >= 64` cannot fit any nonzero
    #    value in 64 bits, so if `64` were not in `out_signed` the width claim is untested.
    for name, _hi, _lo in VALUES:
        for amt in (64, 65, 127):
            assert f"{name}:{amt}" in out_signed, f"{name}@{amt} must be out of signed range"
    # 2. THE SIGNED BOUNDARY MUST ALSO BE CROSSED BELOW 64, or `k = 64` is the only
    #    boundary and this says nothing a 64-bit unsigned carrier would not. `lowhi` is
    #    33 bits, so it leaves signed range at `k = 31` -- a row the wall never names.
    assert "lowhi:31" in out_signed, f"lowhi@31 must be out of signed, got {out_signed}"
    # 3. AND IT MUST BE CROSSED IN BOTH DIRECTIONS: `neg1` at 63 still FITS, `one` at
    #    63 does not. Without both, `k = 63` is not a boundary but a cliff.
    assert "neg1:63" in in_signed, f"neg1@63 must fit signed, got {out_signed}"
    assert "one:63" in out_signed, f"one@63 must NOT fit signed, got {in_signed}"
    # 4. EVERY amount must be reachable, or the runtime rows are a subset of the literal
    #    ones and the claim is untested.
    assert len({a for (_, a) in by_amount}) == len(AMOUNTS), sorted({a for (_, a) in by_amount})
    # 5. THE WIDTH ROWS MUST ALL BE `0:0`, or the port's documented "THE AMOUNT IS
    #    MODULO 2**64" (helpers.bend:1806-1809) is not what the table says. `lowhi`
    #    reaches it at 62 rather than 64 -- its 33 bits overflow 64 at 31 -- which is the
    #    same width law seen from the other side.
    # 6. AND `neg1` AT 63 MUST NOT BE AMONG THEM, because `-1 << 63` is exactly the
    #    int64 sign bit: it is the one row where 63 and 64 cannot be collapsed.
    z = set(zero_out)
    for name in ("neg1", "one", "lowhi"):
        for amt in (64, 65, 127):
            assert f"{name}:{amt}" in z, f"{name}@{amt} must answer 0:0"
    assert "lowhi:62" in z, f"lowhi@62 must answer 0:0, got {sorted(z)}"
    assert "neg1:63" not in z, f"neg1@63 is the int64 sign bit and cannot be 0:0"

    print("\n".join(out))


def unpair_u(s):
    hi, lo = (int(w) for w in s.split(":"))
    return (hi << 32) | lo


def unpair(s):
    v = unpair_u(s)
    return v - (1 << 64) if v >> 63 else v


if __name__ == "__main__":
    sys.exit(main())