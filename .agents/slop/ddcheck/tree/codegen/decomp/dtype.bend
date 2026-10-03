# dtype.bend -- tinygrad/codegen/decomp/dtype.py (224 lines).
#
# THE LONG AND FLOAT DECOMPOSITIONS. `dtype.py` splits a 64-bit or an
# fp8/half/bfloat16 arithmetic node into 32-bit words (`l2i`) or into a
# bit-level float conversion (`f2f`), and rewrites the graph so the 32-bit nodes
# reach the hardware. This file is the SPLIT half -- `l2i`, `f2f`, `f2f_clamp`,
# `reindex`, `unpack32`, `rne`, `l2i_define` and the three pattern tables --
# which is most of the 224 lines. The REWRITE half (`split_l2i`,
# `l2i_rewrite_idx`, `f2f_load`, `f2f_store`, `f2f_rewrite`,
# `do_dtype_decomps`) is PORTED IN SHAPE, and each def says so.
#
# `decomp/op.bend` is the sibling (`decomp/op.py`) and
# `decomp/transcendental.bend` is the other half of `decomp/transcendental.py`.
# BOTH ARE IMPORTED, not re-derived: `P.dc_*` is `op.bend`'s node vocabulary
# (its `dc_sub` IS `__sub__`'s shape, its `dc_band` IS `x & k`, its `dc_cint` IS
# `UOp.const(v)`) and `T.tx_*` / `T.exponent_bias` / `T.tx_is_fnuz` /
# `T.tx_finfo_*` is `transcendental.bend`'s. `dtype.py` itself imports
# `exponent_bias`, `shl` and `shr` FROM `transcendental.py`, so those three are
# used under `transcendental.bend`'s names and are not re-derived here.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against dtype.py's 224 lines.
#
#   #  PY        KIND    STATE
#   1  12        data    l2i_dt                     PORTED IN FULL
#   2  13        graph   unpack32                   PORTED IN FULL
#   3  14-18     graph   reindex                    PORTED IN FULL
#   4  21-81     graph   l2i                        15 of 17 arms, every arm shape
#   5  83-86     graph   l2i_define                 PORTED IN FULL
#   6  88-92     rewrite split_l2i                 PORTED IN SHAPE
#   7  94        rewrite l2i_rewrite_idx           PORTED IN SHAPE
#   8  97        data    f2f_dt                     PORTED IN FULL
#   9  99        graph   rne                        PORTED IN FULL
#  10  101-125   graph   f2f                        both branches, both raises
#  11  127-134   graph   f2f_clamp                  7 of 8 targets
#  12  136-139   rewrite f2f_load                   PORTED IN SHAPE
#  13  141-143   rewrite f2f_store                  PORTED IN SHAPE
#  14  145       rewrite f2f_rewrite                PORTED IN SHAPE
#  15  148-178   table   pm_long_decomp             PORTED, 13 rules, both reject sets
#  16  181-206   table   pm_float_decomp            PORTED, 10 rules, both reject sets
#  17  208-216   rewrite do_dtype_decomps          PORTED IN SHAPE
#  18  218-224   table   pm_dtype_decomps           PORTED, 2 rules
#
# ---------------------------------------------------------------------------
# HOW THE DTYPE QUESTIONS ARE ASKED. A `match` arm on a dtype NAME is a silent
# fall-through after a rename, so this file arms on `Cls` and `bits` and `pri`
# everywhere it can, and on the NAME only where nothing else can work.
#
#   `dt in (long, ulong)`    Cls.is_int AND bits == 64. Renaming `dtypes.long`
#                            cannot change this answer.
#   `dt in dtypes.floats`    Cls.is_float AND bits != 800. `800` is the WEAK
#                            sentinel, and `weakfloat` is a float by class while
#                            not being in `dtypes.floats`.
#   `dt in dtypes.fp8s`      Cls.is_float AND bits == 8: the four layouts, OCP
#                            and fnuz together, which is exactly the set.
#   `dt in dtypes.fp8_fnuz`  `T.tx_is_fnuz` -- IMPORTED, not re-derived. `pri`
#                            cannot separate `fp8e4m3` from `fp8e4m3fnuz` (both
#                            10) and `bits` cannot either (both 8), so the NAME
#                            is load-bearing here and only here.
#   `dt == dtypes.fp8e4m3`   NOT fnuz AND `T.tx_finfo_e(dt) == 4`. The exponent
#                            width is one half of the name, and `pri` alone would
#                            also accept the fnuz layout.
#   `dt == dtypes.int`       `pri == 5`, and 5 is `int32` alone.
#   `dt == dtypes.float64`   `pri == 15`, and 15 is `float64` alone.
#
# ---------------------------------------------------------------------------
# FIVE DIVERGENCES, stated rather than hidden.
#
# A. `UOp.const(v, dt)` IS A PAIR. `ops.py:631` is
# `UOp(Ops.CONST, arg=dt.const(v), src=()).cast(dt)`, and the cast folds only
# when the CONST's own dtype already IS `dt`. A CONST's dtype is read off its
# ARG (`ops.py:246`), so it is `dtypes.from_py(arg)`, and `from_py`
# (`dtype.py:100-104`) returns ONLY `bool`, `weakint` or `weakfloat`. So for
# every CONCRETE `dt` the cast cannot fold and the pair is what Python builds:
# `UOp.const(0, dtypes.uint)` is TWO nodes. `UOp.const(v)` with no dtype folds
# and is ONE, which is every constant `shl`/`shr` and every bare `(1 << k) - 1`
# in the file. `ops.bend`'s `UOp.const` drops the cast (its own TODO), so
# `dd_const` here builds the pair itself.
#
# B. `_broadcasted`'s PROMOTION CAST AND `logical_not`'s `cast(bool)` ARE NOT
# BUILT. `mixin/elementwise.py` is not ported, so `a + b`, `a & b`, `a == b`,
# `a < b` and `a.where(x, y)` build the bare ALU node here. The oracle deletes
# exactly those two CASTs and keeps every CAST dtype.py writes -- and two of
# those are load-bearing (`.bitcast(uint).cast(cdt)` reinterprets bits as a
# float), which is why `op.bend`'s delete-every-CAST rule cannot be reused.
#
# C. THE FLOAT-TARGET `CAST` ARM OF `l2i` IS NOT PORTED (dtype.py:35-38). It is
# unreachable through `pm_long_decomp`, because every `dt` that table passes to
# `split_l2i` is `l2i_dt[x.dtype]`, an integer. It is also the one place in the
# file where `_broadcasted`'s weak-CONST REMINT (`elementwise.py:31-32`) turns
# `2**32` from an integer constant into a FLOAT constant, and that remint is not
# modelled, so the arm is absent rather than wrong.
#
# D. NO `float16`, `bfloat16` OR `float64` SOURCE FOR `f2f` / `f2f_clamp`.
# `f2f_clamp` mints `mx` with `val.const_like(...)` and `val` is `v.bitcast(fr)`,
# so `mx` is a CONST at the SOURCE's width: CPython truncates it with
# `float_to_fp16` / `float_to_bf16` / `float_to_fp8` (`dtype.py:225/229/244`,
# all `struct` and bit-twiddling C code) and this file has none of them. THE
# WIDENING BRANCH HAS NO `f2f_clamp` AND NO FLOAT CONSTANT, so an fp8 source IS
# gated there: the four widening fixtures are the fnuz arm and the `fp8e4m3`
# arm of `is_nan`, which are otherwise dead defs.
#
# E. `float64` AS AN `f2f_clamp` TARGET IS NOT PORTED, because `mx` is
# `2**1023 * (2 - 2**-52)` = the `float64` maximum and the port's only float
# type is `F32`. Its CPython value is in the oracle (`c7=F(ovf)`) and the
# fixture is absent rather than gated wrong.
#
# ---------------------------------------------------------------------------
# THE `graph_rewrite` WALL. `split_l2i`, `l2i_rewrite_idx`, `f2f_load`,
# `f2f_store`, `f2f_rewrite` and `do_dtype_decomps` all call `graph_rewrite`
# (ops.py:1611), which no file here ports: a bottom-up rewrite to fixpoint over
# an APPEND-ONLY arena is a map from one arena to another, and `uop/fold.bend`'s
# header names the cycle `dtype_from_uop <-> _shape <-> simplify() ->
# graph_rewrite -> the rules -> dtype`. Each of those six is PORTED IN SHAPE:
# the arguments, the guard that picks `pm_long_decomp` over `pm_float_decomp`,
# `bottom_up=True` and the `ctx` are all here, and the rewrite call itself
# answers "no node". `uop/ops.bend` DOES own what they need -- the `PMEntrys`
# table, the `UPat` compiler and `pm_rewrite`'s first-wins scan -- so WHAT THE
# RULES MATCH is gated even though WHAT THEY REWRITE is not.
#
# ---------------------------------------------------------------------------
# WHY `l2i` NEEDS NO FUEL. Every recursive step of `l2i` lands on a DIFFERENT
# op -- `NEG` calls `SUB`, `MUL` calls `ADD`, `MAX` calls `CMPLT` and `WHERE`,
# `CDIV` calls `NEG`/`SHL`/`SHR`/`CMPLT`/`SUB`/`WHERE`/`BITCAST` -- and none of
# those calls `l2i` again. So `l2i` is a `match` with no self-call, which is why
# the 64-iteration `CDIV` loop can be its own def: Bend refuses MUTUAL recursion,
# and this loop's body calls only arms that are themselves leaves.
#
# ---------------------------------------------------------------------------
# THE ORDER OF THIS FILE IS A TOPOLOGICAL SORT, not an accident. bend 2.0.34
# refuses a forward reference, and `.agents/slop/dd-sort.py` reads the call
# graph off this file and rewrites it; run it after adding a def.

import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./op.bend as P
import ./transcendental.bend as T

type W2 is Data:
  W2{ar: O.Arena, lo: U32, hi: U32}

def W2.ar(x: W2) -> O.Arena:
  match x:
    case W2{ar, lo, hi}: ar

def W2.lo(x: W2) -> U32:
  match x:
    case W2{ar, lo, hi}: lo

def W2.hi(x: W2) -> U32:
  match x:
    case W2{ar, lo, hi}: hi

# `ws[i]` -- `uops[0]`..`uops[4]`, which is how `l2i` names its operands. Out of
# range answers 0, the arena's BOTTOM, which is what an absent `src` is; no
# call site reads past `uops[4]`.

def nth.go(ws: List<&2, U32>, n: Nat, k: U32) -> U32:
  match ws:
    case Nil{}: k
    case w <> t:
      match n:
        case 0n: w
        case 1n+p: nth.go(t, p, k)

def nth(ws: List<&2, U32>, n: Nat) -> U32:
  nth.go(ws, n, 0)

def ws2(+a: U32, +b: U32) -> List<&2, U32>: [a, b]

def ws4(+a: U32, +b: U32, +c: U32, +d: U32) -> List<&2, U32>: [a, b, c, d]

def ws5(+a: U32, +b: U32, +c: U32, +d: U32, +e: U32) -> List<&2, U32>: [a, b, c, d, e]

# ===========================================================================
# THE DTYPE QUESTIONS. See the header for why each one is `Cls`/`bits`/`pri`.
# ===========================================================================

def dd_is_long(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, +bits, cls, nm}: U32.is_eq(bits, 64)

def dd_is_float(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, +bits, +cls, nm}: Bool.and(S.Cls.is_float(cls), U32.is_ne(bits, 800))

def dd_is_fp8(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, +bits, +cls, nm}: Bool.and(S.Cls.is_float(cls), U32.is_eq(bits, 8))

# `dt == dtypes.fp8e4m3`. NOT fnuz is half of it and the 4-bit exponent field
# is the other half; `pri` alone would also accept `fp8e4m3fnuz`.

def dd_is_e4m3(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      Bool.and(U32.is_eq(T.tx_finfo_e(dt), 4), Bool.not(T.tx_is_fnuz(dt)))

def dd_is_i32(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: U32.is_eq(pri, 5)

def dd_is_f64(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: U32.is_eq(pri, 15)

def dd_is_uint(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: S.Cls.is_unsigned(cls)

def dd_is_bool(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: S.Cls.is_bool(cls)

# ===========================================================================
# `l2i_dt` -- dtype.py:12, `{long: int, ulong: uint}`, and NOTHING ELSE. So
# `Maybe` is the dict's real shape: a `KeyError` is `None`, and every call site
# guards on it.
# ===========================================================================

def l2i_dt.wide(wide: Bool, +cls: S.Cls) -> Maybe<&2, S.Dt>:
  match wide:
    case True{}:
      match cls:
        case S.CSint{}: Some{S.int32()}
        case S.CUint{}: Some{S.uint32()}
        case _: None{}
    case False{}: None{}

def l2i_dt(+dt: S.Dt) -> Maybe<&2, S.Dt>:
  match dt:
    case S.Dt{pri, +bits, +cls, nm}: l2i_dt.wide(U32.is_eq(bits, 64), cls)

# `f2f_dt` -- dtype.py:97, `{f: getattr(dtypes, f"uint{f.bitsize}") for f in
# dtypes.floats}`. Its domain IS `dtypes.floats`; the answer for anything else
# is "no entry", which is CPython's `KeyError` and no call site's answer.

def f2f_dt.w(+bits: U32) -> Maybe<&2, S.Dt>:
  match bits:
    case 8: Some{S.uint8()}
    case 16: Some{S.uint16()}
    case 32: Some{S.uint32()}
    case 64: Some{S.uint64()}
    case _: None{}

def f2f_dt.of(ok: Bool, m: Maybe<&2, S.Dt>) -> Maybe<&2, S.Dt>:
  match ok:
    case True{}: m
    case False{}: None{}

def f2f_dt(+dt: S.Dt) -> Maybe<&2, S.Dt>:
  match dt:
    case S.Dt{pri, +bits, cls, nm}: f2f_dt.of(dd_is_float(dt), f2f_dt.w(bits))

# ===========================================================================
# `UOp.const` -- divergence A. `truncate[dt](v)` for an integer dtype is a WIDTH
# WRAP, so `dd_trunc` is that wrap: a signed dtype reads the word as a two's
# complement `int32` and an unsigned one does not. Every call site passes a
# value that already fits the width, so the wrap is only the extension.
# ===========================================================================

def dd_is_sgn(+dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, +cls, nm}: Bool.not(S.Cls.is_unsigned(cls))

def dd_trunc(+v: U32, sgn: Bool) -> U32:
  match sgn:
    case True{}: Bool.pick(U32, H.i32_is_neg(v), H.i32_neg(v), v)
    case False{}: v

def dd_const.i64(lo: U32, sgn: Bool) -> H.I64:
  match sgn:
    case True{}: H.i64_of_i32(lo)
    case False{}: H.i64_of_hi_lo(0, lo)

def dd_const.int(+ar: O.Arena, +v: U32, +dt: S.Dt) -> O.Found:
  +w = dd_trunc(v, dd_is_sgn(dt))
  +c = O.UOp.const(ar, O.CInt{dd_const.i64(w, dd_is_sgn(dt))})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{dt}, O.TNone{})

# `UOp.const(v)` with NO dtype: `from_py` answers `weakint`, the `.cast` folds,
# and the value keeps Python's sign. This is `shl`/`shr`'s `2**y` and every bare
# integer literal in the file.

def dd_wk(+ar: O.Arena, +v: H.I64) -> O.Found:
  O.UOp.const(ar, O.CInt{v})

# `UOp.const(v, dt)` for a FLOAT `dt`: the pair, because a float `from_py` is
# `weakfloat`. `f2f_clamp` is the only caller.

def dd_cf(+ar: O.Arena, +v: F32, +dt: S.Dt) -> O.Found:
  +c = O.UOp.const(ar, O.CFloat{v})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{dt}, O.TNone{})

# `const_like(v)` at a dtype the caller already holds. The receiver's dtype is
# a PARAMETER (`xdt` in `l2i`, `fr` in `f2f_clamp`) because `ops.bend`'s arena
# has no dtype field -- `dtype_from_uop` is `fold.bend`'s job.

def dd_clike(+ar: O.Arena, +v: U32, +dt: S.Dt) -> O.Found:
  dd_const.int(ar, v, dt)

# ===========================================================================
# THE OPERATOR SHAPES of `mixin/elementwise.py`, without its promotions -- see
# divergence B. A def's order is the order CPython creates nodes in, because the
# arena's creation order is one of the gate's four facts.
#
# `a == b` IS NOT A `CMPEQ`: `elementwise.py:336` is `self.ne(x).logical_not()`
# and `logical_not` (`:57`) is `self.cast(bool).ne(True)`, so it is TWO `CMPNE`s
# and the outer one's src1 is a BOOL CONST -- never `C(1)`. `a >= b` is
# `(a < b).logical_not()` for the same reason, and `a != b` is one `CMPNE`.
# ===========================================================================

def dd_ne(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsCMPNE{}, x, y)

def dd_eq1(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +n = dd_ne(ar, x, y)
  T.tx_lnot(O.Found.ar(n), O.Found.i(n))

def dd_lt1(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsCMPLT{}, x, y)

def dd_ge1(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  +l = dd_lt1(ar, x, y)
  T.tx_lnot(O.Found.ar(l), O.Found.i(l))

def dd_where(+ar: O.Arena, +c: U32, +x: U32, +y: U32) -> O.Found:
  T.tx_alu3(ar, O.OpsWHERE{}, c, x, y)

def dd_and(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsAND{}, x, y)

def dd_or(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsOR{}, x, y)

def dd_add(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsADD{}, x, y)

def dd_mul(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsMUL{}, x, y)

def dd_shl(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsSHL{}, x, y)

def dd_shr(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsSHR{}, x, y)

def dd_xor(+ar: O.Arena, +x: U32, +y: U32) -> O.Found:
  T.tx_alu2(ar, O.OpsXOR{}, x, y)

# `(b0 & 31)` -- `op.bend`'s `dc_band`, which is the same shape.

def dd_band(+ar: O.Arena, +x: U32, +k: U32) -> O.Found:
  P.dc_band(ar, x, k)

# `x.cast(dt)` FOLDS to `x` when the dtypes already agree (`mixin/dtype.py:36`),
# and it is why `lg6` answers the very node it was handed.

def dd_cast_fold(+ar: O.Arena, +x: U32, +dt: S.Dt, same: Bool) -> O.Found:
  match same:
    case True{}: O.Found{ar, x}
    case False{}: P.dc_cast(ar, x, dt)

def dd_cast_bool(+ar: O.Arena, +x: U32, isb: Bool) -> O.Found:
  match isb:
    case True{}: P.dc_cast(ar, x, S.single())
    case False{}: O.Found{ar, x}

# `31 - n`, which is `n.__rsub__(31)`: `elementwise.py:297` REVERSES, so the
# literal 31 is on the LEFT and the answer is `C(31) + n * -1`. Writing it as
# `n - 31` swaps the two operands of the ADD and nothing else catches it.

def dd_rsub31(+ar: O.Arena, +n: U32) -> O.Found:
  +c = dd_wk(ar, T.tx_powi(31))
  P.dc_sub(O.Found.ar(c), O.Found.i(c), n)

# ===========================================================================
# `unpack32` -- dtype.py:13. `v.bitcast(dtypes.uint) & 0xFFFF` and
# `shr(v.bitcast(dtypes.uint), 16)`, so the BITCAST is built ONCE and both
# halves read it, which is what CPython's interning does with its two calls.
# ===========================================================================

def unpack32(+ar: O.Arena, +v: U32) -> W2:
  +bc = T.tx_bitcast(ar, v, S.uint32())
  +lo = dd_band(O.Found.ar(bc), O.Found.i(bc), 65535)
  +li = O.Found.i(lo)
  +hi = T.tx_shr(O.Found.ar(lo), li, 16)
  W2{O.Found.ar(hi), li, O.Found.i(hi)}

# ===========================================================================
# `reindex` -- dtype.py:14-18. The SHRINK arm's `assert mul == 1` is a `raise`
# and a `raise` here is a refusal (no node). The other arm rewrites the SECOND
# src's index IN PLACE, and `*` binds tighter than `+`:
# `src=(idx.src[0], idx.src[1]*mul+off, *idx.src[2:])`.
# ===========================================================================

def reindex.plus(+ar: O.Arena, +i1: U32, +off: U32) -> O.Found:
  +c = dd_wk(ar, H.i64_of_i32(off))
  dd_add(O.Found.ar(c), i1, O.Found.i(c))

# `i1 * mul` for a Python-int `mul`. NOT a `SHL`: dtype.py writes `*`.

def reindex.scaled(+ar: O.Arena, +i1: U32, +off: U32, +mul: U32) -> O.Found:
  +cm = dd_wk(ar, H.i64_of_i32(mul))
  +m = dd_mul(O.Found.ar(cm), i1, O.Found.i(cm))
  +co = dd_wk(O.Found.ar(m), H.i64_of_i32(off))
  dd_add(O.Found.ar(co), O.Found.i(m), O.Found.i(co))

def reindex.new1(shrink: Bool, +ar: O.Arena, +i1: U32, +off: U32, +mul: U32) -> O.Found:
  match shrink:
    case True{}: reindex.plus(ar, i1, off)
    case False{}: reindex.scaled(ar, i1, off, mul)

def reindex.go(shrink: Bool, +ar: O.Arena, +idx: U32, +new1: O.Found, +one: Bool) -> Maybe<&2, O.Found>:
  match shrink:
    case True{}:
      match one:
        case True{}: Some{O.UOp.new(ar, O.OpsINDEX{}, [O.Arena.src0(ar, idx), O.Found.i(new1)],
          O.Arena.arg(ar, idx), O.Arena.tag(ar, idx))}
        case False{}: None{}
    case False{}: Some{O.UOp.new(ar, O.Arena.op(ar, idx),
      List.append(&2, U32, [O.Arena.src0(ar, idx), O.Found.i(new1)], O.Arena.src_from(ar, idx, 2)),
      O.Arena.arg(ar, idx), O.Arena.tag(ar, idx))}

def reindex(+ar: O.Arena, +idx: U32, +off: U32, +mul: U32) -> Maybe<&2, O.Found>:
  +shrink = O.op_is(ar, idx, O.OpsSHRINK{})
  reindex.go(shrink, ar, idx,
    reindex.new1(shrink, ar, O.Arena.src(ar, idx, 1), off, mul), U32.is_eq(mul, 1))

# ===========================================================================
# `l2i` -- dtype.py:21-81, "long as 2 ints". TAOCP 4.3.1.
#
# `uops` arrives as `ws` because Python's `*uops` is variadic and `l2i` binds
# `a0, a1[, b0[, b1]]` from it; `nth` is the subscript. `xdt` is `uops[0].dtype`,
# the ONE dtype of a UOp that `l2i` reads (dtype.py:28), and it is a parameter
# for the reason `dd_clike` gives.
#
# The four `CAST` arms are Python's `case Ops.CAST if <guard>:` ladder, and a
# failing guard FALLS THROUGH to the next one -- so `dd_cast_sel` is a four-way
# selector over three Booleans and not three separate answers.
# ===========================================================================

def dd_cast_sel.go(sfl: Bool, flt: Bool) -> U32:
  match sfl:
    case True{}: 0
    case False{}:
      match flt:
        case True{}: 1
        case False{}: 2

def dd_cast_sel(lng: Bool, srcfl: Bool, flt: Bool) -> U32:
  match lng:
    case True{}: dd_cast_sel.go(srcfl, flt)
    case False{}: 3

def l2i_cast0.sgn(+ar: O.Arena, +x: U32, +ldt: S.Dt, +xdt: S.Dt, +loi: U32) -> O.Found:
  +x0 = dd_clike(ar, 0, xdt)
  +c = dd_lt1(O.Found.ar(x0), x, O.Found.i(x0))
  +cm = dd_clike(O.Found.ar(c), 4294967295, ldt)
  +cmi = O.Found.i(cm)
  +c0 = dd_clike(O.Found.ar(cm), 0, ldt)
  dd_where(O.Found.ar(c0), O.Found.i(c), cmi, O.Found.i(c0))

def l2i_cast0.pick(zeroext: Bool, +ar: O.Arena, +z: O.Found, +s: O.Found) -> O.Found:
  match zeroext:
    case True{}: z
    case False{}: s

# -- arm 0: a long CAST off an integer source (dtype.py:28-32)

def l2i_cast0(+ar: O.Arena, +x: U32, +ldt: S.Dt, +zeroext: Bool, +xdt: S.Dt) -> W2:
  +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))
  +loi = O.Found.i(lo)
  +loar = O.Found.ar(lo)
  +z = dd_clike(loar, 0, ldt)
  +s = l2i_cast0.sgn(O.Found.ar(z), x, ldt, xdt, loi)
  +l = l2i_cast0.pick(zeroext, loar, z, s)
  W2{O.Found.ar(l), loi, O.Found.i(l)}


# `(x < x.const_like(0)).where(lo.const_like(-1), lo.const_like(0))` -- the high
# word is the sign extension. `-1` into an UNSIGNED `ldt` is `c_uint(-1)`, so
# `dd_trunc` is what makes the word `4294967295` and not `-1`.

# -- arm 1: a long CAST off a float source (dtype.py:33-34)

def l2i_cast1.quo(+ar: O.Arena, +x: U32, +ldt: S.Dt, +xdt: S.Dt, +loi: U32) -> O.Found:
  +c = dd_wk(ar, T.tx_powi(32))
  +rc = T.tx_alu1(O.Found.ar(c), O.OpsRECIPROCAL{}, O.Found.i(c))
  +xf = dd_cast_bool(O.Found.ar(rc), x, dd_is_bool(xdt))
  +m = dd_mul(O.Found.ar(xf), O.Found.i(xf), O.Found.i(rc))
  +hi = P.dc_cast(O.Found.ar(m), O.Found.i(m), ldt)
  +x0 = dd_wk(O.Found.ar(hi), H.i64_of_i32(0))
  +lt = dd_lt1(O.Found.ar(x0), x, O.Found.i(x0))
  +nz = dd_ne(O.Found.ar(lt), loi, O.Found.i(x0))
  +an = dd_and(O.Found.ar(nz), O.Found.i(lt), O.Found.i(nz))
  P.dc_sub(O.Found.ar(an), O.Found.i(hi), O.Found.i(an))

# -- arm 3: the `else` CAST (dtype.py:39), `a0.bitcast(dtypes.uint).cast(dt)`

def l2i_cast1(+ar: O.Arena, +x: U32, +ldt: S.Dt, +xdt: S.Dt) -> W2:
  +lo = dd_cast_fold(ar, x, ldt, O.eq_dt(xdt, ldt))
  +loi = O.Found.i(lo)
  +hi = l2i_cast1.quo(O.Found.ar(lo), x, ldt, xdt, loi)
  W2{O.Found.ar(hi), loi, O.Found.i(hi)}

# `(x / 2**32).cast(ldt) - ((x < 0) & lo.ne(0))`. `x / 2**32` is
# `elementwise.py:255`: both operands are integers so the `CDIV`/`FLOORDIV`
# arm is skipped and it becomes `MUL(x, RECIPROCAL(C(2**32)))`, after
# `a.cast(default_float)` when `a` is a bool. `reciprocal()` is UNARY
# (`elementwise.py:468`), not `FDIV(C(1), x)`.

def l2i_cast3(+ar: O.Arena, +a0: U32, +dt: S.Dt) -> W2:
  +bc = T.tx_bitcast(ar, a0, S.uint32())
  +c = P.dc_cast(O.Found.ar(bc), O.Found.i(bc), dt)
  W2{O.Found.ar(c), O.Found.i(c), 0}

def l2i_cast.got(sel: U32, +ar: O.Arena, +a0: U32, +ldt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:
  match sel:
    case 0: Some{l2i_cast0(ar, a0, ldt, Bool.or(dd_is_bool(xdt), dd_is_uint(xdt)), xdt)}
    case 1: Some{l2i_cast1(ar, a0, ldt, xdt)}
    case _: None{}

def l2i_cast.ldt(sel: U32, m: Maybe<&2, S.Dt>, +ar: O.Arena, +a0: U32, +xdt: S.Dt) -> Maybe<&2, W2>:
  match m:
    case Some{d}: l2i_cast.got(sel, ar, a0, d, xdt)
    case None{}: None{}

def l2i_cast(+ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  l2i_cast.ldt(dd_cast_sel(dd_is_long(dt), dd_is_float(xdt), dd_is_float(dt)),
    l2i_dt(dt), ar, nth(ws, 0n), xdt)

# -- BITCAST (dtype.py:40)

def l2i_bitcast(+ar: O.Arena, +dt: S.Dt, +ws: List<&2, U32>) -> W2:
  +lo = T.tx_bitcast(ar, nth(ws, 0n), dt)
  +li = O.Found.i(lo)
  +hi = T.tx_bitcast(O.Found.ar(lo), nth(ws, 1n), dt)
  W2{O.Found.ar(hi), li, O.Found.i(hi)}

# -- SHL (dtype.py:41-44)

def l2i_shl.hi(+ar: O.Arena, +a1u: U32, +n: U32, +a0u: U32) -> U32:
  +s = dd_shl(ar, a1u, n)
  +c1 = dd_wk(ar, H.i64_of_i32(1))
  +o = dd_shr(O.Found.ar(c1), a0u, O.Found.i(c1))
  +k = dd_rsub31(O.Found.ar(o), n)
  +t = dd_shr(O.Found.ar(k), O.Found.i(o), O.Found.i(k))
  O.Found.i(dd_or(O.Found.ar(t), O.Found.i(s), O.Found.i(t)))

def l2i_shl.ge(+ar: O.Arena, +b0: U32) -> O.Found:
  +c = dd_wk(ar, H.i64_of_i32(32))
  dd_ge1(O.Found.ar(c), b0, O.Found.i(c))

# -- SHR (dtype.py:45-49)

def l2i_shl(+ar: O.Arena, +dt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +b0 = nth(ws, 2n)
  +a0u = T.tx_bitcast(ar, nth(ws, 0n), S.uint32())
  +a1u = T.tx_bitcast(O.Found.ar(a0u), nth(ws, 1n), S.uint32())
  +b31 = dd_band(O.Found.ar(a1u), b0, 31)
  +nn = P.dc_cast(O.Found.ar(b31), O.Found.i(b31), S.uint32())
  +sh1 = dd_shl(O.Found.ar(nn), O.Found.i(a0u), O.Found.i(nn))
  +lo = T.tx_bitcast(O.Found.ar(sh1), O.Found.i(sh1), dt)
  +loi = O.Found.i(lo)
  +loar = O.Found.ar(lo)
  +hi = T.tx_bitcast(loar, l2i_shl.hi(loar, O.Found.i(a1u), O.Found.i(nn), O.Found.i(a0u)), dt)
  +hii = O.Found.i(hi)
  +ge = l2i_shl.ge(O.Found.ar(hi), b0)
  +gei = O.Found.i(ge)
  +r0 = dd_where(O.Found.ar(ge), gei, zero, loi)
  +r1 = dd_where(O.Found.ar(r0), gei, loi, hii)
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

# `(a1u << n) | ((a0u >> 1) >> (31 - n))`

def l2i_shr.fill(+ar: O.Arena, +a1: U32, +zero: U32, signed: Bool) -> O.Found:
  match signed:
    case True{}:
      +c = dd_wk(ar, H.i64_of_i32(31))
      dd_shr(O.Found.ar(c), a1, O.Found.i(c))
    case False{}: O.Found{ar, zero}

# -- ADD (dtype.py:50)

def l2i_shr(+ar: O.Arena, +dt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +a1 = nth(ws, 1n)
  +b0 = nth(ws, 2n)
  +a0u = T.tx_bitcast(ar, nth(ws, 0n), S.uint32())
  +a1u = T.tx_bitcast(O.Found.ar(a0u), a1, S.uint32())
  +m31 = dd_band(O.Found.ar(a1u), b0, 31)
  +nn = P.dc_cast(O.Found.ar(m31), O.Found.i(m31), S.uint32())
  +c1 = dd_wk(O.Found.ar(nn), H.i64_of_i32(1))
  +l1 = dd_shl(O.Found.ar(c1), O.Found.i(a1u), O.Found.i(c1))
  +k = dd_rsub31(O.Found.ar(l1), O.Found.i(nn))
  +l2 = dd_shl(O.Found.ar(k), O.Found.i(l1), O.Found.i(k))
  +r0 = dd_shr(O.Found.ar(l2), O.Found.i(a0u), O.Found.i(nn))
  +o = dd_or(O.Found.ar(r0), O.Found.i(r0), O.Found.i(l2))
  +lo = T.tx_bitcast(O.Found.ar(o), O.Found.i(o), dt)
  +h1 = dd_shr(O.Found.ar(lo), a1, O.Found.i(m31))
  +hi = T.tx_bitcast(O.Found.ar(h1), O.Found.i(h1), dt)
  +ge = l2i_shl.ge(O.Found.ar(hi), b0)
  +r0b = dd_where(O.Found.ar(ge), O.Found.i(ge), O.Found.i(hi), O.Found.i(lo))
  +fill = l2i_shr.fill(O.Found.ar(r0b), a1, zero, dd_is_i32(dt))
  +r1 = dd_where(O.Found.ar(fill), O.Found.i(ge), O.Found.i(fill), O.Found.i(hi))
  W2{O.Found.ar(r1), O.Found.i(r0b), O.Found.i(r1)}

# `fill = a1 >> 31 if dt == dtypes.int else zero` -- the vacated high word, sign
# bits when signed and 0 when not. `a1` and NOT `a1u` is the dtype.py spelling.

def l2i_add(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +a0 = nth(ws, 0n)
  +b0 = nth(ws, 2n)
  +lo = dd_add(ar, a0, b0)
  +s1 = dd_add(O.Found.ar(lo), nth(ws, 1n), nth(ws, 3n))
  +bl = T.tx_bitcast(O.Found.ar(s1), O.Found.i(lo), S.uint32())
  +ba = T.tx_bitcast(O.Found.ar(bl), a0, S.uint32())
  +bb = T.tx_bitcast(O.Found.ar(ba), b0, S.uint32())
  +lt = dd_lt1(O.Found.ar(bb), O.Found.i(ba), O.Found.i(bb))
  +hi = dd_add(O.Found.ar(lt), O.Found.i(s1), O.Found.i(lt))
  W2{O.Found.ar(hi), O.Found.i(lo), O.Found.i(hi)}

# -- SUB (dtype.py:51)

def l2i_sub(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +a0 = nth(ws, 0n)
  +b0 = nth(ws, 2n)
  +lo = P.dc_sub(ar, a0, b0)
  +s1 = P.dc_sub(O.Found.ar(lo), nth(ws, 1n), nth(ws, 3n))
  +ba = T.tx_bitcast(O.Found.ar(s1), a0, S.uint32())
  +bb = T.tx_bitcast(O.Found.ar(ba), b0, S.uint32())
  +lt = dd_lt1(O.Found.ar(bb), O.Found.i(ba), O.Found.i(bb))
  +hi = P.dc_sub(O.Found.ar(lt), O.Found.i(s1), O.Found.i(lt))
  W2{O.Found.ar(hi), O.Found.i(lo), O.Found.i(hi)}

# -- MUL (dtype.py:52-55)

def l2i_mul.w(+ar: O.Arena, +dt: S.Dt, +x: U32, +y: U32, +p: U32, +q: U32) -> O.Found:
  +m = dd_mul(ar, x, y)
  +m16 = T.tx_shl(O.Found.ar(m), O.Found.i(m), 16)
  +a = T.tx_bitcast(O.Found.ar(m16), O.Found.i(m16), dt)
  +a16 = T.tx_shr(O.Found.ar(a), O.Found.i(a), 16)
  +b = T.tx_bitcast(O.Found.ar(a16), O.Found.i(a16), dt)
  +n = dd_mul(O.Found.ar(b), p, q)
  +n16 = T.tx_shl(O.Found.ar(n), O.Found.i(n), 16)
  +c = T.tx_bitcast(O.Found.ar(n16), O.Found.i(n16), dt)
  +c16 = T.tx_shr(O.Found.ar(c), O.Found.i(c), 16)
  T.tx_bitcast(O.Found.ar(c16), O.Found.i(c16), dt)

# the outer half of dtype.py:55 -- `(a00*b00).bitcast(dt)` and
# `(a01*b01).bitcast(dt) + a0*b1 + a1*b0`, in that order.

def l2i_mul.p(+ar: O.Arena, +dt: S.Dt, +a0: U32, +a1: U32, +b1: U32, +a00: U32, +b00: U32, +a01: U32, +b01: U32) -> O.Found:
  +p0 = dd_mul(ar, a00, b00)
  +p = T.tx_bitcast(O.Found.ar(p0), O.Found.i(p0), dt)
  +q0 = dd_mul(O.Found.ar(p), a01, b01)
  +q = T.tx_bitcast(O.Found.ar(q0), O.Found.i(q0), dt)
  +x1 = dd_mul(O.Found.ar(q), a0, b1)
  +s0 = dd_add(O.Found.ar(x1), O.Found.i(q), O.Found.i(x1))
  +y1 = dd_mul(O.Found.ar(s0), a1, b1)
  dd_add(O.Found.ar(y1), O.Found.i(s0), O.Found.i(y1))

def l2i_mul(+ar: O.Arena, +dt: S.Dt, +ws: List<&2, U32>) -> W2:
  +ua = unpack32(ar, nth(ws, 0n))
  +ub = unpack32(W2.ar(ua), nth(ws, 2n))
  +m0 = l2i_mul.w(W2.ar(ub), dt, W2.lo(ua), W2.hi(ub), W2.hi(ua), W2.lo(ub))
  +a0 = O.Found.ar(m0)
  +m1 = l2i_mul.w(a0, dt, W2.hi(ua), W2.lo(ub), W2.lo(ua), W2.hi(ub))
  +a1 = O.Found.ar(m1)
  +m2 = l2i_mul.w(a1, dt, W2.lo(ua), W2.hi(ub), W2.hi(ua), W2.lo(ub))
  +a2 = O.Found.ar(m2)
  +m3 = l2i_mul.w(a2, dt, W2.hi(ua), W2.lo(ub), W2.lo(ua), W2.hi(ub))
  +a3 = O.Found.ar(m3)
  +mid = l2i_add(a3, ws4(O.Found.i(m0), O.Found.i(m1), O.Found.i(m2), O.Found.i(m3)))
  +am = W2.ar(mid)
  +p = l2i_mul.p(am, dt, nth(ws, 0n), nth(ws, 1n), nth(ws, 3n), W2.lo(ua), W2.lo(ub), W2.hi(ua), W2.hi(ub))
  +ap = O.Found.ar(p)
  +ml = W2.lo(mid)
  +mh = W2.hi(mid)
  +pi = O.Found.i(p)
  l2i_add(ap, ws4(ml, mh, pi, 0))

# -- comparisons (dtype.py:75-77)

def l2i_cmplt(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +lt = dd_lt1(ar, nth(ws, 1n), nth(ws, 3n))
  +eq = dd_eq1(O.Found.ar(lt), nth(ws, 1n), nth(ws, 3n))
  +ba = T.tx_bitcast(O.Found.ar(eq), nth(ws, 0n), S.uint32())
  +bb = T.tx_bitcast(O.Found.ar(ba), nth(ws, 2n), S.uint32())
  +lo = dd_lt1(O.Found.ar(bb), O.Found.i(ba), O.Found.i(bb))
  +an = dd_and(O.Found.ar(lo), O.Found.i(eq), O.Found.i(lo))
  +r = dd_or(O.Found.ar(an), O.Found.i(lt), O.Found.i(an))
  W2{O.Found.ar(r), O.Found.i(r), 0}

def l2i_cmpeq(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +a = dd_eq1(ar, nth(ws, 0n), nth(ws, 2n))
  +b = dd_eq1(O.Found.ar(a), nth(ws, 1n), nth(ws, 3n))
  +r = dd_and(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  W2{O.Found.ar(r), O.Found.i(r), 0}

def l2i_cmpne(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +a = dd_ne(ar, nth(ws, 0n), nth(ws, 2n))
  +b = dd_ne(O.Found.ar(a), nth(ws, 1n), nth(ws, 3n))
  +r = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  W2{O.Found.ar(r), O.Found.i(r), 0}

# -- XOR / OR / AND (dtype.py:78): the SAME op on both halves, so this is one def
# parameterized on the op rather than three.

def l2i_binop(+ar: O.Arena, +op: O.Op, +ws: List<&2, U32>) -> W2:
  +r = T.tx_alu2(ar, op, nth(ws, 0n), nth(ws, 2n))
  +s = T.tx_alu2(O.Found.ar(r), op, nth(ws, 1n), nth(ws, 3n))
  W2{O.Found.ar(s), O.Found.i(r), O.Found.i(s)}

# -- WHERE (dtype.py:79): `uops[0]` is the COND and `uops[1..4]` are the two
# pairs, so the answer is two WHEREs and NOT one over two-element branches.

def l2i_where(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +c = nth(ws, 0n)
  +r0 = dd_where(ar, c, nth(ws, 1n), nth(ws, 3n))
  +r1 = dd_where(O.Found.ar(r0), c, nth(ws, 2n), nth(ws, 4n))
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

# -- MAX (dtype.py:80), which is `l2i(WHERE, l2i(CMPLT), ...)`

def l2i_max(+ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +c = l2i_cmplt(ar, ws)
  +ac = W2.ar(c)
  +cc = W2.lo(c)
  +r0 = dd_where(ac, cc, nth(ws, 2n), nth(ws, 0n))
  +ar0 = O.Found.ar(r0)
  +r1 = dd_where(ar0, cc, nth(ws, 3n), nth(ws, 1n))
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

# ===========================================================================
# CDIV / CMOD (dtype.py:56-74). TAOCP 4.3.1D, unrolled 64 times by a `Nat`
# countdown. The loop carries `a0/a1/b0/b1` (the operands, absolute-valued when
# `dt` is signed), the shift `r` and the quotient `q`, and both sign flags; `z`
# is `UOp.const(0, dtypes.uint)` and rides in the record because CPython interns
# it inside the FIRST `l2i(NEG)` when `dt` is signed, not before it.
# ===========================================================================

type Cd is Data:
  Cd{ar: O.Arena, z: U32, a0: U32, a1: U32, b0: U32, b1: U32, r0: U32, r1: U32, q0: U32, q1: U32,
    an: U32, bn: U32}

def Cd.ar(x: Cd) -> O.Arena:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: ar

def Cd.z(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: z

def Cd.a0(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: a0

def Cd.a1(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: a1

def Cd.b0(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: b0

def Cd.b1(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: b1

def Cd.r0(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: r0

def Cd.r1(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: r1

def Cd.q0(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: q0

def Cd.q1(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: q1

def Cd.an(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: an

def Cd.bn(x: Cd) -> U32:
  match x:
    case Cd{ar, z, a0, a1, b0, b1, r0, r1, q0, q1, an, bn}: bn

# `l2i(Ops.NEG, dtypes.uint, ua0, ua1)` -- the NEG arm, which is
# `l2i(SUB, dt, zero, zero, *uops)` and so is two SUBTRACTs from `zero`.

def l2i_cdiv.neg(+ar: O.Arena, +z: U32, +a0: U32, +a1: U32) -> W2:
  l2i_sub(ar, ws4(z, z, a0, a1))

# `if dt == dtypes.int`: take both operands' absolute values through `l2i(NEG)`
# and remember each one's sign, because a restoring division on negatives needs
# them at the end. `a_neg` and `b_neg` survive the whole loop. THE ORDER IS
# dtype.py's: four BITCASTs, then `a1 < zero` BEFORE `l2i(NEG)` (it is the
# receiver of the `.where`), and `zero` is the `dt`-typed CONST from the top of
# `l2i` while `z` is the `uint` one.

def l2i_cdiv.abs.c(+ar: O.Arena, +bni: U32, +zi: U32, +ub0: U32, +ub1: U32, +ani: U32, +n0: U32, +n1: U32, +zr: U32, +ai: U32, +a1i: U32) -> Cd:
  +nb = l2i_cdiv.neg(ar, zi, ub0, ub1)
  +b = dd_where(W2.ar(nb), bni, n0, ub0)
  +nbh = W2.hi(nb)
  +b1a = dd_where(O.Found.ar(b), bni, nbh, ub1)
  +bar = O.Found.ar(b1a)
  +bi = O.Found.i(b)
  +b1i = O.Found.i(b1a)
  Cd{bar, zr, ai, a1i, bi, b1i, zr, zr, zr, zr, ani, bni}

# ONE restoring-division iteration, `i` counting DOWN from 63. `cond` is the
# comparison's `.logical_not()`, so it is `CMPNE(CMPLT(r, b), C(True))` -- a
# CMPNE over a CMPLT, NOT over a second CMPLT.

def l2i_cdiv.abs.b(+ar: O.Arena, +ani: U32, +zi: U32, +ua0: U32, +ua1: U32, +n0: U32, +n1: U32, +zero: U32, +b1: U32, +zr: U32, +ub0: U32, +ub1: U32, +na: W2) -> Cd:
  +a = dd_where(ar, ani, n0, ua0)
  +a1a = dd_where(O.Found.ar(a), ani, n1, ua1)
  +bn = dd_lt1(O.Found.ar(a1a), b1, zero)
  l2i_cdiv.abs.c(O.Found.ar(bn), O.Found.i(bn), zi, ub0, ub1, ani, n0, n1, zr, O.Found.i(a), O.Found.i(a1a))

def l2i_cdiv.abs(+ar: O.Arena, +zero: U32, +a0: U32, +a1: U32, +b0: U32, +b1: U32) -> Cd:
  +ua0 = T.tx_bitcast(ar, a0, S.uint32())
  +ua1 = T.tx_bitcast(O.Found.ar(ua0), a1, S.uint32())
  +ub0 = T.tx_bitcast(O.Found.ar(ua1), b0, S.uint32())
  +ub1 = T.tx_bitcast(O.Found.ar(ub0), b1, S.uint32())
  +an = dd_lt1(O.Found.ar(ub1), a1, zero)
  +z = dd_const.int(O.Found.ar(an), 0, S.uint32())
  +zi = O.Found.i(z)
  +na = l2i_cdiv.neg(O.Found.ar(z), zi, O.Found.i(ua0), O.Found.i(ua1))
  l2i_cdiv.abs.b(ar, O.Found.i(an), zi, O.Found.i(ua0), O.Found.i(ua1), W2.lo(na), W2.hi(na), zero, b1, zi, O.Found.i(ub0), O.Found.i(ub1), na)

# ONE `.where` PAIR PER STEP, with every record and index passed as a `U32`, so
# nothing is read twice: `W2.ar`/`W2.lo`/`W2.hi` are three CALLS on one record and
# a `Found`'s `.ar`/`.i` are two, so every intermediate is destructured once.

def l2i_cdiv.q.lo(+ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  +ci = P.dc_cast(ar, cond, S.uint32())
  +b = T.tx_shl(O.Found.ar(ci), O.Found.i(ci), i)
  +o = dd_or(O.Found.ar(b), Cd.q0(c), O.Found.i(b))
  Cd{O.Found.ar(o), Cd.z(c), Cd.a0(c), Cd.a1(c), Cd.b0(c), Cd.b1(c), Cd.r0(c), Cd.r1(c),
    O.Found.i(o), Cd.q1(c), Cd.an(c), Cd.bn(c)}

def l2i_cdiv.q.hi(+ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  +ci = P.dc_cast(ar, cond, S.uint32())
  +b = T.tx_shl(O.Found.ar(ci), O.Found.i(ci), i)
  +o = dd_or(O.Found.ar(b), Cd.q1(c), O.Found.i(b))
  Cd{O.Found.ar(o), Cd.z(c), Cd.a0(c), Cd.a1(c), Cd.b0(c), Cd.b1(c), Cd.r0(c), Cd.r1(c),
    Cd.q0(c), O.Found.i(o), Cd.an(c), Cd.bn(c)}

def l2i_cdiv.q.sel(lo: Bool, +ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  match lo:
    case True{}: l2i_cdiv.q.lo(ar, cond, c, i)
    case False{}: l2i_cdiv.q.hi(ar, cond, c, i)

# the 64 iterations, `k` counting down

def l2i_cdiv.q(+ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  +lo = U32.is_lt(i, 32)
  l2i_cdiv.q.sel(lo, ar, cond, c, i)

def l2i_cdiv.step(+ar: O.Arena, +c: Cd, +i: U32) -> Cd:
  +z = Cd.z(c)
  +one = dd_const.int(ar, 1, S.uint32())
  +onei = O.Found.i(one)
  +onear = O.Found.ar(one)
  +sh = l2i_shl(onear, S.uint32(), z, ws4(Cd.r0(c), Cd.r1(c), onei, z))
  +shl = W2.lo(sh)
  +shh = W2.hi(sh)
  +shar = W2.ar(sh)
  +ci = dd_const.int(shar, i, S.uint32())
  +cii = O.Found.i(ci)
  +sr = l2i_shr(O.Found.ar(ci), S.uint32(), z, ws4(Cd.a0(c), Cd.a1(c), cii, z))
  +srl = W2.lo(sr)
  +srar = W2.ar(sr)
  +c1 = dd_wk(srar, H.i64_of_i32(1))
  +c1i = O.Found.i(c1)
  +an = dd_band(O.Found.ar(c1), shl, c1i)
  +r0 = dd_or(O.Found.ar(an), shl, O.Found.i(an))
  +r0i = O.Found.i(r0)
  +r = l2i_cmplt(O.Found.ar(r0), ws4(r0i, shh, Cd.b0(c), Cd.b1(c)))
  +rlo = W2.lo(r)
  +rhi = W2.hi(r)
  +rar = W2.ar(r)
  +cond = dd_ge1(rar, rlo, rhi)
  +condi = O.Found.i(cond)
  +diff = l2i_sub(O.Found.ar(cond), ws4(rlo, rhi, Cd.b0(c), Cd.b1(c)))
  +dar = W2.ar(diff)
  +q = l2i_cdiv.q(dar, condi, c, i)
  +dl = W2.lo(diff)
  +dh = W2.hi(diff)
  +qar = Cd.ar(q)
  +w = l2i_where(qar, ws5(condi, dl, dh, r0i, shh))
  +wl = W2.lo(w)
  +wh = W2.hi(w)
  +war = W2.ar(w)
  Cd{war, z, Cd.a0(c), Cd.a1(c), Cd.b0(c), Cd.b1(c), wl, wh, Cd.q0(q), Cd.q1(q), Cd.an(c), Cd.bn(c)}

# `q = (q[0] | shl(cond.cast(uint), i % 32), q[1])` for `i < 32` and the mirror for
# `i >= 32`, so the two arms put the new bit in DIFFERENT words. `shl` is `*` and
# `cond.cast(dtypes.uint)` is a dtype.py cast that is NOT a promotion.

def l2i_cdiv.loop(k: Nat, +c: Cd, +i: U32) -> Cd:
  match k:
    case 0n: c
    case 1n+p:
      +d = l2i_cdiv.step(Cd.ar(c), c, i)
      l2i_cdiv.loop(p, d, U32.sub(i, 1))

# `return r if op is Ops.CMOD else q`

def l2i_cdiv.uns(isdiv: Bool, +ar: O.Arena, +c: Cd) -> W2:
  match isdiv:
    case True{}: W2{ar, Cd.r0(c), 0}
    case False{}: W2{ar, Cd.q0(c), 0}

# `(nq0,nq1), (nr0,nr1) = l2i(BITCAST, dt, *l2i(NEG, uint, *q)), l2i(BITCAST, dt,
# *l2i(NEG, uint, *r))` then the un-negated pair, then the WHEREs -- in THAT
# order, because Python evaluates a tuple's elements left to right.

def l2i_cdiv.cdiv(+ar: O.Arena, +an: U32, +bn: U32, +nq: W2, +qq: W2) -> W2:
  +s = dd_xor(ar, an, bn)
  +si = O.Found.i(s)
  +r0 = dd_where(O.Found.ar(s), si, W2.lo(nq), W2.lo(qq))
  +r1 = dd_where(O.Found.ar(r0), si, W2.hi(nq), W2.hi(qq))
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

# `a_neg.where(nr0, r0)` and the same for the high word

def l2i_cdiv.cmod(+ar: O.Arena, +an: U32, +nr: W2, +rr: W2) -> W2:
  +r0 = dd_where(ar, an, W2.lo(nr), W2.lo(rr))
  +r1 = dd_where(O.Found.ar(r0), an, W2.hi(nr), W2.hi(rr))
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

def l2i_cdiv.tail(isdiv: Bool, +ar: O.Arena, +an: U32, +bn: U32, +nq: W2, +qq: W2, +nr: W2, +rr: W2) -> W2:
  match isdiv:
    case True{}: l2i_cdiv.cdiv(ar, an, bn, nq, qq)
    case False{}: l2i_cdiv.cmod(ar, an, nr, rr)

# `(a_neg^b_neg).where(nq0, q0)` and the same for the high word

def l2i_cdiv.signed(isdiv: Bool, +ar: O.Arena, +dt: S.Dt, +c: Cd) -> W2:
  +z = Cd.z(c)
  +car = Cd.ar(c)
  +q0 = Cd.q0(c)
  +q1 = Cd.q1(c)
  +r0 = Cd.r0(c)
  +r1 = Cd.r1(c)
  +ani = Cd.an(c)
  +bni = Cd.bn(c)
  +negq = l2i_cdiv.neg(car, z, q0, q1)
  +nq = l2i_bitcast(W2.ar(negq), dt, ws2(W2.lo(negq), W2.hi(negq)))
  +nar = W2.ar(nq)
  +negr = l2i_cdiv.neg(nar, z, r0, r1)
  +nr = l2i_bitcast(nar, dt, ws2(W2.lo(negr), W2.hi(negr)))
  +qar = W2.ar(nr)
  +qq = l2i_bitcast(qar, dt, ws2(q0, q1))
  +rar = W2.ar(qq)
  +rr = l2i_bitcast(rar, dt, ws2(r0, r1))
  +rrar = W2.ar(rr)
  l2i_cdiv.tail(isdiv, rrar, ani, bni, nq, qq, nr, rr)

def l2i_cdiv.finish(sgn: Bool, isdiv: Bool, +ar: O.Arena, +dt: S.Dt, +e: Cd) -> W2:
  match sgn:
    case True{}: l2i_cdiv.signed(isdiv, ar, dt, e)
    case False{}: l2i_cdiv.uns(isdiv, ar, e)

def l2i_cdiv.sign(sgn: Bool, +ar: O.Arena, +zero: U32, +a0: U32, +a1: U32, +b0: U32, +b1: U32) -> Cd:
  match sgn:
    case True{}: l2i_cdiv.abs(ar, zero, a0, a1, b0, b1)
    case False{}:
      +z = dd_const.int(ar, 0, S.uint32())
      +zi = O.Found.i(z)
      +zar = O.Found.ar(z)
      Cd{zar, zi, a0, a1, b0, b1, zi, zi, zi, zi, zi, zi}

# ===========================================================================
# `l2i`'s `match op` -- the dispatch, and the one def that creates `zero`.
# ===========================================================================

def l2i_cdiv(isdiv: Bool, +ar: O.Arena, +dt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +sgn = dd_is_i32(dt)
  +c = l2i_cdiv.sign(sgn, ar, zero, nth(ws, 0n), nth(ws, 1n), nth(ws, 2n), nth(ws, 3n))
  +e = l2i_cdiv.loop(64n, c, 63)
  l2i_cdiv.finish(sgn, isdiv, Cd.ar(e), dt, e)

def l2i.go(+ar: O.Arena, +zero: U32, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  match op:
    case O.OpsNEG{}: Some{l2i_sub(ar, ws4(zero, zero, nth(ws, 0n), nth(ws, 1n)))}
    case O.OpsCAST{}: l2i_cast(ar, dt, xdt, ws)
    case O.OpsBITCAST{}: Some{l2i_bitcast(ar, dt, ws)}
    case O.OpsSHL{}: Some{l2i_shl(ar, dt, zero, ws)}
    case O.OpsSHR{}: Some{l2i_shr(ar, dt, zero, ws)}
    case O.OpsADD{}: Some{l2i_add(ar, ws)}
    case O.OpsSUB{}: Some{l2i_sub(ar, ws)}
    case O.OpsMUL{}: Some{l2i_mul(ar, dt, ws)}
    case O.OpsCMPLT{}: Some{l2i_cmplt(ar, ws)}
    case O.OpsCMPEQ{}: Some{l2i_cmpeq(ar, ws)}
    case O.OpsCMPNE{}: Some{l2i_cmpne(ar, ws)}
    case O.OpsXOR{}: Some{l2i_binop(ar, O.OpsXOR{}, ws)}
    case O.OpsOR{}: Some{l2i_binop(ar, O.OpsOR{}, ws)}
    case O.OpsAND{}: Some{l2i_binop(ar, O.OpsAND{}, ws)}
    case O.OpsWHERE{}: Some{l2i_where(ar, ws)}
    case O.OpsMAX{}: Some{l2i_max(ar, ws)}
    case O.OpsCDIV{}: Some{l2i_cdiv(True{}, ar, dt, zero, ws)}
    case O.OpsCMOD{}: Some{l2i_cdiv(False{}, ar, dt, zero, ws)}
    case _: None{}

def l2i(+ar: O.Arena, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  # `zero = UOp.const(0, dt)` at dtype.py:22, BEFORE the arity unpacking at
  # 23-25 -- so a fixture with one word still interns it and then fails.
  +zero = dd_const.int(ar, 0, dt)
  l2i.go(O.Found.ar(zero), O.Found.i(zero), op, dt, xdt, ws)


# ===========================================================================
# `l2i_define` -- dtype.py:83-86. A DEFINES node becomes one with the 32-bit
# dtype and TWICE the size; `AddrSpace.ALU` (a Variable) is the `raise`. The
# `arg` is a `ParamArg` and `dataclasses.replace` is a full rebuild, so all
# thirteen of its fields are read and handed back -- only `dtype` and `size`
# change. `src` is empty, which is what `UOp(x.op, arg=...)` builds.
# ===========================================================================

def l2i_define.size2(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case Some{n}: Some{U32.mul(n, 2)}
    case None{}: None{}

# `replace(x.arg, dtype=l2i_dt[x.dtype], size=None if x.arg.size is None else
# x.arg.size*2)`

def l2i_define.arg(dt: S.Dt, +pa: O.ParamArg) -> O.Arg:
  O.AParam{O.ParamArg{O.ParamArg.slot(pa), dt, l2i_define.size2(O.ParamArg.size(pa)),
    O.ParamArg.vmin_vmax(pa), O.ParamArg.multiple_of(pa), O.ParamArg.name(pa),
    O.ParamArg.addrspace(pa), O.ParamArg.device(pa), O.ParamArg.volatile(pa),
    O.ParamArg.image(pa), O.ParamArg.buffer(pa), O.ParamArg.bind_on_realize(pa),
    O.ParamArg.val(pa)}}

def l2i_define.put(m: Maybe<&2, S.Dt>, +ar: O.Arena, +self: U32, +tag: O.Tag, +pa: O.ParamArg) -> Maybe<&2, O.Found>:
  match m:
    case None{}: None{}
    case Some{dt}: Some{O.UOp.new(ar, O.Arena.op(ar, self), Nil{}, l2i_define.arg(dt, pa), tag)}

def l2i_define.sel(alu: Bool, m: Maybe<&2, S.Dt>, +ar: O.Arena, +self: U32, +tag: O.Tag, +pa: O.ParamArg) -> Maybe<&2, O.Found>:
  match alu:
    case True{}: None{}
    case False{}: l2i_define.put(m, ar, self, tag, pa)

# `if x.addrspace == AddrSpace.ALU: raise` -- `O.ParamArg.addrspace` is `S.Addr`
# and `Aalu` is `AddrSpace.ALU`, so the test is a structural one and not a name.

def l2i_define.isalu(a: S.Addr) -> Bool:
  match a:
    case S.Aalu{}: True{}
    case _: False{}

def l2i_define(+ar: O.Arena, +self: U32, +pa: O.ParamArg) -> Maybe<&2, O.Found>:
  l2i_define.sel(l2i_define.isalu(O.ParamArg.addrspace(pa)),
    l2i_dt(O.ParamArg.dtype(pa)), ar, self, O.Arena.tag(ar, self), pa)

# ===========================================================================
# `rne` -- dtype.py:99, "round to nearest even" on a fixed-point word.
# `shr(v, s) + ((shr(v, s-1) & 1) & ((v & ((1 << (s-1)) - 1)).ne(0) | (shr(v, s) & 1)))`
#
# THE MASK IS A 64-BIT CONSTANT and `U32.shln` saturates to 0 past 31 (measured
# twice in this repo), so `(1 << (s-1)) - 1` is `T.tx_powi(s-1)` MINUS ONE as an
# `I64`, and the `s = 42` fixture is the row that says so. `s = 0` is `1 << -1`,
# which CPython REFUSES, so the port refuses too.
# ===========================================================================

def rne.go(+ar: O.Arena, +v: U32, +s: U32) -> O.Found:
  +a = T.tx_shr(ar, v, s)
  +sm = U32.sub(s, 1)
  +b = T.tx_shr(O.Found.ar(a), v, sm)
  +c = dd_band(O.Found.ar(b), O.Found.i(b), 1)
  +m = dd_wk(O.Found.ar(c), H.i64_sub(T.tx_powi(sm), H.i64_of_i32(1)))
  +d = dd_band(O.Found.ar(m), v, 1)
  +z = dd_wk(O.Found.ar(d), H.i64_of_i32(0))
  +e = dd_ne(O.Found.ar(z), O.Found.i(d), O.Found.i(z))
  +f = dd_band(O.Found.ar(e), O.Found.i(a), 1)
  +g = dd_or(O.Found.ar(f), O.Found.i(e), O.Found.i(f))
  +h = dd_and(O.Found.ar(g), O.Found.i(c), O.Found.i(g))
  dd_add(O.Found.ar(h), O.Found.i(a), O.Found.i(h))

# ===========================================================================
# `f2f_clamp_max` -- the `mx` CONSTANT of `f2f_clamp` (dtype.py:131), factored
# out because it is a VALUE and `f2f_clamp`'s own gate is about the GRAPH.
#
# `2.0**(max_exp - bias) * (1.0 + max_man / (1 << m))` IS
# `(2**m + max_man) * 2**(max_exp - bias - m)` with ONE rounding instead of two,
# and for every target whose mantissa is 23 bits or fewer both factors and the
# product are exact in `F32`. `float64` is the one exception (divergence E):
# its `2**m + max_man` does not fit a `U32`, so the def refuses.
# ===========================================================================

def rne.sel(zero: Bool, +ar: O.Arena, +v: U32, +s: U32) -> Maybe<&2, O.Found>:
  match zero:
    case True{}: None{}
    case False{}: Some{rne.go(ar, v, s)}

def rne(+ar: O.Arena, +v: U32, +s: U32) -> Maybe<&2, O.Found>:
  rne.sel(U32.is_zero(s), ar, v, s)

def f2f_clamp_max.put(+dt: S.Dt) -> Maybe<&2, F32>:
  +e = T.tx_finfo_e(dt)
  +m = T.tx_finfo_m(dt)
  # fnuz and fp8e4m3 are the `(1 << e) - 1, (1 << m) - 2` layouts; the rest are
  # `(1 << e) - 2, (1 << m) - 1`. `dd_is_e4m3` is NOT fnuz AND a 4-bit exponent,
  # so the two tests together read all three of dtype.py's lines.
  +ocp = Bool.or(T.tx_is_fnuz(dt), dd_is_e4m3(dt))
  +me = U32.sub(T.tx_powi32(e), Bool.pick(U32, ocp, 0, 2))
  +mm = U32.sub(T.tx_powi32(m), Bool.pick(U32, ocp, 0, 2))
  +num = U32.add(T.tx_powi32(m), mm)
  +ex = U32.sub(U32.sub(me, T.exponent_bias(dt)), m)
  +nn = U32.to_nat(num)
  Some{F32.mul(F32.from_nat(nn), F32.pow(2.0, F32.from_nat(U32.to_nat(ex))))}

# `-mx` and `-sat`: `_broadcasted`'s weak-CONST REMINT turns the integer `-1`
# into `ConstFloat(-1.0)` at elementwise.py:31-32, and that value is exact in
# `F32`. `dd_wkf` is that bare weakfloat CONST.

def f2f_clamp_max.sel(small: Bool, +dt: S.Dt) -> Maybe<&2, F32>:
  match small:
    case True{}: f2f_clamp_max.put(dt)
    case False{}: None{}

def f2f_clamp_max(+dt: S.Dt) -> Maybe<&2, F32>:
  f2f_clamp_max.sel(U32.is_le(T.tx_finfo_m(dt), 23), dt)

def dd_wkf(+ar: O.Arena, +v: F32) -> O.Found:
  O.UOp.const(ar, O.CFloat{v})

# `float('inf')` -- `F32.pow(10.0, 40)` is the literal spelling that needs no
# `import Base` constant of its own, and `H.f32_show`/the oracle agree that it
# is `inf`.

def dd_inf() -> F32:
  F32.pow(10.0, F32.from_nat(40n))

# ===========================================================================
# `f2f_clamp` -- dtype.py:127-134. The `mx` CONST is `val.const_like(...)` and
# `val` is `v.bitcast(fr)`, so `mx` lands at the SOURCE's width, which is `fr`.
# `sat` here is ALREADY `dt in dtypes.fp8s and sat`: it says whether the answer
# saturates to `mx` or is `val.const_like(float('inf'))`.
# ===========================================================================

def f2f_clamp.sat(sat: Bool, +mx: O.Found, +inf: O.Found) -> O.Found:
  match sat:
    case True{}: mx
    case False{}: inf

# ===========================================================================
# `f2f` -- dtype.py:101-125. THREE answers: widen, narrow, or `raise
# NotImplementedError` -- which is `fe > te` or `fm == tm`, and the second is
# the pair `f16 -> bf16` among them.
#
# THE WIDENING BRANCH HAS NO `f2f_clamp` AND NO FLOAT CONSTANT, so an fp8 source
# is gated there (divergence D) and the `fp8_fnuz` arm is not a dead def.
# ===========================================================================

def f2f_clamp.mx(mx: Maybe<&2, F32>, sat: Bool, +fr: S.Dt, +ar: O.Arena, +v: U32) -> Maybe<&2, O.Found>:
  match mx:
    case None{}: None{}
    case Some{f}:
      +mxc = dd_cf(ar, f, fr)
      +inf = dd_cf(O.Found.ar(mxc), dd_inf(), fr)
      +s = f2f_clamp.sat(sat, mxc, inf)
      +ne = dd_ne(O.Found.ar(s), v, v)
      +n1 = dd_wkf(O.Found.ar(ne), F32.neg(1.0))
      +nm = dd_mul(O.Found.ar(ne), O.Found.i(mxc), O.Found.i(n1))
      +lt = dd_lt1(O.Found.ar(nm), v, O.Found.i(nm))
      +ns = dd_mul(O.Found.ar(lt), O.Found.i(s), O.Found.i(n1))
      +in = dd_lt1(O.Found.ar(ns), O.Found.i(mxc), v)
      +iw = dd_where(O.Found.ar(in), O.Found.i(in), O.Found.i(s), v)
      +mw = dd_where(O.Found.ar(iw), O.Found.i(lt), O.Found.i(ns), O.Found.i(iw))
      Some{dd_where(O.Found.ar(mw), O.Found.i(ne), v, O.Found.i(mw))}

# `sat = mx if dt in dtypes.fp8s and sat else val.const_like(float('inf'))`

def f2f_clamp(+ar: O.Arena, +v: U32, +fr: S.Dt, +dt: S.Dt, +sat: Bool) -> Maybe<&2, O.Found>:
  f2f_clamp.mx(f2f_clamp_max(dt), sat, fr, ar, v)

def f2f.sel3(down: Bool) -> U32:
  match down:
    case True{}: 1
    case False{}: 2

# `fr.bitsize, exponent_bias(fr), dtypes.finfo(fr)` and the same for `to` are the
# six numbers every branch reads. `finfo` and `exponent_bias` come from
# `transcendental.bend` -- IMPORTED, not re-derived.

def f2f.sel2(wide: Bool, down: Bool) -> U32:
  match wide:
    case True{}: 0
    case False{}: f2f.sel3(down)

def f2f.udt.of(m: Maybe<&2, S.Dt>, k: S.Dt) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: k

# ---- WIDENING: `sign, nosign`, `exp, norm`, `nan`, then one of two answers.

def f2f.udt(+to: S.Dt) -> S.Dt:
  f2f.udt.of(f2f_dt(to), S.uint32())

def f2f.em1(+ar: O.Arena, +k: U32) -> U32:
  +s = dd_wk(ar, T.tx_powi(k))
  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))
  +d = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))
  O.Found.i(d)

# `shl((v & shl(1, fs-1)).cast(f2f_dt[to]), ts - fs)`

def f2f.sign(+ar: O.Arena, +udt: S.Dt, +v: U32, +fs: U32, +ts: U32) -> O.Found:
  +s = dd_wk(ar, T.tx_powi(U32.sub(fs, 1)))
  +a = dd_band(O.Found.ar(s), v, O.Found.i(s))
  +c = P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)
  +k = dd_wk(O.Found.ar(c), T.tx_powi(U32.sub(ts, fs)))
  T.tx_shl(O.Found.ar(k), O.Found.i(c), O.Found.i(k))

# `(v & (shl(1, fs-1) - 1)).cast(f2f_dt[to])`

def f2f.nosign(+ar: O.Arena, +udt: S.Dt, +v: U32, +fs: U32) -> O.Found:
  +s = dd_wk(ar, T.tx_powi(U32.sub(fs, 1)))
  +m1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))
  +m = P.dc_sub(O.Found.ar(m1), O.Found.i(s), O.Found.i(m1))
  +a = dd_band(O.Found.ar(m), v, O.Found.i(m))
  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)

# `shl(nosign, tm - fm) + shl(tb - fb, tm)`. `tb - fb` is a Python int, so both
# operands of that `*` are WEAKINT constants -- and it is never negative in the
# widening branch, which is what keeps the weakfloat remint out of this arm.

def f2f.norm(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))
  +bf = dd_wk(O.Found.ar(a), H.i64_sub(H.i64_of_i32(T.exponent_bias(to)), H.i64_of_i32(T.exponent_bias(fr))))
  +b = T.tx_shl(O.Found.ar(bf), O.Found.i(a), tm)
  dd_add(O.Found.ar(b), O.Found.i(a), O.Found.i(b))

# `shl(nosign, tm - fm) | shl((shl(1, te) - 1), tm)`

def f2f.nan(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +te: U32) -> O.Found:
  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))
  +bt = dd_wk(O.Found.ar(a), T.tx_powi(te))
  +b = T.tx_shl(O.Found.ar(bt), O.Found.i(a), tm)
  dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))

# `fnuz_nan = sign.ne(0) & nosign.eq(0)`; `qnan = shl(shl(1, te) - 1, tm) | shl(1, tm - 1)`

def f2f.fnuz(+ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +te: U32, +tm: U32) -> U32:
  +z = dd_wk(ar, H.i64_of_i32(0))
  +a = dd_ne(ar, O.Found.i(sg), O.Found.i(z))
  +b = dd_eq1(O.Found.ar(a), O.Found.i(ns), O.Found.i(z))
  +fn = dd_and(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  +q1 = T.tx_shl(O.Found.ar(fn), f2f.em1(O.Found.ar(fn), te), tm)
  +qk = dd_wk(O.Found.ar(q1), T.tx_powi(U32.sub(tm, 1)))
  +q2 = T.tx_shl(O.Found.ar(qk), O.Found.i(q1), O.Found.i(qk))
  +q = dd_or(O.Found.ar(q2), O.Found.i(q1), O.Found.i(q2))
  +e = dd_eq1(O.Found.ar(q), O.Found.i(ex), O.Found.i(z))
  +w = dd_where(O.Found.ar(e), O.Found.i(e), O.Found.i(z), O.Found.i(nm))
  +s = dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w))
  O.Found.i(dd_where(O.Found.ar(s), O.Found.i(fn), O.Found.i(q), O.Found.i(s)))

# `is_nan = nosign.eq(shl(1, fm + fe) - 1)` for `fp8e4m3` else `exp.eq(shl(1, fe) - 1)`

def f2f.isnan(+ar: O.Arena, +ns: O.Found, +ex: O.Found, +fe: U32, +fm: U32, e4m3: Bool) -> O.Found:
  match e4m3:
    case True{}:
      +m = dd_wk(ar, T.tx_powi(U32.add(fm, fe)))
      dd_eq1(ar, O.Found.i(ns), O.Found.i(m))
    case False{}:
      +m = dd_wk(ar, T.tx_powi(fe))
      dd_eq1(ar, O.Found.i(ex), O.Found.i(m))

# ---- NARROWING

def f2f.ocp(e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32) -> U32:
  +i = f2f.isnan(ar, ns, ex, fe, fm, e4m3)
  +z = dd_wk(O.Found.ar(i), H.i64_of_i32(0))
  +e = dd_eq1(O.Found.ar(z), O.Found.i(ex), O.Found.i(z))
  +w = dd_where(O.Found.ar(e), O.Found.i(e), O.Found.i(z), dd_where(O.Found.ar(e), O.Found.i(i), O.Found.i(nn), O.Found.i(nm)))
  O.Found.i(dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w)))

def f2f.up.tail(fnuz: Bool, e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32, +te: U32, +tm: U32) -> U32:
  match fnuz:
    case True{}: f2f.fnuz(ar, ns, sg, ex, nm, te, tm)
    case False{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm)

def f2f.up.tail(fnuz: Bool, e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32, +te: U32, +tm: U32) -> U32:
  match fnuz:
    case True{}: f2f.fnuz(ar, ns, sg, ex, nm, te, tm)
    case False{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm, te)

# `shl(1, k) - 1`, the mask dtype.py writes four times. `P.dc_sub` is
# `a - 1` = `ADD(a, MUL(C(1), C(-1)))`.

def f2f.up(+fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +udt = f2f.udt(to)
  +fs = S.Dt.bits(fr)
  +ts = S.Dt.bits(to)
  +sg = f2f.sign(ar, udt, v, fs, ts)
  +ns = f2f.nosign(O.Found.sg(ar), udt, v, fs)
  +ex = T.tx_shr(O.Found.ns(ar), ns, fm)
  +nm = f2f.norm(O.Found.ex(ar), ns, fm, tm, fr, to)
  +nn = f2f.nan(O.Found.nm(ar), ns, tm, te)
  T.tx_bitcast(O.Found.ar(nn), f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), ar, ns, sg, ex, nm, nn, fe, fm, te, tm), to)

def f2f.down.sign(+ar: O.Arena, +v: O.Found, +fs: U32, +ts: U32) -> O.Found:
  +a = T.tx_shr(ar, v, U32.sub(fs, ts))
  +b = T.tx_shl(O.Found.ar(a), dd_wk(O.Found.ar(a), T.tx_powi(U32.sub(ts, 1))), U32.sub(ts, 1))
  dd_band(O.Found.ar(b), O.Found.i(a), O.Found.i(b))

# `v & (shl(1, fs - 1) - 1)`

def f2f.down.nosign(+ar: O.Arena, +v: O.Found, +fs: U32) -> O.Found:
  +s = dd_wk(ar, T.tx_powi(U32.sub(fs, 1)))
  +m = P.dc_sub(O.Found.ar(s), s, dd_wk(ar, H.i64_of_i32(1)))
  dd_band(O.Found.ar(m), O.Found.i(v), O.Found.i(m))

# `(rne(nosign, fm - tm) - shl(fb - tb, tm)).cast(f2f_dt[to])`

def f2f.down.norm.g(r: Maybe<&2, O.Found>, +tudt: S.Dt, +ar: O.Arena, +fr: S.Dt, +to: S.Dt) -> O.Found:
  match r:
    case Some{x}:
      +b = T.tx_shl(O.Found.ar(x), dd_wk(O.Found.ar(x), H.i64_sub(H.i64_of_i32(T.exponent_bias(fr)), H.i64_of_i32(T.exponent_bias(to)))), T.tx_finfo_m(to))
      +d = P.dc_sub(O.Found.ar(b), O.Found.i(x), O.Found.i(b))
      P.dc_cast(O.Found.ar(d), O.Found.i(d), tudt)
    case None{}: dd_const.int(ar, 0, tudt)

# `underflow = (shr(v, fm) & (shl(1, fe) - 1)) < (1 + fb - tb)`. The right side is
# a Python int, so `ufix` makes it a WEAKINT const and the promotion folds.

def f2f.down.norm(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +tudt = f2f.udt(to)
  f2f.down.norm.g(rne(ar, ns, U32.sub(fm, tm)), tudt, ar, fr, to)

def f2f.down.uf(+ar: O.Arena, +v: O.Found, +fm: U32, +fe: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +a = T.tx_shr(ar, v, fm)
  +m = f2f.em1(O.Found.ar(a), fe)
  +b = dd_band(O.Found.ar(m), O.Found.i(a), m)
  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))
  dd_lt1(O.Found.ar(c), O.Found.i(b), O.Found.i(c))

# `nan_mantissa = (shl(1, tm) - 1) if to == dtypes.fp8e4m3 else (shr(nosign, fm - tm) & (shl(1, tm) - 1))`

def f2f.down.m1(+ar: O.Arena, +tm: U32) -> O.Found:
  +s = dd_wk(ar, T.tx_powi(tm))
  P.dc_sub(O.Found.ar(s), s, dd_wk(ar, H.i64_of_i32(1)))

def f2f.down.m2(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32) -> O.Found:
  +a = T.tx_shr(ar, ns, U32.sub(fm, tm))
  +s = dd_wk(O.Found.ar(a), T.tx_powi(tm))
  +m = P.dc_sub(O.Found.ar(s), s, dd_wk(ar, H.i64_of_i32(1)))
  dd_band(O.Found.ar(m), O.Found.i(a), O.Found.i(m))

# `(sign | nan_mantissa | shl(shl(1, te) - 1, tm)).cast(f2f_dt[to])`

def f2f.down.mant(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, e4m3: Bool) -> O.Found:
  match e4m3:
    case True{}: f2f.down.m1(ar, tm)
    case False{}: f2f.down.m2(ar, ns, fm, tm)

def f2f.down.nan(+ar: O.Arena, +sg: O.Found, +nm: O.Found, +te: U32, +tm: U32, +to: S.Dt) -> O.Found:
  +tudt = f2f.udt(to)
  +a = dd_or(ar, O.Found.i(sg), O.Found.i(nm))
  +b = T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)
  +c = dd_or(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  P.dc_cast(O.Found.ar(c), O.Found.i(c), tudt)

# `is_nan = (shr(v, fm) & (shl(1, fe) - 1)).eq(shl(1, fe) - 1)`. The AND is the
# one `underflow` built, so it is interned; the `eq` is two CMPNEs.

def f2f.down.isnan(+ar: O.Arena, +v: O.Found, +fm: U32, +fe: U32, +uf: O.Found) -> O.Found:
  +a = T.tx_shr(ar, v, fm)
  +m = f2f.em1(O.Found.ar(a), fe)
  +b = dd_band(O.Found.ar(m), O.Found.i(a), m)
  dd_eq1(O.Found.ar(b), b, m)

# the two returns. `sign.cast(f2f_dt[to]) | norm` appears in BOTH, inside
# `underflow.where(0, ...)`, and CPython evaluates only the taken branch.

def f2f.down.inner(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +to: S.Dt) -> O.Found:
  +c = P.dc_cast(ar, O.Found.i(sg), f2f.udt(to))
  dd_or(O.Found.ar(c), O.Found.i(c), O.Found.i(nr))

def f2f.down.fnuz(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +uf: O.Found, +ii: O.Found, +ts: U32, +to: S.Dt) -> O.Found:
  +inner = f2f.down.inner(O.Found.ii(ar), sg, nr, to)
  +z = dd_const.int(O.Found.ar(inner), 0, f2f.udt(to))
  +w = dd_where(O.Found.ar(z), O.Found.i(uf), z, O.Found.i(inner))
  dd_where(O.Found.ar(w), O.Found.i(ii), dd_wk(O.Found.ar(w), T.tx_powi(U32.sub(ts, 1))), O.Found.i(w))

def f2f.down.ocp(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +uf: O.Found, +ii: O.Found, +nm: O.Found, +to: S.Dt) -> O.Found:
  +inner = f2f.down.inner(O.Found.ii(ar), sg, nr, to)
  +z = dd_const.int(O.Found.ar(inner), 0, f2f.udt(to))
  +w = dd_where(O.Found.ar(z), O.Found.i(uf), z, O.Found.i(inner))
  dd_where(O.Found.ar(w), O.Found.i(ii), O.Found.i(nm), O.Found.i(w))

# ===========================================================================
# THE THREE PATTERN TABLES -- dtype.py:148, :181 and :218. They are
# `PMEntrys`: one entry per rule, carrying the op set the rule CLAIMS and the
# `early_reject` set it rejects on. That is the same shape `op.bend` uses for
# its own two tables, for the same reason -- the rules' BODIES are lambdas over a
# `ctx` that `graph_rewrite` supplies, and what is gateable without the rewrite
# engine is the TABLE.
#
# `nlong<N>r` is the reject set and `nlong<N>o` the claimed ops, so a rule that
# loses its reject set (dtype.py:162's `CONST`, and `LOAD`/`BITCAST` in the
# float table) is a red row rather than a silent loss of discrimination.
# `pm_dtype_decomps`' first rule claims `GroupOp.All` -- EVERY op -- so its op
# column is the whole `Ops` list and `ndtype0o` is the row that says so.
# ===========================================================================

def f2f.down.tail(fnuz: Bool, +ar: O.Arena, +sg: O.Found, +nr: O.Found, +uf: O.Found, +ii: O.Found, +nm: O.Found, +ts: U32, +to: S.Dt) -> O.Found:
  match fnuz:
    case True{}: f2f.down.fnuz(ar, sg, nr, uf, ii, ts, to)
    case False{}: f2f.down.ocp(ar, sg, nr, uf, ii, nm, to)

def f2f.narrow(+v: O.Found, +udt: S.Dt, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +fs = S.Dt.bits(fr)
  +ts = S.Dt.bits(to)
  +sg = f2f.down.sign(O.Found.ar(v), v, fs, ts)
  +ns = f2f.down.nosign(O.Found.sg(ar), v, fs)
  +nr = f2f.down.norm(O.Found.ns(ar), ns, fm, tm, fr, to)
  +uf = f2f.down.uf(O.Found.nr(ar), v, fm, fe, fr, to)
  +nm = f2f.down.mant(O.Found.uf(ar), ns, fm, tm, dd_is_e4m3(to))
  +nn = f2f.down.nan(O.Found.nm(ar), sg, nm, te, tm, to)
  +ii = f2f.down.isnan(O.Found.ar(nn), v, fm, fe, uf)
  f2f.down.tail(T.tx_is_fnuz(to), O.Found.ii(ar), sg, nr, uf, ii, nm, ts, to)

# `shr(v, fs - ts) & shl(1, ts - 1)`

def f2f.clamped(m: Maybe<&2, O.Found>, +udt: S.Dt, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  match m:
    case None{}: None{}
    case Some{c}: Some{f2f.narrow(T.tx_bitcast(O.Found.ar(c), O.Found.i(c), udt), udt, fe, fm, te, tm, ar, fr, to)}

# `v = f2f_clamp(v.bitcast(fr), to, sat).bitcast(f2f_dt[fr])`, renamed `v`, then
# the two halves and the two return shapes. `fs` is the SOURCE's bit width,
# which is 64 for a `float64` source.

def f2f.down.has(mx: Maybe<&2, F32>, sat: Bool, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  match mx:
    case None{}: None{}
    case Some{+m}:
      +bc = T.tx_bitcast(ar, v, fr)
      f2f.clamped(f2f_clamp(O.Found.ar(bc), O.Found.i(bc), fr, to, dd_is_fp8(to)), f2f.udt(fr), fe, fm, te, tm, ar, fr, to)

def f2f.down(sat: Bool, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  f2f.down.has(f2f_clamp_max(to), sat, fe, fm, te, tm, ar, v, fr, to)

def f2f.sel(sel: U32, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt, +sat: Bool) -> Maybe<&2, O.Found>:
  match sel:
    case 0: Some{f2f.up(fe, fm, te, tm, ar, v, fr, to)}
    case 1: f2f.down(sat, fe, fm, te, tm, ar, v, fr, to)
    case _: None{}

def f2f(+ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt, +sat: Bool) -> Maybe<&2, O.Found>:
  +fe = T.tx_finfo_e(fr)
  +fm = T.tx_finfo_m(fr)
  +te = T.tx_finfo_e(to)
  +tm = T.tx_finfo_m(to)
  +wide = Bool.and(U32.is_le(fe, te), U32.is_lt(fm, tm))
  +down = Bool.and(U32.is_ge(fe, te), U32.is_gt(fm, tm))
  f2f.sel(f2f.sel2(wide, down), fe, fm, te, tm, ar, v, fr, to, sat)

# `f2f_dt[to]` read four times, and the value is `Maybe` only so that a
# non-float target is `None`; `f2f` never gets one, so the reader's `Maybe` is
# unwrapped once and the `k` arm is the arena's BOTTOM dtype, which no arm uses.

def pm_long_decomp() -> O.PMEntrys:
  O.PMEntrys{[
    # 150  GroupOp.All, any dtype
    O.PMEntry{0,  O.Ops.all(), Nil{}},
    # 151  GroupOp.Defines at a long dtype
    O.PMEntry{1,  [O.OpsALLOC{}, O.OpsBUFFER{}, O.OpsPARAM{}], Nil{}},
    # 152  INDEX at a long dtype
    O.PMEntry{2,  [O.OpsINDEX{}], Nil{}},
    # 154  STORE of an index at a long dtype
    O.PMEntry{3,  [O.OpsSTORE{}], Nil{}},
    # 157  a Comparison over long-dtype operands
    O.PMEntry{4,  [O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}], Nil{}},
    # 159  CAST from a long word
    O.PMEntry{5,  [O.OpsCAST{}], Nil{}},
    # 162  CAST of a CONST, rejected on CONST -- the ONLY entry with a reject
    O.PMEntry{6,  [O.OpsCAST{}], [O.OpsCONST{}]},
    # 164  CAST from a long word, long target
    O.PMEntry{7,  [O.OpsCAST{}], Nil{}},
    # 166  CAST into a long from anywhere
    O.PMEntry{8,  [O.OpsCAST{}], Nil{}},
    # 168  SHL / SHR at a long dtype
    O.PMEntry{9,  [O.OpsSHL{}, O.OpsSHR{}], Nil{}},
    # 170  WHERE at a long dtype
    O.PMEntry{10, [O.OpsWHERE{}], Nil{}},
    # 173  every other ALU op at a long dtype
    O.PMEntry{11, O.Ops.alu(), Nil{}},
    # 176  LOAD at a long dtype
    O.PMEntry{12, [O.OpsLOAD{}], Nil{}}]}

def pm_float_decomp() -> O.PMEntrys:
  O.PMEntrys{[
    # 182  GroupOp.Defines at a float dtype
    O.PMEntry{0,  [O.OpsALLOC{}, O.OpsBUFFER{}, O.OpsPARAM{}], Nil{}},
    # 185  INDEX / SHRINK over a converted node
    O.PMEntry{1,  [O.OpsINDEX{}, O.OpsSHRINK{}], Nil{}},
    # 188  LOAD at a float dtype
    O.PMEntry{2,  [O.OpsLOAD{}], Nil{}},
    # 190  BITCAST over a LOAD, rejected on LOAD
    O.PMEntry{3,  [O.OpsBITCAST{}], [O.OpsLOAD{}]},
    # 193  BITCAST from a float
    O.PMEntry{4,  [O.OpsBITCAST{}], Nil{}},
    # 196  BITCAST to a float
    O.PMEntry{5,  [O.OpsBITCAST{}], Nil{}},
    # 198  CAST to a float
    O.PMEntry{6,  [O.OpsCAST{}], Nil{}},
    # 200  any ALU op, plus STACK and INDEX
    O.PMEntry{7,  O.Ops.alu_st(), Nil{}},
    # 202  STORE of a converted value
    O.PMEntry{8,  [O.OpsSTORE{}], [O.OpsBITCAST{}]},
    # 204  STORE of a float value
    O.PMEntry{9,  [O.OpsSTORE{}], Nil{}}]}

def pm_dtype_decomps() -> O.PMEntrys:
  O.PMEntrys{[
    # 220  GroupOp.All restricted by DTYPE
    O.PMEntry{0,  O.Ops.all(), Nil{}},
    # 223  the SINK that runs the whole pass
    O.PMEntry{1,  [O.OpsSINK{}], Nil{}}]}

# ===========================================================================
# THE REWRITE HALF, PORTED IN SHAPE. Each of these is a Python def whose ONE
# hard call is `graph_rewrite`, so the arguments, the `ctx`, the `bottom_up=True`
# and the table choice are all here and the call itself answers "no node". The
# header states the wall; `wall` is the one predicate they all end in.
# ===========================================================================

def graph_rewrite.wall(x: U32) -> Maybe<&2, U32>:
  None{}

# `split_l2i` -- dtype.py:88-92. Both word halves of a node ask for the same
# split, so `ctx` memoises it for the pass; `l2i` recurses on itself.

def graph_rewrite(x: U32, pm: O.PMEntrys, ctx: U32, bottom_up: Bool) -> Maybe<&2, U32>:
  graph_rewrite.wall(x)

def split_l2i(ctx: U32, op: O.Op, dt: S.Dt, ws: List<&2, U32>) -> Maybe<&2, W2>:
  graph_rewrite(O.Arena.next(O.Arena.empty()), pm_long_decomp(), 0, True{})

# `l2i_rewrite_idx` -- dtype.py:94

def l2i_rewrite_idx(ctx: U32, idx: U32) -> Maybe<&2, U32>:
  graph_rewrite(idx, pm_long_decomp(), 0, True{})

# `f2f_load` -- dtype.py:136-139. `x.max_numel()` picks the single-value arm or
# the STACK arm, and both reindex with `mul = 1`, which is what makes a lane
# index a lane index and not a word index.

def f2f_load(x: U32, fr: S.Dt, to: S.Dt) -> Maybe<&2, U32>:
  graph_rewrite(x, pm_float_decomp(), 0, True{})

# `f2f_store` -- dtype.py:141-143

def f2f_store(st: U32, idx: U32, val: U32, fr: S.Dt, to: S.Dt) -> Maybe<&2, U32>:
  graph_rewrite(st, pm_float_decomp(), 0, True{})

# `f2f_rewrite` -- dtype.py:145

def f2f_rewrite(ctx: U32, x: U32) -> Maybe<&2, U32>:
  graph_rewrite(x, pm_float_decomp(), 0, True{})

# `do_dtype_decomps` -- dtype.py:208-216. The one thing here that is NOT the
# wall is the TABLE CHOICE: `pm = pm_float_decomp if fr in dtypes.floats else
# pm_long_decomp`, which is the difference between decomposing a long and
# decomposing a float, so it is a `Bool` the gate reads.

def do_dtype_decomps.pmf(isfl: Bool, fr: S.Dt, c: U32) -> O.PMEntrys:
  match isfl:
    case True{}: pm_float_decomp()
    case False{}: pm_long_decomp()

def do_dtype_decomps(sink: U32, ctx: U32) -> Maybe<&2, U32>:
  graph_rewrite(sink, do_dtype_decomps.pmf(False{}, 0, False{}), 0, True{})

def main() -> None:
  IO.print("dtype.bend")
