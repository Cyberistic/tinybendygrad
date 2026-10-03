# tinybendygrad/renderer/amd/elf.bend -- port of tinygrad/renderer/amd/elf.py
#
# THE PACKER. 111 lines, one function. It scans a linearized instruction list
# for register occupancy, walks the sink for kernarg / LDS / workgroup ids,
# pads the text, and writes an ELF whose rodata is an AMD kernel descriptor.
#
# THE SPLIT. A def here builds the argument of the pack (pure; the gate checks
# it). There is no trace and no `@extern`. `Reg` and `FixedBitField` are
# `D.Rg` and `D.K_FIXED` from `dsl.bend` -- reused, not reimplemented.
#
# ===========================================================================
# WHAT IS NOT PORTED, AND THE SPECIFIC BLOCKER FOR EACH.
#
#   elf.py:16   `insts = [u.arg[0] for u in lin.src]`
#               BLOCKER: `lin` is a UOp whose `arg[0]` is an autogen `Inst`
#               (`runtime/autogen/amd/{rdna3,rdna4,cdna}/ins.py`). The scan
#               below runs on an explicit field list; the UOp-to-Inst
#               extraction is that generated table.
#   elf.py:38-42  the sink `toposort`
#               BLOCKER: `u.addrspace` is `ops.py:910`, still
#               `TODO(p3)` in `uop/ops.bend:3718`. `u.dtype.itemsize` is
#               `Dt.itemsize` in `LAWS/spec.bend:176`, not a UOp method.
#               `u.max_numel` is `mixin/movement.py:55` (`prod(max_shape)`),
#               not a def in `movement.bend`. `AddrSpace` itself EXISTS as
#               `S.Addr` (`Aalu`/`ALocal`/`AGlobal`/`AReg`) in
#               `LAWS/spec.bend:79`. Adding the three missing UOp methods to
#               `uop/ops.bend` is not local: 56 importers, measured before
#               this file was written (ops.bend 4977 lines / 509 defs,
#               spec.bend 3317 / 583, ops_metal.bend 4045 / 466, among
#               others). Not landed.
#               The ARITHMETIC each arm does is ported: `param_size` is the
#               `itemsize if ALU else 8` choice, `lds_sum` is
#               `numel * itemsize`, `gid_of` is `startswith("gidx")` plus
#               `int(arg[-1])`. The walk that feeds them is the blocker.
#   elf.py:43   `inst.to_bytes()`
#               BLOCKER: the autogen encoder (`dsl.py:416`). The two padding
#               encodings are constants, called out of CPython, not a general
#               encoder. `code_len` is therefore a parameter.
#   elf.py:103-109  the `bytearray` splice
#               The offsets, sizes and header fields the splice WRITES are
#               ported and gated against a real `assemble_linear` ELF. The
#               mutable buffer itself is not a Bend value. A wrong offset is
#               a wrong section, and that is what the `roff` / `text` rows see.
#
# TODO(p3) elf.py:16,38-42,43,103-109  the four blockers above.
#
# ===========================================================================
# A MEASURED UPSTREAM FACT, because it looks like a bug and it is not one
# to "fix". elf.py:49 is
#
#   text = code_bytes + padding_inst * ((ALIGN - len(code) % ALIGN) % ALIGN)
#
# `padding_inst` is 4 bytes (`s_code_end().to_bytes()` and `s_nop_cdna(0)`
# both, called). `bytes * n` repeats the string n times, so one instruction
# pads to text size 1012, not 256. A real `assemble_linear` call on gfx1100
# with one `s_code_end` returned section 0 size 1012 and entry -1012
# (`.agents/slop/elf_amd_oracle.py`). The gate expects 1012. An "alignment
# fix" that pads by n bytes moves `text` and `roff`.
#
# gfx10 and gfx11 both map to "rdna3" (elf.py:14, called). Swapping those
# two keys moves no row. Reported, not papered over.

import Base
import ../../helpers.bend as H
import ./dsl.bend as D

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(String.eq(got, want))]))
def urow(nm: String, got: U32, want: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(U32.is_eq(got, want))]))

# ===========================================================================
# CONSTANTS. Every literal below was printed by
# `.venv/bin/python .agents/slop/elf_amd_oracle.py`, which calls getattr /
# `.value` / `.to_bytes()` / `ctypes.sizeof`. Not transcribed from a comment.
#
# The shifts live in `tinygrad/runtime/autogen/amdgpu_kd.py`, a generated
# ctypes binding of the LLVM AMDGPU kernel-descriptor header (the
# `register_fields` call at amdgpu_kd.py:36 and the walrus enums at :12-16).
# There is no hand-written Python definition of the shift amounts. The
# citation is the generated binding, which is the definition site in this
# repo. hsa.py:1104-1105 and libc.py are the same kind of generated binding.
# ===========================================================================

# amdgpu_kd.py, getattr. elf.py:67-80.
def SHIFT_VGPR() -> U32: 0      # COMPUTE_PGM_RSRC1_GRANULATED_WORKITEM_VGPR_COUNT_SHIFT
def SHIFT_SGPR() -> U32: 6      # COMPUTE_PGM_RSRC1_GRANULATED_WAVEFRONT_SGPR_COUNT_SHIFT
def SHIFT_DENORM() -> U32: 18   # COMPUTE_PGM_RSRC1_FLOAT_DENORM_MODE_16_64_SHIFT
def SHIFT_DX10() -> U32: 21     # COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_DX10_CLAMP_SHIFT
def SHIFT_IEEE() -> U32: 23     # COMPUTE_PGM_RSRC1_GFX6_GFX11_ENABLE_IEEE_MODE_SHIFT
def SHIFT_MEM() -> U32: 30      # COMPUTE_PGM_RSRC1_GFX10_PLUS_MEM_ORDERED_SHIFT
def SHIFT_USER() -> U32: 1      # COMPUTE_PGM_RSRC2_USER_SGPR_COUNT_SHIFT
def SHIFT_GIDX() -> U32: 7      # COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_X_SHIFT
def SHIFT_GIDY() -> U32: 8      # COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Y_SHIFT
def SHIFT_GIDZ() -> U32: 9      # COMPUTE_PGM_RSRC2_ENABLE_SGPR_WORKGROUP_ID_Z_SHIFT
def SHIFT_KPTR() -> U32: 3      # KERNEL_CODE_PROPERTY_ENABLE_SGPR_KERNARG_SEGMENT_PTR_SHIFT
def SHIFT_WAVE32() -> U32: 10   # KERNEL_CODE_PROPERTY_ENABLE_WAVEFRONT_SIZE32_SHIFT
def SHIFT_ACCUM() -> U32: 0     # COMPUTE_PGM_RSRC3_GFX90A_ACCUM_OFFSET_SHIFT

# hsa.py:1104-1105, called. elf.py:49-50, :90.
def AMD_ISA_ALIGN_BYTES() -> U32: 256
def AMD_KERNEL_CODE_ALIGN_BYTES() -> U32: 64

# OpType.auto() values, `.value` called. common.py lines are the declaration
# site; the NUMBER is the enum ordinal, which a line count can get wrong.
# elf.py:20, :26.
def OPR_ACCVGPR() -> U32: 1                          # common.py:278
def OPR_SRC_ACCVGPR() -> U32: 21                     # common.py:298
def OPR_SRC_VGPR_OR_ACCVGPR() -> U32: 26             # common.py:303
def OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST() -> U32: 27    # common.py:304
def OPR_VGPR_OR_ACCVGPR() -> U32: 41                 # common.py:318

# int.from_bytes(inst().to_bytes(), 'little'), called.
# rdna3/ins.py:1144 s_code_end; cdna/ins.py s_nop. elf.py:11-12, :48.
# Both are 4 bytes: [0, 0, 159, 191] and [0, 0, 128, 191].
def s_code_end_word() -> U32: 3214868480
def s_nop_cdna_word() -> U32: 3212836864
def PAD_LEN() -> U32: 4

# ctypes.sizeof, called. elf.py:50, :103. libc.py Elf64_Ehdr.SIZE / Elf64_Shdr.SIZE,
# amdgpu_kd.py:20 llvm_amdhsa_kernel_descriptor_t.SIZE. All three are 64.
def EHDR_SIZE() -> U32: 64
def SHDR_SIZE() -> U32: 64
def KD_SIZE() -> U32: 64

# libc.py, called. elf.py:94-96.
def SHT_PROGBITS() -> U32: 1
def SHT_STRTAB() -> U32: 3
def SHF_ALLOC() -> U32: 2
def SHF_EXECINSTR() -> U32: 4
def SHF_ALLOC_EXEC() -> U32: 6    # SHF_ALLOC | SHF_EXECINSTR, elf.py:94

# elf.py:101. e_ident[:5] = b"\x7FELF\x02", e_shnum = len(sections) = 3,
# e_shstrndx = 2. Called: a real ELF began 7f454c4602 and had shnum 3, shstrndx 2.
def ELF_MAG0() -> U32: 127
def ELF_MAG1() -> U32: 69
def ELF_MAG2() -> U32: 76
def ELF_MAG3() -> U32: 70
def ELF_CLASS64() -> U32: 2
def E_SHNUM() -> U32: 3
def E_SHSTRNDX() -> U32: 2

# elf.py:32-35, the register windows. The same numbers are dsl.py:47 (`256 <= o
# < 512`) and dsl.py:50 (`o < 106`), and dsl.bend already names them. The scan
# reads those defs so a drifted window is one drift, and the gate checks the
# defs against the literals the CPython scan used.
def vgpr_lo() -> U32: D.V_LO()
def vgpr_hi() -> U32: U32.add(D.V_HI(), 1)
def sgpr_hi() -> U32: U32.add(D.S_HI(), 1)

def bit(v: U32, sh: U32) -> U32: U32.shln(v, U32.to_nat(sh))
def flag(on: Bool) -> U32: Bool.to_u32(on)

# `max(0, q - 1)` without the U32 wrap. `U32.sub(0, 1)` is 4294967295, and
# `U32.max` of that is the wrapped value, not 0. elf.py:57, :59, :80.
def sub1.go(z: Bool, q: U32) -> U32:
  match z:
    case True{}: 0
    case False{}: U32.sub(q, 1)
def sub1(+q: U32) -> U32: sub1.go(U32.is_lt(q, 1), q)

# ===========================================================================
# _arch_map, elf.py:14. Insertion order, which is the order `next` walks.
# A miss is "" -- Python's `next` raises StopIteration, and assemble_linear
# turns that into the refusal string rather than a descriptor.
# ===========================================================================

def arch_pick12(a12: Bool) -> String:
  match a12:
    case True{}: "rdna4"
    case False{}: ""
def arch_pick11(a11: Bool, a12: Bool) -> String:
  match a11:
    case True{}: "rdna3"
    case False{}: arch_pick12(a12)
def arch_pick10(a10: Bool, a11: Bool, a12: Bool) -> String:
  match a10:
    case True{}: "rdna3"
    case False{}: arch_pick11(a11, a12)
def arch_pick9(a9: Bool, a10: Bool, a11: Bool, a12: Bool) -> String:
  match a9:
    case True{}: "cdna"
    case False{}: arch_pick10(a10, a11, a12)
def _arch_map(+arch: String) -> String:
  arch_pick9(String.starts_with(arch, "gfx9"), String.starts_with(arch, "gfx10"),
    String.starts_with(arch, "gfx11"), String.starts_with(arch, "gfx12"))
def is_cdna(arch: String) -> Bool: String.eq(_arch_map(arch), "cdna")
def is_rdna4(arch: String) -> Bool: String.eq(_arch_map(arch), "rdna4")
def arch_hit(arch: String) -> Bool: Bool.not(String.eq(_arch_map(arch), ""))

# ===========================================================================
# THE REGISTER SCAN, elf.py:18-35. An instruction is the three things the
# loop reads: `operands` (name, OpType), `_fields` (name, field class, value),
# and `acc_cd`. `D.Rg` is the value when the value is a Reg. `D.K_FIXED` is
# the FixedBitField the loop skips.
# ===========================================================================

type Opr is Data:
  Opr{name: String, otype: U32}
def Opr.name(o: Opr) -> String:
  match o:
    case Opr{name, otype}: name
def Opr.otype(o: Opr) -> U32:
  match o:
    case Opr{name, otype}: otype

type Use is Data:
  Use{name: String, kind: U32, is_reg: Bool, reg: D.Rg}
def Use.name(u: Use) -> String:
  match u:
    case Use{name, kind, is_reg, reg}: name
def Use.kind(u: Use) -> U32:
  match u:
    case Use{name, kind, is_reg, reg}: kind
def Use.is_reg(u: Use) -> Bool:
  match u:
    case Use{name, kind, is_reg, reg}: is_reg
def Use.reg(u: Use) -> D.Rg:
  match u:
    case Use{name, kind, is_reg, reg}: reg

type Ins is Data:
  Ins{oprs: List<&2, Opr>, fields: List<&2, Use>, acc_cd: U32}
def Ins.oprs(i: Ins) -> List<&2, Opr>:
  match i:
    case Ins{oprs, fields, acc_cd}: oprs
def Ins.fields(i: Ins) -> List<&2, Use>:
  match i:
    case Ins{oprs, fields, acc_cd}: fields
def Ins.acc_cd(i: Ins) -> U32:
  match i:
    case Ins{oprs, fields, acc_cd}: acc_cd

type Mx is Data:
  Mx{v: U32, s: U32, a: U32}
def Mx.v(m: Mx) -> U32:
  match m:
    case Mx{v, s, a}: v
def Mx.s(m: Mx) -> U32:
  match m:
    case Mx{v, s, a}: s
def Mx.a(m: Mx) -> U32:
  match m:
    case Mx{v, s, a}: a
def Mx.zero() -> Mx: Mx{0, 0, 0}
def Mx.text(m: Mx) -> String:
  String.concat([U32.show(Mx.v(m)), ",", U32.show(Mx.s(m)), ",", U32.show(Mx.a(m))])

def is_acc_t(t: U32) -> Bool:
  Bool.or(U32.is_eq(t, OPR_ACCVGPR()), U32.is_eq(t, OPR_SRC_ACCVGPR()))
def is_or_t(t: U32) -> Bool:
  Bool.or(U32.is_eq(t, OPR_VGPR_OR_ACCVGPR()),
    Bool.or(U32.is_eq(t, OPR_SRC_VGPR_OR_ACCVGPR()), U32.is_eq(t, OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST())))
def take_acc(+o: Opr, acc_cd: U32) -> Bool:
  Bool.or(is_acc_t(Opr.otype(o)), Bool.and(is_or_t(Opr.otype(o)), U32.is_eq(acc_cd, 1)))

def acc_cons(yes: Bool, name: String, acc: List<&2, String>) -> List<&2, String>:
  match yes:
    case True{}: List.append(&2, String, [name], acc)
    case False{}: acc
def acc_go(oprs: List<&2, Opr>, acc_cd: U32, acc: List<&2, String>) -> List<&2, String>:
  match oprs:
    case Nil{}: acc
    case h <> t: acc_go(t, acc_cd, acc_cons(take_acc(h, acc_cd), Opr.name(h), acc))
def acc_names(oprs: List<&2, Opr>, acc_cd: U32) -> List<&2, String>:
  acc_go(oprs, acc_cd, Nil{})

def has_name(ns: List<&2, String>, +want: String) -> Bool:
  match ns:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(h, want), has_name(t, want))

def in_vgpr(off: U32) -> Bool:
  Bool.and(Bool.not(U32.is_lt(off, vgpr_lo())), U32.is_lt(off, vgpr_hi()))
def in_sgpr(off: U32) -> Bool: U32.is_lt(off, sgpr_hi())

def apply_v.go(acc: Bool, idx: U32, +m: Mx) -> Mx:
  match acc:
    case True{}: Mx{Mx.v(m), Mx.s(m), U32.max(Mx.a(m), idx)}
    case False{}: Mx{U32.max(Mx.v(m), idx), Mx.s(m), Mx.a(m)}
def apply_v(acc: Bool, off: U32, sz: U32, m: Mx) -> Mx:
  apply_v.go(acc, U32.add(U32.sub(off, vgpr_lo()), sz), m)
def apply_s(sg: Bool, off: U32, sz: U32, +m: Mx) -> Mx:
  match sg:
    case False{}: m
    case True{}: Mx{Mx.v(m), U32.max(Mx.s(m), U32.add(off, sz)), Mx.a(m)}
def apply_which(vg: Bool, sg: Bool, off: U32, sz: U32, name: String, names: List<&2, String>, m: Mx) -> Mx:
  match vg:
    case True{}: apply_v(has_name(names, name), off, sz, m)
    case False{}: apply_s(sg, off, sz, m)
def apply_off(off: U32, sz: U32, name: String, names: List<&2, String>, m: Mx) -> Mx:
  apply_which(in_vgpr(off), in_sgpr(off), off, sz, name, names, m)
def apply_reg(reg: Bool, +u: Use, names: List<&2, String>, m: Mx) -> Mx:
  match reg:
    case False{}: m
    case True{}: apply_off(D.Rg.off(Use.reg(u)), D.Rg.sz(Use.reg(u)), Use.name(u), names, m)
def apply_fixed(fix: Bool, +u: Use, names: List<&2, String>, m: Mx) -> Mx:
  match fix:
    case True{}: m
    case False{}: apply_reg(Use.is_reg(u), u, names, m)
def apply_use(+u: Use, names: List<&2, String>, m: Mx) -> Mx:
  apply_fixed(U32.is_eq(Use.kind(u), D.K_FIXED()), u, names, m)

def scan_fields(fs: List<&2, Use>, names: List<&2, String>, m: Mx) -> Mx:
  match fs:
    case Nil{}: m
    case h <> t: scan_fields(t, names, apply_use(h, names, m))
def scan_one(+i: Ins, m: Mx) -> Mx:
  scan_fields(Ins.fields(i), acc_names(Ins.oprs(i), Ins.acc_cd(i)), m)
def scan_go(xs: List<&2, Ins>, m: Mx) -> Mx:
  match xs:
    case Nil{}: m
    case h <> t: scan_go(t, scan_one(h, m))
def scan(xs: List<&2, Ins>) -> Mx: scan_go(xs, Mx.zero())
def scan_text(xs: List<&2, Ins>) -> String: Mx.text(scan(xs))

# ===========================================================================
# SINK ARITHMETIC, elf.py:40-42. The walk is the blocker named above. These
# are the three arms, given the values the walk would have read.
# ===========================================================================

# `u.dtype.itemsize if u.addrspace is AddrSpace.ALU else 8`. GLOBAL's itemsize
# is NOT what lands in kernarg: a float32 global is 4 bytes and the else arm
# writes 8. Called: slots (0, ALU, 4), (1, ALU, 1), (2, GLOBAL, 4) packed to
# kernarg 16, which is the sorted fold of [4, 1, 8], not [4, 1, 4].
def param_size(alu: Bool, item: U32) -> U32: Bool.pick(U32, alu, item, 8)

type Slot is Data:
  Slot{slot: U32, sz: U32}
def Slot.slot(p: Slot) -> U32:
  match p:
    case Slot{slot, sz}: slot
def Slot.sz(p: Slot) -> U32:
  match p:
    case Slot{slot, sz}: sz

def insert.go(lt: Bool, p: Slot, h: Slot, t: List<&2, Slot>) -> List<&2, Slot>:
  match lt:
    case True{}: List.append(&2, Slot, [p], List.append(&2, Slot, [h], t))
    case False{}: List.append(&2, Slot, [h], insert(p, t))
def insert(p: Slot, xs: List<&2, Slot>) -> List<&2, Slot>:
  match xs:
    case Nil{}: [p]
    case h <> t: insert.go(U32.is_lt(Slot.slot(p), Slot.slot(h)), p, h, t)
def sort_go(xs: List<&2, Slot>, acc: List<&2, Slot>) -> List<&2, Slot>:
  match xs:
    case Nil{}: acc
    case h <> t: sort_go(t, insert(h, acc))
def sort_pairs(xs: List<&2, Slot>) -> List<&2, Slot>: sort_go(xs, Nil{})

# elf.py:62, in sorted slot order. Unsorted (2, 8), (0, 4), (1, 1) is 13 if
# the sort is dropped and 16 if it is kept. The real ELF said 16.
def kernarg_go(xs: List<&2, Slot>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case +h <> t: kernarg_go(t, U32.add(H.round_up_u32(acc, Slot.sz(h)), Slot.sz(h)))
def kernarg(xs: List<&2, Slot>) -> U32: kernarg_go(sort_pairs(xs), 0)

# elf.py:41. `lds_size += u.max_numel() * u.dtype.itemsize`.
type Lds is Data:
  Lds{numel: U32, item: U32}
def Lds.numel(x: Lds) -> U32:
  match x:
    case Lds{numel, item}: numel
def Lds.item(x: Lds) -> U32:
  match x:
    case Lds{numel, item}: item
def lds_go(xs: List<&2, Lds>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: lds_go(t, U32.add(acc, U32.mul(Lds.numel(h), Lds.item(h))))
def lds_sum(xs: List<&2, Lds>) -> U32: lds_go(xs, 0)

# elf.py:42. `u.arg.startswith("gidx")` then `int(u.arg[-1])`.
# Called: "gidx10" sets bit X (last char is '0', not 10). "lidx0" sets
# nothing. "gidx9" parses as 9 and sets no bit. "gidx" raises ValueError
# because 'x' is not a digit -- that is `bad`, not a zero.
def last_ch(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 0
    case h <> _: Char.to_u32(h)
def last_cp.go(empty: Bool, +s: String, n: U32) -> U32:
  match empty:
    case True{}: 0
    case False{}: last_ch(String.to_list(String.take(String.drop(s, U32.to_nat(U32.sub(n, 1))), 1n)))
def last_cp(+s: String) -> U32:
  last_cp.go(U32.is_lt(U32.from_nat(String.length(s)), 1), s, U32.from_nat(String.length(s)))
def is_digit(cp: U32) -> Bool:
  Bool.and(Bool.not(U32.is_lt(cp, 48)), Bool.not(U32.is_lt(57, cp)))

type Gids is Data:
  Gids{bad: Bool, x: Bool, y: Bool, z: Bool}
def Gids.bad(g: Gids) -> Bool:
  match g:
    case Gids{bad, x, y, z}: bad
def Gids.x(g: Gids) -> Bool:
  match g:
    case Gids{bad, x, y, z}: x
def Gids.y(g: Gids) -> Bool:
  match g:
    case Gids{bad, x, y, z}: y
def Gids.z(g: Gids) -> Bool:
  match g:
    case Gids{bad, x, y, z}: z
def Gids.zero() -> Gids: Gids{False{}, False{}, False{}, False{}}

def gid_set(n: U32, +g: Gids) -> Gids:
  Gids{False{}, Bool.or(Gids.x(g), U32.is_eq(n, 0)),
    Bool.or(Gids.y(g), U32.is_eq(n, 1)), Bool.or(Gids.z(g), U32.is_eq(n, 2))}
def gid_one(prefix: Bool, dig: Bool, n: U32, +g: Gids) -> Gids:
  match prefix:
    case False{}: g
    case True{}:
      match dig:
        case False{}: Gids{True{}, Gids.x(g), Gids.y(g), Gids.z(g)}
        case True{}: gid_set(n, g)
def gid_add(+s: String, g: Gids) -> Gids:
  gid_one(String.starts_with(s, "gidx"), is_digit(last_cp(s)), U32.sub(last_cp(s), 48), g)
def gid_go(ss: List<&2, String>, g: Gids) -> Gids:
  match ss:
    case Nil{}: g
    case h <> t: gid_go(t, gid_add(h, g))
def gids_of(ss: List<&2, String>) -> Gids: gid_go(ss, Gids.zero())

# ===========================================================================
# PADDING AND LAYOUT, elf.py:44-50, :84-96.
# text = code_len + PAD_LEN * ((ALIGN - code_len % ALIGN) % ALIGN)
# -- the bytes*n formula, not a byte pad. See the header.
# ===========================================================================

def pad_n(code_len: U32) -> U32:
  U32.mod(U32.sub(AMD_ISA_ALIGN_BYTES(), U32.mod(code_len, AMD_ISA_ALIGN_BYTES())), AMD_ISA_ALIGN_BYTES())
def text_len(+code_len: U32) -> U32:
  U32.add(code_len, U32.mul(PAD_LEN(), pad_n(code_len)))
def text_off() -> U32: H.round_up_u32(EHDR_SIZE(), AMD_ISA_ALIGN_BYTES())
def roff(text: U32) -> U32:
  H.round_up_u32(U32.add(text_off(), text), AMD_KERNEL_CODE_ALIGN_BYTES())
def strtab_off(text: U32) -> U32: U32.add(roff(text), KD_SIZE())

# elf.py:85-88. strtab starts with one NUL; each name is ascii plus a NUL.
# Called: sh_names [1, 7, 15], strtab length 23.
# elf.py:86's list is three literals. Each step is `at + len(name) + 1`, starting
# at 1 because the strtab opens with a NUL. Unrolled: a recursive walk of a
# 3-element literal is the same arithmetic and a nested match on the index is
# the thing Bend refuses here.
def sh_step(at: U32, name: String) -> U32:
  U32.add(U32.add(at, U32.from_nat(String.length(name))), 1)
def sh_name0() -> U32: 1
def sh_name1() -> U32: sh_step(sh_name0(), ".text")
def sh_name2() -> U32: sh_step(sh_name1(), ".rodata")
def strtab_len() -> U32: sh_step(sh_name2(), ".strtab")
def sh_names_text() -> String:
  String.concat([U32.show(sh_name0()), ",", U32.show(sh_name1()), ",", U32.show(sh_name2())])

def shdr_off(text: U32) -> U32: U32.add(strtab_off(text), strtab_len())

# entry = -len(text), an int64. helpers.i64_sub of 0 is the two's complement.
# Called: -1012 is lo 4294966284 hi 4294967295.
def entry_of(text: U32) -> H.I64:
  H.i64_sub(H.i64_of_hi_lo(0, 0), H.i64_of_i32(text))

# ===========================================================================
# THE DESCRIPTOR WORDS, elf.py:53-80.
# ===========================================================================

def accum_off(has: Bool, max_v: U32) -> U32:
  match has:
    case False{}: 0
    case True{}: H.round_up_u32(max_v, 4)
def next_vgpr.go(has: Bool, max_v: U32, max_a: U32, accum: U32) -> U32:
  match has:
    case True{}: H.round_up_u32(U32.add(accum, max_a), 8)
    case False{}: H.round_up_u32(max_v, 8)
def next_vgpr(+has: Bool, +max_v: U32, max_a: U32) -> U32:
  next_vgpr.go(has, max_v, max_a, accum_off(has, max_v))
def next_sgpr(max_s: U32) -> U32: H.round_up_u32(max_s, 8)
def vgpr_gran(next: U32) -> U32: sub1(U32.div(U32.add(next, 7), 8))
def sgpr_gran(cdna: Bool, next: U32) -> U32:
  match cdna:
    case False{}: 0
    case True{}: sub1(H.ceildiv_u32(U32.add(next, 6), 8))

def rsrc1(vg: U32, sg: U32, +rdna4: Bool, cdna: Bool) -> U32:
  U32.or(bit(vg, SHIFT_VGPR()),
    U32.or(bit(sg, SHIFT_SGPR()),
      U32.or(bit(3, SHIFT_DENORM()),
        U32.or(bit(flag(Bool.not(rdna4)), SHIFT_DX10()),
          U32.or(bit(flag(Bool.not(rdna4)), SHIFT_IEEE()),
            bit(flag(Bool.not(cdna)), SHIFT_MEM()))))))
def rsrc2(x: Bool, y: Bool, z: Bool) -> U32:
  U32.or(bit(2, SHIFT_USER()),
    U32.or(bit(flag(x), SHIFT_GIDX()),
      U32.or(bit(flag(y), SHIFT_GIDY()), bit(flag(z), SHIFT_GIDZ()))))
def kprop(cdna: Bool) -> U32:
  U32.or(bit(1, SHIFT_KPTR()), bit(flag(Bool.not(cdna)), SHIFT_WAVE32()))
def rsrc3(on: Bool, max_v: U32) -> U32:
  match on:
    case False{}: 0
    case True{}: bit(sub1(U32.div(accum_off(True{}, max_v), 4)), SHIFT_ACCUM())

# ===========================================================================
# assemble_linear, elf.py:15. The UOp walk and the byte buffer are the
# blockers in the header. Everything from the scan through the header fields
# is this def. A miss on `_arch_map` is Python's StopIteration. A `gidx`
# whose last character is not a digit is Python's ValueError.
# ===========================================================================

def asm_text(+arch: String, +m: Mx, text: U32, lds: U32, kern: U32, +g: Gids) -> String:
  String.concat(["lds=", U32.show(lds), " kern=", U32.show(kern),
    " entry=", H.i64_text(entry_of(text)),
    " r1=", U32.show(rsrc1(vgpr_gran(next_vgpr(U32.is_lt(0, Mx.a(m)), Mx.v(m), Mx.a(m))),
      sgpr_gran(is_cdna(arch), next_sgpr(Mx.s(m))), is_rdna4(arch), is_cdna(arch))),
    " r2=", U32.show(rsrc2(Gids.x(g), Gids.y(g), Gids.z(g))),
    " r3=", U32.show(rsrc3(Bool.and(is_cdna(arch), U32.is_lt(0, Mx.a(m))), Mx.v(m))),
    " prop=", U32.show(kprop(is_cdna(arch))),
    " text=", U32.show(text), " roff=", U32.show(roff(text))])

def asm_go(hit: Bool, bad: Bool, arch: String, m: Mx, text: U32, lds: U32, kern: U32, g: Gids) -> String:
  match hit:
    case False{}: "REFUSAL:StopIteration"
    case True{}:
      match bad:
        case True{}: "REFUSAL:ValueError"
        case False{}: asm_text(arch, m, text, lds, kern, g)

def assemble_linear(arch: String, insts: List<&2, Ins>, code_len: U32,
    locs: List<&2, Lds>, params: List<&2, Slot>, gid_args: List<&2, String>) -> String:
  asm_go(arch_hit(arch), Gids.bad(gids_of(gid_args)), arch, scan(insts), text_len(code_len),
    lds_sum(locs), kernarg(params), gids_of(gid_args))

# ===========================================================================
# FIXTURE BUILDERS. The shapes are the instructions the oracle constructed
# with the real Reg / FixedBitField / OpType, and the real v_mov / accvgpr
# the ELF rows were packed from.
# ===========================================================================

def rg(off: U32, sz: U32) -> D.Rg: D.Rg{off, sz, False{}, False{}, False{}}
def ureg(nm: String, off: U32, sz: U32) -> Use: Use{nm, D.K_PLAIN(), True{}, rg(off, sz)}
def ufix(nm: String, off: U32, sz: U32) -> Use: Use{nm, D.K_FIXED(), True{}, rg(off, sz)}
def uimm(nm: String) -> Use: Use{nm, D.K_PLAIN(), False{}, rg(0, 1)}
def ins_of(oprs: List<&2, Opr>, fields: List<&2, Use>, cd: U32) -> Ins: Ins{oprs, fields, cd}

# v_mov_b32_e32(v[i], s[j]): vdst is a VGPR Reg, src0 is an SGPR Reg, encoding
# is a FixedBitField the scan skips. Operand types are not acc types.
def vmov(vi: U32, sj: U32) -> Ins:
  ins_of(Nil{}, [ufix("encoding", 0, 1), ureg("vdst", U32.add(256, vi), 1), ureg("src0", sj, 1)], 0)
# v_accvgpr_mov_b32_e32(v[d], v[s]): both operands are acc types. Called.
def accmov(d: U32, s0: U32) -> Ins:
  ins_of([Opr{"vdst", OPR_ACCVGPR()}, Opr{"src0", OPR_SRC_ACCVGPR()}],
    [ufix("encoding", 0, 1), ureg("vdst", U32.add(256, d), 1), ureg("src0", U32.add(256, s0), 1)], 0)

def fx_empty() -> List<&2, Ins>: Nil{}
def fx_vgpr0() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("vdst", 256, 1)], 0)]
def fx_vgpr5() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("vdst", 261, 2)], 0)]
def fx_sgpr3() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("sdst", 3, 1)], 0)]
def fx_sgpr105() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("sdst", 105, 1)], 0)]
def fx_sgpr106() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("sdst", 106, 1)], 0)]
def fx_acc() -> List<&2, Ins>:
  [ins_of([Opr{"vdst", OPR_ACCVGPR()}], [ureg("vdst", 256, 4)], 0)]
def fx_src_acc() -> List<&2, Ins>:
  [ins_of([Opr{"src0", OPR_SRC_ACCVGPR()}], [ureg("src0", 260, 1)], 0)]
def fx_or(cd: U32) -> List<&2, Ins>:
  [ins_of([Opr{"vdst", OPR_VGPR_OR_ACCVGPR()}], [ureg("vdst", 258, 1)], cd)]
def fx_or_src() -> List<&2, Ins>:
  [ins_of([Opr{"src0", OPR_SRC_VGPR_OR_ACCVGPR()}], [ureg("src0", 270, 2)], 1)]
def fx_or_const() -> List<&2, Ins>:
  [ins_of([Opr{"src0", OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST()}], [ureg("src0", 256, 1)], 1)]
def fx_fixed() -> List<&2, Ins>:
  [ins_of(Nil{}, [ufix("enc", 256, 8), ureg("vdst", 256, 1)], 0)]
def fx_imm() -> List<&2, Ins>: [ins_of(Nil{}, [uimm("imm")], 0)]
def fx_both() -> List<&2, Ins>:
  [ins_of([Opr{"vdst", OPR_ACCVGPR()}], [ureg("vdst", 256, 2), ureg("sdst", 4, 2)], 0)]
def fx_hi() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("vdst", 511, 1)], 0)]
def fx_512() -> List<&2, Ins>: [ins_of(Nil{}, [ureg("vdst", 512, 1)], 0)]

def none_l() -> List<&2, Lds>: Nil{}
def none_p() -> List<&2, Slot>: Nil{}
def none_g() -> List<&2, String>: Nil{}
def pack(arch: String, insts: List<&2, Ins>, code_len: U32, locs: List<&2, Lds>,
    params: List<&2, Slot>, gids: List<&2, String>) -> String:
  assemble_linear(arch, insts, code_len, locs, params, gids)

# Expected strings are the words a real assemble_linear ELF held, parsed back
# out of the blob the oracle called. entry's hi:lo is struct.pack('<q', -text).
def want_nop(r1: String, prop: String) -> String:
  String.concat(["lds=0 kern=0 entry=4294967295:4294966284 r1=", r1,
    " r2=4 r3=0 prop=", prop, " text=1012 roff=1280"])

def g_consts() -> IO(Unit):
  do IO<Unit>:
    urow("shift.vgpr", SHIFT_VGPR(), 0)
    urow("shift.sgpr", SHIFT_SGPR(), 6)
    urow("shift.denorm", SHIFT_DENORM(), 18)
    urow("shift.dx10", SHIFT_DX10(), 21)
    urow("shift.ieee", SHIFT_IEEE(), 23)
    urow("shift.mem", SHIFT_MEM(), 30)
    urow("shift.user", SHIFT_USER(), 1)
    urow("shift.gidx", SHIFT_GIDX(), 7)
    urow("shift.gidy", SHIFT_GIDY(), 8)
    urow("shift.gidz", SHIFT_GIDZ(), 9)
    urow("shift.kptr", SHIFT_KPTR(), 3)
    urow("shift.wave32", SHIFT_WAVE32(), 10)
    urow("shift.accum", SHIFT_ACCUM(), 0)
    urow("align.isa", AMD_ISA_ALIGN_BYTES(), 256)
    urow("align.kern", AMD_KERNEL_CODE_ALIGN_BYTES(), 64)
    urow("op.acc", OPR_ACCVGPR(), 1)
    urow("op.src_acc", OPR_SRC_ACCVGPR(), 21)
    urow("op.src_or", OPR_SRC_VGPR_OR_ACCVGPR(), 26)
    urow("op.src_or_c", OPR_SRC_VGPR_OR_ACCVGPR_OR_CONST(), 27)
    urow("op.or", OPR_VGPR_OR_ACCVGPR(), 41)
    urow("enc.code_end", s_code_end_word(), 3214868480)
    urow("enc.nop", s_nop_cdna_word(), 3212836864)
    urow("enc.len", PAD_LEN(), 4)
    urow("sz.ehdr", EHDR_SIZE(), 64)
    urow("sz.shdr", SHDR_SIZE(), 64)
    urow("sz.kd", KD_SIZE(), 64)
    urow("sht.progbits", SHT_PROGBITS(), 1)
    urow("sht.strtab", SHT_STRTAB(), 3)
    urow("shf.alloc", SHF_ALLOC(), 2)
    urow("shf.exec", SHF_EXECINSTR(), 4)
    urow("shf.alloc_exec", SHF_ALLOC_EXEC(), 6)
    urow("elf.mag0", ELF_MAG0(), 127)
    urow("elf.mag1", ELF_MAG1(), 69)
    urow("elf.mag2", ELF_MAG2(), 76)
    urow("elf.mag3", ELF_MAG3(), 70)
    urow("elf.class", ELF_CLASS64(), 2)
    urow("elf.shnum", E_SHNUM(), 3)
    urow("elf.shstrndx", E_SHSTRNDX(), 2)
    urow("win.vgpr_lo", vgpr_lo(), 256)
    urow("win.vgpr_hi", vgpr_hi(), 512)
    urow("win.sgpr_hi", sgpr_hi(), 106)
    srow("strtab.names", sh_names_text(), "1,7,15")
    urow("strtab.len", strtab_len(), 23)
    urow("layout.text_off", text_off(), 256)

def g_arch() -> IO(Unit):
  do IO<Unit>:
    srow("arch.gfx900", _arch_map("gfx900"), "cdna")
    srow("arch.gfx908", _arch_map("gfx908"), "cdna")
    srow("arch.gfx90a", _arch_map("gfx90a"), "cdna")
    srow("arch.gfx942", _arch_map("gfx942"), "cdna")
    srow("arch.gfx1030", _arch_map("gfx1030"), "rdna3")
    srow("arch.gfx1100", _arch_map("gfx1100"), "rdna3")
    srow("arch.gfx1101", _arch_map("gfx1101"), "rdna3")
    srow("arch.gfx1200", _arch_map("gfx1200"), "rdna4")
    srow("arch.gfx1201", _arch_map("gfx1201"), "rdna4")
    srow("arch.gfx8", _arch_map("gfx8"), "")
    srow("arch.GFX1100", _arch_map("GFX1100"), "")
    srow("arch.empty", _arch_map(""), "")

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
    urow("kern.sorted", kernarg([Slot{0, 4}, Slot{1, 1}, Slot{2, 8}]), 16)
    urow("kern.unsorted", kernarg([Slot{2, 8}, Slot{0, 4}, Slot{1, 1}]), 16)
    urow("kern.empty", kernarg(none_p()), 0)
    urow("lds.one", lds_sum([Lds{8, 4}]), 32)
    urow("lds.two", lds_sum([Lds{8, 4}, Lds{15, 2}]), 62)
    urow("lds.none", lds_sum(none_l()), 0)
    row("gid.x", Gids.x(gids_of(["gidx0"])))
    row("gid.y", Gids.y(gids_of(["gidx1"])))
    row("gid.z", Gids.z(gids_of(["gidx2"])))
    row("gid.ten_is_x", Gids.x(gids_of(["gidx10"])))
    row("gid.ten_not_y", Bool.not(Gids.y(gids_of(["gidx10"]))))
    row("gid.local_skip", Bool.not(Gids.x(gids_of(["lidx0"]))))
    row("gid.nine_no_bit", Bool.not(Bool.or(Gids.x(gids_of(["gidx9"])), Bool.or(Gids.y(gids_of(["gidx9"])), Gids.z(gids_of(["gidx9"]))))))
    row("gid.bad", Gids.bad(gids_of(["gidx"])))
    row("gid.ok", Bool.not(Gids.bad(gids_of(["gidx0"]))))

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
    srow("elf.lds", pack("gfx1100", fx_empty(), 4, [Lds{8, 4}], none_p(), none_g()),
      "lds=32 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.lds2", pack("gfx1100", fx_empty(), 4, [Lds{8, 4}, Lds{15, 2}], none_p(), none_g()),
      "lds=62 kern=0 entry=4294967295:4294966284 r1=1085014016 r2=4 r3=0 prop=1032 text=1012 roff=1280")
    srow("elf.kern", pack("gfx1100", fx_empty(), 4, none_l(), [Slot{2, 8}, Slot{0, 4}, Slot{1, 1}], none_g()),
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
