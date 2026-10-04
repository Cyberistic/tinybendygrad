#!/usr/bin/env python3
"""f2f-padoracle.py -- CPython side of the arena-size sweep, `dd-bandpad.bend`'s
eighteen fixtures at six `pad` sizes.

IT CALLS CPython. `pad` is `pad PARAMs minted before the fixture's own`, and the port
answers the same rows, so the two lanes are diffable line for line. The print decisions
are borrowed from `dd-bandoracle.py` -- which is the whole point of borrowing them: the
lane that renders is shared, so a disagreement is a disagreement about the GRAPH.

`sys.setrecursionlimit` is raised because `pad = 64` prepends 64 PARAMs and tinygrad's
`ucache` key is a tuple of them.
"""
import struct
import sys

sys.setrecursionlimit(10000)
sys.path.insert(0, '.')

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import dtype as DD

# `dd-bandoracle.py` decisions 1-3, verbatim: delete the promotion CASTs
# `mixin/elementwise.py` inserts, render a CONST as its arena WORD, render a float CONST
# as its F32 bit pattern.
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


FIX = (("w1", dtypes.fp8e4m3, dtypes.float32),
       ("n1", dtypes.float32, dtypes.fp8e4m3),
       ("n2", dtypes.float32, dtypes.fp8e5m2))


def main():
    for pad in (0, 1, 2, 5, 17, 64):
        for nm, fr, to in FIX:
            # THE PAD: `pad` PARAMs interned BEFORE the fixture's own, which is the
            # whole point -- a wrong mask that is an arena INDEX moves by `pad`.
            for k in range(pad):
                UOp.variable(f"pad{k}", 0, dtypes.uint32)
            v = UOp.variable(nm, 0, fr)
            src = v if fr is v.dtype else v.cast(fr)
            ans = DD.f2f(src, fr, to)
            tag = f"{nm}.p{pad}"
            if ans is None:
                print(f"{tag}=refused:unported")
                continue
            c = cone([ans])
            print(f"{tag}={tree(ans)}")
            print(f"{tag}n={len(c)}")
            print(f"{tag}k={eck(c)}")


if __name__ == "__main__":
    main()