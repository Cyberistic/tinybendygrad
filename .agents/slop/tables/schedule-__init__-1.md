<!-- FROM: tinybendygrad/schedule/__init__.bend:1 -->
# BLOCK:
# THE GATE'S EXPECTED ROWS AND THE MUTATION TABLE.
# (The prose of this header was cut in the source; the DATA is here.)
#
# schedule/__init__.bend -- tinygrad/schedule/__init__.py.
#
# THE PORTED PART IS __init__.py:14-80, and it is the WHOLE of the schedule
# linearizer: the three pure helpers and `create_schedule`, the engine's first
# real consumer. `create_schedule` takes a sink UOp and answers the kernel list.
#
# DEFERRED is __init__.py:82-301. The header has now been wrong TWICE, and both
# corrections were measurements:
#
#   1. It gave ONE reason -- "every rule in it is a `graph_rewrite` over the arena
#      with a PYTHON `ctx` DICT" -- and that clause is FALSE: the ctx is a `Data`
#      record of four append-only lists (`CallifyCtx` below), and the two rules
#      named here were ported ON TOP of it.
#   2. It then said the wall left was "the `graph_rewrite` ENGINE is not [ported]".
#      THAT IS ALSO FALSE. `codegen/__init__.bend:292` HAS `graph_rewrite` (the
#      dispatcher, `ops.py:1888-1890`), and it has `pm_post_sched_cache` -- THE
#      EXACT TWO-RULE TABLE FROM `__init__.py:96-101` -- with its own fixture and
#      oracle. The engine exists; what does not exist is one of its two TABLES.
#
# MEASURED 2026-10-31, the deferral is THREE WALLS, each in a DIFFERENT file, and
# each blocks a NAMED set of the 13 pieces of :82-301 the port does not have.
# OF the 23 NAMES in that region, 10 ARE ported (below) AND 13 ARE not:
#
#   missing: create_new_buffer resolve_linear_call pm_resolve_linear_call
#            pm_schedule pm_copy_from_store contiguous_mops_to_view
#            pm_callify_ctx_collect canonicalize_call_body pm_canonicalize_alloc
#            replace_input_buffer pm_replace_buf transform_to_call
#            create_linear_with_vars
#
#   A. STORAGE. There is no `type Buffer is Data` anywhere in the port
#      (`uop/ops.bend:5300` states the wall), so `new_buffer`, `max_numel`,
#      `on_disk`, `contiguous_view` and `param_like` DO NOT EXIST AS DEFS --
#      MEASURED: all five are comment-only. That blocks
#      `create_new_buffer`, `contiguous_mops_to_view` and `replace_input_buffer`.
#
#   B. `bottom_up`. AND the wall is not a BOOL, IT is the shape of the driver.
#      Upstream's `unified_rewrite` (`ops.py:1814-1818`) is ONE MEMOISED STACK
#      TRAVERSAL -- `while stack:` over `(node, stage, new_n)` triples, memoised by
#      `self.replace`. Its TWO STAGES are what make `bottom_up` expressible:
#        stage 0  if `self.bpm is not None`, apply bpm to a FIXED POINT *before*
#                 descending (`ops.py:1824-1838`), and a `BottomUpGate` stops the
#                 descent;
#        stage 1  apply `self.pm` after the srcs are replaced.
#      `bottom_up=True` is just TABLE SELECTION -- `pm=None`, `bpm=pm`.
#
#      THE PORT'S DRIVER IS A DIFFERENT ALGORITHM. `unified_rewrite`
#      (`codegen/__init__.bend:279-280`) runs `walk_rewrite` to a FIXED POINT
#      OUTSIDE the walk (`FIXPOINT_PASSES`, `:162`) -- whole-graph passes, not a
#      per-node stage. So there is no stage 0 for a `bpm` to fire in, and
#      `bottom_up` cannot be added by threading a `Bool`: IT IS A PROPERTY OF
#      THE stack, AND the port has a LOOP.
#
#      AND there is a second `graph_rewrite` THAT *DOES* TAKE `bottom_up`, AND
#      IT IS A STUB. `codegen/decomp/dtype.bend:2044` is
#      `graph_rewrite(x, pm, ctx, bottom_up) -> Maybe<&2, U32>` whose body is
#      `graph_rewrite.wall(x)`, and the wall answers `None{}`. A PARAMETER A DEF
#      ACCEPTS and discards is worse than one it omits: IT reads as though the
#      CAPABILITY IS THERE. MEASURED: no non-stub def in the port takes it.
#      That blocks `canonicalize_call_body` and the `pm_canonicalize_alloc` chain.
#
#   C. `variables()`. NO DEF: `UOp.variables`, `is_variable` are comment-only
#      (`substitute` DOES exist, `uop/upat.bend`). That blocks
#      `resolve_linear_call`'s substitution and everything above it --
#      `transform_to_call` and `create_linear_with_vars`, which are the ENTRY
#      POINTS. A wall a named entry point stands on is not a backlog item.
#
# SO the order is not "SCHEDULER next": A is upstream of c is upstream of the
# ENTRY points, and B is orthogonal. THE storage layer is the next thing, NOT
# THIS FILE. What IS done here is the 10 ported pieces, and
# `gates/schedstore-gate.py` is 50 rows over EIGHT of them (was 25 over two), and
# every row is CPython's printed answer -- and two of the eight were BROKEN when
# their first row read them.
#
# WHAT the engine pass looks like here, since this file is its first consumer.
#
# `create_schedule` is NOT a rewrite. It is a WORKLIST over the arena's own
# toposort, and it is the reason `graph_rewrite` has to be an arena-shaped
# engine rather than a fold: the whole thing is `for u in sink.toposort(gate)`,
# where `gate` is a Python callable (`gate_kernel_sink`) and the body builds four
# dictionaries keyed by UOp. In Bend:
#
#   * the four `dict`s become ASSOCIATION LISTS of `Data` records -- an
#     append-only `List` with an O(n) lookup, exactly what `fold.bend`'s `Table`
#     is and for the same reason (`Array<T>` masks its index, so it cannot grow).
#     `Ctx.kids` is `List<Kid>`, `Ctx.degs` is `List<Dep>`, `Ctx.wrns` is
#     `List<Wrn>` and `Ctx.rds` is `List<Rd>` -- Python's four dicts, in Python's
#     order, and the ORDER MATTERS: `wrns` and `rds` are iterated in insertion
#     order and that order decides the linearization, and `degs`'s insertion
#     order decides the zero-degree queue, which decides the linearization too.
#     So every mutation inserts at the TAIL and none reorders.
#   * `sink.toposort(gate_kernel_sink)` cannot be `O.UOp.toposort`, because
#     ops.bend's toposort has no gate parameter and ops.bend cannot call a def in
#     this file. So `sc_topo` below is a second copy of `Topo.step` with the
#     gate inlined. It reuses ops.bend's `Topo` RECORD, its `Topo.cache_add` and
#     its `Arena.push_srcs`, so the copy is the pop, the `n in cache` test and
#     the gate.
#   * `k.backward_slice` is `O.UOp.toposort_nocalls(fuel, ar, k)` minus self, and
#     since the `t is not k` test runs first, "t is in k.backward_slice" and "t
#     is in that nocalls toposort" are the SAME predicate. That is why `sc_in_bs`
#     below reads a toposort rather than a slice.
#
# FOUR things that are easy to get wrong, all measured against the Python.
#
# 1. `_split_after` KEEPS a kernel list and a dep list, and the second partition
#    DROPS Python's `remaining`. Python raises `AssertionError` when a source is
#    neither CALL/END/AFTER/STORE; a raise is not a value, so `Split` here has
#    exactly Python's two fields and the assertion is a work item:
#    TODO(p3) tinygrad/schedule/__init__.py:28 -- upstream RAISES `AssertionError`
#    there (the builtin, so it has no declaration to cite).
#    Not carrying `remaining` is the price of a total function,
#    and it is the same trade `helpers.bend`'s `unwrap_or` documents. The gate's
#    `split_bad_ks` pins the DROP where Python raises.
# 2. `prev_kernels` is a `set`, but `k not in prev_kernels` is membership, and
#    membership in a set is membership in the list -- so `sc_newks` filters
#    against `Split.ks` directly and builds no set.
# 3. `in_degree.setdefault(k, 0)` is `da(c, k, 0)`: `da` INSERTS a missing key
#    with the added value, so "insert zero if absent" and "add one" are the same
#    def and the insertion lands where Python's `setdefault` lands. The gate's
#    `fx1_zero`/`fx2_zero` rows are the ones that would see a different order.
# 4. THE linearization is not the toposort order. `fx2` in the gate is the
#    fixture for it: three CALLs whose toposort order is Ka,Kb,Kc and whose
#    LINEAR order is Kb,Kc,Ka, because a WAR edge (`__init__.py:59-65`) makes Ka
#    run after the kernel that reads the state Ka supersedes. A gate that only
#    checked "the right kernels are present" would not see it.
#
# THREE properties this file needs from ops.py AND does not get for free.
#
# * `gate_kernel_sink` (ops.py:1915 symbol=gate_kernel_sink) is three lines and its `arg is KernelInfo`
#   is a `match` on `O.Arg`, so `sc_gate` is three defs. It is a def and not a
#   parameter because a Python `Callable` is not a Bend value, and `sc_topo`
#   inlines it -- the same bill `Topo.step` pays for having no gate.
# * `UOp.is_bound_var` (ops.py:1015 symbol=is_bound_var) reads `is_variable` (ops.py:1020), whose
#   last conjunct is `self._shape == ()`. For a PARAM that is ops.py:323 symbol=_shape, which
#   is `image`/`size` off the arg and nothing else -- so it is `fold.bend`'s
#   `param_shape`, NOT the fold table, and no `Folded` is threaded anywhere in
#   this file.  TODO(p3) ops.py:323  `UOp._shape` -- STAYS IN ops.bend.
#   (ops.py:1756 DOES NOT EXIST at the pin: `tinygrad/uop/ops.py` is 1926 lines
#   there.  `_shape` is ops.py:323 and `shape` is ops.py:439.)
# * `UOp.buf_uop` (ops.py:911 symbol=buf_uop) is a fuel fold here and NOT the recursive property
#   it is in Python, because of the two arms that CONSTRUCT:
#       if self.op is Ops.MSELECT: return self.src[0].buf_uop.mselect(self.arg)
#       if self.op is Ops.MSTACK: return UOp(Ops.MSTACK, src=tuple(x.buf_uop for x in self.src))
#   A rule that interns must hand back the ARENA (`Hop{ar, at}` in movement.bend),
#   and threading the arena through a walk that descends its own srcs makes every
#   caller carry it. What IS ported is exact for four of the five arms:
#     - `BUFFER | ALLOC | PARAM` -- the first arm, and the while loop's stop set.
#     - the movement chain -- the while loop, verbatim.
#     - `self.base.op is AFTER` -- the walk does NOT stop at AFTER (AFTER is
#       neither in `GroupOp.Movement` nor DETACH, so `base` is the identity on
#       it), so the walk descends `AFTER.src[0]`, which is what the arm says;
#       and the arm's trailing `.base` is then the identity too, because the walk
#       only ever answers BUFFER/ALLOC/PARAM/STAGE/MSTACK and none of those five
#       is in `GroupOp.Movement` nor is DETACH.
#     - `MSTACK` -- the walk STOPS at MSTACK and Python REBUILDS it, so the two
#       agree exactly when every src's `buf_uop` is that src.
#   MSELECT is the one arm where the walk's answer is wrong rather than merely
#   partial: it descends into `src[0]` and drops the MSELECT wrapper. Both
#   remaining arms are multi-device -- `tinygrad/schedule/multi.py` -- and
#   `create_schedule`'s `buf_uops` line is their only reader.
#
# THE FUEL IS SQUARED IN TWO PLACES, and the reason is worth stating once. A walk
# that cannot revisit a node (every `unwrap`, `buf_uop` and `toposort` here) is
# bounded by `Arena.budget`, which is EXACT. A walk that CAN revisit one is not,
# and there are two: `_states`, whose MSTACK expansion is a MULTISET -- a shared
# subtree is visited once per PATH -- and the Kahn loop, whose children lists can
# hold the same edge twice. Both take `sc_fuel`, the budget squared: exact for the
# tree case, and in the non-tree case tinygrad is itself exponential, so the fuel
# measures Python's cost and not the port's.
#
# NOT PORTED, one line each, with the wall behind it:
# TODO(p3) __init__.py:18 symbol=_states  `_states`' assert -- a raise, as above.
# WALL(p3) __init__.py:28  the AssertionError in _split_after (see above) -- BLOCKED: needs Python's `raise AssertionError`; the port DROPS the invalid src instead (`Split` carries only Python's two fields) and `split_bad_ks` pins the drop.
# WALL(p3) __init__.py:62  `t not in k.backward_slice` is read as a nocalls
#   toposort; that is EXACT, and the header explains why -- NOT A GAP: `sc_in_bs` reads `O.UOp.toposort_nocalls` and `wt_keep` applies `t is not k` FIRST (:885-886), so the two predicates are the SAME.
# TODO(p3) __init__.py:78  `raise RuntimeError("cycle detected in assign graph")`
#   -- a raise, as above. `COUNT_fx*_cyc` in the gate is the observable it guards,
#   and it is 1 for fx2 and fx5 and 0 for fx1, so a cycle is visible as a
#   non-empty answer even though the raise is not.
# wall(p3) ops.py:107     `buf_uop`'s mselect and mstack arms (see above) -- blocked: needs the arena threaded through a walk that constructs (interns) a UOp: mselect is `src[0].buf_uop.mselect(self.arg)` (tinygrad/uop/ops.py:911 symbol=buf_uop) and mstack rebuilds `UOp(MSTACK, ...)` (:925). Both arms are multi-device (`schedule/multi.py`) and read only by `create_schedule`'s `buf_uops` line; the port's walk is a fuel fold that stops at mstack.
# TODO(p3) __init__.py:66-80  the `while queue` loop is a fuel fold, not a while.
#   The queue is a `List` in Python's DEQUE ORDER -- `popleft` is a head pop and
#   `append` is `List.append`, which is `qs ++ [x]` and O(n) -- so the loop's own
#   list is re-wrapped by the BUILTIN and not by a constructor in this file.
#   `z_pick` and `lk.put` say which end each operation is on, because getting
#   either wrong still typechecks and still terminates.
#
# FOUR NEW BEND RULES, all measured here and written up in
# `.agents/slop/notes/bend2-constraints.md`. Every one of them is a refusal.
#
# 1. A `match` NESTED INSIDE A `case h <> t:` LIST ARM IS REFUSED -- for a Bool,
#    a U32 and a List scrutinee alike ("a match on a parameter or field: this
#    name is a def or a consumed binder"). A List arm may hold a CALL but not a
#    `match`. The escapes, both used below: put the decision in a PARAMETER and
#    match it in the def's OWN body (`unwrap.go`, `st.go`), or split the def in
#    two and let exactly one of the pair recurse (`ln_go` / `ln_go.pop`).
# 2. A `match` NESTED INSIDE A `Data`-RECORD ARM is refused for a Bool scrutinee
#    and ACCEPTED for a Nat or a List one. So a two-Bool decision becomes one
#    two-scrutinee `match` (`sp_put`, `st_cls`) -- which is shorter than the pair
#    of nested matches it replaces.
# 3. A self-CALL may not pass a computed argument before the shrinking one. The
#    check is left to right, so `f(x, Bool.or(...), t)` is refused and
#    `f(t, Bool.or(...), x)` is not -- which is why `found` accumulates into the
#    SECOND slot of `ka_go` / `da_go` / `wa_go`.
# 4. A `Bool`-MATCH IS LEGAL IN A NUMERIC ARM, so the `1n+p` fold and its decision
#    can be ONE def with no helper -- which is what every `*.go` here is, and the
#    opposite of the `.step` helper shape ops.bend's `Topo.step` uses. The helper
#    shape is a MUTUAL RECURSION (`go` calls `step`, `step` calls `go`) and
#    declaration order makes one of them a forward reference; the parameter shape
#    has no such cycle.
#
# THE GATE. 109 rows, and EVERY expectation is CPython's printed output: the
# oracle is `.agents/slop/schedport/oracle.py`, which builds the SAME fixtures
# here and runs the PIN's `tinygrad.schedule.create_schedule` on them.  It
# answers 80 of the 109 rows; the other 29 are the port's OWN bookkeeping (the
# arena counts and the four dicts' counts), which CPython has no name for.
# The floor is `oracles/schedule-bodies/BEFORE-rows.rows` (81 rows) and the
# gate is `checks/sb-gate.sh`.
#
#   fx1 `topo_n 19 lin_n 2 lin_op LINEAR marks 12 nsrcs 22
#        lin_src_ops [['SINK','BUFFER'],['SINK','BUFFER']]`
#        counts `n_children 0 n_in_degree 2 n_writes 2 n_reads 3 n_zero 2 cycle 0`
#   fx2 `topo_n 22 lin_n 3 lin_op LINEAR marks 231 nsrcs 222
#        lin_src_ops [['SINK','BUFFER']] * 3`
#        counts `n_children 1 n_in_degree 3 n_writes 3 n_reads 3 n_zero 2 cycle 1`
#   fx3 `lin_n 1 marks 3`, `n_writes 2`, and the write kernel lists sum to 1
#        because AG2 supersedes nothing new
#   fx5 `topo_n 15 lin_n 2 lin_op LINEAR marks 12 nsrcs 23
#        lin_src_ops [['SINK','BUFFER'],['SINK','BUFFER','BUFFER']]`
#        counts `n_children 1 n_in_degree 2 n_writes 2 n_reads 3 n_zero 1 cycle 1`
#
# `fx1_marks=12` and `fx2_marks=231` are THE rows for the linearization: fx2's
# toposort order is Ka,Kb,Kc and its LINEAR order is Kb,Kc,Ka, because a WAR edge
# (__init__.py:59-65) makes Ka run after the kernel that reads the state Ka
# supersedes. A gate that only counted kernels would not see it.
#
# THE MUTATION TABLE. Fifteen mutations, run one at a time against this file, and
# the rows each one moves. The driver is `.agents/slop/notes/`'s pattern list; the
# rows are all of them.
#
#   M1  unwrap ignores the op set                        27 rows
#   M2  split drops AFTER instead of keeping it           1  split_AG3_ds
#   M3  the seed queue is held backwards                  2  fx1_marks fx2_marks
#   M4  in_degree tested BEFORE the decrement             8  fx2_* fx5_*
#   M5  a rebuild scan puts the entry at the TAIL         1  fx1_marks
#   M6  the insert arm ignores that the key was found     4  COUNT_fx2_degs/_cyc
#                                                          fx3_lin_n fx3_marks
#   M7  buf_uop drops STAGE|MSTACK from its stop set       2  bufuop_STAGE/_MSTACK
#   M8  the toposort gate is dropped                     37  (nearly all)
#   M8b the gate is inverted                              37  (nearly all)
#   M9  is_bound_var ignores the val payload              1  bv_Vu
#   M10 the WAR pass ignores the backward_slice test      8  fx5_* COUNT_fx5_*
#   M11 the prev_kernels filter is dropped                1  COUNT_fx3_wrks
#   M12 buf_uop drops STAGE alone                         1  bufuop_STAGE
#   M13 the toposort's `n in cache` test is dropped      30  (nearly all)
#   M14 is_bound_var ignores the addrspace                0  VACUOUS
#   M15 _states expands nothing                           0  VACUOUS
#
# FIVE real bugs were found by this gate, in this order, and each is named at the
# def it lives in: the three rebuild scans put the updated entry at the tail (M5),
# their insert arm added a SECOND entry for a key already present (M6), the Kahn
# loop pushed at the wrong end of the queue and tested `in_degree` before the
# decrement (M3, M4), and pass one's RAW loop never incremented `in_degree` at all
# -- which `COUNT_fx5_zero` caught and which fx1/fx2/fx3 CANNOT, because none of
# them has a RAW edge.
#
# TWO MUTATIONS MOVE NOTHING, and both are reported rather than hidden. M14 needs
# a PARAM whose addrspace is GLOBAL, which no fixture has: `is_bound_var` is only
# ever asked about ALU scalars. M15 needs an MSELECT or MSTACK among the states
# `_states` expands, and no fixture has one either -- `fx4` has an MSTACK but the
# schedule never reads it, because MSTACK only matters to `buf_uop`.
