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
# modelled, so the arm is absent rather than wrong. The gate row is `lgu` and it
# prints `refused:unported`. CPython does not raise: the answer is
# `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` (dtype.py:35-38, two f32 words).
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
# CONTROL, dd-fix round 1 (2026-10-04): this comment block is a comment and nothing
# else, and the gate is required to read the SAME 172 rows byte for byte. Recorded
# because the THREE arena-aliasing defects fixed this round -- `l2i_shl.hi`
# (dtype.py:41-44), `l2i_cdiv.abs` (dtype.py:58-61) and `l2i_cdiv.signed`
# (dtype.py:71) -- are the kind a green gate cannot tell from a fixed one: each read
# as a plausible string, and `--check-only` said `ALL PROOFS CHECK` on every one of
# them. See `.agents/slop/notes/bend2-constraints.md` at the end.
#
# CONTROL, dd-fix round 2 (2026-10-04): this comment block is a comment and nothing else,
# and the gate is required to read the SAME 182 rows byte for byte. Recorded because the
# SIX defects closed this round are the same SPECIES as round 1's -- each read as a
# plausible string and `--check-only` said `ALL PROOFS CHECK` on every one of them -- and
# three of the six were not operand errors at all:
#
#   1. `l2i_cdiv.step` (dtype.py:65) built `AND` over the SHL result's low word and over
#      the ARENA INDEX of `C(1)` where upstream says the SHR result's low word and the
#      literal `1`. The SHR subtree was built, dead, and off the cone.
#   2. `l2i_cdiv.step` (dtype.py:67) handed `l2i(SUB, ...)` the CMPLT ARM'S ANSWER where
#      dtype.py:66 and :67 spell the SAME `*r`.
#   3. `l2i_cdiv.abs.c` (dtype.py:61) handed the B-side `.where` pair the A-SIDE
#      negation's words, so `nb`'s own low word was built and never read.
#   4. `l2i_cdiv.abs` (dtype.py:59) minted four BITCASTs that `mixin/dtype.py:53` folds
#      on a `u32` source, which is why `xdt` is a parameter of `abs`, `sign`, `cdiv`.
#   5. `dd_fuel` was `32 * (to - from)` -- the CREATION WINDOW -- so a fixture that
#      interns NOTHING got fuel 64 and `lgtsig`/`lgrsig` read 57 and 112 nodes against
#      CPython's 2184 and 2218. A TRUNCATED WALK, not a small graph.
#   6. `l2i_cast1.quo` (dtype.py:34) did not model `mixin/elementwise.py`'s weak-CONST
#      REMINT, so `2**32` stayed the integer `C(1:0)` instead of `F(1333788672)` and
#      `x < 0` reused the `C(0)` that `lo.ne(0)` owns.
#
# WHAT IS STILL RED AND WHY, so the next reader does not re-derive it: `c7`, `lgu` and
# `lgun` are DECLARED refusals (`refused:unported`), and `lg1n`/`lg6n`/`lg9n`/`lgqn` are
# not port defects at all. `<nm>n=` is the SLOTS MINTED, a property of
# `UOpMetaClass.ucache` and so of the SESSION, and dd-oracle.py's `main()` MINTS UOPS
# before the first `l2i` row: it prints
# `u32n=len(L2I()) + ... + len(IDX()) + len(defines())` and `IDX()` builds
# `UOp.const(0, dtypes.u32)`, `UOp.const(1, dtypes.u32)` and a `t` PARAM. The port's
# `fixtures()` builds dd-oracle's module-level `WORD` then `WPOOL` and nothing else.
# MEASURED, `.agents/slop/dd-slotprobe.bend` with its `pre` switch ON and NOTHING in this
# file changed: `lg1n` 11 -> 10, `lg6n` 5 -> 4, `lg9n` 18 -> 17, i.e. all three agree
# exactly. `lgqn` goes 2495 -> 2494 against CPython's 2496, and that residue is
# divergence B: this file does not build `_broadcasted`'s promotion CASTs, so its `lg1`
# interns `MUL(Pu320, C(-1))` where CPython interns `MUL(<promo cast>, C(-1))` -- a
# DIFFERENT node -- and `lgq` then reuses the port's. Closing that would need 69 more
# nodes per window and would break every `*sig` row.
#
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
# `UOp.const(v, dt)` -- divergence A. THE INTEGER PATH IS `int(val)` AND NOT A
# WIDTH WRAP, and that is the whole reason the word here is an `H.I64` and not a
# `U32`.
#
# MEASURED, not read off `truncate`: `DType.const` (tinygrad/dtype.py:79-84) ends
# `... else int(val)`, and `truncate` reaches only the FLOAT branch's
# `truncate.get(self, float)`. `UOp.const` (uop/ops.py:628-635) is
# `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`, so the CONST's arg is
# the raw Python int whatever `dt` is.
#
# It is OBSERVABLE, and in both directions. `dd-probe-intern.py`:
#     UOp.const(-1, dtypes.uint32).src[0].arg   ->  -1
#     UOp.const(4294967295, dtypes.uint32)     ->  4294967295
# so dtype.py:32's `lo.const_like(-1)` (uop/ops.py:600-602 -> `UOp.const`) leaves
# `-1` in the arena even when `lo` is `u32`. A port that wraps to the width stores
# `4294967295` there, which is the same 32 bits and a DIFFERENT node: the gate
# reads the word, and `lg6k`/`lg6p` say `C(4294967295)` where CPython says
# `C(-1)`.
#
# `truncate` for the integer dtypes IS a width wrap (tinygrad/dtype.py:298-299,
# `ctypes.c_int32(x).value`), so a port that modelled IT would be right about the
# float dtypes and wrong about every integer one. The comment this replaced
# claimed the opposite.
# ===========================================================================

def dd_const.int(+ar: O.Arena, +v: H.I64, +dt: S.Dt) -> O.Found:
  +c = O.UOp.const(ar, O.CInt{v})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{dt}, O.TNone{})

# `UOp.const(v)` with NO dtype: `from_py` answers `weakint`, the `.cast` folds,
# and the value keeps Python's sign. This is `shl`/`shr`'s `2**y` and every bare
# integer literal in the file.

def dd_wk(+ar: O.Arena, +v: H.I64) -> O.Found:
  O.UOp.const(ar, O.CInt{v})

# `remint`'s RESULT -- `mixin/elementwise.py:29-31` promotes a weak CONST to
# `weak_dtype(out_dtype)`, which is `weakfloat` for every float (`dtype.py:175-176`),
# so a Python integer written against a float operand stops being an integer constant.
# `UOp.ccast` (`ops.py:637`) is `UOp.const(self.val, dt)` for a CONST, so the remint is
# ONE node and not a CAST, and `weakfloat.const` is `float(val)` (`dtype.py:79-84`).
#
# MEASURED, `.agents/slop/dd-f32probe.bend`:
#     F32.bits(F32.pow(2.0, F32.from_nat(32n))) == 1333788672
#     F32.bits(0.0)                            == 0
# and CPython's `lg5k` reads `F(1333788672),F(0),C(0),C(-1)`. `F32.show` is NOT the
# witness -- it prints 4294967300 for the same value, which is why dd-oracle.py packs
# to `struct 'f'` and prints the BITS.
def dd_wf(+ar: O.Arena, +v: F32) -> O.Found:
  O.UOp.const(ar, O.CFloat{v})

# `UOp.const(v, dt)` for a FLOAT `dt`: the pair, because a float `from_py` is
# `weakfloat`. `f2f_clamp` is the only caller.

def dd_cf(+ar: O.Arena, +v: F32, +dt: S.Dt) -> O.Found:
  +c = O.UOp.const(ar, O.CFloat{v})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{dt}, O.TNone{})

# `const_like(v)` at a dtype the caller already holds. The receiver's dtype is
# a PARAMETER (`xdt` in `l2i`, `fr` in `f2f_clamp`) because `ops.bend`'s arena
# has no dtype field -- `dtype_from_uop` is `fold.bend`'s job.

def dd_clike(+ar: O.Arena, +v: H.I64, +dt: S.Dt) -> O.Found:
  dd_const.int(ar, v, dt)

# `x.bitcast(dt)` -- mixin/dtype.py:53, `return self if self.dtype == dt else
# self._wrap_uop(self._uop.alu(Ops.BITCAST, arg=dt))`. THE FOLD IS HALF OF THE
# OPERATOR AND IT IS NOT COSMETIC: `l2i`'s words are read as `u32` for the
# arithmetic and the whole uint half of `dtype.py:41-49` is a no-op on a `u32`
# source.
#
# MEASURED, `dd-cone.py lga`: dtype.py:42's `a0u, a1u, n = a0.bitcast(dtypes.uint),
# a1.bitcast(dtypes.uint), (b0 & 31).cast(dtypes.uint)` interns NO BITCAST and NO
# CAST at all on a `u32` fixture -- the cone's `SHR` src is `PARAM u320` and its
# shift count is the `AND` node itself. A port that always builds the node puts two
# BITCASTs and a CAST into `lgasig` that CPython does not have, and every cone
# constant, sig and slot row downstream of them is wrong with it.
#
# `cast` folds the same way (mixin/dtype.py:36), so `dd_bcast` and `dd_cast_fold`
# are one rule asked twice; `unpack32.bc` and `l2i_cast3.bitc` are the same
# question with `uint32` hard-wired, and they are now CALLS rather than copies.
def dd_bcast(isu: Bool, +ar: O.Arena, +x: U32, +dt: S.Dt) -> O.Found:
  match isu:
    case True{}: O.Found{ar, x}
    case False{}: T.tx_bitcast(ar, x, dt)

# ===========================================================================
# THE OPERATOR SHAPES of `mixin/elementwise.py`, without its promotions -- see
# divergence B. A def's order is the order CPython creates nodes in, because the
# arena's creation order is one of the gate's four facts.
#
# `a == b` IS NOT A `CMPEQ`: `elementwise.py:337` is `self.ne(x).logical_not()`
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
#
# BOTH HALVES OF THAT SENTENCE WERE FALSE IN THE BODY THIS COMMENT SITS ON, and
# both were measured rather than guessed. `.agents/slop/dd-probe-ops.py`, called
# live on `(31 - n)` with `n = (b0 & 31).cast(dtypes.uint)`:
#
#     ADD(u32)
#       CONST 31
#       MUL(u32)
#         AND(u32){ PARAM b0, CONST 31 }      <- `n` ITSELF, and the CAST is gone
#         CONST -1
#
# so (1) there is NO `SUB` at all -- `neg` is `self * (-1)`
# (mixin/elementwise.py:82), and (2) the `31` is the integer 31, NOT `2**31`,
# which is what `T.tx_powi(31)` builds. `31` is already interned by `b0 & 31`
# (dtype.py:42), so CPython mints exactly ONE new constant here -- the `-1` -- and
# a port that builds `C(2**31)` mints a constant CPython does not and misses the
# one it does. That is `lg9k`/`lgak`/`lgbk` in full: the port printed
# `C(2147483648)` where CPython has nothing, and had no `C(-1)` at all.
def dd_rsub31(+ar: O.Arena, +n: U32) -> O.Found:
  +c = dd_wk(ar, H.i64_of_i32(31))
  +m = dd_wk(O.Found.ar(c), H.i64_of_i32(4294967295))
  +mn = dd_mul(O.Found.ar(m), n, O.Found.i(m))
  dd_add(O.Found.ar(mn), O.Found.i(c), O.Found.i(mn))

# ===========================================================================
# `unpack32` -- dtype.py:13. `v.bitcast(dtypes.uint) & 0xFFFF` and
# `shr(v.bitcast(dtypes.uint), 16)`, so the BITCAST is built ONCE and both
# halves read it, which is what CPython's interning does with its two calls.
# ===========================================================================

def unpack32.bc(isu: Bool, +ar: O.Arena, +v: U32) -> O.Found:
  dd_bcast(isu, ar, v, S.uint32())

def unpack32(+ar: O.Arena, +v: U32, +xdt: S.Dt) -> W2:
  +bc = unpack32.bc(O.eq_dt(xdt, S.uint32()), ar, v)
  +lo = dd_band(O.Found.ar(bc), O.Found.i(bc), 65535)
  +hi = T.tx_shr(O.Found.ar(lo), O.Found.i(bc), 16)
  W2{O.Found.ar(hi), O.Found.i(lo), O.Found.i(hi)}

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

# dtype.py:28-40 IS FOUR `case ... if` CLAUSES AND PYTHON TAKES THE FIRST THAT
# MATCHES, so the selector is first-wins over three Booleans and NOT a priority
# list. Guard 1 is `dt in (long,ulong) AND the source is NOT a float`, guard 2 is
# `dt in (long,ulong)` ALONE -- so `dt` being a float is never consulted while it
# is a long, and guard 3's `dt in dtypes.floats` can only be reached once guards 1
# and 2 have both failed, which means `dt` is not a long. The float test on the
# TARGET is therefore asked only in the `lng == False` arm, and the float test on
# the SOURCE is INVERTED relative to what the name suggests: a NON-float source is
# the one that lands on arm 0.
#
# Arm 2 needs `dt in dtypes.floats`, which is a FLOAT target for a function called
# "long as 2 ints", so no fixture in the table reaches it and it stays a refusal.
# `sel == 2` is the one selector value with no arm behind it.
def dd_cast_sel(lng: Bool, srcfl: Bool, flt: Bool) -> U32:
  match lng:
    case True{}: Bool.pick(U32, srcfl, 1, 0)
    case False{}: Bool.pick(U32, flt, 2, 3)

# `(x < x.const_like(0)).where(lo.const_like(-1), lo.const_like(0))` -- dtype.py:32.
# THE SIGN EXTENSION IS `-1` AND NOT `2**32-1`. dtype.py:32 writes `-1` and
# `const_like` (uop/ops.py:600-602) is `UOp.const(-1, lo.dtype)`, whose arg is
# `dtype.const(-1)` = `int(-1)` (tinygrad/dtype.py:84) -- so the arena word is `-1`
# for `l2i_dt[ulong]` = `u32` exactly as it is for `int`. MEASURED: the `u32`
# fixture `lg6` answers `CAST(u32)` over `CONST arg=-1`. A `U32`-typed parameter
# cannot spell `-1`, which is the reason `dd_clike` takes an `H.I64`.

def l2i_cast0.sgn(+ar: O.Arena, +x: U32, +ldt: S.Dt, +xdt: S.Dt) -> O.Found:
  +x0 = dd_clike(ar, H.i64_of_i32(0), xdt)
  +c = dd_lt1(O.Found.ar(x0), x, O.Found.i(x0))
  +cm = dd_clike(O.Found.ar(c), H.i64_of_i32(4294967295), ldt)
  +cmi = O.Found.i(cm)
  +c0 = dd_clike(O.Found.ar(cm), H.i64_of_i32(0), ldt)
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
  +z = dd_clike(loar, H.i64_of_i32(0), ldt)
  +s = l2i_cast0.sgn(O.Found.ar(z), x, ldt, xdt)
  +l = l2i_cast0.pick(zeroext, loar, z, s)
  W2{O.Found.ar(l), loi, O.Found.i(l)}


# -- arm 1: a long CAST off a float source (dtype.py:33-34)

def l2i_cast1.quo(+ar: O.Arena, +x: U32, +ldt: S.Dt, +xdt: S.Dt, +loi: U32) -> O.Found:
  # ⚠ dtype.py:34's `2**32` AND `0` ARE PYTHON INTEGERS AND BOTH GO THROUGH
  # `_broadcasted`'s `promote` (`mixin/elementwise.py:29-31`), WHICH REMINTS A weak
  # CONST TO `weak_dtype(out_dtype)` = `weakfloat`. So the `RECIPROCAL`'s operand is the
  # FLOAT 4294967296.0 and NOT `C(1:0)`, and `x < 0`'s ZERO is a node of its own rather
  # than the `C(0)` that `lo.ne(0)` reuses -- `promote` returns `t` unchanged there
  # because `lo` is `int32`, so `weak_dtype(int32) == weakint == t.dtype`.
  #
  # `_broadcasted` BUILDS `self.ufix(y)` BEFORE it remints, so the weakint `2**32` is
  # minted and then left unreferenced; `lg5n` counts it and `lg5sig` does not, which is
  # the same shape as every other dead node in this file.
  #
  # MEASURED: CPython's `lg5k` is `F(1333788672),F(0),C(0),C(-1)` where the port read
  # `C(1:0),C(0),C(-1)`, and `lg5sig` was one `CONST/0` short at the position of the
  # float zero. `.agents/slop/dd-cone-py.py lg5` prints CPython's cone with labels; the
  # two float constants are at its positions 6 and 10.
  +ci = dd_wk(ar, T.tx_powi(32))
  +c = dd_wf(O.Found.ar(ci), F32.pow(2.0, F32.from_nat(32n)))
  +rc = T.tx_alu1(O.Found.ar(c), O.OpsRECIPROCAL{}, O.Found.i(c))
  +xf = dd_cast_bool(O.Found.ar(rc), x, dd_is_bool(xdt))
  +m = dd_mul(O.Found.ar(xf), O.Found.i(xf), O.Found.i(rc))
  +hi = P.dc_cast(O.Found.ar(m), O.Found.i(m), ldt)
  +z0 = dd_wk(O.Found.ar(hi), H.i64_of_i32(0))
  +x0 = dd_wf(O.Found.ar(z0), 0.0)
  +lt = dd_lt1(O.Found.ar(x0), x, O.Found.i(x0))
  +nz = dd_ne(O.Found.ar(lt), loi, O.Found.i(z0))
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

# `UOp.bitcast` FOLDS when the dtype already agrees (mixin/dtype.py:53), so on a
# `uint32` source there is no BITCAST at all -- which is what makes `lg7` answer the
# very node `lg2`/`lg6` already interned, with `n = 0`. `l2i` hands the port `xdt`
# precisely so this fold can be asked, and `dd_bcast` is the same question.
def l2i_cast3.bitc(isu: Bool, +ar: O.Arena, +a0: U32) -> O.Found:
  dd_bcast(isu, ar, a0, S.uint32())

def l2i_cast3(+ar: O.Arena, +a0: U32, +dt: S.Dt, +xdt: S.Dt) -> W2:
  +bc = l2i_cast3.bitc(O.eq_dt(xdt, S.uint32()), ar, a0)
  +c = P.dc_cast(O.Found.ar(bc), O.Found.i(bc), dt)
  W2{O.Found.ar(c), O.Found.i(c), 0}

def l2i_cast.got(sel: U32, +ar: O.Arena, +a0: U32, +dt: S.Dt, +ldt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:
  match sel:
    case 0: Some{l2i_cast0(ar, a0, ldt, Bool.or(dd_is_bool(xdt), dd_is_uint(xdt)), xdt)}
    case 1: Some{l2i_cast1(ar, a0, ldt, xdt)}
    case 3: Some{l2i_cast3(ar, a0, dt, xdt)}
    case _: None{}

# `l2i_dt[dt]` is the NARROW dtype, and only arms 0 and 1 use it. Guarding every
# arm with it made arms 2 and 3 DEAD: `sel == 2`/`sel == 3` mean `dt` is NOT
# long/ulong, so `l2i_dt[dt]` is `None` and the unwrap refused first. That is what
# `lg7` measured -- the `else` at dtype.py:39 is `a0.bitcast(dtypes.uint).cast(dt)`
# and it needs `dt`, not `l2i_dt[dt]`. M02 and M06 moved nothing for this reason
# and nothing else.
def l2i_cast.wide(sel: U32, m: Maybe<&2, S.Dt>, +ar: O.Arena, +a0: U32, +dt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:
  match m:
    case Some{d}: l2i_cast.got(sel, ar, a0, dt, d, xdt)
    case None{}: None{}

def l2i_cast.ldt(sel: U32, m: Maybe<&2, S.Dt>, +ar: O.Arena, +a0: U32, +dt: S.Dt, +xdt: S.Dt) -> Maybe<&2, W2>:
  match sel:
    case 3: Some{l2i_cast3(ar, a0, dt, xdt)}
    case _: l2i_cast.wide(sel, m, ar, a0, dt, xdt)

def l2i_cast(+ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  l2i_cast.ldt(dd_cast_sel(dd_is_long(dt), dd_is_float(xdt), dd_is_float(dt)),
    l2i_dt(dt), ar, nth(ws, 0n), dt, xdt)

# -- BITCAST (dtype.py:40)

def l2i_bitcast(+ar: O.Arena, +dt: S.Dt, +ws: List<&2, U32>) -> W2:
  +lo = T.tx_bitcast(ar, nth(ws, 0n), dt)
  +li = O.Found.i(lo)
  +hi = T.tx_bitcast(O.Found.ar(lo), nth(ws, 1n), dt)
  W2{O.Found.ar(hi), li, O.Found.i(hi)}

# -- SHL (dtype.py:41-44)

# dtype.py:42-43, `a0u, a1u, n = a0.bitcast(dtypes.uint), a1.bitcast(dtypes.uint),
# (b0 & 31).cast(dtypes.uint)` then `lo, hi = (a0u << n).bitcast(dt),
# ((a1u << n) | ((a0u >> 1) >> (31 - n))).bitcast(dt)`.
#
# `xdt` IS `uops[0].dtype` AND `uops[1].dtype` -- every `l2i` word of one operand
# shares the operand's dtype, and dtype.py reads no other dtype on this path -- so
# one flag answers both BITCAST folds and the CAST fold. MEASURED
# (`.agents/slop/dd-probe-intern.py`, `dd-cone.py lg9`): `dtypes.uint is
# dtypes.uint32` is `True`, and the `lg9` cone's `SHL` shift count is the `AND`
# NODE, so CPython's `cast(dtypes.uint)` folded and both BITCASTs folded.
def l2i_shift.band(+isu: Bool, +ar: O.Arena, +b0: U32) -> O.Found:
  +m = dd_band(ar, b0, 31)
  dd_cast_fold(O.Found.ar(m), O.Found.i(m), S.uint32(), isu)

# `a0u, a1u` as ONE record: both BITCASTs live in the same arena and the caller
# has to keep building from it, so a `Found` for `a1u` alone would strand `a0u`.
def l2i_shift.words(+isu: Bool, +ar: O.Arena, +ws: List<&2, U32>) -> W2:
  +a0u = dd_bcast(isu, ar, nth(ws, 0n), S.uint32())
  +a1u = dd_bcast(isu, O.Found.ar(a0u), nth(ws, 1n), S.uint32())
  W2{O.Found.ar(a1u), O.Found.i(a0u), O.Found.i(a1u)}

# THE ARENA IS THREADED AND EVERY INDEX IS TAKEN FROM THE `Found` THAT OWNS IT.
# This body did neither: it handed the SAME `ar` to all six node builders, and
# `O.Arena` is an immutable `Arena{nodes: List<Node>}` (uop/ops.bend:1099-1100),
# so `O.UOp.new(ar, ...)` returns a Found over `ar ++ [node]` and the NEXT builder
# appends to `ar` again -- at the SAME index. `a1u << n` was therefore overwritten
# by `C(1)` before the final `|` read it, and the `hi` word came out as a `WHERE`
# borrowed from a later part of the arena. `lg9p` printed
# `BITCAST(WHERE)` where CPython has `BITCAST(OR)`.
def l2i_shl.hi(+ar: O.Arena, +a1u: U32, +n: U32, +a0u: U32) -> O.Found:
  +s = dd_shl(ar, a1u, n)
  +c1 = dd_wk(O.Found.ar(s), H.i64_of_i32(1))
  +o = dd_shr(O.Found.ar(c1), a0u, O.Found.i(c1))
  +k = dd_rsub31(O.Found.ar(o), n)
  +t = dd_shr(O.Found.ar(k), O.Found.i(o), O.Found.i(k))
  dd_or(O.Found.ar(t), O.Found.i(s), O.Found.i(t))

def l2i_shl.ge(+ar: O.Arena, +b0: U32) -> O.Found:
  +c = dd_wk(ar, H.i64_of_i32(32))
  dd_ge1(O.Found.ar(c), b0, O.Found.i(c))

# -- SHR (dtype.py:45-49)

def l2i_shl(+ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +isu = O.eq_dt(xdt, S.uint32())
  +w = l2i_shift.words(isu, ar, ws)
  +a0u = W2.lo(w)
  +a1u = W2.hi(w)
  +b0 = nth(ws, 2n)
  +nn = l2i_shift.band(isu, W2.ar(w), b0)
  +sh1 = dd_shl(O.Found.ar(nn), a0u, O.Found.i(nn))
  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(sh1), O.Found.i(sh1), dt)
  +loi = O.Found.i(lo)
  +loar = O.Found.ar(lo)
  +hib = l2i_shl.hi(loar, a1u, O.Found.i(nn), a0u)
  +hi = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(hib), O.Found.i(hib), dt)
  +ge = l2i_shl.ge(O.Found.ar(hi), b0)
  +gei = O.Found.i(ge)
  +r0 = dd_where(O.Found.ar(ge), gei, zero, loi)
  +r1 = dd_where(O.Found.ar(r0), gei, loi, O.Found.i(hi))
  W2{O.Found.ar(r1), O.Found.i(r0), O.Found.i(r1)}

# `(a1u << n) | ((a0u >> 1) >> (31 - n))`

def l2i_shr.fill(+ar: O.Arena, +a1: U32, +zero: U32, signed: Bool) -> O.Found:
  match signed:
    case True{}:
      +c = dd_wk(ar, H.i64_of_i32(31))
      dd_shr(O.Found.ar(c), a1, O.Found.i(c))
    case False{}: O.Found{ar, zero}

# -- ADD (dtype.py:50)

# dtype.py:47: `lo, hi = ((a0u >> n) | ((a1u << 1) << (31 - n))).bitcast(dt),
# a1 >> (b0 & 31)`.
#
# THE `.bitcast(dt)` BELONGS TO `lo` AND NOT TO `hi`, AND THAT IS THE WHOLE OF
# `lga`'s second disagreement: `hi` is a bare `SHR` at `u32` and this body wrapped
# it. MEASURED (`dd-cone.py lga`): the `hi` node is `#7 SHR dt=u32` with no
# BITCAST parent, and `lgasig` carries a `BITCAST/1` at position 7 that CPython's
# cone does not have. `a1` not `a1u` is the dtype.py spelling and it matters here
# for the same reason it matters in `fill`: the high word of an `int` keeps its
# signedness.
def l2i_shr(+ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +isu = O.eq_dt(xdt, S.uint32())
  +w = l2i_shift.words(isu, ar, ws)
  +a0u = W2.lo(w)
  +a1u = W2.hi(w)
  +a1 = nth(ws, 1n)
  +b0 = nth(ws, 2n)
  +m31 = dd_band(W2.ar(w), b0, 31)
  +nn = dd_cast_fold(O.Found.ar(m31), O.Found.i(m31), S.uint32(), isu)
  +c1 = dd_wk(O.Found.ar(nn), H.i64_of_i32(1))
  +l1 = dd_shl(O.Found.ar(c1), a1u, O.Found.i(c1))
  +k = dd_rsub31(O.Found.ar(l1), O.Found.i(nn))
  +l2 = dd_shl(O.Found.ar(k), O.Found.i(l1), O.Found.i(k))
  +r0 = dd_shr(O.Found.ar(l2), a0u, O.Found.i(nn))
  +o = dd_or(O.Found.ar(r0), O.Found.i(r0), O.Found.i(l2))
  +lo = dd_bcast(O.eq_dt(dt, S.uint32()), O.Found.ar(o), O.Found.i(o), dt)
  +hi = dd_shr(O.Found.ar(lo), a1, O.Found.i(m31))
  +hii = O.Found.i(hi)
  +ge = l2i_shl.ge(O.Found.ar(hi), b0)
  +r0b = dd_where(O.Found.ar(ge), O.Found.i(ge), O.Found.i(hi), O.Found.i(lo))
  +fill = l2i_shr.fill(O.Found.ar(r0b), a1, zero, dd_is_i32(dt))
  +r1 = dd_where(O.Found.ar(fill), O.Found.i(ge), O.Found.i(fill), O.Found.i(hi))
  W2{O.Found.ar(r1), O.Found.i(r0b), O.Found.i(r1)}

# `fill = a1 >> 31 if dt == dtypes.int else zero` -- the vacated high word, sign
# bits when signed and 0 when not. `a1` and NOT `a1u` is the dtype.py spelling.

# `low.bitcast(dtypes.uint) < a0.bitcast(dtypes.uint)` at dtype.py:50 and
# `a0.bitcast(dtypes.uint) < b0.bitcast(dtypes.uint)` at dtype.py:51. `bitcast`
# FOLDS when the dtype already agrees, and on the `pm_long_decomp` entry path the
# words ARE `uint` -- so `lgc` and `lgd` have no BITCAST anywhere in their sigs.
#
# They are NOT always `uint`, and ONE dtype is not enough: `l2i` hands the port
# only `uops[0].dtype`, while dtype.py reads the dtype off EACH node. `l2i(NEG,
# dt, *uops)` is `l2i(SUB, dt, zero, zero, *uops)`, so there `a0` is `zero` at
# `dt` and `b0` is `uops[0]` at `xdt` -- TWO dtypes for ONE arm. Assuming the fold
# unconditionally is what `lg1sig` caught; assuming it for both is what `lg1n`
# caught. So `ad` and `bd` are the two low-word dtypes, and every call site says
# which it means.
def dd_bc(isu: Bool, +ar: O.Arena, +x: U32) -> O.Found:
  match isu:
    case True{}: O.Found{ar, x}
    case False{}: T.tx_bitcast(ar, x, S.uint32())

def l2i_add(+ar: O.Arena, +ad: S.Dt, +bd: S.Dt, +ws: List<&2, U32>) -> W2:
  +a0 = nth(ws, 0n)
  +b0 = nth(ws, 2n)
  +lo = dd_add(ar, a0, b0)
  +s1 = dd_add(O.Found.ar(lo), nth(ws, 1n), nth(ws, 3n))
  +ua = O.eq_dt(ad, S.uint32())
  +bl = dd_bc(ua, O.Found.ar(s1), O.Found.i(lo))
  +ba = dd_bc(ua, O.Found.ar(bl), a0)
  +lt = dd_lt1(O.Found.ar(ba), O.Found.i(bl), O.Found.i(ba))
  +hi = dd_add(O.Found.ar(lt), O.Found.i(s1), O.Found.i(lt))
  W2{O.Found.ar(hi), O.Found.i(lo), O.Found.i(hi)}

# -- SUB (dtype.py:51)

def l2i_sub(+ar: O.Arena, +ad: S.Dt, +bd: S.Dt, +ws: List<&2, U32>) -> W2:
  +a0 = nth(ws, 0n)
  +b0 = nth(ws, 2n)
  +lo = P.dc_sub(ar, a0, b0)
  +s1 = P.dc_sub(O.Found.ar(lo), nth(ws, 1n), nth(ws, 3n))
  +ua = O.eq_dt(ad, S.uint32())
  +ub = O.eq_dt(bd, S.uint32())
  +ba = dd_bc(ua, O.Found.ar(s1), a0)
  +bb = dd_bc(ub, O.Found.ar(ba), b0)
  +lt = dd_lt1(O.Found.ar(bb), O.Found.i(ba), O.Found.i(bb))
  +hi = P.dc_sub(O.Found.ar(lt), O.Found.i(s1), O.Found.i(lt))
  W2{O.Found.ar(hi), O.Found.i(lo), O.Found.i(hi)}

# -- MUL (dtype.py:52-55)

# ONE product `x*y` yields BOTH halves of dtype.py:54, and `shr` READS THE RAW
# PRODUCT. `shr(a00*b01, 16)` is the raw `a00*b01` floored, not the bitcast `shl`
# of it -- `shl`/`shr` are transcendental.py:19-20 (`x * 2**y`, `x // 2**y`) and
# dtype.py:54 spells both off the same parenthesised product. MEASURED
# (`dd-cone.py lge`): `#24 FLOORDIV` has `#4 MUL` as its src0 and `#4` is the
# `a00*b01` product itself, while `#2 BITCAST` sits over `#3 MUL` which is that same
# `#4` times `C(65536)`. Chaining `shr` off the bitcast -- as this did -- builds a
# second, different `FLOORDIV` and puts an extra node in every sig.
def l2i_mul.w(+ar: O.Arena, +dt: S.Dt, +x: U32, +y: U32) -> W2:
  +m = dd_mul(ar, x, y)
  +mar = O.Found.ar(m)
  +mi = O.Found.i(m)
  +hi = T.tx_shl(mar, mi, 16)
  +hi2 = T.tx_bitcast(O.Found.ar(hi), O.Found.i(hi), dt)
  +lo = T.tx_shr(O.Found.ar(hi2), mi, 16)
  +lo2 = T.tx_bitcast(O.Found.ar(lo), O.Found.i(lo), dt)
  W2{O.Found.ar(lo2), O.Found.i(hi2), O.Found.i(lo2)}

# the outer half of dtype.py:55 -- `(a00*b00).bitcast(dt)` and
# `(a01*b01).bitcast(dt) + a0*b1 + a1*b0`, in that order. BOTH ARE RETURNED: the
# outer `l2i(ADD, dt, *mid, <w3>, <w4>)` needs the pair, and a def that hands back
# only `w4` loses `w3` -- which is what put the arena's BOTTOM (`O.NOOP`, index 0)
# where `w4` belongs and made `lgep` print `ADD(ADD,NOOP)` for `(a01*b01)+...`.
#
# THE SECOND PRODUCT IS `a1*b0` AND NOT `a1*b1`. dtype.py:55 writes
# `(a01*b01).bitcast(dt) + a0*b1 + a1*b0`, and the asymmetry is load-bearing: `b0`
# is the operand's LOW word, the same one `unpack32` split. MEASURED
# (`dd-cone.py lge`): the two products in `#37 MUL{u321, u322}` and
# `#40 MUL{u321, u322}`... precisely `#37 = MUL(u321, u323)` = `a1*b1` and
# `#40 = MUL(u321, u322)` = `a1*b0`, BOTH under `CAST_i64` promotion nodes the
# oracle deletes (dd-oracle.py decision 1), so `lgesig`'s `MUL/2,PARAM/0,PARAM/0`
# pair is the whole of the evidence.
def l2i_mul.p(+ar: O.Arena, +dt: S.Dt, +a0: U32, +a1: U32, +b0: U32, +b1: U32, +a00: U32, +b00: U32, +a01: U32, +b01: U32) -> W2:
  +p0 = dd_mul(ar, a00, b00)
  +p = T.tx_bitcast(O.Found.ar(p0), O.Found.i(p0), dt)
  +q0 = dd_mul(O.Found.ar(p), a01, b01)
  +q = T.tx_bitcast(O.Found.ar(q0), O.Found.i(q0), dt)
  +x1 = dd_mul(O.Found.ar(q), a0, b1)
  +s0 = dd_add(O.Found.ar(x1), O.Found.i(q), O.Found.i(x1))
  +y1 = dd_mul(O.Found.ar(s0), a1, b0)
  +w4 = dd_add(O.Found.ar(y1), O.Found.i(s0), O.Found.i(y1))
  W2{O.Found.ar(w4), O.Found.i(p), O.Found.i(w4)}

# dtype.py:54 hands `l2i` FOUR words, in this order:
#     l2i(ADD, dt, shl(a00*b01, 16).bitcast(dt), shr(a00*b01, 16).bitcast(dt),
#              shl(a01*b00, 16).bitcast(dt), shr(a01*b00, 16).bitcast(dt))
#
# ONE product therefore yields TWO words and this def used to yield one -- the
# `shr` half -- while building the `shl` half as an unreachable intermediate. Four
# calls with permuted arguments could not repair that: they all built the same
# `shr` node and none of them built `shl`. MEASURED (`dd-cone.py lge`): the cone's
# `#2 BITCAST` sits over `#3 MUL` (the `shl`, since `shl` is `x * 2**16`) and only
# `#11`/`#16` sit over `MUL`s; the port's `lgesig` position 3 was
# `FLOORDIV/2,BITCAST/1` where CPython has `MUL/2,MUL/2` -- it never had a `shl` at
# all. `W2` carries both halves in one arena, so the `shl` and the `shr` of one
# product cannot be separated by index again.
def l2i_mul(+ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> W2:
  +ua = unpack32(ar, nth(ws, 0n), xdt)
  +ub = unpack32(W2.ar(ua), nth(ws, 2n), xdt)
  +p1 = l2i_mul.w(W2.ar(ub), dt, W2.lo(ua), W2.hi(ub))
  +p2 = l2i_mul.w(W2.ar(p1), dt, W2.hi(ua), W2.lo(ub))
  +am = W2.ar(p2)
  +mid = l2i_add(am, dt, dt, ws4(W2.lo(p1), W2.hi(p1), W2.lo(p2), W2.hi(p2)))
  +pw = l2i_mul.p(W2.ar(mid), dt, nth(ws, 0n), nth(ws, 1n), nth(ws, 2n), nth(ws, 3n),
    W2.lo(ua), W2.lo(ub), W2.hi(ua), W2.hi(ub))
  +ml = W2.lo(mid)
  +mh = W2.hi(mid)
  l2i_add(W2.ar(pw), dt, dt, ws4(ml, mh, W2.lo(pw), W2.hi(pw)))

# -- comparisons (dtype.py:75-77)

# dtype.py:75, `(a1 < b1) | ((a1.eq(b1)) & (a0.bitcast(dtypes.uint) <
# b0.bitcast(dtypes.uint)))`. BOTH BITCASTS FOLD on a `u32` word pair, and the cone
# says so: MEASURED (`dd-cone.py lgf`), the inner `CMPLT`'s srcs are `PARAM u320`
# and `PARAM u322` with no BITCAST above either, and `lgfsig` ends
# `CMPLT/2,PARAM/0,PARAM/0` where the port printed
# `CMPLT/2,BITCAST/1,PARAM/0,BITCAST/1,PARAM/0`. `l2i_max` (dtype.py:80) is
# `l2i(WHERE, l2i(CMPLT), ...)`, so `lgm` inherits it -- `lgmsig` is the same row.
def l2i_cmplt(+ar: O.Arena, +xdt: S.Dt, +ws: List<&2, U32>) -> W2:
  +isu = O.eq_dt(xdt, S.uint32())
  +lt = dd_lt1(ar, nth(ws, 1n), nth(ws, 3n))
  +eq = dd_eq1(O.Found.ar(lt), nth(ws, 1n), nth(ws, 3n))
  +ba = dd_bc(isu, O.Found.ar(eq), nth(ws, 0n))
  +bb = dd_bc(isu, O.Found.ar(ba), nth(ws, 2n))
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

def l2i_max(+ar: O.Arena, +xdt: S.Dt, +ws: List<&2, U32>) -> W2:
  +c = l2i_cmplt(ar, xdt, ws)
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
  l2i_sub(ar, S.uint32(), S.uint32(), ws4(z, z, a0, a1))

# `if dt == dtypes.int`: take both operands' absolute values through `l2i(NEG)`
# and remember each one's sign, because a restoring division on negatives needs
# them at the end. `a_neg` and `b_neg` survive the whole loop. THE ORDER IS
# dtype.py's: four BITCASTs, then `a1 < zero` BEFORE `l2i(NEG)` (it is the
# receiver of the `.where`), and `zero` is the `dt`-typed CONST from the top of
# `l2i` while `z` is the `uint` one.

def l2i_cdiv.abs.c(+ar: O.Arena, +bni: U32, +zi: U32, +ub0: U32, +ub1: U32, +ani: U32, +zr: U32, +ai: U32, +a1i: U32) -> Cd:
  # dtype.py:61's `n` IS THE B-SIDE NEGATION -- `(n:=l2i(Ops.NEG, dtypes.uint, ub0,
  # ub1))[0]` and `n[1]` -- and this was handed the A-SIDE pair instead, so `nb`'s own
  # LOW word was built and never read: a dead binding, which is what a wrong operand
  # looks like from the outside. MEASURED, `.agents/slop/dd-gap.py --sig lgq`: the
  # cone was short exactly one `ADD/2` and one `MUL/2`, and `.agents/slop/dd-cone-py.py
  # lgq 285 320` put them at CPython's positions 295/296 under the b-side `WHERE` --
  # `ADD <- CAST, MUL` and `MUL <- Pu322, C(-1)`, i.e. `zero - ub0`.
  +nb = l2i_cdiv.neg(ar, zi, ub0, ub1)
  +b = dd_where(W2.ar(nb), bni, W2.lo(nb), ub0)
  +b1a = dd_where(O.Found.ar(b), bni, W2.hi(nb), ub1)
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
  l2i_cdiv.abs.c(O.Found.ar(bn), O.Found.i(bn), zi, ub0, ub1, ani, zr, O.Found.i(a), O.Found.i(a1a))

# THE ARENA IS HANDED ON, NOT RE-USED, and every index below belongs to the arena
# named beside it. This body handed `abs.b` the arena `l2i` started with, while
# `ani`/`ua0`/`ua1`/`ub0`/`ub1` are indices into the arena six builders LATER.
# `O.Arena` is immutable (`uop/ops.bend:1099-1100`), so `abs.b`'s first
# `dd_where` re-used the very slot `a_neg` occupies and `a_neg` then read back as
# whatever node that WHERE became. It is invisible while the node COUNT happens to
# line up: `lgq`/`lgqp` agreed at one bitcast configuration and printed
# `XOR(ADD,CMPLT)` for `(a_neg^b_neg)` at the next, with no error anywhere -- the
# same species as the `l2i_shl.hi` aliasing, and the same silent fall-through.
def l2i_cdiv.abs(+ar: O.Arena, +xdt: S.Dt, +zero: U32, +a0: U32, +a1: U32, +b0: U32, +b1: U32) -> Cd:
  # dtype.py:59's FOUR BITCASTS FOLD on a `u32` source -- `mixin/dtype.py:53` returns
  # `self` when the dtypes already agree -- and `dd_bcast` IS that rule, already used
  # by `l2i_shl` and `l2i_shr` for dtype.py:42/46. `T.tx_bitcast` always minted the
  # node, so every signed CDIV/CMOD cone carried four BITCASTs CPython's does not.
  # `xdt` is the ONLY place the source dtype is known, which is why it is a parameter
  # of `abs`, `sign` and `cdiv` now. MEASURED, `.agents/slop/dd-gap.py --sig lgq`:
  # ONLY-PORT held `BITCAST/1` four times over against a cone CPython's lacks.
  +isu = O.eq_dt(xdt, S.uint32())
  +ua0 = dd_bcast(isu, ar, a0, S.uint32())
  +ua1 = dd_bcast(isu, O.Found.ar(ua0), a1, S.uint32())
  +ub0 = dd_bcast(isu, O.Found.ar(ua1), b0, S.uint32())
  +ub1 = dd_bcast(isu, O.Found.ar(ub0), b1, S.uint32())
  +an = dd_lt1(O.Found.ar(ub1), a1, zero)
  +z = dd_const.int(O.Found.ar(an), H.i64_of_i32(0), S.uint32())
  +zi = O.Found.i(z)
  +na = l2i_cdiv.neg(O.Found.ar(z), zi, O.Found.i(ua0), O.Found.i(ua1))
  l2i_cdiv.abs.b(W2.ar(na), O.Found.i(an), zi, O.Found.i(ua0), O.Found.i(ua1), W2.lo(na), W2.hi(na), zero, b1, zi, O.Found.i(ub0), O.Found.i(ub1), na)

# ONE `.where` PAIR PER STEP, with every record and index passed as a `U32`, so
# nothing is read twice: `W2.ar`/`W2.lo`/`W2.hi` are three CALLS on one record and
# a `Found`'s `.ar`/`.i` are two, so every intermediate is destructured once.
#
# THE SHIFT AMOUNT IS `i % 32`, NOT `i`. dtype.py:68 writes
# `shl(cond.cast(dtypes.uint), i % 32)` and `shl` is transcendental.py:20,
# `x * 2**y` -- so for `i = 63` the constant is `2**31` = `C(2147483648)` and NOT
# `2**63`, which `tx_powi(63)` builds as the 64-bit `C(2147483648:0)`. `U32.mod` is
# a machine word, so the reduction is exact and needs no special case.
#
# ⚠ THE MEASUREMENT THAT USED TO STAND HERE WAS WRONG AND IS CORRECTED IN PLACE, because a
# stale measurement in a comment is a measurement that gets cited. It claimed: "CPython's
# cone constants after the fixed six are `C(63), C(62), ..., C(2)` ... while the port
# printed `C(64)` and `C(2147483648)` there and NEVER PRODUCED A `2**31` AT ALL."
# Re-measured on the live tree, the port DOES print `2**31`. The port's `lgqk` is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(64),C(2147483648),C(1073741824),...
#
# and CPython's is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(63),C(62),C(61),C(60),...,C(33),
#     C(2147483648),C(30),C(1073741824),C(29),...
#
# So the real difference is not a missing power of two. It is that the port emits ONE
# leading word `C(64)` and then a RUN of powers of two, while CPython interleaves
# `C(i)` with `2**(i-32)` for i = 63..33 -- the port never emits the 31 `UOp.const(i,
# dtypes.uint)` shift words of dtype.py:65 at all. Whether that is the CDIV loop or the
# `q` accumulator is not yet established; `lgtk` is still 3 constants against CPython's
# 66 and `lgtsig` 57 cone nodes against 2184, so the family is OPEN. `.agents/slop/
# dd-truth.py` is what prints both sequences side by side.
def l2i_cdiv.q.lo(+ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  +ci = P.dc_cast(ar, cond, S.uint32())
  +b = T.tx_shl(O.Found.ar(ci), O.Found.i(ci), U32.mod(i, 32))
  +o = dd_or(O.Found.ar(b), Cd.q0(c), O.Found.i(b))
  Cd{O.Found.ar(o), Cd.z(c), Cd.a0(c), Cd.a1(c), Cd.b0(c), Cd.b1(c), Cd.r0(c), Cd.r1(c),
    O.Found.i(o), Cd.q1(c), Cd.an(c), Cd.bn(c)}

def l2i_cdiv.q.hi(+ar: O.Arena, +cond: U32, +c: Cd, +i: U32) -> Cd:
  +ci = P.dc_cast(ar, cond, S.uint32())
  +b = T.tx_shl(O.Found.ar(ci), O.Found.i(ci), U32.mod(i, 32))
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
  +one = dd_const.int(ar, H.i64_of_i32(1), S.uint32())
  +onei = O.Found.i(one)
  +onear = O.Found.ar(one)
  +sh = l2i_shl(onear, S.uint32(), S.uint32(), z, ws4(Cd.r0(c), Cd.r1(c), onei, z))
  +shl = W2.lo(sh)
  +shh = W2.hi(sh)
  +shar = W2.ar(sh)
  +ci = dd_const.int(shar, H.i64_of_i32(i), S.uint32())
  +cii = O.Found.i(ci)
  +sr = l2i_shr(O.Found.ar(ci), S.uint32(), S.uint32(), z, ws4(Cd.a0(c), Cd.a1(c), cii, z))
  +srl = W2.lo(sr)
  +an = dd_band(W2.ar(sr), srl, 1)
  +r0 = dd_or(O.Found.ar(an), shl, O.Found.i(an))
  +r0i = O.Found.i(r0)
  +r = l2i_cmplt(O.Found.ar(r0), S.uint32(), ws4(r0i, shh, Cd.b0(c), Cd.b1(c)))
  +rlo = W2.lo(r)
  +rar = W2.ar(r)
  # dtype.py:66, `cond = l2i(Ops.CMPLT, dtypes.uint, *r, b0, b1).logical_not()`.
  # `.logical_not()` IS ON THE ANSWER OF `l2i`, WHICH IS THE `OR` OF dtype.py:75 --
  # NOT on the `a1 < b1` inside it. `dd_ge1(rar, rlo, rhi)` re-ran the comparison
  # and negated THAT, so the port's `cond` was `CMPNE(CMPLT, C(True))` over a node
  # CPython never built. MEASURED: `lgt`'s root src0 label is `OR` in CPython and
  # `CMPLT` in the port, and that ONE label is the whole of `lgt`'s disagreement.
  +cond = T.tx_lnot(rar, rlo)
  +condi = O.Found.i(cond)
  # ⚠ dtype.py:67's `*r` IS THE SAME TUPLE dtype.py:66 SPELLED, and this handed it
  # `W2.lo(r)`/`W2.hi(r)` -- the CMPLT ARM'S OWN ANSWER -- instead of `r` itself.
  # dtype.py:75's `(a1 < b1) | ((a1.eq(b1)) & (a0 < b0))` and dtype.py:51's
  # `a0.bitcast(uint) < b0.bitcast(uint)` are then the SAME `CMPLT` node, so
  # CPython interns one and reuses it; the port's `diff` compared the comparison
  # against the divisor and minted a second `CMPLT` no CPython cone has.
  # MEASURED, `.agents/slop/dd-gap.py --sig lgq`: the port carried `CMPLT/2` 63
  # times too many against CPython's cone, and 63 `ADD/2` plus 1 `MUL/2` were
  # missing. `rlo` STAYS: it IS `cond`'s receiver at dtype.py:66.
  +diff = l2i_sub(O.Found.ar(cond), S.uint32(), S.uint32(), ws4(r0i, shh, Cd.b0(c), Cd.b1(c)))
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

# `return r if op is Ops.CMOD else q` -- dtype.py:74. SO `isdiv` ANSWERS `q` AND
# NOT `r`. The arms were the other way round, and it is invisible on the SIGNED
# fixtures, where dtype.py:73 has already replaced the return with the two WHEREs
# and `l2i_cdiv.uns` is never reached. It shows on the unsigned pair, and it shows
# as a SWAP: MEASURED, `lgs` (CDIV uint) is `OR(OR(OR,MUL),MUL(CAST,C(1)))` --
# the quotient, `q[1] | shl(cond, i%32)` -- while the port answered the `r` shape
# `WHERE(CMPNE(CMPLT,C(1)),ADD(OR,MUL),OR(WHERE,AND))`, which is what CPython
# answers for `lgt`. `lgs` and `lgt` were each other's answer.
#
# THE HIGH WORD IS AN ARENA INDEX, NOT A VALUE. `W2` is `{ar: Arena, lo: U32, hi: U32}`
# and both `lo` and `hi` are INDICES -- `W2.hi` is read by `l2i_shr`, `l2i_shl` and the
# final WHERE as `Arena.op(ar, hi)`. Writing the literal `0` here did not mean "high word
# is zero", it meant "high word is ARENA SLOT 0", and slot 0 is the arena's bottom node,
# whose label is `NOOP`. dtype.py:74 returns the PAIR, not one word: `q` and `r` are both
# `(z, z)`-shaped 2-tuples from dtype.py:62, so the unsigned answer is `(q[0], q[1])` and
# `(r[0], r[1])`.
#
# MEASURED, and it is invisible for the reason the `nr` note below describes -- the node
# COUNT barely moves while the CONE collapses:
#
#     row         CPython sig   CPython k   port sig   port k   port rows gained
#     lgtsig            2184          66         57        3      lgsp, lgtp
#     lgssig            2396          92       1642       36      lgsp, lgtp
#
# So the port's CMOD cone is 38x smaller than CPython's and still is after this fix. THE
# FIX IS CORRECT AND INCOMPLETE: it stopped an arena slot from being read as a node and it
# recovered the two rows CPython emits that the port was not emitting at all, but the loop
# still does not reach back through its own iterations. `lgsn` is 1976 against CPython's
# 1977, so the nodes ARE built -- they are not REACHABLE from the answer, which is a
# different defect and a smaller one.
#
# `lgt`'s BARE answer row still agreed before the fix, because `tree()` only reaches two
# levels and slot 0's label is a valid-looking word there. The disagreement was in `lgtk`
# and `lgtsig` -- both of which dtype-oracle.py SUPPRESSES, so the wired gate reported
# neither. Fourth instance of the NOOP species in this file.
def l2i_cdiv.uns(isdiv: Bool, +ar: O.Arena, +c: Cd) -> W2:
  match isdiv:
    case True{}: W2{ar, Cd.q0(c), Cd.q1(c)}
    case False{}: W2{ar, Cd.r0(c), Cd.r1(c)}

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
  # `W2.ar(negr)` AND NOT `nar`. `nar` is the arena as it stood BEFORE the two
  # negations of `r`, so `l2i_bitcast` re-used the slots `negr`'s own nodes occupy
  # and `nr`'s srcs read back as `O.NOOP` -- the arena's bottom, index 0, whose
  # `lab` is `NOOP`. MEASURED: `lgrp`'s root src2 label was `NOOP` and `lgrsig`
  # position 8 was `NOOP/0` where CPython has `CAST/1`. Third instance of the same
  # defect in this file, and the third to be invisible in `--check-only`.
  +nr = l2i_bitcast(W2.ar(negr), dt, ws2(W2.lo(negr), W2.hi(negr)))
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

def l2i_cdiv.sign(sgn: Bool, +ar: O.Arena, +xdt: S.Dt, +zero: U32, +a0: U32, +a1: U32, +b0: U32, +b1: U32) -> Cd:
  match sgn:
    case True{}: l2i_cdiv.abs(ar, xdt, zero, a0, a1, b0, b1)
    case False{}:
      +z = dd_const.int(ar, H.i64_of_i32(0), S.uint32())
      +zi = O.Found.i(z)
      +zar = O.Found.ar(z)
      Cd{zar, zi, a0, a1, b0, b1, zi, zi, zi, zi, zi, zi}

# ===========================================================================
# `l2i`'s `match op` -- the dispatch, and the one def that creates `zero`.
# ===========================================================================

def l2i_cdiv(isdiv: Bool, +ar: O.Arena, +dt: S.Dt, +xdt: S.Dt, +zero: U32, +ws: List<&2, U32>) -> W2:
  +sgn = dd_is_i32(dt)
  +c = l2i_cdiv.sign(sgn, ar, xdt, zero, nth(ws, 0n), nth(ws, 1n), nth(ws, 2n), nth(ws, 3n))
  +e = l2i_cdiv.loop(64n, c, 63)
  l2i_cdiv.finish(sgn, isdiv, Cd.ar(e), dt, e)

def l2i.go(+ar: O.Arena, +zero: U32, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  match op:
    case O.OpsNEG{}: Some{l2i_sub(ar, dt, xdt, ws4(zero, zero, nth(ws, 0n), nth(ws, 1n)))}
    case O.OpsCAST{}: l2i_cast(ar, dt, xdt, ws)
    case O.OpsBITCAST{}: Some{l2i_bitcast(ar, dt, ws)}
    case O.OpsSHL{}: Some{l2i_shl(ar, dt, xdt, zero, ws)}
    case O.OpsSHR{}: Some{l2i_shr(ar, dt, xdt, zero, ws)}
    case O.OpsADD{}: Some{l2i_add(ar, xdt, xdt, ws)}
    case O.OpsSUB{}: Some{l2i_sub(ar, xdt, xdt, ws)}
    case O.OpsMUL{}: Some{l2i_mul(ar, dt, xdt, ws)}
    case O.OpsCMPLT{}: Some{l2i_cmplt(ar, xdt, ws)}
    case O.OpsCMPEQ{}: Some{l2i_cmpeq(ar, ws)}
    case O.OpsCMPNE{}: Some{l2i_cmpne(ar, ws)}
    case O.OpsXOR{}: Some{l2i_binop(ar, O.OpsXOR{}, ws)}
    case O.OpsOR{}: Some{l2i_binop(ar, O.OpsOR{}, ws)}
    case O.OpsAND{}: Some{l2i_binop(ar, O.OpsAND{}, ws)}
    case O.OpsWHERE{}: Some{l2i_where(ar, ws)}
    case O.OpsMAX{}: Some{l2i_max(ar, xdt, ws)}
    case O.OpsCDIV{}: Some{l2i_cdiv(True{}, ar, dt, xdt, zero, ws)}
    case O.OpsCMOD{}: Some{l2i_cdiv(False{}, ar, dt, xdt, zero, ws)}
    case _: None{}

def l2i(+ar: O.Arena, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, +ws: List<&2, U32>) -> Maybe<&2, W2>:
  # `zero = UOp.const(0, dt)` at dtype.py:22, BEFORE the arity unpacking at
  # 23-25. A one-word CAST does not fail: arms 0 and 1 read `uops[0]`, not `a0`.
  # An arm that reads `a0` (`:39`, the float-target arm) raises `UnboundLocalError`
  # on one word. That is not `NotImplementedError`.
  +zero = dd_const.int(ar, H.i64_of_i32(0), dt)
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

# `shl(1, k) - 1`, the mask dtype.py writes four times. `P.dc_sub` is
# `a - 1` = `ADD(a, MUL(C(1), C(-1)))`, and THAT IS THE BUG: `shl(1, k)` is
# `1 * (2**k)` and BOTH of its arguments are Python ints (transcendental.py:20), so
# tinygrad folds the subtraction in PYTHON and the mask is ONE interned `CONST` node
# before any graph exists. Building it as `ADD(C(2**k), MUL(C(1), C(-1)))` costs FOUR
# nodes where CPython has one, and the three the `+s`/`+m1`/`+m` binders mint are DEAD
# -- nothing reads them -- so they are invisible in a cone walk from the root.
# MEASURED, `f2f-arena-diff.py` against `.agents/slop/f2f-arena-oracle.py`:
#     cpy[6]  CONST C(127)                       one node
#     port[7] CONST C(1)  <- the mask's graph    four nodes, all dead
#     port[8] CONST C(-1)
#     port[9] MUL    <- 6,7
#     port[10] ADD    <- 1,8
# and the port's `q1` carried `+6` nodes over CPython's, of which these four and
# `f2f.norm`'s two are the whole.
def dd_mask1(+k: U32) -> U32:
  U32.sub(T.tx_powi32(k), 1)

# THE SAME NUMBER AS A NODE, for the three places dtype.py COMPARES against the mask
# (`x.eq(shl(1, k) - 1)` twice) or ORs it in (`nan_mantissa = shl(1, tm) - 1`) rather
# than ANDing it. One interned `CONST`; `H.i64_of_i32` of `mask1` is exact because
# `2**k - 1` is below `2**31` for every `k` dtype.py writes here.
def dd_mask1.node(+ar: O.Arena, +k: U32) -> O.Found:
  dd_wk(ar, H.i64_of_i32(dd_mask1(k)))

def rne.go(+ar: O.Arena, +v: U32, +s: U32) -> O.Found:
  +a = T.tx_shr(ar, v, s)
  +sm = U32.sub(s, 1)
  +b = T.tx_shr(O.Found.ar(a), v, sm)
  +c = dd_band(O.Found.ar(b), O.Found.i(b), 1)
  # ⚠ `+d` ANDed WITH `1`. dtype.py:98 is `(v & ((1 << (s - 1)) - 1)).ne(0)`, so the mask
  # is `(1 << (s-1)) - 1` and the `+m` line was interning it as a CONST NOTHING READ --
  # four dead slots, and the one function CPython does not build.
  # MEASURED, `q2`: cpy[50] is `CONST C(524287)` (`2**19 - 1`, `s = fm - tm = 20`) feeding
  # cpy[51] `AND <- 44,50` and cpy[52] `CMPNE <- 51,20`. The port had no `C(524287)` at
  # all and its `q2k` was 17 CONSTs against CPython's 18.
  +d = dd_band(O.Found.ar(c), v, dd_mask1(sm))
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
  # dtype.py:129-130 is TWO PREDICATES AND NOT ONE. `max_exp` is `(1 << e) - 1`
  # for the fnuz-and-e4m3 layouts and `(1 << e) - 2` for the other three;
  # `max_man` is `(1 << m) - 2` for `fp8e4m3` ALONE and `(1 << m) - 1`
  # everywhere else -- fnuz INCLUDED. One `ocp` for both gets `fp8e4m3fnuz` and
  # `fp8e5m2fnuz` wrong, and the two errors partly cancel so the row that
  # would have caught it was never printed. `dd_is_e4m3` is NOT fnuz AND a
  # 4-bit exponent.
  +e4m = dd_is_e4m3(dt)
  +ocp = Bool.or(T.tx_is_fnuz(dt), e4m)
  +me = U32.sub(T.tx_powi32(e), Bool.pick(U32, ocp, 1, 2))
  +mm = U32.sub(T.tx_powi32(m), Bool.pick(U32, e4m, 2, 1))
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
      # ⚠ `O.Found.ar(ne)` WAS ONE NODE STALE HERE: `dd_wkf` interns the `F(-1.0)`
      # CONST and grows, so the `MUL` landed ON the CONST's slot and its src1 pointed at
      # itself. MEASURED, `q3` before: `6 MUL/2 MUL <- 4,6 FORWARD` -- src1 == its own
      # slot. `qmask`'s siblings are the same shape; see `.agents/slop/dd-stalearena.py`
      # rule R2.
      +nm = dd_mul(O.Found.ar(n1), O.Found.i(mxc), O.Found.i(n1))
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

def f2f.qmask(+ar: O.Arena, +k: U32, +j: U32) -> O.Found:
  dd_wk(ar, H.i64_shl(H.i64_of_i32(dd_mask1(k)), U32.to_nat(j)))

# `qnan = shl(shl(1, te) - 1, tm) | shl(1, tm - 1)`, dtype.py:108. BOTH operands of that
# `|` are Python ints -- `shl` is `x * (2**y)` with two int arguments (transcendental.py:20)
# -- so the disjunction is evaluated in PYTHON and the whole thing is ONE interned CONST.
# MEASURED, `q4` (fp8e4m3fnuz -> float32): cpy[145] is `CONST/0 C(2143289344)` =
# `2139095040 | 4194304` = `0x7FC00000`, feeding cpy[146] `WHERE <- 140,145,144`. The port
# carried `C(2139095040)` AND `C(4194304)` separately with an `OR` over them, so its `q4k`
# had a constant CPython does not have and its `q4sig` was 28 long against CPython's 22.
# `j - 1` is `tm - 1` and every `to` reachable from `f2f.fnuz` is float32 or float64, so
# `j >= 23`; a `tm` of 0 would underflow `U32.sub` and is not reachable from this arm.
def f2f.qnan.c(+ar: O.Arena, +k: U32, +j: U32) -> O.Found:
  +m = H.i64_shl(H.i64_of_i32(dd_mask1(k)), U32.to_nat(j))
  +o = H.i64_shl(H.i64_of_i32(1), U32.to_nat(U32.sub(j, 1)))
  dd_wk(ar, H.i64_or(m, o))

# `shl((v & shl(1, fs-1)).cast(f2f_dt[to]), ts - fs)`

# `shl(shl(1, k) - 1, j)`, the `nan` pattern of dtype.py:106 and :120. `shl` is
# `x * (2**y)` (transcendental.py:20) with BOTH arguments Python ints, so the whole
# expression is one Python int by the time a node exists: `(2**k - 1) * 2**j`. ONE
# `CONST`. MEASURED, `shl(255, 23)` is `C(2139095040)`, and CPython's `q1` slot 15 is
# `CONST/0 C(2139095040)` with an `OR` for src1 -- not a `MUL` by a `CONST 2**j`.
# This def REPLACED `f2f.em1`, which built `2**k - 1` as a three-node graph and then
# handed the SAME arena to `tx_shl`, so `tx_shl`'s `MUL` overwrote the `em1` CONST and
# its own src0 pointed FORWARD. See `f2f.qnan`.
# ⚠ THE MASK WAS ROUTED THROUGH `dd_band`'s `U32` THIRD PARAMETER, AND `dc_cint` is
# `O.CInt{H.i64_of_i32(v)}` -- `H.i64_of_i32` SIGN-EXTENDS. `shl(1, fs - 1)` is `2**31` for a
# `float32` source, and `2**31` as a `U32` sign-extends to `-2147483648`, so `q7` interned
# `C(-2147483648)` where CPython has `C(2147483648)` -- and a SECOND, DEAD `C(2147483648)`
# sat next to it, because `+s` had already interned the correct I64 CONST.
# MEASURED, `q7k`: port `C(-2147483648)` against CPython `C(2147483648)`, one constant.
# `+s` IS the mask, so `dc_band`'s own shape is `AND(x, CONST)` and the CONST's INDEX is
# `O.Found.i(s)` -- the mask VALUE never has to round-trip through `U32` at all.
def f2f.sign(+ar: O.Arena, +udt: S.Dt, +v: U32, +fs: U32, +ts: U32) -> O.Found:
  +s = dd_wk(ar, T.tx_powi(U32.sub(fs, 1)))
  +a = T.tx_alu2(O.Found.ar(s), O.OpsAND{}, v, O.Found.i(s))
  +c = P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)
  T.tx_shl(O.Found.ar(c), O.Found.i(c), U32.sub(ts, fs))

# `(v & (shl(1, fs-1) - 1)).cast(f2f_dt[to])`
# ⚠ THE THREE `+s`/`+m1`/`+m` BINDERS BUILT A `2**k - 1` NODE GRAPH AND NOTHING READ
# IT. `dd_band`'s third parameter IS the mask VALUE (`op.bend`'s `dc_band` interns it as
# `dc_cint(ar, k)`), so those were four dead slots -- see `f2f.mask1`. `f2f.sign` keeps
# its one `+s` line and this one does not: there the CONST `+s` interns is the one
# `dc_band` HITS, so its slot is where the AND's mask has to live; here the AND's mask
# is a different VALUE and gets its own slot either way.

def f2f.nosign(+ar: O.Arena, +udt: S.Dt, +v: U32, +fs: U32) -> O.Found:
  +a = dd_band(ar, v, dd_mask1(U32.sub(fs, 1)))
  P.dc_cast(O.Found.ar(a), O.Found.i(a), udt)

# `shl(nosign, tm - fm) + shl(tb - fb, tm)`. `tb - fb` is a Python int and so is `tm`,
# so `shl(tb - fb, tm)` is `(tb - fb) * (2**tm)` evaluated IN PYTHON -- one interned
# `CONST`. It is never negative in the widening branch, which is what keeps the
# weakfloat remint out of this arm.
# ⚠ THIS ARM BUILT THE WRONG NODE until this rewrite: it passed `O.Found.i(a)` to
# `tx_shl`, so the graph was `a + (a * 2**tm)` and the `tb - fb` CONST it had just
# interned was DEAD. MEASURED: cpy[13] is `CONST C(1006632960)` feeding cpy[14]
# `ADD <- 12,13`, and `120 * 2**23 == 1006632960`; port[18] was `CONST C(120)` read by
# nothing, port[20] was `MUL <- 16,18` (a *masked*, not an offset) and port[21] was
# `ADD <- 16,19`. Two extra nodes and a different function.

def f2f.norm(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))
  +bf = dd_wk(O.Found.ar(a), H.i64_shl(H.i64_sub(H.i64_of_i32(T.exponent_bias(to)),
                                                H.i64_of_i32(T.exponent_bias(fr))),
                                     U32.to_nat(tm)))
  dd_add(O.Found.ar(bf), O.Found.i(a), O.Found.i(bf))

# `shl(nosign, tm - fm) | shl((shl(1, te) - 1), tm)`
# ⚠ THIS ARM WAS ONE ARENA HANDED TO TWO NODE BUILDERS. `T.tx_shl(O.Found.ar(a),
# f2f.em1(O.Found.ar(a), te), tm)` reads `O.Found.ar(a)` -- the arena BEFORE `em1` grew
# it -- so `tx_shl` wrote its `MUL` into the slot `em1`'s first `CONST` had just taken,
# and read `src0` at `em1`'s LAST slot, three past the `MUL`. The result was a graph
# whose `OR`'s operand pointed forward into the `OR` itself: on `f1` port slot 22 was
# `MUL <- 23,19` and slot 23 was `OR <- 17,22`, a CYCLE, and slot 18's `CONST C(2**te)`
# was gone. `+` means "the callee may REBIND this name", not "consumed on every path":
# two mints from one arena name both returned index 2 and overwrote each other.
# The rule this arm now follows is ONE ARENA, ONE BUILDER, PER NODE: `f2f.qmask`
# returns the arena it grew and that arena is what `dd_or` is handed.

def f2f.qnan(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +te: U32) -> O.Found:
  +a = T.tx_shl(ar, O.Found.i(ns), U32.sub(tm, fm))
  +qm = f2f.qmask(O.Found.ar(a), te, tm)
  dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))

# `fnuz_nan = sign.ne(0) & nosign.eq(0)`; `qnan = shl(shl(1, te) - 1, tm) | shl(1, tm - 1)`
# ⚠ THE SAME ALIASING AS `f2f.qnan`, on the `q1` operand this time.

def f2f.fnuz(+ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +te: U32, +tm: U32) -> O.Found:
  +z = dd_wk(ar, H.i64_of_i32(0))
  # ⚠ `dd_ne(ar, ...)` WROTE OVER `z`'s OWN SLOT -- `+z` had already interned `C(0)`
  # there -- and `a`'s src1 was that same slot, so `a` pointed at ITSELF. On `q4` before:
  # `18 CMPNE/2 CMPNE <- 6,18 FORWARD`.
  +a = dd_ne(O.Found.ar(z), O.Found.i(sg), O.Found.i(z))
  +b = dd_eq1(O.Found.ar(a), O.Found.i(ns), O.Found.i(z))
  +fn = dd_and(O.Found.ar(b), O.Found.i(a), O.Found.i(b))
  # ⚠ `qnan` IS ONE CONST. It used to be `f2f.qmask`, then `CONST 2**(tm-1)`, then an
  # `OR` -- three nodes -- and the `OR` was handed `q1`'s arena with `qk` minted in
  # between, so it also wrote over `qk` and pointed at ITSELF: `23 OR/2 OR <- 16,23
  # FORWARD` on `q4` before. See `f2f.qnan.c` for the `C(2143289344)` measurement.
  +q = f2f.qnan.c(O.Found.ar(fn), te, tm)
  +e = dd_eq1(O.Found.ar(q), O.Found.i(ex), O.Found.i(z))
  +w = dd_where(O.Found.ar(e), O.Found.i(e), O.Found.i(z), O.Found.i(nm))
  +s = dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w))
  dd_where(O.Found.ar(s), O.Found.i(fn), O.Found.i(q), O.Found.i(s))

# `is_nan = nosign.eq(shl(1, fm + fe) - 1)` for `fp8e4m3` else `exp.eq(shl(1, fe) - 1)`
# ⚠ BOTH ARMS COMPARED AGAINST `2**(fm+fe)` AND `2**fe` -- THE MASK, NOT THE MINUS ONE.
# dtype.py's `- 1` is inside the Python int `shl(1, k) - 1`, so the node is `C(2**k - 1)`
# and the port's `C(2**k)` was a different function. MEASURED: cpy[6] is `C(127)` feeding
# cpy[17] `CMPNE <- 8,6` (`nosign` vs `127`); the port's q1 read `CMPNE <- 12,1` (`nosign`
# vs `128`). CPython's own `q1k` carries the `C(127)` the port never compared against.

def f2f.isnan(+ar: O.Arena, +ns: O.Found, +ex: O.Found, +fe: U32, +fm: U32, e4m3: Bool) -> O.Found:
  match e4m3:
    case True{}:
      +m = dd_mask1.node(ar, U32.add(fm, fe))
      dd_eq1(O.Found.ar(m), O.Found.i(ns), O.Found.i(m))
    case False{}:
      +m = dd_mask1.node(ar, fe)
      dd_eq1(O.Found.ar(m), O.Found.i(ex), O.Found.i(m))

# ---- NARROWING

def f2f.ocp(e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32) -> O.Found:
  +i = f2f.isnan(ar, ns, ex, fe, fm, e4m3)
  +z = dd_wk(O.Found.ar(i), H.i64_of_i32(0))
  +e = dd_eq1(O.Found.ar(z), O.Found.i(ex), O.Found.i(z))
  +iu = dd_where(O.Found.ar(e), O.Found.i(i), O.Found.i(nn), O.Found.i(nm))
  # ⚠ `O.Found.ar(e)` IS ONE NODE STALE: `dd_where` grew it into `iu`. On `q3` before:
  # `42 WHERE/3 WHERE <- 29,42 FORWARD`, whose src2 was the `WHERE`'s own slot.
  +w = dd_where(O.Found.ar(iu), O.Found.i(e), O.Found.i(z), O.Found.i(iu))
  dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w))

def f2f.up.tail(fnuz: Bool, e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32, +te: U32, +tm: U32) -> O.Found:
  match fnuz:
    case True{}: f2f.fnuz(ar, ns, sg, ex, nm, te, tm)
    case False{}: f2f.ocp(e4m3, ar, ns, sg, ex, nm, nn, fe, fm)

def f2f.up(+fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +udt = f2f.udt(to)
  +fs = S.Dt.bits(fr)
  +ts = S.Dt.bits(to)
  +sg = f2f.sign(ar, udt, v, fs, ts)
  +ns = f2f.nosign(O.Found.ar(sg), udt, v, fs)
  +ex = T.tx_shr(O.Found.ar(ns), O.Found.i(ns), fm)
  +nm = f2f.norm(O.Found.ar(ex), ns, fm, tm, fr, to)
  +nq = f2f.qnan(O.Found.ar(nm), ns, fm, tm, te)
  +w = f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), O.Found.ar(nq), ns, sg, ex, nm, nq, fe, fm, te, tm)
  T.tx_bitcast(O.Found.ar(w), O.Found.i(w), to)

# ⚠ THE SAME `U32` MASK ROUND-TRIP AS `f2f.sign`, at `2**(ts - 1)`. No fixture the file owns
# reaches `ts = 32` -- `ts` is the TARGET's width and every narrowing target here is fp8 --
# so this is a latent defect, fixed because the fix is the same one line and the wrong
# version is what `f2f.sign` shipped.
def f2f.down.sign(+ar: O.Arena, +v: O.Found, +fs: U32, +ts: U32) -> O.Found:
  +a = T.tx_shr(ar, O.Found.i(v), U32.sub(fs, ts))
  +b = dd_wk(O.Found.ar(a), T.tx_powi(U32.sub(ts, 1)))
  T.tx_alu2(O.Found.ar(b), O.OpsAND{}, O.Found.i(a), O.Found.i(b))

# `v & (shl(1, fs - 1) - 1)`
# ⚠ THE SAME THREE DEAD BINDERS AS `f2f.nosign`: `dd_band`'s third parameter is the mask
# VALUE, so `+s`/`+c1`/`+m` minted a four-node graph that nothing read.

def f2f.down.nosign(+ar: O.Arena, +v: O.Found, +fs: U32) -> O.Found:
  dd_band(ar, O.Found.i(v), dd_mask1(U32.sub(fs, 1)))

# `(rne(nosign, fm - tm) - shl(fb - tb, tm)).cast(f2f_dt[to])`

# ⚠ `+k` interned `C(fb - tb)` and `tx_shl` multiplied `x` by `2**tm` -- so the graph was
# `(x - (fb - tb)) * 2**tm`, which is not the function, and it cost a `CONST 2**tm` and a
# `MUL` that CPython does not have. `shl(fb - tb, tm)` is `x * (2**y)` with BOTH
# arguments Python ints (transcendental.py:20), so the whole offset is one CONST and the
# subtraction keeps `dc_sub`'s `x + MUL(C(k), C(-1))`. MEASURED, `q2`: cpy[58] is
# `CONST C(960)` (`120 * 2**3` for `float32 -> fp8e4m3`) feeding cpy[59] `MUL <- 58,32`
# where 32 is `C(-1)`, and cpy[60] is `ADD <- 57,59`; `q3` reads `C(448)` (`112 * 2**2`)
# and `q5` reads `C(444)` (`111 * 2**2`, the fnuz bias of 16). The port read `C(120)`.
# `+xi` AND NOT `+x: O.Found`, because `O.Found.ar(x)` CONSUMES `x` and passing `x` then
# consumes it again: bend says `x (consumed more than once)`. `+ar` and `O.Found.ar(x)`
# are the same value, so the caller passes both parts.
def f2f.down.norm.put(+tudt: S.Dt, +ar: O.Arena, +xi: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +k = dd_wk(ar, H.i64_shl(H.i64_sub(H.i64_of_i32(T.exponent_bias(fr)), H.i64_of_i32(T.exponent_bias(to))),
                           U32.to_nat(T.tx_finfo_m(to))))
  +d = P.dc_sub(O.Found.ar(k), xi, O.Found.i(k))
  P.dc_cast(O.Found.ar(d), O.Found.i(d), tudt)

# ⚠ `+ar` IS ONLY LIVE IN THE `None` ARM. `rne` grows a COPY, and `f2f.down.norm` used
# to hand `put` the name `ar` -- the arena from BEFORE rne -- so `put` wrote over rne's
# twelve nodes and the whole `rne` subtree vanished. THE FORWARD DETECTOR CANNOT SEE
# THIS: rne's own edges all still pointed backwards and the only symptom was a node
# COUNT (`q3` 50 against CPython's 126 slots for the fixture). Found by
# `.agents/slop/dd-stalearena.py` rule R1, which is why that file exists.
def f2f.down.norm.g(r: Maybe<&2, O.Found>, +tudt: S.Dt, +ar: O.Arena, +fr: S.Dt, +to: S.Dt) -> O.Found:
  match r:
    case Some{O.Found{+xa, +xi}}: f2f.down.norm.put(tudt, xa, xi, fr, to)
    case None{}: dd_const.int(ar, H.i64_of_i32(0), tudt)

# `underflow = (shr(v, fm) & (shl(1, fe) - 1)) < (1 + fb - tb)`. The right side is
# a Python int, so `ufix` makes it a WEAKINT const and the promotion folds.

def f2f.down.norm(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  f2f.down.norm.g(rne(ar, O.Found.i(ns), U32.sub(fm, tm)), f2f.udt(to), ar, fr, to)

def f2f.down.uf(+ar: O.Arena, +v: O.Found, +fm: U32, +fe: U32, +fr: S.Dt, +to: S.Dt) -> O.Found:
  +a = T.tx_shr(ar, O.Found.i(v), fm)
  +b = dd_band(O.Found.ar(a), O.Found.i(a), dd_mask1(fe))
  +c = dd_wk(O.Found.ar(b), H.i64_of_i32(U32.add(U32.sub(T.exponent_bias(fr), T.exponent_bias(to)), 1)))
  dd_lt1(O.Found.ar(c), O.Found.i(b), O.Found.i(c))

# `nan_mantissa = (shl(1, tm) - 1) if to == dtypes.fp8e4m3 else (shr(nosign, fm - tm) & (shl(1, tm) - 1))`

# ⚠ THE THIRD DEAD MASK GRAPH. MEASURED, `q2`: cpy[50] is `CONST C(524287)` and it is
# OR'd straight into the `nan`; the port minted `CONST C(8388608)`, `CONST C(1)`,
# `CONST C(-1)`, `MUL` and `ADD` for the same number.
def f2f.down.m1(+ar: O.Arena, +tm: U32) -> O.Found:
  dd_mask1.node(ar, tm)

def f2f.down.m2(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32) -> O.Found:
  +a = T.tx_shr(ar, O.Found.i(ns), U32.sub(fm, tm))
  dd_band(O.Found.ar(a), O.Found.i(a), dd_mask1(tm))

# `(sign | nan_mantissa | shl(shl(1, te) - 1, tm)).cast(f2f_dt[to])`

def f2f.down.mant(+ar: O.Arena, +ns: O.Found, +fm: U32, +tm: U32, e4m3: Bool) -> O.Found:
  match e4m3:
    case True{}: f2f.down.m1(ar, tm)
    case False{}: f2f.down.m2(ar, ns, fm, tm)

# ⚠ THE THIRD OF THE THREE ALIASED ARMS -- `f2f.qnan`, `f2f.fnuz` and this one all wrote
# `T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)`, one arena to two builders.
# On `n2` the two `FORWARD` slots 41 and 48 were this arm and its `.cast`, and slot 26's
# `MUL <- 36,25` and slot 28's `ADD <- 36,27` were the overwritten pair.
def f2f.down.npat(+ar: O.Arena, +sg: O.Found, +nm: O.Found, +te: U32, +tm: U32, +to: S.Dt) -> O.Found:
  +tudt = f2f.udt(to)
  +a = dd_or(ar, O.Found.i(sg), O.Found.i(nm))
  +qm = f2f.qmask(O.Found.ar(a), te, tm)
  +c = dd_or(O.Found.ar(qm), O.Found.i(a), O.Found.i(qm))
  P.dc_cast(O.Found.ar(c), O.Found.i(c), tudt)

# `is_nan = (shr(v, fm) & (shl(1, fe) - 1)).eq(shl(1, fe) - 1)`. The AND is the
# one `underflow` built, so it is interned; the `eq` is two CMPNEs.

# ⚠ `+mc` minted `2**fe - 1` as `ADD(C(2**fe), MUL(C(1), C(-1)))` -- four nodes -- and
# `dd_band`'s third parameter interned the SAME mask as a `CONST` two slots later, so the
# graph and the constant were both in the arena. MEASURED, `q2`: cpy[50] `C(524287)` is
# the single CONST the AND and the EQ both read.
def f2f.down.isnan(+ar: O.Arena, +v: O.Found, +fm: U32, +fe: U32) -> O.Found:
  +a = T.tx_shr(ar, O.Found.i(v), fm)
  +mc = dd_mask1.node(O.Found.ar(a), fe)
  +b = dd_band(O.Found.ar(mc), O.Found.i(a), dd_mask1(fe))
  dd_eq1(O.Found.ar(b), O.Found.i(b), O.Found.i(mc))

# `sign.cast(f2f_dt[to]) | norm`, which the fnuz return wraps.

def f2f.down.inner(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +to: S.Dt) -> O.Found:
  +c = P.dc_cast(ar, O.Found.i(sg), f2f.udt(to))
  dd_or(O.Found.ar(c), O.Found.i(c), O.Found.i(nr))

def f2f.down.fnuz(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +uf: O.Found, +ii: O.Found, +ts: U32, +to: S.Dt) -> O.Found:
  +k = dd_wk(ar, T.tx_powi(U32.sub(ts, 1)))
  +in = f2f.down.inner(O.Found.ar(k), sg, nr, to)
  +z = dd_wk(O.Found.ar(in), H.i64_of_i32(0))
  +w = dd_where(O.Found.ar(z), O.Found.i(uf), O.Found.i(z), O.Found.i(in))
  dd_where(O.Found.ar(w), O.Found.i(ii), O.Found.i(k), O.Found.i(w))

def f2f.down.ocp(+ar: O.Arena, +sg: O.Found, +nr: O.Found, +uf: O.Found, +ii: O.Found, +nm: O.Found, +to: S.Dt) -> O.Found:
  +c = P.dc_cast(ar, O.Found.i(sg), f2f.udt(to))
  +z = dd_wk(O.Found.ar(c), H.i64_of_i32(0))
  # ⚠ `O.Found.ar(c)` IS ONE NODE STALE: `dd_wk` grew it into `z`.
  +w = dd_where(O.Found.ar(z), O.Found.i(uf), O.Found.i(z), O.Found.i(nr))
  +o = dd_or(O.Found.ar(w), O.Found.i(c), O.Found.i(w))
  dd_where(O.Found.ar(o), O.Found.i(ii), O.Found.i(nm), O.Found.i(o))

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
  +ns = f2f.down.nosign(O.Found.ar(sg), v, fs)
  +nr = f2f.down.norm(O.Found.ar(ns), ns, fm, tm, fr, to)
  +uf = f2f.down.uf(O.Found.ar(nr), v, fm, fe, fr, to)
  +nm = f2f.down.mant(O.Found.ar(uf), ns, fm, tm, dd_is_e4m3(to))
  +nn = f2f.down.npat(O.Found.ar(nm), sg, nm, te, tm, to)
  +ii = f2f.down.isnan(O.Found.ar(nn), v, fm, fe)
  f2f.down.tail(T.tx_is_fnuz(to), O.Found.ar(ii), sg, nr, uf, ii, nm, ts, to)

# `shr(v, fs - ts) & shl(1, ts - 1)`

# ⚠ NEITHER DEF TAKES AN `ar` ANY MORE, AND THAT IS THE POINT. Both used to, and
# `f2f.down.has` passed the SAME `ar` to `f2f_clamp` and to `f2f.clamped`, so `tx_bitcast`
# and `f2f.narrow` rebuilt the whole clamp on top of itself. The arena now travels INSIDE
# the `Maybe` -- `case Some{O.Found{+ca, +ci}}` -- so there is no name a caller can hand
# over stale. Found by `.agents/slop/dd-stalearena.py` rule R1.
def f2f.clamped.put(+udt: S.Dt, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ca: O.Arena, +ci: U32, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  +bc = T.tx_bitcast(ca, ci, udt)
  Some{f2f.narrow(bc, udt, fe, fm, te, tm, O.Found.ar(bc), fr, to)}

def f2f.clamped(m: Maybe<&2, O.Found>, +udt: S.Dt, +fe: U32, +fm: U32, +te: U32, +tm: U32, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  match m:
    case None{}: None{}
    case Some{O.Found{+ca, +ci}}: f2f.clamped.put(udt, fe, fm, te, tm, ca, ci, fr, to)

# `v = f2f_clamp(v.bitcast(fr), to, sat).bitcast(f2f_dt[fr])`, renamed `v`, then
# the two halves and the two return shapes. `fs` is the SOURCE's bit width,
# which is 64 for a `float64` source.

def f2f.down.has(mx: Maybe<&2, F32>, sat: Bool, +fe: U32, +fm: U32, +te: U32, +tm: U32, +ar: O.Arena, +v: U32, +fr: S.Dt, +to: S.Dt) -> Maybe<&2, O.Found>:
  match mx:
    case None{}: None{}
    case Some{+m}:
      +bc = T.tx_bitcast(ar, v, fr)
      f2f.clamped(f2f_clamp(O.Found.ar(bc), O.Found.i(bc), fr, to, dd_is_fp8(to)), f2f.udt(fr), fe, fm, te, tm, fr, to)

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

# The three op sets the tables name. `GroupOp.All` is every op, `GroupOp.ALU` is
# Unary|Binary|Ternary, and `GroupOp.Comparison` is the three that yield bool.
# They are spelled out because `uop/ops.bend` names each op and nothing owns the
# groups -- and a table row is only as good as the set it claims, so the gate
# prints them and a missing op is a red cell rather than a silent narrowing.

def dd_ops.cmp() -> List<&2, O.Op>:
  [O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}]

# `(GroupOp.ALU - GroupOp.Comparison - {SHL, SHR, WHERE}) | {BITCAST}` -- the
# catch-all ARM at dtype.py:173, and the only set that is a DIFFERENCE, so it
# cannot be a shared list.

def dd_ops.alu11() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsBITCAST{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsFLOORDIV{},
   O.OpsFLOORMOD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{},
   O.OpsRECIPROCAL{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsXOR{}]

def dd_ops.alu() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAND{}, O.OpsBITCAST{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{},
   O.OpsEXP2{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsINDEX{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMUL{},
   O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{}, O.OpsRECIPROCAL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{},
   O.OpsSQRT{}, O.OpsSTACK{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}]

def dd_ops.all() -> List<&2, O.Op>:
  [O.OpsADD{}, O.OpsAFTER{}, O.OpsALLOC{}, O.OpsALLREDUCE{}, O.OpsAND{}, O.OpsBACKEDGE{}, O.OpsBARRIER{},
   O.OpsBINARY{}, O.OpsBITCAST{}, O.OpsBUFFER{}, O.OpsCALL{}, O.OpsCAST{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{},
   O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCONST{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsCOPY{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{},
   O.OpsCUSTOM_FUNCTION{}, O.OpsDETACH{}, O.OpsEND{}, O.OpsENDIF{}, O.OpsEXP2{}, O.OpsEXPAND{}, O.OpsFDIV{},
   O.OpsFLIP{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsGETADDR{}, O.OpsGROUP{}, O.OpsIF{}, O.OpsINDEX{},
   O.OpsINS{}, O.OpsLINEAR{}, O.OpsLOAD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsMUL{},
   O.OpsMULACC{}, O.OpsNEG{}, O.OpsNOOP{}, O.OpsOR{}, O.OpsPAD{}, O.OpsPARAM{}, O.OpsPERMUTE{}, O.OpsPOW{},
   O.OpsPROGRAM{}, O.OpsPYLITERAL{}, O.OpsRANGE{}, O.OpsRECIPROCAL{}, O.OpsREDUCE{}, O.OpsRESHAPE{},
   O.OpsREWRITE_ERROR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSHRINK{}, O.OpsSIN{}, O.OpsSINK{}, O.OpsSOURCE{},
   O.OpsSPECIAL{}, O.OpsSQRT{}, O.OpsSTACK{}, O.OpsSTAGE{}, O.OpsSTORE{}, O.OpsSUB{}, O.OpsTHREEFRY{},
   O.OpsTRUNC{}, O.OpsUNSHARD{}, O.OpsWHERE{}, O.OpsWMMA{}, O.OpsXOR{}]

def pm_long_decomp() -> O.PMEntrys:
  O.PMEntrys{[
    # 150  GroupOp.All, any dtype
    O.PMEntry{0,  dd_ops.all(), Nil{}},
    # 151  GroupOp.Defines at a long dtype
    O.PMEntry{1,  [O.OpsALLOC{}, O.OpsBUFFER{}, O.OpsPARAM{}], Nil{}},
    # 152  INDEX at a long dtype
    O.PMEntry{2,  [O.OpsINDEX{}], Nil{}},
    # 154  STORE of an index at a long dtype
    O.PMEntry{3,  [O.OpsSTORE{}], Nil{}},
    # 157  a Comparison over long-dtype operands
    O.PMEntry{4,  dd_ops.cmp(), Nil{}},
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
    # 173  ALU minus Comparison minus SHL/SHR/WHERE, plus BITCAST
    O.PMEntry{11, dd_ops.alu11(), Nil{}},
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
    # 200  ALU, plus STACK and INDEX
    O.PMEntry{7,  dd_ops.alu(), Nil{}},
    # 202  STORE of a converted value
    O.PMEntry{8,  [O.OpsSTORE{}], [O.OpsBITCAST{}]},
    # 204  STORE of a float value
    O.PMEntry{9,  [O.OpsSTORE{}], Nil{}}]}

def pm_dtype_decomps() -> O.PMEntrys:
  O.PMEntrys{[
    # 220  GroupOp.All restricted by DTYPE
    O.PMEntry{0,  dd_ops.all(), Nil{}},
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
  # `l2i(op, dt, *graph_rewrite(UOp.sink(*uops), ...).src)` -- the `.src` is a
  # `graph_rewrite` result, so with the wall in place there is no word list to
  # hand `l2i` and there is no pair to return.
  None{}

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
  graph_rewrite(sink, do_dtype_decomps.pmf(False{}, S.uint32(), 0), 0, True{})

# ===========================================================================
# THE GATE. `.agents/slop/dd-oracle.py` calls CPython's `dtype.py` and prints
# four facts per fixture; this prints the same four for the port and the two
# files are diffed row for row. Python is the reference.
#
#   <nm>=      the answer's TREE, two levels: `LABEL(sh1(src),...)`
#   <nm>n=     how many nodes the fixture interned, in CREATION ORDER
#   <nm>sig=   `op/nsrc` for each of them, in that same order
#   <nm>k=     the CONSTANTS among them, in that same order
#
# THE THREE PRINT-SHAPE DECISIONS, restated as code:
#   * `mixin/elementwise.py` is NOT PORTED, so `_broadcasted`'s promotion CAST
#     and `logical_not`'s `cast(bool)` are absent from the arena and there is
#     nothing to erase here. That is why there is no `uncast` below and why the
#     oracle's two erasures are the WHOLE of the difference between the lanes.
#   * a CONST prints as its ARENA WORD -- `C(<lo>)`, `C(<hi>:<lo>)`, `C(-<mag>)`
#     for an integer and `F(<its 32 bits>)` for a float. A decimal float could
#     not agree with the oracle at the `float32` maximum, so the bit pattern is
#     the label and `H.f32_show` is not used.
#   * `sig` is the arena's CREATION ORDER, which is why every def above builds
#     its nodes in CPython's evaluation order and not in a tidier one.
#
# EVERY PRINTER TAKES THE ARENA BY VALUE: the arena is a `Data` value, a reader
# does not move it, and a printer must read it many times.
# ===========================================================================

def dd_cval.go(neg: Bool, +lo: U32, +hi: U32) -> String:
  match neg:
    case True{}: String.concat(["C(-", U32.show(U32.sub(0, lo)), ")"])
    case False{}: String.concat(["C(", Bool.pick(String, U32.is_zero(hi), U32.show(lo),
      String.concat([U32.show(hi), ":", U32.show(lo)])), ")"])

# DESTRUCTURED, not `i64_is_neg(i), lo32(i), hi32(i)`: `I64` is linear, so a
# binder may be read once and a parameter is not a copy.
def dd_cval(i: H.I64) -> String:
  match i:
    case H.I64{+hi, +lo}: dd_cval.go(H.i32_is_neg(hi), lo, hi)

def dd_lab.name(m: Maybe<&2, String>, +k: String) -> String:
  match m:
    case Some{+s}: String.concat(["P", s])
    case None{}: k

def dd_lab.node(+op: O.Op, +arg: O.Arg) -> String:
  match arg:
    case O.AParam{+pa}: dd_lab.name(O.ParamArg.name(pa), P.dc_opname(op))
    case O.APy{O.CInt{i}}: dd_cval(i)
    case O.APy{O.CFloat{f}}: String.concat(["F(", U32.show(F32.bits(f)), ")"])
    case O.APy{O.CBool{+b}}: dd_cval(H.i64_of_i32(Bool.pick(U32, b, 1, 0)))
    case _: P.dc_opname(op)

def dd_lab.nd(nd: O.Node) -> String:
  match nd:
    case O.Node{+op, +src, +arg, +tag}: dd_lab.node(op, arg)

def dd_lab(ar: O.Arena, u: U32) -> String:
  dd_lab.nd(O.Arena.node(ar, u))

def dd_sfx1.go(+ar: O.Arena, +u: U32, wide: Bool) -> String:
  match wide:
    case True{}: String.concat([dd_lab(ar, O.Arena.src0(ar, u)), ",",
                                dd_lab(ar, O.Arena.src(ar, u, 1)), ",",
                                dd_lab(ar, O.Arena.src(ar, u, 2))])
    case False{}: String.concat([dd_lab(ar, O.Arena.src0(ar, u)), ",",
                                 dd_lab(ar, O.Arena.src(ar, u, 1))])

def dd_sfx1.put(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dd_lab(ar, O.Arena.src0(ar, u))
    case 2: dd_sfx1.go(ar, u, True{})
    case _: dd_sfx1.go(ar, u, False{})

def dd_sh1.go(+ar: O.Arena, +u: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dd_lab(ar, u)
    case False{}: String.concat([dd_lab(ar, u), "(", dd_sfx1.put(ar, u,
                                 U32.sub(U32.min(O.Arena.nsrc(ar, u), 3), 1)), ")"])

def dd_sh1(+ar: O.Arena, +u: U32) -> String:
  dd_sh1.go(ar, u, U32.is_zero(O.Arena.nsrc(ar, u)))

def dd_sfx2.put(+ar: O.Arena, +u: U32, k: U32) -> String:
  match k:
    case 0: dd_sh1(ar, O.Arena.src0(ar, u))
    case 2: String.concat([dd_sh1(ar, O.Arena.src0(ar, u)), ",",
                           dd_sh1(ar, O.Arena.src(ar, u, 1)), ",",
                           dd_sh1(ar, O.Arena.src(ar, u, 2))])
    case _: String.concat([dd_sh1(ar, O.Arena.src0(ar, u)), ",",
                           dd_sh1(ar, O.Arena.src(ar, u, 1))])

def dd_tree.go(+ar: O.Arena, +u: U32, leaf: Bool) -> String:
  match leaf:
    case True{}: dd_lab(ar, u)
    case False{}: String.concat([dd_lab(ar, u), "(", dd_sfx2.put(ar, u,
                                  U32.sub(U32.min(O.Arena.nsrc(ar, u), 3), 1)), ")"])

def dd_tree(+ar: O.Arena, +u: U32) -> String:
  dd_tree.go(ar, u, U32.is_zero(O.Arena.nsrc(ar, u)))

# THE FUEL. bend wants a DECREASING self-call ("arguments are read left to
# right: each passed unchanged until one shrinks"), so every walk here counts in a
# `Nat` countdown and the other arguments only ever move. A window of `n` nodes
# holds at most `n` stack entries per edge, so `32 * n + 64` cannot run out.
#
# ⚠ `n` IS `Arena.next(ar)` AND NOT THE CREATION WINDOW, and that is the whole of the
# CDIV/CMOD cone collapse. The fuel used to be `32 * (to - from)` -- the SIZE OF THE
# FIXTURE'S OWN INTERNING WINDOW -- and a fixture that interns NOTHING has
# `to == from`, so it got `64`. `lgt` interns nothing (`lgtn = 0` in both lanes: the
# whole CDIV cone was interned by the `lgs` fixture before it), so its cone walk ran
# out of fuel after 57 nodes and `lgtsig` read
#     WHERE/3,CMPNE/2,OR/2,CMPLT/2,WHERE/3,...,SHL/2
# against CPython's 2184-node cone; `lgrn = 2` gave fuel 128 and `lgrsig` read 112
# against 2218. MEASURED on the live tree: the SAME `l2i` call prints a 2186-node
# cone for `lgt` and 2222 for `lgr` when it is given fuel from the arena. It is a
# TRUNCATED WALK, not a small graph, and it is invisible in `--check-only` because a
# truncated cone is still a well-formed list of `op/nsrc` words. CPython's `cone()`
# has no fuel at all: `dd-oracle.py` walks until the stack empties, and the row it
# prints is the whole cone.
#
# `dd_seen` below was already arena-based, which is why the membership test had fuel
# and the walk did not. One multiplier, `5n` = 32, is kept so that the fuel for every
# fixture is at least what it used to be (`next(ar) >= to - from` always), and a row
# that passed before cannot lose fuel.
def dd_fuel(+ar: O.Arena) -> Nat:
  U32.to_nat(U32.add(U32.shln(O.Arena.next(ar), 5n), 64))

def dd_join.add(first: Bool, +acc: String, +s: String) -> String:
  match first:
    case True{}: s
    case False{}: String.concat([acc, ",", s])

def dd_join.dash(first: Bool, acc: String) -> String:
  match first:
    case True{}: "-"
    case False{}: acc

def dd_sig1(+ar: O.Arena, +u: U32) -> String:
  String.concat([P.dc_opname(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u))])

# ===========================================================================
# THE CANONICAL ROW, and the invariant it has.
#
# `sig` IS THE ANSWER'S CONE IN DFS PRE-ORDER: every arena node REACHABLE from
# the answer root(s), each ONCE, listed parent-before-child and src[0] first.
#
# WHAT IT IS INVARIANT TO, which is what the old row was not:
#   * WHEN a node was interned. Arena slot numbers, the window `[from, to)` and
#     the order CPython happened to call things in never appear.
#   * SHARING. `intern.find` compares whole `Node`s, so two structurally equal
#     nodes are the SAME index, and the walk visits an index once. A module-level
#     constant interned once and referenced N times contributes ONE entry, exactly
#     as N equal copies would -- so the row cannot tell them apart, BY CONSTRUCTION.
#   * CONSTANT INTERNING SPECIFICALLY, which is the trap this row was rebuilt for.
#     `dtype.py:22`'s `zero = UOp.const(0, dt)` is interned by `ucache` the first
#     time any fixture needs it and REUSED by every later one, so a node inventory
#     measured over the window is a function of the WHOLE SESSION, not of `l2i`.
#     Measured: `IDX()` is called by the oracle's own `u32n` row, so it interns
#     `C(0)/C(1)` at u32 before the first `l2i` fixture runs.
#
# WHAT IT STILL CANNOT SEE, stated so nobody reads agreement as proof:
#   * HOW MANY SLOTS were minted, or nodes the answer does not reach. `<nm>n=` is
#     the row for that, and it still measures interning -- a disagreement there is
#     a real difference in the arena, not a metric artefact.
#   * A NODE'S DTYPE, TAG or metadata: `op/nsrc` is the whole node shape.
#   * WHICH src of a node an equal node is: that is the sharing the row is blind
#     to on purpose, so two ISOMORPHIC cones agree by definition.
#   * A RAISE that happened after nodes were minted. CPython's `sig` on a refusal
#     is "what the body interned before the raise"; this row is the cone of an
#     answer that does not exist, which is empty. `lgn` is the row that shows the
#     two coincide, and the port's pre-call guard at dtype.py:81 is why.
# ===========================================================================

def dd_rs.cat(h: U32, st: List<&2, U32>) -> List<&2, U32>:
  h <> st

# APPENDS each src in order, so the head popped is src[0], which is what
# dd-oracle.py's `cone` walks (`for s in v.src: go(s)`). Prepending here popped
# src[n] first, which reversed the children of every multi-src node in `sig`:
# `upsig` read `AND/2,CONST/0,PARAM/0,FLOORDIV/2,CONST/0,PARAM/0` where CPython
# reads `AND/2,PARAM/0,CONST/0,FLOORDIV/2,PARAM/0,CONST/0`.
def dd_rs.push(f: Nat, srcs: List<&2, U32>, st: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: st
    case 1n+q:
      match srcs:
        case Nil{}: st
        case s <> t: dd_rs.cat(s, dd_rs.push(q, t, st))

def dd_rs.has(f: Nat, xs: List<&2, U32>, +u: U32) -> Bool:
  match f:
    case 0n: False{}
    case 1n+q:
      match xs:
        case Nil{}: False{}
        case h <> t:
          r = dd_rs.has(q, t, u)
          Bool.or(U32.is_eq(h, u), r)

# PREPENDED, so the push is O(1) and only the one `List.reverse` at the end is
# O(n). Appending instead makes the walk O(n^2) in list cells on top of `has`.
# It is also the MEMBERSHIP TEST, not an append: a node with two parents is
# reachable ONCE, so it is listed once. Unconditional, it listed a shared node
# once per parent -- `lgwsig` read `CAST/1,CONST/0,CAST/1` where CPython's
# `cone` dedups by `id` and reads `CAST/1,CONST/0`.
#
# ONE test, TWO consumers: `go` asks `has` twice rather than threading the one
# answer, because doing both effects from a single test needs a pair return, and
# a pair can only be destructured from a PARAMETER -- `more` returning
# `(st, seen)` and `go` taking it is refused at the `(st, seen) = r` bind. That
# doubles the membership walk, not its order: `go` already spent one per pop on
# `more` and this walk is already O(n^2) in `seen`.
#
# `nat` is a PARAMETER, not a bound value, because a `match` may not scrutinise
# a computed value nor a local binder ("give it its own def"). `dd_rs.more` is
# the same shape for the same reason.
def dd_rs.add(nat: Bool, u: U32, xs: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case True{}: dd_rs.cat(u, xs)
    case False{}: xs

# `seen` never outgrows the arena, and the FUEL is spent here rather than read
# out of `dd_rs.go`'s own countdown: `case 1n+q:` has already SPENT that `Nat`, so
# a second read of it inside the arm is a second consumption of a piece of it.
def dd_seen(ar: O.Arena) -> Nat:
  U32.to_nat(O.Arena.next(ar))

def dd_rs.more(nat: Bool, +ar: O.Arena, +u: U32, st: List<&2, U32>) -> List<&2, U32>:
  match nat:
    case True{}: dd_rs.push(U32.to_nat(O.Arena.nsrc(ar, u)), O.Arena.srcs(ar, u), st)
    case False{}: st

def dd_rs.go(f: Nat, +ar: O.Arena, +st: List<&2, U32>, +seen: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: seen
    case 1n+q:
      match st:
        case Nil{}: seen
        case +u <> rest:
          st2 = dd_rs.more(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), ar, u, rest)
          sn = dd_rs.add(Bool.not(dd_rs.has(dd_seen(ar), seen, u)), u, seen)
          dd_rs.go(q, ar, st2, sn)

def dd_cone(n: Nat, +ar: O.Arena, +roots: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, dd_rs.go(n, ar, roots, Nil{}))

def dd_esig(+ar: O.Arena, f: Nat, +xs: List<&2, U32>, +first: Bool, +acc: String) -> String:
  match f:
    case 0n: acc
    case 1n+q:
      match xs:
        case Nil{}: acc
        case u <> t:
          s = dd_join.add(first, acc, dd_sig1(ar, u))
          dd_esig(ar, q, t, False{}, s)

# The CONSTANTS of the cone, in the cone's own order. `sig` alone cannot separate
# two `f2f_clamp`s over different `mx` values, because `lab` prints a CAST as the
# bare word `CAST` and a CONST's VALUE is in no node shape at all.

def dd_ck.arg(+arg: O.Arg) -> Bool:
  match arg:
    case O.APy{O.CInt{i}}: True{}
    case O.APy{O.CFloat{f}}: True{}
    case O.APy{O.CBool{+b}}: True{}
    case _: False{}

def dd_ck(+ar: O.Arena, +u: U32) -> Bool:
  dd_ck.arg(O.Arena.arg(ar, u))

def dd_join.ck(first: Bool, k: Bool, +acc: String, +s: String) -> String:
  match k:
    case True{}: dd_join.add(first, acc, s)
    case False{}: acc

# `first` CLEARS ITSELF HERE AND NOT IN `dd_join.add`: `dd_join.add(first, acc, s)`
# answers `s` when `first`, so a fold that threaded `first` unchanged printed the
# LAST label and then the `-` fallback -- which is why every one of the 121 rows
# said `k=-`, and `k` was a column no mutation could move. `nf` is
# `first AND NOT k`: nothing seen yet, or this node was not a CONST.

def dd_eck(+ar: O.Arena, f: Nat, +xs: List<&2, U32>, +first: Bool, +acc: String) -> String:
  match f:
    case 0n: dd_join.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: dd_join.dash(first, acc)
        case u <> t:
          +k = dd_ck(ar, u)
          nf = Bool.and(first, Bool.not(k))
          s = dd_join.ck(first, k, acc, dd_lab(ar, u))
          dd_eck(ar, q, t, nf, s)

# ---- the four rows, and the mark that separates one fixture from the next

# ---- THE MARK AND THE TEXT
#
# The arena in `ops.bend` is PERSISTENT: `intern.put` returns a NEW `Arena`, so
# a `+ar` parameter is CONSUMED and the next one arrives inside the answer
# (`O.Found.ar`). A refusal has no answer and therefore no arena back -- which is
# why every refusal below is a PURE guard evaluated BEFORE the call, so the call
# never happens and the arena is still live.
#
# `Ga` holds the arena BY VALUE, which is why the fixture NODES can be built once
# in `fixtures` and then only INDEXED: the arena is append-only, so an index
# minted before the first fixture is still the same node after the last one.
# That is what makes one text for the whole gate buildable.

type Ga is Data:
  Ga{ar: O.Arena, n: U32, s: String, ps: List<&2, U32>, w: List<&2, U32>, z: U32, o: U32}

def Ga.ar(ga: Ga) -> O.Arena:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: ar

def Ga.n(ga: Ga) -> U32:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: n

def Ga.s(ga: Ga) -> String:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: s

def Ga.ps(ga: Ga) -> List<&2, U32>:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: ps

def Ga.w(ga: Ga, k: Nat) -> U32:
  match ga:
    case Ga{ar, n, s, ps, +w, z, o}: nth(w, k)

def Ga.z(ga: Ga) -> U32:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: z

def Ga.o(ga: Ga) -> U32:
  match ga:
    case Ga{ar, n, s, ps, w, z, o}: o

def Ga.bare(ga: Ga, ar: O.Arena, n: U32, s: String) -> Ga:
  match ga:
    case Ga{a, _, t, ps, w, z, o}: Ga{ar, n, s, ps, w, z, o}

def Ga.mark(ga: Ga) -> Ga:
  match ga:
    case Ga{+ar, n, s, ps, w, z, o}:
      +k = O.Arena.next(ar)
      Ga{ar, k, s, ps, w, z, o}

def Ga.acc(ga: Ga, ar: O.Arena, n: U32, s: String) -> Ga:
  match ga:
    case Ga{a, _, t, ps, w, z, o}: Ga{ar, n, String.concat([t, s]), ps, w, z, o}

# ---- the four rows, appended to the text
#
# `<nm>=` the answer's TREE two levels deep, `<nm>n=` the SLOTS MINTED (the
# window, so this is the interning row), `<nm>sig=` the answer's CONE in pre-order
# and `<nm>k=` its CONSTS. A tinygrad refusal names dtype.py's exception
# (`NotImplementedError`, dtype.py:81). An arm this file does not build names
# `unported` instead — the same string would be a false statement about tinygrad.

# dtype.py:81, `case _: raise NotImplementedError`. This string is ONLY that raise.
# An arm the port does not build is `dd_gap` (`unported`), never this name: printing
# `NotImplementedError` for it would be a statement about tinygrad that is false.
def dd_ref(ar: O.Arena, from: U32, to: U32, +nm: String) -> String:
  String.concat([nm, "=refused:", "NotImplementedError", "\n", nm, "n=", U32.show(U32.sub(to, from)), "\n"])

def dd_gap(ar: O.Arena, from: U32, to: U32, +nm: String) -> String:
  String.concat([nm, "=refused:", "unported", "\n", nm, "n=", U32.show(U32.sub(to, from)), "\n"])

def rows.body(+nm: String, ok: Bool, +u: U32, +ar: O.Arena, +from: U32, +to: U32) -> String:
  match ok:
    case True{}:
      +f = dd_fuel(ar)
      +c = dd_cone(f, ar, [u])
      String.concat([nm, "=", dd_tree(ar, u), "\n", nm, "n=", U32.show(U32.sub(to, from)),
                     "\n", nm, "sig=", dd_esig(ar, f, c, True{}, ""),
                     "\n", nm, "k=", dd_eck(ar, f, c, True{}, ""), "\n"])
    case False{}: dd_ref(ar, from, to, nm)

def rows.put(+nm: String, ok: Bool, u: U32, +ar: O.Arena, +from: U32) -> String:
  rows.body(nm, ok, u, ar, from, O.Arena.next(ar))


# ===========================================================================
# THE FIXTURES. `.agents/slop/dd-oracle.py` builds `WORD` then `WPOOL` at MODULE
# level, before any measurement, so their nodes are interned before the first
# row and a later row that wants the same word finds it already there. The pool
# is ONE list of TWENTY: five `i32`, five `u32`, five `bool`, five `f32`, in that
# order, so a fixture is a base offset and a word count.
#
# `xdt` is `uops[0].dtype`. CPython reads it off the node and the port is HANDED
# it, because `ops.bend`'s arena has no dtype field -- that is the whole reason
# `l2i` takes five arguments and not four.
# ===========================================================================

def dd_par(+ar: O.Arena, +nm: String, +dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{O.ParamArg{0, dt, Some{0},
    Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(0)}}, Some{1}, Some{nm}, S.Aalu{}, None{},
    False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

def dd_pool.go(n: Nat, +ar: O.Arena, +nm: String, +dt: S.Dt, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      +k = U32.from_nat(List.length(&2, U32, acc))
      +nm2 = String.concat([nm, U32.show(k)])
      +f = dd_par(ar, nm2, dt)
      dd_pool.go(p, O.Found.ar(f), nm, dt, List.append(&2, U32, acc, [O.Found.i(f)]))

def dd_pool5(+ar: O.Arena, +nm: String, +dt: S.Dt) -> List<&2, U32>:
  dd_pool.go(5n, ar, nm, dt, Nil{})

# `WORD`: one word per `f2f_dt` VALUE, so u8 stands for all four fp8 layouts.
def dd_words(+ar: O.Arena) -> List<&2, U32>:
  +a = dd_par(ar, "w", S.uint8())
  +b = dd_par(O.Found.ar(a), "w", S.uint16())
  +c = dd_par(O.Found.ar(b), "w", S.uint32())
  +d = dd_par(O.Found.ar(c), "w", S.uint64())
  [O.Found.i(a), O.Found.i(b), O.Found.i(c), O.Found.i(d)]

# `WORD` then `WPOOL`, in the oracle's MODULE order, threaded through one arena.
# ONE list of TWENTY-FOUR: four `w` words (u8, u16, u32, u64) and then five each
# of `i32`, `u32`, `bool`, `f32`, so a fixture is an INDEX and the whole fixture
# set is one walk.

type Nd is Data:
  Nd{ar: O.Arena, ns: List<&2, U32>}

def Nd.ar(nd: Nd) -> O.Arena:
  match nd:
    case Nd{ar, ns}: ar

def Nd.ns(nd: Nd) -> List<&2, U32>:
  match nd:
    case Nd{ar, ns}: ns

def dd_wpool.slot(k: U32) -> U32:
  U32.div(U32.sub(k, 4), 5)

def dd_wpool.words1(k: U32) -> S.Dt:
  match k:
    case 0: S.uint8()
    case 1: S.uint16()
    case 2: S.uint32()
    case _: S.uint64()

def dd_wpool.pool1(slot: U32) -> S.Dt:
  match slot:
    case 0: S.int32()
    case 1: S.uint32()
    case 2: S.boolean()
    case _: S.single()

def dd_wpool.pname(slot: U32) -> String:
  match slot:
    case 0: "i32"
    case 1: "u32"
    case 2: "bool"
    case _: "f32"

# The 24-WORD WALK. bend will not scrutinise a computed value, not even a call,
# so the two discriminating Booleans are PARAMETERS and the caller decides --
# and because `p` shrinks at position two, the self-call is the legal shape.
def dd_wpool.isw(k: U32) -> Bool:
  U32.is_lt(k, 4)

def dd_wpool.name(slot: U32, k: U32) -> String:
  String.concat([dd_wpool.pname(slot), U32.show(U32.mod(U32.sub(k, 4), 5))])

def dd_wpool.node(+ar: O.Arena, isw: Bool, +slot: U32, +k: U32) -> O.Found:
  match isw:
    case True{}: dd_par(ar, "w", dd_wpool.words1(k))
    case False{}: dd_par(ar, dd_wpool.name(slot, k), dd_wpool.pool1(slot))

def dd_wpool.go(n: Nat, +ar: O.Arena, +ns: List<&2, U32>, isw: Bool, +slot: U32, +k: U32) -> Nd:
  match n:
    case 0n: Nd{ar, ns}
    case 1n+p:
      +k2 = U32.add(k, 1)
      +f = dd_wpool.node(ar, isw, slot, k)
      dd_wpool.go(p, O.Found.ar(f), List.append(&2, U32, ns, [O.Found.i(f)]),
                  dd_wpool.isw(k2), dd_wpool.slot(k2), k2)

def dd_wpool.step(n: Nat, +ar: O.Arena, +ns: List<&2, U32>, +slot: U32, +k: U32) -> Nd:
  dd_wpool.go(n, ar, ns, U32.is_lt(k, 4), slot, k)

# `Ga.ps` is the POOL (offset 4) and `Ga.w` is the four words; both are INDICES
# into the same list, and an index minted before the first fixture is still the
# same node after the last one because the arena is append-only.
def Ga.pool(ga: Ga, k: Nat) -> U32:
  match ga:
    case Ga{+ar, n, s, +ps, +w, z, o}: nth(w, k)

def Ga.word(ga: Ga, k: Nat) -> U32:
  Ga.pool(ga, k)

# ===========================================================================
# THE ROWS. One def per fixture family, each a PURE fold over the text.
# ===========================================================================

def dd_dtb.nm(k: S.Dt) -> String:
  match k:
    case S.Dt{pri, bits, cls, +nm}: nm

def dd_dtb.maybe(key: S.Dt, d: Maybe<&2, S.Dt>) -> String:
  match d:
    case Some{+t}: String.concat([dd_dtb.nm(key), "->", dd_dtb.nm(t)])
    case None{}: "none"

def dd_dtb.to(key: S.Dt, m: Maybe<&2, S.Dt>) -> String:
  dd_dtb.maybe(key, m)

# `l2i_dt` and `f2f_dt` as `a->b` and the refusal as `none`: the TARGET is the
# dtype and the NAME is the load, so these are the two rows that make a rename of
# `dtypes.long` visible rather than silent.

def dd_l2i.row(nm: String, +k: S.Dt) -> String:
  String.concat([nm, "=", dd_dtb.to(k, l2i_dt(k)), "\n"])

def dd_f2f.row(nm: String, +k: S.Dt) -> String:
  String.concat([nm, "=", dd_dtb.to(k, f2f_dt(k)), "\n"])

# THE HEAD ROWS, and they are SEEDED rather than appended: `l2idt*` and `f2fdt*`
# were both written and both DEAD -- nothing called `dd_text.head`, so the "121
# rows" the first report counted were 121 `lg*` rows and the two dtype tables had
# NO row at all. `f2fdt8` is the NEGATIVE case: `f2f_dt` is keyed on
# `dtypes.floats`, so an integer key is `none`.
def dd_text.head() -> String:
  String.concat([dd_l2i.row("l2idt0", S.int64()), dd_l2i.row("l2idt1", S.uint64()),
    dd_f2f.row("f2fdt0", S.fp8e4m3()), dd_f2f.row("f2fdt1", S.fp8e5m2()),
    dd_f2f.row("f2fdt2", S.fp8e4m3fnuz()), dd_f2f.row("f2fdt3", S.fp8e5m2fnuz()),
    dd_f2f.row("f2fdt4", S.half()), dd_f2f.row("f2fdt5", S.bfloat16()),
    dd_f2f.row("f2fdt6", S.single()), dd_f2f.row("f2fdt7", S.double()),
    dd_f2f.row("f2fdt8", S.int32()), "# l2i\n"])

def fixtures.put(+ar: O.Arena, +ns: List<&2, U32>) -> Ga:
  Ga{ar, O.Arena.next(ar), dd_text.head(), ns, ns, 0, 0}

def fixtures.nd(nd: Nd) -> Ga:
  match nd:
    case Nd{+ar, +ns}: fixtures.put(ar, ns)

def fixtures() -> Ga:
  fixtures.nd(dd_wpool.step(24n, O.Arena.empty(), Nil{}, 0, 0))


# ---- the `l2i` rows
#
# `l2i`'s ONE tinygrad refusal is `case _: raise NotImplementedError` (dtype.py:81),
# a PURE test on the op, asked BEFORE the call. `l2i` returning `None` is a
# different fact: the float-target CAST arm (dtype.py:35-38) is not built, and
# CPython accepts that call. It prints `unported`, not `NotImplementedError`.

def dd_l2i_ok(op: O.Op) -> Bool:
  match op:
    case O.OpsNEG{}: True{}
    case O.OpsCAST{}: True{}
    case O.OpsBITCAST{}: True{}
    case O.OpsSHL{}: True{}
    case O.OpsSHR{}: True{}
    case O.OpsADD{}: True{}
    case O.OpsSUB{}: True{}
    case O.OpsMUL{}: True{}
    case O.OpsCMPLT{}: True{}
    case O.OpsCMPEQ{}: True{}
    case O.OpsCMPNE{}: True{}
    case O.OpsXOR{}: True{}
    case O.OpsOR{}: True{}
    case O.OpsAND{}: True{}
    case O.OpsWHERE{}: True{}
    case O.OpsMAX{}: True{}
    case O.OpsCDIV{}: True{}
    case O.OpsCMOD{}: True{}
    case _: False{}

def dd_ws.go(n: Nat, +k: U32, +ps: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: dd_ws.go(p, U32.add(k, 1), ps, List.append(&2, U32, acc, [nth(ps, U32.to_nat(k))]))

# the first `nw` pool words from `base`; the oracle's `ws(xdt, n)`.
def dd_ws(ga: Ga, base: Nat, nw: U32) -> List<&2, U32>:
  match ga:
    case Ga{+ar, n, s, +ps, +w, z, o}: dd_ws.go(U32.to_nat(nw), U32.from_nat(base), ps, Nil{})

# `hi == 0` IS "ONE NODE": four of dtype.py's seventeen arms answer a single UOp
# (`Ops.CAST`'s `else` at :39, CMPLT, CMPEQ and CMPNE), which is why the `<nm>p`
# row exists only for the arms that answer two, and why the CONE is rooted at
# `lo` alone for them.
def l2i.ph(+nm: String, two: Bool, hi: U32, +ar: O.Arena) -> String:
  match two:
    case True{}: String.concat([nm, "p=", dd_tree(ar, hi), "\n"])
    case False{}: ""

def l2i.roots(two: Bool, lo: U32, hi: U32) -> List<&2, U32>:
  match two:
    case True{}: [lo, hi]
    case False{}: [lo]

def l2i.put(+nm: String, +two: Bool, +lo: U32, +hi: U32, +ar: O.Arena, +from: U32, +to: U32) -> String:
  +f = dd_fuel(ar)
  +a = String.concat([nm, "=", dd_tree(ar, lo), "\n"])
  +b = l2i.ph(nm, two, hi, ar)
  +c = String.concat([nm, "n=", U32.show(U32.sub(to, from)), "\n"])
  +g = dd_cone(f, ar, l2i.roots(two, lo, hi))
  +d = String.concat([nm, "sig=", dd_esig(ar, f, g, True{}, ""), "\n"])
  +e = String.concat([nm, "k=", dd_eck(ar, f, g, True{}, ""), "\n"])
  String.concat([a, b, c, d, e])

def l2i.put.put2(+nm: String, two: Bool, lo: U32, hi: U32, +ar: O.Arena, +from: U32) -> String:
  l2i.put(nm, two, lo, hi, ar, from, O.Arena.next(ar))

def l2i.gone(nm: String, +ga: Ga) -> Ga:
  match ga:
    case Ga{+ar, +n, +s, +ps, +w, z, o}: Ga{ar, n, String.concat([s, rows.put(nm, False{}, 0, ar, n)]), ps, w, z, o}

# `l2i` returned `None`. Not dtype.py:81. The float-target CAST arm is the only
# current producer; CPython returns a node there (dtype.py:35-38).
def l2i.gap(nm: String, +ga: Ga) -> Ga:
  match ga:
    case Ga{+ar, +n, +s, +ps, +w, z, o}:
      Ga{ar, n, String.concat([s, dd_gap(ar, n, O.Arena.next(ar), nm)]), ps, w, z, o}

def l2i.put3(+nm: String, two: Bool, lo: U32, hi: U32, ar: O.Arena, from: U32, +t: String) -> String:
  String.concat([t, l2i.put.put2(nm, two, lo, hi, ar, from)])

def l2i.two(nm: String, w: W2, +ga: Ga, from: U32) -> Ga:
  match w:
    case W2{+ar, +lo, +hi}:
      match ga:
        case Ga{a, +n, +t, +ps, +w2, z, o}:
          +k = O.Arena.next(ar)
          Ga{ar, k, l2i.put3(nm, U32.is_ne(hi, 0), lo, hi, ar, from, t), ps, w2, z, o}

def l2i.got(nm: String, r: Maybe<&2, W2>, +ga: Ga, from: U32) -> Ga:
  match r:
    case Some{w}: l2i.two(nm, w, ga, from)
    case None{}: l2i.gap(nm, ga)

def l2i.went(nm: String, ok: Bool, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32, +ga: Ga) -> Ga:
  match ok:
    case True{}:
      +from = Ga.n(ga)
      +ws = dd_ws(ga, base, nw)
      l2i.got(nm, l2i(Ga.ar(ga), op, dt, xdt, ws), ga, from)
    case False{}: l2i.gone(nm, ga)

def l2i.one(nm: String, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32, +ga: Ga) -> Ga:
  l2i.went(nm, dd_l2i_ok(op), op, dt, xdt, base, nw, ga)

# `l2i(Ops.CAST, dt, UOp.const(v, xdt))`. The const is minted BEFORE the window,
# which is what the oracle does: the argument exists before `l2i` is called, and
# `n=` counts only what the call interns. dtype.py:28-32. `long` is `dtypes.i64`
# (tinygrad/dtype.py:142); the pair is `(lo, hi)`.
def l2i.const.put(+nm: String, +dt: S.Dt, +xdt: S.Dt, +c: O.Found, +ga: Ga) -> Ga:
  match c:
    case O.Found{+ar, +i}:
      +from = O.Arena.next(ar)
      l2i.got(nm, l2i(ar, O.OpsCAST{}, dt, xdt, [i]), ga, from)

def l2i.const(+nm: String, +v: U32, +dt: S.Dt, +xdt: S.Dt, +ga: Ga) -> Ga:
  l2i.const.put(nm, dt, xdt, dd_const.int(Ga.ar(ga), H.i64_of_i32(v), xdt), ga)

# THE `l2i` TABLE, index 0..31, in the oracle's order. `base` is the POOL OFFSET
# into the TWENTY-FOUR word list -- four `w` words then five `i32` at 4, five
# `u32` at 9, five `bool` at 14, five `f32` at 19 -- and `nw` the word count. The arms are one per row so a fixture added in the
# wrong place moves a row instead of silently shortening the table.
def l2i.pick(+i: U32, +ga: Ga) -> Ga:
  match i:
    case 0: l2i.one("lg1", O.OpsNEG{}, S.int32(), S.uint32(), 9n, 2, ga)
    case 1: l2i.one("lg2", O.OpsCAST{}, S.int64(), S.int32(), 4n, 2, ga)
    case 2: l2i.one("lg3", O.OpsCAST{}, S.int64(), S.uint32(), 9n, 2, ga)
    case 3: l2i.one("lg4", O.OpsCAST{}, S.int64(), S.boolean(), 14n, 2, ga)
    case 4: l2i.one("lg5", O.OpsCAST{}, S.int64(), S.single(), 19n, 2, ga)
    case 5: l2i.one("lg6", O.OpsCAST{}, S.uint64(), S.int32(), 4n, 2, ga)
    case 6: l2i.one("lg7", O.OpsCAST{}, S.int32(), S.uint32(), 9n, 2, ga)
    case 7: l2i.one("lg8", O.OpsBITCAST{}, S.int64(), S.uint32(), 9n, 2, ga)
    case 8: l2i.one("lg9", O.OpsSHL{}, S.int32(), S.uint32(), 9n, 3, ga)
    case 9: l2i.one("lga", O.OpsSHR{}, S.int32(), S.uint32(), 9n, 3, ga)
    case 10: l2i.one("lgb", O.OpsSHR{}, S.uint32(), S.uint32(), 9n, 3, ga)
    case 11: l2i.one("lgc", O.OpsADD{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 12: l2i.one("lgd", O.OpsSUB{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 13: l2i.one("lge", O.OpsMUL{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 14: l2i.one("lgf", O.OpsCMPLT{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 15: l2i.one("lgg", O.OpsCMPEQ{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 16: l2i.one("lgh", O.OpsCMPNE{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 17: l2i.one("lgi", O.OpsXOR{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 18: l2i.one("lgj", O.OpsOR{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 19: l2i.one("lgk", O.OpsAND{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 20: l2i.one("lgl", O.OpsWHERE{}, S.int32(), S.uint32(), 9n, 5, ga)
    case 21: l2i.one("lgm", O.OpsMAX{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 22: l2i.one("lgn", O.OpsFLOORDIV{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 23: l2i.one("lgo", O.OpsCAST{}, S.int64(), S.uint32(), 9n, 1, ga)
    case 24: l2i.one("lgq", O.OpsCDIV{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 25: l2i.one("lgr", O.OpsCMOD{}, S.int32(), S.uint32(), 9n, 4, ga)
    case 26: l2i.one("lgs", O.OpsCDIV{}, S.uint32(), S.uint32(), 9n, 4, ga)
    case 27: l2i.one("lgt", O.OpsCMOD{}, S.uint32(), S.uint32(), 9n, 4, ga)
    # dtype.py:28-32, source not a float, unsigned: zero-extend. CPython:
    # `(CAST(CAST(C(0))), CAST(C(0)))`. NOT the note's `(CAST(C(0)), CAST(C(0)))`.
    case 28: l2i.const("lgv", 0, S.int64(), S.uint32(), ga)
    # dtype.py:31 and mixin/dtype.py:36. `l2i_dt[ulong]` is `uint`, so the cast
    # FOLDS and both words are the source const. The note attributed this tree
    # to `long`. Words are equal; `lgx` is the order-sensitive neighbour.
    case 29: l2i.const("lgw", 0, S.uint64(), S.uint32(), ga)
    case 30: l2i.const("lgx", 1, S.uint64(), S.uint32(), ga)
    # dtype.py:35-38. CPython returns one node,
    # `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))`, and does not raise. This arm is
    # not built (header C). `unported`, not `NotImplementedError`.
    case 31: l2i.one("lgu", O.OpsCAST{}, S.single(), S.single(), 19n, 2, ga)
    # dtype.py:39, `case Ops.CAST: return a0.bitcast(dtypes.uint).cast(dt)`, on a
    # source whose bitcast does NOT FOLD.  `lg7` is the same arm and `lg7=CAST(Pu320)`
    # -- no BITCAST -- because `bitcast` folds when the dtypes already agree
    # (`mixin/dtype.py:53`), and `lg7` is its only fixture, so the node this arm
    # EXISTS to build was in no row at all.  `l2i_cast3.bitc`'s False arm is live
    # code with zero coverage: `dd-mut-proof.py` REFUSES to rename it (bend names
    # the missing def), so M05's zero is INVISIBILITY and not unreachability.
    # Two words because dtype.py:39 reads `a0`, which `l2i` binds only at
    # `len(uops) >= 2` (dtype.py:23) -- one word is `UnboundLocalError`, measured.
    # CPython, `.agents/slop/dd-mut-fixtures.py lgy`:
    #   lgy=CAST(BITCAST(Pi320))  lgyn=0  lgysig=CAST/1,BITCAST/1,PARAM/0  lgyk=-
    case 32: l2i.one("lgy", O.OpsCAST{}, S.int32(), S.int32(), 4n, 2, ga)
    case _: l2i.one("lgt", O.OpsCMOD{}, S.uint32(), S.uint32(), 9n, 4, ga)

def l2i.rows(n: Nat, +i: U32, +ga: Ga) -> Ga:
  match n:
    case 0n: ga
    case 1n+p:
      +g2 = l2i.pick(i, ga)
      l2i.rows(p, U32.add(i, 1), g2)

# ---- `unpack32` (dtype.py:13) over `WPOOL[u32][0]`, the pool word at 9. It is
# the only two-root fixture outside `l2i`, and it is what shows `unpack32` builds
# the BITCAST ONCE for both halves -- `u.bitcast(uint) & 0xFFFF` and
# `shr(u.bitcast(uint), 16)` share it, so the cone has one BITCAST and not two.

def unpack.one(nm: String, +ga: Ga) -> Ga:
  +from = Ga.n(ga)
  l2i.two(nm, unpack32(Ga.ar(ga), Ga.pool(ga, 9n), S.uint32()), ga, from)

# ---- `hi42`: the `hi` of `dtype.py:42` AS THE ANSWER of a fixture
#
# `((a1u << n) | ((a0u >> 1) >> (31 - n))).bitcast(dt)` is a SUB-EXPRESSION of
# dtype.py's SHL arm, and `l2i` gives it back only as the `y` of
# `(b0 >= 32).where(lo, hi)` -- `dd_where` is a three-src WHERE -- so it is two
# levels under the answer. `dd_tree` prints TWO levels (`dd_sfx2.put` calls
# `dd_sh1`, `dd_sfx1.put` calls the bare `dd_lab`), which is why `lg9p` reads
# `BITCAST(OR)`: the ORDER of that `|` is in no `lg9` row except `lg9sig`, and
# only because the cone walk happens to read src[0] before src[1].  An instance of
# that swap reached origin/master with 147 rows green, so the order wants a row
# that READS it.  Rooting the cone AT the `|` puts it at the answer's root, where
# `OR(SHL(...),SHR(...))` and `OR(SHR(...),SHL(...))` are different strings.
#
# `dt` is `uint32` and NOT `int32`, and that is load-bearing: `.bitcast(dt)` FOLDS
# only when the dtypes already agree (`mixin/dtype.py:53`), so at `uint32` `hi`
# IS the `|` and both lanes reach it at ONE address -- CPython's `r1.src[2]`,
# here `O.Arena.src(ar, r1, 2)` -- while at `int32` the node at that address is a
# BITCAST and the answer row would be `BITCAST(OR(...))` again.
#
# `xdt` is `int32` and not `lg9`'s `uint32`: with a `u32` source `a0u`/`a1u` fold
# to bare PARAMs, and with an `i32` source each half of the `|` carries its own
# BITCAST, so this fixture also reaches `dd_bcast`'s and `dd_cast_fold`'s False
# arms INSIDE the SHL arm -- neither of which `lg9` reaches.
#
# `n = b0 & 31` puts the shift amount in `0..31` for EVERY input, which is this
# arm's precondition rather than a choice, and the two halves are a `SHL` and a
# `SHR`, so no input makes them coincide.  `W2{ar, o, 0}` is this gate's own
# idiom for "the answer is ONE node": `l2i.two` reads `hi == 0` as such, so
# `l2i.ph` prints nothing and `l2i.roots` roots the cone at `lo` alone.
# CPython, `.agents/slop/dd-mut-m09.py`:  hi42=OR(SHL(BITCAST,CAST),SHR(SHR,ADD))
#   hi42n=22  hi42k=C(31),C(1),C(-1)  and hi.src[0] IS `a1u << n`.
# The `match` is on a PARAMETER and not on the `l2i(...)` call, because bend will
# not scrutinise a computed value -- the same seam as `l2i.got` under `l2i.went`,
# and for the same reason it comes FIRST: a def must be filled before it is used.
def l2i.hi.put(nm: String, r: Maybe<&2, W2>, +ga: Ga, from: U32) -> Ga:
  match r:
    case Some{W2{+ar, +lo, +hi}}: l2i.two(nm, W2{ar, O.Arena.src(ar, hi, 2), 0}, ga, from)
    case None{}: l2i.gap(nm, ga)

def l2i.hi42(nm: String, +ga: Ga) -> Ga:
  +from = Ga.n(ga)
  +ws = dd_ws(ga, 4n, 3)
  l2i.hi.put(nm, l2i(Ga.ar(ga), O.OpsSHL{}, S.uint32(), S.int32(), ws), ga, from)

# ---- the `c*` rows: `f2f_clamp`'s `mx` CONSTANT (tinygrad/codegen/decomp/dtype.py:127), as a VALUE
#
# These are the ONLY fixtures that reach `f2f_clamp_max`, and until they existed
# nothing in this file called it from the gate at all: `f2f_clamp` is the only
# caller and no `f2f`/`f2f_clamp` fixture is printed either. The def was written,
# documented as "factored out because it is a VALUE", and never exercised -- and
# it was wrong on all SEVEN dtypes it answers, in a way that cancelled on the
# two fnuz layouts.
#
# THE ORACLE'S `c{i}` ROW IS A FUNCTION OF `dt` ALONE AND CPython'S IS NOT.
# `mx` is `val.const_like(...)`, so its VALUE also depends on `fr`, and the two
# answers differ for `float64` AND ONLY THERE. Called, in
# `.agents/slop/dd-divE-probe.py`:
#
#     f2f_clamp(f32_val, float64) -> mx = inf     -> F(2139095040)
#     f2f_clamp(f64_val, float64) -> mx = 1.8e308 -> F(ovf), outside f32
#
# `c0..c6` are the same number under both, which is why the row is well posed
# for seven of the eight. `c7` prints `unported` here rather than matching the
# oracle's `F(ovf)`, which is the oracle declining to render a value, not a
# value at all -- and matching it would be a statement about tinygrad that the
# `fr = f32` call above contradicts. TODO: `c7` closes when this file has an
# `F64` or when `f2f_clamp_max` returns the `fr`-narrowed value instead of the
# bare `mx`; either way the fixture is printed, so the gap is COUNTED.

def dd_cmx.row(nm: String, m: Maybe<&2, F32>) -> String:
  match m:
    case Some{f}: String.concat([nm, "=F(", U32.show(F32.bits(f)), ")\n"])
    case None{}: String.concat([nm, "=refused:unported\n"])

def dd_cmx.put(nm: String, +dt: S.Dt, +ga: Ga) -> Ga:
  match ga:
    case Ga{+ar, +n, +s, +ps, +w, z, o}:
      Ga{ar, n, String.concat([s, dd_cmx.row(nm, f2f_clamp_max(dt))]), ps, w, z, o}

def dd_cmx.pick(i: U32, +ga: Ga) -> Ga:
  match i:
    case 0: dd_cmx.put("c0", S.fp8e4m3(), ga)
    case 1: dd_cmx.put("c1", S.fp8e4m3fnuz(), ga)
    case 2: dd_cmx.put("c2", S.fp8e5m2(), ga)
    case 3: dd_cmx.put("c3", S.fp8e5m2fnuz(), ga)
    case 4: dd_cmx.put("c4", S.half(), ga)
    case 5: dd_cmx.put("c5", S.bfloat16(), ga)
    case 6: dd_cmx.put("c6", S.single(), ga)
    case _: dd_cmx.put("c7", S.double(), ga)

def dd_cmx.rows(n: Nat, +i: U32, +ga: Ga) -> Ga:
  match n:
    case 0n: ga
    case 1n+p: dd_cmx.rows(p, U32.add(i, 1), dd_cmx.pick(i, ga))

# ===========================================================================
# THE `f2f` ROWS -- dtype.py:101-125, THE WHOLE REGION, WHICH HAD NO ROW AT ALL.
#
# Until these existed the 182-row gate reached `f2f_clamp_max` (the `c*` rows) and
# NOTHING ELSE in dtype.py's float half. `f2f`, `f2f.up`, `f2f.up.tail`, `f2f.fnuz`,
# `f2f.ocp`, `f2f.isnan`, `f2f.qnan`, `f2f.down.*`, `rne` and `f2f_narrow` were reachable
# from `main` by nothing, which is exactly why a FORWARD REFERENCE -- a node whose src is
# a LATER slot -- could sit in `f2f.up.tail` / `f2f.fnuz` / `f2f.ocp` for a whole session
# and cost nothing. `.agents/slop/dd-band-reach.py` says so, and the gate was 182 rows of
# `True` throughout.
#
# SEVEN FIXTURES, and each one is the ONLY way into a def:
#
#   q1  fp8e4m3 -> float32      widening, dtype.py:104. `f2f.up` + `f2f.sign` +
#                              `f2f.nosign` + `f2f.norm` + `f2f.qnan` + `f2f.isnan`
#                              + `f2f.up.tail` + `f2f.ocp`.
#   q2  float32 -> fp8e4m3      narrowing to an e4m3 target, dtype.py:115. `f2f_clamp`
#                              + `rne` + `f2f.down.*` + `f2f.down.m1`.
#   q3  float32 -> fp8e5m2      narrowing to a NON-e4m3 target, and the ONLY way into
#                              `f2f.down.m2` (dtype.py:120's `else` arm).
#   q4  fp8e4m3fnuz -> float32  `fr in dtypes.fp8_fnuz`, dtype.py:108 -- the ONLY fixture
#                              that reaches `f2f.fnuz`, one of the three defs whose `U32`
#                              return was the forward reference.
#   q5  float32 -> fp8e5m2fnuz  `to in dtypes.fp8_fnuz`, dtype.py:123 -- the ONLY fixture
#                              that reaches `f2f.down.fnuz`.
#   q6  float16 -> bfloat16     dtype.py:125 `else: raise NotImplementedError`. THE
#                              NEGATIVE ROW: a fixture that must FAIL. `f2f.sel2`
#                              answers 2 and `f2f.sel`'s `_` arm maps it to `None`, so the
#                              port DECLINES where CPython RAISES. Printing `unported` is
#                              the honest string: it says the port does not build the arm,
#                              and it is NOT dtype.py's exception name.
#   q7  float32 -> float64      a widening whose `mx` is an `f64` CONST -- the second arm
#                              of `f2f_clamp_max`, the subject `c7` names.
#
# CPython, `.agents/slop/f2f-fixtures.py`, run twice with the same result. NOT
# transcribed: that file calls `DD.f2f` on a live `tinygrad`.
#
# !! THE NAMES ARE `q*` AND NOT `f*`/`g*`/`h*`/`k*`, because `.agents/slop/dd-oracle.py`
# ALREADY OWNS THOSE for the SAME DEFS with DIFFERENT fixtures: its `f1` is
# `fp8e4m3 -> f32` where `q1` is, its `f2` is `fp8e4m3fnuz -> f32` where `q4` is, and
# its `g3`/`g4`/`g6`/`g7` are `q2`/`q3`/`q5`/`q7`. Two DIFFERENT fixtures sharing one
# `name=` key is a disagreement MANUFACTURED BY THE NAMING, and `dd-band-diff.py` cannot
# see it -- it compares whole `name=value` lines, so a collision reads exactly like a real
# bug. MEASURED: with `f1`/`f2` reused, the differ reported 8 disagreements of which 4
# were this collision and 0 were real. `grep -c '^q' dd-oracle.txt` is 0.
#
# !! `n=` IS THE INTERNING WINDOW (`rows.put`'s `to - from`), and CPython's is the same
# quantity -- `dd-oracle.py`'s `ORDER` hook, reinstalled in `f2f-fixtures.py`. It is NOT
# the cone size, which deduplicates shared subtrees and the window does not: `q1n` is 26
# and `q1c` is 27, and the two are separate rows for that reason.
#
# ⚠ `f2f` is `Maybe`-returning here because the port's `f2f.sel` declines rather than
# raising, so the port's answer for `x1` is `None` and CPython's is an exception. That is
# a REAL divergence and it is why `x1` names `unported` and not `NotImplementedError`.
# ===========================================================================

# `+ar` IS THE ANSWER'S ARENA and `+i` its slot: `f2f` may intern into either, and a copy
# of the arena is what makes the two disagree silently.
type Fx is Data:
  Fx{ar: O.Arena, i: U32}

def f2f.fx(r: Maybe<&2, O.Found>, +ar: O.Arena) -> Fx:
  match r:
    case Some{+f}: Fx{O.Found.ar(f), O.Found.i(f)}
    case None{}: Fx{ar, 0}

# A `match` MAY NOT BE NESTED inside a `match` arm on a consumed binder -- bend says
# `a match on a parameter or field (this name is a def or a consumed binder: give the
# value its own def)`. So the `Maybe` is dispatched in a LEAF def whose first statement is
# the match, and the accumulated text rides in as a `String` the leaf concatenates onto.
# `l2i.hi.put` is the same seam for the same reason.
def f2f.got.put(nm: String, r: Maybe<&2, O.Found>, +s: String, +ar: O.Arena, +ps: List<&2, U32>, +w: List<&2, U32>, n: U32, z: U32, o: U32, from: U32) -> Ga:
  match r:
    case Some{+f}: Ga{O.Found.ar(f), n, String.concat([s, rows.put(nm, True{}, O.Found.i(f), O.Found.ar(f), from)]), ps, w, z, o}
    case None{}: Ga{ar, n, String.concat([s, dd_gap(ar, from, O.Arena.next(ar), nm)]), ps, w, z, o}

def f2f.got(nm: String, r: Maybe<&2, O.Found>, +ga: Ga, from: U32) -> Ga:
  match ga:
    case Ga{+ar, n, +s, +ps, +w, z, o}: f2f.got.put(nm, r, s, ar, ps, w, n, z, o, from)

# ONE FIXTURE, and `+from` is read AFTER the PARAM is interned and BEFORE `f2f` is called,
# which is how `rows.put` measures a window. A fixture that interned nothing would read
# `n=0`, and that is indistinguishable from "not started" -- so every row below carries a
# non-zero `n`, and `w1n`/`n1n` are the rows that say the window is not empty.
#
# The answer's arena is `O.Found.ar(f)` and NOT the arena the call was given: `f2f` grows
# it, and the cone must be walked in the grown one. That distinction is the whole of the
# forward reference this file used to have.
#
# ⚠ THE PARAM'S DTYPE IS `f2f_dt[fr]` AND NOT `fr`, because BOTH REAL CALL SITES PASS A
# UINT: dtype.py:142 `f2f(val.bitcast(f2f_dt[to]), to, fr)` and dtype.py:196
# `f2f(x.bitcast(f2f_dt[ctx[0]]), ctx[0], ctx[1])`, with `f2f_dt[f] =
# getattr(dtypes, f"uint{f.bitsize}")` at dtype.py:97. `f2f.udt(fr)` IS that table, and
# `f2f.udt`'s fallback arm is `S.uint32()` -- which is why passing `fr` here compiled, ran,
# and disagreed: `dd_par`'s PARAM carries its dtype in the ARENA'S `Arg`, so a `float32`
# PARAM is expressible and the fold in `mixin/dtype.py:53` (`return self if self.dtype ==
# dt`) then REMOVES a BITCAST that dtype.py builds. MEASURED both ways, and the `fr`
# receiver costs `w1` a node (28 against CPython's 27).
def f2f.one(nm: String, +nmv: String, +fr: S.Dt, +to: S.Dt, +ga: Ga) -> Ga:
  match ga:
    case Ga{+ar, n, s, ps, w, z, o}:
      +p = dd_par(ar, nmv, f2f.udt(fr))
      +pa = O.Found.ar(p)
      +from = O.Arena.next(pa)
      f2f.got(nm, f2f(pa, O.Found.i(p), fr, to, True{}), Ga{pa, n, s, ps, w, z, o}, from)

def f2f.pick(i: U32, +ga: Ga) -> Ga:
  match i:
    case 0: f2f.one("q1", "q1", S.fp8e4m3(), S.single(), ga)
    case 1: f2f.one("q2", "q2", S.single(), S.fp8e4m3(), ga)
    case 2: f2f.one("q3", "q3", S.single(), S.fp8e5m2(), ga)
    case 3: f2f.one("q4", "q4", S.fp8e4m3fnuz(), S.single(), ga)
    case 4: f2f.one("q5", "q5", S.single(), S.fp8e5m2fnuz(), ga)
    case 5: f2f.one("q6", "q6", S.half(), S.bfloat16(), ga)
    case _: f2f.one("q7", "q7", S.single(), S.double(), ga)

def f2f.rows(n: Nat, +i: U32, +ga: Ga) -> Ga:
  match n:
    case 0n: ga
    case 1n+p: f2f.rows(p, U32.add(i, 1), f2f.pick(i, ga))

def gate() -> IO(Unit):
  IO.print(Ga.s(f2f.rows(7n, 0, dd_cmx.rows(8n, 0, l2i.hi42("hi42", unpack.one("up", l2i.rows(33n, 0, fixtures())))))))

def main() -> IO(Unit):
  gate()
