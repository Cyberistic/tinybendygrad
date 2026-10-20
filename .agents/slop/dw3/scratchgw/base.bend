# base.bend -- `F32.from_bits`, the one primitive `references/bend/bend2/base.bend`
# declares the type of and has no name for.
#
# WHY THIS FILE IS PORT-LOCAL. `tinygrad` has no `base.py`, so there is no
# upstream counterpart to mirror; this is the primitive both `tinygrad/dtype.py`
# and `tinygrad/runtime/ops_python.py` need and neither can see the other's copy
# of, because `runtime/ops_python.bend` IMPORTS `dtype.bend` and the dependency
# only runs one way.
#
# ---------------------------------------------------------------------------
# THE OBSERVATION. `base.bend:60` declares
#
#     type U32 is Data:
#       U32{data: Word(32n)}
#     type F32 is Data:
#       F32{data: Word(32n)}
#
# so a float's payload and an integer's payload are the SAME TYPE, `Word(32n)`,
# and a float's payload IS its IEEE-754 bit pattern. The constructor `F32{..}`
# is therefore already a bitcast -- it takes the pattern and yields the float.
# `runtime/ops_python.bend:274-278` had already measured this (`w32`/`f32_of`)
# and had no way to hand it to `dtype.bend`. So `from_bits` is not a new
# primitive, an intrinsic, or a law: it is one destructuring and one
# constructor, and it is safe, so `bend --check-only` accepts it.
#
# `U32.to_f32` IS NOT THIS. `base.bend:1545` declares it a `law` and it is the
# NUMERIC conversion: `U32.to_f32(3) == 3.0`, so `U32.to_f32(0x3F800000)` is
# 1.0e9-ish and not 1.0. Reaching for it produces plausible floats.
#
# INVERSE: `F32.bits` (`base.bend:1697`, also a `law`). `F32.bits` IS the
# inverse -- there is deliberately no second name for it here.
#
# ---------------------------------------------------------------------------
# THE LANE SPLIT, MEASURED, AND IT IS THE INTERESTING PART. The round trip
# `F32.bits(F32.from_bits(p)) == p` holds for EVERY one of the 2^32 patterns in
# the C lane and for all but the NaNs in the JS lane:
#
#   C   `--check-only` clean; the runtime carries an F32 as the raw `u64` of
#       its pattern (`comp.ts:391 f32_unbox` / `:396 f32_rewrap`, a union), so
#       `f32_bits` is the identity and every NaN payload, sign included,
#       survives: `from_bits(0xFFC00001)` reads back `0xFFC00001`.
#   JS  `F32.bits(F32.from_bits(p))` collapses EVERY NaN onto `0x7FC00000` --
#       payload and sign both gone -- because `comp.ts:539 f32_from_bits` hands
#       the float to JavaScript, whose `NaN` is a single value.
#
# So the primitive is exact where the conversion seam (`runtime/dtype.c`) lives,
# and the JS lane's fp8/bf16/fp16 paths cannot tell two NaNs apart. That is a
# property of the JS backend's float representation, not of `from_bits`, and no
# definition of `from_bits` can repair it.
# ---------------------------------------------------------------------------

import Base

def F32.from_bits(bits: U32) -> F32:
  match bits:
    case U32{data}: F32{data}
