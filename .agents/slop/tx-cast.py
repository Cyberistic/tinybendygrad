#!/usr/bin/env python3
# tx-cast.py -- which CAST nodes in transcendental.py are PROMOTION casts?
# A promotion cast is one `mixin/elementwise.py`'s `_broadcasted` builds (or one
# `UOp.__init__`'s dtype_from_uop builds on a comparison). Everything else is an
# EXPLICIT `.cast()` in transcendental.py and MUST be ported as a node.
import sys
sys.path.insert(0, '.')
from tinygrad.mixin.dtype import DTypeMixin
from tinygrad.mixin.elementwise import ElementwiseMixin
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
from tinygrad.dtype import dtypes
from tinygrad.codegen.decomp import transcendental as T

INSIDE = [False]
PROMOTED = set()
ARENA = []

_orig = UOpMetaClass.__call__


def hooked(cls, op, src=(), arg=None, tag=None, metadata=None):
    r = _orig(cls, op, src, arg, tag, metadata)
    if not any(r is a for a in ARENA): ARENA.append(r)
    return r


UOpMetaClass.__call__ = hooked

_cast = DTypeMixin.cast


def traced_cast(self, dt):
    if INSIDE[0]: PROMOTED.add(id(self._uop))
    return _cast(self, dt)


DTypeMixin.cast = traced_cast

_bc = ElementwiseMixin._broadcasted


def traced_bc(self, y, reverse=False):
    INSIDE[0] = True
    try: return _bc(self, y, reverse)
    finally: INSIDE[0] = False


ElementwiseMixin._broadcasted = traced_bc


def idx(v):
    for j, u in enumerate(ARENA):
        if u is v: return j
    return -1


def run(nm, f):
    PROMOTED.clear(); ARENA.clear()
    f()
    rows = []
    for i, v in enumerate(ARENA):
        if v.op is not Ops.CAST: continue
        rows.append(f"{i}:{v.src[0].dtype}->{str(v.arg).split('.')[-1]}"
                    f"{'*PROMOTED' if id(v) in PROMOTED else ' explicit'}")
    print(f"n_{nm}={len(ARENA)}")
    for r in rows: print(f"c_{nm}={r}")


def main():
    d = UOp.variable("d", 0.0, 100.0, dtypes.f32)
    x = UOp.variable("x", -1.0, 1.0, dtypes.f32)
    i32 = dtypes.i32
    for nm, f in (
        ("rintk", lambda: T.rintk(d)),
        ("pow2if", lambda: T.pow2if(UOp.const(3, i32), dtypes.f32)),
        ("ilogb", lambda: T.ilogb2k(d)),
        ("ldexp3", lambda: T.ldexp3k(d, UOp.const(-2, dtypes.f32))),
        ("ldexp2", lambda: T.ldexp2k(d, UOp.const(-2, i32))),
        ("frexp", lambda: T.frexp(d)),
        ("cwm", lambda: T.cody_waite_reduction(d)[0]),
        ("phr", lambda: T.payne_hanek_reduction(d)[0]),
        ("sp", lambda: T.sin_poly(d)),
        ("sps", lambda: T.sin_poly_small(x, UOp.const(1, i32))),
        ("spl", lambda: T.sin_poly_large(x, UOp.const(2, i32))),
        ("xsin", lambda: T.xsin(d)),
        ("xexp2", lambda: T.xexp2(d)),
        ("xlog2", lambda: T.xlog2(d)),
        ("xpow", lambda: T.xpow(d, UOp.const(2, dtypes.f32))),
    ):
        run(nm, f)


if __name__ == "__main__":
    main()