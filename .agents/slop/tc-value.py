#!/usr/bin/env python3
"""tc-value.py -- the VALUE oracle for transcendental.py.

The coefficient oracle (`tc-audit.py`) captured what tinygrad passes to `polyN`.
This one asks tinygrad for the ANSWER: it builds each expansion with tinygrad's
own function, realises it on the float32 PYTHON device (numpy-backed), and
prints the IEEE-754 binary32 bit pattern of the answer.

  names are `xf_<rule>_<fixture>`; the value is `struct.unpack('<I', ...)`.
  NaN is normalised to 0x7fc00000, which is what numpy, tinygrad's interpreter
  and Bend all produce for 0/0 and for `math.nan`.

NOTHING here restates a formula. Every row is `Tensor(tinygrad_fn(uop)).numpy()`
where `tinygrad_fn` is imported FROM transcendental.py. An oracle that rewrote
the source would agree with a port that misread it; this one cannot.
"""
import sys, struct, math
import numpy as np

sys.path.insert(0, '.')
from tinygrad import Tensor
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp
import tinygrad.codegen.decomp.transcendental as T

F32 = dtypes.float32
CANON_NAN = 0x7fc00000


def bits(x):
  v = np.float32(x)
  if np.isnan(v): return CANON_NAN
  if np.isposinf(v): return 0x7f800000
  if np.isneginf(v): return -0x7f800000 & 0xffffffff
  return struct.unpack('<I', struct.pack('<f', v))[0]


def ibits(x):
  return int(np.uint32(x))


def realize(u, shape=None):
  return Tensor(u).numpy().astype(np.float32).reshape(-1)


def vals(name, xs, fn, cast=None):
  """fn takes a float32 numpy array of UOps and returns UOps (or a tuple)."""
  u = Tensor(list(map(float, xs)), dtype=F32).uop
  r = fn(u)
  r = r if isinstance(r, tuple) else (r,)
  got = [realize(z) for z in r]
  for i, xs_ in enumerate(xs):
    print(f'xf_{name}_{xs_}=' + ','.join(str(bits(v)) for v in got[i]))


def main():
  F32d = F32

  # ---- polyN over sin_poly's own table (:150, :152-156)
  for d in (0.0, 0.5, -0.5, 1.0, -1.0, 1.5707963, 0.25, -0.75):
    vals('sin_poly', [d], lambda u: T.sin_poly(u))
  # ---- trig_poly with the f64 table is NOT reachable on a f32 UOp; the f64
  # window is a declared wall, see the file header.
  for d in (0.0, 0.5, -0.5, 1.0, 1.5707963):
    vals('polyn.sin32', [d], lambda u: T.trig_poly(u, *T_sin32()))

  # ---- rintk (:22-25)
  for d in (0.0, -0.0, 0.4, -0.4, 0.5, -0.5, 2.5, -2.5, 1e7, -1e7):
    print(f'xf_rintk_{d}={ibits(T.rintk(UOp.const(np.float32(d), F32d)).ssg[-1])}')

  # ---- shr / shl (:19-20) on the ONE shape that occurs: integer, by a const
  for x in (1, 2, 255, 256, 0x7fffffff, 0xffffffff):
    print(f'xf_shr_{x}={ibits(T.shr(UOp.const(x, dtypes.uint32), 23))}')
    print(f'xf_shl_{x}={ibits(T.shl(UOp.const(x, dtypes.uint32), 23))}')

  # ---- ilogb2k (:32-37), ldexp2k (:47-50), ldexp3k (:39-45), pow2if (:27-30)
  for d in (0.5, 0.75, 1.0, 1.5, 3.0, 1024.0, 0.0001, 8388608.0):
    print(f'xf_ilogb2k_{d}={ibits(T.ilogb2k(UOp.const(np.float32(d), F32d)).ssg[-1])}')
  for d, e in ((1.0, 3), (1.5, -2), (0.75, 5), (3.0, 0)):
    print(f'xf_ldexp2k_{d}_{e}='
          f'{bits(T.ldexp2k(UOp.const(np.float32(d), F32d), UOp.const(np.int32(e), dtypes.int32)))}')
    print(f'xf_ldexp3k_{d}_{e}='
          f'{bits(T.ldexp3k(UOp.const(np.float32(d), F32d), UOp.const(np.float32(e), F32d)))}')
  for q in (0, 1, -1, 10, -10, 126, -126):
    print(f'xf_pow2if_{q}='
          f'{bits(T.pow2if(UOp.const(np.int32(q), dtypes.int32), F32d))}')

  # ---- frexp (:52-63)
  for v in (0.5, 1.0, 1.5, 3.0, -2.5, 1024.0):
    m, e = T.frexp(UOp.const(np.float32(v), F32d))
    print(f'xf_frexp_{v}={bits(m.ssg[-1])},{ibits(e.ssg[-1])}')

  # ---- cody_waite_reduction (:115-147), the f32 arm
  for d in (0.0, 0.5, 1.0, 1.5707963, 3.0, 30.0, 100.0, -100.0, 39800.0):
    r, q = T.cody_waite_reduction(UOp.const(np.float32(d), F32d))
    print(f'xf_cody_waite_{d}={bits(r.ssg[-1])},{ibits(q.ssg[-1])}')

  # ---- sin_poly_small / sin_poly_large (:160-166)
  for d, q in ((0.5, 0), (0.5, 1), (0.5, 2), (0.5, 3), (0.5, 4), (-0.5, 1),
               (1.0, 2), (1.5707963, 2), (1.5707963, 1)):
    dd = UOp.const(np.float32(d), F32d)
    qq = UOp.const(np.int32(q), dtypes.int32)
    print(f'xf_sps_{d}_{q}={bits(T.sin_poly_small(dd, qq).ssg[-1])}')
    print(f'xf_spl_{d}_{q}={bits(T.sin_poly_large(dd, qq).ssg[-1])}')

  # ---- the whole float32 expansions
  XS = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5707963, 3.1415927, 6.2831855,
        29.999998, 30.0, 30.000002, 39800.0, math.inf, -math.inf, math.nan,
        0.25, 100.0, -100.0]
  vals('xsin_fast', XS, lambda u: T.xsin(u, True))
  vals('xsin_slow_small', [x for x in XS if abs(x) < 30.0 and math.isfinite(x)],
       lambda u: T.xsin(u, False))

  XS2 = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 30.0, 126.99999, 127.0,
         127.99999, 128.0, 128.00001, 200.0, -149.99999, -150.0, -150.00001,
         -200.0, math.inf, -math.inf, math.nan, 100000.0, -100000.0]
  vals('xexp2', XS2, lambda u: T.xexp2(u))

  XS3 = [0.0, -0.0, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 0.5e-4, 0.00009999,
         0.00010001, 1e-30, 3e-40, -1.0, math.inf, -math.inf, math.nan,
         1024.0, 0.25, 8.0]
  vals('xlog2', XS3, lambda u: T.xlog2(u))

  # ---- xpow (:257-265).  base, exponent.
  POWS = [(2.0, 0.5), (4.0, 0.5), (9.0, 0.5), (2.0, 3.0), (2.0, -1.0),
          (-2.0, 3.0), (-2.0, 2.0), (-2.0, 2.5), (-2.0, math.inf),
          (0.0, 0.0), (0.0, 5.0), (math.inf, 0.0), (-1.0, math.inf),
          (1.0, math.inf), (4.0, 0.0), (-4.0, 0.0), (-0.0, 3.0), (-0.0, 2.5),
          (2.0, 0.0), (math.nan, 1.0), (2.0, math.nan), (0.5, 2.0)]
  for b, e in POWS:
    ub = Tensor([np.float32(b)], dtype=F32).uop
    ue = Tensor([np.float32(e)], dtype=F32).uop
    print(f'xf_xpow_{b}_{e}={bits(T.xpow(ub, ue).ssg[-1])}')

  # ---- _lazy_map_numbers (:9-11), one row per arm
  for x in (math.inf, -math.inf, math.nan, 0.0, 1.0, -1.0):
    ux = UOp.const(np.float32(x), F32d)
    r = T._lazy_map_numbers(ux, ux.const_like(0.0), ux.const_like(0.0),
                            ux.const_like(0.0), ux)
    print(f'xf_lazy0_{x}={bits(r.ssg[-1])}')
    r = T._lazy_map_numbers(ux, ux.const_like(7.0), ux.const_like(-7.0),
                            ux.const_like(9.0), ux.const_like(3.0))
    print(f'xf_lazy1_{x}={bits(r.ssg[-1])}')


def T_sin32():
  cap = []
  real = T.polyN
  def spy(d, coeff):
    cap.append(list(coeff)); return d
  T.polyN = spy
  T.sin_poly(UOp.const(0.5, F32))
  T.polyN = real
  return (cap[0], cap[1])


if __name__ == '__main__':
  main()