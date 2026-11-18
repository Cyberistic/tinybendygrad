# movement.bend -- tinygrad/uop/movement.py. `mop_cleanup`: the pattern matchers
# # TODO: pm_mops from rangeify belongs here. this is all pattern matchers that
# A rule here answers a NEW UOP or `None`, not a verdict, so a rewrite carries the
# `early_reject` IS A NECESSARY CONDITION, not a veto: a rule FIRES when the op set
# IS a subset of `ler` (ops.py:1701). Rule 6's `{STACK, CONST}`, from `UPat.cvar`,
# DEFERRED: `mp_0` at rank >= 2 (`UOp.sink(...).simplify()` would reach
# from the END when `v` is negative, and the port read every index as a `U32`, so a
# negative `v` became a huge `U32` and the answer was the FIRST element. MEASURED

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
# WHICH SIDE PYTHON IS ON, since this def was INVERTED and its own comment was right:
# ops.py:1610 reads `if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret`,
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

# PYTHON'S LIST INDEX, and it is the fix for a MEASURED parity gap. `lst[v]` for a
# MEASURED 2026-10-30 against CPython at the pin, on `UOp(Ops.INDEX, src=(STACK(3,5,7),
# `None` IS PYTHON'S `IndexError`: the port has no exception form, and the honest
def mp_py_index.tail(sumneg: Bool, +v: H.I64, +n: H.I64) -> Maybe<&1, U32>:
  match sumneg:
    case True{}: None{}
    case False{}: Some{H.lo32(H.i64_add(n, v))}

def mp_py_index.head(cmp: Cmp, +v: H.I64, +n: H.I64) -> Maybe<&1, U32>:
  match cmp:
    case LT{}: Some{H.lo32(v)}
    case _: None{}

def mp_py_index.of(neg: Bool, +v: H.I64, +n: H.I64) -> Maybe<&1, U32>:
  match neg:
    case True{}:
# `n + v` -- the tail. `n >= 0` and `v < 0`, so the sum is `< n`, and it is in range
# exactly when it is not negative.
      mp_py_index.tail(H.i64_is_neg(H.i64_add(n, v)), v, n)
    case False{}:
      mp_py_index.head(H.i64_cmp(v, n), v, n)

def mp_py_index(v: H.I64, n: Nat) -> Maybe<&1, U32>:
  +i = v
  mp_py_index.of(H.i64_is_neg(i), i, H.i64_of_i32(U32.from_nat(n)))

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

# `UOp.index` -- ops.py:559. Three of these nine rules call it and it belongs in ops.bend
#     def index(self, *srcs, kwargs):
# the special case is why a rewrite can return a node it did not build, and `idx_pick` is
# `new_srcs[0].val` is the VALUE, and Python's answer is that value used as an INDEX into
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
# THE INDEX IS PYTHON'S, so `mp_py_index` resolves it against the STACK's OWN src count:
# a negative `v` reads from the END and an out-of-range `v` is Python's `IndexError`,
# which is the `None` here. `self` is the STACK, because `tinygrad/uop/ops.py:561` indexes
def mp_stack_val.pos(k: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match k:
    case Some{v}: Some{v}
    case None{}  : None{}

def mp_stack_val.of(e: Maybe<&1, H.I64>, +ar: O.Arena, self: U32) -> Maybe<&1, U32>:
  match e:
    case Some{v}: mp_stack_val.pos(mp_py_index(v, mp_nat(mp_srcs(ar, self))))
    case None{}  : None{}

def mp_stack_val.head(extra: List<&2, U32>, +ar: O.Arena, self: U32) -> Maybe<&1, U32>:
  match extra:
    case e <> Nil{}: mp_stack_val.of(Some{mp_const_val(ar, e)}, ar, self)
    case _: None{}

def mp_stack_val(+ar: O.Arena, self: U32, extra: List<&2, U32>) -> Maybe<&1, U32>:
  mp_stack_val.head(extra, ar, self)

def mp_index(+ar: O.Arena, +self: U32, +extra: List<&2, U32>) -> Hop:
  mp_index.of(mp_stack_val(ar, self, extra), Nat.is_eq(mp_nat(extra), 1n), mp_is(ar, self, O.OpsSTACK{}), ar, self, extra)

# `x.src[1].val`, which is an `I64` and a `Maybe` because `.val` is only for a CONST or a
# CAST of one (ops.py:259-262).
def mp_const(ar: O.Arena, i: U32) -> Maybe<&2, H.I64>:
  const_i64(mp_arg(ar, i))

# `UOp.replace` -- ops.py:252. `new_args = (kwargs.pop("op", self.op), kwargs.pop("src",
def mp_replace(op: O.Op, arg: O.Arg, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Hop:
  mp_hit(O.UOp.new(ar, op, src, arg, mp_tag(ar, self)))

# `as_shape` -- ops.py:807 -- and `marg` -- ops.py:813, SHRINK's arm.
#     def as_shape(self):
#     case Ops.PAD | Ops.SHRINK: return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
# TWO ARMS ARE PORTED and the middle one is not, because it is `ssimplify`, which is
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
# `List.append(&2, A, r, [x])` puts `x` at the END of `r` (MEASURED, and the reproducer is
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

def marg_zip.go(ys: List<&2, H.I64>, xs: List<&2, H.I64>, acc: List<&2, Marg>) -> List<&2, Marg>:
  match ys xs:
    case Nil{} _        : acc
    case _ <> _ Nil{}   : acc
    case y <> yt x <> xt: marg_zip.go(yt, xt, List.append(&2, Marg, acc, [Marg{x, y}]))

def marg_zip(ys: List<&2, H.I64>, xs: List<&2, H.I64>) -> List<&2, Marg>:
  marg_zip.go(ys, xs, Nil{})

# `tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg))`, with the four `None`s folded
# THE ARGUMENT ORDER IS THE WHOLE OF `(o + p, n)`, and it is a naming trap:
# `UPat.f` (ops.py:1504) is `UPat(op, src=(self,))`, so in
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
def mp_0.shrink(+ar: O.Arena, +self: U32, +m: Marg) -> Hop:
  +o = O.UOp.const(ar, O.CInt{Marg.o(m)})
  +s = O.UOp.const(O.Found.ar(o), O.CInt{Marg.n(m)})
  mp_hit(O.UOp.new(O.Found.ar(s), O.OpsSHRINK{}, [mp_src0(ar, self), O.Found.i(o), O.Found.i(s)], O.ANone{}, O.TNone{}))

# THE RANK TEST, and it is the whole of the `_mop` deferral. `_mop`'s node is
# buildable exactly when `UOp.sink(*usrcs).simplify()` is ops.py:515's EARLY
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
def mp_1.of(pat: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match pat:
    case True{}: mp_replace(O.OpsRESHAPE{}, mp_arg(ar, self), ar, self, [mp_src0(ar, mp_src0(ar, self)), mp_src(ar, self, 1)])
    case False{}: Hop{ar, 0}

def mp_1(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_1.of(Bool.and(mp_nsrc_is(ar, self, 2), mp_is(ar, mp_src0(ar, self), O.OpsRESHAPE{})), ar, self)

# remove noop RESHAPEs (movement.py:12)
def mp_2.of(pat: Bool, ok: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat ok:
    case True{} True{}: Hop{ar, mp_src0(ar, self)}
    case _ _           : Hop{ar, 0}

def mp_2(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_2.of(mp_nsrc_is(ar, self, 2), shp_same(tb, ar, mp_src0(ar, self), self), tb, ar, self)

# merge PERMUTEs (movement.py:14)
def mp_perm.go(todo: List<&2, U32>, +p2: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}  : acc
    case i <> t : mp_perm.go(t, p2, List.append(&2, U32, acc, [list_at(p2, i)]))

def mp_perm(p2: List<&2, U32>, xa: List<&2, U32>) -> List<&2, U32>:
  mp_perm.go(xa, p2, Nil{})

# AND THE MERGED PERMUTE CARRIES THE ORDER IN `src[1]`, AS
def mp_perm_srcs(ar: O.Arena, perm2: List<&2, U32>, x2: U32) -> List<&2, U32>:
  [x2, O.shape_arg(ar, perm2)]

def mp_3.of(pat: Bool, xa: Maybe<&2, List<&2, U32>>, x2a: Maybe<&2, List<&2, U32>>,
            +ar: O.Arena, +self: U32) -> Hop:
  match pat xa x2a:
    case True{} Some{perm} Some{p2}:
      +x2 = mp_src0(ar, self)
      +perm2 = mp_perm(p2, perm)
      mp_replace(O.OpsPERMUTE{}, O.ANone{}, ar, x2, mp_perm_srcs(ar, perm2, x2))
    case _ _ _ : Hop{ar, 0}

def mp_3(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_3.of(Bool.and(mp_nsrc_is(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsPERMUTE{})),
          arg_tuple(mp_arg(ar, self)), arg_tuple(mp_arg(ar, mp_src0(ar, self))), ar, self)

# remove noop PERMUTEs -- WAS movement.py:16-17, REMOVED UPSTREAM in 9fa22cc4f
def mp_4.of(ok: Bool, +ar: O.Arena, +self: U32) -> Hop:
  match ok:
    case True{} : Hop{ar, mp_src0(ar, self)}
    case False{}: Hop{ar, 0}

# `list(x.arg) == list(range(len(x.arg)))`, as `arg[k] == k` for every k. ONE DEF, with
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
# `a.src[i.val]` IS PYTHON'S LIST INDEX, so `mp_py_index` resolves it and a negative
# `i.val` reads from the END. MEASURED 2026-10-30: upstream's rule 6 answers `CONST 7`
# THE OUT-OF-RANGE ANSWER IS "NO REWRITE", and Python's is an `IndexError` -- the port
def mp_stack_src.of(k: Maybe<&1, U32>, ar: O.Arena, stk: U32) -> Maybe<&1, U32>:
  match k:
    case Some{v}: Some{mp_src(ar, stk, v)}
    case None{}  : None{}

def mp_stack_src(+ar: O.Arena, self: U32) -> Maybe<&1, U32>:
  +s = self
  +stk = mp_src0(ar, s)
  mp_stack_src.of(mp_py_index(mp_const_val(ar, mp_src(ar, s, 1)), mp_nat(mp_srcs(ar, stk))),
                  ar, stk)

def mp_6.of(pat: Bool, two: Bool, src: Maybe<&1, U32>, +ar: O.Arena, +self: U32) -> Hop:
  match pat two src:
    case True{} True{} Some{k} : Hop{ar, k}
    case True{} False{} Some{k}: mp_index(ar, k, mp_src_from(ar, self, 2))
    case _ _ _                 : Hop{ar, 0}

def mp_6(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_6.of(Bool.and(mp_nsrc_ge(ar, self, 2),
                   Bool.and(mp_is(ar, mp_src0(ar, self), O.OpsSTACK{}),
                            mp_is(ar, mp_src(ar, self, 1), O.OpsCONST{}))),
          mp_nsrc_is(ar, self, 2), mp_stack_src(ar, self), ar, self)

# INDEX on INDEX is INDEX (movement.py:24-25)
def mp_7.of(pat: Bool, outer: Bool, inner: Bool, +tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  match pat outer inner:
    case True{} True{} True{}: mp_index(ar, mp_src0(ar, mp_src0(ar, self)),
                                         List.append(&2, U32, mp_src_from(ar, mp_src0(ar, self), 1), mp_src_from(ar, self, 1)))
    case _ _ _                : Hop{ar, 0}

def mp_7(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:
  mp_7.of(Bool.and(mp_nsrc_ge(ar, self, 1), mp_is(ar, mp_src0(ar, self), O.OpsINDEX{})),
          shp_each(tb, ar, mp_src_from(ar, self, 1)),
          shp_each(tb, ar, mp_src_from(ar, mp_src0(ar, self), 1)), tb, ar, self)

# INDEX ON SHAPED INDEX IS STILL SPECIALIZED. movement.py:25 -- upstream marks
# INDEX on shaped INDEX (TODO: this can be more generic) -- movement.py:27-28
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

# THE MEASURED MUTATION TABLE. Fifteen textual edits, one at a time, each re-checked
# `rows moved` is the set difference of the two gates, so it names rows by the property
#   mutation                                                        rows moved
# (0) M7'S ROW IS `shrink2_marg` AND NOT `shrink1_marg`, which reads 31 either way, and the
# (1) M8 IS THE ROW FOR `UPat.f`'s NAMING, and it is the only row that reads `n` rather
# (2) M9 IS A PROOF, NOT A GAP. `mp_5.one`'s arity test is `== 2` because the inner pattern
# (3) M11 is the biggest mutation in the table and it is a gate defect, not a rule defect.
# (4) M12 IS ALSO A PROOF. `mp_early.go` folds its reject set with `and`, and `or` is the
#     only other reading of `issubset`. Those are DIFFERENT functions in general and the
# (5) M14 is `M1` again, and that is the finding. Last-wins moves M1's thirteen rows and
# M15 is the row the count rows exist for. It deletes a `PMEntry` rather than editing it,
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
   O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},              # was movement.py:16-17, REMOVED UPSTREAM in 9fa22cc4f  x  no srcs
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
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
             None{}, False{}, None{}}

def pimage(h: U32, w: U32) -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{},
             Some{O.Img{h, w}}, None{}, False{}, None{}}

# THE FIXTURE. Built in the order above, one `+` per node, because Bend has no mutable
# store and each intermediate arena is a value.
def g() -> G:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  +c4 = O.UOp.const(O.Found.ar(c2), O.CInt{H.i64_of_i32(4)})
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "0")
  +b4 = O.UOp.new.param(O.Found.ar(sp), O.OpsBUFFER{}, Some{4}, O.AParam{psize(Some{4})}, O.TNone{})
  +b0 = O.UOp.new.param(O.Found.ar(b4), O.OpsBUFFER{}, None{}, O.AParam{psize(None{})}, O.TNone{})
  +b24 = O.UOp.new.param(O.Found.ar(b0), O.OpsBUFFER{}, None{}, O.AParam{pimage(2, 4)}, O.TNone{})
  +big = O.UOp.new.param(O.Found.ar(b24), O.OpsBUFFER{}, None{}, O.AParam{pimage(2, 7)}, O.TNone{})
  +o1 = O.UOp.new.param(O.Found.ar(big), O.OpsBUFFER{}, Some{2}, O.AParam{psize(Some{2})}, O.TNone{})
  +o2 = O.UOp.new.param(O.Found.ar(o1), O.OpsBUFFER{}, Some{7}, O.AParam{psize(Some{7})}, O.TNone{})
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
  +o10 = O.shape_arg_found(O.Found.ar(r3), [1, 0])
  +p1 = O.UOp.new(O.Found.ar(o10), O.OpsPERMUTE{}, [O.Found.i(b24), O.Found.i(o10)], O.ANone{}, O.TNone{})
  +o10b = O.shape_arg_found(O.Found.ar(p1), [1, 0])
  +p2 = O.UOp.new(O.Found.ar(o10b), O.OpsPERMUTE{}, [O.Found.i(p1), O.Found.i(o10b)], O.ANone{}, O.TNone{})
  +o01 = O.shape_arg_found(O.Found.ar(p2), [0, 1])
  +p3 = O.UOp.new(O.Found.ar(o01), O.OpsPERMUTE{}, [O.Found.i(b24), O.Found.i(o01)], O.ANone{}, O.TNone{})
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

# the first of the two deferred walls, and the row that says so. CPython answers a 3-src
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

# THE GATE MOVED TO `gates/movement-gate.bend`.
# The rows are consumers: each calls a def above through `P.`, and the
# Its rows are the census this file prints, and `gates/<name>-gate.bend` is the
