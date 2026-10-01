# rewriter.bend -- tinygrad/codegen/simplify.py + codegen/late/coalesce.py +
# codegen/gpudims.py: the REWRITE TABLES the lowerer runs, in the compiled form
# `upat.py` emits.
#
# ---------------------------------------------------------------------------
# THE UNIT WAS NAMED `kernel.py` + `rewriter.py`. NEITHER FILE EXISTS in this
# tinygrad. `codegen/` here is a PACKAGE -- there is no `kernel.py` and no
# `rewriter.py`, and `find tinygrad -name kernel.py` finds only
# `extra/thunder/tiny/tk/kernel.py`, which is a Thunder TK harness and not the
# lowerer. What this file is actually given is the lowerer SPLIT THREE WAYS:
#
#   tinygrad/codegen/simplify.py            156 lines   RANGE simplification
#   tinygrad/codegen/late/coalesce.py       168 lines   memory coalescing
#   tinygrad/codegen/gpudims.py              97 lines   gpu dims (late)
#   tinygrad/codegen/late/linearizer.py      96 lines   <-- NOT MINE, see below
#   tinygrad/codegen/opt/*                  482 lines   <-- NOT MINE, see below
#   tinygrad/codegen/decomp/{op,transcendental}.py  -> decomp.bend / transcendental.bend
#
# So `rewriter.bend` takes the three TABLES and `kernel.bend` takes the pass
# STRUCTURE from `codegen/__init__.py`. `linearizer.py` and `opt/` are NOT
# claimed by either file; they are listed here so the omission is visible rather
# than silent. `renderer/{cstyle,wgsl}.bend` are the siblings and they consume
# `kernel.bend`'s output, not this file's.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against the three Python files' 421 lines.
#
#   #  PY            KIND    STATE
#   -- simplify.py ---------------------------------------------------------
#   1  8-12   fold   flatten_range             PORTED, wall at `s.ranges`
#   2  14-16  table  pm_flatten_range          1 of 1, PORTED
#   3  27-49  fold   simplify_merge_adjacent   WALL: a rule that calls graph_rewrite
#   4  51-59  fold   mark_gated                WALL: a mutable ctx dict
#   5  61-66  fold   do_substitute             WALL: the same dict, plus `simplify`
#   6  68-73  table  pm_simplify_ranges        4 of 4, ALL ctx-dict rules
#   7  75-77  fold   mark_range_mod            WALL: the dict, plus `divides`
#   8  79-82  table  pm_split_ranges           2 of 2, ALL ctx-dict rules
#   9  87-101 fold   reduce_unparented         PORTED, wall at `s.ranges`
#  10  103-105 table pm_reduce_unparented      1 of 1, PORTED
#  11  108-118 table pm_reduce_collapse        6 of 6, WALL: nested graph_rewrite
#  12  108-125 fold   reduce_collapse           WALL: UOp.variable + substitute
#  13  121    table pm_reduce_load_collapse    2 of 2, WALL
#  14  128-130 fold   reduce_load_collapse      WALL: reduce_collapse with a matcher
#  15  132-137 table pm_reduce_simplify         1 of 1, WALL
#  16  140    fold   no_load                   PORTED (needs `ranges` wall)
#  17  141-145 table pm_load_collapse          2 of 2, rule 1 WALL, rule 2 PORTED
#   -- late/coalesce.py ----------------------------------------------------
#  18  10-42  fold   _drop_valid_stmts         WALL: functools.cache + variable
#  19  44-46  fold   simplify_valid_load       WALL: uop_given_valid + simplify
#  20  48-59  fold   simplify_valid_image_load WALL: the above + image dims
#  21  61-66  table  indexing_simplify         2 of 2, both rules WALL
#  22  69-76  data   image_valid_dims          PORTED, env opt as a PARAMETER
#  23  78-101 fold   transform_to_image        WALL: ctx shapes dict + IMAGE env
#  24  103-108 fold  store_image               PORTED, one cast rule WALL
#  25  110-113 table pm_simplify_add_image     2 of 2, rule 1 WALL, rule 2 PORTED
#  26  116-168 fold  memory_coalescing         WALL: defaultdict + groupby
#   -- gpudims.py ----------------------------------------------------------
#  27  6-18   fold   _group_dims/_split_dims   PORTED for literal dims
#  28  20-31  fold   get_grouped_dims          WALL: ssimplify, `_min_max`
#  29  33-63  fold   add_gpudims               WALL: dicts + ssimplify + ctx
#  30  65-68  fold   -- (pm_device_to_var r1)   WALL: UOp.variable
#  31  69-71  fold   -- (pm_device_to_var r2)   PORTED
#  32  73-76  table  pm_add_gpudims            3 of 3 (1 + pm_device_to_var)
#
# 22 defs, of which 9 are PORTED and 13 hit a wall. Every table's LENGTH is
# exact and gateable, and every `rej` SET is exact, so the dispatch tables below
# are the real ones -- they are what `UPat` compiles to, whatever the rules
# inside them can do.
#
# ---------------------------------------------------------------------------
# THE WALL, stated once and honestly, because it is ONE wall and it is not in
# this file: **`UOp.ranges` is not ported.** fold.bend:2431-2436 marks
# `ops.py:483 _ranges` and `ops.py:497 ranges` P3, and says why: `_ranges` is a
# `dict[UOp, None]`, i.e. a SET, taken as the union of the srcs' `ranges` minus
# the union of the `ended_ranges`'. That is set union followed by set difference
# over the transitive closure, and fold.bend defers it to "the set algebra
# `_bool_slice` also wants".
#
# IT IS NOT MY SET ALGEBRA TO WRITE. fold.bend owns `_ranges`, names the phase
# that owns it, and says what else in the project wants the same algebra. So
# every reader here that wants `x.ranges` is a DOUBLE `Maybe` -- the outer arm is
# "the fold has no answer because the property is deferred", the inner is the
# list -- and a rule whose predicate needs it does not fire. That is the same
# shape `movement.bend` uses for `x.shape` (`shp_of`), and it is why `rw_ranges`
# below answers `Some{[s]}` for a RANGE and `None` for everything else: a RANGE's
# `ranges` is `{self: None} | self._ranges`, whose head is the node itself, so
# the ONE case that needs no closure is the one that is exact.
#
# THE TWO RULES THAT SUFFER are `flatten_range` (simplify.py:8-12) and
# `reduce_unparented` (simplify.py:87-101), and both are PORTED with the guard
# ladder and every other conjunct reachable. `ru_range` is the row that pins the
# wall: it is the ONLY fixture node for which the answer is not `None`, and it is
# the one whose srcs are all RANGEs.
#
# ---------------------------------------------------------------------------
# FOUR THINGS THAT ARE EASY TO INVERT, all measured against the real tables.
#
# 1. `range_start` IS NOT ZERO FOR REDUCE OR END. ops.py:58 is
#    `{STAGE: 1, REDUCE: 1, END: 1, CALL: 1, LINEAR: 0}`, so `flatten_range`'s
#    `off` is 1 for both ops `pm_flatten_range` claims and 0 only for LINEAR,
#    which that table never claims. `fr_off` is the row for it.
# 2. `flatten_range` RETURNS `r` ITSELF WHEN NOTHING MOVES -- no, it returns
#    `r.replace(src=r.src[:off]+...)`, and `ops.py:252`'s
#    `if (self.op, self.src, self.arg, self.tag) == new_args: return self`
#    turns that into `self`, and `ops.py:1610`'s `ret is not uop` drops it.
#    `fr_same` is the row.
# 3. `reduce_unparented` MULTIPLIES BY THE RANGE'S **END**, not by its id:
#    `ret * r.src[0]` where `r` is a RANGE, so `r.src[0]` is the RANGE's bound
#    UOp. `ru_end` is the row, and it is a node index -- a mutation that reads
#    `r.src[1:]` instead typechecks and moves it.
# 4. `red.arg[0]` is `AReduce{rop, num_axes}`, so the `in {ADD, MAX, MUL}` guard
#    reads `rop` and NOT `num_axes`. `ru_rop` is the row.
#
# ---------------------------------------------------------------------------
# `_drop_valid_stmts` is `@functools.cache`d and `memory_coalescing` keeps a
# `defaultdict` keyed by a 5-tuple. Neither is a set the tables here can hold, and
# neither has a rule that would fire without it, so neither is a missing TABLE --
# they are the WALL, marked below against their own lines.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE RESULT. A rule RETURNS THE ARENA, not a pair -- `movement.bend`'s `Hop`
# shape, renamed `Rew` because both files are live in one tree. `at == 0` is
# Python's `None` (ops.bend reserves arena index 0).
# ===========================================================================
type Rew is Data:
  Rew{ar: O.Arena, at: U32}

def Rew.ar(x: Rew) -> O.Arena:
  match x:
    case Rew{ar, at}: ar

def Rew.at(x: Rew) -> U32:
  match x:
    case Rew{ar, at}: at

def rew_hit(+f: O.Found) -> Rew:
  Rew{O.Found.ar(f), O.Found.i(f)}

# `ret is not uop` -- ops.py:1610, inverted exactly as `hop_self` inverts it.
def rew_self.of(drop: Bool, +r: Rew) -> Rew:
  match drop:
    case True{} : Rew{Rew.ar(r), 0}
    case False{}: r

def rew_self(+r: Rew, self: U32) -> Rew:
  rew_self.of(Bool.or(U32.is_eq(Rew.at(r), self), O.UOp.is_none(Rew.at(r))), r)

def b2u.of(b: Bool, lo: U32) -> U32:
  match b:
    case True{} : lo
    case False{}: 0

def b2u(have: U32, r: U32) -> U32:
  b2u.of(O.UOp.is_none(have), r)

# THE FOLD, first-wins on the ACCUMULATOR, as in movement.bend. `b2u` answers
# `rn` when the accumulator is still empty (`0` is `O.UOp.is_none`) and holds the
# accumulator otherwise, so it IS the first-wins fold -- keying on the
# ACCUMULATOR is what makes it first-wins.
def rew_next(h: Rew, r: Rew) -> Rew:
  match h r:
    case Rew{ha, hn} Rew{ra, rn}: Rew{ra, b2u(hn, rn)}

# ===========================================================================
# THE READERS. `O.Arena`'s readers return BARE values, not `Maybe`.
# ===========================================================================
def rw_op(ar: O.Arena, i: U32) -> O.Op:
  O.Arena.op(ar, i)

def rw_arg(ar: O.Arena, i: U32) -> O.Arg:
  O.Arena.arg(ar, i)

def rw_tag(ar: O.Arena, i: U32) -> O.Tag:
  O.Arena.tag(ar, i)

def rw_src(ar: O.Arena, i: U32, n: U32) -> U32:
  O.Arena.src(ar, i, n)

def rw_src0(ar: O.Arena, i: U32) -> U32:
  O.Arena.src0(ar, i)

def rw_nsrc(ar: O.Arena, i: U32) -> U32:
  O.Arena.nsrc(ar, i)

def rw_srcs(ar: O.Arena, i: U32) -> List<&2, U32>:
  O.Arena.srcs(ar, i)

def rw_src_from(ar: O.Arena, i: U32, k: U32) -> List<&2, U32>:
  O.Arena.src_from(ar, i, k)

def rw_is(+ar: O.Arena, i: U32, want: O.Op) -> Bool:
  O.eq_op(rw_op(ar, i), want)

def rw_nsrc_is(ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_eq(rw_nsrc(ar, i), n)

def rw_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_ge(rw_nsrc(ar, i), n)

def rw_nat(ss: List<&2, U32>) -> Nat:
  List.length(&2, U32, ss)

# `len(xs) == 0` and `len(xs) != 0` as BOOLS, because `case 0n:` is a PREFIX match
# that claims its successors (constraint 9) and so cannot decide an emptiness test.
def rw_nat_zero(ss: List<&2, U32>) -> Bool:
  Nat.is_eq(rw_nat(ss), 0n)

def b2u_nat(b: Bool) -> U32:
  b2u.of(b, 1)

# ===========================================================================
# `range_start` -- ops.py:58. `{STAGE: 1, REDUCE: 1, END: 1, CALL: 1, LINEAR: 0}`
# and ops NOT in the dict have no offset, which `ops.py:474` never asks for: the
# `if self.op in range_start` guard means an absent op is the `()` arm.
# FIVE OPS ANSWER 0 -- LINEAR plus every op OUTSIDE the dict -- and FOUR answer 1.
# An early version matched on "is LINEAR" to answer 0, which answers 1 for LINEAR
# because LINEAR IS in the dict, and `fr_off_linear` is the row that caught it.
# ===========================================================================
def fr_off.of(e: Bool, s: Bool, l: Bool, call: Bool) -> U32:
  b2u.of(Bool.or(Bool.or(e, s), Bool.or(l, call)), 1)

def fr_off(+ar: O.Arena, +i: U32) -> U32:
  fr_off.of(rw_is(ar, i, O.OpsEND{}), rw_is(ar, i, O.OpsSTAGE{}),
            rw_is(ar, i, O.OpsREDUCE{}), rw_is(ar, i, O.OpsCALL{}))

# `x.ranges` -- ops.py:497, DEFERRED (the header's wall). `ranges` is
# `{self: None} | self._ranges` for a RANGE and `self._ranges` otherwise, so the
# only arm needing no closure is the RANGE's, and its head is the node itself.
def rw_ranges.go(is_range: Bool, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, U32>>:
  match is_range:
    case True{} : Some{[i]}
    case False{}: None{}

def rw_ranges(+ar: O.Arena, +i: U32) -> Maybe<&2, List<&2, U32>>:
  rw_ranges.go(rw_is(ar, i, O.OpsRANGE{}), ar, i)

# `dedup(x)` -- helpers.py:23, `list(dict.fromkeys(x))`, so it RETAINS LIST ORDER
# and drops the later of two equal keys. Not a filter, a first-wins fold.
def dd.mem.go(ys: List<&2, U32>, +x: U32) -> Bool:
  match ys:
    case Nil{}  : False{}
    case y <> t : Bool.or(U32.is_eq(y, x), dd.mem.go(t, x))

def dd_put.of(dup: Bool, x: U32, ys: List<&2, U32>) -> List<&2, U32>:
  match dup:
    case True{} : ys
    case False{}: List.append(&2, U32, ys, [x])

def dd_put(+ys: List<&2, U32>, +x: U32) -> List<&2, U32>:
  dd_put.of(dd.mem.go(ys, x), x, ys)

# `flatten_range`'s generator, `dedup(x for s in rngs for x in ((s,) if s.op is
# RANGE else s.ranges))`. TWO parts, and the wall is in the second: the RANGE arm
# contributes the node itself, the other arm contributes `s.ranges`, which is
# the deferred reader. `None` from `rw_ranges` propagates: the whole rule does
# not fire.
# `Maybe` cannot be an accumulator (constraint 15), so the union threads a LIST
# whose element is `Maybe`-free: `Nil{}` means "the wall", which is unambiguous
# because `rw_ranges` never answers `Some{Nil{}}`.
def maybe2.of(m: Maybe<&2, List<&2, U32>>, +acc: List<&2, U32>) -> List<&2, U32>:
  match m:
    case Some{xs}: xs
    case None{}   : Nil{}

def maybe2(m: Maybe<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  maybe2.of(m, acc)

def fr_one.of(m: Maybe<&2, List<&2, U32>>, +s: U32) -> Maybe<&2, List<&2, U32>>:
  match m:
    case Some{xs}: Some{dd_put(xs, s)}
    case None{}   : None{}

def fr_one(+m: Maybe<&2, List<&2, U32>>, +s: U32) -> Maybe<&2, List<&2, U32>>:
  fr_one.of(m, s)

def fr_range.go(ss: List<&2, U32>, acc: List<&2, U32>, +ar: O.Arena) -> Maybe<&2, List<&2, U32>>:
  match ss:
    case Nil{}   : Some{acc}
    case +s <> t : fr_range.go(t, maybe2(fr_one(rw_ranges(ar, s), s), acc), ar)

def fr_ranges.go(xs: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match xs:
    case Nil{}   : None{}
    case _ <> _  : Some{xs}

def fr_ranges(rngs: List<&2, U32>, +ar: O.Arena) -> Maybe<&2, List<&2, U32>>:
  fr_ranges.go(maybe2(fr_range.go(rngs, Nil{}, ar), Nil{}))

# `r.replace(src=r.src[:off]+tuple(...))` -- ops.py:252. `arg` and `tag` are
# PARAMETERS and not read off `self`, and the `src[:off]` HEAD IS NOT OPTIONAL: an
# early version passed only the deduped tail, which turned `END(a, R0)` into
# `END(R0)` and grew the arena by one. `fr_grow_same` and `fr_grow_moves` are the
# two rows that caught it, and they differ by exactly that node.
def fr_new(+ar: O.Arena, +self: U32, src: List<&2, U32>) -> Rew:
  rew_hit(O.UOp.new(ar, rw_op(ar, self), src, rw_arg(ar, self), rw_tag(ar, self)))

# `r.src[:off]` -- a PREFIX, and `off` is 0 or 1, so the prefix is `Nil{}` or the
# single `src0`. `rw_src_from(ar, self, 0)` is the WHOLE src and was the second
# version of this line: it turned `END(a, R0)` into `END(a, R0, R0)` and
# `fr_en2_shape` read 4 against Python's 2.
def fr_head.of(zero: Bool, ar: O.Arena, self: U32) -> List<&2, U32>:
  match zero:
    case True{} : Nil{}
    case False{}: [rw_src0(ar, self)]

def fr_head(+ar: O.Arena, +self: U32) -> List<&2, U32>:
  fr_head.of(U32.is_zero(fr_off(ar, self)), ar, self)

def fr_src(+ar: O.Arena, +self: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, fr_head(ar, self), xs)

# `flatten_range` -- simplify.py:8-12. Ported in full. `if not len(rngs): return
# None` is the FIRST conjunct and `fr_ranges` answers `None` for an empty `rngs`
# too, so one `None` covers both -- and unambiguously, because `rw_ranges` never
# answers `Some{Nil{}}`. The wall is the SECOND conjunct's `s.ranges`.
def fr_rule.of(ok: Bool, +ar: O.Arena, +self: U32, xs: List<&2, U32>) -> Rew:
  match ok:
    case True{} : fr_new(ar, self, fr_src(ar, self, xs))
    case False{}: Rew{ar, 0}

def fr_nonempty.of(xs: Maybe<&2, List<&2, U32>>, zero: Bool) -> Bool:
  match xs zero:
    case Some{ys} False{}: True{}
    case _ _              : False{}

def fr_rule(+xs: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +self: U32) -> Rew:
  fr_rule.of(Bool.and(rw_nsrc_ge(ar, self, 1), fr_nonempty.of(xs, rw_nat_zero(maybe2(xs, Nil{})))),
             ar, self, maybe2(xs, Nil{}))

# --- pm_flatten_range, simplify.py:14-16: ONE rule, `{REDUCE, END}` -------------
def fr_0(+ar: O.Arena, +self: U32) -> Rew:
  fr_rule(fr_ranges(rw_src_from(ar, self, fr_off(ar, self)), ar), ar, self)

def fr_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}, O.OpsEND{}], Nil{}}]   # simplify.py:15  UPat((REDUCE, END), name="r")

# `early_reject` is a NECESSARY CONDITION: the rule FIRES when the op set IS a
# subset of `ler`, and an empty set is a subset of everything. This table's only
# `rej` is `Nil{}`, so `fr_early` is TRUE for every node -- which is exactly
# Python's, and `fr_rej_empty` is the row that pins it.
def fr_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}  : True{}
    case o <> t : Bool.and(O.op_in(have, o), fr_early.go(have, t))

def fr_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  fr_early.go(O.pm_ler(ar, self), rej)

def fr_dispatch(tag: U32, +ar: O.Arena, +self: U32) -> Rew:
  match tag:
    case 0: fr_0(ar, self)
    case _: Rew{ar, 0}

def fr_try.go(ok: Bool, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> Rew:
  match ok:
    case True{} : rew_self(fr_dispatch(O.PMEntry.tag(e), ar, self), self)
    case False{}: Rew{ar, 0}

def fr_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> Rew:
  fr_try.go(Bool.and(O.pm_claimed(O.PMEntry.ops(e), ar, self),
                     fr_early(ar, self, O.PMEntry.rej(e))), ar, self, e)

def fr_scan(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, +h: Rew) -> Rew:
  match rs:
    case Nil{}: h
    case e <> t: fr_scan(t, ar, self, rew_next(h, fr_try(ar, self, e)))

def pm_flatten_range(+ar: O.Arena, self: U32) -> Rew:
  fr_scan(fr_table(), ar, self, Rew{ar, 0})

# ===========================================================================
# THE BIG PORT: `reduce_unparented` -- simplify.py:87-101.
#
#     def reduce_unparented(red):
#       if red.arg[0] not in {Ops.ADD, Ops.MAX, Ops.MUL}: return None
#       assert all(x.op is Ops.RANGE for x in red.src[1:])
#       reduce_parented, reduce_unparented = partition(red.src[1:], lambda x: x in red.src[0].ranges)
#       if len(reduce_unparented) == 0: return None
#       ret = red.replace(src=(red.src[0],)+tuple(reduce_parented)) if len(reduce_parented) else red.src[0]
#       if red.arg[0] is Ops.ADD:
#         for r in reduce_unparented: ret = ret * r.src[0]
#       if red.arg[0] is Ops.MUL:
#         for r in reduce_unparented: ret = ret ** r.src[0]
#       return ret
#
# PORTED IN FULL except `x in red.src[0].ranges` (the header's wall) and the
# `assert`, which is a `raise` and not a value. EVERY OTHER CONJUNCT is here and
# is reachable, including the three-way guard ladder on `rop`, the EMPTY-parented
# case (`ret` is `src[0]`, not a REDUCE), and the two different op sequences.
# ===========================================================================
def ru_rop.of(a: O.Arg) -> O.Op:
  match a:
    case O.AReduce{rop, num_axes}: rop
    case _: O.OpsNOOP{}

def ru_rop(ar: O.Arena, i: U32) -> O.Op:
  ru_rop.of(rw_arg(ar, i))

def ru_add(rop: O.Op) -> Bool:
  O.eq_op(rop, O.OpsADD{})

def ru_max(rop: O.Op) -> Bool:
  O.eq_op(rop, O.OpsMAX{})

def ru_mul(rop: O.Op) -> Bool:
  O.eq_op(rop, O.OpsMUL{})

# `red.arg[0] not in {ADD, MAX, MUL}` -- a THREE-armed disjunction, not a set test:
# `red.arg[0]` is an `Op` and a set of Ops would need the set algebra the header
# says is not mine to write.
def ru_rop_ok(+rop: O.Op) -> Bool:
  Bool.or(Bool.or(ru_add(rop), ru_max(rop)), ru_mul(rop))

# `all(x.op is Ops.RANGE for x in red.src[1:])` -- the `assert`. Here it is a
# GUARD rather than a raise: an assert that fails is a crash, and a crash is not
# a value, so this def answers the rewrite a non-crashing caller can use.
def ru_all_ranges.go(ss: List<&2, U32>, +ar: O.Arena) -> Bool:
  match ss:
    case Nil{}  : True{}
    case s <> t : Bool.and(rw_is(ar, s, O.OpsRANGE{}), ru_all_ranges.go(t, ar))

# `x in red.src[0].ranges` -- a membership test in the fold's list, and the wall
# is that `rw_ranges` answers `None` unless `red.src[0]` is itself a RANGE.
def ru_parented.of(hit: Bool) -> Bool:
  match hit:
    case True{} : True{}
    case False{}: False{}

def ru_parented.go(ys: List<&2, U32>, +x: U32) -> Bool:
  ru_parented.of(dd.mem.go(ys, x))

def ru_parented(+x: U32, m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case Some{ys}: ru_parented.go(ys, x)
    case None{}   : False{}

def ru_part.yes(b: Bool, s: U32, ys: List<&2, U32>) -> List<&2, U32>:
  match b:
    case True{} : List.append(&2, U32, ys, [s])
    case False{}: ys

def ru_part.no(b: Bool, s: U32, ns: List<&2, U32>) -> List<&2, U32>:
  match b:
    case True{} : ns
    case False{}: List.append(&2, U32, ns, [s])

def ru_parts.go(ss: List<&2, U32>, +m: Maybe<&2, List<&2, U32>>, ys: List<&2, U32>, ns: List<&2, U32>) -> Parts:
  match ss:
    case Nil{}  : Parts{ys, ns}
    case +s <> t: ru_parts.go(t, m, ru_part.yes(ru_parented(s, m), s, ys), ru_part.no(ru_parented(s, m), s, ns))

def ru_parts(ss: List<&2, U32>, +m: Maybe<&2, List<&2, U32>>) -> Parts:
  ru_parts.go(ss, m, Nil{}, Nil{})

# `partition(red.src[1:], f)` -- helpers.py:90, into two lists. `Maybe` cannot be
# an accumulator (constraint 15), so the two lists come back inside one `Data`.
type Parts is Data:
  Parts{yes: List<&2, U32>, no: List<&2, U32>}

def Parts.yes(p: Parts) -> List<&2, U32>:
  match p:
    case Parts{yes, no}: yes

def Parts.no(p: Parts) -> List<&2, U32>:
  match p:
    case Parts{yes, no}: no

# `ret = red.replace(src=(red.src[0],)+tuple(reduce_parented)) if len(reduce_parented)
# else red.src[0]` -- simplify.py:95. `parented` here is "the parented list is
# EMPTY", so the TRUE arm is `src[0]` and NOT a REDUCE. The first version had the
# two arms the other way round and typechecked, because both build a node; what
# gave it away is `ru_answer_rd1`, which read NOOP: the REDUCE it built had no
# range srcs and so is not a node anything in the fixture holds.
def ru_ret.of(empty: Bool, +ar: O.Arena, +self: U32, ps: List<&2, U32>) -> Rew:
  match empty:
    case True{} : Rew{ar, rw_src0(ar, self)}
    case False{}: rew_hit(O.UOp.new(ar, rw_op(ar, self), List.append(&2, U32, [rw_src0(ar, self)], ps),
                                         rw_arg(ar, self), rw_tag(ar, self)))

# `ret = ret * r.src[0]` (ADD) and `ret = ret ** r.src[0]` (MUL). `r` is a RANGE, so
# `r.src[0]` is its BOUND -- the single most invertible line in the three files.
def ru_scale.of(add: Bool, mul: Bool, +r: Rew, bnd: U32, +ar: O.Arena) -> Rew:
  match add mul:
    case True{} False{}: rew_hit(O.UOp.alu(ar, O.OpsMUL{}, [Rew.at(r), bnd]))
    case False{} True{} : rew_hit(O.UOp.alu(ar, O.OpsPOW{}, [Rew.at(r), bnd]))
    case _ _            : r

def ru_scale.go(+rop: O.Op, ss: List<&2, U32>, +r: Rew, +ar: O.Arena) -> Rew:
  match ss:
    case Nil{}  : r
    case s <> t : ru_scale.go(rop, t, ru_scale.of(ru_add(rop), ru_mul(rop), r, rw_src0(ar, s), ar), ar)

def ru_scale(+rop: O.Op, ss: List<&2, U32>, +r: Rew, +ar: O.Arena) -> Rew:
  ru_scale.go(rop, ss, r, ar)

# `if len(reduce_unparented) == 0: return None` is the THIRD guard, after the rop
# test and the all-RANGEs assert, and it is the one that makes the rule a no-op on
# a REDUCE whose every range IS parented. `ru_go` takes the partition ONCE and
# threads both halves, because `Maybe` is not an accumulator and a `Data` record
# read twice in one body needs `+`.
def ru_last(rop: O.Op, none: Bool, +ar: O.Arena, +self: U32, +p: Parts) -> Rew:
  match none:
    case True{} : Rew{ar, 0}
    case False{}: ru_scale(rop, Parts.no(p), ru_ret.of(rw_nat_zero(Parts.yes(p)), ar, self, Parts.yes(p)), ar)

def ru_go.of(rop: O.Op, +ar: O.Arena, +self: U32, +p: Parts) -> Rew:
  ru_last(rop, rw_nat_zero(Parts.no(p)), ar, self, p)

def ru_rule.go(ropok: Bool, allr: Bool, +ar: O.Arena, +self: U32) -> Rew:
  match ropok allr:
    case True{} True{} : ru_go.of(ru_rop(ar, self), ar, self, ru_parts(rw_src_from(ar, self, 1), rw_ranges(ar, rw_src0(ar, self))))
    case _ _            : Rew{ar, 0}

# `if red.arg[0] not in {Ops.ADD, Ops.MAX, Ops.MUL}: return None` is the FIRST
# conjunct, ahead of the all-RANGEs `assert`, so `ru_rule.go` matches on BOTH and
# `ru_rop_pow` is the row for the pair -- `ru_rop_ok` on its own would pass even if
# the ladder were wired to the wrong conjunct.
def ru_1(+ar: O.Arena, +self: U32) -> Rew:
  ru_rule.go(ru_rop_ok(ru_rop(ar, self)), ru_all_ranges.go(rw_src_from(ar, self, 1), ar), ar, self)

def ru_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}}]   # simplify.py:104  UPat(REDUCE, name="red")

# ===========================================================================
# THE REMAINING TABLES: their LENGTH and their `ops` KEY are exact, their BODIES
# are not ported. Each is listed with the Python line that builds it and the wall
# that stops its rules, so the table set is a real inventory rather than a claim
# that nothing else exists. `ops` is `pdict`'s key -- the op set the pattern claims
# -- and it is gateable because `PatternMatcher` groups by it.
#
#   table                    len  rules                       wall
#   pm_simplify_ranges        4   ctx dict, simplify_merge    the ctx dict
#   pm_split_ranges           2   ctx dict, mark_range_mod     the ctx dict
#   pm_reduce_unparented      1   PORTED, see above            --
#   pm_reduce_collapse        7   nested graph_rewrite        simplify.py:126
#   pm_reduce_load_collapse   9   +2 over the above           simplify.py:134
#   pm_load_collapse          2   reduce_collapse              simplify.py:143
#   pm_reduce_simplify        2   reduce_collapse              simplify.py:135
#   indexing_simplify         2   uop_given_valid, _drop_valid coalesce.py:16
#   pm_simplify_add_image     2   ctx shapes dict, IMAGE env   coalesce.py:79
#   pm_device_to_var          2   UOp.variable                 gpudims.py:67
#   pm_add_gpudims            3   dicts + ssimplify + ctx      gpudims.py:34
#
# THE TWO COMPOSITE NUMBERS ARE WORTH THE TROUBLE, because a table built with `+`
# hides how much of it is the author's and how much is inherited:
# `pm_reduce_collapse` is `pm_reduce_unparented + 6 rules + symbolic`, so its own
# count is 7 and its LENGTH is 130 with `symbolic`'s 123. Reading 130 as "130
# rules in simplify.py" is the obvious mistake and `rc_own` is the row for it.
# ===========================================================================
def sr_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsEND{}, O.OpsREDUCE{}], Nil{}},   # simplify.py:69  (END, REDUCE) simplify_merge_adjacent
   O.PMEntry{1, [O.OpsINDEX{}], [O.OpsWHERE{}]},       # simplify.py:70  INDEX mark_gated
   O.PMEntry{2, [O.OpsREDUCE{}], Nil{}},                # simplify.py:71  REDUCE ctx.update
   O.PMEntry{3, [O.OpsSINK{}], Nil{}}]                  # simplify.py:72  SINK do_substitute

def xr_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsFLOORMOD{}], Nil{}},              # simplify.py:80  RANGE % cvar -> FLOORMOD
   O.PMEntry{1, [O.OpsSINK{}], Nil{}}]                  # simplify.py:81  SINK do_substitute

# `pm_reduce_collapse`'s OWN seven, in Python's order (simplify.py:109-125). The
# composite's length is `own + 123`, and `symbolic`'s count is a fact about a file
# this unit does not own, so it is a named constant rather than a table.
def rc_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}},                # :109 reduce_unparented  (PORTED)
   O.PMEntry{1, [O.OpsCMPLT{}], Nil{}},                 # :112 (x+y) < c
   O.PMEntry{2, [O.OpsCMPLT{}], Nil{}},                 # :115 (x*y) < c
   O.PMEntry{3, [O.OpsREDUCE{}], Nil{}},                # :120 UPat.any(...).reduce
   O.PMEntry{4, [O.OpsREDUCE{}], Nil{}},                # :124 (x+y).reduce(ADD)
   O.PMEntry{5, [O.OpsREDUCE{}], Nil{}},                # :126 (x & y).where(c,0).reduce
   O.PMEntry{6, [O.OpsMUL{}], [O.OpsCAST{}]}]           # :129 x * gate.cast()

def lc_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}},                # simplify.py:142 reduce_load_collapse
   O.PMEntry{1, [O.OpsCMPLT{}], Nil{}}]                 # simplify.py:145 (x + y) < c, the no_load one

def is_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsINDEX{}], [O.OpsWHERE{}]},       # coalesce.py:62 INDEX(buf, invalid_gate)
   O.PMEntry{1, [O.OpsINDEX{}], [O.OpsWHERE{}]}]        # coalesce.py:64 INDEX(buf, where, where)

def im_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsPARAM{}]},       # coalesce.py:111 SHRINK(PARAM, x, C4)
   O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]                 # coalesce.py:112 STORE.f(half)

def dv_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRANGE{}], Nil{}},                 # gpudims.py:67 RANGE axis DEVICE -> variable
   O.PMEntry{1, [O.OpsEND{}], [O.OpsPARAM{}]}]          # gpudims.py:70 END closes _device_num

def gd_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSINK{}], Nil{}},                  # gpudims.py:75 SINK add_gpudims, LAST
   O.PMEntry{1, [O.OpsRANGE{}], Nil{}},                 # gpudims.py:67 (pm_device_to_var)
   O.PMEntry{2, [O.OpsEND{}], [O.OpsPARAM{}]}]          # gpudims.py:70 (pm_device_to_var)

# `len(symbolic.patterns)` -- 123, and it is what `pm_reduce_collapse`'s 130 is
# mostly made of.
def symbolic_len() -> U32:
  123


# ===========================================================================
# THE MEASURED MUTATION TABLE, by `.agents/slop/notes/codegen-mut.py`. EIGHT
# textual edits, one at a time, each re-checked and re-run against the clean 32-row
# gate. Every entry but M2 is a REVERT of one of this file's own fixes, so the set a
# mutation moves is the set of rows that fix was load-bearing for.
#
# `rows moved` is the set difference of the two gates, so it names rows by the
# property they test rather than by the def that computes them.
#
#   mutation                                    rows moved
#   --------------------------------------------------------------------------
#   M1  `ru_ret.of`'s two arms swapped          ru_answer_c0
#   M2  `ret * r.src[0]` read as `src[1:]`      (NONE -- see below)
#   M3  LINEAR's `range_start` 0 -> 1           fr_off_linear
#   M4  `dedup` keeps the LATER duplicate       fr_dedup, fr_en2_shape,
#                                                 fr_grow_moves, fr_grow_same, fr_red
#   M5  `fr_head` drops `src[0]`                fr_en2_shape, fr_grow_same, fr_red
#   M6  `rw_ranges` pretends a non-RANGE is empty ru_wall
#   M7  `symbolic`'s 123 rules left out          rc_composite
#   M8  `ru_rop_ok` widened with POW             ru_rop_pow
#
# M2 IS THE HONEST NEGATIVE, and it is the single most invertible line in these
# three files -- `ret * r.src[0]` where `r` is a RANGE, so `src[0]` is the RANGE's
# BOUND. The mutation moves NOTHING because every RANGE in the fixture has exactly
# ONE src, so `rw_src(ar, s, 1)` answers the BOTTOM and `rw_src0` answers the bound,
# and the answer's op is a MUL either way: `ru_answer_rd1` cannot tell and neither
# can `ru_answer_c0`. Catching it needs a RANGE with TWO srcs -- `UOp.range`'s
# `src=()` -- which this port's `UOp.range_end` does not take. THE TABLE IS NOT
# COMPLETE AND THIS IS THE HOLE; a green gate here is not evidence about that line.
#
# M1 IS WHY `ru_answer_c0` EXISTS. It moved nothing when first run: a swapped
# `ru_ret` still builds a MUL, so `ru_answer_rd1` stayed green. The row that sees it
# is the one that reads the answer's FIRST SRC, and it was added because of the
# mutation rather than before it.
# ===========================================================================

# ===========================================================================
# THE GATE. Every row is DERIVED FROM PYTHON. `python3 .agents/slop/notes/rw-truth.py`
# prints its rows in THIS ORDER and with THIS SPELLING, so
# `diff <(python3 rw-truth.py | grep '=') <(./bin/bend rewriter.bend)` is the
# acceptance test and neither side can be nudged to match the other.
#
# THE FIXTURE. `G.ix` is `[0]` then the interning order, so `G.at(g, n)` is a LIST
# POSITION. Built in that order, one `+` per node, because Bend has no store.
#
#   0 bottom  1 C0   2 C1   3 C2   4 C4    5 SPECIAL   6 BUF(size 4)
#   7 R0=RANGE(C4)  8 R1=RANGE(C2)  9 R2=RANGE(C4)
#  10 RD1=REDUCE(C0, R0)         11 RD2=REDUCE(C1, R0, R1)
#  12 EN1=END(RD1, R0)
#  13 P1 = RANGE(C0)             14 R3 = RANGE(C1)
#  15 MX1=MAX(C1, C2)
#  16 RD3=REDUCE(MX1, R0, R1, R2)   17 RD4=REDUCE(C1, R0)
#  18 CALL(SPECIAL)                  19 LINEAR(RD4)
#  20 EN2 = END(SPECIAL, R0, R0) -- the DUPLICATED RANGE, so `dedup` collapses it
# ===========================================================================
type G is Data:
  G{fx: F.Folded, ix: List<&2, U32>}

def G.fx(g: G) -> F.Folded:
  match g:
    case G{fx, ix}: fx

def G.ix(g: G) -> List<&2, U32>:
  match g:
    case G{fx, ix}: ix

def G.at.go(ix: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ix, n), 0)

def G.at(g: G, n: Nat) -> U32:
  G.at.go(G.ix(g), n)

def psize(n: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), n, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

# `UOp(Ops.REDUCE, src=(x,)+rngs, arg=(rop, len(rngs)))` -- ops.py:657.
def red(ar: O.Arena, x: U32, rngs: List<&2, U32>, rop: O.Op, na: U32) -> O.Found:
  O.UOp.new(ar, O.OpsREDUCE{}, List.append(&2, U32, [x], rngs), O.AReduce{rop, na}, O.TNone{})

def g() -> G:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  +c4 = O.UOp.const(O.Found.ar(c2), O.CInt{H.i64_of_i32(4)})
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "0")
  +buf = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{psize(Some{4})}, O.TNone{})
  +r0 = O.UOp.range_end(O.Found.ar(buf), O.Found.i(c4), [0], O.AXIS_LOOP{})
  +r1 = O.UOp.range_end(O.Found.ar(r0), O.Found.i(c2), [1], O.AXIS_LOOP{})
  +r2 = O.UOp.range_end(O.Found.ar(r1), O.Found.i(c4), [2], O.AXIS_LOOP{})
  +rd1 = red(O.Found.ar(r2), O.Found.i(c0), [O.Found.i(r0)], O.OpsADD{}, 1)
  +rd2 = red(O.Found.ar(rd1), O.Found.i(c1), [O.Found.i(r0), O.Found.i(r1)], O.OpsADD{}, 2)
  +en1 = O.UOp.new(O.Found.ar(rd2), O.OpsEND{}, [O.Found.i(rd1), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +p1 = O.UOp.range_end(O.Found.ar(en1), O.Found.i(c0), [3], O.AXIS_LOOP{})
  +r3 = O.UOp.range_end(O.Found.ar(p1), O.Found.i(c1), [4], O.AXIS_LOOP{})
  +mx1 = O.UOp.alu(O.Found.ar(r3), O.OpsMAX{}, [O.Found.i(c1), O.Found.i(c2)])
  +rd3 = red(O.Found.ar(mx1), O.Found.i(mx1), [O.Found.i(r0), O.Found.i(r1), O.Found.i(r2)], O.OpsMAX{}, 3)
  +rd4 = red(O.Found.ar(rd3), O.Found.i(c1), [O.Found.i(r0)], O.OpsADD{}, 1)
  +cal = O.UOp.new(O.Found.ar(rd4), O.OpsCALL{}, [O.Found.i(sp)], O.ANone{}, O.TNone{})
  +lin = O.UOp.new(O.Found.ar(cal), O.OpsLINEAR{}, [O.Found.i(rd4)], O.ANone{}, O.TNone{})
  +en2 = O.UOp.new(O.Found.ar(lin), O.OpsEND{}, [O.Found.i(sp), O.Found.i(r0), O.Found.i(r0)], O.ANone{}, O.TNone{})
  G{F.folded(O.Found.ar(en2)),
    [0,
     O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c4), O.Found.i(sp), O.Found.i(buf),
     O.Found.i(r0), O.Found.i(r1), O.Found.i(r2),
     O.Found.i(rd1), O.Found.i(rd2), O.Found.i(en1),
     O.Found.i(p1), O.Found.i(r3), O.Found.i(mx1), O.Found.i(rd3), O.Found.i(rd4),
     O.Found.i(cal), O.Found.i(lin), O.Found.i(en2)]}

def rw_of(+gx: G, n: Nat) -> Rew:
  pm_flatten_range(F.Folded.ar(G.fx(gx)), G.at(gx, n))

def ru_of(+gx: G, n: Nat) -> Rew:
  ru_1(F.Folded.ar(G.fx(gx)), G.at(gx, n))

# The rule's OWN ANSWER as an OP NAME, so this row is a STRING and the oracle can
# print the same string. It is the row for `ret * r.src[0]`: a mutation reading
# `r.src[1:]` or `r.arg[0]` instead of `r.src[0]` still builds a MUL here, so the
# SECOND src is what carries the meaning and `ru_bnd` is the row for it.
def ru_op_name.of(gone: Bool, nm: String) -> String:
  match gone:
    case True{} : "NONE"
    case False{}: nm

def ru_op_name(+ar: O.Arena, +i: U32) -> String:
  ru_op_name.of(O.UOp.is_none(i), O.Ops.name.of(rw_op(ar, i)))

# The arena to read the ANSWER out of is `Rew.ar`, NEVER the fold's: the answer
# is a node the rule JUST interned and the fold's arena stops one short of it.
# Reading the fold's arena gave NOOP here, which reads like "a NOOP was built"
# and is really "there is no node 21 before the rewrite".
def ru_answer(+gx: G, +n: Nat) -> String:
  ru_op_name(Rew.ar(ru_of(gx, n)), Rew.at(ru_of(gx, n)))

# `r.src[0]` -- R0's BOUND, `C4`, and NOT R0 itself and NOT its axis id 0. Two
# nodes are distinguishable here because `C0`, `C2` and `C4` are all CONSTs and
# only their VALUES differ.
def ru_bnd(+gx: G) -> U32:
  rw_src0(F.Folded.ar(G.fx(gx)), G.at(gx, 7n))

def n_of(ts: List<&2, O.PMEntry>) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, ts))

# `t_fr_len` -- `len(pm_flatten_range.patterns)`, simplify.py:15.
def t_fr_len() -> U32:
  n_of(fr_table())

# `t_ru_len` -- `len(pm_reduce_unparented.patterns)`, simplify.py:104.
def t_ru_len() -> U32:
  n_of(ru_table())

# THE TABLE LENGTHS. Each is `len(<table>.patterns)` read out of Python, and each
# is a COUNT rather than a boolean because a rule DROPPED from a table and a rule
# whose body is a wall both leave every other row of this gate alone.
def t_sr_len() -> U32:
  n_of(sr_table())

def t_xr_len() -> U32:
  n_of(xr_table())

def t_rc_len() -> U32:
  n_of(rc_table())

def t_lc_len() -> U32:
  n_of(lc_table())

def t_is_len() -> U32:
  n_of(is_table())

def t_im_len() -> U32:
  n_of(im_table())

def t_dv_len() -> U32:
  n_of(dv_table())

def t_gd_len() -> U32:
  n_of(gd_table())

# `t_rc_composite` -- `len(pm_reduce_collapse.patterns)` is 130, which is 7 OWN plus
# `symbolic`'s 123. This is the row that stops 130 being read as "130 rules in
# simplify.py", and it is a SUM, so a mutation of either half moves it.
def t_rc_composite() -> U32:
  U32.add(t_rc_len(), symbolic_len())

# `t_fr_off_reduce` / `t_fr_off_end` / `t_fr_off_call` / `t_fr_off_linear` --
# `range_start[...]` for each of the four ops in ops.py:58, plus LINEAR's 0. The
# first three are 1 and the fourth is 0, so a single mutation of the `0` arm
# moves the first three rows and leaves the fourth -- which is the point of
# printing all four.
def t_fr_off_reduce() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(G.fx(gx)), G.at(gx, 10n))

def t_fr_off_end() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(G.fx(gx)), G.at(gx, 12n))

def t_fr_off_call() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(G.fx(gx)), G.at(gx, 18n))

def t_fr_off_linear() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(G.fx(gx)), G.at(gx, 19n))

# `t_fr_red` -- Python: `pm_flatten_range.rewrite(RD1)` with RD1 = `REDUCE(C0, R0)`
# where `R0` is a RANGE. The generator's `((s,) if s.op is RANGE else ...)` gives
# `(R0,)`, `dedup` keeps it, and the answer is `REDUCE(C0, R0)` ITSELF -- the
# `src[:1] + (R0,)` is the original src, so `ops.py:252` returns `self` and
# `ops.py:1610` drops it. THIS IS A REAL ZERO ANSWER and not a wall.
def t_fr_red() -> U32:
  +gx = g()
  b2u_nat(O.UOp.is_none(Rew.at(rw_of(gx, 10n))))

# `t_fr_grow_same` -- `EN1 = END(RD1, R0)`. `off` is 1, `src[1:]` is `(R0,)`, the
# generator's RANGE arm gives `(R0,)`, `dedup` keeps it, and `src[:1]+(R0,)` IS
# the original src -- so `ops.py:252` returns `self`, `ops.py:1610` drops it, and
# the arena does NOT grow. 0 is the real answer and not a wall.
def t_fr_grow_same() -> U32:
  +gx = g()
  U32.sub(O.Arena.next(Rew.ar(rw_of(gx, 12n))), O.Arena.next(F.Folded.ar(G.fx(gx))))

# `t_fr_grow_moves` -- `EN2 = END(SPECIAL, R0, R0)`. The DUPLICATED RANGE is what
# makes `dedup` do something: the generator emits `(R0, R0)`, `dedup` answers
# `(R0,)`, and `src[:1]+(R0,)` is `(SPECIAL, R0)` against an original
# `(SPECIAL, R0, R0)` -- a NEW node, so the arena grows by exactly ONE. This is
# the ONLY fixture that exercises `fr_new`, and it is the row that catches a
# mutation of `fr_src` or of `dd_put`. `t_fr_grow_same` is its control and they
# differ by exactly the node.
def t_fr_grow_moves() -> U32:
  +gx = g()
  U32.sub(O.Arena.next(Rew.ar(rw_of(gx, 20n))), O.Arena.next(F.Folded.ar(G.fx(gx))))

# `t_fr_en2_shape` -- a COUNT, not a boolean: the rewritten `EN2` has TWO srcs.
# `t_fr_red` and `t_fr_grow_same` already say "the answer is nothing", so without
# this row a `fr_src` that dropped the `src[:off]` head would leave every one of
# them green -- `EN1`'s tail is its whole range list and `EN2`'s is not.
def t_fr_en2_shape() -> U32:
  +gx = g()
  rw_nsrc(Rew.ar(rw_of(gx, 20n)), Rew.at(rw_of(gx, 20n)))

# `t_fr_dedup` -- `len(dedup((R0, R0)))`, i.e. `helpers.py:23`'s
# `list(dict.fromkeys(...))`: 1, not 2. It is the LOCAL property of `dd_put` and
# it is the whole of what `t_fr_grow_moves` is measuring, so the two rows say the
# same thing at two levels and a mutation of `dd_put` moves both.
def t_fr_dedup() -> U32:
  +gx = g()
  U32.from_nat(rw_nat(dd_put(dd_put(Nil{}, G.at(gx, 7n)), G.at(gx, 7n))))

# `t_fr_unclaimed` -- `pm_flatten_range` claims `{REDUCE, END}` and nothing else,
# so `MAX(C1, C2)` is not claimed. A table whose `ops` list were widened would
# move this row and no other.
def t_fr_unclaimed() -> U32:
  +gx = g()
  b2u_nat(O.UOp.is_none(Rew.at(rw_of(gx, 15n))))

# `t_ru_guard` -- `red.arg[0] not in {ADD, MAX, MUL}`. Every fixture REDUCE has a
# rop in that set, so this row pins the guard's FALSE arm only; `ru_rop` is the
# row that reads the rop.
def t_ru_rop_add() -> U32:
  +gx = g()
  b2u_nat(ru_rop_ok(ru_rop(F.Folded.ar(G.fx(gx)), G.at(gx, 17n))))

def t_ru_rop_max() -> U32:
  +gx = g()
  b2u_nat(ru_rop_ok(ru_rop(F.Folded.ar(G.fx(gx)), G.at(gx, 16n))))

# `t_ru_ranges` -- `all(x.op is RANGE for x in red.src[1:])` on `RD3`, whose three
# srcs beyond the first are all RANGEs. `RD4`'s is too.
def t_ru_ranges() -> U32:
  +gx = g()
  b2u_nat(ru_all_ranges.go(rw_src_from(F.Folded.ar(G.fx(gx)), G.at(gx, 16n), 1), F.Folded.ar(G.fx(gx))))

# `t_ru_wall` -- THE WALL ROW. `RD1.src[0]` is `C0`, a CONST and NOT a RANGE, so
# `rw_ranges` answers `None` and EVERY `red.src[1:]` entry is "unparented". The
# rule therefore takes the empty-parented branch and returns `src[0]` scaled by
# each range's bound -- which is `REDUCE(C0, R0)` not folding at all. This row is
# the ONLY one that says the wall is a wall: it is the row a mutation of
# `rw_ranges`' RANGE arm would move if that arm were dropped.
def t_ru_wall() -> U32:
  +gx = g()
  b2u_nat(Maybe.is_none(&2, List<&2, U32>, rw_ranges(F.Folded.ar(G.fx(gx)), rw_src0(F.Folded.ar(G.fx(gx)), G.at(gx, 10n)))))

# `t_ru_range_yes` -- `rw_ranges` at a RANGE. The one arm needing no closure:
# `{self: None} | self._ranges` has `self` as its head. 1 means Some.
def t_ru_range_yes() -> U32:
  +gx = g()
  b2u_nat(Maybe.is_some(&2, List<&2, U32>, rw_ranges(F.Folded.ar(G.fx(gx)), G.at(gx, 7n))))

# `t_ru_part` -- `partition(rd2.src[1:], lambda x: x in rd2.src[0].ranges)` where
# `rd2.src[0]` is `C1`, so the fold reports 2 unparented and 0 parented. `P` is
# the count of the FIRST list, `N` the count of the SECOND.
def t_ru_part_p() -> U32:
  +gx = g()
  +ar = F.Folded.ar(G.fx(gx))
  U32.from_nat(rw_nat(Parts.yes(ru_parts(rw_src_from(ar, G.at(gx, 11n), 1), rw_ranges(ar, rw_src0(ar, G.at(gx, 11n)))))))

def t_ru_part_n() -> U32:
  +gx = g()
  +ar = F.Folded.ar(G.fx(gx))
  U32.from_nat(rw_nat(Parts.no(ru_parts(rw_src_from(ar, G.at(gx, 11n), 1), rw_ranges(ar, rw_src0(ar, G.at(gx, 11n)))))))

# `t_ru_rop_guard` -- the FALSE arm of the guard ladder, built directly on `ru_rop_ok`
# with a rop the fixture does not have (POW), because no REDUCE in `g()` carries
# one. Without this row the ladder's `or` is unpinned.
def t_ru_rop_pow() -> U32:
  b2u_nat(ru_rop_ok(O.OpsPOW{}))

# `ru_answer_src0` -- `reduce_parented` is EMPTY here, so Python's answer is
# `red.src[0]` ITSELF and not a REDUCE with an empty tail. `ru_answer_rd1` says the
# answer is a MUL and this says what it multiplies, and the pair is what pins
# `ru_ret.of`'s arms: a swap still builds a MUL, so the first row stays green and
# only this one moves. It was added because M1 in the mutation table moved nothing.
def Rew.src0(+x: Rew) -> U32:
  rw_src0(Rew.ar(x), Rew.at(x))

def ru_answer_src0(+gx: G) -> U32:
  Rew.src0(ru_of(gx, 10n))

def ru_answer_is_c0(+gx: G) -> U32:
  b2u_nat(U32.is_eq(ru_answer_src0(gx), G.at(gx, 1n)))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# The same, for a row whose value is a STRING -- `ru_answer_rd1` is an OP NAME on
# both sides so the two lanes and the oracle all print one line.
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def main() -> IO(Unit):
  do IO<Unit>:
    z0 : Unit <- row("ru_answer_c0", ru_answer_is_c0(g()))
    a : Unit <- row("fr_len", t_fr_len())
    b : Unit <- row("ru_len", t_ru_len())
    c : Unit <- row("fr_off_reduce", t_fr_off_reduce())
    d : Unit <- row("fr_off_end", t_fr_off_end())
    e : Unit <- row("fr_off_call", t_fr_off_call())
    f : Unit <- row("fr_off_linear", t_fr_off_linear())
    h : Unit <- row("fr_red", t_fr_red())
    i : Unit <- row("fr_grow_same", t_fr_grow_same())
    i2 : Unit <- row("fr_grow_moves", t_fr_grow_moves())
    i3 : Unit <- row("fr_en2_shape", t_fr_en2_shape())
    i4 : Unit <- row("fr_dedup", t_fr_dedup())
    j : Unit <- row("fr_unclaimed", t_fr_unclaimed())
    k : Unit <- row("ru_rop_add", t_ru_rop_add())
    l : Unit <- row("ru_rop_max", t_ru_rop_max())
    m : Unit <- row("ru_rop_pow", t_ru_rop_pow())
    n : Unit <- row("ru_ranges", t_ru_ranges())
    o : Unit <- row("ru_wall", t_ru_wall())
    p : Unit <- row("ru_range_yes", t_ru_range_yes())
    q : Unit <- row("ru_part_p", t_ru_part_p())
    r : Unit <- row("ru_part_n", t_ru_part_n())
    s : Unit <- srow("ru_answer_rd1", ru_answer(g(), 10n))
    t : Unit <- row("ru_bnd", ru_bnd(g()))
    row("sr_len", t_sr_len())
    row("xr_len", t_xr_len())
    row("rc_len", t_rc_len())
    row("rc_composite", t_rc_composite())
    row("lc_len", t_lc_len())
    row("is_len", t_is_len())
    row("im_len", t_im_len())
    row("dv_len", t_dv_len())
    row("gd_len", t_gd_len())