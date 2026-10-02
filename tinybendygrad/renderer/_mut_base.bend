# tinybendygrad/renderer/nir.bend -- tinygrad/renderer/nir.py

# ===========================================================================
# THE FILE, AND THE TWO MEASURED FACTS THAT DECIDED ITS SHAPE.
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
# `tinygrad/runtime/support/c.py:89`, which raises when the library is absent and
# the `try` swallows it, so the names never get bound. `tinymesa` is not
# installed: `.venv/lib/python3.12/site-packages/tinymesa` does not exist.
#
#     .venv/bin/python -c "from tinygrad.runtime.autogen import mesa; print(len(dir(mesa)))"
#       glsl_type_builtin*: 0        # of 9,974 module attributes
#
# So `nir.glsl_type` (:14-16) is not missing a constant, it is UNUSABLE: its dict
# comprehension is EAGER, so it evaluates `g("glsl_type_builtin_double")` before
# it ever indexes `[t]`, and that getattr raises -- so `glsl_type` raises
# `AttributeError` for EVERY `t`, including the eleven whose own symbol is never
# consulted. The gate rows say exactly that, and they name the symbol CPython
# asked for, because 0 would be `nir_deref_type_var`'s value and would read as a
# plausible wrong constant.
#
# FACT TWO, and it is narrower. `nir_intrinsic_infos` (mesa.py:989) is the same
# `in_dll` shape and is likewise absent, so `nir_instr`'s intrinsic arm
# (:49-52) raises before it reaches its own `assert idx > 0, "invalid intrinsic.
# mesa version mismatch?"`. But the `NIR_INTRINSIC_*` ENUM values it would index
# with are generated INTS and ARE present, so this file audits all eight of them
# and records the `index_map` SLOTS as the wall. `TODO(p3) nir.py:50`.
#
# THE CONVENTIONS are `renderer/__init__.bend`'s HEADER, read in full. Four that
# bite here:
#
#   1. A RENDERER IS A `Data` RECORD OF ITS OPTIONS. `NIRRenderer` and its three
#      subclasses differ by `supported_dtypes`, `code_for_op`, the `param`
#      builder and three maxima, so each is one `Nir` record below and the gate
#      READS THE RECORD -- a wrong constant is a moved row, not a wrong shader
#      nobody diffs.
#   2. THE GATE IS A STRING DIFF, NEVER A BOOLEAN ABOUT STRINGS. Every row is
#      `<name> = [BEND]   py=[CPYTHON]`, the `py=` half is a LITERAL so it cannot
#      be the same expression as the BEND half, and `String.concat` -- which
#      drops a literal silently -- is why every table is emitted as ONE joined
#      string rather than a count.
#   4. A `match` MAY ONLY SCRUTINISE A PARAMETER OR A PATTERN BINDER. Every test
#      of a computed value is therefore a trailing `Bool`/`U32` parameter of a
#      `.of`/`.go` helper and the `match` is inside THAT. Measured: the first
#      draft of this file refused on `match Bool.and(c.is_uint(d), unsigned):`
#      at line 173, which is why there are eleven `.of` helpers below.
#   6. A RECORD LITERAL AND A RECORD PATTERN BOTH NAME EVERY FIELD.
#
# BOTH DIRECTIONS ARE WRITTEN INDEPENDENTLY, and that is deliberate. Folding the
# reverse table out of the forward one would make the two rows agree by
# construction: `agent-core.md`'s `nv_query_litter` case, where the port and the
# oracle made the SAME mistake and the differ reported zero disagreements over
# it. So `u_aop` and `u_aop.rev` are two matches, each typed from `nir.py:19-20`,
# and the ORACLE inverts Python's dict. An arm moved in one does not move in the
# other, which is what makes the reverse rows worth their cost.
# ===========================================================================

import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../LAWS/spec.bend as S

# ===========================================================================
# THE GATE PRIMITIVES. Same shape as `nir_llvmir.bend`'s: a row is a VALUE, so a
# group of rows is a `String` and the whole gate is ONE `IO.print` whose own
# newline is the only frame.
# ===========================================================================

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

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

# ===========================================================================
# THE THREE SET-MEMBERSHIP TESTS, and they are NOT `S.Dt`'s.
#
#     c(t,u): "u" if t in dtypes.uints and u else ("i" if t in dtypes.ints else
#             ("f" if t in dtypes.floats else "b"))
#     ncast:  it in dtypes.ints and ot in dtypes.ints
#
# `dtypes.ints` is `uints + sints` -- EIGHT concrete dtypes -- while
# `dtypes.is_int(x)` (and so `S.Dt.is_int`) is `x in ints + (weakint,)`. They
# DIFFER on `weakint`, and so do `floats` and `dtypes.is_float` on `weakfloat`.
# A port that reaches for the shared reader answers `"i"` for `weakint` where
# Python answers `"b"`, and nothing downstream would notice. So these three
# match the CLASS and exclude the weak members, and the `weakint` / `void` /
# `weakfloat` rows at the foot of the gate are what hold them to it.
# ===========================================================================

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

# ===========================================================================
# `c(t, u)` -- nir.py:26. FOUR arms, and the fourth is the reach for `bool`,
# which is in NEITHER set: `dtypes.floats` excludes it and `dtypes.ints` excludes
# it, so a `bool` falls all the way through to `"b"`. The `and u` binds to the
# FIRST arm only, so `u=False` turns a uint into `"i"` and leaves every other
# class alone. Both are boundary cases with their own row.
# ===========================================================================

# THE THREE ARMS, INNERMOST FIRST: a def may only call defs ABOVE it, so the
# chain `arm1 -> arm2 -> arm3` is spelled bottom-up. Measured refusal otherwise.
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

# ===========================================================================
# THE THREE ALU OP TABLES -- nir.py:19-23.
#
#   u_aop  unsigned/bool arithmetic        14 entries  (nir.py:19-20)
#   s_aop  u_aop with FIVE arms replaced   14 entries  (nir.py:21)
#   f_aop  float arithmetic                12 entries  (nir.py:22-23)
#   aop    dtype -> one of the three       17 keys     (nir.py:24)
#
# `s_aop`'s FIVE overrides are the whole difference between the two integer
# tables and they are NOT the ones a reader would guess. CMPLT, CDIV, CMOD, MAX
# and SHR change; ADD, MUL, CMPNE, CMPEQ, OR, AND, XOR, WHERE and SHL are
# spelled the SAME for signed and unsigned -- NINE shared spellings, FIVE
# diverging ones. So each table is its own match rather than `u_aop` plus a
# patch list: a port that derived `s_aop` from `u_aop` could not tell which of
# the fourteen entries is a shared spelling and which is an override, and the
# `aop signed char` row is the one that shows a wrong answer in either.
#
# The three tables have SIX NAMES in common as OPS (`ADD`, `MUL`, `CMPLT`,
# `CMPNE`, `CMPEQ`, `MAX` are `iadd`/`imul`/.. in one table and `fadd`/`fmul`/..
# in another), which is why the REVERSE direction is a per-table match and not
# one shared inverse: `f_aop.rev("fadd") = "ADD"` and `u_aop.rev("iadd") =
# "ADD"` are BOTH true and one shared inverse would have to pick.
# ===========================================================================
# THE MESA ENUM VALUES. Read by `getattr` on the live module, never transcribed,
# and each one is gated so an entry moved into the wrong arm is a diff. The
# authority for every one of these is the generated enum in
# `tinygrad/runtime/autogen/mesa.py`; `nir.py` never states a value, only a
# SYMBOL, so this file is the place the numbers enter and the gate is the only
# thing that can say they are right.
# ===========================================================================

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

# NINE OF THE THIRTY-SIX CAST NAMES DO NOT EXIST: every `*2f8` (the fp8s are not
# in `glsl_type`'s key set and neither are they in NIR's op enum) and every
# `*2b1` (`nir_op_i2b1` and friends are not ops). So `ncast` to an fp8 or to
# `bool` RAISES in CPython, and `op_const`'s `case _` of 0 would be a plausible
# wrong constant for all nine. `op_present` is the separate question and the
# `ncast` rows print the refusal where it says no.
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

# ===========================================================================

def u_aop(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "iadd"
    case O.OpsMUL{}: "imul"
    case O.OpsCDIV{}: "udiv"
    case O.OpsCMOD{}: "umod"
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
    case O.OpsCDIV{}: "idiv"
    case O.OpsCMOD{}: "irem"
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
    case O.OpsRECIPROCAL{}: "frcp"
    case O.OpsMAX{}: "fmax"
    case O.OpsTRUNC{}: "ftrunc"
    case O.OpsSIN{}: "fsin"
    case O.OpsEXP2{}: "fexp2"
    case O.OpsLOG2{}: "flog2"
    case _: ""

# THE REVERSE DIRECTION -- nir.py:19-23 READ BACKWARDS, AND NOT FOLDED OUT OF
# THE FORWARD ONE. See the header: folding would make the two rows agree by
# construction and an error made twice reads as zero disagreements.
def u_aop.rev(nm: String) -> String:
  match nm:
    case "iadd": "ADD"
    case "imul": "MUL"
    case "udiv": "CDIV"
    case "umod": "CMOD"
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
    case "idiv": "CDIV"
    case "irem": "CMOD"
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
    case "frcp": "RECIPROCAL"
    case "fmax": "MAX"
    case "ftrunc": "TRUNC"
    case "fsin": "SIN"
    case "fexp2": "EXP2"
    case "flog2": "LOG2"
    case _: ""

# `aop` -- nir.py:24. `{**{x:u_aop for x in (dtypes.bool,)+dtypes.uints},
# **{x:s_aop for x in dtypes.sints}, **{x:f_aop for x in dtypes.floats}}`.
#
# The INSERTION ORDER is bool, uints, sints, floats -- NOT `dtypes.all`'s
# floats-first order, and that is a real diff rather than a cosmetic one: it is
# why `aop keys` is a joined STRING and not a count. THREE classes, so the table
# is a `U32` TAG -- `0` unsigned/bool, `1` signed, `2` float -- which keeps
# `aop_of` total on all seventeen and makes an unreachable class a `3` no row
# can hide.
# `(dtypes.bool,) + dtypes.uints` (nir.py:24), so `bool` is in the SAME class as
# the uints and not a fourth class of its own. The first run answered `1` for
# `bool` -- `bool`'s CLASS is `CBool`, which is neither `CUint` nor `CSint`, so
# the unsigned test alone fell through to the signed arm. CAUGHT BY THE
# `aop kind bool` ROW.
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
def u_ops() -> List<&2, String>: ["ADD","MUL","CDIV","CMOD","CMPLT","CMPNE","CMPEQ","OR","AND","XOR","WHERE","MAX","SHL","SHR"]

def f_ops() -> List<&2, String>: ["ADD","MUL","CMPLT","CMPNE","CMPEQ","FDIV","RECIPROCAL","MAX","TRUNC","SIN","EXP2","LOG2"]

def op_of(nm: String) -> O.Op:
  match nm:
    case "ADD": O.OpsADD{}
    case "MUL": O.OpsMUL{}
    case "CDIV": O.OpsCDIV{}
    case "CMOD": O.OpsCMOD{}
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
    case "RECIPROCAL": O.OpsRECIPROCAL{}
    case "TRUNC": O.OpsTRUNC{}
    case "SIN": O.OpsSIN{}
    case "EXP2": O.OpsEXP2{}
    case "LOG2": O.OpsLOG2{}
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

# ===========================================================================
# `glsl_type` -- nir.py:14-16. THE SYMBOL NAME is computed, not looked up:
# `'u'*(d in dtypes.uints)`, then the LITERAL `int`, then `bitsize + '_t'`
# EXCEPT when `itemsize == 4`. That exception is the whole width rule -- `uint32`
# and `int32` are spelled with no `_t` while all three other widths carry one,
# and it is `itemsize` rather than `bitsize` that decides, so the two agree on
# every dtype here only by luck.
#
# TWELVE keys -- four explicit plus the EIGHT of `dtypes.ints` -- so the fp8s and
# `__bf16` are ABSENT and `glsl_type(fp8_e4m3)` is a `KeyError`, not a wrong
# answer. `glsl_keyed` is that membership and the five non-int dtypes it admits
# are exactly the four explicit keys plus `bool`.
# ===========================================================================

def glsl_sym4.of3(d: S.Dt, is_half: Bool) -> String:
  match is_half:
    case True{}: "glsl_type_builtin_float16_t"
    case False{}: Bool.pick(String, R.is_named(d, "bool"), "glsl_type_builtin_uint8_t", "?")

def glsl_sym4.of2(+d: S.Dt, is_float: Bool) -> String:
  match is_float:
    case True{}: "glsl_type_builtin_float"
    case False{}: glsl_sym4.of3(d, R.is_named(d, "half"))

def glsl_sym4.of(+d: S.Dt, is_double: Bool) -> String:
  match is_double:
    case True{}: "glsl_type_builtin_double"
    case False{}: glsl_sym4.of2(d, R.is_named(d, "float"))

def glsl_sym4(+d: S.Dt) -> String: glsl_sym4.of(d, R.is_named(d, "double"))

# `bits` is read TWICE -- once for the `itemsize == 4` test and once for the
# spelling -- and a pattern BINDER is affine exactly like a parameter, so it is
# `S.Dt.bits(d)` twice rather than a binder. MEASURED on 2.0.34: `case D{a, b}:
# String.concat([b, b])` is refused with "b (consumed more than once)". Calls are
# repeatable; bindings are not. That is also why `dtn` and `c.in_uints` read each
# binder once.
# The `glsl_type_builtin_` PREFIX IS PART OF THE KEY. The first run printed
# `unsigned char=uint8_t` -- the f-string's tail with its head left off -- and
# the `glsl keys` row caught it. `nir.py:16` interpolates the prefix into the
# SAME f-string, so there was nowhere to have forgotten it.
def glsl_sym_int(+d: S.Dt) -> String:
  String.concat(["glsl_type_builtin_", Bool.pick(String, c.in_uints(d), "u", ""), "int",
    Bool.pick(String, U32.is_eq(S.Dt.bits(d), 32), "", String.concat([U32.show(S.Dt.bits(d)), "_t"]))])

def glsl_keyed.of(+d: S.Dt, is_int: Bool) -> Bool:
  match is_int:
    case True{}: True{}
    case False{}: R.is_named(d, "double") || R.is_named(d, "float") || R.is_named(d, "half") || R.is_named(d, "bool")

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
# DATA symbols tinymesa does not provide here, so the answer is the same refusal
# for all twelve -- and the refusal NAMES the symbol, which is what turns it from
# a shrug into a diagnosis. The FIRST one is `double`'s, because the dict
# comprehension is eager, so that is the symbol the traceback actually says.
# THE CALL RAISES FOR EVERY `t`, INCLUDING THE FIVE WHOSE KEY IT DOES NOT HOLD.
# `nir.py:15` builds the dict EAGERLY, so `g("glsl_type_builtin_double")` runs --
# and raises -- before `[t]` is ever indexed, so an unkeyed `t` never gets that
# far. The first run printed `NO_KEY` for the fp8s and `__bf16` here and
# `glsl call` disagreed with CPython on five of seventeen cells. Key MEMBERSHIP
# is `glsl keys`; the CALL is this, and it has one answer.
def glsl_const(nm: String) -> String: "AttributeError:glsl_type_builtin_double"

def glsl_row(+d: S.Dt) -> String: String.concat([dtn(d), " -> ", glsl_sym(d), " ", glsl_const(glsl_sym(d))])

def glsl_call_row(+d: S.Dt) -> String: String.concat([dtn(d), "=", glsl_const(glsl_sym(d))])

# ===========================================================================
# `ncast` -- nir.py:27-28.
#
#     nalu(b, f"{c(it)}2{c(it) if it in dtypes.ints and ot in dtypes.ints else
#                  c(ot, ot == dtypes.bool)}{ot.bitsize}", src)
#
# The name is `c(it)` + the literal `2` + a SECOND prefix + the DESTINATION's
# bit size, and the second prefix has a two-way condition that is easy to get
# backwards: int->int keeps the SOURCE prefix -- so a signed->unsigned cast is
# `i2u8` and the source's `i` survives -- while everything else uses
# `c(ot, ot == bool)` on the DESTINATION. So `float->int` is `f2i32`,
# `uint8->bool` is `u2b1`, and `bool->bool` is `b2b1`: the destination `bool`
# makes the second prefix `b` even though the SOURCE is not an int.
#
# GATED BY ASKING, not by re-deriving. The oracle replaces `nir.g` with a
# recorder and calls the REAL `nir.ncast`, so each `py=` half is the symbol mesa
# was asked for. A port that misreads the two-way condition disagrees on a large
# part of the 17x17 grid, which is the point.
# ===========================================================================

# BOTH PREFIXES ARE COMPUTED AND PASSED IN, rather than one computed per arm:
# Bend counts a parameter read in each arm as read TWICE (measured at line 617,
# `ot` in `ncast_mid.of`), so the arms must select between two values rather than
# compute one. That also puts the two-way condition in ONE place.
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

# ===========================================================================
# `nalu` -- nir.py:38. `g(f"nir_build_alu{len(srcs)}")(b, g(f"nir_op_{op}"), *srcs)`.
#
# So the mesa SYMBOL is `nir_op_` + the table entry and the BUILD call is
# `nir_build_alu` + the arity. FOUR arities exist and `nir.py` asks for
# `alu1` (ncast, nchannel, nimm, nundef), `alu2` (every binary op), `alu3` (`ilt`
# compares, and `ngid`/`nlid` are `nc=3` destinations) and `alu4` (`tovec`,
# nir.py:273). A `nalu` with FIVE srcs would ask for a fifth arity that does not
# exist, so `alu5` is ABSENT and that is a row rather than an assumption.
# ===========================================================================

def build_alu(n: U32) -> String:
  match n:
    case 1: "nir_build_alu1"
    case 2: "nir_build_alu2"
    case 3: "nir_build_alu3"
    case 4: "nir_build_alu4"
    case _: "ABSENT"

# ===========================================================================
# `scope(space)` -- nir.py:83.
#
#     return 'global' if space == AddrSpace.GLOBAL else ('shared' if space ==
#            AddrSpace.LOCAL else 'deref')
#
# TWO arms and an ELSE, and the else is a WALL: `AddrSpace.REG` is the one the
# else was written for, and `AddrSpace.ALU` -- which exists, and which
# `NIRRenderer.param` reads at nir.py:147 -- falls into it too, answering
# `deref`. So `scope(ALU) == scope(REG)` and a renderer that gives ALU its own
# case is not reading this function. The ALU rows below are exactly that test.
# ===========================================================================

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

# ===========================================================================
# THE INTRINSIC ARITHMETIC -- nir.py:84-91. The oracle reaches these by calling
# the REAL closures out of `nir_instr` (`inspect.getclosurevars`), not by
# reimplementing them, so every `py=` half here is `nir`'s own lambda:
#
#   nstore (nir.py:84-87)
#     WRITE_MASK = (1 << val.num_components) - 1            ALWAYS
#     ALIGN_MUL  = val.bit_size // 8 * val.num_components   UNLESS space is REG
#     srcs       = [val, addr] reversed for REG, copied otherwise
#   nload  (nir.py:88-91)
#     ACCESS     = ACCESS_CAN_REORDER                        ONLY for GLOBAL
#     ALIGN_MUL  = u.dtype.itemsize * u.max_numel()          UNLESS space is REG
#
# TWO FACTS THE ROWS PIN, and both are boundary cases rather than arithmetic:
# `REG` is the ONLY space with no `ALIGN_MUL` on either side, so `ALU` -- which
# HAS one -- is the row that separates "unless REG" from "for GLOBAL"; and the
# REG `srcs` REVERSAL is the one place in this file where the order of two
# identical-typed operands is the whole answer, so it is emitted as a NAME list
# rather than a count. `nir.py:86` spells the reversal
# `[nsrc(val), nsrc(addr)][::1 if space != AddrSpace.REG else -1]`.
# ===========================================================================

def nstore_mask(n: U32) -> U32: U32.sub(U32.shln(1, U32.to_nat(n)), 1)

def nstore_align.of(is_reg: Bool, bits: U32, n: U32) -> U32:
  match is_reg:
    case True{}: 0
    case False{}: U32.mul(U32.div(bits, 8), n)

def nstore_align(space: S.Addr, bits: U32, n: U32) -> U32: nstore_align.of(is_reg(space), bits, n)

# `0` IS NOT THE HONEST ANSWER FOR REG: the intrins dict simply HAS NO
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

# ===========================================================================
# `padded_idx(param_idx:int, size:int) -> round_up(param_idx, size) + size`
# -- nir.py:246.
#
# `round_up(x, y)` is `(x + (y-1)) // y * y`, so `padded_idx(p, s)` is
# `ceil(p/s)*s + s`: it rounds UP and then adds a WHOLE EXTRA size, which
# reserves the base pointer of the NEXT param. So it is never `s` and never `0`,
# and `padded_idx(0, s) == s`. Both are rows, because `round_up + size` misread as
# `round_up` is an off-by-a-whole-block, and `LVPRenderer.param_sz`
# (nir.py:271) and `IR3Renderer.param_sz` (nir.py:309) both REDUCE over it.
# ===========================================================================

# `y` appears THREE times -- the `(y-1)`, the divisor and the multiplier -- so it
# needs `+` and this is the only arithmetic in the file that does. Measured.
def round_up(+x: U32, +y: U32) -> U32: U32.mul(U32.div(U32.add(x, U32.sub(y, 1)), y), y)

def padded_idx(+p: U32, +s: U32) -> U32: U32.add(round_up(p, s), s)

# ===========================================================================
# THE RENDERER RECORD -- convention 1. `NIRRenderer` and its three subclasses
# are one `Nir` each; nothing mutates after construction and the gate READS THE
# RECORD, so a wrong constant is a moved row rather than a wrong shader nobody
# diffs.
#
# `NIRRenderer` (:116-119) sets `suffix = "NIR"`, takes the THREE MAXIMA from
# `CUDARenderer` and has no `has_local`/`has_shared` override, so it keeps the
# base's `True`/`True`. `LVPRenderer` (:255-259) is the only one that flips them
# AND the only one that pins `global_max = (1, 0, 0)` -- which is why that row
# carries a ZERO and every other device's does not, and why `unum` has to print
# the zeros rather than elide them. `NAKRenderer` (:248) and `IR3Renderer` (:285)
# override neither.
#
# `sd_kind` is `Nir`'s own tag for WHICH `supported_dtypes` override is live:
# `0` the base filter, `1` NAK's arch test, `2` IR3's `double` drop. LVP is `0`
# because `LVPRenderer` does not override `supported_dtypes` -- it inherits
# `NIRRenderer`'s -- and a renderer that gave it a tag of its own would be
# inventing an override `nir.py` does not have.
# ===========================================================================

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
# `global_max` and `local_max` are triples. The first draft gave it three `U32`s
# of `0` and the `rec NIR` row disagreed with CPython on the field COUNT --
# caught because the row is a string and not a claim about three numbers.
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

# ===========================================================================
# `supported_dtypes` -- nir.py:244, :253, :321. THREE OVERRIDES, and the
# NESTING is the content:
#
#   NIRRenderer (:244)  dtypes.all MINUS fp8s MINUS bfloat16            -> 12
#   NAKRenderer (:253)  NIR's MINUS half, but only when int(arch[3:]) < 53  -> 11 / 12
#   IR3Renderer (:321)  NIR's MINUS double                              -> 11
#
# The NAK test is `int(self.target.arch[3:])`, so it reads the digits after a
# THREE-CHARACTER PREFIX: `sm_53` -> 53 -> keeps `half`, `sm_52` -> 52 -> drops
# it, `sm_120` -> 120 -> keeps it. `52` and `120` are the two boundary rows,
# because a `>=` written as `>` drops `half` on 53 and a TWO-character slice
# would raise on a bare `"86"` -- which is `arch_off` below.
# ===========================================================================

# No binder: `R.is_named` takes the dtype, so a `case S.Dt{...}` here bound four
# names and read none of them -- and an unread binder still counts toward
# affinity (refused as "nm (consumed more than once)" at line 884).
def sd.drop_base(+d: S.Dt) -> Bool:
  Bool.or(R.is_named(d, "float8_e4m3") || R.is_named(d, "float8_e5m2") ||
  R.is_named(d, "float8_e4m3fnuz") || R.is_named(d, "float8_e5m2fnuz"), R.is_named(d, "__bf16"))

def sd.drop_nak.of(under: Bool, d: S.Dt) -> Bool:
  match under:
    case True{}: R.is_named(d, "half")
    case False{}: False{}

def sd.drop_ir3(d: S.Dt) -> Bool: R.is_named(d, "double")

# ONE MATCH PER PARAMETER, and that is a measured Bend rule rather than taste: a
# def parameter or binder may be `match`ed ONCE, so the base filter and the
# device tag are two matches in TWO defs (`sd.is_drop.of` / `sd.by_kind`) rather
# than one nested match. Refused at line 893 on the nested spelling.
#
# A device that set two flags would get BOTH drops, which no renderer does and
# which no row can hide -- that is what the `sd_kind` tag buys.
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
# `String.to_nat` -- so the four gated arches are matched directly and the SLICE
# stays a separate string row (`arch_off`). Keeping them apart matters: `arch_off`
# is the rule "the offset is THREE" and `arch_int` is the rule "these are the
# values", and a port that fused them could pass both rows while getting the
# offset wrong for a fifth arch. `"86"` has no `sm_` prefix, so `arch_off` reads
# it as itself -- which is the row that would catch a two-character slice.
def arch_int(nm: String) -> U32:
  match nm:
    case "sm_52": 52
    case "sm_53": 53
    case "sm_86": 86
    case "sm_120": 120
    case _: 0

# ===========================================================================
# `code_for_op` -- nir.py:119 and :262.
#
#     code_for_op = {**{k:None for k in s_aop.keys()}, **{k:None for k in f_aop.keys()}}
#     LVPRenderer: {k:v for k,v in NIRRenderer.code_for_op.items() if k != Ops.EXP2}
#
# A SET of ops -- 14 signed + 12 float with SIX shared op names, so 20 unique,
# and 19 for LVP. Every value is `lambda: None`, so the set's only content is
# WHICH ops a device claims to implement natively; the `EXP2` removal is
# gallivm's "undefined behavior with infs, 0s and nans" (nir.py:260-261). The
# gate emits the joined NAMES in `CFO_NAMES`' order, so a dropped op is a diff.
# ===========================================================================

def cfo.is(nm: String) -> Bool:
  match nm:
    case "ADD": True{}
    case "AND": True{}
    case "CDIV": True{}
    case "CMOD": True{}
    case "CMPEQ": True{}
    case "CMPLT": True{}
    case "CMPNE": True{}
    case "EXP2": True{}
    case "FDIV": True{}
    case "LOG2": True{}
    case "MAX": True{}
    case "MUL": True{}
    case "OR": True{}
    case "RECIPROCAL": True{}
    case "SHL": True{}
    case "SHR": True{}
    case "SIN": True{}
    case "TRUNC": True{}
    case "WHERE": True{}
    case "XOR": True{}
    case _: False{}

# `k != Ops.EXP2` is the ONLY filter `LVPRenderer` applies (nir.py:262), and
# `Bool.or(Bool.not(drops), nm != "EXP2")` says it with no `match` at all. That is
# not a style preference: a `match` whose scrutinee is `Nir.drops_exp2(n)` is a
# computed value and is refused, and nesting a `match` on a def parameter inside
# another `match` is refused too (measured at lines 893 and 979).
def cfo.has(+n: Nir, +nm: String) -> Bool:
  Bool.and(cfo.is(nm), Bool.or(Bool.not(Nir.drops_exp2(n)), Bool.not(String.eq(nm, "EXP2"))))

def cfo_names() -> List<&2, String>: ["ADD","AND","CDIV","CMOD","CMPEQ","CMPLT","CMPNE","EXP2","FDIV","LOG2","MAX","MUL","OR","RECIPROCAL","SHL","SHR","SIN","TRUNC","WHERE","XOR"]

def cfo.go(+n: Nir, +ns: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    # `Bool.pick(t, cond, X, Y)` is X WHEN cond IS TRUE, so the KEPT arm goes in
    # the SECOND position. The first run had it the other way round and every
    # `cfo` row printed the exact inverse: `cfo nir` was `[]` and `cfo lvp` was
    # `[EXP2]`. This is `agent-core.md`'s "Bool.pick CHOOSES an arm; it does not
    # SEQUENCE one" wearing the polarity as a disguise.
    case +h <> +t: cfo.go(n, t, Bool.pick(List<&2, String>, cfo.has(n, h), List.append(&2, String, acc, [h]), acc))

def code_for_op(n: Nir) -> List<&2, String>: cfo.go(n, cfo_names(), Nil{})

# ===========================================================================
# THE GATE, AND WHAT EVERY GROUP IS FOR.
#
#   .venv/bin/python .agents/slop/nir/nir-oracle.py rows > .agents/slop/nir/py1.txt
#   ./bin/bend tinybendygrad/renderer/nir.bend            > /tmp/nir_i.txt
#   ./bin/bend tinybendygrad/renderer/nir.bend -o /tmp/nir && /tmp/nir > /tmp/nir_n.txt
#   diff /tmp/nir_i.txt .agents/slop/nir/py1.txt && diff /tmp/nir_n.txt .agents/slop/nir/py1.txt
#
# The whole gate is ONE `IO.print`, so its own newline is the only frame and the
# oracle's single trailing "\n" is its match. BOTH lanes are compared -- the
# interpreted and the native.
#
# `aop.*` AND `aop rev.*` ARE THE TWO DIRECTIONS, and they are separate rows on
# purpose: `u_aop` reads nir.py:19-20 forwards and `u_aop.rev` reads it
# backwards, so an arm moved in one leaves the other green. `aop rev` prints
# `name -> rev(name) -> forward(rev(name))`, so a REVERSE table that disagrees
# with the FORWARD one is caught rather than assumed consistent.
#
# `mesa.nir_op_*` IS THE CONSTANT SWEEP: every enum this file names is gated by
# `getattr` on the live module, and `aop.*` carries the SAME value inline as
# `OP=nir_name/value`, so a table entry and the constant behind it move together.
# ===========================================================================

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
    # THE ACCUMULATOR IS A STRING, NOT A LIST. `join` puts a `,` BETWEEN
    # elements, so a list of columns read `...,pi32,|1:ru1,...` with `|` as a
    # prefix and `...,pi32;,1:ru1` with `;` as a suffix -- in both cases a
    # separator this fold does not own sat between two columns. MEASURED in a
    # six-line reduction before it was spelled this way.
    case +p <> +t: pad_tbl.go(t, ss, String.concat([acc, pad_col(p, ss, Nil{}), ";"]))

def pad_tbl(ps: List<&2, U32>, ss: List<&2, U32>) -> String: pad_tbl.go(ps, ss, "")

# ===========================================================================
# THE GATE ROWS.
#
# `pad_tbl` is ONE COLUMN PER `param_idx` holding every `size`: the grid is
# 11 x 5, so a joined column keeps it at one row while a wrong CELL is still a
# diff. A `size`-outer fold prints the same numbers in the other order and
# would read as a different table, so the ORDER is part of the claim.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([
    # ---- `c(t, u)` : 17 dtypes x 2, plus the THREE `dtypes.all` does not hold
    r("c bool u=True ", c(S.boolean(), True{}), "b"),
    r("c bool u=False", c(S.boolean(), False{}), "b"),
    r("c uint8 u=True ", c(S.uint8(), True{}), "u"),
    r("c uint8 u=Fals", c(S.uint8(), False{}), "i"),
    r("c uint32 u=True", c(S.uint32(), True{}), "u"),
    r("c int32 u=True ", c(S.int32(), True{}), "i"),
    r("c half u=True  ", c(S.half(), True{}), "f"),
    r("c bf16 u=True  ", c(S.bfloat16(), True{}), "f"),
    r("c fp8_e4m3 u=T ", c(S.fp8e4m3(), True{}), "f"),
    r("c double u=True", c(S.double(), True{}), "f"),
    r("c uint64 u=Fal", c(S.uint64(), False{}), "i"),
    # THE THREE THAT SEPARATE `in_ints` FROM `S.Dt.is_int`. `weakint` is in
    # `dtypes.is_int` and NOT in `dtypes.ints`, so a port that used the shared
    # reader answers "i" here where Python answers "b".
    r("c weakint u=T ", c(S.weakint(), True{}), "b"),
    r("c weakfloat u=", c(S.weakfloat(), True{}), "b"),
    r("c void u=True ", c(S.void(), True{}), "b"),
    r("c index u=True", c(S.index(), True{}), "b"),
    # ---- the three op tables, FORWARD and REVERSE
    r("aop u  keys    ", dnames(aop_keys()), "bool,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,__bf16,float,double"),
    r("aop u  table   ", u_aop_tbl(0), "ADD=iadd/306,MUL=imul/338,CDIV=udiv/427,CMOD=umod/451,CMPLT=ult/441,CMPNE=ine/344,CMPEQ=ieq/314,OR=ior/353,AND=iand/309,XOR=ixor/361,WHERE=bcsel/115,MAX=umax/447,SHL=ishl/356,SHR=ushr/479"),
    r("aop s  table   ", u_aop_tbl(1), "ADD=iadd/306,MUL=imul/338,CDIV=idiv/313,CMOD=irem/354,CMPLT=ilt/326,CMPNE=ine/344,CMPEQ=ieq/314,OR=ior/353,AND=iand/309,XOR=ixor/361,WHERE=bcsel/115,MAX=imax/334,SHL=ishl/356,SHR=ishr/357"),
    r("aop f  table   ", f_aop_tbl(2), "ADD=fadd/177,MUL=fmul/253,CMPLT=flt/240,CMPNE=fneu/260,CMPEQ=feq/213,FDIV=fdiv/198,RECIPROCAL=frcp/270,MAX=fmax/248,TRUNC=ftrunc/288,SIN=fsin/279,EXP2=fexp2/221,LOG2=flog2/238"),
    r("aop rev u      ", rev.go(0, u_ops()), "ADD:ADD->iadd/306,MUL:MUL->imul/338,CDIV:CDIV->udiv/427,CMOD:CMOD->umod/451,CMPLT:CMPLT->ult/441,CMPNE:CMPNE->ine/344,CMPEQ:CMPEQ->ieq/314,OR:OR->ior/353,AND:AND->iand/309,XOR:XOR->ixor/361,WHERE:WHERE->bcsel/115,MAX:MAX->umax/447,SHL:SHL->ishl/356,SHR:SHR->ushr/479"),
    r("aop rev s      ", rev.go(1, u_ops()), "ADD:ADD->iadd/306,MUL:MUL->imul/338,CDIV:CDIV->idiv/313,CMOD:CMOD->irem/354,CMPLT:CMPLT->ilt/326,CMPNE:CMPNE->ine/344,CMPEQ:CMPEQ->ieq/314,OR:OR->ior/353,AND:AND->iand/309,XOR:XOR->ixor/361,WHERE:WHERE->bcsel/115,MAX:MAX->imax/334,SHL:SHL->ishl/356,SHR:SHR->ishr/357"),
    r("aop rev f      ", rev.go(2, f_ops()), "ADD:ADD->fadd/177,MUL:MUL->fmul/253,CMPLT:CMPLT->flt/240,CMPNE:CMPNE->fneu/260,CMPEQ:CMPEQ->feq/213,FDIV:FDIV->fdiv/198,RECIPROCAL:RECIPROCAL->frcp/270,MAX:MAX->fmax/248,TRUNC:TRUNC->ftrunc/288,SIN:SIN->fsin/279,EXP2:EXP2->fexp2/221,LOG2:LOG2->flog2/238"),
    # `aop_kind` per dtype -- the CLASS tag, all seventeen plus the weak three.
    r("aop kind uint8 ", U32.show(aop_kind(S.uint8())), "0"),
    r("aop kind bool  ", U32.show(aop_kind(S.boolean())), "0"),
    r("aop kind int32 ", U32.show(aop_kind(S.int32())), "1"),
    r("aop kind half  ", U32.show(aop_kind(S.half())), "2"),
    r("aop kind weaki ", U32.show(aop_kind(S.weakint())), "1"),
    r("aop kind void  ", U32.show(aop_kind(S.void())), "1"),
    # ---- `glsl_type`: the SYMBOL is computed, the CONSTANT is a refusal
    r("glsl keys      ", glsl_key_go(all_of(), Nil{}), "float8_e4m3=?,float8_e5m2=?,float8_e4m3fnuz=?,float8_e5m2fnuz=?,half=glsl_type_builtin_float16_t,__bf16=?,float=glsl_type_builtin_float,double=glsl_type_builtin_double,unsigned char=glsl_type_builtin_uint8_t,unsigned short=glsl_type_builtin_uint16_t,unsigned int=glsl_type_builtin_uint,unsigned long=glsl_type_builtin_uint64_t,signed char=glsl_type_builtin_int8_t,short=glsl_type_builtin_int16_t,int=glsl_type_builtin_int,long=glsl_type_builtin_int64_t,bool=glsl_type_builtin_uint8_t"),
    r("glsl call      ", glsl_call(all_of()), "float8_e4m3=AttributeError:glsl_type_builtin_double,float8_e5m2=AttributeError:glsl_type_builtin_double,float8_e4m3fnuz=AttributeError:glsl_type_builtin_double,float8_e5m2fnuz=AttributeError:glsl_type_builtin_double,half=AttributeError:glsl_type_builtin_double,__bf16=AttributeError:glsl_type_builtin_double,float=AttributeError:glsl_type_builtin_double,double=AttributeError:glsl_type_builtin_double,unsigned char=AttributeError:glsl_type_builtin_double,unsigned short=AttributeError:glsl_type_builtin_double,unsigned int=AttributeError:glsl_type_builtin_double,unsigned long=AttributeError:glsl_type_builtin_double,signed char=AttributeError:glsl_type_builtin_double,short=AttributeError:glsl_type_builtin_double,int=AttributeError:glsl_type_builtin_double,long=AttributeError:glsl_type_builtin_double,bool=AttributeError:glsl_type_builtin_double"),
    # ---- `ncast`: 17 sources x 17 destinations, joined per source
    r("ncast from int32", ncast_row(S.int32(), all_of()), "float8_e4m3:i2f8/AttributeError,float8_e5m2:i2f8/AttributeError,float8_e4m3fnuz:i2f8/AttributeError,float8_e5m2fnuz:i2f8/AttributeError,half:i2f16/293,__bf16:i2f16/293,float:i2f32/294,double:i2f64/295,unsigned char:i2i8/301,unsigned short:i2i16/298,unsigned int:i2i32/299,unsigned long:i2i64/300,signed char:i2i8/301,short:i2i16/298,int:i2i32/299,long:i2i64/300,bool:i2b1/AttributeError"),
    r("ncast from uint8", ncast_row(S.uint8(), all_of()), "float8_e4m3:u2f8/AttributeError,float8_e5m2:u2f8/AttributeError,float8_e4m3fnuz:u2f8/AttributeError,float8_e5m2fnuz:u2f8/AttributeError,half:u2f16/411,__bf16:u2f16/411,float:u2f32/412,double:u2f64/413,unsigned char:u2u8/419,unsigned short:u2u16/416,unsigned int:u2u32/417,unsigned long:u2u64/418,signed char:u2u8/419,short:u2u16/416,int:u2u32/417,long:u2u64/418,bool:u2b1/AttributeError"),
    r("ncast from bool ", ncast_row(S.boolean(), all_of()), "float8_e4m3:b2f8/AttributeError,float8_e5m2:b2f8/AttributeError,float8_e4m3fnuz:b2f8/AttributeError,float8_e5m2fnuz:b2f8/AttributeError,half:b2f16/32,__bf16:b2f16/32,float:b2f32/33,double:b2f64/34,unsigned char:b2i8/39,unsigned short:b2i16/36,unsigned int:b2i32/37,unsigned long:b2i64/38,signed char:b2i8/39,short:b2i16/36,int:b2i32/37,long:b2i64/38,bool:b2b1/28"),
    r("ncast from float", ncast_row(S.single(), all_of()), "float8_e4m3:f2f8/AttributeError,float8_e5m2:f2f8/AttributeError,float8_e4m3fnuz:f2f8/AttributeError,float8_e5m2fnuz:f2f8/AttributeError,half:f2f16/156,__bf16:f2f16/156,float:f2f32/159,double:f2f64/160,unsigned char:f2i8/166,unsigned short:f2i16/163,unsigned int:f2i32/164,unsigned long:f2i64/165,signed char:f2i8/166,short:f2i16/163,int:f2i32/164,long:f2i64/165,bool:f2b1/AttributeError"),
    r("ncast from long ", ncast_row(S.int64(), all_of()), "float8_e4m3:i2f8/AttributeError,float8_e5m2:i2f8/AttributeError,float8_e4m3fnuz:i2f8/AttributeError,float8_e5m2fnuz:i2f8/AttributeError,half:i2f16/293,__bf16:i2f16/293,float:i2f32/294,double:i2f64/295,unsigned char:i2i8/301,unsigned short:i2i16/298,unsigned int:i2i32/299,unsigned long:i2i64/300,signed char:i2i8/301,short:i2i16/298,int:i2i32/299,long:i2i64/300,bool:i2b1/AttributeError"),
    r("ncast from weaki", ncast_row(S.weakint(), all_of()), "float8_e4m3:b2f8/AttributeError,float8_e5m2:b2f8/AttributeError,float8_e4m3fnuz:b2f8/AttributeError,float8_e5m2fnuz:b2f8/AttributeError,half:b2f16/32,__bf16:b2f16/32,float:b2f32/33,double:b2f64/34,unsigned char:b2i8/39,unsigned short:b2i16/36,unsigned int:b2i32/37,unsigned long:b2i64/38,signed char:b2i8/39,short:b2i16/36,int:b2i32/37,long:b2i64/38,bool:b2b1/28"),
    # ---- `scope` -- ALU IS THE ROW: it is not REG and it is not GLOBAL
    r("scope global   ", scope(S.AGlobal{}), "global"),
    r("scope local    ", scope(S.ALocal{}), "shared"),
    r("scope reg      ", scope(S.AReg{}), "deref"),
    r("scope alu      ", scope(S.Aalu{}), "deref"),
    r("is_reg global  ", b2s(is_reg(S.AGlobal{})), "False"),
    r("is_reg alu     ", b2s(is_reg(S.Aalu{})), "False"),
    r("is_global local", b2s(is_global(S.ALocal{})), "False"),
    r("is_global alu  ", b2s(is_global(S.Aalu{})), "False"),
    # ---- the intrinsic arithmetic: WRITE_MASK / ALIGN_MUL / src ORDER
    r("nstore mask    ", mask_tbl(S.uint32(), [1, 2, 3, 4, 8, 16]), "x1=wm1,al4,gsrcval,addr,lsrcaddr,val,lal4,nc1,bs32,x2=wm3,al8,gsrcval,addr,lsrcaddr,val,lal8,nc2,bs32,x3=wm7,al12,gsrcval,addr,lsrcaddr,val,lal12,nc3,bs32,x4=wm15,al16,gsrcval,addr,lsrcaddr,val,lal16,nc4,bs32,x8=wm255,al32,gsrcval,addr,lsrcaddr,val,lal32,nc8,bs32,x16=wm65535,al64,gsrcval,addr,lsrcaddr,val,lal64,nc16,bs32"),
    r("nstore align L ", nstore_align_str(S.ALocal{}, 64, 4), "32"),
    r("nstore align R ", nstore_align_str(S.AReg{}, 64, 4), "ABSENT"),
    r("nstore align A ", nstore_align_str(S.Aalu{}, 64, 4), "32"),
    r("nstore hasAL R ", b2s(nstore_has_align(S.AReg{})), "False"),
    r("nstore hasAL A ", b2s(nstore_has_align(S.Aalu{})), "True"),
    r("nstore srcs G  ", join(nstore_srcs(S.AGlobal{})), "val,addr"),
    r("nstore srcs A  ", join(nstore_srcs(S.Aalu{})), "val,addr"),
    r("nstore srcs R  ", join(nstore_srcs(S.AReg{})), "addr,val"),
    r("nload hasACC G ", b2s(nload_has_access(S.AGlobal{})), "True"),
    r("nload hasACC L ", b2s(nload_has_access(S.ALocal{})), "False"),
    r("nload hasACC R ", b2s(nload_has_access(S.AReg{})), "False"),
    r("nload hasACC A ", b2s(nload_has_access(S.Aalu{})), "False"),
    r("nload hasAL R  ", b2s(nload_has_align(S.AReg{})), "False"),
    r("nload hasAL A  ", b2s(nload_has_align(S.Aalu{})), "True"),
    r("nload align R  ", U32.show(nload_align(S.AReg{}, 4, 16)), "0"),
    r("nload align L  ", U32.show(nload_align(S.ALocal{}, 1, 16)), "16"),
    r("bit_size long  ", U32.show(bit_size(S.int64())), "64"),
    r("bit_size half  ", U32.show(bit_size(S.half())), "16"),
    r("def_bit_size 64", U32.show(def_bit_size(64)), "64"),
    r("gid nc/bs      ", String.concat([U32.show(gid_nc()), "/", U32.show(gid_bs())]), "3/32"),
    r("barrier has_def", b2s(barrier_has_def()), "False"),
    r("store has_def  ", b2s(store_has_def()), "False"),
    r("load has_def   ", b2s(load_has_def()), "True"),
    r("load_nc 16     ", U32.show(load_nc(16)), "16"),
    r("store_nc 4     ", U32.show(store_nc()), "1"),
    # ---- `nalu`'s two symbols: the op name and the BUILD arity
    r("alu arities    ", String.concat([build_alu(1), ",", build_alu(2), ",", build_alu(3), ",", build_alu(4), ",", build_alu(5)]), "nir_build_alu1,nir_build_alu2,nir_build_alu3,nir_build_alu4,ABSENT"),
    # ---- `padded_idx` -- `round_up` + a WHOLE extra size
    r("padded 0 4     ", pad_row(0, 4), "padded_idx 0 4 = ru0+sz=4"),
    r("padded 3 8     ", pad_row(3, 8), "padded_idx 3 8 = ru8+sz=16"),
    r("padded 8 8     ", pad_row(8, 8), "padded_idx 8 8 = ru8+sz=16"),
    r("padded 9 16    ", pad_row(9, 16), "padded_idx 9 16 = ru16+sz=32"),
    r("padded 17 32   ", pad_row(17, 32), "padded_idx 17 32 = ru32+sz=64"),
    r("padded tbl     ", pad_tbl([0, 1, 3, 4, 7, 8, 9, 15, 16, 17, 32], [1, 4, 8, 16, 32]), "1:ru0,pi1,4:ru0,pi4,8:ru0,pi8,16:ru0,pi16,32:ru0,pi32;1:ru1,pi2,4:ru4,pi8,8:ru8,pi16,16:ru16,pi32,32:ru32,pi64;1:ru3,pi4,4:ru4,pi8,8:ru8,pi16,16:ru16,pi32,32:ru32,pi64;1:ru4,pi5,4:ru4,pi8,8:ru8,pi16,16:ru16,pi32,32:ru32,pi64;1:ru7,pi8,4:ru8,pi12,8:ru8,pi16,16:ru16,pi32,32:ru32,pi64;1:ru8,pi9,4:ru8,pi12,8:ru8,pi16,16:ru16,pi32,32:ru32,pi64;1:ru9,pi10,4:ru12,pi16,8:ru16,pi24,16:ru16,pi32,32:ru32,pi64;1:ru15,pi16,4:ru16,pi20,8:ru16,pi24,16:ru16,pi32,32:ru32,pi64;1:ru16,pi17,4:ru16,pi20,8:ru16,pi24,16:ru16,pi32,32:ru32,pi64;1:ru17,pi18,4:ru20,pi24,8:ru24,pi32,16:ru32,pi48,32:ru32,pi64;1:ru32,pi33,4:ru32,pi36,8:ru32,pi40,16:ru32,pi48,32:ru32,pi64;"),
    # ---- `int(self.target.arch[3:])` -- the offset is THREE
    r("arch_off sm_53 ", arch_off("sm_53"), "53"),
    r("arch_off sm_120", arch_off("sm_120"), "120"),
    r("arch_off 86    ", arch_off("86"), "86"),
    r("arch_int sm_52 ", U32.show(arch_int("sm_52")), "52"),
    r("arch_int sm_53 ", U32.show(arch_int("sm_53")), "53"),
    r("arch_int sm_120", U32.show(arch_int("sm_120")), "120"),
    # ---- the RENDERER RECORD, and its three supported_dtypes overrides
    r("rec NIR        ", Nir.row(Nir.base()), "NIR has_local=True has_shared=True global_max=[2147483647,65535,65535] local_max=[1024,1024,64] shared_max=49152 drops_exp2=False has_param=False sd_kind=0"),
    r("rec NAK        ", Nir.row(Nir.nak()), "NAK has_local=True has_shared=True global_max=[2147483647,65535,65535] local_max=[1024,1024,64] shared_max=49152 drops_exp2=False has_param=True sd_kind=1"),
    r("rec LVP        ", Nir.row(Nir.lvp()), "LVP has_local=False has_shared=False global_max=[1,0,0] local_max=[1024,1024,64] shared_max=49152 drops_exp2=True has_param=True sd_kind=0"),
    r("rec IR3        ", Nir.row(Nir.ir3()), "IR3 has_local=True has_shared=True global_max=[2147483647,65535,65535] local_max=[1024,1024,64] shared_max=49152 drops_exp2=False has_param=True sd_kind=2"),
    r("sd nir         ", dnames(supported_dtypes(Nir.base(), 86)), "half,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    r("sd nak sm_86   ", dnames(supported_dtypes(Nir.nak(), 86)), "half,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    r("sd nak sm_53   ", dnames(supported_dtypes(Nir.nak(), 53)), "half,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    r("sd nak sm_52   ", dnames(supported_dtypes(Nir.nak(), 52)), "float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    r("sd nak sm_120  ", dnames(supported_dtypes(Nir.nak(), 120)), "half,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    r("sd ir3         ", dnames(supported_dtypes(Nir.ir3(), 86)), "half,float,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool"),
    # ---- `code_for_op` -- 20 ops, and LVP's 19 without EXP2
    r("cfo nir        ", join(code_for_op(Nir.base())), "ADD,AND,CDIV,CMOD,CMPEQ,CMPLT,CMPNE,EXP2,FDIV,LOG2,MAX,MUL,OR,RECIPROCAL,SHL,SHR,SIN,TRUNC,WHERE,XOR"),
    r("cfo lvp        ", join(code_for_op(Nir.lvp())), "ADD,AND,CDIV,CMOD,CMPEQ,CMPLT,CMPNE,FDIV,LOG2,MAX,MUL,OR,RECIPROCAL,SHL,SHR,SIN,TRUNC,WHERE,XOR"),
    r("cfo nak        ", join(code_for_op(Nir.nak())), "ADD,AND,CDIV,CMOD,CMPEQ,CMPLT,CMPNE,EXP2,FDIV,LOG2,MAX,MUL,OR,RECIPROCAL,SHL,SHR,SIN,TRUNC,WHERE,XOR"),
    r("cfo ir3        ", join(code_for_op(Nir.ir3())), "ADD,AND,CDIV,CMOD,CMPEQ,CMPLT,CMPNE,EXP2,FDIV,LOG2,MAX,MUL,OR,RECIPROCAL,SHL,SHR,SIN,TRUNC,WHERE,XOR"),
    ]))
