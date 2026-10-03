# simplify.bend -- tinygrad/codegen/simplify.py: RANGE simplification, the
# pattern tables the lowerer runs over a SINK's ranges.
#
# ---------------------------------------------------------------------------
# ONE OF THREE. `codegen/rewriter.bend` was ONE file for `simplify.py` +
# `late/coalesce.py` + `gpudims.py`; the 1:1 ruling -- one `.bend` per upstream
# `.py`, AT THE SAME PATH, no merging and no prefixes standing in for a directory
# -- made it three, and this is `simplify.py`'s. The 54 rows the merged file
# printed CONCATENATE IN PYTHON'S ORDER (this file, then `late/coalesce.bend`,
# then `gpudims.bend`) to exactly those 54, and
# `.agents/slop/codegen3-gate.sh` is that invariant against the pre-split
# snapshot. The cut itself is `.agents/slop/split-codegen3.py`, which moved every
# body by LINE RANGE, so "moved verbatim" is a checkable claim and not a promise.
#
# THE SHARED SUBSTRATE IS IMPORTED, NOT COPIED. `Rew` (the rule's answer), the
# `rw_*` node readers, `rw_ranges`, `G` (the fixture's index map), `n_of` and the
# two row printers live in `codegen/rewriter.bend` and every use here is `RW.<name>`.
# A TYPE MENTION needs the alias as well as a call -- an unqualified imported
# `type` name is not in scope -- so it is `RW.Rew` and `RW.Rew.ar`, never `Rew.ar`.
# A def is in the substrate iff at least TWO of the three files used it; every
# def only this file used came here.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against simplify.py's 156 lines. Every `PY` range is
# re-derived from the file as it stands.
#
#   #  PY            KIND    STATE

#  1  8-13   fold   flatten_range             PORTED, wall at `s.ranges`
#  2  14-19  table  pm_flatten_range          1 of 1, PORTED
#  3  20     fold   count_divmod              NOT CLAIMED: one-line count helper
#  4  21-39  fold   simplify_merge_adjacent   WALL: a rule that calls graph_rewrite
#  5  40-50  fold   mark_gated                WALL: a mutable ctx dict
#  6  51-57  fold   do_substitute             WALL: the same dict, plus `simplify`
#  7  58-65  table  pm_simplify_ranges        4 of 4, ALL ctx-dict rules
#  8  66-70  fold   mark_range_mod            WALL: the dict, plus `divides`
#  9  71-78  table  pm_split_ranges           2 of 2, ALL ctx-dict rules
# 10  79-80  fold   no_range                  NOT CLAIMED: `backward_slice_with_self`
# 11  81-92  fold   reduce_unparented         PORTED, wall at `s.ranges`
# 12  93-97  table  pm_reduce_unparented      1 of 1, PORTED
# 13  98-120 table  pm_reduce_collapse        6 of 6, WALL: nested graph_rewrite
# 14  121-128 table pm_reduce_load_collapse    2 of 2, WALL
# 15  129-143 fold  reduce_collapse           WALL: UOp.variable + substitute
# 16  144-146 fold  reduce_load_collapse      WALL: reduce_collapse with a matcher
# 17  147-150 table pm_reduce_simplify        1 of 1, WALL
# 18  151    fold   no_load                   PORTED (needs `ranges` wall)
# 19  152-156 table pm_load_collapse          2 of 2, rule 1 WALL, rule 2 PORTED
#
# 19 defs. Five are wholly PORTED (1, 2, 11, 12, 18) and the rest hit a wall or
# are not claimed. Every table's LENGTH is exact and gateable, and every `rej`
# SET is exact, so the dispatch tables below are the real ones -- they are what
# `UPat` compiles to, whatever the rules inside them can do.
#
# THE WALL, and it is ONE wall and it is NOT this file's: **`UOp.ranges` is not
# ported.** `rw_ranges` is the reader, it is DEFERRED to `fold.bend`, and
# `codegen/rewriter.bend` carries the whole argument. Two rules here need it and
# both are PORTED with every other conjunct reachable: `flatten_range`
# (simplify.py:8-12) and `reduce_unparented` (simplify.py:87-101). `ru_range` is
# the row that pins the wall: it is the ONLY fixture node for which the answer is
# not `None`, and it is the one whose srcs are all RANGEs.
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
# THE NAME CORRESPONDENCE, because the tables are the whole of this file and they
# now carry UPSTREAM names: `pm_flatten_range` (simplify.py:14), `flatten_range`
# (simplify.py:8), `pm_simplify_ranges` (:58), `pm_split_ranges` (:71),
# `reduce_unparented` (:81) and `pm_reduce_unparented` (:93), `pm_reduce_collapse`
# (:98) and `pm_load_collapse` (:152) -- eight of the nineteen, and the eight that
# ARE in the file as upstream tables or rules. The merged file called them
# `fr_table`, `pm_flatten_range` (for the RULE), `sr_table`, `xr_table`, `ru_1`,
# `ru_table`, `rc_table`, `lc_table`, so this is EIGHT renames and every one of
# them is inside this file; `.agents/slop/split-codegen3.py` does them in ONE
# single-pass token rewrite and `--check` undoes them to find the original bytes.
# THE REMAING ELEVEN ARE PORT-LOCAL and the naming rule does not apply to them:
# `fr_off`, `dd_put`, `fr_new`, `fr_head`, `fr_src`, `fr_rule`, `fr_0`, `fr_early`,
# `fr_dispatch`, `fr_try`, `fr_scan` are `flatten_range`'s decomposition into the
# shapes Bend needs, and `ru_rop`, `ru_rop_ok`, `ru_all_ranges`, `ru_parented`,
# `ru_parts`, `Parts`, `ru_ret`, `ru_scale`, `ru_last`, `ru_go`, `ru_rule` are
# `reduce_unparented`'s. Upstream each of those is ONE function.
#
# ---------------------------------------------------------------------------
# THE GATE. Every row is DERIVED FROM PYTHON. `python3 .agents/slop/notes/
# rw-truth.py` prints these rows in THIS ORDER and with THIS SPELLING, so
# `diff <(python3 rw-truth.py | grep '=') <(cat simplify late/coalesce gpudims)`
# is the acceptance test and neither side can be nudged to match the other.
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

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./rewriter.bend as RW

# THE INVENTORY, def by def, against the three Python files' 430 lines. Every
# `PY` range below was RE-DERIVED from the files as they stand; the previous
# table's ranges were up to TWENTY-ONE lines high, it named two symbols that do
# not exist in `gpudims.py` at all (`add_gpudims`, `pm_add_gpudims`), it omitted
# six top-level defs, and its summary counted 22 defs over a 32-row table. The
# STATE column is the port's verdict and was not touched; the `#` column is new.
#
#   #  PY            KIND    STATE

#   -- simplify.py ---------------------------------------------------------
#   1  8-13   fold   flatten_range             PORTED, wall at `s.ranges`
#   2  14-19  table  flatten_range          1 of 1, PORTED
#   3  20     fold   count_divmod              NOT CLAIMED: one-line count helper
#   4  21-39  fold   simplify_merge_adjacent   WALL: a rule that calls graph_rewrite
#   5  40-50  fold   mark_gated                WALL: a mutable ctx dict
#   6  51-57  fold   do_substitute             WALL: the same dict, plus `simplify`
#   7  58-65  table  pm_simplify_ranges        4 of 4, ALL ctx-dict rules
#   8  66-70  fold   mark_range_mod            WALL: the dict, plus `divides`
#   9  71-78  table  pm_split_ranges           2 of 2, ALL ctx-dict rules
#  10  79-80  fold   no_range                  NOT CLAIMED: `backward_slice_with_self`
#  11  81-92  fold   reduce_unparented         PORTED, wall at `s.ranges`
#  12  93-97  table  pm_reduce_unparented      1 of 1, PORTED
#  13  98-120 table  pm_reduce_collapse        6 of 6, WALL: nested graph_rewrite
#  14  121-128 table pm_reduce_load_collapse    2 of 2, WALL
#  15  129-143 fold  reduce_collapse           WALL: UOp.variable + substitute
#  16  144-146 fold  reduce_load_collapse      WALL: reduce_collapse with a matcher
#  17  147-150 table pm_reduce_simplify        1 of 1, WALL
#  18  151    fold   no_load                   PORTED (needs `ranges` wall)
#  19  152-156 table pm_load_collapse          2 of 2, rule 1 WALL, rule 2 PORTED

# 37 rows over 35 defs (rows 34 and 35 are the two RULES of `pm_device_to_var`,
# gpudims.py:91-100, inventoried as one def). Of the 35: 9 are wholly PORTED, 18
# wholly a WALL, 3 are MIXED (a ported rule beside a walled one: rows 19, 26, 27)
# and 3 are NOT CLAIMED. Every table's LENGTH is
# exact and gateable, and every `rej` SET is exact, so the dispatch tables below
# are the real ones -- they are what `UPat` compiles to, whatever the rules
# inside them can do.

# FOUR THINGS THAT ARE EASY TO INVERT, all measured against the real tables.
#
# 1. `range_start` IS NOT ZERO FOR REDUCE OR END. ops.py:58 is
#    `{STAGE: 1, REDUCE: 1, END: 1, CALL: 1, LINEAR: 0}`, so `flatten_range`'s
#    `off` is 1 for both ops `flatten_range` claims and 0 only for LINEAR,
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

# ===========================================================================
# `range_start` -- ops.py:58. `{STAGE: 1, REDUCE: 1, END: 1, CALL: 1, LINEAR: 0}`
# and ops NOT in the dict have no offset, which `ops.py:474` never asks for: the
# `if self.op in range_start` guard means an absent op is the `()` arm.
# FIVE OPS ANSWER 0 -- LINEAR plus every op OUTSIDE the dict -- and FOUR answer 1.
# An early version matched on "is LINEAR" to answer 0, which answers 1 for LINEAR
# because LINEAR IS in the dict, and `fr_off_linear` is the row that caught it.
# ===========================================================================
def fr_off.of(e: Bool, s: Bool, l: Bool, call: Bool) -> U32:
  RW.b2u.of(Bool.or(Bool.or(e, s), Bool.or(l, call)), 1)

def fr_off(+ar: O.Arena, +i: U32) -> U32:
  fr_off.of(RW.rw_is(ar, i, O.OpsEND{}), RW.rw_is(ar, i, O.OpsSTAGE{}),
            RW.rw_is(ar, i, O.OpsREDUCE{}), RW.rw_is(ar, i, O.OpsCALL{}))

# `dedup(x)` -- tinygrad/helpers.py:23, `list(dict.fromkeys(x))`, so it RETAINS
# LIST ORDER and drops the later of two equal keys. Not a filter, a first-wins fold.
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
    case +s <> t : fr_range.go(t, maybe2(fr_one(RW.rw_ranges(ar, s), s), acc), ar)

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
def fr_new(+ar: O.Arena, +self: U32, src: List<&2, U32>) -> RW.Rew:
  RW.rew_hit(O.UOp.new(ar, RW.rw_op(ar, self), src, RW.rw_arg(ar, self), RW.rw_tag(ar, self)))

# `r.src[:off]` -- a PREFIX, and `off` is 0 or 1, so the prefix is `Nil{}` or the
# single `src0`. `rw_src_from(ar, self, 0)` is the WHOLE src and was the second
# version of this line: it turned `END(a, R0)` into `END(a, R0, R0)` and
# `fr_en2_shape` read 4 against Python's 2.
def fr_head.of(zero: Bool, ar: O.Arena, self: U32) -> List<&2, U32>:
  match zero:
    case True{} : Nil{}
    case False{}: [RW.rw_src0(ar, self)]

def fr_head(+ar: O.Arena, +self: U32) -> List<&2, U32>:
  fr_head.of(U32.is_zero(fr_off(ar, self)), ar, self)

def fr_src(+ar: O.Arena, +self: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, fr_head(ar, self), xs)

# `flatten_range` -- simplify.py:8-12. Ported in full. `if not len(rngs): return
# None` is the FIRST conjunct and `fr_ranges` answers `None` for an empty `rngs`
# too, so one `None` covers both -- and unambiguously, because `rw_ranges` never
# answers `Some{Nil{}}`. The wall is the SECOND conjunct's `s.ranges`.
def fr_rule.of(ok: Bool, +ar: O.Arena, +self: U32, xs: List<&2, U32>) -> RW.Rew:
  match ok:
    case True{} : fr_new(ar, self, fr_src(ar, self, xs))
    case False{}: RW.Rew{ar, 0}

def fr_nonempty.of(xs: Maybe<&2, List<&2, U32>>, zero: Bool) -> Bool:
  match xs zero:
    case Some{ys} False{}: True{}
    case _ _              : False{}

def fr_rule(+xs: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +self: U32) -> RW.Rew:
  fr_rule.of(Bool.and(RW.rw_nsrc_ge(ar, self, 1), fr_nonempty.of(xs, RW.rw_nat_zero(maybe2(xs, Nil{})))),
             ar, self, maybe2(xs, Nil{}))

# --- flatten_range, simplify.py:14-16: ONE rule, `{REDUCE, END}` -------------
def fr_0(+ar: O.Arena, +self: U32) -> RW.Rew:
  fr_rule(fr_ranges(RW.rw_src_from(ar, self, fr_off(ar, self)), ar), ar, self)

def pm_flatten_range() -> List<&2, O.PMEntry>:
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

def fr_dispatch(tag: U32, +ar: O.Arena, +self: U32) -> RW.Rew:
  match tag:
    case 0: fr_0(ar, self)
    case _: RW.Rew{ar, 0}

def fr_try.go(ok: Bool, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> RW.Rew:
  match ok:
    case True{} : RW.rew_self(fr_dispatch(O.PMEntry.tag(e), ar, self), self)
    case False{}: RW.Rew{ar, 0}

def fr_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> RW.Rew:
  fr_try.go(Bool.and(O.pm_claimed(O.PMEntry.ops(e), ar, self),
                     fr_early(ar, self, O.PMEntry.rej(e))), ar, self, e)

def fr_scan(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, +h: RW.Rew) -> RW.Rew:
  match rs:
    case Nil{}: h
    case e <> t: fr_scan(t, ar, self, RW.rew_next(h, fr_try(ar, self, e)))

def flatten_range(+ar: O.Arena, self: U32) -> RW.Rew:
  fr_scan(pm_flatten_range(), ar, self, RW.Rew{ar, 0})

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
  ru_rop.of(RW.rw_arg(ar, i))

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
    case s <> t : Bool.and(RW.rw_is(ar, s, O.OpsRANGE{}), ru_all_ranges.go(t, ar))

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

# `partition(red.src[1:], f)` -- tinygrad/helpers.py:90, into two lists. `Maybe` cannot be
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
# else red.src[0]` -- simplify.py:86. `parented` here is "the parented list is
# EMPTY", so the TRUE arm is `src[0]` and NOT a REDUCE. The first version had the
# two arms the other way round and typechecked, because both build a node; what
# gave it away is `ru_answer_rd1`, which read NOOP: the REDUCE it built had no
# range srcs and so is not a node anything in the fixture holds.
def ru_ret.of(empty: Bool, +ar: O.Arena, +self: U32, ps: List<&2, U32>) -> RW.Rew:
  match empty:
    case True{} : RW.Rew{ar, RW.rw_src0(ar, self)}
    case False{}: RW.rew_hit(O.UOp.new(ar, RW.rw_op(ar, self), List.append(&2, U32, [RW.rw_src0(ar, self)], ps),
                                         RW.rw_arg(ar, self), RW.rw_tag(ar, self)))

# `ret = ret * r.src[0]` (ADD) and `ret = ret ** r.src[0]` (MUL). `r` is a RANGE, so
# `r.src[0]` is its BOUND -- the single most invertible line in the three files.
def ru_scale.of(add: Bool, mul: Bool, +r: RW.Rew, bnd: U32, +ar: O.Arena) -> RW.Rew:
  match add mul:
    case True{} False{}: RW.rew_hit(O.UOp.alu(ar, O.OpsMUL{}, [RW.Rew.at(r), bnd]))
    case False{} True{} : RW.rew_hit(O.UOp.alu(ar, O.OpsPOW{}, [RW.Rew.at(r), bnd]))
    case _ _            : r

def ru_scale.go(+rop: O.Op, ss: List<&2, U32>, +r: RW.Rew, +ar: O.Arena) -> RW.Rew:
  match ss:
    case Nil{}  : r
    case s <> t : ru_scale.go(rop, t, ru_scale.of(ru_add(rop), ru_mul(rop), r, RW.rw_src0(ar, s), ar), ar)

def ru_scale(+rop: O.Op, ss: List<&2, U32>, +r: RW.Rew, +ar: O.Arena) -> RW.Rew:
  ru_scale.go(rop, ss, r, ar)

# `if len(reduce_unparented) == 0: return None` is the THIRD guard, after the rop
# test and the all-RANGEs assert, and it is the one that makes the rule a no-op on
# a REDUCE whose every range IS parented. `ru_go` takes the partition ONCE and
# threads both halves, because `Maybe` is not an accumulator and a `Data` record
# read twice in one body needs `+`.
def ru_last(rop: O.Op, none: Bool, +ar: O.Arena, +self: U32, +p: Parts) -> RW.Rew:
  match none:
    case True{} : RW.Rew{ar, 0}
    case False{}: ru_scale(rop, Parts.no(p), ru_ret.of(RW.rw_nat_zero(Parts.yes(p)), ar, self, Parts.yes(p)), ar)

def ru_go.of(rop: O.Op, +ar: O.Arena, +self: U32, +p: Parts) -> RW.Rew:
  ru_last(rop, RW.rw_nat_zero(Parts.no(p)), ar, self, p)

def ru_rule.go(ropok: Bool, allr: Bool, +ar: O.Arena, +self: U32) -> RW.Rew:
  match ropok allr:
    case True{} True{} : ru_go.of(ru_rop(ar, self), ar, self, ru_parts(RW.rw_src_from(ar, self, 1), RW.rw_ranges(ar, RW.rw_src0(ar, self))))
    case _ _            : RW.Rew{ar, 0}

# `if red.arg[0] not in {Ops.ADD, Ops.MAX, Ops.MUL}: return None` is the FIRST
# conjunct, ahead of the all-RANGEs `assert`, so `ru_rule.go` matches on BOTH and
# `ru_rop_pow` is the row for the pair -- `ru_rop_ok` on its own would pass even if
# the ladder were wired to the wrong conjunct.
def reduce_unparented(+ar: O.Arena, +self: U32) -> RW.Rew:
  ru_rule.go(ru_rop_ok(ru_rop(ar, self)), ru_all_ranges.go(RW.rw_src_from(ar, self, 1), ar), ar, self)

def pm_reduce_unparented() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}}]   # simplify.py:104  UPat(REDUCE, name="red")

def pm_simplify_ranges() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsEND{}, O.OpsREDUCE{}], Nil{}},   # simplify.py:69  (END, REDUCE) simplify_merge_adjacent
   O.PMEntry{1, [O.OpsINDEX{}], [O.OpsWHERE{}]},       # simplify.py:70  INDEX mark_gated
   O.PMEntry{2, [O.OpsREDUCE{}], Nil{}},                # simplify.py:71  REDUCE ctx.update
   O.PMEntry{3, [O.OpsSINK{}], Nil{}}]                  # simplify.py:72  SINK do_substitute

def pm_split_ranges() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsFLOORMOD{}], Nil{}},              # simplify.py:80  RANGE % cvar -> FLOORMOD
   O.PMEntry{1, [O.OpsSINK{}], Nil{}}]                  # simplify.py:81  SINK do_substitute

# `pm_reduce_collapse`'s OWN seven, in Python's order (simplify.py:109-125). The
# composite's length is `own + 123`, and `symbolic`'s count is a fact about a file
# this unit does not own, so it is a named constant rather than a table.
def pm_reduce_collapse() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}},                # :109 reduce_unparented  (PORTED)
   O.PMEntry{1, [O.OpsCMPLT{}], Nil{}},                 # :112 (x+y) < c
   O.PMEntry{2, [O.OpsCMPLT{}], Nil{}},                 # :115 (x*y) < c
   O.PMEntry{3, [O.OpsREDUCE{}], Nil{}},                # :120 UPat.any(...).reduce
   O.PMEntry{4, [O.OpsREDUCE{}], Nil{}},                # :124 (x+y).reduce(ADD)
   O.PMEntry{5, [O.OpsREDUCE{}], Nil{}},                # :126 (x & y).where(c,0).reduce
   O.PMEntry{6, [O.OpsMUL{}], [O.OpsCAST{}]}]           # :129 x * gate.cast()

def pm_load_collapse() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsREDUCE{}], Nil{}},                # simplify.py:142 reduce_load_collapse
   O.PMEntry{1, [O.OpsCMPLT{}], Nil{}}]                 # simplify.py:145 (x + y) < c, the no_load one

# `len(symbolic.patterns)` -- 123, and it is what `pm_reduce_collapse`'s 130 is
# mostly made of.
def symbolic_len() -> U32:
  123

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

def psize(n: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), n, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

# `UOp(Ops.REDUCE, src=(x,)+rngs, arg=(rop, len(rngs)))` -- ops.py:657.
def red(ar: O.Arena, x: U32, rngs: List<&2, U32>, rop: O.Op, na: U32) -> O.Found:
  O.UOp.new(ar, O.OpsREDUCE{}, List.append(&2, U32, [x], rngs), O.AReduce{rop, na}, O.TNone{})

def g() -> RW.G:
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
  RW.G{F.folded(O.Found.ar(en2)),
    [0,
     O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c4), O.Found.i(sp), O.Found.i(buf),
     O.Found.i(r0), O.Found.i(r1), O.Found.i(r2),
     O.Found.i(rd1), O.Found.i(rd2), O.Found.i(en1),
     O.Found.i(p1), O.Found.i(r3), O.Found.i(mx1), O.Found.i(rd3), O.Found.i(rd4),
     O.Found.i(cal), O.Found.i(lin), O.Found.i(en2)]}

def rw_of(+gx: RW.G, n: Nat) -> RW.Rew:
  flatten_range(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, n))

def ru_of(+gx: RW.G, n: Nat) -> RW.Rew:
  reduce_unparented(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, n))

# The rule's OWN ANSWER as an OP NAME, so this row is a STRING and the oracle can
# print the same string. It is the row for `ret * r.src[0]`: a mutation reading
# `r.src[1:]` or `r.arg[0]` instead of `r.src[0]` still builds a MUL here, so the
# SECOND src is what carries the meaning and `ru_bnd` is the row for it.
def ru_op_name.of(gone: Bool, nm: String) -> String:
  match gone:
    case True{} : "NONE"
    case False{}: nm

def ru_op_name(+ar: O.Arena, +i: U32) -> String:
  ru_op_name.of(O.UOp.is_none(i), O.Ops.name.of(RW.rw_op(ar, i)))

# The arena to read the ANSWER out of is `Rew.ar`, NEVER the fold's: the answer
# is a node the rule JUST interned and the fold's arena stops one short of it.
# Reading the fold's arena gave NOOP here, which reads like "a NOOP was built"
# and is really "there is no node 21 before the rewrite".
def ru_answer(+gx: RW.G, +n: Nat) -> String:
  ru_op_name(RW.Rew.ar(ru_of(gx, n)), RW.Rew.at(ru_of(gx, n)))

# `r.src[0]` -- R0's BOUND, `C4`, and NOT R0 itself and NOT its axis id 0. Two
# nodes are distinguishable here because `C0`, `C2` and `C4` are all CONSTs and
# only their VALUES differ.
def ru_bnd(+gx: RW.G) -> U32:
  RW.rw_src0(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 7n))

# `t_fr_len` -- `len(flatten_range.patterns)`, simplify.py:15.
def t_fr_len() -> U32:
  RW.n_of(pm_flatten_range())

# `t_ru_len` -- `len(pm_reduce_unparented.patterns)`, simplify.py:104.
def t_ru_len() -> U32:
  RW.n_of(pm_reduce_unparented())

# THE TABLE LENGTHS. Each is `len(<table>.patterns)` read out of Python, and each
# is a COUNT rather than a boolean because a rule DROPPED from a table and a rule
# whose body is a wall both leave every other row of this gate alone.
def t_sr_len() -> U32:
  RW.n_of(pm_simplify_ranges())

def t_xr_len() -> U32:
  RW.n_of(pm_split_ranges())

def t_rc_len() -> U32:
  RW.n_of(pm_reduce_collapse())

def t_lc_len() -> U32:
  RW.n_of(pm_load_collapse())

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
  fr_off(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 10n))

def t_fr_off_end() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 12n))

def t_fr_off_call() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 18n))

def t_fr_off_linear() -> U32:
  +gx = g()
  fr_off(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 19n))

# `t_fr_red` -- Python: `flatten_range.rewrite(RD1)` with RD1 = `REDUCE(C0, R0)`
# where `R0` is a RANGE. The generator's `((s,) if s.op is RANGE else ...)` gives
# `(R0,)`, `dedup` keeps it, and the answer is `REDUCE(C0, R0)` ITSELF -- the
# `src[:1] + (R0,)` is the original src, so `ops.py:252` returns `self` and
# `ops.py:1610` drops it. THIS IS A REAL ZERO ANSWER and not a wall.
def t_fr_red() -> U32:
  +gx = g()
  RW.b2u_nat(O.UOp.is_none(RW.Rew.at(rw_of(gx, 10n))))

# `t_fr_grow_same` -- `EN1 = END(RD1, R0)`. `off` is 1, `src[1:]` is `(R0,)`, the
# generator's RANGE arm gives `(R0,)`, `dedup` keeps it, and `src[:1]+(R0,)` IS
# the original src -- so `ops.py:252` returns `self`, `ops.py:1610` drops it, and
# the arena does NOT grow. 0 is the real answer and not a wall.
def t_fr_grow_same() -> U32:
  +gx = g()
  U32.sub(O.Arena.next(RW.Rew.ar(rw_of(gx, 12n))), O.Arena.next(F.Folded.ar(RW.G.fx(gx))))

# `t_fr_grow_moves` -- `EN2 = END(SPECIAL, R0, R0)`. The DUPLICATED RANGE is what
# makes `dedup` do something: the generator emits `(R0, R0)`, `dedup` answers
# `(R0,)`, and `src[:1]+(R0,)` is `(SPECIAL, R0)` against an original
# `(SPECIAL, R0, R0)` -- a NEW node, so the arena grows by exactly ONE. This is
# the ONLY fixture that exercises `fr_new`, and it is the row that catches a
# mutation of `fr_src` or of `dd_put`. `t_fr_grow_same` is its control and they
# differ by exactly the node.
def t_fr_grow_moves() -> U32:
  +gx = g()
  U32.sub(O.Arena.next(RW.Rew.ar(rw_of(gx, 20n))), O.Arena.next(F.Folded.ar(RW.G.fx(gx))))

# `t_fr_en2_shape` -- a COUNT, not a boolean: the rewritten `EN2` has TWO srcs.
# `t_fr_red` and `t_fr_grow_same` already say "the answer is nothing", so without
# this row a `fr_src` that dropped the `src[:off]` head would leave every one of
# them green -- `EN1`'s tail is its whole range list and `EN2`'s is not.
def t_fr_en2_shape() -> U32:
  +gx = g()
  RW.rw_nsrc(RW.Rew.ar(rw_of(gx, 20n)), RW.Rew.at(rw_of(gx, 20n)))

# `t_fr_dedup` -- `len(dedup((R0, R0)))`, i.e. `tinygrad/helpers.py:23`'s
# `list(dict.fromkeys(...))`: 1, not 2. It is the LOCAL property of `dd_put` and
# it is the whole of what `t_fr_grow_moves` is measuring, so the two rows say the
# same thing at two levels and a mutation of `dd_put` moves both.
def t_fr_dedup() -> U32:
  +gx = g()
  U32.from_nat(RW.rw_nat(dd_put(dd_put(Nil{}, RW.G.at(gx, 7n)), RW.G.at(gx, 7n))))

# `t_fr_unclaimed` -- `flatten_range` claims `{REDUCE, END}` and nothing else,
# so `MAX(C1, C2)` is not claimed. A table whose `ops` list were widened would
# move this row and no other.
def t_fr_unclaimed() -> U32:
  +gx = g()
  RW.b2u_nat(O.UOp.is_none(RW.Rew.at(rw_of(gx, 15n))))

# `t_ru_guard` -- `red.arg[0] not in {ADD, MAX, MUL}`. Every fixture REDUCE has a
# rop in that set, so this row pins the guard's FALSE arm only; `ru_rop` is the
# row that reads the rop.
def t_ru_rop_add() -> U32:
  +gx = g()
  RW.b2u_nat(ru_rop_ok(ru_rop(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 17n))))

def t_ru_rop_max() -> U32:
  +gx = g()
  RW.b2u_nat(ru_rop_ok(ru_rop(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 16n))))

# `t_ru_ranges` -- `all(x.op is RANGE for x in red.src[1:])` on `RD3`, whose three
# srcs beyond the first are all RANGEs. `RD4`'s is too.
def t_ru_ranges() -> U32:
  +gx = g()
  RW.b2u_nat(ru_all_ranges.go(RW.rw_src_from(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 16n), 1), F.Folded.ar(RW.G.fx(gx))))

# `t_ru_wall` -- THE WALL ROW. `RD1.src[0]` is `C0`, a CONST and NOT a RANGE, so
# `rw_ranges` answers `None` and EVERY `red.src[1:]` entry is "unparented". The
# rule therefore takes the empty-parented branch and returns `src[0]` scaled by
# each range's bound -- which is `REDUCE(C0, R0)` not folding at all. This row is
# the ONLY one that says the wall is a wall: it is the row a mutation of
# `rw_ranges`' RANGE arm would move if that arm were dropped.
def t_ru_wall() -> U32:
  +gx = g()
  RW.b2u_nat(Maybe.is_none(&2, List<&2, U32>, RW.rw_ranges(F.Folded.ar(RW.G.fx(gx)), RW.rw_src0(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 10n)))))

# `t_ru_range_yes` -- `rw_ranges` at a RANGE. The one arm needing no closure:
# `{self: None} | self._ranges` has `self` as its head. 1 means Some.
def t_ru_range_yes() -> U32:
  +gx = g()
  RW.b2u_nat(Maybe.is_some(&2, List<&2, U32>, RW.rw_ranges(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, 7n))))

# `t_ru_part` -- `partition(rd2.src[1:], lambda x: x in rd2.src[0].ranges)` where
# `rd2.src[0]` is `C1`, so the fold reports 2 unparented and 0 parented. `P` is
# the count of the FIRST list, `N` the count of the SECOND.
def t_ru_part_p() -> U32:
  +gx = g()
  +ar = F.Folded.ar(RW.G.fx(gx))
  U32.from_nat(RW.rw_nat(Parts.yes(ru_parts(RW.rw_src_from(ar, RW.G.at(gx, 11n), 1), RW.rw_ranges(ar, RW.rw_src0(ar, RW.G.at(gx, 11n)))))))

def t_ru_part_n() -> U32:
  +gx = g()
  +ar = F.Folded.ar(RW.G.fx(gx))
  U32.from_nat(RW.rw_nat(Parts.no(ru_parts(RW.rw_src_from(ar, RW.G.at(gx, 11n), 1), RW.rw_ranges(ar, RW.rw_src0(ar, RW.G.at(gx, 11n)))))))

# `t_ru_rop_guard` -- the FALSE arm of the guard ladder, built directly on `ru_rop_ok`
# with a rop the fixture does not have (POW), because no REDUCE in `g()` carries
# one. Without this row the ladder's `or` is unpinned.
def t_ru_rop_pow() -> U32:
  RW.b2u_nat(ru_rop_ok(O.OpsPOW{}))

def ru_answer_src0(+gx: RW.G) -> U32:
  RW.Rew.src0(ru_of(gx, 10n))

def ru_answer_is_c0(+gx: RW.G) -> U32:
  RW.b2u_nat(U32.is_eq(ru_answer_src0(gx), RW.G.at(gx, 1n)))

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

def main() -> IO(Unit):
  do IO<Unit>:
    z0 : Unit <- RW.row("ru_answer_c0", ru_answer_is_c0(g()))
    a : Unit <- RW.row("fr_len", t_fr_len())
    b : Unit <- RW.row("ru_len", t_ru_len())
    c : Unit <- RW.row("fr_off_reduce", t_fr_off_reduce())
    d : Unit <- RW.row("fr_off_end", t_fr_off_end())
    e : Unit <- RW.row("fr_off_call", t_fr_off_call())
    f : Unit <- RW.row("fr_off_linear", t_fr_off_linear())
    h : Unit <- RW.row("fr_red", t_fr_red())
    i : Unit <- RW.row("fr_grow_same", t_fr_grow_same())
    i2 : Unit <- RW.row("fr_grow_moves", t_fr_grow_moves())
    i3 : Unit <- RW.row("fr_en2_shape", t_fr_en2_shape())
    i4 : Unit <- RW.row("fr_dedup", t_fr_dedup())
    j : Unit <- RW.row("fr_unclaimed", t_fr_unclaimed())
    k : Unit <- RW.row("ru_rop_add", t_ru_rop_add())
    l : Unit <- RW.row("ru_rop_max", t_ru_rop_max())
    m : Unit <- RW.row("ru_rop_pow", t_ru_rop_pow())
    n : Unit <- RW.row("ru_ranges", t_ru_ranges())
    o : Unit <- RW.row("ru_wall", t_ru_wall())
    p : Unit <- RW.row("ru_range_yes", t_ru_range_yes())
    q : Unit <- RW.row("ru_part_p", t_ru_part_p())
    r : Unit <- RW.row("ru_part_n", t_ru_part_n())
    s : Unit <- RW.srow("ru_answer_rd1", ru_answer(g(), 10n))
    t : Unit <- RW.row("ru_bnd", ru_bnd(g()))
    RW.row("sr_len", t_sr_len())
    RW.row("xr_len", t_xr_len())
    RW.row("rc_len", t_rc_len())
    RW.row("rc_composite", t_rc_composite())
    RW.row("lc_len", t_lc_len())
