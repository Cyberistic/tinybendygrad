<!-- FROM: tinybendygrad/schedule/rangeify.bend:2350 -->
# BLOCK:
# `get_kernel_graph` -- rangeify.py:351-376. PORTED AS A STAGE ORDER, and the reason is
# the `ctx` wall rather than a missing idea. SEVEN `graph_rewrite` CALLS, in this order,
# and the order is the port: the tables are all here, each applied to the arena the
# previous stage left, and `rf_stages` is the row that pins the count. What is NOT here
# is the engine that walks the arena applying them -- see the TODO block at the foot.
#
# two of the stages are not in this file's tables and that is a Python fact, not an
# omission: `run_rangeify` (353) is `schedule/indexing.py:190`, and `symbolic` +
# `pm_reduce_simplify` (357) are `uop/symbolic.py` (123 rules) and
# `codegen/simplify.py`. `type_verify` (375) is `uop/spec.py` and IS ported, as
# `uop/spec.bend`.
#
# the two `ctx` lines are the wall and they are the only two: `itertools.count` at 360 and
# 366, and `LimitBufsContext` at 360. Every one is a MUTABLE object threaded through a
# pass, which is exactly the shape `schedule/__init__.bend` refuses for the same reason.
# END BLOCK

# `get_kernel_graph` -- rangeify.py:351-376. PORTED AS A STAGE ORDER, and the reason is
# the `ctx` wall rather than a missing idea. SEVEN `graph_rewrite` CALLS, in this order,
# and the order is the port: the tables are all here, each applied to the arena the
# previous stage left, and `rf_stages` is the row that pins the count. What is NOT here
# is the engine that walks the arena applying them -- see the TODO block at the foot.
#
# two of the stages are not in this file's tables and that is a Python fact, not an
# omission: `run_rangeify` (353) is `schedule/indexing.py:190`, and `symbolic` +
# `pm_reduce_simplify` (357) are `uop/symbolic.py` (123 rules) and
# `codegen/simplify.py`. `type_verify` (375) is `uop/spec.py` and IS ported, as
# `uop/spec.bend`.
#
# the two `ctx` lines are the wall and they are the only two: `itertools.count` at 360 and
# 366, and `LimitBufsContext` at 360. Every one is a MUTABLE object threaded through a
# pass, which is exactly the shape `schedule/__init__.bend` refuses for the same reason.
