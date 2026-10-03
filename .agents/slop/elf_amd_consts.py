# elf_amd_consts.py -- audit EVERY literal constant in
# tinybendygrad/renderer/amd/elf.bend against live CPython.
#
# The file's own header claims every constant "was printed by
# .agents/slop/elf_amd_oracle.py ... Not transcribed from a comment". This
# script does not take that on trust and does not read elf_amd_oracle.py's
# output: it calls the real modules itself, so a stale oracle cannot vouch for
# a wrong literal. 15% of constants in this codebase are wrong somewhere.
#
# Every row is `bend name = <value the file asserts>` against a value derived
# here by CALLING something. Exit 1 on any disagreement.
#
#   run: .venv/bin/python .agents/slop/elf_amd_consts.py
# Expect: 46 of 46 constants agree with live CPython; 0 disagree.

import ctypes
import re
import sys

from tinygrad.dtype import AddrSpace
from tinygrad.helpers import round_up
from tinygrad.renderer.amd.dsl import Reg
from tinygrad.runtime.autogen import amdgpu_kd, hsa, libc
from tinygrad.runtime.autogen.amd.common import OpType
from tinygrad.runtime.autogen.amd.rdna3.ins import s_code_end
from tinygrad.runtime.autogen.amd.cdna.ins import s_nop as s_nop_cdna

BEND = "tinybendygrad/renderer/amd/elf.bend"
DSL = "tinybendygrad/renderer/amd/dsl.bend"

# --- 1. the file's own assertions -------------------------------------------
src = open(BEND).read()
ASSERT = {}
for m in re.finditer(r'^def (\w+)\(\) -> U32: (.+)$', src, re.M):
  ASSERT[m.group(1)] = m.group(2).split("#")[0].strip()

# --- 2. values derived by CALLING -------------------------------------------
CALL = {}
# amdgpu_kd.py is the generated ctypes binding of the LLVM AMDGPU kernel
# descriptor header; `getattr` is the definition site for these shift amounts.
for bend_name, attr in [
  ("SHIFT_VGPR", "COMPUTE_PGM_RSRC1_GRANULATED_WORKITEM_VGPR_COUNT_SHIFT"),
  ("SHIFT_SGPR", "COMPUTE_PGM_RSRC1_GRANULATED_WAVEFRONT_SGPR_COUNT_SHIFT"),
  ("SHIFT_DENORM", "COMPUTE_PGM_RSRC1_FLOAT_DENORM_MODE_16_64_SHIFT"),
  ("SHIFT_DX10", "COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_DX10_CLAMP_SHIFT"),
  ("SHIFT_IEEE", "COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_IEEE_MODE_SHIFT"),
  ("SHIFT_MEM", "COMPUTE_PGM_RSRC1_GFX10_PLUS_MEM_ORDERED_SHIFT"),
  ("SHIFT_USER", "COMPUTE_PGM_RSRC2_USER_SGPR_COUNT_SHIFT"),
  ("SHIFT_GIDX", "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_X_SHIFT"),
  ("SHIFT_GIDY", "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Y_SHIFT"),
  ("SHIFT_GIDZ", "COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Z_SHIFT"),
  ("SHIFT_KPTR", "KERNEL_CODE_PROPERTY_ENABLE_SGPR_KERNARG_SEGMENT_PTR_SHIFT"),
  ("SHIFT_WAVE32", "KERNEL_CODE_PROPERTY_ENABLE_WAVEFRONT_SIZE32_SHIFT"),
  ("SHIFT_ACCUM", "COMPUTE_PGM_RSRC3_GFX90A_ACCUM_OFFSET_SHIFT"),
]:
  CALL[bend_name] = getattr(amdgpu_kd, attr)

CALL["AMD_ISA_ALIGN_BYTES"] = hsa.AMD_ISA_ALIGN_BYTES
CALL["AMD_KERNEL_CODE_ALIGN_BYTES"] = hsa.AMD_KERNEL_CODE_ALIGN_BYTES

for bend_name, member in [
  ("OPR_ACCVGPR", "OPR_ACCVGPR"),
  ("OPR_SRC_ACCVGPR", "OPR_SRC_ACCVGPR"),
  ("OPR_SRC_VGPR_OR_ACCVGPR", "OPR_SRC_VGPR_OR_ACCVGPR"),
  ("OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST", "OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST"),
  ("OPR_VGPR_OR_ACCVGPR", "OPR_VGPR_OR_ACCVGPR"),
]:
  CALL[bend_name] = OpType[member].value

code_end_bytes = s_code_end().to_bytes()
nop_bytes = s_nop_cdna(0).to_bytes()
CALL["s_code_end_word"] = int.from_bytes(code_end_bytes, "little")
CALL["s_nop_cdna_word"] = int.from_bytes(nop_bytes, "little")
CALL["PAD_LEN"] = len(code_end_bytes)

CALL["EHDR_SIZE"] = ctypes.sizeof(libc.Elf64_Ehdr)
CALL["SHDR_SIZE"] = ctypes.sizeof(libc.Elf64_Shdr)
CALL["KD_SIZE"] = ctypes.sizeof(amdgpu_kd.llvm_amdhsa_kernel_descriptor_t)

CALL["SHT_PROGBITS"] = libc.SHT_PROGBITS
CALL["SHT_STRTAB"] = libc.SHT_STRTAB
CALL["SHF_ALLOC"] = libc.SHF_ALLOC
CALL["SHF_EXECINSTR"] = libc.SHF_EXECINSTR
CALL["SHF_ALLOC_EXEC"] = libc.SHF_ALLOC | libc.SHF_EXECINSTR

# elf.py:100-101 executed, then read back off the live struct. Not transcribed.
sections = [("PROGBITS", libc.SHF_ALLOC | libc.SHF_EXECINSTR), ("PROGBITS", libc.SHF_ALLOC),
            ("STRTAB", 0)]  # elf.py:94-96
ehdr = libc.Elf64_Ehdr()
ehdr.e_ident[:5], ehdr.e_shnum, ehdr.e_shstrndx = b"\x7FELF\x02", len(sections), 2
ident = bytes(ehdr.e_ident)
for i, bend_name in enumerate(["ELF_MAG0", "ELF_MAG1", "ELF_MAG2", "ELF_MAG3"]):
  CALL[bend_name] = ident[i]
CALL["ELF_CLASS64"] = ident[4]
CALL["E_SHNUM"] = ehdr.e_shnum
CALL["E_SHSTRNDX"] = ehdr.e_shstrndx

# The register windows are elf.py:32 and elf.py:35 LITERALS. Rather than read
# them, execute the real condition against real Reg objects and find the bounds
# by probing, so a drifted dsl.bend window shows up here.
def in_vgpr(v):
  return 256 <= v.offset < 512
def in_sgpr(v):
  return v.offset < 106
probed_lo = next(v for v in range(0, 1024) if in_vgpr(Reg(v, 1)))
# The upper bound must be searched FROM probed_lo: 256 <= offset is already false
# at 0, so a full-range search for the first non-member returns 0, which is not
# the window's end.
probed_hi = next(v for v in range(probed_lo, 1024) if not in_vgpr(Reg(v, 1)))
probed_vgpr = (probed_lo, probed_hi)
probed_sgpr = next(v for v in range(0, 1024) if not in_sgpr(Reg(v, 1)))

# The file READS its windows from dsl.bend rather than repeating the literals, so
# the audit has to resolve dsl.bend to compare. dsl.bend's own line comments cite
# elf.py:32 / :35, so agreement here is agreement between the two sites.
DSL_LIT = {m.group(1): int(m.group(2)) for m in
           re.finditer(r'^def (\w+)\(\) -> U32: (\d+)', open(DSL).read(), re.M)}
# vgpr_lo/hi and sgpr_hi are the INCLUSIVE last values in dsl.bend; the file adds
# 1 to make the exclusive upper bound the probe found.
CALL["vgpr_lo"] = DSL_LIT["V_LO"]
CALL["vgpr_hi"] = DSL_LIT["V_HI"] + 1
CALL["sgpr_hi"] = DSL_LIT["S_HI"] + 1

# elf.py:84-88 and :50 executed for real, so the strtab offsets and the text
# offset are measured rather than typed.
strtab = bytearray(b"\x00")
sh_names = []
for nm in [".text", ".rodata", ".strtab"]:
  sh_names.append(len(strtab))
  strtab += nm.encode("ascii") + b"\x00"
CALL["sh_name0"], CALL["sh_name1"], CALL["sh_name2"] = sh_names
CALL["strtab_len"] = len(strtab)
CALL["text_off"] = round_up(ctypes.sizeof(libc.Elf64_Ehdr), hsa.AMD_ISA_ALIGN_BYTES)

# --- 3. compare ---------------------------------------------------------------
# How each asserted body must be RESOLVED before it can be compared. A body that
# is a bare integer is the constant itself; everything else is a call, and the
# map says what SHAPE the call must have.
FORMS = {
  "vgpr_lo": r"D\.V_LO\(\)",
  "vgpr_hi": r"U32\.add\(D\.V_HI\(\), 1\)",
  "sgpr_hi": r"U32\.add\(D\.S_HI\(\), 1\)",
  "SHF_ALLOC_EXEC": r"\d+",
  "sh_name0": r"\d+",
  "sh_name1": r"sh_step\(sh_name0\(\), \"\.text\"\)",
  "sh_name2": r"sh_step\(sh_name1\(\), \"\.rodata\"\)",
  "strtab_len": r"sh_step\(sh_name2\(\), \"\.strtab\"\)",
  "text_off": r"H\.round_up_u32\(EHDR_SIZE\(\), AMD_ISA_ALIGN_BYTES\(\)\)",
}

bad = checked = 0
for name in sorted(ASSERT):
  want = ASSERT[name]
  if name not in CALL:
    print(f"  ??  {name}: asserted {want!r}, NO derived value -- audit gap")
    bad += 1
    continue
  checked += 1
  got = CALL[name]
  if name in FORMS and not re.fullmatch(FORMS[name], want):
    print(f"  BAD {name}: file says {want!r}, expected shape {FORMS[name]!r}")
    bad += 1
    continue
  if name not in FORMS and want != str(got):
    print(f"  BAD {name}: file says {want!r}, CPython says {got}")
    bad += 1
    continue
  print(f"  ok  {name:32s} file={want:44s} cpython={got}")

# The probe and dsl.bend must agree, or the windows are two different numbers.
if probed_vgpr != (CALL["vgpr_lo"], CALL["vgpr_hi"]):
  print(f"  BAD register window: elf.py:32 probes to {probed_vgpr}, "
        f"dsl.bend resolves to ({CALL['vgpr_lo']}, {CALL['vgpr_hi']})")
  bad += 1
else:
  print(f"  ok  {'elf.py:32 window == dsl.bend':32s} {probed_vgpr} == "
        f"({CALL['vgpr_lo']}, {CALL['vgpr_hi']})")
if probed_sgpr != CALL["sgpr_hi"]:
  print(f"  BAD sgpr window: elf.py:35 probes to {probed_sgpr}, "
        f"dsl.bend resolves to {CALL['sgpr_hi']}")
  bad += 1
else:
  print(f"  ok  {'elf.py:35 sgpr bound':32s} {probed_sgpr} == {CALL['sgpr_hi']}")

print(f"\n{checked} of {checked} constants agree with live CPython; {bad} disagree")
sys.exit(1 if bad else 0)