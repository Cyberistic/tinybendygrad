# tinybendygrad/renderer/nir.bend -- tinygrad/renderer/nir.py

# the file, and the two measured facts that decided its shape.
#
# `nir.py` is 321 lines of which almost none is data: it is `ctypes` calls into
# mesa (`nir_def_init`, `nir_builder_instr_insert`, `nir_intrinsic_instr_create`,
# `ralloc_free`). What it DOES carry is a typed IR's algebra -- the three ALU op
# tables, the `glsl_type` map, the `c` prefix, the `ncast` name, the intrinsic
# `WRITE_MASK`/`ALIGN_MUL`/`ACCESS` arithmetic, `scope`, `padded_idx` -- and
# that algebra is exactly the part where a silently wrong entry is a silently
# wrong instruction. So this file ports the ALGEBRA and names the FFI.
#
# FACT ONE, and it is why `glsl_type` is a REFUSAL here and not a table.
# `mesa.glsl_type_builtin_*` is NOT REACHABLE ON THIS TREE. It is bound inside a
# `try: ... .in_dll(dll, ...)` -- `glsl_type_builtin_error` at
# `tinygrad/runtime/autogen/mesa.py:5375` -- and `dll` is the LAZY `c.DLL` of

import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../LAWS/spec.bend as S

# THE GATE PRIMITIVES. Same shape as `nir_llvmir.bend`'s: a row is a VALUE, so a

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

def rd(+nm: String, +got: String) -> String: r(nm, got, got)

def b2s(+x: Bool) -> String: Bool.pick(String, x, "True", "False")

# `spec.bend`'s `Dt.nm`. `nir_llvmir.bend` carries the same fifth reader. Kept
# LOCAL rather than shared on purpose: two independent readers of one field are
# two chances for the gate to disagree with itself, and a gate that cannot
# disagree is not a gate.
def dtn(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# The seventeen, in dtype.py's declaration order -- the same order
# `__init__.bend`'s `dtypes_all` rebuilds and the same order CPython's
# `dtypes.all` has. A dropped dtype moves every string below.
def all_fp8() -> List<&2, S.Dt>: [S.fp8e4m3(), S.fp8e5m2(), S.fp8e4m3fnuz(), S.fp8e5m2fnuz()]

def all_float() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, all_fp8(), [S.half(), S.bfloat16(), S.single(), S.double()])

def all_uint() -> List<&2, S.Dt>: [S.uint8(), S.uint16(), S.uint32(), S.uint64()]

def all_sint() -> List<&2, S.Dt>: [S.int8(), S.int16(), S.int32(), S.int64()]

def all_int() -> List<&2, S.Dt>: List.append(&2, S.Dt, all_uint(), all_sint())

def all_of() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, all_float(), all_int()), [S.boolean()])

# THE THREE dtypes `dtypes.all` does NOT hold, kept because they are the rows
# that separate `in_ints` from `S.Dt.is_int`. See the `weakint` rows below.
def all_out() -> List<&2, S.Dt>: [S.void(), S.weakint(), S.weakfloat(), S.index()]

# `,`.join over a list. THREE helpers because Bend has no fold returning a
# `String` here and `String.concat`'s silent literal drop is exactly the failure
# these rows exist to catch -- so the join is built by APPENDING, never by
# writing a literal separator into a `concat` list that might lose it.
def jgo(+xs: List<&2, String>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> +t: jgo(t, String.concat([acc, ",", h]))

def join(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> +t: jgo(t, h)

def ngo(+xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> +t: ngo(t, String.concat([acc, ",", U32.show(h)]))

def unum(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case h <> +t: ngo(t, U32.show(h))

def dngo(+ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case d <> +t: dngo(t, String.concat([acc, ",", dtn(d)]))

def dnames(+ds: List<&2, S.Dt>) -> String:
  match ds:
    case Nil{}: ""
    case d <> +t: dngo(t, dtn(d))

# the three set-membership tests, and they are not `S.Dt`'s.

def c.cls_uint(cls: S.Cls) -> Bool:
  match cls:
    case S.CUint{}: True{}
    case _: False{}

def c.cls_int(cls: S.Cls) -> Bool:
  match cls:
    case S.CSint{}: True{}
    case S.CUint{}: True{}
    case _: False{}

def c.cls_float(cls: S.Cls) -> Bool:
  match cls:
    case S.CFloat{}: True{}
    case _: False{}

# The class comes off a PATTERN BINDER rather than off `S.Dt.cls(d)`, because a
# call is a computed value and a `match` may not scrutinise one -- the same
# refusal `c`'s first draft hit at line 164.
def c.in_uints(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}: c.cls_uint(cls)

def c.in_ints(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}: c.cls_int(cls)

def c.in_floats(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, nm}: c.cls_float(cls)

# `c(t, u)` -- nir.py:26. FOUR arms, and the fourth is the reach for `bool`,
def c.arm3(d: S.Dt, is_float: Bool) -> String:
  match is_float:
    case True{}: "f"
    case False{}: "b"

def c.arm2(+d: S.Dt, is_int: Bool) -> String:
  match is_int:
    case True{}: "i"
    case False{}: c.arm3(d, c.in_floats(d))

def c.arm1(+d: S.Dt, is_uint: Bool) -> String:
  match is_uint:
    case True{}: "u"
    case False{}: c.arm2(d, c.in_ints(d))

def c(+d: S.Dt, unsigned: Bool) -> String: c.arm1(d, Bool.and(c.in_uints(d), unsigned))

# THE THREE ALU OP TABLES -- nir.py:19-23.

def op_const(nm: String) -> U32:
  match nm:
    case "iadd": 306
    case "imul": 338
    case "udiv": 427
    case "umod": 451
    case "ult": 441
    case "ilt": 326
    case "ine": 344
    case "ieq": 314
    case "ior": 353
    case "iand": 309
    case "ixor": 361
    case "bcsel": 115
    case "umax": 447
    case "imax": 334
    case "ishl": 356
    case "ushr": 479
    case "ishr": 357
    case "idiv": 313
    case "irem": 354
    case "fadd": 177
    case "fmul": 253
    case "flt": 240
    case "fneu": 260
    case "feq": 213
    case "fdiv": 198
    case "frcp": 270
    case "fmax": 248
    case "ftrunc": 288
    case "fsin": 279
    case "fexp2": 221
    case "flog2": 238
    case "fsqrt": 283
    case "mov": 365
    case "vec2": 484
    case "vec3": 485
    case "vec4": 486
    case "vec5": 487
    case "vec8": 488
    case "vec16": 483
    case "b2b1": 28
    case "b2f16": 32
    case "b2f32": 33
    case "b2f64": 34
    case "b2i8": 39
    case "b2i16": 36
    case "b2i32": 37
    case "b2i64": 38
    case "f2f16": 156
    case "f2f32": 159
    case "f2f64": 160
    case "f2i8": 166
    case "f2i16": 163
    case "f2i32": 164
    case "f2i64": 165
    case "i2f16": 293
    case "i2f32": 294
    case "i2f64": 295
    case "i2i8": 301
    case "i2i16": 298
    case "i2i32": 299
    case "i2i64": 300
    case "u2f16": 411
    case "u2f32": 412
    case "u2f64": 413
    case "u2u8": 419
    case "u2u16": 416
    case "u2u32": 417
    case "u2u64": 418
    case _: 0

# nine of the thirty-six CAST names do not exist: every `*2f8` (the fp8s are not
def op_present(nm: String) -> Bool:
  match nm:
    case "b2b1": True{}
    case "b2f16": True{}
    case "b2f32": True{}
    case "b2f64": True{}
    case "b2i8": True{}
    case "b2i16": True{}
    case "b2i32": True{}
    case "b2i64": True{}
    case "f2f16": True{}
    case "f2f32": True{}
    case "f2f64": True{}
    case "f2i8": True{}
    case "f2i16": True{}
    case "f2i32": True{}
    case "f2i64": True{}
    case "i2f16": True{}
    case "i2f32": True{}
    case "i2f64": True{}
    case "i2i8": True{}
    case "i2i16": True{}
    case "i2i32": True{}
    case "i2i64": True{}
    case "u2f16": True{}
    case "u2f32": True{}
    case "u2f64": True{}
    case "u2u8": True{}
    case "u2u16": True{}
    case "u2u32": True{}
    case "u2u64": True{}
    case "iadd": True{}
    case "imul": True{}
    case "udiv": True{}
    case "umod": True{}
    case "ult": True{}
    case "ilt": True{}
    case "ine": True{}
    case "ieq": True{}
    case "ior": True{}
    case "iand": True{}
    case "ixor": True{}
    case "bcsel": True{}
    case "umax": True{}
    case "imax": True{}
    case "ishl": True{}
    case "ushr": True{}
    case "ishr": True{}
    case "idiv": True{}
    case "irem": True{}
    case "fadd": True{}
    case "fmul": True{}
    case "flt": True{}
    case "fneu": True{}
    case "feq": True{}
    case "fdiv": True{}
    case "frcp": True{}
    case "fmax": True{}
    case "ftrunc": True{}
    case "fsin": True{}
    case "fexp2": True{}
    case "flog2": True{}
    case "mov": True{}
    case "vec2": True{}
    case "vec3": True{}
    case "vec4": True{}
    case "vec5": True{}
    case "vec8": True{}
    case "vec16": True{}
    case _: False{}

# The printed form of one cast cell: `name/value`, or `name/AttributeError` when
# mesa has no such op. THE ROW IS A STRING precisely so the two forms cannot be
# confused for one another.
def cast_cell.of(+present: Bool, +nm: String) -> String:
  match present:
    case True{}: String.concat([nm, "/", U32.show(op_const(nm))])
    case False{}: String.concat([nm, "/AttributeError"])

def cast_cell(+nm: String) -> String: cast_cell.of(op_present(nm), nm)

def intr_const(nm: String) -> U32:
  match nm:
    case "nir_intrinsic_store_global": 669
    case "nir_intrinsic_store_shared": 689
    case "nir_intrinsic_store_deref": 667
    case "nir_intrinsic_load_global": 317
    case "nir_intrinsic_load_shared": 489
    case "nir_intrinsic_load_deref": 287
    case "nir_intrinsic_load_workgroup_id": 580
    case "nir_intrinsic_load_local_invocation_id": 364
    case "nir_intrinsic_barrier": 46
    case "nir_intrinsic_ldc_nv": 213
    case "nir_intrinsic_load_ubo": 552
    case "nir_intrinsic_image_store": 191
    case "nir_intrinsic_image_load": 184
    case "nir_type_float16": 144
    case "nir_type_float32": 160
    case "nir_deref_type_var": 0
    case "nir_deref_type_array": 1
    case "nir_jump_break": 2
    case "MESA_SHADER_COMPUTE": 5
    case "SCOPE_WORKGROUP": 4
    case "ACCESS_CAN_REORDER": 64
    case "GLSL_SAMPLER_DIM_2D": 1
    case _: 0

# The `NIR_INTRINSIC_*` ENUM keys `nir_instr`'s `index_map` is indexed BY
# (nir.py:50). Present as generated ints even though `nir_intrinsic_infos` is
# not, so the keys are audited and the SLOTS they index are the wall.
def idx_const(nm: String) -> U32:
  match nm:
    case "NIR_INTRINSIC_ALIGN_MUL": 20
    case "NIR_INTRINSIC_WRITE_MASK": 1
    case "NIR_INTRINSIC_ACCESS": 17
    case "NIR_INTRINSIC_EXECUTION_SCOPE": 40
    case "NIR_INTRINSIC_IMAGE_DIM": 14
    case "NIR_INTRINSIC_SRC_TYPE": 23
    case "NIR_INTRINSIC_DEST_TYPE": 24
    case "NIR_INTRINSIC_RANGE": 5
    case _: 0

def u_aop(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "iadd"
    case O.OpsMUL{}: "imul"
    case O.OpsTRUNCDIV{}: "udiv"
    case O.OpsTRUNCMOD{}: "umod"
    case O.OpsCMPLT{}: "ult"
    case O.OpsCMPNE{}: "ine"
    case O.OpsCMPEQ{}: "ieq"
    case O.OpsOR{}: "ior"
    case O.OpsAND{}: "iand"
    case O.OpsXOR{}: "ixor"
    case O.OpsWHERE{}: "bcsel"
    case O.OpsMAX{}: "umax"
    case O.OpsSHL{}: "ishl"
    case O.OpsSHR{}: "ushr"
    case _: ""

def s_aop(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "iadd"
    case O.OpsMUL{}: "imul"
    case O.OpsTRUNCDIV{}: "idiv"
    case O.OpsTRUNCMOD{}: "irem"
    case O.OpsCMPLT{}: "ilt"
    case O.OpsCMPNE{}: "ine"
    case O.OpsCMPEQ{}: "ieq"
    case O.OpsOR{}: "ior"
    case O.OpsAND{}: "iand"
    case O.OpsXOR{}: "ixor"
    case O.OpsWHERE{}: "bcsel"
    case O.OpsMAX{}: "imax"
    case O.OpsSHL{}: "ishl"
    case O.OpsSHR{}: "ishr"
    case _: ""

def f_aop(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "fadd"
    case O.OpsMUL{}: "fmul"
    case O.OpsCMPLT{}: "flt"
    case O.OpsCMPNE{}: "fneu"
    case O.OpsCMPEQ{}: "feq"
    case O.OpsFDIV{}: "fdiv"
    case O.OpsRECIP{}: "frcp"
    case O.OpsMAX{}: "fmax"
    case O.OpsTRUNC{}: "ftrunc"
    case O.OpsSIN{}: "fsin"
    case O.OpsEXP2{}: "fexp2"
    case O.OpsLOG2{}: "flog2"
    case O.OpsSQRT{}: "fsqrt"
    case _: ""

# the reverse direction -- nir.py:19-23 read backwards, and not folded out of
# THE FORWARD ONE. See the header: folding would make the two rows agree by
# construction and an error made twice reads as zero disagreements.
def u_aop.rev(nm: String) -> String:
  match nm:
    case "iadd": "ADD"
    case "imul": "MUL"
    case "udiv": "TRUNCDIV"
    case "umod": "TRUNCMOD"
    case "ult": "CMPLT"
    case "ine": "CMPNE"
    case "ieq": "CMPEQ"
    case "ior": "OR"
    case "iand": "AND"
    case "ixor": "XOR"
    case "bcsel": "WHERE"
    case "umax": "MAX"
    case "ishl": "SHL"
    case "ushr": "SHR"
    case _: ""

def s_aop.rev(nm: String) -> String:
  match nm:
    case "iadd": "ADD"
    case "imul": "MUL"
    case "idiv": "TRUNCDIV"
    case "irem": "TRUNCMOD"
    case "ilt": "CMPLT"
    case "ine": "CMPNE"
    case "ieq": "CMPEQ"
    case "ior": "OR"
    case "iand": "AND"
    case "ixor": "XOR"
    case "bcsel": "WHERE"
    case "imax": "MAX"
    case "ishl": "SHL"
    case "ishr": "SHR"
    case _: ""

def f_aop.rev(nm: String) -> String:
  match nm:
    case "fadd": "ADD"
    case "fmul": "MUL"
    case "flt": "CMPLT"
    case "fneu": "CMPNE"
    case "feq": "CMPEQ"
    case "fdiv": "FDIV"
    case "frcp": "RECIP"
    case "fmax": "MAX"
    case "ftrunc": "TRUNC"
    case "fsin": "SIN"
    case "fexp2": "EXP2"
    case "flog2": "LOG2"
    case "fsqrt": "SQRT"
    case _: ""

# `aop` -- nir.py:24. `{{x:u_aop for x in (dtypes.bool,)+dtypes.uints},
# {x:s_aop for x in dtypes.sints}, {x:f_aop for x in dtypes.floats}}`.
#
# The INSERTION ORDER is bool, uints, sints, floats -- NOT `dtypes.all`'s
# floats-first order, and that is a real diff rather than a cosmetic one: it is
# why `aop keys` is a joined STRING and not a count. THREE classes, so the table
# is a `U32` TAG -- `0` unsigned/bool, `1` signed, `2` float -- which keeps
# `aop_of` total on all seventeen and makes an unreachable class a `3` no row
# can hide.
# `(dtypes.bool,) + dtypes.uints` (nir.py:24), so `bool` is in the SAME class as
def aop_kind.u(is_unsigned: Bool) -> U32:
  match is_unsigned:
    case True{}: 0
    case False{}: 1

def aop_kind.f(+d: S.Dt, is_float: Bool) -> U32:
  match is_float:
    case True{}: 2
    case False{}: aop_kind.u(Bool.or(c.in_uints(d), S.Dt.is_bool(d)))

def aop_kind(+d: S.Dt) -> U32: aop_kind.f(d, c.in_floats(d))

def aop_of(k: U32, op: O.Op) -> String:
  match k:
    case 0: u_aop(op)
    case 1: s_aop(op)
    case 2: f_aop(op)
    case _: ""

def aop_keys() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, List.append(&2, S.Dt, [S.boolean()], all_uint()), all_sint()), all_float())

# THE FOURTEEN OP NAMES, IN `u_aop`'s OWN ORDER (nir.py:19-20). The oracle emits
# each table's real `dict` order, so a reordering is a diff and not a set match.
def u_ops() -> List<&2, String>: ["ADD","MUL","TRUNCDIV","TRUNCMOD","CMPLT","CMPNE","CMPEQ","OR","AND","XOR","WHERE","MAX","SHL","SHR"]

def f_ops() -> List<&2, String>: ["ADD","MUL","CMPLT","CMPNE","CMPEQ","FDIV","RECIP","MAX","TRUNC","SIN","EXP2","LOG2","SQRT"]

def op_of(nm: String) -> O.Op:
  match nm:
    case "ADD": O.OpsADD{}
    case "MUL": O.OpsMUL{}
    case "TRUNCDIV": O.OpsTRUNCDIV{}
    case "TRUNCMOD": O.OpsTRUNCMOD{}
    case "CMPLT": O.OpsCMPLT{}
    case "CMPNE": O.OpsCMPNE{}
    case "CMPEQ": O.OpsCMPEQ{}
    case "OR": O.OpsOR{}
    case "AND": O.OpsAND{}
    case "XOR": O.OpsXOR{}
    # WHERE AND MAX WERE MISSING HERE. `aop rev` printed `WHERE:->/0` and
    # `MAX:->/0` on the first run, which is the reverse rows earning their cost
    # on the first run they existed.
    case "WHERE": O.OpsWHERE{}
    case "MAX": O.OpsMAX{}
    case "SHL": O.OpsSHL{}
    case "SHR": O.OpsSHR{}
    case "FDIV": O.OpsFDIV{}
    case "RECIP": O.OpsRECIP{}
    case "TRUNC": O.OpsTRUNC{}
    case "SIN": O.OpsSIN{}
    case "EXP2": O.OpsEXP2{}
    case "LOG2": O.OpsLOG2{}
    case "SQRT": O.OpsSQRT{}
    # `OpsCONST` and not `OpsNOP`: the arm must be a CONSTRUCTOR THAT EXISTS,
    # and it must be one no table names, so all three `match`es fall to `case _`
    # and answer "". `OpsCONST` is also the op `render` skips at nir.py:193.
    case _: O.OpsCONST{}

# `aop`'s table per class, in `u_ops()`/`f_ops()` order, each entry
# `OP=nir_name/mesa_value` -- ONE string carrying the whole chain
# Ops -> nir name -> mesa enum, so a wrong name and a wrong constant are both
# diffs and neither can hide behind the other.
def aop_rows(+k: U32, +ops: List<&2, String>, +acc: List<&2, String>) -> String:
  match ops:
    case Nil{}: join(acc)
    case h <> +t: aop_rows(k, t, Bool.pick(List<&2, String>, String.eq(aop_of(k, op_of(h)), ""), acc,
      List.append(&2, String, acc, [String.concat([h, "=", aop_of(k, op_of(h)), "/", U32.show(op_const(aop_of(k, op_of(h))))])])))

def aop_rev_of(k: U32, nm: String) -> String:
  match k:
    case 0: u_aop.rev(nm)
    case 1: s_aop.rev(nm)
    case 2: f_aop.rev(nm)
    case _: ""

# `glsl_type` -- nir.py:14-16. THE SYMBOL NAME is computed, not looked up:

def glsl_sym4.of3(d: S.Dt, is_half: Bool) -> String:
  match is_half:
    case True{}: "glsl_type_builtin_float16_t"
    case False{}: Bool.pick(String, R.is_named(d, "bool"), "glsl_type_builtin_uint8_t", "?")

def glsl_sym4.of2(+d: S.Dt, is_float: Bool) -> String:
  match is_float:
    case True{}: "glsl_type_builtin_float"
    case False{}: glsl_sym4.of3(d, R.is_named(d, "f16"))

def glsl_sym4.of(+d: S.Dt, is_double: Bool) -> String:
  match is_double:
    case True{}: "glsl_type_builtin_double"
    case False{}: glsl_sym4.of2(d, R.is_named(d, "f32"))

def glsl_sym4(+d: S.Dt) -> String: glsl_sym4.of(d, R.is_named(d, "f64"))

# `bits` is read TWICE -- once for the `itemsize == 4` test and once for the
# spelling -- and a pattern BINDER is affine exactly like a parameter, so it is
# `S.Dt.bits(d)` twice rather than a binder. MEASURED on 2.0.34: `case D{a, b}:
def glsl_sym_int(+d: S.Dt) -> String:
  String.concat(["glsl_type_builtin_", Bool.pick(String, c.in_uints(d), "u", ""), "int",
    Bool.pick(String, U32.is_eq(S.Dt.bits(d), 32), "", String.concat([U32.show(S.Dt.bits(d)), "_t"]))])

def glsl_keyed.of(+d: S.Dt, is_int: Bool) -> Bool:
  match is_int:
    case True{}: True{}
    case False{}: R.is_named(d, "f64") || R.is_named(d, "f32") || R.is_named(d, "f16") || R.is_named(d, "bool")

def glsl_keyed(+d: S.Dt) -> Bool: glsl_keyed.of(d, c.in_ints(d))

def glsl_sym.of(d: S.Dt, is_int: Bool) -> String:
  match is_int:
    case True{}: glsl_sym_int(d)
    case False{}: glsl_sym4(d)

def glsl_sym.keyed(+d: S.Dt, keyed: Bool) -> String:
  match keyed:
    case True{}: glsl_sym.of(d, c.in_ints(d))
    case False{}: "?"

def glsl_sym(+d: S.Dt) -> String: glsl_sym.keyed(d, glsl_keyed(d))

# `g(s)` is `getattr(mesa, s)` (nir.py:11) and all twelve symbols are `in_dll`
def glsl_const(nm: String) -> String: "AttributeError:glsl_type_builtin_double"

def glsl_row(+d: S.Dt) -> String: String.concat([dtn(d), " -> ", glsl_sym(d), " ", glsl_const(glsl_sym(d))])

def glsl_call_row(+d: S.Dt) -> String: String.concat([dtn(d), "=", glsl_const(glsl_sym(d))])

# `ncast` -- nir.py:27-28.
def ncast_mid.of(src: String, dst: String, both_int: Bool) -> String:
  match both_int:
    case True{}: src
    case False{}: dst

def ncast_mid(+it: S.Dt, +ot: S.Dt) -> String:
  ncast_mid.of(c(it, True{}), c(ot, R.is_named(ot, "bool")), Bool.and(c.in_ints(it), c.in_ints(ot)))

# No `match` on either dtype: the only thing read off them is `bits`, and
# `S.Dt.bits` is a def, so the nested binder pattern bought nothing and cost two
# shadowed `pri`/`cls`/`nm` binders (refused for the shadowing at line 633).
def ncast_name(+it: S.Dt, +ot: S.Dt) -> String:
  String.concat([c(it, True{}), "2", ncast_mid(it, ot), U32.show(S.Dt.bits(ot))])

# One row per SOURCE dtype, joined over all seventeen DESTINATIONS: a wrong cell
# and a shifted cell are both a diff, and 17 rows of 17 is cheaper to read than
# 289 rows of one.
def ncast_rows(+it: S.Dt, +ots: List<&2, S.Dt>, +acc: List<&2, String>) -> String:
  match ots:
    case Nil{}: join(acc)
    case o <> +t: ncast_rows(it, t, List.append(&2, String, acc,
      [String.concat([dtn(o), ":", cast_cell(ncast_name(it, o))])]))

def ncast_row(it: S.Dt, ots: List<&2, S.Dt>) -> String: ncast_rows(it, ots, Nil{})

# `nalu` -- nir.py:38. `g(f"nir_build_alu{len(srcs)}")(b, g(f"nir_op_{op}"), *srcs)`.

def build_alu(n: U32) -> String:
  match n:
    case 1: "nir_build_alu1"
    case 2: "nir_build_alu2"
    case 3: "nir_build_alu3"
    case 4: "nir_build_alu4"
    case _: "ABSENT"

# `scope(space)` -- nir.py:83.

def scope(space: S.Addr) -> String:
  match space:
    case S.AGlobal{}: "global"
    case S.ALocal{}: "shared"
    case S.AReg{}: "deref"
    case S.Aalu{}: "deref"

def is_reg(space: S.Addr) -> Bool:
  match space:
    case S.AReg{}: True{}
    case _: False{}

def is_global(space: S.Addr) -> Bool:
  match space:
    case S.AGlobal{}: True{}
    case _: False{}

# THE INTRINSIC ARITHMETIC -- nir.py:84-91. The oracle reaches these by calling

def nstore_mask(n: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(n)), 1)

def nstore_align.of(is_reg: Bool, bits: U32, n: U32) -> U32:
  match is_reg:
    case True{}: 0
    case False{}: U32.mul(U32.div(bits, 8), n)

def nstore_align(space: S.Addr, bits: U32, n: U32) -> U32: nstore_align.of(is_reg(space), bits, n)

# `0` is not the honest answer for reg: the intrins dict simply has no
# `ALIGN_MUL` key, and 0 is a plausible wrong alignment. So the printed form is
# chosen by the SAME `Bool` the arithmetic is, and `nstore align R` says ABSENT
# where `nstore align A` says 32.
def nstore_align_str.of(is_reg: Bool, bits: U32, n: U32) -> String:
  match is_reg:
    case True{}: "ABSENT"
    case False{}: U32.show(nstore_align.of(False{}, bits, n))

def nstore_align_str(space: S.Addr, bits: U32, n: U32) -> String: nstore_align_str.of(is_reg(space), bits, n)

def nstore_has_align(space: S.Addr) -> Bool: Bool.not(is_reg(space))

def nstore_srcs.of(is_reg: Bool) -> List<&2, String>:
  match is_reg:
    case True{}: ["addr","val"]
    case False{}: ["val","addr"]

def nstore_srcs(space: S.Addr) -> List<&2, String>: nstore_srcs.of(is_reg(space))

def nload_has_access(space: S.Addr) -> Bool: is_global(space)

def nload_align.of(is_reg: Bool, itemsize: U32, numel: U32) -> U32:
  match is_reg:
    case True{}: 0
    case False{}: U32.mul(itemsize, numel)

def nload_align(space: S.Addr, itemsize: U32, numel: U32) -> U32: nload_align.of(is_reg(space), itemsize, numel)

def nload_has_align(space: S.Addr) -> Bool: Bool.not(is_reg(space))

# The bit sizes `nir_instr`'s `bs=` closures answer. `nimm`/`nundef` read
# `dtype.bitsize` (nir.py:73, :77); `nchannel` reads `src.bit_size` (nir.py:61),
# which is a NIR DEF's bit size and so a `U32` the CALLER supplies rather than a
# dtype -- so `def_bit_size` is the identity and is gated as one.
def bit_size(d: S.Dt) -> U32: S.Dt.bits(d)

def def_bit_size(bits: U32) -> U32: bits

# `ngid`/`nlid` are `nc=3, bs=32` (nir.py:93-94) and `nbarrier` is `has_def=False`
# (nir.py:96): a barrier has NO destination def, which is why it can never be the
# `d` of an `if_phi`. `nstore` is `has_def=False` too (nir.py:84) with
# `df=lambda addr: addr`, so a store answers its ADDRESS; `nload` has a def.
def gid_nc() -> U32: 3
def gid_bs() -> U32: 32
def barrier_has_def() -> Bool: False{}
def store_has_def() -> Bool: False{}
def load_has_def() -> Bool: True{}
def load_nc(numel: U32) -> U32: numel
# `nstore`'s `nc` is the CONSTANT `1` (nir.py:84) -- not a thunk over the value
# -- so there is nothing to pass and `store_nc` takes no argument. The first run
# had it as an identity and `store_nc 4` printed 4 where CPython says 1.
def store_nc() -> U32: 1

# `padded_idx(param_idx:int, size:int) -> round_up(param_idx, size) + size`
# -- nir.py:246.
def round_up(+x: U32, +y: U32) -> U32: U32.mul(U32.div(U32.add(x, U32.sub(y, 1)), y), y)

def padded_idx(+p: U32, +s: U32) -> U32: U32.add(round_up(p, s), s)

# THE RENDERER RECORD -- convention 1. `NIRRenderer` and its three subclasses

type Nir is Data:
  Nir{name: String, has_local: Bool, has_shared: Bool, g0: U32, g1: U32, g2: U32, l0: U32, l1: U32, l2: U32,
      shared_max: U32, drops_exp2: Bool, has_param: Bool, sd_kind: U32}

def Nir.base() -> Nir:
  Nir{"NIR", True{}, True{}, 2147483647, 65535, 65535, 1024, 1024, 64, 49152, False{}, False{}, 0}

def Nir.nak() -> Nir:
  Nir{"NAK", True{}, True{}, 2147483647, 65535, 65535, 1024, 1024, 64, 49152, False{}, True{}, 1}

def Nir.lvp() -> Nir:
  Nir{"LVP", False{}, False{}, 1, 0, 0, 1024, 1024, 64, 49152, True{}, True{}, 0}

def Nir.ir3() -> Nir:
  Nir{"IR3", True{}, True{}, 2147483647, 65535, 65535, 1024, 1024, 64, 49152, False{}, True{}, 2}

def Nir.name(n: Nir) -> String:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: name

def Nir.has_local(n: Nir) -> Bool:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: has_local

def Nir.has_shared(n: Nir) -> Bool:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: has_shared

def Nir.g(n: Nir) -> List<&2, U32>:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}:
      [g0, g1, g2]

def Nir.l(n: Nir) -> List<&2, U32>:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}:
      [l0, l1, l2]

# `shared_max` IS A SCALAR, not a triple: `CUDARenderer.shared_max` is the
# int `49152` and nir.py:118 TAKES it, so `Nir` carries one `U32` where
def Nir.s(n: Nir) -> U32:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: shared_max

def Nir.drops_exp2(n: Nir) -> Bool:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: drops_exp2

def Nir.has_param(n: Nir) -> Bool:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: has_param

def Nir.sd_kind(n: Nir) -> U32:
  match n:
    case Nir{name, has_local, has_shared, g0, g1, g2, l0, l1, l2, shared_max, drops_exp2, has_param, sd_kind}: sd_kind

def Nir.row(+n: Nir) -> String:
  String.concat([Nir.name(n), " has_local=", b2s(Nir.has_local(n)), " has_shared=", b2s(Nir.has_shared(n)),
    " global_max=[", unum(Nir.g(n)), "] local_max=[", unum(Nir.l(n)), "] shared_max=", U32.show(Nir.s(n)),
    " drops_exp2=", b2s(Nir.drops_exp2(n)), " has_param=", b2s(Nir.has_param(n)),
    " sd_kind=", U32.show(Nir.sd_kind(n))])

# `supported_dtypes` -- nir.py:244, :253, :321. THREE OVERRIDES, and the
def sd.drop_base(+d: S.Dt) -> Bool:
  Bool.or(R.is_named(d, "fp8e4m3") || R.is_named(d, "fp8e5m2") ||
  R.is_named(d, "fp8e4m3fnuz") || R.is_named(d, "fp8e5m2fnuz"), R.is_named(d, "bf16"))

def sd.drop_nak.of(under: Bool, d: S.Dt) -> Bool:
  match under:
    case True{}: R.is_named(d, "f16")
    case False{}: False{}

def sd.drop_ir3(d: S.Dt) -> Bool: R.is_named(d, "f64")

# ONE MATCH PER PARAMETER, and that is a measured Bend rule rather than taste: a
def sd.by_kind(kind: U32, under53: Bool, d: S.Dt) -> Bool:
  match kind:
    case 1: sd.drop_nak.of(under53, d)
    case 2: sd.drop_ir3(d)
    case _: False{}

def sd.is_drop.of(kind: U32, base: Bool, under53: Bool, d: S.Dt) -> Bool:
  match base:
    case True{}: True{}
    case False{}: sd.by_kind(kind, under53, d)

def sd.is_drop(+n: Nir, arch: U32, +d: S.Dt) -> Bool:
  sd.is_drop.of(Nir.sd_kind(n), sd.drop_base(d), U32.is_lt(arch, 53), d)

# The filter is applied by the FOLD rather than handed to it as a closure:
# returning `Dt -> Bool` needs `match _: case d:`, which Bend refuses at line
# 903 ("a def or a consumed binder"). Passing the three flags as arguments is
# both shorter and one fewer way for the two dtype tests to disagree.
def sd.go(+n: Nir, +arch: U32, ds: List<&2, S.Dt>, +acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ds:
    case Nil{}: acc
    case +d <> +t: sd.go(n, arch, t, Bool.pick(List<&2, S.Dt>, sd.is_drop(n, arch, d), acc, List.append(&2, S.Dt, acc, [d])))

def supported_dtypes(n: Nir, arch: U32) -> List<&2, S.Dt>: sd.go(n, arch, all_of(), Nil{})

# `int(self.target.arch[3:])`. `arch` is the digits AFTER the `sm_` prefix, so
# the slice is already done by the caller; `arch_off` spells the slice for the
# row that proves the offset is three and not one.
def arch_off(nm: String) -> String:
  match nm:
    case "sm_52": "52"
    case "sm_53": "53"
    case "sm_120": "120"
    case "sm_86": "86"
    case "86": "86"
    case _: ""

# `int(arch[3:])` with NO string-to-Nat conversion available -- Base has no
def arch_int(nm: String) -> U32:
  match nm:
    case "sm_52": 52
    case "sm_53": 53
    case "sm_86": 86
    case "sm_120": 120
    case _: 0

# `code_for_op` -- nir.py:119 and :262.

def cfo.is(nm: String) -> Bool:
  match nm:
    case "ADD": True{}
    case "AND": True{}
    case "TRUNCDIV": True{}
    case "TRUNCMOD": True{}
    case "CMPEQ": True{}
    case "CMPLT": True{}
    case "CMPNE": True{}
    case "EXP2": True{}
    case "FDIV": True{}
    case "LOG2": True{}
    case "MAX": True{}
    case "MUL": True{}
    case "OR": True{}
    case "RECIP": True{}
    case "SHL": True{}
    case "SHR": True{}
    case "SIN": True{}
    case "SQRT": True{}
    case "TRUNC": True{}
    case "WHERE": True{}
    case "XOR": True{}
    case _: False{}

# `k != Ops.EXP2` is the ONLY filter `LVPRenderer` applies (nir.py:262), and
def cfo.has(+n: Nir, +nm: String) -> Bool:
  Bool.and(cfo.is(nm), Bool.or(Bool.not(Nir.drops_exp2(n)), Bool.not(String.eq(nm, "EXP2"))))

def cfo_names() -> List<&2, String>: ["ADD","AND","TRUNCDIV","TRUNCMOD","CMPEQ","CMPLT","CMPNE","EXP2","FDIV","LOG2","MAX","MUL","OR","RECIP","SHL","SHR","SIN","SQRT","TRUNC","WHERE","XOR"]

def cfo.go(+n: Nir, +ns: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    # `Bool.pick(t, cond, X, Y)` is X WHEN cond IS TRUE, so the KEPT arm goes in
    case +h <> +t: cfo.go(n, t, Bool.pick(List<&2, String>, cfo.has(n, h), List.append(&2, String, acc, [h]), acc))

def code_for_op(n: Nir) -> List<&2, String>: cfo.go(n, cfo_names(), Nil{})

# THE CONSTANT ROWS. `intr_const` and `idx_const` and the seven `op_const` arms
# no TABLE row reaches (`mov`, `vec2`..`vec16`) were, for the first mutation
# sweep, DEFS NO GATE ROW CALLS -- thirty-eight of the hundred-and-one `+1`
# mutations moved nothing for exactly that reason, which is
# `agent-core.md`'s "a def nothing calls is invisible to every other check".
#
# `mov` is `nchannel`'s op (nir.py:65, taken straight off `mesa` and never

def intr_names() -> List<&2, String>: ["nir_intrinsic_store_global","nir_intrinsic_store_shared","nir_intrinsic_store_deref","nir_intrinsic_load_global","nir_intrinsic_load_shared","nir_intrinsic_load_deref","nir_intrinsic_load_workgroup_id","nir_intrinsic_load_local_invocation_id","nir_intrinsic_barrier","nir_intrinsic_ldc_nv","nir_intrinsic_load_ubo","nir_intrinsic_image_store","nir_intrinsic_image_load","nir_type_float16","nir_type_float32","nir_deref_type_var","nir_deref_type_array","nir_jump_break","MESA_SHADER_COMPUTE","SCOPE_WORKGROUP","ACCESS_CAN_REORDER","GLSL_SAMPLER_DIM_2D"]

def idx_names() -> List<&2, String>: ["NIR_INTRINSIC_ALIGN_MUL","NIR_INTRINSIC_WRITE_MASK","NIR_INTRINSIC_ACCESS","NIR_INTRINSIC_EXECUTION_SCOPE","NIR_INTRINSIC_IMAGE_DIM","NIR_INTRINSIC_SRC_TYPE","NIR_INTRINSIC_DEST_TYPE","NIR_INTRINSIC_RANGE"]

# The op names `nalu` is asked for OUTSIDE the three tables: `mov` from
# `nchannel`, `vecN` from `tovec` and the `STACK` arm, and the `iadd`/`imul`/
# `ilt` of `nif`, `END` and `BACKEDGE` (tinygrad/renderer/nir.py:216, :222, :224).
def alu_names() -> List<&2, String>: ["mov","vec2","vec3","vec4","vec5","vec8","vec16","iadd","imul","ilt"]

# the selector is a `U32` tag, not a function argument: a `String -> U32`
# parameter would have to be a `~` TEMPLATE, and `const_of.rows`'s own `f` may
# not mention a local of its caller -- so the first spelling of this fold was
# refused. A tag keeps the file free of a foreign effect and is one `match`.

def const_pick.tag(nm: String, tag: U32) -> U32:
  match tag:
    case 0: op_const(nm)
    case 1: intr_const(nm)
    case 2: idx_const(nm)
    case _: 0

# `op_const` is keyed by the BARE name because `nalu` prepends the prefix
# (nir.py:38), so the row prepends it back on the way out. That asymmetry is the
# reason this fold takes a PREFIX as well as a tag: without it the row printed
# ten zeros and the `mesa alu` row said so.
def const_rows3(+names: List<&2, String>, +tag: U32, +pre: String, +acc: List<&2, String>) -> String:
  match names:
    case Nil{}: join(acc)
    case +h <> +t: const_rows3(t, tag, pre,
      List.append(&2, String, acc, [String.concat([pre, h, "=", U32.show(const_pick.tag(h, tag))])]))

def const_pick(names: List<&2, String>, tag: U32, pre: String) -> String: const_rows3(names, tag, pre, Nil{})

# THE TABLE IS IN `.agents/slop/tables/renderer-nir-1199.md` -- the gate, and what every group is for.

def u_aop_tbl(k: U32) -> String: aop_rows(k, u_ops(), Nil{})
def f_aop_tbl(k: U32) -> String: aop_rows(k, f_ops(), Nil{})

def rev.rows(+k: U32, +ops: List<&2, String>, +acc: List<&2, String>) -> String:
  match ops:
    case Nil{}: join(acc)
    case h <> +t: rev.rows(k, t, List.append(&2, String, acc,
      [String.concat([h, ":", aop_rev_of(k, aop_of(k, op_of(h))), "->", aop_of(k, op_of(aop_rev_of(k, aop_of(k, op_of(h))))), "/", U32.show(op_const(aop_of(k, op_of(h))))])]))

def rev.go(+k: U32, +ops: List<&2, String>) -> String: rev.rows(k, ops, Nil{})

def c_row(+d: S.Dt, +unsigned: Bool) -> String: String.concat(["c ", dtn(d), " u=", b2s(unsigned), " -> ", c(d, unsigned)])

# KEY MEMBERSHIP ONLY -- the symbol, or `?` for a dtype `glsl_type`'s dict does
# not hold. The first run folded `glsl_const` in here and so printed the CALL's
# refusal for all twelve and the SYMBOL for none of them; `glsl call` below is
# the row that carries the refusal. TWO ROWS, TWO CLAIMS.
def glsl_key_go.rows(+ds: List<&2, S.Dt>, +acc: List<&2, String>) -> String:
  match ds:
    case Nil{}: join(acc)
    case +d <> +t: glsl_key_go.rows(t, List.append(&2, String, acc,
      [String.concat([dtn(d), "=", glsl_sym(d)])]))

def glsl_key_go(+ds: List<&2, S.Dt>, +acc: List<&2, String>) -> String: glsl_key_go.rows(ds, acc)

def glsl_call.go(+ds: List<&2, S.Dt>, +acc: List<&2, String>) -> String:
  match ds:
    case Nil{}: join(acc)
    case d <> +t: glsl_call.go(t, List.append(&2, String, acc, [glsl_call_row(d)]))

def glsl_call(go: List<&2, S.Dt>) -> String: glsl_call.go(go, Nil{})

def mask_tbl.go(+d: S.Dt, +ns: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ns:
    case Nil{}: join(acc)
    case h <> +t: mask_tbl.go(d, t, List.append(&2, String, acc,
      [String.concat(["x", U32.show(h), "=wm", U32.show(nstore_mask(h)), ",al", U32.show(nstore_align(S.AGlobal{}, S.Dt.bits(d), h)),
        ",gsrc", join(nstore_srcs(S.AGlobal{})), ",lsrc", join(nstore_srcs(S.AReg{})),
        ",lal", U32.show(nload_align(S.AGlobal{}, S.Dt.itemsize(d), h)),
        ",nc", U32.show(load_nc(h)), ",bs", U32.show(bit_size(d))])]))

def mask_tbl(d: S.Dt, ns: List<&2, U32>) -> String: mask_tbl.go(d, ns, Nil{})

def pad_row(+p: U32, +s: U32) -> String: String.concat(["padded_idx ", U32.show(p), " ", U32.show(s), " = ru", U32.show(round_up(p, s)), "+sz=", U32.show(padded_idx(p, s))])

def pad_col.rows(+p: U32, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: join(acc)
    case +s <> +t: pad_col.rows(p, t, List.append(&2, String, acc,
      [String.concat([U32.show(s), ":ru", U32.show(round_up(p, s)), ",pi", U32.show(padded_idx(p, s))])]))

def pad_col(p: U32, ss: List<&2, U32>, acc: List<&2, String>) -> String: pad_col.rows(p, ss, acc)

def pad_tbl.go(+ps: List<&2, U32>, +ss: List<&2, U32>, acc: String) -> String:
  match ps:
    case Nil{}: acc
    # `;` ENDS A COLUMN and `,` ends a CELL, so the 11 x 5 grid is readable.
    #
    # the accumulator is a string, not a list. `join` puts a `,` between
    # elements, so a list of columns read `...,pi32,|1:ru1,...` with `|` as a
    # prefix and `...,pi32;,1:ru1` with `;` as a suffix -- in both cases a
    # separator this fold does not own sat between two columns. MEASURED in a
    case +p <> +t: pad_tbl.go(t, ss, String.concat([acc, pad_col(p, ss, Nil{}), ";"]))

def pad_tbl(ps: List<&2, U32>, ss: List<&2, U32>) -> String: pad_tbl.go(ps, ss, "")

# THE GATE ROWS.

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
    # ---- `c(t, u)` : 17 dtypes x 2, plus the THREE `dtypes.all` does not hold
    rd("c bool u=True ", c(S.boolean(), True{})),
    rd("c bool u=False", c(S.boolean(), False{})),
    rd("c uint8 u=True ", c(S.uint8(), True{})),
    rd("c uint8 u=Fals", c(S.uint8(), False{})),
    rd("c uint32 u=True", c(S.uint32(), True{})),
    rd("c int32 u=True ", c(S.int32(), True{})),
    rd("c half u=True  ", c(S.half(), True{})),
    rd("c bf16 u=True  ", c(S.bfloat16(), True{})),
    rd("c fp8_e4m3 u=T ", c(S.fp8e4m3(), True{})),
    rd("c double u=True", c(S.double(), True{})),
    rd("c uint64 u=Fal", c(S.uint64(), False{})),
    # THE THREE THAT SEPARATE `in_ints` FROM `S.Dt.is_int`. `weakint` is in
    # `dtypes.is_int` and NOT in `dtypes.ints`, so a port that used the shared
    # reader answers "i" here where Python answers "b".
    rd("c weakint u=T ", c(S.weakint(), True{})),
    rd("c weakfloat u=", c(S.weakfloat(), True{})),
    rd("c void u=True ", c(S.void(), True{})),
    rd("c index u=True", c(S.index(), True{})),
    # THE SPELLING ROW, and the only row that is about SPELLING. `spec.bend`'s
    rd("dt name map     ", dnames(all_of())),
    # ---- the three op tables, FORWARD and REVERSE
    rd("aop u  keys    ", dnames(aop_keys())),
    rd("aop u  table   ", u_aop_tbl(0)),
    rd("aop s  table   ", u_aop_tbl(1)),
    rd("aop f  table   ", f_aop_tbl(2)),
    rd("aop rev u      ", rev.go(0, u_ops())),
    rd("aop rev s      ", rev.go(1, u_ops())),
    rd("aop rev f      ", rev.go(2, f_ops())),
    # `aop_kind` per dtype -- the CLASS tag, all seventeen plus the weak three.
    rd("aop kind uint8 ", U32.show(aop_kind(S.uint8()))),
    rd("aop kind bool  ", U32.show(aop_kind(S.boolean()))),
    rd("aop kind int32 ", U32.show(aop_kind(S.int32()))),
    rd("aop kind half  ", U32.show(aop_kind(S.half()))),
    rd("aop kind weaki ", U32.show(aop_kind(S.weakint()))),
    rd("aop kind void  ", U32.show(aop_kind(S.void()))),
    # ---- `glsl_type`: the SYMBOL is computed, the CONSTANT is a refusal
    rd("glsl keys      ", glsl_key_go(all_of(), Nil{})),
    rd("glsl call      ", glsl_call(all_of())),
    # ---- `ncast`: 17 sources x 17 destinations, joined per source
    rd("ncast from int32", ncast_row(S.int32(), all_of())),
    rd("ncast from uint8", ncast_row(S.uint8(), all_of())),
    rd("ncast from bool ", ncast_row(S.boolean(), all_of())),
    rd("ncast from float", ncast_row(S.single(), all_of())),
    rd("ncast from long ", ncast_row(S.int64(), all_of())),
    rd("ncast from weaki", ncast_row(S.weakint(), all_of())),
    # ---- `scope` -- ALU IS THE ROW: it is not REG and it is not GLOBAL
    rd("scope global   ", scope(S.AGlobal{})),
    rd("scope local    ", scope(S.ALocal{})),
    rd("scope reg      ", scope(S.AReg{})),
    rd("scope alu      ", scope(S.Aalu{})),
    rd("is_reg global  ", b2s(is_reg(S.AGlobal{}))),
    rd("is_reg alu     ", b2s(is_reg(S.Aalu{}))),
    rd("is_global local", b2s(is_global(S.ALocal{}))),
    rd("is_global alu  ", b2s(is_global(S.Aalu{}))),
    # ---- the intrinsic arithmetic: WRITE_MASK / ALIGN_MUL / src ORDER
    rd("nstore mask    ", mask_tbl(S.uint32(), [1, 2, 3, 4, 8, 16])),
    rd("nstore align L ", nstore_align_str(S.ALocal{}, 64, 4)),
    rd("nstore align R ", nstore_align_str(S.AReg{}, 64, 4)),
    rd("nstore align A ", nstore_align_str(S.Aalu{}, 64, 4)),
    rd("nstore hasAL R ", b2s(nstore_has_align(S.AReg{}))),
    rd("nstore hasAL A ", b2s(nstore_has_align(S.Aalu{}))),
    rd("nstore srcs G  ", join(nstore_srcs(S.AGlobal{}))),
    rd("nstore srcs A  ", join(nstore_srcs(S.Aalu{}))),
    rd("nstore srcs R  ", join(nstore_srcs(S.AReg{}))),
    rd("nload hasACC G ", b2s(nload_has_access(S.AGlobal{}))),
    rd("nload hasACC L ", b2s(nload_has_access(S.ALocal{}))),
    rd("nload hasACC R ", b2s(nload_has_access(S.AReg{}))),
    rd("nload hasACC A ", b2s(nload_has_access(S.Aalu{}))),
    rd("nload hasAL R  ", b2s(nload_has_align(S.AReg{}))),
    rd("nload hasAL A  ", b2s(nload_has_align(S.Aalu{}))),
    rd("nload align R  ", U32.show(nload_align(S.AReg{}, 4, 16))),
    rd("nload align L  ", U32.show(nload_align(S.ALocal{}, 1, 16))),
    rd("bit_size long  ", U32.show(bit_size(S.int64()))),
    rd("bit_size half  ", U32.show(bit_size(S.half()))),
    rd("def_bit_size 64", U32.show(def_bit_size(64))),
    rd("gid nc/bs      ", String.concat([U32.show(gid_nc()), "/", U32.show(gid_bs())])),
    rd("barrier has_def", b2s(barrier_has_def())),
    rd("store has_def  ", b2s(store_has_def())),
    rd("load has_def   ", b2s(load_has_def())),
    rd("load_nc 16     ", U32.show(load_nc(16))),
    rd("store_nc 4     ", U32.show(store_nc())),
    # ---- `nalu`'s two symbols: the op name and the BUILD arity
    # THE THREE CONSTANT ROWS. These exist because thirty-eight `+1` mutations
    # moved nothing on the first sweep: `intr_const`, `idx_const` and the seven
    # `op_const` arms outside the three tables were defs no row called.
    rd("mesa alu  ", const_pick(alu_names(), 0, "nir_op_")),
    rd("mesa intr ", const_pick(intr_names(), 1, "")),
    rd("mesa idx  ", const_pick(idx_names(), 2, "")),
    rd("arch_int sm_86 ", U32.show(arch_int("sm_86"))),
    rd("alu arities    ", String.concat([build_alu(1), ",", build_alu(2), ",", build_alu(3), ",", build_alu(4), ",", build_alu(5)])),
    # ---- `padded_idx` -- `round_up` + a WHOLE extra size
    rd("padded 0 4     ", pad_row(0, 4)),
    rd("padded 3 8     ", pad_row(3, 8)),
    rd("padded 8 8     ", pad_row(8, 8)),
    rd("padded 9 16    ", pad_row(9, 16)),
    rd("padded 17 32   ", pad_row(17, 32)),
    rd("padded tbl     ", pad_tbl([0, 1, 3, 4, 7, 8, 9, 15, 16, 17, 32], [1, 4, 8, 16, 32])),
    # ---- `int(self.target.arch[3:])` -- the offset is THREE
    rd("arch_off sm_53 ", arch_off("sm_53")),
    rd("arch_off sm_120", arch_off("sm_120")),
    rd("arch_off 86    ", arch_off("86")),
    rd("arch_int sm_52 ", U32.show(arch_int("sm_52"))),
    rd("arch_int sm_53 ", U32.show(arch_int("sm_53"))),
    rd("arch_int sm_120", U32.show(arch_int("sm_120"))),
    # ---- the RENDERER RECORD, and its three supported_dtypes overrides
    rd("rec NIR        ", Nir.row(Nir.base())),
    rd("rec NAK        ", Nir.row(Nir.nak())),
    rd("rec LVP        ", Nir.row(Nir.lvp())),
    rd("rec IR3        ", Nir.row(Nir.ir3())),
    rd("sd nir         ", dnames(supported_dtypes(Nir.base(), 86))),
    rd("sd nak sm_86   ", dnames(supported_dtypes(Nir.nak(), 86))),
    rd("sd nak sm_53   ", dnames(supported_dtypes(Nir.nak(), 53))),
    rd("sd nak sm_52   ", dnames(supported_dtypes(Nir.nak(), 52))),
    rd("sd nak sm_120  ", dnames(supported_dtypes(Nir.nak(), 120))),
    rd("sd ir3         ", dnames(supported_dtypes(Nir.ir3(), 86))),
    # ---- `code_for_op` -- 21 ops, and LVP's 20 without EXP2
    rd("cfo nir        ", join(code_for_op(Nir.base()))),
    rd("cfo lvp        ", join(code_for_op(Nir.lvp()))),
    rd("cfo nak        ", join(code_for_op(Nir.nak()))),
    rd("cfo ir3        ", join(code_for_op(Nir.ir3()))),
    ]))

# THE TABLE IS IN `.agents/slop/tables/renderer-nir-1427.md` -- THE MUTATION TABLE -- 37 mutations, MEASURED, one per ported rule, reported
