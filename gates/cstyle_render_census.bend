# cstyle_render_census.bend -- A RENDER CENSUS over `tinybendygrad/renderer/cstyle.bend`:
# the same UOp is built in both lanes, RENDERED, and the two STRINGS are compared byte for byte.
#
#   .venv/bin/python gates/cstyle_render_census-gate.py
#
# THE POPULATION IS DISCOVERED, NOT LISTED. A name is a ROW iff
# `tinygrad/renderer/cstyle.py` defines a method or function of that name (leading underscores
# stripped) AND the port's def emits a String (or a value) from a UOp:
#
#     grep -o '^def [A-Za-z_0-9]*' tinybendygrad/renderer/cstyle.bend | sed 's/def //' | sed 's/\..*//' \
#       | sed 's/^_*//' | sort -u > /tmp/BD.txt
#     grep -oE '^[[:space:]]*def [A-Za-z_0-9]+' tinygrad/renderer/cstyle.py | sed -E 's/^[[:space:]]*def //' \
#       | sed 's/^_*//' | sort -u > /tmp/PY.txt
#     grep -Fxf /tmp/PY.txt /tmp/BD.txt        # 8 names
#
# EIGHT names survive: render_dtype (CPython's `_render_dtype` AND the LEGACY `render_dtype`),
# render_type, render_ptr, render_access, render_cast, render_index, render_buffer, wmma_name
# (`_wmma_name`). `render_kernel` and `uops_to_dtypes` are CPython methods/functions the port
# does NOT define -- both are the fold wall (`cstyle.bend`'s TODO(p3)s) -- so they fall out, and
# so does every `render_vector_prefix`/`_render`/`render`/`__getitem__`/`supported_dtypes`/
# `__init__`/`asm`/`is_cdna*`/`wmma_args`/`fp8_index`/`_ocml`/`create_non_native_float_pats`/
# `cast_float_to_bf16`, none of which has a port def.
#
# THE DISPATCH AND OPTION TABLES ARE NOT NAMES. `code_for_op`, `code_for_workitem` and the
# option attributes (`kernel_typedef`, `type_map`, `barrier`, ...) are CPython CLASS ATTRIBUTES,
# not methods, so they are not in the population -- but a renderer IS mostly a dispatch table,
# so the census reaches them THROUGH the eight functions and, for the ones no ported function
# reads, drives the port's own table def directly. Those are the `opt_`, `cfo_` and `cfw_` rows.
# The arms of one dispatch table are not separate rows: `cfo_<dev>_<op>` IS the arm, driven
# through the one `code_for_op.of` the port has.
#
# WHAT THE FIXTURE VARIES, AND WHY ALL FOUR. `_render_dtype` reads the DEVICE (six type_maps,
# six prefix sets), the DTYPE (eighteen names, four UNMAPPED on some devices), the
# ADDRSPACE/SIZE (the `*`, the local/global prefix, the `sz>1` suffix) and the OP/ARG (the ALU
# dispatch and the index arms). A one-CONST fixture exercises almost none of it.
#
# THE ARENA IS ONE ARENA, like `gates/ew_graph_census.bend`'s `world()`: `ri_world()` builds
# CONST 7, CONST 0, a CAST over CONST 0 and a REDUCE over CONST 0 in ONE `Arena.empty()` chain
# and hands out their indices, so no row can hand `render_index` a sibling arena. `Arena` is an
# IMMUTABLE `Data` value, so `Found.ar` snapshots and each row binds `+ar` before use.
#
# THE ARENA, AND THE MERGE RULE THIS LAYER DOES NOT HAVE. `render_index` reads ONE arena and
# `cstyle.bend` contains NO `Arena.merge` (`grep -c Arena.merge` is 0) -- unlike `ew_*`, whose
# `ew_join` merged two operand arenas BY LENGTH until it moved to `O.Arena.merge`. So the
# `gates/ew_graph_census.bend` trap cannot fire here and there is no rule to pick: `ri_world()`
# is the `world()` shape, one `Arena.empty()` chain handing out every index a row needs.
#
# THE NINETEEN DECLARED DIVERGENCES, measured. Eighteen are carve-outs and one is a DEFECT:
#   * `rdx_*` -- HEAD `_render_dtype` uses `self.type_map[dtype]` and RAISES KeyError for an
#     unmapped dtype; the port prints the dtype's own name (`tm_get`'s default), which is the
#     PIN's `.get(dtype, dtype.name)`. `gates/cstyle_render_census-gate.py` pins each one.
#   * `opt_float4_0` -- CPython's `float4` is `None` on the base and the port answers `""`
#     (the STACK arm is not ported, `cstyle.bend:427-437`).
#   * `cfo_*`/`cfw_*` KeyError rows -- a dropped ALU op and the base's empty workitem dict are
#     `KeyError` in CPython and `""` in the port, which `cstyle.bend:1045-1052` records.
#   * `ri_add_*` -- THE DEFECT. See the FINDING block at the foot.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/renderer/cstyle.bend as C

# ---- the one row printer, and a no-op for a list's empty tail --------------
# `IO.print("")` emits a blank line, which `gatekit._lines` drops, so the recursion's base case
# costs no row. MEASURED against `gatekit.py:214`.
def go(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def nil() -> IO(Unit): IO.print("")

# ---- the dtype table: an INTEGER KEY, so both lanes agree ------------------
# The order is the census's own; the names are `S.Dt.nm`, which is what `C.dt_name` reads and
# what `type_map` is keyed by.
def dt_of(+i: U32) -> S.Dt:
  match i:
    case 0: S.void()
    case 1: S.boolean()
    case 2: S.int8()
    case 3: S.uint8()
    case 4: S.int16()
    case 5: S.uint16()
    case 6: S.int32()
    case 7: S.uint32()
    case 8: S.int64()
    case 9: S.uint64()
    case 10: S.half()
    case 11: S.bfloat16()
    case 12: S.single()
    case 13: S.double()
    case 14: S.fp8e4m3()
    case 15: S.fp8e5m2()
    case 16: S.fp8e4m3fnuz()
    case _: S.fp8e5m2fnuz()

# `C.render_dtype(dev, d, sz, addr, mutable, override_ptr, img)`. The shape id selects the
# parameters: 0 scalar, 1 vec4, 2 local, 3 global, 4 reg+override, 5 image read, 6 image write.
def rd_at(+dev: U32, +dti: U32, +shape: U32) -> String:
  match shape:
    case 0: C.render_dtype(dev, dt_of(dti), 1, S.Aalu{}, True{}, False{}, False{})
    case 1: C.render_dtype(dev, dt_of(dti), 4, S.Aalu{}, True{}, False{}, False{})
    case 2: C.render_dtype(dev, dt_of(dti), 1, S.ALocal{}, True{}, False{}, False{})
    case 3: C.render_dtype(dev, dt_of(dti), 1, S.AGlobal{}, True{}, False{}, False{})
    case 4: C.render_dtype(dev, dt_of(dti), 1, S.AReg{}, True{}, True{}, False{})
    case 5: C.render_dtype(dev, dt_of(dti), 1, S.Aalu{}, False{}, False{}, True{})
    case _: C.render_dtype(dev, dt_of(dti), 1, S.Aalu{}, True{}, False{}, True{})

# ---- the option tables -----------------------------------------------------
def opt_name(+k: U32) -> String:
  match k:
    case 0: "ktypedef"
    case 1: "bufpre"
    case 2: "bufsuf"
    case 3: "smempre"
    case 4: "smemalign"
    case 5: "varpre"
    case 6: "varsuf"
    case 7: "barrier"
    case 8: "float4"
    case 9: "f4open"
    case 10: "f4close"
    case 11: "gep"
    case 12: "inf"
    case 13: "nan"
    case _: "smemcast"

def opt_val(+k: U32, +dev: U32) -> String:
  match k:
    case 0: C.kernel_typedef(dev, 4)
    case 1: C.buffer_prefix.of(dev)
    case 2: C.buffer_suffix.of(dev)
    case 3: C.smem_prefix.of(dev)
    case 4: C.smem_align.of(dev)
    case 5: C.var_prefix.of(dev)
    case 6: C.var_suffix.of(dev)
    case 7: C.barrier.of(dev)
    case 8: C.float4.of(dev)
    case 9: C.float4_open(dev)
    case 10: C.float4_close(dev)
    case 11: U32.show(C.gep_arr_threshold.of(dev))
    case 12: C.infinity.of(dev)
    case 13: C.nan.of(dev)
    case _: Bool.pick(String, C.smem_prefix_for_cast(dev), "1", "0")

# ---- the ALU dispatch table: name and constructor per op index -------------
# The 22-op order matches `tinygrad/renderer/cstyle.py`'s dict literal plus Clang's FDIV.
def op_name(+i: U32) -> String:
  match i:
    case 0: "sqrt"
    case 1: "reciprocal"
    case 2: "neg"
    case 3: "exp2"
    case 4: "log2"
    case 5: "sin"
    case 6: "trunc"
    case 7: "and"
    case 8: "xor"
    case 9: "or"
    case 10: "add"
    case 11: "sub"
    case 12: "mul"
    case 13: "cmod"
    case 14: "cdiv"
    case 15: "cmpne"
    case 16: "shr"
    case 17: "shl"
    case 18: "cmplt"
    case 19: "where"
    case 20: "cmpeq"
    case _: "fdiv"

def op_of(+i: U32) -> O.Op:
  match i:
    case 0: O.OpsSQRT{}
    case 1: O.OpsRECIPROCAL{}
    case 2: O.OpsNEG{}
    case 3: O.OpsEXP2{}
    case 4: O.OpsLOG2{}
    case 5: O.OpsSIN{}
    case 6: O.OpsTRUNC{}
    case 7: O.OpsAND{}
    case 8: O.OpsXOR{}
    case 9: O.OpsOR{}
    case 10: O.OpsADD{}
    case 11: O.OpsSUB{}
    case 12: O.OpsMUL{}
    case 13: O.OpsCMOD{}
    case 14: O.OpsCDIV{}
    case 15: O.OpsCMPNE{}
    case 16: O.OpsSHR{}
    case 17: O.OpsSHL{}
    case 18: O.OpsCMPLT{}
    case 19: O.OpsWHERE{}
    case 20: O.OpsCMPEQ{}
    case _: O.OpsFDIV{}

# ---- the fixture lists -----------------------------------------------------
def devs() -> List<&2, U32>: [0, 1, 2, 3, 4, 5]
def devs045() -> List<&2, U32>: [0, 4, 5]
def ri_devs() -> List<&2, U32>: [0, 1, 4]
def dts14() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
def vec_dts() -> List<&2, U32>: [2, 12, 13]
def fp8_dts() -> List<&2, U32>: [14, 15, 16, 17]
def legacy_dts() -> List<&2, U32>: [2, 12]
def opt_ks() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
def rb_addrs() -> List<&2, U32>: [0, 1, 2]

# ---- the iterators ---------------------------------------------------------
def for_dts(+pre: String, +dev: U32, +dts: List<&2, U32>, +shape: U32) -> IO(Unit):
  match dts:
    case Nil{}: nil()
    case x <> t:
      do IO<Unit>:
        go(String.concat([pre, U32.show(dev), "_", U32.show(x)]), rd_at(dev, x, shape))
        for_dts(pre, dev, t, shape)

def for_devs_dts(+pre: String, +devs: List<&2, U32>, +dts: List<&2, U32>, +shape: U32) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        for_dts(pre, d, dts, shape)
        for_devs_dts(pre, dt, dts, shape)

def for_devs(+pre: String, +devs: List<&2, U32>, +shape: U32, +dti: U32) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        go(String.concat([pre, U32.show(d)]), rd_at(d, dti, shape))
        for_devs(pre, dt, shape, dti)

def for_legacy_dts(+dev: U32, +dts: List<&2, U32>) -> IO(Unit):
  match dts:
    case Nil{}: nil()
    case x <> t:
      do IO<Unit>:
        go(String.concat(["rdl2_", U32.show(dev), "_", U32.show(x)]), C.render_dtype_legacy(dev, dt_of(x)))
        for_legacy_dts(dev, t)

def for_legacy(+devs: List<&2, U32>, +dts: List<&2, U32>) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        for_legacy_dts(d, dts)
        for_legacy(dt, dts)

def for_opt_dev(+k: U32, +devs: List<&2, U32>) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        go(String.concat(["opt_", opt_name(k), "_", U32.show(d)]), opt_val(k, d))
        for_opt_dev(k, dt)

def for_opts(+ks: List<&2, U32>, +devs: List<&2, U32>) -> IO(Unit):
  match ks:
    case Nil{}: nil()
    case k <> kt:
      do IO<Unit>:
        for_opt_dev(k, devs)
        for_opts(kt, devs)

def rb_addr(+i: U32) -> S.Addr:
  match i:
    case 1: S.ALocal{}
    case 2: S.AGlobal{}
    case _: S.Aalu{}

def rb_tag(+i: U32) -> String:
  match i:
    case 1: "local"
    case 2: "global"
    case _: "alu"

def for_rb_addr(+dev: U32, +addrs: List<&2, U32>) -> IO(Unit):
  match addrs:
    case Nil{}: nil()
    case a <> t:
      do IO<Unit>:
        go(String.concat(["rb_", U32.show(dev), "_", rb_tag(a)]), C.render_buffer(dev, dt_of(12), 4, rb_addr(a), "buf0"))
        for_rb_addr(dev, t)

def for_rb(+devs: List<&2, U32>, +addrs: List<&2, U32>) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        for_rb_addr(d, addrs)
        for_rb(dt, addrs)

# ---- the render_index fixture: ONE arena -----------------------------------
# bottom(0), CONST 7(1), CONST 0(2), CAST(CONST 0)(3), REDUCE ADD(CONST 0)(4).
def ri_world() -> O.Arena:
  +a0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})
  +a1 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(0)})
  +a2 = O.UOp.new(O.Found.ar(a1), O.OpsCAST{}, [O.Found.i(a1)], O.ADt{S.int32()}, O.TNone{})
  +a3 = O.UOp.new(O.Found.ar(a2), O.OpsREDUCE{}, [O.Found.i(a1)], O.AReduce{O.OpsADD{}, 0}, O.TNone{})
  O.Found.ar(a3)

def ri_lane(+dev: U32) -> IO(Unit):
  +ar = ri_world()
  go(String.concat(["ri_lane_", U32.show(dev)]), C.render_index(ar, dev, 1, S.Aalu{}, "alu1", "alu3", 4, True{}))

def ri_array(+dev: U32) -> IO(Unit):
  +ar = ri_world()
  go(String.concat(["ri_array_", U32.show(dev)]), C.render_index(ar, dev, 3, S.Aalu{}, "alu2", "cast1", 8, False{}))

def ri_swizzle(+dev: U32) -> IO(Unit):
  +ar = ri_world()
  go(String.concat(["ri_swizzle_", U32.show(dev)]), C.render_index(ar, dev, 3, S.Aalu{}, "alu1", "cast1", 4, False{}))

def ri_add(+dev: U32) -> IO(Unit):
  +ar = ri_world()
  go(String.concat(["ri_add_", U32.show(dev)]), C.render_index(ar, dev, 4, S.AGlobal{}, "buf1", "(a+b)", 4, True{}))

def ri_plain(+dev: U32) -> IO(Unit):
  +ar = ri_world()
  go(String.concat(["ri_plain_", U32.show(dev)]), C.render_index(ar, dev, 1, S.AGlobal{}, "buf1", "alu3", 4, True{}))

def for_ri(+devs: List<&2, U32>) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> dt:
      do IO<Unit>:
        a : Unit <- ri_lane(d)
        b : Unit <- ri_array(d)
        c : Unit <- ri_swizzle(d)
        e : Unit <- ri_add(d)
        f : Unit <- ri_plain(d)
        for_ri(dt)

# ---- the ALU dispatch rows -------------------------------------------------
def cfo_row(+pre: String, +dev: U32, +i: U32, +dti: U32) -> IO(Unit):
  go(String.concat([pre, U32.show(dev), "_", op_name(i)]),
     C.code_for_op.of(dev, op_of(i), ["a", "b", "c"], dt_of(dti)))

def cfw_row(+dev: U32, +k: String) -> IO(Unit):
  go(String.concat(["cfw_", U32.show(dev), "_", k]), C.code_for_workitem.g(dev, k, 1))

def cfo_ops() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]
def cfo_clang() -> List<&2, U32>: [0, 6, 21, 3, 5, 4, 1]
def cfo_sin() -> List<&2, U32>: [5]
def cfo_cuda() -> List<&2, U32>: [6, 5, 4, 3, 0, 1]
def cfo_hip() -> List<&2, U32>: [6, 5, 4, 3, 0]
def cfo_add() -> List<&2, U32>: [10]
def cfo_sqrt_trunc() -> List<&2, U32>: [0, 6]
def cfo_ft() -> List<&2, U32>: [1, 2, 3, 4, 5]

def for_ops(+pre: String, +dev: U32, +ops: List<&2, U32>, +dti: U32) -> IO(Unit):
  match ops:
    case Nil{}: nil()
    case i <> t:
      do IO<Unit>:
        r : Unit <- cfo_row(pre, dev, i, dti)
        for_ops(pre, dev, t, dti)

def for_cfo_devs(+pre: String, +devs: List<&2, U32>, +ops: List<&2, U32>, +dti: U32) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> t:
      do IO<Unit>:
        for_ops(pre, d, ops, dti)
        for_cfo_devs(pre, t, ops, dti)

def cfw_keys() -> List<&2, String>: ["g", "l"]

def for_keys(+dev: U32, +ks: List<&2, String>) -> IO(Unit):
  match ks:
    case Nil{}: nil()
    case k <> t:
      do IO<Unit>:
        r : Unit <- cfw_row(dev, k)
        for_keys(dev, t)

def cfw_go(devs: List<&2, U32>) -> IO(Unit):
  match devs:
    case Nil{}: nil()
    case d <> t:
      do IO<Unit>:
        r : Unit <- for_keys(d, cfw_keys())
        cfw_go(t)

def cfw_all() -> IO(Unit):
  cfw_go(devs())

# ---- the pointer/cast vocabulary and wmma_name -----------------------------
def rt_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- go("rt_scalar", C.render_type(0, dt_of(12), 1, S.Aalu{}, O.OpsCONST{}, False{}))
    b : Unit <- go("rp_scalar", C.render_ptr(0, dt_of(12), 1, S.Aalu{}, dt_of(12), "alu0", O.OpsCONST{}, False{}))
    c : Unit <- go("ra_scalar", C.render_access(0, dt_of(12), 1, S.Aalu{}, dt_of(12), "alu0", O.OpsCONST{}, False{}))
    d : Unit <- go("rc_scalar", C.render_cast(0, dt_of(12), 1, S.Aalu{}, O.OpsCONST{}, False{}, "alu0"))
    e : Unit <- go("rt_vec", C.render_type(0, dt_of(12), 4, S.Aalu{}, O.OpsCONST{}, False{}))
    f : Unit <- go("rp_vec", C.render_ptr(0, dt_of(12), 4, S.Aalu{}, dt_of(12), "alu0", O.OpsCONST{}, False{}))
    g : Unit <- go("ra_vec", C.render_access(0, dt_of(12), 4, S.Aalu{}, dt_of(12), "alu0", O.OpsCONST{}, False{}))
    h : Unit <- go("rt_idx_reg", C.render_type(0, dt_of(12), 1, S.AReg{}, O.OpsINDEX{}, False{}))
    i : Unit <- go("rp_cast", C.render_ptr(0, dt_of(12), 1, S.Aalu{}, dt_of(6), "cast0", O.OpsCONST{}, False{}))
    j : Unit <- go("ra_cast", C.render_access(0, dt_of(12), 1, S.Aalu{}, dt_of(6), "cast0", O.OpsCONST{}, False{}))
    return Unit{}

def wn_row(nm: String, dims: List<&2, U32>, +din: U32, +dout: U32) -> IO(Unit):
  go(nm, C.wmma_name(O.AWmma{dims, dt_of(din), 0, None{}}, dt_of(dout)))

def wn_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- wn_row("wn_a", [16, 16, 16], 2, 12)
    b : Unit <- wn_row("wn_b", [16, 8, 32], 10, 10)
    c : Unit <- wn_row("wn_c", [16, 16, 128], 14, 12)
    return Unit{}

# ---- main: THE ROW SEQUENCE, in the oracle's order -------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- for_opts(opt_ks(), devs())
    b : Unit <- for_devs_dts("rd_", devs(), dts14(), 0)
    c : Unit <- for_devs_dts("rdv_", devs(), vec_dts(), 1)
    d : Unit <- for_devs("rdl_", devs(), 2, 12)
    e : Unit <- for_devs("rdg_", devs(), 3, 12)
    f : Unit <- for_devs("rdo_", devs(), 4, 12)
    g : Unit <- for_devs("rdir_", devs(), 5, 12)
    h : Unit <- for_devs("rdiw_", devs(), 6, 12)
    i : Unit <- for_devs_dts("rdx_", devs045(), fp8_dts(), 0)
    j : Unit <- for_legacy(devs(), legacy_dts())
    k : Unit <- for_rb(devs(), rb_addrs())
    l : Unit <- rt_rows()
    m : Unit <- for_ri(ri_devs())
    n : Unit <- wn_rows()
    o : Unit <- for_ops("cfo_", 0, cfo_ops(), 12)
    p : Unit <- for_ops("cfo_", 1, cfo_clang(), 12)
    q : Unit <- for_ops("cfo_", 3, cfo_sin(), 12)
    r : Unit <- for_ops("cfo_", 4, cfo_cuda(), 12)
    s : Unit <- for_ops("cfo_", 5, cfo_hip(), 12)
    t : Unit <- for_cfo_devs("cfo_", cfo_ft(), cfo_add(), 12)
    u : Unit <- for_ops("cfoh_", 4, cfo_cuda(), 10)
    v : Unit <- for_ops("cfof_", 1, cfo_sqrt_trunc(), 13)
    w : Unit <- cfw_all()
    return Unit{}

# ===========================================================================
# FINDING: THE PORT'S `idx_arg_is_add` FIRES WHERE CPYTHON'S `idx.arg == Ops.ADD` CANNOT.
#
# MEASURED, three ways. `render_index`'s non-ALU branch is
#     return f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"
# and CPython tests the WHOLE ARG. `UOp.reduce(arg=Ops.ADD)` sets `arg=(Ops.ADD, 0)` --
# `ops.py:671-674` at HEAD AND at the pin, `if isinstance(arg, Ops): arg = (arg, 0)` -- so the
# index node a real graph builds has `idx.arg == (Ops.ADD, 0)`, and `(Ops.ADD, 0) == Ops.ADD` is
# FALSE. MEASURED in the oracle: `UOp(Ops.REDUCE, src=..., arg=(Ops.ADD, 0))` renders
# `(buf1+(a+b))`; the SAME node with `arg=Ops.ADD` -- which `UOp.reduce` NEVER builds -- renders
# `(buf1+a+b)`.
#
# The port matches on `AReduce{rop, num_axes}` with `is_add(rop) and num_axes == 0`
# (`cstyle.bend:932-935`), and `AReduce{ADD, 0}` is the port's OWN spelling of CPython's
# `(Ops.ADD, 0)` (`ops.bend:7257-7264`). So the port's test is TRUE for the node CPython's test is
# FALSE for, and the two strings differ by the inner parens: the port emits `(buf1+a+b)` where
# CPython emits `(buf1+(a+b))`.
#
# THIS IS A DEFECT AND NOT A CARVE-OUT: the branch is reachable, the difference is visible in a
# kernel's bytes, and it is NOT one of the tree's documented deviations. To match CPython the port
# would have to test for the bare `Op` (its `AOpLit{OpsADD{}}`), which is the shape `Ops.PYLITERAL`
# carries. The fix belongs to the caller; this unit REPORTS and leaves `cstyle.bend` byte-identical.
# ===========================================================================
