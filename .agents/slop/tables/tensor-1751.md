<!-- FROM: tinybendygrad/tensor.bend:1751 -->
# BLOCK:
# THE DEVICE HALF. Every one of these is WALL 2, and they are listed rather than left out
# because THE LIST IS THE DELIVERABLE: this is the exact set of tensor.py's methods that a
# Tensor-shaped port cannot have until there is a `Buffer`.
#
# TODO(p3) tensor.py:38   _fromnp      -- `UOp.new_buffer` + `buffer.allocate`
# TODO(p3) tensor.py:153  as_param     -- `UOp.param_like` is ops.py:1239, P3
# TODO(p3) tensor.py:156  call         -- `UOp.call_with_output` + a `grad_fxn` kwarg
# TODO(p3) tensor.py:159  custom_kernel -- `UOp.custom_kernel`
# TODO(p3) tensor.py:276  _buffer      -- `x.realize().uop.buffer`
# TODO(p3) tensor.py:283  _data        -- `memoryview`
# TODO(p3) tensor.py:287  data         -- WALL 2, and `dtypes.fmt` with it
# TODO(p3) tensor.py:306  tolist       -- WALL 2, and the `_tolist` recursion is a
#                                         nested-forward tree printer, which
#                                         bend2-constraints records as refused
# TODO(p3) tensor.py:328  numpy        -- WALL 2, and numpy is a foreign module
# TODO(p3) tensor.py:344  clone        -- `UOp.clone` is ops.py:882, `empty_like` plus
#                                         `after(store(src.cast))`, so the AFTER/STORE
#                                         spine is ported above and only the
#                                         `empty_like` is missing
# TODO(p3) tensor.py:353  to           -- `canonicalize_device`, `is_disk_device`,
#                                         `empty_like`, `clone`, `copy_to_device`
# TODO(p3) tensor.py:369  to_          -- `to` + `replace`
# TODO(p3) tensor.py:377  shard        -- `UOp.shard` is ops.py:757 and `_resolve_dim`
#                                         is mixin/movement.py. Upstream's own
#                                         comment at tensor.py:366 is the reason the
#                                         CLONE is not optional: "a shard of a load
#                                         from a creation device (disk/npy/python)
#                                         wants the copy to persist, so it inserts a
#                                         clone". A CREATION DEVICE is one that
#                                         materialises on demand -- a file, an
#                                         in-memory blob -- and its contents are
#                                         GONE once the load is consumed, so a
#                                         shard of one has to COPY rather than
#                                         view. `self.uop.on_creation_device()`
#                                         is the test and `UOp.clone` is the copy.
# TODO(p3) tensor.py:395  shard_       -- `shard` + `replace`
# TODO(p3) tensor.py:401  shard_like   -- `shard` + `to`
# TODO(p3) tensor.py:412  from_blob    -- an external pointer
# TODO(p3) tensor.py:426  from_url     -- `helpers.fetch`
# TODO(p3) tensor.py:442  manual_seed  -- class-level mutable state
# TODO(p3) tensor.py:460  _next_counter -- the same, plus slicing and `assign`
# TODO(p3) tensor.py:502  __setitem__  -- `backward_slice`, `is_realized`,
#                                         `_base_buffer_is_realized` and
#                                         mixin/elementwise.py's `_getitem`
# TODO(p3) tensor.py:530  __delitem__  -- `raise TypeError`, and `__bool__`'s wall
# TODO(p3) tensor.py:553  decode_hevc_frame -- `Variable.unbound` and
#                                         `Ops.CUSTOM_FUNCTION`
#
