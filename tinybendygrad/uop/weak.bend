# `UOp._min_max` (ops.py:1104-1158) IS LANDED, and the reader that joins it to
# THE SECOND WALL is `DType.const` (tinygrad/dtype.py:79-84) for
# weak.bend -- tinygrad/uop/weak.py: the four `PatternMatcher` tables that commit
# `dtype.bend` is unreachable to any importer (it prints a foreign-code notice for
# `dtype_from_uop` over a chosen src list is NOT a wall: `F.dt_shape` is `dtype_from_uop`
# `DType.const` (tinygrad/dtype.py:79-84) is a wall for the fp8s, whose `truncate` entry

import Base
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./ops.bend as O
import ./fold.bend as F
import ./../mixin/dtype.bend as D

# `dtypes.weaks` (dtype.py:160) is `(weakint, weakfloat)`.

def weak_cls(c: S.Cls) -> Bool:
  match c:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_weak(d: S.Dt) -> Bool:
  weak_cls(S.Dt.cls(d))

# strong_dtype -- dtype.py:169-170. weak.py calls dtype.bend's version with no defaults,
# so they are `S.int32()`/`S.single()` here.
def strong_dtype.cls(cls: S.Cls, di: S.Dt, df: S.Dt, d: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakInt{}: di
    case S.CWeakFloat{}: df
    case _: d

# weak_dtype -- dtype.py:175-176. The predicate is load-bearing: `is_float`/`is_int` cover
# EVERY concrete width as well, so a concrete float really does become weakfloat.
def weak_dtype.int(dt: S.Dt, isint: Bool) -> S.Dt:
  match isint:
    case True{}: S.weakint()
    case False{}: dt

def weak_dtype.of(isfloat: Bool, isint: Bool, dt: S.Dt) -> S.Dt:
  match isfloat:
    case True{}: S.weakfloat()
    case False{}: weak_dtype.int(dt, isint)

def weak_dtype.cls(+cls: S.Cls, dt: S.Dt) -> S.Dt:
  weak_dtype.of(S.Cls.is_float(cls), S.Cls.is_int(cls), dt)

def weak_dtype(+d: S.Dt) -> S.Dt:
  weak_dtype.cls(S.Dt.cls(d), d)

# The four dtypes whose `truncate` entry is the C-effect seam, matched on the record so no
# `nm` string is compared.
def wk_sealed(d: S.Dt) -> Bool:
  match d:
    case S.Dt{12, 16, S.CFloat{}, _}: True{}    # float16
    case S.Dt{13, 16, S.CFloat{}, _}: True{}    # bfloat16
    case S.Dt{10, 8, S.CFloat{}, _}: True{}     # fp8 e4m3, e4m3fnuz
    case S.Dt{11, 8, S.CFloat{}, _}: True{}     # fp8 e5m2, e5m2fnuz
    case _: False{}

# `ops.bend:1895 symbol=eq_cls.sel` HAD SIX arms and was missing `CWeakFloat`, so
# The class as a NUMBER, so the comparison is one `U32.is_eq`. The seven values are the
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

# dtype.py's `DType.__eq__` is the dataclass tuple `(priority, bitsize, name, fmt)` and
# `fmt` is derivable from the class, so `(pri, bits, cls, nm)` is the same value.
def wk_eq_dt(+x: S.Dt, +y: S.Dt) -> Bool:
  wk_eq_dt.go(U32.is_eq(S.Dt.pri(x), S.Dt.pri(y)), U32.is_eq(S.Dt.bits(x), S.Dt.bits(y)), x, y)

# THE READERS. Every dtype read is a read of the FOLD, because a node's dtype is a

def wk_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

# MEASURED, the edge this file adds -- `weak.bend -> mixin/dtype.bend` -- closes NO cycle:
# `commit_dtype` (dtype.py:16) -- `commit_int(self._uop.vmin, self._uop.vmax, default_int)
def wk_bnd_i64.of(b: F.Bnd) -> Maybe<&1, H.I64>:
  match b:
    case F.BndInt{neg, mag}: Some{H.i64_neg(neg, mag)}
    case _: None{}

def wk_bnd_i64(m: Maybe<&2, F.Bnd>) -> Maybe<&1, H.I64>:
  match m:
    case Some{b}: wk_bnd_i64.of(b)
    case _: None{}

# `__float__` NEEDS THE OTHER HALF OF `Bnd`, which is `BndFlt{v}` rather than
def wk_bnd_f32.of(b: F.Bnd) -> Maybe<&1, F32>:
  match b:
    case F.BndFlt{v}: Some{v}
    case _: None{}

def wk_bnd_f32(m: Maybe<&2, F.Bnd>) -> Maybe<&1, F32>:
  match m:
    case Some{b}: wk_bnd_f32.of(b)
    case _: None{}

# `UOp._eval` -- tinygrad/uop/ops.py:521. THREE CHECKS, IN PYTHON'S ORDER:
def wk_same(lo: Maybe<&1, H.I64>, hi: Maybe<&1, H.I64>) -> Bool:
  match lo, hi:
    case Some{a}, Some{b}: O.eq_i64(a, b)
    case _, _: False{}

def wk_same_f(lo: Maybe<&1, F32>, hi: Maybe<&1, F32>) -> Bool:
  match lo, hi:
    case Some{a}, Some{b}: F32.is_eq(a, b)
    case _, _: False{}

# THE bounds are re-READ, NEVER held. A `Maybe` holding an I64 by value is LINEAR -- a
# MEASURED, because the rule is the opposite of the obvious reading of `+`: a def with a
def wk_eval_int(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, H.I64>:
  Bool.pick(Maybe<&1, H.I64>,
            Bool.and(D.dt_is_int(wk_dt(fx, i)),
                     wk_same(wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                             wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})

def wk_eval_float(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, F32>:
  Bool.pick(Maybe<&1, F32>,
            Bool.and(D.dt_is_float(wk_dt(fx, i)),
                     wk_same_f(wk_bnd_f32(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                               wk_bnd_f32(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_f32(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})

def wk_eval_bool(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, H.I64>:
  Bool.pick(Maybe<&1, H.I64>,
            Bool.and(D.dt_is_bool(wk_dt(fx, i)),
                     wk_same(wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
                             wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)))),
            wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
            None{})
# `UOp.is_virtual` -- ops.py:902. `self.device is None or self.dtype in dtypes.weaks`, which
# THE NESTED Maybe IS NOT A TYPO. `F.fold.device` answers `Maybe<Maybe<Dev>>` -- the outer is
def no_dev(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Bool:
  match m:
    case Some{s}:
      match s:
        case Some{d}: False{}
        case _: True{}
    case _: True{}

def wk_is_virtual(+fx: F.Folded, +i: U32) -> Bool:
  Bool.or(no_dev(F.fold.device(F.Folded.ar(fx), F.Folded.t(fx), i)),
          D.md_weak(wk_dt(fx, i)))

# `UOp.param` -- ops.py:1229, THE SHAPE-LESS ARM. It lives here rather than in `ops.bend`
# CPython's `param` is three arms; the other two want `prod(to_max_shape(shape))` plus a
def wk_param_noshape(+ar: O.Arena, slot: U32, +dt: S.Dt, vmm: Maybe<&2, O.PyRange>) -> Maybe<&1, O.Found>:
  Bool.pick(Maybe<&1, O.Found>, Bool.not(D.md_weak(dt)),            Some{O.UOp.new.param(ar, O.OpsPARAM{}, None{}, O.AParam{O.ParamArg{slot, dt, vmm, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})},            None{})

# `S.int32()` IS CPython'S `default_int=None` SET TO int32, which is what
# `absorb_weak_src` and `lower_weak_node` pass (`s.commit_dtype(dtypes.i32)`).
def wk_commit_dtype(+fx: F.Folded, +bt: F.BTable, +i: U32) -> Maybe<&1, S.Dt>:
  D.commit_dtype(wk_dt(fx, i),
    wk_bnd_i64(F.UOp.vmin(F.Folded.ar(fx), bt, i)),
    wk_bnd_i64(F.UOp.vmax(F.Folded.ar(fx), bt, i)), S.int32())

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

def wk_dt_list.go(+fx: F.Folded, ss: List<&2, U32>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ss:
    case Nil{}: acc
    case s <> t: wk_dt_list.go(fx, t, List.append(&2, S.Dt, acc, [wk_dt(fx, s)]))

def wk_dt_list(+fx: F.Folded, ss: List<&2, U32>) -> List<&2, S.Dt>:
  wk_dt_list.go(fx, ss, Nil{})

# AGAINST UPSTREAM's `promo_dtype` INSTEAD OF THE PORT's.
# promo_dtype -- ops.py:120, which the port hoisted into `fold.bend`.
def wk_meet(+fx: F.Folded, ss: List<&2, U32>) -> S.Dt:
  F.promo_dtype(wk_dt_list(fx, ss))

# `any(...)` over the srcs, as a fold with the answer THREADED, so the walk stays one
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
# place, called by the driver, so no individual rule repeats the check.
def wk_ready.go(+fx: F.Folded, ss: List<&2, U32>, acc: Bool) -> Bool:
  match ss:
    case Nil{}: acc
    case s <> t: wk_ready.go(fx, t, Bool.and(acc, wk_known(fx, s)))

def wk_ready(+fx: F.Folded, +self: U32) -> Bool:
  wk_ready.go(fx, wk_srcs(fx, self), wk_known(fx, self))

# `dtype_from_uop` OVER A CHOSEN src LIST. `F.fold.shape`/`device`/`addr` answer

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
    Maybe.default(&1, U32, F.fold.unbase(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
    Maybe.default(&1, U32, F.fold.sbase(F.Folded.ar(fx), F.Folded.t(fx), i), 0),
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

# dtype_from_uop(u.op, src, u.arg) with the node's OWN op and arg and a src list of my
def wk_dtype_at(+fx: F.Folded, +self: U32, dss: List<&2, F.Derived>) -> Maybe<&2, S.Dt>:
  wk_dtshape_dt(F.dt_shape(F.Folded.ar(fx), self, O.Arena.op(F.Folded.ar(fx), self),
    O.Arena.arg(F.Folded.ar(fx), self), dss))

# `DType.const` -- dtype.py:79-84. A float destination is `truncate.get(self, float)(float(val))`,
def wk_i64_to_f32.c0(lo: U32) -> F32: U32.to_f32(U32.and(lo, 16777215))

def wk_i64_to_f32.c1(hi: U32, lo: U32) -> F32:
# bits 24..47: the low 8 from `lo`'s top byte and the high 16 from `hi`'s bottom half.
  U32.to_f32(U32.or(U32.and(U32.shrn(lo, 24n), 255), U32.shln(U32.and(hi, 65535), 8n)))

def wk_i64_to_f32.c2(hi: U32) -> F32:
# bits 48..63: the top half of `hi`, 16 bits.
  U32.to_f32(U32.and(U32.shrn(hi, 16n), 65535))

def wk_i64_to_f32.hi(+hi: U32, +lo: U32) -> F32:
  F32.mul(F32.add(F32.mul(wk_i64_to_f32.c2(hi), 16777216.0), wk_i64_to_f32.c1(hi, lo)), 16777216.0)

def wk_i64_to_f32.sgn(neg: Bool, +v: F32) -> F32:
  Bool.pick(F32, neg, F32.neg(v), v)

def wk_i64_to_f32.put(neg: Bool, +hi: U32, +lo: U32) -> F32:
  wk_i64_to_f32.sgn(neg, F32.add(wk_i64_to_f32.hi(hi, lo), wk_i64_to_f32.c0(lo)))

def wk_i64_to_f32.go(+neg: Bool, +x: H.I64) -> F32:
  +m = H.i64_neg(neg, x)
  wk_i64_to_f32.put(neg, H.hi32(m), H.lo32(m))

def wk_i64_to_f32(+x: H.I64) -> F32:
  wk_i64_to_f32.go(H.i64_is_neg(x), x)

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
# a `match` may only scrutinise a PARAMETER or a binder, and the seal test is a call, so it
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
def wk_blocked.of(sealed: Bool, bare: Bool, ss: List<&2, U32>, +fx: F.Folded) -> Bool:
  match sealed:
    case True{}: Bool.or(Bool.not(bare), wk_any_weak_const(fx, ss))
    case False{}: False{}

def wk_blocked(+fx: F.Folded, dt: S.Dt, bare: Bool, ss: List<&2, U32>) -> Bool:
  wk_blocked.of(wk_sealed(dt), bare, ss, fx)

# THE walks that grow the arena. `Walk` is a `Data` record because a rule may read the

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

# THE NODE BUILDERS. `UOp.replace` IS the hash-consing constructor `UOp(op, src=..., kwargs)`,
def replace_in(+ar: O.Arena, +self: U32, +src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, self), src, O.Arena.arg(ar, self), O.Arena.tag(ar, self))

# TWO spellings, AND the difference is LOAD-BEARING. A walk that made nodes carries a GROWN
def wk_replace(+fx: F.Folded, +self: U32, +src: List<&2, U32>) -> O.Found:
  replace_in(F.Folded.ar(fx), self, src)

def replace_walk(+w: Walk, +fx: F.Folded, +self: U32) -> O.Found:
  replace_in(Walk.ar(w), self, Walk.srcs(w))

# A `Maybe` this file can answer, because `wk_blocked` has already refused the sealed
# case. The `None` arm is unreachable on every path that gets here.
def wk_const_of.pick(m: Maybe<&1, O.Const>) -> O.Const:
  match m:
    case Some{c}: c
    case None{}: O.CInvalid{}

def wk_const_of(m: Maybe<&1, O.Const>) -> O.Const:
  wk_const_of.pick(m)

# mixin/dtype.py:36 `cast`: `self if self.dtype == (dt := to_dtype(dtype)) else
def wk_cast_at.of(same: Bool, +fx: F.Folded, self: U32, +dt: S.Dt) -> O.Found:
  match same:
    case True{}: O.Found{F.Folded.ar(fx), self}
    case False{}: O.UOp.new(F.Folded.ar(fx), O.OpsCAST{}, [self], O.ADt{dt}, O.TNone{})

def wk_cast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  wk_cast_at.of(wk_eq_dt(wk_dt(fx, self), dt), fx, self, dt)

# ops.py:632-638 `UOp.const`: `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)` -- the
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

# WHY it lives here and not in `mixin/elementwise.bend`. `tensor.bend` NEEDS it, and that is
# not a preference. CPython's `self.eq(inf)` runs `_broadcasted`'s `promote`
# (elementwise.py:29-31), whose weak-CONST arm IS `remint`. So `self.eq(+inf)` REMINTS
def wk_remint.folds(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, S.CWeakInt{}, nm}: True{}
    case S.Dt{pri, bits, S.CWeakFloat{}, nm}: True{}
    case S.Dt{pri, bits, S.CBool{}, nm}: True{}
    case _: False{}

def wk_remint.mkconst(bare: Bool, +dt: S.Dt, +made: O.Found) -> O.Found:
  match bare:
    case True{}: made
    case False{}: O.UOp.new(O.Found.ar(made), O.OpsCAST{}, [O.Found.i(made)], O.ADt{dt}, O.TNone{})

# `UOp.const(val, dt)` -- ops.py:629-635. `wk_bare_const` is the same value truncation and
def wk_remint.cast(+ar: O.Arena, u: U32, +dt: S.Dt) -> O.Found:
  v = wk_const_of(wk_dt_const(dt, wk_ccast.val(F.folded(ar), u)))
  wk_remint.mkconst(wk_remint.folds(dt), dt, O.UOp.new(ar, O.OpsCONST{}, Nil{}, O.APy{v}, O.TNone{}))

# what put a four-deep `replace` chain in `tn_isfinite`'s graph (MEASURED: 18 nodes, four
# `u.op is Ops.CONST` -- the leaf test, and THE TOP-LEVEL ONE ONLY. The recursive arm tests
# `u.src[0]`'s op and that is a DIFFERENT question: merging the two into one predicate is
def wk_remint.isc(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsCONST{})

# `u.replace(src=(...)+u.src[1:])`. The tail is `O.Arena.src_from(ar, u, 1)`, NOT
# AND THE STORE IS `child`'s, NOT `ar`'s. The recursive call that produced `child` may have
def wk_remint.put(+child: O.Found, +ar: O.Arena, +u: U32) -> O.Found:
  replace_in(O.Found.ar(child), u, List.append(&2, U32, [O.Found.i(child)], O.Arena.src_from(ar, u, 1)))

# It recurses on `u.src[0]` and it GROWS the arena, so it is one self-recursive def with the
def wk_remint.go(fuel: Nat, isc: Bool, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  match fuel isc:
    case 0n _        : O.Found{ar, u}
    case 1n+p True{} : wk_remint.cast(ar, u, dt)
    case 1n+p False{}: wk_remint.put(wk_remint.go(p, wk_remint.isc(ar, O.Arena.src0(ar, u)), ar, O.Arena.src0(ar, u), dt), ar, u)

def wk_remint(fuel: Nat, +ar: O.Arena, +u: U32, +dt: S.Dt) -> O.Found:
  wk_remint.go(fuel, wk_remint.isc(ar, u), ar, u, dt)

# THE PYTHON, in weak.py's order. Every rule body here is `(Folded, U32) ->

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
#   if u.op not in GroupOp.Broadcastable or (meet:=promo_dtype(src)) in
def derived_dtypes(+fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Dts:
  derived_dtypes.put(Bool.and(O.GroupOp.broadcastable(O.Arena.op(F.Folded.ar(fx), self)),
      Bool.not(dt_weak(wk_meet(fx, ss)))),
    wk_meet(fx, ss),
    wk_dtype_at(fx, self, wk_deriveds(fx, ss)))

# `UOp.const(dt.const(s.val))` -- the bare CONST with NO dtype, so no CAST on top.
def wk_bare_const(+fx: F.Folded, +s: U32, +dt: S.Dt) -> O.Found:
  O.UOp.const(F.Folded.ar(fx), wk_const_of(wk_dt_const(dt, wk_ccast.val(fx, s))))

# THE ROOT RE-DERIVES. weak.py:18 -- a shift's dtype is its lhs's dtype, so committing the
#   bare = derived_dtypes(u, u.src) is not None

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

# The meet is `promo_dtype(src)` verbatim (ops.py:120 is `least_upper_dtype` over the
#   if not any(s.dtype in dtypes.weaks for s in u.src) or

def commit_weak_srcs.bad(+fx: F.Folded, +ss: List<&2, U32>) -> Bool:
  Bool.or(Bool.not(wk_any_weak(fx, ss)), dt_weak(wk_meet(fx, ss)))

def commit_weak_srcs.ans(bad: Bool, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: commit_srcs_at(fx, self, wk_meet(fx, ss))

def commit_weak_srcs(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  commit_weak_srcs.ans(commit_weak_srcs.bad(fx, wk_srcs(fx, self)), fx, self, wk_srcs(fx, self))

# A PURE walk: dropping a CAST names `s.src[0]`, which is already in the arena, so no node
# is made and no accumulator is needed. And the predicate a weak CAST over a const is not
# a commit, it is still resolving -- so the drop is allowed.
# uncast_const -- weak.py:80-87.

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

# caller (`cast_consts`, weak.py:94) is behind `_min_max`, so it has no caller in this
# commit_weak_consts -- weak.py:7-8. The FIRST def in weak.py, and the only one whose

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

# `u if dt is None else u.replace(src=...)`. The branch is on `dt is None` and the WALK IS
# Python returns a UOp on BOTH arms, and `u` is the node itself when `dt is None`, so the
def commit_weak_consts.walked(some: Bool, dt: ODt, +fx: F.Folded, +self: U32, +ss: List<&2, U32>) -> O.Found:
  match some:
    case True{}: replace_walk(commit_weak_consts.go(ss, walk_seed(F.Folded.ar(fx)), fx, ODt.dt(dt)), fx, self)
    case False{}: O.Found{F.Folded.ar(fx), self}

# NOTE the pattern is `src=(UPat(), UPat(dtype=dtypes.weaks), ...)`, so the pattern REQUIRES
# the src to be weak; the body then commits it at src[0]'s dtype, and a weak CONST src that
# is already there is the no-op Python's own hash-consing produces. The pattern's first src
# is a bare `UPat`, so `early_reject` is empty.
# THE pm_commit_weak RULE 1 LAMBDA -- weak.py:37-38, the one rule here with no def of its

def wk_store_cast.bad.of(sealed: Bool, isconst: Bool) -> Bool:
  Bool.and(sealed, isconst)

# `ccast` on src[1] reaches `dt.const` only when src[1] IS a CONST; otherwise it is `cast`,
# which `wk_blocked` does not gate. `dt` is src[0]'s dtype.
def wk_store_cast.bad(+fx: F.Folded, +self: U32) -> Bool:
  wk_store_cast.bad.of(wk_sealed(wk_dt(fx, wk_src0(fx, self))), wk_op_is(fx, wk_src1(fx, self), O.OpsCONST{}))

def wk_store_cast.srcs(+fx: F.Folded, +self: U32, +dt: S.Dt, mid: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [wk_src0(fx, self)], [mid]),
    O.Arena.src_from(F.Folded.ar(fx), self, 2))

def wk_store_cast.hit(bad: Bool, +hit: O.Found, +fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match bad:
    case True{}: None{}
    case False{}: Some{replace_in(O.Found.ar(hit), self, wk_store_cast.srcs(fx, self, dt, O.Found.i(hit)))}

# `(u.src[0], u.src[1].ccast(u.src[0].dtype), *u.src[2:])`, interned in the arena `wk_ccast`
# grew and not in the fold's own.
def wk_store_cast.ans(bad: Bool, +fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.hit(bad, wk_ccast(fx, wk_src1(fx, self), wk_dt(fx, wk_src0(fx, self))),
    fx, self, wk_dt(fx, wk_src0(fx, self)))

def wk_store_cast(+fx: F.Folded, +self: U32) -> Maybe<&2, O.Found>:
  wk_store_cast.ans(wk_store_cast.bad(fx, self), fx, self)

# GroupOp.Broadcastable == GroupOp.Binary | GroupOp.Ternary (tinygrad/uop/__init__.py:110).
def OP_BC() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

# no CONST arm: a concrete CAST over a weak CONST is already committed, minted that way by
# UOp.const
# pm_commit_weak -- weak.py:35-41. THREE rules in Python; TWO here. It rides every round
def wk_commit_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, OP_BC(),        Nil{}},   # 36  commit_weak_srcs
    O.PMEntry{1, [O.OpsSTORE{}], Nil{}}]}  # 38  the STORE lambda
# _lower_weak_ops -- weak.py:45, PORTED. It is a MODULE CONSTANT and the only
# TODO(p3) weak.py:40  pm_commit_weak rule 2 -- (UPat(Ops.CAST, src=(UPat(GroupOp.ALU, dtype=dtypes.weaks,
def LOWER_OPS() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsMUL{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsOR{},
   O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{},
   O.OpsMOD{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{},
   O.OpsNEG{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsRANGE{}, O.OpsSTACK{}, O.OpsSPECIAL{}]

# pm_uncast_const -- weak.py:89. ONE rule in Python; ONE here.
def wk_uncast_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, OP_BC(), Nil{}}]}   # 89

# THE DRIVER. A rule answers `Maybe<&2, Found>`, and `Found` is ops.bend's arena-and-index
# `wk_keep` is first-wins, the same shape as ops.bend:4017 `pm_keep`.

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
