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




def enc_inputs(x, op):
  """THE FIFTEEN NUMBERS `Enc.emit` TAKES, READ OUT OF THE LIVE `encode` FRAME.

  THE FIRST VERSION OF THIS FUNCTION RE-TRANSCRIBED `x86.py:600-616`, and it was
  wrong in three places at once, which is why every byte row disagreed with CPython
  while the FILE reported ALL PROOFS CHECK:

    * the Rm2nd arm read `reg_uop = rest[0] if x.dtype is not dtypes.void else None`
      where x86.py:616 says `_encode(x, ...) if x.dtype is not dtypes.void else
      _encode(rest[0], ...)` -- inverted, so CMP's `reg` came out 5 instead of 2;
    * NEITHER arm honoured the `if reg is None` fork, so an op whose table supplies
      `reg=` (SHL 4, SUBi 5, CMPi 7, IDIV 7, VPSRLDQ 3) was handed the FIXTURE's
      register where CPython keeps the TABLE's -- and `reg = 0` where CPython keeps
      4, 5, 7.  Every MODRM reg field of those ops was wrong;
    * `vvvv` was a hardcoded list of four op names, so VPSRLDQ -- which x86.py:610
      passes `x` as `vvvv_uop` -- got 0 and emitted the C5 byte `f9` instead of `e9`.

  That is `agent-core.md`'s THIRD FORM of the trap (a row that re-transcribes agrees
  with a port that misread it) reached by a fourth route: a transcription of
  `encode`'s CONTROL FLOW rather than of its arithmetic.  So this no longer
  re-transcribes anything.  `capture` installs a line tracer on `encode`'s own code
  object, reads the frame's locals at the FIRST line of `_encode` -- before
  x86.py:567 masks reg/rm/idx to three bits -- and the numbers are whatever
  CPython's encoder actually used.

  It is still a description rather than the answer: what the gate compares is the
  BYTES, which no wrong opcode and no wrong REX/VEX/MODRM/SIB bit can reproduce."""
  return CAPTURE[0] and CAPTURE[0](x, op)


def _capture(x, op):
  """runs `encodings[op](x)` with a tracer and returns the fifteen numbers, or None
  when `encode` was never entered (the ops in no group, x86.py:618).

  `_encode` binds its operands ONE LINE AT A TIME and MASKS THEM at x86.py:567, so
  the frame is frozen at the first line event on which all five are bound -- which is
  x86.py:547, `r, _x, b = reg >> 3, idx >> 3, rm >> 3`, the last line before the
  mask.  Nothing here names a line number, so an edit above 547 does not silently
  change the answer; an edit below it cannot be seen at all, which is the point."""
  if x is None:
    return None
  outer, inner, frozen = {}, {}, [None]
  # `encode`'s own frame holds `x` and the five encoding parameters. `_encode`'s is a
  # CLOSURE -- not reachable as an attribute -- and is taken from `co_consts`, where
  # CPython keeps every code object a function defines. `_encode`'s frame also carries
  # `reg` as a FREE VARIABLE (it is `nonlocal` there) and it shows the REBOUND value, so
  # `reg` is read from the inner frame and not from the outer's stale parameter copy.
  code_outer, code_inner = encode.__code__, _INNER_CODE
  operands = ('reg', 'rm', 'idx', 'rm_sz', 'reg_sz')

  def tracer(frame, event, arg):
    if frame.f_code is code_outer:
      if event == 'line':
        for k, v in frame.f_locals.items():
          outer.setdefault(k, v)
      return tracer
    if frame.f_code is code_inner:
      if event == 'line' and frozen[0] is None:
        l = frame.f_locals
        if all(k in l for k in operands):
          frozen[0] = {k: l[k] for k in operands}
        for k in ('disp_uop', 'vvvv_uop', 'imm_uop'):
          if k in l:
            inner.setdefault(k, l[k])
      return tracer
    return None

  sys.settrace(tracer)
  try:
    # A fixture CPython cannot encode (VCVTPS2PH, VMOVDm, VMOVQm) RAISES, and the
    # caller has already recorded that as `HexBad`; there are no numbers to hand over.
    encodings[op](x)
  except Exception:
    return None
  finally:
    sys.settrace(None)
  if frozen[0] is None:
    return None
  l = dict(outer)
  l.update(inner)
  l.update(frozen[0])
  reg, rm, idx, rm_sz, reg_sz = l['reg'], l['rm'], l['idx'], l['rm_sz'], l['reg_sz']
  disp_uop, vvvv_uop, imm_uop, node = l['disp_uop'], l['vvvv_uop'], l['imm_uop'], l['x']
  vd = rdef(vvvv_uop) if vvvv_uop is not None else None
  vvvv = (vd.index if isinstance(vd, Register) else reg) if vvvv_uop is not None else 0
  if disp_uop is not None:
    has_disp, dv, dsz = "True{}", str(disp_uop.src[0].val), str(disp_uop.dtype.itemsize)
  else:
    has_disp, dv, dsz = "False{}", "0", "4"
  if imm_uop is not None and imm_uop.op is Ops.CAST:
    ikind, inum, ival = "1", str(imm_uop.dtype.itemsize), str(imm_uop.src[0].val)
  elif imm_uop is not None:
    ikind, inum, ival = "2", "1", str(rdef(imm_uop).index)
  else:
    ikind, inum, ival = "0", "0", "0"
  # `x86.py:558` spells this `x.arg[0] not in X86GroupOp.ReadFlags | {LEA}`, and a
  # Python bool is not a Bend Bool -- `True{}` IS one.
  no_demote = "True{}" if (op in X86GroupOp.ReadFlags or op.name == "LEA") else "False{}"
  # `x.dtype.itemsize` and `x.src[1].dtype.itemsize` are what the two computed `we=`
  # expressions read (x86.py:641-644) and NEITHER is reg_sz or rm_sz: `x.src[1]` is the
  # rm operand for an Rm2nd op, whose `rm_sz` is the REGISTER's 16, while the expression
  # reads its DTYPE's 4.  So both are numbers of their own.
  xsz = node.dtype.itemsize
  src1sz = node.src[1].dtype.itemsize if len(node.src) > 1 else 0
  return (f'{reg}, {rm}, {idx}, {rm_sz}, {reg_sz}, {vvvv}, '
          f'{has_disp}, {dv}, {dsz}, {ikind}, {inum}n, {ival}, {no_demote}, {xsz}, {src1sz}')


CAPTURE = [_capture]
_INNER_CODE = next(c for c in encode.__code__.co_consts
                   if hasattr(c, "co_name") and c.co_name == "_encode")


# ---------------------------------------------------------------- THE FIXTURES
# ONE fixture per op, chosen so every ENCODING SHAPE is covered: a register operand, a
# memory operand (base, index, displacement), an immediate, and the ops that write to
# memory. The SAME fixture is handed to CPython's `encode` and its inputs are extracted
# from it (`enc_inputs`), so the two sides cannot describe two different instructions.
def nreg(r):
  return UOp(Ops.NOOP, tag=(r,))


def ins(op, dt, srcs=(), tag=None):
  return UOp(Ops.INS, srcs, (op, dt), tag)


def membase(r, dt=dtypes.u32):
  """an INDEX node tagged `r` whose dtype is `dt` -- what `fold_address` and `asm_str`
  call a base. An INDEX over a 1-D ALLOC reports `max_numel() == 1` for every size, so
  the vector-width fixtures use a BUFFER instead (MEASURED)."""
  al = UOp(Ops.ALLOC, (), ParamArg(0, dt, 4))
  return UOp(Ops.INDEX, (UOp(Ops.CONST, (), 0, dtypes.i32),), tag=(r,)).replace(src=(al, UOp(Ops.CONST, (), 0, dtypes.i32)))


def const(v, dt=dtypes.i32):
  return UOp(Ops.CONST, (), v, dt)


def cast(c, dt):
  return UOp(Ops.CAST, (c,), dt)


MEMBASE = membase(RSP)


def fixture_op(n):
  """A STABLE register pattern: the reg operand is GPR[2] = RDX = index 2 and the rm
  srcs step through GPR by five, so `xmm` and `r8..r15` (indices 8..15, which need the
  REX extension bit) appear without being named."""
  op = X86Ops[n]
  dt = dtypes.f64 if n.endswith("SD") else dtypes.f32 if n.endswith("SS") else dtypes.i32
  mem = (MEMBASE, nreg(RCX), cast(const(8), dtypes.i32), nreg(RDX))
  if n in ("RET", "DEFINE", "LABEL", "FRAME_INDEX", "LOOP_CMP"):
    return None
  if n in ("JMP", "JE", "JNE", "JL", "JB", "JGE"):
    return ins(op, dtypes.void, ())
  if n in ("MOVm", "MOVi", "VMOVSSm", "VMOVSDm", "VMOVUPSm", "SETNE", "SETE", "SETL", "SETB",
           "VPEXTRW", "VPEXTRD"):
    # A WriteMem op resolves its rm through `rdef(x)`, the OP NODE's own tag
    # (x86.py:534), so these need a tag or CPython raises for an unrelated reason.
    return ins(op, dtypes.void if n.endswith("m") or n.endswith("i") else dtypes.i8, mem, RDX)
  if n in ("LEA", "MOV", "MOVZX", "MOVSX", "MOVSXD", "VMOVD", "VMOVQ", "VMOVDm", "VMOVQm",
           "VMOVSS", "VMOVSD", "VMOVUPS", "VPSRLDQ", "VCVTTSS2SI", "VCVTTSD2SI", "VCVTPH2PS"):
    return ins(op, dt, mem[:3], RDX)
  if n == "MOVABS":
    return ins(op, dtypes.i64, (cast(const(0x1234), dtypes.i64),), RDX)
  if n in ("ADDi", "SUBi", "ANDi", "ORi", "XORi", "SHLi", "SHRi", "SARi", "IMULi"):
    return ins(op, dt, (nreg(RCX), cast(const(3), dtypes.i32)), RDX)
  if n == "CMPi":
    # CMPi is Rm1st; the arm reads `x.src[1:3]` as the memory triple.
    return ins(op, dt, mem[:3], RDX)
  if n == "VCVTPS2PH":
    # the isel rule builds `src=x.src + (imm(uint8,4),)`, so the imm IS a src.
    return ins(op, dt, mem[:3] + (cast(const(4), dtypes.u8),), RDX)
  if op in X86Ops and n.startswith("V"):
    # the VECTOR ops: xmm0 is the destination and the srcs are xmm registers, which is
    # the only way the `sel`/`pp`/`vvvv` bytes are exercised at all.
    return ins(op, dt, (nreg(XMM[1]), nreg(XMM[2])), XMM[0])
  regs = [GPR[(i * 5) % 16] for i in range(16)]
  return ins(op, dt, (nreg(regs[1]), nreg(regs[6])), RDX)


def reg_strs_get(o, size):
  return reg_strs[o].get(size, o) if o in reg_strs else o


def _missing_encodings():
  return [o.name for o in X86Ops if o not in encodings]


# =========================================================== helpers the port must mirror
def _callee(ix):
  return ix in (GPR[3].index, GPR[5].index, 12, 13, 14, 15)


def _ita(o):
  global is_two_address
  is_two_address = REN.is_two_address
  x = ins(o, dtypes.i32, ())
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
K0 = UOp(Ops.CONST, (), 0, dtypes.i32)
ALLOC_U32 = UOp(Ops.ALLOC, (), ParamArg(0, dtypes.u32, 4))


def const(v, dt=dtypes.i32):
  return UOp(Ops.CONST, (), v, dt)


def cast(c, dt):
  return UOp(Ops.CAST, (c,), dt)


def nreg(r):
  return UOp(Ops.NOOP, tag=(r,))


def ins(op, dt, srcs=(), tag=None):
  return UOp(Ops.INS, srcs, (op, dt), tag)


def membase(r, dt=dtypes.u32):
  """an INDEX node tagged `r` whose dtype is `dt` -- what fold_address/asm_str call a base."""
  al = UOp(Ops.ALLOC, (), ParamArg(0, dt, 4))
  return UOp(Ops.INDEX, (al, K0), tag=(r,))


# =========================================================== the ROWS
# Every row is `(bend_expr, reference_text)`. The reference text is what CPython
# answered ON THIS TREE; the Bend expression is the ONLY thing the port is asked for.
# Both come from this one list, so `rows` and `bend` cannot disagree.


def row(expr, ref):
  ROWS.append((expr, ref))


def names(ls):
  return ",".join(str(x) for x in ls)


# ---------------------------------------------------------------- STAGE 1: registers
for i, r in enumerate(GPR):
  row(f'"reg.gpr {r.name} = [" ++ RegTriple(Reg.gpr({i})) ++ "]   py=[{r.name} {r.index} {r.size}]"',
      f"reg.gpr {r.name} = [{r.name} {r.index} {r.size}]")
for i, r in enumerate(XMM):
  row(f'"reg.xmm {r.name} = [" ++ RegTriple(Reg.xmm({i})) ++ "]   py=[{r.name} {r.index} {r.size}]"',
      f"reg.xmm {r.name} = [{r.name} {r.index} {r.size}]")
# number -> name, PER CLASS: indices 0..15 name BOTH a GPR and an XMM, so there is no
# global reverse map and pretending otherwise is the first thing a wrong number hides
# behind.
for i in range(16):
  row(f'"reg.gprrev {i} = [" ++ RegName(Reg.gpr_at({i})) ++ "]   py=[{GPR[i].name}]"',
      f"reg.gprrev {i} = [{GPR[i].name}]")
for i in range(16):
  row(f'"reg.xmmrev {i} = [" ++ RegName(Reg.xmm_at({i})) ++ "]   py=[{XMM[i].name}]"',
      f"reg.xmmrev {i} = [{XMM[i].name}]")
for key, expr, py in [
    ("GPR", "RegNames(Reg.gpr_list())", [r.name for r in GPR]),
    ("WGPR", "RegNames(Reg.wgpr_list())", [r.name for r in WGPR]),
    ("XMM", "RegNames(Reg.xmm_list())", [r.name for r in XMM]),
    ("CALLEE", "RegNames(Reg.callee_list())", [r.name for r in CALLEE_SAVED]),
    ("strs.rax", "RegStrRow(Reg.gpr(0))", [reg_strs["rax"][k] for k in (1, 2, 4)]),
    ("strs.rcx", "RegStrRow(Reg.gpr(1))", [reg_strs["rcx"][k] for k in (1, 2, 4)]),
    ("strs.rdx", "RegStrRow(Reg.gpr(2))", [reg_strs["rdx"][k] for k in (1, 2, 4)]),
    ("strs.rbx", "RegStrRow(Reg.gpr(3))", [reg_strs["rbx"][k] for k in (1, 2, 4)]),
    ("strs.rsp", "RegStrRow(Reg.gpr(4))", [reg_strs["rsp"][k] for k in (1, 2, 4)]),
    ("strs.rbp", "RegStrRow(Reg.gpr(5))", [reg_strs["rbp"][k] for k in (1, 2, 4)]),
    ("strs.rsi", "RegStrRow(Reg.gpr(6))", [reg_strs["rsi"][k] for k in (1, 2, 4)]),
    ("strs.rdi", "RegStrRow(Reg.gpr(7))", [reg_strs["rdi"][k] for k in (1, 2, 4)]),
    ("strs.r8", "RegStrRow(Reg.gpr(8))", [reg_strs["r8"][k] for k in (1, 2, 4)]),
    ("strs.r12", "RegStrRow(Reg.gpr(12))", [reg_strs["r12"][k] for k in (1, 2, 4)]),
    ("strs.r15", "RegStrRow(Reg.gpr(15))", [reg_strs["r15"][k] for k in (1, 2, 4)]),
    ("strs.xmm0", "RegStrRow(Reg.xmm(0))", [reg_strs_get("xmm0", 4), reg_strs_get("xmm0", 8),
                                             reg_strs_get("xmm0", 16)]),
    ("stackptr", "RegTriple(Reg.gpr_at(4))",
     " ".join(str(x) for x in (rdef(stack_pointer).name, rdef(stack_pointer).index, 8))),
]:
  pv = py if isinstance(py, str) else names(py)
  row(f'"reg.{key} = [" ++ {expr} ++ "]   py=[{pv}]"', f"reg.{key} = [{pv}]")
row(f'"reg.WGPRn = [" ++ U32.show(RegLen(Reg.wgpr_list())) ++ "]   py=[{len(WGPR)}]"',
    f"reg.WGPRn = [{len(WGPR)}]")
for o, sz in [(o, sz) for o in ("rax", "rsp", "r12", "xmm0", "nope") for sz in (1, 2, 4, 8, 16)]:
  v = reg_strs_get(o, sz)
  row(f'"reg.get {o} {sz} = [" ++ Reg.strs_lookup("{o}", {sz}) ++ "]   py=[{v}]"',
      f"reg.get {o} {sz} = [{v}]")
for ix in range(16):
  v = str(_callee(ix))
  row(f'"reg.callee {ix} = [" ++ Bool.show(Reg.is_callee({ix})) ++ "]   py=[{v}]"',
      f"reg.callee {ix} = [{v}]")


# ---------------------------------------------------------------- STAGE 2: the ops
for o in X86Ops:
  row(f'"op.{o.name} = [" ++ op_num("{o.name}") ++ "]   py=[{o.value}]"', f"op.{o.name} = [{o.value}]")
for o in X86Ops:
  row(f'"oprev {o.value} = [" ++ op_name_of({o.value}) ++ "]   py=[{o.name}]"',
      f"oprev {o.value} = [{o.name}]")
row(f'"op.count = [" ++ U32.show(op_len()) ++ "]   py=[{len(list(X86Ops))}]"',
    f"op.count = [{len(list(X86Ops))}]")
row(f'"op.unknown = [" ++ op_num("NOSUCH") ++ "]   py=[KeyError]"', "op.unknown = [KeyError]")
row(f'"op.revbad = [" ++ op_name_of(200) ++ "]   py=[ValueError]"', "op.revbad = [ValueError]")

SETS = [("Copy", X86GroupOp.Copy, 0), ("TwoAddress", X86GroupOp.TwoAddress, 1),
        ("Rm2nd", X86GroupOp.Rm2nd, 2), ("WriteMem", X86GroupOp.WriteMem, 3),
        ("ReadFlags", X86GroupOp.ReadFlags, 4), ("WriteFlags", X86GroupOp.WriteFlags, 5),
        ("GPR_DEST_OPS", GPR_DEST_OPS, 6), ("Rm1st", X86GroupOp.Rm1st, 7), ("XMM_OPS", XMM_OPS, 8)]
for nm, st, which in SETS:
  py = names([o.name for o in sorted(st, key=lambda z: z.value)])
  row(f'"grp.{nm} = [" ++ Op.set_name({which}) ++ "]   py=[{py}]"', f"grp.{nm} = [{py}]")
  row(f'"grpn.{nm} = [" ++ U32.show(Op.set_len({which})) ++ "]   py=[{len(st)}]"',
      f"grpn.{nm} = [{len(st)}]")


# ---------------------------------------------------------------- STAGE 3: xmm_sz
SZ_DTS = [("int", dtypes.i32), ("float", dtypes.f32), ("int8", dtypes.i8),
          ("double", dtypes.f64), ("half", dtypes.f16)]
SZ_NS = (1, 2, 3, 4, 6, 8, 16)
SZ_ITEMSIZE = {"int": 4, "float": 4, "int8": 1, "double": 8, "half": 2}
for dn, _ in SZ_DTS:
  for n in SZ_NS:
    b = UOp(Ops.BUFFER, (), ParamArg(0, _, n))
    bits = b.max_numel() * b.dtype.itemsize
    row(f'"isz {dn} {n} = [" ++ Op.xmm_sz({bits}) ++ "]   py=[{_xmm_sz(b).name}]"',
        f"isz {dn} {n} = [{_xmm_sz(b).name}]")
    row(f'"iszm {dn} {n} = [" ++ Op.xmm_sz_m({bits}) ++ "]   py=[{_xmm_sz_m(b).name}]"',
        f"iszm {dn} {n} = [{_xmm_sz_m(b).name}]")
    row(f'"iszbits {dn} {n} = [" ++ U32.show({bits}) ++ "]   py=[{bits}]"',
        f"iszbits {dn} {n} = [{bits}]")
# the three thresholds, straddled: 7/8/15/16/17
for bits in (0, 1, 7, 8, 15, 16, 17, 32):
  row(f'"iszthr {bits} = [" ++ Op.xmm_sz({bits}) ++ "]   py=[{"VMOVUPS" if bits >= 16 else ("VMOVSD" if bits >= 8 else "VMOVSS")}]"',
      f'iszthr {bits} = [{"VMOVUPS" if bits >= 16 else ("VMOVSD" if bits >= 8 else "VMOVSS")}]')
  row(f'"iszthrm {bits} = [" ++ Op.xmm_sz_m({bits}) ++ "]   py=[{"VMOVUPSm" if bits >= 16 else ("VMOVSDm" if bits >= 8 else "VMOVSSm")}]"',
      f'iszthrm {bits} = [{"VMOVUPSm" if bits >= 16 else ("VMOVSDm" if bits >= 8 else "VMOVSSm")}]')

for nm, d in [("float16", dtypes.f16), ("float32", dtypes.f32), ("float64", dtypes.f64)]:
  row(f'"toint {nm} = [" ++ Op.to_int("{nm}") ++ "]   py=[{to_int(d).name}]"',
      f"toint {nm} = [{to_int(d).name}]")
for nm in ("int8", "int32", "uint8", "bool"):
  try:
    v = to_int(getattr(dtypes, nm)).name
  except KeyError:
    v = "KeyError"
  row(f'"toint.miss {nm} = [" ++ Op.to_int("{nm}") ++ "]   py=[{v}]"',
      f"toint.miss {nm} = [{v}]")


# ---------------------------------------------------------------- STAGE 2b: two-address
for o in X86Ops:
  v = str(REN.is_two_address(ins(o, dtypes.i32, ())))
  row(f'"2a.{o.name} = [" ++ Bool.show(Op.is_two_address("{o.name}")) ++ "]   py=[{v}]"',
      f"2a.{o.name} = [{v}]")


# ---------------------------------------------------------------- STAGE 4: encodings
# The ENCODING PARAMETERS, read out of `encodings`' lambdas with CPython's own `ast`
# -- NOT transcribed, and not re-derived from the lambdas' text by hand. A lambda that
# does not call `encode` (the six jumps, `JMP` and `RET`) is in no table here, which
# is what `enc.paramcount` and `enc.count` disagree about and both rows are asked.
import ast
SRC = (ROOT / "tinygrad/renderer/isa/x86.py").read_text().splitlines()
TREE = ast.parse("\n".join(SRC))
PARAM_ORDER = ("opc", "reg", "pp", "sel", "we")
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
      pv = {}
      for i, a in enumerate(c.args[1:]):
        pv[PARAM_ORDER[i]] = a.value if isinstance(a, ast.Constant) else "?"
      for kw in c.keywords:
        # `we=1` is a Constant and `we=x.src[1].dtype.itemsize == 8` is a Compare, and
        # collapsing both to "EXPR" loses the ONE distinction the `enc.*` row exists
        # to check -- MEASURED, `param_line` then printed `x.dtype.itemsize == 8` for
        # both VCVTSI2 entries. `ast.unparse` keeps the source text.
        pv[kw.arg] = (kw.value.value if isinstance(kw.value, ast.Constant)
                      else ast.unparse(kw.value))
      PARAMS[k.attr] = pv


def param_line(name, pv):
  """one stable string per entry, with the two COMPUTED `we`s left as the expression
  CPython's `ast` found -- so the row shows the source's own text and the port's
  SELECTOR (0/1/2) is checked against it by the `enc.*` row."""
  out = []
  for k in PARAM_ORDER:
    if k not in pv:
      out.append(f"{k}=-")
    elif k == "we" and isinstance(pv[k], str):
      out.append(f"{k}=x.src[1].dtype.itemsize == 8" if "src[1]" in pv[k] else f"{k}=x.dtype.itemsize == 8")
    else:
      out.append(f"{k}={pv[k]}")
  return ",".join(out)


for name in sorted(PARAMS):
  sv = param_line(name, PARAMS[name])
  row(f'"enc.{name} = [" ++ EncRow("{name}") ++ "]   py=[{sv}]"', f"enc.{name} = [{sv}]")
row(f'"enc.count = [" ++ U32.show(enc_count()) ++ "]   py=[{len(encodings)}]"',
    f"enc.count = [{len(encodings)}]")
row(f'"enc.paramcount = [" ++ U32.show(enc_paramcount()) ++ "]   py=[{len(PARAMS)}]"',
    f"enc.paramcount = [{len(PARAMS)}]")
row(f'"enc.missing = [" ++ enc_missing_names() ++ "]   py=[{names(_missing_encodings())}]"',
    f"enc.missing = [{names(_missing_encodings())}]")
# the `no entry` answer, for all four non-instructions
for nm in _missing_encodings():
  row(f'"enc.none {nm} = [" ++ Bool.show(Enc.is_direct("{nm}")) ++ "]   py=[False]"',
      f"enc.none {nm} = [False]")
  row(f'"enc.norow {nm} = [" ++ EncRow("{nm}") ++ "]   py=[none]"', f"enc.norow {nm} = [none]")
# THE DIRECT-BYTE ENTRIES ARE `Bool` ROWS AGAINST CPython'S OWN BYTES. They were
# BARE STRING CONCATENATIONS ("direct.JMP = [e90000000000]   py=[e900000000]"), which
# is a row that CANNOT FAIL: nothing in the file asserted anything, and `Enc.emit`'s
# six-byte JMP and every wrong opcode survived an ALL PROOFS CHECK. The expected bytes
# are already written on the right-hand side of each row; a `Bool` row against them
# turns the whole class into something the gate sees.
for nm in ("JE", "JNE", "JL", "JB", "JGE", "JMP", "RET"):
  f = fixture_op(nm)
  b = bytes([0xC3]) if nm == "RET" else encodings[X86Ops[nm]](f)
  row(f'"direct.{nm}.{b.hex()} = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("{nm}")), '
      f'"{b.hex()}")) ++ "]   py=[True]"', f"direct.{nm}.{b.hex()} = [True]")
for reg in (0, 1, 7, 8, 15):
  b = encodings[X86Ops.MOVABS](UOp(Ops.INS, (UOp(Ops.CAST, (UOp(Ops.CONST, (), 0x1234, dtypes.i64),),
                                               dtypes.i64),), (X86Ops.MOVABS, dtypes.i64), (GPR[reg],)))
  row(f'"direct.MOVABS {reg}.{b.hex()} = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs({reg}, 4660)), '
      f'"{b.hex()}")) ++ "]   py=[True]"', f"direct.MOVABS {reg}.{b.hex()} = [True]")


# ---------------------------------------------------------------- STAGE 5: the BYTES
# The four non-instructions have no `encodings` entry and `x86.py:761` raises on one, so
# they get no byte row -- `enc.missing` and `enc.none <NAME>` are their rows.
#
# THREE MORE GET NO ROW, and the reason is CPython's and not the port's: `VMOVDm`,
# `VMOVQm` and `VCVTPS2PH` make `encode` RAISE on these fixtures (the first two exhaust
# `_encode`'s arity in the four-src WriteMem shape, the third reaches `rdef(reg_uop).index`
# on a None). There is no byte string to assert and no numbers to hand the port, so
# `_capture` answers None and the row is skipped. Their ENCODING PARAMETERS are gated
# anyway, as the `enc.*` rows for those three names. The previous cut gave them a row
# reading `NOT-ENCODABLE` -- a string concatenation that asserted nothing, three more of
# the eighty.
#
# `hex.*` IS A `Bool` ROW, and the EXPECTED BYTES GO IN THE ROW NAME so the mutation
# harness still names the row it moved and a reader can see what the answer must be
# without running CPython.
for op in [o for o in X86Ops if o in encodings]:
  f = fixture_op(op.name)
  try:
    h = encodings[op](f).hex()
  except Exception as e:
    h = f"RAISES {type(e).__name__}"
  args = enc_inputs(f, op)
  if args is None:
    continue
  assert not h.startswith("RAISES"), f"{op.name} raised but handed the port numbers"
  row('"hex.%s.%s = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("%s", %s)), "%s")) ++ "]   py=[True]"'
      % (op.name, h, op.name, args, h), f"hex.{op.name}.{h} = [True]")


# ---------------------------------------------------------------- STAGE 6: the renderer
# `supported_dtypes` is a SET DIFFERENCE, `{d for d in super().supported_dtypes() if d
# not in dtypes.fp8s+(dtypes.bf16,)}` (x86.py:770), so it gets THREE rows: the base
# set it walks, the names the filter drops, and the answer. The port's version of the
# first was a hardcoded literal of the ANSWER, which asserted nothing about the filter --
# and it spelled the names "short"/"int"/"long"/"double", the C spellings tinygrad
# moved OFF in 793abbb (spec.bend's header, at the top of `Dt`).
BASE_DTYPES = sorted(d.name for d in {d for d in super(X86Renderer, REN).supported_dtypes()})
DROP_DTYPES = sorted(d.name for d in (dtypes.fp8s + (dtypes.bf16,)))
G = {  # the renderer constants, ASKED not transcribed
  "device": X86Renderer.device,
  "has_local": str(X86Renderer.has_local),
  "global_max": " ".join(str(x) for x in X86Renderer.global_max),
  "code_for_op": names(sorted(o.name for o in REN.code_for_op)),
  "base_dtypes": names(BASE_DTYPES),
  "drop_dtypes": names(DROP_DTYPES),
  "supported_dtypes": names(sorted(d.name for d in REN.supported_dtypes())),
}
for k, expr, py in [("device", "Cls.device()", G["device"]), ("has_local", "Bool.show(Cls.has_local())", G["has_local"]),
                    ("global_max", "ClsGmax()", G["global_max"]),
                    ("code_for_op", "Cls.code_for_op()", G["code_for_op"]),
                    ("code_for_op_n", "U32.show(Cls.code_for_op_n())", str(len(REN.code_for_op))),
                    ("base_dtypes", "Cls.base_dtypes()", G["base_dtypes"]),
                    ("base_dtypes_n", "U32.show(Cls.base_dtypes_n())", str(len(BASE_DTYPES))),
                    ("drop_dtypes", "Cls.drop_dtypes()", G["drop_dtypes"]),
                    ("supported_dtypes", "Cls.supported_dtypes()", G["supported_dtypes"]),
                    ("supported_dtypes_n", "U32.show(Cls.supported_dtypes_n())",
                     str(len(REN.supported_dtypes())))]:
  row(f'"cls.{k} = [" ++ {expr} ++ "]   py=[{py}]"', f"cls.{k} = [{py}]")
# the filter itself, one row per DROPPED name sitting next to one row per KEPT name, so
# a filter that drops nothing and a filter that drops everything both move a row.
for nm in BASE_DTYPES:
  v = str(nm in DROP_DTYPES)
  row(f'"cls.drop {nm} = [" ++ Bool.show(Cls.dropped("{nm}")) ++ "]   py=[{v}]"',
      f"cls.drop {nm} = [{v}]")


# ---------------------------------------------------------------- STAGE 7: `asm_str`
# x86.py:728-749. CPython's `asm_str` takes a `list[UOp]` and a UOp graph is not this
# file's type, so the oracle hands the port ONE `AsmOp` per uop carrying only the facts
# the FORMATTER reads, and the port does every part of the formatting. The facts are read
# off the SAME uops CPython formats, so a wrong mnemonic, a wrong padding, a wrong
# operand arm or a missing comma is a diff.
#
# THE FOUR OPERAND ARMS AND THE THREE KINDS ARE CHOSEN HERE, because `u.op is not
# Ops.INS`, `arg[0] is X86Ops.LABEL/RET/DEFINE` and `len(x.src) > 3` / `> 2` are
# properties of the GRAPH. Everything after that -- `o[7:-1] if o[-1] in 'im'`,
# `.lower()`, `:7s`, `_format`, `_mem_adress`, `", ".join`, the `"\n".join` -- is the
# port's, and `Asm.line` is the whole of it.
def _arg(u):
  """`_format`'s per-src expression (x86.py:732-733): a CAST prints its CONST's value and
  anything else prints `reg_strs[rdef(s)].get(rdef(s).size, rdef(s))`. Returns None for
  a src whose `rdef` is None, which `_format` SKIPS."""
  if rdef(u) is None:
    return None
  if u.op is Ops.CAST:
    return f'Asm.imm({u.src[0].val})'
  return f'Asm.reg("{rdef(u)}", {rdef(u).size})'


def _args(us):
  return "[" + ", ".join(a for a in (_arg(u) for u in us) if a is not None) + "]"


def _mem(base, idx, disp):
  """`_mem_adress` (x86.py:734-735). `rdef(idx)` falsy is the EMPTY index string and a
  zero displacement prints as nothing, which is how `idx: String` / `disp: U32` say it."""
  return (f'AsmMem.of("{rdef(base)}", "{"" if rdef(idx) is None else rdef(idx)}", '
          f'{base.dtype.itemsize}, {0 if disp.src[0].val == 0 else disp.src[0].val})')


ASM_PROG = [
  ("skip", lambda: UOp(Ops.NOOP)),                                     # `u.op is not Ops.INS`
  ("define", lambda: UOp(Ops.INS, (), (X86Ops.DEFINE, dtypes.void), (RDX,))),  # DEFINE
  ("label", lambda: UOp(Ops.INS, (), (X86Ops.LABEL, dtypes.void), "L1")),
  # WriteMem: `_mem_adress(*x.src[:3]) + _format(x.src[3:])` -- memory FIRST, and the
  # four-src shape, which is the only one `_mem_adress(*x.src[:3])` can take.
  ("writemem", lambda: UOp(Ops.INS, (MEMBASE, nreg(RCX), cast(const(8), dtypes.int32), nreg(RDX)),
                           (X86Ops.MOVm, dtypes.void), (RDX,))),
  # WriteMem with THREE srcs and an immediate: `_format(x.src[3:])` is empty.
  ("writememimm", lambda: UOp(Ops.INS, (MEMBASE, nreg(RCX), cast(const(0), dtypes.int32)),
                              (X86Ops.MOVi, dtypes.void), (RDX,))),
  # Rm1st: `_format((x,)) + _mem_adress(*x.src[:3]) + _format(x.src[3:])`
  ("rm1st", lambda: UOp(Ops.INS, (MEMBASE, nreg(RCX), cast(const(16), dtypes.int32)),
                        (X86Ops.MOV, dtypes.float32), (RDX,))),
  # Rm1st with NO index and a ONE-BYTE displacement. The displacement is POSITIVE:
  # `AsmMem.disp` is a `U32` and CPython's is a signed `int`, so `f" + {-3}"` has no
  # Bend spelling. MEASURED wall, not a fixture choice -- `U32` has no signed type.
  ("rm1stnoidx", lambda: UOp(Ops.INS, (MEMBASE, nreg(RBX), cast(const(3), dtypes.int8)),
                             (X86Ops.MOVSX, dtypes.int32), (RDX,))),
  # Rm2nd: `_format((x, x.src[0])) + _mem_adress(*x.src[1:4]) + _format(x.src[4:])`.
  # `VADDSS` and NOT `ADD`: `Rm1st` is `{...} | (Rm2nd & TwoAddress)` (x86.py:86), so
  # every Rm2nd arithmetic op is ALSO Rm1st and would be caught by the arm above --
  # MEASURED, `ADD` with five srcs raises IndexError inside CPython's own `asm_str`
  # because the Rm1st arm reads `x.src[:3]` and the third of those is a register.
  ("rm2nd", lambda: UOp(Ops.INS, (nreg(XMM[1]), MEMBASE, nreg(XMM[2]), cast(const(4), dtypes.int32),
                                  nreg(XMM[0])), (X86Ops.VADDSS, dtypes.float32), (XMM[0],))),
  # WriteMem AND Rm1st, four srcs: the WriteMem arm wins on ORDER (x86.py:737 before :738),
  # and the mnemonic is `ADDi`, whose trailing `i` is trimmed to `add`.
  ("writememoverlap", lambda: UOp(Ops.INS, (MEMBASE, nreg(RCX), cast(const(8), dtypes.int32),
                                             imm(dtypes.int32, 3)),
                                  (X86Ops.ADDi, dtypes.void), (RDX,))),
  # plain: `_format((x,) + x.src)` -- an XMM destination (not a `reg_strs` key, so it
  # prints its own name) and an XMM source.
  ("plain", lambda: UOp(Ops.INS, (nreg(XMM[3]), nreg(RDI)), (X86Ops.VADDSS, dtypes.float32), (XMM[0],))),
  # An immediate operand and a register, which is the `else ret = _format((x,) + x.src)`
  # arm: NEITHER `len(x.src) > 3` NOR `len(x.src) > 2` holds, and `ADDi` is in WriteMem
  # and Rm1st both -- so this row is what proves the arm ORDER (WriteMem, then Rm1st,
  # then Rm2nd) and that two memberships do not make a memory operand.
  #
  # THE IMMEDIATE IS `imm(dtypes.int32, 5)` AND NOT `cast(const(5), dtypes.int32)`, and
  # the difference is not cosmetic. MEASURED: `rdef` of a bare CAST is None
  # (`isa/__init__.py:29` returns `u.tag`, and a CAST carries no tag), so `_format`'s
  # `for s in src if rdef(s) is not None` DROPS IT and `s.op is Ops.CAST` never fires.
  # `imm` is `UOp.cconst(...).rtag()` (x86.py:191), which tags it `True`, and `rdef`
  # then answers True -- not None -- so the CAST arm is reachable and prints the value.
  # The two fixtures differ ONLY in the tag and print `5` and nothing respectively.
  ("byte", lambda: UOp(Ops.INS, (imm(dtypes.int32, 5), nreg(RSI)), (X86Ops.ADDi, dtypes.int32), (RDX,))),
  ("ret", lambda: UOp(Ops.INS, (), (X86Ops.RET, dtypes.void))),
  # A NINE-CHARACTER MNEMONIC. `VCVTSI2SS` ends in neither `i` nor `m`, so `:7s` leaves
  # it at nine and pads ZERO -- and `U32.sub` WRAPS, so `7 - 9` is 4294967294 and a port
  # that wrote the field width as a plain subtraction asks `String.repeat` for four
  # billion spaces. Every other mnemonic in this program is four to seven characters.
  ("long", lambda: UOp(Ops.INS, (nreg(XMM[2]), nreg(XMM[1])), (X86Ops.VCVTSI2SS, dtypes.float32), (XMM[0],))),
]
ASM_UOPS = [f() for _, f in ASM_PROG]
ASM_TEXT = REN.asm_str(ASM_UOPS, "kern")


def _asm_op(where, u):
  mn = str(u.arg[0]) if u.op is Ops.INS else ""
  if u.op is not Ops.INS or u.arg[0] is X86Ops.DEFINE:
    return "Asm.skip()"
  if u.arg[0] is X86Ops.LABEL:
    return f'Asm.label("{u.tag}")'
  if u.arg[0] is X86Ops.RET:
    return f'Asm.ret("{mn}")'
  if len(u.src) > 3 and u.arg[0] in X86GroupOp.WriteMem:
    return f'Asm.ins("{mn}", [], True{{}}, {_mem(*u.src[:3])}, {_args(u.src[3:])})'
  if len(u.src) > 2 and u.arg[0] in X86GroupOp.Rm1st:
    return f'Asm.ins("{mn}", {_args((u,))}, True{{}}, {_mem(*u.src[:3])}, {_args(u.src[3:])})'
  if len(u.src) > 3 and u.arg[0] in X86GroupOp.Rm2nd:
    return f'Asm.ins("{mn}", {_args((u, u.src[0]))}, True{{}}, {_mem(*u.src[1:4])}, {_args(u.src[4:])})'
  return f'Asm.ins("{mn}", {_args((u,) + tuple(u.src))}, False{{}}, Asm.none(), Nil{{}})'


ASM_OPS = ", ".join(_asm_op(w, u) for w, u in zip(ASM_PROG, ASM_UOPS))
ASM_LINES = ASM_TEXT.split("\n")
row(f'"asm.lines = [" ++ U32.show(AsmLines_n([{ASM_OPS}])) ++ "]   py=[{len(ASM_LINES) - 1}]"',
    f"asm.lines = [{len(ASM_LINES) - 1}]")
row(f'"asm.total = [" ++ U32.show(AsmN(asm_str("kern", [{ASM_OPS}]))) ++ "]   py=[{len(ASM_LINES)}]"',
    f"asm.total = [{len(ASM_LINES)}]")
# ONE ROW PER LINE, AND THE LINE TEXT GOES IN THE ROW NAME. `asm.L7.<text> = [True]` can
# FAIL, where the old bare `asmtext.L7 = [<text>]` could not -- the eighty `hex.*` rows
# were that shape and all eighty of them disagreed with CPython while the gate was green.
for i, line in enumerate(ASM_LINES):
  row(f'"asm.L{i}.{line} = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [{ASM_OPS}]), '
      f'{i}n), "{line}")) ++ "]   py=[True]"', f"asm.L{i}.{line} = [True]")
# AND THE HEADER, as a row of its own rather than as line zero: `f".{function_name}:"` is
# the one line that is not an instruction, and a mutation that dropped it would move every
# other row too, which makes them unnameable.
row(f'"asm.fn = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("mykern", [{ASM_OPS}]), 0n), '
    f'".mykern:")) ++ "]   py=[True]"', "asm.fn = [True]")

# ---------------------------------------------------------------- STAGE 8: the patch
# `(targets[u.tag] - t).to_bytes(4, 'little', signed=True)` (x86.py:767). The delta is
# SIGNED and a backward jump makes it negative, so the pair that matters is (target < t)
# and the pair that matters MORE is the sign bit: `U32.sub` WRAPS (`Word.sub(32n, x, y)`
# on `Base`), so if it saturated instead, both of these would print `00000000` and a
# backpatching jump would become a jump to address zero. The four bytes are CPython's
# own `to_bytes`, and the row is a `Bool` against them.
for target, t in [(0, 0), (12, 12), (0, 16), (40, 12), (0, 2 ** 20)]:
  b = (target - t).to_bytes(4, "little", signed=True).hex()
  row(f'"render.{target}-{t}.{b} = [" ++ Bool.show(String.eq(Render.le4(Render.delta({target}, {t})), '
      f'"{b}")) ++ "]   py=[True]"', f"render.{target}-{t}.{b} = [True]")
# `targets[u.tag]` and `t` are both BYTE POSITIONS, so the delta fits in a signed 32-bit
# word for any program under two gigabytes and the ONLY way the sign bit is set is a
# NEGATIVE delta -- a backward jump. So the fixtures that matter are the two with
# `target < t`, and `2**31` is not reachable at all: `to_bytes(4, signed=True)` raises
# `OverflowError` on it, which is why it is not in this list.


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


def bend_gate(limit=6000):
  """The `Gate.rowsN()` CHUNKS, replaced wholesale in `x86.bend`.

  `String.concat` is ONE `IO.print` over its arguments and the parser refuses a call with
  this many, and a fold over a list of row-strings costs a step per row, so the gate is
  N list literals joined by `List.concat`. The chunk SIZE is measured in characters and
  not in rows so that one long row cannot unbalance the split."""
  chunks, cur, n = [], [], 0
  for expr, _ in ROWS:
    if cur and sum(len(c) for c in cur) + len(expr) > limit:
      chunks.append(cur)
      cur = []
    cur.append(expr)
  if cur:
    chunks.append(cur)
  out = []
  for i, c in enumerate(chunks):
    out.append(f"def Gate.rows{i}() -> List<&2, String>: [")
    out.extend("   " + e for e in c)
    out.append(" ]")
    out.append("")
  return "\n".join(out), len(chunks)


if __name__ == "__main__":
  mode = sys.argv[1] if len(sys.argv) > 1 else "rows"
  if mode == "tables":
    print(bend_tables())
    raise SystemExit(0)
  if mode == "gate":
    src, nchunks = bend_gate()
    sys.stdout.write(src)
    sys.stderr.write(f"{len(ROWS)} rows in {nchunks} chunks\n")
    raise SystemExit(0)
  if mode not in ("rows", "bend"):
    sys.stderr.write("usage: x86-oracle.py rows|bend|gate|tables\n")
    raise SystemExit(2)
  if mode == "rows":
    # THE REFERENCE IS `NAME = [CPYTHON]   py=[CPYTHON]` -- the ANSWER half is filled
    # with CPython's own answer, because the reference's claim is "this is what the
    # answer must be". So a diff line is a disagreement about the ANSWER and not about
    # the oracle, and the port's half is never consulted to build the reference.
    out = []
    for expr, ref in ROWS:
      # THE REFERENCE IS `NAME = [ANSWER]`, and a NAME MAY NOW CONTAIN `[` AND `]` --
      # every `asm.L*` row carries the assembly line it asserts, and an assembly line is
      # full of `[rsp + rcx*4]`. `ref.index("[")` found the bracket INSIDE the name and
      # produced `py=[rsp + rcx*4 + 8], rdx = [True]` for a row that must read
      # `py=[True]`. The separator is `rindex`d instead, so only the LAST one counts.
      inner = ref[ref.rindex(" = [") + 4:ref.rindex("]")]
      out.append(ref + "   py=[" + inner + "]")
    print("\n".join(out))
  else:
    print("\n".join(expr for expr, _ in ROWS))
  sys.stderr.write(f"{len(ROWS)} rows\n")




