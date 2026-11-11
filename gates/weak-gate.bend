# gates/weak-gate.bend -- THE GATE DRIVER for `tinybendygrad/uop/weak.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/uop/weak.bend as P
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/mixin/dtype.bend as D

def strong_dtype(+d: S.Dt) -> S.Dt:
  P.strong_dtype.cls(S.Dt.cls(d), S.int32(), S.single(), d)

def commit_weak_consts(+fx: F.Folded, +self: U32, dt: Maybe<&1, S.Dt>) -> O.Found:
  +o = P.od_of(dt)
  P.commit_weak_consts.walked(P.ODt.some(o), o, fx, self, P.wk_srcs(fx, self))

# pm_lower_weak -- weak.py:67-78. FOUR rules in Python; NONE here. All four read
# `commit_dtype`: three directly, and the fourth through `max_numel` ->
# `to_max_shape` -> `x.vmax`, which is the same fold.
# a gated long index into a small buffer narrows; its out-of-gate value is discarded
# two stacked weak casts are two kind conversions: each resolves at its own kind's default
# TODO(p3) weak.py:69  pm_lower_weak rule 0 -- INDEX/SHRINK gated long index -- `buf.max_numel()` is
#   `prod(to_max_shape(shape))` and `to_max_shape` (ops.py:1886) is `int(x.vmax)`.
# TODO(p3) weak.py:73  pm_lower_weak rule 1 -- two stacked weak casts -- `commit_dtype` twice.
# TODO(p3) weak.py:75  pm_lower_weak rule 2 -- PARAM/BUFFER/ALLOC weakint -- `u.commit_dtype(dtypes.i32)`.
# TODO(p3) weak.py:77 lower_weak_node             -- see the TODO on that def.
def wk_lower_table() -> O.PMEntrys:
  O.PMEntrys{Nil{}}

# pm_cast_const -- weak.py:98. ONE rule in Python; NONE here.
# TODO(p3) weak.py:98 cast_consts -- `UOp.cconst(s.val, s.commit_dtype(dtypes.i32))`.
def wk_cast_table() -> O.PMEntrys:
  O.PMEntrys{Nil{}}

def pm_commit_weak(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  P.pm_go(P.wk_ready(fx, self),
    P.wk_scan(P.wk_commit_table(), True{}, fx, self, O.PMEntrys.es(P.wk_commit_table()), None{}))

def pm_uncast_const(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  P.pm_go(P.wk_ready(fx, self),
    P.wk_scan(P.wk_uncast_table(), False{}, fx, self, O.PMEntrys.es(P.wk_uncast_table()), None{}))


# --- THE GATE ROWS ----------------------------------------------------
# ===========================================================================
# THE GATE. One row per claim, and every claim is DERIVED FROM PYTHON: the values are in
# `.agents/slop/notes/weak_oracle.txt`, produced by running weak.py's own defs against real
# tinygrad, so a row here can be WRONG rather than merely restating this code. The COUNT
# rows pin each table's length against weak.py's, which is how the `_min_max` shortfall
# becomes machine-visible instead of a silent under-rewrite.
#
# WHAT this gate cannot see, stated rather than left to be discovered. FIRST-WINS: the two
# ported `pm_commit_weak` entries claim DISJOINT op sets -- Broadcastable and STORE -- so no
# node here is claimed twice and a first-wins-vs-conjunction bug in `wk_keep` moves NOTHING;
# `disjoint` says so out loud. And the four `_min_max` defs and the five rules behind them:
# no row can see them, and the `*_total` rows print False ON PURPOSE.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b), "\n"]))

def cnt(nm: String, n: Nat) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(U32.from_nat(n)), "\n"]))

# The twenty dtypes in dtype.py's own order, so `weak_count` is a claim about ALL of
# them and not about the three the other rows happen to name.
def ALL_DTS() -> List<&2, S.Dt>:
  [S.void(), S.weakint(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(),
   S.int32(), S.uint32(), S.int64(), S.uint64(), S.weakfloat(), S.fp8e4m3(),
   S.fp8e4m3fnuz(), S.fp8e5m2(), S.fp8e5m2fnuz(), S.half(), S.bfloat16(),
   S.single(), S.double()]

# Base has `Bool.to_u32` and no `Bool.to_nat`, and `Nat` is not a U32 (rule 9), so a
# COUNT over a `Bool` needs this.
def nat_of(b: Bool) -> Nat:
  match b:
    case True{}: 1n
    case False{}: 0n

def weak_count.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case d <> t: weak_count.go(t, (Nat.add(n, nat_of(P.dt_weak(d))) : Nat))

def weak_count() -> Nat:
  weak_count.go(ALL_DTS(), 0n)

def sealed_count.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case d <> t: sealed_count.go(t, (Nat.add(n, nat_of(P.wk_sealed(d))) : Nat))


def sealed_count() -> Nat:
  sealed_count.go(ALL_DTS(), 0n)

# ===========================================================================
# THE FIXTURES. ONE arena, built by ONE recipe, so no index is written down twice.
#
# Every node is one tinygrad would build. `CAST(CONST(weakfloat), half)` is exactly Python's
# `UOp.const(v, dtypes.f16)`: ops.py:638 is `UOp(Ops.CONST, arg=dtype.const(b), src=())
# .cast(dtype)`, and ops.bend spells the bare CONST and the CAST as two nodes. A raw `OpsADD`
# over two bare weakint CONSTs is the weak NON-CONST node that makes `commit_weak_srcs`
# actually rewrite; with weak CONST srcs on both sides the `bare and CONST` arm rebuilds each
# src and the whole rule is the identity (the oracle's rows A-C say so).
#
#   A  node `a`  MUL(ADD(weakint), CAST(weakfloat, half))  -- `commit_weak_srcs` rewrites it
#   B  node `b`  STORE(CAST(weakfloat, half), CONST(weakfloat)) -- the rule makes src[1] half
#   C  node `c`  ADD(MUL(half,half), CAST(weakfloat, half)) -- `uncast_const` drops the CAST,
#                                                               so src[1] becomes WEAK again
# ===========================================================================

type Fix is Data:
  Fix{fx: F.Folded, wl: U32, a: U32, c: U32, b: U32, bs: U32, cg: U32}

def Fix.fx(f: Fix) -> F.Folded:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: fx

def Fix.wl(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: wl

def Fix.a(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: a

def Fix.c(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: c

def Fix.b(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: b

def Fix.bs(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: bs

def Fix.cg(f: Fix) -> U32:
  match f:
    case Fix{fx, wl, a, c, b, bs, cg}: cg

def c_int(ar: O.Arena, k: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(k)})

def c_flt(ar: O.Arena, f: F32) -> O.Found:
  O.UOp.const(ar, O.CFloat{f})

# `UOp.const(v, dtypes.f16)`: the bare weakfloat CONST, then the CAST.
def cast_half(ar: O.Arena, +f: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(f), O.OpsCAST{}, [O.Found.i(f)], O.ADt{S.half()}, O.TNone{})

def g_fix() -> Fix:
  +c3 = c_int(O.Arena.empty(), 3)
  +c5 = c_int(O.Found.ar(c3), 5)
  # the weak NON-CONST node: ADD(CONST(3), CONST(5)), dtype weakint
  +wl = O.UOp.new(O.Found.ar(c5), O.OpsADD{}, [O.Found.i(c3), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +f1 = c_flt(O.Found.ar(wl), 1.0)
  +h1 = cast_half(O.Found.ar(f1), f1)
  # fixture A
  +a = O.UOp.new(O.Found.ar(h1), O.OpsMUL{}, [O.Found.i(wl), O.Found.i(h1)], O.ANone{}, O.TNone{})
  +f3 = c_flt(O.Found.ar(a), 3.0)
  +h3 = cast_half(O.Found.ar(f3), f3)
  # a half node that is neither a CONST nor a CAST
  +hn = O.UOp.new(O.Found.ar(h3), O.OpsMUL{}, [O.Found.i(h1), O.Found.i(h3)], O.ANone{}, O.TNone{})
  +f2 = c_flt(O.Found.ar(hn), 2.0)
  +h2 = cast_half(O.Found.ar(f2), f2)
  # fixture C
  +c = O.UOp.new(O.Found.ar(h2), O.OpsADD{}, [O.Found.i(hn), O.Found.i(h2)], O.ANone{}, O.TNone{})
  +f4 = c_flt(O.Found.ar(c), 4.0)
  # fixture B, at `single` and NOT at `half`: the rule commits src[1] with
  # `dt.const`, and at float16 that is `float_to_fp16`, the C-effect seam, so this file
  # REFUSES the rewrite. `store_sealed` below is the row that pins that refusal, and
  # the same STORE at `half` is fixture B'.
  +fs = O.UOp.new(O.Found.ar(f4), O.OpsCAST{}, [O.Found.i(f4)], O.ADt{S.single()}, O.TNone{})
  +b = O.UOp.new(O.Found.ar(fs), O.OpsSTORE{}, [O.Found.i(fs), O.Found.i(f4)], O.ANone{}, O.TNone{})
  # fixture B', the same STORE at `half`: Python rewrites it and this file does not
  +b2 = O.UOp.new(O.Found.ar(b), O.OpsSTORE{}, [O.Found.i(h1), O.Found.i(f4)], O.ANone{}, O.TNone{})
  # a CAST over a STRONG src. `cg`'s only src is `half`, so its meet is `half` and the
  # weak-meet guard cannot be what answers "no" on it -- only the
  # `GroupOp.broadcastable` guard can, which is what `dts_cast_none` pins.
  +cg = O.UOp.new(O.Found.ar(b2), O.OpsCAST{}, [O.Found.i(hn)], O.ADt{S.single()}, O.TNone{})
  Fix{F.folded(O.Found.ar(cg)), O.Found.i(wl), O.Found.i(a), O.Found.i(c), O.Found.i(b),
    O.Found.i(b2), O.Found.i(cg)}

# ===========================================================================
# THE ROWS.
# ===========================================================================

# --- the dtype claims ----------------------------------------------------
def t_strong_weakint() -> Bool: P.wk_eq_dt(strong_dtype(S.weakint()), S.int32())
def t_strong_weakfloat() -> Bool: P.wk_eq_dt(strong_dtype(S.weakfloat()), S.single())
def t_strong_half() -> Bool: P.wk_eq_dt(strong_dtype(S.half()), S.half())
def t_weak_half() -> Bool: P.wk_eq_dt(P.weak_dtype(S.half()), S.weakfloat())
def t_weak_int32() -> Bool: P.wk_eq_dt(P.weak_dtype(S.int32()), S.weakint())
def t_weak_bool() -> Bool: P.wk_eq_dt(P.weak_dtype(S.boolean()), S.boolean())
def t_weak_void() -> Bool: P.wk_eq_dt(P.weak_dtype(S.void()), S.void())

# `weak_count == 2` and `sealed_count == 6` are claims about ALL twenty dtypes: a
# `Cls` arm spelled with the wrong constructor, or a `wk_sealed` arm off by one
# priority, moves one of them and nothing else.
def t_weak_count() -> Bool: U32.is_eq(U32.from_nat(weak_count()), 2)
def t_sealed_count() -> Bool: U32.is_eq(U32.from_nat(sealed_count()), 6)
def t_sealed_half() -> Bool: P.wk_sealed(S.half())
def t_sealed_single() -> Bool: Bool.not(P.wk_sealed(S.single()))
def t_sealed_weakfloat() -> Bool: Bool.not(P.wk_sealed(S.weakfloat()))

def meet_is(a: S.Dt, b: S.Dt, want: S.Dt) -> Bool:
  P.wk_eq_dt(F.least_upper.of(a, b), want)

def t_meet_ww() -> Bool: meet_is(S.weakint(), S.weakfloat(), S.weakfloat())
def t_meet_wi() -> Bool: meet_is(S.weakint(), S.int32(), S.int32())
def t_meet_wh() -> Bool: meet_is(S.weakfloat(), S.half(), S.half())
def t_meet_hh() -> Bool: meet_is(S.half(), S.single(), S.single())

# `eq_const` -- ops.bend has `eq_op`, `eq_dt`, `eq_addr` and `eq_arg` and NOT this, and
# `O.Const` is a four-way tag whose every arm compares against a value, so the eight defs
# below are the shape and the only shape. It lives HERE because ops.bend is read-only to
# this port; when it moves there these eight go with it and nothing else changes.
def eq_const.flt(y: O.Const, +f: F32) -> Bool:
  match y:
    case O.CFloat{g}: F32.is_eq(f, g)
    case _: False{}

def eq_const.int(y: O.Const, +i: H.I64) -> Bool:
  match y:
    case O.CInt{g}: Cmp.is_eq(H.i64_cmp(i, g))
    case _: False{}

def eq_const.bool(y: O.Const, +b: Bool) -> Bool:
  match y:
    case O.CBool{g}: U32.is_eq(Bool.to_u32(b), Bool.to_u32(g))
    case _: False{}

def eq_const.inv(y: O.Const) -> Bool:
  match y:
    case O.CInvalid{}: True{}
    case _: False{}

def eq_const(x: O.Const, y: O.Const) -> Bool:
  match x:
    case O.CInvalid{}: eq_const.inv(y)
    case O.CBool{b}: eq_const.bool(y, b)
    case O.CInt{i}: eq_const.int(y, i)
    case O.CFloat{f}: eq_const.flt(y, f)

# `DType.const` at an int, at a bool, at a float and at Invalid, from dtype.py:84's
# four arms.
def t_const_int() -> Bool:
  eq_const(P.wk_const_of(P.wk_dt_const(S.int32(), O.CInt{H.i64_of_i32(7)})), O.CInt{H.i64_of_i32(7)})

def t_const_bool() -> Bool:
  eq_const(P.wk_const_of(P.wk_dt_const(S.boolean(), O.CInt{H.i64_of_i32(0)})), O.CBool{False{}})

def t_const_flt() -> Bool:
  eq_const(P.wk_const_of(P.wk_dt_const(S.single(), O.CInt{H.i64_of_i32(3)})), O.CFloat{3.0})

# `int(val)` truncates toward zero -- F32.trunc, which is `math.trunc`'s float twin.
def t_const_trunc() -> Bool:
  eq_const(P.wk_const_of(P.wk_dt_const(S.int32(), O.CFloat{2.75})), O.CInt{H.i64_of_i32(2)})

def t_const_invalid() -> Bool:
  eq_const(P.wk_const_of(P.wk_dt_const(S.int32(), O.CInvalid{})), O.CInvalid{})

def sealed_const_is_none.go(m: Maybe<&1, O.Const>, same: Bool) -> Bool:
  match m:
    case Some{c}: Bool.not(same) && eq_const(c, O.CInvalid{})
    case None{}: same

def sealed_const_is_none() -> Bool:
  sealed_const_is_none.go(P.wk_dt_const(S.half(), O.CFloat{1.0}), True{})

# `dt.const` at float16 is the C-effect seam, so it is `None` and not a wrong number.
def t_const_sealed() -> Bool:
  sealed_const_is_none()

def t_ready_all.go(+f: Fix, ns: List<&2, Nat>, acc: Bool) -> Bool:
  match ns:
    case Nil{}: acc
    case n <> t: t_ready_all.go(f, t, Bool.and(acc, P.wk_ready(Fix.fx(f), U32.from_nat(n))))


# --- the fold claims -----------------------------------------------------
def t_ready_all(+f: Fix) -> Bool:
  t_ready_all.go(f, List.range(U32.to_nat(O.Arena.next(F.Folded.ar(Fix.fx(f))))), True{})

def t_meet_a_half(+f: Fix) -> Bool:
  P.wk_eq_dt(P.wk_meet(Fix.fx(f), P.wk_srcs(Fix.fx(f), Fix.a(f))), S.half())

def t_dts_a.pick(+d: P.Dts) -> Bool:
  Bool.and(Bool.and(P.Dts.some(d), P.wk_eq_dt(P.Dts.meet(d), S.half())), P.wk_eq_dt(P.Dts.result(d), S.half()))


def t_dts_a(+f: Fix) -> Bool: t_dts_a.pick(P.derived_dtypes(Fix.fx(f), Fix.a(f), P.wk_srcs(Fix.fx(f), Fix.a(f))))

def t_dts_weak_none.pick(d: P.Dts) -> Bool:
  Bool.not(P.Dts.some(d))


# an all-weakint ADD: the op IS Broadcastable, but the meet is weak, so None.
def t_dts_weak_none(+f: Fix) -> Bool:
  t_dts_weak_none.pick(P.derived_dtypes(Fix.fx(f), Fix.wl(f), P.wk_srcs(Fix.fx(f), Fix.wl(f))))

# Fix.a(f) STORE is not Broadcastable, so `derived_dtypes` is None whatever its srcs are.
def t_dts_store_none(+f: Fix) -> Bool:
  t_dts_weak_none.pick(P.derived_dtypes(Fix.fx(f), Fix.b(f), P.wk_srcs(Fix.fx(f), Fix.b(f))))

def t_hypo_weak.pick(d: P.Dts) -> Bool:
  Bool.not(P.Dts.some(d))


# THE HYPOTHETICAL READ. `derived_dtypes` on `Fix.a(f)` with the src list `[wl, wl]` instead
# of `[wl, CAST(weakfloat, half)]`: the meet must become WEAKINT, because that is the whole
# point of asking `dtype_from_uop` about a src list the arena does not contain. If `wk_derived`
# quietly read `u.src` instead of the list it was handed, this row would still say `half` and
# would be False.
def hypo_srcs(+f: Fix) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [Fix.wl(f)], [Fix.wl(f)]), Nil{})

def t_hypo_weak(+f: Fix) -> Bool:
  t_hypo_weak.pick(P.derived_dtypes(Fix.fx(f), Fix.a(f), hypo_srcs(g_fix())))

# --- the REWRITE claims --------------------------------------------------
# `refold(f)`: a rule that fires has GROWN the arena, so the fold the fixture carries is
# stale and the row re-folds the answer's own arena. Reading node `i` of THAT fold is what
# makes these rows about the rewrite and not about the fixture.
def refold(f: O.Found) -> F.Folded:
  F.folded(O.Found.ar(f))

# After `P.commit_weak_srcs(a)` BOTH srcs are half: node 2's weakint became
# `CAST(ADD, half)` and the CAST over the weakfloat const became `CAST(..., half)`.
def t_commit_a.dts(+fx: F.Folded, i: U32) -> Bool:
  P.wk_eq_dt(P.wk_meet(fx, P.wk_srcs(fx, i)), S.half())


def t_commit_a.pick(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{+g}: t_commit_a.dts(refold(g), O.Found.i(g))
    case None{}: False{}


def t_commit_a(+f: Fix) -> Bool: t_commit_a.pick(pm_commit_weak(Fix.fx(f), Fix.a(f)))

def t_commit_a_new.pick(m: Maybe<&2, O.Found>, was: U32) -> Bool:
  match m:
    case Some{+g}: Bool.not(U32.is_eq(O.Found.i(g), was))
    case None{}: False{}


def t_commit_a_new(+f: Fix) -> Bool:
  t_commit_a_new.pick(pm_commit_weak(Fix.fx(f), Fix.a(f)), Fix.a(f))

def t_store_b.dt(+fx: F.Folded, i: U32) -> Bool:
  P.wk_eq_dt(P.wk_dt(fx, P.wk_src1(fx, i)), S.single())


def t_store_b.pick(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{+g}: t_store_b.dt(refold(g), O.Found.i(g))
    case None{}: False{}


# fixture B: the STORE rule commits src[1] at src[0]'s dtype.
def t_store_b(+f: Fix) -> Bool: t_store_b.pick(pm_commit_weak(Fix.fx(f), Fix.b(f)))

def t_uncast_c.dt(+fx: F.Folded, i: U32) -> Bool:
  P.wk_eq_dt(P.wk_dt(fx, P.wk_src1(fx, i)), S.weakfloat())


def t_uncast_c.pick(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{+g}: t_uncast_c.dt(refold(g), O.Found.i(g))
    case None{}: False{}


# fixture C: `uncast_const` DROPS the CAST, so src[1] becomes WEAK again -- the point
# of the rule. A row asserting `half` here would pass on the PRE-rewrite arena, which
# is exactly why it is written `weakfloat`.
def t_uncast_c(+f: Fix) -> Bool: t_uncast_c.pick(pm_uncast_const(Fix.fx(f), Fix.c(f)))

def t_uncast_c_new(+f: Fix) -> Bool:
  t_commit_a_new.pick(pm_uncast_const(Fix.fx(f), Fix.c(f)), Fix.c(f))

def t_commit_wl_none.go(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}


# `commit_weak_srcs` on the all-weakint ADD is Python's None: the meet is weak.
def t_commit_wl_none(+f: Fix) -> Bool:
  t_commit_wl_none.go(P.commit_weak_srcs(Fix.fx(f), Fix.wl(f)))

# `commit_weak_consts` has no caller in this port (`cast_consts` is behind `_min_max`), so
# without these two rows it would be entirely ungated. The first is the IDENTITY arm -- Bend
# is strict, so it is also the row that notices if the walk runs when `dt` is `None` and grows
# an arena Python never grows. The second is the real one: fixture B's src[1] IS a weak CONST,
# so the rule commits it at `single`.
def t_cwc_none_nodes(+f: Fix) -> Bool:
  U32.is_eq(O.Found.i(commit_weak_consts(Fix.fx(f), Fix.b(f), None{})), Fix.b(f))

def t_cwc_b_single.dt(+fx: F.Folded, i: U32) -> Bool:
  P.wk_eq_dt(P.wk_dt(fx, P.wk_src1(fx, i)), S.single())

def t_cwc_b_single(+f: Fix) -> Bool:
  t_cwc_b_single.dt(refold(commit_weak_consts(Fix.fx(f), Fix.b(f), Some{S.single()})),
    O.Found.i(commit_weak_consts(Fix.fx(f), Fix.b(f), Some{S.single()})))

# THE SEALED REFUSAL, which is a divergence and is therefore a row. The same STORE at
# `half` is fixture B': Python's rule rewrites it (`UOp.const(4.0, dtypes.f16)` ->
# `float_to_fp16`, dtype.bend's C-effect seam) and this file answers "no rewrite", because
# `wk_store_cast.bad` refuses rather than committing an unrounded CONST.
def t_store_sealed.go(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}

def t_store_sealed(+f: Fix) -> Bool:
  t_store_sealed.go(P.wk_store_cast(Fix.fx(f), Fix.bs(f)))

# and the same shape through the driver, so the refusal is not an artefact of calling
# the rule body directly
def t_store_sealed_pm(+f: Fix) -> Bool:
  t_store_sealed.go(pm_commit_weak(Fix.fx(f), Fix.bs(f)))

# `_lower_weak_ops` -- weak.py:45 -- and it is a COUNT over a list because a SET
# that gates a rewrite is invisible to a per-op boolean: a dropped op makes
# `lower_weak_node` SKIP a node and a spurious one makes it rewrite one, and both
# look like a rule that never fires. CPython's own `len` is the oracle, and the
# arithmetic is `GroupOp.binary` NINETEEN + `GroupOp.unary` SEVEN + FOUR named.
def op_count.go(os: List<&2, O.Op>, n: Nat) -> Nat:
  match os:
    case Nil{}: n
    case _ <> t: op_count.go(t, Nat.add(n, 1n))

def t_lower_n() -> Bool: U32.is_eq(U32.from_nat(op_count.go(P.LOWER_OPS(), 0n)), 30)

# THE THREE MEMBERSHIP CLAIMS a count cannot see, and they are the three ends of
# the set: a NAMED EXTRA is IN, a `GroupOp.Unary` member is IN, and a movement op
# -- which is in NEITHER group and not in the four -- is OUT.
def t_lower_in() -> Bool: O.op_in(P.LOWER_OPS(), O.OpsRANGE{})

def t_lower_unary() -> Bool: O.op_in(P.LOWER_OPS(), O.OpsEXP2{})

def t_lower_out() -> Bool: Bool.not(O.op_in(P.LOWER_OPS(), O.OpsEXPAND{}))

# --- the TABLE claims ----------------------------------------------------
def len_of(ts: O.PMEntrys) -> Nat:
  List.length(&2, O.PMEntry, O.PMEntrys.es(ts))

def cnt_is(ts: O.PMEntrys, want: Nat) -> Bool:
  U32.is_eq(U32.from_nat(len_of(ts)), U32.from_nat(want))

def rej_go.rej(rej: List<&2, O.Op>, n: Nat) -> Nat:
  match rej:
    case Nil{}: (Nat.add(n, 1n) : Nat)
    case _ <> _: n

def rej_go.one(+es: List<&2, O.PMEntry>, n: Nat) -> Nat:
  match es:
    case Nil{}: n
    case e <> t: rej_go.one(t, rej_go.rej(O.PMEntry.rej(e), n))

def rej_go(ts: O.PMEntrys) -> Nat:
  rej_go.one(O.PMEntrys.es(ts), 0n)

# every `rej` in both ported tables is empty, so `early_reject` decides nothing here. Stated
# as a COUNT because that is the claim.
def rej_all_empty() -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(rej_go(P.wk_commit_table())), U32.from_nat(len_of(P.wk_commit_table()))),
    U32.is_eq(U32.from_nat(rej_go(P.wk_uncast_table())), U32.from_nat(len_of(P.wk_uncast_table()))))

# THE first-WINS row, and it is about the TABLES and not about `P.OP_BC`: the two ported
# `pm_commit_weak` entries must claim DISJOINT op sets, or a node could be claimed twice and
# `wk_keep`'s first-wins would be untested here. Mutation 10 sets tag 1's op set to `P.OP_BC()`
# and this row is the one that moves.
def entry_at(ts: O.PMEntrys, k: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, O.PMEntrys.es(ts), k),
    O.PMEntry{0, Nil{}, Nil{}})

def overlap.go(os: List<&2, O.Op>, +bs: List<&2, O.Op>) -> Bool:
  match os:
    case Nil{}: False{}
    case o <> t: Bool.or(O.op_in(bs, o), overlap.go(t, bs))

def overlap(a: O.PMEntry, +b: O.PMEntry) -> Bool:
  overlap.go(O.PMEntry.ops(a), O.PMEntry.ops(b))

def disjoint() -> Bool:
  Bool.not(overlap(entry_at(P.wk_commit_table(), 0n), entry_at(P.wk_commit_table(), 1n)))

# The OP-SET GATE ITSELF, as a row. Mutation 4 deletes `pm_claimed` and moves NOTHING else,
# because for these fixtures the other rules happen to agree with the gate; this row is what
# notices the gate being gone.
def claimed_store_b(+f: Fix) -> Bool:
  O.pm_claimed(P.OP_BC(), F.Folded.ar(Fix.fx(f)), Fix.b(f))

# a CAST is not Broadcastable either, so `derived_dtypes` is None on it as well as on a
# STORE. Mutation 5 drops the `broadcastable` guard and BOTH of these rows move.
def t_dts_cast_none.go(d: P.Dts) -> Bool:
  Bool.not(P.Dts.some(d))

def t_dts_cast_none(+f: Fix) -> Bool:
  t_dts_cast_none.go(P.derived_dtypes(Fix.fx(f), Fix.cg(f), P.wk_srcs(Fix.fx(f), Fix.cg(f))))


# THE count rows that make the wall visible. `*_total` compares this file's table against
# weak.py's own rule count and therefore prints False for the three tables `_min_max` blocks.
# That is the point: a table with fewer entries than Python has is a silent under-rewrite, and
# these four rows are how it is not silent.

def main() -> IO(Unit):
  do IO<Unit>:
    # `g_fix()` builds eleven nodes and folds them; every fixture row takes it as a
    # parameter and `main` calls it per row. An `IO<Unit>` `do` block can only BIND an `IO`
    # (fold.bend:2068's `a : Unit <- row(...)`), and the fixture is pure, so threading it
    # through the block would mean an IO wrapper for no reason.
    row("strong_weakint", t_strong_weakint())
    row("strong_weakfloat", t_strong_weakfloat())
    row("strong_half", t_strong_half())
    row("weak_half", t_weak_half())
    row("weak_int32", t_weak_int32())
    row("weak_bool", t_weak_bool())
    row("weak_void", t_weak_void())
    row("weak_count", t_weak_count())
    cnt("weak_count_n", weak_count())
    row("sealed_count", t_sealed_count())
    cnt("sealed_count_n", sealed_count())
    row("sealed_half", t_sealed_half())
    row("sealed_single", t_sealed_single())
    row("sealed_weakfloat", t_sealed_weakfloat())
    row("const_int", t_const_int())
    row("const_bool", t_const_bool())
    row("const_flt", t_const_flt())
    row("const_trunc", t_const_trunc())
    row("const_invalid", t_const_invalid())
    row("const_sealed", t_const_sealed())
    row("meet_ww", t_meet_ww())
    row("meet_wi", t_meet_wi())
    row("meet_wh", t_meet_wh())
    row("meet_hh", t_meet_hh())
    row("ready_all", t_ready_all(g_fix()))
    row("meet_a_half", t_meet_a_half(g_fix()))
    row("dts_a", t_dts_a(g_fix()))
    row("dts_weak_none", t_dts_weak_none(g_fix()))
    row("dts_store_none", t_dts_store_none(g_fix()))
    row("hypo_weak", t_hypo_weak(g_fix()))
    row("commit_a", t_commit_a(g_fix()))
    row("commit_a_new", t_commit_a_new(g_fix()))
    row("commit_wl_none", t_commit_wl_none(g_fix()))
    row("cwc_none_nodes", t_cwc_none_nodes(g_fix()))
    row("cwc_b_single", t_cwc_b_single(g_fix()))
    row("store_b", t_store_b(g_fix()))
    row("store_sealed", t_store_sealed(g_fix()))
    row("store_sealed_pm", t_store_sealed_pm(g_fix()))
    row("uncast_c", t_uncast_c(g_fix()))
    row("uncast_c_new", t_uncast_c_new(g_fix()))
    cnt("commit_len", len_of(P.wk_commit_table()))
    cnt("lower_len", len_of(wk_lower_table()))
    cnt("uncast_len", len_of(P.wk_uncast_table()))
    cnt("cast_len", len_of(wk_cast_table()))
    row("commit_total", cnt_is(P.wk_commit_table(), 3n))
    row("lower_total", cnt_is(wk_lower_table(), 4n))
    row("uncast_total", cnt_is(P.wk_uncast_table(), 1n))
    row("cast_total", cnt_is(wk_cast_table(), 1n))
    row("rej_all_empty", rej_all_empty())
    row("dts_cast_none", t_dts_cast_none(g_fix()))
    row("claimed_store_b", claimed_store_b(g_fix()))
    row("disjoint", disjoint())
    row("lower_n", t_lower_n())
    row("lower_in", t_lower_in())
    row("lower_unary", t_lower_unary())
    row("lower_out", t_lower_out())

# ===========================================================================
# NOT PORTED, one line each, and the wall each one is behind. The Python line numbers are
# weak.py's, so this diffs against weak.py line for line and
# `rg "TODO(p3)" tinybendygrad/uop/weak.bend` is the work queue. Every one of them is behind
# THE one line that covers four: `UOp._min_max` (ops.py:1104-1158), read through
# `DTypeMixin.commit_dtype` (mixin/dtype.py:16), which is `commit_int(self._uop.vmin,
# self._uop.vmax)` on a weakint node, and `vmin`/`vmax` ARE `_min_max`. One more arm needs
# the binary-blob decoder: `_min_max`'s LOAD arm reads
# `memoryview(b.arg).cast(dtype).tolist()`.
#
# Each blocked def keeps tinygrad's own comment above it here, so the comment travels with
# the work item instead of being re-derived from the Python.
#
# a concrete CAST over a weak node states the width the value will live at. that width is a
#   floor, never a narrowing.
#   only within the kind: an int cast of a weakfloat node is a value conversion, not a
#   statement about the node's width.
#   every weak src commits at the one width: the node's own bounds and each src's, none of
#   them narrowed.
# consumers absorb the weak CAST off their srcs and default underivable consts;
#   dtype-producing ops settle here.
#   a weakfloat Unary (sin/exp2/...) must resolve before the transcendental decomposition.
# a weak CAST states a width, which the consumer restates. a weakint over a bool or float
#   is a conversion, it commits here.
#   a committed const, not a consumer.
#   WHERE's cond is bool, never part of the width unification.
#   resolve whole once every weak expression lowered: a Binary widens from its own bounds
#   too, derivable consts wait.
# commit every remaining bare const, keyed on the consumer: "bare" is a property of the edge.
#   a committed const's CONST is its value, not an edge.
#   `.cast` folds at the dtypes a bare CONST derives, so the width is forced. Invalid never
#   commits.
# ===========================================================================
# WHAT `commit_dtype` ACTUALLY IS, and it is the finding that makes this block
# CHEAPER than it was filed. mixin/dtype.py:16 is
#     commit_int(self._uop.vmin, self._uop.vmax, default_int) if self.dtype is
#     weakint else strong_dtype(self.dtype)
# so the ONLY thing behind these four defs and four rules is the PAIR `(vmin, vmax)`.
# `strong_dtype` is PORTED (`strong_dtype` above), `weak_dtype` is PORTED, the dtype
# lattice is PORTED (`F.promo_dtype`), and `commit_int` (dtype.py:171) is itself
# expressible -- a FOUR-rung ladder over `(default_int, int32, int64, uint64)`
# keeping the first `dt.min <= lo and hi <= dt.max`, with the fallback `int64` --
# but its `uint64` rung needs `2**64 - 1`, and that is the SAME window `fold.bend`
# measures for `_min_max`: a SIGN bit plus an unsigned 64-BIT magnitude, not a
# signed 64-bit word. `fold.bend`'s `Bnd`/`bnd_lim` is that pair and is landed.
# SO: `commit_int` is `Bnd`'s consumer, and the missing argument is `F`'s walk of
# `_min_max` -- ONE def, not four. That is the ordering this block wants stated.
# TODO(p3) weak.py:27 def cast_weak_srcs -- `P.weak_dtype(c.dtype)` is ported, and the
#   `least_upper_dtype` lattice is ported, but the `dt` it computes reads
#   `u.commit_dtype(dtypes.i32)` and `s.commit_dtype(dtypes.i32)`. P3 with `_min_max`.
#   It is `pm_commit_weak`'s THIRD rule (weak.py:40) and it is the one rule of that
#   table whose body is not in this file.
# TODO(p3) weak.py:48 def absorb_weak_src -- `s.commit_dtype(dtypes.i32)` on the
#   weakint-over-a-bool-or-float arm. P3 with `_min_max`.
# TODO(p3) weak.py:53 def lower_weak_node -- reads `commit_dtype` (line 57) and
#   `strong_dtype` (line 62, PORTED) and `dtype_from_uop` (line 63, PORTED as
#   `wk_dtype_at`). Only the `commit_dtype` is missing. It is `pm_lower_weak`'s FOURTH
#   rule (weak.py:77).
# TODO(p3) weak.py:92 def cast_consts -- `UOp.cconst(s.val, s.commit_dtype(dtypes.i32))`
#   and `s.is_invalid` (portable: `F.fold.base` + a `CInvalid` test). It is
#   `pm_cast_const`'s only rule (weak.py:98), which is why that table is EMPTY here.
# TODO(p3) weak.py:69 pm_lower_weak rule 0 -- `buf.max_numel()` is
#   `prod(to_max_shape(shape))` and `to_max_shape` (ops.py:1886) is `int(x.vmax)`.
#   P3 with `_min_max`. The rest of the rule (`idx.cast`, `idx.valid`, the
#   `UPat.var("gate").where(...)` pattern) is portable and is not the wall.
# TODO(p3) weak.py:73 pm_lower_weak rule 1 -- two `commit_dtype` reads.
# TODO(p3) weak.py:75 pm_lower_weak rule 2 -- one `commit_dtype` read.
# TODO(p3) weak.py:98 pm_cast_const -- the whole table; see `cast_consts`.
# ===========================================================================
# DIVERGENCES THAT ARE NOT TODOs, because they are reported refusals and a rule or a row
# already carries them.
#
#   * `DType.const` at float16 / bfloat16 / the four fp8s is `None`, so `commit_srcs_at` and
#     the STORE rule answer "no rewrite" there instead of committing an unrounded CONST.
#     Rows: `const_sealed`, `store_sealed`, `store_sealed_pm`. Python rewrites.
#   * `DType.const`'s int arm is `c_intN(x).value`, which RAISES on overflow in Python.
#     `wk_dt_const` is total. No row: a value a weak CONST can hold does not overflow a U32,
#     so the two agree everywhere the port is defined.
#   * `wk_eq_dt` is a LOCAL COPY of `O.eq_dt`, because ops.bend's is wrong for weakfloat.
#     When ops.bend is fixed this becomes `O.eq_dt`.

# ===========================================================================
# THE MUTATION TABLE. Twelve real edits to this file, each re-run, each "rows that moved"
# column MEASURED and not predicted. The three that move NOTHING are in the table because
# each is a statement about what this gate can and cannot see.
#
#  #   mutation                                              rows that moved
#  1   `weak_dtype.of`'s isfloat arm returns `dt`          weak_half
#  2   `wk_sealed` gains an arm for `S.Dt{14, 32, CFloat}`   sealed_count, sealed_count_n,
#      i.e. float32 becomes sealed                           sealed_single, const_flt,
#                                                           store_b, cwc_b_single
#  3a  `wk_keep.take`: a later SKIP returns `v` and so      commit_a, commit_a_new
#      ERASES an earlier hit
#  3b  `wk_keep` becomes true LAST-WINS                     NOTHING -- and this is the
#                                                           measurement the header
#                                                           claims: `disjoint` says
#                                                           the two ported entries
#                                                           claim disjoint op sets, so
#                                                           no node is claimed twice
#  3c  `wk_try`'s subset test `and` -> `or`                  NOTHING -- `rej_all_empty`
#      (mutation 3c of spec.bend's table, repeated here)     says every `rej` is empty
#  4   `wk_fire` drops `pm_claimed` and always fires        NOTHING, and this is a
#      the gate                                                  THEOREM, not a gap:
#                                                           `wk_keep` is FIRST-WINS,
#                                                           so a permissive gate
#                                                           changes the answer only
#                                                           when the intended rule
#                                                           would NOT have fired.
#                                                           `claimed_store_b` pins the
#                                                           predicate; what nothing
#                                                           here sees is its WIRING
#                                                           into `wk_fire`
#  5   `derived_dtypes` drops the `broadcastable` guard      dts_store_none, dts_cast_none
#  6   `commit_srcs_at.fin` interns the closing `replace`    commit_a
#      in the fold's ORIGINAL arena, not the grown one
#  7   `uncast_const.bad` drops the `dts.result != u.dtype`  NOTHING -- a real gap in
#      test (weak.py:86)                                       this fixture set: on
#                                                           fixture C the hypothetical
#                                                           result equals `u.dtype`
#                                                           either way
#  8   `wk_dt` defaults to `S.single()` instead of `S.void()`  NOTHING -- `wk_ready` gates
#                                                           it and `ready_all` says so
#  9   `wk_sealed`'s bfloat16 arm priority 13 -> 12         sealed_count, sealed_count_n
#      (so float16 matches twice and bfloat16 never)         -- and NOT sealed_half,
#                                                           which stays True: the float16
#                                                           arm is still there
#  10  `wk_commit_table` gives tag 1 the op set `P.OP_BC()`,   store_b, disjoint
#      so the two ported rules OVERLAP
# ===========================================================================
