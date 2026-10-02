# ================= INS-PART-2 =========================
# FOLD 1 -- THE BASE CLASSES.
#
# `base_allowed = all_ops - base_suffix_ops - sdst_opcodes.get(enc_name, set())`.
# Both subtractions are needed and neither is redundant: the first keeps a
# suffix-only op OUT of the base class, the second moves an SGPR-writing op to
# `VOP1_SDST`/`VOP3_SDST`.  The fixture has one op that is BOTH (VOP1 op 0 is
# `_LIT`-only AND VOP1 op 4 writes an SREG), which is what makes the order of the
# two subtractions unobservable here and therefore worth stating.
# ======================================================================

def base_allowed(encs: List<&2, EC>, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>,
                 +fmt: String) -> List<&2, U32>:
  u32_diff(u32_diff(all_ops(fmt, eos), base_suffix_ops.of(ss, fmt)), sdst_of(sdst_ops(tys, eos), fmt, Nil{}))

# `set(enums.get(name, {}).keys())`
def all_ops.of(os_: List<&2, OP>, +acc: List<&2, U32>) -> List<&2, U32>:
  match os_:
    case Nil{}: acc
    case +o <> t: all_ops.of(t, List.append(&2, U32, acc, [OP.op(o)]))

def all_ops(fmt: String, eos: List<&2, EO>) -> List<&2, U32>:
  dedup_u32(sort_u32s(all_ops.eos(eos, fmt, Nil{})))

def all_ops.eos(eos: List<&2, EO>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match eos:
    case Nil{}: acc
    case +e <> t: Bool.pick(List<&2, U32>, String.eq(EO.fmt(e), fmt),
      all_ops.eos(t, fmt, all_ops.of(EO.ops(e), acc)), all_ops.eos(t, fmt, acc))

# `seg = FixedBitField(hi, lo, SEG)` -- the literal is NOT a `0b` bitfield,
# unlike `encoding`, because `seg` is a plain integer in the DSL.
def base_field.seg(f: Fld, seg: U32) -> String:
  "seg = FixedBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++ U32.show(Fld.lo(f)) ++ ", " ++
    U32.show(seg) ++ ")"

def base_field.op(f: Fld, +oe: String, allowed: List<&2, U32>, eos: List<&2, EO>) -> String:
  "op = EnumBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++ U32.show(Fld.lo(f)) ++ ", " ++ oe ++ ", " ++
    fmt_allowed(oe, allowed, eos) ++ ")"

def base_field(f: Fld, +cls: String, +bits: String, hb: Bool, seg: U32, +oe: String,
               allowed: List<&2, U32>, eos: List<&2, EO>, fixed: List<&2, Fd2>,
               encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "seg"),
    List.append(&2, String, acc, [base_field.seg(f, seg)]),
    Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "op"),
      List.append(&2, String, acc, [base_field.op(f, oe, allowed, eos)]),
      List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++
        field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), cls, bits, hb, fixed, encs, eos)])))

def base_fields.go(fs: List<&2, Fld>, +cls: String, +bits: String, hb: Bool, seg: U32, +oe: String,
                   allowed: List<&2, U32>, eos: List<&2, EO>, fixed: List<&2, Fd2>,
                   encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> t: base_fields.go(t, cls, bits, hb, seg, oe, allowed, eos, fixed, encs,
      base_field(f, cls, bits, hb, seg, oe, allowed, eos, fixed, encs, acc))

# ONE FLAT CLASS: `class {cls}(Inst):` then its sorted fields then a blank.
def flat_class(fv: FV, e: EC, eos: List<&2, EO>, fixed: List<&2, Fd2>, encs: List<&2, EC>,
               +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String, ["class " ++ FV.cls(fv) ++ "(Inst):"],
    List.append(&2, String,
      base_fields.go(sort_fields(EC.fields(e)), FV.cls(fv), EC.bits(e), EC.has_bits(e),
        FV.seg(fv), FV.oe(fv), all_ops(FV.cls(fv), eos), eos, fixed, encs, Nil{}), [""])))

def flat_split.go(vs: List<&2, FV>, e: EC, eos: List<&2, EO>, fixed: List<&2, Fd2>,
                  encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: acc
    case +v <> t: flat_split.go(t, e, eos, fixed, encs, flat_class(v, e, eos, fixed, encs, acc))

# `op = EnumBitField(hi, lo, base_fmt + "Op", fmt_allowed(base_fmt + "Op", base_allowed))`
def plain_class(e: EC, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String,
    ["class " ++ EC.name(e) ++ "(Inst):"],
    List.append(&2, String,
      plain_fields.go(sort_fields(EC.fields(e)), e, eos, tys, ss, fixed, encs, Nil{}), [""])))

# The base class passes `enc_bits if fn == "encoding" else None`, so ONLY the
# `encoding` field is a FixedBitField here.  `field_def`'s `has_bits` flag IS
# that test, and passing it for every field would make `SGPRField` and
# `BitField` indistinguishable in the gate.
def plain_field(f: Fld, e: EC, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>,
                fixed: List<&2, Fd2>, encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "op"),
    List.append(&2, String, acc, ["  op = EnumBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++
      U32.show(Fld.lo(f)) ++ ", " ++ get_base_fmt(EC.name(e)) ++ "Op, " ++
      fmt_allowed(get_base_fmt(EC.name(e)) ++ "Op", base_allowed(encs, eos, tys, ss, EC.name(e)), eos) ++ ")"]),
    List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++ field_def(Fld.nm(f), Fld.hi(f),
      Fld.lo(f), EC.name(e), EC.bits(e), String.eq(Fld.nm(f), "encoding"), fixed, encs, eos)]))

def plain_fields.go(fs: List<&2, Fld>, e: EC, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>,
                    fixed: List<&2, Fd2>, encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> t: plain_fields.go(t, e, eos, tys, ss, fixed, encs,
      plain_field(f, e, eos, tys, ss, fixed, encs, acc))

def base_class(e: EC, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
               encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, is_flat_split(EC.name(e), seg_hit(EC.fields(e))),
    flat_split.go(flat_variants(EC.name(e)), e, eos, fixed, encs, acc),
    Bool.pick(List<&2, String>, skip_cls(EC.name(e)), acc,
      plain_class(e, eos, tys, ss, fixed, encs, acc)))

def base_classes(walk: List<&2, EC>, encs: List<&2, EC>, eos: List<&2, EO>, tys: List<&2, TY>,
                 ss: List<&2, SS>, fixed: List<&2, Fd2>, +acc: List<&2, String>) -> List<&2, String>:
  match walk:
    case Nil{}: acc
    case +e <> t: base_classes(t, encs, eos, tys, ss, fixed,
      base_class(e, eos, tys, ss, fixed, encs, acc))

# ======================================================================
# FOLD 2 -- THE VARIANT CLASSES.  `class {enc}({base})`, extra fields only.
# ======================================================================

# `next((sfx for sfx in _VARIANT_SUFFIXES if enc_name.endswith(sfx)), None)` --
# the FIRST matching suffix in TABLE order, not the longest.
def variant_suffix.go(nm: String, sfx: List<&2, String>, i: Nat, +acc: String) -> String:
  match sfx:
    case Nil{}: acc
    case +h <> t: Bool.pick(String, String.ends_with(nm, h), acc,
      variant_suffix.go(nm, t, Nat.add(i, 1n), h))

def variant_suffix(nm: String) -> String: variant_suffix.go(nm, variant_suffixes(), 0n, "")

def ss_has(ss: List<&2, SS>, +sfx: String) -> Bool:
  match ss:
    case Nil{}: False{}
    case +s <> t: Bool.or(String.eq(SS.sfx(s), sfx), ss_has(t, sfx))

# `is_suffix_variant = variant_suffix in suffix_only_ops`
def is_suffix_variant(nm: String, ss: List<&2, SS>) -> Bool: ss_has(ss, variant_suffix(nm))

# `extra_fields = [(fn,hi,lo) for fn,hi,lo in fields if fn not in base_fields]`
def extra_fields.go(fs: List<&2, Fld>, base_fs: List<&2, Fld>, +acc: List<&2, Fld>) -> List<&2, Fld>:
  match fs:
    case Nil{}: acc
    case +f <> t: Bool.pick(List<&2, Fld>, fld_in(base_fs, Fld.nm(f)),
      extra_fields.go(t, base_fs, acc), extra_fields.go(t, base_fs, List.append(&2, Fld, acc, [f])))

def fld_in(fs: List<&2, Fld>, +nm: String) -> Bool:
  match fs:
    case Nil{}: False{}
    case +f <> t: Bool.or(String.eq(Fld.nm(f), nm), fld_in(t, nm))

# `op_field = next((f for f in base_encodings[base][0] if f[0] == "op"), None)`
def base_op_field(base: EC) -> Maybe<&2, Fld>: fld_find(EC.fields(base), "op")

def fld_find.kv(+f: Fld, +nm: String) -> Maybe<&2, Fld>:
  Bool.pick(Maybe<&2, Fld>, String.eq(Fld.nm(f), nm), Some{f}, None{})

def fld_find.take(acc: Maybe<&2, Fld>, hit: Maybe<&2, Fld>) -> Maybe<&2, Fld>:
  match acc:
    case Some{g}: Some{g}
    case None{}: hit

def fld_find.of(fs: List<&2, Fld>, acc: Maybe<&2, Fld>, +nm: String) -> Maybe<&2, Fld>:
  match fs:
    case Nil{}: acc
    case +f <> r: fld_find.of(r, fld_find.take(acc, fld_find.kv(f, nm)), nm)

def fld_find(fs: List<&2, Fld>, +nm: String) -> Maybe<&2, Fld>: fld_find.of(fs, None{}, nm)

# `_LIT` allows ALL of the base format's opcodes; every other suffix-only
# variant allows exactly `suffix_only_ops[sfx][base]`.
def variant_allowed(base: EC, eos: List<&2, EO>, ss: List<&2, SS>, +sfx: String) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(sfx, "_LIT"), all_ops(EC.name(base), eos),
    sfx_ops(ss, sfx, EC.name(base)))

def variant_field(f: Fld, +cls: String, fixed: List<&2, Fd2>, encs: List<&2, EC>,
                  +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++
    field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), cls, "", False{}, fixed, encs, Nil{})])

def variant_fields.go(fs: List<&2, Fld>, +cls: String, fixed: List<&2, Fd2>, encs: List<&2, EC>,
                      +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> t: variant_fields.go(t, cls, fixed, encs, variant_field(f, cls, fixed, encs, acc))

def variant_op_line(m: Maybe<&2, Fld>, +base: EC, allowed: List<&2, U32>, eos: List<&2, EO>,
                    +acc: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}: acc
    case Some{g}: List.append(&2, String, acc,
      ["  op = EnumBitField(" ++ U32.show(Fld.hi(g)) ++ ", " ++ U32.show(Fld.lo(g)) ++ ", " ++
        EC.name(base) ++ "Op, " ++ fmt_allowed(EC.name(base) ++ "Op", allowed, eos) ++ ")"])

# `if extra_fields or is_suffix_variant` -- the emitted body of a variant is
# non-empty exactly when it has an extra field, and `is_suffix_variant` adds
# the `op` override even with no extra field at all.
def variant_fields_has(body: List<&2, String>) -> Bool: Bool.not(List.is_empty(&2, String, body))

def variant_class(e: EC, base: EC, eos: List<&2, EO>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                  encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  variant_class.of(e, base, eos, ss, fixed, encs,
    is_suffix_variant(EC.name(e), ss),
    variant_fields.go(sort_fields(extra_fields.go(EC.fields(e), EC.fields(base), Nil{})),
      EC.name(e), fixed, encs, Nil{}), acc)

def variant_class.of(e: EC, base: EC, eos: List<&2, EO>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                     encs: List<&2, EC>, sv: Bool, body: List<&2, String>,
                     +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.or(sv, variant_fields_has(body)),
    List.append(&2, String, acc, List.append(&2, String,
      ["class " ++ EC.name(e) ++ "(" ++ EC.name(base) ++ "):"],
      List.append(&2, String,
        Bool.pick(List<&2, String>, sv,
          variant_op_line(base_op_field(base), base, variant_allowed(base, eos, ss, variant_suffix(EC.name(e))), eos, Nil{}),
          Nil{}),
        List.append(&2, String, body, [""])))), acc)

def variant_classes(vs: List<&2, EC>, encs: List<&2, EC>, eos: List<&2, EO>, ss: List<&2, SS>,
                    fixed: List<&2, Fd2>, +acc: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: acc
    case +e <> t: variant_classes(t, encs, eos, ss, fixed,
      variant_class.of2(e, ec_get(get_base_fmt(EC.name(e)), encs), eos, ss, fixed, encs, acc))

# `if base not in base_encodings: continue` -- `ec_get` answers the EMPTY
# encoding on a miss, and `EC.name` of that is "", which no variant names.
def variant_class.of2(e: EC, base: EC, eos: List<&2, EO>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                      encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(EC.name(base), get_base_fmt(EC.name(e))), acc,
    variant_class(e, base, eos, ss, fixed, encs, acc))

# ======================================================================
# FOLD 3 -- THE SDST CLASSES.
# ======================================================================

def sdst_base_widened(base: EC, eos: List<&2, EO>, tys: List<&2, TY>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(EC.name(base), "VOP3"),
    u32_union(sdst_of(sdst_ops(tys, eos), EC.name(base), Nil{}),
      u32_filter(all_ops(EC.name(base), eos))),
    sdst_of(sdst_ops(tys, eos), EC.name(base), Nil{}))

def sdst_empty(xs: List<&2, U32>) -> Bool: List.is_empty(&2, U32, xs)

def sdst_lit(vs: List<&2, EC>, +base: String) -> Maybe<&2, EC>: ec_find(base ++ "_LIT", vs)

def sdst_lit_field(vs: List<&2, EC>, +base: String) -> Maybe<&2, Fld>:
  sdst_lit_field.of(sdst_lit(vs, base))

def sdst_lit_field.of(m: Maybe<&2, EC>) -> Maybe<&2, Fld>:
  match m:
    case None{}: None{}
    case Some{g}: fld_find(EC.fields(g), "literal")

def sdst_one(base: EC, eos: List<&2, EO>, tys: List<&2, TY>, vs: List<&2, EC>,
             fixed: List<&2, Fd2>, encs: List<&2, EC>, field_hi: U32, field_lo: U32,
             +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.or(sdst_empty(sdst_of(sdst_ops(tys, eos), EC.name(base), Nil{})),
    String.eq(EC.name(base), "")),
    acc,
    List.append(&2, String, acc, List.append(&2, String,
      ["class " ++ EC.name(base) ++ "_SDST(" ++ EC.name(base) ++ "):"],
      List.append(&2, String,
        variant_op_line(base_op_field(base), base, sdst_base_widened(base, eos, tys), eos, Nil{}),
        List.append(&2, String, ["  vdst = SSrcField(" ++ U32.show(field_hi) ++ ", " ++
          U32.show(field_lo) ++ ")"], [""])))))

def sdst_lit_lines(base: EC, vs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  sdst_lit_lines.of(base, sdst_lit_field(vs, EC.name(base)), acc)

def sdst_lit_lines.of(base: EC, m: Maybe<&2, Fld>, +acc: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}: acc
    case Some{g}: List.append(&2, String, acc, List.append(&2, String,
      ["class " ++ EC.name(base) ++ "_SDST_LIT(" ++ EC.name(base) ++ "_SDST):"],
      List.append(&2, String, ["  literal = BitField(" ++ U32.show(Fld.hi(g)) ++ ", " ++
        U32.show(Fld.lo(g)) ++ ")"], [""])))

# `[("VOP1", 24, 17), ("VOP3", 7, 0)]` -- the table AND the order.
type SD is Data: SD{base: String, hi: U32, lo: U32}

def SD.base(s: SD) -> String:
  match s:
    case SD{base, hi, lo}: base

def SD.hi(s: SD) -> U32:
  match s:
    case SD{base, hi, lo}: hi

def SD.lo(s: SD) -> U32:
  match s:
    case SD{base, hi, lo}: lo

def sdst_targets() -> List<&2, SD>: [SD{"VOP1", 24, 17}, SD{"VOP3", 7, 0}]

def sdst_walk.go(tds: List<&2, SD>, eos: List<&2, EO>, tys: List<&2, TY>, vs: List<&2, EC>,
                 fixed: List<&2, Fd2>, encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match tds:
    case Nil{}: acc
    case +d <> t: sdst_walk.go(t, eos, tys, vs, fixed, encs,
      sdst_lit_lines(ec_get(SD.base(d), encs), vs,
        sdst_one(ec_get(SD.base(d), encs), eos, tys, vs, fixed, encs, SD.hi(d), SD.lo(d), acc)))

def sdst_classes(eos: List<&2, EO>, tys: List<&2, TY>, vs: List<&2, EC>, fixed: List<&2, Fd2>,
                 encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  sdst_walk.go(sdst_targets(), eos, tys, vs, fixed, encs, acc)