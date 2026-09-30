"""Derive the f32-width fp8 tables and check a f32 restatement of dtype.py's
`float_to_fp8` against the f64 original, bit for bit.

dtype.py does the arithmetic on f64 (`struct.pack('d', x)`). Bend's only float
is F32 and it has no bits->float constructor, so the port is a C effect on f32.
That is only faithful if the f32 restatement agrees on every f32 input, which
is what this checks -- over random bit patterns and, for the boundary, exhaustively.

usage: .venv/bin/python .agents/slop/notes/fp8_oracle.py
"""
import math
import random
import struct
import sys

sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.dtype import dtypes, float_to_fp8, fp8_to_float  # noqa: E402

# (bias, sig_bits, mant_mask, min_denorm_half, ovf_threshold, max_norm, min_norm)
# with the three f64 bit patterns rewritten as the f32 bit patterns of the SAME
# value: the comparisons are between magnitudes, and an f32 input's magnitude
# lives in the f32 pattern, so the threshold must be the f32 image of the value.
# dtype.py's three constants are F64 bit patterns. The C effect is handed an F32
# pattern, and the branch is on the MAGNITUDE, so each threshold is rewritten as
# the F32 pattern of the same value. The two `-1` entries (an F64 ULP below
# 61440) round to the same F32 pattern as 61440 itself, which is why 0x47700000
# appears twice.
CFG = {
  "float8_e4m3":     (7, 4, 0x7, 0x3A800000, 0x43E80000, 0x7E, 0x3C800000),
  "float8_e5m2":     (15, 3, 0x3, 0x37000000, 0x47700000, 0x7B, 0x38800000),
  "float8_e4m3fnuz": (8, 4, 0x7, 0x3A000000, 0x43780000, 0x7F, 0x3C000000),
  "float8_e5m2fnuz": (16, 3, 0x3, 0x36800000, 0x47700000, 0x7F, 0x38000000),
}
DT = {"float8_e4m3": dtypes.fp8e4m3, "float8_e5m2": dtypes.fp8e5m2,
      "float8_e4m3fnuz": dtypes.fp8e4m3fnuz, "float8_e5m2fnuz": dtypes.fp8e5m2fnuz}
F32 = {dtypes.fp8e4m3fnuz, dtypes.fp8e5m2fnuz}


def bits(x):
  return struct.unpack("<I", struct.pack("<f", x))[0]


def val(u):
  return struct.unpack("<f", struct.pack("<I", u))[0]


def is_finite(u):
  return ((u >> 23) & 0xFF) != 0xFF


def is_nan(u):
  e = (u >> 23) & 0xFF
  return e == 0xFF and (u & 0x7FFFFF) != 0


def is_inf(u):
  return ((u >> 23) & 0xFF) == 0xFF and (u & 0x7FFFFF) == 0


def sign(u):
  return 1 if (u >> 31) == 0 else -1


def to_fp8(x, d):
  """dtype.py float_to_fp8, restated at f32 width. Same branches, same order."""
  if d in F32 and not is_finite(bits(x)):
    return 0x80
  if d == dtypes.fp8e4m3 and not is_finite(bits(x)):
    return 0x7F if sign(bits(x)) > 0 else 0xFF
  if d == dtypes.fp8e5m2 and not is_finite(bits(x)):
    return ((0 if sign(bits(x)) > 0 else 0x80) |
            (0x7C if is_inf(bits(x)) else 0x7F))
  bias, sig, mant, mdh, ovf, mx, mn = CFG[d.name]
  xb = bits(x)
  # dtype.py's tie bit is f64 bit (52 - sig_bits). An f32's mantissa occupies
  # f64 bits 29..51, so f64 bit k is f32 pattern bit (k - 29) and the tie bit
  # lands at 23 - sig_bits.
  hu = 1 << (23 - sig)
  s = ((xb >> 31) & 1) << 7
  exp = ((xb >> 23) & 0xFF) - 127 + bias
  m = (xb >> (24 - sig)) & mant
  a = xb & 0x7FFFFFFF
  if a <= mdh:
    r = 0
  elif a > ovf:
    r = mx
  elif a >= mn:
    r = (exp << (sig - 1)) | m
    rb = xb & ((hu << 1) - 1)
    if rb > hu or (rb == hu and m & 1):
      r += 1
  else:
    sh = 1 - exp
    m |= 1 << (sig - 1)
    r, half = m >> sh, hu << sh
    rb = (xb | (1 << 23)) & ((half << 1) - 1)
    if rb > half or (rb == half and r & 1):
      r += 1
  return 0 if d in F32 and r == 0 else r | s


def from_fp8(x, d):
  """dtype.py fp8_to_float, returning the f32 bit pattern of the result."""
  bias, sig, *_ = CFG[d.name]
  if d in F32 and x == 0x80:
    return 0x7FC00000
  if (x & 0x7F) == 0:
    return 0x80000000 if (x & 0x80) else 0
  mant_bits, exp_bits = sig - 1, 8 - sig
  exp_max, mant_max = (1 << exp_bits) - 1, (1 << mant_bits) - 1
  s, exp, m = (x >> 7) & 1, (x >> mant_bits) & exp_max, x & mant_max
  if d not in F32 and exp == exp_max:
    if d == dtypes.fp8e5m2:
      # dtype.py: copysign(nan if mantissa else inf, -1 if sign else 1)
      if m:
        return 0xFFC00000 if s else 0x7FC00000
      return 0xFF800000 if s else 0x7F800000
    if m == mant_max:
      return 0x7FC00000
  v = ((m / (mant_max + 1)) * 2 ** (1 - bias) if exp == 0
       else (1 + m / (mant_max + 1)) * 2 ** (exp - bias))
  if s:
    return bits(-v)
  return bits(v)


def check(fn, ref, name, cases):
  bad = [(a, r, fn(a)) for a, r in cases if fn(a) != r]
  print(f"{name:22s} {len(bad)}/{len(cases)} mismatches")
  for a, r, g in bad[:6]:
    print(f"    0x{a:08X} python=0x{r:08X} f32=0x{g:08X}")
  return not bad


def ref_to(name, u):
  return float_to_fp8(val(u), DT[name])


def ref_from(name, x):
  # a nan's SIGN is part of its bit pattern, dtype.py preserves it, and
  # struct.pack of any nan canonicalises to +nan -- so the reference has to read
  # the sign off the float with copysign rather than off its bytes.
  f = fp8_to_float(x, DT[name])
  if f != f:
    return (0xFFC00000 if math.copysign(1.0, f) < 0 else 0x7FC00000)
  return bits(f)


random.seed(7)
ok = True
for name in CFG:
  # every f32 bit pattern is 2^32, too many: a million random ones plus all the
  # small exponents where the denormal branch and the two thresholds live
  rnd = [random.getrandbits(32) for _ in range(1_000_000)]
  near = [(e << 23) | m
          for e in range(0, 140)
          for m in (0, 1, 0x7F, 0x80, 0xFF, 0x7FFF, 0x8000, 0xFFFF,
                    0x400000, 0x7FFFFF, 0x3FFFFF, 0x3FFFFE)]
  near = [u | s << 31 for u in near for s in (0, 1)]
  ok &= check(lambda u, _n=name: to_fp8(val(u), DT[_n]), lambda u: ref_to(name, u),
              f"to_fp8 {name}", [(u, ref_to(name, u)) for u in rnd + near])
  ok &= check(lambda x, _n=name: from_fp8(x, DT[_n]), lambda x: ref_from(name, x),
              f"from_fp8 {name}", [(x, ref_from(name, x)) for x in range(256)])
print("ALL AGREE" if ok else "DIVERGENCE")
