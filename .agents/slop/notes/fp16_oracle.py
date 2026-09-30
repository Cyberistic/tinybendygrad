"""Check the hand-written binary16 encoder in runtime/dtype.c against struct's.

Bend has F32.bits but no bits->F32, so float_to_fp16 is a C effect and the C is
hand-written rather than delegating to a compiler's __fp16. This checks it: every
f32 bit pattern is too many to enumerate, so it covers a million random ones, all
256 exponents crossed with every top mantissa bit pattern (which is where every
rounding decision and both overflow directions live), and the exact tie values.

usage: .venv/bin/python .agents/slop/notes/fp16_oracle.py
"""
import math
import random
import struct
import sys

MASK = 0xFFFFFFFF


def ref(x):
  """dtype.py float_to_fp16: struct's rounding, OverflowError -> signed inf."""
  f = struct.unpack("<f", struct.pack("<f", x))[0]
  try:
    return struct.unpack("<e", struct.pack("<e", f))[0]
  except OverflowError:
    return math.copysign(math.inf, f)


def bits_of(y):
  """The f32 pattern of a half value, which is the half zero-extended."""
  return struct.unpack("<I", struct.pack("<f", y))[0] & MASK


def half_bits(y):
  return struct.unpack("<H", struct.pack("<e", y))[0]


def enc(xb):
  """runtime/dtype.c fp16_encode, transcribed."""
  s = (xb >> 16) & 0x8000
  e = (xb >> 23) & 0xFF
  m = xb & 0x7FFFFF
  if e == 0xFF:
    return s | 0x7C00 | (0x200 if m else 0)
  if e == 0 and m == 0:
    return s
  exp = e - 127 + 15
  if exp >= 0x1F:
    return s | 0x7C00
  if exp <= 0:
    if exp < -10:
      return s
    m |= 0x800000
    shift = 14 - exp
    half = m >> shift
    rem = m & ((1 << shift) - 1)
    halfway = 1 << (shift - 1)
    if rem > halfway or (rem == halfway and (half & 1)):
      half += 1
    return s | half
  half = (exp << 10) | (m >> 13)
  rem = m & 0x1FFF
  if rem > 0x1000 or (rem == 0x1000 and (half & 1)):
    half += 1
  return s | half


def half_to_f32(h):
  """The f32 pattern of a half. NOT a zero extension: the two formats have
  different exponent biases (127 vs 15) and different exponent widths."""
  s = (h >> 15) & 1
  e = (h >> 10) & 0x1F
  m = h & 0x3FF
  if e == 0x1F:
    return (s << 31) | 0x7F800000 | (0x400000 if m else 0)
  if e == 0:
    if m == 0:
      return s << 31
    # a half subnormal is m * 2^-24, always an f32 NORMAL since 2^-24 >> 2^-149
    k = m.bit_length() - 1
    return (s << 31) | ((k + 103) << 23) | ((m << (23 - k)) & 0x7FFFFF)
  return (s << 31) | ((e + 112) << 23) | (m << 13)


def check(xs, label):
  """dtype.py's contract is `float_to_fp16(nan)` is nan, `float_to_fp16(inf)`
  is that same infinity, and every finite value is the correctly rounded half.
  A nan's PAYLOAD is not part of the contract and struct promises none, so a nan
  compares as a nan and everything else compares bit for bit."""
  bad = []
  for xb in xs:
    want = ref(struct.unpack("<f", struct.pack("<I", xb))[0])
    got = struct.unpack("<f", struct.pack("<I", half_to_f32(enc(xb))))[0]
    ok = (got != got) if want != want else got == want
    if not ok:
      bad.append((xb, want, got))
  print(f"{label:26s} {len(bad)}/{len(xs)} mismatches")
  for xb, w, g in bad[:8]:
    x = struct.unpack("<f", struct.pack("<I", xb))[0]
    print(f"    0x{xb:08X} x={x!r:>16} want={w!r} got={g!r}")
  return not bad


random.seed(11)
ok = check([random.getrandbits(32) for _ in range(1_000_000)], "random f32")

# every exponent crossed with the mantissa patterns that decide a rounding
top = []
for e in range(256):
  for hi in range(0, 0x800):
    top.append((e << 23) | (hi << 13))
    top.append((e << 23) | (hi << 13) | 0x1000)   # the exact tie
    top.append((e << 23) | (hi << 13) | 0x0FFF)
    top.append((e << 23) | (hi << 13) | 0x2000)
ok &= check(top + [u | 0x80000000 for u in top], "exhaustive exponent sweep")

# the values dtype.py's own test names
ok &= check([struct.unpack("<I", struct.pack("<f", v))[0] for v in
             (1, 65504, 65519.999, 65520, 1e-8, -65504, -65519.999, -65520)],
            "docstring examples")
print("ALL AGREE" if ok else "DIVERGENCE")
sys.exit(0 if ok else 1)
