# transcendental.bend -- tinygrad/codegen/decomp/transcendental.py (277 lines).
#
# THE GRAPH HALF.  `tinybendygrad/codegen/transcendental_f32.bend` ports the OTHER
# half of these same 277 lines -- the COEFFICIENTS and the float32 VALUES -- and
# the two are complementary, not duplicates.  Both headers state the split; read
# that one for why they are not merged (two oracles, and a 0.17 s coefficient lane
# against a 21 min value lane).  Neither file imports the other.
#
# THE SOFTWARE TRANSCENDENTAL EXPANSIONS: `exp2`/`log2`/`sin`/`sqrt` as
# polynomial-plus-bit-trick trees, and the seven-entry pattern table that fires
# them. `decomp.bend` is the sibling (`decomp/op.py`); its header says so and it
# carries NONE of this.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against transcendental.py's 277 lines. Python's
# order is kept; two blocks move and each says why.
#
#   #  PY        KIND    STATE
#   1  7         data    TRANSCENDENTAL_DTYPES      PORTED, a dtype CLASS test
#   2  9-11      fold    _lazy_map_numbers          PORTED IN FULL
#   3  14        fold    mantissa_bits              PORTED (the finfo TABLE)
#   4  15        fold    exponent_bias              PORTED (the fp8_fnuz arm too)
#   5  16        fold    exponent_mask              PORTED
#   6  19        fold    shr                        PORTED, the UOp arm DEAD
#   7  20        fold    shl                        PORTED, the UOp arm DEAD
#   8  22-25     fold    rintk                      PORTED IN FULL
#   9  27-30     fold    pow2if                     PORTED IN FULL
#  10  32-37     fold    ilogb2k                    PORTED IN FULL
#  11  39-45     fold    ldexp3k                    PORTED IN FULL
#  12  47-50     fold    ldexp2k                    PORTED IN FULL
#  13  52-63     fold    frexp                      PORTED IN FULL
#  14  66-113    fold    payne_hanek_reduction      PORTED IN FULL
#  15  115-147   fold    cody_waite_reduction       PORTED IN FULL
#  16  150       fold    trig_poly                  PORTED IN FULL (polyN)
#  17  152-156   fold    sin_poly                   PORTED IN FULL
#  18  158       fold    _ifand                     PORTED IN FULL
#  19  160-162   fold    sin_poly_small             PORTED IN FULL
#  20  164-166   fold    sin_poly_large             PORTED IN FULL
#  21  170-191   fold    xsin                       PORTED IN FULL
#  22  193-217   fold    xexp2                      PORTED IN FULL
#  23  219-255   fold    xlog2                      PORTED IN FULL
#  24  257-265   fold    xpow                       PORTED IN FULL
#  25  267-277   table   get_transcendental_patterns PORTED, 5 tables, <=7 rules
#  26  helpers   fold    polyN                      PORTED IN FULL (helpers.py:153)
#
# ---------------------------------------------------------------------------
# THE HEADLINE MEASUREMENT: THERE IS NO 64-BIT ARITHMETIC IN THIS FILE, and the
# brief predicted there would be. The prediction is wrong for a structural reason
# worth stating: transcendental.py BUILDS GRAPHS, it does not EVALUATE them.
# Every `*`, `//`, `&`, `<<` here is an `Ops` node, so `_hp_mul` -- the one place
# a real 32x32 product appears, at line 103 -- is a `MUL` node on two `uint64`
# operands and the host never multiplies anything. The 64-bit things that DO
# appear are CONSTANTS:
#     2**62          line 108, `shr(p, 62)`
#     0x3fff...ffff  line 109, the mantissa mask
#     2**32          line 105, `shl(_, 32)`
#     0x3FE0000000000000 / 0x000FFFFFFFFFFFFF   lines 56-57, `frexp`'s masks
# and a CONST is `CInt{H.I64}`, so `H.i64_of_hi_lo` mints all of them. So
# `helpers.bend` needs NONE of `i64_mul`/`i64_div`/`i64_mod`/`i64_shl` for this
# file, and this file is the only caller. `n_ph` -- 116 nodes, the largest single
# reduction in the gate -- is reached with nothing but `UOp.alu` and
# `H.i64_of_hi_lo`.
#
# ---------------------------------------------------------------------------
# SIX THINGS THAT ARE EASY TO GET WRONG, and the row that holds each down.
#
# 1. `shr`/`shl` (lines 19-20) TAKE A `UOp` `y` AND CALL `y.simplify().val`.
#    EVERY ONE OF THE ELEVEN CALL SITES IN THIS FILE PASSES A PYTHON `int`.
#    MEASURED by regex over the source. So the fold is DEAD here and
#    `tx_shr`/`tx_shl` are `FLOORDIV`/`MUL` by a CONST, NOT `SHR`/`SHL` -- and
#    `ldexp2k`, which DOES take a symbolic `e`, survives without the fold
#    because the `y` it shifts by is the literal `1`. `a_ilogb9` is the row.
# 2. `_reduce_d` (lines 121-142) RECURSES on the float16 arm -- into float32,
#    which cannot recurse. Two levels, so `tx_cw32`/`tx_cw64` are two defs and
#    the float16 arm is `tx_cw32(...)` then one CAST. A self-call on a `Dt`
#    parameter is not decreasing, so the unroll is not a convenience: it is the
#    only total reading.
# 3. `_take` (lines 88-92) TAKES `offset` FROM A LIST COMPREHENSION that
#    SHADOWS the enclosing `i`, so `offset` is a Python `int` 0..3 and
#    `count+offset < len(two_over_pi_f)-1` is a COMPILE-TIME test -- while
#    `i.ne(count)` inside the body is the OUTER `i`, a UOp. Both halves matter:
#    `ph_take`'s fuel is `6 - offset`, its table index is `offset+count`, and
#    it must intern the CONST AFTER the recursive call, because Python evaluates
#    `i.ne(count).where(_take(...), an.const_like(...))` left to right. `a_ph`
#    pins all eighteen `WHERE`s in their intern order.
# 4. `qdh` (line 145) IS BUILT UNCONDITIONALLY and is DEAD for float32 and
#    float16 -- only the float64 arm of `_reduce_d` reads it. A root-walking
#    oracle would not see those nine nodes; this one prints every node interned,
#    so `n_cw` counts them and the port builds them. Divergence B's note.
# 5. `dtypes.finfo` (dtype.py:113) IS NOT `(bits-1-x, ...)`: bfloat16 and
#    float16 both have `bits == 16` and mantissas 7 and 10. It is a TABLE, and
#    `mt_f16`/`mt_f32`/`mt_f64` are its three rows here.
# 6. `polyN` (helpers.py:153) IS SEEDED WITH THE PYTHON FLOAT `0.0`, so its
#    FIRST step is a real `MUL(C(0.0), x)` and not a fold-away. A port that
#    starts the Horner at `c[0]` builds five fewer nodes in `sin_poly` alone
#    and `a_sp9` is the row.
#
# ---------------------------------------------------------------------------
# TWO DIVERGENCES, stated rather than hidden.
#
# A. NO PROMOTION CASTS and NO `UOp.const` FOLD. `mixin/elementwise.py`'s
#    `_broadcasted` casts a non-CONST operand up to the least upper dtype, and
#    `ops.py:638` writes `UOp.const` as `CONST(b).cast(dtype)`. `ops.bend`'s
#    `UOp.new` runs the first and its `UOp.const` IS the second, because the
#    port's `Const` carries the VALUE and a bare CONST node has no dtype to
#    promote into. Both sets are MEASURED -- `.agents/slop/tx-arena.py` traces
#    `_broadcasted` and `UOp.const` -- and both are erased by the oracle and
#    absent here. `decomp.bend`'s divergence A is the first half; this is the
#    second, and it is why `a_rintk2` is a `CONST` where Python prints
#    `CAST(CONST)`.
#    EVERY OTHER CAST IS KEPT. `rintk`'s output cast, `frexp`'s bitcasts,
#    `cody_waite`'s `int64` round trip and `payne_hanek`'s `_shl_lazy`/
#    `_shr_lazy` are EXPLICIT `.cast()`s, `ops.bend` can build them, and keeping
#    them pins twice as much per row. The oracle's shape-based erasure
#    (`arg != src.dtype`, which is what decomp.bend's oracle uses) is TOO COARSE
#    for this file and is NOT used: it eats `cody_waite`'s `.cast(int64)`, merges
#    two arena slots into one, and silently rewires every src index.
# B. A CONST HAS NO DTYPE IN THE PORT. Python's `CONST` derives one
#    (`ops.py:186`: `weakint`/`weakfloat`/`bool`) and `UOp.const(b, dt)` folds
#    it into the value; the port's `Const` is `CInt{H.I64}`/`CFloat{F32}` and a
#    bare CONST node has no dtype field. So the ORACLE prints `ci`/`cf`/`cb` --
#    which encode the value KIND and therefore the weak dtype -- and nothing
#    else about it, and no non-CONST row carries a dtype at all. Consequence:
#    the f16 and f64 arms of `cody_waite_reduction` build the same tree over
#    DIFFERENT constants, and `a_cw` is the float32 window only. The f16 and f64
#    windows are P3, not claims.
#
# ---------------------------------------------------------------------------
# WHERE THE GATES COME FROM. `codegen/__init__.py:360` calls
# `get_transcendental_patterns(supported_ops, TRANSCENDENTAL>=2)`, so `ops` and
# `force` are PARAMETERS here -- `tx_tab` takes five Bools and returns a `Data`
# table -- because `Config` does not exist in Bend and neither does a renderer.
# `supports_float4` (renderer/__init__.py:67, set False by wgsl.py:58) is NOT
# reachable from this file: MEASURED, the identifier occurs nowhere in
# transcendental.py or in anything it calls. `TRANSCENDENTAL` is the only flag
# and it is `force`.
#
# THE GATE. `main` prints one row per claim; both lanes must print the same rows
# and `.agents/slop/tx-arena.py` prints the reference. The rows are
#   mt_/eb_/em_   the three finfo-derived values, per TRANSCENDENTAL dtype
#   n_<tag>       nodes ADDED by one expansion, over a FRESH arena
#   a_<tag>       every one of those nodes, in intern order, with src indices
#   n_<tab>       the pattern-table size for one `ops`/`force` pair
#   e_<tab><i>    one table entry: ops|early_reject|match_dtype|name
#   sw<n>         `xsin`'s `switch_over` CONST, for two parameter values
# The `a_` rows are the whole tree at EVERY depth, so nothing is hidden behind a
# two-level print and a dropped leaf moves a row.

import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O

# ===========================================================================
# THE NODE BUILDERS. `mixin/elementwise.py` IS NOT PORTED, so every operator
# below is the RAW `alu`, and decomp.bend's divergence B applies here too: `x - y`
# is `ADD(x, MUL(y, C(-1)))` and this file writes `-` in three places and never a
# `SUB`.
# ===========================================================================
def tx_ci(+ar: O.Arena, +v: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})

def tx_ci64(+ar: O.Arena, +x: H.I64) -> O.Found:
  O.UOp.const(ar, O.CInt{x})

def tx_cf(+ar: O.Arena, +v: F32) -> O.Found:
  O.UOp.const(ar, O.CFloat{v})

# `-0.0` IS ITS OWN CONST IN TINYGRAD -- MEASURED, `UOp.const(-0.0) is
# UOp.const(0.0)` is False, and `a_xlog2 70` is `cf2147483648` -- and
# `ops.bend`'s `eq_const.CFloat` (ops.bend:1406) tests `F32.is_eq(f, g)`, which
# IEEE says is TRUE of `+0.0` and `-0.0`. So the port's arena would fold the two
# into one node and `a_xlog2 70`..`a_xlog2 78` would all shift. REPORTED, not
# fixed -- ops.bend is read-only to this unit -- and worked around here by pushing
# the node the way `intern.put` does. It is used ONCE in this file, so the loss of
# dedup is not observable; a second use would need `intern.find` on the bits.
def tx_cf_neg0(+ar: O.Arena) -> O.Found:
  +i = O.Arena.next(ar)
  O.Found{O.intern.put(ar, O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CFloat{F32.neg(0.0)}}, O.TNone{}}), i}

# `2**y` for the Python-int `y` every `shr`/`shl` in this file gets.
# `H.i64_of_i32` SIGN-EXTENDS, so `1 << 31` would come out negative; the two
# halves are therefore chosen and `2**62` needs the high word.
def tx_powi.go(wide: Bool, +y: U32) -> H.I64:
  match wide:
    case True{}: H.i64_of_hi_lo(U32.shln(1, U32.to_nat(U32.sub(y, 32))), 0)
    case False{}: H.i64_of_hi_lo(0, U32.shln(1, U32.to_nat(y)))

def tx_powi(+y: U32) -> H.I64:
  tx_powi.go(U32.is_ge(y, 32), y)

def tx_pow2(+ar: O.Arena, +y: U32) -> O.Found:
  +p = tx_powi(y)
  tx_ci64(ar, p)

def tx_alu1(+ar: O.Arena, +op: O.Op, +x: U32) -> O.Found:
  O.UOp.alu(ar, op, [x])

def tx_alu2(+ar: O.Arena, +op: O.Op, +x: U32, +y: U32) -> O.Found:
  O.UOp.alu(ar, op, [x, y])

def tx_alu3(+ar: O.Arena, +op: O.Op, +x: U32, +y: U32, +z: U32) -> O.Found:
  O.UOp.alu(ar, op, [x, y, z])

def tx_cbo(+ar: O.Arena, b: Bool) -> O.Found:
  match b:
    case True{}: O.UOp.const(ar, O.CBool{True{}})
    case False{}: O.UOp.const(ar, O.CBool{False{}})

def tx_cb(+ar: O.Arena, b: Bool) -> O.Found:
  tx_cbo(ar, b)

# `logical_not` -- mixin/elementwise.py:57, `self.cast(dtypes.bool).ne(True)`. The
# CAST ELIDES because the receiver is already a bool (mixin/dtype.py:19), so this
# is a `CMPNE` against a BOOL CONST and not against an int 1. `a_xexp2 65` is the
# row and a port that wrote `C(1)` there builds a different node.
def tx_lnot(+ar: O.Arena, +x: U32) -> O.Found:
  +t = tx_cb(ar, True{})
  tx_alu2(O.Found.ar(t), O.OpsCMPNE{}, x, O.Found.i(t))

def tx_cast(+ar: O.Arena, +x: U32, +dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsCAST{}, [x], O.ADt{dt}, O.TNone{})

def tx_bitcast(+ar: O.Arena, +x: U32, +dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBITCAST{}, [x], O.ADt{dt}, O.TNone{})

# `shr`/`shl` -- lines 19-20, and header note 1.
def tx_shr(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +c = tx_pow2(ar, y)
  tx_alu2(O.Found.ar(c), O.OpsFLOORDIV{}, x, O.Found.i(c))

def tx_shl(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +c = tx_pow2(ar, y)
  tx_alu2(O.Found.ar(c), O.OpsMUL{}, x, O.Found.i(c))

# ===========================================================================
# `dtypes.finfo` -- dtype.py:113, `(exponent, mantissa)`. A TABLE, not a
# formula; header note 5. `Dt.pri` is the discriminant and it is unique per
# dtype, so one `match` on the binder reads the whole table.
# ===========================================================================
def tx_finfo_e(dt: S.Dt) -> U32:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 10: 4
        case 11: 5
        case 12: 5
        case 13: 8
        case 14: 8
        case _: 11

def tx_finfo_m(dt: S.Dt) -> U32:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 10: 3
        case 11: 2
        case 12: 10
        case 13: 7
        case 14: 23
        case _: 52

# `d in dtypes.fp8_fnuz` -- the two fnuz layouts, the only dtypes with no
# exponent bias, and the only reason `exponent_bias` is not a constant shift.
# `pri` cannot separate `fp8e4m3` from `fp8e4m3fnuz`, so the NAME is the test.
def tx_is_fnuz.nm(nm: String) -> Bool:
  match nm:
    case "fp8e4m3fnuz": True{}
    case "fp8e5m2fnuz": True{}
    case _: False{}

def tx_is_fnuz(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: tx_is_fnuz.nm(nm)

def tx_powi32(+y: U32) -> U32:
  U32.shln(1, U32.to_nat(y))

# `(1 << (exponent - 1)) - (0 if d in fp8_fnuz else 1)` -- line 15. The shift is
# on `exponent - 1`, NOT on `exponent`: an 8-bit exponent field gives a 127 bias
# and `1 << 8` would give 255. `eb_f32` is the row that says so.
def exponent_bias.go(bias0: Bool, dt: S.Dt) -> U32:
  match bias0:
    case True{}: tx_powi32(U32.sub(tx_finfo_e(dt), 1))
    case False{}: U32.sub(tx_powi32(U32.sub(tx_finfo_e(dt), 1)), 1)

def exponent_bias(+dt: S.Dt) -> U32:
  exponent_bias.go(tx_is_fnuz(dt), dt)

def mantissa_bits(dt: S.Dt) -> U32:
  tx_finfo_m(dt)

def exponent_mask(dt: S.Dt) -> U32:
  U32.sub(tx_powi32(tx_finfo_e(dt)), 1)

# `TRANSCENDENTAL_DTYPES` -- line 7 -- and its complement inside `dtypes.floats`,
# which is the SECOND `dtype=` conjunct of every second pattern in the table.
# `pri` is the whole test: 12/14/15 against 10/11/13.
def tx_is_tt.pri(pri: U32) -> Bool:
  match pri:
    case 12: True{}
    case 14: True{}
    case _: U32.is_eq(pri, 15)

def tx_is_tt(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: tx_is_tt.pri(pri)

# `intermediate_dtype = dtypes.f32 if d.dtype == dtypes.f16 else
# d.dtype` -- payne_hanek line 79. float16 is the ONLY TRANSCENDENTAL dtype whose
# intermediate differs from itself, so `same` -- "does `f.cast(intermediate)`
# elide" -- is float16's negation. `a_ph25` is the float32 row: True.
def tx_same(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: U32.is_ne(pri, 12)

def tx_f16(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: U32.is_eq(pri, 12)

# `d.dtype == dtypes.f64` (line 123, 146) and `x.dtype == dtypes.f16`
# (line 133) are the TWO `cody_waite_reduction` guards and they are separate facts
# about the same dtype, so two defs. They are also NOT negations of each other --
# float32 is neither -- so no arm here reads `Bool.not`.
def tx_d64(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: U32.is_eq(pri, 15)

# ===========================================================================
# THE BIT TRICKS. `rintk` -- lines 22-25. The output dtype is the int width of
# the same name, and `d.const_like(-0.5)` is a CONST of `d`'s dtype: the port has
# ONE float width (divergence B) so `tx_cf` mints it and the dtype rides along in
# the value.
# ===========================================================================
def tx_int_dt(dt: S.Dt) -> S.Dt:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 12: S.int16()
        case 14: S.int32()
        case _: S.int64()

# `dt` IS `d`'s OWN FLOAT DTYPE and the OUTPUT dtype is derived here, because
# that is the one reading of line 24 that every caller shares. A caller that
# pre-converts double-converts: `tx_int_dt(S.int32())` is not `S.int32()` but
# `S.int64()` (pri 5 is neither 12 nor 14), and the rintk CAST comes out `long`
# where the oracle says `int` -- `a_cw 23`, `a_xsinf 39`, `a_xsin 143`.
def tx_rintk(+ar: O.Arena, +d: U32, +dt: S.Dt) -> O.Found:
  +z = tx_cf(ar, 0.0)
  +c = tx_alu2(O.Found.ar(z), O.OpsCMPLT{}, d, O.Found.i(z))
  +nm = tx_cf(O.Found.ar(c), F32.neg(0.5))
  +ph = tx_cf(O.Found.ar(nm), 0.5)
  +w = tx_alu3(O.Found.ar(ph), O.OpsWHERE{}, O.Found.i(c), O.Found.i(nm), O.Found.i(ph))
  +s = tx_alu2(O.Found.ar(w), O.OpsADD{}, d, O.Found.i(w))
  tx_cast(O.Found.ar(s), O.Found.i(s), tx_int_dt(dt))

# `x - y` -- decomp.bend's divergence B, restated because this file writes `-` in
# four places (`xexp2`'s `x - q`, `ldexp2k`, `ilogb2k`, `cody_waite_reduction`)
# and never a `SUB`.
#
# `pf` IS NOT COSMETIC. `-1` IS A PYTHON INT LITERAL and `_broadcasted` re-mints
# it to a float ONLY when the other operand is a float: `xexp2` subtracts floats,
# so `a_xexp2 25` is a SECOND CONST and the MUL reads it, while `ldexp2k` and
# `ilogb2k` subtract int32s, the weakint passes through unchanged, and
# `a_ldexp2 17` and `a_ilogb 16` read the int. One flag, and it is the
# difference between `n_ldexp2` 23 and 24.
def tx_sub.i(+ar: O.Arena, +x: U32, +y: U32, +n: O.Found) -> O.Found:
  +m = tx_alu2(O.Found.ar(n), O.OpsMUL{}, y, O.Found.i(n))
  tx_alu2(O.Found.ar(m), O.OpsADD{}, x, O.Found.i(m))

# `self * (-1)` -- elementwise.py:77, `neg`. `-1` IS A PYTHON INT, so `_broadcasted`
# interns the weakint and re-mints it, and the tree reads the FLOAT half: that is
# `a_xpow32` reading slot 13 and not the CMPNE beside it.
def tx_negf(+ar: O.Arena) -> O.Found:
  tx_cf(O.Found.ar(tx_ci(ar, H.i32_neg(1))), F32.neg(1.0))

def tx_sub.f(+ar: O.Arena, +x: U32, +y: U32, +n: O.Found) -> O.Found:
  +f = tx_negf(O.Found.ar(n))
  +m = tx_alu2(O.Found.ar(f), O.OpsMUL{}, y, O.Found.i(f))
  tx_alu2(O.Found.ar(m), O.OpsADD{}, x, O.Found.i(m))

def tx_sub.go(+ar: O.Arena, +x: U32, +y: U32, +n: O.Found, pf: Bool) -> O.Found:
  match pf:
    case True{}: tx_sub.f(ar, x, y, n)
    case False{}: tx_sub.i(ar, x, y, n)

def tx_sub(+ar: O.Arena, +x: U32, +y: U32, pf: Bool) -> O.Found:
  tx_sub.go(ar, x, y, tx_ci(ar, H.i32_neg(1)), pf)

# `pow2if` -- lines 27-30. `q.dtype` picks `out_dtype`; the port takes it as a
# parameter, because a CONST has no dtype to read (divergence B) and `qexp2if`'s
# three callers all pass the same width as `d`.
def tx_pow2if(+ar: O.Arena, +q: U32, +out: S.Dt) -> O.Found:
  +b = tx_ci(ar, exponent_bias(out))
  +s = tx_alu2(O.Found.ar(b), O.OpsADD{}, q, O.Found.i(b))
  +m = tx_shl(O.Found.ar(s), O.Found.i(s), mantissa_bits(out))
  tx_bitcast(O.Found.ar(m), O.Found.i(m), out)

# `ilogb2k` -- lines 32-37. A BITCAST down, a shift, a mask, and a subtraction
# written `ADD(x, MUL(bias, C(-1)))` because that is what `-` is (divergence B).
def tx_ilogb2k(+ar: O.Arena, +d: U32, +dt: S.Dt) -> O.Found:
  +b = tx_bitcast(ar, d, tx_int_dt(dt))
  +f = tx_shr(O.Found.ar(b), O.Found.i(b), mantissa_bits(dt))
  +m = tx_ci(O.Found.ar(f), exponent_mask(dt))
  +a = tx_alu2(O.Found.ar(m), O.OpsAND{}, O.Found.i(f), O.Found.i(m))
  +c = tx_ci(O.Found.ar(a), exponent_bias(dt))
  +n = tx_ci(O.Found.ar(c), H.i32_neg(1))
  +x = tx_alu2(O.Found.ar(n), O.OpsMUL{}, O.Found.i(c), O.Found.i(n))
  tx_alu2(O.Found.ar(x), O.OpsADD{}, O.Found.i(a), O.Found.i(x))

# `ldexp3k` -- lines 39-45.
def tx_ldexp3k(+ar: O.Arena, +d: U32, +e: U32, +dt: S.Dt) -> O.Found:
  +m1 = tx_bitcast(ar, d, tx_int_dt(dt))
  +ec = tx_cast(O.Found.ar(m1), e, tx_int_dt(dt))
  +m2 = tx_shl(O.Found.ar(ec), O.Found.i(ec), mantissa_bits(dt))
  +s = tx_alu2(O.Found.ar(m2), O.OpsADD{}, O.Found.i(m1), O.Found.i(m2))
  tx_bitcast(O.Found.ar(s), O.Found.i(s), dt)

# `ldexp2k` -- lines 47-50. `shr(e, 1)` is `e // 2` and the WHOLE of this
# function's use of the dead UOp arm of `shr` is that `1`.
def tx_ldexp2k(+ar: O.Arena, +d: U32, +e: U32, +dt: S.Dt) -> O.Found:
  +h = tx_shr(ar, e, 1)
  +a = tx_pow2if(O.Found.ar(h), O.Found.i(h), dt)
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, d, O.Found.i(a))
  +r = tx_sub(O.Found.ar(m), e, O.Found.i(h), False{})
  +b = tx_pow2if(O.Found.ar(r), O.Found.i(r), dt)
  tx_alu2(O.Found.ar(b), O.OpsMUL{}, O.Found.i(m), O.Found.i(b))

# `frexp` -- lines 52-63. It returns a TUPLE and Bend has no tuple, so the pair
# rides in a `Data` record with the arena beside it: `(Arena, U32, U32)` is not a
# Bend type and `tx_ph` needs all three at once.
type Frexp is Data:
  Frexp{ar: O.Arena, m: U32, e: U32}

def Frexp.ar(+x: Frexp) -> O.Arena:
  match x:
    case Frexp{ar, m, e}: ar

def Frexp.m(+x: Frexp) -> U32:
  match x:
    case Frexp{ar, m, e}: m

def Frexp.e(+x: Frexp) -> U32:
  match x:
    case Frexp{ar, m, e}: e

# The exponent, read FIRST -- line 59 is evaluated before line 61 because the
# tuple's head is built first, and the arena order is the gate.
def frexp.exponent(+ar: O.Arena, +bits: U32, +dt: S.Dt) -> O.Found:
  +f = tx_shr(ar, bits, mantissa_bits(dt))
  +m = tx_ci(O.Found.ar(f), exponent_mask(dt))
  tx_alu2(O.Found.ar(m), O.OpsAND{}, O.Found.i(f), O.Found.i(m))

# `Frexp` needs both halves and the arena they were built in, and `(Arena, U32,
# U32)` is not a Bend type, so the record is what carries all three.

# `frexp`'s two masks -- lines 56-57. `m1` keeps the SIGN as well as the mantissa
# (that is what makes `frexp` signed-correct) and `m2` is the half-way exponent
# bias, so the two are not symmetric and cannot be derived from each other. For
# float64 they are 64-bit, which is the other place this file needs a word wider
# than `U32` -- and it is a CONSTANT again.
def frexp.m1(dt: S.Dt) -> H.I64:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 12: H.i64_of_hi_lo(0, 14336)
        case 14: H.i64_of_hi_lo(0, 2155872255)
        case _: H.i64_of_hi_lo(1048575, 4294967295)

def frexp.m2(dt: S.Dt) -> H.I64:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 12: H.i64_of_hi_lo(0, 14336)
        case 14: H.i64_of_hi_lo(0, 1056964608)
        case _: H.i64_of_hi_lo(1073217536, 0)

# The normalised mantissa -- `((bits & m1) | m2).bitcast(d.dtype)`.
def frexp.mantissa(+ar: O.Arena, +bits: U32, +dt: S.Dt) -> O.Found:
  +k = tx_ci64(ar, frexp.m1(dt))
  +n = tx_alu2(O.Found.ar(k), O.OpsAND{}, bits, O.Found.i(k))
  +z = tx_ci64(O.Found.ar(n), frexp.m2(dt))
  +o = tx_alu2(O.Found.ar(z), O.OpsOR{}, O.Found.i(n), O.Found.i(z))
  tx_bitcast(O.Found.ar(o), O.Found.i(o), dt)

def frexp(+ar: O.Arena, +v: U32, +dt: S.Dt, +idt: S.Dt) -> Frexp:
  +b = tx_bitcast(ar, v, idt)
  +x = frexp.exponent(O.Found.ar(b), O.Found.i(b), dt)
  +m = frexp.mantissa(O.Found.ar(x), O.Found.i(b), dt)
  +c = tx_ci(O.Found.ar(m), exponent_bias(dt))
  +n = tx_ci(O.Found.ar(c), H.i32_neg(1))
  +p = tx_alu2(O.Found.ar(n), O.OpsMUL{}, O.Found.i(c), O.Found.i(n))
  +s = tx_alu2(O.Found.ar(p), O.OpsADD{}, O.Found.i(x), O.Found.i(p))
  +o = tx_ci(O.Found.ar(s), 1)
  +r = tx_alu2(O.Found.ar(o), O.OpsADD{}, O.Found.i(s), O.Found.i(o))
  Frexp{O.Found.ar(r), O.Found.i(m), O.Found.i(r)}
# ===========================================================================
# `_broadcasted`'s TWO STEPS, AS ONE DEF. `mixin/elementwise.py:25-34` is
#   y = self.ufix(y)                 # interns a CONST at `y`'s OWN python type
#   promote(t): ... remint(t._uop, dt)   # and then RE-MINTS it to the dtype
# so an `int` LITERAL compared against a float leaves TWO arena slots: the weakint
# CONST that `ufix` made and the float CONST that `remint` made. The tree reads
# only the second. The port interns both, for the same reason and not for
# tidiness, and `a_xsin18` is the row that sees the slot nothing reads.
# ===========================================================================
def tx_pintf(+ar: O.Arena, +v: U32) -> O.Found:
  +i = tx_ci(ar, v)
  tx_cf(O.Found.ar(i), U32.to_f32(v))

# `mixin/dtype.py`'s `cast` ELIDES when the dtype already matches, and this file
# has four places that depend on it: `payne_hanek`'s two `intermediate_dtype`
# casts, `cody_waite_reduction`'s `quadrant.cast(dtypes.i32)`, and `xexp2`'s
# `s = x - q` reading the float `-1.0`. The port takes the answer as a `Bool`
# because a CONST has no dtype to compare (divergence B).
# IT RETURNS AN `O.Found` AND NOT AN INDEX because the ELIDED arm still has to
# hand back the arena it was given, or the caller's next node lands in an arena
# that does not contain this one. `O.Found{ar, x}` IS the elision: the same pair,
# with no node added. `payne_hanek`'s two intermediate casts and
# `cody_waite_reduction`'s `quadrant.cast(dtypes.i32)` are the three call sites.
def tx_cast_same.go(+ar: O.Arena, +x: U32, +dt: S.Dt, same: Bool) -> O.Found:
  match same:
    case True{}: O.Found{ar, x}
    case False{}: tx_cast(ar, x, dt)

def tx_cast_same(+ar: O.Arena, +x: U32, +dt: S.Dt, same: Bool) -> O.Found:
  tx_cast_same.go(ar, x, dt, same)

# ===========================================================================
# THE COEFFICIENTS. Python writes them as Python floats and tinygrad truncates to
# the operand's dtype (`dtype.py:84`), so a coefficient is an F32 bit pattern and
# this file's floats ARE F32: `a_sp12` is `cf909052551` and it is the row. The
# decimal spelling is FULL, never `e-notation`: Bend's float parser reads
# `0.0000026083159809786593541503` and not `2.6083159809786593541503e-06` reliably
# at every exponent (measured: `6.1e-5` and `1e-4` do not parse at all), and a
# dropped digit here is exactly the failure `String.concat` hides.
# ===========================================================================
def SIN32() -> List<&2, F32>:
  [0.0000026083159809786593541503, F32.neg(0.0001981069071916863322258),
   0.00833307858556509017944336, F32.neg(0.166666597127914428710938), 1.0]

def SIN64() -> List<&2, F32>:
  [0.00000000000000000000797255955009037868891952,
   0.00000000000000000281009972710863200091251,
   F32.neg(0.000000000000000000764712219118158833288484),
   0.000000000160590430605664501629054,
   F32.neg(0.0000000250521083763502045810755),
   0.00000275573192239198747630416,
   F32.neg(0.000198412698412696162806809),
   0.00833333333333332974823815,
   F32.neg(0.166666666666666657414808), 1.0]

def EXP232() -> List<&2, F32>:
  [0.0001535920892, 0.001339262701, 0.009618384764, 0.05550347269,
   0.2402264476, 0.6931471825, 1.0]

def EXP264() -> List<&2, F32>:
  [0.0000000004434359082926529454, 0.000000007073164598085707425,
   0.0000001017819260921760451, 0.000001321543872511327615,
   0.0000152527335351758473, 0.0001540353045101147808,
   0.001333355814670499073, 0.009618129107597600536,
   0.05550410866482046596, 0.2402265069591012214,
   0.6931471805599452862, 1.0]

def LOG232() -> List<&2, F32>:
  [0.4374550283, 0.5764790177, 0.961801290512]

def LOG264() -> List<&2, F32>:
  [0.2211941750456081490, 0.2200768693152277689, 0.2623708057488514656,
   0.3205977477944495502, 0.4121985945485324709, 0.5770780162997058982,
   0.96179669392608091449]

# ===========================================================================
# `polyN` -- helpers.py:153, `functools.reduce(lambda acc,c: acc*x+c, p, 0.0)`.
# The seed is the PYTHON FLOAT `0.0`, so the first step is a real
# `MUL(C(0.0), x)` and NOT a fold-away; header note 6. And each coefficient is
# interned by `reduce` BETWEEN its `MUL` and its `ADD`, because `_binop` calls
# `_broadcasted` on the right operand before it calls `alu`. `a_sp10` is the row.
# ===========================================================================
# THE COEFFICIENT LIST IS THE FUEL. It is FIRST and it shrinks first, so the arena
# and the accumulator -- which both CHANGE on every step -- ride after it, and a
# self-call whose first argument is a computed arena is refused outright.
# `O.Found` AND NOT A BARE `U32`. A def that returns only the index DISCARDS its
# own arena: the caller reads `tx_poly`'s index out of the arena it passed IN,
# which does not contain the `MUL`s or the coefficient CONSTs -- `n_sp` came out
# 11 against the oracle's 27 for exactly this. The `Nil` arm therefore rebuilds
# the pair from the arena it was HANDED, which is the only place the accumulated
# arena and the accumulated value can come apart.
def tx_poly.go(cs: List<&2, F32>, +ar: O.Arena, +acc: U32, +x: U32) -> O.Found:
  match cs:
    case Nil{}: O.Found{ar, acc}
    case c <> t:
      +m = tx_alu2(ar, O.OpsMUL{}, acc, x)
      +k = tx_cf(O.Found.ar(m), c)
      +a = tx_alu2(O.Found.ar(k), O.OpsADD{}, O.Found.i(m), O.Found.i(k))
      tx_poly.go(t, O.Found.ar(a), O.Found.i(a), x)

def tx_poly(+ar: O.Arena, +x: U32, cs: List<&2, F32>) -> O.Found:
  +z = tx_cf(ar, 0.0)
  tx_poly.go(cs, O.Found.ar(z), O.Found.i(z), x)

def trig_coeffs(d64: Bool) -> List<&2, F32>:
  match d64:
    case True{}: SIN64()
    case False{}: SIN32()

# `trig_poly` -- line 150 -- and `sin_poly` -- lines 152-156. `d*d` is built
# FIRST because it is `polyN`'s argument, and the outer `d * ...` LAST.
# The two halves are `(Arena, U32)` -- a `Data` record would be a second type for
# the same thing -- so every expansion here returns `O.Found` and `O.Found.i` is
# the only place an index is taken back out.
def tx_trig_poly(+ar: O.Arena, +d: U32, cs: List<&2, F32>) -> O.Found:
  +sq = tx_alu2(ar, O.OpsMUL{}, d, d)
  +p = tx_poly(O.Found.ar(sq), O.Found.i(sq), cs)
  tx_alu2(O.Found.ar(p), O.OpsMUL{}, d, O.Found.i(p))

# `sin_poly` -- approximate sine on [-pi/2, pi/2].
def sin_poly(+ar: O.Arena, +d: U32, +d64: Bool) -> O.Found:
  tx_trig_poly(ar, d, trig_coeffs(d64))

# ===========================================================================
# `_ifand` -- line 158, `(q & n).ne(0)`. `uprod` with a bool `self` would be an
# OR, so `q` MUST be an int for this to be an `AND`; that is the whole reason the
# line exists.
# ===========================================================================
def _ifand.and(+ar: O.Arena, +q: U32, +n: U32) -> O.Found:
  +k = tx_ci(ar, n)
  tx_alu2(O.Found.ar(k), O.OpsAND{}, q, O.Found.i(k))

# `.ne(0)` COMPARES INT TO INT, so `_broadcasted` does NOT re-mint: the literal
# 0 is a weakint and the least-upper dtype of int32 and weakint is int32, whose
# weak dtype IS weakint, so the CONST passes through unchanged. `tx_pintf` would
# mint the float half too and `a_sps29` would read slot 10 where the oracle reads
# the int slot 28.
def _ifand.ne(+b: O.Found, +bi: U32) -> O.Found:
  +z = tx_ci(O.Found.ar(b), 0)
  tx_alu2(O.Found.ar(z), O.OpsCMPNE{}, bi, O.Found.i(z))

def _ifand(+ar: O.Arena, +q: U32, +n: U32) -> O.Found:
  +b = _ifand.and(ar, q, n)
  _ifand.ne(b, O.Found.i(b))

def sin_poly_small(+ar: O.Arena, +d: U32, +q: U32, +d64: Bool) -> O.Found:
  +r = sin_poly(ar, d, d64)
  +c = _ifand(O.Found.ar(r), q, 1)
  +nm = tx_cf(O.Found.ar(c), F32.neg(1.0))
  +ph = tx_cf(O.Found.ar(nm), 1.0)
  +w = tx_alu3(O.Found.ar(ph), O.OpsWHERE{}, O.Found.i(c), O.Found.i(nm), O.Found.i(ph))
  tx_alu2(O.Found.ar(w), O.OpsMUL{}, O.Found.i(r), O.Found.i(w))

def sin_poly_large(+ar: O.Arena, +d: U32, +q: U32, +d64: Bool) -> O.Found:
  +c = _ifand(ar, q, 1)
  +hp = tx_cf(O.Found.ar(c), F32.div(F32.pi(), 2.0))
  +z = tx_cf(O.Found.ar(hp), 0.0)
  +w = tx_alu3(O.Found.ar(z), O.OpsWHERE{}, O.Found.i(c), O.Found.i(hp), O.Found.i(z))
  +s = tx_alu2(O.Found.ar(w), O.OpsADD{}, d, O.Found.i(w))
  +r = sin_poly(O.Found.ar(s), O.Found.i(s), d64)
  +c2 = _ifand(O.Found.ar(r), q, 2)
  +nm = tx_cf(O.Found.ar(c2), F32.neg(1.0))
  +ph = tx_cf(O.Found.ar(nm), 1.0)
  +w2 = tx_alu3(O.Found.ar(ph), O.OpsWHERE{}, O.Found.i(c2), O.Found.i(nm), O.Found.i(ph))
  tx_alu2(O.Found.ar(w2), O.OpsMUL{}, O.Found.i(r), O.Found.i(w2))

# ===========================================================================
# `payne_hanek_reduction` -- lines 66-113. THE BIGGEST SINGLE PIECE IN THE FILE
# AND IT IS ALL 32-BIT GRAPH CONSTRUCTION: see the header's i64 note. It returns
# a TUPLE, so the pair rides in a `Data` record beside the arena.
# ===========================================================================
type Red is Data:
  Red{ar: O.Arena, r: U32, q: U32}

def Red.ar(+x: Red) -> O.Arena:
  match x:
    case Red{ar, r, q}: ar

def Red.r(+x: Red) -> U32:
  match x:
    case Red{ar, r, q}: r

def Red.q(+x: Red) -> U32:
  match x:
    case Red{ar, r, q}: q

# 190 bits of 2/pi for Payne-Hanek style argument reduction -- line 77. The
# `1 << n` ARE REAL SHIFTS in Python because the literals are hex ints; here they
# are the already-shifted values, and `a_ph44` is the row.
# Only `two_over_pi_f[0..5]` is EVER read -- `count+offset < len-1` caps the index
# at 5 -- so index 6 is dead. It is spelled right anyway (`0x4f10e410`), because a
# wrong constant in a table is a lie the gate cannot see.
def TWO_OVER_PI() -> List<&2, U32>:
  [0, 683565275, 2475754826, 2131351028, 2102212464, 920167782, 1326507024]

def two_over_pi(+k: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, TWO_OVER_PI(), U32.to_nat(k)), 0)

# `_take` -- lines 88-92 -- header note 3. THE FUEL AND THE COUNT ARE TWO
# PARAMETERS and they are not the same number: the guard is
# `count+offset < len(two_over_pi_f) - 1` -- a COMPILE-TIME test in Python --
# while the table index is `two_over_pi_f[count+offset]` and the comparison is
# `i.ne(count)`. So for `offset = k` there are `6 - k` levels and `count` runs
# 0..5-k. Reading one Nat as both makes `a_ph36` compare against 6, misses
# `i.ne(0)` entirely, and shifts every node by one.
#
# THE CONST IS INTERNED AFTER THE RECURSIVE CALL because Python evaluates
# `i.ne(count).where(_take(...), an.const_like(...))` receiver-first: the six
# CMPNEs are `a_ph36`..`a_ph43` OUTERMOST FIRST and the six WHEREs
# `a_ph45`..`a_ph54` INNERMOST FIRST.
def ph_take(+k: Nat, +c: U32, +ar: O.Arena, +i: U32, +an: O.Found,
             +off: U32) -> O.Found:
  match k:
    case 0n: O.Found{ar, O.Found.i(an)}
    case 1n+p:
      +cc = tx_ci(ar, c)
      +ne = tx_alu2(O.Found.ar(cc), O.OpsCMPNE{}, i, O.Found.i(cc))
      +in = ph_take(p, U32.add(c, 1), O.Found.ar(ne), i, an, off)
      +t = tx_ci64(O.Found.ar(in), H.i64_of_hi_lo(0, two_over_pi(U32.add(c, off))))
      tx_alu3(O.Found.ar(t), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(in), O.Found.i(t))

# `_shl_lazy` / `_shr_lazy` -- line 93-94. A REAL `SHL`/`SHR` (not `shr`/`shl`),
# a uint64 up-cast on BOTH operands, and a uint32 down-cast after.
# THE SHIFT IS ITS OWN BINDING. Written as
# `tx_cast(b.ar, O.Found.i(tx_alu2(b.ar, SHL, ...)), uint32)` the arena argument
# is evaluated BEFORE the shift is built, so the returned arena does not contain
# it and the uint32 CAST's src is a slot that is not there: `a_ph36`..`a_ph53`
# all read a missing index and `n_ph` came out 73 against 116. Same root cause as
# `tx_pas` and `payne_hanek_reduction`: THE ARENA IS THE SIDE EFFECT.
def shl_lazy(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +a = tx_cast(ar, x, S.uint64())
  +b = tx_cast(O.Found.ar(a), y, S.uint64())
  +s = tx_alu2(O.Found.ar(b), O.OpsSHL{}, O.Found.i(a), O.Found.i(b))
  tx_cast(O.Found.ar(s), O.Found.i(s), S.uint32())

def shr_lazy(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +a = tx_cast(ar, x, S.uint64())
  +b = tx_cast(O.Found.ar(a), y, S.uint64())
  +s = tx_alu2(O.Found.ar(b), O.OpsSHR{}, O.Found.i(a), O.Found.i(b))
  tx_cast(O.Found.ar(s), O.Found.i(s), S.uint32())

# `_hp_mul` -- line 103. This is the ONE place a 64-bit product appears and it is
# a `MUL` NODE on two uint64 operands: the host multiplies nothing. Header note.
#
# `x` IS `ia`, WHICH IS ALREADY uint64` (line 82 ends in `.cast(dtypes.u64)`),
# so `x.cast(dtypes.u64)` ELIDES (mixin/dtype.py:19) and only `y` casts, and
# there is NO cast on the way out. Casting both ways adds two nodes the oracle
# does not have and moves every `a_ph` row from 88 on.
def hp_mul(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +b = tx_cast(ar, y, S.uint64())
  tx_alu2(O.Found.ar(b), O.OpsMUL{}, x, O.Found.i(b))

# `a = [_take(UOp.const(0, dtypes.u32), k) for k in range(4)]` -- line 96.
# FOUR CALLS, NOT A FOLD: the comprehension's `k` is a Python int, so the four
# fuel depths are 6, 5, 4 and 3 AT COMPILE TIME and a `range` is four literals.
def tx_pa0(+ar: O.Arena, +i: U32, +an: O.Found) -> O.Found: ph_take(6n, 0, ar, i, an, 0)
def tx_pa1(+ar: O.Arena, +i: U32, +an: O.Found) -> O.Found: ph_take(5n, 0, ar, i, an, 1)
def tx_pa2(+ar: O.Arena, +i: U32, +an: O.Found) -> O.Found: ph_take(4n, 0, ar, i, an, 2)
def tx_pa3(+ar: O.Arena, +i: U32, +an: O.Found) -> O.Found: ph_take(3n, 0, ar, i, an, 3)

# `a[0..3]` as a FOUR-ARY `Data` record: a `List<&2, U32>` would be a second
# carrier for the same four numbers, and `hi`/`mi`/`lo` want them pairwise anyway.
type As is Data:
  As{ar: O.Arena, a0: U32, a1: U32, a2: U32, a3: U32}

def As.ar(+x: As) -> O.Arena:
  match x:
    case As{ar, a0, a1, a2, a3}: ar

def As.a0(+x: As) -> U32:
  match x:
    case As{ar, a0, a1, a2, a3}: a0

def As.a1(+x: As) -> U32:
  match x:
    case As{ar, a0, a1, a2, a3}: a1

def As.a2(+x: As) -> U32:
  match x:
    case As{ar, a0, a1, a2, a3}: a2

def As.a3(+x: As) -> U32:
  match x:
    case As{ar, a0, a1, a2, a3}: a3

def As.ax(+x: As, k: U32) -> U32:
  match k:
    case 2: As.a2(x)
    case _: As.a3(x)

def As.at(+x: As, k: U32) -> U32:
  match k:
    case 0: As.a0(x)
    case 1: As.a1(x)
    case _: As.ax(x, k)

def tx_pas(+ar: O.Arena, +i: U32) -> As:
  +z = tx_ci(ar, 0)
  +a0 = tx_pa0(O.Found.ar(z), i, z)
  +a1 = tx_pa1(O.Found.ar(a0), i, z)
  +a2 = tx_pa2(O.Found.ar(a1), i, z)
  +a3 = tx_pa3(O.Found.ar(a2), i, z)
  As{O.Found.ar(a3), O.Found.i(a0), O.Found.i(a1), O.Found.i(a2), O.Found.i(a3)}

# `hi = _shl_lazy(a[0], e) | _shr_lazy(a[1], offset)`, `mi` from (1,2) and `lo`
# from (2,3) -- lines 99-101. `offset` is the `nbits - e`, a UOp, so the shift
# AMOUNT is a node's src1 and not a CONST. `a_ph67` is the row.
def ph_mix(+ar: O.Arena, +az: As, +e: U32, +off: U32, +k: U32) -> O.Found:
  +s = shl_lazy(ar, As.at(az, k), e)
  +t = shr_lazy(O.Found.ar(s), As.at(az, U32.add(k, 1)), off)
  tx_alu2(O.Found.ar(t), O.OpsOR{}, O.Found.i(s), O.Found.i(t))

def ph_hi(+ar: O.Arena, +az: As, +e: U32, +off: U32) -> O.Found:
  ph_mix(ar, az, e, off, 0)

def ph_mi(+ar: O.Arena, +az: As, +e: U32, +off: U32) -> O.Found:
  ph_mix(ar, az, e, off, 1)

def ph_lo(+ar: O.Arena, +az: As, +e: U32, +off: U32) -> O.Found:
  ph_mix(ar, az, e, off, 2)

# `p = shl(_hp_mul(ia, hi), 32) + _hp_mul(ia, mi) + shr(_hp_mul(ia, lo), 32)`
# -- line 105. Three 64-bit products and three CONSTs, and `2**32` is interned ONCE
# because `shl` and `shr` both mint it and the arena interns it. `a_ph88` is the
# row and `n_ph` is the count that says how big this is.
# EVERY STEP TAKES THE PREVIOUS STEP'S ARENA. Written as `hp_mul(ar, ...)` then
# `tx_ci64(ar, ...)`, the compiler is free to evaluate them in either order and
# it chose the const first, which put `ci1:0` at `a_ph88` instead of `a_ph90` and
# moved twenty rows. Reading `O.Found.ar` of the previous step is what makes the
# order observable, so it is written that way here.
def ph_p(+ar: O.Arena, +ia: O.Found, +hi: O.Found, +mi: O.Found, +lo: O.Found) -> O.Found:
  +a = hp_mul(ar, O.Found.i(ia), O.Found.i(hi))
  +c = tx_ci64(O.Found.ar(a), tx_powi(32))
  +s = tx_alu2(O.Found.ar(c), O.OpsMUL{}, O.Found.i(a), O.Found.i(c))
  +b = hp_mul(O.Found.ar(s), O.Found.i(ia), O.Found.i(mi))
  +x = tx_alu2(O.Found.ar(b), O.OpsADD{}, O.Found.i(s), O.Found.i(b))
  +d2 = hp_mul(O.Found.ar(x), O.Found.i(ia), O.Found.i(lo))
  +y = tx_shr(O.Found.ar(d2), O.Found.i(d2), 32)
  tx_alu2(O.Found.ar(y), O.OpsADD{}, O.Found.i(x), O.Found.i(y))

# Lines 108-113: the quotient, the masked remainder, the scaled remainder, and
# the `f < 0.5` quadrant correction. The `2**62` and the 62-bit mask are the two
# 64-bit CONSTANTS of the whole file and `H.i64_of_hi_lo` mints both.
#
# `p.cast(intermediate_dtype)` IS uint64 -> float32 and is therefore a REAL CAST
# (`a_ph104`); only the SECOND cast, `.cast(d.dtype)`, is the one `same` answers,
# because that is the cast whose two dtypes can be equal. Swapping the two makes
# `a_ph103` and `a_ph104` vanish and `n_ph` come out 114 against 116.
def ph_qr(+ar: O.Arena, +p: U32, +f: U32, +inter: S.Dt, +same: Bool, +dt: S.Dt) -> Red:
  +c = tx_ci64(ar, tx_powi(62))
  +d = tx_alu2(O.Found.ar(c), O.OpsFLOORDIV{}, p, O.Found.i(c))
  +q = tx_cast(O.Found.ar(d), O.Found.i(d), S.int32())
  +pq = O.Found.i(q)
  +m = tx_ci64(O.Found.ar(q), H.i64_of_hi_lo(1073741823, 4294967295))
  +pm = tx_alu2(O.Found.ar(m), O.OpsAND{}, p, O.Found.i(m))
  +pf = tx_cast(O.Found.ar(pm), O.Found.i(pm), inter)
  +k = tx_cf(O.Found.ar(pf), 0.00000000000000000034061215800865545)
  +r0 = tx_alu2(O.Found.ar(k), O.OpsMUL{}, O.Found.i(pf), O.Found.i(k))
  +h = tx_cf(O.Found.ar(r0), 0.5)
  +rc = tx_cast_same(O.Found.ar(h), O.Found.i(r0), dt, same)
  +lt = tx_alu2(O.Found.ar(rc), O.OpsCMPLT{}, f, O.Found.i(h))
  +pi = tx_cf(O.Found.ar(lt), F32.div(F32.pi(), 2.0))
  +n1 = tx_cf(O.Found.ar(pi), F32.neg(1.0))
  +pmul = tx_alu2(O.Found.ar(n1), O.OpsMUL{}, O.Found.i(pi), O.Found.i(n1))
  +rsub = tx_alu2(O.Found.ar(pmul), O.OpsADD{}, O.Found.i(rc), O.Found.i(pmul))
  +w = tx_alu3(O.Found.ar(rsub), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(rc), O.Found.i(rsub))
  +one = tx_ci(O.Found.ar(w), 1)
  +qa = tx_alu2(O.Found.ar(one), O.OpsADD{}, pq, O.Found.i(one))
  +w2 = tx_alu3(O.Found.ar(qa), O.OpsWHERE{}, O.Found.i(lt), pq, O.Found.i(qa))
  Red{O.Found.ar(w2), O.Found.i(w), O.Found.i(w2)}

# `ia = (f.cast(intermediate_dtype) * 4.294967296e9).cast(dtypes.u64)` -- line
# 82. The `f.cast(intermediate)` ELIDES for float32 and float64 (divergence A's
# `mixin/dtype.py:19`), which is what `same` says. `a_ph25` is the row.
def ph_ia(+ar: O.Arena, +f: U32, +inter: S.Dt, +same: Bool) -> O.Found:
  +c = tx_cf(ar, 4294967296.0)
  +fc = tx_cast_same(O.Found.ar(c), f, inter, same)
  +m = tx_alu2(O.Found.ar(fc), O.OpsMUL{}, O.Found.i(fc), O.Found.i(c))
  tx_cast(O.Found.ar(m), O.Found.i(m), S.uint64())

# `i = shr(e.cast(dtypes.u64), 5)` -- line 84. `shr` by a Python int, so this is
# a FLOORDIV by `2**5` and NOT a `SHR`; header note 1.
def ph_i(+ar: O.Arena, +e: U32) -> O.Found:
  +a = tx_cast(ar, e, S.uint64())
  +b = tx_ci(O.Found.ar(a), 32)
  tx_alu2(O.Found.ar(b), O.OpsFLOORDIV{}, O.Found.i(a), O.Found.i(b))

# `e = e.cast(dtypes.i32) & 31` -- line 85. `e` is REBOUND, so the frexp exponent
# and the masked exponent are two different nodes and `a_ph30` vs `a_ph23` is the
# row that says so.
def ph_ec(+ar: O.Arena, +e: U32) -> O.Found:
  +a = tx_cast(ar, e, S.int32())
  +b = tx_ci(O.Found.ar(a), 31)
  tx_alu2(O.Found.ar(b), O.OpsAND{}, O.Found.i(a), O.Found.i(b))

# `offset = 32 - e` -- line 86 -- on the REBOUND `e`, and `-` is `ADD(32, MUL(e,-1))`.
def ph_off(+ar: O.Arena, +ec: O.Found) -> O.Found:
  +c = tx_ci(ar, 32)
  +n = tx_ci(O.Found.ar(c), H.i32_neg(1))
  +m = tx_alu2(O.Found.ar(n), O.OpsMUL{}, O.Found.i(ec), O.Found.i(n))
  tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(c), O.Found.i(m))

# EVERY STEP THREADS THE ARENA. Bend ELIMINATES a call whose result is unused,
# and `ph_ia`/`ph_i`/`ph_ec`/`ph_off` build their nodes by RETURNING an
# `O.Found`, so an unused one loses its nodes: the first version of this def
# passed the post-`frexp` arena to all four, `ph_i`'s CAST was eliminated
# because only its INDEX was read, and `n_ph` came out 60 against the oracle's
# 116 with three rows reading slots that did not exist yet. Reading `.ar` is
# what keeps a step alive; the arena IS the side effect.
def payne_hanek_reduction(+ar: O.Arena, +d: U32, +dt: S.Dt, +same: Bool,
                           +inter: S.Dt) -> Red:
  +fx = frexp(ar, d, dt, S.uint32())
  +f = Frexp.m(fx)
  +e = Frexp.e(fx)
  +ia = ph_ia(Frexp.ar(fx), f, inter, same)
  +i = ph_i(O.Found.ar(ia), e)
  +ec = ph_ec(O.Found.ar(i), e)
  +off = ph_off(O.Found.ar(ec), ec)
  +az = tx_pas(O.Found.ar(off), O.Found.i(i))
  +hi = ph_hi(As.ar(az), az, O.Found.i(ec), O.Found.i(off))
  +mi = ph_mi(O.Found.ar(hi), az, O.Found.i(ec), O.Found.i(off))
  +lo = ph_lo(O.Found.ar(mi), az, O.Found.i(ec), O.Found.i(off))
  +p = ph_p(O.Found.ar(lo), ia, hi, mi, lo)
  ph_qr(O.Found.ar(p), O.Found.i(p), f, inter, same, dt)

# ===========================================================================
# `cody_waite_reduction` -- lines 115-147. The float64 arm of `_reduce_d` is
# `qdh * -PI_A + x`, ... , `(qdh + q) * -PI_D + d`, and the float32 arm is the
# SLEEF four-term chain; header note 2 says why they are two defs and not a
# self-call.
# ===========================================================================


# LAST addend is `(qdh + q) * -PI_D`, i.e. the quadrant sum is formed ONCE.
def tx_cw32.rest3(+ar: O.Arena, +q: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(0.00000000012154201256553420762))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, q, O.Found.i(a))
  tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
def tx_cw32.rest2(+ar: O.Arena, +q: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(0.0000000019841872589410058936))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, q, O.Found.i(a))
  +s2 = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
  tx_cw32.rest3(O.Found.ar(s2), q, s2)

def tx_cw32.rest(+ar: O.Arena, +q: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(0.00011315941810607910156))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, q, O.Found.i(a))
  +s2 = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
  tx_cw32.rest2(O.Found.ar(s2), q, s2)

def tx_cw32.chain(+ar: O.Arena, +x: U32, +q: U32) -> O.Found:
  +a = tx_cf(ar, F32.neg(3.1414794921875))
  +d = tx_alu2(O.Found.ar(a), O.OpsMUL{}, q, O.Found.i(a))
  +s = tx_alu2(O.Found.ar(d), O.OpsADD{}, O.Found.i(d), x)
  tx_cw32.rest(O.Found.ar(s), q, s)



# `qdh = (d * (m_1_pi / 2.0**24)).cast(dtypes.i64).cast(d.dtype) * (2.0**24)`
# -- line 145. BUILT UNCONDITIONALLY AND DEAD FOR float32/float16; header note 4.
def cw_qdh(+ar: O.Arena, +d: U32, +dt: S.Dt) -> O.Found:
  +c = tx_cf(ar, F32.div(0.318309886183790671537767526745028724, 16777216.0))
  +m = tx_alu2(O.Found.ar(c), O.OpsMUL{}, d, O.Found.i(c))
  +l = tx_cast(O.Found.ar(m), O.Found.i(m), S.int64())
  +f = tx_cast(O.Found.ar(l), O.Found.i(l), dt)
  +p = tx_cf(O.Found.ar(f), 16777216.0)
  tx_alu2(O.Found.ar(p), O.OpsMUL{}, O.Found.i(f), O.Found.i(p))

# `quadrant = rintk(d * m_1_pi - qdh) if d.dtype == dtypes.f64 else rintk(d
# * m_1_pi)` -- line 146. The float64 arm SUBTRACTS `qdh`, so it is its OWN def
# and not a Bool on one: `-` is `ADD(x, MUL(y, C(-1.0)))` and the `C(-1)` is
# re-interned to the float half (divergence B), which is two nodes the float32
# arm does not have. `rintk`'s OUTPUT dtype is the int width of the same name,
# so both arms pass `tx_int_dt(dt)` and `float16` gets `short` -- which is what
# makes the final `quadrant.cast(dtypes.i32)` a REAL CAST on the float16 path
# and an ELISION on the other two. Header note 4 is why `qdh` is built even when
# the float32 arm does not read it.
def cw_quadrant.f32(+ar: O.Arena, +d: U32, +dt: S.Dt) -> O.Found:
  +a = tx_cf(ar, 0.318309886183790671537767526745028724)
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, d, O.Found.i(a))
  tx_rintk(O.Found.ar(m), O.Found.i(m), dt)

def cw_quadrant.d64(+ar: O.Arena, +d: U32, +qdh: U32) -> O.Found:
  +a = tx_cf(ar, 0.318309886183790671537767526745028724)
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, d, O.Found.i(a))
  +s = tx_sub(O.Found.ar(m), O.Found.i(m), qdh, True{})
  tx_rintk(O.Found.ar(s), O.Found.i(s), S.double())

def cw_quadrant(+ar: O.Arena, +d: U32, +dt: S.Dt, +qdh: U32, d64: Bool) -> O.Found:
  match d64:
    case True{}: cw_quadrant.d64(ar, d, qdh)
    case False{}: cw_quadrant.f32(ar, d, dt)

# `cody_waite_reduction` -- lines 144-147. The ORDER is Python's: `qdh` FIRST and
# unconditionally (header note 4), then `quadrant`, then `_reduce_d`, and
# `quadrant.cast(dtypes.i32)` LAST AND ELIDED because the quadrant is already
# int32 -- which is why the port's second return value needs no node.
# The float64 arm of `_reduce_d` -- lines 123-132, sleefdp.c. Six MULs and six
# ADDs and the LAST addend is `(qdh + q) * -PI_D`, so the quadrant sum is
# formed ONCE. Header note 2 is why this is a def and not a self-call.
def tx_cw64.rest3(+ar: O.Arena, +q: U32, +qdh: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(0.0000000000000000000012736634327021899816))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, qdh, O.Found.i(a))
  +s2 = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
  +q2 = tx_alu2(O.Found.ar(s2), O.OpsADD{}, qdh, q)
  +m2 = tx_alu2(O.Found.ar(q2), O.OpsMUL{}, O.Found.i(q2), O.Found.i(a))
  tx_alu2(O.Found.ar(m2), O.OpsADD{}, O.Found.i(m2), O.Found.i(s2))

def tx_cw64.rest2(+ar: O.Arena, +q: U32, +qdh: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(0.00000000000000012246467864107188502))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, qdh, O.Found.i(a))
  +s2 = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
  +b = tx_alu2(O.Found.ar(s2), O.OpsMUL{}, q, O.Found.i(a))
  tx_cw64.rest3(O.Found.ar(b), q, qdh, s2)

def tx_cw64.rest(+ar: O.Arena, +x: U32, +q: U32, +qdh: U32, +s: O.Found) -> O.Found:
  +a = tx_cf(ar, F32.neg(3.1786509424591713469e-08))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, qdh, O.Found.i(a))
  +s2 = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), O.Found.i(s))
  +b = tx_alu2(O.Found.ar(s2), O.OpsMUL{}, q, O.Found.i(a))
  tx_cw64.rest2(O.Found.ar(b), q, qdh, s2)

def tx_cw64.chain(+ar: O.Arena, +x: U32, +q: U32, +qdh: U32) -> O.Found:
  +a = tx_cf(ar, F32.neg(3.1415926218032836914))
  +m = tx_alu2(O.Found.ar(a), O.OpsMUL{}, qdh, O.Found.i(a))
  +s = tx_alu2(O.Found.ar(m), O.OpsADD{}, O.Found.i(m), x)
  +b = tx_alu2(O.Found.ar(s), O.OpsMUL{}, q, O.Found.i(a))
  tx_cw64.rest(O.Found.ar(b), x, q, qdh, s)




# `x.dtype == dtypes.f16` -- line 126 -- is the ONLY ARM OF `_reduce_d` THAT
# RECURSES: `d = _reduce_d(x.cast(dtypes.f32), q.cast(dtypes.f32)).cast(
# dtypes.f16)`. It is reached from the TOP-LEVEL call and not from the float32
# arm, which is why the unroll is `tx_cw32`/`tx_cw64` for the other two and a
# THIRD def here. Header note 2 says the unroll is not a convenience; this arm is
# why the unroll has a boundary at all. NOT GATED -- the oracle's fixture is
# float32 -- and it is written rather than stubbed because a float16 that built
# the float32 chain would be a WRONG TREE rather than a missing one.
def tx_cw16.chain(+ar: O.Arena, +x: U32, +q: U32, +dt: S.Dt) -> O.Found:
  +xf = tx_cast(ar, x, S.single())
  +qf = tx_cast(O.Found.ar(xf), q, S.single())
  +r = tx_cw32.chain(O.Found.ar(qf), O.Found.i(xf), O.Found.i(qf))
  tx_cast(O.Found.ar(r), O.Found.i(r), dt)

def cody_waite_reduction.reduce2(+ar: O.Arena, +d: U32, +d64: Bool, +qdh: U32,
                                 +quad: O.Found) -> O.Found:
  match d64:
    case True{}: tx_cw64.chain(ar, d, O.Found.i(quad), qdh)
    case False{}: tx_cw32.chain(ar, d, O.Found.i(quad))

# `d64` AND `f16` ARE SEPARATE BOOLS AND NEITHER IS DERIVABLE FROM THE OTHER. The
# first version of this def took one and treated "not float64" as "float32", which
# sends float16 down the float32 chain.
def cody_waite_reduction.reduce(+ar: O.Arena, +d: U32, +d64: Bool, +f16: Bool,
                                +dt: S.Dt, +qdh: U32, +quad: O.Found) -> O.Found:
  match f16:
    case True{}: tx_cw16.chain(ar, d, O.Found.i(quad), dt)
    case False{}: cody_waite_reduction.reduce2(ar, d, d64, qdh, quad)

# THE RETURNED `q` IS THE INT32 QUADRANT AND `_reduce_d` READS THE FLOAT ONE.
# Python returns `quadrant.cast(dtypes.i32)`, which ELIDES because the quadrant
# is already int32 for float32 and float64 -- and does NOT for float16, whose
# quadrant is `short` -- while `_reduce_d` is handed `quadrant.cast(d.dtype)`. One
# node, two readers: passing the float quadrant as the result moves `a_xsinf69`
# and `a_xsin175` -- the two `_ifand(q, 1)` and `_ifand(q, 2)` reads -- and no
# count row at all, because the two nodes exist either way.
def cody_waite_reduction.tail(+qf: O.Found, +quad: O.Found, +d: U32,
                             +d64: Bool, +f16: Bool, +dt: S.Dt,
                             +qdh: O.Found) -> Red:
  +r = cody_waite_reduction.reduce(O.Found.ar(qf), d, d64, f16, dt, O.Found.i(qdh), qf)
  +q = tx_cast_same(O.Found.ar(r), O.Found.i(quad), S.int32(), Bool.not(f16))
  Red{O.Found.ar(q), O.Found.i(r), O.Found.i(q)}

# `cody_waite_reduction` -- lines 145-147. THE ORDER IS PYTHON'S: `qdh` FIRST and
# unconditionally (header note 4), then `quadrant`, then `_reduce_d`, and
# `quadrant.cast(dtypes.i32)` LAST AND ELIDED because the quadrant is already
# int32 -- which is why the port's second return value needs no node. `qdh` is
# THREADED IN AS AN INDEX rather than rebuilt by the float64 arm, because
# rebuilding it would mint a second copy of its six nodes on a caller arena that
# `_reduce_d` also reads.
def cody_waite_reduction(+ar: O.Arena, +d: U32, +dt: S.Dt) -> Red:
  +qdh = cw_qdh(ar, d, dt)
  +quad = cw_quadrant(O.Found.ar(qdh), d, dt, O.Found.i(qdh), tx_d64(dt))
  cody_waite_reduction.tail(tx_cast(O.Found.ar(quad), O.Found.i(quad), dt), quad, d,
                            tx_d64(dt), tx_f16(dt), dt, qdh)

# `math.inf`, `math.nan` and `-math.inf` are F32 LAWS with no body, so they are
# `div(1, 0)`, `div(0, 0)` and `neg(div(1, 0))` -- and the port's `CFloat` is an
# F32, which is what `a_xsin10` and `a_xsin13` and `a_xsin202` spell.
def tx_inf() -> F32: F32.div(1.0, 0.0)
def tx_ninf() -> F32: F32.neg(tx_inf())
def tx_nan() -> F32: F32.div(0.0, 0.0)

# ===========================================================================
# `_lazy_map_numbers` -- lines 9-11, `replace inf -> inf, -inf -> _inf,
# nan -> nan, otherwise -> ratio`. The three WHEREs NEST OUT-IN, so the
# innermost `x.ne(-inf).where(ratio, _inf)` is the FIRST node after the three
# CMPNEs; `a_xexp2 15` is the row.
#
# `math.inf` AND `-math.inf` ARE LITERALS IN THE BODY and are NOT the `inf` and
# `_inf` PARAMETERS -- `inf` is the caller's `d.const_like(...)` and it only
# appears in the OUTERMOST `where`. So this def mints the two itself: for
# `xexp2` all three parameters are `C(0.0)` and the literals are still arena
# slots, which is why `a_xexp2 10` and `a_xexp2 13` are `C(inf)` and `C(-inf)`
# and neither is read by the tree.
# ===========================================================================
def tx_lazy_map(+ar: O.Arena, +x: U32, +inf: U32, +_inf: U32, +nan: U32,
               +ratio: U32) -> O.Found:
  +pi = tx_cf(ar, tx_inf())
  +n1 = tx_alu2(O.Found.ar(pi), O.OpsCMPNE{}, x, O.Found.i(pi))
  +n2 = tx_alu2(O.Found.ar(n1), O.OpsCMPNE{}, x, x)
  +ni = tx_cf(O.Found.ar(n2), tx_ninf())
  +n3 = tx_alu2(O.Found.ar(ni), O.OpsCMPNE{}, x, O.Found.i(ni))
  +w1 = tx_alu3(O.Found.ar(n3), O.OpsWHERE{}, O.Found.i(n3), ratio, _inf)
  +w2 = tx_alu3(O.Found.ar(w1), O.OpsWHERE{}, O.Found.i(n2), nan, O.Found.i(w1))
  tx_alu3(O.Found.ar(w2), O.OpsWHERE{}, O.Found.i(n1), O.Found.i(w2), inf)

# `x_sign = x.ne(0).where((x<0).where(x.const_like(-1), x.const_like(1)),
# x.const_like(0))` -- line 180. `0` is an INT literal and `x` is a float, so
# `_broadcasted` mints the weakint CONST and then re-mints it, and BOTH are arena
# slots: `a_xsin18` is the one nothing reads.
def xsin.sign(+ar: O.Arena, +x: U32) -> O.Found:
  +z = tx_pintf(ar, 0)
  +n1 = tx_alu2(O.Found.ar(z), O.OpsCMPNE{}, x, O.Found.i(z))
  +lt = tx_alu2(O.Found.ar(n1), O.OpsCMPLT{}, x, O.Found.i(z))
  +nm = tx_cf(O.Found.ar(lt), F32.neg(1.0))
  +ph = tx_cf(O.Found.ar(nm), 1.0)
  +w1 = tx_alu3(O.Found.ar(ph), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(nm), O.Found.i(ph))
  tx_alu3(O.Found.ar(w1), O.OpsWHERE{}, O.Found.i(n1), O.Found.i(w1), O.Found.i(z))

# ===========================================================================
# `xsin` -- lines 170-191. `fast` and `switch_over` are PARAMETERS because they
# are PARAMETERS in Python (`fast:bool=False, switch_over:float=30.0`), and
# `Config` does not exist in Bend.
#
# THE ORDER of the non-fast arm is NOT the order of the source lines and that is
# the whole point of the `a_xsin` window. Python evaluates
#     r, q = payne_hanek_reduction(x_abs)              # line 182
#     r_small, q_small = cody_waite_reduction(x_abs)  # line 185
#     result = (x_abs<switch_over).where(sin_poly_small(r_small, q_small),
#                                        sin_poly_large(r, q))
# so PAYNE-HANEK IS BUILT FIRST even though `sin_poly_small` reads the CODY-WAITE
# values: the reduction is a separate statement, not an argument. `a_xsin26` is
# the first payne-hanek node and `a_xsin131` is the first cody-waite one, and a
# port that read them in source order swaps 105 nodes.
#
# `fast` picks the WHOLE reduction, so it is a `match` on a Bool PARAMETER and
# not a `match` on a node: rule 2 of the Bend notes.
# ===========================================================================
def xsin.slow(+ar: O.Arena, +xa: U32, +dt: S.Dt, +d64: Bool, +sw: F32,
              +xs: U32) -> O.Found:
  +ph = payne_hanek_reduction(ar, xa, dt, tx_same(dt), dt)
  +cw = cody_waite_reduction(Red.ar(ph), xa, dt)
  +c = tx_cf(Red.ar(cw), sw)
  +lt = tx_alu2(O.Found.ar(c), O.OpsCMPLT{}, xa, O.Found.i(c))
  +ss = sin_poly_small(O.Found.ar(lt), Red.r(cw), Red.q(cw), d64)
  +sl = sin_poly_large(O.Found.ar(ss), Red.r(ph), Red.q(ph), d64)
  +w = tx_alu3(O.Found.ar(sl), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(ss), O.Found.i(sl))
  tx_alu2(O.Found.ar(w), O.OpsMUL{}, O.Found.i(w), xs)

def xsin.fast(+ar: O.Arena, +xa: U32, +dt: S.Dt, +d64: Bool, +xs: U32) -> O.Found:
  +cw = cody_waite_reduction(ar, xa, dt)
  +ss = sin_poly_small(Red.ar(cw), Red.r(cw), Red.q(cw), d64)
  tx_alu2(O.Found.ar(ss), O.OpsMUL{}, O.Found.i(ss), xs)

def xsin.result(fast: Bool, +ar: O.Arena, +xa: U32, +dt: S.Dt, +d64: Bool,
                +sw: F32, +xs: U32) -> O.Found:
  match fast:
    case True{}: xsin.fast(ar, xa, dt, d64, xs)
    case False{}: xsin.slow(ar, xa, dt, d64, sw, xs)

# `sin(Inf) = NaN, sin(-Inf) = NaN, sin(NaN) = NaN` -- line 191 -- is the SAME
# `_lazy_map_numbers` with the nan const in all three slots, and `x` is the RAW
# `d` and not the masked one: `a_xsin203` reads slot 1.
def xsin.tail(+ar: O.Arena, +d: U32, +r: U32) -> O.Found:
  +nan = tx_cf(ar, tx_nan())
  tx_lazy_map(O.Found.ar(nan), d, O.Found.i(nan), O.Found.i(nan), O.Found.i(nan), r)

def xsin(+ar: O.Arena, +d: U32, +dt: S.Dt, +d64: Bool, +fast: Bool,
         +sw: F32) -> O.Found:
  +zero = tx_cf(ar, 0.0)
  +inf = tx_cf(O.Found.ar(zero), tx_inf())
  +x = tx_lazy_map(O.Found.ar(inf), d, O.Found.i(zero), O.Found.i(zero), O.Found.i(zero), d)
  +xs = xsin.sign(O.Found.ar(x), O.Found.i(x))
  +xa = tx_alu2(O.Found.ar(xs), O.OpsMUL{}, O.Found.i(x), O.Found.i(xs))
  +r = xsin.result(fast, O.Found.ar(xa), O.Found.i(xa), dt, d64, sw, O.Found.i(xs))
  xsin.tail(O.Found.ar(r), d, O.Found.i(r))

def exp_coeffs(d64: Bool) -> List<&2, F32>:
  match d64:
    case True{}: EXP264()
    case False{}: EXP232()

# ===========================================================================
# `xexp2` -- lines 193-217. Paper https://arxiv.org/pdf/2001.09258.
# ===========================================================================
def xexp2.tail.nan(+ar: O.Arena, +u: U32, +d: U32) -> O.Found:
  +nn = tx_alu2(ar, O.OpsCMPNE{}, d, d)
  +nan = tx_cf(O.Found.ar(nn), tx_nan())
  tx_alu3(O.Found.ar(nan), O.OpsWHERE{}, O.Found.i(nn), O.Found.i(nan), u)

def xexp2.tail.lower(+ar: O.Arena, +u: U32, +d: U32) -> O.Found:
  +i1 = tx_ci(ar, H.i32_neg(150))
  +f1 = tx_cf(O.Found.ar(i1), F32.neg(U32.to_f32(150)))
  +lt = tx_alu2(O.Found.ar(f1), O.OpsCMPLT{}, d, O.Found.i(f1))
  +z = tx_cf(O.Found.ar(lt), 0.0)
  +w = tx_alu3(O.Found.ar(z), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(z), u)
  xexp2.tail.nan(O.Found.ar(w), O.Found.i(w), d)

def xexp2.tail.upper(+ar: O.Arena, +u: U32, +d: U32) -> O.Found:
  +i0 = tx_ci(ar, 128)
  +f0 = tx_cf(O.Found.ar(i0), U32.to_f32(128))
  +lt = tx_alu2(O.Found.ar(f0), O.OpsCMPLT{}, d, O.Found.i(f0))
  +ge = tx_lnot(O.Found.ar(lt), O.Found.i(lt))
  +inf = tx_cf(O.Found.ar(ge), tx_inf())
  +w = tx_alu3(O.Found.ar(inf), O.OpsWHERE{}, O.Found.i(ge), O.Found.i(inf), u)
  xexp2.tail.lower(O.Found.ar(w), O.Found.i(w), d)

def xexp2.tail(+ar: O.Arena, +u: U32, +d: U32) -> O.Found:
  xexp2.tail.upper(ar, u, d)

def xexp2(+ar: O.Arena, +d: U32, +d64: Bool) -> O.Found:
  +zero = tx_cf(ar, 0.0)
  +inf = tx_cf(O.Found.ar(zero), tx_inf())
  +x = tx_lazy_map(O.Found.ar(inf), d, O.Found.i(zero), O.Found.i(zero), O.Found.i(zero), d)
  +q = tx_rintk(O.Found.ar(x), O.Found.i(x), S.single())
  +s = tx_sub(O.Found.ar(q), O.Found.i(x), O.Found.i(q), True{})
  +u = tx_poly(O.Found.ar(s), O.Found.i(s), exp_coeffs(d64))
  +l = tx_ldexp2k(O.Found.ar(u), O.Found.i(u), O.Found.i(q), S.single())
  xexp2.tail(O.Found.ar(l), O.Found.i(l), d)

# `upper, lower = {float32: (128, -150), ...}[d.dtype]` -- line 211. Python's
# 128 and -150 are INT LITERALS, so `_broadcasted` mints a weakint CONST and then
# re-mints it to a float CONST and both are slots; `a_xexp2 62` and `a_xexp2 68`
# are the two rows and `tx_pintf` cannot express the SIGN, so the one negative
# literal is written out here.




# ===========================================================================
# `xlog2` -- lines 219-255. Paper https://arxiv.org/pdf/2001.09258 5.5. ONE
# LINEAR DEF: the function is a straight-line chain of 33 steps and Bend's only
# loop is a self-call, so splitting it would mean threading `(Arena, U32)` pairs
# through four carriers for no gain.
#
# `x = (m - 1.0) / (m + 1.0)` is `MUL(m-1, RECIPROCAL(m+1))` because `div`
# builds the reciprocal FIRST -- `a_xlog2 42` is the row -- and `denormal_exp`'s
# 64 is an INT literal against a float, so `tx_pintf` mints the weakint CONST and
# the float CONST and both are slots: `a_xlog2 33` is the one nothing reads.
# ===========================================================================
def log_coeffs(d64: Bool) -> List<&2, F32>:
  match d64:
    case True{}: LOG264()
    case False{}: LOG232()

# The `s_lo` term -- line 244 -- is float32-ONLY because it UNDERFLOWS in float16,
# and the float64 coefficient above is the float32 spelling of it: MEASURED, the
# f64 `2.885390081777926774` and the f32 `2.8853900432586669922` have the SAME
# f32 bits, so one F32 literal serves both arms and only the third term's
# EXISTENCE is the dtype branch. `a_xlog2 61` is the row.
def xlog2.recip(+ar: O.Arena, +rc: U32, +w4: O.Found, +ninf: U32) -> O.Found:
  +c = tx_alu2(ar, O.OpsCMPNE{}, rc, ninf)
  tx_alu3(O.Found.ar(c), O.OpsWHERE{}, O.Found.i(c), O.Found.i(w4), ninf)

# `r = (d<-0.0).where(r.const_like(math.nan), r)` -- line 253 -- and `r =
# d.ne(d).where(r.const_like(math.nan), r)` -- line 254 -- SHARE the nan CONST, so
# it is interned ONCE at `a_xlog2 72` and both WHEREs read it. `d.ne(d)` is the
# receiver of the second one and so it is built BEFORE it.
def xlog2.negzero(+ar: O.Arena, +r: U32, +d: U32, +ninf: U32) -> O.Found:
  +nz = tx_cf_neg0(ar)
  +lt = tx_alu2(O.Found.ar(nz), O.OpsCMPLT{}, d, O.Found.i(nz))
  +nan = tx_cf(O.Found.ar(lt), tx_nan())
  +w3 = tx_alu3(O.Found.ar(nan), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(nan), r)
  +c4 = tx_alu2(O.Found.ar(w3), O.OpsCMPNE{}, d, d)
  +w4 = tx_alu3(O.Found.ar(c4), O.OpsWHERE{}, O.Found.i(c4), O.Found.i(nan), O.Found.i(w3))
  +rc = tx_alu1(O.Found.ar(w4), O.OpsRECIPROCAL{}, d)
  xlog2.recip(O.Found.ar(rc), O.Found.i(rc), w4, ninf)

def xlog2.clamp(+ar: O.Arena, +r: U32, +d: U32, +lt: O.Found) -> O.Found:
  +inf = tx_cf(ar, tx_inf())
  +c1 = tx_alu2(O.Found.ar(inf), O.OpsCMPNE{}, d, O.Found.i(inf))
  +w1 = tx_alu3(O.Found.ar(c1), O.OpsWHERE{}, O.Found.i(c1), r, O.Found.i(inf))
  +z = tx_cf(O.Found.ar(w1), 0.0)
  +c2 = tx_alu2(O.Found.ar(z), O.OpsCMPNE{}, d, O.Found.i(z))
  +ninf = tx_cf(O.Found.ar(c2), tx_ninf())
  +w2 = tx_alu3(O.Found.ar(ninf), O.OpsWHERE{}, O.Found.i(c2), O.Found.i(w1), O.Found.i(ninf))
  xlog2.negzero(O.Found.ar(w2), O.Found.i(w2), d, O.Found.i(ninf))

def xlog2.slo(+ar: O.Arena, +x: U32, +r2: U32, +sl: U32, +d: U32, +lt: O.Found) -> O.Found:
  +sx = tx_alu2(ar, O.OpsMUL{}, x, sl)
  +r3 = tx_alu2(O.Found.ar(sx), O.OpsADD{}, r2, O.Found.i(sx))
  xlog2.clamp(O.Found.ar(r3), O.Found.i(r3), d, lt)

# Lines 247-255: the four special-case WHEREs and then the `-0.0` reciprocal test.
# `d.reciprocal()` is a RECIPROCAL NODE and not a division: `a_xlog2 76` is the row.



def xlog2.head(+ar: O.Arena, +d: U32, +d64: Bool) -> O.Found:
  +fm = tx_cf(ar, 0.0001)
  +lt = tx_alu2(O.Found.ar(fm), O.OpsCMPLT{}, d, O.Found.i(fm))
  +p2 = tx_cf(O.Found.ar(lt), 18446744073709551616.0)
  +m1 = tx_alu2(O.Found.ar(p2), O.OpsMUL{}, d, O.Found.i(p2))
  +a = tx_alu3(O.Found.ar(m1), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(m1), d)
  +q = tx_cf(O.Found.ar(a), F32.div(1.0, 0.75))
  +qa = tx_alu2(O.Found.ar(q), O.OpsMUL{}, O.Found.i(a), O.Found.i(q))
  +ig = tx_ilogb2k(O.Found.ar(qa), O.Found.i(qa), S.single())
  +e0 = tx_cast(O.Found.ar(ig), O.Found.i(ig), S.single())
  +nm = tx_cf(O.Found.ar(e0), F32.neg(1.0))
  +ne = tx_alu2(O.Found.ar(nm), O.OpsMUL{}, O.Found.i(e0), O.Found.i(nm))
  +m = tx_ldexp3k(O.Found.ar(ne), O.Found.i(a), O.Found.i(ne), S.single())
  +de = tx_pintf(O.Found.ar(m), 64)
  +es = tx_sub(O.Found.ar(de), O.Found.i(e0), O.Found.i(de), True{})
  +e = tx_alu3(O.Found.ar(es), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(es), O.Found.i(e0))
  +one = tx_cf(O.Found.ar(e), 1.0)
  +mn = tx_alu2(O.Found.ar(one), O.OpsMUL{}, O.Found.i(one), O.Found.i(nm))
  +mo = tx_alu2(O.Found.ar(mn), O.OpsADD{}, O.Found.i(m), O.Found.i(mn))
  +mp = tx_alu2(O.Found.ar(mo), O.OpsADD{}, O.Found.i(m), O.Found.i(one))
  +rc = tx_alu1(O.Found.ar(mp), O.OpsRECIPROCAL{}, O.Found.i(mp))
  +x = tx_alu2(O.Found.ar(rc), O.OpsMUL{}, O.Found.i(mo), O.Found.i(rc))
  +x2 = tx_alu2(O.Found.ar(x), O.OpsMUL{}, O.Found.i(x), O.Found.i(x))
  +ta = O.Found.ar(x2)
  +t = tx_poly(ta, O.Found.i(x2), log_coeffs(d64))
  +xx = tx_alu2(O.Found.ar(t), O.OpsMUL{}, O.Found.i(x), O.Found.i(x2))
  +r0 = tx_alu2(O.Found.ar(xx), O.OpsMUL{}, O.Found.i(t), O.Found.i(xx))
  +r1 = tx_alu2(O.Found.ar(r0), O.OpsADD{}, O.Found.i(r0), O.Found.i(e))
  +lg = tx_cf(O.Found.ar(r1), 2.8853900432586669922)
  +lx = tx_alu2(O.Found.ar(lg), O.OpsMUL{}, O.Found.i(x), O.Found.i(lg))
  +r2 = tx_alu2(O.Found.ar(lx), O.OpsADD{}, O.Found.i(r1), O.Found.i(lx))
  +sl = tx_cf(O.Found.ar(r2), 3.2734474483568488616e-08)
  xlog2.slo(O.Found.ar(sl), O.Found.i(x), O.Found.i(r2), O.Found.i(sl), d, lt)

def xlog2(+ar: O.Arena, +d: U32, +d64: Bool) -> O.Found:
  xlog2.head(ar, d, d64)
# ===========================================================================
# `xpow` -- lines 257-265, and the ONE place where three values are threaded
# forward instead of recomputed. `ret`, `non_int` and `is_odd` are each read by
# a LATER line, and interning would hand back the same slot, but threading them
# is what keeps the node ORDER the oracle's: `a_xpow` is the order Python
# EVALUATES in, and `where` builds its receiver, then `x`, then `y`
# (elementwise.py:426), so `neg_base`'s two inner WHEREs precede its outer one.
#
# `base` is the fixture's PARAM `d` and `exponent` is its `C(2.0)`.
#
# `(base < 0)` -- line 258 -- is `tx_pintf(0)` and NOT a plain float CONST, because
# the literal is a Python INT and `_broadcasted` interns the weakint and then
# re-mints it: `a_xpow9` is the slot nothing reads. `-base` is `self * (-1)`
# (elementwise.py:77) and mints the pair the same way at `a_xpow12` and 13.
# ===========================================================================
type Xp is Data:
  Xp{ar: O.Arena, ret: U32, ni: U32, io: U32}

def Xp.ar(+x: Xp) -> O.Arena:
  match x:
    case Xp{ar, ret, ni, io}: ar

def Xp.ret(+x: Xp) -> U32:
  match x:
    case Xp{ar, ret, ni, io}: ret

def Xp.ni(+x: Xp) -> U32:
  match x:
    case Xp{ar, ret, ni, io}: ni

def Xp.io(+x: Xp) -> U32:
  match x:
    case Xp{ar, ret, ni, io}: io

# `ret = (base < 0).where(-base, base).log2().mul(exponent).exp2()` -- line 258.
def xpow.ret(+ar: O.Arena, +base: U32, +ex: U32) -> Xp:
  +z = tx_pintf(ar, 0)
  +lt = tx_alu2(O.Found.ar(z), O.OpsCMPLT{}, base, O.Found.i(z))
  +ni = tx_ci(O.Found.ar(lt), H.i32_neg(1))
  +nf = tx_cf(O.Found.ar(ni), F32.neg(1.0))
  +nb = tx_alu2(O.Found.ar(nf), O.OpsMUL{}, base, O.Found.i(nf))
  +ab = tx_alu3(O.Found.ar(nb), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(nb), base)
  +lg = tx_alu1(O.Found.ar(ab), O.OpsLOG2{}, O.Found.i(ab))
  +ml = tx_alu2(O.Found.ar(lg), O.OpsMUL{}, O.Found.i(lg), ex)
  +rt = tx_alu1(O.Found.ar(ml), O.OpsEXP2{}, O.Found.i(ml))
  Xp{O.Found.ar(rt), O.Found.i(rt), 0, 0}

# `non_int` and `is_odd` -- lines 261-262. `mod` is `FLOORMOD` because after the
# int32 CAST both operands are ints (elementwise.py:216), and its `2` is the
# fixture's OWN `C(2)`, so `a_xpow26` reads slot 7 and not a fresh CONST. The
# trailing `.cast(dtypes.bool)` is a REAL CAST and `a_xpow27` is the row.
def xpow.flags(+xp: Xp, +ex: U32) -> Xp:
  +ci = tx_cast(Xp.ar(xp), ex, S.int32())
  +cf = tx_cast(O.Found.ar(ci), O.Found.i(ci), S.single())
  +ni = tx_alu2(O.Found.ar(cf), O.OpsCMPNE{}, ex, O.Found.i(cf))
  +z = tx_pintf(O.Found.ar(ni), 0)
  +lo = tx_alu2(O.Found.ar(z), O.OpsCMPLT{}, ex, O.Found.i(z))
  +n1 = tx_ci(O.Found.ar(lo), H.i32_neg(1))
  +nf = tx_cf(O.Found.ar(n1), F32.neg(1.0))
  +ne = tx_alu2(O.Found.ar(nf), O.OpsMUL{}, ex, O.Found.i(nf))
  +w = tx_alu3(O.Found.ar(ne), O.OpsWHERE{}, O.Found.i(lo), O.Found.i(ne), ex)
  +wj = tx_cast(O.Found.ar(w), O.Found.i(w), S.int32())
  +c2 = tx_ci(O.Found.ar(wj), 2)
  +fm = tx_alu2(O.Found.ar(c2), O.OpsFLOORMOD{}, O.Found.i(wj), O.Found.i(c2))
  +io = tx_cast(O.Found.ar(fm), O.Found.i(fm), S.boolean())
  Xp{O.Found.ar(io), Xp.ret(xp), O.Found.i(ni), O.Found.i(io)}

# `neg_base` -- line 263. `-inf` is `math.neg(inf)` and not a MUL, and `a_xpow32`
# is `-ret` -- a MUL against the SAME `-1.0f` slot 13 that `-base` interned.
def xpow.negbase(+xp: Xp, +base: U32) -> O.Found:
  +ret = Xp.ret(xp)
  +linf = tx_cf(Xp.ar(xp), tx_ninf())
  +ne = tx_alu2(O.Found.ar(linf), O.OpsCMPNE{}, base, O.Found.i(linf))
  +nn = tx_cf(O.Found.ar(ne), tx_nan())
  +w1 = tx_alu3(O.Found.ar(nn), O.OpsWHERE{}, O.Found.i(ne), O.Found.i(nn), ret)
  +nr = tx_alu2(O.Found.ar(w1), O.OpsMUL{}, ret, O.Found.i(tx_negf(O.Found.ar(w1))))
  +w2 = tx_alu3(O.Found.ar(nr), O.OpsWHERE{}, Xp.io(xp), O.Found.i(nr), ret)
  tx_alu3(O.Found.ar(w2), O.OpsWHERE{}, Xp.ni(xp), O.Found.i(w1), O.Found.i(w2))

# `exponent.eq(0)` -- line 265 -- is `ne(0).logical_not()` (elementwise.py:337),
# so it is a CMPNE against a BOOL CONST and not against an int 0: `a_xpow36`.
def xpow.zero(+ar: O.Arena, +ex: U32) -> O.Found:
  +z = tx_pintf(ar, 0)
  +ne = tx_alu2(O.Found.ar(z), O.OpsCMPNE{}, ex, O.Found.i(z))
  tx_lnot(O.Found.ar(ne), O.Found.i(ne))

# `(base < 0)` is REBUILT rather than threaded: it is `tx_alu2` against the same
# two slots and so it interns back to `a_xpow11`, which is the whole point of the
# arena being an arena and not a tree.
def xpow.tail(+xp: Xp, +nb: O.Found, +base: U32, +ex: U32) -> O.Found:
  +z = xpow.zero(O.Found.ar(nb), ex)
  +one = tx_cf(O.Found.ar(z), 1.0)
  +z2 = tx_pintf(O.Found.ar(one), 0)
  +lt = tx_alu2(O.Found.ar(z2), O.OpsCMPLT{}, base, O.Found.i(z2))
  +w1 = tx_alu3(O.Found.ar(lt), O.OpsWHERE{}, O.Found.i(lt), O.Found.i(nb), Xp.ret(xp))
  tx_alu3(O.Found.ar(w1), O.OpsWHERE{}, O.Found.i(z), O.Found.i(one), O.Found.i(w1))

# `neg_base` is BOUND, not inlined into `O.Found.i(...)`: an arena that is
# produced inside an argument expression and read only through `.i` is DROPPED,
# and `a_xpow28`..`a_xpow34` are seven nodes the gate could not see. `n_xpow`
# read 34 against the oracle's 41.
def xpow(+ar: O.Arena, +base: U32, +ex: U32) -> O.Found:
  +xp = xpow.ret(ar, base, ex)
  +fp = xpow.flags(xp, ex)
  +nb = xpow.negbase(fp, base)
  xpow.tail(fp, nb, base, ex)

# ===========================================================================
# `get_transcendental_patterns` -- lines 267-277. `ops` AND
# `force_transcendental` ARE PARAMETERS: `codegen/__init__.py:360` calls it as
# `get_transcendental_patterns(supported_ops, TRANSCENDENTAL >= 2)`, so `force`
# IS `TRANSCENDENTAL` and `Config` does not exist in Bend. `ops` is FIVE BITs,
# one per op this function mentions, and `supports_float4` is NOT among them --
# MEASURED, the identifier occurs nowhere in transcendental.py or in anything it
# calls.
#
# THE SHAPE IS PYTHON'S: for each of EXP2, LOG2, SIN in that order, ZERO OR TWO
# rules, and then one SQRT rule. `if op not in ops or force_transcendental` is
# `tx_tab.keep`, and because a kept op contributes exactly two, the tag of every
# later rule DEPENDS ON the flags -- which is why `tx_t_op` re-derives the
# mapping rather than reading a tag, and why the tag is "the index in THIS table"
# here exactly as it is in decomp.bend.
# ===========================================================================
def tx_tab.keep(has: Bool, force: Bool) -> Bool:
  match force:
    case True{}: True{}
    case False{}: Bool.not(has)

def tx_tab.exp2.go(k: Bool) -> List<&2, O.PMEntry>:
  match k:
    case True{}: [O.PMEntry{0, [O.OpsEXP2{}], Nil{}}, O.PMEntry{1, [O.OpsEXP2{}], Nil{}}]
    case False{}: Nil{}

def tx_tab.exp2(+has: Bool, +force: Bool) -> List<&2, O.PMEntry>:
  tx_tab.exp2.go(tx_tab.keep(has, force))

def tx_tab.log2.go(k: Bool, +base: U32) -> List<&2, O.PMEntry>:
  match k:
    case True{}: [O.PMEntry{base, [O.OpsLOG2{}], Nil{}},
                  O.PMEntry{U32.add(base, 1), [O.OpsLOG2{}], Nil{}}]
    case False{}: Nil{}

def tx_tab.log2(+has: Bool, +force: Bool, +base: U32) -> List<&2, O.PMEntry>:
  tx_tab.log2.go(tx_tab.keep(has, force), base)

def tx_tab.sin.go(k: Bool, +base: U32) -> List<&2, O.PMEntry>:
  match k:
    case True{}: [O.PMEntry{base, [O.OpsSIN{}], Nil{}},
                  O.PMEntry{U32.add(base, 1), [O.OpsSIN{}], Nil{}}]
    case False{}: Nil{}

def tx_tab.sin(+has: Bool, +force: Bool, +base: U32) -> List<&2, O.PMEntry>:
  tx_tab.sin.go(tx_tab.keep(has, force), base)

# `if Ops.SQRT not in ops or force_transcendental` -- line 275 -- is the LAST rule
# and its tag is the running length, which is always EVEN because every kept op
# before it contributed two. That is what makes "odd tag" a sound test for the
# `name="x"` half of a pair, and `n_nosq` -- a table of exactly one rule, tagged
# 0 -- is the row that would break it.
def tx_tab.sqrt.go(k: Bool, +base: U32) -> List<&2, O.PMEntry>:
  match k:
    case True{}: [O.PMEntry{base, [O.OpsSQRT{}], Nil{}}]
    case False{}: Nil{}

def tx_tab.sqrt(+has: Bool, +force: Bool, +base: U32) -> List<&2, O.PMEntry>:
  tx_tab.sqrt.go(tx_tab.keep(has, force), base)

def tx_tab.len(+a: List<&2, O.PMEntry>, +b: List<&2, O.PMEntry>,
               +c: List<&2, O.PMEntry>, +d: List<&2, O.PMEntry>) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, List.append(&2, O.PMEntry, a, List.append(&2, O.PMEntry, b, List.append(&2, O.PMEntry, c, d)))))

def tx_tab(+e2: Bool, +l2: Bool, +sn: Bool, +sq: Bool, +f: Bool) -> O.PMEntrys:
  +a = tx_tab.exp2(e2, f)
  +b = tx_tab.log2(l2, f, U32.from_nat(List.length(&2, O.PMEntry, a)))
  +c = tx_tab.sin(sn, f, tx_tab.len(a, b, Nil{}, Nil{}))
  +d = tx_tab.sqrt(sq, f, tx_tab.len(a, b, c, Nil{}))
  O.PMEntrys{List.append(&2, O.PMEntry, a, List.append(&2, O.PMEntry, b, List.append(&2, O.PMEntry, c, d)))}

def tx_tab.n(+t: O.PMEntrys) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(t)))

def tx_tab.at(+t: O.PMEntrys, +i: U32) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, O.PMEntrys.es(t), U32.to_nat(i)),
                O.PMEntry{0, Nil{}, Nil{}})

# THE DISPATCH, keyed on the OP and not on the tag, because the tag is a
# position and the position moves. `ops.bend` cannot call into this file, so
# `decomp.bend` reads the entry's op and hands it here; that is the whole of the
# duplicated scan. The SQRT rule's body is `lambda d: xpow(d, d.const_like(0.5))`
# -- line 276 -- so the half is minted first.
def tx_t_apply.sqrt(+ar: O.Arena, +d: U32) -> O.Found:
  +h = tx_cf(ar, 0.5)
  xpow(O.Found.ar(h), d, O.Found.i(h))

def tx_t_apply(+op: O.Op, +ar: O.Arena, +d: U32, +dt: S.Dt) -> O.Found:
  match op:
    case O.OpsEXP2{}: xexp2(ar, d, tx_d64(dt))
    case O.OpsLOG2{}: xlog2(ar, d, tx_d64(dt))
    case O.OpsSIN{}: xsin(ar, d, dt, tx_d64(dt), False{}, 30.0)
    case _: tx_t_apply.sqrt(ar, d)

# ===========================================================================
# THE FIXTURE. ONE ARENA, addressed BY INDEX, and it is REBUILT FRESH for every
# window: `tx_win` drops every node the expansion added and hands back the nine
# fixture slots, so a node that leaks between two expansions moves a row instead
# of making two windows agree on a wrong answer. THE ORDER IS THE ORACLE'S
# FIXTURE ORDER (tx-arena.py `fresh()`) and it is PART OF THE CONTRACT:
#
#   0 bottom NOOP
#   1 PARAM d float32   2 PARAM x float32
#   3 C(3) int32   4 C(-2) int32   5 C(-2.0) float32
#   6 C(1) int32   7 C(2) int32   8 C(2.0) float32
#
# The three int/float PAIRS at 3..8 are load-bearing, not decoration: `xpow`'s
# `mod(2)` reads the fixture's own `C(2)` at slot 7 and `sin_poly_small`'s
# `_ifand(q, 1)` reads slot 6, so a fixture without them would intern a second
# `C(2)` and every src index after it would move.
# ===========================================================================
def txp.range(+dt: S.Dt, +lo: U32, +vmax: U32, +nm: String) -> O.ParamArg:
  O.ParamArg{0, dt, Some{0}, Some{O.PyRange{H.i64_of_i32(lo), H.i64_of_i32(vmax)}},
             Some{1}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def t_fixtures() -> O.Arena:
  +a = O.Arena.empty()
  +d = O.UOp.new(a, O.OpsPARAM{}, Nil{}, O.AParam{txp.range(S.single(), 0, 100, "d")}, O.TNone{})
  +x = O.UOp.new(O.Found.ar(d), O.OpsPARAM{}, Nil{}, O.AParam{txp.range(S.single(), H.i32_neg(1), 1, "x")}, O.TNone{})
  +c3 = tx_ci(O.Found.ar(x), 3)
  +cm2 = tx_ci(O.Found.ar(c3), H.i32_neg(2))
  +cm2f = tx_cf(O.Found.ar(cm2), F32.neg(2.0))
  +c1 = tx_ci(O.Found.ar(cm2f), 1)
  +c2 = tx_ci(O.Found.ar(c1), 2)
  +c2f = tx_cf(O.Found.ar(c2), 2.0)
  O.Found.ar(c2f)

def t_nfix() -> U32: 9

# ===========================================================================
# THE ROWS. A node prints as `<idx>,<OP>,<arg>,<src>,<src>...` and the whole
# window as one string, so a dropped leaf and a rewired src both move a line and
# `diff` sees them.
#
# `<arg>` is the oracle's `cargs`: `cb0`/`cb1` for a bool CONST, `cf<32 BITS>`
# for a float CONST -- the port's `CFloat` is an F32 and `F32.to_u32` is the bit
# pattern, so the two sides agree without a decimal -- `ci<hi>:<lo>` for an int
# CONST (a decimal would not fit 2**62 in a U32), `p<name>` for a PARAM, the
# dtype name for a CAST or BITCAST, and `-` for everything else. Divergence B is
# why no other dtype is visible: a CONST has none.
# ===========================================================================
def tx_opname(+op: O.Op) -> String: String.drop(O.Ops.name(op), 4n)

def tx_cbool(+b: Bool) -> String:
  match b:
    case True{}: "cb1"
    case False{}: "cb0"

def tx_carg.dt(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

def tx_carg.pn(m: Maybe<&2, String>) -> String:
  match m:
    case Some{+s}: String.concat(["p", s])
    case None{}: "p-"

def tx_carg.pa(pa: O.ParamArg) -> String:
  match pa:
    case O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace,
                   device, volatile, image, buffer, bind_on_realize, val}:
      tx_carg.pn(name)

# `F32` IS `F32{data: Word(32n)}` -- Bend stores a float as its BITS -- so the
# bit pattern is the payload and `F32.to_u32` is NOT it: `to_u32` is an unfilled
# LAW, and the compiled backend implements it as a numeric truncation, so it
# reads `2.0` back as `2`. Rebuilding a U32 from the payload word is the reading
# that agrees with `struct.pack('<f')`, and it is what makes `cf1073741824` mean
# `C(2.0)` on both sides of the diff.
def tx_fbits(f: F32) -> U32:
  match f:
    case F32{data}: U32{data}

def tx_carg.put(+arg: O.Arg, k: String) -> String:
  match arg:
    case O.APy{O.CBool{b}}: tx_cbool(b)
    case O.APy{O.CFloat{f}}: String.concat(["cf", U32.show(tx_fbits(f))])
    case O.APy{O.CInt{i}}: String.concat(["ci", H.i64_text(i)])
    case O.AParam{pa}: tx_carg.pa(pa)
    case O.ADt{dt}: tx_carg.dt(dt)
    case _: k

def tx_carg(+ar: O.Arena, +u: U32) -> String:
  tx_carg.put(O.Arena.arg(ar, u), "-")

# The oracle writes `','.join(src) or '-'`, so a node with NO srcs ends in a
# bare `-` and not in a trailing comma: `a_rintk1=1,PARAM,pd,-`. `first` is the
# `or` and it is a Bool PARAMETER because a `match` may not scrutinise a `let`.
def tx_srcs.add(acc: String, s: U32, first: Bool) -> String:
  match first:
    case True{}: U32.show(s)
    case False{}: String.concat([acc, ",", U32.show(s)])

def tx_srcs.step(+xs: List<&2, U32>, +ar: O.Arena, acc: String, first: Bool) -> String:
  match xs:
    case Nil{}: acc
    case s <> t: tx_srcs.step(t, ar, tx_srcs.add(acc, s, first), False{})

def tx_row(+ar: O.Arena, +u: U32) -> String:
  String.concat([U32.show(u), ",", tx_opname(O.Arena.op(ar, u)), ",",
                 tx_carg(ar, u), ",", tx_srcs.step(O.Arena.srcs(ar, u), ar, "-", True{})])

# THE WINDOW. Every node from 0 to `Arena.next` INCLUSIVE, which is the whole
# point: a two-level print would hide a dropped leaf, and `n_` alone would hide
# a rewired src.
def tx_win.add(acc: String, +tag: String, +i: U32, +ar: O.Arena, first: Bool) -> String:
  match first:
    case True{}: String.concat(["a_", tag, "=", tx_row(ar, i)])
    case False{}: String.concat([acc, "\na_", tag, "=", tx_row(ar, i)])

def tx_win.go(+tag: String, +k: Nat, +i: U32, +ar: O.Arena, acc: String,
              first: Bool) -> String:
  match k:
    case 0n: acc
    case 1n+p: tx_win.go(tag, p, U32.add(i, 1), ar, tx_win.add(acc, tag, i, ar, first), False{})

def tx_win(+tag: String, +ar: O.Arena) -> String:
  tx_win.go(tag, U32.to_nat(O.Arena.next(ar)), 0, ar, "", True{})

# `n_<tag>` counts the nodes ADDED by one expansion over a FRESH arena, and it is
# the row that cannot be satisfied by a boolean: a rule that builds the right
# shape with the wrong number of pieces passes every `a_` row it does not touch.
def tx_n(+ar: O.Arena) -> U32: O.Arena.next(ar)

# ===========================================================================
# THE WINDOWS. Each is `t_fixtures()` and then ONE expansion, so the window is
# self-contained and a node that leaks from the previous expansion shows up as a
# changed row rather than as two windows agreeing on the same wrong answer.
#
# `t_d` is the fixture's PARAM `d` (slot 1), `t_x` its PARAM `x` (slot 2), and
# `t_c2f` its `C(2.0)` (slot 8), which is `xpow`'s exponent.
# ===========================================================================
def t_d() -> U32: 1
def t_x() -> U32: 2
def t_c3() -> U32: 3
def t_cm2() -> U32: 4
def t_cm2f() -> U32: 5
def t_c1() -> U32: 6
def t_c2() -> U32: 7
def t_c2f() -> U32: 8

def w_rintk() -> O.Arena:
  O.Found.ar(tx_rintk(t_fixtures(), t_d(), S.single()))

def w_pow2if() -> O.Arena:
  O.Found.ar(tx_pow2if(t_fixtures(), t_c3(), S.single()))

def w_ilogb() -> O.Arena:
  O.Found.ar(tx_ilogb2k(t_fixtures(), t_d(), S.single()))

def w_ldexp3() -> O.Arena:
  O.Found.ar(tx_ldexp3k(t_fixtures(), t_d(), t_cm2f(), S.single()))

def w_ldexp2() -> O.Arena:
  O.Found.ar(tx_ldexp2k(t_fixtures(), t_d(), t_cm2(), S.single()))

def w_frexp() -> O.Arena:
  Frexp.ar(frexp(t_fixtures(), t_d(), S.single(), S.uint32()))

def w_cw() -> O.Arena:
  Red.ar(cody_waite_reduction(t_fixtures(), t_d(), S.single()))

def w_ph() -> O.Arena:
  Red.ar(payne_hanek_reduction(t_fixtures(), t_d(), S.single(), True{}, S.single()))

def w_sp() -> O.Arena:
  O.Found.ar(sin_poly(t_fixtures(), t_d(), False{}))

def w_sps() -> O.Arena:
  O.Found.ar(sin_poly_small(t_fixtures(), t_x(), t_c1(), False{}))

def w_spl() -> O.Arena:
  O.Found.ar(sin_poly_large(t_fixtures(), t_x(), t_c2(), False{}))

def w_xsinf() -> O.Arena:
  O.Found.ar(xsin(t_fixtures(), t_d(), S.single(), False{}, True{}, 30.0))

def w_xsin() -> O.Arena:
  O.Found.ar(xsin(t_fixtures(), t_d(), S.single(), False{}, False{}, 30.0))

def w_xexp2() -> O.Arena:
  O.Found.ar(xexp2(t_fixtures(), t_d(), False{}))

def w_xlog2() -> O.Arena:
  O.Found.ar(xlog2(t_fixtures(), t_d(), False{}))

def w_xpow() -> O.Arena:
  O.Found.ar(xpow(t_fixtures(), t_d(), t_c2f()))

# `dtypes.floats` -- dtype.py:22 -- IS A TABLE in this order, and BOTH `dtype=`
# conjuncts of the table are read off it. The oracle prints the DType's ATTRIBUTE
# name, which is `repr(dtype)` -- and `__repr__` CHANGED in tinygrad 793abbb: it
# was `f"dtypes.{INVERSE_DTYPES_DICT[self.name]}"` and is now
# `f"dtypes.{self.name}"`, so what this table prints moved from
# half/float/double/bfloat16 to f16/f32/f64/bf16. The fp8 names are the one group
# that did not move, because their `name` was already their attribute.
def tx_dt_nm.fnuz.f(f: Bool, base: String) -> String:
  match f:
    case True{}: String.concat([base, "fnuz"])
    case False{}: base

def tx_dt_nm.fnuz(nm: String, base: String) -> String:
  tx_dt_nm.fnuz.f(tx_is_fnuz.nm(nm), base)

def tx_dt_nm.wide(pri: U32) -> String:
  match pri:
    case 14: "f32"
    case _: "f64"

def tx_dt_nm.pri(+pri: U32, +nm: String) -> String:
  match pri:
    case 10: tx_dt_nm.fnuz(nm, "fp8e4m3")
    case 11: tx_dt_nm.fnuz(nm, "fp8e5m2")
    case 12: "f16"
    case 13: "bf16"
    case _: tx_dt_nm.wide(pri)

def tx_dt_nm(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: tx_dt_nm.pri(pri, nm)

# `TRANSCENDENTAL_DTYPES` -- line 7 -- is `half, float, double` and the second
# conjunct of every second rule is `dtypes.floats` minus those three.
def tx_tab.tt() -> String:
  String.concat([tx_dt_nm(S.half()), ",", tx_dt_nm(S.single()), ",", tx_dt_nm(S.double())])

def tx_tab.ot() -> String:
  String.concat([tx_dt_nm(S.fp8e4m3()), ",", tx_dt_nm(S.fp8e5m2()), ",",
                 tx_dt_nm(S.fp8e4m3fnuz()), ",", tx_dt_nm(S.fp8e5m2fnuz()), ",",
                 tx_dt_nm(S.bfloat16())])

# THE ENTRY ROW: `ops|early_reject|match_dtype|name`, exactly as the oracle
# spells them. `name` is `"x"` for the cast-to-float32 half of a pair and `None`
# otherwise, and `match_dtype` is `-` for the SQRT rule, which has no `dtype=`.
# BOTH ARE READ OFF THE TAG AND THE OP rather than stored, because `PMEntry` has
# no dtype field -- the `dtype=` conjunct LIVES IN THE RULE BODY, which is
# decomp.bend's arrangement and this file's too.
def tx_tab.mdx(x: Bool) -> String:
  match x:
    case True{}: tx_tab.ot()
    case False{}: tx_tab.tt()

def tx_tab.md(x: Bool, sq: Bool) -> String:
  match sq:
    case True{}: "-"
    case False{}: tx_tab.mdx(x)

def tx_tab.nm(x: Bool) -> String:
  match x:
    case True{}: "x"
    case False{}: "-"

def tx_tab.rej.add(+acc: String, +nm: String, first: Bool) -> String:
  match first:
    case True{}: nm
    case False{}: String.concat([acc, ",", nm])

def tx_tab.rejstr.empty(l: List<&2, O.Op>) -> Bool:
  match l:
    case Nil{}: True{}
    case _: False{}

# `','.join(rej) or '-'` -- the oracle's own `or '-'`, and it is the only place
# an EMPTY reject set and a one-element one are told apart. Every entry in this
# table has an empty reject set, so every `e_` row ends `|-|`.
def tx_tab.rejstr.go(+l: List<&2, O.Op>, +acc: String, first: Bool) -> String:
  match l:
    case Nil{}: acc
    case o <> t: tx_tab.rejstr.go(t, tx_tab.rej.add(acc, tx_opname(o), first), False{})

def tx_tab.rej.dash(first: Bool, acc: String) -> String:
  match first:
    case True{}: "-"
    case False{}: acc

def tx_tab.rejstr(+l: List<&2, O.Op>) -> String:
  tx_tab.rej.dash(tx_tab.rejstr.empty(l), tx_tab.rejstr.go(l, "", tx_tab.rejstr.empty(l)))

def tx_tab.oddf(t: U32) -> Bool: U32.is_eq(U32.mod(t, 2), 1)

def tx_tab.head(l: List<&2, O.Op>) -> O.Op:
  match l:
    case o <> _: o
    case Nil{}: O.OpsEXP2{}

def tx_tab.issq1(o: O.Op) -> Bool:
  match o:
    case O.OpsSQRT{}: True{}
    case _: False{}

def tx_tab.issq(l: List<&2, O.Op>) -> Bool:
  match l:
    case o <> _: tx_tab.issq1(o)
    case Nil{}: False{}

def tx_tab.row(+t: O.PMEntrys, +i: U32) -> String:
  +e = tx_tab.at(t, i)
  +x = tx_tab.oddf(O.PMEntry.tag(e))
  +sq = tx_tab.issq(O.PMEntry.ops(e))
  String.concat([tx_opname(tx_tab.head(O.PMEntry.ops(e))), "|",
                 tx_tab.rejstr(O.PMEntry.rej(e)), "|", tx_tab.md(x, sq), "|",
                 tx_tab.nm(x)])

# `sw30` AND `sw7` -- `xsin`'s `switch_over`, A PARAMETER (Python line 170), read at
# THE SLOT IT LANDS IN. The slot is 157 for both values because the tree's SHAPE
# does not depend on it, which is exactly what makes the pair discriminate: a port
# that hard-coded 30.0 prints `cf1106247680` twice, and this is the whole of the
# evidence that the value reaches the arena. The rows are CONST args and not
# numbers so that a `-` (no CONST there) is visible too.
def w_xsin7() -> O.Arena:
  O.Found.ar(xsin(t_fixtures(), t_d(), S.single(), False{}, False{}, 7.0))

def row(+nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(+nm: String, +v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# A window is MANY rows and it prints itself, prefix and all, so `rows` would
# only add a stray `a_tag=` above the first node.
def win(+nm: String, +v: String) -> IO(Unit):
  IO.print(v)

# ONE TABLE, THREE KINDS OF ROW: `n_<tag>` and then one `e_<tag><i>` per entry.
# The `i` is IN the tag, so a rule added or removed early renumbers every later
# row -- which is the point: a table whose SIZE is right and whose CONTENTS are
# wrong still moves `e_`, and a table whose size is wrong moves `n_`.
#
# ONE SELF-CALL AND NO `IO` IN AN ARM. Printing an entry and then recursing needs
# a `do` block inside a `match` arm, and arm-printing plus a helper is MUTUAL
# RECURSION, which Bend refuses; so the rows are built as one String and printed
# once, exactly as `tx_win` does for a node window.
# THE ENTRY COUNT IS THE Nat FUEL and it is the FIRST parameter, because Bend
# wants a decreasing self-call read left to right and `i` only ever goes up.
def tx_tab_go.e(+k: Nat, +nm: String, +t: O.PMEntrys, +i: U32) -> String:
  match k:
    case 0n: ""
    case 1n+p: String.concat(["\ne_", nm, U32.show(i), "=", tx_tab.row(t, i),
                              tx_tab_go.e(p, nm, t, U32.add(i, 1))])

# THE SEPARATOR LEADS, so the string has no trailing newline and `IO.print`'s own
# newline is the last one. A trailing one prints a blank line per table and four
# of those lines are a diff against the oracle for no reason at all.
def tx_tab_head.go(+nm: String, +t: O.PMEntrys, +n: U32) -> String:
  String.concat(["n_", nm, "=", U32.show(n), tx_tab_go.e(U32.to_nat(n), nm, t, 0)])

def tx_tab_head(+nm: String, +t: O.PMEntrys) -> String:
  tx_tab_head.go(nm, t, tx_tab.n(t))


def gate() -> IO(Unit):
  do IO<Unit>:
    row("mt_f16", mantissa_bits(S.half()))
    row("eb_f16", exponent_bias(S.half()))
    row("em_f16", exponent_mask(S.half()))
    row("mt_f32", mantissa_bits(S.single()))
    row("eb_f32", exponent_bias(S.single()))
    row("em_f32", exponent_mask(S.single()))
    row("mt_f64", mantissa_bits(S.double()))
    row("eb_f64", exponent_bias(S.double()))
    row("em_f64", exponent_mask(S.double()))
    row("n_rintk", tx_n(w_rintk()))
    win("a_rintk", tx_win("rintk", w_rintk()))
    row("n_pow2if", tx_n(w_pow2if()))
    win("a_pow2if", tx_win("pow2if", w_pow2if()))
    row("n_ilogb", tx_n(w_ilogb()))
    win("a_ilogb", tx_win("ilogb", w_ilogb()))
    row("n_ldexp3", tx_n(w_ldexp3()))
    win("a_ldexp3", tx_win("ldexp3", w_ldexp3()))
    row("n_ldexp2", tx_n(w_ldexp2()))
    win("a_ldexp2", tx_win("ldexp2", w_ldexp2()))
    row("n_frexp", tx_n(w_frexp()))
    win("a_frexp", tx_win("frexp", w_frexp()))
    row("n_cw", tx_n(w_cw()))
    win("a_cw", tx_win("cw", w_cw()))
    row("n_ph", tx_n(w_ph()))
    win("a_ph", tx_win("ph", w_ph()))
    row("n_sp", tx_n(w_sp()))
    win("a_sp", tx_win("sp", w_sp()))
    row("n_sps", tx_n(w_sps()))
    win("a_sps", tx_win("sps", w_sps()))
    row("n_spl", tx_n(w_spl()))
    win("a_spl", tx_win("spl", w_spl()))
    row("n_xsinf", tx_n(w_xsinf()))
    win("a_xsinf", tx_win("xsinf", w_xsinf()))
    row("n_xsin", tx_n(w_xsin()))
    win("a_xsin", tx_win("xsin", w_xsin()))
    row("n_xexp2", tx_n(w_xexp2()))
    win("a_xexp2", tx_win("xexp2", w_xexp2()))
    row("n_xlog2", tx_n(w_xlog2()))
    win("a_xlog2", tx_win("xlog2", w_xlog2()))
    row("n_xpow", tx_n(w_xpow()))
    win("a_xpow", tx_win("xpow", w_xpow()))
    # THE TABLE, for the FIVE (ops, force) PAIRS the oracle sweeps. `non` is
    # "every op except the three transcendentals, no force", `force` is the same
    # with force, `nosq` is "every op except SQRT", `empty` is no ops at all and
    # `all` is every op -- the last is the ONE THAT MUST BE EMPTY and is why the
    # table cannot be a constant.
    rows("sw30", tx_carg(w_xsin(), 157))
    rows("sw7", tx_carg(w_xsin7(), 157))
    IO.print(tx_tab_head("non", tx_tab(False{}, False{}, False{}, True{}, False{})))
    IO.print(tx_tab_head("force", tx_tab(False{}, False{}, False{}, True{}, True{})))
    IO.print(tx_tab_head("nosq", tx_tab(True{}, True{}, True{}, False{}, False{})))
    IO.print(tx_tab_head("empty", tx_tab(False{}, False{}, False{}, False{}, False{})))
    IO.print(tx_tab_head("all", tx_tab(True{}, True{}, True{}, True{}, False{})))

def main() -> IO(Unit):
  gate()

# ===========================================================================
# THE MUTATION TABLE. MEASURED, one hand edit at a time, by
# `.agents/slop/tools/tx-mut.py` -- which re-checks the file, runs the
# interpreted lane, and diffs it against `.agents/slop/tx-arena.txt` keyed on
# `<tag>#<slot>`. A POSITIONAL diff reports every row after an insertion as moved,
# which is noise; a `<tag>`-only key collapses all 205 `a_xsin` rows into one.
# Every mutation below still says `checks`, so none of them is a compile-time
# mistake caught for free -- which is the point: the gate has to see them.
#
# | mutation | rows moved | what it catches |
# | --- | --- | --- |
# | `EXP232`'s second coefficient, last digit | `a_xexp2#32` and nothing else | a coefficient is ONE row, and only the windows that use that TABLE move. A coefficient table with a typo is invisible to every count row |
# | `mantissa_bits(float32)` 23 -> 24 | `a_frexp#10`, `a_ilogb#10`, `a_ldexp2#12`, `a_ldexp3#11`, `a_ph#10`, `a_pow2if#11`, `mt_f32`, ... (+4) | the `dtypes.finfo` TABLE, read by six different defs; `mt_f32` is the row that says the value itself moved |
# | `polyN`'s seed `0.0` -> `1.0` | `a_sp#10`, `a_sp#24`..`#26`, `a_spl#17`..`#31`, `a_sps#10`.., `a_xexp2#27`.., `a_xlog2#46`.., `a_xsin#159`.., ... (+74) and `n_sp`, `n_sps`, `n_xsin` | header note 6: the seed is a real `MUL(C(0.0), x)`. A port that starts the Horner at `c[0]` is indistinguishable from this one except in these rows |
# | `_ifand`'s `.ne(0)` reads a float CONST instead of the int one | `a_spl#10`.., `a_sps#29`, `a_xsin#176`, `a_xsin#197`, ... (+31) | `_broadcasted` does NOT re-mint when both sides are already int. MINTING THE PAIR is not "safer", it is wrong |
# | `xsin`: build `cody_waite` BEFORE `payne_hanek` | `a_xsin#100`..`#205`, `a_xsinf`-unaffected, `n_xsin`, `sw30`, `sw7` (+176) | Python evaluates the reductions as STATEMENTS, so payne-hanek is interned first even though `sin_poly_small` reads the cody-waite values. Reading the source order swaps 105 nodes |
# | `xpow`: `base.ne(-inf)` reads `-inf` instead of `ret` | `a_xpow#31` and nothing else | `where(x, y)` builds the receiver, then `x`, then `y`; one row sees it and no COUNT row does, which is why `n_` rows are not enough on their own |
# | `tx_tab.sqrt` ignores `force` | `e_force6`, `n_force` | `force` is `TRANSCENDENTAL` and it is the ONLY difference between the `non` and `force` tables; `n_non` does not move |
# | the `name="x"` half of every pair loses its name | `e_empty1`, `e_empty3`, `e_empty5`, `e_force1`, `e_force3`, `e_force5`, `e_non1`, `e_non3`, `e_non5` | a rule table whose SIZE and SHAPE are right and whose `name=` is wrong. Only a per-entry row sees this |
# | `rintk`'s `d.const_like(-0.5)` -> `+0.5` | `a_rintk#11`, `a_cw#19`.., `a_xsinf#35`, `a_xsin#140`, ... (+187) and `n_rintk`, `n_cw`, `n_xexp2`, `n_xsin`, `n_xsinf`, `sw30`, `sw7` | the sign of the rounding bias, which is `round away from 0` and not `round half up`. Every expansion that rounds moves |
# | `ldexp2k`: `shr(e, 1)` -> `shr(e, 2)` | `a_ldexp2#10`..`#22`, `a_xexp2#49`.., ... (+37) and `n_ldexp2`, `n_xexp2` | header note 1: `shr` by a Python int is a `FLOORDIV` by `2**y`, and `y` is 1 |
# | `payne_hanek`: `shl(p, 62)` -> `shl(p, 63)` | `a_ph#99`, `a_xsin#115` and nothing else | the `2**62` CONST is one node and one reader in each window; `n_ph` does not move because the node is still there |
# | `xpow`: `ret.const_like(1)` -> `2.0` | `a_xpow#38`, `a_xpow#39`, `a_xpow#40`, `n_xpow` | `x ** 0 = 1`, and the CONST is the last node of the window |
# | `xsin`'s `switch_over` hard-coded at 30.0 | `sw7` and nothing else | `switch_over` is a PARAMETER. This is the only mutation `sw30`/`sw7` exists to see, and it is why both rows are read at the SAME SLOT: the shape does not depend on the value |
#
# A row that ONE mutation moves is a LOCALISED row, and there are four of those:
# `a_xexp2#32`, `a_xpow#31`, `a_ph#99` and `sw7`. They are worth keeping for
# exactly that reason -- each one is the only witness for a fact that has no other
# witness in the gate.
#
# ===========================================================================
# WHAT IS NOT DONE. Stated, not hidden.
#
# 1. THE float16 AND float64 WINDOWS ARE NOT GATED. The whole gate is float32,
#    because the oracle's fixture is. `xsin`'s `switch_over` is the only
#    non-structural parameter with two gated values. All THREE of
#    `cody_waite_reduction`'s arms are WRITTEN -- `cw_quadrant.d64` subtracts
#    `qdh`, `cody_waite_reduction.reduce` takes `d64` AND `f16` as two separate
#    Bools, and `tx_cw16.chain` recurses into the float32 chain and casts back --
#    but the float16 and float64 arms have no row:
#      - `cody_waite_reduction`'s float64 arm, including `cw_quadrant.d64`'s
#        `d * m_1_pi - qdh` (header note 4's dead-`qdh` case is the float32 one,
#        not this), and `tx_cw64`'s six `PI_A..PI_D` terms.
#        `# TODO(p3) transcendental.py:126  cody_waite_reduction f64 arm`
#      - `cody_waite_reduction`'s float16 arm -- `_reduce_d` RECURSES into float32
#        and casts back (header note 2), so `tx_cw16.chain` is a real second
#        entry point into `tx_cw32`, and the quadrant is `short` so the final
#        `quadrant.cast(dtypes.i32)` does NOT elide.
#        `# TODO(p3) transcendental.py:135  cody_waite_reduction f16 arm`
#      - `payne_hanek_reduction`'s float16 arm, for the same reason plus the
#        `intermediate_dtype` CAST that float16 is the only dtype to need.
#        `# TODO(p3) transcendental.py:79  payne_hanek intermediate_dtype`
#      - the float64 CONSTANTS (`frexp`'s 64-bit masks, `_reduce_d`'s six
#        `PI_A..PI_D` terms, `EXP264`, `LOG264`, `SIN64`) are spelled as full
#        decimals that were CHECKED against `struct.pack('<f')` for the f32
#        windows, but the f64 windows are not gated and the f64 coefficient
#        literals are NOT independently verified.
#      - `exponent_bias`'s fp8_fnuz arm (`tx_is_fnuz`) is exercised only by the
#        table's `match_dtype` strings, not by a window.
# 2. `ops.bend`'s `eq_const.CFloat` uses `F32.is_eq`, which IEEE says is TRUE of
#    `+0.0` and `-0.0`, and tinygrad keeps them apart (MEASURED:
#    `UOp.const(-0.0) is UOp.const(0.0)` is False). `tx_cf_neg0` pushes the node
#    the way `intern.put` does, which is a WORKAROUND for a defect in a read-only
#    file, and it is correct only because `-0.0` is used ONCE here. REPORTED, NOT
#    FIXED: `ops.bend:1406`.
# 3. `xsin`'s `fast` arm is gated at `fast=True` (`n_xsinf`) but the `switch_over`
#    parameter is only read on the `fast=False` path, which is Python's own dead
#    arm -- `switch_over` is unused when `fast` is true. The port keeps the
#    parameter and does not model the deadness.
# 4. THE TABLE'S `dtype=` CONJUNCTS LIVE IN THE RULE BODY, not in `PMEntry`,
#    because `O.PMEntry` has no dtype field. `tx_tab.md` therefore DERIVES the
#    dtype string from the tag's parity and the entry's op rather than reading it
#    off the rule. That is decomp.bend's arrangement and this file follows it, but
#    it means a rule whose `dtype=` and whose `tag` disagree would still print the
#    right string -- the gate cannot see a rule body.
# 5. `PatternMatcher` itself is NOT ported. `get_transcendental_patterns` returns
#    a `Data` table of `O.PMEntry`, which is the shape ops.bend uses, but nothing
#    here runs `pm_scan` over it: the gate is about the table's CONTENT and the
#    EXPANSIONS' shapes, and `decomp.bend` owns the scan.
