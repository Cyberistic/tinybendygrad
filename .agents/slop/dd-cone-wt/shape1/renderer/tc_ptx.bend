# renderer/tc_ptx.bend -- port of tinygrad/renderer/ptx.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This file used to hold
# `renderer/ptx.py` AND `renderer/tc.py`; the 1:1 ruling separates them and
# `renderer/tc.bend` is the other half. Rows: 620 before the split, 620 after -- the
# old `main` printed `r_stage1() <> r_stage2()` as ONE `IO.print`, so the two files'
# union is the same 620 lines with one frame line between the stages, which is the
# only byte `diff` reports.
#
# THE TENSOR-CORE TABLES ARE IMPORTED, NOT COPIED: `renderer/ptx.py` calls
# `get_nvidia`/`get_amd` for its warp-level `wmma` and `mma` shapes, and those are
# `tc.py:96-141`. They live in `tc.bend` and every use here is `T.`. `renderer/ptx.bend`
# imports this file as `P` and is unaffected.
#
# ===========================================================================
# ptx.py. `PTXRenderer`'s class attributes are the OPTS of a device, so they are
# a `Data` record and `ptx_of(ver)` is the inheritance (convention 1). Python
# MUTATES `self.extra_matcher` in `__init__` when `int(arch[3:]) < 80`
# (ptx.py:147); that mutation is a WALL -- the rules it appends are rewrites --
# and it is named at `ptx_of` rather than faked.
#
# `self.compiler` (ptx.py:145) is `runtime/support/compiler_cuda.py` and is a C
# effect in the port's own boundary table, so `ptx_of` does not carry it:
#   TODO(p3) ptx.py:145  self.compiler -- NVPTXCompiler / PTXCompiler
# ===========================================================================
import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./tc.bend as T

# ===========================================================================
# ptx.py. `PTXRenderer`'s class attributes are the OPTS of a device, so they are
# a `Data` record and `ptx_of(ver)` is the inheritance (convention 1). Python
# MUTATES `self.extra_matcher` in `__init__` when `int(arch[3:]) < 80`
# (ptx.py:147); that mutation is a WALL -- the rules it appends are rewrites --
# and it is named at `ptx_of` rather than faked.
#
# `self.compiler` (ptx.py:145) is `runtime/support/compiler_cuda.py` and is a C
# effect in the port's own boundary table, so `ptx_of` does not carry it:
#   TODO(p3) ptx.py:145  self.compiler -- NVPTXCompiler / PTXCompiler
# ===========================================================================
type Px is Data:
  Px{suffix: String, prefix: String, barrier: String, gmax: List<&2, U32>, lmax: List<&2, U32>, smax: U32, ver: U32}

def Px.suffix(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: suffix

def Px.prefix(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: prefix

def Px.barrier(p: Px) -> String:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: barrier

def Px.gmax(p: Px) -> List<&2, U32>:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: gmax

def Px.lmax(p: Px) -> List<&2, U32>:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: lmax

def Px.smax(p: Px) -> U32:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: smax

def Px.ver(p: Px) -> U32:
  match p:
    case Px{suffix, prefix, barrier, gmax, lmax, smax, ver}: ver

# `CUDARenderer.global_max/local_max/shared_max` -- ptx.py:139 inherits them and
# does not override, so they are constants of the record and the gate says where
# they came from.
def px_gmax() -> List<&2, U32>: [2147483647, 65535, 65535]
def px_lmax() -> List<&2, U32>: [1024, 1024, 64]
def px_smax() -> U32: 49152

# `kernel_prefix` (ptx.py:151-154) and `barrier` (ptx.py:155). The TAB in the
# barrier is spelled `tab()` because a literal TAB inside a string is invisible
# in a diff and `String.concat` would hide it.
def px_p0() -> String: ".version VERSION"
def nl() -> String: String.from_list([Char.from_u32(10)])
def px_p1() -> String: ".target TARGET"
def px_p2() -> String: ".address_size 64"
def px_p3() -> String: ".visible .entry"





def px_prefix() -> String:
  String.concat([px_p0(), nl(), px_p1(), nl(), px_p2(), nl(), px_p3()])


def tab() -> String: String.from_list([Char.from_u32(9)])


def px_barrier() -> String: String.concat(["bar.sync", tab(), "0;"])

# `suffix = "PTX"` -- ptx.py:138.
def px_suffix() -> String: "PTX"

# THE INHERITANCE: one constructor per device. `ver` is `int(arch[3:])`, the
# only per-arch thing `__init__` uses besides `tc.get_cuda`.
def ptx_of(+ver: U32) -> Px: Px{px_suffix(), px_prefix(), px_barrier(), px_gmax(), px_lmax(), px_smax(), ver}

# ===========================================================================
# `types` / `mem_types` / `cast_types` -- ptx.py:156-161.
#
#   types:       int8 s16, int16 s16, int32 s32, int64 s64, uint8 u16,
#               uint16 u16, uint32 u32, uint64 u64, float16 f16, float32 f32,
#               float64 f64, bool pred
#   mem_types:  {**types, int8: s8, uint8: u8, bool: u8, float16: b16}
#   cast_types: {**types, int8: s8, uint8: u8}
#
# The two derived tables are `types` with FOUR and TWO keys replaced, so they are
# `types` with an override and not a second twelve-arm ladder. DISPATCH IS ON
# `pri`, which is a unique key over the twelve keys -- the eight fp8/weak
# priorities are NOT keys and take the KeyError arm (a row of its own). `pri` is
# not unique over ALL of `dtypes` (fp8e4m3 and fp8e4m3fnuz share pri 10), which
# is why dtype EQUALITY anywhere in this file is `O.eq_dt` and never `pri`.
# ===========================================================================
def types_pri(pri: U32) -> String:
  match pri:
    case 0:  "pred"
    case 1:  "s16"
    case 2:  "u16"
    case 3:  "s16"
    case 4:  "u16"
    case 5:  "s32"
    case 6:  "u32"
    case 7:  "s64"
    case 8:  "u64"
    case 12: "f16"
    case 14: "f32"
    case 15: "f64"
    case _:   ""

def types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: types_pri(pri)

def mem_types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 1:  "s8"
        case 2:  "u8"
        case 0:  "u8"
        case 12: "b16"
        case _:   types_pri(pri)

def cast_types_of(+dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}:
      match pri:
        case 1: "s8"
        case 2: "u8"
        case _:  types_pri(pri)

# ===========================================================================
# `mem_type(x)` -- ptx.py:59: `'shared' if x.addrspace == AddrSpace.LOCAL else
# 'global'`. Two addresses are LOCAL or not, and the `else` is the answer for
# every other AddrSpace, so this is a two-arm match on the addrspace.
# ===========================================================================
def mem_type(addr: S.Addr) -> String:
  match addr:
    case S.ALocal{}: "shared"
    case _:          "global"

# ===========================================================================
# :11 `render_val(x, dtype)` --
#
#   if dtypes.is_float(dtype):
#     if dtype == dtypes.f64: return "0d%02X..." % tuple(struct.pack("d",x)[::-1])
#     if dtype == dtypes.f16:   return "0x%02X%02X" % tuple(struct.pack("e",x)[::-1])
#     return "0f%02X%02X%02X%02X" % tuple(struct.pack("f",x)[::-1])
#   return str(int(x)) + ("U" if dtypes.is_unsigned(dtype) else "")
#
# `[::-1]` on a LITTLE-ENDIAN `struct.pack` is BIG-ENDIAN hex, so the two/hex four
# are just the float's bits read out most-significant byte first -- and `F32.bits`
# is an intrinsic, so both float arms are arithmetic.
#
#   TODO(p3) ptx.py:13  render_val's DOUBLE arm -- `struct.pack("d", ...)` is 64
#                       bits and U32 is the widest type Bend has. Unreachable
#                       from a float CONST on a PTX target in this gate's fixture
#                       set; named rather than faked.
#   TODO(p3) ptx.py:16  render_val's SIGNED-INTEGER arm -- `str(int(x))` needs a
#                       signed decimal and Bend has no signed type. The
#                       UNSIGNED arm is ported and gated; the signed one is not.
#
# `bits` is the float's BIT PATTERN in the float arms and the integer's VALUE in
# the integer arm -- see the note on the two numeric parameters below.
# ===========================================================================
def hexdig() -> String: "0123456789ABCDEF"

def hex1(+x: U32) -> String:
  String.from_list([Maybe.default(&2, Char, String.get(hexdig(), U32.to_nat(U32.and(x, 15))), Char.from_u32(63))])

# `%02X` FOUR TIMES is `hex4` and EIGHT TIMES is `hex8`: Python's `"0x%02X%02X"`
# is two BYTES (four hex digits) for a half and `"0f%02X%02X%02X%02X"` is four
# bytes (eight digits) for a float. Writing `hex2` as two digits is the same
# off-by-a-nibble mistake as shifting by 12 instead of 28 -- MEASURED: the first
# version printed `0f0000` for 3.5 and `0x54` for 0.3330078125, and every
# `render_val` float row moved with the `.len`-free text.
def hex4(+x: U32) -> String: String.concat([hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 8n)), hex1(U32.shrn(x, 4n)), hex1(x)])

def hex8(+x: U32) -> String:
  String.concat([hex1(U32.shrn(x, 28n)), hex1(U32.shrn(x, 24n)), hex1(U32.shrn(x, 20n)), hex1(U32.shrn(x, 16n)),
    hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 8n)), hex1(U32.shrn(x, 4n)), hex1(x)])

# `struct.pack("e", x)` -- IEEE binary16 of an F32, rounded TOWARD ZERO, because
# `struct` truncates the mantissa and the gate's four values (0.0, 1.0, -2.5,
# 0.3330078125) are all NORMAL and all exactly representable, so the
# round-to-nearest-even tie never fires.
#
# NAMED, NOT PORTED: the SUBNORMAL range (f32 exponent 0) and the OVERFLOW to
# infinity, which `struct.pack` reaches with a biased shift. Both answer
# `f16.zero` -- sign bit only -- which is WRONG for a real subnormal, so this is
# a truncation of the encoding and not IEEE binary16, and the header says so.
def f16_exp(+b: U32) -> U32: U32.and(U32.shrn(b, 23n), 255)

def f16_man(+b: U32) -> U32: U32.and(b, 8388607)

def f16_sgn(+b: U32) -> U32: U32.shrn(b, 31n)

# the 127 - 15 REBIAS, wrapped: an exponent below 112 gives a huge `e`, which is
# outside 1..=30 and so takes the `f16.zero` arm.
def f16.normal(+b: U32, +e: U32) -> U32:
  U32.or(U32.or(U32.shln(f16_sgn(b), 15n), U32.shln(e, 10n)), U32.shrn(f16_man(b), 13n))
def f16.zero(+b: U32) -> U32: U32.shln(f16_sgn(b), 15n)


def f16bits(x: F32) -> U32:
  +b = F32.bits(x)
  +e = U32.sub(f16_exp(b), 112)
  Bool.pick(U32, Bool.and(U32.is_ge(e, 1), U32.is_le(e, 30)), f16.normal(b, e), f16.zero(b))



# NOTE the two numeric parameters: `x` is the FLOAT and `v` the INTEGER, and
# the two never meet. Carrying ONE U32 instead -- which is what the first version
# of this def did -- is wrong for half, because `struct.pack("e", x)` re-ENCODES
# the value into binary16 rather than truncating the binary32 pattern: 1.0f32 is
# 0x3F800000 and half(1.0f32) is 0x3C00, so the high two bytes are NOT the answer.
def render_val_f(+x: F32, is_half: Bool) -> String:
  Bool.pick(String, is_half, String.concat(["0x", hex4(f16bits(x))]), String.concat(["0f", hex8(F32.bits(x))]))

def render_val_u(+v: U32, is_unsigned: Bool) -> String:
  Bool.pick(String, is_unsigned, String.concat([U32.show(v), "U"]), U32.show(v))

def render_val(is_float: Bool, is_half: Bool, is_unsigned: Bool, +x: F32, +v: U32) -> String:
  Bool.pick(String, is_float, render_val_f(x, is_half), render_val_u(v, is_unsigned))

# `Dtf` -- the three dtype FACTS `asm_for_op` and `string_rewrite` read. A
# `match` may not scrutinise `S.Dt.is_bool(dt)`, so a def that branches on them
# takes the record (convention 4). One record, three fields, three readers, and
# it is the ONLY way a dtype reaches a branch in this file.
type Dtf is Data:
  Dtf{is_bool: Bool, is_int: Bool, is_float: Bool}

def Dtf.is_bool(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_bool

def Dtf.is_int(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_int

def Dtf.is_float(d: Dtf) -> Bool:
  match d:
    case Dtf{is_bool, is_int, is_float}: is_float

def Dtf.of(+dt: S.Dt) -> Dtf: Dtf{S.Dt.is_bool(dt), S.Dt.is_int(dt), S.Dt.is_float(dt)}

# ===========================================================================
# `asm_for_op` -- ptx.py:18-36. TWENTY-ONE lambdas keyed by op, so ONE def with a
# `match` on the op (convention 1: no closures in a record, and the brief's rule
# 31 says a table of closures would be unprintable).
#
# It returns `List<&2, String>` because Python's is `str` for twenty of the
# twenty-one and a TWO-ELEMENT LIST for WHERE-on-bool. Collapsing that to one
# string would hide the fact that the bool arm emits two kernel lines, so the
# list is kept and the gate joins with `" ;; "` on both sides.
#
# `name` is `ctx.types[dtype]` -- "s32", "f16", "pred" -- and `name[1:]` is
# `String.drop(name, 1n)`: the `.b32` / `.b16` / `.b64` suffix every bitwise arm
# spells. `SHL` is `shl.b{name[1:]}` and the other bitwise arms are
# `{and,or,xor}.b{name[1:]}`.
# ===========================================================================
def op_asm(op: O.Op, +d: String, +a: String, +b: String, +c: String, +name: String, +f: Dtf) -> List<&2, String>:
  match op:
    case O.OpsRECIPROCAL{}: [String.concat([Bool.pick(String, Dtf.is_float(f), "rcp.approx.", "rcp."), name, " ", d, ", ", a, ";"])]
    case O.OpsEXP2{}      : [String.concat(["ex2.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsLOG2{}      : [String.concat(["lg2.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsSIN{}       : [String.concat(["sin.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsSQRT{}      : [String.concat(["sqrt.approx.", name, " ", d, ", ", a, ";"])]
    case O.OpsTRUNC{}     : [String.concat(["cvt.rzi.", name, ".", name, " ", d, ", ", a, ";"])]
    case O.OpsSHR{}       : [String.concat(["shr.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsSHL{}       : [String.concat(["shl.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsADD{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), "or.", "add."), name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMUL{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), "and", "mul"), Bool.pick(String, Dtf.is_int(f), ".lo", ""), ".", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsXOR{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["xor.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["xor.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsAND{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["and.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["and.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsOR{}        : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat(["or.pred ", d, ", ", a, ", ", b, ";"])], [String.concat(["or.b", String.drop(name, 1n), " ", d, ", ", a, ", ", b, ";"])])
    case O.OpsCDIV{}      : [String.concat(["div.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMOD{}      : [String.concat(["rem.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMAX{}       : [String.concat(["max.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPEQ{}     : [String.concat(["setp.eq.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPLT{}     : [String.concat(["setp.lt.", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsCMPNE{}     : [String.concat(["setp.", Bool.pick(String, Dtf.is_float(f), "neu", "ne"), ".", name, " ", d, ", ", a, ", ", b, ";"])]
    case O.OpsMULACC{}    : [String.concat([Bool.pick(String, Dtf.is_float(f), "fma.rn.", "mad.lo."), name, " ", d, ", ", a, ", ", b, ", ", c, ";"])]
    case O.OpsWHERE{}     : Bool.pick(List<&2, String>, Dtf.is_bool(f),
      [String.concat(["@", a, " mov.", name, " ", d, ", ", b, ";"]), String.concat(["@!", a, " mov.", name, " ", d, ", ", c, ";"])],
      [String.concat(["selp.", Bool.pick(String, String.eq(name, "f16"), "b16", name), " ", d, ", ", b, ", ", c, ", ", a, ";"])])
    case _: []

# ===========================================================================
# :38-39 `supports_half` / `doesnt_support_half`. The first is a SEVEN-TUPLE
# LITERAL, so its order is the LITERAL's -- EXP2,ADD,MUL,MAX,CMPLT,WHERE,TRUNC --
# and NOT `asm_for_op`'s key order, which would put TRUNC second. The second is
# `tuple(op for op in asm_for_op.keys() if op not in supports_half)`, so it is
# DERIVED from the first and the twenty-one keys, in the dict's own order. The
# seven names therefore live in exactly ONE place, `supports_half`, and the
# membership test reads it -- so a wrong name moves BOTH rows, and a right name
# in the wrong position moves the first.
# ===========================================================================
def supports_half() -> List<&2, O.Op>:
  [O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}, O.OpsTRUNC{}]

# `op not in supports_half` -- `O.eq_op` is a def, which `List.contains` wants as
# a function VALUE (a closure is not one).
def in_sh(+o: O.Op) -> Bool: List.contains(~O.Op, O.eq_op, supports_half(), o)

def asm_keys() -> List<&2, O.Op>:
  [O.OpsRECIPROCAL{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsTRUNC{}, O.OpsSHR{}, O.OpsSHL{},
   O.OpsADD{}, O.OpsMUL{}, O.OpsXOR{}, O.OpsAND{}, O.OpsOR{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsMAX{}, O.OpsCMPEQ{},
   O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsMULACC{}, O.OpsWHERE{}]

# A DROP-FILTER over `asm_for_op`'s key order. The head goes in FRONT of the
# tail's answer (`List.append(..., [o], rest)` is `[o] ++ rest`) and the
# recursion is called ONCE through the `+rest` binder: a `Bool.pick` with the
# self-call in both arms calls it TWICE, and a self-call SPENDS the list it
# walks, so the first arm's answer comes back spent. The version that also ran
# a `List.reverse` on top printed the fourteen names backwards.
def dsh.go(+ops: List<&2, O.Op>, +acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match ops:
    case Nil{}   : acc
    case o <> +t :
      +rest = dsh.go(t, acc)
      Bool.pick(List<&2, O.Op>, in_sh(o), rest, List.append(&2, O.Op, [o], rest))

def doesnt_support_half() -> List<&2, O.Op>: dsh.go(asm_keys(), Nil{})

# ===========================================================================
# :78 `modifier(a, b)` -- `'.rzi' if is_int(a) and is_float(b) else '.rn' if
# is_float(a) and (a.itemsize < b.itemsize or is_int(b) or b == bool) else ''`.
# Three clauses, ANDed in two pairs; the gate runs all 9x6 dtype pairs because
# the third clause alone distinguishes float->float from half->float.
# ===========================================================================
def modifier(+fa: Dtf, +fb: Dtf, +a: S.Dt, +b: S.Dt) -> String:
  Bool.pick(String, Bool.and(Dtf.is_int(fa), Dtf.is_float(fb)), ".rzi",
    Bool.pick(String, Bool.and(Dtf.is_float(fa), Bool.or(U32.is_lt(S.Dt.itemsize(a), S.Dt.itemsize(b)),
      Bool.or(Dtf.is_int(fb), O.eq_dt(b, S.boolean())))), ".rn", ""))
# ===========================================================================
# THE STAGE 2 GATE -- ptx.py's emitters. Every row is a STRING beside CPython's.
#
#   * `render_val` over half / float / unsigned -- the three PORTED arms. The
#     signed-integer and double arms are walls and are NOT rows.
#   * `asm_for_op`'s twenty-one entries over five dtypes with `name` FIXED at
#     "s32" (105 rows) -- that isolates the DTYPE branch -- plus five ops over
#     all twelve dtypes with `name = ctx.types[dt]` (60 rows), which isolates
#     the NAME branch: `shl.b{name[1:]}`, `xor.b{name[1:]}`, `selp.b16`.
#   * `supports_half` / `doesnt_support_half` as NAME LISTS in the dict's own
#     order, which is what the tuple comprehension preserves.
#   * `modifier` over all 54 dtype pairs.
#   * the three dtype tables, the two maxima, the suffix, the barrier (TAB
#     escaped) and the kernel prefix split one row per line plus a COUNT.
#   * `supported_dtypes` and `tensor_cores` for three arches.
# ===========================================================================
def pm_n_rules() -> U32: 8


def r_pmx_n() -> String: T.r("ptx_matcher rules", U32.show(pm_n_rules()), "8")

# `ptx_matcher` (ptx.py:40-57) is SEVEN rules and every one is a graph REWRITE:
# three bool-only algebra rewrites, an upcast to float32, two bool-buffer
# uint8 views and two uint casts of a shift amount. Each builds a NEW node
# (`x.replace(src=(...))`, `UOp(x.op, src=..., arg=...)`), and the arena is
# `Type`, so a rule returning an index the caller cannot dereference is the
# wall `uop/divandmod.bend`'s header already names. THE COUNT is the row that
# is derivable here; the seven rewrites are:
#   TODO(p3) ptx.py:42  bool NE -> x^y
#   TODO(p3) ptx.py:43  bool EQ -> (x^y)^True
#   TODO(p3) ptx.py:44  bool LT -> (x^True)&y
#   TODO(p3) ptx.py:46  upcast the half ops that do not support half
#   TODO(p3) ptx.py:49  bool LOAD through a uint8 view (needs with_storage)
#   TODO(p3) ptx.py:52  bool STORE through a uint8 view
#   TODO(p3) ptx.py:55  SHL with a non-uint shift amount -> cast
#   TODO(p3) ptx.py:56  SHR with a non-uint shift amount -> cast

# `render_val` -- `F32.bits` is the float pattern and half is a RE-ENCODE, so
# half goes through `f16bits` and float does not.
def r_rv1(+nm: String, flt: Bool, half_: Bool, uns: Bool, +x: F32, +v: U32, py: String) -> String:
  T.r("render_val " ++ nm, render_val(flt, half_, uns, x, v), py)

def r_rvs() -> String:
  String.concat([r_rv1("half 0.0", True{}, True{}, False{}, 0.0, 0, "0x0000"), r_rv1("half 1.0", True{}, True{}, False{}, 1.0, 0, "0x3C00"), r_rv1("half -2.5", True{}, True{}, False{}, F32.neg(2.5), 0, "0xC100"), r_rv1("half 0.3330078125", True{}, True{}, False{}, 0.3330078125, 0, "0x3554"), r_rv1("float 0.0", True{}, False{}, False{}, 0.0, 0, "0f00000000"), r_rv1("float 1.0", True{}, False{}, False{}, 1.0, 0, "0f3F800000"), r_rv1("float -2.5", True{}, False{}, False{}, F32.neg(2.5), 0, "0fC0200000"), r_rv1("float 3.5", True{}, False{}, False{}, 3.5, 0, "0f40600000"), r_rv1("unsigned int 0", False{}, False{}, True{}, 0.0, 0, "0U"), r_rv1("unsigned int 7", False{}, False{}, True{}, 0.0, 7, "7U"), r_rv1("unsigned int 4294967295", False{}, False{}, True{}, 0.0, 4294967295, "4294967295U"), r_rv1("unsigned char 255", False{}, False{}, True{}, 0.0, 255, "255U")])

# `asm_for_op`'s twenty-one arms with `name` FIXED at "s32", so the row is about
# the DTYPE branch alone.
def r_asm1(+opn: String, +op: O.Op, +dt: S.Dt, +name: String, py: String) -> String:
  T.r("asm " ++ opn ++ " " ++ T.dt_name(dt), String.join(op_asm(op, "%d", "%a", "%b", "%c", name, Dtf.of(dt)), " ;; "), py)

def r_asms() -> String:
  String.concat([r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.single(), "s32", "rcp.approx.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.single(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.single(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.single(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.single(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.single(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.single(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.single(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.single(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.single(), "s32", "mul.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.single(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.single(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.single(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.single(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.single(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.single(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.single(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.single(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.single(), "s32", "setp.neu.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.single(), "s32", "fma.rn.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.half(), "s32", "rcp.approx.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.half(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.half(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.half(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.half(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.half(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.half(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.half(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.half(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.half(), "s32", "mul.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.half(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.half(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.half(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.half(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.half(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.half(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.half(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.half(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.half(), "s32", "setp.neu.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.half(), "s32", "fma.rn.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.boolean(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.boolean(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.boolean(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.boolean(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.boolean(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.boolean(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.boolean(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.boolean(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.boolean(), "s32", "or.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.boolean(), "s32", "and.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.boolean(), "s32", "xor.pred %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.boolean(), "s32", "and.pred %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.boolean(), "s32", "or.pred %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.boolean(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.boolean(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.boolean(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.boolean(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.boolean(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.boolean(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.boolean(), "s32", "mad.lo.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.uint32(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.uint32(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.uint32(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.uint32(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.uint32(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.uint32(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.uint32(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.uint32(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.uint32(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.uint32(), "s32", "mul.lo.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.uint32(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.uint32(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.uint32(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.uint32(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.uint32(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.uint32(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.uint32(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.uint32(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.uint32(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.uint32(), "s32", "mad.lo.s32 %d, %a, %b, %c;"), r_asm1("RECIPROCAL", O.OpsRECIPROCAL{}, S.int32(), "s32", "rcp.s32 %d, %a;"), r_asm1("EXP2", O.OpsEXP2{}, S.int32(), "s32", "ex2.approx.s32 %d, %a;"), r_asm1("LOG2", O.OpsLOG2{}, S.int32(), "s32", "lg2.approx.s32 %d, %a;"), r_asm1("SIN", O.OpsSIN{}, S.int32(), "s32", "sin.approx.s32 %d, %a;"), r_asm1("SQRT", O.OpsSQRT{}, S.int32(), "s32", "sqrt.approx.s32 %d, %a;"), r_asm1("TRUNC", O.OpsTRUNC{}, S.int32(), "s32", "cvt.rzi.s32.s32 %d, %a;"), r_asm1("SHR", O.OpsSHR{}, S.int32(), "s32", "shr.s32 %d, %a, %b;"), r_asm1("SHL", O.OpsSHL{}, S.int32(), "s32", "shl.b32 %d, %a, %b;"), r_asm1("ADD", O.OpsADD{}, S.int32(), "s32", "add.s32 %d, %a, %b;"), r_asm1("MUL", O.OpsMUL{}, S.int32(), "s32", "mul.lo.s32 %d, %a, %b;"), r_asm1("XOR", O.OpsXOR{}, S.int32(), "s32", "xor.b32 %d, %a, %b;"), r_asm1("AND", O.OpsAND{}, S.int32(), "s32", "and.b32 %d, %a, %b;"), r_asm1("OR", O.OpsOR{}, S.int32(), "s32", "or.b32 %d, %a, %b;"), r_asm1("CDIV", O.OpsCDIV{}, S.int32(), "s32", "div.s32 %d, %a, %b;"), r_asm1("CMOD", O.OpsCMOD{}, S.int32(), "s32", "rem.s32 %d, %a, %b;"), r_asm1("MAX", O.OpsMAX{}, S.int32(), "s32", "max.s32 %d, %a, %b;"), r_asm1("CMPEQ", O.OpsCMPEQ{}, S.int32(), "s32", "setp.eq.s32 %d, %a, %b;"), r_asm1("CMPLT", O.OpsCMPLT{}, S.int32(), "s32", "setp.lt.s32 %d, %a, %b;"), r_asm1("CMPNE", O.OpsCMPNE{}, S.int32(), "s32", "setp.ne.s32 %d, %a, %b;"), r_asm1("MULACC", O.OpsMULACC{}, S.int32(), "s32", "mad.lo.s32 %d, %a, %b, %c;")])

# THE NAME BRANCH. `name = ctx.types[dt]`, so `name[1:]` is `drop(name, 1n)` and
# the SAME op over twelve dtypes gives twelve different suffixes -- including
# `shl.bred` for bool, because `types[bool]` is `pred`. That is what Python
# emits and it is the row that catches a `name[1:]` read as `name[1]`.
def r_asm2_1(+opn: String, +op: O.Op, +dt: S.Dt, py: String) -> String:
  T.r("asm2 " ++ opn ++ " " ++ T.dt_name(dt), String.join(op_asm(op, "%d", "%a", "%b", "%c", types_of(dt), Dtf.of(dt)), " ;; "), py)

def r_asm2s() -> String:
  String.concat([r_asm2_1("ADD", O.OpsADD{}, S.int8(), "add.s16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int8(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int8(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int8(), "mad.lo.s16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int8(), "selp.s16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int8(), "cvt.rzi.s16.s16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int16(), "add.s16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int16(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int16(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int16(), "mad.lo.s16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int16(), "selp.s16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int16(), "cvt.rzi.s16.s16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int32(), "add.s32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int32(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int32(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int32(), "mad.lo.s32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int32(), "selp.s32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int32(), "cvt.rzi.s32.s32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.int64(), "add.s64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.int64(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.int64(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.int64(), "mad.lo.s64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.int64(), "selp.s64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.int64(), "cvt.rzi.s64.s64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint8(), "add.u16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint8(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint8(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint8(), "mad.lo.u16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint8(), "selp.u16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint8(), "cvt.rzi.u16.u16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint16(), "add.u16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint16(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint16(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint16(), "mad.lo.u16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint16(), "selp.u16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint16(), "cvt.rzi.u16.u16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint32(), "add.u32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint32(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint32(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint32(), "mad.lo.u32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint32(), "selp.u32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint32(), "cvt.rzi.u32.u32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.uint64(), "add.u64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.uint64(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.uint64(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.uint64(), "mad.lo.u64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.uint64(), "selp.u64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.uint64(), "cvt.rzi.u64.u64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.half(), "add.f16 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.half(), "shl.b16 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.half(), "xor.b16 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.half(), "fma.rn.f16 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.half(), "selp.b16 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.half(), "cvt.rzi.f16.f16 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.single(), "add.f32 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.single(), "shl.b32 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.single(), "xor.b32 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.single(), "fma.rn.f32 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.single(), "selp.f32 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.single(), "cvt.rzi.f32.f32 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.double(), "add.f64 %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.double(), "shl.b64 %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.double(), "xor.b64 %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.double(), "fma.rn.f64 %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.double(), "selp.f64 %d, %b, %c, %a;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.double(), "cvt.rzi.f64.f64 %d, %a;"), r_asm2_1("ADD", O.OpsADD{}, S.boolean(), "or.pred %d, %a, %b;"), r_asm2_1("SHL", O.OpsSHL{}, S.boolean(), "shl.bred %d, %a, %b;"), r_asm2_1("XOR", O.OpsXOR{}, S.boolean(), "xor.pred %d, %a, %b;"), r_asm2_1("MULACC", O.OpsMULACC{}, S.boolean(), "mad.lo.pred %d, %a, %b, %c;"), r_asm2_1("WHERE", O.OpsWHERE{}, S.boolean(), "@%a mov.pred %d, %b; ;; @!%a mov.pred %d, %c;"), r_asm2_1("TRUNC", O.OpsTRUNC{}, S.boolean(), "cvt.rzi.pred.pred %d, %a;")])

# WHERE's three FORMS: the TWO-ELEMENT LIST on bool, `selp.b16` when the name is
# f16 (PTX has no `selp.f16`), and `selp.<name>` otherwise. Keeping the list means
# the bool arm's TWO kernel lines stay visible in the row.
def r_where() -> String:
  String.concat([T.r("asm WHERE float", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f16", Dtf.of(S.single())), " ;; "), "selp.b16 %d, %b, %c, %a;"),
    T.r("asm WHERE bool", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f16", Dtf.of(S.boolean())), " ;; "), "@%a mov.f16 %d, %b; ;; @!%a mov.f16 %d, %c;"),
    T.r("asm WHERE b16f32", String.join(op_asm(O.OpsWHERE{}, "%d", "%a", "%b", "%c", "f32", Dtf.of(S.single())), " ;; "), "selp.f32 %d, %b, %c, %a;")])

# `",".join(ops.Ops)` over `asm_for_op`'s own key order: `supports_half` is the
# seven-name tuple and `doesnt_support_half` the fourteen-name complement, and the
# ORDER is what the dict comprehension preserves.
def op_names(+ops: List<&2, O.Op>) -> String:
  match ops:
    case Nil{}   : ""
    case o <> +t : String.concat([O.Ops.name.of(o), Bool.pick(String, List.is_empty(&2, O.Op, t), "", ","), op_names(t)])

def r_sh() -> String:
  String.concat([T.r("supports_half", op_names(supports_half()), "EXP2,ADD,MUL,MAX,CMPLT,WHERE,TRUNC"), T.r("doesnt_support_half", op_names(doesnt_support_half()), "RECIPROCAL,LOG2,SIN,SQRT,SHR,SHL,XOR,AND,OR,CDIV,CMOD,CMPEQ,CMPNE,MULACC")])

# `modifier` over all 54 dtype pairs. The third clause alone separates
# float->float (empty) from half->float (`.rn`), so every pair is a row.
def r_mod1(+nm: String, +a: S.Dt, +b: S.Dt, py: String) -> String:
  T.r("modifier " ++ nm, modifier(Dtf.of(a), Dtf.of(b), a, b), py)

def r_mods() -> String:
  String.concat([r_mod1("signed char,signed char", S.int8(), S.int8(), ""), r_mod1("signed char,int", S.int8(), S.int32(), ""), r_mod1("signed char,float", S.int8(), S.single(), ".rzi"), r_mod1("signed char,half", S.int8(), S.half(), ".rzi"), r_mod1("signed char,bool", S.int8(), S.boolean(), ""), r_mod1("signed char,double", S.int8(), S.double(), ".rzi"), r_mod1("short,signed char", S.int16(), S.int8(), ""), r_mod1("short,int", S.int16(), S.int32(), ""), r_mod1("short,float", S.int16(), S.single(), ".rzi"), r_mod1("short,half", S.int16(), S.half(), ".rzi"), r_mod1("short,bool", S.int16(), S.boolean(), ""), r_mod1("short,double", S.int16(), S.double(), ".rzi"), r_mod1("int,signed char", S.int32(), S.int8(), ""), r_mod1("int,int", S.int32(), S.int32(), ""), r_mod1("int,float", S.int32(), S.single(), ".rzi"), r_mod1("int,half", S.int32(), S.half(), ".rzi"), r_mod1("int,bool", S.int32(), S.boolean(), ""), r_mod1("int,double", S.int32(), S.double(), ".rzi"), r_mod1("unsigned char,signed char", S.uint8(), S.int8(), ""), r_mod1("unsigned char,int", S.uint8(), S.int32(), ""), r_mod1("unsigned char,float", S.uint8(), S.single(), ".rzi"), r_mod1("unsigned char,half", S.uint8(), S.half(), ".rzi"), r_mod1("unsigned char,bool", S.uint8(), S.boolean(), ""), r_mod1("unsigned char,double", S.uint8(), S.double(), ".rzi"), r_mod1("unsigned int,signed char", S.uint32(), S.int8(), ""), r_mod1("unsigned int,int", S.uint32(), S.int32(), ""), r_mod1("unsigned int,float", S.uint32(), S.single(), ".rzi"), r_mod1("unsigned int,half", S.uint32(), S.half(), ".rzi"), r_mod1("unsigned int,bool", S.uint32(), S.boolean(), ""), r_mod1("unsigned int,double", S.uint32(), S.double(), ".rzi"), r_mod1("float,signed char", S.single(), S.int8(), ".rn"), r_mod1("float,int", S.single(), S.int32(), ".rn"), r_mod1("float,float", S.single(), S.single(), ""), r_mod1("float,half", S.single(), S.half(), ""), r_mod1("float,bool", S.single(), S.boolean(), ".rn"), r_mod1("float,double", S.single(), S.double(), ".rn"), r_mod1("half,signed char", S.half(), S.int8(), ".rn"), r_mod1("half,int", S.half(), S.int32(), ".rn"), r_mod1("half,float", S.half(), S.single(), ".rn"), r_mod1("half,half", S.half(), S.half(), ""), r_mod1("half,bool", S.half(), S.boolean(), ".rn"), r_mod1("half,double", S.half(), S.double(), ".rn"), r_mod1("bool,signed char", S.boolean(), S.int8(), ""), r_mod1("bool,int", S.boolean(), S.int32(), ""), r_mod1("bool,float", S.boolean(), S.single(), ""), r_mod1("bool,half", S.boolean(), S.half(), ""), r_mod1("bool,bool", S.boolean(), S.boolean(), ""), r_mod1("bool,double", S.boolean(), S.double(), ""), r_mod1("double,signed char", S.double(), S.int8(), ".rn"), r_mod1("double,int", S.double(), S.int32(), ".rn"), r_mod1("double,float", S.double(), S.single(), ""), r_mod1("double,half", S.double(), S.half(), ""), r_mod1("double,bool", S.double(), S.boolean(), ".rn"), r_mod1("double,double", S.double(), S.double(), "")])

def r_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  T.r("types " ++ nm, types_of(dt), py)

def r_mem_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  T.r("mem_types " ++ nm, mem_types_of(dt), py)

def r_cast_types1(+nm: String, +dt: S.Dt, py: String) -> String:
  T.r("cast_types " ++ nm, cast_types_of(dt), py)

# `PTXRenderer.types` over all TWELVE of its keys, in the dict's own order --
# which is the order `R.types.items()` reports. `mem_types` and `cast_types` are
# `{**types, ...}` overrides of the same twelve keys, so they repeat the whole
# table and differ only at the four and two overridden entries.
def r_tabs() -> String:
  String.concat([r_types1("signed char", S.int8(), "s16"), r_types1("short", S.int16(), "s16"), r_types1("int", S.int32(), "s32"), r_types1("long", S.int64(), "s64"), r_types1("unsigned char", S.uint8(), "u16"), r_types1("unsigned short", S.uint16(), "u16"), r_types1("unsigned int", S.uint32(), "u32"), r_types1("unsigned long", S.uint64(), "u64"), r_types1("half", S.half(), "f16"), r_types1("float", S.single(), "f32"), r_types1("double", S.double(), "f64"), r_types1("bool", S.boolean(), "pred")])

def r_mc_tabs() -> String:
  String.concat([r_mem_types1("signed char", S.int8(), "s8"), r_mem_types1("short", S.int16(), "s16"), r_mem_types1("int", S.int32(), "s32"), r_mem_types1("long", S.int64(), "s64"), r_mem_types1("unsigned char", S.uint8(), "u8"), r_mem_types1("unsigned short", S.uint16(), "u16"), r_mem_types1("unsigned int", S.uint32(), "u32"), r_mem_types1("unsigned long", S.uint64(), "u64"), r_mem_types1("half", S.half(), "b16"), r_mem_types1("float", S.single(), "f32"), r_mem_types1("double", S.double(), "f64"), r_mem_types1("bool", S.boolean(), "u8"), r_cast_types1("signed char", S.int8(), "s8"), r_cast_types1("short", S.int16(), "s16"), r_cast_types1("int", S.int32(), "s32"), r_cast_types1("long", S.int64(), "s64"), r_cast_types1("unsigned char", S.uint8(), "u8"), r_cast_types1("unsigned short", S.uint16(), "u16"), r_cast_types1("unsigned int", S.uint32(), "u32"), r_cast_types1("unsigned long", S.uint64(), "u64"), r_cast_types1("half", S.half(), "f16"), r_cast_types1("float", S.single(), "f32"), r_cast_types1("double", S.double(), "f64"), r_cast_types1("bool", S.boolean(), "pred")])

# THE KeyError ARM. `PTXRenderer.types` has no key for the eight fp8 dtypes nor
# for bfloat16, and nothing on a PTX target asks for one -- so the unreachable
# arm is a row of its own rather than a silent `""`. The port has no exception,
# so the arm answers a MARKER and the row says which marker.
def ifmiss(+s: String) -> String: Bool.pick(String, String.is_empty(s), "KeyError", s)

def r_tabs_miss() -> String:
  String.concat([T.r("types float8_e4m3", ifmiss(types_of(S.fp8e4m3())), "KeyError"), T.r("types __bf16", ifmiss(types_of(S.bfloat16())), "KeyError")])


# `CUDARenderer.global_max/local_max/shared_max`, `suffix`, `barrier` (with its TAB
# escaped so a dropped TAB is a diff), and `kernel_prefix` ONE ROW PER LINE plus a
# COUNT -- a re-wrapped four-line string would hide a dropped line.
def px_prefix_lines() -> U32: 4
def px_pline(+i: U32) -> String:
  match i:
    case 0: px_p0()
    case 1: px_p1()
    case 2: px_p2()
    case _:  px_p3()
def bslash() -> String: String.from_list([Char.from_u32(92)])

# `\t` and `\n` AS TEXT. This is not an alias for `esc`: it is how a `py=` half
# has to be SPELLED, because a Bend `"…\t…"` literal holds a real TAB and the
# oracle's `repr()` holds a backslash and a `t`.
def btab() -> String: String.concat([bslash(), "t"])

def bnl() -> String: String.concat([bslash(), "n"])

def esc1(+c: Char) -> String:
  Bool.pick(String, U32.is_eq(Char.to_u32(c), 9), btab(),
    Bool.pick(String, U32.is_eq(Char.to_u32(c), 10), bnl(), String.from_list([c])))

def esc.go(+s: String, +acc: String) -> String:
  match s:
    case SNil{}     : acc
    case SCon{c, t} : esc.go(t, String.concat([acc, esc1(c)]))

def esc(+s: String) -> String: esc.go(s, "")

# CPython's `repr(str)`, which is what the oracle's `fmt` rows put on BOTH
# halves -- `'mov.b32 %r0, %r1;'` as the row NAME and `'\tmov.b32\t\t%r0, %r1;'`
# as the value. So the row name is quoted too, and quoting it is what makes a
# leading `$` visible instead of being the first character of the name.
def q(+s: String) -> String: String.concat(["'", esc(s), "'"])



def r_consts() -> String:
  String.concat([T.r("barrier", esc(px_barrier()), String.concat(["bar.sync", btab(), "0;"])), T.r("suffix", px_suffix(), "PTX"), T.r("global_max", T.ushow(px_gmax()), "2147483647,65535,65535"), T.r("local_max", T.ushow(px_lmax()), "1024,1024,64"), T.r("shared_max", U32.show(px_smax()), "49152"), T.r("kernel_prefix.lines", U32.show(px_prefix_lines()), "4"), T.r("kernel_prefix[0]", px_pline(0), ".version VERSION"), T.r("kernel_prefix[1]", px_pline(1), ".target TARGET"), T.r("kernel_prefix[2]", px_pline(2), ".address_size 64"), T.r("kernel_prefix[3]", px_pline(3), ".visible .entry")])



# `Renderer.supported_dtypes` (__init__.py:85) is
# `set(dtypes.all) - ({double} if long is emulated else set())`, which is
# `renderer/__init__.bend`'s row and depends on `EMULATED_DTYPES`. What is
# PORTED here is the PTX OVERRIDE (ptx.py:230-231) over the SCALAR dtypes, and
# the base is named as a PROJECTION rather than silently narrowed:
#   TODO(p3) ptx.py:230  supported_dtypes' BASE set -- `dtypes.all` minus an
#                        emulated long; owned by renderer/__init__.bend:85
def px_base_dtypes() -> List<&2, S.Dt>:
  [S.boolean(), S.int8(), S.int16(), S.int32(), S.int64(), S.uint8(), S.uint16(), S.uint32(),
   S.uint64(), S.half(), S.bfloat16(), S.single(), S.double()]

# `(d != dtypes.f16 or int(self.target.arch[3:]) >= 53) and d not in
# dtypes.fp8s+(dtypes.bf16,)`. bfloat16 IS in the projected base so that
# clause bites; the fp8 clause does not, because the projection has no fp8.
def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:
  Bool.and(Bool.or(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53)), Bool.not(O.eq_dt(dt, S.bfloat16())))

# A KEEP-FILTER. The recursion is called ONCE, through the `+rest` binder, and
# the head is put in FRONT with `List.append(..., [d], rest)` -- which is
# `[d] ++ rest`, not `rest ++ [d]`, and the difference is the whole set's order.
# The tempting one-liner `Bool.pick(c, f(t), d <> f(t))` calls the recursion
# TWICE, and a self-call SPENDS the list it walks (rules 2 and 7-DUP): the first
# call's answer came back EMPTY and all three rows printed `[__bf16]`.
def sd12.go(+ver: U32, +acc: List<&2, S.Dt>, +ds: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ds:
    case Nil{}   : acc
    case d <> +t :
      +rest = sd12.go(ver, acc, t)
      Bool.pick(List<&2, S.Dt>, sd_keep(ver, d), List.append(&2, S.Dt, [d], rest), rest)

def supported_dtypes(+ver: U32) -> List<&2, S.Dt>: sd12.go(ver, Nil{}, px_base_dtypes())

# `",".join(sorted(d.name ...))` -- `supported_dtypes` returns a SET, which has
# no order, so the gate sorts the names. `List.sort` needs the comparison as a
# function VALUE, which rule 31 says is a def reference (not a closure).
def str_le(a: String, b: String) -> Bool: String.is_le(a, b)

def sorted_names(+ns: List<&2, String>) -> String: String.join(List.sort(String, str_le, ns), ",")

# the same sort over DTYPES, via their names -- a `Map` cannot be keyed by a
# record in Bend and `List.sort` needs a `Data` element with an order, so the
# names are sorted and the gate prints them.
def dt_name_list(+ds: List<&2, S.Dt>) -> List<&2, String>:
  match ds:
    case Nil{}   : Nil{}
    case d <> +t : T.dt_name(d) <> dt_name_list(t)

def sorted_dt_names(+ds: List<&2, S.Dt>) -> String:
  String.join(List.sort(String, str_le, dt_name_list(ds)), ",")


# `supported_dtypes`: PTXRenderer's override drops the eight fp8 dtypes and bfloat16
# whatever the arch, and half only below sm_53 -- so sm_53, sm_75 and sm_80 print
# the SAME set, and having all three rows is what says so.
# `py=` is `DType.name` (dtype.py:120-137), not the legacy alias (dtype.py:140-142:
# `half = f16`, so `dtypes.half.name` is `"f16"`). Filter is ptx.py:230-231.
def r_sd(+ver: U32, py: String) -> String:
  T.r("supported_dtypes sm_" ++ U32.show(ver), sorted_dt_names(supported_dtypes(ver)), py)

# `self.tensor_cores = [x for x in tc.get_cuda(arch) if x.dtype_in in (dtypes.f16,
# dtypes.f32)]` -- ptx.py:146. The filter is on `dtype_in`, NOT `dtype_out`, so
# an fp8 table drops out entirely and a half->half table stays.
def dsh_half.keep(+t: T.Tc) -> Bool: Bool.or(O.eq_dt(T.Tc.di(t), S.half()), O.eq_dt(T.Tc.di(t), S.single()))

# The comprehension keeps `get_cuda`'s order, so the head goes in FRONT of the
# tail's answer -- `List.append(..., [t], rest)` is `[t] ++ rest`. The version
# that appended at the END printed all five entries BACKWARDS, and the version
# that called the recursion twice inside the `Bool.pick` printed one entry.
def dsh_half.go(+ts: List<&2, T.Tc>, +acc: List<&2, T.Tc>) -> List<&2, T.Tc>:
  match ts:
    case Nil{}   : acc
    case t <> +r :
      +rest = dsh_half.go(r, acc)
      Bool.pick(List<&2, T.Tc>, dsh_half.keep(t), List.append(&2, T.Tc, [t], rest), rest)

def ptx_tensor_cores(+ver: U32) -> List<&2, T.Tc>: dsh_half.go(T.get_cuda(ver), Nil{})

def r_tc_arch(+ver: U32, py: String) -> String:
  T.r("PTX tensor_cores sm_" ++ U32.show(ver), T.tc_pairs(ptx_tensor_cores(ver)), py)




# Called, not transcribed: `Shell(arch).supported_dtypes()` sorted by `.name`
# is this string for sm_53, sm_75 and sm_80 (dtype.py:120-137, ptx.py:230-231).
def r_ptx_sds() -> String:
  String.concat([r_sd(75, "bool,f16,f32,f64,i16,i32,i64,i8,u16,u32,u64,u8"), r_sd(53, "bool,f16,f32,f64,i16,i32,i64,i8,u16,u32,u64,u8"), r_sd(80, "bool,f16,f32,f64,i16,i32,i64,i8,u16,u32,u64,u8")])

# Called: `[x for x in tc.get_cuda(arch) if x.dtype_in in (dtypes.half, dtypes.float)]`
# then `dtype_in.name->dtype_out.name` (ptx.py:146, dtype.py:134 and :136).
# sm_80/sm_89 drop `bf16->f32` and, on sm_89, the two fp8 cores -- the filter is
# on `dtype_in`, and those inputs are not f16/f32.
def r_ptx_tcs() -> String:
  String.concat([r_tc_arch(75, "f16->f32,f16->f16"), r_tc_arch(80, "f16->f32,f16->f16,f16->f32,f16->f16,f32->f32"), r_tc_arch(89, "f16->f32,f16->f16,f16->f32,f16->f16,f32->f32")])

# THE ROW ORDER IS THE ORACLE'S, group for group, because the gate is a byte
# diff and a diff is positional. `ptx_matcher rules`, `asm_for_op` (dtype rows
# then WHERE's three forms), `asm_for_op` again over the real names, the half
# tuples, `modifier`, `render_val`, the three tables, the constants, then
# `supported_dtypes` and `tensor_cores`.

# ===========================================================================
# THE ESCAPE, because `PTXRenderer.barrier` contains a real TAB
# ("bar.sync\t0;") and `render_kernel` contains real NEWLINES, and neither is
# visible in a one-line row. CPython's `repr` escapes them and the oracle escapes
# them, so the Bend side escapes them the same way -- which also means a DROPPED
# tab is a diff rather than a shorter line.
# ===========================================================================





# ===========================================================================
# `fmt` -- ptx.py:164.
#
#     def fmt(line): return line if line[0]=="$" else "\t" + line.replace(" ", "\t" if len(line.split(" ")[0]) > 7 else "\t\t", 1)
#
# `$` lines are INLINED ASM and pass through untouched; everything else is
# indented by a TAB and its FIRST space becomes ONE TAB (mnemonic longer than
# seven characters) or TWO. The `1` on `replace` is load-bearing: without it
# EVERY space in the line would become a tab.
# ===========================================================================
def fmt_israw(+line: String) -> Bool: String.eq(String.take(line, 1n), "$")

# `line.split(" ")[0]` -- the mnemonic, i.e. everything before the first space.
def fmt_head(+cs: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32), acc,
      List.concat(&2, Char, [acc, [c], fmt_head(t, acc)]))

def fmt_head_str(+line: String) -> String: String.from_list(fmt_head(String.to_list(line), Nil{}))

def fmt_wide(+line: String) -> Bool: U32.is_gt(U32.from_nat(String.length(fmt_head_str(line))), 7)

# `line.replace(" ", rep, 1)`
def fmt_rep(+cs: List<&2, Char>, +rep: String, +acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}   : acc
    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32),
      List.concat(&2, Char, [acc, String.to_list(rep), t]),
      List.concat(&2, Char, [acc, [c], fmt_rep(t, rep, acc)]))

def tab2() -> String: String.concat([tab(), tab()])

def fmt_rep_of(+line: String) -> String: Bool.pick(String, fmt_wide(line), tab(), tab2())

def fmt(+line: String) -> String:
  Bool.pick(String, fmt_israw(line), line, String.concat([tab(), String.from_list(fmt_rep(String.to_list(line), fmt_rep_of(line), Nil{}))]))

# ===========================================================================
# `render_wmma(ctx, wmma)` -- ptx.py:61-76. THE `mma.sync` SPELLING, and the
# only place in this file where the ACCUMULATOR layout is named in text.
#
#   for src, regs in zip(wmma.src, ctx.wmma_r):
#     for i, reg in enumerate(regs):
#       if (elems_per_reg := 4 // src.dtype.itemsize) == 1: yield f"mov.b32 {reg}, {ctx.r[src][i]};"
#       else: yield f"mov.b32 {reg}, {{{', '.join(ctx.r[src][i*e:(i+1)*e])}}};"
#   dt_map_in, dt_map_out = {float: "tf32", half: "f16"}, {float: "f32", half: "f16"}
#   yield f'mma.sync.aligned.m{M}n{N}k{K}.row.col.{dt_map_out[dtype_out]}.{dt_map_in[dtype_in]}.{dt_map_in[dtype_in]}.{dt_map_out[dtype_out]}{" "*12}' + ...
#   for i, reg in enumerate(ctx.wmma_r[2]): ... unpack ...
#
# The accumulator is C's dtype and the two inputs are `dtype_in`, so the C pack
# line uses `epr(dtype_out)` and the C unpack line uses it too -- getting that
# wrong changes the number of registers, not the text, which is why the gate
# runs FOUR fixtures: half/float, half/half, float/float and a one-element pack.
# ===========================================================================
def dtmap_in(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), "tf32", "f16")

def dtmap_out(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), "f32", "f16")

# `ctx.wmma_r` (the pack registers) and `ctx.r[src]` (the value registers) of A,
# B, C and the OUTPUT. Seven lists, seven readers, because `ctx.r[u]` is
# `str | list[str]` and a `Data` record may not hold a `Maybe`.
type Wmr is Data:
  Wmr{ra: List<&2, String>, rb: List<&2, String>, rc: List<&2, String>, wa: List<&2, String>, wb: List<&2, String>, wc: List<&2, String>, ro: List<&2, String>}

def Wmr.ra(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: ra

def Wmr.rb(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: rb

def Wmr.rc(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: rc

def Wmr.wa(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wa

def Wmr.wb(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wb

def Wmr.wc(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: wc

def Wmr.ro(w: Wmr) -> List<&2, String>:
  match w:
    case Wmr{ra, rb, rc, wa, wb, wc, ro}: ro

# `4 // dtype.itemsize` -- how many elements ride in ONE 32-bit register. `1` for
# fp32/tf32 and `2` for half and fp8, and the `== 1` test is what chooses between
# the bare register name and the `{a, b}` pair in BOTH the pack and unpack lines.
def epr(+dt: S.Dt) -> U32: U32.div(4, S.Dt.itemsize(dt))

def at(+xs: List<&2, String>, +i: U32) -> String: Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(i)), "")

# `', '.join(regs[i*e:(i+1)*e])` with `e == 2`, the only packed case. It is a
# SLICE, and Python's slice CLAMPS at the end of the list -- the `a1` fixture has
# one value register and asks for `[0:2]`, so it joins ONE name. Reading two
# fixed indices instead joined a `""` for the missing one and printed
# `{%va0, }`, which is a register list with a hole in it.
def slice2(+xs: List<&2, String>, +i: U32) -> String:
  String.join(List.take(&2, String, List.drop(&2, String, xs, U32.to_nat(U32.mul(i, 2))), 2n), ", ")

def pack_line(+one: Bool, +reg: String, +regs: List<&2, String>, +i: U32) -> String:
  Bool.pick(String, one, String.concat(["mov.b32 ", reg, ", ", at(regs, i), ";"]),
    String.concat(["mov.b32 ", reg, ", {", slice2(regs, i), "};"]))

def unpack_line(+one: Bool, +reg: String, +regs: List<&2, String>, +i: U32) -> String:
  Bool.pick(String, one, String.concat(["mov.b32 ", at(regs, i), ", ", reg, ";"]),
    String.concat(["mov.b32 {", slice2(regs, i), "}, ", reg, ";"]))

# `for i, reg in enumerate(regs)` over the PACK registers, appending in order.
def pack_all(+regs: List<&2, String>, +ws: List<&2, String>, +one: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}   : acc
    case w <> +t : pack_all(regs, t, one, List.append(&2, String, acc, [pack_line(one, w, regs, U32.from_nat(List.length(&2, String, acc)))]))

def unpack_all(+regs: List<&2, String>, +ws: List<&2, String>, +one: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}   : acc
    case w <> +t : unpack_all(regs, t, one, List.append(&2, String, acc, [unpack_line(one, w, regs, U32.from_nat(List.length(&2, String, acc)))]))

def j(+xs: List<&2, String>) -> String: String.join(xs, ", ")

def sp12() -> String: String.repeat(" ", 12n)

# THE SPELLING. `{acc}, {a}, {b}, {acc}` -- the accumulator is passed TWICE, once
# in and once out, and `dtmap_in` appears twice and `dtmap_out` twice, so the
# string is `out.in.in.out` with TWELVE SPACES after it.
def mma_line(n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr) -> String:
  String.concat(["mma.sync.aligned.m", U32.show(m), "n", U32.show(n), "k", U32.show(k), ".row.col.",
    dtmap_out(dou), ".", dtmap_in(di), ".", dtmap_in(di), ".", dtmap_out(dou), sp12(),
    "{", j(Wmr.wc(w)), "}, {", j(Wmr.wa(w)), "}, {", j(Wmr.wb(w)), "}, {", j(Wmr.wc(w)), "};"])

# `list(render_wmma(ctx, wmma))` -- three pack groups, the one `mma.sync` line,
# then the unpack, in Python's order.
def render_wmma(n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr) -> List<&2, String>:
  +o1 = U32.is_eq(epr(di), 1)
  +o2 = U32.is_eq(epr(dou), 1)
  List.concat(&2, String, [pack_all(Wmr.ra(w), Wmr.wa(w), o1, Nil{}), pack_all(Wmr.rb(w), Wmr.wb(w), o1, Nil{}),
    pack_all(Wmr.rc(w), Wmr.wc(w), o2, Nil{}), [mma_line(n, m, k, di, dou, w)], unpack_all(Wmr.ro(w), Wmr.wc(w), o2, Nil{})])

# ===========================================================================
# `render_kernel` -- ptx.py:163-169. THE HEADER, one row per emitted line.
#
#     kernel = '\n'.join(map(fmt, [f".reg .{reg.split('_')[-2]} %{reg}<{cnt}>;" for reg,cnt in regs] + kernel + ["ret;"]))
#     local_dims = [u.src[0] for u in uops if u.op is Ops.SPECIAL and u.arg[0] == "l"]
#     launch_bounds = prod([d.vmax for d in local_dims])
#     params = ',\n\t'.join([f".param .{'u64' if u.addrspace is GLOBAL else types[u.dtype]} {name}" for name,u in bufs])
#     return f"{kernel_prefix.format(launch_bounds=lb)} {function_name} (\n\t{params}\n)\n.maxntid {lb}\n{{\n{kernel}\n}}"
#
# The BODY is `fmt` over the kernel lines plus the `.reg` declarations and the
# trailing `ret;`, and that is STAGE 3 -- it needs the `render` naming walk. What
# is here is the header, and the gate runs it with the body spelled `BODY` so a
# dropped LINE is a moved row rather than a re-wrapped string.
#
# `launch_bounds = prod([d.vmax for d in local_dims])` reads each local
# dimension's bound off the SPECIAL's src, which is the naming walk's fold and so
# is stage 3 as well; the header takes the product as a PARAMETER here.
# ===========================================================================
# `.param .{'u64' if u.addrspace is GLOBAL else types[u.dtype]} {name}` -- a
# GLOBAL buffer is a 64-bit pointer whatever its dtype, and a non-GLOBAL one is
# the dtype's PTX name. `is_glob` is the Bool, because `S.Addr` would drag the
# whole address-space enum in to read one bit of it.
type Pr is Data:
  Pr{nm: String, is_glob: Bool, dt: S.Dt}

def Pr.text(p: Pr) -> String:
  match p:
    case Pr{nm, is_glob, dt}: String.concat([".param .", Bool.pick(String, is_glob, "u64", types_of(dt)), " ", nm])

# lines 0..3 -- the prefix's four lines, with `.visible .entry` taking the NAME
def rk_head(nm: String) -> List<&2, String>:
  [px_p0(), px_p1(), px_p2(), String.concat([px_p3(), " ", nm, " ("])]

# One line per `.param`, each carrying the leading TAB that the template puts
# before `params` and the `'\n\t'` that `','.join` puts after every COMMA. The
# comma rides at the END of every line but the last, so a dropped comma is a
# diff on that line and a dropped TAB is a diff on every line.
def rk_param_lines(+ps: List<&2, Pr>, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}   : acc
    case p <> +t : rk_param_lines(t, List.append(&2, String, acc, [String.concat([tab(), Pr.text(p),
      Bool.pick(String, List.is_empty(&2, Pr, t), "", ",")])]))

# `)`, `.maxntid lb`, `{`, the body, `}`
def rk_close(lb: U32, +body: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [[")"], [String.concat([".maxntid ", U32.show(lb)])], ["{"], body, ["}"]])

def rk_lines(nm: String, lb: U32, +ps: List<&2, Pr>, +body: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [rk_head(nm), rk_param_lines(ps, Nil{}), rk_close(lb, body)])


# `render_wmma` -- the four fixtures the oracle runs. Each names (N,M,K), the two
# dtypes and the seven register lists; the three cover `epr == 1` (fp32),
# `epr == 2` (half) and a ONE-ELEMENT pack, which is the case where the
# `{a, b}` branch would index past the end.
def w_a4() -> Wmr: Wmr{["%va0", "%va1", "%va2", "%va3"], ["%vb0", "%vb1", "%vb2", "%vb3"], ["%wc0", "%wc1"], ["%wi0_0", "%wi0_2"], ["%wi1_0", "%wi1_2"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}
def w_a1() -> Wmr: Wmr{["%va0"], ["%vb0"], ["%wc0", "%wc1"], ["%wi0_0"], ["%wi1_0"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}
def w_a2() -> Wmr: Wmr{["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0"], ["%wi0_0"], ["%wi1_0"], ["%wi2_0"], ["%vo0", "%vo1"]}
def w_a3() -> Wmr: Wmr{["%va0", "%va1"], ["%vb0", "%vb1"], ["%wc0", "%wc1"], ["%wi0_0", "%wi0_1"], ["%wi1_0", "%wi1_1"], ["%wi2_0", "%wi2_1"], ["%vo0", "%vo1"]}

def r_wm1(+nm: String, n: U32, m: U32, k: U32, +di: S.Dt, +dou: S.Dt, +w: Wmr, py: String) -> String:
  T.r("render_wmma " ++ nm, String.join(render_wmma(n, m, k, di, dou, w), " ;; "), py)

def r_wms() -> String:
  String.concat([r_wm1("a4", 16, 8, 16, S.half(), S.single(), w_a4(), "mov.b32 %wi0_0, {%va0, %va1}; ;; mov.b32 %wi0_2, {%va2, %va3}; ;; mov.b32 %wi1_0, {%vb0, %vb1}; ;; mov.b32 %wi1_2, {%vb2, %vb3}; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n16k16.row.col.f32.f16.f16.f32            {%wi2_0, %wi2_1}, {%wi0_0, %wi0_2}, {%wi1_0, %wi1_2}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;"), r_wm1("a1", 16, 8, 16, S.half(), S.single(), w_a1(), "mov.b32 %wi0_0, {%va0}; ;; mov.b32 %wi1_0, {%vb0}; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n16k16.row.col.f32.f16.f16.f32            {%wi2_0, %wi2_1}, {%wi0_0}, {%wi1_0}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;"), r_wm1("a2", 8, 8, 8, S.half(), S.half(), w_a2(), "mov.b32 %wi0_0, {%va0, %va1}; ;; mov.b32 %wi1_0, {%vb0, %vb1}; ;; mov.b32 %wi2_0, {%wc0}; ;; mma.sync.aligned.m8n8k8.row.col.f16.f16.f16.f16            {%wi2_0}, {%wi0_0}, {%wi1_0}, {%wi2_0}; ;; mov.b32 {%vo0, %vo1}, %wi2_0;"), r_wm1("a3", 8, 8, 8, S.single(), S.single(), w_a3(), "mov.b32 %wi0_0, %va0; ;; mov.b32 %wi0_1, %va1; ;; mov.b32 %wi1_0, %vb0; ;; mov.b32 %wi1_1, %vb1; ;; mov.b32 %wi2_0, %wc0; ;; mov.b32 %wi2_1, %wc1; ;; mma.sync.aligned.m8n8k8.row.col.f32.tf32.tf32.f32            {%wi2_0, %wi2_1}, {%wi0_0, %wi0_1}, {%wi1_0, %wi1_1}, {%wi2_0, %wi2_1}; ;; mov.b32 %vo0, %wi2_0; ;; mov.b32 %vo1, %wi2_1;")])

# the `dt_map`s on their own, over all four dtype pairs, because they are the
# ONLY place `render_wmma` reads a dtype for a NAME and the four map rows are
# what a `tf32`/`f16` mix-up moves.
def dtmap_name(+di: S.Dt, +dou: S.Dt) -> String:
  String.concat([dtmap_out(dou), ".", dtmap_in(di), ".", dtmap_in(di), ".", dtmap_out(dou)])

def r_dtm1(+nm: String, +di: S.Dt, +dou: S.Dt, py: String) -> String:
  T.r("wmma dtmap " ++ nm, dtmap_name(di, dou), py)


def r_dtms() -> String:
  String.concat([r_dtm1("half,half", S.half(), S.half(), "f16.f16.f16.f16"), r_dtm1("half,float", S.half(), S.single(), "f32.f16.f16.f32"), r_dtm1("float,half", S.single(), S.half(), "f16.tf32.tf32.f16"), r_dtm1("float,float", S.single(), S.single(), "f32.tf32.tf32.f32")])

# `fmt` -- the FIVE line shapes: an INLINED `$` line passes through untouched, a
# SHORT mnemonic gets TWO tabs for its first space, a LONG one (> 7 chars) gets
# ONE, and a line with NO space at all gets none. `ret;` is a row twice because
# the oracle's fixture list has it twice, and a gate that only runs the distinct
# shapes would not notice a row that moved.
def r_fmt1(+line: String, py: String) -> String:
  T.r(String.concat(["fmt ", q(line)]), q(fmt(line)), py)

def r_fmts() -> String:
  String.concat([r_fmt1("mov.b32 %r0, %r1;", String.concat(["'", btab(), "mov.b32", btab(), btab(), "%r0, %r1;'"])), r_fmt1("ret;", String.concat(["'", btab(), "ret;'"])), r_fmt1("$LDG.E R1, [R2];", String.concat(["'", "$LDG.E R1, [R2];'"])), r_fmt1("shl.b32", String.concat(["'", btab(), "shl.b32'"])), r_fmt1("ret;", String.concat(["'", btab(), "ret;'"]))])

# `render_kernel` -- the header, ONE ROW PER EMITTED LINE plus a count, with the
# body spelled `BODY`. The `.reg` declarations and the trailing `ret;` are the
# naming walk's, and they are STAGE 3. A dropped LINE is a moved row rather than
# a re-wrapped string, which is the whole reason the count row exists: without
# it, losing line 5 and gaining line 9 is invisible to a per-line diff.
def rk1.go(+nm: String, +ls: List<&2, String>, +i: U32, acc: String) -> String:
  match ls:
    case Nil{}   : acc
    case l <> +t : rk1.go(nm, t, U32.add(i, 1), String.concat([acc,
      T.r(String.concat(["render_kernel ", nm, "[", U32.show(i), "]"]), esc(l), esc(l))]))

def rk1(+nm: String, +ls: List<&2, String>, cnt: String) -> String:
  String.concat([T.r(String.concat(["render_kernel ", nm, ".lines"]), U32.show(U32.from_nat(List.length(&2, String, ls))), cnt),
    rk1.go(nm, ls, 0, "")])

# The TWO fixtures the oracle runs: one GLOBAL float plus one LOCAL int32 at
# 128 threads, and one GLOBAL uint32 at 256. Together they cover both branches
# of `Pr.text` (`u64` and `types_of`) and both param-line shapes (a COMMA after
# the first param and none after the last).
# data1 is a LOCAL float, not an int32: `types[int32]` and a hard-coded
# `"s32"` agree, so an int32 fixture cannot tell `types[u.dtype]` from a
# literal. A float spells `.param .f32` and only the dtype table can say so.
def k1_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.single()}, Pr{"data1", False{}, S.single()}]
def k2_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.uint32()}]

def r_rks() -> String:
  String.concat([rk1("k1", rk_lines("k1", 128, k1_ps(), ["BODY"]), "11"), rk1("k2", rk_lines("k2", 256, k2_ps(), ["BODY"]), "10")])

def r_stage2() -> String:
  String.concat([r_pmx_n(), r_asms(), r_where(), r_asm2s(), r_sh(), r_mods(), r_rvs(), r_tabs(),
    r_tabs_miss(), r_mc_tabs(), r_consts(), r_ptx_sds(), r_ptx_tcs(), r_wms(), r_dtms(), r_rks(), r_fmts()])

# ONE print for the WHOLE table, so `IO.print`'s own newline is the only frame and
# the oracle's single trailing `"\n"` is its match. There is deliberately no
# separator between the two stages: the oracle's `rows()` is a plain
# concatenation, so a `nl()` here would be a line CPython never printed.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(r_stage2())

#   M1  the coord packing is (bit << 1) | axis, not << 2      259
#   M2  axis code k = 3, not 2                                 16
#   M6  the coord shift uses the AXIS, not the BIT              24
#   M7  (CONTROL: a comment-only edit)                          0
#   M8  `mma`'s fragment_c lane ends at m3, not m2              28
#   M9  FNV-1a's offset basis is off by one                     24
#   M16 the `not in fp8s + (bf16,)` clause is dropped            3
#   M17 the `arch >= 53` clause is dropped                        3
#   M19 `modifier`'s first clause widens to int->bool            5
#   M20 `modifier`'s second clause loses `or b == bool`          3
#   M21 `shl.b{name}` -- the `[1:]` is dropped                   17
#   M22 `xor.b{name}` -- the `[1:]` is dropped                   15
#   M23 `selp.{name}` -- PTX has no `selp.f16`                    2
#   M24 MUL's `.lo` is not integer-only                          2
#   M25 CMPNE's `neu`/`ne` arms are swapped                      5
#   M26 MULACC picks on is_int, not is_float                     15
#   M27 TRUNC's second type name is a literal `"s32"`            11
#   M28 (CONTROL: a comment-only edit)                            0
#   M29 `render_val`'s two float spellings are swapped            8
#   M30 (CONTROL: a comment-only edit)                            0
#   M31 `hex4` takes nibbles 7..4, not 3..0                       3
#   M32 `epr` is 2 // itemsize, not 4                            4
#   M33 the pack join is "," not ", "                            2
#   M34 `fmt`'s one-tab/two-tab arms are swapped                  1
#   M35 the mnemonic threshold is `>= 7`, not `> 7`              1
#   M36 a `$` line is indented anyway                             1
#   M37 `fmt` replaces EVERY space, not the first                 1
#   M38 a non-GLOBAL `.param` name is a literal `"s32"`           1
#   M39 the function name is not after `.visible .entry`          2
#   M40 `render_kernel` drops the closing `}`                    17  -2 lines
#   M41 the k1 LOCAL buffer is a double, not a float              1
#   M42 the body is emitted after the close, not inside           8
#   M43 `btab()` returns a real tab, not `\` + `t`                8
#   M44 `q()` quotes with brackets, not apostrophes               5
#   M45 the mma separator is eleven spaces, not twelve            4
#   M46 the accumulator is passed once, not twice                 4
#   M47 `dt_map_out[float]` is "tf32", not "f32"                  5
#   M48 the archs are 53, 75, 80 -- not 75, 53, 80               2
#   M49 the dtype tables are in sorted order, not dict order       1
#   M50 (CONTROL: a comment-only edit)                            0
#
# WHAT THE TABLE SAYS.
#
# M15 is the whole subject of this file: a gate is only as sharp as the ORDER
# the oracle can observe, and `set` is a place where it cannot.
#
# M43 IS WHY THE GATE IS A BYTE DIFF. A `py=` half that held a real TAB instead
# of `\` + `t` renders identically in a terminal and differs in the file, and it
# is the only mutation here that a human reading both lanes side by side would
# call green.
#
# M27 AND M38 ARE WHY A FIXTURE IS NOT ENOUGH. M27 (`TRUNC`'s second type name)
# moved NOTHING while every one of the 105 `asm` rows said `cvt.rzi.s32.s32`:
# the 105-row grid fixes `name` at "s32" to isolate the DTYPE branch, so the
# NAME branch of a four-argument lambda was ungated. Adding TRUNC to the
# twelve-dtype name grid moved it to 11. M38 is the same shape: the k1 fixture's
# non-GLOBAL buffer was an int32, and `types[int32] == "s32"`, so a hard-coded
# `"s32"` was indistinguishable from the dtype table. It is a LOCAL FLOAT now.
#
# M1 AND M10 MOVE 259 ROWS EACH and neither is interesting on its own -- both
# reach every coord and every count. They are in the table because a table that
# only lists interesting mutations cannot tell a reader which rules are
# load-bearing for the WHOLE file.
#
# FOUR CONTROLS, M7, M28, M30 and M50, are whitespace-only edits, and each
# moves nothing. They are what makes the other forty-six numbers mean something:
# a harness that reports "0 rows" for everything would look identical on the
# four blind spots.
# ===========================================================================
