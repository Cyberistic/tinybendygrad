# tinybendygrad/renderer/amd/dsl.bend -- port of tinygrad/renderer/amd/dsl.py

# the deferred boundary, measured, and it is not this file.
#
# dsl.py:239-242 imports three GENERATED operand tables and merges them:

import Base
import ../../helpers.bend as H

def u32_text(v: U32) -> String: U32.show(v)
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
# 2. `H.I64` EXISTS (helpers.bend:1607, `I64{hi: U32, lo: U32}`), so the
#    64-BIT WALL is narrower than "no 64-bit type": a `_raw` wider than 32 bits
#    and the 64-bit `literal` field can both be held. What CANNOT be held is a
#    field WIDER than 64 bits, of which there are none.
# THE TYPES.
# `dsl.py:18-20`. `Reg` is a WINDOW on the 512-entry src space: an offset, a
type Rg is Data:
  Rg{off: U32, sz: U32, neg: Bool, ab: Bool, hi: Bool}

# ONE answer: a number, and its rendered form, or the refusal VERBATIM. One
# refusal type for the whole file, because a refusal is a MESSAGE and a gate that
# compares flags compares less than a gate that compares text.
type Res is Data:
  Res{v: U32, s: String}
  Bad{msg: String}

# the same answer at the WORD's width, and a second type because a scalar is not
# half of a word. `Res` carries an encoded FIELD value in twenty of its
# twenty-two constructors -- `src_encode`'s offset, `al_encode`'s shifted
# register, a formatted offset -- and widening those to 64 bits would mean
# `H.lo32` at each of the ~110 rows that read `Res.v`, saying "half a word" where
# a scalar is meant. `Wrd` is what `bf_set` and `raw_walk` answer with, and
# nothing else.
#
# `H.I64` IS THE WORD. `bend` has no 64-bit primitive (helpers.bend:1607) and
# `H.I64{hi: U32, lo: U32}` is this tree's own two-limb answer, already carried
# by `dtype.bend` and `uop/fold.bend`. MEASURED on `helpers.bend`'s own algebra
type Wrd is Data:
  Wrd{w: H.I64, s: String}
  WBad{msg: String}

# the FIVE field classes (:100 BitField, :125 FixedBitField, :130
# EnumBitField, :149 SrcField, :202 AlignedSGPRField, :221 VDSTYField) as ONE
# tagged record, because the algebra dispatches on the class and nothing else.
# `rng` is `_valid_range` (lo/hi) for the SrcField family and 0/0 elsewhere.
type Fld is Data:
  Fld{name: String, hi: U32, lo: U32, dflt: U32, kind: U32, rlo: U32, rhi: U32,
      align: U32}

# the KIND tag. The numbers are this file's own, in the order the classes are
# defined in dsl.py -- they reach no device.
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

type Opd is Data:
  Opd{name: String, bits: U32}

type Nm is Data:
  Nm{name: String, off: U32}

# THE CONSTANTS. Every one of these is audited in
# `.agents/slop/dsl_constmap.py` against CPython, by getattr and by probe.
# THE SPACE. `src = Reg(0, 512)` (:66). 512 entries, offsets 0..511.
def SRC_SZ() -> U32: 512
def SRC_LO() -> U32: 0
def SRC_HI() -> U32: 511

def S_HI() -> U32: 105          # s = src[0:105] -> SZPR 106
def TTMP_HI() -> U32: 123
def V_LO() -> U32: 256          # v = src[256:511]
def V_HI() -> U32: 511
def VCC_LO() -> U32: 106
def VCC_HI() -> U32: 107
def VCC_SZ() -> U32: 2
def EXEC_LO() -> U32: 126
def EXEC_HI() -> U32: 127
def EXEC_SZ() -> U32: 2
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

# WHAT THE INLINE-CONSTANT REGIONS HOLD, and it is a LITERAL INVENTORY
# RATHER THAN A RANGE.
#
# "128: 0, 129-192: integers 1-64, 193-208: integers -1 to -16 / 240-248: float
# constants (0.5, -0.5, 1.0, -1.0, 2.0, -2.0, 4.0, -4.0, 1/(2*PI))" -- dsl.py:79-80,
# upstream's comment ON THE SLICES.
#
# THE THREE FACTS IN IT, AND EACH ONE IS A GOTCHA:
#   * 128 IS **0**, NOT 1. THE RANGE IS 128..192, WHICH IS 65 SLOTS, AND IT
#     ENCODES 0 THROUGH 64 -- SO `FMT_INT_LO` IS 128 AND `FMT_INT_BASE` IS 128
#     AND THE OFFSET 128 IS **NOT** SUBTRACTED TO GET THE VALUE. The
#     subtraction happens only because 0 has no slot of its own: 129 is 1.
#     A reader that computes `o - 128` for offset 128 gets 0, which is RIGHT,
#     and a reader that treats 128 as "1" gets every constant wrong by one.
#   * 193..208 IS **NEGATIVE** 1 THROUGH -16, AND THE SIGN IS IN THE RANGE
#     ITSELF: `str(-(o - 192))` -- 193 IS -1. SO THE NEGATIVE REGION IS
#     16 SLOTS AND IT IS SEPARATE FROM THE POSITIVE ONE, NOT A SIGN BIT ON
#     IT. `FMT_NEG_BASE` IS 192 FOR THAT REASON.
#   * 240..248 IS NINE **FLOAT** CONSTANTS AND 248 IS `1/(2*PI)` -- WHICH IS
#     NOT IN `_FLOAT_ENC` AT ALL. `_FLOAT_ENC` (dsl.py:151) HAS EIGHT ENTRIES,

def BRACKET_MULTI() -> U32: 1   # sz > 1

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

def INT_MIN() -> U32: 0
def INT_MAX() -> U32: 64
def NEG_MIN() -> U32: 4294967280   # -16, two's complement: no I32 in Bend
def NEG_MAX() -> U32: 4294967295   # -1
def NEG_OFF_BASE() -> U32: 192     # offset = 192 - val
def INT_OFF_BASE() -> U32: 128     # offset = 128 + val
def INT_N() -> U32: 65             # 0..64 inclusive, :252

# VGPRField's `.h` opsel bit, :194-197. 8-bit fields only, and the encoded
# index must already be below 128.
#
# "For 8-bit vdst fields in VOP1/VOP2 16-bit ops, bit 7 is opsel for dest
# half" -- dsl.py:192, upstream's comment ON THE `.h` ENCODING. THE `.h`
def VGPR_HI_MASK() -> U32: 128
def VGPR_HI_BITS() -> U32: 8

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

def BASE_SIZE_ROUND() -> U32: 8
def BASE_SIZE_DIV() -> U32: 8
def LIT_MARKER() -> U32: 255
def LIT32_MASK() -> U32: 4294967295

# the WORD, and the three widths that bound it. `H.I64` is 64 bits and
# `H.i64_shl` SATURATES PAST 63 -- MEASURED, `put 1 at 64` answers `0:0` where
def WORD_HI() -> U32: 63
def WORD_BITS() -> U32: 32
def WORD_BYTE() -> U32: 4
def WORD_BYTE_SHIFT() -> Nat: 32n
def HEX_NIBBLES() -> Nat: 8n
def HEX_BYTE() -> Nat: 8n

# THE MODIFIER BITS, :313-321. src0/src1/src2 take bit 0/1/2 and vdst.hi takes
# bit 3 -- four DIFFERENT bits for four different registers.
def MOD_SRC0_BIT() -> U32: 1
def MOD_SRC1_BIT() -> U32: 2
def MOD_SRC2_BIT() -> U32: 4
def MOD_VDST_BIT() -> U32: 8

def REG_STRIDE() -> U32: 32
def REG_MIN() -> U32: 1

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

def NSRC_MAX() -> U32: 3
def NSRC_TWO() -> U32: 2
def NSRC_ONE() -> U32: 1
def NSRC_ZERO() -> U32: 0

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

# THE TABLES. Four of them, each ported in BOTH directions.
#
# A Bend list of `Nm` IS the direction; the two directions are two defs over
# one list, so a wrong binding shows up in both at once. That is the property a
# dict keyed the other way would not have.
# `Reg._NAMES` (:11-15), in DICT ORDER -- the order is part of the table, so it
# is a list and not a set. 32 entries.
#
# "Register names vary by arch: RDNA has NULL@124/M0@125, CDNA has
# M0@124/reserved@125 / RDNA4 has DPP8@233, CDNA has SDWA@249/DPP@250/VCCZ@251/
# EXECZ@252" -- dsl.py:9-10, upstream's comment ON THIS TABLE. THE TWO
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

# THE LOOKUPS. A dict lookup is "walk in lockstep and keep the FIRST hit", so
def nm_name.go(n: Nat, +off: U32, xs: List<&2, Nm>, +found: Bool, got: String) -> String:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case Nm{nm, +o} <> t:
          +h = U32.is_eq(off, o)
          nm_name.go(m, off, t, Bool.or(found, h), Bool.pick(String, Bool.and(Bool.not(found), h), nm, got))

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

def Wrd.w(r: Wrd) -> H.I64:
  match r:
    case Wrd{w, s}: w
    case WBad{msg}: H.i64_zero()

def Wrd.s(r: Wrd) -> String:
  match r:
    case Wrd{w, s}: s
    case WBad{msg}: msg

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
def pair_name_of(off: U32) -> String: nm_name.go(reg_pairs_n(), off, reg_pairs(), False{}, "")
def float_enc_name(off: U32) -> String: nm_name.go(float_enc_n(), off, float_enc(), False{}, "")
def float_enc_of(nm: String) -> U32: nm_off.go(float_enc_n(), nm, float_enc(), False{}, FLOAT_ENC_DEFAULT())
def canon_name(id: U32) -> String: nm_name.go(canon_fwd_n(), id, canon_fwd(), False{}, "")

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
def reg_slice.go(bad: Bool, start_neg: Bool, stop_neg: Bool, +start: U32, +stop: U32, +r: Rg) -> Res:
  match bad:
    case True{}:
      Bad{String.concat(["slice [", key_text(start, start_neg), ":", key_text(stop, stop_neg), "] out of bounds for size ", u32_text(Rg.sz(r))])}
    case False{}: Res{0, ""}

# `Reg.fmt` -- :44-62. EIGHT arms, and a transposed pair of them is a silently

def reg_at(+key: U32, +key_neg: Bool, +r: Rg) -> Res:
  reg_at.go(Bool.or(key_neg, U32.is_ge(key, Rg.sz(r))), r, key, key_neg)

# `f"index {key} out of bounds"` (:28) prints the SIGNED key, and Bend has no
def reg_slice(+start: U32, +start_neg: Bool, has_start: Bool, +stop: U32, +stop_neg: Bool,
              has_stop: Bool, +r: Rg) -> Res:
  reg_slice.go(Bool.or(Bool.or(start_neg, stop_neg), U32.is_ge(stop, Rg.sz(r))),
               start_neg, stop_neg, start, stop, r)
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

# THE TABLE IS IN `.agents/slop/tables/renderer-amd-dsl-685.md` -- `BitField` -- :100-123. THE FOUR NUMBERS, and only four:

def bf_bits(+f: Fld) -> U32: U32.add(U32.sub(Fld.hi(f), Fld.lo(f)), 1)

# `1 << 32` SATURATES TO 0 in a U32 (measured, bend2-constraints), so a 32-bit
# field takes its mask from the constant instead of the shift. THE MASK IS A `U32`
# AND THAT IS CORRECT: a field is at most 32 bits wide, so `enc` is too, and
# `bf_width_ok` says so. What is NOT a U32 is the word the mask goes into.
def bf_mask.w(wide: Bool, +f: Fld) -> U32:
  match wide:
    case True{}: LIT32_MASK()
    case False{}: U32.sub(U32.shln(1, U32.to_nat(bf_bits(f))), 1)

def bf_mask(+f: Fld) -> U32: bf_mask.w(U32.is_eq(bf_bits(f), 32), f)

def bf_in_word(+f: Fld) -> Bool: U32.is_le(Fld.hi(f), WORD_HI())

# the one shift, and it is a WORD-wide one. This def is the whole of AMDWORD32:
# `U32.shln` SATURATES past 31, so every `enc << lo` with `lo >= 32` used to come
# back as a SMALLER NUMBER rather than an error -- `sdst` [41:36] and `op_sel`
# [35:34] of a VOP2, `src1` [33:26] of every instruction that has one, `lit`
# [63:32] of an F64 -- and a census that compares rendered BYTES could not see it
# because `hex8` masked to 32 bits ON BOTH SIDES, so the two lanes agreed and
# were both wrong. MEASURED, both lanes: `raw_vop2_all` read `|0x14060a00` where
def wplaced(enc: U32, lo: U32) -> H.I64: H.i64_shl(H.i64_of_i32(enc), U32.to_nat(lo))

def bf_raw_get(+raw: H.I64, +lo: U32, mask: U32) -> U32:
  +m = H.i64_and(raw, wplaced(mask, lo))
  Bool.pick(U32, U32.is_lt(lo, WORD_BITS()), H.lo32(m), H.hi32(m))

# `set`, and its TWO refusals. `enc` is ALREADY encoded -- the caller has run the
# field's own `encode`, which is what makes this one def for all five classes.
def bf_set_msg(+f: Fld, enc: U32) -> String:
  String.concat(["field '", Fld.name(f), "': value ", U32.show(enc), " doesn't fit in ", U32.show(bf_bits(f)), " bits"])

# the second refusal, and it is the port's own. dsl.py:118 names the field's
# value and its width; this one names the field's POSITION and the word it would
# not fit, because `H.i64_shl` cannot report the failure itself.
def bf_word_msg(+f: Fld) -> String:
  String.concat(["field '", Fld.name(f), "': bits ", U32.show(Fld.hi(f)), "..",
                 U32.show(Fld.lo(f)), " do not fit a ", U32.show(WORD_HI()),
                 "-bit instruction word"])

# (raw & ~(mask << lo)) | (encoded << lo), split so the `~(mask << lo)` term is
# named: at four levels of nesting a missing paren is a compile error that reads
# like a missing function.
def bf_set.masked(+f: Fld, +raw: H.I64) -> H.I64:
  H.i64_and(raw, H.i64_not(wplaced(bf_mask(f), Fld.lo(f))))

def bf_set.placed(f: Fld, enc: U32) -> H.I64: wplaced(enc, Fld.lo(f))

def bf_set.over(over: Bool, +f: Fld, raw: H.I64, enc: U32) -> Wrd:
  match over:
    case True{}: WBad{bf_set_msg(f, enc)}
    case False{}: Wrd{H.i64_or(bf_set.masked(f, raw), bf_set.placed(f, enc)), ""}

def bf_set.go(fits: Bool, over: Bool, +f: Fld, raw: H.I64, enc: U32) -> Wrd:
  match fits:
    case True{}: bf_set.over(over, f, raw, enc)
    case False{}: WBad{bf_word_msg(f)}

# `encoded < 0 or encoded > self.mask` (:118), held as U32. `enc_neg` IS the
def bf_set(+f: Fld, raw: H.I64, +enc: U32, enc_neg: Bool) -> Wrd:
  bf_set.go(bf_in_word(f), Bool.or(enc_neg, U32.is_gt(enc, bf_mask(f))), f, raw, enc)

# `field '{self.name}': value {encoded} doesn't fit in {hi - lo + 1} bits`
# (:118). The NAME is in the message, so a transposed `_fields` order shows up
# in the text and not only in the value -- and it is the reason `bf_set_msg` and
# `bf_word_msg` are two defs rather than one def with a mode flag.

def src_ov_float(off: U32, known: Bool) -> Ov: Ov{OV_FLOAT(), Bool.pick(U32, known, off, FLOAT_ENC_DEFAULT()), 1, False{}, False{}, False{}}

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

def vgpr_encode.big.go(big: Bool, enc: U32, e: U32, s: String) -> Res:
  match big:
    case True{}:
      Bad{String.concat(["VGPRField: v[", U32.show(e), "].h not encodable in 8-bit field (v[0:127] only for .h)"])}
    case False{}: Res{enc, s}

# `AlignedSGPRField.encode` (:205-210). FOUR cases, and the FIRST is the one a

def vgpr_encode.big(enc: U32, +f: Fld, +e: U32, s: String) -> Res:
  vgpr_encode.big.go(U32.is_ge(e, VGPR_HI_MASK()), enc, e, s)

def vgpr_encode.range(res: Res, +v: Ov, +f: Fld) -> Res:
  match res:
    case Bad{msg}: Bad{msg}
    case Res{+enc, s}: vgpr_encode.big(enc, f, enc, s)


def vgpr_encode.fit(set: Bool, res: Res, +v: Ov, +f: Fld) -> Res:
  match set:
    case True{}: vgpr_encode.range(res, v, f)
    case False{}: res

def vgpr_or(set: Bool, res: Res, f: Fld) -> Res:
  match res:
    case Bad{msg}: Bad{msg}
    case Res{+enc, s}: Res{Bool.pick(U32, set, U32.or(enc, VGPR_HI_MASK()), enc), s}

# the order of :194-197 is the whole of this class, and it is two steps in one order:
#     encoded = super().encode(val)
#     if val.hi and (self.hi - self.lo + 1) == 8:
#       if encoded >= 128: raise ValueError(...)
#       encoded |= 0x80
# so the `>= 128` test is on `encoded` before the bit is set. This def read
# `vgpr_encode.fit(set, vgpr_or(set, X, f), v, f)` -- the OR FIRST, then the test -- and
# since ORing 0x80 into an eight-bit value ALWAYS leaves it >= 128, EVERY `.h` in an
# eight-bit field took the refusal arm. MEASURED on the census: `vgenchi_7_0_256` CPython
def vgpr_encode.hi(+set: Bool, +v: Ov, +f: Fld) -> Res: vgpr_or(set, vgpr_encode.fit(set, src_encode(v, f), v, f), f)

def vgpr_hbit(v: Ov, f: Fld) -> Bool: Bool.and(Ov.hi(v), U32.is_eq(bf_bits(f), VGPR_HI_BITS()))

def vgpr_encode(+v: Ov, +f: Fld) -> Res: vgpr_encode.hi(vgpr_hbit(v, f), v, f)

# the shift is `_align.bit_length() - 1`, which is not the alignment and not `align - 1`.
# This def read `U32.sub(Fld.align(f), 1)`, so for `_align = 4` (`dsl.py:219 SRsrcField`) it
def al_shift_of.two() -> U32: ALIGN_SHIFT_2()
def al_shift_of.four() -> U32: ALIGN_SHIFT_4()
def al_shift_of.is2(a: U32) -> Bool: U32.is_eq(a, 2)

def al_shift_of.go(a: U32) -> U32:
  Bool.pick(U32, al_shift_of.is2(a), al_shift_of.two(), al_shift_of.four())

def al_shift_of(f: Fld) -> U32: al_shift_of.go(Fld.align(f))

def al_encode.why(notsgpr: Bool, +v: Ov, +f: Fld) -> Res:
  match notsgpr:
    case True{}: Bad{String.concat([Fld.name(f), " requires SGPR, got offset ", U32.show(Ov.off(v))])}
    case False{}:
      Bad{String.concat([Fld.name(f), " requires ", U32.show(Fld.align(f)), "-aligned SGPR, got s[", U32.show(Ov.off(v)), "]"])}


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
def vdsty_not_reg() -> String: "VDSTYField requires Reg, got int"

def vdsty_encode.why(isreg: Bool, +v: Ov) -> Res:
  match isreg:
    case True{}: Bad{String.concat(["VDSTYField requires VGPR, got offset ", U32.show(Ov.off(v))])}
    case False{}: Bad{vdsty_not_reg()}

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

def enum_encode(enc: U32, is_member: Bool) -> Bool: Bool.not(is_member)

# `Inst` -- :270-456. The LOGIC, with the autogen DATA as arguments.
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
def src_bit.vdst(name: String, rest: U32) -> U32:
  Bool.pick(U32, String.eq(name, "vdst"), MOD_VDST_BIT(), rest)

def src_bit.s2(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src2"), MOD_SRC2_BIT(), rest)


def src_bit.s1(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src1"), MOD_SRC1_BIT(), rest)

def src_bit.s0(name: String, rest: U32) -> U32: Bool.pick(U32, String.eq(name, "src0"), MOD_SRC0_BIT(), rest)

def src_bit(+name: String) -> U32:
  src_bit.s2(name, src_bit.s1(name, src_bit.s0(name, src_bit.vdst(name, 0))))

# which of the three masks is being accumulated. dsl.py:313-319 keeps three
def MOD_NEG() -> U32: 0     # neg_bits   (dsl.py:317)
def MOD_ABS() -> U32: 1     # abs_bits   (dsl.py:318)  `Reg.abs_`; the census spells it `ab`
def MOD_OPSEL() -> U32: 2   # opsel_bits (dsl.py:319)
def mod_mask.pick.go(hit: Bool, +bit: U32, +acc: U32) -> U32:
  match hit:
    case True{}: U32.or(acc, bit)
    case False{}: acc

# `if reg.neg` / `if reg.abs_` / `if reg.hi` (:317-319) -- the three tests the loop
def mod_hit.opsel(m: U32, +v: Ov, rest: Bool) -> Bool: Bool.pick(Bool, U32.is_eq(m, MOD_OPSEL()), Ov.hi(v), rest)
def mod_hit.ab(m: U32, +v: Ov, rest: Bool) -> Bool: Bool.pick(Bool, U32.is_eq(m, MOD_ABS()), Ov.ab(v), rest)
def mod_hit.neg(m: U32, +v: Ov, rest: Bool) -> Bool: Bool.pick(Bool, U32.is_eq(m, MOD_NEG()), Ov.neg(v), rest)
def mod_hit(+m: U32, +v: Ov) -> Bool: mod_hit.neg(m, v, mod_hit.ab(m, v, mod_hit.opsel(m, v, False{})))

def mod_mask.pick(named: Bool, isreg: Bool, +bit: U32, +acc: U32) -> U32: mod_mask.pick.go(Bool.and(named, isreg), bit, acc)

# dsl.py:316-319 -- `if reg.neg: neg_bits |= (1 << bit)`. ALL THREE CLAUSES AT ONCE,
# which is what a mask is: `m` says which flag, `bit` says which register.
def mod_mask.one(m: U32, nm: String, +v: Ov, +has: Bool, +bit: U32, +acc: U32) -> U32:
  mod_mask.pick(U32.is_eq(src_bit(nm), bit), Bool.and(has, Bool.and(U32.is_eq(Ov.k(v), OV_REG()), mod_hit(m, v))), bit, acc)

def mod_mask.go(+m: U32, vfs: List<&2, Vf>, +acc: U32, +bit: U32) -> U32:
  match vfs:
    case Nil{}: acc
    case Vf{f, v, has} <> t: mod_mask.go(m, t, mod_mask.one(m, Fld.name(f), v, has, bit, acc), bit)

def mod_mask(m: U32, bit: U32, vfs: List<&2, Vf>) -> U32: mod_mask.go(m, vfs, 0, bit)

def bind.take(name: String, f: Fld, kwname: String, kwsz: U32, kwhas: Bool, has: Bool) -> Bool:
  Bool.or(U32.is_eq(Fld.kind(f), K_FIXED()), Bool.or(kwhas, has))

def too_many(n_left: U32) -> Bool: U32.is_gt(n_left, 0)

# the write walk (:334-335): `for name, field in self._fields: self._raw =
# field.set(self._raw, vals[name])`. THE ORDER IS THE ENCODING.
def Vf.f(vf: Vf) -> Fld: match vf: case Vf{f, v, has}: f

def enc_big(+enc: Res, +f: Fld) -> Bool: Bool.not(U32.is_le(Res.v(enc), bf_mask(f)))

def raw_step.set(ok: Bool, +vf: Vf, +raw: H.I64, +enc: Res) -> Wrd:
  match ok:
    case True{}: bf_set(Vf.f(vf), raw, Res.v(enc), enc_big(enc, Vf.f(vf)))
    case False{}: WBad{Res.msg(enc)}

def enc_ok(e: Res) -> Bool:
  match e:
    case Res{v, s}: True{}
    case Bad{msg}: False{}

# `encoded < 0 or encoded > self.mask` (:118), held as U32. A negative producer
# has already been `& mask`-ed by :117, so the only live half of the test is
# "bigger than the mask"; `bf_set` re-derives the same predicate, and sharing
# `bf_mask` here is what makes a wrong mask move BOTH rows.

def raw_step.go(+enc: Res, +vf: Vf, +raw: H.I64) -> Wrd:
  raw_step.set(enc_ok(enc), vf, raw, enc)

def Vf.v(vf: Vf) -> Ov: match vf: case Vf{f, v, has}: v
def Vf.has(vf: Vf) -> Bool: match vf: case Vf{f, v, has}: has

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
#
# "Resize register based on operand info (skip non-resizable special
# registers) / VCC/EXEC pairs (106, 126), NULL (124), M0 (125), float constants
# (240-255)" -- dsl.py:178-179, upstream's comment ON THE SKIP. THE RESIZE IS
# NOT COSMETIC: A FIELD'S VALUE IS A REGISTER *OFFSET*, BUT THE INSTRUCTION
# NEEDS A REGISTER *OF A GIVEN WIDTH*, AND THE WIDTH COMES FROM THE XML'S
# OPERAND INFO, NOT FROM THE OFFSET. SO A `src0` THAT THE XML SAYS IS TWO
# VGPRS WIDE MUST READ BACK AS A TWO-REGISTER `Reg`, AND THE ENCODER THEN
# EMITS `v[0:1]`.
#
# AND THE SKIP IS THE PART THAT IS EASY TO GET WRONG: A RESIZE IS NOT ALWAYS
# POSSIBLE. THE VCC AND EXEC PAIRS (106, 126) ARE TWO REGISTERS BY
# CONSTRUCTION, NULL (124) AND M0 (125) ARE SINGLE REGISTERS THAT HAPPEN TO
# HAVE A NAME, AND THE FLOAT CONSTANTS (240..255) ARE **VALUES** AND NOT
# REGISTERS AT ALL -- RESIZING A FLOAT CONSTANT WOULD PRODUCE A `Reg` THAT
# PRINTS AS A REGISTER NAME IT IS NOT. SO THE SKIP LIST IS A LIST OF
# "THIS OFFSET IS NOT A RESIZABLE REGISTER" AND IT IS NOT A LIST OF "THIS
# OFFSET IS SPECIAL" IN GENERAL: 233 (`DPP8`) AND 236..238 (`SHARED_BASE`
# AND FRIENDS) ARE SPECIAL AND ARE **NOT** IN THE LIST, BECAUSE THEY *ARE*
# RESIZABLE.
#
# "Map variant field names (vsrc0->src0, vsrc1->src1, etc.) for DPP/SDWA
# classes" -- dsl.py:181, upstream's comment ON THE NAME HALF OF THE SAME
# STATEMENT. A DPP OR SDWA CLASS NAMES ITS SOURCE FIELD `vsrc0` WHERE THE
# ORDINARY CLASS NAMES IT `src0`, AND THE OPERAND INFO IS KEYED BY THE
# ORDINARY NAME. SO THE LOOKUP STRIPS A LEADING `v` -- BUT ONLY IF WHAT
# FOLWS IS A NAME THE OPERAND INFO ACTUALLY HAS, BECAUSE A FIELD GENUINELY
# NAMED `vdst` OR `vdata` MUST NOT BECOME `dst` OR `data`. THE PORT'S
# `canon_fwd` / `canon_in` TABLES (THE EVEN FOLD AT dsl.py:261-268) ARE THE

def fld_encode.k(k: Nat, +vf: Vf) -> Res:
  match k:
    case 0n: Res{Ov.off(Vf.v(vf)), ""}
    case 1n: Res{Fld.dflt(Vf.f(vf)), ""}
    case 2n: Res{Ov.off(Vf.v(vf)), ""}
    case _: typed_encode(U32.to_nat(Fld.kind(Vf.f(vf))), vf)

# `if val is None: val = self.default` (dsl.py:114), which is the FIRST LINE of `set`
def fld_encode.dflt(k: Nat, +f: Fld) -> Res:
  match k:
    case 10n: Bad{vdsty_not_reg()}
    case _: Res{Fld.dflt(f), ""}

def fld_encode.go(has: Bool, +vf: Vf) -> Res:
  match has:
    case True{}: fld_encode.k(U32.to_nat(Fld.kind(Vf.f(vf))), vf)
    case False{}: fld_encode.dflt(U32.to_nat(Fld.kind(Vf.f(vf))), Vf.f(vf))

def fld_encode(+vf: Vf) -> Res: fld_encode.go(Vf.has(vf), vf)

def raw_step(+vf: Vf, raw: H.I64) -> Wrd: raw_step.go(fld_encode(vf), vf, raw)

def Vf.of(f: Fld, v: Ov, has: Bool) -> Vf: Vf{f, v, has}

def needs_literal.k(k: Nat, +v: Ov) -> Bool:
  match k:
    case 0n: False{}
    case 1n: False{}
    case 2n: Bool.not(Bool.or(inl_int_val(Ov.off(v)), inl_neg_val(Ov.off(v))))
    case _: False{}

def needs_literal(+v: Ov) -> Bool: needs_literal.k(U32.to_nat(Ov.k(v)), v)

# THE TABLE IS IN `.agents/slop/tables/renderer-amd-dsl-1249.md` -- `op_bits` / `op_regs` -- :348-381. FIVE ADJUSTMENTS over the XML widths, and

def ADJ_WAVE32() -> U32: 1
def ADJ_IS_CDNA() -> U32: 1

def has_name_bit(name: String, sub: String) -> Bool: String.contains(name, sub)
def is_vop3sd(cls: String) -> Bool: String.contains(cls, "VOP3SD")

def adj_sdst_bits(cls: String, has_sdst: Bool) -> U32:
  Bool.pick(U32, Bool.and(has_sdst, is_vop3sd(cls)), ADJ_SRC2_BITS(), 0)

# GLOBAL/FLAT: `saddr_val = (self._raw >> saddr.lo) & saddr.mask` (:364) reads
def adj_addr_bits.y(narrow: Bool) -> U32:
  match narrow:
    case True{}: ADJ_ADDR_BITS2()
    case False{}: ADJ_ADDR_BITS()

# `type(self).__name__ not in ('SCRATCH', 'VSCRATCH')` (:363). A name test, so a
# subclass of SCRATCH is NOT exempt and a class merely NAMED like it is.

def adj_addr_bits.x(nul: Bool, exempt: Bool) -> U32: adj_addr_bits.y(Bool.or(exempt, Bool.not(nul)))

def adj_addr_bits(+saddr_raw: U32, exempt: Bool) -> U32:
  adj_addr_bits.x(Bool.or(U32.is_eq(saddr_raw, ADJ_SADDR_NULL()), U32.is_eq(saddr_raw, ADJ_SADDR_M0())), exempt)

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

def num_srcs.a0(+has_s0: Bool) -> U32: Bool.pick(U32, has_s0, NSRC_ONE(), NSRC_ZERO())

# `_variant_suffix` (:423-437). 255 -> _LIT, 249 -> _SDWA or _DPP8 by arch,

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

# THE GATE. Every `py=` below was produced by CALLING CPython --

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
def Fld.sbase(nm: String, hi: U32, lo: U32) -> Fld: Fld.of(nm, hi, lo, 0, K_SBASE(), 0, 0, ALIGN_SBASE())
def Fld.vdsty(nm: String) -> Fld: Fld.of(nm, 0, 0, 0, K_VDSTY(), 0, 0, 1)

def Ov.none() -> Ov: Ov{OV_NONE(), 0, 1, False{}, False{}, False{}}
def Ov.reg(off: U32, sz: U32, neg: Bool, ab: Bool, hi: Bool) -> Ov: Ov{OV_REG(), off, sz, neg, ab, hi}
def Ov.int(n: U32) -> Ov: Ov{OV_INT(), n, 1, False{}, False{}, False{}}

def fields_of.go(fs: List<&2, Fld>, +acc: String) -> String:
  match fs:
    case Nil{}: acc
    case Fld{nm, hi, lo, dflt, kind, rlo, rhi, align} <> t:
      fields_of.go(t, String.concat([acc, nm, ":", U32.show(hi), ":", U32.show(lo), ","]))


def fields_of(fs: List<&2, Fld>) -> String: fields_of.go(fs, "")

def hi_max.go(fs: List<&2, Fld>, +acc: U32) -> U32:
  match fs:
    case Nil{}: acc
    case Fld{nm, hi, lo, dflt, kind, rlo, rhi, align} <> t: hi_max.go(t, U32.max(acc, hi))

# gate 1: the tables, both directions, and one row per entry.

def hi_max(fs: List<&2, Fld>) -> U32: hi_max.go(fs, 0)

# THE GATE'S HELPERS. Each exists because a generated row needs it, and NONE of
def bs(b: Bool) -> String: Bool.pick(String, b, "True", "False")

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

# eight hex digits, zero-padded, and no `0x`. The prefix belongs to `hexw` and
# only to `hexw` -- a word is rendered in ONE place, so a word cannot come back
# with two prefixes or with one and a half.
def hex8(+v: U32) -> String:
  String.concat([hex4(U32.shrn(v, 16n)), hex4(U32.and(v, 65535))])

# CPython's `f"{x:#010x}"` -- OF A WORD. `#010x` pads to a WIDTH, and a word
def hexhi.go(k: Nat, zero: Bool, +hi: U32, acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+j:
      match zero:
        case True{}: hexhi.go(j, U32.is_zero(U32.shrn(hi, 4n)), U32.shrn(hi, 4n), acc)
        case False{}: hexhi.go(j, U32.is_zero(U32.shrn(hi, 4n)), U32.shrn(hi, 4n),
                               String.concat([hex1(U32.and(hi, 15)), acc]))

def hexhi(+hi: U32) -> String: hexhi.go(HEX_NIBBLES(), U32.is_zero(hi), hi, "")

# the high WORD is omitted rather than zero-printed, and that is the whole
def hexw(+w: H.I64) -> String:
  +hi = H.hi32(w)
  +lo = hex8(H.lo32(w))
  String.concat(["0x", Bool.pick(String, U32.is_zero(hi), lo, String.concat([hexhi(hi), lo]))])

# `bfs` READS WHAT `bf_set` ANSWERS rather than re-deriving "does the value fit"
# to choose a message of its own. That duplicated predicate is why a `WBad` about
# the WORD would have been unreachable here: the old arm knew only `bf_set_msg`.
def bfs.go(r: Wrd) -> String:
  match r:
    case Wrd{w, s}: hexw(w)
    case WBad{msg}: String.concat(["REFUSE:", msg])

def bfs(+f: Fld, raw: H.I64, +val: U32) -> String: bfs.go(bf_set(f, raw, val, False{}))

def is_some.go(m: Maybe<&2, String>, dflt: Bool) -> Bool:
  match m:
    case Some{s}: True{}
    case None{}: dflt

# `int.from_bytes(data[:base_size], 'little')` (:442) -- the DECODE half of

def is_some(m: Maybe<&2, String>) -> Bool: is_some.go(m, False{})

def hexnib(v: U32, n: Nat) -> String: hex1(U32.shrn(v, Nat.mul(n, 4n)))
def hex2(+v: U32) -> String: String.concat([hexnib(v, 1n), hexnib(v, 0n)])

# BYTE `b` OF THE WORD, LOW BYTE FIRST. The limb is chosen by `b / 4` and the
# shift is `8 * b` WITHIN it, because `U32.shrn` SATURATES past 31 -- shifting
# the low limb by its own 32 bits answers 0, which is how every byte above the
# third used to read as zero.
def wbyte(+w: H.I64, +b: Nat) -> U32:
  +i = Nat.mul(b, HEX_BYTE())
  Bool.pick(U32, U32.is_lt(U32.from_nat(b), WORD_BYTE()),
    U32.shrn(H.lo32(w), i), U32.shrn(H.hi32(w), Nat.sub(i, WORD_BYTE_SHIFT())))

def bytes_of.go(n: Nat, +b: Nat, +w: H.I64, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: bytes_of.go(m, Nat.add(b, 1n), w, String.concat([acc, hex2(wbyte(w, b))]))

def bytes_of(w: H.I64, sz: U32) -> String: bytes_of.go(U32.to_nat(sz), 0n, w, "")

# `raw_walk` -- the `__init__` write walk (:334-335): `for name, field in
def raw_walk.go(vfs: List<&2, Vf>, prior: Wrd) -> Wrd:
  match vfs:
    case Nil{}: prior
    case Vf{f, v, has} <> t:
      match prior:
        case WBad{msg}: WBad{msg}
        case Wrd{praw, pacc}: raw_walk.go(t, raw_step(Vf.of(f, v, has), praw))

def raw_walk(vfs: List<&2, Vf>) -> Wrd: raw_walk.go(vfs, Wrd{H.i64_zero(), ""})

# ONE LIST, not two. In Python `_fields` and `vals` are separate and zipped by
# iteration order; here each `Vf` CARRIES its own `Fld`, so there is no zip and
# no second list to get out of step -- and `_fields` ORDER is then visible in
# the `Vf` list's order, which is what `fields_of` prints.

def F8_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5)]
def F40_FIELDS() -> List<&2, Fld>: [Fld.fixed("op", 7, 0, 5), Fld.plain("A", 39, 8)]
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

def vs_text(m: Maybe<&2, String>) -> String: vs_text.go(m, "None")
