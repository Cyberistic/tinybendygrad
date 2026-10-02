"""Generates `main` for tinybendygrad/renderer/cstyle.bend from live CPython.

Every `py=` literal in the gate is produced by CALLING CPython, not by transcribing
what CPython said once. The row LABEL is the same string the Bend row prints, so the
gate's own output and this generator's output are keyed identically and a label that
drifts is a diff rather than a silent skip.
"""

import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))

from tinygrad.helpers import Target, strip_parens
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import Ops, UOp, ParamArg
from tinygrad.renderer.cstyle import (CStyleLanguage, ClangRenderer, OpenCLRenderer,
                                      MetalRenderer, CUDARenderer, HIPRenderer)

def Bare(cls, arch="x86_64", dev="CPU"):
    # `Target`'s positional order is (device, renderer, arch, ..) -- passing the arch
    # FIRST silently sets `arch=""` and every arch-reading row answers for no arch.
    o = cls.__new__(cls)
    o.target = Target(device=dev, arch=arch)
    o.tensor_cores = []
    return o

BASE, CLANG = Bare(CStyleLanguage), Bare(ClangRenderer)
OPENCL, METAL = Bare(OpenCLRenderer, "gfx1100", "AMD"), Bare(MetalRenderer, "12.0", "METAL")
CUDA, HIP = Bare(CUDARenderer, "8.0", "CUDA"), Bare(HIPRenderer, "gfx1100", "AMD")
HIP4 = Bare(HIPRenderer, "gfx950", "AMD")
DEVS = [("BASE", BASE), ("CLANG", CLANG), ("OPENCL", OPENCL), ("METAL", METAL), ("CUDA", CUDA), ("HIP", HIP)]

ROWS = []   # (label, bend_call_prefix, oracle_value)
def row(label, call, val): ROWS.append((label, call, val))

def alu(dt): return UOp.const(1.0, dtypes.float).cast(dt)
def sp(): return UOp(Ops.SPECIAL, (UOp.const(0, dtypes.uint32),), ("g", 0, "gidx0", "g"))
IMG = (32, 32, 4)   # `is_image_shape` is `len(shape)==3 and shape[-1]==4`
KERNEL = ["  float4 val0 = (*((float4*)((data1_4+0))));", "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]

def kbuf(dt, nm, volatile=False):
    return (nm, (UOp(Ops.BUFFER, (), arg=ParamArg(0, dt, size=1, volatile=volatile)), True))
BS = [kbuf(dtypes.float, "data0_4"), kbuf(dtypes.float, "data1_4")]
# AN ALU-SPACE BUFFER ARGUMENT. `buftype` branches on `u.addrspace == ALU` to pick
# `var_prefix`/`var_suffix` INSTEAD of `buffer_suffix`, and a kernel argument is
# never ALU in practice -- so without this fixture the two `var_*` tables are
# ungated, and the mutation table shows `var_prefix: Metal -> const` moving
# NOTHING. The branch is upstream's and this row is what pins it.
def kbuf_alu(nm):
    return (nm, (UOp(Ops.BUFFER, (), arg=ParamArg(0, dtypes.float, size=1, addrspace=AddrSpace.ALU)), True))
ALU = [kbuf_alu("alu0_1"), kbuf_alu("alu1_1")]
# TWO VECTOR-PREFIX LINES, which is what CUDA's and HIP's `render_vector_prefix`
# produce for a half4. They are the LAST clause of both prefixes and no other row
# reaches it, so without this fixture `prefix_clauses`' COUNT is ungated -- and
# `CUDA 5 -> 4` moves NOTHING, which is a blind spot and not a proof.
# THE VECTOR-PREFIX CLAUSE NEEDS A WIDE UOP, not a scalar one: CUDA's filter is
# `count in (4,8) and dt in {half, bfloat16}` (cstyle.py:462) and HIP's is
# `count > 1` (cstyle.py:579), so a scalar half turns on the `#include` line and
# NOT the `vecs` line. `UOp.stack` of four halves is a half4 in ALU space with a
# shape -- which is all `uops_to_dtypes` asks for.
def half4(): return UOp.stack(*[alu(dtypes.half)] * 4)
CUDA_VECS = [CUDA.render_vector_prefix(dtypes.half, 4)]
HIP_VECS = [HIP.render_vector_prefix(dtypes.half, 4)]
BSV = [kbuf(dtypes.float, "data0_4", True), kbuf(dtypes.float, "data1_4")]

def kern2(r, bufs, prefix=None, uops=()):
    r.r = {}
    for nm, (u, _) in bufs: r.r[u] = nm
    return r.render_kernel("E_4", list(KERNEL), bufs, list(uops), prefix=prefix)

# ---------------------------------------------------------------- tmap
for nm, r in DEVS:
    row(f"tmap {nm:<5}", f"tmap_row(\"tmap {nm:<5}\", dev_{nm.lower()}())",
        ",".join(r.type_map.get(dt, dt.name) for dt in dtypes.all))

# ---------------------------------------------------------------- rd
def rd_cells(r, dt):
    return "|".join([r._render_dtype(dt, 1, AddrSpace.GLOBAL, mutable=True),
                     r._render_dtype(dt, 1, AddrSpace.LOCAL, mutable=True),
                     r._render_dtype(dt, 1, AddrSpace.ALU, mutable=True),
                     r._render_dtype(dt, 1, AddrSpace.REG, mutable=True),
                     r._render_dtype(dt, 4, AddrSpace.ALU, mutable=True),
                     r._render_dtype(dt, 2, AddrSpace.REG, mutable=True, override_ptr=True),
                     r._render_dtype(dt, 1, AddrSpace.GLOBAL, mutable=False, shape=IMG)])
DR = {"f32": "single()", "half": "half()", "bf16": "bfloat16()", "bool": "boolean()",
      "u8": "uint8()", "fp8": "fp8e4m3()", "int": "int32()"}
RDR = {"f32": dtypes.float, "half": dtypes.half, "bf16": dtypes.bfloat16, "bool": dtypes.bool,
       "u8": dtypes.uint8, "fp8": dtypes.fp8e4m3, "int": dtypes.int}
RDMAP = dict(DEVS)
for dtag in ["f32", "half", "bf16", "bool", "u8", "fp8", "int"]:
    for nm, r in DEVS:
        row(f"rd {nm:<5} {RDR[dtag].name}", f"rd_row(\"rd {nm:<5}\", dev_{nm.lower()}(), S.{DR[dtag]})",
            rd_cells(r, RDR[dtag]))

# ---------------------------------------------------------------- witem
for nm, r in DEVS:
    def wi(k, n):
        try: return r.code_for_workitem[k](n)
        except KeyError: return ""
    row(f"witem {nm:<5}", f"witem_row(\"witem {nm:<5}\", dev_{nm.lower()}())", f"{wi('g',0)} / {wi('l',0)}")

# ---------------------------------------------------------------- cfo
UNARY = {Ops.SQRT, Ops.RECIPROCAL, Ops.NEG, Ops.EXP2, Ops.LOG2, Ops.SIN, Ops.TRUNC}
def cfo(r, op, dt):
    try:
        if op is Ops.WHERE: return r.code_for_op[op]("X", "Y", "Z", dt)
        if op in UNARY: return r.code_for_op[op]("X", dt)
        return r.code_for_op[op]("X", "Y", dt)
    except KeyError: return ""
DTN = {"f32": (dtypes.float, "single()"), "f16": (dtypes.half, "half()"), "f64": (dtypes.float64, "double()"),
       "bf16": (dtypes.bfloat16, "bfloat16()")}
def cro(op, dtag): return f"cfo_row(\"cfo {0}\""

CFO = [("BASE", BASE, "SQRT", "f32"), ("BASE", BASE, "SQRT", "f16"), ("BASE", BASE, "SQRT", "f64"),
       ("BASE", BASE, "NEG", "f32"), ("BASE", BASE, "RECIPROCAL", "f32"), ("BASE", BASE, "RECIPROCAL", "f16"),
       ("BASE", BASE, "EXP2", "f32"), ("BASE", BASE, "LOG2", "f32"), ("BASE", BASE, "SIN", "f32"),
       ("BASE", BASE, "TRUNC", "f32"), ("BASE", BASE, "ADD", "f32"), ("BASE", BASE, "SUB", "f32"),
       ("BASE", BASE, "MUL", "f32"), ("BASE", BASE, "CDIV", "f32"), ("BASE", BASE, "CMOD", "f32"),
       ("BASE", BASE, "SHR", "f32"), ("BASE", BASE, "SHL", "f32"), ("BASE", BASE, "CMPLT", "f32"),
       ("BASE", BASE, "CMPEQ", "f32"), ("BASE", BASE, "CMPNE", "f32"), ("BASE", BASE, "AND", "f32"),
       ("BASE", BASE, "OR", "f32"), ("BASE", BASE, "XOR", "f32"), ("BASE", BASE, "FDIV", "f32"),
       ("CLANG", CLANG, "SQRT", "f32"), ("CLANG", CLANG, "SQRT", "f16"), ("CLANG", CLANG, "SQRT", "f64"),
       ("CLANG", CLANG, "TRUNC", "f32"), ("CLANG", CLANG, "TRUNC", "f64"), ("CLANG", CLANG, "FDIV", "f32"),
       ("CLANG", CLANG, "EXP2", "f32"), ("CLANG", CLANG, "LOG2", "f32"), ("CLANG", CLANG, "SIN", "f32"),
       ("CLANG", CLANG, "RECIPROCAL", "f32"), ("CLANG", CLANG, "ADD", "f32"),
       ("METAL", METAL, "SIN", "f32"), ("METAL", METAL, "SIN", "f16"), ("METAL", METAL, "SQRT", "f32"),
       ("METAL", METAL, "FDIV", "f32"),
       ("CUDA", CUDA, "SQRT", "f16"), ("CUDA", CUDA, "SQRT", "f32"), ("CUDA", CUDA, "TRUNC", "f16"),
       ("CUDA", CUDA, "TRUNC", "f32"), ("CUDA", CUDA, "SIN", "f16"), ("CUDA", CUDA, "LOG2", "f16"),
       ("CUDA", CUDA, "EXP2", "f16"), ("CUDA", CUDA, "RECIPROCAL", "f16"), ("CUDA", CUDA, "RECIPROCAL", "f32"),
       ("CUDA", CUDA, "SQRT", "f64"), ("CUDA", CUDA, "SQRT", "bf16"), ("CUDA", CUDA, "SIN", "bf16"),
       ("CUDA", CUDA, "TRUNC", "bf16"), ("CUDA", CUDA, "LOG2", "bf16"), ("CUDA", CUDA, "EXP2", "bf16"),
       ("CUDA", CUDA, "RECIPROCAL", "bf16"), ("CUDA", CUDA, "FDIV", "f32"),
       ("HIP", HIP, "SQRT", "f16"), ("HIP", HIP, "SQRT", "f32"), ("HIP", HIP, "SQRT", "f64"),
       ("HIP", HIP, "TRUNC", "f16"), ("HIP", HIP, "SIN", "f32"), ("HIP", HIP, "LOG2", "f32"),
       ("HIP", HIP, "EXP2", "f16"), ("HIP", HIP, "RECIPROCAL", "f32"), ("HIP", HIP, "SQRT", "bf16"),
       ("HIP", HIP, "TRUNC", "bf16"),
       ("OPENCL", OPENCL, "SIN", "f32"), ("OPENCL", OPENCL, "SQRT", "f16")]
for nm, r, op, dtag in CFO:
    dt, call = DTN[dtag]
    row(f"cfo {nm:<5} {op:<10} {dtag}",
        f"cfo_row(\"cfo {nm:<5}\", dev_{nm.lower()}(), O.Ops{op}{{}}, \"{dtag}\", S.{call})", cfo(r, getattr(Ops, op), dt))
for nm, r in [("BASE", BASE), ("CLANG", CLANG)]:
    row(f"cfo {nm:<5} {'WHERE':<10} f32", f"cfo_where_row(\"cfo {nm:<5}\", dev_{nm.lower()}())",
        cfo(r, Ops.WHERE, dtypes.float))

# ---------------------------------------------------------------- kern
for nm, r, lb in [("BASE", BASE, 1), ("CLANG", CLANG, 4), ("OPENCL", OPENCL, 1), ("METAL", METAL, 1),
                  ("CUDA", CUDA, 1), ("CUDA", CUDA, 4), ("HIP", HIP, 1), ("HIP", HIP, 4)]:
    row(f"kern {nm:<5} lb={lb}", f"kern_row(\"kern {nm:<5}\", dev_{nm.lower()}(), {lb})",
        r.kernel_typedef.format(launch_bounds=lb))

# ---------------------------------------------------------------- idx
def const_uop(k): return UOp.const(k, dtypes.int32)
def idx_uop(k): return const_uop(k).cast(dtypes.int)
def add_idx_uop(k):
    # NOTHING in tinygrad builds an INDEX whose `arg is Ops.ADD` (measured: no
    # `.index(..., arg=Ops.ADD)` call site exists), so `render_index`'s
    # `strip_parens` arm is DEAD UPSTREAM and this is a hand-built node -- which is
    # the only way to reach it at all.
    return UOp(Ops.INDEX, (const_uop(0), const_uop(k)), Ops.ADD)
def lane_uop(): return UOp(Ops.INDEX, (const_uop(0), const_uop(0)))

class FakeBuf:
    def __init__(self, a, n): self.addrspace, self._n = a, n
    def max_numel(self): return self._n
def render_index(r, baddr, bnumel, ix, bname="B", iname="R"):
    b = FakeBuf(baddr, bnumel)
    if b.addrspace == AddrSpace.ALU:
        if not (ix.op is Ops.CAST and ix.src[0].op is Ops.CONST): return f"({bname})[{iname}]"
        return bname + (f"[{ix.src[0].val}]" if b.max_numel() > r.gep_arr_threshold else f".{'xyzwabcd'[ix.src[0].val]}")
    return f"({bname}+{strip_parens(iname) if ix.arg == Ops.ADD else iname})"

IDX = [("BASE  sz1 k0 ", "BASE", S_ALU := "alu", 1, "R", "g_cidx(0)"), ("BASE  sz8 k0 ", "BASE", S_ALU, 8, "R", "g_cidx(0)"),
       ("BASE  sz1 k1 ", "BASE", S_ALU, 1, "R", "g_cidx(1)"), ("BASE  sz1 k3 ", "BASE", S_ALU, 1, "R", "g_cidx(3)"),
       ("CLANG sz1 k0 ", "CLANG", S_ALU, 1, "R", "g_cidx(0)"), ("CLANG sz8 k0 ", "CLANG", S_ALU, 8, "R", "g_cidx(0)"),
       ("OPENCLsz1 k0 ", "OPENCL", S_ALU, 1, "R", "g_cidx(0)"), ("OPENCLsz8 k0 ", "OPENCL", S_ALU, 8, "R", "g_cidx(0)"),
       ("CUDA  sz8 k0 ", "CUDA", S_ALU, 8, "R", "g_cidx(0)"), ("CUDA  sz16k0", "CUDA", S_ALU, 16, "R", "g_cidx(0)"),
       ("CUDA  sz8 k1 ", "CUDA", S_ALU, 8, "R", "g_cidx(1)"), ("CUDA  sz8 k3 ", "CUDA", S_ALU, 8, "R", "g_cidx(3)"),
       ("HIP   sz1 k0 ", "HIP", S_ALU, 1, "R", "g_cidx(0)"), ("METAL sz1 k0 ", "METAL", S_ALU, 1, "R", "g_cidx(0)"),
       ("BASE  lane   ", "BASE", S_ALU, 1, "R", "g_lane()"), ("CLANG lane   ", "CLANG", S_ALU, 16, "R", "g_lane()"),
       ("HIP   lane   ", "HIP", S_ALU, 16, "R", "g_lane()"),
       ("BASE  regadd ", "BASE", "reg", 1, "(R)", "g_cadd0()"), ("BASE  regnoad", "BASE", "reg", 1, "(R)", "g_cidx(0)"),
       ("HIP   regadd ", "HIP", "reg", 1, "(R)", "g_cadd0()")]
FIX = {"g_cidx(0)": idx_uop(0), "g_cidx(1)": idx_uop(1), "g_cidx(3)": idx_uop(3),
       "g_cadd0()": add_idx_uop(0), "g_lane()": lane_uop()}
DMAP = dict(DEVS)
for nm, dn, addr, bsz, iname, fx in IDX:
    ac = "S.Aalu{}" if addr == S_ALU else "S.AReg{}"
    row(f"idx {nm}", f"idx_row(\"idx {nm}\", dev_{dn.lower()}(), {ac}, {bsz}, \"{iname}\", {fx})",
        render_index(DMAP[dn], AddrSpace.ALU if addr == S_ALU else AddrSpace.REG, bsz, FIX[fx], iname=iname))

# ---------------------------------------------------------------- type/ptr/cast/leg
row("type BASE  stk4  ", "type_row(\"type BASE  stk4  \", dev_base(), S.single(), 4, S.Aalu{}, O.OpsSTACK{})",
    BASE._render_dtype(dtypes.float, 4, AddrSpace.ALU, override_ptr=False))
row("type BASE  regidx", "type_row(\"type BASE  regidx\", dev_base(), S.single(), 1, S.AReg{}, O.OpsINDEX{})",
    BASE._render_dtype(dtypes.float, 1, AddrSpace.REG, override_ptr=True))
row("type BASE  scalar", "type_row(\"type BASE  scalar\", dev_base(), S.single(), 1, S.Aalu{}, O.OpsCAST{})",
    BASE._render_dtype(dtypes.float, 1, AddrSpace.ALU))
row("type OPENCLglob ", "type_row(\"type OPENCLglob \", dev_opencl(), S.single(), 1, S.AGlobal{}, O.OpsINDEX{})",
    OPENCL._render_dtype(dtypes.float, 1, AddrSpace.GLOBAL, override_ptr=False))
row("type METAL glob ", "type_row(\"type METAL glob \", dev_metal(), S.single(), 1, S.AGlobal{}, O.OpsINDEX{})",
    METAL._render_dtype(dtypes.float, 1, AddrSpace.GLOBAL, override_ptr=False))
row("ptr  BASE  stk4  ", "ptr_row(\"ptr  BASE  stk4  \", dev_base(), S.single(), 4, S.single(), \"S\")",
    f"(({BASE._render_dtype(dtypes.float, 4, AddrSpace.ALU, override_ptr=True)})(S))")
row("ptr  BASE  bitcast", "ptr_row(\"ptr  BASE  bitcast\", dev_base(), S.int32(), 1, S.single(), \"V\")",
    f"(({BASE._render_dtype(dtypes.int, 1, AddrSpace.ALU, override_ptr=True)})(V))")
row("acc  BASE  stk4  ", "acc_row(\"acc  BASE  stk4  \", dev_base(), S.single(), 4, S.single(), \"S\")",
    "*" + f"(({BASE._render_dtype(dtypes.float, 4, AddrSpace.ALU, override_ptr=True)})(S))")
row("acc  BASE  plain ", "acc_row(\"acc  BASE  plain \", dev_base(), S.single(), 1, S.single(), \"V\")", "*V")
row("cast BASE  half  ", "cast_row(\"cast BASE  half  \", dev_base(), S.half())",
    f"({BASE._render_dtype(dtypes.half, 1, AddrSpace.REG)})(V)")
row("cast CLANG half  ", "cast_row(\"cast CLANG half  \", dev_clang(), S.half())",
    f"({CLANG._render_dtype(dtypes.half, 1, AddrSpace.REG)})(V)")
row(f"leg  BASE  {dtypes.float.name}", "legacy_row(\"leg  BASE  \", dev_base(), S.single())", BASE.render_dtype(dtypes.float))
row(f"leg  CLANG {dtypes.half.name}", "legacy_row(\"leg  CLANG \", dev_clang(), S.half())", CLANG.render_dtype(dtypes.half))
row(f"leg  CLANG {dtypes.bool.name}", "legacy_row(\"leg  CLANG \", dev_clang(), S.boolean())", CLANG.render_dtype(dtypes.bool))

# ---------------------------------------------------------------- buf2
def rb_row(r, dt, size, nm, addr=AddrSpace.GLOBAL):
    # `render_buffer` reads `x.addrspace`, and an INDEXED uop gets its address
    # space from `arg.addrspace` (GLOBAL by default) -- not from anything passed
    # alongside it. A fixture that leaves it alone is a GLOBAL buffer wearing a
    # LOCAL label, which is what the gate caught on five rows.
    r.r = {}
    u = UOp(Ops.BUFFER, (), arg=ParamArg(0, dt, size=size, addrspace=addr))
    r.r[u] = nm
    return r.render_buffer(u)
BUF = [("buf2 BASE  LOC   ", "BASE", "ALocal{}", '"L0"', BASE, AddrSpace.LOCAL, "L0"),
       ("buf2 OPENCLLOC   ", "OPENCL", "ALocal{}", '"L0"', OPENCL, AddrSpace.LOCAL, "L0"),
       ("buf2 CUDA  LOC   ", "CUDA", "ALocal{}", '"L0"', CUDA, AddrSpace.LOCAL, "L0"),
       ("buf2 HIP   LOC   ", "HIP", "ALocal{}", '"L0"', HIP, AddrSpace.LOCAL, "L0"),
       ("buf2 METAL LOC   ", "METAL", "ALocal{}", '"L0"', METAL, AddrSpace.LOCAL, "L0"),
       ("buf2 OPENCLGLOB  ", "OPENCL", "AGlobal{}", '"G"', OPENCL, AddrSpace.GLOBAL, "G"),
       ("buf2 CUDA  GLOB  ", "CUDA", "AGlobal{}", '"G"', CUDA, AddrSpace.GLOBAL, "G"),
       ("buf2 METAL GLOB  ", "METAL", "AGlobal{}", '"G"', METAL, AddrSpace.GLOBAL, "G")]
for nm, dn, ac, bnm, r, addr, onm in BUF:
    row(nm, f"buf_row(\"{nm}\", dev_{dn.lower()}(), S.{ac}, {bnm})", rb_row(r, dtypes.float, 1, onm, addr))
row("buf2 HIP   sz16  ", "buf_sz_row(\"buf2 HIP   sz16  \", dev_hip())",
    rb_row(HIP, dtypes.half, 16, "L0", AddrSpace.LOCAL))

# ---------------------------------------------------------------- wmma
def wmma_arg(dims, din): return (tuple(dims), din, 32, ())
def wmma_name_of(dims, din, dout):
    # `Ops.WMMA`'s dtype is `src[0].dtype`, so the srcs carry `dout` -- a uint32
    # src made every row print `unsigned int` for the OUTPUT dtype.
    u = UOp(Ops.WMMA, (UOp.const(0, dout),) * 3, arg=(tuple(dims), din, 32, ()))
    return f"WMMA_{'_'.join(map(str, u.arg[0]))}_{u.arg[1].name}_{u.dtype.name}".replace(" ", "_")
WM = [("wmma 16_16_16 half ", "half()", [16, 16, 16], dtypes.half, dtypes.half),
      ("wmma 16_16_16 i8   ", "int8()", [16, 16, 16], dtypes.int8, dtypes.int8),
      ("wmma 8_8_32   bf16 ", "bfloat16()", [8, 8, 32], dtypes.bfloat16, dtypes.bfloat16),
      ("wmma 16_16_128 fp8 ", "fp8e4m3()", [16, 16, 128], dtypes.fp8e4m3, dtypes.fp8e4m3)]
for nm, dt, dd, di, do in WM:
    row(nm, f"wmma_row(\"{nm}\", wmma_arg({dd}, S.{dt}), S.{dt})", wmma_name_of(dd, di, do))

# ---------------------------------------------------------------- under
for nm, s in [("under float       ", "float"), ("under signed char ", "signed char"),
              ("under unsigned lon", "unsigned long")]:
    row(nm, f"under_row(\"{nm}\", \"{s}\")", s.replace(" ", "_"))

# ---------------------------------------------------------------- img
row("img BASE  write   ", "img_row(\"img BASE  write   \", True{})",
    BASE._render_dtype(dtypes.float, 1, AddrSpace.GLOBAL, mutable=True, shape=IMG))
row("img BASE  read    ", "img_row(\"img BASE  read    \", False{})",
    BASE._render_dtype(dtypes.float, 1, AddrSpace.GLOBAL, mutable=False, shape=IMG))
row("img OPENCLwrite   ", "img_row(\"img OPENCLwrite   \", True{})",
    OPENCL._render_dtype(dtypes.float, 1, AddrSpace.GLOBAL, mutable=True, shape=IMG))

# ---------------------------------------------------------------- buft
def buft_expr(r, dt, addr, nm, volatile=False, mutable=True):
    """upstream's `buftypes` element, evaluated with `r` as `self`."""
    return ("volatile " if volatile else "") + \
      (r.var_prefix if addr is AddrSpace.ALU else "") + \
      r._render_dtype(dt, 1, addr, mutable=mutable) + \
      (r.var_suffix if addr is AddrSpace.ALU else r.buffer_suffix) + " " + nm
for nm, r in DEVS:
    row(f"buft {nm:<5}", f"buft_row(\"buft {nm:<5}\", dev_{nm.lower()}())",
        "|".join([buft_expr(r, dtypes.float, AddrSpace.ALU, "v0"),
                  buft_expr(r, dtypes.float, AddrSpace.ALU, "v0", True),
                  buft_expr(r, dtypes.float, AddrSpace.GLOBAL, "v0"),
                  buft_expr(r, dtypes.float, AddrSpace.GLOBAL, "v0", True),
                  buft_expr(r, dtypes.float, AddrSpace.LOCAL, "v0")]))

# ---------------------------------------------------------------- opt tables
row("opt devname", "opt_row(\"opt devname\", dev_names())", "|".join(n for n, _ in DEVS))
row("opt barrier", "opt_row(\"opt barrier\", barriers())", "|".join(r.barrier for _, r in DEVS))
# FIVE cells, not six: the base's `float4` is `None` and this file's is `""`, and
# that difference is the `TODO(p3)` on the `Ops.STACK` arm, not a bug.
row("opt f4style", "opt_row(\"opt f4style\", f4s())",
    "|".join(f"{r.float4}{r.float4_style[0]}{r.float4_style[1]}" for n, r in DEVS if n != "BASE"))
row("opt infnan", "opt_row(\"opt infnan\", infs())",
    "|".join(f"{r.infinity}/{r.nan}" for _, r in DEVS))

# ---------------------------------------------------------------- hip externs
row("hipockl", "hipockl_row(\"hipockl\")", "\n".join(
    'extern "C" __attribute__((device%s)) %s %s(%s);' % ((", " + a) if a else "", dto, m, dti)
    for m, dti, dto, a in [(f"__ockl_get_{n}", "unsigned int", "size_t", "const")
                           for n in ["local_id", "group_id", "local_size"]]))
OCML_OPS = [("EXP2", "exp2", "pure"), ("LOG2", "log2", "pure"), ("SQRT", "sqrt", "const"),
            ("SIN", "sin", ""), ("TRUNC", "trunc", "")]
row("hipocml", "hipocml_row(\"hipocml\")", "\n".join(
    'extern "C" __attribute__((device%s)) %s __ocml_%s_f%d(%s);' % ((", " + a) if a else "", dt.name, cn, dt.bitsize, dt.name)
    for _, cn, a in OCML_OPS for dt in [dtypes.half, dtypes.float, dtypes.float64]))

# ---------------------------------------------------------------- kern2
SQRT_H, SQRT_F = alu(dtypes.half).alu(Ops.SQRT), alu(dtypes.float).alu(Ops.SQRT)
KERN2 = [
  ("kern2 BASE       ", "kern2_row(\"kern2 BASE       \", dev_base(), 1, g_bs(S.single()), emit_min(), False{})", BASE, BS, (), None),
  ("kern2 CLANG      ", "kern2_row(\"kern2 CLANG      \", dev_clang(), 1, g_bs(S.single()), emit_min(), False{})", CLANG, BS, (), None),
  ("kern2 OPENCL     ", "kern2_row(\"kern2 OPENCL     \", dev_opencl(), 1, g_bs(S.single()), emit_min(), False{})", OPENCL, BS, (), None),
  ("kern2 HIP        ", "kern2_row(\"kern2 HIP        \", dev_hip(), 1, g_bs(S.single()), emit_min(), False{})", HIP, BS, (), None),
  ("kern2 METAL      ", "kern2_row(\"kern2 METAL      \", dev_metal(), 1, g_bs(S.single()), emit_min(), False{})", METAL, BS, (), None),
  # THE PREFIX BRANCH: None vs [] vs a two-line prefix are THREE kernels.
  ("kern2 BASE  pref2", "kern2_row(\"kern2 BASE  pref2\", dev_base(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})", BASE, BS, (), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  ("kern2 BASE  pref0", "kern2_row(\"kern2 BASE  pref0\", dev_base(), 1, g_bs(S.single()), emit_prefixed(), False{})", BASE, BS, (), []),
  ("kern2 OPENCL pref2", "kern2_row(\"kern2 OPENCL pref2\", dev_opencl(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})", OPENCL, BS, (), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  # CUDA, HIP and Metal ASSIGN `prefix`, so the caller's lines are DROPPED. Three
  # rows, because three devices dropping it is a fact and not one fact.
  ("kern2 CUDA  pref2", "kern2_row(\"kern2 CUDA  pref2\", dev_cuda(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})", CUDA, BS, (), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  ("kern2 HIP   pref2", "kern2_row(\"kern2 HIP   pref2\", dev_hip(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})", HIP, BS, (), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  ("kern2 METAL pref2", "kern2_row(\"kern2 METAL pref2\", dev_metal(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})", METAL, BS, (), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  # OpenCL's `#pragma` PREPENDS onto the caller's list and is conditional on a half
  # uop -- so it is a third row and not a fourth spelling of the second.
  ("kern2 OPENCL f16 ", "kern2_row(\"kern2 OPENCL f16 \", dev_opencl(), 1, g_bs(S.single()), emit_ocl_half(g_caller()), False{})", OPENCL, BS, (sp(), alu(dtypes.half)), ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]),
  # `buftype`'s `volatile` half.
  ("kern2 BASE  vol  ", "kern2_row(\"kern2 BASE  vol  \", dev_base(), 1, g_bs_vol(), emit_min(), False{})", BASE, BSV, (), None),
  ("kern2 CLANG vol  ", "kern2_row(\"kern2 CLANG vol  \", dev_clang(), 1, g_bs_vol(), emit_min(), False{})", CLANG, BSV, (), None),
  # HIP's prefix, clause by clause.
  ("kern2 HIP   spec ", "kern2_row(\"kern2 HIP   spec \", dev_hip(), 1, g_bs(S.single()), emit_hip_spec(), False{})", HIP, BS, (sp(),), None),
  ("kern2 HIP   ockl ", "kern2_row(\"kern2 HIP   ockl \", dev_hip(), 1, g_bs(S.single()), emit_hip_ocml(), False{})", HIP, BS, (sp(), SQRT_H, SQRT_F), None),
  ("kern2 HIP   half ", "kern2_row(\"kern2 HIP   half \", dev_hip(), 1, g_bs(S.single()), emit_hip_half(), False{})", HIP, BS, (sp(), alu(dtypes.half)), None),
  ("kern2 HIP   bf16 ", "kern2_row(\"kern2 HIP   bf16 \", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16(), False{})", HIP, BS, (sp(), alu(dtypes.bfloat16)), None),
  ("kern2 HIP   bf16h ", "kern2_row(\"kern2 HIP   bf16h \", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16_half(), False{})", HIP, BS, (sp(), alu(dtypes.bfloat16), alu(dtypes.half)), None),
  ("kern2 HIP   cdna4", "kern2_row(\"kern2 HIP   cdna4\", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16(), True{})", HIP4, BS, (sp(), alu(dtypes.bfloat16)), None),
  ("kern2 HIP   inf  ", "kern2_row(\"kern2 HIP   inf  \", dev_hip(), 1, g_bs(S.single()), emit_hip_inf(), False{})", HIP, BS, (sp(), UOp.const(float("nan"), dtypes.float).cast(dtypes.float)), None),
  # CUDA's prefix: four static lines then one `#include` per used dtype.
  ("kern2 CUDA  half ", "kern2_row(\"kern2 CUDA  half \", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(True{}, False{}, False{}, False{}, False{}, False{})), False{})", CUDA, BS, (alu(dtypes.half),), None),
  ("kern2 CUDA  bf16 ", "kern2_row(\"kern2 CUDA  bf16 \", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(False{}, True{}, False{}, False{}, False{}, False{})), False{})", CUDA, BS, (alu(dtypes.bfloat16),), None),
  ("kern2 CUDA  fp8  ", "kern2_row(\"kern2 CUDA  fp8  \", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(False{}, False{}, True{}, False{}, False{}, False{})), False{})", CUDA, BS, (alu(dtypes.fp8e4m3),), None),
  ("kern2 BASE  alu  ", "kern2_row(\"kern2 BASE  alu  \", dev_base(), 1, g_bs_alu(), emit_min(), False{})", BASE, ALU, (), None),
  ("kern2 CLANG alu  ", "kern2_row(\"kern2 CLANG alu  \", dev_clang(), 1, g_bs_alu(), emit_min(), False{})", CLANG, ALU, (), None),
  ("kern2 METAL alu  ", "kern2_row(\"kern2 METAL alu  \", dev_metal(), 1, g_bs_alu(), emit_min(), False{})", METAL, ALU, (), None),
  ("kern2 CUDA  vecs ", "kern2_row(\"kern2 CUDA  vecs \", dev_cuda(), 1, g_bs(S.single()), emit_vecs(g_cuda_vecs()), False{})", CUDA, BS, (half4(),), None),
  ("kern2 HIP   vecs ", "kern2_row(\"kern2 HIP   vecs \", dev_hip(), 1, g_bs(S.single()), emit_hip_vecs(g_hip_vecs()), False{})", HIP, BS, (sp(), half4()), None),
  ("kern2 CUDA  all  ", "kern2_row(\"kern2 CUDA  all  \", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(True{}, True{}, True{}, False{}, False{}, False{})), False{})", CUDA, BS, (alu(dtypes.half), alu(dtypes.bfloat16), alu(dtypes.fp8e4m3)), None),
]
for nm, call, r, bufs, uops, pref in KERN2:
    row(nm, call, kern2(r, bufs, prefix=pref, uops=uops))

# ---------------------------------------------------------------- emit
def lit(v):
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "main_rows.txt"), "w") as fh:
    for nm, call, v in ROWS:
        fh.write(f"{nm}\t{call}\t{lit(v)}\n")
print(f"{len(ROWS)} rows")
for nm, call, v in ROWS:
    print("%s = [%s]" % (nm, str(v).replace("\n", "\\n")))