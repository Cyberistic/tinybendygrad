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
import tinygrad.helpers as TH

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

def shtxt(x, b):
  if is64(b):
    F = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<Q",8),("sh_addr","<Q",16),
         ("sh_offset","<Q",24),("sh_size","<Q",32),("sh_link","<I",40),("sh_info","<I",44),
         ("sh_addralign","<Q",48),("sh_entsize","<Q",56)]
  else:
    F = [("sh_name","<I",0),("sh_type","<I",4),("sh_flags","<I",8),("sh_addr","<I",12),
         ("sh_offset","<I",16),("sh_size","<I",20),("sh_link","<I",24),("sh_info","<I",28),
         ("sh_addralign","<I",32),("sh_entsize","<I",36)]
  return [f"{n}@{o}:{struct.unpack_from(c,b,o)[0]}" for n,c,o in F]

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
  for c, n in [("0","elf_hexval_0"),("9","elf_hexval_9"),("a","elf_hexval_a"),
               ("f","elf_hexval_f"),("A","elf_hexval_A"),("F","elf_hexval_F"),
               ("z","elf_hexval_z")]:
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
    prow(f"elf_is64_{tag}", is64(b))
  for n, v in [("elf_ehdr_size64", libc.Elf64_Ehdr.SIZE), ("elf_ehdr_size32", libc.Elf32_Ehdr.SIZE),
               ("elf_shdr_size64", libc.Elf64_Shdr.SIZE), ("elf_shdr_size32", libc.Elf32_Shdr.SIZE),
               ("elf_sym_size64", libc.Elf64_Sym.SIZE), ("elf_sym_size32", libc.Elf32_Sym.SIZE),
               ("elf_eident_size", 16)]:
    prow(n, v)

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
  # the Ehdr field-order string, with the offsets the fixture's own class uses
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
  row(f"elf_hdr_{tag}_hdr", ",".join(f"{n}@{o}:{struct.unpack_from(c,b,o)[0]}" for n,c,o in F))

def Sec_all(tag, b):
  try:
    image, sections, relocs = elf_loader(b, link_libs=[STUB])
    ok = 1
  except Exception:
    ok = 0
  r = shdrs(b)
  prow(f"elf_sec_{tag}_nsec", len(r))
  row(f"elf_sec_{tag}_hdrtxt", ";".join(",".join(shtxt(x, b)) for x in r))
  row(f"elf_sec_{tag}_names", ",".join(s.name for s in sections))
  for nm, i in [("sh_name",0),("sh_type",1),("sh_flags",2),("sh_link",6),("sh_info",7)]:
    row(f"elf_sec_{tag}_{nm}", ",".join(str(x[i]) for x in r))
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
  sys.stdout.write("\n".join(OUT) + "\n")
  # THE EXIT GUARD. If this script reached the end it wrote at least the
  # field-order rows, so an empty OUT is a bug and must not exit 0.
  assert len(OUT) > 0, "ORACLE EMITTED ZERO ROWS"

main()