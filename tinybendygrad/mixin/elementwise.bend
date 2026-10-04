# elementwise.bend -- tinygrad/mixin/elementwise.py. `ElementwiseMixin`: the
# promotion, the binop dispatch, and the method surface that makes
# `Tensor(...)+Tensor(...)` CONCRETE.
#
# WHAT IS IN HERE, and it is the whole of the part of Python that is a GRAPH
# FACT. `_broadcasted`'s promotion (elementwise.py:24-34), `_binop` (:36), `remint`
# (:12), `ufix` (:21), and the sixty methods whose body is an `alu` over a promoted
# operand. Those are the twelve ops tensor.bend's dunder table names, the three
# comparison binops plus their three negations, the unary alu family, and the
# composed ones (`neg`, `sub`, `logical_not`, `where`, `mod`, `fmod`, `div`,
# `square`, `minimum`, `bitwise_not`, the shifts and `pow`).
#
# FOUR WALLS, and each is a NAMED TOLERANCE rather than a hole.
#
#   1. `x: Self | ConstType` IS A `Data` UNION (`Ew` below), because Python's
#      `isinstance(x, type(self))` is a membership test over two types and a `Data`
#      union is a set of tags. `ufix` is then `ECon` -> a CONST node and `ETen` ->
#      the tensor, which is Python's `x if isinstance(x, Self) else wrap(ufix(x))`.
#   2. `_broadcasted` answers a PAIR, and a pair is a `Type` in Bend, so it is
#      `Br{l, r}`, a two-field `Data` record -- `mixin/dtype.bend`'s `Dts` and
#      `uop/weak.bend`'s `ODt` are the same shape for the same reason.
#   3. `promote` BUILDS, so the arena grows under it and `self._uop.dtype` is stale
#      the moment it fires. Python re-reads `.dtype` lazily, from one global ucache;
#      here it is one store per METHOD, and the whole file is written to keep it that
#      way. `Tensor.ar(t)` is only the right store while nothing has been minted
#      since `t` was made, which is exactly the condition that stops holding at the
#      second operand -- so `+ar` is threaded (`ew_promote`, `ew_cast.at`) and never
#      read off a tensor, and the two arms that mint nothing STILL rebase. See
#      `ew_promote` and `ew_alu2`; the measured failure is in
#      bend2-constraints.md, "rule 6 has a SECOND HALF".
#   4. `remint` is a RECURSION (`u.src[0]`) that GROWS the arena, so it is
#      self-recursive with the FUEL FIRST and it threads `+O.Arena` rather than a
#      fold: every read it makes (`op`, `arg`, `src0`) is a raw arena read of a node
#      that existed BEFORE the walk, and an append-only store does not renumber
#      what it already holds. That is why `ew_ccast_at` builds with the threaded
#      arena and does NOT call `uop/weak.bend`'s `wk_const_at`, which builds in
#      `F.Folded.ar(fx)` -- the arena rule, and the one `tensor.bend` records as its
#      second Bend rule. `ew_remint.put` then has to build in the arena its OWN
#      recursion grew, which is the same rule one level down.
#
# THE FLOAT-CONST FAMILY IS A THIRD WALL AND IT IS BIG. Every method whose Python
# body names a float LITERAL -- `cos` (math.pi/2), `exp` and `sigmoid` and
# `tanh` (1/math.log(2)), `log`/`log10`, `erf`, `asin`, `gelu`, `round` (0.5),
# `isinf` (float("inf")) and everything built on them -- cannot be written, because
# `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and `U32.to_f32` is an
# unfilled LAW which live code may not call. `tensor.bend`'s header records the same
# wall for its own CONST fixtures ("every CONST fixture here is an INT or a BOOL,
# and `Tensor(1.0)` is a `TODO(p3)`"), and it is the same wall rather than a second
# one. Every such line is a `TODO(p3)` at the foot, with the Python line and the
# literal it names, so the list is the deliverable.
#
# FIVE BEND RULES THIS FILE IS BUILT ON, each of which cost a compile cycle:
#
#   1. A def may only call defs DECLARED ABOVE it, and the diagnostic is "an unfilled
#      law is a dead claim", which names the CALLEE. So every `.at`/`.go`/`.put`
#      split is written callee-first and the gate's printers sit above every row.
#   2. A `match` may not scrutinise a COMPUTED VALUE, so `is_invalid`, `is_const`,
#      `base` and `ew_op_is` are all `.go` leaves that take the value as a parameter.
#      `promote`'s three-way choice is a TWO-SCRUTINEE match over two `Bool`
#      PARAMETERS, which needs no nesting at all.
#   3. A branch is NOT LAZY in an argument position ("Bend is strict: an argument is
#      evaluated before the callee branches"), and `promote`'s three arms have
#      DIFFERENT ARITY and one of them mints nothing. So the work is inside a `match`
#      ARM of a def whose FIRST parameter is the flag -- `ew_promote.at`,
#      `ew_ccast.go`, `ew_ufix.at` -- and never in a `Bool.pick` argument.
#   4. `Maybe` is a `Type`: no `+`, read once. Every optional answer here is
#      therefore a total wrapper over a `Bool` (`ew_base.pick`, `ew_const_val`) or
#      is dropped at the boundary (`wk_dt`'s `void` default).
#   5. THE ARENA A BUILD RETURNED IS NOT THE ARENA THAT WENT IN. Every def here that
#      builds returns a `Found` or a `Tensor` carrying the GROWN arena, and
#      `ew_promo2` re-folds between the two promotions for exactly that reason.
#
# THE GATE is at the foot: 72 rows, with the MEASURED mutation table under it.
# `ew-gate.py` IS THE AUTHORITY -- it is the only side derived from CPython rather
# than from this file -- so it is regenerated, never hand-edited.
#     .venv/bin/python .agents/slop/ew-gate.py > /tmp/py.txt
#     ./bin/bend tinybendygrad/mixin/elementwise.bend > /tmp/bd.txt
#     ./bin/bend tinybendygrad/mixin/elementwise.bend -o /tmp/ew && /tmp/ew > /tmp/nat.txt
#     wc -l /tmp/py.txt /tmp/bd.txt       # 71 vs 72 -- COUNTS FIRST. A clean `diff`
#                                         # over two EMPTY files is also clean.
#     cmp /tmp/py.txt /tmp/nat.txt          # the two BEND lanes agree
#     diff /tmp/py.txt /tmp/bd.txt          # 71 vs 72 -- ONE ROW DIFFERS, and
#                                           # that is the honest state, not a
#                                           # byte-identical claim.
# THE ONE IS `ew_promo_nc`, and it is UNFALSIFIABLE, which is a stronger statement
# than "three rows disagree". `ew-gate.py` NOW PRINTS the other two of that family
# (`ew_dt_promo_nc=i32`, `ew_op_promo_nc=CAST`) from live CPython, both for the
# fixture at :1253-1260 -- `Tensor(3) + Tensor(5)` is weakint with base op ADD;
# after `+ Tensor(7, dtype=dtypes.i32)` its src0 is `int` with op CAST -- and both
# AGREE with this port, so M13's conjunct is gated by CPython rather than by a
# paragraph. The SIGNATURE row stays unpaired because this file builds it from a
# BUFFER of a weak dtype and CPython cannot build that at all: `Tensor.empty(...,
# dtype=dtypes.weakint)` raises "cannot create storage for weak dtype" at
# tinygrad/mixin/creation.py:37. MEASURED both ways -- CPython's reachable fixture
# is `7 CONST/0 CONST/0 ADD/2 CAST/1 CONST/0 CAST/1 ADD/2 ` and this file's is
# `5 BUFFER/0 ADD/2 CAST/1 BUFFER/0 ADD/2 `. Printing the CPython one would compare
# two different graphs, so it is named rather than faked.
# EVERY OTHER row is derived from CPython rather than restated from this file, and three
# kinds of row exist because three kinds of bug are invisible to the others: the
# COUNT (a dropped or duplicated node), the INDEX/OP rows (`sub` builds an ADD with
# a negated rhs and NOT an `Ops.SUB`; `eq` builds a CMPNE and NOT a `CMPEQ`; two
# CONSTs print the same signature in either operand order), and the DTYPE rows
# (`promote` changes a node's dtype and nothing else it is printed for, so the whole
# promotion matrix is invisible to every signature row).

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../uop/weak.bend as W
import ./../tensor.bend as T

# ===========================================================================
# THE READERS `promote` NEEDS. `elementwise.py:30-33` reads four things off a
# tensor: `t._uop.base`, `t.dtype`, `dtypes.weaks` membership and the CONST-ness of
# the base. All four are here, and the base is a `Maybe` from the fold so it gets a
# total wrapper -- `None` means "this node IS its own base", which is what Python's
# `.base` answers for a node with no movement op over it.
# ===========================================================================

def ew_base.pick(m: Maybe<&1, U32>, i: U32) -> U32:
  match m:
    case Some{b}: b
    case None{}: i

def ew_base(+fx: F.Folded, +i: U32) -> U32:
  ew_base.pick(F.UOp.base(F.Folded.ar(fx), F.Folded.t(fx), i), i)

# `UOp.is_invalid` -- ops.py:267, `self.op is Ops.CONST and self.val is Invalid`.
# A two-scrutinee match over the op and the arg, and `CInvalid` is a CONSTRUCTOR
# pattern inside a field pattern, so the whole predicate is one arm.
def ew_is_invalid.go(op: O.Op, arg: O.Arg) -> Bool:
  match op arg:
    case O.OpsCONST{} O.APy{O.CInvalid{}}: True{}
    case _ _: False{}

def ew_is_invalid(+fx: F.Folded, +b: U32) -> Bool:
  ew_is_invalid.go(O.Arena.op(F.Folded.ar(fx), b), O.Arena.arg(F.Folded.ar(fx), b))

# `t._uop.base.op is Ops.CONST` -- the second conjunct of `promote`'s weak test, and
# the one a `weaks AND is_const` -> `weaks OR is_const` mutation breaks.
def ew_is_const(+fx: F.Folded, +b: U32) -> Bool:
  O.eq_op(O.Arena.op(F.Folded.ar(fx), b), O.OpsCONST{})

# `_wrap_uop` -- and the rule it exists for. The `Found` a BUILD returns carries the
# GROWN arena, and pairing its INDEX with a STALE arena is a read one past the end:
# `Arena.node` answers the bottom, a `void` dtype, and the graph loses a src without
# changing shape anywhere else. Every build in this file therefore wraps through here
# rather than through `T.tn_wrap_uop` with a second arena read.
def ew_of(+f: O.Found) -> T.Tensor:
  T.tn_wrap_uop(O.Found.ar(f), O.Found.i(f))

# THE FOLD IS TAKEN FROM THE TENSOR, NEVER HANDED IN. A `F.Folded` is a fold of ONE
# arena, and every build grows it, so a fold passed down a call chain goes stale the
# moment the callee mints -- and a stale fold does not raise: `wk_dt` answers `void`,
# `void` is not weak, and the node takes the CAST arm. Taking the fold from the
# tensor's OWN arena at the point of use is what makes that unrepresentable, and it
# is the same discipline as `ew_of`: the arena comes from whatever LAST built.
def ew_fx(+t: T.Tensor) -> F.Folded:
  F.folded(T.Tensor.ar(t))

# `t.cast(dt)` -- mixin/dtype.py:19, `self if self.dtype == dt else
# self._wrap_uop(self._uop.alu(Ops.CAST, arg=dt))`. `uop/weak.bend` has it as
# `wk_cast_at` and this is the call; nothing here reimplements it.
#
# `.at` NAMES THE ARENA because `wk_cast_at` builds in `F.Folded.ar(fx)`, and a
# method that casts one operand and builds from the other would otherwise take the
# same index twice. See `ew_alu1.at` for why that is the rule here and not a choice.
def ew_cast.at(+ar: O.Arena, +t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  +f = W.wk_cast_at(F.folded(ar), T.Tensor.u(t), dt)
  ew_of(f)

def ew_cast(+t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  ew_cast.at(T.Tensor.ar(t), t, dt)

# ===========================================================================
# `ufix` -- elementwise.py:21. `x if isinstance(x, type(self)) else
# self._wrap_uop(self._uop.ufix(x))`, and `UOp.ufix` (ops.py:609) is `x if
# isinstance(x, UOp) else UOp.const(x)`. So the WHOLE of it is: a Tensor stays, and
# a Const becomes a CONST node in `self`'s arena. The `isinstance` becomes the union
# tag.
# ===========================================================================

type Ew is Data:
  ETen{t: T.Tensor}
  ECon{v: O.Const}

def ew_is_t(e: Ew) -> Bool:
  match e:
    case ETen{t}: True{}
    case _: False{}

# the dead arm is read only on the `ECon` side, and `Invalid` is the honest dead
# default: it is the arena's own "no value" and ops.py's `Invalid` is that too.
def ew_con(e: Ew) -> O.Const:
  match e:
    case ECon{v}: v
    case _: O.CInvalid{}

# AND `ew_ten` IS NOT OPTIONAL. An earlier version of `ew_ufix.at` answered `t` on
# the `ETen` arm -- `self` -- because `t` was in scope and `e` was not read. Python's
# `ufix` returns **x**, the argument, and returning `self` instead makes EVERY binop
# `(t OP t)`: it typechecks, it checks, every node COUNT and every ARITY is right
# (both operands hash-cons to one node), and the only thing in the whole file that
# sees it is a row whose two operands have DIFFERENT dtypes -- `ew_promo_remint`,
# where the rhs must be lifted from weakint to weakfloat and `self` is not. This is
# the sharpest instance of the rule the whole gate is built on: a wrong ARGUMENT is
# invisible to every row that reads a shape.
def ew_ten(e: Ew) -> T.Tensor:
  match e:
    case ETen{t}: t
    case _: T.tn_new(O.Arena.empty(), 0)

# TWO ARENAS, AND THE LONGER ONE CONTAINS THE OTHER. `ufix` can hand back a Tensor
# built in a DIFFERENT store from `self`'s -- the `ETen` case, where the operand was
# made elsewhere -- and then `_broadcasted` folds one arena and promotes against
# another. `Arena.node` answers the BOTTOM for an index past the end, which is a
# `void` dtype and therefore a `cast`, and the whole failure is SILENT: the cast is
# a real node, every arity is right, and the graph is wrong. That is why the two
# operands are REBASED onto one arena here rather than at each call site.
#
# "longer" is `Arena.next`, the store's node COUNT, and it is the right test because
# the store is APPEND-ONLY: every index valid in the shorter arena is still valid in
# the longer one, and no index is renumbered. This is the same argument
# `uop/divandmod.bend`'s rule 4 makes about a `+` not enforcing arena identity, and
# here it is the FIX rather than the hazard.
def ew_rebase(ar: O.Arena, +t: T.Tensor) -> T.Tensor:
  T.tn_new(ar, T.Tensor.u(t))

def ew_newer(longer: Bool, +a: O.Arena, +b: O.Arena) -> O.Arena:
  match longer:
    case True{}: a
    case _: b

def ew_newer.of(+a: O.Arena, +b: O.Arena) -> O.Arena:
  ew_newer(U32.is_ge(O.Arena.next(a), O.Arena.next(b)), a, b)

# ONE ARENA PER METHOD. This is the rule the whole file is built on, and it is worth
# stating why, because "take the longer arena" is the obvious alternative and it is
# wrong. `promote(l)` and `promote(r)` start from the same arena and BOTH MINT, so the
# two arenas they return are SIBLINGS: each is one node longer than the input, and
# each holds its own new node at the SAME index. The longer of two siblings is not a
# store that contains both -- the loser's new node is simply absent, and it reads back
# as whatever the winner put at that index. Silently: arity right, count plausible,
# graph wrong.
#
# What makes it sound instead is that the promotions are SEQUENTIAL and each takes the
# arena the previous one grew (`ew_promo2`), and every build appends rather than
# replacing. So one arena runs through a whole method, and the only merge is at ENTRY,
# where both operands are still in the store the fixture put them in -- a pair that is
# a prefix pair by construction rather than by luck.
type Tw is Data:
  Tw{a: T.Tensor, b: T.Tensor}

def Tw.a(x: Tw) -> T.Tensor:
  match x:
    case Tw{a, b}: a

def Tw.b(x: Tw) -> T.Tensor:
  match x:
    case Tw{a, b}: b

def ew_join(+x: T.Tensor, +y: T.Tensor) -> Tw:
  +ar = ew_newer.of(T.Tensor.ar(x), T.Tensor.ar(y))
  Tw{ew_rebase(ar, x), ew_rebase(ar, y)}

def ew_alu2(op: O.Op, +x: T.Tensor, +y: T.Tensor) -> T.Tensor:
  +j = ew_join(x, y)
  T.tn_alu(Tw.a(j), op, [T.Tensor.u(Tw.b(j))])

# `self.alu(Ops.WHERE, x, y)` -- the ternary, and the condition is `self`, which is a
# THIRD arena.
def ew_alu3(op: O.Op, +c: T.Tensor, +x: T.Tensor, +y: T.Tensor) -> T.Tensor:
  +ar = ew_newer.of(ew_newer.of(T.Tensor.ar(c), T.Tensor.ar(x)), T.Tensor.ar(y))
  +cr = ew_rebase(ar, c)
  T.tn_alu(cr, op, [T.Tensor.u(ew_rebase(ar, x)), T.Tensor.u(ew_rebase(ar, y))])

def ew_ufix.at(ist: Bool, +t: T.Tensor, +e: Ew) -> T.Tensor:
  match ist:
    case True{}: ew_ten(e)
    case False{}: T.tn_const(T.Tensor.ar(t), ew_con(e))

def ew_ufix(+t: T.Tensor, +e: Ew) -> T.Tensor:
  ew_ufix.at(ew_is_t(e), t, e)

# ===========================================================================
# `remint` -- elementwise.py:12.
#     return u.ccast(dt) if u.op is Ops.CONST else u.replace(src=(remint(u.src[0], dt),)+u.src[1:])
# It recurses on `u.src[0]` and it GROWS the arena, so it is one self-recursive def
# with the FUEL FIRST and it threads `+O.Arena`. `ew_remint.put` is a leaf, so the
# self-call can be an ARGUMENT of a `case` arm and there is no mutual recursion --
# which is the only way Bend can express `a.alu(op, f(b))` at all.
# ===========================================================================

def ew_const_val(arg: O.Arg) -> O.Const:
  match arg:
    case O.APy{v}: v
    case _: O.CInvalid{}

# ops.py:637 says it: ".cast folds away at exactly the dtypes a CONST derives
# (bool/weakint/weakfloat): bare there, the pair everywhere else". So a CONST
# rebuilt at a weak dtype or at bool is ONE node, and everywhere else it is a CAST
# over a CONST. That is the whole difference between `UOp.const(v, dt)` here and in
# CPython, and it is why `ew_promo_remint` prints three nodes and not four.
def ew_const_bare(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, S.CWeakInt{}, nm}: True{}
    case S.Dt{pri, bits, S.CWeakFloat{}, nm}: True{}
    case S.Dt{pri, bits, S.CBool{}, nm}: True{}
    case _: False{}

def ew_ccast.go(bare: Bool, +dt: S.Dt, +made: O.Found) -> O.Found:
  match bare:
    case True{}: made
    case False{}: O.UOp.new(O.Found.ar(made), O.OpsCAST{}, [O.Found.i(made)], O.ADt{dt}, O.TNone{})

# `UOp.const(val, dt)` -- ops.py:629-635. `uop/weak.bend`'s `wk_const_at` is these
# same two nodes, but it builds in `F.Folded.ar(fx)`, and this walk has GROWN the
# arena, so the CAST would name an index the caller's arena does not have. The
# value truncation is `W.wk_dt_const` and `wk_const_of` is weak.bend's own dead
# default; only the two `UOp.new` calls are spelled here, for the arena's sake.
def ew_ccast_at(+ar: O.Arena, u: U32, +dt: S.Dt) -> O.Found:
  v = W.wk_const_of(W.wk_dt_const(dt, ew_const_val(O.Arena.arg(ar, u))))
  ew_ccast.go(ew_const_bare(dt), dt, O.UOp.new(ar, O.OpsCONST{}, Nil{}, O.APy{v}, O.TNone{}))

def ew_src0(+ar: O.Arena, +u: U32) -> U32:
  O.Arena.src0(ar, u)

def ew_is_c0(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsCONST{})

# `u.replace(src=(...)+u.src[1:])`. `uop/weak.bend`'s `replace_in` IS `UOp.replace` --
# it is the hash-consing constructor read straight off the arena. The tail is
# `O.Arena.src_from(ar, u, 1)`, NOT `src_to`: `src_to` keeps the first `k` and
# `src_from` drops the first `k`, so `src_to(_, 1)` is the WHOLE list for a one-src
# node and the replacement silently gains a src. Measured -- `DETACH` came out with
# arity 2 and two CONSTs where CPython has arity 1 and one. The head goes back IN
# FRONT, which is `List.append(&2, U32, [head], tail)`; the other order compiles and
# silently relocates it to the end.
#
# AND THE STORE IS `child`'s, NOT `ar`'s. The recursive call that produced `child`
# may have minted a CONST one step deeper, so `child`'s index is valid only in the
# arena IT grew; handing `replace_in` the pre-recursion `ar` names an index one past
# its end. Measured on `ew_remint_recurse`, which printed `1 BUFFER/0` -- a one-node
# graph, with the arity still right. Same rule as `ew_of`: the arena comes from
# whatever LAST built.
def ew_remint.put(+child: O.Found, +ar: O.Arena, +u: U32) -> O.Found:
  +cr = O.Found.ar(child)
  W.replace_in(cr, u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_from(ar, u, 1)))

def ew_remint.go(fuel: Nat, isc: Bool, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  match fuel isc:
    case 0n _        : O.Found{ar, u}
    case 1n+p True{} : ew_ccast_at(ar, u, dt)
    case 1n+p False{}: ew_remint.put(ew_remint.go(p, ew_is_c0(ar, ew_src0(ar, u)), ar, ew_src0(ar, u), dt), ar, u)

def ew_remint(fuel: Nat, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  ew_remint.go(fuel, ew_is_c0(ar, u), ar, u, dt)

# ===========================================================================
# `promote` -- elementwise.py:29-33, the inner closure of `_broadcasted`.
#     if t._uop.base.is_invalid: return t
#     if t.dtype in dtypes.weaks and t._uop.base.op is Ops.CONST:
#       return t if t.dtype == (dt := weak_dtype(out_dtype)) else wrap(remint(t._uop, dt))
#     return t.cast(out_dtype)
#
# THREE ARMS OF DIFFERENT ARITY, one of which mints nothing, so the choice is a
# two-scrutinee match over two `Bool` PARAMETERS with the WORK inside the arm. A
# `Bool.pick` would evaluate all three and mint the CONST and the CAST on the
# branches that do not fire, which the `ew_promo_weak_keep` COUNT row sees.
#
# `remint` gets FOUR units of fuel. It descends through movement ops to a CONST, and
# a shape arg is at most a STACK of CONSTs, so four is two levels more than any
# fixture needs -- and an OVER-provisioned bound costs nothing while an
# under-provisioned one answers `None` for everything (uop/upat.bend's M2 lesson).
# ===========================================================================

# `+ar` IS THE ARENA THE ANSWER LIVES IN, on EVERY arm -- including the two that mint
# nothing. That is the point. An arm that answers `t` unchanged hands back a tensor
# carrying the arena as it was BEFORE the sibling promotion grew it, and the next
# build in that stale store takes an index a real node already holds. Rebasing on the
# no-op arms costs one node of nothing and makes "one arena per method" true rather
# than merely intended.
def ew_promote.b(same: Bool, +ar: O.Arena, +t: T.Tensor, +wd: S.Dt) -> T.Tensor:
  match same:
    case True{}: ew_rebase(ar, t)
    case False{}: ew_of(ew_remint(4n, ar, T.Tensor.u(t), wd))

def ew_promote.at(inv: Bool, wc: Bool, same: Bool, +ar: O.Arena, +t: T.Tensor, +od: S.Dt, +wd: S.Dt) -> T.Tensor:
  match inv wc:
    case True{}  _        : ew_rebase(ar, t)
    case False{} True{}   : ew_promote.b(same, ar, t, wd)
    case False{} False{}  : ew_cast.at(ar, t, od)

def ew_promote(+ar: O.Arena, +t: T.Tensor, +od: S.Dt) -> T.Tensor:
  +wd = W.weak_dtype(od)
  +fx = F.folded(ar)
  +b = ew_base(fx, T.Tensor.u(t))
  +dt = W.wk_dt(fx, T.Tensor.u(t))
  # `t.dtype in dtypes.weaks AND t._uop.base.op is Ops.CONST`. The second conjunct is
  # what keeps the weak arm off a weak ALGEBRAIC result: `weak_dtype(out_dtype)` is
  # weak whenever `out_dtype` is strong, so without it a weakint ADD against int32
  # stays weakint and the root then adds weakint to int32. `ew_dt_promo_nc` /
  # `ew_op_promo_nc` are the gate; `g_promo_nonconst`'s header has the CPython rows.
  ew_promote.at(ew_is_invalid(fx, b), Bool.and(W.dt_weak(dt), ew_is_const(fx, b)),
    O.eq_dt(dt, wd), ar, t, od, wd)

# ===========================================================================
# `_broadcasted` -- elementwise.py:24-34, and `_binop` -- elementwise.py:36.
#     y = self.ufix(y); x, y = (self, y) if not reverse else (y, self)
#     out_dtype = least_upper_dtype(x.dtype, y.dtype); return promote(x), promote(y)
#     # _binop: lhs, rhs = self._broadcasted(x, reverse); return lhs.alu(op, rhs)
#
# `least_upper_dtype` is `uop/fold.bend`'s hoisted lattice (`least_upper.of`), NOT
# a second copy of it: the brief's "promotion -- reuse, don't reimplement" is
# `fold.bend`'s lattice for the MEET and `uop/weak.bend`'s `weak_dtype` for the
# `weak_dtype(out_dtype)` the weak arm tests against.
# ===========================================================================

type Br is Data:
  Br{l: T.Tensor, r: T.Tensor}

# NAMED `ew_br_l`/`ew_br_r` AND NOT `Br.l`/`Br.r`: a reader whose NAME is a FIELD
# name of the record it reads is ambiguous to read back, and MEASURED here -- both
# spellings answered field 0, so every binop built `[lhs, lhs]` and every graph lost
# a src while `Arena.nsrc` still said 2. The count and the arity were both right and
# the GRAPH was wrong, which is the exact failure this gate's `ew_op_*` rows exist to
# catch.
def ew_br_l(b: Br) -> T.Tensor:
  match b:
    case Br{x, y}: x

def ew_br_r(b: Br) -> T.Tensor:
  match b:
    case Br{x, y}: y

def ew_pair(rev: Bool, a: T.Tensor, b: T.Tensor) -> Br:
  match rev:
    case True{}: Br{b, a}
    case False{}: Br{a, b}

# `promote` TAKES THE ARENA AS AN ARGUMENT and `ew_promo2` runs the two promotions
# SEQUENTIALLY through one store, re-reading the arena the first one grew. Threading
# rather than reading it off the tensor is what makes the pair a chain instead of two
# siblings -- see `ew_promote`'s note, which is the measured half of this.
def ew_promo2(+od: S.Dt, +p: Br) -> Br:
  +l = ew_promote(T.Tensor.ar(ew_br_l(p)), ew_br_l(p), od)
  Br{l, ew_promote(T.Tensor.ar(l), ew_br_r(p), od)}

# THE MERGE COMES BEFORE THE FOLD, and that order is load-bearing. Folding either
# operand's own arena is the bug this file measured twice: `wk_dt` of an index past
# the end answers `void`, `void` is not in `dtypes.weaks`, and every operand then
# takes the CAST arm -- a graph with the right ops, the right arities and the wrong
# dtypes, which is why `ew_dt_*` had to exist.
def ew_broadcasted.of(rev: Bool, +t: T.Tensor, +e: Ew) -> Br:
  +u = ew_ufix(t, e)
  +j = ew_join(t, u)
  +tf = Tw.a(j)
  +uf = Tw.b(j)
  +fx = ew_fx(tf)
  +od = F.least_upper.of(W.wk_dt(fx, T.Tensor.u(tf)), W.wk_dt(fx, T.Tensor.u(uf)))
  ew_promo2(od, ew_pair(rev, tf, uf))

def ew_broadcasted(+t: T.Tensor, +e: Ew, rev: Bool) -> Br:
  ew_broadcasted.of(rev, t, e)

def ew_binop(op: O.Op, +t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  ew_alu2(op, ew_br_l(p), ew_br_r(p))

# `logical_not` -- elementwise.py:57 -- is `self.cast(dtypes.bool).ne(True)`, so it
# is a CAST and a CMPNE and NOT an `Ops.NEG`. `ew_op_eq_s0` reads its inner node's
# op and `ew_lnot_i` reads its arity.
def ew_logical_not(+t: T.Tensor) -> T.Tensor:
  ew_binop(O.OpsCMPNE{}, ew_cast(t, S.boolean()), ECon{O.CBool{True{}}}, False{})

# `neg` -- elementwise.py:82 -- is `self.logical_not() if self.dtype == bool else
# self * (-1)`. The `-1` is the two's complement pair, because `H.i64_of_i32`
# sign-EXTENDS a U32 and `-1` is not a U32 literal.
def ew_neg.go(isbool: Bool, +t: T.Tensor) -> T.Tensor:
  match isbool:
    case True{}: ew_logical_not(t)
    case False{}: ew_binop(O.OpsMUL{}, t, ECon{O.CInt{H.i64_of_i32(4294967295)}}, False{})

def ew_neg(+t: T.Tensor) -> T.Tensor:
  +fx = ew_fx(t)
  ew_neg.go(S.Dt.is_bool(W.wk_dt(fx, T.Tensor.u(t))), t)

# `__ge__` -- elementwise.py:327 -- is `(self < x).logical_not()`, and `__le__` is
# `(self > x).logical_not()`, so both are the comparison plus a boolean negation and
# NOT a CMPEQ / a reversed CMPLT.
def ew_ge(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  ew_logical_not(ew_binop(O.OpsCMPLT{}, t, e, rev))

# `eq` -- elementwise.py:337 -- is `self.ne(x).logical_not()`.
def ew_eq(+t: T.Tensor, +e: Ew) -> T.Tensor:
  ew_logical_not(ew_binop(O.OpsCMPNE{}, t, e, False{}))

# `bitwise_not` -- elementwise.py:157 -- is `self ^ self.dtype.max` when UNSIGNED
# and `self ^ -1` otherwise, and `logical_not` for a bool. `S.Dt.is_unsigned` is
# the test and `DType.max` is `LAWS/spec.bend`'s `Dt.range`, which answers a `Maybe`
# for the weak dtypes -- so the dead default is `-1`, which is the OTHER arm's
# constant and therefore the honest "there is no max here".
def ew_dt_max(+t: T.Tensor) -> Maybe<&2, U32>:
  +fx = ew_fx(t)
  S.Dt.max(W.wk_dt(fx, T.Tensor.u(t)))

# `Maybe.default` is INVARIANT in its element type, so `U32 -> H.I64` is its own
# two-arm def and not a `Maybe.default`. `H.i64_of_i32` sign-EXTENDS, which is the
# right reading for a signed `dt.max` and for a uint8's 255.
def ew_dt_max_i64.of(m: Maybe<&2, U32>, d: H.I64) -> H.I64:
  match m:
    case Some{v}: H.i64_of_i32(v)
    case _: d

def ew_dt_max_i64(+t: T.Tensor) -> H.I64:
  ew_dt_max_i64.of(ew_dt_max(t), H.i64_of_i32(4294967295))

def ew_xor_const(un: Bool, +t: T.Tensor) -> T.Tensor:
  match un:
    case True{}: ew_binop(O.OpsXOR{}, t, ECon{O.CInt{ew_dt_max_i64(t)}}, False{})
    case _: ew_binop(O.OpsXOR{}, t, ECon{O.CInt{H.i64_of_i32(4294967295)}}, False{})

def ew_bitwise_not.go(b: Bool, un: Bool, +t: T.Tensor) -> T.Tensor:
  match b:
    case True{}: ew_logical_not(t)
    case _: ew_xor_const(un, t)

def ew_bitwise_not(+t: T.Tensor) -> T.Tensor:
  +fx = ew_fx(t)
  ew_bitwise_not.go(S.Dt.is_bool(W.wk_dt(fx, T.Tensor.u(t))),
    S.Dt.is_unsigned(W.wk_dt(fx, T.Tensor.u(t))), t)

# ===========================================================================
# THE ARITHMETIC AND COMPARISON FAMILY. One def per Python method, in Python's
# order, and no abstraction: `_binop` IS the abstraction and the methods below are
# its twelve call sites. `elementwise.py:103` and `:123` spell out that `sub` is
# `_binop(Ops.ADD, -b)` and NOT `Ops.SUB`, and `ew_op_sub0` is the row that pins it.
# ===========================================================================

def ew_add(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsADD{}, t, e, rev)
def ew_mul(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsMUL{}, t, e, rev)
def ew_mul2(+t: T.Tensor, +e: T.Tensor, rev: Bool) -> T.Tensor: ew_binop(O.OpsMUL{}, t, ETen{e}, rev)
def ew_bitwise_and(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsAND{}, t, e, rev)
def ew_bitwise_or(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsOR{}, t, e, rev)
def ew_bitwise_xor(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsXOR{}, t, e, rev)
def ew_lshift(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsSHL{}, t, e, rev)
def ew_rshift(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsSHR{}, t, e, rev)
def ew_maximum(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsMAX{}, t, e, rev)
def ew_pow(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsPOW{}, t, e, rev)
def ew_lt(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsCMPLT{}, t, e, rev)
def ew_ne(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor: ew_binop(O.OpsCMPNE{}, t, e, rev)

# `__gt__` -- elementwise.py:324 -- is `self._binop(Ops.CMPLT, x, True)`: the SAME op
# with `reverse` set. It is a one-liner here for the same reason, and `ew_src0_rev`
# is the row that sees the swap.
def ew_gt(+t: T.Tensor, +e: Ew) -> T.Tensor: ew_binop(O.OpsCMPLT{}, t, e, True{})

# `sub` -- elementwise.py:121-123. `_broadcasted`, then `a.alu(Ops.ADD, -b)`, and
# the NOTE says "alu, not +: _broadcasted already promoted these, and a second
# promote would cast -b (only a weak CONST is kept weak)". `ew_sub_no_promo2` is
# that NOTE as a row.
def ew_sub.of(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  +b = ew_neg(ew_br_r(p))
  ew_alu2(O.OpsADD{}, ew_br_l(p), b)

def ew_sub(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  ew_sub.of(t, e, rev)

# ===========================================================================
# THE UNARY ALU FAMILY. `self.alu(Ops.X)` with no promotion at all, so each is one
# line and `alu` is `T.tn_alu`. These are the methods `elementwise.py` writes as
# `return self.alu(Ops.NAME)` -- eleven of them, plus `threefry`'s one src.
# ===========================================================================

def ew_detach(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsDETACH{}, Nil{})
def ew_contiguous_backward(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsCONTIGUOUS_BACKWARD{}, Nil{})
def ew_reciprocal(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsRECIPROCAL{}, Nil{})
def ew_trunc(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsTRUNC{}, Nil{})
def ew_sqrt(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsSQRT{}, Nil{})
def ew_sin(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsSIN{}, Nil{})
def ew_log2(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsLOG2{}, Nil{})
def ew_exp2(+t: T.Tensor) -> T.Tensor: T.tn_alu(t, O.OpsEXP2{}, Nil{})
# `square` -- elementwise.py:584 -- is `self * self`, so it is a `_binop` whose two
# operands are the SAME tensor. `ew_square` is the row that says so: two srcs and no
# third node, which a `alu(MUL, self, self)` shortcut would also print -- so it is
# the COUNT, not the shape, that is the claim.
def ew_square(+t: T.Tensor) -> T.Tensor: ew_binop(O.OpsMUL{}, t, ETen{t}, False{})

# ===========================================================================
# THE COMPOSED ARITHMETIC. `where` and `mod`/`fmod`/`div` are the three that build
# their own src list rather than reusing `_binop`'s.
# ===========================================================================

# `where` -- elementwise.py:436-437. `x, y = self.ufix(x)._broadcasted(y)` and then
# `self.alu(Ops.WHERE, x, y)` -- note the CONDITION is `self`, NOT the promoted
# `ufix(x)`, so `ufix` only ever runs on the first operand here.
def ew_where.of(+t: T.Tensor, +x: Ew, +y: Ew) -> T.Tensor:
  +p = ew_broadcasted(ew_ufix(t, x), y, False{})
  ew_alu3(O.OpsWHERE{}, t, ew_br_l(p), ew_br_r(p))

def ew_where(+t: T.Tensor, +x: Ew, +y: Ew) -> T.Tensor:
  ew_where.of(t, x, y)

# `masked_fill` -- elementwise.py:455 -- is `mask.where(value, self)`.
def ew_masked_fill(+t: T.Tensor, +mask: T.Tensor, +value: Ew) -> T.Tensor:
  ew_where(mask, value, ETen{t})

# `div` -- elementwise.py:229-259. `rounding_mode` is `None | "trunc" | "floor"`, so
# it is a THREE-armed `Data` sum and the arm is a match, not a Bool. The int/int
# tests come BEFORE the promotion-to-default_float, so a `None` mode FALLS THROUGH
# both of them and reaches the float arm -- which is Python, and is why
# `Tensor([1,2,3]) / Tensor([2,3,4])` builds an `MUL` over a `RECIPROCAL` and not a
# `CDIV`. That fall-through is the single most surprising line in this file.
type Rm is Data:
  RNone{}
  RTrunc{}
  RFloor{}

# `floor` -- elementwise.py:672 -- is `(self < (b := self.trunc())).where(b-1, b)`.
# `b-1` is a TENSOR minus a weak CONST and not the constant `-1`, so it goes back
# through `_binop` and through the promotion, exactly as in Python -- which is why
# this row's node count is larger than a reader expects.
def ew_floor(+t: T.Tensor) -> T.Tensor:
  +b = ew_trunc(t)
  +l = ew_binop(O.OpsCMPLT{}, t, ETen{b}, False{})
  +bb = ew_rebase(T.Tensor.ar(l), b)
  ew_where.of(l, ECon{O.CInt{H.i64_of_i32(4294967295)}}, ETen{bb})

# `if dtypes.is_int(a.dtype) or a.dtype == dtypes.bool: a = a.cast(dtypes.default_float)`.
# `S.single()` is float32, which is `DEFAULT_FLOAT`'s default and which no caller of
# this path overrides. The cast is LAZY -- `Bool.pick` would mint the CAST on the arm
# that does not fire, and every count row would see it.
def ew_needs_float(+t: T.Tensor) -> Bool:
  +fx = ew_fx(t)
  +dt = W.wk_dt(fx, T.Tensor.u(t))
  Bool.or(S.Dt.is_int(dt), S.Dt.is_bool(dt))

def ew_cast_if_int.at(need: Bool, +t: T.Tensor) -> T.Tensor:
  match need:
    case True{}: ew_cast(t, S.single())
    case _: t

def ew_cast_if_int(+t: T.Tensor) -> T.Tensor:
  ew_cast_if_int.at(ew_needs_float(t), t)

def ew_div_round(rm: Rm, +d: T.Tensor) -> T.Tensor:
  match rm:
    case RTrunc{}: ew_trunc(d)
    case RFloor{}: ew_floor(d)
    case _: d

# THE THREE BUILDS ARE IN PYTHON'S ORDER, and `b` is REBASED into the arena `cast`
# grew before `reciprocal` builds in it. Without that, `cast` and `reciprocal` each
# append at index N to stores that are SIBLINGS -- same length, same index, different
# nodes -- and the `MUL` then names whichever one `ew_join` picked. That is the whole
# of the arena discipline in one line: before a build, the operand is in the CURRENT
# arena. `ew_alu2` does it for its two operands; this is the same two lines for a
# build whose operands are not the pair being combined.
def ew_div_float(rm: Rm, +a: T.Tensor, +b: T.Tensor) -> T.Tensor:
  +c = ew_cast_if_int(a)
  +r = ew_reciprocal(ew_rebase(T.Tensor.ar(c), b))
  ew_div_round(rm, ew_alu2(O.OpsMUL{}, c, r))

def ew_div_int(rm: Rm, +a: T.Tensor, +b: T.Tensor) -> T.Tensor:
  match rm:
    case RTrunc{}: ew_alu2(O.OpsCDIV{}, a, b)
    case RFloor{}: ew_alu2(O.OpsFLOORDIV{}, a, b)
    case _: ew_div_float(rm, a, b)

def ew_div.go(ai: Bool, bi: Bool, rm: Rm, +a: T.Tensor, +b: T.Tensor) -> T.Tensor:
  match ai bi:
    case True{} True{}  : ew_div_int(rm, a, b)
    case _ _            : ew_div_float(rm, a, b)

# `div`'s ENTRY, and the two rounding modes Python's callers reach for. `_broadcasted`
# runs once, at the top, exactly as it does for every other binop here.
def ew_div.p(rm: Rm, +a: T.Tensor, +b: T.Tensor) -> T.Tensor:
  +fx = ew_fx(a)
  +da = W.wk_dt(fx, T.Tensor.u(a))
  ew_div.go(S.Dt.is_int(da), S.Dt.is_int(da), rm, a, b)

def ew_div(+t: T.Tensor, +e: Ew, rev: Bool, rm: Rm) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  ew_div.p(rm, ew_br_l(p), ew_br_r(p))

# `mod` -- elementwise.py:212-214. `is_int(a) and is_int(b)` is tested on BOTH
# promoted operands and not on `a` alone, so it is a two-scrutinee match over two
# Bool PARAMETERS; the float arm is `a - a.div(b, "floor") * b`.
def ew_mod_int(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  ew_alu2(O.OpsFLOORMOD{}, ew_br_l(p), ew_br_r(p))

def ew_mod_float(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  +d = ew_div.p(RNone{}, ew_br_l(p), ew_br_r(p))
  +m = ew_mul2(d, ew_br_r(p), False{})
  ew_sub.of(ew_br_l(p), ETen{m}, False{})

def ew_mod.of(ai: Bool, bi: Bool, +t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  match ai bi:
    case True{} True{}  : ew_mod_int(t, e, rev)
    case _ _            : ew_mod_float(t, e, rev)

def ew_mod(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +fx = ew_fx(t)
  dt = W.wk_dt(fx, T.Tensor.u(t))
  ew_mod.of(S.Dt.is_int(dt), True{}, t, e, rev)

# `fmod` -- elementwise.py:225-227. The same shape with `Ops.CMOD` and a TRUNCATING
# division, so it is a separate def and not a rounding_mode parameter of `mod`.
def ew_fmod_int(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  ew_alu2(O.OpsCMOD{}, ew_br_l(p), ew_br_r(p))

def ew_fmod_float(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +p = ew_broadcasted(t, e, rev)
  +d = ew_div.p(RTrunc{}, ew_br_l(p), ew_br_r(p))
  +m = ew_mul2(d, ew_br_r(p), False{})
  ew_sub.of(ew_br_l(p), ETen{m}, False{})

def ew_fmod.of(ai: Bool, bi: Bool, +t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  match ai bi:
    case True{} True{}  : ew_fmod_int(t, e, rev)
    case _ _            : ew_fmod_float(t, e, rev)

def ew_fmod(+t: T.Tensor, +e: Ew, rev: Bool) -> T.Tensor:
  +fx = ew_fx(t)
  dt = W.wk_dt(fx, T.Tensor.u(t))
  ew_fmod.of(S.Dt.is_int(dt), True{}, t, e, rev)

# THE WALLS. Each is a Python line and the thing that is missing, in the file's own
# terms. `p3` is the phase that owns the method surface.
# ===========================================================================

# ===========================================================================
# the F32 CONSTANTS, and the wall above them was FALSE
# ===========================================================================
#
# The marker block that follows says "no float literal anywhere in the port, because
# `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and `U32.to_f32` is an unfilled
# LAW which live code may not call". MEASURED, all three halves of that are wrong:
#
#   A LITERAL WORKS. `0.044715` compiles and `F32.bits` of it is the f32 CPython's
#   `struct.pack('f', 0.044715)` gives. Seventeen literals were measured and all seventeen
#   land on CPython's exact bit pattern -- see .agents/slop/ew-consts-gate.sh, which is a
#   three-lane diff of the bit patterns, not of the decimals.
#   `F32.pi()` IS A CONSTANT, in base.bend, spelled `3.14159265` -- a TRUNCATED literal --
#   and it still rounds to CPython's f32(pi) = 0x40490fdb, because the truncation is under
#   half an ulp. `F32.div(F32.pi(), 2.0)` is therefore exactly f32(pi/2), and halving a
#   normal f32 is exact.
#   `U32.to_f32` IS a `law`, and a base law is callable: `F32.from_nat` (base.bend) calls
#   it. "An unfilled law which live code may not call" is true of a law someone left EMPTY
#   and false of this one.
#
# So the constants were never the wall. What they were is a REASON WRITTEN WITHOUT A
# MEASUREMENT, and it held up a dozen methods at a time -- which is the failure this block
# exists to prevent a second time: a named wall is a CLAIM, and a claim about what the
# substrate cannot do is the one kind of claim a compiler cannot check for you.
#
# ONLY THE TRANSCRIPTIONS GET A NAME. A constant with an exact short spelling is written
# where it is used -- `0.5`, `1.0`, `2.0`, `-1.0`, `0.01`, `1e-05`, `1e-08`, and `pi/2` are
# all exact in decimal and a named def for each would be a name to keep in sync with
# nothing. An IRRATIONAL is named because a transcription is a silent-typo surface:
# `0.6931472` for log(2) and `0.044715` for gelu's cubic are both wrong in the ninth
# decimal place and both still round to the right f32, so nothing but the gate catches a
# typo. That is the whole criterion, and it is why this block is eight defs and not
# seventeen.
def ew_k.log2() -> F32: 0.6931472

def ew_k.log10_2() -> F32: 0.30103

def ew_k.inv_log2() -> F32: F32.div(1.0, ew_k.log2())

def ew_k.sqrt_2() -> F32: F32.sqrt(2.0)

def ew_k.sqrt_2_over_pi() -> F32: 0.7978846

def ew_k.gelu() -> F32: 0.044715

def ew_k.quick_gelu() -> F32: 1.702

def ew_k.selu_alpha() -> F32: 1.6732632

def ew_k.selu_gamma() -> F32: 1.050701

# ===========================================================================
# THE `F32` CONST WALL WAS REFUTED. It read: "no float literal anywhere in the
# port, because `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and
# `U32.to_f32` is an unfilled LAW which live code may not call".
# ===========================================================================
#
# ALL THREE HALVES ARE FALSE, and the measurement is `.agents/slop/ew-consts-gate.sh`:
# 21 constants, three lanes, byte-identical on the f32 BIT PATTERNS. What the gate
# established, in the order it established it:
#
#   A LITERAL WORKS. `0.044715` compiles, and its `F32.bits` is the f32 CPython's
#   `struct.pack('f', 0.044715)` gives. So the "no float literal" claim needs no
#   `Word` and no `U32.to_f32`: a literal is not a constructor call.
#   `F32.pi()` IS A CONSTANT, spelled `3.14159265` in base.bend -- a TRUNCATION -- and it
#   is still bit-equal to f32(pi) = 0x40490FDB, because the truncation is under half
#   an ulp. `F32.div(F32.pi(), 2.0)` is therefore exactly f32(pi/2), halving a normal
#   f32 being exact.
#   `U32.to_f32` IS a `law`, and a base law is callable: `F32.from_nat` calls it. "An
#   unfilled law which live code may not call" describes a law someone left EMPTY, and
#   this one is not that.
#   EVEN INF IS PRODUCIBLE, which the `isinf` marker below had as its own reason:
#   `F32.div(1.0, 0.0)` is 0x7F800000. So `float("inf")` is not a wall either.
#
# AND THREE OF THE OBVIOUS SPELLINGS MEASURED WRONG, which is the part worth keeping:
#   `0.30102999` for log10(2) is one ulp LOW and `0.30103` -- FIVE digits -- is right.
#   `1.0507009` for selu's gamma is wrong and `1.050701` is right. **More digits is not
#   more accurate in f32**, and the intuition that it is is what wrote the first two.
#   `F32.sqrt(F32.div(2.0, F32.pi()))` is one ulp off, because it rounds twice where
#   CPython rounds once. A LITERAL cannot double-round, so that constant is a literal.
#
# So the markers below are no longer blocked on a constant. Each says what is actually
# left, and where that is "undiagnosed" it says THAT rather than borrowing the old
# excuse -- refuting a stated reason is not the same as landing the method, and a
# marker that keeps a reason which has been measured false is worse than no marker.
#
# `H.f32_show` IS A SIX-DECIMAL-PLACE FORMATTER where CPython's `repr` is a
# shortest-round-trip one, so f32(log 2) prints `0.693147` here and
# `0.6931471824645996` there. That is a real difference about a different def and it
# is NOT gated here; it is its own unit.
# TODO(p3) elementwise.py:500  cos  -- math.pi/2 is `F32.div(F32.pi(), 2.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:511  exp  -- 1/math.log(2) is `ew_k.inv_log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:840  log  -- math.log(2) is `ew_k.log2()`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:852  log10  -- math.log10(2) is `ew_k.log10_2()` = 0.30103, bit-exact -- NOT 0.30102999, which is one ulp low
# TODO(p3) elementwise.py:613  isinf  -- float("inf") is PRODUCIBLE: `F32.div(1.0, 0.0)` is 0x7F800000. the RULE BODY is the remainder; UNDIAGNOSED
# TODO(p3) elementwise.py:623  isfinite  -- was `isinf + 0.0`; both are now available, so the remainder is the rule body. UNDIAGNOSED
# TODO(p3) elementwise.py:633  isclose  -- rtol=1e-05 and atol=1e-08 are literals, bit-exact. the rule body is the remainder; UNDIAGNOSED
# TODO(p3) elementwise.py:654  ceil  -- b+1 is fine and was always fine -- the marker said so. `round` is the remainder; see 890
# TODO(p3) elementwise.py:709  hardswish  -- (1/6) is `F32.div(1.0, 6.0)`, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:721  hardsigmoid  -- alpha=1/6 and beta=0.5 are both available, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:744  leaky_relu  -- neg_slope=0.01 is a literal, bit-exact. nothing else was named; UNDIAGNOSED

# TODO(p3) elementwise.py:854  atanh        -- .log()
# TODO(p3) elementwise.py:866  asinh        -- .log()
# TODO(p3) elementwise.py:878  acosh        -- .log()
# TODO(p3) elementwise.py:890  round  -- 0.5 and 2.0 are available. THE REMAINDER IS NOT A CONSTANT: it is the rounding mode, and it still is
# TODO(p3) elementwise.py:921  tan          -- .cos()
# TODO(p3) elementwise.py:931  asin  -- math.pi/2 is available; `polyN` and the arcsine series are the remainder
# TODO(p3) elementwise.py:944  acos  -- math.pi/2 is available; `asin` is the remainder
# TODO(p3) elementwise.py:954  atan  -- math.sqrt(2) is `ew_k.sqrt_2()`, bit-exact; `asin` is the remainder
# TODO(p3) elementwise.py:964  elu  -- alpha=1.0 is a literal, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:976  celu  -- alpha=1.0 is a literal, bit-exact. nothing else was named; UNDIAGNOSED
# TODO(p3) elementwise.py:988  selu  -- alpha and gamma are `ew_k.selu_alpha()` and `ew_k.selu_gamma()` = 1.050701, bit-exact -- NOT 1.0507009. UNDIAGNOSED
# TODO(p3) elementwise.py:1000 softplus     -- beta=1.0
# TODO(p3) elementwise.py:1010 mish         -- softplus()
# TODO(p3) elementwise.py:1022 logsigmoid   -- softplus()
# TODO(p3) elementwise.py:1034 sinh         -- exp()
# TODO(p3) elementwise.py:1046 cosh         -- exp()
# TODO(p3) elementwise.py:1058 erf          -- polyN, 0.3275911
# TODO(p3) elementwise.py:410  copysign     -- -(mag := a.abs()) with a float 0 path
# TODO(p3) elementwise.py:418  logaddexp    -- .isfinite(), 0
# TODO(p3) elementwise.py:820  rsqrt        -- free of literals; blocked on sqrt's
#                                                own fold, not on a constant

# WALLS THAT ARE NOT CONSTANTS.
# `usum` / `uprod` -- elementwise.py:40-41 -- are `functools.reduce(op, argfix(*uops),
# self)` over a VARIADIC, and `argfix` is helpers.py's. The reduce itself is a
# self-recursive fold with the fuel first and is one def; the variadic is not
# expressible and is the whole of the wall.
# TODO(p3) elementwise.py:40  usum   -- functools.reduce + argfix + *uops
# TODO(p3) elementwise.py:41  uprod  -- ditto
#
# `contiguous` -- elementwise.py:59-66 -- tests `uop.has_buffer_identity()` (ops.py:952,
# P3), `self.device is None` and `uop.op is Ops.STAGE`, so its three arms need P3's
# buffer reader before the STAGE arm is reachable.
# TODO(p3) elementwise.py:59  contiguous -- has_buffer_identity + device
#
# `clamp` / `clip` -- elementwise.py:586-601 -- are `(self < min_).where(min_, self)`
# twice, and the two `is not None` tests are a `Maybe`. Both bounds arriving as
# `Maybe<&2, Ew>` rather than as two `Ew`s is a signature change rather than an
# algorithmic one, and it is not written rather than half-written.
# TODO(p3) elementwise.py:586  clamp   -- min_/max_ are `DTypeLike|None`
# TODO(p3) elementwise.py:599  clip    -- clamp's alias
#
# `relu` / `relu6` / `hardtanh` / `isnan` / `abs` / `sign` / `sqr` are all
# `where`/`ne` compositions of methods already here and are NOT deferred: they are
# three lines each and they gate. `rsqrt` is the one composition that is free of
# literals (`self.sqrt().reciprocal()`), so it is deferred on the SQRT fold rather
# than on a constant, which is a different kind of deferral from every line above.
# TODO(p3) elementwise.py:820  rsqrt   -- SQRT's fold, not a constant
#
# `usum`'s `operator.or_ if self.dtype is dtypes.bool else operator.add` is the
# only place the unit chooses BETWEEN TWO OPS on a dtype, and it is the reason
# `weak.bend`'s promotion matters here rather than only downstream: a bool reduce
# must answer an `Ops.OR` and an int reduce an `Ops.ADD`, and the two have different
# `dtype_from_uop` arms.

# ===========================================================================
# ===========================================================================
# THE GATE.
#
# EVERY ROW IS A GRAPH SHAPE, and the shape is the SIGNATURE of the toposort --
# `n=<count> OP/<nsrc> ...` in DFS-postorder with the BARE enum name -- so the
# oracle runs without hardware and the lanes diff byte for byte. `ew-gate.py` is
# the AUTHORITY: it is derived from CPython and this file is not, so a difference
# is a bug in THIS file unless the row is one of the named unfalsifiable ones at
# the head (currently exactly one, `ew_promo_nc`).
#     .venv/bin/python .agents/slop/ew-gate.py > /tmp/py.txt
#     ./bin/bend tinybendygrad/mixin/elementwise.bend > /tmp/bd.txt
#     wc -l /tmp/py.txt /tmp/bd.txt        # 71 vs 72 -- counts first: a clean
#                                          # `diff` over two empty files is clean
#     diff /tmp/py.txt /tmp/bd.txt
#
# The `n=` is in every signature on purpose. A boolean row that says "the ADD is
# there" cannot see a dropped CONST, and gradient.bend records two mutations that
# produced the RIGHT COUNT and the wrong graph.
#
# THREE KINDS OF ROW, because the three kinds of bug are blind to each other:
#   * COUNT rows, and the count in every signature -- a dropped or duplicated node.
#   * INDEX / OP rows (`ew_src0_*`, `ew_op_*`, `ew_dt_*`) -- a swapped op or a
#     swapped operand. Two CONSTs print the SAME signature in either operand order
#     (tensor.bend's mutation M15 is exactly that hole), and `promote` changes a
#     node's DTYPE and nothing else it is printed for, so the entire promotion
#     matrix is invisible without the `ew_dt_*` rows.
#   * `ew_both` -- the node BOTH promotions build, hash-consed to ONE node. A
#     first-wins / conjunction bug is invisible unless the two answers disagree, so
#     this asks for the node COUNT and not for an index.
#
# THE SHAPE OF A ROW: a PURE `g_*` builder returns a `Tensor`, and the row is one
# line that prints it. A `do IO<Unit>` block can only bind an `IO`
# (bend2-constraints, weak.py rule 8), so a row that prints twice calls its pure
# builder twice -- which is free, because the builder is pure and the fixture is
# three nodes.
# ===========================================================================

def ew_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# A FLOAT CONST PRINTS ITS f32 BITS AND AN INT CONST DOES NOT, and that asymmetry is the
# point rather than an inconsistency. Landing `sigmoid` and the three methods composed on
# it put FLOAT CONSTANTS into the graph, and a signature that printed every CONST as
# `CONST/0` could not tell `sigmoid` from a `sigmoid` with the wrong multiplier: the shape
# is identical and the value is the whole difference. `ew_quick_gelu` with `ew_k.gelu()`
# instead of `ew_k.quick_gelu()` is the same ten nodes with a different constant, and this
# row is the only thing in the port that can see it.
#
# The bits and not the decimal, because the port has no F64 and a decimal comparison would
# pass a value that rounds differently; the constants themselves are gated by value in
# ew-consts-gate.sh, and THIS is the gate that says a given method uses a given one.
# The ARG IS A PARAMETER and not a computed value: a `match` may scrutinise a parameter
# or a field and not a call, and `O.Arena.arg(ar, u)` is a call. So the reader is its own
# def over the arg and the caller passes it -- the shape `range_at.of` uses.
def ew_sig.bits.of(a: O.Arg) -> String:
  match a:
    case O.APy{O.CFloat{f}}: String.concat(["=", U32.show(F32.bits(f))])
    case _: SNil{}

def ew_sig.bits(+ar: O.Arena, u: U32) -> String: ew_sig.bits.of(O.Arena.arg(ar, u))

def ew_sig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: ew_sig.go(t, ar,
      String.concat([acc, O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u)),
        ew_sig.bits(ar, u), " "]))

def ew_sig.print(nm: String, +xs: List<&2, U32>, +ar: O.Arena) -> IO(Unit):
  IO.print(String.concat([nm, "=", ew_sig.go(xs, ar,
    String.concat([U32.show(U32.from_nat(List.length(&2, U32, xs))), " "]))]))

def ew_nnodes(+ar: O.Arena, i: U32) -> U32:
  U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, i)))

def ew_sig(nm: String, +t: T.Tensor) -> IO(Unit):
  ew_sig.print(nm, O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)), T.Tensor.ar(t))

def ew_cnt(nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(ew_nnodes(T.Tensor.ar(t), T.Tensor.u(t)))]))

def ew_opname(nm: String, +t: T.Tensor, u: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", O.Ops.name.of(O.Arena.op(T.Tensor.ar(t), u))]))

def ew_dtnm(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

# `k` is a SRC SLOT of the node the row named, so this is a direct read of a derived
# value rather than a re-walk.
def ew_dtsrc(nm: String, +t: T.Tensor, k: U32) -> IO(Unit):
  +fx = F.folded(T.Tensor.ar(t))
  IO.print(String.concat([nm, "=", ew_dtnm(W.wk_dt(fx, O.Arena.src(F.Folded.ar(fx), T.Tensor.u(t), k)))]))

# --- THE FIXTURES. Every one takes the INCOMING arena: an index means nothing
# outside the arena that produced it, and two fixtures built from two `Arena.empty()`s
# would intern the same node over the same index twice. tensor.bend's header records
# this and it is the reason its gate has a COUNT in every row.
def ew_buf.arg(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def ew_buf(+ar: O.Arena, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{ew_buf.arg(0, 4, dt)}, O.TNone{})

def ew_f32(ar: O.Arena) -> O.Found: ew_buf(ar, S.single())
def ew_i8(ar: O.Arena) -> O.Found: ew_buf(ar, S.int8())
def ew_i32(ar: O.Arena) -> O.Found: ew_buf(ar, S.int32())

def ew_ci(ar: O.Arena, v: U32) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})

def ew_cf(ar: O.Arena, +f: F32) -> O.Found: O.UOp.const(ar, O.CFloat{f})
def ew_cbool(ar: O.Arena, b: Bool) -> O.Found: O.UOp.const(ar, O.CBool{b})

# `Invalid` -- tinygrad/dtype.py:36, the singleton an OPTIONAL dtype's absent
# value is. It is
# the one thing `promote`'s FIRST arm exists for ("invalid bool is weak const"), and
# without a fixture holding one that arm is dead code that no row can see -- which is
# what mutation M3 measured, at zero. CPython mints it as
# `dtypes.bool.const(Invalid)`, and `Ops.CInvalid{}` is ops.bend's name for it.
def ew_cinvalid(ar: O.Arena) -> O.Found: O.UOp.const(ar, O.CInvalid{})

def ew_t(+f: O.Found) -> T.Tensor: T.tn_new(O.Found.ar(f), O.Found.i(f))
def ew_ct(+b: O.Found) -> T.Tensor: T.tn_wrap_uop(O.Found.ar(b), O.Found.i(b))

def ew_ctrue() -> Ew: ECon{O.CBool{True{}}}
def ew_cfalse() -> Ew: ECon{O.CBool{False{}}}

# --- 1: THE TWELVE OPS tensor.bend's dunder table names -------------------------
def g_add() -> T.Tensor:
  +c5 = ew_ci(O.Arena.empty(), 5)
  +c3 = ew_ci(O.Found.ar(c5), 3)
  ew_add(ew_ct(c3), ETen{ew_ct(c5)}, False{})

def t_add() -> IO(Unit): ew_sig("ew_add", g_add())

def g_add_f() -> T.Tensor:
  +b = ew_f32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  ew_add(ew_ct(b), ETen{ew_ct(c)}, False{})

def t_add_f() -> IO(Unit): ew_sig("ew_add_f", g_add_f())

# THE SRC-ORDER ROW. `reverse` puts the CONST first and the BUFFER second, and a
# BUFFER and a CONST print DIFFERENT signatures -- two CONSTs print the same one
# either way round, which is tensor.bend's mutation M15 and the hole it closed.
def g_add_rev() -> T.Tensor:
  +c = ew_ci(O.Arena.empty(), 3)
  +b = ew_f32(O.Found.ar(c))
  ew_add(ew_ct(b), ETen{ew_ct(c)}, True{})

def t_add_rev() -> IO(Unit): ew_sig("ew_add_rev", g_add_rev())

def g_add_int8() -> T.Tensor:
  +a = ew_i8(O.Arena.empty())
  +b = ew_i32(O.Found.ar(a))
  ew_add(ew_ct(a), ETen{ew_ct(b)}, False{})

def t_add_int8() -> IO(Unit): ew_sig("ew_add_int8", g_add_int8())

def g_mul() -> T.Tensor:
  +c5 = ew_ci(O.Arena.empty(), 5)
  +c3 = ew_ci(O.Found.ar(c5), 3)
  ew_mul(ew_ct(c3), ETen{ew_ct(c5)}, False{})

def t_mul() -> IO(Unit): ew_sig("ew_mul", g_mul())

# the six remaining single-op binops differ only in the op and the fixture value, so
# one builder takes the op and one value.
def g_bin1(op: O.Op, v: U32) -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), v)
  ew_binop(op, ew_ct(b), ETen{ew_ct(c)}, False{})

def t_and() -> IO(Unit): ew_sig("ew_and", g_bin1(O.OpsAND{}, 3))
def t_or() -> IO(Unit): ew_sig("ew_or", g_bin1(O.OpsOR{}, 3))
def t_xor() -> IO(Unit): ew_sig("ew_xor", g_bin1(O.OpsXOR{}, 3))
def t_shl() -> IO(Unit): ew_sig("ew_shl", g_bin1(O.OpsSHL{}, 3))
def t_shr() -> IO(Unit): ew_sig("ew_shr", g_bin1(O.OpsSHR{}, 3))
def t_max() -> IO(Unit): ew_sig("ew_max", g_bin1(O.OpsMAX{}, 3))
def t_pow() -> IO(Unit): ew_sig("ew_pow", g_bin1(O.OpsPOW{}, 2))
def t_ne() -> IO(Unit): ew_sig("ew_ne", g_bin1(O.OpsCMPNE{}, 3))
def t_lt() -> IO(Unit): ew_sig("ew_lt", g_bin1(O.OpsCMPLT{}, 3))

# `reverse` IS AN OPERAND SWAP, so the row that pins it has to put the BUFFER and the
# CONST on OPPOSITE sides of the call in the right order -- `(self=CONST, x=BUFFER,
# reverse=True)` puts the BUFFER first. `gt` and `le` are `reverse=True` on a CONST
# self, so they share a fixture; `ge` is `reverse=False` on a BUFFER self, so it does
# not, and sharing one builder across both is how the swap got tested in only one
# direction.
def g_rev(+t: T.Tensor, +e: Ew) -> T.Tensor:
  ew_ge(t, e, True{})

def g_gt() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  ew_gt(ew_ct(c), ETen{ew_ct(b)})

def t_gt() -> IO(Unit): ew_sig("ew_gt", g_gt())

def g_le() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  g_rev(ew_ct(c), ETen{ew_ct(b)})

def t_le() -> IO(Unit): ew_sig("ew_le", g_le())

def g_ge() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  ew_ge(ew_ct(b), ETen{ew_ct(c)}, False{})

def t_ge() -> IO(Unit): ew_sig("ew_ge", g_ge())

def g_eq() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  ew_eq(ew_ct(b), ETen{ew_ct(c)})

def t_eq() -> IO(Unit): ew_sig("ew_eq", g_eq())

# --- 2: THE UNARY ALU FAMILY. `self.alu(Ops.X)` with no promotion, so one builder
# over a `Data` sum is eight one-line rows rather than twenty-four lines.
type Un is Data:
  UDetach{}
  UContigBwd{}
  URecip{}
  UTrunc{}
  USqrt{}
  USin{}
  ULog2{}
  UExp2{}

def ew_unary.at(u: Un, +t: T.Tensor) -> T.Tensor:
  match u:
    case UDetach{}: ew_detach(t)
    case UContigBwd{}: ew_contiguous_backward(t)
    case URecip{}: ew_reciprocal(t)
    case UTrunc{}: ew_trunc(t)
    case USqrt{}: ew_sqrt(t)
    case USin{}: ew_sin(t)
    case ULog2{}: ew_log2(t)
    case _: ew_exp2(t)

def g_unary(u: Un) -> T.Tensor:
  b = ew_i32(O.Arena.empty())
  ew_unary.at(u, ew_ct(b))

# `sigmoid` is `(1 + (self * (-1/math.log(2))).exp2()).reciprocal()` (elementwise.py:693),
# and the constant is the one the refuted wall said could not be written. It is
# `F32.neg(ew_k.inv_log2())` and it is BIT-EXACT -- ew-consts-gate.sh row `k_inv_log2` --
# so this is the first of the 22 unmarked methods whose stated blocker is measurably gone.
#
# THE ORDER OF THE THREE BUILDS IS THE ORDER OF THE PYTHON and it does not matter to the
# signature: `ew_sig` reads `O.UOp.toposort`, the same DFS-POSTORDER CPython's `u.toposort`
# is, so what the row compares is the SHAPE and not the arena indices. That is why
# `ew_cf` may intern the constant whenever it is called without perturbing a row.
def ew_sigmoid(+t: T.Tensor) -> T.Tensor:
  ew_reciprocal(ew_add(ew_exp2(ew_mul2(t, ew_ct(ew_cf(T.Tensor.ar(t), F32.neg(ew_k.inv_log2()))), False{})), ECon{O.CInt{H.i64_of_i32(1)}}, True{}))

def ew_threefry(+t: T.Tensor, +e: Ew) -> T.Tensor: ew_binop(O.OpsTHREEFRY{}, t, e, False{})


# `swish` is `self * self.sigmoid()` (elementwise.py:801) and `silu` is `self.swish()`
# (:814), so both are one line over something that now exists -- which is the whole
# return on landing `sigmoid` first. `sigmoid` is called on the SAME tensor, so the
# MUL's two srcs are the tensor and the sigmoid of the tensor, and the signature row is
# what says so: a version that hoisted the sigmoid into its own binding would be a
# DIFFERENT graph and the row would catch it.
def ew_swish(+t: T.Tensor) -> T.Tensor: ew_mul2(t, ew_sigmoid(t), False{})
def ew_silu(+t: T.Tensor) -> T.Tensor: ew_swish(t)


# `quick_gelu` (elementwise.py:769) and `tanh` (:757) are one line each over the landed
# `sigmoid`, so they are the second and third methods the composition pays for. Both MULs
# in `tanh` put the CONSTANT ON THE LEFT because CPython writes `2.0 * self` and
# `2.0 * (...)`, and that is `rev=True` here -- the same thing sigmoid's ADD needed, and
# the signature row is the only thing in this port that can see an operand order at all.
def ew_quick_gelu(+t: T.Tensor) -> T.Tensor: ew_mul2(t, ew_sigmoid(ew_mul2(t, ew_ct(ew_cf(T.Tensor.ar(t), ew_k.quick_gelu())), False{})), False{})

# `tanh` is `2.0 * ((2.0 * self).sigmoid()) - 1.0` (elementwise.py:757) -- one line over
# the landed `sigmoid`, and it was HELD for three rounds. The blocker was real and it was
# NOT in this file: `ew_neg` is `x * CInt{H.i64_of_i32(4294967295)}`, and promoting a
# NEGATIVE int const to a float const went through a two-term sum
# `lo + sgn(hi) * 2**32` that needs `hi` EXACTLY. f32 has 24 mantissa bits, so
# `U32.to_f32(0xFFFFFFFF)` is 2**32 -- correctly rounded -- where the formula needed
# 4294967295, the high term collapsed to zero, and -1 and -2 BOTH converted to
# 4294967296.0. MEASURED, and the fix is `wk_i64_to_f32` carrying the magnitude in 24-bit
# chunks, gated by `.agents/slop/wk-f32-gate.sh` (18 rows, three lanes).
#
# BOTH MULs PUT THE CONSTANT ON THE LEFT, as CPython writes `2.0 * self`, and that is
# `rev=True` -- the same thing sigmoid's ADD needed, and the signature row is the only
# thing in this port that can see an operand order at all.
def ew_tanh(+t: T.Tensor) -> T.Tensor: ew_sub(ew_mul2(t, ew_sigmoid(ew_mul2(t, ew_ct(ew_cf(T.Tensor.ar(t), 2.0)), True{})), True{}), ECon{O.CFloat{1.0}}, False{})

def g_i32() -> T.Tensor: ew_ct(ew_ci(O.Arena.empty(), 5))

# THE MISSING MATRIX CELL, and the fixture pair is chosen so the fold is VISIBLE. `2` and
# not `1`, because a reminted `1.0` hash-conses with the `1.0` already there and the two
# graphs are indistinguishable -- `Tensor(1.0) * 1` is 2 nodes on BOTH sides and a matrix
# built only from it would look correct and be blind. Two CONSTs of different weak classes
# is a cell the other seven do not reach.
# THE ARENA IS THREADED, and every other fixture in this file threads it too --
# `g_promo_remint` is `+b = ew_f32(empty); c = ew_ci(Found.ar(b), 3)`. This one was
# `ew_cf(empty, 1.0)` and `ew_ci(empty, v)` as two INDEPENDENT roots, so both operands
# were node 1 in DIFFERENT arenas and the fold collided them: the int const was read
# from the float's arena and every value came out as 1.0.
#
# **THE THIRD FIXTURE-SHAPED WALL IN THIS SESSION, and the most expensive one, because
# two commits of diagnosis were built on top of it.** The file's own comment predicted it
# -- "Folding either operand's own arena is the bug this file measured twice" -- and the
# probe that found it is the one that printed `SAME=T idx=1/1` for the WORKING pair as
# well as the failing one. A defect that reproduces in the case that works is not a
# defect in the thing under test.
def g_f32c() -> T.Tensor: ew_ct(ew_cf(O.Arena.empty(), 1.0))
def g_i32c(v: U32, +t: T.Tensor) -> T.Tensor: ew_ct(ew_ci(T.Tensor.ar(t), v))

def t_detach() -> IO(Unit): ew_sig("ew_detach", g_unary(UDetach{}))
def t_sigmoid() -> IO(Unit): ew_sig("ew_sigmoid", ew_sigmoid(g_i32()))def t_swish() -> IO(Unit): ew_sig("ew_swish", ew_swish(g_i32()))
def t_silu() -> IO(Unit): ew_sig("ew_silu", ew_silu(g_i32()))
def g_wf_wi() -> T.Tensor:
  +f = g_f32c()
  g_i32c(2, f)

def t_promo_wf_wi() -> IO(Unit): ew_sig("ew_promo_wf_wi", ew_mul2(g_f32c(), g_i32c(2, g_f32c()), False{}))
def t_quick_gelu() -> IO(Unit): ew_sig("ew_quick_gelu", ew_quick_gelu(g_i32()))
def t_tanh() -> IO(Unit): ew_sig("ew_tanh", ew_tanh(g_i32()))


def t_contig_bwd() -> IO(Unit): ew_sig("ew_contig_bwd", g_unary(UContigBwd{}))
def t_recip() -> IO(Unit): ew_sig("ew_recip", g_unary(URecip{}))
def t_trunc() -> IO(Unit): ew_sig("ew_trunc", g_unary(UTrunc{}))
def t_sqrt() -> IO(Unit): ew_sig("ew_sqrt", g_unary(USqrt{}))
def t_sin() -> IO(Unit): ew_sig("ew_sin", g_unary(USin{}))
def t_log2() -> IO(Unit): ew_sig("ew_log2", g_unary(ULog2{}))
def t_exp2() -> IO(Unit): ew_sig("ew_exp2", g_unary(UExp2{}))

def g_threefry() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  c = ew_ci(O.Found.ar(b), 3)
  ew_threefry(ew_ct(b), ETen{ew_ct(c)})

def t_threefry() -> IO(Unit): ew_sig("ew_threefry", g_threefry())

# --- 3: THE COMPOSED ONES -------------------------------------------------------
# the int arm of `neg` is `self * -1` -- a MUL over a CONST -- and the BOOL arm is
# `logical_not` -- a CMPNE. Two fixtures, one per arm, so a mutation of either is
# LOCALISED and neither row can be satisfied by the other arm's graph.
def g_neg_i() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  ew_neg(ew_ct(b))

def t_neg() -> IO(Unit): ew_sig("ew_neg", g_neg_i())

def g_neg_b() -> T.Tensor:
  +n = ew_cbool(O.Arena.empty(), True{})
  ew_neg(ew_ct(n))

def t_neg_bool() -> IO(Unit): ew_sig("ew_neg_bool", g_neg_b())

def g_lnot_b() -> T.Tensor:
  +n = ew_cbool(O.Arena.empty(), True{})
  ew_logical_not(ew_ct(n))

def t_lnot() -> IO(Unit): ew_sig("ew_lnot", g_lnot_b())

# the int row is the one with a CAST in it: `cast(bool)` on a non-bool.
def g_lnot_i() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  ew_logical_not(ew_ct(b))

def t_lnot_i() -> IO(Unit): ew_sig("ew_lnot_i", g_lnot_i())

def g_where() -> T.Tensor:
  +ct = ew_cbool(O.Arena.empty(), True{})
  +c1 = ew_ci(O.Found.ar(ct), 1)
  c2 = ew_ci(O.Found.ar(c1), 2)
  ew_where(ew_ct(ct), ETen{ew_ct(c1)}, ETen{ew_ct(c2)})

def t_where() -> IO(Unit): ew_sig("ew_where", g_where())

def g_square() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  ew_square(ew_ct(b))

def t_square() -> IO(Unit): ew_sig("ew_square", g_square())

# `mod` and `fmod` differ in TWO decisions -- the op and the float arm's rounding
# mode -- so each is its own builder rather than a parameter of one. Both fixtures
# are an int32 buffer against a weakint CONST, so both take the int arm and the rows
# are distinguishable by their OP alone.
def g_mod() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  t = ew_ct(b)
  fx = F.folded(O.Found.ar(c))
  ew_mod.of(S.Dt.is_int(W.wk_dt(fx, O.Found.i(b))), True{}, t, ETen{ew_ct(c)}, False{})

def t_mod() -> IO(Unit): ew_sig("ew_mod", g_mod())

def g_fmod() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  t = ew_ct(b)
  fx = F.folded(O.Found.ar(c))
  ew_fmod.of(S.Dt.is_int(W.wk_dt(fx, O.Found.i(b))), True{}, t, ETen{ew_ct(c)}, False{})

def t_fmod() -> IO(Unit): ew_sig("ew_fmod", g_fmod())

# --- 4: THE PROMOTION MATRIX. One row per cell of `promote`'s three arms, which is
# the only part of this file whose effect a signature cannot see.
def g_promo_weak_keep() -> T.Tensor:
  +c5 = ew_ci(O.Arena.empty(), 5)
  c3 = ew_ci(O.Found.ar(c5), 3)
  ew_add(ew_ct(c3), ETen{ew_ct(c5)}, False{})

def t_promo_weak_keep() -> IO(Unit): ew_sig("ew_promo_weak_keep", g_promo_weak_keep())

def g_promo_weak_keep2() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  c = ew_ci(O.Found.ar(b), 3)
  ew_add(ew_ct(b), ETen{ew_ct(c)}, False{})

def t_promo_weak_keep2() -> IO(Unit): ew_sig("ew_promo_weak_keep2", g_promo_weak_keep2())

def g_promo_remint() -> T.Tensor:
  +b = ew_f32(O.Arena.empty())
  c = ew_ci(O.Found.ar(b), 3)
  ew_add(ew_ct(b), ETen{ew_ct(c)}, False{})

def t_promo_remint() -> IO(Unit): ew_sig("ew_promo_remint", g_promo_remint())

def g_promo_cast() -> T.Tensor:
  +a = ew_i8(O.Arena.empty())
  b = ew_i32(O.Found.ar(a))
  ew_add(ew_ct(a), ETen{ew_ct(b)}, False{})

def t_promo_cast() -> IO(Unit): ew_sig("ew_promo_cast", g_promo_cast())

# the cell where the two conjuncts of `promote`'s weak test DISAGREE: a bool CONST
# is weak-ish but is NOT in `dtypes.weaks`, so it takes the CAST arm.
def g_promo_bool_cast() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  n = ew_cbool(O.Found.ar(b), True{})
  ew_add(ew_ct(b), ETen{ew_ct(n)}, False{})

def t_promo_bool_cast() -> IO(Unit): ew_sig("ew_promo_bool_cast", g_promo_bool_cast())

def g_promo_bool_keep() -> T.Tensor:
  +ct = ew_cbool(O.Arena.empty(), True{})
  cf = ew_cbool(O.Found.ar(ct), False{})
  ew_add(ew_ct(ct), ETen{ew_ct(cf)}, False{})

def t_promo_bool_keep() -> IO(Unit): ew_sig("ew_promo_bool_keep", g_promo_bool_keep())

# `promote`'s FIRST ARM: `if t._uop.base.is_invalid: return t`. An `Invalid` bool is
# NOT in `dtypes.weaks` -- so without this arm it would be CAST to the out_dtype, and
# every other row in the file would be blind to that. CPython mints it as
# `dtypes.bool.const(Invalid)`; the arm returns the tensor UNTOUCHED, so the ADD's
# src1 is still the Invalid CONST and NOT a CAST over it. That is the whole claim.
def g_promo_invalid() -> T.Tensor:
  +b = ew_f32(O.Arena.empty())
  n = ew_cinvalid(O.Found.ar(b))
  ew_add(ew_ct(b), ETen{ew_ct(n)}, False{})

def t_promo_invalid() -> IO(Unit): ew_sig("ew_promo_invalid", g_promo_invalid())

# `remint`'s RECURSION. Every other weak fixture is a bare CONST, where `remint`
# takes `u.ccast(dt)` and never descends -- so `u.replace(src=...)` was unreachable
# and mutation M5 measured zero. `DETACH` is the node for this: ops.py:787 says
# `base` descends through `Ops.DETACH` explicitly, so a DETACH over a weakint CONST
# has a weak dtype AND a CONST base, which is exactly the cell where `promote` sends
# `remint` down the recursive arm. (`CONTIGUOUS_BACKWARD` looks like it and is not:
# it is neither a `Movement` nor a `DETACH`, so its base is ITSELF and `promote`
# takes the CAST arm instead -- measured, and it is why this row is `DETACH`.)
def g_remint_recurse() -> T.Tensor:
  +b = ew_f32(O.Arena.empty())
  +c = ew_ci(O.Found.ar(b), 3)
  +m = ew_detach(ew_ct(c))
  ew_add(ew_ct(b), ETen{m}, False{})

def t_remint_recurse() -> IO(Unit): ew_sig("ew_remint_recurse", g_remint_recurse())

# THE TWO-RULES-CLAIM-ONE-NODE ROW. `t + t` runs the SAME promotion twice over the
# SAME node, so the two CASTs hash-cons to one and the COUNT is the claim. Asking
# for an index here would be satisfied by any wrong-but-present node, which is
# bend2-constraints' rule about negative rows.
def g_both() -> T.Tensor:
  +b = ew_i32(O.Arena.empty())
  +t = ew_ct(b)
  ew_add(t, ETen{t}, False{})

def t_both() -> IO(Unit): ew_sig("ew_both", g_both())

# `sub`'s NOTE as a row: `_broadcasted` already promoted, so `a.alu(Ops.ADD, -b)`
# must NOT promote again -- a second promote would add a node and this count moves.
def g_sub8() -> T.Tensor:
  +a = ew_i8(O.Arena.empty())
  +b = ew_i32(O.Found.ar(a))
  ew_sub.of(ew_ct(a), ETen{ew_ct(b)}, False{})

def t_sub() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- ew_sig("ew_sub_no_promo2", g_sub8())
    ew_cnt("ew_sub_n", g_sub8())

def g_sub() -> T.Tensor:
  +c5 = ew_ci(O.Arena.empty(), 5)
  c3 = ew_ci(O.Found.ar(c5), 3)
  ew_sub.of(ew_ct(c3), ETen{ew_ct(c5)}, False{})

def t_sub_const() -> IO(Unit): ew_sig("ew_sub", g_sub())

# --- 5: THE COUNT, INDEX AND OP ROWS ---------------------------------------------
def t_count_add() -> IO(Unit): ew_cnt("ew_count_add", g_add())

# `sub` is `a.alu(Ops.ADD, -b)`, so the ROOT is an ADD and NOT an Ops.SUB, and src1
# is a MUL and not a bare CONST. Reading the op is the only thing that sees either.
# `ew_opname_root` / `ew_opname_src` take the fixture as a PARAMETER rather than
# binding it in the row, because a `do` block can only bind an `IO`; each call runs
# its own pure `g_sub()` and the fixture is five nodes.
def ew_opname_root(nm: String, +t: T.Tensor) -> IO(Unit):
  ew_opname(nm, t, T.Tensor.u(t))

def ew_opname_src(nm: String, +t: T.Tensor, k: U32) -> IO(Unit):
  ew_opname(nm, t, O.Arena.src(T.Tensor.ar(t), T.Tensor.u(t), k))

def t_op_sub() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- ew_opname_root("ew_op_sub0", g_sub())
    ew_opname_src("ew_op_sub1", g_sub(), 1)

# `eq` is `ne(...).logical_not()` and `logical_not` is `cast(bool).ne(True)`, so
# the root AND src0 are both CMPNE. This is gradient.bend's "x.eq(y) spelled CMPEQ"
# row one level up, and it is the row a swapped op moves.
def t_op_eq() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- ew_opname_root("ew_op_eq0", g_eq())
    ew_opname_src("ew_op_eq_s0", g_eq(), 0)

# the INDEX rows: the ROOT's src0's op. `reverse` swaps the two operands and the two
# orders have the SAME count, so only the index reading separates them.
def t_src0() -> IO(Unit):
  do IO<Unit>:
    x : Unit <- ew_opname_src("ew_src0_rev", g_add_rev(), 0)
    y : Unit <- ew_opname_src("ew_src0_fwd", g_add_f(), 0)
    ew_cnt("ew_count_rev", g_add_rev())

# THE DTYPE ROWS. These are the only rows that see `promote` at all: `remint`
# rebuilds a CONST with the same op, the same srcs and the same node count, so every
# signature row above is blind to it.
def t_dt_remint() -> IO(Unit): ew_dtsrc("ew_dt_remint", g_promo_remint(), 1)
def t_dt_remint_rev() -> IO(Unit): ew_dtsrc("ew_dt_remint_rev", g_add_rev(), 1)
def t_dt_keep() -> IO(Unit): ew_dtsrc("ew_dt_keep", g_promo_weak_keep2(), 1)
def t_dt_weak() -> IO(Unit): ew_dtsrc("ew_dt_weak", g_promo_weak_keep(), 1)
def t_dt_cast() -> IO(Unit): ew_dtsrc("ew_dt_cast", g_promo_cast(), 1)
def t_dt_bool_cast() -> IO(Unit): ew_dtsrc("ew_dt_bool_cast", g_promo_bool_cast(), 1)

# THE SECOND CONJUNCT. `t.dtype in dtypes.weaks and t._uop.base.op is Ops.CONST`
# (elementwise.py:31) is a CONJUNCTION, and every other fixture in this file holds a
# weak CONST -- so `base.op is CONST` was true in all of them and the second conjunct
# was never load-bearing. This fixture is the cell where it is: `w + w` is weak
# (`least_upper(weakint, weakint)`), so the ADD has a weak dtype and a base op of ADD,
# and promoting THAT against an int32 must CAST. CPython, elementwise.py:31-33:
#
#     Tensor(3) + Tensor(5)                        -> weakint, base op ADD
#     ... + Tensor(7, dtype=dtypes.i32)          -> src0 int, src0 op CAST
#
# because `weak_dtype(int32)` is weakint, so the weak arm would KEEP it -- and the
# weak arm is only for CONSTs. Dropping the conjunct keeps it weakint and the root
# ADD then adds a weakint to an int32, which is the promotion the lattice forbids.
def g_promo_nonconst() -> T.Tensor:
  +w = ew_buf(O.Arena.empty(), S.weakint())
  +s = ew_add(ew_ct(w), ETen{ew_ct(w)}, False{})
  +b = ew_i32(T.Tensor.ar(s))
  ew_add(s, ETen{ew_ct(b)}, False{})

def t_promo_nc() -> IO(Unit): ew_sig("ew_promo_nc", g_promo_nonconst())
def t_dt_promo_nc() -> IO(Unit): ew_dtsrc("ew_dt_promo_nc", g_promo_nonconst(), 0)
def t_op_promo_nc() -> IO(Unit): ew_opname_src("ew_op_promo_nc", g_promo_nonconst(), 0)

# --- 6: THE LATTICE ITSELF, straight from dtype.py --------------------------------
def t_lattice() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- ew_row("ew_lud_weakint_int32", O.eq_dt(F.least_upper.of(S.weakint(), S.int32()), S.int32()))
    b : Unit <- ew_row("ew_lud_bool_int32", O.eq_dt(F.least_upper.of(S.boolean(), S.int32()), S.int32()))
    c : Unit <- ew_row("ew_lud_weakint_float32", O.eq_dt(F.least_upper.of(S.weakint(), S.single()), S.single()))
    d : Unit <- ew_row("ew_lud_int8_uint8", O.eq_dt(F.least_upper.of(S.int8(), S.uint8()), S.int16()))
    e : Unit <- ew_row("ew_wd_int32", O.eq_dt(W.weak_dtype(S.int32()), S.weakint()))
    f : Unit <- ew_row("ew_wd_float32", O.eq_dt(W.weak_dtype(S.single()), S.weakfloat()))
    g : Unit <- ew_row("ew_wd_bool", O.eq_dt(W.weak_dtype(S.boolean()), S.boolean()))
    ew_row("ew_weaks", Bool.and(W.dt_weak(S.weakint()), W.dt_weak(S.weakfloat())))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_add()
    b : Unit <- t_add_f()
    c : Unit <- t_add_rev()
    d : Unit <- t_add_int8()
    e : Unit <- t_sub_const()
    f : Unit <- t_mul()
    g : Unit <- t_and()
    h : Unit <- t_or()
    i : Unit <- t_xor()
    j : Unit <- t_shl()
    k : Unit <- t_shr()
    l : Unit <- t_max()
    m : Unit <- t_pow()
    n : Unit <- t_lt()
    o : Unit <- t_gt()
    p : Unit <- t_ge()
    q : Unit <- t_le()
    r : Unit <- t_ne()
    s : Unit <- t_eq()
    u : Unit <- t_detach()
    t : Unit <- t_sigmoid()
    bh : Unit <- t_swish()
    bi : Unit <- t_silu()
    bh : Unit <- t_quick_gelu()
    bh : Unit <- t_tanh()
    bh : Unit <- t_promo_wf_wi()
    v : Unit <- t_contig_bwd()
    w : Unit <- t_recip()
    x : Unit <- t_trunc()
    y : Unit <- t_sqrt()
    z : Unit <- t_log2()
    aa : Unit <- t_exp2()
    ab : Unit <- t_sin()
    ac : Unit <- t_threefry()
    ad : Unit <- t_neg()
    ae : Unit <- t_neg_bool()
    af : Unit <- t_lnot()
    ag : Unit <- t_lnot_i()
    ah : Unit <- t_where()
    ai : Unit <- t_square()
    aj : Unit <- t_mod()
    ak : Unit <- t_fmod()
    al : Unit <- t_promo_weak_keep()
    am : Unit <- t_promo_weak_keep2()
    an : Unit <- t_promo_remint()
    ao : Unit <- t_promo_cast()
    ap : Unit <- t_promo_bool_cast()
    aq : Unit <- t_promo_bool_keep()
    a9 : Unit <- t_promo_invalid()
    ba : Unit <- t_remint_recurse()
    ar : Unit <- t_both()
    as : Unit <- t_sub()
    at : Unit <- t_count_add()
    au : Unit <- t_op_sub()
    av : Unit <- t_op_eq()
    aw : Unit <- t_src0()
    ay : Unit <- t_dt_remint()
    az : Unit <- t_dt_remint_rev()
    ba : Unit <- t_dt_keep()
    bb : Unit <- t_dt_weak()
    bc : Unit <- t_dt_cast()
    bd : Unit <- t_dt_bool_cast()
    be : Unit <- t_dt_promo_nc()
    bf : Unit <- t_op_promo_nc()
    bg : Unit <- t_promo_nc()
    t_lattice()

# ===========================================================================
# THE MUTATION TABLE. See .agents/slop/ew-mutate.py, which applies each edit to a
# scratch copy, runs the interpreted lane and diffs. Every number below is that
# harness's output, not an estimate. The column that matters is "rows MOVED",
# because a mutation that moves nothing is a measurement of what this gate does NOT
# see, and that is the useful half.
#
# | mutation | the edit | rows MOVED | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `ew_alu2`: `[T.Tensor.u(Tw.b(j))]` -> `[T.Tensor.u(Tw.a(j))]` | 40 | `lhs.alu(op, rhs)`'s operand order -- name `lhs` twice instead of `rhs`. |
# | M2 | `ew_promote`: `W.dt_weak(dt)` -> `True{}` | 35 | `promote`'s FIRST conjunct, `t.dtype in dtypes.weaks`. |
# | M3 | `ew_promote`: `ew_is_invalid(fx, b)` -> `False{}` | 1 (`ew_promo_invalid`) | `promote`'s `base.is_invalid` arm. ZERO until `ew_promo_invalid` was added: no fixture held an `Invalid` CONST, so the arm was dead code. |
# | M4 | `ew_promote`: `O.eq_dt(dt, wd)` -> `False{}` | 0 -- AN EQUIVALENCE | `t.dtype == weak_dtype(out_dtype)`. `remint` at the dtype a CONST already has rebuilds an IDENTICAL node (CPython agrees: `c.ccast(dtypes.weakint) is c`), so forcing the remint arm is not observable in any graph. Not a gap; a fact about `remint`. |
# | M5 | `ew_remint.put`: `[head] ++ src_from(...,1)` -> `src_from(...,1) ++ [head]` | 0 -- AN EQUIVALENCE | the `+u.src[1:]` order. `remint` only reaches nodes `base` descends into, and every one of those in this gate has ONE src, so `src[1:]` is empty and the two orders are the same list. Closing it needs a `Movement` node with a shape arg; measured that CPython takes the weak arm there and this port takes the CAST arm, which makes it a `uop/fold.bend` dtype question. Left open and named. |
# | M5b | `ew_remint.put`: `Arena.src_from(ar, u, 1)` -> `Arena.src_to(ar, u, 1)` | 1 (`ew_remint_recurse`) | that `u.src[1:]` is `src_from` (drop the first k) and NOT `src_to` (keep the first k). Zero until `ew_remint_recurse` was added: `remint.put` was unreachable. |
# | M6 | `ew_ccast_at`: `ew_const_bare(dt)` -> `False{}` | 6 | ops.py:637's ".cast folds away at exactly bool/weakint/weakfloat". |
# | M7 | `ew_neg`: `S.Dt.is_bool(...)` -> `False{}` | 1 (`ew_neg_bool`) | `neg`'s bool arm. Two-sided on purpose. |
# | M7b | `ew_neg`: `S.Dt.is_bool(...)` -> `True{}` | 5 | the other direction, so neither arm can be satisfied by the other's graph. |
# | M8 | `ew_pair`: swap the two arms | 34 | `x, y = (self, y) if not reverse else (y, self)`. |
# | M9 | `ew_promo2`: second promote builds in the FIRST's pre-growth arena | 2 (`ew_sub_no_promo2`, `ew_sub_n`) | the re-fold BETWEEN the two promotions -- the sibling-arena bug, which is this file's one structural defect. |
# | M10 | `ew_logical_not`: drop the `cast(bool)` | 1 (`ew_lnot_i`) | `self.cast(dtypes.bool).ne(True)`'s CAST. |
# | M11 | `ew_sub.of`: `O.OpsADD{}` -> `O.OpsSUB{}` | 3 | `sub` is an ADD over a negated rhs and NOT an `Ops.SUB`. |
# | M12 | a comment-only edit | 0 -- THE CONTROL | a mutation table with no row that CANNOT move is a table of coincidences. |
# | M13 | `ew_promote`: `Bool.and(W.dt_weak(dt), ew_is_const(fx, b))` -> `W.dt_weak(dt)` | 2 (`ew_dt_promo_nc`, `ew_op_promo_nc`) + the `ew_promo_nc` count 5->4 | `elementwise.py:31`'s SECOND conjunct, `t._uop.base.op is Ops.CONST`. This one was a REAL DEFECT, not a coverage hole: the port tested `t.dtype in dtypes.weaks` alone, and every other fixture in this file holds a weak CONST, so the conjunct was true wherever it was read and the gate could not see it. `weak_dtype(out_dtype)` is weak whenever `out_dtype` is strong, so the missing conjunct keeps a weakint ADD weakint against int32, and the root then adds weakint to int32 -- a promotion the lattice forbids. CPython: `Tensor(3)+Tensor(5)` is weakint with base op ADD, and after `+ Tensor(7, dtype=dtypes.i32)` its src0 is `int`/`Ops.CAST`. `g_promo_nonconst` is the first fixture in this file whose weak tensor is NOT a CONST. |
#
# M9 is the one to read twice. It moves exactly the two rows whose graph crosses a
# promotion that MINTS, and nothing else -- which is the point: a sibling-arena bug is
# invisible everywhere the two promotions happen to agree, and the whole signature
# surface of this file is blind to it except through `sub`.
# ===========================================================================