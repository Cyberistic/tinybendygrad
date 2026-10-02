# ===========================================================================
# SECTION 5 -- the fixture shapes, `field_def`, and the emitters.
#
# `field_def` is generate.py:295-318 and it is a SEVENTEEN-ARM LADDER over
# (field name, bit width, format, arch, enc_bits).  Its ORDER is load-bearing:
# `soffset` at 7 bits is `SGPRField` and at 8 bits it is `SSrcField`, and the
# `ssrc*`-at-8 arm is tested BEFORE the `saddr`/`soffset`-at-8 arm.  So the
# ladder is a TABLE here, in source order, and the walk returns the FIRST
# match.  The table IS the spec; reordering the table reorders the spec.
#
# THE KIND CODES ARE `K2_*`, NOT `dsl.bend`'s `K_*`, DELIBERATELY.  dsl.bend
# exports `K_PLAIN`/`K_FIXED`/`K_ENUM`/`K_SRC`/`K_VGPR`/`K_SGPR`/`K_SSRC`/
# `K_ALIGN`/`K_SBASE`/`K_SRSC`/`K_VDSTY`, which classify the SAME eleven
# classes -- at the ENCODE side, where `SGPRField(7,0)` is ONE class.  The
# generator emits `SGPRField(hi, lo)` and `SGPRField(hi, lo, default=NULL)` as
# two DIFFERENT lines, so importing dsl's codes would alias them and every
# `field_def` row would be blind to exactly that swap.  Two code spaces, and
# this paragraph is the reason.  REPORTED to the coordinator: if one code space
# is preferred, the default variants have to gain a bit over there first.
#
# `ctor_names` / `arg3_names` are INDEXED TABLES of eighteen strings rather than
# eighteen-arm matches, because a `match` may not scrutinise a computed value
# and an eighteen-deep `.of` chain would be thirty-six defs.
# ===========================================================================

# pk: 0 nm == pa | 1 starts_with(nm, pa) | 2 nm in pa(words)
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
   R{0, "vdsty", 0, 0, K2_VDSTY()}, R{2, "", 1, 0, K2_VGPR()},
   R{0, "sbase", 1, 0, K2_SBASE()}, R{0, "srsrc", 1, 0, K2_SRSC()}, R{0, "ssamp", 1, 0, K2_SRSC()},
   R{0, "sdst", 1, 0, K2_SGPR()}, R{0, "sdata", 1, 0, K2_SGPR()},
   R{0, "soffset", 1, 0, K2_SGPRN()}, R{0, "saddr", 1, 0, K2_SGPRN()},
   R{1, "ssrc", 1, 0, K2_SSRC()}, R{0, "saddr", 1, 0, K2_SSRCN()}, R{0, "soffset", 1, 0, K2_SSRCN()},
   R{1, "src", 1, 0, K2_SRC9()},
   R{0, "offset", 0, 2, K2_OFF13()},
   R{0, "opsel_hi", 0, 0, K2_OPHI3()}, R{0, "opsel_hi2", 0, 0, K2_OPHI21()}]

# The constructor name per kind.  THREE names repeat (SGPRField, SSrcField,
# BitField) and they repeat here on purpose: a separate table would be a second
# source of truth for which kinds share a spelling.
def ctor_names() -> List<&2, String>:
  ["BitField", "FixedBitField", "FixedBitField", "FixedBitField", "EnumBitField", "EnumBitField",
   "VDSTYField", "VGPRField", "SBaseField", "SRsrcField", "SGPRField", "SGPRField", "SSrcField",
   "SSrcField", "SrcField", "BitField", "BitField", "BitField"]

# The THIRD constructor argument per kind, "" when the arm has none.  Note
# `EnumBitField` appears TWICE with DIFFERENT third arguments (the base format
# versus the fixed `VOPDOp`), which is the reason this is a table and not a
# function of the constructor name.
def arg3_names() -> List<&2, String>:
  ["", "", "", "", "%Op", "VOPDOp", "", "", "", "", "", "default=NULL", "", "default=NULL", "",
   "", "default=3", "default=1"]

def ctor(kind: U32) -> String: str_at(ctor_names(), U32.to_nat(kind))

# `%Op` is the ONE placeholder: the emitted enum is the field's BASE FORMAT
# plus `Op`, so it cannot live in a constant table.
def arg3(kind: U32, base_fmt: String) -> String:
  Bool.pick(String, String.eq(arg3_raw(kind), "%Op"), base_fmt ++ "Op", arg3_raw(kind))

def arg3_raw(kind: U32) -> String: str_at(arg3_names(), U32.to_nat(kind))

# `f"{ctor}({hi}, {lo}{sep}{arg3})"` -- and an empty `arg3` must NOT leave a
# trailing comma, which is the `String.concat`-drops-a-literal class of bug in
# its most literal form.
def ctor_text(kind: U32, hi: U32, lo: U32, base_fmt: String) -> String:
  Bool.pick(String, String.is_empty(arg3(kind, base_fmt)),
    ctor(kind) ++ "(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ")",
    ctor(kind) ++ "(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", " ++ arg3(kind, base_fmt) ++ ")")

# `BitField(12, {lo})` -- the offset field of GLOBAL/SCRATCH is a SIGNED 13-bit
# field [12:0] whatever the XML says, and the XML says 12 bits for all three.
def field_def.hi_text(kind: U32, hi: U32) -> String:
  U32.show(Bool.pick(U32, U32.is_eq(kind, K2_OFF13()), 12, hi))

# ===========================================================================
# `field_def`, generate.py:295-318.  ARMS 1 AND 2 COME FIRST because they are
# the only two that consult FIXED_FIELDS, and both return a `FixedBitField`
# with a LITERAL value rather than a class.
#
# ARM 2's value is the interesting one.  FIXED_FIELDS says
# `{"x2encoding": ("VOP3P", "V_MFMA_LD_SCALE_B32")}`, and the emitted literal is
# that format's ENCODING BITS concatenated with the OPCODE of that instruction,
# zero-padded to the field width.  So the emitted `0b...` is a FUNCTION OF THE
# OTHER TABLES, and it is where a mis-transcribed opcode would land; the
# `cdna` `fd.emb` rows diff it against CPython's own emitted file.
# ===========================================================================

# `0b{fixed_bits}{opcode:0{bits-len(fixed_bits)}b}` -- `String.repeat` with a
# NEGATIVE count is the failure, so the padding width is clamped and the clamp
# is a named def rather than a hidden `max`.
def field_def.emb(hi: U32, lo: U32, fixed_bits: String, opcode: U32, width: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ fixed_bits ++
  String.repeat("0", pad_n(U32.sub(width, U32.to_nat(String.length(fixed_bits))))) ++ U32.show(opcode) ++ ")"

def pad_n(n: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(0n, n), n, 0n)

def field_def(nm: String, hi: U32, lo: U32, fmt: String, bits: String, has_bits: Bool,
              fixed: List<&2, Fd2>, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.enc(nm, hi, lo, fmt, bits, has_bits, fixed, encs, enums)

def field_def.enc(+nm: String, hi: U32, lo: U32, +fmt: String, +bits: String, has_bits: Bool,
                  +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  match field_def.k0(String.eq(nm, "encoding"), has_bits):
    case True{}: "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ bits ++ ")"
    case False{}: field_def.fix(nm, hi, lo, fmt, fixed, encs, enums)

def field_def.k0(is_enc: Bool, has_bits: Bool) -> Bool: Bool.and(is_enc, has_bits)

# FIXED_FIELDS is keyed by (arch, encoding, field).  The arch is a TABLE
# CONSTANT here -- the only entry is cdna's -- so it is not a third lookup
# level; conflating FIXED_FIELDS with FIELD_FIXES would be, and FIELD_FIXES is
# a field-LIST append done by `__main__`, not a lookup.  Two different tables.
def field_def.fix(+nm: String, hi: U32, lo: U32, +fmt: String, +fixed: List<&2, Fd2>,
                  +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  field_def.fix_of(fd_find(fixed, fmt, nm), nm, hi, lo, fmt, encs, enums)

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
# by NAME over one format's opcode table.  There is no `Maybe`-free spelling of
# a search, so `ec_op_of` answers 0 on a miss and `fd.emb` row for
# `x2encoding` is the row that would see it.
def field_def.fix_pair(g: Fd2, hi: U32, lo: U32, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.emb(hi, lo, EC.bits(ec_get(Fd2.e(g), encs)), ec_op_of(enums, Fd2.e(g), Fd2.k(g)),
    U32.sub(U32.add(hi, 1), lo))

def field_def.fd_find(kvs: List<&2, Fd2>, fmt: String, nm: String) -> Maybe<&2, Fd2>:
  match kvs:
    case Nil{}: None{}
    case k <> t:
      match String.eq(Fd2.fmt(k), fmt):
        case True{}: fd_find_kv(k, t, fmt, nm)
        case False{}: fd_find(t, fmt, nm)

def field_def.fix_kind(nm: String, hi: U32, lo: U32, fmt: String, encs: List<&2, EC>,
                       enums: List<&2, EO>) -> String:
  ctor_text(field_kind(nm, hi, lo, fmt), hi, lo, fmt)

def field_def.kind(nm: String, hi: U32, lo: U32, fmt: String, encs: List<&2, EC>,
                   enums: List<&2, EO>) -> String:
  field_def.fix_kind(nm, hi, lo, fmt, encs, enums)

# ---- THE LADDER ITSELF: `sorted`-independent FIRST MATCH over the table ----

def field_kind(nm: String, hi: U32, lo: U32, fmt: String) -> U32:
  field_kind.go(field_rules(), nm, U32.sub(U32.add(hi, 1), lo), get_base_fmt(fmt), fmt, K2_BIT())

def field_kind.go(rs: List<&2, R>, +nm: String, width: U32, +base_fmt: String, +fmt: String,
                  cur: U32) -> U32:
  match rs:
    case Nil{}: cur
    case r <> rest: field_kind.step(r, rest, nm, width, base_fmt, fmt, cur)

def field_kind.step(r: R, rest: List<&2, R>, +nm: String, width: U32, +base_fmt: String,
                    +fmt: String, cur: U32) -> U32:
  match r_ok(r, nm, width, base_fmt, fmt):
    case True{}: R.kind(r)
    case False{}: field_kind.go(rest, nm, width, base_fmt, fmt, cur)

def r_ok(r: R, +nm: String, width: U32, +base_fmt: String, +fmt: String) -> Bool:
  r_ok.pc(r_pk(R.pk(r), R.pa(r), nm), Bool.or(R.pb(r) == 0, R.pb(r) == width),
          fmt_exempt_b(R.pc(r), fmt, base_fmt))

def r_ok.pc(pk_ok: Bool, pb_ok: Bool, pc_ok: Bool) -> Bool: Bool.and(pk_ok, Bool.and(pb_ok, pc_ok))

def r_pk(pk: U32, pa: String, +nm: String) -> Bool:
  match pk:
    case 0: String.eq(nm, pa)
    case 1: String.starts_with(nm, pa)
    case _: vgpr_hit(nm, vgpr_fields())

def vgpr_hit(+nm: String, ws: List<&2, String>) -> Bool:
  match ws:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(h, nm), vgpr_hit(nm, t))

# pc: 0 any | 1 fmt not in (DPP,SDWA) | 2 base_fmt in (GLOBAL,SCRATCH).  The
# `DPP`/`SDWA` exemption is the ONE place `field_def` refuses to call an enum
# for a format whose `op` field is not an opcode, and it is a NOT IN test, so
# a fourth format would have to be added to BOTH this def and the comment.
def fmt_exempt(fmt: String) -> Bool: Bool.or(String.eq(fmt, "DPP"), String.eq(fmt, "SDWA"))

def fmt_exempt_b(pc: U32, fmt: String, base_fmt: String) -> Bool:
  Bool.pick(Bool, U32.is_eq(pc, 1), Bool.not(fmt_exempt(fmt)),
    Bool.pick(Bool, U32.is_eq(pc, 2),
      Bool.or(String.eq(base_fmt, "GLOBAL"), String.eq(base_fmt, "SCRATCH")), True{}))

# ===========================================================================
# THE RECORD SHAPES, and the FOUR DIFFERENT SORTS.  They are NOT
# interchangeable and a gate that only diffed counts would pass with all four
# collapsed into one:
#   sorted(ops.items())       -- by OPCODE; in write_ins the opcode IS the
#                                identity, so the sort is total.
#   sorted(encodings.items()) -- by ENCODING NAME, lexicographic.
#   sorted(fields, key=(order, lo)) -- the two-key ORDER sort of SECTION 4.
#   sorted(types.items())     -- by (name, encoding), a PAIR.
# ===========================================================================

type EO is Data: EO{fmt: String, ops: List<&2, OP>}
type EC is Data: EC{name: String, fields: List<&2, Fld>, bits: String, has_bits: Bool}

def EO.fmt(e: EO) -> String:
  match e:
    case EO{fmt, ops}: fmt
def EO.ops(e: EO) -> List<&2, OP>:
  match e:
    case EO{fmt, ops}: ops
def EO.of(f: String, os_: List<&2, OP>) -> EO: EO{f, os_}

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
def EC.miss() -> EC: EC{"", Nil{}, "", False{}}

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

# `next(op for op, n in enums[fmt].items() if n == nm)` -- the search by NAME.
# A miss answers 0 and says so in the caller; no gate row can reach the miss
# with the shipped FIXED_FIELDS table, and `fd.miss` says so out loud.
def ec_op_of(eos: List<&2, EO>, fmt: String, nm: String) -> U32:
  ec_op_of.of(op_find(ops_of(fmt, eos), nm), 0)

def op_find(os_: List<&2, OP>, nm: String) -> Maybe<&2, U32>:
  match os_:
    case Nil{}: None{}
    case o <> t:
      match String.eq(OP.nm(o), nm):
        case True{}: Some{OP.op(o)}
        case False{}: op_find(t, nm)

def ec_op_of.of(m: Maybe<&2, U32>, miss: U32) -> U32:
  match m:
    case None{}: miss
    case Some{g}: g

def ec_get(nm: String, encs: List<&2, EC>) -> EC:
  ec_get.of(ec_find(nm, encs), EC.miss())

def ec_get.of(m: Maybe<&2, EC>, miss: EC) -> EC:
  match m:
    case None{}: miss
    case Some{g}: g

def ec_find(nm: String, encs: List<&2, EC>) -> Maybe<&2, EC>:
  match encs:
    case Nil{}: None{}
    case e <> t:
      match String.eq(EC.name(e), nm):
        case True{}: Some{e}
        case False{}: ec_find(nm, t)

# ---- Fd2, the FIXED_FIELDS sum ------------------------------------------

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

def fd_find_kv(k: Fd2, t: List<&2, Fd2>, fmt: String, nm: String) -> Maybe<&2, Fd2>:
  match String.eq(Fd2.k(k), nm):
    case True{}: Some{k}
    case False{}: field_def.fd_find(t, fmt, nm)

# ===========================================================================
# SECTION 6 -- the emitted FILES, as LISTS OF LINES.
#
# WALL 3: four `with open(path, "w") as f: f.write("\n".join(lines))` calls,
# and bend's only sink is `IO.print`.  So every emitter returns
# `List<&2, String>` -- THE LINES -- and `main` prints them.  The line LIST is
# the port; `open` is the one line it does not make, and the shape difference
# is why the gate can diff the emission at all.
#
# `write_enum`, generate.py:273-287.
# ===========================================================================

# `suffix = "_E32" if name in ("VOP1","VOP2","VOPC") else "_E64" if name == "VOP3" else ""`
def enum_suffix(fmt: String) -> String:
  enum_suffix.e32(fmt) ++ enum_suffix.e64(fmt)

def enum_suffix.e32(fmt: String) -> String:
  Bool.pick(String, enum_suffix.e32_b(fmt), "_E32", "")

def enum_suffix.e32_b(fmt: String) -> Bool:
  Bool.or(String.eq(fmt, "VOP1"), Bool.or(String.eq(fmt, "VOP2"), String.eq(fmt, "VOPC")))

def enum_suffix.e64(fmt: String) -> String: Bool.pick(String, String.eq(fmt, "VOP3"), "_E64", "")

# `msuf = suffix if name != "VOP3" or op < 512 else ""` -- THE ONE place a VOP3
# opcode at 512 or above loses its `_E64`, and it is a `<` on the OPCODE, not
# on the enum name.  `member_suffix` is the same rule at the pcode call site.
def op_msuf(fmt: String, op: U32) -> String:
  op_msuf.of(String.eq(fmt, "VOP3"), op, enum_suffix(fmt))

def op_msuf.of(is_vop3: Bool, op: U32, suffix: String) -> String:
  Bool.pick(String, Bool.and(is_vop3, U32.is_le(512, op)), "", suffix)

def class_name(fmt: String) -> String:
  Bool.pick(String, enum_plain_b(fmt), fmt, fmt ++ "Op")

def enum_plain_b(fmt: String) -> Bool:
  Bool.or(String.eq(fmt, "HWREG"), String.eq(fmt, "MSG"))

def enum_members(fmt: String, eos: List<&2, EO>) -> List<&2, String>:
  enum_members.go(ops_of(fmt, eos), fmt, Nil{})

def enum_members.go(os_: List<&2, OP>, +fmt: String, acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> t:
      enum_members.go(t, fmt, List.append(&2, String, acc,
        [OP.nm(o) ++ op_msuf(fmt, OP.op(o)) ++ " = " ++ U32.show(OP.op(o))]))

# `f"class {name}(ReprEnum):" if name in ("HWREG","MSG") else f"class {name}Op(ReprEnum):"`
def write_enum(eos: List<&2, EO>) -> List<&2, String>:
  write_enum.go(sort_eos(eos), [
    "# autogenerated from AMD ISA XML - do not edit",
    "from tinygrad.runtime.autogen.amd.common import ReprEnum, Fmt, FMT_BITS, OpType  # noqa: F401", ""])

def write_enum.go(eos: List<&2, EO>, acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case e <> t:
      match List.is_empty(&2, OP, EO.ops(e)):
        case True{}: write_enum.go(t, acc)
        case False{}: write_enum.cls(EO.fmt(e), EO.ops(e), t, write_enum.go2(EO.fmt(e), EO.ops(e), acc))

def write_enum.go2(fmt: String, os_: List<&2, OP>, acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String, write_enum.aliases(fmt, sort_ops(os_)),
      write_enum.cells(fmt, sort_ops(os_))),
    List.append(&2, String, ["", "class " ++ class_name(fmt) ++ "(ReprEnum):"], acc))

def write_enum.cells(fmt: String, os_: List<&2, OP>) -> List<&2, String>:
  List.append(&2, String, ["class " ++ class_name(fmt) ++ "(ReprEnum):"],
    write_enum.aliases(fmt, os_))

# THE ALIAS PASS IS SECOND AND SEPARATE: `aliases` collects (mem, msuf) for
# every op that GOT a suffix and is emitted after all the value cells, so
# `V_CNPY = V_CNPY_E32` follows `V_CNPY_E32 = 0`.  Folding the two passes into
# one list puts the aliases before the values, which is legal Python and a
# different file.
def write_enum.aliases(fmt: String, os_: List<&2, OP>) -> List<&2, String>:
  List.append(&2, String, write_enum.aliases.go(os_, fmt, Nil{}), [fmt: ""])

def write_enum.aliases.go(os_: List<&2, OP>, +fmt: String, acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> t:
      write_enum.aliases.go(t, fmt,
        Bool.pick(List<&2, String>, String.is_empty(op_msuf(fmt, OP.op(o))), acc,
          List.append(&2, String, acc, ["  " ++ OP.nm(o) ++ " = " ++ OP.nm(o) ++ op_msuf(fmt, OP.op(o))])))

# ===========================================================================
# `write_common`, generate.py:256-271.  `all_fmts` and `all_op_types` are the
# CROSS-ARCH union that `__main__` builds, and `sorted(all_fmts.keys())` is a
# LEXICOGRAPHIC sort of the keys with `sorted(all_fmts.items())` a second sort
# over the pairs.  Both are emitted, in that order, which is why the two
# `Fmt` blocks in common.py are in different orders for the same key set.
# ===========================================================================

type FB is Data: FB{nm: String, bits: U32}

def FB.nm(f: FB) -> String:
  match f:
    case FB{nm, bits}: nm
def FB.bits(f: FB) -> U32:
  match f:
    case FB{nm, bits}: bits

def fb_le(a: FB, b: FB) -> Bool: String.is_lt(FB.nm(a), FB.nm(b))
def sort_fbs(fs: List<&2, FB>) -> List<&2, FB>: List.sort(&2, FB, fb_le, fs)

def write_common(fbs: List<&2, FB>, ots: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, write_common.tail(sort_fbs(fbs), sort_strs(ots)), write_common.head())

def write_common.head() -> List<&2, String>:
  ["# autogenerated from AMD ISA XML - do not edit", "from enum import Enum, auto", "",
   "class ReprEnum(Enum):", '  """Enum with clean repr that roundtrips with eval()."""',
   "  def __repr__(self): return f\"{type(self).__name__}.{self.name}\"", "", "class Fmt(Enum):"]

def write_common.tail(fbs: List<&2, FB>, ots: List<&2, String>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String,
      List.append(&2, String, write_common.fmt_names(fbs), ["", "FMT_BITS = {"]),
      write_common.fmt_bits(fbs)),
    List.append(&2, String, ["}", "", "class OpType(Enum):"], write_common.ot_names(ots)))

def write_common.fmt_names(fbs: List<&2, FB>) -> List<&2, String>:
  write_common.fmt_names.go(fbs, Nil{})

def write_common.fmt_names.go(fbs: List<&2, FB>, acc: List<&2, String>) -> List<&2, String>:
  match fbs:
    case Nil{}: acc
    case f <> t: write_common.fmt_names.go(t, List.append(&2, String, acc, ["  " ++ FB.nm(f) ++ " = auto()"]))

def write_common.fmt_bits(fbs: List<&2, FB>) -> List<&2, String>:
  List.append(&2, String, write_common.fmt_bits.go(fbs, Nil{}), ["}"])

def write_common.fmt_bits.go(fbs: List<&2, FB>, acc: List<&2, String>) -> List<&2, String>:
  match fbs:
    case Nil{}: acc
    case f <> t:
      write_common.fmt_bits.go(t, List.append(&2, String, acc,
        ["  Fmt." ++ FB.nm(f) ++ ": " ++ U32.show(FB.bits(f)) ++ ","]))

def write_common.ot_names(ots: List<&2, String>) -> List<&2, String>:
  write_common.ot_names.go(ots, Nil{})

def write_common.ot_names.go(ots: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match ots:
    case Nil{}: acc
    case o <> t: write_common.ot_names.go(t, List.append(&2, String, acc, ["  " ++ o ++ " = auto()"]))

def str_le(a: String, b: String) -> Bool: String.is_lt(a, b)
def sort_strs(xs: List<&2, String>) -> List<&2, String>: List.sort(&2, String, str_le, xs)

# ===========================================================================
# `fmt_allowed`, generate.py:361-364, and `write_operands`/`fmt_val`,
# generate.py:464-482.
#
# `fmt_allowed` is "{EnumName.MEMBER, ...}" and its member names come from the
# ENUM TABLE, not from the operand set's own names, so a caller that formatted
# the members from `ops` directly would produce a different string whenever an
# opcode is in the set but absent from the enum.  `suffix_only_ops` supplies
# exactly such an opcode in the fixture.
# ===========================================================================

def fmt_allowed(op_enum: String, os_: List<&2, OP>, eos: List<&2, EO>) -> String:
  "{" ++ String.join(fmt_allowed.names(sort_ops(os_), remsuffix(op_enum, "Op"), eos), ", ") ++ "}"

def fmt_allowed.names(os_: List<&2, OP>, +base: String, eos: List<&2, EO>) -> List<&2, String>:
  fmt_allowed.names.go(os_, base, eos, Nil{})

def fmt_allowed.names.go(os_: List<&2, OP>, +base: String, eos: List<&2, EO>,
                         acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> t:
      fmt_allowed.names.go(t, base, eos, List.append(&2, String, acc,
        [OP.nm(op_named(base, OP.op(o), eos))]))

# `next(n for op, n in enums[base].items() if op == target)` -- the REVERSE
# search.  A miss answers the empty string, and `fmt_allowed` then emits
# `VOP1Op.` with nothing after the dot: visible, not silent.
def op_named(base: String, op: U32, eos: List<&2, EO>) -> String:
  op_named.of(op_find(ops_of(base, eos), U32.show(op)), "")

def op_find_nm(os_: List<&2, OP>, op: String) -> Maybe<&2, String>:
  match os_:
    case Nil{}: None{}
    case o <> t:
      match String.eq(U32.show(OP.op(o)), op):
        case True{}: Some{OP.nm(o)}
        case False{}: op_find_nm(t, op)

def op_named.of(m: Maybe<&2, String>, miss: String) -> String:
  match m:
    case None{}: miss
    case Some{g}: g

# `op_enum.removesuffix("Op")` -- every `fmt_allowed` caller passes `<fmt>Op`.
def remsuffix(s: String, p: String) -> String:
  Bool.pick(String, String.ends_with(s, p), String.take(s, U32.to_nat(U32.sub(String.length(s), String.length(p)))), s)

# `fmt_val`, generate.py:474-476.
# `f"({f'Fmt.{fmt}' if fmt else 'None'}, {size}, {f'OpType.{otype}' if otype else 'None'})"`
# -- note the order is FMT, SIZE, OTYPE, and both conditionals are FALSY tests,
# so an empty-string DataFormatName is `None` and not `Fmt.`.
type OI is Data: OI{nm: String, fmt: String, size: U32, otype: String}
type TY is Data: TY{name: String, base: String, flds: List<&2, OI>}

def OI.nm(o: OI) -> String:
  match o:
    case OI{nm, fmt, size, otype}: nm
def OI.fmt(o: OI) -> String:
  match o:
    case OI{nm, fmt, size, otype}: fmt
def OI.size(o: OI) -> U32:
  match o:
    case OI{nm, fmt, size, otype}: size
def OI.otype(o: OI) -> String:
  match o:
    case OI{nm, fmt, size, otype}: otype

def TY.name(t: TY) -> String:
  match t:
    case TY{name, base, flds}: name
def TY.base(t: TY) -> String:
  match t:
    case TY{name, base, flds}: base
def TY.flds(t: TY) -> List<&2, OI>:
  match t:
    case TY{name, base, flds}: flds

def fmt_val(v: OI) -> String:
  "(" ++ fmt_val.fmt(OI.fmt(v)) ++ ", " ++ U32.show(OI.size(v)) ++ ", " ++ fmt_val.otype(OI.otype(v)) ++ ")"

def fmt_val.fmt(f: String) -> String: Bool.pick(String, String.is_empty(f), "None", "Fmt." ++ f)
def fmt_val.otype(t: String) -> String: Bool.pick(String, String.is_empty(t), "None", "OpType." ++ t)
def oi_le(a: OI, b: OI) -> Bool: String.is_lt(OI.nm(a), OI.nm(b))
def sort_ois(xs: List<&2, OI>) -> List<&2, OI>: List.sort(&2, OI, oi_le, xs)

def fmt_val.cells(v: OI) -> String: "\"" ++ OI.nm(v) ++ "\": " ++ fmt_val(v)

def write_operands(tys: List<&2, TY>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String, ["# autogenerated from AMD ISA XML - do not edit", ""],
      List.append(&2, String, ["# instruction operand info: {Op: {field: (Fmt, size_bits, OpType)}}", "OPERANDS = {"],
        List.append(&2, String, write_operands.rows(sort_tys(tys)), ["}"])))

def sort_tys(tys: List<&2, TY>) -> List<&2, TY>: List.sort(&2, TY, ty_le, tys)

def ty_le(a: TY, b: TY) -> Bool:
  ty_le.pair(String.is_lt(TY.name(a), TY.name(b)), String.eq(TY.name(a), TY.name(b)),
    TY.base(a), TY.base(b))

def ty_le.pair(nm_lt: Bool, nm_eq: Bool, ba: String, bb: String) -> Bool:
  Bool.pick(Bool, nm_lt, True{}, Bool.pick(Bool, nm_eq, String.is_lt(ba, bb), False{}))

def write_operands.rows(tys: List<&2, TY>) -> List<&2, String>:
  write_operands.rows.go(tys, Nil{})

def write_operands.rows.go(tys: List<&2, TY>, acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case t <> rest:
      write_operands.rows.go(rest, List.append(&2, String, acc,
        ["  " ++ TY.base(t) ++ "Op." ++ TY.name(t) ++ ": {" ++
         String.join(write_operands.cells(sort_ois(TY.flds(t))), ", ") ++ "},"]))

def write_operands.cells(ois: List<&2, OI>) -> List<&2, String>:
  write_operands.cells.go(ois, Nil{})

def write_operands.cells.go(ois: List<&2, OI>, acc: List<&2, String>) -> List<&2, String>:
  match ois:
    case Nil{}: acc
    case o <> t: write_operands.cells.go(t, List.append(&2, String, acc, [fmt_val.cells(o)]))