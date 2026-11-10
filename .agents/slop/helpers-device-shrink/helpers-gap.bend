# helpers-gap.bend -- THE DIFFERENTIAL DRIVER for the `helpers.bend` defs that
# NO EXISTING GATE COVERS.
#
#   sh .agents/slop/helpers-device-shrink/helpers-gap-gate.sh
#
# WHAT IS ALREADY COVERED, AND WHAT THIS ADDS:
#
#   COVERED   `.agents/slop/helpers-tc-gate.sh` -- 237 shared rows, 3 lanes
#             identical (`trange`, `GlobalCounters`, `Context`, `i64_or`,
#             `i64_and`, `i64_shl`, `i64_div`, `i64_mod`, `i64_add`,
#             `i64_sub`, `i64_dec`).
#   COVERED   `gates/i64-shl-gate.py` -- 151 rows, 3 lanes identical.
#   COVERED   `gates/i64-shr-gate.py` -- 301 rows, 3 lanes identical.
#
#   NOT COVERED, AND THIS IS THE LIST THIS FILE IS FOR:
#     `i64_shr` IS COVERED. THE GAPS ARE:
#       `i64_mul` -- the two's-complement multiply, and `cmod` is WHY it exists
#       `gcd` -- `math.gcd`, whose answer is NON-NEGATIVE by guarantee
#       `u64_divmod` -- the UNSIGNED pair division, which `gcd` and
#                     `cdiv_i64` use
#       `i64_abs` / `i64_not` / `i64_neg`
#       `cdiv_i64` / `cmod_i64` -- upstream's `cdiv` / `cmod` ON THE PAIR
#       `floordiv_i32` / `floormod_i32` / `cdiv_i32` / `cmod_i32`
#       `ceildiv_i32` / `round_up_i32` / `round_down_i32`
#       `next_power2`
#
# EVERY def under test is reached THROUGH `H`, i.e. through the real
# `tinybendygrad/helpers.bend`. This file defines no `I64` arithmetic of its own:
# `rg '^def (i64_|gcd|u64_|cdiv|cmod|floordiv|floormod|ceildiv|round_|next_power2)'
# over this file must find nothing but the ROW HELPERS.
#
# THE FIXTURE SET IS THE UNIVERSE and it is chosen by asking which rows can see
# A DEFECT. The hard values -- int64.min, -1, 0, 1, 2**62, 2**63-1 -- are in
# there because they are the ones where a sign bit, a truncation and a wrap
# disagree. CPython's UNBOUNDED arithmetic is the oracle and every expectation
# here comes from THAT, so a mistake would have to be made twice to hide.
import Base
import ./../../../tinybendygrad/helpers.bend as H

# ===========================================================================
# the gate
# ===========================================================================

def p(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def pu(+nm: String, n: U32) -> IO(Unit):
  p(nm, U32.show(n))

# ---- the 64-bit pair, as a pair of U32
def pair(hi: U32, lo: U32) -> H.I64:
  H.i64_of_hi_lo(hi, lo)

def s64(nm: String, x: H.I64) -> IO(Unit):
  p(nm, H.i64_text(x))

def s32(nm: String, n: U32) -> IO(Unit):
  pu(nm, n)

# ---- the 32-bit signed helpers take and answer a U32 BIT PATTERN, and there is
# NO SIGNED-DECIMAL PRINTER IN THE PORT -- so the driver prints the SIGN and
# then the UNSIGNED magnitude, and the oracle prints the same two fields. The
# split is what makes the comparison exact: CPython's `str(-7)` is one field and
# the port's bit pattern is another, so the driver renders CPython's answer the
# same way the port's is rendered.
def i32_text.go(neg: Bool, f: U32) -> String:
  match neg:
    case True{}: String.concat(["-", H.u32_dec(H.i32_neg(f))])
    case False{}: H.u32_dec(f)

def i32_text(+f: U32) -> String:
  i32_text.go(H.i32_is_neg(f), f)

def i32(nm: String, f: U32) -> IO(Unit):
  p(nm, i32_text(f))

# ===========================================================================
# THE FIXTURE PAIRS. (hi, lo) -- the 64-bit values, as (high word, low word).
# ===========================================================================

# -----the-I64-FIXTURES
def i64_zero() -> H.I64: pair(0, 0)
def i64_one() -> H.I64: pair(0, 1)
def i64_neg1() -> H.I64: pair(4294967295, 4294967295)
def i64_min() -> H.I64: pair(2147483648, 0)
def i64_max() -> H.I64: pair(2147483647, 4294967295)
def i64_p62() -> H.I64: pair(1073741824, 0)
def i64_p63m1() -> H.I64: pair(2147483647, 4294967295)
def i64_2() -> H.I64: pair(0, 2)
def i64_3() -> H.I64: pair(0, 3)
def i64_10() -> H.I64: pair(0, 10)
def i64_100() -> H.I64: pair(0, 100)
def i64_7() -> H.I64: pair(0, 7)
def i64_p32() -> H.I64: pair(0, 4294967295)
def i64_lohi() -> H.I64: pair(1, 2596069104)
def i64_5() -> H.I64: pair(0, 5)
def i64_12() -> H.I64: pair(0, 12)
def i64_18() -> H.I64: pair(0, 18)
def i64_255() -> H.I64: pair(0, 255)

def main() -> IO(Unit):
  do IO<Unit>:
    # ---- `i64_mul`: the two's-complement multiply, mod 2**64.
    s64("mul_1_1", H.i64_mul(i64_one(), i64_one()))
    s64("mul_2_3", H.i64_mul(i64_2(), i64_3()))
    s64("mul_neg1_1", H.i64_mul(i64_neg1(), i64_one()))
    s64("mul_neg1_neg1", H.i64_mul(i64_neg1(), i64_neg1()))
    s64("mul_min_1", H.i64_mul(i64_min(), i64_one()))
    s64("mul_min_min", H.i64_mul(i64_min(), i64_min()))
    s64("mul_max_max", H.i64_mul(i64_max(), i64_max()))
    s64("mul_p62_4", H.i64_mul(i64_p62(), H.i64_of_i32(4)))
    s64("mul_lohi_lohi", H.i64_mul(i64_lohi(), i64_lohi()))
    s64("mul_0_max", H.i64_mul(i64_zero(), i64_max()))
    s64("mul_neg7_3", H.i64_mul(H.i64_neg(True{}, i64_7()), i64_3()))

    # -----`gcd`:-NON-NEGATIVE-by-guarantee,-and-`gcd(0,0)`-is-0.
    s64("gcd_12_18", H.gcd(i64_12(), i64_18()))
    s64("gcd_18_12", H.gcd(i64_18(), i64_12()))
    s64("gcd_0_0", H.gcd(i64_zero(), i64_zero()))
    s64("gcd_0_5", H.gcd(i64_zero(), i64_5()))
    s64("gcd_5_0", H.gcd(i64_5(), i64_zero()))
    s64("gcd_neg_neg", H.gcd(H.i64_neg(True{}, i64_12()), H.i64_neg(True{}, i64_18())))
    s64("gcd_neg_pos", H.gcd(H.i64_neg(True{}, i64_12()), i64_18()))
    s64("gcd_min_min", H.gcd(i64_min(), i64_min()))
    s64("gcd_min_2", H.gcd(i64_min(), i64_2()))
    s64("gcd_1_1", H.gcd(i64_one(), i64_one()))
    s64("gcd_255_10", H.gcd(i64_255(), i64_10()))
    # `gcd(min, 3)` -- THE FIXTURE THAT SEPARATES THE SIGNED REMAINDER FROM THE
    # UNSIGNED ONE. The magnitude of int64.min is 2**63, and 2**63 % 3 is 2,
    # while the SIGNED remainder is -2. A `gcd` that stepped with `i64_mod`
    # instead of `u64_divmod` would carry a NEGATIVE remainder and the loop
    # would not terminate on the magnitude. `gcd_min_min` and `gcd_min_2` CANNOT
    # SEE IT -- both have remainder 0 under either spelling.
    s64("gcd_min_3", H.gcd(i64_min(), i64_3()))

    # ---- `u64_divmod`: the UNSIGNED pair division.
    p("udm_100_7_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_100(), i64_7()))))
    p("udm_100_7_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_100(), i64_7()))))
    p("udm_100_10_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_100(), i64_10()))))
    p("udm_100_10_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_100(), i64_10()))))
    p("udm_min_1_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_min(), i64_one()))))
    p("udm_min_1_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_min(), i64_one()))))
    p("udm_max_1_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_max(), i64_one()))))
    p("udm_max_1_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_max(), i64_one()))))
    p("udm_lohi_255_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_lohi(), i64_255()))))
    p("udm_lohi_255_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_lohi(), i64_255()))))
    p("udm_0_7_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_zero(), i64_7()))))
    p("udm_0_7_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_zero(), i64_7()))))
    # THE ZERO DIVISOR -- and it is a ROW because the answer is NOT ZERO:
    # helpers.bend says "the zero divisor answers the DIVIDEND for the
    # remainder, by the same helpers.py:78 argument as `i64_divmod.of` above:
    # the quotient is 0 and the remainder is whatever was divided. Both callers
    # already guard it, so this is here to keep the def total rather than to
    # serve a row." AND A ROW THAT SAYS "THE ZERO DIVISOR ANSWERS ZERO" IS A
    # ROW THAT CANNOT SEE THE ARM AT ALL -- so the dividend is a NON-ZERO
    # value and the row is the arm.
    p("udm_100_0_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_100(), i64_zero()))))
    p("udm_100_0_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_100(), i64_zero()))))
    p("udm_min_0_q", H.i64_text(H.divmod_q(H.u64_divmod(i64_min(), i64_zero()))))
    p("udm_min_0_r", H.i64_text(H.divmod_r(H.u64_divmod(i64_min(), i64_zero()))))

    # ---- `cdiv_i64` / `cmod_i64`: upstream's `cdiv` / `cmod` ON THE PAIR.
    s64("cdiv_7_2", H.cdiv_i64(i64_7(), i64_2()))
    s64("cdiv_neg7_2", H.cdiv_i64(H.i64_neg(True{}, i64_7()), i64_2()))
    s64("cdiv_neg7_neg2", H.cdiv_i64(H.i64_neg(True{}, i64_7()), H.i64_neg(True{}, i64_2())))
    s64("cdiv_7_neg2", H.cdiv_i64(i64_7(), H.i64_neg(True{}, i64_2())))
    s64("cdiv_0_2", H.cdiv_i64(i64_zero(), i64_2()))
    s64("cdiv_7_0", H.cdiv_i64(i64_7(), i64_zero()))
    s64("cmod_7_2", H.cmod_i64(i64_7(), i64_2()))
    s64("cmod_neg7_2", H.cmod_i64(H.i64_neg(True{}, i64_7()), i64_2()))
    s64("cmod_neg7_neg2", H.cmod_i64(H.i64_neg(True{}, i64_7()), H.i64_neg(True{}, i64_2())))
    s64("cmod_7_0", H.cmod_i64(i64_7(), i64_zero()))

    # ---- `i64_abs` / `i64_not` / `i64_neg`.
    s64("abs_neg7", H.i64_abs(H.i64_neg(True{}, i64_7())))
    s64("abs_min", H.i64_abs(i64_min()))
    s64("abs_7", H.i64_abs(i64_7()))
    s64("not_neg1", H.i64_not(i64_neg1()))
    s64("not_0", H.i64_not(i64_zero()))
    s64("not_7", H.i64_not(i64_7()))
    s64("neg_7", H.i64_neg(True{}, i64_7()))
    s64("neg_min", H.i64_neg(True{}, i64_min()))

    # ---- `floordiv_i32` / `floormod_i32` / `cdiv_i32` / `cmod_i32`: the SIGNED
    # 32-bit pair, and the two spellings of the division are DIFFERENT THINGS.
    i32("fdiv_7_2", H.floordiv_i32(7, 2))
    i32("fdiv_neg7_2", H.floordiv_i32(4294967289, 2))
    i32("fdiv_7_neg2", H.floordiv_i32(7, 4294967294))
    i32("fdiv_neg7_neg2", H.floordiv_i32(4294967289, 4294967294))
    i32("fmod_7_2", H.floormod_i32(7, 2))
    i32("fmod_neg7_2", H.floormod_i32(4294967289, 2))
    i32("fmod_7_neg2", H.floormod_i32(7, 4294967294))
    i32("fmod_neg7_neg2", H.floormod_i32(4294967289, 4294967294))
    i32("cdiv32_7_2", H.cdiv_i32_go(7, 2))
    i32("cdiv32_neg7_2", H.cdiv_i32_go(4294967289, 2))
    i32("cdiv32_7_neg2", H.cdiv_i32_go(7, 4294967294))
    i32("cdiv32_neg7_neg2", H.cdiv_i32_go(4294967289, 4294967294))
    i32("cmod32_7_2", H.cmod_i32(7, 2))
    i32("cmod32_neg7_2", H.cmod_i32(4294967289, 2))
    i32("cmod32_7_neg2", H.cmod_i32(7, 4294967294))
    i32("cmod32_neg7_neg2", H.cmod_i32(4294967289, 4294967294))

    # ---- `ceildiv_i32` / `round_up_i32` / `round_down_i32`.
    i32("ceil_7_2", H.ceildiv_i32(7, 2))
    i32("ceil_neg7_2", H.ceildiv_i32(4294967289, 2))
    i32("ceil_8_2", H.ceildiv_i32(8, 2))
    i32("ceil_0_2", H.ceildiv_i32(0, 2))
    i32("ceil_7_0", H.ceildiv_i32(7, 0))
    i32("rup_7_2", H.round_up_i32(7, 2))
    i32("rup_neg7_2", H.round_up_i32(4294967289, 2))
    i32("rup_8_2", H.round_up_i32(8, 2))
    i32("rdown_7_2", H.round_down_i32(7, 2))
    i32("rdown_neg7_2", H.round_down_i32(4294967289, 2))
    i32("rdown_8_2", H.round_down_i32(8, 2))

    # ---- `next_power2`: the smallest power of two >= x, and 0 answers 1.
    s32("np2_0", H.next_power2(0))
    s32("np2_1", H.next_power2(1))
    s32("np2_2", H.next_power2(2))
    s32("np2_3", H.next_power2(3))
    s32("np2_4", H.next_power2(4))
    s32("np2_5", H.next_power2(5))
    s32("np2_100", H.next_power2(100))
    s32("np2_255", H.next_power2(255))
    s32("np2_256", H.next_power2(256))
    s32("np2_257", H.next_power2(257))
    s32("np2_1000", H.next_power2(1000))
