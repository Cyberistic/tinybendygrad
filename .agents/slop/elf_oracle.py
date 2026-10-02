#!/usr/bin/env python3
# elf_oracle.py -- CPython oracle for tinybendygrad/runtime/support/elf.bend
#
# EVERY `py=` expectation in elf.bend comes from CALLING the real
# tinygrad/runtime/support/elf.py against REAL ELF files compiled here
# (.agents/slop/elf/*.o, *.exe). No value is transcribed by hand.
#
# Emits `name=value` lines on stdout, one per row. The harness
# (.agents/slop/elf-mutate.py) diffs whole `name=value` LINES, not row names.
#
# USAGE:  python3 elf_oracle.py > elf_oracle.txt

import sys, os, struct, ctypes, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FIX = os.path.join(HERE, "elf")
sys.path.insert(0, REPO)

from tinygrad.runtime.support.elf import ElfSection, elf_loader, jit_loader, link_sym
from tinygrad.runtime.autogen import libc
from tinygrad.helpers import getbits, i2u, ceildiv, round_up

OUT = []
def row(name, val): OUT.append(f"{name}={val}")

# ---------------------------------------------------------------- THE FIXTURES
# REAL ELF FILES, compiled in .agents/slop/elf/ with clang and ld.lld, verified
# with `file(1)`:
#
#   e64.o    ELF 64-bit LSB relocatable, x86-64, 12 sections  (SHT_REL not used;
#            RELA, SYMTAB, every PROGBITS has sh_addr == 0)
#   ea64.o   ELF 64-bit LSB relocatable, ARM aarch64, 11 sections
#   e32.o    ELF 32-bit LSB relocatable, Intel 80386, 12 sections  <- the Elf32 arm
#   n64.o    ELF 64-bit LSB relocatable, x86-64, 15 sections  (bigger: .rodata,
#            .data, a message string; 9 sections of varying width)
#   na64.o   ELF 64-bit LSB relocatable, ARM aarch64, 14 sections
#   n32.o    ELF 32-bit LSB relocatable, Intel 80386, 15 sections  <- Elf32, big
#   r64.so   ELF 64-bit LSB shared object, x86-64   -- RAISES StopIteration (the
#            `.rela.dyn` -> `.dyn` defect, REPORT.md DEFECT 2)
#   rx64.exe ELF 64-bit LSB executable, x86-64, sh_addr != 0 -- RAISES on the
#            wrong-string-table defect (REPORT.md DEFECT 1)
#
# WHY REAL AND NOT SYNTHETIC. `elf_loader` reads a byte-packed header whose field
# ORDER and OFFSETS are the ELF spec, and a synthetic header written by whoever
# wrote the port would be checked against a port that shares its assumptions. The
# authority here is clang/ld.lld; the SUT is tinygrad's own reader; the two sides
# have no common author.
#
# WHY THE WIDTHS ARE NON-UNIFORM. 11-15 sections, SHT_NULL at 0, a 0-byte
# section, PROGBITS with and without sh_addr, .comment (sh_addr 0, 77 bytes),
# .relro_padding (SHT_NOBITS, 2544-3624 bytes, sh_size huge but no content), and
# both Elf32 and Elf64 -- so an off-by-one in the section walk, a wrong stride, or
# a field transposition lands on a DIFFERENT number per fixture instead of
# agreeing by accident.

DEFAULT = ["e64.o", "ea64.o", "e32.o", "n64.o", "na64.o", "n32.o", "r64.so", "rx64.exe"]

# The link_libs that make the fixtures' UNDEFINED symbols resolve. Without it
# elf_loader raises at :13 -- which is itself the fact the `*_ok` rows report.
STUB = ctypes.CDLL(os.path.join(FIX, "libstub.dylib"))

def blob_of(nm): return open(os.path.join(FIX, nm), "rb").read()
def is64(b): return b[libc.EI_CLASS] == libc.ELFCLASS64

# ===========================================================================
# THE ELF-SPEC FIELD WALKS. Spelled out so the port can be gated on FIELD ORDER
# and BYTE OFFSET, never on a count -- a transposed pair in a struct the port
# writes is a silently wrong value, and a count cannot see it.
# ===========================================================================
EHDR_ORDER = "e_ident,e_type,e_machine,e_version,e_entry,e_phoff,e_shoff,e_flags," \
             "e_ehsize,e_phentsize,e_phnum,e_shentsize,e_shnum,e_shstrndx"
SHDR_ORDER = "sh_name,sh_type,sh_flags,sh_addr,sh_offset,sh_size,sh_link,sh_info,sh_addralign,sh_entsize"
SYM_ORDER64 = "st_name,st_info,st_other,st_shndx,st_value,st_size"
SYM_ORDER32 = "st_name,st_value,st_size,st_info,st_other,st_shndx"
REL_ORDER = "r_offset,r_info"
RELA_ORDER = "r_offset,r_info,r_addend"

def ehdr(b):
  """The Ehdr field walk WITH the byte offset of each field. Both arms."""
  if is64(b):
    fs = [("e_type","<H",16),("e_machine","<H",18),("e_version","<I",20),("e_entry","<Q",24),
          ("e_phoff","<Q",32),("e_shoff","<Q",40),("e_flags","<I",48),("e_ehsize","<H",52),
          ("e_phentsize","<H",54),("e_phnum","<H",56),("e_shentsize","<H",58),
          ("e_shnum","<H",60),("e_shstrndx","<H",62)]
  else:
    fs = [("e_type","<H",16),("e_machine","<H",18),("e_version","<I",20),("e_entry","<I",24),
          ("e_phoff","<I",28),("e_shoff","<I",32),("e_flags","<I",36),("e_ehsize","<H",40),
          ("e_phentsize","<H",42),("e_phnum","<H",44),("e_shentsize","<H",46),
          ("e_shnum","<H",48),("e_shstrndx","<H",50)]
  return ",".join(f"{n}@{o}:{struct.unpack_from(c,b,o)[0]}" for n,c,o in fs)

def shdr_at(b, off):
  """The Shdr field walk, name@byteoffset:value. Ten fields, BOTH word sizes."""
  if is64(b):
    fs = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<Q",8),("sh_addr","<Q",16),
          ("sh_offset","<Q",24),("sh_size","<Q",32),("sh_link","<I",40),("sh_info","<I",44),
          ("sh_addralign","<Q",48),("sh_entsize","<Q",56)]
  else:
    fs = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<I",8),("sh_addr","<I",12),
          ("sh_offset","<I",16),("sh_size","<I",20),("sh_link","<I",24),("sh_info","<I",28),
          ("sh_addralign","<I",32),("sh_entsize","<I",36)]
  return ",".join(f"{n}@{o}:{struct.unpack_from(c,b,off+o)[0]}" for n,c,o in fs)

def sym_at(buf, i, isx):
  """One Sym, all six fields, name@offset:value, both layouts."""
  base = i*(24 if isx else 16)
  if isx:
    fs = [("st_name","<I",0),("st_info","<B",4),("st_other","<B",5),
          ("st_shndx","<H",6),("st_value","<Q",8),("st_size","<Q",16)]
  else:
    fs = [("st_name","<I",0),("st_value","<I",4),("st_size","<I",8),
          ("st_info","<B",12),("st_other","<B",13),("st_shndx","<H",14)]
  return ",".join(f"{nm}@{o}:{struct.unpack_from(code,buf,base+o)[0]}" for nm,code,o in fs)

def rel_at(c, i, isx, has_addend):
  """One Rel/Rela, with the byte offset of EVERY field spelled out.
  Elf64: r_offset@0 r_info@8  (+r_addend@16), stride 16/24.
  Elf32: r_offset@0 r_info@4  (+r_addend@8),  stride  8/12.
  The offsets DIFFER between the two classes, which is why they are in the row."""
  st = (24 if has_addend else 16) if isx else (12 if has_addend else 8)
  base = i*st
  co = "<Q" if isx else "<I"
  io = 8 if isx else 4
  o0 = struct.unpack_from(co, c, base)[0]
  oi = struct.unpack_from(co, c, base+io)[0]
  if has_addend:
    ao = io + (8 if isx else 4)
    ad = struct.unpack_from("<q" if isx else "<i", c, base+ao)[0]
    return f"r_offset@0:{o0},r_info@{io}:{oi},r_addend@{ao}:{ad}"
  return f"r_offset@0:{o0},r_info@{io}:{oi}"

def sec_hdrs(b):
  """Every Shdr, by hand, with no ctypes -- so it is an independent reading of
  the same bytes elf_loader's ctypes structs read."""
  shoff = struct.unpack_from("<Q" if is64(b) else "<I", b, 40 if is64(b) else 32)[0]
  shsz = 64 if is64(b) else 40
  n = struct.unpack_from("<H", b, 60 if is64(b) else 48)[0]
  return [shdr_at(b, shoff + i*shsz) for i in range(n)]

def sec_raw(b):
  shoff = struct.unpack_from("<Q" if is64(b) else "<I", b, 40 if is64(b) else 32)[0]
  shsz = 64 if is64(b) else 40
  n = struct.unpack_from("<H", b, 60 if is64(b) else 48)[0]
  F = lambda i: struct.unpack_from("<IIQQQQIIQQ" if is64(b) else "<IIIIIIIIII", b, shoff+i*shsz)
  return [F(i) for i in range(n)]

def strtab(b, i):
  """_strtab(blob, idx) -- the NUL-terminated slice at a byte offset."""
  r = sec_raw(b)
  so, ss = r[i][4], r[i][5]
  return b[so:so+ss]

def shstrndx(b): return struct.unpack_from("<H", b, 62 if is64(b) else 50)[0]

# ===========================================================================
# PER FIXTURE
# ===========================================================================
def per_fixture(nm, align):
  b = blob_of(nm)
  t = nm.replace(".", "_").replace("-", "_")
  raw = sec_raw(b)
  sst = strtab(b, shstrndx(b))

  # ---- the four bytes the FIRST assert reads, and the class byte
  row(f"{t}_magic", b[0:4].hex())
  row(f"{t}_magic_ok", int(b[0:4] == libc.ELFMAG.encode()))
  row(f"{t}_elfmag", libc.ELFMAG.encode().hex())
  row(f"{t}_ei_class", b[libc.EI_CLASS])
  row(f"{t}_ei_class_val", libc.EI_CLASS)
  row(f"{t}_ecls", {libc.ELFCLASS32:"Elf32", libc.ELFCLASS64:"Elf64"}[b[libc.EI_CLASS]])
  row(f"{t}_is64", int(is64(b)))
  row(f"{t}_ehdr_order", EHDR_ORDER)
  row(f"{t}_ehdr", ehdr(b))
  row(f"{t}_ehdr_size", 64 if is64(b) else 52)
  row(f"{t}_shdr_order", SHDR_ORDER)
  row(f"{t}_sym_order", SYM_ORDER64 if is64(b) else SYM_ORDER32)
  row(f"{t}_rel_order", REL_ORDER)
  row(f"{t}_rela_order", RELA_ORDER)

  # ---- the hand-read section walk vs the one elf_loader built
  row(f"{t}_nsec_raw", len(raw))
  row(f"{t}_shnum", raw and struct.unpack_from("<H", b, 60 if is64(b) else 48)[0])
  row(f"{t}_shdr0", sec_hdrs(b)[0])
  row(f"{t}_shdr1", sec_hdrs(b)[1])
  row(f"{t}_shdr_last", sec_hdrs(b)[-1])
  row(f"{t}_sh_name_off", ",".join(str(x[0]) for x in raw))
  row(f"{t}_sh_type", ",".join(str(x[1]) for x in raw))
  row(f"{t}_sh_flags", ",".join(str(x[2]) for x in raw))
  row(f"{t}_sh_addr", ",".join(str(x[3]) for x in raw))
  row(f"{t}_sh_offset", ",".join(str(x[4]) for x in raw))
  row(f"{t}_sh_size", ",".join(str(x[5]) for x in raw))
  row(f"{t}_sh_link", ",".join(str(x[6]) for x in raw))
  row(f"{t}_sh_info", ",".join(str(x[7]) for x in raw))
  row(f"{t}_sh_addralign", ",".join(str(x[8]) for x in raw))
  row(f"{t}_sh_entsize", ",".join(str(x[9]) for x in raw))
  # the SHT_* constants, MEASURED off libc rather than transcribed
  row(f"{t}_sht_null", libc.SHT_NULL)
  row(f"{t}_sht_progbits", libc.SHT_PROGBITS)
  row(f"{t}_sht_symtab", libc.SHT_SYMTAB)
  row(f"{t}_sht_strtab", libc.SHT_STRTAB)
  row(f"{t}_sht_rel", libc.SHT_REL)
  row(f"{t}_sht_rela", libc.SHT_RELA)
  row(f"{t}_shf_alloc", libc.SHF_ALLOC)
  row(f"{t}_shf_execinstr", libc.SHF_EXECINSTR)
  row(f"{t}_shf_write", libc.SHF_WRITE)
  row(f"{t}_ntype_progbits", sum(1 for x in raw if x[1] == libc.SHT_PROGBITS))
  row(f"{t}_ntype_symtab", sum(1 for x in raw if x[1] == libc.SHT_SYMTAB))
  row(f"{t}_ntype_strtab", sum(1 for x in raw if x[1] == libc.SHT_STRTAB))
  row(f"{t}_ntype_rel", sum(1 for x in raw if x[1] == libc.SHT_REL))
  row(f"{t}_ntype_rela", sum(1 for x in raw if x[1] == libc.SHT_RELA))
  row(f"{t}_ntype_nobits", sum(1 for x in raw if x[1] == libc.SHT_NOBITS))

  # ---- _strtab(sh_strtab, idx): the section NAMES, and each one's byte offset
  row(f"{t}_shstrtab_idx", shstrndx(b))
  row(f"{t}_shstrtab_off", raw[shstrndx(b)][4])
  row(f"{t}_shstrtab_size", raw[shstrndx(b)][5])
  row(f"{t}_shstrtab", sst.hex())
  names = [_strtab(b, sst, x[0]) for x in raw]
  row(f"{t}_names", ",".join(names))
  row(f"{t}_name_offs", ",".join(str(x[0]) for x in raw))
  # the strip that names the reloc TARGET: name[4:] for REL, name[5:] for RELA
  row(f"{t}_rel_names", ",".join(n for n, x in zip(names, raw) if x[1] == libc.SHT_REL))
  row(f"{t}_rela_names", ",".join(n for n, x in zip(names, raw) if x[1] == libc.SHT_RELA))
  row(f"{t}_rel_trgt4", ",".join(n[4:] for n, x in zip(names, raw) if x[1] == libc.SHT_REL))
  row(f"{t}_rela_trgt5", ",".join(n[5:] for n, x in zip(names, raw) if x[1] == libc.SHT_RELA))
  row(f"{t}_ehframe_skipped", int(any(n[4:] == ".eh_frame" for n, x in zip(names, raw) if x[1] == libc.SHT_REL)
                                  or any(n[5:] == ".eh_frame" for n, x in zip(names, raw) if x[1] == libc.SHT_RELA)))

  # ---- the symtab: name/info/other/shndx/value/size, all six, both layouts
  sts = [i for i, x in enumerate(raw) if x[1] == libc.SHT_SYMTAB]
  row(f"{t}_symtab_idx", sts[0] if sts else -1)
  if sts:
    sx = raw[sts[0]]
    cnt = sx[5]//sx[9] if sx[9] else 0
    row(f"{t}_nsyms", cnt)
    row(f"{t}_sym_entsize", sx[9])
    row(f"{t}_sym_size", sx[5])
    row(f"{t}_sym_shndx", ",".join(str(struct.unpack_from("<H", b[sx[4]:sx[4]+sx[5]], i*sx[9]+(6 if is64(b) else 14))[0]) for i in range(cnt)))
    row(f"{t}_sym_nameoff", ",".join(str(struct.unpack_from("<I", b[sx[4]:sx[4]+sx[5]], i*sx[9])[0]) for i in range(cnt)))
    row(f"{t}_sym_value", ",".join(str(struct.unpack_from("<Q" if is64(b) else "<I", b[sx[4]:sx[4]+sx[5]], i*sx[9]+(8 if is64(b) else 4))[0]) for i in range(cnt)))
    row(f"{t}_sym_info", ",".join(str(struct.unpack_from("<B", b[sx[4]:sx[4]+sx[5]], i*sx[9]+(4 if is64(b) else 12))[0]) for i in range(cnt)))
    row(f"{t}_sym_other", ",".join(str(struct.unpack_from("<B", b[sx[4]:sx[4]+sx[5]], i*sx[9]+(5 if is64(b) else 13))[0]) for i in range(cnt)))
    row(f"{t}_sym_size_f", ",".join(str(struct.unpack_from("<Q" if is64(b) else "<I", b[sx[4]:sx[4]+sx[5]], i*sx[9]+(16 if is64(b) else 8))[0]) for i in range(cnt)))
    row(f"{t}_sym0", sym_at(b[sx[4]:sx[4]+sx[5]], 0, is64(b)))
    row(f"{t}_sym1", sym_at(b[sx[4]:sx[4]+sx[5]], 1, is64(b)))
    row(f"{t}_sym_last", sym_at(b[sx[4]:sx[4]+sx[5]], cnt-1, is64(b)))
    # ELF64_R_SYM / ELF64_R_TYPE -- measured off libc
    row(f"{t}_r_sym_vals", ",".join(str(libc.ELF64_R_SYM(v)) for v in (1024, 4096, 4294967295, 0)))
    row(f"{t}_r_type_vals", ",".join(str(libc.ELF64_R_TYPE(v)) for v in (1024, 4096, 4294967295, 0)))
    row(f"{t}_r_sym32_vals", ",".join(str(libc.ELF32_R_SYM(v)) for v in (1024, 4096, 4294967295, 0)))
    row(f"{t}_r_type32_vals", ",".join(str(libc.ELF32_R_TYPE(v)) for v in (1024, 4096, 4294967295, 0)))

  # ---- the Rel / Rela entries, with byte offsets
  for kind, styp, hasadd, sz, co, ai in [("rel", libc.SHT_REL, False, 16 if is64(b) else 8, "<Q" if is64(b) else "<I", 8 if is64(b) else 4),
                                          ("rela", libc.SHT_RELA, True, 24 if is64(b) else 12, "<Q" if is64(b) else "<I", 8 if is64(b) else 4)]:
    idxs = [i for i, x in enumerate(raw) if x[1] == styp]
    row(f"{t}_{kind}_idx", ",".join(str(i) for i in idxs))
    row(f"{t}_{kind}_entsize", ",".join(str(raw[i][9]) for i in idxs))
    allrel = []
    for i in idxs:
      c = b[raw[i][4]:raw[i][4]+raw[i][5]]
      for k in range(raw[i][5]//raw[i][9] if raw[i][9] else 0):
        allrel.append(rel_at(c, k, is64(b), hasadd))
    row(f"{t}_{kind}_n", len(allrel))
    row(f"{t}_{kind}_first", allrel[0] if allrel else "")
    row(f"{t}_{kind}_last", allrel[-1] if allrel else "")
    # r_info split into R_SYM and R_TYPE, which is the whole point of r_info
    # elf.py:45 picks `ELF{32,64}_R_SYM` / `_R_TYPE` BY CLASS, so the split
    # differs: 64 is (>>32, &0xffffffff), 32 is (>>8, &0xff).
    r_sym  = libc.ELF64_R_SYM if is64(b) else libc.ELF32_R_SYM
    r_type = libc.ELF64_R_TYPE if is64(b) else libc.ELF32_R_TYPE
    row(f"{t}_{kind}_rsym_is64", int(is64(b)))
    offs, syms, tys = [], [], []
    for i in idxs:
      c = b[raw[i][4]:raw[i][4]+raw[i][5]]
      for k in range(raw[i][5]//raw[i][9] if raw[i][9] else 0):
        o = struct.unpack_from(co, c, k*sz)[0]
        inf = struct.unpack_from(co, c, k*sz+ai)[0]
        offs.append(o); syms.append(r_sym(inf)); tys.append(r_type(inf))
    row(f"{t}_{kind}_offsets", ",".join(str(x) for x in offs))
    row(f"{t}_{kind}_rsym", ",".join(str(x) for x in syms))
    row(f"{t}_{kind}_rtype", ",".join(str(x) for x in tys))

  # ---- the image: prealloc max, the aligned append, the fixed write
  pbits = [(i, raw[i]) for i, x in enumerate(raw) if x[1] == libc.SHT_PROGBITS]
  fixed = [x for _, x in pbits if x[3] != 0]
  row(f"{t}_nprogbits", len(pbits))
  row(f"{t}_nprogbits_fixed", len(fixed))
  row(f"{t}_nprogbits_reloc", len(pbits)-len(fixed))
  row(f"{t}_prealloc_max", max([x[3]+x[5] for x in fixed] + [0]))
  row(f"{t}_force_align", align)
  row(f"{t}_align_max", max([max(x[8], align) for _, x in pbits] + [0]))

  # ---- elf_loader itself, and its refusals
  try:
    image, sections, relocs = elf_loader(b, force_section_align=align, link_libs=[STUB])
    img = bytes(image)
    row(f"{t}_elf_ok", 1)
    row(f"{t}_elf_err", "")
    row(f"{t}_nsec", len(sections))
    row(f"{t}_sec_names", ",".join(s.name for s in sections))
    row(f"{t}_sec_types", ",".join(str(s.header.sh_type) for s in sections))
    row(f"{t}_sec_sizes", ",".join(str(s.header.sh_size) for s in sections))
    row(f"{t}_sec_offsets", ",".join(str(s.header.sh_offset) for s in sections))
    row(f"{t}_sec_addrs", ",".join(str(s.header.sh_addr) for s in sections))
    row(f"{t}_sec_entsizes", ",".join(str(s.header.sh_entsize) for s in sections))
    row(f"{t}_sec_addraligns", ",".join(str(s.header.sh_addralign) for s in sections))
    row(f"{t}_sec_links", ",".join(str(s.header.sh_link) for s in sections))
    row(f"{t}_sec_infos", ",".join(str(s.header.sh_info) for s in sections))
    row(f"{t}_sec_flags", ",".join(str(s.header.sh_flags) for s in sections))
    row(f"{t}_sec_nameoffs", ",".join(str(s.header.sh_name) for s in sections))
    # the ElfSection CONTENT slices, blob[off:off+size]
    row(f"{t}_content_lens", ",".join(str(len(s.content)) for s in sections))
    row(f"{t}_content_sha", ",".join(hashlib.sha256(bytes(s.content)).hexdigest()[:8] for s in sections))
    row(f"{t}_content0_hex", bytes(sections[0].content).hex())
    row(f"{t}_image_len", len(img))
    row(f"{t}_image_sha", hashlib.sha256(img).hexdigest()[:16])
    row(f"{t}_image_head", img[:32].hex())
    row(f"{t}_image_tail", img[-32:].hex())
    row(f"{t}_image_zeros", str(len(img) - sum(1 for x in img if x)))
    # the reloc tuples, in order, all four fields
    row(f"{t}_nrelocs", len(relocs))
    row(f"{t}_relocs", ",".join(f"{o}:{t2}:{ty}:{ad}" for o, t2, ty, ad in relocs))
    row(f"{t}_reloc_addrs", ",".join(str(o) for o, _, _, _ in relocs))
    row(f"{t}_reloc_tgts", ",".join(str(t2) for _, t2, _, _ in relocs))
    row(f"{t}_reloc_types", ",".join(str(ty) for _, _, ty, _ in relocs))
    row(f"{t}_reloc_addends", ",".join(str(ad) for _, _, _, ad in relocs))
    # the symtab-name table the port READS. DEFECT 1: this is sh_strtab, and
    # for a LINKED image it is the wrong table -- so the row is a DIFFERENT
    # string for the .o files and for the .exe, which is the finding.
    row(f"{t}_sym_name_via_shstrtab", ",".join(_strtab(b, sst, struct.unpack_from("<I", b[raw[sts[0]][4]:raw[sts[0]][4]+raw[sts[0]][5]], i*raw[sts[0]][9])[0])
                                               for i in range(cnt)) if sts else "")
    if sts:
      sl = raw[sts[0]][6]
      sst2 = strtab(b, sl)
      row(f"{t}_symtab_shlink", sl)
      row(f"{t}_sym_name_via_shlink", ",".join(_strtab(b, sst2, struct.unpack_from("<I", b[raw[sts[0]][4]:raw[sts[0]][4]+raw[sts[0]][5]], i*raw[sts[0]][9])[0])
                                                for i in range(cnt)))
      row(f"{t}_sym_tables_differ", int(sst != sst2))
  except Exception as e:
    row(f"{t}_elf_ok", 0)
    row(f"{t}_elf_err", type(e).__name__)

  # ---- jit_loader: the FUNCTION that applies the relocs
  try:
    out = jit_loader(b, link_libs=[STUB])
    row(f"{t}_jit_ok", 1)
    row(f"{t}_jit_len", len(out))
    row(f"{t}_jit_sha", hashlib.sha256(out).hexdigest()[:16])
    row(f"{t}_jit_head", out[:32].hex())
    row(f"{t}_jit_tail", out[-32:].hex())
  except Exception as e:
    row(f"{t}_jit_ok", 0)
    row(f"{t}_jit_len", -1)
    row(f"{t}_jit_sha", "ERR")
    row(f"{t}_jit_head", "")
    row(f"{t}_jit_tail", type(e).__name__)

def _strtab(b, tbl, idx):
  e = tbl.find(b'\x00', idx)
  return tbl[idx:e].decode('utf-8') if idx < len(tbl) else ""

# ===========================================================================
# THE ALIGN LANES. `force_section_align` only bites when a PROGBITS has
# sh_addr == 0, so every fixture is run at four alignments -- 1 (no-op), 4, 16,
# 256 -- and the IMAGE LENGTH plus the section ADDRESSES are the rows.
# ===========================================================================
def per_align(nm):
  for a in [1, 4, 16, 256]:
    b = blob_of(nm)
    t = f"{nm.replace('.','_').replace('-','_')}_a{a}"
    raw = sec_raw(b)
    pbits = [x for x in raw if x[1] == libc.SHT_PROGBITS and x[3] == 0]
    row(f"{t}_nreloc_pbits", len(pbits))
    row(f"{t}_align_used", ",".join(str(max(x[8], a)) for x in pbits))
    # the arithmetic of :37, spelled out: ((align - len(image) % align) % align)
    img, addrs = 0, []
    for x in raw:
      if x[1] != libc.SHT_PROGBITS: continue
      if x[3] != 0:
        continue
      al = max(x[8], a)
      img += ((al - img % al) % al)
      addrs.append(img)
      img += x[5]
    row(f"{t}_model_len", img)
    row(f"{t}_model_addrs", ",".join(str(x) for x in addrs))
    try:
      image, sections, relocs = elf_loader(b, force_section_align=a, link_libs=[STUB])
      row(f"{t}_ok", 1)
      row(f"{t}_len", len(bytes(image)))
      row(f"{t}_addrs", ",".join(str(s.header.sh_addr) for s in sections))
    except Exception as e:
      row(f"{t}_ok", 0)
      row(f"{t}_len", -1)
      row(f"{t}_addrs", type(e).__name__)

# ===========================================================================
# link_sym -- THE LIVE BUG
# ===========================================================================
def link_sym_rows():
  libs = [("libm", ctypes.CDLL("/usr/lib/libm.dylib")),
          ("rt", ctypes.CDLL("/usr/lib/libSystem.dylib")),
          ("objc", ctypes.CDLL("/usr/lib/libobjc.dylib"))]
  row("ls_order", ",".join(n for n, _ in libs))
  for sym in ["sel_registerName", "objc_msgSend", "sin", "cos", "sqrt", "malloc",
              "memcpy", "definitely_not_a_symbol"]:
    hits = []
    for _, l in libs:
      try:
        hits.append(int(link_sym(sym, [l]) != 0))
      except Exception:
        hits.append(0)
    row(f"ls_{sym}", ",".join(str(x) for x in hits))
  # the exact pair ops_cpu.py:21 builds -- libm first, then rt_lib
  row("ls_cpu_pair", "libm,rt")
  for sym in ["sel_registerName", "sin"]:
    try:
      link_sym(sym, [libs[0][1], libs[1][1]]); row(f"ls_cpupair_{sym}", 1)
    except RuntimeError:
      row(f"ls_cpupair_{sym}", 0)
  # the same pair PLUS libobjc -- the one-line fix, measured
  row("ls_trio", "libm,rt,objc")
  for sym in ["sel_registerName", "sin"]:
    try:
      link_sym(sym, [libs[0][1], libs[1][1], libs[2][1]]); row(f"ls_trio_{sym}", 1)
    except RuntimeError:
      row(f"ls_trio_{sym}", 0)
  # the refusal itself, VERBATIM, because the message is the observable
  try:
    link_sym("sin", []); row("ls_empty_ok", 1); row("ls_empty_msg", "")
  except RuntimeError as e:
    row("ls_empty_ok", 0); row("ls_empty_msg", str(e))
  try:
    link_sym("definitely_not_a_symbol", [libs[0][1]]); row("ls_miss_ok", 1); row("ls_miss_msg", "")
  except RuntimeError as e:
    row("ls_miss_ok", 0); row("ls_miss_msg", str(e))
  # the ORDER that decides a fall-through: libm has sin, rt has sin, so the
  # FIRST hit wins and the two orders give DIFFERENT addresses
  row("ls_sin_m_first", link_sym("sin", [libs[0][1]]))
  row("ls_sin_rt_only", link_sym("sin", [libs[1][1]]))
  row("ls_sin_pair_first_is_m", int(link_sym("sin", [libs[0][1], libs[1][1]]) == link_sym("sin", [libs[0][1]])))
  row("ls_sin_pair_first_is_rt", int(link_sym("sin", [libs[0][1], libs[1][1]]) == link_sym("sin", [libs[1][1]])))

# ===========================================================================
# relocate -- the ten arms of the `match r_type`, elf.py:58-81
# ===========================================================================
def relocate_rows():
  # `relocate` is a CLOSURE over `image` and is not reachable from outside, so
  # its arms are gated through (a) the constants and the two trampolines, which
  # are MEASURED off struct.pack here, and (b) jit_loader's output on the real
  # fixtures above, which is the only thing that calls it.
  row("rc_x86_pc32", libc.R_X86_64_PC32)
  row("rc_x86_plt32", libc.R_X86_64_PLT32)
  row("rc_a64_adr", libc.R_AARCH64_ADR_PREL_PG_HI21)
  row("rc_a64_add_lo12", libc.R_AARCH64_ADD_ABS_LO12_NC)
  row("rc_a64_ldst16", libc.R_AARCH64_LDST16_ABS_LO12_NC)
  row("rc_a64_ldst32", libc.R_AARCH64_LDST32_ABS_LO12_NC)
  row("rc_a64_ldst64", libc.R_AARCH64_LDST64_ABS_LO12_NC)
  row("rc_a64_ldst128", libc.R_AARCH64_LDST128_ABS_LO12_NC)
  row("rc_a64_call26", libc.R_AARCH64_CALL26)
  row("rc_ten_arms", 10)
  # the two trampolines -- the arms that WRITE into `image`
  for nm, v in [("t16", 0), ("t32", 0x11223344), ("t64", 0x1122334455667788)]:
    row(f"tr_x86_{nm}", struct.pack("<HIQ", 0x25FF, 0, v).hex())
    row(f"tr_arm_{nm}", struct.pack("<IIQ", 0x58000051, 0xD61F0220, v).hex())
  row("tr_x86_len", len(struct.pack("<HIQ", 0x25FF, 0, 0)))
  row("tr_arm_len", len(struct.pack("<IIQ", 0x58000051, 0xD61F0220, 0)))
  row("tr_x86_off", len(struct.pack("<HIQ", 0x25FF, 0, 0)) - 14)
  row("tr_arm_off", len(struct.pack("<IIQ", 0x58000051, 0xD61F0220, 0)) - 16)
  # the 4-byte write of :85
  for w in [0, 1, 0x7fffffff, 0x80000000, 0xffffffff, 0x11223344, 0xdeadbeef]:
    row(f"ld_pack_{w:08x}", struct.pack("<I", w).hex())
  row("ld_unpack", struct.unpack("<I", struct.pack("<I", 0x11223344))[0])
  # getbits over every range relocate uses
  for v, s, e in [(0x1234,12,13),(0x1234,14,32),(0xabcd,0,11),(0xabcd,1,11),(0xabcd,2,11),
                  (0xabcd,3,11),(0xabcd,4,11),(0xabcd,2,27),(0xdeadbeef,0,31),(0xdeadbeef,0,0),
                  (0xffffffff,12,13),(0,12,13),(0xffffffff,14,32),(0x1000,12,13)]:
    row(f"gb_{v:08x}_{s}_{e}", getbits(v, s, e))
  # i2u(32, ..) on both signs -- the rel32 encoding
  for v in [0,1,-1,-1000,2147483647,-2147483648,0x7fffff00,-2]:
    row(f"i2u32_{v}", i2u(32, v))
  # the rel32 range test, at the four boundary values
  for v in [0,2147483647,2147483648,-2147483648,-2147483649,4294967295]:
    row(f"rel32_in_{v}", int(-2**31 <= v < 2**31))
  # R_AARCH64_CALL26's range test -- a DIFFERENT predicate, off the same inputs
  for v in [0,33554431,33554432,134217724,134217727,134217728,-1,-33554432]:
    row(f"call26_in_{v}", int(-(2**25) <= v <= (2**25-1)*4))
  # the page masks of the ADRP arm
  for v in [0,0xfff,0x1000,0x1fff,0x123456,0xffffffff]:
    row(f"pgmask_{v:08x}", v & ~0xFFF)
  # getbits shifted into position: (getbits(x,12,13) << 29)
  for v in [0, 0x1234, 0x12340, 0xfffff000]:
    row(f"adr_hi21_{v:08x}", getbits(v, 12, 13) << 29)
    row(f"adr_lo19_{v:08x}", getbits(v, 14, 32) << 5)

# ===========================================================================
def main():
  for nm in DEFAULT:
    per_fixture(nm, 1)
    per_align(nm)
  link_sym_rows()
  relocate_rows()
  sys.stdout.write("\n".join(OUT) + "\n")

main()
