# mixin/dtype.bend -- tinygrad/mixin/dtype.py. `DTypeMixin`, the twelve methods every
# UOp-carrying object answers, and ONE of them is the wall `uop/weak.bend` is waiting on.
#
# WHAT IS IN HERE. `mixin/dtype.py` is 142 lines of which 126 are docstrings, and the
# docstrings are `exec="true"` doctests over a live Tensor -- there is no Tensor here to exec
# against, so they are prose below and the defs are the port. Sixteen defs in Python;
# fourteen are bodies here and two are the abstract properties Python raises
# `NotImplementedError` from, which are declarations and not ports.
#
# THE WALL IS ONE LINE: upstream's `commit_dtype`
# (tinygrad/mixin/dtype.py:17 symbol=commit_dtype) reads `self._uop.vmin` and
# `self._uop.vmax` (upstream's `vmin`/`vmax`, tinygrad/uop/ops.py:1090
# symbol=vmin), and THOSE ARE `UOp._min_max` (tinygrad/uop/ops.py:1094
# symbol=_min_max). This file ports
# `commit_dtype` COMPLETELY -- the weakint branch, the `strong_dtype` branch, the
# `default_int` default -- and takes `(lo, hi)` as parameters, because `_min_max` is ops.py's
# def and ops.py is not this file. What that buys is the whole of `commit_int`
# (tinygrad/dtype.py:314), which `tinybendygrad/dtype.bend` already had.
#
# `uop/weak.bend`'s header says `tinybendygrad/dtype.bend` "is unreachable to any importer
# (it prints a foreign-code notice for `Dt.bf16`, `Dt.fp16`, the `fp8_*` and the `i64_*` /
# `float_to_*` helpers)", and that is why weak.bend RECOPIES `strong_dtype` and
# `weak_dtype`. That claim is now TRUE for this file too, and this file is where it stops
# being an excuse: `commit_int` and `strong_dtype` are RECOPIED below, in this file, under the
# notice that names them, and the `import ./../dtype.bend` line is GONE, so `--check-only`
# here is `ALL PROOFS CHECK` and this file is importable by anything. WHAT the re-COPY IS and
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
#   ADD                                 i64_add, i64_sub        PRESENT, pure -- helpers.bend:1687,1733
#   MAX/CMPLT/CMPNE/OR/AND-bool/XOR      i64_le/i64_cmp          PRESENT, pure -- helpers.bend:1662,1696
#   WHERE/PAD/STACK/MOVEMENT/CONST       (no arith)              PORTABLE, they are min/max over srcs
#   CAST (truncation)                   i64 trunc toward zero   `Dt.i64_trunc` -- dtype.bend:534, but
#                                                                       an `IO(F32)`-style EFFECT SEAM
#   MUL                                 i64_mul                 NOWHERE. Not helpers.bend, not
#                                                                       dtype.bend, not any tinygrad .py.
#   TRUNCDIV/DIV                       i64_div                 `Dt.i64_cdiv` / `Dt.i64_floor_div` --
#                                                                       dtype.bend:545,563, EFFECT SEAMS
#   MOD/TRUNCMOD                       i64_mod                 `Dt.i64_floor_mod` / `Dt.i64_cmod` --
#                                                                       dtype.bend:541,571, EFFECT SEAMS
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

# THE READERS. `dtype` is `DTypeMixin.dtype` (tinygrad/dtype.py:10), a property every carrier
# answers with the node's own dtype, and Bend refuses the mutual recursion Python breaks
# with a property, so it is a read of the FOLD -- the same reason `uop/weak.bend`'s
# `wk_dt` is one. `void` is the dead default and it is a LATTICE BOTTOM, so it poisons
# a promotion rather than reading as some other dtype.

def md_dt(+fx: F.Folded, i: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), i), S.void())

def md_ar(fx: F.Folded) -> O.Arena: F.Folded.ar(fx)

# `O.eq_dt`. `uop/weak.bend` carries a local `wk_eq_dt` because ops.bend's ladder was
# missing `CWeakFloat`; the port's `uop/ops.bend` now has all seven arms, so the workaround is
# stale and this file uses the shared one. REPORTED, not fixed.
def md_dt_eq(x: S.Dt, y: S.Dt) -> Bool: O.eq_dt(x, y)

# TWO weakness tests, AND they are not the same question. This is the one real bug the
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
#     the answers agree -- dtype.bend:471-474 records this and it is unchanged.
#   * the ladder starts at default_int, which may already be int32, so the int32 test
#     runs twice in that case. That is dtype.py's behaviour, kept.

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

# CORRECTED: dtype.bend:362-363 read (0xFFFFFF80 -> 0xffffc808) and (0xFFFF8000 ->
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

# A PARAM WITH NO `vmin_vmax` -- the `cd_none` row of `gates/wk-cd-gate.py`. The bound
# reads as `Bnd{NInf}` / `Bnd{PInf}` (a saturation, since `weakint`'s bits == 800 has no
# 64-bit magnitude), and `wk_bnd_i64` cannot convert infinity to an I64, so `m`/`m2` are
# `None`. CPython's `commit_int` would answer `long` for this case: the no-bounds PARAM's
# interval is `[NInf, PInf]`, which is wider than int32 (and wider than the ladder's
# `default_int` rung), so the ladder falls off the end at `long`. THE PORT'S HONEST ANSWER
# IS THE SAME -- supply the WIDEST int range we can represent, which `commit_int` sees as
# "does not fit int32" and answers `int64`. The earlier version returned `None`, which is
# what `wk-cd-gate.py`'s `cd_none` row was pinned as a divergence on; the fix closes it.
def commit_dtype.weak(m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  commit_int(
    Maybe.default(&1, H.I64, m, md_i64_min_s(64)),
    Maybe.default(&1, H.I64, m2, md_i64_max_s(64)),
    di)

def commit_dtype.of(weakint: Bool, +dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  match weakint:
    case True{}: commit_dtype.weak(m, m2, di)
    case False{}: Some{strong_dtype(dt, di, S.single())}

def commit_dtype(+dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, di: S.Dt) -> Maybe<&1, S.Dt>:
  commit_dtype.of(md_weakint(dt), dt, m, m2, di)

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

def cast_at.of(same: Bool, +fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  match same:
    case True{}: O.Found{md_ar(fx), self}
    case False{}: O.UOp.new(md_ar(fx), O.OpsCAST{}, [self], O.ADt{dt}, O.TNone{})

def cast_at(+fx: F.Folded, +self: U32, +dt: S.Dt) -> O.Found:
  cast_at.of(md_dt_eq(md_dt(fx, self), dt), fx, self, dt)

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

# THE EIGHT NAMED CASTS -- tinygrad/dtype.py:79-142. Python spells each as `return self.cast(dtypes.X)`
# and a docstring, so each is one line here and there is no rule table: a table plus a
# dispatch would be 40 lines to say what eight one-liners say, and there is no `UPat` in
# `mixin/dtype.py` to be a tag for. The eight targets are `S.single`, `S.half`,
# `S.int32`, `S.boolean`, `S.bfloat16`, `S.double`, `S.int64`, `S.int16` -- dtype.py's
# order is float32, float16, int32, bool, then bfloat16, double, long, short.

def cast_float(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.single())
def cast_half(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.half())
def cast_int(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int32())
def cast_bool(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.boolean())
def cast_bfloat16(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.bfloat16())
def cast_double(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.double())
def cast_long(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int64())
def cast_short(+fx: F.Folded, +self: U32) -> O.Found: cast_at(fx, self, S.int16())

# THE FIXTURE. One weakint node (ADD of two int CONSTs), one weakfloat node (a bare
# half CONST), and one int32 node, so the three dtype classes `dtypes.weaks` and the
# two concrete classes all appear and every row below reads a real fold rather than a
# literal.

type Fix is Data:
  Fix{fx: F.Folded, wi: U32, ch: U32, wf: U32, i32: U32, ub: U32}

def fx_wi(ar: O.Arena) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(3)})

def fx_wi2(ar: O.Arena, +a: O.Found) -> O.Found: O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(5)})

def f_i32(f: Fix) -> U32:
  match f:
    case Fix{fx, wi, ch, wf, i32, ub}: i32

# `commit_dtype`'s answer, unwrapped. `void` is the dead default and it is a LATTICE
# BOTTOM, so a caller that unwraps a refusal gets something that poisons a promotion
# rather than something that reads as a real dtype.
def dtnm_b(m: Maybe<&1, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()
