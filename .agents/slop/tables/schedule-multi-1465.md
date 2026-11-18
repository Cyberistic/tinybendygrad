<!-- FROM: tinybendygrad/schedule/multi.bend:1465 -->
# BLOCK:
# FOUR per-axis outcomes, and the ORDER is the whole function:
#
#   0 OWN      -- the shrink IS this range's own shard, so the UNSHARD RESOLVES and the axis
#                 leaves `remaining`. "a fragment indexed by its LOCAL thread range becomes that
#                 thread's REG shard, no copy needed".
#   1 WHOLE    -- the axis is not shrunk at all (`(s,l) == (0, shape[ax])`), so it stays sharded
#                 and only the OTHER axes shrink locally.
#   2 PARTITION -- the LEGACY device path: one partition copied to all devices, which
#                 multi.py:174-175 explicitly deprecates.
#   3 RAISE    -- `shrinking not supported`.
#
