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
import dataclasses, sys
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

# CPython's ANSWER IS AN EXCEPTION, AND THE PORT'S ANSWER IS NOT, so a lane has to say which
# of the two it is printing. The port has no exception channel and its marker for "this key is
# not in the dict" is the EMPTY STRING -- stated at cstyle.bend:1074 ("a `KeyError` in Python,
# an empty string here") and at :1149. So:
#
#   PORT_REFUSAL  what a `cstyle-rows` VALUE carries where CPython raised. Comparable.
#   REFUSED_MARK  every refusal, NAMED, on stderr. Never dropped, never in the value.
#
# ⚠ IT WAS `!KeyError` IN THE VALUE AND THAT COST THE LANE ITS WIRING, MEASURED. `!KeyError` is
# a fine sentinel and an uncomparable one: 9 of the 222 row names this lane shares with the port
# printed it, so rebase-gate.py would have reported 9 disagreements and the lane would have been
# BROKEN on every sweep -- a permanently-red lane, which is worse than an unwired one because it
# teaches the reader to read red as normal. Teaching the SHARED reader to translate a token is
# worse still: `!KeyError` means nothing to any other lane, so the rule would be one lane's
# editorial decision living in a parser 38 verdicts share, and rebase-scan-oracles.py -- which
# IMPORTS this parser and computes its own shared/disagree counts -- would then disagree with the
# gate by construction. So the substitution is HERE, in the producer that owns it, and every
# reader sees the same bytes.
#
# WHAT IS GIVEN UP, precisely, because "the oracle called CPython" has to mean something: 9 of the
# 222 shared rows are a refusal rendered as the port's marker rather than as CPython's answer,
# and the other 213 are CPython's own return value. Each of the 9 names itself on stderr, and
# cstyle-gate.py's count_refusals() re-reads those lines, so a lane that stopped reporting
# refusals FAILS rather than passing quietly -- which is why that count is a control and not a
# comment.
PORT_REFUSAL = ""
REFUSED_MARK = "REFUSED "

def refuse(what, why):
  print(f"{REFUSED_MARK}{what}: {why}; the port answers `{PORT_REFUSAL}` for this cell, so the "
        f"row is GATED and not skipped", file=sys.stderr)
  return PORT_REFUSAL

def call(fn, *a, **kw):
  """Upstream's OWN call, and its answer. A `KeyError` is not swallowed -- it is REPORTED, and
  the port's marker is returned, so a lane that DIED and a lane that was REFUSED cannot be
  confused. Any OTHER exception propagates and the lane dies, because a lane that dies cannot be
  mistaken for a lane that agrees."""
  try:
    return fn(*a, **kw)
  except KeyError as e:
    return refuse(f"{getattr(fn, '__qualname__', fn)}({', '.join(map(repr, a))})", f"KeyError: {e}")

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
  t = Target(f"TEST {arch}")
  # MEASURED: `Target("TEST gfx950").arch` is `''` -- the string went to `.device` --
  # so `is_cdna4(arch)` is False for EVERY renderer built that way and
  # `HIPRenderer.render_kernel` takes the `unsigned short` branch on a target whose
  # name says gfx950. `Target` is a frozen dataclass, so this is a `replace`.
  o.target = dataclasses.replace(t, arch=arch)
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

def fallback_renderer(r, dt):
  """A renderer that is `r` with ONE dict entry changed: `type_map[dt] =
  type_map.get(dt, dt.name)`. Every other attribute is `r`'s own.

  WHY: at HEAD `_render_dtype` does `self.type_map[dtype]` (cstyle.py:190-191) and
  four of the six devices have NO fp8 entry, so the call RAISES. The port has no
  exception channel and answers the `.get` reading instead, and the honest way to
  ask "what would upstream print under that reading" is to let UPSTREAM print it
  with the one entry patched -- not to write the seven cells out here, which would
  be a def of the thing under test. The refusal itself is reported on stderr as a
  `REFUSED` line so it cannot read as agreement.
  """
  o = object.__new__(type(r))
  o.__dict__.update(r.__dict__)
  o.type_map = {**r.type_map, dt: r.type_map.get(dt, dt.name)}
  return o

def rows_rd():
  # THE SEVEN DTYPES of the port's rd block, in its order. `fp8e4m3` IS HERE and
  # on four of the six devices `_render_dtype` REFUSES: HEAD's `type_map` has no
  # fp8 entry above CUDA. The refusal is REPORTED (stderr, one line per cell group)
  # and the row is answered by upstream's own `_render_dtype` under the `.get`
  # reading, so it is gated rather than skipped.
  for d in range(6):
    for dt in (dtypes.f32, dtypes.half, dtypes.bfloat16, dtypes.bool, dtypes.uint8,
               dtypes.fp8e4m3, dtypes.int32):
      r = RD(d)
      if dt not in r.type_map:
        print(f"{REFUSED_MARK}rd {dn(d)} {dt.name}: {len(RD_CELLS)} `_render_dtype` calls "
              f"raise KeyError: dtypes.{dt.name} is not in {type(r).__name__}.type_map "
              f"at HEAD; the row is answered under the .get reading", file=sys.stderr)
        r = fallback_renderer(r, dt)
      cells = [call(r._render_dtype, dt, sz, a, mut, ptr, shp) for sz, a, mut, ptr, shp in RD_CELLS]
      R(f"rd {dn(d)} {dt.name}", "|".join(cells))

def rows_witem():
  # `code_for_workitem[k](n)` -- cstyle.py:47, `code_for_workitem[x.arg[0]](x.arg[-1])`. The BASE
  # and CLANG maps are `{}` at HEAD, so `__getitem__` is a KeyError and `call()` reports it and
  # returns the port's marker; the `(0)` argument is applied only when the key EXISTS, because
  # `(0)` on the marker is a TypeError and a TypeError kills the lane rather than answering it.
  # TWO cells joined by the port's own " / ", so a refusing row is TWO empty cells -- folding them
  # into one would have made 2 of the 222 shared rows disagree (`[ / ]` against `[]`), and a
  # disagreement manufactured by the oracle's own formatting is the same species as one
  # manufactured by the port: both are red for a reason that is not the thing under test.
  for d in range(6):
    r = RD(d)
    if r.code_for_workitem:
      cells = [call(r.code_for_workitem.__getitem__, k)(0) for k in ("g", "l")]
    else:
      # The refusal is reported HERE, under the ROW name, rather than by `call()` under the name
      # of a bound `__getitem__`: `dict.__getitem__('g')` says a dict refused, and cstyle-gate's
      # UNREPORTED-REFUSALS check looks for the ROW, so a refusal under the wrong name reads as
      # a row compared against an assertion. Both cells refuse together, and the row keeps its
      # own " / " so the answer stays two empty cells -- one empty cell was 2 of 222 rows
      # disagreeing (`[ / ]` against `[]`), red for a reason that is not the thing under test.
      refuse(f"witem {dn(d)}", "code_for_workitem is EMPTY at HEAD (cstyle.py:131), so "
                              "code_for_workitem['g'] and ['l'] are BOTH a KeyError")
      cells = [PORT_REFUSAL] * 2
    R(f"witem {dn(d)}", " / ".join(cells))

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
    # `code_for_op` is a PLAIN dict (cstyle.py:143) and `render_kernel` reads it as
    # `ctx.code_for_op[x.op](...)` (cstyle.py:64), so a missing op is a `KeyError` there. `.get`
    # is how this lane ASKS without raising, and `None` is its answer for "no such op".
    fn = r.code_for_op.get(op)
    args = (XS[0],) if op in UN else (XS[0], XS[1]) if op in BIN else tuple(XS)
    R(f"cfo {dev} {op.name} {tag}",
      refuse(f"cfo {dev} {op.name} {tag}",
             f"Ops.{op.name} is not in {type(r).__name__}.code_for_op at HEAD") if fn is None
      else fn(*args, DT[tag]))
  # THE TWO `cfo_where_row` ROWS: no op and no tag in the key, because
  # `cfo_where_row` prints neither.
  for dev in ("BASE ", "CLANG"):
    r = RD(NIDX[dev])
    R(f"cfo {dev}", r.code_for_op[Ops.WHERE](*XS, dtypes.f32))

def rows_kern():
  # ⚠ `lb {lb}`, NOT `lb={lb}`. A ROW NAME MUST NOT CONTAIN `=`, because
  # rebase-gate.py:437 splits a line on its FIRST `=` and keeps the head as the name:
  # `kern CUDA  lb=1 = [...]` is then named `kern CUDA  lb` and the lb=1 and lb=4 rows
  # COLLIDE ON ONE KEY, losing a measurement (MEASURED on the pre-rename port lane:
  # 227 rows read as 225 names, both survivors being the lb=4 values). The value's
  # upstream name is `launch_bounds` (cstyle.py:163); `lb` is the token, `=` was the
  # separator, and the separator was the defect. This string and cstyle.bend's
  # `kern_row` are ONE coordinate -- renaming one side alone turns 8 green rows
  # into 8 ghost/stray failures, which is the intended failure, not a regression.
  for d, lb in ((0, 1), (1, 4), (2, 1), (3, 1), (4, 1), (4, 4), (5, 1), (5, 4)):
    R(f"kern {dn(d)} lb {lb}", call(RD(d).kernel_typedef.format, launch_bounds=lb))

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
        cells.append(sig(RD(d), UOp.param(0, dtypes.f32, (), addrspace=a, volatile=vol)))
    cells.append(sig(RD(d), UOp.param(0, dtypes.f32, (), addrspace=AddrSpace.LOCAL)))
    R(f"buft {dn(d)}", "|".join(cells))

def sig(r, u):
  """THE ONE BUFFER ARGUMENT OF A KERNEL, read out of the SIGNATURE `render_kernel`
  emitted. The signature is cut at `E_4(` and then to the first `)` AFTER that
  point -- the first `)` in the whole string is inside CUDA's `#define INFINITY
  (__int_as_float(0x7f800000))`, which is what made this read `|||||` for two
  devices on the first run."""
  s = r.render_kernel("E_4", ["  ;"], [("v0", (u, True))], [], None)
  k = s.index("E_4(") + 4
  return s[k:s.index(")", k)]

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