#!/usr/bin/env python3
"""dd-bandoracle.py -- the CPython side of the `f2f` fixtures in
`.agents/slop/dd-bandprobe.bend`, so the seven `dd_band` MASK sites have an oracle.

IT CALLS CPython. It does not reimplement `f2f`. The two lanes print the same four
fields in the same shapes, borrowed verbatim from `.agents/slop/dd-oracle.py` (its
decisions 1-3: delete `_broadcasted`'s promotion CASTs and `logical_not`'s, render a CONST
as its arena WORD, render a float CONST as its F32 bit pattern, walk the cone in DFS
pre-order). Those are PRINT decisions, and borrowing the print code is what makes the two
lanes diffable; nothing here decides what `f2f` builds.

usage: dd-bandoracle.py            the three fixtures, to stdout
"""
import struct
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.codegen.decomp import dtype as DD

# ---- decision 1 of dd-oracle.py, verbatim: `mixin/elementwise.py` is not ported, so the
# CASTs an operator overload inserts that dtype.py never wrote are deleted HERE AND ONLY
# HERE. Two sites, identified by the PYTHON FUNCTION that called `.cast`.
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


def cval(a):
    v = int(a)
    hi = (v >> 32) & 0xFFFFFFFF
    lo = v & 0xFFFFFFFF
    if hi == 0:
        return f"C({lo})"
    if hi == 0xFFFFFFFF:
        mag = 0 if lo == 0 else 4294967296 - lo
        return f"C(-{mag})"
    return f"C({hi}:{lo})"


def fbits(x):
    return f"F({struct.unpack('I', struct.pack('f', float(x)))[0]})"


def lab(v):
    v = uncast(v)
    if v.op is Ops.CONST:
        if isinstance(v.arg, bool):
            return f"C({int(v.arg)})"
        if isinstance(v.arg, int):
            return cval(v.arg)
        return fbits(v.arg)
    if v.op is Ops.PARAM:
        return f"P{v.arg.name}"
    return v.op.name


def sh1(v):
    v = uncast(v)
    return lab(v) if not v.src else f"{lab(v)}({','.join(lab(s) for s in v.src)})"


def tree(v):
    if v is None:
        return "none"
    v = uncast(v)
    if not v.src:
        return lab(v)
    return f"{lab(v)}({','.join(sh1(s) for s in v.src)})"


def cone(roots):
    seen, out = set(), []

    def go(v):
        v = uncast(v)
        if id(v) in seen:
            return
        seen.add(id(v))
        out.append(v)
        for s in v.src:
            go(s)
    for r in roots:
        go(r)
    return out


def esig(built):
    return ",".join(f"{u.op.name}/{len(u.src)}" for u in built)


def eck(built):
    seen, out = set(), []

    def go(v):
        v = uncast(v)
        if id(v) in seen:
            return
        seen.add(id(v))
        if v.op is Ops.CONST:
            out.append(lab(v))
        for s in v.src:
            go(s)
    for r in built:
        go(r)
    return ",".join(out)


def main():
    # THE THREE FIXTURES, the same three dd-bandprobe.bend builds, in the same order.
    for nm, dt, fr, to in (("w1", dtypes.float, dtypes.fp8e4m3, dtypes.float32),
                           ("n1", dtypes.float, dtypes.float32, dtypes.fp8e4m3),
                           ("n2", dtypes.float, dtypes.float32, dtypes.fp8e5m2)):
        v = UOp.variable(nm, 0, dt)
        if fr is v.dtype:
            src = v
        else:
            src = v.cast(fr)
        ans = DD.f2f(src, fr, to)
        if ans is None:
            print(f"{nm}=refused:unported\n")
            continue
        c = cone([ans])
        print(f"{nm}={tree(ans)}")
        print(f"{nm}n={len(c)}")
        print(f"{nm}sig={esig(c)}")
        print(f"{nm}k={eck(c)}")


if __name__ == "__main__":
    main()