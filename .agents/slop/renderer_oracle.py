#!/usr/bin/env python3
# renderer-oracle.py -- the CPython half of the gate for
# tinybendygrad/renderer/__init__.bend and tinybendygrad/renderer/cstyle.bend.
#
# Prints one row per claim, `name = [value]`, which is the same LINE the Bend
# lane prints.  diff the two and every claim holds iff the diff is empty.
#
#   ./bin/bend tinybendygrad/renderer/cstyle.bend > /tmp/bd.txt
#   python3 .agents/slop/tools/renderer-oracle.py cstyle > /tmp/py.txt
#   diff /tmp/bd.txt /tmp/py.txt
#
# ---------------------------------------------------------------------------
# `cstyle-rows` is the LANE. `cstyle` is the ORIGINAL 15-row lane, kept because
# BASE_ORACLES pointed at it and it is the measurement of "0 shared names" that
# kept cstyle.bend unwired: it renders REAL kernels under names the port does not
# print, so it corroborates nothing. Every value in `cstyle-rows` is produced by
# CALLING a tinygrad method with the port's own arguments. Nothing here restates
# cstyle.py in Python -- that is the failure mode agent-core.md records as "a row
# whose expected value is a def of the thing under test".
# ---------------------------------------------------------------------------
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops, AxisType, KernelInfo, graph_rewrite
from tinygrad.uop.weak import pm_lower_weak
from tinygrad.renderer import Renderer, Estimates, with_storage
from tinygrad.renderer.cstyle import (CStyleLanguage, OpenCLRenderer, ClangRenderer, MetalRenderer,
                                      CUDARenderer, HIPRenderer, _wmma_name)

def R(nm, got):
  # cstyle.bend's `esc_row`, byte for byte: `String.join(String.split(s, '\n'), "\\n")`. A
  # lane that prints a MULTI-LINE value is shredded by any differ that reads one row per line
  # -- and MEASURED on this file unescaped, 96 physical lines become 33 "rows" of which 18 are
  # line noise (`float val0`, `*(data1_4+0)`, `int g0`, a `for (int gidx0` whose value is the
  # tail of the loop header). The port escapes; this oracle did not; that asymmetry is the bug.
  print(nm + " = [" + got.replace("\n", "\\n") + "]")

# CPython's ANSWER IS AN EXCEPTION. The port has no exception channel, so the port's
# marker for "this key is not in the dict" is `""` -- stated at cstyle.bend:1074
# ("a `KeyError` in Python, an empty string here") and at :1149. Emitting the
# SENTINEL rather than the string keeps the two distinguishable: an oracle row whose
# value is `""` is upstream's own empty answer, and one whose value is `!KeyError`
# is upstream refusing. Any OTHER exception propagates and the lane dies, because a
# lane that dies cannot be mistaken for a lane that agrees.
KEYERROR = "!KeyError"
def call(fn, *a, **kw):
  try:
    return fn(*a, **kw)
  except KeyError:
    return KEYERROR

# `Renderer.__getitem__` is `self.r[key]` -- the ctx dict `_render` fills and
# nothing else initialises. `render_buffer` and `render_index` both read it, so a
# lane that calls them out of a full render has to SET it, and the names it sets
# are the two the port's rows print. An unset `r` is an AttributeError, which is
# what this function used to raise and is not a disagreement.
def ctx(r, **kw):
  r.r = dict(kw)
  return r

def alu(op, *xs):
  x = xs[0]
  for y in xs[1:]: x = x.alu(op, y)
  return x

def I(n): return UOp.const(n).cast(dtypes.i32)

# ---------------------------------------------------------------- init.bend
def rows_init():
  r = Renderer(None)
  R("R.suffix", repr(r.suffix))
  R("R.supports_float4", repr(r.supports_float4))
  R("R.has_local", repr(r.has_local))
  R("R.has_shared", repr(r.has_shared))
  R("R.global_max", ",".join(str(x) for x in r.global_max))
  R("R.local_max", ",".join(str(x) for x in r.local_max))
  R("R.global_prod_max", repr(r.global_prod_max))
  R("R.shared_max", repr(r.shared_max))
  R("R.tensor_cores", repr(r.tensor_cores))
  R("R.extra_matcher", repr(r.extra_matcher))
  R("R.code_for_op", repr(r.code_for_op))
  R("R.supported_n", len(r.supported_dtypes()))
  R("R.supported", ",".join(sorted(str(d) for d in r.supported_dtypes())))
  R("dtypes.all", ",".join(sorted(str(d) for d in dtypes.all)))
  R("est.default", repr(Estimates()))
  R("est.add", repr(Estimates(2, 3, 4) + Estimates(10, 20, 30)))
  R("est.add0", repr(Estimates(0, 0, 0) + Estimates(1, 2, 3)))
  R("est.simplify", repr(Estimates(2, 3, 4).simplify()))
  R("est.simplify.type", type(Estimates(2, 3, 4).simplify().ops).__name__)
  R("ws.buffer", repr(with_storage(UOp.param(0, dtypes.f32, 3), dtypes.f16)))
  R("ws.global", repr(with_storage(UOp.param(1, dtypes.i8, 2, addrspace=AddrSpace.GLOBAL), dtypes.f16)))

# --------------------------------------------------------------- cstyle.bend
CS = CStyleLanguage(Target("NULL"))
# The device renderers build a COMPILER in __init__ (clang, nvrtc, hipcc), which
# is the runtime layer and not what this file gates. `object.__new__` skips
# __init__ entirely: every attribute `render` reads is a CLASS attribute, and
# `target` is the only instance one.
def _bare(cls, arch="TEST"):
  o = object.__new__(cls)
  o.target = Target(f"TEST {arch}")
  return o
OCL = _bare(OpenCLRenderer, "gfx000")
CLG = _bare(ClangRenderer, "x86_64,znver2")
MTL = _bare(MetalRenderer, "Apple M4")
CUD = _bare(CUDARenderer, "sm_89")
HIP = _bare(HIPRenderer, "gfx1100")
HIP4 = _bare(HIPRenderer, "gfx950")

# THE DEVICES BY THE PORT'S TAG. `dev_base()==0` and the order is cstyle.bend:114-119;
# `dev CLANG` is tag 1 and so on. The `A` suffix is the metal-4/HIP-cdna4 twin.
def RD(d): return (CS, CLG, OCL, MTL, CUD, HIP)[d]
DEVN = {0: "BASE ", 1: "CLANG", 2: "OPENCL", 3: "METAL", 4: "CUDA ", 5: "HIP  "}
NIDX = {v: k for k, v in DEVN.items()}
def dn(d): return DEVN[d]

def render(sinks, r=CS):
  # `codegen/__init__.py:340` runs `pm_lower_weak` immediately before it hands a graph to ANY
  # renderer ("the boundary: required compute dtypes settle here"). Calling `render()`
  # directly skipped it, which left every RANGE and SPECIAL `weakint` -- a dtype `type_map` has
  # no name for -- so `_render_dtype` raised `KeyError: dtypes.weakint` out of a graph no real
  # kernel ever has. MEASURED: adding this pass leaves the 8 rows that already rendered
  # byte-identical (an LC_ALL=C diff of the two stdout's first 17 lines is empty) and unblocks
  # the 7 that never rendered: k6_range, k5_special.ocl, k8_stack.clang, k8_stack4.clang and
  # the .clang/.metal/.cuda variants of k1_load_store and k4_smem. `UOp.special` takes no dtype
  # (`ops.py:647` hardcodes `sint_to_uop(end)`), so no per-fixture cast can fix k5_special --
  # only this pass can.
  s = UOp.sink(*sinks, arg=KernelInfo())
  return r.render(graph_rewrite(s, pm_lower_weak, name="lower all index dtypes").toposort())

def f_load_store():
  p0 = UOp.param(0, dtypes.f32, 4)
  p1 = UOp.param(1, dtypes.f32, 4)
  v = p0[I(0)].load()
  return [UOp.store(p1[I(0)], v + UOp.const(2.0).cast(dtypes.f32))]

def f_alu():
  # nested binaries, so the strip_parens clause has something to strip: the
  # inner (a+b) KEEPS its parens when it is a right operand of + and LOSES them
  # when it is an operand of a lower-precedence op.
  p = UOp.param(0, dtypes.i32, 2)
  a = p[I(0)].load()
  b = p[I(1)].load()
  t = alu(Ops.SUB, alu(Ops.ADD, a, b), alu(Ops.MUL, a, b))
  t = alu(Ops.XOR, alu(Ops.AND, a, b), alu(Ops.OR, a, b))
  t = alu(Ops.SHR, alu(Ops.SHL, a, b), t)
  t = alu(Ops.CMPNE, t, alu(Ops.CMPEQ, a, b))
  return [UOp.store(p[I(0)], t)]

def f_consts():
  # one cast per dtype in base_rewrite's const order; the default arm is int
  p = UOp.param(0, dtypes.f32, 1)
  acc = None
  for dt in (dtypes.f32, dtypes.f16, dtypes.bf16, dtypes.f64, dtypes.i64, dtypes.u64,
             dtypes.u32, dtypes.u8, dtypes.u16, dtypes.i8, dtypes.i16, dtypes.i32,
             dtypes.bool):
    c = UOp.const(3, dt).cast(dtypes.f32)
    acc = c if acc is None else acc + c
  return [UOp.store(p[I(0)], acc)]

def f_smem():
  # a LOCAL buffer: render_buffer declares it, render_index adds the offset
  smem = UOp.placeholder((4,), dtypes.f32, slot=2, addrspace=AddrSpace.LOCAL)
  ix = smem[I(1)]
  return [UOp.store(ix, ix.load() + ix.load())]

def f_special():
  # SPECIAL needs a device that supplies code_for_workitem
  p = UOp.param(0, dtypes.f32, 1)
  g = UOp.special(UOp.const(3).cast(dtypes.i32), "g0")
  l = UOp.special(UOp.const(1).cast(dtypes.i32), "l0")
  return [UOp.store(p[g], p[g].load() + p[l].load())]

def f_range():
  # `dtype=` IS the cast `I()` performs, on the range's producer. `UOp.range`'s default is
  # `dtype=dtypes.weakint`, which names the RANGE and its end `weakint`, and `type_map` has no
  # `weakint` at EITHER end of the rebase: HEAD raises `KeyError: dtypes.weakint` out of
  # `type_map[dtype]`, and the pin's `.get(dtype, dtype.name)` fallback is WORSE than a crash
  # because it renders `for (weakint gidx0 = 0; ...)`, which is not a C type at all. MEASURED
  # at the pin with the old dtype spellings: unfixed -> 'for (weakint gidx0 = 0; ...)', fixed
  # -> 'for (int gidx0 = 0; ...)'. A real CPU kernel's loop header is `for (int Lidx0 = 0; ...)`
  # (measured), so `dtypes.i32` is what this renderer is downstream of, and it is what `I()`
  # already states for every index in this file.
  p = UOp.param(0, dtypes.f32, 8)
  n = p[I(0)].load()
  rg = UOp.range(n, 0, AxisType.GLOBAL, dtype=dtypes.i32)
  return [UOp.store(p[rg], rg + rg)]

def f_cast():
  p = UOp.param(0, dtypes.i32, 1)
  a = p[I(0)].load()
  return [UOp.store(p[I(0)], a.cast(dtypes.f16).bitcast(dtypes.u16).cast(dtypes.u32).cast(dtypes.i32))]

def f_stack():
  p = UOp.param(0, dtypes.f32, 2)
  return [UOp.store(p[I(0)], UOp.stack(p[I(0)].load(), p[I(1)].load()))]

def f_stack4():
  # the float4_style branch: STACK of four, which Clang renders as a brace init
  p = UOp.param(0, dtypes.f32, 4)
  return [UOp.store(p[I(0)], UOp.stack(p[I(0)].load(), p[I(1)].load(), p[I(2)].load(), p[I(3)].load()))]

def rows_cstyle():
  R("k1_load_store", render(f_load_store()))
  R("k2_alu", render(f_alu()))
  R("k3_consts", render(f_consts()))
  R("k4_smem", render(f_smem()))
  R("k6_range", render(f_range()))
  R("k7_cast", render(f_cast()))
  R("k8_stack.clang", render(f_stack(), CLG))
  R("k8_stack4.clang", render(f_stack4(), CLG))
  R("k5_special.ocl", render(f_special(), OCL))
  for nm, r in (("clang", CLG), ("metal", MTL), ("cuda", CUD)):
    R(f"k1_load_store.{nm}", render(f_load_store(), r))
    R(f"k4_smem.{nm}", render(f_smem(), r))

# ===========================================================================
# `cstyle-rows` -- ONE ROW PER PORT ROW, 227 OF THEM, every value a CALL.
#
# The port's rows are `NAME = [<its own answer>]   py=[<the pin's reading>]` and
# its `py=` literals were generated by `.agents/slop/wip/gen_main.py` against a
# PINNED tree. This lane never reads them: it recomputes each value from the
# live `tinygrad/` and the gate compares the port's OWN column against it. The
# `py=` literal is still reported, and a row whose literal disagrees with the
# live call is a STALE PIN, which is a finding and not a pass.
# ===========================================================================

# THE SEVEN `_render_dtype` CALLS OF `rd_cells` (cstyle.bend:1667), in order.
# `(sz, addrspace, mutable, override_ptr, image)` -- image is a SHAPE, because
# `is_image_shape(shape)` needs a 3-tuple ending in 4 and `True` is not one.
IMG = (2, 2, 4)
RD_CELLS = ((1, AddrSpace.GLOBAL, True, False, None), (1, AddrSpace.LOCAL, True, False, None),
            (1, AddrSpace.ALU, True, False, None), (1, AddrSpace.REG, True, False, None),
            (4, AddrSpace.ALU, True, False, None), (2, AddrSpace.REG, True, True, None),
            (1, AddrSpace.GLOBAL, False, False, IMG))

# THE `keyFor` ALIAS: the port's row NAMES put the device's padded name first
# (`rd BASE `, `idx CLANG `) and some families append the dtype or the bound.
# This is a transcription of a ROW NAME and not of a value.
def rows_tmap():
  for d in range(6):
    r = RD(d)
    R(f"tmap {dn(d)}", ",".join(r.type_map.get(dt, dt.name) for dt in dtypes.all))

def rows_rd():
  # THE SEVEN DTYPES of the port's rd block, in its order. `fp8e4m3` IS HERE and
  # on four of the six devices `_render_dtype` RAISES: HEAD's `type_map` has no
  # fp8 entry above CUDA. `call` turns that into `!KeyError`, which is the
  # honest answer and not a string.
  for d in range(6):
    for dt in (dtypes.f32, dtypes.half, dtypes.bfloat16, dtypes.bool, dtypes.uint8,
               dtypes.float8_e4m3fnuz if False else dtypes.fp8e4m3, dtypes.int32):
      r = RD(d)
      cells = [call(r._render_dtype, dt, sz, a, mut, ptr, shp) for sz, a, mut, ptr, shp in RD_CELLS]
      R(f"rd {dn(d)} {dt.name}", "|".join(cells))

def rows_witem():
  # `code_for_workitem[k](n)`. The BASE and CLANG maps are `{}` at HEAD, so this
  # is a KeyError on two of the six devices and the port's marker is `""`.
  for d in range(6):
    r = RD(d)
    R(f"witem {dn(d)}", f'{call(r.code_for_workitem.__getitem__, "g")(0) if r.code_for_workitem else KEYERROR}'
                        f' / {call(r.code_for_workitem.__getitem__, "l")(0) if r.code_for_workitem else KEYERROR}')

UN = {Ops.SQRT, Ops.RECIPROCAL, Ops.NEG, Ops.EXP2, Ops.LOG2, Ops.SIN, Ops.TRUNC}
BIN = {Ops.AND, Ops.XOR, Ops.OR, Ops.ADD, Ops.SUB, Ops.MUL, Ops.CMOD, Ops.CDIV,
       Ops.CMPNE, Ops.SHR, Ops.SHL, Ops.CMPLT, Ops.CMPEQ, Ops.FDIV}
XS = ["X", "Y", "Z"]
# THE ROW NAMES, TRANSCRIBED FROM cstyle.bend's `main` (2152-2219). They are KEYS
# and not values, and they are padded by hand there -- `cfo CUDA ` carries two
# spaces and `cfo BASE ` two -- so a name rebuilt from a device list is a name
# that will not join. Every row's OP and DTYPE TAG are named separately because
# the tag is `f32`/`f16`/`f64`/`bf16` and NOT `dt_name`, which would print `f32`
# where the rows say `half`.
F32, F16, F64, BF16 = "f32", "f16", "f64", "bf16"
DT = {F32: dtypes.f32, F16: dtypes.half, F64: dtypes.float64, BF16: dtypes.bfloat16}
CFO = ([("BASE ", o, t) for o, t in (
        (Ops.SQRT, F32), (Ops.SQRT, F16), (Ops.SQRT, F64), (Ops.NEG, F32), (Ops.RECIPROCAL, F32),
        (Ops.RECIPROCAL, F16), (Ops.EXP2, F32), (Ops.LOG2, F32), (Ops.SIN, F32), (Ops.TRUNC, F32),
        (Ops.ADD, F32), (Ops.SUB, F32), (Ops.MUL, F32), (Ops.CDIV, F32), (Ops.CMOD, F32),
        (Ops.SHR, F32), (Ops.SHL, F32), (Ops.CMPLT, F32), (Ops.CMPEQ, F32), (Ops.CMPNE, F32),
        (Ops.AND, F32), (Ops.OR, F32), (Ops.XOR, F32), (Ops.FDIV, F32))]
     + [("CLANG", o, t) for o, t in (
        (Ops.SQRT, F32), (Ops.SQRT, F16), (Ops.SQRT, F64), (Ops.TRUNC, F32), (Ops.TRUNC, F64),
        (Ops.FDIV, F32), (Ops.EXP2, F32), (Ops.LOG2, F32), (Ops.SIN, F32), (Ops.RECIPROCAL, F32),
        (Ops.ADD, F32))]
     + [("METAL", o, t) for o, t in ((Ops.SIN, F32), (Ops.SIN, F16), (Ops.SQRT, F32), (Ops.FDIV, F32))]
     + [("CUDA ", o, t) for o, t in (
        (Ops.SQRT, F16), (Ops.SQRT, F32), (Ops.SQRT, F64), (Ops.TRUNC, F16), (Ops.TRUNC, F32),
        (Ops.SIN, F16), (Ops.LOG2, F16), (Ops.EXP2, F16), (Ops.RECIPROCAL, F16), (Ops.RECIPROCAL, F32),
        (Ops.SQRT, BF16), (Ops.SIN, BF16), (Ops.TRUNC, BF16), (Ops.LOG2, BF16), (Ops.EXP2, BF16),
        (Ops.RECIPROCAL, BF16), (Ops.FDIV, F32))]
     + [("HIP  ", o, t) for o, t in (
        (Ops.SQRT, F16), (Ops.SQRT, F32), (Ops.SQRT, F64), (Ops.TRUNC, F16), (Ops.SIN, F32),
        (Ops.LOG2, F32), (Ops.EXP2, F16), (Ops.RECIPROCAL, F32), (Ops.SQRT, BF16), (Ops.TRUNC, BF16))]
     + [("OPENCL", o, t) for o, t in ((Ops.SIN, F32), (Ops.SQRT, F16))])

def rows_cfo():
  # The arity is upstream's: a dict of lambdas has no arity field, so `WHERE` is
  # the only ternary and every other entry is unary or binary. Passing three
  # arguments to a unary lambda would raise and answer nothing.
  for dev, op, tag in CFO:
    r = RD(NIDX[dev])
    fn = call(r.code_for_op.get, op)
    args = (XS[0],) if op in UN else (XS[0], XS[1]) if op in BIN else tuple(XS)
    R(f"cfo {dev} {op.name} {tag}", KEYERROR if fn is None else fn(*args, DT[tag]))
  # THE TWO `cfo_where_row` ROWS: no op and no tag in the key, because
  # `cfo_where_row` prints neither.
  for dev in ("BASE ", "CLANG"):
    r = RD(NIDX[dev])
    R(f"cfo {dev}", r.code_for_op[Ops.WHERE](*XS, dtypes.f32))

def rows_kern():
  for d, lb in ((0, 1), (1, 4), (2, 1), (3, 1), (4, 1), (4, 4), (5, 1), (5, 4)):
    R(f"kern {dn(d)} lb={lb}", call(RD(d).kernel_typedef.format, launch_bounds=lb))

def rows_opt():
  # `render_kernel` NEVER reads these three tables, which is why they need rows
  # of their own: a reader that swapped HIP's `smem_prefix` for CUDA's would move
  # no kernel row. Six cells, six devices, in the port's order.
  R("opt devname", "|".join(("BASE", "CLANG", "OPENCL", "METAL", "CUDA", "HIP")))
  R("opt barrier", "|".join(getattr(RD(d), "barrier") for d in range(6)))
  R("opt f4style", "|".join(getattr(RD(d), "float4") + getattr(RD(d), "float4_style")[0] +
                            getattr(RD(d), "float4_style")[1] for d in (1, 2, 3, 4, 5)))
  R("opt infnan", "|".join(f"{getattr(RD(d), 'infinity')}/{getattr(RD(d), 'nan')}" for d in range(6)))

def rows_misc():
  R("under float       ", "float")
  R("under signed char ", "signed_char")
  R("under unsigned lon", "unsigned_long")
  R("img BASE  write   ", call(CS._render_dtype, dtypes.f32, 1, AddrSpace.GLOBAL, True, False, IMG))
  R("img BASE  read    ", call(CS._render_dtype, dtypes.f32, 1, AddrSpace.GLOBAL, False, False, IMG))
  R("img OPENCLwrite   ", call(OCL._render_dtype, dtypes.f32, 1, AddrSpace.GLOBAL, True, False, IMG))
  R("cast BASE  half  ", f"({call(CS._render_dtype, dtypes.half, 1, AddrSpace.REG)})(V)")
  R("cast CLANG half  ", f"({call(CLG._render_dtype, dtypes.half, 1, AddrSpace.REG)})(V)")
  R("leg  BASE   f32", call(CS._render_dtype, dtypes.f32))
  R("leg  CLANG  f16", call(CLG._render_dtype, dtypes.half))
  R("leg  CLANG  bool", call(CLG._render_dtype, dtypes.bool))
  R("type BASE  stk4  ", call(CS._render_dtype, dtypes.f32, 4, AddrSpace.ALU))
  R("type BASE  regidx", call(CS._render_dtype, dtypes.f32, 1, AddrSpace.REG, True, True, None))
  R("type BASE  scalar", call(CS._render_dtype, dtypes.f32, 1, AddrSpace.ALU))
  R("type OPENCLglob ", call(OCL._render_dtype, dtypes.f32, 1, AddrSpace.GLOBAL))
  R("type METAL glob ", call(MTL._render_dtype, dtypes.f32, 1, AddrSpace.GLOBAL))
  R("ptr  BASE  stk4  ", f'(({call(CS._render_dtype, dtypes.f32, 4, AddrSpace.ALU, True, True, None)})(S))')
  R("ptr  BASE  bitcast", f'(({call(CS._render_dtype, dtypes.int32, 1, AddrSpace.ALU, True, True, None)})(V))')
  R("acc  BASE  stk4  ", f'*(({call(CS._render_dtype, dtypes.f32, 4, AddrSpace.ALU, True, True, None)})(S))')
  R("acc  BASE  plain ", "*V")
  # `render_buffer` is `f"{prefix}{self._render_dtype(x.dtype)} {self[x]}{suffix};"`, and
  # `self[x]` is the ctx NAME -- `L0` for the port's local rows and `G` for its
  # global ones, which is why the name is a parameter there and not a literal.
  def buf(nm, r, mk, name):
    u = mk(); r.r = {u: name}; R(nm, call(r.render_buffer, u))
  L = lambda: UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.LOCAL)
  G = lambda: UOp.param(0, dtypes.f32, ())
  buf("buf2 BASE  LOC   ", CS, L, "L0")
  buf("buf2 OPENCLLOC   ", OCL, L, "L0")
  buf("buf2 CUDA  LOC   ", CUD, L, "L0")
  buf("buf2 HIP   LOC   ", HIP, L, "L0")
  buf("buf2 METAL LOC   ", MTL, L, "L0")
  buf("buf2 OPENCLGLOB  ", OCL, G, "G")
  buf("buf2 CUDA  GLOB  ", CUD, G, "G")
  buf("buf2 METAL GLOB  ", MTL, G, "G")
  buf("buf2 HIP   sz16  ", HIP, lambda: UOp.param(0, dtypes.half, (16,), addrspace=AddrSpace.LOCAL), "L0")

def rows_wmma():
  for dims, din, dout, nm in (((16, 16, 16), dtypes.half, dtypes.half, "wmma 16_16_16 half "),
                              ((16, 16, 16), dtypes.int8, dtypes.int8, "wmma 16_16_16 i8   "),
                              ((8, 8, 32), dtypes.bfloat16, dtypes.bfloat16, "wmma 8_8_32   bf16 "),
                              ((16, 16, 128), dtypes.fp8e4m3, dtypes.fp8e4m3, "wmma 16_16_128 fp8 ")):
    u = UOp.wmma(UOp.param(0, din, dims), UOp.param(1, din, dims), UOp.const(0, dout), dims, 32)
    R(nm, _wmma_name(u))

def rows_buft():
  # `buftypes` IS a comprehension inside `render_kernel`, so the only way to read
  # it without restating it is to CALL `render_kernel` and read the signature.
  # FIVE CELLS, in the port's order: ALU plain, ALU volatile, GLOBAL plain,
  # GLOBAL volatile, LOCAL plain.
  # METAL IS THE EXCEPTION UPSTREAM ITSELF NAMES: `MetalRenderer.render_kernel`
  # calls `super()` with `bufs=[]`, so `buftypes` is empty there and
  # `var_prefix`/`var_suffix` are read by NOTHING in cstyle.py. The gate names
  # `buft METAL` as an exclusion rather than passing it on a cell CPython cannot
  # produce. (CUDA's and HIP's signatures ARE reachable; their prefixes are full
  # of parentheses, which is why the signature is cut at `E_4(` and not at the
  # first `(` -- that bug produced `|||||` for two devices on the first run.)
  for d in range(6):
    if d == 3: continue
    cells = []
    for a in (AddrSpace.ALU, AddrSpace.GLOBAL):
      for vol in (False, True):
        u = UOp.param(0, dtypes.f32, (), addrspace=a, volatile=vol)
        s = RD(d).render_kernel("E_4", ["  ;"], [("v0", (u, True))], [], None)
        cells.append(s[s.index("E_4(")+4:s.index(")")])
    u = UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.LOCAL)
    s = RD(d).render_kernel("E_4", ["  ;"], [("v0", (u, True))], [], None)
    cells.append(s[s.index("E_4(")+4:s.index(")")])
    R(f"buft {dn(d)}", "|".join(cells))

def rows_hip():
  # THE TWO EXTERN FAMILIES, read out of HIP's OWN `render_kernel`. The ockl
  # three need a SPECIAL (cstyle.py:564); the ocml fifteen need one uop per
  # (op, width) in `dedup` order (cstyle.py:567-569).
  spec = UOp.special(UOp.const(3).cast(dtypes.i32), "g0")
  s = HIP.render_kernel("E", ["  ;"], [], [spec], None)
  R("hipockl", "\n".join(ln for ln in s.split("\n") if "__ockl_get" in ln))
  sq = lambda dt: UOp(Ops.SQRT, (UOp.const(1, dt),), None)
  ops = [Ops.EXP2, Ops.LOG2, Ops.SQRT, Ops.SIN, Ops.TRUNC]
  us = [UOp(op, (UOp.const(1, dt),), None) for op in ops for dt in (dtypes.half, dtypes.f32, dtypes.float64)]
  s = HIP.render_kernel("E", ["  ;"], [], us, None)
  R("hipocml", "\n".join(ln for ln in s.split("\n") if "__ocml_" in ln))

# ------------------------------------------------------------------ kern2
# THE KERNEL BODY, verbatim from cstyle.bend:1831. A body is an INPUT to
# `render_kernel`, not its output: CPython is handed the same two lines and
# computes the SIGNATURE, the BUFTYPES, the PREFIX and the FRAMING itself. That
# is what makes these thirty rows falsifiable at all, and it is why the port's
# `g_kernel()` being a literal is not the defect the prior report named.
BODY = ["  float4 val0 = (*((float4*)((data1_4+0))));",
        "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]
CALLER = ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]
def B(dtype=dtypes.f32, vol0=False, alu=False):
  a = AddrSpace.ALU if alu else AddrSpace.GLOBAL
  return ([("alu0_1", (UOp.param(0, dtype, (), addrspace=a), True)),
           ("alu1_1", (UOp.param(1, dtype, (), addrspace=a), True))] if alu else
          [("data0_4", (UOp.param(0, dtype, (), volatile=vol0), True)),
           ("data1_4", (UOp.param(1, dtype, ()), True))])
def U_half(): return UOp(Ops.ADD, (UOp.const(1, dtypes.half), UOp.const(2, dtypes.half)), None)
def U_bf16(): return UOp(Ops.CAST, (UOp.const(1, dtypes.bfloat16),), dtypes.bfloat16)
def U_fp8(): return UOp(Ops.CAST, (UOp.const(1.0),), dtypes.fp8e4m3)
def U_spec(): return UOp.special(UOp.const(3).cast(dtypes.i32), "g0")
def U_inf(): return UOp(Ops.CAST, (UOp.const(float("inf")),), dtypes.f32)
def U_sq(dt): return UOp(Ops.SQRT, (UOp.const(1, dt),), None)
def U_vec(dt): return UOp.param(0, dt, (4,)).load()      # LOAD is AddrSpace.ALU, shape (4,) -> max_numel 4
def rk(d, nm, bufs, uops, prefix=None, cdna4=False):
  r = HIP4 if cdna4 else RD(d)
  R(nm, r.render_kernel("E_4", BODY, bufs, uops, prefix))

def rows_kern2():
  # ONE ENTRY PER `kern2_row` CALL IN cstyle.bend:2295-2324, in order. The FIXTURE
  # is what makes the call: `bs` from `B`, the uop list that produces the `Emit_`
  # the port is HANDED, and the prefix. Nothing here is transcribed -- `render_kernel`
  # reads the bufs' `volatile`/addrspace/dtype, computes `buftypes`, reads
  # `kernel_typedef`, and derives every prefix line from the uop list.
  rk(0, "kern2 BASE       ", B(), [], None)
  rk(1, "kern2 CLANG      ", B(), [], None)
  rk(2, "kern2 OPENCL     ", B(), [], None)
  rk(5, "kern2 HIP        ", B(), [], None)
  rk(3, "kern2 METAL      ", B(), [], None)
  rk(0, "kern2 BASE  pref2", B(), [], CALLER)
  rk(0, "kern2 BASE  pref0", B(), [], [])
  rk(2, "kern2 OPENCL pref2", B(), [], CALLER)
  rk(4, "kern2 CUDA  pref2", B(), [], CALLER)
  rk(5, "kern2 HIP   pref2", B(), [], CALLER)
  rk(3, "kern2 METAL pref2", B(), [], CALLER)
  rk(2, "kern2 OPENCL f16 ", B(), [U_half()], CALLER)
  rk(0, "kern2 BASE  vol  ", B(vol0=True), [], None)
  rk(1, "kern2 CLANG vol  ", B(vol0=True), [], None)
  rk(5, "kern2 HIP   spec ", B(), [U_spec()], None)
  rk(5, "kern2 HIP   ockl ", B(), [U_half(), U_sq(dtypes.half), U_sq(dtypes.f32), U_spec()], None)
  rk(5, "kern2 HIP   half ", B(), [U_half(), U_spec()], None)
  rk(5, "kern2 HIP   bf16 ", B(), [U_bf16(), U_spec()], None)
  rk(5, "kern2 HIP   bf16h", B(), [U_bf16(), U_half(), U_spec()], None)
  rk(5, "kern2 HIP   cdna4", B(), [U_bf16(), U_spec()], None, True)
  rk(5, "kern2 HIP   inf  ", B(), [U_inf(), U_spec()], None)
  rk(4, "kern2 CUDA  half ", B(), [U_half()], None)
  rk(4, "kern2 CUDA  bf16 ", B(), [U_bf16()], None)
  rk(4, "kern2 CUDA  fp8  ", B(), [U_fp8()], None)
  rk(0, "kern2 BASE  alu  ", B(alu=True), [], None)
  rk(1, "kern2 CLANG alu  ", B(alu=True), [], None)
  rk(3, "kern2 METAL alu  ", B(alu=True), [], None)
  rk(4, "kern2 CUDA  vecs ", B(), [U_vec(dtypes.half)], None)
  rk(5, "kern2 HIP   vecs ", B(), [U_vec(dtypes.half), U_spec()], None)
  rk(4, "kern2 CUDA  all  ", B(), [U_fp8(), U_half(), U_bf16()], None)

# ------------------------------------------------------------------- idx
# `render_index` reads `self[buf]` and `self[idx]` out of `self.r`, the ctx dict
# `_render` fills. Calling `render_index` out of a full render means SETTING that
# dict by hand, and "B"/"R" are the two names the port's rows print -- which is
# what makes `(B)[R]` and `B.x` and `(B+R)` comparable at all.
def CIX(k): return UOp(Ops.CAST, (UOp.const(k),), dtypes.int32)
def rows_idx():
  # THE BUFFER'S ELEMENT COUNT IS `buf.max_numel()` UPSTREAM, so the fixture is a
  # PARAM of that length in that address space rather than a number. The ROW
  # NAMES are copied from the port verbatim -- they are not `dn(d)`-shaped, and
  # `idx OPENCLsz1 k0 ` has NO SPACE AT ALL, which is what a name rebuilt from
  # `dn()` would silently lose.
  #
  # THE TWO `regadd` ROWS ARE ABSENT AND THE GATE NAMES THEM AS AN EXCLUSION.
  # `render_index`'s non-ALU arm is `strip_parens(self[idx]) if idx.arg ==
  # Ops.ADD else self[idx]`, and MEASURED at HEAD `u.arg == Ops.ADD` is False for
  # every UOp a caller can build: INDEX's arg is `None`, RANGE's is
  # `(AxisType, id)`, REDUCE's is `(Ops.ADD, n)`, CAST's is a DType, SPECIAL's is
  # a string. So the ADD arm is unreachable, `strip_parens` is dead in cstyle.py,
  # and the port's `AReduce{ADD, 0}` fixture is a shape `UOp.arg` does not have.
  SWZ = (("idx BASE  sz1 k0 ", 0, 1, 0), ("idx BASE  sz8 k0 ", 0, 8, 0),
         ("idx BASE  sz1 k1 ", 0, 1, 1), ("idx BASE  sz1 k3 ", 0, 1, 3),
         ("idx CLANG sz1 k0 ", 1, 1, 0), ("idx CLANG sz8 k0 ", 1, 8, 0),
         ("idx OPENCLsz1 k0 ", 2, 1, 0), ("idx OPENCLsz8 k0 ", 2, 8, 0),
         ("idx CUDA  sz8 k0 ", 4, 8, 0), ("idx CUDA  sz16k0", 4, 16, 0),
         ("idx CUDA  sz8 k1 ", 4, 8, 1), ("idx CUDA  sz8 k3 ", 4, 8, 3),
         ("idx HIP   sz1 k0 ", 5, 1, 0), ("idx METAL sz1 k0 ", 3, 1, 0))
  for nm, d, n, k in SWZ:
    buf = UOp.param(0, dtypes.f32, (n,), addrspace=AddrSpace.ALU)
    idx = CIX(k); RD(d).r = {buf: "B", idx: "R"}
    R(nm, RD(d).render_index(idx, buf, idx))
  for nm, d, n in (("idx BASE  lane   ", 0, 1), ("idx CLANG lane   ", 1, 16), ("idx HIP   lane   ", 5, 16)):
    buf = UOp.param(0, dtypes.f32, (n,), addrspace=AddrSpace.ALU)
    lane = UOp(Ops.INDEX, (CIX(0),), dtypes.f32)
    RD(d).r = {buf: "B", lane: "R"}
    R(nm, RD(d).render_index(lane, buf, lane))
  # `idx.arg == Ops.ADD` IS FALSE, so upstream prints `self[idx]` UNCHANGED --
  # and `self[idx]` is whatever the ctx holds. The port's row passes `iname` as a
  # PARAMETER, so the fixture's ctx name must be that parameter, parens included:
  # `"(R)"` is what makes this row `(B+(R))` and `"R"` would make it `(B+R)`.
  buf = UOp.param(0, dtypes.f32, (1,), addrspace=AddrSpace.REG)
  idx = CIX(0); CS.r = {buf: "B", idx: "(R)"}
  R("idx BASE  regnoad", CS.render_index(idx, buf, idx))

def rows_all():
  for f in (rows_tmap, rows_rd, rows_witem, rows_cfo, rows_kern, rows_opt, rows_misc,
            rows_wmma, rows_buft, rows_hip, rows_kern2, rows_idx):
    f()

LANES = {"init": rows_init, "cstyle": rows_cstyle, "cstyle-rows": rows_all}

if __name__ == "__main__":
  LANES[sys.argv[1]]()