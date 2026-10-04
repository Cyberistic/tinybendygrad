#!/usr/bin/env python3
"""f2f-bitcast-oracle.py -- DOES CPYTHON FOLD `v.bitcast(fr)` in `f2f`'s narrowing branch,
and under which receiver dtype? The question item 3 of the brief turns on it.

  f2f-bitcast-oracle.py

dtype.py:115 is
    v = f2f_clamp(v.bitcast(fr), to, sat).bitcast(f2f_dt[fr])
so there are TWO bitcasts on the narrowing path and the brief's item 3 names the FIRST
one -- `f2f.down.has`'s `T.tx_bitcast(ar, v, fr)` -- as "a BITCAST CPython folds".

`mixin/dtype.py:53` folds `bitcast` to `self` iff `self.dtype == dt`. So it folds exactly
when the receiver already has dtype `fr`. And the receiver is `f2f`'s `v`, which BOTH real
call sites hand over ALREADY BITCAST TO A UINT:

    dtype.py:142   f2f(val.bitcast(f2f_dt[to]), to, fr)
    dtype.py:196   f2f(x.bitcast(f2f_dt[ctx[0]]), ctx[0], ctx[1])
    dtype.py:97    f2f_dt = { f: getattr(dtypes, f"uint{f.bitsize}") ... }

`fr` is a FLOAT dtype there and `f2f_dt[fr]` is a UINT of the same width, so
`v.dtype == fr` is FALSE for every reachable call and the fold is UNREACHABLE. This file
measures both directions so the claim is a number and not an argument:

  A. the four-arg receiver (`f2f_dt[fr]`) -- dtype.py's own contract. Reports whether a
     BITCAST appears and the node count.
  B. the three-arg receiver (`UOp.variable(nm, 0, fr)`, dtype `weakint`, then
     `v.cast(fr)`) -- what `.agents/slop/f2f-padoracle.py` builds, and what
     `.agents/slop/dd-bandpad.bend` builds on the port side. Here `v` IS a `fr` after the
     `cast`, so the bitcast FOLDS.

If A shows a BITCAST and B does not, then "CPython folds it" was measured on B, and
landing `dd_bcast` at `f2f.down.has` would REMOVE a node CPython builds.
"""
import struct
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import dtype as DD

PROMO = set()
_CAST = type(UOp.variable("p", 0, 0)).cast


def _cast(self, dtype):
    r = _CAST(self, dtype)
    try:
        caller = sys._getframe(1).f_code.co_name
    except Exception:
        caller = '?'
    if caller in ('promote', 'logical_not') and r.op is Ops.CAST and r is not self:
        PROMO.add(id(r))
    return r


type(UOp.variable("p", 0, 0)).cast = _cast


def uncast(v):
    while v.op is Ops.CAST and id(v) in PROMO:
        v = v.src[0]
    return v


def cone(roots):
    seen, out = set(), set()
    st = list(roots)
    while st:
        v = st.pop()
        v = uncast(v)
        if id(v) in seen:
            continue
        seen.add(id(v))
        out.add(v.op.name)
        st.extend(v.src)
    return out


def f2f_dt_of(fr):
    return getattr(dtypes, f"uint{fr.bitsize}")


# every narrowing pair `f2f` accepts (`fe >= te and fm > tm`), plus one widening pair so the
# control is not accidentally a narrowing-only file.
FIX = (("narrow-e4m3", dtypes.float32, dtypes.fp8e4m3),
       ("narrow-e5m2", dtypes.float32, dtypes.fp8e5m2),
       ("narrow-fnuz", dtypes.float32, dtypes.fp8e5m2fnuz),
       ("wide-f64", dtypes.float32, dtypes.float64))


def build(nm, fr, to, four_arg):
    PROMO.clear()
    if four_arg:
        v = UOp.variable(nm, 0, 0, f2f_dt_of(fr))
        return v
    # THE STALE FIXTURE. `ops.py:1015` is
    #   variable(name, min_val, max_val, dtype=dtypes.weakint, multiple_of=1)
    # so the third positional is `max_val` and the dtype stays `weakint`. The receiver is
    # then `v.cast(fr)` -- a `fr` node -- which is the graph dtype.py never builds.
    v = UOp.variable(nm, 0, fr)
    return v if fr is v.dtype else v.cast(fr)


def main():
    print(f"{'fixture':<14} {'receiver':<22} {'BITCAST in cone?':<17} {'nodes':>6}")
    for nm, fr, to in FIX:
        for four in (True, False):
            src = build(nm, fr, to, four)
            ops = cone([DD.f2f(src, fr, to)])
            tag = "f2f_dt[fr] (4-arg)" if four else "v.cast(fr) (3-arg)"
            n = sum(1 for _ in ops)
            print(f"{nm:<14} {tag:<22} {'BITCAST' if 'BITCAST' in ops else 'FOLDED':<17} {n:>6}")
    print()
    print("The NARROWING rows are the ones item 3 is about. `f2f_dt[fr]` is the receiver")
    print("dtype.py's own two call sites pass; the 3-arg row is what `f2f-padoracle.py` and")
    print("`dd-bandpad.bend` build. A fold that only happens in the 3-arg row is a FIXTURE")
    print("difference, and landing `dd_bcast` for it would delete a node CPython builds.")


if __name__ == "__main__":
    main()
