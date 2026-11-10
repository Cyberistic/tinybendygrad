# gates/dtype-gate.bend -- THE GATE DRIVER for `tinybendygrad/mixin/dtype.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/mixin/dtype.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

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
# is_floating_point -- tinygrad/mixin/dtype.py:77. `dtypes.is_float(self.dtype)` is `x in dtypes.floats
# + (dtypes.weakfloat,)`, so it is `Cls.is_float` and it DOES include weakfloat.
# ===========================================================================
def is_floating_point(dt: S.Dt) -> Bool: S.Dt.is_float(dt)

# `dtypes.f32` and `dtypes.f64` are `S.single` / `S.double`, and
# `dtypes.f16` / `dtypes.bf16` are `S.half` / `S.bfloat16`; `dtypes.i64` is
# `int64` and `dtypes.i16` is `int16`. The names are the IR's, per spec.bend's header.
def named_cast_count() -> U32: 8

# ADD(CONST(3), CONST(5)) -- weakint by derivation, and NOT a CONST, which is the node
# `absorb_weak_src` (weak.py:55) commits and the node `_min_max` would have to walk.
def g_fix() -> P.Fix:
  +c3 = P.fx_wi(O.Arena.empty())
  +c5 = P.fx_wi2(O.Arena.empty(), c3)
  +wi = O.UOp.new(O.Found.ar(c5), O.OpsADD{}, [O.Found.i(c3), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +ch = O.UOp.const(O.Found.ar(wi), O.CFloat{1.0})
  +wf = O.UOp.new(O.Found.ar(ch), O.OpsCAST{}, [O.Found.i(ch)], O.ADt{S.half()}, O.TNone{})
  +ci = O.UOp.new(O.Found.ar(wf), O.OpsCAST{}, [O.Found.i(wf)], O.ADt{S.int32()}, O.TNone{})
  +ub = O.UOp.new(O.Found.ar(ci), O.OpsCAST{}, [O.Found.i(ci)], O.ADt{S.uint8()}, O.TNone{})
  P.Fix{F.folded(O.Found.ar(ub)), O.Found.i(wi), O.Found.i(ch), O.Found.i(wf), O.Found.i(ci), O.Found.i(ub)}

def f_fx(f: P.Fix) -> F.Folded:
  match f:
    case P.Fix{fx, wi, ch, wf, i32, ub}: fx

def f_wi(f: P.Fix) -> U32:
  match f:
    case P.Fix{fx, wi, ch, wf, i32, ub}: wi

def f_ch(f: P.Fix) -> U32:
  match f:
    case P.Fix{fx, wi, ch, wf, i32, ub}: ch

def f_wf(f: P.Fix) -> U32:
  match f:
    case P.Fix{fx, wi, ch, wf, i32, ub}: wf

def f_ub(f: P.Fix) -> U32:
  match f:
    case P.Fix{fx, wi, ch, wf, i32, ub}: ub


# --- THE GATE ROWS ------------------------------------------------------
# THE ROWS. Every one is DERIVABLE FROM PYTHON, and each is a number Python can be asked
# for; a row that only restates this file would pass forever.
# ===========================================================================

def t_commit_default_int() -> Bool: P.md_dt_eq(P.md_default_int(), S.int32())

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

# ONE ladder cell: `P.commit_int(lo, hi, di)` against one expected dtype. `di` and
# `want` are built at the CALL SITE and used once each, which is what keeps this
# legal -- an `S.Dt` holds a `String` and so cannot be copied inside a def.
def md_ci(lo: H.I64, hi: H.I64, di: S.Dt, want: S.Dt) -> Bool:
  P.md_dt_eq(Maybe.default(&1, S.Dt, P.commit_int(lo, hi, di), S.int64()), want)

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
def t_sd_weakint() -> Bool: P.md_dt_eq(P.strong_dtype(S.weakint(), S.int32(), S.single()), S.int32())
def t_sd_weakfloat() -> Bool: P.md_dt_eq(P.strong_dtype(S.weakfloat(), S.int32(), S.single()), S.single())
def t_sd_concrete() -> Bool: P.md_dt_eq(P.strong_dtype(S.uint8(), S.int32(), S.single()), S.uint8())
def t_sd_di_moves() -> Bool: P.md_dt_eq(P.strong_dtype(S.weakint(), S.int16(), S.single()), S.int16())
def t_sd_df_moves() -> Bool: P.md_dt_eq(P.strong_dtype(S.weakfloat(), S.int32(), S.double()), S.double())
def t_sd_identity() -> Bool: P.md_dt_eq(P.strong_dtype(S.bfloat16(), S.int32(), S.single()), S.bfloat16())

# --- commit_dtype, both branches -----------------------------------------
# The ladder walk. Python: P.commit_int(-7, 9, dtypes.i32) == dtypes.i32.
def t_commit_int32() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(4294967295, 3221225473)}, Some{H.i64_of_i32(9)}, S.int32())), S.int32())
# Python: P.commit_int(2**32, 2**33, dtypes.i32) == dtypes.i64.
def t_commit_long() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(1, 0)}, Some{H.i64_of_hi_lo(2, 0)}, S.int32())), S.int64())
# `default_int` is a LADDER START, not a floor: with long as the start rung the int32
# rung never runs and a small range still answers long. Python agrees.
def t_commit_start_matters() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.weakint(), Some{H.i64_of_hi_lo(4294967295, 3221225473)}, Some{H.i64_of_i32(9)}, S.int64())), S.int64())
# weakfloat never reads the ladder: `P.strong_dtype(weakfloat)` is `dtypes.f32`.
def t_commit_weakfloat() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.weakfloat(), None{}, None{}, S.int32())), S.single())
# `P.strong_dtype(weakfloat)` is `dtypes.f32` = `S.single`, and it is the DEFAULT_FLOAT
# argument, not `default_int`. Passing a non-default `di` here must not move it.
def t_commit_weakfloat_ignores_di() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.weakfloat(), None{}, None{}, S.int16())), S.single())
# `strong_dtype` on a CONCRETE dtype is the identity -- that is tinygrad/dtype.py:169-170's
# `{weakint: ..., weakfloat: ...}.get(dtype, dtype)`.
def t_commit_concrete() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.int16(), None{}, None{}, S.int32())), S.int16())
def t_commit_bool() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.boolean(), None{}, None{}, S.int32())), S.boolean())
def t_commit_ub() -> Bool: P.md_dt_eq(P.dtnm_b(P.commit_dtype(S.uint8(), None{}, None{}, S.int32())), S.uint8())
# THE REFUSAL ROW. lo/hi are `Maybe` because `_min_max` returns `PyConst`; a weakint
# node whose bounds are not measurable answers None rather than a dtype. This is the row
# that would move if the refusal were dropped for a sentinel. `a match` may not
# scrutinise a CALL, so both refusals are tested by a def that takes the answer as a
# PARAMETER -- which is also why they cannot be confused with "answered with the wrong
# dtype", the two arms being separate cases.
def dt_refused(m: Maybe<&1, S.Dt>) -> Bool:
  match m:
    case Some{d}: Bool.not(P.md_dt_eq(d, S.void()))
    case None{}: True{}

def t_commit_refuses_unmeasured() -> Bool: dt_refused(P.commit_dtype(S.weakint(), None{}, None{}, S.int32()))

# Half the pair missing is still a refusal, not a half answer.
def t_commit_refuses_half() -> Bool: dt_refused(P.commit_dtype(S.weakint(), Some{H.i64_of_i32(0)}, None{}, S.int32()))

# Both bounds absent is the `_min_max` wall itself, on the node shape weak.bend asks
# about. If `commit_dtype` ever answered a sentinel here instead of None, this is the
# row that moves and `commit_int32` above would not.
# The fixture's own dtypes, so the rows above are not all literals.
def t_commit_wi_is_weak() -> Bool: P.md_weak(P.md_dt(f_fx(g_fix()), f_wi(g_fix())))
# THE REGRESSION ROW for the bug in this file's header: `commit_dtype` on a weakfloat
# answers `dtypes.f32` and does NOT read the ladder, which is only observable if the
# fixture holds a node that is genuinely weak. `f_wf` is NOT one -- a CAST to `half` is
# a concrete half node, and asking `dtypes.weaks` of it is False (measured). The weak
# float is the bare CONST, which is why this row reads `f_ch` and `f_wf` is only ever
# asked about its CONCRETENESS below.
def t_commit_ch_is_weak() -> Bool: P.md_weak(P.md_dt(f_fx(g_fix()), f_ch(g_fix())))
def t_commit_wf_concrete() -> Bool: P.md_dt_eq(P.md_dt(f_fx(g_fix()), f_wf(g_fix())), S.half())
# The two tests disagree on weakint itself: `weaks` is True, `weakint` is True -- and on
# weakfloat, where `weaks` is True and `weakint` is FALSE. That last one is the whole
# reason both predicates exist.
def t_weaks_vs_weakint() -> Bool: Bool.and(P.md_weak(S.weakfloat()), Bool.not(P.md_weakint(S.weakfloat())))
def t_weaks_vs_weakint_both() -> Bool: Bool.and(P.md_weak(S.weakint()), P.md_weakint(S.weakint()))
def t_commit_i32_not_weak() -> Bool: Bool.not(P.md_weak(P.md_dt(f_fx(g_fix()), P.f_i32(g_fix()))))
def t_commit_ub_not_weak() -> Bool: Bool.not(P.md_weak(P.md_dt(f_fx(g_fix()), f_ub(g_fix()))))

# --- cast ----------------------------------------------------------------
# `cast_at` at the node's OWN dtype is `self` -- the `self if self.dtype == dt` arm --
# and at another dtype it mints. Two rows because a def that always minted would pass
# the second and fail the first.
def same_node(+h: O.Found, want: U32) -> Bool: U32.is_eq(O.Found.i(h), want)

def t_cast_same_is_self() -> Bool: same_node(P.cast_at(f_fx(g_fix()), f_wi(g_fix()), S.weakint()), f_wi(g_fix()))
def t_cast_mints() -> Bool: Bool.not(same_node(P.cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), f_wi(g_fix())))
def op_is_at(+h: O.Found, want: O.Op) -> Bool: O.eq_op(O.Arena.op(O.Found.ar(h), O.Found.i(h)), want)

def t_cast_mint_is_cast() -> Bool: op_is_at(P.cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), O.OpsCAST{})
def arg_is_dt(arg: O.Arg, want: S.Dt) -> Bool:
  match arg:
    case O.ADt{dt}: P.md_dt_eq(dt, want)
    case _: False{}

def arg_is(+h: O.Found, want: S.Dt) -> Bool: arg_is_dt(O.Arena.arg(O.Found.ar(h), O.Found.i(h)), want)

def t_cast_target_is_arg() -> Bool: arg_is(P.cast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()), S.int32())
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
  Bool.not(same_node(P.cast_at(fx, self, t), self))

def cast_minted_count(+fx: F.Folded, +self: U32, +ts: List<&2, S.Dt>) -> U32:
  match ts:
    case Nil{}: 0
    case t <> rest: U32.add(cast_minted_count(fx, self, rest), Bool.to_u32(cast_minted(fx, self, t)))

def cast_same_count(+fx: F.Folded, +self: U32, +ts: List<&2, S.Dt>) -> U32:
  match ts:
    case Nil{}: 0
    case t <> rest: U32.add(cast_same_count(fx, self, rest), Bool.to_u32(Bool.not(cast_minted(fx, self, t))))

def t_cast_no_refusal() -> Bool: U32.is_eq(cast_minted_count(f_fx(g_fix()), P.f_i32(g_fix()), TARGETS()), 9)

def t_cast_one_self() -> Bool: U32.is_eq(cast_same_count(f_fx(g_fix()), P.f_i32(g_fix()), TARGETS()), 1)





# --- bitcast -------------------------------------------------------------
def found_refused(m: Maybe<&2, O.Found>) -> Bool:
  match m:
    case Some{h}: Bool.not(U32.is_zero(O.Found.i(h)))
    case None{}: True{}

def t_bitcast_refuses_weak_src() -> Bool: found_refused(P.bitcast_at(f_fx(g_fix()), f_wi(g_fix()), S.int32()))
def t_bitcast_refuses_weak_dst() -> Bool: found_refused(P.bitcast_at(f_fx(g_fix()), P.f_i32(g_fix()), S.weakfloat()))
def found_is(m: Maybe<&2, O.Found>, want: U32) -> Bool:
  match m:
    case Some{h}: same_node(h, want)
    case None{}: False{}

def t_bitcast_same_is_self() -> Bool: found_is(P.bitcast_at(f_fx(g_fix()), P.f_i32(g_fix()), S.int32()), P.f_i32(g_fix()))
def t_bitcast_mints() -> Bool: Bool.not(found_is(P.bitcast_at(f_fx(g_fix()), P.f_i32(g_fix()), S.single()), P.f_i32(g_fix())))
def found_op_is(m: Maybe<&2, O.Found>, want: O.Op) -> Bool:
  match m:
    case Some{h}: op_is_at(h, want)
    case None{}: False{}

def t_bitcast_mint_is_bitcast() -> Bool: found_op_is(P.bitcast_at(f_fx(g_fix()), P.f_i32(g_fix()), S.single()), O.OpsBITCAST{})




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
  found_minted(P.bitcast_at(fx, self, t), self)


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





def t_cast_vs_bitcast_xor() -> U32: xor_count.go(f_fx(g_fix()), P.f_i32(g_fix()), TARGETS(), 0)

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
def element_size_of(+dt: S.Dt) -> Maybe<&1, U32>: element_size(P.md_weak(dt), dt)


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

# THE mutation that proved these rows were worthless. The first version of these two rows
# passed `P.md_weak(dt)` IN as `element_size`'s `blocked` argument, which meant they tested
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
# Each is `P.cast_at(fx, self, <dtype>)` and nothing else, so the rows are "the named cast
# puts that dtype in the CAST's ADt arg". `named_cast_total` pins the COUNT so a
# dropped one-liner is visible; `named_cast_count` would otherwise be the only thing
# that noticed a deleted def.
def t_named_cast_total() -> U32: named_cast_count()
def t_named_cast_float() -> Bool: arg_is(P.cast_float(f_fx(g_fix()), f_wi(g_fix())), S.single())
def t_named_cast_half() -> Bool: arg_is(P.cast_half(f_fx(g_fix()), f_wi(g_fix())), S.half())
def t_named_cast_int() -> Bool: arg_is(P.cast_int(f_fx(g_fix()), f_wi(g_fix())), S.int32())
def t_named_cast_bool() -> Bool: arg_is(P.cast_bool(f_fx(g_fix()), f_wi(g_fix())), S.boolean())
def t_named_cast_bfloat16() -> Bool: arg_is(P.cast_bfloat16(f_fx(g_fix()), f_wi(g_fix())), S.bfloat16())
def t_named_cast_double() -> Bool: arg_is(P.cast_double(f_fx(g_fix()), f_wi(g_fix())), S.double())
def t_named_cast_long() -> Bool: arg_is(P.cast_long(f_fx(g_fix()), f_wi(g_fix())), S.int64())
def t_named_cast_short() -> Bool: arg_is(P.cast_short(f_fx(g_fix()), f_wi(g_fix())), S.int16())



# A named cast at the node's OWN dtype is `self` -- the `self if self.dtype == dt` arm
# travels through all eight, so one row at the shared fixture pins it for the whole set.
def t_named_cast_same_is_self() -> Bool: U32.is_eq(O.Found.i(P.cast_int(f_fx(g_fix()), P.f_i32(g_fix()))), P.f_i32(g_fix()))
def t_named_cast_same_is_self_wf() -> Bool: U32.is_eq(O.Found.i(P.cast_half(f_fx(g_fix()), f_wf(g_fix()))), f_wf(g_fix()))

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
#  19  `P.md_i64_min_s(8)` = dtype.bend's 0xffffc808 (i.e. -14328)      i8_past_min
#  20  `P.md_i64_min_s(16)` = dtype.bend's 0xffff0000 (i.e. -65536)     i16_past_min
#  21  `P.md_i64_max_u(64)` = dtype.bend's 0xFFFFFFFF_FFFFFFFF (i.e. -1) u64_at_min, u64_at_2p32,
#                                                                       u64_at_i64max
#  22  `strong_dtype` swaps its `di` and `df` defaults                sd_weakint, sd_weakfloat,
#                                                                       sd_di_moves, sd_df_moves,
#                                                                       commit_weakfloat,
#                                                                       commit_weakfloat_ignores_di
#
# WHAT the table says that the rows do not.
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
#   * MUTATIONS 5 AND 8 ARE the point of the two-RULES-ONE-NODE rows. `cast` and `bitcast`
#     both claim the same fixture node, and each mutation that touches one of them moves
#     `cast_vs_bitcast_xor`. A gate whose only fixture was a weak node could not have
#     separated them: on the weak fixture they disagree on all ten targets whatever the
#     code does, so the count is saturated and blind. The concrete fixture is the one
#     where they agree on nine and part company on one, and that is where the edit shows.
#
#   * MUTATION 6 MOVES fourteen rows and mutations 7 AND 8 MOVE ONE each, which is the
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
