<!-- FROM: tinybendygrad/mixin/movement.bend:763 -->
# BLOCK:
# THE WHOLE OF `_shape` FOR A MOVEMENT OP (ops.py:409-431), as a DISPATCH on the
# marg's tag. Every arm is arithmetic over values already read, which is the whole
# point: `fold.bend`'s `None{}` for these five ops (uop/fold.bend:1670 symbol=sym_dim.end) is replaced
# by calls that need no rewrite engine, and `fold.bend` is READ-ONLY here so the arms
# are supplied for a consumer to call rather than installed in the fold.
#
# `UNSHARD` and `REDUCE` are NOT here: UNSHARD needs `vmax` (ops.py:432) and REDUCE
# needs `self.arg[1]`, and `fold.bend` defers UNSHARD for the same reason
# (uop/fold.bend:1670 symbol=sym_dim.end). `SPLIT_REDUCE` is the same arm as REDUCE.
#
# the sels are declared in call-chain order, bottom first, because Bend has no
# forward references and the `match`-on-a-parameter shape needs the leaf to exist.
# END BLOCK

# THE WHOLE OF `_shape` FOR A MOVEMENT OP (ops.py:409-431), as a DISPATCH on the
# marg's tag. Every arm is arithmetic over values already read, which is the whole
# point: `fold.bend`'s `None{}` for these five ops (uop/fold.bend:1670 symbol=sym_dim.end) is replaced
# by calls that need no rewrite engine, and `fold.bend` is READ-ONLY here so the arms
# are supplied for a consumer to call rather than installed in the fold.
#
# `UNSHARD` and `REDUCE` are NOT here: UNSHARD needs `vmax` (ops.py:432) and REDUCE
# needs `self.arg[1]`, and `fold.bend` defers UNSHARD for the same reason
# (uop/fold.bend:1670 symbol=sym_dim.end). `SPLIT_REDUCE` is the same arm as REDUCE.
#
# the sels are declared in call-chain order, bottom first, because Bend has no
# forward references and the `match`-on-a-parameter shape needs the leaf to exist.
