# ================= INS-PART-1 =========================
# `write_ins`, generate.py:289-462: the CLASS TREE and the helpers.
#
# The inherited file stopped at `field_def`, which is the 17-arm field ladder
# inside `write_ins`, and never emitted a class.  Everything below is the other
# half of the same function, and the whole emitted `ins.py` is ONE gate row
# (`ins rdna3`, `ins cdna`) because a count row is identical for a dropped
# member, a dropped alias, a swapped `default=NULL` and a reordered field.
#
# FOUR FOLDS, in upstream order, and the order is the file:
#   1. base classes -- with the RDNA3 `seg` special case that splits FLAT into
#      FLAT/GLOBAL/SCRATCH and VFLAT into VFLAT/VGLOBAL/VSCRATCH, and the
#      EXCLUSION list (`FLAT_GLOBAL`, `FLAT_SCRATCH`, `FLAT_GLBL`, `DPP`,
#      `SDWA`) that emits nothing at all;
#   2. variant classes -- only the fields the base does NOT already have, plus
#      an `op` override when the variant is a SUFFIX-ONLY variant;
#   3. the SDST classes -- `VOP1_SDST`/`VOP3_SDST` and their `_LIT` children,
#      with `VOP3` widened by every opcode below 256;
#   4. `functools.partial` helpers -- the only place `ADDTID` is dropped.
#
# `Bool.pick` IS NEVER USED TO SEQUENCE A WALK.  It chooses between two
# already-computed values, so every fold below passes the self-call as an
# ARGUMENT and puts only the accumulator in the pick.
# ======================================================================

type SG is Data: SG{fmt: String, ops: List<&2, U32>}

type SS is Data: SS{sfx: String, gs: List<&2, SG>}

type FV is Data: FV{cls: String, seg: U32, oe: String}

# ---- THE OPCODE-SET ALGEBRA ------------------------------------------
# `enums`, `suffix_only_ops` and `sdst_opcodes` are SETS OF OPCODES in the
# Python, and three of the four class folds are set difference or set union
# over them, so the set algebra has to exist before any class does.

def u32_le(a: U32, b: U32) -> Bool: U32.is_lt(a, b)

def sort_u32s(xs: List<&2, U32>) -> List<&2, U32>: List.sort(U32, u32_le, xs)

def u32_in(x: U32, xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(U32.is_eq(h, x), u32_in(x, t))

def dedup_u32.step(x: U32, last: U32, acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(x, last), acc, List.append(&2, U32, acc, [x]))

def dedup_u32.go(xs: List<&2, U32>, last: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> t: dedup_u32.go(t, x, dedup_u32.step(x, last, acc))

def dedup_u32(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case +x <> t: dedup_u32.go(t, x, [x])

def u32_diff.go(xs: List<&2, U32>, ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> t: u32_diff.go(t, ys, Bool.pick(List<&2, U32>, u32_in(x, ys), acc,
      List.append(&2, U32, acc, [x])))

# `A - B`, and `A - B - C` is left-associative so one subtraction is enough.
def u32_diff(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  dedup_u32(sort_u32s(u32_diff.go(xs, ys, Nil{})))

def u32_union(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  dedup_u32(sort_u32s(List.append(&2, U32, xs, ys)))

# `op for op in all_base_ops if op < 256` -- the VOP3 SDST widening.
def u32_filter.go(xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> t: u32_filter.go(t, Bool.pick(List<&2, U32>, U32.is_lt(x, 256),
      List.append(&2, U32, acc, [x]), acc))

def u32_filter(xs: List<&2, U32>) -> List<&2, U32>: u32_filter.go(xs, Nil{})

# ---- `suffix_only_ops`, the {suffix: {fmt: {opcode}}} table ----------
# `suffix_only_ops.values()` is a list of dicts of sets, and three different
# questions are asked of it: does a format's BASE class exclude these opcodes,
# does a variant class ALLOW them, and which CLASS does an opcode's helper use.

def SG.fmt(g: SG) -> String:
  match g:
    case SG{fmt, ops}: fmt

def SG.ops(g: SG) -> List<&2, U32>:
  match g:
    case SG{fmt, ops}: ops

def SS.sfx(s: SS) -> String:
  match s:
    case SS{sfx, gs}: sfx

def SS.gs(s: SS) -> List<&2, SG>:
  match s:
    case SS{sfx, gs}: gs

def sg_hit(g: SG, op: U32) -> Bool: u32_in(op, SG.ops(g))

def sg_go(gs: List<&2, SG>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match gs:
    case Nil{}: acc
    case +g <> t: Bool.pick(List<&2, U32>, String.eq(SG.fmt(g), fmt),
      sg_go(t, fmt, u32_union(acc, SG.ops(g))), sg_go(t, fmt, acc))

# ONE WALK answers every question of the form `d.get(fmt, set())`: the union of
# the groups whose format matches, which for a MISSING format is `Nil{}`.
def sg_ops_of(gs: List<&2, SG>, +fmt: String) -> List<&2, U32>: sg_go(gs, fmt, Nil{})

# `suffix_only_ops[suffix].get(fmt, set())` -- the table MISSES keys in the
# real data, so a miss is Nil{} and not an error.
def ss_go(ss: List<&2, SS>, +sfx: String, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> t: Bool.pick(List<&2, U32>, String.eq(SS.sfx(s), sfx),
      ss_go(t, sfx, fmt, sg_ops_of(SS.gs(s), fmt)), ss_go(t, sfx, fmt, acc))

def sfx_ops(ss: List<&2, SS>, +sfx: String, +fmt: String) -> List<&2, U32>:
  ss_go(ss, sfx, fmt, Nil{})

# `set().union(*(d.get(fmt, set()) for d in suffix_only_ops.values()))` -- what
# the BASE class of this format must NOT allow.
def base_suffix_ops(ss: List<&2, SS>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> t: base_suffix_ops(t, fmt, u32_union(acc, sg_ops_of(SS.gs(s), fmt)))

def base_suffix_ops.of(ss: List<&2, SS>, +fmt: String) -> List<&2, U32>:
  base_suffix_ops(ss, fmt, Nil{})

# `op_to_suffix = {op: suffix for suffix, ops in suffix_only_ops.items() for op in ops.get(fmt, set())}`
# -- the LAST suffix that claims an opcode wins, so the walk must not stop.
def op_sfx.go(ss: List<&2, SS>, +fmt: String, op: U32, +acc: String) -> String:
  match ss:
    case Nil{}: acc
    case +s <> t: op_sfx.go(t, fmt, op, Bool.pick(String, u32_in(op, sg_ops_of(SS.gs(s), fmt)),
      SS.sfx(s), acc))

def op_to_suffix(ss: List<&2, SS>, +fmt: String, op: U32) -> String:
  op_sfx.go(ss, fmt, op, "")

# ---- `sdst_opcodes`: ops whose `vdst` operand is an SGPR --------------
# `types.get((name, fmt), {})` then `.get("vdst", (None,None,None))[2] == "OPR_SREG"`.

def oi_hit(ois: List<&2, OI>, +nm: String) -> Bool:
  match ois:
    case Nil{}: False{}
    case +o <> t: Bool.or(String.eq(OI.nm(o), nm), oi_hit(t, nm))

def oi_otype(ois: List<&2, OI>, +nm: String, +acc: String) -> String:
  match ois:
    case Nil{}: acc
    case +o <> t: Bool.pick(String, String.eq(OI.nm(o), nm), oi_otype(t, nm, OI.otype(o)), acc)

def vdst_is_sreg(t: TY) -> Bool: String.eq(oi_otype(TY.flds(t), "vdst", ""), "OPR_SREG")

def ty_find.kv(+t: TY, +nm: String, +base: String) -> Maybe<&2, TY>:
  Bool.pick(Maybe<&2, TY>, Bool.and(String.eq(TY.name(t), nm), String.eq(TY.base(t), base)),
    Some{t}, None{})

def ty_find.take(acc: Maybe<&2, TY>, hit: Maybe<&2, TY>) -> Maybe<&2, TY>:
  match acc:
    case Some{g}: Some{g}
    case None{}: hit

# THE WALK NEVER STOPS AND NEVER NESTS.  A `match` on a parameter NESTED in a
# match arm is refused, and `Bool.pick` does not SEQUENCE a self-call, so
# first-hit-wins is `take` on an accumulator that the walk keeps feeding: the
# answer is the first match either way, and this shape is one `match`.
def ty_find.of(tys: List<&2, TY>, acc: Maybe<&2, TY>, +nm: String, +base: String) -> Maybe<&2, TY>:
  match tys:
    case Nil{}: acc
    case +t <> r: ty_find.of(r, ty_find.take(acc, ty_find.kv(t, nm, base)), nm, base)

def ty_find(tys: List<&2, TY>, +nm: String, +base: String) -> Maybe<&2, TY>:
  ty_find.of(tys, None{}, nm, base)

def sdst_hit(tys: List<&2, TY>, +nm: String, +fmt: String) -> Bool:
  ty_is_sreg(ty_find(tys, nm, fmt))

def ty_is_sreg(m: Maybe<&2, TY>) -> Bool:
  match m:
    case None{}: False{}
    case Some{g}: vdst_is_sreg(g)

def sdst_ops.ops(os_: List<&2, OP>, +fmt: String, tys: List<&2, TY>,
                 +acc: List<&2, U32>) -> List<&2, U32>:
  match os_:
    case Nil{}: acc
    case +o <> t: sdst_ops.ops(t, fmt, tys,
      Bool.pick(List<&2, U32>, sdst_hit(tys, OP.nm(o), fmt),
        List.append(&2, U32, acc, [OP.op(o)]), acc))

def sdst_ops.eos(eos: List<&2, EO>, tys: List<&2, TY>, +acc: List<&2, SG>) -> List<&2, SG>:
  match eos:
    case Nil{}: acc
    case +e <> t: sdst_ops.eos(t, tys, List.append(&2, SG, acc,
      [SG{EO.fmt(e), sdst_ops.ops(EO.ops(e), EO.fmt(e), tys, Nil{})}]))

def sdst_ops(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, SG>:
  sdst_ops.eos(eos, tys, Nil{})

def sdst_of(sgs: List<&2, SG>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match sgs:
    case Nil{}: acc
    case +g <> t: Bool.pick(List<&2, U32>, String.eq(SG.fmt(g), fmt),
      sdst_of(t, fmt, u32_union(acc, SG.ops(g))), sdst_of(t, fmt, acc))

# ---- the encoding split and the `seg` test ---------------------------

def bases.go(encs: List<&2, EC>, +acc: List<&2, EC>) -> List<&2, EC>:
  match encs:
    case Nil{}: acc
    case +e <> t: Bool.pick(List<&2, EC>, String.eq(get_base_fmt(EC.name(e)), EC.name(e)),
      bases.go(t, List.append(&2, EC, acc, [e])), bases.go(t, acc))

def bases(encs: List<&2, EC>) -> List<&2, EC>: bases.go(sort_encs(encs), Nil{})

def variants.go(encs: List<&2, EC>, +acc: List<&2, EC>) -> List<&2, EC>:
  match encs:
    case Nil{}: acc
    case +e <> t: Bool.pick(List<&2, EC>, String.eq(get_base_fmt(EC.name(e)), EC.name(e)),
      variants.go(t, acc), variants.go(t, List.append(&2, EC, acc, [e])))

def variants(encs: List<&2, EC>) -> List<&2, EC>: variants.go(sort_encs(encs), Nil{})

def seg_hit(fs: List<&2, Fld>) -> Bool:
  match fs:
    case Nil{}: False{}
    case +f <> t: Bool.or(String.eq(Fld.nm(f), "seg"), seg_hit(t))

# `enc_name in ("FLAT_GLOBAL","FLAT_SCRATCH","FLAT_GLBL","DPP","SDWA")` -- the
# formats that get NO class at all, so the walk skips them.
def skip_cls(nm: String) -> Bool:
  Bool.or(String.eq(nm, "FLAT_GLOBAL"), Bool.or(String.eq(nm, "FLAT_SCRATCH"),
    Bool.or(String.eq(nm, "FLAT_GLBL"), Bool.or(String.eq(nm, "DPP"), String.eq(nm, "SDWA")))))

def is_flat_split(nm: String, has_seg: Bool) -> Bool:
  Bool.and(has_seg, Bool.or(String.eq(nm, "FLAT"), String.eq(nm, "VFLAT")))

# `prefix = "V" if enc_name == "VFLAT" else ""`
def flat_prefix(nm: String) -> String:
  Bool.pick(String, String.eq(nm, "VFLAT"), "V", "")

def flat_variants(nm: String) -> List<&2, FV>:
  [FV{flat_prefix(nm) ++ "FLAT", 0, flat_prefix(nm) ++ "FLATOp"},
   FV{flat_prefix(nm) ++ "GLOBAL", 2, flat_prefix(nm) ++ "GLOBALOp"},
   FV{flat_prefix(nm) ++ "SCRATCH", 1, flat_prefix(nm) ++ "SCRATCHOp"}]

def FV.cls(f: FV) -> String:
  match f:
    case FV{cls, seg, oe}: cls

def FV.seg(f: FV) -> U32:
  match f:
    case FV{cls, seg, oe}: seg

def FV.oe(f: FV) -> String:
  match f:
    case FV{cls, seg, oe}: oe

# ---- the import header -----------------------------------------------

def enum_names.ops(eos: List<&2, EO>, +plain: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case +e <> t: Bool.pick(List<&2, String>, Bool.eq(plain, enum_plain_b(EO.fmt(e))),
      enum_names.ops(t, plain, List.append(&2, String, acc, [EO.fmt(e) ++ "Op"])),
      enum_names.ops(t, plain, acc))

# `enum_names = sorted(f"{k}Op" for k in enums if enums[k] and k not in ("HWREG","MSG"))`
# then `enum_names += sorted(k for k in enums if k in ("HWREG","MSG") and enums[k])`.
# TWO SORTS AND A CONCATENATION, not one sort of the union: the plain enums are
# emitted last and unsuffixed, which is why the line ends `..., VSCRATCHOp, HWREG, MSG`.
def enum_names(eos: List<&2, EO>) -> List<&2, String>:
  List.append(&2, String, sort_strs(dedup_adj(enum_names.ops(sort_eos(eos), False{}, Nil{}))),
    sort_strs(dedup_adj(enum_names.ops(sort_eos(eos), True{}, Nil{}))))

# `all_field_defs = " ".join(field_def(fn, hi, lo, enc, eb) for enc, (flds, eb) in encodings.items() for fn, hi, lo in flds)`
def all_defs.go(walk: List<&2, EC>, fixed: List<&2, Fd2>, encs: List<&2, EC>, enums: List<&2, EO>,
                +acc: List<&2, String>) -> List<&2, String>:
  match walk:
    case Nil{}: acc
    case +e <> t: all_defs.go(t, fixed, encs, enums,
      List.append(&2, String, acc, all_defs.of(EC.fields(e), EC.name(e), EC.bits(e),
        EC.has_bits(e), fixed, encs, enums)))

def all_defs.of(fs: List<&2, Fld>, +enc: String, +bits: String, hb: Bool, fixed: List<&2, Fd2>,
                encs: List<&2, EC>, enums: List<&2, EO>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> t: all_defs.of(t, enc, bits, hb, fixed, encs, enums,
      List.append(&2, String, acc, [field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), enc, bits, hb,
        fixed, encs, enums)]))

def all_dsl() -> List<&2, String>:
  ["BitField", "EnumBitField", "FixedBitField", "NULL", "SBaseField", "SGPRField", "SRsrcField",
   "SSrcField", "SrcField", "VDSTYField", "VGPRField"]

def dsl_regs() -> List<&2, String>:
  ["s", "v", "src", "VCC_LO", "VCC_HI", "VCC", "EXEC_LO", "EXEC_HI", "EXEC", "NULL", "OFF", "M0",
   "SCC", "VCCZ", "EXECZ", "ttmp", "INV_2PI", "SDWA", "DPP", "DPP16", "LIT", "SRC_LDS_DIRECT"]

# `[n for n in _ALL_DSL if n in all_field_defs]` -- a SUBSTRING test over the
# joined field definitions, which is why the list is a flat string and not a
# set of classes: `SGPRField(1, 2)` and `SGPRField(1, 2, default=NULL)` are one
# class name here and TWO DIFFERENT LINES in the emission, which is exactly why
# this file uses its own `K2_*` codes and not `dsl.bend`'s.
def dsl_used(xs: List<&2, String>, +hay: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t: Bool.pick(List<&2, String>, String.contains(hay, x),
      dsl_used(t, hay, List.append(&2, String, acc, [x])), dsl_used(t, hay, acc))

def dsl_reexport(encs: List<&2, EC>, fixed: List<&2, Fd2>, eos: List<&2, EO>) -> List<&2, String>:
  dedup_adj(sort_strs(List.append(&2, String, dsl_used(all_dsl(),
    String.join(all_defs.go(sort_encs(encs), fixed, encs, eos, Nil{}), " "), Nil{}),
    List.append(&2, String, ["Inst"], dsl_regs()))))