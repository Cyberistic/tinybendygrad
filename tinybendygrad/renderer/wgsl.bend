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

import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H

# :7  sign_extend -- `(val << (32-width)).bitcast(dtypes.i32) >> (32-width)`.
#
# "a field of `width` bits sitting in the low bits of val: shift it up to the
# sign bit, then let the arithmetic shift fill" -- wgsl.py:6, upstream's

def se_shift(width: U32) -> U32: U32.sub(32, width)

# THE TABLE IS IN `.agents/slop/tables/renderer-wgsl-136.md` -- :10  packed_field -- `elems, width = 4//dt.itemsize, 8*dt.itemsize` and the

def pf_elems(+dt: S.Dt) -> U32: U32.div(4, S.Dt.itemsize(dt))

def pf_width(+dt: S.Dt) -> U32: U32.mul(8, S.Dt.itemsize(dt))

def pf_mask(+dt: S.Dt) -> U32: U32.sub(U32.shln(1, U32.to_nat(pf_width(dt))), 1)

# :15  packed_store -- `wmask = ((mask << shift_am) ^ 0xFFFFFFFF)`.
#
# "store for char: buf[idx/4] <- (var << (idx%4)*8))" -- wgsl.py:14, upstream's

def ps_wmask(mask: U32, shift: U32) -> U32: U32.xor(U32.shln(mask, U32.to_nat(shift)), 4294967295)

# :30  is_packed -- `dt.itemsize < 4 and dt != dtypes.f16 and

def addr_is_reg(a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

# THE THIRD CLAUSE IS NEGATED, and the gate caught it inverted the first time
# this was written: ANDing `addr_is_reg` here says "packed iff the buffer is a
# REGISTER", which is the exact opposite of wgsl.py:32 and makes the whole
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

# :33  _packed_size -- `ceildiv(u.max_numel(), 4//u.dtype.itemsize) if
# is_packed(u) else u.max_numel()`. `max_numel` is a PARAMETER here for the
# reason `is_packed`'s is: it is read off the UOp, and `Buf` is the projection
# of a UOp this file needs. `w_numel` below is the reader.

def packed_size(+n: U32, +dt: S.Dt, addr: S.Addr) -> U32:
  Bool.pick(U32, is_packed(dt, addr), H.ceildiv_u32(n, pf_elems(dt)), n)

# `max_numel` -- the product of the shape's dims. `F.fold.shape` answers
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

# :34  is_nan -- `(a.bitcast(uint{bs}) & ((1 << (bs - 1)) - 1)) >
# (((1 << exp) - 1) << mant)`. The bitcast and the compare are the wall; the
# FIVE INTEGERS are not, and they are the whole rule: the mask is the sign bit
# cleared and the threshold is the largest finite magnitude.
#
# WHY THE RULE EXISTS AT ALL, AND IT IS TWO DIFFERENT RULES WITH THE SAME

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

# `(1 << (bs - 1)) - 1`. THE MASK IS 64 BITS WIDE AND IT IS COMPUTED AT 64 BITS.
#
# WAS.  The old body was `U32.sub(U32.shln(1, Nat.sub(U32.to_nat(nan_bs(dt)), 1n)), 1)`
# -- a U32 -- and `U32.shln` SATURATES past 31 (`helpers.bend:1759`), so for a double
# `U32.shln(1, 63n)` is 0 and `U32.sub(0, 1)` is 4294967295.  CPython's mask is
# `(1 << 63) - 1` = 9223372036854775807.  The old comment here said "THE WIDTH LIMIT
# IS REAL ... the overflowing width is unreachable from this renderer", and that was
# an argument that a wrong answer was harmless because no WGSL shader can ask for a
# double.  a wrong answer that nothing asks for is still a wrong answer, and
# the census that runs this file found it: `nan_mask double` was one of four rows
# whose two halves disagreed.
#
# so the answer is a `H.I64` -- the pair of 32-bit words `helpers.bend` already
# carries (`i64_shl`, `i64_sub`) -- and the row prints it with `H.i64_dec`, the
# DECIMAL printer `helpers.bend:2130` already carries.  CPython's `1 << 63` is an
# ARBITRARY-PRECISION int and this is the 64-BIT answer to the same expression, which
# is the same number for every dtype `wgsl.py:36` can ask about: the widest is
def nan_mask(+dt: S.Dt) -> H.I64:
  H.i64_sub(H.i64_shl(H.i64_one(), Nat.sub(U32.to_nat(nan_bs(dt)), 1n)), H.i64_one())

# `((1 << exp) - 1) << mant`. the same width, the same way.  The old body was a
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

# :39  packed_rmw -- the read-modify-write a packed_store emits:
# `UPat(Ops.LOAD, src=(UPat(Ops.CAST, dtype=uint32, src=(UPat.var("b"),)),),
# allow_any_len=True) & UPat.var("wmask")`.
#
# "the read-modify-write packed_store emits: a load of the very index being
# stored to, masked (a gated store loads with 3 srcs)" -- wgsl.py:39,
# upstream's comment ON IT. TWO FACTS AND THE SECOND IS A GOTCHA:
#   * THE RMW LOADS **THE VERY INDEX BEING STORED TO**. IT IS NOT A LOAD OF
#     THE WHOLE BUFFER AND NOT A LOAD OF SOMETHING ELSE: THE READ-MODIFY-
#     WRITE IS OF ONE **WORD**, AND THE WORD IS THE ONE THE STORE HITS.
#     SO THE PATTERN IS Pinned TO THE `Ops.LOAD` THAT `packed_store` ITSELF
#     EMITTED, AND THE `& UPat.var("wmask")` BINDS THE MASK THAT COMES WITH
#     IT.
#   * "A GATED STORE LOADS WITH 3 SRCS." A GATED LOAD -- ONE WITH AN `alt`
#     AND A `gate` -- HAS **THREE** SRCS WHERE AN UNGATED ONE HAS ONE. SO
#     THE PATTERN'S `allow_any_len=True` IS NOT COSMETIC: WITHOUT IT THE
#     PATTERN WOULD MATCH ONLY THE UNGATED SHAPE AND EVERY GATED PACKED
#     STORE WOULD FALL THROUGH TO THE PLAIN STORE RULE AND LOSE THE
#     ATOMIC.
#
# `allow_any_len` is a LENGTH CLAUSE, not a repetition: the LOAD may carry any
# number of srcs and only src[0] is constrained, and the CAST is exact-length-1
# (`allow_any_len` is absent). The trailing `& UPat.var("wmask")` is the table's
# BIND, not a guard, so it is not part of the predicate -- and that is
# load-bearing in the other direction too: `string_rewrite`'s store rule takes
# the mask as a SECOND binder, so the same LOAD matches with or without it.

def prw_is(ar: O.Arena, u: U32) -> Bool: O.eq_op(O.Arena.op(ar, u), O.OpsLOAD{})

# the inner UPat, and `allow_any_len` is ABSENT here, so the CAST's src count is
# pinned at one. A gated load's src[0] is still the CAST, which is why the outer
# clause is the only one that is a length clause at all.
def prw_cast(+ar: O.Arena, +tb: F.Table, +c: U32) -> Bool:
  Bool.and(Bool.and(O.eq_op(O.Arena.op(ar, c), O.OpsCAST{}), O.eq_dt(w_dt(ar, tb, c), S.uint32())),
    U32.is_eq(O.Arena.nsrc(ar, c), 1))

def prw_of(+ar: O.Arena, +tb: F.Table, +u: U32) -> Bool:
  Bool.and(prw_is(ar, u), prw_cast(ar, tb, O.Arena.src0(ar, u)))

# :53  WGSLRenderer. Every attribute, in Python's order.
# `global_max = (65535, 65535, 65535)` and `local_max = (256, 256, 64)`. A
# Python tuple of three ints is a `List<&2, U32>`: the ORDER is the whole
# content and there is no name to read.
def global_max() -> List<&2, U32>: [65535, 65535, 65535]

def local_max() -> List<&2, U32>: [256, 256, 64]

# `barrier = "workgroupBarrier();"` -- note the SEMICOLON is inside the string,
# because `base_rewrite`'s BARRIER arm substitutes the text bare and the
# `_render` naming pass only appends `;` to a declaration, not to this.
def barrier() -> String: "workgroupBarrier();"

def nan() -> String: "nan()"

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
def code_for_workitem.ret(isg: Bool, m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: String.concat(["i32(", Bool.pick(String, isg, "gindex", "lindex"), ".", s, ")"])
    case None{}  : ""

def code_for_workitem(isg: Bool, x: U32) -> String: code_for_workitem.ret(isg, wi_axis.of(x))

# :62 `type_map`. Nine dtypes, and a KeyError for every other one. The `case _:`
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

# :60 `code_for_op = {CStyleLanguage.code_for_op, Ops.WHERE: lambda
# a,b,c,dtype: f"select({c},{b},{a})"}`. The WHERE arm takes FOUR arguments and
# the rest take two or one, and NONE of them read `dtype`, so one def with three
# string parameters answers all twenty-two: the unary arms ignore `b` and `c`.
# The twenty inherited from cstyle.py:142-150 are the duplication the header
def cfo_un(nm: String, +a: String) -> String:
  String.concat([nm, "(", a, ")"])

def cfo_bin(sym: String, +a: String, +b: String) -> String:
  String.concat(["(", a, sym, b, ")"])

def code_for_op.of(+op: O.Op, +a: String, +b: String, +c: String) -> String:
  match op:
    case O.OpsSQRT{}      : cfo_un("sqrt", a)
    case O.OpsRECIP{}: String.concat(["(1/", a, ")"])
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
    case O.OpsTRUNCMOD{}      : cfo_bin("%", a, b)
    case O.OpsTRUNCDIV{}      : cfo_bin("/", a, b)
    # Ops.FDIV is MISSING from WGSLRenderer.code_for_op upstream and present in
    # ClangRenderer's (cstyle.py:294 renders `(a/b)`). Measured, not assumed:
    case O.OpsFDIV{}      : cfo_bin("/", a, b)
    case O.OpsCMPNE{}     : cfo_bin("!=", a, b)
    case O.OpsSHR{}       : cfo_bin(">>", a, b)
    case O.OpsSHL{}       : cfo_bin("<<", a, b)
    case O.OpsCMPLT{}     : cfo_bin("<", a, b)
    case O.OpsCMPEQ{}     : cfo_bin("==", a, b)
    case O.OpsWHERE{}     : String.concat(["select(", c, ",", b, ",", a, ")"])
      # Upstream is LOUD here: `code_for_op[op](...)` raises KeyError for an op with no arm
    case _                : String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])

# :95 render_cast -- `f"{self.type_map[u.dtype]}({val})"`, then the two narrow
# forms. `u` is a UOp in Python and only `u.dtype` is read, so `dt` is the
# parameter. The `&{m}u` and `^{h}` are UNSIGNED CONSTANTS in WGSL and the
# `-{h}` is not, which is why the third form subtracts a bare integer.
#
# WHY THERE ARE TWO NARROW FORMS AT ALL: "Small integers use 32-bit WGSL
# values, so casts must truncate before subsequent arithmetic" -- wgsl.py:99,
# upstream's comment ON `render_cast`. WGSL HAS **NO** 8- OR 16-BIT
# ARITHMETIC TYPES: A `u8` IN WGSL IS A `u32` WITH A NAME, NOT A NARROW
# VALUE. SO A CAST TO `u8` PRODUCES A `u32` THAT IS **NOT YET** NARROWED,
# AND IF THE TRUNCATION IS NOT DONE HERE THEN EVERY SUBSEQUENT ARITHMETIC
# ON THAT VALUE HAPPENS AT 32 BITS AND THE ANSWER IS WRONG.
#
# WHICH MEANS THE TRUNCATION IS NOT COSMETIC AND ITS POSITION MATTERS: THE
# CAST IS THE LAST POINT WHERE THE WIDTH IS KNOWN. `u8(x)` MUST NARROW
# **THERE** AND NOT AT THE POINT OF USE.
#
# AND THE TWO FORMS ARE NOT THE SAME EXPRESSION BECAUSE THE SIGNED ONE IS
# NOT A MASK: A SIGNED `i8` IS NOT `x & 0xFF` -- THAT WOULD BE A `u8`. IT
# IS `((x & 0xFF) ^ 0x80) - 0x80`, WHICH IS "RE-INTERPRET THE 8 BITS AS
# SIGNED". THE PORT'S `render_cast.cls` SPELLS THAT AS `((ret & M) ^ H) - H`
# WITH `H = 2^(bits-1)`, AND THE SUBTRACTION IS BY A **BARE INTEGER** AND
# NOT BY `Hu` BECAUSE WGSL'S `i32` AND `u32` ARE DISTINCT TYPES AND THE
# EXPRESSION IS A SIGNED ONE.
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

# :106 render_kernel -- the whole WGSL MODULE. This is the def the browser

type Buf is Data:
  Buf{name: String, dt: S.Dt, addr: S.Addr, numel: U32}

# `local_size = [u.src[0].ssimplify() for u in sorted([u for u in uops if
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

# :121 supported_dtypes -- `{bool, char, uchar, short, ushort, int32, uint32,
# float, *((half,) if "shader-f16" in self.target.arch else ())}`.
#
# `self.target.arch` is a STRING here and the test is a SUBSTRING test, not an
# equality, so `arch` is a parameter: `"shader-f16" in arch` is the whole of
# what `Target` contributes to this method. The set is a list -- Python's set
# has no order and neither does this, so the gate compares it SORTED and the
# sort is a gate detail, not a claim.

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

# :65 `string_rewrite` -- THE SEVENTEEN RULES, in Python's order. This block
# `ctx[x]` looked like a graph call: `CStyleLanguage.__getitem__` is
# `self.r[key]`, a dict the NAMING pass fills in before it calls
# `string_rewrite.rewrite` (cstyle.py:245-250). So `ctx[x]` is not a fold and not

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

# THE ORDER. `PatternMatcher.rewrite` walks `patterns` TOP TO BOTTOM and takes
# the first hit, so the order is the semantics in EXACTLY TWO places in
# wgsl.py:65-93, and `sr_pick_*` is the port of that walk for those two. The

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
# rule 3 has no negative arm, and that is the PIN's change: upstream dropped
# `f"bitcast<u32>({c.val})" if c.val < 0 else ...` and a negative const cast to
# u8/u16/u32 is now the MASKED value with its `u` suffix. MEASURED against the
def sr_cuint.masked(+v: H.I64) -> H.I64: H.i64_of_hi_lo(0, H.lo32(v))

def sr_cuint(+dt: S.Dt, +v: H.I64) -> String:
  Bool.pick(String, p_cuint(dt), String.concat([H.i64_dec(sr_cuint.masked(v)), "u"]), "NOMATCH")

def sr_ci32.trunc(+v: H.I64) -> H.I64: H.i64_of_i32(H.lo32(v))

# WHY A NEGATIVE CONST IS SPELLED `i32(...)` AND NOT A BARE NUMBER:
def sr_ci32(+dt: S.Dt, +v: H.I64) -> String:
  Bool.pick(String, O.eq_dt(dt, S.int32()),
    Bool.pick(String, H.i64_is_neg(sr_ci32.trunc(v)),
      String.concat(["i32(", H.i64_dec(sr_ci32.trunc(v)), ")"]), H.i64_dec(sr_ci32.trunc(v))), "NOMATCH")

# 5 `UPat(Ops.BUFFER, name="x")` -- and it is the ONE rule whose op is a
def sr_buffer.local(a: S.Addr) -> Bool:
  match a:
    case S.ALocal{}: True{}
    case _           : False{}

def sr_buffer(+op: O.Op, +nm: String, +n: U32, +d: S.Dt, +a: S.Addr) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsBUFFER{}),
    String.concat([Bool.pick(String, sr_buffer.local(a), "var<workgroup>", "var"), " ", nm, ": array<",
      buf_map(n, d, a), ",", U32.show(packed_size(n, d, a)), ">;"]), "NOMATCH")

# 6..11 the SIX `bitcast<>` SPELLINGS, and they are six rules rather than one
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
def sr_lgate(ns: U32, +b: String, +i0: String, +n0: U32, +d0: S.Dt, a0: S.Addr, +v: String, +g: String) -> String:
  Bool.pick(String, U32.is_eq(ns, 3),
    String.concat(["select(", v, ", ", render_load(i0, n0, d0, a0), ", ", g, ")"]), "NOMATCH")

def sr_load(ns: U32, +x: String, +n: U32, +dt: S.Dt, a: S.Addr) -> String:
  Bool.pick(String, U32.is_eq(ns, 1), render_load(x, n, dt, a), "NOMATCH")

# 14 `UPat.store(UPat(Ops.CAST, src=(UPat.var("b"),)), UPat.any(packed_rmw, packed_rmw | UPat.var("nv")))`
def sr_rmw.add(hasnv: Bool, +b: String, +nv: String) -> String:
  Bool.pick(String, hasnv, String.concat(["\n  atomicAdd(&", b, ",", nv, ");"]), "")

# WHY TWO ATOMICS AND NOT ONE WRITE, AND WHY THE SECOND ONE IS OPTIONAL:
def sr_rmw(+vop: O.Op, +bop: O.Op, pk: Bool, hasnv: Bool, +b: String, +w: String, +nv: String) -> String:
  Bool.pick(String, Bool.and(Bool.and(O.eq_op(vop, O.OpsAND{}), sr_rmw_cast(bop)), pk),
    String.concat(["atomicAnd(&", b, ",", w, ");", sr_rmw.add(hasnv, b, nv)]), "NOMATCH")

# 15 `UPat.store(UPat.var("b"), UPat.var("v"))` -- `f"{ctx[b]} = {ctx[v]};"` --
# and it is the SUBSET-fall-through of rule 14, so it takes the same src COUNT.
def sr_store(ns: U32, +b: String, +v: String) -> String:
  Bool.pick(String, U32.is_eq(ns, 2), String.concat([b, " = ", v, ";"]), "NOMATCH")

# 16 `UPat(Ops.INDEX, src=(UPat.var("b"), UPat.var("idx")))` --
def sr_index(+op: O.Op, isadd: Bool, +b: String, +i: String) -> String:
  Bool.pick(String, O.eq_op(op, O.OpsINDEX{}),
    String.concat([b, "[", Bool.pick(String, isadd, H.strip_parens(i), i), "]"]), "NOMATCH")

# THE render_kernel FIXTURES AND ROWS.

def bs(x: Bool) -> String: Bool.pick(String, x, "True", "False")

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

# A row is ONE line, so a module's newlines are SPELLED. Without this a dropped
# separator between two bindings would be invisible to a line-oriented diff, and
# `String.concat` would hide it: the whole point of the gate is that a lost
# separator is a lost claim.
def one_line(+s: String) -> String: String.join(String.split(s, '\n'), "\\n")

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

# `rk_sz` and `rk_half` get rows because they are the half of `render_kernel` a
def u32_show(us: List<&2, U32>) -> List<&2, String>:
  match us:
    case Nil{}: Nil{}
    case h <> t: U32.show(h) <> u32_show(t)

# the fixture class this file was missing, added because the gate found
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

# `data0_4`, `data1_4`, `data2_4` are GLOBAL f32 of four: the three PARAMs of the
# real add, in the order `_render` recorded them. That order IS the binding
# number, so this is the row a reversed `bufs` fold breaks.
def bufs_alu() -> List<&2, Buf>:
  [Buf{"data0_4", S.single(), S.AGlobal{}, 4}, Buf{"data1_4", S.single(), S.AGlobal{}, 4},
    Buf{"data2_4", S.single(), S.AGlobal{}, 4}]

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
def r_bd() -> String:
  r("rk_bindings", String.join(bd_go.go(bufs_alu(), 0, Nil{}), ";"),
    "@group(0) @binding(1)var<storage,read_write>data0_4:array<f32>;;@group(0) @binding(2)var<storage,read_write>data1_4:array<f32>;;@group(0) @binding(3)var<storage,read_write>data2_4:array<f32>;")

def r_pt() -> String:
  r("rk_body", String.join(Part.rest(rk_partition(kern_alu())), ";"),
    "  var val0 = data1_4[0];;  var val1 = data1_4[1];;  var val2 = data1_4[2];;  var val3 = data1_4[3];;  var val4 = data2_4[0];;  var val5 = data2_4[1];;  var val6 = data2_4[2];;  var val7 = data2_4[3];;  data0_4[0] = (val0+val4);;  data0_4[1] = (val1+val5);;  data0_4[2] = (val2+val6);;  data0_4[3] = (val3+val7);")

# A MODULE ROW has no `py=` half, and that is deliberate. The expectation for
def rk_row(nm: String, got: String) -> String: String.concat([nm, " = [", got, "]\n"])

def r_rk_alu() -> String:
  rk_row("rk alu", one_line(render_kernel("E_4", kern_alu(), bufs_alu(), Scan{[1], False{}})))

def r_rk_mixed(+f: Fx) -> String:
  rk_row("rk mixed", one_line(render_kernel("K_mixed", kern_mixed(), bufs_mixed(),
    rk_scan(Fx.ar(f), fx_tb(f), fx_uops(f)))))

def r_rk_empty() -> String:
  rk_row("rk empty", one_line(render_kernel("K_empty", Nil{}, Nil{}, Scan{[1], False{}})))

# THE TABLE IS IN `.agents/slop/tables/renderer-wgsl-1518.md` -- THE GATE. Every row is a STRING and every row carries CPython's value, so the
def r_tm1(+nm: String, +d: S.Dt, py: String) -> String: r("type_map " ++ nm, type_map(d), py)

def r_tms() -> String:
  String.concat([r_tm1("float", S.single(), "f32"), r_tm1("uchar", S.uint8(), "u32"),
    r_tm1("ushort", S.uint16(), "u32"), r_tm1("short", S.int16(), "i32"),
    r_tm1("char", S.int8(), "i32"), r_tm1("int32", S.int32(), "i32"),
    r_tm1("uint32", S.uint32(), "u32"), r_tm1("bool", S.boolean(), "bool"),
    r_tm1("half", S.half(), "f16")])

# THE KeyError ARM, and it is LOUD: the port answers `UNHANDLED(dtypes.f64)` --
# a call to a dtype WGSL has no name for, which cannot compile. It answered `""`
# name is `dt_name`'s, which is `DType.name`.
#
# and the `py=` half carries the port's own refusal token, not CPython's exception
# NAME.  It used to carry `REFUSE:KeyError`, and that made the row compare TWO
# DIFFERENT CONVENTIONS: the port's half said "UNHANDLED(dtypes.f64)" and the
def r_tm_miss() -> String: r_tm1("double", S.double(), "UNHANDLED(dtypes.f64)")

def r_rc1(+nm: String, +d: S.Dt, py: String) -> String: r("render_cast " ++ nm, render_cast(d, "V"), py)

def r_rcs() -> String:
  String.concat([r_rc1("uchar", S.uint8(), "(u32(V)&255u)"), r_rc1("ushort", S.uint16(), "(u32(V)&65535u)"),
    r_rc1("char", S.int8(), "(((i32(V)&255)^128)-128)"),
    r_rc1("short", S.int16(), "(((i32(V)&65535)^32768)-32768)"),
    r_rc1("int32", S.int32(), "i32(V)"), r_rc1("uint32", S.uint32(), "u32(V)"),
    r_rc1("float", S.single(), "f32(V)"), r_rc1("half", S.half(), "f16(V)")])

def r_consts() -> String:
  String.concat([r("barrier", barrier(), "workgroupBarrier();"), r("nan", nan(), "nan()"),
    r("supports_float4", bs(supports_float4()), "False"),
    r("global_max", String.join(u32_show(global_max()), ","), "65535,65535,65535"),
    r("local_max", String.join(u32_show(local_max()), ","), "256,256,64")])

def r_pf3(+nm: String, +d: S.Dt, e: String, w: String, k: String) -> String:
  String.concat([r("pf_elems " ++ nm, U32.show(pf_elems(d)), e),
    r("pf_width " ++ nm, U32.show(pf_width(d)), w), r("pf_mask " ++ nm, U32.show(pf_mask(d)), k)])

def r_pfs() -> String:
  String.concat([r_pf3("uchar", S.uint8(), "4", "8", "255"), r_pf3("char", S.int8(), "4", "8", "255"),
    r_pf3("ushort", S.uint16(), "2", "16", "65535"), r_pf3("short", S.int16(), "2", "16", "65535"),
    r_pf3("half", S.half(), "2", "16", "65535"), r_pf3("int32", S.int32(), "1", "32", "4294967295")])

def r_wm(+mask: U32, +shift: U32, py: String) -> String:
  r("wmask " ++ U32.show(mask) ++ "_" ++ U32.show(shift), U32.show(ps_wmask(mask, shift)), py)

def r_wms() -> String:
  String.concat([r_wm(255, 0, "4294967040"), r_wm(255, 8, "4294902015"), r_wm(255, 16, "4278255615"),
    r_wm(255, 24, "16777215"), r_wm(65535, 0, "4294901760"), r_wm(65535, 16, "65535")])

def r_nan5(+nm: String, +d: S.Dt, b: String, e: String, m: String, k: String, t: String) -> String:
  String.concat([r("nan_bs " ++ nm, U32.show(nan_bs(d)), b), r("nan_e " ++ nm, U32.show(nan_e(d)), e),
    r("nan_m " ++ nm, U32.show(nan_m(d)), m), r("nan_mask " ++ nm, H.i64_dec(nan_mask(d)), k),
    r("nan_thr " ++ nm, H.i64_dec(nan_thr(d)), t)])

# `nan_mask` and `nan_thr` are 64-bit answers and they print in decimal, so the two
def r_nans() -> String:
  String.concat([r_nan5("float", S.single(), "32", "8", "23", "2147483647", "2139095040"),
    r_nan5("half", S.half(), "16", "5", "10", "32767", "31744"),
    r_nan5("bfloat16", S.bfloat16(), "16", "8", "7", "32767", "32640"),
    r_nan5("double", S.double(), "64", "11", "52", "9223372036854775807", "9218868437227405312")])

# `getattr(dtypes, f"uint{bs}")` -- the bitcast TARGET of the whole rule.
def r_nan_uint() -> String:
  String.concat([r("nan_uint float", dt_name(nan_uint(S.single())), "u32"),
    r("nan_uint half", dt_name(nan_uint(S.half())), "u16"),
    r("nan_uint double", dt_name(nan_uint(S.double())), "u64")])

def r_cfo1(+op: O.Op, py: String) -> String:
  r("code_for_op " ++ O.Ops.name.of(op), code_for_op.of(op, "A", "B", "C"), py)

def r_cfos() -> String:
  String.concat([r_cfo1(O.OpsSQRT{}, "sqrt(A)"), r_cfo1(O.OpsRECIP{}, "(1/A)"), r_cfo1(O.OpsNEG{}, "-A"),
    r_cfo1(O.OpsEXP2{}, "exp2(A)"), r_cfo1(O.OpsLOG2{}, "log2(A)"), r_cfo1(O.OpsSIN{}, "sin(A)"),
    r_cfo1(O.OpsTRUNC{}, "trunc(A)"), r_cfo1(O.OpsAND{}, "(A&B)"), r_cfo1(O.OpsXOR{}, "(A^B)"),
    r_cfo1(O.OpsOR{}, "(A|B)"), r_cfo1(O.OpsADD{}, "(A+B)"), r_cfo1(O.OpsSUB{}, "(A-B)"),
    r_cfo1(O.OpsMUL{}, "(A*B)"), r_cfo1(O.OpsTRUNCMOD{}, "(A%B)"), r_cfo1(O.OpsTRUNCDIV{}, "(A/B)"),
    r_cfo1(O.OpsFDIV{}, "(A/B)"),
    r_cfo1(O.OpsCMPNE{}, "(A!=B)"), r_cfo1(O.OpsSHR{}, "(A>>B)"), r_cfo1(O.OpsSHL{}, "(A<<B)"),
    r_cfo1(O.OpsCMPLT{}, "(A<B)"), r_cfo1(O.OpsCMPEQ{}, "(A==B)"), r_cfo1(O.OpsWHERE{}, "select(C,B,A)"),
    # The FALLTHROUGH is the row that matters most: upstream raises KeyError for an op with no arm,
    # so an unhandled op must not render as valid-looking WGSL. LOAD is chosen because it has no arm
    # and is an op a reader would expect to be absent (it never reaches a rendered kernel).
    r_cfo1(O.OpsLOAD{}, "UNHANDLED(Ops.LOAD)"),
    r_cfo1(O.OpsMAX{}, "UNHANDLED(Ops.MAX)"), r_cfo1(O.OpsPOW{}, "UNHANDLED(Ops.POW)")])

def r_wi1(+k: String, isg: Bool, x: U32, py: String) -> String: r("workitem " ++ k, code_for_workitem(isg, x), py)

def r_wis() -> String:
  String.concat([r_wi1("g0", True{}, 0, "i32(gindex.x)"), r_wi1("g1", True{}, 1, "i32(gindex.y)"),
    r_wi1("g2", True{}, 2, "i32(gindex.z)"), r_wi1("l0", False{}, 0, "i32(lindex.x)"),
    r_wi1("l1", False{}, 1, "i32(lindex.y)"), r_wi1("l2", False{}, 2, "i32(lindex.z)")])

# the IndexError arm of `'xyz'[int(x)]`.
def r_wi_miss() -> String: r_wi1("l3", False{}, 3, "")

def r_sd1(+arch: String, py: String) -> String: r("supported_dtypes " ++ arch, sorted_names(supported_dtypes(arch)), py)

def r_sds() -> String:
  String.concat([r_sd1("", "bool,f32,i16,i32,i8,u16,u32,u8"),
    r_sd1("shader-f16", "bool,f16,f32,i16,i32,i8,u16,u32,u8")])

def r_rds() -> String:
  String.concat([r("render_dtype float", render_dtype(S.single(), True{}), "var"),
    r("_render_dtype uchar global", _render_dtype(S.uint8(), 1, S.AGlobal{}, True{}, True{}, Nil{}), "var")])

# THE `string_rewrite` ROWS -- 33 of them, one per rule ARM.
#
# `r_sr` is `r` with the `sr ` prefix, and the RENDERED SOURCE TEXT is spelled
# out in each call rather than held in a def: it stands in for the naming pass's
# `self.r[key]` dict (cstyle.py:207), and the oracle puts THE SAME LITERAL in

def r_sr(+nm: String, got: String, py: String) -> String: r("sr " ++ nm, got, py)

def r_srneg(i: U32, +nm: String, got: String, py: String) -> String:
  r("srneg " ++ U32.show(i) ++ " " ++ nm, got, py)

# THE SEVENTEEN REFUSALS. Each `srneg` row drives the SAME body as the `sr` row
# for the same rule, on a node CPython's `UPat` REJECTS -- the oracle asserts that
# rejection with `UPat.match`, so the row's `py=[NOMATCH]` half is a refusal by
# construction rather than a transcription. until the patterns landed these rows
# ANSWERED ANYWAY, and two of them answered WRONG: `srneg 14` is a PACKED store of
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

# rules 3-4: the two CONST casts. the fixture is the weakint CONST's own value as
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
# the CAST constructor and the INDEX constructor are the STORE's BUFFER, and they
# are what the pinned rule-14 pattern discriminates on. `rmw nv` is CPython's OWN
# `packed_store` output, whose buffer is `word = idx.cast(dtypes.uint32)` -- a
# CAST -- so it IS rule 14. `rmw bare` is the same AND without the `new_v`, and
# its buffer is the INDEX under that CAST, so rule 14 REFUSES it and the row is
# a refusal. MEASURED, the two patterns are INVERTED over the two nodes: the
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

# THE TABLE IS IN `.agents/slop/tables/renderer-wgsl-1845.md` -- THE MUTATION TABLE. Measured 2026-10-02 with
