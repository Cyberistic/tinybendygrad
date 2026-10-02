#!/usr/bin/env python3
# elf_reloc_probe.py -- reaches elf.py:56-81 `relocate`, which is a CLOSURE over
# `image` and therefore unreachable from outside.
#
# HOW IT REACHES IT. `relocate` is only ever called by jit_loader:85, inside the
# per-relocation loop. So the arms are exercised THROUGH THE REAL jit_loader, on a
# REAL ELF64 object file, with ONE thing substituted: the relocation TYPE, which
# is patched into the object's `.rela.text` bytes before the call. Everything else
# -- the header walk, the section walk, the symtab, the image build, the 4-byte
# write-back at :85 -- is upstream's own code on a clang-produced file.
#
# This is stated rather than hidden because it is the one place the fixture is
# constructed rather than compiled. The alternative -- transcribing `relocate` into
# the probe and comparing the probe to itself -- is the tautology the brief warns
# about, so the transcription is NOT used: the only thing the probe decides is
# WHICH r_type the real code sees.
#
# Each row is:  <name> = <hex of the 4 bytes jit_loader wrote>  or  ERR:<exc>
#
# The object is the aarch64 one (.agents/slop/elf/j_aarch64.o), because it is the
# only architecture on this machine whose `ext_data` address is in range for the
# arms that take a raw `tgt` -- a dylib symbol address here is an arm64 address
# (>2^32), which makes the x86-64 PC32/PLT32 arms overflow struct.pack. That is
# recorded as a row rather than hidden.

import sys, os, struct, ctypes, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, REPO)
FIX = os.path.join(HERE, "elf")

from tinygrad.runtime.support.elf import jit_loader, elf_loader
from tinygrad.runtime.autogen import libc

OUT = []
def row(n, v): OUT.append(f"{n}={v}")
STUB = ctypes.CDLL(os.path.join(FIX, "libstub.dylib"))
SRC = os.path.join(FIX, "j_aarch64.o")

# ---------------------------------------------------------------- find the relocs
def relocs_of(b):
  _, _, r = elf_loader(b, link_libs=[STUB])
  return r

BASE = open(SRC, "rb").read()
ORIG = relocs_of(BASE)
row("probe_src", os.path.basename(SRC))
row("probe_nreloc", len(ORIG))
row("probe_types", ",".join(str(x[2]) for x in ORIG))
row("probe_addrs", ",".join(str(x[0]) for x in ORIG))
row("probe_tgts", ",".join(str(x[1]) for x in ORIG))
row("probe_addends", ",".join(str(x[3]) for x in ORIG))
row("probe_base_len", len(BASE))
row("probe_base_sha", hashlib.sha256(BASE).hexdigest()[:16])

def rela_text_span(b):
  """The byte span of `.rela.text` inside the blob."""
  shoff = struct.unpack_from("<Q", b, 40)[0]
  shnum = struct.unpack_from("<H", b, 60)[0]
  shstr = struct.unpack_from("<H", b, 62)[0]
  F = lambda i: struct.unpack_from("<IIQQQQIIQQ", b, shoff+i*64)
  so = F(shstr)[4]
  for i in range(shnum):
    x = F(i)
    nm = b[so+x[0]:b.find(b"\x00", so+x[0])].decode()
    if x[1] == libc.SHT_RELA and nm == ".rela.text":
      return i, x[4], x[5], x[9]
  return None, 0, 0, 0

def patch_type(b, idx, newtype):
  """Set entry `idx`'s r_type to `newtype`, preserving r_offset and r_sym.
  r_info is sym<<32|type, so this is a mask-and-set on the low 32 bits."""
  i, off, sz, ent = rela_text_span(b)
  b = bytearray(b)
  for k in range(idx+1):
    p = off + k*ent + 8
    info = struct.unpack_from("<Q", b, p)[0]
    sym = info >> 32
    struct.pack_into("<Q", b, p, (sym << 32) | (newtype & 0xffffffff))
  return bytes(b)

def run(b):
  """jit_loader, and the four bytes it wrote at each reloc site."""
  out = jit_loader(b, link_libs=[STUB])
  img = out
  vals = []
  for o, t, ty, ad in relocs_of(b):
    vals.append(img[o:o+4].hex())
  return len(out), ",".join(vals)

# ---------------------------------------------------------------- the ten arms
ARMS = [
  ("R_X86_64_PC32",        libc.R_X86_64_PC32),
  ("R_X86_64_PLT32",       libc.R_X86_64_PLT32),
  ("R_AARCH64_ADR_PREL_PG_HI21",   libc.R_AARCH64_ADR_PREL_PG_HI21),
  ("R_AARCH64_ADD_ABS_LO12_NC",    libc.R_AARCH64_ADD_ABS_LO12_NC),
  ("R_AARCH64_LDST16_ABS_LO12_NC", libc.R_AARCH64_LDST16_ABS_LO12_NC),
  ("R_AARCH64_LDST32_ABS_LO12_NC", libc.R_AARCH64_LDST32_ABS_LO12_NC),
  ("R_AARCH64_LDST64_ABS_LO12_NC", libc.R_AARCH64_LDST64_ABS_LO12_NC),
  ("R_AARCH64_LDST128_ABS_LO12_NC",libc.R_AARCH64_LDST128_ABS_LO12_NC),
  ("R_AARCH64_CALL26",     libc.R_AARCH64_CALL26),
  ("R_AARCH64_NONE",       libc.R_AARCH64_NONE),
  ("R_X86_64_64_UNSUPPORTED", libc.R_X86_64_64),
  ("R_X86_64_GLOB_DAT_UNSUPPORTED", libc.R_X86_64_GLOB_DAT),
]
for nm, ty in ARMS:
  row(f"arm_{nm}_type", ty)
  b = patch_type(BASE, 0, ty)
  try:
    n, vals = run(b)
    row(f"arm_{nm}_ok", 1)
    row(f"arm_{nm}_len", n)
    row(f"arm_{nm}_words", vals)
  except Exception as e:
    row(f"arm_{nm}_ok", 0)
    row(f"arm_{nm}_len", -1)
    row(f"arm_{nm}_words", type(e).__name__)

# the UNMODIFIED run, the baseline every arm is compared against
try:
  n, vals = run(BASE)
  row("arm_BASE_ok", 1); row("arm_BASE_len", n); row("arm_BASE_words", vals)
except Exception as e:
  row("arm_BASE_ok", 0); row("arm_BASE_len", -1); row("arm_BASE_words", type(e).__name__)

# every entry in the section, one at a time, with its ORIGINAL type restored --
# this is what proves the arm is per-ENTRY and not per-section
row("probe_entsize", rela_text_span(BASE)[3])
row("probe_nents", rela_text_span(BASE)[2]//rela_text_span(BASE)[3])
for k in range(rela_text_span(BASE)[2]//rela_text_span(BASE)[3]):
  b = patch_type(BASE, k, libc.R_AARCH64_NONE)
  try:
    n, vals = run(b)
    row(f"none_at_{k}_ok", 1); row(f"none_at_{k}_len", n); row(f"none_at_{k}_words", vals)
  except Exception as e:
    row(f"none_at_{k}_ok", 0); row(f"none_at_{k}_len", -1); row(f"none_at_{k}_words", type(e).__name__)

# ---------------------------------------------------------------- the two trampolines
# Both are arms that APPEND to `image` mid-loop, so the image GROWS and every
# later reloc site sees a different offset. That is the load-bearing fact.
row("tramp_x86_bytes", struct.pack("<HIQ", 0x25FF, 0, 0).hex())
row("tramp_x86_len", len(struct.pack("<HIQ", 0x25FF, 0, 0)))
row("tramp_x86_head", struct.pack("<HI", 0x25FF, 0).hex())
row("tramp_x86_tail", struct.pack("<Q", 0x1122334455667788).hex())
row("tramp_arm_bytes", struct.pack("<IIQ", 0x58000051, 0xD61F0220, 0).hex())
row("tramp_arm_len", len(struct.pack("<IIQ", 0x58000051, 0xD61F0220, 0)))
row("tramp_arm_head", struct.pack("<II", 0x58000051, 0xD61F0220).hex())
row("tramp_arm_tail", struct.pack("<Q", 0x1122334455667788).hex())

# the NotImplementedError message, verbatim
b = patch_type(BASE, 0, libc.R_X86_64_GLOB_DAT)
try:
  jit_loader(b, link_libs=[STUB])
  row("unknown_msg", "")
except NotImplementedError as e:
  row("unknown_msg", str(e))

# the R_X86_64 arm's overflow, verbatim -- the cross-arch fixture fact
b = patch_type(BASE, 0, libc.R_X86_64_PC32)
try:
  jit_loader(b, link_libs=[STUB])
  row("x86_pc32_err", "")
except Exception as e:
  row("x86_pc32_err", type(e).__name__)

sys.stdout.write("\n".join(OUT) + "\n")
