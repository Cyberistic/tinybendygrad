<!-- FROM: tinybendygrad/mixin/movement.bend:7 -->
# BLOCK:
# WHAT IS PORTED HERE, gated against CPython:
#
#   1. `_pool` in full as SHAPE ARITHMETIC (movement.py:614-632 symbol=_pool): `noop`, `i_`, `o_`
#      (movement.py:618), `f_` (movement.py:622), the dilation window `k*(i*f+d)`
#      (movement.py:624-626), the permute order (movement.py:632).
#   2. `marg` (ops.py:792 symbol=marg) in all THREE arms, and `as_shape` on its CONCRETE arm
#      (`as_shape`, ops.py:786 symbol=as_shape). This is the W1/W2 answer.
#   3. `_shape`'s movement arms (ops.py:395-414 symbol=_shape) for RESHAPE, EXPAND, PERMUTE, PAD,
#      SHRINK and FLIP -- FIVE arms upstream: `Ops.FLIP` is NOT IN upstream at this pin.
#   4. The `PERMUTE` validity check (ops.py:402-404 symbol=_shape), as `mxm_perm_lt` + `mxm_dup`.
#   5. The WRITE half (Section I): `reshape` (:164), `permute` (:214), `pad` (:186), `shrink`
#      (:192), `flip` (:233), plus `mxw_dims_of` (the shape of ANY node, the merge point that
#      makes the identity test answerable) and `mxw_sig` (node count + root op + src count + SRC
#      OP SEQUENCE).
#
