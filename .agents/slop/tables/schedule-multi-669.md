<!-- FROM: tinybendygrad/schedule/multi.bend:669 -->
# BLOCK:
# `shard_srcs` (multi.py:54-76). THE CENTRAL DECISION, and the function three resharding
# fallbacks call (`alu_multi` :104, `stack_multi` :200). It is the most arithmetically dense
# body in multi.py and none of it is a builder, so all of it is here:
#
# UPSTREAM'S FIRST COMMENT IS THE FUNCTION'S PRECONDITION: "normalize srcs to
# local shards on axis" (55). Every src is NORMALISED to the same axis first --
# a src with fewer axes is offset by the broadcast -- and only then is the
# per-axis decision made. The `assert all_same(devices)` on the next line is
# the other half: all the srcs must be on the same device.
#
#     devices = [x.device for x in msrcs if x.device is not None]
#     assert all_same(devices)
#     if len(devices): sharding_rng = UOp.range(len(devices[0]), -1, DEVICE)
#     else:            sharding_rng = next(m.src[1] for m in msrcs if m.op is UNSHARD)
#     out_shape = _broadcast_shape(*[x.shape for x in msrcs])
#     for mlb in msrcs:
#       src_axis = axis - (len(out_shape) - len(mlb.shape))
#       if mlb.axis == src_axis:                       srcs.append(mlb.src[0])
#       else:
#         full = mlb if mlb.axis is None else copy_multi(mlb, mlb.device)
#         srcs.append(full if axis in broadcast_axes(mlb.shape, out_shape)
#                     else full._shard(src_axis, sharding_rng))
# FOUR decisions, and they are four defs because they are four answers: `mu_ss_rng` WHICH
# sharding range (a fresh DEVICE range over the devices, or the UNSHARD's own `src[1]`, a
# LOCAL thread range per the comment at multi.py:58-59), `mu_ss_out` the broadcast shape,
# `mu_ss_axis` the RIGHT-ALIGNMENT, and `mu_ss_kind` the three-way per-src branch.
# `_broadcast_shape` is `fold.bend`'s `bcast_shape` (ops.py:80) and is REUSED, not
# re-derived; what is here is `mu_bs_*`, the `IsNone` test on its answer, because a shape
# MISMATCH is an IndexError in Python (ops.py:85) and a `None` here.
# END BLOCK

# `shard_srcs` (multi.py:54-76). THE CENTRAL DECISION, and the function three resharding
# fallbacks call (`alu_multi` :104, `stack_multi` :200). It is the most arithmetically dense
# body in multi.py and none of it is a builder, so all of it is here:
#
# UPSTREAM'S FIRST COMMENT IS THE FUNCTION'S PRECONDITION: "normalize srcs to
# local shards on axis" (55). Every src is NORMALISED to the same axis first --
# a src with fewer axes is offset by the broadcast -- and only then is the
# per-axis decision made. The `assert all_same(devices)` on the next line is
# the other half: all the srcs must be on the same device.
#
#     devices = [x.device for x in msrcs if x.device is not None]
#     assert all_same(devices)
#     if len(devices): sharding_rng = UOp.range(len(devices[0]), -1, DEVICE)
#     else:            sharding_rng = next(m.src[1] for m in msrcs if m.op is UNSHARD)
#     out_shape = _broadcast_shape(*[x.shape for x in msrcs])
#     for mlb in msrcs:
#       src_axis = axis - (len(out_shape) - len(mlb.shape))
#       if mlb.axis == src_axis:                       srcs.append(mlb.src[0])
#       else:
#         full = mlb if mlb.axis is None else copy_multi(mlb, mlb.device)
#         srcs.append(full if axis in broadcast_axes(mlb.shape, out_shape)
#                     else full._shard(src_axis, sharding_rng))
# FOUR decisions, and they are four defs because they are four answers: `mu_ss_rng` WHICH
# sharding range (a fresh DEVICE range over the devices, or the UNSHARD's own `src[1]`, a
# LOCAL thread range per the comment at multi.py:58-59), `mu_ss_out` the broadcast shape,
# `mu_ss_axis` the RIGHT-ALIGNMENT, and `mu_ss_kind` the three-way per-src branch.
# `_broadcast_shape` is `fold.bend`'s `bcast_shape` (ops.py:80) and is REUSED, not
# re-derived; what is here is `mu_bs_*`, the `IsNone` test on its answer, because a shape
# MISMATCH is an IndexError in Python (ops.py:85) and a `None` here.
