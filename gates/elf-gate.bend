# gates/elf-gate.bend -- THE GATE DRIVER for `tinybendygrad/renderer/amd/elf.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/renderer/amd/elf.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/renderer/amd/dsl.bend as D

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(String.eq(got, want))]))
def urow(nm: String, got: U32, want: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(U32.is_eq(got, want))]))

# int.from_bytes(inst().to_bytes(), 'little'), called.
# rdna3/ins.py:1144 s_code_end; cdna/ins.py s_nop. elf.py:11-12, :48.
# Both are 4 bytes: [0, 0, 159, 191] and [0, 0, 128, 191].
def s_code_end_word() -> U32: 3214868480
def s_nop_cdna_word() -> U32: 3212836864
def scan_text(xs: List<&2, P.Ins>) -> String: P.Mx.text(P.scan(xs))

# `u.dtype.itemsize if u.addrspace is AddrSpace.ALU else 8`. GLOBAL's itemsize
# is NOT what lands in kernarg: a float32 global is 4 bytes and the else arm
# writes 8. Called: slots (0, ALU, 4), (1, ALU, 1), (2, GLOBAL, 4) packed to
# kernarg 16, which is the sorted fold of [4, 1, 8], not [4, 1, 4].
def param_size(alu: Bool, item: U32) -> U32: Bool.pick(U32, alu, item, 8)

def sh_names_text() -> String:
  String.concat([U32.show(P.sh_name0()), ",", U32.show(P.sh_name1()), ",", U32.show(P.sh_name2())])

# v_mov_b32_e32(v[i], s[j]): vdst is a VGPR Reg, src0 is an SGPR Reg, encoding
# is a FixedBitField the scan skips. Operand types are not acc types.
def vmov(vi: U32, sj: U32) -> P.Ins:
  P.ins_of(Nil{}, [P.ufix("encoding", 0, 1), P.ureg("vdst", U32.add(256, vi), 1), P.ureg("src0", sj, 1)], 0)
# v_accvgpr_mov_b32_e32(v[d], v[s]): both operands are acc types. Called.
def accmov(d: U32, s0: U32) -> P.Ins:
  P.ins_of([P.Opr{"vdst", P.OPR_ACCVGPR()}, P.Opr{"src0", P.OPR_SRC_ACCVGPR()}],
    [P.ufix("encoding", 0, 1), P.ureg("vdst", U32.add(256, d), 1), P.ureg("src0", U32.add(256, s0), 1)], 0)

def fx_empty() -> List<&2, P.Ins>: Nil{}
def fx_vgpr0() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("vdst", 256, 1)], 0)]
def fx_vgpr5() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("vdst", 261, 2)], 0)]
def fx_sgpr3() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("sdst", 3, 1)], 0)]
def fx_sgpr105() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("sdst", 105, 1)], 0)]
def fx_sgpr106() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("sdst", 106, 1)], 0)]
def fx_acc() -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"vdst", P.OPR_ACCVGPR()}], [P.ureg("vdst", 256, 4)], 0)]
def fx_src_acc() -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"src0", P.OPR_SRC_ACCVGPR()}], [P.ureg("src0", 260, 1)], 0)]
def fx_or(cd: U32) -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"vdst", P.OPR_VGPR_OR_ACCVGPR()}], [P.ureg("vdst", 258, 1)], cd)]
def fx_or_src() -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"src0", P.OPR_SRC_VGPR_OR_ACCVGPR()}], [P.ureg("src0", 270, 2)], 1)]
def fx_or_const() -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"src0", P.OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST()}], [P.ureg("src0", 256, 1)], 1)]
def fx_fixed() -> List<&2, P.Ins>:
  [P.ins_of(Nil{}, [P.ufix("enc", 256, 8), P.ureg("vdst", 256, 1)], 0)]
def fx_imm() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.uimm("imm")], 0)]
def fx_both() -> List<&2, P.Ins>:
  [P.ins_of([P.Opr{"vdst", P.OPR_ACCVGPR()}], [P.ureg("vdst", 256, 2), P.ureg("sdst", 4, 2)], 0)]
def fx_hi() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("vdst", 511, 1)], 0)]
def fx_512() -> List<&2, P.Ins>: [P.ins_of(Nil{}, [P.ureg("vdst", 512, 1)], 0)]

def none_l() -> List<&2, P.Lds>: Nil{}
def none_p() -> List<&2, P.Slot>: Nil{}
def none_g() -> List<&2, String>: Nil{}
def pack(arch: String, insts: List<&2, P.Ins>, code_len: U32, locs: List<&2, P.Lds>,
    params: List<&2, P.Slot>, gids: List<&2, String>) -> String:
  P.assemble_linear(arch, insts, code_len, locs, params, gids)

# Expected strings are the words a real assemble_linear ELF held, parsed back
# out of the blob the oracle called. entry's hi:lo is struct.pack('<q', -text).
def want_nop(r1: String, prop: String) -> String:
  String.concat(["lds=0 kern=0 entry=4294967295:4294966284 r1=", r1,
    " r2=4 r3=0 prop=", prop, " text=1012 roff=1280"])


# --- THE GATE ROWS ------------------------------------------------------
def g_consts() -> IO(Unit):
  do IO<Unit>:
    urow("shift.vgpr", P.SHIFT_VGPR(), 0)
    urow("shift.sgpr", P.SHIFT_SGPR(), 6)
    urow("shift.denorm", P.SHIFT_DENORM(), 18)
    urow("shift.dx10", P.SHIFT_DX10(), 21)
    urow("shift.ieee", P.SHIFT_IEEE(), 23)
    urow("shift.mem", P.SHIFT_MEM(), 30)
    urow("shift.user", P.SHIFT_USER(), 1)
    urow("shift.gidx", P.SHIFT_GIDX(), 7)
    urow("shift.gidy", P.SHIFT_GIDY(), 8)
    urow("shift.gidz", P.SHIFT_GIDZ(), 9)
    urow("shift.kptr", P.SHIFT_KPTR(), 3)
    urow("shift.wave32", P.SHIFT_WAVE32(), 10)
    urow("shift.accum", P.SHIFT_ACCUM(), 0)
    urow("align.isa", P.AMD_ISA_ALIGN_BYTES(), 256)
    urow("align.kern", P.AMD_KERNEL_CODE_ALIGN_BYTES(), 64)
    urow("op.acc", P.OPR_ACCVGPR(), 1)
    urow("op.src_acc", P.OPR_SRC_ACCVGPR(), 21)
    urow("op.src_or", P.OPR_SRC_VGPR_OR_ACCVGPR(), 26)
    urow("op.src_or_c", P.OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST(), 27)
    urow("op.or", P.OPR_VGPR_OR_ACCVGPR(), 41)
    urow("enc.code_end", s_code_end_word(), 3214868480)
    urow("enc.nop", s_nop_cdna_word(), 3212836864)
    urow("enc.len", P.PAD_LEN(), 4)
    urow("sz.ehdr", P.EHDR_SIZE(), 64)
    urow("sz.shdr", P.SHDR_SIZE(), 64)
    urow("sz.kd", P.KD_SIZE(), 64)
    urow("sht.progbits", P.SHT_PROGBITS(), 1)
    urow("sht.strtab", P.SHT_STRTAB(), 3)
    urow("shf.alloc", P.SHF_ALLOC(), 2)
    urow("shf.exec", P.SHF_EXECINSTR(), 4)
    urow("shf.alloc_exec", P.SHF_ALLOC_EXEC(), 6)
    urow("elf.mag0", P.ELF_MAG0(), 127)
    urow("elf.mag1", P.ELF_MAG1(), 69)
    urow("elf.mag2", P.ELF_MAG2(), 76)
    urow("elf.mag3", P.ELF_MAG3(), 70)
    urow("elf.class", P.ELF_CLASS64(), 2)
    urow("elf.shnum", P.E_SHNUM(), 3)
    urow("elf.shstrndx", P.E_SHSTRNDX(), 2)
    urow("win.vgpr_lo", P.vgpr_lo(), 256)
    urow("win.vgpr_hi", P.vgpr_hi(), 512)
    urow("win.sgpr_hi", P.sgpr_hi(), 106)
    srow("strtab.names", sh_names_text(), "1,7,15")
    urow("strtab.len", P.strtab_len(), 23)
    urow("layout.text_off", P.text_off(), 256)

def g_arch() -> IO(Unit):
  do IO<Unit>:
    srow("arch.gfx900", P._arch_map("gfx900"), "cdna")
    srow("arch.gfx908", P._arch_map("gfx908"), "cdna")
    srow("arch.gfx90a", P._arch_map("gfx90a"), "cdna")
    srow("arch.gfx942", P._arch_map("gfx942"), "cdna")
    srow("arch.gfx1030", P._arch_map("gfx1030"), "rdna3")
    srow("arch.gfx1100", P._arch_map("gfx1100"), "rdna3")
    srow("arch.gfx1101", P._arch_map("gfx1101"), "rdna3")
    srow("arch.gfx1200", P._arch_map("gfx1200"), "rdna4")
    srow("arch.gfx1201", P._arch_map("gfx1201"), "rdna4")
    srow("arch.gfx8", P._arch_map("gfx8"), "")
    srow("arch.GFX1100", P._arch_map("GFX1100"), "")
    srow("arch.empty", P._arch_map(""), "")

def g_scan() -> IO(Unit):
  do IO<Unit>:
    srow("scan.empty", scan_text(fx_empty()), "0,0,0")
    srow("scan.vgpr0", scan_text(fx_vgpr0()), "1,0,0")
    srow("scan.vgpr5sz2", scan_text(fx_vgpr5()), "7,0,0")
    srow("scan.sgpr3", scan_text(fx_sgpr3()), "0,4,0")
    srow("scan.sgpr105", scan_text(fx_sgpr105()), "0,106,0")
    srow("scan.sgpr106", scan_text(fx_sgpr106()), "0,0,0")
    srow("scan.acc", scan_text(fx_acc()), "0,0,4")
    srow("scan.src_acc", scan_text(fx_src_acc()), "0,0,5")
    srow("scan.or_off", scan_text(fx_or(0)), "3,0,0")
    srow("scan.or_on", scan_text(fx_or(1)), "0,0,3")
    srow("scan.or_src", scan_text(fx_or_src()), "0,0,16")
    srow("scan.or_const", scan_text(fx_or_const()), "0,0,1")
    srow("scan.fixed", scan_text(fx_fixed()), "1,0,0")
    srow("scan.imm", scan_text(fx_imm()), "0,0,0")
    srow("scan.both", scan_text(fx_both()), "0,6,2")
    srow("scan.hi", scan_text(fx_hi()), "256,0,0")
    srow("scan.512", scan_text(fx_512()), "0,0,0")

def g_sink() -> IO(Unit):
  do IO<Unit>:
    urow("param.alu", param_size(True{}, 4), 4)
    urow("param.glob", param_size(False{}, 4), 8)
    urow("kern.sorted", P.kernarg([P.Slot{0, 4}, P.Slot{1, 1}, P.Slot{2, 8}]), 16)
    urow("kern.unsorted", P.kernarg([P.Slot{2, 8}, P.Slot{0, 4}, P.Slot{1, 1}]), 16)
    # The one row that can tell a correct sort from a wrong one. Both rows
    # above fold to 16 whether the comparison is `<` or `>=`, so neither can
    # see `insert`'s comparison at all; here key order (0 then 1) is the
    # REVERSE of the fixture's list order, and the two folds differ.
    # Called: `.venv/bin/python .agents/slop/elf_amd_sort.py` -- kernarg 9,
    # and 16 with the sort dropped, and 16 again with the comparison flipped.
    urow("kern.keyorder", P.kernarg([P.Slot{1, 1}, P.Slot{0, 8}]), 9)
    urow("kern.empty", P.kernarg(none_p()), 0)
    urow("lds.one", P.lds_sum([P.Lds{8, 4}]), 32)
    urow("lds.two", P.lds_sum([P.Lds{8, 4}, P.Lds{15, 2}]), 62)
    urow("lds.none", P.lds_sum(none_l()), 0)
    row("gid.x", P.Gids.x(P.gids_of(["gidx0"])))
    row("gid.y", P.Gids.y(P.gids_of(["gidx1"])))
    row("gid.z", P.Gids.z(P.gids_of(["gidx2"])))
    row("gid.ten_is_x", P.Gids.x(P.gids_of(["gidx10"])))
    row("gid.ten_not_y", Bool.not(P.Gids.y(P.gids_of(["gidx10"]))))
    row("gid.local_skip", Bool.not(P.Gids.x(P.gids_of(["lidx0"]))))
    row("gid.nine_no_bit", Bool.not(Bool.or(P.Gids.x(P.gids_of(["gidx9"])), Bool.or(P.Gids.y(P.gids_of(["gidx9"])), P.Gids.z(P.gids_of(["gidx9"]))))))
    row("gid.bad", P.Gids.bad(P.gids_of(["gidx"])))
    row("gid.ok", Bool.not(P.Gids.bad(P.gids_of(["gidx0"]))))

def g_pack() -> IO(Unit):
  do IO<Unit>:
    srow("elf.rdna3", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), none_g()),
      want_nop("1085014016", "1032"))
    srow("elf.rdna4", pack("gfx1200", fx_empty(), 4, none_l(), none_p(), none_g()),
      want_nop("1074528256", "1032"))
    srow("elf.cdna", pack("gfx900", fx_empty(), 4, none_l(), none_p(), none_g()),
      want_nop("11272192", "8"))
    srow("elf.v16", pack("gfx1100", [vmov(16, 20)], 4, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1085014018 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.cdna_v16", pack("gfx908", [vmov(16, 20)], 4, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=11272386 r2=4 r3=0 prop=8 text=1012 roff=1280")
    srow("elf.acc0", pack("gfx90a", [accmov(0, 0)], 4, none_l(), none_p(), none_g()),
      want_nop("11272192", "8"))
    srow("elf.acc_v8", pack("gfx90a", [vmov(8, 0), accmov(0, 0)], 8, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966296 r1=11272257 r2=4 r3=2 prop=8 text=1000 roff=1280")
    srow("elf.v8", pack("gfx90a", [vmov(8, 0)], 4, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=11272257 r2=4 r3=0 prop=8 text=1012 roff=1280")
    srow("elf.acc_v4", pack("gfx90a", [vmov(4, 0), accmov(7, 0)], 8, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966296 r1=11272257 r2=4 r3=1 prop=8 text=1000 roff=1280")
    srow("elf.v4", pack("gfx90a", [vmov(4, 0)], 4, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=11272256 r2=4 r3=0 prop=8 text=1012 roff=1280")
    srow("elf.lds", pack("gfx1100", fx_empty(), 4, [P.Lds{8, 4}], none_p(), none_g()),
      "lds=32 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.lds2", pack("gfx1100", fx_empty(), 4, [P.Lds{8, 4}, P.Lds{15, 2}], none_p(), none_g()),
      "lds=62 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.kern", pack("gfx1100", fx_empty(), 4, none_l(), [P.Slot{2, 8}, P.Slot{0, 4}, P.Slot{1, 1}], none_g()),
      "lds=0 kern=16 entry=4294967295:4294966284 r1=1085014016 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.gidx", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx0"]),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=132 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.gidy", pack("gfx1200", fx_empty(), 4, none_l(), none_p(), ["gidx1"]),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1074528256 r2=260 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.gidz", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx2"]),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=516 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.gidxz", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx0", "gidx2"]),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=644 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.gidx10", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx10"]),
      "lds=0 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=132 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.lidx", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["lidx0"]),
      want_nop("1085014016", "1032"))
    srow("elf.gidx9", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx9"]),
      want_nop("1085014016", "1032"))
    srow("elf.three", pack("gfx1100", fx_empty(), 12, none_l(), none_p(), none_g()),
      "lds=0 kern=0 entry=4294967295:4294966308 r1=1085014016 r2=4 r3=0 prop=1032 text=988 roff=1280")
    srow("elf.miss", pack("gfx8", fx_empty(), 4, none_l(), none_p(), none_g()), "REFUSAL:StopIteration")
    srow("elf.badgid", pack("gfx1100", fx_empty(), 4, none_l(), none_p(), ["gidx"]), "REFUSAL:ValueError")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- g_consts()
    b : Unit <- g_arch()
    c : Unit <- g_scan()
    d : Unit <- g_sink()
    e : Unit <- g_pack()
    IO.print("elf-done=1")
