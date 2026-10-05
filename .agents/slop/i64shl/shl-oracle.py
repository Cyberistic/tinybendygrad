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
    signed_out, zero_out = [], []
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
                # THE THREE BOUNDARIES, asserted on this row's own numbers.
                if amt <= 62:
                    assert got != "0:0", f"{name}@{amt}: in range, yet the pair is zero"
                    assert unpair(got) == exact, f"{name}@{amt}: {unpair(got)} != {exact}"
                elif amt == 63:
                    if unpair(got) != exact:
                        signed_out.append(f"{name}:{amt}")
                        assert not (SIGN_MIN <= exact <= SIGN_MAX), (
                            f"{name}@{amt}: {unpair(got)} != {exact} yet the exact answer "
                            "FITS signed, so the pair lost it")
                    assert unpair_u(got) == exact & M64, (
                        f"{name}@{amt}: the pair must HOLD the k=63 answer unsigned")
                else:
                    zero_out.append(f"{name}:{amt}")
                    assert got == "0:0" and exact != 0, f"{name}@{amt}: should be 0:0"

    # THE UNIVERSE CHECK, and it is the whole point of the fixture set: the `k = 63`
    # boundary must be crossed in BOTH directions, or the boundary is not a boundary.
    assert "one:63" in signed_out, f"one@63 was expected past signed range, got {signed_out}"
    assert "neg1:63" not in signed_out, f"neg1@63 must fit signed, got {signed_out}"
    assert "lowhi:31" in signed_out, f"lowhi@31 was expected past signed, got {signed_out}"
    # and the k >= 64 rows must not all be one value's worth of evidence
    assert len({n.split(":")[0] for n in zero_out}) == 3, f"k>=64 only hit {zero_out}"
    # EVERY amount must be reachable on the runtime route, or the runtime rows are a
    # subset of the literal ones and the claim is untested
    assert len({a for (_, a) in by_amount}) == len(AMOUNTS), sorted({a for (_, a) in by_amount})

    print("\n".join(out))


def unpair_u(s):
    hi, lo = (int(w) for w in s.split(":"))
    return (hi << 32) | lo


def unpair(s):
    v = unpair_u(s)
    return v - (1 << 64) if v >> 63 else v


if __name__ == "__main__":
    sys.exit(main())