#!/usr/bin/env python3
# dd-divE-probe.py -- MEASURE what CPython's dtype.py:131 actually mints for
# `f2f_clamp`'s `mx`, for each of dd-oracle.py's CLAMP_DTS, by CALLING
# `DD.f2f_clamp` and reading the CONST out of the result. Nothing here
# reimplements dtype.py:128-131; `clamp_mx` in dd-oracle.py does, and that is
# the difference this probe exists to measure.
#
# The question dd-oracle.py's `c{i}` rows ask is:
#     "what is `clamp_mx(dt)` -- a BARE PYTHON FLOAT -- as f32 bits?"
# The question upstream answers is:
#     "what CONST does `val.const_like(mx)` mint, at `val`'s dtype?"
# Those differ whenever `mx` is outside f32's range (dt == float64), because
# `const_like` truncates to `val.dtype` and `fbits` raises instead.
import struct
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp
from tinygrad.codegen.decomp import dtype as DD

CLAMP_DTS = [dtypes.fp8e4m3, dtypes.fp8e4m3fnuz, dtypes.fp8e5m2, dtypes.fp8e5m2fnuz,
             dtypes.float16, dtypes.bfloat16, dtypes.float32, dtypes.float64]


def f32(x):
    try:
        return struct.unpack('I', struct.pack('f', float(x)))[0]
    except OverflowError:
        return None


def f64(x):
    return struct.unpack('Q', struct.pack('d', float(x)))[0]


def consts(node):
    seen, out = set(), []

    def go(v):
        if id(v) in seen: return
        seen.add(id(v))
        if v.op.name == 'CONST': out.append(v)
        for s in v.src: go(s)
    go(node)
    return out


def main():
    # ONE f32 word: `f2f_clamp`'s `mx`/`sat` are minted with `val.const_like`,
    # so their dtype is `val.dtype`, and f32 is the widest float dtype whose
    # `const_like` CPython can do without a narrowing conversion in the way.
    v32 = UOp.variable("v", 0, 0, dtypes.float32)
    v64 = UOp.variable("w", 0, 0, dtypes.float64)
    for i, dt in enumerate(CLAMP_DTS):
        for tag, v in (("f32src", v32), ("f64src", v64)):
            r = DD.f2f_clamp(v, dt, True)
            cs = consts(r)
            mx = cs[0].arg if len(cs) > 0 else None
            sat = cs[1].arg if len(cs) > 1 else None
            b32 = f32(mx) if mx is not None else None
            print(f"c{i}={dt.name} src={tag} mxval={mx!r} mxdt={cs[0].dtype.name if cs else '-'} "
                  f"mxf32={b32 if b32 is not None else 'ovf'} mxf64={f64(mx) if mx is not None else '-'} "
                  f"sat={sat!r} n={len(cs)}")


if __name__ == "__main__":
    main()