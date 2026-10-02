#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/renderer/nir_llvmir.bend.

Every row is one line:  <name> = [BEND-VALUE]   py=[CPYTHON-VALUE]
The Bend file prints the same lines; `diff` of the two lane outputs is the gate.
Every `py=` half is COMPUTED HERE -- nothing is transcribed by hand.

Run from the repo root:
    .venv/bin/python .agents/slop/nl/nl-oracle.py rows > .agents/slop/nl/py1.txt
    .venv/bin/python .agents/slop/nl/nl-oracle.py bend > .agents/slop/nl/stage1.bend

`bend` prints the STAGE 1 ROW-BUILDER SOURCE for the .bend file, so the `py=`
literals in the port are generated rather than typed. That is the whole point:
`cstyle.bend` arrived with 215 hand-written expectations of which seventeen were
wrong.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import Ops
from tinygrad.renderer import Renderer
from tinygrad.renderer import llvmir as L
from tinygrad.helpers import Target

# ---------------------------------------------------------------- the grids
# `dtypes.all`'s own order, so a joined string on both sides is positional.
ALL = list(dtypes.all)
# the grid for `lcast` and for the `lop` keys. `void` is in `lcast`'s grid
# because CPython's `lcast` answers NotImplementedError for it, and the port
# has no exceptions, so the wall needs a row.
CA = [dtypes.void, dtypes.half, dtypes.bfloat16, dtypes.float, dtypes.double, dtypes.bool,
      dtypes.int8, dtypes.int16, dtypes.int32, dtypes.int64,
      dtypes.uint8, dtypes.uint16, dtypes.uint32, dtypes.uint64]
# The 13-op union of `unsigned_lop | signed_lop | float_lop`, in the dict's own
# insertion order -- which is unsigned_lop's, since `signed_lop` and `float_lop`
# only override VALUES.
OPS13 = [Ops.ADD, Ops.MUL, Ops.CDIV, Ops.CMOD, Ops.CMPLT, Ops.CMPNE, Ops.CMPEQ,
         Ops.OR, Ops.AND, Ops.XOR, Ops.SHL, Ops.SHR, Ops.FDIV]
# `dtypes.all` plus `void` plus the two weak dtypes: `ldt`'s dict has no key for
# either weak dtype and CPython raises, which is a row.
LDD = [dtypes.void] + ALL + [dtypes.weakfloat, dtypes.weakint]


def row(nm, got, want):
  return f"{nm} = [{got}]   py=[{want}]\n"


def j(x):
  return ",".join(str(v) for v in x)


def mx(v):
  """`shared_max` is an int and the maxima are tuples; one row each, in one spelling."""
  return "None" if v is None else (str(v) if isinstance(v, int) else j(v))


# ================================================================ llvmir.py
# ---------------------------------------------------------------- ldt
def ldt_rows():
  out = ""
  for d in LDD:
    try:
      got = L.ldt(d)
    except Exception as e:
      got = type(e).__name__
    out += row(f"ldt {d.name}", got, got)
  # `ptr` and `count`. `count > 1` nests `ldt(dt, 1, ptr)` with ptr=False, so
  # `ldt 4 ptr float` is `<4 x float>*` and NOT `<4 x float**>`.
  for d in (dtypes.float, dtypes.int32, dtypes.void, dtypes.bool, dtypes.half, dtypes.bfloat16):
    got = L.ldt(d, ptr=True)
    out += row(f"ldt ptr {d.name}", got, got)
  for cnt, d, ptr in ((0, dtypes.float, False), (1, dtypes.float, False), (2, dtypes.float, False),
                      (4, dtypes.float, False), (8, dtypes.double, False), (16, dtypes.half, False),
                      (4, dtypes.float, True), (2, dtypes.int32, True), (1, dtypes.float, True),
                      (4, dtypes.bfloat16, True)):
    got = L.ldt(d, cnt, ptr)
    out += row(f"ldt {cnt} {'ptr' if ptr else '   '} {d.name}", got, got)
  return out


# ---------------------------------------------------------------- lcast
def lcast_rows():
  """BOTH directions of the 14x14 grid, so a mutation is localised by dtype.

  `lcast.a <a>` reads one input row (all 14 outputs), `lcast.b <b>` reads one
  output column (all 14 inputs). Two rows with the same text in the wrong place
  are a diff, because the gate is byte-positional.
  """
  out = ""
  for a in CA:
    cs = []
    for b in CA:
      try:
        cs.append(f"{b.name}={L.lcast(a, b)}")
      except Exception as e:
        cs.append(f"{b.name}={type(e).__name__}")
    out += row(f"lcast.a {a.name}", ",".join(cs), ",".join(cs))
  for b in CA:
    cs = []
    for a in CA:
      try:
        cs.append(f"{a.name}={L.lcast(a, b)}")
      except Exception as e:
        cs.append(f"{a.name}={type(e).__name__}")
    out += row(f"lcast.b {b.name}", ",".join(cs), ",".join(cs))
  return out


# ---------------------------------------------------------------- lop
def lop_rows():
  out = ""
  out += row("lop.flags", repr(L.flags), repr(L.flags))
  for nm, tbl in (("unsigned", L.unsigned_lop), ("signed", L.signed_lop), ("float", L.float_lop)):
    cs = [f"{o.name}={v}" for o, v in tbl.items()]
    out += row(f"lop.{nm}", ",".join(cs), ",".join(cs))
    out += row(f"lop.{nm}.len", str(len(tbl)), str(len(tbl)))
  # one row per dtype, carrying that dtype's WHOLE table in dict order
  for d in ALL:
    t = L.lop[d]
    cs = [f"{o.name}={t[o]}" for o in OPS13 if o in t]
    out += row(f"lop {d.name}", ",".join(cs), ",".join(cs))
  # one row per op, across every dtype -- the op direction of the same grid
  for o in OPS13:
    cs = [f"{d.name}={L.lop[d][o]}" for d in ALL if o in L.lop[d]]
    out += row(f"lop.op {o.name}", ",".join(cs), ",".join(cs))
  out += row("lop.keys", j(d.name for d in L.lop), j(d.name for d in L.lop))
  out += row("lop.keys.len", str(len(L.lop)), str(len(L.lop)))
  return out


# ---------------------------------------------------------------- constants
def const_rows():
  """The class constants, read off the CLASS and not an instance.

  A renderer is a `Data` record of its options and these ARE the options, so
  every `got=` half on the Bend side is a RECORD READER and not a literal. A
  constant row whose `got=` is the same literal as its `py=` restates the code,
  which is the thing the gate exists to prevent.

  The three `*.patterns` rows are NOT here. They count `base_rewrite`'s and
  `AMDLLVMRenderer.string_rewrite`'s rules, and the port has no rule table until
  STAGE 2 -- so they are stage-2 rows and the header says so. A row that is RED
  for a named wall is noise.
  """
  out = ""
  out += row("llvm.string_rewrite", "ABSENT", "ABSENT")
  out += row("Renderer.suffix", repr(Renderer.suffix), repr(Renderer.suffix))
  for nm in ("has_local", "has_shared"):
    out += row(f"Renderer.{nm}", str(getattr(Renderer, nm)), str(getattr(Renderer, nm)))
  for nm in ("global_max", "local_max", "global_prod_max", "shared_max"):
    out += row(f"Renderer.{nm}", mx(getattr(Renderer, nm, None)), mx(getattr(Renderer, nm, None)))
  for cls, nm in ((L.LLVMRenderer, "llvm"), (L.CPULLVMRenderer, "cpullvm"), (L.AMDLLVMRenderer, "amd")):
    out += row(f"{nm}.has_local", str(cls.has_local), str(cls.has_local))
    try:
      out += row(f"{nm}.abi", str(getattr(cls, "abi")), str(getattr(cls, "abi")))
    except AttributeError:
      out += row(f"{nm}.abi", "AttributeError", "AttributeError")
    out += row(f"{nm}.suffix", repr(cls.suffix), repr(cls.suffix))
    for k in ("global_max", "local_max", "global_prod_max", "shared_max"):
      out += row(f"{nm}.{k}", mx(getattr(cls, k, None)), mx(getattr(cls, k, None)))
    out += row(f"{nm}.code_for_op", ",".join(sorted(o.name for o in cls.code_for_op)),
               ",".join(sorted(o.name for o in cls.code_for_op)))
    out += row(f"{nm}.code_for_op.len", str(len(cls.code_for_op)), str(len(cls.code_for_op)))
  out += row("llvm_intrinsics", ",".join(f"{o.name}={v}" for o, v in L.llvm_intrinsics.items()),
             ",".join(f"{o.name}={v}" for o, v in L.llvm_intrinsics.items()))
  for k, f in L.code_for_workitem.items():
    for i in (0, 1, 2):
      out += row(f"code_for_workitem {k} {i}", f(i), f(i))
  # `barrier` holds THREE newlines, so one row per line plus a count: a dropped
  # line is a moved row rather than a re-wrapped one, and `barrier[3]` is the
  # EMPTY tail that the trailing newline produces.
  bl = L.barrier.split("\n")
  out += row("barrier.lines", str(len(bl)), str(len(bl)))
  for i, ln in enumerate(bl):
    out += row(f"barrier[{i}]", ln, ln)
  return out


# ---------------------------------------------------------------- supported_dtypes
def sd_rows():
  out = ""

  class Base(Renderer):
    def __init__(self): self.target = None

  class CPU(L.CPULLVMRenderer):
    def __init__(self, target): self.target = target

  class AMD(L.AMDLLVMRenderer):
    def __init__(self, target): self.target = target

  got = j(sorted(d.name for d in Base().supported_dtypes()))
  out += row("sd base", got, got)
  # CPULLVM: `d != bfloat16 or arch.startswith(("x86","arm"))` AND
  # `d != half or OSX` AND `d not in fp8s`. `llvmir.OSX` is an IMPORTED name, so
  # the module attribute is what the method reads and it is what we set.
  for arch in ("LLVM", "x86_64", "arm", "riscv64"):
    for osx in (True, False):
      L.OSX = osx
      got = j(sorted(d.name for d in CPU(Target(interface="", device="CPU", arch=arch)).supported_dtypes()))
      out += row(f"sd cpullvm {arch} osx={osx}", got, got)
  L.OSX = True
  # AMD: `d not in fp8s or d in amd_fp8s(arch)`. gfx942 is the only arch here
  # whose `amd_fp8s` is non-empty, and it is the FNUZ pair.
  for arch in ("gfx1100", "gfx942", "gfx1200", "gfx1201"):
    got = j(sorted(d.name for d in AMD(Target(interface="", device="HIP", arch=arch)).supported_dtypes()))
    out += row(f"sd amd {arch}", got, got)
  return out


# ---------------------------------------------------------------- the naming walk's names
def name_rows():
  """`%data{slot}` and `%{'local' if LOCAL else 'reg'}_{slot}` (llvmir.py:178,181).

  Only LOCAL is spelled; GLOBAL, REG and ALU all read `reg`, which is a
  three-way agreement a single inverted test would break.
  """
  out = ""
  for s in (0, 3, 7):
    got = f"%data{s}"
    out += row(f"name param {s}", got, got)
  for a, an in ((AddrSpace.GLOBAL, "global"), (AddrSpace.LOCAL, "local"), (AddrSpace.REG, "reg"), (AddrSpace.ALU, "alu")):
    got = f"%{'local' if a == AddrSpace.LOCAL else 'reg'}_5"
    out += row(f"name buffer {an}", got, got)
  return out


# ---------------------------------------------------------------- base_rewrite[0]
# llvmir.py:79-80. The x name, x dtype, x count, src0 name, src1 dtype, src1 name.
GEP_FMT = "  {x} = getelementptr inbounds {t}, {tp} {s0}, {t1} {s1}"
GEP = (
       ("%v3", dtypes.float, 1, "%data0", dtypes.int32, "%v2"),
       ("%v0", dtypes.float32, 4, "%reg_1", dtypes.int64, "%v1"),
       ("%v7", dtypes.half, 1, "%local_2", dtypes.uint32, "%v6"),
       ("%v9", dtypes.bfloat16, 8, "%data1", dtypes.uint64, "%v8"))


def gep_rows():
  out = ""
  for xn, d, cnt, s0, d1, s1 in GEP:
    got = GEP_FMT.format(x=xn, t=L.ldt(d, cnt), tp=L.ldt(d, cnt, ptr=True), s0=s0, t1=L.ldt(d1), s1=s1)
    out += row(f"gep {xn} {d.name}x{cnt} {d1.name}", got, got)
  return out


# ---------------------------------------------------------------- the AMD fp8 prefix
def f32fp8_rows():
  """`AMDLLVMRenderer.render`'s `f32_to_fp8` prefix (llvmir.py:252-263).

  The prefix is asked of the REAL method with a recording `_render_kernel`, so
  the `.replace(": ", ":\\n  ")` and the FOUR trailing spaces after
  `float -{fp8_max})` are CPython's own bytes. Line 12 of gfx942 carries those
  spaces and the gate does NOT strip them: both sides come from here.
  """
  got = {}

  class Shell(L.AMDLLVMRenderer):
    def __init__(self, arch):
      self.target = Target(interface="", device="HIP", arch=arch)
      self.seen = None

    def _render_kernel(self, uops, prefix=None):
      self.seen = prefix
      return ((), "KERNEL")

    def _render_footer(self, uops):
      return "FOOTER"

  from tinygrad.uop.ops import UOp, ParamArg

  def fp8buf(dt):
    return UOp(Ops.BUFFER, src=UOp.device_range_src('HIP'), arg=ParamArg(0, dt, 4))

  s = Shell("gfx942")
  s.render([])
  out = row("fp8 prefix none", str(len(s.seen)), str(len(s.seen)))
  s.render([fp8buf(dtypes.fp8e4m3fnuz)])
  ls = s.seen[0].split("\n")
  out += row("fp8 prefix lines", str(len(ls)), str(len(ls)))
  for i, ln in enumerate(ls):
    out += row(f"fp8 prefix[{i}]", ln, ln)
  # `f32show 240.0` IS THE ONE ROW WHOSE `got=` IS TRANSCRIBED FROM THE BEND
  # LANE, and that is the POINT of it: Bend's `F32.show(240.0)` is `240` and
  # CPython's `str(240.0)` is `240.0`, so there is no oracle for it and the `py=`
  # half is the literal marker `BEND-ONLY`. Its whole content is the NAMES of the
  # gap -- the `.0` in llvmir.py's `{fp8_max}` is a deliberate spelling, and
  # `fp8 prefix[12]` is the row that pins CPython's side of it.
  out += row("f32show 240.0", "240", "BEND-ONLY")
  return out


def stage1():
  return (ldt_rows() + lcast_rows() + lop_rows() + const_rows() + sd_rows() + name_rows()
          + gep_rows() + f32fp8_rows())


# ================================================================ the generator
def q(s):
  """A Bend string literal for CPython's `repr`-free text."""
  return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def bname(d):
  """The `S.Dt` constructor call for a real DType."""
  return {dtypes.void: "S.void()", dtypes.weakint: "S.weakint()", dtypes.weakfloat: "S.weakfloat()",
          dtypes.bool: "S.boolean()", dtypes.int8: "S.int8()", dtypes.uint8: "S.uint8()",
          dtypes.int16: "S.int16()", dtypes.uint16: "S.uint16()", dtypes.int32: "S.int32()",
          dtypes.uint32: "S.uint32()", dtypes.int64: "S.int64()", dtypes.uint64: "S.uint64()",
          dtypes.fp8e4m3: "S.fp8e4m3()", dtypes.fp8e5m2: "S.fp8e5m2()",
          dtypes.fp8e4m3fnuz: "S.fp8e4m3fnuz()", dtypes.fp8e5m2fnuz: "S.fp8e5m2fnuz()",
          dtypes.half: "S.half()", dtypes.bfloat16: "S.bfloat16()",
          dtypes.float32: "S.single()", dtypes.float64: "S.double()"}[d]


def bend_lcast():
  """`r_lca`/`r_lcb`: the 14x14 grid as TWO joined rows per direction."""
  out = ""
  for tag, seq in (("a", CA), ("b", CA)):
    parts = []
    for a in seq:
      cs = []
      for b in seq:
        if tag == "a":
          try: v = L.lcast(a, b)
          except Exception as e: v = type(e).__name__
        else:
          try: v = L.lcast(b, a)
          except Exception as e: v = type(e).__name__
        cs.append(f"{b.name if tag == 'a' else b.name}={v}")
      parts.append(f'r_lc{tag}({q(a.name)}, {bname(a)}, {q(",".join(cs))})')
    out += f"def r_lc{tag}s() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  return out


BENDOP = {"ADD": "O.OpsADD{}", "MUL": "O.OpsMUL{}", "CDIV": "O.OpsCDIV{}", "CMOD": "O.OpsCMOD{}",
          "CMPLT": "O.OpsCMPLT{}", "CMPNE": "O.OpsCMPNE{}", "CMPEQ": "O.OpsCMPEQ{}", "OR": "O.OpsOR{}",
          "AND": "O.OpsAND{}", "XOR": "O.OpsXOR{}", "SHL": "O.OpsSHL{}", "SHR": "O.OpsSHR{}",
          "FDIV": "O.OpsFDIV{}"}


def bend_lop():
  out = ""
  parts = [f'r_lop({q(d.name)}, {bname(d)}, {q(",".join(f"{o.name}={L.lop[d][o]}" for o in OPS13 if o in L.lop[d]))})'
           for d in ALL]
  out += "def r_lops() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  parts = [f'r_lopo({q(o.name)}, {BENDOP[o.name]}, {q(",".join(f"{d.name}={L.lop[d][o]}" for d in ALL if o in L.lop[d]))})'
           for o in OPS13]
  out += "def r_lopos() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  return out


def bend():
  """The STAGE 1 ROW-BUILDER SOURCE, generated from the run above."""
  out = ""
  # ---- ldt
  parts = []
  for d in LDD:
    try: v = L.ldt(d)
    except Exception as e: v = type(e).__name__
    parts.append(f'r_ldt({q(d.name)}, {bname(d)}, {q(v)})')
  for d in (dtypes.float, dtypes.int32, dtypes.void, dtypes.bool, dtypes.half, dtypes.bfloat16):
    parts.append(f'r_ldtp({q(d.name)}, {bname(d)}, {q(L.ldt(d, ptr=True))})')
  for cnt, d, ptr in ((0, dtypes.float, False), (1, dtypes.float, False), (2, dtypes.float, False),
                      (4, dtypes.float, False), (8, dtypes.double, False), (16, dtypes.half, False),
                      (4, dtypes.float, True), (2, dtypes.int32, True), (1, dtypes.float, True),
                      (4, dtypes.bfloat16, True)):
    lbl = f"{cnt} {'ptr' if ptr else '   '} {d.name}"
    parts.append(f'r_ldtn({q(lbl)}, {bname(d)}, {cnt}, {"True{}" if ptr else "False{}"}, {q(L.ldt(d, cnt, ptr))})')
  out += "def r_ldts() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  # ---- lcast
  out += bend_lcast()
  # ---- lop
  out += "def r_lopf() -> String:\n  String.concat(["
  fl = [f'r({q("lop.flags")}, q1(ldt.flags()), {q(repr(L.flags))})']
  for nm, tbl, d, ln, ops in (("unsigned", L.unsigned_lop, bname(dtypes.bool), "oplen", "lops.uf()"),
                              ("signed", L.signed_lop, bname(dtypes.int8), "oplen", "lops.uf()"),
                              ("float", L.float_lop, bname(dtypes.float32), "oplen", "lops.sf()")):
    fl.append(f'r({q("lop." + nm)}, lop.row({d}), {q(j(f"{o.name}={v}" for o, v in tbl.items()))})')
    fl.append(f'r({q("lop." + nm + ".len")}, U32.show({ln}({ops})), {q(str(len(tbl)))})')
  out += ", ".join(fl) + "])\n\n"
  out += "def r_lopz() -> String:\n  String.concat(["
  out += ", ".join([f'r({q("lop.keys")}, unames(lop.keys()), {q(j(d.name for d in L.lop))})',
                    f'r({q("lop.keys.len")}, U32.show(dtlen(lop.keys())), {q(str(len(L.lop)))})'])
  out += "])\n\n"
  out += bend_lop()
  # ---- constants. Every `got=` is a RECORD READER, never a literal.
  parts = [f'r({q("llvm.string_rewrite")}, "ABSENT", "ABSENT")']
  parts.append(f'r({q("Renderer.suffix")}, q1(Llvm.suffix(Renderer_of())), {q(repr(Renderer.suffix))})')
  parts.append(f'r({q("Renderer.has_local")}, bs(Llvm.has_local(Renderer_of())), {q(str(Renderer.has_local))})')
  parts.append(f'r({q("Renderer.has_shared")}, bs(Llvm.has_shared(Renderer_of())), {q(str(Renderer.has_shared))})')
  for nm, rd in (("global_max", "gmax"), ("local_max", "lmax")):
    parts.append(f'r({q("Renderer." + nm)}, ushow(Llvm.{rd}(Renderer_of())), {q(j(getattr(Renderer, nm)))})')
  for nm, hs, rd in (("global_prod_max", "gpmax_has", "gpmax"),):
    parts.append(f'r({q("Renderer." + nm)}, pmax(Renderer_of()), {q(mx(getattr(Renderer, nm, None)))})')
  parts.append(f'r({q("Renderer.shared_max")}, U32.show(Llvm.smax(Renderer_of())), {q(str(Renderer.shared_max))})')
  for ctor, cls, nm in ((("llvm_of()"), L.LLVMRenderer, "llvm"), ("cpullvm_of()", L.CPULLVMRenderer, "cpullvm"),
                        ("amd_of()", L.AMDLLVMRenderer, "amd")):
    parts.append(f'r({q(nm + ".has_local")}, bs(Llvm.has_local({ctor})), {q(str(cls.has_local))})')
    try:
      parts.append(f'r({q(nm + ".abi")}, abi_str(Llvm.has_abi({ctor}), Llvm.abi({ctor})), {q(str(getattr(cls, "abi")))})')
    except AttributeError:
      parts.append(f'r({q(nm + ".abi")}, abi_str(Llvm.has_abi({ctor}), Llvm.abi({ctor})), "AttributeError")')
    parts.append(f'r({q(nm + ".suffix")}, q1(Llvm.suffix({ctor})), {q(repr(cls.suffix))})')
    for k, rd in (("global_max", "gmax"), ("local_max", "lmax")):
      parts.append(f'r({q(nm + "." + k)}, ushow(Llvm.{rd}({ctor})), {q(j(getattr(cls, k)))})')
    parts.append(f'r({q(nm + ".global_prod_max")}, pmax({ctor}), {q(mx(getattr(cls, "global_prod_max", None)))})')
    parts.append(f'r({q(nm + ".shared_max")}, U32.show(Llvm.smax({ctor})), {q(str(cls.shared_max))})')
    cfo = "cfo_base()" if nm != "amd" else "cfo_amd()"
    cs = ",".join(sorted(o.name for o in cls.code_for_op))
    parts.append(f'r({q(nm + ".code_for_op")}, opnames({cfo}), {q(cs)})')
    parts.append(f'r({q(nm + ".code_for_op.len")}, U32.show(oplen({cfo})), {q(str(len(cls.code_for_op)))})')
  parts.append(f'r({q("llvm_intrinsics")}, intr_names(), {q(",".join(f"{o.name}={v}" for o, v in L.llvm_intrinsics.items()))})')
  for k, f in L.code_for_workitem.items():
    for i in (0, 1, 2):
      parts.append(f'r({q(f"code_for_workitem {k} {i}")}, wi({"True{}" if k == "l" else "False{}"}, {i}), {q(f(i))})')
  bl = L.barrier.split("\n")
  parts.append(f'r({q("barrier.lines")}, U32.show(slen(barrier())), {q(str(len(bl)))})')
  for i, ln in enumerate(bl):
    parts.append(f'r({q(f"barrier[{i}]")}, nth(barrier(), {i}), {q(ln)})')
  out += "def r_consts() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  # ---- supported_dtypes
  parts = []

  class Base(Renderer):
    def __init__(self): self.target = None

  class CPU(L.CPULLVMRenderer):
    def __init__(self, target): self.target = target

  class AMD(L.AMDLLVMRenderer):
    def __init__(self, target): self.target = target

  parts.append(f'r_sdb({q(j(sorted(d.name for d in Base().supported_dtypes())))})')
  # CPULLVM reads THREE things: `arch.startswith(("x86","arm"))` (a Bool the port
  # takes as a parameter, since Bend has no string prefix test that is also a
  # Python `startswith`), `llvmir.OSX` (a Bool), and `d not in dtypes.fp8s`.
  for arch, x86 in (("LLVM", False), ("x86_64", True), ("arm", True), ("riscv64", False)):
    for osx in (True, False):
      L.OSX = osx
      got = j(sorted(d.name for d in CPU(Target(interface="", device="CPU", arch=arch)).supported_dtypes()))
      parts.append(f'r_sdcpu({q(f"{arch} osx={osx}")}, {"True{}" if x86 else "False{}"}, {"True{}" if osx else "False{}"}, {q(got)})')
  L.OSX = True
  # AMD reads ONE thing: membership in `amd_fp8s(arch)`, whose only non-empty
  # answer on this tree is gfx942's FNUZ pair.
  for arch in ("gfx1100", "gfx942", "gfx1200", "gfx1201"):
    got = j(sorted(d.name for d in AMD(Target(interface="", device="HIP", arch=arch)).supported_dtypes()))
    parts.append(f'r_sdamd({q(arch)}, {"True{}" if arch == "gfx942" else "False{}"}, {q(got)})')
  out += "def r_sds() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  # ---- naming
  parts = []
  for s in (0, 3, 7):
    parts.append(f'r_nm({q(f"param {s}")}, {s}, {q(f"%data{s}")})')
  for a, an in ((AddrSpace.GLOBAL, "global"), (AddrSpace.LOCAL, "local"), (AddrSpace.REG, "reg"), (AddrSpace.ALU, "alu")):
    got = f"%{'local' if a == AddrSpace.LOCAL else 'reg'}_5"
    parts.append(f'r_nmbuf({q(an)}, {"True{}" if a == AddrSpace.LOCAL else "False{}"}, 5, {q(got)})')
  out += "def r_nms() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  # ---- getelementptr
  parts = []
  for xn, d, cnt, s0, d1, s1 in GEP:
    got = GEP_FMT.format(x=xn, t=L.ldt(d, cnt), tp=L.ldt(d, cnt, ptr=True), s0=s0, t1=L.ldt(d1), s1=s1)
    parts.append(f'r_gep({q(f"{xn} {d.name}x{cnt} {d1.name}")}, {q(xn)}, {bname(d)}, {cnt}, {q(s0)}, {bname(d1)}, {q(s1)}, {q(got)})')
  out += "def r_geps() -> String:\n  String.concat([" + ", ".join(parts) + "])\n\n"
  # ---- fp8 prefix
  from tinygrad.uop.ops import UOp, ParamArg

  def fp8buf(dt):
    return UOp(Ops.BUFFER, src=UOp.device_range_src('HIP'), arg=ParamArg(0, dt, 4))

  class Shell(L.AMDLLVMRenderer):
    def __init__(self, arch):
      self.target = Target(interface="", device="HIP", arch=arch)
      self.seen = None

    def _render_kernel(self, uops, prefix=None):
      self.seen = prefix
      return ((), "KERNEL")

    def _render_footer(self, uops):
      return "FOOTER"

  s = Shell("gfx942")
  s.render([])
  mxv = str(240.0)
  # `fp8 max cpython` is GONE and its place is `f32show 240.0`. A row whose
  # `got=` is the same literal the port substitutes is a row that restates the
  # code; the SPELLING `240.0` is already pinned by `fp8 prefix[12]`, and what
  # needed naming was the GAP -- `F32.show(240.0)` is `240`, so the `.0` is a
  # deliberate spelling rather than an oversight. That is the named BEND-ONLY
  # row.
  parts = [f'r({q("fp8 prefix none")}, U32.show(slen(fp8_prefix(False{{}}, {q(mxv)}))), {q(str(len(s.seen)))})']
  s.render([fp8buf(dtypes.fp8e4m3fnuz)])
  ls = s.seen[0].split("\n")
  pl = [f'r({q("fp8 prefix lines")}, U32.show(slen(fp8_prefix(True{{}}, {q(mxv)}))), {q(str(len(ls)))})']
  for i, ln in enumerate(ls):
    pl.append(f'r({q(f"fp8 prefix[{i}]")}, {f"nth(fp8_prefix(True{{}}, {q(mxv)}), {i})"}, {q(ln)})')
  pl.append(f'r({q("f32show 240.0")}, F32.show(240.0), "BEND-ONLY")')
  out += "def r_fps() -> String:\n  String.concat([" + ", ".join(parts + pl) + "])\n\n"
  return out


def rows():
  return stage1()


if __name__ == "__main__":
  what = sys.argv[1] if len(sys.argv) > 1 else "rows"
  # FRAMING: every `row` already ends in "\n" and the Bend side prints the whole
  # table with one `IO.print`, which appends its own. So the oracle needs
  # exactly one more -- the same one wgsl-oracle.py's per-row `print` supplies.
  sys.stdout.write({"rows": rows, "stage1": stage1, "bend": bend}[what]() + "\n")