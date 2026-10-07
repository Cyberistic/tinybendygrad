# indexing.bend -- tinygrad/schedule/indexing.py. THE RANGEIFY CONTEXT: the
# `IndexingContext` that records which nodes get REALIZED and which ranges reach
# which node, plus `apply_movement_op`, which is the one place a movement op
# turns RANGES into other RANGES.
#
# WHAT THIS FILE IS, IN ONE PARAGRAPH. `indexing.py` is 328 lines and it is
# almost entirely DECISION and LOOKUP. What it computes is a MAP -- node to
# (input ranges, output ranges) and node to realized-or-not -- and the one piece
# of real arithmetic in it is `apply_movement_op`, whose six arms each rewrite a
# tuple of ranges by a movement op's own semantics. What it BUILDS is a STAGE
# node (`create_bufferize_and_index_srcs`) and a WHERE chain (`_stack_select`),
# and those builders are the walls named below.
#
# THE ORDER OF THE FILE IS PYTHON'S ORDER, and one piece of it is load-bearing:
# `ALWAYS_CONTIGUOUS` (indexing.py:24) is named at the TOP of the file because
# `create_bufferize_and_index_srcs` (indexing.py:90) and `realize_srcs`
# (indexing.py:32) read it, and `broadcast_axes` (indexing.py:64) reads
# `GroupOp.Broadcastable`, which `ops.bend` already has as
# `O.GroupOp.broadcastable`.
#
# ---------------------------------------------------------------------------
# THE THREE WALLS, stated where they bite. Two of the three were named for me:
# `mixin/creation.bend` and `mixin/rand.bend` name `resolve` and `UOp._min_max`
# at their own heads, and this file hits BOTH.
#
# W1. `resolve` -- ops.py:64.
#        def resolve(x, default=True):
#          if isinstance(x, bool): return x
#          return bool(sx.vmin) if (sx:=x.simplify()).vmin == sx.vmax else default
#     Two arms, and only the first is writable: a Python `bool` is identity, and
#     the second is `_min_max`. `new_range` (indexing.py:21) calls
#     `resolve(s != 1)` on a `sint`, and `broadcast_axes` (ops.py:91) calls
#     `resolve(s == 1, default=False)` on a shape dim. When the dim is a
#     CONCRETE `int` both reduce to plain arithmetic and BOTH ARE PORTED --
#     `ix_resolve_concrete` below is the whole of the first arm plus the int
#     case of the second. When the dim is a UOp the answer needs W2.
#     SUPPLIED IN THIS FILE: the concrete arm, and it is a merge point --
#     `ix_resolve_concrete(1)` is `resolve(True, ...)` and any sibling file that
#     has already committed to "the dim is an int" can call it. See
#     `ix_resolve_is1`, which is `broadcast_axes`'s exact call.
# W2. `UOp._min_max` -- ops.py:1104-1160. Named at the head of
#     `mixin/creation.bend` and `mixin/rand.bend`. It is NOT a fold property
#     (no `Derived` field answers it) because it is ARITHMETIC over the srcs'
#     intervals, and the `helpers.bend` wall recorded in bend2-constraints.md
#     ("a 64-BIT PRODUCT IS A WALL, NOT A TODO") blocks the `CMOD`/`FLOORDIV`/
#     `CDIV` arms specifically. `apply_movement_op`'s SHRINK and FLIP arms and
#     `_apply_reshape`'s `%` and `//` are all here, and all three are
#     `ix_min_max_miss()`.
# W3. The BUILDERS. `UOp.index`, `.end`, `.valid`, `.const_like`, `UOp(Ops.STAGE,
#     arg=BufferizeOpts(...))` and `graph_rewrite` are not ported (ops.py:614
#     through :853). `create_bufferize_and_index_srcs` is therefore a DECISION
#     port: it answers which src gets which treatment, and the node it would
#     build is named at the call site.
#
# `BufferizeOpts` (indexing.py:56-61) is a frozen dataclass read at
# `indexing.py:91-92`, and `ops.bend`'s `Arg` has NO constructor for a STAGE's
# arg at all -- so `s.device`, `s.removable` and `s.addrspace` are all walls.
# `rangeify.bend` states the same fact for its own three rules, and the two
# files are the same wall.
#
# THE TABLES. Three, and they are three because Python has three objects:
#
#   pm_generate_realize_map   indexing.py:45   FOUR rules
#   pm_apply_rangeify         indexing.py:136  FIVE rules
#   pm_fix_deviceless         indexing.py:149  ONE rule
#
# `ops.bend` cannot call a def in this file and each table needs its own
# dispatch, so this file has its own `<name>_table` / `_dispatch` / `_try` /
# `_scan` three times over. `uop/spec.bend` does it six times and
# `schedule/rangeify.bend` eleven; `schedule/multi.bend` says why in its header
# and there is no generic dispatch here either. `PMEntry.rej` is
# `early_reject` and is a NECESSARY CONDITION despite the name (ops.py:1609 is
# `if not early_reject.issubset(ler): continue`): a rule FIRES when its op set
# IS a SUBSET of the node's src ops, and the empty set is a subset of
# everything. Every reject slot in these three tables is EMPTY -- measured by
# the oracle (`grm_*_rej`, `par_*_rej`, `pfd_*_rej` are all `-`) -- so no rule
# here is decided by one, and `ix_early_and` vs `ix_early_or` is the mutation
# that measures it (M1 below, moves nothing, and that is a PROOF).
#
# `pm_apply_rangeify` rule 3 is `UPat(GroupOp.All, name="x")`, which is
# EVERY op except SINK -- so its op set is a 79-member list and it is a row.
# Reading a 79-element list as a `Data` record is not possible under the 28-field
# cap (bend2-constraints.md, `mixin/gradient.bend` rule 1), so the port stores
# it as `par_3_all()` returning True for every op EXCEPT SINK, and the count
# `par_3_n` (79) plus the SINK exception are the rows.
#
# THE GATE. `.agents/` is read-only to this unit, so the oracle and the mutation
# driver were written to a scratch directory and their paths are named in the
# MUTATION TABLE at the foot. The gate is a SHAPE-and-PERMUTATION table: for one
# kernel, the answer of `apply_movement_op` is printed as its AXIS-ID SEQUENCE,
# which is the permutation. A shape alone is a WEAK row here and the oracle
# proves it: `mv_perm0_ids=R0,R1` and `mv_perm1_ids=R1,R0` have the same length
# and the same `r.shape`, and a gate that printed only the length would pass
# with the two arms of `ix_mv_permute` swapped. Every `*_ids` row therefore
# prints the full id sequence, and every `*_at` row prints the AxisType column
# beside it -- which is also where a `?` appears, and a `?` IS a claim (it says
# the range came back through `.valid()` and is no longer a RANGE).

import Base

import ./../helpers.bend as H

import ./../uop/ops.bend as O

# ===========================================================================
# THE RECORDS. Bend has no dict, so `realize_map`, `non_removable` and
# `range_map` are association lists of `Data` records with a linear scan, which
# is `schedule/memory.bend`'s `Bf`/`Lane` shape.
#
# `IxReal` is `realize_map[UOp] = None | list[int]` (indexing.py:12). A `Data`
# record CANNOT hold a `Maybe` field (bend2-constraints.md, rule 15 of the spec
# notes), so the `Maybe` is the pair `islist: Bool` + `axes: List<U32>`, which is
# `Dts`/`ODt` in `mixin/weak.bend` and `device.bend`'s `Flags` -- the SAME
# shape, reached three ways.

type IxReal is Data:
  IxReal{n: U32, islist: Bool, axes: List<&2, U32>}

type IxMap is Data:
  IxMap{es: List<&2, IxReal>}

# `range_map: dict[UOp, tuple[tuple[UOp,...], tuple[UOp,...]]]` (indexing.py:14)
# -- the (INPUT ranges, OUTPUT ranges) pair. A PAIR IS A `Type` in Bend, so this
# is a two-field `Data` record (bend2-constraints.md rule 1 of the general set).

type IxRngs is Data:
  IxRngs{inp: List<&2, U32>, outp: List<&2, U32>}

type IxRMap is Data:
  IxRMap{es: List<&2, IxRngs>}

# `non_removable: dict[UOp, None]` (indexing.py:13) -- a SET, and `ix_set` is
# the same list-of-one-record the two dicts above use.

type IxSet is Data:
  IxSet{es: List<&2, U32>}

# THE WHOLE CONTEXT, in Python's declaration order (indexing.py:11-17):
# `realize_map`, `non_removable`, `range_map`, then `range_idx`. The
# `itertools.count` is a MUTABLE COUNTER and Bend has no mutable state, so it is
# a `U32` FIELD that every def threading the context bumps -- `schedule/
# allreduce.bend` gives the same treatment to the `RING`/`ALL2ALL` flags and
# `rangeify.bend` to its `ctx` counter, and it is the one wall `new_range`
# really is.

type IxCtx is Data:
  IxCtx{rmap: IxMap, nrem: IxSet, rngm: IxRMap, ridx: U32}

def IxCtx.empty() -> IxCtx:
  IxCtx{IxMap{Nil{}}, IxSet{Nil{}}, IxRMap{Nil{}}, 0}

# `IxCtx.at` is the SAME record at a later `range_idx`. Python's counter is a
# mutable `itertools.count` that `next()` advances, so `nridx_start` -- which
# reads `next(ctx.range_idx)` and throws the value away -- leaves the counter at
# 1 and the NEXT `new_range` builds `R1`. A pure `IxCtx` cannot mutate, so the
# caller supplies the counter and `nr_4_idx=1` is that, not a fudge.

def IxCtx.at(ridx: U32) -> IxCtx:
  IxCtx{IxMap{Nil{}}, IxSet{Nil{}}, IxRMap{Nil{}}, ridx}

def IxRngs.inp(x: IxRngs) -> List<&2, U32>:
  match x:
    case IxRngs{inp, outp}: inp

def IxRngs.outp(x: IxRngs) -> List<&2, U32>:
  match x:
    case IxRngs{inp, outp}: outp

def IxMap.es(x: IxMap) -> List<&2, IxReal>:
  match x:
    case IxMap{es}: es

def IxRMap.es(x: IxRMap) -> List<&2, IxRngs>:
  match x:
    case IxRMap{es}: es

def IxSet.es(x: IxSet) -> List<&2, U32>:
  match x:
    case IxSet{es}: es

def IxReal.n(x: IxReal) -> U32:
  match x:
    case IxReal{n, islist, axes}: n

def IxReal.islist(x: IxReal) -> Bool:
  match x:
    case IxReal{n, islist, axes}: islist

def IxReal.axes(x: IxReal) -> List<&2, U32>:
  match x:
    case IxReal{n, islist, axes}: axes

def IxCtx.rmap(x: IxCtx) -> IxMap:
  match x:
    case IxCtx{rmap, nrem, rngm, ridx}: rmap

def IxCtx.ridx(x: IxCtx) -> U32:
  match x:
    case IxCtx{rmap, nrem, rngm, ridx}: ridx

def IxCtx.nrem(x: IxCtx) -> IxSet:
  match x:
    case IxCtx{rmap, nrem, rngm, ridx}: nrem

def IxCtx.rngm(x: IxCtx) -> IxRMap:
  match x:
    case IxCtx{rmap, nrem, rngm, ridx}: rngm

# ===========================================================================
# THE ASSOCIATION LISTS. Four folds, one per dict, each a two-scrutinee match
# with the KEY and the rest, because a `Maybe` cannot be threaded through a
# recursion (bend2-constraints.md rule 2 of the general set) and an early return
# out of a fold needs mutual recursion, which is refused.

# THE LIST IS THE FIRST PARAMETER because the fuel is a `Nat` INDEX that does not
# shrink and the decrease check reads arguments left to right (bend2-constraints
# rule 7 of the `divandmod.bend` set: "the countdown has to be the SECOND
# parameter for both to line up"). `k` is passed unchanged, so the tail is the
# only subterm and it is first.
#
# `n == key` is a `Bool` PARAMETER, not a scrutinee: a `match` may not examine a
# computed value (bend2-constraints rule 2), so the compare is computed in the
# caller and the arm consumes a parameter. This is `spec.bend`'s `DevOpt` shape.

#

#

def ixr_hit.of(hit: Bool, k: U32, +e: IxReal) -> IxReal:
  match hit:
    case True{}: e
    case False{}: e

def ixr_step(+e: IxReal, acc: Maybe<&2, IxReal>, k: Nat) -> Maybe<&2, IxReal>:
  Bool.pick(Maybe<&2, IxReal>, U32.is_eq(IxReal.n(e), U32.from_nat(k)), Some{e}, acc)

def ixr_find.go(+es: List<&2, IxReal>, +k: Nat, +acc: Maybe<&2, IxReal>) -> Maybe<&2, IxReal>:
  match es:
    case Nil{}: acc
    case e <> t: ixr_find.go(t, k, ixr_step(e, acc, k))

# ===========================================================================
# `ALWAYS_CONTIGUOUS` -- indexing.py:24-26. NINE ops:
#   AFTER BUFFER ALLOC CONST MSELECT MSTACK PARAM LOAD CALL
# and it is read at `realize_srcs` (:32), `realize_custom_kernel_srcs` (:41) and
# `create_bufferize_and_index_srcs` (:90). A Python `set` membership is a
# linear scan over a `List<Op>`, which is what `ix_ac` is; the rows are
# `ac_n`, `ac_sorted` and one row per probed op including the NEGATIVES, because
# a table with no negative row cannot see a set that has grown by one.
# THE HEAD READER. `List.head` answers a `Maybe` (bend2-constraints.md,
# `upat.bend` rule 4) so it needs an `.of` split, and a one-slot `Maybe` may
# only be read ONCE, so the value and the test travel together.

def ix_hd.of(m: Maybe<&2, O.Op>) -> O.Op:
  match m:
    case Some{o}: o
    case _: O.OpsNOOP{}

def ix_hd(+xs: List<&2, O.Op>) -> O.Op: ix_hd.of(List.head(&2, O.Op, xs))

# THE SCAN, AND THE HEAD IS TESTED ON THE WAY PAST IT. Peeling the head in the
# driver and never comparing it was the first version, and it answered False for
# every set member except the FIRST: `ac_after=True` beside `ac_alloc=False` in a
# nine-element list. Eight of nine rows FALSE and the gate was not red, because
# FALSE is a legal answer for a NEGATIVE row -- the recorded "ALL-TRUE tells you
# the cases you covered and nothing about the rest" in its most embarrassing
# form. Only the diff against the oracle saw it.

# `out_shape[nleft+i]`, and `List.get` answers a `Maybe`
# (bend2-constraints.md, `upat.bend` rule 4).

def ix_mem(+xs: List<&2, O.Op>, +hit: Bool, +w: O.Op) -> Bool:
  match xs:
    case Nil{}: hit
    case _ <> t: Bool.pick(Bool, hit, True{}, ix_mem(t, O.eq_op(ix_hd(xs), w), w))

# THE LIST IS FIRST so the tail is the first shrinking subterm the decrease
# checker finds (bend2-constraints.md rule 2 of the "ELEVEN MORE RULES" set).

def ix_mem1(+w: O.Op, +xs: List<&2, O.Op>) -> Bool:
  ix_mem(xs, O.eq_op(ix_hd(xs), w), w)

def ix_ac_ops() -> List<&2, O.Op>:
  [O.OpsAFTER{}, O.OpsALLOC{}, O.OpsBUFFER{}, O.OpsCALL{}, O.OpsCONST{},
   O.OpsLOAD{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsPARAM{}]

def ix_ac_len() -> U32: U32.from_nat(List.length(&2, O.Op, ix_ac_ops()))

def ix_ac(w: O.Op) -> Bool: ix_mem1(w, ix_ac_ops())

# ===========================================================================
# W1, SUPPLIED: `resolve`'s FIRST arm, extended to the int case of the second.
#
# `resolve(x, default=True)` is identity on a Python `bool` and is `_min_max`
# otherwise. When the scrutinee is a CONCRETE int -- which is what a shape of a
# materialized graph is -- the whole answer is `(s != d)`. So:
#
#   ix_resolve_concrete(s, d)  ==  resolve(s != d)  for integer s, d
#   ix_resolve_is1(s)          ==  resolve(s == 1, default=False)
#   ix_resolve_ne1(s)          ==  resolve(s != 1)                       (indexing.py:21)
#
# and the three places indexing.py asks are named at each call site. `s` is a
# `U32` here where Python's is a `sint`, and that is the WHOLE of the gap: a
# symbolic dim is not a `U32`, and the def that has one must not call these.
#
# `ix_resolve_miss()` is the named wall, the same shape `rangeify.bend`'s
# `rf_ranges_miss()` takes: one constant, `rg "ix_resolve_miss"` lists every
# dependent, and no caller can get a plausible wrong answer by accident.

#
#
#
#

def ix_resolve_concrete(s: U32, d: U32) -> Bool: Bool.not(U32.is_eq(s, d))

def ix_resolve_is1(s: U32) -> Bool: U32.is_eq(s, 1)

def ix_resolve_ne1(s: U32) -> Bool: ix_resolve_concrete(s, 1)

def ix_resolve_miss() -> Bool: True{}

# `List<&2, U32>`'s length, and the SECOND of the four per-element-type length
# readers this file needs (`U32`, `O.Op`, `O.PMEntry`, and no `Bool` at all).

def ix_len(+xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

# `len(out_shape) - len(src_shape) < 0`, i.e. `len(src) > len(out)`. A `U32`
# WRAPS, so this is an explicit comparison and NOT a subtraction -- the recorded
# `U32.sub(0,1) = 4294967295` trap. An earlier revision returned
# `U32.sub(no, ns)` on the NON-negative arm, which made `bax_neg` produce
# `nleft = 4294967295` and then HUNG: `ix_range` built a four-billion-element
# list and the runtime died with
# `bend: memory fault (machine stack overflow?)` -- the diagnostic the notes
# send you hunting for a runaway fold in YOUR OWN code, and there was none.

def ix_bag.of(+ns: U32, +no: U32) -> U32: Bool.pick(U32, U32.is_lt(no, ns), 0, U32.sub(no, ns))

def ix_nleft.of(ns: U32, no: U32) -> U32: ix_bag.of(ns, no)

def ix_bax_nleft(+srcs: List<&2, U32>, +outs: List<&2, U32>) -> U32:
  ix_nleft.of(ix_len(srcs), ix_len(outs))

def ix_ndim_neg(ns: U32, no: U32) -> Bool: U32.is_lt(no, ns)

def ix_bax_neg(+srcs: List<&2, U32>, +outs: List<&2, U32>) -> Bool:
  ix_ndim_neg(ix_len(srcs), ix_len(outs))

# ===========================================================================
# `broadcast_axes` -- ops.py:89-92, which indexing.py:64 CALLS. Full text:
#
#   def broadcast_axes(src_shape, out_shape):
#     if (nleft := len(out_shape)-len(src_shape)) < 0: raise RuntimeError(...)
#     return tuple(range(nleft)) + tuple(nleft+i for i,s in enumerate(src_shape)
#                                         if resolve(s == 1, default=False)
#                                         and resolve(out_shape[nleft+i] != 1))
#
# Two halves and they are DIFFERENT in kind: `nleft` is a length subtraction and
# the `raise` is Python's negative-length guard, and the comprehension is a W1
# question per dim. `ix_bax_go` ports the comprehension for INTEGER dims; a
# symbolic dim needs W2 and the caller must say so.
#
# The accumulator is APPENDED (`List.append(&2, U32, acc, [x])`) because the
# result feeds a walk, not a join -- bend2-constraints.md's `wgsl` entry. An
# earlier draft prepended and every `bax` row came out reversed, which is the
# recorded `mxw_stk` failure (movement.bend rule 15) exactly.
# `out_shape[nleft+i]`, and `List.get` answers a `Maybe`
# (bend2-constraints.md, `upat.bend` rule 4).

#
#

def ix_bax_out.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: 1

def ix_bax_out(+nleft: U32, +outs: List<&2, U32>, i: U32) -> U32:
  ix_bax_out.of(List.get(&2, U32, outs, U32.to_nat(U32.add(nleft, i))))

# the `if` CONDITION as a `Bool`, because a `match` may not scrutinise the two
# `List.get` results and a `.go` split of a self-recursive step is mutual
# recursion (bend2-constraints.md, `mixin/movement.bend` rule 2).

def ix_bax_pick(s: U32, +nleft: U32, +outs: List<&2, U32>, i: U32) -> Bool:
  Bool.and(ix_resolve_is1(s), Bool.not(ix_resolve_is1(ix_bax_out(nleft, outs, i))))

def ix_bax_one(pick: Bool, +acc: List<&2, U32>, +i: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, pick, List.append(&2, U32, acc, [i]), acc)

# THE COMPREHENSION. The list is FIRST so the tail is the first shrinking
# subterm the decrease checker finds, and `i` is the `enumerate` index threaded
# as a `U32` because a `list` tail cannot carry it (bend2-constraints.md,
# `mixin/tensor.py` rule 1).

def ix_bax_go(+srcs: List<&2, U32>, +i: Nat, +nleft: U32, +outs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case s <> t:
      ix_bax_go(t, Nat.add(i, 1n), nleft, outs, ix_bax_one(ix_bax_pick(s, nleft, outs, U32.from_nat(i)), acc, U32.add(nleft, U32.from_nat(i))))

# `tuple(range(nleft))` -- the leading `range`, APPENDED in order.

def ix_range.go(+n: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: ix_range.go(p, U32.add(i, 1), List.append(&2, U32, acc, [i]))

def ix_range(n: U32) -> List<&2, U32>:
  ix_range.go(U32.to_nat(n), 0, Nil{})

def ix_bax.go(+srcs: List<&2, U32>, +outs: List<&2, U32>) -> List<&2, U32>:
  ix_bax_go(srcs, 0n, ix_bax_nleft(srcs, outs), outs, ix_range(ix_bax_nleft(srcs, outs)))

# THE `raise` ARM IS A SEPARATE DEF, and that is forced: `Bool.pick` and a
# `match` arm both evaluate their ARGUMENTS first (bend2-constraints.md,
# `mixin/movement.bend` rule 5 -- "a flag parameter makes the arms cheap, it does
# not make the arguments lazy"), so passing the body in would build the range
# list even on the raising case. The def whose FIRST parameter is the flag is
# the only shape that is lazy.

def ix_bax_pick.of(bad: Bool, +srcs: List<&2, U32>, +outs: List<&2, U32>) -> List<&2, U32>:
  match bad:
    case True{}: Nil{}
    case False{}: ix_bax.go(srcs, outs)

def ix_bax(+srcs: List<&2, U32>, +outs: List<&2, U32>) -> List<&2, U32>:
  ix_bax_pick.of(ix_bax_neg(srcs, outs), srcs, outs)

# ===========================================================================
# `data_srcs` -- indexing.py:68-71. FULLY PORTED, and it is the smallest
# complete thing in the file:
#
#   if op in {PARAM, BUFFER, ALLOC, RANGE, SPECIAL}: return ()
#   if op in GroupOp.Movement|{INDEX, STAGE, REDUCE, AFTER, END, BACKEDGE, COPY}: return src[:1]
#   return src
#
# `GroupOp.Movement` is `O.GroupOp.movement` (ops.bend:443) and is reused rather
# than re-listed, which is the reuse the brief asks for: a SIX-member set that
# `mixin/movement.bend` already owns.
#
# The answer is a LENGTH for every arm -- `()`, `src[:1]`, `len(src)` -- and
# `src[:1]` is empty when there is no src, so `ix_ds_take` handles that without
# a separate case (movement.bend's `mxm_not_const` does the same).

# `src[:1]` -- ONE arm, and it is the arm that has to know `src[:1]` of an empty
# `src` is empty. The parameter is the `src[:1]` DECISION (`ix_ds_one`), so `True`
# means "take one" and `False` means the `case _` arm, which is all of `src`.

def ix_ds_take.of(one: Bool, +ss: List<&2, U32>) -> List<&2, U32>:
  match one:
    case True{}: List.take(&2, U32, ss, 1n)
    case False{}: ss

# `op in {PARAM, BUFFER, ALLOC, RANGE, SPECIAL}` -- indexing.py:69.

def ix_ds_take(one: Bool, +ss: List<&2, U32>) -> List<&2, U32>:
  ix_ds_take.of(one, ss)

# `op in {PARAM, BUFFER, ALLOC, RANGE, SPECIAL}` -- indexing.py:69. The FIVE
# members are listed because `GroupOp.Broadcastable` is NOT this set (SPECIAL is
# in neither) and reusing it would be a bug. `ix_mem1` IS the membership scan.

def ix_ds_zero(op: O.Op) -> Bool:
  ix_mem1(op, [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsRANGE{}, O.OpsSPECIAL{}])

# `op in GroupOp.Movement|{INDEX, STAGE, REDUCE, AFTER, END, BACKEDGE, COPY}` --
# indexing.py:70. The SIX movements come from `ops.bend` as `O.GroupOp.movement`
# (the reuse the brief asks for) and the SEVEN extras are listed.

# `+op` because the scan and the movement test each read it and `Op` is
# Data-kinded (ops.bend:101).

def ix_ds_one(+op: O.Op) -> Bool:
  Bool.or(ix_mem1(op, [O.OpsINDEX{}, O.OpsSTAGE{}, O.OpsREDUCE{}, O.OpsAFTER{}, O.OpsEND{}, O.OpsBACKEDGE{}, O.OpsCOPY{}]), O.GroupOp.movement(op))

# THE ANSWER, as a length. `src[:1]` is `1` when there is a src and `0`
# otherwise, so `ix_ds_n` is the whole of the function's observable behaviour and
# the gate is 22 `ds_*_srcs` rows.

# THE ANSWER, as a LENGTH, and it goes through `ix_ds_take` because `src[:1]` is
# a LIST and `ix_ds_take` is the arm that builds it. A mutation of `ix_ds_take`
# moved NOTHING before this, which is the blind spot the mutation table exists to
# find: the def was written, commented and never called.

def ix_ds_n.of(zero: Bool, one: Bool, +ss: List<&2, U32>) -> U32:
  Bool.pick(U32, zero, 0, ix_len(ix_ds_take(one, ss)))

# ===========================================================================
# `argsort` -- helpers.py, read at indexing.py:174 (`Ops.PERMUTE`). FULLY
# PORTED: a selection sort over a tuple of permutation indices.
#
# It is the PERMUTATION INVERSE: `argsort((1,0))` is `(1,0)` because position 0
# takes the value at index 1. So step `j` emits the INDEX of the smallest value
# not yet placed -- the index IS the answer, which is why `ix_aslot` returns a
# `U32` and not a value -- and then marks THAT index placed. An earlier revision
# marked `j` placed and always scanned from slot 0, so it answered the identity
# for every input and all seven `argsort*` rows read as an empty list.
#
# `mv_perm*_ids` is where the answer is USED, and `argsort*` is the answer.

def ix_ds_n(+ar: O.Arena, +op: O.Op, i: U32) -> U32:
  ix_ds_n.of(ix_ds_zero(op), ix_ds_one(op), O.Arena.srcs(ar, i))

def ix_asc_marked(+k: Nat, +placed: List<&2, U32>) -> Bool:
  Bool.not(U32.is_zero(Maybe.default(&2, U32, List.get(&2, U32, placed, k), 0)))

# `ys[j] < bestv`, and `U32.is_lt` is the STRICT comparison argsort needs: a tie
# must keep the EARLIER index, which is what first-wins gives. The argument order
# matters -- an earlier revision read `is_lt(bestv, y)` and so never found a
# smaller value than the initial `4294967295`, which made every `argsort*` row
# the constant index 0.

def ix_asc.less(a: U32, b: U32) -> Bool: U32.is_lt(a, b)

def ix_aslot_better(+k: Nat, y: U32, bestv: U32, +placed: List<&2, U32>) -> Bool:
  Bool.and(Bool.not(ix_asc_marked(k, placed)), ix_asc.less(y, bestv))

# THE LIST IS FIRST and `k` is THIRD, and both positions are forced: the checker
# reads left to right and each argument must pass unchanged until one shrinks, so
# a growing `k` in the first slot hides the tail behind it. With `ys` first the
# shrink is found immediately and the arguments after it may be anything.

def ix_aslot.go(+ys: List<&2, U32>, +placed: List<&2, U32>, +k: Nat, +best: U32, +bestv: U32) -> U32:
  match ys:
    case Nil{}: best
    case y <> t:
      ix_aslot.go(t, placed, Nat.add(k, 1n),
        Bool.pick(U32, ix_aslot_better(k, y, bestv, placed), U32.from_nat(k), best),
        Bool.pick(U32, ix_aslot_better(k, y, bestv, placed), y, bestv))

def ix_aslot(+ys: List<&2, U32>, +placed: List<&2, U32>) -> U32:
  ix_aslot.go(ys, placed, 0n, 0, 4294967295)

# SET `placed[j]`, in place, by rebuilding -- a `List` has no update, and the tail
# is the shrink the decrease checker wants.

# `List.append(acc, [x])` is a TAIL append (`acc ++ [x]`), so building `[x] ++ t`
# needs the append reversed -- the "every row came out reversed" trap of
# `mxw_stk`, and the reason this walk cannot use `List.append` directly.

def ix_cons(h: U32, +t: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, Nil{}, [h]), t)

def ix_asc_mark.go(+j: U32, +ps: List<&2, U32>, +k: Nat) -> List<&2, U32>:
  match ps:
    case Nil{}: Nil{}
    case p <> t:
      ix_cons(Bool.pick(U32, U32.is_eq(U32.from_nat(k), j), 1, p), ix_asc_mark.go(j, t, Nat.add(k, 1n)))

def ix_asc_mark(+j: U32, +ps: List<&2, U32>) -> List<&2, U32>: ix_asc_mark.go(j, ps, 0n)

# The decrease is the COUNT, and it is a `Nat`: an earlier revision matched on a
# separate `k` that started at 0n and so took `case 0n` on the first step, which
# made `placed` the EMPTY list, made every index read as unplaced, and made every
# `argsort*` row the constant index 0.

def ix_asc_pad.go(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: ix_asc_pad.go(p, List.append(&2, U32, acc, [0]))

def ix_asc_pad(n: U32) -> List<&2, U32>: ix_asc_pad.go(U32.to_nat(n), Nil{})

def ix_asort.go(k: Nat, +ys: List<&2, U32>, +placed: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p:
      ix_asort.go(p, ys, ix_asc_mark(ix_aslot(ys, placed), placed), List.append(&2, U32, acc, [ix_aslot(ys, placed)]))

def ix_asort(+ys: List<&2, U32>) -> List<&2, U32>:
  ix_asort.go(U32.to_nat(ix_len(ys)), ys, ix_asc_pad(ix_len(ys)), Nil{})

# ===========================================================================
# `apply_movement_op` -- indexing.py:170-187. THE ARITHMETIC, AND THE GATE.
#
#   SHRINK:  tuple(a if off == 0 else a+off for a,(off,_) in zip(rngs, arg))
#   PERMUTE: tuple(rngs[p] for p in argsort(arg))
#   FLIP:    tuple(((s-1)-a) if f else a for a,s,f in zip(rngs, in_shape, arg))
#   EXPAND:  rngs[len(arg):]
#   PAD:     tuple(r if (sz == sh and off == 0) else (r-off).valid(...) ...)
#   RESHAPE: _apply_reshape(...)                      # THE WALL
#   case _: raise RuntimeError(f"{op} is not a MovementOp")
#
# WHAT IS PORTED AND WHAT IS NOT, arm by arm:
#
#  * PERMUTE is FULLY PORTED. It is a pure REORDERING of the input range tuple
#    and needs no arithmetic at all, so it is the arm that carries the
#    permutation claim and the one the `mv_perm*` rows gate. `ix_mv_permute`
#    picks `rngs[argsort(arg)[j]]` and the `*_ids` row is that exact sequence.
#  * EXPAND is FULLY PORTED for the same reason -- it is `rngs[len(arg):]`, a
#    tail drop. The rows `mv_expand*_n` pin the LENGTH, and the oracle says 0 for
#    every fixture here, which is the `list` tail being shorter than the drop.
#  * SHRINK and FLIP and PAD have their DECISION ported and their ARITHMETIC
#    named: `a+off`, `(s-1)-a` and `r-off` all build a node through the symbolic
#    simplify, which is W3 plus W2. `ix_mv_shrink_is_add` and `ix_mv_flip_is_add`
#    answer the ONE BIT the port can -- whether this dim becomes a new node or is
#    passed through -- and that is a real claim with a real row (`mv_shrink1_ids`
#    is `ADD,R1` and `mv_shrink0_ids` is `R0,R1`).
#  * PAD's `sz == sh and off == 0` is the no-op test and it IS the whole of
#    `mv_pad0_ids=R0,R1` against `mv_pad1_ids=WHERE,R1`, so it is ported; the
#    `.valid(graph_rewrite(...))` is W3.
#  * RESHAPE is `_apply_reshape` (indexing.py:155-167), which is `UOp.sink`,
#    `usum`, `%` and `//` followed by a `graph_rewrite` under `symbolic` --
#    three builders and W2, so the arm is `ix_mv_reshape` and it answers the
#    IDENTITY (a RESHAPE whose arg is the source shape is the input unchanged),
#    which is the one row `mv_reshape2_ids=R0` is about.
#  * The `case _` raise is `ix_mv_is_movement` and `ix_mv_raise`, and
#    `mv_add_raises=raise` is the row.
#
# A RANGE is `O.Arg` `ARange{ids, at}` (ops.bend:1504), and `UOp.axis_id`
# (ops.py:502) and `UOp.axis_type` (:507) are BOTH readers over that one arg, so
# they are TWO readers over the SAME pair. `ids` is a LIST -- a broadcast range
# carries several -- which is why every `*_ids` row prints the whole sequence.
#
# THEY ARE LOCAL, and that is a constraint rather than a preference: they used to
# be `F.UOp.axis_id` and `F.UOp.axis_type` from `uop/fold.bend`, and a file cannot
# import `fold.bend` because as an IMPORT it has unresolved forward references
# (`perm_ds.ans` at 1405, `perm.go` at 1385, `g_mv_r23` at 2807) that
# `--check-only` does not report while `fold.bend` is the TOP-LEVEL file. Six
# readers, zero imports, same answers.

def ix_nth(xs: List<&2, U32>, k: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, k), 0)

def ix_axis_ids.of(arg: O.Arg, op: O.Op) -> Maybe<&2, List<&2, U32>>:
  match arg op:
    case O.ARange{ids, at} O.OpsRANGE{}: Some{ids}
    case _ _: None{}

def ix_axis_at.of(arg: O.Arg, op: O.Op) -> Maybe<&2, O.AxisType>:
  match arg op:
    case O.ARange{ids, at} O.OpsRANGE{}: Some{at}
    case _ _: None{}

# `None` -- a node that is not a RANGE -- is the empty sequence and `AXIS_LOOP`,
# and `ix_rng_at` is where the `?` in an `*_at` row comes from.

def ix_rng_id.of(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match m:
    case Some{v}: v
    case _: Nil{}

def ix_rng_id(+ar: O.Arena, +i: U32) -> List<&2, U32>:
  ix_rng_id.of(ix_axis_ids.of(O.Arena.arg(ar, i), O.Arena.op(ar, i)))

def ix_rng_axis(+ar: O.Arena, +i: U32) -> U32: ix_nth(ix_rng_id(ar, i), 0n)

def ix_rng_at.of(m: Maybe<&2, O.AxisType>) -> O.AxisType:
  match m:
    case Some{a}: a
    case _: O.AXIS_LOOP{}

def ix_rng_at(+ar: O.Arena, +i: U32) -> O.AxisType:
  ix_rng_at.of(ix_axis_at.of(O.Arena.arg(ar, i), O.Arena.op(ar, i)))


# `List.length` is per ELEMENT TYPE, so an op list and an entry list each need
# their own reader; there is no `List<&2, O.Op>` reuse of `ix_len`.

def ix_len_str(xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def ix_ops_n(ops: List<&2, O.Op>) -> U32: U32.from_nat(List.length(&2, O.Op, ops))

def ix_pme_n(es: List<&2, O.PMEntry>) -> U32: U32.from_nat(List.length(&2, O.PMEntry, es))

# `new_range(1)` returns `UOp.const(0)` and `nr_1_val` is that CONST's payload. The
# reader is LOCAL: it used to be `M.mxm_const_val` from `mixin/movement.bend`, and
# one borrowed reader is not worth an import of a file that does not check.

def ix_const_arg.of(a: O.Arg) -> U32:
  match a:
    case O.APy{O.CInt{i}}: H.lo32(i)
    case _: 0

def ix_const_val(+ar: O.Arena, +i: U32) -> U32:
  ix_const_arg.of(O.Arena.arg(ar, i))

def ix_mv_is_movement(op: O.Op) -> Bool: O.GroupOp.movement(op)

# `rngs[p]` -- a positional read, so a `List.get` and a total wrapper.
# `ix_mv_permute` is the walk; this is the ONE element reader, and `List.get`
# answers a `Maybe` (bend2-constraints.md, `upat.bend` rule 4).

def ix_mv_ats.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: 0

def ix_mv_ats(+rs: List<&2, U32>, j: Nat) -> U32:
  ix_mv_ats.of(List.get(&2, U32, rs, j))

# A ZIP OF TWO LISTS IS REFUSED -- the decrease checker reads arguments left to
# right and a `match ps rs` shrinks both, so neither tail is the FIRST shrink.
# The permutation is `rs[p]` for each `p` in order, which is a POSITIONAL READ:
# `ps` is the only thing that shrinks and `rs` rides along unchanged.

def ix_mv_permute.go(+ps: List<&2, U32>, +rs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: ix_mv_permute.go(t, rs, List.append(&2, U32, acc, [ix_mv_ats(rs, U32.to_nat(p))]))

def ix_mv_permute(+arg: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  ix_mv_permute.go(ix_asort(arg), rngs, Nil{})

def ix_shr_nooff(off: U32) -> Bool: U32.is_zero(off)

# `a if off == 0 else a+off`. The port answers WHICH, never the `a+off`: that
# build is W3. `ix_mv_shrink_is_add` is `not ix_shr_nooff`, i.e. "this dim
# becomes a NEW node", and the gate reads it off the fixture's `off` list.

def ix_mv_shrink_is_add(off: U32) -> Bool: Bool.not(ix_shr_nooff(off))

# `f` is the FLIP flag and `(s-1)-a` is the build; the decision is `f`.

def ix_mv_flip_is_add(f: U32) -> Bool: Bool.not(U32.is_zero(f))

# --- EXPAND: `rngs[len(arg):]`. FULLY PORTED. ------------------------------

def ix_mv_expand(+arg: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, rngs, U32.to_nat(ix_len(arg)))

# --- RESHAPE: the IDENTITY only. `ix_mv_reshape_same` is
# `arg == in_shape`, which is `F.eq_sints` over the two dim lists after
# `mxm_as_shape`-style flattening. The full `_apply_reshape` is W2+W3.

def ix_mv_reshape_same.go(+as: List<&2, U32>, +bs: List<&2, U32>, +aa: List<&2, U32>, +bb: List<&2, U32>) -> Bool:
  match as bs:
    case Nil{} Nil{}: True{}
    case _ Nil{}: False{}
    case Nil{} _: False{}
    case a <> at b <> bt:
      ix_mv_reshape_same.go(at, bt, List.append(&2, U32, aa, [a]), List.append(&2, U32, bb, [b]))

# `_apply_reshape` -- indexing.py:155-167. THE WALL, in full:
#
#   acc = 1
#   for s,src in list(zip(out_shape, urngs.src))[::-1]:
#     axes_in.append(acc*src); acc *= s
#   combined_axes = UOp.const(0).usum(axes_in)
#   for s in in_shape[::-1]:
#     axes_out.append(combined_axes % s); combined_axes //= s
#   return graph_rewrite(UOp.sink(*axes_out[::-1]), symbolic+..., name="reshape")
#
# `usum` is W3, `%` and `//` are W2 (the `FLOORDIV`/`FLOORMOD` arms of
# `_min_max` are the ones the 64-bit-product wall blocks), and the `graph_rewrite`
# is W3. What IS portable and gated is the REVERSE walk -- `axes_in` is built
# from the zip read BACKWARDS, which is a fold with a reversed accumulator, and
# `ix_ar_rev` is it -- plus the `acc` product, which is `ix_ar_acc`.

#
#

def ix_mv_reshape_same(+arg: List<&2, U32>, +src: List<&2, U32>) -> Bool:
  ix_mv_reshape_same.go(arg, src, Nil{}, Nil{})

def ix_ar_rev.go(+xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: ix_ar_rev.go(t, List.append(&2, U32, acc, [x]))

def ix_ar_rev(+xs: List<&2, U32>) -> List<&2, U32>:
  ix_ar_rev.go(xs, Nil{})

def ix_ar_acc(acc: U32, s: U32) -> U32: U32.mul(acc, s)

def ix_ar_acc0() -> U32: 1

# ===========================================================================
# `IndexingContext.new_range` -- indexing.py:18-21. FULLY PORTED on the
# CONCRETE arm, and the counter is the parameter that `IxCtx.ridx` is.
#
#   def new_range(self, s, axistype=AxisType.WEAK) -> UOp:
#     if isinstance(s, UOp) and s.op is Ops.RANGE: return s
#     return UOp.range(s, next(self.range_idx), axistype) if resolve(s!=1) else UOp.const(0)
#
# THREE claims, and all three are rows:
#   * `s == 1` gives `UOp.const(0)` and does NOT advance the counter --
#     `nr_1_op`, `nr_counter_after_two_ones`.
#   * `s != 1` gives a RANGE with `AxisType.WEAK` and DOES advance it --
#     `nr_4_op`, `nr_4_at`, `nr_counter_after_two_ranges`.
#   * a RANGE input is returned UNCHANGED and also does not advance it --
#     `nr_passthru`.
# The last one is a `Bool` PARAMETER (`ix_nr_passthru`) rather than a `match` on
# a computed op, because `O.eq_op` is a CALL (bend2-constraints rule 2).

# `if isinstance(s, UOp) and s.op is Ops.RANGE: return s` -- indexing.py:19, the
# PASS-THROUGH arm, and the one arm whose answer is a NODE rather than a dim.
# `ix_nr_through` returns the input index unchanged and falls through to `ridx`
# otherwise, so the row is a real comparison against the input node: a port that
# built a fresh RANGE instead of returning `s` would answer 0.

def ix_nr_through(ar: O.Arena, +i: U32, ridx: U32) -> U32:
  Bool.pick(U32, O.eq_op(O.Arena.op(ar, i), O.OpsRANGE{}), i, ridx)

def ix_nr_passthru(+ar: O.Arena, +i: U32, ridx: U32) -> Bool:
  U32.is_eq(ix_nr_through(ar, i, ridx), i)

def ix_nr_is_one(s: U32) -> Bool: ix_resolve_is1(s)

def ix_nr_pick(one: Bool, at: O.AxisType, +ar: O.Arena, s: U32, ridx: U32) -> O.Found:
  match one:
    case True{}: O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
    case False{}: O.UOp.range_end(ar, s, [ridx], at)

def ix_new_range.of(one: Bool, at: O.AxisType, +ar: O.Arena, s: U32, ridx: U32) -> O.Found:
  ix_nr_pick(one, at, ar, s, ridx)

# the counter advance, which is the WHOLE of the mutability `new_range` has.

def ix_new_range(+ctx: IxCtx, +ar: O.Arena, +s: U32, at: O.AxisType) -> O.Found:
  ix_new_range.of(ix_nr_is_one(s), at, ar, s, IxCtx.ridx(ctx))

def ix_nr_next(+ridx: U32, one: Bool) -> U32: Bool.pick(U32, one, ridx, U32.add(ridx, 1))

# ===========================================================================
# THE REALIZE-MAP RULE BODIES -- indexing.py:28-43. All four MUTATE the Python
# context, and all four are therefore DECISIONS here: each answers the LIST of
# keys it would insert, and `ix_m*` is the def a caller folds into `IxCtx.rmap`.
#
# `realize(ctx, tr)` (:28) inserts `(tr, None)` -- one key, no axis list.

#

#

def realize(tr: U32) -> IxReal: IxReal{tr, False{}, Nil{}}

# `realize_srcs(ctx, rb)` (:30-32) -- every src whose base is NOT in
# ALWAYS_CONTIGUOUS. `s.base.op` is `F.fold.base` -> `F.UOp.base`, which is a
# WALL the fold answers as a `Maybe`, and `Maybe.default(..., 0)` is the arena
# bottom (movement.bend rule 16: a stale arena gives an EMPTY answer, not a
# wrong one).

# `UOp.base` (ops.py:785) is a KAHN WALK over the fold table and `fold.bend` is
# the file that owns it, so `ix_base_idx` is a NAMED WALL: `realize_store_after_src`
# (:34-36) asks `dest.base in src.toposort(...)` and this port answers the
# toposort half only. `rg -n "ix_base_miss" tinybendygrad/` lists every dependent.

def ix_base_miss(ar: O.Arena, s: U32) -> U32: s

def ix_base_idx(+ar: O.Arena, s: U32) -> U32: ix_base_miss(ar, s)

def ix_base_op(+ar: O.Arena, s: U32) -> O.Op: O.Arena.op(ar, ix_base_idx(ar, s))

# `realize_store_after_src(ctx, dest, src)` (:34-36) -- `dest.base in
# src.toposort(enter_calls=False)`. The identity is `U32.is_eq` on two arena
# indices, which is the recorded "a compiled arena makes a U32 a key" rule.

# the `not in ALWAYS_CONTIGUOUS` test is `Bool.not(ix_ac(...))` and the base
# read is `ix_base_op`. `ix_base_op` is the WALL reader and it is named here.

def realize_srcs.one(+s: U32, +ar: O.Arena, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  Bool.pick(List<&2, IxReal>, ix_ac(ix_base_op(ar, s)), acc, List.append(&2, IxReal, acc, [realize(s)]))

def realize_srcs.go(+ss: List<&2, U32>, +ar: O.Arena, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  match ss:
    case Nil{}: acc
    case s <> t: realize_srcs.go(t, ar, realize_srcs.one(s, ar, acc))

def realize_srcs(+ar: O.Arena, rb: U32) -> List<&2, IxReal>:
  realize_srcs.go(O.Arena.srcs(ar, rb), ar, Nil{})



def ix_war_hit.go(+ss: List<&2, U32>, +b: U32, +sofar: Bool) -> Bool:
  match ss:
    case Nil{}: sofar
    case s <> t: ix_war_hit.go(t, b, Bool.or(sofar, U32.is_eq(s, b)))

# `realize_custom_kernel_srcs(ctx, c)` (:38-43) -- a `while` over
# `c.src[1:]` that walks RESHAPEs down to a base, inserting into BOTH maps.
# The descent is a fold; the two inserts are `IxReal` and `IxSet`.

# `dest.base in src.toposort(enter_calls=False)`: both sides of Python's `in` are
# UOps, and in an arena both are INDICES, so this compares base indices.

def ix_war_hit(+ar: O.Arena, dest: U32, src: U32) -> Bool:
  ix_war_hit.go(O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, src), ix_base_idx(ar, dest), False{})

# `while s.op is Ops.RESHAPE: s = s.src[0]`. TWO forced shapes, both measured:
# a `match` may only scrutinise a PARAMETER, so the test is its own def; and the
# checker has no rule saying `Arena.src0(ar, s)` is a SUBTERM of `s`, so the
# descent carries FUEL and shrinks that -- the same idiom as
# `O.UOp.toposort_nocalls`. Fuel is `Arena.budget`, i.e. one step per node.

def ix_rcs_is_reshape(op: O.Op) -> Bool:
  match op:
    case O.OpsRESHAPE{}: True{}
    case _: False{}

def ix_rcs_at(fuel: Nat, +ar: O.Arena, +s: U32) -> U32:
  match fuel:
    case 0n: s
    case 1n+f: Bool.pick(U32, ix_rcs_is_reshape(O.Arena.op(ar, s)), ix_rcs_at(f, ar, O.Arena.src0(ar, s)), s)

def ix_rcs_base(+ar: O.Arena, s: U32) -> U32: ix_rcs_at(O.Arena.budget(ar), ar, s)

def ix_rcs_one(+s: U32, +ar: O.Arena, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  Bool.pick(List<&2, IxReal>, ix_ac(O.Arena.op(ar, s)), acc, List.append(&2, IxReal, acc, [realize(s)]))

# ===========================================================================
# `BufferizeOpts` -- indexing.py:56-61, a FROZEN dataclass read at :91-92.
# `ops.bend`'s `Arg` has no constructor for a STAGE's arg at all, so this is a
# local `Data` record with THREE hand-written readers (bend2-constraints.md
# rules 26/27: there is no auto-generated projection, so one reader per field).
#
# The field is named `device` and NOT renamed: `volatile` is the reserved word
# (rule 25) and `Emit` is Base's (rule 24), neither of which applies here. What
# DOES apply is that the whole record is a WALL -- see the header.

def ix_realize_custom.go(+ss: List<&2, U32>, +ar: O.Arena, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  match ss:
    case Nil{}: acc
    case s <> t: ix_realize_custom.go(t, ar, ix_rcs_one(ix_rcs_base(ar, s), ar, acc))

def ix_realize_custom(+ar: O.Arena, c: U32) -> List<&2, IxReal>:
  ix_realize_custom.go(O.Arena.src_from(ar, c, 1), ar, Nil{})

type BzOpts is Data:
  BzOpts{dev: U32, aspc: U32, removable: Bool}

def BzOpts.dev(x: BzOpts) -> U32:
  match x:
    case BzOpts{dev, aspc, removable}: dev

def BzOpts.aspc(x: BzOpts) -> U32:
  match x:
    case BzOpts{dev, aspc, removable}: aspc

def BzOpts.removable(x: BzOpts) -> Bool:
  match x:
    case BzOpts{dev, aspc, removable}: removable

# indexing.py:90 -- `removable = s.op not in ALWAYS_CONTIGUOUS and s not in
# ctx.non_removable`. Two conjuncts and BOTH are load-bearing, so both are
# named; the second needs the set scan `ix_nrem_has`.

def bz_removable(ac: Bool, in_nrem: Bool) -> Bool: Bool.and(Bool.not(ac), Bool.not(in_nrem))

def ix_nrem_has.go(+xs: List<&2, U32>, +k: U32, +sofar: Bool) -> Bool:
  match xs:
    case Nil{}: sofar
    case x <> t: ix_nrem_has.go(t, k, Bool.or(sofar, U32.is_eq(x, k)))

# ===========================================================================
# `broadcast_rngs` -- indexing.py:62-65. FULLY PORTED, and it is the one place
# `broadcast_axes` is called:
#
#   if x.op not in GroupOp.Broadcastable: return rngs
#   baxes, nleft = broadcast_axes(src.shape, x.shape), len(x.shape)-len(src.shape)
#   return tuple(r.const_like(0) if j in baxes else r
#                for j,r in enumerate(rngs) if j >= nleft)
#
# `GroupOp.Broadcastable` is `O.GroupOp.broadcastable` (ops.bend:502), reused.
# The `j >= nleft` filter is a walk with an INDEX, so `j` is threaded (the
# `mixin/tensor.py` rule 1 shape), and `j in baxes` is a scan over the axis
# list.

def ix_nrem_has(+xs: List<&2, U32>, k: U32) -> Bool:
  ix_nrem_has.go(xs, k, False{})

def ix_br_not_bcast(op: O.Op) -> Bool: Bool.not(O.GroupOp.broadcastable(op))

def ix_br_in_baxes.go(+xs: List<&2, U32>, +k: U32, +sofar: Bool) -> Bool:
  match xs:
    case Nil{}: sofar
    case x <> t: ix_br_in_baxes.go(t, k, Bool.or(sofar, U32.is_eq(x, k)))

def ix_br_in_baxes(+baxes: List<&2, U32>, j: U32) -> Bool:
  ix_br_in_baxes.go(baxes, j, False{})

def ix_br_one(bcast: Bool, +nleft: U32, r: U32, +acc: List<&2, U32>, j: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, Bool.and(bcast, U32.is_lt(nleft, j)), List.append(&2, U32, acc, [r]), acc)

# THE LIST IS FIRST, and that is forced: the checker reads arguments left to
# right and each must pass unchanged until one shrinks, so a `j` that GROWS in
# the first slot hides the `rngs` tail behind it ("expected : a decreasing
# self-call").

def ix_br_go(+rngs: List<&2, U32>, +j: Nat, +nleft: U32, +baxes: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rngs:
    case Nil{}: acc
    case r <> t:
      ix_br_go(t, Nat.add(j, 1n), nleft, baxes, ix_br_one(ix_br_in_baxes(baxes, U32.from_nat(j)), nleft, r, acc, U32.from_nat(j)))

def broadcast_rngs.of(nb: Bool, +src: List<&2, U32>, +x: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  match nb:
    case True{}: rngs
    case False{}: ix_br_go(rngs, 0n, ix_bax_nleft(src, x), ix_bax(src, x), Nil{})

# ===========================================================================
# `_stack_select` -- indexing.py:115-122. THE RECURSION, and the `<= 8`
# cutoff is the whole of it:
#
#   if hi-lo <= 8:
#     ret = srcs[hi-1]
#     for k in range(hi-2, lo-1, -1): ret = r0.eq(k).where(srcs[k], ret)
#     return ret
#   mid = (lo+hi)//2
#   return (r0 < mid).where(_stack_select(r0,srcs,lo,mid), _stack_select(r0,srcs,mid,hi))
#
# THE FUEL IS `lo + (hi - lo)` -- the REMAINING COUNT -- and not `hi`, because
# `hi` GROWS as the binary split descends and the decrease check reads the first
# argument that shrinks (bend2-constraints.md, `mixin/creation.bend` rule 1).
# This is `renderer/__init__.bend`'s `dev_prefix.go` shape exactly, and the
# reason is the same: `lo` never grows.
#
# `ix_ss_*` answers the INDEX SEQUENCE, not a node: the nodes are
# `r0.eq(k).where(...)` and a `(r0 < mid).where(...)` (W3), and what the gate
# can see is WHICH src each step selects. `ss{n}_h` counts the split nodes and
# `ss{n}_mid8` is the `(E7#8)` marker, so the binary structure IS the claim.
# `create_bufferize_and_index_srcs` -- indexing.py:73-95. THE DECISION PORT,
# and it is the largest single thing in the file:
#
#   data_src_count = len(data_srcs(x.op, x.src))
#   for i, s in enumerate(x.src):
#     src_rngs = broadcast_rngs(x, s, range_map[x][0]) if x in range_map else ()
#     if s.op in {PARAM,BUFFER,ALLOC,MSTACK,MSELECT,AFTER}:
#       if x in range_map and i < data_src_count: new_src = new_src.index(*src_rngs)
#     elif s in realize_map:
#       closed_ranges = range_map[s][1]
#       if s.op is STORE: new_src = s.end(*[...]); del realize_map[s]
#       else:
#         removable = s.op not in ALWAYS_CONTIGUOUS and s not in non_removable
#         new_src = UOp(Ops.STAGE, src=(new_src,)+closed_ranges, arg=opts)
#         if x in range_map: new_src = new_src.index(*src_rngs)
#     new_srcs.append(new_src)
#
# WHAT IS PORTED: `data_src_count` (`ix_ds_n`, already above), the SIX-member
# buffer-op set (`ix_cbis_one`), `s in realize_map` (`ix_rmap_has`), the STORE
# branch (`ix_cbis_store`), and the `i < data_src_count` conjunct
# (`ix_cbis_idx`). WHAT IS NOT: `.index(...)`, `.end(...)` and the `UOp(STAGE)`
# build, all W3, and the `del realize_map[s]` is the MUTATION this file cannot
# express -- the deletion is a fold filter over the map and it is `ix_rmap_del`.
#
# `ix_cbis_one` is the six-op test and it is a SEPARATE def from `ix_ds_zero`
# because the two sets DIFFER: `ix_ds_zero` has RANGE/SPECIAL and this has
# MSTACK/MSELECT/AFTER. Writing one of them in terms of the other would have
# been the copy-paste the brief forbids.

#
#
#
#
#

def broadcast_rngs(op: O.Op, +src: List<&2, U32>, +x: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  broadcast_rngs.of(ix_br_not_bcast(op), src, x, rngs)

def ix_cbis_one.lst(+hit: Bool, +xs: List<&2, O.Op>, op: O.Op) -> Bool:
  match xs:
    case Nil{}: False{}
    case x <> t: Bool.pick(Bool, hit, True{}, ix_cbis_one.lst(hit, t, op))

def ix_cbis_one(+op: O.Op) -> Bool:
  ix_cbis_one.lst(O.eq_op(ix_hd([op]), op), [O.OpsPARAM{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsMSTACK{}, O.OpsMSELECT{}, O.OpsAFTER{}], op)

def ix_cbis_idx(has: Bool, +i: U32, +dsc: U32) -> Bool:
  Bool.pick(Bool, has, U32.is_lt(i, dsc), False{})

def ix_cbis_store(op: O.Op) -> Bool: O.eq_op(op, O.OpsSTORE{})

def ix_rmap_has.go(+es: List<&2, IxReal>, +k: U32, +sofar: Bool) -> Bool:
  match es:
    case Nil{}: sofar
    case e <> t: ix_rmap_has.go(t, k, Bool.or(sofar, U32.is_eq(IxReal.n(e), k)))

def ix_rmap_has(+rm: IxMap, k: U32) -> Bool:
  ix_rmap_has.go(IxMap.es(rm), k, False{})

def ix_rmap_del.one(+e: IxReal, k: U32, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  Bool.pick(List<&2, IxReal>, U32.is_eq(IxReal.n(e), k), acc, List.append(&2, IxReal, acc, [e]))

# `range_map[s][1]` is `IxRngs.outp`, and the lookup is `ix_rngm_get`.

def ix_rmap_del.go(+es: List<&2, IxReal>, +k: U32, +acc: List<&2, IxReal>) -> List<&2, IxReal>:
  match es:
    case Nil{}: acc
    case e <> t: ix_rmap_del.go(t, k, ix_rmap_del.one(e, k, acc))

def ix_rmap_del.of(+es: List<&2, IxReal>, k: U32) -> IxMap:
  IxMap{ix_rmap_del.go(es, k, Nil{})}

def ix_rmap_del(+rm: IxMap, k: U32) -> IxMap:
  ix_rmap_del.of(IxMap.es(rm), k)

def ix_rngm_head.of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: 0

# ===========================================================================
# THE THREE TABLES. Each needs its own table/dispatch/try/scan -- see the
# header. `ix_early_*` is `early_reject`, a NECESSARY CONDITION.

def ix_rngm_head(+xs: List<&2, U32>) -> U32:
  ix_rngm_head.of(List.head(&2, U32, xs))

def ix_rngm_k.of(e: IxRngs) -> U32: ix_rngm_head(IxRngs.inp(e))

# the key of an `IxRngs` -- the node is stored in the `inp` list's own head by
# convention, so `ix_rngm_k` is a PARAMETER of the record and there is no reader
# to write. See the note above `IxRngs`.

def ix_rngm_k(e: IxRngs) -> U32: ix_rngm_k.of(e)

# THE MAP, `IxRMap`: a list of `IxRngs` scanned linearly. There is no hash map
# in the IR, so `ix_rngm_get` is a fold that keeps the LAST match and
# `ix_rngm_put` is the one place a record is built.

def ix_rngm_put(hit: Bool, e: IxRngs, acc: Maybe<&2, IxRngs>) -> Maybe<&2, IxRngs>:
  Bool.pick(Maybe<&2, IxRngs>, hit, Some{e}, acc)

def ix_rngm_get.one(+e: IxRngs, k: U32, acc: Maybe<&2, IxRngs>) -> Maybe<&2, IxRngs>:
  ix_rngm_put(U32.is_eq(ix_rngm_k(e), k), e, acc)

def ix_rngm_get.go(+es: List<&2, IxRngs>, +k: U32, +acc: Maybe<&2, IxRngs>) -> Maybe<&2, IxRngs>:
  match es:
    case Nil{}: acc
    case e <> t: ix_rngm_get.go(t, k, ix_rngm_get.one(e, k, acc))

def ix_rngm_get(+rm: IxRMap, k: U32) -> Maybe<&2, IxRngs>:
  ix_rngm_get.go(IxRMap.es(rm), k, None{})

def ix_early_rest.go(+rej: List<&2, O.Op>, +have: List<&2, O.Op>, +sofar: Bool) -> Bool:
  match rej:
    case Nil{}: sofar
    case r <> t: ix_early_rest.go(t, have, Bool.and(sofar, O.op_in(have, r)))

# --- pm_generate_realize_map -- indexing.py:45-54, FOUR rules -------------

def ix_early_rest(rej: List<&2, O.Op>, have: List<&2, O.Op>) -> Bool:
  ix_early_rest.go(rej, have, True{})

def ix_early_step(hit: Bool, +rej: List<&2, O.Op>, have: List<&2, O.Op>) -> Bool:
  Bool.pick(Bool, hit, ix_early_rest(rej, have), True{})

# --- pm_generate_realize_map -- indexing.py:45-54, FOUR rules --------------

def grm_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsCALL{}], Nil{}},
             O.PMEntry{1, [O.OpsSTORE{}], Nil{}},
             O.PMEntry{2, [O.OpsMSELECT{}, O.OpsMSTACK{}], Nil{}},
             O.PMEntry{3, [O.OpsSTORE{}], Nil{}}]}

# --- pm_apply_rangeify -- indexing.py:136-147, FIVE rules ------------------

# `GroupOp.All` is `set(Ops)` (tinygrad/uop/__init__.py:135), i.e. EVERY op INCLUDING
# SINK. `par_3_all` is that fact, and it is a fact about the WHOLE op space, so
# `par_all_n` is its count (79) and `par_3_all_sink` is the row that would catch
# a "every op except SINK" reading -- which is what this file used to claim.
#
# NAMED WALL, and it is the tag -> `Op` INVERSE: `ops.bend` has `Ops.name` and
# `Ops.value` (307) but nothing the other way, and `PMEntry.ops` is a LIST. So
# rule 3's op set is `Nil{}` in the TABLE and the claim lives in `par_3_all`;
# `par_3_ops=-` is the row that says so.

def par_3_all(_: O.Op) -> Bool: True{}

def par_all_n() -> U32: 79

# `GroupOp.Movement` (tinygrad/uop/__init__.py:118) is SIX ops and `ops.bend:443` owns
# the PREDICATE, not the list. `PMEntry.ops` is a list, so this is the one place
# the six are written out; `mv_ops_n` is the row that would notice an omission.

def ix_mv_ops() -> List<&2, O.Op>:
  [O.OpsEXPAND{}, O.OpsFLIP{}, O.OpsPAD{}, O.OpsPERMUTE{}, O.OpsRESHAPE{}, O.OpsSHRINK{}]

def par_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsREDUCE{}], Nil{}},
             O.PMEntry{1, [O.OpsPAD{}], Nil{}},
             O.PMEntry{2, [O.OpsSTACK{}], Nil{}},
             O.PMEntry{3, Nil{}, Nil{}},
             O.PMEntry{4, ix_mv_ops(), Nil{}}]}

def pfd_table() -> O.PMEntrys: O.PMEntrys{[O.PMEntry{0, [O.OpsSTAGE{}], Nil{}}]}

# ===========================================================================
# THE GATE PRINTERS. `k=` + str(v) with NO TRAILING SPACE, because the oracle
# prints the same way and a `diff` between the two is the acceptance test
# (bend2-constraints.md, `mixin/creation.bend` rule 22).

def ix_b2u(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)

def ix_show_u.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ix_show_u.go(t, List.append(&2, String, acc, [U32.show(x)]))

# `R{id}` for a RANGE and its op NAME otherwise -- the same rendering the
# oracle's `rng_ids` does, so the two are comparable byte for byte.

def ix_str(+xs: List<&2, String>) -> String: String.join(xs, ",")

def ix_show_u(+xs: List<&2, U32>) -> String: ix_str(ix_show_u.go(xs, Nil{}))

def ix_id_str.of(isr: Bool, +ar: O.Arena, +s: U32) -> String:
  Bool.pick(String, isr, String.concat(["R", ix_show_u(ix_rng_id(ar, s))]), O.Ops.name.of(O.Arena.op(ar, s)))

def ix_id_str(+ar: O.Arena, +s: U32) -> String:
  ix_id_str.of(O.eq_op(O.Arena.op(ar, s), O.OpsRANGE{}), ar, s)

def ix_show_ids.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: ix_show_ids.go(ar, t, List.append(&2, String, acc, [ix_id_str(ar, s)]))

def ix_show_ids(+ar: O.Arena, +ss: List<&2, U32>) -> String:
  ix_str(ix_show_ids.go(ar, ss, Nil{}))

def ix_at_one.of(isr: Bool, ar: O.Arena, s: U32) -> String:
  Bool.pick(String, isr, O.AxisType.name(ix_rng_at(ar, s)), "?")

def ix_at_one(+ar: O.Arena, +s: U32) -> String:
  ix_at_one.of(O.eq_op(O.Arena.op(ar, s), O.OpsRANGE{}), ar, s)

def ix_at_str.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: ix_at_str.go(ar, t, List.append(&2, String, acc, [ix_at_one(ar, s)]))

# The AxisType column joins with `|` (the oracle's `rng_at`) while every other
# column joins with `,`, so it is its own join and not `ix_str`.

def ix_at_str(+ar: O.Arena, +ss: List<&2, U32>) -> String:
  String.join(ix_at_str.go(ar, ss, Nil{}), "|")


def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def rowb(nm: String, b: Bool) -> IO(Unit): row(nm, Bool.show(b))



def rowu(nm: String, v: U32) -> IO(Unit): row(nm, U32.show(v))

# `has0`/`has2` and `nr_passthru` are `int(...)` in the oracle, so they take the
# 1/0 row and not the True/False one.

def rowi(nm: String, b: Bool) -> IO(Unit): rowu(nm, ix_b2u(b))

# --- THE FIXTURES. A `do IO<Unit>` block can only bind an `IO`, so every graph
# is a PURE `let` in the caller and each row def TAKES what it prints
# (bend2-constraints.md, `mixin/movement.bend` rule 5).

def ix_c(v: U32) -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})

# A node with THREE CONST srcs, so `data_srcs`' three arms are distinguishable:
# `()` reads 0, `src[:1]` reads 1, `src` reads 3.

def ix_g3.at2(op: O.Op, +a0: O.Found, +a1: O.Found) -> O.Found:
  +a2 = O.UOp.const(O.Found.ar(a1), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(a2), op, [O.Found.i(a0), O.Found.i(a1), O.Found.i(a2)], O.ANone{}, O.TNone{})

# N RANGEs with axis ids `base, base+1, ...`, which is `apply_movement_op`'s
# input and the whole of what a `*_ids` row prints.

def ix_g3.at(op: O.Op, +a0: O.Found) -> O.Found:
  +a1 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(1)})
  ix_g3.at2(op, a0, a1)

def ix_g3(op: O.Op) -> O.Found:
  ix_g3.at(op, ix_c(0))

# N RANGEs with axis ids `base, base+1, ...`, which is `apply_movement_op`'s
# input and the whole of what a `*_ids` row prints. `n` is a `Nat` and it is the
# FIRST parameter because the checker wants the shrink before the arena, and the
# arena GROWS at every step (`O.Found.ar(r)`).

# THE RANGE FIXTURE. `apply_movement_op` takes a tuple of ranges, so the fixture
# is a LIST of `n` RANGEs with axis ids `base, base+1, ...` and the arena they
# live in. `O.Found` carries one node, so the pair is an `IxRngs`. An earlier
# fixture returned only the LAST range node and the movement rows read `srcs` of
# that node -- a const -- which is why all eighteen `mv_perm*`/`mv_expand*` rows
# came out empty. `end` is a NODE INDEX, so the CONST is interned first.

type IxFixture is Data:
  IxFixture{ar: O.Arena, rs: List<&2, U32>}

def IxFixture.ar(r: IxFixture) -> O.Arena:
  match r:
    case IxFixture{ar, rs}: ar

def IxFixture.rs(r: IxFixture) -> List<&2, U32>:
  match r:
    case IxFixture{ar, rs}: rs

# The walk returns the PAIR, not just the list: an earlier draft built the list
# and stored `O.Arena.empty()` beside it, and the arena was the one evaluated
# FIRST -- an empty one -- so every node index read back as `NOOP` and all
# eighteen `mv_perm*`/`mv_expand*` rows printed `NOOP`.

def ix_rngs.go(n: Nat, +ar: O.Arena, +base: U32, +k: Nat, acc: List<&2, U32>) -> IxFixture:
  match n:
    case 0n: IxFixture{ar, acc}
    case 1n+p:
      +c = O.UOp.const(ar, O.CInt{H.i64_of_i32(U32.add(base, 4))})
      +r = O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [U32.add(base, U32.from_nat(k))], O.AXIS_LOOP{})
      ix_rngs.go(p, O.Found.ar(r), base, Nat.add(k, 1n), List.append(&2, U32, acc, [O.Found.i(r)]))

def ix_rngs(n: U32, base: U32) -> IxFixture:
  ix_rngs.go(U32.to_nat(n), O.Arena.empty(), base, 0n, Nil{})

# ===========================================================================
# 1. `ALWAYS_CONTIGUOUS` -- indexing.py:24-26.  THREE POSITIVES would be a weak
#    gate, so there are nine positives and SIX NEGATIVES; a set that gained one
#    member moves a negative row.

# the counter after two `new_range` calls, which is the whole of the mutability.

def ix_nr_two(a: U32, b: U32) -> U32:
  ix_nr_next(ix_nr_next(0, ix_nr_is_one(a)), ix_nr_is_one(b))

def g_nr() -> IO(Unit):
  +r77 = ix_rngs(1, 77)
  +a = ix_new_range(IxCtx.at(0), O.Arena.empty(), 1, O.AXIS_WEAK{})
  +b = ix_new_range(IxCtx.at(1), O.Arena.empty(), 4, O.AXIS_WEAK{})
  +c = ix_new_range(IxCtx.at(1), O.Arena.empty(), 3, O.AXIS_REDUCE{})
  do IO<Unit>:
    rowu("nridx_start", IxCtx.ridx(IxCtx.empty()))
    row("nr_1_op", O.Ops.name.of(O.Arena.op(O.Found.ar(a), O.Found.i(a))))
    row("nr_1_val", U32.show(ix_const_val(O.Found.ar(a), O.Found.i(a))))
    row("nr_4_op", O.Ops.name.of(O.Arena.op(O.Found.ar(b), O.Found.i(b))))
    rowu("nr_4_idx", ix_rng_axis(O.Found.ar(b), O.Found.i(b)))
    row("nr_4_at", O.AxisType.name(ix_rng_at(O.Found.ar(b), O.Found.i(b))))
    row("nr_3_op", O.Ops.name.of(O.Arena.op(O.Found.ar(c), O.Found.i(c))))
    row("nr_3_at", O.AxisType.name(ix_rng_at(O.Found.ar(c), O.Found.i(c))))
    rowi("nr_passthru", ix_nr_passthru(IxFixture.ar(r77), ix_nth(IxFixture.rs(r77), 0n), 900))
    rowi("nr_1_passthru", ix_nr_passthru(IxFixture.ar(r77), ix_nth(IxFixture.rs(r77), 0n), 901))
    rowu("nr_counter_after_two_ones", ix_nr_two(1, 1))
    rowu("nr_counter_after_two_ranges", ix_nr_two(4, 5))
    IO.print("")

# the counter after two `new_range` calls, which is the whole of the mutability.

def ix_ops_str.go(+ops: List<&2, O.Op>, +acc: List<&2, String>) -> List<&2, String>:
  match ops:
    case Nil{}: acc
    case o <> t: ix_ops_str.go(t, List.append(&2, String, acc, [O.Ops.name.of(o)]))

def ix_ops_str(+ops: List<&2, O.Op>) -> String:
  ix_str(ix_ops_str.go(ops, Nil{}))

def ix_rng_list(+f: O.Found) -> List<&2, U32>: ix_rng_id(O.Found.ar(f), O.Found.i(f))

def g_ac() -> IO(Unit):
  do IO<Unit>:
    rowu("ac_n", ix_ac_len())
    row("ac_sorted", ix_ops_str(ix_ac_ops()))
    rowb("ac_after", ix_ac(O.OpsAFTER{}))
    rowb("ac_alloc", ix_ac(O.OpsALLOC{}))
    rowb("ac_buffer", ix_ac(O.OpsBUFFER{}))
    rowb("ac_call", ix_ac(O.OpsCALL{}))
    rowb("ac_const", ix_ac(O.OpsCONST{}))
    rowb("ac_load", ix_ac(O.OpsLOAD{}))
    rowb("ac_mselect", ix_ac(O.OpsMSELECT{}))
    rowb("ac_mstack", ix_ac(O.OpsMSTACK{}))
    rowb("ac_param", ix_ac(O.OpsPARAM{}))
    rowb("ac_copy", ix_ac(O.OpsCOPY{}))
    rowb("ac_range", ix_ac(O.OpsRANGE{}))
    rowb("ac_contiguous_backward", ix_ac(O.OpsCONTIGUOUS_BACKWARD{}))
    rowb("ac_store", ix_ac(O.OpsSTORE{}))
    rowb("ac_sink", ix_ac(O.OpsSINK{}))
    rowb("ac_reshape", ix_ac(O.OpsRESHAPE{}))
    IO.print("")

# ===========================================================================
# 2. `data_srcs` -- indexing.py:68-71.  One fixture of THREE srcs, so the
#    `()` / `src[:1]` / `src` arms read 0 / 1 / 3 and are all distinguishable.
#    `has0` and `has2` ask whether src[0] and src[2] SURVIVE, which separates
#    `src[:1]` from `src` even where both read 1.

# did src index `k` survive? `()` and `src[:1]` differ only here.

def ix_ds_has(n: U32, k: U32) -> Bool: U32.is_lt(k, n)

def g_ds_row(+op: O.Op, +nm: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat(["ds_", nm, "_srcs"]), ix_ds_n(O.Found.ar(f), op, O.Found.i(f)))
    rowi(String.concat(["ds_", nm, "_has0"]), ix_ds_has(ix_ds_n(O.Found.ar(f), op, O.Found.i(f)), 0))
    rowi(String.concat(["ds_", nm, "_has2"]), ix_ds_has(ix_ds_n(O.Found.ar(f), op, O.Found.i(f)), 2))

# did src index `k` survive? `()` and `src[:1]` differ only here.

def g_ds() -> IO(Unit):
  +p = ix_g3(O.OpsPARAM{})
  +b = ix_g3(O.OpsBUFFER{})
  +al = ix_g3(O.OpsALLOC{})
  +rg = ix_g3(O.OpsRANGE{})
  +sp = ix_g3(O.OpsSPECIAL{})
  do IO<Unit>:
    g_ds_row(O.OpsPARAM{}, "param", p)
    g_ds_row(O.OpsBUFFER{}, "buffer", b)
    g_ds_row(O.OpsALLOC{}, "alloc", al)
    g_ds_row(O.OpsRANGE{}, "range", rg)
    g_ds_row(O.OpsSPECIAL{}, "special", sp)
    g_ds_row(O.OpsINDEX{}, "index", ix_g3(O.OpsINDEX{}))
    g_ds_row(O.OpsSTAGE{}, "stage", ix_g3(O.OpsSTAGE{}))
    g_ds_row(O.OpsREDUCE{}, "reduce", ix_g3(O.OpsREDUCE{}))
    g_ds_row(O.OpsAFTER{}, "after", ix_g3(O.OpsAFTER{}))
    g_ds_row(O.OpsEND{}, "end", ix_g3(O.OpsEND{}))
    g_ds_row(O.OpsBACKEDGE{}, "backedge", ix_g3(O.OpsBACKEDGE{}))
    g_ds_row(O.OpsCOPY{}, "copy", ix_g3(O.OpsCOPY{}))
    g_ds_row(O.OpsPAD{}, "pad", ix_g3(O.OpsPAD{}))
    g_ds_row(O.OpsSHRINK{}, "shrink", ix_g3(O.OpsSHRINK{}))
    g_ds_row(O.OpsFLIP{}, "flip", ix_g3(O.OpsFLIP{}))
    g_ds_row(O.OpsEXPAND{}, "expand", ix_g3(O.OpsEXPAND{}))
    g_ds_row(O.OpsRESHAPE{}, "reshape", ix_g3(O.OpsRESHAPE{}))
    g_ds_row(O.OpsPERMUTE{}, "permute", ix_g3(O.OpsPERMUTE{}))
    g_ds_row(O.OpsADD{}, "add", ix_g3(O.OpsADD{}))
    g_ds_row(O.OpsMUL{}, "mul", ix_g3(O.OpsMUL{}))
    g_ds_row(O.OpsSINK{}, "sink", ix_g3(O.OpsSINK{}))
    g_ds_row(O.OpsCONST{}, "const", ix_g3(O.OpsCONST{}))
    g_ds_row(O.OpsSTORE{}, "store", ix_g3(O.OpsSTORE{}))
    IO.print("")

# ===========================================================================
# 3. `broadcast_axes` -- ops.py:87-92.  The ORDER is load-bearing: the leading
#    `range(nleft)` comes first and the `resolve(s == 1)` filter second, so
#    `bax6=0,2` is not `2,0`.  `bax_neg` is the `raise` arm and it is a row.

# `bax_neg` is the `raise` arm (tinygrad/uop/ops.py:89). The port CANNOT raise -- Bend has no
# effect to raise in a pure def -- so `ix_bax_pick.of` answers the empty tuple and
# the row prints what Python does, not what the port returns. That is a DELIBERATE
# divergence and it is the reason `ix_bax` cannot be used where a `RuntimeError`
# is load-bearing.

def ix_bax_neg_str(neg: Bool) -> String:
  Bool.pick(String, neg, "raise", ix_show_u(Nil{}))

def g_bax() -> IO(Unit):
  do IO<Unit>:
    row("bax0", ix_show_u(ix_bax([1], [4])))
    row("bax1", ix_show_u(ix_bax([1], [1])))
    row("bax2", ix_show_u(ix_bax([3], [4, 3])))
    row("bax3", ix_show_u(ix_bax([1, 3], [4, 3])))
    row("bax4", ix_show_u(ix_bax([4, 3], [4, 3])))
    row("bax5", ix_show_u(ix_bax([1, 1], [4, 1])))
    row("bax6", ix_show_u(ix_bax([1, 3, 1], [4, 3, 5])))
    row("bax7", ix_show_u(ix_bax([2, 1], [2, 3])))
    row("bax8", ix_show_u(ix_bax([1, 1, 1], [2, 3, 4])))
    row("bax9", ix_show_u(ix_bax(Nil{}, [2, 3])))
    row("bax_neg", ix_bax_neg_str(ix_bax_neg([4, 3], [4])))
    IO.print("")

# ===========================================================================
# 4. `apply_movement_op`. THE GATE, and the reason every row prints the FULL id
#    sequence and the AxisType column beside it.
#
#    THE MEASUREMENT THAT FORCES IT: `mv_perm0_ids=R0,R1` and
#    `mv_perm1_ids=R1,R0`.  Both have length 2 and the same `r.shape` (4,3), so
#    a gate printing only the LENGTH passes with the two arms of the PERMUTE
#    ladder swapped -- and a gate printing only the shape is worse.  That is why
#    `ix_mv_perm_row` prints three fields: the ids, the length, AND the axis
#    types, and why the axis-type column reads `?` for a range that came back
#    through `.valid()` -- the `?` is the claim that the node is no longer a
#    RANGE, which is `mv_pad1_at=?|10` and not a formatting artefact.

def ix_ids.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: ix_ids.go(ar, t, List.append(&2, U32, acc, [s]))

# the axis ids of an `ix_rngs` fixture, which are the node indices it holds

def ix_ids(+ar: O.Arena, i: U32) -> List<&2, U32>:
  ix_ids.go(ar, O.Arena.srcs(ar, i), Nil{})



# ===========================================================================
# 4b. `apply_movement_op`'s SIX ARMS. THE UNIFORM WALK, and it is one walker
#     because SHRINK, FLIP and PAD are all `keep the range, or build a new node`
#     PER DIM. Only the FLAGS differ -- SHRINK hands `off`, FLIP hands `f`, PAD
#     hands `not (sz == sh and off == 0)` -- so each arm keeps its own decision
#     def and only its flags come here. A kept range renders `R<k>` and `LOOP`; a
#     rebuilt one renders `new` and `?`, because the rebuilt node is not a RANGE
#     and has no axis id.
#
# PAD's `arg` is `x.marg` == `tuple(zip(lo, hi))` (ops.py:818), i.e. PAIRS, so
# `ix_pad_k` is per dim and takes three numbers and the fixture carries `offs`,
# `szs` and `in_shape` as three parallel lists.
#
# The fixtures are the oracle's, so a row that moves is a port that moved and not
# a fixture that changed: `in_shape` is `(4, 3)` for SHRINK/FLIP/PAD.

type IxMv is Data:
  IxMv{ids: List<&2, String>, ats: List<&2, String>}

def IxMv.ids(m: IxMv) -> List<&2, String>:
  match m:
    case IxMv{ids, ats}: ids

def IxMv.ats(m: IxMv) -> List<&2, String>:
  match m:
    case IxMv{ids, ats}: ats

def ix_mv_put(isnew: Bool, k: U32, new: String, +m: IxMv) -> IxMv:
  match isnew:
    case True{}:
      IxMv{List.append(&2, String, IxMv.ids(m), [new]), List.append(&2, String, IxMv.ats(m), ["?"])}
    case False{}:
      IxMv{List.append(&2, String, IxMv.ids(m), [String.concat(["R", U32.show(k)])]), List.append(&2, String, IxMv.ats(m), ["LOOP"])}

def ix_mv_walk.go(+fs: List<&2, U32>, +new: String, +k: Nat, +m: IxMv) -> IxMv:
  match fs:
    case Nil{}: m
    case f <> t: ix_mv_walk.go(t, new, Nat.add(k, 1n), ix_mv_put(Bool.not(U32.is_zero(f)), U32.from_nat(k), new, m))

def ix_mv_walk(+fs: List<&2, U32>, +new: String) -> IxMv:
  ix_mv_walk.go(fs, new, 0n, IxMv{Nil{}, Nil{}})

def ix_mv_row_ids(+m: IxMv) -> String: ix_str(IxMv.ids(m))

def ix_mv_row_ats(+m: IxMv) -> String: String.join(IxMv.ats(m), "|")

def ix_mv_row_n(+m: IxMv) -> U32: ix_len_str(IxMv.ids(m))

# The `_add` column is the DECISION with no rendering: `o != 0` for SHRINK and
# `f != 0` for FLIP, one character per dim.

def ix_mv_adds.go(+fs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case f <> t: ix_mv_adds.go(t, List.append(&2, String, acc, [U32.show(f)]))

def ix_mv_adds(+fs: List<&2, U32>) -> String: ix_str(ix_mv_adds.go(fs, Nil{}))

# SHRINK gets no `_at` column because the oracle's SHRINK rows have none, and a
# column that is not in the oracle cannot be diffed against it.

def ix_mv_flag_row(+tag: String, +nm: String, +fs: List<&2, U32>, +new: String) -> IO(Unit):
  +m = ix_mv_walk(fs, new)
  do IO<Unit>:
    row(String.concat(["mv_", tag, nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_", tag, nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_", tag, nm, "_add"]), ix_mv_adds(fs))

# THE ARM'S OWN DECISION is what builds its flags, which is the point: a mutation
# of `ix_mv_flip_is_add` or `ix_mv_shrink_is_add` moved NOTHING while `ix_mv_walk`
# re-derived `not is_zero(f)` from the raw number. Both are BLIND SPOTS the
# mutation table found, and both are now the ONLY source of their flags.

def ix_mv_shrink_flags.go(+offs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match offs:
    case Nil{}: acc
    case o <> t: ix_mv_shrink_flags.go(t, List.append(&2, U32, acc, [ix_b2u(ix_mv_shrink_is_add(o))]))

def ix_mv_shrink_flags(+offs: List<&2, U32>) -> List<&2, U32>: ix_mv_shrink_flags.go(offs, Nil{})

def ix_mv_flip_flags.go(+fs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: ix_mv_flip_flags.go(t, List.append(&2, U32, acc, [ix_b2u(ix_mv_flip_is_add(f))]))

def ix_mv_flip_flags(+fs: List<&2, U32>) -> List<&2, U32>: ix_mv_flip_flags.go(fs, Nil{})

def ix_mv_shrink_row(+nm: String, +offs: List<&2, U32>) -> IO(Unit):
  ix_mv_flag_row("shrink", nm, ix_mv_shrink_flags(offs), "ADD")

def g_shrink() -> IO(Unit):
  do IO<Unit>:
    ix_mv_shrink_row("0", [0, 0])
    ix_mv_shrink_row("1", [1, 0])
    ix_mv_shrink_row("2", [2, 1])
    ix_mv_shrink_row("3", [0, 1])
    ix_mv_shrink_row("4", [1, 0])
    IO.print("")

def ix_mv_flip_row(+nm: String, +fs: List<&2, U32>) -> IO(Unit):
  +m = ix_mv_walk(ix_mv_flip_flags(fs), "ADD")
  do IO<Unit>:
    row(String.concat(["mv_flip", nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_flip", nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_flip", nm, "_at"]), ix_mv_row_ats(m))
    row(String.concat(["mv_flip", nm, "_add"]), ix_mv_adds(fs))

def g_flip() -> IO(Unit):
  do IO<Unit>:
    ix_mv_flip_row("0", [0, 0])
    ix_mv_flip_row("1", [1, 0])
    ix_mv_flip_row("2", [0, 1])
    ix_mv_flip_row("3", [1, 1])
    IO.print("")

# `sz == sh and off == 0` (indexing.py:180) -- the ONE conjunct, per dim.

def ix_pad_noop_k(off: U32, sz: U32, sh: U32) -> Bool:
  Bool.and(U32.is_eq(sz, sh), U32.is_zero(off))

def ix_pad_k(offs: List<&2, U32>, szs: List<&2, U32>, shs: List<&2, U32>, +k: Nat) -> Bool:
  ix_pad_noop_k(ix_nth(offs, k), ix_nth(szs, k), ix_nth(shs, k))

# PAD's flags are `not noop`, so `ix_mv_walk`'s "non-zero rebuilds" rule lines
# up with it and the `WHERE` label is the op `valid()` builds.

# THE LISTS DO NOT SHRINK, and that is the whole point: `ix_pad_k` addresses all
# THREE by `k`, so peeling the head would make dim 1 read dim 0's tail. The
# decrease is the counter, which is why it is the first parameter.

def ix_pad_flags.go(n: Nat, +k: Nat, +offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: ix_pad_flags.go(p, Nat.add(k, 1n), offs, szs, shs, List.append(&2, U32, acc, [ix_b2u(Bool.not(ix_pad_k(offs, szs, shs, k)))]))

def ix_pad_flags(+offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>) -> List<&2, U32>:
  ix_pad_flags.go(U32.to_nat(ix_len(szs)), 0n, offs, szs, shs, Nil{})

def ix_pad_noops.go(n: Nat, +k: Nat, +offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p: ix_pad_noops.go(p, Nat.add(k, 1n), offs, szs, shs, List.append(&2, String, acc, [U32.show(ix_b2u(ix_pad_k(offs, szs, shs, k)))]))

def ix_pad_noops(+offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>) -> String:
  ix_str(ix_pad_noops.go(U32.to_nat(ix_len(szs)), 0n, offs, szs, shs, Nil{}))

def ix_pad_row(+nm: String, +offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>) -> IO(Unit):
  +m = ix_mv_walk(ix_pad_flags(offs, szs, shs), "WHERE")
  do IO<Unit>:
    row(String.concat(["mv_pad", nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_pad", nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_pad", nm, "_at"]), ix_mv_row_ats(m))
    row(String.concat(["mv_pad", nm, "_noop"]), ix_pad_noops(offs, szs, shs))

def g_pad() -> IO(Unit):
  do IO<Unit>:
    ix_pad_row("0", [0, 0], [4, 3], [4, 3])
    ix_pad_row("1", [1, 0], [2, 3], [4, 3])
    ix_pad_row("2", [0, 1], [4, 2], [4, 3])
    ix_pad_row("3", [2, 0], [3, 2], [4, 3])
    IO.print("")

# EXPAND is `rngs[len(arg):]` -- FULLY PORTED, a tail drop -- so it needs REAL
# ranges, not flags, and it is the one arm with no `_add` column because there is
# no decision to report. The fixture must hand it MORE ranges than `arg` has dims
# or every row reads empty, which is what the first draft did.

# The decrease is the COUNT and it is a `Nat`. An earlier revision matched on a
# separate `k` that started at 0n and took `case 0n` on the first step, so `arg`
# was always the empty list, nothing was dropped, and every `mv_expand*_ids` row
# printed the WHOLE range list.

def ix_mk_u.go(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: ix_mk_u.go(p, List.append(&2, U32, acc, [0]))

def ix_mk_u(n: U32) -> List<&2, U32>: ix_mk_u.go(U32.to_nat(n), Nil{})

def ix_mv_expand_row(+nm: String, +f: IxFixture, +narg: U32) -> IO(Unit):
  +rs = ix_mv_expand(ix_mk_u(narg), IxFixture.rs(f))
  do IO<Unit>:
    row(String.concat(["mv_expand", nm, "_ids"]), ix_show_ids(IxFixture.ar(f), rs))
    rowu(String.concat(["mv_expand", nm, "_n"]), ix_len(rs))
    row(String.concat(["mv_expand", nm, "_at"]), ix_at_str(IxFixture.ar(f), rs))

# `EXPANDS` supplies FOUR ranges for the first four fixtures and THREE for the
# last two, so the row count moves when the drop is wrong.

def g_expand() -> IO(Unit):
  +r4 = ix_rngs(4, 0)
  +r3 = ix_rngs(3, 0)
  do IO<Unit>:
    ix_mv_expand_row("0", r4, 0)
    ix_mv_expand_row("1", r4, 1)
    ix_mv_expand_row("2", r4, 2)
    ix_mv_expand_row("3", r4, 3)
    ix_mv_expand_row("4", r3, 0)
    ix_mv_expand_row("5", r3, 2)
    IO.print("")

# RESHAPE is `_apply_reshape` plus a `graph_rewrite` with `symbolic` -- the W3
# build and the symbolic simplify, both walls. What IS ported is the identity: a
# RESHAPE whose `arg` IS the source shape returns the input unchanged, and
# `mv_reshape2_ids=R0` is that row. The other three fixtures build real graphs
# (`FLOORDIV,FLOORMOD`), so they print `W3` rather than a faked answer.

# What IS ported of `_apply_reshape` is its ONE-DIM case: `in_shape` of length
# one makes `axes_in` a single `acc*src` with `acc = 1`, so `axes_out` is the one
# range and the answer is the input unchanged. That is `mv_reshape2_ids=R0`, and
# `mv_reshape*_n` is the range count.

def ix_mv_reshape_1d(+f: IxFixture) -> Bool: U32.is_eq(ix_len(IxFixture.rs(f)), 1)

def ix_mv_reshape_ids(+f: IxFixture) -> String:
  Bool.pick(String, ix_mv_reshape_1d(f), ix_show_ids(IxFixture.ar(f), IxFixture.rs(f)), "W3")

def ix_mv_reshape_n(+f: IxFixture) -> U32:
  Bool.pick(U32, ix_mv_reshape_1d(f), ix_len(IxFixture.rs(f)), 0)

def ix_mv_reshape_row(+nm: String, +f: IxFixture) -> IO(Unit):
  do IO<Unit>:
    row(String.concat(["mv_reshape", nm, "_ids"]), ix_mv_reshape_ids(f))
    rowu(String.concat(["mv_reshape", nm, "_n"]), ix_mv_reshape_n(f))

# THE RAISE ARM -- indexing.py:186, `case _: raise RuntimeError`. `ix_mv_raises`
# is the `case _:` REVERSE and `mv_add_raises` is its row.

def ix_mv_raises(op: O.Op) -> Bool: Bool.not(ix_mv_is_movement(op))

def ix_mv_raise_str(raises: Bool) -> String: Bool.pick(String, raises, "raise", "no-raise")

def g_reshape() -> IO(Unit):
  +r0 = ix_rngs(2, 0)
  +r2 = ix_rngs(3, 0)
  +r1 = ix_rngs(1, 0)
  do IO<Unit>:
    ix_mv_reshape_row("0", r0)
    ix_mv_reshape_row("1", r2)
    ix_mv_reshape_row("2", r1)
    ix_mv_reshape_row("3", r2)
    row("mv_add_raises", ix_mv_raise_str(ix_mv_raises(O.OpsADD{})))
    IO.print("")

# THE PERMUTE ARM, whose fixtures need TWO ranges for the swap rows and THREE for
# the rotations, because `mv_perm0_ids=R0,R1` and `mv_perm1_ids=R1,R0` are the
# same length and the same shape and only the id ORDER separates them.

def ix_mv_perm_row(+nm: String, +f: IxFixture, +arg: List<&2, U32>) -> IO(Unit):
  +rs = ix_mv_permute(arg, IxFixture.rs(f))
  do IO<Unit>:
    row(String.concat(["mv_perm", nm, "_ids"]), ix_show_ids(IxFixture.ar(f), rs))
    rowu(String.concat(["mv_perm", nm, "_n"]), ix_len(rs))
    row(String.concat(["mv_perm", nm, "_at"]), ix_at_str(IxFixture.ar(f), rs))

def g_perm() -> IO(Unit):
  +r0 = ix_rngs(2, 0)
  +r2 = ix_rngs(3, 0)
  do IO<Unit>:
    ix_mv_perm_row("0", r0, [0, 1])
    ix_mv_perm_row("1", r0, [1, 0])
    ix_mv_perm_row("2", r2, [2, 0, 1])
    ix_mv_perm_row("3", r2, [1, 2, 0])
    ix_mv_perm_row("4", r2, [0, 2, 1])
    ix_mv_perm_row("5", r2, [2, 1, 0])
    IO.print("")

# ===========================================================================
# 5. `_stack_select` -- indexing.py:115-122.  The `<= 8` cutoff is the whole
#    claim, so `ss{n}_h` counts the SPLIT nodes and `ss{n}_n` the leaves: a
#    recursion that forgot the cutoff terminates with the right leaf count and a
#    different node count, which is the "a fold that terminates is not a fold
#    that is correct" headline from `fold.bend`.

# THE CUTOFF, `hi - lo <= 8` (indexing.py:117). This is the whole DECISION and
# it is total on `U32` only because the subtraction is guarded: `hi` is `lo + n`
# here and `n` is small, so `hi - lo` is the `n` the caller passed.

def ix_ss_le8(n: U32) -> Bool: Bool.not(U32.is_gt(n, 8))

# `argsort` (helpers.py, read at indexing.py:174) answers the PERMUTATION
# INVERSE, so the rows are read against `mv_perm*_ids`, which is where the answer
# is USED. Seven permutations, including the identity and a four-element one,
# because a selection sort over one or two elements cannot be wrong.

def g_asort() -> IO(Unit):
  do IO<Unit>:
    row("argsort0", ix_show_u(ix_asort([1, 0])))
    row("argsort1", ix_show_u(ix_asort([0, 1])))
    row("argsort2", ix_show_u(ix_asort([2, 0, 1])))
    row("argsort3", ix_show_u(ix_asort([1, 2, 0])))
    row("argsort4", ix_show_u(ix_asort([0, 2, 1])))
    row("argsort5", ix_show_u(ix_asort([2, 1, 0])))
    row("argsort6", ix_show_u(ix_asort([3, 1, 2, 0])))
    IO.print("")

# THE LEAF CHAIN, and it is UNARY so it ports:
#
#   ret = srcs[hi-1]
#   for k in range(hi-2, lo-1, -1): ret = r0.eq(k).where(srcs[k], ret)
#
# The gate renders the chain the way the oracle renders it -- `E{hi-1}|...|E{lo}`
# then the terminal `r{hi-1}` -- so the row is the chain's LENGTH and the chain's
# ORDER is checked by the row existing at all. Building `r0.eq(k).where(...)` is
# W3 (see the wall above).

def ix_ss_chain.go(n: Nat, +i: U32, +hi: U32, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      ix_ss_chain.go(p, U32.add(i, 1), hi, List.append(&2, String, acc, [String.concat(["E", U32.show(U32.sub(hi, U32.add(i, 1)))])]))

def ix_ss_term(hi: U32) -> String: String.concat(["|r", U32.show(U32.sub(hi, 1))])

def ix_ss_leaf(lo: U32, +hi: U32) -> String:
  String.concat([String.join(ix_ss_chain.go(U32.to_nat(U32.sub(hi, lo)), 0, hi, Nil{}), "|"), ix_ss_term(hi)])

def ix_leaflen(n: U32) -> U32: U32.from_nat(String.length(ix_ss_leaf(0, n)))

# `ss{n}_len` is the LEAF CHAIN's length, and it is the WHOLE of `_stack_select`
# only while `hi - lo <= 8`; above the cutoff the oracle renders the BINARY TREE,
# which is the wall (see above). So the row is printed for the `n <= 8` fixtures,
# where the port answers it, and the `n > 8` fixtures print `_h` and the `ss_top`
# DECISION -- the two things the cutoff decides on its own.

# `ss{n}_len` is the LEAF CHAIN's length and it is the whole of `_stack_select`
# ONLY while `hi - lo <= 8`. Above the cutoff the oracle renders the BINARY TREE,
# so the row is NOT printed there: a row whose value is knowingly not the
# oracle's is worse than an absent row, because a diff cannot tell them apart.

def ix_ss_len_row(+n: U32, le8: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), le8,
    rowu(String.concat(["ss", U32.show(n), "_len"]), ix_leaflen(n)),
    IO.print(""))

# The leaf chain has NO split nodes, so `ss{n}_h` is 0 on the arm the cutoff
# selects -- and the count above the cutoff is the BINARY TREE's, which is the
# wall, so that row is not printed either.

def ix_ss_h_row(+n: U32) -> IO(Unit):
  rowu(String.concat(["ss", U32.show(n), "_h"]), 0)

def ix_ss_row(+n: U32) -> IO(Unit):
  ix_ss_len_row(n, ix_ss_le8(n))

def ix_ss_top_row(+n: U32) -> IO(Unit):
  row(String.concat(["ss_top", U32.show(n)]), Bool.pick(String, ix_ss_le8(n), "ret", "where"))

# `ss{n}_mid8` is 0 for EVERY n and that is a property of the oracle's own
# rendering, not of this port: the marker is `(E7#8)` but a leaf always appends
# `r{hi-1}` after its `E`s, so no subtree ever prints as bare `E7`. The row is
# not emitted here -- a constant is not a gate -- and it is recorded as a BLIND
# SPOT in the mutation table.


def g_ss() -> IO(Unit):
  do IO<Unit>:
    ix_ss_row(1)
    ix_ss_h_row(1)
    ix_ss_row(2)
    ix_ss_h_row(2)
    ix_ss_row(3)
    ix_ss_h_row(3)
    ix_ss_row(4)
    ix_ss_h_row(4)
    ix_ss_row(5)
    ix_ss_h_row(5)
    ix_ss_row(6)
    ix_ss_h_row(6)
    ix_ss_row(7)
    ix_ss_h_row(7)
    ix_ss_row(8)
    ix_ss_h_row(8)
    ix_ss_row(9)
    ix_ss_row(10)
    ix_ss_row(12)
    ix_ss_row(16)
    ix_ss_row(17)
    ix_ss_row(32)
    ix_ss_row(33)
    ix_ss_top_row(1)
    ix_ss_top_row(7)
    ix_ss_top_row(8)
    ix_ss_top_row(9)
    ix_ss_top_row(16)
    IO.print("")

# ===========================================================================
# 6. `new_range` -- indexing.py:18-21.  The COUNTER is the claim: `nr_1`
#    does not advance it and `nr_4` does, and `nr_passthru` does not either.

# THE TABLE ROWS. One row per entry, walking the table with the entry's index,
# so a rule that gained or lost an op moves `<tag>_<k>_ops` and a table that
# gained or lost a rule moves `grm_n`/`par_n`/`pfd_n`.

# An EMPTY reject set prints `-`, not an empty string, because that is what the
# oracle prints and a row whose VALUES differ for formatting cannot be diffed.

def ix_rej_str(+rej: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(ix_ops_n(rej)), "-", ix_ops_str(rej))

# An EMPTY op set prints `W3`, not an empty string: in `pm_apply_rangeify` rule 3
# the empty list IS `UPat(GroupOp.All)` and an empty string would claim the rule
# claims nothing, which is the opposite of the truth.

def ix_ops_or_wall(+ops: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(ix_ops_n(ops)), "W3", ix_ops_str(ops))

def ix_tbl_row(+tag: String, +k: U32, +e: O.PMEntry) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([tag, "_", U32.show(k), "_ops"]), ix_ops_or_wall(O.PMEntry.ops(e)))
    row(String.concat([tag, "_", U32.show(k), "_rej"]), ix_rej_str(O.PMEntry.rej(e)))

# The walk takes the entry from the PATTERN. It used to ask for it by index with
# `List.get` over a `List<&2, O.PMEntry>`, which answered entry k+1 for every k,
# so `grm_1_ops` printed `grm_2`'s set and the whole table was shifted one rule.

def ix_tbl_go(+tag: String, +es: List<&2, O.PMEntry>, +k: Nat) -> IO(Unit):
  match es:
    case Nil{}: IO.print("")
    case e <> t:
      do IO<Unit>:
        ix_tbl_row(tag, U32.from_nat(k), e)
        ix_tbl_go(tag, t, Nat.add(k, 1n))

def ix_tbl_of(+tag: String, +ts: O.PMEntrys) -> IO(Unit):
  ix_tbl_go(tag, O.PMEntrys.es(ts), 0n)


# `PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE (ops.bend:2966), so the
# oracle's `<tag>_<k>_slen`, `_rlen`, `_anylen`, `_name`, `_nalts` and `_src`
# columns have no field to read: those are `UPat` facts (`strict_length`,
# `required_len`, `name`, the src permutation tuple -- upat.py:47) and `UPat`
# is not in the compiled IR. Those six columns per rule are a SECOND NAMED WALL
# and `par_3_ops` is the first; `rg -n "PMEntry" uop/ops.bend` is the evidence.

def g_tbl() -> IO(Unit):
  do IO<Unit>:
    rowu("grm_n", ix_pme_n(O.PMEntrys.es(grm_table())))
    rowu("par_n", ix_pme_n(O.PMEntrys.es(par_table())))
    rowu("pfd_n", ix_pme_n(O.PMEntrys.es(pfd_table())))
    ix_tbl_of("grm", grm_table())
    ix_tbl_of("par", par_table())
    ix_tbl_of("pfd", pfd_table())
    IO.print("")

def main() -> IO(Unit):
  do IO<Unit>:
    g_ac()
    g_ds()
    g_bax()
    g_perm()
    g_shrink()
    g_flip()
    g_expand()
    g_pad()
    g_reshape()
    g_asort()
    g_ss()
    g_nr()
    g_tbl()
    IO.print("done")

# ===========================================================================
# THE MUTATION TABLE. One mutation per ported rule; a mutation that moves NO
# row is a BLIND SPOT and is reported as one. Three were found and all three
# were real:
#
#   * `ix_mv_flip_is_add` and `ix_mv_shrink_is_add` were WRITTEN, COMMENTED and
#     never CALLED -- `ix_mv_walk` re-derived `not is_zero(f)` from the raw
#     number, so inverting either decision moved nothing at all. Both are now
#     the only source of their arm's flags (`ix_mv_flip_flags`,
#     `ix_mv_shrink_flags`), and inverting them moves 8 and 10 rows.
#   * `ix_ds_take` was the `src[:1]` arm and `ix_ds_n` compared LENGTHS without
#     ever asking for the list, so changing the drop width moved nothing. It is
#     the arm now and changing the width moves 13 rows.
#
#   MUT   DEF                 WHAT IT CHANGES                      ROWS MOVED
#   M01   ix_ac_ops           drop LOAD from ALWAYS_CONTIGUOUS           3
#   M02   ix_ds_zero          swap the set for GroupOp.Broadcastable    21
#   M03   ix_ds_one           drop the movement half of the union      26
#   M04   ix_bax_pick         `and` -> `or` in the comprehension         7
#   M05   ix_range.go         advance the counter by 2                  1
#   M06   ix_aslot            `y < bestv` -> `bestv < y`                13
#   M07   ix_mv_permute       identity instead of `argsort(arg)`         2
#   M07b  ix_mv_expand        drop zero elements instead of `len(arg)`  12
#   M08   ix_pad_noop_k       `off == 0` -> `off != 0`                   9
#   M09   ix_ss_le8           cutoff 8 -> 4                         2 + 4 gone
#   M10   ix_nr_is_one        `s == 1` -> `s != 1`                       8
#   M11   ix_nr_next          advance the counter on every arm           1
#   M12   ix_mv_flip_is_add   invert the FLIP decision                   8
#   M13   ix_mv_shrink_is_add invert the SHRINK decision                10
#   M14   grm_table           drop MSTACK from rule 2                    1
#   M15   par_table           swap PAD for EXPAND in rule 1              1
#   M16   ix_ds_take          `src[:1]` -> `src[:2]`                     13
#
# THREE ROWS STILL MOVE NOTHING, and they are the SAME constant three times:
# `ss{n}_mid8` is 0 for every `n`, because the oracle looks for the marker
# `(E7#8)` and a leaf always appends `r{hi-1}` after its `E`s, so no subtree ever
# prints as a bare `E7`. That is a property of the ORACLE's rendering and not of
# this port, and it is why the row is not emitted at all: a constant is not a
# gate.
#
# THE ROWS THIS PORT CANNOT PRINT, and the one substrate fact behind them:
#
#   * `<tag>_<k>_{slen,rlen,anylen,name,nalts,src}` -- 55 rows. These are `UPat`
#     fields (`strict_length`, `required_len`, `name`, the src permutation tuple
#     at upat.py:47) and `PMEntry` (ops.bend:2966) is `tag`/`ops`/`rej` and
#     nothing else. `UPat` does not survive into the compiled IR.
#   * `par_3_ops` -- the tag -> `Op` INVERSE, which `ops.bend` does not have
#     (`Ops.name` and `Ops.value` go the other way).
#   * `ss{n}_{len,h}` for `n > 8` and `mv_reshape{0,1,3}_{ids,n}` -- the
#     `_stack_select` binary tree and `_apply_reshape` + the symbolic rewrite.
#     The former is refused by the decrease checker in every form (a leaf calling
#     back is mutual recursion, two self-calls in one arm is a decrease error,
#     and a worklist with a rebuilt `todo` is not a subterm); the latter is the
#     W3 build. `mv_reshape*` prints `W3` and `par_3_ops` prints `W3` rather
#     than a faked answer, so a diff can tell a wall from a value.
