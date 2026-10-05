"""The CPython oracle for `gates/i64-shl-gate.py`, plus the `magicgu` reachability
measurement that decides whether the 65-bit gap is even reachable.

    .venv/bin/python .agents/slop/i64shl/shl-oracle.py > py.txt

WHAT IS EXPECTED HERE, AND WHY IT IS NOT "A ROW THAT ENCODES THE PORT".

There is no `i64_shl` in `tinygrad/` -- measured: `grep -rn 'i64_shl' tinygrad/` is 0
hits -- so there is nothing to CALL. What there IS is CPython's own unbounded `<<`,
and this oracle derives every expectation from THAT, by a route that is not the
port's: the port splits into two `U32` words and does `or(shln(hi,k), shrn(lo,32-k))`
per word, while here it is `(x << k) & 2**64` in one expression and the pair is then
DECOMPOSED by `>> 32` and `& 0xffffffff`. A shared mistake cannot hide in both.

TWO COLUMNS, AND THE DIFFERENCE BETWEEN THEM IS THE FINDING:

    *_shl   `(x << k) & 2**64`, printed `hi:lo`   -- what a 64-bit PAIR can hold
    *_cpy   `x << k`, printed as a Python int      -- what CPython/upstream holds

For `k <= 63` the two MUST be equal. For `k >= 64` they MUST DIFFER, because `2**64`
does not fit in 64 bits and every `k` past 63 sends the pair to `0:0`. So the
`k in {64,65,127}` rows are not the boring tail: they are the rows that make the
boundary visible, and their inequality is ASSERTED below rather than assumed.

THE `magicgu` MEASUREMENT, which is why this file is more than a table. The wall's
own text asks for `i64_shl` because `tinygrad/codegen/decomp/op.py:15` materialises
`2**s` for `s` up to `2*nbits`, i.e. 64 at 32 bits, and `2**64` does not fit an
unsigned 64-bit word. So: DOES `s` EVER REACH 64?  This calls the REAL upstream
`magicgu` (imported from the tree, not retyped) over every `d` below `2**16` and over
`vmax` at each dtype's maximum, and reports the largest `s` it ever returns. If the
answer is 63 then the 65-bit carrier is unreachable for `magicgu` and the width gap
is real but VACUOUS, which is a different claim from "it is needed".
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad.codegen.decomp.op import magicgu  # noqa: E402  the REAL upstream def

M64 = (1 << 64) - 1
SIGN_MIN = -(1 << 63)
SIGN_MAX = (1 << 63) - 1


def pair(x, k):
    """`(x << k) & 2**64` as `hi:lo`, computed WITHOUT the port's word-wise route."""
    v = (x << k) & M64
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def unpair_unsigned(s):
    """`hi:lo` read back as the UNSIGNED 64-bit word the pair actually is."""
    hi, lo = (int(w) for w in s.split(":"))
    return (hi << 32) | lo


def unpair_signed(s):
    """`hi:lo` read back as a SIGNED 64-bit integer, which is how the port's pair is
    meant to be read (`helpers.bend:1698-1700` prints `hi:lo` because `2**63` has no
    `U32` image)."""
    v = unpair_unsigned(s)
    return v - (1 << 64) if v >> 63 else v


# ---- the fixtures ---------------------------------------------------------
# THE VALUE SET IS CHOSEN SO THE ROWS CAN SEE THE DEFECT, and each is there for a
# measured reason rather than for being a round number.
#
#   neg1  -1. The ONLY value for which the `63` and `64` rows can disagree in the
#          port's favour: `-1 << k` is `-1` for every `k` in `0..63`, so the pair is
#          nonzero right up to the boundary and drops to `0:0` exactly at 64. A
#          fixture set without it makes 63 and 64 look like the same row.
#   one    1. `helpers.bend:1803-1804` names this exact case: "Reading `hi` there
#          drops the low word entirely and answers 0 for `1 << 63`". So `one` is the
#          row that separates the high arm from a wrong one.
#   both   0x12345678_9abcdef0. Both words nonzero AND different, so for every `k`
#          in `1..31` BOTH the high arm and the spill out of the low word contribute,
#          and for `k >= 32` only the low word may. A set of all-small values cannot
#          tell those two arms apart -- which is why `helpers-mut/gate.bend`'s small
#          pair rows are the control and not the test.
VALUES = [("neg1", -1), ("one", 1), ("both", 0x123456789ABCDEF0)]

# THE AMOUNTS, and each is a boundary rather than a sample:
#   0   identity, and one of the two amounts where the low form and the high form
#       MEET (`helpers.bend:1797-1799`), so the pick's two arms must agree here
#   1   the only amount where both the high arm and a low-word spill are nonzero
#   31  the last amount the `U32.shln` saturation does not eat (`shln` is 0 past 31)
#   32  the OTHER meeting amount, and the boundary of `k <= 32` vs `k > 32`
#   33  the first amount served by the high arm
#   62  one below the widest in-range amount
#   63  the widest amount a 64-bit shift can express: `1 << 63` is the top bit
#   64  `2**64`. THE WALL'S AMOUNT.  CPython holds it; a 64-bit pair cannot.
#   65  past the width, where the pair is `0:0` and the divergence is total
#   127 0x7f, the largest amount below the `Nat` cap a `U32` can carry, and far
#       enough past 64 that a `& 31`/`& 63` clamp would ALSO answer 0 -- so this
#       row separates "wraps to zero" from "clamps to a bit width", which `64` and
#       `65` alone cannot tell apart from each other.
AMOUNTS = [0, 1, 31, 32, 33, 62, 63, 64, 65, 127]


def main():
    out = []
    for vname, x in VALUES:
        for k in AMOUNTS:
            n = f"sh_{vname}_k{k}"
            out.append(f"{n}_x={pair(x, 0)}")
            out.append(f"{n}_amt={k}")
            out.append(f"{n}_shl={pair(x, k)}")
            out.append(f"{n}_cpy={x << k}")
    # ---- THE THREE BOUNDARIES, asserted on the ORACLE's own numbers ----
    #
    # THE CLAIM IS NOT "WRAPS AT 64". There are TWO widths and they are one row apart,
    # and the FIRST is the one the wall does not name:
    #
    #   1. k <= 62  the pair `hi:lo`, read SIGNED, IS `x << k`. Equal decimals.
    #   2. k == 63  the pair still HOLDS the answer UNSIGNED, but the exact answer
    #               `x << 63` no longer fits a SIGNED 64-bit word whenever `x` is
    #               positive, so the pair reads NEGATIVE where CPython reads positive.
    #               `one` at 63 is that row: CPython `9223372036854775808`, pair
    #               `-9223372036854775808`. `i64_shl` is a SIGNED pair, so its range
    #               is [-2**63, 2**63-1] and `1 << 63` -- the int64 sign bit -- is
    #               OUT OF IT. That is one row BEFORE the wall's 64 and it is the one
    #               that a signed carrier hits first.
    #   3. k >= 64  the pair is `0:0` and `x << k` is not. This is the wall's row.
    #
    # All three are asserted, so the oracle cannot ship a table whose two columns agree
    # everywhere -- which would make every `k >= 63` row a row that cannot fail, the
    # failure mode `gates/README.md` records.
    signed_out = []
    for vname, x in VALUES:
        for k in AMOUNTS:
            s64 = unpair_signed(pair(x, k))
            exact = x << k
            if k <= 62:
                assert s64 == exact, f"{vname} k={k}: {s64} != {exact}"
                assert pair(x, k) != "0:0", f"{vname} k={k}: in range, yet the pair is zero"
            elif k == 63:
                if s64 != exact:
                    signed_out.append(f"{vname}:{k}")
                    assert not (SIGN_MIN <= exact <= SIGN_MAX), (
                        f"{vname} k=63: {s64} != {exact} but the exact answer FITS signed, "
                        "so the pair lost it")
                # the pair always HOLDS the k=63 answer UNSIGNED -- that is the row
                # separating this boundary from the k>=64 one
                assert unpair_unsigned(pair(x, k)) == exact & M64
            else:
                assert s64 == 0 and exact != 0, f"{vname} k={k}: the pair should be 0:0"
        assert pair(x, 0) != pair(x, 1) or x == 0, f"{vname}: k=0 and k=1 must differ"
    # `one` at 63 MUST be out of signed range and `neg1` at 63 MUST be in it, so the
    # k=63 boundary is on both sides of the sign and is not one direction only.
    assert "one:63" in signed_out, f"one@63 was expected to overflow signed, got {signed_out}"
    assert "neg1:63" not in signed_out, f"neg1@63 must fit signed, got {signed_out}"

    # ---- `magicgu`: DOES `s` EVER REACH 64? --------------------------------
    # This is the reachability half. `magicgu(vmax, d)` returns the smallest `s`
    # with `2**s > nc*(d - 1 - (2**s-1) % d)` and `nc <= vmax`, so `s` can only reach
    # 64 when `vmax*(d-1) >= 2**63`. Exhaustive over every `d < 2**16` for the widest
    # `vmax` of each dtype boundary, which is the configuration that maximises `s`.
    worst = {}
    for name, vmax in (("int32", 2**31 - 1), ("uint32", 2**32 - 1),
                       ("int64", 2**63 - 1), ("uint64", 2**64 - 1)):
        hi = 0
        arg = None
        for d in range(1, 1 << 16):
            m, s = magicgu(vmax, d)
            if s > hi:
                hi, arg = s, (vmax, d)
        worst[name] = (hi, arg)
    for name, (hi, arg) in worst.items():
        out.append(f"mg_{name}_maxs={hi}")
        out.append(f"mg_{name}_at={arg[1]}")
    out.append(f"mg_s_eq_64={int(worst['int32'][0] == 64 or worst['uint32'][0] == 64)}")

    print("\n".join(out))


if __name__ == "__main__":
    main()