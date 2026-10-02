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
import ast

sys.path.insert(0, '.')
from tinygrad import Tensor
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp
import tinygrad.codegen.decomp.transcendental as T

F32 = dtypes.float32
NAN = 0x7fc00000
PSRC = open('tinygrad/codegen/decomp/transcendental.py').read()


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


def bi(u): return int(np.asarray(Tensor(u).numpy()).reshape(-1)[0])


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


def SRCTXT(lineno, name):
  """the source text of `name = ...` written on 1-based `lineno`"""
  tree = ast.parse(PSRC)
  for n in ast.walk(tree):
    if getattr(n, 'lineno', None) != lineno: continue
    if getattr(n, 'end_lineno', None) != lineno: continue
    if not isinstance(n, ast.Assign): continue
    for t in n.targets:
      if isinstance(t, ast.Name) and t.id == name:
        return ast.get_source_segment(PSRC, n.value)
  raise KeyError((lineno, name))


def SRCSEG(lineno, needle, exact=False):
  """the smallest source segment on `lineno` CONTAINING `needle` -- for a
  predicate with no assignment to hang off"""
  tree = ast.parse(PSRC)
  best = None
  for n in ast.walk(tree):
    if getattr(n, 'lineno', None) != lineno: continue
    if getattr(n, 'end_lineno', None) != lineno: continue
    seg = ast.get_source_segment(PSRC, n)
    if not seg or (seg != needle if exact else needle not in seg): continue
    if best is None or len(seg) < len(best): best = seg
  assert best is not None, (lineno, needle)
  return best


def SRCVAL(lineno, needle, ns):
  """EVALUATE tinygrad's own source text for an expression on `lineno`. The
  needle only LOCATES it; the value is computed by tinygrad's interpreter on
  the UOps in `ns`, so this is not a restatement of the rule."""
  import ast
  tree = ast.parse(PSRC)
  best = None
  for n in ast.walk(tree):
    if getattr(n, 'lineno', None) != lineno: continue
    if getattr(n, 'end_lineno', None) != lineno: continue
    seg = ast.get_source_segment(PSRC, n)
    if not seg or needle not in seg: continue
    if best is None or len(seg) < len(best): best = seg
  assert best is not None, (lineno, needle)
  return eval(best, ns)


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
    print(f'xf_frexp_m_{v}={f1(m)}')
    print(f'xf_frexp_e_{v}={i1(e)}')

  for d in (0.0, 0.5, 1.0, 1.5707963, 3.0, 30.0, 100.0, -100.0, 39800.0):
    r, q = T.cody_waite_reduction(C(d))
    print(f'xf_cody_waite_r_{d}={f1(r)}')
    print(f'xf_cody_waite_q_{d}={i1(q)}')

  for d, q in ((0.5, 0), (0.5, 1), (0.5, 2), (0.5, 3), (0.5, 4), (-0.5, 1),
               (1.0, 2), (1.5707963, 2), (1.5707963, 1)):
    qq = K1(np.int32(q), dtypes.int32)
    row(f'sps_{d}_{q}', lambda: T.sin_poly_small(C(d), qq))
    row(f'spl_{d}_{q}', lambda: T.sin_poly_large(C(d), qq))

  XS = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5707963, 3.1415927, 6.2831855,
        29.999998, 30.0, 30.000002, 0.25, 100.0, -100.0]
  vecrow('xsin_fast', XS, lambda u: T.xsin(u, True))
  # xsin(fast=False) picks payne_hanek at |x| >= switch_over (:186-187), and that
  # path needs the uint64 product (:103-109) which Bend cannot express -- so the
  # VALUE rows stop at the boundary and the CHOICE is gated by xg_xsin_below_*.
  SMALL = [x for x in XS if abs(x) < 30.0]
  vecrow('xsin_slow_small', SMALL, lambda u: T.xsin(u, False))

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

  # MEASURED: any xpow with an INFINITE exponent is not realisable on the
  # PYTHON device, because :261-262 CAST the exponent to int32 and
  # `int(inf)` raises. `(-1)**inf` is therefore not a value this port claims:
  # it is a predicate row, below, and the value depends on `(int)inf` which is
  # undefined on hardware too. `nan` is excluded for the same CAST.
  POWS = [(2.0, 0.5), (4.0, 0.5), (9.0, 0.5), (2.0, 3.0), (2.0, -1.0),
          (-2.0, 3.0), (-2.0, 2.0), (-2.0, 2.5),
          (0.0, 0.0), (0.0, 5.0), (math.inf, 0.0),
          (4.0, 0.0), (-4.0, 0.0), (-0.0, 3.0), (-0.0, 2.5),
          (2.0, 0.0), (0.5, 2.0), (0.0, -1.0), (-0.0, -3.0)]
  for b, e in POWS:
    print(f'xf_xpow_{b}_{e}={f1(T.xpow(C1(b), C1(e)))}')

  # ---- xpow's PREDICATES. `non_int` (:261), `is_odd` (:262) and the
  # `exponent.eq(0)` short circuit (:265) are LOCAL expressions, so they are
  # pulled out of tinygrad's source TEXT and evaluated on REAL tinygrad UOps:
  # the text is tinygrad's and the values come from the interpreter.
  POWP = [(2.0, 0.5), (-2.0, 3.0), (-2.0, 2.0), (-2.0, 2.5), (-2.0, -3.0),
          (0.0, 0.0), (0.0, 5.0), (math.inf, 0.0), (4.0, 0.0), (-4.0, 0.0),
          (-0.0, 3.0), (-0.0, 2.5), (2.0, 0.0), (0.5, 2.0), (0.0, -1.0)]
  for b, e in POWP:
    ns = {'base': C1(b), 'exponent': C1(e), 'dtypes': dtypes,
          '__builtins__': {}}
    non_int = bi(eval(SRCTXT(261, 'non_int'), ns))
    is_odd = bi(eval(SRCTXT(262, 'is_odd'), ns))
    e_zero = bi(SRCVAL(265, "exponent.eq(0)", ns))
    print(f'xp_xpow_non_int_{b}_{e}={non_int}')
    print(f'xp_xpow_is_odd_{b}_{e}={is_odd}')
    print(f'xp_xpow_e_zero_{b}_{e}={e_zero}')
    print(f'xp_xpow_neg_base_{b}_{e}=' + str(bi(eval(SRCSEG(265, 'base < 0', exact=True), ns))))

  # ---- the GUARDS. Every special case in this file is a predicate that picks
  # a branch, and a predicate is exactly a value here: `where(cond, a, b)`
  # returns one of two bit patterns, so a mis-written guard is a silently wrong
  # kernel and the branch ids below are what the gate reads.
  GX = [0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 30.0, 127.99999, 128.0,
        128.00001, -149.99999, -150.0, -150.00001, math.inf, -math.inf, math.nan]
  GUARDS = [('xg_xexp2_ge_up', 213, 'd >= upper'),
            ('xg_xexp2_lt_lo', 215, 'd<lower'),
            ('xg_xexp2_nan', 217, 'd.ne(d)'),
            ('xg_xlog2_denorm', 228, 'd<FLT_MIN'),
            ('xg_xlog2_neinf', 247, 'd.ne(math.inf)'),
            ('xg_xlog2_nezero', 249, 'd.ne(0.0)'),
            ('xg_xlog2_neg', 251, 'd<-0.0'),
            ('xg_xlog2_recip', 255, 'd.reciprocal().ne(-math.inf)'),
            ('xg_xsin_below', 187, 'x_abs<switch_over'),
            ('xg_lazy_ne_inf', 11, 'x.ne(math.inf)'),
            ('xg_lazy_ne_ninf', 11, 'x.ne(-math.inf)'),
            ('xg_lazy_ne_self', 11, 'x.ne(x)'),
            ('xg_lazy_nz', 180, 'x.ne(0)'),
            ('xg_lazy_lt0', 180, 'x<0')]
  for x in GX:
    G = {'d': C(x), 'x': C(x), 'x_abs': C(abs(x)), 'math': math,
         'dtypes': dtypes, 'upper': C(128), 'lower': C(-150),
         'FLT_MIN': C(1e-4), 'switch_over': C(30.0), '__builtins__': {}}
    for nm, ln, nd in GUARDS:
      print(nm + '_' + str(x) + '=' + str(bi(eval(SRCSEG(ln, nd, exact=True), G))))
  # MEASURED by the mutation table: M24 (dropping `_lazy_map_numbers`'s -inf
  # arm) moved NOTHING because no fixture here was +-inf or NaN, so the arms
  # the mutation touches were never distinguishable.  inf/-inf/nan are
  # exactly the three inputs `:9-11` exists for.
  for x in (0.0, -0.0, 0.5, -0.5, 1.0, -1.0, math.inf, -math.inf, math.nan):
    ux = C(x)
    print(f'xf_lazy0_{x}='
          f'{f1(T._lazy_map_numbers(ux, ux.const_like(0.0), ux.const_like(0.0), ux.const_like(0.0), ux))}')
    print(f'xf_lazy1_{x}='
          f'{f1(T._lazy_map_numbers(ux, ux.const_like(7.0), ux.const_like(-7.0), ux.const_like(9.0), ux.const_like(3.0)))}')


if __name__ == '__main__':
  main()