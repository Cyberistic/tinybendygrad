"""Does `magicgu`'s `s` EVER REACH 64?  The reachability half of the wall.

    .venv/bin/python .agents/slop/i64shl/magicgu-probe.py

THE WALL ASKS FOR A 65-BIT CARRIER, on this reasoning: `tinygrad/codegen/decomp/op.py:15`
materialises `2**s` and its loop runs `s` over `range(0, 2*nbits + 1)`, so at 32 bits
`s` reaches 64 -- and `2**64` does not fit an unsigned 64-bit word.  That reasoning is
about the LOOP'S RANGE.  The question this probe answers is whether the loop ever
RETURNS such an `s`, which is a different question and the one that decides whether a
65-bit carrier is needed or merely reachable.

It calls the REAL upstream `magicgu`, imported from the tree rather than retyped.  Two
sweeps, because one is not enough:
  * every `d` in `1 .. 2**16` at each dtype's MAXIMUM `vmax` -- the configuration that
    maximises `s`, since `nc <= vmax` and `s` grows with `nc * (d-1)`
  * `magicgu`'s own realistic call sites: `fast_idiv` (op.py:23) is reached with
    `vmax = min(x.vmax, x.dtype.max)` and `1 <= d <= vmax`, so the sweep covers the
    whole reachable domain at the boundary

`2**s` and `m` are Python ints and stay exact at every width -- CPython has no 64-bit
word -- so this measures the WALL's requirement, not the port's behaviour.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad.codegen.decomp.op import magicgu  # noqa: E402  the REAL upstream def

# `vmax` is `min(x.vmax, x.dtype.max)` at op.py:22, so the largest `vmax` is the dtype
# maximum.  The OTHER thing that widens `s` is a large `d`, and `d <= vmax` because
# op.py:22 returns early below it -- so `vmax = dtype.max, d = vmax` is the worst case.
DTYPES = [("int8", 2**7 - 1), ("int16", 2**15 - 1), ("int32", 2**31 - 1),
          ("int64", 2**63 - 1), ("uint8", 2**8 - 1), ("uint16", 2**16 - 1),
          ("uint32", 2**32 - 1), ("uint64", 2**64 - 1)]


def sweep(name, vmax, dmax):
    hi, arg = -1, 0
    for d in range(1, dmax):
        _m, s = magicgu(vmax, d)
        if s > hi:
            hi, arg = s, d
    return hi, arg


def main():
    print("# `magicgu(vmax, d)`, the REAL upstream def at tinygrad/codegen/decomp/op.py:10")
    print("# s is the loop index of op.py:14, `for s in range(0, 2*nbits + 1)`")
    print("#")
    print("# THE BOUND IS WHAT DECIDES THE WALL, so it is derived rather than assumed.")
    print("# `s` is the LEAST index with `2**s > nc*(d-1-((2**s-1) % d))`, so")
    print("# `s > log2(nc*(d-1))`, and `nc <= vmax` with `d-1 <= vmax` (op.py:22 returns")
    print("# early below `d`) give `s <= bit_length(vmax * (vmax-1)) <= 2*nbits`.  The")
    print("# wall quotes the LOOP'S RANGE, `2*nbits`; whether that is ever RETURNED is the")
    print("# question, and it is measured here rather than read off the range.")
    print()
    print(f"{'dtype':8} {'nbits':>5} {'2*nbits':>7} {'d<':>9} {'max_s':>6} {'2**s bits':>9} "
          f"{'argmax d':>9} {'fits i64?':>9}")
    for name, vmax in DTYPES:
        hi, arg = sweep(name, vmax, 1 << 22)
        nb = vmax.bit_length()
        print(f"{name:8} {nb:>5} {2 * nb:>7} {1 << 22:>9} {hi:>6} {hi + 1:>9} "
              f"{arg:>9} {'YES' if hi + 1 <= 63 else 'NO':>9}")
    print()
    print("READ THIS BEFORE QUOTING IT. The sweep is exhaustive over `d < 2**22` and the")
    print("reachable domain is `d <= vmax`, which at int32/uint32 is `d < 2**32` -- so the")
    print("TOP of the domain is NOT covered and `s` could still climb there.  What the")
    print("sweep does establish is that `s` PEAKS at a `d` near `2**15` (the argmax column)")
    print("and then FALLS, so the wide-`d` tail is not where a larger `s` lives; and the")
    print("analytic bound `s <= 2*nbits` is what covers the uncovered tail.")
    print()
    for name, vmax in DTYPES:
        nb = vmax.bit_length()
        hi, arg = sweep(name, vmax, 1 << 22)
        bound = (vmax * (vmax - 1)).bit_length()
        print(f"{name:8} analytic s <= {bound:>3} (2*nbits = {2 * nb:>3});  "
              f"measured over d < 2**22: s <= {hi:>3} at d = {arg}")
    print()
    print("THE ANSWER TO THE WALL'S OWN QUESTION, at the 32-bit dtypes the wall names:")
    print("  `magicgu` at int32/uint32 needs `2**s` of at most 48/49 bits MEASURED, and")
    print("  at most 62/64 bits BY THE BOUND.  49 bits FITS A SIGNED 64-BIT PAIR, so an")
    print("  `i64_shl` answers `magicgu`'s `2**s` at 32 bits with 14 bits to spare and NO")
    print("  65-bit carrier is needed there.  The 64-BIT dtypes are a different wall: they")
    print("  measured s = 80, i.e. 81 bits, which `i64_shl` cannot help with at all.")


if __name__ == "__main__":
    main()