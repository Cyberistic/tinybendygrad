# rewriter.bend -- the SHARED REWRITE SUBSTRATE for codegen's three rewrite
# modules: the answer a rule returns, the node readers, the fixture's index map
# and the two row printers.
#
# ---------------------------------------------------------------------------
# IT HAS NO UPSTREAM `.py` AT THIS PATH, and that is not an omission: every def in
# it is PORT-LOCAL TOOLKIT and none of it is from `simplify.py`,
# `late/coalesce.py` or `gpudims.py`. `find tinygrad -name rewriter.py` returns
# nothing -- the lowerer is split three ways -- and what this file was is all
# three of them at once.
#
# WHAT IT WAS. One file for three, and the 1:1 ruling (one `.bend` per upstream
# `.py`, AT THE SAME PATH, no merging and no prefixes standing in for a directory)
# made it three:
#
#   tinygrad/codegen/simplify.py            156 lines   -> codegen/simplify.bend
#   tinygrad/codegen/late/coalesce.py       168 lines   -> codegen/late/coalesce.bend
#   tinygrad/codegen/gpudims.py             106 lines   -> codegen/gpudims.bend
#
# and THIS file is the residue. The criterion is MECHANICAL: a def is here iff at
# least TWO of the three used it, and every def exactly one of them used moved to
# that file. So `Rew` (the answer), `rew_hit`/`rew_self`/`rew_next` (the two
# spellings of "no rewrite" and the first-wins fold over them), the eleven `rw_*`
# node readers, `rw_ranges`, the `Nat` coercions `rw_nat`/`rw_nat_zero`, `b2u`/
# `b2u.of`/`b2u_nat`, `type G` with its three readers, `n_of` and `row`/`srow` are
# the residue.
#
# WHY NOT IN ONE OF THE THREE. None of them imports either of the other two --
# upstream `coalesce.py` does not import `simplify.py` -- so a substrate two of
# them need cannot live in one of them without asserting a dependency that does not
# exist. The precedent is `codegen/kernel.bend`, which is `codegen/__init__.py` and
# hosts the twin `Ker` answer and the `kn_*` readers for exactly this reason:
# `codegen/late/*.bend` imports it as `KER`. `codegen/late/regalloc.bend`'s header
# calls the arrangement "THE SHARED SUBSTRATE IS IMPORTED, NOT COPIED" and this
# file is the same shape one level up.
#
# IT IS IMPORTED, NOT COPIED. Every use in the three files is `RW.<name>`, and a
# TYPE MENTION needs the alias as well as a call -- an unqualified imported `type`
# name is not in scope -- so it is `RW.Rew` and `RW.Rew.ar`, never `Rew.ar`.
#
# ---------------------------------------------------------------------------
# IT PRINTS NO ROWS AND HAS NO `main`. Running it is not a gate. The 54 rows the
# merged file printed are `.agents/slop/codegen3-gate.sh`'s, from the three files,
# CONCATENATED IN PYTHON'S ORDER, and diffed against
# `.agents/slop/runs/base_codegen_rewriter.bend.txt` -- the snapshot taken before
# anything moved.
#
# THE CUT. `.agents/slop/split-codegen3.py` holds every moved body as a LINE RANGE
# in the pre-split text and `--check` re-derives that text from the four files and
# diffs it against the original, so "moved verbatim" is a checkable claim and not a
# promise. The only edits it applies are call-site QUALIFIERS and thirteen
# single-pass RENAMES to upstream names, and it prints both.

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
#   tinygrad/codegen/gpudims.py             106 lines   gpu dims (late)
#   tinygrad/codegen/late/linearizer.py      96 lines   <-- NOT MINE, see below
#   tinygrad/codegen/opt/*                  636 lines   <-- NOT MINE, see below
#   tinygrad/codegen/decomp/{op,transcendental}.py  -> decomp.bend / transcendental.bend
#
# So `rewriter.bend` takes the three TABLES and `kernel.bend` takes the pass
# STRUCTURE from `codegen/__init__.py`. `linearizer.py` and `opt/` are NOT
# claimed by either file; they are listed here so the omission is visible rather
# than silent. `renderer/{cstyle,wgsl}.bend` are the siblings and they consume
# `kernel.bend`'s output, not this file's.
#
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE WALL, stated once and honestly, because it is ONE wall and it is not in
# this file: **`UOp.ranges` is not ported.** fold.bend:4819-4823 marks
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

# `ret is not uop` -- ops.py:1618, inverted exactly as `hop_self` inverts it.
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

# `x.ranges` -- ops.py:497, DEFERRED (the header's wall). `ranges` is
# `{self: None} | self._ranges` for a RANGE and `self._ranges` otherwise, so the
# only arm needing no closure is the RANGE's, and its head is the node itself.
def rw_ranges.go(is_range: Bool, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, U32>>:
  match is_range:
    case True{} : Some{[i]}
    case False{}: None{}

def rw_ranges(+ar: O.Arena, +i: U32) -> Maybe<&2, List<&2, U32>>:
  rw_ranges.go(rw_is(ar, i, O.OpsRANGE{}), ar, i)

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
#   pm_device_to_var          2   UOp.variable                 gpudims.py:93
#   pm_group_gpudims          3   dicts + ssimplify + ctx      gpudims.py:101
#   pm_range_to_special       2   PORTED, see below + pm_split_ends
#
# THE LAST TWO ROWS ARE THE HEAD NAMES. `pm_add_gpudims` was RENAMED
# `pm_group_gpudims` and `pm_range_to_special` was ADDED, and the difference
# matters: the rename is 3 rules at BOTH ends with the SAME `ops` in the same
# order, so `gd_len` does not move and re-pointing the name is the whole of the
# port. `pm_range_to_special` did not exist at the pin at all (`rs_len` is
# `!ABSENT` there, measured), and it is PORTABLE -- one guard and one rebuild, no
# `ssimplify`, no dict, no `ctx` -- so it is ported rather than listed as a wall.
# `pm_split_ends` is linearizer.py's and linearizer.py is NOT MINE, so only its
# LENGTH is claimed.
#
# THE TWO COMPOSITE NUMBERS ARE WORTH THE TROUBLE, because a table built with `+`
# hides how much of it is the author's and how much is inherited:
# `pm_reduce_collapse` is `pm_reduce_unparented + 6 rules + symbolic`, so its own
# count is 7 and its LENGTH is 130 with `symbolic`'s 123. Reading 130 as "130
# rules in simplify.py" is the obvious mistake and `rc_own` is the row for it.
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

def n_of(ts: List<&2, O.PMEntry>) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, ts))

# `ru_answer_src0` -- `reduce_parented` is EMPTY here, so Python's answer is
# `red.src[0]` ITSELF and not a REDUCE with an empty tail. `ru_answer_rd1` says the
# answer is a MUL and this says what it multiplies, and the pair is what pins
# `ru_ret.of`'s arms: a swap still builds a MUL, so the first row stays green and
# only this one moves. It was added because M1 in the mutation table moved nothing.
def Rew.src0(+x: Rew) -> U32:
  rw_src0(Rew.ar(x), Rew.at(x))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# The same, for a row whose value is a STRING -- `ru_answer_rd1` is an OP NAME on
# both sides so the two lanes and the oracle all print one line.
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))
