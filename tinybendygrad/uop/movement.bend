# movement.bend -- tinygrad/uop/movement.py. `mop_cleanup`: the pattern matchers
# that strictly CLEAN UP movement ops, in the compiled form `upat.py` emits.
#
# # TODO: pm_mops from rangeify belongs here. this is all pattern matchers that
# strictly clean up movement ops
#
# A rule here answers a NEW UOP or `None`, not a verdict, so a rewrite carries the
# arena and WHICH node it produced: `Hop{ar, at}`, with `at == 0` being Python's
# `None` (ops.bend reserves arena index 0). Two consequences the gate pins: a rule
# that does not fire interns nothing, and a rule that returns an existing node grows
# the arena where one that interns does not. `ler` is threaded once per pass because
# the node under examination is fixed for the whole pass -- a rule returns a fresh
# node or a strict ancestor, and neither changes `self`'s srcs.
#
# `early_reject` IS A NECESSARY CONDITION, not a veto: a rule FIRES when the op set
# IS a subset of `ler` (ops.py:1609). Rule 6's `{STACK, CONST}`, from `UPat.cvar`,
# is the only non-empty set and its own src-op tests already imply it, so no verdict
# here is decided by the subset test. No pattern in movement.py binds a name twice,
# so no rule emits the identity check `upat.py:100-105` builds for one.
#
# DEFERRED: `mp_0` at rank >= 2 (`UOp.sink(...).simplify()` would reach
# `graph_rewrite(self, symbolic)` -- the engine calling itself), `mp_2`'s `x.shape`
# (fold.bend does not answer a movement op's shape), a float CONST where an int is
# wanted, and `Arena.src`'s 0 for Python's `IndexError`. `ret is not uop` is in
# `hop_self` and is unreachable from these nine rules.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O
import ./fold.bend as F

# THE RESULT. A rule's answer: the arena as it stands after that rule, and WHICH
# node it produced. `at == 0` is Python's `None`.
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
# first-wins: keying on the ACCUMULATOR is what makes it first-wins.
def hop_first.of(b: Bool, +hold: U32, r: U32) -> U32:
  match b:
    case True{}: r
    case False{}: hold

def hop_first(+hold: U32, r: U32) -> U32:
  hop_first.of(O.UOp.is_none(hold), hold, r)

# THE FOLD, and the arena threading. A later rule builds in the arena an earlier rule
# produced, so the next arm reads `hop_ar(h)` and not the arena it was handed.
def hop_next(h: Hop, r: Hop) -> Hop:
  match h r:
    case Hop{ha, hn} Hop{ra, rn}: Hop{ra, hop_first(hn, rn)}

# `ret is not uop` -- ops.py:1611. The arena KEEPS whatever the rule built and only the
# ANSWER is dropped, which is Python's `return None` after a construction. So `drop` is
# "the answer IS self, OR the answer IS none", and `True` must answer NOTHING.
#
# WHICH SIDE PYTHON IS ON, since this def was INVERTED and its own comment was right:
# ops.py:1610 reads `if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret`,
# so the KEEP condition is `ret is not None AND ret is not uop` and the DROP condition is
# its negation. `drop` here is exactly that negation, so `False` keeps and `True` drops.
# The pre-fix arms had them the other way round -- keeping `self` and dropping a
# genuinely new node -- which is the inverse of ops.py:1610 AND of the comment above it.
# `t_ret_new` is the row that pins it, and it read 1 while the bug was in place.
def hop_self.of(drop: Bool, +r: Hop) -> Hop:
  match drop:
    case True{}: Hop{hop_ar(r), 0}
    case False{}: r

def hop_self(+r: Hop, self: U32) -> Hop:
  hop_self.of(Bool.or(U32.is_eq(hop_ix(r), self), O.UOp.is_none(hop_ix(r))), r)

# THE READERS. `spec.bend`'s `sp_*`, renamed `mp_*` because these read the CURRENT
# arena rather than a `Folded`. `O.Arena`'s readers return BARE values, not `Maybe`.
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

# `len(x.src) >= n` -- `allow_any_len=True`'s "at least n srcs". `U32.is_ge`, NOT
# `U32.is_lt(n, nsrc)`: the name is the whole contract, and one arity is the entire
# content of a rule's arity test. A `len(x.src) == n` test is `mp_nsrc_is` -- this is
# `>=` and nothing else, so `mp_5.one`'s STRICT two-tuple is `mp_nsrc_is`, not this.
def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:
  U32.is_ge(mp_nsrc(ar, i), n)

def mp_nat(ss: List<&2, U32>) -> Nat:
  List.length(&2, U32, ss)

# `x.shape` -- ops.py:456, which is `_shape` unless `_shape` is None, in which case it
# is a fresh UNIQUE UOp. So the fold's shape is a DOUBLE `Maybe`: the outer is "the table
# has no entry", the inner is `_shape` being None. The rules want the inner.
def mp_shape(tb: F.Table, ar: O.Arena, i: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  F.fold.shape(ar, tb, i)

def shp_of.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case None{}: None{}

def shp_of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  shp_of.go(m)

# `x.shape == y.shape` -- `movement.py:12`'s second conjunct and `movement.py:19`'s
# first. A shape element that is a uop rather than a literal compares by index, which is
# what Python's `==` on `sint`s does.
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

# `len(idx1_arg.shape) == len(idx2.src[1:])` -- `movement.py:28`. Python's `len` of
# `shape` RAISES when `_shape` is None, so `None` is the answer that does not fire.
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
def arg_tuple.go(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ATuple{ys}: Some{ys}
    case _: None{}

def arg_tuple(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  arg_tuple.go(a)

# The value of a CONST as an `I64` -- `.val` reads `self.arg` (tinygrad/uop/ops.py:261). `CBool` is
# Python's `True`/`False` and `True == 1`, so a bool CONST answers 1/0; a `CFloat`
# answers nothing (a float CONST where an int is wanted, see the header).
def const_i64.go(a: O.Arg) -> Maybe<&2, H.I64>:
  match a:
    case O.APy{O.CInt{i}}   : Some{i}
    case O.APy{O.CBool{True{}}}: Some{H.i64_of_i32(1)}
    case O.APy{O.CBool{False{}}}: Some{H.i64_of_i32(0)}
    case _: None{}

def const_i64(a: O.Arg) -> Maybe<&2, H.I64>:
  const_i64.go(a)

# The same value as a `U32`, for the two places it is a src INDEX. Python's `a.src[-1]`
# would read from the END and a float index is a TypeError, so the only value this port
# can use is a non-negative int and everything else answers 0.
def i64_u32.of(b: Bool, lo: U32) -> U32:
  match b:
    case True{}: lo
    case False{}: 0

def i64_u32(+x: H.I64) -> U32:
  i64_u32.of(U32.is_zero(H.hi32(x)), H.lo32(x))

# `x.arg[n]` -- the permutation composition of `movement.py:14`.
def list_at(xs: List<&2, U32>, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(n)), 0)

# `x.src[1].val == k`, the `list(range(len(stk.src))) == [x.src[1].val ...]` half. A
# CONST's VALUE against a position, never a node against a position: the elements of
# `x.arg` are Python ints (see `mp_ident.at`), and here the CONST is a real arena node.
def const_is(m: Maybe<&2, H.I64>, n: Nat) -> Bool:
  match m:
    case Some{v}: Cmp.is_eq(H.i64_cmp(v, H.i64_of_i32(U32.from_nat(n))))
    case None{}: False{}

# `UOp.index` -- ops.py:581. Three of these nine rules call it and it belongs in ops.bend
# the next time that file is edited (`# TODO(p3) ops.py:581  def index`).
#
#     def index(self, *srcs, **kwargs):
#       new_srcs = [UOp.const(x) if isinstance(x, int) else x for x in srcs if x is not None]
#       if len(new_srcs) == 1 and new_srcs[0].op is Ops.CONST and self.op is Ops.STACK: return self.src[new_srcs[0].val]
#       return UOp(Ops.INDEX, src=(self,)+tuple(new_srcs), **kwargs)
#
# THE SPECIAL CASE IS WHY A REWRITE CAN RETURN A NODE IT DID NOT BUILD, and `idx_pick` is
# the row for it: `INDEX(INDEX(STACK, C1))` has no offsets of its own, so the outer
# `index()` hands back `STACK.src[C1.val]`. Every `extra` is already a UOp index and never
# a Python int, so the `UOp.const(x)` half and the `is not None` filter are vacuous here.
# `(self,)+tuple(new_srcs)` is a HEAD, not a tail, so `mp_index.new` prepends.
#
# `new_srcs[0].val` is the VALUE, and Python's answer is that value used as an INDEX into
# the STACK's srcs -- so the resolution is `Arena.src` here, the IndexError included
# (`Arena.src` answers 0). Returning the value itself answers 1 where Python answers
# `STACK.src[1]`, which is a CONST and a different node.
def mp_index.pick(sel: Maybe<&1, U32>, ar: O.Arena, self: U32) -> U32:
  match sel:
    case Some{v}: mp_src(ar, self, v)
    case None{}  : 0

def mp_index.new(+ar: O.Arena, self: U32, extra: List<&2, U32>) -> Hop:
  mp_hit(O.UOp.new(ar, O.OpsINDEX{}, List.append(&2, U32, [self], extra), O.ANone{}, O.TNone{}))

def mp_index.of(sel: Maybe<&1, U32>, one: Bool, stack: Bool, +ar: O.Arena, self: U32, extra: List<&2, U32>) -> Hop:
  match one stack:
    case True{} True{}: Hop{ar, mp_index.pick(sel, ar, self)}
    case _ _: mp_index.new(ar, self, extra)

def mp_const_val.of(m: Maybe<&2, H.I64>) -> H.I64:
  match m:
    case Some{v}: v
    case None{}: H.i64_of_i32(0)

def mp_const_val(ar: O.Arena, i: U32) -> H.I64:
  mp_const_val.of(const_i64(mp_arg(ar, i)))

# `new_srcs[0].val` -- the CONST's VALUE, not a node. `mp_index.pick` is what uses it as
# an index; a float CONST where an int is wanted answers nothing (the header's DEFERRED).
def mp_stack_val(ar: O.Arena, self: U32, extra: List<&2, U32>) -> Maybe<&1, U32>:
  match extra:
    case e <> Nil{}: Some{i64_u32(mp_const_val(ar, e))}
    case _: None{}


def mp_index(+ar: O.Arena, +self: U32, +extra: List<&2, U32>) -> Hop:
  mp_index.of(mp_stack_val(ar, self, extra), Nat.is_eq(mp_nat(extra), 1n), mp_is(ar, self, O.OpsSTACK{}), ar, self, extra)

# `x.src[1].val`, which is an `I64` and a `Maybe` because `.val` is only for a CONST or a
# CAST of one (ops.py:259-262).
def mp_const(ar: O.Arena, i: U32) -> Maybe<&2, H.I64>:
  const_i64(mp_arg(ar, i))

# `UOp.replace` -- ops.py:252. `new_args = (kwargs.pop("op", self.op), kwargs.pop("src",
# self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))`, so `arg` is a
# PARAMETER and not something read off `self`: rule 1 replaces only `src` and passes
# `self`'s own arg, rule 3 replaces only `arg` and keeps `x2`'s src and tag. Reading the
# arg off `self` answers `x2` for rule 3, which is the node the rule was folding away.
# `if (self.op, self.src, self.arg, self.tag) == new_args: return self` needs no code
# here: the arena hash-conses and hands back the same index, and `hop_self` turns "the
# answer is the node itself" into no answer.
def mp_replace(op: O.Op, arg: O.Arg, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Hop:
  mp_hit(O.UOp.new(ar, op, src, arg, mp_tag(ar, self)))

# `as_shape` -- ops.py:807 -- and `marg` -- ops.py:813, SHRINK's arm.
#
#     def as_shape(self):
#       if self.op is Ops.CONST: return (self.val,)
#       if self.op is not Ops.STACK: return (ssimplify(self),)
#       return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)
#
#     case Ops.PAD | Ops.SHRINK: return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
#
# TWO ARMS ARE PORTED and the middle one is not, because it is `ssimplify`, which is
# `graph_rewrite(self, symbolic)`. So `as_shape` here answers for a CONST and for a STACK
# of CONSTs -- exactly the shapes `_mop` builds -- and `None` otherwise. The elements are
# `H.I64` and not `O.Sint`, because an `O.Sint` element that is a uop would make `o+p` a
# symbolic sum while the merged margin is `o+p` with a literal `p`.
def as_shape.one.of(v: Maybe<&2, H.I64>) -> Maybe<&1, List<&2, H.I64>>:
  match v:
    case Some{c}: Some{[c]}
    case None{}  : None{}

def as_shape.one(+ar: O.Arena, +i: U32) -> Maybe<&1, List<&2, H.I64>>:
  as_shape.one.of(mp_const(ar, i))

# `tuple(s.val if s.op is CONST else ssimplify(s) for s in self.src)`, split in two
# because a `Maybe` cannot be an accumulator. `mp_const_val`'s 0 default is unreachable:
# `shape_to_shape_arg` (ops.py:104) raises unless every element is an int.
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

# `Marg` is Python's `(o, n)` pair, and a `Data` RECORD rather than a tuple because a
# pair is a `Type` and Bend's affine handler, and a `Type` cannot be a list element.
type Marg is Data:
  Marg{o: H.I64, n: H.I64}

# Bend has no `x.field`, so a record costs two accessors. Everywhere a `Marg` is already
# destructured by a `match` these are not used.
def Marg.o(x: Marg) -> H.I64:
  match x:
    case Marg{o, n}: o

def Marg.n(x: Marg) -> H.I64:
  match x:
    case Marg{o, n}: n

# `(o + p, n)` -- the whole of `movement.py:8`'s generator. `n` is `s.marg`'s, so the SIZE
# of the inner shrink survives and the offset is the sum.
#
# `List.append(&2, A, r, [x])` puts `x` at the END of `r` (MEASURED, and the reproducer is
# `.agents/slop/notes/probe-append.bend`), so the accumulator must grow on the way DOWN, as
# `marg_zip.go` and `as_shape.vals.go` do. Appending on the way UP -- `step(go(..), ..)` --
# REVERSES the margin, and a reversed margin of two entries still has length two, so
# `marg_n1`/`marg_n2` and `shrink2_marg`'s length all read correct.
def marg.step(x: Marg, y: Marg, acc: List<&2, Marg>) -> List<&2, Marg>:
  match x y:
    case Marg{xo, xn} Marg{yo, yn}: List.append(&2, Marg, acc, [Marg{H.i64_add(xo, yo), yn}])

# `zip(x.marg, s.marg)`, which TRUNCATES to the shorter, so an empty side gives an empty
# margin and `mp_0` then lands on `_mop`'s `len(arg) == 0` early return.
def marg.go(ys: List<&2, Marg>, xs: List<&2, Marg>, acc: List<&2, Marg>) -> List<&2, Marg>:
  match ys xs:
    case Nil{} _        : acc
    case _ <> _ Nil{}   : acc
    case y <> yt x <> xt: marg.go(yt, xt, marg.step(x, y, acc))

def marg(ys: List<&2, Marg>, xs: List<&2, Marg>) -> List<&2, Marg>:
  marg.go(ys, xs, Nil{})

# `zip(self.src[1].as_shape, self.src[2].as_shape)` -- SHRINK's arm of `marg`.
def marg_zip.go(ys: List<&2, H.I64>, xs: List<&2, H.I64>, acc: List<&2, Marg>) -> List<&2, Marg>:
  match ys xs:
    case Nil{} _        : acc
    case _ <> _ Nil{}   : acc
    case y <> yt x <> xt: marg_zip.go(yt, xt, List.append(&2, Marg, acc, [Marg{x, y}]))

def marg_zip(ys: List<&2, H.I64>, xs: List<&2, H.I64>) -> List<&2, Marg>:
  marg_zip.go(ys, xs, Nil{})

# `tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg))`, with the four `None`s folded
# into one: a margin is a margin only if BOTH `as_shape`s of BOTH shrinks are. `self` is
# the OUTER shrink and `mp_src0(ar, self)` the INNER.
#
# THE ARGUMENT ORDER IS THE WHOLE OF `(o + p, n)`, and it is a naming trap:
# `UPat.f` (ops.py:1504) is `UPat(op, src=(self,))`, so in
# `UPat(SHRINK, name="x").f(SHRINK, name="s")` the OUTER node is `s` and the INNER is `x`
# -- the reverse of what the letters suggest -- and `(o,_),(p,n) in zip(x.marg, s.marg)`
# reads `n` off `s.marg`, the OUTER's. `marg` takes `n` from its FIRST list, so the
# outer's margin goes first. Only the order is load-bearing: `o` is SUMMED, so the two
# `marg_zip` arguments commute and swapping them changes `n` alone. `M8` in the mutation
# table is that swap, and it moves `shrink1_marg` from 31 to 32 -- CPython's `SHRINK(b4,
# CONST(3), CONST(1))` has the OUTER's `n = 1`, and the swap would give the inner's `2`.
def marg_add.of(ox: Maybe<&1, List<&2, H.I64>>, nx: Maybe<&1, List<&2, H.I64>>,
                os: Maybe<&1, List<&2, H.I64>>, ns: Maybe<&1, List<&2, H.I64>>) -> Maybe<&1, List<&2, Marg>>:
  match ox nx os ns:
    case Some{a} Some{b} Some{c} Some{d}: Some{marg(marg_zip(b, a), marg_zip(d, c))}
    case _ _ _ _                         : None{}

def marg_add(+ar: O.Arena, +x: U32, +s: U32) -> Maybe<&1, List<&2, Marg>>:
  marg_add.of(as_shape(ar, mp_src(ar, x, 1)), as_shape(ar, mp_src(ar, x, 2)),
              as_shape(ar, mp_src(ar, s, 1)), as_shape(ar, mp_src(ar, s, 2)))

# THE NINE RULES, in movement.py's order. Each `match` is on BOOLS: the first is the
# pattern's own tests, the rest are the LAMBDA's condition -- `upat.py`'s split exactly --
# and every construction sits in a TAKEN arm, so a rule that does not fire interns nothing.

# merge adjacent SHRINKs (movement.py:7-8)
#   UPat(Ops.SHRINK, name="x").f(Ops.SHRINK, allow_any_len=True, name="s")
#   lambda s,x: x.src[0]._mop(Ops.SHRINK, tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg)))
# `_mop`'s SHRINK node is `SHRINK(x.src[0], <o>, <n>)`, and `shape_to_shape_arg` of a ONE
# element shape is a bare CONST (ops.py:106).
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
# ONE axis per side, because `shape_to_shape_arg` of a ONE element shape is a bare
# CONST (ops.py:106). A merged margin of length 2 is the `simplify()` that reaches
# `graph_rewrite(self, symbolic)`: Python builds STACKs there and this port does not,
# so it answers nothing rather than dropping an axis and claiming a half-ported `_mop`.
# A merged margin of length 0 is `_mop`'s `len(arg) == 0` early NOOP, which returns
# `_mop`'s own `self`. `shrink2` is the row for the length-2 refusal: Python fires and
# answers `SHRINK(S3, STACK(C1,CONST(2)), STACK(C1,C1))`, and this port answers none.
def mp_0.of(pat: Bool, m: Maybe<&1, List<&2, Marg>>, +ar: O.Arena, +self: U32) -> Hop:
  match pat m:
    case True{} Some{m <> Nil{}}   : mp_0.shrink(ar, self, m)
    # TWO Margs, or none: a merged margin of length 1 is the ONE axis per side that
    # `shape_to_shape_arg` turns into a bare CONST. The pattern is EXACTLY ONE element
    # because `<>` on the scrutinee gives the head, and the `Nil{}` is the TAIL -- a
    # three-scrutinee read of the same list would test the WHOLE list against `Nil{}`.
    case _ _                        : Hop{ar, 0}

def mp_0(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_0.of(mp_is(ar, mp_src0(ar, self), O.OpsSHRINK{}), marg_add(ar, self, mp_src0(ar, self)), ar, self)

# merge adjacent RESHAPEs (movement.py:10)
#   UPat(Ops.RESHAPE, src=(UPat(Ops.RESHAPE, name="x2"), UPat()), name="x")
#   lambda x,x2: x.replace(src=(x2.src[0], x.src[1]))
# A two-tuple src with no `allow_any_len` sets `strict_length`, so the arity test is `== 2`.
def mp_1.of(pat: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match pat:
    case True{}: mp_replace(O.OpsRESHAPE{}, mp_arg(ar, self), ar, self, [mp_src0(ar, mp_src0(ar, self)), mp_src(ar, self, 1)])
    case False{}: Hop{ar, 0}

def mp_1(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_1.of(Bool.and(mp_nsrc_is(ar, self, 2), mp_is(ar, mp_src0(ar, self), O.OpsRESHAPE{})), ar, self)

# remove noop RESHAPEs (movement.py:12)
#   UPat(Ops.RESHAPE, src=(UPat(name="x2"), UPat()), name="x")
#   lambda x,x2: x2 if x2._shape is not None and x2.shape == x.shape else None
# The answer is an EXISTING node, so nothing is interned. `shp_same` is False whenever
# EITHER side is None, which covers the `x2._shape is not None` half and the `x.shape`
# half at once -- and `x.shape` is the deferral, because `x` is a RESHAPE and fold.bend
# does not answer a movement op's shape.
def mp_2.of(pat: Bool, ok: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok:
    case True{} True{}: Hop{ar, mp_src0(ar, self)}
    case _ _           : Hop{ar, 0}

def mp_2(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_2.of(mp_nsrc_is(ar, self, 2), shp_same(tb, ar, mp_src0(ar, self), self), tb, ar, self)

# merge PERMUTEs (movement.py:14)
#   UPat(Ops.PERMUTE, src=(UPat(Ops.PERMUTE, name="x2"),), name="x")
#   lambda x,x2: x2.replace(arg=tuple(x2.arg[i] for i in x.arg))
# `replace` with a new `arg` and nothing else changed, so the op, src, tag and dtype are
# `x2`'s -- and the `arg` is the COMPOSED one. The one-element tuple src is strict, so the
# arity test is `== 1`. `tuple(x2.arg[i] for i in x.arg)` -- iterate `x.arg`, index `x2.arg`,
# and the IndexError is 0. Both tuples are `ATuple`, so the third scrutinee is `x2`'s own
# arg and NOT another `Maybe` that has to be unwrapped: composing out of `x2`'s SRCS (which
# is a list of node indices, not a permutation) answers `[B24[1], B24[0]]` and a node no
# rule can name.
def mp_perm.go(todo: List<&2, U32>, +p2: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}  : acc
    case i <> t : mp_perm.go(t, p2, List.append(&2, U32, acc, [list_at(p2, i)]))

def mp_perm(p2: List<&2, U32>, xa: List<&2, U32>) -> List<&2, U32>:
  mp_perm.go(xa, p2, Nil{})

def mp_3.of(pat: Bool, xa: Maybe<&2, List<&2, U32>>, x2a: Maybe<&2, List<&2, U32>>,
            +ar: O.Arena, +self: U32) -> Hop:
  match pat xa x2a:
    case True{} Some{perm} Some{p2}:
      +x2 = mp_src0(ar, self)
      mp_replace(O.OpsPERMUTE{}, O.ATuple{mp_perm(p2, perm)}, ar, x2, mp_srcs(ar, x2))
    case _ _ _ : Hop{ar, 0}

def mp_3(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_3.of(Bool.and(mp_nsrc_is(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsPERMUTE{})),
          arg_tuple(mp_arg(ar, self)), arg_tuple(mp_arg(ar, mp_src0(ar, self))), ar, self)

# remove noop PERMUTEs (movement.py:16)
#   UPat(Ops.PERMUTE, name="x")
#   lambda x: x.src[0] if list(x.arg) == list(range(len(x.arg))) else None
# No srcs in the pattern, so no arity test, and `x.src[0]`'s IndexError is the bottom.
def mp_4.of(ok: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match ok:
    case True{} : Hop{ar, mp_src0(ar, self)}
    case False{}: Hop{ar, 0}

# `list(x.arg) == list(range(len(x.arg)))`, as `arg[k] == k` for every k. ONE DEF, with
# the element's verdict as a PARAMETER: a match may not scrutinise a call, so splitting it
# into `.go` and `.at` would be the mutual recursion Bend refuses. The elements of `x.arg`
# are Python INTS, not nodes, so the comparison is `U32.is_eq` on the element and the
# position -- there is no arena here to read, and `const_is` on an element would be a read
# of whatever node that INDEX happens to name.
def mp_ident.at(todo: Maybe<&2, List<&2, U32>>, k: Nat, ok: Bool) -> Bool:
  match todo ok:
    case _ False{}        : False{}
    case None{} True{}    : False{}
    case Some{Nil{}} True{}: True{}
    case Some{i <> t} True{}:
      +kk = k
      mp_ident.at(Some{t}, 1n+kk, U32.is_eq(i, U32.from_nat(kk)))

def mp_4(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_4.of(mp_ident.at(arg_tuple(mp_arg(ar, self)), 0n, True{}), ar, self)

# STACK on INDEX CONST (movement.py:18-19)
#   UPat(Ops.STACK, src=UPat(Ops.INDEX, src=(UPat.var("src"), UPat(Ops.CONST))), name="stk")
#   lambda src,stk: src if stk.shape == src.shape and list(range(len(stk.src))) == [x.src[1].val for x in stk.src] else None
# `src` is a UPat and not a tuple, so the STACK needs at least one src, while the inner
# INDEX pattern IS a two-tuple and is strict: every stacked element must be a TWO-src
# `INDEX(_, CONST)` -- measured, not read off the source. `src` binds `stk.src[0].src[0]`,
# and `_shape`'s STACK arm is `(len(src),) + self.src[0].shape`, so the shape equality is
# what makes the rule reachable: it holds exactly when `buf.shape[0] == len(stk.src)`.
def mp_5.of(pat: Bool, ok: Bool, elems: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok elems:
    case True{} True{} True{}: Hop{ar, mp_src0(ar, mp_src0(ar, self))}
    case _ _ _                : Hop{ar, 0}

# `[x.src[1].val for x in stk.src] == list(range(len(stk.src)))`, as
# `stk.src[k].src[1].val == k` for every k. The arity is `== 2` and not `>= 2`: the inner
# pattern is a two-TUPLE, so `strict_length` is on and a three-src element does not match.
def mp_5.one(+ar: O.Arena, +x: U32, k: Nat) -> Bool:
  Bool.and(mp_is(ar, x, O.OpsINDEX{}),
           Bool.and(mp_nsrc_is(ar, x, 2), const_is(mp_const(ar, mp_src(ar, x, 1)), k)))

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

# const INDEX into STACK is src (movement.py:21-22)
#   UPat(Ops.INDEX, src=(UPat(Ops.STACK, name="a"), UPat.cvar("i")), name="idx", allow_any_len=True)
#   lambda a,i,idx: a.src[i.val] if len(idx.src) <= 2 else a.src[i.val].index(*idx.src[2:])
# `UPat.cvar` carries `Ops.CONST`, which is why this is the file's only two-element reject
# set. `allow_any_len` makes the arity `>= 2`, and `a.src[i.val]` is read ONCE and given
# to `mp_index`, which is what makes Python's two-branch conditional one call here.
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

# INDEX on INDEX is INDEX (movement.py:24-25)
#   UPat(Ops.INDEX, src=(UPat(Ops.INDEX, name="idx1", allow_any_len=True),), allow_any_len=True, name="idx2")
#   lambda idx1,idx2: idx1.src[0].index(*idx1.src[1:], *idx2.src[1:]) if all(x.shape == () for x in idx1.src[1:]+idx2.src[1:]) else None
# Both arities are `>= 1`, so `INDEX(x)` matches on its own and the two `src[1:]` slices
# are empty -- `all([])` is true, and fixture `idx_pick` is exactly that case. The answer
# is `mp_index` on the inner buffer with the two offset slices CONCATENATED.
def mp_7.of(pat: Bool, outer: Bool, inner: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat outer inner:
    case True{} True{} True{}: mp_index(ar, mp_src0(ar, mp_src0(ar, self)),
                                         List.append(&2, U32, mp_src_from(ar, mp_src0(ar, self), 1), mp_src_from(ar, self, 1)))
    case _ _ _                : Hop{ar, 0}

def mp_7(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_7.of(Bool.and(mp_nsrc_ge(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsINDEX{})),
          shp_each(tb, ar, mp_src_from(ar, self, 1)),
          shp_each(tb, ar, mp_src_from(ar, mp_src0(ar, self), 1)), tb, ar, self)

# INDEX on shaped INDEX (TODO: this can be more generic) -- movement.py:27-28
#   UPat(Ops.INDEX, src=(UPat(Ops.INDEX, src=(UPat.var("buf"), UPat.var("idx1_arg"))),), allow_any_len=True, name="idx2")
#   lambda buf,idx1_arg,idx2: buf.index(idx1_arg.index(*idx2.src[1:])) if len(idx1_arg.shape) == len(idx2.src[1:]) else None
# The inner INDEX's src is a two-tuple and so IS strict: `idx1` has exactly two srcs.
# Python's own TODO is the `UPat.var` on that second src, and it is already the generic
# form here. The two `mp_index` calls mean the inner node is built first and the outer
# node's arena is the INNER's -- which is why the arena is threaded, not reused.
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

# `early_reject` -- ops.py:1609 with the set from ops.py:1477, a NECESSARY CONDITION:
# the rule FIRES when the op set IS a subset of `ler`, and an empty set is a subset of
# everything. `O.pm_ler` folds over EVERY src, which is what Python's `{u.op for u in
# uop.src}` is; reading only `src[0]` would make rule 6's two-element set unreachable for a
# three-src INDEX, and `rej_pair` is the row for it.
def mp_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(O.op_in(have, o), mp_early.go(have, t))

def mp_early(ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  mp_early.go(O.pm_ler(ar, self), rej)

# THE DISPATCH. `upat.py` emits a closure; Bend has no first-class functions, so the tag
# selects a top-level def. That is why the table is `Data` and not a list of closures, and
# why a second pass costs nothing.
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

# THE TRY. Three things in Python's `PatternMatcher.rewrite`: the op the rule claims
# (`pdict.get(uop.op, [])`), the subset test, and `ret is not uop`.
def mp_try.go(ok: Bool, tag: U32, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match ok:
    case True{} : hop_self(mp_dispatch(tag, tb, ar, self), self)
    case False{}: Hop{ar, 0}

def mp_try(+tb: F.Table, +ar: O.Arena, +self: U32, +ler: List<&2, O.Op>, +e: O.PMEntry) -> Hop:
  mp_try.go(Bool.and(O.pm_claimed(O.PMEntry.ops(e), ar, self), mp_early(ar, self, O.PMEntry.rej(e))),
           O.PMEntry.tag(e), tb, ar, self)

# ===========================================================================
# THE MEASURED MUTATION TABLE. Fifteen textual edits, one at a time, each re-checked
# and re-run against the clean 26-row gate, by `.agents/slop/mop-mut.py`. This is the
# only evidence in the file that a row can FAIL: a row that cannot fail is a restatement,
# and most of these rows exist precisely because a mutation first showed them moving
# nothing. Every mutation but M12, M14 and M15 is a REVERT of one of this file's own
# fixes, so the set it moves is the set of rows that fix was load-bearing for.
#
# `rows moved` is the set difference of the two gates, so it names rows by the property
# they test rather than by the def that computes them.
#
#   mutation                                                        rows moved
#   -------------------------------------------------------------- -------------------------------------------------------------
#   M1  `hop_self.of`'s two arms swapped (the reported inversion)     14  ret_new, and every row that reads a
#                                                                       FIRED rule's answer: shrink1_ns
#                                                                       shrink1_marg reshape_pick permute_merge
#                                                                       permute_noop stack_idx const_idx2
#                                                                       const_idx3 const_idx5 rej_pair idx_idx
#                                                                       idx_pick idx_shaped
#   M2  `mp_nsrc_ge` back to `n < nsrc` (the off-by-one)                2  const_idx2 idx_pick
#   M3  `mp_index.pick` returns the VALUE, not `Arena.src(self, val)`  1  idx_pick
#   M4  `mp_replace` reads the arg off `self`                           1  permute_merge
#   M5  `mp_3` composes from `x2`'s SRCS, not its `arg`                 1  permute_merge
#   M6  `mp_ident.at` reads an arg ELEMENT as an arena index           1  permute_noop
#   M7  `marg.go` appends on the way UP (reverses the margin)           1  shrink2_marg
#                                                                       (see (0))
#   M8  `marg_add` takes `n` from the INNER shrink                       1  shrink1_marg
#   M9  `mp_5.one`'s strict two-tuple relaxed to `>= 2`                 0  -- see (2)
#   M10 `mp_0`'s one-axis rank guard dropped                             1  shrink2
#   M11 `G.ix` without the bottom's 0                                   17  see (3)
#   M12 `mp_early`'s subset test `and` -> `or`                           0  -- see (4)
#   M13 rule 6's reject set {STACK, CONST} misspelled as {STACK, NOOP}  4  const_idx2 const_idx3 const_idx5 rej_pair
#   M14 `hop_first`'s first-wins test flipped (last-wins)               13  M1's set MINUS ret_new
#   M15 rule 8 DELETED from the table                                    2  idx_shaped mop_len
#
# (0) M7'S ROW IS `shrink2_marg` AND NOT `shrink1_marg`, which reads 31 either way, and the
#     asymmetry is the ROW. Reversing the margin reorders its entries: `((1,1),(2,1))`
#     encodes 1121 and `((2,1),(1,1))` encodes 2111, so the two-entry row sees it and the
#     one-entry row cannot. A one-element fold is order-blind, which is why the bug survived
#     in `marg` while every single-margin row stayed correct. `List.append(r, [x])` putting
#     `x` at the END of `r` is MEASURED, reproducer `.agents/slop/notes/probe-append.bend`.
#
# (1) M8 IS THE ROW FOR `UPat.f`'s NAMING, and it is the only row that reads `n` rather
#     than `o`. `UPat.f` is `UPat(op, src=(self,))`, so `x` is the INNER shrink and `s` the
#     OUTER -- and `n` is `s.marg`'s, the outer's. The swap gives 32 where CPython gives
#     31: `SHRINK(b4, CONST(3), CONST(1))` carries the outer's `n = 1`, and the inner's is
#     2. `o` is unaffected because it is SUMMED, which is why one row and not two move.
#     `shrink2_marg` does NOT move: `S3` and `S4` are `((0,1),(1,1))` and `((1,1),(1,1))`,
#     so both `n`s are 1 and both orders agree. That asymmetry is the row's whole value.
#
# (2) M9 IS A PROOF, NOT A GAP. `mp_5.one`'s arity test is `== 2` because the inner pattern
#     is a two-TUPLE (`strict_length` is on). Relaxing it to `>= 2` can only ADMIT more
#     nodes, and every stacked element in the fixture is a two-src INDEX, so the set of
#     nodes rule 5 fires on is unchanged. The `>= 2` reading is exactly the defect M2 was,
#     and M2 DOES move two rows -- so the arity test is load-bearing, just not here.
#
# (3) M11 IS THE BIGGEST MUTATION IN THE TABLE and it is a GATE defect, not a rule defect.
#     `G.ix` is the arena's index list, and the bottom's `0` was missing, so `G.at(g, n)`
#     was one node PAST the one every row's comment names. That is why half this file's
#     rows read 0 before the fix and why the reported `hop_self` evidence ("four rows moved,
#     seven did not") understated the damage: `const_idx2` and `const_idx3` were reading
#     IX3 and IX5, not IX2 and IX3. Seventeen rows, including all three `grow_*`/`marg_*`
#     readers, depend on the addressing being right.
#
# (4) M12 IS ALSO A PROOF. `mp_early.go` folds its reject set with `and`, and `or` is the
#     only other reading of `issubset`. Those are DIFFERENT functions in general and the
#     SAME function on a set of one -- and rule 6's `{STACK, CONST}` is the only reject set
#     in this table with two members, so `and`/`or` differ on exactly one rule. M13 is that
#     rule's row: a misspelled set moves four rows where the fold's connective moves none,
#     because the difference is in WHICH ops are in the set, not in how they combine.
#
# (5) M14 IS `M1` AGAIN, AND THAT IS THE FINDING. Last-wins moves M1's THIRTEEN rows and
#     not `ret_new` -- so `hop_self` and the first-wins fold are the same defect seen from
#     two sides: both are "the answer survives when it should not". They are separate defs
#     with separate bugs, and one mutation does not substitute for the other: M1 leaves the
#     fold's ORDER intact (so `reshape_pick`, where `mp_1` and `mp_2` both claim R2, still
#     picks the earlier rule) while M14 leaves `ret is not uop` intact. A first pass at M14
#     flipped the test WITHOUT threading `+` through `r`, and the mutation was REFUSED --
#     `expected : r / observed : r (consumed more than once)`. That refusal is why the row
#     has a `+` in it now, and it is worth stating: a mutant that does not compile has
#     measured nothing, and a table entry reading "0 rows moved" because the edit was
#     refused is a lie. `mop-mut.py` reports "DOES NOT CHECK" for exactly this.
#
# M15 IS THE ROW THE COUNT ROWS EXIST FOR. It DELETES a `PMEntry` rather than editing it,
# and it deletes the LAST one, so no tag after it renumbers and no rule can fire
# differently: `mop_len` and `idx_shaped` are the only rows in the 26 that can move. Delete
# the COUNT rows and this mutation is invisible. (M13 is the same table with a wrong op set,
# which is a different job and is a separate row.)
# ===========================================================================
# THE ONE RECURSIVE DEF. The fuel is the first parameter and every self-call passes a
# list tail, so the decrease check reads left to right and stops at the first argument that
# shrinks. `h` is read twice -- once for its arena, which the next rule builds in, and once
# for the fold -- so it is `+`.
def mp_scan(rs: List<&2, O.PMEntry>, +tb: F.Table, +ler: List<&2, O.Op>, +self: U32, +h: Hop) -> Hop:
  match rs:
    case Nil{}: h
    case e <> t: mp_scan(t, tb, ler, self, hop_next(h, mp_try(tb, hop_ar(h), self, ler, e)))

# THE TABLE: `movement.py:5-29`, nine entries in Python's order. `tag` names the def, `ops`
# is the pdict key and `rej` is ops.py:1477's set over the pattern's OWN SRCS.
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

# `mop_cleanup.rewrite` -- ops.py:1611. The `tb` is the fold of the arena as it stands on
# ENTRY, which is the right answer for every node a rule can ask about, and `ler` is
# computed ONCE and threaded. The answer is a `Hop`: read `O.UOp.is_none` on its index for
# Python's `None`, and `hop_ar` for the arena to hand to the next node.
def mop_cleanup(+fx: F.Folded, +self: U32) -> Hop:
  mp_scan(mop_table(), F.Folded.t(fx), O.pm_ler(F.Folded.ar(fx), self), self, Hop{F.Folded.ar(fx), 0})

# ===========================================================================
# THE GATE. Every row is DERIVED FROM PYTHON, via
# `.agents/slop/notes/mop-truth3.py`, which prints its rows in THIS ORDER and with THIS
# SPELLING, so `diff <(python3 mop-truth3.py | grep '=') <(./bin/bend movement.bend)` is the
# acceptance test and neither side can be nudged to match the other. A row here can be
# WRONG rather than merely restate this file. `mop-truth.py` is the earlier, partial
# oracle; `mop-truth3.py` is the one that covers the rows.
#
# THE FIXTURE, and the node indices it fixes. `G.ix` is `[0]` then the interning order
# MINUS `ki`, which `g()` builds and never lists -- so `G.at(g, n)` is a LIST POSITION and
# the last two positions are one below the arena index they hold. `mop-truth3.py` prints
# the whole map. Naming the nodes makes the result-index rows readable, since "the rewrite
# of P2 IS P3" is a Python fact.
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

# `ParamArg(0, int32, size=..., image=...)`, the only thing that makes a BUFFER's shape
# `(size,)` or `(h, w, 4)`.
def psize(n: Maybe<&2, U32>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), n, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

def pimage(h: U32, w: U32) -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{},
             Some{O.Img{h, w}}, None{}, False{}, None{}}

# THE FIXTURE. Built in the order above, one `+` per node, because Bend has no mutable
# store and each intermediate arena is a value.
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
    [0,
     O.Found.i(c0), O.Found.i(c1), O.Found.i(c2), O.Found.i(c4), O.Found.i(sp),
     O.Found.i(b4), O.Found.i(b0), O.Found.i(b24), O.Found.i(big), O.Found.i(o1), O.Found.i(o2),
     O.Found.i(s1), O.Found.i(s2), O.Found.i(t2), O.Found.i(t11), O.Found.i(s3), O.Found.i(s4),
     O.Found.i(t4), O.Found.i(r1), O.Found.i(r2), O.Found.i(r3), O.Found.i(p1), O.Found.i(p2), O.Found.i(p3),
     O.Found.i(ss), O.Found.i(e0), O.Found.i(e1), O.Found.i(stk), O.Found.i(ix2), O.Found.i(ix3), O.Found.i(ix5),
     O.Found.i(j1), O.Found.i(j2), O.Found.i(j3), O.Found.i(k1), O.Found.i(k2), O.Found.i(k3), O.Found.i(add)]}

def rw(+gx: G, n: Nat) -> Hop:
  mop_cleanup(G.fx(gx), G.at(gx, n))

# The merged margin of `self` over its own src[0] -- `movement.py:8`'s generator for both
# halves of rule 0. GATE-ONLY: the rule does not use it.
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

# `enc` packs a margin as `(((o0*10+n0)*100 + o1*10+n1) ...)`, so the Python `((3,1),)` is
# 31 and `((1,1),(2,1))` is 1121. Both are printed by mop-truth3.py.
def marg_pair(+o: H.I64, n: H.I64) -> U32:
  U32.add(U32.mul(i64_u32(o), 10), i64_u32(n))

# ONE READ of the pair: a `Marg` taken out of a `List` is a binder, and a binder read
# twice is refused exactly like a parameter.
def marg_pair.of(+m: Marg) -> U32:
  marg_pair(Marg.o(m), Marg.n(m))

def marg_enc.go(ms: List<&2, Marg>, acc: U32) -> U32:
  List.foldl(~&2, ~Marg, ~U32, (a: U32) => (m: Marg) => U32.add(U32.mul(a, 100), marg_pair.of(m)), ms, acc)

def t_mop_len() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, mop_table()))

# SHRINK over SHRINK at rank 1. Python answers `SHRINK(b4, CONST(3), CONST(1))`: three
# srcs, offsets 2+1 and size 1. `mop-truth3.py`: `at(13) = S2 -> FRESH nsrc=3`.
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

# THE FIRST OF THE TWO DEFERRED WALLS, and the row that says so. CPython answers a 3-src
# SHRINK for S4; the port answers none, because rank 2's `_mop` needs
# `UOp.sink(*usrcs).simplify()` and that is `graph_rewrite(self, symbolic)`. So this reads
# 1 where CPython says 0 -- and that is the row's job: it FAILS the day the wall is ported.
def t_shrink2() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 17n))))

# The rank-2 merged margin, `((1,1),(2,1))` == 1121. The GENERATOR is ported even though
# the node it feeds is not, so this row and `marg_n2` are about `marg_add` and not about
# rule 0 firing.
def t_shrink2_marg() -> U32:
  marg_enc.go(marg_un.go(g_marg(17n)), 0)

def t_marg_n1() -> U32:
  U32.from_nat(marg_n.go(g_marg(13n)))

def t_marg_n2() -> U32:
  U32.from_nat(marg_n.go(g_marg(17n)))

# FIRST WINS, and the fixture is built so `mp_1` and `mp_2` BOTH claim R2 and DISAGREE.
# Python: `mp_1` gives `RESHAPE(b4, st4)` and `mp_2` gives `RESHAPE(b4, CONST(4))`, and
# `rewrite` returns the first. `mop-truth3.py`: `at(20) = R2 -> R3 nsrc=2`.
def t_reshape_pick() -> U32:
  +h = rw(g(), 20n)
  b2u(mp_is(hop_ar(h), mp_src(hop_ar(h), hop_ix(h), 1), O.OpsSTACK{}))

# THE SECOND DEFERRED WALL. CPython answers `b4` (index 6) for R3; the port answers none,
# because rule 2 asks `x.shape` for a RESHAPE and fold.bend does not answer a movement op's
# shape. So this reads 0 where CPython says 6, and the comment above it is the reason.
def t_reshape_noop() -> U32:
  hop_ix(rw(g(), 21n))

# `P2 -> P3`, i.e. the permutes COMPOSE and the answer is a different arg node. Reading
# 24 rather than 22 is what distinguishes the composed arg from `x2`'s own.
def t_permute_merge() -> U32:
  hop_ix(rw(g(), 23n))

def t_permute_noop() -> U32:
  hop_ix(rw(g(), 24n))

def t_stack_idx() -> U32:
  hop_ix(rw(g(), 28n))

# `IX2 -> C1` (index 2). Rule 6's answer is a node the fixture ALREADY HOLDS, which is
# `a.src[i.val]` with no `index()` call: two srcs, so `mp_6` takes the `True True` arm.
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

# `UOp.index`'s STACK special case: rule 7's answer is a node it did NOT build. `J3` has one
# src, so the `zip` of `idx1.src[1:]` and `idx2.src[1:]` is empty and the offset list is just
# `C1` -- one src, a CONST, on a STACK buffer, which is ops.py:223's early return. Reading 2
# (`C1`) and not 1 (the VALUE) is what `mp_index.pick` resolving through `Arena.src` buys.
def t_idx_pick() -> U32:
  hop_ix(rw(g(), 34n))

def t_idx_shaped() -> U32:
  +h = rw(g(), 36n)
  mp_nsrc(hop_ar(h), hop_ix(h))

def t_idx_shaped_bad() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 37n))))

def t_unclaimed() -> U32:
  b2u(O.UOp.is_none(hop_ix(rw(g(), 38n))))

# Rule 6's TWO-element reject set, over a THREE-src INDEX (IX3): `ler` folds over every
# src, and reading only `src[0]` would leave `{STACK}` -- which does not contain `CONST`,
# so rule 6 would not fire and this row would read 0. It is the ANSWER's index, and
# `const_idx3` is the answer's arity, so the two are independent readings of one rewrite.
def t_rej_pair() -> U32:
  hop_ix(rw(g(), 30n))

# A rule that interns a node GROWS the arena, and a rule that does not does not. These two
# are the `Hop`'s ARENA half: `J2 -> INDEX(b4, C0, C1)` is a new node, `IX2 -> C1` is not.
def t_grow_new() -> U32:
  +gx = g()
  +h = mop_cleanup(G.fx(gx), G.at(gx, 33n))
  U32.sub(O.Arena.next(hop_ar(h)), O.Arena.next(F.Folded.ar(G.fx(gx))))

def t_grow_same() -> U32:
  +gx = g()
  +h = mop_cleanup(G.fx(gx), G.at(gx, 29n))
  U32.sub(O.Arena.next(hop_ar(h)), O.Arena.next(F.Folded.ar(G.fx(gx))))

# THE SAME TABLE VALUE, TWICE: the `Data` table has none of the linear-table cost a
# closure table pays.
def t_twice() -> U32:
  +gx = g()
  +ts = mop_table()
  +tb = F.Folded.t(G.fx(gx))
  +ar = F.Folded.ar(G.fx(gx))
  +ler = O.pm_ler(ar, G.at(gx, 23n))
  +a = mp_scan(ts, tb, ler, G.at(gx, 23n), Hop{ar, 0})
  +b = mp_scan(ts, tb, ler, G.at(gx, 23n), Hop{ar, 0})
  b2u(U32.is_eq(hop_ix(a), hop_ix(b)))

# `ret is not uop`, ops.py:1611. The answer IS `self` -> `rewrite` returns None -> 1. This
# row CANNOT see the arms of `hop_self` (both readings answer index 0), which is why
# `t_ret_new` exists: it is the row for the def.
def t_ret_self() -> U32:
  b2u(O.UOp.is_none(hop_ix(hop_self(Hop{O.Arena.empty(), 0}, 0))))

# A NEW index against a DIFFERENT self: `ret is not None and ret is not uop` holds, so the
# answer SURVIVES and this reads 0. This row is what the inverted arms made read 1, i.e. the
# gate asserted the bug. There is no fixture node whose rewrite is itself, so the whole of
# `hop_self` rests on these two rows being derived and not restated.
def t_ret_new() -> U32:
  b2u(O.UOp.is_none(hop_ix(hop_self(Hop{O.Arena.empty(), 3}, 2))))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("mop_len", t_mop_len())
    b : Unit <- row("shrink1_ns", t_shrink1_ns())
    c : Unit <- row("shrink1_marg", t_shrink1_marg())
    d : Unit <- row("shrink2", t_shrink2())
    e : Unit <- row("shrink2_marg", t_shrink2_marg())
    f : Unit <- row("marg_n1", t_marg_n1())
    h : Unit <- row("marg_n2", t_marg_n2())
    i : Unit <- row("reshape_pick", t_reshape_pick())
    j : Unit <- row("reshape_noop", t_reshape_noop())
    k : Unit <- row("permute_merge", t_permute_merge())
    l : Unit <- row("permute_noop", t_permute_noop())
    m : Unit <- row("stack_idx", t_stack_idx())
    n : Unit <- row("const_idx2", t_const_idx2())
    o : Unit <- row("const_idx3", t_const_idx3())
    p : Unit <- row("const_idx5", t_const_idx5())
    q : Unit <- row("idx_idx", t_idx_idx())
    r : Unit <- row("idx_pick", t_idx_pick())
    s : Unit <- row("idx_shaped", t_idx_shaped())
    t : Unit <- row("idx_shaped_bad", t_idx_shaped_bad())
    u : Unit <- row("unclaimed", t_unclaimed())
    v : Unit <- row("rej_pair", t_rej_pair())
    w : Unit <- row("grow_new", t_grow_new())
    x : Unit <- row("grow_same", t_grow_same())
    y : Unit <- row("twice", t_twice())
    row("ret_self", t_ret_self())
    row("ret_new", t_ret_new())
