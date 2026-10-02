# ===========================================================================
# SECTION 5 -- the fixture shapes and `field_def`.
#
# `field_def` is generate.py:295-318 and it is a SEVENTEEN-ARM LADDER over
# (field name, bit width, format, arch, enc_bits).  Its ORDER is load-bearing:
# `soffset` at 7 bits is `SGPRField` and at 8 bits it is `SSrcField`, and the
# `ssrc*`-at-8 arm is tested BEFORE the `saddr`/`soffset`-at-8 arm.  So the
# ladder is a TABLE here, in source order, and the walk returns the FIRST
# match.  The table IS the spec; reordering the table reorders the spec, and
# the gate row `rule N` diffs it against CPython's own emitted lines.
#
# THE KIND CODES ARE `K2_*`, NOT `dsl.bend`'s `K_*`, DELIBERATELY.  dsl.bend
# exports `K_PLAIN`/`K_FIXED`/`K_ENUM`/`K_SRC`/`K_VGPR`/`K_SGPR`/`K_SSRC`/
# `K_ALIGN`/`K_SBASE`/`K_SRSC`/`K_VDSTY`, which classify the SAME eleven
# classes -- but at the ENCODE side, where `SGPRField(7,0)` is ONE class.  The
# generator emits `SGPRField(hi, lo)` and `SGPRField(hi, lo, default=NULL)`
# as two DIFFERENT lines, so importing dsl's codes would alias them and the
# `field_def` rows would be blind to exactly that swap.  Two code spaces, and
# this paragraph is the reason.  REPORTED to the coordinator: if the owner
# prefers one code space, the default variants have to gain a bit there first.
#
# `ctor` and `arg3` are indexed TABLES of 18 strings rather than 18-arm
# matches, because a `match` may not scrutinise a computed value and an
# 18-deep `.of` chain would be 36 defs.  `U32.sub(hi, ...)`, `String.length`
# and `U32.to_nat` are the only arithmetic in the text builders.
# ===========================================================================

# pk: 0 nm == pa | 1 starts_with(nm, pa) | 2 base_fmt in pa(words) | 3 nm in pa(words)
# pb: 0 any width | 1 width == pb
# pc: 0 any format | 1 fmt not in (DPP,SDWA) | 2 base_fmt in (GLOBAL,SCRATCH)
type R is Data: R{pk: U32, pa: String, pb: U32, pc: U32, kind: U32}

def K2_BIT() -> U32: 0
def K2_ENCBITS() -> U32: 1
def K2_FIXINT() -> U32: 2
def K2_FIXEMB() -> U32: 3
def K2_ENOP() -> U32: 4
def K2_ENOPD() -> U32: 5
def K2_VDSTY() -> U32: 6
def K2_VGPR() -> U32: 7
def K2_SBASE() -> U32: 8
def K2_SRSC() -> U32: 9
def K2_SGPR() -> U32: 10
def K2_SGPRN() -> U32: 11
def K2_SSRC() -> U32: 12
def K2_SSRCN() -> U32: 13
def K2_SRC9() -> U32: 14
def K2_OFF13() -> U32: 15
def K2_OPHI3() -> U32: 16
def K2_OPHI21() -> U32: 17

def vgpr_fields() -> List<&2, String>:
  ["vdst", "vdstx", "vsrc0", "vsrc1", "vsrc2", "vsrc3", "vsrcx1", "vsrcy1", "vaddr",
   "vdata", "data", "data0", "data1", "addr", "vsrc"]

def field_rules() -> List<&2, R>:
  [R{0, "op", 0, 1, K2_ENOP()}, R{0, "opx", 0, 0, K2_ENOPD()}, R{0, "opy", 0, 0, K2_ENOPD()},
   R{0, "vdsty", 0, 0, K2_VDSTY()}, R{3, "", 1, 0, K2_VGPR()},
   R{0, "sbase", 1, 0, K2_SBASE()}, R{0, "srsrc", 1, 0, K2_SRSC()}, R{0, "ssamp", 1, 0, K2_SRSC()},
   R{0, "sdst", 1, 0, K2_SGPR()}, R{0, "sdata", 1, 0, K2_SGPR()},
   R{0, "soffset", 1, 0, K2_SGPRN()}, R{0, "saddr", 1, 0, K2_SGPRN()},
   R{1, "ssrc", 1, 0, K2_SSRC()}, R{0, "saddr", 1, 0, K2_SSRCN()}, R{0, "soffset", 1, 0, K2_SSRCN()},
   R{1, "src", 1, 0, K2_SRC9()},
   R{0, "offset", 0, 2, K2_OFF13()},
   R{0, "opsel_hi", 0, 0, K2_OPHI3()}, R{0, "opsel_hi2", 0, 0, K2_OPHI21()}]

# The constructor name per kind, indexed by kind.  EIGHTEEN entries, and the
# three repeated names (SGPRField, SSrcField, BitField) are repeated here on
# purpose: a separate table would be a second source of truth for which kinds
# share a spelling.
def ctor_names() -> List<&2, String>:
  ["BitField", "FixedBitField", "FixedBitField", "FixedBitField", "EnumBitField", "EnumBitField",
   "VDSTYField", "VGPRField", "SBaseField", "SRsrcField", "SGPRField", "SGPRField", "SSrcField",
   "SSrcField", "SrcField", "BitField", "BitField", "BitField"]

# The THIRD constructor argument per kind, "" when the arm has none.  Note
# `EnumBitField` appears twice with DIFFERENT third arguments (the base format
# vs the fixed `VOPDOp`), which is the reason this is a table and not a
# function of the constructor name.
def arg3_names() -> List<&2, String>:
  ["", "", "", "", "%Op", "VOPDOp", "", "", "", "", "", "default=NULL", "", "default=NULL", "",
   "", "default=3", "default=1"]

def ctor(kind: U32) -> String: str_at(ctor_names(), U32.to_nat(kind))

# `%Op` is the ONE placeholder: the emitted enum is the field's BASE FORMAT
# plus `Op`, so it cannot live in a constant table.
def arg3(kind: U32, base_fmt: String) -> String:
  Bool.pick(String, String.eq(str_at(arg3_names(), U32.to_nat(kind)), "%Op"),
    base_fmt ++ "Op", str_at(arg3_names(), U32.to_nat(kind)))

# `f"{ctor}({hi}, {lo}{sep}{arg3})"` -- and an empty `arg3` must NOT leave a
# trailing comma, which is the `String.concat`-drops-a-literal class of bug in
# its most literal form.
def ctor_text(kind: U32, hi: U32, lo: U32, base_fmt: String) -> String:
  Bool.pick(String, String.is_empty(arg3(kind, base_fmt)),
    ctor(kind) ++ "(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ")",
    ctor(kind) ++ "(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", " ++ arg3(kind, base_fmt) ++ ")")

# `BitField(12, {lo})` -- the offset field of GLOBAL/SCRATCH is a SIGNED 13-bit
# field [12:0] whatever the XML says, and the XML says 12 bits for all three.
def field_def.hi_text(kind: U32, hi: U32) -> String: U32.show(Bool.pick(U32, U32.is_eq(kind, K2_OFF13()), 12, hi))

# ===========================================================================
# `field_def`, generate.py:295-318.  ARMS 1 AND 2 COME FIRST because they are
# the only two that consult the FIXED_FIELDS table, and BOTH of them return a
# `FixedBitField` with a literal value rather than a class.
#
# ARM 2's value is the interesting one.  FIXED_FIELDS says
# `{"x2encoding": ("VOP3P", "V_MFMA_LD_SCALE_B32")}`, and the emitted literal is
# that format's ENCODING BITS concatenated with the OPCODE of that instruction,
# the opcode zero-padded to the field width.  So the emitted 0b... string is a
# FUNCTION OF THE OTHER TABLES -- it is where a mis-transcribed opcode would
# land, and the `cdna` rows diff it against CPython's own file.
# ===========================================================================

# `0b{fixed_bits}{opcode:0{bits-len(fixed_bits)}b}` -- `String.repeat` with a
# NEGATIVE count is the failure, so the padding width is clamped and the
# clamp is a named def rather than a hidden `max`.
def field_def.emb(hi: U32, lo: U32, fixed_bits: String, opcode: U32, width: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ fixed_bits ++
  String.repeat("0", pad_n(U32.sub(width, U32.to_nat(String.length(fixed_bits))))) ++ U32.show(opcode) ++ ")"

def pad_n(n: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(0n, n), n, 0n)

def field_def(nm: String, hi: U32, lo: U32, fmt: String, bits: String, has_bits: Bool,
              arch: String, ffx: List<&2, FLX>, fixed: List<&2, FD>, encs: List<&2, EC>,
              enums: List<&2, EO>) -> String:
  field_def.enc(nm, hi, lo, fmt, bits, has_bits, arch, ffx, fixed, encs, enums)

def field_def.enc(nm: String, hi: U32, lo: U32, fmt: String, bits: String, has_bits: Bool,
                  arch: String, ffx: List<&2, FLX>, fixed: List<&2, FD>, encs: List<&2, EC>,
                  enums: List<&2, EO>) -> String:
  match field_def.k0(String.eq(nm, "encoding"), has_bits):
    case True{}: "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ bits ++ ")"
    case False{}: field_def.fix(nm, hi, lo, fmt, bits, arch, ffx, fixed, encs, enums)

def field_def.k0(is_enc: Bool, has_bits: Bool) -> Bool: Bool.and(is_enc, has_bits)

# FIXED_FIELDS is {arch: {encoding: {field: int | (encoding, opcode)}}}, and it
# is `get`-ed with a THREE-key chain, so the three misses are three defs.
def field_def.fix(nm: String, hi: U32, lo: U32, fmt: String, bits: String, arch: String,
                  ffx: List<&2, FLX>, fixed: List<&2, FD>, encs: List<&2, EC>,
                  enums: List<&2, EO>) -> String:
  match field_def.fix_hit(ffx, arch, fmt, nm):
    case True{}: field_def.fix_val(nm, hi, lo, fmt, arch, fixed, encs, enums)
    case False{}: field_def.kind(nm, hi, lo, fmt, encs, enums)

def field_def.fix_hit(ffx: List<&2, FLX>, +arch: String, +fmt: String, +nm: String) -> Bool:
  ffx_has(ffx, arch, fmt, nm)

def ffx_arch(xs: List<&2, FLX>, arch: String, i: Nat) -> List<&2, FL>:
  match xs:
    case Nil{}: Nil{}
    case x <> t:
      match Nat.is_eq(i, 0n):
        case True{}:
          match String.eq(FX.arch(x), arch):
            case True{}: FL.fls(x)
            case False{}: Nil{}
        case False{}: ffx_arch(t, arch, Nat.sub(i, 1n))

def ffx_fmt(fs: List<&2, FL>, fmt: String, i: Nat) -> List<&2, Fx3>:
  match fs:
    case Nil{}: Nil{}
    case x <> t:
      match Nat.is_eq(i, 0n):
        case True{}:
          match String.eq(FL.fmt(x), fmt):
            case True{}: FL.flds(x)
            case False{}: Nil{}
        case False{}: ffx_fmt(t, fmt, Nat.sub(i, 1n))

def FL.fmt(x: FL) -> String:
  match x:
    case FL{fmt, flds}: fmt
def FL.flds(x: FL) -> List<&2, Fx3>:
  match x:
    case FL{fmt, flds}: flds

def ffx_has(xs: List<&2, FLX>, arch: String, fmt: String, nm: String) -> Bool:
  Bool.or(fx3_hit(ffx_fmt(ffx_arch(xs, arch, 0n), fmt, 0n), nm),
    fd_hit(fd_kvs(fixed_arch(xs, arch)), fmt, nm))

# ---- the two FIXED_FIELDS lookup shapes, as LIST walks --------------------

def fixed_arch(xs: List<&2, FLX>, arch: String, i: Nat) -> List<&2, FD>:
  match xs:
    case Nil{}: Nil{}
    case x <> t:
      match Nat.is_eq(i, 0n):
        case True{}:
          match String.eq(FX.arch(x), arch):
            case True{}: FD.fds(x)
            case False{}: Nil{}
        case False{}: fixed_arch(t, arch, Nat.sub(i, 1n))

def FD.fds(x: FD) -> List<&2, Fd2>:
  match x:
    case FD{fmt, kvs}: kvs

# `Fd2` is the FIXED_FIELDS inner `{field: int | (encoding, opcode)}` with the
# sum made explicit: `is_pair` says which arm, and the int arm carries its
# value in `e` as a decimal string so the record needs no second numeric field
# for a value that is sometimes an opcode.
type Fd2 is Data: Fd2{fmt: String, k: String, e: String, opc: U32, is_pair: Bool}

def fd_kvs(xs: List<&2, Fd2>, fmt: String, i: Nat) -> List<&2, Fd2>:
  match xs:
    case Nil{}: Nil{}
    case x <> t:
      match Nat.is_eq(i, 0n):
        case True{}:
          match String.eq(Fd2.fmt(x), fmt):
            case True{}: [x]
            case False{}: Nil{}
        case False{}: fd_kvs(t, fmt, Nat.sub(i, 1n))

def Fd2.fmt(x: Fd2) -> String:
  match x:
    case Fd2{fmt, k, e, opc, is_pair}: fmt
def Fd2.k(x: Fd2) -> String:
  match x:
    case Fd2{fmt, k, e, opc, is_pair}: k
def Fd2.e(x: Fd2) -> String:
  match x:
    case Fd2{fmt, k, e, opc, is_pair}: e
def Fd2.is_pair(x: Fd2) -> Bool:
  match x:
    case Fd2{fmt, k, e, opc, is_pair}: is_pair

def fv_of(k: String, e: String, opc: U32, is_pair: Bool) -> Fd2: Fd2{"", k, e, opc, is_pair}

def fx3_hit(fs: List<&2, Fx3>, nm: String) -> Bool:
  match fs:
    case Nil{}: False{}
    case f <> t: Bool.or(String.eq(Fx3.nm(f), nm), fx3_hit(t, nm))

def Fx3.nm(f: Fx3) -> String:
  match f:
    case Fx3{nm, hi, lo}: nm

def fd_hit(kvs: List<&2, Fd2>, fmt: String, nm: String) -> Bool:
  match kvs:
    case Nil{}: False{}
    case k <> t:
      match String.eq(Fd2.fmt(k), fmt):
        case True{}: Bool.or(String.eq(Fd2.k(k), nm), fd_hit(t, fmt, nm))
        case False{}: fd_hit(t, fmt, nm)

def fd_find(kvs: List<&2, Fd2>, fmt: String, nm: String) -> Maybe<&2, Fd2>:
  match kvs:
    case Nil{}: None{}
    case k <> t:
      match String.eq(Fd2.fmt(k), fmt):
        case True{}: fd_find_kv(k, t, fmt, nm)
        case False{}: fd_find(t, fmt, nm)

def fd_find_kv(k: Fd2, t: List<&2, Fd2>, fmt: String, nm: String) -> Maybe<&2, Fd2>:
  match String.eq(Fd2.k(k), nm):
    case True{}: Some{k}
    case False{}: fd_find(t, fmt, nm)

# FIXED_FIELDS has no FIELD_FIXES arm in generate.py: a fixed field is found by
# (arch, encoding, field) only, and the FIELD_FIXES list above is a DIFFERENT
# table (a field LIST append).  Conflating them is the one way to get this
# ladder wrong, so the two lookups are separate walks.
def field_def.fix_val(nm: String, hi: U32, lo: U32, fmt: String, arch: String,
                      fixed: List<&2, FD>, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.fix_of(fd_find(fixed, arch, nm), nm, hi, lo, fmt, encs, enums)

def field_def.fix_of(m: Maybe<&2, Fd2>, +nm: String, hi: U32, lo: U32, +fmt: String,
                     +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  match m:
    case None{}: field_def.kind(nm, hi, lo, fmt, encs, enums)
    case Some{g}:
      match Fd2.is_pair(g):
        case True{}: field_def.fix_pair(g, hi, lo, encs, enums)
        case False{}: field_def.fix_int(g, hi, lo)

def field_def.fix_int(g: Fd2, hi: U32, lo: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", " ++ Fd2.e(g) ++ ")"

# `next(op for op, n in enums[fixed[0]].items() if n == fixed[1])` -- a SEARCH
# by NAME over one format's opcode table, and there is no `Maybe`-free spelling
# of a search, so `ec_op_of` returns the opcode or 0 and `ec_op_found` says
# whether the search hit.  0 is the port's marker; the `cdna` row for
# `x2encoding` is the row that would see it.
def field_def.fix_pair(g: Fd2, hi: U32, lo: U32, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.emb(hi, lo, ec_bits(ec_get(Fd2.e(g), encs)), ec_op_of(enums, Fd2.e(g), Fd2.k(g)),
    U32.sub(U32.add(hi, 1), lo))

def ec_bits(e: EC) -> String:
  match e:
    case EC{name, fields, bits, has_bits}: bits

def ec_get(nm: String, encs: List<&2, EC>) -> EC:
  ec_get.of(ec_find(nm, encs), ec_missing())

def ec_missing() -> EC: EC{"", Nil{}, "", False{}}

def ec_get.of(m: Maybe<&2, EC>, miss: EC) -> EC:
  match m:
    case None{}: miss
    case Some{g}: g

def EC.name(e: EC) -> String:
  match e:
    case EC{name, fields, bits, has_bits}: name
def EC.fields(e: EC) -> List<&2, Fld>:
  match e:
    case EC{name, fields, bits, has_bits}: fields
def EC.bits(e: EC) -> String:
  match e:
    case EC{name, fields, bits, has_bits}: bits
def EC.has_bits(e: EC) -> Bool:
  match e:
    case EC{name, fields, bits, has_bits}: has_bits
def EC.of(nm: String, fs: List<&2, Fld>, bits: String, hb: Bool) -> EC: EC{nm, fs, bits, hb}

def ec_find(nm: String, encs: List<&2, EC>) -> Maybe<&2, EC>:
  match encs:
    case Nil{}: None{}
    case e <> t:
      match String.eq(EC.name(e), nm):
        case True{}: Some{e}
        case False{}: ec_find(nm, t)

def ec_op_of(enums: List<&2, EO>, fmt: String, nm: String) -> U32:
  ec_op_of.of(eo_find(eo_of_fmt(enums, fmt), nm), 0)

def eo_find(eos: List<&2, EO>, nm: String) -> Maybe<&2, OP>:
  match eos:
    case Nil{}: None{}
    case e <> t:
      match eo_name_hit(e, nm):
        case True{}: Some{OP.op(e)}
        case False{}: eo_find(t, nm)

def eo_name_hit(e: OP, nm: String) -> Bool: String.eq(OP.nm(e), nm)

def ec_op_of.of(m: Maybe<&2, U32>, miss: U32) -> U32:
  match m:
    case None{}: miss
    case Some{g}: g

# ===========================================================================
# THE SIX LIST HELPERS every emitter shares, and the ORDER they sort by.
#
# FOUR DIFFERENT SORTS appear in generate.py and they are NOT interchangeable:
#   sorted(ops.items())      -- by OPCODE, and in write_ins the opcode IS the
#                               identity, so a stable sort on it is total.
#   sorted(encodings.items())-- by ENCODING NAME, lexicographic.
#   sorted(fields, key=(order, lo)) -- the two-key ORDER sort of SECTION 4.
#   sorted(types.items())    -- by (name, encoding), a PAIR.
# A gate that only diffed counts would pass with all four collapsed into one.
# ===========================================================================

type OP is Data: OP{op: U32, nm: String}
type EO is Data: EO{fmt: String, ops: List<&2, OP>}
type EC2 is Data: EC2{name: String, fields: List<&2, Fld>, bits: String, has_bits: Bool}

def OP.op(o: OP) -> U32:
  match o:
    case OP{op, nm}: op
def OP.nm(o: OP) -> String:
  match o:
    case OP{op, nm}: nm
def OP.of(n: U32, nm: String) -> OP: OP{n, nm}

def EO.fmt(e: EO) -> String:
  match e:
    case EO{fmt, ops}: fmt
def EO.ops(e: EO) -> List<&2, OP>:
  match e:
    case EO{fmt, ops}: ops
def EO.of(f: String, os_: List<&2, OP>) -> EO: EO{f, os_}

def op_le(a: OP, b: OP) -> Bool: U32.is_lt(OP.op(a), OP.op(b))
def sort_ops(os_: List<&2, OP>) -> List<&2, OP>: List.sort(&2, OP, op_le, os_)
def ec_le(a: EC, b: EC) -> Bool: String.is_lt(EC.name(a), EC.name(b))
def sort_encs(es: List<&2, EC>) -> List<&2, EC>: List.sort(&2, EC, ec_le, es)
def eo_le(a: EO, b: EO) -> Bool: String.is_lt(EO.fmt(a), EO.fmt(b))
def sort_eos(es: List<&2, EO>) -> List<&2, EO>: List.sort(&2, EO, eo_le, es)

def eo_of_fmt(eos: List<&2, EO>, fmt: String) -> List<&2, OP>:
  eo_of_fmt.of(eo_find(eos, fmt))

def eo_of_fmt.of(m: Maybe<&2, EO>) -> List<&2, OP>:
  match m:
    case None{}: Nil{}
    case Some{g}: EO.ops(g)

def eo_find(eos: List<&2, EO>, fmt: String) -> Maybe<&2, EO>:
  match eos:
    case Nil{}: None{}
    case e <> t:
      match String.eq(EO.fmt(e), fmt):
        case True{}: Some{e}
        case False{}: eo_find(t, fmt)

def ops_of(fmt: String, eos: List<&2, EO>) -> List<&2, OP>: sort_ops(eo_of_fmt(eos, fmt))