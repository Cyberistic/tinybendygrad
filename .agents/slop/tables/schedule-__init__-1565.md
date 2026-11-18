<!-- FROM: tinybendygrad/schedule/__init__.bend:1565 -->
# BLOCK:
# THE TWELVE -- __init__.py:82-301. THE RULE BODIES, in the order they unblock.
#
# The header deferred this region on THREE clauses, and the measurement in
# `.agents/slop/lintable/06-UNBLOCKED.md` found TWO of the three false, so the
# order below is what the measurement said and not what the header said:
#
#   * C1 "every rule is a graph_rewrite" -- FALSE for FOUR of the fifteen:
#     `is_store_after`, `assert_all_same_devices`, `canonicalize_call_body` and
#     `apply_binds` are plain functions with NO table at all.
#   * C2 "...over the arena with a PYTHON ctx DICT" -- the WEAKER of the two
#     live claims, and it fails twice over. FIVE of the twelve take NO ctx at
#     all (`lower_sink_to_linear`, `copy_kernel_to_store`,
#     `simplify_copy_kernel`, `assert_all_same_devices`, `apply_binds`), and the
#     TWO that do take one take the SAME `CallifyCtx` whose `dict` field is one
#     of four and is not the load-bearing one -- `collect_stores` writes
#     `stores`, a LIST, and never reads `allocs`.
#   * C3, the linear rule table -- held for 8 of 15 and is the WEAKEST claim of
#     the three: 12 were never behind it.
#
# WHAT IS HERE: EIGHT of the twelve, under UPSTREAM NAMES. The four that are
# not, and their `file:line` walls, are at the end of this block. Of the
# remaining three of the fifteen that the table unblocked
# (`create_new_buffer` :90, `resolve_linear_call` :103, `transform_to_call` :261)
# none lives in this file, so the honest count against the DENOMINATOR OF FIFTEEN
# is ELEVEN present and FOUR walls.
#
# `sb-oracle.py` computes every expectation below from CPython. None is typed,
# and `SCHEDULE-BODIES.md` carries the lane comparison.
#
# THE gate for the ctx BODIES is `gates/schedstore-gate.py`, AND it is new
# (2026-10-30). BEFORE it, THIS block'S eight ported bodies had no row
# ANYWHERE: the port emitted 111 rows and 0 of them were `isa_*`, `cs_*` or
# `ca_*`, so a body that no row reads is a body that no gate can go red on --
# and the `ca_slot3` DEFECT below was in the tree the whole time, under a
# header that CLAIMED the opposite. The gate is 25 rows over `is_store_after`,
# `collect_stores` and `canonicalize_alloc`, and it is FALSIFIABLE: both
# reverts were measured and both moved rows.
#
# AND the other five got rows too (2026-10-31). `lower_sink_to_linear`,
# `copy_kernel_to_store`, `simplify_copy_kernel`, `assert_all_same_devices`
# and `apply_binds` were PORTED and had NO ROW, and the gate now carries 25
# MORE (`lsl_*`, `cks_*`, `sck_*`, `ads_*`, `ab_*`) over them -- 50 ROWS AND 2
# LANES in all. THE gate found two more real defects in this block, AND
# BOTH were in bodies that no row read:
#   * `copy_kernel_to_store` REWROTE WITH THE WRONG POLARITY -- `cks_fire` IS
#     upstream's "return None" PREDICATE and it was used as the rewrite
#     trigger, so a SAME-device copy was rewritten and a CROSS-device one was
#     not. The `cks_*` rows see it (6 of 50 move).
#   * `assert_all_same_devices` DEDUPED the nodes and not the devices, so two
#     PARAMS on ONE device counted as TWO and the `>= 2` threshold RAISED on a
#     single-device kernel. The `ads_same_*` rows see it (2 of 50 move).
# 1. `is_store_after` -- __init__.py:217-218. NO ctx, NO table, NO fold, and it
# is the FIRST of the twelve with NO WALL AT ALL:
#
#     def is_store_after(u:UOp) -> bool:
#       return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
#                                     or u.src[1].op is Ops.STORE)
#
# `UOp.unsharded_base` (ops.py:792) is already in ops.bend and the fuel is
# `Arena.budget`, which is EXACT for a walk that cannot revisit a node.
# `sc_src(ar, u, 1)` answers 0 -- the bottom NOOP -- where Python raises
# IndexError, and `isa_SA_E` is the row that pins the rescue onto `src[1]` and
# NOT onto `nsrc`: SA_E is an AFTER with TWO srcs and its second is an END, so
# it answers False.
# END BLOCK

# THE TWELVE -- __init__.py:82-301. THE RULE BODIES, in the order they unblock.
#
# The header deferred this region on THREE clauses, and the measurement in
# `.agents/slop/lintable/06-UNBLOCKED.md` found TWO of the three false, so the
# order below is what the measurement said and not what the header said:
#
#   * C1 "every rule is a graph_rewrite" -- FALSE for FOUR of the fifteen:
#     `is_store_after`, `assert_all_same_devices`, `canonicalize_call_body` and
#     `apply_binds` are plain functions with NO table at all.
#   * C2 "...over the arena with a PYTHON ctx DICT" -- the WEAKER of the two
#     live claims, and it fails twice over. FIVE of the twelve take NO ctx at
#     all (`lower_sink_to_linear`, `copy_kernel_to_store`,
#     `simplify_copy_kernel`, `assert_all_same_devices`, `apply_binds`), and the
#     TWO that do take one take the SAME `CallifyCtx` whose `dict` field is one
#     of four and is not the load-bearing one -- `collect_stores` writes
#     `stores`, a LIST, and never reads `allocs`.
#   * C3, the linear rule table -- held for 8 of 15 and is the WEAKEST claim of
#     the three: 12 were never behind it.
#
# WHAT IS HERE: EIGHT of the twelve, under UPSTREAM NAMES. The four that are
# not, and their `file:line` walls, are at the end of this block. Of the
# remaining three of the fifteen that the table unblocked
# (`create_new_buffer` :90, `resolve_linear_call` :103, `transform_to_call` :261)
# none lives in this file, so the honest count against the DENOMINATOR OF FIFTEEN
# is ELEVEN present and FOUR walls.
#
# `sb-oracle.py` computes every expectation below from CPython. None is typed,
# and `SCHEDULE-BODIES.md` carries the lane comparison.
#
# THE gate for the ctx BODIES is `gates/schedstore-gate.py`, AND it is new
# (2026-10-30). BEFORE it, THIS block'S eight ported bodies had no row
# ANYWHERE: the port emitted 111 rows and 0 of them were `isa_*`, `cs_*` or
# `ca_*`, so a body that no row reads is a body that no gate can go red on --
# and the `ca_slot3` DEFECT below was in the tree the whole time, under a
# header that CLAIMED the opposite. The gate is 25 rows over `is_store_after`,
# `collect_stores` and `canonicalize_alloc`, and it is FALSIFIABLE: both
# reverts were measured and both moved rows.
#
# AND the other five got rows too (2026-10-31). `lower_sink_to_linear`,
# `copy_kernel_to_store`, `simplify_copy_kernel`, `assert_all_same_devices`
# and `apply_binds` were PORTED and had NO ROW, and the gate now carries 25
# MORE (`lsl_*`, `cks_*`, `sck_*`, `ads_*`, `ab_*`) over them -- 50 ROWS AND 2
# LANES in all. THE gate found two more real defects in this block, AND
# BOTH were in bodies that no row read:
#   * `copy_kernel_to_store` REWROTE WITH THE WRONG POLARITY -- `cks_fire` IS
#     upstream's "return None" PREDICATE and it was used as the rewrite
#     trigger, so a SAME-device copy was rewritten and a CROSS-device one was
#     not. The `cks_*` rows see it (6 of 50 move).
#   * `assert_all_same_devices` DEDUPED the nodes and not the devices, so two
#     PARAMS on ONE device counted as TWO and the `>= 2` threshold RAISED on a
#     single-device kernel. The `ads_same_*` rows see it (2 of 50 move).
# 1. `is_store_after` -- __init__.py:217-218. NO ctx, NO table, NO fold, and it
# is the FIRST of the twelve with NO WALL AT ALL:
#
#     def is_store_after(u:UOp) -> bool:
#       return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
#                                     or u.src[1].op is Ops.STORE)
#
# `UOp.unsharded_base` (ops.py:792) is already in ops.bend and the fuel is
# `Arena.budget`, which is EXACT for a walk that cannot revisit a node.
# `sc_src(ar, u, 1)` answers 0 -- the bottom NOOP -- where Python raises
# IndexError, and `isa_SA_E` is the row that pins the rescue onto `src[1]` and
# NOT onto `nsrc`: SA_E is an AFTER with TWO srcs and its second is an END, so
# it answers False.
