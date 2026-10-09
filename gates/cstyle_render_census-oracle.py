#!/usr/bin/env python3
"""cstyle_render_census-oracle.py -- CPython's RENDERED STRINGS for the cstyle census.

    .venv/bin/python gates/cstyle_render_census-oracle.py

A THIRD KIND OF INSTRUMENT. `gates/*_graph_census-*.py` compare OP SEQUENCES (a graph) and
`gates/fold_graph_census-gate.py` compares VALUES (a dtype, a shape, a pair of bounds). A
RENDERER produces NEITHER: it produces a STRING. So this lane builds the SAME UOp the Bend
lane builds and asks the REAL CPython renderer -- `renderer._render_dtype`, `render_type`,
`render_ptr`, `render_access`, `render_cast`, `render_index`, `render_buffer`, `render_dtype`
(LEGACY), `_wmma_name` -- to render it. It never reimplements the renderer: an oracle that
reimplements the thing it checks agrees with itself.

THE POPULATION IS DISCOVERED, NOT LISTED. `gates/cstyle_render_census.bend`'s header states the
rule; the short form is: a name is a ROW iff `tinygrad/renderer/cstyle.py` defines a method or
function of that name (leading underscores stripped) AND the port's def emits a String (or a
value) from a UOp. EIGHT names survive:

    render_dtype    <- `_render_dtype` (the workhorse) AND the LEGACY `render_dtype`
    render_type render_ptr render_access render_cast render_index render_buffer
    wmma_name       <- `_wmma_name`

`render_kernel` and `uops_to_dtypes` are CPython methods/functions the port DOES NOT define
(both are the fold wall, `cstyle.bend`'s TODO(p3)s), so they fall out. `render_vector_prefix`,
`_render`, `render`, `__getitem__`, `supported_dtypes`, `__init__`, `asm`, `is_cdna*`,
`wmma_args`, `fp8_index`, `_ocml`, `create_non_native_float_pats`, `cast_float_to_bf16` have no
port def either. The renderer's DISPATCH and OPTION TABLES (`code_for_op`, `code_for_workitem`,
`type_map`, `kernel_typedef`, ...) are CPython CLASS ATTRIBUTES, not methods, so they are not
names in the population -- the census reaches them THROUGH the eight functions and, for the ones
no ported function reads, drives the port's own table def directly. Those rows are marked `opt_`
and `cfo_`/`cfw_` below.

WHAT THE FIXTURE VARIES, and why all four are load-bearing (the file's `_render_dtype` reads
all four): the DEVICE (six type_maps, six prefix sets), the DTYPE (eighteen names, four of them
UNMAPPED on some devices), the ADDRSPACE/SIZE (the `*`, the local/global prefix, the `sz>1`
suffix), and the OP/ARG (the ALU dispatch and the index arms).

THE VENDORED `tinygrad/` HAS DRIFTED PAST THE PIN THE PORT TARGETS (`ad117c928^`). Two measured
consequences, and they are the census's whole reason to exist:

  * HEAD `_render_dtype` uses `self.type_map[dtype]` and RAISES KeyError for an unmapped dtype;
    the port prints the dtype's own name (`tm_get`'s default), which is the PIN's
    `.get(dtype, dtype.name)`. So every `rdx_` row is a declared divergence: `KeyError` here,
    the name there. `gates/cstyle_render_census-gate.py` pins each one.
  * HEAD `_wmma_name` no longer `.replace(" ", "_")`; the port still does. It is a NO-OP at
    HEAD because `DType.name` moved to the rust spellings (`i8`, not `signed char`), which the
    `wn_` rows confirm rather than assume.

AND ONE DEFECT THE CENSUS FOUND, `ri_add_*`. `render_index`'s non-ALU branch tests
`idx.arg == Ops.ADD`, and `UOp.reduce(arg=Ops.ADD)` sets `arg=(Ops.ADD, 0)` (`ops.py:671-674`, at
HEAD and at the pin), so CPython's test is FALSE and it emits `(buf1+(a+b))`. The port's
`idx_arg_is_add` matches `AReduce{ADD, 0}` -- its own spelling of `(Ops.ADD, 0)` -- so it strips
and emits `(buf1+a+b)`. The fixture here is the REACHABLE `arg=(Ops.ADD, 0)`; `arg=Ops.ADD` (which
`UOp.reduce` never builds) would have hidden the difference.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/cstyle_render_census-oracle.py
"""
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.renderer.cstyle import (CStyleLanguage, ClangRenderer, OpenCLRenderer,
                                      MetalRenderer, CUDARenderer, HIPRenderer, _wmma_name)
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops, ParamArg

OUT = []
def row(name, value):
    OUT.append(f"{name}={value}")

# ---- the fixture tables ----------------------------------------------------
# 18 dtypes, indexed so the two lanes agree on an integer key. 0..13 are the fourteen in
# CStyleLanguage.type_map (mapped on EVERY device); 14..17 are the fp8 group, which is mapped
# on some devices and NOT on others -- the `rdx_` rows.
DTS = [dtypes.void, dtypes.bool, dtypes.int8, dtypes.uint8, dtypes.int16, dtypes.uint16,
       dtypes.int32, dtypes.uint32, dtypes.int64, dtypes.uint64, dtypes.half, dtypes.bfloat16,
       dtypes.float, dtypes.double, dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.fp8e4m3fnuz,
       dtypes.fp8e5m2fnuz]
DEVS = [CStyleLanguage, ClangRenderer, OpenCLRenderer, MetalRenderer, CUDARenderer, HIPRenderer]
R = [object.__new__(c) for c in DEVS]          # the methods under test read only class attrs + self.r
for x in R: x.r = {}


def safe(fn):
    """`fn()`, or the EXCEPTION CLASS NAME. An unmapped dtype is a KeyError in HEAD's renderer,
    and a KeyError is a MEASUREMENT (the port answers the name instead), not a crash."""
    try:
        return fn()
    except Exception as e:
        return type(e).__name__


# `_render_dtype(dtype, sz, addrspace, mutable, override_ptr, shape)`. The port's seventh
# argument is `is_image_shape(shape)` already computed, so `img` maps to a real image shape.
def rd(dev, dti, sz, addr, mut, ovr, img):
    shape = (2, 3, 4) if img else None
    return safe(lambda: R[dev]._render_dtype(DTS[dti], sz, addr, mut, ovr, shape))


# ---- opt_ -- the OPTION TABLES (CPython class attributes) ------------------
# 15 keys, one row per device. `kernel_typedef` is `str.format(launch_bounds=..)`; `float4` is
# `str|None` and the base's None prints as "None" where the port prints "" (declared divergence).
OPT_KEYS = ("ktypedef", "bufpre", "bufsuf", "smempre", "smemalign", "varpre", "varsuf",
            "barrier", "float4", "f4open", "f4close", "gep", "inf", "nan", "smemcast")


def opt(dev, key):
    r = R[dev]
    if key == "ktypedef": return r.kernel_typedef.format(launch_bounds=4)
    if key == "bufpre": return r.buffer_prefix
    if key == "bufsuf": return r.buffer_suffix
    if key == "smempre": return r.smem_prefix
    if key == "smemalign": return r.smem_align
    if key == "varpre": return r.var_prefix
    if key == "varsuf": return r.var_suffix
    if key == "barrier": return r.barrier
    if key == "float4": return str(r.float4)
    if key == "f4open": return r.float4_style[0]
    if key == "f4close": return r.float4_style[1]
    if key == "gep": return str(r.gep_arr_threshold)
    if key == "inf": return r.infinity
    if key == "nan": return r.nan
    if key == "smemcast": return "1" if r.smem_prefix_for_cast else "0"
    raise KeyError(key)


# ---- code_for_op / code_for_workitem -- the DISPATCH TABLES ----------------
# (op, arity). Unary / binary / ternary, exactly the three shapes `code_for_op` stores.
OPS = [("sqrt", Ops.SQRT, 1), ("reciprocal", Ops.RECIPROCAL, 1), ("neg", Ops.NEG, 1),
       ("exp2", Ops.EXP2, 1), ("log2", Ops.LOG2, 1), ("sin", Ops.SIN, 1), ("trunc", Ops.TRUNC, 1),
       ("and", Ops.AND, 2), ("xor", Ops.XOR, 2), ("or", Ops.OR, 2), ("add", Ops.ADD, 2),
       ("sub", Ops.SUB, 2), ("mul", Ops.MUL, 2), ("cmod", Ops.CMOD, 2), ("cdiv", Ops.CDIV, 2),
       ("cmpne", Ops.CMPNE, 2), ("shr", Ops.SHR, 2), ("shl", Ops.SHL, 2), ("cmplt", Ops.CMPLT, 2),
       ("where", Ops.WHERE, 3), ("cmpeq", Ops.CMPEQ, 2), ("fdiv", Ops.FDIV, 2)]
ARITY = {n: a for n, _, a in OPS}
OPOBJ = {n: o for n, o, _ in OPS}
XS = ["a", "b", "c"]


def cfo(dev, opname, dtype):
    n = ARITY[opname]
    return safe(lambda: R[dev].code_for_op[OPOBJ[opname]](*XS[:n], dtype))


# ---- render_index / render_buffer / render_ptr / ... UOp fixtures ----------
# The port's `render_index` reads a real arena; this lane builds the equivalent real UOp and
# asks the real method. `r.r` is CPython's `self[key]` map, which the port takes as the
# `bname`/`iname` arguments.
def build():
    fx = {}
    # a scalar ALU alloc (render_type/render_ptr/render_access/render_cast)
    a = UOp.alloc((), dtypes.float, slot=0, addrspace=AddrSpace.ALU)
    R[0].r = {a: "alu0"}
    fx["scalar"] = (a, "alu0")
    # a vector ALU alloc: max_numel 4, so render_ptr's `>1` arm and render_type's `float4`
    v = UOp.alloc((4,), dtypes.float, slot=0, addrspace=AddrSpace.ALU)
    fx["vec"] = (v, "alu0")
    # a REG INDEX: render_type's `op is INDEX and addrspace is REG` -> override_ptr
    rb = UOp.alloc((4,), dtypes.float, slot=1, addrspace=AddrSpace.REG)
    ri = UOp(Ops.INDEX, src=(rb, UOp(Ops.CONST, arg=0)))
    fx["idx_reg"] = (ri, "bidx0")
    # a CAST whose src[0] dtype differs: render_ptr's `d != src[0].dtype` arm
    cast = UOp(Ops.CAST, src=(UOp(Ops.CONST, arg=3),), arg=dtypes.float)
    fx["cast"] = (cast, "cast0")
    # render_buffer: a LOCAL buffer
    buf = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float, size=4, addrspace=AddrSpace.LOCAL))
    fx["buffer"] = (buf, "buf0")
    # render_index arms
    ab4 = UOp.alloc((4,), dtypes.float, slot=2, addrspace=AddrSpace.ALU)
    ab8 = UOp.alloc((8,), dtypes.float, slot=3, addrspace=AddrSpace.ALU)
    gb = UOp.alloc((4,), dtypes.float, slot=4, addrspace=AddrSpace.GLOBAL)
    laneidx = UOp(Ops.CONST, arg=7)
    castc = UOp(Ops.CAST, src=(UOp(Ops.CONST, arg=0),), arg=dtypes.int32)
    redadd = UOp(Ops.REDUCE, src=(UOp(Ops.CONST, arg=1),), arg=(Ops.ADD, 0))
    fx["lane"] = (UOp(Ops.INDEX, src=(ab4, laneidx)), ab4, laneidx, "bidx1")
    fx["array"] = (UOp(Ops.INDEX, src=(ab8, castc)), ab8, castc, "bidx2")
    fx["swizzle"] = (UOp(Ops.INDEX, src=(ab4, castc)), ab4, castc, "bidx3")
    fx["add"] = (UOp(Ops.INDEX, src=(gb, redadd)), gb, redadd, "bidx4")
    fx["plain"] = (UOp(Ops.INDEX, src=(gb, laneidx)), gb, laneidx, "bidx5")
    fx["_r"] = {ab4: "alu1", ab8: "alu2", gb: "buf1", laneidx: "alu3", castc: "cast1",
                redadd: "(a+b)"}
    return fx


FX = build()
R[0].r = FX["_r"]
# device 1 has gep_arr_threshold 0 and device 4 has 8: the array/swizzle split moves.
R[1].r = FX["_r"]
R[4].r = FX["_r"]


def wmma(dims, dti_in, dti_out):
    a = UOp(Ops.CONST, arg=1)
    b = UOp(Ops.CONST, arg=1)
    out = UOp(Ops.CAST, src=(UOp(Ops.CONST, arg=2.0),), arg=DTS[dti_out])
    return _wmma_name(UOp(Ops.WMMA, src=(a, b, out), arg=(dims, DTS[dti_in])))


# ---- the row sequence, IN THE PORT'S OWN ORDER -----------------------------
def main():
    # opt_ -- 15 x 6
    for key in OPT_KEYS:
        for dev in range(6):
            row(f"opt_{key}_{dev}", opt(dev, key))
    # rd_ scalar -- 6 x 14
    for dev in range(6):
        for dti in range(14):
            row(f"rd_{dev}_{dti}", rd(dev, dti, 1, AddrSpace.ALU, True, False, False))
    # rdv_ vector -- 6 x 3 (the sz>1 suffix)
    for dev in range(6):
        for dti in (2, 12, 13):
            row(f"rdv_{dev}_{dti}", rd(dev, dti, 4, AddrSpace.ALU, True, False, False))
    # the address-space / pointer / image arms, dtype f32 (12)
    for dev in range(6):
        row(f"rdl_{dev}", rd(dev, 12, 1, AddrSpace.LOCAL, True, False, False))
    for dev in range(6):
        row(f"rdg_{dev}", rd(dev, 12, 1, AddrSpace.GLOBAL, True, False, False))
    for dev in range(6):
        row(f"rdo_{dev}", rd(dev, 12, 1, AddrSpace.REG, True, True, False))
    for dev in range(6):
        row(f"rdir_{dev}", rd(dev, 12, 1, AddrSpace.ALU, False, False, True))
    for dev in range(6):
        row(f"rdiw_{dev}", rd(dev, 12, 1, AddrSpace.ALU, True, False, True))
    # rdx_ -- the UNMAPPED dtypes, the declared KeyError divergences
    for dev in (0, 4, 5):
        for dti in (14, 15, 16, 17):
            row(f"rdx_{dev}_{dti}", rd(dev, dti, 1, AddrSpace.ALU, True, False, False))
    # legacy render_dtype -- 6 x 2
    for dev in range(6):
        for dti in (2, 12):
            row(f"rdl2_{dev}_{dti}", safe(lambda: R[dev].render_dtype(DTS[dti])))
    # render_buffer -- 6 x 3 address spaces
    for dev in range(6):
        for tag, addr in (("alu", AddrSpace.ALU), ("local", AddrSpace.LOCAL),
                          ("global", AddrSpace.GLOBAL)):
            b = UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float, size=4, addrspace=addr))
            R[dev].r = {b: "buf0"}
            row(f"rb_{dev}_{tag}", safe(lambda: R[dev].render_buffer(b)))
    R[0].r = FX["_r"]
    # the pointer / cast vocabulary
    a, an = FX["scalar"]
    R[0].r = {a: an}
    row("rt_scalar", safe(lambda: R[0].render_type(a)))
    row("rp_scalar", safe(lambda: R[0].render_ptr(a)))
    row("ra_scalar", safe(lambda: R[0].render_access(a)))
    row("rc_scalar", safe(lambda: R[0].render_cast(a, an)))
    v, vn = FX["vec"]
    R[0].r = {v: vn}
    row("rt_vec", safe(lambda: R[0].render_type(v)))
    row("rp_vec", safe(lambda: R[0].render_ptr(v)))
    row("ra_vec", safe(lambda: R[0].render_access(v)))
    i, inn = FX["idx_reg"]
    R[0].r = {i: inn, i.src[0]: "alu1"}
    row("rt_idx_reg", safe(lambda: R[0].render_type(i)))
    c, cn = FX["cast"]
    R[0].r = {c: cn}
    row("rp_cast", safe(lambda: R[0].render_ptr(c)))
    row("ra_cast", safe(lambda: R[0].render_access(c)))
    # render_index arms
    for dev in (0, 1, 4):
        R[dev].r = FX["_r"]
        for tag in ("lane", "array", "swizzle", "add", "plain"):
            x, buf, idx, xn = FX[tag]
            row(f"ri_{tag}_{dev}", safe(lambda: R[dev].render_index(x, buf, idx)))
    # wmma_name
    row("wn_a", wmma((16, 16, 16), 2, 12))
    row("wn_b", wmma((16, 8, 32), 10, 10))
    row("wn_c", wmma((16, 16, 128), 14, 12))
    # cfo_ -- the ALU dispatch table
    for n, _, _ in OPS:
        row(f"cfo_0_{n}", cfo(0, n, dtypes.float))
    for n in ("sqrt", "trunc", "fdiv", "exp2", "sin", "log2", "reciprocal"):
        row(f"cfo_1_{n}", cfo(1, n, dtypes.float))
    row("cfo_3_sin", cfo(3, "sin", dtypes.float))
    for n in ("trunc", "sin", "log2", "exp2", "sqrt", "reciprocal"):
        row(f"cfo_4_{n}", cfo(4, n, dtypes.float))
    for n in ("trunc", "sin", "log2", "exp2", "sqrt"):
        row(f"cfo_5_{n}", cfo(5, n, dtypes.float))
    for dev in (1, 2, 3, 4, 5):
        row(f"cfo_{dev}_add", cfo(dev, "add", dtypes.float))
    for n in ("trunc", "sin", "log2", "exp2", "sqrt", "reciprocal"):
        row(f"cfoh_4_{n}", cfo(4, n, dtypes.half))
    for n in ("sqrt", "trunc"):
        row(f"cfof_1_{n}", cfo(1, n, dtypes.double))
    # cfw_ -- the workitem dispatch table
    for dev in range(6):
        for k in ("g", "l"):
            row(f"cfw_{dev}_{k}", safe(lambda: R[dev].code_for_workitem[k]("1")))
    print("\n".join(OUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
