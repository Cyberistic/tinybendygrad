import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/schedule/multi.bend"

EDITS = [
  # ---- THE HEADER (12 lines) -> 10. THE ONE WALL STAYS.
  (1, 12, """# multi.bend -- tinygrad/schedule/multi.py. Multi-device scheduling: the UNSHARD-splitting
# rules, the device-group COPY rules, and the MSELECT/MSTACK rewrites.
#
# the one wall that cuts across every line: `UOp._min_max` (ops.py:1094), which `int(rng.vmax)+1`
# needs in `shard_srcs`, `shrink_multi`, `reshape_multi` and `copy_multi`.
# `uop/fold.bend:5088 symbol=ranged` names it at 1104 in its own PROSE and carries it as its
# `_min_max` WALK -- there is no `TODO(p3)` marker for it there -- and it is not a fold at all --
# it is arithmetic over the srcs. What `mu_count` ports is the NARROW case that is exact and
# load-bearing: a RANGE over a CONST end, where ops.py:1137 reads `(self.src[0]-1).vmax` so
# `int(rng.vmax)+1 == src[0]`, which is exactly what
# `UOp.range(len(devices[0]), -1, AxisType.DEVICE)` builds. A RANGE over a SYMBOLIC end answers
# `mu_sym_count()`, the named wall, and every caller that must not silently get it says so."""),

  # ---- THE 48-LINE `shrink_multi` BLOCK. THE UPSTREAM SOURCE IS A QUOTE AND GOES TO THE
  # TABLE; THE FOUR OUTCOMES AND THE TWO LOAD-BEARING FACTS STAY.
  (1460, 1507, """# AND THE SECOND ARM IS THE LEGACY PATH, and upstream says so: "NOTE: otherwise a
# shrink on the shard axis is only allowed on the legacy device path, selecting a single partition
# (which is copied to all the devices and optimized out later)" (173-174). So the fallback COPIES
# one partition to every device and the later optimisation removes the copy. The port refuses here
# rather than pretending the copy is free. THE UPSTREAM BODY IS IN
# `.agents/slop/tables/schedule-multi-1460.md`.
#
# FOUR per-axis outcomes, and the ORDER is the whole function:
#   0 OWN      -- the shrink IS this range's own shard, so the UNSHARD RESOLVES and the axis
#                 leaves `remaining`. "a fragment indexed by its LOCAL thread range becomes that
#                 thread's REG shard, no copy needed".
#   1 WHOLE    -- the axis is not shrunk at all (`(s,l) == (0, shape[ax])`), so it stays sharded
#                 and only the OTHER axes shrink locally.
#   2 PARTITION -- the LEGACY device path: one partition copied to all devices, which
#                 multi.py:174-175 explicitly deprecates.
#   3 RAISE    -- `shrinking not supported`.
# The OWN test has TWO conjuncts and both are load-bearing: the LENGTH must equal the shard size
# (so the shrink covers this shard exactly) and the START must be `rng * shard_sz` (so it starts
# where this shard starts). A port that tested only the length would resolve an UNSHARD for a
# shrink of the WRONG half.
# `part_bounds` is `((i*shard_sz, shard_sz) for i in range(count))` -- the PARTITION boundaries,
# and it is pure arithmetic over two integers, so it is fully ported and gated: `pb_*` in the gate
# is CPython's own.
# `shard_sz = multi.src[0].shape[ax]` (multi.py:165) -- the LOCAL shape, i.e. `multi.src[0]`, NOT
# `multi.shape`. That distinction is the whole of the OWN test: `l` is compared against the
# SHARD's extent and against `multi.shape[ax]` on the very next line, and they are different
# numbers whenever the axis is sharded.
# THE COUNTDOWN IS FIRST because a self-call must be decreasing and read left to right: `n` is
# the fuel and `p` is its subterm, so it leads. `shard_sz` and the counter `k` ride after and are
# never both read before the shrink."""),

  # ---- `reduce_multi` (21 lines) -- the TWO UPSTREAM COMMENTS and the EXHAUSTIVE-DISJOINT
  # fact stay; the prose goes.
  (887, 907, """# `reduce_multi` (multi.py:107-123). The decision is the SPLIT of the sharding by `num_axes`,
# over two comprehensions that are exhaustive and DISJOINT by construction (`<` and `>=`), so a
# sharding of length n gives `len(reduced) + len(remaining) == n` ALWAYS; `rd_*_n` and `rd_sum_n`
# are that row, and it is the one that would catch a partition that dropped or duplicated an axis.
#
# UPSTREAM'S TWO COMMENTS NAME THE TWO OUTCOMES, and they are the difference between an ALLREDUCE
# and a LOCAL REDUCE:
#
#   "all sharded axes are reduced: full allreduce" (114)
#       every sharded axis is consumed by the reduce, so the partial sums live on different
#       devices and have to be COMBINED -- an allreduce.
#   "no sharded axes reduced: piecewise, keep all remaining sharding" (119)
#       and the opposite: the reduce is entirely within one shard, so it is a LOCAL reduce and the
#       remaining sharding is kept untouched.
# `op` and `num_axes` are `root.arg`, which is `AReduce{rop, num_axes}` (ops.py:752) and already
# split in `ops.bend`, so both are direct reads. The `remaining` AXES ARE REBASED by `num_axes`
# (multi.py:121) and that is the arithmetic `off` carries -- it is why a REDUCE over two of three
# sharded axes unshards on axis 0 and not axis 2. A non-empty `reduced` with a non-empty
# `remaining` is Python's "partial allreduce not supported for multi-axis sharding" assert, which
# is `rd_bad`."""),

  # ---- `reshape_multi` (18 lines) -- the THREE RAISES and the UPSTREAM COMMENT stay.
  (998, 1015, """# `reshape_multi` (multi.py:125-140). The whole body is ARITHMETIC and none of it is a
# builder, which makes this the most completely ported function in the file. FOUR pieces of
# arithmetic and THREE raises, and the three raises are three distinct failure modes:
#   1. `prod(multi.shape) != prod(new_shape)` -- the reshape is not a reshape.
#   2. `target not in arg_acc` -- the shard boundary does not survive the reshape, so items
#      would move between shards.
#   3. `new_shape[new_ax] % count != 0` -- the boundary survives but does not divide evenly.
# `Rs` carries all three as ONE `ok`, because Python raises on the FIRST and the three are
# alternatives, so a port that answered all three independently would have to invent an order it
# does not have. `rs_*_ok` are the rows.
#
# UPSTREAM'S COMMENT IS THE CONDITION THAT MAKES THOSE TWO RAISES THE SAME FAILURE: "map every
# sharded axis through the reshape: the axis boundary must survive intact and stay divisible by
# its shard count" (126). So a reshape is legal across a shard boundary only if the boundary is a
# boundary in the new shape too AND the new axis divides evenly by the shard count. Both raises
# say the same thing -- IT MOVED ITEMS BETWEEN SHARDS -- and they are two checks because the first
# can fail before the second is even meaningful."""),
]

apply(F, EDITS)
