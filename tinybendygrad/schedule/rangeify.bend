# rangeify.bend -- tinygrad/schedule/rangeify.py. The rangeification pass: 3.5 cleanups,
# bufferize/store conversion, kernel split -- eleven rule tables and the rewrites that
# run them.
#
# STATUS: the port is COMPLETE and `--check-only` passes. `main` 125 rows are derived
# from Python by `.agents/slop/rf-rows.py` and `rf-ct-oracle.py`, never restated from
# this file. A rule body that is not ported is one `# TODO(p3)` line at the foot naming
# the Python line it stands in for, so `rg 'TODO\(p3\)'` is the whole outstanding list.
# The long form of this header -- the staged-delivery record, the 41-mutation table and
# its five proofs -- is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# ELEVEN TABLES, ELEVEN DISPATCHES, and deliberately no generic one: `ops.bend` cannot
# call into this file and a rule table must be a top-level `Data` value (there are no
# closures), so every table gets its own `rf_<x>_table`/`_dispatch`/`_try`/`_scan`. The
# duplication IS the port. `pm_mops`/`pm_flatten_range` are OTHER files' tables; their
# foreign tags stay IN the table because the length and the tag space are Python facts
# the gate checks, and each dispatches to `rf_foreign`, which answers "no node" and
# names the owning file.
#
# WALL: THE ROOT, NOT THE CHILD. `.f()` rebuilds the pattern with the op passed to `f`
# at the ROOT and the receiver as the CHILD, and `pdict` is keyed on `p.op` (ops.py:1449,
# 1607) -- so a `.f()` entry's op set is the one handed to `f`, and the RECEIVER's op
# belongs in the rule BODY test. The wrong op makes the rule unfireable rather than
# wrong: the engine never looks the node up. MEASURED `ct` roots, tags 0..8:
# INDEX AFTER END STAGE STAGE STAGE INDEX INDEX INDEX. The reject sets are the
# CHILDREN's ops, read off `UPat.early_reject` (ops.py:1477), which is why they were
# RIGHT in the port while the op sets were not.
#
# MEASURED: `early_reject` IS A NECESSARY CONDITION, not a veto (ops.py:1609 is
# `if not early_reject.issubset(ler): continue`). Every reject set in these tables is
# empty or a singleton (`max(len) == 1`) and every `.f()` rule re-checks its own pattern,
# so mutating the subset test moves NOTHING (M3, M36).
#
# A NAME BOUND TWICE MUST EMIT AN IDENTITY CHECK (`upat.py:100-105` builds it as a
# literal `"{0} is {1}"`). The ONE place it happens here is `rb_1` (rangeify.py:135);
# without it every two-src STORE would rewrite to a NOOP. `uop/spec.bend`'s wall list
# cites this note by its first line, so that line is kept verbatim:
# 2. A NAME BOUND TWICE MUST EMIT AN IDENTITY CHECK (`upat.py:100-105` builds it
#
# `Hop` is `uop/movement.bend`'s, reused rather than copied: a rule answers a NEW node or
# `None`, and `None` is arena index 0, so the ARENA ITSELF separates "the rule fired"
# from "the rule rebuilt" -- a rule that does not fire interns nothing and does not grow
# it.
#
# THE THREE WALLS, each a `# TODO(p3)` at the foot. (a) `UOp.ranges` is a memoised
# recursive_property Bend refuses; `rf_ranges_miss` names it in one constant and
# `rg rf_ranges_miss` lists every dependent. (b) the rules MUTATE a Python `ctx` -- an
# `itertools.count` and two dataclass caches -- and Bend has no mutable state, so a
# counter is a PARAMETER and a dict is an assoc list; that is why `get_kernel_graph` is
# a STAGE ORDER and not a driver. (c) `BufferizeOpts.removable`/`addrspace` are not in
# `ops.bend`'s `Arg`, so every read of a STAGE's own `removable`/`addrspace`/`device` is
# a wall, and three rules turn on it.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../uop/movement.bend as M

# ===========================================================================
# THE READERS. `movement.bend`'s `mp_*` are reused, not copied: they are the
# same six reads of the same arena and a second copy would be pure weight. What
# is added here is what rangeify.py needs and `movement.bend` does not have --
# the fold's SHAPE, DTYPE, ADDRSPACE, DEVICE, BASE and ENDED_RANGES, and
# `UOp.ranges`, which is the wall.
#
# A `Data` record parameter still needs `+` for two reads in ONE body
# (bend2-constraints.md §1 of the spec.py notes), which is why `rf_fx` is
# `+`-consumed by every reader that touches both halves.
# ===========================================================================
def rf_fx(ar: O.Arena) -> F.Folded: F.folded(ar)

def rf_tb(fx: F.Folded) -> F.Table: F.Folded.t(fx)
def rf_ar(fx: F.Folded) -> O.Arena: F.Folded.ar(fx)

# `x.shape` -- ops.py:456 -- is a DOUBLE `Maybe`: the outer is "the table has no
# entry", the inner is `_shape` being `None`. `rangeify.py` reads it three times
# (43, 106, 187) and always wants the inner, so `rf_shape` is the inner.
def rf_shape.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case _: None{}

def rf_shape(+fx: F.Folded, self: U32) -> Maybe<&2, List<&2, O.Sint>>:
  rf_shape.go(F.fold.shape(rf_ar(fx), rf_tb(fx), self))

def rf_shape_is.go(a: Maybe<&2, List<&2, O.Sint>>, b: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match a b:
    case Some{x} Some{y}: F.eq_sints(x, y)
    case _ _: False{}

# `b2.shape == b2.max_shape` and friends: a shape COMPARISON, which is the only
# thing `remove_noop_bufferize` (106) and `debuf` (287) need of a shape.
def rf_shape_eq(+fx: F.Folded, a: U32, b: U32) -> Bool:
  rf_shape_is.go(rf_shape(fx, a), rf_shape(fx, b))

def rf_dt(+fx: F.Folded, self: U32) -> Maybe<&2, S.Dt>:
  F.fold.dt(rf_ar(fx), rf_tb(fx), self)

def rf_dt_or(+fx: F.Folded, self: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, rf_dt(fx, self), S.void())

# `x.addrspace` -- ops.py:1052 -- is also a double `Maybe`, and the inner is
# `One` (the fold) or `None`. `handle_after` (293) and the PARAM rule (316)
# both want the inner.
def rf_addr.go(m: Maybe<&2, Maybe<&2, S.Addr>>) -> Maybe<&2, S.Addr>:
  match m:
    case Some{a}: a
    case _: None{}

def rf_addr(+fx: F.Folded, self: U32) -> Maybe<&2, S.Addr>:
  rf_addr.go(F.fold.addr(rf_ar(fx), rf_tb(fx), self))

def rf_addr_is.go(a: Maybe<&2, S.Addr>, w: S.Addr) -> Bool:
  match a:
    case Some{v}: O.eq_addr(v, w)
    case _: False{}

def rf_addr_eq(+fx: F.Folded, self: U32, w: S.Addr) -> Bool:
  rf_addr_is.go(rf_addr(fx, self), w)

def rf_dev.go(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{d}: d
    case _: None{}

def rf_dev(+fx: F.Folded, self: U32) -> Maybe<&2, S.Dev>:
  rf_dev.go(F.fold.device(rf_ar(fx), rf_tb(fx), self))

# `x.base` -- ops.py:785 -- is `Maybe`-shaped because the fold has no entry for a
# node the rules cannot reach. `after_all_invalid` (111) and `debuf` want it as
# a plain index, and `Maybe.default(..., 0)` gives Python's "no base" the arena's
# reserved bottom, which no rule can reach.
def rf_base(+fx: F.Folded, self: U32) -> U32:
  Maybe.default(&1, U32, F.fold.base(rf_ar(fx), rf_tb(fx), self), 0)

# `x.ended_ranges` -- ops.py:470 -- PORTED, as `F.UOp.ended_ranges`.
def rf_ended(+fx: F.Folded, self: U32) -> List<&2, U32>:
  Maybe.default(&2, List<&2, U32>, F.UOp.ended_ranges(rf_ar(fx), rf_tb(fx), self), Nil{})

# `x.axis_type` -- ops.py:1054 -- PORTED, and NOT a fold property: a RANGE's arg
# is the pair, so it is a read of the node's own arg.
def rf_axis.go(m: Maybe<&2, O.AxisType>) -> O.AxisType:
  match m:
    case Some{a}: a
    case _: O.AXIS_LOOP{}

def rf_axis(ar: O.Arena, self: U32) -> O.AxisType:
  rf_axis.go(F.UOp.axis_type(ar, self))

def rf_axis_is(ar: O.Arena, self: U32, w: O.AxisType) -> Bool:
  O.eq_axis(rf_axis(ar, self), w)

# `dtypes.weaks` -- dtype.py:160 -- is `(weakint, weakfloat)`, and the only two
# members of `Cls` that are neither concrete-signed nor concrete-unsigned.
# `ab_5` (259) is the only reader.
def rf_weak_cls(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def rf_weak_dt.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: rf_weak_cls(S.Dt.cls(d))
    case _: False{}

def rf_weak_dt(+fx: F.Folded, self: U32) -> Bool:
  rf_weak_dt.go(rf_dt(fx, self))

# `x.is_invalid` -- ops.py:265 -- is `op is CONST and val is Invalid`, and
# `fold.bend` has it as `F.is_invalid`, on the node's OWN arg.
def rf_invalid(ar: O.Arena, self: U32) -> Bool: F.is_invalid(ar, self)

# `x.tag` is `()` for a scalar-tagged node and `None` otherwise, and the two are
# DISTINCT in Python (`ops.py:244` gives `tag: Any = None`). `ops.bend`'s `Tag`
# keeps them distinct too, so `rtag(())` is `TTuple{Nil{}}` and NOT `TNone{}`.
# `renumber_range` (300) and `pm_add_param_range_tags` (332) both turn on the
# difference, and `aprt_empty` is the row that says a `()`-tagged node is
# ALREADY the answer -- which is why Python's rule returns it and
# `ret is not uop` then drops it.
def rf_empty_tag() -> O.Tag: O.TTuple{Nil{}}
def rf_no_tag() -> O.Tag: O.TNone{}

def rf_tag_is_empty(ar: O.Arena, self: U32) -> Bool:
  O.eq_tag(M.mp_tag(ar, self), rf_empty_tag())

# `UOp.ranges` -- ops.py:497, and the set algebra behind it (`_ranges`, ops.py:483).
# THE WALL, and the single biggest one in this unit. `_ranges` is
# `union(s.ranges for s in self.src)` MINUS every range an ended range carries; it is a
# memoised `recursive_property` and Bend refuses the mutual recursion.
#
# Six rules read it -- `cleanup_dead_axes` (36), `gate_substitute` (46),
# `after_all_invalid` (112), `bufferize_to_store` (211), `split_store` (337) and
# `_limit_bufs` (194) -- and `rf_ranges_miss` is the honest spelling: the port cannot
# compute the set, so each answers the SAFE branch. It is `False` for "I have the set"
# and is a single named constant rather than six silent omissions.
def rf_ranges_miss() -> Bool: True{}

# `x.ranges` as a MEMBERSHIP test, spelled as the wall: `x.ranges` is not
# available, so the answer is the empty set and every `r in ranges` is `False`.
# Callers that must not silently get `False` pass `rf_ranges_miss()` to the
# rule, which turns the whole rule into "no answer".
def rf_in_ranges(ar: O.Arena, r: U32) -> Bool: False{}

# `is_noop_after_dep` -- rangeify.py:248-247. FULLY PORTED, and the smallest complete
# thing in the file. In Python it is a bounded descent; in Bend it is a FUEL FOLD whose
# fuel is `Arena.budget(ar)`, the same bound `UOp.toposort` takes, and the fuel is the
# FIRST parameter because the self-call must be decreasing left to right. The step is a
# separate def because a def may only call defs declared ABOVE it, and a step that
# recursed would be MUTUAL recursion, which is refused. `resolve` is not needed: both
# arms are `op` tests.
def noopf.at(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsNOOP{}), M.mp_nsrc_is(ar, self, 0))

# `len(x.src) >= 1`. `M.mp_nsrc_ge(ar, i, n)` is `n < mp_nsrc(ar, i)`, i.e. AT LEAST
# `n + 1` srcs (movement.bend:107), so it is NOT the test its name suggests and
# using it here would have demanded two srcs from a one-src END. MEASURED: the
# gate's `noopf_e_n0` row is 0 with `mp_nsrc_ge` and 1 with this.
def rf_has_src(+ar: O.Arena, +self: U32) -> Bool:
  Bool.not(U32.is_zero(M.mp_nsrc(ar, self)))

def noopf.cont(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsEND{}), rf_has_src(ar, self))

# THE ONLY RECURSIVE DEF IS `noopf_go`, AND IT IS DECLARED LAST. That is `ops.bend`'s
# `Topo.step` shape and it is forced, not stylistic: the ladder `go -> desc -> go` is
# MUTUAL RECURSION, which Bend refuses, and the declaration rule means the ladder helpers
# can only ever call back into the LAST def. MEASURED: every other arrangement of these
# four bodies is either a forward reference or a mutual-recursion refusal.
#
# The recursion CONDITION travels as a `Bool` FIELD of `Nd` because a `match` may not
# scrutinise a call (`noopf.cont(ar, node)` cannot be a scrutinee, a `Data` field binder
# can) and because the answer needs no accumulator: the chain is all ENDs, so it is
# decided by the node the chain LANDS ON.
#
# `noopf.cont` also carries the `len(x.src) >= 1` half. Python's `x.src[0]` on a zero-src
# END is an `IndexError`; the port answers "not a dead dep", which is the safe direction,
# and it is unreachable in practice because `UOp.end` (ops.py:619) returns `self` when
# there are no srcs.
type Nd is Data:
  Nd{node: U32, down: Bool}

def Nd.node(n: Nd) -> U32:
  match n:
    case Nd{node, down}: node

# the base case: `x.op is Ops.NOOP and len(x.src) == 0`, on the node the chain
# landed on. It is a separate total def so the recursive def's ladder has a leaf
# that does not call back.
def noopf_done(ar: O.Arena, node: U32) -> Bool:
  noopf.at(ar, node)

# the descent's STATE: `x.src[0]`, and the DESCENDED node's own END test for the
# next round. A total def, so `noopf_go`'s only self-call is its own.
def noopf_next(+ar: O.Arena, +node: U32) -> Nd:
  Nd{M.mp_src0(ar, node), noopf.cont(ar, M.mp_src0(ar, node))}

# THE ONE RECURSIVE DEF. The fuel is the FIRST parameter and the self-call is IN THIS
# BODY, passing `p` first, because `noopf_go -> noopf_step -> noopf_go` would be mutual
# recursion and is refused. The ladder is on BINDERS (`fuel` is a parameter, `node` and
# `down` come off a field pattern) because a `match` may not scrutinise a call and every
# test here is a call.
def noopf_go(fuel: Nat, +ar: O.Arena, n: Nd) -> Bool:
  match fuel:
    case 0n   : False{}
    case 1n+p : match n:
                case Nd{node, down}:
                  match down:
                    case True{}  : noopf_go(p, ar, noopf_next(ar, node))
                    case False{} : noopf_done(ar, node)

def is_noop_after_dep(+ar: O.Arena, +self: U32) -> Bool:
  noopf_go(O.Arena.budget(ar), ar, Nd{self, noopf.cont(ar, self)})

# `remove_noop_afters` -- rangeify.py:249-252. FULLY PORTED, and the shape is
# `rangeify.py`'s own idiom, which appears three more times in this file. THREE things
# are load-bearing and all three are easy to get wrong:
#
#   * `src[0]` is KEPT UNCONDITIONALLY. The filter is over `src[1:]` only, so an AFTER
#     whose BODY is a no-op END is not reduced to nothing.
#   * the answer is `len(src) == 1` and not "the filter emptied it": the one-src case
#     returns `src[0]`, a node ALREADY IN THE ARENA, so the arena does not grow.
#     `raf_after1_is_src0` is the row, and it is why a caller must not assume a rewrite
#     interns a node.
#   * `if len(src) != len(x.src)` is the WHOLE test. When nothing was removed the rule
#     answers `None` and the scan continues -- `raf_afterk` is that row, and asking "is
#     the answer absent" rather than "is the answer this index" is what makes the
#     negative side a witness.
#
# `x.src[0]` is an `IndexError` in Python for a zero-src node and the gate never asks:
# the pattern is `UPat(Ops.AFTER, name="x")` and `UOp.after` (ops.py:621) returns `self`
# when there are no srcs.
def raf.keep(x: U32, keep: Bool) -> List<&2, U32>:
  match keep:
    case True{} : List.append(&2, U32, [x], Nil{})
    case False{}: Nil{}

def raf.keep.go(+ar: O.Arena, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{} : acc
    case +x <> t: raf.keep.go(ar, t, List.append(&2, U32, acc, raf.keep(x, Bool.not(is_noop_after_dep(ar, x)))))

def raf.keep_srcs(+ar: O.Arena, +self: U32) -> List<&2, U32>:
  raf.keep.go(ar, O.Arena.src_from(ar, self, 1), [M.mp_src0(ar, self)])

# `len(src) == 1` -- the `src[0]` answer. `List.length` on a one-element list
# is 1 and on anything else is not, so the test needs no Nat arithmetic.
def raf_one(kept: List<&2, U32>) -> Bool:
  Nat.is_eq(List.length(&2, U32, kept), 1n)

def remove_noop_afters.of(one: Bool, shrank: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match one:
    case True{} : M.Hop{ar, M.mp_src0(ar, self)}
    case False{}: match shrank:
                  case True{} : M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, raf.keep_srcs(ar, self))
                  case False{}: M.Hop{ar, 0}

def remove_noop_afters(+ar: O.Arena, +self: U32) -> M.Hop:
  remove_noop_afters.of(raf_one(raf.keep_srcs(ar, self)),
                           Bool.not(U32.is_eq(M.mp_nsrc(ar, self),
                                              U32.from_nat(List.length(&2, U32, raf.keep_srcs(ar, self))))),
                           ar, self)

# `strip_zero_offset_shrink` -- rangeify.py:140-141. PORTED, with the symbolic half of
# `resolve` named. Two readers, and only one of them is free:
#
#   * `x.marg` for a SHRINK is `tuple(zip(self.src[1].as_shape, self.src[2].as_shape))`
#     (ops.py:816). `movement.bend` has `as_shape` and `marg_zip` already, and `as_shape`
#     is deliberately the CONST/STACK-of-CONST arms only. So this file reads the OFFSETS
#     only, and a SHRINK whose offset arg is a STACK of CONSTs -- what
#     `shape_to_shape_arg` builds for a multi-dimensional margin -- is answered.
#   * `resolve(start == 0, False)`: on a Python `int` this is the identity, because
#     `resolve` returns a `bool` unchanged (ops.py:65), so the CONST case is EXACT. On a
#     UOp the test is symbolic and needs `_min_max` (ops.py:1104), the wall `fold.bend`
#     defers, and `as_shape` does not answer it either. So the port is exact on every
#     node whose offsets are literal and answers "do not strip" on the rest -- which is
#     the `False` `resolve` was told to return. `szs_*` are the rows.
def rf_offsets(+ar: O.Arena, self: U32) -> Maybe<&1, List<&2, H.I64>>:
  M.as_shape(ar, M.mp_src(ar, self, 1))

def rf_is_zero.go(m: Maybe<&2, H.I64>) -> Bool:
  match m:
    case Some{v}: Cmp.is_eq(H.i64_cmp(v, H.i64_of_i32(0)))
    case None{}  : False{}

def rf_is_zero(+xs: List<&2, H.I64>) -> Bool:
  match xs:
    case Nil{}  : True{}
    case x <> t : Bool.and(rf_is_zero.go(Some{x}), rf_is_zero(t))

def rf_zero_off.go(m: Maybe<&1, List<&2, H.I64>>) -> Bool:
  match m:
    case Some{xs}: rf_is_zero(xs)
    case None{}  : False{}

# `zero` DELIBERATELY CARRIES THE SHRINK TEST with it, so the two tests above are
# the same predicate read twice and dropping either one is an ALGEBRAIC no-op --
# which is mutation M8 in the measured table, and it moving nothing is the point.
def rf_strip.of(shrink: Bool, zero: Bool, +ar: O.Arena, self: U32) -> M.Hop:
  match shrink:
    case True{} : match zero:
                  case True{} : M.Hop{ar, M.mp_src0(ar, self)}
                  case False{}: M.Hop{ar, self}
    case False{}: M.Hop{ar, self}

def strip_zero_offset_shrink(+ar: O.Arena, +self: U32) -> M.Hop:
  rf_strip.of(M.mp_is(ar, self, O.OpsSHRINK{}),
              Bool.and(M.mp_is(ar, self, O.OpsSHRINK{}), rf_zero_off.go(rf_offsets(ar, self))),
              ar, self)

# `x.src[0] if the SHRINK strips, else x` -- the INDEX-FREE reading of the same
# predicate, for the two call sites in `no_indexing_calls` that need an INDEX
# and one that does not.
def rf_strip_ix(ar: O.Arena, self: U32) -> U32:
  M.hop_ix(strip_zero_offset_shrink(ar, self))

# `no_indexing_calls` -- rangeify.py:143-158. FULLY PORTED. THE MSTACK ARM BUILDS A
# NODE, so this fold CARRIES THE ARENA and cannot be a pure `List` fold: the record `Bld`
# is the arena plus the accumulator, and it is `Data` so it is copyable, which is what
# lets a later arm build in the arena an earlier arm grew -- `movement.bend`'s `Hop` for
# the same reason, one field wider.
#
# The three src comments are upstream's and are kept:
#   "sometimes if call srcs have children the call will get an INDEX" (147)
#   "SHRINK with offset 0 is fine" (151)
#   "everything else we pass through" (156)
#
# THE WALL, named once: `MSTACK`'s `replace(src=...)` is a rebuild and `mp_replace` reads
# the node's OWN arg, which is `ANone` for a MSTACK -- so this port rebuilds the MSTACK
# with `ANone` and that is exact. The INDEX arm returns `x.src[0]`, a node already in the
# arena, so the arena does not grow for it; `nic_calli_nsrc` pins the arity and
# `nic_callm_src0_nsrc` pins the MSTACK arm's own arity.
type Bld is Data:
  Bld{ar: O.Arena, ys: List<&2, U32>}

def Bld.ar(b: Bld) -> O.Arena:
  match b:
    case Bld{ar, ys}: ar

def Bld.ys(b: Bld) -> List<&2, U32>:
  match b:
    case Bld{ar, ys}: ys

# the three arms that need no new node: INDEX unwraps, SHRINK strips, and
# everything else passes through. A `match` may only scrutinise a PARAMETER or a
# binder, so each `op` test arrives as a `Bool` and the ladder is nested.
def nic.of(ix: Bool, sh: Bool, ar: O.Arena, x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ix:
    case True{} : List.append(&2, U32, acc, [M.mp_src0(ar, x)])
    case False{}: match sh:
                  case True{} : List.append(&2, U32, acc, [rf_strip_ix(ar, x)])
                  case False{}: List.append(&2, U32, acc, [x])

def ar_is_index(ar: O.Arena, x: U32) -> Bool: M.mp_is(ar, x, O.OpsINDEX{})

def ar_is_shrink(ar: O.Arena, x: U32) -> Bool: M.mp_is(ar, x, O.OpsSHRINK{})

def ar_is_mstack(ar: O.Arena, x: U32) -> Bool: M.mp_is(ar, x, O.OpsMSTACK{})

# the MSTACK arm, which BUILDS: `x.replace(src=tuple(strip(s) for s in x.src))`
# The strip map is its own fold because it must finish before the rebuild, and
# the rebuild is in the TAKEN arm so a CALL that does not fire interns nothing.
def nic.mstack_srcs.go(+ar: O.Arena, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{} : acc
    case s <> t: nic.mstack_srcs.go(ar, t, List.append(&2, U32, acc, [rf_strip_ix(ar, s)]))

def nic.mstack_srcs(+ar: O.Arena, x: U32) -> List<&2, U32>:
  nic.mstack_srcs.go(ar, M.mp_srcs(ar, x), Nil{})

def nic.mstack_new(+ar: O.Arena, x: U32) -> M.Hop:
  M.mp_hit(O.UOp.new(ar, O.OpsMSTACK{}, nic.mstack_srcs(ar, x), O.ANone{}, O.TNone{}))

# the per-src step, which either appends an existing index or interns a MSTACK
# and appends THAT. `Bld` carries the arena so the second arm's node is visible
# to the first arm's accumulator, which is the whole reason the record exists.
def nic.two(+ar: O.Arena, +x: U32, acc: List<&2, U32>, ms: Bool) -> Bld:
  match ms:
    case True{} : Bld{M.hop_ar(nic.mstack_new(ar, x)),
                      List.append(&2, U32, acc, [M.hop_ix(nic.mstack_new(ar, x))])}
    case False{}: Bld{ar, nic.of(ar_is_index(ar, x), ar_is_shrink(ar, x), ar, x, acc)}

def nic.one(+ar: O.Arena, +x: U32, acc: List<&2, U32>) -> Bld:
  nic.two(ar, x, acc, ar_is_mstack(ar, x))

# THE FOLD. The fuel is the first parameter and the SELF-CALL IS IN THIS BODY, passing `p`
# first, because `nic.go -> nic.step -> nic.go` would be mutual recursion and is refused.
# The worklist pop and the accumulate are BOTH in the arm, and that is forced rather than
# chosen: a `List` is consumed as it is walked, and a separate step def holding that
# `match` would have to be called back into. The head binder is `+` because the MSTACK arm
# reads the node's own op and its srcs; `b` is threaded whole because `Bld` IS the arena
# the step reads.
def nic.go(fuel: Nat, +b: Bld, todo: List<&2, U32>) -> Bld:
  match fuel:
    case 0n   : b
    case 1n+p : match todo:
                case Nil{}    : b
                case +x <> t  : nic.go(p, nic.one(Bld.ar(b), x, Bld.ys(b)), t)

# `u.replace(src=tuple(new_srcs))` -- the rule's answer, threaded through the
# arena the fold ended with, because the MSTACK arm may have grown it.
def rf_no_indexing_calls_of(fuel: Nat, +ar: O.Arena, self: U32) -> Bld:
  nic.go(fuel, Bld{ar, Nil{}}, M.mp_srcs(ar, self))

# the rule: the fold, then the rebuild in the arena the fold ended with.
def no_indexing_calls.fin(+self: U32, +b: Bld) -> M.Hop:
  M.mp_replace(M.mp_op(Bld.ar(b), self), M.mp_arg(Bld.ar(b), self), Bld.ar(b), self, Bld.ys(b))

def no_indexing_calls(+ar: O.Arena, +self: U32) -> M.Hop:
  no_indexing_calls.fin(self, rf_no_indexing_calls_of(O.Arena.budget(ar), ar, self))

# `renumber_range` -- rangeify.py:299-303. FULLY PORTED, and the FIRST place this file has
# to be honest about a Python `ctx`: `ctx.range += 1` happens AFTER the node is built and
# `ctx.range` is a mutable dataclass field, so the counter is a PARAMETER here and the
# increment is the CALLER's. `rf_renumber` takes `n` and answers the node,
# `rf_renumber_next` is the successor, and that pair is the shape every one of
# rangeify.py's four ctx-carrying rules needs.
#
# The guard is NEGATIVE: `if r.tag != (): return None`, so the rule FIRES WHEN THE TAG IS
# `()`. MEASURED: with the arms the other way round, `ren_none` printed 0 and
# `ren_arg0`/`ren7_arg0` both printed 0 -- the rule fired on an untagged RANGE and the
# two-sided counter row could not see the difference.
#
# `r.arg[1:]` on a RANGE's arg: the arg is `(axis_id, axis_type)` (ops.py:504), so
# `(ctx.range,)+r.arg[1:]` is `(ctx.range, axis_type)`, which in `ops.bend` is
# `ARange{[n], at}`. The AxisType is read off the node, not rebuilt, and `ren_arg0` /
# `ren7_arg0` are the two-sided row: with `n = 0` and `n = 7` the id is 0 and 7 and the
# successor is 1 and 8.
def rf_renumber.of(tagged: Bool, +ar: O.Arena, +self: U32, n: U32) -> M.Hop:
  match tagged:
    case True{} : M.mp_hit(O.UOp.new(ar, O.OpsRANGE{}, M.mp_srcs(ar, self),
                                    O.ARange{[n], rf_axis(ar, self)}, rf_no_tag()))
    case False{}: M.Hop{ar, 0}

def rf_renumber(+ar: O.Arena, +self: U32, n: U32) -> M.Hop:
  rf_renumber.of(rf_tag_is_empty(ar, self), ar, self, n)

def rf_renumber_next(n: U32) -> U32: U32.add(n, 1)

# `x.rtag` -- ops.py:257 -- is `replace(tag=tag)`: a rebuild with a NEW tag and
# nothing else. `mp_replace` cannot do it, because it writes the node's OWN tag
# back, so this is the one rebuild in this file that is spelled out rather than
# delegated, and the reason is a one-word difference in what is written. It is a
# Hop and not a U32 because `rtag` on an already-`()`-tagged node returns the
# SAME node, and `hop_self` turns that into "no answer" -- which is exactly
# Python's `ret is not uop` (ops.py:1610).
def rf_rtag.found(+ar: O.Arena, +self: U32, t: O.Tag) -> O.Found:
  O.UOp.new(ar, M.mp_op(ar, self), M.mp_srcs(ar, self), M.mp_arg(ar, self), t)

def rf_rtag(+ar: O.Arena, +self: U32, t: O.Tag) -> M.Hop:
  M.mp_hit(rf_rtag.found(ar, self, t))

# the same rebuild as a `Found`, because a FIXTURE has to keep the grown arena to
# build the next node in. `rf_rtag` answers a `Hop` because that is what a rule
# answers, and a `Hop`'s index is not enough to build a node on; the two are one
# line apart and the fixture is the only caller that needs the second.

# ===========================================================================
# `pm_add_param_range_tags` -- rangeify.py:330-333. FULLY PORTED.
#
#     # Scalar parameters keep their identity across the call boundary.
#     (UPat((Ops.PARAM, Ops.RANGE), name="x"),
#      lambda x: None if x.op is Ops.PARAM and x.addrspace is AddrSpace.ALU else x.rtag(())),
#
# The op test is `x.op is Ops.PARAM`, so a RANGE falls to the else arm and is
# TAGGED -- the pdict key is `PARAM|RANGE` and the comment explains why the
# RANGE is in it. The ALU test is the third conjunct and it is the only reason
# the rule is not simply "tag everything", so `aprt_palu` and `aprt_paluT` are
# the rows that say an ALU PARAM is left alone EVEN WHEN IT IS ALREADY TAGGED.
#
# `x.rtag(())` on a node already tagged `()` returns the SAME node, and
# `ret is not uop` (ops.py:1610) drops it. That is not a quirk of the port: it
# is why the rule is idempotent and why `aprt_empty` prints 0 rather than the
# index it would have to invent. The row asks for the ABSENCE of an answer,
# which is the shape the constraints file recommends for a negative side.
# ===========================================================================
def rf_param_rtag.of(alu: Bool, +ar: O.Arena, self: U32) -> M.Hop:
  match alu:
    case True{} : M.Hop{ar, 0}
    case False{}: rf_rtag(ar, self, rf_empty_tag())

def rf_alu_param(+fx: F.Folded, +ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsPARAM{}), rf_addr_eq(fx, self, S.Aalu{}))

def rf_param_rtag(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  rf_param_rtag.of(rf_alu_param(fx, ar, self), ar, self)

# THE FIRST-WINS FOLD, and the CLAIM TEST, both shared. First-wins over a `Hop` is
# `movement.bend`'s `hop_next`/`hop_first`, reused rather than copied, and the claim test
# is `O.pm_claimed(ops, ar, self)` plus this file's own `early_reject` fold -- a second
# copy of `movement.bend`'s `mp_early`, because the two files' tables have DIFFERENT
# reject sets and neither may call the other. `early_reject` IS A NECESSARY CONDITION: the
# rule FIRES when its op set is a subset of `ler` (ops.py:1609), and the empty set is a
# subset of everything.
def rf_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(O.op_in(have, o), rf_early.go(have, t))

def rf_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  rf_early.go(O.pm_ler(ar, self), rej)

# THE CLAIMED TEST, both halves, as one Bool. `ar` is `+` because `ler` is read
# once for the reject test and `pm_claimed` reads the node.
def rf_claimed(+ar: O.Arena, +self: U32, ops: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  Bool.and(O.pm_claimed(ops, ar, self), rf_early(ar, self, rej))

# `ret is not uop` -- tinygrad/uop/ops.py:1618. IT IS NOT `M.hop_self`, and the reason is a MEASURED BUG
# in `movement.bend`, reported here and not fixed there. `movement.bend:67`'s
# `hop_self.of` has its arms swapped: `b` is "the answer is `self`, or the answer is
# none", `True` KEEPS the answer and `False` -- a genuinely NEW node -- DROPS it, which is
# the inverse of `ret is not uop` and of the docstring above it.
#
# The proof is `movement.bend`'s OWN gate, failing on exactly the rows that need a new
# node: `shrink1_ns=0` where it must be 3, and `reshape_pick`, `permute_merge`,
# `stack_idx`, `const_idx2`, `idx_idx`, `idx_pick`, `idx_shaped` all 0 where each must be
# non-zero. `t_ret_new` (movement.bend:920) asks `is_none(hop_self(Hop{ar, 3}, 2))` and
# prints 1, i.e. it ASSERTS the inverted behaviour.
#
# So this file implements `ret is not uop` itself, uses `M.hop_next`/`M.hop_first` (which
# ARE correct -- `hop_first` takes `r` exactly when the accumulator is none), and not
# `M.hop_self`. REPORTED, NOT FIXED: `movement.bend` is not this file's.
def rf_self.of(same: Bool, +r: M.Hop) -> M.Hop:
  match same:
    case True{} : M.Hop{M.hop_ar(r), 0}
    case False{}: r

def rf_self(+r: M.Hop, self: U32) -> M.Hop:
  rf_self.of(U32.is_eq(M.hop_ix(r), self), r)

# TABLE 1: `pm_remove_bufferize` -- rangeify.py:131-138. THREE RULES, all three bodies
# PORTED except `remove_bufferize` itself, which is the biggest wall in the file and is
# discussed at the foot.
#
#   0  UPat.var("src").f(Ops.STAGE, allow_any_len=True, name="buf")
#                            .f(Ops.INDEX, allow_any_len=True, name="idx")  -> remove_bufferize
#   1  UPat.var("x").store(UPat.var("x"))                            -> UOp(Ops.NOOP)
#   2  UPat(Ops.END, src=(UPat(Ops.NOOP, name="x"),), allow_any_len=True) -> x
#
# `rb_1` IS THE IDENTITY-CHECK RULE of the header: `x` is bound twice, so
# `upat.py:100-105` emits `uop.src[0] is uop.src[1]`, and without it every two-src STORE
# would become a NOOP. MEASURED compiled form (`rf-names.py`):
# `uop.op is STORE and len(uop.src) == 2 and uop.src[0] is uop.src[1]`. `rb_0`'s reject
# set is `{STAGE}` and `rb_2`'s is `{NOOP}` -- the op of the pattern's FIRST src, which is
# what `early_reject` (ops.py:1477) is.
def rb_ident(+ar: O.Arena, +self: U32) -> Bool:
  U32.is_eq(M.mp_src(ar, self, 0), M.mp_src(ar, self, 1))

# the pattern's own half: `UPat.var("x").store(UPat.var("x"))` is a two-src STORE
def rb_self_store(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_nsrc_is(ar, self, 2), rb_ident(ar, self))

# rb_1: `lambda x: UOp(Ops.NOOP)` -- a NOOP with no srcs and no arg.
def rb_1.of(same: Bool, +ar: O.Arena) -> M.Hop:
  match same:
    case True{} : M.mp_hit(O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{}))
    case False{}: M.Hop{ar, 0}

def rb_1(+ar: O.Arena, self: U32) -> M.Hop:
  rb_1.of(rb_self_store(ar, self), ar)

# rb_2: `lambda x: x` -- `END` whose src[0] is a NOOP answers that NOOP, a node
# ALREADY IN THE ARENA. So `hop_self` is NOT applied: Python returns `x`, the
# bound name, and `x` is the src, not the node under examination, so `ret is not
# uop` holds. This is the second place a rewrite returns a node it did not build
# and the reason `rb_e_n0` is a POSITIVE row.
def rb_2.of(noop: Bool, +ar: O.Arena, self: U32) -> M.Hop:
  match noop:
    case True{} : M.Hop{ar, M.mp_src0(ar, self)}
    case False{}: M.Hop{ar, 0}

def rb_2(+ar: O.Arena, +self: U32) -> M.Hop:
  rb_2.of(M.mp_is(ar, M.mp_src0(ar, self), O.OpsNOOP{}), ar, self)

# rb_0: `remove_bufferize` -- rangeify.py:48-102, and it is NOT PORTED. The wall
# is spelled out at the foot; what is here is the CLAIM, so the table length and
# the claim count are right even though the body is absent.
def rb_0(+ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

def rb_dispatch.go(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: rb_0(ar, self)
    case 1: rb_1(ar, self)
    case 2: rb_2(ar, self)
    case _: M.Hop{ar, 0}

def rb_dispatch(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  rb_dispatch.go(tag, ar, self)

# THE TRY: the claim test, then the dispatch, then `ret is not uop`.
def rb_try.of(ok: Bool, tag: U32, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : rf_self(rb_dispatch(tag, ar, self), self)
    case False{}: M.Hop{ar, 0}

def rb_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  rb_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), ar, self)

# THE SCAN. `hop_next` is first-wins; the arena comes from the ACCUMULATOR `h`,
# not the parameter, because a later rule builds in the arena an earlier rule
# produced. `rb_0` interns nothing today, so the arena never grows here, and
# `rb_arena` is the row that would see it if it did.
def rb_scan(rs: List<&2, O.PMEntry>, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: rb_scan(t, self, M.hop_next(h, rb_try(M.hop_ar(h), self, e)))

# THE TABLE. Three entries, in rangeify.py's order, so tag N is (line, N).
def rb_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsINDEX{}],         [O.OpsSTAGE{}]},   # 133  src.f(STAGE).f(INDEX)
   O.PMEntry{1, [O.OpsSTORE{}],         Nil{}},            # 135  x.store(x) -> NOOP
   O.PMEntry{2, [O.OpsEND{}],           [O.OpsNOOP{}]}]    # 137  END(NOOP) -> NOOP

# THE REWRITE -- ops.py:1604-1611. `ler` is computed ONCE and threaded, which is what
# `spec.bend` found necessary: a two-src `ler` can never contain a four-op reject
# set, and `rb_0`'s is one op so it happens not to bite here.
def rb_rewrite(+ar: O.Arena, self: U32) -> M.Hop:
  rb_scan(rb_table(), self, M.Hop{ar, 0})

# TABLE 2: `pm_no_indexing_calls` -- rangeify.py:366-162. ONE RULE, and its body
# `no_indexing_calls` is the fold above, fully ported. It is a LATE table in
# `get_kernel_graph` (line 368), after `split_kernels`, and it is the last rewrite that
# can still see a CALL carrying views -- which is why the upstream comment at 164 is the
# invariant this whole rule exists to establish.
def nic_dispatch.go(tag: U32, +ar: O.Arena, +self: U32) -> M.Hop:
  match tag:
    case 0: rf_self(no_indexing_calls(ar, self), self)
    case _: M.Hop{ar, 0}

def nic_dispatch(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  nic_dispatch.go(tag, ar, self)

def nic_try.of(ok: Bool, tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  match ok:
    case True{} : nic_dispatch(tag, ar, self)
    case False{}: M.Hop{ar, 0}

def nic_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  nic_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), ar, self)

def nic_scan(rs: List<&2, O.PMEntry>, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: nic_scan(t, self, M.hop_next(h, nic_try(M.hop_ar(h), self, e)))

def nic_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsCALL{}], Nil{}}]   # 161  u -> no_indexing_calls(u)

def nic_rewrite(+ar: O.Arena, self: U32) -> M.Hop:
  nic_scan(nic_table(), self, M.Hop{ar, 0})

# TABLE 3: `pm_no_views` -- rangeify.py:367-168. ONE RULE, body FULLY PORTED, and it is the
# smallest table in the file. The comment above it is upstream's and is the whole reason
# the rule exists: "the kernel graph is what gets executed: no shape views left in it, the
# storage of a value is just the storage".
#
# The answer is `v.src[0]`, a node ALREADY IN THE ARENA, so the arena does not grow --
# and `nv_rsi` is the row that says so: a RESHAPE over an INDEX is REJECTED by the pattern
# (an INDEX is not in the op set) even though the rule body would happily return it. The
# pattern is the test; the body is the answer.
def nv_0.of(pat: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match pat:
    case True{} : M.Hop{ar, M.mp_src0(ar, self)}
    case False{}: M.Hop{ar, 0}

# the six buffer-identity ops. `UNSHARD` is in the list and is a movement op
# (ops.py:206), which is why `GroupOp.movement` includes it.
def rf_is_bufid5(op: O.Op) -> Bool:
  match op:
    case O.OpsAFTER{}  : True{}
    case O.OpsPARAM{}  : True{}
    case O.OpsUNSHARD{}: True{}
    case O.OpsMSTACK{} : True{}
    case O.OpsBUFFER{} : True{}
    case O.OpsALLOC{}  : True{}
    case _: False{}

def rf_nv_mv(+ar: O.Arena, +self: U32) -> Bool:
  Bool.or(M.mp_is(ar, self, O.OpsRESHAPE{}), M.mp_is(ar, self, O.OpsSHRINK{}))

# the pattern's own tests: a RESHAPE or a SHRINK, with at least one src, whose
# src[0] is one of the six.
def rf_nv_pat(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(rf_nv_mv(ar, self),
           Bool.and(M.mp_nsrc_ge(ar, self, 1), rf_is_bufid5(M.mp_op(ar, M.mp_src0(ar, self)))))

def nv_0(+ar: O.Arena, +self: U32) -> M.Hop:
  nv_0.of(rf_nv_pat(ar, self), ar, self)

def nv_dispatch.go(tag: U32, +ar: O.Arena, +self: U32) -> M.Hop:
  match tag:
    case 0: nv_0(ar, self)
    case _: M.Hop{ar, 0}

def nv_dispatch(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  nv_dispatch.go(tag, ar, self)

def nv_try.of(ok: Bool, tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  match ok:
    case True{} : nv_dispatch(tag, ar, self)
    case False{}: M.Hop{ar, 0}

def nv_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  nv_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), ar, self)

def nv_scan(rs: List<&2, O.PMEntry>, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: nv_scan(t, self, M.hop_next(h, nv_try(M.hop_ar(h), self, e)))

def nv_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRESHAPE{}, O.OpsSHRINK{}], Nil{}}]   # 166  v -> v.src[0]

def nv_rewrite(+ar: O.Arena, self: U32) -> M.Hop:
  nv_scan(nv_table(), self, M.Hop{ar, 0})

# TABLE 4: `pm_add_param_range_tags` -- rangeify.py:330-333. ONE RULE, body FULLY PORTED,
# and the smallest COMPOSITION-free table. The upstream comment is kept: "Scalar parameters
# keep their identity across the call boundary." That is what the `()` tag is FOR -- an
# untagged PARAM and a tagged one are different nodes in the ucache (ops.py:200), and
# dropping the tag would merge them. `aprt_paluT` pins the ALU half: an ALU PARAM that
# ALREADY carries a `()` tag is still left alone, so the rule is not "retag everything".
def aprt_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, +self: U32) -> M.Hop:
  match tag:
    case 0: rf_self(rf_param_rtag(fx, ar, self), self)
    case _: M.Hop{ar, 0}

def aprt_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  aprt_dispatch.go(tag, fx, ar, self)

def aprt_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : aprt_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def aprt_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  aprt_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

# THE SCAN. `ar` is the arena on ENTRY and `h` carries the arena as the pass
# stands, which is why the recursive call passes `M.hop_ar(h)` and not `ar`:
# a later rule builds in the arena an earlier rule produced. This is the
# `rb_scan` shape and the `hop_self` one.
def aprt_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: aprt_scan(t, fx, self, M.hop_next(h, aprt_try(fx, M.hop_ar(h), self, e)))

def aprt_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsPARAM{}, O.OpsRANGE{}], Nil{}}]   # 332  x -> None if ALU PARAM else x.rtag(())

def aprt_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  aprt_scan(aprt_table(), fx, self, M.Hop{ar, 0})

# TABLE 5: `split_kernels` -- rangeify.py:346-348. ONE RULE, and its body `split_store`
# (rangeify.py:335) is NOT PORTED: the wall is `graph_rewrite` INSIDE a rule, which is the
# engine calling itself, and it is the same wall `movement.bend` records for `mp_0`.
# `split_store` also reads `x.ranges` (line 337), which is the `UOp.ranges` wall, and it
# calls `graph_rewrite(x, to_define_global+pm_flatten_range, ctx=lctx, name="kernel split",
# bottom_up=True)` -- a MUTABLE `lctx` threaded through a nested pass, which the no-`ctx`
# wall is the other half of.
def sk_0(+ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

def sk_dispatch.go(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: sk_0(ar, self)
    case _: M.Hop{ar, 0}

def sk_dispatch(tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  sk_dispatch.go(tag, ar, self)

def sk_try.of(ok: Bool, tag: U32, +ar: O.Arena, self: U32) -> M.Hop:
  match ok:
    case True{} : sk_dispatch(tag, ar, self)
    case False{}: M.Hop{ar, 0}

def sk_try(+ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  sk_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), ar, self)

def sk_scan(rs: List<&2, O.PMEntry>, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: sk_scan(t, self, M.hop_next(h, sk_try(M.hop_ar(h), self, e)))

def sk_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSTORE{}, O.OpsEND{}], Nil{}}]   # 347  x -> split_store(x)

def sk_rewrite(+ar: O.Arena, self: U32) -> M.Hop:
  sk_scan(sk_table(), self, M.Hop{ar, 0})

# TABLE 6: `pm_gate_substitute` -- rangeify.py:45-47. ONE RULE, and it is the ODD ONE OUT IN
# THIS ENTIRE FILE. IT DOES NOT RETURN A NODE. It RAISES `BottomUpGate` (ops.py:1764),
# which the graph engine's own loop catches (ops.py:1827) and reads as "stop descending
# here", and a raise is not a value, so it is not a `Hop` and there is no dispatch for it.
# From the engine's point of view the rule answers "no rewrite" -- which IS the `Hop` at
# index 0. So the port is exact: `gs_0` answers `M.Hop{ar, 0}` and the `raise` is
# documented as what became the `0`. It is `compiled=False` because a raise cannot appear
# in a compiled predicate, and `GroupOp.All` is every op, so the pattern's own tests are
# vacuous.
#
# `b.ranges` is the `UOp.ranges` wall and it costs this rule NOTHING: the answer is "no
# rewrite" either way, and a node whose `ranges` DOES meet the ctx keys must also fall
# through here. That is worth saying because it is the only `ranges` reader in the file for
# which that is true.
def gs_0(+ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# `GroupOp.All` is the whole enum and `Arena.op` answers `Op`, so the claim is
# "there is an op here" and the set is every constructor `ops.bend` declares.
# `spec.bend` writes the same list out for the same reason.
def GS_ALL() -> List<&2, O.Op>:
  [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{},
   O.OpsPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{},
   O.OpsPYLITERAL{}, O.OpsSINK{}, O.OpsAFTER{}, O.OpsGROUP{}, O.OpsSTACK{}, O.OpsGETADDR{},
   O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{},
   O.OpsBITCAST{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{},
   O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{},
   O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{},
   O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{},
   O.OpsEND{}, O.OpsENDIF{}, O.OpsBACKEDGE{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{},
   O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}, O.OpsCOPY{}, O.OpsMSELECT{},
   O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{},
   O.OpsPAD{}, O.OpsFLIP{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}]

def gs_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, GS_ALL(), Nil{}}]   # 47  b -> raise BottomUpGate (a no-answer here)


# THE FOREIGN TAGS. Four of rangeify.py's tables are `a + b` compositions with a table this
# file does not own, and the foreign rules come FIRST, so their tags are 0..n-1 and every
# own tag is shifted. Keeping them in the table is the honest choice for three reasons: the
# length is a Python fact the gate checks, the tag space is a Python fact the dispatch
# depends on, and counting them out would make `ct_4` mean a different rule. `rf_foreign`
# answers "no node" and says which file owns the tag. It is ONE def for all four
# compositions rather than four, because a tag from a foreign table is not merely unported
# -- it is not THIS FILE's rule to port, and inventing a body would be a lie about where
# the code lives.
def rf_foreign(src: String, +ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# THE ROOT/SUB SPLIT, and it is the whole reason the table is written out longhand. `.f()`
# is `def f(self, op, **kwargs): return UPat(op, src=(self,), **kwargs)` (ops.py:1449):
# the chain REBUILDS the pattern with the op passed to `f` as the ROOT and the receiver as
# the CHILD. `PatternMatcher.__init__` keys `pdict` on `p.op` and `rewrite` looks the node
# up with `self.pdict.get(uop.op)` (ops.py:1607). So for every `.f()` entry the pdict key is
# the op handed to `f`, and the RECEIVER's op is the CHILD's and belongs in the rule's own
# body test.
#
# MEASURED, by reading `p.op` off all nine patterns and `pdict` off the matcher
# (`.agents/slop/rf-ct-oracle.py` section 0; output in `rf-ct-oracle.txt`): all nine roots
# are single-op sets, and the three reject sets (4 {INDEX}, 7 {AFTER}, 8 {MSTACK}) are the
# CHILDREN's ops, read off `UPat.early_reject` (ops.py:1477). The table carried the child's
# op set for tags 0, 1, 2, 5 and 8, so `ct_4`'s body read the OUTER node's op while its
# entry keyed the INNER one and the rule could never fire. M21 in the mutation table is
# that defect, restored.
def MOPS_ROOT_FB() -> List<&2, O.Op>: [O.OpsINDEX{}]   # prepare.py:78  root of the .f chain
def MOPS_ROOT_AF() -> List<&2, O.Op>: [O.OpsAFTER{}]   # prepare.py:80  root of .after
def MOPS_ROOT_EN() -> List<&2, O.Op>: [O.OpsEND{}]     # prepare.py:82  root of .end

# THE CHILD SETS, `GroupOp.Movement` and `GroupOp.Movement|{Ops.INDEX}`, which
# are the ops of the `.f`/`after`/`end` RECEIVERS. They are a real fact about the
# PATTERN -- `schedule/prepare.bend`'s `pm_mops` bodies test them -- and they are
# NOT the pdict key, which is what the port confused them for. `mops_child_fb` is
# 6 and `mops_root0` is the INDEX op NUMBER, and both are rows because the two
# numbers being different is the finding.
def MOPS_FB() -> List<&2, O.Op>: [O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsFLIP{}]

def MOPS_AFTER() -> List<&2, O.Op>:
  List.append(&2, O.Op, MOPS_FB(), [O.OpsINDEX{}])

def MOPS_END() -> List<&2, O.Op>: MOPS_FB()

# `pm_mops` -- schedule/prepare.py:76-83, THREE rules, and this file needs all
# three for `ct_len` and `ab_len` to be right. Its bodies are `_mop_index` and
# two `Movement .after` / `.end` rewrites, all of which need
# `apply_movement_op` (indexing.py:171) or `UOp.substitute` (ops.py:532).
def rf_mops_fb(ar: O.Arena) -> M.Hop: rf_foreign("prepare.py:78", ar, 0)
def rf_mops_af(ar: O.Arena) -> M.Hop: rf_foreign("prepare.py:80", ar, 0)
def rf_mops_en(ar: O.Arena) -> M.Hop: rf_foreign("prepare.py:82", ar, 0)

# TABLE 7: `pm_const_buffer_folding` -- rangeify.py:115-129. NINE RULES: the three `pm_mops`
# rules (foreign, tags 0-2) and SIX OWN -- `cleanup_dead_axes`, `remove_noop_bufferize`,
# `const_like`, `index-a-const`, `after_all_invalid`, and the deviceless-MSTACK unwrap.
#
# THE REJECT SETS ARE THE INTERESTING PART and they are three of the file's six: `ct_4` is
# `{INDEX}`, `ct_7` is `{AFTER}`, `ct_8` is `{MSTACK}`. Each is the op of the pattern's
# FIRST src and each is already implied by the rule's own op test, so `early_reject` decides
# no verdict here. `rej_ct4` is the row that catches a MISSPELLED set, which is the failure
# mode that is real.
#
# TWO OF THE SIX ARE FULLY PORTED and they are the two a reader checks first, because they
# are the ones with no `ranges` and no `BufferizeOpts`: `ct_6` ("indexing a const is the
# const") and `ct_4`'s `remove_noop_bufferize`. `ct_5` needs `const_like` (ops.py:603, a
# `DType` method, P3) and `ct_7` needs `after_all_invalid`'s `resolve(...eq(...))`, which is
# `_min_max`.
#
# ct_6's answer is a node ALREADY IN THE ARENA, so nothing is interned. `or_casted` is an
# `is_any` of two alternatives, so there are TWO arms and `c` is bound in each; they never
# meet, so no identity check is emitted.
#
# THE PATTERN IS THE CLAIM, and giving the body an ELSE arm makes the rule a catch-all.
# MEASURED: with an else arm the answer's src op sequence was ".58.58" (the MSTACK) and
# `ct8d_srcops` was 0; with the claim in place it is ".58" and `ct8d_srcops` is 1.
def ct_6.of(alt: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match alt:
    case True{} : M.Hop{ar, M.mp_src0(ar, self)}
    case False{}: M.Hop{ar, 0}

def ct_6(+ar: O.Arena, +self: U32) -> M.Hop:
  ct_6.of(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{}), ar, self)

# `UPat.cvar().or_casted()` -- the op is CONST for the bare arm and CAST for the
# wrapped one, and the CAST arm requires EXACTLY one src.
def ct_6_casted(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsCAST{}), M.mp_nsrc_is(ar, self, 1))

def rf_ix_1src(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsINDEX{}), M.mp_nsrc_ge(ar, self, 1))

def ct_6_pat(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(rf_ix_1src(ar, self),
           Bool.or(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{}),
                   ct_6_casted(ar, M.mp_src0(ar, self))))

# ct_4: `remove_noop_bufferize` -- rangeify.py:104-106. The CLAIM is ported and CORRECTED;
# the ANSWER is the wall. `UPat(Ops.INDEX, name="idx").f(Ops.STAGE, ...)` REBUILDS the
# pattern with the STAGE at the ROOT and the INDEX as its src[0], so the node under
# examination IS `b2`, `idx` is `self.src[0]`, and the first line is `eq_u32` on two
# `src_from(1)` lists -- one on the STAGE and one on the INDEX.
#
# MEASURED, LIVE, and this is the rule the table used to make unfireable:
# `STAGE(INDEX(b4,r0), r0)` has `claim_n = 2` (tags 3 and 4) and answers the BUFFER,
# because `idx.src[0].shrink(((0,4),))` folds back to `idx.src[0]`. The MIRROR
# `INDEX(STAGE(b4,r0), r0)` has `claim_n = 0` and answers `None`, and the same STAGE with
# the tails differing answers `None` too. All three are rows.
#
# THE ANSWER IS A MOVEMENT OP -- `UOp.shrink` (ops.py:192) is `apply_movement_op`, the `W3`
# wall. `ct4a_ans` is therefore the WALL row: the port refuses where CPython rebuilds, and
# BOTH answers are recorded rather than the port's absence being dressed up as agreement.
def rf_stage_tail(+ar: O.Arena, b2: U32, idx: U32) -> Bool:
  O.eq_u32(O.Arena.src_from(ar, b2, 1), O.Arena.src_from(ar, idx, 1))

# `idx` is `b2.src[0]`, so the INNER op test reads the SRC and the `!=` compares
# the STAGE's tail against the INDEX's. The port had `b2` and `idx` the other way
# round, which is the same defect one level down.
def rf_same_tail(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, M.mp_src0(ar, self), O.OpsINDEX{}), rf_stage_tail(ar, self, M.mp_src0(ar, self)))

# `b2.shape` -- the `if b2.shape` of the second line. A STAGE's `_shape` is the
# fold's shape, and "empty" is the scalar case `()`.
def rf_shape_empty.go(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{Nil{}}: True{}
    case _: False{}

def rf_shape_empty(+fx: F.Folded, self: U32) -> Bool:
  rf_shape_empty.go(rf_shape(fx, self))

def ct_4.of(pat: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match pat:
    case True{} : M.Hop{ar, 0}
    case False{}: M.Hop{ar, 0}

def ct_4(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  ct_4.of(rf_same_tail(ar, self), ar, self)

# ct_3: `cleanup_dead_axes` -- rangeify.py:24-43. NOT PORTED. Two walls on the
# FIRST TWO LINES: `b.arg.removable` is a field of `BufferizeOpts`
# (indexing.py:60) which `ops.bend`'s `Arg` does not carry at all, and line 36
# tests `rng not in b.src[0].ranges`. The body also needs `b.reshape` and
# `b.expand`, which are movement ops over `b.shape`. MEASURED: it DOES fire on a
# STAGE with a removable `BufferizeOpts`, so this is a wall and not a liveness
# question -- see the note in `.agents/slop/rf-ct-oracle.txt` section 1.
def ct_3(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop: M.Hop{ar, 0}

# ct_5: `b.const_like(c.val)` -- rangeify.py:120. The CLAIM is ported here (it was
# absent, so the rule was ungated in the body as well as in the table); the ANSWER
# is walled. `const_like` (ops.py:603) is
# `UOp.const(self.dtype.const(val))` and then an `EXPAND` when `self._shape`
# disagrees with the const's, so it needs `DType.const` (dtype.py:79) AND
# `_mop`/`apply_movement_op` -- two of the three walls at once.
# MEASURED, LIVE, on BOTH arms: `STAGE(c4, r0)` and `STAGE(CAST(c4,half), r0)` each
# answer an `EXPAND` of two CONSTs, and `STAGE(b4, r0)` binds `c` zero times.
def ct_5_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}),
           Bool.and(M.mp_nsrc_ge(ar, self, 1),
                    Bool.or(M.mp_is(ar, M.mp_src0(ar, self), O.OpsCONST{}),
                            ct_6_casted(ar, M.mp_src0(ar, self)))))

def ct_5(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop: M.Hop{ar, 0}

# ct_7: the `after_all_invalid` arm -- rangeify.py:124-125. NOT PORTED:
# `after_all_invalid` (108-113) ends in
# `resolve(cast(UOp, prod(r.src[0] for r in s.ended_ranges)).eq(buf.numel()), False)` and
# that is `_min_max` (ops.py:1104) plus `UOp.numel` (a product over `max_shape`, which is
# `to_max_shape`, ops.py:1886). `ended_ranges` and `is_invalid` ARE ported, which is why
# `rf_ended` and `rf_invalid` are readers with no caller yet rather than omitted.
#
# MEASURED DEFECT IN CPYTHON, REPORTED AND NOT FIXED, because it is a fact about
# rangeify.py and not about this file. With an END that ends no RANGE, `ended_ranges` is
# empty, `prod()` over it is the PYTHON INT 1, and `1..eq(...)` raises
# `AttributeError: 'int' object has no attribute 'eq'`. So `after_all_invalid` CRASHES on
# an all-invalid AFTER with no ranges instead of answering, and the `cast(UOp, ...)` on
# line 113 is doing nothing. `.agents/slop/rf-ct-oracle.py` section 4 prints both shapes:
# `ct7_ix_after` RAISES, `ct7_ix_after_rng` answers `False`.
def ct_7(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop: M.Hop{ar, 0}

# ct_7's CLAIM, which is the one `ct_claim_n` needs: an INDEX whose src[0] is an
# AFTER. `early_reject` is `{AFTER}` -- the CHILD's op -- so the reject set ALREADY
# implies src[0] is an AFTER whenever there is exactly one src, and with two srcs
# it only implies one of them is. The claim is therefore not redundant with the
# reject set, which is the exception `M3`'s proof does not cover.
def ct_7_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsINDEX{}),
           Bool.and(M.mp_nsrc_ge(ar, self, 1),
                    M.mp_is(ar, M.mp_src0(ar, self), O.OpsAFTER{})))

# ct_8: the deviceless-MSTACK arm -- rangeify.py:127-128. THE CLAIM AND THE REBUILD are
# ported, and MEASURED LIVE. THE ROOT IS THE INDEX, so this is the ONE `.f()` entry whose
# body read the outer node correctly in the port as it stood, and `s` is the MSTACK's
# src[0]. It is gated now, which is the point. MEASURED:
#   INDEX(MSTACK(c4,c1))       claim_n 1  ->  INDEX, srcops=[CONST]
#   INDEX(MSTACK(c4,c1), r0)   claim_n 1  ->  INDEX, srcops=[CONST,RANGE]
#   MSTACK(c4,c1)              claim_n 0  ->  None     <- the mirror, outer/inner
#   INDEX(MSTACK(bufdev))      claim_n 1  ->  None     <- the device refusal
# and the rebuild keeps the INDEX's OWN arg, which is the `ct8r_arg`/`ct8r0_arg` row pair
# and is the arg gate the old fixture could not express.
def ct_8_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsINDEX{}),
           Bool.and(M.mp_nsrc_ge(ar, self, 1),
                    M.mp_is(ar, M.mp_src0(ar, self), O.OpsMSTACK{})))

def ct_8.of(devless: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match devless:
    case True{} : M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self,
                               List.append(&2, U32, [M.mp_src(ar, M.mp_src0(ar, self), 0)], O.Arena.src_from(ar, self, 1)))
    case False{}: M.Hop{ar, 0}

# `s.device is None` -- the fold's OUTER `Maybe`, and a `Some` device is NOT
# "no device". `dev_none_shape` used to answer `False{}` for every `S.Dev` and
# the `Bool.not` made every device-bearing node read as DEVICELESS, so `ct_8`
# fired on `INDEX(MSTACK(b4d, c1))` where CPython refuses. `ct8b_devnone` and
# `ct8b_none` are the two rows that see it, and the ONLY reason they exist is the
# outer-vs-inner fixture: every node the old fixture could reach had a deviceless
# `s`, so `rf_dev_is_none` was `True` on all of them and the inversion was
# invisible. A `S.Dev` in this port is a device NAME or a tuple of names, so a
# present device is always a present device and the answer is unconditional.
def dev_none_shape(d: S.Dev) -> Bool: True{}

def rf_dev_none(m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case Some{d}: Bool.not(dev_none_shape(d))
    case _: True{}

def rf_dev_is_none(+fx: F.Folded, +s: U32) -> Bool:
  rf_dev_none(rf_dev(fx, s))

# `ct_8` RE-CHECKS ITS OWN PATTERN, and that is not redundancy -- it is what Python's
# compiled matcher does and it is MEASURED to matter. `ct_8` was the one rule in this
# table whose body carried NO pattern test. M3 (`rf_early`'s subset test `and` -> `or`,
# which makes the reject test VACUOUS because `Bool.or(x, True{})` is `True{}` while
# `Bool.and(x, True{})` is `x`) then let tag 8 stop rejecting `ct7b` -- an INDEX whose
# AFTER is in src[1], not src[0] -- and `ct_8` rebuilt it. M36 removes the self-check and
# moves `ct7b_none` and `ct8b_none`; with the self-check in place M3 and M20b move nothing,
# and THAT is the real reason the reject sets are redundant.
def ct_8(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  ct_8.of(Bool.and(ct_8_claim(ar, self),
                   rf_dev_is_none(fx, M.mp_src(ar, M.mp_src0(ar, self), 0))), ar, self)

def ct_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: rf_mops_fb(ar)
    case 1: rf_mops_af(ar)
    case 2: rf_mops_en(ar)
    case 3: ct_3(fx, ar, self)
    case 4: ct_4(fx, ar, self)
    case 5: ct_5(fx, ar, self)
    case 6: ct_6(ar, self)
    case 7: ct_7(fx, ar, self)
    case 8: ct_8(fx, ar, self)
    case _: M.Hop{ar, 0}

def ct_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  ct_dispatch.go(tag, fx, ar, self)

def ct_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : ct_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def ct_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  ct_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

def ct_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: ct_scan(t, fx, self, M.hop_next(h, ct_try(fx, M.hop_ar(h), self, e)))

# THE TABLE. NINE entries, and the first THREE are `pm_mops`'s -- so tag 3 is
# rangeify.py:116 and every own tag is (line, tag - 3).
#
# EVERY `ops` SET BELOW IS THE ROOT'S, measured off `p.op`; every `rej` set is the
# CHILD's, measured off `p.early_reject`. That is the whole shape of the table and
# it is what the ROOT/SUB comment above the `MOPS_ROOT_*` defs is about.
def ct_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, MOPS_ROOT_FB(),  Nil{}},                   # prepare.py:78  FOREIGN
   O.PMEntry{1, MOPS_ROOT_AF(),  Nil{}},                   # prepare.py:80  FOREIGN
   O.PMEntry{2, MOPS_ROOT_EN(),  Nil{}},                   # prepare.py:82  FOREIGN
   O.PMEntry{3, [O.OpsSTAGE{}],   Nil{}},                   # 116  b -> cleanup_dead_axes
   O.PMEntry{4, [O.OpsSTAGE{}],   [O.OpsINDEX{}]},          # 118  INDEX.f(STAGE) -- root STAGE
   O.PMEntry{5, [O.OpsSTAGE{}],   Nil{}},                   # 120  CONST.f(STAGE) -- root STAGE
   O.PMEntry{6, [O.OpsINDEX{}],   Nil{}},                   # 122  INDEX(const) -> const
   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsAFTER{}]},          # 124  AFTER.f(INDEX) -- root INDEX
   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX) -- root INDEX

def ct_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  ct_scan(ct_table(), fx, self, M.Hop{ar, 0})

# TABLE 8: `pm_flatten_bufferize` -- rangeify.py:235-244. ONE RULE, the SMALLEST table in
# the file AND the only one whose body is a cross-file movement op.
#
# THE WALL IS `apply_movement_op` -- schedule/indexing.py:171, ANOTHER FILE -- and its
# RESHAPE arm is the worst of it: `UOp.sink(*rngs).simplify()` then two `substitute`
# calls. `simplify` is `graph_rewrite(self, symbolic)` (ops.py:513) and `substitute` is
# ops.py:532, so this one line needs the engine AND a graph walk. `get_single_element`
# (helpers.py:97) is free.
#
# WHAT IS PORTED is the FIRST LINE and the `any(...)` test, and the first line is the one
# that matters: `fb_stg2` is the node TWO rules claim (see `claim_ab_stg2`) and it is
# exactly this `len(x.src) == 2` that makes rule 3 SKIP there, so the first-wins
# discriminator in this file lives on it. The `any(...)` is ported EXACTLY because it reads
# no derived property -- two ops -- and it is the only part of `flatten_bufferize` that
# does.
def rf_fb_collapse(two: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match two:
    case True{} : M.Hop{ar, 0}
    case False{}: M.Hop{ar, 0}

# `len(x.src) == 2` -- the early return. `U32.is_eq` on the arity, not a `Nat`
# comparison, because `mp_nsrc` is a `U32`.
def rf_fb_two(+ar: O.Arena, +self: U32) -> Bool:
  U32.is_eq(M.mp_nsrc(ar, self), 2)

def rf_fb_sym.one(ok: Bool, acc: Bool) -> Bool:
  match ok:
    case True{} : True{}
    case False{}: acc
def rf_fb_symr(+ar: O.Arena, +r: U32) -> Bool:
  Bool.and(M.mp_is(ar, r, O.OpsRANGE{}), Bool.not(M.mp_is(ar, M.mp_src0(ar, r), O.OpsCONST{})))


def rf_fb_sym.go(+ar: O.Arena, rs: List<&2, U32>, acc: Bool) -> Bool:
  match rs:
    case Nil{} : acc
    case r <> t: rf_fb_sym.go(ar, t, rf_fb_sym.one(rf_fb_symr(ar, r), acc))


def rf_fb_sym(+ar: O.Arena, self: U32) -> Bool:
  rf_fb_sym.go(ar, O.Arena.src_from(ar, self, 1), False{})

def fb_0(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  rf_fb_collapse(rf_fb_two(ar, self), ar, self)

def fb_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: fb_0(fx, ar, self)
    case _: M.Hop{ar, 0}

def fb_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  fb_dispatch.go(tag, fx, ar, self)

def fb_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : fb_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def fb_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  fb_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

def fb_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: fb_scan(t, fx, self, M.hop_next(h, fb_try(fx, M.hop_ar(h), self, e)))

def fb_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSTAGE{}], Nil{}}]   # 244  x -> flatten_bufferize(x)

def fb_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  fb_scan(fb_table(), fx, self, M.Hop{ar, 0})

# TABLE 9: `to_define_global` -- rangeify.py:311-328. SEVEN RULES, and it is the one table
# where the port splits BY LINE, because the walls and the ported halves do not fall on the
# same lines.
#
# `dg_2`'s three-way CONDITION is fully ported -- `tag != ()` is `rf_tag_is_empty`,
# `addrspace is ALU` is `rf_addr_eq`, and `buf._shape is None` is the INNER `Maybe` of the
# fold's shape -- and only the `else debuf(...)` is missing. `dg_3` is fully ported
# INCLUDING its answer, because it is `lambda v: v`, a node already in the arena, gated on
# an `addrspace` the fold has. `dg_6` is `renumber_range`, ported above with the counter as
# a parameter. `dg_0` needs `UOp.buf_uop` (ops.py:925, a `while` with a MSELECT/MSTACK
# special case) and RAISES; `dg_1` needs `UOp.to_max_shape` (ops.py:1886) plus
# `buf.addrspace`/`buf.device`, which live in `BufferizeOpts`; `dg_4` needs
# `after.buf_uop`; `dg_5` is the clearest single wall in the file. `dg_3`'s reject set is
# `{PARAM}` -- the FOURTH of the file's six, and again already implied by the rule's own
# src-op test; `rej_dg3` is its row.
#
# dg_3's body is `lambda v: v if v.addrspace == AddrSpace.ALU else None` -- FULLY PORTED,
# and the only rule here whose body is a CONDITIONAL over a property the fold owns. The
# upstream comment is kept and it is the reason the rule exists: "ALU params are scalar
# symbolic values, not buffers." A symbolic scalar has no storage, so an INDEX of one IS
# the scalar.
def dg_3.of(alu: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match alu:
    case True{} : M.Hop{ar, M.mp_src0(ar, self)}
    case False{}: M.Hop{ar, 0}

def dg_3(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  dg_3.of(rf_addr_eq(fx, M.mp_src0(ar, self), S.Aalu{}), ar, self)

# dg_6: `renumber_range` -- rangeify.py:297, ported above. The dispatch threads
# the counter as a PARAMETER, which is the `ctx.range` wall; the gate feeds it
# CPython's value, and `ren7_*` is the row for a non-zero start.
def dg_6_of(n: U32) -> U32: n

def dg_6(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  rf_renumber(ar, self, dg_6_of(0))

# dg_5: `b.replace(arg=replace(b.arg, device=None))` -- rangeify.py:324. NOT
# PORTED, and this is the clearest single wall in the file: `b.arg` for a STAGE
# is a `BufferizeOpts` (indexing.py:57) and `ops.bend`'s `Arg` has NO constructor
# for it, so a STAGE carries `ANone` here and there is no `device` field to
# clear. The upstream comment is kept: "remove device from local BUFFERIZE".
def dg_5(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# dg_0: `check_buf_states` -- rangeify.py:305-309. NOT PORTED. It RAISES
# `RuntimeError` on a cycle and it needs `UOp.buf_uop` (ops.py:925). The port's
# answer is "no node" for the same reason `gs_0`'s is: an exception is not a
# value, and a rule that raises does not rewrite.
def dg_0(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# dg_1: `debuf` -- rangeify.py:283-290. NOT PORTED. `prod(buf.max_shape)` needs
# `UOp.to_max_shape` (ops.py:1886), `ParamArg(ctx.dg, ...)` needs the mutable
# `dg` counter, and `param.reshape(buf.max_shape)` is a movement op over a
# `max_shape` that does not exist in this port.
def dg_1(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# dg_2: the PARAM rule -- rangeify.py:315-316. The CONDITION is fully ported and
# the `debuf` it guards is not. The comment is kept: "Only storage parameters get
# kernel-local slots; scalar parameters retain their enclosing call's slots."
def rf_param_slot(ok: Bool, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : M.Hop{ar, 0}
    case False{}: M.Hop{ar, 0}

# the three-way condition, as three NAMED predicates so the gate can test each
# one alone -- and they are three rows because they are three different reasons
# a PARAM is not a slot, and only the first is about the tag.
#
# `buf.tag != ()` is `tag is not the empty tuple`. Python's default is `None`
# (ops.py:244) and `None != ()`, so an UNTAGGED PARAM takes the branch -- which
# is why `pm_add_param_range_tags` must run first.
def rf_param_tagged(+ar: O.Arena, +self: U32) -> Bool: rf_tag_is_empty(ar, self)

def rf_param_alu(+fx: F.Folded, +self: U32) -> Bool: rf_addr_eq(fx, self, S.Aalu{})

# `buf._shape is None` -- the INNER Maybe. The fold's OUTER Maybe means "the
# table has no entry", which is a DIFFERENT answer from "this node has no shape";
# `rf_param_shapeless` reads the inner, and a node the fold could not reach reads
# as shapeless, which is the safe direction.
def rf_param_shapeless.go(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{ds}: Bool.not(Nat.is_eq(List.length(&2, O.Sint, ds), 0n))
    case None{}  : True{}

def rf_param_shapeless(+fx: F.Folded, self: U32) -> Bool: rf_param_shapeless.go(rf_shape(fx, self))

def dg_2(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  rf_param_slot(Bool.or(rf_param_tagged(ar, self),
                        Bool.or(rf_param_alu(fx, self), rf_param_shapeless(fx, self))), ar, self)

# dg_4: `handle_after` -- rangeify.py:290-297. NOT PORTED: the guard
# `after.addrspace == AddrSpace.LOCAL` IS ported, and `after.buf_uop` is the
# wall. The comment is kept -- "NOTE: this is bottom up, so we only add it once"
# -- and it is about the mutable `ctx.map`, the other half of the same wall.
def dg_4(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# `after.addrspace == AddrSpace.LOCAL` -- the one conjunct of `handle_after`
# this port can read, kept as a named predicate so it is not mistaken for part
# of the missing body. `after_local` is the row.
def rf_after_local(+fx: F.Folded, +self: U32) -> Bool: rf_addr_eq(fx, self, S.ALocal{})

def dg_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: dg_0(fx, ar, self)
    case 1: dg_1(fx, ar, self)
    case 2: dg_2(fx, ar, self)
    case 3: dg_3(fx, ar, self)
    case 4: dg_4(fx, ar, self)
    case 5: dg_5(fx, ar, self)
    case 6: dg_6(fx, ar, self)
    case _: M.Hop{ar, 0}

def dg_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  dg_dispatch.go(tag, fx, ar, self)

def dg_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : dg_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def dg_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  dg_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

def dg_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: dg_scan(t, fx, self, M.hop_next(h, dg_try(fx, M.hop_ar(h), self, e)))

def dg_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSTORE{}],  Nil{}},                     # 312  x -> check_buf_states
   O.PMEntry{1, [O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsMSTACK{}, O.OpsMSELECT{}], Nil{}},  # 313  debuf
   O.PMEntry{2, [O.OpsPARAM{}],  Nil{}},                     # 315  PARAM -> debuf if a slot
   O.PMEntry{3, [O.OpsINDEX{}],  [O.OpsPARAM{}]},            # 319  INDEX(PARAM) -> PARAM
   O.PMEntry{4, [O.OpsAFTER{}],  Nil{}},                     # 321  after -> handle_after
   O.PMEntry{5, [O.OpsSTAGE{}],  Nil{}},                     # 324  b -> drop device
   O.PMEntry{6, [O.OpsRANGE{}],  Nil{}}]                     # 327  r -> renumber_range

def dg_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  dg_scan(dg_table(), fx, self, M.Hop{ar, 0})

# TABLE 10: `pm_limit_bufs` -- rangeify.py:170-198. ONE RULE, and the rule with the MOST wall
# behind it, because it counts DISTINCT BUFFERS over a whole graph. `_limit_bufs` is NOT
# PORTED. THE WALLS, in the order the body hits them:
#
# 1. `MAX_KERNEL_BUFFERS.value` is an ENV FLAG (helpers.py), so `rf_max_bufs` is a
#    PARAMETER and the gate feeds it CPython's value. `DEVICE_MAX_BUFS`'s `{"WEBGPU": 8}`
#    is a DEVICE-NAME table and a device here is `S.Dev`, a `U32` tag per name interned by
#    the runtime, so the same treatment applies and `rf_webgpu8` is the row that says the
#    table is a parameter and not a literal.
# 2. `visitor` is a PYTHON CLOSURE that both reads `ctx.buf_cache` and WRITES it --
#    `topovisit(visitor, ctx.buf_cache)` passes the dict in as the memo. So the port would
#    need a mutable dict threaded through a graph walk and returned, and Bend has neither.
#    The `frozenset` union over the srcs is a SET (MSELECT/MSTACK can contribute the same
#    buffer twice). `rf_bufset` is the empty answer: `lb_bufs` is 0, so
#    `len(bufs) > MAX_BUFS - 1` is `False` and the rule does not fire -- which is the SAFE
#    direction, because the alternative is bufferizing on a set it cannot compute.
# 3. The rewrite itself needs `s.ranges` (the `UOp.ranges` wall, twice: line 192 and the
#    `orig_ranges` on 194) and `s.substitute` (ops.py:532) and `BufferizeOpts`.
#
# The pdict key is `set.union(GroupOp.Binary, GroupOp.Ternary)`, so the key is 21 ops and
# `rf_binary_ternary` writes them out. `WHERE` and `MULACC` are in it because they are
# TERNARY ops (ops.py:171-172) even though nobody thinks of them as arithmetic.
def rf_webgpu8() -> U32: 8

# `set.union(GroupOp.Binary, GroupOp.Ternary)` -- the pdict key, twenty-one ops.
def rf_binary_ternary() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{},
   O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsSUB{},
   O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsMULACC{}, O.OpsWHERE{},
   O.OpsTHREEFRY{}]

# THE BUFFER SET, as the honest empty answer. `topovisit`'s `visitor` returns a
# `frozenset` per node and the dict is the memo, so the port cannot compute it;
# `rf_bufset` is where a `List<U32>` set would go and it is empty.
def rf_bufset(ar: O.Arena, self: U32) -> List<&2, U32>: Nil{}

# `len(bufs) > MAX_BUFS - 1` -- the ONLY line of the rule that this port can
# evaluate, and it evaluates it on an empty set, so the rule does not fire. The
# `-1` is the output buffer and upstream says so.
def Nat.to_bool(n: Nat) -> Bool:
  match n:
    case 0n: False{}
    case _: True{}

def rf_over_limit(bufs: List<&2, U32>, max_bufs: U32) -> Bool:
  Bool.and(U32.is_lt(max_bufs, 1), Nat.to_bool(0n))

# `Nat.to_bool(0n)` is `False` and it is here so the `MAX_BUFS` test is visible:
# `MAX_BUFS - 1` with `MAX_BUFS = 0` underflows a `U32`, and Python's `- 1` on
# `int` does not. The port therefore REFUSES to fire rather than wrap, which is
# the fail-safe direction and is why `lb_nofire` is a row.

def lb_0(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

def lb_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: lb_0(fx, ar, self)
    case _: M.Hop{ar, 0}

def lb_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  lb_dispatch.go(tag, fx, ar, self)

def lb_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : lb_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def lb_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  lb_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

def lb_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: lb_scan(t, fx, self, M.hop_next(h, lb_try(fx, M.hop_ar(h), self, e)))

def lb_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, rf_binary_ternary(), Nil{}}]   # 198  root -> _limit_bufs(ctx, root)

def lb_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  lb_scan(lb_table(), fx, self, M.Hop{ar, 0})

# TABLE 11: `pm_add_buffers` -- rangeify.py:364-272. TEN RULES, the BIGGEST composition in
# the file: `pm_mops + pm_flatten_bufferize + 6 own`, so three foreign rules, one of which
# (`pm_flatten_bufferize`) is THIS file's table 8 and IS ported.
#
# `ab_5` ({CAST}), `ab_6` ({RESHAPE}) and `ab_8` ({CONST}) are three of the file's six
# non-empty reject sets. All three are the op of the pattern's FIRST src and so are already
# implied by the rule's own op test; `rej_ab8` is the row for a MISSPELLED one.
#
# THE TWO RULES CLAIMING ONE NODE ARE TAGS 3 AND 4, and this is the first-wins row. `stg2`
# is a two-src `STAGE`; tag 3 (`UPat(Ops.STAGE, name="x")`) and tag 4
# (`UPat(Ops.STAGE, src=(UPat(), UPat(name="idx")), name="x")`) BOTH match it and they
# DISAGREE -- tag 3 returns `None` because `len(x.src) == 2` and tag 4 returns a node -- and
# `stg3`, a three-src STAGE, is claimed by tag 3 only because tag 4's src is a STRICT
# two-tuple. Measured by `.agents/slop/rf-claims.py`; the counts are `claim_ab_stg2` and
# `claim_ab_stg3`.
#
# `ab_7` is FULLY PORTED, body and all: it is a src map with one arm and no derived
# property. `ab_8` is FULLY PORTED too -- the `Invalid` arg test is `arg == Invalid` and
# `O.eq_arg` answers it exactly. `ab_9` is `remove_noop_afters`. `ab_4` is the big one and is
# NOT PORTED: `bufferize_to_store` (208-232) needs `x.commit_dtype()`,
# `sorted(idx.ranges, key=x.arg)` (the `ranges` wall plus a sort), `UOp.device_range_src`,
# a fresh `ParamArg` from `next(ctx)`, and a `buf.after(...)`/`store`/`end` chain.
def ab_7_src.go(is_rs: Bool, ar: O.Arena, x: U32) -> U32:
  match is_rs:
    case True{} : M.mp_src0(ar, x)
    case False{}: x

def ab_7_src(+ar: O.Arena, +x: U32) -> U32:
  ab_7_src.go(M.mp_is(ar, x, O.OpsRESHAPE{}), ar, x)

def ab_7.one(ar: O.Arena, x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, [ab_7_src(ar, x)])



def ab_7_srcs.go(+ar: O.Arena, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{} : acc
    case x <> t: ab_7_srcs.go(ar, t, ab_7.one(ar, x, acc))

def ab_7_srcs(+ar: O.Arena, self: U32) -> List<&2, U32>:
  ab_7_srcs.go(ar, M.mp_srcs(ar, self), Nil{})

def ab_7(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))

# ab_8: `lambda: UOp(Ops.NOOP)` for a STORE whose src[1] is a CONST of `Invalid`.
# FULLY PORTED, and `UPat(Ops.CONST, arg=Invalid)` compiles to
# `uop.src[1].op is CONST and uop.src[1].arg == Invalid` -- an ARG EQUALITY, so
# the test is `O.eq_arg` against `APy{CInvalid{}}` and it is exact. The comment
# is upstream's: "remove invalid writes".
def rf_is_invalid_const(ar: O.Arena, x: U32) -> Bool:
  O.eq_arg(M.mp_arg(ar, x), O.APy{O.CInvalid{}})

def ab_8.pat(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsSTORE{}),
           Bool.and(M.mp_nsrc_is(ar, self, 2),
                    Bool.and(M.mp_is(ar, M.mp_src(ar, self, 1), O.OpsCONST{}),
                             rf_is_invalid_const(ar, M.mp_src(ar, self, 1)))))

def ab_8.of(pat: Bool, +ar: O.Arena) -> M.Hop:
  match pat:
    case True{} : M.mp_hit(O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{}))
    case False{}: M.Hop{ar, 0}

def ab_8(+fx: F.Folded, +ar: O.Arena, self: U32) -> M.Hop:
  ab_8.of(ab_8.pat(ar, self), ar)

# ab_4: `bufferize_to_store` -- rangeify.py:253-232. NOT PORTED, and the comment block above
# it (200-206) is kept because it explains what the rule is FOR even though the body is
# absent:
#
#   # TODO: should BUFFERIZE look a lot more like STORE
#   # BUFFERIZE has device in arg
#   # BUFFERIZE doesn't have indexing, that's implied by the ranges it closes
#   # BUFFERIZE returns the BUFFER ready for INDEXing
#   # NOTE: this has been fixed up a bit
#
# `sorted(idx.ranges, key=lambda x: x.arg)` (211) is the `UOp.ranges` wall AND a sort by a
# TUPLE arg; `x.commit_dtype()` (210) is ops.py's committed-dtype walk;
# `UOp.device_range_src` (230) is P6; and `next(ctx)` is the mutable `itertools.count`.
# Its CLAIM -- a two-src STAGE -- is ported and it is the claim half of the
# two-rules-one-node fixture.
def ab_4(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# ab_4's CLAIM: `UPat(Ops.STAGE, src=(UPat(), UPat(name="idx")), name="x")` is a
# STRICT two-src STAGE. `ab_4_claim` is the row, and the contrast with
# `claim_ab_stg3` is the whole discriminator: a two-src STAGE is claimed here
# and a three-src one is not.
def ab_4_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsSTAGE{}), M.mp_nsrc_is(ar, self, 2))

# ab_5: the weak-cast INDEX arm -- rangeify.py:259-260. NOT PORTED as a rewrite
# (it is `u.replace(src=(buf,)+u.src[1:]).cast(u.dtype)`, and `u.dtype` is the
# fold's dtype while the CAST's own arg is what the pattern matched, so the
# rebuild needs the INDEX's dtype in a CAST's arg -- expressible, but the `buf`
# binding is `UPat.var` INSIDE a CAST and the value is `u.src[0].src[0]`, which
# is the same shape as `ct_6` and does work). What is ported is the CLAIM: a
# one-src CAST of a weak dtype under an INDEX.
def ab_5_cast(+fx: F.Folded, +ar: O.Arena, +c: U32) -> Bool:
  Bool.and(M.mp_is(ar, c, O.OpsCAST{}),
           Bool.and(M.mp_nsrc_is(ar, c, 1), rf_weak_dt(fx, c)))

def ab_5_claim(+fx: F.Folded, +ar: O.Arena, +self: U32) -> Bool:
  Bool.and(M.mp_is(ar, self, O.OpsINDEX{}),
           Bool.and(M.mp_nsrc_ge(ar, self, 1), ab_5_cast(fx, ar, M.mp_src0(ar, self))))


def ab_5(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# ab_6: `m.replace(src=tuple(x.src[0].base for x in m.src)).reshape(m.shape)` --
# rangeify.py:263-264. NOT PORTED: `x.src[0].base` is `UOp.base` (ops.py:785)
# which `fold.bend` HAS as `F.UOp.base`, and `.reshape(m.shape)` is a movement op
# over a `Shape` rather than a list of `Sint`. The comment is upstream's: "move
# RESHAPEs through MSELECT/MSTACK".
def ab_6(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}

# ab_9: `remove_noop_afters` -- rangeify.py:269, ported above as a def. The
# table entry is the ONLY thing new here.
def ab_9(+fx: F.Folded, ar: O.Arena, +self: U32) -> M.Hop: rf_self(remove_noop_afters(ar, self), self)

def ab_dispatch.go(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  match tag:
    case 0: rf_mops_fb(ar)
    case 1: rf_mops_af(ar)
    case 2: rf_mops_en(ar)
    case 3: fb_0(fx, ar, self)
    case 4: ab_4(fx, ar, self)
    case 5: ab_5(fx, ar, self)
    case 6: ab_6(fx, ar, self)
    case 7: ab_7(fx, ar, self)
    case 8: ab_8(fx, ar, self)
    case 9: ab_9(fx, ar, self)
    case _: M.Hop{ar, 0}

def ab_dispatch(tag: U32, +fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  ab_dispatch.go(tag, fx, ar, self)

def ab_try.of(ok: Bool, tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:
  match ok:
    case True{} : ab_dispatch(tag, fx, ar, self)
    case False{}: M.Hop{ar, 0}

def ab_try(+fx: F.Folded, +ar: O.Arena, +self: U32, +e: O.PMEntry) -> M.Hop:
  ab_try.of(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), O.PMEntry.tag(e), fx, ar, self)

def ab_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: M.Hop) -> M.Hop:
  match rs:
    case Nil{}: h
    case e <> t: ab_scan(t, fx, self, M.hop_next(h, ab_try(fx, M.hop_ar(h), self, e)))

# THE TABLE. TEN entries: three foreign, then `pm_flatten_bufferize` (this file's
# table 8, and the ONLY foreign-prefix entry with a ported body), then six own.
def ab_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, MOPS_ROOT_FB(), Nil{}},                        # prepare.py:78  FOREIGN
   O.PMEntry{1, MOPS_ROOT_AF(), Nil{}},                        # prepare.py:80  FOREIGN
   O.PMEntry{2, MOPS_ROOT_EN(), Nil{}},                        # prepare.py:82  FOREIGN
   O.PMEntry{3, [O.OpsSTAGE{}], Nil{}},                      # 244  pm_flatten_bufferize
   O.PMEntry{4, [O.OpsSTAGE{}], Nil{}},                      # 255  x -> bufferize_to_store
   O.PMEntry{5, [O.OpsINDEX{}], [O.OpsCAST{}]},              # 259  INDEX(weak CAST)
   O.PMEntry{6, [O.OpsMSELECT{}, O.OpsMSTACK{}], [O.OpsRESHAPE{}]},  # 263  reshape through
   O.PMEntry{7, [O.OpsCALL{}], Nil{}},                       # 267  drop RESHAPEs
   O.PMEntry{8, [O.OpsSTORE{}], [O.OpsCONST{}]},            # 270  invalid write -> NOOP
   O.PMEntry{9, [O.OpsAFTER{}], Nil{}}]                      # 271  remove_noop_afters

def ab_rewrite(+fx: F.Folded, ar: O.Arena, self: U32) -> M.Hop:
  ab_scan(ab_table(), fx, self, M.Hop{ar, 0})

# THE GATE. Every row is DERIVED FROM PYTHON by `.agents/slop/rf-rows.py`, so a row here can
# be WRONG rather than merely restate this file. `1`/`0` is a Bool, and a `0` that is a
# positive claim is a real answer (`ren_none` is a `True` result meaning "no node"), not a
# failure.
#
# THE FIXTURE, and what each node is FOR. `b4` and `bx` are TWO GLOBAL BUFFERs of 4 int32
# with different slots, so `STORE(b4, bx)` is a two-src STORE whose srcs are DIFFERENT nodes
# -- which is the whole point of `rb_diff`, and is why the fixture needs two buffers and not
# one. `stg2` is a two-src STAGE and `stg3` a three-src one; they differ in exactly the
# property `flatten_bufferize` (236) tests, and `stg2` is ALSO the node two `pm_add_buffers`
# rules claim. `after1`/`after`/`afterk` are an AFTER with one removable dep, with two, and
# with none, so `remove_noop_afters` has all three of its answers in one arena. `b2u` is
# `Bool -> U32` because `Bool` will not `U32.show`, and it is used by every row, which is why
# it sits above the fixture rather than inside `main`.
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def b2u(b: Bool) -> U32:
  match b:
    case True{} : 1
    case False{}: 0

# THE FIXTURE, as one `Data` record: the fold and the node indices. `Folded` is
# `Data`, so the record is copyable and every row can read it without `+`; the
# alternative -- rebuilding the arena per row -- is not expressible, because a
# fixture is a CHAIN of `+`-consumed arenas.
type G is Data:
  G{fx: F.Folded, ix: List<&2, U32>}

def G.fx(g: G) -> F.Folded:
  match g:
    case G{fx, ix}: fx

def G.ix(g: G) -> List<&2, U32>:
  match g:
    case G{fx, ix}: ix

def G.at(ix: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ix, n), 0)

def G.n(g: G, n: Nat) -> U32:
  G.at(G.ix(g), n)

def g_ar(g: G) -> O.Arena: F.Folded.ar(G.fx(g))
def g_tb(g: G) -> F.Table: F.Folded.t(G.fx(g))

# `ParamArg(slot, int32, size=n, addrspace=GLOBAL)` -- the shape a BUFFER's
# `size` gives it (`(n,)`), which is what makes `b4`'s shape `(4,)`.
def g_psize(slot: U32, n: U32, a: S.Addr) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{n}, None{}, None{}, None{}, a, None{}, False{},
             None{}, None{}, False{}, None{}}

# A `ParamArg` WITH A DEVICE, which is the only thing `s.device is None` reads.
# `fold.bend`'s `device_of.param` is how a BUFFER's device is answered, and this
# is the one fixture node that gives it a `Some` to read.
def g_pdev(slot: U32, n: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{n}, None{}, None{}, None{}, S.AGlobal{},
             Some{S.D1{1}}, False{}, None{}, None{}, False{}, None{}}
def g_buf.slot(slot: U32, n: U32, a: S.Addr, s: U32) -> O.Arena: O.Arena.empty()


def g_buf(slot: U32, n: U32, a: S.Addr) -> O.Arena:
  g_buf.slot(slot, n, a, 0)


def g_c(v: H.I64) -> O.Const: O.CInt{v}

# THE FIXTURE. Built in one chain, one `+` per node, because `Arena` is affine
# and every intermediate arena is a value. The node order is the order they are
# needed, not the graph order, and `lay` is the row that pins the count.
def g() -> G:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  +c4 = O.UOp.const(O.Found.ar(c2), O.CInt{H.i64_of_i32(4)})
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "0")
  +b4 = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)],
                  O.AParam{g_psize(0, 4, S.AGlobal{})}, O.TNone{})
  +bx = O.UOp.new(O.Found.ar(b4), O.OpsBUFFER{}, [O.Found.i(sp)],
                  O.AParam{g_psize(1, 4, S.AGlobal{})}, O.TNone{})
  +r0 = O.UOp.range_end(O.Found.ar(bx), O.Found.i(c4), [0], O.AXIS_WEAK{})
  +r1 = O.UOp.range_end(O.Found.ar(r0), O.Found.i(c4), [1], O.AXIS_WEAK{})
  +n0 = O.UOp.new(O.Found.ar(r1), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  +nx = O.UOp.new(O.Found.ar(n0), O.OpsNOOP{}, [O.Found.i(c0)], O.ANone{}, O.TNone{})
  +e0 = O.UOp.new(O.Found.ar(nx), O.OpsEND{}, [O.Found.i(n0)], O.ANone{}, O.TNone{})
  +e1 = O.UOp.new(O.Found.ar(e0), O.OpsEND{}, [O.Found.i(nx)], O.ANone{}, O.TNone{})
  +ek = O.UOp.new(O.Found.ar(e1), O.OpsEND{}, [O.Found.i(b4)], O.ANone{}, O.TNone{})
  +af1 = O.UOp.new(O.Found.ar(ek), O.OpsAFTER{}, [O.Found.i(b4), O.Found.i(e0)], O.ANone{}, O.TNone{})
  +af = O.UOp.new(O.Found.ar(af1), O.OpsAFTER{},
                  [O.Found.i(b4), O.Found.i(e0), O.Found.i(e1), O.Found.i(ek)], O.ANone{}, O.TNone{})
  +afk = O.UOp.new(O.Found.ar(af), O.OpsAFTER{}, [O.Found.i(b4), O.Found.i(ek)], O.ANone{}, O.TNone{})
  +st2 = O.UOp.new(O.Found.ar(afk), O.OpsSTAGE{}, [O.Found.i(b4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +st3 = O.UOp.new(O.Found.ar(st2), O.OpsSTAGE{},
                   [O.Found.i(b4), O.Found.i(r0), O.Found.i(r1)], O.ANone{}, O.TNone{})
  +ixs = O.UOp.new(O.Found.ar(st3), O.OpsINDEX{}, [O.Found.i(st2), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ixc = O.UOp.new(O.Found.ar(ixs), O.OpsINDEX{}, [O.Found.i(c4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +rs = O.UOp.new(O.Found.ar(ixc), O.OpsRESHAPE{}, [O.Found.i(b4), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +rsi = O.UOp.new(O.Found.ar(rs), O.OpsRESHAPE{}, [O.Found.i(ixs), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +sh0 = O.UOp.new(O.Found.ar(rsi), O.OpsSHRINK{},
                   [O.Found.i(b4), O.Found.i(c0), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +sh1 = O.UOp.new(O.Found.ar(sh0), O.OpsSHRINK{},
                   [O.Found.i(b4), O.Found.i(c1), O.Found.i(c2)], O.ANone{}, O.TNone{})
  +cst = O.UOp.new(O.Found.ar(sh1), O.OpsCONST{}, Nil{}, O.APy{O.CInvalid{}}, O.TNone{})
  +mst = O.UOp.new(O.Found.ar(cst), O.OpsMSTACK{}, [O.Found.i(sh1), O.Found.i(sh0)], O.ANone{}, O.TNone{})
  +cli = O.UOp.new(O.Found.ar(mst), O.OpsCALL{}, [O.Found.i(ixs), O.Found.i(rs)], O.ANone{}, O.TNone{})
  +cls = O.UOp.new(O.Found.ar(cli), O.OpsCALL{}, [O.Found.i(sh1), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +clm = O.UOp.new(O.Found.ar(cls), O.OpsCALL{}, [O.Found.i(mst), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +msr = O.UOp.new(O.Found.ar(clm), O.OpsMSTACK{}, [O.Found.i(rs), O.Found.i(rs)], O.ANone{}, O.TNone{})
  +sti = O.UOp.new(O.Found.ar(msr), O.OpsSTORE{}, [O.Found.i(b4), O.Found.i(cst)], O.ANone{}, O.TNone{})
  +sts = O.UOp.new(O.Found.ar(sti), O.OpsSTORE{}, [O.Found.i(b4), O.Found.i(b4)], O.ANone{}, O.TNone{})
  +std = O.UOp.new(O.Found.ar(sts), O.OpsSTORE{}, [O.Found.i(b4), O.Found.i(bx)], O.ANone{}, O.TNone{})
  +pg = O.UOp.new(O.Found.ar(std), O.OpsPARAM{}, Nil{},
                  O.AParam{g_psize(2, 4, S.AGlobal{})}, O.TNone{})
  +pa = O.UOp.new(O.Found.ar(pg), O.OpsPARAM{}, Nil{},
                  O.AParam{g_psize(3, 4, S.Aalu{})}, O.TNone{})
  +ipg = O.UOp.new(O.Found.ar(pa), O.OpsINDEX{}, [O.Found.i(pg)], O.ANone{}, O.TNone{})
  +ipa = O.UOp.new(O.Found.ar(ipg), O.OpsINDEX{}, [O.Found.i(pa)], O.ANone{}, O.TNone{})
  +r0t = rf_rtag.found(O.Found.ar(ipa), O.Found.i(r0), rf_empty_tag())
  +pgt = rf_rtag.found(O.Found.ar(r0t), O.Found.i(pg), rf_empty_tag())
  +pat = rf_rtag.found(O.Found.ar(pgt), O.Found.i(pa), rf_empty_tag())
  # AFTN: an AFTER whose BODY is itself a dead dep AND which has a second
  # removable dep. `remove_noop_afters` filters `src[1:]` only, so Python removes
  # the END, is left with the body alone, and returns `src[0]` -- a node already in
  # the arena. A port that filters `src[0]` too removes BOTH, is left with
  # nothing, and rebuilds an AFTER with no srcs. That is the subtlety three raf
  # rows exist for, and this is the only node in the fixture that exercises it.
  +aftn = O.UOp.new(O.Found.ar(pat), O.OpsAFTER{}, [O.Found.i(n0), O.Found.i(e0)], O.ANone{}, O.TNone{})
  # AFTK: the SAME shape with nothing removable, so it is the negative of AFTN.
  +aftk = O.UOp.new(O.Found.ar(aftn), O.OpsAFTER{}, [O.Found.i(b4), O.Found.i(ek)], O.ANone{}, O.TNone{})
  # STC0: a two-src STORE of a VALID constant. `ab_8`'s pattern is
  # `arg == Invalid`, so this is the node that separates "is a CONST" from "is the
  # Invalid CONST" -- the difference `sts` and `std` cannot make, because neither
  # has a CONST as src[1].
  +stc0 = O.UOp.new(O.Found.ar(aftk), O.OpsSTORE{}, [O.Found.i(b4), O.Found.i(c0)], O.ANone{}, O.TNone{})
  # RSAF: a RESHAPE over an AFTER, so `rf_is_bufid5`'s SIX-op set is tested on a
  # member other than BUFFER -- `rs` and `rsi` only ever test BUFFER.
  +rsaf = O.UOp.new(O.Found.ar(stc0), O.OpsRESHAPE{}, [O.Found.i(af), O.Found.i(c4)], O.ANone{}, O.TNone{})
# CLIK and CLIK0: the CALLI shape (CALL(IXSTG,RS)) carrying a REAL `Kernel` arg, and
# its `ANone` twin. THEY ARE THE ONLY TWO NODES THAT MAKE AN ARG VISIBLE. Every other
# node the four `mp_replace` rules can reach -- an AFTER, an MSTACK, a CALL -- is given
# `ANone` by this fixture, and an AFTER's and an MSTACK's arg is `None` in CPython too
# (measured: `raf_after_arg_is_none = 1`, `mstack_arg_is_none = 1`). So a row of the
# shape `eq_arg(rebuilt_arg, original_arg)` on any of them degenerates to
# `eq_arg(ANone, ANone)` -- TRUE whether the port preserves the arg or hardcodes
# `ANone`, which is exactly the mistake that satisfied the type checker when
# `mp_replace` gained its `arg` parameter. A CALL's arg is a Kernel, so CLIK is the node
# that separates the two, and CLIK0 is the negative one row from it at the same shape.
  +clik = O.UOp.new(O.Found.ar(rsaf), O.OpsCALL{}, [O.Found.i(ixs), O.Found.i(rs)],
                   O.AKernel{O.KernelInfo.of()}, O.TNone{})
  +clik0 = O.UOp.new(O.Found.ar(clik), O.OpsCALL{}, [O.Found.i(ixs), O.Found.i(rs)],
                    O.ANone{}, O.TNone{})
# THE OUTER-VS-INNER FIXTURES, and why the old fixture could not ask the question.
# Every node below exists to make ONE thing askable: WHICH OP IS AT THE INNER VS THE
# OUTER POSITION. A `.f()` chain puts the op handed to `f` at the ROOT, so a table that
# carries the CHILD's op keys the mirror of the node the body reads -- and a fixture of
# AFTERs, MSTACKs and CALLs with `ANone` args cannot see it, because no node in it has
# both shapes. `UOp` does NOT type-check `arg` against `op` (measured), so the
# discriminating shapes build without complaint and an INDEX can carry a `Range` arg
# that survives the rebuild.
#
# B4D   BUFFER with a `ParamArg.device`     what `s.device is None` reads
# IXB4  INDEX(B4, R0)                        the CHILD ct_4 needs
# CT4A  STAGE(IXB4, R0)       CLAIMED: root STAGE, child INDEX, tails EQUAL
# CT4D  STAGE(IXB4, R1)       the same with the tails DIFFERENT: the `!=`
# CT4B  INDEX(STG2, R0)       THE MIRROR: root INDEX, child STAGE. Same two
#                            ops, same two nodes, opposite order. py: claim 0.
# CT5C  STAGE(C4, R0)         ct_5 arm one: the child is a CONST
# CT5K  STAGE(CAST(C4), R0)   ct_5 arm two: the child is a CAST of a CONST
# CT5B  STAGE(B4, R0)         the negative: the child is neither
# MSTC  MSTACK(C4, C1)        ct_8's `s`, DEVICELESS
# MSTB  MSTACK(B4D, C1)       ct_8's `s`, carrying a DEVICE: the refusal
# CT8D  INDEX(MSTC)           ct_8 CLAIMED: root INDEX, child MSTACK
# CT8B  INDEX(MSTB)           the `s.device is None` refusal, one node from it
# CT8R  INDEX(MSTC, R0) with an `ARange` arg   the rebuild, with the ARG
#                            visible: `UOp` accepts it and `replace` keeps it
# CT8R0 the SAME node with `ANone`             the negative one row from it
# CT7A  INDEX(AFTER)          ct_7's claim: root INDEX, child AFTER
  +bd = O.UOp.new(O.Found.ar(clik0), O.OpsBUFFER{}, [O.Found.i(sp)],
                  O.AParam{g_pdev(4, 9)}, O.TNone{})
  +ixb4 = O.UOp.new(O.Found.ar(bd), O.OpsINDEX{}, [O.Found.i(b4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ct4a = O.UOp.new(O.Found.ar(ixb4), O.OpsSTAGE{}, [O.Found.i(ixb4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ct4d = O.UOp.new(O.Found.ar(ct4a), O.OpsSTAGE{}, [O.Found.i(ixb4), O.Found.i(r1)], O.ANone{}, O.TNone{})
  +ct4b = O.UOp.new(O.Found.ar(ct4d), O.OpsINDEX{}, [O.Found.i(st2), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ct5k0 = O.UOp.new(O.Found.ar(ct4b), O.OpsCAST{}, [O.Found.i(c4)], O.ADt{S.half()}, O.TNone{})
  +ct5c = O.UOp.new(O.Found.ar(ct5k0), O.OpsSTAGE{}, [O.Found.i(c4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ct5k = O.UOp.new(O.Found.ar(ct5c), O.OpsSTAGE{}, [O.Found.i(ct5k0), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +ct5b = O.UOp.new(O.Found.ar(ct5k), O.OpsSTAGE{}, [O.Found.i(b4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +mstc = O.UOp.new(O.Found.ar(ct5b), O.OpsMSTACK{}, [O.Found.i(c4), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +mstb = O.UOp.new(O.Found.ar(mstc), O.OpsMSTACK{}, [O.Found.i(bd), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +ct8d = O.UOp.new(O.Found.ar(mstb), O.OpsINDEX{}, [O.Found.i(mstc)], O.ANone{}, O.TNone{})
  +ct8b = O.UOp.new(O.Found.ar(ct8d), O.OpsINDEX{}, [O.Found.i(mstb)], O.ANone{}, O.TNone{})
  +ct8r = O.UOp.new(O.Found.ar(ct8b), O.OpsINDEX{}, [O.Found.i(mstc), O.Found.i(r0)],
                    O.ARange{[7], O.AXIS_LOOP{}}, O.TNone{})
  +ct8r0 = O.UOp.new(O.Found.ar(ct8r), O.OpsINDEX{}, [O.Found.i(mstc), O.Found.i(r0)],
                     O.ANone{}, O.TNone{})
  +ct7a = O.UOp.new(O.Found.ar(ct8r0), O.OpsINDEX{}, [O.Found.i(af)], O.ANone{}, O.TNone{})
# RGD / RGT -- a RANGE whose AxisType is NOT `AXIS_WEAK`, plus its `rtag(())`.
# EVERY RANGE in the fixture up to here is AXIS_WEAK, so `rf_renumber`'s "rebuild
# the AxisType" and "read it off the node" are the SAME FUNCTION over the rest of the
# fixture and mutation M12 moved nothing. One node with a different axis type
# separates them, which is what `ren_axis_out_dev` is for.
# CT7B -- an INDEX whose src[0] is a RANGE and whose src[1] IS an AFTER. The
# `early_reject` of tag 7 is `{AFTER}` and `ler` is `{RANGE, AFTER}`, so the SET TEST
# is satisfied by an AFTER ANYWHERE, while the PATTERN needs it at src[0]. This is
# the only node in the fixture where `ct_7`'s own body test is not implied by its
# reject set, so it is what makes mutation M30 sharp: with `ct_src.of`'s
# `case 7: True{}` the count reads 2 and with the test it reads 1.
  +ct7b = O.UOp.new(O.Found.ar(ct7a), O.OpsINDEX{}, [O.Found.i(r0), O.Found.i(af)], O.ANone{}, O.TNone{})
  +rgd = O.UOp.range_end(O.Found.ar(ct7b), O.Found.i(c4), [2], O.AXIS_DEVICE{})
  +rgt = rf_rtag.found(O.Found.ar(rgd), O.Found.i(rgd), rf_empty_tag())
  G{F.folded(O.Found.ar(rgt)),
    [O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c4), O.Found.i(sp),
     O.Found.i(b4), O.Found.i(bx), O.Found.i(r0), O.Found.i(r1), O.Found.i(n0),
     O.Found.i(nx), O.Found.i(e0), O.Found.i(e1), O.Found.i(ek), O.Found.i(af1),
     O.Found.i(af), O.Found.i(afk), O.Found.i(st2), O.Found.i(st3), O.Found.i(ixs),
     O.Found.i(ixc), O.Found.i(rs), O.Found.i(rsi), O.Found.i(sh0), O.Found.i(sh1),
     O.Found.i(cst), O.Found.i(mst), O.Found.i(cli), O.Found.i(cls), O.Found.i(clm),
     O.Found.i(msr), O.Found.i(sti), O.Found.i(sts), O.Found.i(std), O.Found.i(pg),
     O.Found.i(pa), O.Found.i(ipg), O.Found.i(ipa), O.Found.i(r0t), O.Found.i(pgt),
     O.Found.i(pat), O.Found.i(aftn), O.Found.i(aftk), O.Found.i(stc0),
     O.Found.i(rsaf), O.Found.i(clik), O.Found.i(clik0),
     O.Found.i(bd), O.Found.i(ixb4), O.Found.i(ct4a), O.Found.i(ct4d),
     O.Found.i(ct4b), O.Found.i(ct5k0), O.Found.i(ct5c), O.Found.i(ct5k),
     O.Found.i(ct5b), O.Found.i(mstc), O.Found.i(mstb), O.Found.i(ct8d),
     O.Found.i(ct8b), O.Found.i(ct8r), O.Found.i(ct8r0), O.Found.i(ct7a),
     O.Found.i(ct7b), O.Found.i(rgd), O.Found.i(rgt)]}

# THE NODE NAMES, so a row reads as a claim about a thing and not an index.
#  0 C0  1 C1  2 C2  3 C4  4 SPECIAL  5 B4  6 BX  7 R0  8 R1
#  9 NOOP(0 srcs)  10 NOOP(C0)  11 END(NOOP0)  12 END(NOOPc0)  13 END(B4)
# 14 AFTER1=AFTER(B4,END(NOOP0))  15 AFTER  16 AFTERK
# 17 STG2=STAGE(B4,R0)  18 STG3=STAGE(B4,R0,R1)
# 19 IXSTG=INDEX(STG2,R0)  20 IXC=INDEX(C4,R0)
# 21 RS=RESHAPE(B4,C4)  22 RSI=RESHAPE(IXSTG,C4)
# 23 SH0=SHRINK(B4,C0,C4)  24 SH1=SHRINK(B4,C1,C2)  25 INVALID
# 26 MST=MSTACK(SH1,SH0)  27 CALLI=CALL(IXSTG,RS)  28 CALLS=CALL(SH1,C0)
# 29 CALLM=CALL(MST,C0)  30 MSRS=MSTACK(RS,RS)  31 STINV=STORE(B4,Invalid)
# 32 SELFSTORE=STORE(B4,B4)  33 DIFFSTORE=STORE(B4,BX)
# 34 PG=PARAM(2,GLOBAL)  35 PA=PARAM(3,ALU)  36 IXPG  37 IXPA
# 38 R0T=R0.rtag(())  39 PGT  40 PAT
def g_c0(g: G) -> U32: G.n(g, 0n)
def g_n0(g: G) -> U32: G.n(g, 9n)
def g_nx(g: G) -> U32: G.n(g, 10n)
def g_e0(g: G) -> U32: G.n(g, 11n)
def g_e1(g: G) -> U32: G.n(g, 12n)
def g_ek(g: G) -> U32: G.n(g, 13n)
def g_af1(g: G) -> U32: G.n(g, 14n)
def g_af(g: G) -> U32: G.n(g, 15n)
def g_afk(g: G) -> U32: G.n(g, 16n)
def g_st2(g: G) -> U32: G.n(g, 17n)
def g_st3(g: G) -> U32: G.n(g, 18n)
def g_ixs(g: G) -> U32: G.n(g, 19n)
def g_ixc(g: G) -> U32: G.n(g, 20n)
def g_rs(g: G) -> U32: G.n(g, 21n)
def g_rsi(g: G) -> U32: G.n(g, 22n)
def g_sh0(g: G) -> U32: G.n(g, 23n)
def g_sh1(g: G) -> U32: G.n(g, 24n)
def g_mst(g: G) -> U32: G.n(g, 26n)
def g_cli(g: G) -> U32: G.n(g, 27n)
def g_cls(g: G) -> U32: G.n(g, 28n)
def g_clm(g: G) -> U32: G.n(g, 29n)
def g_msr(g: G) -> U32: G.n(g, 30n)
def g_sti(g: G) -> U32: G.n(g, 31n)
def g_sts(g: G) -> U32: G.n(g, 32n)
def g_std(g: G) -> U32: G.n(g, 33n)
def g_pg(g: G) -> U32: G.n(g, 34n)
def g_pa(g: G) -> U32: G.n(g, 35n)
def g_ipg(g: G) -> U32: G.n(g, 36n)
def g_ipa(g: G) -> U32: G.n(g, 37n)
def g_r0(g: G) -> U32: G.n(g, 7n)
def g_r0t(g: G) -> U32: G.n(g, 38n)
def g_pgt(g: G) -> U32: G.n(g, 39n)
def g_pat(g: G) -> U32: G.n(g, 40n)
def g_aftn(g: G) -> U32: G.n(g, 41n)
def g_aftk(g: G) -> U32: G.n(g, 42n)
def g_stc0(g: G) -> U32: G.n(g, 43n)
def g_rsaf(g: G) -> U32: G.n(g, 44n)
#  45 CLIK=CALL(IXSTG,RS) with a REAL Kernel arg  46 CLIK0, the same with ANone
def g_clik(g: G) -> U32: G.n(g, 45n)
def g_clik0(g: G) -> U32: G.n(g, 46n)
def g_b4(g: G) -> U32: G.n(g, 5n)
def g_bx(g: G) -> U32: G.n(g, 6n)
#  47 B4D=BUFFER with a DEVICE   48 IXB4=INDEX(B4,R0)
#  49 CT4A=STAGE(IXB4,R0)  50 CT4D=STAGE(IXB4,R1)  51 CT4B=INDEX(STG2,R0)
#  52 CT5K0=CAST(C4,half) 53 CT5C=STAGE(C4,R0)  54 CT5K=STAGE(CAST(C4),R0)
#  55 CT5B=STAGE(B4,R0)    56 MSTC=MSTACK(C4,C1)  57 MSTB=MSTACK(B4D,C1)
#  58 CT8D=INDEX(MSTC)     59 CT8B=INDEX(MSTB)
#  60 CT8R=INDEX(MSTC,R0) with an ARange arg   61 CT8R0, the same with ANone
#  62 CT7A=INDEX(AFTER)
def g_b4d(g: G) -> U32: G.n(g, 47n)
def g_ixb4(g: G) -> U32: G.n(g, 48n)
def g_ct4a(g: G) -> U32: G.n(g, 49n)
def g_ct4d(g: G) -> U32: G.n(g, 50n)
def g_ct4b(g: G) -> U32: G.n(g, 51n)
def g_ct5k0(g: G) -> U32: G.n(g, 52n)
def g_ct5c(g: G) -> U32: G.n(g, 53n)
def g_ct5k(g: G) -> U32: G.n(g, 54n)
def g_ct5b(g: G) -> U32: G.n(g, 55n)
def g_mstc(g: G) -> U32: G.n(g, 56n)
def g_mstb(g: G) -> U32: G.n(g, 57n)
def g_ct8d(g: G) -> U32: G.n(g, 58n)
def g_ct8b(g: G) -> U32: G.n(g, 59n)
def g_ct8r(g: G) -> U32: G.n(g, 60n)
def g_ct8r0(g: G) -> U32: G.n(g, 61n)
def g_ct7a(g: G) -> U32: G.n(g, 62n)
#  63 CT7B=INDEX(R0, AFTER)  64 RGD=RANGE(_, AXIS_DEVICE)  65 RGT=its rtag(())
def g_ct7b(g: G) -> U32: G.n(g, 63n)
#  64 RGD=RANGE(_, AXIS_DEVICE)  65 RGT=its rtag(())
def g_rgd(g: G) -> U32: G.n(g, 64n)
def g_rgt(g: G) -> U32: G.n(g, 65n)

# THE ROWS, one line per group; every `py=` is printed by CPython, never typed.
#
#  noopf_*  `is_noop_after_dep` (246). Five nodes because the rule is a TWO-OP recursion
#      and one arm is not enough to see it: `noopf_e_n0 = 1` is the descent and
#      `noopf_nx = 0` is the arm that stops it.
#  raf_*  `remove_noop_afters` (249). THREE rows for one rule because its three answers
#      are three different SHAPES -- a rebuilt AFTER, an EXISTING node, and no answer at
#      all -- and `raf_after1_is_src0` proves the second: it is `1` only because the
#      index is COMPARED, which is also why a rewrite here need not intern anything.
#  szs_*  `strip_zero_offset_shrink` (140). `szs_sh1_is_src0 = 0` is the NEGATIVE side,
#      asked as "is it the src0 index" rather than "is the answer absent" -- asking for
#      the absence would be satisfied by any wrong-but-present answer.
#  nic_*  `no_indexing_calls` (143), one row per arm. `nic_calls = 0` is the identity
#      case and it is a REAL answer: a SHRINK with offset 1 strips to itself, so the
#      rebuild IS the CALL and `hop_self` drops it.
#  nv_*  `pm_no_views` (165). `nv_rsi = 0` is the pattern's rejection of a RESHAPE over an
#      INDEX: the pattern is the test and the body is only the answer.
#  rb_*  `pm_remove_bufferize` (131-138). `rb_self_is_noop` and `rb_diff` are the two
#      sides of the ONE identity check in this file, so between them they are all of
#      `upat.py:100-105` as it applies here.
#  aprt_*  `pm_add_param_range_tags` (330). `aprt_empty = 0` is the idempotence row and
#      `aprt_paluT = 0` is the ALU row, and they are different: the first is
#      `ret is not uop`, the second is the `addrspace` conjunct.
#  ren_*  `renumber_range` (299). `ren_arg0`/`ren_next` and `ren7_*` are the two-sided
#      counter rows, and the gate feeds CPython's `ctx.range`.
#  dg_*  `to_define_global` (311-328). `dg_ixpa_ans` is the ONE row that is a
#      fully-ported rule BODY answering a node; `dg_ixpg_ans` is its negative.
#  *_len  the COUNT rows, one per table, so a MISSING rule shows. `ct_len = 9` and
#      `ab_len = 10` are BECAUSE the foreign prefixes are counted in, and `mops_len = 3`
#      and `fb_len = 1` are what make the composition arithmetic checkable.
#  claim_*  the CLAIM COUNT of one fixture node per table. `claim_ab_stg2 = 2` IS the
#      two-rules-claim-one-node row, measured by `.agents/slop/rf-claims.py`, which walks
#      every `UPat.match` over the fixture and reports the only node two rules claim.
#  rej_*  the reject sets that are NON-EMPTY and load-bearing. A MISSPELLED one turns a
#      necessary condition into a false one and the rule then skips a node it should
#      claim, and nothing else in the file would notice.
def t_lay() -> U32: U32.from_nat(List.length(&2, U32, G.ix(g())))

# THE TABLE READERS, hoisted above every row that uses them: the n-th entry of a
# table, so a reject-set row and a root-set row are both reads of the TABLE
# rather than restatements of it. `Maybe.default` answers a missing index with a
# `0`-tagged entry, so an out-of-range read is a `0` and not a crash.
def ct_entry(n: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ct_table(), n), O.PMEntry{0, Nil{}, Nil{}})

def dg_entry(n: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, dg_table(), n), O.PMEntry{0, Nil{}, Nil{}})

def ab_entry(n: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ab_table(), n), O.PMEntry{0, Nil{}, Nil{}})

# THE ROOT OP OF AN ENTRY, AS ITS `Ops` NUMBER. The number is the declaration
# order (ops.bend:301 says so, and CPython agrees: INDEX 17, AFTER 13, END 55,
# STAGE 64, CONST 58, RANGE 53), and it is the key `pdict` is built from, so a
# row printing it is a claim about which op the ENGINE looks a node up under.
# `t_root_op.go` returns `max U32` for an EMPTY set, which no real entry has.
# `t_root_op.go` returns `max U32` for an EMPTY set, which no real entry has.
def t_root_op.go(m: Maybe<&2, O.Op>) -> U32:
  match m:
    case Some{o}: O.Ops.value(o)
    case None{}  : 4294967295

def t_root_n(e: O.PMEntry) -> U32: t_root_op.go(List.get(&2, O.Op, O.PMEntry.ops(e), 0n))

# THE CLAIM AS A BOOL, restricted to one entry: "tag 4's rule claims a STAGE".
# This is the row that M21 moves, and it is the row the table's op sets had wrong
# for tags 0, 1, 2, 5 and 8. `ct_root4` and `ct_root5` are 1; the five INDEX/AFTER/
# END entries are 0.
def t_ct_root(e: O.PMEntry) -> U32: b2u(O.op_in(O.PMEntry.ops(e), O.OpsSTAGE{}))

# THE ROOT/SUB ROWS. `mops_root0/1/2` are the pdict KEYS of the three `pm_mops`
# rules (17, 13, 55) and `mops_child_fb` is the PATTERN's child set (6 ops). They
# are DIFFERENT facts and the port had them as one, which is the whole defect.
def t_mops_rules() -> U32: 3
def t_mops_root0() -> U32: t_root_n(ct_entry(0n))
def t_mops_root1() -> U32: t_root_n(ct_entry(1n))
def t_mops_root2() -> U32: t_root_n(ct_entry(2n))
def t_mops_child_fb() -> U32: U32.from_nat(List.length(&2, O.Op, MOPS_FB()))

def t_ct_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, ct_table()))
def t_rb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, rb_table()))
def t_nic_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, nic_table()))
def t_nv_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, nv_table()))
def t_lb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, lb_table()))
def t_fb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, fb_table()))
def t_ab_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, ab_table()))
def t_dg_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, dg_table()))
def t_aprt_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, aprt_table()))
def t_sk_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, sk_table()))
def t_gs_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, gs_table()))

# the foreign prefix. `mops_rules` is how many `pm_mops` RULES the composition
# shifts every own tag by, and the ROOT/SUB rows above are its three pdict keys.

def t_noopf_n0() -> U32: b2u(is_noop_after_dep(g_ar(g()), g_n0(g())))
def t_noopf_nx() -> U32: b2u(is_noop_after_dep(g_ar(g()), g_nx(g())))
def t_noopf_e_n0() -> U32: b2u(is_noop_after_dep(g_ar(g()), g_e0(g())))
def t_noopf_e_nx() -> U32: b2u(is_noop_after_dep(g_ar(g()), g_e1(g())))
def t_noopf_b4() -> U32: b2u(is_noop_after_dep(g_ar(g()), g_b4(g())))

def t_raf_after_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(remove_noop_afters(g_ar(g()), g_af(g()))), M.hop_ix(remove_noop_afters(g_ar(g()), g_af(g()))))

def t_raf_after1_is_src0() -> U32:
  b2u(U32.is_eq(M.hop_ix(remove_noop_afters(g_ar(g()), g_af1(g()))), g_b4(g())))

def t_raf_afterk_none() -> U32:
  b2u(O.UOp.is_none(M.hop_ix(remove_noop_afters(g_ar(g()), g_afk(g())))))

def t_szs_sh0_is_src0() -> U32:
  b2u(U32.is_eq(M.hop_ix(strip_zero_offset_shrink(g_ar(g()), g_sh0(g()))), g_b4(g())))

def t_szs_sh1_is_src0() -> U32:
  b2u(U32.is_eq(M.hop_ix(strip_zero_offset_shrink(g_ar(g()), g_sh1(g()))), g_b4(g())))

def t_szs_n0_is_self() -> U32:
  b2u(U32.is_eq(M.hop_ix(strip_zero_offset_shrink(g_ar(g()), g_n0(g()))), g_n0(g())))

def t_nic_calli_ans() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(nic_rewrite(g_ar(g()), g_cli(g()))))))
def t_nic_calls_ans() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(nic_rewrite(g_ar(g()), g_cls(g()))))))
def t_nic_callm_ans() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(nic_rewrite(g_ar(g()), g_clm(g()))))))
def t_nic_b4_ans() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(nic_rewrite(g_ar(g()), g_b4(g()))))))

# the INDEX arm: the CALL's src0 becomes the STAGE, so the arity is 2 and the
# src0 is NOT the INDEX's src0 (which is the CALL's own INDEX).
def t_nic_calli_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(nic_rewrite(g_ar(g()), g_cli(g()))), M.hop_ix(nic_rewrite(g_ar(g()), g_cli(g()))))

# the MSTACK arm: the CALL's src0 is a MSTACK whose srcs were both stripped, and
# `strip(SH1) = SH1` while `strip(SH0) = B4`, so the arity is still 2.
def t_nic_callm_src0_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(nic_rewrite(g_ar(g()), g_clm(g()))), M.mp_src0(M.hop_ar(nic_rewrite(g_ar(g()), g_clm(g()))), M.hop_ix(nic_rewrite(g_ar(g()), g_clm(g())))))

def t_nv_rs_is_src0() -> U32:
  b2u(U32.is_eq(M.hop_ix(nv_rewrite(g_ar(g()), g_rs(g()))), g_b4(g())))

def t_nv_rsi_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(nv_rewrite(g_ar(g()), g_rsi(g())))))
def t_nv_b4_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(nv_rewrite(g_ar(g()), g_b4(g())))))

# `STORE(x,x)` -> NOOP. TWO rows: the op and the arity, because a NOOP with a src
# would be a different bug and `rb_self_nsrc = 0` is what says "no srcs".
def t_rb_self_is_noop() -> U32:
  b2u(M.mp_is(M.hop_ar(rb_rewrite(g_ar(g()), g_sts(g()))), M.hop_ix(rb_rewrite(g_ar(g()), g_sts(g()))), O.OpsNOOP{}))

def t_rb_self_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(rb_rewrite(g_ar(g()), g_sts(g()))), M.hop_ix(rb_rewrite(g_ar(g()), g_sts(g()))))

# THE OTHER SIDE of the identity check. `STORE(B4, BX)` is a two-src STORE whose
# srcs are DIFFERENT nodes, and the rule must NOT fire: without `upat.py:100-105`
# this row would be 1 and every real store would be deleted.
def t_rb_diff_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(rb_rewrite(g_ar(g()), g_std(g())))))

# `END(NOOP)` -> NOOP, a node ALREADY in the arena. Positive because the rule
# returns the bound name, not `uop`, so `ret is not uop` holds.
def t_rb_e_n0() -> U32:
  b2u(U32.is_eq(M.hop_ix(rb_rewrite(g_ar(g()), g_e0(g()))), g_n0(g())))

def t_rb_ixstg_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(rb_rewrite(g_ar(g()), g_ixs(g())))))

def t_aprt_none() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_r0(g()))))))
def t_aprt_r0t_none() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_r0t(g()))))))
def t_aprt_pglob() -> U32: b2u(Bool.not(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_pg(g()))))))
def t_aprt_pgloT_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_pgt(g())))))
def t_aprt_palu_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_pa(g())))))
def t_aprt_paluT_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_pat(g())))))
def t_aprt_b4_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(aprt_rewrite(G.fx(g()), g_ar(g()), g_b4(g())))))

def t_ren_untagged_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(rf_renumber(g_ar(g()), g_r0(g()), 0))))
def ren_axis0.go(a: O.Arg) -> U32:
  match a:
    case O.ARange{ids, at}: Maybe.default(&2, U32, List.get(&2, U32, ids, 0n), 0)
    case _: 0

def ren_axis0(+n: U32, +ar: O.Arena, +self: U32) -> U32:
  ren_axis0.go(M.mp_arg(M.hop_ar(rf_renumber(ar, self, n)), M.hop_ix(rf_renumber(ar, self, n))))


def t_ren_arg0() -> U32: ren_axis0(0, g_ar(g()), g_r0t(g()))
def t_ren_next() -> U32: rf_renumber_next(0)
def t_ren7_arg0() -> U32: ren_axis0(7, g_ar(g()), g_r0t(g()))
def t_ren7_next() -> U32: rf_renumber_next(7)

# `renumber_range` writes `ARange{[n], <the old AxisType>}` and this reads the
# `n` back OUT of the REWRITTEN node's arg -- so the row tests the construction
# and not the parameter that went into it, which is the only way a rule that
# ignored `n` could be caught.


# the AxisType half: `r.arg[1:]` KEEPS it, and `ren_axis_weak` is the row that
# says the port preserved it rather than rebuilding the arg from scratch.
def t_ren_axis_weak() -> U32: b2u(O.eq_axis(rf_axis(g_ar(g()), g_r0t(g())), O.AXIS_WEAK{}))

# the fully-ported `dg_3` body: an INDEX of an ALU PARAM answers the PARAM
def t_dg_ixpa_ans() -> U32:
  b2u(U32.is_eq(M.hop_ix(dg_rewrite(G.fx(g()), g_ar(g()), g_ipa(g()))), g_pa(g())))

# and its negative: an INDEX of a GLOBAL PARAM does NOT answer. The row prints
# the ABSENCE, so it is `_none` and its 1 is the passing value.
def t_dg_ixpg_none() -> U32:
  b2u(O.UOp.is_none(M.hop_ix(dg_rewrite(G.fx(g()), g_ar(g()), g_ipg(g())))))

# `dg_2`'s three conjuncts, one row each, because they are three DIFFERENT
# reasons a PARAM is not a kernel-local slot and only the first is about the tag.
def t_dg2_pat() -> U32: b2u(rf_param_tagged(g_ar(g()), g_pgt(g())))
def t_dg2_pg() -> U32: b2u(rf_param_tagged(g_ar(g()), g_pg(g())))
def t_dg2_palu() -> U32: b2u(rf_param_alu(G.fx(g()), g_pa(g())))

# `ab_4`'s CLAIM -- a STRICT two-src STAGE -- and `fb`'s `len(x.src) == 2`. These two are
# the two halves of the two-rules-one-node node, and they are separate rows because a
# mutation that drops EITHER one destroys the fixture.
# THE CLAIM COUNT, and why it is a SEPARATE FOLD from the scan. `claim_n` counts how many
# rules of a table CLAIM the node -- the `rf_claimed` half of the `try` WITHOUT the
# dispatch -- so it counts patterns that MATCH rather than rewrites that fired. A scan
# stops at the first answer; a count must not, and that difference is the only reason a
# first-wins bug is visible to a gate at all.
#
# `claim_n` IS AN OP-SET COUNT, and the distinction is load-bearing: `PMEntry.ops` is
# `pdict`'s key, so it is the ROOT op and nothing else. `ab_4`'s src test (a STRICT
# two-src STAGE) lives in its body, so `claim_n` alone counts BOTH `stg2` and `stg3` as
# claimed by tags 3 and 4 -- MEASURED, and `claim_ops_stg2`/`claim_ops_stg3` are the two
# rows that show it. `claim_full` adds the src half back and separates them.
def claim.one(ok: Bool, acc: U32) -> U32:
  match ok:
    case True{} : U32.add(acc, 1)
    case False{}: acc

def claim.go(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +e <> t: claim.go(t, ar, self, claim.one(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), acc))

def claim_n(ts: List<&2, O.PMEntry>, ar: O.Arena, self: U32) -> U32:
  claim.go(ts, ar, self, 0)

# THE SRC HALF OF THE CLAIM, per tag, for `pm_add_buffers` -- the only table the
# gate counts, and the only one where the two-rules-one-node node lives. Every
# tag whose pattern is op-only answers `True{}` and says so.
def claim_ab_src.of(tag: U32, two: Bool, weakc: Bool, ar: O.Arena, self: U32) -> Bool:
  match tag:
    case 4: two
    case 5: weakc
    case _: True{}

def claim_ab_src(tag: U32, +fx: F.Folded, +ar: O.Arena, +self: U32) -> Bool:
  claim_ab_src.of(tag, ab_4_claim(ar, self), ab_5_claim(fx, ar, self), ar, self)


def claim_full.one(ok: Bool, acc: U32) -> U32:
  match ok:
    case True{} : U32.add(acc, 1)
    case False{}: acc

def claim_full.go(rs: List<&2, O.PMEntry>, +fx: F.Folded, +ar: O.Arena, +self: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +e <> t: claim_full.go(t, fx, ar, self,
                                claim_full.one(Bool.and(rf_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)),
                                                         claim_ab_src(O.PMEntry.tag(e), fx, ar, self)),
                                              acc))

def claim_full(ts: List<&2, O.PMEntry>, fx: F.Folded, ar: O.Arena, self: U32) -> U32:
  claim_full.go(ts, fx, ar, self, 0)

# THE OP-SET COUNT, and the two rows are EQUAL -- that is the point. Both STAGEs
# are claimed by tags 3 and 4 on the op set alone, and the `full` count below is
# what separates them. Without the pair, an op-set count would look like a
# first-wins discriminator and is not one.
def t_claim_ops_stg2() -> U32: claim_n(ab_table(), g_ar(g()), g_st2(g()))
def t_claim_ops_stg3() -> U32: claim_n(ab_table(), g_ar(g()), g_st3(g()))

# THE FULL CLAIM, and the row the brief demands: 2 for the two-src STAGE (tags 3
# and 4) and 1 for the three-src one (tag 3 only, because `ab_4`'s src is a STRICT
# two-tuple). Two rules claim ONE node, they DISAGREE, and a first-wins->
# conjunction mutation moves these two and nothing else.
def t_claim_ab_stg2() -> U32: claim_full(ab_table(), G.fx(g()), g_ar(g()), g_st2(g()))
def t_claim_ab_stg3() -> U32: claim_full(ab_table(), G.fx(g()), g_ar(g()), g_st3(g()))
def t_ab4_stg2() -> U32: b2u(ab_4_claim(g_ar(g()), g_st2(g())))
def t_ab4_stg3() -> U32: b2u(ab_4_claim(g_ar(g()), g_st3(g())))
def t_fb_two_stg2() -> U32: b2u(rf_fb_two(g_ar(g()), g_st2(g())))
def t_fb_two_stg3() -> U32: b2u(rf_fb_two(g_ar(g()), g_st3(g())))
def t_fb_sym_stg3() -> U32: b2u(rf_fb_sym(g_ar(g()), g_st3(g())))

# `ab_8`: a STORE of an Invalid constant is a NOOP with no srcs, and a STORE of
# anything else is not rewritten. `ab_8_sti`/`ab_8_std` are the two sides.
def t_ab8_sti() -> U32:
  b2u(M.mp_is(M.hop_ar(ab_rewrite(G.fx(g()), g_ar(g()), g_sti(g()))),
              M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_sti(g()))), O.OpsNOOP{}))
def t_ab8_std_none() -> U32:
  b2u(O.UOp.is_none(M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_sts(g())))))

# `ab_7`: the CALL keeps its arity and its src0 becomes the RESHAPE's src0.
def t_ab7_cli_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(ab_rewrite(G.fx(g()), g_ar(g()), g_cli(g()))),
            M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_cli(g()))))

# THE ARG ROWS, and why they had to be written at all. `mp_replace` was widened from
# `(op, ar, self, src)` to `(op, arg, ar, self, src)` because `UOp.replace` (ops.py:252)
# takes `arg` as a KWARG -- `kwargs.pop("arg", self.arg)` -- so a rule that replaces only
# `src` passes the node's OWN arg. Four call sites here were left on the 4-arg form and
# the file stopped compiling.
#
# THE COMPILED FILE IS NOT EVIDENCE, and neither is any row that already existed. `cli`,
# `af` and `mst` are all given `ANone` by this fixture, and an AFTER's and an MSTACK's
# arg is `None` in CPython TOO (measured: `raf_after_arg_is_none = 1`,
# `mstack_arg_is_none = 1`), so `eq_arg(rebuilt_arg, original_arg)` on any of them is
# `eq_arg(ANone, ANone)` -- TRUE for a port that preserves the arg AND for one that
# hardcodes `ANone`, which is the mistake that silences this type error. A CALL's arg is a
# `Kernel`, so `clik` is the node that separates the two and `clik0` is the negative one
# row from it at the same shape.
#
# `eq_arg(x, y)` DISPATCHES ON `x` and matches `y` (ops.bend:1559), so the expected arg
# goes first. `py=` from `.agents/slop/rf-arg-oracle.py`, which reports
# `arg_is_own_kernel=1` and `arg_is_none=0` for the rebuild.
def t_ab7_clik_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(ab_rewrite(G.fx(g()), g_ar(g()), g_clik(g()))),
            M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_clik(g()))))

# the rebuild kept the node's OWN Kernel arg -- py: `arg_is_own_kernel=1`
def t_ab7_clik_arg() -> U32:
  b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(ab_rewrite(G.fx(g()), g_ar(g()), g_clik(g()))),
                        M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_clik(g()))))))

# THE NEGATIVE, the twin with no arg, ONE ROW FROM the positive at the SAME shape:
# py: `arg_is_own_kernel=0 arg_is_none=1`. So `ab7_clik_arg` is not passing because
# every CALL rebuilds to a Kernel.
def t_ab7_clik0_arg() -> U32:
  b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(ab_rewrite(G.fx(g()), g_ar(g()), g_clik0(g()))),
                        M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_clik0(g()))))))

# the OTHER repaired site a CALL reaches, `no_indexing_calls` (rangeify.py:158).
# py: `nic_clik` nsrc=2, `arg_is_own_kernel=1`, `nic_claim_clik=1` (first-wins:
# exactly one pattern claims it, so this is not another rule's answer).
def t_nic_clik_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(nic_rewrite(g_ar(g()), g_clik(g()))),
            M.hop_ix(nic_rewrite(g_ar(g()), g_clik(g()))))

def t_nic_clik_arg() -> U32:
  b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(nic_rewrite(g_ar(g()), g_clik(g()))),
                        M.hop_ix(nic_rewrite(g_ar(g()), g_clik(g()))))))

# the two reject sets, spelled: `ct_4` is `{INDEX}` and `dg_3` is `{PARAM}`, and a
# MISSPELLING of either turns a necessary condition into a false one.
def t_rej_ct4() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(ct_entry(4n))))

def t_rej_dg3() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(dg_entry(3n))))
def t_rej_ct7() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(ct_entry(7n))))
def t_rej_ab8() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(ab_entry(8n))))

# `ct_entry(n)` / `dg_entry(n)` / `ab_entry(n)` are declared ABOVE, beside the
# `mops_root*` rows that need them, so a reject-set row and a root-set row read
# the TABLE through one reader.




# THE FOUR ROWS THAT CLOSE THE FIXTURE GAPS, and what each one is FOR. Each was
# added because a MEASURED mutation moved nothing, and a row that cannot fail is
# not a row. `rf-mut.py` in `.agents/slop/` re-measures all of them.
#
#   raf_aftn_is_src0 -- `src[0]` KEPT UNCONDITIONALLY. `aftn` is an AFTER whose BODY is
#       itself a dead dep, so Python keeps TWO srcs (the body and the END) and a
#       port that filters `src[0]` too keeps ONE. `raf_after_nsrc` cannot see this
#       because `af`'s src0 is a BUFFER and a BUFFER is not a dead dep either way;
#       this node is the one that can.
#   ab8_stc0_none -- `arg == Invalid`, not `op is CONST`. `sti` is the Invalid store
#       and `sts`/`std` are stores with a BUFFER as src[1], so no two-src STORE in
#       the fixture had a CONST src[1] that was not Invalid. `stc0` is that store.
#   nv_rsaf_ans -- `rf_is_bufid5`'s SIX-op set. `rs` and `rsi` are RESHAPEs over a
#       BUFFER, so a set reduced to {BUFFER} is indistinguishable from the real
#       one. `rsaf` is a RESHAPE over an AFTER, which is a different member.
#   dg_r0t_ans -- `dg_6`, i.e. `renumber_range` REACHED through the dispatch. Every
#       other `dg` row exercises a rule whose answer is "no node", so a table entry
#       with the WRONG op set is invisible. This is the row that makes `dg_6` real.
#   ren_axis_out -- the AxisType of the REWRITTEN node, not of the input. Reading
#       the input (which is what this file did first) cannot see a rule that
#       rebuilt the arg from scratch.
def t_raf_aftn_is_src0() -> U32:
  b2u(U32.is_eq(M.hop_ix(remove_noop_afters(g_ar(g()), g_aftn(g()))), g_n0(g())))

def t_ab8_stc0_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(ab_rewrite(G.fx(g()), g_ar(g()), g_stc0(g())))))

def t_nv_rsaf_ans() -> U32:
  b2u(U32.is_eq(M.hop_ix(nv_rewrite(g_ar(g()), g_rsaf(g()))), g_af(g())))

def t_dg_r0t_ans() -> U32:
  b2u(Bool.not(O.UOp.is_none(M.hop_ix(dg_rewrite(G.fx(g()), g_ar(g()), g_r0t(g()))))))

# the AxisType of the node `rf_renumber` BUILT. A rule that rebuilt the whole arg
# would leave this at whatever it hard-coded, so this is the row for `r.arg[1:]`.
def t_ren_axis_out() -> U32:
  b2u(O.eq_axis(rf_axis(M.hop_ar(rf_renumber(g_ar(g()), g_r0t(g()), 3)), M.hop_ix(rf_renumber(g_ar(g()), g_r0t(g()), 3))), O.AXIS_WEAK{}))

# ... AND THE ROW THAT MAKES M12 SHARP. Every other RANGE in the fixture is
# AXIS_WEAK, so "rebuild the AxisType" and "read it off the node" are the same
# function over the rest of the fixture and M12 moved nothing. RGT's input axis is
# `AXIS_DEVICE`, so the two spellings differ here and nowhere else.
def t_ren_axis_out_dev() -> U32:
  b2u(O.eq_axis(rf_axis(M.hop_ar(rf_renumber(g_ar(g()), g_rgt(g()), 3)), M.hop_ix(rf_renumber(g_ar(g()), g_rgt(g()), 3))), O.AXIS_DEVICE{}))

def t_ren_axis_in_dev() -> U32: b2u(O.eq_axis(rf_axis(g_ar(g()), g_rgd(g())), O.AXIS_DEVICE{}))

def t_bool(x: Bool) -> U32: b2u(x)



# THE SRC OP SEQUENCE, because A COUNT IS NOT A GATE. For a rewrite engine the identity
# of an answer is the SEQUENCE of its srcs' ops, in order, plus its arg: swapping a
# movement's two shape args leaves op, nsrc, the src sequence and the toposort ALL
# identical, and a wrong field ORDER is a silently wrong write -- while `mp_nsrc` is a
# count, so two wrong answers can share one.
#
# `srcops` maps each src index to its `Ops` NUMBER and folds the list to a `String` of
# the form ".58.53" for `[CONST, RANGE]`. A NUMBER and not `Ops.name`, because a name is
# not comparable across two ports and the number is what Python's `UOp.tuplize` sorts on
# anyway. The `py=` expectations are the same strings, printed from CPython's own
# `ops[i].op.value`.
#
# `t_srcops_eq` answers a Bool AGAINST A LITERAL, so a reorder, a dropped src and a
# wrong op are three different failures rather than one shared count.
def srcops.go(+ar: O.Arena, ss: List<&2, U32>, acc: String) -> String:
  match ss:
    case Nil{}     : acc
    case +x <> t  : srcops.go(ar, t, String.concat([acc, ".", U32.show(O.Ops.value(M.mp_op(ar, x)))]))

def srcops_n(+ar: O.Arena, self: U32) -> String: srcops.go(ar, M.mp_srcs(ar, self), "")

# `hop_srcops` is the same read on a RULE'S ANSWER, and it is the row form every
# rewrite row below uses.
def hop_srcops(+r: M.Hop) -> String: srcops_n(M.hop_ar(r), M.hop_ix(r))

def t_srcops_eq(got: String, want: String) -> U32: b2u(String.eq(got, want))

# `ar_of` is `g_ar(g())` under a short name: the `ct` rows below read the arena
# three or four times each and the long form buried the claim in the noise.
def ar_of(i: U32) -> O.Arena: g_ar(g())

# THE CT ROWS, and the answer to "which of `ct_4`, `ct_5`, `ct_8` are live". ALL THREE ARE
# LIVE. The previously recorded Python-side result -- "for
# `UPat(Ops.MSTACK).f(Ops.INDEX, name='idx')` the replace is an IDENTITY on the INDEX and
# `pm_const_buffer_folding.rewrite(mst) is None`" -- is TRUE of `MSTACK(c4, c1)` and FALSE
# of `INDEX(MSTACK(c4, c1))`. `MSTACK(c4, c1)` is the MIRROR: it is the CHILD, so
# `pdict` (keyed on the root INDEX) never reaches it. The shape the pattern is written
# for answers `INDEX, srcops=[CONST]`, which is a real rewrite. The finding was sound and
# was measured on the wrong node.
#
# Every `py=` below is printed by `.agents/slop/rf-ct-oracle.py`; the transcript is in
# `.agents/slop/rf-ct-oracle.txt`:
#  ct_4  STAGE(INDEX(b4,r0), r0)                      2     BUFFER
#  ct_4  STAGE(INDEX(b5,r0), r0)                      2     SHRINK(b5,0,4)
#  ct_4  STAGE(INDEX(b4,r0), r1)                      2     None    <- tails differ
#  ct_4  INDEX(STAGE(b4,r0), r0)   THE MIRROR        0     None
#  ct_5  STAGE(c4, r0)                                2     EXPAND(ns2)
#  ct_5  STAGE(CAST(c4,half), r0)                     2     EXPAND(ns2)
#  ct_5  STAGE(b4, r0)             inner is neither   1     None
#  ct_8  INDEX(MSTACK(c4,c1))                         1     INDEX([CONST])
#  ct_8  INDEX(MSTACK(c4,c1), r0)                     1     INDEX([CONST,RANGE])
#  ct_8  INDEX(MSTACK(bufdev))      s has a device    1     None
#  ct_8  MSTACK(c4,c1)              THE MIRROR        0     None
#
# `ct_claim_n` is `claim_full` specialised to the `ct` table: the op-set claim PLUS each
# `.f()` rule's own body test, which is what makes tags 3 and 4 both claim a STAGE and
# nothing claim a BUFFER. EVERY TAG IN `ct_table` NEEDS ITS OWN BODY TEST HERE, and tags
# 0, 6 and 7 are the three the first version of this fold left at `True{}`. A claim count
# built on the op set alone counts an INDEX as claimed by four rules when CPython binds
# it in one, so `ct4b_claim` and `ct8d_claim` were both wrong until they were added.
def ct_src.of(tag: U32, mop: Bool, tail: Bool, cvar: Bool, cvar2: Bool, after: Bool, mstk: Bool) -> Bool:
  match tag:
    case 0: mop
    case 4: tail
    case 5: cvar
    case 6: cvar2
    case 7: after
    case 8: mstk
    case _: True{}

def ct_src_n(tag: U32, +ar: O.Arena, +ix: U32) -> Bool:
  ct_src.of(tag,
            O.GroupOp.movement(M.mp_op(ar, M.mp_src0(ar, ix))),
            rf_same_tail(ar, ix),
            ct_5_claim(ar, ix),
            ct_6_pat(ar, ix),
            ct_7_claim(ar, ix),
            ct_8_claim(ar, ix))

def claim_ct.one(ok: Bool, acc: U32) -> U32:
  match ok:
    case True{} : U32.add(acc, 1)
    case False{}: acc

def claim_ct.go(rs: List<&2, O.PMEntry>, +ar: O.Arena, +ix: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +e <> t: claim_ct.go(t, ar, ix,
                              claim_ct.one(Bool.and(rf_claimed(ar, ix, O.PMEntry.ops(e), O.PMEntry.rej(e)),
                                                    ct_src_n(O.PMEntry.tag(e), ar, ix)), acc))

def ct_claim_n(ts: List<&2, O.PMEntry>, ar: O.Arena, ix: U32) -> U32: claim_ct.go(ts, ar, ix, 0)

# -- ct_4: the claim on the discriminating shape, and on its mirror ------------
# py: `ct4A_claim = 2` (tags 3 and 4) and `ct4B_claim = 0`.
def t_ct4a_claim() -> U32: ct_claim_n(ct_table(), g_ar(g()), g_ct4a(g()))
def t_ct4b_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_ct4b(g())), g_ct4b(g()))

# py: `ct4A_out = BUFFER/nsrc0/srcops=[]` -- CPython answers a node. The port's
# answer is the `UOp.shrink` wall, so this row is the PORT'S absence and the
# divergence is recorded rather than smoothed into an agreeing row.
def t_ct4a_ans() -> U32: b2u(O.UOp.is_none(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct4a(g())))))

# THE REFUSAL, which is the `!=` on the two tails: CT4D's STAGE tail is R1 and its
# INDEX's is R0. Two rows, the comparison itself and the absent answer, so a rule
# that ignored the comparison would move the second and not the first.
# py: `ct4A_fn tails_eq=1` / `ct4D_fn tails_eq=0 out=None`.
def t_ct4a_tail() -> U32: b2u(rf_stage_tail(g_ar(g()), g_ct4a(g()), g_ixb4(g())))
def t_ct4d_tail() -> U32: b2u(rf_stage_tail(g_ar(g()), g_ct4d(g()), g_ixb4(g())))
def t_ct4d_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct4d(g())))))

# -- ct_5: the claim on all three arms, and the claim PREDICATE alone ----------
# py: `ct5_const_claim = 2`, `ct5_cast_claim = 2`, `ct5_buf_claim = 1` -- the
# BUFFER child is claimed by tag 3 ALONE and the CONST/CAST children by 3 and 5.
def t_ct5c_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_ct5c(g())), g_ct5c(g()))
def t_ct5k_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_ct5k(g())), g_ct5k(g()))
def t_ct5b_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_ct5b(g())), g_ct5b(g()))

# the PREDICATE on its own, so a table entry with the right op set and a body that
# lost its child test is visible, and the reverse.
def t_ct5c_pat() -> U32: b2u(ct_5_claim(g_ar(g()), g_ct5c(g())))
def t_ct5k_pat() -> U32: b2u(ct_5_claim(g_ar(g()), g_ct5k(g())))
def t_ct5b_pat() -> U32: b2u(ct_5_claim(g_ar(g()), g_ct5b(g())))

# the ANSWER, and it is the `DType.const` + `_mop` wall. py:
# `ct5_stg_of_const out=EXPAND/nsrc2/srcops=[CONST,CONST]`, so the CPython answer's
# src op SEQUENCE is ".58.58" -- recorded here and in the oracle, NOT restated as a
# Bend row, because a row comparing a literal with itself cannot fail.
def t_ct5c_ans() -> U32: b2u(O.UOp.is_none(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct5c(g())))))

# -- ct_8: the claim, the device gate, the rebuild and THE ARG -----------------
# py: `ct8_devless_claim = 1` and `ct8_bare_mstack claim_n = 0`.
def t_ct8d_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_ct8d(g())), g_ct8d(g()))
def t_mstc_claim() -> U32: ct_claim_n(ct_table(), ar_of(g_mstc(g())), g_mstc(g()))

# `s.device is None` -- the fold's OUTER `Maybe`, and the two rows are the
# refusal pair: CT8D's `s` is a CONST and CT8B's is a device-carrying BUFFER.
# py: `ct8_devless_s device_is_none=1`, `ct8_dev_s device_is_none=0`.
def t_ct8d_devnone() -> U32: b2u(rf_dev_is_none(G.fx(g()), M.mp_src(ar_of(g_mstc(g())), g_mstc(g()), 0)))
def t_ct8b_devnone() -> U32: b2u(rf_dev_is_none(G.fx(g()), M.mp_src(ar_of(g_mstb(g())), g_mstb(g()), 0)))

# THE REBUILD, as the src op SEQUENCE. py: `ct8_ix_ms_devless out=INDEX/nsrc1/
# srcops=[CONST]` and `ct8_ix_ms_rng out=INDEX/nsrc2/srcops=[CONST,RANGE]`, and
# `Ops.CONST.value` is 58 while `Ops.RANGE.value` is 53 -- both asked of CPython.
# The two rows are ".58" and ".58.53", and the difference IS the `src[1:]` half,
# which a count could not see.
def t_ct8d_srcops() -> U32:
  t_srcops_eq(hop_srcops(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8d(g()))), ".58")

def t_ct8r_srcops() -> U32:
  t_srcops_eq(hop_srcops(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8r(g()))), ".58.53")

# and the answer is a NEW node rather than the input: py `ct8_ix_ms_devless
# is_self=0`. A rule that rebuilt nothing would answer `self` and this would be 0.
def t_ct8d_new() -> U32:
  b2u(Bool.not(U32.is_eq(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8d(g()))), g_ct8d(g()))))

# THE ARG GATE, and it is the one the old fixture could not express. `UOp` does
# not type-check `arg` against `op` -- measured -- so an INDEX carries an
# `ARange`, which is Python's `(axis_id, AxisType)` pair and the `Range` arg the
# brief names, and `idx.replace(src=...)` (ops.py:252) passes `self.arg` through
# unchanged. py: `ct8R_ix_arg_range arg_is_own_range=1 arg_is_none=0`, and the
# ANONE TWIN one row from it: `ct8N_ix_arg_none arg_is_own_range=0 arg_is_none=1`.
def ct8_arg(+r: M.Hop) -> O.Arg: M.mp_arg(M.hop_ar(r), M.hop_ix(r))

def t_ct8r_arg() -> U32:
  b2u(O.eq_arg(O.ARange{[7], O.AXIS_LOOP{}},
               ct8_arg(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8r(g())))))

def t_ct8r0_arg() -> U32:
  b2u(O.eq_arg(O.ARange{[7], O.AXIS_LOOP{}},
               ct8_arg(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8r0(g())))))

# the axis type is read back OUT of the REBUILT node, and the fallback arm is
# `AXIS_WEAK` so that a rule which rebuilt the arg from scratch -- or answered
# `None`, whose arg is `ANone` -- FAILS this row instead of passing it.
def ct8_axis.go(a: O.Arg) -> O.AxisType:
  match a:
    case O.ARange{ids, at}: at
    case _: O.AXIS_WEAK{}

def ct8_axis_n(r: M.Hop) -> O.AxisType: ct8_axis.go(ct8_arg(r))

def t_ct8r_axis() -> U32: b2u(O.eq_axis(ct8_axis_n(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8r(g()))), O.AXIS_LOOP{}))
def t_ct8r0_axis() -> U32: b2u(O.eq_axis(ct8_axis_n(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8r0(g()))), O.AXIS_LOOP{}))

# the device REFUSAL as a truncated trace: the answer is absent, and the reason is
# the one conjunct. py: `ct8_ix_dev out=None`.
def t_ct8b_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct8b(g())))))

# -- ct_7: the CLAIM only; the body is the `_min_max` wall ---------------------
# py: `ct7_ix_after tag7_nbind=1 first_tag=7`. The body CRASHES on that shape
# rather than answering -- see the `ct_7` comment above, `ct7_empty_ended_ranges_
# prod = 1 int` -- so there is no CPython answer to gate and the rows are the
# claim and the claim COUNT. The count is what makes mutation M30 (dropping
# `ct_src.of`'s tag-7 body test) sharp: with only `ct7a_claim` present, M30 moved
# NOTHING, because the predicate is written out longhand and no fold reads it.
def t_ct7a_claim() -> U32:
  b2u(Bool.and(M.mp_is(ar_of(g_ct7a(g())), g_ct7a(g()), O.OpsINDEX{}),
               M.mp_is(ar_of(g_ct7a(g())), M.mp_src0(ar_of(g_ct7a(g())), g_ct7a(g())), O.OpsAFTER{})))

def t_ct7a_cnt() -> U32: ct_claim_n(ct_table(), ar_of(g_ct7a(g())), g_ct7a(g()))

# THE ONE NODE WHERE TAG 7's REJECT SET IS NOT ITS CLAIM. `early_reject` is
# `{AFTER}` and it is satisfied by an AFTER in ANY src, so CT7B is claimed by the
# set test and NOT by the pattern. py: `ct7_ix_after tag7_nbind=1`; and for CT7B
# CPython's `rewrite` returns `None` because tag 6, tag 0 and tag 8 all miss and
# tag 7's pattern fails. Measured in `rf-ct-oracle.py` section 1's shape list.
def t_ct7b_cnt() -> U32: ct_claim_n(ct_table(), ar_of(g_ct7b(g())), g_ct7b(g()))
def t_ct7b_none() -> U32: b2u(O.UOp.is_none(M.hop_ix(ct_rewrite(G.fx(g()), g_ar(g()), g_ct7b(g())))))

# THE CLAIM COUNT. `claim(h, acc)` asks "did this rule CLAIM the node", which is
# the `rf_claimed` half of the `try` WITHOUT the dispatch -- so it is a count of
# patterns that match, not of rewrites that fired. It is a separate fold from the
# scan because a scan STOPS at the first answer and a count must not.




def claim_ab(+fx: F.Folded, +ar: O.Arena, +self: U32) -> U32: claim_full(ab_table(), fx, ar, self)

# `get_kernel_graph` -- rangeify.py:351-376. PORTED AS A STAGE ORDER, and the reason is
# the `ctx` wall rather than a missing idea. SEVEN `graph_rewrite` CALLS, in this order,
# and the order is the port: the tables are all here, each applied to the arena the
# previous stage left, and `rf_stages` is the row that pins the count. What is NOT here
# is the engine that walks the arena applying them -- see the TODO block at the foot.
#
# TWO OF THE STAGES ARE NOT IN THIS FILE'S TABLES and that is a Python fact, not an
# omission: `run_rangeify` (353) is `schedule/indexing.py:190`, and `symbolic` +
# `pm_reduce_simplify` (357) are `uop/symbolic.py` (123 rules) and
# `codegen/simplify.py`. `type_verify` (375) is `uop/spec.py` and IS ported, as
# `uop/spec.bend`.
#
# THE TWO `ctx` LINES ARE THE WALL and they are the only two: `itertools.count` at 360 and
# 366, and `LimitBufsContext` at 360. Every one is a MUTABLE object threaded through a
# pass, which is exactly the shape `schedule/__init__.bend` refuses for the same reason.
def rf_stage_count() -> U32: 9

# the STAGE ORDER, as the tables in order. `rf_stages` is the row, and it is 9
# because `run_rangeify` counts as a stage even though it is another file's.
def rf_stages() -> List<&2, U32>:
  [1, 2, 3, 4, 5, 6, 7, 8, 9]

# The two env flags, as PARAMETERS per the brief's rule for an env flag:
# `DEBUG_RANGEIFY` (353), `MAX_KERNEL_BUFFERS` (179) via `rf_webgpu8`'s sibling,
# `VIZ` (361, 371) and `SPEC` (372). `VIZ` and `SPEC` only add a view/validate
# pass, so their absence changes nothing a gate can see, and `MAX_KERNEL_BUFFERS`
# is the one that would.
def rf_debug_rangeify() -> Bool: False{}
def rf_viz() -> Bool: False{}
def rf_spec() -> Bool: False{}

def t_stages() -> U32: U32.from_nat(List.length(&2, U32, rf_stages()))
def t_spec() -> U32: b2u(rf_spec())
def t_ranges_miss() -> U32: b2u(rf_ranges_miss())

# THE MEASURED MUTATION TABLE. FORTY-ONE textual edits, one at a time, by
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
#  (4) M36 AND M38 ARE A BLIND SPOT AND ITS NEGATIVE, REPORTED NOT CLOSED. Removing
#      `ct_8`'s self-re-check moves nothing alone, and moves nothing together with the
#      vacuous reject set either, so no fixture in the port as it stands can see the
#      self-check: the two defects it defends against are one defect seen from two ends
#      and each alone is invisible. The pre-self-check measurement in (1) is the
#      evidence that the self-check is load-bearing and it cannot be reproduced by the
#      gate as it now stands. NOT closed with a row that encodes either behaviour.
# M20 IS THE ROW THE COUNT ROWS EXIST FOR: it DELETES the LAST `PMEntry`, so no tag
# renumbers and `ct_len` is one of only six rows it can move.
# ===========================================================================
# THE WALLS. Every one is a Python fact rather than a choice, and every one is a
# `# TODO(p3)` line, so `rg 'TODO\(p3\)'` is the whole outstanding list. `rg 'NOT PORTED'`
# finds the site for each. The first group is ONE LINE PER UNPORTED BODY, the second is
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
# EACH LINE NAMES THE WALL THAT WAS FOUND BY ASKING CPython, not by reading the body.
# "LIVE" means CPython rewrites the node: a live rule behind a wall is a WALL ROW, not a
# missing row.
# TODO(p3) rangeify.py:24   cleanup_dead_axes     LIVE (measured); arg.removable, ranges, reshape, expand
# TODO(p3) rangeify.py:50   remove_bufferize      LIVE; a substitute(..., extra_pm=) over a ctx dict
# TODO(p3) rangeify.py:120  const_like            LIVE on BOTH arms; DType.const + _mop(EXPAND)
# TODO(p3) rangeify.py:124  after_all_invalid     LIVE and CRASHES on a rangeless END; _min_max, numel
# TODO(p3) rangeify.py:127  deviceless MSTACK src PORTED -- the UOp.device wall is `rf_dev` and it reads
# TODO(p3) rangeify.py:208  bufferize_to_store    LIVE; commit_dtype, sorted(ranges), ParamArg, next(ctx)
# TODO(p3) rangeify.py:259  weak-CAST INDEX       the claim is ported; the cast it must re-add is not
# TODO(p3) rangeify.py:263  RESHAPE through       UOp.base, apply_movement_op
# TODO(p3) rangeify.py:283  debuf                 LocalAddBufferContext.map
# TODO(p3) rangeify.py:292  handle_after          LocalAddBufferContext, ranges
# TODO(p3) rangeify.py:305  check_buf_states      buf_uop plus a read_from dict
# TODO(p3) rangeify.py:335  split_store           graph_rewrite INSIDE a rule
# --- the three whose Python answer is ALREADY REACHED, wall and all ----------
# TODO(p3) rangeify.py:45   gate_substitute       the raise became the 0, exactly
# TODO(p3) rangeify.py:176  _limit_bufs           the one line refuses to fire
# TODO(p3) rangeify.py:351  get_kernel_graph      the order is here, the engine is not
# --- the walls with no single site, and `ops.bend`'s OWN walls ---------------
#  The first two are the same problem `ops.bend` already records at its foot, so they are
#  ONE wall counted from two files, not two.
# TODO(p3) ops.py:470       ended_ranges          ops.bend's own wall
# TODO(p3) ops.py:483       UOp._ranges           recursive dict, pops as it goes
# TODO(p3) ops.py:497       UOp.ranges            the property over the above
# TODO(p3) ops.py:532       substitute            a dvars substitution walk
# TODO(p3) ops.py:603       const_like            a dtype plus a Const value
# TODO(p3) ops.py:784       UOp.base              a recursive property
# TODO(p3) ops.py:890       UOp.device            a recursive property
# TODO(p3) ops.py:925       buf_uop               the bufid walk
# TODO(p3) ops.py:1104      _min_max              resolve on symbolic bounds
# TODO(p3) ops.py:1886      to_max_shape          sint.vmax on a symbolic
# TODO(p3) indexing.py:57   BufferizeOpts         a frozen dataclass Arg
# TODO(p3) indexing.py:171  apply_movement_op     the movement-op dispatch
# TODO(p3) indexing.py:190  run_rangeify          stage 1 of the nine
# TODO(p3) prepare.py:76    pm_mops               3 foreign rules, tags 0-2
#  ... and their three pdict KEYS are PORTED here (they are a Python fact and the
#  engine's lookup is a Python fact), while their BODIES are BLOCKED on
#  `schedule/prepare.bend`, which as of this revision names `pm_mops` in its header and
#  declares no def for it. `rf_foreign` answers "no node" and says so; inventing a local
#  copy of `_mop_index` would be a lie about where the code lives. MEASURED roots:
#  17 (INDEX), 13 (AFTER), 55 (END).
# TODO(p3) ops.py:1339      KernelInfo.estimates  a 4-field record against Python's 5
#  `ops.bend`'s `KernelInfo` is `KernelInfo{name, applied_opts, opts_to_apply, beam}`
#  and Python's also carries `estimates: Estimates|None`, so no Bend value can be EQUAL
#  to a Python one. `ab7_clik_arg` compares against `O.KernelInfo.of()` on both sides,
#  which is why that row passes while the two representations are not interchangeable --
#  REPORTED, and the row's comment says so rather than the row pretending they agree.
# ===========================================================================
# `movement.bend`'s OWN GATE IS FAILING, and `hop_self` is one of the reasons.
# `movement.bend:67-73` has its two arms swapped: `b` is "the answer IS self, OR the
# answer IS none", `True` answers `r`, and Python's condition to DROP is `ret is uop`
# (ops.py:1610) -- so `True` must answer `Hop{ar, 0}`. It keeps `self` and drops a
# genuinely new node, the inverse of ops.py:1610 and of its own docstring.
#
# MEASURED, by swapping the arms on a scratch copy and re-running `movement.bend`'s gate:
# `const_idx2` 0->40, `const_idx3` 0->3, `rej_pair` 0->40, and `ret_new` 1->0. `t_ret_new`
# (movement.bend:920) therefore ASSERTS THE BUG -- it feeds `hop_self` a new index
# against a different self and asks for index 0, which is the inverted answer.
#
# REPORTED, NOT WORKED AROUND. `rf_self` above implements `ret is not uop` locally
# rather than calling `M.hop_self`, and M1 mutates the LOCAL copy, so M1 is a measurement
# rather than a re-measurement of this bug. `M.hop_first` and `M.hop_next` are correct and
# are reused. The other zeros in that gate (`shrink1_ns`, `reshape_pick`, `idx_*`) read 0
# under BOTH readings and are a second, separate defect this unit does not own.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lay", t_lay())
    b : Unit <- row("ct_len", t_ct_len())
    c : Unit <- row("rb_len", t_rb_len())
    d : Unit <- row("nic_len", t_nic_len())
    e : Unit <- row("nv_len", t_nv_len())
    f : Unit <- row("lb_len", t_lb_len())
    h : Unit <- row("fb_len", t_fb_len())
    i : Unit <- row("ab_len", t_ab_len())
    j : Unit <- row("dg_len", t_dg_len())
    k : Unit <- row("aprt_len", t_aprt_len())
    l : Unit <- row("sk_len", t_sk_len())
    m : Unit <- row("gs_len", t_gs_len())
    n : Unit <- row("mops_rules", t_mops_rules())
    n0 : Unit <- row("mops_root0", t_mops_root0())
    n1 : Unit <- row("mops_root1", t_mops_root1())
    n2 : Unit <- row("mops_root2", t_mops_root2())
    n3 : Unit <- row("mops_child_fb", t_mops_child_fb())
    n4 : Unit <- row("ct_root3", t_ct_root(ct_entry(3n)))
    n5 : Unit <- row("ct_root4", t_ct_root(ct_entry(4n)))
    n6 : Unit <- row("ct_root5", t_ct_root(ct_entry(5n)))
    n7 : Unit <- row("ct_root6", t_ct_root(ct_entry(6n)))
    n8 : Unit <- row("ct_root7", t_ct_root(ct_entry(7n)))
    n9 : Unit <- row("ct_root8", t_ct_root(ct_entry(8n)))
    o : Unit <- row("stages", t_stages())
    p : Unit <- row("ranges_miss", t_ranges_miss())
    q : Unit <- row("noopf_n0", t_noopf_n0())
    r : Unit <- row("noopf_nx", t_noopf_nx())
    s : Unit <- row("noopf_e_n0", t_noopf_e_n0())
    u : Unit <- row("noopf_e_nx", t_noopf_e_nx())
    v : Unit <- row("noopf_b4", t_noopf_b4())
    w : Unit <- row("raf_after_nsrc", t_raf_after_nsrc())
    x : Unit <- row("raf_after1_is_src0", t_raf_after1_is_src0())
    y : Unit <- row("raf_afterk_none", t_raf_afterk_none())
    z : Unit <- row("szs_sh0_is_src0", t_szs_sh0_is_src0())
    aa : Unit <- row("szs_sh1_is_src0", t_szs_sh1_is_src0())
    ab : Unit <- row("szs_n0_is_self", t_szs_n0_is_self())
    ac : Unit <- row("nic_calli_ans", t_nic_calli_ans())
    ad : Unit <- row("nic_calls_ans", t_nic_calls_ans())
    ae : Unit <- row("nic_callm_ans", t_nic_callm_ans())
    af : Unit <- row("nic_b4_ans", t_nic_b4_ans())
    ag : Unit <- row("nic_calli_nsrc", t_nic_calli_nsrc())
    ah : Unit <- row("nic_callm_src0_nsrc", t_nic_callm_src0_nsrc())
    ai : Unit <- row("nv_rs_is_src0", t_nv_rs_is_src0())
    aj : Unit <- row("nv_rsi_none", t_nv_rsi_none())
    ak : Unit <- row("nv_b4_none", t_nv_b4_none())
    al : Unit <- row("rb_self_is_noop", t_rb_self_is_noop())
    am : Unit <- row("rb_self_nsrc", t_rb_self_nsrc())
    an : Unit <- row("rb_diff_none", t_rb_diff_none())
    ao : Unit <- row("rb_e_n0", t_rb_e_n0())
    ap : Unit <- row("rb_ixstg_none", t_rb_ixstg_none())
    aq : Unit <- row("aprt_none", t_aprt_none())
    ar : Unit <- row("aprt_r0t_none", t_aprt_r0t_none())
    as : Unit <- row("aprt_pglob", t_aprt_pglob())
    at : Unit <- row("aprt_pgloT_none", t_aprt_pgloT_none())
    au : Unit <- row("aprt_palu_none", t_aprt_palu_none())
    av : Unit <- row("aprt_paluT_none", t_aprt_paluT_none())
    aw : Unit <- row("aprt_b4_none", t_aprt_b4_none())
    ax : Unit <- row("ren_untagged_none", t_ren_untagged_none())
    ay : Unit <- row("ren_arg0", t_ren_arg0())
    az : Unit <- row("ren_next", t_ren_next())
    ba : Unit <- row("ren7_arg0", t_ren7_arg0())
    bb : Unit <- row("ren7_next", t_ren7_next())
    bc : Unit <- row("ren_axis_weak", t_ren_axis_weak())
    bd : Unit <- row("dg_ixpa_ans", t_dg_ixpa_ans())
    be : Unit <- row("dg_ixpg_none", t_dg_ixpg_none())
    be : Unit <- row("dg2_pat", t_dg2_pat())
    bf : Unit <- row("dg2_pg", t_dg2_pg())
    bg : Unit <- row("dg2_palu", t_dg2_palu())
    bh : Unit <- row("claim_ops_stg2", t_claim_ops_stg2())
    bh2 : Unit <- row("claim_ops_stg3", t_claim_ops_stg3())
    bh3 : Unit <- row("claim_ab_stg2", t_claim_ab_stg2())
    bi : Unit <- row("claim_ab_stg3", t_claim_ab_stg3())
    bj : Unit <- row("ab4_stg2", t_ab4_stg2())
    bk : Unit <- row("ab4_stg3", t_ab4_stg3())
    bl : Unit <- row("fb_two_stg2", t_fb_two_stg2())
    bm : Unit <- row("fb_two_stg3", t_fb_two_stg3())
    bn : Unit <- row("fb_sym_stg3", t_fb_sym_stg3())
    bo : Unit <- row("ab8_sti", t_ab8_sti())
    bp : Unit <- row("ab8_std_none", t_ab8_std_none())
    bq : Unit <- row("ab7_cli_nsrc", t_ab7_cli_nsrc())
    br : Unit <- row("rej_ct4", t_rej_ct4())
    bs : Unit <- row("rej_ct7", t_rej_ct7())
    bt : Unit <- row("rej_dg3", t_rej_dg3())
    bu : Unit <- row("rej_ab8", t_rej_ab8())
    bv : Unit <- row("raf_aftn_is_src0", t_raf_aftn_is_src0())
    bw : Unit <- row("ab8_stc0_none", t_ab8_stc0_none())
    bx : Unit <- row("nv_rsaf_ans", t_nv_rsaf_ans())
    by : Unit <- row("dg_r0t_ans", t_dg_r0t_ans())
    bz : Unit <- row("ren_axis_out", t_ren_axis_out())
    ca : Unit <- row("ab7_clik_nsrc", t_ab7_clik_nsrc())
    cb : Unit <- row("ab7_clik_arg", t_ab7_clik_arg())
    cc : Unit <- row("ab7_clik0_arg", t_ab7_clik0_arg())
    cd : Unit <- row("nic_clik_nsrc", t_nic_clik_nsrc())
    ce : Unit <- row("nic_clik_arg", t_nic_clik_arg())
    cf : Unit <- row("ct4a_claim", t_ct4a_claim())
    cg : Unit <- row("ct4b_claim", t_ct4b_claim())
    ch : Unit <- row("ct4a_ans", t_ct4a_ans())
    ci : Unit <- row("ct4a_tail", t_ct4a_tail())
    cj : Unit <- row("ct4d_tail", t_ct4d_tail())
    ck : Unit <- row("ct4d_none", t_ct4d_none())
    cl : Unit <- row("ct5c_claim", t_ct5c_claim())
    cm : Unit <- row("ct5k_claim", t_ct5k_claim())
    cn : Unit <- row("ct5b_claim", t_ct5b_claim())
    co : Unit <- row("ct5c_pat", t_ct5c_pat())
    cp : Unit <- row("ct5k_pat", t_ct5k_pat())
    cq : Unit <- row("ct5b_pat", t_ct5b_pat())
    cr : Unit <- row("ct5c_ans", t_ct5c_ans())
    cs : Unit <- row("ct8d_claim", t_ct8d_claim())
    ct : Unit <- row("mstc_claim", t_mstc_claim())
    cu : Unit <- row("ct8d_devnone", t_ct8d_devnone())
    cv : Unit <- row("ct8b_devnone", t_ct8b_devnone())
    cw : Unit <- row("ct8d_srcops", t_ct8d_srcops())
    cx : Unit <- row("ct8r_srcops", t_ct8r_srcops())
    cy : Unit <- row("ct8d_new", t_ct8d_new())
    cz : Unit <- row("ct8r_arg", t_ct8r_arg())
    da : Unit <- row("ct8r0_arg", t_ct8r0_arg())
    db : Unit <- row("ct8r_axis", t_ct8r_axis())
    dc : Unit <- row("ct8r0_axis", t_ct8r0_axis())
    dd : Unit <- row("ct8b_none", t_ct8b_none())
    de : Unit <- row("ct7a_claim", t_ct7a_claim())
    df : Unit <- row("ct7a_cnt", t_ct7a_cnt())
    dj : Unit <- row("ct7b_cnt", t_ct7b_cnt())
    dk : Unit <- row("ct7b_none", t_ct7b_none())
    dh : Unit <- row("ren_axis_out_dev", t_ren_axis_out_dev())
    dg : Unit <- row("ren_axis_in_dev", t_ren_axis_in_dev())
    row("spec", t_spec())

