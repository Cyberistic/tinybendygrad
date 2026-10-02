"""CPython oracle for tinybendygrad/renderer/cstyle.bend.

Emits ONE `name = [value]` line per gate row on stdout, keyed by the ROW NAME,
so the Bend gate's own output diffs against this line-for-line.

THE RENDERERS ARE BUILT WITH `__new__`, NOT CONSTRUCTED. A real
`ClangRenderer(Target(...))` runs `ClangCompiler` and a real `HIPRenderer` runs
`comgr`; these rows are about STRING GENERATION and the oracle must not need a
toolchain. `Bare` sets `target` by hand, which is all any row here reads.
"""

import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))

from tinygrad.helpers import Target, strip_parens
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import Ops, UOp, ParamArg
from tinygrad.renderer.cstyle import (CStyleLanguage, ClangRenderer, OpenCLRenderer,
                                      MetalRenderer, CUDARenderer, HIPRenderer)

ROWS = []
def row(name, val): ROWS.append((name, val))

def Bare(cls, arch="x86_64", dev="CPU"):
    # `Target`'s positional order is (device, renderer, arch, ..) -- passing the
    # arch FIRST silently sets `arch=""` and every arch-reading row answers for
    # no architecture at all.
    o = cls.__new__(cls)
    o.target = Target(device=dev, arch=arch)
    o.tensor_cores = []
    return o

BASE = Bare(CStyleLanguage)
CLANG = Bare(ClangRenderer)
OPENCL = Bare(OpenCLRenderer, "gfx1100", "AMD")
METAL = Bare(MetalRenderer, "12.0", "METAL")
CUDA = Bare(CUDARenderer, "8.0", "CUDA")
HIP = Bare(HIPRenderer, "gfx1100", "AMD")
DEVS = [("BASE", BASE), ("CLANG", CLANG), ("OPENCL", OPENCL), ("METAL", METAL), ("CUDA", CUDA), ("HIP", HIP)]

# ---- tmap. `type_map.get(dtype, dtype.name)` over dtype.py's own order.
for nm, r in DEVS:
    row(f"tmap {nm:<5}", ",".join(r.type_map.get(dt, dt.name) for dt in dtypes.all))

# ---- rd. Seven `_render_dtype` columns: GLOBAL|LOCAL|ALU|REG|sz4|ovrptr|image.
IMG = (32, 32, 4)   # `is_image_shape` is `len(shape)==3 and shape[-1]==4`
def rd_cells(r, dt):
    return "|".join([
        r._render_dtype(dt, 1, AddrSpace.GLOBAL, mutable=True),
        r._render_dtype(dt, 1, AddrSpace.LOCAL, mutable=True),
        r._render_dtype(dt, 1, AddrSpace.ALU, mutable=True),
        r._render_dtype(dt, 1, AddrSpace.REG, mutable=True),
        r._render_dtype(dt, 4, AddrSpace.ALU, mutable=True),
        r._render_dtype(dt, 2, AddrSpace.REG, mutable=True, override_ptr=True),
        r._render_dtype(dt, 1, AddrSpace.GLOBAL, mutable=False, shape=IMG),
    ])

RD = [("BASE", BASE, dtypes.f32), ("CLANG", CLANG, dtypes.f32), ("OPENCL", OPENCL, dtypes.f32),
      ("CUDA", CUDA, dtypes.f32), ("HIP", HIP, dtypes.f32), ("METAL", METAL, dtypes.f32),
      ("BASE", BASE, dtypes.f16), ("CLANG", CLANG, dtypes.f16), ("OPENCL", OPENCL, dtypes.f16),
      ("METAL", METAL, dtypes.f16),
      ("BASE", BASE, dtypes.bf16), ("OPENCL", OPENCL, dtypes.bf16), ("CUDA", CUDA, dtypes.bf16),
      ("HIP", HIP, dtypes.bf16), ("METAL", METAL, dtypes.bf16),
      ("BASE", BASE, dtypes.bool), ("CLANG", CLANG, dtypes.bool),
      ("BASE", BASE, dtypes.u8), ("CLANG", CLANG, dtypes.u8), ("OPENCL", OPENCL, dtypes.u8),
      ("BASE", BASE, dtypes.fp8e4m3), ("CUDA", CUDA, dtypes.fp8e4m3), ("HIP", HIP, dtypes.fp8e4m3),
      ("BASE", BASE, dtypes.i32), ("METAL", METAL, dtypes.i32)]
# The DTYPE is part of the row NAME, not only of the row's value, and that is not
# cosmetic: `rd BASE ` is emitted seven times (once per dtype) and `cfo BASE ` twenty
# times, so a name-keyed dict kept ONE of each and silently discarded the other 99.
# A gate that drops rows it cannot key is a gate reporting a smaller run than it did.
for nm, r, dt in RD:
    row(f"rd {nm:<5} {dt.name}", rd_cells(r, dt))

# ---- witem. The base dict is EMPTY, so upstream is a KeyError and the port's
# marker is the empty string.
for nm, r in DEVS:
    def wi(k, n):
        try: return r.code_for_workitem[k](n)
        except KeyError: return ""
    row(f"witem {nm:<5}", f"{wi('g',0)} / {wi('l',0)}")

def alu(dt): return UOp.const(1.0, dtypes.f32).cast(dt)
# ONE GLOBAL SPECIAL, which is what switches HIP's `size_t` and the three
# `__ockl_*` externs on -- that test is `any(u.op is Ops.SPECIAL)`, not the axis
# letter (cstyle.py:561). GLOBAL rather than local on purpose: a LOCAL special
# also enters `local_dims` and so moves `launch_bounds` to `prod([vmax])`, which
# makes the row about the `TODO(p3) launch_bounds` wall instead of about the
# prefix. Its dtype passes through `src[0]`, so the src is not optional.
def sp(): return UOp(Ops.SPECIAL, (UOp.const(0, dtypes.u32),), ("g", 0, "gidx0", "g"))

# ---- cfo. `code_for_op` per device. Arity is data, not a convention: WHERE is
# the only ternary and the seven listed ops are the only unary.
UNARY = {Ops.SQRT, Ops.RECIPROCAL, Ops.NEG, Ops.EXP2, Ops.LOG2, Ops.SIN, Ops.TRUNC}
def cfo(r, op, dt):
    try:
        if op is Ops.WHERE: return r.code_for_op[op]("X", "Y", "Z", dt)
        if op in UNARY: return r.code_for_op[op]("X", dt)
        return r.code_for_op[op]("X", "Y", dt)
    except KeyError: return ""

CFO = [("BASE", BASE, Ops.SQRT, dtypes.f32), ("BASE", BASE, Ops.SQRT, dtypes.f16),
       ("BASE", BASE, Ops.SQRT, dtypes.f64), ("BASE", BASE, Ops.NEG, dtypes.f32),
       ("BASE", BASE, Ops.RECIPROCAL, dtypes.f32), ("BASE", BASE, Ops.RECIPROCAL, dtypes.f16),
       ("BASE", BASE, Ops.EXP2, dtypes.f32), ("BASE", BASE, Ops.LOG2, dtypes.f32),
       ("BASE", BASE, Ops.SIN, dtypes.f32), ("BASE", BASE, Ops.TRUNC, dtypes.f32),
       ("BASE", BASE, Ops.ADD, dtypes.f32), ("BASE", BASE, Ops.SUB, dtypes.f32),
       ("BASE", BASE, Ops.MUL, dtypes.f32), ("BASE", BASE, Ops.CDIV, dtypes.f32),
       ("BASE", BASE, Ops.CMOD, dtypes.f32), ("BASE", BASE, Ops.SHR, dtypes.f32),
       ("BASE", BASE, Ops.SHL, dtypes.f32), ("BASE", BASE, Ops.CMPLT, dtypes.f32),
       ("BASE", BASE, Ops.CMPEQ, dtypes.f32), ("BASE", BASE, Ops.CMPNE, dtypes.f32),
       ("BASE", BASE, Ops.AND, dtypes.f32), ("BASE", BASE, Ops.OR, dtypes.f32),
       ("BASE", BASE, Ops.XOR, dtypes.f32),
       ("CLANG", CLANG, Ops.SQRT, dtypes.f32), ("CLANG", CLANG, Ops.SQRT, dtypes.f16),
       ("CLANG", CLANG, Ops.SQRT, dtypes.f64), ("CLANG", CLANG, Ops.TRUNC, dtypes.f32),
       ("CLANG", CLANG, Ops.TRUNC, dtypes.f64), ("CLANG", CLANG, Ops.FDIV, dtypes.f32),
       ("CLANG", CLANG, Ops.EXP2, dtypes.f32), ("CLANG", CLANG, Ops.LOG2, dtypes.f32),
       ("CLANG", CLANG, Ops.SIN, dtypes.f32), ("CLANG", CLANG, Ops.RECIPROCAL, dtypes.f32),
       ("CLANG", CLANG, Ops.ADD, dtypes.f32),
       ("METAL", METAL, Ops.SIN, dtypes.f32), ("METAL", METAL, Ops.SIN, dtypes.f16),
       ("METAL", METAL, Ops.SQRT, dtypes.f32),
       ("CUDA", CUDA, Ops.SQRT, dtypes.f16), ("CUDA", CUDA, Ops.SQRT, dtypes.f32),
       ("CUDA", CUDA, Ops.TRUNC, dtypes.f16), ("CUDA", CUDA, Ops.TRUNC, dtypes.f32),
       ("CUDA", CUDA, Ops.SIN, dtypes.f16), ("CUDA", CUDA, Ops.LOG2, dtypes.f16),
       ("CUDA", CUDA, Ops.EXP2, dtypes.f16), ("CUDA", CUDA, Ops.RECIPROCAL, dtypes.f16),
       ("CUDA", CUDA, Ops.RECIPROCAL, dtypes.f32), ("CUDA", CUDA, Ops.SQRT, dtypes.f64),
       ("HIP", HIP, Ops.SQRT, dtypes.f16), ("HIP", HIP, Ops.SQRT, dtypes.f32),
       ("HIP", HIP, Ops.SQRT, dtypes.f64), ("HIP", HIP, Ops.TRUNC, dtypes.f16),
       ("HIP", HIP, Ops.SIN, dtypes.f32), ("HIP", HIP, Ops.LOG2, dtypes.f32),
       ("HIP", HIP, Ops.EXP2, dtypes.f16), ("HIP", HIP, Ops.RECIPROCAL, dtypes.f32),
       ("OPENCL", OPENCL, Ops.SIN, dtypes.f32), ("OPENCL", OPENCL, Ops.SQRT, dtypes.f16),
       ("CUDA", CUDA, Ops.SQRT, dtypes.bf16), ("CUDA", CUDA, Ops.SIN, dtypes.bf16),
       ("CUDA", CUDA, Ops.TRUNC, dtypes.bf16), ("CUDA", CUDA, Ops.LOG2, dtypes.bf16),
       ("CUDA", CUDA, Ops.EXP2, dtypes.bf16), ("CUDA", CUDA, Ops.RECIPROCAL, dtypes.bf16),
       ("HIP", HIP, Ops.SQRT, dtypes.bf16), ("HIP", HIP, Ops.TRUNC, dtypes.bf16),
       ("BASE", BASE, Ops.FDIV, dtypes.f32), ("CUDA", CUDA, Ops.FDIV, dtypes.f32),
       ("METAL", METAL, Ops.FDIV, dtypes.f32)]
for nm, r, op, dt in CFO:
    row(f"cfo {nm:<5} {op.name} {dt.name}", cfo(r, op, dt))
row("cfo BASE  WHERE", cfo(BASE, Ops.WHERE, dtypes.f32))
row("cfo CLANG WHERE", cfo(CLANG, Ops.WHERE, dtypes.f32))

# ---- kern. `lb=1` is the NO-LOCAL case, because `prod([])` is 1.
for nm, r, lb in [("BASE", BASE, 1), ("CLANG", CLANG, 4), ("OPENCL", OPENCL, 1), ("METAL", METAL, 1),
                  ("CUDA", CUDA, 1), ("CUDA", CUDA, 4), ("HIP", HIP, 1), ("HIP", HIP, 4)]:
    row(f"kern {nm:<5} lb={lb}", r.kernel_typedef.format(launch_bounds=lb))

# ---- idx. `render_index` reads `buf.addrspace`, `buf.max_numel()`, `idx.op`,
# `idx.src[0].val`, `idx.arg` and `self.gep_arr_threshold`, so the index must be
# a REAL UOp -- a duck type with only `.op` set answers `.src` as AttributeError.
def const_uop(k): return UOp.const(k, dtypes.i32)
def idx_uop(k, add=False):
    # `render_index`'s `idx.op is CAST and idx.src[0].op is CONST` half.
    c = const_uop(k)
    if add: return c.cast(dtypes.i32).bitcast(dtypes.i32)
    return c.cast(dtypes.i32)
def add_idx_uop(k):
    # NOTHING in tinygrad builds an INDEX whose `arg is Ops.ADD`, so this is a
    # HAND-BUILT node -- which is the only way to reach `render_index`'s
    # `strip_parens` arm at all. MEASURED: no `.index(..., arg=Ops.ADD)` exists.
    return UOp(Ops.INDEX, (const_uop(0), const_uop(k)), Ops.ADD)
def lane_uop(): return UOp(Ops.INDEX, (const_uop(0), const_uop(0)))

class FakeBuf:
    def __init__(self, baddr, bnumel): self.addrspace, self._n = baddr, bnumel
    def max_numel(self): return self._n

def render_index(r, baddr, bnumel, ix, bname="B", iname="R"):
    b = FakeBuf(baddr, bnumel)
    if b.addrspace == AddrSpace.ALU:
        if not (ix.op is Ops.CAST and ix.src[0].op is Ops.CONST): return f"({bname})[{iname}]"
        return bname + (f"[{ix.src[0].val}]" if b.max_numel() > r.gep_arr_threshold else f".{'xyzwabcd'[ix.src[0].val]}")
    return f"({bname}+{strip_parens(iname) if ix.arg == Ops.ADD else iname})"

IDX = [("BASE  sz1 k0 ", BASE, AddrSpace.ALU, 1, idx_uop(0), "R"),
       ("BASE  sz8 k0 ", BASE, AddrSpace.ALU, 8, idx_uop(0), "R"),
       ("BASE  sz1 k1 ", BASE, AddrSpace.ALU, 1, idx_uop(1), "R"),
       ("CLANG sz1 k0 ", CLANG, AddrSpace.ALU, 1, idx_uop(0), "R"),
       ("CLANG sz8 k0 ", CLANG, AddrSpace.ALU, 8, idx_uop(0), "R"),
       ("OPENCLsz1 k0 ", OPENCL, AddrSpace.ALU, 1, idx_uop(0), "R"),
       ("OPENCLsz8 k0 ", OPENCL, AddrSpace.ALU, 8, idx_uop(0), "R"),
       ("CUDA  sz8 k0 ", CUDA, AddrSpace.ALU, 8, idx_uop(0), "R"),
       ("CUDA  sz16k0 ", CUDA, AddrSpace.ALU, 16, idx_uop(0), "R"),
       ("CUDA  sz8 k1 ", CUDA, AddrSpace.ALU, 8, idx_uop(1), "R"),
       ("HIP   sz1 k0 ", HIP, AddrSpace.ALU, 1, idx_uop(0), "R"),
       ("METAL sz1 k0 ", METAL, AddrSpace.ALU, 1, idx_uop(0), "R"),
       ("BASE  lane   ", BASE, AddrSpace.ALU, 1, lane_uop(), "R"),
       ("CLANG lane   ", CLANG, AddrSpace.ALU, 16, lane_uop(), "R"),
       ("HIP   lane   ", HIP, AddrSpace.ALU, 16, lane_uop(), "R"),
       ("BASE  regadd ", BASE, AddrSpace.REG, 1, add_idx_uop(0), "(R)"),
       ("BASE  regnoad", BASE, AddrSpace.REG, 1, idx_uop(0), "(R)"),
       ("HIP   regadd ", HIP, AddrSpace.REG, 1, add_idx_uop(0), "(R)"),
       ("BASE  sz1 k3 ", BASE, AddrSpace.ALU, 1, idx_uop(3), "R"),
       ("CUDA  sz8 k3 ", CUDA, AddrSpace.ALU, 8, idx_uop(3), "R")]
for nm, r, baddr, bnumel, ix, iname in IDX:
    row(f"idx {nm}", render_index(r, baddr, bnumel, ix, iname=iname))

# ---- type / ptr / cast / legacy. `override_ptr` is `op is INDEX and REG`.
row("type BASE  stk4", BASE._render_dtype(dtypes.f32, 4, AddrSpace.ALU, override_ptr=False))
row("type BASE  regidx", BASE._render_dtype(dtypes.f32, 1, AddrSpace.REG, override_ptr=True))
row("type BASE  scalar", BASE._render_dtype(dtypes.f32, 1, AddrSpace.ALU))
row("type OPENCLglobidx", OPENCL._render_dtype(dtypes.f32, 1, AddrSpace.GLOBAL, override_ptr=False))
row("type METAL globidx", METAL._render_dtype(dtypes.f32, 1, AddrSpace.GLOBAL, override_ptr=False))
row("ptr  BASE  stk4", f"(({BASE._render_dtype(dtypes.f32, 4, AddrSpace.ALU, override_ptr=True)})(S))")
row("ptr  BASE  bitcast", f"(({BASE._render_dtype(dtypes.i32, 1, AddrSpace.ALU, override_ptr=True)})(V))")
row("cast BASE  half", f"({BASE._render_dtype(dtypes.f16, 1, AddrSpace.REG)})(V)")
row("cast CLANG half", f"({CLANG._render_dtype(dtypes.f16, 1, AddrSpace.REG)})(V)")
row("leg  BASE  float", BASE.render_dtype(dtypes.f32))
row("leg  CLANG half", CLANG.render_dtype(dtypes.f16))
row("leg  CLANG bool", CLANG.render_dtype(dtypes.bool))

# ---- buf2. `render_buffer` reads `ctx[x]`, so `self.r` must map the REAL uop.
def rb_row(r, dt, size, nm):
    r.r = {}
    u = UOp(Ops.BUFFER, (), arg=ParamArg(0, dt, size=size))
    r.r[u] = nm
    return r.render_buffer(u)

row("buf2 BASE  LOC", rb_row(BASE, dtypes.f32, 1, "L0"))
row("buf2 OPENCLLOC", rb_row(OPENCL, dtypes.f32, 1, "L0"))
row("buf2 CUDA  LOC", rb_row(CUDA, dtypes.f32, 1, "L0"))
row("buf2 HIP   LOC", rb_row(HIP, dtypes.f32, 1, "L0"))
row("buf2 METAL LOC", rb_row(METAL, dtypes.f32, 1, "L0"))
row("buf2 OPENCLGLOB", rb_row(OPENCL, dtypes.f32, 1, "G"))
row("buf2 CUDA  GLOB", rb_row(CUDA, dtypes.f32, 1, "G"))
row("buf2 METAL GLOB", rb_row(METAL, dtypes.f32, 1, "G"))
row("buf2 HIP   sz16", rb_row(HIP, dtypes.f16, 16, "L0"))

# ---- wmma. `_wmma_name` indexes `u.arg[0]` and `u.arg[1]`, so the arg is a REAL
# WMMA arg tuple and the dtype is read off the node.
def wmma_name_of(dims, din, dout):
    u = UOp(Ops.WMMA, (UOp.const(0, dtypes.u32), UOp.const(0, dtypes.u32), UOp.const(0, dtypes.u32)),
            arg=(tuple(dims), din, 32, ()))
    return f"WMMA_{'_'.join(map(str, u.arg[0]))}_{u.arg[1].name}_{u.dtype.name}".replace(" ", "_")
row("wmma 16_16_16 half", wmma_name_of([16, 16, 16], dtypes.f16, dtypes.f16))
row("wmma 16_16_16 i8", wmma_name_of([16, 16, 16], dtypes.i8, dtypes.i8))
row("wmma 8_8_32   bf16", wmma_name_of([8, 8, 32], dtypes.bf16, dtypes.bf16))
row("wmma 16_16_128 fp8", wmma_name_of([16, 16, 128], dtypes.fp8e4m3, dtypes.fp8e4m3))

# ---- under. `.replace(" ", "_")`.
row("under float", "float".replace(" ", "_"))
row("under signed char", "signed char".replace(" ", "_"))
row("under unsigned long", "unsigned long".replace(" ", "_"))

# ---- img. `is_image_shape` beats the address space in BOTH directions.
row("img BASE  write", BASE._render_dtype(dtypes.f32, 1, AddrSpace.GLOBAL, mutable=True, shape=IMG))
row("img BASE  read", BASE._render_dtype(dtypes.f32, 1, AddrSpace.GLOBAL, mutable=False, shape=IMG))
row("img OPENCLwrite", OPENCL._render_dtype(dtypes.f32, 1, AddrSpace.GLOBAL, mutable=True, shape=IMG))

# ---- devname / barrier / f4. The option tables `render_kernel` never reads.
row("devname", "/".join(dict(zip(["BASE", "CLANG", "OPENCL", "METAL", "CUDA", "HIP"],
                                 [type(CStyleLanguage).__name__])) and ["BASE", "CLANG", "OPENCL", "METAL", "CUDA", "HIP"]))
for nm, r in DEVS: row(f"barrier {nm:<5}", r.barrier)
for nm, r in DEVS:
    try: f4 = r.float4
    except AttributeError: f4 = None
    row(f"f4style {nm:<5}", f"{f4}|{r.float4_style[0]}{r.float4_style[1]}")
row("inf BASE", f"{BASE.infinity}|{BASE.nan}")
row("inf CLANG", f"{CLANG.infinity}|{CLANG.nan}")
row("inf HIP", f"{HIP.infinity}|{HIP.nan}")

# ---- kern2. `render_kernel` end to end, `prefix=None` and the body verbatim.
KERNEL = ["  float4 val0 = (*((float4*)((data1_4+0))));", "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]
def kbuf(dt, nm, volatile=False, mutable=True, size=1):
    u = UOp(Ops.BUFFER, (), arg=ParamArg(0, dt, size=size, volatile=volatile))
    return (nm, (u, mutable))

def kern2(r, bufs, lb=1, prefix=None, uops=()):
    r.r = {}
    for nm, (u, _) in bufs: r.r[u] = nm
    return r.render_kernel("E_4", list(KERNEL), bufs, list(uops), prefix=prefix)

BS = [kbuf(dtypes.f32, "data0_4"), kbuf(dtypes.f32, "data1_4")]
for nm, r in [("BASE", BASE), ("CLANG", CLANG), ("OPENCL", OPENCL), ("HIP", HIP), ("METAL", METAL)]:
    row(f"kern2 {nm}", kern2(r, BS))
# THE PREFIX BRANCH. `prefix=None`, `prefix=[]` and a two-line prefix are THREE
# kernels (cstyle.py:166), and only the base and OpenCL keep the caller's lines.
CALLER = ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]
row("kern2 BASE  pref2", kern2(BASE, BS, prefix=list(CALLER)))
row("kern2 BASE  pref0", kern2(BASE, BS, prefix=[]))
row("kern2 OPENCLpref2", kern2(OPENCL, BS, prefix=list(CALLER)))
for nm, r in [("CUDA", CUDA), ("HIP", HIP), ("METAL", METAL)]:
    row(f"kern2 {nm} pref2", kern2(r, BS, prefix=list(CALLER)))
# OpenCL's `#pragma` is conditional on a half uop and PREPENDS onto the caller's
# list, so the two halves are two rows.
row("kern2 OPENCLhlfp16", kern2(OPENCL, BS, prefix=list(CALLER), uops=[sp(), alu(dtypes.f16)]))
# `buftype`'s `volatile` half, which `kern2` cannot reach without one.
row("kern2 BASE  vol", kern2(BASE, [kbuf(dtypes.f32, "data0_4", volatile=True), kbuf(dtypes.f32, "data1_4")]))
row("kern2 CLANG vol", kern2(CLANG, [kbuf(dtypes.f32, "data0_4", volatile=True), kbuf(dtypes.f32, "data1_4")]))
# HIP's prefix, clause by clause. A SPECIAL is what turns on `size_t` + the three
# `__ockl_*` externs; the named dtypes turn on the rest.
SQRT_H, SQRT_F = alu(dtypes.f16).alu(Ops.SQRT), alu(dtypes.f32).alu(Ops.SQRT)
row("kern2 HIP   nocdna4", kern2(HIP, BS, uops=[sp()]))
row("kern2 HIP   ockl", kern2(HIP, BS, uops=[sp(), SQRT_H, SQRT_F]))
row("kern2 HIP   half", kern2(HIP, BS, uops=[sp(), alu(dtypes.f16)]))
row("kern2 HIP   bf16", kern2(HIP, BS, uops=[sp(), alu(dtypes.bf16)]))
row("kern2 HIP   cdna4", kern2(Bare(HIPRenderer, "gfx950", "AMD"), BS, uops=[sp(), alu(dtypes.bf16)]))
row("kern2 HIP   inf", kern2(HIP, BS, uops=[sp(), UOp.const(float("nan"), dtypes.f32).cast(dtypes.f32)]))
# CUDA's prefix: four static lines then one `#include` per used dtype.
row("kern2 CUDA  half", kern2(CUDA, BS, uops=[alu(dtypes.f16)]))
row("kern2 CUDA  bf16", kern2(CUDA, BS, uops=[alu(dtypes.bf16)]))
row("kern2 CUDA  fp8", kern2(CUDA, BS, uops=[alu(dtypes.fp8e4m3)]))
row("kern2 CUDA  all", kern2(CUDA, BS, uops=[alu(dtypes.f16), alu(dtypes.bf16), alu(dtypes.fp8e4m3)]))

# ---- hipockl / hipocml. The two extern FAMILIES, joined: `kern2 HIP ockl`
# emits the `ockl` half and the `ocml` attribute table has FIVE rows that no single
# kernel reaches at once, and a gate that never shows the `""` (no comma) attribute
# is a gate that cannot see a reader that always writes `, `.
row("hipockl", "\n".join(
    'extern "C" __attribute__((device%s)) %s %s(%s);' % (
      (", " + atr) if atr else "", dto, meth, dti)
    for meth, dti, dto, atr in [(f"__ockl_get_{n}", "unsigned int", "size_t", "const")
                                for n in ["local_id", "group_id", "local_size"]]))
OCML_OPS = {"EXP2": ("exp2", "pure"), "LOG2": ("log2", "pure"), "SQRT": ("sqrt", "const"),
            "SIN": ("sin", ""), "TRUNC": ("trunc", "")}
row("hipocml", "\n".join(
    'extern "C" __attribute__((device%s)) %s __ocml_%s_f%d(%s);' % (
      (", " + atr) if atr else "", dt.name, cn, dt.bitsize, dt.name)
    for _, (cn, atr) in OCML_OPS.items() for dt in [dtypes.f16, dtypes.f32, dtypes.f64]))

# ---- acc. `render_access` is `f"*{render_ptr}"`, and `kern2`'s fixture BODY
# spells that by hand -- so this row is what says the def and the fixture agree.
row("acc BASE  stk4", "*" + f"(({BASE._render_dtype(dtypes.f32, 4, AddrSpace.ALU, override_ptr=True)})(S))")
row("acc BASE  plain", "*V")

for nm, v in ROWS:
    print("%s = [%s]" % (nm, str(v).replace("\n", "\\n")))
