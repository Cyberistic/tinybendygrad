#!/usr/bin/env python3
"""Call CPython for every constant and every pure result renderer/amd/elf.py uses.

Expectations are printed, never typed into the port. Run:
  .venv/bin/python .agents/slop/elf_amd_oracle.py
"""
import ctypes
from tinygrad.helpers import ceildiv, round_up
from tinygrad.runtime.autogen import amdgpu_kd, hsa, libc
from tinygrad.runtime.autogen.amd.common import OpType
from tinygrad.runtime.autogen.amd.rdna3.ins import s_code_end
from tinygrad.runtime.autogen.amd.cdna.ins import s_nop as s_nop_cdna
from tinygrad.renderer.amd.dsl import Reg, FixedBitField, BitField
from tinygrad.uop.ops import UOp, Ops
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.renderer.amd.elf import assemble_linear, _arch_map

def show(name, value, cite):
    print(f"{name}\t{value!r}\t{cite}")

# --- constants, by getattr, not by reading the source ---
SHIFTS = [
    "COMPUTE_PGM_RSRC1_GRANULATED_WORKITEM_VGPR_COUNT_SHIFT",
    "COMPUTE_PGM_RSRC1_GRANULATED_WAVEFRONT_SGPR_COUNT_SHIFT",
    "COMPUTE_PGM_RSRC1_FLOAT_DENORM_MODE_16_64_SHIFT",
    "COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_DX10_CLAMP_SHIFT",
    "COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_IEEE_MODE_SHIFT",
    "COMPUTE_PGM_RSRC1_GFX10_PLUS_MEM_ORDERED_SHIFT",
    "COMPUTE_PGM_RSRC2_USER_SGPR_COUNT_SHIFT",
    "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_X_SHIFT",
    "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Y_SHIFT",
    "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Z_SHIFT",
    "KERNEL_CODE_PROPERTY_ENABLE_SGPR_KERNARG_SEGMENT_PTR_SHIFT",
    "KERNEL_CODE_PROPERTY_ENABLE_WAVEFRONT_SIZE32_SHIFT",
    "COMPUTE_PGM_RSRC3_GFX90A_ACCUM_OFFSET_SHIFT",
]
for n in SHIFTS:
    show(n, getattr(amdgpu_kd, n), "tinygrad/runtime/autogen/amdgpu_kd.py (generated; getattr)")

show("AMD_ISA_ALIGN_BYTES", hsa.AMD_ISA_ALIGN_BYTES, "tinygrad/runtime/autogen/hsa.py:1104")
show("AMD_KERNEL_CODE_ALIGN_BYTES", hsa.AMD_KERNEL_CODE_ALIGN_BYTES, "tinygrad/runtime/autogen/hsa.py:1105")

for n in ("OPR_ACCVGPR", "OPR_SRC_ACCVGPR", "OPR_VGPR_OR_ACCVGPR",
          "OPR_SRC_VGPR_OR_ACCVGPR", "OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST"):
    show(n, getattr(OpType, n).value, "tinygrad/runtime/autogen/amd/common.py OpType (Enum.auto)")

show("s_code_end_bytes", s_code_end().to_bytes().hex(), "rdna3/ins.py s_code_end().to_bytes()")
show("s_nop_cdna_0_bytes", s_nop_cdna(0).to_bytes().hex(), "cdna/ins.py s_nop(0).to_bytes()")
show("s_code_end_len", len(s_code_end().to_bytes()), "len(s_code_end().to_bytes())")
show("s_nop_cdna_0_len", len(s_nop_cdna(0).to_bytes()), "len(s_nop_cdna(0).to_bytes())")

show("sizeof_Elf64_Ehdr", ctypes.sizeof(libc.Elf64_Ehdr), "ctypes.sizeof(libc.Elf64_Ehdr)")
show("sizeof_Elf64_Shdr", ctypes.sizeof(libc.Elf64_Shdr), "ctypes.sizeof(libc.Elf64_Shdr)")
show("sizeof_kd", ctypes.sizeof(amdgpu_kd.llvm_amdhsa_kernel_descriptor_t), "ctypes.sizeof(llvm_amdhsa_kernel_descriptor_t)")
show("SHT_PROGBITS", libc.SHT_PROGBITS, "libc.py SHT_PROGBITS")
show("SHT_STRTAB", libc.SHT_STRTAB, "libc.py SHT_STRTAB")
show("SHF_ALLOC", libc.SHF_ALLOC, "libc.py SHF_ALLOC")
show("SHF_EXECINSTR", libc.SHF_EXECINSTR, "libc.py SHF_EXECINSTR")
show("SHF_ALLOC_EXEC", libc.SHF_ALLOC | libc.SHF_EXECINSTR, "elf.py:94")

# descriptor field offsets, from the live struct, not the OFFSET dict
desc = amdgpu_kd.llvm_amdhsa_kernel_descriptor_t()
for fname, _, off in amdgpu_kd.llvm_amdhsa_kernel_descriptor_t._real_fields_:
    show(f"kd.{fname}.off", off, "llvm_amdhsa_kernel_descriptor_t._real_fields_")

for fname, _, off in libc.Elf64_Ehdr._real_fields_:
    show(f"ehdr.{fname}.off", off, "Elf64_Ehdr._real_fields_")
for fname, _, off in libc.Elf64_Shdr._real_fields_:
    show(f"shdr.{fname}.off", off, "Elf64_Shdr._real_fields_")

print("--- arch map ---")
for k, v in _arch_map.items():
    show(f"arch.{k}", v, "elf.py:14")

# startswith cases, calling the same next() the function uses
def arch_of(arch):
    return next(v for k, v in _arch_map.items() if arch.startswith(k))

for a in ("gfx900", "gfx908", "gfx90a", "gfx942", "gfx1030", "gfx1100", "gfx1101", "gfx1200", "gfx1201"):
    show(f"arch_of.{a}", arch_of(a), "elf.py:44")

print("--- padding / offsets via helpers ---")
def pad_bytes(code_len, inst_len):
    align = hsa.AMD_ISA_ALIGN_BYTES
    n = ((align - code_len % align) % align)
    # n is a BYTE count, and the multiplier is the instruction, so the pad
    # count in instructions is n // inst_len only when n is a multiple.
    return n

for clen in (0, 1, 4, 8, 255, 256, 257, 300, 512, 1000):
    show(f"pad_bytes.{clen}", pad_bytes(clen, 4), "elf.py:49")
    show(f"text_len.{clen}", clen + pad_bytes(clen, 4), "elf.py:49")

show("text_offset", round_up(ctypes.sizeof(libc.Elf64_Ehdr), hsa.AMD_ISA_ALIGN_BYTES), "elf.py:50")

print("--- granules via helpers ---")
def granules(max_vgpr, max_sgpr, max_accvgpr, is_cdna):
    accum_offset = round_up(max_vgpr, 4) if max_accvgpr > 0 else 0
    next_free_vgpr = round_up(accum_offset + max_accvgpr, 8) if max_accvgpr > 0 else round_up(max_vgpr, 8)
    next_free_sgpr = round_up(max_sgpr, 8)
    vgpr_granule = max(0, (next_free_vgpr + 7) // 8 - 1)
    sgpr_granule = max(0, ceildiv(next_free_sgpr + 6, 8) - 1) if is_cdna else 0
    rsrc3 = max(0, accum_offset // 4 - 1) if (is_cdna and max_accvgpr > 0) else 0
    return accum_offset, next_free_vgpr, next_free_sgpr, vgpr_granule, sgpr_granule, rsrc3

fixtures = [
    (0, 0, 0, False),
    (1, 1, 0, False),
    (1, 1, 0, True),
    (4, 8, 0, True),
    (5, 9, 0, False),
    (8, 16, 4, True),
    (7, 3, 1, True),
    (32, 40, 16, True),
    (3, 0, 0, False),
    (0, 0, 4, True),
    (256, 106, 0, False),
    (12, 6, 8, True),
]
for fx in fixtures:
    show(f"gran.{fx}", granules(*fx), "elf.py:54-59,80 via round_up/ceildiv")

print("--- kernarg fold via round_up ---")
def kernarg(sizes):
    acc = 0
    for sz in sizes:
        acc = round_up(acc, sz) + sz
    return acc

for sizes in ([4], [8], [4, 8], [8, 4], [1, 2, 4], [4, 4, 8], [2, 2, 2], [8, 1, 8], []):
    show(f"kernarg.{sizes}", kernarg(sizes), "elf.py:62")

print("--- descriptor words via the live struct and the live shifts ---")
def rsrc(vgpr_g, sgpr_g, is_rdna4, is_cdna, gid0, gid1, gid2, rsrc3_gran):
    r1 = (vgpr_g << amdgpu_kd.COMPUTE_PGM_RSRC1_GRANULATED_WORKITEM_VGPR_COUNT_SHIFT |
          sgpr_g << amdgpu_kd.COMPUTE_PGM_RSRC1_GRANULATED_WAVEFRONT_SGPR_COUNT_SHIFT |
          3 << amdgpu_kd.COMPUTE_PGM_RSRC1_FLOAT_DENORM_MODE_16_64_SHIFT |
          (0 if is_rdna4 else 1) << amdgpu_kd.COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_DX10_CLAMP_SHIFT |
          (0 if is_rdna4 else 1) << amdgpu_kd.COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_IEEE_MODE_SHIFT |
          (0 if is_cdna else 1) << amdgpu_kd.COMPUTE_PGM_RSRC1_GFX10_PLUS_MEM_ORDERED_SHIFT)
    r2 = (2 << amdgpu_kd.COMPUTE_PGM_RSRC2_USER_SGPR_COUNT_SHIFT |
          int(gid0) << amdgpu_kd.COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_X_SHIFT |
          int(gid1) << amdgpu_kd.COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Y_SHIFT |
          int(gid2) << amdgpu_kd.COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Z_SHIFT)
    prop = (1 << amdgpu_kd.KERNEL_CODE_PROPERTY_ENABLE_SGPR_KERNARG_SEGMENT_PTR_SHIFT |
            (0 if is_cdna else 1) << amdgpu_kd.KERNEL_CODE_PROPERTY_ENABLE_WAVEFRONT_SIZE32_SHIFT)
    r3 = rsrc3_gran << amdgpu_kd.COMPUTE_PGM_RSRC3_GFX90A_ACCUM_OFFSET_SHIFT
    return r1, r2, prop, r3

# one row per arch class, with and without each gid, so a swapped shift moves a row
for is_rdna4, is_cdna, tag in ((False, False, "rdna3"), (True, False, "rdna4"), (False, True, "cdna")):
    for gids in ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 1)):
        show(f"rsrc.{tag}.{gids}", rsrc(3, 2, is_rdna4, is_cdna, *gids, 5), "elf.py:67-80")

print("--- strtab name offsets, the loop at elf.py:86-88 ---")
strtab = bytearray(b"\x00")
names = []
for name in [".text", ".rodata", ".strtab"]:
    names.append(len(strtab))
    strtab += name.encode("ascii") + b"\x00"
show("sh_names", names, "elf.py:87")
show("strtab_hex", bytes(strtab).hex(), "elf.py:85-88")
show("strtab_len", len(strtab), "elf.py:92")

print("--- layout for a few text sizes ---")
text_offset = round_up(ctypes.sizeof(libc.Elf64_Ehdr), hsa.AMD_ISA_ALIGN_BYTES)
rodata_size = ctypes.sizeof(amdgpu_kd.llvm_amdhsa_kernel_descriptor_t)
strtab_size = len(strtab)
for text_size in (256, 260, 512, 4, 1024):
    rodata_offset = round_up(text_offset + text_size, hsa.AMD_KERNEL_CODE_ALIGN_BYTES)
    strtab_offset = rodata_offset + rodata_size
    shdr_offset = strtab_offset + strtab_size
    shdrs_size = ctypes.sizeof(libc.Elf64_Shdr) * 3
    total = shdr_offset + shdrs_size
    show(f"layout.{text_size}", (rodata_offset, strtab_offset, shdr_offset, total), "elf.py:90-92,103")

print("--- register scan, using real Reg / FixedBitField / OpType ---")
# A stand-in Inst: assemble_linear reads .operands, ._fields, getattr, acc_cd.
class FakeInst:
    def __init__(self, operands, fields, acc_cd=0):
        self.operands = operands
        self._fields = fields
        self.acc_cd = acc_cd
        for name, val in fields:
            setattr(self, name, val)

def scan(insts):
    max_vgpr, max_sgpr, max_accvgpr = 0, 0, 0
    _ACCVGPR_TYPES = {OpType.OPR_ACCVGPR, OpType.OPR_SRC_ACCVGPR}
    OR_TYPES = {OpType.OPR_VGPR_OR_ACCVGPR, OpType.OPR_SRC_VGPR_OR_ACCVGPR, OpType.OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST}
    for inst in insts:
        accvgpr_fields = set()
        for opr_name, (_, _, opr_type) in inst.operands.items():
            if opr_type in _ACCVGPR_TYPES:
                accvgpr_fields.add(opr_name)
            elif opr_type in OR_TYPES:
                if getattr(inst, "acc_cd", 0) == 1:
                    accvgpr_fields.add(opr_name)
        for name, field in inst._fields:
            if isinstance(field, FixedBitField):
                continue
            val = getattr(inst, name)
            if not isinstance(val, Reg):
                continue
            if 256 <= val.offset < 512:
                if name in accvgpr_fields:
                    max_accvgpr = max(max_accvgpr, (val.offset - 256) + val.sz)
                else:
                    max_vgpr = max(max_vgpr, (val.offset - 256) + val.sz)
            elif val.offset < 106:
                max_sgpr = max(max_sgpr, val.offset + val.sz)
    return max_vgpr, max_sgpr, max_accvgpr

# fixtures that separate vgpr / sgpr / accvgpr / fixed-field skip / acc_cd / boundary
fx_insts = []
# vgpr v0 sz 1 -> max_vgpr 1
fx_insts.append(("v0", FakeInst(
    {"vdst": (None, None, OpType.OPR_VGPR)},
    [("vdst", BitField(7, 0),), ("enc", FixedBitField(31, 31, 1))],
)))
# wait, FakeInst fields are (name, field) and setattr uses the field not the reg.
# Fix: fields list is (name, field_obj) and the value is set separately.

class FI:
    def __init__(self, operands, pairs, acc_cd=0):
        # pairs: (name, field_obj, value)
        self.operands = operands
        self._fields = [(n, f) for n, f, _ in pairs]
        self.acc_cd = acc_cd
        for n, _, v in pairs:
            setattr(self, n, v)

cases = {
    "empty": [],
    "vgpr0": [FI({"vdst": (None, None, None)}, [("vdst", BitField(7, 0), Reg(256, 1))])],
    "vgpr5sz2": [FI({}, [("vdst", BitField(7, 0), Reg(261, 2))])],
    "sgpr3sz1": [FI({}, [("sdst", BitField(7, 0), Reg(3, 1))])],
    "sgpr105": [FI({}, [("sdst", BitField(7, 0), Reg(105, 1))])],  # offset 105 is NOT < 106? 105 < 106, yes. max = 105+1 = 106
    "sgpr106": [FI({}, [("sdst", BitField(7, 0), Reg(106, 1))])],  # VCC, not < 106, not in 256..512
    "acc": [FI({"vdst": (None, None, OpType.OPR_ACCVGPR)}, [("vdst", BitField(7, 0), Reg(256, 4))])],
    "src_acc": [FI({"src0": (None, None, OpType.OPR_SRC_ACCVGPR)}, [("src0", BitField(8, 0), Reg(260, 1))])],
    "or_off": [FI({"vdst": (None, None, OpType.OPR_VGPR_OR_ACCVGPR)}, [("vdst", BitField(7, 0), Reg(258, 1))], acc_cd=0)],
    "or_on": [FI({"vdst": (None, None, OpType.OPR_VGPR_OR_ACCVGPR)}, [("vdst", BitField(7, 0), Reg(258, 1))], acc_cd=1)],
    "or_src": [FI({"src0": (None, None, OpType.OPR_SRC_VGPR_OR_ACCVGPR)}, [("src0", BitField(8, 0), Reg(270, 2))], acc_cd=1)],
    "or_const": [FI({"src0": (None, None, OpType.OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST)}, [("src0", BitField(8, 0), Reg(256, 1))], acc_cd=1)],
    "fixed_skip": [FI({}, [("enc", FixedBitField(31, 31, 1), Reg(256, 8)), ("vdst", BitField(7, 0), Reg(256, 1))])],
    "not_reg": [FI({}, [("imm", BitField(15, 0), 7)])],
    "both": [FI({"vdst": (None, None, OpType.OPR_ACCVGPR)},
                [("vdst", BitField(7, 0), Reg(256, 2)), ("sdst", BitField(6, 0), Reg(4, 2))])],
    "hi_vgpr": [FI({}, [("vdst", BitField(7, 0), Reg(511, 1))])],  # offset 511 < 512, idx 255+1 = 256
    "vgpr512": [FI({}, [("vdst", BitField(7, 0), Reg(512, 1))])],  # not < 512
}
for name, insts in cases.items():
    show(f"scan.{name}", scan(insts), "elf.py:21-35 using real Reg/FixedBitField/OpType")

print("--- try assemble_linear ---")
try:
    nop = s_nop_cdna(0)
    u = UOp(Ops.CUSTOM, arg=(nop,))
    # discover what lin.src items look like: arg[0] must be the inst
    print("nop type", type(nop), "has to_bytes", hasattr(nop, "to_bytes"))
    print("operands sample", list(getattr(nop, "operands", {}).items())[:4])
    print("_fields sample", getattr(nop, "_fields", None))
except Exception as e:
    print("probe inst failed", type(e), e)

# Build a sink with PARAM / BUFFER / SPECIAL and call assemble_linear.
try:
    sink = UOp(Ops.SINK)
    prg = UOp(Ops.PROGRAM, src=(sink,))
    lin = UOp(Ops.LINEAR, src=(UOp(Ops.CUSTOM, arg=(s_code_end(),)),))
    blob = assemble_linear(prg, lin, "gfx1100")
    print("assemble gfx1100 len", len(blob), blob[:16].hex())
except Exception as e:
    print("assemble failed", type(e).__name__, e)
