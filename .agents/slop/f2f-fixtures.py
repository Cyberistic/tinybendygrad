#!/usr/bin/env python3
"""f2f-fixtures.py -- CPython side of the three `f2f` fixtures, MINIMAL and CALLED.

`dd-bandoracle.py` builds `UOp.variable(nm, 0, dtypes.float).cast(fr)`, which mints a
`CAST` node the port's fixture does not have -- the port's is a bare `PARAM` of dtype `fr`
(`.agents/slop/dd-bandprobe.bend`). Comparing the two lanes then reports a disagreement
that is a FIXTURE difference, not a port bug, and the cone offset by one hides every
later disagreement behind it. So the input here is `UOp.variable(nm, 0, fr)` DIRECTLY,
which is dtype.py's own `f2f(v, fr, to)` contract: `v` is a node of dtype `fr` and
nothing in `f2f` reads anything else about it.

WHAT THIS FIXTURE SET REACHES, per dtype.py:
    w1  fp8e4m3 -> float32   widening, dtype.py:104 `fe <= te and fm < tm`
    n1  float32 -> fp8e4m3   narrowing, dtype.py:115, e4m3 target -> f2f.down.*
    n2  float32 -> fp8e5m2   narrowing, NON-e4m3 target, the only way into f2f.down.m2
    f1  fp8e4m3fnuz -> float32   the fnuz arm of `f2f.up`, dtype.py:108
    f2  float32 -> fp8e5m2fnuz   the fnuz arm of `f2f.down`, dtype.py:123
    x1  float16 -> bfloat16      dtype.py:125 `else: raise NotImplementedError`
    x2  float32 -> float64       the refusal whose `fe > te and fm == tm` half
"""
import struct
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.codegen.decomp import dtype as DD

# `dd-bandoracle.py`'s print decisions, verbatim: drop the promotion CASTs
# `mixin/elementwise.py` inserts, render a CONST as its arena WORD and a float CONST as
# its F32 bit pattern. Borrowed so the lane that RENDERS is shared, which is what makes a
# disagreement about the GRAPH rather than about the printer.
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


FIX = (("w1", dtypes.fp8e4m3, dtypes.float32),
       ("n1", dtypes.float32, dtypes.fp8e4m3),
       ("n2", dtypes.float32, dtypes.fp8e5m2),
       ("f1", dtypes.fp8e4m3fnuz, dtypes.float32),
       ("f2", dtypes.float32, dtypes.fp8e5m2fnuz),
       ("x1", dtypes.float16, dtypes.bfloat16),
       ("x2", dtypes.float32, dtypes.float64))


def main():
    for nm, fr, to in FIX:
        v = UOp.variable(nm, 0, fr)
        try:
            ans = DD.f2f(v, fr, to)
        except NotImplementedError as e:
            # dtype.py:125 is the ONLY refusal `f2f` raises, and it names its own
            # condition. Printing the exception TYPE rather than the message, because the
            # message interpolates the two dtypes and the port's refusal is a tag.
            print(f"{nm}=refused:NotImplementedError")
            print(f"{nm}n=0")
            continue
        c = cone([ans])
        print(f"{nm}={tree(ans)}")
        print(f"{nm}n={len(c)}")
        print(f"{nm}sig={esig(c)}")
        print(f"{nm}k={eck(c)}")


if __name__ == "__main__":
    main()