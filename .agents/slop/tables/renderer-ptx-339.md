<!-- FROM: tinybendygrad/renderer/ptx.bend:339 -->
# BLOCK:
# block is not.
# END BLOCK

# THE PREFIX TABLE -- ptx.py:217-219, plus ptx.py:198-209's three allocating
# overrides folded in so ONE `alloc` covers all four:
#
#     Ops.CAST/BITCAST -> ("cast", None)    Ops.END    -> ("pred", "pred")
#     Ops.RANGE        -> ("ridx", None)    Ops.BUFFER -> ("local", "u64")
#     Ops.INDEX/SHRINK -> ("bidx", "u64")   Ops.PARAM  -> ("dat", "u64" if GLOBAL)
#     every ALU op     -> ("alu", None)     else       -> (None, None)
#     Ops.RANGE and u.dtype == dtypes.void  ->  prefix = None        (ptx.py:220)
#
# `Pf{has, prefix, ty, k, lst}` IS that tuple plus the two facts ptx.py spells at
# the USE SITE rather than in the table: `k`, how many `ssa` calls this uop makes,
# and `lst`, whether the answer is a list. `ty = ""` is Python's `None`, meaning
# "read `P.types_of(dt)`" -- no PTX type name is empty, so one field carries
# both the sentinel and the read.
#
# THE FOUR `k`/`lst` CASES and the fixture that separates each PAIR:
#   REG BUFFER  k = max_numel, lst ALWAYS true    f5 (4 -> `{a,b,c,d}`), f6 (1 -> `{a}`)
#   LOAD        k = max_numel, lst = max_numel>1  f10 (8 -> a list); the scalar
#                                                   LOAD of f19 shares the walk
#   PARAM       k = 1,          lst false         f13 (`%dat_u64_0`, `%dat_f32_0`)
#   table op    k = 1,          lst false         f1..f4
