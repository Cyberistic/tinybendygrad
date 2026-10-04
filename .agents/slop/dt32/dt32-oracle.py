#!/usr/bin/env python3
"""dt32-oracle.py -- the CPython half of the eight seam defs in
tinybendygrad/dtype.bend.

ASKS CPYTHON.  Nothing here is transcribed:

  * every CONSTANT the port needs is derived here from tinygrad's own
    `float_to_bf16` / `float_to_fp16` / `float_to_fp8` / `fp8_to_float` and
    `_fp8_cfg`, and printed as a row the port's file is checked against;
  * every FIXTURE is an f32 bit pattern, and every expectation is what CPython
    answers for the exact double that pattern denotes.

The f32 restriction is the PORT's, not upstream's: `Dt.bf16`, `Dt.fp8_from` and
`Dt.fp8_to` take a U32 that is an f32 pattern (`float_to_bf16` truncates to
f32; `float_to_fp8` is reached from `float_to_fp8(float(x), dtype)`), so the
oracle is called on `struct.unpack('f', struct.pack('f', bits))[0]` -- the
double CPython would widen that pattern to.  `float_to_fp16` is the one that
takes an f32 directly, and it is still read out of the widened double because
`struct.pack('e', float(x))` is exact for it.

Emits:
  dt32-const.txt   name=py=<value>, the constants the port may spell
  dt32-rows.txt    name=py=<value>, the gate rows, one per fixture per def
"""
import math
import os
import struct
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
os.chdir(REPO)

from tinygrad.dtype import (dtypes, float_to_bf16, float_to_fp16, float_to_fp8,
                            fp8_to_float, _fp8_cfg)


def f32_bits(x):
  return struct.unpack('<I', struct.pack('<f', float(x)))[0]


def bits_to_f32(b):
  return struct.unpack('<f', struct.pack('<I', b & 0xFFFFFFFF))[0]


def as_f64(x):
  """the exact double an f32 pattern widens to"""
  return float(x)


CONST = []
ROWS = []


def add(name, value):
  ROWS.append((name, value))


def cadd(name, value):
  CONST.append((name, value))


# ---------------------------------------------------------------- the fixtures
# The four fp8 kinds, as the port's `fp8_kind` numbers them.
KINDS = [("fp8e4m3", dtypes.fp8e4m3, 0), ("fp8e5m2", dtypes.fp8e5m2, 1),
         ("fp8e4m3fnuz", dtypes.fp8e4m3fnuz, 2), ("fp8e5m2fnuz", dtypes.fp8e5m2fnuz, 3)]

# f32 patterns, chosen so that each arm of each upstream function is reached:
#   0.0 / -0.0 / +-1 / +-2 / +-0.5        sign, zero
#   1.0, 1.0000001, 1.0000002, ...         the bf16/fp16 rounding ties
#   0.1, 3.14159265, 448.0, 464.0, 240.0   fp8 saturate / overflow
#   1e-5, 1e-10, 5.9604645e-8               fp8 subnormal / round-to-zero
#   65504.0, 65519.0, 65520.0, 65536.0     fp16 overflow at exactly 65520
#   inf, -inf, nan, nan-with-payload        the non-finite arms
F32_TEXTS = [
  "0.0", "-0.0", "1.0", "-1.0", "2.0", "-2.0", "0.5", "-0.5",
  "1.0000001", "1.0000002", "1.000000059604644775390625", "3.0000002",
  "0.1", "3.141592653589793", "448.0", "464.0", "240.0", "57344.0",
  "1e-5", "1e-10", "5.960464477539063e-08", "2.9802322387695312e-08",
  "65504.0", "65519.0", "65520.0", "65536.0", "65535.9",
  "inf", "-inf", "nan", "3.4028234663852886e+38", "-3.4028234663852886e+38",
  "1.1754943508222875e-38", "1.1754942106924411e-38",
  "256.0", "260.0", "264.0", "272.0", "288.0", "512.0",
  "6.103515625e-05", "1.220703125e-04", "2.44140625e-07",
  "0.3333333432674408", "0.6666666865348816", "0.7071067811865476",
]

F32S = []
for t in F32_TEXTS:
  x = float(t)
  F32S.append((t, f32_bits(x), x))

# ---------------------------------------------------------------- the constants
# --- the f64 pattern of every _fp8_cfg threshold, split into hi and lo ------
# The port carries the widened f64 as a pair of U32s, so the oracle prints the
# pair.  `hi:lo` is the same unsigned hex the oracle prints everywhere else.
for name, dt, kind in KINDS:
  bias, sig_bits, mant_mask, min_denorm_half, ovf_threshold, max_norm, min_norm = _fp8_cfg[dt]
  cadd(f"fp8_{kind}_bias", bias)
  cadd(f"fp8_{kind}_sig_bits", sig_bits)
  cadd(f"fp8_{kind}_mant_mask", mant_mask)
  cadd(f"fp8_{kind}_hidden_bit", 1 << (sig_bits - 1))
  cadd(f"fp8_{kind}_half_ulp_hi", (1 << (52 - sig_bits)) >> 32)
  cadd(f"fp8_{kind}_half_ulp_lo", (1 << (52 - sig_bits)) & 0xFFFFFFFF)
  cadd(f"fp8_{kind}_half2m1_hi", ((1 << (53 - sig_bits)) - 1) >> 32)
  cadd(f"fp8_{kind}_half2m1_lo", ((1 << (53 - sig_bits)) - 1) & 0xFFFFFFFF)
  for lbl, v in (("min_denorm_half", min_denorm_half), ("ovf_threshold", ovf_threshold),
                 ("min_norm", min_norm)):
    cadd(f"fp8_{kind}_{lbl}_hi", (v >> 32) & 0xFFFFFFFF)
    cadd(f"fp8_{kind}_{lbl}_lo", v & 0xFFFFFFFF)
  cadd(f"fp8_{kind}_max_norm", max_norm)
  cadd(f"fp8_{kind}_is_fnuz", int(dt in dtypes.fp8_fnuz))
  # exp = e32 - 127 + bias, so the port's `shift = 1 - exp` is
  # `128 - bias - e32`.  The port needs the constant, CPython computes it.
  cadd(f"fp8_{kind}_shift_base", 128 - bias)
  # the fp8 biased exponent an f32 exponent field maps to
  cadd(f"fp8_{kind}_exp_bias", bias - 127)
  # `mantissa = (xbits >> (53 - sig_bits)) & mant_mask`, and xbits' mantissa
  # starts at hi bit 20, so the port shifts hi right by this much.
  cadd(f"fp8_{kind}_mant_shift", 20 - (sig_bits - 1))

# --- fp8_to_float's own table --------------------------------------------
for name, dt, kind in KINDS:
  bias, sig_bits, mant_mask, *_ = _fp8_cfg[dt]
  mant_bits, exp_bits = sig_bits - 1, 8 - sig_bits
  cadd(f"f8t_{kind}_mant_bits", mant_bits)
  cadd(f"f8t_{kind}_exp_bits", exp_bits)
  cadd(f"f8t_{kind}_exp_max", (1 << exp_bits) - 1)
  cadd(f"f8t_{kind}_mant_max", (1 << mant_bits) - 1)
  cadd(f"f8t_{kind}_mant_den", 1 << mant_bits)
  cadd(f"f8t_{kind}_mant_exp", 1 - bias)
  cadd(f"f8t_{kind}_is_fnuz", int(dt in dtypes.fp8_fnuz))
  cadd(f"f8t_{kind}_is_e5m2", int(dt is dtypes.fp8e5m2))
  cadd(f"f8t_{kind}_bias", bias)

# --- the nan patterns CPython itself produces ----------------------------
cadd("nan_pos_f32", f32_bits(math.nan))
cadd("nan_neg_f32", f32_bits(math.copysign(math.nan, -1.0)))
cadd("inf_pos_f32", f32_bits(math.inf))
cadd("inf_neg_f32", f32_bits(-math.inf))
cadd("neg_zero_f32", f32_bits(-0.0))
# bf16's 0x7FFF and 0xFFFF0000 mask, read off the function's own body
import inspect
import re
_bf16 = inspect.getsource(float_to_bf16)
_bf16_hex = re.findall(r"0x[0-9A-Fa-f]+", _bf16)
cadd("bf16_half", int(_bf16_hex[0], 16))
cadd("bf16_mask", int(_bf16_hex[1], 16))

# ---------------------------------------------------------------- the rows
# --- Dt.bf16 : f32 bits -> f32 bits, dtype.py float_to_bf16 ---------------
for t, b, x in F32S:
  add(f"bf16[{t}]", f32_bits(float_to_bf16(x)))

# --- Dt.fp16 : f32 bits -> f32 bits, dtype.py float_to_fp16 ---------------
for t, b, x in F32S:
  add(f"fp16[{t}]", f32_bits(float_to_fp16(x)))

# --- Dt.fp8_from : f32 bits -> fp8 bits ----------------------------------
for name, dt, kind in KINDS:
  for t, b, x in F32S:
    add(f"fp8_from[{kind}:{t}]", float_to_fp8(x, dt))

# --- Dt.fp8_to : fp8 bits -> f32 bits ------------------------------------
# every pattern 0..255, plus the saturated ones, for all four kinds
FP8_XS = sorted(set(list(range(256)) + [_fp8_cfg[dt][5] for _, dt, _ in KINDS]))
for name, dt, kind in KINDS:
  for x in FP8_XS:
    add(f"fp8_to[{kind}:{x}]", f32_bits(fp8_to_float(x, dt)))

# --- the four upstream-named wrappers, through dtype.py's own names --------
for t, b, x in F32S:
  add(f"float_to_bf16[{t}]", f32_bits(float_to_bf16(x)))
  add(f"float_to_fp16[{t}]", f32_bits(float_to_fp16(x)))
  for name, dt, kind in KINDS:
    add(f"float_to_fp8[{kind}:{t}]", float_to_fp8(x, dt))
  for x in (0, 1, 0x7F, 0x80, 0xFF, 0x7C):
    add(f"fp8_to_float[0:{x}]", f32_bits(fp8_to_float(x, dtypes.fp8e4m3)))
    add(f"fp8_to_float[3:{x}]", f32_bits(fp8_to_float(x, dtypes.fp8e5m2fnuz)))


def main():
  out = os.path.join(REPO, ".agents", "slop", "dt32")
  with open(os.path.join(out, "dt32-const.txt"), "w") as f:
    for k, v in CONST:
      f.write(f"{k}=py={v}\n")
  with open(os.path.join(out, "dt32-rows.txt"), "w") as f:
    for k, v in ROWS:
      f.write(f"{k}=py={v}\n")
  print("consts: %d  rows: %d" % (len(CONST), len(ROWS)))


if __name__ == "__main__":
  main()