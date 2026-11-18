<!-- FROM: tinybendygrad/renderer/amd/dsl.bend:685 -->
# BLOCK:
#       if encoded >= 128: raise ValueError(...)
#       encoded |= 0x80
# so the `>= 128` test is on `encoded` before the bit is set. This def read
# `vgpr_encode.fit(set, vgpr_or(set, X, f), v, f)` -- the OR FIRST, then the test -- and
# since ORing 0x80 into an eight-bit value ALWAYS leaves it >= 128, EVERY `.h` in an
# eight-bit field took the refusal arm. MEASURED on the census: `vgenchi_7_0_256` CPython
# END BLOCK

# `BitField` -- :100-123. THE FOUR NUMBERS, and only four:
#
#   hi, lo, default, mask = (1 << (hi - lo + 1)) - 1   (:103)
#
# `mask` is the load-bearing one: every read AND every write is masked by it, so
# a wrong mask silently reads a neighbouring field. `set` is (:113-119):
#
#   val is None  -> default            (:114)
#   encoded < 0  -> encoded & mask     two's complement (:117)
#   out of range -> REFUSE             (:118)
#   else  -> (raw & ~(mask << lo)) | (encoded << lo)          (:119)
#
# THE FIELD's OWN FOUR NUMBERS are U32s and always will be: `mask = (1 << (hi -
# lo + 1)) - 1` and a field is at most 32 bits wide (`bf_width_ok`), so `enc` is
# always below 2^32 and `U32.shln` is the right shift for the MASK. WHAT IS NOT a
# U32 is the WORD the mask is shifted INTO -- see `wplaced`. `~` is `U32.not`
# for a mask and `H.i64_not` for a word, and `<<` is `U32.shln` on a Nat for the
# former (`U32.shl` is a ONE-BIT shift, so every shift AMOUNT is a Nat literal or
# a `U32.to_nat` of a bound) and `H.i64_shl` for the latter.
