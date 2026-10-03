#!/usr/bin/env python3
# elf_rows.py -- the CPython side of the gate, emitting EXACTLY the row names
# tinybendygrad/runtime/support/elf.bend prints.
#
# Every value is CALLed out of tinygrad's own `runtime/support/elf.py` on one of
# the nine real ELF fixtures, or MEASURED out of `runtime/autogen/libc.py`. None
# is transcribed. The per-fixture tags are `elf_sec_e64` / `elf_str_e64` and so
# on, matching the Bend side.
#
#     python3 .agents/slop/elf_rows.py > .agents/slop/elf_rows.txt
#
# THE EXIT PATH IS PART OF THE CONTRACT: this script writes every row it can and
# then exits 0, and it refuses to exit 0 having written nothing. An oracle that
# emits 0 rows and exits 1 while the gate prints hundreds of green rows is not a
# passing gate; `exit_guard()` below is what makes that impossible to miss.

import sys, os, struct, ctypes, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, REPO)
FIX = os.path.join(HERE, "elf")

from tinygrad.runtime.support.elf import ElfSection, elf_loader, jit_loader, link_sym
from tinygrad.runtime.autogen import libc
from tinygrad.helpers import getbits, i2u, ceildiv, round_up

OUT = []
def row(n, v): OUT.append(f"{n}={v}")
def prow(n, v): row(n, str(v))

STUB = ctypes.CDLL(os.path.join(FIX, "libstub.dylib"))

FIXTURES = [("e64.o","e64"),("ea64.o","ea64"),("e32.o","e32"),("n64.o","n64"),
            ("na64.o","na64"),("n32.o","n32"),("j_aarch64.o","ja64")]
REFUSERS = [("r64.so","r64so"),("rx64.exe","rx64exe")]
ALL = FIXTURES + REFUSERS

def blob(nm): return open(os.path.join(FIX, nm), "rb").read()
def is64(b): return b[libc.EI_CLASS] == libc.ELFCLASS64

def ehdr(b):
  if is64(b):
    F = [("e_type","<H",16),("e_machine","<H",18),("e_version","<I",20),("e_entry","<Q",24),
         ("e_phoff","<Q",32),("e_shoff","<Q",40),("e_flags","<I",48),("e_ehsize","<H",52),
         ("e_phentsize","<H",54),("e_phnum","<H",56),("e_shentsize","<H",58),
         ("e_shnum","<H",60),("e_shstrndx","<H",62)]
  else:
    F = [("e_type","<H",16),("e_machine","<H",18),("e_version","<I",20),("e_entry","<I",24),
         ("e_phoff","<I",28),("e_shoff","<I",32),("e_flags","<I",36),("e_ehsize","<H",40),
         ("e_phentsize","<H",42),("e_phnum","<H",44),("e_shentsize","<H",46),
         ("e_shnum","<H",48),("e_shstrndx","<H",50)]
  return ",".join(f"{n}@{o}:{struct.unpack_from(c,b,o)[0]}" for n,c,o in F)

def shdrs(b):
  shoff = struct.unpack_from("<Q" if is64(b) else "<I", b, 40 if is64(b) else 32)[0]
  sz = 64 if is64(b) else 40
  n = struct.unpack_from("<H", b, 60 if is64(b) else 48)[0]
  return [struct.unpack_from("<IIQQQQIIQQ" if is64(b) else "<IIIIIIIIII", b, shoff+i*sz)
          for i in range(n)]

# The ten Shdr fields at their register offsets, in the reader's order, printed
# as `name@byteoffset:value`. THE VALUES COME FROM THE SECTION TABLE AT
# `shoff + i*stride` -- NOT from offset 0 of the blob, which is what the first
# version of this function did and which is why every `*_hdrtxt` row read the ELF
# MAGIC back. Both classes are printed at their OWN offsets, so the row also gates
# the Elf32 offset table (which is 4 lower for every 64-bit field).
def shtxt(b, at, i):
  if is64(b):
    F = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<Q",8),("sh_addr","<Q",16),
         ("sh_offset","<Q",24),("sh_size","<Q",32),("sh_link","<I",40),("sh_info","<I",44),
         ("sh_addralign","<Q",48),("sh_entsize","<Q",56)]
  else:
    F = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<I",8),("sh_addr","<I",12),
         ("sh_offset","<I",16),("sh_size","<I",20),("sh_link","<I",24),("sh_info","<I",28),
         ("sh_addralign","<I",32),("sh_entsize","<I",36)]
  # A 64-bit field is printed `hi:lo` -- BOTH halves, always, so a port that
  # swapped them disagrees. A 32-bit field is a bare value. This is the same
  # `W64.text` shape the port uses, and it is why `elf_sec_*_hdrtxt` is a STRING
  # and not a count: a transposed pair and a swapped half are both invisible to
  # anything that compares magnitudes.
  def cell(n, c, o):
    v = struct.unpack_from(c, b, at+o)[0]
    return f"{n}@{o}:{v>>32}:{v & 0xffffffff}" if c == "<Q" else f"{n}@{o}:{v}"
  return ",".join(cell(n, c, o) for n, c, o in F)

def sstrtab(b):
  r = shdrs(b)
  i = struct.unpack_from("<H", b, 62 if is64(b) else 50)[0]
  return b[r[i][4]:r[i][4]+r[i][5]]

def strtab_at(tbl, i):
  return tbl[i:tbl.find(b"\x00", i)].decode("utf-8") if i < len(tbl) else ""

def w64(v): return f"{v>>32}:{v & 0xffffffff}"

def g_glob():
  row("elf_F_EHDR", "e_ident,e_type,e_machine,e_version,e_entry,e_phoff,e_shoff,e_flags,"
                     "e_ehsize,e_phentsize,e_phnum,e_shentsize,e_shnum,e_shstrndx")
  row("elf_F_SHDR", "sh_name,sh_type,sh_flags,sh_addr,sh_offset,sh_size,sh_link,sh_info,"
                     "sh_addralign,sh_entsize")
  row("elf_F_SYM64", "st_name,st_info,st_other,st_shndx,st_value,st_size")
  row("elf_F_SYM32", "st_name,st_value,st_size,st_info,st_other,st_shndx")
  row("elf_F_RELA", "r_offset,r_info,r_addend")
  row("elf_F_REL", "r_offset,r_info")
  for n, v in [("elf_c_ELFMAG", int.from_bytes(libc.ELFMAG.encode(), "big")),
               ("elf_c_EI_CLASS", libc.EI_CLASS), ("elf_c_ELFCLASS32", libc.ELFCLASS32),
               ("elf_c_ELFCLASS64", libc.ELFCLASS64), ("elf_c_SHT_NULL", libc.SHT_NULL),
               ("elf_c_SHT_PROGBITS", libc.SHT_PROGBITS), ("elf_c_SHT_SYMTAB", libc.SHT_SYMTAB),
               ("elf_c_SHT_STRTAB", libc.SHT_STRTAB), ("elf_c_SHT_RELA", libc.SHT_RELA),
               ("elf_c_SHT_NOBITS", libc.SHT_NOBITS), ("elf_c_SHT_REL", libc.SHT_REL),
               ("elf_c_SHF_WRITE", libc.SHF_WRITE), ("elf_c_SHF_ALLOC", libc.SHF_ALLOC),
               ("elf_c_SHF_EXECINSTR", libc.SHF_EXECINSTR)]:
    prow(n, v)
  b = blob("e64.o")
  for n, v in [("elf_blk_hexlen", len(b.hex())), ("elf_blk_bytes", len(b)),
               ("elf_blk_u8_0", b[0]), ("elf_blk_u8_1", b[1]), ("elf_blk_u8_3", b[3]),
               ("elf_blk_u8_4", b[4]),
               ("elf_blk_le16_16", struct.unpack_from("<H", b, 16)[0]),
               ("elf_blk_le16_18", struct.unpack_from("<H", b, 18)[0]),
               ("elf_blk_le32_20", struct.unpack_from("<I", b, 20)[0]),
               ("elf_blk_le32_40", struct.unpack_from("<I", b, 40)[0]),
               ("elf_blk_le32_44", struct.unpack_from("<I", b, 44)[0]),
               ("elf_blk_le32_56", struct.unpack_from("<I", b, 56)[0]),
               ("elf_blk_le32_60", struct.unpack_from("<I", b, 60)[0])]:
    prow(n, v)
  row("elf_blk_magic_hex", b[0:4].hex())
  row("elf_blk_slice_0_4", b[0:4].hex())
  row("elf_blk_slice_4_4", b[4:8].hex())
  row("elf_blk_slice_896_16", b[896:912].hex())
  # The port's `Hex.val` is TOTAL: a NON-hex character answers 15, which is the
  # last digit rather than a crash. `'z'` is the probe for that -- it is what a
  # truncated or corrupted blob produces, and a port that answered 0 there would
  # silently read a NUL.
  for c, n in [("0","elf_hexval_0"),("9","elf_hexval_9"),("a","elf_hexval_a"),
               ("f","elf_hexval_f"),("A","elf_hexval_A"),("F","elf_hexval_F"),
               ("z","elf_hexval_z"),("g","elf_hexval_g"),("/","elf_hexval_slash")]:
    prow(n, int(c, 16) if c in "0123456789abcdefABCDEF" else 15)
  row("elf_hexdig", "0123456789abcdef")
  for n, v in [("elf_hexof_deadbeef", 0xdeadbeef), ("elf_hexof_0", 0),
               ("elf_hexof_ffffffff", 0xffffffff)]:
    row(n, f"{v:08x}")
  row("elf_hexpair_1234", f"{0x1234 & 0xff:02x}{0x1234 >> 8:02x}")
  row("elf_hexu8_ff", "ff")
  row("elf_hexu8_00", "00")
  for fn, tag in ALL:
    b = blob(fn)
    prow(f"elf_magic_{tag}", int(b[0:4] == libc.ELFMAG.encode()))
    prow(f"elf_ei_class_{tag}", b[libc.EI_CLASS])
    row(f"elf_ecls_{tag}", "Elf64" if is64(b) else "Elf32")
    prow(f"elf_is64_{tag}", 1 if is64(b) else 0)
  for n, v in [("elf_ehdr_size64", libc.Elf64_Ehdr.SIZE), ("elf_ehdr_size32", libc.Elf32_Ehdr.SIZE),
               ("elf_shdr_size64", libc.Elf64_Shdr.SIZE), ("elf_shdr_size32", libc.Elf32_Shdr.SIZE),
               ("elf_sym_size64", libc.Elf64_Sym.SIZE), ("elf_sym_size32", libc.Elf32_Sym.SIZE),
               ("elf_eident_size", 16)]:
    prow(n, v)

# THE PORT'S `Ehdr.text` SPELLS THE Elf64 REGISTER TABLE -- that is deliberate: the
# row is about the TABLE (its names, its order, its offsets), and the per-class
# VALUES are gated by the separate `*_ehsize` / `*_shoff` / `*_shnum` rows, which
# read through `Ehdr.e_*` and therefore through the class. So the oracle reads the
# SAME Elf64 offsets for both classes.
FHDR64 = [("e_type","<H",16),("e_machine","<H",18),("e_version","<I",20),("e_entry","<Q",24),
          ("e_phoff","<Q",32),("e_shoff","<Q",40),("e_flags","<I",48),("e_ehsize","<H",52),
          ("e_phentsize","<H",54),("e_phnum","<H",56),("e_shentsize","<H",58),
          ("e_shnum","<H",60),("e_shstrndx","<H",62)]

def Ehdr_label(n, o, v, c):
  # `hi:lo` for a 64-bit field and a bare value for a 32-bit one. Both halves
  # always, so a port that swapped them disagrees.
  if c == "<Q":
    return f"{n}@{o}:{v>>32}:{v & 0xffffffff}"
  return f"{n}@{o}:{v}"

def Sec_hdr(tag, b):
  x = libc.Elf64_Ehdr.from_buffer_copy(b) if is64(b) else libc.Elf32_Ehdr.from_buffer_copy(b)
  prow(f"elf_hdr_{tag}_ehsize", libc.Elf64_Ehdr.SIZE if is64(b) else libc.Elf32_Ehdr.SIZE)
  prow(f"elf_hdr_{tag}_shoff", w64(x.e_shoff))
  prow(f"elf_hdr_{tag}_phoff", w64(x.e_phoff))
  prow(f"elf_hdr_{tag}_entry", w64(x.e_entry))
  prow(f"elf_hdr_{tag}_shnum", x.e_shnum)
  prow(f"elf_hdr_{tag}_shstrndx", x.e_shstrndx)
  prow(f"elf_hdr_{tag}_shentsize_declared", x.e_shentsize)
  prow(f"elf_hdr_{tag}_shdr_stride", libc.Elf64_Shdr.SIZE if is64(b) else libc.Elf32_Shdr.SIZE)
  prow(f"elf_hdr_{tag}_shdr_nfields", (libc.Elf64_Shdr.SIZE if is64(b) else libc.Elf32_Shdr.SIZE)//10)
  row(f"elf_hdr_{tag}_magic", b[0:4].hex())
  prow(f"elf_hdr_{tag}_bytes", len(b))
  prow(f"elf_hdr_{tag}_is64", is64(b))
  # THE PORT'S `Ehdr.text` SPELLS THE Elf64 REGISTER TABLE for BOTH classes --
  # deliberately: that row is about the TABLE (its names, its order, its
  # offsets), and the per-CLASS VALUES are gated by the separate `*_ehsize` /
  # `*_shoff` / `*_shnum` rows above, which read through the ctypes struct and so
  # through the class. The port's `Shdr.at_text` spells the Elf64 table for the
  # same reason, and `elf_sec_*_hdrtxt` is the row where the Elf32 OFFSETS are
  # gated -- through `Shdr.at`, which does branch on the class.
  # The LABEL is the Elf64 register offset (the table). The VALUE is read through
  # the ctypes struct, i.e. through the fixture's OWN class, so the Elf32 fixtures
  # read e_shoff@32 where the Elf64 ones read e_shoff@40. That split is the point:
  # the row says "the field named e_shoff sits at Elf64 offset 40, and its value
  # here is whatever this class's layout puts there".
  E = {"e_type": x.e_type, "e_machine": x.e_machine, "e_version": x.e_version,
       "e_entry": x.e_entry, "e_phoff": x.e_phoff, "e_shoff": x.e_shoff,
       "e_flags": x.e_flags, "e_ehsize": x.e_ehsize, "e_phentsize": x.e_phentsize,
       "e_phnum": x.e_phnum, "e_shentsize": x.e_shentsize, "e_shnum": x.e_shnum,
       "e_shstrndx": x.e_shstrndx}
  row(f"elf_hdr_{tag}_hdr", ",".join(Ehdr_label(n, o, E[n], c) for n, c, o in FHDR64))

def Sec_all(tag, b):
  try:
    image, sections, relocs = elf_loader(b, link_libs=[STUB])
    ok = 1
  except Exception:
    ok = 0
  r = shdrs(b)
  prow(f"elf_sec_{tag}_nsec", len(r))
  shoff = struct.unpack_from("<Q" if is64(b) else "<I", b, 40 if is64(b) else 32)[0]
  shsz = libc.Elf64_Shdr.SIZE if is64(b) else libc.Elf32_Shdr.SIZE
  row(f"elf_sec_{tag}_hdrtxt", ";".join(shtxt(b, shoff + i*shsz, i) for i in range(len(r))))
  row(f"elf_sec_{tag}_names", ",".join(s.name for s in sections))
  # `sh_flags` IS an `Elf64_Xword`, the same class as sh_addr/sh_offset/sh_size/
  # sh_entsize, so it is rendered `hi:lo` like them. The first version of this
  # oracle printed it BARE with the three u32 columns, which made the port's
  # `sh_flags: W64` disagree with the oracle on every section of every file --
  # and a bare render is the one that CANNOT catch a high half. NOTE, measured:
  # no toolchain sets a `sh_flags` bit above 2**31 (`SHF_MASKOS` is 0x0ff00000,
  # `SHF_MASKPROC` is 0xf0000000), so on REAL fixtures the high half is always 0
  # and the WIDTH of `sh_flags` is not observable. What the row pins is the
  # values, their order, and -- via `hdrtxt` -- the byte offsets. The width is
  # pinned by the type, not by a fixture, and the report says so.
  for nm, i in [("sh_name",0),("sh_type",1),("sh_link",6),("sh_info",7)]:
    row(f"elf_sec_{tag}_{nm}", ",".join(str(x[i]) for x in r))
  row(f"elf_sec_{tag}_sh_flags", ",".join(w64(x[2]) for x in r))
  row(f"elf_sec_{tag}_sh_addr", ",".join(w64(x[3]) for x in r))
  row(f"elf_sec_{tag}_sh_offset", ",".join(w64(x[4]) for x in r))
  row(f"elf_sec_{tag}_sh_size", ",".join(w64(x[5]) for x in r))
  row(f"elf_sec_{tag}_sh_entsize", ",".join(w64(x[9]) for x in r))
  row(f"elf_sec_{tag}_content_lens", ",".join(str(len(s.content)) for s in sections))
  row(f"elf_sec_{tag}_content0", bytes(sections[0].content).hex()[:16] if sections else "")
  row(f"elf_sec_{tag}_content1", bytes(sections[1].content).hex()[:16] if len(sections) > 1 else "")
  prow(f"elf_sec_{tag}_shstrtab_bytes", len(sstrtab(b)))

def Str_walk(tag, b):
  t = sstrtab(b)
  r = shdrs(b)
  prow(f"elf_str_{tag}_shstrtab_bytes", len(t))
  row(f"elf_str_{tag}_shstrtab_head", t[:16].hex())
  row(f"elf_str_{tag}_names", ",".join(strtab_at(t, x[0]) for x in r))

def main():
  g_glob()
  for fn, tag in ALL:
    b = blob(fn)
    Sec_hdr(tag, b)
    if (fn, tag) in FIXTURES:
      Sec_all(tag, b)
    Str_walk(tag, b)
  # THE EXIT GUARD. If this script reached the end it wrote at least the
  # field-order rows, so an empty OUT is a bug and must not exit 0.
  assert len(OUT) > 0, "ORACLE EMITTED ZERO ROWS"
  # THE COMPLETION SENTINEL, on BOTH sides. The Bend port prints `elf-done=1`
  # as its last statement, which is how a truncated run -- a bend machine-stack
  # overflow kills the interpreter mid-walk, and it does so about 1 run in 20 --
  # is told apart from a clean one. `elfdiff.py` treats a row present on one
  # side and absent on the other as a MISMATCH, so the oracle has to carry the
  # same sentinel or the gate would report a permanent false positive.
  row("elf-done", 1)
# ===========================================================================
# THE LOADER FAMILIES: the image assembly (elf.py:32-38), the symbol table
# (elf.py:29), the relocation list (elf.py:40-48) and jit_loader (elf.py:52-86).
#
# EVERY VALUE HERE IS CALLED OUT OF tinygrad's OWN `elf_loader` / `jit_loader` on
# a REAL ELF FILE. The FNV-1a 32 digest replaces sha256 because the image is a few
# kilobytes and sha256 is not writable in bend; it is the same word on both sides
# (bend's U32 wraps mod 2**32 exactly as Python's `& 0xffffffff` does -- MEASURED)
# and it is a fingerprint, not a security property.
def fnv1a(b):
  h = 2166136261
  for x in b:
    h = ((h ^ x) * 16777619) & 0xffffffff
  return h

# THE FOUR LIBRARIES `link_sym` IS ASKED ABOUT, AND WHAT EACH REALLY EXPORTS.
# `getattr(ctypes.CDLL(path), name)` on the four real dylibs -- a measurement, so
# `elf_ls_*` says what this machine answers rather than what the port believes.
LIBM, LIRT, LIOBJC, LSTUB = (ctypes.CDLL("/usr/lib/libm.dylib"),
                            ctypes.CDLL("/usr/lib/libSystem.dylib"),
                            ctypes.CDLL("/usr/lib/libobjc.dylib"),
                            ctypes.CDLL(os.path.join(FIX, "libstub.dylib")))
LS_LIBS = [("libm", LIBM), ("rt", LIRT), ("objc", LIOBJC), ("stub", LSTUB)]
LS_SYMS = ["sel_registerName", "objc_msgSend", "sin", "cos", "sqrt", "malloc", "memcpy",
           "ext_fn", "ext_data", "definitely_not_a_symbol"]

def ls_exports(lib, sym):
  try:
    getattr(lib, sym)
    return 1
  except (OSError, AttributeError):
    return 0

def link_sym_rows():
  row("elf_ls_order", ",".join(n for n, _ in LS_LIBS))
  for s in LS_SYMS:
    row(f"elf_ls_{s}", ",".join(str(ls_exports(l, s)) for _, l in LS_LIBS))
  # the SCAN: the 1-BASED position of the first library that exports the symbol,
  # 0 for the refusal. This is what `Link.pick` computes.
  for s in LS_SYMS:
    row(f"elf_ls_pick_{s}", str(next((i + 1 for i, (_, l) in enumerate(LS_LIBS)
                                      if ls_exports(l, s)), 0)))
  # THE ORDER IS LOAD-BEARING: `sin` is in all four, so the answer is 1 whichever
  # order it is asked in, while `sel_registerName` is in libobjc only and the
  # `ops_cpu.py:19/21` pair `[libm, rt]` MISSES it. That is DEFECT 3.
  row("elf_ls_cpu_pair", ",".join(n for n, _ in LS_LIBS[:2]))
  row("elf_ls_cpu_trio", ",".join(n for n, _ in LS_LIBS[:3]))
  for s in ["sel_registerName", "objc_msgSend", "sin", "ext_fn"]:
    row(f"elf_ls_pair_{s}", str(next((i + 1 for i, (_, l) in enumerate(LS_LIBS[:2])
                                      if ls_exports(l, s)), 0)))
    row(f"elf_ls_trio_{s}", str(next((i + 1 for i, (_, l) in enumerate(LS_LIBS[:3])
                                      if ls_exports(l, s)), 0)))
  # THE REFUSAL MESSAGE, VERBATIM, because the message is the observable.
  try:
    link_sym("definitely_not_a_symbol", [LS_LIBS[0][1]])
    row("elf_ls_miss_ok", 1); row("elf_ls_miss_msg", "")
  except RuntimeError as e:
    row("elf_ls_miss_ok", 0); row("elf_ls_miss_msg", str(e))

def Loader_walk(tag, b):
  t = tag.replace("elf_sec_", "").replace("elf_hdr_", "")
  r = shdrs(b)
  x64 = is64(b)
  pbits = [x for x in r if x[1] == libc.SHT_PROGBITS]
  # --- THE IMAGE. elf.py:33's prealloc, then elf.py:34-38.
  fixed = [x for x in pbits if x[3] != 0]
  row(f"elf_built_{t}_prealloc", max([x[3] + x[5] for x in fixed] + [0]))
  row(f"elf_built_{t}_nprogbits", len(pbits))
  row(f"elf_built_{t}_nprogbits_fixed", len(fixed))
  row(f"elf_built_{t}_nprogbits_reloc", len(pbits) - len(fixed))
  row(f"elf_built_{t}_align_max", max([max(x[8], 1) for x in pbits] + [0]))
  try:
    image, sections, relocs = elf_loader(b, link_libs=[LSTUB])
    img = bytes(image)
    row(f"elf_built_{t}_ok", 1)
    row(f"elf_built_{t}_len", len(img))
    row(f"elf_built_{t}_digest", fnv1a(img))
    row(f"elf_built_{t}_head", img[:32].hex())
    row(f"elf_built_{t}_tail", img[-32:].hex())
    row(f"elf_built_{t}_zeros", str(len(img) - sum(1 for x in img if x)))
    # elf.py:38's WRITE-BACK: the addresses of the APPENDED sections are the only
    # observation of it, and they are not in the header the port read.
    row(f"elf_built_{t}_addrs", ",".join(w64(s.header.sh_addr) for s in sections))
    row(f"elf_built_{t}_content_lens", ",".join(str(len(s.content)) for s in sections))
    row(f"elf_built_{t}_content0", bytes(sections[0].content).hex())
    row(f"elf_built_{t}_content1", bytes(sections[1].content).hex())
    row(f"elf_built_{t}_nrelocs", len(relocs))
    row(f"elf_built_{t}_relocs", ",".join(f"{w64(o)}:{w64(g)}:{ty}:{ad}"
                                         for o, g, ty, ad in relocs))
    row(f"elf_built_{t}_reloc_addrs", ",".join(w64(o) for o, _, _, _ in relocs))
    row(f"elf_built_{t}_reloc_tgts", ",".join(w64(g) for _, g, _, _ in relocs))
    row(f"elf_built_{t}_reloc_types", ",".join(str(ty) for _, _, ty, _ in relocs))
    row(f"elf_built_{t}_reloc_addends", ",".join(str(ad) for _, _, _, ad in relocs))
  except Exception as e:
    row(f"elf_built_{t}_ok", 0)
    row(f"elf_built_{t}_err", type(e).__name__)
  # --- jit_loader: THE FUNCTION THAT APPLIES THE RELOCS. ITS OWN `try`, because
  # a jit failure on a file `elf_loader` READ must not overwrite `elf_built_*_ok`.
  try:
    out = jit_loader(b, link_libs=[LSTUB])
    row(f"elf_jit_{t}_ok", 1)
    row(f"elf_jit_{t}_len", len(out))
    row(f"elf_jit_{t}_digest", fnv1a(out))
    row(f"elf_jit_{t}_head", out[:32].hex())
    row(f"elf_jit_{t}_tail", out[-32:].hex())
  except Exception as e:
    row(f"elf_jit_{t}_ok", 0)
    row(f"elf_jit_{t}_err", type(e).__name__)
  # --- THE SYMTAB, read by hand: name/info/other/shndx/value/size, both layouts.
  sts = [i for i, x in enumerate(r) if x[1] == libc.SHT_SYMTAB]
  row(f"elf_sym_{t}_idx", str(sts[0]) if sts else "-1")
  if not sts:
    for k in ["n", "entsize", "order", "nameoff", "value", "info", "other",
              "shndx", "size", "first", "last"]:
      row(f"elf_sym_{t}_{k}", "")
    return
  sx = r[sts[0]]
  cnt = sx[5] // sx[9] if sx[9] else 0
  c = b[sx[4]:sx[4] + sx[5]]
  def at(code, i, off): return struct.unpack_from(code, c, i * sx[9] + off)[0]
  row(f"elf_sym_{t}_n", cnt)
  row(f"elf_sym_{t}_entsize", sx[9])
  row(f"elf_sym_{t}_order", SYM_ORDER[x64])
  co, c4, cb, ch = ("<Q", "<I", "<B", "<H") if x64 else ("<I", "<I", "<B", "<H")
  o_v, o_i, o_o, o_s = (8, 4, 5, 6) if x64 else (4, 12, 13, 14)
  o_z = 16 if x64 else 8
  row(f"elf_sym_{t}_nameoff", ",".join(str(at(c4, i, 0)) for i in range(cnt)))
  row(f"elf_sym_{t}_value", ",".join(str(at(co, i, o_v)) for i in range(cnt)))
  row(f"elf_sym_{t}_info", ",".join(str(at(cb, i, o_i)) for i in range(cnt)))
  row(f"elf_sym_{t}_other", ",".join(str(at(cb, i, o_o)) for i in range(cnt)))
  row(f"elf_sym_{t}_shndx", ",".join(str(at(ch, i, o_s)) for i in range(cnt)))
  row(f"elf_sym_{t}_size", ",".join(str(at(co, i, o_z)) for i in range(cnt)))
  def one(i):
    return ",".join(f"{nm}@{o}:{at(cc, i, o)}" for nm, cc, o in
                    ([("st_name", c4, 0), ("st_info", cb, o_i), ("st_other", cb, o_o),
                      ("st_shndx", ch, o_s), ("st_value", co, o_v), ("st_size", co, o_z)] if x64 else
                     [("st_name", c4, 0), ("st_value", co, o_v), ("st_size", co, o_z),
                      ("st_info", cb, o_i), ("st_other", cb, o_o), ("st_shndx", ch, o_s)]))
  row(f"elf_sym_{t}_first", one(0))
  row(f"elf_sym_{t}_last", one(cnt - 1))

# THE Sym FIELD ORDER, as the gABI declares it, per class. THE OFFSETS DIFFER AND
# THE ORDER DOES NOT, so this is one row per class and not a count: Elf64 is
# name, info, other, shndx, value, size and Elf32 is name, value, size, info,
# other, shndx.
SYM_ORDER = {True: "st_name,st_info,st_other,st_shndx,st_value,st_size",
             False: "st_name,st_value,st_size,st_info,st_other,st_shndx"}

def Reloc_rows():
  # THE relocate PRIMITIVES, measured off tinygrad's OWN helpers and off struct.
  # `relocate` is a closure and is unreachable, so its arms are gated through
  # these constants and the two trampolines, which are MEASURED here and not
  # transcribed -- and through `elf_jit_*` above, which is the real thing.
  for nm, v in [("rc_x86_pc32", libc.R_X86_64_PC32), ("rc_x86_plt32", libc.R_X86_64_PLT32),
                ("rc_a64_adr", libc.R_AARCH64_ADR_PREL_PG_HI21),
                ("rc_a64_add_lo12", libc.R_AARCH64_ADD_ABS_LO12_NC),
                ("rc_a64_ldst16", libc.R_AARCH64_LDST16_ABS_LO12_NC),
                ("rc_a64_ldst32", libc.R_AARCH64_LDST32_ABS_LO12_NC),
                ("rc_a64_ldst64", libc.R_AARCH64_LDST64_ABS_LO12_NC),
                ("rc_a64_ldst128", libc.R_AARCH64_LDST128_ABS_LO12_NC),
                ("rc_a64_call26", libc.R_AARCH64_CALL26), ("rc_ten_arms", 10)]:
    row(f"elf_{nm}", v)
  # THE TWO TRAMPOLINES -- the arms that WRITE INTO `image`.
  for nm, v in [("t16", 0), ("t32", 0x11223344), ("t64", 0x1122334455667788)]:
    row(f"elf_tr_x86_{nm}", struct.pack("<HIQ", 0x25FF, 0, v).hex())
    row(f"elf_tr_arm_{nm}", struct.pack("<IIQ", 0x58000051, 0xD61F0220, v).hex())
  row("elf_tr_x86_len", len(struct.pack("<HIQ", 0x25FF, 0, 0)))
  row("elf_tr_arm_len", len(struct.pack("<IIQ", 0x58000051, 0xD61F0220, 0)))
  # `len(image) - 14 + addend - ploc` and `len(image) - ploc - 16` at THREE
  # lengths and TWO plocs, so `-14` and `-16` cannot be transposed against the
  # trampoline they belong to.
  for L in (16, 64, 4096):
    for ploc in (0, 8):
      for ad in (0, 4):
        row(f"elf_tr_x86_ret_{L}_{ploc}_{ad}", (L - 14 + ad - ploc) & 0xffffffff)
      row(f"elf_tr_arm_ret_{L}_{ploc}", (L - ploc - 16) & 0xffffffff)
  # THE FOUR-BYTE WRITE of elf.py:85.
  for w in [0, 1, 0x7fffffff, 0x80000000, 0xffffffff, 0x11223344, 0xdeadbeef]:
    row(f"elf_ld_pack_{w:08x}", struct.pack("<I", w).hex())
  row("elf_ld_unpack", struct.unpack("<I", struct.pack("<I", 0x11223344))[0])
  # `getbits` over every range the ten arms use, both signs.
  for v, s_, e_ in [(0x1234,12,13),(0x1234,14,32),(0xabcd,0,11),(0xabcd,1,11),(0xabcd,2,11),
                    (0xabcd,3,11),(0xabcd,4,11),(0xabcd,2,27),(0xdeadbeef,0,31),(0xdeadbeef,0,0),
                    (0xffffffff,12,13),(0,12,13),(0xffffffff,14,32),(0x1000,12,13)]:
    row(f"elf_gb_{v:08x}_{s_}_{e_}", getbits(v, s_, e_))
  # `i2u(32, v)` on BOTH signs -- the encoding, which is the magnitude PLUS
  # 2**32 when negative and so is not the magnitude alone.
  for v in [0,1,-1,-1000,2147483647,-2147483648,0x7fffff00,-2]:
    row(f"elf_i2u32_{v}", i2u(32, v))
  # THE RANGE TESTS, at every boundary, and they are TWO DIFFERENT predicates.
  for v in [0, 2147483647, 2147483648, -2147483648, -2147483649, 4294967295]:
    row(f"elf_rel32_in_{v}", int(-2**31 <= v < 2**31))
  for v in [0, 33554431, 33554432, 134217724, 134217727, 134217728, -1, -33554432, -33554433]:
    row(f"elf_call26_in_{v}", int(-(2**25) <= v <= (2**25 - 1) * 4))
  # THE ADRP PAGE MASK, `v & ~0xFFF`, and the two shifted getbits.
  for v in [0, 0xfff, 0x1000, 0x1fff, 0x123456, 0xffffffff]:
    row(f"elf_pgmask_{v:08x}", v & ~0xFFF)
  for v in [0, 0x1234, 0x12340, 0xfffff000]:
    row(f"elf_adr_hi21_{v:08x}", getbits(v, 12, 13) << 29)
    row(f"elf_adr_lo19_{v:08x}", getbits(v, 14, 32) << 5)
  # `getbits(tgt, s, 11) << 10` -- the five lo12 arms, one per shift amount.
  for v in [0, 0x7ff, 0x800, 0xffff, 0xffffffff]:
    for sh in range(5):
      row(f"elf_lo12_{v:08x}_{sh}", getbits(v, sh, 11) << 10)
  # `getbits(x, 2, 27)` -- the CALL26 in-range arm's field, which is shifted by
  # TWO and not by zero.
  for v in [0, 3, 0xfffffff, 0xffffffff, 0x7ffffffc]:
    row(f"elf_call26_gb_{v:08x}", getbits(v, 2, 27))

def Align_lanes(tag, b):
  # `force_section_align` only bites when a PROGBITS has sh_addr == 0, so every
  # fixture is run at four alignments and the LENGTH plus the ADDRESSES are the
  # rows -- a length alone cannot see a byte moved within the image.
  t = tag.replace("elf_sec_", "")
  r = shdrs(b)
  p0 = [x for x in r if x[1] == libc.SHT_PROGBITS and x[3] == 0]
  for a in (1, 4, 16, 256):
    row(f"elf_al_{t}_a{a}_nreloc_pbits", len(p0))
    row(f"elf_al_{t}_a{a}_align_used", ",".join(str(max(x[8], a)) for x in p0))
    img = 0
    addrs = []
    for x in r:
      if x[1] != libc.SHT_PROGBITS or x[3] != 0: continue
      al = max(x[8], a)
      img += ((al - img % al) % al)
      addrs.append(img)
      img += x[5]
    row(f"elf_al_{t}_a{a}_model_len", img)
    row(f"elf_al_{t}_a{a}_model_addrs", ",".join(str(x) for x in addrs))
    try:
      image, sections, relocs = elf_loader(b, force_section_align=a, link_libs=[LSTUB])
      row(f"elf_al_{t}_a{a}_ok", 1)
      row(f"elf_al_{t}_a{a}_len", len(bytes(image)))
      row(f"elf_al_{t}_a{a}_addrs", ",".join(w64(s.header.sh_addr) for s in sections))
    except Exception as e:
      row(f"elf_al_{t}_a{a}_ok", 0)
      row(f"elf_al_{t}_a{a}_err", type(e).__name__)

def main2():
  g_glob()
  for fn, tag in ALL:
    b = blob(fn)
    Sec_hdr(tag, b)
    if (fn, tag) in FIXTURES:
      Sec_all(tag, b)
    Str_walk(tag, b)
    Loader_walk(tag, b)
    Align_lanes(tag, b)
  link_sym_rows()
  Reloc_rows()
  row("elf-done", 1)
  sys.stdout.write("\n".join(OUT) + "\n")

main2()
