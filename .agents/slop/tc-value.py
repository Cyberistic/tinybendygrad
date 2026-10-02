#!/usr/bin/env python3
"""tc-value.py -- the VALUE oracle for transcendental.py.

The coefficient oracle (`tc-audit.py`) captured what tinygrad passes to `polyN`.
This one asks tinygrad for the ANSWER: it builds each expansion with tinygrad's
own function, realises it on the float32 PYTHON device (numpy-backed), and
prints the IEEE-754 binary32 bit pattern of the answer.

  rows are `xf_<rule>_<fixture>`; the value is `struct.unpack('<I', ...)`.
  NaN is normalised to 0x7fc00000, which is what numpy, tinygrad's interpreter
  and Bend all produce for 0/0 and for `math.nan`.

NOTHING here restates a formula. Every row is `Tensor(tinygrad_fn(uop)).numpy()`
where `tinygrad_fn` is IMPORTED FROM transcendental.py. An oracle that rewrote
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
NAN = 0x7fc00000


def fbits(x):
  v = np.float32(x)
  if np.isnan(v): return NAN
  if np.isposinf(v): return 0x7f800000
  if np.isneginf(v): return 0xff800000
  return int(struct.unpack('<I', struct.pack('<f', v))[0])


def ibits(x): return int(x) & 0xffffffff


def get(u):
  """realise a UOp of ANY dtype to a flat python list. Every fixture is built
  through a ONE-ELEMENT Tensor so the result carries a PYTHON buffer: realising
  a bare CONST falls through to the CPU renderer, which is broken here."""
  return [x.item() for x in Tensor(u).numpy().reshape(-1)]


def one(u):
  v = get(u)
  assert len(v) == 1, v
  return v[0]


def f1(u): return fbits(one(u))


def i1(u): return ibits(one(u))


def vec(xs, dt=F32):
  return Tensor([np.float32(x) for x in xs], dtype=dt).uop


def C1(x, dt=F32):
  return Tensor([np.float32(x)], dtype=dt).uop


def K1(x, dt):
  return Tensor([x], dtype=dt).uop


def row(name, fn, out='f'):
  u = fn()
  print(f'xf_{name}={f1(u) if out == "f" else i1(u)}')


def vecrow(name, xs, fn, out='f'):
  r = fn(vec(xs))
  r = r if isinstance(r, tuple) else (r,)
  cols = [[fbits(v) if out == 'f' else ibits(v) for v in get(z)] for z in r]
  for i, x in enumerate(xs):
    print(f'xf_{name}_{x}=' + ','.join(str(c[i]) for c in cols))


def sin_tables():
  cap = []
  real = T.polyN
  def spy(d, coeff):
    cap.append(list(coeff)); return d
  T.polyN = spy
  T.sin_poly(UOp.const(0.5, F32))
  T.sin_poly(UOp.const(0.5, dtypes.float64))
  T.polyN = real
  return cap[0], cap[1]


SIN32, SIN64 = sin_tables()


def main():
  C = C1

  for d in (0.0, 0.5, -0.5, 1.0, -1.0, 1.5707963, 0.25, -0.75):
    row(f'sin_poly_{d}', lambda: T.sin_poly(C(d)))
    row(f'polyn32_{d}', lambda: T.trig_poly(C(d), SIN32, SIN64))

  for d in (0.0, -0.0, 0.4, -0.4, 0.5, -0.5, 2.5, -2.5, 1e7, -1e7):
    row(f'rintk_{d}', lambda: T.rintk(C(d)), 'i')

  for x in (1, 2, 255, 256, 0x7fffffff, 0xffffffff):
    row(f'shr23_{x}', lambda: T.shr(K1(x, dtypes.uint32), 23), 'i')
    row(f'shl23_{x}', lambda: T.shl(K1(x, dtypes.uint32), 23), 'i')

  for d in (0.5, 0.75, 1.0, 1.5, 3.0, 1024.0, 0.0001, 8388608.0):
    row(f'ilogb2k_{d}', lambda: T.ilogb2k(C(d)), 'i')
  for d, e in ((1.0, 3), (1.5, -2), (0.75, 5), (3.0, 0)):
    row(f'ldexp2k_{d}_{e}',
        lambda: T.ldexp2k(C(d), K1(np.int32(e), dtypes.int32)))
    row(f'ldexp3k_{d}_{e}',
        lambda: T.ldexp3k(C(d), C1(e)))
  for q in (0, 1, -1, 10, -10, 126, -126):
    row(f'pow2if_{q}', lambda: T.pow2if(K1(np.int32(q), dtypes.int32), F32))

  for v in (0.5, 1.0, 1.5, 3.0, -2.5, 1024.0):
    m, e = T.frexp(C(v))
    print(f'xf_frexp_{v}={f1(m)},{i1(e)}')

  for d in (0.0, 0.5, 1.0, 1.5707963, 3.0, 30.0, 100.0, -100.0, 39800.0):
    r, q = T.cody_waite_reduction(C(d))
    print(f'xf_cody_waite_{d}={f1(r)},{i1(q)}')

  for d, q in ((0.5, 0), (0.5, 1), (0.5, 2), (0.5, 3), (0.5, 4), (-0.5, 1),
               (1.0, 2), (1.5707963, 2), (1.5707963, 1)):
    qq = K1(np.int32(q), dtypes.int32)
    row(f'sps_{d}_{q}', lambda: T.sin_poly_small(C(d), qq))
    row(f'spl_{d}_{q}', lambda: T.sin_poly_large(C(d), qq))

  XS = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5707963, 3.1415927, 6.2831855,
        29.999998, 30.0, 30.000002, 0.25, 100.0, -100.0]
  vecrow('xsin_fast', XS, lambda u: T.xsin(u, True))
  vecrow('xsin_slow_small', XS, lambda u: T.xsin(u, False))

  XS2 = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 30.0, 126.99999, 127.0,
         127.99999, 128.0, 128.00001, 200.0, -149.99999, -150.0, -150.00001,
         -200.0, 100000.0, -100000.0]
  vecrow('xexp2', XS2, lambda u: T.xexp2(u))
  # MEASURED: xexp2(NaN) is NOT REALISABLE on the PYTHON device. :200 masks
  # +-inf/nan to 0.0, but only because the mask is a `where` -- the NaN still
  # reaches `q = rintk(x)` (:201), whose `.cast(int32)` (:25) is `int(nan)` in
  # the interpreter and raises. Real hardware does not trap, so the row for
  # NaN is a GUARD row below, not a value row.
  vecrow('xexp2_sp', XS2 + [math.inf, -math.inf], lambda u: T.xexp2(u))

  XS3 = [0.0, -0.0, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 0.5e-4, 0.00009999,
         0.00010001, 1e-30, 3e-40, -1.0, 1024.0, 0.25, 8.0]
  vecrow('xlog2', XS3, lambda u: T.xlog2(u))
  # MEASURED, same reason as xexp2: `ilogb2k` (:32-37) CASTs NaN to int32.
  vecrow('xlog2_sp', XS3 + [math.inf, -math.inf], lambda u: T.xlog2(u))

  POWS = [(2.0, 0.5), (4.0, 0.5), (9.0, 0.5), (2.0, 3.0), (2.0, -1.0),
          (-2.0, 3.0), (-2.0, 2.0), (-2.0, 2.5), (-2.0, math.inf),
          (0.0, 0.0), (0.0, 5.0), (math.inf, 0.0), (-1.0, math.inf),
          (1.0, math.inf), (4.0, 0.0), (-4.0, 0.0), (-0.0, 3.0), (-0.0, 2.5),
          (2.0, 0.0), (math.nan, 1.0), (2.0, math.nan), (0.5, 2.0)]
  for b, e in POWS:
    ub = C1(b)
    ue = C1(e)
    print(f'xf_xpow_{b}_{e}={f1(T.xpow(ub, ue))}')

  for x in (math.inf, -math.inf, math.nan, 0.0, 1.0, -1.0):
    ux = C(x)
    print(f'xf_lazy0_{x}='
          f'{f1(T._lazy_map_numbers(ux, ux.const_like(0.0), ux.const_like(0.0), ux.const_like(0.0), ux))}')
    print(f'xf_lazy1_{x}='
          f'{f1(T._lazy_map_numbers(ux, ux.const_like(7.0), ux.const_like(-7.0), ux.const_like(9.0), ux.const_like(3.0)))}')


if __name__ == '__main__':
  main()