<!-- FROM: tinybendygrad/nn/layers.bend:225 -->
# BLOCK:
# `ret.reshape(kept) if axis != reduce_axis else ret` -- ops.py:638. APPLIED
# UNCONDITIONALLY, which is the same thing: `axis == reduce_axis` makes `kept`
# the identity, and `M.mo_reshape` (mixin/op.bend:692 symbol=mo_reshape) answers its source
# unchanged on an identity target rather than minting a RESHAPE. MEASURED: with
# the reshape applied, `sum(axis=[2])` over `(2, 4, 3)` is a 20-node graph whose
# root IS the REDUCE and whose folded shape is `(2, 4)`; with the INDICES
# substituted for the values it minted a second RESHAPE to `(0, 1)`, which the
# fold could not read, and the row printed nothing.
# `1 if i in axis else s for i,s in enumerate(self.shape)` -- reduce.py:18,
# the keepdim target. this is now read from `mixin/op.bend`'s `mo_keep_ds` and not
# spelled here, and the reason the local COPY existed is gone.
# the history, because it is why the bug was hard to see: the local COPY was written
# INDEX counted from the end, while every neighbour is forward (`mo_dim_at` reads
# `mo_dims` AT A FORWARD INDEX, `mo_resolve` ADDS `total` TO A NEGATIVE AXIS, `mo_range`
# BUILDS `0..n-1`). `.agents/slop/nnconv/probe/moat.bend` MEASURED `idx(10,20,30) = 2,1,0`
# over a forward walk, so `mo_keep_ds` was right on a one-dimensional shape -- WHERE the
# two readings agree, and WHERE `mixin/op.bend`'s `sh_sum0kd` row lives -- and wrong on
# every other: it answered `(1,4,3)` on `(2,4,3)` with axis `[2]` WHERE CPython answers
# `(2,4,1)` (tinygrad/mixin/reduce.py:18).
# - so the port had *two* implementations of one rule, one right and one wrong, and the
# nn layer used the right one -- which is exactly why the wrongness was invisible: the row
# that caught it, `fold_smk`, expected `2,1,3`, which is CPython's answer for axis `[1]`
# and also what the port's `mo_keep_ds` answered for every axis. a wrong answer that
# coincides with a right one is the deepest form of *\"a row that cannot go red is a
# LABEL\"*.
# - and `mo_at` is now fixed (`mixin/op.bend`: `n - len(ds)`, the original length
# threaded, because `ds` at the call site is the *remaining* list), so `mo_keep_ds` is
# forward and correct, and the local COPY is dead weight. - and the two read the same
# SHAPE: `nn_shape` IS `nn_u32(M.mo_dims(...))` AND `mo_keep_ds` IS `mo_dims(...)` -- THE
# FOLD's shape, both of them -- so the swap changes the INDEX and nothing ELSE.
# END BLOCK

# `ret.reshape(kept) if axis != reduce_axis else ret` -- ops.py:638. APPLIED
# UNCONDITIONALLY, which is the same thing: `axis == reduce_axis` makes `kept`
# the identity, and `M.mo_reshape` (mixin/op.bend:692 symbol=mo_reshape) answers its source
# unchanged on an identity target rather than minting a RESHAPE. MEASURED: with
# the reshape applied, `sum(axis=[2])` over `(2, 4, 3)` is a 20-node graph whose
# root IS the REDUCE and whose folded shape is `(2, 4)`; with the INDICES
# substituted for the values it minted a second RESHAPE to `(0, 1)`, which the
# fold could not read, and the row printed nothing.
# `1 if i in axis else s for i,s in enumerate(self.shape)` -- reduce.py:18,
# the keepdim target. this is now read from `mixin/op.bend`'s `mo_keep_ds` and not
# spelled here, and the reason the local COPY existed is gone.
# the history, because it is why the bug was hard to see: the local COPY was written
# INDEX counted from the end, while every neighbour is forward (`mo_dim_at` reads
# `mo_dims` AT A FORWARD INDEX, `mo_resolve` ADDS `total` TO A NEGATIVE AXIS, `mo_range`
# BUILDS `0..n-1`). `.agents/slop/nnconv/probe/moat.bend` MEASURED `idx(10,20,30) = 2,1,0`
# over a forward walk, so `mo_keep_ds` was right on a one-dimensional shape -- WHERE the
# two readings agree, and WHERE `mixin/op.bend`'s `sh_sum0kd` row lives -- and wrong on
# every other: it answered `(1,4,3)` on `(2,4,3)` with axis `[2]` WHERE CPython answers
# `(2,4,1)` (tinygrad/mixin/reduce.py:18).
# - so the port had *two* implementations of one rule, one right and one wrong, and the
# nn layer used the right one -- which is exactly why the wrongness was invisible: the row
# that caught it, `fold_smk`, expected `2,1,3`, which is CPython's answer for axis `[1]`
# and also what the port's `mo_keep_ds` answered for every axis. a wrong answer that
# coincides with a right one is the deepest form of *\"a row that cannot go red is a
# LABEL\"*.
# - and `mo_at` is now fixed (`mixin/op.bend`: `n - len(ds)`, the original length
# threaded, because `ds` at the call site is the *remaining* list), so `mo_keep_ds` is
# forward and correct, and the local COPY is dead weight. - and the two read the same
# SHAPE: `nn_shape` IS `nn_u32(M.mo_dims(...))` AND `mo_keep_ds` IS `mo_dims(...)` -- THE
# FOLD's shape, both of them -- so the swap changes the INDEX and nothing ELSE.
