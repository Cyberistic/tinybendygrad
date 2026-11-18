<!-- FROM: tinybendygrad/mixin/movement.bend:54 -->
# BLOCK:
# THE EXACT INTERFACE `examples/beautiful_mnist.bend` SHOULD CALL -- three defs, and nothing else
# in this file is on the path:
#
#   import ../tinybendygrad/mixin/movement.bend as MX
#   MX.mxm_shape(MX.mxm_marg(ar, i), src_shape) -> List<&2, U32>   # the SHAPE of a movement
#       node, given the source's shape: the `fold.bend:1606-1612` replacement
#   MX.mx_pool_shape(shp, k, stride, dilation) -> List<&2, U32>   # `_pool`'s OUTPUT shape.
#       This is W1/W2 and it needs no arena at all -- it is pure integer arithmetic
#   MX.mx_pool_perm(nn: U32, ni: U32)                             # `_pool`'s PERMUTE order.
#       EXISTS AND IS GATED (four rows against CPython), with BOTH arguments already
#       `U32`-converted: `nn` is `U32.from_nat(ndim - len(k))` and `ni` is
#       `U32.from_nat(List.length(&2, U32, k))`. It answers the ORDER, not a node: building the
#       PERMUTE is `mxw_permute(t, MX.mx_pool_perm(nn, ni))`, which is the gate row `pool_perm`,
#       NOT written.
# `mxm_marg` needs `+ar: O.Arena` and a node index.
#
