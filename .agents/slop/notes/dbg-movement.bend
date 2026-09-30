# movement.bend -- tinygrad/uop/movement.py. `mop_cleanup`: the nine rules that
# strictly CLEAN UP movement ops, in the compiled form `upat.py` emits.
#
# # TODO: pm_mops from rangeify belongs here. this is all pattern matchers that
# strictly clean up movement ops
#
# WHAT THIS FILE IS, and how it differs from `spec.bend`. `spec.py` is a graph
# VALIDATOR: for one node it answers True/False/None, and a verdict is enough.
# This is a REWRITER: for one node it answers a NEW UOP or `None`. Every rule
# here is a construction -- `x.replace(src=...)`, `x._mop(...)`,
# `a.src[i.val].index(...)`, `x2 if ... else None` -- so a rule returns a NODE,
# and the pass has to say WHICH one.
#
# ---------------------------------------------------------------------------
# THE SHAPE, and the answer to "a rule returns the arena, but which node?"
#
# `.agents/slop/notes/engine-shape.bend` settles that a rewrite rule RETURNS THE
# ARENA and not a pair, because a pair makes the engine `match` on a computed
# value and Bend refuses. Folding `Hop`s has no such problem -- the verdict IS
# the arena, and it is a `Data` record, so there is no `(A & B)` to destructure.
# The cost that note names, though, is real there: a rule is a `Type` because it
# holds a closure, so the table is LINEAR and a second pass rebuilds it.
#
# THAT COST DOES NOT EXIST HERE, and the reason is that ops.bend's `PMEntry` is a
# `Data` record holding a TAG. So the rules are top-level defs selected by a
# `match` on the tag -- `mp_dispatch` -- exactly as `ops.bend`'s `pm_dispatch`
# and `spec.bend`'s six `sh_`/`te_`/`pr_`/`hq_`/`fu_`/`kg_` dispatches are. The
# table is a `List<PMEntry>`, which is COPYABLE, so a second pass reuses it and
# costs nothing. The gate row `twice` is that claim, measured. The price is nine
# `case` arms instead of a closure, which is the price `spec.bend` already pays
# 84 times and argues for.
#
# So the shape is ONE recursive def and four leaves around it:
#
#     def mp_scan(rs, +tb, +ler, +self, +h) -> Hop:
#       match rs:
#         case Nil{}: h
#         case e <> t: mp_scan(t, tb, ler, self, hop_next(h, mp_try(tb, hop_ar(h), self, ler, e)))
#
# and FOUR things make that correct.
#
#   1. `at == 0` IS PYTHON'S `None`, and that is not a new convention: ops.bend
#      already reserves arena index 0 and says so ("INDEX 0 IS RESERVED ... 0 is
#      this port's spelling of both Python's `None` UOp and the IndexError that
#      `self.src[0]` on an empty src raises"). `O.UOp.is_none` is the test. A rule
#      that fires returns a real index; a rule that skips returns 0.
#   2. A RULE THAT DOES NOT FIRE MUST NOT GROW THE ARENA. In Python the pattern
#      is matched before the lambda runs, so a rule whose body returns `None`
#      never constructs anything. Here the tests and the construction sit in one
#      `match` and the construction sits in the TAKEN arm -- so a rule that hands
#      back an existing node and a rule that interns a new one differ in the
#      arena size, and the gate pins both (`grow_new`, `grow_same`).
#   3. `ler` IS COMPUTED ONCE, which is `uop.__dict__['_src_ops']`. Python caches
#      it on the uop; ops.bend's `pm_ler` recomputes it per rule and names that
#      as the one place the port is slower. Here it is a `+` parameter, and that
#      is not a pessimisation: the node under examination is FIXED for the whole
#      pass, because every rule here returns either a freshly interned node or a
#      STRICT ANCESTOR in the DAG, and neither changes `self`'s srcs. One
#      `pm_ler` per `mop_cleanup` is the cache, exactly.
#   4. THE TABLE'S `DATA` AND THE FOLD'S `Table` TRAVEL APART. `F.Folded` is
#      `{ar, tb}` and fold.bend's header says why the two are bundled: the fold
#      reads the table once per SRC of every node it answers, so a bare `List`
#      cannot be the store. But the arena here GROWS mid-pass while the table
#      must not -- a `tb` built on the pre-pass arena is still the right answer
#      for every node a rule can ask about, and `F.fold.shape` ignores its `ar`
#      argument anyway. So a rule takes `+tb` and the arena separately.
#
# ---------------------------------------------------------------------------
# WHAT IS DEFERRED, and each wall. Every `# TODO(p3)` names a Python line.
#
#   * `marg` (ops.py:813) and `_mop` (ops.py:821) -- `movement.py:7-8`, rule 0.
#     `marg` needs `as_shape`, and `as_shape`'s middle arm is `(ssimplify(self),)`
#     for anything that is neither a CONST nor a STACK, and `ssimplify` is
#     `UOp.simplify` (ops.py:513) which is `graph_rewrite(self, symbolic)`.
#     `symbolic` is `tinygrad/uop/symbolic.py`, a file this phase does not have
#     -- and it is worse than a missing import, because a rule that called
#     `graph_rewrite` would be the rewrite engine calling itself, which is the
#     mutual recursion Bend refuses. THE WALL IS STRUCTURAL, not an import.
#     WHAT IS PORTED is the part that needs none of it: `as_shape` restricted to
#     CONST and STACK-of-CONST (the two arms that never reach `ssimplify`), the
#     `zip`, the `(o+p, n)` arithmetic, and `_mop`'s NODE for the case where
#     `UOp.sink(*usrcs).simplify()` is ops.py:515's EARLY RETURN -- which holds
#     exactly when both `shape_to_shape_arg` results are CONSTs, that is, one
#     axis per side. So `mp_0` fires at rank 1 and SKIPS at rank >= 2, where
#     `simplify()` would see a SINK of STACKs and call `symbolic`. Measured on
#     this repo's Python: at rank 2 that `simplify()` happens to be the identity,
#     but one fixture is not a proof about `symbolic`, so the rank >= 2 case is
#     not ported and the gate row `shrink2` says so.
#   * THE SIX MOVEMENT SHAPES. `mp_2` (movement.py:12) tests `x2._shape is not
#     None and x2.shape == x.shape`, and `x` is a RESHAPE, so it needs a
#     RESHAPE's `_shape`. fold.bend's ladder DEFERS RESHAPE, and PERMUTE, EXPAND,
#     PAD, SHRINK and FLIP with it, for the reason above (`# marg -> as_shape ->
#     ssimplify`). So `mp_2`'s test cannot be evaluated for any node whose op is
#     a movement op, and it is reachable only when `x2` is something else -- a
#     BUFFER, an INDEX, an ALU. `reshape_noop` is that fixture and it fires. What
#     cannot be said is the case the rule was written for, a RESHAPE over a
#     RESHAPE of the same shape; `mp_1` (the merge) covers that one instead, which
#     is why the first-wins row is about `mp_1` and not about `mp_2`.
#   * `storage_base` (ops.py:801) is NOT needed here and this file does not
#     defer it. Recorded because the brief asks: no rule in movement.py reads it,
#     and `spec.bend`'s `sh_31` is the one that does.
#   * `a.src[i.val]` (movement.py:22) is an INDEX into a variable-length list.
#     Python raises `IndexError`; `O.Arena.src` answers 0, which is this port's
#     EXISTING spelling of that IndexError, so the rule yields the bottom node.
#   * `x2.arg[i] for i in x.arg` (movement.py:14) is the same question. Python
#     raises; `List.get` gives a `Maybe` and `Maybe.default` gives 0. `spec.py`
#     requires a PERMUTE's arg to be a permutation of `range(len(arg))` of its
#     operand's rank, so the two args have equal length and the IndexError is
#     unreachable on a legal arena. Recorded, not worked around.
#   * A FLOAT CONST where an int is wanted: `[x.src[1].val for x in stk.src] ==
#     list(range(len(stk.src)))` compares Python ints against a list that may hold
#     `1.0`, and `1.0 == 1` is True, so the rule fires. `const_i64` answers `None`
#     for a `CFloat`, so this port does not. The conversion is `dtypes.from_py`
#     (dtype.py:100), a `TODO(p3)` in ops.bend, and a float offset in a STACK is
#     rejected by `spec.py` before it can get here.
#   * `ret is not uop` (ops.py:1611) is PORTED, in `hop_self`, and it is NOT
#     REACHABLE FROM ANY OF THESE NINE RULES. Every return is either a freshly
#     interned node or a strict ancestor in the DAG, and the arena is a DAG by
#     construction, so no rule can hand back its own input. It is here because it
#     belongs to `PatternMatcher.rewrite` and the next ported rewriter needs it;
#     `ret_self`/`ret_new` exercise it directly.
#
# ---------------------------------------------------------------------------
# TWO FACTS THAT ARE EASY TO INVERT, both measured against movement.py.
#
# 1. `early_reject` IS A NECESSARY CONDITION, not a veto, despite the name:
#    `ops.py:1609` is `if not early_reject.issubset(ler): continue`, so a rule
#    FIRES when the op set IS a subset of `ler` and is SKIPPED when it is not.
#    It is the set of the ops of the pattern's OWN SRCS (ops.py:1477, over
#    `self.src[0]`), not of one src. Eight of the nine sets here are non-empty --
#    `movement.py:12` (a bare `UPat()` first src) and `movement.py:16` (no srcs
#    at all) are the two empty ones -- and EVERY non-empty set is implied by its
#    own pattern's op test, so, as in spec.bend, no verdict in this file is
#    decided by the subset test. The mutation table records the and->or flip
#    moving NOTHING, which is the measured proof of "implied" rather than an
#    assertion about it. Rule 6 (movement.py:21) is the only two-element set,
#    `{STACK, CONST}`, because `UPat.cvar("i")` carries `Ops.CONST`; `rej_pair`
#    is its row, and it is also the only rule whose reject set can be longer than
#    the number of srcs the arena has, so it is the only row that can catch a set
#    spelled one op too big.
# 2. A NAME BOUND TWICE MUST EMIT AN IDENTITY CHECK (`upat.py:100-105` builds it
#    as the literal `"{0} is {1}"`). movement.py binds every capture name once per
#    rule -- `x`/`s`, `x`/`x2`, `x`/`x2`, `x`, `src`/`stk`, `a`/`i`/`idx`,
#    `idx1`/`idx2`, `buf`/`idx1_arg`/`idx2` -- and `rg -n 'name="' movement.py`
#    shows no name twice, so there is no identity check to write here. Adding one
#    would be a bug: `x2` in `mp_1`, `mp_2` and `mp_3` is three different
#    patterns, not a conjunction.
# ---------------------------------------------------------------------------

import Base
import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/LAWS/spec.bend as S
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/uop/fold.bend as F

# ===========================================================================
# THE RESULT. A rule's answer: the arena as it stands after that rule, and
# WHICH node the rule produced. `at == 0` is Python's `None`; see the header.
# `mp_hit` is the one place a freshly interned node becomes a `Hop`, so none of
# the nine rules spells `Found.ar`/`Found.i` itself.
# ===========================================================================
type Hop is Data:
  Hop{ar: O.Arena, at: U32}

def hop_ar(h: Hop) -> O.Arena:
  match h:
    case Hop{ar, at}: ar

def hop_ix(h: Hop) -> U32:
  match h:
    case Hop{ar, at}: at

def mp_hit(+f: O.Found) -> Hop:
  Hop{O.Found.ar(f), O.Found.i(f)}

# `PatternMatcher.rewrite` returns the FIRST non-None, so this is a fold with
# first-wins. Keying on the ACCUMULATOR is what makes it first-wins: keying on
# the new result is last-wins, and then a rule that skips erases every earlier
# answer. Measured: the last-wins mutation moves `reshape_pick`.
def hop_first.of(b: Bool, +hold: U32, r: U32) -> U32:
  match b:
    case True{}: r
    case False{}: hold

def hop_first(+hold: U32, r: U32) -> U32:
  hop_first.of(O.UOp.is_none(hold), hold, r)

# THE FOLD, and the arena threading. A later rule builds in the arena an earlier
# rule produced, so the next arm reads `hop_ar(h)` and not the arena it was
# handed. `r.ar` is the current arena either way, because a rule that does not
# fire returns the arena it was given.
def hop_next(h: Hop, r: Hop) -> Hop:
  match h r:
    case Hop{ha, hn} Hop{ra, rn}: Hop{ra, hop_first(hn, rn)}

# `ret is not uop` -- ops.py:1611. The arena KEEPS whatever the rule built (the
# node really was interned) and only the ANSWER is dropped, which is Python's
# `return None` after a construction.
def hop_self.of(b: Bool, +r: Hop) -> Hop:
  match b:
    case True{}: r
    case False{}: Hop{hop_ar(r), 0}

def hop_self(+r: Hop, self: U32) -> Hop:
  hop_self.of(Bool.or(U32.is_eq(hop_ix(r), self), O.UOp.is_none(hop_ix(r))), r)

# ===========================================================================
# THE READERS. `spec.bend`'s `sp_*`, renamed `mp_*` because these read the
# CURRENT arena rather than a `Folded` -- see the header, point 4. `O.Arena.op`,
# `O.Arena.arg`, `O.Arena.src`, `O.Arena.nsrc` and `O.Arena.src_from` are
# ops.bend's OWN readers and return BARE values, not `Maybe`. Four compile cycles
# were lost to that once across this port, so it is worth saying twice.
# ===========================================================================
def mp_op(ar: O.Arena, i: U32) -> O.Op:
  O.Arena.op(ar, i)

def mp_arg(ar: O.Arena, i: U32) -> O.Arg:
  O.Arena.arg(ar, i)

def mp_tag(ar: O.Arena, i: U32) -> O.Tag:
  O.Arena.tag(ar, i)

def mp_src(ar: O.Arena, i: U32, n: U32) -> U32:
  O.Arena.src(ar, i, n)

def mp_src0(ar: O.Arena, i: U32) -> U32:
  O.Arena.src0(ar, i)

def mp_nsrc(ar: O.Arena, i: U32) -> U32:
  O.Arena.nsrc(ar, i)

def mp_srcs(ar: O.Arena, i: U32) -> List<&2, U32>:
  O.Arena.srcs(ar, i)

def mp_src_from(ar: O.Arena, i: U32, k: U32) -> List<&2, U32>:
  O.Arena.src_from(ar, i, k)

def mp_is(ar: O.Arena, i: U32, want: O.Op) -> Bool:
  O.eq_op(mp_op(ar, i), want)

def mp_nsrc_is(ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_eq(mp_nsrc(ar, i), n)

def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_lt(n, mp_nsrc(ar, i))

def mp_nat(ss: List<&2, U32>) -> Nat:
  List.length(&2, U32, ss)

# `x.shape` -- ops.py:456, which is `_shape` unless `_shape` is None, in which
# case it is a fresh UNIQUE UOp. So the fold's shape is a DOUBLE `Maybe`: the
# outer is "the table has no entry", the inner is `_shape` being None. All four
# places the rules read a shape want the inner, so `shp_of` is the one test.
def mp_shape(tb: F.Table, ar: O.Arena, i: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  F.fold.shape(ar, tb, i)

def shp_of.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case None{}: None{}

def shp_of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  shp_of.go(m)

# `x.shape == y.shape` -- `movement.py:12`'s second conjunct and `movement.py:19`'s
# first. `F.eq_sints` is fold.bend's element-wise walk, and a shape element that
# is a uop rather than a literal compares by index, which is what Python's `==`
# on `sint`s does.
def shp_same.go(a: Maybe<&2, List<&2, O.Sint>>, b: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match a b:
    case Some{x} Some{y}: F.eq_sints(x, y)
    case _ _: False{}

def shp_same(+tb: F.Table, +ar: O.Arena, j: U32, k: U32) -> Bool:
  shp_same.go(shp_of(mp_shape(tb, ar, j)), shp_of(mp_shape(tb, ar, k)))

# `all(x.shape == () for x in xs)` -- `movement.py:25`. `()` is the empty shape
# and a CONST's `_shape` is `()`, so this is `eq_sints(xs, Nil{})`. `True` for an
# empty `xs`, which is `all([])` and is what lets `INDEX(INDEX(x))` fire.
def shp_one.go(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case Some{Nil{}}: True{}
    case _: False{}

def shp_one(+tb: F.Table, ar: O.Arena, i: U32) -> Bool:
  shp_one.go(shp_of(mp_shape(tb, ar, i)))

def shp_each.go(xs: List<&2, U32>, rest: List<&2, U32>, +tb: F.Table, +ar: O.Arena) -> Bool:
  match xs rest:
    case Nil{} _       : True{}
    case x <> _ Nil{}  : False{}
    case x <> t y <> u : Bool.and(shp_each.go(t, u, tb, ar), shp_one(tb, ar, x))

def shp_each(+tb: F.Table, ar: O.Arena, +xs: List<&2, U32>) -> Bool:
  shp_each.go(xs, xs, tb, ar)

# `len(idx1_arg.shape) == len(idx2.src[1:])` -- `movement.py:28`. Python's `len`
# of `shape` RAISES when `_shape` is None, because `shape` is then a UNIQUE UOp
# and a UOp has no `__len__`; so `None` is the answer that does not fire.
def shp_n.go(m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, Nat>:
  match m:
    case Some{ds}: Some{List.length(&2, O.Sint, ds)}
    case None{}: None{}

def shp_n(m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, Nat>:
  shp_n.go(m)

def shp_n_is.go(m: Maybe<&1, Nat>, n: Nat) -> Bool:
  match m:
    case Some{k}: Nat.is_eq(k, n)
    case None{}: False{}

def shp_n_is(+tb: F.Table, ar: O.Arena, i: U32, n: Nat) -> Bool:
  shp_n_is.go(shp_n(shp_of(mp_shape(tb, ar, i))), n)

# `x.arg` for a PERMUTE is `tuple[int, ...]`, which ops.bend models as `ATuple`.
# This is `movement.py:14`'s `x.arg` and `x2.arg` and `movement.py:16`'s `x.arg`.
def arg_tuple.go(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ATuple{ys}: Some{ys}
    case _: None{}

def arg_tuple(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  arg_tuple.go(a)

# The value of a CONST as an `I64` -- `.val` reads `self.arg` (ops.py:259).
# `CBool` is Python's `True`/`False` and `True == 1`, so a bool CONST answers
# 1/0 rather than nothing; that is the whole of `movement.py:19`'s
# `[x.src[1].val for x in stk.src]`. A `CFloat` answers nothing: see the header,
# "a float CONST where an int is wanted".
def const_i64.go(a: O.Arg) -> Maybe<&2, H.I64>:
  match a:
    case O.APy{O.CInt{i}}   : Some{i}
    case O.APy{O.CBool{True{}}}: Some{H.i64_of_i32(1)}
    case O.APy{O.CBool{False{}}}: Some{H.i64_of_i32(0)}
    case _: None{}

def const_i64(a: O.Arg) -> Maybe<&2, H.I64>:
  const_i64.go(a)

# The same value as a `U32`, for the two places it is a src INDEX rather than an
# int to compare. Python's `a.src[-1]` would read from the END and a float index
# is a TypeError, so the only value this port can use is a non-negative int, and
# everything else answers 0 -- which is ops.bend's existing spelling of both
# Python's `None` UOp and the IndexError.
def i64_u32.of(b: Bool, lo: U32) -> U32:
  match b:
    case True{}: lo
    case False{}: 0

def i64_u32(+x: H.I64) -> U32:
  i64_u32.of(U32.is_zero(H.hi32(x)), H.lo32(x))

# `x.arg[n]` -- the permutation composition of `movement.py:14`.
def list_at(xs: List<&2, U32>, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(n)), 0)

def const_is.go(m: Maybe<&2, H.I64>, n: Nat) -> Bool:
  match m:
    case Some{v}: Cmp.is_eq(H.i64_cmp(v, H.i64_of_i32(U32.from_nat(n))))
    case None{}: False{}

# ===========================================================================
# `UOp.index` -- ops.py:581. It is the one Python method in this file's
# dependency set that ops.bend's inventory lists as not ported
# (`# TODO(p3) ops.py:581  def index`), three of these nine rules call it, and it
# belongs in ops.bend the next time that file is edited.
#
#     def index(self, *srcs, **kwargs):
#       new_srcs = [UOp.const(x) if isinstance(x, int) else x for x in srcs if x is not None]
#       if len(new_srcs) == 1 and new_srcs[0].op is Ops.CONST and self.op is Ops.STACK: return self.src[new_srcs[0].val]
#       return UOp(Ops.INDEX, src=(self,)+tuple(new_srcs), **kwargs)
#
# THE SPECIAL CASE IS NOT A NICETY. It is why a rewrite here can return a node it
# did not build, and `idx_pick` is the row for it: `INDEX(INDEX(STACK, C1))` has
# no offsets at all, so the outer `index()` sees one CONST src over a STACK and
# hands back `STACK.src[1]`. Every `extra` is already a UOp index and never a
# Python int, so the `UOp.const(x)` half and the `is not None` filter are both
# vacuous here and are not written. `(self,)+tuple(new_srcs)` is a HEAD, not a
# tail, so `mp_index.new` prepends.
# ===========================================================================
def mp_index.pick(sel: Maybe<&1, U32>) -> U32:
  Maybe.default(&1, U32, sel, 0)

def mp_index.new(+ar: O.Arena, self: U32, extra: List<&2, U32>) -> Hop:
  mp_hit(O.UOp.new(ar, O.OpsINDEX{}, List.append(&2, U32, [self], extra), O.ANone{}, O.TNone{}))

def mp_index.of(sel: Maybe<&1, U32>, one: Bool, stack: Bool, +ar: O.Arena, self: U32, extra: List<&2, U32>) -> Hop:
  match one stack:
    case True{} True{}: Hop{ar, mp_index.pick(sel)}
    case _ _: mp_index.new(ar, self, extra)

def mp_const_val.of(m: Maybe<&2, H.I64>) -> H.I64:
  match m:
    case Some{v}: v
    case None{}: H.i64_of_i32(0)

def mp_const_val(ar: O.Arena, i: U32) -> H.I64:
  mp_const_val.of(const_i64(mp_arg(ar, i)))

# `self.src[new_srcs[0].val]`, the IndexError included: `Arena.src` answers 0.
def mp_stack_val(ar: O.Arena, self: U32, extra: List<&2, U32>) -> Maybe<&1, U32>:
  match extra:
    case e <> Nil{}: Some{i64_u32(mp_const_val(ar, e))}
    case _: None{}


def mp_index(+ar: O.Arena, +self: U32, +extra: List<&2, U32>) -> Hop:
  mp_index.of(mp_stack_val(ar, self, extra), Nat.is_eq(mp_nat(extra), 1n), mp_is(ar, self, O.OpsSTACK{}), ar, self, extra)

# `x.src[1].val`, which is an `I64` and a `Maybe` because `.val` is only for a
# CONST or a CAST of one (ops.py:259-262), and a STACK's element is a CONST.
def mp_const(ar: O.Arena, i: U32) -> Maybe<&2, H.I64>:
  const_i64(mp_arg(ar, i))

# `x.src[1].val == k` and `i.val == k`: the two places a CONST's value is
# compared with a position in a list.
def const_is(ar: O.Arena, i: U32, n: Nat) -> Bool:
  const_is.go(mp_const(ar, i), n)

# ===========================================================================
# `UOp.replace` -- ops.py:252. `if (self.op, self.src, self.arg, self.tag) ==
# new_args: return self` needs no code here: the arena hash-conses, so it hands
# back the same index, and `hop_self` is what turns "the answer is the node
# itself" into no answer.
# ===========================================================================
def mp_replace(op: O.Op, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Hop:
  mp_hit(O.UOp.new(ar, op, src, mp_arg(ar, self), mp_tag(ar, self)))

# ===========================================================================
# `as_shape` -- ops.py:807 -- and `marg` -- ops.py:813, SHRINK's arm.
#
#     def as_shape(self):
#       if self.op is Ops.CONST: return (self.val,)
#       if self.op is not Ops.STACK: return (ssimplify(self),)
#       return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)
#
#     case Ops.PAD | Ops.SHRINK: return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
#
# TWO ARMS ARE PORTED and the middle one is not, and that is the whole deferral:
# the middle arm is `ssimplify`, which is `graph_rewrite(self, symbolic)`. So
# `as_shape` here answers for a CONST and for a STACK of CONSTs -- exactly the
# shapes `_mop` itself builds, since `shape_to_shape_arg` makes a CONST for a
# one-element shape and a STACK of CONSTs for a longer one -- and `None`
# otherwise. The elements are `H.I64` and not `O.Sint`, because an `O.Sint`
# element that is a uop would make `o+p` a symbolic sum, and the merged margin is
# `o+p` with a literal `p`.
# ===========================================================================
def as_shape.one.of(v: Maybe<&2, H.I64>) -> Maybe<&1, List<&2, H.I64>>:
  match v:
    case Some{c}: Some{[c]}
    case None{}  : None{}

def as_shape.one(+ar: O.Arena, +i: U32) -> Maybe<&1, List<&2, H.I64>>:
  as_shape.one.of(mp_const(ar, i))

# `tuple(s.val if s.op is CONST else ssimplify(s) for s in self.src)`, split in
# two because a `Maybe` is a `Type` and cannot be an accumulator, so the
# `s.op is CONST` test and the value collection are two folds over the same
# short list. `mp_const_val`'s 0 default is unreachable on a legal arena:
# `shape_to_shape_arg` (ops.py:106) raises unless every element is an int, so a
# STACK shape never holds a float.
def as_shape.allc.go(ss: List<&2, U32>, +ar: O.Arena) -> Bool:
  match ss:
    case Nil{}  : True{}
    case x <> t : Bool.and(mp_is(ar, x, O.OpsCONST{}), as_shape.allc.go(t, ar))

def as_shape.vals.go(ss: List<&2, U32>, +ar: O.Arena, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match ss:
    case Nil{}  : acc
    case x <> t : as_shape.vals.go(t, ar, List.append(&2, H.I64, acc, [mp_const_val(ar, x)]))

def as_shape.stack.of(ok: Bool, ss: List<&2, H.I64>) -> Maybe<&1, List<&2, H.I64>>:
  match ok:
    case True{} : Some{ss}
    case False{}: None{}

def as_shape.stack(+ar: O.Arena, +i: U32) -> Maybe<&1, List<&2, H.I64>>:
  as_shape.stack.of(as_shape.allc.go(mp_srcs(ar, i), ar), as_shape.vals.go(mp_srcs(ar, i), ar, Nil{}))

def as_shape.of_op(c: Bool, s: Bool, +ar: O.Arena, +i: U32) -> Maybe<&1, List<&2, H.I64>>:
  match c s:
    case True{} False{} : as_shape.one(ar, i)
    case False{} True{} : as_shape.stack(ar, i)
    case _ _             : None{}

def as_shape(+ar: O.Arena, +i: U32) -> Maybe<&1, List<&2, H.I64>>:
  as_shape.of_op(mp_is(ar, i, O.OpsCONST{}), mp_is(ar, i, O.OpsSTACK{}), ar, i)

# `Marg` is Python's `(o, n)` pair. It is a `Data` RECORD and not the tuple
# `(H.I64 & H.I64)` because a pair is a `Type`, Bend's affine handler, and a
# `Type` cannot be a list element: `List<&2, H.I64 & H.I64>` is refused with
# "expected : Data / observed : Type". Measured.
type Marg is Data:
  Marg{o: H.I64, n: H.I64}

# Bend has no `x.field`, so the two accessors are the price of a record instead
# of a tuple; ops.bend's header calls this "the whole trick" and it is two lines
# each. Everywhere a `Marg` is already destructured by a `match` these are not
# used.
def Marg.o(x: Marg) -> H.I64:
  match x:
    case Marg{o, n}: o

def Marg.n(x: Marg) -> H.I64:
  match x:
    case Marg{o, n}: n

# `(o + p, n)` -- the whole of `movement.py:8`'s generator. `n` is `s.marg`'s, so
# the SIZE of the inner shrink survives, and the offset is the sum.
def marg.step(acc: List<&2, Marg>, x: Marg, y: Marg) -> List<&2, Marg>:
  match x y:
    case Marg{xo, xn} Marg{yo, yn}: List.append(&2, Marg, acc, [Marg{H.i64_add(xo, yo), yn}])

# `zip(x.marg, s.marg)`, which TRUNCATES to the shorter, so an empty side gives
# an empty margin and `mp_0` then lands on `_mop`'s `len(arg) == 0` early return.
# The truncation is the two `Nil{}` arms rather than a length test, so it is the
# same `zip`.
def marg.go(ys: List<&2, Marg>, xs: List<&2, Marg>, acc: List<&2, Marg>) -> List<&2, Marg>:
  match ys xs:
    case Nil{} _        : acc
    case _ <> _ Nil{}   : acc
    case y <> yt x <> xt: marg.step(marg.go(yt, xt, acc), x, y)

def marg(ys: List<&2, Marg>, xs: List<&2, Marg>) -> List<&2, Marg>:
  marg.go(ys, xs, Nil{})

# `zip(self.src[1].as_shape, self.src[2].as_shape)` -- SHRINK's arm of `marg`,
# and it truncates to the shorter side exactly as the `zip` below does.
def marg_zip.go(ys: List<&2, H.I64>, xs: List<&2, H.I64>, acc: List<&2, Marg>) -> List<&2, Marg>:
  match ys xs:
    case Nil{} _        : acc
    case _ <> _ Nil{}   : acc
    case y <> yt x <> xt: marg_zip.go(yt, xt, List.append(&2, Marg, acc, [Marg{x, y}]))

def marg_zip(ys: List<&2, H.I64>, xs: List<&2, H.I64>) -> List<&2, Marg>:
  marg_zip.go(ys, xs, Nil{})

# `tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg))`, with the four `None`s
# folded into one: a margin is a margin only if BOTH `as_shape`s of BOTH shrinks
# are. `x` is the OUTER shrink and `s` the inner one, and Python keeps `n` from
# `s.marg`, which is why the fold's second argument is `s.marg`.
def marg_add.of(ox: Maybe<&1, List<&2, H.I64>>, nx: Maybe<&1, List<&2, H.I64>>,
                os: Maybe<&1, List<&2, H.I64>>, ns: Maybe<&1, List<&2, H.I64>>) -> Maybe<&1, List<&2, Marg>>:
  match ox nx os ns:
    case Some{a} Some{b} Some{c} Some{d}: Some{marg(marg_zip(d, c), marg_zip(b, a))}
    case _ _ _ _                         : None{}

def marg_add(+ar: O.Arena, +x: U32, +s: U32) -> Maybe<&1, List<&2, Marg>>:
  marg_add.of(as_shape(ar, mp_src(ar, x, 1)), as_shape(ar, mp_src(ar, x, 2)),
              as_shape(ar, mp_src(ar, s, 1)), as_shape(ar, mp_src(ar, s, 2)))

# ===========================================================================
# THE NINE RULES, in movement.py's order. Each `match` is on BOOLS: the first is
# the pattern's own tests, the rest are the LAMBDA's condition. That is
# `upat.py`'s split exactly -- the compiled `and_clause` is the pattern and the
# body is the lambda -- and it keeps every construction in a TAKEN arm, so a rule
# that does not fire interns nothing (header, point 2). `mp_try` has already run
# `early_reject`, so the tests here are the ones the subset test cannot stand in
# for: an op test is a claim about ONE src, while `ler` is the ops of ALL of them.
# ===========================================================================

# (movement.py:7-8) merge adjacent SHRINKs
#   UPat(Ops.SHRINK, name="x").f(Ops.SHRINK, allow_any_len=True, name="s")
#   lambda s,x: x.src[0]._mop(Ops.SHRINK, tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg)))
# `x.src[0]._mop(op, arg)` for SHRINK is `UOp(op, src=(self,)+UOp.sink(*usrcs).
# simplify().src)` with `usrcs = [shape_to_shape_arg(o), shape_to_shape_arg(n)]`,
# so the node is `SHRINK(x.src[0], <o>, <n>)`, and `shape_to_shape_arg` of a ONE
# element shape is `src[0]`, a bare CONST (ops.py:106). Both `as_shape`s are
# `x.marg`'s sides, and `x` is the OUTER shrink.
# TODO(p3) movement.py:7  rank >= 2: `UOp.sink(*usrcs).simplify()` there sees a
#   SINK of STACKs and calls `graph_rewrite(self, symbolic)`, which is
#   tinygrad/uop/symbolic.py. A rule that called `graph_rewrite` is the rewrite
#   engine calling itself. WALL: structural, not a missing import. Measured on
#   this repo's Python: at rank 2 that `simplify()` is the identity on a
#   pure-CONST fixture, which is not a proof about `symbolic`.
def mp_0.shrink(+ar: O.Arena, +self: U32, +m: Marg) -> Hop:
  +o = O.UOp.const(ar, O.CInt{Marg.o(m)})
  +s = O.UOp.const(O.Found.ar(o), O.CInt{Marg.n(m)})
  mp_hit(O.UOp.new(O.Found.ar(s), O.OpsSHRINK{}, [mp_src0(ar, self), O.Found.i(o), O.Found.i(s)], O.ANone{}, O.TNone{}))

# THE RANK TEST, and it is the whole of the `_mop` deferral. `_mop`'s node is
# buildable exactly when `UOp.sink(*usrcs).simplify()` is ops.py:515's EARLY
# RETURN, which needs both `shape_to_shape_arg` results to be CONSTs -- that is,
# one axis per side. A merged margin of length 0 is `_mop`'s `len(arg) == 0` early
# NOOP, which returns `_mop`'s own `self`; that case is not reachable from
# `movement.py:8` on a legal arena (both `zip`ped shapes are the same length), so
# it answers nothing rather than claiming a half-ported `_mop`.
def mp_0.rank.build(+ar: O.Arena, +self: U32, ms: List<&2, Marg>) -> Hop:
  match ms:
    case m <> Nil{}: mp_0.shrink(ar, self, m)
    case _           : Hop{ar, 0}

def mp_0.of(pat: Bool, m: Maybe<&1, List<&2, Marg>>, +ar: O.Arena, +self: U32) -> Hop:
  match pat m:
    case True{} Some{ms}: mp_0.rank.build(ar, self, ms)
    case _ _             : Hop{ar, 0}

def mp_0(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_0.of(mp_is(ar, mp_src0(ar, self), O.OpsSHRINK{}), marg_add(ar, self, mp_src0(ar, self)), ar, self)

# (movement.py:10) merge adjacent RESHAPEs
#   UPat(Ops.RESHAPE, src=(UPat(Ops.RESHAPE, name="x2"), UPat()), name="x")
#   lambda x,x2: x.replace(src=(x2.src[0], x.src[1]))
# A two-tuple src with no `allow_any_len` sets `strict_length` (ops.py:1470), so
# the arity test is `== 2` and not `>= 2`.
def mp_1.of(pat: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match pat:
    case True{}: mp_replace(O.OpsRESHAPE{}, ar, self, [mp_src0(ar, mp_src0(ar, self)), mp_src(ar, self, 1)])
    case False{}: Hop{ar, 0}

def mp_1(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_1.of(Bool.and(mp_nsrc_is(ar, self, 2), mp_is(ar, mp_src0(ar, self), O.OpsRESHAPE{})), ar, self)

# (movement.py:12) remove noop RESHAPEs
#   UPat(Ops.RESHAPE, src=(UPat(name="x2"), UPat()), name="x")
#   lambda x,x2: x2 if x2._shape is not None and x2.shape == x.shape else None
# The answer is an EXISTING node, so nothing is interned. `shp_same` is False
# whenever EITHER side is None, which covers the `x2._shape is not None` half and
# the `x.shape` half at once -- and the `x.shape` half is the deferral, because
# `x` is a RESHAPE and fold.bend does not answer a movement op's shape.
def mp_2.of(pat: Bool, ok: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok:
    case True{} True{}: Hop{ar, mp_src0(ar, self)}
    case _ _           : Hop{ar, 0}

def mp_2(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_2.of(mp_nsrc_is(ar, self, 2), shp_same(tb, ar, mp_src0(ar, self), self), tb, ar, self)

# (movement.py:14) merge PERMUTEs
#   UPat(Ops.PERMUTE, src=(UPat(Ops.PERMUTE, name="x2"),), name="x")
#   lambda x,x2: x2.replace(arg=tuple(x2.arg[i] for i in x.arg))
# `replace` with a new `arg` and nothing else changed, so the src is `x2`'s and
# the op, tag and dtype are `x2`'s too. The one-element tuple src is strict, so
# the arity test is `== 1`.
# `tuple(x2.arg[i] for i in x.arg)` -- the IndexError is 0; see the header.
def mp_perm.go(todo: List<&2, U32>, +p2: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}  : acc
    case i <> t : mp_perm.go(t, p2, List.append(&2, U32, acc, [list_at(p2, i)]))

def mp_perm(p2: List<&2, U32>, xa: List<&2, U32>) -> List<&2, U32>:
  mp_perm.go(xa, p2, Nil{})

def mp_3.of(pat: Bool, arg: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +self: U32) -> Hop:
  match pat arg:
    case True{} Some{xa}: mp_replace(O.OpsPERMUTE{}, ar, mp_src0(ar, self),
                                     mp_perm(mp_srcs(ar, mp_src0(ar, self)), xa))
    case _ _             : Hop{ar, 0}

def mp_3(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_3.of(Bool.and(mp_nsrc_is(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsPERMUTE{})),
          arg_tuple(mp_arg(ar, self)), ar, self)

# (movement.py:16) remove noop PERMUTEs
#   UPat(Ops.PERMUTE, name="x")
#   lambda x: x.src[0] if list(x.arg) == list(range(len(x.arg))) else None
# No srcs in the pattern, so no arity test: `x.src[0]` is `Arena.src0` and its
# IndexError is the bottom.
def mp_4.of(ok: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match ok:
    case True{} : Hop{ar, mp_src0(ar, self)}
    case False{}: Hop{ar, 0}

# `list(x.arg) == list(range(len(x.arg)))`, as `arg[k] == k` for every k. THE
# FOLD IS ONE DEF with the element's verdict as a PARAMETER, because the element
# has to be matched on and a match may not scrutinise a call -- so splitting it
# into `.go` and `.at` would be the mutual recursion Bend refuses.
def mp_ident.at(todo: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +k: Nat, ok: Bool) -> Bool:
  match todo ok:
    case _ False{}        : False{}
    case None{} True{}    : False{}
    case Some{Nil{}} True{}: True{}
    case Some{i <> t} True{}: mp_ident.at(Some{t}, ar, 1n+k, const_is(ar, i, k))

def mp_4(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_4.of(mp_ident.at(arg_tuple(mp_arg(ar, self)), ar, 0n, True{}), ar, self)

# (movement.py:18-19) STACK on INDEX CONST
#   UPat(Ops.STACK, src=UPat(Ops.INDEX, src=(UPat.var("src"), UPat(Ops.CONST))), name="stk")
#   lambda src,stk: src if stk.shape == src.shape and list(range(len(stk.src))) == [x.src[1].val for x in stk.src] else None
# `src` is a UPat and not a tuple, so the STACK's own `strict_length` is False and
# its `required_len` is 0: the STACK needs at least one src. The inner INDEX
# pattern IS a two-tuple, so it is strict, and every stacked element must be a
# TWO-src `INDEX(_, CONST)` -- a three-src INDEX does not match and this was found
# by measurement, not by reading. `src` binds `stk.src[0].src[0]`, NOT
# `stk.src[0]`, and the shape equality is what makes the rule reachable at all:
# `_shape`'s STACK arm is `(len(src),) + self.src[0].shape`, so `stk.shape ==
# src.shape` holds exactly when `buf.shape[0] == len(stk.src)`.
def mp_5.of(pat: Bool, ok: Bool, elems: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok elems:
    case True{} True{} True{}: Hop{ar, mp_src0(ar, mp_src0(ar, self))}
    case _ _ _                : Hop{ar, 0}

# `[x.src[1].val for x in stk.src] == list(range(len(stk.src)))`, as
# `stk.src[k].src[1].val == k` for every k.
def mp_5.one(+ar: O.Arena, +x: U32, k: Nat) -> Bool:
  Bool.and(mp_is(ar, x, O.OpsINDEX{}),
           Bool.and(mp_nsrc_ge(ar, x, 2), const_is(ar, mp_src(ar, x, 1), k)))

# ONE DEF for the fold, for the reason `mp_ident.at` says.
def mp_5.each.at(ss: List<&2, U32>, +ar: O.Arena, +k: Nat, ok: Bool) -> Bool:
  match ss ok:
    case _ False{}        : False{}
    case Nil{} True{}     : True{}
    case x <> t True{}    : mp_5.each.at(t, ar, 1n+k, mp_5.one(ar, x, k))

def mp_5.each(ss: List<&2, U32>, ar: O.Arena, k: Nat) -> Bool:
  mp_5.each.at(ss, ar, k, True{})

def mp_5(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_5.of(mp_nsrc_ge(ar, self, 1), shp_same(tb, ar, mp_src0(ar, mp_src0(ar, self)), self),
          mp_5.each(mp_srcs(ar, self), ar, 0n), tb, ar, self)

# (movement.py:21-22) const INDEX into STACK is src
#   UPat(Ops.INDEX, src=(UPat(Ops.STACK, name="a"), UPat.cvar("i")), name="idx", allow_any_len=True)
#   lambda a,i,idx: a.src[i.val] if len(idx.src) <= 2 else a.src[i.val].index(*idx.src[2:])
# `UPat.cvar` carries `Ops.CONST`, so `i` is a CONST and the reject set is the only
# two-element one in the file. `allow_any_len` makes the arity `>= 2`. The
# `a.src[i.val]` half is read ONCE and given to `mp_index`, which is what makes
# Python's two-branch conditional one call here.
def mp_stack_src(+ar: O.Arena, +self: U32) -> U32:
  mp_src(ar, mp_src0(ar, self), i64_u32(mp_const_val(ar, mp_src(ar, self, 1))))

def mp_6.of(pat: Bool, two: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match pat two:
    case True{} True{} : Hop{ar, mp_stack_src(ar, self)}
    case True{} False{}: mp_index(ar, mp_stack_src(ar, self), mp_src_from(ar, self, 2))
    case _ _            : Hop{ar, 0}

def mp_6(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_6.of(Bool.and(mp_nsrc_ge(ar, self, 2),
                   Bool.and(mp_is(ar, mp_src0(ar, self), O.OpsSTACK{}),
                            mp_is(ar, mp_src(ar, self, 1), O.OpsCONST{}))),
          mp_nsrc_is(ar, self, 2), ar, self)

# (movement.py:24-25) INDEX on INDEX is INDEX
#   UPat(Ops.INDEX, src=(UPat(Ops.INDEX, name="idx1", allow_any_len=True),), allow_any_len=True, name="idx2")
#   lambda idx1,idx2: idx1.src[0].index(*idx1.src[1:], *idx2.src[1:]) if all(x.shape == () for x in idx1.src[1:]+idx2.src[1:]) else None
# Both arities are `>= 1`, so `INDEX(x)` matches on its own and the two `src[1:]`
# slices are then empty -- `all([])` is true, and the fixture `idx_pick` is
# exactly that case. The answer is `mp_index` on the inner buffer with the two
# offset slices CONCATENATED, which is what `*a, *b` does.
def mp_7.of(pat: Bool, outer: Bool, inner: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat outer inner:
    case True{} True{} True{}: mp_index(ar, mp_src0(ar, mp_src0(ar, self)),
                                         List.append(&2, U32, mp_src_from(ar, mp_src0(ar, self), 1), mp_src_from(ar, self, 1)))
    case _ _ _                : Hop{ar, 0}

def mp_7(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_7.of(Bool.and(mp_nsrc_ge(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsINDEX{})),
          shp_each(tb, ar, mp_src_from(ar, self, 1)),
          shp_each(tb, ar, mp_src_from(ar, mp_src0(ar, self), 1)), tb, ar, self)

# (movement.py:27-28) INDEX on shaped INDEX
#   UPat(Ops.INDEX, src=(UPat(Ops.INDEX, src=(UPat.var("buf"), UPat.var("idx1_arg"))),), allow_any_len=True, name="idx2")
#   lambda buf,idx1_arg,idx2: buf.index(idx1_arg.index(*idx2.src[1:])) if len(idx1_arg.shape) == len(idx2.src[1:]) else None
# The inner INDEX's src is a two-tuple and so IS strict: `idx1` has exactly two
# srcs, which is why `buf` is `idx1.src[0]` and `idx1_arg` is `idx1.src[1]`. The
# Python's own TODO -- "this can be more generic" -- is the `UPat.var` on that
# second src, and it is already the generic form here.
#
# `buf.index(idx1_arg.index(*idx2.src[1:]))` is TWO `mp_index` calls, and the outer
# one's src list has the inner INDEX as its second element, so the inner node is
# built first and the outer node's arena is the INNER's -- which is why the arena
# is threaded rather than reused.
def mp_8.node(+ar: O.Arena, +self: U32) -> Hop:
  +inner = mp_index(ar, mp_src(ar, mp_src0(ar, self), 1), mp_src_from(ar, self, 1))
  mp_hit(O.UOp.new(hop_ar(inner), O.OpsINDEX{}, [mp_src(ar, mp_src0(ar, self), 0), hop_ix(inner)], O.ANone{}, O.TNone{}))

def mp_8.of(pat: Bool, ok: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok:
    case True{} True{}: mp_8.node(ar, self)
    case _ _           : Hop{ar, 0}

def mp_8(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_8.of(Bool.and(mp_nsrc_ge(ar, self, 1),
                   Bool.and(mp_is(ar, mp_src0(ar, self), O.OpsINDEX{}),
                            mp_nsrc_is(ar, mp_src0(ar, self), 2))),
          shp_n_is(tb, ar, mp_src(ar, mp_src0(ar, self), 1), mp_nat(mp_src_from(ar, self, 1))),
          tb, ar, self)

# ===========================================================================
# `early_reject` -- ops.py:1609 with the set from ops.py:1477. A NECESSARY
# CONDITION, not a veto: the rule FIRES when the op set IS a subset of `ler` and
# is SKIPPED when it is not. An empty set is a subset of everything, which is why
# rules 2 and 4 always get as far as their own tests. `O.pm_ler` is ops.bend's
# fold over EVERY src, which is what Python's `{u.op for u in uop.src}` is;
# reading only `src[0]` and `src[1]` would make rule 6's TWO-element set
# unreachable for a three-src INDEX, and `rej_pair` is the row for it.
# ===========================================================================
def mp_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(O.op_in(have, o), mp_early.go(have, t))

def mp_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  mp_early.go(O.pm_ler(ar, self), rej)

# ===========================================================================
# THE DISPATCH. `upat.py` emits a closure; Bend has no first-class functions, so
# the tag selects a top-level def. THIS is the mechanism, and it is why the table
# is `Data` rather than a list of closures -- and therefore why a second pass
# costs nothing, which is the one structural cost `engine-shape.bend` cannot
# avoid and this file does not have.
# ===========================================================================
def mp_dispatch.go(tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match tag:
    case 0: mp_0(tb, ar, self)
    case 1: mp_1(tb, ar, self)
    case 2: mp_2(tb, ar, self)
    case 3: mp_3(tb, ar, self)
    case 4: mp_4(tb, ar, self)
    case 5: mp_5(tb, ar, self)
    case 6: mp_6(tb, ar, self)
    case 7: mp_7(tb, ar, self)
    case 8: mp_8(tb, ar, self)
    case _: Hop{ar, 0}

def mp_dispatch(tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_dispatch.go(tag, tb, ar, self)

# THE TRY. Three things in Python's `PatternMatcher.rewrite` and three here: the
# op the rule claims (`pdict.get(uop.op, [])`), the subset test, and
# `ret is not uop`.
def mp_try.go(ok: Bool, tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match ok:
    case True{} : hop_self(mp_dispatch(tag, tb, ar, self), self)
    case False{}: Hop{ar, 0}

def mp_try(+tb: F.Table, +ar: O.Arena, +self: U32, +ler: List<&2, O.Op>, +e: O.PMEntry) -> Hop:
  mp_try.go(Bool.and(O.pm_claimed(O.PMEntry.ops(e), ar, self), mp_early(ar, self, O.PMEntry.rej(e))),
           O.PMEntry.tag(e), tb, ar, self)

# THE ONE RECURSIVE DEF. The fuel is the first parameter and every self-call
# passes a list tail, so the decrease check reads it left to right and stops at
# the first argument that shrinks. `h` is read twice -- once for its arena, which
# the next rule builds in, and once for the fold -- so it is `+`.
def mp_scan(rs: List<&2, O.PMEntry>, +tb: F.Table, +ler: List<&2, O.Op>, +self: U32, +h: Hop) -> Hop:
  match rs:
    case Nil{}: h
    case e <> t: mp_scan(t, tb, ler, self, hop_next(h, mp_try(tb, hop_ar(h), self, ler, e)))

# THE TABLE: `movement.py:5-29`, nine entries in Python's order. `tag` names the
# def, `ops` is the pdict key (the top-level pattern's op) and `rej` is
# ops.py:1477's set over the pattern's OWN SRCS.
def mop_table() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSHRINK{}],  [O.OpsSHRINK{}]},   # movement.py:7   x.f(SHRINK, s)
   O.PMEntry{1, [O.OpsRESHAPE{}], [O.OpsRESHAPE{}]},  # movement.py:10  x(RESHAPE(x2), _)
   O.PMEntry{2, [O.OpsRESHAPE{}], Nil{}},              # movement.py:12  x(x2, _)   first src a bare UPat()
   O.PMEntry{3, [O.OpsPERMUTE{}], [O.OpsPERMUTE{}]},  # movement.py:14  x(PERMUTE(x2))
   O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},              # movement.py:16  x          no srcs
   O.PMEntry{5, [O.OpsSTACK{}],   [O.OpsINDEX{}]},    # movement.py:18  x(INDEX(src, CONST))
   O.PMEntry{6, [O.OpsINDEX{}],   [O.OpsSTACK{}, O.OpsCONST{}]},  # movement.py:21 cvar carries CONST
   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsINDEX{}]},    # movement.py:24  x(INDEX(idx1))
   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsINDEX{}]}]    # movement.py:27  x(INDEX(buf, idx1_arg))

# `mop_cleanup.rewrite` -- ops.py:1611. TWO lines, and both are in the header:
# the `tb` is the fold of the arena as it stands on ENTRY, which is the right
# answer for every node a rule can ask about (point 4), and `ler` is computed
# ONCE and threaded (point 3). The answer is a `Hop`: read `O.UOp.is_none` on its
# index for Python's `None`, and `hop_ar` for the arena to hand to the next node.
def mop_cleanup(+fx: F.Folded, +self: U32) -> Hop:
  mp_scan(mop_table(), F.Folded.t(fx), O.pm_ler(F.Folded.ar(fx), self), self, Hop{F.Folded.ar(fx), 0})

# ===========================================================================
# THE GATE.
#
# Every claim below is DERIVED FROM PYTHON, not from this file. The oracle is
# `.agents/slop/notes/mop-truth.py`, which builds the same graphs in this repo's
# Python and prints `mop_cleanup.rewrite(...)` for each. A row that merely
# restates this file would be worthless, so each one says what tinygrad answers.
#
# THE FIXTURE, and the node indices it fixes. They are not load-bearing -- no row
# compares an index across lanes -- but naming them makes the result-index rows
# readable, since "the rewrite of P2 IS P3" is a Python fact.
#
#   0 bottom  1 C0   2 C1   3 C2   4 C4    5 SPECIAL   6 b4(size 4)
#   7 b0(none)  8 B24(img 2x4)   9 bimg(img 2x7)   10 o1(size 2)  11 o2(size 7)
#  12 S1=SHRINK(b4,C2,C2)      13 S2=SHRINK(S1,C1,C1)      rank 1
#  14 st2=STACK(C0,C1)  15 st11=STACK(C1,C1)  16 S3  17 S4 rank 2
#  18 st4=STACK(C4)  19 R1=RESHAPE(b4,C4)  20 R2=RESHAPE(R1,st4)  21 R3=RESHAPE(b4,st4)
#  22 P1=PERMUTE(B24,(1,0))  23 P2=PERMUTE(P1,(1,0))  24 P3=PERMUTE(B24,(0,1))
#  25 SS=STACK(C0,C1,C2)  26 E0=INDEX(bimg,C0)  27 E1=INDEX(bimg,C1)  28 STK
#  29 IX2=INDEX(SS,C1)  30 IX3=INDEX(SS,C1,C0)  31 IX5=INDEX(SS,C0,C0,C1)
#  32 J1=INDEX(b4,C0)  33 J2=INDEX(J1,C1)  34 J3=INDEX(IX2)
#  35 K1=INDEX(B24,o1)  36 K2=INDEX(K1,o2)  37 K3=INDEX(INDEX(B24,STK),o2)
#  38 ADD(C0,C1)
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

def b2u(b: Bool) -> U32:
  match b:
    case True{} : 1
    case False{}: 0

# `ParamArg(0, int32, size=..., image=...)` -- `ops.bend`'s record literal, and the
# only thing that makes a BUFFER's shape `(size,)` or `(h, w, 4)`.
def psize(n: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), n, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

def pimage(h: U32, w: U32) -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{},
             Some{O.Img{h, w}}, None{}, False{}, None{}}

# THE FIXTURE. Built in the order above, one `+` per node, because Bend has no
# mutable store and each intermediate arena is a value.
def g() -> G:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  +c4 = O.UOp.const(O.Found.ar(c2), O.CInt{H.i64_of_i32(4)})
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "0")
  +b4 = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{psize(Some{4})}, O.TNone{})
  +b0 = O.UOp.new(O.Found.ar(b4), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{psize(None{})}, O.TNone{})
  +b24 = O.UOp.new(O.Found.ar(b0), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pimage(2, 4)}, O.TNone{})
  +big = O.UOp.new(O.Found.ar(b24), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pimage(2, 7)}, O.TNone{})
  +o1 = O.UOp.new(O.Found.ar(big), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{psize(Some{2})}, O.TNone{})
  +o2 = O.UOp.new(O.Found.ar(o1), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{psize(Some{7})}, O.TNone{})
  +s1 = O.UOp.new(O.Found.ar(o2), O.OpsSHRINK{}, [O.Found.i(b4), O.Found.i(c2), O.Found.i(c2)], O.ANone{}, O.TNone{})
  +s2 = O.UOp.new(O.Found.ar(s1), O.OpsSHRINK{}, [O.Found.i(s1), O.Found.i(c1), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +t2 = O.UOp.new(O.Found.ar(s2), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +t11 = O.UOp.new(O.Found.ar(t2), O.OpsSTACK{}, [O.Found.i(c1), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +s3 = O.UOp.new(O.Found.ar(t11), O.OpsSHRINK{}, [O.Found.i(b24), O.Found.i(t2), O.Found.i(t11)], O.ANone{}, O.TNone{})
  +s4 = O.UOp.new(O.Found.ar(s3), O.OpsSHRINK{}, [O.Found.i(s3), O.Found.i(t11), O.Found.i(t11)], O.ANone{}, O.TNone{})
  +t4 = O.UOp.new(O.Found.ar(s4), O.OpsSTACK{}, [O.Found.i(c4)], O.ANone{}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(t4), O.OpsRESHAPE{}, [O.Found.i(b4), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +r2 = O.UOp.new(O.Found.ar(r1), O.OpsRESHAPE{}, [O.Found.i(r1), O.Found.i(t4)], O.ANone{}, O.TNone{})
  +r3 = O.UOp.new(O.Found.ar(r2), O.OpsRESHAPE{}, [O.Found.i(b4), O.Found.i(t4)], O.ANone{}, O.TNone{})
  +p1 = O.UOp.new(O.Found.ar(r3), O.OpsPERMUTE{}, [O.Found.i(b24)], O.ATuple{[1, 0]}, O.TNone{})
  +p2 = O.UOp.new(O.Found.ar(p1), O.OpsPERMUTE{}, [O.Found.i(p1)], O.ATuple{[1, 0]}, O.TNone{})
  +p3 = O.UOp.new(O.Found.ar(p2), O.OpsPERMUTE{}, [O.Found.i(b24)], O.ATuple{[0, 1]}, O.TNone{})
  +ss = O.UOp.new(O.Found.ar(p3), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1), O.Found.i(c2)], O.ANone{}, O.TNone{})
  +e0 = O.UOp.new(O.Found.ar(ss), O.OpsINDEX{}, [O.Found.i(big), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +e1 = O.UOp.new(O.Found.ar(e0), O.OpsINDEX{}, [O.Found.i(big), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +stk = O.UOp.new(O.Found.ar(e1), O.OpsSTACK{}, [O.Found.i(e0), O.Found.i(e1)], O.ANone{}, O.TNone{})
  +ix2 = O.UOp.new(O.Found.ar(stk), O.OpsINDEX{}, [O.Found.i(ss), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +ix3 = O.UOp.new(O.Found.ar(ix2), O.OpsINDEX{}, [O.Found.i(ss), O.Found.i(c1), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +ix5 = O.UOp.new(O.Found.ar(ix3), O.OpsINDEX{}, [O.Found.i(ss), O.Found.i(c0), O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +j1 = O.UOp.new(O.Found.ar(ix5), O.OpsINDEX{}, [O.Found.i(b4), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +j2 = O.UOp.new(O.Found.ar(j1), O.OpsINDEX{}, [O.Found.i(j1), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +j3 = O.UOp.new(O.Found.ar(j2), O.OpsINDEX{}, [O.Found.i(ix2)], O.ANone{}, O.TNone{})
  +k1 = O.UOp.new(O.Found.ar(j3), O.OpsINDEX{}, [O.Found.i(b24), O.Found.i(o1)], O.ANone{}, O.TNone{})
  +k2 = O.UOp.new(O.Found.ar(k1), O.OpsINDEX{}, [O.Found.i(k1), O.Found.i(o2)], O.ANone{}, O.TNone{})
  +ki = O.UOp.new(O.Found.ar(k2), O.OpsINDEX{}, [O.Found.i(b24), O.Found.i(stk)], O.ANone{}, O.TNone{})
  +k3 = O.UOp.new(O.Found.ar(ki), O.OpsINDEX{}, [O.Found.i(ki), O.Found.i(o2)], O.ANone{}, O.TNone{})
  +add = O.UOp.alu(O.Found.ar(k3), O.OpsADD{}, [O.Found.i(c0), O.Found.i(c1)])
  G{F.folded(O.Found.ar(add)),
    [O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c4), O.Found.i(sp),
     O.Found.i(b4), O.Found.i(b0), O.Found.i(b24), O.Found.i(big), O.Found.i(o1), O.Found.i(o2),
     O.Found.i(s1), O.Found.i(s2), O.Found.i(t2), O.Found.i(t11), O.Found.i(s3), O.Found.i(s4),
     O.Found.i(t4), O.Found.i(r1), O.Found.i(r2), O.Found.i(r3), O.Found.i(p1), O.Found.i(p2), O.Found.i(p3),
     O.Found.i(ss), O.Found.i(e0), O.Found.i(e1), O.Found.i(stk), O.Found.i(ix2), O.Found.i(ix3), O.Found.i(ix5),
     O.Found.i(j1), O.Found.i(j2), O.Found.i(j3), O.Found.i(k1), O.Found.i(k2), O.Found.i(k3), O.Found.i(add)]}

def rw(+gx: G, n: Nat) -> Hop:
  mop_cleanup(G.fx(gx), G.at(gx, n))

# The merged margin of `self` over its own src[0] -- `movement.py:8`'s generator
# for both halves of rule 0. GATE-ONLY INSTRUMENT: it reads the ported arithmetic
# and prints it, and the rule itself does not use it.
def g_fx() -> F.Folded:
  G.fx(g())

def g_ar() -> O.Arena:
  F.Folded.ar(g_fx())

def g_node(+n: Nat) -> U32:
  G.at(g(), n)

def g_marg(+n: Nat) -> Maybe<&1, List<&2, Marg>>:
  marg_add(g_ar(), g_node(n), mp_src0(g_ar(), g_node(n)))

def marg_n.go(m: Maybe<&1, List<&2, Marg>>) -> Nat:
  match m:
    case Some{ms}: List.length(&2, Marg, ms)
    case None{}   : 0n

def marg_un.go(m: Maybe<&1, List<&2, Marg>>) -> List<&2, Marg>:
  match m:
    case Some{ms}: ms
    case None{}   : Nil{}

# `enc` packs a margin as `(((o0*10+n0)*100 + o1*10+n1) ...)`, so the Python
# `((3,1),)` is 31 and `((1,1),(2,1))` is 1121. Both are printed by mop-truth.py.
def marg_pair(+o: H.I64, n: H.I64) -> U32:
  U32.add(U32.mul(i64_u32(o), 10), i64_u32(n))

# ONE READ of the pair: a `Marg` taken out of a `List` is a binder, and a binder
# read twice is refused exactly like a parameter, so both field reads are hoisted
# into a def that takes the `Marg` whole.
def marg_pair.of(+m: Marg) -> U32:
  marg_pair(Marg.o(m), Marg.n(m))

def marg_enc.go(ms: List<&2, Marg>, acc: U32) -> U32:
  match ms:
    case Nil{}: acc
    case m <> t: marg_enc.go(t, U32.add(U32.mul(acc, 100), marg_pair.of(m)))

def t_mop_len() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, mop_table()))

# SHRINK over SHRINK at rank 1. Python answers
# `SHRINK(b4, CONST(3), CONST(1))`: three srcs, offsets 2+1 and size 1.
def t_shrink1_ns() -> U32:
  +h = rw(g(), 13n)
  mp_nsrc(hop_ar(h), hop_ix(h))

def shr_o(+ar: O.Arena, r: U32) -> H.I64:
  mp_const_val(ar, mp_src(ar, r, 1))

def shr_n(+ar: O.Arena, r: U32) -> H.I64:
  mp_const_val(ar, mp_src(ar, r, 2))

def t_shrink1_marg() -> U32:
  +h = rw(g(), 13n)
  marg_pair(shr_o(hop_ar(h), hop_ix(h)), shr_n(hop_ar(h), hop_ix(h)))

def t_shrink2() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 17n))))

# The rank-2 merged margin, `((1,1),(2,1))`. Python's rule FIRES here and
# `simplify()` supplies the STACKs; this port's does not, and that is the row.
def t_shrink2_marg() -> U32:
  marg_enc.go(marg_un.go(g_marg(17n)), 0)

def t_marg_n1() -> U32:
  U32.from_nat(marg_n.go(g_marg(13n)))

def t_marg_n2() -> U32:
  U32.from_nat(marg_n.go(g_marg(17n)))

# FIRST WINS, and the fixture is built so `mp_1` and `mp_2` BOTH claim R2 and
# DISAGREE. Python: `mp_1` gives `RESHAPE(b4, st4)` and `mp_2` gives
# `RESHAPE(b4, CONST(4))`, and `rewrite` returns the first. So the result's src[1]
# is a STACK, and the row says so.
def t_reshape_pick() -> U32:
  +h = rw(g(), 20n)
  b2u(mp_is(hop_ar(h), mp_src(hop_ar(h), hop_ix(h), 1), O.OpsSTACK{}))

# `mp_2` alone, on a RESHAPE whose src[0] is a BUFFER -- the only shape it can be
# evaluated for while fold.bend defers a movement op's shape. Python: b4.
def t_reshape_noop() -> U32:
  hop_ix(rw(g(), 21n))

def t_permute_merge() -> U32:
  hop_ix(rw(g(), 23n))

def t_permute_noop() -> U32:
  hop_ix(rw(g(), 24n))

def t_stack_idx() -> U32:
  hop_ix(rw(g(), 28n))

def t_const_idx2() -> U32:
  hop_ix(rw(g(), 29n))

def t_const_idx3() -> U32:
  +h = rw(g(), 30n)
  mp_nsrc(hop_ar(h), hop_ix(h))

def t_const_idx5() -> U32:
  +h = rw(g(), 31n)
  mp_nsrc(hop_ar(h), hop_ix(h))

def t_idx_idx() -> U32:
  +h = rw(g(), 33n)
  mp_nsrc(hop_ar(h), hop_ix(h))

# `UOp.index`'s STACK special case: rule 7's answer is a node it did NOT build.
def t_idx_pick() -> U32:
  hop_ix(rw(g(), 34n))

def t_idx_shaped() -> U32:
  +h = rw(g(), 36n)
  mp_nsrc(hop_ar(h), hop_ix(h))

def t_idx_shaped_bad() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 37n))))

def t_unclaimed() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 38n))))

def t_rej_pair() -> U32:
  hop_ix(rw(g(), 29n))

# A rule that interns a node GROWS the arena, and a rule that does not does not.
# Both are the same two-line difference, so the two rows are read as one.
def t_grow_new() -> U32:
  +gx = g()
  +h = mop_cleanup(G.fx(gx), G.at(gx, 33n))
  U32.sub(O.Arena.next(hop_ar(h)), O.Arena.next(F.Folded.ar(G.fx(gx))))

def t_grow_same() -> U32:
  +gx = g()
  +h = mop_cleanup(G.fx(gx), G.at(gx, 29n))
  U32.sub(O.Arena.next(hop_ar(h)), O.Arena.next(F.Folded.ar(G.fx(gx))))

# THE SAME TABLE VALUE, TWICE. This is the row for the header's claim that a
# `Data` table removes the "a second pass rebuilds it" cost of a closure table.
def t_twice() -> U32:
  +gx = g()
  +ts = mop_table()
  +tb = F.Folded.t(G.fx(gx))
  +ar = F.Folded.ar(G.fx(gx))
  +ler = O.pm_ler(ar, G.at(gx, 23n))
  +a = mp_scan(ts, tb, ler, G.at(gx, 23n), Hop{ar, 0})
  +b = mp_scan(ts, tb, ler, G.at(gx, 23n), Hop{ar, 0})
  b2u(U32.is_eq(hop_ix(a), hop_ix(b)))

# `ret is not uop`, ops.py:1611, which no rule in this file can trigger.
def t_ret_self() -> U32:
  b2u(O.UOp.is_none(hop_ix(hop_self(Hop{O.Arena.empty(), 0}, 0))))

def t_ret_new() -> U32:
  b2u(O.UOp.is_none(hop_ix(hop_self(Hop{O.Arena.empty(), 3}, 2))))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def dbg_op.go(op: O.Op) -> U32:
  match op:
    case O.OpsSHRINK{}: 1
    case O.OpsRESHAPE{}: 2
    case O.OpsPERMUTE{}: 3
    case O.OpsSTACK{}: 4
    case O.OpsINDEX{}: 5
    case O.OpsCONST{}: 6
    case O.OpsBUFFER{}: 7
    case O.OpsSPECIAL{}: 8
    case O.OpsADD{}: 9
    case _: 0

def dbg_op(i: U32) -> U32:
  dbg_op.go(O.Arena.op(g_ar(), i))

def dbg_shape.go(m: Maybe<&2, List<&2, O.Sint>>) -> U32:
  match m:
    case Some{Nil{}}: 1
    case Some{_ <> _}: 2
    case None{}: 0

def dbg_shape(i: U32) -> U32:
  dbg_shape.go(shp_of(mp_shape(F.Folded.t(g_fx()), g_ar(), i)))

def dbg_as.go(m: Maybe<&1, List<&2, H.I64>>) -> U32:
  match m:
    case Some{Nil{}}: 0
    case Some{_ <> _}: 1
    case None{}: 9

def dbg_as(i: U32) -> U32:
  dbg_as.go(as_shape(g_ar(), i))

def t_dbg() -> U32:
  dbg_op(G.at(g(), 13n))

def t_dbg2() -> U32:
  dbg_shape(G.at(g(), 13n))

def t_dbg3() -> U32:
  dbg_as(G.at(g(), 4n))

def t_dbg4() -> U32:
  dbg_as(G.at(g(), 2n))

def t_dbg5() -> U32:
  O.Arena.next(g_ar())

def t_dbg6() -> U32:
  dbg_op(G.at(g(), 6n))

def t_dbg7() -> U32:
  dbg_op(G.at(g(), 7n))

def t_dbg8() -> U32:
  dbg_op(G.at(g(), 12n))

def dbg_all.go(n: Nat, i: Nat, acc: U32) -> U32:
  match n:
    case 0n: acc
    case m : dbg_all.go(nat_un(m), Nat.add(i, 1n), U32.add(U32.mul(acc, 10), dbg_op(U32.from_nat(i))))

def nat_un(n: Nat) -> Nat:
  Nat.sub(n, 1n)

def t_dbgall() -> U32:
  dbg_all.go(40n, 0n, 0)

def dbg_consts.go(c: O.Const) -> U32:
  match c:
    case O.CInt{i}: 7
    case _: 8

def dbg_ck(i: U32) -> U32:
  match O.Arena.arg(g_ar(), i):
    case O.APy{c}: dbg_consts(c)
    case _: 0

def t_dbgck() -> U32:
  dbg_ck.go2(Nil{}, 0)

def dbg_ck.go2(ns: List<&2, U32>, acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case i <> t: dbg_ck.go2(t, U32.add(U32.mul(acc, 10), dbg_ck(i)))

def t_dbgck2() -> U32:
  dbg_ck.go2([1, 2, 3, 4], 0)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("dbgall", t_dbgall())
    row("dbgck", t_dbgck2())
