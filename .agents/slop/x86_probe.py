#!/usr/bin/env python3
"""PROBE: can CPython's x86.py be DRIVEN -- encode() and asm_str() called for real?

Answers, by asking, four things the port's staging depends on:
  1. does `Target(arch="x86_64")` construct without a device?
  2. can a synthetic UOp be built with a Register tag, so `asm_str` formats it?
  3. do `encode()` / `encodings[op](x)` return real bytes for a synthetic UOp?
  4. what is `X86Ops`' integer assignment (auto()) -- read, never transcribed?
"""
import sys, struct
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[2]))
from tinygrad.helpers import Target
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.renderer.isa.x86 import (X86Ops, X86GroupOp, Register, RAX, RCX, RDX, RSP, RSI, RDI, XMM, GPR, WGPR,
                                       CALLEE_SAVED, reg_strs, encodings, X86Renderer, _xmm_sz, _xmm_sz_m, to_int,
                                       to_imm, imm, is_address, fold_address, fold_address as fa, _is_vec_xmm, flag_gate)

print("== 1 Target ==")
try:
  t = Target(arch="x86_64")
  print("  Target OK", t)
except Exception as e:
  print("  Target FAIL", type(e).__name__, e)
print("  platform =", sys.platform)

print("== 2 asm_str ==")
ren = X86Renderer(Target(arch="x86_64"))
print("  renderer OK; code_for_op =", sorted(x.name for x in ren.code_for_op))

def ins(op, dt, srcs=(), tag=None):
  return UOp(Ops.INS, arg=(op, dt), src=srcs, tag=tag)

u1 = ins(X86Ops.MOV, dtypes.i32, (UOp(Ops.NOOP, tag=(RCX,)),), tag=(RDX,))
print("  MOV asm:", repr(ren.asm_str([u1], "f")))

u2 = ins(X86Ops.ADD, dtypes.i32, (UOp(Ops.NOOP, tag=(RCX,)), UOp(Ops.NOOP, tag=(XMM[3],))), tag=(RDX,))
print("  ADD asm:", repr(ren.asm_str([u2], "f")))

# memory operand: three srcs = (base, idx, disp)
base = UOp(Ops.NOOP, tag=(RSP,))
idx = UOp(Ops.NOOP, tag=(RCX,))
disp = UOp(Ops.CAST, dtypes.i32, (UOp(Ops.CONST, dtypes.i32, arg=8),))
mv = ins(X86Ops.MOVm, dtypes.void, (base, idx, disp, UOp(Ops.NOOP, tag=(RDX,))))
print("  MOVm asm:", repr(ren.asm_str([mv], "f")))

print("== 3 encode ==")
print("  MOV  bytes:", encodings[X86Ops.MOV](ins(X86Ops.MOV, dtypes.i32, (UOp(Ops.NOOP, tag=(RCX,)),), tag=(RDX,))).hex())
print("  ADD  bytes:", encodings[X86Ops.ADD](ins(X86Ops.ADD, dtypes.i32, (UOp(Ops.NOOP, tag=(RCX,)), UOp(Ops.NOOP, tag=(RDX,))), tag=(RCX,))).hex())
print("  RET  bytes:", encodings[X86Ops.RET](ins(X86Ops.RET, dtypes.void)).hex())
v = ins(X86Ops.VADDSS, dtypes.f32, (UOp(Ops.NOOP, tag=(XMM[1],)), UOp(Ops.NOOP, tag=(XMM[2],))), tag=(XMM[0],))
print("  VADDSS bytes:", encodings[X86Ops.VADDSS](v).hex())

print("== 4 X86Ops numbers ==")
print("  n =", len(list(X86Ops)), "first =", X86Ops.FRAME_INDEX.value, "last =", X86Ops.RET.value)
print("  LEAs =", X86Ops.LEA.value, "MOVABS =", X86Ops.MOVABS.value)

print("== 5 registers ==")
print("  GPR n =", len(GPR), "XMM n =", len(XMM), "WGPR n =", len(WGPR), "CALLEE n =", len(CALLEE_SAVED))
print("  GPR =", [(r.name, r.index, r.size) for r in GPR])
print("  XMM =", [(r.name, r.index, r.size) for r in XMM])
print("  CALLEE =", [r.name for r in CALLEE_SAVED])
print("  reg_strs =", {k: sorted(v.items()) for k, v in sorted(reg_strs.items())})

print("== 6 pure decisions ==")
for op in (X86Ops.MOV, X86Ops.MOVm, X86Ops.CMOVB, X86Ops.VADDSS, X86Ops.LEA):
  print(f"  X86Ops.{op.name} = {op.value}")
print("  _xmm_sz f32 x4: need a UOp")

# a vector UOp: INDEX over a GPR-ish src, shape (4,)
def vec(dt, n):
  return UOp(Ops.INDEX, dt, (UOp(Ops.PARAM, dt, arg=0), UOp(Ops.CONST, dtypes.i32, arg=0)), arg=UOp(Ops.SPECIAL, arg=(0, dt, "s")))

print("== 7 sets ==")
for nm in ("Copy", "TwoAddress", "Rm2nd", "WriteMem", "ReadFlags", "WriteFlags", "Rm1st"):
  s = getattr(X86GroupOp, nm)
  print(f"  {nm} n={len(s)} names={[o.name for o in sorted(s, key=lambda z: z.value)]}")
