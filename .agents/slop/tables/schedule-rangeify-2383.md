<!-- FROM: tinybendygrad/schedule/rangeify.bend:2383 -->
# BLOCK:
# the measured mutation table. forty-one textual edits, one at a time, by
# `.agents/slop/rf2-mutate.py`, each diffed as WHOLE `name=value` LINES rather than row
# names -- a name-comparing harness reported 0 for all 30 mutations in one unit and 0 for
# all 68 in another. Raw table: `.agents/slop/rf2-mutations.txt`; the full 41-row table
# with row sets is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# 37 of 41 move a row. M3, M8, M20b, M36 and M38 move nothing and all five are PROOFS:
#  (1) M3 -- `rf_early`'s subset test `and`->`or` makes the reject test VACUOUS
#      (`or(op_in, True{})` is `True{}` while `and(op_in, True{})` is `op_in`). The
#      previous revision's proof of M3 -- "for a ONE-element set the two tests are the
#      same function" -- is FALSE. M3 is a zero NOW because every `.f()` rule re-checks
#      its own pattern, and M36/M38 measure that reason.
#  (2) M8 -- `rf_strip.of` takes `shrink` and `zero` as parameters and its one caller
#      conjoins the SHRINK test in AGAIN, so the dropped `match` arm is unreachable.
#  (3) M20b -- `ct_8`'s reject set `{MSTACK}` is implied by `ct_8_claim`, the rule's own
#      test, which is what ops.py:1477 says the reject set is for.
#  (4) M36 and M38 are a blind spot and its negative, reported not closed. Removing
#      `ct_8`'s self-re-check moves nothing alone, and moves nothing together with the
#      vacuous reject set either, so no fixture in the port as it stands can see the
#      self-check: the two defects it defends against are one defect seen from two ends
#      and each alone is invisible. The pre-self-check measurement in (1) is the
#      evidence that the self-check is load-bearing and it cannot be reproduced by the
#      gate as it now stands. NOT closed with a row that encodes either behaviour.
# M20 is the row the count rows exist for: it deletes the last `PMEntry`, so no tag
# renumbers and `ct_len` is one of only six rows it can move.
# THE WALLS. Every one is a Python fact rather than a choice, and every one is a
# `# WALL(p3)` line, so `rg 'WALL\(p3\)'` is the whole outstanding list. `rg 'NOT PORTED'`
# finds the site for each. - and this sentence used to name `# TODO(p3)` and
# `rg 'TODO\(p3\)'`, WHICH IS FALSE OF THIS FILE -- MEASURED 2026-11-10, `TODO(p3)`
# answers 3 here and all three are prose in this header, while `WALL(p3)` answers 30
# and those are the markers.  The first group is one line per unported body, the second is
# the three whose Python answer is reached anyway (wall and all), and the third is the
# walls read by more than one rule, so they have no single site. The recurring shapes:
# a STAGE's `x.arg` is a `BufferizeOpts` that `ops.bend`'s `Arg` cannot construct, so
# `removable`/`addrspace`/`device` cannot be read at all; `UOp.ranges` is a DICT keyed
# by node built by a RECURSIVE walk that POPS as it goes, and what is missing is the
# KEYED SET WITH REMOVAL; `UOp.base` (ops.py:784) and `UOp.device` (ops.py:890) are the
# same shape of wall; and a `ctx` COUNTER is a `Nat` PARAMETER (done, in
# `renumber_range`) while a `ctx` DICT is an assoc list of `Data` records and NONE of the
# three is written.
# --- the bodies that are NOT PORTED, one line each ----------------------------
# each line names the wall that was found by asking CPython, not by reading the body.
# "LIVE" means CPython rewrites the node: a live rule behind a wall is a WALL ROW, not a
# missing row.
# wall(p3) rangeify.py:24  cleanup_dead_axes     live (measured); arg.removable, ranges, reshape, expand -- blocked: needs `removable` (`ops.bend`'s `Arg` cannot construct a `BufferizeOpts`, so `removable`/`addrspace`/`device` cannot be read at all), `ranges` (`UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal), and the `reshape`/`expand` builders.
# WALL(p3) rangeify.py:50  remove_bufferize      LIVE; a substitute(..., extra_pm=) over a ctx dict -- BLOCKED: needs `UOp.substitute` with `extra_pm`, over a `ctx` DICT is an assoc list of `Data` records and is not written.
# wall(p3) rangeify.py:120  const_like            live on both arms; DType.const + _mop(expand) -- blocked: needs `DType.const` and `_mop(EXPAND)` -- live on both arms.
# wall(p3) rangeify.py:124  after_all_invalid     live and crashes on a rangeless end; _min_max, numel -- blocked: needs `_min_max` to resolve on symbolic bounds, plus `numel`.
# wall(p3) rangeify.py:127  deviceless mstack src ported -- the UOp.device wall is `rf_dev` and it reads -- blocked: needs nothing new for the device half (`rf_dev` reads it); the mstack src half is ported and this line records the split, not a gap.
# WALL(p3) rangeify.py:208  bufferize_to_store    LIVE; commit_dtype, sorted(ranges), ParamArg, next(ctx) -- BLOCKED: needs `commit_dtype`, `sorted(ranges)`, a `ParamArg` the `Arg` sum cannot build, and `next(ctx)`.
# WALL(p3) rangeify.py:259  weak-CAST INDEX       the claim is ported; the cast it must re-add is not -- BLOCKED: needs the CAST it must re-add -- the claim itself is ported.
# WALL(p3) rangeify.py:263  RESHAPE through       UOp.base, apply_movement_op -- BLOCKED: needs `UOp.base` and `apply_movement_op`.
# WALL(p3) rangeify.py:283  debuf                 LocalAddBufferContext.map -- BLOCKED: needs `LocalAddBufferContext.map`.
# WALL(p3) rangeify.py:292  handle_after          LocalAddBufferContext, ranges -- BLOCKED: needs `LocalAddBufferContext` and `ranges`.
# WALL(p3) rangeify.py:305  check_buf_states      buf_uop plus a read_from dict -- BLOCKED: needs `buf_uop` plus a `read_from` dict.
# WALL(p3) rangeify.py:335  split_store           graph_rewrite INSIDE a rule -- BLOCKED: needs `graph_rewrite` INSIDE a rule -- a rewrite that runs another rewrite.
# --- the three whose Python answer is ALREADY REACHED, wall and all ----------
# WALL(p3) rangeify.py:45  gate_substitute       the raise became the 0, exactly -- BLOCKED: NOT A GAP: the raise became the `0` exactly, so the port answers the same thing and the row pins it.
# WALL(p3) rangeify.py:176  _limit_bufs           the one line refuses to fire -- BLOCKED: NOT A GAP: the one line refuses to fire, and the port's answer matches by construction.
# wall(p3) rangeify.py:351  get_kernel_graph      the order is here, the engine is not -- blocked: not a gap: the order is here; the engine that would consume it is not, so this is a downstream unit.
# --- the walls with no single site, and `ops.bend`'s OWN walls ---------------
#  The first two are the same problem `ops.bend` already records at its foot, so they are
#  ONE wall counted from two files, not two.
# WALL(p3) ops.py:470  ended_ranges          ops.bend's own wall -- BLOCKED: ops.bend's own wall, counted from two files -- ONE wall, not two.
# wall(p3) ops.py:483  UOp._ranges           recursive dict, pops as it goes -- blocked: needs the keyed set with removal: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# wall(p3) ops.py:497  UOp.ranges            the property over the above -- blocked: needs `UOp._ranges` above: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# WALL(p3) ops.py:532  substitute            a dvars substitution walk -- BLOCKED: needs a `dvars` substitution walk -- `UOp.substitute`, and the `extra_pm` form adds a second rewriter.
# WALL(p3) ops.py:603  const_like            a dtype plus a Const value -- BLOCKED: needs a dtype plus a Const value; `DType.const` and `_mop(EXPAND)` are the two halves.
# wall(p3) ops.py:784  UOp.base              a recursive property -- blocked: a memoised `recursive_property`: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# wall(p3) ops.py:890  UOp.device            a recursive property -- blocked: a memoised `recursive_property`: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# WALL(p3) ops.py:925  buf_uop               the bufid walk -- BLOCKED: needs the `bufid` walk.
# WALL(p3) ops.py:1104  _min_max              resolve on symbolic bounds -- BLOCKED: needs `_min_max` to resolve on a SYMBOLIC bound; the constant case is ported (17/17 rows).
# WALL(p3) ops.py:1886  to_max_shape          sint.vmax on a symbolic -- BLOCKED: needs `sint.vmax` on a SYMBOLIC shape.
# WALL(p3) indexing.py:57  BufferizeOpts         a frozen dataclass Arg -- BLOCKED: needs a `BufferizeOpts` as an `Arg` arm -- a frozen dataclass `ops.bend`'s `Arg` has no case for.
# WALL(p3) indexing.py:171  apply_movement_op     the movement-op dispatch -- BLOCKED: needs the movement-op dispatch.
# WALL(p3) indexing.py:190  run_rangeify          stage 1 of the nine -- BLOCKED: needs stage 1 of the nine-stage rangeify pipeline.
# WALL(p3) prepare.py:76  pm_mops               3 foreign rules, tags 0-2 -- BLOCKED: needs `pm_mops`, which `schedule/prepare.bend` names in its header and declares no def for; `rf_foreign` answers "no node" rather than inventing a local copy.
#  ... and their three pdict KEYS are PORTED here (they are a Python fact and the
#  engine's lookup is a Python fact), while their BODIES are BLOCKED on
#  `schedule/prepare.bend`, which as of this revision names `pm_mops` in its header and
#  declares no def for it. `rf_foreign` answers "no node" and says so; inventing a local
#  copy of `_mop_index` would be a lie about where the code lives. MEASURED roots:
#  17 (INDEX), 13 (AFTER), 55 (END).
# WALL(p3) ops.py:1339  KernelInfo.estimates  CLOSED 2026-10-30: `ops.bend`'s `KernelInfo`
#  IS UPSTREAM'S SIX FIELDS NOW -- `name, applied_opts, opts_to_apply, estimates, beam,
#  optimized` -- so a Bend value CAN be EQUAL to a Python one. `estimates` is
#  `Maybe<&2, Estimates>` and `Estimates` is `renderer/estimates.bend`'s record, a LEAF,
#  because Bend refuses an import cycle and upstream breaks it under `TYPE_CHECKING`.
#  `ab7_clik_arg` compares against `O.KernelInfo.of()` on both sides and that still holds.
#  WHAT IS STILL NOT TRUE: the port can build NO `KernelInfo` with a non-`None`
#  `estimates`, because upstream's only writer -- `codegen/__init__.py:446` -- is
#  a wall in `codegen/kernel.bend`. so every value the port builds carries
#  `estimates=None` and `optimized=False`, which is upstream's default and not
#  A LIE.
# `movement.bend`'s `hop_self` was inverted, and is not any more. It is kept here
# because the note above `M.hop_self`'s use is only worth reading if the thing it
# records is real. `hop_self.of` used to answer `r` on `True` (the answer IS self, or
# the answer IS none) and `Hop{ar, 0}` on `False`, keeping `self` and dropping a
# genuinely new node -- the inverse of ops.py:1610 and of its own docstring.
#
# MEASURED, running `movement.bend`'s own rows today: `ret_new=0` (the row that read
# fix and names its own inversion, so this file CALLS `M.hop_self` rather than keeping
# fix and names its own inversion, so this file CALLS `M.hop_self` rather than keeping
# a second copy -- see the note at the top of the `*_try` block.
# THE ENGINE. `graph_rewrite` -- ops.py:1886 -- over the port's ARENA.
#
# WHAT UPSTREAM DOES, and the four lines that matter:
#   * `unified_rewrite` (ops.py:1814) walks the graph CHILDREN FIRST.
#   * a node is REBUILT with its children's rewritten srcs (ops.py:1808,
#     `UOp(n.op, new_src, n.arg, n.tag)`).
#   * the table is applied to the REBUILT node and the ANSWER is re-traversed
#     (ops.py:1866-1867), so a rule is a FIXED POINT.
#   * `bottom_up=True` puts the matcher in `self.bpm` (ops.py:1891) and
#     `self.bpm` is applied to the node BEFORE its children are visited
#     (ops.py:1826-1832).
#
# why a sweep and not a dfs. `Arena.nodes` is topologically sorted
# (ops.bend:2774): `UOp.new` is only ever called with srcs already in the
# arena, so every node's src indices are BELOW its own position. INDEX ORDER is
# therefore an order every node's children precede it, which is the order the
# DFS's post-order produces -- and a sweep is the SAME computation with none of
# the mutual recursion Bend refuses. the one thing a sweep cannot reproduce is
# the order upstream's `ctx` counters see, and every rule the port has ported
# is CTX-FREE, so the order is not observable in the port today. It IS
# observable upstream (`itertools.count` at rangeify.py:357 and `:318`), and
# `eng_order_note` is the row that says so.
#
# the bottom-up mode is not implemented, and the CPython oracle is what says
# so: `get_kernel_graph` runs stages 4 and 6 with `bottom_up=True`, and the
# oracle runs the SAME two stages the same way. If the port and CPython agree
# there, the mode is not observable ON THESE FIXTURES -- which is a
# MEASUREMENT and not a claim about the engine.
#
# WHAT THE ENGINE IS NOT. `run_rangeify` (rangeify.py:190, stage 1 of the
# nine), `symbolic` (uop/symbolic.py) and `pm_reduce_simplify`
# (codegen/simplify.py) are TABLES this file does not own, and the engine
# drives the tables it owns. Stage 1 is `Stg{0, Nil{}}` -- an EMPTY table --
# because `run_rangeify` is not ported, and an empty table is the honest
# spelling of "this stage does nothing here".
# THE MAP. An original node index -> the index it BECAME. It is APPENDED and
# the scan keeps the LAST match, so the newest entry wins. EVERY visited node
# is in it, so an absent key means "never visited" and a visited node that did
# not change maps to ITSELF.
# END BLOCK

# the measured mutation table. forty-one textual edits, one at a time, by
# `.agents/slop/rf2-mutate.py`, each diffed as WHOLE `name=value` LINES rather than row
# names -- a name-comparing harness reported 0 for all 30 mutations in one unit and 0 for
# all 68 in another. Raw table: `.agents/slop/rf2-mutations.txt`; the full 41-row table
# with row sets is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# 37 of 41 move a row. M3, M8, M20b, M36 and M38 move nothing and all five are PROOFS:
#  (1) M3 -- `rf_early`'s subset test `and`->`or` makes the reject test VACUOUS
#      (`or(op_in, True{})` is `True{}` while `and(op_in, True{})` is `op_in`). The
#      previous revision's proof of M3 -- "for a ONE-element set the two tests are the
#      same function" -- is FALSE. M3 is a zero NOW because every `.f()` rule re-checks
#      its own pattern, and M36/M38 measure that reason.
#  (2) M8 -- `rf_strip.of` takes `shrink` and `zero` as parameters and its one caller
#      conjoins the SHRINK test in AGAIN, so the dropped `match` arm is unreachable.
#  (3) M20b -- `ct_8`'s reject set `{MSTACK}` is implied by `ct_8_claim`, the rule's own
#      test, which is what ops.py:1477 says the reject set is for.
#  (4) M36 and M38 are a blind spot and its negative, reported not closed. Removing
#      `ct_8`'s self-re-check moves nothing alone, and moves nothing together with the
#      vacuous reject set either, so no fixture in the port as it stands can see the
#      self-check: the two defects it defends against are one defect seen from two ends
#      and each alone is invisible. The pre-self-check measurement in (1) is the
#      evidence that the self-check is load-bearing and it cannot be reproduced by the
#      gate as it now stands. NOT closed with a row that encodes either behaviour.
# M20 is the row the count rows exist for: it deletes the last `PMEntry`, so no tag
# renumbers and `ct_len` is one of only six rows it can move.
# THE WALLS. Every one is a Python fact rather than a choice, and every one is a
# `# WALL(p3)` line, so `rg 'WALL\(p3\)'` is the whole outstanding list. `rg 'NOT PORTED'`
# finds the site for each. - and this sentence used to name `# TODO(p3)` and
# `rg 'TODO\(p3\)'`, WHICH IS FALSE OF THIS FILE -- MEASURED 2026-11-10, `TODO(p3)`
# answers 3 here and all three are prose in this header, while `WALL(p3)` answers 30
# and those are the markers.  The first group is one line per unported body, the second is
# the three whose Python answer is reached anyway (wall and all), and the third is the
# walls read by more than one rule, so they have no single site. The recurring shapes:
# a STAGE's `x.arg` is a `BufferizeOpts` that `ops.bend`'s `Arg` cannot construct, so
# `removable`/`addrspace`/`device` cannot be read at all; `UOp.ranges` is a DICT keyed
# by node built by a RECURSIVE walk that POPS as it goes, and what is missing is the
# KEYED SET WITH REMOVAL; `UOp.base` (ops.py:784) and `UOp.device` (ops.py:890) are the
# same shape of wall; and a `ctx` COUNTER is a `Nat` PARAMETER (done, in
# `renumber_range`) while a `ctx` DICT is an assoc list of `Data` records and NONE of the
# three is written.
# --- the bodies that are NOT PORTED, one line each ----------------------------
# each line names the wall that was found by asking CPython, not by reading the body.
# "LIVE" means CPython rewrites the node: a live rule behind a wall is a WALL ROW, not a
# missing row.
# wall(p3) rangeify.py:24  cleanup_dead_axes     live (measured); arg.removable, ranges, reshape, expand -- blocked: needs `removable` (`ops.bend`'s `Arg` cannot construct a `BufferizeOpts`, so `removable`/`addrspace`/`device` cannot be read at all), `ranges` (`UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal), and the `reshape`/`expand` builders.
# WALL(p3) rangeify.py:50  remove_bufferize      LIVE; a substitute(..., extra_pm=) over a ctx dict -- BLOCKED: needs `UOp.substitute` with `extra_pm`, over a `ctx` DICT is an assoc list of `Data` records and is not written.
# wall(p3) rangeify.py:120  const_like            live on both arms; DType.const + _mop(expand) -- blocked: needs `DType.const` and `_mop(EXPAND)` -- live on both arms.
# wall(p3) rangeify.py:124  after_all_invalid     live and crashes on a rangeless end; _min_max, numel -- blocked: needs `_min_max` to resolve on symbolic bounds, plus `numel`.
# wall(p3) rangeify.py:127  deviceless mstack src ported -- the UOp.device wall is `rf_dev` and it reads -- blocked: needs nothing new for the device half (`rf_dev` reads it); the mstack src half is ported and this line records the split, not a gap.
# WALL(p3) rangeify.py:208  bufferize_to_store    LIVE; commit_dtype, sorted(ranges), ParamArg, next(ctx) -- BLOCKED: needs `commit_dtype`, `sorted(ranges)`, a `ParamArg` the `Arg` sum cannot build, and `next(ctx)`.
# WALL(p3) rangeify.py:259  weak-CAST INDEX       the claim is ported; the cast it must re-add is not -- BLOCKED: needs the CAST it must re-add -- the claim itself is ported.
# WALL(p3) rangeify.py:263  RESHAPE through       UOp.base, apply_movement_op -- BLOCKED: needs `UOp.base` and `apply_movement_op`.
# WALL(p3) rangeify.py:283  debuf                 LocalAddBufferContext.map -- BLOCKED: needs `LocalAddBufferContext.map`.
# WALL(p3) rangeify.py:292  handle_after          LocalAddBufferContext, ranges -- BLOCKED: needs `LocalAddBufferContext` and `ranges`.
# WALL(p3) rangeify.py:305  check_buf_states      buf_uop plus a read_from dict -- BLOCKED: needs `buf_uop` plus a `read_from` dict.
# WALL(p3) rangeify.py:335  split_store           graph_rewrite INSIDE a rule -- BLOCKED: needs `graph_rewrite` INSIDE a rule -- a rewrite that runs another rewrite.
# --- the three whose Python answer is ALREADY REACHED, wall and all ----------
# WALL(p3) rangeify.py:45  gate_substitute       the raise became the 0, exactly -- BLOCKED: NOT A GAP: the raise became the `0` exactly, so the port answers the same thing and the row pins it.
# WALL(p3) rangeify.py:176  _limit_bufs           the one line refuses to fire -- BLOCKED: NOT A GAP: the one line refuses to fire, and the port's answer matches by construction.
# wall(p3) rangeify.py:351  get_kernel_graph      the order is here, the engine is not -- blocked: not a gap: the order is here; the engine that would consume it is not, so this is a downstream unit.
# --- the walls with no single site, and `ops.bend`'s OWN walls ---------------
#  The first two are the same problem `ops.bend` already records at its foot, so they are
#  ONE wall counted from two files, not two.
# WALL(p3) ops.py:470  ended_ranges          ops.bend's own wall -- BLOCKED: ops.bend's own wall, counted from two files -- ONE wall, not two.
# wall(p3) ops.py:483  UOp._ranges           recursive dict, pops as it goes -- blocked: needs the keyed set with removal: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# wall(p3) ops.py:497  UOp.ranges            the property over the above -- blocked: needs `UOp._ranges` above: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# WALL(p3) ops.py:532  substitute            a dvars substitution walk -- BLOCKED: needs a `dvars` substitution walk -- `UOp.substitute`, and the `extra_pm` form adds a second rewriter.
# WALL(p3) ops.py:603  const_like            a dtype plus a Const value -- BLOCKED: needs a dtype plus a Const value; `DType.const` and `_mop(EXPAND)` are the two halves.
# wall(p3) ops.py:784  UOp.base              a recursive property -- blocked: a memoised `recursive_property`: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# wall(p3) ops.py:890  UOp.device            a recursive property -- blocked: a memoised `recursive_property`: `UOp.ranges` is a keyed set built by a recursive walk that pops as it goes, and Bend refuses the mutual recursion; the missing piece is the keyed set with removal.
# WALL(p3) ops.py:925  buf_uop               the bufid walk -- BLOCKED: needs the `bufid` walk.
# WALL(p3) ops.py:1104  _min_max              resolve on symbolic bounds -- BLOCKED: needs `_min_max` to resolve on a SYMBOLIC bound; the constant case is ported (17/17 rows).
# WALL(p3) ops.py:1886  to_max_shape          sint.vmax on a symbolic -- BLOCKED: needs `sint.vmax` on a SYMBOLIC shape.
# WALL(p3) indexing.py:57  BufferizeOpts         a frozen dataclass Arg -- BLOCKED: needs a `BufferizeOpts` as an `Arg` arm -- a frozen dataclass `ops.bend`'s `Arg` has no case for.
# WALL(p3) indexing.py:171  apply_movement_op     the movement-op dispatch -- BLOCKED: needs the movement-op dispatch.
# WALL(p3) indexing.py:190  run_rangeify          stage 1 of the nine -- BLOCKED: needs stage 1 of the nine-stage rangeify pipeline.
# WALL(p3) prepare.py:76  pm_mops               3 foreign rules, tags 0-2 -- BLOCKED: needs `pm_mops`, which `schedule/prepare.bend` names in its header and declares no def for; `rf_foreign` answers "no node" rather than inventing a local copy.
#  ... and their three pdict KEYS are PORTED here (they are a Python fact and the
#  engine's lookup is a Python fact), while their BODIES are BLOCKED on
#  `schedule/prepare.bend`, which as of this revision names `pm_mops` in its header and
#  declares no def for it. `rf_foreign` answers "no node" and says so; inventing a local
#  copy of `_mop_index` would be a lie about where the code lives. MEASURED roots:
#  17 (INDEX), 13 (AFTER), 55 (END).
# WALL(p3) ops.py:1339  KernelInfo.estimates  CLOSED 2026-10-30: `ops.bend`'s `KernelInfo`
#  IS UPSTREAM'S SIX FIELDS NOW -- `name, applied_opts, opts_to_apply, estimates, beam,
#  optimized` -- so a Bend value CAN be EQUAL to a Python one. `estimates` is
#  `Maybe<&2, Estimates>` and `Estimates` is `renderer/estimates.bend`'s record, a LEAF,
#  because Bend refuses an import cycle and upstream breaks it under `TYPE_CHECKING`.
#  `ab7_clik_arg` compares against `O.KernelInfo.of()` on both sides and that still holds.
#  WHAT IS STILL NOT TRUE: the port can build NO `KernelInfo` with a non-`None`
#  `estimates`, because upstream's only writer -- `codegen/__init__.py:446` -- is
#  a wall in `codegen/kernel.bend`. so every value the port builds carries
#  `estimates=None` and `optimized=False`, which is upstream's default and not
#  A LIE.
# `movement.bend`'s `hop_self` was inverted, and is not any more. It is kept here
# because the note above `M.hop_self`'s use is only worth reading if the thing it
# records is real. `hop_self.of` used to answer `r` on `True` (the answer IS self, or
# the answer IS none) and `Hop{ar, 0}` on `False`, keeping `self` and dropping a
# genuinely new node -- the inverse of ops.py:1610 and of its own docstring.
#
# MEASURED, running `movement.bend`'s own rows today: `ret_new=0` (the row that read
# fix and names its own inversion, so this file CALLS `M.hop_self` rather than keeping
# fix and names its own inversion, so this file CALLS `M.hop_self` rather than keeping
# a second copy -- see the note at the top of the `*_try` block.
# THE ENGINE. `graph_rewrite` -- ops.py:1886 -- over the port's ARENA.
#
# WHAT UPSTREAM DOES, and the four lines that matter:
#   * `unified_rewrite` (ops.py:1814) walks the graph CHILDREN FIRST.
#   * a node is REBUILT with its children's rewritten srcs (ops.py:1808,
#     `UOp(n.op, new_src, n.arg, n.tag)`).
#   * the table is applied to the REBUILT node and the ANSWER is re-traversed
#     (ops.py:1866-1867), so a rule is a FIXED POINT.
#   * `bottom_up=True` puts the matcher in `self.bpm` (ops.py:1891) and
#     `self.bpm` is applied to the node BEFORE its children are visited
#     (ops.py:1826-1832).
#
# why a sweep and not a dfs. `Arena.nodes` is topologically sorted
# (ops.bend:2774): `UOp.new` is only ever called with srcs already in the
# arena, so every node's src indices are BELOW its own position. INDEX ORDER is
# therefore an order every node's children precede it, which is the order the
# DFS's post-order produces -- and a sweep is the SAME computation with none of
# the mutual recursion Bend refuses. the one thing a sweep cannot reproduce is
# the order upstream's `ctx` counters see, and every rule the port has ported
# is CTX-FREE, so the order is not observable in the port today. It IS
# observable upstream (`itertools.count` at rangeify.py:357 and `:318`), and
# `eng_order_note` is the row that says so.
#
# the bottom-up mode is not implemented, and the CPython oracle is what says
# so: `get_kernel_graph` runs stages 4 and 6 with `bottom_up=True`, and the
# oracle runs the SAME two stages the same way. If the port and CPython agree
# there, the mode is not observable ON THESE FIXTURES -- which is a
# MEASUREMENT and not a claim about the engine.
#
# WHAT THE ENGINE IS NOT. `run_rangeify` (rangeify.py:190, stage 1 of the
# nine), `symbolic` (uop/symbolic.py) and `pm_reduce_simplify`
# (codegen/simplify.py) are TABLES this file does not own, and the engine
# drives the tables it owns. Stage 1 is `Stg{0, Nil{}}` -- an EMPTY table --
# because `run_rangeify` is not ported, and an empty table is the honest
# spelling of "this stage does nothing here".
# THE MAP. An original node index -> the index it BECAME. It is APPENDED and
# the scan keeps the LAST match, so the newest entry wins. EVERY visited node
# is in it, so an absent key means "never visited" and a visited node that did
# not change maps to ITSELF.
