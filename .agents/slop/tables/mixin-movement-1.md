<!-- FROM: tinybendygrad/mixin/movement.bend:21 -->
# BLOCK:
# THE NOT-PORTED INVENTORY, one line each, with the wall behind it.
# (The prose of this header was cut in the source; the LIST is here.)
#
# NOT PORTED, each with the reason. `_broadcast_to` (:128) / `expand` (:149) -- DONE FOR
# A CONCRETE SHAPE: `mxw_bcast` at the END of this file is `_broadcast_to` with
# `broadcast_axes`'s `resolve` dropped, and `mixin/creation.bend`'s `cr_expand` and
# `nn/layers.bend`'s `nn_expand` are both it. The SYMBOLIC shape is still the WALL --
# `broadcast_axes` (ops.py:89) needs `resolve` on a `Sint`, i.e. `uop/symbolic.bend`,
# i.e. `mixin/op.bend`'s W3. `repeat` (movement.py:591 symbol=repeat) is blocked on `expand` and is the first
# thing `_pool`'s chain needs. `stack` (movement.py:270 symbol=stack) -- WALL
# in `tensor.bend`: `_mop`'s `case Ops.STACK` (ops.py:809-812 symbol=_mop) needs `dtype_from_uop` and
# `ccast`, and `MopArg` has no STACK constructor; nothing here can route around it.
# `split` (movement.py:438) / `chunk` (movement.py:464 symbol=chunk) -- PORTABLE, NOT DONE: each is a LIST of shrinks whose
# boundaries are `sum(sizes[:i])`. `squeeze` (movement.py:301), `unsqueeze` (movement.py:323), `flatten` (movement.py:360 symbol=flatten),
# `unflatten` (movement.py:376), `transpose` (movement.py:343 symbol=transpose) -- PORTABLE, NOT DONE: each is `mxw_reshape` or
# `mxw_permute` plus a shape-list builder; `mixin/op.bend` already carries `mo_squeeze` and
# `mo_resolve` at the Tensor level. `pad_to` (movement.py:293), `shrink_to` (movement.py:290), `view` (movement.py:297 symbol=view) --
# PORTABLE, NOT DONE, one line each. `diag` (movement.py:516), `diagonal` (movement.py:527), `roll` (movement.py:551 symbol=roll),
# `unfold` (movement.py:634), `meshgrid` (movement.py:489 symbol=meshgrid), `repeat_interleave` (movement.py:575) -- PARTLY, NOT DONE:
# `meshgrid` also needs `_broadcast_shape` (ops.py:80), which needs `dedup` over a `Sint`;
# `roll`'s `delta := n - s%n` is a `Sint` expression whose canonical form is `ssimplify`'s
# business. `ndim` (movement.py:27 symbol=ndim), `numel` (movement.py:38 symbol=numel), `size` (movement.py:59 symbol=size) -- PORTABLE, NOT DONE as PUBLIC DEFS,
# but every internal caller here goes through `mxw_dims_of` instead. `contiguous`, `detach`,
# `to`, `f`, `fs` -- NOT IN `movement.py` AT ALL: `contiguous` (elementwise.py:59) and
# `detach` (elementwise.py:43), `Tensor.to` is `tensor.py:353 symbol=to`, and `f` is
# `UPat.f` (ops.py:1499 symbol=f) -- a pattern-builder method with no Tensor analogue. They are reported rather than ported,
# because porting a method that is not in the file this unit owns would be a
# change-detector test against a neighbour. `_normalize_indices` (movement.py:73) --
# WALL 1: `indices` is a Python list whose elements are `int | slice | Tensor | None | list
# | tuple | Ellipsis`, and the `Ellipsis` SENTINEL and the slice TRIPLE have no Bend
# spelling (`mixin/op.bend`'s W1 from the other side). `_parse_view_index` (:86) -- WALL 1
# again, and the body then threads a list of FIVE-FIELD DICTS (op.py:82); the four fields
# that survive are `(boundary, stride, size, collapse_dim)`. `_apply_view_ops` (:115) --
# WALL 1, built entirely on the two above. `rearrange` (movement.py:393 symbol=rearrange) -- WALL 2, a STRING FORMULA
# PARSER, the same wall as `mixin/op.bend`'s W2 (`einsum`). `max_shape` (movement.py:50 symbol=max_shape) /
# `max_numel` (movement.py:55 symbol=max_numel) -- it needs `to_max_shape`, a deferred import.
