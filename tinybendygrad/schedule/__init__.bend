# schedule/__init__.bend -- tinygrad/schedule/__init__.py.
#
# THE PORTED PART IS __init__.py:14-80, and it is the WHOLE of the schedule
# linearizer: the three pure helpers and `create_schedule`, the engine's first
# real consumer. `create_schedule` takes a sink UOp and answers the kernel list.
#
# DEFERRED is __init__.py:82-301, and the reason is one line: every rule in it is
# a `graph_rewrite` over the arena with a PYTHON `ctx` DICT, and `graph_rewrite`'s
# engine pass needs the rule table to be LINEAR (see brief-port.md, THE
# REWRITER) while these rules need the ctx to be a MUTABLE accumulator threaded
# through the pass. `pm_callify_ctx_collect` is the clearest case: its ctx is a
# `CallifyCtx` holding a `list`, a `dict`, a `set` and another `list`. See each
# TODO(p3).
#
# ---------------------------------------------------------------------------
# WHAT THE ENGINE PASS LOOKS LIKE HERE, since this file is its first consumer.
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
# ---------------------------------------------------------------------------
# FOUR THINGS THAT ARE EASY TO GET WRONG, all measured against the Python.
#
# 1. `_split_after` KEEPS A KERNEL LIST AND A DEP LIST, and the second partition
#    DROPS Python's `remaining`. Python raises `AssertionError` when a source is
#    neither CALL/END/AFTER/STORE; a raise is not a value, so `Split` here has
#    exactly Python's two fields and the assertion is `# TODO(p3)
#    __init__.py:29`. Not carrying `remaining` is the price of a total function,
#    and it is the same trade `helpers.bend`'s `unwrap_or` documents. The gate's
#    `split_bad_ks` pins the DROP where Python raises.
# 2. `prev_kernels` is a `set`, but `k not in prev_kernels` is membership, and
#    membership in a set is membership in the list -- so `sc_newks` filters
#    against `Split.ks` directly and builds no set.
# 3. `in_degree.setdefault(k, 0)` is `da(c, k, 0)`: `da` INSERTS a missing key
#    with the added value, so "insert zero if absent" and "add one" are the same
#    def and the insertion lands where Python's `setdefault` lands. The gate's
#    `fx1_zero`/`fx2_zero` rows are the ones that would see a different order.
# 4. THE LINEARIZATION IS NOT THE TOPOSORT ORDER. `fx2` in the gate is the
#    fixture for it: three CALLs whose toposort order is Ka,Kb,Kc and whose
#    LINEAR order is Kb,Kc,Ka, because a WAR edge (`__init__.py:59-65`) makes Ka
#    run after the kernel that reads the state Ka supersedes. A gate that only
#    checked "the right kernels are present" would not see it.
#
# ---------------------------------------------------------------------------
# THREE PROPERTIES THIS FILE NEEDS FROM ops.py AND DOES NOT GET FOR FREE.
#
# * `gate_kernel_sink` (ops.py:1901) is three lines and its `arg is KernelInfo`
#   is a `match` on `O.Arg`, so `sc_gate` is three defs. It is a def and not a
#   parameter because a Python `Callable` is not a Bend value, and `sc_topo`
#   inlines it -- the same bill `Topo.step` pays for having no gate.
# * `UOp.is_bound_var` (ops.py:1023) reads `is_variable` (ops.py:1020), whose
#   last conjunct is `self._shape == ()`. For a PARAM that is ops.py:368, which
#   is `image`/`size` off the arg and nothing else -- so it is `fold.bend`'s
#   `param_shape`, NOT the fold table, and no `Folded` is threaded anywhere in
#   this file. TODO(p3) ops.py:3370 stays in ops.bend.
# * `UOp.buf_uop` (ops.py:925) is a fuel fold here and NOT the recursive property
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
# TODO(p3) __init__.py:22  `_states`' assert -- a raise, as above.
# WALL(p3) __init__.py:29  the AssertionError in _split_after (see above) -- BLOCKED: needs Python's `raise AssertionError`; the port DROPS the invalid src instead (`Split` carries only Python's two fields) and `split_bad_ks` pins the drop.
# WALL(p3) __init__.py:61  `t not in k.backward_slice` is read as a nocalls
#   toposort; that is EXACT, and the header explains why -- NOT A GAP: `sc_in_bs` reads `O.UOp.toposort_nocalls` and `wt_keep` applies `t is not k` FIRST (:885-886), so the two predicates are the SAME.
# TODO(p3) __init__.py:79  `raise RuntimeError("cycle detected in assign graph")`
#   -- a raise, as above. `COUNT_fx*_cyc` in the gate is the observable it guards,
#   and it is 1 for fx2 and fx5 and 0 for fx1, so a cycle is visible as a
#   non-empty answer even though the raise is not.
# WALL(p3) ops.py:925     `buf_uop`'s MSELECT and MSTACK arms (see above) -- BLOCKED: needs the arena threaded through a walk that CONSTRUCTS (interns) a UOp: MSELECT is `src[0].buf_uop.mselect(self.arg)` (tinygrad/uop/ops.py:924) and MSTACK rebuilds `UOp(MSTACK, ...)` (:925). Both arms are multi-device (`schedule/multi.py`) and read only by `create_schedule`'s `buf_uops` line; the port's walk is a fuel fold that STOPS at MSTACK.
# TODO(p3) __init__.py:66-80  the `while queue` loop is a fuel fold, not a while.
#   The queue is a `List` in Python's DEQUE ORDER -- `popleft` is a head pop and
#   `append` is `List.append`, which is `qs ++ [x]` and O(n) -- so the loop's own
#   list is re-wrapped by the BUILTIN and not by a constructor in this file.
#   `z_pick` and `lk.put` say which end each operation is on, because getting
#   either wrong still typechecks and still terminates.
#
# ---------------------------------------------------------------------------
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
# 3. A SELF-CALL MAY NOT PASS A COMPUTED ARGUMENT BEFORE THE SHRINKING ONE. The
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
# ---------------------------------------------------------------------------
# THE GATE. 71 rows, and EVERY expectation is the printed output of
# `.agents/slop/notes/sched-truth.py` (fx1, fx2, fx3, the helper rows) or of
# `python3` running `tinygrad.schedule.create_schedule` on the fixtures built
# here (fx5). Both lanes print the same 71 lines.
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
# ---------------------------------------------------------------------------
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
# FIVE REAL BUGS WERE FOUND BY THIS GATE, in this order, and each is named at the
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

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE READERS. `ops.bend`'s own, wrapped, because every def here reads the arena
# and a rule that forgets to thread it is the bug this file exists to prevent.
# ===========================================================================
def sc_op(ar: O.Arena, i: U32) -> O.Op:
  O.Arena.op(ar, i)

def sc_arg(ar: O.Arena, i: U32) -> O.Arg:
  O.Arena.arg(ar, i)

def sc_tag(ar: O.Arena, i: U32) -> O.Tag:
  O.Arena.tag(ar, i)

def sc_src(ar: O.Arena, i: U32, n: U32) -> U32:
  O.Arena.src(ar, i, n)

def sc_src0(ar: O.Arena, i: U32) -> U32:
  O.Arena.src0(ar, i)

def sc_srcs(ar: O.Arena, i: U32) -> List<&2, U32>:
  O.Arena.srcs(ar, i)

def sc_src_from(ar: O.Arena, i: U32, k: U32) -> List<&2, U32>:
  O.Arena.src_from(ar, i, k)

def sc_nsrc(ar: O.Arena, i: U32) -> U32:
  O.Arena.nsrc(ar, i)

def sc_is(ar: O.Arena, i: U32, want: O.Op) -> Bool:
  O.eq_op(sc_op(ar, i), want)

# THE FOUR OP SETS the Python names, as PREDICATES over the node. Python spells
# them inline `s.op not in {...}`; ops.bend's `op_in` is a list membership test
# and a list is an allocation per call, so each set is a two-or-three way
# `Bool.or`, which is also how the Python reads. `_unwrap_src`'s set is the
# UNION of the first two, which is why the loop condition names both.
def sc_is_after(ar: O.Arena, i: U32) -> Bool:
  sc_is(ar, i, O.OpsAFTER{})

def sc_is_state(+ar: O.Arena, +i: U32) -> Bool:
  Bool.or(sc_is(ar, i, O.OpsBUFFER{}),
    Bool.or(sc_is(ar, i, O.OpsALLOC{}), sc_is(ar, i, O.OpsPARAM{})))

def sc_is_state5(+ar: O.Arena, +i: U32) -> Bool:
  Bool.or(sc_is_after(ar, i), sc_is_state(ar, i))

def sc_is_multi(+ar: O.Arena, +i: U32) -> Bool:
  Bool.or(sc_is(ar, i, O.OpsMSELECT{}), sc_is(ar, i, O.OpsMSTACK{}))

def sc_is_kernel(+ar: O.Arena, +i: U32) -> Bool:
  Bool.or(sc_is(ar, i, O.OpsCALL{}), sc_is(ar, i, O.OpsEND{}))

def sc_is_buf_uop(+ar: O.Arena, +i: U32) -> Bool:
  Bool.or(sc_is_state(ar, i), Bool.or(sc_is(ar, i, O.OpsSTAGE{}), sc_is(ar, i, O.OpsMSTACK{})))

# `Arena.budget` squared -- see the FUEL paragraph in the header. Only the walks
# that can revisit a node take this one.
def sc_fuel(+ar: O.Arena) -> Nat:
  Nat.mul(O.Arena.budget(ar), O.Arena.budget(ar))

# ---------------------------------------------------------------------------
# TWO LOCAL READERS, `ops.py:562 UOp.body` and `ops.py:622 UOp.store`, and the
# reason they are HERE is the same one `sc_topo` has: the reader this file needs
# was not reachable from `ops.bend`, and `ops.bend` cannot call a def in this
# file. MEASURED, not assumed: `uop/ops.bend` was 8313 lines with 1896-era
# `UOp.body` and `UOp.store` present when this block was written (17:47), and a
# concurrent unit took it to 6306 lines with BOTH defs GONE (`grep -cE '^def
# UOp\.(body|store)\(' uop/ops.bend` answers 0/0). Every other reader this block
# uses -- `UOp.unsharded_base`, `UOp.toposort`, `UOp.new`, `eq_op`, `eq_dev`,
# `ParamArg.slot`, `ParamArg.device`, `CallInfo.precompile`, `Arena.src0`,
# `Arena.src_from`, `Arena.budget`, `Found.ar`, and all four `Ops` constructors
# -- SURVIVED that edit, so these two are the whole of the damage.
#
# `sc_body` is `if self.op is not Ops.CALL: raise; return self.src[0]`, and the
# `None{}` is the raise -- the same spelling `UOp.body`'s own `None{}` was for.
# `sc_store` is `UOp.new(ar, OpsSTORE, (self, val) or (self, val, gate),
# ANone, TNone)` with the gate folded, and `g_body` in this file's own gate
# already builds a STORE by hand, so this is that literal made a def.
#   TODO(p3) ops.py:562  `UOp.body`  -- LOCAL COPY; ops.bend has no def.
#   TODO(p3) ops.py:622  `UOp.store` -- LOCAL COPY; ops.bend has no def.
# ---------------------------------------------------------------------------
def sc_body.of(op: O.Op, src0: U32) -> Maybe<&2, U32>:
  match op:
    case O.OpsCALL{}: Some{src0}
    case _          : None{}

def sc_body(+ar: O.Arena, +self: U32) -> Maybe<&2, U32>:
  sc_body.of(sc_op(ar, self), sc_src0(ar, self))

def sc_store.of(gate: Maybe<&2, U32>, +self: U32, +val: U32) -> List<&2, U32>:
  match gate:
    case Some{g}: [self, val, g]
    case None{} : [self, val]

def sc_store(ar: O.Arena, +self: U32, +val: U32, gate: Maybe<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsSTORE{}, sc_store.of(gate, self, val), O.ANone{}, O.TNone{})

# ===========================================================================
# `_unwrap_src` -- __init__.py:14-16. The one loop in the first 30 lines:
#
#     while len(s.src) and s.op not in {AFTER, BUFFER, ALLOC, PARAM, MSELECT,
#                                       MSTACK}: s = s.src[0]
#
# A `while` is a fuel fold here, and the fuel is the FIRST parameter because the
# self-call must be decreasing left to right. `sc_unwrap` passes
# `Arena.budget`, which is EXACT for a walk that cannot revisit a node.
# ===========================================================================
def sc_go(+ar: O.Arena, +s: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(sc_nsrc(ar, s))),
    Bool.not(Bool.or(sc_is_state5(ar, s), sc_is_multi(ar, s))))

def unwrap.go(fuel: Nat, go: Bool, +ar: O.Arena, +s: U32) -> U32:
  match fuel:
    case 0n   : s
    case 1n+p :
      match go:
        case True{} : unwrap.go(p, sc_go(ar, sc_src0(ar, s)), ar, sc_src0(ar, s))
        case False{}: s

def sc_unwrap(+ar: O.Arena, +s: U32) -> U32:
  unwrap.go(O.Arena.budget(ar), sc_go(ar, s), ar, s)

# ===========================================================================
# `buf_uop`'s while loop -- ops.py:931. `unwrap.go`'s shape with a WIDER stop
# set, and the header says why that is exact for four of the five arms.
# ===========================================================================
def sc_buf_go(+ar: O.Arena, +i: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(sc_nsrc(ar, i))), Bool.not(sc_is_buf_uop(ar, i)))

def buf.go(fuel: Nat, go: Bool, +ar: O.Arena, +s: U32) -> U32:
  match fuel:
    case 0n   : s
    case 1n+p :
      match go:
        case True{} : buf.go(p, sc_buf_go(ar, sc_src0(ar, s)), ar, sc_src0(ar, s))
        case False{}: s

def sc_buf_uop(+ar: O.Arena, +s: U32) -> U32:
  buf.go(O.Arena.budget(ar), sc_buf_go(ar, s), ar, s)

# ===========================================================================
# `_states` -- __init__.py:19-23:
#
#     s = _unwrap_src(s)
#     if s.op in {MSELECT, MSTACK}: return [st for ss in s.src for st in _states(ss)]
#     assert s.op in {AFTER, BUFFER, ALLOC, PARAM}
#     return [s]
#
# ONE def with the worklist threaded, because Bend refuses the mutual recursion
# this shape needs (constraints 1.5): the pop, the multi test and the push are
# match ARMS of one fold and not three defs. `todo` is a STACK, so the push is
# `srcs ++ todo` and NOT reversed -- `ops.bend`'s `Arena.push_srcs` un-reverses
# its own input the same way, and `st_push` is that def's twin.
# ===========================================================================
# THREE classes, TWO-SCRUTINEE, and NO NESTED MATCH. Both refusals measured in
# bend 2.0.34 forced this shape: a `match` inside a `case h <> t:` LIST arm is
# refused (for a Bool, a U32 and a List scrutinee alike), so the POP cannot live
# in the same arm as the decision. Hence the popped node and the rest are
# PARAMETERS and the terminator is a CLASS, not a `Nil{}` arm.
#
#   0  MSELECT/MSTACK with at least one src -- push its srcs
#   1  an anchor -- append it
#   2  the todo ran dry -- stop
#
# `case 2` is the bottom node, which `st_hd` answers for an empty list. `st_hd` is
# also why class 0 carries the `nsrc` guard: an MSTACK/MSELECT with no srcs would
# otherwise push nothing and loop on the bottom forever. Python cannot reach it
# -- `UOp.mstack` returns `self` when given no srcs, so a real MSTACK always has
# one -- so the guard is the honesty, not the fidelity.
def st_cls.n(n: U32) -> U32:
  match n:
    case 0: 1
    case _: 0

def st_cls(z: Bool, multi: Bool, n: U32) -> U32:
  match z multi:
    case True{}  _       : 2
    case False{} True{}  : st_cls.n(n)
    case False{} False{} : 1

def st_cl(+ar: O.Arena, +u: U32) -> U32:
  st_cls(U32.is_zero(u), sc_is_multi(ar, u), sc_nsrc(ar, u))

def st_hd(t: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.head(&2, U32, t), 0)

def st.go(fuel: Nat, cls: U32, +ar: O.Arena, +u: U32, +t: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel cls:
    case 0n   _     : acc
    case 1n+p 0     : st.go(p, st_cl(ar, sc_src(ar, u, 0)), ar, sc_src(ar, u, 0),
                           List.append(&2, U32, sc_srcs(ar, u), t), acc)
    case 1n+p 1     : st.go(p, st_cl(ar, st_hd(t)), ar, st_hd(t),
                           List.drop(&2, U32, t, 1n), List.append(&2, U32, acc, [u]))
    case _    _     : acc

def sc_states(fuel: Nat, +ar: O.Arena, +s: U32) -> List<&2, U32>:
  st.go(fuel, st_cl(ar, sc_unwrap(ar, s)), ar, sc_unwrap(ar, s), Nil{}, Nil{})

# ===========================================================================
# `_split_after` -- __init__.py:25-30. TWO `partition` calls become ONE walk,
# which is exact because the second only sees what the first kept: a src is a
# kernel, an AFTER, or one of the DROPPED, and the dropped are precisely the
# STOREs and Python's `invalid`.
# ===========================================================================
type Split is Data:
  Split{ks: List<&2, U32>, ds: List<&2, U32>}

def Split.ks(x: Split) -> List<&2, U32>:
  match x:
    case Split{ks, ds}: ks

def Split.ds(x: Split) -> List<&2, U32>:
  match x:
    case Split{ks, ds}: ds

# THREE-WAY, so `sp_add` matches ONCE. A `Bool`-parameter `match` nested in a
# `Data`-record `match` arm is REFUSED in bend 2.0.34 ("a match on a parameter
# or field: this name is a def or a consumed binder"), while the `Nat`- and
# `List`-arm nests are accepted -- measured, and it is why the fold below is a
# `U32` selector and not two nested matches.
def sp_put(ker: Bool, aft: Bool) -> U32:
  match ker aft:
    case True{}  _       : 0
    case False{} True{}  : 1
    case False{} False{} : 2

def sp_add(cls: U32, +s: U32, ks: List<&2, U32>, ds: List<&2, U32>) -> Split:
  match cls:
    case 0: Split{List.append(&2, U32, ks, [s]), ds}
    case 1: Split{ks, List.append(&2, U32, ds, [s])}
    case _: Split{ks, ds}

def sp_step(+ar: O.Arena, +s: U32, +sp: Split) -> Split:
  sp_add(sp_put(sc_is_kernel(ar, s), sc_is_after(ar, s)), s, Split.ks(sp), Split.ds(sp))

def sp_go(+ar: O.Arena, ss: List<&2, U32>, +sp: Split) -> Split:
  match ss:
    case Nil{}      : sp
    case +s <> rest : sp_go(ar, rest, sp_step(ar, s, sp))

def sc_split(+ar: O.Arena, +after: U32) -> Split:
  sp_go(ar, sc_src_from(ar, after, 1), Split{Nil{}, Nil{}})

# ===========================================================================
# `gate_kernel_sink` -- ops.py:1909 -- and the second copy of `Topo.step`.
#
#     if node in cache: continue                      <- sc_topo.seen
#     if not visited: if gate(node): push(n, True); push srcs
#     else: cache[node] = None                        <- O.Topo.cache_add
#
# `sc_topo` reuses ops.bend's `Topo` RECORD and `Arena.push_srcs`, so the only
# thing it copies is the loop.
# ===========================================================================
def sc_gate.ker(arg: O.Arg) -> Bool:
  match arg:
    case O.AKernel{ki}: True{}
    case _            : False{}

def sc_gate.of(op: O.Op, arg: O.Arg) -> Bool:
  match op arg:
    case O.OpsLINEAR{} _ : False{}
    case O.OpsSINK{} a   : True{}
    case _ _             : True{}

def sc_gate(+ar: O.Arena, +i: U32) -> Bool:
  sc_gate.of(sc_op(ar, i), sc_arg(ar, i))

def sc_topo.cx(rest: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match t:
    case O.Topo{cache, stack, calls}: O.Topo{cache, rest, calls}

def sc_topo.keep2(ar: O.Arena, +n: U32, cache: List<&2, U32>, calls: Bool, rest: List<&2, O.Frame>, ok: Bool) -> O.Topo:
  match ok:
    case True{} : O.Topo{cache, O.Arena.push_srcs(sc_srcs(ar, n), O.Frame{n, True{}} <> rest), calls}
    case False{}: O.Topo{cache, rest, calls}

def sc_topo.keep(ok: Bool, ar: O.Arena, +n: U32, rest: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match t:
    case O.Topo{cache, stack, calls}: sc_topo.keep2(ar, n, cache, calls, rest, ok)

def sc_topo.vis2(visited: Bool, +ar: O.Arena, +n: U32, rest: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match visited:
    case True{} : O.Topo.cache_add(n, sc_topo.cx(rest, t))
    case False{}: sc_topo.keep(sc_gate(ar, n), ar, n, rest, t)

def sc_topo.seen(seen: Bool, visited: Bool, +ar: O.Arena, +n: U32, rest: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match seen:
    case True{} : t
    case False{}: sc_topo.vis2(visited, ar, n, rest, t)

def sc_topo.vis(+ar: O.Arena, +n: U32, visited: Bool, +rest: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match t:
    case O.Topo{+cache, stack, calls}:
      sc_topo.seen(List.contains(U32, U32.is_eq, cache, n), visited, ar, n, rest, O.Topo{cache, rest, calls})

def sc_topo.pop(+ar: O.Arena, stack: List<&2, O.Frame>, t: O.Topo) -> O.Topo:
  match stack:
    case Nil{}                     : t
    case O.Frame{n, visited} <> st : sc_topo.vis(ar, n, visited, st, t)

def sc_topo(+ar: O.Arena, t: O.Topo) -> O.Topo:
  match t:
    case O.Topo{cache, +stack, calls}: sc_topo.pop(ar, stack, O.Topo{cache, stack, calls})

def sc_topo.go(fuel: Nat, +ar: O.Arena, t: O.Topo) -> List<&2, U32>:
  match fuel:
    case 0n   : O.Topo.cache_of(t)
    case 1n+p : sc_topo.go(p, ar, sc_topo(ar, t))

def sc_topo_of(fuel: Nat, +ar: O.Arena, +self: U32) -> List<&2, U32>:
  sc_topo.go(fuel, ar, sc_topo(ar, O.Topo{Nil{}, List.append(&2, O.Frame, Nil{}, [O.Frame{self, False{}}]), True{}}))

# ===========================================================================
# `UOp.is_bound_var` -- ops.py:1023 -- which is `is_variable` (ops.py:1020) plus
# `self.arg.val is not None`. `is_variable`'s conjuncts are the op test, an
# `AParam` test, `vmin_vmax is not None`, `addrspace is ALU` and `_shape == ()`,
# and the last is ops.py:368, which for a PARAM is `image`/`size` off the arg and
# nothing else. So it is `fold.bend`'s `param_shape` and NOT the fold table.
# ===========================================================================
def sc_val.some(arg: O.Arg) -> Bool:
  match arg:
    case O.AParam{pa}: Maybe.is_some(&2, O.Const, O.ParamArg.val(pa))
    case _           : False{}

def sc_var.pa(arg: O.Arg, shape: List<&2, O.Sint>) -> Bool:
  match arg:
    case O.AParam{+pa}:
      Bool.and(Maybe.is_some(&2, O.PyRange, O.ParamArg.vmin_vmax(pa)),
        Bool.and(O.eq_addr(O.ParamArg.addrspace(pa), S.Aalu{}), F.is_empty(shape)))
    case _: False{}

def sc_var.of(op: O.Op, arg: O.Arg, shape: List<&2, O.Sint>) -> Bool:
  match op:
    case O.OpsPARAM{}: sc_var.pa(arg, shape)
    case _           : False{}

def sc_is_bound_var(+ar: O.Arena, +i: U32) -> Bool:
  Bool.and(sc_var.of(sc_op(ar, i), sc_arg(ar, i), F.param_shape(sc_arg(ar, i))), sc_val.some(sc_arg(ar, i)))

# `t not in k.backward_slice` -- ops.py:1378 is `toposort(enter_calls=False)` minus
# self, and the `t is not k` test runs FIRST, so self may stay in the list.
def sc_in_bs(+ar: O.Arena, +k: U32, +t: U32) -> Bool:
  List.contains(U32, U32.is_eq, O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, k), t)

# ===========================================================================
# THE FOUR DICTS. Python's `dict[UOp, X]` is a `List<&2, X>` of one-key records,
# the lookup is a linear scan and the write is a rebuild -- the same bill
# `Kahn.get` in fold.bend pays for its `List` table.
#
#   children: dict[UOp, list[UOp]]                         -> List<Kid>
#   in_degree: dict[UOp, int]                              -> List<Dep>
#   writes: dict[UOp, list[tuple[UOp, tuple[UOp, ...]]]]   -> List<Wrn>
#   reads: list[tuple[UOp, UOp, UOp]]                      -> List<Rd>
# ===========================================================================
type Kid is Data:
  Kid{k: U32, vs: List<&2, U32>}

type Dep is Data:
  Dep{k: U32, d: U32}

type Wrt is Data:
  Wrt{a: U32, ks: List<&2, U32>}

type Wrn is Data:
  Wrn{s: U32, vs: List<&2, Wrt>}

type Rd is Data:
  Rd{u: U32, k: U32, s: U32}

type Ctx is Data:
  Ctx{kids: List<&2, Kid>, degs: List<&2, Dep>, wrns: List<&2, Wrn>, rds: List<&2, Rd>}

def Ctx.of(kids: List<&2, Kid>, degs: List<&2, Dep>, wrns: List<&2, Wrn>, rds: List<&2, Rd>) -> Ctx:
  Ctx{kids, degs, wrns, rds}

def Ctx.kids(x: Ctx) -> List<&2, Kid>:
  match x:
    case Ctx{kids, degs, wrns, rds}: kids

def Ctx.degs(x: Ctx) -> List<&2, Dep>:
  match x:
    case Ctx{kids, degs, wrns, rds}: degs

def Ctx.wrns(x: Ctx) -> List<&2, Wrn>:
  match x:
    case Ctx{kids, degs, wrns, rds}: wrns

def Ctx.rds(x: Ctx) -> List<&2, Rd>:
  match x:
    case Ctx{kids, degs, wrns, rds}: rds

# `children.get(k, [])`
def kg_pick(hit: Bool, acc: List<&2, U32>, vs: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{} : vs
    case False{}: acc

def kg_go(+ks: List<&2, Kid>, +k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}          : acc
    case Kid{j, vs} <> t: kg_go(t, k, kg_pick(U32.is_eq(j, k), acc, vs))

def kg(c: Ctx, +k: U32) -> List<&2, U32>:
  kg_go(Ctx.kids(c), k, Nil{})

# `writes.get(s, [])`
def wg_pick(hit: Bool, acc: List<&2, Wrt>, vs: List<&2, Wrt>) -> List<&2, Wrt>:
  match hit:
    case True{} : vs
    case False{}: acc

def wg_go(+ws: List<&2, Wrn>, +s: U32, acc: List<&2, Wrt>) -> List<&2, Wrt>:
  match ws:
    case Nil{}           : acc
    case Wrn{j, vs} <> t : wg_go(t, s, wg_pick(U32.is_eq(j, s), acc, vs))

def wg(c: Ctx, +s: U32) -> List<&2, Wrt>:
  wg_go(Ctx.wrns(c), s, Nil{})

# `in_degree.get(k, 0)`
def dg_pick(hit: Bool, acc: U32, d: U32) -> U32:
  match hit:
    case True{} : d
    case False{}: acc

def dg_go(+ds: List<&2, Dep>, +k: U32, acc: U32) -> U32:
  match ds:
    case Nil{}          : acc
    case Dep{j, d} <> t : dg_go(t, k, dg_pick(U32.is_eq(j, k), acc, d))

def dg(c: Ctx, +k: U32) -> U32:
  dg_go(Ctx.degs(c), k, 0)

# `children.setdefault(t, []).append(k)`: insert the key if it is missing, append
# if it is not. `ka` is also the whole of `in_degree[t] += 1`'s partner in the
# WAR pass, where the key is `k` and the appended value is `t`.
# THE TWO RULES EVERY REBUILD SCAN IN THIS FILE FOLLOWS, and both were bugs
# before they were rules:
#
#   1. the entry goes back IN FRONT of the rebuilt tail. `List.append(a, A, xs,
#      ys)` is `xs ++ ys`, so `[new] ++ r` and NOT `r ++ [new]`. The second put
#      every updated key at the END of the list.
#   2. the `Nil{}` arm INSERTS the key only if the walk did not already find it,
#      so `found` accumulates down the tail. Without that, `in_degree[k] += 1`
#      left a SECOND entry for `k` at the end and fx2 grew five `in_degree`
#      entries for three kernels.
#
# `COUNT_fx*_degs`, `COUNT_fx*_zero` and `fx2_marks` are the rows that see both.
# `children.setdefault(KEY, []).append(VAL)`, so `ka`'s two U32s are the KEY and
# the appended VALUE -- and THE TWO CALL SITES DISAGREE, which is the whole trap:
#   RAW  `children.setdefault(t, []).append(k)`   __init__.py:55 -> `ka(c, t, k)`
#   WAR  `children.setdefault(k, []).append(t)`   __init__.py:64 -> `ka(c, k, t)`
# Reading the WAR line as the RAW one made `children[Kb] = [Kb]` -- a SELF edge --
# and `in_degree[Kb] -= 1` then decremented a degree that was already zero, the
# Kahn loop stopped draining and `fx2_lin_n` ran to the fuel. `fx2_marks=231` and
# `COUNT_fx2_kidn=1` are the rows that see it.
def ka_tail(found: Bool, key: U32, val: U32) -> List<&2, Kid>:
  match found:
    case True{} : Nil{}
    case False{}: [Kid{key, [val]}]

def ka_pick(hit: Bool, r: List<&2, Kid>, j: U32, vs: List<&2, U32>, val: U32) -> List<&2, Kid>:
  match hit:
    case True{} : List.append(&2, Kid, [Kid{j, List.append(&2, U32, vs, [val])}], r)
    case False{}: List.append(&2, Kid, [Kid{j, vs}], r)

def ka_go(+ks: List<&2, Kid>, found: Bool, +key: U32, +val: U32) -> List<&2, Kid>:
  match ks:
    case Nil{}          : ka_tail(found, key, val)
    case Kid{j, vs} <> t:
      r = ka_go(t, Bool.or(found, U32.is_eq(j, key)), key, val)
      ka_pick(U32.is_eq(j, key), r, j, vs, val)

def ka(+c: Ctx, key: U32, val: U32) -> Ctx:
  Ctx.of(ka_go(Ctx.kids(c), False{}, key, val), Ctx.degs(c), Ctx.wrns(c), Ctx.rds(c))

# the same, for a LIST of keys, IN ORDER -- the order is what the Kahn loop pops.
def km_go(+ts: List<&2, U32>, +c: Ctx, +val: U32) -> Ctx:
  match ts:
    case Nil{}    : c
    case t <> rest: km_go(rest, ka(c, t, val), val)

def km(c: Ctx, ts: List<&2, U32>, val: U32) -> Ctx:
  km_go(ts, c, val)

# `in_degree[k] += n`, WITH Python's KeyError folded in: `n` is 0 for the
# `setdefault` and `t` is always a kernel of some `_split_after`, so the key is
# always there already. `in_degree.setdefault(k, 0)` is therefore `da(c, k, 0)`
# at its one call site, and the INSERTION lands where Python's does.
def da_tail(found: Bool, k: U32, n: U32) -> List<&2, Dep>:
  match found:
    case True{} : Nil{}
    case False{}: [Dep{k, n}]

def da_pick(hit: Bool, r: List<&2, Dep>, j: U32, d: U32, k: U32, n: U32) -> List<&2, Dep>:
  match hit:
    case True{} : List.append(&2, Dep, [Dep{j, U32.add(d, n)}], r)
    case False{}: List.append(&2, Dep, [Dep{j, d}], r)

def da_go(+ds: List<&2, Dep>, found: Bool, +k: U32, +n: U32) -> List<&2, Dep>:
  match ds:
    case Nil{}          : da_tail(found, k, n)
    case Dep{j, d} <> t :
      r = da_go(t, Bool.or(found, U32.is_eq(j, k)), k, n)
      da_pick(U32.is_eq(j, k), r, j, d, k, n)

def da(+c: Ctx, +k: U32, n: U32) -> Ctx:
  Ctx.of(Ctx.kids(c), da_go(Ctx.degs(c), False{}, k, n), Ctx.wrns(c), Ctx.rds(c))

# `writes.setdefault(s, []).append(w)`
def wa_tail(found: Bool, s: U32, +w: Wrt) -> List<&2, Wrn>:
  match found:
    case True{} : Nil{}
    case False{}: [Wrn{s, [w]}]

def wa_pick(hit: Bool, r: List<&2, Wrn>, j: U32, vs: List<&2, Wrt>, s: U32, w: Wrt) -> List<&2, Wrn>:
  match hit:
    case True{} : List.append(&2, Wrn, [Wrn{j, List.append(&2, Wrt, vs, [w])}], r)
    case False{}: List.append(&2, Wrn, [Wrn{j, vs}], r)

def wa_go(+ws: List<&2, Wrn>, found: Bool, +s: U32, +w: Wrt) -> List<&2, Wrn>:
  match ws:
    case Nil{}           : wa_tail(found, s, w)
    case Wrn{j, vs} <> t :
      r = wa_go(t, Bool.or(found, U32.is_eq(j, s)), s, w)
      wa_pick(U32.is_eq(j, s), r, j, vs, s, w)

def wa(+c: Ctx, +s: U32, +w: Wrt) -> Ctx:
  Ctx.of(Ctx.kids(c), Ctx.degs(c), wa_go(Ctx.wrns(c), False{}, s, w), Ctx.rds(c))

# `reads += [(u, k, st) for st in read_states]` -- the APPEND is the fold, so the
# accumulator is `Ctx.rds` itself and there is no bulk append to write.
def rr_go(rs: List<&2, U32>, +u: U32, +k: U32, +ds: List<&2, Rd>) -> List<&2, Rd>:
  match rs:
    case Nil{}     : ds
    case s <> rest : rr_go(rest, u, k, List.append(&2, Rd, ds, [Rd{u, k, s}]))

def rd(+c: Ctx, rsts: List<&2, U32>, u: U32, k: U32) -> Ctx:
  Ctx.of(Ctx.kids(c), Ctx.degs(c), Ctx.wrns(c), rr_go(rsts, u, k, Ctx.rds(c)))

# `[st for s in ss for st in _states(s)]` -- one flatten, and `H.flatten_u32` is
# the one already written for `ended_of.flat`.
def so_go(+ar: O.Arena, ss: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ss:
    case Nil{}     : acc
    case s <> rest : so_go(ar, rest, List.append(&2, List<&2, U32>, acc, [sc_states(sc_fuel(ar), ar, s)]))

def sc_states_of(+ar: O.Arena, ss: List<&2, U32>) -> List<&2, U32>:
  H.flatten_u32(so_go(ar, ss, Nil{}))

# ===========================================================================
# PASS ONE, `__init__.py:39-56`. Five defs, one per Python scope, in Python's
# order: the per-`t` RAW fold, the per-kernel body, the per-kernels fold, the
# per-AFTER body and the toposort walk.
# ===========================================================================
# `for st in read_states + [st for s in after_deps for st in _states(s)]:
#    if st.op is AFTER: for t in _split_after(st)[0]: ...` -- the `t` list.
def ts_step.of(aft: Bool, +ar: O.Arena, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match aft:
    case True{} : List.append(&2, U32, acc, Split.ks(sc_split(ar, s)))
    case False{}: acc

def ts_step(+ar: O.Arena, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  ts_step.of(sc_is_after(ar, s), ar, s, acc)

def ts_go(+ar: O.Arena, sts: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match sts:
    case Nil{}     : acc
    case s <> rest : ts_go(ar, rest, ts_step(ar, s, acc))

def sc_ts(+ar: O.Arena, sts: List<&2, U32>) -> List<&2, U32>:
  ts_go(ar, sts, Nil{})

# `prev_kernels = set(_split_after(prev_state)[0]) if prev_state.op is AFTER else
# set()` and `tuple(k for k in kernels if k not in prev_kernels)`.
def nk_pick(have: Bool, acc: List<&2, U32>, k: U32) -> List<&2, U32>:
  match have:
    case True{} : acc
    case False{}: List.append(&2, U32, acc, [k])

def nk_go(+ks: List<&2, U32>, +pk: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}    : acc
    case k <> rest: nk_go(rest, pk, nk_pick(List.contains(U32, U32.is_eq, pk, k), acc, k))

def sc_pks.of(aft: Bool, +ar: O.Arena, prev: U32) -> List<&2, U32>:
  match aft:
    case True{} : Split.ks(sc_split(ar, prev))
    case False{}: Nil{}

def sc_pks(+ar: O.Arena, +prev: U32) -> List<&2, U32>:
  sc_pks.of(sc_is_after(ar, prev), ar, prev)

def sc_newks(+pk: List<&2, U32>, ks: List<&2, U32>) -> List<&2, U32>:
  nk_go(ks, pk, Nil{})

# `kernel_deps = k.src[0].src[1:] if k.op is END else k.src[1:]`
def sc_kdeps.of(op: O.Op, +ar: O.Arena, +k: U32) -> List<&2, U32>:
  match op:
    case O.OpsEND{}: sc_src_from(ar, sc_src0(ar, k), 1)
    case _          : sc_src_from(ar, k, 1)

def sc_kdeps(+ar: O.Arena, +k: U32) -> List<&2, U32>:
  sc_kdeps.of(sc_op(ar, k), ar, k)

# ONE KERNEL, `__init__.py:45-56`: the `setdefault`, the reads, the RAW `t`s.
# `in_degree[k] += 1` RUNS ONCE PER `t`, so the addend is the LENGTH of the `t`
# list and not a constant -- and it is the SAME def as the `setdefault(k, 0)`,
# because `da` inserts `Dep{k, n}` when the key is missing. fx5 is the only
# fixture with a RAW edge, so `COUNT_fx5_zero=1` and `COUNT_fx5_cyc=1` are the
# only rows that see a non-zero `in_degree` out of pass one; with a constant 0 fx5
# linearized as Ka,Kb and the edge ran the wrong way.
def sk_one.of(+rsts: List<&2, U32>, +c: Ctx, +u: U32, +k: U32, adsts: List<&2, U32>, +ar: O.Arena) -> Ctx:
  +ts = sc_ts(ar, List.append(&2, U32, rsts, adsts))
  km(da(rd(c, rsts, u, k), k, U32.from_nat(List.length(&2, U32, ts))), ts, k)

def sk_one(+ar: O.Arena, +u: U32, +k: U32, adsts: List<&2, U32>, c: Ctx) -> Ctx:
  sk_one.of(sc_states_of(ar, sc_kdeps(ar, k)), c, u, k, adsts, ar)

def sk(fuel: Nat, +ar: O.Arena, +u: U32, ks: List<&2, U32>, +adsts: List<&2, U32>, +c: Ctx) -> Ctx:
  match fuel:
    case 0n: c
    case 1n+p:
      match ks:
        case Nil{}    : c
        case k <> rest: sk(p, ar, u, rest, adsts, sk_one(ar, u, k, adsts, c))

# `writes.setdefault(prev_state, []).append((u, newks))` with
# `prev_state = _unwrap_src(u.src[0])`. `sc_pks` re-reads `prev_state` because
# Python evaluates the conditional before the append.
def sw_wr(+ar: O.Arena, +u: U32, c: Ctx, ks: List<&2, U32>) -> Ctx:
  wa(c, sc_unwrap(ar, sc_src0(ar, u)), Wrt{u, sc_newks(sc_pks(ar, sc_unwrap(ar, sc_src0(ar, u))), ks)})

# THE BODY FOR ONE AFTER. `sw` splits `u`, `sw_wr` writes `writes`, and `sk`
# walks the kernels -- Python's four statements in Python's order.
def sw_run(+c: Ctx, +ar: O.Arena, +u: U32, +sp: Split) -> Ctx:
  match sp:
    case Split{ks, ds}:
      sk(O.Arena.budget(ar), ar, u, ks, sc_states_of(ar, ds), sw_wr(ar, u, c, ks))

def sw.of(after: Bool, +c: Ctx, +ar: O.Arena, +u: U32) -> Ctx:
  match after:
    case False{}: c
    case True{} : sw_run(c, ar, u, sc_split(ar, u))

def sw.ar(after: Bool, +ar: O.Arena, +u: U32, +c: Ctx) -> Ctx:
  sw.of(after, c, ar, u)



def sa(fuel: Nat, +ar: O.Arena, us: List<&2, U32>, +c: Ctx) -> Ctx:
  match fuel:
    case 0n: c
    case 1n+p:
      match us:
        case Nil{}     : c
        case +u <> rest: sa(p, ar, rest, sw.ar(sc_is_after(ar, u), ar, u, c))

# THE TOPI: `for u in sched_sink.toposort(gate_kernel_sink)`. The fuel is the
# budget, which ops.bend calls EXACT: one pop per pushed frame and a frame is
# pushed once per edge plus once per gated node.
def pass1(+ar: O.Arena, +sink: U32) -> Ctx:
  sa(O.Arena.budget(ar), ar, sc_topo_of(O.Arena.budget(ar), ar, sink), Ctx.of(Nil{}, Nil{}, Nil{}, Nil{}))

# ===========================================================================
# PASS TWO, the WAR loop, `__init__.py:59-65`. Three defs for three scopes.
# ===========================================================================
def wt_keep(+ar: O.Arena, +k: U32, +t: U32) -> Bool:
  Bool.and(Bool.not(U32.is_eq(t, k)), Bool.not(sc_in_bs(ar, k, t)))

def wt.of(keep: Bool, +c: Ctx, +k: U32, +t: U32) -> Ctx:
  match keep:
    case True{} : ka(da(c, t, 1), k, t)
    case False{}: c

def wt(+ar: O.Arena, +k: U32, +t: U32, c: Ctx) -> Ctx:
  wt.of(wt_keep(ar, k, t), c, k, t)

def wt_go(fuel: Nat, ts: List<&2, U32>, +ar: O.Arena, +k: U32, +c: Ctx) -> Ctx:
  match fuel:
    case 0n: c
    case 1n+p:
      match ts:
        case Nil{}    : c
        case t <> rest: wt_go(p, rest, ar, k, wt(ar, k, t, c))

# `for a, write_kernels in writes.get(s, []): if a is u: continue`
def ww.of(same: Bool, wks: List<&2, U32>, +c: Ctx, +ar: O.Arena, +k: U32) -> Ctx:
  match same:
    case True{} : c
    case False{}: wt_go(sc_fuel(ar), wks, ar, k, c)

def ww(fuel: Nat, ws: List<&2, Wrt>, +ar: O.Arena, +u: U32, +k: U32, +c: Ctx) -> Ctx:
  match fuel:
    case 0n: c
    case 1n+p:
      match ws:
        case Nil{}             : c
        case Wrt{a, wks} <> st : ww(p, st, ar, u, k, ww.of(U32.is_eq(a, u), wks, c, ar, k))

# `for u, k, s in reads` -- reads in INSERTION order, which is the order the
# toposort met the AFTERs and that decides the WAR edges.
def war(fuel: Nat, +ar: O.Arena, rds: List<&2, Rd>, +c: Ctx) -> Ctx:
  match fuel:
    case 0n: c
    case 1n+p:
      match rds:
        case Nil{}          : c
        case Rd{u, k, s} <> st: war(p, ar, st, ww(sc_fuel(ar), wg(c, s), ar, u, k, c))

def pass2(+ar: O.Arena, +c: Ctx) -> Ctx:
  war(sc_fuel(ar), ar, Ctx.rds(c), c)

# ===========================================================================
# PASS THREE, `__init__.py:67-80`. TWO records, because the queue is the one
# piece of loop state whose SHAPE changes every turn and a fold that must return
# both its accumulator and a queue needs a record -- `Sized` in fold.bend and
# `Kahn` here are the same bill. The queue is a `List` in Python's DEQUE ORDER
# (`popleft` is a head pop, `append` is a tail-append) and `Lin.out` is appended
# too, so both are already in the order Python has them and nothing reverses.
# ===========================================================================
type Lin is Data:
  Lin{ar: O.Arena, c: Ctx, out: List<&2, U32>}

type Q is Data:
  Q{q: List<&2, U32>, l: Lin}

def Lin.ar(x: Lin) -> O.Arena:
  match x:
    case Lin{ar, c, out}: ar

def Lin.c(x: Lin) -> Ctx:
  match x:
    case Lin{ar, c, out}: c

def Lin.out(x: Lin) -> List<&2, U32>:
  match x:
    case Lin{ar, c, out}: out

# `linearized.append(...)` -- the arena moves on because `replace` interned.
# `in_degree[x] -= n`, the one write the Kahn loop makes to the four dicts.
def Lin.dec(+l: Lin, x: U32, n: U32) -> Lin:
  match l:
    case Lin{ar, c, out}: Lin{ar, da(c, x, n), out}

def Q.q(x: Q) -> List<&2, U32>:
  match x:
    case Q{q, l}: q

def Q.l(x: Q) -> Lin:
  match x:
    case Q{q, l}: l

# `queue = deque(k for k,v in in_degree.items() if v == 0)` -- `in_degree`'s
# INSERTION order, which `da` preserves and which decides the linearization.
# THE SEED QUEUE, in `in_degree` order, and APPENDED like every other list in this
# file. The queue is a `List` in Python's DEQUE ORDER -- `popleft` is a head pop
# and `append` is `List.append`, which is `qs ++ [x]` and therefore O(n) where
# CPython's deque is O(1). That is the honest cost of a `List` standing in for a
# deque and it is the ONLY place the port is asymptotically worse.
def z_pick(z: Bool, acc: List<&2, U32>, k: U32) -> List<&2, U32>:
  match z:
    case True{} : List.append(&2, U32, acc, [k])
    case False{}: acc

def z_go(+ds: List<&2, Dep>, acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}          : acc
    case Dep{k, d} <> t : z_go(t, z_pick(U32.is_zero(d), acc, k))

def zero(c: Ctx) -> List<&2, U32>:
  z_go(Ctx.degs(c), Nil{})

# `buf_uops = tuple(_unwrap_src(s).buf_uop for s in k.src[1:] if not s.is_bound_var)`
def bu_step.of(bnd: Bool, +ar: O.Arena, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match bnd:
    case True{} : acc
    case False{}: List.append(&2, U32, acc, [sc_buf_uop(ar, sc_unwrap(ar, s))])

def bu_step(+ar: O.Arena, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  bu_step.of(sc_is_bound_var(ar, s), ar, s, acc)

def bu_go(+ar: O.Arena, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}     : acc
    case s <> rest : bu_go(ar, rest, bu_step(ar, s, acc))

# `k.replace(src=(k.body, *buf_uops))`. `k` is a CALL here -- __init__.py:75
# asserts it -- so `k.body` is `src[0]`. This is the ONE place in the file that
# interns, so it is the ONE place the arena is handed back.
def replace(+ar: O.Arena, +k: U32) -> O.Found:
  O.UOp.new(ar, sc_op(ar, k),
    List.append(&2, U32, [sc_src0(ar, k)], bu_go(ar, sc_src_from(ar, k, 1), Nil{})),
    sc_arg(ar, k), sc_tag(ar, k))

# `k = rk.src[0] if rk.op is END else rk`
def kernel.of(op: O.Op, +ar: O.Arena, +rk: U32) -> U32:
  match op:
    case O.OpsEND{}: sc_src0(ar, rk)
    case _          : rk

def kernel(+ar: O.Arena, +rk: U32) -> U32:
  kernel.of(sc_op(ar, rk), ar, rk)

# `for x in children.get(rk, []): in_degree[x] -= 1; if in_degree[x] == 0:
# queue.append(x)` -- the push is a cons because the queue is a stack here.
# THE ORDER MATTERS: Python decrements and THEN tests, so the test is on the
# DECREMENTED value and BOTH arms write it. Testing `d == 0` first strands every
# kernel whose degree is 1 -- which is every kernel the WAR pass put there -- so
# fx2 lost Ka and linearized as Kb,Kc with `fx2_marks=23`. `fx2_lin_n=3` and
# `fx2_marks=231` are the rows.
def lk.put(z: Bool, q: List<&2, U32>, nl: Lin, x: U32) -> Q:
  match z:
    case True{} : Q{List.append(&2, U32, q, [x]), nl}
    case False{}: Q{q, nl}

def lk.of(+e: U32, q: List<&2, U32>, +l: Lin, +x: U32) -> Q:
  lk.put(U32.is_zero(e), q, Lin.dec(l, x, e), x)

def lk(q: List<&2, U32>, +l: Lin, +x: U32) -> Q:
  lk.of(U32.sub(dg(Lin.c(l), x), 1), q, l, x)

def lk_go(fuel: Nat, xs: List<&2, U32>, q: List<&2, U32>, +l: Lin) -> Q:
  match fuel:
    case 0n: Q{q, l}
    case 1n+p:
      match xs:
        case Nil{}    : Q{q, l}
        case x <> rest:
          +t = lk(q, l, x)
          lk_go(p, rest, Q.q(t), Q.l(t))

# `linearized.append(k.replace(...))`, and the queue's new head -- so the Lin's
# own `out` grows and `Lin.put` is not needed; the popped node leaves `l` behind.
def lh.put(+f: O.Found, rest: List<&2, U32>, +l: Lin) -> Lin:
  match l:
    case Lin{ar, c, out}: Lin{O.Found.ar(f), c, List.append(&2, U32, out, [O.Found.i(f)])}

def lh(rk: U32, rest: List<&2, U32>, +l: Lin) -> Lin:
  lh.put(replace(Lin.ar(l), kernel(Lin.ar(l), rk)), rest, l)



# THE WHILE, and the whole of it is ONE recursive def. The queue is `ln_go`'s OWN
# PARAMETER and not a field, because `Q.q(s)` is a CALL and a `match` may not
# scrutinise a call; so the kids loop answers a `Q`, a `+` local holds it, and the
# self-call unpacks it in tail position.
def ln_go(fuel: Nat, q: List<&2, U32>, +l: Lin) -> Lin:
  match fuel:
    case 0n   : l
    case 1n+p :
      match q:
        case Nil{}     : l
        case +rk <> +rest:
          +t = lk_go(sc_fuel(Lin.ar(l)), kg(Lin.c(l), rk), rest, lh(rk, rest, l))
          ln_go(p, Q.q(t), Q.l(t))



def lin(+ar: O.Arena, +c: Ctx) -> Lin:
  ln_go(sc_fuel(ar), zero(c), Lin{ar, c, Nil{}})


# ===========================================================================
# `create_schedule` -- __init__.py:32-80, and `linear` is the `return UOp(Ops.
# LINEAR, src=tuple(linearized))`.
# ===========================================================================
def linear(+x: Lin) -> O.Found:
  O.UOp.new(Lin.ar(x), O.OpsLINEAR{}, Lin.out(x), O.ANone{}, O.TNone{})

def schedule(+ar: O.Arena, +sink: U32) -> Lin:
  lin(ar, pass2(ar, pass1(ar, sink)))

# `if any(in_degree.values()): raise RuntimeError("cycle detected in assign
# graph")` -- a raise the TODO above cannot make, so what IS observable is the
# set of KEYS with a non-zero degree, and `fx2_cycle` asks whether it is empty.
def cy_pick(z: Bool, acc: List<&2, U32>, k: U32) -> List<&2, U32>:
  match z:
    case True{} : acc
    case False{}: k <> acc

def cy_go(+ds: List<&2, Dep>, acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}          : acc
    case Dep{k, d} <> t : cy_go(t, cy_pick(U32.is_zero(d), acc, k))

def cycles(c: Ctx) -> Nat:
  List.length(&2, U32, cy_go(Ctx.degs(c), Nil{}))

# ===========================================================================
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
# ===========================================================================

# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
def is_store_after(+ar: O.Arena, +u: U32) -> Bool:
  Bool.and(sc_is_after(ar, u),
    Bool.or(Bool.not(sc_is(ar, O.UOp.unsharded_base(O.Arena.budget(ar), ar, sc_src0(ar, u)), O.OpsALLOC{})),
      sc_is(ar, sc_src(ar, u, 1), O.OpsSTORE{})))

# ---------------------------------------------------------------------------
# 2. `CallifyCtx` -- __init__.py:192-197. THE C2 CLAUSE, and this is the whole
# of it: a dataclass of a list, a dict, a set and another list.
#
#     @dataclass
#     class CallifyCtx:
#       replacements: list[UOp] = field(default_factory=list)
#       allocs: dict[UOp, UOp] = field(default_factory=dict)
#       views: set[UOp] = field(default_factory=set)
#       stores: list[UOp] = field(default_factory=list)
#
# All four are append-only `List`s IN PYTHON'S FIELD ORDER, because the order
# decides WHICH list a rule body writes: `collect_stores` writes `stores`,
# `canonicalize_alloc` writes `allocs`, `replace_input_buffer` writes
# `replacements` and `contiguous_mops_to_view` writes `views`. A record whose
# fields are re-ordered answers the RIGHT list while the gate says it wrote the
# wrong one, so `cs_reps`/`cs_allocs`/`cs_views` are rows and not decoration.
# `allocs` is the `dict[UOp,UOp]` and it is an ASSOCIATION LIST `Aa{b,v}`, one
# entry per key, because Bend's `Map` is String-keyed and this dict is keyed by
# the node -- the same bill `ka_go` pays for `children`.
#
# `views` is a Python `set` and `set.add` DEDUPLICATES while `list.append` does
# NOT. `cs_dup2` is the identity row for `stores`; no row covers `views` because
# no body ported here writes it.
# ---------------------------------------------------------------------------
type Aa is Data:
  Aa{b: U32, v: U32}

type CallifyCtx is Data:
  CallifyCtx{replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>}

def CallifyCtx.of(replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>) -> CallifyCtx:
  CallifyCtx{replacements, allocs, views, stores}

# `CallifyCtx()` -- all four fields are `field(default_factory=...)`, so four
# `Nil{}`. `CallifyCtx.of` is the four-argument rebuild, exactly as `Ctx.of` is.
def callify_ctx() -> CallifyCtx:
  CallifyCtx.of(Nil{}, Nil{}, Nil{}, Nil{})

def CallifyCtx.replacements(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: replacements

def CallifyCtx.allocs(x: CallifyCtx) -> List<&2, Aa>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: allocs

def CallifyCtx.views(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: views

def CallifyCtx.stores(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: stores

def Aa.b(x: Aa) -> U32:
  match x:
    case Aa{b, v}: b

def Aa.v(x: Aa) -> U32:
  match x:
    case Aa{b, v}: v

# `ctx.allocs.get(b, None)` -- the ONE reader of `allocs` a ported body needs.
def ag_pick(hit: Bool, acc: Maybe<&2, U32>, v: U32) -> Maybe<&2, U32>:
  match hit:
    case True{} : Some{v}
    case False{}: acc

def ag_go(+as: List<&2, Aa>, +b: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match as:
    case Nil{}       : acc
    case Aa{j, v} <> t: ag_go(t, b, ag_pick(U32.is_eq(j, b), acc, v))

def aa_get(+c: CallifyCtx, +b: U32) -> Maybe<&2, U32>:
  ag_go(CallifyCtx.allocs(c), b, None{})

# `ctx.allocs[b] = v`. INSERT if absent and REPLACE if present -- Python's
# `dict[k] = v` does both -- so the walk needs the `found` accumulator `ka_go`
# uses: without it a second write leaves TWO entries for ONE key, and `ca_n3` is
# the row that sees it.
def ap_tail(found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match found:
    case True{} : Nil{}
    case False{}: [Aa{b, v}]

def ap_pick(hit: Bool, r: List<&2, Aa>, j: U32, old: U32, +v: U32) -> List<&2, Aa>:
  match hit:
    case True{} : List.append(&2, Aa, [Aa{j, v}], r)
    case False{}: List.append(&2, Aa, [Aa{j, old}], r)

def ap_go(+as: List<&2, Aa>, found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match as:
    case Nil{}        : ap_tail(found, b, v)
    case Aa{j, old} <> t:
      r = ap_go(t, Bool.or(found, U32.is_eq(j, b)), b, v)
      ap_pick(U32.is_eq(j, b), r, j, old, v)

def aa_put(+c: CallifyCtx, +b: U32, +v: U32) -> CallifyCtx:
  CallifyCtx.of(CallifyCtx.replacements(c),
    ap_go(CallifyCtx.allocs(c), False{}, b, v),
    CallifyCtx.views(c), CallifyCtx.stores(c))

# `b in ctx.allocs`
def aa_has(+as: List<&2, Aa>, +b: U32) -> Bool:
  match as:
    case Nil{}       : False{}
    case Aa{j, _} <> t: Bool.or(U32.is_eq(j, b), aa_has(t, b))

# ---------------------------------------------------------------------------
# 3. `collect_stores` -- __init__.py:220-221. NEEDS ctx, and it is one of only
# TWO of the twelve that do:
#
#     def collect_stores(ctx:CallifyCtx, u:UOp):
#       if is_store_after(u): ctx.stores.append(u)
#
# Python returns None on BOTH arms and the rewriter reads that as "no rewrite",
# so the ANSWER is `None{}` twice and the only effect is the append. A rule body
# that mutated the ctx and returned the node would be a DIFFERENT rule, so the
# ctx and the answer come back TOGETHER in `Cw`: Python's one-call-one-side-effect
# signature cannot be spelled, and splitting it into two defs would let a caller
# drop one of them.
# ---------------------------------------------------------------------------
type Cw is Data:
  Cw{c: CallifyCtx, a: Maybe<&2, U32>}

def Cw.c(x: Cw) -> CallifyCtx:
  match x:
    case Cw{c, a}: c

def Cw.a(x: Cw) -> Maybe<&2, U32>:
  match x:
    case Cw{c, a}: a

def cs_put(hit: Bool, +c: CallifyCtx, +u: U32) -> CallifyCtx:
  match hit:
    case True{} : CallifyCtx.of(CallifyCtx.replacements(c), CallifyCtx.allocs(c),
                 CallifyCtx.views(c), List.append(&2, U32, CallifyCtx.stores(c), [u]))
    case False{}: c

def collect_stores(c: CallifyCtx, +ar: O.Arena, +u: U32) -> Cw:
  Cw{cs_put(is_store_after(ar, u), c, u), None{}}

# THE EIGHT CALLS in the gate's order, so `cs_ops2` is an APPEND-ORDER row and
# not a count. `cs_dup2` is the identity row: `stores[1]` and `stores[2]` are the
# same SA_B, so a `set` would answer 2 where the list answers 3.
def cs_run.go(+us: List<&2, U32>, +ar: O.Arena, c: CallifyCtx) -> CallifyCtx:
  match us:
    case Nil{}     : c
    case u <> rest : cs_run.go(rest, ar, Cw.c(collect_stores(c, ar, u)))

def cs_run(c: CallifyCtx, +ar: O.Arena, us: List<&2, U32>) -> CallifyCtx:
  cs_run.go(us, ar, c)

# ---------------------------------------------------------------------------
# 4. `lower_sink_to_linear` -- __init__.py:124-126. NO ctx. THE GUARD is ported
# and the guard is what decides whether the schedule cache is consulted at all:
#
#     function = call.body
#     if function.op is not Ops.SINK or isinstance(function.arg, KernelInfo)
#        or not call.arg.precompile: return None
#
# `UOp.body` (ops.py:562) answers `Maybe<&2,U32>` and its `None{}` is Python's
# `raise`, so a non-CALL answers `None{}` here too. `sc_gate.ker` IS
# `isinstance(arg, KernelInfo)` -- the same reader the toposort gate uses, which
# is why this is one call and not a second `match`.
#
# WHAT IS NOT PORTED, and it is the rest of the function:
#   TODO(p3) __init__.py:127-131  `time.perf_counter` and `function.key` --
#     `function.key` is a `bytes` CONTENT hash of the whole function and
#     nothing in this tree computes one. AGENTS.md says inject time rather than
#     read a clock, so the clock is not the wall; the KEY is.
#   TODO(p3) __init__.py:130-131  `schedule_cache` and `diskcache_get`. THIS is
#     the trap worth naming: `schedule_cache` is a MODULE-LEVEL `dict[bytes,UOp]`
#     read at :130 BEFORE `create_schedule` is called at :135, so a spec run twice
#     in one process answers from the cache and NEVER re-enters the function. A
#     Bend `Map` cache would inherit that memo, and a gate row that called
#     `lower_sink_to_linear` twice in one process would be measuring the cache
#     and not the guard. The guard below is therefore cache-free BY CONSTRUCTION
#     -- it takes no cache at all -- and `lsl_none_*` are real CPython calls of
#     the real function, so they exercise the same early return.
#   WALL(p3) __init__.py:133      `if SPEC: type_verify(function, spec_tensor)` -- BLOCKED: needs the `if SPEC:` gate wired to `uop/spec.bend`'s `verify_tensor` over `tensor_table()`; `type_verify`/`spec_tensor` are PORTED there (spec.bend:3121), NOT missing defs, and only the `SPEC > 1` and `DEBUG >= 3` arms are absent.
#   TODO(p3) __init__.py:135      `get_kernel_graph(prepare_rangeify(function))`
#     -- `schedule/rangeify.py` and `schedule/prepare.py`, out of scope.
#   TODO(p3) __init__.py:141-150  the `inspect.stack()` DEBUG block.
# ---------------------------------------------------------------------------
def lsl_pre(arg: O.Arg) -> Bool:
  match arg:
    case O.ACall{ci}: O.CallInfo.precompile(ci)
    case _           : False{}

def lsl_ok(pre: Bool, +ar: O.Arena, +fn: U32) -> Bool:
  Bool.and(Bool.and(sc_is(ar, fn, O.OpsSINK{}), Bool.not(sc_gate.ker(sc_arg(ar, fn)))), pre)

def lsl_of(ok: Bool, fn: U32) -> Maybe<&2, U32>:
  match ok:
    case True{} : Some{fn}
    case False{}: None{}

# THE FUNCTION ANSWERS THE `fn` INDEX and not `call`, because the answer in
# Python is a REWRITTEN `call` and `call.replace(src=(linear,)+call.src[1:])` is
# behind the same key. `lsl_p_*` are the three predicates as separate defs, since
# `lsl_p_*` are rows and a row that is only the conjunction cannot say WHICH
# conjunct moved.
def lower_sink_to_linear(+ar: O.Arena, +call: U32) -> Maybe<&2, U32>:
  lsl_of(lsl_ok(lsl_pre(sc_arg(ar, call)), ar, Maybe.default(&2, U32, sc_body(ar, call), 0)),
    sc_src0(ar, call))

def lower_sink_to_linear.p_sink(+ar: O.Arena, +call: U32) -> Bool:
  sc_is(ar, Maybe.default(&2, U32, sc_body(ar, call), 0), O.OpsSINK{})

def lower_sink_to_linear.p_ki(+ar: O.Arena, +call: U32) -> Bool:
  sc_gate.ker(sc_arg(ar, Maybe.default(&2, U32, sc_body(ar, call), 0)))

def lower_sink_to_linear.p_pre(+ar: O.Arena, +call: U32) -> Bool:
  lsl_pre(sc_arg(ar, call))

def lower_sink_to_linear.p_ok(+ar: O.Arena, +call: U32) -> Bool:
  Bool.and(Bool.and(lower_sink_to_linear.p_sink(ar, call),
    Bool.not(lower_sink_to_linear.p_ki(ar, call))),
    lower_sink_to_linear.p_pre(ar, call))

# ---------------------------------------------------------------------------
# 5. `copy_kernel_to_store` -- __init__.py:161-163, and
# 6. `simplify_copy_kernel` -- __init__.py:165-172. BOTH NO ctx, and BOTH open
# with THE SAME LINE, which is why they share `cks_fire` and why `sck_*` is two
# rows over ONE predicate rather than a merge:
#
#     if dst.device == src.device and not (isinstance(dst.device, str)
#        and dst.device.startswith("DISK")): return None
#
# THE DEVICE IS A TAG, NOT A NAME. `S.Dev` is `D1{tag}` / `Dn{tags}` and the name
# is gone, so `startswith("DISK")` cannot be asked here. `schedule/memory.bend:189`
# already hit this on `startswith(("DISK","CL","WEBGPU"))` and the treatment is a
# PARAMETER: `disk` is the DISK TAG SET and the caller is the device table. So
# `disk=[]` is a PERMITTED answer and the prefix test is PARAMETERISED, not
# ported. `Dn` is a TUPLE and Python's `isinstance(dst.device, str)` is False for
# it, so `Dn` answers False whatever `disk` says -- `cks_disk_n` is that row.
#
# `dst.device` for a PARAM is `self.arg.device` (ops.py:888), read straight off
# the `ParamArg`, so no fold is needed. The general `.device` -- ops.py:889-895's
# STAGE/AFTER/MSELECT/MSTACK arms and the "first src with a device" tail -- IS
# `fold.bend`'s and needs a `Table`:
#   TODO(p3) ops.py:889-895  `.device`'s non-PARAM arms -- `fold.device`.
#
# `dst.store(src)` is `UOp.store` and IS in ops.bend, and `call.replace(src=
# (stored,)+call.src[1:])` is `cks_rep` -- the local `replace` at :971 is
# hard-wired to the linearizer's own shape, so this is its own def.
# ---------------------------------------------------------------------------
def cks_dev(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.AParam{pa}: O.ParamArg.device(pa)
    case _            : None{}

def cks_dev.of(+ar: O.Arena, +u: U32) -> Maybe<&2, S.Dev>:
  cks_dev(sc_arg(ar, u))

# the scrutinees are CALLS and a `match` may not scrutinise a call, so they go in
# as parameters -- the same bill `sc_gate.of` pays.
def cks_dev.eq(x: Maybe<&2, S.Dev>, y: Maybe<&2, S.Dev>) -> Bool:
  match x y:
    case Some{p} Some{q}: O.eq_dev(p, q)
    case _            _   : False{}

def cks_dev.same(+ar: O.Arena, +d: U32, +s: U32) -> Bool:
  cks_dev.eq(cks_dev.of(ar, d), cks_dev.of(ar, s))

def cks_disk(disk: List<&2, U32>, m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case Some{dev}:
      match dev:
        case S.D1{t} : List.contains(U32, U32.is_eq, disk, t)
        case S.Dn{ts}: False{}
    case None{}    : False{}

def cks_fire(disk: List<&2, U32>, +ar: O.Arena, +dst: U32, +src: U32) -> Bool:
  Bool.and(cks_dev.same(ar, dst, src), Bool.not(cks_disk(disk, cks_dev.of(ar, dst))))

def cks_rep(+ar: O.Arena, +call: U32, +head: U32) -> O.Found:
  O.UOp.new(ar, sc_op(ar, call),
    List.append(&2, U32, [head], sc_src_from(ar, call, 1)), sc_arg(ar, call), sc_tag(ar, call))

def cks_put(fire: Bool, +ar: O.Arena, +call: U32, +dst: U32, +src: U32) -> Maybe<&2, O.Found>:
  match fire:
    case True{}:
      +st = sc_store(ar, dst, src, None{})
      Some{cks_rep(O.Found.ar(st), call, O.Found.i(st))}
    case False{}: None{}

# `r:UOp|None=None` is the FOURTH parameter and NOBODY PASSES IT -- the two
# patterns at :181 and :184 bind only `call`, `dst`, `src`, `r` -- so it is not a
# parameter here.
def copy_kernel_to_store(disk: List<&2, U32>, +ar: O.Arena, +call: U32, +dst: U32, +src: U32) -> Maybe<&2, O.Found>:
  cks_put(cks_fire(disk, ar, dst, src), ar, call, dst, src)

# THE GUARD OF `simplify_copy_kernel` IS PORTED AND THE RULE IS NOT, so the def
# is `simplify_copy_kernel.ok` and NOT `simplify_copy_kernel`. The answer is a
# SINK and the only way to get one is
#
#     graph_rewrite(ast, sym+pm_mops+pm_flatten_range+pm_simplify_ranges,
#                   ctx={}, name="simplify ranges in copy")
#
# a bottom-up rewrite over FOUR matchers, two of them imported at :168-170.
# Naming a def `simplify_copy_kernel` that answers the guard's BOOLEAN would put
# a WRONG ANSWER under an UPSTREAM NAME and a caller would take it for the rule.
#   TODO(p3) __init__.py:171  the four-matcher bottom_up rewrite -- THE WALL.
#   TODO(p3) __init__.py:168-170  `sym` / `pm_flatten_range` /
#     `pm_simplify_ranges` -- no port. `pm_mops` is `schedule/prepare.bend`'s.
def simplify_copy_kernel.ok(disk: List<&2, U32>, +ar: O.Arena, +dst: U32, +src: U32) -> Bool:
  cks_fire(disk, ar, dst, src)

# ---------------------------------------------------------------------------
# 7. `assert_all_same_devices` -- __init__.py:157-159. NO ctx, NO table:
#
#     devices = dedup([x.device for x in ast.toposort()
#                      if x.op is Ops.PARAM and x.device is not None])
#     if len(devices) >= 2: raise RuntimeError(...)
#
# `UOp.toposort` (ops.bend:2894) is the ungated one, so no `sc_topo` copy is
# needed. `dedup` preserves FIRST-OCCURRENCE order and the arena interns, so two
# structurally equal UOps are ONE index: the dedup is over INDICES and a
# `List.contains` over the kept ones is the same set -- the argument `sc_newks`
# makes for `prev_kernels`.
#
# THE ANSWER IS NOT A BOOLEAN. Python RETURNS None and the RAISE is the whole
# effect, and a rule body must return a node, so `Ads` carries the DEVICES --
# the same treatment `cycles` gets above. `asd_raises` is the `>= 2` THRESHOLD
# and `asd_two` (ONE device) is the row that pins it: a `>= 1` mutation leaves
# every other row green.
#
# THE THREE-WAY SELECTOR IS ONE `match` AND NOT A NESTED ONE, because a `match`
# nested inside a `case h <> t:` LIST arm is REFUSED in bend 2.0.34 (this file's
# rule 1). Class 1 is "a PARAM with a device we have not kept yet".
#   TODO(p3) __init__.py:159  the RuntimeError -- a raise.
# ---------------------------------------------------------------------------
type Ads is Data:
  Ads{ds: List<&2, U32>}

def Ads.ds(x: Ads) -> List<&2, U32>:
  match x:
    case Ads{ds}: ds

def asd_cls(ispar: Bool, hasdev: Bool, seen: Bool) -> U32:
  match ispar hasdev seen:
    case True{} True{} True{}  : 0
    case True{} True{} False{} : 1
    case _      _      _       : 0

# TWO defs AND NOT ONE, for the file's rule 1: a `match` NESTED inside a
# `case x <> rest:` LIST arm is refused, so the SELECTOR cannot live in the arm.
# `asd_go`'s arm is calls only and `asd_step` matches on a `U32` PARAMETER.
def asd_step(cls: U32, +kept: List<&2, U32>, +x: U32) -> List<&2, U32>:
  match cls:
    case 1: List.append(&2, U32, kept, [x])
    case _: kept

# THE LIST IS THE FIRST PARAMETER, NOT THE SECOND, and that is this file's rule 3:
# the check is left to right and each argument is passed unchanged until one
# shrinks, so the shrinking LIST must come FIRST and the computed accumulator
# second -- `ka_go(t, Bool.or(...), key, val)` above is the same shape.
def asd_go(+xs: List<&2, U32>, +kept: List<&2, U32>, +ar: O.Arena) -> List<&2, U32>:
  match xs:
    case Nil{}     : kept
    case x <> rest :
      k = asd_step(asd_cls(sc_is(ar, x, O.OpsPARAM{}),
                  Maybe.is_some(&2, S.Dev, cks_dev.of(ar, x)),
                  List.contains(U32, U32.is_eq, kept, x)), kept, x)
      asd_go(rest, k, ar)

def assert_all_same_devices(+ar: O.Arena, +ast: U32) -> Ads:
  Ads{asd_go(O.UOp.toposort(O.Arena.budget(ar), ar, ast), Nil{}, ar)}

# `if len(devices) >= 2: raise`. 2147483648 is `>= 2`'s other side: the THRESHOLD
# is two, not one, and `asd_two` is the row that says so.
def assert_all_same_devices.raises(x: Ads) -> Bool:
  Bool.not(U32.is_lt(U32.from_nat(List.length(&2, U32, Ads.ds(x))), 2))

# ---------------------------------------------------------------------------
# 8. `apply_binds` -- __init__.py:110-114. NO ctx. THE THREE-ARM DISPATCH is
# ported and ARM 3 IS NOT, so the def is `apply_binds` and the answer is an ARM
# NUMBER (1, 2, 3) and not a node:
#
#     def apply_binds(si:UOp) -> UOp:
#       if si.op is Ops.CALL and si.body.op is Ops.LINEAR:  return resolve_linear_call(si, binds)
#       if si.op is Ops.CALL and si.body.op is Ops.PROGRAM: return si
#       subs = {v:binds[v.arg.slot] for s in si.src for v in s.variables() if v.arg.slot in binds}
#       return si.replace(src=tuple(s.substitute(subs, ...) for s in si.src))
#
# ARM 3 needs `UOp.variables` and `UOp.substitute` and NEITHER IS IN THE TREE:
# `fold.bend`'s own header names `variables` as one of the three readers waiting
# on the RANGES FOLD, and `ops.py:1239 UOp.substitute` waits behind it.
# `ab_C_LIN` is arm 1, whose recursion target `resolve_linear_call` is NOT in `uop/ops.bend` --
# an earlier revision of this sentence said it was "already ... as tag 42's table", AND THAT IS
# FALSE: tag 42 is `_pm_resolve_params` (`uop/ops.bend:4044`) and no `def ...resolve_linear_call`
# exists anywhere. See the corrected note at `__init__.py:279` for the measurement. Arm 1 is
# therefore ALSO blocked on it, not on `binds` alone (:107-109), which is `dict[int,UOp]` keyed by a
# Python int -- the same String-keyed-`Map` bill `Aa` pays above.
#   TODO(p3) __init__.py:113  `s.variables()` -- no reader in the tree.
#   TODO(p3) __init__.py:114  `s.substitute`   -- no reader in the tree.
#   TODO(p3) __init__.py:107-109  `binds`, a `dict[int,UOp]` -- arm 1.
# ---------------------------------------------------------------------------
def apply_binds.arm(iscall: Bool, linear: Bool, program: Bool) -> U32:
  match iscall linear program:
    case True{}  True{}  _       : 1
    case True{}  False{} True{}  : 2
    case _       _      _       : 3

def apply_binds.of(iscall: Bool, +bop: O.Op) -> U32:
  apply_binds.arm(iscall, O.eq_op(bop, O.OpsLINEAR{}), O.eq_op(bop, O.OpsPROGRAM{}))

def apply_binds(+ar: O.Arena, +si: U32) -> U32:
  apply_binds.of(sc_is(ar, si, O.OpsCALL{}),
    sc_op(ar, Maybe.default(&2, U32, sc_body(ar, si), 0)))

# ---------------------------------------------------------------------------
# 9. `canonicalize_alloc` -- __init__.py:235-237. NEEDS ctx, and it is the
# SECOND and LAST of the two bodies that do:
#
#     def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
#       if b.arg.slot >= 0 and b not in ctx.allocs:
#         ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
#       return ctx.allocs.get(b)
#
# THREE THINGS ARE THE PORT AND ALL THREE HAVE A ROW:
#   * `-1 - len(ctx.allocs)`, so the slots are -1, -2, ... and NOT 0, -1, ...
#     (`ca_slot1`/`ca_slot2`, ONE ROW APART, from fixtures whose incoming slots
#     are 7 and 9 -- so a port that dropped the `-1-` would answer 0 and 1).
#   * the `b not in ctx.allocs` GUARD, so a second call on the same `b` writes
#     nothing and returns the SAME node (`ca_n3`, `ca_repeat`).
#   * `slot >= 0`, so a slot that is ALREADY canonical is left alone and the
#     answer is `None{}` (`ca_neg_none`, `ca_neg_n`). Python's `None` and the
#     rewriter's "no rewrite" are the same value here and NOT by accident.
#
# **`ParamArg.slot` IS A `U32` AND PYTHON'S IS AN `int`.** That is the whole
# difficulty of the third clause: `slot >= 0` is TRUE for every Python int, so the
# only thing it can be excluding is a NEGATIVE slot, and in a `U32` the negative
# range is the TOP half. `ca_neg_*` uses an incoming slot of `-3`, which this file
# writes as `4294967293`, and `ca_slot.of` writes `-1 - n` as `4294967295 - n`.
# A port that read `>= 0` as `!= 0` would answer the same for every slot the
# gate holds, because none of them is 0 -- so `ca_slot1` and `ca_neg_none` are
# the pair that separates the two readings.
#
# `b.replace(arg=replace(b.arg, slot=n))` is `dataclasses.replace` on a
# 13-field `ParamArg`, so `ca_slot.of` rebuilds the record with one field moved.
# `ca_arg.of` answers `None{}` for a non-`AParam`, and that `None{}` is Python's
# AttributeError -- `ca_noarg` is that row, and it is the one place the port is
# total where Python raises.
# ---------------------------------------------------------------------------
def ca_slot.of(x: O.ParamArg, n: U32) -> O.ParamArg:
  match x:
    case O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device,
                    volatile, image, buffer, bind_on_realize, val}:
      O.ParamArg{n, dtype, size, vmin_vmax, multiple_of, name, addrspace, device,
        volatile, image, buffer, bind_on_realize, val}

def ca_arg.of(arg: O.Arg) -> Maybe<&2, O.ParamArg>:
  match arg:
    case O.AParam{pa}: Some{pa}
    case _           : None{}

def ca_arg.slot(arg: O.Arg) -> Maybe<&2, U32>:
  match arg:
    case O.AParam{pa}: Some{O.ParamArg.slot(pa)}
    case _           : None{}

# `slot >= 0` on a Python int is `slot < 2**31` on the port's U32.
def ca_fresh(s: Maybe<&2, U32>, +as: List<&2, Aa>, +b: U32) -> Bool:
  match s:
    case Some{v}: Bool.and(U32.is_lt(v, 2147483648), Bool.not(aa_has(as, b)))
    case None{}  : False{}

# `-1 - len(ctx.allocs)` as a U32: one wrap, and `ca_slot1`/`ca_slot2` are the
# rows that would catch a wrap in the WRONG DIRECTION (`1 - len` answers 1 and 0
# and is still "negative-looking" enough to pass a boolean row).
def ca_slotn(c: CallifyCtx) -> U32:
  U32.sub(4294967295, U32.from_nat(List.length(&2, Aa, CallifyCtx.allocs(c))))

type CaPut is Data:
  CaPut{c: CallifyCtx, a: Maybe<&2, O.Found>}

def CaPut.c(x: CaPut) -> CallifyCtx:
  match x:
    case CaPut{c, a}: c

def CaPut.a(x: CaPut) -> Maybe<&2, O.Found>:
  match x:
    case CaPut{c, a}: a

def ca_new(fresh: Bool, +pa: O.ParamArg, +ar: O.Arena, +c: CallifyCtx, +b: U32) -> CaPut:
  match fresh:
    case True{}:
      +f = O.UOp.new(ar, sc_op(ar, b), sc_srcs(ar, b), O.AParam{pa}, sc_tag(ar, b))
      CaPut{aa_put(c, b, O.Found.i(f)), Some{f}}
    case False{}: CaPut{c, None{}}

def canonicalize_alloc.pa(m: Maybe<&2, O.ParamArg>, n: U32, s: Maybe<&2, U32>, +as: List<&2, Aa>, +ar: O.Arena, +c: CallifyCtx, +b: U32) -> CaPut:
  match m:
    case Some{pa}: ca_new(ca_fresh(s, as, b), ca_slot.of(pa, n), ar, c, b)
    case None{}  : CaPut{c, None{}}

def canonicalize_alloc(+c: CallifyCtx, +ar: O.Arena, +b: U32) -> CaPut:
  canonicalize_alloc.pa(ca_arg.of(sc_arg(ar, b)), ca_slotn(c),
    ca_arg.slot(sc_arg(ar, b)), CallifyCtx.allocs(c), ar, c, b)

# THE TWO WALLS THAT REMAIN, each with `file:line`, and each NOT a `graph_rewrite`:
#
# 10. `canonicalize_call_body` -- __init__.py:239-240. NO ctx. IT IS A ONE-LINE
#     BODY WHOSE ONE LINE IS THE REWRITER:
#         c.replace(src=(graph_rewrite(c.body, pm_canonicalize_alloc,
#                                     ctx=CallifyCtx(), bottom_up=True),)+c.src[1:])
#     The `c.replace(src=(X,)+c.src[1:])` half is `cks_rep` above and is PORTED;
#     the `graph_rewrite` half is the bottom_up engine over `PMEntrys`, which is
#     `uop/ops.bend`'s `pm_rewrite_m` and is not exported. There is no ctx work
#     left to do here -- `CallifyCtx` exists above -- so the wall is the ENGINE.
#     TODO(p3) __init__.py:240  `graph_rewrite(..., bottom_up=True)` -- no
#     bottom_up entry point; `ops.bend` has the top-down scan only.
#
# 11. `replace_input_buffer` -- __init__.py:248-250. NEEDS ctx, and it is the
#     ONLY ctx body left, so it is the last C2 item:
#         ctx.replacements.append(b)
#         return b.param_like(len(ctx.replacements)-1)
#     The append is one `List.append` and the `len` is one `List.length`; the
#     mint is the wall. `UOp.param_like` is `TODO(p3) ops.py:1239` in
#     `uop/ops.bend:4453` -- named, unported, and named as a TODO, so this is a
#     recorded deferral and not a gap I found.
#     TODO(p3) ops.py:1239  `UOp.param_like` -- no port. Blocks this body.
#
# 12. `contiguous_mops_to_view` -- __init__.py:199-215. It is the one of the
#     twelve that `06-UNBLOCKED.md` found passes NO ctx on any call, and that is
#     right about the CALL SITES but not about the SIGNATURE: :207 recurses with
#     `ctx` and :213 writes `ctx.views.add(view)`. So it needs ctx, weakly --
#     `if ctx is not None` at :213 makes the write optional.
#     It is the LARGEST of the twelve (17 lines) and every one of its five
#     helpers is missing or walled:
#     TODO(p3) ops.py:559  `all_int(c.shape)` -- `c.shape` needs `fold.bend`'s
#       `UOp.shape` and a whole-arena `Table`; `all_int` itself is
#       `helpers.bend`'s `all_int_nest` over a `Nest`.
#     TODO(p3) ops.py:561  `src.base` is ported; the `while buf.op is BITCAST`
#       peel is `UOp.base` with BITCAST added and is NOT a reader here.
#     TODO(p3) __init__.py:206  `graph_rewrite(src, multi_pm)` --
#       `schedule/multi.py`'s table.
#     TODO(p3) ops.py    `src.contiguous_view()` -- ABSENT from the tree. This is
#       the binding one: `:210` returns None when it is None, so without it the
#       rule has no fallthrough case and answering anything else would be a
#       fabrication.
#     WALL(p3) __init__.py:212  `buf[a:b]` (SHRINK) and `.bitcast` -- BLOCKED: needs `UOp.shrink` (tinygrad/uop/ops.py:192, `apply_movement_op`), the SHRINK builder `rangeify.bend` records as a WALL; `.bitcast` is NOT missing -- it is `mixin/dtype.bend`'s `bitcast_at` (:372), which mints `OpsBITCAST`.
#     TODO(p3) __init__.py:214  `.reshape` -- `mixin/movement.bend`'s.
#     TODO(p3) __init__.py:208  `.unshard` -- ABSENT from the tree.
#
# 13. `create_linear_with_vars` -- __init__.py:273-301. NO ctx, and it is the
#     TOP: five `graph_rewrite` passes at :276, :279, :282 plus the two at :240
#     and :267 inside the bodies above, `capturing[0].add_linear` at :297,
#     `memory_plan_rewrite` at :301, `used_vars` at :285 (which needs
#     `UOp.variables`, the same reader arm 3 of `apply_binds` needs) and the
#     `RuntimeError` bind-mismatch check at :292. Porting it before any of the
#     five matchers it calls would be a name with no body.
#     WALL(p3) __init__.py:276  `pm_schedule` -> `lower_sink_to_linear` (ported
#       above) but the PASS is a rewriter -- BLOCKED: needs the `pm_schedule` PatternMatcher + its `graph_rewrite` pass; the rule body `lower_sink_to_linear` IS ported (:1362) and `pm_schedule` has no def in the tree.
#     WALL(p3) __init__.py:279  `pm_resolve_linear_call` -> `resolve_linear_call`
#       (in `ops.bend`) + `pm_flatten_linear` from `engine/realize.py` -- BLOCKED: needs `resolve_linear_call`, which has NO DEF anywhere in the tree; the :1549 note that tag 42 holds it is FALSE (tag 42 is `_pm_resolve_params`, ops.bend:4044), and `pm_flatten_linear` is absent too.
#     WALL(p3) __init__.py:282  `pm_copy_from_store` -> the two bodies above plus
#       `assert_all_same_devices`, and the PASS is a rewriter -- BLOCKED: needs the `pm_copy_from_store` PatternMatcher + `graph_rewrite` pass. The THREE rule bodies are ALL PORTED (`cks_*` :1407, `simplify_copy_kernel` :1466, `assert_all_same_devices` :1527); only the PASS is absent.
#     TODO(p3) __init__.py:285  `used_vars` -- `UOp.variables`.
#     TODO(p3) __init__.py:301  `memory_plan_rewrite` -- `schedule/memory.py`.

# ===========================================================================
# THE GATE.
#
# Three fixtures, built in the arena with the same construction ORDER as
# `.agents/slop/notes/sched-truth.py`, so every index below is that file's index
# and `fx*_nodes` says how many there are. `fx1` and `fx2` are the Python's;
# `fx3` is the nested-AFTER chain `sched-truth.py` builds for `buf_uop`, and
# `BAD` is an AFTER with a SINK source, which `_split_after` DROPS here and
# which Python raises on.
#
#   fx1     1 C1  2 SPa  3 A1   4 SPb  5 B1   6 C0   7 ST1  8 BODY1  9 C2
#          10 ST2 11 BODY2 12 VB 13 Vu 14 K1 15 K2 16 E2 17 AF1 18 AF2 19 SINKA
#          20 TOP1 21 BAD            (so `fx1_nodes`=21 and `fx1_topo`=19)
#   fx2     1 C1  2 SPa  3 A2   4 SPx  5 X2   6 C0   7 ST1  8 BODY1  9 C2
#          10 ST2 11 BODY2 12 C3 13 ST3 14 BODY3 15 Ka 16 Kb 17 Kc 18 AFa 19 AFb
#          20 AFc 21 SINKA 22 TOP2
#   fx3     1 C1  2 SPa  3 A3   4 C0   5 C3   6 ST3  7 BODY3 8 K3 9 AG1 10 AG2
#          11 SINKA 12 TOP3 13 AG3 (AFTER(AG2, AG1), unreachable)
#   fx4     1 C1 2 SPa 3 A4 4 C0 5 C1 6 STAGE 7 MSTACK
#   fx5     1 C1  2 SPa  3 A5   4 C0   5 ST1  6 BODY1  7 C2   8 ST2  9 BODY2 10 Ka
#          11 AFa 12 Kb 13 AFb 14 SINKA 15 TOP5  (so `fx5_nodes`=16, `fx5_topo`=15)
#
# `Vu` and `BAD` are interned and NOT reachable from the sink, which is why
# `fx1_nodes` is 21 while `fx1_topo` is Python's 19.
# ===========================================================================
# `ParamArg(slot=0, dtype=int32, size=4, name='a', device='CPU')`. The port
# interned device NAMES as `S.D1{tag}`, and tag 0 stands for CPU.
def g_pb(+slot: U32, +nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{4}, None{}, None{}, Some{nm}, S.AGlobal{},
    Some{S.D1{0}}, False{}, None{}, None{}, False{}, None{}}

# `UOp.variable("v", 0, 10, dtype=int32)` and `.bind(3)`. The slot is `None` in
# Python's `-1`; nothing in this file reads a slot, so it is 0 here.
def g_pv(+nm: String, val: Maybe<&2, O.Const>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(10)}},
    Some{1}, Some{nm}, S.Aalu{}, None{}, False{}, None{}, None{}, False{}, val}

# `UOp(Ops.BUFFER, src=(UOp(Ops.SPECIAL, arg=name, src=(UOp.const(1),)),), arg=...)`
def g_buf(+slot: U32, +nm: String, ar: O.Arena) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  +sp = O.UOp.special(O.Found.ar(z), O.Found.i(z), nm)
  O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{g_pb(slot, nm)}, O.TNone{})

# `UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(UOp.const(0), UOp.const(n))),))`
def g_body(+n: U32, ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +cn = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(n)})
  +st = O.UOp.new(O.Found.ar(cn), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(cn)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])

# fx1: A1 <- K1, then AF1(AFTER(A1,K1)), AF2(AFTER(AF1, E2(K2))) where
# K2 = CALL(body(2), B1, v-bound-3), and TOP1 = SINK(AF2, SINK(A1)).
def fx1() -> O.Found:
  +a = g_buf(0, "a", O.Arena.empty())
  +b = g_buf(1, "b", O.Found.ar(a))
  +d1 = g_body(1, O.Found.ar(b))
  +d2 = g_body(2, O.Found.ar(d1))
  +vb = O.UOp.new(O.Found.ar(d2), O.OpsPARAM{}, Nil{}, O.AParam{g_pv("v", Some{O.CInt{H.i64_of_i32(3)}})}, O.TNone{})
  +vu = O.UOp.new(O.Found.ar(vb), O.OpsPARAM{}, Nil{}, O.AParam{g_pv("v", None{})}, O.TNone{})
  +k1 = O.UOp.new(O.Found.ar(vu), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +k2 = O.UOp.new(O.Found.ar(k1), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(b), O.Found.i(vb)], O.ANone{}, O.TNone{})
  +e2 = O.UOp.new(O.Found.ar(k2), O.OpsEND{}, [O.Found.i(k2)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(e2), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k1)], O.ANone{}, O.TNone{})
  +f2 = O.UOp.new(O.Found.ar(f1), O.OpsAFTER{}, [O.Found.i(f1), O.Found.i(e2)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(f2), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(f2), O.Found.i(sa)])

# `UOp(Ops.AFTER, src=(A1, K1, UOp(Ops.SINK, src=(A1,))))` -- the AFTER whose
# third source `_split_after` DROPS here and which Python raises on. Interned in
# fx1's arena and deliberately NOT reachable from the sink, so `fx1_nodes` (21) is
# two larger than `fx1_topo` (19, which is `sched-truth.py`'s printed `topo_n`):
# `Vu` and `BAD` are interned and nothing reaches them.
def fx1.bad() -> O.Found:
  O.UOp.new(O.Found.ar(fx1()), O.OpsAFTER{}, [3, 14, 19], O.ANone{}, O.TNone{})

# BAD's arena -- one node longer than `fx1.ar()`, because BAD lives at index 21.
def fx1.arb() -> O.Arena: O.Found.ar(fx1.bad())

# fx2: three kernels on TWO states, A2 written twice. Ka and Kb both write A2, so
# Kb READS the state AFa superseded and Ka must run AFTER it -- the WAR edge.
def fx2() -> O.Found:
  +a = g_buf(0, "a2", O.Arena.empty())
  +x = g_buf(1, "x2", O.Found.ar(a))
  +d1 = g_body(1, O.Found.ar(x))
  +d2 = g_body(2, O.Found.ar(d1))
  +d3 = g_body(3, O.Found.ar(d2))
  +ka = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +kb = O.UOp.new(O.Found.ar(ka), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(a)], O.ANone{}, O.TNone{})
  +kc = O.UOp.new(O.Found.ar(kb), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(x)], O.ANone{}, O.TNone{})
  +fa = O.UOp.new(O.Found.ar(kc), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(ka)], O.ANone{}, O.TNone{})
  +fb = O.UOp.new(O.Found.ar(fa), O.OpsAFTER{}, [O.Found.i(fa), O.Found.i(kb)], O.ANone{}, O.TNone{})
  +fc = O.UOp.new(O.Found.ar(fb), O.OpsAFTER{}, [O.Found.i(x), O.Found.i(kc)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(fc), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(fb), O.Found.i(fc), O.Found.i(sa)])

# fx3: AG1(AFTER(A3,K3)), AG2(AFTER(AG1,K3)) -- the nested AFTER chain, and the
# `AFTER(AFTER(...))` case `sched-truth.py` builds for `buf_uop`.
def fx3() -> O.Found:
  +a = g_buf(0, "a3", O.Arena.empty())
  +d3 = g_body(3, O.Found.ar(a))
  +k3 = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(a)], O.ANone{}, O.TNone{})
  +g1 = O.UOp.new(O.Found.ar(k3), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k3)], O.ANone{}, O.TNone{})
  +g2 = O.UOp.new(O.Found.ar(g1), O.OpsAFTER{}, [O.Found.i(g1), O.Found.i(k3)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(g2), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(g2), O.Found.i(sa)])

# fx5: the RAW-dep path and the backward-slice suppression, which no other fixture
# reaches. `Kb` reads BOTH A5 and `AFa`, so `AFa` is a read state that is an AFTER
# and `Ka = AFa`'s kernel becomes a RAW producer of `Kb` (__init__.py:52-56). And
# because `Kb` reads `AFa`, `Ka` is in `Kb.backward_slice`, so the WAR candidate
# (Kb, Ka) that A5's write proposes is SUPPRESSED (__init__.py:63) -- drop that
# test and `in_degree` never reaches zero and nothing is linearized at all.
def fx5() -> O.Found:
  +a = g_buf(0, "a5", O.Arena.empty())
  +d1 = g_body(1, O.Found.ar(a))
  +d2 = g_body(2, O.Found.ar(d1))
  +ka = O.UOp.new(O.Found.ar(d2), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +fa = O.UOp.new(O.Found.ar(ka), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(ka)], O.ANone{}, O.TNone{})
  +kb = O.UOp.new(O.Found.ar(fa), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(a), O.Found.i(fa)], O.ANone{}, O.TNone{})
  +fb = O.UOp.new(O.Found.ar(kb), O.OpsAFTER{}, [O.Found.i(fa), O.Found.i(kb)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(fb), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(fb), O.Found.i(sa)])

# fx4: the two ops that `buf_uop`'s stop set adds to `{BUFFER, ALLOC, PARAM}` and
# that no other fixture has. `MSTACK(a, a)` is Python's `UOp(Ops.MSTACK, src=(a,
# a))` and `STAGE(c0, c1)` its two-source form.
def fx4() -> O.Found:
  +a = g_buf(0, "a4", O.Arena.empty())
  +c0 = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +st = O.UOp.new(O.Found.ar(c1), O.OpsSTAGE{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(st), O.OpsMSTACK{}, [O.Found.i(a), O.Found.i(a)], O.ANone{}, O.TNone{})

# `fx3.after_after` -- an AFTER whose SECOND source is an AFTER, so `_split_after`
#'s dep half is exercised. Interned in fx3's arena, not reachable from the sink.
def fx3.after_after() -> O.Found:
  O.UOp.new(O.Found.ar(fx3()), O.OpsAFTER{}, [10, 9], O.ANone{}, O.TNone{})

def fx1.ar() -> O.Arena: O.Found.ar(fx1())
def fx1.top() -> U32: O.Found.i(fx1())
def fx2.ar() -> O.Arena: O.Found.ar(fx2())
def fx2.top() -> U32: O.Found.i(fx2())
def fx3.ar() -> O.Arena: O.Found.ar(fx3())
def fx3.top() -> U32: O.Found.i(fx3())
def fx3.arb() -> O.Arena: O.Found.ar(fx3.after_after())
def fx3.aa() -> U32: O.Found.i(fx3.after_after())
def fx5.ar() -> O.Arena: O.Found.ar(fx5())
def fx5.top() -> U32: O.Found.i(fx5())
def fx4.ar() -> O.Arena: O.Found.ar(fx4())
def fx4.st() -> U32: U32.sub(O.Found.i(fx4()), 1)
def fx4.ms() -> U32: O.Found.i(fx4())

# ===========================================================================
# THE GATE'S READERS. `gate.code` is `sched-truth.py`'s `code()` verbatim, plus
# LINEAR=10 and MSTACK=11, which that script never needed. `gate.enc` is its
# `enc()`, so a row like `fx1_marks=12` is the same string Python printed.
# ===========================================================================
def gate.code(op: O.Op) -> U32:
  match op:
    case O.OpsBUFFER{}: 1
    case O.OpsAFTER{} : 2
    case O.OpsPARAM{} : 3
    case O.OpsCALL{}  : 4
    case O.OpsEND{}   : 5
    case O.OpsSTORE{} : 6
    case O.OpsSINK{}  : 7
    case O.OpsSPECIAL{}: 8
    case O.OpsCONST{} : 9
    case O.OpsNOOP{}  : 99
    case O.OpsLINEAR{}: 10
    case O.OpsMSTACK{}: 11
    case O.OpsSTAGE{} : 12
    case _            : 0

# `r = r * 10 + x`, and `mark` is `k.src[0].src[0].src[1].val` -- the STORE's
# value CONST. `H` has `i32 -> i64` and no way back, so the DIGIT is picked by
# equality; the fixture only ever stores 1, 2 or 3.
def gate.digit.pick(hit: Bool, acc: U32, n: U32) -> U32:
  match hit:
    case True{} : n
    case False{}: acc

def gate.digit(+i: H.I64) -> U32:
  gate.digit.pick(O.eq_i64(i, H.i64_of_i32(1)),
    gate.digit.pick(O.eq_i64(i, H.i64_of_i32(2)),
      gate.digit.pick(O.eq_i64(i, H.i64_of_i32(3)), 0, 3), 2), 1)

def gate.val.c(c: O.Const) -> H.I64:
  match c:
    case O.CInt{i}: i
    case _         : H.i64_of_i32(0)

# the CONST's arg is `APy{Const}`, so the `.val` is one `match` deeper than the
# node read above it.
def gate.val(arg: O.Arg) -> H.I64:
  match arg:
    case O.APy{c}: gate.val.c(c)
    case _        : H.i64_of_i32(0)

def gate.mark(+ar: O.Arena, k: U32) -> U32:
  gate.digit(gate.val(sc_arg(ar, sc_src(ar, sc_src0(ar, sc_src0(ar, k)), 1))))
def gate.marks.go(ks: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ks:
    case Nil{}     : acc
    case k <> rest : gate.marks.go(rest, ar, U32.add(U32.mul(acc, 10), gate.mark(ar, k)))


def gate.marks(+ar: O.Arena, ks: List<&2, U32>) -> U32:
  gate.marks.go(ks, ar, 0)
def gate.nsrcs.go(ks: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ks:
    case Nil{}     : acc
    case k <> rest : gate.nsrcs.go(rest, ar, U32.add(U32.mul(acc, 10), sc_nsrc(ar, k)))



def gate.nsrcs(+ar: O.Arena, ks: List<&2, U32>) -> U32:
  gate.nsrcs.go(ks, ar, 0)


# every linearized kernel's srcs, in LINEAR ORDER: `Lin.out` is appended at the
# right, so it needs no reversal (the QUEUE is reversed; `Lin.out` is not).
def gate.ops.of(ss: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ss:
    case Nil{}     : acc
    case s <> rest : gate.ops.of(rest, ar, U32.add(U32.mul(acc, 10), gate.code(sc_op(ar, s))))

def gate.ops.go(ks: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ks:
    case Nil{}          : acc
    case k <> rest      : gate.ops.go(rest, ar, gate.ops.of(sc_srcs(ar, k), ar, acc))

def gate.ops(+ar: O.Arena, ks: List<&2, U32>) -> U32:
  gate.ops.go(ks, ar, 0)

# the length of `Split`'s two halves, for the `_split_after` rows
def gate.ks(+ar: O.Arena, a: U32) -> U32:
  U32.from_nat(List.length(&2, U32, Split.ks(sc_split(ar, a))))

def gate.ds(+ar: O.Arena, a: U32) -> U32:
  U32.from_nat(List.length(&2, U32, Split.ds(sc_split(ar, a))))

# the TOTAL child edges, which is one for fx2 and zero for fx1 -- the edge the
# WAR pass added and the one the linearization turns on.
def kids_n.go(+ks: List<&2, Kid>, acc: U32) -> U32:
  match ks:
    case Nil{}           : acc
    case Kid{k, vs} <> t : kids_n.go(t, U32.add(acc, U32.from_nat(List.length(&2, U32, vs))))

def kids_n(c: Ctx) -> U32:
  kids_n.go(Ctx.kids(c), 0)

def b2u(b: Bool) -> U32:
  match b:
    case True{} : 1
    case False{}: 0

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ===========================================================================
# THE ROWS. Every expectation below is `sched-truth.py`'s printed output, and the
# comment over each block is that output.
# ===========================================================================
def t_unwrap_A1() -> U32: gate.code(sc_op(fx1.ar(), sc_unwrap(fx1.ar(), 3)))
def t_unwrap_B1() -> U32: gate.code(sc_op(fx1.ar(), sc_unwrap(fx1.ar(), 5)))
def t_unwrap_Vb() -> U32: gate.code(sc_op(fx1.ar(), sc_unwrap(fx1.ar(), 12)))
def t_unwrap_AF1() -> U32: gate.code(sc_op(fx1.ar(), sc_unwrap(fx1.ar(), 17)))
def t_unwrap_AF2() -> U32: gate.code(sc_op(fx1.ar(), sc_unwrap(fx1.ar(), 18)))
def t_unwrap_bad() -> U32: gate.code(sc_op(fx1.arb(), sc_unwrap(fx1.arb(), O.Found.i(fx1.bad()))))

# sched-truth.py: `split_A1 ks=0 ds=0` .. `split_AG2 ks=1 ds=0` and
# `split_bad RAISED`. BAD's sources are K1 (a CALL) and a SINK, so the kernels
# half is 1 and the SINK is DROPPED where Python raises -- `split_bad_ks` pins
# the drop, and `split_AF2_ds=0` pins the AFTER half of a real one.
def t_split_A1() -> U32: gate.ks(fx1.ar(), 3)
def t_split_AF1() -> U32: gate.ks(fx1.ar(), 17)
def t_split_AF2() -> U32: gate.ks(fx1.ar(), 18)
def t_split_AG1() -> U32: gate.ks(fx3.ar(), 9)
def t_split_AG2() -> U32: gate.ks(fx3.ar(), 10)
def t_split_bad() -> U32: gate.ks(fx1.arb(), O.Found.i(fx1.bad()))
def t_split_AF2_ds() -> U32: gate.ds(fx1.ar(), 18)

# `states_A1 1 ['BUFFER']`, `states_AF2 1 ['AFTER']`, `states_AG2 1 ['AFTER']`
def t_states_A1() -> U32: U32.from_nat(List.length(&2, U32, sc_states(sc_fuel(fx1.ar()), fx1.ar(), 3)))
def t_states_AF2() -> U32: U32.from_nat(List.length(&2, U32, sc_states(sc_fuel(fx1.ar()), fx1.ar(), 18)))
def t_states_AG2() -> U32: U32.from_nat(List.length(&2, U32, sc_states(sc_fuel(fx3.ar()), fx3.ar(), 10)))

# `bufuop_A1 1 bufuop_AF1 1 bufuop_AF2 1 / bufuop_AG1 1 bufuop_AG2 1 bufuop_Vb 3`
def t_bu_A1() -> U32: gate.code(sc_op(fx1.ar(), sc_buf_uop(fx1.ar(), 3)))
def t_bu_AF1() -> U32: gate.code(sc_op(fx1.ar(), sc_buf_uop(fx1.ar(), 17)))
def t_bu_AF2() -> U32: gate.code(sc_op(fx1.ar(), sc_buf_uop(fx1.ar(), 18)))
def t_bu_Vb() -> U32: gate.code(sc_op(fx1.ar(), sc_buf_uop(fx1.ar(), 12)))
def t_bu_AG1() -> U32: gate.code(sc_op(fx3.ar(), sc_buf_uop(fx3.ar(), 9)))
def t_bu_AG2() -> U32: gate.code(sc_op(fx3.ar(), sc_buf_uop(fx3.ar(), 10)))

# `bv_Vb 1 bv_Vu 0 bv_A1 0` -- and the bound var is a CALL's src[2]
def t_bv_Vb() -> U32: b2u(sc_is_bound_var(fx1.ar(), 12))
def t_bv_Vu() -> U32: b2u(sc_is_bound_var(fx1.ar(), 13))
def t_bv_A1() -> U32: b2u(sc_is_bound_var(fx1.ar(), 3))
def t_bv_K2src2() -> U32: b2u(sc_is_bound_var(fx1.ar(), sc_src(fx1.ar(), 15, 2)))

# `bs_K2_K1 0 bs_E2_K2 1 bs_K1_K2 0 bs_Kb_Ka 0`
def t_bs_K2_K1() -> U32: b2u(sc_in_bs(fx1.ar(), 15, 14))
def t_bs_E2_K2() -> U32: b2u(sc_in_bs(fx1.ar(), 16, 15))
def t_bs_K1_K2() -> U32: b2u(sc_in_bs(fx1.ar(), 14, 15))
def t_bs_Kb_Ka() -> U32: b2u(sc_in_bs(fx2.ar(), 16, 15))

# fx1: `topo_n 19 lin_n 2 lin_op LINEAR / marks 12 nsrcs 22 /
#        lin_src_ops [['SINK','BUFFER'],['SINK','BUFFER']]`
# fx2: `topo_n 22 lin_n 3 lin_op LINEAR / marks 231 nsrcs 222`
def t_fx1_topo() -> U32: U32.from_nat(List.length(&2, U32, sc_topo_of(O.Arena.budget(fx1.ar()), fx1.ar(), fx1.top())))
def t_fx2_topo() -> U32: U32.from_nat(List.length(&2, U32, sc_topo_of(O.Arena.budget(fx2.ar()), fx2.ar(), fx2.top())))
def t_fx1_nodes() -> U32: O.Arena.next(fx1.ar())
def t_fx2_nodes() -> U32: O.Arena.next(fx2.ar())

# THE ARENA IS `Lin.ar`, NOT `fx1.ar()`: `k.replace(src=...)` interned the
# linearized kernels, so they live at indices past `fx1.ar()`'s end and reading
# them from the fixture's arena answers the bottom node (code 99). `lin_n` is the
# only row here that does not need it, because it is a length.
def t_fx1.lin.of(+l: Lin) -> U32:
  U32.from_nat(List.length(&2, U32, Lin.out(l)))

def t_fx2.lin.of(+l: Lin) -> U32:
  U32.from_nat(List.length(&2, U32, Lin.out(l)))

def t_fx1.lin.op(+f: O.Found) -> U32:
  gate.code(sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx2.lin.op(+f: O.Found) -> U32:
  gate.code(sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx1.lin.marks(+l: Lin) -> U32:
  gate.marks(Lin.ar(l), Lin.out(l))

def t_fx2.lin.marks(+l: Lin) -> U32:
  gate.marks(Lin.ar(l), Lin.out(l))

def t_fx1.lin.nsrcs(+l: Lin) -> U32:
  gate.nsrcs(Lin.ar(l), Lin.out(l))

def t_fx2.lin.nsrcs(+l: Lin) -> U32:
  gate.nsrcs(Lin.ar(l), Lin.out(l))

def t_fx1.lin.ops(+l: Lin) -> U32:
  gate.ops(Lin.ar(l), Lin.out(l))

def t_fx2.lin.ops(+l: Lin) -> U32:
  gate.ops(Lin.ar(l), Lin.out(l))

def t_fx1_lin_op() -> U32: t_fx1.lin.op(linear(schedule(fx1.ar(), fx1.top())))
def t_fx2_lin_op() -> U32: t_fx2.lin.op(linear(schedule(fx2.ar(), fx2.top())))
def t_fx1_marks() -> U32: t_fx1.lin.marks(schedule(fx1.ar(), fx1.top()))
def t_fx2_marks() -> U32: t_fx2.lin.marks(schedule(fx2.ar(), fx2.top()))
def t_fx1_nsrcs() -> U32: t_fx1.lin.nsrcs(schedule(fx1.ar(), fx1.top()))
def t_fx2_nsrcs() -> U32: t_fx2.lin.nsrcs(schedule(fx2.ar(), fx2.top()))
def t_fx1_ops() -> U32: t_fx1.lin.ops(schedule(fx1.ar(), fx1.top()))
def t_fx2_ops() -> U32: t_fx2.lin.ops(schedule(fx2.ar(), fx2.top()))
def t_fx1_lin_n() -> U32: t_fx1.lin.of(schedule(fx1.ar(), fx1.top()))
def t_fx2_lin_n() -> U32: t_fx2.lin.of(schedule(fx2.ar(), fx2.top()))


# `_split_after`'s DEP half: `AG2` is `AFTER(AG1, K3)`, so its sources are a
# kernel; `AG3` is `AFTER(AG2, AG1)`, so its sources are an AFTER, and Python's
# partition puts AG1 in `deps` and nothing in `kernels`.
def t_split_AG3_ks() -> U32: gate.ks(fx3.arb(), fx3.aa())
def t_split_AG3_ds() -> U32: gate.ds(fx3.arb(), fx3.aa())

# `buf_uop` on the two ops its stop set adds. With the wider stop set the walk
# answers the node itself; without it the walk descends to the BUFFER and both
# print 1.
def t_bu_STAGE() -> U32: gate.code(sc_op(fx4.ar(), sc_buf_uop(fx4.ar(), fx4.st())))
def t_bu_MSTACK() -> U32: gate.code(sc_op(fx4.ar(), sc_buf_uop(fx4.ar(), fx4.ms())))

# THE COUNT ROWS. THE WRITES' KERNEL LISTS, summed: fx1 1+1, fx2 1+1+1, fx3 1+0.
# fx3's zero is the `prev_kernels` filter -- `AG2 = AFTER(AG1, K3)` and K3 is
# already a kernel of AG1, so AG2 supersedes nothing new -- and `COUNT_fx3_wrks`
# is the only row in the file that sees that filter.
def wrks_n.go(+ws: List<&2, Wrt>, acc: U32) -> U32:
  match ws:
    case Nil{}           : acc
    case Wrt{a, ks} <> t : wrks_n.go(t, U32.add(acc, U32.from_nat(List.length(&2, U32, ks))))

def wrks_n.go2(+ws: List<&2, Wrn>, acc: U32) -> U32:
  match ws:
    case Nil{}           : acc
    case Wrn{s, vs} <> t : wrks_n.go2(t, wrks_n.go(vs, acc))

def wrks_n(c: Ctx) -> U32:
  wrks_n.go2(Ctx.wrns(c), 0)

def t_fx3_wrns() -> U32: U32.from_nat(List.length(&2, Wrn, Ctx.wrns(pass2(fx3.ar(), pass1(fx3.ar(), fx3.top())))))
def t_fx3_wrks() -> U32: wrks_n(pass2(fx3.ar(), pass1(fx3.ar(), fx3.top())))

def t_fx3.lin.marks(+l: Lin) -> U32:
  gate.marks(Lin.ar(l), Lin.out(l))

def t_fx3.lin.of(+l: Lin) -> U32:
  U32.from_nat(List.length(&2, U32, Lin.out(l)))

def t_fx5_nodes() -> U32: O.Arena.next(fx5.ar())
def t_fx5_topo() -> U32: U32.from_nat(List.length(&2, U32, sc_topo_of(O.Arena.budget(fx5.ar()), fx5.ar(), fx5.top())))
def t_fx5_lin_n() -> U32: t_fx3.lin.of(schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.op(+f: O.Found) -> U32:
  gate.code(sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx5_lin_op() -> U32: t_fx3.lin.op(linear(schedule(fx5.ar(), fx5.top())))
def t_fx5_marks() -> U32: t_fx3.lin.marks(schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.nsrcs(+l: Lin) -> U32:
  gate.nsrcs(Lin.ar(l), Lin.out(l))

def t_fx5_nsrcs() -> U32: t_fx3.lin.nsrcs(schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.ops(+l: Lin) -> U32:
  gate.ops(Lin.ar(l), Lin.out(l))

def t_fx5_ops() -> U32: t_fx3.lin.ops(schedule(fx5.ar(), fx5.top()))



def t_fx5_kids() -> U32: U32.from_nat(List.length(&2, Kid, Ctx.kids(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))))
def t_fx5_degs() -> U32: U32.from_nat(List.length(&2, Dep, Ctx.degs(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))))
def t_fx5_wrns() -> U32: U32.from_nat(List.length(&2, Wrn, Ctx.wrns(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))))
def t_fx5_rds() -> U32: U32.from_nat(List.length(&2, Rd, Ctx.rds(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))))
def t_fx5_zero() -> U32: U32.from_nat(List.length(&2, U32, zero(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))))
def t_fx5_cyc() -> U32: U32.from_nat(cycles(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top()))))
def t_fx5_kidn() -> U32: kids_n(pass2(fx5.ar(), pass1(fx5.ar(), fx5.top())))

# `Ka in Kb.backward_slice` -- the predicate that suppresses the WAR edge here.
def t_bs_Ka_Kb() -> U32: b2u(sc_in_bs(fx5.ar(), 12, 10))

def t_fx3_lin_n() -> U32: t_fx3.lin.of(schedule(fx3.ar(), fx3.top()))
def t_fx3_marks() -> U32: t_fx3.lin.marks(schedule(fx3.ar(), fx3.top()))

# THE COUNT ROWS. `n_children n_in_degree n_writes n_reads n_zero cycle`:
#   fx1 `0 2 2 3 2 0`   fx2 `1 3 3 3 2 1`
# `zero_deg_order` is `11` for both and `deg_K fx1 {'CALL':0,'END':0}` /
# `{'CALL':0}` for fx2 -- so the SUM of the degrees is a row too, because a
# wrong `in_degree` that still has the right KEY SET would slip past the count.
def t_fx1_kids() -> U32: U32.from_nat(List.length(&2, Kid, Ctx.kids(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))))
def t_fx1_degs() -> U32: U32.from_nat(List.length(&2, Dep, Ctx.degs(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))))
def t_fx1_wrns() -> U32: U32.from_nat(List.length(&2, Wrn, Ctx.wrns(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))))
def t_fx1_rds() -> U32: U32.from_nat(List.length(&2, Rd, Ctx.rds(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))))
def t_fx1_zero() -> U32: U32.from_nat(List.length(&2, U32, zero(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))))
def t_fx1_cyc() -> U32: U32.from_nat(cycles(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top()))))
def t_fx1_kids_n() -> U32: kids_n(pass2(fx1.ar(), pass1(fx1.ar(), fx1.top())))
def t_fx2_kids() -> U32: U32.from_nat(List.length(&2, Kid, Ctx.kids(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))))
def t_fx2_degs() -> U32: U32.from_nat(List.length(&2, Dep, Ctx.degs(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))))
def t_fx2_wrns() -> U32: U32.from_nat(List.length(&2, Wrn, Ctx.wrns(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))))
def t_fx2_rds() -> U32: U32.from_nat(List.length(&2, Rd, Ctx.rds(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))))
def t_fx2_zero() -> U32: U32.from_nat(List.length(&2, U32, zero(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))))
def t_fx2_cyc() -> U32: U32.from_nat(cycles(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top()))))
def t_fx2_kids_n() -> U32: kids_n(pass2(fx2.ar(), pass1(fx2.ar(), fx2.top())))

# ===========================================================================
# THE TWELVE'S ROWS. Every expectation is `sb-oracle.py`'s printed output and
# NONE is typed. Run `sh checks/sb-gate.sh`, which diffs
# whole `name=value` LINES and never row names.
#
# `gate.code` gains ALLOC and PROGRAM. Both are NEW codes no base row reads, so
# the 81 rows are unaffected -- and `sb-gate.sh` re-checks that on every run
# rather than taking it. `usb_SA_A` NEEDS the ALLOC code: a BUFFER and an ALLOC
# are different `unsharded_base` answers and a boolean row cannot tell them
# apart. `ab_body_C_PROG` needs the PROGRAM code.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("unwrap_A1", t_unwrap_A1())
    b : Unit <- row("unwrap_B1", t_unwrap_B1())
    c : Unit <- row("unwrap_Vb", t_unwrap_Vb())
    d : Unit <- row("unwrap_AF1", t_unwrap_AF1())
    e : Unit <- row("unwrap_AF2", t_unwrap_AF2())
    f : Unit <- row("unwrap_bad", t_unwrap_bad())
    g : Unit <- row("split_A1_ks", t_split_A1())
    h : Unit <- row("split_AF1_ks", t_split_AF1())
    i : Unit <- row("split_AF2_ks", t_split_AF2())
    j : Unit <- row("split_AG1_ks", t_split_AG1())
    k : Unit <- row("split_AG2_ks", t_split_AG2())
    l : Unit <- row("split_AF2_ds", t_split_AF2_ds())
    m : Unit <- row("split_bad_ks", t_split_bad())
    n : Unit <- row("states_A1", t_states_A1())
    o : Unit <- row("states_AF2", t_states_AF2())
    p : Unit <- row("states_AG2", t_states_AG2())
    q : Unit <- row("bufuop_A1", t_bu_A1())
    r : Unit <- row("bufuop_AF1", t_bu_AF1())
    s : Unit <- row("bufuop_AF2", t_bu_AF2())
    t : Unit <- row("bufuop_Vb", t_bu_Vb())
    u : Unit <- row("bufuop_AG1", t_bu_AG1())
    v : Unit <- row("bufuop_AG2", t_bu_AG2())
    w : Unit <- row("bv_Vb", t_bv_Vb())
    x : Unit <- row("bv_Vu", t_bv_Vu())
    y : Unit <- row("bv_A1", t_bv_A1())
    z : Unit <- row("bv_K2src2", t_bv_K2src2())
    a2 : Unit <- row("bs_K2_K1", t_bs_K2_K1())
    b2 : Unit <- row("bs_E2_K2", t_bs_E2_K2())
    c2 : Unit <- row("bs_K1_K2", t_bs_K1_K2())
    d2 : Unit <- row("bs_Kb_Ka", t_bs_Kb_Ka())
    e2 : Unit <- row("fx1_nodes", t_fx1_nodes())
    f2 : Unit <- row("fx1_topo", t_fx1_topo())
    g2 : Unit <- row("fx1_lin_n", t_fx1_lin_n())
    h2 : Unit <- row("fx1_lin_op", t_fx1_lin_op())
    i2 : Unit <- row("fx1_marks", t_fx1_marks())
    j2 : Unit <- row("fx1_nsrcs", t_fx1_nsrcs())
    k2 : Unit <- row("fx1_ops", t_fx1_ops())
    l2 : Unit <- row("fx2_nodes", t_fx2_nodes())
    m2 : Unit <- row("fx2_topo", t_fx2_topo())
    n2 : Unit <- row("fx2_lin_n", t_fx2_lin_n())
    o2 : Unit <- row("fx2_lin_op", t_fx2_lin_op())
    p2 : Unit <- row("fx2_marks", t_fx2_marks())
    q2 : Unit <- row("fx2_nsrcs", t_fx2_nsrcs())
    r2 : Unit <- row("fx2_ops", t_fx2_ops())
    s2 : Unit <- row("COUNT_fx1_kids", t_fx1_kids())
    t2 : Unit <- row("COUNT_fx1_degs", t_fx1_degs())
    u2 : Unit <- row("COUNT_fx1_wrns", t_fx1_wrns())
    v2 : Unit <- row("COUNT_fx1_rds", t_fx1_rds())
    w2 : Unit <- row("COUNT_fx1_zero", t_fx1_zero())
    x2 : Unit <- row("COUNT_fx1_cyc", t_fx1_cyc())
    y2 : Unit <- row("COUNT_fx1_kidn", t_fx1_kids_n())
    z2 : Unit <- row("COUNT_fx2_kids", t_fx2_kids())
    a3 : Unit <- row("COUNT_fx2_degs", t_fx2_degs())
    b3 : Unit <- row("COUNT_fx2_wrns", t_fx2_wrns())
    c3 : Unit <- row("COUNT_fx2_rds", t_fx2_rds())
    d3 : Unit <- row("COUNT_fx2_zero", t_fx2_zero())
    e3 : Unit <- row("COUNT_fx2_cyc", t_fx2_cyc())
    row("split_AG3_ks", t_split_AG3_ks())
    row("split_AG3_ds", t_split_AG3_ds())
    row("bufuop_STAGE", t_bu_STAGE())
    row("bufuop_MSTACK", t_bu_MSTACK())
    row("COUNT_fx3_wrns", t_fx3_wrns())
    row("COUNT_fx3_wrks", t_fx3_wrks())
    row("fx3_lin_n", t_fx3_lin_n())
    row("fx3_marks", t_fx3_marks())
    row("fx5_nodes", t_fx5_nodes())
    row("fx5_topo", t_fx5_topo())
    row("fx5_lin_n", t_fx5_lin_n())
    row("fx5_lin_op", t_fx5_lin_op())
    row("fx5_marks", t_fx5_marks())
    row("fx5_nsrcs", t_fx5_nsrcs())
    row("fx5_ops", t_fx5_ops())
    row("bs_Ka_Kb", t_bs_Ka_Kb())
    row("COUNT_fx5_kids", t_fx5_kids())
    row("COUNT_fx5_degs", t_fx5_degs())
    row("COUNT_fx5_wrns", t_fx5_wrns())
    row("COUNT_fx5_rds", t_fx5_rds())
    row("COUNT_fx5_zero", t_fx5_zero())
    row("COUNT_fx5_cyc", t_fx5_cyc())
    row("COUNT_fx5_kidn", t_fx5_kidn())
    row("COUNT_fx2_kidn", t_fx2_kids_n())
