<!-- FROM: tinybendygrad/tensor.bend:2487 -->
# BLOCK:
# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort:
# `n=<count> OP/<nsrc> OP/<nsrc> ...` in DFS-postorder, with the BARE enum name
# (`O.Ops.name.of`, which is `Enum.name`, not `str(enum)`). The oracle is CPython:
# `.agents/slop/tensor-oracle.py` prints the same string for the same expression, and
# the two files' outputs are diffed. NOTHING is executed, because the point is that
# tensor.py's oracle runs without hardware.
#
# The `n=` COUNT is in every signature row on purpose. A boolean row that says "the ADD
# is there" cannot see a missing CONST, and `tn_alu3` exists because `tn_alu2` would
# pass against a `tn_alu` that dropped the third src.
#
# A COUNT row of its own, `tn_arena`, is the arena size after `tn_mop_pad` -- the
# BEND-only number, since Python's ucache is global and shared and its length depends on
# every fixture that ran before it. It pins the orphan SINK that `tn_mop.node` builds, so
# a `tn_mop` that stopped building the SINK would still pass all seven movement rows and
# move this one.
#
# The `tn_alu*` rows call `tn_alu` and not `O.UOp.alu`, and the `tn_mop*`/`tn_rop*` rows
# call `tn_mop`/`tn_rop`, because a gate row that calls the SUBSTRATE is a row about
# ops.bend and not about this file.
# the fixture BUFFER. `UOp.new_buffer(device, size, dtype, num)` is ops.py:853 and is
# WALL 2, but the NODE it builds is not device state -- it is `UOp(Ops.BUFFER,
# src=UOp.device_range_src(device), arg=ParamArg(slot, dtype, size=size,
# device=device, buffer=buf))`, and for a single device `device_range_src` is `()`
# (ops.py:851). So the node is buildable and the `buffer=buf` field is left `None`,
# which is the ONE field of `ParamArg` that needs a device. These are the gate's
# fixtures, not the port's, and the header says so.
# END BLOCK

# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort:
# `n=<count> OP/<nsrc> OP/<nsrc> ...` in DFS-postorder, with the BARE enum name
# (`O.Ops.name.of`, which is `Enum.name`, not `str(enum)`). The oracle is CPython:
# `.agents/slop/tensor-oracle.py` prints the same string for the same expression, and
# the two files' outputs are diffed. NOTHING is executed, because the point is that
# tensor.py's oracle runs without hardware.
#
# The `n=` COUNT is in every signature row on purpose. A boolean row that says "the ADD
# is there" cannot see a missing CONST, and `tn_alu3` exists because `tn_alu2` would
# pass against a `tn_alu` that dropped the third src.
#
# A COUNT row of its own, `tn_arena`, is the arena size after `tn_mop_pad` -- the
# BEND-only number, since Python's ucache is global and shared and its length depends on
# every fixture that ran before it. It pins the orphan SINK that `tn_mop.node` builds, so
# a `tn_mop` that stopped building the SINK would still pass all seven movement rows and
# move this one.
#
# The `tn_alu*` rows call `tn_alu` and not `O.UOp.alu`, and the `tn_mop*`/`tn_rop*` rows
# call `tn_mop`/`tn_rop`, because a gate row that calls the SUBSTRATE is a row about
# ops.bend and not about this file.
# the fixture BUFFER. `UOp.new_buffer(device, size, dtype, num)` is ops.py:853 and is
# WALL 2, but the NODE it builds is not device state -- it is `UOp(Ops.BUFFER,
# src=UOp.device_range_src(device), arg=ParamArg(slot, dtype, size=size,
# device=device, buffer=buf))`, and for a single device `device_range_src` is `()`
# (ops.py:851). So the node is buildable and the `buffer=buf` field is left `None`,
# which is the ONE field of `ParamArg` that needs a device. These are the gate's
# fixtures, not the port's, and the header says so.
