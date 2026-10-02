#!/usr/bin/env python3
"""tc-gen.py -- turn the CPython audit into (a) the Bend table SOURCE and
(b) the expected coefficient rows. Nothing here types a coefficient: the audit
file, which is CPython's own output, is the only input.

    python3 .agents/slop/tc-gen.py bend > .agents/slop/tc_tables.bend
    python3 .agents/slop/tc-gen.py rows > .agents/slop/tc-rows-coef.txt

Row shapes, and WHY there are five of them per element:

  xf_<t>_<i>=<bits>   INDEX -> VALUE. reads element i of the table.
  xv_<t>_<bits>=<i>   VALUE -> INDEX. searches the table for that bit pattern.
                       The FIXTURE is the value, so it is independent of xf:
                       a mutated coefficient leaves the old bits unfindable and
                       this row answers 4294967295.
  cd_<t>_<i>=<dec>    the exact f64 DECIMAL. Bend has no F64, so this text is
                       the strongest handle on a float64 coefficient and it is
                       why the brief's "no f64 literal is unverified" is closed.
  cu_<t>_<i>=<dec>    the integer value.
  cx_<t>_<i>=0x...    the HEX SPELLING as text. Printed separately on purpose:
                       reading a digit pair in decimal is not independent of
                       typing it, so the hex is a second reading of the same
                       constant.
"""
import sys

AUDIT = '.agents/slop/tc-audit.txt'

TABLES = {                       # audit prefix -> (bend def, 'f' float | 'u' u32)
  'sin_poly.coeff32': ('sp.sin32', 'f'),
  'sin_poly.coeff64': ('sp.sin64', 'f'),
  'xexp2.coeff32': ('sp.exp32', 'f'),
  'xexp2.coeff64': ('sp.exp64', 'f'),
  'xlog2.coeff32': ('sp.log32', 'f'),
  'xlog2.coeff64': ('sp.log64', 'f'),
  'two_over_pi_f': ('sp.topi', 'u'),
}

SCALARS_F = [                    # bend def -> audit name
  ('sp.m_1_pi', 'cw.m_1_pi'),
  ('sp.two_24', 'cw.two_24'),
  ('sp.topi_scale', 'ph.two_over_pi_scale'),
  ('sp.neg_half_pi_over_2', 'ph.neg_half_pi_over_2'),
  ('sp.nlog2e64', 'xlog2.neg_log2e_f64'),
  ('sp.nlog2e32', 'xlog2.neg_log2e_f32'),
  ('sp.s_lo32', 'xlog2.s_lo_f32'),
  ('sp.one_over_075', 'xlog2.one_over_075'),
  ('sp.switch_over', 'xsin.switch_over'),
  ('sp.pi_over_2', 'xsin.pi_over_2'),
  ('sp.cw0', 'xcw32.pi0'),
  ('sp.cw1', 'xcw32.pi1'),
  ('sp.cw2', 'xcw32.pi2'),
  ('sp.cw3', 'xcw32.pi3'),
  ('sp.pi_a', 'cw.PI_A'),
  ('sp.pi_b', 'cw.PI_B'),
  ('sp.pi_c', 'cw.PI_C'),
  ('sp.pi_d', 'cw.PI_D'),
  ('sp.xexp2_lo_32', 'xexp2.bounds.lower[float32]'),
  ('sp.xexp2_up_32', 'xexp2.bounds.upper[float32]'),
  ('sp.flmin_16', 'xlog2.FLT_MIN[float16]'),
  ('sp.flmin_32', 'xlog2.FLT_MIN[float32]'),
]

SCALARS_U = [
  ('sp.q_shift', 'ph.q_shift_amount'),
  ('sp.take_window', 'ph._take_window'),
  ('sp.mb_32', 'mantissa_bits[f32]'),
  ('sp.eb_32', 'exponent_bias[f32]'),
  ('sp.em_32', 'exponent_mask[f32]'),
  ('sp.mb_16', 'mantissa_bits[f16]'),
  ('sp.eb_16', 'exponent_bias[f16]'),
  ('sp.em_16', 'exponent_mask[f16]'),
]

# the 64-bit constants, split at 32 so `1 << 34` saturation cannot bite
SCALARS_U64 = [
  ('p_mask', 'ph.p_mask'),
  ('fm1_64', 'frexp.m1[float64]'),
  ('fm2_64', 'frexp.m2[float64]'),
  ('mant64', 'mantissa_bits[f64]'),
  ('eb64', 'exponent_bias[f64]'),
  ('em64', 'exponent_mask[f64]'),
]

SCALARS_U32_OF_U64 = [            # 32-bit truncations of the same words
  ('mb_64', 'mantissa_bits[f64]'),
]

TEXT = [
  ('tx_dt.transcendental', 'TRANSCENDENTAL_DTYPES'),
  ('tx_dt.rintk_f64', 'rintk.out[float64]'),
  ('tx_dt.rintk_f32', 'rintk.out[float32]'),
  ('tx_dt.rintk_f16', 'rintk.out[float16]'),
  ('tx_dt.pow2if_i64', 'pow2if.out[int64]'),
  ('tx_dt.pow2if_i32', 'pow2if.out[int32]'),
  ('tx_dt.pow2if_i16', 'pow2if.out[int16]'),
  ('tx_dt.ilogb2k_f64', 'ilogb2k.int[float64]'),
  ('tx_dt.ilogb2k_f32', 'ilogb2k.int[float32]'),
  ('tx_dt.ilogb2k_f16', 'ilogb2k.int[float16]'),
  ('tx_dt.ldexp3k_f64', 'ldexp3k.int[float64]'),
  ('tx_dt.ldexp3k_f32', 'ldexp3k.int[float32]'),
  ('tx_dt.ldexp3k_f16', 'ldexp3k.int[float16]'),
  ('tx_dt.frexp_u_f64', 'frexp.unsigned[float64]'),
  ('tx_dt.frexp_u_f32', 'frexp.unsigned[float32]'),
  ('tx_dt.frexp_u_f16', 'frexp.unsigned[float16]'),
  ('tx_dt.pow2if_param', 'pow2if.out[param]'),
]


def load():
  rows = {}
  for line in open(AUDIT):
    f = line.rstrip('\n').split('|')
    if len(f) == 6: rows[f[0]] = f
  return rows


def elems(R, aud):
  ks = [k for k in R if k.startswith(aud + '[') and k.endswith(']')
        and k[len(aud) + 1:-1].isdigit()]
  return sorted(ks, key=lambda k: int(k[len(aud) + 1:-1]))


def main():
  R = load()
  mode = sys.argv[1]
  if mode == 'bend':
    for aud, (nm, kind) in TABLES.items():
      body = [R[k][2] for k in elems(R, aud)]
      parts = [f'String.read("{b}")' for b in body] if kind == 'f' else body
      ty = 'String' if kind == 'f' else 'U32'
      print(f'def {nm}() -> List<&2, {ty}>:')
      print('  ' + ' <> '.join(parts))
    for nm, aud in SCALARS_F:
      print(f'def {nm}() -> String: String.read("{R[aud][2]}")')
    for nm, aud in SCALARS_U:
      print(f'def {nm}() -> U32: {int(R[aud][2])}')
    for nm, aud in SCALARS_U32_OF_U64:
      print(f'def {nm}() -> U32: {int(R[aud][2]) & 0xffffffff}')
    for nm, aud in SCALARS_U64:
      v = int(R[aud][2])
      print(f'def {nm}.hi() -> U32: {v >> 32}')
      print(f'def {nm}.lo() -> U32: {v & 0xffffffff}')
  elif mode == 'rows':
    for aud, (nm, kind) in TABLES.items():
      for i, k in enumerate(elems(R, aud)):
        b = int(R[k][4]) if kind == 'f' else int(R[k][2])
        print(f'xf_{nm}_{i}={b}')
        print(f'xv_{nm}_{b}={i}')
        if kind == 'f':
          print(f'cd_{nm}_{i}={R[k][2]}')
        else:
          print(f'cu_{nm}_{i}={b}')
          print(f'cx_{nm}_{i}=0x{b:08x}')
    for nm, aud in SCALARS_F:
      t = nm[3:].replace('_', '.')
      print(f'xf_{t}={R[aud][4]}')
      print(f'cd_{t}={R[aud][2]}')
    for nm, aud in SCALARS_U + SCALARS_U32_OF_U64:
      t = nm[3:].replace('_', '.')
      print(f'cu_{t}={int(R[aud][2]) & 0xffffffff}')
      print(f'cx_{t}=0x{int(R[aud][2]) & 0xffffffff:08x}')
    for nm, aud in SCALARS_U64:
      v = int(R[aud][2])
      print(f'cu_{nm}.hi={v >> 32}')
      print(f'cu_{nm}.lo={v & 0xffffffff}')
      print(f'cx_{nm}.lo=0x{v & 0xffffffff:08x}')
    for nm, aud in TEXT:
      print(f'{nm}={R[aud][2]}')


if __name__ == '__main__':
  main()