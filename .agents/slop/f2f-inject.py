#!/usr/bin/env python3
"""f2f-inject.py -- the CALIBRATION for `f2f-pad.sh`, measured rather than asserted.

`f2f-pad.sh` sweeps six arena sizes. A clean sweep is only worth something if the sweep is
known to catch something, and only if what it catches is stated. So this injects FOUR
defect classes into `f2f`'s narrowing/up region, one per run, and reports for each whether
the sweep's rows move. The claim the sweep licenses is the SMALLEST of the four.

  1. FIXED WRONG INDEX -- `dd_band`'s mask argument replaced by the arena index of a node
     (`O.Found.i(v)`) instead of the value `2**k - 1`. A position-dependent defect: the
     port interns `CONST <slot>`, so prepending `pad` PARAMs moves it by exactly `pad`.
     **This is the one the sweep catches**, and it is the one `dd-band-fix.sh` fixed.

  2. WRONG CONSTANT -- `f2f.mask1` returns `2**k + 1` instead of `2**k - 1`. The right
     KIND of defect, the wrong value. Position-independent, so no sweep catches it.

  3. WRONG OFFSET -- `f2f.mask1` returns `2**k` instead of `2**k - 1`, i.e. the `- 1` is
     dropped. Also position-independent.

  4. STALE ARENA -- `f2f.up` hands `f2f.up.tail` its own pre-`f2f.sign` `+ar` instead of
     `O.Found.ar(nq)`, which is what the file did before Task A. `O.Arena.node` is TOTAL
     and answers the arena bottom out of range, so the tail still PRINTS: a stale arena is
     an arena.

Class 4 is the important one for this unit: it is the defect Task A fixed, and a clean
sweep over a fixed file says nothing about it. The evidence for Task A is the forward
reference (slot 22's src0 = slot 23, which is later than itself) and the CPython cone.

usage: f2f-inject.py CLASS OUT.bend     CLASS in {index,const,offset,stale}
"""
import hashlib
import sys

INJECT = {
    # (old, new) -- each anchored to count exactly 1, asserted.
    "index": [(
        "  +b = dd_band(O.Found.ar(a), O.Found.i(a), f2f.mask1(fe))\n  +c = dd_wk(O.Found.ar(b)",
        "  +b = dd_band(O.Found.ar(a), O.Found.i(a), O.Found.i(a))\n  +c = dd_wk(O.Found.ar(b)",
    )],
    "const": [(
        "def f2f.mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def f2f.mask1(+k: U32) -> U32:\n  U32.add(T.tx_powi32(k), 1)",
    )],
    "offset": [(
        "def f2f.mask1(+k: U32) -> U32:\n  U32.sub(T.tx_powi32(k), 1)",
        "def f2f.mask1(+k: U32) -> U32:\n  T.tx_powi32(k)",
    )],
    "stale": [(
        "  +w = f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), O.Found.ar(nq), ns, sg, ex, nm, nq, fe, fm, te, tm)",
        "  +w = f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), ar, ns, sg, ex, nm, nq, fe, fm, te, tm)",
    )],
}


def main():
    cls, out = sys.argv[1], sys.argv[2]
    src = sys.argv[3] if len(sys.argv) > 3 else "tinybendygrad/codegen/decomp/dtype.bend"
    s = open(src).read()
    for old, new in INJECT[cls]:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f"ANCHOR {n}-BAD for {cls}: {old[:70]!r}")
        s = s.replace(old, new, 1)
    open(out, "w").write(s)
    print(f"{cls} -> {out} md5={hashlib.md5(open(out, 'rb').read()).hexdigest()}")


if __name__ == "__main__":
    main()