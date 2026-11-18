<!-- FROM: tinybendygrad/renderer/tc_ptx.bend:487 -->
# BLOCK:
# THE STAGE 2 GATE -- ptx.py's emitters. Every row is a STRING beside CPython's.
#
#   * `render_val` over half / float / unsigned -- the three PORTED arms. The
#     signed-integer and double arms are walls and are NOT rows.
#   * `asm_for_op`'s twenty-one entries over five dtypes with `name` FIXED at
#     "s32" (105 rows) -- that isolates the DTYPE branch -- plus five ops over
#     all twelve dtypes with `name = ctx.types[dt]` (60 rows), which isolates
#     the NAME branch: `shl.b{name[1:]}`, `xor.b{name[1:]}`, `selp.b16`.
#   * `supports_half` / `doesnt_support_half` as NAME LISTS in the dict's own
#     order, which is what the tuple comprehension preserves.
#   * `modifier` over all 54 dtype pairs.
#   * the three dtype tables, the two maxima, the suffix, the barrier (TAB
#     escaped) and the kernel prefix split one row per line plus a COUNT.
#   * `supported_dtypes` and `tensor_cores` for three arches.
# END BLOCK

# THE STAGE 2 GATE -- ptx.py's emitters. Every row is a STRING beside CPython's.
#
#   * `render_val` over half / float / unsigned -- the three PORTED arms. The
#     signed-integer and double arms are walls and are NOT rows.
#   * `asm_for_op`'s twenty-one entries over five dtypes with `name` FIXED at
#     "s32" (105 rows) -- that isolates the DTYPE branch -- plus five ops over
#     all twelve dtypes with `name = ctx.types[dt]` (60 rows), which isolates
#     the NAME branch: `shl.b{name[1:]}`, `xor.b{name[1:]}`, `selp.b16`.
#   * `supports_half` / `doesnt_support_half` as NAME LISTS in the dict's own
#     order, which is what the tuple comprehension preserves.
#   * `modifier` over all 54 dtype pairs.
#   * the three dtype tables, the two maxima, the suffix, the barrier (TAB
#     escaped) and the kernel prefix split one row per line plus a COUNT.
#   * `supported_dtypes` and `tensor_cores` for three arches.
