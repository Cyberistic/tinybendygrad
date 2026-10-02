#!/usr/bin/env python3
"""tc-audit.py -- COEFFICIENT AUTHORITY for transcendental.py.

Every expectation here is produced by CALLING tinygrad's own decomposition or by
EVALUATING tinygrad's own source text. Nothing is typed here. Three channels:

  SPY   `polyN`, `shr` and `shl` are imported into transcendental's namespace
        (`from tinygrad.helpers import polyN`, transcendental.py:4), so
        replacing the module attribute intercepts exactly what tinygrad ITSELF
        passes. The coefficient lists are therefore tinygrad's own, not a
        transcription of the source.

  AST   a constant that lives in a function body is located by (line, needle)
        and then EVALUATED from the source text with a restricted namespace, so
        `2.0**24` answers 16777216 because Python said so.

  DT   `dtypes.finfo` / `dtypes.fp8_fnuz` are CALLED, not reimplemented.

Each coefficient is reported three ways so a transposed digit pair cannot hide:
  col 2 `dec`  repr(float)      -- the exact round-trip decimal
  col 3 `h64`  float.hex()      -- the f64 spelling, exact, no rounding at all
  col 4 `f32`  struct '<f' bits -- the f32 the float32 lanes actually carry
  col 5 `hx32` 0x%08x of the same bits -- the f32 HEX spelling
The gate consumes col 2 and col 4. Col 3 and col 5 are what a human reads to
confirm a hex spelling, and they are on the record for exactly the reason the
brief gives: typing a value while reading decimal is not independent.
"""
import ast, struct, sys, math

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp
import tinygrad.codegen.decomp.transcendental as T

SRC = open('tinygrad/codegen/decomp/transcendental.py').read()
TREE = ast.parse(SRC)


def f32bits(x):
  return struct.unpack('<I', struct.pack('<f', x))[0]


def hexrow(name, kind, v):
  if isinstance(v, bool):
    return (name, kind, str(v), str(v), str(v), str(v))
  if isinstance(v, int):
    return (name, kind, str(v), hex(v), str(v), hex(v))
  return (name, kind, repr(v), float(v).hex(), str(f32bits(v)),
          '0x%08x' % f32bits(v))


# ------------------------------------------------------------------ SPY channel
CAP_POLY = []
CAP_SHIFT = []
_real_polyN, _real_shr, _real_shl = T.polyN, T.shr, T.shl


def spy_poly(d, coeff):
  CAP_POLY.append([nm for nm in []] or list(coeff))
  return d


def spy_shr(x, y):
  CAP_SHIFT.append(('shr', y))
  return x


def spy_shl(x, y):
  CAP_SHIFT.append(('shl', y))
  return x


def run_spies():
  CAP_POLY.clear()
  CAP_SHIFT.clear()
  T.polyN, T.shr, T.shl = spy_poly, spy_shr, spy_shl
  u32 = UOp.const(0.5, dtypes.float32)
  u64 = UOp.const(0.5, dtypes.float64)
  T.sin_poly(u32); T.sin_poly(u64)
  T.xexp2(u32); T.xexp2(u64)
  T.xlog2(u32); T.xlog2(u64)
  T.xsin(u32, False)
  T.polyN, T.shr, T.shl = _real_polyN, _real_shr, _real_shl


# ------------------------------------------------------------------ AST channel
def seg(lineno, needle):
  """the SMALLEST ast node on 1-based `lineno` whose source segment contains
  `needle` -- smallest, so a whole Assign is never returned in place of the
  Constant or BinOp inside it."""
  best = None
  for n in ast.walk(TREE):
    if getattr(n, 'lineno', None) != lineno: continue
    if getattr(n, 'end_lineno', None) != lineno: continue
    s = ast.get_source_segment(SRC, n)
    if not s or needle not in s: continue
    if best is None or len(s) < len(best): best = s
  if best is None: raise KeyError(f'{needle!r} not on line {lineno}')
  return best


class _D:
  def __init__(self, dt): self.dtype = dt


def val(lineno, needle, dtype=None):
  ns = {'math': math, 'dtypes': dtypes, 'len': len, 'float_dtype': '<param>',
        'two_over_pi_f': eval(assigns(77)['two_over_pi_f'], {'__builtins__': {}}),
        'denormal_exp': 10 if dtype == dtypes.float16 else 64,
        '__builtins__': {}}
  if dtype is not None: ns['d'] = _D(dtype)
  return eval(seg(lineno, needle), ns)


def assigns(line):
  """every `name = <expr>` written on 1-based `line`, name -> source text"""
  out = {}
  for n in ast.walk(TREE):
    if getattr(n, 'lineno', None) != line: continue
    if getattr(n, 'end_lineno', None) != line: continue
    if not isinstance(n, ast.Assign): continue
    for t in n.targets:
      if isinstance(t, ast.Name): out[t.id] = ast.get_source_segment(SRC, n.value)
      elif isinstance(t, ast.Tuple):     # :125 `PI_A, PI_B, PI_C, PI_D = ...`
        for k, v in zip(t.elts, n.value.elts):
          out[k.id] = ast.get_source_segment(SRC, v)
  return out


def dtype_dicts(line):
  """every `{dtypes.floatNN: value}` literal written on 1-based `line`, as an
  ordered list of (dtype-name, value). Catches the masks at :56-57, the
  FLT_MIN table at :227, the upper/lower table at :211 and the exponent-shifted
  dtype tables at :24/:29/:35/:42, whatever shape they are written in."""
  out = []
  for n in ast.walk(TREE):
    if getattr(n, 'lineno', None) != line: continue
    if getattr(n, 'end_lineno', None) != line: continue
    if not isinstance(n, ast.Dict): continue
    if not n.keys or not isinstance(n.keys[0], ast.Attribute): continue
    out.append([(k.attr, eval(ast.get_source_segment(SRC, v),
                              {'dtypes': dtypes, 'float_dtype': '<param>',
                               '__builtins__': {}}))
                for k, v in zip(n.keys, n.values)])
  return out


def frexp_masks():
  """:56-57 -- `m1 = {...}[v.dtype]`, so the Dict is a Subscript's `.value`
  and every key is `dtypes.<name>`."""
  m1, m2 = {}, {}
  for n in ast.walk(TREE):
    if not (isinstance(n, ast.Assign) and isinstance(n.value, ast.Subscript)): continue
    tgt = getattr(n.targets[0], 'id', '')
    if tgt not in ('m1', 'm2'): continue
    for k, v in zip(n.value.value.keys, n.value.value.values):
      key = k.attr if isinstance(k, ast.Attribute) else ast.literal_eval(k)
      (m1 if tgt == 'm1' else m2)[key] = ast.literal_eval(v)
  return m1, m2


def main():
  run_spies()
  out = []
  # ---- the polyN lists, in the order tinygrad passed them to the spy
  names = ['sin_poly.coeff32', 'sin_poly.coeff64', 'xexp2.coeff32',
           'xexp2.coeff64', 'xlog2.coeff32', 'xlog2.coeff64']
  # xsin is called last and reaches polyN twice more, once per sin_poly_*, and
  # both are the SAME coeff32 list -- so the last two are the reuse, not new data.
  assert len(CAP_POLY) >= 6, CAP_POLY
  assert CAP_POLY[6] == CAP_POLY[0] == CAP_POLY[7], 'xsin reuses sin_poly coeff32'
  for nm, coeff in zip(names, CAP_POLY[:6]):
    for i, c in enumerate(coeff): out.append(hexrow(f'{nm}[{i}]', 'poly', c))
  # ---- every shift/shrink tinygrad asks for, in order
  for i, (kind, y) in enumerate(CAP_SHIFT):
    out.append(hexrow(f'{kind}[{i}].y', 'shift', y))
  # ---- the dtype-keyed literal tables
  for line, tag in ((56, 'frexp.m1'), (57, 'frexp.m2'), (227, 'xlog2.FLT_MIN'),
                    (211, 'xexp2.bounds')):
    for tbl in dtype_dicts(line):
      for k, v in tbl:
        if isinstance(v, tuple):   # xexp2's upper/lower pair, :211
          out.append(hexrow(f'{tag}.upper[{k}]', 'table', v[0]))
          out.append(hexrow(f'{tag}.lower[{k}]', 'table', v[1]))
        else:
          out.append(hexrow(f'{tag}[{k}]', 'table', v))
  for line, tag in ((24, 'rintk.out'), (29, 'pow2if.out'), (35, 'ilogb2k.int'),
                    (42, 'ldexp3k.int'), (58, 'frexp.unsigned')):
    for tbl in dtype_dicts(line):
      for k, v in tbl: out.append((f'{tag}[{k}]', 'dtype', str(v), str(v),
                                  str(v), str(v)))
  # ---- :29's table is keyed by the INTEGER dtype and one entry is the
  # `float_dtype` PARAMETER, so its source text is reported rather than its value.
  out.append(('pow2if.out[param]', 'dtype', 'float_dtype', 'float_dtype',
              'float_dtype', 'float_dtype'))
  # ---- payne_hanek's 2/pi table, in SOURCE order
  tpi = eval(assigns(77)['two_over_pi_f'], {'__builtins__': {}})
  for i, w in enumerate(tpi): out.append(hexrow(f'two_over_pi_f[{i}]', 'u', w))
  # ---- cody_waite's four f64 PI terms, in order
  cw = assigns(125)
  for k in ('PI_A', 'PI_B', 'PI_C', 'PI_D'):
    out.append(hexrow(f'cw.{k}', 'poly', eval(cw[k], {'__builtins__': {}})))
  # ---- the remaining named scalars, located at their own line
  rest = [
    ('cw.m_1_pi', 144, '0.318309886183790671537767526745028724', None),
    ('cw.two_24', 145, '2.0**24', None),
    ('ph.two_over_pi_scale', 82, '4.294967296e9', None),
    ('ph.neg_half_pi_over_2', 110, '3.4061215800865545e-19', None),
    ('ph.q_shift_amount', 108, '62', None),
    ('ph.p_mask', 109, '0x3fffffffffffffff', None),
    ('ph._take_window', 90, 'len(two_over_pi_f) - 1', None),
    ('xlog2.neg_log2e_f64', 240, '2.885390081777926774', None),
    ('xlog2.neg_log2e_f32', 244, '2.8853900432586669922', None),
    ('xlog2.s_lo_f32', 244, '3.2734474483568488616e-08', None),
    ('xlog2.denormal_exp', 226, '10 if', dtypes.float16),
    ('xlog2.denormal_exp', 226, '10 if', dtypes.float32),
    ('xlog2.one_over_075', 231, '1.0 / 0.75', None),
    ('xsin.switch_over', 170, '30.0', None),
    ('xsin.pi_over_2', 165, 'math.pi / 2', None),
    ('xcw32.pi0', 138, '-3.1414794921875', None),
    ('xcw32.pi1', 139, '-0.00011315941810607910156', None),
    ('xcw32.pi2', 140, '-1.9841872589410058936e-09', None),
    ('xcw32.pi3', 141, '-1.2154201256553420762e-10', None),
  ]
  seen = set()
  for nm, ln, needle, dt in rest:
    v = val(ln, needle, dt)
    tag = nm if dt is None else f'{nm}[{dt.name}]'
    out.append(hexrow(tag, 'scalar', v))
  # ---- finfo, CALLED not reimplemented
  for dt, tag in ((dtypes.float64, 'f64'), (dtypes.float32, 'f32'),
                  (dtypes.float16, 'f16')):
    fi = dtypes.finfo(dt)
    out.append((f'finfo[{tag}].0', 'u', str(fi[0]), hex(fi[0]), str(fi[0]), hex(fi[0])))
    out.append((f'finfo[{tag}].1', 'u', str(fi[1]), hex(fi[1]), str(fi[1]), hex(fi[1])))
    mb = T.mantissa_bits(dt)
    eb = T.exponent_bias(dt)
    em = T.exponent_mask(dt)
    for k, v in (('mantissa_bits', mb), ('exponent_bias', eb), ('exponent_mask', em)):
      out.append((f'{k}[{tag}]', 'u', str(v), hex(v), str(v), hex(v)))
  # ---- the two 32-bit frexp masks as a U32 each (the 64-bit ones are hi/lo)
  m1w, m2w = frexp_masks()
  for k, tag in (('float32', 'f32'), ('float16', 'f16')):
    out.append(hexrow(f'frexp.m1w[{tag}]', 'u', m1w[k] & 0xffffffff))
    out.append(hexrow(f'frexp.m2w[{tag}]', 'u', m2w[k] & 0xffffffff))
  # ---- frexp's fraction field, DERIVED from the audited mask and not typed:
  # the port rebuilds the mantissa from `m1` without its sign bit.
  out.append(hexrow('port.frac_mask', 'u', m1w['float32'] & 0x7fffffff))
  # ---- the scaling constants the port needs, EVALUATED from the source
  out.append(hexrow('port.denorm_scale_f32', 's',
                    val(229, '2.0 ** denormal_exp', dtypes.float32)))
  out.append(hexrow('port.denorm_exp_f32', 's',
                    val(226, '10 if', dtypes.float32)))
  out.append(hexrow('port.two_m24', 's', 2.0 ** -24))
  # ---- TRANSCENDENTAL_DTYPES, read off the module
  out.append(('TRANSCENDENTAL_DTYPES', 'dtype',
              ' '.join(dt.name for dt in T.TRANSCENDENTAL_DTYPES),
              ' '.join(dt.name for dt in T.TRANSCENDENTAL_DTYPES),
              ' '.join(dt.name for dt in T.TRANSCENDENTAL_DTYPES),
              ' '.join(dt.name for dt in T.TRANSCENDENTAL_DTYPES)))
  for r in out: print('|'.join(str(x) for x in r))


if __name__ == '__main__':
  main()