# gate_norm.bend -- the rows that motivated `canon`, read off BOTH lanes in ONE
# emit so node's and cc's exit status belong to the whole row set.
#
# BOTH SPELLINGS OF EVERY ANSWER, on one line, because the class of defect this
# gate exists for is a difference BETWEEN SPELLINGS of one value:
#
#   <name> show=<F32.show(v)> bits=<U32.show(F32.bits(v))>
#
# `F32.show` is the spelling that SEVEN-TO-NINE DIGITS (`references/bend/bend2/
# bend.ts:1197`) and `F32.bits` is the spelling that does not round at all, and
# only the second separates two NaNs (`comp.ts:525-545` splices both verbatim).
# Printing both on one line is what lets `gate_norm.py` report a FORMATTING
# difference and a VALUE difference as two different verdicts rather than as one
# number that means two things at once.
#
# TWO SHAPES OF HELPER, BOTH NEEDED, AND NEITHER IS A CONVENTION:
#   * `show_of`/`bits_of` each take the value ONCE, because a Bend parameter is
#     consumed by its first use and `v : F32` used twice is `consumed more than
#     once` -- measured, not assumed.
#   * a PURE call needs no lift in an ARGUMENT position.  `IO.pure(F32, ...)`
#     does not compile -- `IO.pure`'s first parameter is `-A: Type` and `F32` in
#     expression position is the CONSTRUCTOR, so `expected : F32 / observed :
#     @-R:Type -> ...`.  MEASURED.  `jstage/jsstage.py:218` emits
#     `IO.pure({ty}, {ex})` with `ty = "F32"`, so that lane has the same shape in
#     it; `jstage` is not this unit's file, so it is REPORTED, not edited.
import Base
import ../../../tinybendygrad/base.bend as FB
import ../../../tinybendygrad/dtype.bend as D

def show_of(v: F32) -> String: F32.show(v)
def bits_of(v: F32) -> String: U32.show(F32.bits(v))

def row(nm: String, +v: F32) -> String:
  String.concat([nm, " show=", show_of(v), " bits=", bits_of(v), " | "])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
      # THE FOUR MOTIVATING ROWS.  `fp16` is the seam because `float_to_fp16` is
      # the one upstream conversion CPython can answer AND the tree can compute,
      # and the seam's declared transport is `F32`, so f32 IS the row's width.
      row("f16_1p1", D.Dt.fp16(1.1)),
      row("f32_1p0", D.Dt.fp16(1.0)),
      # `1.0 + 2**-40` is `0x3ff0000000001000` in f64 and EXACTLY 1.0 in f32
      # (e2e.sh:215, "THE ROW f32 CANNOT HAVE"), so this row's verdict DEPENDS on
      # the width and nothing else does.  The carrier is f32, so `1.0` is what the
      # lane can be asked for, and CPython's f64 answer is what would disagree.
      row("f64_2m40", D.Dt.fp16(1.0)),
      # TWO NaNs THAT DIFFER ONLY IN PAYLOAD, plus the negative one.  These three
      # are what `canon_bits` exists for and what `canon` REFUSES.
      row("nan_p0", FB.F32.from_bits(2143289344)),
      row("nan_p1", FB.F32.from_bits(2143289345)),
      row("nan_neg", FB.F32.from_bits(4290772993)),
      # THE LANE'S OWN NaN, which is a payload this file did not choose.
      row("fp8to_nan", D.Dt.fp8_to(127, 1)),
      # `Dt.bf16` takes an F32 PATTERN, not a bf16 one, so this literal is
      # `0x3FC00000` = the bits of 1.5.  A DECIMAL LITERAL IS REQUIRED and the
      # number is not readable: MEASURED, feeding it `0x3F8CC000` (the bits of
      # fp16(1.1), which is what `f16_1p1` uses) answers `1.1015625`, which is a
      # correct bf16 ROUNDING of the wrong input and looks like a port defect.
      row("bf16_1p5", D.Dt.bf16(1069547520))]))