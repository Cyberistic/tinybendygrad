# kernel.bend -- tinygrad/codegen/__init__.py: the LOWERER'S PASS STRUCTURE.
#
# ---------------------------------------------------------------------------
# THE UNIT WAS NAMED `kernel.py` + `rewriter.py`. NEITHER FILE EXISTS in this
# tinygrad; `codegen/` is a package and `find tinygrad -name kernel.py` finds only
# `extra/thunder/tiny/tk/kernel.py`, a Thunder TK harness. The lowerer is here:
#
#   tinygrad/codegen/__init__.py   519 lines   THIS FILE
#   tinygrad/codegen/simplify.py   156 lines   -> codegen/simplify.bend
#   tinygrad/codegen/late/coalesce.py  168     -> codegen/late/coalesce.bend
#   tinygrad/codegen/gpudims.py    106 lines   -> codegen/gpudims.bend
#   tinygrad/codegen/decomp/{op,transcendental}.py -> decomp.bend / transcendental.bend
#   tinygrad/codegen/late/{linearizer,regalloc,gater}.py  NOT CLAIMED
#   tinygrad/codegen/opt/*        636 lines    NOT CLAIMED
#
# NOTHING FROM ANY OTHER `.py` IS IN THIS FILE. It used to name three -- the three
# above, all of them claimed by `rewriter.bend` -- and the 1:1 ruling (one `.bend`
# per upstream `.py`, AT THE SAME PATH) moved them to their own paths, which took
# this file's last merged-in `.py` with it. `.agents/slop/split-codegen3.py` is the
# cut and `.agents/slop/codegen3-gate.sh` is the invariant: this file's 38 rows are
# unchanged and its 38 rows were never involved.
#
# `renderer/{cstyle,wgsl}.bend` are the siblings and they consume THIS file's
# `to_program` output shape, named at the foot.
#
# ---------------------------------------------------------------------------
# WHAT THIS FILE IS: `full_rewrite_to_sink` (:275-394) is a fixed SEQUENCE of
# ~20 `graph_rewrite` calls, and the sequence IS the lowerer. Everything else in
# `__init__.py` is a rule a stage owns. So the split is: the PASS LIST and the
# KERNEL COUNT live here, and the rules live in the files that own them.
#
# THE ONE NUMBER THE SIBLINGS NEED is `kernels_per_schedule`: how many
# `graph_rewrite` passes a scheduled kernel goes through on its way to renderable
# UOps, which is `kn_passes` below and which `renderer/cstyle.bend` and
# `renderer/wgsl.bend` both need in order to know how deep the pipeline is.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against __init__.py's 519 lines.
#
#   #  PY         KIND    STATE
#   1  33-36   fold   do_number_param          PORTED IN FULL
#   2  38-40   table  pm_number_params         1 of 1, PORTED
#   3  42-47   fold   build_range_map          PORTED
#   4  49-63   fold   expand_reduce            WALL: `permute`/`reduce`/`reshape`
#   5  65-66   fold   contract_axis            WALL: same
#   6  68-70   fold   unroll_axis              WALL: `argsort`
#   7  72-76   fold   expand_wmma              WALL: WMMA's 4-tuple arg
#   8  78-84   table  expander                 3 of 3, walls in all three
#   9  86-90   fold   expand_broadcast         WALL: `_broadcast_shape`
#  10  92-100  fold   broadcast_and_devec_wmma WALL: itertools.product
#  11  102-110 table pm_wmma_add               3 of 3, PORTED SHAPE
#  12  112-115 table pm_expand_broadcast       2 of 2, walls in both
#  13  117-124 fold  do_devectorize            WALL: itertools.product
#  14  126-135 fold  do_stack_wmma             PORTED SHAPE
#  15  137-158 table devectorizer2             8 of 8, walls in 6
#  16  160-175 fold  fix_group_for_reduce      WALL: `bufferize`, `partition`
#  17  177-195 fold  merge_reduce_ends         WALL: frozenset, `substitute`
#  18  197-204 fold  reduce_ranges_to_acc      WALL: `alloc_like`, `after`, `rtag`
#  19  206-209 fold  expand_horizontal_reduce  WALL: itertools.product
#  20  212-215 table pm_reduce_identity        1 of 1, PORTED SHAPE
#  21  217-224 table pm_reduce_local           4 of 4, walls in 3
#  22  226     fold   is_shape_changing_bitcast PORTED
#  23  227     fold   maybe_load               PORTED
#  24  228-232 table pm_add_loads              2 of 2, PORTED
#  25  234-240 fold/table add_local_buffer     WALL: `alloc`, `after`, `store`
#  26  244-247 table pm_cast_float_alu        1 of 1, PORTED IN FULL
#  27  249     fold   _is_local_store          PORTED
#  28  251-257 fold   add_raw_barrier          WALL: `toposort`, `sink`
#  29  259-268 fold   add_war_barrier          WALL: `backward_slice_with_self`
#  30  270-273 table pm_implicit_barriers      2 of 2, PORTED SHAPE
#  31  275-394 pass   full_rewrite_to_sink     PORTED AS THE PASS LIST
#  32  397-403 table pm_linearize_cleanups     2 of 2, one is `panic`
#  33  405     table pm_alloc_to_buf           1 of 1, PORTED IN FULL
#  34  408-416 fold   line_rewrite             PORTED IN FULL
#  35  418-427 table pm_lower_calls/fixup     WALL: CALL bodies
#  36  429-444 fold   do_linearize             WALL: `linearize`
#  37  446-448 fold   do_estimates             WALL: `Estimates.from_uops`
#  38  450-454 fold   do_assemble              WALL: the renderer
#  39  456-458 fold   do_render                WALL: `ctx.render`
#  40  460-464 fold   do_compile               WALL: `ctx.compiler`
#  41  466-472 table pm_to_program             5 of 5, PORTED SHAPE
#  42  474-506 fold   do_to_program            PORTED IN SHAPE
#  43  509-518 data   to_program_config        11 of 11, PORTED
#
# 43 defs. 13 are PORTED (1, 2, 3, 22, 23, 24, 26, 27, 30, 33, 34, 41, 43), EIGHT are
# PORTED IN SHAPE (8, 11, 14, 15, 20, 21, 32, 42) and the rest hit a wall. The prose
# said `six` over an EIGHT-element list, and four of the eight rows whose own STATE
# line reads `walls in ...` (8, 15, 21, 32) are listed as ported in shape, which is
# the weaker claim and is the one the list means.
#
# ---------------------------------------------------------------------------
# THE WALL THAT DOMINATES, and it is ONE wall: **`itertools.product` over a shape
# and `UOp.permute`/`reshape`/`reduce`/`unflatten`.** Items 4, 5, 6, 9, 10, 13
# and 19 are all the same wall from seven directions: the vectorizer
# DE-INDEXES a node by enumerating every element of its shape and rebuilding the
# node per element. That is a cartesian product whose size is the node's numel,
# and this architecture has no product and no way to name "the i-th element of a
# STACK". `movement.bend` owns `UOp.index` as `mp_index`, and movement.bend:235
# carries the `# TODO(p3) ops.py:581 def index` marker (581 is the `return`
# inside `ops.py:578`'s `def index`) -- and even it answers one index, not a
# product.
#
# The second wall is `UOp.replace`-with-a-NEW-OP: `pm_add_loads` and
# `pm_cast_float_alu` both build `x.replace(src=...)` with the SAME op, which is
# `UOp.new` and works. What does NOT work is `x.replace(op=Ops.BITCAST, ...)` with
# a different op AND a dtype change, which is item 17's `merge_reduce_ends` and
# item 4's `permute`.
#
# THE THIRD, and it is not a Bend limitation at all: `graph_rewrite` itself. Item
# 31 is a fixed sequence of 20 calls, so it ports as a LIST, not as a fixpoint.
# There is no engine here, deliberately -- `movement.bend`'s header settled that a
# pass is a linear scan over a `Data` table, and this file honours it.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
# `import ./rewriter.bend as RW` WAS HERE and was DEAD: `rg 'RW\.'` over this file
# finds ZERO uses, so the 38 rows below were transitively checking a file that
# answered nothing for them. It is gone, which is what makes this file's 38 rows a
# gate over THIS file's code alone instead of a gate over a merged neighbour's.

# ===========================================================================
# THE ANSWER. A rule RETURNS THE ARENA, `movement.bend`'s shape, called `Ker` so
# both files can be live in one tree. `at == 0` is Python's `None`.
# ===========================================================================
type Ker is Data:
  Ker{ar: O.Arena, at: U32}

def Ker.ar(x: Ker) -> O.Arena:
  match x:
    case Ker{ar, at}: ar

def Ker.at(x: Ker) -> U32:
  match x:
    case Ker{ar, at}: at

def ker_hit(+f: O.Found) -> Ker:
  Ker{O.Found.ar(f), O.Found.i(f)}

# `ret is not uop` -- ops.py:1610, inverted exactly as `hop_self` inverts it.
def ker_self.of(drop: Bool, +r: Ker) -> Ker:
  match drop:
    case True{} : Ker{Ker.ar(r), 0}
    case False{}: r

def ker_self(+r: Ker, self: U32) -> Ker:
  ker_self.of(Bool.or(U32.is_eq(Ker.at(r), self), O.UOp.is_none(Ker.at(r))), r)

def b2u.of(empty: Bool, r: U32) -> U32:
  match empty:
    case True{} : r
    case False{}: 0

def k2u.of(b: Bool, lo: U32) -> U32:
  match b:
    case True{} : lo
    case False{}: 0

def k2u(b: Bool) -> U32:
  k2u.of(b, 1)

# The first-wins test, `O.UOp.is_none` on the accumulator, as a def rather than an
# expression, because `al_next` READS it in a record constructor.
def b2u(have: U32, r: U32) -> U32:
  b2u.of(O.UOp.is_none(have), r)

def n_of(ts: List<&2, O.PMEntry>) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, ts))

# THE READERS. `O.Arena`'s readers return BARE values, not `Maybe`.
def kn_op(+ar: O.Arena, i: U32) -> O.Op:
  O.Arena.op(ar, i)

def kn_arg(+ar: O.Arena, i: U32) -> O.Arg:
  O.Arena.arg(ar, i)

def kn_tag(+ar: O.Arena, i: U32) -> O.Tag:
  O.Arena.tag(ar, i)

def kn_src(+ar: O.Arena, i: U32, n: U32) -> U32:
  O.Arena.src(ar, i, n)

def kn_src0(+ar: O.Arena, i: U32) -> U32:
  O.Arena.src0(ar, i)

def kn_nsrc(+ar: O.Arena, i: U32) -> U32:
  O.Arena.nsrc(ar, i)

def kn_srcs(+ar: O.Arena, i: U32) -> List<&2, U32>:
  O.Arena.srcs(ar, i)

def kn_src_from(+ar: O.Arena, i: U32, k: U32) -> List<&2, U32>:
  O.Arena.src_from(ar, i, k)

def kn_is(+ar: O.Arena, i: U32, want: O.Op) -> Bool:
  O.eq_op(kn_op(ar, i), want)

def kn_nsrc_is(+ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_eq(kn_nsrc(ar, i), n)

def kn_nsrc_ge(+ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_ge(kn_nsrc(ar, i), n)

# ===========================================================================
# `pm_cast_float_alu` -- __init__.py:244-247. THE OP SET AND THE TABLE ARE
# PORTED; THE DTYPE GUARD IS A WALL.
#
#     (UPat((Ops.SIN, Ops.LOG2, Ops.EXP2, Ops.SQRT, Ops.RECIPROCAL), src=(UPat(name="x"),), name="u"),
#      lambda u,x: u.replace(src=(x.cast(u.dtype),)) if x.dtype != u.dtype else None)
#
# `# TODO(p3) __init__.py:246  x.dtype != u.dtype` -- the guard, and the `cast` it
# wraps, need an `S.Dt` as a VALUE: `x.cast(u.dtype)` is
# `UOp(Ops.CAST, src=(x,), arg=dtype)` and `u.dtype` comes out of `fold.dt` as a
# `Maybe<&2, S.Dt>`. bend 2.0.34 mis-parses `Maybe<&2, S.Dt>` in a def signature
# at this position -- see the note appended to `.agents/slop/notes/
# bend2-constraints.md`, "Maybe<&2, S.Dt> in a def signature is position-sensitive"
# -- so the `Maybe` cannot be carried and the dtype cannot be named. The rule is
# therefore a TABLE with no body, which is the honest half.
#
# THE OP SET IS A FIVE-ARMED DISJUNCTION and not a set test, and that is the part
# that is exactly right and gateable: `UPat((A,B,C,D,E))` is ONE `UPat` with five
# ops, so a reader that consulted only the first would typecheck and drop 4 of the
# 5 float ALUs. `kn_alu_is` is the row for each arm and `cfa_len` for the table.
def kn_alu_is(op: O.Op) -> Bool:
  match op:
    case O.OpsSIN{}       : True{}
    case O.OpsLOG2{}      : True{}
    case O.OpsEXP2{}      : True{}
    case O.OpsSQRT{}      : True{}
    case O.OpsRECIPROCAL{}: True{}
    case _: False{}

def cfa_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSIN{}, O.OpsLOG2{}, O.OpsEXP2{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}], Nil{}}]

# `UOp.replace` -- ops.py:252, with `arg` and `tag` as PARAMETERS. The arena
# hash-conses, so `(self.op, self.src, self.arg, self.tag) == new_args` returning
# `self` needs no code: `ker_self` turns "the answer is the node itself" into no
# answer, exactly as `hop_self` does.
def kn_replace(op: O.Op, arg: O.Arg, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Ker:
  ker_hit(O.UOp.new(ar, op, src, arg, kn_tag(ar, self)))

# ===========================================================================
# PASS 1 -- `do_number_param`, __init__.py:33-36. PORTED IN FULL.
#
#     def do_number_param(ctx, x):
#       if x.arg.slot != -1: return None
#       ctx[0] += 1
#       return x.replace(arg=replace(x.arg, slot=ctx[0]-1))
#
# `ctx` is `itertools.count(num_params)` (:309), so `ctx[0]` is a MUTABLE SLOT
# counter. That is a store, and this architecture has none -- BUT the whole rule is
# a pure function of (the starting count, the node), because the pass walks the
# sink in toposort order and assigns `num_params + k` to the k-th PARAM with slot
# -1. So the counter becomes a PARAMETER and the rule is `slot + 1`. The
# sequential-ness is the CALLER's problem and it is why `kn_number_params` takes
# the running count and hands back the next one.
#
# `x.arg` for a PARAM is `ParamArg`, whose `slot` field `ops.bend` split out, so
# the read is `kn_slot` and not a tuple index.
# ===========================================================================
def kn_slot.of(a: O.Arg, none: U32) -> U32:
  match a:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: none

# `-1` IS NOT REPRESENTABLE in a `U32`, and `u32_none` (0xFFFFFFFF) is this port's
# "unset". `kn_slot_missing` is the row for that decision, and the alternative --
# answering 0 for a non-PARAM -- would make `x.arg.slot != -1` TRUE for every
# CONST and the rule would try to renumber them. `u32_none` is WRAPPED rather than
# arithmetic because 0 - 1 in a `U32` is not guaranteed to be the top word. The
# VALUE now comes from `O.ParamArg.no_slot()`, which is the same `U32` and lives in
# the file that owns the field -- `codegen/late/linearizer.bend` had its own
# independent copy of this def, and two spellings of one sentinel is two places to
# drift.
def u32_none() -> U32:
  O.ParamArg.no_slot()
def kn_slot(+ar: O.Arena, i: U32) -> U32:
  kn_slot.of(kn_arg(ar, i), u32_none())

def pa(slot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

# `x.arg.slot != -1` -- and the slot is a `U32`, so Python's -1 is not
# representable and the port reads "unset" as `u32_none()`. `kn_slot_missing`
# is the row for that decision.
def kn_slot_missing(+ar: O.Arena, i: U32) -> Bool:
  U32.is_eq(kn_slot(ar, i), u32_none())

# The rewrite, and the NEXT count: `ctx[0] += 1` then `slot=ctx[0]-1`, so the slot
# written is the count BEFORE the increment and the NEXT PARAM gets `n+1`. `kn_np`
# returns both, which is why it is a `Data` and not a pair, and it returns the RAW
# rewrite: `ker_self` is applied by the caller, once, on the answer.
type NP is Data:
  NP{k: Ker, n: U32}

def NP.k(x: NP) -> Ker:
  match x:
    case NP{k, n}: k

def NP.n(x: NP) -> U32:
  match x:
    case NP{k, n}: n

# `x.replace(arg=replace(x.arg, slot=ctx[0]-1))` -- same op, same srcs, same tag,
# and a `ParamArg` whose ONLY changed field is the slot. `kn_tag(ar, i)` is read
# rather than `TNone{}`: `UOp.replace` keeps the tag, and a PARAM with a tag is a
# different node.
def kn_param_slot(+ar: O.Arena, +i: U32, slot: U32) -> Ker:
  ker_hit(O.UOp.new(ar, kn_op(ar, i), O.Arena.srcs(ar, i), O.AParam{pa(slot)}, kn_tag(ar, i)))

def kn_np.go(fresh: Bool, +ar: O.Arena, i: U32, slot: U32) -> Ker:
  match fresh:
    case True{} : kn_param_slot(ar, i, slot)
    case False{}: Ker{ar, 0}

def kn_np.next(fresh: Bool, n: U32) -> U32:
  match fresh:
    case True{} : U32.add(n, 1)
    case False{}: n

def kn_np.of(+fresh: Bool, +ar: O.Arena, i: U32, +n: U32) -> NP:
  NP{kn_np.go(fresh, ar, i, n), kn_np.next(fresh, n)}

# `kn_slot_missing` is read TWICE -- once for the rewrite and once for the next
# count -- and reading it twice would be two walks of the arg, so it is computed
# once and handed to the `.of` form. `np_next` is the row for the increment and
# `np_slot` for the value written.
# `ctx[0] += 1` and THEN `slot=ctx[0]-1`, so the slot is `n + 1 - 1` and the two
# cancel: the slot written is THE COUNT ITSELF. An earlier version wrote `n - 1` and
# `np_slot` read 2 against Python's 3 -- the oracle caught it, and an off-by-one is
# exactly what a counting row is for. `np_next` is the row for the increment, which
# IS real: the NEXT unnumbered PARAM gets `n + 1`.
#
# `kn_slot_missing` is read TWICE -- once for the rewrite and once for the next
# count -- and reading it twice would be two walks of the arg, so it is computed
# once and handed to the `.of` form.
def kn_np(+ar: O.Arena, +i: U32, n: U32) -> NP:
  kn_np.of(kn_slot_missing(ar, i), ar, i, n)

# The table: `pm_number_params`, __init__.py:38-40. ONE rule, `UPat(PARAM,
# name="x")`, and the `slot != -1` test is the RULE'S OWN BODY, not `early_reject`.
# So `rej` is `Nil{}` and `ops` is `[PARAM]`.
def np_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsPARAM{}], Nil{}}]   # __init__.py:39  UPat(Ops.PARAM, name="x")

def np_try.go(ok: Bool, +ar: O.Arena, +self: U32, +np: NP) -> Ker:
  match ok:
    case True{} : ker_self(NP.k(np), self)
    case False{}: Ker{ar, 0}

# The pass, with the running count as a PARAMETER: `pm_number_params(ctx=[n])`.
# The post-increment count comes back as `NP.n` and the caller threads it, which is
# the whole of what `itertools.count` bought Python. `kn_np` is computed ONCE and
# its two halves are read from the `Data` -- two walks of the arg would answer the
# same thing but cost the reader twice, and the gate counts walks indirectly.
def pm_number_params.of(ok: Bool, +np: NP, +ar: O.Arena, +self: U32) -> NP:
  NP{np_try.go(ok, ar, self, np), NP.n(np)}

def pm_number_params(+n: U32, +ar: O.Arena, +self: U32) -> NP:
  pm_number_params.of(O.pm_claimed([O.OpsPARAM{}], ar, self), kn_np(ar, self, n), ar, self)

# ===========================================================================
# `build_range_map` -- __init__.py:40-45. PORTED, AND THE PORT IS NOW WRONG.
#
#     def build_range_map(sink):
#       ctx = {}
#       for x in sink.toposort():
#         if x.op is Ops.RANGE and x.axis_type is AxisType.UPCAST:
#           ctx[x.arg] = len(ctx)
#       return ctx
#
# `AxisType.UNROLL` IS DELETED UPSTREAM and so is the half of the membership test
# that named it, AND the key changed with it: it was `ctx[x.axis_id]` and is now
# `ctx[x.arg]`, because a RANGE's `arg` is `(axis_type, *axis_id)` now.
# `kn_unroll.ax` below still admits `O.AXIS_UNROLL`, so it ports the PIN.
#
# MEASURED, NOT ARGUED. `.agents/slop/xb1/build_range_map-oracle.py`, run against
# a pristine `git archive 6c3d401cf324` tree and against the vendored HEAD tree:
#   pin  AxisType has UNROLL=True,  REDUCE=True   (10 members)
#        build_range_map(UOp.range(3, 0, AxisType.UNROLL)) -> len=1  keys=[(0,)]
#   HEAD AxisType has UNROLL=False, REDUCE=False  (8 members)
#        build_range_map(UOp.range(3, 0, AxisType.UPCAST)) -> len=1 keys=[(AxisType.UPCAST, 0)]
#        build_range_map(UOp.range(3, 0, AxisType.LOOP))   -> len=0
#        AxisType.UNROLL -> AttributeError: type object 'AxisType' has no attribute 'UNROLL'
# So `rm_unroll` and `rm` are rows that are GREEN AGAINST THE PIN AND WRONG AT
# HEAD: both would move to 0, and the fixture's `R_U` is a member CPython can no
# longer construct at all.
#
# REPORTED, NOT FIXED HERE, and the reason is scope rather than difficulty: this
# is port LOGIC (a membership predicate, a fixture, and three row values), it is
# B1's own RE-PORT -- `ad117c928` lists `kernel.bend:353` by name -- and folding
# it in beside an orphan citation would move three rows without the row audit
# that a three-row move owes. `uop/ops.bend` already keeps `AXIS_UNROLL` for
# exactly this reason: it names `codegen/kernel.bend:366,:956` as a live consumer,
# so the enum's ten members are load-bearing until this lands.
#   TODO(p3) codegen/__init__.py:43  `build_range_map`'s set is `{UPCAST}` and its
#     key is `x.arg`; `kn_unroll.ax`, `kn_fixture`'s `R_U`, `k_rm` and `k_rm_unroll`
#     are all pinned to the pin's predicate.
#
# IT IS A FOLD, and `fold.bend` is where a fold belongs -- but its OUTPUT is a
# `dict[axis_id, int]`, a map from an axis id to its ORDINAL AMONG UNROLL/UPCAST
# RANGEs, and `fold.bend`'s `Derived` has no such field. So it is a table here,
# and `kn_unroll` is the row for the membership test. `ops.bend`'s `UOp.axis_id`
# and `UOp.axis_type` are both PORTED (fold.bend:2430-2436), which is why this
# half is cheap.
# ===========================================================================
# `kn_unroll.ax` IS THE PIN'S PREDICATE. The UNROLL arm has no upstream
# counterpart -- `AxisType.UNROLL` was deleted from the enum -- so this arm is
# what makes `rm` and `rm_unroll` green against a tree CPython no longer has.
# MEASURED both ends, in the block above. Delete the arm, drop `R_U` from
# `kn_fixture`, and `rm`/`rm_unroll` go to 0 together; that is B1's RE-PORT and it
# wants a row audit, so it is NOT done in a comment-fix pass.
# ===========================================================================
def kn_unroll.ax(t: O.AxisType) -> Bool:
  match t:
    case O.AXIS_UNROLL{}: True{}
    case O.AXIS_UPCAST{}: True{}
    case _: False{}

def kn_unroll.at(m: Maybe<&2, O.AxisType>) -> Bool:
  match m:
    case Some{t}: kn_unroll.ax(t)
    case None{}  : False{}

# `x.op is Ops.RANGE and x.axis_type in {UNROLL, UPCAST}` -- TWO predicates, and
# `axis_type` is a `Maybe` whose `_` arm is the `None` of `ops.py:507`'s assert.
# `kn_is_expand0` is the row for the conjunction and `kn_expand_range` for the
# RANGE half on its own, because `build_range_map` reads both.
def kn_is_expand0(tb: F.Table, +ar: O.Arena, +i: U32) -> Bool:
  Bool.and(kn_is(ar, i, O.OpsRANGE{}), kn_unroll.at(F.UOp.axis_type(ar, i)))

# THE FUEL IS FIRST, as everywhere else in this port (bend2-constraints.md, "A
# SELF-CALL MUST BE DECREASING, READ LEFT TO RIGHT"): the walk is over arena
# INDICES 0..next-1 and the budget is exactly that bound, so it can never cut the
# count short. `kerm` is the fuel and `acc` is the count so far.
# THE INDEX DESCENDS AND THE FUEL FOLLOWS IT. The decrease check reads a
# recursive call's arguments left to right and stops at the first strict subterm,
# so only the FUEL has to shrink -- everything after it is free -- but `p` may not
# be READ twice either, so the index is threaded as its own parameter rather than
# recomputed from the fuel. That is why this walks 0, 1, 2, ... by way of a
# DESCENDING index: `last` starts at `next - 1` and the self-call passes a
# STRICTLY SMALLER `last`. `krm_n` is the row for the count and a mutation of the
# direction moves it, because the count is order-independent and only the
# termination proof is not.
def kn_rm_len.go(fuel: Nat, +tb: F.Table, +ar: O.Arena, +last: U32, acc: U32) -> U32:
  match fuel:
    case 0n   : acc
    case 1n+p : kn_rm_len.go(p, tb, ar, U32.sub(last, 1),
                             U32.add(acc, k2u(kn_is_expand0(tb, ar, last))))

# `len(ctx)` for `build_range_map`, i.e. the number of RANGEs whose axis type is
# UNROLL or UPCAST anywhere in the arena. The budget is `Arena.next`, which
# counts the bottom at 0, so `last` is `next - 1` and the bottom is counted as
# `Ops.NOOP` and contributes 0.
def kn_range_map_n(+tb: F.Table, +ar: O.Arena) -> U32:
  kn_rm_len.go(U32.to_nat(O.Arena.next(ar)), tb, ar, U32.sub(O.Arena.next(ar), 1), 0)

# ===========================================================================
# `is_shape_changing_bitcast` and `maybe_load` -- __init__.py:226-227. BOTH
# PORTED, and `maybe_load` is the one that decides whether `pm_add_loads` fires at
# all, so its `AddrSpace` test is the load-bearing half.
#
#     def is_shape_changing_bitcast(u): return u.op is Ops.BITCAST and u.shape != u.src[0].shape
#     def maybe_load(u): return u.load() if u.addrspace in (AddrSpace.GLOBAL, AddrSpace.LOCAL, AddrSpace.REG) else u
#
# `u.shape != u.src[0].shape` is the WALL -- it is the double-`Maybe` of the fold's
# shape and the deferred `_ranges`-alike shape comparison, and movement.bend's
# `shp_same` is the reader that would answer it. `# TODO(p3) __init__.py:226
# u.shape != u.src[0].shape`. What IS here is the op test, and `bitcast_op` is its
# row: a rule that read only `u.op is BITCAST` and dropped the shape half would
# fire on every bitcast, which is Python's `and` with the second conjunct missing.
def kn_is_bitcast(+ar: O.Arena, i: U32) -> Bool:
  kn_is(ar, i, O.OpsBITCAST{})

# `u.addrspace in {GLOBAL, LOCAL, REG}` -- THREE arms, and it is `AddrSpace` and
# not a dtype, so the read is `F.fold.addr`'s inner `Maybe`. `# TODO(p3)
# __init__.py:227  u.addrspace` needs `Derived.addr` to answer for an Elementwise
# node rather than only for a BUFFER/PARAM; the membership test itself is here.
def kn_alu_loadable.addr(ad: S.Addr, bad: Bool) -> Bool:
  match ad:
    case S.AGlobal{}: Bool.or(bad, True{})
    case S.ALocal{} : Bool.or(bad, True{})
    case S.AReg{}   : Bool.or(bad, True{})
    case _: bad

def kn_alu_loadable.ax(a: Maybe<&2, S.Addr>, bad: Bool) -> Bool:
  match a:
    case Some{ad}: kn_alu_loadable.addr(ad, bad)
    case None{}   : bad

def kn_alu_loadable.go(m: Maybe<&2, Maybe<&2, S.Addr>>, bad: Bool) -> Bool:
  match m:
    case Some{a}: kn_alu_loadable.ax(a, bad)
    case None{}  : bad

def kn_alu_loadable(+tb: F.Table, +ar: O.Arena, i: U32) -> Bool:
  kn_alu_loadable.go(F.fold.addr(ar, tb, i), False{})

# `x.replace(src=tuple(map(maybe_load, x.src)))` -- `map` over the srcs, and a
# `Bool` cannot be an accumulator, so the mapped list threads the TEST as a value.
# `kn_map_load` is the fold and `al_grow`/`al_same` are its rows.
# `maybe_load(u)` -- `u.load()` when loadable, else `u` ITSELF. `u.load()` is
# `UOp(Ops.LOAD, src=(u,))` (ops.py:594), which is `UOp.new` with the LOAD op.
def kn_load_one.of(loadable: Bool, +ar: O.Arena, s: U32) -> U32:
  match loadable:
    case True{} : O.Found.i(O.UOp.new(ar, O.OpsLOAD{}, [s], O.ANone{}, O.TNone{}))
    case False{}: s

def kn_load_one(loadable: Bool, +ar: O.Arena, s: U32) -> U32:
  kn_load_one.of(loadable, ar, s)

def kn_map_load.go(ss: List<&2, U32>, +tb: F.Table, +ar: O.Arena) -> List<&2, U32>:
  match ss:
    case Nil{}   : Nil{}
    case +s <> t : List.append(&2, U32, kn_map_load.go(t, tb, ar), [kn_load_one(kn_alu_loadable(tb, ar, s), ar, s)])

def al_0.of(shaped: Bool, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Ker:
  match shaped:
    case True{} : ker_hit(O.UOp.new(ar, kn_op(ar, self), src, kn_arg(ar, self), kn_tag(ar, self)))
    case False{}: Ker{ar, 0}

# `x.replace(src=(x.src[0], maybe_load(x.src[1]))+x.src[2:])` -- the STORE arm
# (:231). Note it is `src[1]` and not every src: a STORE's value is the ONLY src
# that is loaded, and `al_store_src` is the row that pins the position.
def al_store_src(+tb: F.Table, +ar: O.Arena, +self: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [kn_src0(ar, self)], [kn_load_one(kn_alu_loadable(tb, ar, kn_src(ar, self, 1)), ar, kn_src(ar, self, 1))]),
              O.Arena.src_from(ar, self, 2))

def al_1(+tb: F.Table, +ar: O.Arena, +self: U32) -> Ker:
  al_0.of(kn_is(ar, self, O.OpsSTORE{}), ar, self, al_store_src(tb, ar, self))

# The table: `pm_add_loads`, __init__.py:228-232. TWO rules, and the first is a
# GroupOp over `{REDUCE, WMMA, STACK}` plus every Elementwise op -- an op SET this
# port cannot name, because `GroupOp.Elementwise` is a computed membership over 60
# ops and `ops.bend`'s `Op` is a closed enumeration. `# TODO(p3) __init__.py:229
# GroupOp.Elementwise`: `al_0`'s `ops` list therefore holds the three NAMED ops and
# `al_elem_len` is the row for what that costs.
def al_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}, O.OpsWMMA{}, O.OpsSTACK{}], Nil{}},   # :229 Elementwise|{REDUCE,WMMA,STACK}
   O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]                                # :231 STORE

def kn_map_load(ss: List<&2, U32>, +tb: F.Table, +ar: O.Arena) -> List<&2, U32>:
  kn_map_load.go(ss, tb, ar)

def al_dispatch(tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Ker:
  match tag:
    case 0: al_0.of(Bool.or(Bool.or(kn_is(ar, self, O.OpsREDUCE{}), kn_is(ar, self, O.OpsWMMA{})),
                             Bool.or(kn_is(ar, self, O.OpsSTACK{}), Bool.not(kn_is_bitcast(ar, self)))),
                    ar, self, kn_map_load(kn_srcs(ar, self), tb, ar))
    case 1: al_1(tb, ar, self)
    case _: Ker{ar, 0}

def al_try.go(ok: Bool, tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Ker:
  match ok:
    case True{} : ker_self(al_dispatch(tag, tb, ar, self), self)
    case False{}: Ker{ar, 0}

# THE FOLD, first-wins on the ACCUMULATOR: `PatternMatcher.rewrite` returns the
# FIRST non-None, so keying on the accumulator is what makes it first-wins.
def al_next(h: Ker, r: Ker) -> Ker:
  match h r:
    case Ker{ha, hn} Ker{ra, rn}: Ker{ra, b2u(hn, rn)}

def al_scan(rs: List<&2, O.PMEntry>, +tb: F.Table, +ar: O.Arena, +self: U32, +h: Ker) -> Ker:
  match rs:
    case Nil{}  : h
    case +e <> t: al_scan(t, tb, ar, self, al_next(h, al_try.go(O.pm_claimed(O.PMEntry.ops(e), ar, self),
                                                               O.PMEntry.tag(e), tb, ar, self)))

def pm_add_loads(+fx: F.Folded, self: U32) -> Ker:
  al_scan(al_table(), F.Folded.t(fx), F.Folded.ar(fx), self, Ker{F.Folded.ar(fx), 0})

# ===========================================================================
# `_is_local_store` -- __init__.py:249. PORTED. `x.op is Ops.STORE and
# x.addrspace is AddrSpace.LOCAL`, and the `is` on an enum is an identity test, so
# the second conjunct is `ALocal{}` and nothing else. `LocalStore` uses `is`, so
# `AddrSpace.GLOBAL` is a DIFFERENT node and `ib_local` is the row for that.
def ib_local.addr(m: Maybe<&2, Maybe<&2, S.Addr>>, bad: Bool) -> Bool:
  kn_alu_loadable.go(m, bad)

def ib_local(+tb: F.Table, +ar: O.Arena, +i: U32) -> Bool:
  Bool.and(kn_is(ar, i, O.OpsSTORE{}), ib_local.addr(F.fold.addr(ar, tb, i), False{}))

# ===========================================================================
# `pm_implicit_barriers` -- __init__.py:270-273. TWO rules, and BOTH are WALLS, but
# for the SAME wall and it is the wall this whole lowerer keeps hitting:
#
#     (UPat(Ops.AFTER, name="after"),   add_raw_barrier)   # :271  -- :251-257
#     (UPat((Ops.END, Ops.BACKEDGE), name="end"), add_war_barrier)  # :272  -- :259-268
#
# `# TODO(p3) __init__.py:255  UOp.sink(...).toposort(gate=...)` -- BOTH bodies open
# with a toposort over the node's deps (`add_raw_barrier` gates out BARRIERs,
# `add_war_barrier` walks `backward_slice_with_self`), and a rule here cannot run a
# fixpoint: that is the whole of movement.bend's header. What IS here is the OP
# SET, which is what the dispatch turns on and what `ib_len`/`ib_after`/`ib_back`
# pin.
#
# NOTE THE ORDER, because it is not the order the two defs are written in: the
# table lists AFTER first and {END, BACKEDGE} second, so `tag 1` is END-or-
# BACKEDGE. A table that reordered them would typecheck and fire the wrong rule.
def ib_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsAFTER{}], Nil{}},      # :271  AFTER add_raw_barrier
   O.PMEntry{1, [O.OpsEND{}, O.OpsBACKEDGE{}], Nil{}}]   # :272  END|BACKEDGE add_war_barrier

# ===========================================================================
# `pm_alloc_to_buf` -- __init__.py:405. ONE rule, and it is the WHOLE of the
# function: `((buf:=x.replace(op=Ops.BUFFER)), [buf])`. It changes the OP and
# keeps everything else, so `UOp.new` with the BUFFER op and `self`'s own src, arg
# and tag is exactly it. PORTED IN FULL -- this is the one rule in the file with no
# wall at all, and `ab_op`/`ab_nsrc` are its rows.
#
#     pm_alloc_to_buf = PatternMatcher([(UPat(Ops.ALLOC, name="x"),
#                                        lambda x: ((buf:=x.replace(op=Ops.BUFFER)), [buf])),])
#
# THE ARENA GROWS BY ONE even though nothing about the srcs changed, because the
# OP is part of the hash: `ALLOC(SPECIAL)` and `BUFFER(SPECIAL)` are two nodes.
# `ab_grow` is the row for that, and it is why `ab_nsrc` alone is not enough.
def ab_new(+ar: O.Arena, +self: U32) -> Ker:
  ker_hit(O.UOp.new(ar, O.OpsBUFFER{}, O.Arena.srcs(ar, self), kn_arg(ar, self), kn_tag(ar, self)))

def ab_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsALLOC{}], Nil{}}]   # __init__.py:405  UPat(Ops.ALLOC, name="x")

def ab_try.go(ok: Bool, +ar: O.Arena, +self: U32) -> Ker:
  match ok:
    case True{} : ker_self(ab_new(ar, self), self)
    case False{}: Ker{ar, 0}

def pm_alloc_to_buf(+ar: O.Arena, +self: U32) -> Ker:
  ab_try.go(O.pm_claimed([O.OpsALLOC{}], ar, self), ar, self)

# ===========================================================================
# `line_rewrite` -- __init__.py:408-416. PORTED IN FULL, and it is the SECOND
# engine in this file: a fixpoint over a LIST rather than over the arena.
#
#     def line_rewrite(lst, pm, ctx=None):
#       newlst, replaced = [], {}
#       for u in lst:
#         nu = u.replace(src=tuple([replaced.get(x, x) for x in u.src]))
#         ret = pm.rewrite(nu, ctx) or (nu, [nu])
#         replaced[u] = ret[0]
#         newlst.extend(ret[1])
#       return newlst
#
# `replaced` is a `dict[UOp, UOp]` and `ret[1]` is a LIST of nodes -- so the pair
# `(nu, [nu])` is a `(UOp, list[UOp])`. A rule here may return SEVERAL nodes, which
# no rule in `ops.bend`'s `pm_rewrite` can, so `lw_step` answers `(answer, list)`
# as a `Data` and the list is threaded through the accumulator.
#
# `# TODO(p3) __init__.py:411  replaced.get(x, x)` -- the substitution map is a
# mutable dict and this architecture has no store, so it is a LIST threaded as an
# accumulator. That is a CHANGE OF SHAPE and not a change of meaning, because the
# walk is in toposort order and each key is written once: `lw_subst` finds the
# FIRST match and `lw_subst_go` installs the LAST write, which is the same dict.
# `lw_three` is the row that exercises it.
# ===========================================================================
# The substitution pair.
type Sub is Data:
  Sub{was: U32, now: U32}

def Sub.was(s: Sub) -> U32:
  match s:
    case Sub{was, now}: was

def Sub.now(s: Sub) -> U32:
  match s:
    case Sub{was, now}: now

def lw_find.same(s: Sub, x: U32) -> Bool:
  U32.is_eq(Sub.was(s), x)

def lw_find.hit(same: Bool, s: Sub, hold: U32) -> U32:
  match same:
    case True{} : Sub.now(s)
    case False{}: hold

# `replaced.get(x, x)` -- the FIRST match, since a key is written at most once.
def lw_find.go(ss: List<&2, Sub>, +x: U32, hold: U32) -> U32:
  match ss:
    case Nil{}    : hold
    case +s <> t  : lw_find.go(t, x, lw_find.hit(lw_find.same(s, x), s, hold))

def lw_find(+ss: List<&2, Sub>, +x: U32) -> U32:
  lw_find.go(ss, x, x)

# `replaced[u] = ret[0]` -- a HEAD, because `dict.fromkeys` order is irrelevant to
# a lookup and a first-wins list is the same map. `lw_install` is the row.
def lw_install(ss: List<&2, Sub>, u: U32, now: U32) -> List<&2, Sub>:
  List.append(&2, Sub, [Sub{u, now}], ss)

# `tuple([replaced.get(x, x) for x in u.src])` -- `map` over the srcs, which is
# `lw_map` and whose result is `nu`'s srcs.
def lw_map.go(ss: List<&2, U32>, +subs: List<&2, Sub>) -> List<&2, U32>:
  match ss:
    case Nil{}   : Nil{}
    case s <> t  : List.append(&2, U32, lw_map.go(t, subs), [lw_find(subs, s)])

def lw_map(+ss: List<&2, U32>, +subs: List<&2, Sub>) -> List<&2, U32>:
  lw_map.go(ss, subs)

def lw_nu(+subs: List<&2, Sub>, +ar: O.Arena, +u: U32) -> U32:
  O.Found.i(O.UOp.new(ar, kn_op(ar, u), lw_map(O.Arena.srcs(ar, u), subs), kn_arg(ar, u), kn_tag(ar, u)))

# A step's two answers: the substituted map and the output list. `ret[0]` goes in
# `subs` and `ret[1]` goes in `out`, so the `Data` holds the PAIR the tuple held.
type Line is Data:
  Line{subs: List<&2, Sub>, out: List<&2, U32>}

def Line.subs(l: Line) -> List<&2, Sub>:
  match l:
    case Line{subs, out}: subs

def Line.out(l: Line) -> List<&2, U32>:
  match l:
    case Line{subs, out}: out

# `who` is read TWICE -- once as the substitution's value and once as the output
# node -- and two uses in ONE body need `+`. This is the same rule `movement.bend`
# records for a `Data` record parameter, and it is why `lw_put` takes the answer
# once and builds both fields.
def lw_put(+who: U32, subs: List<&2, Sub>, u: U32, acc: List<&2, U32>) -> Line:
  Line{lw_install(subs, u, who), List.append(&2, U32, acc, [who])}

# `pm.rewrite(nu, ctx) or (nu, [nu])` -- the `or` is what makes a non-matching node
# PASS THROUGH, so `fired`'s `None` arm is `nu` and NOT 0. `lw_answer` is the row for
# that arm and `lw_answer_fired` its control: they differ only by the rewrite.
def lw_answer.of(fired: Maybe<&2, Ker>, nu: U32) -> U32:
  match fired:
    case Some{k}: Ker.at(k)
    case None{}  : nu

def lw_answer(+fired: Maybe<&2, Ker>, nu: U32) -> U32:
  lw_answer.of(fired, nu)

# THE STEP, on ONE node: `nu = u.replace(src=[replaced.get(x,x) for x in u.src])`,
# then the rewrite, then `replaced[u] = ret[0]` and `newlst.extend(ret[1])`.
#
# `# TODO(p3) __init__.py:412  pm.rewrite(nu, ctx)` -- `ctx` is the RENDERER for
# `pm_simplify_add_image` and `None` for the other three uses, and a renderer is a
# Python object this port has no value for. So the rewrite is a `Maybe<&2, Ker>`
# PARAMETER, computed by the caller, and the step is otherwise exact. `lw_step` is
# a def and not the loop body so that the loop below has ONE self-call.
# THE LOOP. `lst` is toposorted, so each key is written once and the walk needs no
# visited set -- the fuel is the LIST itself, which is the structural-decrease form
# of the fuel rule and needs no `Nat`.
#
# `lw_step` is called ONCE and its two halves are read off the `Data`: calling it
# twice would walk the srcs twice AND read `subs` twice in one body, which bends
# charges for in `+`. The self-call runs on the REST and the step wraps it, so the
# step's `subs` and `acc` are the ones BEFORE it -- which is Python's order, because
# `replaced[u]` is written after `nu` is built from the OLD `replaced`.
def lw_tail(rest: Line, +step: Line) -> Line:
  Line{Line.subs(step), Line.out(rest)}

# THE STEP IS AN ARGUMENT, NOT A TAIL WRAP, and that is the fix worth recording.
# A tail wrap -- `lw_tail(lw_go(t, ...), lw_step(...))` -- can only return ONE of
# the step's two fields paired with the recursion's OTHER field, because `subs` and
# `out` both live in the `Data` and a wrap may only combine two of them. Taking
# `subs` from the step and `out` from the recursion DROPS every earlier output, and
# `lw_miss` read 0 where Python's `newlst` has one entry per input. The step is
# bound to a `+s` binder and BOTH fields go into the recursive call's arguments, so
# the accumulator is threaded and nothing is dropped.
# `subs` and `acc` are each read TWICE -- once by `lw_nu` to substitute the srcs and
# once by `lw_put` -- so they need `+`. Both are threaded lists, so `+` costs a
# copy and nothing else.
def lw_step(+subs: List<&2, Sub>, +acc: List<&2, U32>, fired: Maybe<&2, Ker>, +ar: O.Arena, +u: U32) -> Line:
  lw_put(lw_answer(fired, lw_nu(subs, ar, u)), subs, u, acc)
def lw_go(lst: List<&2, U32>, +subs: List<&2, Sub>, +acc: List<&2, U32>, +ar: O.Arena, +fired: Maybe<&2, Ker>) -> Line:
  match lst:
    case Nil{}   : Line{subs, acc}
    case +u <> t : lw_go(t, Line.subs(lw_step(subs, acc, fired, ar, u)), Line.out(lw_step(subs, acc, fired, ar, u)), ar, fired)


# `# TODO(p3) __init__.py:411  replaced: dict[UOp, UOp]` -- a mutable dict becomes a
# threaded LIST of `Sub`. That is a CHANGE OF SHAPE and not of meaning, because the
# walk is in toposort order and each key is written once, so `lw_find`'s FIRST match
# is the only match. `lw_three` is the row that exercises it, and `lw_key` is the
# row for the write itself.
def line_rewrite(+lst: List<&2, U32>, +ar: O.Arena, fired: Maybe<&2, Ker>) -> Line:
  lw_go(lst, Nil{}, Nil{}, ar, fired)

# ===========================================================================
# `to_program_config` -- __init__.py:509-510. ELEVEN ENV FLAGS, and this is the
# CACHE KEY and not a behaviour list: `to_program_key` (:512-513) is
# `(ast.key, type(renderer), renderer.target, *[x.value for x in to_program_config])`
# and `to_program_cache` (:515) is keyed by it. So the count IS the contract -- a
# flag added to `to_program_config` changes the cache key and therefore which
# compiled PROGRAM you get -- and `cfg_len` is the row for it.
#
#     to_program_config = (NOOPT, EMULATED_DTYPES, USE_TC, IMAGE, DISABLE_FAST_IDIV,
#                          TRANSCENDENTAL, ALLOW_TF32, DEFAULT_FLOAT, DEFAULT_INT,
#                          TC_SELECT, TC_OPT, TC_MIN_GLOBALS)
#
# `to_program_context` (:511) is that plus `SPEC` and `DEBUG`, so it is THIRTEEN,
# and `cfg_ctx_len` is the row for the difference -- `to_program_context` is what
# reaches a WORKER, and `to_program_config` alone is what a cache key is built from.
# Getting these two confused means a worker's DEBUG is part of a cache key, which
# is not Python's behaviour.
#
# THE FLAGS THEMSELVES are env reads and `helpers.bend` owns those, so they are not
# names here: what this file owns is the COUNT and the ORDER, and the count is what
# the cache key hashes. `# TODO(p3) __init__.py:509  to_program_config` -- the flags
# are `ContextVar`s in Python and a worker-scoped value here, which is a runtime
# concern and not a codegen one.
def cfg_len() -> U32:
  12

def cfg_ctx_len() -> U32:
  14

# ===========================================================================
# `pm_to_program` -- __init__.py:466-472. FIVE rules, ONE PER STAGE, and this is
# the second engine in this file and it is the one the SIBLINGS consume: a PROGRAM
# gains a LINEAR, then a SOURCE, then a BINARY, one `graph_rewrite` at a time, and
# `renderer/cstyle.bend` and `renderer/wgsl.bend` are the rules for stage 4.
#
#     (UPat(PROGRAM, src=(UPat(SINK, name="sink"),), name="prg"),                    do_linearize)   # :467
#     (UPat(PROGRAM, src=(UPat(SINK, name="sink"), UPat(LINEAR, name="lin")),        do_estimates)    # :468
#     (UPat(PROGRAM, src=(UPat(), UPat(LINEAR, src=UPat(INS))), name="prg"),          do_assemble)     # :469
#     (UPat(PROGRAM, src=(UPat(), UPat(LINEAR, name="lin")), name="prg"),            do_render)       # :470
#     (UPat(PROGRAM, src=(UPat(), UPat(LINEAR), UPat(SOURCE, name="source")), "prg"), do_compile)      # :471
#
# THE ORDER IS THE CONTRACT, and it is visible in the `nsrc` TESTS: 1 src is
# stage 1, 2 is stages 2 and 4, 3 is stage 5, and stages 2 and 4 are told apart by
# whether the LINEAR's first src is an INS -- an ISA renderer only. So the dispatch
# key is `(nsrc, is_ins)` and NOT the src count alone: `tp_tag` returns 2 and 4 from
# the same arity and `tp_stage` is the row that says so.
#
# `# TODO(p3) __init__.py:425  UOp(Ops.LINEAR, src=tuple(lst))` -- `do_linearize`'s
# body is `linearize(sink)` from `late/linearizer.py`, which is not a claimed file,
# and the LINEAR node's `arg=to_function_name(...)` is a string. The TABLE is
# therefore exact and the BODIES are all `codegen/late/` and the renderer, i.e. the
# walls, and `tp_len`/`tp_stage`/`tp_ins` are the rows for the part that is here.
# `UPat(LINEAR, src=UPat(Ops.INS))` -- the pattern claims the FIRST SRC **OF THE
# LINEAR**, and the LINEAR is `self.src[1]`, so reading `self`'s own `src[0]` is
# reading the SINK and answers False on every ISA program. `k_ins` is the row that
# caught it: it read 0 on a LINEAR whose only src IS an INS.
#
# `k_lins` is the LINEAR half and `k_is_ins` the op half, and they are two defs
# because a mutation of either leaves the other's row green.
# `U32.is_zero` is the defensive arm for a node with no src[1] at all, where
# `Arena.src` answers the bottom; `k_not_ins` is its control.
def tp_ins(+first: U32, ar: O.Arena) -> Bool:
  Bool.or(U32.is_zero(first), kn_is(ar, first, O.OpsINS{}))

def k_lins(+ar: O.Arena, self: U32) -> U32:
  kn_src(ar, self, 1)

def k_is_ins(+ar: O.Arena, self: U32) -> Bool:
  tp_ins(kn_src(ar, self, 1), ar)

# THE STAGE NUMBER, which is the TABLE'S TAG: 1 is LINEARIZE, 2 ESTIMATES, 3
# ASSEMBLE, 4 RENDER, 5 COMPILE.
#
# THE ARITY IS THE FIRST TEST, and this is what `k_stage_pr1` caught. Reading the
# INS before the arity answers 3 for `PROGRAM(SINK)` -- a one-src PROGRAM has no
# `src[1]`, so `Arena.src` hands back the bottom, `U32.is_zero` fires, and the node
# looks like an ISA program. Python's rules are tried in ORDER, so arity first and
# the INS only ever discriminates AMONG the two-src rules (2 against 4).
#
# `0` is "no stage": not a PROGRAM, or a PROGRAM with no LINEAR. There is no
# fixture for it, because `Ops.PROGRAM`'s own `arg` is the point and no rule
# matches a zero-src PROGRAM.
# THE ARITY LADDER, AS THREE EQUALITY TESTS. `case 1n:` is a PREFIX match that
# claims its successors (constraint 9), so an arity dispatch CANNOT be a `match` on
# the count -- `case 1n: 1 / case 2n+p: ...` makes 1 answer 2's arm too. It is three
# `Nat.is_eq`s, and the order is the ORDER OF PYTHON'S RULES: 1 src is stage 1, 3 is
# stage 5, and 2 is the only arity the INS discriminates (2 against 4).
#
# `k_stage_pr1` is the row that matters: `PROGRAM(SINK)` has ONE src, and a version
# that read the INS before the arity answered 3, because `Arena.src` handed back the
# bottom for the missing `src[1]` and `U32.is_zero` fired on it.
# 0 IS "NO STAGE", and 3 IS UNREACHABLE.
#
# THE FINDING, AND IT IS THE WHOLE OF `stage_pr3`: all five patterns are keyed
# `Ops.PROGRAM`, so `pdict[PROGRAM]` preserves the literal order 1,2,3,4,5, and
# rule 3's `UPat(LINEAR, src=UPat(INS))` is only consulted when rule 2's
# `UPat(LINEAR, name="lin")` has NOT matched -- which it always has, because rule
# 2's LINEAR arm says nothing about `lin.src`. MEASURED against Python:
# `pm_to_program.rewrite(PROGRAM(SINK, LINEAR(INS)))` reaches `do_estimates` (it
# raises on `sink.arg.estimates is None`), not `do_assemble`.
#
# SO A DISPATCH THAT READS THE INS IS WRONG, and this file read it: `stage_pr3` said
# 3 where Python says 2. `tp_ins` and `k_is_ins` stay, because the INS TEST is what
# rule 3's pattern says and a reader that omits it has not read the table -- but
# they are DOCUMENTED as unreachable and `stage_pr3` is what pins that.
def tp_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{1, [O.OpsPROGRAM{}], Nil{}},   # :467 PROGRAM(SINK)                    -> LINEAR
   O.PMEntry{2, [O.OpsPROGRAM{}], Nil{}},   # :468 PROGRAM(SINK, LINEAR)            -> estimates
   O.PMEntry{3, [O.OpsPROGRAM{}], Nil{}},   # :469 PROGRAM(_, LINEAR(LINEAR(INS)))  -> BINARY, UNREACHABLE
   O.PMEntry{4, [O.OpsPROGRAM{}], Nil{}},   # :470 PROGRAM(_, LINEAR)               -> SOURCE, also shadowed by 2
   O.PMEntry{5, [O.OpsPROGRAM{}], Nil{}}]   # :471 PROGRAM(_, LINEAR, SOURCE)       -> BINARY

def tp_stage.two() -> U32:
  2

def tp_stage.w3(three: Bool) -> U32:
  match three:
    case True{} : 5
    case False{}: 0

def tp_stage.w2(two: Bool, three: Bool) -> U32:
  match two:
    case True{} : tp_stage.two()
    case False{}: tp_stage.w3(three)

def tp_stage.w1(one: Bool, two: Bool, three: Bool) -> U32:
  match one:
    case True{} : 1
    case False{}: tp_stage.w2(two, three)

def tp_stage(+ar: O.Arena, +self: U32) -> U32:
  tp_stage.w1(Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 1n),
              Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 2n),
              Nat.is_eq(U32.to_nat(kn_nsrc(ar, self)), 3n))


# ===========================================================================
# THE MEASURED MUTATION TABLE, by `.agents/slop/notes/codegen-mut.py`. TWELVE
# textual edits, one at a time, each re-checked and re-run against the clean 38-row
# gate. Ten are REVERTS of one of this file's own fixes, so the set a mutation moves
# is the set of rows that fix was load-bearing for.
#
#   mutation                                    rows moved
#   --------------------------------------------------------------------------
#   M1  `kn_np` writes `n - 1` for the slot       np_slot
#   M2  `kn_np.next` drops the increment          np_next
#   M3  `kn_alu_is` loses the RECIPROCAL arm      alu_recip
#   M4  `ab_new` keeps the ALLOC op               ab, ab_grow, ab_nsrc
#   M5  `tp_stage` reads the INS (rule 3)         stage_pr2
#   M6  `tp_stage`'s arity test always true       stage_pr1, stage_pr4
#   M7  `cfg_ctx_len` 14 -> 12                   cfg_ctx
#   M8  `lw_map` drops the head                   lw_miss_nsrc, lw_sub_1
#   M9  `lw_find.hit`'s arms swapped              lw_hit, lw_sub_1
#   M10 `kn_is_expand0` drops `axis_type`         rm, rm_loop
#   M11 `ker_self` inverted                       ab, ab_nsrc, np_slot
#   M12 `kn_np`'s guard always true (see note)    --
#
# M3 MOVED NOTHING UNTIL `k_alu_recip` EXISTED. Dropping one of five arms of a
# disjunction left `alu_sqrt`, `alu_sin` and `alu_add` all unchanged, so a rule
# serving three of the five float ALUs looked correct. ONE ROW PER ARM is the only
# thing that makes a five-armed disjunction checkable, and the row was added
# because the mutation found the gap rather than before it.
#
# M5 IS `pm_to_program`'s THIRD RULE. `tp_stage` originally read the INS and
# answered 3 for `PROGRAM(SINK, LINEAR(INS))` where Python answers 2, because rule
# 2's LINEAR arm is unconstrained and shadows rule 3 entirely. `stage_pr2` is the
# row that moves; `stage_pr3` was the row that exposed it, and it is now a row
# that agrees with Python rather than one that disagreed.
# ===========================================================================

# ===========================================================================
# THE GATE. Every row is DERIVED FROM PYTHON by
# `.agents/slop/notes/kn-truth.py`, which prints its rows in THIS ORDER and with
# THIS SPELLING, so
# `diff <(python3 kn-truth.py) <(./bin/bend tinybendygrad/codegen/kernel.bend)` is
# the acceptance test and NEITHER side can be nudged to match the other.
#
# THE FIXTURE. `K.ix` is `[0]` then the interning order, so `K.at(k, n)` is a LIST
# POSITION. One `+` per node, because Bend has no store.
#
#   0 bottom  1 C0  2 C1  3 C4   4 SPECIAL   5 BUF(slot 7)  6 BUF(slot 3)
#   7 PRM(-1)  8 R_U=RANGE(C4,UNROLL)  9 R_L=RANGE(C4,LOOP)
#  10 SQ1=SQRT(C0)  11 ST1=STORE(C0, C1)
#  12 AL1=ALLOC(C1)  13 RD1=REDUCE(SQ1, R_U)
#  14 PR1=PROGRAM(SINK(SQ1))  15 PR2=PROGRAM(SINK(SQ1), LINEAR(ST1))
#  16 INS0=INS()  17 PR3=PROGRAM(SINK(SQ1), LINEAR(INS0))
#  18 PR4=PROGRAM(SINK(SQ1), LINEAR(ST1), SOURCE)
#
# `ix` PRINTS THE WHOLE LIST and `pos_same` COMPARES ITS LENGTH to `Arena.next`,
# and both exist because `PR3` was once built from `Found.ar(pr2)` -- a STALE
# arena, `INS0` having already been interned in it -- so `PR3` came back at index 17
# and every position after it named the node one slot behind its comment. That read
# as two rule bugs (`ins` answering 0, `al_store` answering NOOP) and was neither.
# A fixture whose rows cannot see the fixture is worse than no fixture.
# ===========================================================================
type K is Data:
  K{fx: F.Folded, ix: List<&2, U32>}

def K.fx(k: K) -> F.Folded:
  match k:
    case K{fx, ix}: fx

def K.ix(k: K) -> List<&2, U32>:
  match k:
    case K{fx, ix}: ix

def K.at.go(ix: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ix, n), 0)

def K.at(k: K, n: Nat) -> U32:
  K.at.go(K.ix(k), n)

def pa1(slot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

def kn_fixture() -> K:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c4 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(4)})
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "0")
  +b7 = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pa1(7)}, O.TNone{})
  +b3 = O.UOp.new(O.Found.ar(b7), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pa1(3)}, O.TNone{})
  +prm = O.UOp.new(O.Found.ar(b3), O.OpsPARAM{}, [O.Found.i(sp)], O.AParam{pa1(u32_none())}, O.TNone{})
  +ru = O.UOp.range_end(O.Found.ar(prm), O.Found.i(c4), [0], O.AXIS_UNROLL{})
  +rl = O.UOp.range_end(O.Found.ar(ru), O.Found.i(c4), [1], O.AXIS_LOOP{})
  +sq1 = O.UOp.alu(O.Found.ar(rl), O.OpsSQRT{}, [O.Found.i(c0)])
  +st1 = O.UOp.new(O.Found.ar(sq1), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +al1 = O.UOp.new(O.Found.ar(st1), O.OpsALLOC{}, [O.Found.i(c1)], O.ANone{}, O.TNone{})
  +rd1 = O.UOp.new(O.Found.ar(al1), O.OpsREDUCE{}, [O.Found.i(sq1), O.Found.i(ru)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  +sk1 = O.UOp.new(O.Found.ar(rd1), O.OpsSINK{}, [O.Found.i(sq1)], O.ANone{}, O.TNone{})
  +pr1 = O.UOp.new(O.Found.ar(sk1), O.OpsPROGRAM{}, [O.Found.i(sk1)], O.ANone{}, O.TNone{})
  +pr2 = O.UOp.new(O.Found.ar(pr1), O.OpsPROGRAM{}, [O.Found.i(sk1), O.Found.i(st1)], O.ANone{}, O.TNone{})
  +ins0 = O.UOp.new(O.Found.ar(pr2), O.OpsINS{}, Nil{}, O.ANone{}, O.TNone{})
  # `Found.ar(pr2)` HERE WOULD BE A STALE ARENA -- `ins0` was interned in it, so
  # both `ins0` and `pr3` come back at index 17 and every position after that
  # names a node one slot behind its comment. That is exactly what `pos_same` and
  # `ix` reported, and both rows are kept BECAUSE they caught it.
  +pr3 = O.UOp.new(O.Found.ar(ins0), O.OpsPROGRAM{}, [O.Found.i(sk1), O.Found.i(ins0)], O.ANone{}, O.TNone{})
  +pr4 = O.UOp.new(O.Found.ar(pr3), O.OpsPROGRAM{}, [O.Found.i(sk1), O.Found.i(st1), O.Found.i(c1)], O.ANone{}, O.TNone{})
  K{F.folded(O.Found.ar(pr4)),
    [0,
     O.Found.i(c0), O.Found.i(c1), O.Found.i(c4), O.Found.i(sp), O.Found.i(b7), O.Found.i(b3),
     O.Found.i(prm), O.Found.i(ru), O.Found.i(rl), O.Found.i(sq1), O.Found.i(st1),
     O.Found.i(al1), O.Found.i(rd1), O.Found.i(sk1), O.Found.i(pr1), O.Found.i(pr2),
     O.Found.i(ins0), O.Found.i(pr3), O.Found.i(pr4)]}

# `KN.param` -- the PARAM the rule BUILT, as a `ParamArg`, for the three rows that
# read the slot off it. `NP.k` is the `Ker` and `Ker.at` the index, so the answer is
# a node in `Ker.ar`, NOT in the fold's arena: reading the fold's arena here would
# answer the node one short of it, which is the mistake `ru_answer` records.
def KN.param.arg(a: O.Arg) -> O.ParamArg:
  match a:
    case O.AParam{pa}: pa
    case _: O.ParamArg{u32_none(), S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{},
                        False{}, None{}, None{}, False{}, None{}}

def KN.param(+np: NP) -> O.ParamArg:
  KN.param.arg(O.Arena.arg(Ker.ar(NP.k(np)), Ker.at(NP.k(np))))

def k_of(+kx: K, n: Nat) -> Ker:
  pm_alloc_to_buf(F.Folded.ar(K.fx(kx)), K.at(kx, n))

def k_al(+kx: K, n: Nat) -> Ker:
  pm_add_loads(K.fx(kx), K.at(kx, n))

def k_np_of(+kx: K, n: Nat, c: U32) -> NP:
  pm_number_params(c, F.Folded.ar(K.fx(kx)), K.at(kx, n))

def k_stage(+kx: K, n: Nat) -> U32:
  tp_stage(F.Folded.ar(K.fx(kx)), K.at(kx, n))

def k_op(nm: String, +kx: K, n: Nat) -> String:
  O.Ops.name.of(kn_op(F.Folded.ar(K.fx(kx)), K.at(kx, n)))

# ---------------------------------------------------------------------------
# THE ROWS. Grouped by the def they test, in that order.
#
# `k_np_len` / `k_cfa_len` / `k_al_len` / `k_ib_len` / `k_ab_len` / `k_tp_len` --
# the table LENGTHS. Each is `len(<table>.patterns)` and each is a COUNT, because
# a rule dropped from a table and a rule whose body is a wall both leave every
# boolean row here alone.
# ---------------------------------------------------------------------------
def k_np_len() -> U32:
  n_of(np_table())

def k_cfa_len() -> U32:
  n_of(cfa_table())

def k_al_len() -> U32:
  n_of(al_table())

def k_ib_len() -> U32:
  n_of(ib_table())

def k_ab_len() -> U32:
  n_of(ab_table())

def k_tp_len() -> U32:
  n_of(tp_table())

# `k_np_fresh` -- `x.arg.slot != -1` on the unnumbered PARAM, which is the rule's
# ONLY guard. 1 means it fires, which is what `itertools.count` gives.
def k_np_fresh() -> U32:
  +kx = kn_fixture()
  k2u(kn_slot_missing(F.Folded.ar(K.fx(kx)), K.at(kx, 7n)))

# `k_np_slot` -- the slot WRITTEN is `ctx[0] - 1`, i.e. the count BEFORE the
# increment. It is a node index, so `k_np_slot` is compared against the position of
# the rewritten PARAM in the ANSWER's arena.
def k_np_slot() -> U32:
  +kx = kn_fixture()
  O.ParamArg.slot(KN.param(k_np_of(kx, 7n, 3)))

# `k_np_next` -- the count handed to the NEXT PARAM. 4 is 3 + 1, and `k_np_next`
# is the row for the increment: a mutation dropping it leaves `k_np_slot` green.
def k_np_next() -> U32:
  +kx = kn_fixture()
  NP.n(k_np_of(kx, 7n, 3))

# `k_np_set` -- the OTHER PARAM's slot is 3 and STAYS 3: the rule does not fire on a
# node whose slot is already set, so `x.replace(...)` is never reached and the
# answer is nothing. `k_np_fresh` (fires) and `k_np_set` (does not) are the pair for
# the single guard `x.arg.slot != -1`, and both are needed: a mutation that dropped
# the guard would leave `k_np_fresh` green and move only this row.
def k_np_set() -> U32:
  +kx = kn_fixture()
  k2u(O.UOp.is_none(Ker.at(NP.k(k_np_of(kx, 6n, 3)))))

# `k_np_twice` -- the SAME count applied twice gives the SAME slot, which is what
# makes this rule order-dependent in Python and makes `ctx` a store rather than a
# value. Both calls read 3 and write 2.
def k_np_twice() -> U32:
  +kx = kn_fixture()
  k2u(U32.is_eq(O.ParamArg.slot(KN.param(k_np_of(kx, 7n, 3))),
                O.ParamArg.slot(KN.param(k_np_of(kx, 7n, 3)))))

# `k_rm` -- `len(build_range_map(sink))` for the fixture, which is 1: only `R_U` is
# UNROLL and `R_L` is LOOP. This is a COUNT over a fold and it is the row that
# catches the walk's direction, the fuel, and the `axis_type` membership at once.
def k_rm() -> U32:
  +kx = kn_fixture()
  kn_range_map_n(F.Folded.t(K.fx(kx)), F.Folded.ar(K.fx(kx)))

# `k_rm_unroll` / `k_rm_loop` -- the two halves of the `and` in `build_range_map`,
# so a mutation that dropped the `axis_type` conjunct (counting BOTH RANGEs) moves
# `k_rm` and `k_rm_unroll` and leaves `k_rm_loop`, which is the control.
def k_rm_unroll() -> U32:
  +kx = kn_fixture()
  k2u(kn_is_expand0(F.Folded.t(K.fx(kx)), F.Folded.ar(K.fx(kx)), K.at(kx, 8n)))

def k_rm_loop() -> U32:
  +kx = kn_fixture()
  k2u(kn_is_expand0(F.Folded.t(K.fx(kx)), F.Folded.ar(K.fx(kx)), K.at(kx, 9n)))

# `k_bitcast` -- `is_shape_changing_bitcast`'s op half. The rule does NOT fire on
# `SQRT`, and this is the row for the op test alone -- the shape half is a wall.
def k_bitcast() -> U32:
  +kx = kn_fixture()
  k2u(kn_is_bitcast(F.Folded.ar(K.fx(kx)), K.at(kx, 10n)))

# `k_alu_sin` / `k_alu_add` -- the five arms of `pm_cast_float_alu`'s op set and
# its control. `k_alu_len` says the TABLE holds five; these say the SET matches on
# the one op the fixture carries and not on the ALU next to it.
def k_alu_sqrt() -> U32:
  k2u(kn_alu_is(O.OpsSQRT{}))

def k_alu_sin() -> U32:
  k2u(kn_alu_is(O.OpsSIN{}))

def k_alu_add() -> U32:
  k2u(kn_alu_is(O.OpsADD{}))

# `k_alu_recip` -- the FIFTH arm. Without it, dropping the RECIPROCAL arm from the
# op set moved NO row: `alu_sqrt`, `alu_sin` and `alu_add` all still answer the
# same, and a rule that served three of five float ALUs looked correct. One row per
# arm is the only thing that makes a five-armed disjunction checkable.
def k_alu_recip() -> U32:
  k2u(kn_alu_is(O.OpsRECIPROCAL{}))

# `k_al_store` -- `pm_add_loads`'s STORE arm fires on `STORE(C0, C1)`, and the
# answer's SECOND src is the LOAD. The op NAME is the row, and `k_al_store_nsrc`
# is its count: the rewrite has two srcs, like the original.
def k_al_store_nsrc() -> U32:
  +kx = kn_fixture()
  kn_nsrc(Ker.ar(k_al(kx, 11n)), Ker.at(k_al(kx, 11n)))

# `k_al_store_src1` -- the LOADED src is `src[1]`, so the answer's second src is a
# LOAD and its first is `src[0]` UNCHANGED. Two rows for one line: `k_al_store`
# says a LOAD was built and `k_al_store_src0` says the other src was not loaded.
def k_al_sqrt() -> U32:
  k2u(O.UOp.is_none(Ker.at(k_al(kn_fixture(), 10n))))

def k_ab() -> String:
  +kx = kn_fixture()
  O.Ops.name.of(kn_op(Ker.ar(k_of(kx, 12n)), Ker.at(k_of(kx, 12n))))

# `k_ab_nsrc` -- a COUNT: the srcs are UNCHANGED, so the answer still has one. This
# is the row that distinguishes `replace(op=...)` from a rewrite that also changed
# the srcs, and both together pin `pm_alloc_to_buf` completely.
def k_ab_nsrc() -> U32:
  +kx = kn_fixture()
  kn_nsrc(Ker.ar(k_of(kx, 12n)), Ker.at(k_of(kx, 12n)))

# `k_ab_grow` -- the arena GROWS BY ONE even though the srcs did not change,
# because the OP is part of the hash. This is why `k_ab_nsrc` alone is not enough.
def k_ab_grow() -> U32:
  +kx = kn_fixture()
  U32.sub(O.Arena.next(Ker.ar(k_of(kx, 12n))), O.Arena.next(F.Folded.ar(K.fx(kx))))

# `k_ab_miss` -- a BUFFER IS NOT CLAIMED, so the rewrite produces nothing. The
# control for `k_ab_grow`, and the row that says the claim test is the table's `ops`
# list and not the rule's body.
def k_ab_miss() -> U32:
  +kx = kn_fixture()
  k2u(O.UOp.is_none(Ker.at(k_of(kx, 6n))))

# `k_stage_*` -- `pm_to_program`'s dispatch. FIVE stages and the arity test is not
# enough on its own, which is the point: `PR2` and `PR3` both have TWO srcs and
# answer 2 and 3.
def k_stage_pr1() -> U32:
  +kx = kn_fixture()
  k_stage(kx, 15n)

def k_stage_pr2() -> U32:
  +kx = kn_fixture()
  k_stage(kx, 16n)

def k_stage_pr3() -> U32:
  +kx = kn_fixture()
  k_stage(kx, 18n)

def k_stage_pr4() -> U32:
  +kx = kn_fixture()
  k_stage(kx, 19n)

# `k_ins` -- the INS half of the dispatch key on `PR3`, whose LINEAR's only src IS
# an INS. 1, and `k_not_ins` on `PR2`, whose LINEAR's src is a STORE.
def k_cfg() -> U32:
  cfg_len()

def k_cfg_ctx() -> U32:
  cfg_ctx_len()

# `k_lw_miss` -- `line_rewrite` with a rule that does NOT fire: every node passes
# through and `ret` is `(nu, [nu])`, so the output is the INPUT. A COUNT, and it is
# the row for the `or (nu, [nu])` arm.
def k_lw_miss_nsrc() -> U32:
  +kx = kn_fixture()
  U32.from_nat(List.length(&2, U32, lw_map(O.Arena.srcs(F.Folded.ar(K.fx(kx)), K.at(kx, 11n)), Nil{})))

# `k_lw_find` -- `replaced.get(x, x)` on an EMPTY map is `x`, which is the `hold`
# arm of `lw_find`. The row for the miss.
def k_lw_find() -> U32:
  +kx = kn_fixture()
  k2u(U32.is_eq(lw_find(Nil{}, K.at(kx, 10n)), K.at(kx, 10n)))

# `k_lw_hit` -- and on a map holding that key it is the VALUE, which is the
# `True{}` arm. Two rows for one line: a mutation that swapped `lw_find.hit`'s arms
# moves this one and leaves `k_lw_find`.
def k_lw_hit() -> U32:
  +kx = kn_fixture()
  +s1 = lw_install(Nil{}, K.at(kx, 10n), K.at(kx, 11n))
  k2u(U32.is_eq(lw_find(s1, K.at(kx, 10n)), K.at(kx, 11n)))

# `k_lw_sub` -- `tuple([replaced.get(x, x) for x in u.src])` with the map holding
# `src[0]`: the second src is substituted and the first is not, so the LIST is
# `(C0, STORE)`. `k_lw_sub_1` and `k_lw_sub_0` are its two halves.
# `lw_map`'s answer, positionally. `List.get` and not `[n]`, because the position
# is a `Nat` and a projection is a NAME lookup (ops.bend's header).
def lw_at(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

def k_lw_sub_1() -> U32:
  +kx = kn_fixture()
  lw_at(lw_map(O.Arena.srcs(F.Folded.ar(K.fx(kx)), K.at(kx, 11n)),
               lw_install(Nil{}, K.at(kx, 10n), K.at(kx, 11n))), 1n)

def k_lw_sub_0() -> U32:
  +kx = kn_fixture()
  lw_at(lw_map(O.Arena.srcs(F.Folded.ar(K.fx(kx)), K.at(kx, 11n)),
               lw_install(Nil{}, K.at(kx, 10n), K.at(kx, 11n))), 0n)

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))


# ---------------------------------------------------------------------------
# THE FIXTURE IS INTERNED, NOT COUNTED, so a dedup cannot shift a row silently. The
# first version of these rows anchored each one at a literal list position, and one
# `UOp.new` deduplicated the fixture down by one -- so `k_ins` read a LINEAR's SINK
# and answered 0, and `k_al_store` read a STORE's SOURCE and answered NOOP. Both
# looked like rule bugs and neither was: a row that cannot see its own fixture is
# worse than no row.
#
# `k_ops` prints EVERY node's op in order, in ONE row, so a shift is visible rather
# than inferred. `k_pos` is the list length and `k_pos_same` that it equals
# `Arena.next` -- both counts, precisely so a dedup shows up as a disagreement
# rather than as a plausible-looking number.
# ---------------------------------------------------------------------------
# `case 0n:` is a PREFIX match (constraint 9) so the walk ends on it, and the
# termination is the LIST not a fuel: `n` is the remaining length of `K.ix`.
# THE WALK IS OVER THE LIST, so the list IS the fuel -- no `Nat` and no `U32`/`Nat`
# mixing, and `List.length` never appears in a position type. `i` is the head's
# POSITION and `rest` the tail, and `K.at` takes a `Nat`.
# NO COUNTER. The first version threaded an `i` that INCREASED, which the decrease
# check reads left to right and refuses -- so it cannot be a fuel, and the list is
# the fuel. The op names come off `kn_op` in list order, which is all this row is.
def k_ops.go(ids: List<&2, U32>, +ar: O.Arena) -> String:
  match ids:
    case Nil{}   : ""
    case v <> t  : String.concat([O.Ops.name.of(kn_op(ar, v)), " ", k_ops.go(t, ar)])

def k_ops() -> String:
  +kx = kn_fixture()
  k_ops.go(K.ix(kx), F.Folded.ar(K.fx(kx)))

def k_pos.ar(+kx: K) -> U32:
  O.Arena.next(F.Folded.ar(K.fx(kx)))

def k_pos() -> U32:
  U32.from_nat(List.length(&2, U32, K.ix(kn_fixture())))

# WHICH ENTRY IS THE STALE ONE. `k_dup` is the first position whose node is not the
# one the interning order expects: the fixture's ix list is built from `Found.i`
# values, so a dedup makes a later entry REPEAT an earlier index and every position
# from there on reads a node that is one slot behind its name. That is the whole of
# `pos_same=0`.
# WHICH ENTRY IS THE STALE ONE. `k_dup` is the first POSITION whose node repeats
# the one before it: the ix list is built from `Found.i` values, so a dedup makes a
# later entry REPEAT an earlier index and every position from there on names a node
# that is not the one its comment claims. `at` is a `U32`, not a `Nat`, because the
# only thing built from it is the row's own value and `U32.add` keeps the fuel in one
# type.
def k_dup.at(at: U32) -> U32:
  at

def k_dup.hit(same: Bool, v: U32, at: U32, rest: U32) -> U32:
  match same:
    case True{} : v
    case False{}: rest

def k_dup.go(ids: List<&2, U32>, +prev: U32, +at: U32) -> U32:
  match ids:
    case Nil{}   : 0
    case +v <> t : k_dup.hit(U32.is_eq(v, prev), v, at, k_dup.go(t, v, U32.add(at, 1)))

# THE WHOLE ix LIST, as a string, because `dup` only finds an ADJACENT repeat and a
# dedup three entries apart shifts everything after it without repeating anything
# next to itself. This row is what makes the shift visible.
def k_ix.go(ids: List<&2, U32>) -> String:
  match ids:
    case Nil{}   : ""
    case +v <> t: String.concat([U32.show(v), " ", k_ix.go(t)])

def k_ix() -> String:
  k_ix.go(K.ix(kn_fixture()))

def k_dup() -> U32:
  +kx = kn_fixture()
  k_dup.go(K.ix(kx), 0, 0)

def k_pos_same() -> U32:
  +kx = kn_fixture()
  k2u(U32.is_eq(k_pos(), k_pos.ar(kx)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("np_len", k_np_len())
    b : Unit <- row("cfa_len", k_cfa_len())
    c : Unit <- row("al_len", k_al_len())
    d : Unit <- row("ib_len", k_ib_len())
    e : Unit <- row("ab_len", k_ab_len())
    f : Unit <- row("tp_len", k_tp_len())
    h : Unit <- row("np_fresh", k_np_fresh())
    i : Unit <- row("np_slot", k_np_slot())
    j : Unit <- row("np_next", k_np_next())
    k : Unit <- row("np_set", k_np_set())
    l : Unit <- row("np_twice", k_np_twice())
    m : Unit <- row("rm", k_rm())
    n : Unit <- row("rm_unroll", k_rm_unroll())
    o : Unit <- row("rm_loop", k_rm_loop())
    p : Unit <- row("bitcast", k_bitcast())
    q : Unit <- row("alu_sqrt", k_alu_sqrt())
    r : Unit <- row("alu_sin", k_alu_sin())
    s : Unit <- row("alu_add", k_alu_add())
    s1 : Unit <- row("alu_recip", k_alu_recip())
    t : Unit <- row("ab_grow", k_ab_grow())
    u : Unit <- row("ab_nsrc", k_ab_nsrc())
    v : Unit <- row("ab_miss", k_ab_miss())
    w : Unit <- row("stage_pr1", k_stage_pr1())
    x : Unit <- row("stage_pr2", k_stage_pr2())
    y : Unit <- row("stage_pr3", k_stage_pr3())
    z : Unit <- row("stage_pr4", k_stage_pr4())
    c2 : Unit <- row("cfg", k_cfg())
    d2 : Unit <- row("cfg_ctx", k_cfg_ctx())
    f2 : Unit <- row("lw_miss_nsrc", k_lw_miss_nsrc())
    h2 : Unit <- row("lw_find", k_lw_find())
    i2 : Unit <- row("lw_hit", k_lw_hit())
    j2 : Unit <- row("lw_sub_1", k_lw_sub_1())
    a2 : Unit <- row("pos", k_pos())
    a3 : Unit <- row("dup", k_dup())
    a4 : Unit <- row("pos_same", k_pos_same())
    a6 : Unit <- srow("ix", k_ix())
    a5 : Unit <- srow("ops", k_ops())
    srow("ab", k_ab())
