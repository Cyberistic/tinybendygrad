<!-- FROM: tinybendygrad/dtype.bend:574 -->
# BLOCK:
# dtype.py's float_to_fp16, in bits: `fp16_encode` then `fp16_f32`
# (`dtype.c:117-153`), which is a rebias and a shift, not a value computation.
# `dtype.c:143` says a half subnormal is `m * 2^-24`, always an f32 NORMAL, so
# the DECODE side needs no denormal path; the encode side does.
#
# THE ONE ARITHMETIC SUBSTITUTION, forced by the type: the C writes
# `int exp = (int)e - 127 + 15` and tests `exp >= 0x1f`, `exp <= 0`, `exp < -10`.
# `U32.sub` SATURATES AT 0 (base.bend:1375 symbol=Word.sub; `U32.sub` itself is
# at base.bend:1483 symbol=U32.sub), so `exp` cannot be formed as a U32 at all --
# every `e` under 112 would read 0 and "too small to represent" would be
# indistinguishable from "subnormal". Every test is therefore restated against
# `e` itself, which is exact:
#
#     exp = e - 112        exp >= 31  <=>  e >= 143
#                         exp <= 0   <=>  e <= 112
#                         exp < -10  <=>  e <= 101
#                         shift = 14 - exp = 126 - e, 15..24 over that arm
#
# `fp16_encode` takes the three fields `dtype.c:118-120` reads -- sign, exponent,
# mantissa -- and answers the half, sign already in half position. The arms are
# `dtype.c:121-138` in the order the C tests them; each is its own def because
# Bend will not match on a computed Bool. A def must be declared before its
# caller, so the arms run bottom-up.
#
# TWO OF THE C's FOUR TESTS ARE GONE, both subsumed rather than
# dropped-by-accident:
#   `if (e == 0 && m == 0) return s;` (:122) -- e is 0, which is <= 101, so the
#     underflow arm answers `s` too. The C needs the early exit; the ladder does
#     not.
#   `if (exp < -10) return s;` (:129) -- kept, deliberately. The subnormal arm
#     happens to agree out here (half is 0 and rem cannot reach halfway), but
#     only because `U32.shln(1, 126)` SATURATES to 0 and the mask then saturates
#     too. Depending on that is depending on a cliff.
#
# Round-half-to-even: the tie is `rem == halfway` and then the LOW bit of what
# is being kept decides (`dtype.c:132`, `:137`). `half` may carry, so the
# increment is added, not or-ed in -- `dtype.c:137`'s comment says so.
# END BLOCK

# dtype.py's float_to_fp16, in bits: `fp16_encode` then `fp16_f32`
# (`dtype.c:117-153`), which is a rebias and a shift, not a value computation.
# `dtype.c:143` says a half subnormal is `m * 2^-24`, always an f32 NORMAL, so
# the DECODE side needs no denormal path; the encode side does.
#
# THE ONE ARITHMETIC SUBSTITUTION, forced by the type: the C writes
# `int exp = (int)e - 127 + 15` and tests `exp >= 0x1f`, `exp <= 0`, `exp < -10`.
# `U32.sub` SATURATES AT 0 (base.bend:1375 symbol=Word.sub; `U32.sub` itself is
# at base.bend:1483 symbol=U32.sub), so `exp` cannot be formed as a U32 at all --
# every `e` under 112 would read 0 and "too small to represent" would be
# indistinguishable from "subnormal". Every test is therefore restated against
# `e` itself, which is exact:
#
#     exp = e - 112        exp >= 31  <=>  e >= 143
#                         exp <= 0   <=>  e <= 112
#                         exp < -10  <=>  e <= 101
#                         shift = 14 - exp = 126 - e, 15..24 over that arm
#
# `fp16_encode` takes the three fields `dtype.c:118-120` reads -- sign, exponent,
# mantissa -- and answers the half, sign already in half position. The arms are
# `dtype.c:121-138` in the order the C tests them; each is its own def because
# Bend will not match on a computed Bool. A def must be declared before its
# caller, so the arms run bottom-up.
#
# TWO OF THE C's FOUR TESTS ARE GONE, both subsumed rather than
# dropped-by-accident:
#   `if (e == 0 && m == 0) return s;` (:122) -- e is 0, which is <= 101, so the
#     underflow arm answers `s` too. The C needs the early exit; the ladder does
#     not.
#   `if (exp < -10) return s;` (:129) -- kept, deliberately. The subnormal arm
#     happens to agree out here (half is 0 and rem cannot reach halfway), but
#     only because `U32.shln(1, 126)` SATURATES to 0 and the mask then saturates
#     too. Depending on that is depending on a cliff.
#
# Round-half-to-even: the tie is `rem == halfway` and then the LOW bit of what
# is being kept decides (`dtype.c:132`, `:137`). `half` may carry, so the
# increment is added, not or-ed in -- `dtype.c:137`'s comment says so.
