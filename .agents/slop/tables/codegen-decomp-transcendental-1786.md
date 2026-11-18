<!-- FROM: tinybendygrad/codegen/decomp/transcendental.bend:1786 -->
# BLOCK:
# THE DISPATCH, keyed on the OP and not on the tag, because the tag is a
# position and the position moves. `ops.bend` cannot call into this file, so
# `decomp.bend` reads the entry's op and hands it here; that is the whole of the
# duplicated scan. The SQRT rule's body is `lambda d: xpow(d, d.const_like(0.5))`
# -- line 276 -- so the half is minted first.
#
# UPSTREAM'S COMMENT ON THE SQRT RULE IS THAT IT IS NOT A SQRT: "rewrite SQRT
# to xpow 0.5" (292). So a backend without a native SQRT gets a POWER instead
# -- and the power goes through exp2 and log2, which is why the SQRT rule is
# in the TRANSCENDENTAL table and not in the ordinary one.
#
# AND UPSTREAM'S `xpow_int` (267-282) IS NOT IN THE PORT, so its two comments
# are recorded here rather than on a def that does not exist:
#   "square and multiply over the exponent bits in unsigned, masking so
#    products wrap instead of growing" (269)
#       so an INTEGER power is computed by squaring and multiplying over the
#       exponent's bits, in UNSIGNED arithmetic, and every product is MASKED
#       to the unsigned width so the intermediate products WRAP instead of
#       growing without bound.
#   "negative exponent truncates to 0, except for 1 and -1" (279)
#       so a negative integer exponent is not a reciprocal -- it TRUNCATES to
#       zero -- with the two exceptions of 1 and -1, which are their own
#       reciprocals.
# END BLOCK

# THE DISPATCH, keyed on the OP and not on the tag, because the tag is a
# position and the position moves. `ops.bend` cannot call into this file, so
# `decomp.bend` reads the entry's op and hands it here; that is the whole of the
# duplicated scan. The SQRT rule's body is `lambda d: xpow(d, d.const_like(0.5))`
# -- line 276 -- so the half is minted first.
#
# UPSTREAM'S COMMENT ON THE SQRT RULE IS THAT IT IS NOT A SQRT: "rewrite SQRT
# to xpow 0.5" (292). So a backend without a native SQRT gets a POWER instead
# -- and the power goes through exp2 and log2, which is why the SQRT rule is
# in the TRANSCENDENTAL table and not in the ordinary one.
#
# AND UPSTREAM'S `xpow_int` (267-282) IS NOT IN THE PORT, so its two comments
# are recorded here rather than on a def that does not exist:
#   "square and multiply over the exponent bits in unsigned, masking so
#    products wrap instead of growing" (269)
#       so an INTEGER power is computed by squaring and multiplying over the
#       exponent's bits, in UNSIGNED arithmetic, and every product is MASKED
#       to the unsigned width so the intermediate products WRAP instead of
#       growing without bound.
#   "negative exponent truncates to 0, except for 1 and -1" (279)
#       so a negative integer exponent is not a reciprocal -- it TRUNCATES to
#       zero -- with the two exceptions of 1 and -1, which are their own
#       reciprocals.
