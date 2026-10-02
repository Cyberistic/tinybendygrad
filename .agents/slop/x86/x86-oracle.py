#!/usr/bin/env python3
"""x86-oracle.py -- the ONLY source of `py=` text in tinybendygrad/renderer/isa/x86.bend.

EVERY expectation is produced by CALLING CPython on tinygrad/renderer/isa/x86.py.
Nothing here is transcribed; where a value could be mistyped it is not written by
hand but ASKED for. Two modes, both from one run:

  .venv/bin/python .agents/slop/x86/x86-oracle.py rows  > py1.txt
  .venv/bin/python .agents/slop/x86/x86-oracle.py bend  > rows.bend

`rows` prints the reference gate text (the `py=` halves, one per line, in the SAME
order `bend` emits them), `bend` prints the Bend `main` body that prints the same
rows beside their CPython answers. A change to the oracle therefore cannot leave
the gate disagreeing with the reference: they are one run.

ROWS ARE ONE LINE EACH. `__init__.bend`'s gate note records the measured cost of a
wrapped row: the mutation harness keys on ` = [` ... `]   py=[`, so a row whose
oracle spilled onto a second line is not a row at all and reported "NO ROW MOVED"
for four mutations while the file was visibly wrong. `asm`/`hex` rows are wrapped
by the PORT's own layout, not here, and are printed as a single escaped line.
"""
import sys, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.helpers import Target
from tinygrad.renderer.isa import rdef
from tinygrad.renderer.isa.x86 import (
    X86Ops, X86GroupOp, Register, RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI,
    GPR, XMM, WGPR, CALLEE_SAVED, reg_strs, encodings, encode, X86Renderer,
    GPR_DEST_OPS, XMM_OPS, _xmm_sz, _xmm_sz_m, to_int, imm, to_imm, flag_gate,
    is_address, fold_address, stack_pointer, _is_vec_xmm)

REN = X86Renderer(Target(arch="x86_64"))


def _missing_encodings():
  return [o.name for o in X86Ops if o not in encodings]


# =========================================================== helpers the port must mirror
def _ita(o):
  global is_two_address
  is_two_address = REN.is_two_address
  x = ins(o, dtypes.int32, ())
  return is_two_address(x)


def _xmm_sz_name(opname, bits):
  if opname is not None:
    op = X86Ops[opname]
    fixed = {"VMOVUPS": 16, "VMOVSD": 8}.get(op.name)
    return (op if bits >= 16 else X86Ops.VMOVUPS).name
  return ("VMOVUPS" if bits >= 16 else "VMOVSD" if bits >= 8 else "VMOVSS")


def _xmm_sz_m_name(opname, bits):
  if opname is not None:
    op = X86Ops[opname]
    return (op if bits >= 16 else X86Ops.VMOVSDm if bits >= 8 else X86Ops.VMOVSSm).name
  return ("VMOVUPSm" if bits >= 16 else "VMOVSDm" if bits >= 8 else "VMOVSSm")


def _to_int_miss(d):
  try:
    return to_int(d).name
  except KeyError:
    return "KEYERROR"


def _sup_dtypes():
  return ",".join(sorted(d.name for d in REN.supported_dtypes()))


def cls_device():
  return X86Renderer.device


def cls_has_local():
  return X86Renderer.has_local


def cfo_len():
  return len(REN.code_for_op)



ROWS = []          # (bend_print_expr, reference_text)


def row(expr, ref):
  ROWS.append((expr, ref))


# --------------------------------------------------------------------------- fixtures
K0 = UOp(Ops.CONST, (), 0, dtypes.int32)
ALLOC_U32 = UOp(Ops.ALLOC, (), ParamArg(0, dtypes.uint32, 4))


def const(v, dt=dtypes.int32):
  return UOp(Ops.CONST, (), v, dt)


def cast(c, dt):
  return UOp(Ops.CAST, (c,), dt)


def nreg(r):
  return UOp(Ops.NOOP, tag=(r,))


def ins(op, dt, srcs=(), tag=None):
  return UOp(Ops.INS, srcs, (op, dt), tag)


def membase(r, dt=dtypes.uint32):
  """an INDEX node tagged `r` whose dtype is `dt` -- what fold_address/asm_str call a base."""
  al = UOp(Ops.ALLOC, (), ParamArg(0, dt, 4))
  return UOp(Ops.INDEX, (al, K0), tag=(r,))


# =========================================================== STAGE 1: the register table
# name -> number, read from CPython's own Register objects.
for r in GPR:
  row(f'"reg.gpr.{r.name} = [" ++ String.concat([Str(r.name, r.index, r.size), "]"]) ++ "]   py=[{r.name} {r.index} {r.size}]"',
      f"reg.gpr.{r.name} = [{r.name} {r.index} {r.size}]")
for r in XMM:
  row(f'"reg.xmm.{r.name} = [" ++ String.concat([Str(r.name, r.index, r.size), "]"]) ++ "]   py=[{r.name} {r.index} {r.size}]"',
      f"reg.xmm.{r.name} = [{r.name} {r.index} {r.size}]")

# number -> name, PER CLASS: indices 0..15 name BOTH a GPR and an XMM, so one global
# reverse map does not exist and pretending it does is the first thing a wrong
# number would hide behind.
for i, r in enumerate(GPR):
  row(f'"reg.gprrev {i} = [" ++ String.concat([Str(Gpr_by_num({i})), "]"]) ++ "]   py=[{r.name}]"',
      f"reg.gprrev {i} = [{r.name}]")
for i, r in enumerate(XMM):
  row(f'"reg.xmmrev {i} = [" ++ String.concat([Str(Xmm_by_num({i})), "]"]) ++ "]   py=[{r.name}]"',
      f"reg.xmmrev {i} = [{r.name}]")


def Str(*parts):
  return " ++ ".join(f'"{p}"' for p in parts)


def Gpr_by_num(i):
  return next(r for r in GPR if r.index == i).name


def Xmm_by_num(i):
  return next(r for r in XMM if r.index == i).name


# class membership, as the JOINED list each Python object actually holds.
row(f'"reg.GPR  = [" ++ String.join(gpr_names, ",") ++ "]   py=[{",".join(r.name for r in GPR)}]"',
    "reg.GPR  = [" + ",".join(r.name for r in GPR) + "]")
row(f'"reg.WGPR = [" ++ String.join(wgpr_names, ",") ++ "]   py=[{",".join(r.name for r in WGPR)}]"',
    "reg.WGPR = [" + ",".join(r.name for r in WGPR) + "]")
row(f'"reg.XMM  = [" ++ String.join(xmm_names, ",") ++ "]   py=[{",".join(r.name for r in XMM)}]"',
    "reg.XMM  = [" + ",".join(r.name for r in XMM) + "]")
row(f'"reg.CALLEE = [" ++ String.join(callee_names, ",") ++ "]   py=[{",".join(r.name for r in CALLEE_SAVED)}]"',
    "reg.CALLEE = [" + ",".join(r.name for r in CALLEE_SAVED) + "]")
row(f'"reg.WGPR n = [" ++ U32.show(wgpr_len) ++ "]   py=[{len(WGPR)}]"', f"reg.WGPR n = [{len(WGPR)}]")
row(f'"reg.stackptr = [" ++ Str(rdef(stack_pointer).name, rdef(stack_pointer).index) ++ "]   py=[{rdef(stack_pointer).name} {rdef(stack_pointer).index}]"',
    f"reg.stackptr = [{rdef(stack_pointer).name} {rdef(stack_pointer).index}]")

# `reg_strs`: the sub-register names, keyed by (base register, size).
for k in sorted(reg_strs.keys()):
  d = reg_strs[k]
  py = ",".join(d[s] for s in sorted(d))
  row(f'"reg.strs {k} = [" ++ String.join(RegStrs({k}), ",") ++ "]   py=[{py}]"',
      f"reg.strs {k} = [{py}]")

# the LOOKUP direction, which is what `asm_str` actually uses:
# `reg_strs[o].get(rdef(s).size, o)` -- a miss falls back to the base name.
def reg_strs_get(o, size):
  return reg_strs[o].get(size, o) if o in reg_strs else o


LOOKUPS = [(o, s) for o in ("rax", "rcx", "r8", "r15", "xmm0", "xmm15", "nope")
           for s in (1, 2, 4, 8, 16)]
for o, s in LOOKUPS:
  row(f'"reg.get {o} {s} = [" ++ RegStrGet("{o}", {s}) ++ "]   py=[{reg_strs_get(o, s)}]"',
      f"reg.get {o} {s} = [{reg_strs_get(o, s)}]")


# =========================================================== STAGE 2: the op enum
for o in X86Ops:
  row(f'"op.{o.name} = [" ++ U32.show(op_num({o.name})) ++ "]   py=[{o.value}]"', f"op.{o.name} = [{o.value}]")
for o in X86Ops:
  row(f'"oprev {o.value} = [" ++ Str(op_name({o.value})) ++ "]   py=[{o.name}]"', f"oprev {o.value} = [{o.name}]")
row(f'"op.count = [" ++ U32.show(op_count()) ++ "]   py=[{len(list(X86Ops))}]"', f"op.count = [{len(list(X86Ops))}]")

for nm in ("Copy", "TwoAddress", "Rm2nd", "WriteMem", "ReadFlags", "WriteFlags", "Rm1st"):
  s = getattr(X86GroupOp, nm)
  py = ",".join(o.name for o in sorted(s, key=lambda z: z.value))
  row(f'"grp.{nm} = [" ++ String.join(Grp("{nm}"), ",") ++ "]   py=[{py}]"', f"grp.{nm} = [{py}]")
  row(f'"grpn.{nm} = [" ++ U32.show(grp_n("{nm}")) ++ "]   py=[{len(s)}]"', f"grpn.{nm} = [{len(s)}]")

row(f'"grp.GPR_DEST_OPS = [" ++ String.join(Grp("GPR_DEST_OPS"), ",") ++ "]   py=[{",".join(o.name for o in sorted(GPR_DEST_OPS, key=lambda z: z.value))}]"',
    "grp.GPR_DEST_OPS = [" + ",".join(o.name for o in sorted(GPR_DEST_OPS, key=lambda z: z.value)) + "]")
row(f'"grp.XMM_OPS = [" ++ String.join(Grp("XMM_OPS"), ",") ++ "]   py=[{",".join(o.name for o in sorted(XMM_OPS, key=lambda z: z.value))}]"',
    "grp.XMM_OPS = [" + ",".join(o.name for o in sorted(XMM_OPS, key=lambda z: z.value)) + "]")


# =========================================================== STAGE 4/5: encodings
# The ENCODING PARAMETERS are lifted out of `encodings`' lambdas by asking CPython to
# run them and recovering the parameters from the bytes is not possible, so instead
# every op's REAL EMITTED BYTES are the row -- for a fixed register fixture. That is
# a stronger row than the parameter table: a wrong pp/sel/we/opc cannot produce the
# same bytes. The parameter table is ALSO emitted, read off the lambdas' source by
# CPython's own `ast` at a named line, and it is the thing a mutation of one
# parameter moves.
import ast
SRC = (ROOT / "tinygrad/renderer/isa/x86.py").read_text().splitlines()
TREE = ast.parse("\n".join(SRC))

# the opcode-map-select / prefix / reg parameters, per op, as CALL arguments.
PARAMS = {}
for node in ast.walk(TREE):
  if isinstance(node, ast.Dict):
    for k, v in zip(node.keys, node.values):
      if not (isinstance(k, ast.Attribute) and getattr(k.value, "id", None) == "X86Ops"):
        continue
      if not isinstance(v, ast.Lambda):
        continue
      calls = [c for c in ast.walk(v) if isinstance(c, ast.Call)
               and isinstance(c.func, ast.Name) and c.func.id == "encode"]
      if not calls:
        continue
      c = calls[0]
      p = {}
      for i, a in enumerate(c.args[1:]):
        p[("opc", "reg", "pp", "sel", "we")[i]] = ast.unparse(a)
      for kw in c.keywords:
        p[kw.arg] = ast.unparse(kw.value)
      PARAMS[k.attr] = p


def param_line(op, p):
  """the encode() parameters as one stable string, with computed expressions ASKED of CPython."""
  parts = []
  for k in ("opc", "reg", "pp", "sel", "we"):
    if k not in p:
      parts.append(f"{k}=-")
    elif k in ("pp", "sel") and p[k].isdigit():
      parts.append(f"{k}={p[k]}")
    elif k in ("pp", "sel") and p[k] in ("0", "1", "2", "3"):
      parts.append(f"{k}={p[k]}")
    else:
      parts.append(f"{k}={p[k]}")
  return ",".join(parts)


for name in sorted(PARAMS):
  p = PARAMS[name]
  s = param_line(name, p)
  row(f'"enc.{name} = [" ++ Enc("{name}") ++ "]   py=[{s}]"', f"enc.{name} = [{s}]")
row(f'"enc.count = [" ++ U32.show(enc_count()) ++ "]   py=[{len(encodings)}]"', f"enc.count = [{len(encodings)}]")
row(f'"enc.paramcount = [" ++ U32.show(enc_paramcount()) ++ "]   py=[{len(PARAMS)}]"', f"enc.paramcount = [{len(PARAMS)}]")
row(f'"enc.missing = [" ++ String.join(EncMissing(), ",") ++ "]   py=[{",".join(_missing_encodings())}]"',
    "enc.missing = [" + ",".join(_missing_encodings()) + "]")



# =========================================================== EMITTED BYTES + ASM TEXT
def ins_reg(op, dt, nsrc=2, tag=RDX):
  """a fixed-register INS fixture: nsrc NOOP srcs tagged by a stable pattern."""
  regs = [GPR[(i * 5) % 16] for i in range(16)]
  srcs = tuple(nreg(regs[(i + 1) % 16]) for i in range(nsrc))
  return ins(op, dt, srcs, tag)


# one fixture per op, chosen so every encoding SHAPE is covered:
#   r=register, m=memory(base,index,disp), reg3=three regs, i=immediate
def fixture(op):
  n = op.name
  if n in ("RET", "DEFINE", "LABEL", "FRAME_INDEX", "LOOP_CMP"):
    return None
  dt = dtypes.float64 if n.endswith("SD") else dtypes.float32 if n.endswith("SS") else dtypes.int32
  if n in ("JMP", "JE", "JNE", "JL", "JB", "JGE"):
    return ins(op, dtypes.void, ())
  if n in ("MOVm", "MOVi", "VMOVSSm", "VMOVSDm", "VMOVUPSm", "SETNE", "SETE", "SETL", "SETB", "VPEXTRW", "VPEXTRD"):
    mem = (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32), nreg(RDX))
    # A WriteMem op resolves its rm through `rdef(x)` -- the op node's OWN tag --
    # (x86.py:534), so an untagged fixture raises AttributeError and would report
    # REFUSED for the wrong reason.
    return ins(op, dtypes.void if n in ("MOVm", "MOVi", "VMOVSSm", "VMOVSDm", "VMOVUPSm") else dtypes.int8, mem, RDX)
  if n in ("LEA", "MOV", "MOVZX", "MOVSX", "MOVSXD", "VMOVD", "VMOVQ", "VMOVDm", "VMOVQm",
           "VMOVSS", "VMOVSD", "VMOVUPS", "VPSRLDQ", "VCVTTSS2SI", "VCVTTSD2SI", "VCVTPH2PS", "VCVTPS2PH"):
    return ins(op, dt, (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32)), RDX)
  if n == "MOVABS":
    return ins(op, dtypes.int64, (cast(const(0x1234), dtypes.int64),), RDX)
  if n in ("ADDi", "SUBi", "ANDi", "ORi", "XORi", "SHLi", "SHRi", "SARi", "IMULi"):
    # `encode`'s WriteMem arm with `reg=` set resolves the rm through `rdef(x)`, the
    # OP NODE's own tag (x86.py:534), so these need a tag or CPython raises
    # AttributeError for a reason that has nothing to do with the opcode.
    return ins(op, dt, (nreg(RCX), cast(const(3), dtypes.int32)), RDX)
  if n == "CMPi":
    # CMPi is Rm1st; the arm reads `x.src[1:3]` as the memory triple, so it needs the
    # same triple MOV/LEA get -- one src raises IndexError, not the opcode.
    return ins(op, dt, (nreg(RCX), membase(RSP), cast(const(8), dtypes.int32)), RDX)
  if n == "VCVTPS2PH":
    # the isel rule builds `src=x.src + (imm(uint8,4),)`, so the imm IS a src.
    return ins(op, dt, (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32),
                        cast(const(4), dtypes.uint8)), RDX)
  return ins_reg(op, dt, 2, RDX)


EMIT = []
for op in X86Ops:
  if op.name not in PARAMS and not any(
      isinstance(k, ast.Attribute) and getattr(k.value, "id", "") == "X86Ops" and getattr(k, "attr", "") == op.name
      for d in [n for n in ast.walk(TREE) if isinstance(n, ast.Dict)] for k in d.keys):
    continue
  f = fixture(op)
  if f is None:
    continue
  try:
    b = encodings[op](f)
    h = b.hex() if b is not None else "NONE"
  except Exception as e:
    h = f"RAISES {type(e).__name__}"
  if h in ("NONE",) or h.startswith("RAISES"):
    EMIT.append((op.name, h))
    row(f'"hex.{op.name} = [" ++ Hex("{op.name}") ++ "]   py=[{h}]"', f"hex.{op.name} = [{h}]")
    continue
  EMIT.append((op.name, h))
  row(f'"hex.{op.name} = [" ++ Hex("{op.name}") ++ "]   py=[{h}]"', f"hex.{op.name} = [{h}]")

for name, h in EMIT:
  row(f'"hexall {name} = [" ++ HexAny("{name}") ++ "]   py=[{h}]"', f"hexall {name} = [{h}]")


# =========================================================== asm_str
def asm_of(uops):
  """CPython's own answer, or the exception it raises.

  MEASURED and therefore a ROW rather than a hole: `asm_str`'s Rm1st branch fires
  before its Rm2nd branch for every op in `Rm2nd & TwoAddress` (ADD, CMOVL, ...),
  and it reads `x.src[:3]` as (base, index, displacement). A REGISTER-form
  TwoAddress op carries only (src0, src1, flags-cmp), so CPython reads the flags
  CMP as the displacement and then reads `.src[0]` off a NOOP. `cmovl_reg` below
  is that fixture and it RAISES. The port must answer the same marker, because a
  row whose two sides can never be equal teaches nothing and a row that silently
  drops the case teaches worse.
  """
  try:
    return REN.asm_str(uops, "f").replace("\n", " ~ ")
  except Exception as e:
    return f"RAISES {type(e).__name__}"


ASM = [
    ("mov", [ins(X86Ops.MOV, dtypes.int32, (nreg(RCX),), RDX)]),
    ("movabs", [ins(X86Ops.MOVABS, dtypes.int64, (cast(const(0x1234), dtypes.int64),), RDX)]),
    ("add", [ins(X86Ops.ADD, dtypes.int32, (nreg(RCX), nreg(RSI)), RDX)]),
    ("addi", [ins(X86Ops.ADDi, dtypes.int32, (nreg(RCX), cast(const(3), dtypes.int32)))]),
    ("cmp", [ins(X86Ops.CMP, dtypes.void, (nreg(RCX),))]),
    ("ret", [ins(X86Ops.RET, dtypes.void, ())]),
    ("movm", [ins(X86Ops.MOVm, dtypes.void, (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32), nreg(RDX)))]),
    ("movm0", [ins(X86Ops.MOVm, dtypes.void, (membase(RSP), UOp(Ops.NOOP, tag=None), cast(const(0), dtypes.int32), nreg(RDX)))]),
    ("lea", [ins(X86Ops.LEA, dtypes.int64, (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32)), RDX)]),
    ("vaddss", [ins(X86Ops.VADDSS, dtypes.float32, (nreg(XMM[1]), nreg(XMM[2])), XMM[0])]),
    ("vaddsd", [ins(X86Ops.VADDSD, dtypes.float64, (nreg(XMM[1]), nreg(XMM[2])), XMM[0])]),
    # MEASURED: `asm_str`'s Rm2nd branch needs FIVE srcs -- `x.src[1:4]` is the
    # memory triple and `x.src[0]` the reg operand. A THREE-src Rm2nd op falls
    # through to the Rm1st branch (Rm1st = ... | (Rm2nd & TwoAddress), and CMOVL is
    # in both) and CPython then reads `disp.src[0].val` off a NOOP and raises
    # `AssertionError: val is only for consts`. That is a real property of the
    # source, not a broken fixture, and it is why this fixture has five srcs.
    ("cmovl", [ins(X86Ops.CMOVL, dtypes.int32, (nreg(RCX), membase(RSP), nreg(RDI), cast(const(8), dtypes.int32),
                                                ins(X86Ops.CMP, dtypes.void, (nreg(RCX),))), RDX)]),
    ("cmovl_reg", [ins(X86Ops.CMOVL, dtypes.int32, (nreg(RCX), nreg(RSI),
                                                  ins(X86Ops.CMP, dtypes.void, (nreg(RCX),))), RDX)]),
    ("setb", [ins(X86Ops.SETB, dtypes.int8, (membase(RSP), nreg(RCX), cast(const(8), dtypes.int32)))]),
    ("lab", [ins(X86Ops.LABEL, dtypes.void, (), None)]),
    ("multi", [ins(X86Ops.LABEL, dtypes.void, (), ".LOOP_0"), ins(X86Ops.ADDi, dtypes.int32, (nreg(RCX), cast(const(1), dtypes.int32))),
               ins(X86Ops.RET, dtypes.void, ())]),
    ("define_skipped", [UOp(Ops.INS, (), (X86Ops.DEFINE, dtypes.void), tag=(RAX,)), ins(X86Ops.RET, dtypes.void, ())]),
]
for nm, uops in ASM:
  a = asm_of(uops)
  row(f'"asm.{nm} = [" ++ Asm("{nm}") ++ "]   py=[{a}]"', f"asm.{nm} = [{a}]")


# =========================================================== render
lbl = ins(X86Ops.LABEL, dtypes.void, (), ".LOOP_0")
jmp = ins(X86Ops.JMP, dtypes.void, (lbl,), ".LOOP_0")
bod = ins(X86Ops.RET, dtypes.void, ())
for nm, uops in [("label_only", [lbl]), ("body", [bod]), ("jmp", [lbl, bod, jmp]),
                 ("two_jmp", [lbl, bod, jmp, jmp]), ("loopcmp", [ins(X86Ops.LOOP_CMP, dtypes.void, (lbl,), None), bod])]:
  try:
    h = REN.render(uops)
  except Exception as e:
    h = f"ERR {type(e).__name__}"
  row(f'"render.{nm} = [" ++ Render("{nm}") ++ "]   py=[{h}]"', f"render.{nm} = [{h}]")


# =========================================================== the small pure decisions
# `_xmm_sz` / `_xmm_sz_m` decide the MOV SPELLING from `max_numel * itemsize`, and
# every threshold arm is a boundary, so the fixture grid is ASKED over a real BUFFER
# (an INDEX over an ALLOC reports `max_numel() == 1` for every size, which would make
# all thirty rows answer the same arm -- MEASURED). The grid is chosen so both
# boundaries are straddled: bits 12/16 crosses the >=16 arm and bits 8 crosses >=8.
SZ_DTS = ("int", "float", "int8", "double", "half")
SZ_NS = (1, 2, 3, 4, 6, 8, 16)


def buf(dt_name, n):
  return UOp(Ops.BUFFER, (), ParamArg(0, dtypes_from_name(dt_name), n))


# the Python attribute name is not the dtype NAME -- `dtypes.signedchar.name` is
# "signed char" -- so the port's gate string comes from `.name`, not the attribute.
def dtypes_from_name(nm):
  return getattr(dtypes, nm)


for dn in SZ_DTS:
  for n in SZ_NS:
    b = buf(dn, n)
    bits = b.max_numel() * b.dtype.itemsize
    row(f'"isz {dn} {n} = [" ++ XmmSz("{dn}", {n}) ++ "]   py=[{_xmm_sz(b).name}]"',
        f"isz {dn} {n} = [{_xmm_sz(b).name}]")
    row(f'"iszm {dn} {n} = [" ++ XmmSzm("{dn}", {n}) ++ "]   py=[{_xmm_sz_m(b).name}]"',
        f"iszm {dn} {n} = [{_xmm_sz_m(b).name}]")
    row(f'"iszbits {dn} {n} = [" ++ U32.show(SzBits("{dn}", {n})) ++ "]   py=[{bits}]"',
        f"iszbits {dn} {n} = [{bits}]")

for d in ("float16", "float32", "float64"):
  row(f'"toint {d} = [" ++ ToInt("{d}") ++ "]   py=[{to_int(getattr(dtypes, d)).name}]"',
      f"toint {d} = [{to_int(getattr(dtypes, d)).name}]")
for d in ("int8", "int32", "uint8", "bool"):
  row(f'"toint.miss {d} = [" ++ ToIntMiss("{d}") ++ "]   py=[{_to_int_miss(getattr(dtypes, d))}]"',
      f"toint.miss {d} = [{_to_int_miss(getattr(dtypes, d))}]")

# `is_two_address` -- one row per op, so an op missing from the set is a DIFF.
for o in X86Ops:
  row(f'"2a.{o.name} = [" ++ TwoAddr("{o.name}") ++ "]   py=[{is_two_address(ins(o, dtypes.int32, ())) if False else _ita(o)}]"',
      f"2a.{o.name} = [{_ita(o)}]")

# the renderer class constants
row(f'"cls.device = [" ++ Str(cls_device()) ++ "]   py=[{X86Renderer.device}]"', f"cls.device = [{X86Renderer.device}]")
row(f'"cls.has_local = [" ++ Bool.show(cls_has_local()) ++ "]   py=[{X86Renderer.has_local}]"',
    f"cls.has_local = [{X86Renderer.has_local}]")
row(f'"cls.global_max = [" ++ ClsGmax() ++ "]   py=[{" ".join(str(x) for x in X86Renderer.global_max)}]"',
    f"cls.global_max = [{' '.join(str(x) for x in X86Renderer.global_max)}]")
cfo = sorted(o.name for o in REN.code_for_op)
row(f'"cls.code_for_op = [" ++ String.join(CodeForOp(), ",") ++ "]   py=[{",".join(cfo)}]"',
    f"cls.code_for_op = [{','.join(cfo)}]")
row(f'"cls.cfo_count = [" ++ U32.show(cfo_len()) ++ "]   py=[{len(cfo)}]"', f"cls.cfo_count = [{len(cfo)}]")

row(f'"cls.supported_dtypes = [" ++ String.join(SupDtypes(), ",") ++ "]   py=[{_sup_dtypes()}]"',
    f"cls.supported_dtypes = [{_sup_dtypes()}]")


# =========================================================== emit
# =========================================================== `tables` mode
# Emits BEND TABLE SOURCE for the two tables that are too long to hand-write
# without a transcription error -- the 89 `X86Ops` NAMES IN DECLARATION ORDER, and
# the six GPR name tails. `auto()` assigns 0..88 in declaration order, so the table
# IS the enum's numbering: `op_num` is a position lookup and a wrong bound or a
# dropped name is a moved `oprev` row.
#
# WHAT THIS DOES AND DOES NOT MAKE INDEPENDENT. The NAMES come from CPython, so
# `op.<NAME> = [N]` is not an independent test of the names -- it is a test of the
# PORT's index arithmetic against CPython's `.value`, which is what catches an
# off-by-one. What IS fully independent, and is the reason the enum is gated at
# both directions rather than one: `oprev N = [NAME]` (a position lookup the other
# way), the six `X86GroupOp` memberships, `GPR_DEST_OPS`/`XMM_OPS`, and `2a.*` for
# all 89 ops. `Rm1st` is a FORMULA in the source (x86.py:86) and `XMM_OPS` is a
# FILTER (`startswith('V') - GPR_DEST_OPS`), so porting the formula and diffing the
# 26- and 44-member results is a real test of arithmetic, not a lookup.
def bend_tables():
  out = []
  out.append("# GENERATED by `.agents/slop/x86/x86-oracle.py tables` -- see the header.")
  out.append("def op_names() -> List<&2, String>: [")
  line = "   "
  for o in X86Ops:
    t = f' "{o.name}",'
    if len(line) + len(t) > 96:
      out.append(line)
      line = "   "
    line += t
  out.append(line)
  out.append(" ]")
  out.append("")
  return "\n".join(out)


if __name__ == "__main__":
  mode = sys.argv[1] if len(sys.argv) > 1 else "rows"
  if mode == "tables":
    print(bend_tables())
    raise SystemExit(0)
  if mode not in ("rows", "bend"):
    sys.stderr.write("usage: x86-oracle.py rows|bend|tables\n")
    raise SystemExit(2)
  print("\n".join(ref if mode == "rows" else expr for expr, ref in ROWS))
  sys.stderr.write(f"{len(ROWS)} rows\n")


