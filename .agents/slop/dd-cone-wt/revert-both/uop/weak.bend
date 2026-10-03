# weak.bend -- tinygrad/uop/weak.py: the four `PatternMatcher` tables that commit
# weak dtypes at lowering boundaries. 5 of weak.py's 9 defs and 3 of its 8 rules.
#
# TWO DEPENDENCIES, measured. `dtype.bend` is unreachable to any importer (it prints a
# foreign-code notice for `Dt.bf16`, `Dt.fp16`, the `fp8_*` and the `i64_*`/`float_to_*`
# helpers), so `strong_dtype` and `weak_dtype` are spelled HERE, as `fold.bend` did for
# `least_upper_dtype`. `least_upper_dtype` is `F.promo_dtype`. `dtype_from_uop` over a
# chosen src list is NOT a wall: `F.dt_shape` is `dtype_from_uop` with its src half
# factored out as `List<Derived>`, and `Derived` is `Data`, so a fold rebuilds one per
# hypothetical src (`wk_derived`/`wk_dtype_at` below). Asking the fold about a node that
# does not exist would need a scratch arena and a second Kahn worklist per query.
#
# THE WALL is `UOp._min_max` (ops.py:1104-1158), which `commit_dtype` (mixin/dtype.py:16)
# reads for `vmin`/`vmax` on a weakint node. `fold.bend:2176-2184` records it as the
# biggest single piece left in that half of ops.py and names what is missing (`i64_mul`,
# `i64_div`, `i64_mod`; there is no F32 min/max). Every blocked def and rule below is
# behind it, and the gate prints a COUNT row per table so the shortfall is visible rather
# than a silent under-rewrite.
#
# THE SECOND WALL is `DType.const` (dtype.py:79-84) for float16, bfloat16 and the four
# fp8s, whose `truncate` entry is a C-effect seam. `wk_sealed` names those six dtypes and
# `wk_blocked` turns "this rule wants a sealed `dt.const`" into "no answer" -- which is
# `fold.bend`'s stated policy: the fold reports the absence and the caller decides.

import Base
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./ops.bend as O
import ./fold.bend as F

# `dtypes.weaks` (dtype.py:160) is `(weakint, weakfloat)`, the two members of `S.Cls`
# that are neither concrete-signed nor concrete-unsigned.

def weak_cls(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_weak(d: S.Dt) -> Bool:
  weak_cls(S.Dt.cls(d))

# strong_dtype -- dtype.py:169-170, `{weakint: default_int, weakfloat:
# default_float}.get(dtype, dtype)`. weak.py calls dtype.bend's version with no defaults,
# so they are `S.int32()`/`S.single()` here.
def strong_dtype.cls(cls: S.Cls, di: S.Dt, df: S.Dt, d: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakInt{}: di
    case S.CWeakFloat{}: df
    case _: d

def strong_dtype(+d: S.Dt) -> S.Dt:
  strong_dtype.cls(S.Dt.cls(d), S.int32(), S.single(), d)

# weak_dtype -- dtype.py:175-176, `weakfloat if is_float(dtype) else weakint if
# is_int(dtype) else dtype`. The predicate is load-bearing: `is_float`/`is_int` cover
# EVERY concrete width as well, so a concrete float really does become weakfloat.
def weak_dtype.int(dt: S.Dt, isint: Bool) -> S.Dt:
  match isint:
    case True{}: S.weakint()
    case False{}: dt

def weak_dtype.of(isfloat: Bool, isint: Bool, dt: S.Dt) -> S.Dt:
  match isfloat:
    case True{}: S.weakfloat()
    case False{}: weak_dtype.int(dt, isint)

# What is left after the two predicates is `void` and `bool`, and `bool` is neither.
def weak_dtype.cls(+cls: S.Cls, dt: S.Dt) -> S.Dt:
  weak_dtype.of(S.Cls.is_float(cls), S.Cls.is_int(cls), dt)

def weak_dtype(+d: S.Dt) -> S.Dt:
  weak_dtype.cls(S.Dt.cls(d), d)

# The four dtypes whose `truncate` entry is the C-effect seam, matched on the record
# so this is `promo_mask`'s "twenty short arms" style and no `nm` string is compared.
def wk_sealed(d: S.Dt) -> Bool:
  match d:
    case S.Dt{12, 16, S.CFloat{}, _}: True{}    # float16
    case S.Dt{13, 16, S.CFloat{}, _}: True{}    # bfloat16
    case S.Dt{10, 8, S.CFloat{}, _}: True{}     # fp8 e4m3, e4m3fnuz
    case S.Dt{11, 8, S.CFloat{}, _}: True{}     # fp8 e5m2, e5m2fnuz
    case _: False{}

# `wk_eq_dt` / `wk_eq_cls` -- A LOCAL COPY, BECAUSE ops.bend's IS WRONG FOR weakfloat.
# `ops.bend:1313 eq_cls.sel` has SIX arms and is missing `CWeakFloat`, so
# `eq_cls(CWeakFloat{}, CWeakFloat{})` is False (measured), which also makes two
# structurally identical `CAST(..., weakfloat)` nodes fail to hash-cons. ops.bend is
# READ-ONLY to this port, so this is a workaround: the one-line fix is a
# `case S.CWeakFloat{}` arm in `eq_cls.sel`, and then `wk_eq_dt` becomes `O.eq_dt`.

# The class as a NUMBER, so the comparison is one `U32.is_eq`. The seven values are the
# declaration order of `S.Cls`, and they are this file's own: `wk_eq_cls` is the only
# place a `Cls` is given a number.
def wk_eq_cls(c: S.Cls) -> U32:
  match c:
    case S.CVoid{}: 0
    case S.CWeakInt{}: 1
    case S.CBool{}: 2
    case S.CUint{}: 3
    case S.CSint{}: 4
    case S.CFloat{}: 5
    case _: 6

def wk_eq_dt.nm(ok: Bool, k: U32, +nm: String, +y: S.Dt) -> Bool:
  match y:
    case S.Dt{p2, b2, c2, n2}:
      Bool.and(ok, Bool.and(U32.is_eq(k, wk_eq_cls(c2)), String.eq(nm, n2)))

def wk_eq_dt.go(p: Bool, b: Bool, +x: S.Dt, +y: S.Dt) -> Bool:
  match x:
    case S.Dt{pri, bits, cls, nm}: wk_eq_dt.nm(Bool.and(p, b), wk_eq_cls(cls), nm, y)

# dtype.py's `DType.__eq__` is the dataclass tuple `(priority, bitsize, name, fmt)`
# and `fmt` is derivable from the class, so `(pri, bits, cls, nm)` is the same value.
def wk_eq_dt(+x: S.Dt, +y: S.Dt) -> Bool:
  wk_eq_dt.go(U32.is_eq(S.Dt.pri(x), S.Dt.pri(y)), U32.is_eq(S.Dt.bits(x), S.Dt.bits(y)), x, y)


# THE READERS. Every dtype read is a read of the FOLD, because a node's dtype is a
# derived property and `fold.bend` is the only well-founded way to answer it: Bend refuses
# the mutual recursion Python breaks with `recursive_property`. `wk_dt` answers `void` for
# a node the fold has not settled, which is dtype.bend's own "no dtype" and a LATTICE
# BOTTOM, so it poisons a `promo_mask` rather than reading as something else; `wk_ready`
# refuses such a node, so the default is never observable.

def wk_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

def wk_known.go(m: Maybe<&2, S.Dt>) -> Bool:
  match m:
    case Some{d}: True{}
    case None{}: False{}

def wk_known(+fx: F.Folded, i: U32) -> Bool:
  wk_known.go(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i))

def wk_srcs(fx: F.Folded, self: U32) -> List<&2, U32>:
  O.Arena.srcs(F.Folded.ar(fx), self)

def wk_src0(fx: F.Folded, self: U32) -> U32:
  O.Arena.src0(F.Folded.ar(fx), self)

def wk_src1(fx: F.Folded, self: U32) -> U32:
  O.Arena.src(F.Folded.ar(fx), self, 1)

def wk_op_is(fx: F.Folded, self: U32, want: O.Op) -> Bool:
  O.eq_op(O.Arena.op(F.Folded.ar(fx), self), want)

def wk_is_weak(fx: F.Folded, i: U32) -> Bool:
  dt_weak(wk_dt(fx, i))

def wk_is_weak_const(+fx: F.Folded, +i: U32) -> Bool:
  Bool.and(wk_op_is(fx, i, O.OpsCONST{}), wk_is_weak(fx, i))

# `[x.dtype for x in src]`
def wk_dt_list.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ss:
    case Nil{}: acc
    case s <> t: wk_dt_list.go(fx, t, List.append(&2, S.Dt, acc, [wk_dt(fx, s)]))

def wk_dt_list(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, S.Dt>:
  wk_dt_list.go(fx, ss, Nil{})

# promo_dtype -- ops.py:120, which `fold.bend:173` already hoisted.
def wk_meet(+fx: F.Folded, ss: List<&2, U32>) -> S.Dt:
  F.promo_dtype(wk_dt_list(fx, ss))

# `any(...)` over the srcs, as a fold with the answer THREADED, so the walk stays one
# self-call: a `None` returned from the middle of a self-call would need a def that
# returns to the self-call, and that is mutual recursion, which Bend refuses
# (fold.bend's `Kahn.gather` note).
def wk_any_weak.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_any_weak.go(fx, t, Bool.or(acc, wk_is_weak(fx, s)))

def wk_any_weak(+fx: F.Folded, ss: List<&2, U32>) -> Bool:
  wk_any_weak.go(fx, ss, False{})

def wk_any_weak_const.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_any_weak_const.go(fx, t, Bool.or(acc, wk_is_weak_const(fx, s)))

def wk_any_weak_const(+fx: F.Folded, ss: List<&2, U32>) -> Bool:
  wk_any_weak_const.go(fx, ss, False{})

# `wk_ready`: "the fold has answered this node and every src a rule would read". One
# place, called by the driver, so no individual rule repeats the check and the `void`
# default is never observable.
def wk_ready.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_ready.go(fx, t, Bool.and(acc, wk_known(fx, s)))

def wk_ready(+fx: F.Folded, +self: U32) -> Bool:
  wk_ready.go(fx, wk_srcs(fx, self), wk_known(fx, self))

# `dtype_from_uop` OVER A CHOSEN src LIST. `F.fold.shape`/`device`/`addr` answer
# `Maybe<&2, Maybe<&2, T>>`: the OUTER Maybe is "the fold did not answer this node" and
# the INNER one is Python's own `None` (`_shape` is `tuple|None`). `Derived` wants the
# inner one, so each pair is unwrapped once here.

def wk_shape_of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_dev_of(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_addr_of(m: Maybe<&2, Maybe<&2, S.Addr>>) -> Maybe<&2, S.Addr>:
  match m:
    case Some{s}: s
    case None{}: None{}

def wk_ended_of(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  Maybe.default(&2, List<&2, U32>, m, Nil{})

def wk_derived(+fx: F.Folded, +i: U32) -> F.Derived:
  F.Derived{wk_dt(fx, i),
    wk_shape_of(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), i)),
    wk_dev_of(F.fold.device(F.Folded.ar(fx), F.Folded.t(fx), i)),
    wk_addr_of(F.fold.addr(F.Folded.ar(fx), F.Folded.t(fx), i)),
    Maybe.default(&1, U32, F.fold.base(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
    wk_ended_of(F.fold.ended(F.Folded.ar(fx), F.Folded.t(fx), i))}

def wk_deriveds.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, F.Derived>) -> List<&2, F.Derived>:
  match ss:
    case Nil{}: acc
    case s <> t: wk_deriveds.go(fx, t, List.append(&2, F.Derived, acc, [wk_derived(fx, s)]))

def wk_deriveds(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, F.Derived>:
  wk_deriveds.go(fx, ss, Nil{})

def wk_dtshape_dt(m: Maybe<&2, F.DtShape>) -> Maybe<&2, S.Dt>:
  match m:
    case Some{F.DtShape{dt, shape}}: Some{dt}
    case None{}: None{}

# dtype_from_uop(u.op, src, u.arg) with the node's OWN op and arg and a src list of
# my choosing. `None` is Python's `raise RuntimeError`, which `dt_shape` reports the
# same way and which `derived_dtypes` turns into "not derived".
def wk_dtype_at(+fx: F.Folded, +self: U32, dss: List<&2, F.Derived>) -> Maybe<&2, S.Dt>:
  wk_dtshape_dt(F.dt_shape(F.Folded.ar(fx), self, O.Arena.op(F.Folded.ar(fx), self),
    O.Arena.arg(F.Folded.ar(fx), self), dss))

# `DType.const` -- dtype.py:79-84.
#
#   Invalid passes through; a float destination is
#   `truncate.get(self, float)(float(val))`, which is the IDENTITY for float32 / float64
#   / weakfloat and `float_to_fp16` / `float_to_bf16` / `fp8_to_float(float_to_fp8(x))`
#   for float16, bfloat16 and the four fp8s; a bool destination is `bool(val)`; an int
#   destination is `int(val)`.
#
# So those four C-effect dtypes are the whole of the wall and `wk_sealed` names them. The
# int arm is `c_intN(x).value`, which RAISES on overflow in Python; a U32 cannot see that
# difference for a value a weak CONST can hold, so `wk_dt_const` is total where Python is
# not, and that is the only reading this file makes.

# `(lo as f32) + (hi_signed as f32) * 2^32`: exact for every |v| <= 2^24 and monotone
# above it, which is what `float(val)` needs for a CONST.
def wk_i64_to_f32.sgn(neg: Bool, hi: U32) -> F32:
  match neg:
    case True{}: F32.sub(U32.to_f32(hi), 4294967296.0)
    case False{}: U32.to_f32(hi)

def wk_i64_to_f32(+x: H.I64) -> F32:
  F32.add(U32.to_f32(H.lo32(x)), F32.mul(wk_i64_to_f32.sgn(H.i64_is_neg(x), H.hi32(x)), 4294967296.0))

# `float(val)`: the identity `truncate.get(self, float)` for every unsealed float.
def wk_dt_const.fpure(v: O.Const) -> O.Const:
  match v:
    case O.CInvalid{}: O.CInvalid{}
    case O.CBool{b}: O.CFloat{U32.to_f32(Bool.to_u32(b))}
    case O.CInt{i}: O.CFloat{wk_i64_to_f32(i)}
    case O.CFloat{f}: O.CFloat{f}

def wk_dt_const.bool(v: O.Const) -> Maybe<&1, O.Const>:
  match v:
    case O.CInvalid{}: Some{O.CInvalid{}}
    case O.CBool{b}: Some{O.CBool{b}}
    case O.CInt{i}: Some{O.CBool{Bool.not(U32.is_zero(H.lo32(i)))}}
    case O.CFloat{f}: Some{O.CBool{Bool.not(U32.is_zero(F32.to_u32(f)))}}

def wk_dt_const.int(v: O.Const) -> Maybe<&1, O.Const>:
  match v:
    case O.CInvalid{}: Some{O.CInvalid{}}
    case O.CBool{b}: Some{O.CInt{H.i64_of_i32(Bool.to_u32(b))}}
    case O.CInt{i}: Some{O.CInt{i}}
    case O.CFloat{f}: Some{O.CInt{H.i64_of_i32(F32.to_u32(F32.trunc(f)))}}

# `ConstFloat(truncate...) if is_float else bool(val) if is_bool else int(val)`.
# The order is dtype.py's and it matters: `is_float` is tested first and bool is not a
# float, while `is_int` INCLUDES weakint so the int arm covers every concrete integer
# and `weakint` itself.
# a `match` may only scrutinise a PARAMETER or a binder, and the seal test is a call,
# so it arrives as the def's FIRST parameter.
def wk_dt_const.sealed_pick.go(sealed: Bool, v: O.Const) -> Maybe<&1, O.Const>:
  match sealed:
    case True{}: None{}
    case False{}: Some{wk_dt_const.fpure(v)}

def wk_dt_const.sealed_pick(dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  wk_dt_const.sealed_pick.go(wk_sealed(dt), v)

def wk_dt_const.cls(cls: S.Cls, dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  match cls:
    case S.CFloat{}: wk_dt_const.sealed_pick(dt, v)
    case S.CWeakFloat{}: Some{wk_dt_const.fpure(v)}
    case S.CBool{}: wk_dt_const.bool(v)
    case _: wk_dt_const.int(v)

def wk_dt_const(+dt: S.Dt, v: O.Const) -> Maybe<&1, O.Const>:
  wk_dt_const.cls(S.Dt.cls(dt), dt, v)

# `wk_blocked`: this rule wants a `dt.const` at a sealed dtype. `bare` is
# `derived_dtypes(...) is not None`; when it holds only a weak CONST src reaches
# `dt.const` (every other weak src goes through `cast`), and when it does not hold
# EVERY weak src does. That is `not bare or any weak CONST src`, which is the whole
# predicate.
def wk_blocked.of(sealed: Bool, bare: Bool, ss: List<&2, U32>, +fx: F.Folded) -> Bool:
  match sealed:
    case True{}: Bool.or(Bool.not(bare), wk_any_weak_const(fx, ss))
    case False{}: False{}

def wk_blocked(+fx: F.Folded, dt: S.Dt, bare: Bool, ss: List<&2, U32>) -> Bool:
  wk_blocked.of(wk_sealed(dt), bare, ss, fx)

# THE WALKS THAT GROW THE ARENA. `Walk` is a `Data` record because a rule may read the
# arena as often as it likes and each walk step needs the arena and the rebuilt src list
# together, the same reason fold.bend's `Sized` and spec.bend's `Pa` are records. Two
# fields, two accessors, three rules: that is the reuse, not a new abstraction.

type Walk is Data:
  Walk{ar: O.Arena, srcs: List<&2, U32>}

def Walk.ar(w: Walk) -> O.Arena:
  match w:
    case Walk{ar, srcs}: ar

def Walk.srcs(w: Walk) -> List<&2, U32>:
  match w:
    case Walk{ar, srcs}: srcs

def walk_seed(ar: O.Arena) -> Walk:
  Walk{ar, Nil{}}

def walk_step(w: Walk, +hit: O.Found) -> Walk:
  Walk{O.Found.ar(hit), List.append(&2, U32, Walk.srcs(w), [O.Found.i(hit)])}

def walk_keep(+w: Walk, s: U32) -> Walk:
  Walk{Walk.ar(w), List.append(&2, U32, Walk.srcs(w), [s])}

# THE NODE BUILDERS. `UOp.replace` IS the hash-consing constructor `UOp(op, src=..., **kwargs)`,
# so it is `UOp.new` here, and Python's `ret is u` is `UOp.make`'s interning handing back
# the same index -- which is why the identity check below is exactly Python's `is`.
def replace_in(+ar: O.Arena, +self: U32, +src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, self), src, O.Arena.arg(ar, self), O.Arena.tag(ar, self))

# TWO SPELLINGS, AND THE DIFFERENCE IS LOAD-BEARING. A walk that made nodes carries a GROWN
# arena, and the closing `replace` has to be interned in THAT arena or it names a `src` index
# the original arena does not have. Only `uncast_const` -- whose walk is pure, because
# dropping a CAST names `s.src[0]` and mints nothing -- may reach for the fold's own.
def wk_replace(+fx: F.Folded, +self: U32, +src: List<&2, U32>) -> O.Found:
  replace_in(F.Folded.ar(fx), self, src)

def replace_walk(+w: Walk, +fx: F.Folded, +self: U32) -> O.Found:
  replace_in(Walk.ar(w), self, Walk.srcs(w))

# A `Maybe` this file can answer, because `wk_blocked` has already refused the sealed
# case. The `None` arm is unreachable on every path that gets here and is the dead
# default `fold.bend:630` writes for the same reason.
def wk_const_of.pick(m: Maybe<&1, O.Const>) -> O.Const:
  match m:
    case Some{c}: c
    case None{}: O.CInvalid{}

def wk_const_of(m: Maybe<&1, O.Const>) -> O.Const:
  wk_const_of.pick(m)

# mixin/dtype.py:36 `cast`: `self if self.dtype == (dt := to_dtype(dtype)) else
# self._uop.alu(Ops.CAST, arg=dt)`. ops.bend:2020's `UOp.alu` takes no arg, so the
# CAST is spelled with `UOp.new` and the `ADt` arg.
def wk_cast_at.of(same: Bool, +fx: F.Folded, self: U32, +dt: S.Dt) -> O.Found:
  match same:
    case True{}: O.Found{F.Folded.ar(fx), self}
    case False{}: O.UOp.new(F.Folded.ar(fx), O.OpsCAST{}, [self], O.ADt{dt}, O.TNone{})

def wk_cast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  wk_cast_at.of(wk_eq_dt(wk_dt(fx, self), dt), fx, self, dt)

# ops.py:632-638 `UOp.const`: `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`
# -- the bare CONST the fold derives a dtype from, PLUS the CAST. ops.bend:2093 has
# the bare half; `.cast` folds away at exactly bool/weakint/weakfloat, so for those
# three Python has ONE node and this has two, which ops.bend:2080-2092 documents.
# Spelling the CAST unconditionally is what `UOp.const`'s own shape does.
def wk_const_at(+fx: F.Folded, +dt: S.Dt, cv: Maybe<&1, O.Const>) -> O.Found:
  wk_cast_at.of(False{}, fx, O.Found.i(O.UOp.const(F.Folded.ar(fx), wk_const_of(cv))), dt)

# ops.py:640 `ccast`: `UOp.const(self.val, dtype) if self.op is Ops.CONST else
# self.cast(dtype)` -- "cast, EXCEPT for CONST, in which case rebuild a new CONST".
def cconst_val(arg: O.Arg) -> Maybe<&1, O.Const>:
  match arg:
    case O.APy{v}: Some{v}
    case _: None{}

def wk_ccast.val(+fx: F.Folded, +self: U32) -> O.Const:
  wk_const_of(cconst_val(O.Arena.arg(F.Folded.ar(fx), self)))

def wk_ccast.of(isconst: Bool, +fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  match isconst:
    case True{}: wk_const_at(fx, dt, wk_dt_const(dt, wk_ccast.val(fx, self)))
    case False{}: wk_cast_at(fx, self, dt)

def wk_ccast(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  wk_ccast.of(O.eq_op(O.Arena.op(F.Folded.ar(fx), self), O.OpsCONST{}), fx, self, dt)

# THE PYTHON, in weak.py's order. Every rule body here is `(Folded, U32) ->
# Maybe<&2, Found>`: Python's `UOp -> UOp|None` arrives whole, as the arena the rewrite
# built AND the index it named. A rule GROWS the arena, so the fold the caller holds is
# stale the moment one fires; `wk_rewrite` re-folds ONCE, at the end, rather than each rule
# re-folding for itself.
#
# `(is there an answer, meet, result)` is a `Data` record and not a `Maybe`:
# `derived_dtypes`'s answer is read twice by `commit_srcs_at` (once for `bare`, once for
# the pair) and a `Maybe` is affine with no `+` spelling.

type Dts is Data:
  Dts{dts_some: Bool, meet: S.Dt, result: S.Dt}

def Dts.some(d: Dts) -> Bool:
  match d:
    case Dts{dts_some, meet, result}: dts_some

def Dts.meet(d: Dts) -> S.Dt:
  match d:
    case Dts{dts_some, meet, result}: meet

def Dts.result(d: Dts) -> S.Dt:
  match d:
    case Dts{dts_some, meet, result}: result

def derived_dtypes.hold(ok: Bool, meet: S.Dt, result: S.Dt) -> Dts:
  match ok:
    case True{}: Dts{True{}, meet, result}
    case False{}: Dts{False{}, S.void(), S.void()}

def derived_dtypes.put(ok: Bool, meet: S.Dt, result: Maybe<&2, S.Dt>) -> Dts:
  derived_dtypes.hold(ok, meet, Maybe.default(&2, S.Dt, result, S.void()))

# derived_dtypes -- weak.py:11-14.
#
#   if u.op not in GroupOp.Broadcastable or (meet:=promo_dtype(src)) in
#      dtypes.weaks or (result:=dtype_from_uop(u.op, src, u.arg)) in
#      dtypes.weaks: return None
#   return meet, result
#
# the concrete dtypes u commits its srcs at: the operands' meet and u's own derived dtype,
# None if either is weak.
# `GroupOp.Broadcastable` is `Binary | Ternary`, ops.bend:493 `GroupOp.broadcastable`.
# Both guards are `dtypes.weaks`; Python's `tuple[DType,DType]|None` is `Dts` with
# `dts_some`.
def derived_dtypes(+fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Dts:
  derived_dtypes.put(Bool.and(O.GroupOp.broadcastable(O.Arena.op(F.Folded.ar(fx), self)),
      Bool.not(dt_weak(wk_meet(fx, ss)))),
    wk_meet(fx, ss),
    wk_dtype_at(fx, self, wk_deriveds(fx, ss)))

# `UOp.const(dt.const(s.val))` -- the bare CONST with NO dtype, so no CAST on top.
def wk_bare_const(+fx: F.Folded, +s: U32, +dt: S.Dt) -> O.Found:
  O.UOp.const(F.Folded.ar(fx), wk_const_of(wk_dt_const(dt, wk_ccast.val(fx, s))))


# commit_srcs_at -- weak.py:16-20.
#
#   bare = derived_dtypes(u, u.src) is not None
#   src = tuple(s if s.dtype not in dtypes.weaks else
#               UOp.const(dt.const(s.val)) if bare and s.op is Ops.CONST else
#               s.ccast(dt) for s in u.src)
#   return None if (ret := u.replace(src=src)) is u else ret
#
# the root re-derives: a shift's dtype is its lhs's, so committing the lhs commits the
# node too. And the `bare and CONST` arm reads like a no-op because it very nearly IS one:
# `UOp.const(dt.const(s.val))` is `UOp.const` with NO dtype, so `dtype is None ->
# dtypes.from_py(val)` hands the src's own weak dtype BACK and the node hash-conses to `s`
# itself. It differs only when the weak src's VALUE changes class, and it rounds at the
# sealed dtypes, which `wk_blocked` refuses.

def commit_srcs_at.bare(isbare: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match isbare:
    case True{}: walk_step(w, wk_bare_const(fx, s, dt))
    case False{}: walk_step(w, wk_ccast(fx, s, dt))

def commit_srcs_at.weak(w: Walk, bare: Bool, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  commit_srcs_at.bare(Bool.and(bare, wk_is_weak_const(fx, s)), w, s, fx, dt)

def commit_srcs_at.pick(notweak: Bool, bare: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match notweak:
    case True{}: walk_keep(w, s)
    case False{}: commit_srcs_at.weak(w, bare, s, fx, dt)

def commit_srcs_at.on(w: Walk, bare: Bool, +fx: F.Folded, +s: U32, +dt: S.Dt) -> Walk:
  commit_srcs_at.pick(Bool.not(wk_is_weak(fx, s)), bare, w, s, fx, dt)


def commit_srcs_at.go(ss: List<&2, U32>, w: Walk, +fx: F.Folded, +dt: S.Dt, +bare: Bool) -> Walk:
  match ss:
    case Nil{}: w
    case s <> t: commit_srcs_at.go(t, commit_srcs_at.on(w, bare, fx, s, dt), fx, dt, bare)

# `None if (ret := u.replace(src=src)) is u else ret`
def commit_srcs_at.same(alike: Bool, w: Walk, hit: O.Found) -> Maybe<&2, O.Found>:
  match alike:
    case True{}: None{}
    case False{}: Some{hit}

def commit_srcs_at.fin(+w: Walk, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  commit_srcs_at.same(U32.is_eq(O.Found.i(replace_walk(w, fx, self)), self), w,
    replace_walk(w, fx, self))

def commit_srcs_at.gate(blocked: Bool, dts: Dts, +fx: F.Folded, +self: U32, +ss: List<&2, U32>, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match blocked:
    case True{}: None{}
    case False{}: commit_srcs_at.fin(commit_srcs_at.go(ss, walk_seed(F.Folded.ar(fx)), fx, dt, Dts.some(dts)), fx, self)


def commit_srcs_at.ans(+dts: Dts, +fx: F.Folded, +self: U32, +ss: List<&2, U32>, +dt: S.Dt) -> Maybe<&2, O.Found>:
  commit_srcs_at.gate(wk_blocked(fx, dt, Dts.some(dts), ss), dts, fx, self, ss, dt)

def commit_srcs_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  commit_srcs_at.ans(derived_dtypes(fx, self, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self), dt)

# ---------------------------------------------------------------------------
# commit_weak_srcs -- weak.py:22-24.
#
#   if not any(s.dtype in dtypes.weaks for s in u.src) or
#      (dt:=least_upper_dtype(*(s.dtype for s in u.src))) in dtypes.weaks: return None
#   return commit_srcs_at(u, dt)
#
# The meet is `promo_dtype(src)` verbatim (ops.py:120 is `least_upper_dtype` over the
# operand dtypes), so `wk_meet` is dtype.py:193 through `fold.bend`.
# ---------------------------------------------------------------------------

def commit_weak_srcs.bad(+fx: F.Folded, +ss: List<&2, U32>) -> Bool:
  Bool.or(Bool.not(wk_any_weak(fx, ss)), dt_weak(wk_meet(fx, ss)))

def commit_weak_srcs.ans(bad: Bool, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: commit_srcs_at(fx, self, wk_meet(fx, ss))

def commit_weak_srcs(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  commit_weak_srcs.ans(commit_weak_srcs.bad(fx, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self))

# ---------------------------------------------------------------------------
# uncast_const -- weak.py:80-87.
#
# drop the CAST off a committed const where the consumer re-derives it anyway, so
# bare-CONST rules keep matching. the drop must change nothing the consumer derives:
# neither the operands' meet nor the node's own dtype.
#
#   src = tuple(s.src[0] if s.op is Ops.CAST and s.dtype not in dtypes.weaks and
#               s.src[0].op is Ops.CONST and s.src[0].dtype in dtypes.weaks else s
#               for s in u.src)
#   if src == u.src or (dts:=derived_dtypes(u, src)) is None or
#      dts[0] != promo_dtype(u.src) or dts[1] is not u.dtype: return None
#   return u.replace(src=src)
#
# A PURE walk: dropping a CAST names `s.src[0]`, which is already in the arena, so no node
# is made and no accumulator is needed. And the predicate a weak CAST over a const is not
# a commit, it is still resolving -- so the drop is allowed.

def uncast_const.hit(+fx: F.Folded, +s: U32) -> Bool:
  Bool.and(Bool.and(wk_op_is(fx, s, O.OpsCAST{}), Bool.not(wk_is_weak(fx, s))),
    wk_is_weak_const(fx, wk_src0(fx, s)))

def uncast_const.put.go(hit: Bool, +fx: F.Folded, +s: U32) -> U32:
  match hit:
    case True{}: wk_src0(fx, s)
    case False{}: s

def uncast_const.put(+fx: F.Folded, +s: U32) -> U32:
  uncast_const.put.go(uncast_const.hit(fx, s), fx, s)

def uncast_const.walk.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: uncast_const.walk.go(fx, t, List.append(&2, U32, acc, [uncast_const.put(fx, s)]))

def uncast_const.walk(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, U32>:
  uncast_const.walk.go(fx, ss, Nil{})

def uncast_const.reach(bad: Bool) -> Bool:
  bad


def uncast_const.bad(+src: List<&2, U32>, +ss: List<&2, U32>, +dts: Dts, +fx: F.Folded, +self: U32) -> Bool:
  uncast_const.reach(Bool.or(Bool.or(H.u32_list_eq(src, ss), Bool.not(Dts.some(dts))),
    Bool.or(Bool.not(wk_eq_dt(Dts.meet(dts), wk_meet(fx, ss))), Bool.not(wk_eq_dt(Dts.result(dts), wk_dt(fx, self))))))

def uncast_const.ans(bad: Bool, +src: List<&2, U32>, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: Some{wk_replace(fx, self, src)}

def uncast_const(+src: List<&2, U32>, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Maybe<&2, O.Found>:
  uncast_const.ans(uncast_const.bad(src, ss, derived_dtypes(fx, self, src), fx, self), src, fx, self)

def uncast_const_fx(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  uncast_const(uncast_const.walk(fx, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self))

# commit_weak_consts -- weak.py:7-8. The FIRST def in weak.py, and the only one whose
# caller (`cast_consts`, weak.py:94) is behind `_min_max`, so it has no caller in this
# port. It is here because it is a def in the Python and it is fully portable; a dead def
# in a mechanical port is the file's shape, not a leftover.
#
#   return u if dt is None else u.replace(src=tuple(s.ccast(dt) if
#     s.op is Ops.CONST and s.dtype in dtypes.weaks else s for s in u.src))
#
# the decomps and float emulation commit bare consts at a dtype another src already states.
# `dt:DType|None` is read once PER SRC and a `Maybe` is affine with no `+` spelling, so it
# travels as an `ODt`: a `Bool` plus the value, the same move fold.bend's `Sized` and
# spec.bend's `Pa` make.

type ODt is Data:
  ODt{od_some: Bool, od_dt: S.Dt}

def ODt.some(d: ODt) -> Bool:
  match d:
    case ODt{od_some, od_dt}: od_some

def ODt.dt(d: ODt) -> S.Dt:
  match d:
    case ODt{od_some, od_dt}: od_dt

def od_of.pick(m: Maybe<&1, S.Dt>) -> ODt:
  match m:
    case Some{d}: ODt{True{}, d}
    case None{}: ODt{False{}, S.void()}

def od_of(m: Maybe<&1, S.Dt>) -> ODt:
  od_of.pick(m)

def commit_weak_consts.pick(isconst_weak: Bool, w: Walk, +s: U32, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match isconst_weak:
    case True{}: walk_step(w, wk_ccast(fx, s, dt))
    case False{}: walk_keep(w, s)


def commit_weak_consts.on(w: Walk, +fx: F.Folded, +s: U32, +dt: S.Dt) -> Walk:
  commit_weak_consts.pick(Bool.and(wk_op_is(fx, s, O.OpsCONST{}), wk_is_weak(fx, s)), w, s, fx, dt)

def commit_weak_consts.go(ss: List<&2, U32>, w: Walk, +fx: F.Folded, +dt: S.Dt) -> Walk:
  match ss:
    case Nil{}: w
    case s <> t: commit_weak_consts.go(t, commit_weak_consts.on(w, fx, s, dt), fx, dt)


# `u if dt is None else u.replace(src=...)`. The branch is on `dt is None` and the WALK
# IS INSIDE THE TRUE ARM, because Bend is STRICT: passing the walk as an argument would
# evaluate it on the identity arm too, grow the arena, and return the grown one here.
# `cwc_none_nodes` in the gate is the row that notices.
# Python returns a UOp on BOTH arms, and `u` is the node itself when `dt is None`, so
# the answer is `Found{ar, self}` there and the rewritten node otherwise. `Found` rather
# than a bare `Arena` because a caller that cannot see the new index cannot tell a
# rewrite from a no-op -- which is exactly what `cwc_b_single` needed.
def commit_weak_consts.walked(some: Bool, dt: ODt, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> O.Found:
  match some:
    case True{}: replace_walk(commit_weak_consts.go(ss, walk_seed(F.Folded.ar(fx)), fx, ODt.dt(dt)), fx, self)
    case False{}: O.Found{F.Folded.ar(fx), self}

def commit_weak_consts(+fx: F.Folded, +self: U32, dt: Maybe<&1, S.Dt>) -> O.Found:
  +o = od_of(dt)
  commit_weak_consts.walked(ODt.some(o), o, fx, self, wk_srcs(fx, self))

# ---------------------------------------------------------------------------
# THE pm_commit_weak RULE 1 LAMBDA -- weak.py:37-38, the one rule here with no def of its
# own in the file (Python spells it as a lambda over a UPat):
#
#   lambda u: u.replace(src=(u.src[0], u.src[1].ccast(u.src[0].dtype), *u.src[2:]))
#
# NOTE the pattern is `src=(UPat(), UPat(dtype=dtypes.weaks), ...)`, so the pattern
# REQUIRES the src to be weak; the body then commits it at src[0]'s dtype, and a weak
# CONST src that is already there is the no-op Python's own hash-consing produces. The
# pattern's first src is a bare `UPat`, so `early_reject` is empty.

def wk_store_cast.bad.of(sealed: Bool, isconst: Bool) -> Bool:
  Bool.and(sealed, isconst)

# `ccast` on src[1] reaches `dt.const` only when src[1] IS a CONST; otherwise it is
# `cast`, which `wk_blocked` does not gate. `dt` is src[0]'s dtype.
def wk_store_cast.bad(+fx: F.Folded, +self: U32) -> Bool:
  wk_store_cast.bad.of(wk_sealed(wk_dt(fx, wk_src0(fx, self))), wk_op_is(fx, wk_src1(fx, self), O.OpsCONST{}))

def wk_store_cast.srcs(+fx: F.Folded, +self: U32, +dt: S.Dt, mid: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [wk_src0(fx, self)], [mid]),
    O.Arena.src_from(F.Folded.ar(fx), self, 2))


def wk_store_cast.hit(bad: Bool, +hit: O.Found, +fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: Some{replace_in(O.Found.ar(hit), self, wk_store_cast.srcs(fx, self, dt, O.Found.i(hit)))}


# `(u.src[0], u.src[1].ccast(u.src[0].dtype), *u.src[2:])`, interned in the arena
# `wk_ccast` grew and not in the fold's own.
def wk_store_cast.ans(bad: Bool, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.hit(bad, wk_ccast(fx, wk_src1(fx, self), wk_dt(fx, wk_src0(fx, self))),
    fx, self, wk_dt(fx, wk_src0(fx, self)))

def wk_store_cast(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.ans(wk_store_cast.bad(fx, self), fx, self)

# THE TABLES. Tag N is weak.py's own index in `pm_<name>`'s list, so a GAP is a BLOCKED
# RULE and not a renumbering. `ops` is the set `pdict` keys on and `rej` is
# `early_reject`, which ops.py:1609 reads as `if not rej.issubset(ler): continue` -- a
# NECESSARY CONDITION, so an empty set always passes. All three ported rules have a bare
# `UPat()` as the pattern's FIRST src or no src pattern at all, so every `rej` here is
# empty and none of the three is ever decided by the subset test: `rej_all_empty` counts
# them, and the mutation table records what flipping the test does.

# GroupOp.Broadcastable == GroupOp.Binary | GroupOp.Ternary
# (tinygrad/uop/__init__.py:110).
def OP_BC() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{},
   O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

# pm_commit_weak -- weak.py:35-41. THREE rules in Python; TWO here. It rides every round
# that can mint a weak const, and must reach fixpoint before pm_lower_weak below defaults
# one.
#
# no CONST arm: a concrete CAST over a weak CONST is already committed, minted that way by
# UOp.const
def wk_commit_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, OP_BC(),        Nil{}},   # 36  commit_weak_srcs
    O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]}  # 38  the STORE lambda
# TODO(p3) weak.py:40 (UPat(Ops.CAST, src=(UPat(GroupOp.ALU, dtype=dtypes.weaks,
#   name="u"),), name="c"), cast_weak_srcs) -- `cast_weak_srcs` reads
#   `u.commit_dtype(dtypes.i32)` and `s.commit_dtype(dtypes.i32)`, which is
#   `commit_int(vmin, vmax)`, which is `UOp._min_max`. See the TODO on that def.

# pm_lower_weak -- weak.py:67-78. FOUR rules in Python; NONE here. All four read
# `commit_dtype`: three directly, and the fourth through `max_numel` ->
# `to_max_shape` -> `x.vmax`, which is the same fold.
# a gated long index into a small buffer narrows; its out-of-gate value is discarded
# two stacked weak casts are two kind conversions: each resolves at its own kind's default
# TODO(p3) weak.py:69 INDEX/SHRINK gated long index -- `buf.max_numel()` is
#   `prod(to_max_shape(shape))` and `to_max_shape` (ops.py:1886) is `int(x.vmax)`.
# TODO(p3) weak.py:73 two stacked weak casts       -- `commit_dtype` twice.
# TODO(p3) weak.py:75 PARAM/BUFFER/ALLOC weakint  -- `u.commit_dtype(dtypes.i32)`.
# TODO(p3) weak.py:77 lower_weak_node             -- see the TODO on that def.
def wk_lower_table() -> O.PMEntrys:
  O.PMEntrys{Nil{}}

# pm_uncast_const -- weak.py:89. ONE rule in Python; ONE here.
def wk_uncast_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, OP_BC(), Nil{}}]}   # 89

# pm_cast_const -- weak.py:98. ONE rule in Python; NONE here.
# TODO(p3) weak.py:98 cast_consts -- `UOp.cconst(s.val, s.commit_dtype(dtypes.i32))`.
def wk_cast_table() -> O.PMEntrys:
  O.PMEntrys{Nil{}}

# THE DRIVER. A rule answers `Maybe<&2, Found>`, and `Found` is ops.bend's arena-and-index
# record, so Python's `UOp -> UOp|None` arrives whole. The engine, not this file, re-folds:
# a rule that fires has grown the arena, so `graph_rewrite` owns the loop that rebuilds it.
#
# `spec.bend` writes six scans, one per table, because its `try` names a dispatch; here the
# only per-table difference is WHICH of the two already-written dispatches a tag goes to,
# and a `Bool` selects between them. The two dispatches and the tables stay separate.
#
# `wk_keep` is first-wins, the same shape as ops.bend:2860 `pm_keep`: a `Some` accumulator
# keeps what it holds and discards a later hit.

def wk_keep.take(acc: Maybe<&2, O.Found>, v: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match acc:
    case Some{f}: Some{f}
    case None{}: v

def wk_keep(acc: Maybe<&2, O.Found>, v: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  wk_keep.take(acc, v)

# pm_commit_weak's dispatch. Tag 2 is weak.py:40 and is the `# TODO(p3)` above.
def wk_commit_dispatch.go(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match tag:
    case 0: commit_weak_srcs(fx, self)
    case 1: wk_store_cast(fx, self)
    case _: None{}


def wk_commit_dispatch(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  wk_commit_dispatch.go(tag, fx, self)

# pm_uncast_const's dispatch.
def wk_uncast_dispatch.go(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match tag:
    case 0: uncast_const_fx(fx, self)
    case _: None{}


def wk_uncast_dispatch(tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  wk_uncast_dispatch.go(tag, fx, self)



def wk_pick(which: Bool, tag: U32, +fx: F.Folded, self: U32) -> Maybe<&2, O.Found>:
  match which:
    case True{}: wk_commit_dispatch(tag, fx, self)
    case False{}: wk_uncast_dispatch(tag, fx, self)

def wk_fire(ok: Bool, which: Bool, +fx: F.Folded, +self: U32, tag: U32) -> Maybe<&2, O.Found>:
  match ok:
    case True{}: wk_pick(which, tag, fx, self)
    case False{}: None{}

def wk_try(ts: O.PMEntrys, which: Bool, +fx: F.Folded, +self: U32, +e: O.PMEntry) -> Maybe<&2, O.Found>:
  wk_fire(Bool.and(O.pm_claimed(O.PMEntry.ops(e), F.Folded.ar(fx), self),
    O.pm_early(ts, F.Folded.ar(fx), self, O.PMEntry.rej(e))), which, fx, self, O.PMEntry.tag(e))

def wk_scan(+ts: O.PMEntrys, +which: Bool, +fx: F.Folded, +self: U32, todo: List<&2, O.PMEntry>,
  acc: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match todo:
    case Nil{}: acc
    case e <> t: wk_scan(ts, which, fx, self, t, wk_keep(acc, wk_try(ts, which, fx, self, e)))

# `pm_<name>.rewrite`. `wk_ready` is Python's `None` for a node the fold could not answer,
# and it is HERE rather than in each rule so no rule repeats the check.
def pm_go(ready: Bool, m: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match ready:
    case True{}: m
    case False{}: None{}

def pm_commit_weak(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  pm_go(wk_ready(fx, self),
    wk_scan(wk_commit_table(), True{}, fx, self, O.PMEntrys.es(wk_commit_table()), None{}))

def pm_uncast_const(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  pm_go(wk_ready(fx, self),
    wk_scan(wk_uncast_table(), False{}, fx, self, O.PMEntrys.es(wk_uncast_table()), None{}))

# ===========================================================================
# THE GATE. One row per claim, and every claim is DERIVED FROM PYTHON: the values are in
# `.agents/slop/notes/weak_oracle.txt`, produced by running weak.py's own defs against real
# tinygrad, so a row here can be WRONG rather than merely restating this code. The COUNT
# rows pin each table's length against weak.py's, which is how the `_min_max` shortfall
# becomes machine-visible instead of a silent under-rewrite.
#
# WHAT THIS GATE CANNOT SEE, stated rather than left to be discovered. FIRST-WINS: the two
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
    case d <> t: weak_count.go(t, (Nat.add(n, nat_of(dt_weak(d))) : Nat))

def weak_count() -> Nat:
  weak_count.go(ALL_DTS(), 0n)

def sealed_count.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case d <> t: sealed_count.go(t, (Nat.add(n, nat_of(wk_sealed(d))) : Nat))


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
def t_strong_weakint() -> Bool: wk_eq_dt(strong_dtype(S.weakint()), S.int32())
def t_strong_weakfloat() -> Bool: wk_eq_dt(strong_dtype(S.weakfloat()), S.single())
def t_strong_half() -> Bool: wk_eq_dt(strong_dtype(S.half()), S.half())
def t_weak_half() -> Bool: wk_eq_dt(weak_dtype(S.half()), S.weakfloat())
def t_weak_int32() -> Bool: wk_eq_dt(weak_dtype(S.int32()), S.weakint())
def t_weak_bool() -> Bool: wk_eq_dt(weak_dtype(S.boolean()), S.boolean())
def t_weak_void() -> Bool: wk_eq_dt(weak_dtype(S.void()), S.void())

# `weak_count == 2` and `sealed_count == 6` are claims about ALL twenty dtypes: a
# `Cls` arm spelled with the wrong constructor, or a `wk_sealed` arm off by one
# priority, moves one of them and nothing else.
def t_weak_count() -> Bool: U32.is_eq(U32.from_nat(weak_count()), 2)
def t_sealed_count() -> Bool: U32.is_eq(U32.from_nat(sealed_count()), 6)
def t_sealed_half() -> Bool: wk_sealed(S.half())
def t_sealed_single() -> Bool: Bool.not(wk_sealed(S.single()))
def t_sealed_weakfloat() -> Bool: Bool.not(wk_sealed(S.weakfloat()))

def meet_is(a: S.Dt, b: S.Dt, want: S.Dt) -> Bool:
  wk_eq_dt(F.least_upper.of(a, b), want)

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
  eq_const(wk_const_of(wk_dt_const(S.int32(), O.CInt{H.i64_of_i32(7)})), O.CInt{H.i64_of_i32(7)})

def t_const_bool() -> Bool:
  eq_const(wk_const_of(wk_dt_const(S.boolean(), O.CInt{H.i64_of_i32(0)})), O.CBool{False{}})

def t_const_flt() -> Bool:
  eq_const(wk_const_of(wk_dt_const(S.single(), O.CInt{H.i64_of_i32(3)})), O.CFloat{3.0})

# `int(val)` truncates toward zero -- F32.trunc, which is `math.trunc`'s float twin.
def t_const_trunc() -> Bool:
  eq_const(wk_const_of(wk_dt_const(S.int32(), O.CFloat{2.75})), O.CInt{H.i64_of_i32(2)})

def t_const_invalid() -> Bool:
  eq_const(wk_const_of(wk_dt_const(S.int32(), O.CInvalid{})), O.CInvalid{})

def sealed_const_is_none.go(m: Maybe<&1, O.Const>, same: Bool) -> Bool:
  match m:
    case Some{c}: Bool.not(same) && eq_const(c, O.CInvalid{})
    case None{}: same

def sealed_const_is_none() -> Bool:
  sealed_const_is_none.go(wk_dt_const(S.half(), O.CFloat{1.0}), True{})

# `dt.const` at float16 is the C-effect seam, so it is `None` and not a wrong number.
def t_const_sealed() -> Bool:
  sealed_const_is_none()

def t_ready_all.go(+f: Fix, ns: List<&2, Nat>, acc: Bool) -> Bool:
  match ns:
    case Nil{}: acc
    case n <> t: t_ready_all.go(f, t, Bool.and(acc, wk_ready(Fix.fx(f), U32.from_nat(n))))


# --- the fold claims -----------------------------------------------------
def t_ready_all(+f: Fix) -> Bool:
  t_ready_all.go(f, List.range(U32.to_nat(O.Arena.next(F.Folded.ar(Fix.fx(f))))), True{})

def t_meet_a_half(+f: Fix) -> Bool:
  wk_eq_dt(wk_meet(Fix.fx(f), wk_srcs(Fix.fx(f), Fix.a(f))), S.half())

def t_dts_a.pick(+d: Dts) -> Bool:
  Bool.and(Bool.and(Dts.some(d), wk_eq_dt(Dts.meet(d), S.half())), wk_eq_dt(Dts.result(d), S.half()))


def t_dts_a(+f: Fix) -> Bool: t_dts_a.pick(derived_dtypes(Fix.fx(f), Fix.a(f), wk_srcs(Fix.fx(f), Fix.a(f))))

def t_dts_weak_none.pick(d: Dts) -> Bool:
  Bool.not(Dts.some(d))


# an all-weakint ADD: the op IS Broadcastable, but the meet is weak, so None.
def t_dts_weak_none(+f: Fix) -> Bool:
  t_dts_weak_none.pick(derived_dtypes(Fix.fx(f), Fix.wl(f), wk_srcs(Fix.fx(f), Fix.wl(f))))

# Fix.a(f) STORE is not Broadcastable, so `derived_dtypes` is None whatever its srcs are.
def t_dts_store_none(+f: Fix) -> Bool:
  t_dts_weak_none.pick(derived_dtypes(Fix.fx(f), Fix.b(f), wk_srcs(Fix.fx(f), Fix.b(f))))

def t_hypo_weak.pick(d: Dts) -> Bool:
  Bool.not(Dts.some(d))


# THE HYPOTHETICAL READ. `derived_dtypes` on `Fix.a(f)` with the src list `[wl, wl]` instead
# of `[wl, CAST(weakfloat, half)]`: the meet must become WEAKINT, because that is the whole
# point of asking `dtype_from_uop` about a src list the arena does not contain. If `wk_derived`
# quietly read `u.src` instead of the list it was handed, this row would still say `half` and
# would be False.
def hypo_srcs(+f: Fix) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [Fix.wl(f)], [Fix.wl(f)]), Nil{})

def t_hypo_weak(+f: Fix) -> Bool:
  t_hypo_weak.pick(derived_dtypes(Fix.fx(f), Fix.a(f), hypo_srcs(g_fix())))

# --- the REWRITE claims --------------------------------------------------
# `refold(f)`: a rule that fires has GROWN the arena, so the fold the fixture carries is
# stale and the row re-folds the answer's own arena. Reading node `i` of THAT fold is what
# makes these rows about the rewrite and not about the fixture.
def refold(f: O.Found) -> F.Folded:
  F.folded(O.Found.ar(f))

# After `commit_weak_srcs(a)` BOTH srcs are half: node 2's weakint became
# `CAST(ADD, half)` and the CAST over the weakfloat const became `CAST(..., half)`.
def t_commit_a.dts(+fx: F.Folded, i: U32) -> Bool:
  wk_eq_dt(wk_meet(fx, wk_srcs(fx, i)), S.half())


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
  wk_eq_dt(wk_dt(fx, wk_src1(fx, i)), S.single())


def t_store_b.pick(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{+g}: t_store_b.dt(refold(g), O.Found.i(g))
    case None{}: False{}


# fixture B: the STORE rule commits src[1] at src[0]'s dtype.
def t_store_b(+f: Fix) -> Bool: t_store_b.pick(pm_commit_weak(Fix.fx(f), Fix.b(f)))

def t_uncast_c.dt(+fx: F.Folded, i: U32) -> Bool:
  wk_eq_dt(wk_dt(fx, wk_src1(fx, i)), S.weakfloat())


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
  t_commit_wl_none.go(commit_weak_srcs(Fix.fx(f), Fix.wl(f)))

# `commit_weak_consts` has no caller in this port (`cast_consts` is behind `_min_max`), so
# without these two rows it would be entirely ungated. The first is the IDENTITY arm -- Bend
# is strict, so it is also the row that notices if the walk runs when `dt` is `None` and grows
# an arena Python never grows. The second is the real one: fixture B's src[1] IS a weak CONST,
# so the rule commits it at `single`.
def t_cwc_none_nodes(+f: Fix) -> Bool:
  U32.is_eq(O.Found.i(commit_weak_consts(Fix.fx(f), Fix.b(f), None{})), Fix.b(f))

def t_cwc_b_single.dt(+fx: F.Folded, i: U32) -> Bool:
  wk_eq_dt(wk_dt(fx, wk_src1(fx, i)), S.single())

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
  t_store_sealed.go(wk_store_cast(Fix.fx(f), Fix.bs(f)))

# and the same shape through the driver, so the refusal is not an artefact of calling
# the rule body directly
def t_store_sealed_pm(+f: Fix) -> Bool:
  t_store_sealed.go(pm_commit_weak(Fix.fx(f), Fix.bs(f)))

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
  Bool.and(U32.is_eq(U32.from_nat(rej_go(wk_commit_table())), U32.from_nat(len_of(wk_commit_table()))),
    U32.is_eq(U32.from_nat(rej_go(wk_uncast_table())), U32.from_nat(len_of(wk_uncast_table()))))

# THE FIRST-WINS ROW, and it is about the TABLES and not about `OP_BC`: the two ported
# `pm_commit_weak` entries must claim DISJOINT op sets, or a node could be claimed twice and
# `wk_keep`'s first-wins would be untested here. Mutation 10 sets tag 1's op set to `OP_BC()`
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
  Bool.not(overlap(entry_at(wk_commit_table(), 0n), entry_at(wk_commit_table(), 1n)))

# The OP-SET GATE ITSELF, as a row. Mutation 4 deletes `pm_claimed` and moves NOTHING else,
# because for these fixtures the other rules happen to agree with the gate; this row is what
# notices the gate being gone.
def claimed_store_b(+f: Fix) -> Bool:
  O.pm_claimed(OP_BC(), F.Folded.ar(Fix.fx(f)), Fix.b(f))

# a CAST is not Broadcastable either, so `derived_dtypes` is None on it as well as on a
# STORE. Mutation 5 drops the `broadcastable` guard and BOTH of these rows move.
def t_dts_cast_none.go(d: Dts) -> Bool:
  Bool.not(Dts.some(d))

def t_dts_cast_none(+f: Fix) -> Bool:
  t_dts_cast_none.go(derived_dtypes(Fix.fx(f), Fix.cg(f), wk_srcs(Fix.fx(f), Fix.cg(f))))


# THE COUNT ROWS THAT MAKE THE WALL VISIBLE. `*_total` compares this file's table against
# weak.py's own rule count and therefore prints False for the three tables `_min_max` blocks.
# That is the point: a table with fewer entries than Python has is a silent under-rewrite, and
# these four rows are how it is not silent.

def main() -> IO(Unit):
  do IO<Unit>:
    # `g_fix()` builds eleven nodes and folds them; every fixture row takes it as a
    # parameter and `main` calls it per row. An `IO<Unit>` `do` block can only BIND an `IO`
    # (fold.bend:2087's `a : Unit <- row(...)`), and the fixture is pure, so threading it
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
    cnt("commit_len", len_of(wk_commit_table()))
    cnt("lower_len", len_of(wk_lower_table()))
    cnt("uncast_len", len_of(wk_uncast_table()))
    cnt("cast_len", len_of(wk_cast_table()))
    row("commit_total", cnt_is(wk_commit_table(), 3n))
    row("lower_total", cnt_is(wk_lower_table(), 4n))
    row("uncast_total", cnt_is(wk_uncast_table(), 1n))
    row("cast_total", cnt_is(wk_cast_table(), 1n))
    row("rej_all_empty", rej_all_empty())
    row("dts_cast_none", t_dts_cast_none(g_fix()))
    row("claimed_store_b", claimed_store_b(g_fix()))
    row("disjoint", disjoint())

# ===========================================================================
# NOT PORTED, one line each, and the wall each one is behind. The Python line numbers are
# weak.py's, so this diffs against weak.py line for line and
# `rg "TODO(p3)" tinybendygrad/uop/weak.bend` is the work queue. Every one of them is behind
# THE ONE LINE THAT COVERS FOUR: `UOp._min_max` (ops.py:1104-1158), read through
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
# TODO(p3) weak.py:27 def cast_weak_srcs -- `weak_dtype(c.dtype)` is ported, and the
#   `least_upper_dtype` lattice is ported, but the `dt` it computes reads
#   `u.commit_dtype(dtypes.i32)` and `s.commit_dtype(dtypes.i32)`. P3 with `_min_max`.
#   It is `pm_commit_weak`'s THIRD rule (weak.py:40) and it is the one rule of that
#   table whose body is not in this file.
# TODO(p3) weak.py:45 _lower_weak_ops -- the `GroupOp.Binary|GroupOp.Unary|{WHERE,
#   RANGE, STACK, SPECIAL}` set, a module constant, belongs with `lower_weak_node` and
#   is only read there. 30 op literals; no value without the def.
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
#  10  `wk_commit_table` gives tag 1 the op set `OP_BC()`,   store_b, disjoint
#      so the two ported rules OVERLAP
# ===========================================================================
