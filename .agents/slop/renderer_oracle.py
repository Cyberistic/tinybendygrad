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
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target
from tinygrad.uop.ops import UOp, Ops, KernelInfo, AxisType, graph_rewrite
from tinygrad.uop.weak import pm_lower_weak
from tinygrad.renderer import Renderer, Estimates, with_storage
from tinygrad.renderer.cstyle import (CStyleLanguage, OpenCLRenderer, ClangRenderer, MetalRenderer,
                                     CUDARenderer, HIPRenderer)

def R(nm, got):
  # cstyle.bend's `esc_row`, byte for byte: `String.join(String.split(s, '\n'), "\\n")`. A
  # lane that prints a MULTI-LINE value is shredded by any differ that reads one row per line
  # -- and MEASURED on this file unescaped, 96 physical lines become 33 "rows" of which 18 are
  # line noise (`float val0`, `*(data1_4+0)`, `int g0`, a `for (int gidx0` whose value is the
  # tail of the loop header). The port escapes; this oracle did not; that asymmetry is the bug.
  print(nm + " = [" + got.replace("\n", "\\n") + "]")

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

if __name__ == "__main__":
  (rows_init if sys.argv[1] == "init" else rows_cstyle)()