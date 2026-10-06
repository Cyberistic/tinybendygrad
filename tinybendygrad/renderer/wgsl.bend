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
#   TODO(p3) wgsl.py:23  packed_load  -- ditto, plus `.index`
#   TODO(p3) wgsl.py:34  is_nan       -- ditto (`.bitcast` and the compare)
#   TODO(p3) wgsl.py:41  wgsl_matcher -- ditto; the seven RULES return arenas,
#                                  so a rule table here would have nothing to
#                                  return but the input it was handed
#
# `ops.bend` named the sugar in its own NOT PORTED block (`UOp.cast`,
# `UOp.bitcast`, `UOp.index`, `UOp.load`, `UOp.store`, `UOp.where` were all
# `TODO(p3) ops.py:<line>`). `UOp.cast` IS NOW PORTED at `ops.bend:2783`, the
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
#   :65  string_rewrite the sixteen WGSL rules, in Python's order
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
# of each row is CPython's value, measured 2026-10-01 on this `tinygrad/` by
# `.agents/slop/wgsl-oracle.py`, and the two lanes print the SAME LINE, so the
# diff of the two lanes is empty iff every claim holds.
#
#   ./bin/bend tinybendygrad/renderer/wgsl.bend
#   python3 .agents/slop/wgsl-oracle.py rows > /tmp/py.txt
#   ./bin/bend tinybendygrad/renderer/wgsl.bend > /tmp/bd.txt
#   diff /tmp/bd.txt /tmp/py.txt
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

# `(1 << (bs - 1)) - 1`. THE WIDTH LIMIT IS REAL: double's is 2^63-1 and a U32
# holds 2^32-1, so `U32.shln(1, 63n)` wraps to 0 and this answers 4294967295
# where CPython answers 9223372036854775807. Every dtype `wgsl_matcher` calls
# `is_nan` on is in `dtypes.floats` AND must be in `supported_dtypes` to render
# at all, and WGSL's `type_map` has no double, so the overflowing width is
# unreachable from this renderer. The gate says so out loud: `nan_mask double`
# is the one row whose two lanes DIFFER, and it is left printing.
def nan_mask(+dt: S.Dt) -> U32: U32.sub(U32.shln(1, Nat.sub(U32.to_nat(nan_bs(dt)), 1n)), 1)

# `((1 << exp) - 1) << mant`
def nan_thr(+dt: S.Dt) -> U32: U32.shln(U32.sub(U32.shln(1, U32.to_nat(nan_e(dt))), 1), U32.to_nat(nan_m(dt)))

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
def wi_axis.of2(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}  : ""

def wi_axis(x: U32) -> String: wi_axis.of2(wi_axis.of(x))

def code_for_workitem.ret(isg: Bool, m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: String.concat(["i32(", Bool.pick(String, isg, "gindex", "lindex"), ".", s, ")"])
    case None{}  : ""

def code_for_workitem(isg: Bool, x: U32) -> String: code_for_workitem.ret(isg, wi_axis.of(x))

# :62 `type_map`. Nine dtypes, and a KeyError for every other one. The `case _:`
# arm is that KeyError: `supported_dtypes` below is the gate that keeps it
# unreachable, and a WGSLRenderer asked for a double must fail rather than
# silently emit a name the shader cannot parse.
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
        case _ : ""

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

# `u.src[0].ssimplify()` -- ops.py:1384, a symbolic fold. A local bound in a
# compiled kernel is `CAST(int, CONST(n))` or a bare CONST, and symbolic
# folding the first is a CONST, so those two arms are the port. Anything else
# is the wall: `graph_rewrite(u, symbolic)` is a rewrite ENGINE call, and
# codegen/symbolic.bend does not export one a renderer can call.
def ss_is(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsCONST{})

def ss_val.of(a: O.Arg) -> U32:
  match a:
    case O.APy{O.CInt{i}}: H.lo32(i)
    case _                 : 0

def ss_val(ar: O.Arena, +x: U32) -> U32: ss_val.of(O.Arena.arg(ar, x))

def ss_of(ar: O.Arena, +x: U32) -> U32: ss_val(ar, x)

# the `CAST(int, CONST(n))` arm, and the `nope` default of the CONST arm above.
def ssimp(+ar: O.Arena, +x: U32) -> U32:
  Bool.pick(U32, ss_is(ar, x), ss_of(ar, x),
    Bool.pick(U32, O.eq_op(O.Arena.op(ar, x), O.OpsCAST{}) && ss_is(ar, O.Arena.src0(ar, x)),
      ss_of(ar, O.Arena.src0(ar, x)), 0))

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
# would not be in it. `l0`'s bound is `CAST(weakint, CONST(8))` -- NOT a bare
# CONST -- so `ssimp`'s CAST-of-CONST arm is what reads it, exactly as
# `codegen/gpudims.py:37` and `ops.py:1382` leave it.
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
  +k8 = f_cast_dt(c8, S.weakint())
  +s0 = O.UOp.special(O.Found.ar(k8), O.Found.i(k8), "l0")
  +c2 = f_const(O.Found.ar(s0), 2)
  +k2 = f_cast_dt(c2, S.weakint())
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

# the KeyError arm. `supported_dtypes` is what keeps it unreachable from a real
# kernel, and THIS row is the arm that would emit a name no WGSL parser knows.
def r_tm_miss() -> String: r_tm1("double", S.double(), "")

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
    r("nan_m " ++ nm, U32.show(nan_m(d)), m), r("nan_mask " ++ nm, U32.show(nan_mask(d)), k),
    r("nan_thr " ++ nm, U32.show(nan_thr(d)), t)])

# THE TWO ROWS WHOSE TWO LANES DIFFER, and they are left printing. `nan_mask
# double` is 2^63-1 and `nan_thr double` is 2047<<52; a U32 holds 2^32-1, so the
# Bend lane says 4294967295 and 0 -- and the `py=` half of each row carries
# CPython's value, so the diff is the overflow and nothing else. The header says
# why the width is unreachable from a WGSLRenderer (no double in `type_map`, none
# in `supported_dtypes`). A row that quietly agreed with itself would be the
# dishonest choice.
def r_nans() -> String:
  String.concat([r_nan5("float", S.single(), "32", "8", "23", "2147483647", "2139095040"),
    r_nan5("half", S.half(), "16", "5", "10", "32767", "31744"),
    r_nan5("bfloat16", S.bfloat16(), "16", "8", "7", "32767", "32640"),
    r_nan5("double", S.double(), "64", "11", "52", "9223372036854775807", "9218868437227405312")])

# `getattr(dtypes, f"uint{bs}")` -- the bitcast TARGET of the whole rule.
def r_nan_uint() -> String:
  String.concat([r("nan_uint float", dt_name(nan_uint(S.single())), "unsigned int"),
    r("nan_uint half", dt_name(nan_uint(S.half())), "unsigned short"),
    r("nan_uint double", dt_name(nan_uint(S.double())), "unsigned long")])

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
  String.concat([r_sd1("", "bool,float,int,short,signed char,unsigned char,unsigned int,unsigned short"),
    r_sd1("shader-f16", "bool,float,half,int,short,signed char,unsigned char,unsigned int,unsigned short")])

# -- the two dtype renderers --------------------------------------------------
def r_rds() -> String:
  String.concat([r("render_dtype float", render_dtype(S.single(), True{}), "var"),
    r("_render_dtype uchar global", _render_dtype(S.uint8(), 1, S.AGlobal{}, True{}, True{}, Nil{}), "var")])

def rows() -> String:
  +fx = fx_mixed()
  String.concat([r_tms(), r_tm_miss(), r_rcs(), r_consts(), r_pfs(), r_wms(), r_nans(), r_nan_uint(),
    r_cfos(), r_wis(), r_wi_miss(), r_sds(), r_rds(), r_pk_all(), r_ps_all(), r_rk_sz_pad(), r_rk_sz(fx), r_rk_half(fx),
    r_rk_half_no(O.Arena.empty()), r_bd(), r_pt(), r_rk_alu(), r_rk_mixed(fx), r_rk_empty()])

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
#   M33 _render_dtype spells f32, not the storage class       2
#   M34 ssimp's CAST-of-CONST arm is dropped                  2
#   M35 the f16 test compares against float                  2
#   M36 a global buffer takes the var<uniform> arm            3
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
# FOUR BLIND SPOTS, and they are the honest content of this table.
#
#   M11 and M12 move NOTHING because `render_load` and `barrier` have no row that
#   a mutation of their BODY can move: `barrier()` has a row, but M12's edit did
#   not reach it, and `render_load` has NO ROW AT ALL -- it is ported, called by
#   nothing in this file (the string rule that calls it is `string_rewrite`, the
#   wall), and ungated. `render_load` is the next row to add.
#   M20 moves nothing because `ls_ins`'s no-compare arm appends, and the fixture's
#   WALK order (l0, l1) already agrees with its SORT order. The fixture needs a
#   case whose walk order DIFFERS from its sort order -- a `uops` list holding l1
#   before l0 -- and then M20 says `2,8`. That is the brief's two-rules-claim-one-
#   node trap in its purest form, and this table is the evidence that the trap is
#   still open here.
#   M7 is the control: an edit that changes nothing must move nothing.
#
# TWO MUTATIONS FAIL TO COMPILE rather than moving rows, and that is information
# too: `buf_map`'s two arms must both be `String` (M10) and `rk_f16`'s arms must
# both be `String` (M16), so those two constants are pinned by the type system as
# well as by the text. Two more (M17, M31) did not find their pattern and are
# recorded as untested rather than as passing.
# ===========================================================================
