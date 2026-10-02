# ===========================================================================
# SECTION 5 -- the fixture shapes and the emitters.
#
# `write_ins` is 175 lines of generate.py and 122 of them are logic.  Its three
# nested closures are the whole difficulty: `field_def` is a SEVENTEEN-ARM
# LADDER over (field name, bit width, format, arch, enc_bits) and its ORDER is
# load-bearing (`soffset` at 7 bits is SGPRField, at 8 bits it is SSrcField;
# `ssrc*` at 8 bits is SSrcField and is tested BEFORE the saddr/soffset arm).
# So the ladder is a TABLE here, in source order, and `field_def` is a walk
# over it that returns the FIRST match -- the table is the spec, and a
# reordering of the table is a reordering of the spec.
#
# The kind codes are `K2_*` and NOT `dsl.bend`'s `K_*`, deliberately.  dsl.bend
# exports `K_PLAIN`/`K_FIXED`/`K_ENUM`/`K_SRC`/`K_VGPR`/`K_SGPR`/`K_SSRC`/
# `K_ALIGN`/`K_SBASE`/`K_SRSC`/`K_VDSTY`, which classify the SAME eleven
# classes -- but at the ENCODE side, where `SGPRField(7,0)` is one class.  The
# generator emits `SGPRField(hi, lo)` and `SGPRField(hi, lo, default=NULL)` as
# two DIFFERENT lines, so importing dsl's codes would alias them and a gate row
# would be blind to the swap.  Two code spaces, and this comment is the reason.
# ===========================================================================

# pk: 0 nm == pa | 1 starts_with(nm, pa) | 2 base_fmt == pa | 3 nm in pa
# pb: 0 any width | 1 width == pb
# pc: 0 any format | 1 fmt not in ("DPP","SDWA") | 2 base_fmt in ("GLOBAL","SCRATCH")
type R is Data: R{pk: U32, pa: String, pb: U32, pc: U32, kind: U32}

def K2_BIT() -> U32: 0     # BitField(hi, lo)
def K2_ENCBITS() -> U32: 1 # FixedBitField(hi, lo, 0b<enc_bits>)
def K2_FIXINT() -> U32: 2  # FixedBitField(hi, lo, <int>)
def K2_FIXEMB() -> U32: 3  # FixedBitField(hi, lo, 0b<bits><opcode>)
def K2_ENOP() -> U32: 4    # EnumBitField(hi, lo, <base_fmt>Op)
def K2_ENOPD() -> U32: 5   # EnumBitField(hi, lo, VOPDOp)
def K2_VDSTY() -> U32: 6   # V_DSTYField(hi, lo)
def K2_VGPR() -> U32: 7    # VGPRField(hi, lo)
def K2_SBASE() -> U32: 8   # SBaseField(hi, lo)
def K2_SRSC() -> U32: 9    # SRsrcField(hi, lo)
def K2_SGPR() -> U32: 10   # SGPRField(hi, lo)
def K2_SGPRN() -> U32: 11  # SGPRField(hi, lo, default=NULL)
def K2_SSRC() -> U32: 12   # SSrcField(hi, lo)
def K2_SSRCN() -> U32: 13  # SSrcField(hi, lo, default=NULL)
def K2_SRC9() -> U32: 14   # SrcField(hi, lo)
def K2_OFF13() -> U32: 15  # BitField(12, lo)
def K2_OPHI3() -> U32: 16  # BitField(hi, lo, default=3)
def K2_OPHI21() -> U32: 17 # BitField(hi, lo, default=1)

def field_rules() -> List<&2, R>:
  [R{0, "op", 0, 1, K2_ENOP()}, R{0, "opx", 0, 0, K2_ENOPD()}, R{0, "opy", 0, 0, K2_ENOPD()},
   R{0, "vdsty", 0, 0, K2_VDSTY()}, R{3, vgpr_fields(), 1, 0, K2_VGPR()},
   R{0, "sbase", 1, 0, K2_SBASE()}, R{0, "srsrc", 1, 0, K2_SRSC()}, R{0, "ssamp", 1, 0, K2_SRSC()},
   R{0, "sdst", 1, 0, K2_SGPR()}, R{0, "sdata", 1, 0, K2_SGPR()},
   R{0, "soffset", 1, 0, K2_SGPRN()}, R{0, "saddr", 1, 0, K2_SGPRN()},
   R{1, "ssrc", 1, 0, K2_SSRC()}, R{0, "saddr", 1, 0, K2_SSRCN()}, R{0, "soffset", 1, 0, K2_SSRCN()},
   R{1, "src", 1, 0, K2_SRC9()},
   R{0, "offset", 0, 2, K2_OFF13()},
   R{0, "opsel_hi", 0, 0, K2_OPHI3()}, R{0, "opsel_hi2", 0, 0, K2_OPHI21()}]

def vgpr_fields() -> String:
  "vdst vdstx vsrc0 vsrc1 vsrc2 vsrc3 vsrcx1 vsrcy1 vaddr vdata data data0 data1 addr vsrc"

def vgpr_hit(+nm: String, i: Nat, ws: List<&2, String>) -> Bool:
  match ws:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(h, nm), vgpr_hit(nm, i, t))

# `in ("DPP","SDWA")` -- the ONE place `field_def` refuses to call an enum for
# a format whose `op` field is not an opcode.
def fmt_exempt(fmt: String) -> Bool: Bool.or(String.eq(fmt, "DPP"), String.eq(fmt, "SDWA"))

def r_pk(pk: U32, pa: String, +nm: String, +base_fmt: String) -> Bool:
  match pk:
    case 0: String.eq(nm, pa)
    case 1: String.starts_with(nm, pa)
    case 2: String.eq(base_fmt, pa)
    case _: vgpr_hit(nm, 0n, String.split(pa, ' '))

def r_ok(r: R, nm: String, width: U32, base_fmt: String, fmt: String) -> Bool:
  r_ok.pc(r_pk(R.pk(r), R.pa(r), nm, base_fmt),
          Bool.or(R.pb(r) == 0, R.pb(r) == width),
          fmt_exempt_b(R.pc(r), fmt, base_fmt))

# pc: 0 any | 1 fmt not in (DPP,SDWA) | 2 base_fmt in (GLOBAL,SCRATCH)
def fmt_exempt_b(pc: U32, fmt: String, base_fmt: String) -> Bool:
  Bool.pick(Bool, U32.is_eq(pc, 1), Bool.not(fmt_exempt(fmt)),
    Bool.pick(Bool, U32.is_eq(pc, 2),
      Bool.or(String.eq(base_fmt, "GLOBAL"), String.eq(base_fmt, "SCRATCH")), True{}))

def field_rules.go(rs: List<&2, R>, nm: String, width: U32, base_fmt: String, fmt: String,
                   cur: U32) -> U32:
  match rs:
    case Nil{}: cur
    case r <> rest: field_rules.step(r, rest, nm, width, base_fmt, fmt, cur)

def field_rules.step(r: R, rest: List<&2, R>, nm: String, width: U32, base_fmt: String,
                     fmt: String, cur: U32) -> U32:
  match r_ok(r, nm, width, base_fmt, fmt):
    case True{}: R.kind(r)
    case False{}: field_rules.go(rest, nm, width, base_fmt, fmt, cur)

# ===========================================================================
# `field_def`, generate.py:295-318.
#
# The output is a PYTHON constructor call, so this is where WALL 3 shows: the
# port builds the call as a STRING rather than as a value, because a generated
# `class X(Inst): op = EnumBitField(...)` body is not a bend value at all and
# writing it as one would be a lie about what the file does.
# ===========================================================================

# `f"FixedBitField({hi}, {lo}, 0b{fixed_bits}{opcode:0{bits-len(fixed_bits)}b})"` --
# the embedded-instruction form: FIXED_FIELDS names a (format, instruction) PAIR
# and the generator concatenates that format's ENCODING BITS with the
# instruction's OPCODE, zero-padded to the field width.  Zero-padding is
# `String.repeat("0", n)` and is the part that silently truncates if n is
# negative, so `pad_n` is the port's guard.
def field_def.emb(hi: U32, lo: U32, fixed_bits: String, opcode: U32, width: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ fixed_bits ++
  String.repeat("0", pad_n(U32.sub(width, U32.to_nat(String.length(fixed_bits))))) ++
  U32.show(opcode) ++ ")"

def pad_n(n: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(0n, n), Nat.sub(n, 0n), 0n)

# `get_base_fmt(fmt)` and then the trailing `)Op`, except for opx/opy which are
# always `VOPDOp` -- so the enum name is `base_fmt ++ "Op"` OR `VOPDOp`.
def field_def.kind_text(kind: U32, hi: U32, lo: U32, base_fmt: String) -> String:
  field_def.tail(kind, "BitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ")")

def field_def.tail(kind: U32, fallback: String) -> String:
  Bool.pick(String, U32.is_eq(kind, K2_BIT()), fallback,
    Bool.pick(String, U32.is_eq(kind, K2_VDSTY()), "VDSTYField(" ++ field_def.hilo(kind),
      field_def.mid(kind, fallback)))

def field_def.mid(kind: U32, fallback: String) -> String:
  Bool.pick(String, U32.is_eq(kind, K2_VGPR()), "VGPRField(" ++ field_def.hilo(kind),
    Bool.pick(String, U32.is_eq(kind, K2_SBASE()), "SBaseField(" ++ field_def.hilo(kind),
      Bool.pick(String, U32.is_eq(kind, K2_SRSC()), "SRsrcField(" ++ field_def.hilo(kind),
        Bool.pick(String, U32.is_eq(kind, K2_SSRC()), "SSrcField(" ++ field_def.hilo(kind),
          Bool.pick(String, U32.is_eq(kind, K2_SRC9()), "SrcField(" ++ field_def.hilo(kind),
            Bool.pick(String, U32.is_eq(kind, K2_ENOPD()), "EnumBitField(" ++ field_def.hilo(kind),
              fallback)))))))

# SGPRField and SSrcField are the SAME spelling with and without the default,
# so the six SGPR/SSRC kinds collapse onto two strings and only the default
# differs.  `hilo` cannot be spelled from the fallback alone, so the default
# variants are assembled here.
def field_def.hilo(kind: U32) -> String: "?"

def field_def(name: String, hi: U32, lo: U32, fmt: String, enc_bits: String, has_bits: Bool,
              fixed: List<&2, Fv>, encs: List<&2, EC>, enums: List<&2, EO>, arch: String) -> String:
  field_def.enc(name, hi, lo, fmt, enc_bits, has_bits, fixed, encs, enums, arch)

def field_def.enc(name: String, hi: U32, lo: U32, fmt: String, enc_bits: String, has_bits: Bool,
                  +fixed: List<&2, Fv>, +encs: List<&2, EC>, +enums: List<&2, EO>, arch: String) -> String:
  match field_def.k0(String.eq(name, "encoding"), has_bits):
    case True{}: "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ enc_bits ++ ")"
    case False{}: field_def.fix(name, hi, lo, fmt, enc_bits, has_bits, fixed, encs, enums, arch)

def field_def.k0(same: Bool, has_bits: Bool) -> Bool: Bool.and(same, has_bits)