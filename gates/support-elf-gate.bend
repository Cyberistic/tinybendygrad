# gates/support-elf-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/support/elf.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/support/elf.bend as P
import ./../tinybendygrad/helpers.bend as H

# elf.py:17's `{P.ELFCLASS32: "Elf32", P.ELFCLASS64: "Elf64"}[blob[P.EI_CLASS]]`. The
# dict SUBSCRIPT raises KeyError on anything else, so the total form is the name
# plus the `is64` Bool the rest of the file branches on.
def is64(+h: String) -> Bool: U32.is_eq(P.Blob.u8(h, P.EI_CLASS()), P.ELFCLASS64())
def ecls.name(x: Bool) -> String: Bool.pick(String, x, "Elf64", "Elf32")

def brow(nm: String, v: Bool) -> IO(Unit): P.urow(nm, P.b01(v))


# --- THE GATE ROWS ----------------------------------------------------
# ===========================================================================
# THE ROWS.
# ===========================================================================
def g_glob() -> IO(Unit):
  do IO<Unit>:
    # --- THE FIELD-ORDER STRINGS. These are the gABI `register_fields` name
    # lists, and a transposition shows HERE first.
    P.row("elf_F_EHDR", P.F_EHDR())
    P.row("elf_F_SHDR", P.F_SHDR())
    P.row("elf_F_SYM64", P.F_SYM64())
    P.row("elf_F_SYM32", P.F_SYM32())
    P.row("elf_F_RELA", P.F_RELA())
    P.row("elf_F_REL", P.F_REL())
    # --- THE CONSTANTS, measured off autogen/libc.py.
    P.urow("elf_c_ELFMAG", P.ELFMAG())
    P.urow("elf_c_EI_CLASS", P.EI_CLASS())
    P.urow("elf_c_ELFCLASS32", P.ELFCLASS32())
    P.urow("elf_c_ELFCLASS64", P.ELFCLASS64())
    P.urow("elf_c_SHT_NULL", P.SHT_NULL())
    P.urow("elf_c_SHT_PROGBITS", P.SHT_PROGBITS())
    P.urow("elf_c_SHT_SYMTAB", P.SHT_SYMTAB())
    P.urow("elf_c_SHT_STRTAB", P.SHT_STRTAB())
    P.urow("elf_c_SHT_RELA", P.SHT_RELA())
    P.urow("elf_c_SHT_NOBITS", P.SHT_NOBITS())
    P.urow("elf_c_SHT_REL", P.SHT_REL())
    P.urow("elf_c_SHF_WRITE", P.SHF_WRITE())
    P.urow("elf_c_SHF_ALLOC", P.SHF_ALLOC())
    P.urow("elf_c_SHF_EXECINSTR", P.SHF_EXECINSTR())
    # --- THE BYTE LAYER, against CPython's struct.unpack.
    P.row("elf_blk_hexlen", U32.show(P.Blob.hexlen(P.B_E64_O())))
    P.row("elf_blk_bytes", U32.show(P.Blob.nbytes(P.B_E64_O())))
    P.row("elf_blk_magic_hex", P.Blob.magic_hex(P.B_E64_O()))
    P.urow("elf_blk_u8_0", P.Blob.u8(P.B_E64_O(), 0))
    P.urow("elf_blk_u8_1", P.Blob.u8(P.B_E64_O(), 1))
    P.urow("elf_blk_u8_3", P.Blob.u8(P.B_E64_O(), 3))
    P.urow("elf_blk_u8_4", P.Blob.u8(P.B_E64_O(), 4))
    P.urow("elf_blk_le16_16", P.Blob.le16(P.B_E64_O(), 16))
    P.urow("elf_blk_le16_18", P.Blob.le16(P.B_E64_O(), 18))
    P.urow("elf_blk_le32_20", P.Blob.le32(P.B_E64_O(), 20))
    P.urow("elf_blk_le32_40", P.Blob.le32(P.B_E64_O(), 40))
    P.urow("elf_blk_le32_44", P.Blob.le32(P.B_E64_O(), 44))
    P.urow("elf_blk_le32_56", P.Blob.le32(P.B_E64_O(), 56))
    P.urow("elf_blk_le32_60", P.Blob.le32(P.B_E64_O(), 60))
    P.row("elf_blk_slice_0_4", P.Blob.slice(P.B_E64_O(), 0, 4))
    P.row("elf_blk_slice_4_4", P.Blob.slice(P.B_E64_O(), 4, 4))
    P.row("elf_blk_slice_896_16", P.Blob.slice(P.B_E64_O(), 896, 16))
    # --- THE HEX PARSER. All THREE offsets, and the uppercase arm is 55 not 87 --
    # the mistake a single-constant spelling makes, which SATURATES U32.
    P.urow("elf_hexval_0", P.Hex.val(Char.from_u32(48)))
    P.urow("elf_hexval_9", P.Hex.val(Char.from_u32(57)))
    P.urow("elf_hexval_a", P.Hex.val(Char.from_u32(97)))
    P.urow("elf_hexval_f", P.Hex.val(Char.from_u32(102)))
    P.urow("elf_hexval_A", P.Hex.val(Char.from_u32(65)))
    P.urow("elf_hexval_F", P.Hex.val(Char.from_u32(70)))
    P.urow("elf_hexval_z", P.Hex.val(Char.from_u32(122)))
    P.urow("elf_hexval_g", P.Hex.val(Char.from_u32(103)))
    P.urow("elf_hexval_slash", P.Hex.val(Char.from_u32(47)))
    # --- THE HEX FORMATTER, all sixteen nibbles, plus the endianness pair.
    P.row("elf_hexdig", P.Hex.digit(0n) ++ P.Hex.digit(1n) ++ P.Hex.digit(2n) ++ P.Hex.digit(3n) ++ P.Hex.digit(4n) ++ P.Hex.digit(5n) ++ P.Hex.digit(6n) ++ P.Hex.digit(7n) ++ P.Hex.digit(8n) ++ P.Hex.digit(9n) ++ P.Hex.digit(10n) ++ P.Hex.digit(11n) ++ P.Hex.digit(12n) ++ P.Hex.digit(13n) ++ P.Hex.digit(14n) ++ P.Hex.digit(15n))
    P.row("elf_hexof_deadbeef", P.Hex.of(3735928559))
    P.row("elf_hexof_0", P.Hex.of(0))
    P.row("elf_hexof_ffffffff", P.Hex.of(4294967295))
    P.row("elf_hexpair_1234", P.Hex.pair(4660))
    P.row("elf_hexu8_ff", P.Hex.u8(255))
    P.row("elf_hexu8_00", P.Hex.u8(0))
    # --- THE MAGIC AND THE CLASS, on EVERY fixture including the two that refuse.
    brow("elf_magic_e64", P.magic_ok(P.B_E64_O()))
    brow("elf_magic_ea64", P.magic_ok(P.B_EA64_O()))
    brow("elf_magic_e32", P.magic_ok(P.B_E32_O()))
    brow("elf_magic_n64", P.magic_ok(P.B_N64_O()))
    brow("elf_magic_na64", P.magic_ok(P.B_NA64_O()))
    brow("elf_magic_n32", P.magic_ok(P.B_N32_O()))
    brow("elf_magic_ja64", P.magic_ok(P.B_JA64_O()))
    brow("elf_magic_r64so", P.magic_ok(P.B_R64_SO()))
    brow("elf_magic_rx64exe", P.magic_ok(P.B_RX64_EXE()))
    P.urow("elf_ei_class_e64", P.Blob.u8(P.B_E64_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_ea64", P.Blob.u8(P.B_EA64_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_e32", P.Blob.u8(P.B_E32_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_n64", P.Blob.u8(P.B_N64_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_na64", P.Blob.u8(P.B_NA64_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_n32", P.Blob.u8(P.B_N32_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_ja64", P.Blob.u8(P.B_JA64_O(), P.EI_CLASS()))
    P.urow("elf_ei_class_r64so", P.Blob.u8(P.B_R64_SO(), P.EI_CLASS()))
    P.urow("elf_ei_class_rx64exe", P.Blob.u8(P.B_RX64_EXE(), P.EI_CLASS()))
    P.row("elf_ecls_e64", ecls.name(is64(P.B_E64_O())))
    P.row("elf_ecls_ea64", ecls.name(is64(P.B_EA64_O())))
    P.row("elf_ecls_e32", ecls.name(is64(P.B_E32_O())))
    P.row("elf_ecls_n64", ecls.name(is64(P.B_N64_O())))
    P.row("elf_ecls_na64", ecls.name(is64(P.B_NA64_O())))
    P.row("elf_ecls_n32", ecls.name(is64(P.B_N32_O())))
    P.row("elf_ecls_ja64", ecls.name(is64(P.B_JA64_O())))
    P.row("elf_ecls_r64so", ecls.name(is64(P.B_R64_SO())))
    P.row("elf_ecls_rx64exe", ecls.name(is64(P.B_RX64_EXE())))
    brow("elf_is64_e64", is64(P.B_E64_O()))
    brow("elf_is64_ea64", is64(P.B_EA64_O()))
    brow("elf_is64_e32", is64(P.B_E32_O()))
    brow("elf_is64_n64", is64(P.B_N64_O()))
    brow("elf_is64_na64", is64(P.B_NA64_O()))
    brow("elf_is64_n32", is64(P.B_N32_O()))
    brow("elf_is64_ja64", is64(P.B_JA64_O()))
    brow("elf_is64_r64so", is64(P.B_R64_SO()))
    brow("elf_is64_rx64exe", is64(P.B_RX64_EXE()))
    # --- THE STRUCT SIZES, both classes. The AMD packer needs the Elf64 one
    # (renderer/amd/elf.py:50) so it is gated in BOTH files.
    P.urow("elf_ehdr_size64", P.Ehdr.size(True{}))
    P.urow("elf_ehdr_size32", P.Ehdr.size(False{}))
    P.urow("elf_shdr_size64", P.Shdr.size(True{}))
    P.urow("elf_shdr_size32", P.Shdr.size(False{}))
    P.urow("elf_sym_size64", P.Sym.size(True{}))
    P.urow("elf_sym_size32", P.Sym.size(False{}))
    P.urow("elf_eident_size", P.Ehdr.e_ident_size())

def Sec.ehdr(+t: String, +h: String) -> IO(Unit):
  do IO<Unit>:
    P.row(String.concat([t, "_hdr"]), P.Ehdr.text(P.Ehdr.at(h, is64(h))))
    P.row(String.concat([t, "_ehsize"]), U32.show(P.Ehdr.size(is64(h))))
    P.row(String.concat([t, "_shoff"]), P.W64.text(P.Ehdr.e_shoff(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_phoff"]), P.W64.text(P.Ehdr.e_phoff(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_entry"]), P.W64.text(P.Ehdr.e_entry(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_shnum"]), U32.show(P.Ehdr.e_shnum(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_shstrndx"]), U32.show(P.Ehdr.e_shstrndx(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_shentsize_declared"]), U32.show(P.Ehdr.e_shentsize(P.Ehdr.at(h, is64(h)))))
    P.row(String.concat([t, "_shdr_stride"]), U32.show(P.Shdr.size(is64(h))))
    P.row(String.concat([t, "_shdr_nfields"]), U32.show(P.Shdr.nfields(is64(h))))
    P.row(String.concat([t, "_magic"]), P.Blob.magic_hex(h))
    P.row(String.concat([t, "_bytes"]), U32.show(P.Blob.nbytes(h)))
    P.row(String.concat([t, "_is64"]), Bool.show(is64(h)))

def Sec.all(+t: String, +h: String) -> IO(Unit):
  do IO<Unit>:
    P.row(String.concat([t, "_nsec"]), U32.show(P.Sections.len(P.Sections.of(h, P.Ehdr.at(h, is64(h)), is64(h)))))
    P.row(String.concat([t, "_names"]), P.Sec.names(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_hdrtxt"]), P.Sec.hd_text(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h)), is64(h)))
    P.row(String.concat([t, "_sh_name"]), P.Sec.col.name(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_type"]), P.Sec.col.typ(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_flags"]), P.Sec.col.flags(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_link"]), P.Sec.col.link(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_info"]), P.Sec.col.info(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_addr"]), P.Sec.col.addr(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_offset"]), P.Sec.col.off(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_size"]), P.Sec.col.size(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_sh_entsize"]), P.Sec.col.ent(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_content_lens"]), P.Sec.lens(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h))))
    P.row(String.concat([t, "_content0"]), P.Sec.content_hex(P.Sections.at_sec(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h)), 0)))
    P.row(String.concat([t, "_content1"]), P.Sec.content_hex(P.Sections.at_sec(P.Sections.build(h, P.Ehdr.at(h, is64(h)), is64(h)), 1)))
    P.row(String.concat([t, "_shstrtab_bytes"]), U32.show(P.Blob.nbytes(P.shstrtab(h, P.Ehdr.at(h, is64(h)), is64(h)))))

def g_sec() -> IO(Unit):
  do IO<Unit>:
    Sec.ehdr("elf_hdr_e64", P.B_E64_O())
    Sec.ehdr("elf_hdr_ea64", P.B_EA64_O())
    Sec.ehdr("elf_hdr_e32", P.B_E32_O())
    Sec.ehdr("elf_hdr_n64", P.B_N64_O())
    Sec.ehdr("elf_hdr_na64", P.B_NA64_O())
    Sec.ehdr("elf_hdr_n32", P.B_N32_O())
    Sec.ehdr("elf_hdr_ja64", P.B_JA64_O())
    Sec.ehdr("elf_hdr_r64so", P.B_R64_SO())
    Sec.ehdr("elf_hdr_rx64exe", P.B_RX64_EXE())
    Sec.all("elf_sec_e64", P.B_E64_O())
    Sec.all("elf_sec_ea64", P.B_EA64_O())
    Sec.all("elf_sec_e32", P.B_E32_O())
    Sec.all("elf_sec_n64", P.B_N64_O())
    Sec.all("elf_sec_na64", P.B_NA64_O())
    Sec.all("elf_sec_n32", P.B_N32_O())
    Sec.all("elf_sec_ja64", P.B_JA64_O())

def Str.walk(+t: String, +h: String) -> IO(Unit):
  do IO<Unit>:
    P.row(String.concat([t, "_shstrtab_bytes"]), U32.show(P.Blob.nbytes(P.shstrtab(h, P.Ehdr.at(h, is64(h)), is64(h)))))
    P.row(String.concat([t, "_shstrtab_head"]), String.take(P.shstrtab(h, P.Ehdr.at(h, is64(h)), is64(h)), 32n))
    P.row(String.concat([t, "_names"]), P.Str.names(P.Sections.of(h, P.Ehdr.at(h, is64(h)), is64(h)), P.shstrtab(h, P.Ehdr.at(h, is64(h)), is64(h))))

def g_str() -> IO(Unit):
  do IO<Unit>:
    Str.walk("elf_str_e64", P.B_E64_O())
    Str.walk("elf_str_ea64", P.B_EA64_O())
    Str.walk("elf_str_e32", P.B_E32_O())
    Str.walk("elf_str_n64", P.B_N64_O())
    Str.walk("elf_str_na64", P.B_NA64_O())
    Str.walk("elf_str_n32", P.B_N32_O())
    Str.walk("elf_str_ja64", P.B_JA64_O())
    Str.walk("elf_str_r64so", P.B_R64_SO())
    Str.walk("elf_str_rx64exe", P.B_RX64_EXE())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- g_glob()
    b : Unit <- g_sec()
    c : Unit <- g_str()
    IO.print("elf-done=1")
