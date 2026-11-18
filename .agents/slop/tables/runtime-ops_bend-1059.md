<!-- FROM: tinybendygrad/runtime/ops_bend.bend:1059 -->
# BLOCK:
# :200 `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]`
# `Bool.pick` CHOOSES an arm, so `hit` carries the PREDICATE for the line about to
# be read. THE seed is wrong once and it was hidden: `in_bufs.of` seeded `hit` from
# `ls_at(ls, 0n)` -- the FIRST line -- and then the first arm re-tested it, so the
# first line was counted twice and the LAST line never counted. MEASURED, after
# WALL 4 was cleared: `bend_prog_tiny_in_bufs` read `4 4 4 0` where CPython's
# `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]` is `[4, 4, 4]`.
#
# The fix is the shape `ops_python.bend` uses everywhere: TEST THE HEAD INSIDE THE
# ARM, so every line is tested exactly once and the seed is `False{}`.
# `Bool.pick` EVALUATES BOTH ARMS, so a `pick` whose arms both RECUR diverges the
# walk into an infinite regress -- MEASURED: the run never terminated. So the pick
# is over a VALUE, not over the recursion, which is the shape the rest of this file
# uses (`hexout.go`, `raw_free`).
# END BLOCK

# :200 `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]`
# `Bool.pick` CHOOSES an arm, so `hit` carries the PREDICATE for the line about to
# be read. THE seed is wrong once and it was hidden: `in_bufs.of` seeded `hit` from
# `ls_at(ls, 0n)` -- the FIRST line -- and then the first arm re-tested it, so the
# first line was counted twice and the LAST line never counted. MEASURED, after
# WALL 4 was cleared: `bend_prog_tiny_in_bufs` read `4 4 4 0` where CPython's
# `[buf_extent(u.arg) for u in self.uops if is_buf(u.arg)]` is `[4, 4, 4]`.
#
# The fix is the shape `ops_python.bend` uses everywhere: TEST THE HEAD INSIDE THE
# ARM, so every line is tested exactly once and the seed is `False{}`.
# `Bool.pick` EVALUATES BOTH ARMS, so a `pick` whose arms both RECUR diverges the
# walk into an infinite regress -- MEASURED: the run never terminated. So the pick
# is over a VALUE, not over the recursion, which is the shape the rest of this file
# uses (`hexout.go`, `raw_free`).
