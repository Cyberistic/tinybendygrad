<!-- FROM: tinybendygrad/helpers.bend:2121 -->
# BLOCK:
# `i64_dec` DIVIDES THE MAGNITUDE UNSIGNED, through `u64_divmod` rather than
# `i64_divmod`, and that is what lets it print int64.min. It used to answer the
# `hi:lo` bit pattern for that one value and call it a fallback: |int64.min| = 2**63
# has no positive i64 image, and the fold divided a NEGATIVE magnitude and read
# its digits off a two's complement word. The magnitude 2**63 IS representable as
# an UNSIGNED pair -- `i64_abs` already answers the pair `2147483648:0` -- and
# `u64_divmod` divides that pair without reading bit 63 as a sign, so the fold
# emits 9223372036854775808 and `i64_dec.put` supplies the "-". MEASURED: the
# `hi:lo` fallback answered `2147483648:0` where CPython's `str` says
# `-9223372036854775808`. So the fallback and its `wide` test are DELETED rather
# than widened: the one value they existed for is now the one value that works.
# the fuel is the actual digit count, and that is a measured change. Every fold step is one
# `u64_divmod` and every division is `div_loop(64n, ...)`, i.e. SIXTY-FOUR bit steps whatever the values
# are -- so the fixed fuel of 20 paid 21 divisions for a constant like `392`, which needs three. The count is
# found by COMPARISON, never by division: multiply a power of ten up and add one for each that fits, which is
# `u64_mul` (four `U32` multiplies) and `u64_lt` (two compares) per step and no division at all.
# MEASURED on the 405-uop kernel: this took the render from 94.0 ms to the number in `PARITY.md` §28.
#
# THE TEST IS `p <= x`, WRITTEN AS `not (x < p)`. The first spelling compared `p` on the left and counted
# every power of ten ABOVE the value -- MEASURED: `2147483647` printed `147483647`, one digit short, and the
# truncation was invisible on nine-digit-and-under rows.
#
# `* 10` IS `(x << 3) + (x << 1)`, and that is not a micro-optimisation: `u64_mul` is defined LATER in this
# file and a Bend def cannot be referenced before it, while `i64_shl`/`i64_add` are above. Two shifts and an
# add on a pair are also cheaper than a full 64-bit multiply, so the spelling that satisfies the ordering is
# the faster one as well.
# END BLOCK

# `i64_dec` DIVIDES THE MAGNITUDE UNSIGNED, through `u64_divmod` rather than
# `i64_divmod`, and that is what lets it print int64.min. It used to answer the
# `hi:lo` bit pattern for that one value and call it a fallback: |int64.min| = 2**63
# has no positive i64 image, and the fold divided a NEGATIVE magnitude and read
# its digits off a two's complement word. The magnitude 2**63 IS representable as
# an UNSIGNED pair -- `i64_abs` already answers the pair `2147483648:0` -- and
# `u64_divmod` divides that pair without reading bit 63 as a sign, so the fold
# emits 9223372036854775808 and `i64_dec.put` supplies the "-". MEASURED: the
# `hi:lo` fallback answered `2147483648:0` where CPython's `str` says
# `-9223372036854775808`. So the fallback and its `wide` test are DELETED rather
# than widened: the one value they existed for is now the one value that works.
# the fuel is the actual digit count, and that is a measured change. Every fold step is one
# `u64_divmod` and every division is `div_loop(64n, ...)`, i.e. SIXTY-FOUR bit steps whatever the values
# are -- so the fixed fuel of 20 paid 21 divisions for a constant like `392`, which needs three. The count is
# found by COMPARISON, never by division: multiply a power of ten up and add one for each that fits, which is
# `u64_mul` (four `U32` multiplies) and `u64_lt` (two compares) per step and no division at all.
# MEASURED on the 405-uop kernel: this took the render from 94.0 ms to the number in `PARITY.md` §28.
#
# THE TEST IS `p <= x`, WRITTEN AS `not (x < p)`. The first spelling compared `p` on the left and counted
# every power of ten ABOVE the value -- MEASURED: `2147483647` printed `147483647`, one digit short, and the
# truncation was invisible on nine-digit-and-under rows.
#
# `* 10` IS `(x << 3) + (x << 1)`, and that is not a micro-optimisation: `u64_mul` is defined LATER in this
# file and a Bend def cannot be referenced before it, while `i64_shl`/`i64_add` are above. Two shifts and an
# add on a pair are also cheaper than a full 64-bit multiply, so the spelling that satisfies the ordering is
# the faster one as well.
