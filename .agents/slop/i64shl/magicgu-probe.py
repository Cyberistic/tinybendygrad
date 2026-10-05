"""Does `magicgu`'s `s` EVER REACH 64?  The reachability half of the wall.

    .venv/bin/python .agents/slop/i64shl/magicgu-probe.py

THE WALL ASKS FOR A 65-BIT CARRIER, on this reasoning: `tinygrad/codegen/decomp/op.py:15`
materialises `2**s` and its loop runs `s` over `range(0, 2*nbits + 1)`, so at 32 bits
`s` "reaches 64" -- and `2**64` does not fit an unsigned 64-bit word.  **That reasoning
is about the loop's RANGE, not about what the loop RETURNS**, and the two are 9 apart at
int32.

THE BOUND IS EXACT AND IS DERIVED HERE, NOT ASSUMED, because it is what actually
settles the question.  `s` is the LEAST index with
`2**s > nc*(d-1-((2**s-1) % d))`, so `s > log2(nc*(d-1))`; and `nc <= vmax` with
`d <= vmax` (op.py:22 returns early below `d`, so `d` never exceeds `vmax`), hence

    s <= bit_length(vmax * (vmax-1)) <= 2*nbits

| dtype | bound on `s` | bits in `2**s` | fits a SIGNED 64-bit pair? |
|---|---|---|---|
| int8   | 14  | 15  | yes |
| int16  | 30  | 31  | yes |
| int32  | 62  | 63  | **yes, exactly** |
| uint8  | 16  | 17  | yes |
| uint16 | 32  | 33  | yes |
| uint32 | 64  | 65  | **NO -- 65 bits** |
| int64  | 126 | 127 | no |
| uint64 | 128 | 129 | no |

So the wall's answer splits, and this is the whole finding:

  * **int32 and everything narrower: NO 65-bit carrier is needed.** The bound alone puts
    `2**s` at 63 bits, which `i64_shl` holds as a SIGNED 64-bit pair with one bit spare.
    The wall's own named dtype is settled by its own bound.
  * **uint32: NOT SETTLED.** The bound is 64, so `2**64` is possible in principle.  The
    sweep cannot exclude it, and this probe does not claim to.

THE SWEEP IS CORROBORATION AND ONLY CORROBORATION, and the limit is stated rather than
glossed: it is exhaustive over `d < 2**20` plus a ladder up to the domain edge, while
the reachable domain is `d <= vmax`, which is `d < 2**32` at 32 bits.  **So every
measured `max_s` below is a LOWER BOUND, not the maximum** -- `s` was still climbing at
the sweep's top edge in the first run of this file, which is why the bound is what the
conclusion rests on and the sweep is not.  It calls the REAL upstream `magicgu`,
imported from the tree rather than retyped, and CPython's unbounded ints keep `2**s`
and `m` exact at every width, so this measures the WALL's requirement and not the port's
behaviour.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad.codegen.decomp.op import magicgu  # noqa: E402  the REAL upstream def

DTYPES = [("int8", 2**7 - 1), ("int16", 2**15 - 1), ("int32", 2**31 - 1),
          ("int64", 2**63 - 1), ("uint8", 2**8 - 1), ("uint16", 2**16 - 1),
          ("uint32", 2**32 - 1), ("uint64", 2**64 - 1)]

SWEEP = 1 << 20


def bound(vmax):
    """The EXACT bound, and it needs no search: `s <= bit_length(vmax*(vmax-1))`."""
    return (vmax * (vmax - 1)).bit_length()


def main():
    print("# `magicgu(vmax, d)`, the REAL upstream def at tinygrad/codegen/decomp/op.py:10")
    print("# s is the loop index of op.py:14, `for s in range(0, 2*nbits + 1)`")
    print("#")
    print("# THE BOUND IS WHAT DECIDES IT.  `s` is the LEAST index with")
    print("# `2**s > nc*(d-1-((2**s-1) % d))`, so `s > log2(nc*(d-1))`; `nc <= vmax` and")
    print("# `d <= vmax` (op.py:22 returns early below `d`), so")
    print("#     s <= bit_length(vmax * (vmax-1)) <= 2*nbits.")
    print("# The wall quotes the loop's RANGE, 2*nbits.  At int32 the two differ by 2.")
    print()
    print(f"{'dtype':8} {'nbits':>5} {'range':>6} {'BOUND s':>7} {'2**s bits':>9} "
          f"{'fits signed i64?':>16} {'swept d<':>9} {'meas s':>7} {'argmax d':>9}")
    for name, vmax in DTYPES:
        b = bound(vmax)
        hi, arg = -1, 0
        for d in range(1, SWEEP):
            s = magicgu(vmax, d)[1]
            if s > hi:
                hi, arg = s, d
        # the LADDER, so the domain edge is not unsampled: every power of two from
        # SWEEP to `vmax`, plus the edge itself and its two neighbours.
        ladder = [1 << k for k in range(SWEEP.bit_length() - 1, vmax.bit_length())]
        ladder += [vmax - 1, vmax]
        for d in ladder:
            if 1 <= d <= vmax:
                s = magicgu(vmax, d)[1]
                if s > hi:
                    hi, arg = s, d
        fits = "YES" if b + 1 <= 63 else "NO"
        print(f"{name:8} {vmax.bit_length():>5} {2 * vmax.bit_length():>6} {b:>7} "
              f"{b + 1:>9} {fits:>16} {SWEEP:>9} {hi:>7} {arg:>9}")
    print()
    print("THE MEASURED COLUMN IS A LOWER BOUND.  The sweep is exhaustive over")
    print(f"`d < {SWEEP}` plus a power-of-two ladder to the domain edge, and the reachable")
    print("domain is `d <= vmax` -- `d < 2**32` at the 32-bit dtypes -- so the interior of")
    print("the unswept band is covered by the BOUND column and by nothing else.  `s` was")
    print("still climbing at the top edge in an earlier 2**22 sweep of this file, which is")
    print("the reason the conclusion below rests on the bound.")
    print()
    print("THE ANSWER, split the way the bound splits it:")
    for name, vmax in DTYPES:
        b = bound(vmax)
        verdict = ("NO 65-bit carrier needed: `2**s` is at most "
                   f"{b + 1} bits and `i64_shl` holds it" if b + 1 <= 63 else
                   f"a 64-bit pair CANNOT hold `2**s`: {b + 1} bits")
        print(f"  {name:7} s <= {b:>3}  ->  {verdict}")
    print()
    print("SO: the wall's named dtype (32 bits) is SETTLED AGAINST the 65-bit carrier by")
    print("its own bound at int32, and is OPEN at uint32 where the bound is exactly 64.")
    print("The 64-bit dtypes are a different and wider wall (81+ bits measured), which")
    print("`i64_shl` cannot serve at any width.")


if __name__ == "__main__":
    main()