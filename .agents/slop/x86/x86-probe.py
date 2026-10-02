#!/usr/bin/env python3
"""x86-probe.py -- BYTE-LEVEL ground truth for `encode`, split BY STAGE.

`Enc.emit` is wrong and the row diff says WHICH leading bytes survive but not WHY.
`x86.encode` is patched for the duration of the run, so every `encodings[...]` lambda
routes through the instrumented copy and the SAME expression order as x86.py:544-595 is
preserved; `inst` is snapshotted after each accumulation point, which makes a wrong JOIN
visible as a wrong stage boundary rather than as a wrong hex string.

`trace_encode` asserts nothing: the answer it builds is compared against the answer the
REAL `encode` built for the same fixture, so this probe cannot silently disagree with
CPython.

    .venv/bin/python .agents/slop/x86/x86-probe.py [OPNAME ...]
"""
import struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).parent))

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.helpers import unwrap
from tinygrad.renderer.isa import rdef, Register
import tinygrad.renderer.isa.x86 as X
from x86_oracle import fixture_op  # the SAME fixtures the rows use

REAL = X.encode
LOG = []


def trace_encode(x, opc, reg=None, pp=0, sel=0, we=0):
  def _encode(reg_uop, rm_uop, idx_uop=None, disp_uop=None, vvvv_uop=None, imm_uop=None):
    nonlocal reg, opc
    reg = rdef(reg_uop).index if reg_uop is not None else reg
    rm = rdef(rm_uop).index
    idx = rdef(idx_uop).index if idx_uop is not None and rdef(idx_uop) is not None else 4
    rm_sz = rm_uop.dtype.itemsize if disp_uop is not None else (
      rm_uop.dtype.itemsize if rm_uop.op is Ops.BITCAST else rdef(rm_uop).size)
    reg_sz = (reg_uop.dtype.itemsize if reg_uop.op is Ops.BITCAST else rdef(reg_uop).size) if reg_uop is not None else 0
    sz = reg_sz or rm_sz
    inst = bytes([])
    r, _x, b = reg >> 3, idx >> 3, rm >> 3
    marks = [inst.hex()]
    demote = False
    if sel:
      vvvv = (vd.index if isinstance(vd := rdef(vvvv_uop), Register) else reg) if vvvv_uop is not None else 0
      if sel == 1 and _x == b == we == 0:
        inst += bytes([0xC5, (~r & 0b1) << 7 | (~vvvv & 0b1111) << 3 | pp])
      else:
        inst += bytes([0xC4, (~r & 0b1) << 7 | (~_x & 0b1) << 6 | (~b & 0b1) << 5 | sel,
                       we << 7 | (~vvvv & 0b1111) << 3 | pp])
    else:
      w = sz == 8
      demote = (rm_sz == 1 or reg_sz == 1) and x.arg[0] not in (X.X86GroupOp.ReadFlags | {X.X86Ops.LEA})
      if sz == 2:
        inst += bytes([0x66])
      if (w | r | _x | b | (reg_sz == 1 & reg >> 2) | (rm_sz == 1 & rm >> 2)
          | (demote and disp_uop is None and rm >= 4)):
        inst += bytes([0b0100 << 4 | w << 3 | r << 2 | _x << 1 | b])
      if demote:
        opc -= 1
    marks.append(inst.hex())
    inst += opc.to_bytes((opc.bit_length() + 7) // 8, 'big')
    marks.append(inst.hex())
    idx, rm, reg = idx & 0b111, rm & 0b111, reg & 0b111
    if disp_uop is not None:
      mod = (0b01 if disp_uop.dtype.itemsize == 1 else 0b10) if (
        disp_uop.src[0].val != 0 or rm == 0b101) else 0b00
    else:
      mod = 0b11
    _rm = rm if idx == 0b100 and _x == 0b0 else 0b100
    inst += bytes([mod << 6 | reg << 3 | _rm])
    marks.append(inst.hex())
    if _rm == 0b100 and mod != 0b11:
      scale = {1: 0b00, 2: 0b01, 4: 0b10, 8: 0b11}[1 if idx == 0b100 and _x == 0b0 else rm_sz]
      inst += bytes([scale << 6 | idx << 3 | rm])
    marks.append(inst.hex())
    if mod == 0b01 or mod == 0b10:
      inst += struct.pack(unwrap(disp_uop.dtype.fmt), disp_uop.src[0].val)
    marks.append(inst.hex())
    if imm_uop is not None:
      if imm_uop.op is Ops.CAST:
        inst += struct.pack(unwrap(imm_uop.dtype.fmt), imm_uop.src[0].val)
      elif isinstance(rdef(imm_uop), Register):
        inst += bytes([(rdef(imm_uop).index & 0b1111) << 4 | 0b0000])
    marks.append(inst.hex())
    LOG.append((x.arg[0].name, marks, dict(reg=reg, rm=rm, idx=idx, rm_sz=rm_sz, reg_sz=reg_sz,
                 sz=sz, r=r, x=_x, b=b, mod=mod, _rm=_rm, demote=demote, opc=opc)))
    return inst

  if x.arg[0] in X.X86GroupOp.WriteMem:
    if len(x.src) > 3: address, rest = x.src[:3], x.src[3:]
    else: address, rest = (x, None, None), x.src
    imm_uop = rest[:1] if rest and rest[0].op is Ops.CAST else (None,)
    return _encode(rest[0], *address, None, *rest[1:]) if reg is None else _encode(None, *address, None, *imm_uop)
  if x.arg[0] in X.X86GroupOp.Rm1st:
    if len(x.src) > 2: address, rest = x.src[:3], x.src[3:]
    else: address, rest = (x.src[0], None, None), x.src[1:]
    imm_uop = rest[:1] if rest and rest[0].op is Ops.CAST else (None,)
    return _encode(x, *address, None, *imm_uop) if reg is None else _encode(None, *address, *(x if sel else None, *imm_uop))
  if x.arg[0] in X.X86GroupOp.Rm2nd:
    if len(x.src) > 3: address, rest = x.src[1:4], x.src[:1] + x.src[4:]
    else: address, rest = (x.src[1], None, None), x.src[:1] + x.src[2:]
    return _encode(x, *address, *rest) if x.dtype is not dtypes.void else _encode(rest[0], *address)
  return None


NAMES = ["", "pfx/rex/vex", "opcode", "modrm", "sib", "disp", "imm"]

if __name__ == "__main__":
  want = set(sys.argv[1:])
  # TRUTH FIRST, with the REAL `encode` in place, so the instrumented copy is checked
  # against CPython and not against itself.
  truth = {}
  for op in X.X86Ops:
    f = fixture_op(op.name)
    if f is None or op not in X.encodings:
      continue
    try:
      truth[op.name] = X.encodings[op](f)
    except Exception as e:
      truth[op.name] = f"RAISES {type(e).__name__}: {e}"
  X.encode = trace_encode
  for op in X.X86Ops:
    if want and op.name not in want:
      continue
    if op.name not in truth:
      continue
    t = truth[op.name]
    if isinstance(t, str):
      print(f"{op.name}: {t}")
      continue
    f = fixture_op(op.name)
    LOG.clear()
    X.encodings[op](f)
    if not LOG:
      print(f"{op.name} = {t.hex()}   DIRECT BYTES, no `encode` call")
      continue
    nm, marks, nums = LOG[-1]
    assert marks[-1] == t.hex(), (nm, marks[-1], t.hex())
    print(f"{nm} = {t.hex()}   stages {' | '.join(NAMES)}")
    print(f"   {' | '.join(marks)}")
    print("   " + " ".join(f"{k}={v}" for k, v in nums.items()))