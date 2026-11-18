<!-- FROM: tinybendygrad/schedule/multi.bend:1467 -->
# BLOCK:
# THE UPSTREAM BODY OF `shrink_multi`, verbatim.
# (The prose around it was cut in the source; the QUOTE is here.)
#
#     local_marg, remaining = list(root.marg), list(multi.sharding)
#     for ax, rng in multi.sharding:
#       shard_sz = multi.src[0].shape[ax]
#       s, l = root.marg[ax]
#       if sint_to_uop(l).ssimplify() == shard_sz and (sint_to_uop(s)-rng*shard_sz).ssimplify() == 0:
#         local_marg[ax] = (0, shard_sz); remaining.remove((ax, rng)); continue
#       part_bounds = tuple((i*shard_sz, shard_sz) for i in range(int(rng.vmax)+1))
#       if (s, l) == (0, multi.shape[ax]): local_marg[ax] = (0, shard_sz)
#       else:
#         if len(multi.sharding) != 1 or not isinstance(multi.device, tuple) or (s, l) not in part_bounds:
#           raise RuntimeError("shrinking not supported")
#         non_shard_shrink = tuple((0, shard_sz) if i == ax else t for i, t in enumerate(root.marg))
#         return multi.src[0].copy_to_device(multi.device, arg=part_bounds.index((s, l)))._mop(Ops.SHRINK, non_shard_shrink)
#     val = multi.src[0]._mop(Ops.SHRINK, tuple(local_marg))
#     return val if not remaining else val.unshard(...)
