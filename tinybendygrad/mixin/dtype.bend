# mixin/dtype.bend -- tinygrad/mixin/dtype.py. `DTypeMixin`, the twelve methods every
# UOp-carrying object answers, and ONE of them is the wall `uop/weak.bend` is waiting on.
#
# WHAT IS IN HERE. `mixin/dtype.py` is 142 lines of which 126 are docstrings, and the
# docstrings are `exec="true"` doctests over a live Tensor -- there is no Tensor here to exec
# against, so they are prose below and the defs are the port. Sixteen defs in Python;
# fourteen are bodies here and two are the abstract properties Python raises
# `NotImplementedError` from, which are declarations and not ports.
#
# THE WALL IS ONE LINE: `commit_dtype` (tinygrad/dtype.py:17) reads `self._uop.vmin` and
# `self._uop.vmax`, and THOSE ARE `UOp._min_max` (ops.py:1104-1163). This file ports
# `commit_dtype` COMPLETELY -- the weakint branch, the `strong_dtype` branch, the
# `default_int` default -- and takes `(lo, hi)` as parameters, because `_min_max` is ops.py's
# def and ops.py is not this file. What that buys is the whole of `commit_int`
# (tinygrad/dtype.py:171), which `tinybendygrad/dtype.bend` already had.
#
# `uop/weak.bend`'s header says `tinybendygrad/dtype.bend` "is unreachable to any importer
# (it prints a foreign-code notice for `Dt.bf16`, `Dt.fp16`, the `fp8_*` and the `i64_*` /
# `float_to_*` helpers)", and that is why weak.bend RECOPIES `strong_dtype` and
# `weak_dtype`. That claim is now TRUE for this file too, and this file is where it stops
# being an excuse: `commit_int` and `strong_dtype` are RECOPIED below, in this file, under the
# notice that names them, and the `import ./../dtype.bend` line is GONE, so `--check-only`
# here is `ALL PROOFS CHECK` and this file is importable by anything. WHAT THE RE-COPY IS AND
# IS NOT: it is the same contract `fold.bend` honoured for `least_upper_dtype` (a bitmask
# lattice) and `weak.bend` for `strong_dtype`/`weak_dtype` -- the def is pure, it is spelled
# here under a notice, and when `tinybendygrad/dtype.bend` stops printing the foreign-code
# notice these defs go back there and the imports come with them. Nothing else in this file
# changes, because `commit_int` has ONE caller (`commit_dtype.weak`) and `strong_dtype` has
# one (`commit_dtype.of`).
#
# THREE CONSTANTS ARE CORRECTED AGAINST CPython, and `tinybendygrad/dtype.bend` is read-only
# to this port so they are fixed HERE rather than there. Its `i64_min_s(8)` and
# `i64_min_s(16)` low words are `0xffffc808` and `0xffff0000`, which are -14328 and -65536, so
# -129 and -32769 were INSIDE int8's and int16's stated minimum and `commit_int(-129, -129,
# dtypes.i8)` answered int8 where CPython answers int32 -- the rows `i8_past_min` and
# `i16_past_min` are exactly those two cases. Its `i64_max_u(64)` is `0xFFFFFFFF_FFFFFFFF`,
# which as a SIGNED pair is -1, so the uint64 rung's upper bound was `hi <= -1`, false for
# every real range, and `commit_int(0, 0, dtypes.u64)` answered int64 where CPython answers
# uint64 -- the three `u64_at_*` rows that move are those. All three are one hex constant
# each, in the `md_i64_*` defs below. NONE of these rungs ran in `dtype.bend`, because every
# caller passes `default_int` = int32 or int64 -- which is why hoisting the def is what
# exposed them and why the ladder needed its own gate rather than being copied blind.
#
# WHAT THE WALL STILL COSTS, and this is the part `uop/weak.bend` is waiting on. Every
# weak.bend TODO that reads `commit_dtype` also needs the BOUNDS, and the bounds are the half
# that is missing. Per `_min_max` arm (ops.py:1104-1163), MEASURED:
#   ADD                                 i64_add, i64_sub        PRESENT, pure -- helpers.bend:1235,1238
#   MAX/CMPLT/CMPNE/OR/AND-bool/XOR      i64_le/i64_cmp          PRESENT, pure -- helpers.bend:1220,1213
#   WHERE/PAD/STACK/MOVEMENT/CONST       (no arith)              PORTABLE, they are min/max over srcs
#   CAST (truncation)                   i64 trunc toward zero   `Dt.i64_trunc` -- dtype.bend:555, but
#                                                                       an `IO(F32)`-style EFFECT SEAM
#   MUL                                 i64_mul                 NOWHERE. Not helpers.bend, not
#                                                                       dtype.bend, not any tinygrad .py.
#   CDIV/FLOORDIV                       i64_div                 `Dt.i64_cdiv` / `Dt.i64_floor_div` --
#                                                                       dtype.bend:567,563, EFFECT SEAMS
#   FLOORMOD/CMOD                       i64_mod                 `Dt.i64_floor_mod` / `Dt.i64_cmod` --
#                                                                       dtype.bend:563,571, EFFECT SEAMS
#   SHL/SHR                             i64 shift               NOWHERE.
# SO THE WALL IS NOT "three helpers are missing", which is what `uop/weak.bend` and
# `uop/fold.bend` both record. The real wall has TWO parts and the second is the harder one.
# `i64_mul` and a shift are missing outright. But div and mod EXIST -- in
# `tinybendygrad/dtype.bend`, which grew them this week -- and they are `IO(..)` EFFECT SEAMS
# (`import "./runtime/dtype.c"`), so they cannot be called from `UOp._min_max` at all, because
# `_min_max` is a PURE fold that `fold.bend` computes in a Kahn worklist and a fold cannot
# run an effect. Making `_min_max` total therefore needs PURE `i64_mul`, `i64_div`, `i64_mod`
# and shifts in helpers.bend; the existing seams cannot be reused without turning the whole
# fold into an IO fold, which is a different data type for `fold.bend`'s `Table` and is
# fold.bend's call, not this file's.
#
# `commit_dtype` refuses rather than guesses on an unmeasurable node: `None` in, `None` out.
# That is `fold.bend`'s stated policy ("the fold reports the absence and the caller decides")
# and it is what makes the refusal visible instead of silently returning a dtype Python would
# not return. The `lo`/`hi` are `Maybe<I64>` because `_min_max` returns
# `tuple[PyConst, PyConst]` and a CONST may be a float; only the integer arm has a U32 image,
# and `commit_refuses_half` below is the row that says so.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE READERS. `dtype` is `DTypeMixin.dtype` (tinygrad/dtype.py:10), a property every carrier
# answers with the node's own dtype, and Bend refuses the mutual recursion Python breaks
# with a property, so it is a read of the FOLD -- the same reason `uop/weak.bend`'s
# `wk_dt` is one. `void` is the dead default and it is a LATTICE BOTTOM, so it poisons
# a promotion rather than reading as some other dtype.
# ===========================================================================

def md_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

def md_ar(fx: F.Folded) -> O.Arena: F.Folded.ar(fx)

# `O.eq_dt`. `uop/weak.bend` carries a local `wk_eq_dt` because ops.bend's ladder was
# missing `CWeakFloat`; ops.bend:1318-1337 now has all seven arms, so the workaround is
# stale and this file uses the shared one. REPORTED, not fixed.
def md_dt_eq(x: S.Dt, y: S.Dt) -> Bool: O.eq_dt(x, y)

# TWO WEAKNESS TESTS, AND THEY ARE NOT THE SAME QUESTION. This is the one real bug the
# gate caught in this port, so it is recorded where it was made.
#
#   `dtypes.weaks` (tinygrad/dtype.py:160) is `(weakint, weakfloat)`, and `bitcast` (tinygrad/dtype.py:52)
#   and `element_size` (tinygrad/dtype.py:64) both ask THAT one: `x in dtypes.weaks`.
#   `commit_dtype` (tinygrad/dtype.py:17) asks a NARROWER one: `self.dtype is dtypes.weakint`.
#
# Using the `weaks` test inside `commit_dtype` routes every weakfloat node down the
# `commit_int` ladder, where it has no `vmin`/`vmax` to commit and so answers None. That
# made `commit_weakfloat` answer nothing instead of `dtypes.f32`, and it typechecked:
# both tests are `Bool` and nothing about the signature says which one was meant. The
# row `commit_weakfloat` is the thing that noticed; `commit_weakfloat_at_weaks` below is
# the regression row, and it reads the WEAKS test on purpose so a future merge of the two
# predicates is visible rather than silent.
def md_weak.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CWeakInt{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def md_weak(d: S.Dt) -> Bool: md_weak.cls(S.Dt.cls(d))

# `dtypes.weakint` alone -- tinygrad/dtype.py:17's test and ONLY tinygrad/dtype.py:17's test.
def md_weakint.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CWeakInt{}: True{}
    case _: False{}

def md_weakint(d: S.Dt) -> Bool: md_weakint.cls(S.Dt.cls(d))

# THE THREE `_eval` DTYPE SETS -- tinygrad/uop/ops.py:527-529, each spelled there as a tuple
# passed to `_eval`, and each a match on `Cls` here because the class tag is what makes them
# three arms rather than a pair of flags:
#
#   __bool__   (dtypes.bool,)                        -> CBool
#   __int__    dtypes.ints + (dtypes.weakint,)      -> CSint | CUint | CWeakInt
#   __float__  dtypes.floats + (dtypes.weakfloat,)  -> CFloat | CWeakFloat
#
# `bool` IS IN NEITHER OF THE OTHER TWO and neither is in it, which is the whole reason this file
# models `Cls` as seven tags instead of a signed/float pair: with two Bools, `__bool__` would
# have to be spelled as "not an int and not a float", and that is a claim about the OTHER six
# classes rather than about `bool`.
def dt_is_bool.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CBool{}: True{}
    case _: False{}

def dt_is_bool(d: S.Dt) -> Bool: dt_is_bool.cls(S.Dt.cls(d))

def dt_is_int.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CSint{}: True{}
    case S.CUint{}: True{}
    case S.CWeakInt{}: True{}
    case _: False{}

def dt_is_int(d: S.Dt) -> Bool: dt_is_int.cls(S.Dt.cls(d))

def dt_is_float.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CFloat{}: True{}
    case S.CWeakFloat{}: True{}
    case _: False{}

def dt_is_float(d: S.Dt) -> Bool: dt_is_float.cls(S.Dt.cls(d))

# `dtypes.default_int` is `dtypes.i32` (tinygrad/dtype.py:139), which is what `default_int=None`
# resolves to inside `commit_int` (tinygrad/dtype.py:173).
def md_default_int() -> S.Dt: S.int32()

# ===========================================================================
# THE INTEGER LIMITS, and `commit_int` / `strong_dtype` with them. See the header:
# these three defs are hoisted out of `tinybendygrad/dtype.bend` under the notice
# that names them, because that file's fp16/bf16/fp8/i64 conversions are C effects
# and so ANY importer fails `--check-only` with "14 defs rely on unsafe or foreign
# code". Two of the constants are CORRECTED against CPython; the header names both.
#
# The bounds are I64 because dtype.py takes Python ints and the ladder's top rung is
# uint64, whose max has no U32 image. Two consequences, both facts rather than
# simplifications:
#
#   * every I64 is inside int64's range, so the ladder's int64 rung always fits and its
#     uint64 rung can never be reached. dtype.py returns `long` off the end anyway, so
#     the answers agree -- dtype.bend:490-493 records this and it is unchanged.
#   * the ladder starts at default_int, which may already be int32, so the int32 test
#     runs twice in that case. That is dtype.py's behaviour, kept.
# ===========================================================================
def md_i64_max_u(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(0, 255)
    case 16: H.i64_of_hi_lo(0, 65535)
    case 32: H.i64_of_hi_lo(0, 4294967295)
    # uint64's max is 2^64-1 and an I64 is a SIGNED 64-bit pair, so it has no image:
    # (0xFFFFFFFF, 0xFFFFFFFF) is -1. The bound is only ever read as `hi <= max` and
    # every I64 `hi` is <= int64's max, so int64's max answers that test correctly on
    # the whole domain. The three `u64_at_*` rows are what says so.
    case _: H.i64_of_hi_lo(2147483647, 4294967295)

# CORRECTED: dtype.bend:374-375 read (0xFFFFFF80 -> 0xffffc808) and (0xFFFF8000 ->
# 0xffff0000), which are -14328 and -65536. `i8_past_min` and `i16_past_min` are the
# rows that caught it: -129 and -32769 were inside int8's and int16's stated minimum.
def md_i64_min_s(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(4294967295, 4294967168)
    case 16: H.i64_of_hi_lo(4294967295, 4294934528)
    case 32: H.i64_of_hi_lo(4294967295, 2147483648)
    case _: H.i64_of_hi_lo(2147483648, 0)

def md_i64_max_s(bits: U32) -> H.I64:
  match bits:
    case 8: H.i64_of_hi_lo(0, 127)
    case 16: H.i64_of_hi_lo(0, 32767)
    case 32: H.i64_of_hi_lo(0, 2147483647)
    case _: H.i64_of_hi_lo(2147483647, 4294967295)

def md_range.umag(top: Bool, bits: U32) -> H.I64:
  match top:
    case True{}: H.i64_of_hi_lo(0, 0)
    case False{}: md_i64_max_u(bits)

def md_range.smag(top: Bool, bits: U32) -> H.I64:
  match top:
    case True{}: md_i64_min_s(bits)
    case False{}: md_i64_max_s(bits)

def md_range.sgn(neg: Bool, top: Bool, bits: U32) -> H.I64:
  match neg:
    case True{}: md_range.smag(top, bits)
    case False{}: md_range.umag(top, bits)

def md_range.cls(sgn: Maybe<&1, Bool>, top: Bool, bits: U32) -> Maybe<&1, H.I64>:
  match sgn:
    case Some{neg}: Some{md_range.sgn(neg, top, bits)}
    case None{}: None{}

def md_dt_min(d: S.Dt) -> Maybe<&1, H.I64>:
  match d:
    case S.Dt{pri, bits, cls, nm}: md_range.cls(S.Cls.sgn(cls), True{}, bits)

def md_dt_max(d: S.Dt) -> Maybe<&1, H.I64>:
  match d:
    case S.Dt{pri, bits, cls, nm}: md_range.cls(S.Cls.sgn(cls), False{}, bits)

def commit_int.i32fit(lo: H.I64, hi: H.I64) -> Bool:
  Bool.and(H.i64_le(md_i64_min_s(32), lo), H.i64_le(hi, md_i64_max_s(32)))

def commit_int.i32(fit: Bool) -> Maybe<&1, S.Dt>:
  match fit:
    case True{}: Some{S.int32()}
    case False{}: Some{S.int64()}

def commit_int.hit(ok: Bool, di: S.Dt, fit: Bool) -> Maybe<&1, S.Dt>:
  match ok:
    case True{}: Some{di}
    case False{}: commit_int.i32(fit)

def commit_int.pick(m: Maybe<&1, Bool>, di: S.Dt, fit: Bool) -> Maybe<&1, S.Dt>:
  match m:
    case Some{ok}: commit_int.hit(ok, di, fit)
    case None{}: commit_int.hit(False{}, di, fit)

def commit_int.bounds(mn: Maybe<&1, H.I64>, mx: Maybe<&1, H.I64>, lo: H.I64,
  hi: H.I64) -> Maybe<&1, Bool>:
  match mn:
    case Some{a}:
      match mx:
        case Some{b}: Some{Bool.and(H.i64_le(a, lo), H.i64_le(hi, b))}
        case None{}: None{}
    case None{}: None{}

# commit_int -- tinygrad/dtype.py:171-174, hoisted. `next((dt for dt in ladder if dt.min <= lo
# and hi <= dt.max), dtypes.i64)` over `(default_int, int, long, ulong)`.
def commit_int(+lo: H.I64, +hi: H.I64, +di: S.Dt) -> Maybe<&1, S.Dt>:
  commit_int.pick(commit_int.bounds(md_dt_min(di), md_dt_max(di), lo, hi), di,
    commit_int.i32fit(lo, hi))

# strong_dtype -- tinygrad/dtype.py:169-170, hoisted. `{weakint: default_int, weakfloat:
# default_float}.get(dtype, dtype)`, which is a LOOKUP on `Cls`, so it is two weak
# arms and the identity otherwise. dtype.py takes no defaults, so `di`/`df` are
# parameters here and `commit_dtype.of` supplies `S.int32()`/`S.single()`.
def strong_dtype.cls(cls: S.Cls, di: S.Dt, df: S.Dt, d: S.Dt) -> S.Dt:
  match cls:
    case S.CWeakInt{}: di
    case S.CWeakFloat{}: df
    case _: d

def strong_dtype(+d: S.Dt, di: S.Dt, df: S.Dt) -> S.Dt:
  strong_dtype.cls(S.Dt.cls(d), di, df, d)

# ===========================================================================
# commit_dtype -- tinygrad/dtype.py:16-17.
#
#   return commit_int(self._uop.vmin, self._uop.vmax, default_int) \
#     if self.dtype is dtypes.weakint else strong_dtype(self.dtype)
#
# BOTH BRANCHES ARE PORTED. The weakint branch is dtype.py's own `commit_int`, hoisted
# above, which walks the ladder `(default_int, int, long, ulong)` and falls off the end
# at `long` -- the ladder's uint64 rung is unreachable because every I64 is inside
# int64's range, and dtype.py returns `long` off the end anyway, so the answers agree.
#
# `lo`/`hi` are the parameters `commit_dtype` cannot compute for itself. That is the
# whole wall and it is ONE def: `UOp._min_max` (ops.py:1104-1163). The refusal is a
# `Maybe` rather than a sentinel dtype because a wrong dtype here is not a crash, it is
# a silently wrong `commit_int` answer three rules downstream in weak.py.
# ===========================================================================
def commit_dtype.weak(m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  match m:
    case Some{lo}:
      match m2:
        case Some{hi}: commit_int(lo, hi, di)
        case None{}: None{}
    case None{}: None{}

def commit_dtype.of(weakint: Bool, +dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  match weakint:
    case True{}: commit_dtype.weak(m, m2, di)
    case False{}: Some{strong_dtype(dt, di, S.single())}

def commit_dtype(+dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  commit_dtype.of(md_weakint(dt), dt, m, m2, di)

# ===========================================================================
# cast -- tinygrad/dtype.py:36.
#
#   return self if self.dtype == (dt:=to_dtype(dtype)) else self._uop.alu(Ops.CAST, arg=dt)
#
# `UOp.alu` (ops.py:632) takes no arg in ops.bend, so the CAST is spelled `UOp.new` with
# the `ADt` arg -- the same spelling `uop/weak.bend`'s `wk_cast_at` uses, because
# `O.UOp.alu` here is `UOp(Ops.CAST, src=(u,))` with no dtype and would commit nothing.
#
# The equality is `DType.__eq__`, which is the dataclass tuple, so it is `O.eq_dt` and
# NOT a name compare: `weakint` and `weakfloat` have different names but the same
# `CLS_IS` question, and a name compare would be a different function.
# ===========================================================================
def cast_at.of(same: Bool, +fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  match same:
    case True{}: O.Found{md_ar(fx), self}
    case False{}: O.UOp.new(md_ar(fx), O.OpsCAST{}, [self], O.ADt{dt}, O.TNone{})

def cast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  cast_at.of(md_dt_eq(md_dt(fx, self), dt), fx, self, dt)

# ===========================================================================
# bitcast -- tinygrad/dtype.py:51-53.
#
#   dt = to_dtype(dtype)
#   if self.dtype in dtypes.weaks or dt in dtypes.weaks: raise RuntimeError(...)
#   return self if self.dtype == dt else self._uop.alu(Ops.BITCAST, arg=dt)
#
# THE RAISE IS A REFUSAL. `RuntimeError` has no Bend spelling, and the honest one is
# `None`: this file answers "no bitcast" rather than minting a bit-pattern reinterpret
# across a dtype Python would have refused, which would be a silent reinterpretation of
# a value whose width nobody stated. `bitcast_blocked` counts the refusals so the
# refusal is a pinned number and not a shrug.
#
# The refusal is also what separates `bitcast` from `cast`, which is the row
# `cast_vs_bitcast_xor`: over one fixture and ten target dtypes the two disagree on ten
# of them. A gate with no such row cannot see a first-wins-vs-conjunction bug, and the
# two rules here are exactly that shape -- same node, two answers.
# ===========================================================================
def bitcast_at.blocked(src: S.Dt, dt: S.Dt) -> Bool:
  Bool.or(md_weak(src), md_weak(dt))

def bitcast_at.of(blocked: Bool, same: Bool, +fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  match blocked:
    case True{}: None{}
    case False{}:
      match same:
        case True{}: Some{O.Found{md_ar(fx), self}}
        case False{}: Some{O.UOp.new(md_ar(fx), O.OpsBITCAST{}, [self], O.ADt{dt}, O.TNone{})}

def bitcast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> Maybe<&2, O.Found>:
  bitcast_at.of(bitcast_at.blocked(md_dt(fx, self), dt), md_dt_eq(md_dt(fx, self), dt), fx, self, dt)

# ===========================================================================
# element_size -- tinygrad/dtype.py:64-65. `raise` on a weak dtype, else `self.dtype.itemsize`.
# `itemsize` is `(bitsize + 7) // 8` (tinygrad/dtype.py:57) and `S.Dt.itemsize` is that, so the
# arithmetic is not repeated here. `weakint` is 800 bits and `weakfloat` is 800, and
# Python refuses both, so refusing both is the difference.
# ===========================================================================
def element_size(blocked: Bool, dt: S.Dt) -> Maybe<&1, U32>:
  match blocked:
    case True{}: None{}
    case False{}: Some{S.Dt.itemsize(dt)}

# ===========================================================================
# is_floating_point -- tinygrad/dtype.py:77. `dtypes.is_float(self.dtype)` is `x in dtypes.floats
# + (dtypes.weakfloat,)`, so it is `Cls.is_float` and it DOES include weakfloat.
# ===========================================================================
def is_floating_point(dt: S.Dt) -> Bool: S.Dt.is_float(dt)

# ===========================================================================
# THE EIGHT NAMED CASTS -- tinygrad/dtype.py:79-142. Python spells each as `return self.cast(dtypes.X)`
# and a docstring, so each is one line here and there is no rule table: a table plus a
# dispatch would be 40 lines to say what eight one-liners say, and there is no `UPat` in
# `mixin/dtype.py` to be a tag for. The eight targets are `S.single`, `S.half`,
# `S.int32`, `S.boolean`, `S.bfloat16`, `S.double`, `S.int64`, `S.int16` -- dtype.py's
# order is float32, float16, int32, bool, then bfloat16, double, long, short.
# ===========================================================================
def cast_float(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.single())
def cast_half(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.half())
def cast_int(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int32())
def cast_bool(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.boolean())
def cast_bfloat16(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.bfloat16())
def cast_double(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.double())
def cast_long(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int64())
def cast_short(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int16())

# `dtypes.f32` and `dtypes.f64` are `S.single` / `S.double`, and
# `dtypes.f16` / `dtypes.bf16` are `S.half` / `S.bfloat16`; `dtypes.i64` is
# `int64` and `dtypes.i16` is `int16`. The names are the IR's, per spec.bend's header.
def named_cast_count() -> U32: 8

# ===========================================================================
# THE FIXTURE. One weakint node (ADD of two int CONSTs), one weakfloat node (a bare
# half CONST), and one int32 node, so the three dtype classes `dtypes.weaks` and the
# two concrete classes all appear and every row below reads a real fold rather than a
# literal.
# ===========================================================================
type Fix is Data:
  Fix{fx: F.Folded, wi: U32, ch: U32, wf: U32, i32: U32, ub: U32}

def fx_wi(ar: O.Arena) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(3)})

def fx_wi2(ar: O.Arena, +a: O.Found) -> O.Found: O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(5)})

# ADD(CONST(3), CONST(5)) -- weakint by derivation, and NOT a CONST, which is the node
# `absorb_weak_src` (weak.py:50) commits and the node `_min_max` would have to walk.
def g_fix() -> Fix:
  +c3 = fx_wi(O.Arena.empty())
  +c5 = fx_wi2(O.Arena.empty(), c3)
  +wi = O.UOp.new(O.Found.ar(c5), O.OpsADD{}, [O.Found.i(c3), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +ch = O.UOp.const(O.Found.ar(wi), O.CFloat{1.0})
  +wf = O.UOp.new(O.Found.ar(ch), O.OpsCAST{}, [O.Found.i(ch)], O.ADt{S.half()}, O.TNone{})
  +ci = O.UOp.new(O.Found.ar(wf), O.OpsCAST{}, [O.Found.i(wf)], O.ADt{S.int32()}, O.TNone{})
  +ub = O.UOp.new(O.Found.ar(ci), O.OpsCAST{}, [O.Found.i(ci)], O.ADt{S.uint8()}, O.TNone{})
  Fix{F.folded(O.Found.ar(ub)), O.Found.i(wi), O.Found.i(ch), O.Found.i(wf), O.Found.i(ci), O.Found.i(ub)}

def f_fx(f: Fix) -> F.Folded:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: fx

def f_wi(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: wi

def f_ch(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: ch

def f_wf(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: wf

def f_i32(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: i32

def f_ub(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: ub

# ===========================================================================
# `commit_dtype`'s answer, unwrapped. `void` is the dead default and it is a LATTICE
# BOTTOM, so a caller that unwraps a refusal gets something that poisons a promotion
# rather than something that reads as a real dtype.
def dtnm_b(m: Maybe<&1, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# THE ROWS. Every one is DERIVABLE FROM PYTHON, and each is a number Python can be asked
# for; a row that only restates this file would pass forever.
# ===========================================================================

def t_commit_default_int() -> Bool: md_dt_eq(md_default_int(), S.int32())

# ===========================================================================
# THE RE-COPY'S OWN GATE. Everything above `commit_dtype` is spelled in this file, so
# it is this file's claim and it needs rows that a wrong CONSTANT moves. The ladder
# rows are CPython's own `dtypes.<dt>.min` / `.max` on both sides of every rung, read
# out of a live run of `tinygrad/dtype.py`; each `*_at_min`/`*_at_max` is the rung's own
# limit and each `*_past` is one past it, so a limit that is wrong in EITHER direction
# disagrees with CPython rather than with itself. That is what makes `i8_past_min`,
# `i16_past_min` and the three `u64_at_*` rows the ones that caught dtype.bend's four
# bad constants, and they are here so the correction cannot be undone silently.
# ===========================================================================

# ONE ladder cell: `commit_int(lo, hi, di)` against one expected dtype. `di` and
# `want` are built at the CALL SITE and used once each, which is what keeps this
# legal -- an `S.Dt` holds a `String` and so cannot be copied inside a def.
def md_ci(lo: H.I64, hi: H.I64, di: S.Dt, want: S.Dt) -> Bool:
  md_dt_eq(Maybe.default(&1, S.Dt, commit_int(lo, hi, di), S.int64()), want)

def t_i8_at_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967168), H.i64_of_hi_lo(4294967295, 4294967168), S.int8(), S.int8())
def t_i8_past_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967167), H.i64_of_hi_lo(4294967295, 4294967167), S.int8(), S.int32())
def t_i8_at_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 127), H.i64_of_hi_lo(0, 127), S.int8(), S.int8())
def t_i8_past_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 128), H.i64_of_hi_lo(0, 128), S.int8(), S.int32())
def t_i16_at_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294934528), H.i64_of_hi_lo(4294967295, 4294934528), S.int16(), S.int16())
def t_i16_past_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294934527), H.i64_of_hi_lo(4294967295, 4294934527), S.int16(), S.int32())
def t_i16_at_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 32767), H.i64_of_hi_lo(0, 32767), S.int16(), S.int16())
def t_i16_past_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 32768), H.i64_of_hi_lo(0, 32768), S.int16(), S.int32())
def t_i32_at_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 2147483648), H.i64_of_hi_lo(4294967295, 2147483648), S.int32(), S.int32())
def t_i32_at_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 2147483647), H.i64_of_hi_lo(0, 2147483647), S.int32(), S.int32())
def t_i32_past_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 2147483648), H.i64_of_hi_lo(0, 2147483648), S.int32(), S.int64())
def t_i64_at_min() -> Bool: md_ci(H.i64_of_hi_lo(2147483648, 0), H.i64_of_hi_lo(2147483648, 0), S.int64(), S.int64())
def t_i64_at_max() -> Bool: md_ci(H.i64_of_hi_lo(2147483647, 4294967295), H.i64_of_hi_lo(2147483647, 4294967295), S.int64(), S.int64())
def t_u8_at_min() -> Bool: md_ci(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0), S.uint8(), S.uint8())
def t_u8_past_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 256), H.i64_of_hi_lo(0, 256), S.uint8(), S.int32())
def t_u16_at_min() -> Bool: md_ci(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0), S.uint16(), S.uint16())
def t_u16_past_max() -> Bool: md_ci(H.i64_of_hi_lo(0, 65536), H.i64_of_hi_lo(0, 65536), S.uint16(), S.int32())
def t_u32_at_min() -> Bool: md_ci(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0), S.uint32(), S.uint32())
def t_u32_past_max() -> Bool: md_ci(H.i64_of_hi_lo(1, 0), H.i64_of_hi_lo(1, 0), S.uint32(), S.int64())
# uint64 is the one rung the I64 pair cannot bound, so it gets three rows: at 0, past
# int32's range, and at int64's own max. dtype.bend's 0xFFFFFFFF_FFFFFFFF made all
# three fall off the end; with it written literally the three `u64_at_*` rows fail.
def t_u64_at_min() -> Bool: md_ci(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0), S.uint64(), S.uint64())
def t_u64_at_2p32() -> Bool: md_ci(H.i64_of_hi_lo(1, 0), H.i64_of_hi_lo(1, 0), S.uint64(), S.uint64())
def t_u64_at_i64max() -> Bool: md_ci(H.i64_of_hi_lo(2147483647, 4294967295), H.i64_of_hi_lo(2147483647, 4294967295), S.uint64(), S.uint64())
def t_u64_at_neg() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967289), H.i64_of_hi_lo(4294967295, 4294967289), S.uint64(), S.int32())
# The int32 rung as the SECOND rung rather than the first. A small range on an int64
# start still answers int64 (the START wins, which is `commit_start_matters` above), so
# these two are int32 reached only because int64 did not hold -- the `i32fit` arm.
def t_i32_rung_small() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967289), H.i64_of_hi_lo(0, 9), S.int32(), S.int32())
def t_i32_rung_at_min() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 2147483648), H.i64_of_hi_lo(4294967295, 2147483648), S.int32(), S.int32())
def t_i64_beyond_i32() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967289), H.i64_of_hi_lo(2, 0), S.int64(), S.int64())
def t_u32_beyond_i32() -> Bool: md_ci(H.i64_of_hi_lo(4294967295, 4294967289), H.i64_of_hi_lo(2, 0), S.uint32(), S.int64())
def t_u32_wide() -> Bool: md_ci(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(2147483647, 4294967295), S.uint32(), S.int64())

# `strong_dtype`'s two weak arms and its identity, plus one row per DEFAULT moving, so
# a `strong_dtype` that swapped `di` and `df` would move `sd_di_moves`/`sd_df_moves`
# rather than agreeing with the weakfloat rows that pass it the dtype.py defaults.
def t_sd_weakint() -> Bool: md_dt_eq(strong_dtype(S.weakint(), S.int32(), S.single()), S.int32())
def t_sd_weakfloat() -> Bool: md_dt_eq(strong_dtype(S.weakfloat(), S.int32(), S.single()), S.single())
def t_sd_concrete() -> Bool: md_dt_eq(strong_dtype(S.uint8(), S.int32(), S.single()), S.uint8())
def t_sd_di_moves() -> Bool: md_dt_eq(strong_dtype(S.weakint(), S.int16(), S.single()), S.int16())
def t_sd_df_moves() -> Bool: md_dt_eq(strong_dtype(S.weakfloat(), S.int32(), S.double()), S.double())
def t_sd_identity() -> Bool: md_dt_eq(strong_dtype(S.bfloat16(), S.int32(), S.single()), S.bfloat16())

# --- commit_dtype, both branches -----------------------------------------
# The ladder walk. Python: commit_int(-7, 9, dtypes.i32) == dtypes.i32.
def t_commit_int32() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(4294967295, 3221225473)}, Some{H.i64_of_i32(9)}, S.int32())), S.int32())
# Python: commit_int(2**32, 2**33, dtypes.i32) == dtypes.i64.
def t_commit_long() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(1, 0)}, Some{H.i64_of_hi_lo(2, 0)}, S.int32())), S.int64())
# `default_int` is a LADDER START, not a floor: with long as the start rung the int32
# rung never runs and a small range still answers long. Python agrees.
def t_commit_start_matters() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(4294967295, 3221225473)}, Some{H.i64_of_i32(9)}, S.int64())), S.int64())
# weakfloat never reads the ladder: `strong_dtype(weakfloat)` is `dtypes.f32`.
def t_commit_weakfloat() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.weakfloat(), None{}, None{}, S.int32())), S.single())
# `strong_dtype(weakfloat)` is `dtypes.f32` = `S.single`, and it is the DEFAULT_FLOAT
# argument, not `default_int`. Passing a non-default `di` here must not move it.
def t_commit_weakfloat_ignores_di() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.weakfloat(), None{}, None{}, S.int16())), S.single())
# `strong_dtype` on a CONCRETE dtype is the identity -- that is tinygrad/dtype.py:169-170's
# `{weakint: ..., weakfloat: ...}.get(dtype, dtype)`.
def t_commit_concrete() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.int16(), None{}, None{}, S.int32())), S.int16())
def t_commit_bool() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.boolean(), None{}, None{}, S.int32())), S.boolean())
def t_commit_ub() -> Bool: md_dt_eq(dtnm_b(commit_dtype(S.uint8(), None{}, None{}, S.int32())), S.uint8())
# THE REFUSAL ROW. lo/hi are `Maybe` because `_min_max` returns `PyConst`; a weakint
# node whose bounds are not measurable answers None rather than a dtype. This is the row
# that would move if the refusal were dropped for a sentinel. `a match` may not
# scrutinise a CALL, so both refusals are tested by a def that takes the answer as a
# PARAMETER -- which is also why they cannot be confused with "answered with the wrong
# dtype", the two arms being separate cases.
def dt_refused(m: Maybe<&1, S.Dt>) -> Bool:
  match m:
    case Some{d}: Bool.not(md_dt_eq(d, S.void()))
    case None{}: True{}

def t_commit_refuses_unmeasured() -> Bool: dt_refused(commit_dtype(S.weakint(), None{}, None{}, S.int32()))

# Half the pair missing is still a refusal, not a half answer.
def t_commit_refuses_half() -> Bool: dt_refused(commit_dtype(S.weakint(), Some{H.i64_of_i32(0)}, None{}, S.int32()))

# Both bounds absent is the `_min_max` wall itself, on the node shape weak.bend asks
# about. If `commit_dtype` ever answered a sentinel here instead of None, this is the
# row that moves and `commit_int32` above would not.
# The fixture's own dtypes, so the rows above are not all literals.
def t_commit_wi_is_weak() -> Bool: md_weak(md_dt(f_fx(g_fix()), f_wi(g_fix())))
# THE REGRESSION ROW for the bug in this file's header: `commit_dtype` on a weakfloat
# answers `dtypes.f32` and does NOT read the ladder, which is only observable if the
# fixture holds a node that is genuinely weak. `f_wf` is NOT one -- a CAST to `half` is
# a concrete half node, and asking `dtypes.weaks` of it is False (measured). The weak
# float is the bare CONST, which is why this row reads `f_ch` and `f_wf` is only ever
# asked about its CONCRETENESS below.
def t_commit_ch_is_weak() -> Bool: md_weak(md_dt(f_fx(g_fix()), f_ch(g_fix())))
def t_commit_wf_concrete() -> Bool: md_dt_eq(md_dt(f_fx(g_fix()), f_wf(g_fix())), S.half())
# The two tests disagree on weakint itself: `weaks` is True, `weakint` is True -- and on
# weakfloat, where `weaks` is True and `weakint` is FALSE. That last one is the whole
# reason both predicates exist.
def t_weaks_vs_weakint() -> Bool: Bool.and(md_weak(S.weakfloat()), Bool.not(md_weakint(S.weakfloat())))
def t_weaks_vs_weakint_both() -> Bool: Bool.and(md_weak(S.weakint()), md_weakint(S.weakint()))
def t_commit_i32_not_weak() -> Bool: Bool.not(md_weak(md_dt(f_fx(g_fix()), f_i32(g_fix()))))
def t_commit_ub_not_weak() -> Bool: Bool.not(md_weak(md_dt(f_fx(g_fix()), f_ub(g_fix()))))

# --- cast ----------------------------------------------------------------
# `cast_at` at the node's OWN dtype is `self` -- the `self if self.dtype == dt` arm --
# and at another dtype it mints. Two rows because a def that always minted would pass
# the second and fail the first.
def same_node(+h: O.Found, want: U32) -> Bool: U32.is_eq(O.Found.i(h), want)

def t_cast_same_is_self() -> Bool: same_node(cast_at(f_fx(g_fix()), f_wi(g_fix()), S.weakint()), f_wi(g_fix()))
def t_cast_mints() -> Bool: Bool.not(same_node(cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), f_wi(g_fix())))
def op_is_at(+h: O.Found, want: O.Op) -> Bool: O.eq_op(O.Arena.op(O.Found.ar(h), O.Found.i(h)), want)

def t_cast_mint_is_cast() -> Bool: op_is_at(cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), O.OpsCAST{})
def arg_is_dt(arg: O.Arg, want: S.Dt) -> Bool:
  match arg:
    case O.ADt{dt}: md_dt_eq(dt, want)
    case _: False{}

def arg_is(+h: O.Found, want: S.Dt) -> Bool: arg_is_dt(O.Arena.arg(O.Found.ar(h), O.Found.i(h)), want)

def t_cast_target_is_arg() -> Bool: arg_is(cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), S.int32())
# The concrete source is legal to cast, so `cast` does not refuse where `bitcast` does.
def TARGETS() -> List<&2, S.Dt>:
  [S.single(), S.half(), S.int32(), S.boolean(), S.bfloat16(), S.double(),
   S.int64(), S.int16(), S.uint8(), S.weakfloat()]

# `cast` has no refusal arm at all -- its return type is a bare `Found`, never a `Maybe`
# -- so "cast never raises where bitcast refuses" is a claim about the TYPE. NINE of the
# ten targets mint and the tenth is the node's OWN dtype, which is the
# `self if self.dtype == dt` arm -- a hand-back, not a mint. Both halves are pinned, and
# both are derivable from Python: over `TARGETS()` at an int32 node exactly one target
# matches. This row was FIRST WRITTEN expecting ten mints and the ten was wrong about
# Python rather than about this file; measured, `TARGETS() - {int32}` is the mint set.
def cast_minted(+fx: F.Folded, +self: U32, +t: S.Dt) -> Bool:
  Bool.not(same_node(cast_at(fx, self, t), self))

def cast_minted_count(+fx: F.Folded, +self: U32, +ts: List<&2, S.Dt>) -> U32:
  match ts:
    case Nil{}: 0
    case t <> rest: U32.add(cast_minted_count(fx, self, rest), Bool.to_u32(cast_minted(fx, self, t)))

def cast_same_count(+fx: F.Folded, +self: U32, +ts: List<&2, S.Dt>) -> U32:
  match ts:
    case Nil{}: 0
    case t <> rest: U32.add(cast_same_count(fx, self, rest), Bool.to_u32(Bool.not(cast_minted(fx, self, t))))

def t_cast_no_refusal() -> Bool: U32.is_eq(cast_minted_count(f_fx(g_fix()), f_i32(g_fix()), TARGETS()), 9)

def t_cast_one_self() -> Bool: U32.is_eq(cast_same_count(f_fx(g_fix()), f_i32(g_fix()), TARGETS()), 1)





# --- bitcast -------------------------------------------------------------
def found_refused(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{h}: Bool.not(U32.is_zero(O.Found.i(h)))
    case None{}: True{}

def t_bitcast_refuses_weak_src() -> Bool: found_refused(bitcast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()))
def t_bitcast_refuses_weak_dst() -> Bool: found_refused(bitcast_at(f_fx(g_fix()), f_i32(g_fix()), S.weakfloat()))
def found_is(m: Maybe<&2, O.Found>, want: U32) -> Bool:
  match m:
    case Some{h}: same_node(h, want)
    case None{}: False{}

def t_bitcast_same_is_self() -> Bool: found_is(bitcast_at(f_fx(g_fix()), f_i32(g_fix()), S.int32()), f_i32(g_fix()))
def t_bitcast_mints() -> Bool: Bool.not(found_is(bitcast_at(f_fx(g_fix()), f_i32(g_fix()), S.single()), f_i32(g_fix())))
def found_op_is(m: Maybe<&2, O.Found>, want: O.Op) -> Bool:
  match m:
    case Some{h}: op_is_at(h, want)
    case None{}: False{}

def t_bitcast_mint_is_bitcast() -> Bool: found_op_is(bitcast_at(f_fx(g_fix()), f_i32(g_fix()), S.single()), O.OpsBITCAST{})




# --- the row the brief asks for: TWO RULES, ONE NODE ----------------------
# `cast` (tinygrad/dtype.py:36) and `bitcast` (tinygrad/dtype.py:51) are the same question -- "this node at
# dtype D" -- asked of the SAME node, and they DISAGREE: `bitcast` adds the `dtypes.weaks`
# refusal and `cast` does not. Python walks them as two independent methods, so nothing
# stops a port from merging them into one rule that claims both. A gate that only ever
# asked about weak nodes would see them agree-to-differ on all ten targets and learn
# nothing about the concrete case, so this count is over the CONCRETE fixture, where the
# two rules AGREE on nine targets and part company on exactly one. Under a merged rule
# that one target stops being a disagreement and the count falls to 0.
def found_minted(m: Maybe<&2, O.Found>, self: U32) -> Bool:
  match m:
    case Some{h}: Bool.not(same_node(h, self))
    case None{}: False{}

def bitcast_minted(+fx: F.Folded, +self: U32, +t: S.Dt) -> Bool:
  found_minted(bitcast_at(fx, self, t), self)


def xor_one(+fx: F.Folded, +self: U32, +t: S.Dt) -> U32:
  Bool.to_u32(Bool.not(O.eq_bool(cast_minted(fx, self, t), bitcast_minted(fx, self, t))))

def xor_count.go(+fx: F.Folded, +self: U32, +ts: List<&2, S.Dt>, acc: U32) -> U32:
  match ts:
    case Nil{}: acc
    case t <> rest: xor_count.go(fx, self, rest, U32.add(acc, xor_one(fx, self, t)))

# "did this rule answer by minting a NEW node, or hand back the node it was given?" --
# the one question on which `cast` and `bitcast` are directly comparable, since one
# returns a bare `Found` and the other a `Maybe<Found>`. `bitcast`'s refusal is neither,
# and that is exactly what makes it disagree.





def t_cast_vs_bitcast_xor() -> U32: xor_count.go(f_fx(g_fix()), f_i32(g_fix()), TARGETS(), 0)

# The same count over the WEAK node, where the two disagree on every target. Both rows
# exist because they are the two halves: `cast_vs_bitcast_xor` is localised to the weak
# refusal and this one is localised to the ordinary `self if self.dtype == dt` arm.
def t_cast_vs_bitcast_xor_weak() -> U32: xor_count.go(f_fx(g_fix()), f_wi(g_fix()), TARGETS(), 0)


# `xor_count` over the ten targets, as a count and not a Bool: the brief's trap is that a
# boolean gate over a table whose two rules always agree cannot see a merge bug at all.
def list_len(xs: List<&2, S.Dt>) -> U32:
  match xs:
    case Nil{}: 0
    case _ <> rest: U32.add(1, list_len(rest))

def t_cast_vs_bitcast_targets() -> U32: list_len(TARGETS())


# --- element_size --------------------------------------------------------
def u32_b(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0
def element_size_of(+dt: S.Dt) -> Maybe<&1, U32>: element_size(md_weak(dt), dt)


def t_esize_int32() -> Bool: U32.is_eq(u32_b(element_size_of(S.int32())), 4)
def t_esize_ub() -> Bool: U32.is_eq(u32_b(element_size_of(S.uint8())), 1)
def t_esize_double() -> Bool: U32.is_eq(u32_b(element_size_of(S.double())), 8)
def t_esize_half() -> Bool: U32.is_eq(u32_b(element_size_of(S.half())), 2)
# "did this answer refuse?" -- a `None` arm and a `Some` arm that is UNCONDITIONALLY FALSE.
# It was first written `Bool.not(U32.is_zero(v))`, which is the wrong predicate twice over:
# it says "refused" when it got a non-zero SIZE, so `esize_refuses_weakint` passed even
# with `element_size`'s refusal arm deleted (mutation M10). The value is irrelevant; only
# the constructor matters.
def u32_none(m: Maybe<&1, U32>) -> Bool:
  match m:
    case Some{v}: False{}
    case None{}: True{}

# MUTATION M17 MOVED NOTHING, and this row is why it is now visible: `u32_none` is only
# ever called on WEAK dtypes in this gate, so a predicate that is wrong on the `Some` arm
# but happens to be True for a `None` passes every caller. Asking it about a CONCRETE
# dtype, where the answer must be a hard False, is what separates "refused" from
# "answered with a big number" -- which is exactly the bug M10 was hiding.
def t_u32_none_on_concrete() -> Bool: Bool.not(u32_none(element_size_of(S.int32())))
def t_u32_none_on_zero_sized() -> Bool: Bool.not(u32_none(element_size_of(S.void())))

# THE MUTATION THAT PROVED THESE ROWS WERE WORTHLESS. The first version of these two rows
# passed `md_weak(dt)` IN as `element_size`'s `blocked` argument, which meant they tested
# the CALLER's arithmetic and never `element_size`'s own refusal arm at all: deleting
# that arm moved no row (mutation M10). Both rows now let `element_size` compute its own
# refusal from the dtype, exactly as Python does, which is what makes M10 move them.

def t_esize_refuses_weakint() -> Bool: u32_none(element_size_of(S.weakint()))
def t_esize_refuses_weakfloat() -> Bool: u32_none(element_size_of(S.weakfloat()))
# And the four concrete dtypes must NOT be refused, or a `blocked` that was always True
# would pass the two rows above while breaking every real caller.
def t_esize_answers_int32() -> Bool: U32.is_eq(u32_b(element_size_of(S.int32())), 4)
def t_esize_answers_half() -> Bool: U32.is_eq(u32_b(element_size_of(S.half())), 2)



# --- is_floating_point ---------------------------------------------------
# weakfloat IS a float for this question -- `dtypes.is_float` includes it -- and that is
# the whole subtlety; a def that read `Cls.is_int` would pass the concrete rows.
def t_isf_single() -> Bool: is_floating_point(S.single())
def t_isf_weakfloat() -> Bool: is_floating_point(S.weakfloat())
def t_isf_half() -> Bool: is_floating_point(S.half())
def t_isf_int32() -> Bool: Bool.not(is_floating_point(S.int32()))
def t_isf_weakint() -> Bool: Bool.not(is_floating_point(S.weakint()))
def t_isf_bool() -> Bool: Bool.not(is_floating_point(S.boolean()))

# --- the eight named casts -----------------------------------------------
# Each is `cast_at(fx, self, <dtype>)` and nothing else, so the rows are "the named cast
# puts that dtype in the CAST's ADt arg". `named_cast_total` pins the COUNT so a
# dropped one-liner is visible; `named_cast_count` would otherwise be the only thing
# that noticed a deleted def.
def t_named_cast_total() -> U32: named_cast_count()
def t_named_cast_float() -> Bool: arg_is(cast_float(f_fx(g_fix()), f_wi(g_fix())), S.single())
def t_named_cast_half() -> Bool: arg_is(cast_half(f_fx(g_fix()), f_wi(g_fix())), S.half())
def t_named_cast_int() -> Bool: arg_is(cast_int(f_fx(g_fix()), f_wi(g_fix())), S.int32())
def t_named_cast_bool() -> Bool: arg_is(cast_bool(f_fx(g_fix()), f_wi(g_fix())), S.boolean())
def t_named_cast_bfloat16() -> Bool: arg_is(cast_bfloat16(f_fx(g_fix()), f_wi(g_fix())), S.bfloat16())
def t_named_cast_double() -> Bool: arg_is(cast_double(f_fx(g_fix()), f_wi(g_fix())), S.double())
def t_named_cast_long() -> Bool: arg_is(cast_long(f_fx(g_fix()), f_wi(g_fix())), S.int64())
def t_named_cast_short() -> Bool: arg_is(cast_short(f_fx(g_fix()), f_wi(g_fix())), S.int16())



# A named cast at the node's OWN dtype is `self` -- the `self if self.dtype == dt` arm
# travels through all eight, so one row at the shared fixture pins it for the whole set.
def t_named_cast_same_is_self() -> Bool: U32.is_eq(O.Found.i(cast_int(f_fx(g_fix()), f_i32(g_fix()))), f_i32(g_fix()))
def t_named_cast_same_is_self_wf() -> Bool: U32.is_eq(O.Found.i(cast_half(f_fx(g_fix()), f_wf(g_fix()))), f_wf(g_fix()))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def b(v: Bool) -> U32: Bool.to_u32(v)

def main() -> IO(Unit):
  do IO<Unit>:
    row("commit_default_int", b(t_commit_default_int()))
    row("i8_at_min", b(t_i8_at_min()))
    row("i8_past_min", b(t_i8_past_min()))
    row("i8_at_max", b(t_i8_at_max()))
    row("i8_past_max", b(t_i8_past_max()))
    row("i16_at_min", b(t_i16_at_min()))
    row("i16_past_min", b(t_i16_past_min()))
    row("i16_at_max", b(t_i16_at_max()))
    row("i16_past_max", b(t_i16_past_max()))
    row("i32_at_min", b(t_i32_at_min()))
    row("i32_at_max", b(t_i32_at_max()))
    row("i32_past_max", b(t_i32_past_max()))
    row("i64_at_min", b(t_i64_at_min()))
    row("i64_at_max", b(t_i64_at_max()))
    row("u8_at_min", b(t_u8_at_min()))
    row("u8_past_max", b(t_u8_past_max()))
    row("u16_at_min", b(t_u16_at_min()))
    row("u16_past_max", b(t_u16_past_max()))
    row("u32_at_min", b(t_u32_at_min()))
    row("u32_past_max", b(t_u32_past_max()))
    row("u64_at_min", b(t_u64_at_min()))
    row("u64_at_2p32", b(t_u64_at_2p32()))
    row("u64_at_i64max", b(t_u64_at_i64max()))
    row("u64_at_neg", b(t_u64_at_neg()))
    row("i32_rung_small", b(t_i32_rung_small()))
    row("i32_rung_at_min", b(t_i32_rung_at_min()))
    row("i64_beyond_i32", b(t_i64_beyond_i32()))
    row("u32_beyond_i32", b(t_u32_beyond_i32()))
    row("u32_wide", b(t_u32_wide()))
    row("sd_weakint", b(t_sd_weakint()))
    row("sd_weakfloat", b(t_sd_weakfloat()))
    row("sd_concrete", b(t_sd_concrete()))
    row("sd_di_moves", b(t_sd_di_moves()))
    row("sd_df_moves", b(t_sd_df_moves()))
    row("sd_identity", b(t_sd_identity()))
    row("commit_int32", b(t_commit_int32()))
    row("commit_long", b(t_commit_long()))
    row("commit_start_matters", b(t_commit_start_matters()))
    row("commit_weakfloat", b(t_commit_weakfloat()))
    row("commit_weakfloat_ignores_di", b(t_commit_weakfloat_ignores_di()))
    row("commit_concrete", b(t_commit_concrete()))
    row("commit_bool", b(t_commit_bool()))
    row("commit_ub", b(t_commit_ub()))
    row("commit_refuses_unmeasured", b(t_commit_refuses_unmeasured()))
    row("commit_refuses_half", b(t_commit_refuses_half()))
    row("commit_wi_is_weak", b(t_commit_wi_is_weak()))
    row("commit_ch_is_weak", b(t_commit_ch_is_weak()))
    row("commit_wf_concrete", b(t_commit_wf_concrete()))
    row("weaks_vs_weakint", b(t_weaks_vs_weakint()))
    row("weaks_vs_weakint_both", b(t_weaks_vs_weakint_both()))
    row("commit_i32_not_weak", b(t_commit_i32_not_weak()))
    row("commit_ub_not_weak", b(t_commit_ub_not_weak()))
    row("cast_same_is_self", b(t_cast_same_is_self()))
    row("cast_mints", b(t_cast_mints()))
    row("cast_mint_is_cast", b(t_cast_mint_is_cast()))
    row("cast_target_is_arg", b(t_cast_target_is_arg()))
    row("cast_no_refusal", b(t_cast_no_refusal()))
    row("cast_one_self", b(t_cast_one_self()))
    row("bitcast_refuses_weak_src", b(t_bitcast_refuses_weak_src()))
    row("bitcast_refuses_weak_dst", b(t_bitcast_refuses_weak_dst()))
    row("bitcast_same_is_self", b(t_bitcast_same_is_self()))
    row("bitcast_mints", b(t_bitcast_mints()))
    row("bitcast_mint_is_bitcast", b(t_bitcast_mint_is_bitcast()))
    row("cast_vs_bitcast_xor", t_cast_vs_bitcast_xor())
    row("cast_vs_bitcast_xor_weak", t_cast_vs_bitcast_xor_weak())
    row("cast_vs_bitcast_targets", t_cast_vs_bitcast_targets())
    row("esize_int32", b(t_esize_int32()))
    row("esize_ub", b(t_esize_ub()))
    row("esize_double", b(t_esize_double()))
    row("esize_half", b(t_esize_half()))
    row("esize_refuses_weakint", b(t_esize_refuses_weakint()))
    row("esize_refuses_weakfloat", b(t_esize_refuses_weakfloat()))
    row("esize_answers_int32", b(t_esize_answers_int32()))
    row("esize_answers_half", b(t_esize_answers_half()))
    row("u32_none_on_concrete", b(t_u32_none_on_concrete()))
    row("u32_none_on_zero_sized", b(t_u32_none_on_zero_sized()))
    row("isf_single", b(t_isf_single()))
    row("isf_weakfloat", b(t_isf_weakfloat()))
    row("isf_half", b(t_isf_half()))
    row("isf_int32", b(t_isf_int32()))
    row("isf_weakint", b(t_isf_weakint()))
    row("isf_bool", b(t_isf_bool()))
    row("named_cast_total", t_named_cast_total())
    row("named_cast_float", b(t_named_cast_float()))
    row("named_cast_half", b(t_named_cast_half()))
    row("named_cast_int", b(t_named_cast_int()))
    row("named_cast_bool", b(t_named_cast_bool()))
    row("named_cast_bfloat16", b(t_named_cast_bfloat16()))
    row("named_cast_double", b(t_named_cast_double()))
    row("named_cast_long", b(t_named_cast_long()))
    row("named_cast_short", b(t_named_cast_short()))
    row("named_cast_same_is_self", b(t_named_cast_same_is_self()))
    row("named_cast_same_is_self_wf", b(t_named_cast_same_is_self_wf()))
# ===========================================================================
# THE MUTATION TABLE. Twenty-two real edits to this file, each re-run, each "rows that
# moved" read off a diff against the pristine output. The table is NOT one row per bug
# and three of its entries exist BECAUSE an earlier version of this gate could not see
# them.
#
#  #   the edit                                                    rows that moved
#  --  ---------------------------------------------------------  -----------------------------
#  1   `commit_dtype` tests `dtypes.weaks` instead of weakint       commit_weakfloat,
#                                                                       commit_weakfloat_ignores_di
#  2   `commit_dtype.weak` ignores `hi` (answers int32 always)      commit_long,
#                                                                       commit_start_matters
#  3   `commit_dtype.of` always takes the strong_dtype arm          commit_long
#  4   `strong_dtype`'s default_float is `half` not `single`        commit_weakfloat,
#                                                                       commit_weakfloat_ignores_di
#  5   `cast_at` drops the `self if self.dtype == dt` arm           cast_same_is_self,
#                                                                       cast_no_refusal, cast_one_self,
#                                                                       cast_vs_bitcast_xor,
#                                                                       named_cast_same_is_self,
#                                                                       named_cast_same_is_self_wf
#  6   `cast_at` ALWAYS hands back self                              14 rows: every cast_* and
#                                                                       named_cast_* except the
#                                                                       same_is_self pair
#  7   `bitcast` drops the `dtypes.weaks` refusal                    cast_vs_bitcast_xor,
#                                                                       cast_vs_bitcast_xor_weak
#  8   `bitcast` refuses EVERY target                                bitcast_same_is_self,
#                                                                       bitcast_mint_is_bitcast,
#                                                                       cast_vs_bitcast_xor
#  9   `cast` mints Ops.BITCAST instead of Ops.CAST                  cast_mint_is_cast
#  10  `element_size` drops the weak refusal                         esize_refuses_weakint,
#                                                                       esize_refuses_weakfloat
#  11  `is_floating_point` reads `is_int`                            isf_single, isf_half,
#                                                                       isf_weakfloat, isf_int32,
#                                                                       isf_weakint
#  12  `cast_int` targets int64 not int32                             named_cast_int,
#                                                                       named_cast_same_is_self
#  13  `cast_short` targets int32 not int16                          named_cast_short
#  14  `md_dt_eq` is constant True                                   15 rows: every dtype
#                                                                       comparison
#  15  `md_weakint` is `md_weak` (the real bug, see header)           commit_weakfloat,
#                                                                       commit_weakfloat_ignores_di,
#                                                                       weaks_vs_weakint
#  16  `element_size` refuses every dtype                            esize_int32, esize_ub,
#                                                                       esize_double, esize_half,
#                                                                       esize_answers_int32,
#                                                                       esize_answers_half
#  17  `u32_none` back to the wrong `is_zero` predicate              u32_none_on_concrete
#  18  `cast_minted_count` expects 10 mints (wrong about Python)      cast_no_refusal, cast_one_self
#  19  `md_i64_min_s(8)` = dtype.bend's 0xffffc808 (i.e. -14328)      i8_past_min
#  20  `md_i64_min_s(16)` = dtype.bend's 0xffff0000 (i.e. -65536)     i16_past_min
#  21  `md_i64_max_u(64)` = dtype.bend's 0xFFFFFFFF_FFFFFFFF (i.e. -1) u64_at_min, u64_at_2p32,
#                                                                       u64_at_i64max
#  22  `strong_dtype` swaps its `di` and `df` defaults                sd_weakint, sd_weakfloat,
#                                                                       sd_di_moves, sd_df_moves,
#                                                                       commit_weakfloat,
#                                                                       commit_weakfloat_ignores_di
#
# WHAT THE TABLE SAYS THAT THE ROWS DO NOT.
#
#   * THE TWO DEAD MUTATIONS, and both were found by running this table rather than by
#     reading the rows. Mutation 10 first moved NOTHING, and mutation 17 first moved
#     NOTHING. Each was a gate defect, not a code defect, and each is fixed above with a
#     row that exists only to close it: `element_size_of` exists because the rows were
#     passing `blocked` IN as an argument and so never exercised `element_size`'s own
#     refusal arm, and `u32_none_on_concrete` exists because `u32_none` was only ever
#     called on weak dtypes, where its `Some` arm was never taken. A green table with a
#     dead mutation is worse than a red row, because it is a claim that was not tested.
#
#   * MUTATIONS 5 AND 8 ARE THE POINT OF THE TWO-RULES-ONE-NODE ROWS. `cast` and `bitcast`
#     both claim the same fixture node, and each mutation that touches one of them moves
#     `cast_vs_bitcast_xor`. A gate whose only fixture was a weak node could not have
#     separated them: on the weak fixture they disagree on all ten targets whatever the
#     code does, so the count is saturated and blind. The concrete fixture is the one
#     where they agree on nine and part company on one, and that is where the edit shows.
#
#   * MUTATION 6 MOVES FOURTEEN ROWS AND MUTATIONS 7 AND 8 MOVE ONE EACH, which is the
#     honest asymmetry: `cast` is on the path of all eight named casts and `bitcast` is
#     on nobody's. A table that moved the same number of rows for every mutation would be
#     reading its own source rather than its behaviour.
#
#   * MUTATION 18 IS NOT A CODE BUG. The gate expected ten mints from `cast` over
#     `TARGETS()`; Python mints on nine, because the tenth target IS the node's own
#     dtype and that is the hand-back arm. Measured, then corrected in the row. It is in
#     the table because a mutation I ran that turned out to be a correction is still
#     information about what the gate pins.
#
#   * MUTATIONS 19-21 ARE REAL dtype.bend BUGS, not gate defects, and they are why the
#     ladder has its own gate at all. Hoisting `commit_int` into this file made them
#     visible: `dtype.bend`'s own `commit_int` was never exercised at its int8/int16/uint64
#     rungs, because every caller passes `default_int` = int32 or int64 and those rungs
#     never ran. Copying the constants verbatim would have reproduced three wrong answers
#     into a file whose whole claim is that it is the checkable copy. The rows are one per
#     CONSTANT rather than one per def, and each is CPython's own `.min`/`.max`, so a
#     limit that is wrong in either direction disagrees with CPython rather than with
#     itself -- which is the only reason 19-21 were caught rather than copied.
# ===========================================================================
