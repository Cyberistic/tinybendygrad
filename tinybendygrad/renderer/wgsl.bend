# wgsl.bend -- tinygrad/renderer/wgsl.py. WGSL is the WebGPU shading language,
# so this is where tinygrad-in-wasm gets its text: the same kernel UOps that
# cstyle's naming pass already named, rendered to WGSL.
#
# THE SPLIT OF WORK IN THIS FILE, and why. `wgsl.py` is two things wearing one
# coat: a GRAPH REWRITER (`wgsl_matcher`, `packed_store`, `packed_load`,
# `sign_extend`, `is_nan`) that fires on the UOp graph before rendering, and a
# STRING RENDERER (`type_map`, `code_for_op`, `string_rewrite`, `render_kernel`)
# that turns one already-named UOp into one line of WGSL. The string half is
# PORTED AND GATED HERE. The graph half is the WALL, and the wall is in
# `uop/ops.bend`, not in this file:
#
#   TODO(p3) wgsl.py:7   sign_extend  -- `.bitcast`/`.alu` CONSTRUCTOR SUGAR
#   TODO(p3) wgsl.py:15  packed_store -- ditto, plus `.load`/`.store`
#   TODO(p3) wgsl.py:24  packed_load  -- ditto, plus `.index`
#   TODO(p3) wgsl.py:35  is_nan       -- ditto (`.bitcast` and the compare)
#   TODO(p3) wgsl.py:42  wgsl_matcher -- ditto; the seven RULES return arenas,
#                                  so a rule table here would have nothing to
#                                  return but the input it was handed
#
# `ops.bend` named the sugar in its own NOT PORTED block (`UOp.cast`,
# `UOp.bitcast`, `UOp.index`, `UOp.load`, `UOp.store`, `UOp.where` were all
# `TODO(p3) ops.py:<line>`). `UOp.cast` IS NOW PORTED at `ops.bend:2880`, the
# always-builds-new shape (no identity check), gated at `gates/uop_cast-gate.py`
# 8/8 rows. The FOLD the identity check needs (`dtype_from_uop`) is the same FOLD
# the remaining four (`UOp.bitcast`, `UOp.index`, `UOp.load`, `UOp.store`) need:
# `packed_store` alone reads four different dtypes off four different nodes before
# it can name one, and the rule body has no fold context. So the graph half is
# still one substrate gap, not seven, and it is owned by ops.bend. What IS ported here is
# every CONSTANT those five defs compute, because each one reaches the emitted
# text verbatim: `pf_mask` is the `255u` in `((255u<<alu7)^4294967295u)` and
# `nan_thr` is the `nan()` test's bound. The gate below pins all of them against
# CPython.
#
# WHAT IS PORTED AND GATED, in wgsl.py's own order:
#
#   :7   sign_extend    the shift only (se_shift) -- the graph is the wall
#   :10  packed_field   elems / width / mask, all three
#   :15  packed_store   wmask, the one integer it computes
#   :23  packed_load    the wall
#   :30  is_packed      PORTED, and it is load-bearing: it is what makes a
#                       buffer `array<atomic<u32>>` and a load `atomicLoad(&x)`
#   :33  _packed_size   PORTED
#   :34  is_nan         bitsize / exp / mant / the two masks
#   :39  packed_rmw     PORTED as a predicate -- it is the guard half of the
#                       packed store's string rule, which IS ported
#   :41  wgsl_matcher   the seven GUARDS ported, the seven rewrites walled
#   :53  WGSLRenderer   every attribute and every method below
#   :65  string_rewrite ALL SEVENTEEN RULES' STRINGS AND THEIR SEVENTEEN `UPat`s,
#                       in Python's order. This was the largest wall in the file
#                       and it was not a big one: `ctx[x]` is `self.r[x]`, a dict
#                       the naming pass has already filled, so `ctx[x]` is the
#                       CHILD'S TEXT and a parameter here. The PATTERNS were the
#                       second wall and they were SMALLER: a `UPat` reads an op, a
#                       dtype, a src count and src[0]'s op and dtype off a node,
#                       so each rule took the two or three of those its own
#                       pattern constrains and answers `NOMATCH` otherwise.
#                       MEASURED: `patterns[:17]` are these and `patterns[17:]`
#                       is `base_rewrite`'s 33, and the gate's `rules_hold()`
#                       re-derives both numbers and each rule's op and dtypes
#                       from CPython on every run. `sr_pick_bitcast`,
#                       `sr_pick_load` and `sr_pick_store` are the TABLE's order,
#                       which is a fact about no single rule's body, and they are
#                       what the three `sr pick` rows print.
#
# `code_for_op`'s TWENTY-INHERITED entries are cstyle.py:142-150, not wgsl.py:
# wgsl.py:60 only overrides WHERE. They are spelled out here anyway, because the
# `{**CStyleLanguage.code_for_op, ...}` merge needs a base class this port does
# not have yet (renderer/cstyle.bend is a stub) and a gate row cannot cite a
# table it cannot call. This is the ONE duplication in the file and it is a
# merge point: when cstyle.bend lands, twenty of `code_for_op`'s twenty-two
# arms move to `C.code_for_op` and the WGSL override becomes the only arm here.
#
# TWO MEASURED SUBSTRATE GAPS this file rides over, both inherited from
# uop/render.bend and both stated there at greater length:
#
#   (a) F32 REPR. `F32.show(3.0)` is "3" and CPython's `repr(3.0)` is "3.0".
#       Nothing in the WGSL surface needs a float CONST's text -- base_rewrite's
#       const rules live in cstyle.bend and render `f"{c.val}f"`, which is
#       `String.append` on the same F32 -- so this file only needs the CONST
#       RANGE check `math.isfinite`, and that is `nan_thr`'s neighbourhood
#       rather than a formatter. No `f32_repr` is ported because no def here
#       calls one.
#   (b) ParamArg's addrspace. Python's is `AddrSpace|None` and a `None` prints
#       as `addrspace=None`; ops.bend:697 spells it `S.Addr` with no None arm, so
#       a port that printed it would print a space where Python prints `None`.
#       render.bend:341-343 measured and recorded this. HERE it costs nothing:
#       `is_packed` reads `buf_uop.addrspace != AddrSpace.REG` and
#       `render_kernel` reads `== GLOBAL`, and both are comparisons, not
#       renderings. A PARAM with no addrspace in Python therefore has no
#       spelling in this file at all.
#
# THE GATE. `main` prints one row per claim and every row is a STRING, never a
# boolean about a string: `String.concat` hides a dropped literal, so a row that
# said "the prologue is right" would survive losing a semicolon. The `py=` half
# of each row is CPython's value, and the two lanes print the SAME LINE, so the
# diff of the two lanes is empty iff every claim holds.
#
#   .venv/bin/python gates/wgsl_render_census-gate.py
#
# THE `py=` COLUMN'S GENERATOR IS THE ORACLE, and it always was in substance --
# `.agents/slop/wgsl-oracle.py` was a helper, not the contract. FIVE of the
# halves it wrote were STALE, because this `tinygrad/`'s `DType.name` moved to
# the rust spellings after they were measured; the port's own values were right
# on all five and the NOTES were wrong. `gates/wgsl_render_census-oracle.py` is
# the generator now, it is IN GIT, and `selfcheck_hold()` re-derives the stale
# set on every run so a sixth cannot rot unnoticed.
#
# THE MUTATION TABLE is at the foot of the file, measured the same way.

import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H

# ===========================================================================
# :7  sign_extend -- `(val << (32-width)).bitcast(dtypes.i32) >> (32-width)`.
#
# The GRAPH is the wall above. The SHIFT is not, and it reaches the text: the
# packed-char load renders as `bitcast<i32>((((val4>>alu7)&255u)<<24u))>>24u)`
# and 24 is exactly this number for width 8. So the one integer is ported and
# pinned, and the three UOp calls around it are named.
# ===========================================================================
def se_shift(width: U32) -> U32: U32.sub(32, width)

# ===========================================================================
# :10  packed_field -- `elems, width = 4//dt.itemsize, 8*dt.itemsize` and the
# caller's `(1 << width)-1`. Three ints, all three in the output.
# ===========================================================================
def pf_elems(+dt: S.Dt) -> U32: U32.div(4, S.Dt.itemsize(dt))

def pf_width(+dt: S.Dt) -> U32: U32.mul(8, S.Dt.itemsize(dt))

def pf_mask(+dt: S.Dt) -> U32: U32.sub(U32.shln(1, U32.to_nat(pf_width(dt))), 1)

# ===========================================================================
# :15  packed_store -- `wmask = ((mask << shift_am) ^ 0xFFFFFFFF)`.
#
# `shift_am` is a UOp in Python, so this is a graph expression there and the
# string `((255u<<alu7)^4294967295u)` is what base_rewrite's SHL and XOR arms
# make of it. With a CONSTANT shift it collapses to an integer, and those are
# the values a folded kernel stores (`atomicAnd(&data0_4[0],4294967040u)` for
# shift 0). So the int is ported; the UOp form is the wall above.
# ===========================================================================
def ps_wmask(mask: U32, shift: U32) -> U32: U32.xor(U32.shln(mask, U32.to_nat(shift)), 4294967295)

# ===========================================================================
# :30  is_packed -- `dt.itemsize < 4 and dt != dtypes.f16 and
# x.buf_uop.addrspace != AddrSpace.REG`.
#
# `dt` is src[1]'s for a STORE and `buf_uop.dtype` for everything else, so the
# UOp reader is `is_packed_of` below and the PREDICATE takes the two things the
# UOp is read for. That is the whole reduction: Python's one `x` is a UOp, this
# port's is the pair (dtype, addrspace), and nothing else about the node is read.
# ===========================================================================
def addr_is_reg(a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

# THE THIRD CLAUSE IS NEGATED, and the gate caught it inverted the first time
# this was written: ANDing `addr_is_reg` here says "packed iff the buffer is a
# REGISTER", which is the exact opposite of wgsl.py:32 and makes the whole
# packed path -- `atomic<u32>`, `atomicLoad`, the `atomicAnd`/`atomicAdd`
# read-modify-write -- dead, because no buffer a shader reads is a register. It
# typechecked, every `pf_*` and `wmask` row stayed green, and only `rk mixed`
# moved. The `is_packed` rows below exist because of that, and they are the
# fixture class this file was MISSING: a predicate with no row is a predicate no
# mutation can find.
def is_packed(+dt: S.Dt, addr: S.Addr) -> Bool:
  Bool.and(Bool.and(U32.is_lt(S.Dt.itemsize(dt), 4), Bool.not(O.eq_dt(dt, S.half()))), Bool.not(addr_is_reg(addr)))

# `buf_uop` -- ops.py:925. The while loop, as a fuel fold: `schedule/__init__.bend`
# measured this exact shape (`sc_buf_uop`), and the mutation that dropping
# STAGE|MSTACK from the stop set moves two rows THERE, so the stop set is the
# five ops ops.py:926-931 stops at and not the three a first reading suggests.
def bu_stop(+op: O.Op) -> Bool:
  match op:
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case O.OpsPARAM{}: True{}
    case O.OpsSTAGE{}: True{}
    case O.OpsMSTACK{}: True{}
    case _: False{}

def bu_go2(+ar: O.Arena, +x: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(O.Arena.nsrc(ar, x))), Bool.not(bu_stop(O.Arena.op(ar, x))))

def bu_go(fuel: Nat, go: Bool, +ar: O.Arena, +s: U32) -> U32:
  match fuel:
    case 0n   : s
    case 1n+f :
      match go:
        case True{} : bu_go(f, bu_go2(ar, O.Arena.src0(ar, s)), ar, O.Arena.src0(ar, s))
        case False{}: s

def w_buf_uop(+ar: O.Arena, +s: U32) -> U32: bu_go(O.Arena.budget(ar), bu_go2(ar, s), ar, s)

# ===========================================================================
# :33  _packed_size -- `ceildiv(u.max_numel(), 4//u.dtype.itemsize) if
# is_packed(u) else u.max_numel()`. `max_numel` is a PARAMETER here for the
# reason `is_packed`'s is: it is read off the UOp, and `Buf` is the projection
# of a UOp this file needs. `w_numel` below is the reader.
# ===========================================================================
def packed_size(+n: U32, +dt: S.Dt, addr: S.Addr) -> U32:
  Bool.pick(U32, is_packed(dt, addr), H.ceildiv_u32(n, pf_elems(dt)), n)

# `max_numel` -- the product of the shape's dims. `F.fold.shape` answers
# `Maybe<Maybe<List<Sint>>>`, and a `Data` record cannot hold a `Maybe`, so the
# two layers are unwrapped one def at a time and the product is a fold over the
# `SI` arm. A `SU` dim is a SYMBOLIC size: Python's `prod` over a symbolic dim
# is the dim's UOp, which no integer here can be, and the wall is recorded
# rather than approximated.
def nm_sh2(m: Maybe<&2, List<&2, O.Sint>>) -> List<&2, O.Sint>:
  match m:
    case Some{x}: x
    case None{}: Nil{}

def nm_sh(+m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> List<&2, O.Sint>:
  match m:
    case Some{x}: nm_sh2(x)
    case None{}: Nil{}

def nm_one(s: O.Sint) -> U32:
  match s:
    case O.SI{i}: H.lo32(i)
    case O.SU{u}: 0

def w_numel(+ar: O.Arena, +tb: F.Table, +u: U32) -> U32:
  List.foldl(~&2, ~O.Sint, ~U32, (acc: U32) => (h: O.Sint) => U32.mul(acc, nm_one(h)), nm_sh(F.fold.shape(ar, tb, u)), 1)

# `dt` and `addr` of a node, the two reads `is_packed_of` needs.
def w_dt(+ar: O.Arena, +tb: F.Table, +u: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(ar, tb, u), S.void())

# `F.fold.addr` is a Maybe of a Maybe: the outer is "was this node answered",
# the inner is the fold's own "I do not know this addrspace". Both answer REG,
# which is ops.py:913's `return AddrSpace.REG` default -- and it is the SAFE
# default for `is_packed` because a REG buffer is never packed.
def w_addr.of(m: Maybe<&2, Maybe<&2, S.Addr>>) -> S.Addr:
  match m:
    case Some{x}:
      match x:
        case Some{a}: a
        case None{}: S.AReg{}
    case None{}: S.AReg{}

def w_addr(+ar: O.Arena, +tb: F.Table, +u: U32) -> S.Addr: w_addr.of(F.fold.addr(ar, tb, u))

# `x.src[1].dtype if x.op is Ops.STORE else x.buf_uop.dtype` -- the ONE line of
# `is_packed` that reads the node, and the reason the predicate is a pair.
def w_is_store(ar: O.Arena, u: U32) -> Bool: O.eq_op(O.Arena.op(ar, u), O.OpsSTORE{})

def w_packed_dt(+ar: O.Arena, +tb: F.Table, +u: U32) -> S.Dt:
  Bool.pick(S.Dt, w_is_store(ar, u), w_dt(ar, tb, O.Arena.src(ar, u, 1)),
    w_dt(ar, tb, w_buf_uop(ar, u)))

def is_packed_of(+ar: O.Arena, +tb: F.Table, +u: U32) -> Bool:
  is_packed(w_packed_dt(ar, tb, u), w_addr(ar, tb, w_buf_uop(ar, u)))

# ===========================================================================
# :34  is_nan -- `(a.bitcast(uint{bs}) & ((1 << (bs - 1)) - 1)) >
# (((1 << exp) - 1) << mant)`. The bitcast and the compare are the wall; the
# FIVE INTEGERS are not, and they are the whole rule: the mask is the sign bit
# cleared and the threshold is the largest finite magnitude.
#
# `dtypes.finfo` -- tinygrad/dtype.py:114, `(exponent, mantissa)`. A TABLE, not a
# formula, and the table is spelled here rather than imported from dtype.bend for
# the reason codegen/transcendental.bend gives at its own `tx_finfo_e`: the
# table is eight rows, dtype.bend's own copy is unreachable from a file that must
# not drag in its `@unsafe` fp8 lanes, and two ports of one lookup table is
# cheaper than one port of a module boundary. `Dt.pri` is the discriminant and it
# is unique per dtype, so one `match` on the binder reads the whole table.
# The None arm is dtype.py's raise for a non-float.
# ===========================================================================
type Fi is Data:
  Fi{e: U32, m: U32}

def finfo.of(nm: String) -> Maybe<&1, Fi>:
  match nm:
    case "f16"      : Some{Fi{5, 10}}
    case "bf16"    : Some{Fi{8, 7}}
    case "f32"     : Some{Fi{8, 23}}
    case "f64"    : Some{Fi{11, 52}}
    case "fp8e4m3"     : Some{Fi{4, 3}}
    case "fp8e5m2"     : Some{Fi{5, 2}}
    case "fp8e4m3fnuz" : Some{Fi{4, 3}}
    case "fp8e5m2fnuz" : Some{Fi{5, 2}}
    case _: None{}

def nan_fi.of(m: Maybe<&1, Fi>, isexp: Bool) -> U32:
  match m:
    case Some{Fi{e, m}}: Bool.pick(U32, isexp, e, m)
    case None{}: 0

# `S.Dt.nm` IS `DType.name` -- dtype.bend's `dt_name` is a one-field projection of
# this record, so the projection is the port and the wrapper is not.
def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def nan_fi(+dt: S.Dt, isexp: Bool) -> U32: nan_fi.of(finfo.of(dt_name(dt)), isexp)

def nan_e(+dt: S.Dt) -> U32: nan_fi(dt, True{})

def nan_m(+dt: S.Dt) -> U32: nan_fi(dt, False{})

def nan_bs(+dt: S.Dt) -> U32: S.Dt.bits(dt)

# `(1 << (bs - 1)) - 1`. **THE MASK IS 64 BITS WIDE AND IT IS COMPUTED AT 64 BITS.**
#
# IT WAS NOT, AND THE PROSE THAT DEFENDED IT WAS THE DEFECT AS MUCH AS THE ARITHMETIC
# WAS.  The old body was `U32.sub(U32.shln(1, Nat.sub(U32.to_nat(nan_bs(dt)), 1n)), 1)`
# -- a U32 -- and `U32.shln` SATURATES past 31 (`helpers.bend:1802`), so for a double
# `U32.shln(1, 63n)` is 0 and `U32.sub(0, 1)` is 4294967295.  CPython's mask is
# `(1 << 63) - 1` = 9223372036854775807.  The old comment here said "THE WIDTH LIMIT
# IS REAL ... the overflowing width is unreachable from this renderer", and that was
# an argument that a wrong answer was harmless because no WGSL shader can ask for a
# double.  **A WRONG ANSWER THAT NOTHING ASKS FOR IS STILL A WRONG ANSWER**, and
# the census that runs this file found it: `nan_mask double` was one of four rows
# whose two halves disagreed.
#
# SO THE ANSWER IS A `H.I64` -- THE PAIR OF 32-BIT WORDS `helpers.bend` already
# carries (`i64_shl`, `i64_sub`) -- and the row prints it with `H.i64_dec`, the
# DECIMAL printer `helpers.bend:2180` already carries.  CPython's `1 << 63` is an
# ARBITRARY-PRECISION int and this is the 64-BIT answer to the same expression, which
# is the same number for every dtype `wgsl.py:36` can ask about: the widest is
# double's 2^63-1 and it fits.
def nan_mask(+dt: S.Dt) -> H.I64:
  H.i64_sub(H.i64_shl(H.i64_one(), Nat.sub(U32.to_nat(nan_bs(dt)), 1n)), H.i64_one())

# `((1 << exp) - 1) << mant`. **THE SAME WIDTH, THE SAME WAY.**  The old body was a
# U32 and `U32.shln(2047, 52n)` saturates to 0, so the port answered 0 where CPython
# answers 9218868437227405312 -- the same truncation seen from the other side.  The
# threshold is a MASK over the same 64 bits as `nan_mask`, so it is a pair too.
def nan_thr(+dt: S.Dt) -> H.I64:
  H.i64_shl(H.i64_sub(H.i64_shl(H.i64_one(), U32.to_nat(nan_e(dt))), H.i64_one()),
    U32.to_nat(nan_m(dt)))

# `getattr(dtypes, f"uint{bs}")` -- the unsigned dtype of the same width, which
# is the bitcast TARGET and so the dtype of the mask's node.
def nan_uint.of(b: U32) -> S.Dt:
  match b:
    case 8  : S.uint8()
    case 16 : S.uint16()
    case 32 : S.uint32()
    case 64 : S.uint64()
    case _  : S.uint32()

def nan_uint(+dt: S.Dt) -> S.Dt: nan_uint.of(nan_bs(dt))

# ===========================================================================
# :39  packed_rmw -- the read-modify-write a packed_store emits:
# `UPat(Ops.LOAD, src=(UPat(Ops.CAST, dtype=uint32, src=(UPat.var("b"),)),),
# allow_any_len=True) & UPat.var("wmask")`.
#
# `allow_any_len` is a LENGTH CLAUSE, not a repetition: the LOAD may carry any
# number of srcs and only src[0] is constrained, and the CAST is exact-length-1
# (`allow_any_len` is absent). The trailing `& UPat.var("wmask")` is the table's
# BIND, not a guard, so it is not part of the predicate -- and that is
# load-bearing in the other direction too: `string_rewrite`'s store rule takes
# the mask as a SECOND binder, so the same LOAD matches with or without it.
# ===========================================================================
def prw_is(ar: O.Arena, u: U32) -> Bool: O.eq_op(O.Arena.op(ar, u), O.OpsLOAD{})

# the inner UPat, and `allow_any_len` is ABSENT here, so the CAST's src count is
# pinned at one. A gated load's src[0] is still the CAST, which is why the outer
# clause is the only one that is a length clause at all.
def prw_cast(+ar: O.Arena, +tb: F.Table, +c: U32) -> Bool:
  Bool.and(Bool.and(O.eq_op(O.Arena.op(ar, c), O.OpsCAST{}), O.eq_dt(w_dt(ar, tb, c), S.uint32())),
    U32.is_eq(O.Arena.nsrc(ar, c), 1))

def prw_of(+ar: O.Arena, +tb: F.Table, +u: U32) -> Bool:
  Bool.and(prw_is(ar, u), prw_cast(ar, tb, O.Arena.src0(ar, u)))

# ===========================================================================
# :53  WGSLRenderer. Every attribute, in Python's order.
# ===========================================================================

# `global_max = (65535, 65535, 65535)` and `local_max = (256, 256, 64)`. A
# Python tuple of three ints is a `List<&2, U32>`: the ORDER is the whole
# content and there is no name to read.
def global_max() -> List<&2, U32>: [65535, 65535, 65535]

def local_max() -> List<&2, U32>: [256, 256, 64]

# `barrier = "workgroupBarrier();"` -- note the SEMICOLON is inside the string,
# because `base_rewrite`'s BARRIER arm substitutes the text bare and the
# `_render` naming pass only appends `;` to a declaration, not to this.
def barrier() -> String: "workgroupBarrier();"

# `nan = "nan()"`, used by base_rewrite's non-finite const rule.
def nan() -> String: "nan()"

# `supports_float4 = False`
def supports_float4() -> Bool: False{}

# :56 `code_for_workitem = {"g": lambda x: f"i32(gindex.{'xyz'[int(x)]})",
# "l": lambda x: f"i32(lindex.{'xyz'[int(x)]})"}`. The dict key is a `Bool`
# (`is_global`) because there are exactly two and neither is named in the
# output; the axis is a `U32` in 0..2 and `'xyz'[3]` is Python's IndexError.
def wi_axis.of(x: U32) -> Maybe<&1, String>:
  match x:
    case 0: Some{"x"}
    case 1: Some{"y"}
    case 2: Some{"z"}
    case _: None{}

# `'xyz'[int(x)]` is an INDEX and an index of 3 is Python's IndexError, so the
# whole call has no answer there -- not a call with an empty axis letter. The
# totalization is the EMPTY STRING for the whole def, and `gpudims.py:37` builds
# the name as `f"{prefix}{i}"` for `i` in `enumerate(limited)`, so `x` is 0..2 by
# construction and the None arm is unreachable. Recorded rather than dressed up as
# a name: `i32(lindex.)` would be plausible wrong WGSL.
#
# THE `None` ARM LIVES IN `code_for_workitem.ret` AND NOT IN A `wi_axis` OF ITS
# OWN. It used to be `wi_axis.of2`, and `wi_axis` -- the one the header named as
# the totalizer -- called nothing: `code_for_workitem` went to `wi_axis.of`
# directly and `code_for_workitem.ret`'s `None` arm is what actually answers "".
# A def that describes a decision no def makes, next to the def that makes it,
# is the shape `dead_defs_hold` was built to name. Two defs deleted, not moved.
def code_for_workitem.ret(isg: Bool, m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: String.concat(["i32(", Bool.pick(String, isg, "gindex", "lindex"), ".", s, ")"])
    case None{}  : ""

def code_for_workitem(isg: Bool, x: U32) -> String: code_for_workitem.ret(isg, wi_axis.of(x))

# :62 `type_map`. Nine dtypes, and a KeyError for every other one. The `case _:`
# arm is that KeyError: `supported_dtypes` below is the gate that keeps it
# unreachable, and a WGSLRenderer asked for a double must fail rather than
# silently emit a name the shader cannot parse.
#
# AND IT FAILS LOUDLY, IN `code_for_op`'s SPELLING. This arm answered `""` until
# FINDING 2 was fixed, and `""` is a SPELLING no WGSL parser knows -- so the
# file held two spellings of one KeyError, `UNHANDLED(Ops.X)` here's sibling
# `code_for_op` and `""` here, and the silent one was the dangerous one. Bend is
# total and cannot raise, so the refusal is an operand that CANNOT COMPILE and
# that NAMES ITS CAUSE, exactly as `code_for_op` does below.
def type_map.miss(+dt: S.Dt) -> String: String.concat(["UNHANDLED(dtypes.", dt_name(dt), ")"])

def type_map(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 14: "f32"     # dtypes.f32
        case 2 : "u32"     # dtypes.u8
        case 4 : "u32"     # dtypes.u16
        case 3 : "i32"     # dtypes.i16
        case 1 : "i32"     # dtypes.i8
        case 5 : "i32"     # dtypes.i32
        case 6 : "u32"     # dtypes.u32
        case 0 : "bool"    # dtypes.bool
        case 12: "f16"     # dtypes.f16
        case _ : type_map.miss(dt)

# :60 `code_for_op = {**CStyleLanguage.code_for_op, Ops.WHERE: lambda
# a,b,c,dtype: f"select({c},{b},{a})"}`. The WHERE arm takes FOUR arguments and
# the rest take two or one, and NONE of them read `dtype`, so one def with three
# string parameters answers all twenty-two: the unary arms ignore `b` and `c`.
# The twenty inherited from cstyle.py:142-150 are the duplication the header
# names.
def cfo_un(nm: String, +a: String) -> String:
  String.concat([nm, "(", a, ")"])

def cfo_bin(sym: String, +a: String, +b: String) -> String:
  String.concat(["(", a, sym, b, ")"])

def code_for_op.of(+op: O.Op, +a: String, +b: String, +c: String) -> String:
  match op:
    case O.OpsSQRT{}      : cfo_un("sqrt", a)
    case O.OpsRECIPROCAL{}: String.concat(["(1/", a, ")"])
    case O.OpsNEG{}       : String.concat(["-", a])
    case O.OpsEXP2{}      : cfo_un("exp2", a)
    case O.OpsLOG2{}      : cfo_un("log2", a)
    case O.OpsSIN{}       : cfo_un("sin", a)
    case O.OpsTRUNC{}     : cfo_un("trunc", a)
    case O.OpsAND{}       : cfo_bin("&", a, b)
    case O.OpsXOR{}       : cfo_bin("^", a, b)
    case O.OpsOR{}        : cfo_bin("|", a, b)
    case O.OpsADD{}       : cfo_bin("+", a, b)
    case O.OpsSUB{}       : cfo_bin("-", a, b)
    case O.OpsMUL{}       : cfo_bin("*", a, b)
    case O.OpsCMOD{}      : cfo_bin("%", a, b)
    case O.OpsCDIV{}      : cfo_bin("/", a, b)
    # Ops.FDIV is MISSING from WGSLRenderer.code_for_op upstream and present in
    # ClangRenderer's (cstyle.py:294 renders `(a/b)`). Measured, not assumed:
    #   clang - wgsl = ['Ops.FDIV'];  wgsl - clang = ['Ops.EXP2','Ops.LOG2','Ops.RECIPROCAL','Ops.SIN']
    # so this is ONE missing arm, not five -- the other four are WGSL builtins with no C spelling.
    # It matters because the fallthrough below is `case _: ""`, so before this arm an FDIV rendered
    # as the EMPTY STRING: a malformed shader, not a Python KeyError. BatchNorm's
    # rsqrt(running_var + eps) is the shape that reaches it.
    case O.OpsFDIV{}      : cfo_bin("/", a, b)
    case O.OpsCMPNE{}     : cfo_bin("!=", a, b)
    case O.OpsSHR{}       : cfo_bin(">>", a, b)
    case O.OpsSHL{}       : cfo_bin("<<", a, b)
    case O.OpsCMPLT{}     : cfo_bin("<", a, b)
    case O.OpsCMPEQ{}     : cfo_bin("==", a, b)
    case O.OpsWHERE{}     : String.concat(["select(", c, ",", b, ",", a, ")"])
      # Upstream is LOUD here: `code_for_op[op](...)` raises KeyError for an op with no arm
      # (measured: KeyError - Ops.LOAD). This port returned "", which is the divergence that let
      # Ops.FDIV render as the EMPTY STRING -- a malformed shader, not an error.
      # Bend is total and cannot raise, so the equivalent of KeyError is an operand that CANNOT
      # COMPILE and that NAMES THE OP: `UNHANDLED(Ops.FDIV)` is a call to nothing. A WGSL comment
      # would have been valid and would have silently deleted the operand instead.
    case _                : String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])

# :95 render_cast -- `f"{self.type_map[u.dtype]}({val})"`, then the two narrow
# forms. `u` is a UOp in Python and only `u.dtype` is read, so `dt` is the
# parameter. The `&{m}u` and `^{h}` are UNSIGNED CONSTANTS in WGSL and the
# `-{h}` is not, which is why the third form subtracts a bare integer.
def rc_mask(+bits: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(bits)), 1)

def rc_half(+bits: U32) -> U32: U32.shln(1, U32.to_nat(U32.sub(bits, 1)))

def render_cast.cls(cls: S.Cls, +bits: U32, ret: String) -> String:
  match cls:
    case S.CUint{}: String.concat(["(", ret, "&", U32.show(rc_mask(bits)), "u)"])
    case S.CSint{}: String.concat(["(((", ret, "&", U32.show(rc_mask(bits)), ")^", U32.show(rc_half(bits)),
      ")-", U32.show(rc_half(bits)), ")"])
    case _         : ret

# `u.dtype in (dtypes.u8, dtypes.u16)` and `in (dtypes.i8,
# dtypes.i16)` are BOTH-WIDTH tests, and both narrow forms are the same
# expression, so the test is `itemsize < 4 and not float` -- which is
# `is_packed`'s first two clauses and NOT its third: a REG uint8 casts this way
# too. Reusing the name would be a lie, so this is its own test.
def rc_narrow(+dt: S.Dt) -> Bool:
  Bool.and(Bool.and(U32.is_lt(S.Dt.itemsize(dt), 4), S.Dt.is_int(dt)),
    Bool.or(U32.is_eq(S.Dt.bits(dt), 8), U32.is_eq(S.Dt.bits(dt), 16)))

def render_cast.of(narrow: Bool, cls: S.Cls, +bits: U32, +ret: String) -> String:
  Bool.pick(String, narrow, render_cast.cls(cls, bits, ret), ret)

def render_cast(+dt: S.Dt, val: String) -> String:
  render_cast.of(rc_narrow(dt), S.Dt.cls(dt), S.Dt.bits(dt),
    String.concat([type_map(dt), "(", val, ")"]))

# :103 `_render_dtype` -- `return "var"`, for every dtype, every size, every
# addrspace, `override_ptr` and shape. WGSL has no type to spell for a value:
# `var` is a storage CLASS and the type comes from the initializer. So the whole
# method is one constant and the five parameters are all ignored, which is
# recorded rather than dressed up as five unused arguments.
def _render_dtype(dt: S.Dt, sz: U32, addr: S.Addr, mutable: Bool, ovr: Bool, shp: List<&2, O.Sint>) -> String: "var"

# `render_dtype` -- tinygrad/renderer/cstyle.py:205, `_render_dtype(dt, 1, AddrSpace.REG)`. The
# LEGACY spelling WGSLRenderer inherits; the buffer prologue reaches it through
# base_rewrite's BUFFER arm.
def render_dtype(dt: S.Dt, mutable: Bool) -> String: _render_dtype(dt, 1, S.AReg{}, mutable, False{}, Nil{})

# :105 `buf_map` -- `"atomic<u32>" if is_packed(u) else self.type_map[u.dtype]`.
# The atomic is what makes a packed buffer a `var<storage,read_write>
# data0_16:array<atomic<u32>>` and its read-modify-write legal.
def buf_map(+n: U32, +dt: S.Dt, addr: S.Addr) -> String:
  Bool.pick(String, is_packed(dt, addr), "atomic<u32>", type_map(dt))

# :104 `render_load` -- `f"atomicLoad(&{x})" if is_packed(u) else x`. The `&` is
# WGSL's pointer syntax on an atomic and there is no plain form.
def render_load(+x: String, +n: U32, +dt: S.Dt, addr: S.Addr) -> String:
  Bool.pick(String, is_packed(dt, addr), String.concat(["atomicLoad(&", x, ")"]), x)

# ===========================================================================
# :106 render_kernel -- the whole WGSL MODULE. This is the def the browser
# target exists for, and it is PORTED IN FULL.
#
# `bufs` is Python's `list[tuple[str, tuple[UOp, bool]]]`: a name and a UOp. The
# `UOp` is projected to the three fields this method reads of it -- its dtype,
# its addrspace and its `max_numel` -- and the `bool` (the writable flag) is
# dropped because `render_kernel` never reads it, exactly as Python's own
# `for name,(u,_) in bufs` discards it. So `Buf` is the honest record and the
# discarded field is named here rather than silently dropped.
# ===========================================================================
type Buf is Data:
  Buf{name: String, dt: S.Dt, addr: S.Addr, numel: U32}

# `local_size = [u.src[0].ssimplify() for u in sorted([u for u in uops if
# u.op is Ops.SPECIAL and u.arg[0] == 'l'], key=lambda u: u.arg)]`, and
# `prg = "enable f16;\n" if any(uop.dtype == dtypes.f16 for uop in uops)`.
#
# Those two scans are `rk_scan`, and they are a PARAMETER of `render_kernel`
# here for one reason: the `uops` of a real kernel is 138 nodes, so a gate
# fixture that carries one would have to be 138 nodes to agree with CPython's
# `any(...)` over the same list. Splitting the scan out puts the two halves in
# rows of their own -- `rk_sz`, `rk_half` -- and leaves the body below, which is
# the part that is WGSL.
type Scan is Data:
  Scan{sz: List<&2, U32>, half: Bool}

# `u.arg` is the NAME string `f"{prefix}{i}"` (codegen/gpudims.py:37), so
# `u.arg[0]` is its first CHARACTER and `u.arg[-1]` its last, and the axis is
# `int()` of that digit. Brief rule 12 is load-bearing twice here.
def sp_name.of(a: O.Arg) -> String:
  match a:
    case O.AStr{s}: s
    case _         : ""

def sp_name(+ar: O.Arena, +u: U32) -> String: sp_name.of(O.Arena.arg(ar, u))

def sp_is_local(+nm: String) -> Bool: String.eq(String.take(nm, 1n), "l")

# `u.src[0].ssimplify()` -- ops.py:1384, a symbolic fold. It folds a CAST OF A
# CONST to that CONST, and it does so through AS MANY CASTs as there are:
# CPython builds `sint_to_uop(UOp.const(8, dtypes.int32))` as
# `CAST(weakint, CAST(i32, CONST(8)))` and `ssimplify` answers 8 (MEASURED, and
# `never_folding_cast_hold` re-measures both halves on every run). So the arm is
# a CAST-CHAIN WALK and not a single step, and the FUEL is what makes it
# terminate -- the chain is two deep there, and `symbolic` has no bound at all
# because a graph rewrite that cannot loop does not need one.
#
# A float bound is the wall: `ssimplify(CAST(weakint, CAST(f32, CONST(8.0))))`
# answers the NODE and not a number (MEASURED, for f16/f32/f64 alike), so a `U32`
# cannot be its answer and the `0` here is that wall rather than a value.
def ss_is(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsCONST{})

def ss_val.of(a: O.Arg) -> U32:
  match a:
    case O.APy{O.CInt{i}}: H.lo32(i)
    case _                 : 0

def ss_val(ar: O.Arena, +x: U32) -> U32: ss_val.of(O.Arena.arg(ar, x))

def ss_of(ar: O.Arena, +x: U32) -> U32: ss_val(ar, x)

# the `CAST(int, CONST(n))` arm, and the `nope` default of the CONST arm above.
def ss_go.go(f: Nat, +ar: O.Arena, +x: U32) -> U32:
  match f:
    case 0n: 0
    case 1n+g: Bool.pick(U32, ss_is(ar, x), ss_of(ar, x),
      Bool.pick(U32, O.eq_op(O.Arena.op(ar, x), O.OpsCAST{}), ss_go.go(g, ar, O.Arena.src0(ar, x)), 0))

def ssimp(+ar: O.Arena, +x: U32) -> U32: ss_go.go(4n, ar, x)

# one entry of the sort: the name the sort key reads, and the bound.
type Ls is Data:
  Ls{nm: String, v: U32}

def Ls.nm(x: Ls) -> String:
  match x:
    case Ls{nm, v}: nm

def Ls.v(x: Ls) -> U32:
  match x:
    case Ls{nm, v}: v

# the insertion, and the fold that runs it -- `u32_isort` in uop/render.bend is
# this same shape on U32s, and its mutation table says a sort that never
# compares moves one row there, so the compare is the row.
def ls_ins(+x: Ls, +acc: List<&2, Ls>) -> List<&2, Ls>:
  match acc:
    case Nil{}: [x]
    case h <> t: Bool.pick(List<&2, Ls>, String.is_lt(Ls.nm(x), Ls.nm(h)), x <> acc, h <> ls_ins(x, t))

def ls_sort(xs: List<&2, Ls>) -> List<&2, Ls>:
  List.foldl(~&2, ~Ls, ~List<&2, Ls>, (acc: List<&2, Ls>) => (h: Ls) => ls_ins(h, acc), xs, Nil{})

# the two lists, so `sorted` and the `if` are separate rows from the join.
def ls_put.of(isl: Bool, +acc: List<&2, Ls>, e: Ls) -> List<&2, Ls>:
  Bool.pick(List<&2, Ls>, isl, List.append(&2, Ls, acc, [e]), acc)

def ls_put(+ar: O.Arena, +tb: F.Table, +u: U32, acc: List<&2, Ls>) -> List<&2, Ls>:
  ls_put.of(sp_is_local(sp_name(ar, u)), acc, Ls{sp_name(ar, u), ssimp(ar, O.Arena.src0(ar, u))})

def ls_go.go(fuel: Nat, +ar: O.Arena, +tb: F.Table, us: List<&2, U32>, +acc: List<&2, Ls>) -> List<&2, Ls>:
  match fuel:
    case 0n: acc
    case 1n+f:
      match us:
        case Nil{}: acc
        case u <> t: ls_go.go(f, ar, tb, t, ls_put(ar, tb, u, acc))

def ls_sz.go(ss: List<&2, Ls>) -> List<&2, U32>:
  match ss:
    case Nil{}: Nil{}
    case h <> t: Ls.v(h) <> ls_sz.go(t)

def rk_sz(+ar: O.Arena, +tb: F.Table, +uops: List<&2, U32>) -> List<&2, U32>:
  ls_sz.go(ls_sort(ls_go.go(O.Arena.budget(ar), ar, tb, uops, Nil{})))

# `if not local_size: local_size = [1]` -- the empty case, and the reason a
# kernel with no local axis is `@workgroup_size(1)`.
def rk_sz_pad(+ss: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: [1]
    case _     : ss

def hf_go.go(fuel: Nat, +ar: O.Arena, +tb: F.Table, us: List<&2, U32>, acc: Bool) -> Bool:
  match fuel:
    case 0n: acc
    case 1n+f:
      match us:
        case Nil{}: acc
        case u <> t: hf_go.go(f, ar, tb, t, Bool.or(acc, O.eq_dt(w_dt(ar, tb, u), S.half())))

def rk_half(+ar: O.Arena, +tb: F.Table, +uops: List<&2, U32>) -> Bool:
  hf_go.go(O.Arena.budget(ar), ar, tb, uops, False{})

def rk_scan(+ar: O.Arena, +tb: F.Table, +uops: List<&2, U32>) -> Scan:
  Scan{rk_sz_pad(rk_sz(ar, tb, uops)), rk_half(ar, tb, uops)}

# `external_local_bufs = [line.lstrip() for line in kernel if "var<workgroup>"
# in line]` and the line-for-line removal that follows it: ONE partition, and
# both halves come out of it.
type Part is Data:
  Part{work: List<&2, String>, rest: List<&2, String>}

def Part.work(p: Part) -> List<&2, String>:
  match p:
    case Part{work, rest}: work

def Part.rest(p: Part) -> List<&2, String>:
  match p:
    case Part{work, rest}: rest

def pt_line.of(isw: Bool, +h: String, +acc: Part) -> Part:
  match isw:
    case True{} : Part{List.append(&2, String, Part.work(acc), [String.trim_start(h)]), Part.rest(acc)}
    case False{}: Part{Part.work(acc), List.append(&2, String, Part.rest(acc), [h])}

def pt_line(+h: String, acc: Part) -> Part: pt_line.of(String.contains(h, "var<workgroup>"), h, acc)

def rk_partition(+kernel: List<&2, String>) -> Part:
  List.foldl(~&2, ~String, ~Part, (acc: Part) => (h: String) => pt_line(h, acc), kernel, Part{Nil{}, Nil{}})

def Buf.dt(b: Buf) -> S.Dt:
  match b:
    case Buf{name, dt, addr, numel}: dt

def Buf.addr(b: Buf) -> S.Addr:
  match b:
    case Buf{name, dt, addr, numel}: addr

def Buf.numel(b: Buf) -> U32:
  match b:
    case Buf{name, dt, addr, numel}: numel

def Buf.name(b: Buf) -> String:
  match b:
    case Buf{name, dt, addr, numel}: name

# `f"@group(0) @binding({n+1})" + ('var<storage,read_write>' if GLOBAL else
# 'var<uniform>') + f"{name}:{f'array<{buf_map(u)}>' if GLOBAL else buf_map(u)};"`
#
# NOTE THE MISSING SPACE, twice: `@binding(1)var<storage,read_write>` and
# `data0_4:array<f32>` with no space after the colon. Both are in the source and
# both are what a WGSL parser is handed, so neither is a typo to fix here.
def bd_is_global(a: S.Addr) -> Bool:
  match a:
    case S.AGlobal{}: True{}
    case _           : False{}

def bd_tail(+b: Buf) -> String:
  Bool.pick(String, bd_is_global(Buf.addr(b)),
    String.concat([":array<", buf_map(Buf.numel(b), Buf.dt(b), Buf.addr(b)), ">"]),
    String.concat([":", buf_map(Buf.numel(b), Buf.dt(b), Buf.addr(b))]))

def bd_one(+b: Buf, k: U32) -> String:
  String.concat(["@group(0) @binding(", U32.show(U32.add(k, 1)), ")",
    Bool.pick(String, bd_is_global(Buf.addr(b)), "var<storage,read_write>", "var<uniform>"),
    Buf.name(b), bd_tail(b), ";"])

# `bind_it = iter(range(len(bufs)))` and `next(bind_it)+1`: the binding number
# is the buffer's POSITION plus one, because binding 0 is INFINITY. A fold with
# a counter is the honest `iter`/`next`, and the counter is a U32 because
# `Arena.budget` is a Nat and mixing them is the one conversion Bend will not do
# for me.
def bd_go.go(bs: List<&2, Buf>, +k: U32, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case h <> t: bd_go.go(t, U32.add(k, 1), List.append(&2, String, acc, [bd_one(h, k)]))

# `"\n".join([str(x) for x in local_size])` -- `','.join`, and `str` of a CONST
# int. `sint_show` is `uop/render.bend`'s; it is three lines here rather than an
# import because a renderer must not depend on a file that is still landing.
def sint_str(+x: U32) -> String:
  Bool.pick(String, H.i32_is_neg(x), String.concat(["-", U32.show(U32.sub(0, x))]), U32.show(x))

def ls_show(ss: List<&2, U32>) -> List<&2, String>:
  match ss:
    case Nil{}: Nil{}
    case h <> t: sint_str(h) <> ls_show(t)

def ls_join(+ss: List<&2, U32>) -> String: String.join(ls_show(ss), ",")

def rk_workgroup(+ss: List<&2, U32>) -> String:
  String.concat(["\n@compute @workgroup_size(", ls_join(ss), ") fn "])

def rk_sig(fn: String) -> String:
  String.concat([fn, "(@builtin(workgroup_id) gindex: vec3<u32>,",
    "@builtin(local_invocation_id) lindex: vec3<u32>) {\n"])

# `prg = "enable f16;\n" if any(...) else ""` -- the F16 ENABLEMENT, and it is
# the first line of the module, before `nan()`.
def rk_f16(half: Bool) -> String:
  Bool.pick(String, half, "enable f16;\n", "")

# the three fixed lines. They are CONSTANTS in Python too, and they are three
# constants here for the same reason: they are not derived from anything.
def rk_nan() -> String: "fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }\n"

def rk_inf() -> String: "@group(0) @binding(0)\nvar<uniform> INFINITY : f32;\n"

# `prg += "\n".join((external_local_bufs or [])+[bindings])` and then
# `"\n@compute @workgroup_size(...) fn NAME(...gindex: vec3<u32>,"` -- the
# concatenation has no separator of its own, so the `\n` is INSIDE the
# workgroup fragment above and the binding block runs straight into it.
def rk_bind(+work: List<&2, String>, bs: List<&2, Buf>) -> String:
  String.join(List.append(&2, String, work, bd_go.go(bs, 0, Nil{})), "\n")

def Scan.sz(s: Scan) -> List<&2, U32>:
  match s:
    case Scan{sz, half}: sz

def Scan.half(s: Scan) -> Bool:
  match s:
    case Scan{sz, half}: half

def rk_body(+fn: String, +part: Part, bufs: List<&2, Buf>, +sc: Scan) -> String:
  String.concat([rk_f16(Scan.half(sc)), rk_nan(), rk_inf(), rk_bind(Part.work(part), bufs),
    rk_workgroup(Scan.sz(sc)), rk_sig(fn), String.join(Part.rest(part), "\n"), "\n}"])

def render_kernel(+fn: String, +kernel: List<&2, String>, +bufs: List<&2, Buf>, +sc: Scan) -> String:
  rk_body(fn, rk_partition(kernel), bufs, sc)

# ===========================================================================
# :121 supported_dtypes -- `{bool, char, uchar, short, ushort, int32, uint32,
# float, *((half,) if "shader-f16" in self.target.arch else ())}`.
#
# `self.target.arch` is a STRING here and the test is a SUBSTRING test, not an
# equality, so `arch` is a parameter: `"shader-f16" in arch` is the whole of
# what `Target` contributes to this method. The set is a list -- Python's set
# has no order and neither does this, so the gate compares it SORTED and the
# sort is a gate detail, not a claim.
# ===========================================================================
def sd_go(a: Bool, +ds: List<&2, S.Dt>) -> List<&2, S.Dt>:
  Bool.pick(List<&2, S.Dt>, a, List.append(&2, S.Dt, ds, [S.half()]), ds)

def supported_dtypes(arch: String) -> List<&2, S.Dt>:
  sd_go(String.contains(arch, "shader-f16"),
    [S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(), S.int32(), S.uint32(), S.single()])

def dt_show(go: List<&2, S.Dt>, acc: List<&2, String>) -> List<&2, String>:
  match go:
    case Nil{}: acc
    case h <> t: dt_show(t, dt_name(h) <> acc)

# the SORT is a gate detail and not a claim: Python's `supported_dtypes` returns
# a SET, which has no order, so the two lanes would disagree on any ordering at
# all. Sorting both sides by the dtype NAME is the one comparison that makes the
# two lists the same list, and `sorted_names` is the only reader.
def st_ins(+x: String, +acc: List<&2, String>) -> List<&2, String>:
  match acc:
    case Nil{}: [x]
    case h <> t: Bool.pick(List<&2, String>, String.is_lt(x, h), x <> acc, h <> st_ins(x, t))

def dt_sort(xs: List<&2, String>) -> List<&2, String>:
  List.foldl(~&2, ~String, ~List<&2, String>, (acc: List<&2, String>) => (h: String) => st_ins(h, acc), xs, Nil{})

def sorted_names(go: List<&2, S.Dt>) -> String: String.join(dt_sort(dt_show(go, Nil{})), ",")

# ===========================================================================
# :65 `string_rewrite` -- THE SEVENTEEN RULES, in Python's order. This block
# used to be the renderer's largest WALL, and it was the largest because
# `ctx[x]` looked like a graph call: `CStyleLanguage.__getitem__` is
# `self.r[key]`, a dict the NAMING pass fills in before it calls
# `string_rewrite.rewrite` (cstyle.py:245-250). So `ctx[x]` is not a fold and not
# a rewrite engine -- it is the CHILD'S TEXT, and the text is a parameter here
# exactly as `render_cast(u, "V")`'s `val` is. What is left is STRING
# CONSTRUCTION, and that is what the seventeen rules below are.
#
# MEASURED, and this is the census's population statement for the block:
# `len(WGSLRenderer.string_rewrite.patterns)` is 50 and
# `patterns[:17]` are these seventeen while `patterns[17:]` is `base_rewrite`'s
# 33 -- `cstyle.py:153`'s table, which is `renderer/cstyle.bend`'s and not this
# file's. The gate's `rules_hold()` re-measures both numbers and re-derives each
# rule's op and dtype from CPython, so the seventeen are DISCOVERED and not this
# comment's list.
#
# `NOMATCH` IS THIS PORT'S SPELLING OF PYTHON'S `None`, and the gate's oracle
# spells it the same way. A rule that does not apply answers `None` upstream --
# `if is_packed(x) else None` and `else None` -- and `PatternMatcher.rewrite`
# treats `None` as "this rule did not fire", which is a CONTROL-FLOW state and
# not a value. Both sides name it once so that a rule which stops firing and a
# rule which starts rendering the empty string cannot print the same row, and
# the empty string is the shape `type_map`'s arm used to have (FINDING 2).
# ===========================================================================

# ===========================================================================
# THE SEVENTEEN `UPat`s, PORTED AS PREDICATES. wgsl.py:65-93's rule BODIES were
# here first and their PATTERNS were not, and the consequence was measurable: a
# rule body fired on every node it was handed, including the seventeen the
# `srneg` rows below drive, and CPython's own `UPat.match` REJECTS all seventeen.
# Two of those were not over-firing but WRONG ANSWERS -- a packed store of a plain
# CONST answered `atomicAnd(&B[1],W);` with the stored value dropped, and a GATED
# store answered `B = V;` with the gate dropped.
#
# A `UPat` reads five things off a node: its op, its dtype, its src COUNT, and
# src[0]'s op and dtype. Each rule below is handed the ones ITS OWN PATTERN
# constrains and no more. The op is a parameter for exactly THREE rules -- 5, 11
# and 16, whose rejecting fixture is a CONST -- and is absent from the other
# fourteen, where the rule's own row already fixes the op and a parameter would
# be a second spelling of it. `NOMATCH` is the token above, so a rule that
# declines prints the same word CPython's `None` is spelled and the row is
# comparable.
#
# A dtype that is a SET in CPython gets one named predicate and the `O.eq_dt` of
# a SINGLE dtype is spelled at the use site, so there is exactly one `uint32` test
# per rule and no table to drift. MEASURED: `tinygrad/dtype.py:157` is
# `uints = (uint8, uint16, uint32, uint64)`.
# ===========================================================================
def p_uints(+dt: S.Dt) -> Bool:
  Bool.or(Bool.or(O.eq_dt(dt, S.uint8()), O.eq_dt(dt, S.uint16())),
    Bool.or(O.eq_dt(dt, S.uint32()), O.eq_dt(dt, S.uint64())))

# rule 3's `(dtypes.uchar, dtypes.ushort, dtypes.uint32)`, and DISJOINT from
# rule 4's `dtypes.int32` -- which is why `srneg 3` and `srneg 4` are the SAME
# node at two dtypes and each is the other's refusal.
def p_cuint(+dt: S.Dt) -> Bool:
  Bool.or(Bool.or(O.eq_dt(dt, S.uint8()), O.eq_dt(dt, S.uint16())), O.eq_dt(dt, S.uint32()))

# rule 6's `src=(UPat(dtype=(dtypes.short, dtypes.ushort, dtypes.uint32),),)` --
# the ONE rule of the six bitcast rules that constrains its SOURCE, and the
# reason `sr bhalf` needs a source dtype at all.
def p_bsrc(+dt: S.Dt) -> Bool:
  Bool.or(Bool.or(O.eq_dt(dt, S.int16()), O.eq_dt(dt, S.uint16())), O.eq_dt(dt, S.uint32()))

# ===========================================================================
# THE ORDER. `PatternMatcher.rewrite` walks `patterns` TOP TO BOTTOM and takes
# the first hit, so the order is the semantics in EXACTLY TWO places in
# wgsl.py:65-93, and `sr_pick_*` is the port of that walk for those two. The
# `sr pick` rows print the indices, so the order is a MEASURED fact here and not
# a comment.
#
# THE BITCAST CATCH-ALL. Rules 6..10 own five dtypes and rule 11 is
# `UPat(Ops.BITCAST, name="x")` -- NO dtype, so it matches EVERY BITCAST. It is
# LAST, and that is the whole of its safety: hoisted above rule 6, a `half`
# BITCAST answers `bitcast<f16>(S)` where CPython answers
# `bitcast<vec2<f16>>(S)[0]`. That is a shader which COMPILES and computes the
# wrong thing, which is why the catch-all is a ROW and not a default arm: the
# seventh element of `sr pick bitcast` is `half` from `half`, and M56 is the
# mutation that takes it from 11 to 6.
#
# THE STORE PAIR. Rule 14's `UPat.any(packed_rmw, packed_rmw | UPat.var("nv"))` is
# a SUBSET of rule 15's `UPat.store(b, v)`, so 14 before 15 IS the fall-through
# and a packed store of an ordinary CONST is not a read-modify-write: it lands on
# `sr_store` and answers `B = V;`. That is the `sr rmw plain` row, and `sr pick
# store` is the same fact with the index instead of the string. `Ops.AND` is
# `packed_rmw`'s OUTER op -- the `&` in `packed_rmw & UPat.var("wmask")` is
# `Ops.AND` and not a bind, so the shape under it is still `prw_of`'s wall.
#
# THE PIN ADDED A SECOND FALL-THROUGH, and it is `sr rmw bare`: rule 14's
# pattern binds `b` to the SOURCE of a CAST, so a store whose buffer is not a
# CAST is not rule 14 either, and it falls to rule 15 with rule 14 alone
# answering nothing. The two rules' patterns are therefore INVERTED over the
# two nodes, and `sr_rmw_cast` is the clause that says which way round.
#
# The other two multi-rule ops need no walk and get none: rules 12 and 13 are
# disjoint on the src COUNT and rules 0, 2, 3, 4 are disjoint on the dtype and on
# src[0]'s op, so first-match and any-match agree on them. MEASURED on CPython's
# OWN matcher by the gate's `sr_dispatch_hold()`, which re-asks it for all 35
# positive fixtures and finds exactly one that falls through.
# ===========================================================================
def sr_none() -> U32: 17

# Rules 7..10 and the catch-all. `"f16"` is ABSENT from this table ON PURPOSE:
# rule 6 owns it, and the `Bool.pick` below routes to 11 when rule 6's `src=`
# clause refuses -- so a `f16` that reaches `_` here is rule 11 and not a rule 6
# that failed to be asked.
def sr_pick_bitcast.of(nm: String) -> U32:
  match nm:
    case "u8" : 7
    case "i8" : 8
    case "u16": 9
    case "i16": 10
    case _    : 11

# Rule 6 is the only one of the six that constrains its SOURCE, so it is the only
# one that reads `s0` -- and `half` FROM `half` is therefore rule 11 and not
# rule 6, which the seventh element of `sr pick bitcast` is there to say.
def sr_pick_bitcast(+dt: S.Dt, +s0: S.Dt) -> U32:
  Bool.pick(U32, Bool.and(O.eq_dt(dt, S.half()), p_bsrc(s0)), 6, sr_pick_bitcast.of(dt_name(dt)))

def sr_pick_load(+ns: U32) -> U32:
  Bool.pick(U32, U32.is_eq(ns, 3), 12, Bool.pick(U32, U32.is_eq(ns, 1), 13, sr_none()))

# THE STORE'S BUFFER MUST BE A CAST. Upstream's rule 14 is
# `UPat.store(UPat(Ops.CAST, src=(UPat.var("b"),)), UPat.any(packed_rmw, packed_rmw | UPat.var("nv")))`
# -- the `b` binder is the CAST's SOURCE and not the buffer -- and that is a PAIR
# with `packed_store`, which now stores to `word = idx.cast(dtypes.uint32)`
# rather than to `idx` itself. MEASURED, the two patterns are INVERTED over the
# two nodes: the pre-pin `UPat.store(UPat.var("b"), ...)` answers
# `atomicAnd(&B[1],W);` on `STORE(INDEX, AND)` and NOTHING on `STORE(CAST, AND)`,
# and the pinned one answers NOTHING on the first and `atomicAnd(&B[1],W);` on
# the second -- because `UPat.match`'s `setdefault(name, uop) is not uop` check
# REJECTS a store whose `b` and `packed_rmw`'s `b` are different UOps. So the
# buffer's op is the rule's THIRD predicate, beside the src COUNT and the value's
# op, and it is ONE def because the TABLE and the BODY both ask it.
def sr_rmw_cast(+bop: O.Op) -> Bool: O.eq_op(bop, O.OpsCAST{})

def sr_pick_store(+ns: U32, +vop: O.Op, +bop: O.Op) -> U32:
  Bool.pick(U32, Bool.and(Bool.and(U32.is_eq(ns, 2), O.eq_op(vop, O.OpsAND{})), sr_rmw_cast(bop)), 14,
    Bool.pick(U32, U32.is_eq(ns, 2), 15, sr_none()))

# 0 `UPat(Ops.CAST, dtype=dtypes.uint32, src=(UPat(Ops.INDEX, name="x"),))`, then
# `ctx[x] if is_packed(x) else None` -- a packed INDEX is rendered by its own rule,
# so the CAST around it only carries the width. `pk` is the BODY's clause and the
# dtype and src[0]'s op are the PATTERN's, and both answer NOMATCH.
def sr_idx(+dt: S.Dt, +s0: O.Op, pk: Bool, +x: String) -> String:
  Bool.pick(String, Bool.and(Bool.and(O.eq_dt(dt, S.uint32()), O.eq_op(s0, O.OpsINDEX{})), pk), x, "NOMATCH")

# 1 `UPat(Ops.NEG, dtypes.uints, src=(UPat.var('x'),))` -- `f"(0-{ctx[x]})"`, and
# WGSL has no unsigned negation.
def sr_neg(+dt: S.Dt, +x: String) -> String:
  Bool.pick(String, p_uints(dt), String.concat(["(0-", x, ")"]), "NOMATCH")

# 2 `UPat.cvar("c").cast(dtypes.bool)` -- `"true" if c.val else "false"`, and
# `c.val` is a bare CONST's value, and a bare CONST is ALWAYS weakint
# (ops.py:632: `.cast` folds away at exactly bool/weakint/weakfloat), so this is
# a Python truth test on an integer.
def sr_cbool(+dt: S.Dt, v: Bool) -> String:
  Bool.pick(String, O.eq_dt(dt, S.boolean()), Bool.pick(String, v, "true", "false"), "NOMATCH")

# 3 `f"{c.val&0xFFFFFFFF}u"` and 4 `f"i32({v})" if (v:=truncate[x.dtype](c.val))<0
# else f"{v}"`. BOTH TAKE THE CONST'S OWN weakint VALUE, and the value is an
# `I64` and NOT a `U32` here because a U32 cannot tell a weakint CONST of -1
# from one of 4294967295 and CPython can. `truncate[x.dtype]` with `x.dtype ==
# int32` is `ctypes.c_int32`, so rule 4's mask is the 32-bit one and NOT a
# 64-bit one.
#
# RULE 3 HAS NO NEGATIVE ARM, and that is THE PIN'S CHANGE: upstream dropped
# `f"bitcast<u32>({c.val})" if c.val < 0 else ...` and a negative const cast to
# u8/u16/u32 is now the MASKED value with its `u` suffix. MEASURED against the
# vendored `tinygrad/renderer/wgsl.py`: `c.val = -1` answers `4294967295u` and
# not `bitcast<u32>(-1)`. So the two spellings the old text contrasted are ONE
# spelling now, and the axis below still carries -1 because the WEAKINT value
# is still a different one -- `fixtures_hold` compares the AXES and not the
# renderings.
def sr_cuint.masked(+v: H.I64) -> H.I64: H.i64_of_hi_lo(0, H.lo32(v))

def sr_cuint(+dt: S.Dt, +v: H.I64) -> String:
  Bool.pick(String, p_cuint(dt), String.concat([H.i64_dec(sr_cuint.masked(v)), "u"]), "NOMATCH")

def sr_ci32.trunc(+v: H.I64) -> H.I64: H.i64_of_i32(H.lo32(v))

def sr_ci32(+dt: S.Dt, +v: H.I64) -> String:
  Bool.pick(String, O.eq_dt(dt, S.int32()),
    Bool.pick(String, H.i64_is_neg(sr_ci32.trunc(v)),
      String.concat(["i32(", H.i64_dec(sr_ci32.trunc(v)), ")"]), H.i64_dec(sr_ci32.trunc(v))), "NOMATCH")

# 5 `UPat(Ops.BUFFER, name="x")` -- and it is the ONE rule whose op is a
# parameter, because `srneg 5` hands it a CONST. `f"var{'<workgroup>' if
# x.addrspace == AddrSpace.LOCAL else ''} {ctx[x]}: array<{buf_map(x)},
# {_packed_size(x)}>;"`. NOTE THE SPACE AFTER THE COLON: it is in the f-string and
# a WGSL parser is handed it. `buf_map` and `packed_size` are the two ported defs
# this rule is the only caller of that were written for, and the
# `array<atomic<u32>,4>` they produce together is the `var<workgroup>` line
# `render_kernel` hoists.
def sr_buffer.local(a: S.Addr) -> Bool:
  match a:
    case S.ALocal{}: True{}
    case _           : False{}

def sr_buffer(+op: O.Op, +nm: String, +n: U32, +d: S.Dt, +a: S.Addr) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsBUFFER{}),
    String.concat([Bool.pick(String, sr_buffer.local(a), "var<workgroup>", "var"), " ", nm, ": array<",
      buf_map(n, d, a), ",", U32.show(packed_size(n, d, a)), ">;"]), "NOMATCH")

# 6..11 the SIX `bitcast<>` SPELLINGS, and they are six rules rather than one
# because they are six different WGSL constructions. 9 and 10 each have TWO
# arms: a half source goes through `vec2<f16>` and anything else is a mask --
# and that source dtype is the arm, so it is a `S.Dt` here and not a Bool handed
# in, or the two spellings would be one spelling with a flag.
#
# RULE 11 IS THE CATCH-ALL AND ITS PATTERN IS `UPat(Ops.BITCAST, name="x")` WITH
# NO dtype, so its op is the whole of it and `srneg 11` hands it a CONST. THE
# CATCH-ALL'S REAL WORK IS `sr_pick_bitcast` above: nothing here can keep a
# `half` off rule 11, because CPython's rule 11 genuinely ACCEPTS a half BITCAST
# -- what keeps it off is that rules 6..10 are consulted first.
def sr_bhalf(+dt: S.Dt, +s0: S.Dt, +s: String) -> String:
  Bool.pick(String, Bool.and(O.eq_dt(dt, S.half()), p_bsrc(s0)),
    String.concat(["bitcast<vec2<f16>>(", s, ")[0]"]), "NOMATCH")

def sr_buchar(+dt: S.Dt, +s: String) -> String:
  Bool.pick(String, O.eq_dt(dt, S.uint8()), String.concat(["bitcast<u32>(", s, "&0xFF)"]), "NOMATCH")

def sr_bchar(+dt: S.Dt, +s: String) -> String:
  Bool.pick(String, O.eq_dt(dt, S.int8()), String.concat(["((i32(", s, "&0xFF)<<24)>>24)"]), "NOMATCH")

def sr_bushort(+dt: S.Dt, +s0: S.Dt, +s: String) -> String:
  Bool.pick(String, O.eq_dt(dt, S.uint16()),
    Bool.pick(String, O.eq_dt(s0, S.half()), String.concat(["bitcast<u32>(vec2<f16>(", s, ",0))"]),
      String.concat(["bitcast<u32>(", s, "&0xFFFF)"])), "NOMATCH")

def sr_bshort(+dt: S.Dt, +s0: S.Dt, +s: String) -> String:
  Bool.pick(String, O.eq_dt(dt, S.int16()),
    Bool.pick(String, O.eq_dt(s0, S.half()), String.concat(["bitcast<i32>(vec2<f16>(", s, ",0))"]),
      String.concat(["((i32(", s, "&0xFFFF)<<16)>>16)"])), "NOMATCH")

def sr_bany(+op: O.Op, +d: S.Dt, s: String) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsBITCAST{}), String.concat(["bitcast<", type_map(d), ">(", s, ")"]), "NOMATCH")

# 12 `UPat.load(UPat.var("b"), UPat.var("v"), UPat.var("gate"))` --
# `f"select({ctx[v]}, {ctx.render_load(ctx[b], b.src[0])}, {ctx[gate]})"`, and 13
# `UPat.load(UPat.var("b"))` -- `ctx.render_load(ctx[b], b)`. THE TWO DIVIDE ON
# THE SRC COUNT and the count is the whole of both patterns, so `ns` is what makes
# a two-src LOAD rule 13's and a three-src one rule 12's -- and what made
# `srneg 12` and `srneg 13` refusals rather than answers.
#
# RULE 13 HAS NO BODY OF ITS OWN: it IS `render_load`, so it gets a def that is
# the PATTERN plus the call, and the row still calls `render_load` through it.
# `b.src[0]` is the INDEX under the CAST, and `is_packed` reads that node's buffer
# -- which is why the rows hand in its `(n, dt, addr)` and not the LOAD's.
def sr_lgate(ns: U32, +b: String, +i0: String, +n0: U32, +d0: S.Dt, a0: S.Addr, +v: String, +g: String) -> String:
  Bool.pick(String, U32.is_eq(ns, 3),
    String.concat(["select(", v, ", ", render_load(i0, n0, d0, a0), ", ", g, ")"]), "NOMATCH")

def sr_load(ns: U32, +x: String, +n: U32, +dt: S.Dt, a: S.Addr) -> String:
  Bool.pick(String, U32.is_eq(ns, 1), render_load(x, n, dt, a), "NOMATCH")

# 14 `UPat.store(UPat(Ops.CAST, src=(UPat.var("b"),)), UPat.any(packed_rmw, packed_rmw | UPat.var("nv")))`
# -- the READ-MODIFY-WRITE: `atomicAnd` clears the field, `atomicAdd` sets it, and
# `new_v` is gone when it is 0 so the second line is OPTIONAL. `vop` is
# `packed_rmw`'s OUTER op and it is the pattern's whole discriminator here: a
# store of an ordinary CONST is not a read-modify-write, and without this test
# `srneg 14` answered `atomicAnd(&B[1],W);` and DROPPED THE STORED VALUE. The
# `\n  ` is a real newline in Python and is SPELLED by the row's `one_line`; the
# two spaces after it are in the f-string.
#
# `bop` IS THE STORE'S BUFFER'S OP and it is the pin's THIRD predicate: the
# pattern binds `b` to the CAST's SOURCE, so a store whose buffer is not a CAST
# is not this rule at all. `sr_rmw_cast` is that clause.
def sr_rmw.add(hasnv: Bool, +b: String, +nv: String) -> String:
  Bool.pick(String, hasnv, String.concat(["\n  atomicAdd(&", b, ",", nv, ");"]), "")

def sr_rmw(+vop: O.Op, +bop: O.Op, pk: Bool, hasnv: Bool, +b: String, +w: String, +nv: String) -> String:
  Bool.pick(String, Bool.and(Bool.and(O.eq_op(vop, O.OpsAND{}), sr_rmw_cast(bop)), pk),
    String.concat(["atomicAnd(&", b, ",", w, ");", sr_rmw.add(hasnv, b, nv)]), "NOMATCH")

# 15 `UPat.store(UPat.var("b"), UPat.var("v"))` -- `f"{ctx[b]} = {ctx[v]};"` --
# and it is the SUBSET-fall-through of rule 14, so it takes the same src COUNT.
def sr_store(ns: U32, +b: String, +v: String) -> String:
  Bool.pick(String, U32.is_eq(ns, 2), String.concat([b, " = ", v, ";"]), "NOMATCH")

# 16 `UPat(Ops.INDEX, src=(UPat.var("b"), UPat.var("idx")))` --
# `f"{ctx[b]}[{strip_parens(ctx[idx]) if idx.arg is Ops.ADD else ctx[idx]}]"`, and
# `strip_parens` (helpers.bend:1463) is ALREADY PORTED, `is_balanced` and all,
# which is why this rule is four lines and not a walk. The `Ops.ADD` test is the
# rule's own `isadd` parameter; a source that is not balanced keeps its parens,
# and `(I0)+(I1)` is that case. `op` is the pattern's, because `srneg 16` is a
# CONST and an INDEX is the only thing this rule renders.
def sr_index(+op: O.Op, isadd: Bool, +b: String, +i: String) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsINDEX{}),
    String.concat([b, "[", Bool.pick(String, isadd, H.strip_parens(i), i), "]"]), "NOMATCH")

# ===========================================================================
# THE render_kernel FIXTURES AND ROWS.
#
# `render_kernel` is a String -> String function and this is the row that says so
# on the REAL inputs: the float32 add's twelve body lines are the ones
# `to_program` produced for `Tensor([1,2,3,4]) + Tensor([5,6,7,8])` on this
# `tinygrad/`, measured off the Spy's `render_kernel` record in
# `.agents/slop/wgsl-rows.py`, and the three buffers are the three PARAMs
# `_render` found. Measured, not transcribed.
#
# THE `mixed` CASE EARNS ITS KEEP, because no single real kernel exercises every
# branch at once: a packed GLOBAL uchar (the `array<atomic<u32>>` spelling), a
# `var<workgroup>` line to hoist out of the body, a LOCAL f32 to take the
# `var<uniform>` arm, TWO local axes so the `,` join is not a one-element list,
# and a half uop so `enable f16;` is emitted. `empty` is the two short-circuits:
# the empty join and `range(0)`.
# ===========================================================================

def bs(x: Bool) -> String: Bool.pick(String, x, "True", "False")

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

# A row is ONE line, so a module's newlines are SPELLED. Without this a dropped
# separator between two bindings would be invisible to a line-oriented diff, and
# `String.concat` would hide it: the whole point of the gate is that a lost
# separator is a lost claim.
def one_line(+s: String) -> String: String.join(String.split(s, '\n'), "\\n")

# `UOp.const(n)` -- weakint, and `fold` agrees, so no CAST is involved.
def f_const(+ar: O.Arena, n: U32) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

def f_cast_dt(+c: O.Found, d: S.Dt) -> O.Found:
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{d}, O.TNone{})

# THE MIXED ARENA: l0, l1 and one half-dtype node in ONE arena, because
# `rk_scan` folds a table over the whole arena and a node in a different arena
# would not be in it.
#
# `l0`'s bound is `CAST(weakint, CAST(i32, CONST(8)))` -- NOT a bare CONST, and
# NOT the single CAST this used to build. It is the shape
# `sint_to_uop(UOp.const(8, dtypes.int32))` builds, which is the shape a real
# kernel's bound has whenever the bound was written with a dtype, and
# `ssimplify` answers 8 on it (MEASURED). This fixture used to build
# `CAST(weakint, CONST(8))`, which is UNBUILDABLE: `UOp.cast` FOLDS when the
# dtypes agree (`mixin/dtype.py:36`), the only CONST is weakint, and
# `UOp.const(8).cast(weakint) is UOp.const(8)` -- so that node exists nowhere in
# CPython and only `ssimp`'s ONE-step CAST arm could read it. `never_folding_cast_hold`
# re-measures the fold, CPython's shape and CPython's answer on every run.
type Fx is Data:
  Fx{ar: O.Arena, l0: U32, l1: U32, h: U32}

def Fx.ar(f: Fx) -> O.Arena:
  match f:
    case Fx{ar, l0, l1, h}: ar

def Fx.l0(f: Fx) -> U32:
  match f:
    case Fx{ar, l0, l1, h}: l0

def Fx.l1(f: Fx) -> U32:
  match f:
    case Fx{ar, l0, l1, h}: l1

def Fx.h(f: Fx) -> U32:
  match f:
    case Fx{ar, l0, l1, h}: h

def fx_mixed() -> Fx:
  +a = O.Arena.empty()
  +c8 = f_const(a, 8)
  +i8 = f_cast_dt(c8, S.int32())
  +k8 = f_cast_dt(i8, S.weakint())
  +s0 = O.UOp.special(O.Found.ar(k8), O.Found.i(k8), "l0")
  +c2 = f_const(O.Found.ar(s0), 2)
  +k2 = f_cast_dt(f_cast_dt(c2, S.int32()), S.weakint())
  +s1 = O.UOp.special(O.Found.ar(k2), O.Found.i(k2), "l1")
  +c0 = f_const(O.Found.ar(s1), 0)
  +ch = f_cast_dt(c0, S.half())
  Fx{O.Found.ar(ch), O.Found.i(s0), O.Found.i(s1), O.Found.i(ch)}

def fx_uops(+f: Fx) -> List<&2, U32>: [Fx.l0(f), Fx.l1(f), Fx.h(f)]

def fx_tb(+f: Fx) -> F.Table: F.UOp.fold(Fx.ar(f))

# -- the two `uops` scans, as rows of their own --------------------------------
# `rk_sz` and `rk_half` get rows because they are the half of `render_kernel` a
# real kernel's 138-element uop list would hide, and because the SORT inside
# `rk_sz` is the one place an order bug can hide: `rk_sz none` is the empty case
# and `rk_sz mixed` is `8,2`, so a reversed sort would say `2,8`.
# `global_max` and `local_max` are three ints each and Python's `repr` of the
# tuple is the gate's whole content, so the row needs them as decimal text. THE
# CONSTRUCTOR MATTERS: this list is WALKED on the way to `String.join`, and
# `String.join` is head-first, so `<>` (a prepend) is the constructor that keeps
# the order and `List.append(acc, [x])` would reverse it.
def u32_show(us: List<&2, U32>) -> List<&2, String>:
  match us:
    case Nil{}: Nil{}
    case h <> t: U32.show(h) <> u32_show(t)

# -- is_packed / buf_map / packed_size, over every dtype and addrspace ---------
# THE FIXTURE CLASS THIS FILE WAS MISSING, added because the gate found
# `is_packed`'s third clause inverted with every other row green. A predicate
# that no row calls is a predicate no mutation finds, and `is_packed` decides
# whether a buffer is `atomic<u32>` at all.
def r_pk1(+nm: String, +d: S.Dt, +a: S.Addr, pk: String, bm: String) -> String:
  String.concat([r("is_packed " ++ nm, bs(is_packed(d, a)), pk),
    r("buf_map " ++ nm, buf_map(16, d, a), bm)])

def r_pk(+nm: String, +d: S.Dt, +a: S.Addr, pk: String, bm: String) -> String:
  r_pk1(nm, d, a, pk, bm)

def r_ps(+nm: String, +d: S.Dt, +a: S.Addr, +n: U32, py: String) -> String:
  r("packed_size " ++ nm, U32.show(packed_size(n, d, a)), py)

def r_pk8(+nm: String, +d: S.Dt, pg: String, pl: String, pr: String, bg: String, bl: String, br: String) -> String:
  String.concat([r_pk(nm ++ " GLOBAL", d, S.AGlobal{}, pg, bg), r_pk(nm ++ " LOCAL", d, S.ALocal{}, pl, bl),
    r_pk(nm ++ " REG", d, S.AReg{}, pr, br)])

def r_pk_all() -> String:
  String.concat([
    r_pk8("uchar", S.uint8(), "True", "True", "False", "atomic<u32>", "atomic<u32>", "u32"),
    r_pk8("char", S.int8(), "True", "True", "False", "atomic<u32>", "atomic<u32>", "i32"),
    r_pk8("ushort", S.uint16(), "True", "True", "False", "atomic<u32>", "atomic<u32>", "u32"),
    r_pk8("short", S.int16(), "True", "True", "False", "atomic<u32>", "atomic<u32>", "i32"),
    r_pk8("bool", S.boolean(), "True", "True", "False", "atomic<u32>", "atomic<u32>", "bool"),
    r_pk8("half", S.half(), "False", "False", "False", "f16", "f16", "f16"),
    r_pk8("float", S.single(), "False", "False", "False", "f32", "f32", "f32"),
    r_pk8("int32", S.int32(), "False", "False", "False", "i32", "i32", "i32")])

def r_ps_all() -> String:
  String.concat([r_ps("uchar 16", S.uint8(), S.AGlobal{}, 16, "4"),
    r_ps("uchar 17", S.uint8(), S.AGlobal{}, 17, "5"),
    r_ps("ushort 16", S.uint16(), S.AGlobal{}, 16, "8"),
    r_ps("ushort 17", S.uint16(), S.AGlobal{}, 17, "9"),
    r_ps("half 16", S.half(), S.AGlobal{}, 16, "16"),
    r_ps("half 17", S.half(), S.AGlobal{}, 17, "17"),
    r_ps("float 16", S.single(), S.AGlobal{}, 16, "16"),
    r_ps("int32 16", S.int32(), S.AGlobal{}, 16, "16"),
    r_ps("uchar 16 REG", S.uint8(), S.AReg{}, 16, "16")])

def r_sz(us: List<&2, U32>) -> String: String.join(u32_show(us), ",")

def r_rk_sz(+f: Fx) -> String:
  r("rk_sz mixed", r_sz(rk_sz(Fx.ar(f), fx_tb(f), fx_uops(f))), "8,2")

def r_rk_sz_pad() -> String: r("rk_sz none", r_sz(rk_sz_pad(Nil{})), "1")

def r_rk_half(+f: Fx) -> String:
  r("rk_half mixed", bs(rk_half(Fx.ar(f), fx_tb(f), fx_uops(f))), "True")

def r_rk_half_no(+ar: O.Arena) -> String: r("rk_half none", bs(rk_half(ar, F.UOp.fold(ar), Nil{})), "False")

# -- the module rows ----------------------------------------------------------
# `data0_4`, `data1_4`, `data2_4` are GLOBAL f32 of four: the three PARAMs of the
# real add, in the order `_render` recorded them. That order IS the binding
# number, so this is the row a reversed `bufs` fold breaks.
def bufs_alu() -> List<&2, Buf>:
  [Buf{"data0_4", S.single(), S.AGlobal{}, 4}, Buf{"data1_4", S.single(), S.AGlobal{}, 4},
    Buf{"data2_4", S.single(), S.AGlobal{}, 4}]

# THE TWELVE BODY LINES of the real float32 add, verbatim.
def kern_alu() -> List<&2, String>:
  ["  var val0 = data1_4[0];", "  var val1 = data1_4[1];", "  var val2 = data1_4[2];",
    "  var val3 = data1_4[3];", "  var val4 = data2_4[0];", "  var val5 = data2_4[1];",
    "  var val6 = data2_4[2];", "  var val7 = data2_4[3];", "  data0_4[0] = (val0+val4);",
    "  data0_4[1] = (val1+val5);", "  data0_4[2] = (val2+val6);", "  data0_4[3] = (val3+val7);"]

# A packed GLOBAL uchar and a LOCAL f32. The `var<workgroup>` line is NOT chosen
# here: it is what `render_kernel` puts there, from the LOCAL buffer that
# wgsl.py:74's BUFFER rule renders, and its `:array<atomic<u32>,4>` is `buf_map`
# and `_packed_size` agreeing on a 16-element uchar.
def bufs_mixed() -> List<&2, Buf>:
  [Buf{"data0_16", S.uint8(), S.AGlobal{}, 16}, Buf{"t0", S.single(), S.ALocal{}, 1}]

def kern_mixed() -> List<&2, String>:
  ["  var val0 = atomicLoad(&data0_16[0]);", "  var<workgroup> buf0:array<atomic<u32>,4>;",
    "  data0_16[0] = (val0+1);"]

# THE TWO FOLDS `render_kernel`'s body is made of, as rows, and these two rows
# are the ONLY reason the file's other folds are written the way they are.
#
# MEASURED 2026-10-02 on bend 2.0.34, and it is the OPPOSITE of what the brief
# says. Four facts, and only together do they fix the direction:
#
#   `case h <> t` on a list LITERAL is head-first: ["a","b","c"] walks a,b,c.
#   `x <> rest` is a PREPEND, so `h <> f(t)` rebuilds the list head-first.
#   `List.append(acc, [x])` is an APPEND, so it rebuilds the list tail-first.
#   `String.join` is HEAD-FIRST.
#
# So a fold whose result reaches `String.join` must APPEND, and a fold whose
# result is WALKED must PREPEND. `bd_go` and `pt.go` reach `String.join`;
# `u32_show`, `ls_show`, `dt_show` and `ls_sz` are walked. Getting this backwards
# typechecks, runs, and emits a shader with its bindings and its body in REVERSE
# ORDER -- which is why both folds are rows and not an assertion in a comment.
def r_bd() -> String:
  r("rk_bindings", String.join(bd_go.go(bufs_alu(), 0, Nil{}), ";"),
    "@group(0) @binding(1)var<storage,read_write>data0_4:array<f32>;;@group(0) @binding(2)var<storage,read_write>data1_4:array<f32>;;@group(0) @binding(3)var<storage,read_write>data2_4:array<f32>;")

def r_pt() -> String:
  r("rk_body", String.join(Part.rest(rk_partition(kern_alu())), ";"),
    "  var val0 = data1_4[0];;  var val1 = data1_4[1];;  var val2 = data1_4[2];;  var val3 = data1_4[3];;  var val4 = data2_4[0];;  var val5 = data2_4[1];;  var val6 = data2_4[2];;  var val7 = data2_4[3];;  data0_4[0] = (val0+val4);;  data0_4[1] = (val1+val5);;  data0_4[2] = (val2+val6);;  data0_4[3] = (val3+val7);")

# A MODULE ROW has no `py=` half, and that is deliberate. The expectation for
# `render_kernel` is the DRIVER's own call to the real method
# (`.agents/slop/wgsl-rows.py`), not a second copy of a 700-character escaped
# module pasted in here: a pasted copy is a second thing to re-escape by hand
# every time the renderer changes, and it went wrong twice while this file was
# being written. Both lanes still print `nm = [<value>]`, and the diff of the two
# `[...]` halves is the gate.
def rk_row(nm: String, got: String) -> String: String.concat([nm, " = [", got, "]\n"])

def r_rk_alu() -> String:
  rk_row("rk alu", one_line(render_kernel("E_4", kern_alu(), bufs_alu(), Scan{[1], False{}})))

def r_rk_mixed(+f: Fx) -> String:
  rk_row("rk mixed", one_line(render_kernel("K_mixed", kern_mixed(), bufs_mixed(),
    rk_scan(Fx.ar(f), fx_tb(f), fx_uops(f)))))

def r_rk_empty() -> String:
  rk_row("rk empty", one_line(render_kernel("K_empty", Nil{}, Nil{}, Scan{[1], False{}})))

# ===========================================================================
# THE GATE. Every row is a STRING and every row carries CPython's value, so the
# two lanes print the SAME LINE and the diff of the two lanes is empty iff every
# claim holds. The rows are built as one string by a fold rather than printed
# one IO at a time: an `IO.bind` chain nine deep is a paren-counting exercise
# with no payoff, and a fold over rows is also what makes the row ORDER a
# property of this file that the Python side can copy.
#
# `r` is render.bend's `py_row` with the IO dropped: a row is a value here, not
# an effect, so a group of them is a `String` and the whole gate is one print.
# ===========================================================================
# `global_max` and `local_max` are three ints each and Python's `repr` of the
# tuple is the gate's whole content, so the row needs them as decimal text. THE
# CONSTRUCTOR MATTERS: this list is WALKED by `case h <> t` on the way to
# `String.join`, and `String.join` is head-first, so `<>` (a prepend) is the
# constructor that keeps the order and `List.append(acc, [x])` would reverse it.
# -- type_map -----------------------------------------------------------------
def r_tm1(+nm: String, +d: S.Dt, py: String) -> String: r("type_map " ++ nm, type_map(d), py)

def r_tms() -> String:
  String.concat([r_tm1("float", S.single(), "f32"), r_tm1("uchar", S.uint8(), "u32"),
    r_tm1("ushort", S.uint16(), "u32"), r_tm1("short", S.int16(), "i32"),
    r_tm1("char", S.int8(), "i32"), r_tm1("int32", S.int32(), "i32"),
    r_tm1("uint32", S.uint32(), "u32"), r_tm1("bool", S.boolean(), "bool"),
    r_tm1("half", S.half(), "f16")])

# THE KeyError ARM, and it is LOUD: the port answers `UNHANDLED(dtypes.f64)` --
# a call to a dtype WGSL has no name for, which cannot compile. It answered `""`
# until FINDING 2 was fixed, and `""` is a SPELLING no WGSL parser knows. The
# name is `dt_name`'s, which is `DType.name`.
#
# **AND THE `py=` HALF CARRIES THE PORT'S OWN REFUSAL TOKEN, NOT CPython's EXCEPTION
# NAME.**  It used to carry `REFUSE:KeyError`, and that made the row compare TWO
# DIFFERENT CONVENTIONS: the port's half said "UNHANDLED(dtypes.f64)" and the
# claimed CPython half said "REFUSE:KeyError", so no two halves could ever agree and
# the row was ROT by construction rather than by measurement.  **CPython's
# CONVENTION IS TO RAISE**, and Bend cannot raise: `type_map`'s answer reaches the
# RENDERED WGSL (`render_cast`, `buf_map`, `code_for_op`), so the port has to answer
# SOMETHING, and the only honest something is the token a shader cannot silently
# hold.  `REFUSE:KeyError` is the ORACLE's spelling of an exception and is not a
# WGSL fragment; `UNHANDLED(dtypes.f64)` is the port's, and it is what this row's
# `got=` half already was.
#
# **THIS IS THE FILE'S OWN CONVENTION, NOT A NEW ONE.**  `code_for_op LOAD/MAX/POW`
# below record CPython's `KeyError` as the port's `UNHANDLED(Ops.X)`, and
# `workitem l3` records CPython's `IndexError` as the port's `""`.  **THE `py=` HALF
# IS "WHAT THE PORT MUST ANSWER HERE FOR THE PORT TO AGREE WITH CPython"**, and for a
# CPython refusal that is the port's refusal token, because the port cannot raise.
def r_tm_miss() -> String: r_tm1("double", S.double(), "UNHANDLED(dtypes.f64)")

# -- render_cast --------------------------------------------------------------
def r_rc1(+nm: String, +d: S.Dt, py: String) -> String: r("render_cast " ++ nm, render_cast(d, "V"), py)

def r_rcs() -> String:
  String.concat([r_rc1("uchar", S.uint8(), "(u32(V)&255u)"), r_rc1("ushort", S.uint16(), "(u32(V)&65535u)"),
    r_rc1("char", S.int8(), "(((i32(V)&255)^128)-128)"),
    r_rc1("short", S.int16(), "(((i32(V)&65535)^32768)-32768)"),
    r_rc1("int32", S.int32(), "i32(V)"), r_rc1("uint32", S.uint32(), "u32(V)"),
    r_rc1("float", S.single(), "f32(V)"), r_rc1("half", S.half(), "f16(V)")])

# -- the class constants ------------------------------------------------------
def r_consts() -> String:
  String.concat([r("barrier", barrier(), "workgroupBarrier();"), r("nan", nan(), "nan()"),
    r("supports_float4", bs(supports_float4()), "False"),
    r("global_max", String.join(u32_show(global_max()), ","), "65535,65535,65535"),
    r("local_max", String.join(u32_show(local_max()), ","), "256,256,64")])

# -- packed_field -------------------------------------------------------------
def r_pf3(+nm: String, +d: S.Dt, e: String, w: String, k: String) -> String:
  String.concat([r("pf_elems " ++ nm, U32.show(pf_elems(d)), e),
    r("pf_width " ++ nm, U32.show(pf_width(d)), w), r("pf_mask " ++ nm, U32.show(pf_mask(d)), k)])

def r_pfs() -> String:
  String.concat([r_pf3("uchar", S.uint8(), "4", "8", "255"), r_pf3("char", S.int8(), "4", "8", "255"),
    r_pf3("ushort", S.uint16(), "2", "16", "65535"), r_pf3("short", S.int16(), "2", "16", "65535"),
    r_pf3("half", S.half(), "2", "16", "65535"), r_pf3("int32", S.int32(), "1", "32", "4294967295")])

# -- packed_store's wmask ----------------------------------------------------
def r_wm(+mask: U32, +shift: U32, py: String) -> String:
  r("wmask " ++ U32.show(mask) ++ "_" ++ U32.show(shift), U32.show(ps_wmask(mask, shift)), py)

def r_wms() -> String:
  String.concat([r_wm(255, 0, "4294967040"), r_wm(255, 8, "4294902015"), r_wm(255, 16, "4278255615"),
    r_wm(255, 24, "16777215"), r_wm(65535, 0, "4294901760"), r_wm(65535, 16, "65535")])

# -- is_nan's five integers ---------------------------------------------------
def r_nan5(+nm: String, +d: S.Dt, b: String, e: String, m: String, k: String, t: String) -> String:
  String.concat([r("nan_bs " ++ nm, U32.show(nan_bs(d)), b), r("nan_e " ++ nm, U32.show(nan_e(d)), e),
    r("nan_m " ++ nm, U32.show(nan_m(d)), m), r("nan_mask " ++ nm, H.i64_dec(nan_mask(d)), k),
    r("nan_thr " ++ nm, H.i64_dec(nan_thr(d)), t)])

# `nan_mask` AND `nan_thr` ARE 64-BIT ANSWERS AND THEY PRINT IN DECIMAL, so the two
# lanes of each row now AGREE with CPython's own integers.  They used to be U32s and
# they used to differ: `nan_mask double` was 4294967295 where CPython says
# 9223372036854775807, and `nan_thr double` was 0 where CPython says
# 9218868437227405312.  **BOTH WERE THE SAME TRUNCATION** -- a U32 holding a 64-bit
# mask -- and both are gone now, because the defs above compute in `H.I64` and
# `H.i64_dec` prints the pair as the decimal CPython prints.
def r_nans() -> String:
  String.concat([r_nan5("float", S.single(), "32", "8", "23", "2147483647", "2139095040"),
    r_nan5("half", S.half(), "16", "5", "10", "32767", "31744"),
    r_nan5("bfloat16", S.bfloat16(), "16", "8", "7", "32767", "32640"),
    r_nan5("double", S.double(), "64", "11", "52", "9223372036854775807", "9218868437227405312")])

# `getattr(dtypes, f"uint{bs}")` -- the bitcast TARGET of the whole rule.
# THE `py=` HALVES HERE WERE THE C SPELLINGS (`unsigned int`, `unsigned short`,
# `unsigned long`) AND THIS `tinygrad/` ANSWERS THE RUST ONES. Measured against
# `gates/wgsl_render_census-oracle.py`, which reads `DType.name` off the class:
# `u32`, `u16`, `u64`. `selfcheck_hold()` re-derives the stale set on every run.
def r_nan_uint() -> String:
  String.concat([r("nan_uint float", dt_name(nan_uint(S.single())), "u32"),
    r("nan_uint half", dt_name(nan_uint(S.half())), "u16"),
    r("nan_uint double", dt_name(nan_uint(S.double())), "u64")])

# -- code_for_op --------------------------------------------------------------
def r_cfo1(+op: O.Op, py: String) -> String:
  r("code_for_op " ++ O.Ops.name.of(op), code_for_op.of(op, "A", "B", "C"), py)

def r_cfos() -> String:
  String.concat([r_cfo1(O.OpsSQRT{}, "sqrt(A)"), r_cfo1(O.OpsRECIPROCAL{}, "(1/A)"), r_cfo1(O.OpsNEG{}, "-A"),
    r_cfo1(O.OpsEXP2{}, "exp2(A)"), r_cfo1(O.OpsLOG2{}, "log2(A)"), r_cfo1(O.OpsSIN{}, "sin(A)"),
    r_cfo1(O.OpsTRUNC{}, "trunc(A)"), r_cfo1(O.OpsAND{}, "(A&B)"), r_cfo1(O.OpsXOR{}, "(A^B)"),
    r_cfo1(O.OpsOR{}, "(A|B)"), r_cfo1(O.OpsADD{}, "(A+B)"), r_cfo1(O.OpsSUB{}, "(A-B)"),
    r_cfo1(O.OpsMUL{}, "(A*B)"), r_cfo1(O.OpsCMOD{}, "(A%B)"), r_cfo1(O.OpsCDIV{}, "(A/B)"),
    r_cfo1(O.OpsFDIV{}, "(A/B)"),
    r_cfo1(O.OpsCMPNE{}, "(A!=B)"), r_cfo1(O.OpsSHR{}, "(A>>B)"), r_cfo1(O.OpsSHL{}, "(A<<B)"),
    r_cfo1(O.OpsCMPLT{}, "(A<B)"), r_cfo1(O.OpsCMPEQ{}, "(A==B)"), r_cfo1(O.OpsWHERE{}, "select(C,B,A)"),
    # The FALLTHROUGH is the row that matters most: upstream raises KeyError for an op with no arm,
    # so an unhandled op must not render as valid-looking WGSL. LOAD is chosen because it has no arm
    # and is an op a reader would expect to be absent (it never reaches a rendered kernel).
    r_cfo1(O.OpsLOAD{}, "UNHANDLED(Ops.LOAD)"),
    r_cfo1(O.OpsMAX{}, "UNHANDLED(Ops.MAX)"), r_cfo1(O.OpsPOW{}, "UNHANDLED(Ops.POW)")])

# -- code_for_workitem --------------------------------------------------------
def r_wi1(+k: String, isg: Bool, x: U32, py: String) -> String: r("workitem " ++ k, code_for_workitem(isg, x), py)

def r_wis() -> String:
  String.concat([r_wi1("g0", True{}, 0, "i32(gindex.x)"), r_wi1("g1", True{}, 1, "i32(gindex.y)"),
    r_wi1("g2", True{}, 2, "i32(gindex.z)"), r_wi1("l0", False{}, 0, "i32(lindex.x)"),
    r_wi1("l1", False{}, 1, "i32(lindex.y)"), r_wi1("l2", False{}, 2, "i32(lindex.z)")])

# the IndexError arm of `'xyz'[int(x)]`.
def r_wi_miss() -> String: r_wi1("l3", False{}, 3, "")

# -- supported_dtypes ---------------------------------------------------------
def r_sd1(+arch: String, py: String) -> String: r("supported_dtypes " ++ arch, sorted_names(supported_dtypes(arch)), py)

def r_sds() -> String:
  String.concat([r_sd1("", "bool,f32,i16,i32,i8,u16,u32,u8"),
    r_sd1("shader-f16", "bool,f16,f32,i16,i32,i8,u16,u32,u8")])

# -- the two dtype renderers --------------------------------------------------
def r_rds() -> String:
  String.concat([r("render_dtype float", render_dtype(S.single(), True{}), "var"),
    r("_render_dtype uchar global", _render_dtype(S.uint8(), 1, S.AGlobal{}, True{}, True{}, Nil{}), "var")])

# ===========================================================================
# THE `string_rewrite` ROWS -- 33 of them, one per rule ARM.
#
# `r_sr` is `r` with the `sr ` prefix, and the RENDERED SOURCE TEXT is spelled
# out in each call rather than held in a def: it stands in for the naming pass's
# `self.r[key]` dict (cstyle.py:207), and the oracle puts THE SAME LITERAL in
# that dict, so `bitcast<u32>(S&0xFF)` is what CPython said and not what this
# file believes CPython said.
# ===========================================================================
def r_sr(+nm: String, got: String, py: String) -> String: r("sr " ++ nm, got, py)

def r_srneg(i: U32, +nm: String, got: String, py: String) -> String:
  r("srneg " ++ U32.show(i) ++ " " ++ nm, got, py)

# THE SEVENTEEN REFUSALS. Each `srneg` row drives the SAME body as the `sr` row
# for the same rule, on a node CPython's `UPat` REJECTS -- the oracle asserts that
# rejection with `UPat.match`, so the row's `py=[NOMATCH]` half is a refusal by
# construction rather than a transcription. UNTIL THE PATTERNS LANDED THESE ROWS
# ANSWERED ANYWAY, and two of them answered WRONG: `srneg 14` is a PACKED store of
# an ordinary CONST, `packed_rmw`'s `AND` is the whole of rule 14's pattern, and
# `sr_rmw` emitted `atomicAnd(&B[1],W);` and DROPPED THE STORED VALUE; `srneg 15`
# is a GATED store, three srcs, and `sr_store` emitted `B = V;` and DROPPED THE
# GATE. Each row now hands the body the NODE it is refusing -- the dtype for the
# eleven rules whose pattern names one, the op for the three whose rejecting node
# is a CONST, the src count for the four that divide on arity -- and the body
# answers `NOMATCH`, which is the word CPython's `None` is spelled.
#
# THE ARGUMENTS ARE THE POSITIVE ROW'S OWN, so a `srneg` row changes the NODE and
# nothing else: the two rows for a rule differ only in whether the pattern would
# have accepted what the body was handed.
def r_srneg_0() -> String:
  String.concat([r_srneg(0, "cast i32", sr_idx(S.int32(), O.OpsINDEX{}, True{}, "B[1]"), "NOMATCH"),
    r_srneg(1, "neg f32", sr_neg(S.single(), "S"), "NOMATCH"),
    r_srneg(2, "cast i32", sr_cbool(S.int32(), True{}), "NOMATCH"),
    r_srneg(3, "cast i32", sr_cuint(S.int32(), H.i64_of_hi_lo(0, 3)), "NOMATCH"),
    r_srneg(4, "cast u32", sr_ci32(S.uint32(), H.i64_of_hi_lo(0, 3)), "NOMATCH"),
    r_srneg(5, "const", sr_buffer(O.OpsCONST{}, "data0_16", 16, S.uint8(), S.AGlobal{}), "NOMATCH"),
    r_srneg(6, "bitcast u32", sr_bhalf(S.uint32(), S.uint32(), "S"), "NOMATCH"),
    r_srneg(7, "bitcast half", sr_buchar(S.half(), "S"), "NOMATCH"),
    r_srneg(8, "bitcast uchar", sr_bchar(S.uint8(), "S"), "NOMATCH"),
    r_srneg(9, "bitcast half", sr_bushort(S.half(), S.uint32(), "S"), "NOMATCH"),
    r_srneg(10, "bitcast half", sr_bshort(S.half(), S.uint32(), "S"), "NOMATCH"),
    r_srneg(11, "const", sr_bany(O.OpsCONST{}, S.single(), "S"), "NOMATCH"),
    r_srneg(12, "load 2", sr_lgate(1, "B[1]", "B[1]", 16, S.uint8(), S.AGlobal{}, "V", "G"), "NOMATCH"),
    r_srneg(13, "load 3", sr_load(3, "B[1]", 16, S.uint8(), S.AGlobal{}), "NOMATCH"),
    r_srneg(14, "store u8", one_line(sr_rmw(O.OpsCONST{}, O.OpsINDEX{}, True{}, False{}, "B[1]", "W", "NV")), "NOMATCH"),
    r_srneg(15, "store 3", sr_store(3, "B", "V"), "NOMATCH"),
    r_srneg(16, "const", sr_index(O.OpsCONST{}, True{}, "B", "(I0+I1)"), "NOMATCH")])

# rules 0-2: the packed INDEX, the unsigned negation, the bool CONST
def r_sr_0() -> String:
  String.concat([r_sr("idx packed", sr_idx(S.uint32(), O.OpsINDEX{}, True{}, "B[1]"), "B[1]"),
    r_sr("idx plain", sr_idx(S.uint32(), O.OpsINDEX{}, False{}, "B[1]"), "NOMATCH"),
    r_sr("neg", sr_neg(S.uint32(), "X"), "(0-X)"),
    r_sr("cbool 1", sr_cbool(S.boolean(), True{}), "true"), r_sr("cbool 0", sr_cbool(S.boolean(), False{}), "false")])

# rules 3-4: the two CONST casts. THE FIXTURE IS THE WEAKINT CONST'S OWN VALUE AS
# AN I64, SPELLED `hi:lo`, because that is the one representation that tells -1
# from 4294967295 -- and the PINNED rule 3 renders BOTH of them `4294967295u`,
# which is why the AXIS and not the rendering is what these rows carry.
# `fixtures_hold` reads these three axes off this file's text, so an axis cannot
# drift on one side.
def r_cu1(+nm: String, hi: U32, lo: U32, py: String) -> String:
  r("sr cuchar " ++ nm, sr_cuint(S.uint32(), H.i64_of_hi_lo(hi, lo)), py)

def r_ci1(+nm: String, hi: U32, lo: U32, py: String) -> String:
  r("sr ci32 " ++ nm, sr_ci32(S.int32(), H.i64_of_hi_lo(hi, lo)), py)

def r_sr_3() -> String:
  String.concat([r_cu1("255", 0, 255, "255u"), r_cu1("-1", 4294967295, 4294967295, "4294967295u"),
    r_cu1("4294967295", 0, 4294967295, "4294967295u"), r_cu1("4294967296", 1, 0, "0u"),
    r_ci1("7", 0, 7, "7"),
    r_ci1("-3", 4294967295, 4294967293, "i32(-3)"), r_ci1("4294967295", 0, 4294967295, "i32(-1)"),
    r_ci1("4294967296", 1, 0, "0")])

# rule 5: the BUFFER prologue. `data0_16` is the packed GLOBAL uchar of the
# render_kernel fixture and `t0` is the LOCAL f32 beside it, so this axis is the
# same buffer set the module rows use.
def r_sb1(+nm: String, +bn: String, +d: S.Dt, a: S.Addr, n: U32, py: String) -> String:
  r("sr buffer " ++ nm, sr_buffer(O.OpsBUFFER{}, bn, n, d, a), py)

def r_sr_5() -> String:
  String.concat([r_sb1("global", "data0_16", S.uint8(), S.AGlobal{}, 16, "var data0_16: array<atomic<u32>,4>;"),
    r_sb1("local", "t0", S.single(), S.ALocal{}, 1, "var<workgroup> t0: array<f32,1>;"),
    r_sb1("reg", "r0", S.single(), S.AReg{}, 1, "var r0: array<f32,1>;")])

# rules 6-11: the six bitcast spellings, and the two rules with two arms.
# `sr bhalf`'s source is the `u32` of CPython's `UOp.const(1, dtypes.uint32)`,
# which is inside rule 6's `src=` clause, and `bushort half`'s is `f16` -- both
# are the SOURCE, which is why they are a second dtype and not a Bool.
def r_sr_6() -> String:
  String.concat([r_sr("bhalf", sr_bhalf(S.half(), S.uint32(), "S"), "bitcast<vec2<f16>>(S)[0]"),
    r_sr("buchar", sr_buchar(S.uint8(), "S"), "bitcast<u32>(S&0xFF)"),
    r_sr("bchar", sr_bchar(S.int8(), "S"), "((i32(S&0xFF)<<24)>>24)"),
    r_sr("bushort", sr_bushort(S.uint16(), S.int32(), "S"), "bitcast<u32>(S&0xFFFF)"),
    r_sr("bushort half", sr_bushort(S.uint16(), S.half(), "S"), "bitcast<u32>(vec2<f16>(S,0))"),
    r_sr("bshort", sr_bshort(S.int16(), S.int32(), "S"), "((i32(S&0xFFFF)<<16)>>16)"),
    r_sr("bshort half", sr_bshort(S.int16(), S.half(), "S"), "bitcast<i32>(vec2<f16>(S,0))"),
    r_sr("bany", sr_bany(O.OpsBITCAST{}, S.single(), "S"), "bitcast<f32>(S)")])

# rules 12-13: the gated load's `select`, and the plain load -- which IS
# `render_load`, called here through rule 13's own def because that is the rule's
# body plus its pattern. `3` is `UPat.load(b, v, gate)`'s src count and `1` is
# `UPat.load(b)`'s, and the two rules are the same node divided on it.
def r_sr_12() -> String:
  String.concat([r_sr("lgate packed", sr_lgate(3, "B[1]", "B[1]", 16, S.uint8(), S.AGlobal{}, "V", "G"),
      "select(V, atomicLoad(&B[1]), G)"),
    r_sr("lgate plain", sr_lgate(3, "B[1]", "B[1]", 16, S.single(), S.AGlobal{}, "V", "G"), "select(V, B[1], G)"),
    r_sr("load packed", sr_load(1, "B[1]", 16, S.uint8(), S.AGlobal{}), "atomicLoad(&B[1])"),
    r_sr("load plain", sr_load(1, "B[1]", 16, S.single(), S.AGlobal{}), "B[1]")])

# rules 14-15: the read-modify-write and the plain store. THE NEWLINE IS SPELLED
# by `one_line` on the port side and by the oracle's `one_line` on CPython's,
# because a row is one line and the two spaces after the newline are IN the
# f-string. `O.OpsAND{}` is `packed_rmw`'s outer op and `O.OpsCONST{}` is the
# `rmw plain` node's stored value, which is why that row is a refusal and not a
# second rendering.
#
# THE CAST CONSTRUCTOR AND THE INDEX CONSTRUCTOR ARE THE STORE'S BUFFER, and they
# are what the pinned rule-14 pattern discriminates on. `rmw nv` is CPython's OWN
# `packed_store` output, whose buffer is `word = idx.cast(dtypes.uint32)` -- a
# CAST -- so it IS rule 14. `rmw bare` is the same AND without the `new_v`, and
# its buffer is the INDEX under that CAST, so rule 14 REFUSES it and the row is
# a refusal. MEASURED, the two patterns are INVERTED over the two nodes: the
# pre-pin `UPat.store(UPat.var("b"), ...)` answered `atomicAnd(&B[1],W);` on
# `STORE(INDEX, AND)` and NOTHING on `STORE(CAST, AND)`, and the pinned one
# answers NOTHING on the first and `atomicAnd(&B[1],W);` on the second.
def r_sr_14() -> String:
  String.concat([r_sr("rmw nv", one_line(sr_rmw(O.OpsAND{}, O.OpsCAST{}, True{}, True{}, "B[1]", "W", "NV")),
      "atomicAnd(&B[1],W);\\n  atomicAdd(&B[1],NV);"),
    r_sr("rmw bare", one_line(sr_rmw(O.OpsAND{}, O.OpsINDEX{}, True{}, False{}, "B[1]", "W", "NV")), "NOMATCH"),
    r_sr("rmw plain", sr_rmw(O.OpsCONST{}, O.OpsINDEX{}, False{}, False{}, "B", "W", "NV"), "NOMATCH"),
    r_sr("store", sr_store(2, "B", "V"), "B = V;")])

# rule 16: the INDEX, and `strip_parens` on the `Ops.ADD` source. `(I0)+(I1)` is
# the BALANCE case: it opens and does not close, so the parens stay and the
# brackets land inside them.
def r_sr_16() -> String:
  String.concat([r_sr("index add", sr_index(O.OpsINDEX{}, True{}, "B", "(I0+I1)"), "B[I0+I1]"),
    r_sr("index const", sr_index(O.OpsINDEX{}, False{}, "B", "I0"), "B[I0]"),
    r_sr("index unbalanced", sr_index(O.OpsINDEX{}, True{}, "B", "(I0)+(I1)"), "B[(I0)+(I1)]")])

# THE ORDER, AS THREE ROWS, and they are the only rows here that are not a
# rendered string. CPython's `PatternMatcher.rewrite` answers the FIRST pattern
# that matches, so "which rule" is a fact about the table and not about a body --
# and the two places it is not obvious are the bitcast catch-all (rule 11 has NO
# dtype, so it is safe only because rules 6..10 come first) and the store pair
# (rule 14's pattern is a SUBSET of rule 15's, so a plain packed store FALLS
# THROUGH to 15). The comma-joined text is the file's own idiom for a tuple of
# ints (`rk_sz mixed` is `8,2`), and the whole index list is one cell so a single
# moved element moves the row. THE SEVENTH BITCAST IS `half` FROM `half`, which
# is rule 6's `src=` clause doing its work, and the store row's SECOND element is
# the `rmw plain` node -- the fall-through, as an index.
def r_sr_pick() -> String:
  String.concat([r_sr("pick bitcast", String.join(u32_show([sr_pick_bitcast(S.half(), S.uint32()),
    sr_pick_bitcast(S.uint8(), S.uint32()), sr_pick_bitcast(S.int8(), S.uint32()),
    sr_pick_bitcast(S.uint16(), S.uint32()), sr_pick_bitcast(S.int16(), S.uint32()),
    sr_pick_bitcast(S.single(), S.half()), sr_pick_bitcast(S.half(), S.half())]), ","),
    "6,7,8,9,10,11,11"),
    r_sr("pick load", String.join(u32_show([sr_pick_load(3), sr_pick_load(1)]), ","), "12,13"),
    r_sr("pick store", String.join(u32_show([sr_pick_store(2, O.OpsAND{}, O.OpsCAST{}),
      sr_pick_store(2, O.OpsCONST{}, O.OpsINDEX{})]), ","), "14,15")])

def r_srs() -> String:
  String.concat([r_sr_0(), r_sr_3(), r_sr_5(), r_sr_6(), r_sr_12(), r_sr_14(), r_sr_16(), r_sr_pick()])

def rows() -> String:
  +fx = fx_mixed()
  String.concat([r_tms(), r_tm_miss(), r_rcs(), r_consts(), r_pfs(), r_wms(), r_nans(), r_nan_uint(),
    r_cfos(), r_wis(), r_wi_miss(), r_sds(), r_rds(), r_pk_all(), r_ps_all(), r_rk_sz_pad(), r_rk_sz(fx), r_rk_half(fx),
    r_rk_half_no(O.Arena.empty()), r_bd(), r_pt(), r_rk_alu(), r_rk_mixed(fx), r_rk_empty(), r_srs(), r_srneg_0()])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(rows())

# ===========================================================================
# THE MUTATION TABLE. Measured 2026-10-02 with
# `.agents/slop/wgsl-mutate.py`, one textual edit at a time, each row diffed
# against the unmutated 168. "moved" is the number of rows that changed; the
# driver prints which.
#
#   M1  is_packed ANDs addr_is_reg instead of negating it   36
#   M2  is_packed drops the `dt != half` clause               6
#   M3  is_packed drops the `itemsize < 4` clause           11
#   M4  bd_go conses instead of appends                      3  rk_bindings rk alu rk mixed
#   M5  pt.go appends instead of conses                      3  rk_body rk alu rk mixed
#   M6  u32_show appends instead of conses                   2  local_max rk_sz mixed
#   M7  (the no-op control)                                    0
#   M8  the colon after the name gains a space               3
#   M9  var<storage> loses ,read_write                       3
#   M10 a packed buffer is not atomic                       FAIL  compile
#   M11 atomicLoad loses its &                                0  <-- BLIND SPOT
#   M12 the barrier loses its semicolon                       0  <-- BLIND SPOT
#   M13 WHERE renders the ternary, not select                1
#   M14 render_cast's unsigned narrow loses its `u`          2
#   M15 render_cast's signed narrow stops sign-extending     2
#   M16 the f16 enablement is dropped                       FAIL  compile
#   M17 (the INFINITY colon)                                  -  pattern not found
#   M18 the nan() helper leaves the prologue                  3
#   M19 the workgroup_size fallback is 0, not 1               1
#   M20 the local-size sort never compares                    0  <-- BLIND SPOT
#   M21 the hoist looks for var<uniform>                      1
#   M22 the hoisted line is not lstripped                     1
#   M23 the binding number starts at 0, not 1                 3
#   M24 the vec3 builtins lose their type                    3
#   M25 elems is the itemsize, not 4/itemsize                 5
#   M26 width is 4*itemsize, not 8*itemsize                  12
#   M27 wmask xors with 0, not 0xFFFFFFFF                    6
#   M28 the nan threshold shifts by exp, not mant             4
#   M29 the nan mask is 2^bits, not 2^(bits-1)                3
#   M30 type_map sends uchar to i32                           3
#   M31 (the workitem axis letter)                            -  pattern not found
#   M32 supported_dtypes always includes half                 1
#   M33 _render_dtype spells f32, not the storage class 2
#   M34 ssimp's CAST-of-CONST arm is dropped             2
#   M35 the f16 test compares against float             2
#   M36 a global buffer takes the var<uniform> arm       3
#
# M37-M54 AND P1-P9 ARE `string_rewrite`, MEASURED 2026-10-14 BY
# `gates/wgsl_render_census-mutate.py`, which mutates a COPY of this file beside
# the original (a copy anywhere else cannot even warm: the imports are relative
# to the file's own path) and runs the whole gate per mutation. That harness is
# the second half of the gate: a mutation that moves nothing is a claim nothing
# checks. The numbers below are the ROWS THAT MOVED, one per mutation.
#
#   M37 sr_buchar's mask is 0xFF00                1  sr buchar
#   M38 sr_bchar's shift is <<8                   1  sr bchar
#   M39 sr_bshort stops sign-extending            1  sr bshort
#   M40 sr_bany drops the type argument           1  sr bany
#   M41 sr_bushort's half arm loses its vec2      1  sr bushort half
#   M42 sr_rmw's atomicAdd loses its newline      1  sr rmw nv
#   M43 sr_lgate's select is a ternary            2  sr lgate packed sr lgate plain
#   M44 sr_index never strips parens              1  sr index add
#   M49 sr_idx's guard is dropped                 1  sr idx plain
#   M50 sr_ci32 truncates to 64 bits             2  sr ci32 4294967295 sr ci32 4294967296
#   M51 sr_cuint forgets the u32 mask             2  sr cuchar -1, sr cuchar 4294967296
#   M52 sr_buffer drops the space after the colon 3  sr buffer global/local/reg
#   M53 ssimp walks ONE cast, not the chain       2  rk_sz mixed rk mixed
#   M54 type_map's KeyError arm answers nothing   1  type_map double, via the PIN check
#
# M55-M63 ARE THE SEVENTEEN PATTERNS, one edit per DISCRIMINATING FIELD, and each
# moves EXACTLY ONE `srneg` row -- the row for the rule it breaks. MEASURED
# 2026-10-14 on this tree, one row each, and they are what makes the seventeen
# `NOMATCH`s load-bearing rather than seventeen tokens nobody could tell apart.
#
#   M55 sr_bhalf ANDs half with src=, so it ORs   1  srneg 6
#   M56 sr_pick_bitcast drops rule 6's src=       1  sr pick bitcast (11 -> 6)
#   M57 sr_pick_store forgets packed_rmw's AND    0  BLIND SPOT, see THE PIN
#   M58 sr_rmw forgets packed_rmw's AND           0  BLIND SPOT, see THE PIN
#   M59 sr_store accepts a 3-src GATED store      1  srneg 15, DROPS THE GATE AGAIN
#   M60 sr_buffer forgets the BUFFER op           1  srneg 5
#   M61 sr_load accepts any src count             1  srneg 13
#   M62 sr_idx forgets the CAST dtype             1  srneg 0
#   M63 sr_neg accepts float32 as an unsigned     1  srneg 1
#   M64 sr_rmw_cast forgets the CAST              1  sr rmw bare
#   M65 sr_rmw_cast refuses every buffer          2  sr pick store, sr rmw nv
#
# M59 IS THE DANGEROUS ONE NOW, and it is worth reading with M64: M59 reinstates a
# SILENT WRONG ANSWER rather than an over-firing -- a gated store whose gate is
# dropped -- and it shows in a diff of the two lanes' row NAMES only.
# M64 AND M65 ARE THE PIN'S OWN, and they are the two mutations that say the new
# predicate is load-bearing: M64 (`sr_rmw_cast` forgets the CAST) moves `sr rmw
# bare`, and M65 (`sr_rmw_cast` refuses every buffer) moves `sr pick store` AND
# `sr rmw nv`.
#   P1 the port drops rule 16's whole row group   DEAD  5, "207 rows" expected
#   P2 the port drops ONE row from a group        DEAD  5, "207 rows" expected
#   P3 the ORACLE drops one rule's rows          REFUSED 3, "207 rows" expected
#   P4 the port RENAMES a row (same count)        1  sr bushort half
#   P5 the pins lose a pinned divergence          1  code_for_op LOAD
#   P6 a pin's PORT VALUE is edited               1  type_map double, "appears 0 times"
#   P7 the port's fixture axis drifts              0  BLIND SPOT, see THE PIN
#   P8 the oracle's fixture axis drifts            0  fixtures_hold: SR_CI
#   P9 the port DUPLICATES a row name              1  sr bany
#
# P1-P9 ARE THE POPULATION MUTATIONS, and they are the ones this file could not
# have found by reading. P7 and P8 drift the `r_cu1`/`r_ci1` AXIS -- the `(name,
# hi, lo)` triples `fixtures_hold` reads out of this text -- and P7 moves a row
# while P8 moves NOTHING and is caught only by the axis check, which is the
# answer to "an oracle that covers whatever the port happens to do is not an
# oracle". P9 keeps the row COUNT at 207 and still goes red, by NAME.
#
# M51 IS THE ONE A READING MISSED AND A MUTATION CAUGHT. `sr_cuint`'s
# `& 0xFFFFFFFF` is only observable on a weakint CONST whose HIGH WORD is set
# and whose low word reads as non-negative; the original three axis rows all had
# `hi == 0`, so replacing `masked(v)` with `v` left every one of them unchanged
# and the gate was GREEN on a mutation. The `4294967296` row is the fix and it
# was added because the mutation table said so, not because the code looked
# wrong. IT NOW MOVES TWO ROWS, and the second one is the PIN's: rule 3 has no
# negative arm, so a weakint CONST of -1 is masked to `4294967295u` and the mask
# is observable on it too.
#
# ===========================================================================
# THE PIN, AND THE THREE BLIND SPOTS IT OPENED.
#
# `tinygrad/renderer/wgsl.py` MOVED under this port, and TWO of its changes
# touch the rows: `string_rewrite`'s rule 3 lost its negative-const arm and
# rule 14's STORE pattern gained a `CAST` on its buffer. MEASURED, the two
# patterns are INVERTED over the two nodes -- the pre-pin rule 14 answered
# `atomicAnd(&B[1],W);` on `STORE(INDEX, AND)` and NOTHING on `STORE(CAST,
# AND)`, and the pinned one answers NOTHING on the first and `atomicAnd(&B[1],
# W);` on the second -- so this file's `sr rmw bare` row is a REFUSAL now, and
# `sr rmw nv` still renders the pair.
#
# THE THREE BLIND SPOTS ARE ALL THE SAME ONE: THE RULE-14 PREDICATE IS NOW THREE
# CLAUSES AND NO FIXTURE ISOLATES THE SECOND. `sr_pick_store` and `sr_rmw` test
# the src COUNT, the VALUE's op (`Ops.AND`) and the BUFFER's op (`Ops.CAST`),
# and the oracle's three rule-14 fixtures are `rmw nv` (AND, CAST), `rmw bare`
# (AND, INDEX) and `rmw plain` (CONST, INDEX): every one of them is refused by
# the CAST clause or by the AND clause or by BOTH, so removing EITHER clause
# alone changes no row. MEASURED 2026-10-22: M57 and M58 move 0 rows, where
# they moved 1 each before the pin. THE FIX IS AN ORACLE FIXTURE, not a port
# fix -- a fourth rule-14 node whose buffer IS a CAST and whose value is NOT an
# AND -- and it needs a row on both sides.
#
# P7 IS THE SAME SHAPE FROM THE OTHER END. Rule 3 renders a weakint CONST of -1
# and one of 4294967295 as the SAME `4294967295u`, so drifting the `-1` axis
# entry's high word changes no row: MEASURED, P7 moves 0 rows where it moved 1.
# The AXIS still carries -1 because the WEAKINT value is still a different one,
# and `fixtures_hold` compares the axis and not the rendering -- so the axis is
# right and the MUTATION is blind.
#
# THE PLANTS, and they are the same harness the mutation table uses: a COPY of
# this file beside the original, one edit, and the rows that moved.
#
#   PLANT A  rule 3 regains the pre-pin negative arm    1  sr cuchar -1
#   PLANT B  `sr_rmw_cast` always true (pre-pin rule 14) 1  sr rmw bare
#
# A PLANT THAT MOVES NOTHING IS A HOLE, so A and B are the two claims that the
# pin's two changes are load-bearing, and they are the two the gate's lane diff
# would otherwise have caught silently.
# ===========================================================================
#
# WHAT THE TABLE SAYS, and the three things it caught that the rows did not.
#
# M1 IS THE ONE THAT MATTERS. It is the bug this file SHIPPED with for an hour:
# `is_packed` ANDed `addr_is_reg` where wgsl.py:32 negates it, so the predicate
# said "packed iff REGISTER" and the entire packed path -- `atomic<u32>`,
# `atomicLoad`, the `atomicAnd`/`atomicAdd` read-modify-write -- was dead, because
# no buffer a shader reads is a register. It typechecked. Every `pf_*` row, every
# `wmask` row and all 100-odd other rows stayed green. Only `rk mixed` moved, and
# only on ONE line of a 700-character module. THE FIXTURE CLASS THIS FILE WAS
# MISSING IS A PREDICATE WITH NO ROW: `is_packed` had none, so no mutation could
# find it, and the 40 `is_packed`/`buf_map`/`packed_size` rows exist because of
# that. M1 now moves 36.
#
# M4, M5 AND M6 ARE THE ORDER MUTATIONS, and they are three rows each -- which is
# the localisation the brief asks for. `bd_go` and `pt.go` reach `String.join`
# and so must APPEND; `u32_show` and `ls_sz` are WALKED and so must PREPEND. Each
# wrong choice reverses a WHOLE SHADER and is invisible in a boolean.
#
# FIVE BLIND SPOTS LEFT, and they are the honest content of this table. TWO OF
# THEM ARE THE PIN'S -- M57, M58 and P7, and they are in THE PIN block above
# with the reason and the fix.
#
#   M11's BLIND SPOT IS GONE. It moved nothing because `render_load` had NO ROW
#   AT ALL -- it was ported, called by nothing in this file (the string rule that
#   calls it is `string_rewrite`, which was the wall), and ungated. `render_load`
#   now has FOUR rows, `sr lgate packed`, `sr lgate plain`, `sr load packed` and
#   `sr load plain`, and M43 moves two of them by mutating its one caller.
#   M12 still moves nothing: `barrier()` has a row, but M12's edit did not reach
#   it, and that is a property of the EDIT and not of the row.
#   M20 moves nothing because `ls_ins`'s no-compare arm appends, and the fixture's
#   WALK order (l0, l1) already agrees with its SORT order. The fixture needs a
#   case whose walk order DIFFERS from its sort order -- a `uops` list holding l1
#   before l0 -- and then M20 says `2,8`. That is the brief's two-rules-claim-one-
#   node trap in its purest form, and this table is the evidence that the trap is
#   still open here. THE ORACLE HAS THE CASE and asserts it (`UOPS_MIXED_SWAPPED`
#   in `gates/wgsl_render_census-oracle.py`, whose `assert` names "the sort is not
#   load-bearing"), so the gap is on the PORT's side only.
#   M7 is the control: an edit that changes nothing must move nothing.
#
# TWO MUTATIONS FAIL TO COMPILE rather than moving rows, and that is information
# too: `buf_map`'s two arms must both be `String` (M10) and `rk_f16`'s arms must
# both be `String` (M16), so those two constants are pinned by the type system as
# well as by the text. Two more (M17, M31) did not find their pattern and are
# recorded as untested rather than as passing.
#
# WHAT IS STILL NOT GATED, stated as a boundary and not as an omission. The
# census compares each RULE'S ANSWER on a chosen fixture AND, since the patterns
# landed, whether the rule DECLINES a node CPython's own `UPat` declines -- the
# seventeen `srneg` rows, one per rule, each an EXACT MATCH rather than a pin
# because both sides print `NOMATCH`. Three things are still outside it.
#
# 1. `packed_rmw`'s INNER shape. `sr_pick_store` and `sr_rmw` test `Ops.AND`,
#    which is `packed_rmw`'s outer op and the whole of what distinguishes a
#    read-modify-write from a plain store, and the pin's THIRD predicate -- the
#    store's buffer being a CAST -- which is `sr_rmw_cast`; but
#    `AND(LOAD(CAST(b, u32)), wmask)` -- the `& UPat.var("wmask")` is an Ops.AND
#    and not a bind -- is still unported, and `prw_of` is still the def that
#    names it and calls nothing. A CONST spliced onto an `AND` of the wrong
#    shape would still pass.
# 2. RULES 0, 2, 3 AND 4 SHARE AN OP and their dtypes are NOT all disjoint --
#    rule 0 is `uint32` and rule 3 is `uint32 | uint16 | uint8` -- so they divide
#    on src[0]'s op as well, and the ORDER between them is untested because they
#    cannot both match one node. Same for rules 12 and 13 (`sr pick load` prints
#    the indices anyway, because the fact is worth having).
# 3. THE SPELLING OF EACH `srneg` NODE is the port's own. The oracle ASSERTS, on
#    CPython's real node, that each `UPat` rejects it -- so the refusal is real on
#    that side -- but the gate does not re-derive `srneg 6`'s target dtype from
#    the node and compare it to `S.uint32()` in this file. Both sides refusing is
#    checked; both sides refusing about the SAME node is not.
#
# ===========================================================================
