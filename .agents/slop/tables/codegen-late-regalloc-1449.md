<!-- FROM: tinybendygrad/codegen/late/regalloc.bend:1449 -->
# BLOCK:
# THE MUTATION TABLE, MEASURED. One entry per ported rule: the rule is broken on
# purpose, the interpreted lane is re-run, and the rows that MOVE are listed. A row
# that only one mutation moves is a LOCALISED row and is said to be. A mutation
# that moves NOTHING is a BLIND SPOT and is reported with the reason -- it is not
# closed with a row that agrees with the bug.
#
# Reproduce with `.agents/slop/ra-mutate.py` then `.agents/slop/ra-mutate2.py`,
# which restore this file after every entry; the base is 128 rows and the
# acceptance test is `diff .agents/slop/late-cpython.txt <(./bin/bend ...)`.
#
#   MOVES SOMETHING
#   PSEUDO_OPS: drop BARRIER ........................... rw_tbl_ops, rw_pseudo_n
#   live range: the backward walk becomes forward ..... ra0_lr ra1_lr ra1_a7
#                                                  ra1_spills ra1_before ra2_lr
#                                                  ra2_spills ra2_before
#   live range: the loop-interval append dropped ..... ra2_lr
#   loops: the interval bound flipped ................. ra2_lr
#   loops: max user becomes first user ................ NOTHING (blind spot)
#   dedup(u.src) becomes identity ..................... NOTHING (blind spot)
#   live[v] = alloc(...) dropped ...................... ra0_spills ra0_before
#                                                  ra1_a7 ra1_spills ra1_before
#                                                  ra2_spills ra2_before rw_none
#   alloc: first-wins becomes last-wins .............. ra0_a4 ra0_a7 ra0_spills
#                                                  ra0_before ra1_a4 ra1_a7
#                                                  ra1_spills ra1_before rw_none
#   alloc: free has no priority ....................... NOTHING (blind spot)
#   the END/BACKEDGE use-skip dropped ................ ra2_a5 -- a row APPEARS,
#                                                  which is the shape of the gate
#                                                  ra0_before ra1_a1..a4 ra1_a7
#                                                  ra1_a11 ra1_spills ra1_before
#                                                  ra2_a1 a2 a3 ra2_spills
#                                                  ra2_before rw_none
#   live.get is a zero test again (W5b) .............. ra0_a5 ra0_a6 ra0_a7
#                                                  ra0_spills ra0_before ra1_a5
#                                                  ra1_a6 ra1_a7 ra1_spills
#                                                  ra1_before ra2_spills
#                                                  ra2_before rw_none
#   the i+1 for a non-RANGE def becomes i ............. ra1_a7 ra1_spills
#                                                  ra1_before  -- LOCALISED: only
#                                                  ra1, because only the two-address
#                                                  run reaches that distance
#   two-address: the cons reorder dropped ............ ra1_a7 ra1_spills ra1_before
#                                                  -- LOCALISED, and it is the whole
#                                                  reason ra0 and ra1 are two rows
#   two-address: uses[0] goes last, not first ........ ra1_a2 a3 a4 a6 a7 a10 a11
#                                                  ra1_spills ra1_before
#   two-address: only the head def is reordered ....... ra1_a7 ra1_spills ra1_before
#   prologue: the constraint subset test becomes an OR  ra2_spills ra2_before
#   prologue: live_in[v] is not written ............... ra2_spills ra2_before
#   prologue: live_in is written and live is not ...... ra2_spills ra2_before
#   prologue: the live_ins push is dropped ............. ra2_spills ra2_before
#   prologue: used_in_loop is never filtered .......... NOTHING (blind spot)
#   prologue: the union loses its spill half .......... NOTHING (blind spot)
#   epilogue: the reload condition dropped ............ ra2_spills ra2_before
#   epilogue: it reloads everything ................... ra2_spills ra2_before
#   epilogue: the live_ins pop is dropped ............. NOTHING (blind spot)
#   fill: the spill slot is never recorded ............ ra0_spills ra1_spills
#                                                  ra2_spills rw_none
#   fill: the fill is never recorded .................. ra0_before ra1_before
#                                                  ra2_before rw_none
#   fill: the state is the pre-alloc state again ...... DOES NOT COMPILE (the port
#                                                  dropped `s`, so it is a shape
#                                                  error and not a wrong answer)
#   live.pop becomes a no-op .......................... ra0_spills ra0_before
#                                                  ra1_spills ra1_before
#                                                  ra2_spills ra2_before rw_none
#   reals[i][v] replaces with a whole-list append ..... ra0_a7 ra0_a10 ra1_a7
#                                                  ra1_a10 ra2_a4
#   the pseudo-op `continue` in the live-range walk .. NOTHING (blind spot)
#   the main loop starts at 1 ......................... every ra<t>_a<i>, both
#                                                  ra<t>_before, rw_none
#   rewrite: the pseudo-op answer is not None ......... rw_none
#   rewrite: the tag rewrite is not threaded ......... rw_none
#   rewrite: the spilled-src fills are dropped ........ NOTHING (blind spot)
#   the row order: per-uop rows before the four ...... ORDER ONLY -- every row is
#                                                  still present and correct, which
#                                                  is why the harness compares
#                                                  sequences as well as sets
#   the row sorts by intern index, not by text ....... ra2_a4 -- the ONE row where
#                                                  the two orders differ
#   the register NAME is replaced by its index ........ every ra<t> row, rw_none
#   the row reads an index where a name is due ....... every ra<t>_a<i>
#   the intern table loses v4's `index` field ......... NOTHING (blind spot)
#
# THE BLIND SPOTS, and why each one moves nothing. Nine of them, and every one is a
# FIXTURE LIMIT rather than a row that agrees with a bug:
#   * `dedup(u.src)` -- the fixture's src lists are distinct, so identity and dedup
#     are the same list. A fixture with one src twice would tell them apart.
#   * `max user becomes first user` -- the fixture's only RANGE has exactly ONE user,
#     so `max` and `first` agree.
#   * `free has no priority` -- with the distances stubbed to 0 every candidate ties
#     and `alloc` returns `cons[0]`, and on BOTH fixtures `cons[0]` is also what the
#     real rule answers. The rule is gated by the two first-wins mutations above
#     instead, which is the honest split.
#   * the three `sorted_uses` tiebreaks -- the fixture's two prologue candidates tie
#     on the next-use distance (`lr[k][0]` is 1 and 2, which DISAGREES), and the
#     names `v0`/`v5` agree with that order, so dropping either tiebreak is invisible.
#     A third candidate whose name sorted before its `lr[k][0]` would separate them.
#   * `used_in_loop` is never filtered -- both live vregs at the RANGE are used inside
#     it and `spills` is empty, so the filter removes nothing.
#   * the union loses its spill half -- `spills` is empty at the RANGE, so
#     `live.keys() | spills.keys()` and `live.keys()` are the same list.
#   * the `live_ins` pop -- the stack's depth is 1, so dropping the head and keeping
#     it are the same list.
#   * the pseudo-op `continue` in the live-range walk -- the two pseudo ops carry no
#     defs and their only src is a CONST, so both steps are no-ops on them.
#   * v4's `index` field -- `Register.index` is read only by `sorted_uses`' fourth
#     key component, and fixture `ra0` has no RANGE at all.
#   * `regalloc_rewrite`'s `nsrc` -- the oracle prints `r[1]` and not `r[0]`, and the
#     rewritten srcs live in `r[0]`. This is W5c and it is a WALL, not a fixture
#     limit: no row can see that half of the function, and the header says so.
# END BLOCK

# THE MUTATION TABLE, MEASURED. One entry per ported rule: the rule is broken on
# purpose, the interpreted lane is re-run, and the rows that MOVE are listed. A row
# that only one mutation moves is a LOCALISED row and is said to be. A mutation
# that moves NOTHING is a BLIND SPOT and is reported with the reason -- it is not
# closed with a row that agrees with the bug.
#
# Reproduce with `.agents/slop/ra-mutate.py` then `.agents/slop/ra-mutate2.py`,
# which restore this file after every entry; the base is 128 rows and the
# acceptance test is `diff .agents/slop/late-cpython.txt <(./bin/bend ...)`.
#
#   MOVES SOMETHING
#   PSEUDO_OPS: drop BARRIER ........................... rw_tbl_ops, rw_pseudo_n
#   live range: the backward walk becomes forward ..... ra0_lr ra1_lr ra1_a7
#                                                  ra1_spills ra1_before ra2_lr
#                                                  ra2_spills ra2_before
#   live range: the loop-interval append dropped ..... ra2_lr
#   loops: the interval bound flipped ................. ra2_lr
#   loops: max user becomes first user ................ NOTHING (blind spot)
#   dedup(u.src) becomes identity ..................... NOTHING (blind spot)
#   live[v] = alloc(...) dropped ...................... ra0_spills ra0_before
#                                                  ra1_a7 ra1_spills ra1_before
#                                                  ra2_spills ra2_before rw_none
#   alloc: first-wins becomes last-wins .............. ra0_a4 ra0_a7 ra0_spills
#                                                  ra0_before ra1_a4 ra1_a7
#                                                  ra1_spills ra1_before rw_none
#   alloc: free has no priority ....................... NOTHING (blind spot)
#   the END/BACKEDGE use-skip dropped ................ ra2_a5 -- a row APPEARS,
#                                                  which is the shape of the gate
#                                                  ra0_before ra1_a1..a4 ra1_a7
#                                                  ra1_a11 ra1_spills ra1_before
#                                                  ra2_a1 a2 a3 ra2_spills
#                                                  ra2_before rw_none
#   live.get is a zero test again (W5b) .............. ra0_a5 ra0_a6 ra0_a7
#                                                  ra0_spills ra0_before ra1_a5
#                                                  ra1_a6 ra1_a7 ra1_spills
#                                                  ra1_before ra2_spills
#                                                  ra2_before rw_none
#   the i+1 for a non-RANGE def becomes i ............. ra1_a7 ra1_spills
#                                                  ra1_before  -- LOCALISED: only
#                                                  ra1, because only the two-address
#                                                  run reaches that distance
#   two-address: the cons reorder dropped ............ ra1_a7 ra1_spills ra1_before
#                                                  -- LOCALISED, and it is the whole
#                                                  reason ra0 and ra1 are two rows
#   two-address: uses[0] goes last, not first ........ ra1_a2 a3 a4 a6 a7 a10 a11
#                                                  ra1_spills ra1_before
#   two-address: only the head def is reordered ....... ra1_a7 ra1_spills ra1_before
#   prologue: the constraint subset test becomes an OR  ra2_spills ra2_before
#   prologue: live_in[v] is not written ............... ra2_spills ra2_before
#   prologue: live_in is written and live is not ...... ra2_spills ra2_before
#   prologue: the live_ins push is dropped ............. ra2_spills ra2_before
#   prologue: used_in_loop is never filtered .......... NOTHING (blind spot)
#   prologue: the union loses its spill half .......... NOTHING (blind spot)
#   epilogue: the reload condition dropped ............ ra2_spills ra2_before
#   epilogue: it reloads everything ................... ra2_spills ra2_before
#   epilogue: the live_ins pop is dropped ............. NOTHING (blind spot)
#   fill: the spill slot is never recorded ............ ra0_spills ra1_spills
#                                                  ra2_spills rw_none
#   fill: the fill is never recorded .................. ra0_before ra1_before
#                                                  ra2_before rw_none
#   fill: the state is the pre-alloc state again ...... DOES NOT COMPILE (the port
#                                                  dropped `s`, so it is a shape
#                                                  error and not a wrong answer)
#   live.pop becomes a no-op .......................... ra0_spills ra0_before
#                                                  ra1_spills ra1_before
#                                                  ra2_spills ra2_before rw_none
#   reals[i][v] replaces with a whole-list append ..... ra0_a7 ra0_a10 ra1_a7
#                                                  ra1_a10 ra2_a4
#   the pseudo-op `continue` in the live-range walk .. NOTHING (blind spot)
#   the main loop starts at 1 ......................... every ra<t>_a<i>, both
#                                                  ra<t>_before, rw_none
#   rewrite: the pseudo-op answer is not None ......... rw_none
#   rewrite: the tag rewrite is not threaded ......... rw_none
#   rewrite: the spilled-src fills are dropped ........ NOTHING (blind spot)
#   the row order: per-uop rows before the four ...... ORDER ONLY -- every row is
#                                                  still present and correct, which
#                                                  is why the harness compares
#                                                  sequences as well as sets
#   the row sorts by intern index, not by text ....... ra2_a4 -- the ONE row where
#                                                  the two orders differ
#   the register NAME is replaced by its index ........ every ra<t> row, rw_none
#   the row reads an index where a name is due ....... every ra<t>_a<i>
#   the intern table loses v4's `index` field ......... NOTHING (blind spot)
#
# THE BLIND SPOTS, and why each one moves nothing. Nine of them, and every one is a
# FIXTURE LIMIT rather than a row that agrees with a bug:
#   * `dedup(u.src)` -- the fixture's src lists are distinct, so identity and dedup
#     are the same list. A fixture with one src twice would tell them apart.
#   * `max user becomes first user` -- the fixture's only RANGE has exactly ONE user,
#     so `max` and `first` agree.
#   * `free has no priority` -- with the distances stubbed to 0 every candidate ties
#     and `alloc` returns `cons[0]`, and on BOTH fixtures `cons[0]` is also what the
#     real rule answers. The rule is gated by the two first-wins mutations above
#     instead, which is the honest split.
#   * the three `sorted_uses` tiebreaks -- the fixture's two prologue candidates tie
#     on the next-use distance (`lr[k][0]` is 1 and 2, which DISAGREES), and the
#     names `v0`/`v5` agree with that order, so dropping either tiebreak is invisible.
#     A third candidate whose name sorted before its `lr[k][0]` would separate them.
#   * `used_in_loop` is never filtered -- both live vregs at the RANGE are used inside
#     it and `spills` is empty, so the filter removes nothing.
#   * the union loses its spill half -- `spills` is empty at the RANGE, so
#     `live.keys() | spills.keys()` and `live.keys()` are the same list.
#   * the `live_ins` pop -- the stack's depth is 1, so dropping the head and keeping
#     it are the same list.
#   * the pseudo-op `continue` in the live-range walk -- the two pseudo ops carry no
#     defs and their only src is a CONST, so both steps are no-ops on them.
#   * v4's `index` field -- `Register.index` is read only by `sorted_uses`' fourth
#     key component, and fixture `ra0` has no RANGE at all.
#   * `regalloc_rewrite`'s `nsrc` -- the oracle prints `r[1]` and not `r[0]`, and the
#     rewritten srcs live in `r[0]`. This is W5c and it is a WALL, not a fixture
#     limit: no row can see that half of the function, and the header says so.
