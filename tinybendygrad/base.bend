# base.bend -- `F32.from_bits`, the one primitive `references/bend/bend2/base.bend`
# declares the type of and has no name for. PORT-LOCAL: `tinygrad` has no
# `base.py`, so there is no upstream counterpart to mirror; `dtype.bend` and
# `runtime/ops_python.bend` each need this copy and neither can see the other's.
#
# WHY IT IS SAFE. `base.bend:59` declares `U32{data: Word(32n)}` and
# `F32{data: Word(32n)}` -- a float's payload IS its IEEE-754 bit pattern, so the
# constructor `F32{..}` is already a bitcast. One destructuring, one constructor.
#
# GOTCHA: `base.bend:1672` symbol=U32.to_f32 is the NUMERIC conversion
# (`U32.to_f32(3) == 3.0`), NOT a bitcast -- `U32.to_f32(0x3F800000)` is ~1.0e9.
# The inverse is `base.bend:1825` symbol=F32.bits, and there is deliberately no
# second name for it here.
#
# MEASURED, the lane split: `F32.bits(F32.from_bits(p)) == p` for every one of the
# 2^32 patterns in the C lane, and for all but the NaNs in the JS lane. The C lane
# carries an F32 as the raw `u64` of its pattern (`comp.ts:391 f32_unbox` /
# `:396 f32_rewrap`), so `from_bits(0xFFC00001)` reads back `0xFFC00001`. The JS
# lane collapses EVERY NaN onto `0x7FC00000` -- payload and sign gone -- because
# `comp.ts:539 f32_from_bits` hands the float to JavaScript, whose `NaN` is a
# single value. That is a property of the JS float representation, not of
# `from_bits`, and no definition of `from_bits` can repair it.

import Base

def F32.from_bits(bits: U32) -> F32:
  match bits:
    case U32{data}: F32{data}
