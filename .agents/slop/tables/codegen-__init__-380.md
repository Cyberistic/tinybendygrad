<!-- FROM: tinybendygrad/codegen/__init__.bend:380 -->
# BLOCK:
# THE FIXPOINT, ops.py:1777-1885.
#
# Upstream's `unified_rewrite` is a THREE-STAGE WORKLIST: stage 0 pushes a node
# and its srcs (running a bottom-up table to a per-node fixed point first),
# stage 1 rebuilds once every src is in `replace` and runs the top-down table,
# stage 2 links the rebuilt node's replacement back to `n`. It carries a
# `waitlist` for a src that is not ready and an `on_stack` set.
#
# The port's is THE SAME FOLD RE-RUN, which is what makes it a FIXPOINT rather
# here rather than left implied:
#
#   * `bottom_up` / `bpm`. Upstream puts `pm` in `self.bpm` and `None` in
#     `self.pm` when `bottom_up=True`, and BOTH drivers then run only the
#     bottom-up table. `uop/ops.bend` -- which this file must not edit -- has
#     no `bpm` and no per-entry bottom-up marker, so there is no second table
#     for the dispatcher's other half to select. `pm_post_sched_cache` is
#     top-down in both ports, so this is INVISIBLE on the fixture and it is a
#     wall upstream, not a silent difference. ops.py:1889.
#   * `enter_calls`. Both drivers skip `n.src[1:]` of a CALL, so the two
#     upstream call sites that pass `enter_calls=True`
#     (`schedule/__init__.py:276`, `codegen/__init__.py:492`) are wrong here.
#     ops.py:1833/1841.
#   * The per-node `seen` set and `BottomUpGate`, which bound the BOTTOM-UP loop
#     the port does not have.
#
# the stop is "the sink index did not move", and it is sound because the arena
# INTERNS. `uop/ops.bend:2530 UOp.make` calls `intern.find` and a HIT returns the
# arena UNTOUCHED, so two passes handing back the same sink INDEX handed back the
# same `Node{op, src, arg, tag}`. The reachable graph is identical,
# `pm_rewrite_m` is a pure function of that graph and of `ctx`, and the next pass
# rebuilds nothing. Index equality here is the interning invariant, not a
# coincidence.
#
# A cap and a fixpoint ARE DISTINGUISHABLE here, and `capped` says which.
# Upstream raises for both -- `REWRITE_STACK_LIMIT` at ops.py:1821 and the
# stalled waitlist at :1883 -- and a Bend def returns a value, so both raise
# sites become one Bool. `capped=True` IS NOT A FIXPOINT and must never be read
# as one. What it does NOT separate is a genuine rewrite CYCLE (R(n)=m,
# R(m)=n) from a chain that merely needs more passes: both are "the sink was
# still moving when the bound ran out", and the port cannot tell them apart
# because it has no `seen` set. So `capped=True` means NOT-CONVERGED and nothing
# finer. The `grw_cap_*` rows REACH the flag, so it is not merely asserted.
#
# WHY ONE DEF AND NOT TWO. The stop test is a Bool and the bound is a Nat, and
# Bend refuses a `match` after any other statement, refuses a `match` on a
# computed value, and refuses a TWO-DEF cycle -- all three measured in
# `grw-loop-probe.bend`. So the `Nat` match is the body's first statement and the
# `Bool.pick` sits inside its two arms. `f` is the shrinking self-call argument,
# so it comes first and every computed argument follows it. `w` is the pass
# result as a `+` RECORD parameter: a TUPLE may be read exactly once (and `+` on
# one is refused outright), while a record parameter reads as many times as the
# arms need.
# END BLOCK

# THE FIXPOINT, ops.py:1777-1885.
#
# Upstream's `unified_rewrite` is a THREE-STAGE WORKLIST: stage 0 pushes a node
# and its srcs (running a bottom-up table to a per-node fixed point first),
# stage 1 rebuilds once every src is in `replace` and runs the top-down table,
# stage 2 links the rebuilt node's replacement back to `n`. It carries a
# `waitlist` for a src that is not ready and an `on_stack` set.
#
# The port's is THE SAME FOLD RE-RUN, which is what makes it a FIXPOINT rather
# here rather than left implied:
#
#   * `bottom_up` / `bpm`. Upstream puts `pm` in `self.bpm` and `None` in
#     `self.pm` when `bottom_up=True`, and BOTH drivers then run only the
#     bottom-up table. `uop/ops.bend` -- which this file must not edit -- has
#     no `bpm` and no per-entry bottom-up marker, so there is no second table
#     for the dispatcher's other half to select. `pm_post_sched_cache` is
#     top-down in both ports, so this is INVISIBLE on the fixture and it is a
#     wall upstream, not a silent difference. ops.py:1889.
#   * `enter_calls`. Both drivers skip `n.src[1:]` of a CALL, so the two
#     upstream call sites that pass `enter_calls=True`
#     (`schedule/__init__.py:276`, `codegen/__init__.py:492`) are wrong here.
#     ops.py:1833/1841.
#   * The per-node `seen` set and `BottomUpGate`, which bound the BOTTOM-UP loop
#     the port does not have.
#
# the stop is "the sink index did not move", and it is sound because the arena
# INTERNS. `uop/ops.bend:2530 UOp.make` calls `intern.find` and a HIT returns the
# arena UNTOUCHED, so two passes handing back the same sink INDEX handed back the
# same `Node{op, src, arg, tag}`. The reachable graph is identical,
# `pm_rewrite_m` is a pure function of that graph and of `ctx`, and the next pass
# rebuilds nothing. Index equality here is the interning invariant, not a
# coincidence.
#
# A cap and a fixpoint ARE DISTINGUISHABLE here, and `capped` says which.
# Upstream raises for both -- `REWRITE_STACK_LIMIT` at ops.py:1821 and the
# stalled waitlist at :1883 -- and a Bend def returns a value, so both raise
# sites become one Bool. `capped=True` IS NOT A FIXPOINT and must never be read
# as one. What it does NOT separate is a genuine rewrite CYCLE (R(n)=m,
# R(m)=n) from a chain that merely needs more passes: both are "the sink was
# still moving when the bound ran out", and the port cannot tell them apart
# because it has no `seen` set. So `capped=True` means NOT-CONVERGED and nothing
# finer. The `grw_cap_*` rows REACH the flag, so it is not merely asserted.
#
# WHY ONE DEF AND NOT TWO. The stop test is a Bool and the bound is a Nat, and
# Bend refuses a `match` after any other statement, refuses a `match` on a
# computed value, and refuses a TWO-DEF cycle -- all three measured in
# `grw-loop-probe.bend`. So the `Nat` match is the body's first statement and the
# `Bool.pick` sits inside its two arms. `f` is the shrinking self-call argument,
# so it comes first and every computed argument follows it. `w` is the pass
# result as a `+` RECORD parameter: a TUPLE may be read exactly once (and `+` on
# one is refused outright), while a record parameter reads as many times as the
# arms need.
