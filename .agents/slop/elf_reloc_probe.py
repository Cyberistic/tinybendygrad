#!/usr/bin/env python3
# elf_reloc_probe.py -- reaches elf.py:56-81 `relocate`, which is a CLOSURE over
# `image` and therefore unreachable from outside.
#
# HOW IT REACHES IT. `relocate` is only ever called by jit_loader:85, inside the
# per-relocation loop. So the arms are exercised THROUGH THE REAL jit_loader, on a
# REAL ELF64 object file, with TWO things substituted and NOTHING else: the
# relocation TYPE (`r_type`) and the relocation ADDEND (`r_addend`). Everything
# else -- the header walk, the section walk, the symtab, the image build, the
# 4-byte write-back at :85, the trampoline appends -- is upstream's own code on a
# clang/ld.lld-produced file.
#
# This is stated rather than hidden because it is the one place the fixture is
# CONSTRUCTED rather than compiled. The alternative -- transcribing `relocate` into
# the probe and comparing the probe to itself -- is the tautology the brief warns
# about, so the transcription is NOT used: the only thing the probe decides is
# WHICH `r_type` and WHICH `r_addend` the real code sees.
#
# TWO LANES PER ARM, AND WHY BOTH ARE NEEDED. On the unmodified fixture the
# `R_X86_64_PC32` and `R_X86_64_PLT32` arms produce the SAME four bytes: both take
# their in-range path, because `tgt - ploc` fits in a signed 32-bit word. So a
# `near` lane alone cannot tell the two x86 arms apart, and cannot reach EITHER
# trampoline. The `far` lane sets `r_addend` to 2**31, which pushes
# `tgt + r_addend` (elf.py:85 passes `tgt + r_addend`) past 2**31 and takes
# `R_X86_64_PLT32`'s and `R_AARCH64_CALL26`'s TRAMPOLINE arms. Measured: the
# `near` lane gives the same `words` for PC32 and PLT32, and the `far` lane gives
# different `words` AND a longer image, which is the append.
#
# The patched object is WRITTEN OUT next to the fixtures so the Bend port reads
# the SAME bytes and runs its own `jit_loader` on them. One 4-byte field changed
# per lane; the header walk and every other relocation entry are the compiler's.
#
#     python3 .agents/slop/elf_reloc_probe.py > .agents/slop/elf_reloc_probe.txt

import sys, os, struct, ctypes

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

def relocs_of(b):
  _, _, r = elf_loader(b, link_libs=[STUB])
  return r

BASE = open(SRC, "rb").read()
ORIG = relocs_of(BASE)
row("elf_rcp_src", os.path.basename(SRC))
row("elf_rcp_nreloc", len(ORIG))
row("elf_rcp_types", ",".join(str(x[2]) for x in ORIG))
row("elf_rcp_addrs", ",".join(str(x[0]) for x in ORIG))
row("elf_rcp_addends", ",".join(str(x[3]) for x in ORIG))

def rela_text_span(b):
  """The byte span of `.rela.text` inside the blob: index, offset, size, entsize."""
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

def patch_type(b, newtype, upto=None):
  """EVERY entry's r_type, preserving r_offset and r_sym. `r_info` is
  `sym<<32 | type`, so this is a mask-and-set on the low 32 bits.

  EVERY entry, not just the first: `.rela.text` on this fixture carries
  `R_AARCH64_ADR_GOT_PAGE` and `R_AARCH64_LD64_GOT_LO12_NC` as well as the ten
  arm types, and neither is in the `match`, so patching only entry 0 leaves a
  guaranteed `NotImplementedError` on entry 2 and no arm is ever measured."""
  i, off, sz, ent = rela_text_span(b)
  b = bytearray(b)
  for k in range(sz // ent if upto is None else upto + 1):
    p = off + k*ent + 8
    info = struct.unpack_from("<Q", b, p)[0]
    struct.pack_into("<Q", b, p, ((info >> 32) << 32) | (newtype & 0xffffffff))
  return bytes(b)

def patch_addend(b, newadd, upto=None):
  """EVERY entry's r_addend, the SIGNED 64-bit field at entry offset +16.
  elf.py:85 adds it to the target BEFORE the arm runs, so this is what decides
  whether a range test passes -- and it is the ONLY way to reach a trampoline
  arm on a fixture whose symbols are all in range."""
  i, off, sz, ent = rela_text_span(b)
  b = bytearray(b)
  for k in range(sz // ent if upto is None else upto + 1):
    struct.pack_into("<q", b, off + k*ent + 16, newadd)
  return bytes(b)

def run(b):
  """The real jit_loader, and the four bytes it wrote at each reloc site."""
  img = jit_loader(b, link_libs=[STUB])
  return len(img), ",".join(img[o:o+4].hex() for o, _, _, _ in relocs_of(b))

# elf.py:56-81, THE TEN ARMS. `R_AARCH64_NONE` is 0 and so is the `match` fall-
# through's accidental sibling; the two x86 names that are NOT arms are here as
# the REFUSAL rows.
ARMS = [
  ("R_X86_64_PC32",               libc.R_X86_64_PC32),
  ("R_X86_64_PLT32",              libc.R_X86_64_PLT32),
  ("R_AARCH64_ADR_PREL_PG_HI21",  libc.R_AARCH64_ADR_PREL_PG_HI21),
  ("R_AARCH64_ADD_ABS_LO12_NC",   libc.R_AARCH64_ADD_ABS_LO12_NC),
  ("R_AARCH64_LDST16_ABS_LO12_NC",libc.R_AARCH64_LDST16_ABS_LO12_NC),
  ("R_AARCH64_LDST32_ABS_LO12_NC",libc.R_AARCH64_LDST32_ABS_LO12_NC),
  ("R_AARCH64_LDST64_ABS_LO12_NC",libc.R_AARCH64_LDST64_ABS_LO12_NC),
  ("R_AARCH64_LDST128_ABS_LO12_NC", libc.R_AARCH64_LDST128_ABS_LO12_NC),
  ("R_AARCH64_CALL26",            libc.R_AARCH64_CALL26),
]
FAR = 1 << 31
for nm, ty in ARMS:
  row(f"elf_rc_{nm}", ty)
  for lane, add in (("near", 0), ("far", FAR)):
    b = patch_addend(patch_type(BASE, ty), add)
    fn = f"jt_{nm}_{lane}.o"
    open(os.path.join(FIX, fn), "wb").write(b)
    row(f"elf_rcp_{nm}_{lane}_file", fn)
    row(f"elf_rcp_{nm}_{lane}_addend", add)
    try:
      n, vals = run(b)
      row(f"elf_rcp_{nm}_{lane}_ok", 1)
      row(f"elf_rcp_{nm}_{lane}_len", n)
      row(f"elf_rcp_{nm}_{lane}_words", vals)
    except Exception as e:
      row(f"elf_rcp_{nm}_{lane}_ok", 0)
      row(f"elf_rcp_{nm}_{lane}_len", -1)
      row(f"elf_rcp_{nm}_{lane}_words", type(e).__name__)

# THE REFUSAL. `raise NotImplementedError(f"Encountered unknown relocation type
# {r_type}")` at elf.py:81, verbatim, on a type that is in none of the ten.
for nm, ty in (("R_X86_64_64", libc.R_X86_64_64),
               ("R_X86_64_GLOB_DAT", libc.R_X86_64_GLOB_DAT),
               ("R_AARCH64_NONE", libc.R_AARCH64_NONE)):
  row(f"elf_rc_no_{nm}", ty)
  b = patch_type(BASE, ty)
  try:
    jit_loader(b, link_libs=[STUB])
    row(f"elf_rc_no_{nm}_ok", 1); row(f"elf_rc_no_{nm}_msg", "")
  except NotImplementedError as e:
    row(f"elf_rc_no_{nm}_ok", 0); row(f"elf_rc_no_{nm}_msg", str(e))

# THE UNMODIFIED BASELINE, and the per-ENTRY proof: `relocate` is applied per
# relocation, not per section, so restoring entry `k`'s type leaves the others.
try:
  n, vals = run(BASE)
  row("elf_rc_base_ok", 1); row("elf_rc_base_len", n); row("elf_rc_base_words", vals)
except Exception as e:
  row("elf_rc_base_ok", 0); row("elf_rc_base_len", -1); row("elf_rc_base_words", type(e).__name__)
_, _, SZ, ENT = rela_text_span(BASE)
row("elf_rc_entsize", ENT)
row("elf_rc_nents", SZ // ENT)
for k in range(SZ // ENT):
  b = patch_type(BASE, libc.R_AARCH64_NONE, upto=k)
  row(f"elf_rc_entry_at_{k}_file", f"jt_none_at_{k}.o")
  open(os.path.join(FIX, f"jt_none_at_{k}.o"), "wb").write(b)
  try:
    n, vals = run(b)
    row(f"elf_rc_entry_at_{k}_ok", 1); row(f"elf_rc_entry_at_{k}_len", n)
    row(f"elf_rc_entry_at_{k}_words", vals)
  except Exception as e:
    row(f"elf_rc_entry_at_{k}_ok", 0); row(f"elf_rc_entry_at_{k}_len", -1)
    row(f"elf_rc_entry_at_{k}_words", type(e).__name__)

sys.stdout.write("\n".join(OUT) + "\n")
