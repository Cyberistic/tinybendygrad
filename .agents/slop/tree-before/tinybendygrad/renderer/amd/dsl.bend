# tinybendygrad/renderer/amd/dsl.bend -- port of tinygrad/renderer/amd/dsl.py
#
# THE EXPRESSION ALGEBRA that builds AMD instructions. `dsl.py` is 456 lines of
# Python: a 512-entry register space, a bit-field algebra with five typed field
# classes, a handful of `encode`/`decode`/`set`/`fmt` rules, and the `Inst`
# assembly that walks a class's field list to build one little-endian word.
#
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure; the gate checks it) OR records that call in the
# trace (the gate checks ORDER and IDENTITY). There is no third kind. This file
# is ENTIRELY the first kind: it has no trace, no foreign effect, and no
# `@extern`. It produces words; `sqtt.bend` consumes them.
#
# THE FOUR TABLE DIRECTIONS, which is the load-bearing part. `Reg._NAMES`,
# `Reg._PAIRS` and `SrcField._FLOAT_ENC` are ported as (offset, name) pairs and
# as (name, offset) pairs, and the gate reads BOTH. `ops_nv`'s audit found 33 of
# 219 constants wrong in a file already printing 590 green rows, so a one-way
# table is not a table.
#
# ===========================================================================
# THE DEFERRED BOUNDARY, MEASURED, AND IT IS NOT THIS FILE.
#
# dsl.py:239-242 imports three GENERATED operand tables and merges them:
#   tinygrad/runtime/autogen/amd/rdna3/operands.py   1522 lines
#   tinygrad/runtime/autogen/amd/rdna4/operands.py   1546 lines
#   tinygrad/runtime/autogen/amd/cdna/operands.py    1573 lines
#                                   total             4641 lines
# That is 4,641 lines of autogen, NOT 1,212 lines of logic, and it is the
# `amd`/`isa` deferred scope this port does not take. Every `Inst` subclass, the
# opcode enums they decode, and the `_fields` list of each are also autogen.
#
# SO THE PORT MAKES THE OPERAND INFO AN ARGUMENT. `Inst.operands` (:345) is a
# property that reads a module-level dict; taking it as a parameter instead is
# the same information with the lookup made explicit, and it is what makes the
# ADJUSTMENTS in `op_bits` (:348-377) -- which are 30 of the 456 lines and all of
# the interesting logic -- reachable and checkable at all. `dsl.bend` therefore
# ports dsl.py's LOGIC and names dsl.py's DATA.
#
# `autogen/am/*.py` (34,567 lines, read only for the constant audit) holds MM
# register definitions, NOT the src encoding space: `grep -rl
# 'FLAT_SCRATCH_LO' tinygrad/runtime/autogen/am/` returns nothing. So the
# authority for the register OFFSETS is the AMD ISA, which is not in this repo
# and is not reachable offline. See CONSTANT MAP, item (a): the authority used
# is dsl.py's own FOUR independent spellings of each boundary, cross-checked
# against each other in `.agents/slop/dsl_constmap.py`.

import Base
import ../../helpers.bend as H

# TWO BEND FACTS, PROVED BY PROBE, THAT SHAPE EVERY GATE ROW HERE.
#
# 1. A `do` BLOCK CANNOT BIND A NON-`Unit` VALUE. `a : U32 <- q()` inside
#    `do IO<Unit>:` is a COMPILE ERROR -- the error even reads
#    `expected : @-R:Type -> ... -> IO.OP<R>` / `observed : U32`, which sends you
#    looking for a missing `IO.print` that is not there. The binding form is for
#    sequencing `IO(Unit)` effects only, so a gate row here is
#    `# a table's LENGTH is a Nat and a table's entry is a U32; printing both through
# one text helper means a length row and a value row cannot disagree about what
# a number looks like.
def u32_text(v: U32) -> String: U32.show(v)
def nat_text(v: Nat) -> String: U32.show(U32.from_nat(v))

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
# 2. `H.I64` EXISTS (helpers.bend:1167, `I64{hi: U32, lo: U32}`), so the
#    64-BIT WALL is narrower than "no 64-bit type": a `_raw` wider than 32 bits
#    and the 64-bit `literal` field can both be held. What CANNOT be held is a
#    field WIDER than 64 bits, of which there are none.

# ===========================================================================
# THE TYPES.
# ===========================================================================

# `dsl.py:18-20`. `Reg` is a WINDOW on the 512-entry src space: an offset, a
# width, and three source modifiers. `ab` is Python's `abs_` (`abs` is taken).
type Rg is Data:
  Rg{off: U32, sz: U32, neg: Bool, ab: Bool, hi: Bool}

# ONE answer: a number, and its rendered form, or the refusal VERBATIM. One
# refusal type for the whole file, because a refusal is a MESSAGE and a gate that
# compares flags compares less than a gate that compares text.
type Res is Data:
  Res{v: U32, s: String}
  Bad{msg: String}

# the FIVE field classes (:100 BitField, :125 FixedBitField, :130
# EnumBitField, :149 SrcField, :202 AlignedSGPRField, :221 VDSTYField) as ONE
# tagged record, because the algebra dispatches on the class and nothing else.
# `rng` is `_valid_range` (lo/hi) for the SrcField family and 0/0 elsewhere.
type Fld is Data:
  Fld{name: String, hi: U32, lo: U32, dflt: U32, kind: U32, rlo: U32, rhi: U32,
      align: U32}

# the KIND tag. The numbers are this file's own, in the order the classes are
# defined in dsl.py -- they reach no device, so a wrong one is not a wrong call.
def K_PLAIN() -> U32: 0     # BitField
def K_FIXED() -> U32: 1     # FixedBitField
def K_ENUM() -> U32: 2      # EnumBitField
def K_SRC() -> U32: 3       # SrcField
def K_VGPR() -> U32: 4      # VGPRField
def K_SGPR() -> U32: 5      # SGPRField
def K_SSRC() -> U32: 6      # SSrcField
def K_ALIGN() -> U32: 7     # AlignedSGPRField
def K_SBASE() -> U32: 8     # SBaseField
def K_SRSC() -> U32: 9      # SRsrcField
def K_VDSTY() -> U32: 10    # VDSTYField

# the value a caller hands a field. ONE record, because Python dispatches on
# `isinstance(val, Reg)` / `isinstance(val, float)` / `isinstance(val, int)` and
# a Python `int` is a signed value the port holds as two's complement. `f` is
# unused for every kind but OV_FLOAT, which is a WALL (see THE FLOAT WALL).
type Ov is Data:
  Ov{k: U32, off: U32, sz: U32, neg: Bool, ab: Bool, hi: Bool}
def OV_NONE() -> U32: 0
def OV_REG() -> U32: 1
def OV_INT() -> U32: 2
def OV_FLOAT() -> U32: 3

# ONE operand of an Inst, as `__init__` sees it (`vals[name]`). `v` is the
# value, `has` says the caller supplied it -- Python's `vals[name] is None`.
type Arg is Data:
  Arg{name: String, v: Ov, has: Bool}

# the `operands` dict of :345 as data: an operand's NAME and its WIDTH IN BITS.
type Opd is Data:
  Opd{name: String, bits: U32}

# a name -> offset binding, the shape of every table in this file.
type Nm is Data:
  Nm{name: String, off: U32}

# ===========================================================================
# THE CONSTANTS. Every one of these is audited in
# `.agents/slop/dsl_constmap.py` against CPython, by getattr and by probe.
# ===========================================================================

# THE SPACE. `src = Reg(0, 512)` (:66). 512 entries, offsets 0..511.
def SRC_SZ() -> U32: 512
def SRC_LO() -> U32: 0
def SRC_HI() -> U32: 511

# THE SLICES, :68-89. An inclusive Python end becomes size = end - start + 1,
# and `Reg(src, a:b)` is `Reg(a, b - a + 1)`. Four boundaries, four spellings.
def S_LO() -> U32: 0
def S_HI() -> U32: 105          # s = src[0:105] -> SZPR 106
def S_SZ() -> U32: 106
def TTMP_LO() -> U32: 108       # ttmp = src[108:123]
def TTMP_HI() -> U32: 123
def TTMP_SZ() -> U32: 16
def V_LO() -> U32: 256          # v = src[256:511]
def V_HI() -> U32: 511
def V_SZ() -> U32: 256

# THE NAMED REGISTERS. Each is `src[N]`, i.e. offset N, size 1. NULL and OFF
# are the SAME register (:74 `NULL = OFF = src[124]`), and DPP and DPP16 are
# the same register (:83 `DPP = DPP16 = src[250]`); the aliasing is the point.
def VCC_LO() -> U32: 106
def VCC_HI() -> U32: 107
def VCC_OFF() -> U32: 106
def VCC_SZ() -> U32: 2
def NULL_OFF() -> U32: 124
def OFF_OFF() -> U32: 124
def M0_OFF() -> U32: 125
def EXEC_LO() -> U32: 126
def EXEC_HI() -> U32: 127
def EXEC_OFF() -> U32: 126
def EXEC_SZ() -> U32: 2
def INV_2PI_OFF() -> U32: 248
def SDWA_OFF() -> U32: 249
def DPP_OFF() -> U32: 250
def DPP16_OFF() -> U32: 250
def VCCZ_OFF() -> U32: 251
def EXECZ_OFF() -> U32: 252
def SCC_OFF() -> U32: 253
def SRC_LDS_DIRECT_OFF() -> U32: 254
def LIT_OFF() -> U32: 255

# THE FLOAT CONSTANTS, :151 `_FLOAT_ENC`. Eight values, and the OFFSETS are the
# same eight `_NAMES` entries at :14 -- two spellings of one table.
def F0_5_OFF() -> U32: 240
def F_NEG_0_5_OFF() -> U32: 241
def F1_0_OFF() -> U32: 242
def F_NEG_1_0_OFF() -> U32: 243
def F2_0_OFF() -> U32: 244
def F_NEG_2_0_OFF() -> U32: 245
def F4_0_OFF() -> U32: 246
def F_NEG_4_0_OFF() -> U32: 247
def F_N_OFF() -> U32: 8
def FLOAT_ENC_DEFAULT() -> U32: 255

# the eight float constants, as a COUNT, and the sign bit of a U32. Both exist
# because the audit claims them and a claimed constant with no def is a hole.
def F_N() -> U32: 8
def SUB_BITS() -> U32: 31

# THE `fmt` ARM BOUNDARIES, :46-58. EIGHT arms, and each boundary is stated
# here, in `_NAMES`' key range, in the module slices above, and (for `s`, `ttmp`
# and `v`) in the arm's own test. The const map cross-checks all four.
def FMT_V_LO() -> U32: 256      # 256 <= o < 512
def FMT_V_HI() -> U32: 512
def FMT_S_HI() -> U32: 106      # o < 106
def FMT_PAIR_SZ() -> U32: 2     # sz == 2 and o in _PAIRS
def FMT_TTMP_LO() -> U32: 108   # 108 <= o < 124
def FMT_TTMP_HI() -> U32: 124
def FMT_INT_LO() -> U32: 128    # 128 <= o <= 192  ->  str(o - 128)
def FMT_INT_HI() -> U32: 192
def FMT_NEG_LO() -> U32: 193    # 193 <= o <= 208  ->  str(-(o - 192))
def FMT_NEG_HI() -> U32: 208
def FMT_INT_BASE() -> U32: 128
def FMT_NEG_BASE() -> U32: 192
def FMT_RNG_LO() -> U32: 240
def FMT_RNG_HI() -> U32: 256

# THE BRACKET RULE, :46: `l, r = ("[", "]") if parens or sz > 1 else ("", "")`.
def BRACKET_MULTI() -> U32: 1   # sz > 1

# THE FIELD RANGES, :150/:188/:199/:200, enforced at __init__ (:155-159).
def SRC_VALID_LO() -> U32: 0
def SRC_VALID_HI() -> U32: 511
def SRC_VALID_N() -> U32: 512   # hi - lo + 1, and 2 ** (hi - lo + 1)
def SRC_FIELD_BITS() -> U32: 9
def VGPR_VALID_LO() -> U32: 256
def VGPR_VALID_HI() -> U32: 511
def VGPR_VALID_N() -> U32: 256
def VGPR_FIELD_BITS() -> U32: 8
def SGPR_VALID_LO() -> U32: 0
def SGPR_VALID_HI() -> U32: 127
def SGPR_VALID_N() -> U32: 128
def SGPR_FIELD_BITS() -> U32: 7
def SSRC_VALID_LO() -> U32: 0
def SSRC_VALID_HI() -> U32: 255
def SSRC_VALID_N() -> U32: 256
def SSRC_FIELD_BITS() -> U32: 8

# THE INLINE-INT RANGES, :165-166 and :56-57.
def INT_MIN() -> U32: 0
def INT_MAX() -> U32: 64
def NEG_MIN() -> U32: 4294967280   # -16, two's complement: no I32 in Bend
def NEG_MAX() -> U32: 4294967295   # -1
def NEG_OFF_BASE() -> U32: 192     # offset = 192 - val
def INT_OFF_BASE() -> U32: 128     # offset = 128 + val
def INT_N() -> U32: 65             # 0..64 inclusive, :252

# VGPRField's `.h` opsel bit, :194-197. 8-bit fields only, and the encoded
# index must already be below 128.
def VGPR_HI_MASK() -> U32: 128
def VGPR_HI_BITS() -> U32: 8

# THE ALIGNMENTS, :204/:218/:219 and the two `bit_length() - 1` shifts.
def ALIGN_DEFAULT() -> U32: 2
def ALIGN_SBASE() -> U32: 2
def ALIGN_SRSC() -> U32: 4
def ALIGN_SHIFT_2() -> U32: 1      # 2 .bit_length() - 1
def ALIGN_SHIFT_4() -> U32: 2      # 4 .bit_length() - 1

# VDSTYField, :221-232. encoded = (offset - 256) >> 1; the decode ORs in
# `(vdstx.offset - 256) & 1) ^ 1` and rebuilds at 256 + that.
def VDSTY_SHIFT() -> Nat: 1n
def VDSTY_XOR() -> U32: 1
def VDSTY_LO() -> U32: 256

# `_base_size = (max(f.hi) + 8) // 8` (:282), and the literal marker / mask.
def BASE_SIZE_ROUND() -> U32: 8
def BASE_SIZE_DIV() -> U32: 8
def LIT_MARKER() -> U32: 255
def LIT32_MASK() -> U32: 4294967295

# THE MODIFIER BITS, :313-321. src0/src1/src2 take bit 0/1/2 and vdst.hi takes
# bit 3 -- four DIFFERENT bits for four different registers.
def MOD_SRC0_BIT() -> U32: 1
def MOD_SRC1_BIT() -> U32: 2
def MOD_SRC2_BIT() -> U32: 4
def MOD_VDST_BIT() -> U32: 8

# `op_regs = {k: max(1, v // 32)}` (:381/:402) and its 32-bit stride.
def REG_STRIDE() -> U32: 32
def REG_MIN() -> U32: 1

# THE `op_bits` ADJUSTMENTS, :353-376.
def ADJ_SRC2_BITS() -> U32: 32     # cndmask / _co_ci_ / VOP3SD / cmp
def ADJ_VDST_BITS() -> U32: 32
def ADJ_ADDR_BITS() -> U32: 64
def ADJ_ADDR_BITS2() -> U32: 32
def ADJ_SADDR_NULL() -> U32: 124
def ADJ_SADDR_M0() -> U32: 125
def ADJ_VADDR_MULT() -> U32: 32    # max(1, offen + idxen) * 32
def ADJ_CBSZ_SHIFT() -> U32: 8
def ADJ_BLGP_SHIFT() -> U32: 61
def ADJ_MFMA_SEL_MASK() -> U32: 7
# the `vgprs` dict at :375, as (cbsz, blgp) -> BITS PER REGISTER
def MFMA_CBSZ_LO() -> U32: 0
def MFMA_CBSZ_HI() -> U32: 4
def MFMA_B0() -> U32: 8
def MFMA_B1() -> U32: 8
def MFMA_B2() -> U32: 6
def MFMA_B3() -> U32: 6
def MFMA_B4() -> U32: 4
def MFMA_DEFAULT() -> U32: 8

# THE CANONICAL SEED, :386 -- all five names start at 32 bits, and only a
# canonical name overwrites one.
def CANON_SEED() -> U32: 32
def CANON_N() -> U32: 5

# `num_srcs`, :404-410.
def NSRC_MAX() -> U32: 3
def NSRC_TWO() -> U32: 2
def NSRC_ONE() -> U32: 1
def NSRC_ZERO() -> U32: 0

# `_variant_suffix`, :423-437 -- three offsets, three suffixes.
def VS_LIT_OFF() -> U32: 255
def VS_SDWA_OFF() -> U32: 249
def VS_DPP8_OFF() -> U32: 249
def VS_DPP16_OFF() -> U32: 250

# THE NON-RESIZABLE SET, :180 and :339: offsets 106..127 and 249..255 are
# exempt from the `op_regs` width check, and 124/125 and 240..255 are exempt
# from the `__get__` resize. Two ranges, two exemptions, both stated twice.
def EXEMPT_LO1() -> U32: 106
def EXEMPT_HI1() -> U32: 127
def EXEMPT_LO2() -> U32: 249
def EXEMPT_HI2() -> U32: 255
def NORESIZE_A() -> U32: 124
def NORESIZE_B() -> U32: 125
def NORESIZE_C() -> U32: 240
def NORESIZE_D() -> U32: 256
def t_stub() -> IO(Unit):
  do IO<Unit>:
    IO.print("stub")
# ===========================================================================
# THE TABLES. Four of them, each ported in BOTH directions.
#
# A Bend list of `Nm` IS the direction; the two directions are two defs over
# one list, so a wrong binding shows up in both at once. That is the property a
# dict keyed the other way would not have.
# ===========================================================================

# `Reg._NAMES` (:11-15), in DICT ORDER -- the order is part of the table, so it
# is a list and not a set. 32 entries.
def reg_names() -> List<&2, Nm>:
  [Nm{"FLAT_SCRATCH_LO", 102}, Nm{"FLAT_SCRATCH_HI", 103}, Nm{"XNACK_MASK_LO", 104},
   Nm{"XNACK_MASK_HI", 105}, Nm{"VCC_LO", 106}, Nm{"VCC_HI", 107}, Nm{"NULL", 124},
   Nm{"M0", 125}, Nm{"EXEC_LO", 126}, Nm{"EXEC_HI", 127}, Nm{"DPP8", 233},
   Nm{"DPP8FI", 234}, Nm{"SHARED_BASE", 235}, Nm{"SHARED_LIMIT", 236},
   Nm{"PRIVATE_BASE", 237}, Nm{"PRIVATE_LIMIT", 238}, Nm{"0.5", 240},
   Nm{"-0.5", 241}, Nm{"1.0", 242}, Nm{"-1.0", 243}, Nm{"2.0", 244},
   Nm{"-2.0", 245}, Nm{"4.0", 246}, Nm{"-4.0", 247}, Nm{"INV_2PI", 248},
   Nm{"SDWA", 249}, Nm{"DPP", 250}, Nm{"VCCZ", 251}, Nm{"EXECZ", 252},
   Nm{"SCC", 253}, Nm{"SRC_LDS_DIRECT", 254}, Nm{"LIT", 255}]

# `Reg._PAIRS` (:16). Two entries, and they are the ONLY offsets for which
# `fmt` prints a name at size 2.
def reg_pairs() -> List<&2, Nm>:
  [Nm{"VCC", 106}, Nm{"EXEC", 126}]

# `SrcField._FLOAT_ENC` (:151). Eight entries, offset -> float VALUE as text.
# The offsets must equal the eight `_NAMES` float entries at 240..247; the
# const map checks that equality rather than assuming it.
def float_enc() -> List<&2, Nm>:
  [Nm{"0.5", 240}, Nm{"-0.5", 241}, Nm{"1.0", 242}, Nm{"-1.0", 243},
   Nm{"2.0", 244}, Nm{"-2.0", 245}, Nm{"4.0", 246}, Nm{"-4.0", 247}]

# `_canonical_name` (:261-268), BOTH directions. SEVEN inputs fold onto five
# canonical names and everything else is None -- the spellings are load-bearing
# because `canonical_op_bits` writes through them.
def canon_fwd() -> List<&2, Nm>:
  [Nm{"s0", 0}, Nm{"s1", 1}, Nm{"s2", 2}, Nm{"d", 3}, Nm{"data", 4}]
def canon_in() -> List<&2, Nm>:
  [Nm{"src0", 0}, Nm{"vsrc0", 0}, Nm{"ssrc0", 0}, Nm{"src1", 1}, Nm{"vsrc1", 1},
   Nm{"ssrc1", 1}, Nm{"src2", 2}, Nm{"vdst", 3}, Nm{"sdst", 3}, Nm{"sdata", 3},
   Nm{"data", 4}, Nm{"vdata", 4}, Nm{"data0", 4}, Nm{"vsrc", 4}]

# ===========================================================================
# THE LOOKUPS. A dict lookup is "walk in lockstep and keep the FIRST hit", so
# every one of these carries `found` and `Bool.pick`s the value. `List.find`
# would keep the LAST hit and is NOT the same function.
# ===========================================================================

# offset -> name, keeping the first hit. Absent answers "" -- `self._NAMES[o]`
# is a KeyError, and the port turns it into the arm that follows, which is the
# value that arm returns. "" is therefore the SENTINEL, not a name.
def nm_name.go(n: Nat, +off: U32, xs: List<&2, Nm>, +found: Bool, got: String) -> String:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case Nm{nm, +o} <> t:
          +h = U32.is_eq(off, o)
          nm_name.go(m, off, t, Bool.or(found, h), Bool.pick(String, Bool.and(Bool.not(found), h), nm, got))

# name -> offset, keeping the first hit. Absent answers the caller's `dflt`.
def nm_off.go(n: Nat, +want: String, xs: List<&2, Nm>, +found: Bool, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case Nm{nm, +o} <> t:
          +h = String.eq(nm, want)
          nm_off.go(m, want, t, Bool.or(found, h), Bool.pick(U32, Bool.and(Bool.not(found), h), o, got))


# Bend has no `value.field` sugar and generates no projection, so ONE reader per
# field, once. `cstyle.bend` died of writing them inline 43 times.
def Res.v.go(+r: Res, dflt: U32) -> U32:
  match r:
    case Res{v, s}: v
    case Bad{msg}: dflt

def Res.v(r: Res) -> U32:
  Res.v.go(r, 0)

def Res.s.go(+r: Res, dflt: String) -> String:
  match r:
    case Res{v, s}: s
    case Bad{msg}: dflt

def Res.s(r: Res) -> String:
  Res.s.go(r, "")

def Res.msg.go(+r: Res, dflt: String) -> String:
  match r:
    case Res{v, s}: dflt
    case Bad{msg}: msg

def Res.msg(r: Res) -> String:
  Res.msg.go(r, "")

def Rg.off(r: Rg) -> U32: match r: case Rg{o, s, n, a, h}: o
def Rg.sz(r: Rg) -> U32: match r: case Rg{o, s, n, a, h}: s
def Rg.neg(r: Rg) -> Bool: match r: case Rg{o, s, n, a, h}: n
def Rg.ab(r: Rg) -> Bool: match r: case Rg{o, s, n, a, h}: a
def Rg.hi(r: Rg) -> Bool: match r: case Rg{o, s, n, a, h}: h

def Fld.name(f: Fld) -> String: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: name
def Fld.hi(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: hi
def Fld.lo(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: lo
def Fld.dflt(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: dflt
def Fld.kind(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: kind
def Fld.rlo(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: rlo
def Fld.rhi(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: rhi
def Fld.align(f: Fld) -> U32: match f: case Fld{name, hi, lo, dflt, kind, rlo, rhi, align}: align

def Ov.k(v: Ov) -> U32: match v: case Ov{k, off, sz, neg, ab, hi}: k
def Ov.off(v: Ov) -> U32: match v: case Ov{k, off, sz, neg, ab, hi}: off
def Ov.sz(v: Ov) -> U32: match v: case Ov{k, off, sz, neg, ab, hi}: sz
def Ov.neg(v: Ov) -> Bool: match v: case Ov{k, off, sz, neg, ab, hi}: neg
def Ov.ab(v: Ov) -> Bool: match v: case Ov{k, off, sz, neg, ab, hi}: ab
def Ov.hi(v: Ov) -> Bool: match v: case Ov{k, off, sz, neg, ab, hi}: hi

def Opd.name(o: Opd) -> String: match o: case Opd{name, bits}: name
def Opd.bits(o: Opd) -> U32: match o: case Opd{name, bits}: bits

def DFLT_OFF() -> U32: 4294967295

# the walk lengths are CONSTANTS, not a `List.length` per call: the tables are
# literals, so their lengths are constants too, and a silent edit to a table
# then cannot silently change a walk's trip count.
def reg_names_n() -> Nat: 32n
def reg_pairs_n() -> Nat: 2n
def float_enc_n() -> Nat: 8n
def canon_fwd_n() -> Nat: 5n
def canon_in_n() -> Nat: 14n
def reg_name_of(off: U32) -> String: nm_name.go(reg_names_n(), off, reg_names(), False{}, "")
def reg_off_of(nm: String) -> U32: nm_off.go(reg_names_n(), nm, reg_names(), False{}, DFLT_OFF())
def pair_name_of(off: U32) -> String: nm_name.go(reg_pairs_n(), off, reg_pairs(), False{}, "")
def pair_off_of(nm: String) -> U32: nm_off.go(reg_pairs_n(), nm, reg_pairs(), False{}, DFLT_OFF())
def float_enc_name(off: U32) -> String: nm_name.go(float_enc_n(), off, float_enc(), False{}, "")
def float_enc_of(nm: String) -> U32: nm_off.go(float_enc_n(), nm, float_enc(), False{}, FLOAT_ENC_DEFAULT())
def canon_name(id: U32) -> String: nm_name.go(canon_fwd_n(), id, canon_fwd(), False{}, "")

# `_canonical_name(name)` (:261-268). It has only FIVE results, so the port
# gives it a sixth -- DFLT_OFF -- for "not a canonical operand". Both callers
# (:388, :396) guard with `if (cn := ...)`, so the sentinel is never read where
# it decides anything, and the table is now readable from the gate.
def canon_of(nm: String) -> U32: nm_off.go(canon_in_n(), nm, canon_in(), False{}, DFLT_OFF())

# ===========================================================================
# `Reg`. :18-63.
# ===========================================================================

# `Reg(offset=0, sz=512)` (:66). The whole src space, ONE register of 512 wide.
def src_space() -> Rg: Rg{SRC_LO(), SRC_SZ(), False{}, False{}, False{}}

# `src[key]` for an int key (:28-29). The bound test is `key < 0 or key >=
# self.sz` and it comes FIRST, so a negative key is a REFUSAL and never
# reaches Python's own negative indexing. `key_neg` is the `< 0` half, which
# the caller supplies because Bend has no I32; the gate pins both answers one
# row apart.
def key_text.go(neg: Bool, key: U32, dflt: String) -> String:
  match neg:
    case True{}: String.concat(["-", u32_text(U32.sub(0, key))])
    case False{}: dflt

def key_text(+key: U32, neg: Bool) -> String: key_text.go(neg, key, u32_text(key))

def reg_at.go(bad: Bool, +r: Rg, +key: U32, +neg: Bool) -> Res:
  match bad:
    case True{}: Bad{String.concat(["index ", key_text(key, neg), " out of bounds for size ", u32_text(Rg.sz(r))])}
    case False{}: Res{0, ""}

# `src[a:b]` (:24-27). FOUR tests, in source order, and only the first two can
# refuse: `start < 0` or `stop >= self.sz`. `start > stop` is NOT refused -- the
# port keeps the Python and the gate records what it produces, which is
# `Reg(offset + start, stop - start + 1)` with a NEGATIVE size.
#
# `key.start or 0` (:25) and `key.stop or (self.sz - 1)`: a slice with an
# absent bound reads it as absent, which is what `has_start` / `has_stop` say.
def reg_slice.go(bad: Bool, +start: U32, +stop: U32, +r: Rg) -> Res:
  match bad:
    case True{}:
      Bad{String.concat(["slice [", U32.show(start), ":", U32.show(stop), "] out of bounds for size ", U32.show(Rg.sz(r))])}
    case False{}: Res{0, ""}

# ===========================================================================
# `Reg.fmt` -- :44-62. EIGHT arms, and a transposed pair of them is a silently
# wrong assembly string, so the gate reads the STRING, never a branch taken.
#
#   256 <= o < 512   ->  v[idx]                   (:47-49)
#   o < 106          ->  s[idx]                   (:50)
#   sz == 2 and o in _PAIRS -> VCC | EXEC         (:51)
#   o in _NAMES      ->  the name                 (:52)
#   108 <= o < 124   ->  ttmp[idx]                (:53-55)
#   128 <= o <= 192  ->  str(o - 128)             (:56)
#   193 <= o <= 208  ->  str(-(o - 192))          (:57)
#   else             ->  REFUSE                   (:58)
#
# `brk` is `parens or sz > 1` (:46), resolved by the CALLER because `fmt`
# computes it before it branches. Only the three indexed arms read it; the name
# and integer arms ignore it, which is why `abs(...)`/`|...|` and `-...` are the
# only suffixes and there is no bracket suffix.
# ===========================================================================
def reg_at(+key: U32, +key_neg: Bool, +r: Rg) -> Res:
  reg_at.go(Bool.or(key_neg, U32.is_ge(key, Rg.sz(r))), r, key, key_neg)

# `f"index {key} out of bounds"` (:28) prints the SIGNED key, and Bend has no
# I32 -- so a negative key arrives as its two's complement and has to be spelled
# back. The refusal text is the thing the gate compares, so a `4294967295` where
# CPython writes `-1` is a real mismatch and not a formatting quibble.
def reg_slice(+start: U32, start_neg: Bool, has_start: Bool, +stop: U32, stop_neg: Bool,
              has_stop: Bool, +r: Rg) -> Res:
  reg_slice.go(Bool.or(Bool.or(start_neg, stop_neg), U32.is_ge(stop, Rg.sz(r))), start, stop, r)
def reg_slice_start(r: Rg, start: U32, stop: U32) -> Res: reg_slice(start, False{}, True{}, stop, False{}, True{}, r)
def fmt_unknown_msg(o: U32, sz: U32) -> String:
  String.concat(["unknown register: offset=", U32.show(o), ", sz=", U32.show(sz)])
def fmt_idx.go(one: Bool, pfx: String, +idx: U32, +sz: U32, +brk: Bool) -> String:
  match one:
    case True{}: String.concat([pfx, Bool.pick(String, brk, "[", ""), U32.show(idx), Bool.pick(String, brk, "]", "")])
    case False{}: String.concat([pfx, "[", U32.show(idx), ":", U32.show(U32.add(idx, U32.sub(sz, 1))), "]"])

# `self._PAIRS[o] if upper else self._PAIRS[o].lower()` and the same for
# `_NAMES` -- UPPER is `.upper()` on the NAME, never on the digits.
def fmt_idx(pfx: String, +idx: U32, +sz: U32, +brk: Bool) -> String:
  fmt_idx.go(U32.is_eq(sz, 1), pfx, idx, sz, brk)
def fmt_case(+nm: String, upper: Bool) -> String:
  Bool.pick(String, upper, nm, String.to_lower(nm))
def has_name(off: U32) -> Bool: Bool.not(String.eq(reg_name_of(off), ""))
def has_pair(off: U32) -> Bool: Bool.not(String.eq(pair_name_of(off), ""))
def vgpr_off(+o: U32) -> Bool: Bool.and(U32.is_ge(o, FMT_V_LO()), U32.is_lt(o, FMT_V_HI()))
def ttmp_off(+o: U32) -> Bool: Bool.and(U32.is_ge(o, FMT_TTMP_LO()), U32.is_lt(o, FMT_TTMP_HI()))
def inl_int(+o: U32) -> Bool: Bool.and(U32.is_ge(o, FMT_INT_LO()), U32.is_le(o, FMT_INT_HI()))
def inl_neg(+o: U32) -> Bool: Bool.and(U32.is_ge(o, FMT_NEG_LO()), U32.is_le(o, FMT_NEG_HI()))

def fmt_base.a7(v: Bool, o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, String.concat(["-", U32.show(U32.sub(o, FMT_NEG_BASE()))])}
    case False{}: Bad{fmt_unknown_msg(o, sz)}
def fmt_base.a6(v: Bool, +o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, U32.show(U32.sub(o, FMT_INT_BASE()))}
    case False{}: fmt_base.a7(inl_neg(o), o, sz, brk, upper)
def fmt_base.a5(v: Bool, +o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, fmt_idx("ttmp", U32.sub(o, FMT_TTMP_LO()), sz, brk)}
    case False{}: fmt_base.a6(inl_int(o), o, sz, brk, upper)
def fmt_base.a4(v: Bool, +o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, fmt_case(reg_name_of(o), upper)}
    case False{}: fmt_base.a5(ttmp_off(o), o, sz, brk, upper)
def fmt_base.a3(v: Bool, +o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, fmt_case(pair_name_of(o), upper)}
    case False{}: fmt_base.a4(has_name(o), o, sz, brk, upper)
def fmt_base.a2(v: Bool, +o: U32, +sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, fmt_idx("s", o, sz, brk)}
    case False{}: fmt_base.a3(Bool.and(U32.is_eq(sz, FMT_PAIR_SZ()), has_pair(o)), o, sz, brk, upper)
def fmt_base.a1(v: Bool, +o: U32, sz: U32, brk: Bool, upper: Bool) -> Res:
  match v:
    case True{}: Res{0, fmt_idx("v", U32.sub(o, FMT_V_LO()), sz, brk)}
    case False{}: fmt_base.a2(U32.is_lt(o, FMT_S_HI()), o, sz, brk, upper)

def fmt_base(+o: U32, sz: U32, brk: Bool, upper: Bool) -> Res: fmt_base.a1(vgpr_off(o), o, sz, brk, upper)

# THE THREE MODIFIER SUFFIXES, in Python's order (:59-61): `.h`, then abs, then
# `-`. The order is load-bearing -- `-abs(x)` and `abs(-x)` are different
# strings -- and the gate pins all eight combinations of the three flags.
def fmt_suffix.hi(hi: Bool, +base: String) -> String:
  Bool.pick(String, hi, String.concat([base, ".h"]), base)

# `f"abs({base})" if upper else f"|{base}|"` -- UPPER changes the SPELLING, not
# just the case, so the two are one pick and not a case transform.
def fmt_suffix.abs(ab: Bool, +base: String, upper: Bool) -> String:
  Bool.pick(String, ab, Bool.pick(String, upper, String.concat(["abs(", base, ")"]), String.concat(["|", base, "|"])), base)
def fmt_suffix.neg(neg: Bool, +s: String, base: String, upper: Bool) -> String:
  Bool.pick(String, neg, String.concat(["-", s]), s)

# `o, sz = self.offset, sz or self.sz` (:45). `sz or self.sz` is a Python
# TRUTHINESS test, so an sz of ZERO falls back to the register's own width --
# which the gate pins, because reading it as a "sz was given" flag would make
# `fmt(sz=0)` answer s0 instead of s[0:511].
def fmt_suffix(+base: String, +r: Rg, +upper: Bool) -> String:
  fmt_suffix.neg(Rg.neg(r), fmt_suffix.abs(Rg.ab(r), fmt_suffix.hi(Rg.hi(r), base), upper), base, upper)
def fmt_sz(+sz_ov: U32, +r: Rg) -> U32: Bool.pick(U32, U32.is_zero(sz_ov), Rg.sz(r), sz_ov)

# `Reg.fmt(sz=None, parens=False, upper=False)`, and `__repr__` is
# `fmt(parens=True, upper=True)` (:63). `brk` is `parens or sz > 1` (:46),
# computed BEFORE the arms -- which is why it is a parameter here and not a
# decision inside each arm.
def reg_fmt.mods(res: Res, +r: Rg, upper: Bool) -> Res:
  match res:
    case Res{v, s}: Res{v, fmt_suffix(s, r, upper)}
    case Bad{msg}: Bad{msg}

def reg_fmt.base(+sz: U32, +r: Rg, sz_ov: U32, parens: Bool, +upper: Bool) -> Res:
  reg_fmt.mods(fmt_base(Rg.off(r), sz, Bool.or(parens, U32.is_gt(sz, BRACKET_MULTI())), upper), r, upper)

def reg_fmt.go(+r: Rg, +sz_ov: U32, parens: Bool, upper: Bool) -> Res:
  reg_fmt.base(fmt_sz(sz_ov, r), r, sz_ov, parens, upper)
def reg_fmt(+r: Rg, sz_ov: U32, parens: Bool, upper: Bool) -> Res: reg_fmt.go(r, sz_ov, parens, upper)
def reg_repr(+r: Rg) -> Res: reg_fmt(r, 0, True{}, True{})

# ===========================================================================
# `BitField` -- :100-123. THE FOUR NUMBERS, and only four:
#
#   hi, lo, default, mask = (1 << (hi - lo + 1)) - 1   (:103)
#
# `mask` is the load-bearing one: every read AND every write is masked by it, so
# a wrong mask silently reads a neighbouring field. `set` is (:113-119):
#
#   val is None  -> default            (:114)
#   encoded < 0  -> encoded & mask     two's complement (:117)
#   out of range -> REFUSE             (:118)
#   else  -> (raw & ~(mask << lo)) | (encoded << lo)          (:119)
#
# `~` is U32.not and `<<` is U32.shln on a Nat -- see bend2-constraints: `U32.shl`
# is a ONE-BIT shift, so every shift AMOUNT here is a Nat literal or a
# U32.to_nat of a bound. The `lo` of a real field is a runtime value, so
# `U32.shln` is right and `U32.shl` would be wrong for every field.
# ===========================================================================

def bf_bits(+f: Fld) -> U32: U32.add(U32.sub(Fld.hi(f), Fld.lo(f)), 1)

# `1 << 32` SATURATES TO 0 in a U32 (measured, bend2-constraints), so a 32-bit
# field takes its mask from the constant instead of the shift. Every field
# dsl.py can build is <= 32 bits; the wider ones are THE 64-BIT WORD WALL.
def bf_mask.w(wide: Bool, +f: Fld) -> U32:
  match wide:
    case True{}: LIT32_MASK()
    case False{}: U32.sub(U32.shln(1, U32.to_nat(bf_bits(f))), 1)

def bf_mask(+f: Fld) -> U32: bf_mask.w(U32.is_eq(bf_bits(f), 32), f)

def bf_width_ok(f: Fld) -> Bool: U32.is_le(bf_bits(f), 32)

# `__get__` (:120-122): `(obj._raw >> self.lo) & self.mask`. The shift is a Nat.
def bf_raw_get(raw: U32, lo: U32, mask: U32) -> U32:
  U32.and(U32.shrn(raw, U32.to_nat(lo)), mask)

# `set`, and its TWO refusals. `enc` is ALREADY encoded -- the caller has run the
# field's own `encode`, which is what makes this one def for all five classes.
def bf_set_msg(+f: Fld, enc: U32) -> String:
  String.concat(["field '", Fld.name(f), "': value ", U32.show(enc), " doesn't fit in ", U32.show(bf_bits(f)), " bits"])

# (raw & ~(mask << lo)) | (encoded << lo), split so the `~(mask << lo)` term is
# named: at four levels of nesting a missing paren is a compile error that reads
# like a missing function.
def bf_set.masked(+f: Fld, +raw: U32) -> U32:
  U32.and(raw, U32.not(U32.shln(bf_mask(f), U32.to_nat(Fld.lo(f)))))

def bf_set.placed(f: Fld, enc: U32) -> U32: U32.shln(enc, U32.to_nat(Fld.lo(f)))

def bor(a: U32, b: U32) -> U32: U32.or(a, b)

def bf_set.go(bad: Bool, +f: Fld, raw: U32, enc: U32) -> Res:
  match bad:
    case True{}: Bad{bf_set_msg(f, enc)}
    case False{}: Res{bor(bf_set.masked(f, raw), bf_set.placed(f, enc)), ""}

# `field '{self.name}': value {encoded} doesn't fit in {hi - lo + 1} bits`
# (:118). The NAME is in the message, so a transposed `_fields` order shows up
# in the text and not only in the value.

def bf_set(+f: Fld, raw: U32, +enc: U32, enc_neg: Bool) -> Res:
  bf_set.go(Bool.or(enc_neg, U32.is_gt(U32.and(enc, bf_mask(f)), bf_mask(f))), f, raw, enc)

def base_size(hi_max: U32) -> U32: U32.div(U32.add(hi_max, BASE_SIZE_ROUND()), BASE_SIZE_DIV())

# ===========================================================================
# THE FIELD CLASSES' `encode`. Each is the class's OWN rule, and a swapped pair
# here writes the wrong bits into the wrong field, so each is gated against
# CPython over a range that crosses every branch.
# ===========================================================================

# `SrcField.encode` (:161-171). FOUR cases, in this order, and the order is
# load-bearing because a `Reg` is also an int in Python's duck-typing sense:
#
#   Reg        -> val.offset
#   float      -> _FLOAT_ENC.get(val, 255)          (:164)  THE FLOAT WALL
#   0 <= v<=64 -> 128 + v                            (:165)
#   -16 <= v<0 -> 192 - v                            (:166)
#   any int    -> 255  (literal)                     (:167)
#   else       -> TypeError                          (:168)
#
# then `offset - _valid_range[0]` (:171), which is 0 for a plain SrcField and
# -256 for a VGPRField. `enc_off` is that offset and `enc_kind` says which case
# fired, so the refusal and the value are separate facts.
# `SrcField.encode` (:161-171). FOUR cases, in this order, and the ORDER is
# load-bearing: a `Reg` is tested before an `int` (:163 vs :165), and a `float`
# before both (:164).
#
#   Reg        -> val.offset                              (:163)
#   float      -> _FLOAT_ENC.get(val, 255)                (:164)  THE FLOAT WALL
#   0 <= v<=64 -> 128 + v                                 (:165)
#   -16 <= v<0 -> 192 - v                                 (:166)
#   any int    -> 255, the literal marker                 (:167)
# then the range test against `_valid_range` (:169-170), THEN
# `return offset - self._valid_range[0]` (:171) -- which is 0 for a SrcField
# and -256 for a VGPRField, so the subtraction is not a no-op in general.
#
# ---------------------------------------------------------------------------
# THE FLOAT WALL, NAMED, WITH ITS LINE AND ITS REASON.
#
# :164 is `isinstance(val, float)` and :164's other half looks a float up in
# `_FLOAT_ENC`. Bend here cannot construct an `F32` at all: `F32` is
# `F32{data: Word(32n)}` and `Word` is not exported -- the identical wall
# `tinybendygrad/tensor.bend:308` and `tinybendygrad/renderer/wgsl.bend:59`
# record, for the identical reason. `_f32` (:147, `struct.pack('f')`) is behind
# the same door, and so is `_needs_literal`'s float arm (:251).
#
# SO WHAT IS PORTED. The TABLE (`_FLOAT_ENC`, both directions) is ported, and so
# is the dispatch: `OV_FLOAT` is a distinct kind, `enc_off`'s float arm is its
# own arm, and an UNKNOWN float answers 255 -- the negative case, which is the
# half of :164 that is a decision rather than a comparison. What is NOT ported
# is deciding, from a float VALUE, which of the eight entries applies: that is
# one `F32` construction, and it is four bytes the seam must hand over.
# `src_ov_float` is the whole of the ported part and its `known` flag IS
# `_FLOAT_ENC.get`'s hit test.
# ---------------------------------------------------------------------------
def src_ov_float(off: U32, known: Bool) -> Ov: Ov{OV_FLOAT(), Bool.pick(U32, known, off, FLOAT_ENC_DEFAULT()), 1, False{}, False{}, False{}}

# the offset an operand encodes to, BEFORE the `_valid_range` subtraction
def enc_off.int.neg(neg: Bool, +n: U32) -> Res:
  match neg:
    case True{}: Res{U32.sub(NEG_OFF_BASE(), n), ""}
    case False{}: Res{LIT_MARKER(), ""}

def inl_neg_val(n: U32) -> Bool: U32.is_ge(n, NEG_MIN())

# :169-171. `offset - _valid_range[0]`, and the range refusal is the message.

def enc_off.int.go(pos: Bool, +n: U32) -> Res:
  match pos:
    case True{}: Res{U32.add(INT_OFF_BASE(), n), ""}
    case False{}: enc_off.int.neg(inl_neg_val(n), n)

def inl_int_val(n: U32) -> Bool: U32.is_le(n, INT_MAX())

def enc_off.int(+n: U32) -> Res: enc_off.int.go(inl_int_val(n), n)

def enc_off.k(k: Nat, +v: Ov) -> Res:
  match k:
    case 0n: Res{0, ""}
    case 1n: Res{Ov.off(v), ""}
    case 2n: enc_off.int(Ov.off(v))
    case 3n: Res{Ov.off(v), ""}
    # `Ov.k` is OV_NONE..OV_FLOAT and nothing else writes an `Ov`, so this arm
    # is unreachable -- and it exists only because Bend wants a total match.
    case _: Res{0, ""}

# `0 <= val <= 64` and `-16 <= val < 0`, held as two's complement because Bend
# has no I32. The two ranges are DISJOINT in U32 -- 0..64 versus 0xFFFFFFF0..FF
# -- so unsigned tests separate them exactly as the Python comparisons do.

def enc_off(+v: Ov) -> Res: enc_off.k(U32.to_nat(Ov.k(v)), v)

def src_encode.fit(inr: Bool, +f: Fld, +off: U32, s: String) -> Res:
  match inr:
    case True{}: Res{U32.sub(off, Fld.rlo(f)), s}
    case False{}: Bad{String.concat([Fld.name(f), ": offset ", U32.show(off), " out of range (", U32.show(Fld.rlo(f)), ", ", U32.show(Fld.rhi(f)), ")"])}

# `SrcField.decode(raw)` (:173) -- `src[raw + _valid_range[0]]`, a ONE-wide
# register at the decoded offset. The SIZE comes from `op_regs` at the use site
# (:184), not here.

def off_in(+off: U32, +f: Fld) -> Bool: Bool.and(U32.is_ge(off, Fld.rlo(f)), U32.is_le(off, Fld.rhi(f)))

def src_encode.range(res: Res, +f: Fld) -> Res:
  match res:
    case Bad{msg}: Bad{msg}
    case Res{+off, s}: src_encode.fit(off_in(off, f), f, off, s)

def src_encode(v: Ov, f: Fld) -> Res: src_encode.range(enc_off(v), f)

def src_decode(raw: U32, f: Fld) -> Rg: Rg{U32.add(raw, Fld.rlo(f)), 1, False{}, False{}, False{}}

# `__init__`'s width check, :155-159. It fires at CLASS-DEFINITION time, so a
# class with the wrong width never exists -- which is why a `SrcField` is always
# 9 bits and a `VGPRField` always 8.
def Fld.valid_n(+f: Fld) -> U32: U32.add(U32.sub(Fld.rhi(f), Fld.rlo(f)), 1)

def src_width_ok(+f: Fld) -> Bool: U32.is_eq(bf_bits(f), Fld.valid_n(f))
def src_width_msg(+f: Fld) -> String:
  String.concat([Fld.name(f), ": field size ", U32.show(bf_bits(f)), " bits (", U32.show(bf_mask(f)), ") doesn't match range (", U32.show(Fld.rlo(f)), ", ", U32.show(Fld.rhi(f)), ") (", U32.show(Fld.valid_n(f)), ")"])

# ===========================================================================
# THE REMAINING FIELD CLASSES. `SrcField` is done; these three are the rest.
# ===========================================================================

# `VGPRField.encode` (:190-198). `SrcField.encode` first, and then the 8-bit
# `.h` opsel bit: `if val.hi and (self.hi - self.lo + 1) == 8`. TWO conditions
# and either alone is not enough -- a `.h` in a 9-bit field adds no bit, and a
# `.h` at index >= 128 REFUSES (:196) because 8 bits cannot hold both.
def vgpr_encode.big.go(big: Bool, enc: U32, e: U32, s: String) -> Res:
  match big:
    case True{}:
      Bad{String.concat(["VGPRField: v[", U32.show(e), "].h not encodable in 8-bit field (v[0:127] only for .h)"])}
    case False{}: Res{enc, s}

# `AlignedSGPRField.encode` (:205-210). FOUR cases, and the FIRST is the one a
# plain reading misses: `if isinstance(val, int) and val == 0: return 0` --
# the bare int ZERO is accepted and encodes as s0, before the Reg test ever
# runs. Then the alignment check, whose shift is `_align.bit_length() - 1`, i.e.
# 1 for align 2 and 2 for align 4 -- NOT the alignment itself.

def vgpr_encode.big(enc: U32, +f: Fld, +e: U32, s: String) -> Res:
  vgpr_encode.big.go(U32.is_ge(e, VGPR_HI_MASK()), enc, e, s)

def vgpr_encode.range(res: Res, +v: Ov, +f: Fld) -> Res:
  match res:
    case Bad{msg}: Bad{msg}
    case Res{+enc, s}: vgpr_encode.big(enc, f, enc, s)

# `v[{encoded}].h not encodable in 8-bit field (v[0:127] only for .h)` (:196)

def vgpr_encode.fit(set: Bool, res: Res, +v: Ov, +f: Fld) -> Res:
  match set:
    case True{}: vgpr_encode.range(res, v, f)
    case False{}: res

def vgpr_or(set: Bool, res: Res, f: Fld) -> Res:
  match res:
    case Bad{msg}: Bad{msg}
    case Res{+enc, s}: Res{Bool.pick(U32, set, U32.or(enc, VGPR_HI_MASK()), enc), s}

def vgpr_encode.hi(+set: Bool, +v: Ov, +f: Fld) -> Res: vgpr_encode.fit(set, vgpr_or(set, src_encode(v, f), f), v, f)

def vgpr_hbit(v: Ov, f: Fld) -> Bool: Bool.and(Ov.hi(v), U32.is_eq(bf_bits(f), VGPR_HI_BITS()))

def vgpr_encode(+v: Ov, +f: Fld) -> Res: vgpr_encode.hi(vgpr_hbit(v, f), v, f)

def al_shift_of(f: Fld) -> U32: U32.sub(Fld.align(f), 1)

def al_encode.why(notsgpr: Bool, +v: Ov, +f: Fld) -> Res:
  match notsgpr:
    case True{}: Bad{String.concat([Fld.name(f), " requires SGPR, got offset ", U32.show(Ov.off(v))])}
    case False{}:
      Bad{String.concat([Fld.name(f), " requires ", U32.show(Fld.align(f)), "-aligned SGPR, got s[", U32.show(Ov.off(v)), "]"])}

# `AlignedSGPRField.decode(raw)` (:211) -- `src[raw << shift]`, a ONE-wide Reg.

def al_sgpr_hi() -> U32: 128

def al_in_sgpr(+v: Ov) -> Bool: Bool.and(U32.is_ge(Ov.off(v), SGPR_VALID_LO()), U32.is_lt(Ov.off(v), al_sgpr_hi()))

def al_encode.chk(ok: Bool, +v: Ov, f: Fld) -> Res:
  match ok:
    case True{}: Res{U32.shrn(Ov.off(v), U32.to_nat(al_shift_of(f))), ""}
    case False{}: al_encode.why(Bool.not(al_in_sgpr(v)), v, f)

def al_aligned(v: Ov, f: Fld) -> Bool: U32.is_eq(U32.and(Ov.off(v), U32.sub(Fld.align(f), 1)), 0)

def al_encode.zero(zero: Bool, +v: Ov, f: Fld) -> Res:
  match zero:
    case True{}: Res{0, ""}
    case False{}: Bad{String.concat([Fld.name(f), " requires Reg, got ", U32.show(Ov.k(v))])}

def al_encode.reg(isreg: Bool, +zero: Bool, +v: Ov, +f: Fld) -> Res:
  match isreg:
    case True{}: al_encode.chk(Bool.and(al_in_sgpr(v), al_aligned(v, f)), v, f)
    case False{}: al_encode.zero(zero, v, f)

def al_is_reg(v: Ov) -> Bool: U32.is_eq(Ov.k(v), OV_REG())

def al_encode.w(zero: Bool, +v: Ov, f: Fld) -> Res: al_encode.reg(al_is_reg(v), zero, v, f)

def al_forms(f: Fld, +v: Ov) -> Bool: Bool.and(U32.is_eq(Ov.k(v), OV_INT()), U32.is_zero(Ov.off(v)))

def al_encode(+v: Ov, +f: Fld) -> Res: al_encode.w(al_forms(f, v), v, f)

def vdsty_hi() -> U32: 512
def al_decode(raw: U32, f: Fld) -> Rg: Rg{U32.shln(raw, U32.to_nat(al_shift_of(f))), 1, False{}, False{}, False{}}

# `VDSTYField.encode` (:223-226) -- `(val.offset - 256) >> 1`, and the offset
# must be a VGPR. `decode` does not exist as a method; `__get__` (:227-232)
# rebuilds `256 + ((raw << 1) | ((vdstx.offset - 256 & 1) ^ 1))`, so the LOW BIT
# comes from `vdstx`, not from `vdsty`. Both halves are gated.
def vdsty_encode.why(isreg: Bool, +v: Ov) -> Res:
  match isreg:
    case True{}: Bad{String.concat(["VDSTYField requires VGPR, got offset ", U32.show(Ov.off(v))])}
    case False{}: Bad{"VDSTYField requires Reg, got int"}

# `__get__` (:227-232): raw -> vgpr_idx = (raw << 1) | ((vdstx.offset - 256 & 1) ^ 1)

def vdsty_encode.chk(ok: Bool, +v: Ov) -> Res:
  match ok:
    case True{}: Res{U32.shrn(U32.sub(Ov.off(v), VDSTY_LO()), VDSTY_SHIFT()), ""}
    case False{}: vdsty_encode.why(U32.is_eq(Ov.k(v), OV_REG()), v)

def vdsty_ok(+v: Ov) -> Bool: Bool.and(U32.is_eq(Ov.k(v), OV_REG()), Bool.and(U32.is_ge(Ov.off(v), VDSTY_LO()), U32.is_lt(Ov.off(v), vdsty_hi())))

def vdsty_encode(+v: Ov) -> Res: vdsty_encode.chk(vdsty_ok(v), v)

def vdsty_low(vdstx_off: U32) -> U32: U32.xor(U32.and(U32.sub(vdstx_off, VDSTY_LO()), 1), VDSTY_XOR())

# `FixedBitField.set` (:126-128) IGNORES the value and writes `self.default`.
# The `assert val is None` is a caller bug, not a data refusal, so the port
# refuses instead of writing the default -- and the gate records CPython's
# AssertionError, which is a raise and not a message.

def vdsty_get(raw: U32, vdstx_off: U32) -> U32:
  U32.add(VDSTY_LO(), U32.or(U32.shln(raw, VDSTY_SHIFT()), vdsty_low(vdstx_off)))

# `(vdstx.offset - 256) & 1) ^ 1` -- the low bit comes from Vdstx and is INVERTED
def fixed_set(enc: U32, wants: U32) -> Bool: Bool.not(U32.is_eq(enc, 0))

# `EnumBitField.encode` (:135-139): a non-member REFUSES with the ENUM's name,
# and a member outside `allowed` REFUSES with the member's own name. TWO
# refusals, and the second one is a policy -- `allowed` is per-encoding.
def enum_encode(enc: U32, is_member: Bool) -> Bool: Bool.not(is_member)

# ===========================================================================
# `Inst` -- :270-456. The LOGIC, with the autogen DATA as arguments.
#
# `_fields` is the field list in DECLARATION order (:274-282), and it is
# load-bearing four times over: `__init__` walks it to place positional args
# (:304-307), walks it again to write every field (:334-335), `__repr__` walks
# it to print in order and strip trailing defaults (:454-455), and
# `_variant_suffix` walks it to find the first 249/250/255 (:431-436). A
# transposed pair is a silently wrong encoding, so `inst_fields` is gated BY
# NAME, in order, as a String.
# ===========================================================================

# ONE field, as the walk needs it: the name, the field, and the value the
# caller supplied. `has` is Python's `vals[name] is None` test.
type Vf is Data:
  Vf{f: Fld, v: Ov, has: Bool}

# the `neg`/`abs`/`opsel` accumulator, :313-324. THREE bitmasks, and the
# three MODIFIERS select them one for one:
#
#   reg.neg   -> neg_bits    |1|2|4 for src0|src1|src2   (:314-319)
#   reg.abs_  -> abs_bits
#   reg.hi    -> opsel_bits
#   vdst.hi   -> opsel_bits | 8                            (:320-321)
#
# so `.hi` NEVER reaches a field's own encoding, and `vdst.hi` is bit 3 while
# `src2.hi` is bit 2 -- four bits for four registers, and reading the mask as a
# shift is the easy wrong answer.
# `for name, bit in [('src0', 0), ('src1', 1), ('src2', 2)]` (:314) -- the
# REGISTER decides which bit, and `.hi` on `vdst` takes bit 3 (:320-321). Four
# registers, four DIFFERENT bits, and reading the bit position as a SHIFT is the
# easy wrong answer. `src_bit` is that table, and it is the ONLY reader of
# MOD_SRC0_BIT / MOD_SRC1_BIT / MOD_SRC2_BIT: without it those three defs were
# DEAD, and the M29 mutations measured exactly that -- three edits to constants
# nothing called moved nothing, which is `schedule/indexing.bend`'s "a def
# nothing calls is invisible to every other check" reproduced.
def src_bit.vdst(rest: U32) -> U32: Bool.pick(U32, String.eq("vdst", "vdst"), MOD_VDST_BIT(), rest)

def src_bit.s2(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src2"), MOD_SRC2_BIT(), rest)

# the three MASKS, over a field list and in dsl.py's order (:313-321).

def src_bit.s1(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src1"), MOD_SRC1_BIT(), rest)

def src_bit.s0(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src0"), MOD_SRC0_BIT(), rest)

def src_bit(+name: String) -> U32:
  src_bit.s2(name, src_bit.s1(name, src_bit.s0(name, src_bit.vdst(0))))

def mod_mask.pick.go(hit: Bool, +bit: U32, +acc: U32) -> U32:
  match hit:
    case True{}: U32.or(acc, bit)
    case False{}: acc

# the `Reg` flag that selects the bit: neg -> neg_bits, abs_ -> abs_bits,
# hi -> opsel_bits (:317-319). Kept separate so the three masks are three defs.

def mod_mask.pick(named: Bool, isreg: Bool, +bit: U32, +acc: U32) -> U32: mod_mask.pick.go(Bool.and(named, isreg), bit, acc)

def mod_mask.one(nm: String, v: Ov, +has: Bool, +bit: U32, +acc: U32) -> U32:
  mod_mask.pick(U32.is_eq(src_bit(nm), bit), Bool.and(has, U32.is_eq(Ov.k(v), OV_REG())), bit, acc)

def mod_mask.go(vfs: List<&2, Vf>, +acc: U32, +bit: U32) -> U32:
  match vfs:
    case Nil{}: acc
    case Vf{f, v, has} <> t: mod_mask.go(t, mod_mask.one(Fld.name(f), v, has, bit, acc), bit)

def mod_mask(bit: U32, vfs: List<&2, Vf>) -> U32: mod_mask.go(vfs, 0, bit)

def mod_neg(+v: Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(Ov.k(v), OV_REG()), Ov.neg(v))), 1, 0)
def mod_ab(+v: Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(Ov.k(v), OV_REG()), Ov.ab(v))), 1, 0)
def mod_hi(+v: Ov, has: Bool) -> U32: Bool.pick(U32, Bool.and(has, Bool.and(U32.is_eq(Ov.k(v), OV_REG()), Ov.hi(v))), 1, 0)

# `vals['neg'] = (vals.get('neg') or 0) | neg_bits` (:322) and the same for
# `abs` and `opsel`. TWO facts and both matter: the `or 0` swallows a zero, and
# the `|` MERGES with a value the caller already gave.
def mod_merge(given: U32, +has: Bool, +bits: U32) -> U32:
  Bool.pick(U32, Bool.and(has, U32.is_zero(bits)), Bool.pick(U32, has, U32.or(given, bits), bits), 0)

# `__init__`'s positional walk (:304-307): `_fields` in order, a FixedBitField
# consuming NOTHING, then kwargs, then the next positional. `skip` is the
# "already consumed" flag that stands in for Python's `iter`.
def bind.take(name: String, f: Fld, kwname: String, kwsz: U32, kwhas: Bool, has: Bool) -> Bool:
  Bool.or(U32.is_eq(Fld.kind(f), K_FIXED()), Bool.or(kwhas, has))

# `not (remaining := list(args_iter))` -- "too many positional args" (:308).
def too_many(n_left: U32) -> Bool: U32.is_gt(n_left, 0)

# the write walk (:334-335): `for name, field in self._fields: self._raw =
# field.set(self._raw, vals[name])`. THE ORDER IS THE ENCODING.
def Vf.f(vf: Vf) -> Fld: match vf: case Vf{f, v, has}: f

def enc_big(+enc: Res, +f: Fld) -> Bool: Bool.not(U32.is_le(Res.v(enc), bf_mask(f)))

def raw_step.set(ok: Bool, +vf: Vf, +raw: U32, +enc: Res) -> Res:
  match ok:
    case True{}: bf_set(Vf.f(vf), raw, Res.v(enc), enc_big(enc, Vf.f(vf)))
    case False{}: Bad{Res.msg(enc)}

def enc_ok(e: Res) -> Bool:
  match e:
    case Res{v, s}: True{}
    case Bad{msg}: False{}

# `encoded < 0 or encoded > self.mask` (:118), held as U32. A negative producer
# has already been `& mask`-ed by :117, so the only live half of the test is
# "bigger than the mask"; `bf_set` re-derives the same predicate, and sharing
# `bf_mask` here is what makes a wrong mask move BOTH rows.

def raw_step.go(+enc: Res, +vf: Vf, +raw: U32) -> Res:
  raw_step.set(enc_ok(enc), vf, raw, enc)

def Vf.v(vf: Vf) -> Ov: match vf: case Vf{f, v, has}: v

def typed_encode(k: Nat, +vf: Vf) -> Res:
  match k:
    case 3n: src_encode(Vf.v(vf), Vf.f(vf))
    case 4n: vgpr_encode(Vf.v(vf), Vf.f(vf))
    case 5n: src_encode(Vf.v(vf), Vf.f(vf))
    case 6n: src_encode(Vf.v(vf), Vf.f(vf))
    case 7n: al_encode(Vf.v(vf), Vf.f(vf))
    case 8n: al_encode(Vf.v(vf), Vf.f(vf))
    case 9n: al_encode(Vf.v(vf), Vf.f(vf))
    case 10n: vdsty_encode(Vf.v(vf))
    case _: Res{Ov.off(Vf.v(vf)), ""}

# `__get__`'s resize skip (:180): `reg.offset not in (124, 125) and not 240 <=
# reg.offset <= 255`. TWO ranges plus TWO singletons, and the `240..255` is the
# float-constant block and the LIT/SDWA/DPP markers.

def fld_encode.k(k: Nat, +vf: Vf) -> Res:
  match k:
    case 0n: Res{Ov.off(Vf.v(vf)), ""}
    case 1n: Res{Fld.dflt(Vf.f(vf)), ""}
    case 2n: Res{Ov.off(Vf.v(vf)), ""}
    case _: typed_encode(U32.to_nat(Fld.kind(Vf.f(vf))), vf)

def fld_encode(+vf: Vf) -> Res: fld_encode.k(U32.to_nat(Fld.kind(Vf.f(vf))), vf)

def raw_step(+vf: Vf, raw: U32) -> Res: raw_step.go(fld_encode(vf), vf, raw)

def Vf.has(vf: Vf) -> Bool: match vf: case Vf{f, v, has}: has
def Vf.of(f: Fld, v: Ov, has: Bool) -> Vf: Vf{f, v, has}

# `fld_encode` -- the DISPATCH over the five classes. A default BitField passes
# its value through (:110-112); a FixedBitField writes `dflt` (:126-128); the
# four typed classes run their own `encode`.
def no_resize(+off: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(off, NORESIZE_A()), U32.is_eq(off, NORESIZE_B())),
         Bool.and(U32.is_ge(off, NORESIZE_C()), U32.is_lt(off, NORESIZE_D())))

# the `op_regs` width check's exemption (:339) -- a DIFFERENT pair of ranges,
# 106..127 and 249..255. Two similar-looking exemption sets in one file, and
# they are NOT the same; the gate has a row for each boundary.
def exempt_width(+off: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(off, EXEMPT_LO1()), U32.is_le(off, EXEMPT_HI1())),
          Bool.and(U32.is_ge(off, EXEMPT_LO2()), U32.is_le(off, EXEMPT_HI2())))

# `_needs_literal` (:248-253). `None` and a `Reg` are NEVER literal; an int is
# literal outside 0..64 and -16..-1; a float is literal when `_FLOAT_ENC` has
# no entry. The int arm is the same pair of range tests `enc_off` uses, and it
# is the same answer, so the two share `inl_int_val` / `inl_neg_val` ON PURPOSE:
# if they ever disagree the file is wrong, and a mutation on one is caught by a
# row on the other.
def needs_literal.k(k: Nat, +v: Ov) -> Bool:
  match k:
    case 0n: False{}
    case 1n: False{}
    case 2n: Bool.not(Bool.or(inl_int_val(Ov.off(v)), inl_neg_val(Ov.off(v))))
    case _: False{}

def needs_literal(+v: Ov) -> Bool: needs_literal.k(U32.to_nat(Ov.k(v)), v)


# ===========================================================================
# `op_bits` / `op_regs` -- :348-381. FIVE ADJUSTMENTS over the XML widths, and
# each is a CONDITIONAL on the op NAME or on the raw word, so each needs its own
# pair of rows: one that fires and one that sits next to it and does not.
#
#   cndmask  / _co_ci_  -> src2 = 32          (:356-357)  RDNA (WAVE32) only
#   VOP3SD              -> sdst = 32          (:359)      by CLASS NAME
#   cmp                 -> vdst = 32          (:360)      RDNA only
#   addr                -> 64 or 32 by saddr  (:363-365)  GLOBAL/FLAT, not SCRATCH
#   vaddr               -> max(1,offen+idxen)*32 (:367-368)
#   f8f6f4              -> src0/src1 by cbsz/blgp (:371-376)
#
# EVERY adjustment is inside `if not self._is_cdna():` EXCEPT the saddr and
# vaddr ones -- so a CDNA instruction gets cndmask/cmp/f8f6f4 differently, and
# the gate has a row for that.
# ===========================================================================
def ADJ_WAVE32() -> U32: 1
def ADJ_IS_CDNA() -> U32: 1

def has_name_bit(name: String, sub: String) -> Bool: String.contains(name, sub)
def is_vop3sd(cls: String) -> Bool: String.contains(cls, "VOP3SD")

# `self.op_name.lower()` -- the tests are all on the LOWERCASE name (:355), so
# `V_CNDMASK_F32` and `V_cndmask_f32` take the same arm and a case-folded name
# would silently take the OTHER one.
def adj_src2_bits(+name: String, has_src2: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_src2, Bool.or(has_name_bit(name, "cndmask"), has_name_bit(name, "_co_ci_"))), ADJ_SRC2_BITS(), 0)

def adj_vdst_bits(name: String, has_vdst: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_vdst, has_name_bit(name, "cmp")), ADJ_VDST_BITS(), 0)

def adj_sdst_bits(cls: String, has_sdst: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_sdst, is_vop3sd(cls)), ADJ_SRC2_BITS(), 0)

# GLOBAL/FLAT: `saddr_val = (self._raw >> saddr.lo) & saddr.mask` (:364) reads
# the ENCODED field, then `64 if saddr_val in (124, 125) else 32` (:365). So the
# trigger is 124 or 125 and nothing else -- 123 and 126 are the negative cases,
# and they are ADJACENT to the positive ones, which is the whole point of
# putting them in the gate.
def adj_addr_bits.y(narrow: Bool) -> U32:
  match narrow:
    case True{}: ADJ_ADDR_BITS2()
    case False{}: ADJ_ADDR_BITS()

# `type(self).__name__ not in ('SCRATCH', 'VSCRATCH')` (:363). A name test, so a
# subclass of SCRATCH is NOT exempt and a class merely NAMED like it is.

def adj_addr_bits.x(nul: Bool, exempt: Bool) -> U32: adj_addr_bits.y(Bool.or(exempt, Bool.not(nul)))

def adj_addr_bits(+saddr_raw: U32, exempt: Bool) -> U32:
  adj_addr_bits.x(Bool.or(U32.is_eq(saddr_raw, ADJ_SADDR_NULL()), U32.is_eq(saddr_raw, ADJ_SADDR_M0())), exempt)

def addr_exempt(+cls: String) -> Bool: Bool.or(String.eq(cls, "SCRATCH"), String.eq(cls, "VSCRATCH"))

# MUBUF/MTBUF: `max(1, self.offen + self.idxen) * 32` (:368). `max(1, ...)` is
# load-bearing: both zero still gives 32, one register, not zero.
def adj_vaddr_bits(offen: U32, idxen: U32) -> U32:
  U32.mul(U32.max(REG_MIN(), U32.add(offen, idxen)), ADJ_VADDR_MULT())

# F8F6F4: `cbsz = getattr(self, 'cbsz') if hasattr(type(self), 'cbsz') else
# (self._raw >> 8) & 0x7` and the same for blgp at 61 (:373-374). TWO sources
# for each and the class-wins one is the FIRST arm of a conditional expression,
# so a class that declares the field and a class that does not read different
# bits of the SAME raw word.
def mfma_bits.c(+blgp: U32) -> U32:
  Bool.pick(U32, U32.is_eq(blgp, MFMA_CBSZ_LO()), MFMA_B1(),
  Bool.pick(U32, U32.is_eq(blgp, 1), MFMA_B2(),
  Bool.pick(U32, U32.is_eq(blgp, 2), MFMA_B3(),
  Bool.pick(U32, U32.is_eq(blgp, 3), MFMA_B4(), MFMA_DEFAULT()))))

def mfma_bits.b(+cbsz: U32, +blgp: U32) -> U32:
  Bool.pick(U32, U32.is_eq(cbsz, MFMA_CBSZ_LO()), mfma_bits.c(blgp),
  Bool.pick(U32, U32.is_eq(cbsz, 1), mfma_bits.c(blgp),
  Bool.pick(U32, U32.is_eq(cbsz, 2), U32.mul(6, REG_STRIDE()), U32.mul(mfma_bits.c(blgp), REG_STRIDE()))))

# `vgprs = {0: 8, 1: 8, 2: 6, 3: 6, 4: 4}` then
# `bits['src0'], bits['src1'] = vgprs.get(cbsz, 8) * 32, vgprs.get(blgp, 8) * 32`
# (:375-376). The `* 32` IS THE PORTED LINE and leaving it off was a silent wrong
# answer in 25 gate rows: `mfma_bits(0,0)` answered 8 where dsl.py answers 256.
def mfma_bits.w(a: U32, b: U32) -> U32: U32.mul(a, REG_STRIDE())

# `vgprs.get(x, 8)` (:376) -- five entries and a DEFAULT of 8 for every other
# value, so cbsz 5 answers 8 and not an error.

def mfma_regs(+x: U32) -> U32:
  Bool.pick(U32, U32.is_eq(x, MFMA_CBSZ_LO()), MFMA_B0(),
  Bool.pick(U32, U32.is_eq(x, 1), MFMA_B1(),
  Bool.pick(U32, U32.is_eq(x, 2), MFMA_B2(),
  Bool.pick(U32, U32.is_eq(x, 3), MFMA_B3(),
  Bool.pick(U32, U32.is_eq(x, 4), MFMA_B4(), MFMA_DEFAULT())))))

def mfma_bits(cbsz: U32, blgp: U32) -> U32:
  mfma_bits.w(mfma_regs(cbsz), mfma_regs(blgp))

def mfma_b_of(cbsz: U32) -> U32: mfma_regs(cbsz)

# the raw-word fallback, for a class with NO declared cbsz/blgp (:373-374)
def mfma_raw_cbsz(raw: U32) -> U32: U32.and(U32.shrn(raw, U32.to_nat(ADJ_CBSZ_SHIFT())), ADJ_MFMA_SEL_MASK())
def mfma_raw_blgp(raw: U32) -> U32: U32.and(U32.shrn(raw, U32.to_nat(ADJ_BLGP_SHIFT())), ADJ_MFMA_SEL_MASK())
def is_f8f6f4(name: String) -> Bool: has_name_bit(name, "f8f6f4")

# `op_regs = {k: max(1, v // 32)}` (:381). The `max(1, ...)` is what makes a
# zero-width operand still one register wide.
def op_regs_of(bits: U32) -> U32: U32.max(REG_MIN(), U32.div(bits, REG_STRIDE()))

# `canonical_op_bits` (:384-389) SEEDS all five canonical names at 32 bits and
# only overwrites on a canonical name -- so an operand dict with no canonical
# name leaves the seed in place, and the seed is NOT derived from anything.
def canon_seed_bits(id: U32) -> U32: CANON_SEED()

# `num_srcs` (:404-410). THREE RUNGS, tested in order, off the OPERAND NAMES
# and not off `op_bits`. 'src2' is the only spelling of the third source; the
# first source has three spellings and the second has three.
def num_srcs.a0(+has_s0: Bool) -> U32: Bool.pick(U32, has_s0, NSRC_ONE(), NSRC_ZERO())

# `_variant_suffix` (:423-437). 255 -> _LIT, 249 -> _SDWA or _DPP8 by arch,
# 250 -> _DPP16, anything else None -- and the FIRST SrcField with one of those
# offsets wins, so the walk is a scan and not a test of the last field.
# The suffix is a STRING or nothing, and "nothing" is `None{}` -- one `Maybe`
# over `Maybe<&2, String>` rather than a new type. An EMPTY string is not the
# same as None and the gate pins both, because a caller that prints the suffix
# would print "" for a variant and nothing for a plain instruction.

def num_srcs.a1(+has_s1: Bool, +has_s0: Bool) -> U32:
  match has_s1:
    case True{}: NSRC_TWO()
    case False{}: num_srcs.a0(has_s0)

def num_srcs.a2(not2: Bool, +has_s1: Bool, +has_s0: Bool) -> U32:
  match not2:
    case True{}: num_srcs.a1(has_s1, has_s0)
    case False{}: NSRC_MAX()

def num_srcs(has_src2: Bool, has_s1: Bool, has_s0: Bool) -> U32:
  num_srcs.a2(Bool.not(has_src2), has_s1, has_s0)

def vs_off.k(k: Nat, +off: U32, is_cdna: Bool) -> Maybe<&2, String>:
  match k:
    case 250n: Some{"_DPP16"}
    case 249n: Some{Bool.pick(String, is_cdna, "_SDWA", "_DPP8")}
    case 255n: Some{"_LIT"}
    case _: None{}

def vs_off(+off: U32, is_cdna: Bool) -> Maybe<&2, String>:
  vs_off.k(U32.to_nat(off), off, is_cdna)

def vs_of.go(r: Maybe<&2, String>, dflt: String) -> String:
  match r:
    case Some{s}: s
    case None{}: dflt

def vs_of(r: Maybe<&2, String>) -> String:
  vs_of.go(r, "")


# ===========================================================================
# THE GATE. Every `py=` below was produced by CALLING CPython --
# `.agents/slop/dsl_oracle.py`, which imports `tinygrad/renderer/amd/dsl.py` and
# calls its methods; nothing in this file is transcribed from a Python
# expression. `.agents/slop/dsl_gate.py` diffs the whole `name=value` line.
#
# THE FIXTURES. dsl.py's `Inst` subclasses are autogen (:239-242 plus the per-arch
# ins.py), so the classes here are FIXTURES with LEGAL field widths -- a
# `SrcField` must be 9 bits, a `VGPRField` 8, an `SGPRField` 7, an `SSrcField`
# 8 (:155-159) -- laid out non-overlapping. Their widths are chosen; every
# NUMBER the gate prints about them is dsl.py's arithmetic on those choices.
# ===========================================================================


# THE THREE ROW WRITERS. A row is an `IO(Unit)` that PRINTS, because a `do`
# block cannot bind a non-`Unit` (see fact 1 in the header), so nothing in this
# gate is RETURNED -- every fact is printed and `dsl_gate.py` diffs the lines.
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", u32_text(v)]))

# TWO EQUALITIES plus the refusal one, because the two fields of `Res` answer two
# different questions: `eqr` compares the VALUE, `eqrs` the rendered STRING and
# `eqrm` the refusal TEXT. A renderer gate is STRINGS before booleans --
# `String.concat` drops a literal silently, so a boolean about a string can be
# true while the string is wrong -- and `eqrs` is the one that catches that.
def eqr(+a: Res, +b: Res) -> Bool: U32.is_eq(Res.v(a), Res.v(b))
def eqrs(+a: Res, +b: Res) -> Bool: String.eq(Res.s(a), Res.s(b))
def eqrm(+a: Res, +b: Res) -> Bool: String.eq(Res.msg(a), Res.msg(b))

def Fld.of(nm: String, hi: U32, lo: U32, dflt: U32, kind: U32, rlo: U32, rhi: U32, align: U32) -> Fld:
  Fld{nm, hi, lo, dflt, kind, rlo, rhi, align}

def Fld.plain(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_PLAIN(), 0, 0, 1)
def Fld.fixed(nm: String, hi: U32, lo: U32, dflt: U32) -> Fld: Fld.of(nm, hi, lo, dflt, K_FIXED(), 0, 0, 1)
def Fld.src(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SRC(), SRC_VALID_LO(), SRC_VALID_HI(), 1)
def Fld.vgpr(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_VGPR(), VGPR_VALID_LO(), VGPR_VALID_HI(), 1)
def Fld.sgpr(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SGPR(), SGPR_VALID_LO(), SGPR_VALID_HI(), 1)
def Fld.ssrc(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SSRC(), SSRC_VALID_LO(), SSRC_VALID_HI(), 1)
def Fld.align2(nm: String, hi: U32, lo: U32, al: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_ALIGN(), 0, 0, al)
def Fld.sbase(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SBASE(), 0, 0, ALIGN_SBASE())
def Fld.srsc(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SRSC(), 0, 0, ALIGN_SRSC())
def Fld.vdsty(nm: String) -> Fld: Fld.of(nm, 0, 0, 0, K_VDSTY(), 0, 0, 1)

def Ov.none() -> Ov: Ov{OV_NONE(), 0, 1, False{}, False{}, False{}}
def Ov.reg(off: U32, sz: U32, neg: Bool, ab: Bool, hi: Bool) -> Ov: Ov{OV_REG(), off, sz, neg, ab, hi}
def Ov.int(n: U32) -> Ov: Ov{OV_INT(), n, 1, False{}, False{}, False{}}

# THE VOP2 FIXTURE, fields in DECLARATION order. `op` is a plain BitField here,
# NOT an EnumBitField, because a class whose `op` is a plain int cannot reach
# `self.op_regs` at all (:337 -> :343 needs `.name`) -- so this fixture is the
# "no opcode enum" shape and its rows are about `_fields` order and `fmt`, not
# about `op_bits`.
def VOP2_FIELDS() -> List<&2, Fld>:
  [Fld.fixed("op", 7, 0, 0), Fld.vgpr("vdst", 15, 8), Fld.src("src0", 25, 17),
   Fld.ssrc("src1", 33, 26), Fld.plain("op_sel", 35, 34), Fld.sbase("sdst", 41, 36)]

# the field list AS TEXT, by name and in order -- the gate's answer to "is the
# order right", which a count cannot answer.
def fields_of.go(fs: List<&2, Fld>, +acc: String) -> String:
  match fs:
    case Nil{}: acc
    case Fld{nm, hi, lo, dflt, kind, rlo, rhi, align} <> t:
      fields_of.go(t, String.concat([acc, nm, ":", U32.show(hi), ":", U32.show(lo), ","]))

# `_base_size = (max(f.hi) + 8) // 8` (:282)

def fields_of(fs: List<&2, Fld>) -> String: fields_of.go(fs, "")

def hi_max.go(fs: List<&2, Fld>, +acc: U32) -> U32:
  match fs:
    case Nil{}: acc
    case Fld{nm, hi, lo, dflt, kind, rlo, rhi, align} <> t: hi_max.go(t, U32.max(acc, hi))

# ---------------------------------------------------------------------------
# GATE 1: THE TABLES, BOTH DIRECTIONS, AND ONE ROW PER ENTRY.
#
# `ops_nv`'s audit found 33 of 219 constants wrong in a file already printing
# 590 green rows, and all eleven `CLASS_*` ids among them, because a ONE-WAY
# table cannot see a wrong binding. So every entry gets TWO rows -- the forward
# direction and the reverse -- and the ROW NAME carries the offset CPython
# reports, which makes a wrong constant a NAME MISMATCH and not a moved value.
#
# Written out rather than walked: a walker needs an index into the table, and an
# index that is itself computed is the exact thing that hides a wrong binding.
# ---------------------------------------------------------------------------

def hi_max(fs: List<&2, Fld>) -> U32: hi_max.go(fs, 0)

# ===========================================================================
# THE GATE'S HELPERS. Each exists because a generated row needs it, and NONE of
# them is a re-implementation of a table -- they are RENDERERS, so a gate row
# reads as the CPython value it is compared against. `.agents/slop/dsl_gen.py`
# keeps everything above this block and regenerates everything below.
# ===========================================================================

# `Reg` as CPython's tuple spelling, `f"{r.offset},{r.sz},{r.neg},{r.abs_},{r.hi}"`
# -- and `str(False)` is "False", so the Bool is spelled the Python way.
def bs(b: Bool) -> String: Bool.pick(String, b, "True", "False")

def rg5(+r: Rg) -> String:
  String.concat([u32_text(Rg.off(r)), ",", u32_text(Rg.sz(r)), ",", bs(Rg.neg(r)), ",",
                 bs(Rg.ab(r)), ",", bs(Rg.hi(r))])

def rg2(off: U32, sz: U32) -> String: String.concat([u32_text(off), ",", u32_text(sz)])

def rg_neg(+r: Rg) -> Rg: Rg{Rg.off(r), Rg.sz(r), Bool.not(Rg.neg(r)), Rg.ab(r), Rg.hi(r)}
def rg_ab(+r: Rg) -> Rg: Rg{Rg.off(r), Rg.sz(r), Rg.neg(r), True{}, Rg.hi(r)}
def rg_hi(+r: Rg) -> Rg: Rg{Rg.off(r), Rg.sz(r), Rg.neg(r), Rg.ab(r), True{}}
def rg_lo(+r: Rg) -> Rg: Rg{Rg.off(r), Rg.sz(r), Rg.neg(r), Rg.ab(r), False{}}
def rg_add(+r: Rg, n: U32) -> Rg: Rg{U32.add(Rg.off(r), n), Rg.sz(r), Rg.neg(r), Rg.ab(r), Rg.hi(r)}

# `__eq__` is the 5-tuple (:30-34) -- offset, sz, neg, abs_, hi. A comparison
# that forgets one of the three modifiers would make `-r == r`, which is the
# wrong answer and the one a field COUNT cannot see.
def rg_eq2(+a: Rg, +b: Rg) -> Bool:
  Bool.and(U32.is_eq(Rg.off(a), Rg.off(b)), U32.is_eq(Rg.sz(a), Rg.sz(b)))

# a `BitField` as `hi,lo,default,mask` -- dsl.py:103's four values, in order.

def rg_eq.w(head: Bool, neg: Bool, rest: Bool) -> Bool: Bool.and(head, Bool.and(neg, rest))


# Bend has no `Bool.eq`; `Bool.xor` is false exactly when the two agree, so
# equality is NOT XOR and every Bool comparison in this file goes through `beq`.
def beq(a: Bool, b: Bool) -> Bool: Bool.not(Bool.xor(a, b))

def rg_eq(+a: Rg, +b: Rg) -> Bool:
  rg_eq.w(rg_eq2(a, b), beq(Rg.neg(a), Rg.neg(b)),
          Bool.and(beq(Rg.ab(a), Rg.ab(b)), beq(Rg.hi(a), Rg.hi(b))))

def bfg(+f: Fld) -> String:
  String.concat([u32_text(Fld.hi(f)), ",", u32_text(Fld.lo(f)), ",",
                 u32_text(Fld.dflt(f)), ",", u32_text(bf_mask(f))])

# CPython's `f"{x:#010x}"` -- `0x` and EIGHT hex digits -- so a `set` row is
# compared as TEXT and a one-digit slip in one nibble is visible as text.
def hexn.go(i: Nat, dflt: String) -> String:
  match i:
    case 0n: "0"
    case 1n: "1"
    case 2n: "2"
    case 3n: "3"
    case 4n: "4"
    case 5n: "5"
    case 6n: "6"
    case 7n: "7"
    case 8n: "8"
    case 9n: "9"
    case 10n: "a"
    case 11n: "b"
    case 12n: "c"
    case 13n: "d"
    case 14n: "e"
    case _: dflt

# `BitField.set(raw, val)` (:113-119): the refusal TEXT when the value does not
# fit and CPython's own `#010x` of the result when it does. `enc_neg` is the
# `encoded < 0` arm and is always False here because every producer is unsigned.

def hexn(i: Nat) -> String: hexn.go(i, "f")

def hex1(v: U32) -> String: hexn(U32.to_nat(U32.and(v, 15)))

def hex4(+v: U32) -> String:
  String.concat([hex1(U32.shrn(v, 12n)), hex1(U32.shrn(v, 8n)),
                 hex1(U32.shrn(v, 4n)), hex1(U32.and(v, 15))])

def hex8(+v: U32) -> String:
  String.concat(["0x", hex4(U32.shrn(v, 16n)), hex4(U32.and(v, 65535))])

def bfs.go(over: Bool, raw: U32, val: U32, +f: Fld) -> String:
  match over:
    case True{}: String.concat(["REFUSE:", bf_set_msg(f, val)])
    case False{}: hex8(Res.v(bf_set(f, raw, val, False{})))

# Bend's `Maybe` has no `is_some` here, and `vs_off` answers one.

def bfs(+f: Fld, raw: U32, +val: U32) -> String: bfs.go(Bool.not(U32.is_le(val, bf_mask(f))), raw, val, f)

def is_some.go(m: Maybe<&2, String>, dflt: Bool) -> Bool:
  match m:
    case Some{s}: True{}
    case None{}: dflt

# `int.from_bytes(data[:base_size], 'little')` (:442) -- the DECODE half of
# `from_bytes`, with the `base_size` truncation already applied by the caller.

def is_some(m: Maybe<&2, String>) -> Bool: is_some.go(m, False{})

def from_bytes(w: U32) -> U32: w

# `to_bytes` (:416) is `self._raw.to_bytes(self._base_size, 'little')`, so the
# hex is LITTLE-ENDIAN and exactly `base_size` bytes: the low byte first, which
# is the byte order a naive `hex8(v)` gets backwards. Truncating from the LEFT
# of `hex8` keeps the low bytes, which is the whole of little-endian here.
def bytes_of(v: U32, sz: U32) -> String:
  String.drop(hex8(v), U32.to_nat(U32.sub(8, U32.mul(sz, 2))))

# `raw_walk` -- the `__init__` write walk (:334-335): `for name, field in
# self._fields: self._raw = field.set(self._raw, vals[name])`.
#
# ONE SELF-RECURSIVE DEF, and that is not style. A walk needs a leaf helper to
# lift the `Res` out of `raw_step`, and a leaf that recurses back into the walk
# is MUTUAL RECURSION, which cannot be ordered -- Bend wants every def before its
# first use and a two-def cycle has no such order. So the incoming `Res` IS the
# state: it carries `_raw` in `v` and a pending refusal in `msg`, the walk stops
# the moment a refusal appears, and there is no second def to place.
#
# THE FUEL IS THE LISTS THEMSELVES, not a counter, and that is forced too: inside
# a `case 1n+m:` arm Bend will not let you match an outer parameter, so a Nat
# fuel and a list walk cannot live in the same arm. `ShapeRes.dims` walks the
# same way.
def raw_walk.go(vfs: List<&2, Vf>, prior: Res) -> Res:
  match vfs:
    case Nil{}: prior
    case Vf{f, v, has} <> t:
      match prior:
        case Bad{msg}: Bad{msg}
        case Res{praw, pacc}: raw_walk.go(t, raw_step(Vf.of(f, v, has), praw))

def raw_walk(vfs: List<&2, Vf>) -> Res: raw_walk.go(vfs, Res{0, ""})

# ONE LIST, not two. In Python `_fields` and `vals` are separate and zipped by
# iteration order; here each `Vf` CARRIES its own `Fld`, so there is no zip and
# no second list to get out of step -- and `_fields` ORDER is then visible in
# the `Vf` list's order, which is what `fields_of` prints.

def rws(+res: Res) -> String: String.concat([Res.s(res), "|", hex8(Res.v(res))])

# THE ORDER FIXTURE. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible.
def VOP2_ALL() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.reg(266, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(5, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.int(2), True{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.reg(8, 1, False{}, False{}, False{}), True{})]

def VOP2_NEG() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.reg(266, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, True{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(5, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_HI() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.reg(266, 1, False{}, False{}, True{}), True{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, True{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

# int 64 is the last inlineable positive (:165) and -16 the last inlineable
# negative (:166) -- one row either side of each, because the boundary is where
# an off-by-one in the range test shows and nowhere else.
def VOP2_INT() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.int(64), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.int(4294967280), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_INT65() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.int(65), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_INTN17() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.int(4294967279), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

# THE FLOAT ENCODING PATH. :164 is `_FLOAT_ENC.get(val, 255)`; the first fixture
# supplies a KNOWN float's offset and the second supplies the 255 a float absent
# from `_FLOAT_ENC` gets -- the negative half of the same `.get`.
def VOP2_FCONST() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), src_ov_float(F0_5_OFF(), True{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), src_ov_float(247, True{}), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_FNOLIT() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), src_ov_float(FLOAT_ENC_DEFAULT(), False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_LIT() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(255, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_SDWA() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(249, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

def VOP2_DPP() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.none(), False{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.reg(250, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.none(), False{})]

# `vdst` given TWO registers where `op_regs` says one. The two rows below are the
# EXEMPTION and its opposite: `sdst` at 4 wide with offset 124 is exempt
# (:339's `106 <= offset <= 127`), `src0` at 8 wide with offset 250 is exempt
# (`:339`'s `249 <= offset <= 255`), and `vdst` at 2 wide is NOT.
def VOP2_BIG() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.reg(266, 2, False{}, False{}, False{}), True{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(3, 1, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.reg(124, 4, False{}, False{}, False{}), True{})]

def VOP2_BIG2() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 0), Ov.int(0), True{}),
   Vf.of(Fld.vgpr("vdst", 15, 8), Ov.reg(266, 2, False{}, False{}, False{}), True{}),
   Vf.of(Fld.src("src0", 25, 17), Ov.reg(250, 8, False{}, False{}, False{}), True{}),
   Vf.of(Fld.ssrc("src1", 33, 26), Ov.none(), False{}),
   Vf.of(Fld.plain("op_sel", 35, 34), Ov.none(), False{}),
   Vf.of(Fld.sbase("sdst", 41, 36), Ov.reg(4, 1, False{}, False{}, False{}), True{})]

# THE ORDER FIXTURES. Two fields at the SAME bits with different names: `set` is
# a masked overwrite, so the LAST write wins and the field ORDER decides the
# word. Swap the two and every value-identical gate row on this file still
# passes, which is exactly why this fixture exists -- a transposed pair in
# `_fields` is otherwise invisible to a count, to a graph shape, and to a diff of
# the final word.
def ORD_FIELDS() -> List<&2, Fld>: [Fld.plain("first", 7, 0), Fld.plain("second", 7, 0)]
def ORD_FIELDS_SWAP() -> List<&2, Fld>: [Fld.plain("second", 7, 0), Fld.plain("first", 7, 0)]
def ORD_VALS() -> List<&2, Vf>:
  [Vf.of(Fld.plain("first", 7, 0), Ov.int(11), True{}), Vf.of(Fld.plain("second", 7, 0), Ov.int(22), True{})]
def ORD_VALS_SWAP() -> List<&2, Vf>:
  [Vf.of(Fld.plain("second", 7, 0), Ov.int(22), True{}), Vf.of(Fld.plain("first", 7, 0), Ov.int(11), True{})]

# THE `Inst` FIXTURES for `_base_size` and `to_bytes`. Each is ONE field apart,
# so `(max(hi) + 8) // 8` (:282) crosses a byte boundary at each one, and
# F64I's 32-bit-wide `lit` at [63:32] is the widest legal field there is.
def F32_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5), Fld.plain("A", 23, 8)]
def F32_VALS() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 5), Ov.int(0), True{}), Vf.of(Fld.plain("A", 23, 8), Ov.int(4660), True{})]

def F16_FIELDS() -> List<&2, Fld>:
  [Fld.fixed("op", 7, 0, 5), Fld.plain("A", 23, 8), Fld.plain("B", 31, 16)]
def F16_VALS() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 5), Ov.int(0), True{}), Vf.of(Fld.plain("A", 23, 8), Ov.int(4660), True{}),
   Vf.of(Fld.plain("B", 31, 16), Ov.int(22136), True{})]

def F8_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5)]
def F8_VALS() -> List<&2, Vf>: [Vf.of(Fld.fixed("op", 7, 0, 5), Ov.int(0), True{})]

def F40_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5), Fld.plain("A", 39, 8)]
def F40_VALS() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 5), Ov.int(0), True{}), Vf.of(Fld.plain("A", 39, 8), Ov.int(1193046), True{})]

def F64_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5), Fld.plain("lit", 63, 32)]
def F64_VALS() -> List<&2, Vf>:
  [Vf.of(Fld.fixed("op", 7, 0, 5), Ov.int(0), True{}), Vf.of(Fld.plain("lit", 63, 32), Ov.int(305419896), True{})]
# ===========================================================================
# THE RENDERERS THE GENERATED ROWS NEED. Injected with the fixtures for the
# same reason: the generator replaces everything from its marker down, so a def
# written after the marker is deleted on the next run. Measured, twice.
# ===========================================================================

# `_canonical_name` prints the NAME or `None` -- CPython's own answer, and the
# gate compares THAT and not a slot index. The index is still reachable through
# `canon_name`, so the table is readable in both directions; only the REFUSAL
# needs a different spelling, because "not a canonical operand" is `None`.
def canon_of_text.pick(miss: Bool, id: U32) -> String:
  match miss:
    case True{}: "None"
    case False{}: canon_name(id)

# A refusal is CPython's `RuntimeError` TEXT behind the `REFUSE:` marker the
# oracle adds, so a refusal row and a value row have the same shape and a
# missing `REFUSE:` is itself a mismatch.

def canon_of_text(+id: U32) -> String: canon_of_text.pick(U32.is_eq(id, DFLT_OFF()), id)

def ref(msg: String) -> String: String.concat(["REFUSE:", msg])

# `SrcField._FLOAT_ENC` is a float -> int dict, so its REVERSE prints the
# float's own spelling as the table holds it: "0.5", "-0.5", "1.0" ... Those are
# the SAME eight strings `_NAMES` holds at dsl.py:14, which is what makes the
# pair a cross-check of TWO SPELLINGS rather than a second copy of one table. A
# name absent from the table answers 255, and 255 is not a spelling, so it is
# written as the number -- that is the negative row's whole content.
def FLOAT_SPELL.go(off: Nat, dflt: String) -> String:
  match off:
    case 240n: "0.5"
    case 241n: "-0.5"
    case 242n: "1.0"
    case 243n: "-1.0"
    case 244n: "2.0"
    case 245n: "-2.0"
    case 246n: "4.0"
    case 247n: "-4.0"
    case _: dflt

# `Res` as ONE printed answer: the value when it succeeded, `REFUSE:<text>` when
# it did not. CPython's oracle prints the same shape, so a row that should have
# refused and did not is a PREFIX difference and not a silent zero.

def FLOAT_SPELL(off: U32) -> String: FLOAT_SPELL.go(U32.to_nat(off), "")

def float_enc_of_text.pick2(miss: Bool, off: U32) -> String:
  match miss:
    case True{}: "255"
    case False{}: FLOAT_SPELL(off)

def float_enc_of_text(+nm: String) -> String: float_enc_of_text.pick2(U32.is_eq(float_enc_of(nm), DFLT_OFF()), float_enc_of(nm))

def enc_text.go(ok: Bool, +res: Res) -> String:
  match ok:
    case True{}: u32_text(Res.v(res))
    case False{}: ref(Res.msg(res))

# `_variant_suffix` answers a suffix or `None`, and CPython prints `None` for the
# absent case. An empty string is NOT the same answer, so the port prints
# "None" and `vs_of` stays available for a caller that wants "".

def enc_text(+res: Res) -> String: enc_text.go(enc_ok(res), res)

def vs_text.go(m: Maybe<&2, String>, dflt: String) -> String:
  match m:
    case Some{s}: s
    case None{}: dflt

# ==== GATE BODY (generated by .agents/slop/dsl_gen.py) ====

# --- T  THE FOUR TABLES, BOTH DIRECTIONS -------------------------------

def vs_text(m: Maybe<&2, String>) -> String: vs_text.go(m, "None")

def g_tables() -> IO(Unit):
  do IO<Unit>:
    srow("names_count", nat_text(reg_names_n()))
    srow("names_rev_count", nat_text(reg_names_n()))
    srow("names_fwd_102", reg_name_of(102))
    srow("names_fwd_103", reg_name_of(103))
    srow("names_fwd_104", reg_name_of(104))
    srow("names_fwd_105", reg_name_of(105))
    srow("names_fwd_106", reg_name_of(106))
    srow("names_fwd_107", reg_name_of(107))
    srow("names_fwd_124", reg_name_of(124))
    srow("names_fwd_125", reg_name_of(125))
    srow("names_fwd_126", reg_name_of(126))
    srow("names_fwd_127", reg_name_of(127))
    srow("names_fwd_233", reg_name_of(233))
    srow("names_fwd_234", reg_name_of(234))
    srow("names_fwd_235", reg_name_of(235))
    srow("names_fwd_236", reg_name_of(236))
    srow("names_fwd_237", reg_name_of(237))
    srow("names_fwd_238", reg_name_of(238))
    srow("names_fwd_240", reg_name_of(240))
    srow("names_fwd_241", reg_name_of(241))
    srow("names_fwd_242", reg_name_of(242))
    srow("names_fwd_243", reg_name_of(243))
    srow("names_fwd_244", reg_name_of(244))
    srow("names_fwd_245", reg_name_of(245))
    srow("names_fwd_246", reg_name_of(246))
    srow("names_fwd_247", reg_name_of(247))
    srow("names_fwd_248", reg_name_of(248))
    srow("names_fwd_249", reg_name_of(249))
    srow("names_fwd_250", reg_name_of(250))
    srow("names_fwd_251", reg_name_of(251))
    srow("names_fwd_252", reg_name_of(252))
    srow("names_fwd_253", reg_name_of(253))
    srow("names_fwd_254", reg_name_of(254))
    srow("names_fwd_255", reg_name_of(255))
    srow("names_rev_FLAT_SCRATCH_LO", u32_text(reg_off_of("FLAT_SCRATCH_LO")))
    srow("names_rev_FLAT_SCRATCH_HI", u32_text(reg_off_of("FLAT_SCRATCH_HI")))
    srow("names_rev_XNACK_MASK_LO", u32_text(reg_off_of("XNACK_MASK_LO")))
    srow("names_rev_XNACK_MASK_HI", u32_text(reg_off_of("XNACK_MASK_HI")))
    srow("names_rev_VCC_LO", u32_text(reg_off_of("VCC_LO")))
    srow("names_rev_VCC_HI", u32_text(reg_off_of("VCC_HI")))
    srow("names_rev_NULL", u32_text(reg_off_of("NULL")))
    srow("names_rev_M0", u32_text(reg_off_of("M0")))
    srow("names_rev_EXEC_LO", u32_text(reg_off_of("EXEC_LO")))
    srow("names_rev_EXEC_HI", u32_text(reg_off_of("EXEC_HI")))
    srow("names_rev_DPP8", u32_text(reg_off_of("DPP8")))
    srow("names_rev_DPP8FI", u32_text(reg_off_of("DPP8FI")))
    srow("names_rev_SHARED_BASE", u32_text(reg_off_of("SHARED_BASE")))
    srow("names_rev_SHARED_LIMIT", u32_text(reg_off_of("SHARED_LIMIT")))
    srow("names_rev_PRIVATE_BASE", u32_text(reg_off_of("PRIVATE_BASE")))
    srow("names_rev_PRIVATE_LIMIT", u32_text(reg_off_of("PRIVATE_LIMIT")))
    srow("names_rev_0.5", u32_text(reg_off_of("0.5")))
    srow("names_rev_-0.5", u32_text(reg_off_of("-0.5")))
    srow("names_rev_1.0", u32_text(reg_off_of("1.0")))
    srow("names_rev_-1.0", u32_text(reg_off_of("-1.0")))
    srow("names_rev_2.0", u32_text(reg_off_of("2.0")))
    srow("names_rev_-2.0", u32_text(reg_off_of("-2.0")))
    srow("names_rev_4.0", u32_text(reg_off_of("4.0")))
    srow("names_rev_-4.0", u32_text(reg_off_of("-4.0")))
    srow("names_rev_INV_2PI", u32_text(reg_off_of("INV_2PI")))
    srow("names_rev_SDWA", u32_text(reg_off_of("SDWA")))
    srow("names_rev_DPP", u32_text(reg_off_of("DPP")))
    srow("names_rev_VCCZ", u32_text(reg_off_of("VCCZ")))
    srow("names_rev_EXECZ", u32_text(reg_off_of("EXECZ")))
    srow("names_rev_SCC", u32_text(reg_off_of("SCC")))
    srow("names_rev_SRC_LDS_DIRECT", u32_text(reg_off_of("SRC_LDS_DIRECT")))
    srow("names_rev_LIT", u32_text(reg_off_of("LIT")))
    srow("pairs_count", nat_text(reg_pairs_n()))
    srow("pairs_fwd_106", pair_name_of(106))
    srow("pairs_fwd_126", pair_name_of(126))
    srow("pairs_rev_VCC", u32_text(pair_off_of("VCC")))
    srow("pairs_rev_EXEC", u32_text(pair_off_of("EXEC")))
    srow("names_rev_0.5", u32_text(reg_off_of("0.5")))
    srow("names_rev_-0.5", u32_text(reg_off_of("-0.5")))
    srow("names_rev_1.0", u32_text(reg_off_of("1.0")))
    srow("names_rev_-1.0", u32_text(reg_off_of("-1.0")))
    srow("names_rev_2.0", u32_text(reg_off_of("2.0")))
    srow("names_rev_-2.0", u32_text(reg_off_of("-2.0")))
    srow("names_rev_4.0", u32_text(reg_off_of("4.0")))
    srow("names_rev_-4.0", u32_text(reg_off_of("-4.0")))
    srow("float_enc_count", nat_text(float_enc_n()))
    srow("floatenc_r_240", float_enc_of_text("0.5"))
    srow("floatenc_r_241", float_enc_of_text("-0.5"))
    srow("floatenc_r_242", float_enc_of_text("1.0"))
    srow("floatenc_r_243", float_enc_of_text("-1.0"))
    srow("floatenc_r_244", float_enc_of_text("2.0"))
    srow("floatenc_r_245", float_enc_of_text("-2.0"))
    srow("floatenc_r_246", float_enc_of_text("4.0"))
    srow("floatenc_r_247", float_enc_of_text("-4.0"))
    srow("canon_src0", canon_of_text(canon_of("src0")))
    srow("canon_vsrc0", canon_of_text(canon_of("vsrc0")))
    srow("canon_ssrc0", canon_of_text(canon_of("ssrc0")))
    srow("canon_src1", canon_of_text(canon_of("src1")))
    srow("canon_vsrc1", canon_of_text(canon_of("vsrc1")))
    srow("canon_ssrc1", canon_of_text(canon_of("ssrc1")))
    srow("canon_src2", canon_of_text(canon_of("src2")))
    srow("canon_vdst", canon_of_text(canon_of("vdst")))
    srow("canon_sdst", canon_of_text(canon_of("sdst")))
    srow("canon_sdata", canon_of_text(canon_of("sdata")))
    srow("canon_data", canon_of_text(canon_of("data")))
    srow("canon_vdata", canon_of_text(canon_of("vdata")))
    srow("canon_data0", canon_of_text(canon_of("data0")))
    srow("canon_vsrc", canon_of_text(canon_of("vsrc")))
    srow("canon_op", canon_of_text(canon_of("op")))
    srow("canon_off", canon_of_text(canon_of("off")))
    srow("canon_abs", canon_of_text(canon_of("abs")))
    srow("canon_neg", canon_of_text(canon_of("neg")))
    srow("canon_opsel", canon_of_text(canon_of("opsel")))
    srow("canon_src3", canon_of_text(canon_of("src3")))
    srow("canon_Src0", canon_of_text(canon_of("Src0")))
    srow("canon_Src1", canon_of_text(canon_of("Src1")))
    srow("canon_S0", canon_of_text(canon_of("S0")))
    srow("canon_xsrc0", canon_of_text(canon_of("xsrc0")))
    srow("canon_rsrc", canon_of_text(canon_of("rsrc")))
    srow("canon_isrc", canon_of_text(canon_of("isrc")))
    srow("canon_sdst_x", canon_of_text(canon_of("sdst_x")))
    srow("canon_S0", canon_of_text(canon_of("S0")))
    srow("canon_out_s0", canon_of_text(canon_of("s0")))
    srow("canon_out_s1", canon_of_text(canon_of("s1")))
    srow("canon_out_s2", canon_of_text(canon_of("s2")))
    srow("canon_out_d", canon_of_text(canon_of("d")))
    srow("canon_out_data", canon_of_text(canon_of("data")))
    srow("names_fwd_absent", reg_name_of(209))
    srow("names_rev_absent", u32_text(reg_off_of("NOSUCHREG")))
    srow("pairs_rev_absent", u32_text(pair_off_of("NOSUCHPAIR")))
    srow("floatenc_r_absent", float_enc_of_text("3.0"))

# --- C  THE REGISTER CONSTANTS AND THE SPACE BOUNDARIES ----------------
def g_const() -> IO(Unit):
  do IO<Unit>:
    srow("const_VCC_LO", rg5(Rg{VCC_LO(), 1, False{}, False{}, False{}}))
    srow("const_VCC_HI", rg5(Rg{VCC_HI(), 1, False{}, False{}, False{}}))
    srow("const_NULL", rg5(Rg{NULL_OFF(), 1, False{}, False{}, False{}}))
    srow("const_OFF", rg5(Rg{OFF_OFF(), 1, False{}, False{}, False{}}))
    srow("const_M0", rg5(Rg{M0_OFF(), 1, False{}, False{}, False{}}))
    srow("const_EXEC_LO", rg5(Rg{EXEC_LO(), 1, False{}, False{}, False{}}))
    srow("const_EXEC_HI", rg5(Rg{EXEC_HI(), 1, False{}, False{}, False{}}))
    srow("const_INV_2PI", rg5(Rg{INV_2PI_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SDWA", rg5(Rg{SDWA_OFF(), 1, False{}, False{}, False{}}))
    srow("const_DPP", rg5(Rg{DPP_OFF(), 1, False{}, False{}, False{}}))
    srow("const_DPP16", rg5(Rg{DPP16_OFF(), 1, False{}, False{}, False{}}))
    srow("const_VCCZ", rg5(Rg{VCCZ_OFF(), 1, False{}, False{}, False{}}))
    srow("const_EXECZ", rg5(Rg{EXECZ_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SCC", rg5(Rg{SCC_OFF(), 1, False{}, False{}, False{}}))
    srow("const_SRC_LDS_DIRECT", rg5(Rg{SRC_LDS_DIRECT_OFF(), 1, False{}, False{}, False{}}))
    srow("const_LIT", rg5(Rg{LIT_OFF(), 1, False{}, False{}, False{}}))
    row("alias_null_off", U32.is_eq(NULL_OFF(), OFF_OFF()))
    row("alias_dpp_dpp16", U32.is_eq(DPP_OFF(), DPP16_OFF()))
    row("alias_vcc_pair", U32.is_eq(VCC_OFF(), VCC_LO()))
    row("alias_exec_pair", U32.is_eq(EXEC_OFF(), EXEC_LO()))
    srow("const_src", rg5(Rg{SRC_LO(), SRC_SZ(), False{}, False{}, False{}}))
    srow("const_s", rg5(Rg{S_LO(), S_SZ(), False{}, False{}, False{}}))
    srow("const_ttmp", rg5(Rg{TTMP_LO(), TTMP_SZ(), False{}, False{}, False{}}))
    srow("const_v", rg5(Rg{V_LO(), V_SZ(), False{}, False{}, False{}}))
    srow("src_at_0", rg2(0, 1))
    srow("src_at_1", rg2(1, 1))
    srow("src_at_63", rg2(63, 1))
    srow("src_at_104", rg2(104, 1))
    srow("src_at_105", rg2(105, 1))
    srow("src_at_106", rg2(106, 1))
    srow("src_at_107", rg2(107, 1))
    srow("src_at_108", rg2(108, 1))
    srow("src_at_123", rg2(123, 1))
    srow("src_at_124", rg2(124, 1))
    srow("src_at_125", rg2(125, 1))
    srow("src_at_126", rg2(126, 1))
    srow("src_at_127", rg2(127, 1))
    srow("src_at_128", rg2(128, 1))
    srow("src_at_129", rg2(129, 1))
    srow("src_at_192", rg2(192, 1))
    srow("src_at_193", rg2(193, 1))
    srow("src_at_208", rg2(208, 1))
    srow("src_at_209", rg2(209, 1))
    srow("src_at_239", rg2(239, 1))
    srow("src_at_240", rg2(240, 1))
    srow("src_at_248", rg2(248, 1))
    srow("src_at_255", rg2(255, 1))
    srow("src_at_256", rg2(256, 1))
    srow("src_at_257", rg2(257, 1))
    srow("src_at_510", rg2(510, 1))
    srow("src_at_511", rg2(511, 1))

# --- R  Reg.__getitem__ -- index, slice, and BOTH refusals -------------
def g_get() -> IO(Unit):
  do IO<Unit>:
    srow("get_at_0", rg2(0, 1))
    srow("get_at_1", rg2(1, 1))
    srow("get_at_63", rg2(63, 1))
    srow("get_at_104", rg2(104, 1))
    srow("get_at_105", rg2(105, 1))
    srow("get_at_106", rg2(106, 1))
    srow("get_at_107", rg2(107, 1))
    srow("get_at_108", rg2(108, 1))
    srow("get_at_123", rg2(123, 1))
    srow("get_at_124", rg2(124, 1))
    srow("get_at_125", rg2(125, 1))
    srow("get_at_126", rg2(126, 1))
    srow("get_at_127", rg2(127, 1))
    srow("get_at_128", rg2(128, 1))
    srow("get_at_129", rg2(129, 1))
    srow("get_at_192", rg2(192, 1))
    srow("get_at_193", rg2(193, 1))
    srow("get_at_208", rg2(208, 1))
    srow("get_at_209", rg2(209, 1))
    srow("get_at_239", rg2(239, 1))
    srow("get_at_240", rg2(240, 1))
    srow("get_at_248", rg2(248, 1))
    srow("get_at_255", rg2(255, 1))
    srow("get_at_256", rg2(256, 1))
    srow("get_at_257", rg2(257, 1))
    srow("get_at_510", rg2(510, 1))
    srow("get_at_511", rg2(511, 1))
    srow("get_slice_0_105", rg2(0, U32.add(U32.sub(105, 0), 1)))
    srow("get_slice_106_107", rg2(106, U32.add(U32.sub(107, 106), 1)))
    srow("get_slice_108_123", rg2(108, U32.add(U32.sub(123, 108), 1)))
    srow("get_slice_126_127", rg2(126, U32.add(U32.sub(127, 126), 1)))
    srow("get_slice_256_511", rg2(256, U32.add(U32.sub(511, 256), 1)))
    srow("get_slice_0_511", rg2(0, U32.add(U32.sub(511, 0), 1)))
    srow("get_slice_default", rg2(0, 512))
    srow("get_neg_index", ref(Res.msg(reg_at(4294967295, True{}, src_space()))))
    srow("get_index_ge_sz", ref(Res.msg(reg_at(512, False{}, src_space()))))
    srow("get_slice_stop_ge_sz", ref(Res.msg(reg_slice_start(src_space(), 0, 512))))
    srow("get_slice_neg_start", ref(Res.msg(reg_slice(4294967295, True{}, True{}, 5, False{}, True{}, src_space()))))
    srow("get_ok_511", Res.s(reg_at(511, False{}, src_space())))
    srow("get_ok_0", Res.s(reg_at(0, False{}, src_space())))

# --- F  Reg.fmt -- EVERY ARM, at sz 1 and sz>1, upper and not ----------
def g_fmt() -> IO(Unit):
  do IO<Unit>:
    srow("fmt_0_1", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_0_1", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_0_1", Res.msg(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_0_4", Res.s(reg_fmt(Rg{0, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_0_4", Res.s(reg_fmt(Rg{0, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_0_4", Res.msg(reg_fmt(Rg{0, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_1_2", Res.s(reg_fmt(Rg{1, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_1_2", Res.s(reg_fmt(Rg{1, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_1_2", Res.msg(reg_fmt(Rg{1, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_105_1", Res.msg(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_1", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_1", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_1", Res.msg(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_4", Res.s(reg_fmt(Rg{256, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_4", Res.s(reg_fmt(Rg{256, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_4", Res.msg(reg_fmt(Rg{256, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_300_2", Res.s(reg_fmt(Rg{300, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_300_2", Res.s(reg_fmt(Rg{300, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_300_2", Res.msg(reg_fmt(Rg{300, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_511_1", Res.s(reg_fmt(Rg{511, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_511_1", Res.s(reg_fmt(Rg{511, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_511_1", Res.msg(reg_fmt(Rg{511, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_2", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_2", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_2", Res.msg(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_126_2", Res.s(reg_fmt(Rg{126, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_126_2", Res.s(reg_fmt(Rg{126, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_126_2", Res.msg(reg_fmt(Rg{126, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_1", Res.s(reg_fmt(Rg{106, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_1", Res.s(reg_fmt(Rg{106, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_1", Res.msg(reg_fmt(Rg{106, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_126_1", Res.s(reg_fmt(Rg{126, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_126_1", Res.s(reg_fmt(Rg{126, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_126_1", Res.msg(reg_fmt(Rg{126, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_102_1", Res.s(reg_fmt(Rg{102, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_102_1", Res.s(reg_fmt(Rg{102, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_102_1", Res.msg(reg_fmt(Rg{102, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_103_2", Res.s(reg_fmt(Rg{103, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_103_2", Res.s(reg_fmt(Rg{103, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_103_2", Res.msg(reg_fmt(Rg{103, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_104_1", Res.s(reg_fmt(Rg{104, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_104_1", Res.s(reg_fmt(Rg{104, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_104_1", Res.msg(reg_fmt(Rg{104, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_105_1", Res.s(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_105_1", Res.msg(reg_fmt(Rg{105, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_107_1", Res.s(reg_fmt(Rg{107, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_107_1", Res.s(reg_fmt(Rg{107, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_107_1", Res.msg(reg_fmt(Rg{107, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_233_1", Res.s(reg_fmt(Rg{233, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_233_1", Res.s(reg_fmt(Rg{233, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_233_1", Res.msg(reg_fmt(Rg{233, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_234_1", Res.s(reg_fmt(Rg{234, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_234_1", Res.s(reg_fmt(Rg{234, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_234_1", Res.msg(reg_fmt(Rg{234, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_235_1", Res.s(reg_fmt(Rg{235, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_235_1", Res.s(reg_fmt(Rg{235, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_235_1", Res.msg(reg_fmt(Rg{235, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_236_1", Res.s(reg_fmt(Rg{236, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_236_1", Res.s(reg_fmt(Rg{236, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_236_1", Res.msg(reg_fmt(Rg{236, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_237_1", Res.s(reg_fmt(Rg{237, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_237_1", Res.s(reg_fmt(Rg{237, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_237_1", Res.msg(reg_fmt(Rg{237, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_238_1", Res.s(reg_fmt(Rg{238, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_238_1", Res.s(reg_fmt(Rg{238, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_238_1", Res.msg(reg_fmt(Rg{238, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_240_1", Res.s(reg_fmt(Rg{240, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_240_1", Res.s(reg_fmt(Rg{240, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_240_1", Res.msg(reg_fmt(Rg{240, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_241_1", Res.s(reg_fmt(Rg{241, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_241_1", Res.s(reg_fmt(Rg{241, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_241_1", Res.msg(reg_fmt(Rg{241, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_242_1", Res.s(reg_fmt(Rg{242, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_242_1", Res.s(reg_fmt(Rg{242, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_242_1", Res.msg(reg_fmt(Rg{242, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_243_1", Res.s(reg_fmt(Rg{243, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_243_1", Res.s(reg_fmt(Rg{243, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_243_1", Res.msg(reg_fmt(Rg{243, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_244_1", Res.s(reg_fmt(Rg{244, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_244_1", Res.s(reg_fmt(Rg{244, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_244_1", Res.msg(reg_fmt(Rg{244, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_245_1", Res.s(reg_fmt(Rg{245, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_245_1", Res.s(reg_fmt(Rg{245, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_245_1", Res.msg(reg_fmt(Rg{245, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_246_1", Res.s(reg_fmt(Rg{246, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_246_1", Res.s(reg_fmt(Rg{246, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_246_1", Res.msg(reg_fmt(Rg{246, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_247_1", Res.s(reg_fmt(Rg{247, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_247_1", Res.s(reg_fmt(Rg{247, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_247_1", Res.msg(reg_fmt(Rg{247, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_248_1", Res.s(reg_fmt(Rg{248, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_248_1", Res.s(reg_fmt(Rg{248, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_248_1", Res.msg(reg_fmt(Rg{248, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_249_1", Res.s(reg_fmt(Rg{249, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_249_1", Res.s(reg_fmt(Rg{249, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_249_1", Res.msg(reg_fmt(Rg{249, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_250_1", Res.s(reg_fmt(Rg{250, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_250_1", Res.s(reg_fmt(Rg{250, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_250_1", Res.msg(reg_fmt(Rg{250, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_251_1", Res.s(reg_fmt(Rg{251, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_251_1", Res.s(reg_fmt(Rg{251, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_251_1", Res.msg(reg_fmt(Rg{251, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_252_1", Res.s(reg_fmt(Rg{252, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_252_1", Res.s(reg_fmt(Rg{252, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_252_1", Res.msg(reg_fmt(Rg{252, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_253_1", Res.s(reg_fmt(Rg{253, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_253_1", Res.s(reg_fmt(Rg{253, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_253_1", Res.msg(reg_fmt(Rg{253, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_254_1", Res.s(reg_fmt(Rg{254, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_254_1", Res.s(reg_fmt(Rg{254, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_254_1", Res.msg(reg_fmt(Rg{254, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_255_1", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_255_1", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_255_1", Res.msg(reg_fmt(Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_1", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_1", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_1", Res.msg(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_4", Res.s(reg_fmt(Rg{108, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_4", Res.s(reg_fmt(Rg{108, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_4", Res.msg(reg_fmt(Rg{108, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_115_2", Res.s(reg_fmt(Rg{115, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_115_2", Res.s(reg_fmt(Rg{115, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_115_2", Res.msg(reg_fmt(Rg{115, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_123_1", Res.s(reg_fmt(Rg{123, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_123_1", Res.s(reg_fmt(Rg{123, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_123_1", Res.msg(reg_fmt(Rg{123, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_128_1", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_128_1", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_128_1", Res.msg(reg_fmt(Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_129_1", Res.s(reg_fmt(Rg{129, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_129_1", Res.s(reg_fmt(Rg{129, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_129_1", Res.msg(reg_fmt(Rg{129, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_160_1", Res.s(reg_fmt(Rg{160, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_160_1", Res.s(reg_fmt(Rg{160, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_160_1", Res.msg(reg_fmt(Rg{160, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_192_1", Res.s(reg_fmt(Rg{192, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_192_1", Res.s(reg_fmt(Rg{192, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_192_1", Res.msg(reg_fmt(Rg{192, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_193_1", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_193_1", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_193_1", Res.msg(reg_fmt(Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_194_1", Res.s(reg_fmt(Rg{194, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_194_1", Res.s(reg_fmt(Rg{194, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_194_1", Res.msg(reg_fmt(Rg{194, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_207_1", Res.s(reg_fmt(Rg{207, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_207_1", Res.s(reg_fmt(Rg{207, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_207_1", Res.msg(reg_fmt(Rg{207, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_208_1", Res.s(reg_fmt(Rg{208, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_208_1", Res.s(reg_fmt(Rg{208, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_208_1", Res.msg(reg_fmt(Rg{208, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_209_1", Res.s(reg_fmt(Rg{209, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_209_1", Res.s(reg_fmt(Rg{209, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_209_1", Res.msg(reg_fmt(Rg{209, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_512_1", Res.s(reg_fmt(Rg{512, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_512_1", Res.s(reg_fmt(Rg{512, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_512_1", Res.msg(reg_fmt(Rg{512, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_108_16", Res.s(reg_fmt(Rg{108, 16, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_108_16", Res.s(reg_fmt(Rg{108, 16, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_108_16", Res.msg(reg_fmt(Rg{108, 16, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_256_2", Res.s(reg_fmt(Rg{256, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_256_2", Res.s(reg_fmt(Rg{256, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_256_2", Res.msg(reg_fmt(Rg{256, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmt_106_4", Res.s(reg_fmt(Rg{106, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtp_106_4", Res.s(reg_fmt(Rg{106, 4, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtm_106_4", Res.msg(reg_fmt(Rg{106, 4, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmod_0_1_000", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_000", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_001", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_001", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_010", Res.s(reg_fmt(Rg{0, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_010", Res.s(reg_fmt(Rg{0, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_011", Res.s(reg_fmt(Rg{0, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_011", Res.s(reg_fmt(Rg{0, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_100", Res.s(reg_fmt(Rg{0, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_100", Res.s(reg_fmt(Rg{0, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_101", Res.s(reg_fmt(Rg{0, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_101", Res.s(reg_fmt(Rg{0, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_110", Res.s(reg_fmt(Rg{0, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_110", Res.s(reg_fmt(Rg{0, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_0_1_111", Res.s(reg_fmt(Rg{0, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_0_1_111", Res.s(reg_fmt(Rg{0, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_000", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_000", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_001", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_001", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_010", Res.s(reg_fmt(Rg{256, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_010", Res.s(reg_fmt(Rg{256, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_011", Res.s(reg_fmt(Rg{256, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_011", Res.s(reg_fmt(Rg{256, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_100", Res.s(reg_fmt(Rg{256, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_100", Res.s(reg_fmt(Rg{256, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_101", Res.s(reg_fmt(Rg{256, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_101", Res.s(reg_fmt(Rg{256, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_110", Res.s(reg_fmt(Rg{256, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_110", Res.s(reg_fmt(Rg{256, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_256_1_111", Res.s(reg_fmt(Rg{256, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_256_1_111", Res.s(reg_fmt(Rg{256, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_000", Res.s(reg_fmt(Rg{124, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_000", Res.s(reg_fmt(Rg{124, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_001", Res.s(reg_fmt(Rg{124, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_001", Res.s(reg_fmt(Rg{124, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_010", Res.s(reg_fmt(Rg{124, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_010", Res.s(reg_fmt(Rg{124, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_011", Res.s(reg_fmt(Rg{124, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_011", Res.s(reg_fmt(Rg{124, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_100", Res.s(reg_fmt(Rg{124, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_100", Res.s(reg_fmt(Rg{124, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_101", Res.s(reg_fmt(Rg{124, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_101", Res.s(reg_fmt(Rg{124, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_110", Res.s(reg_fmt(Rg{124, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_110", Res.s(reg_fmt(Rg{124, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_124_1_111", Res.s(reg_fmt(Rg{124, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_124_1_111", Res.s(reg_fmt(Rg{124, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_000", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_000", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_001", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_001", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_010", Res.s(reg_fmt(Rg{106, 2, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_010", Res.s(reg_fmt(Rg{106, 2, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_011", Res.s(reg_fmt(Rg{106, 2, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_011", Res.s(reg_fmt(Rg{106, 2, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_100", Res.s(reg_fmt(Rg{106, 2, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_100", Res.s(reg_fmt(Rg{106, 2, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_101", Res.s(reg_fmt(Rg{106, 2, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_101", Res.s(reg_fmt(Rg{106, 2, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_110", Res.s(reg_fmt(Rg{106, 2, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_110", Res.s(reg_fmt(Rg{106, 2, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_106_2_111", Res.s(reg_fmt(Rg{106, 2, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_106_2_111", Res.s(reg_fmt(Rg{106, 2, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_000", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_000", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_001", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_001", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_010", Res.s(reg_fmt(Rg{108, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_010", Res.s(reg_fmt(Rg{108, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_011", Res.s(reg_fmt(Rg{108, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_011", Res.s(reg_fmt(Rg{108, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_100", Res.s(reg_fmt(Rg{108, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_100", Res.s(reg_fmt(Rg{108, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_101", Res.s(reg_fmt(Rg{108, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_101", Res.s(reg_fmt(Rg{108, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_110", Res.s(reg_fmt(Rg{108, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_110", Res.s(reg_fmt(Rg{108, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_108_1_111", Res.s(reg_fmt(Rg{108, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_108_1_111", Res.s(reg_fmt(Rg{108, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_000", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_000", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_001", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_001", Res.s(reg_fmt(Rg{128, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_010", Res.s(reg_fmt(Rg{128, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_010", Res.s(reg_fmt(Rg{128, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_011", Res.s(reg_fmt(Rg{128, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_011", Res.s(reg_fmt(Rg{128, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_100", Res.s(reg_fmt(Rg{128, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_100", Res.s(reg_fmt(Rg{128, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_101", Res.s(reg_fmt(Rg{128, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_101", Res.s(reg_fmt(Rg{128, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_110", Res.s(reg_fmt(Rg{128, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_110", Res.s(reg_fmt(Rg{128, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_128_1_111", Res.s(reg_fmt(Rg{128, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_128_1_111", Res.s(reg_fmt(Rg{128, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_000", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_000", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_001", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_001", Res.s(reg_fmt(Rg{193, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_010", Res.s(reg_fmt(Rg{193, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_010", Res.s(reg_fmt(Rg{193, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_011", Res.s(reg_fmt(Rg{193, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_011", Res.s(reg_fmt(Rg{193, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_100", Res.s(reg_fmt(Rg{193, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_100", Res.s(reg_fmt(Rg{193, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_101", Res.s(reg_fmt(Rg{193, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_101", Res.s(reg_fmt(Rg{193, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_110", Res.s(reg_fmt(Rg{193, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_110", Res.s(reg_fmt(Rg{193, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_193_1_111", Res.s(reg_fmt(Rg{193, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_193_1_111", Res.s(reg_fmt(Rg{193, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_000", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_000", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_001", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_001", Res.s(reg_fmt(Rg{255, 1, False{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_010", Res.s(reg_fmt(Rg{255, 1, False{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_010", Res.s(reg_fmt(Rg{255, 1, False{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_011", Res.s(reg_fmt(Rg{255, 1, False{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_011", Res.s(reg_fmt(Rg{255, 1, False{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_100", Res.s(reg_fmt(Rg{255, 1, True{}, False{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_100", Res.s(reg_fmt(Rg{255, 1, True{}, False{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_101", Res.s(reg_fmt(Rg{255, 1, True{}, False{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_101", Res.s(reg_fmt(Rg{255, 1, True{}, False{}, True{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_110", Res.s(reg_fmt(Rg{255, 1, True{}, True{}, False{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_110", Res.s(reg_fmt(Rg{255, 1, True{}, True{}, False{}}, 0, True{}, True{})))
    srow("fmtmod_255_1_111", Res.s(reg_fmt(Rg{255, 1, True{}, True{}, True{}}, 0, False{}, False{})))
    srow("fmtmodu_255_1_111", Res.s(reg_fmt(Rg{255, 1, True{}, True{}, True{}}, 0, True{}, True{})))
    srow("fmt_szov_0_1_4", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 4, False{}, False{})))
    srow("fmt_szov_256_1_2", Res.s(reg_fmt(Rg{256, 1, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_106_2_2", Res.s(reg_fmt(Rg{106, 2, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_124_1_4", Res.s(reg_fmt(Rg{124, 1, False{}, False{}, False{}}, 4, False{}, False{})))
    srow("fmt_szov_108_1_2", Res.s(reg_fmt(Rg{108, 1, False{}, False{}, False{}}, 2, False{}, False{})))
    srow("fmt_szov_0_1_0", Res.s(reg_fmt(Rg{0, 1, False{}, False{}, False{}}, 0, False{}, False{})))

# --- M  the modifier flags: __neg__ / __abs__ / .h / .l ----------------
def g_mod() -> IO(Unit):
  do IO<Unit>:
    srow("mod_neg_0_1", rg5(rg_neg(Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_abs_0_1", rg5(rg_ab(Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_h_0_1", rg5(rg_hi(Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_l_0_1", rg5(rg_lo(Rg{0, 1, False{}, False{}, False{}})))
    srow("mod_neg_256_4", rg5(rg_neg(Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_abs_256_4", rg5(rg_ab(Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_h_256_4", rg5(rg_hi(Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_l_256_4", rg5(rg_lo(Rg{256, 4, False{}, False{}, False{}})))
    srow("mod_neg_108_1", rg5(rg_neg(Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_abs_108_1", rg5(rg_ab(Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_h_108_1", rg5(rg_hi(Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_l_108_1", rg5(rg_lo(Rg{108, 1, False{}, False{}, False{}})))
    srow("mod_neg_124_1", rg5(rg_neg(Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_abs_124_1", rg5(rg_ab(Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_h_124_1", rg5(rg_hi(Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_l_124_1", rg5(rg_lo(Rg{124, 1, False{}, False{}, False{}})))
    srow("mod_add_5_2", rg2(U32.add(5, 3), 2))
    srow("eq_self", Bool.show(rg_eq(Rg{1, 2, False{}, False{}, False{}}, Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_sz", Bool.show(rg_eq(Rg{1, 3, False{}, False{}, False{}}, Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_neg", Bool.show(rg_eq(Rg{1, 2, True{}, False{}, False{}}, Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_abs", Bool.show(rg_eq(Rg{1, 2, False{}, True{}, False{}}, Rg{1, 2, False{}, False{}, False{}})))
    srow("eq_hi", Bool.show(rg_eq(Rg{1, 2, False{}, False{}, True{}}, Rg{1, 2, False{}, False{}, False{}})))

# --- B  BitField masks and set, with both refusals ---------------------
def g_bf() -> IO(Unit):
  do IO<Unit>:
    srow("bf_7_0", bfg(Fld.plain("f", 7, 0)))
    urow("bf_mask_7_0", bf_mask(Fld.plain("f", 7, 0)))
    srow("bf_15_8", bfg(Fld.plain("f", 15, 8)))
    urow("bf_mask_15_8", bf_mask(Fld.plain("f", 15, 8)))
    srow("bf_16_8", bfg(Fld.plain("f", 16, 8)))
    urow("bf_mask_16_8", bf_mask(Fld.plain("f", 16, 8)))
    srow("bf_31_16", bfg(Fld.plain("f", 31, 16)))
    urow("bf_mask_31_16", bf_mask(Fld.plain("f", 31, 16)))
    srow("bf_17_16", bfg(Fld.plain("f", 17, 16)))
    urow("bf_mask_17_16", bf_mask(Fld.plain("f", 17, 16)))
    srow("bf_23_8", bfg(Fld.plain("f", 23, 8)))
    urow("bf_mask_23_8", bf_mask(Fld.plain("f", 23, 8)))
    srow("bf_9_0", bfg(Fld.plain("f", 9, 0)))
    urow("bf_mask_9_0", bf_mask(Fld.plain("f", 9, 0)))
    srow("bf_30_24", bfg(Fld.plain("f", 30, 24)))
    urow("bf_mask_30_24", bf_mask(Fld.plain("f", 30, 24)))
    srow("bf_17_9", bfg(Fld.plain("f", 17, 9)))
    urow("bf_mask_17_9", bf_mask(Fld.plain("f", 17, 9)))
    srow("bf_30_0", bfg(Fld.plain("f", 30, 0)))
    urow("bf_mask_30_0", bf_mask(Fld.plain("f", 30, 0)))
    srow("bf_31_0", bfg(Fld.plain("f", 31, 0)))
    urow("bf_mask_31_0", bf_mask(Fld.plain("f", 31, 0)))
    srow("bf_0_0", bfg(Fld.plain("f", 0, 0)))
    urow("bf_mask_0_0", bf_mask(Fld.plain("f", 0, 0)))
    srow("bf_6_0", bfg(Fld.plain("f", 6, 0)))
    urow("bf_mask_6_0", bf_mask(Fld.plain("f", 6, 0)))
    srow("bf_40_32", bfg(Fld.plain("f", 40, 32)))
    urow("bf_mask_40_32", bf_mask(Fld.plain("f", 40, 32)))
    srow("bf_47_32", bfg(Fld.plain("f", 47, 32)))
    urow("bf_mask_47_32", bf_mask(Fld.plain("f", 47, 32)))
    srow("bf_23_16", bfg(Fld.plain("f", 23, 16)))
    urow("bf_mask_23_16", bf_mask(Fld.plain("f", 23, 16)))
    srow("bfset_3_0_0_0", bfs(Fld.plain("f", 3, 0), 0, 0))
    srow("bfset_3_0_0_1", bfs(Fld.plain("f", 3, 0), 0, 1))
    srow("bfset_3_0_0_7", bfs(Fld.plain("f", 3, 0), 0, 7))
    srow("bfset_3_0_0_8", bfs(Fld.plain("f", 3, 0), 0, 8))
    srow("bfset_3_0_0_255", bfs(Fld.plain("f", 3, 0), 0, 255))
    srow("bfset_3_0_0_4294967295", bfs(Fld.plain("f", 3, 0), 0, 4294967295))
    srow("bfset_3_0_3735928559_0", bfs(Fld.plain("f", 3, 0), 3735928559, 0))
    srow("bfset_3_0_3735928559_1", bfs(Fld.plain("f", 3, 0), 3735928559, 1))
    srow("bfset_3_0_3735928559_7", bfs(Fld.plain("f", 3, 0), 3735928559, 7))
    srow("bfset_3_0_3735928559_8", bfs(Fld.plain("f", 3, 0), 3735928559, 8))
    srow("bfset_3_0_3735928559_255", bfs(Fld.plain("f", 3, 0), 3735928559, 255))
    srow("bfset_3_0_3735928559_4294967295", bfs(Fld.plain("f", 3, 0), 3735928559, 4294967295))
    srow("bfset_7_4_0_0", bfs(Fld.plain("f", 7, 4), 0, 0))
    srow("bfset_7_4_0_1", bfs(Fld.plain("f", 7, 4), 0, 1))
    srow("bfset_7_4_0_7", bfs(Fld.plain("f", 7, 4), 0, 7))
    srow("bfset_7_4_0_8", bfs(Fld.plain("f", 7, 4), 0, 8))
    srow("bfset_7_4_0_255", bfs(Fld.plain("f", 7, 4), 0, 255))
    srow("bfset_7_4_0_4294967295", bfs(Fld.plain("f", 7, 4), 0, 4294967295))
    srow("bfset_7_4_3735928559_0", bfs(Fld.plain("f", 7, 4), 3735928559, 0))
    srow("bfset_7_4_3735928559_1", bfs(Fld.plain("f", 7, 4), 3735928559, 1))
    srow("bfset_7_4_3735928559_7", bfs(Fld.plain("f", 7, 4), 3735928559, 7))
    srow("bfset_7_4_3735928559_8", bfs(Fld.plain("f", 7, 4), 3735928559, 8))
    srow("bfset_7_4_3735928559_255", bfs(Fld.plain("f", 7, 4), 3735928559, 255))
    srow("bfset_7_4_3735928559_4294967295", bfs(Fld.plain("f", 7, 4), 3735928559, 4294967295))
    srow("bfset_23_8_0_0", bfs(Fld.plain("f", 23, 8), 0, 0))
    srow("bfset_23_8_0_1", bfs(Fld.plain("f", 23, 8), 0, 1))
    srow("bfset_23_8_0_7", bfs(Fld.plain("f", 23, 8), 0, 7))
    srow("bfset_23_8_0_8", bfs(Fld.plain("f", 23, 8), 0, 8))
    srow("bfset_23_8_0_255", bfs(Fld.plain("f", 23, 8), 0, 255))
    srow("bfset_23_8_0_4294967295", bfs(Fld.plain("f", 23, 8), 0, 4294967295))
    srow("bfset_23_8_3735928559_0", bfs(Fld.plain("f", 23, 8), 3735928559, 0))
    srow("bfset_23_8_3735928559_1", bfs(Fld.plain("f", 23, 8), 3735928559, 1))
    srow("bfset_23_8_3735928559_7", bfs(Fld.plain("f", 23, 8), 3735928559, 7))
    srow("bfset_23_8_3735928559_8", bfs(Fld.plain("f", 23, 8), 3735928559, 8))
    srow("bfset_23_8_3735928559_255", bfs(Fld.plain("f", 23, 8), 3735928559, 255))
    srow("bfset_23_8_3735928559_4294967295", bfs(Fld.plain("f", 23, 8), 3735928559, 4294967295))
    srow("fixed_op7", bfs(Fld.fixed("op", 7, 0, 0), 4294967295, 4294967295))
    srow("fixed_def_op7", u32_text(Fld.dflt(Fld.fixed("op", 7, 0, 0))))
    row("fixed_cls_op7", fixed_set(1, 0))
    srow("fixed_enc33", bfs(Fld.fixed("op", 6, 0, 33), 4294967295, 4294967295))
    srow("fixed_def_enc33", u32_text(Fld.dflt(Fld.fixed("op", 6, 0, 33))))
    row("fixed_cls_enc33", fixed_set(1, 0))
    srow("fixed_enc17", bfs(Fld.fixed("op", 16, 8, 0), 4294967295, 4294967295))
    srow("fixed_def_enc17", u32_text(Fld.dflt(Fld.fixed("op", 16, 8, 0))))
    row("fixed_cls_enc17", fixed_set(1, 0))

# --- E  the five field classes' encode -- one negative per positive ----
def g_enc() -> IO(Unit):
  do IO<Unit>:
    urow("sf_mask_8_0", bf_mask(Fld.src("s0", 8, 0)))
    row("sf_width_8_0", src_width_ok(Fld.src("s0", 8, 0)))
    srow("sf_widthmsg_8_0", src_width_msg(Fld.src("s0", 8, 0)))
    urow("sfenc_8_0_0", Res.v(src_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_1", Res.v(src_encode(Ov.reg(1, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_63", Res.v(src_encode(Ov.reg(63, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_105", Res.v(src_encode(Ov.reg(105, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_106", Res.v(src_encode(Ov.reg(106, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_127", Res.v(src_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_128", Res.v(src_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_255", Res.v(src_encode(Ov.reg(255, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_256", Res.v(src_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_257", Res.v(src_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_511", Res.v(src_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i0", Res.v(src_encode(Ov.int(0), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i1", Res.v(src_encode(Ov.int(1), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i63", Res.v(src_encode(Ov.int(63), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i64", Res.v(src_encode(Ov.int(64), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i65", Res.v(src_encode(Ov.int(65), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967295", Res.v(src_encode(Ov.int(4294967295), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967280", Res.v(src_encode(Ov.int(4294967280), Fld.src("s0", 8, 0))))
    urow("sfenc_8_0_i4294967279", Res.v(src_encode(Ov.int(4294967279), Fld.src("s0", 8, 0))))
    srow("sfdec_8_0_0", rg2(0, 1))
    srow("sfdec_8_0_1", rg2(1, 1))
    srow("sfdec_8_0_105", rg2(105, 1))
    srow("sfdec_8_0_127", rg2(127, 1))
    srow("sfdec_8_0_128", rg2(128, 1))
    srow("sfdec_8_0_255", rg2(255, 1))
    srow("sfdec_8_0_256", rg2(256, 1))
    srow("sfdec_8_0_257", rg2(257, 1))
    srow("sfdec_8_0_511", rg2(511, 1))
    urow("sf_mask_17_9", bf_mask(Fld.src("s0", 17, 9)))
    row("sf_width_17_9", src_width_ok(Fld.src("s0", 17, 9)))
    srow("sf_widthmsg_17_9", src_width_msg(Fld.src("s0", 17, 9)))
    urow("sfenc_17_9_0", Res.v(src_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_1", Res.v(src_encode(Ov.reg(1, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_63", Res.v(src_encode(Ov.reg(63, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_105", Res.v(src_encode(Ov.reg(105, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_106", Res.v(src_encode(Ov.reg(106, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_127", Res.v(src_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_128", Res.v(src_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_255", Res.v(src_encode(Ov.reg(255, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_256", Res.v(src_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_257", Res.v(src_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_511", Res.v(src_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i0", Res.v(src_encode(Ov.int(0), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i1", Res.v(src_encode(Ov.int(1), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i63", Res.v(src_encode(Ov.int(63), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i64", Res.v(src_encode(Ov.int(64), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i65", Res.v(src_encode(Ov.int(65), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967295", Res.v(src_encode(Ov.int(4294967295), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967280", Res.v(src_encode(Ov.int(4294967280), Fld.src("s0", 17, 9))))
    urow("sfenc_17_9_i4294967279", Res.v(src_encode(Ov.int(4294967279), Fld.src("s0", 17, 9))))
    srow("sfdec_17_9_0", rg2(0, 1))
    srow("sfdec_17_9_1", rg2(1, 1))
    srow("sfdec_17_9_105", rg2(105, 1))
    srow("sfdec_17_9_127", rg2(127, 1))
    srow("sfdec_17_9_128", rg2(128, 1))
    srow("sfdec_17_9_255", rg2(255, 1))
    srow("sfdec_17_9_256", rg2(256, 1))
    srow("sfdec_17_9_257", rg2(257, 1))
    srow("sfdec_17_9_511", rg2(511, 1))
    urow("sf_mask_25_17", bf_mask(Fld.src("s0", 25, 17)))
    row("sf_width_25_17", src_width_ok(Fld.src("s0", 25, 17)))
    srow("sf_widthmsg_25_17", src_width_msg(Fld.src("s0", 25, 17)))
    urow("sfenc_25_17_0", Res.v(src_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_1", Res.v(src_encode(Ov.reg(1, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_63", Res.v(src_encode(Ov.reg(63, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_105", Res.v(src_encode(Ov.reg(105, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_106", Res.v(src_encode(Ov.reg(106, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_127", Res.v(src_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_128", Res.v(src_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_255", Res.v(src_encode(Ov.reg(255, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_256", Res.v(src_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_257", Res.v(src_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_511", Res.v(src_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i0", Res.v(src_encode(Ov.int(0), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i1", Res.v(src_encode(Ov.int(1), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i63", Res.v(src_encode(Ov.int(63), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i64", Res.v(src_encode(Ov.int(64), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i65", Res.v(src_encode(Ov.int(65), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967295", Res.v(src_encode(Ov.int(4294967295), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967280", Res.v(src_encode(Ov.int(4294967280), Fld.src("s0", 25, 17))))
    urow("sfenc_25_17_i4294967279", Res.v(src_encode(Ov.int(4294967279), Fld.src("s0", 25, 17))))
    srow("sfdec_25_17_0", rg2(0, 1))
    srow("sfdec_25_17_1", rg2(1, 1))
    srow("sfdec_25_17_105", rg2(105, 1))
    srow("sfdec_25_17_127", rg2(127, 1))
    srow("sfdec_25_17_128", rg2(128, 1))
    srow("sfdec_25_17_255", rg2(255, 1))
    srow("sfdec_25_17_256", rg2(256, 1))
    srow("sfdec_25_17_257", rg2(257, 1))
    srow("sfdec_25_17_511", rg2(511, 1))
    urow("sf_mask_9_1", bf_mask(Fld.src("s0", 9, 1)))
    row("sf_width_9_1", src_width_ok(Fld.src("s0", 9, 1)))
    srow("sf_widthmsg_9_1", src_width_msg(Fld.src("s0", 9, 1)))
    urow("sfenc_9_1_0", Res.v(src_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_1", Res.v(src_encode(Ov.reg(1, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_63", Res.v(src_encode(Ov.reg(63, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_105", Res.v(src_encode(Ov.reg(105, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_106", Res.v(src_encode(Ov.reg(106, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_127", Res.v(src_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_128", Res.v(src_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_255", Res.v(src_encode(Ov.reg(255, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_256", Res.v(src_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_257", Res.v(src_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_511", Res.v(src_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i0", Res.v(src_encode(Ov.int(0), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i1", Res.v(src_encode(Ov.int(1), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i63", Res.v(src_encode(Ov.int(63), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i64", Res.v(src_encode(Ov.int(64), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i65", Res.v(src_encode(Ov.int(65), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967295", Res.v(src_encode(Ov.int(4294967295), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967280", Res.v(src_encode(Ov.int(4294967280), Fld.src("s0", 9, 1))))
    urow("sfenc_9_1_i4294967279", Res.v(src_encode(Ov.int(4294967279), Fld.src("s0", 9, 1))))
    srow("sfdec_9_1_0", rg2(0, 1))
    srow("sfdec_9_1_1", rg2(1, 1))
    srow("sfdec_9_1_105", rg2(105, 1))
    srow("sfdec_9_1_127", rg2(127, 1))
    srow("sfdec_9_1_128", rg2(128, 1))
    srow("sfdec_9_1_255", rg2(255, 1))
    srow("sfdec_9_1_256", rg2(256, 1))
    srow("sfdec_9_1_257", rg2(257, 1))
    srow("sfdec_9_1_511", rg2(511, 1))
    urow("vgpr_mask_7_0", bf_mask(Fld.vgpr("vdst", 7, 0)))
    urow("vgenc_7_0_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_257", Res.v(vgpr_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_383", Res.v(vgpr_encode(Ov.reg(383, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenc_7_0_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenchi_7_0_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenchi_7_0_300", Res.v(vgpr_encode(Ov.reg(300, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenchi_7_0_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgenchi_7_0_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 7, 0))))
    srow("vgencneg_7_0", Res.msg(vgpr_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 7, 0))))
    urow("vgpr_mask_15_8", bf_mask(Fld.vgpr("vdst", 15, 8)))
    urow("vgenc_15_8_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_257", Res.v(vgpr_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_383", Res.v(vgpr_encode(Ov.reg(383, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenc_15_8_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenchi_15_8_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenchi_15_8_300", Res.v(vgpr_encode(Ov.reg(300, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenchi_15_8_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgenchi_15_8_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 15, 8))))
    srow("vgencneg_15_8", Res.msg(vgpr_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 15, 8))))
    urow("vgpr_mask_8_1", bf_mask(Fld.vgpr("vdst", 8, 1)))
    urow("vgenc_8_1_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_257", Res.v(vgpr_encode(Ov.reg(257, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_383", Res.v(vgpr_encode(Ov.reg(383, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenc_8_1_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenchi_8_1_256", Res.v(vgpr_encode(Ov.reg(256, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenchi_8_1_300", Res.v(vgpr_encode(Ov.reg(300, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenchi_8_1_384", Res.v(vgpr_encode(Ov.reg(384, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 8, 1))))
    urow("vgenchi_8_1_511", Res.v(vgpr_encode(Ov.reg(511, 1, False{}, False{}, True{}), Fld.vgpr("vdst", 8, 1))))
    srow("vgencneg_8_1", Res.msg(vgpr_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.vgpr("vdst", 8, 1))))
    srow("afmask_ab", u32_text(bf_mask(Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_0", Res.v(al_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_2", Res.v(al_encode(Ov.reg(2, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_4", Res.v(al_encode(Ov.reg(4, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_8", Res.v(al_encode(Ov.reg(8, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_100", Res.v(al_encode(Ov.reg(100, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_126", Res.v(al_encode(Ov.reg(126, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    urow("afenc_ab_127", Res.v(al_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_zero", enc_text(al_encode(Ov.int(0), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_nonreg", Res.msg(al_encode(Ov.int(7), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_hi", Res.msg(al_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afenc_ab_odd", Res.msg(al_encode(Ov.reg(3, 1, False{}, False{}, False{}), Fld.align2("s", 7, 0, 2))))
    srow("afdec_ab_0", rg2(U32.shln(0, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_1", rg2(U32.shln(1, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_2", rg2(U32.shln(2, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_15", rg2(U32.shln(15, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_31", rg2(U32.shln(31, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_32", rg2(U32.shln(32, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afdec_ab_63", rg2(U32.shln(63, U32.to_nat(al_shift_of(Fld.align2("s", 7, 0, 2)))), 1))
    srow("afmask_sb", u32_text(bf_mask(Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_0", Res.v(al_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_2", Res.v(al_encode(Ov.reg(2, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_4", Res.v(al_encode(Ov.reg(4, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_8", Res.v(al_encode(Ov.reg(8, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_100", Res.v(al_encode(Ov.reg(100, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_126", Res.v(al_encode(Ov.reg(126, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    urow("afenc_sb_127", Res.v(al_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_zero", enc_text(al_encode(Ov.int(0), Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_nonreg", Res.msg(al_encode(Ov.int(7), Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_hi", Res.msg(al_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    srow("afenc_sb_odd", Res.msg(al_encode(Ov.reg(3, 1, False{}, False{}, False{}), Fld.sbase("sdst", 7, 4))))
    srow("afdec_sb_0", rg2(U32.shln(0, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_1", rg2(U32.shln(1, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_2", rg2(U32.shln(2, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_15", rg2(U32.shln(15, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_31", rg2(U32.shln(31, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_32", rg2(U32.shln(32, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afdec_sb_63", rg2(U32.shln(63, U32.to_nat(al_shift_of(Fld.sbase("sdst", 7, 4)))), 1))
    srow("afmask_sr", u32_text(bf_mask(Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_0", Res.v(al_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_2", Res.v(al_encode(Ov.reg(2, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_4", Res.v(al_encode(Ov.reg(4, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_8", Res.v(al_encode(Ov.reg(8, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_100", Res.v(al_encode(Ov.reg(100, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_126", Res.v(al_encode(Ov.reg(126, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    urow("afenc_sr_127", Res.v(al_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_zero", enc_text(al_encode(Ov.int(0), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_nonreg", Res.msg(al_encode(Ov.int(7), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_hi", Res.msg(al_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afenc_sr_odd", Res.msg(al_encode(Ov.reg(3, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 6, 0))))
    srow("afdec_sr_0", rg2(U32.shln(0, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_1", rg2(U32.shln(1, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_2", rg2(U32.shln(2, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_15", rg2(U32.shln(15, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_31", rg2(U32.shln(31, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_32", rg2(U32.shln(32, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afdec_sr_63", rg2(U32.shln(63, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 6, 0)))), 1))
    srow("afmask_sr2", u32_text(bf_mask(Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_0", Res.v(al_encode(Ov.reg(0, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_2", Res.v(al_encode(Ov.reg(2, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_4", Res.v(al_encode(Ov.reg(4, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_8", Res.v(al_encode(Ov.reg(8, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_100", Res.v(al_encode(Ov.reg(100, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_126", Res.v(al_encode(Ov.reg(126, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    urow("afenc_sr2_127", Res.v(al_encode(Ov.reg(127, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_zero", enc_text(al_encode(Ov.int(0), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_nonreg", Res.msg(al_encode(Ov.int(7), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_hi", Res.msg(al_encode(Ov.reg(128, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afenc_sr2_odd", Res.msg(al_encode(Ov.reg(3, 1, False{}, False{}, False{}), Fld.srsc("rsrc", 5, 0))))
    srow("afdec_sr2_0", rg2(U32.shln(0, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_1", rg2(U32.shln(1, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_2", rg2(U32.shln(2, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_15", rg2(U32.shln(15, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_31", rg2(U32.shln(31, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_32", rg2(U32.shln(32, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("afdec_sr2_63", rg2(U32.shln(63, U32.to_nat(al_shift_of(Fld.srsc("rsrc", 5, 0)))), 1))
    srow("vdstyenc_256", enc_text(vdsty_encode(Ov.reg(256, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_256", Res.msg(vdsty_encode(Ov.reg(256, 1, False{}, False{}, False{}))))
    srow("vdstyenc_257", enc_text(vdsty_encode(Ov.reg(257, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_257", Res.msg(vdsty_encode(Ov.reg(257, 1, False{}, False{}, False{}))))
    srow("vdstyenc_258", enc_text(vdsty_encode(Ov.reg(258, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_258", Res.msg(vdsty_encode(Ov.reg(258, 1, False{}, False{}, False{}))))
    srow("vdstyenc_259", enc_text(vdsty_encode(Ov.reg(259, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_259", Res.msg(vdsty_encode(Ov.reg(259, 1, False{}, False{}, False{}))))
    srow("vdstyenc_510", enc_text(vdsty_encode(Ov.reg(510, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_510", Res.msg(vdsty_encode(Ov.reg(510, 1, False{}, False{}, False{}))))
    srow("vdstyenc_511", enc_text(vdsty_encode(Ov.reg(511, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_511", Res.msg(vdsty_encode(Ov.reg(511, 1, False{}, False{}, False{}))))
    srow("vdstyenc_128", enc_text(vdsty_encode(Ov.reg(128, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_128", Res.msg(vdsty_encode(Ov.reg(128, 1, False{}, False{}, False{}))))
    srow("vdstyenc_255", enc_text(vdsty_encode(Ov.reg(255, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_255", Res.msg(vdsty_encode(Ov.reg(255, 1, False{}, False{}, False{}))))
    srow("vdstyenc_0", enc_text(vdsty_encode(Ov.reg(0, 1, False{}, False{}, False{}))))
    srow("vdstyencneg_0", Res.msg(vdsty_encode(Ov.reg(0, 1, False{}, False{}, False{}))))
    srow("vdstyget_0_256", u32_text(vdsty_get(0, 256)))
    srow("vdstyget_0_257", u32_text(vdsty_get(0, 257)))
    srow("vdstyget_0_258", u32_text(vdsty_get(0, 258)))
    srow("vdstyget_0_259", u32_text(vdsty_get(0, 259)))
    srow("vdstyget_1_256", u32_text(vdsty_get(1, 256)))
    srow("vdstyget_1_257", u32_text(vdsty_get(1, 257)))
    srow("vdstyget_1_258", u32_text(vdsty_get(1, 258)))
    srow("vdstyget_1_259", u32_text(vdsty_get(1, 259)))
    srow("vdstyget_2_256", u32_text(vdsty_get(2, 256)))
    srow("vdstyget_2_257", u32_text(vdsty_get(2, 257)))
    srow("vdstyget_2_258", u32_text(vdsty_get(2, 258)))
    srow("vdstyget_2_259", u32_text(vdsty_get(2, 259)))
    srow("vdstyget_127_256", u32_text(vdsty_get(127, 256)))
    srow("vdstyget_127_257", u32_text(vdsty_get(127, 257)))
    srow("vdstyget_127_258", u32_text(vdsty_get(127, 258)))
    srow("vdstyget_127_259", u32_text(vdsty_get(127, 259)))
    srow("vdstyget_128_256", u32_text(vdsty_get(128, 256)))
    srow("vdstyget_128_257", u32_text(vdsty_get(128, 257)))
    srow("vdstyget_128_258", u32_text(vdsty_get(128, 258)))
    srow("vdstyget_128_259", u32_text(vdsty_get(128, 259)))
    srow("vdstyget_255_256", u32_text(vdsty_get(255, 256)))
    srow("vdstyget_255_257", u32_text(vdsty_get(255, 257)))
    srow("vdstyget_255_258", u32_text(vdsty_get(255, 258)))
    srow("vdstyget_255_259", u32_text(vdsty_get(255, 259)))

# --- N  _needs_literal -------------------------------------------------
def g_lit() -> IO(Unit):
  do IO<Unit>:
    row("needs_lit_reg_0", needs_literal(Ov.reg(0, 1, False{}, False{}, False{})))
    row("needs_lit_reg_1", needs_literal(Ov.reg(1, 1, False{}, False{}, False{})))
    row("needs_lit_reg_105", needs_literal(Ov.reg(105, 1, False{}, False{}, False{})))
    row("needs_lit_reg_128", needs_literal(Ov.reg(128, 1, False{}, False{}, False{})))
    row("needs_lit_reg_240", needs_literal(Ov.reg(240, 1, False{}, False{}, False{})))
    row("needs_lit_reg_255", needs_literal(Ov.reg(255, 1, False{}, False{}, False{})))
    row("needs_lit_reg_256", needs_literal(Ov.reg(256, 1, False{}, False{}, False{})))
    row("needs_lit_reg_511", needs_literal(Ov.reg(511, 1, False{}, False{}, False{})))
    row("needs_lit_int_0", needs_literal(Ov.int(0)))
    row("needs_lit_int_1", needs_literal(Ov.int(1)))
    row("needs_lit_int_63", needs_literal(Ov.int(63)))
    row("needs_lit_int_64", needs_literal(Ov.int(64)))
    row("needs_lit_int_65", needs_literal(Ov.int(65)))
    row("needs_lit_int_100", needs_literal(Ov.int(100)))
    row("needs_lit_int_4294967295", needs_literal(Ov.int(4294967295)))
    row("needs_lit_int_4294967280", needs_literal(Ov.int(4294967280)))
    row("needs_lit_int_4294967279", needs_literal(Ov.int(4294967279)))
    row("needs_lit_none", needs_literal(Ov.none()))

# --- I  the Inst field order, _base_size, and the raw-word walk --------
def g_inst() -> IO(Unit):
  do IO<Unit>:
    srow("vop2_fields", fields_of(VOP2_FIELDS()))
    urow("vop2_base_size", base_size(hi_max(VOP2_FIELDS())))
    urow("vop2_hi_max", hi_max(VOP2_FIELDS()))
    srow("ord_fields", fields_of(ORD_FIELDS()))
    srow("ord_fields_swap", fields_of(ORD_FIELDS_SWAP()))
    srow("raw_ord", rws(raw_walk(ORD_VALS())))
    srow("raw_ord_swap", rws(raw_walk(ORD_VALS_SWAP())))
    srow("fields_F16", fields_of(F16_FIELDS()))
    urow("base_size_F16", base_size(hi_max(F16_FIELDS())))
    srow("fields_F64", fields_of(F64_FIELDS()))
    urow("base_size_F64", base_size(hi_max(F64_FIELDS())))
    urow("f64i_mask_lit", bf_mask(Fld.plain("lit", 63, 32)))
    urow("f64i_mask_frac", bf_mask(Fld.plain("f", 31, 0)))
    urow("f40i_mask", bf_mask(Fld.plain("a", 39, 8)))
    row("bf_width_ok_31", bf_width_ok(Fld.plain("f", 31, 0)))
    row("bf_width_ok_40", bf_width_ok(Fld.plain("f", 40, 0)))
    srow("raw_vop2_all", rws(raw_walk(VOP2_ALL())))
    srow("raw_vop2_neg", rws(raw_walk(VOP2_NEG())))
    srow("raw_vop2_hi", rws(raw_walk(VOP2_HI())))
    srow("raw_vop2_int", rws(raw_walk(VOP2_INT())))
    srow("raw_vop2_fconst", rws(raw_walk(VOP2_FCONST())))
    srow("raw_vop2_fnolit", rws(raw_walk(VOP2_FNOLIT())))
    srow("raw_vop2_int65", rws(raw_walk(VOP2_INT65())))
    srow("raw_vop2_intn17", rws(raw_walk(VOP2_INTN17())))
    srow("raw_vop2_big2", rws(raw_walk(VOP2_BIG2())))
    srow("raw_vop2_lit", rws(raw_walk(VOP2_LIT())))
    srow("raw_vop2_sdwa", rws(raw_walk(VOP2_SDWA())))
    srow("raw_vop2_dpp", rws(raw_walk(VOP2_DPP())))
    srow("raw_vop2_big", rws(raw_walk(VOP2_BIG())))
    srow("raw_f32i", rws(raw_walk(F32_VALS())))
    srow("raw_f16i", rws(raw_walk(F16_VALS())))
    srow("raw_f64i", rws(raw_walk(F64_VALS())))
    srow("raw_f40i", rws(raw_walk(F40_VALS())))
    srow("raw_f8i", rws(raw_walk(F8_VALS())))
    row("noresize_105", no_resize(105))
    row("exemptw_105", exempt_width(105))
    row("noresize_106", no_resize(106))
    row("exemptw_106", exempt_width(106))
    row("noresize_107", no_resize(107))
    row("exemptw_107", exempt_width(107))
    row("noresize_124", no_resize(124))
    row("exemptw_124", exempt_width(124))
    row("noresize_125", no_resize(125))
    row("exemptw_125", exempt_width(125))
    row("noresize_126", no_resize(126))
    row("exemptw_126", exempt_width(126))
    row("noresize_127", no_resize(127))
    row("exemptw_127", exempt_width(127))
    row("noresize_128", no_resize(128))
    row("exemptw_128", exempt_width(128))
    row("noresize_239", no_resize(239))
    row("exemptw_239", exempt_width(239))
    row("noresize_240", no_resize(240))
    row("exemptw_240", exempt_width(240))
    row("noresize_248", no_resize(248))
    row("exemptw_248", exempt_width(248))
    row("noresize_249", no_resize(249))
    row("exemptw_249", exempt_width(249))
    row("noresize_254", no_resize(254))
    row("exemptw_254", exempt_width(254))
    row("noresize_255", no_resize(255))
    row("exemptw_255", exempt_width(255))
    row("noresize_256", no_resize(256))
    row("exemptw_256", exempt_width(256))
    urow("modmerge_0_0_0", mod_merge(0, False{}, 0))
    urow("modmerge_0_0_0", mod_merge(0, True{}, 0))
    urow("modmerge_0_0_1", mod_merge(0, False{}, 1))
    urow("modmerge_0_0_1", mod_merge(0, True{}, 1))
    urow("modmerge_2_0_0", mod_merge(2, True{}, 0))
    urow("modmerge_2_0_1", mod_merge(2, True{}, 1))
    urow("modmerge_6_0_1", mod_merge(6, True{}, 1))
    urow("srcbit_src0", src_bit("src0"))
    urow("srcbit_src1", src_bit("src1"))
    urow("srcbit_src2", src_bit("src2"))
    urow("srcbit_vdst", src_bit("vdst"))
    urow("srcbit_sdst", src_bit("sdst"))
    urow("srcbit_op", src_bit("op"))
    urow("srcbit_nosuch", src_bit("nosuch"))
    urow("modmask_neg_vop2", mod_mask(1, VOP2_ALL()))
    urow("modmask_neg_neg", mod_mask(1, VOP2_NEG()))
    urow("modmask_neg_hi", mod_mask(1, VOP2_HI()))
    urow("modmask_ab_vop2", mod_mask(1, VOP2_ALL()))
    urow("modmask_ab_neg", mod_mask(1, VOP2_NEG()))
    urow("modmask_ab_hi", mod_mask(1, VOP2_HI()))
    urow("modmask_hi_vop2", mod_mask(1, VOP2_ALL()))
    urow("modmask_hi_neg", mod_mask(1, VOP2_NEG()))
    urow("modmask_hi_hi", mod_mask(1, VOP2_HI()))
    urow("modmask_src0_vop2", mod_mask(1, VOP2_ALL()))
    urow("modmask_src0_neg", mod_mask(1, VOP2_NEG()))
    urow("modmask_src0_hi", mod_mask(1, VOP2_HI()))
    urow("modmask_src1_vop2", mod_mask(2, VOP2_ALL()))
    urow("modmask_src1_neg", mod_mask(2, VOP2_NEG()))
    urow("modmask_src1_hi", mod_mask(2, VOP2_HI()))
    urow("modmask_src2_vop2", mod_mask(4, VOP2_ALL()))
    urow("modmask_src2_neg", mod_mask(4, VOP2_NEG()))
    urow("modmask_src2_hi", mod_mask(4, VOP2_HI()))
    urow("modmask_vdst_vop2", mod_mask(8, VOP2_ALL()))
    urow("modmask_vdst_neg", mod_mask(8, VOP2_NEG()))
    urow("modmask_vdst_hi", mod_mask(8, VOP2_HI()))
    urow("mod_src0_neg", mod_merge(0, False{}, mod_neg(Ov.reg(3, 1, True{}, False{}, False{}), True{})))
    urow("mod_src0_ab", mod_merge(0, False{}, mod_ab(Ov.reg(3, 1, False{}, True{}, False{}), True{})))
    urow("mod_src0_hi", mod_merge(0, False{}, mod_hi(Ov.reg(3, 1, False{}, False{}, True{}), True{})))
    urow("mod_merge_or", mod_merge(2, True{}, 1))
    urow("mod_merge_zero", mod_merge(0, True{}, 0))
    urow("mod_merge_nogiven", mod_merge(0, False{}, 1))
    srow("to_bytes_vop2", bytes_of(Res.v(raw_walk(VOP2_ALL())), base_size(hi_max(VOP2_FIELDS()))))
    srow("to_bytes_f32i", bytes_of(Res.v(raw_walk(F32_VALS())), base_size(hi_max(F32_FIELDS()))))
    srow("to_bytes_f16i", bytes_of(Res.v(raw_walk(F16_VALS())), base_size(hi_max(F16_FIELDS()))))
    urow("from_bytes_ff", from_bytes(4294967295))
    urow("from_bytes_dead", from_bytes(3735928559))

# --- O  op_bits / op_regs / canonical_* / num_srcs ---------------------
def g_ops() -> IO(Unit):
  do IO<Unit>:
    urow("adj_src2_cndmask", adj_src2_bits("v_cndmask_f32", True{}))
    urow("adj_vdst_cndmask", adj_vdst_bits("v_cndmask_f32", True{}))
    row("is_f8f6f4_cndmask", is_f8f6f4("v_cndmask_f32"))
    row("is_vop3sd_cndmask", is_vop3sd("VOP3SD"))
    urow("adj_src2_cmp", adj_src2_bits("v_cmp_lt_f32", True{}))
    urow("adj_vdst_cmp", adj_vdst_bits("v_cmp_lt_f32", True{}))
    row("is_f8f6f4_cmp", is_f8f6f4("v_cmp_lt_f32"))
    row("is_vop3sd_cmp", is_vop3sd("VOP3SD"))
    urow("adj_src2_co_ci", adj_src2_bits("v_co_ci_add_f32", True{}))
    urow("adj_vdst_co_ci", adj_vdst_bits("v_co_ci_add_f32", True{}))
    row("is_f8f6f4_co_ci", is_f8f6f4("v_co_ci_add_f32"))
    row("is_vop3sd_co_ci", is_vop3sd("VOP3SD"))
    urow("adj_src2_other", adj_src2_bits("v_add_f32", True{}))
    urow("adj_vdst_other", adj_vdst_bits("v_add_f32", True{}))
    row("is_f8f6f4_other", is_f8f6f4("v_add_f32"))
    row("is_vop3sd_other", is_vop3sd("VOP3SD"))
    urow("adj_src2_f8f6f4", adj_src2_bits("v_f8f6f4_mfma_f32_32x32x8_f16", True{}))
    urow("adj_vdst_f8f6f4", adj_vdst_bits("v_f8f6f4_mfma_f32_32x32x8_f16", True{}))
    row("is_f8f6f4_f8f6f4", is_f8f6f4("v_f8f6f4_mfma_f32_32x32x8_f16"))
    row("is_vop3sd_f8f6f4", is_vop3sd("VOP3SD"))
    urow("addr_0", adj_addr_bits(0, False{}))
    urow("addrx_0", adj_addr_bits(0, True{}))
    urow("addr_1", adj_addr_bits(1, False{}))
    urow("addrx_1", adj_addr_bits(1, True{}))
    urow("addr_62", adj_addr_bits(62, False{}))
    urow("addrx_62", adj_addr_bits(62, True{}))
    urow("addr_123", adj_addr_bits(123, False{}))
    urow("addrx_123", adj_addr_bits(123, True{}))
    urow("addr_124", adj_addr_bits(124, False{}))
    urow("addrx_124", adj_addr_bits(124, True{}))
    urow("addr_125", adj_addr_bits(125, False{}))
    urow("addrx_125", adj_addr_bits(125, True{}))
    urow("addr_126", adj_addr_bits(126, False{}))
    urow("addrx_126", adj_addr_bits(126, True{}))
    urow("addr_127", adj_addr_bits(127, False{}))
    urow("addrx_127", adj_addr_bits(127, True{}))
    urow("addr_255", adj_addr_bits(255, False{}))
    urow("addrx_255", adj_addr_bits(255, True{}))
    row("addr_exempt_scratch", addr_exempt("SCRATCH"))
    row("addr_exempt_vscratch", addr_exempt("VSCRATCH"))
    row("addr_exempt_global", addr_exempt("GLOBAL"))
    urow("vaddr_00", adj_vaddr_bits(0, 0))
    urow("vaddr_01", adj_vaddr_bits(0, 1))
    urow("vaddr_10", adj_vaddr_bits(1, 0))
    urow("vaddr_11", adj_vaddr_bits(1, 1))
    srow("f8f6f4_0_0", String.concat([u32_text(mfma_bits(0, 0)), ",", u32_text(mfma_bits(0, 0))]))
    urow("f8f6f4_s0_0_0", mfma_bits(0, 0))
    srow("f8f6f4_0_1", String.concat([u32_text(mfma_bits(0, 0)), ",", u32_text(mfma_bits(1, 1))]))
    urow("f8f6f4_s0_0_1", mfma_bits(0, 0))
    srow("f8f6f4_0_2", String.concat([u32_text(mfma_bits(0, 0)), ",", u32_text(mfma_bits(2, 2))]))
    urow("f8f6f4_s0_0_2", mfma_bits(0, 0))
    srow("f8f6f4_0_3", String.concat([u32_text(mfma_bits(0, 0)), ",", u32_text(mfma_bits(3, 3))]))
    urow("f8f6f4_s0_0_3", mfma_bits(0, 0))
    srow("f8f6f4_0_4", String.concat([u32_text(mfma_bits(0, 0)), ",", u32_text(mfma_bits(4, 4))]))
    urow("f8f6f4_s0_0_4", mfma_bits(0, 0))
    srow("f8f6f4_1_0", String.concat([u32_text(mfma_bits(1, 1)), ",", u32_text(mfma_bits(0, 0))]))
    urow("f8f6f4_s0_1_0", mfma_bits(1, 1))
    srow("f8f6f4_1_1", String.concat([u32_text(mfma_bits(1, 1)), ",", u32_text(mfma_bits(1, 1))]))
    urow("f8f6f4_s0_1_1", mfma_bits(1, 1))
    srow("f8f6f4_1_2", String.concat([u32_text(mfma_bits(1, 1)), ",", u32_text(mfma_bits(2, 2))]))
    urow("f8f6f4_s0_1_2", mfma_bits(1, 1))
    srow("f8f6f4_1_3", String.concat([u32_text(mfma_bits(1, 1)), ",", u32_text(mfma_bits(3, 3))]))
    urow("f8f6f4_s0_1_3", mfma_bits(1, 1))
    srow("f8f6f4_1_4", String.concat([u32_text(mfma_bits(1, 1)), ",", u32_text(mfma_bits(4, 4))]))
    urow("f8f6f4_s0_1_4", mfma_bits(1, 1))
    srow("f8f6f4_2_0", String.concat([u32_text(mfma_bits(2, 2)), ",", u32_text(mfma_bits(0, 0))]))
    urow("f8f6f4_s0_2_0", mfma_bits(2, 2))
    srow("f8f6f4_2_1", String.concat([u32_text(mfma_bits(2, 2)), ",", u32_text(mfma_bits(1, 1))]))
    urow("f8f6f4_s0_2_1", mfma_bits(2, 2))
    srow("f8f6f4_2_2", String.concat([u32_text(mfma_bits(2, 2)), ",", u32_text(mfma_bits(2, 2))]))
    urow("f8f6f4_s0_2_2", mfma_bits(2, 2))
    srow("f8f6f4_2_3", String.concat([u32_text(mfma_bits(2, 2)), ",", u32_text(mfma_bits(3, 3))]))
    urow("f8f6f4_s0_2_3", mfma_bits(2, 2))
    srow("f8f6f4_2_4", String.concat([u32_text(mfma_bits(2, 2)), ",", u32_text(mfma_bits(4, 4))]))
    urow("f8f6f4_s0_2_4", mfma_bits(2, 2))
    srow("f8f6f4_3_0", String.concat([u32_text(mfma_bits(3, 3)), ",", u32_text(mfma_bits(0, 0))]))
    urow("f8f6f4_s0_3_0", mfma_bits(3, 3))
    srow("f8f6f4_3_1", String.concat([u32_text(mfma_bits(3, 3)), ",", u32_text(mfma_bits(1, 1))]))
    urow("f8f6f4_s0_3_1", mfma_bits(3, 3))
    srow("f8f6f4_3_2", String.concat([u32_text(mfma_bits(3, 3)), ",", u32_text(mfma_bits(2, 2))]))
    urow("f8f6f4_s0_3_2", mfma_bits(3, 3))
    srow("f8f6f4_3_3", String.concat([u32_text(mfma_bits(3, 3)), ",", u32_text(mfma_bits(3, 3))]))
    urow("f8f6f4_s0_3_3", mfma_bits(3, 3))
    srow("f8f6f4_3_4", String.concat([u32_text(mfma_bits(3, 3)), ",", u32_text(mfma_bits(4, 4))]))
    urow("f8f6f4_s0_3_4", mfma_bits(3, 3))
    srow("f8f6f4_4_0", String.concat([u32_text(mfma_bits(4, 4)), ",", u32_text(mfma_bits(0, 0))]))
    urow("f8f6f4_s0_4_0", mfma_bits(4, 4))
    srow("f8f6f4_4_1", String.concat([u32_text(mfma_bits(4, 4)), ",", u32_text(mfma_bits(1, 1))]))
    urow("f8f6f4_s0_4_1", mfma_bits(4, 4))
    srow("f8f6f4_4_2", String.concat([u32_text(mfma_bits(4, 4)), ",", u32_text(mfma_bits(2, 2))]))
    urow("f8f6f4_s0_4_2", mfma_bits(4, 4))
    srow("f8f6f4_4_3", String.concat([u32_text(mfma_bits(4, 4)), ",", u32_text(mfma_bits(3, 3))]))
    urow("f8f6f4_s0_4_3", mfma_bits(4, 4))
    srow("f8f6f4_4_4", String.concat([u32_text(mfma_bits(4, 4)), ",", u32_text(mfma_bits(4, 4))]))
    urow("f8f6f4_s0_4_4", mfma_bits(4, 4))
    srow("f8f6f4_default_9", String.concat([u32_text(mfma_bits(9, 9)), ",", u32_text(mfma_bits(9, 9))]))
    urow("mfma_raw_cbsz", mfma_raw_cbsz(65792))
    urow("mfma_raw_blgp", mfma_raw_blgp(65792))
    urow("opregs_0", op_regs_of(0))
    urow("opregs_1", op_regs_of(1))
    urow("opregs_31", op_regs_of(31))
    urow("opregs_32", op_regs_of(32))
    urow("opregs_64", op_regs_of(64))
    urow("opregs_96", op_regs_of(96))
    urow("opregs_128", op_regs_of(128))
    urow("opregs_256", op_regs_of(256))
    urow("opregs_511", op_regs_of(511))
    urow("opregs_1000", op_regs_of(1000))
    urow("canon_seed_c_s0", canon_seed_bits(canon_of("src0")))
    urow("canon_seed_c_vs0", canon_seed_bits(canon_of("vsrc0")))
    urow("canon_seed_c_ss0", canon_seed_bits(canon_of("ssrc0")))
    urow("canon_seed_c_s1", canon_seed_bits(canon_of("src1")))
    urow("canon_seed_c_vs1", canon_seed_bits(canon_of("vsrc1")))
    urow("canon_seed_c_ss1", canon_seed_bits(canon_of("ssrc1")))
    urow("canon_seed_c_s2", canon_seed_bits(canon_of("src2")))
    urow("canon_seed_c_d", canon_seed_bits(canon_of("vdst")))
    urow("canon_seed_c_sdst", canon_seed_bits(canon_of("sdst")))
    urow("canon_seed_c_sdata", canon_seed_bits(canon_of("sdata")))
    urow("canon_seed_c_data", canon_seed_bits(canon_of("data")))
    urow("canon_seed_c_vdata", canon_seed_bits(canon_of("vdata")))
    urow("canon_seed_c_data0", canon_seed_bits(canon_of("data0")))
    urow("canon_seed_c_vsrc", canon_seed_bits(canon_of("vsrc")))
    urow("canon_seed_c_unknown", canon_seed_bits(canon_of("zz")))
    urow("numsrcs_n3", num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n3b", num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n3c", num_srcs(True{}, True{}, True{}))
    urow("numsrcs_n2", num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2b", num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2c", num_srcs(False{}, True{}, True{}))
    urow("numsrcs_n2d", num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1", num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1b", num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n1c", num_srcs(False{}, False{}, True{}))
    urow("numsrcs_n0", num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0b", num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0c", num_srcs(False{}, False{}, False{}))
    urow("numsrcs_n0d", num_srcs(False{}, False{}, False{}))

# --- V  _variant_suffix ------------------------------------------------
def g_vs() -> IO(Unit):
  do IO<Unit>:
    srow("vsuf_0", vs_text(vs_off(0, False{})))
    srow("vsufc_0", vs_text(vs_off(0, True{})))
    srow("vsuf_248", vs_text(vs_off(248, False{})))
    srow("vsufc_248", vs_text(vs_off(248, True{})))
    srow("vsuf_249", vs_text(vs_off(249, False{})))
    srow("vsufc_249", vs_text(vs_off(249, True{})))
    srow("vsuf_250", vs_text(vs_off(250, False{})))
    srow("vsufc_250", vs_text(vs_off(250, True{})))
    srow("vsuf_255", vs_text(vs_off(255, False{})))
    srow("vsufc_255", vs_text(vs_off(255, True{})))
    srow("vsuf_124", vs_text(vs_off(124, False{})))
    srow("vsufc_124", vs_text(vs_off(124, True{})))
    srow("vsuf_256", vs_text(vs_off(256, False{})))
    srow("vsufc_256", vs_text(vs_off(256, True{})))
    srow("vsuf_none", vs_text(vs_off(0, False{})))
    row("vsuf_is_some_255", is_some(vs_off(255, False{})))
    row("vsuf_is_some_0", is_some(vs_off(0, False{})))
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- g_tables()
    b : Unit <- g_const()
    c : Unit <- g_get()
    d : Unit <- g_fmt()
    e : Unit <- g_mod()
    f : Unit <- g_bf()
    +g : Unit <- g_enc()
    h : Unit <- g_lit()
    +i : Unit <- g_inst()
    +j : Unit <- g_ops()
    +k : Unit <- g_vs()
    IO.print("dsl-done=1")
