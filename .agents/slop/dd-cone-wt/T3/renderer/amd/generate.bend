# tinybendygrad/renderer/amd/generate.bend -- tinygrad/renderer/amd/generate.py
#
# ===========================================================================
# THE GENERATOR.  541 Python lines that fetch AMD's machine-readable ISA XML
# bundle and three PDF manuals, walk them, and EMIT FOUR Python modules per
# architecture: `runtime/autogen/amd/{common,arch/{enum,ins,operands,str_pcode}}.py`.
#
# WHAT THIS FILE IS.  The DECISIONS, not the emitted strings -- the same ruling
# `runtime/support/autogen.bend` was ported under, and the same cost.  The four
# emitted modules are 30,000+ lines of Python that a Bend runtime could not
# execute, so porting them would be 30,000 lines of data in a language that
# cannot run it.  What has value is the 346 lines that DECIDE what gets emitted.
#
# THE MEASUREMENT, by `.agents/slop/ga-meas2.py` -> `ga-meas2.txt`, over all
# 541 lines, regions attributed to the enclosing TOP-LEVEL def (a nearest-`def`
# scan attributes 78 lines to the nested `_pv_val` and 103 to the nested
# `fmt_allowed`, which reads as though those two closures are the biggest
# functions in the file; they are not, `write_ins` is):
#
#   region                  tot  logic  emis  ffi
#   module(banner+config)     47     25     0     0
#   _strip_enc                 8      5     0     0
#   _norm_field                5      3     0     0
#   _map_flat                 15      8     1     0
#   parse_xml                 88     45     0    25
#   extract_pdf_text          44     22     0    16
#   extract_pcode             48     37     0     0
#   write_common              17     13     1     1
#   write_enum                16     12     1     1
#   write_ins                175    122    16     1
#   write_operands            20     13     2     1
#   write_pcode               21     13     1     1
#   __main__                  37     28     0     5
#   TOTAL                    541    346    22    51
#
#   LOGIC:EMISSION = 346:22 = 15.7 : 1, i.e. 94.0% of the core is LOGIC.
#   So the "a generator is mostly mechanical emission" story is wrong here too,
#   the same way it was wrong for autogen.py: a port of this generator is a
#   port of 346 decisions.  The 22 emission lines are the easy 6%.
#
# ===========================================================================
# THE FOUR WALLS. Stated once, here, rather than as a TODO per arm.
#
# WALL 1 -- the XML/PDF fetch and parse.  `parse_xml` is 25 ffi lines and
#   `extract_pdf_text` is 16, out of 132 for the pair.  `fetch` hits the
#   network, `zipfile.ZipFile` and `zlib.decompress` are compression, and
#   `root.findall(".//ISA/Instructions/Instruction")` is XPath -- there is no
#   Bend spelling for any of it and no `ElementTree`.  So the XML and the PDF
#   are FIXTURES here, values, exactly as `runtime/support/autogen.bend` makes
#   the libclang AST a value: "each field is a fact one call would have
#   returned".  EVERY DECISION THAT RUNS OVER THOSE FIXTURES IS PORTED AND
#   GATED; the descent that produces them is not, and the seam is named.
#
# WALL 2 -- regex.  `extract_pdf_text` matches `rb'startxref\s+(\d+)'`,
#   `rb'/Contents (\d+) 0 R'`, `r'BT(.*?)ET'` and a seven-alternative `_RE_BT`
#   with named groups.  bend 2.0.34 has no regex, no `String.replace`, and no
#   `String.split` on a multi-character separator.  Same ruling as
#   `autogen.bend`'s WALL 2, same reason: re-adding a regex engine is
#   Turing-completeness, which this repo does not permit without approval.
#   `extract_pdf_text` is therefore NOT PORTED and it is the largest single
#   omission in this file.
#
# WALL 3 -- writing files.  Four `with open(path, "w") as f: f.write(...)`
#   calls.  bend's only sink is `IO.print`, and a generator whose product is a
#   file needs a file.  So every emitter here returns `List<&2, String` -- THE
#   LINES -- and `main` prints them.  The line LIST is the port; `open` is the
#   one line it does not make.  That is a departure in shape and not in
#   content, and it is why the gate can diff the emission at all.
#
# WALL 4 -- `str.replace`.  There is no `String.replace` (notes position
#   11040), and generate.py calls `str.replace` in FOUR places
#   (`_strip_enc` x8 table entries, `_norm_field` x17, `get_base_fmt` x6,
#   `base_enum` x6).  Rather than call it a wall, this file writes the general
#   leftmost non-overlapping replace ONCE in SECTION 1 and calls it from all
#   four.  See `rep.go` for the algorithm and for why the PENDING flag is what
#   makes it one self-call rather than two.
#
# WALL 5 -- `F64`.  `extract_pcode` (37 logic lines, the second-largest region in
#   the file) groups text runs by `round(y)`, windows them with `55 < x < 65`,
#   `535 < x < 550`, `end_y < y2 < start_y`, `prev_y - curr_y > 30` and
#   `prev_y > 60 and curr_y < 730`, and `extract_pdf_text` builds those
#   coordinates by SUMMING PDF `Td` offsets into Python floats.  bend 2.0.34 has
#   `F32` and no `F64` -- `bend base --types` lists `F32` and `bend base | grep
#   -c F64` is 0 -- so every one of those seven decisions would be taken on 32-bit
#   values, and `round(y)`'s grouping (which is BANKER'S rounding in CPython and
#   half-away-from-zero in `F32.round`) is a different function, not a
#   differently-typed one.  `extract_pcode` is therefore NOT PORTED.  What IS
#   ported is `write_pcode`, its only consumer, and it is gated against the dict
#   CPython's own `extract_pcode` returns on the same pages fixture, so the seam
#   is a value and a gate row rather than a claim.
#
# ===========================================================================
# MEASURED bend 2.0.34 constraints that shape every def here.  Cite the
# positions in `.agents/slop/notes/bend2-constraints.md`, not rule numbers:
#
#   * A `match` may only scrutinise a PARAMETER or a PATTERN BINDER (pos 2146).
#     So every "is this Bool true" question gets its own def and the Bool
#     arrives as a parameter.  This file has one `.cmp`/`.hit`/`.ok` def per
#     decision, which is the single largest source of LOC here.
#   * `Bool.pick` CHOOSES an arm and BEND IS STRICT, so it EVALUATES BOTH
#     (pos 1389, 2106).  It is never used to guard a call, only to choose
#     between two already-computed values.
#   * `List.append(a, A, xs, ys)` is `xs ++ ys` (pos 1590), so an accumulator
#     that must stay in order either APPENDS or is reversed at the end.  Every
#     list-emitting fold in this file appends.
#   * `String.to_list` / `String.from_list` are the string walk: `take`/`drop`
#     CONSUME the string (pos 2000), so a substring walk is a walk over
#     `List<&2, Char>` and the needle is a `List<&2, Char>` too.
#   * No f-string interpolation (pos 11084), so every emitted line is built by
#     `++`, and a row NAME must already be interpolated.
#   * `do IO<Unit>:` must end with a BARE TERM (pos 3298) and may only bind
#     `IO(Unit)` (pos 11076), so a gate row is `def ... -> IO(Unit)` that
#     prints and returns nothing.
#   * `List.sort`'s comparator is `@_ -> @_ -> Bool`, i.e. BORROWED ONCE, and
#     every field accessor here is a `match` rather than a projection, so a
#     comparator on a two-key record must `match a b:` and compare the two
#     BINDERS.  Asking `PE.en(x)` for the same field twice is two consumptions.
#   * A def body that CONTINUES must continue with a term, not with an operator:
#     `f(x)` on one line and `++ y` on the next parses as two statements and bend
#     reports `expected : String` against the last argument of `f`.
#   * bend's machine stack is not a fixed budget: this file ran to completion on
#     8 of 8 idle runs and died with `the machine stack overflowed` on 2 of 12
#     back-to-back runs, so a harness that runs it ONCE will report a spurious
#     failure.  `ga_mutate.py` retries that error eight times.

import Base

# The replace accumulator: the OUT so far, the needle not yet matched (`need`),
# the matched-so-far chars (`done`, which are literal text if the match breaks),
# and the needle/replacement themselves so `rep.step` is a ONE-argument def.

type RS is Data:
  RS{out: List<&2, Char>, need: List<&2, Char>, done: List<&2, Char>,
     old: List<&2, Char>, new: List<&2, Char>}

# ===========================================================================

# ===========================================================================
# SECTION 1 -- the string algebra, once, because FOUR of generate.py's
# functions are `str.replace` and bend has none.
#
# `rep.go` is the general leftmost-first, non-overlapping replace, i.e. exactly
# Python's `str.replace(old, new)`.  The algorithm, and why it is ONE def:
#
#   Python finds the leftmost occurrence of `old`, emits `new`, and RESUMES
#   AFTER the replacement.  Written positionally that is "consume len(old) or
#   consume 1", which is TWO SELF-CALLS IN ONE ARM and is refused (pos 1908).
#   So the position is not carried; a PENDING flag in the accumulator is: the
#   walk always consumes exactly one Char, and the accumulator says whether
#   that Char extended a match, completed one, or is sitting in one.
#
#   THE NON-OBVIOUS CASE is the mismatch.  When a partial match breaks, the
#   chars already consumed are LITERAL TEXT and must be emitted, and the
#   CURRENT char must be re-tested as a fresh start -- otherwise "aa" over
#   "aaa" drops an "a".  `rep.match` does exactly that by delegating to
#   `rep.armed` with `done` already flushed, which is why this is exact for
#   BORDERED needles too and needs no unbordered precondition.
# ===========================================================================

type Suf is Data: Suf{old: String, new: String}

# bend has no `value.field` sugar and no auto projection, so every record read
# is a def.  These two are the whole `Suf` surface: the four replace tables.

type OP is Data: OP{op: U32, nm: String}

type FF is Data: FF{fmt: String, ops: List<&2, OP>}

type FX is Data: FX{arch: String, ffs: List<&2, FF>}

type Fx3 is Data: Fx3{nm: String, hi: U32, lo: U32}

type FL is Data: FL{fmt: String, flds: List<&2, Fx3>}

type FLX is Data: FLX{arch: String, fls: List<&2, FL>}

type Fd2 is Data: Fd2{fmt: String, k: String, e: String, onm: String, is_pair: Bool}

type Fld is Data: Fld{nm: String, hi: U32, lo: U32}

type R is Data: R{pk: U32, pa: String, pb: U32, pc: U32, kind: U32}

type EO is Data: EO{fmt: String, ops: List<&2, OP>}

type EC is Data: EC{name: String, fields: List<&2, Fld>, bits: String, has_bits: Bool}

type FB is Data: FB{nm: String, bits: U32}

type OI is Data: OI{nm: String, fmt: String, size: U32, otype: String}

type TY is Data: TY{name: String, base: String, flds: List<&2, OI>}

type VF is Data: VF{name: String, fmt: String}

type SG is Data: SG{fmt: String, ops: List<&2, U32>}

type SS is Data: SS{sfx: String, gs: List<&2, SG>}

type FV is Data: FV{cls: String, seg: U32, oe: String}

# `pcode` is `{(name, opcode): pseudocode}` and `write_pcode` walks it once per
# enum, so the key is a PAIR and a Bend record is the pair.  `PE` is one emitted
# entry, already carrying the `f"{fmt_name}Op"` half of its own key.

type PK is Data: PK{nm: String, op: U32, code: String}

type PE is Data: PE{en: String, mn: String, op: U32, code: String}

type SD is Data: SD{base: String, hi: U32, lo: U32}

def PK.nm(p: PK) -> String:
  match p:
    case PK{nm, +op, code}: nm

def PK.op(p: PK) -> U32:
  match p:
    case PK{nm, +op, code}: op

def PK.code(p: PK) -> String:
  match p:
    case PK{nm, +op, +code}: code

def PE.en(e: PE) -> String:
  match e:
    case PE{en, +mn, +op, code}: en

def PE.mn(e: PE) -> String:
  match e:
    case PE{en, +mn, op, code}: mn

def PE.op(e: PE) -> U32:
  match e:
    case PE{en, mn, +op, code}: op

def PE.code(e: PE) -> String:
  match e:
    case PE{en, mn, +op, +code}: code

# ---- THE OPCODE-SET ALGEBRA ------------------------------------------
# `enums`, `suffix_only_ops` and `sdst_opcodes` are SETS OF OPCODES in the
# Python, and three of the four class folds are set difference or set union
# over them, so the set algebra has to exist before any class does.

def Suf.old(s: Suf) -> String:
  match s:
    case Suf{old, new}: old

def Suf.new(s: Suf) -> String:
  match s:
    case Suf{old, new}: new

def rep.hit(nh: Char, +c: Char) -> Bool: Char.is_eq(c, nh)

# NOT currently matching: `c` either starts a new match or is literal.
# `Bool.pick` evaluates all three arms; `old`/`new` are read twice so `+`.

def rep.armed(+out: List<&2, Char>, +need: List<&2, Char>, +done: List<&2, Char>,
              +old: List<&2, Char>, +new: List<&2, Char>, +c: Char) -> RS:
  match old:
    case Nil{}: RS{List.append(&2, Char, out, [c]), Nil{}, Nil{}, old, new}
    case +oh <> +orest:
      RS{Bool.pick(List<&2, Char>, rep.hit(oh, c), out, List.append(&2, Char, out, [c])),
         Bool.pick(List<&2, Char>, rep.hit(oh, c), orest, Nil{}),
         Bool.pick(List<&2, Char>, rep.hit(oh, c), [c], Nil{}),
         old, new}

# A complete match emits `new` and DROPS the matched chars -- they are already
# in `out`?  No: a match never puts its chars in `out`, they sit in `done`.

def rep.grow(+nr: List<&2, Char>, +out: List<&2, Char>, +done: List<&2, Char>,
             +old: List<&2, Char>, +new: List<&2, Char>, +c: Char) -> RS:
  match nr:
    case Nil{}: RS{List.append(&2, Char, out, new), Nil{}, Nil{}, old, new}
    case _ <> _: RS{out, nr, List.append(&2, Char, done, [c]), old, new}

def rep.cmp(same: Bool, +nr: List<&2, Char>, +out: List<&2, Char>, +done: List<&2, Char>,
            +old: List<&2, Char>, +new: List<&2, Char>, +c: Char) -> RS:
  match same:
    case True{}: rep.grow(nr, out, done, old, new, c)
    case False{}: rep.armed(List.append(&2, Char, out, done), Nil{}, Nil{}, old, new, c)

def rep.match(+out: List<&2, Char>, +need: List<&2, Char>, +done: List<&2, Char>,
              +old: List<&2, Char>, +new: List<&2, Char>, +c: Char) -> RS:
  match need:
    case Nil{}: RS{out, Nil{}, Nil{}, old, new}
    case +nh <> +nr: rep.cmp(rep.hit(nh, c), nr, out, done, old, new, c)

# `need == Nil{}` IS the "not matching" case, so it must be an arm that
# dispatches, not one that falls through.

def rep.step(+ra: RS, +c: Char) -> RS:
  match ra:
    case RS{out, Nil{}, done, old, new}: rep.armed(out, Nil{}, done, old, new, c)
    case RS{out, need, done, old, new}: rep.match(out, need, done, old, new, c)

# End of input: whatever is still PENDING is literal text.

def rep.go(cs: List<&2, Char>, +ra: RS) -> List<&2, Char>:
  match cs:
    case Nil{}:
      match ra:
        case RS{out, need, done, old, new}: List.append(&2, Char, out, done)
    case +c <> +rest: rep.go(rest, rep.step(ra, c))

def str_repl_all(+cs: List<&2, Char>, +old: List<&2, Char>, +new: List<&2, Char>) -> List<&2, Char>:
  rep.go(cs, RS{Nil{}, Nil{}, Nil{}, old, new})

# The `s.replace(old, new)` of generate.py, as a String.

def repl(s: String, old: String, new: String) -> String:
  String.from_list(str_repl_all(String.to_list(s), String.to_list(old), String.to_list(new)))

# `s.removeprefix(p)` -- drop the prefix if it is there, else leave it alone.
# `+s, +p` MATTER: `String.eq`/`starts_with`/`drop` CONSUME their argument, and
# `Bool.pick` is strict, so this spends `s` three times.  A binder WITHOUT `+`
# is borrowed and may be consumed once only; `+` is what buys the second use.

def strip_prefix(+s: String, +p: String) -> String:
  Bool.pick(String, String.starts_with(s, p), String.drop(s, String.length(p)), s)

# ===========================================================================
# SECTION 2 -- the CONFIG TABLES, generate.py:11-42.  PORTED AS DATA, in
# DECLARATION ORDER, and the order is load-bearing twice over:
#   * `_FIELD_RENAMES` is a `dict`, so it is applied in INSERTION order, and
#     `op_sel_hi_2` must run BEFORE `op_sel` or the longer name is destroyed;
#   * `_ENC_SUFFIX_MAP` is applied in DESCENDING LENGTH order, by an explicit
#     `sorted(..., key=lambda x: -len(x[0]))` at generate.py:53, because
#     `_VOP_DPP` is a PREFIX of `_VOP_DPP8` and the wrong order mangles it.
#
# Both orders are gate rows (`order enc_suffix_map`, `order field_renames`)
# taken from CPython, not from this comment.
# ===========================================================================

def enc_suffixes() -> List<&2, String>: ["_NSA1"]

def skip_encodings() -> List<&2, String>: ["NSA"]

def enc_suffix_map() -> List<&2, Suf>:
  [Suf{"_VOP_SDWA_SDST_ENC", "_SDWA_SDST"}, Suf{"_INST_LITERAL", "_LIT"},
   Suf{"_VOP_DPP16", "_DPP16"}, Suf{"_VOP_DPP8", "_DPP8"}, Suf{"_VOP_SDWA", "_SDWA"},
   Suf{"_VOP_DPP", "_DPP16"}, Suf{"_MFMA", "_MFMA"}]

def field_renames() -> List<&2, Suf>:
  [Suf{"opsel_hi_2", "opsel_hi2"}, Suf{"op_sel_hi_2", "opsel_hi2"}, Suf{"op_sel", "opsel"},
   Suf{"bound_ctrl", "bc"}, Suf{"tgt", "target"}, Suf{"row_en", "row"}, Suf{"unorm", "unrm"},
   Suf{"clamp", "clmp"}, Suf{"wait_exp", "waitexp"}, Suf{"simm32", "literal"},
   Suf{"dpp_ctrl", "dpp"}, Suf{"acc_cd", "acc_cd"}, Suf{"acc", "acc"},
   Suf{"dst_sel", "dst_sel"}, Suf{"dst_unused", "dst_unused"},
   Suf{"src0_sel", "src0_sel"}, Suf{"src1_sel", "src1_sel"}]

# `NAME_MAP` -- the XML encoding name to the codebase enum name.  Applied to the
# ALREADY-STRIPPED name at :119 and to the ALREADY-`_map_flat`'d base at :131,
# which is why `VOP3_SDST_ENC` and `VOPDXY` must already be in the table: they
# are the two non-`ENC_` names `is_base` accepts.

def name_map() -> List<&2, Suf>:
  [Suf{"VOP3_SDST_ENC", "VOP3SD"}, Suf{"VOP3_SDST_ENC_LIT", "VOP3SD_LIT"},
   Suf{"VOP3_SDST_ENC_DPP16", "VOP3SD_DPP16"}, Suf{"VOP3_SDST_ENC_DPP8", "VOP3SD_DPP8"},
   Suf{"VOPDXY", "VOPD"}, Suf{"VOPDXY_LIT", "VOPD_LIT"}, Suf{"VDS", "DS"}]

# `FIXES` -- instructions present in the PDF but MISSING from the XML.  Nested
# {arch: {fmt: {opcode: name}}}, so `FF{fmt: String, ops: List<&2, OP>}`.

def OP.of(n: U32, nm: String) -> OP: OP{n, nm}

def OP.op(o: OP) -> U32:
  match o:
    case OP{+op, +nm}: op

def OP.nm(o: OP) -> String:
  match o:
    case OP{+op, +nm}: nm

def fixes() -> List<&2, FX>:
  [FX{"rdna3", [FF{"SOPK", [OP.of(22, "S_SUBVECTOR_LOOP_BEGIN"), OP.of(23, "S_SUBVECTOR_LOOP_END")]},
                FF{"FLAT", [OP.of(55, "FLAT_ATOMIC_CSUB_U32")]}]},
   FX{"rdna4", [FF{"SOP1", [OP.of(80, "S_GET_BARRIER_STATE"), OP.of(81, "S_BARRIER_INIT"),
                             OP.of(82, "S_BARRIER_JOIN")]},
                FF{"SOPP", [OP.of(9, "S_WAITCNT"), OP.of(21, "S_BARRIER_LEAVE")]}]},
   FX{"cdna", [FF{"DS", [OP.of(152, "DS_GWS_SEMA_RELEASE_ALL"), OP.of(154, "DS_GWS_SEMA_V"),
                         OP.of(156, "DS_GWS_SEMA_P")]},
               FF{"VOP3P", [OP.of(44, "V_MFMA_LD_SCALE_B32"), OP.of(62, "V_MFMA_F32_16X16X8_XF32"),
                             OP.of(63, "V_MFMA_F32_32X32X4_XF32")]}]}]

# `FIELD_FIXES` -- {arch: {encoding: [(name, hi, lo)]}}, appended to that
# encoding's field list by __main__:515.

def field_fixes() -> List<&2, FLX>:
  [FLX{"cdna", [FL{"VOP3P", [Fx3{"opsel_hi2", 14, 14}]}]}]

# `FIXED_FIELDS` -- {arch: {encoding: {field: int | (encoding, opcode)}}}.  A
# PAIR value, so it is a SUM type, not a record with an empty slot: `is_pair`
# says which arm and `e` carries either the decimal int or the OTHER ENCODING's
# name.  The table has exactly one arch (cdna) so the arch key is carried on
# the SECTION 5 records instead of being a third lookup level.

def fixed_fields() -> List<&2, Fd2>:
  [Fd2{"VOP3PX2", "x2encoding", "VOP3P", "V_MFMA_LD_SCALE_B32", True{}},
   Fd2{"VOP3PX2", "abid", "1", "", False{}}]

def archs() -> List<&2, String>: ["rdna3", "rdna4", "cdna"]

# THE INDEXED READER, shared: `xs[i]` as a COUNTDOWN, not as a comparison.
# `List.get` answers a `Maybe`, so every caller would be a two-def reader; and
# a comparison against the counter would need the Bool as a parameter, which
# makes `str_at` and `str_at.of` mutually recursive -- refused (pos 11109).
# Counting down to zero makes the index THE FUEL, so one def answers it.
# "?" is the port's marker for "index past the end".

def str_at(xs: List<&2, String>, n: Nat) -> String:
  match xs:
    case Nil{}: "?"
    case +h <> t:
      match n:
        case 0n: h
        case 1n+p: str_at(t, p)

# `ARCHS[a]["xml"]`, as a walk over the arch list rather than `List.get`: the
# two list literals below are the ONLY copy of the three filenames, and
# `List.get` answers a `Maybe`, which would make every caller a two-def
# reader for a table of constants.

# `ARCHS[a]["xml"]`, as a walk over the arch list rather than `List.get`: the
# two list literals below are the ONLY copy of the three filenames, and
# `List.get` answers a `Maybe`, which would make every caller a two-def
# reader for a table of constants.
# `len(s)` as a `U32`, because `U32.sub` takes `U32`s and `String.length`
# answers a `Nat`.  The two conversions are named so the widths are read
# at every site rather than at the point of the mistake.

def slen(s: String) -> U32: U32.from_nat(String.length(s))

def arch_xml(i: Nat) -> String: str_at(archs(), i)

def xml_url() -> String: "https://gpuopen.com/download/AMD_GPU_MR_ISA_XML_2025_09_05.zip"

# ===========================================================================
# SECTION 3 -- `_strip_enc` (:48), `_norm_field` (:56), `_map_flat` (:61).
# PORTED.  16 of the 28 logic lines of these three functions.
# ===========================================================================

# There is no `List.eq`, so membership is its own walk and the NEEDLE LEADS,
# because a self-call must shrink its first argument (pos 1922).

def str_in(+nm: String, o: List<&2, String>) -> Bool:
  match o:
    case Nil{}: False{}
    case +h <> +t: Bool.or(String.eq(h, nm), str_in(nm, t))

# `name.removeprefix("ENC_")`, then one `.replace` per `_ENC_SUFFIXES` entry,
# then one per `_ENC_SUFFIX_MAP` entry in its DESCENDING-LENGTH order.  THE
# TABLE LEADS in both, because `repl` GROWS the string: a self-call may not
# have CHANGED an argument before the one it shrinks (pos 1908).

def strip_enc.map(rs: List<&2, Suf>, s: String) -> String:
  match rs:
    case Nil{}: s
    case Suf{old, new} <> rest: strip_enc.map(rest, repl(s, old, new))

def strip_enc.sfx(sfx: List<&2, String>, s: String) -> String:
  match sfx:
    case Nil{}: strip_enc.map(enc_suffix_map(), s)
    case +h <> +t: strip_enc.sfx(t, repl(s, h, ""))

def strip_enc(name: String) -> String: strip_enc.sfx(enc_suffixes(), strip_prefix(name, "ENC_"))

# `_norm_field`: one `.replace` per entry, IN INSERTION ORDER.

def norm_field.go(rs: List<&2, Suf>, acc: String) -> String:
  match rs:
    case Nil{}: acc
    case Suf{old, new} <> rest: norm_field.go(rest, repl(acc, old, new))

def norm_field(name: String) -> String: norm_field.go(field_renames(), name)

# `_map_flat`: FLAT/GLOBAL/SCRATCH share ONE opcode field and are told apart by
# the INSTRUCTION's prefix, not the encoding's.  The V comes off the ENCODING.
# Every test is a `*_b` def and every dispatch is a `.of` that takes the answer
# as a PARAMETER, because a match may not scrutinise a call (pos 2146).  There
# is no shorter spelling of that rule; the `.of` split IS the cost.

def map_flat.glbl_b(+enc_name: String) -> Bool:
  Bool.or(String.eq(enc_name, "FLAT_GLBL"), String.eq(enc_name, "FLAT_GLOBAL"))

def map_flat.five_b(+enc_name: String) -> Bool:
  Bool.or(String.eq(enc_name, "FLAT"), Bool.or(String.eq(enc_name, "VFLAT"),
    Bool.or(String.eq(enc_name, "VGLOBAL"), String.eq(enc_name, "VSCRATCH"))))

def map_flat.v(enc_name: String) -> String: Bool.pick(String, String.starts_with(enc_name, "V"), "V", "")


# SECTION 4 -- `write_ins`'s nested helpers.  `_VARIANT_SUFFIXES`, `get_base_fmt`
# (:292), the field-kind ladder `field_def` (:295), `ORDER` + `sort_fields`
# (:319/:327) and `fmt_allowed` (:361).
# ===========================================================================

def map_flat.scratch_instr.of(enc_name: String, scr: Bool) -> String:
  match scr:
    case True{}: map_flat.v(enc_name) ++ "SCRATCH"
    case False{}: map_flat.v(enc_name) ++ "FLAT"

def map_flat.by_instr.of(enc_name: String, instr_name: String, glob: Bool) -> String:
  match glob:
    case True{}: map_flat.v(enc_name) ++ "GLOBAL"
    case False{}: map_flat.scratch_instr.of(enc_name, String.starts_with(instr_name, "SCRATCH_"))

def map_flat.prefixed.of(enc_name: String, +instr_name: String, five: Bool) -> String:
  match five:
    case True{}: map_flat.by_instr.of(enc_name, instr_name, String.starts_with(instr_name, "GLOBAL_"))
    case False{}: enc_name

def map_flat.scratch.of(+enc_name: String, instr_name: String, scr: Bool) -> String:
  match scr:
    case True{}: "SCRATCH"
    case False{}: map_flat.prefixed.of(enc_name, instr_name, map_flat.five_b(enc_name))

def map_flat.of(+enc_name: String, instr_name: String, glbl: Bool) -> String:
  match glbl:
    case True{}: "GLOBAL"
    case False{}: map_flat.scratch.of(enc_name, instr_name, String.eq(enc_name, "FLAT_SCRATCH"))

# `_map_flat`: FLAT/GLOBAL/SCRATCH share ONE opcode field and are told apart by
# the INSTRUCTION's prefix, not the encoding's.  The V comes off the ENCODING.
# Every test is a `*_b` def and every dispatch is a `.of` that takes the answer
# as a PARAMETER, because a match may not scrutinise a call (pos 2146).  There
# is no shorter spelling of that rule; the `.of` split IS the cost.

def map_flat(+enc_name: String, instr_name: String) -> String:
  map_flat.of(enc_name, instr_name, map_flat.glbl_b(enc_name))

def variant_suffixes() -> List<&2, String>: ["_LIT", "_DPP16", "_DPP8", "_SDWA_SDST", "_SDWA", "_MFMA"]

# `for sfx in _VARIANT_SUFFIXES: fmt = fmt.replace(sfx, "")` -- the TABLE LEADS
# because `repl` GROWS the string, and generate.py's loop carries no counter,
# so neither does this.

def get_base_fmt.go(sfx: List<&2, String>, fmt: String) -> String:
  match sfx:
    case Nil{}: fmt
    case +h <> +t: get_base_fmt.go(t, repl(fmt, h, ""))

def get_base_fmt(fmt: String) -> String: get_base_fmt.go(variant_suffixes(), fmt)

# `ORDER` -- the DECLARATION ORDER of a generated instruction's fields, which is
# NOT the bit order: `encoding` is bit 31 and is emitted FIRST, `offset` is bit
# 14 and is emitted 37th.  This list is the single most load-bearing table in
# the file: `ORDER.index(f[0]) if f[0] in ORDER else 999` is the sort key, so a
# name that is MISSING from it lands at 999 and sorts LAST, and a name that is
# present sorts by declaration, not by `lo`.

def Fld.lo(f: Fld) -> U32:
  match f:
    case Fld{+nm, +hi, +lo}: lo

def Fld.hi(f: Fld) -> U32:
  match f:
    case Fld{+nm, +hi, +lo}: hi

def base_field.seg(+f: Fld, seg: U32) -> String:
  "seg = FixedBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++ U32.show(Fld.lo(f)) ++ ", " ++
    U32.show(seg) ++ ")"

def op_le(a: OP, b: OP) -> Bool: U32.is_lt(OP.op(a), OP.op(b))

def sort_ops(os_: List<&2, OP>) -> List<&2, OP>: List.sort(OP, op_le, os_)

def remsuffix(+s: String, +p: String) -> String:
  Bool.pick(String, String.ends_with(s, p), String.take(s, U32.to_nat(U32.sub(slen(s), slen(p)))), s)

# `fmt_val`, generate.py:474-476.
# `f"({f'Fmt.{fmt}' if fmt else 'None'}, {size}, {f'OpType.{otype}' if otype else 'None'})"`
# -- note the order is FMT, SIZE, OTYPE, and both conditionals are FALSY tests,
# so an empty-string DataFormatName is `None` and not `Fmt.`.

def EO.ops(e: EO) -> List<&2, OP>:
  match e:
    case EO{+fmt, ops}: ops

def g(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", got, "]   py=[", want, "]"]))

# THE EMITTER ROWS ARE ONE ROW PER EMITTED FILE, the file JOINED by newline.
# A count row would be identical for a dropped member, a dropped alias, a
# swapped `default=NULL` and a reordered field; a string diff is not.  This is
# the renderer convention 2 applied to a GENERATOR: the answer is the file.

def eo_of_fmt.of(m: Maybe<&2, EO>) -> List<&2, OP>:
  match m:
    case None{}: Nil{}
    case Some{+g}: EO.ops(g)

def eo_find.take(acc: Maybe<&2, EO>, hit: Maybe<&2, EO>) -> Maybe<&2, EO>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def EO.fmt(e: EO) -> String:
  match e:
    case EO{+fmt, ops}: fmt

def eo_find.kv(+e: EO, +fmt: String) -> Maybe<&2, EO>:
  Bool.pick(Maybe<&2, EO>, String.eq(EO.fmt(e), fmt), Some{e}, None{})

def eo_find.go(eos: List<&2, EO>, +fmt: String, acc: Maybe<&2, EO>) -> Maybe<&2, EO>:
  match eos:
    case Nil{}: acc
    case +e <> r: eo_find.go(r, fmt, eo_find.take(acc, eo_find.kv(e, fmt)))

def eo_find(eos: List<&2, EO>, fmt: String) -> Maybe<&2, EO>:
  eo_find.go(eos, fmt, None{})

def eo_of_fmt(eos: List<&2, EO>, fmt: String) -> List<&2, OP>:
  eo_of_fmt.of(eo_find(eos, fmt))

def ops_of(fmt: String, eos: List<&2, EO>) -> List<&2, OP>: sort_ops(eo_of_fmt(eos, fmt))

# `next(op for op, n in enums[fmt].items() if n == nm)` -- the search by NAME.
# A miss answers 0 and says so in the caller; no gate row can reach the miss
# with the shipped FIXED_FIELDS table, and `fd.miss` says so out loud.

# `Maybe<&2, String>` OR a miss value.  Three call sites need it -- an opcode
# lookup, a field-def miss, and `write_pcode`'s `(name, opcode)` hit -- so it is
# one def named for what it does rather than for its first caller.

def maybe_str(m: Maybe<&2, String>, miss: String) -> String:
  match m:
    case None{}: miss
    case Some{+g}: g

# `op_enum.removesuffix("Op")` -- every `fmt_allowed` caller passes `<fmt>Op`.

# `next(n for op, n in enums[base].items() if op == target)` -- the REVERSE
# search.  A miss answers the empty string, and `fmt_allowed` then emits
# `VOP1Op.` with nothing after the dot: visible, not silent.

def op_find_nm.take(acc: Maybe<&2, String>, hit: Maybe<&2, String>) -> Maybe<&2, String>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def op_find_nm.kv(+o: OP, +op: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.eq(U32.show(OP.op(o)), op), Some{OP.nm(o)}, None{})

def op_find_nm.go(os_: List<&2, OP>, +op: String, acc: Maybe<&2, String>) -> Maybe<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> r: op_find_nm.go(r, op, op_find_nm.take(acc, op_find_nm.kv(o, op)))

def op_find_nm(os_: List<&2, OP>, op: String) -> Maybe<&2, String>:
  op_find_nm.go(os_, op, None{})

def op_named(base: String, op: U32, eos: List<&2, EO>) -> String:
  maybe_str(op_find_nm(ops_of(base, eos), U32.show(op)), "")

# `f"{op_enum}.{enums[op_enum.removesuffix('Op')][op]}"` -- the PREFIX is the
# enum class name and the LOOKUP is the stripped format, which are two different
# strings over one table.  The opcode set is SORTED first: `fmt_allowed` receives
# a Python `set` and the emission order is the opcode order.

# `fmt_allowed` takes an OPCODE SET, not a list of enum members: every caller
# holds a set of opcodes (`all_ops`, `base_allowed`, `sdst_ops`,
# `suffix_only_ops[sfx][base]`) and the NAME comes from the enum table by
# opcode, which is `op_named` below.

def fmt_allowed.names.go(os_: List<&2, U32>, +op_enum: String, +eos: List<&2, EO>,
                         acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case +o <> t:
      fmt_allowed.names.go(t, op_enum, eos, List.append(&2, String, acc,
        [op_enum ++ "." ++ op_named(remsuffix(op_enum, "Op"), o, eos)]))

# `next(n for op, n in enums[base].items() if op == target)` -- the REVERSE
# search.  A miss answers the empty string, and `fmt_allowed` then emits
# `VOP1Op.` with nothing after the dot: visible, not silent.

def fmt_allowed.names(os_: List<&2, U32>, op_enum: String, eos: List<&2, EO>) -> List<&2, String>:
  fmt_allowed.names.go(os_, op_enum, eos, Nil{})

# `op_enum.removesuffix("Op")` -- every `fmt_allowed` caller passes `<fmt>Op`.

def u32_le(a: U32, b: U32) -> Bool: U32.is_lt(a, b)

def sort_u32s(xs: List<&2, U32>) -> List<&2, U32>: List.sort(U32, u32_le, xs)

def fmt_allowed(op_enum: String, os_: List<&2, U32>, eos: List<&2, EO>) -> String:
  "{" ++ String.join(fmt_allowed.names(sort_u32s(os_), op_enum, eos), ", ") ++ "}"

def enum_names.take.op(+e: EO, +acc: List<&2, String>, is_plain: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, is_plain, acc, List.append(&2, String, acc, [EO.fmt(e) ++ "Op"]))

# `enum_names = sorted(f"{k}Op" for k in enums if enums[k] and k not in ("HWREG","MSG"))`
# then `enum_names += sorted(k for k in enums if k in ("HWREG","MSG") and enums[k])`.
# TWO WALKS, TWO SORTS AND A CONCATENATION -- not one sort of the union: the
# plain enums are emitted last and WITHOUT the `Op` suffix, which is why the
# import line ends `..., VSCRATCHOp, HWREG, MSG` rather than sorting `HWREG`
# between `GLOBALOp` and `HWREGOp`.  A single sorted union is a DIFFERENT FILE.

def base_field.op(+f: Fld, +oe: String, allowed: List<&2, U32>, eos: List<&2, EO>) -> String:
  "op = EnumBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++ U32.show(Fld.lo(f)) ++ ", " ++ oe ++ ", " ++
    fmt_allowed(oe, allowed, eos) ++ ")"

def FV.seg(f: FV) -> U32:
  match f:
    case FV{cls, +seg, oe}: seg

def order() -> List<&2, String>:
  ["encoding", "op", "opx", "opy", "vdst", "vdstx", "vdsty", "sdst", "vdata", "sdata", "addr",
   "vaddr", "data", "data0", "data1", "src0", "srcx0", "srcy0", "vsrc0", "ssrc0", "src1", "vsrc1",
   "vsrcx1", "vsrcy1", "ssrc1", "src2", "vsrc2", "src3", "vsrc3", "saddr", "sbase", "srsrc",
   "ssamp", "soffset", "offset", "simm16", "literal", "en", "target", "attr", "attr_chan", "omod",
   "neg", "neg_hi", "abs", "clmp", "opsel", "opsel_hi", "waitexp", "wait_va", "dmask", "dim", "seg",
   "format", "offen", "idxen", "glc", "dlc", "slc", "tfe", "unrm", "done", "row", "dpp", "fi", "bc",
   "row_mask", "bank_mask", "src0_neg", "src0_abs", "src1_neg", "src1_abs", "cbsz", "abid",
   "acc_cd", "acc", "blgp", "lane_sel_0", "lane_sel_1", "lane_sel_2", "lane_sel_3", "lane_sel_4",
   "lane_sel_5", "lane_sel_6", "lane_sel_7", "dst_sel", "dst_unused", "src0_sel", "src1_sel"]

def order.hit(o: List<&2, String>, nm: String) -> Bool: str_in(nm, o)

# 999 is not a sentinel the port invented: it is the literal in generate.py:327,
# and it is what puts a field this file has never heard of LAST.

# `ORDER.index(nm)` -- the index of the first entry equal to `nm`.  ONE def, not
# a `cmp` helper that calls back: two defs that call each other have no order in
# bend.  `Bool.pick` CHOOSES and bend evaluates both arms, which is free here
# because the walk is a pure recursion over a strictly shrinking list.

def order_at(o: List<&2, String>, +nm: String, +i: U32) -> U32:
  match o:
    case Nil{}: 0
    case +h <> +t: Bool.pick(U32, String.eq(h, nm), i, order_at(t, nm, U32.add(i, 1)))

# 999 is not a sentinel the port invented: it is the literal in generate.py:327,
# and it is what puts a field this file has never heard of LAST.

def order_idx(+o: List<&2, String>, +nm: String) -> U32:
  Bool.pick(U32, order.hit(o, nm), order_at(o, nm, 0), 999)

def Fld.nm(f: Fld) -> String:
  match f:
    case Fld{+nm, +hi, +lo}: nm

def Fld.of(nm: String, hi: U32, lo: U32) -> Fld: Fld{nm, hi, lo}

# `sorted(fields, key=lambda f: (ORDER.index(...) else 999, f[2]))` -- a
# TWO-KEY sort.  `List.sort` takes one `le`, so the pair is compared field by
# field here rather than by a tuple, which bend has no spelling for.  This is
# also the ONE comparator in the file whose parameters must stay BORROWED: a
# record read CONSUMES, `List.sort` hands `le` borrowed elements, so each
# element is destructured exactly once and the two keys are carried out as
# arguments instead of being re-read.

def fld_le.k2(same: Bool, ka: U32, kb: U32, la: U32, lb: U32) -> Bool:
  match same:
    case True{}: U32.is_le(la, lb)
    case False{}: U32.is_lt(ka, kb)

def fld_le.c(la: U32, +ka: U32, lb: U32, +kb: U32) -> Bool:
  fld_le.k2(U32.is_eq(ka, kb), ka, kb, la, lb)

def fld_le.b(b: Fld, la: U32, ka: U32) -> Bool:
  match b:
    case Fld{+nm, +hi, +lo}: fld_le.c(la, ka, lo, order_idx(order(), nm))

def fld_le.a(a: Fld, b: Fld) -> Bool:
  match a:
    case Fld{+nm, +hi, +lo}: fld_le.b(b, lo, order_idx(order(), nm))

def fld_le(a: Fld, b: Fld) -> Bool: fld_le.a(a, b)

def sort_fields(fs: List<&2, Fld>) -> List<&2, Fld>: List.sort(Fld, fld_le, fs)
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

# `R{pk, pa, pb, pc, kind}` -- `pb` IS THE WIDTH, and `0` means "any width"
# (`r_ok` tests `U32.is_zero(pb) || pb == width`).  EIGHT of the seventeen arms
# are width-guarded, and the inherited table held `pb = 1` in every one of them,
# which tests `width == 1`: so `field_def("vdst", 16, 9, "VOP1")` answered
# `BitField(16, 9)` where CPython answers `VGPRField(16, 9)`, and SIXTEEN of the
# seventeen field rows would have agreed for the wrong reason.  The inherited
# report said all seventeen arms were gated; they were not, because no gate row
# reached `field_def` at all.
#
# `pk = 2` is `nm in pa.split()` upstream.  bend has no `String.split` on a
# space, so that one arm keeps its word list as `vgpr_fields()` and `pa` is
# unused for it -- stated here rather than hidden, because a reader comparing
# this table to generate.py:296 will look for the words.

def field_rules() -> List<&2, R>:
  [R{0, "op", 0, 1, K2_ENOP()}, R{0, "opx", 0, 0, K2_ENOPD()}, R{0, "opy", 0, 0, K2_ENOPD()},
   R{0, "vdsty", 0, 0, K2_VDSTY()}, R{2, "", 8, 0, K2_VGPR()},
   R{0, "sbase", 6, 0, K2_SBASE()}, R{0, "srsrc", 5, 0, K2_SRSC()}, R{0, "ssamp", 5, 0, K2_SRSC()},
   R{0, "sdst", 7, 0, K2_SGPR()}, R{0, "sdata", 7, 0, K2_SGPR()},
   R{0, "soffset", 7, 0, K2_SGPRN()}, R{0, "saddr", 7, 0, K2_SGPRN()},
   R{1, "ssrc", 8, 0, K2_SSRC()}, R{0, "saddr", 8, 0, K2_SSRCN()}, R{0, "soffset", 8, 0, K2_SSRCN()},
   R{1, "src", 9, 0, K2_SRC9()},
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

def arg3_raw(kind: U32) -> String: str_at(arg3_names(), U32.to_nat(kind))

# `f"{ctor}({hi}, {lo}{sep}{arg3})"` -- and an empty `arg3` must NOT leave a
# trailing comma, which is the `String.concat`-drops-a-literal class of bug in
# its most literal form.

def arg3(+kind: U32, base_fmt: String) -> String:
  Bool.pick(String, String.eq(arg3_raw(kind), "%Op"), base_fmt ++ "Op", arg3_raw(kind))

# `f"{ctor}({hi}, {lo}{sep}{arg3})"` -- and an empty `arg3` must NOT leave a
# trailing comma, which is the `String.concat`-drops-a-literal class of bug in
# its most literal form.

# THE ONLY PLACE `hi` IS NOT `hi`.  The inherited file defined this and never
# called it, so the `BitField(12, {lo})` arm of generate.py:317 was DEAD in the
# port and every GLOBAL/SCRATCH `offset` came out as `BitField(14, 0)`.

def field_def.hi(kind: U32, +hi: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind, K2_OFF13()), 12, hi)

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

def ctor_text(+kind: U32, +hi: U32, +lo: U32, +base_fmt: String) -> String:
  Bool.pick(String, String.is_empty(arg3(kind, base_fmt)),
    ctor(kind) ++ "(" ++ U32.show(field_def.hi(kind, hi)) ++ ", " ++ U32.show(lo) ++ ")",
    ctor(kind) ++ "(" ++ U32.show(field_def.hi(kind, hi)) ++ ", " ++ U32.show(lo) ++ ", " ++
      arg3(kind, base_fmt) ++ ")")

# `BitField(12, {lo})` -- the offset field of GLOBAL/SCRATCH is a SIGNED 13-bit
# field [12:0] whatever the XML says, and the XML says 12 bits for all three.

def pad_n(+n: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(0n, n), n, 0n)

# `0b{fixed_bits}{opcode:0{bits-len(fixed_bits)}b}` -- `String.repeat` with a
# NEGATIVE count is the failure, so the padding width is clamped and the clamp
# is a named def rather than a hidden `max`.

def ty_le.pair(nm_lt: Bool, nm_eq: Bool, ba: String, bb: String) -> Bool:
  Bool.pick(Bool, nm_lt, True{}, Bool.pick(Bool, nm_eq, String.is_lt(ba, bb), False{}))

# `sorted(types.items())` -- the key is the (name, enc_base) TUPLE, so the name
# is compared first and `base` only breaks a tie.  BORROWED, like `fld_le`:
# `List.sort` hands `le` borrowed elements.

def ty_le.b(t: TY, +a_name: String, +a_base: String) -> Bool:
  match t:
    case TY{+name, +base, flds}: ty_le.pair(String.is_lt(a_name, name), String.eq(a_name, name), a_base, base)

# `{opcode:0{bits-len(fixed_bits)}b}` -- the opcode in BINARY, left-padded with
# zeros to `width - len(fixed_bits)`, and NOT TRUNCATED: Python's format spec
# widens, it does not narrow, so 44 with a width of 5 is `101100`, six digits,
# and the emitted literal is seven digits wide.  bend 2.0.34 has no binary
# formatter on `U32` (`to_binary`, `show_bin`, `bits` and `bin` are all absent),
# so this halves with the digits PREPENDED, which turns least-significant first
# into most-significant first.
#
# THE `Nat` COUNTDOWN IS THE ONLY DECREASING ARGUMENT BEND ACCEPTS HERE.
# `U32.div(x, 2)` is not a STRUCTURAL subterm of `x` and the
# decreasing-self-call rule is structural, so a `U32`-only recursion is refused
# outright.  `U32.log2` supplies the digit count, which is exactly Python's `b`
# format width for a value asked for with no padding.

def ubin.of(x: U32) -> Nat: U32.log2(x)

def ubin.n(+x: U32) -> Nat:
  Bool.pick(Nat, U32.is_zero(x), 1n, Nat.add(ubin.of(x), 1n))

def ubin.go(n: Nat, +x: U32, +acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: ubin.go(p, U32.div(x, 2), String.concat([U32.show(U32.mod(x, 2)), acc]))

def ubin(+x: U32) -> String: ubin.go(ubin.n(x), x, "")

def ubin_pad.go(n: Nat, +s: String, +acc: String) -> String:
  match n:
    case 0n: s
    case 1n+p: ubin_pad.go(p, s, String.concat(["0", acc]))

def ubin_pad(s: String, w: U32) -> String: ubin_pad.go(U32.to_nat(w), s, "")

# `f"{x:02x}"` -- Python's `repr` escapes a non-printable code point as `\xNN`
# in LOWERCASE hex, and `write_pcode` is the only place in this file that has to
# produce one.  `ubin` above is the same shape for base 2.

def Fd2.e(x: Fd2) -> String:
  match x:
    case Fd2{+fmt, k, +e, onm, is_pair}: e

def hex_digits() -> List<&2, String>:
  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

def hex2(+h: U32) -> String:
  String.concat([str_at(hex_digits(), U32.to_nat(U32.div(h, 16))),
                 str_at(hex_digits(), U32.to_nat(U32.mod(h, 16)))])

def field_def.emb(hi: U32, lo: U32, +fixed_bits: String, opcode: U32, width: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ fixed_bits ++
  ubin_pad(ubin(opcode), U32.sub(width, slen(fixed_bits))) ++ ")"

def Fd2.fmt(x: Fd2) -> String:
  match x:
    case Fd2{+fmt, k, +e, onm, is_pair}: fmt

def Fd2.k(x: Fd2) -> String:
  match x:
    case Fd2{+fmt, k, +e, onm, is_pair}: k


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

# THE FIVE SEARCHES SHARE ONE SHAPE, and it is the shape bend forces: a walk
# that RETURNS a `Maybe` cannot be `find` -> `hit` -> `find`, because two defs
# that call each other have no order.  So the accumulator IS the recursion
# parameter, `kv` is the per-element answer (never recursive), and `go` is the
# only self-call.  `go` stops as soon as `acc` is `Some`, which is what
# `next(...)`/`dict.get` do.

def field_def.fd_kv(+k: Fd2, +fmt: String, +nm: String) -> Maybe<&2, Fd2>:
  Bool.pick(Maybe<&2, Fd2>, Bool.and(String.eq(Fd2.fmt(k), fmt), String.eq(Fd2.k(k), nm)),
    Some{k}, None{})

# THE FIVE `Maybe`-RETURNING SEARCHES SHARE ONE SHAPE, and it is the shape bend
# forces.  A search cannot be `find` -> `hit` -> `find`, because two defs that
# call each other have no order; and it cannot match a second list inside a
# match arm, because a `match` on a parameter NESTED in a match arm is refused.
# So: `kv` is the per-element answer and is never recursive, `take` is
# first-hit-wins, and `go` is the only self-call.  `go` returns `acc` at the end
# of the list, so it is exactly `next(...)` / `dict.get`.

def field_def.fd_take(acc: Maybe<&2, Fd2>, hit: Maybe<&2, Fd2>) -> Maybe<&2, Fd2>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def field_def.fd_go(t: List<&2, Fd2>, +fmt: String, +nm: String, acc: Maybe<&2, Fd2>) -> Maybe<&2, Fd2>:
  match t:
    case Nil{}: acc
    case +k <> r: field_def.fd_go(r, fmt, nm, field_def.fd_take(acc, field_def.fd_kv(k, fmt, nm)))

def field_def.fd_find(kvs: List<&2, Fd2>, fmt: String, nm: String) -> Maybe<&2, Fd2>:
  field_def.fd_go(kvs, fmt, nm, None{})

def Fd2.is_pair(x: Fd2) -> Bool:
  match x:
    case Fd2{+fmt, k, +e, onm, is_pair}: is_pair

def Fd2.onm(x: Fd2) -> String:
  match x:
    case Fd2{fmt, k, e, onm, is_pair}: onm

def field_def.fix_int(g: Fd2, hi: U32, lo: U32) -> String:
  "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", " ++ Fd2.e(g) ++ ")"

# `next(op for op, n in enums[fixed[0]].items() if n == fixed[1])` -- a SEARCH
# by NAME over one format's opcode table.  There is no `Maybe`-free spelling of
# a search, so `ec_op_of` answers 0 on a miss and `fd.emb` row for
# `x2encoding` is the row that would see it.

def EC.bits(e: EC) -> String:
  match e:
    case EC{name, fields, bits, has_bits}: bits

def EC.miss() -> EC: EC{"", Nil{}, "", False{}}

def EC.name(e: EC) -> String:
  match e:
    case EC{name, fields, bits, has_bits}: name

def ec_find.kv(+e: EC, +nm: String) -> Maybe<&2, EC>:
  Bool.pick(Maybe<&2, EC>, String.eq(EC.name(e), nm), Some{e}, None{})

def ec_find.take(acc: Maybe<&2, EC>, hit: Maybe<&2, EC>) -> Maybe<&2, EC>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def ec_find.go(encs: List<&2, EC>, +nm: String, acc: Maybe<&2, EC>) -> Maybe<&2, EC>:
  match encs:
    case Nil{}: acc
    case +e <> r: ec_find.go(r, nm, ec_find.take(acc, ec_find.kv(e, nm)))

def ec_find(nm: String, encs: List<&2, EC>) -> Maybe<&2, EC>:
  ec_find.go(encs, nm, None{})

# ---- Fd2, the FIXED_FIELDS sum ------------------------------------------

def ec_get.of(m: Maybe<&2, EC>, miss: EC) -> EC:
  match m:
    case None{}: miss
    case Some{+g}: g

def ec_get(nm: String, encs: List<&2, EC>) -> EC:
  ec_get.of(ec_find(nm, encs), EC.miss())

def ec_op_of.of(m: Maybe<&2, U32>, miss: U32) -> U32:
  match m:
    case None{}: miss
    case Some{+g}: g

def op_find.kv(+o: OP, +nm: String) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, String.eq(OP.nm(o), nm), Some{OP.op(o)}, None{})

def op_find.take(acc: Maybe<&2, U32>, hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def op_find.go(os_: List<&2, OP>, +nm: String, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match os_:
    case Nil{}: acc
    case o <> r: op_find.go(r, nm, op_find.take(acc, op_find.kv(o, nm)))

def op_find(os_: List<&2, OP>, nm: String) -> Maybe<&2, U32>:
  op_find.go(os_, nm, None{})

def ec_op_of(eos: List<&2, EO>, fmt: String, nm: String) -> U32:
  ec_op_of.of(op_find(ops_of(fmt, eos), nm), 0)

# `next(op for op, n in enums[fixed[0]].items() if n == fixed[1])` -- a SEARCH
# by NAME over one format's opcode table.  There is no `Maybe`-free spelling of
# a search, so `ec_op_of` answers 0 on a miss and `fd.emb` row for
# `x2encoding` is the row that would see it.

def field_def.fix_pair(+g: Fd2, +hi: U32, +lo: U32, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.emb(hi, lo, EC.bits(ec_get(Fd2.e(g), encs)), ec_op_of(enums, Fd2.e(g), Fd2.onm(g)),
    U32.sub(U32.add(hi, 1), lo))

# pc: 0 any | 1 fmt not in (DPP,SDWA) | 2 base_fmt in (GLOBAL,SCRATCH).  The
# `DPP`/`SDWA` exemption is the ONE place `field_def` refuses to call an enum
# for a format whose `op` field is not an opcode, and it is a NOT IN test, so
# a fourth format would have to be added to BOTH this def and the comment.

def fmt_exempt(+fmt: String) -> Bool: Bool.or(String.eq(fmt, "DPP"), String.eq(fmt, "SDWA"))

def fmt_exempt_b(+pc: U32, fmt: String, +base_fmt: String) -> Bool:
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

def r_ok.pc(pk_ok: Bool, pb_ok: Bool, pc_ok: Bool) -> Bool: Bool.and(pk_ok, Bool.and(pb_ok, pc_ok))

def vgpr_hit(+nm: String, ws: List<&2, String>) -> Bool:
  match ws:
    case Nil{}: False{}
    case +h <> +t: Bool.or(String.eq(h, nm), vgpr_hit(nm, t))

# pc: 0 any | 1 fmt not in (DPP,SDWA) | 2 base_fmt in (GLOBAL,SCRATCH).  The
# `DPP`/`SDWA` exemption is the ONE place `field_def` refuses to call an enum
# for a format whose `op` field is not an opcode, and it is a NOT IN test, so
# a fourth format would have to be added to BOTH this def and the comment.

def R.pk(r: R) -> U32:
  match r:
    case R{pk, pa, pb, +pc, kind}: pk

def R.pa(r: R) -> String:
  match r:
    case R{pk, pa, pb, +pc, kind}: pa

def R.pb(r: R) -> U32:
  match r:
    case R{pk, pa, pb, +pc, kind}: pb

def R.pc(r: R) -> U32:
  match r:
    case R{pk, pa, pb, +pc, kind}: pc

def R.kind(r: R) -> U32:
  match r:
    case R{pk, pa, pb, +pc, kind}: kind

def r_pk(pk: U32, pa: String, +nm: String) -> Bool:
  match pk:
    case 0: String.eq(nm, pa)
    case 1: String.starts_with(nm, pa)
    case _: vgpr_hit(nm, vgpr_fields())

def r_ok(+r: R, +nm: String, width: U32, +base_fmt: String, +fmt: String) -> Bool:
  r_ok.pc(r_pk(R.pk(r), R.pa(r), nm), Bool.or(U32.is_zero(R.pb(r)), U32.is_eq(R.pb(r), width)),
          fmt_exempt_b(R.pc(r), fmt, base_fmt))

# FIRST RULE THAT MATCHES WINS.  One def, not `go` -> `step` -> `step.of` ->
# `go`: that is mutual recursion, which bend refuses.  `Bool.pick` CHOOSES and
# bend evaluates both arms, which is free because both are pure and `rest` is
# strictly shorter -- so the ladder is one self-call per rule examined.

def field_kind.go(rs: List<&2, R>, +nm: String, +width: U32, +base_fmt: String, +fmt: String,
                  cur: U32) -> U32:
  match rs:
    case Nil{}: cur
    case +r <> rest: Bool.pick(U32, r_ok(r, nm, width, base_fmt, fmt), R.kind(r),
      field_kind.go(rest, nm, width, base_fmt, fmt, cur))

def field_kind(nm: String, hi: U32, lo: U32, +fmt: String) -> U32:
  field_kind.go(field_rules(), nm, U32.sub(U32.add(hi, 1), lo), get_base_fmt(fmt), fmt, K2_BIT())

def field_def.fix_kind(nm: String, +hi: U32, +lo: U32, +fmt: String, encs: List<&2, EC>,
                       enums: List<&2, EO>) -> String:
  ctor_text(field_kind(nm, hi, lo, fmt), hi, lo, fmt)

def field_def.kind(nm: String, hi: U32, lo: U32, fmt: String, encs: List<&2, EC>,
                   enums: List<&2, EO>) -> String:
  field_def.fix_kind(nm, hi, lo, fmt, encs, enums)

# ---- THE LADDER ITSELF: `sorted`-independent FIRST MATCH over the table ----

def field_def.fix_pair.of(g: Fd2, hi: U32, lo: U32, +encs: List<&2, EC>, +enums: List<&2, EO>,
                           is_pair: Bool) -> String:
  match is_pair:
    case True{}: field_def.fix_pair(g, hi, lo, encs, enums)
    case False{}: field_def.fix_int(g, hi, lo)

# FIXED_FIELDS is keyed by (arch, encoding, field).  The arch is a TABLE
# CONSTANT here -- the only entry is cdna's -- so it is not a third lookup
# level; conflating FIXED_FIELDS with FIELD_FIXES would be, and FIELD_FIXES is
# a field-LIST append done by `__main__`, not a lookup.  Two different tables.

def field_def.fix_of(m: Maybe<&2, Fd2>, +nm: String, hi: U32, lo: U32, +fmt: String,
                     +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  match m:
    case None{}: field_def.kind(nm, hi, lo, fmt, encs, enums)
    case Some{+g}: field_def.fix_pair.of(g, hi, lo, encs, enums, Fd2.is_pair(g))

def field_def.fix(+nm: String, hi: U32, lo: U32, +fmt: String, +fixed: List<&2, Fd2>,
                  +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  field_def.fix_of(field_def.fd_find(fixed, fmt, nm), nm, hi, lo, fmt, encs, enums)

def field_def.k0(is_enc: Bool, has_bits: Bool) -> Bool: Bool.and(is_enc, has_bits)

# FIXED_FIELDS is keyed by (arch, encoding, field).  The arch is a TABLE
# CONSTANT here -- the only entry is cdna's -- so it is not a third lookup
# level; conflating FIXED_FIELDS with FIELD_FIXES would be, and FIELD_FIXES is
# a field-LIST append done by `__main__`, not a lookup.  Two different tables.

def field_def.enc.of(k0: Bool, +nm: String, hi: U32, lo: U32, +bits: String, +fmt: String,
                     +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  match k0:
    case True{}: "FixedBitField(" ++ U32.show(hi) ++ ", " ++ U32.show(lo) ++ ", 0b" ++ bits ++ ")"
    case False{}: field_def.fix(nm, hi, lo, fmt, fixed, encs, enums)

def field_def.enc(+nm: String, hi: U32, lo: U32, +fmt: String, +bits: String, has_bits: Bool,
                  +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +enums: List<&2, EO>) -> String:
  field_def.enc.of(field_def.k0(String.eq(nm, "encoding"), has_bits), nm, hi, lo, bits, fmt, fixed, encs, enums)

def field_def(nm: String, hi: U32, lo: U32, fmt: String, bits: String, has_bits: Bool,
              fixed: List<&2, Fd2>, encs: List<&2, EC>, enums: List<&2, EO>) -> String:
  field_def.enc(nm, hi, lo, fmt, bits, has_bits, fixed, encs, enums)

def EO.of(f: String, os_: List<&2, OP>) -> EO: EO{f, os_}

def EC.fields(e: EC) -> List<&2, Fld>:
  match e:
    case EC{name, fields, bits, has_bits}: fields

def EC.has_bits(e: EC) -> Bool:
  match e:
    case EC{name, fields, bits, has_bits}: has_bits

def EC.of(nm: String, fs: List<&2, Fld>, bits: String, hb: Bool) -> EC: EC{nm, fs, bits, hb}

def ec_le(a: EC, b: EC) -> Bool: String.is_lt(EC.name(a), EC.name(b))

def sort_encs(es: List<&2, EC>) -> List<&2, EC>: List.sort(EC, ec_le, es)

def eo_le(a: EO, b: EO) -> Bool: String.is_lt(EO.fmt(a), EO.fmt(b))

def sort_eos(es: List<&2, EO>) -> List<&2, EO>: List.sort(EO, eo_le, es)

def enum_suffix.e32_b(+fmt: String) -> Bool:
  Bool.or(String.eq(fmt, "VOP1"), Bool.or(String.eq(fmt, "VOP2"), String.eq(fmt, "VOPC")))

def enum_suffix.e32(fmt: String) -> String:
  Bool.pick(String, enum_suffix.e32_b(fmt), "_E32", "")

def enum_suffix.e64(fmt: String) -> String: Bool.pick(String, String.eq(fmt, "VOP3"), "_E64", "")

# `suffix = "_E32" if name in ("VOP1","VOP2","VOPC") else "_E64" if name == "VOP3" else ""`

def enum_suffix(+fmt: String) -> String:
  enum_suffix.e32(fmt) ++ enum_suffix.e64(fmt)

def op_msuf.of(is_vop3: Bool, op: U32, suffix: String) -> String:
  Bool.pick(String, Bool.and(is_vop3, U32.is_le(512, op)), "", suffix)

# `msuf = suffix if name != "VOP3" or op < 512 else ""` -- THE ONE place a VOP3
# opcode at 512 or above loses its `_E64`, and it is a `<` on the OPCODE, not on
# the enum name.  `write_ins`'s helper block asks for the same rule on the same
# operand, so both emitters share THIS one function rather than a second copy.

def op_msuf(+fmt: String, op: U32) -> String:
  op_msuf.of(String.eq(fmt, "VOP3"), op, enum_suffix(fmt))

def enum_plain_b(+fmt: String) -> Bool:
  Bool.or(String.eq(fmt, "HWREG"), String.eq(fmt, "MSG"))

def class_name(+fmt: String) -> String:
  Bool.pick(String, enum_plain_b(fmt), fmt, fmt ++ "Op")

def enum_members.go(os_: List<&2, OP>, +fmt: String, acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case +o <> t:
      enum_members.go(t, fmt, List.append(&2, String, acc,
        ["  " ++ OP.nm(o) ++ op_msuf(fmt, OP.op(o)) ++ " = " ++ U32.show(OP.op(o))]))

def write_enum.aliases.go(os_: List<&2, OP>, +fmt: String, +acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case +o <> t:
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

# THE ALIAS PASS IS SECOND AND SEPARATE: `aliases` collects (mem, msuf) for
# every op that GOT a suffix and is emitted after all the value cells, so
# `V_CNPY = V_CNPY_E32` follows `V_CNPY_E32 = 0`.  Folding the two passes into
# one list puts the aliases before the values, which is legal Python and a
# different file.

def write_enum.aliases(fmt: String, os_: List<&2, OP>) -> List<&2, String>:
  write_enum.aliases.go(os_, fmt, Nil{})

# THE ALIAS PASS IS SECOND AND SEPARATE: `aliases` collects (mem, msuf) for
# every op that GOT a suffix and is emitted after all the value cells, so
# `V_CNPY = V_CNPY_E32` follows `V_CNPY_E32 = 0`.  Folding the two passes into
# one list puts the aliases before the values, which is legal Python and a
# different file.

# ONE CLASS = HEADER, VALUE CELLS, ALIAS CELLS, BLANK, in that order.  The
# value walk (`enum_members.go`) and the alias walk (`write_enum.aliases.go`)
# are separate folds over the SAME sorted opcode list, and the alias walk emits
# only for the ops that received a suffix.

def write_enum.one(+fmt: String, +os_: List<&2, OP>, acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String,
    List.append(&2, String, ["class " ++ class_name(fmt) ++ "(ReprEnum):"],
      enum_members.go(os_, fmt, Nil{})),
    List.append(&2, String, write_enum.aliases(fmt, os_), [""])))

# `if not ops: continue` -- AN ENUM WITH NO OPCODES EMITS NOTHING AT ALL, not
# even a class line and not even the blank separator.  A fixture with one such
# format is what makes that a gated row rather than a reading of the source.

def write_enum.go(eos: List<&2, EO>, +acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case +e <> +t: write_enum.go(t, Bool.pick(List<&2, String>, List.is_empty(&2, OP, EO.ops(e)), acc,
      write_enum.one(EO.fmt(e), sort_ops(EO.ops(e)), acc)))

# `f"class {name}(ReprEnum):" if name in ("HWREG","MSG") else f"class {name}Op(ReprEnum):"`

def write_enum(eos: List<&2, EO>) -> List<&2, String>:
  write_enum.go(sort_eos(eos), [
    "# autogenerated from AMD ISA XML - do not edit",
    "from tinygrad.runtime.autogen.amd.common import ReprEnum, Fmt, FMT_BITS, OpType  # noqa: F401", ""])

def FB.nm(f: FB) -> String:
  match f:
    case FB{+nm, bits}: nm

def FB.bits(f: FB) -> U32:
  match f:
    case FB{+nm, bits}: bits

def fb_le(a: FB, b: FB) -> Bool: String.is_lt(FB.nm(a), FB.nm(b))

def sort_fbs(fs: List<&2, FB>) -> List<&2, FB>: List.sort(FB, fb_le, fs)

def str_le(a: String, b: String) -> Bool: String.is_lt(a, b)

def sort_strs(xs: List<&2, String>) -> List<&2, String>: List.sort(String, str_le, xs)

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

def write_common.head() -> List<&2, String>:
  ["# autogenerated from AMD ISA XML - do not edit", "from enum import Enum, auto", "",
   "class ReprEnum(Enum):", "  \"\"\"Enum with clean repr that roundtrips with eval().\"\"\"",
   "  def __repr__(self): return f\"{type(self).__name__}.{self.name}\"", "", "class Fmt(Enum):"]

def write_common.fmt_bits.go(fbs: List<&2, FB>, acc: List<&2, String>) -> List<&2, String>:
  match fbs:
    case Nil{}: acc
    case +f <> +t:
      write_common.fmt_bits.go(t, List.append(&2, String, acc,
        ["  Fmt." ++ FB.nm(f) ++ ": " ++ U32.show(FB.bits(f)) ++ ","]))

def write_common.fmt_bits(fbs: List<&2, FB>) -> List<&2, String>:
  write_common.fmt_bits.go(fbs, Nil{})

def write_common.fmt_names.go(fbs: List<&2, FB>, acc: List<&2, String>) -> List<&2, String>:
  match fbs:
    case Nil{}: acc
    case +f <> +t: write_common.fmt_names.go(t, List.append(&2, String, acc, ["  " ++ FB.nm(f) ++ " = auto()"]))

def write_common.fmt_names(fbs: List<&2, FB>) -> List<&2, String>:
  write_common.fmt_names.go(fbs, Nil{})

def write_common.ot_names.go(ots: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match ots:
    case Nil{}: acc
    case +o <> +t: write_common.ot_names.go(t, List.append(&2, String, acc, ["  " ++ o ++ " = auto()"]))

def write_common.ot_names(ots: List<&2, String>) -> List<&2, String>:
  write_common.ot_names.go(ots, Nil{})

def write_common.tail(+fbs: List<&2, FB>, ots: List<&2, String>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String,
      List.append(&2, String, write_common.fmt_names(fbs), ["", "FMT_BITS = {"]),
      write_common.fmt_bits(fbs)),
    List.append(&2, String, ["}", "", "class OpType(Enum):"], write_common.ot_names(ots)))

def write_common(fbs: List<&2, FB>, ots: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, write_common.head(), write_common.tail(sort_fbs(fbs), sort_strs(ots)))

def OI.nm(o: OI) -> String:
  match o:
    case OI{+nm, +fmt, size, otype}: nm

def OI.fmt(o: OI) -> String:
  match o:
    case OI{+nm, +fmt, size, otype}: fmt

def OI.size(o: OI) -> U32:
  match o:
    case OI{+nm, +fmt, size, otype}: size

def OI.otype(o: OI) -> String:
  match o:
    case OI{+nm, +fmt, size, otype}: otype

def TY.name(t: TY) -> String:
  match t:
    case TY{name, +base, flds}: name

def TY.base(t: TY) -> String:
  match t:
    case TY{name, +base, flds}: base

def TY.flds(t: TY) -> List<&2, OI>:
  match t:
    case TY{name, +base, flds}: flds

def fmt_val.fmt(+f: String) -> String: Bool.pick(String, String.is_empty(f), "None", "Fmt." ++ f)

def fmt_val.otype(+t: String) -> String: Bool.pick(String, String.is_empty(t), "None", "OpType." ++ t)

def fmt_val(+v: OI) -> String:
  "(" ++ fmt_val.fmt(OI.fmt(v)) ++ ", " ++ U32.show(OI.size(v)) ++ ", " ++ fmt_val.otype(OI.otype(v)) ++ ")"

def oi_le(a: OI, b: OI) -> Bool: String.is_lt(OI.nm(a), OI.nm(b))

def sort_ois(xs: List<&2, OI>) -> List<&2, OI>: List.sort(OI, oi_le, xs)

def dq() -> String: "\""

def fmt_val.cells(+v: OI) -> String:
  String.concat([dq, OI.nm(v), dq, ": ", fmt_val(v)])

def ty_le(a: TY, b: TY) -> Bool:
  match a:
    case TY{name, +base, flds}: ty_le.b(b, name, base)

# ===========================================================================
# `FIXED_FIELDS.get(arch, {})` -- the table has ONE arch in it (cdna), so handing
# rdna3 the same `fixed_fields()` emits a `FixedBitField` where CPython emits a
# `BitField`.  The ARCH is the lookup key and dropping it is a silent answer.

def fixed_of(+arch: String) -> List<&2, Fd2>:
  Bool.pick(List<&2, Fd2>, String.eq(arch, "cdna"), fixed_fields(), Nil{})

# ---- THE FIXTURE.  Built by `.agents/slop/ga_fix.py` from the SAME dicts
# `ga-oracle.py` hands to `generate.write_ins`, so the port's fixture and
# CPython's input cannot drift apart.

def sort_tys(tys: List<&2, TY>) -> List<&2, TY>: List.sort(TY, ty_le, tys)

def write_operands.cells.go(ois: List<&2, OI>, acc: List<&2, String>) -> List<&2, String>:
  match ois:
    case Nil{}: acc
    case +o <> +t: write_operands.cells.go(t, List.append(&2, String, acc, [fmt_val.cells(o)]))

def write_operands.cells(ois: List<&2, OI>) -> List<&2, String>:
  write_operands.cells.go(ois, Nil{})

def write_operands.tail2(head: List<&2, String>, rows: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, head, List.append(&2, String, rows, ["}"]))

def write_operands.tail(rows: List<&2, String>, head: List<&2, String>) -> List<&2, String>:
  write_operands.tail2(List.append(&2, String, head,
    ["# instruction operand info: {Op: {field: (Fmt, size_bits, OpType)}}", "OPERANDS = {"]),
    rows)

# THE CLOSING BRACE IS ITS OWN STEP, not a fourth nested `List.append`: four
# opens with three closes parses as "a term with no value" and bend reports it
# against the NEXT `def`, thirty lines away, with no mention of the paren.


# ---- THE FIXTURE.  Built by `.agents/slop/ga_fix.py` from the SAME dicts
# `ga-oracle.py` hands to `generate.write_ins`, so the port's fixture and
# CPython's input cannot drift apart.

def VF.name(v: VF) -> String:
  match v:
    case VF{name, +fmt}: name

def VF.fmt(v: VF) -> String:
  match v:
    case VF{name, +fmt}: fmt

def vf_one(+v: VF, +nm: String, +fmt: String) -> Bool:
  Bool.and(String.eq(VF.name(v), nm), String.eq(VF.fmt(v), fmt))

def vf_hit(vs: List<&2, VF>, +nm: String, +fmt: String) -> Bool:
  match vs:
    case Nil{}: False{}
    case +v <> +t: Bool.or(vf_one(v, nm, fmt), vf_hit(t, nm, fmt))

def valid_pairs.ops(os_: List<&2, OP>, +fmt: String, acc: List<&2, VF>) -> List<&2, VF>:
  match os_:
    case Nil{}: acc
    case +o <> +t: valid_pairs.ops(t, fmt, List.append(&2, VF, acc, [VF{OP.nm(o), fmt}]))

def valid_pairs.eos(eos: List<&2, EO>, acc: List<&2, VF>) -> List<&2, VF>:
  match eos:
    case Nil{}: acc
    case +e <> +t: valid_pairs.eos(t, List.append(&2, VF, acc, valid_pairs.ops(EO.ops(e), EO.fmt(e), Nil{})))

def valid_pairs(eos: List<&2, EO>) -> List<&2, VF>:
  valid_pairs.eos(eos, Nil{})

# `{eb for (nm, eb) in types if (nm, eb) in valid}` -- a SET, so the bases are
# deduplicated before the sort.  `dedup_adj` on the SORTED list is that set.

def used_bases.go(tys: List<&2, TY>, +vs: List<&2, VF>, +acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case +t <> rest: used_bases.go(rest, vs,
      Bool.pick(List<&2, String>, vf_hit(vs, TY.name(t), TY.base(t)),
        List.append(&2, String, acc, [TY.base(t)]), acc))

# THE RECURSION IS AN ARGUMENT, NOT AN ARM OF THE PICK.  `Bool.pick` CHOOSES
# between two already-computed values and never sequences one, so a self-call
# inside a pick arm means the walk stops at the first element whose accumulator
# is chosen -- `dedup_adj(["a","a","b","b","c"])` answered `["a"]`, and the
# import list came out as `DPPOp, FLATOp`.  Only the ACCUMULATOR is a pick.

def dedup_adj.step(+x: String, +last: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(x, last), acc, List.append(&2, String, acc, [x]))

def dedup_adj.go(xs: List<&2, String>, +last: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> +t: dedup_adj.go(t, x, dedup_adj.step(x, last, acc))

def dedup_adj(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case +x <> +t: dedup_adj.go(t, x, [x])

def used_bases(tys: List<&2, TY>, vs: List<&2, VF>) -> List<&2, String>:
  dedup_adj(sort_strs(used_bases.go(tys, vs, Nil{})))

def used_bases.names.go(bs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case +b <> +t: used_bases.names.go(t, List.append(&2, String, acc, [b ++ "Op"]))

def used_bases.ops(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, String>:
  used_bases.names.go(used_bases(tys, valid_pairs(eos)), Nil{})

def write_operands.enum_names(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, String>:
  sort_strs(used_bases.ops(tys, eos))

def write_operands.keep(+t: TY, vs: List<&2, VF>) -> Bool:
  vf_hit(vs, TY.name(t), TY.base(t))

def write_operands.rows.go(tys: List<&2, TY>, +vs: List<&2, VF>, +acc: List<&2, String>) -> List<&2, String>:
  match tys:
    case Nil{}: acc
    case +t <> rest: write_operands.rows.go(rest, vs,
      Bool.pick(List<&2, String>, write_operands.keep(t, vs),
        List.append(&2, String, acc,
          ["  " ++ TY.base(t) ++ "Op." ++ TY.name(t) ++ ": {" ++
           String.join(write_operands.cells(sort_ois(TY.flds(t))), ", ") ++ "},"]), acc))

def write_operands(+tys: List<&2, TY>, +eos: List<&2, EO>, +arch: String) -> List<&2, String>:
  write_operands.tail(
    write_operands.rows.go(sort_tys(tys), valid_pairs(eos), Nil{}), [
      "# autogenerated from AMD ISA XML - do not edit",
      "from tinygrad.runtime.autogen.amd.common import Fmt, OpType",
      "from tinygrad.runtime.autogen.amd." ++ arch ++ ".enum import " ++
        String.join(write_operands.enum_names(tys, eos), ", "), ""])

# ======================================================================
# FOLD 5 -- `write_pcode`, generate.py:484-499.  The only emitter whose product
# is DATA rather than a class tree, and the only one that has to spell a Python
# string LITERAL rather than concatenate one.
#
# `extract_pcode`, which produces this input, is NOT PORTED: bend 2.0.34 has
# `F32` and no `F64` (`bend base | grep -c F64` is 0), and `extract_pdf_text`
# accumulates PDF `Td` offsets into Python floats, so `round(y)`'s grouping and
# every `55 < x < 65` window would be decided on 32-bit values.  See WALL 5.
# ======================================================================

# `{code!r}` -- CPython's `repr` for a `str`: single-quoted unless the text
# contains `'` and not `"`, and `\\`, `\t`, `\n`, `\r`, `\'` plus a `\xNN` for
# every other code point `str.isprintable()` rejects.  A bend char literal
# cannot SPELL `'` (there is no escape for it inside `'...'`) nor `\`, so those
# two arrive as code points and the other three are literals.

def ctl(code: U32) -> Char: Char.from_u32(code)

def repr_body.quote(+s: String) -> String:
  Bool.pick(String, Bool.and(String.contains(s, "'"), Bool.not(String.contains(s, "\""))), "\"", "'")

def repr_body.raw(+c: Char) -> String:
  Bool.pick(String, Bool.or(U32.is_lt(Char.to_u32(c), 32), U32.is_eq(Char.to_u32(c), 127)),
    "\\x" ++ hex2(Char.to_u32(c)), Char.show(c))

def repr_body.ch(+c: Char) -> String:
  Bool.pick(String, Bool.or(Char.is_eq(c, ctl(92)), Char.is_eq(c, ctl(39))),
    Bool.pick(String, Char.is_eq(c, ctl(39)), "\\'", "\\\\"),
    Bool.pick(String, Char.is_eq(c, '\n'), "\\n",
      Bool.pick(String, Char.is_eq(c, '\r'), "\\r",
        Bool.pick(String, Char.is_eq(c, '\t'), "\\t", repr_body.raw(c)))))

# `str.isprintable()` is False for the C0 controls and for DEL; everything at or
# above U+00A0 is printable, and Latin-1 punctuation is, so the two thresholds
# are the whole test for every character a PDF text run can carry.

def repr_body.go(cs: List<&2, Char>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case +c <> +t: repr_body.go(t, List.append(&2, String, acc, [repr_body.ch(c)]))

def repr_str(+s: String) -> String:
  repr_body.quote(s) ++ String.concat(repr_body.go(String.to_list(s), Nil{})) ++ repr_body.quote(s)

def pcode_find.go(ps: List<&2, PK>, +nm: String, +op: U32) -> Maybe<&2, String>:
  match ps:
    case Nil{}: None{}
    case +p <> +t:
      Bool.pick(Maybe<&2, String>, Bool.and(String.eq(PK.nm(p), nm), U32.is_eq(PK.op(p), op)),
        Some{PK.code(p)}, pcode_find.go(t, nm, op))

def pcode_find(ps: List<&2, PK>, nm: String, op: U32) -> Maybe<&2, String>: pcode_find.go(ps, nm, op)

# `entries.append((f"{fmt_name}Op", f"{name}{msuf}", opcode, pcode[(name, opcode)]))` --
# the SAME `member_suffix if fmt != "VOP3" or opcode < 512` rule the enum
# emitter and the helper block already share.  A `PK` whose code is the EMPTY
# string is a miss, which is exactly Python's `"x" in d` for this fixture, so the
# lookup is a one-field test rather than a `Maybe` round trip.

def pcode_entry.go(os_: List<&2, OP>, +fmt: String, +ps: List<&2, PK>, +acc: List<&2, PE>) -> List<&2, PE>:
  match os_:
    case Nil{}: acc
    case +o <> +t: pcode_entry.go(t, fmt, ps,
      Bool.pick(List<&2, PE>, String.is_empty(maybe_str(pcode_find(ps, OP.nm(o), OP.op(o)), "")),
        acc,
        List.append(&2, PE, acc, [PE{fmt ++ "Op", OP.nm(o) ++ op_msuf(fmt, OP.op(o)),
          OP.op(o), maybe_str(pcode_find(ps, OP.nm(o), OP.op(o)), "")}])))

def pcode_entry.eos(eos: List<&2, EO>, +ps: List<&2, PK>, +acc: List<&2, PE>) -> List<&2, PE>:
  match eos:
    case Nil{}: acc
    case +e <> +t: pcode_entry.eos(t, ps, pcode_entry.go(EO.ops(e), EO.fmt(e), ps, acc))

def pcode_entry(eos: List<&2, EO>, ps: List<&2, PK>) -> List<&2, PE>: pcode_entry.eos(eos, ps, Nil{})

# `sorted(set(e[0] for e in entries))` -- the import list is the enums that
# actually contributed a row, NOT every enum, which is why VOP2 is absent.

def pcode_enums.go(es: List<&2, PE>, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case +e <> +t: pcode_enums.go(t, List.append(&2, String, acc, [PE.en(e)]))

# `sorted(entries, key=lambda x: (x[0], x[2]))` -- by ENUM then OPCODE, never by
# name: `V_MAD_F32` (512) precedes `V_ADD_F32` (300) only because their enums
# differ.

# `pcode` is walked TWICE -- once for the rows, once for the import list -- so
# every parameter on this chain is BORROWED.  `List.sort`'s comparator takes
# `@_` for the same reason and because a comparator that consumed its operands
# would have to rebuild them.

# `pcode` is walked TWICE -- once for the rows, once for the import list -- so
# every parameter on this chain is BORROWED.  `List.sort`'s comparator takes
# `@_`, and `PE.en` is a `match` rather than a projection, so the comparator
# DESTRUCTURES ONCE and compares the two binders: asking `PE.en(a)` and
# `PE.en(b)` for the same field twice is two consumptions of one operand.

def pe_le(a: PE, b: PE) -> Bool:
  match a b:
    case PE{+en1, mn1, op1, code1} PE{+en2, mn2, op2, code2}:
      Bool.or(String.is_lt(en1, en2), Bool.and(String.eq(en1, en2), U32.is_le(op1, op2)))

def pcode_line(+e: PE) -> String: "  " ++ PE.en(e) ++ "." ++ PE.mn(e) ++ ": " ++ repr_str(PE.code(e)) ++ ","

def pcode_lines.go(es: List<&2, PE>, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case +e <> +t: pcode_lines.go(t, List.append(&2, String, acc, [pcode_line(e)]))

def write_pcode.head(ens: List<&2, String>, +arch: String) -> List<&2, String>:
  List.append(&2, String, [
    "# autogenerated from AMD ISA PDF - do not edit", "# ruff: noqa: E501",
    "from tinygrad.runtime.autogen.amd." ++ arch ++ ".enum import " ++ String.join(ens, ", "),
    "", "PCODE = {"], Nil{})

def write_pcode(+ps: List<&2, PK>, +eos: List<&2, EO>, +arch: String) -> List<&2, String>:
  # `List.append(x, A, xs, ys)` is `xs ++ ys`, so the HEADER IS THE FIRST
  # ARGUMENT and the rows the second.
  List.append(&2, String,
    write_pcode.head(sort_strs(dedup_adj(pcode_enums.go(pcode_entry(eos, ps), Nil{}))), arch),
    List.append(&2, String, pcode_lines.go(List.sort(PE, pe_le, pcode_entry(eos, ps)), Nil{}), ["}"]))

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

def u32_in(+x: U32, xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> +t: Bool.or(U32.is_eq(h, x), u32_in(x, t))

def dedup_u32.step(+x: U32, last: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(x, last), acc, List.append(&2, U32, acc, [x]))

def dedup_u32.go(xs: List<&2, U32>, last: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> +t: dedup_u32.go(t, x, dedup_u32.step(x, last, acc))

def dedup_u32(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case +x <> +t: dedup_u32.go(t, x, [x])

def u32_diff.go(xs: List<&2, U32>, +ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> +t: u32_diff.go(t, ys, Bool.pick(List<&2, U32>, u32_in(x, ys), acc,
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
    case +x <> +t: u32_filter.go(t, Bool.pick(List<&2, U32>, U32.is_lt(x, 256),
      List.append(&2, U32, acc, [x]), acc))

def u32_filter(xs: List<&2, U32>) -> List<&2, U32>: u32_filter.go(xs, Nil{})

# ---- `suffix_only_ops`, the {suffix: {fmt: {opcode}}} table ----------
# `suffix_only_ops.values()` is a list of dicts of sets, and three different
# questions are asked of it: does a format's BASE class exclude these opcodes,
# does a variant class ALLOW them, and which CLASS does an opcode's helper use.

def SG.fmt(g: SG) -> String:
  match g:
    case SG{+fmt, ops}: fmt

def SG.ops(g: SG) -> List<&2, U32>:
  match g:
    case SG{+fmt, ops}: ops

def SS.sfx(s: SS) -> String:
  match s:
    case SS{sfx, gs}: sfx

def SS.gs(s: SS) -> List<&2, SG>:
  match s:
    case SS{sfx, gs}: gs

def sg_hit(g: SG, op: U32) -> Bool: u32_in(op, SG.ops(g))

def sg_go.step(+g: SG, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(SG.fmt(g), fmt), u32_union(acc, SG.ops(g)), acc)

# ONE WALK answers every question of the form `d.get(fmt, set())`: the union of
# the groups whose format matches, which for a MISSING format is `Nil{}`.

def sg_go(gs: List<&2, SG>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match gs:
    case Nil{}: acc
    case +g <> +t: sg_go(t, fmt, sg_go.step(g, fmt, acc))

# `d.get(fmt, set())` for one suffix's dict of formats: found means the union,
# missing means nothing.  A MISS IS NOT AN ERROR, which is why this is a Bool
# pick and not a `Maybe` unwrap.

def sg_ops_of(gs: List<&2, SG>, +fmt: String) -> List<&2, U32>: sg_go(gs, fmt, Nil{})

# `suffix_only_ops[suffix].get(fmt, set())` -- the table MISSES keys in the
# real data, so a miss is Nil{} and not an error.

def ss_go.step(+s: SS, +sfx: String, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(SS.sfx(s), sfx), sg_ops_of(SS.gs(s), fmt), acc)

def ss_go(ss: List<&2, SS>, +sfx: String, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> +t: ss_go(t, sfx, fmt, ss_go.step(s, sfx, fmt, acc))

def sfx_ops(ss: List<&2, SS>, +sfx: String, +fmt: String) -> List<&2, U32>:
  ss_go(ss, sfx, fmt, Nil{})

# `set().union(*(d.get(fmt, set()) for d in suffix_only_ops.values()))` -- what
# the BASE class of this format must NOT allow.

def base_suffix_ops(ss: List<&2, SS>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case +s <> +t: base_suffix_ops(t, fmt, u32_union(acc, sg_ops_of(SS.gs(s), fmt)))

def base_suffix_ops.of(ss: List<&2, SS>, +fmt: String) -> List<&2, U32>:
  base_suffix_ops(ss, fmt, Nil{})

# `op_to_suffix = {op: suffix for suffix, ops in suffix_only_ops.items() for op in ops.get(fmt, set())}`
# -- the LAST suffix that claims an opcode wins, so the walk must not stop.

def op_sfx.go(ss: List<&2, SS>, +fmt: String, +op: U32, +acc: String) -> String:
  match ss:
    case Nil{}: acc
    case +s <> +t: op_sfx.go(t, fmt, op, Bool.pick(String, u32_in(op, sg_ops_of(SS.gs(s), fmt)),
      SS.sfx(s), acc))

def op_to_suffix(ss: List<&2, SS>, +fmt: String, op: U32) -> String:
  op_sfx.go(ss, fmt, op, "")

# ---- `sdst_opcodes`: ops whose `vdst` operand is an SGPR --------------
# `types.get((name, fmt), {})` then `.get("vdst", (None,None,None))[2] == "OPR_SREG"`.

def oi_hit(ois: List<&2, OI>, +nm: String) -> Bool:
  match ois:
    case Nil{}: False{}
    case +o <> +t: Bool.or(String.eq(OI.nm(o), nm), oi_hit(t, nm))

def oi_otype.step(+o: OI, +nm: String, +acc: String) -> String:
  Bool.pick(String, String.eq(OI.nm(o), nm), OI.otype(o), acc)

def oi_otype(ois: List<&2, OI>, +nm: String, +acc: String) -> String:
  match ois:
    case Nil{}: acc
    case +o <> +t: oi_otype(t, nm, oi_otype.step(o, nm, acc))

# `op_types.get("vdst", (None,None,None))[2]` -- "" when there is no `vdst`.

def vdst_is_sreg(t: TY) -> Bool: String.eq(oi_otype(TY.flds(t), "vdst", ""), "OPR_SREG")

def ty_find.kv(+t: TY, +nm: String, +base: String) -> Maybe<&2, TY>:
  Bool.pick(Maybe<&2, TY>, Bool.and(String.eq(TY.name(t), nm), String.eq(TY.base(t), base)),
    Some{t}, None{})

def ty_find.take(acc: Maybe<&2, TY>, hit: Maybe<&2, TY>) -> Maybe<&2, TY>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

# THE WALK NEVER STOPS AND NEVER NESTS.  A `match` on a parameter NESTED in a
# match arm is refused, and `Bool.pick` does not SEQUENCE a self-call, so
# first-hit-wins is `take` on an accumulator the walk keeps feeding: the answer
# is the first match either way, and this shape is ONE `match`.

def ty_find.of(tys: List<&2, TY>, acc: Maybe<&2, TY>, +nm: String, +base: String) -> Maybe<&2, TY>:
  match tys:
    case Nil{}: acc
    case +t <> r: ty_find.of(r, ty_find.take(acc, ty_find.kv(t, nm, base)), nm, base)

def ty_find(tys: List<&2, TY>, +nm: String, +base: String) -> Maybe<&2, TY>:
  ty_find.of(tys, None{}, nm, base)

def ty_is_sreg(m: Maybe<&2, TY>) -> Bool:
  match m:
    case None{}: False{}
    case Some{+g}: vdst_is_sreg(g)

def sdst_hit(tys: List<&2, TY>, +nm: String, +fmt: String) -> Bool:
  ty_is_sreg(ty_find(tys, nm, fmt))

def sdst_ops.ops(os_: List<&2, OP>, +fmt: String, +tys: List<&2, TY>,
                 +acc: List<&2, U32>) -> List<&2, U32>:
  match os_:
    case Nil{}: acc
    case +o <> +t: sdst_ops.ops(t, fmt, tys,
      Bool.pick(List<&2, U32>, sdst_hit(tys, OP.nm(o), fmt),
        List.append(&2, U32, acc, [OP.op(o)]), acc))

def sdst_ops.eos(eos: List<&2, EO>, +tys: List<&2, TY>, +acc: List<&2, SG>) -> List<&2, SG>:
  match eos:
    case Nil{}: acc
    case +e <> +t: sdst_ops.eos(t, tys, List.append(&2, SG, acc,
      [SG{EO.fmt(e), sdst_ops.ops(EO.ops(e), EO.fmt(e), tys, Nil{})}]))

def sdst_ops(tys: List<&2, TY>, eos: List<&2, EO>) -> List<&2, SG>:
  sdst_ops.eos(eos, tys, Nil{})

def sdst_of.step(+g: SG, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(SG.fmt(g), fmt), u32_union(acc, SG.ops(g)), acc)

# ---- the encoding split and the `seg` test ---------------------------

def sdst_of(sgs: List<&2, SG>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match sgs:
    case Nil{}: acc
    case +g <> +t: sdst_of(t, fmt, sdst_of.step(g, fmt, acc))

def bases.step(+e: EC, +acc: List<&2, EC>) -> List<&2, EC>:
  Bool.pick(List<&2, EC>, String.eq(get_base_fmt(EC.name(e)), EC.name(e)),
    List.append(&2, EC, acc, [e]), acc)

def bases.go(encs: List<&2, EC>, +acc: List<&2, EC>) -> List<&2, EC>:
  match encs:
    case Nil{}: acc
    case +e <> +t: bases.go(t, bases.step(e, acc))

# `base = get_base_fmt(enc_name); base == enc_name` -- the BASE/VARIANT split.

def bases(encs: List<&2, EC>) -> List<&2, EC>: bases.go(sort_encs(encs), Nil{})

def variants.step(+e: EC, +acc: List<&2, EC>) -> List<&2, EC>:
  Bool.pick(List<&2, EC>, String.eq(get_base_fmt(EC.name(e)), EC.name(e)), acc,
    List.append(&2, EC, acc, [e]))

def variants.go(encs: List<&2, EC>, +acc: List<&2, EC>) -> List<&2, EC>:
  match encs:
    case Nil{}: acc
    case +e <> +t: variants.go(t, variants.step(e, acc))

# `else: variant_encodings[enc_name] = data` -- the other half of the split.

def variants(encs: List<&2, EC>) -> List<&2, EC>: variants.go(sort_encs(encs), Nil{})

def seg_hit(fs: List<&2, Fld>) -> Bool:
  match fs:
    case Nil{}: False{}
    case +f <> +t: Bool.or(String.eq(Fld.nm(f), "seg"), seg_hit(t))

# `enc_name in ("FLAT_GLOBAL","FLAT_SCRATCH","FLAT_GLBL","DPP","SDWA")` -- the
# formats that get NO class at all, so the walk skips them.

def skip_cls(+nm: String) -> Bool:
  Bool.or(String.eq(nm, "FLAT_GLOBAL"), Bool.or(String.eq(nm, "FLAT_SCRATCH"),
    Bool.or(String.eq(nm, "FLAT_GLBL"), Bool.or(String.eq(nm, "DPP"), String.eq(nm, "SDWA")))))

def is_flat_split(+nm: String, has_seg: Bool) -> Bool:
  Bool.and(has_seg, Bool.or(String.eq(nm, "FLAT"), String.eq(nm, "VFLAT")))

# `prefix = "V" if enc_name == "VFLAT" else ""`

def flat_prefix(nm: String) -> String:
  Bool.pick(String, String.eq(nm, "VFLAT"), "V", "")

def flat_variants(+nm: String) -> List<&2, FV>:
  [FV{flat_prefix(nm) ++ "FLAT", 0, flat_prefix(nm) ++ "FLATOp"},
   FV{flat_prefix(nm) ++ "GLOBAL", 2, flat_prefix(nm) ++ "GLOBALOp"},
   FV{flat_prefix(nm) ++ "SCRATCH", 1, flat_prefix(nm) ++ "SCRATCHOp"}]

def FV.cls(f: FV) -> String:
  match f:
    case FV{cls, +seg, oe}: cls

def FV.oe(f: FV) -> String:
  match f:
    case FV{cls, +seg, oe}: oe

# ---- the import header -----------------------------------------------

def enum_names.take.plain(+e: EO, +acc: List<&2, String>, is_plain: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, is_plain, List.append(&2, String, acc, [EO.fmt(e)]), acc)

def enum_names.take.of(+plain: Bool, +e: EO, +acc: List<&2, String>, is_plain: Bool) -> List<&2, String>:
  match plain:
    case True{}: enum_names.take.plain(e, acc, is_plain)
    case False{}: enum_names.take.op(e, acc, is_plain)

# `k in ("HWREG","MSG")` -> the bare name; otherwise the `<fmt>Op` class name.

def enum_names.take(+e: EO, +plain: Bool, +acc: List<&2, String>) -> List<&2, String>:
  enum_names.take.of(plain, e, acc, enum_plain_b(EO.fmt(e)))

def enum_names.go(eos: List<&2, EO>, +plain: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case +e <> +t: enum_names.go(t, plain, enum_names.take(e, plain, acc))

def enum_names(+eos: List<&2, EO>) -> List<&2, String>:
  List.append(&2, String, sort_strs(dedup_adj(enum_names.go(sort_eos(eos), False{}, Nil{}))),
    sort_strs(dedup_adj(enum_names.go(sort_eos(eos), True{}, Nil{}))))

# `all_field_defs = " ".join(field_def(fn, hi, lo, enc, eb) for enc, (flds, eb) in encodings.items() for fn, hi, lo in flds)`

def all_defs.flds(fs: List<&2, Fld>, +enc: String, +bits: String, +hb: Bool, +fixed: List<&2, Fd2>,
                  +encs: List<&2, EC>, +enums: List<&2, EO>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> +t: all_defs.flds(t, enc, bits, hb, fixed, encs, enums,
      List.append(&2, String, acc, [field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), enc, bits, hb,
        fixed, encs, enums)]))

# ONE ENCODING'S field definitions, as a list of strings.

def all_defs.of(fs: List<&2, Fld>, +enc: String, +bits: String, hb: Bool, fixed: List<&2, Fd2>,
                +encs: List<&2, EC>, +enums: List<&2, EO>) -> List<&2, String>:
  all_defs.flds(fs, enc, bits, hb, fixed, encs, enums, Nil{})

def all_defs.append(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> +t: all_defs.append(t, List.append(&2, String, acc, [x]))

def all_defs.go(walk: List<&2, EC>, +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +enums: List<&2, EO>,
                +acc: List<&2, String>) -> List<&2, String>:
  match walk:
    case Nil{}: acc
    case +e <> +t: all_defs.go(t, fixed, encs, enums,
      all_defs.append(all_defs.of(EC.fields(e), EC.name(e), EC.bits(e),
        EC.has_bits(e), fixed, encs, enums), acc))

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

def dsl_used.step(+x: String, +hay: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.contains(hay, x), List.append(&2, String, acc, [x]), acc)

def dsl_used(xs: List<&2, String>, +hay: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> +t: dsl_used(t, hay, dsl_used.step(x, hay, acc))

def dsl_reexport(+encs: List<&2, EC>, fixed: List<&2, Fd2>, eos: List<&2, EO>) -> List<&2, String>:
  dedup_adj(sort_strs(List.append(&2, String, dsl_used(all_dsl(),
    String.join(all_defs.go(sort_encs(encs), fixed, encs, eos, Nil{}), " "), Nil{}),
    List.append(&2, String, ["Inst"], dsl_regs()))))

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

def all_ops.of(os_: List<&2, OP>, +acc: List<&2, U32>) -> List<&2, U32>:
  match os_:
    case Nil{}: acc
    case +o <> +t: all_ops.of(t, List.append(&2, U32, acc, [OP.op(o)]))

def all_ops.eos.step(+e: EO, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(EO.fmt(e), fmt), all_ops.of(EO.ops(e), acc), acc)

# `seg = FixedBitField(hi, lo, SEG)` -- the literal is NOT a `0b` bitfield,
# unlike `encoding`, because `seg` is a plain integer in the DSL.

def all_ops.eos(eos: List<&2, EO>, +fmt: String, +acc: List<&2, U32>) -> List<&2, U32>:
  match eos:
    case Nil{}: acc
    case +e <> +t: all_ops.eos(t, fmt, all_ops.eos.step(e, fmt, acc))

def all_ops(fmt: String, eos: List<&2, EO>) -> List<&2, U32>:
  dedup_u32(sort_u32s(all_ops.eos(eos, fmt, Nil{})))

def base_allowed(encs: List<&2, EC>, +eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>,
                 +fmt: String) -> List<&2, U32>:
  u32_diff(u32_diff(all_ops(fmt, eos), base_suffix_ops.of(ss, fmt)), sdst_of(sdst_ops(tys, eos), fmt, Nil{}))

# `set(enums.get(name, {}).keys())`

def base_field(+f: Fld, +cls: String, +bits: String, hb: Bool, seg: U32, +oe: String,
               allowed: List<&2, U32>, +eos: List<&2, EO>, fixed: List<&2, Fd2>,
               encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "seg"),
    List.append(&2, String, acc, ["  " ++ base_field.seg(f, seg)]),
    Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "op"),
      List.append(&2, String, acc, ["  " ++ base_field.op(f, oe, allowed, eos)]),
      List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++
        field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), cls, bits, hb, fixed, encs, eos)])))

def base_fields.go(fs: List<&2, Fld>, +cls: String, +bits: String, +hb: Bool, +seg: U32, +oe: String,
                   +allowed: List<&2, U32>, +eos: List<&2, EO>, +fixed: List<&2, Fd2>,
                   +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> +t: base_fields.go(t, cls, bits, hb, seg, oe, allowed, eos, fixed, encs,
      base_field(f, cls, bits, hb, seg, oe, allowed, eos, fixed, encs, acc))

# ONE FLAT CLASS: `class {cls}(Inst):` then its sorted fields then a blank.

def flat_class(+fv: FV, +e: EC, +eos: List<&2, EO>, fixed: List<&2, Fd2>, encs: List<&2, EC>,
               +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String, ["class " ++ FV.cls(fv) ++ "(Inst):"],
    List.append(&2, String,
      base_fields.go(sort_fields(EC.fields(e)), FV.cls(fv), EC.bits(e), EC.has_bits(e),
        FV.seg(fv), FV.oe(fv), all_ops(FV.cls(fv), eos), eos, fixed, encs, Nil{}), [""])))

def flat_split.go(vs: List<&2, FV>, +e: EC, +eos: List<&2, EO>, +fixed: List<&2, Fd2>,
                  +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: acc
    case +v <> +t: flat_split.go(t, e, eos, fixed, encs, flat_class(v, e, eos, fixed, encs, acc))

# `op = EnumBitField(hi, lo, base_fmt + "Op", fmt_allowed(base_fmt + "Op", base_allowed))`

def plain_field(+f: Fld, +e: EC, +eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>,
                fixed: List<&2, Fd2>, +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(Fld.nm(f), "op"),
    List.append(&2, String, acc, ["  op = EnumBitField(" ++ U32.show(Fld.hi(f)) ++ ", " ++
      U32.show(Fld.lo(f)) ++ ", " ++ get_base_fmt(EC.name(e)) ++ "Op, " ++
      fmt_allowed(get_base_fmt(EC.name(e)) ++ "Op", base_allowed(encs, eos, tys, ss, EC.name(e)), eos) ++ ")"]),
    List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++ field_def(Fld.nm(f), Fld.hi(f),
      Fld.lo(f), EC.name(e), EC.bits(e), String.eq(Fld.nm(f), "encoding"), fixed, encs, eos)]))

def plain_fields.go(fs: List<&2, Fld>, +e: EC, +eos: List<&2, EO>, +tys: List<&2, TY>, +ss: List<&2, SS>,
                    +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> +t: plain_fields.go(t, e, eos, tys, ss, fixed, encs,
      plain_field(f, e, eos, tys, ss, fixed, encs, acc))

def plain_class(+e: EC, eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String,
    ["class " ++ EC.name(e) ++ "(Inst):"],
    List.append(&2, String,
      plain_fields.go(sort_fields(EC.fields(e)), e, eos, tys, ss, fixed, encs, Nil{}), [""])))

# The base class passes `enc_bits if fn == "encoding" else None`, so ONLY the
# `encoding` field is a FixedBitField here.  `field_def`'s `has_bits` flag IS
# that test, and passing it for every field would make `SGPRField` and
# `BitField` indistinguishable in the gate.

def base_class(+e: EC, +eos: List<&2, EO>, tys: List<&2, TY>, ss: List<&2, SS>, +fixed: List<&2, Fd2>,
               +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, is_flat_split(EC.name(e), seg_hit(EC.fields(e))),
    flat_split.go(flat_variants(EC.name(e)), e, eos, fixed, encs, acc),
    Bool.pick(List<&2, String>, skip_cls(EC.name(e)), acc,
      plain_class(e, eos, tys, ss, fixed, encs, acc)))

def base_classes(walk: List<&2, EC>, +encs: List<&2, EC>, +eos: List<&2, EO>, +tys: List<&2, TY>,
                 +ss: List<&2, SS>, +fixed: List<&2, Fd2>, +acc: List<&2, String>) -> List<&2, String>:
  match walk:
    case Nil{}: acc
    case +e <> +t: base_classes(t, encs, eos, tys, ss, fixed,
      base_class(e, eos, tys, ss, fixed, encs, acc))

# ======================================================================
# FOLD 2 -- THE VARIANT CLASSES.  `class {enc}({base})`, extra fields only.
# ======================================================================

# `next((sfx for sfx in _VARIANT_SUFFIXES if enc_name.endswith(sfx)), None)` --
# the FIRST matching suffix in TABLE order, not the longest.

def variant_suffix.step(+nm: String, +h: String, +acc: String) -> String:
  Bool.pick(String, String.ends_with(nm, h), h, acc)

def variant_suffix.go(+nm: String, sfx: List<&2, String>, i: Nat, +acc: String) -> String:
  match sfx:
    case Nil{}: acc
    case +h <> +t: variant_suffix.go(nm, t, Nat.add(i, 1n), variant_suffix.step(nm, h, acc))

# `next((sfx for sfx in _VARIANT_SUFFIXES if enc_name.endswith(sfx)), None)` --
# the FIRST match in TABLE order, and the table order is `_LIT, _DPP16, _DPP8,
# _SDWA_SDST, _SDWA, _MFMA`, so a first-match walk and not the longest suffix.

def variant_suffix(nm: String) -> String: variant_suffix.go(nm, variant_suffixes(), 0n, "")

def ss_has(ss: List<&2, SS>, +sfx: String) -> Bool:
  match ss:
    case Nil{}: False{}
    case +s <> +t: Bool.or(String.eq(SS.sfx(s), sfx), ss_has(t, sfx))

# `is_suffix_variant = variant_suffix in suffix_only_ops`

def is_suffix_variant(nm: String, ss: List<&2, SS>) -> Bool: ss_has(ss, variant_suffix(nm))

# `extra_fields = [(fn,hi,lo) for fn,hi,lo in fields if fn not in base_fields]`

def fld_in(fs: List<&2, Fld>, +nm: String) -> Bool:
  match fs:
    case Nil{}: False{}
    case +f <> +t: Bool.or(String.eq(Fld.nm(f), nm), fld_in(t, nm))

# `op_field = next((f for f in base_encodings[base][0] if f[0] == "op"), None)`

def extra_fields.step(+f: Fld, base_fs: List<&2, Fld>, +acc: List<&2, Fld>) -> List<&2, Fld>:
  Bool.pick(List<&2, Fld>, fld_in(base_fs, Fld.nm(f)), acc, List.append(&2, Fld, acc, [f]))

def extra_fields.go(fs: List<&2, Fld>, +base_fs: List<&2, Fld>, +acc: List<&2, Fld>) -> List<&2, Fld>:
  match fs:
    case Nil{}: acc
    case +f <> +t: extra_fields.go(t, base_fs, extra_fields.step(f, base_fs, acc))

# `fn not in base_fields` -- a field the BASE class does not already declare.

def fld_find.take(acc: Maybe<&2, Fld>, hit: Maybe<&2, Fld>) -> Maybe<&2, Fld>:
  match acc:
    case Some{+g}: Some{g}
    case None{}: hit

def fld_find.kv(+f: Fld, +nm: String) -> Maybe<&2, Fld>:
  Bool.pick(Maybe<&2, Fld>, String.eq(Fld.nm(f), nm), Some{f}, None{})

def fld_find.of(fs: List<&2, Fld>, acc: Maybe<&2, Fld>, +nm: String) -> Maybe<&2, Fld>:
  match fs:
    case Nil{}: acc
    case +f <> r: fld_find.of(r, fld_find.take(acc, fld_find.kv(f, nm)), nm)

def fld_find(fs: List<&2, Fld>, +nm: String) -> Maybe<&2, Fld>: fld_find.of(fs, None{}, nm)

# `_LIT` allows ALL of the base format's opcodes; every other suffix-only
# variant allows exactly `suffix_only_ops[sfx][base]`.

def base_op_field(base: EC) -> Maybe<&2, Fld>: fld_find(EC.fields(base), "op")

def variant_allowed(+base: EC, eos: List<&2, EO>, ss: List<&2, SS>, +sfx: String) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(sfx, "_LIT"), all_ops(EC.name(base), eos),
    sfx_ops(ss, sfx, EC.name(base)))

def variant_field(+f: Fld, +cls: String, fixed: List<&2, Fd2>, encs: List<&2, EC>,
                  +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, ["  " ++ Fld.nm(f) ++ " = " ++
    field_def(Fld.nm(f), Fld.hi(f), Fld.lo(f), cls, "", False{}, fixed, encs, Nil{})])

def variant_fields.go(fs: List<&2, Fld>, +cls: String, +fixed: List<&2, Fd2>, +encs: List<&2, EC>,
                      +acc: List<&2, String>) -> List<&2, String>:
  match fs:
    case Nil{}: acc
    case +f <> +t: variant_fields.go(t, cls, fixed, encs, variant_field(f, cls, fixed, encs, acc))

def variant_op_line(m: Maybe<&2, Fld>, +base: EC, allowed: List<&2, U32>, eos: List<&2, EO>,
                    +acc: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}: acc
    case Some{+g}: List.append(&2, String, acc,
      ["  op = EnumBitField(" ++ U32.show(Fld.hi(g)) ++ ", " ++ U32.show(Fld.lo(g)) ++ ", " ++
        EC.name(base) ++ "Op, " ++ fmt_allowed(EC.name(base) ++ "Op", allowed, eos) ++ ")"])

# `if extra_fields or is_suffix_variant` -- the emitted body of a variant is
# non-empty exactly when it has an extra field, and `is_suffix_variant` adds
# the `op` override even with no extra field at all.

def variant_fields_has(body: List<&2, String>) -> Bool: Bool.not(List.is_empty(&2, String, body))

def variant_class.of(+e: EC, +base: EC, +eos: List<&2, EO>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                     encs: List<&2, EC>, +sv: Bool, +body: List<&2, String>,
                     +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.or(sv, variant_fields_has(body)),
    List.append(&2, String, acc, List.append(&2, String,
      ["class " ++ EC.name(e) ++ "(" ++ EC.name(base) ++ "):"],
      List.append(&2, String,
        Bool.pick(List<&2, String>, sv,
          variant_op_line(base_op_field(base), base, variant_allowed(base, eos, ss, variant_suffix(EC.name(e))), eos, Nil{}),
          Nil{}),
        List.append(&2, String, body, [""])))), acc)

def variant_class(+e: EC, +base: EC, eos: List<&2, EO>, +ss: List<&2, SS>, +fixed: List<&2, Fd2>,
                  +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  variant_class.of(e, base, eos, ss, fixed, encs,
    is_suffix_variant(EC.name(e), ss),
    variant_fields.go(sort_fields(extra_fields.go(EC.fields(e), EC.fields(base), Nil{})),
      EC.name(e), fixed, encs, Nil{}), acc)

def variant_class.of2(+e: EC, +base: EC, eos: List<&2, EO>, ss: List<&2, SS>, fixed: List<&2, Fd2>,
                      encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(EC.name(base)), acc,
    variant_class(e, base, eos, ss, fixed, encs, acc))

# ======================================================================
# FOLD 3 -- THE SDST CLASSES.
# ======================================================================

def variant_classes(vs: List<&2, EC>, +encs: List<&2, EC>, +eos: List<&2, EO>, +ss: List<&2, SS>,
                    +fixed: List<&2, Fd2>, +acc: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: acc
    case +e <> +t: variant_classes(t, encs, eos, ss, fixed,
      variant_class.of2(e, ec_get(get_base_fmt(EC.name(e)), encs), eos, ss, fixed, encs, acc))

# `if base not in base_encodings: continue` -- `ec_get` answers the EMPTY
# encoding on a miss, and `EC.name` of that is "", which no variant names.

def sdst_base_widened(+base: EC, +eos: List<&2, EO>, +tys: List<&2, TY>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, String.eq(EC.name(base), "VOP3"),
    u32_union(sdst_of(sdst_ops(tys, eos), EC.name(base), Nil{}),
      u32_filter(all_ops(EC.name(base), eos))),
    sdst_of(sdst_ops(tys, eos), EC.name(base), Nil{}))

def sdst_empty(xs: List<&2, U32>) -> Bool: List.is_empty(&2, U32, xs)

def sdst_lit(vs: List<&2, EC>, +base: String) -> Maybe<&2, EC>: ec_find(base ++ "_LIT", vs)

def sdst_lit_field.of(m: Maybe<&2, EC>) -> Maybe<&2, Fld>:
  match m:
    case None{}: None{}
    case Some{+g}: fld_find(EC.fields(g), "literal")

def sdst_lit_field(vs: List<&2, EC>, +base: String) -> Maybe<&2, Fld>:
  sdst_lit_field.of(sdst_lit(vs, base))

def sdst_one(+base: EC, +eos: List<&2, EO>, +tys: List<&2, TY>, vs: List<&2, EC>,
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

def sdst_lit_lines.of(+base: EC, m: Maybe<&2, Fld>, +acc: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}: acc
    case Some{+g}: List.append(&2, String, acc, List.append(&2, String,
      ["class " ++ EC.name(base) ++ "_SDST_LIT(" ++ EC.name(base) ++ "_SDST):"],
      List.append(&2, String, ["  literal = BitField(" ++ U32.show(Fld.hi(g)) ++ ", " ++
        U32.show(Fld.lo(g)) ++ ")"], [""])))

# `[("VOP1", 24, 17), ("VOP3", 7, 0)]` -- the table AND the order.

def sdst_lit_lines(+base: EC, vs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  sdst_lit_lines.of(base, sdst_lit_field(vs, EC.name(base)), acc)

def SD.base(s: SD) -> String:
  match s:
    case SD{+base, hi, lo}: base

def SD.hi(s: SD) -> U32:
  match s:
    case SD{+base, hi, lo}: hi

def SD.lo(s: SD) -> U32:
  match s:
    case SD{+base, hi, lo}: lo

def sdst_targets() -> List<&2, SD>: [SD{"VOP1", 24, 17}, SD{"VOP3", 7, 0}]

def sdst_walk.go(tds: List<&2, SD>, +eos: List<&2, EO>, +tys: List<&2, TY>, +vs: List<&2, EC>,
                 +fixed: List<&2, Fd2>, +encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  match tds:
    case Nil{}: acc
    case +d <> +t: sdst_walk.go(t, eos, tys, vs, fixed, encs,
      sdst_lit_lines(ec_get(SD.base(d), encs), vs,
        sdst_one(ec_get(SD.base(d), encs), eos, tys, vs, fixed, encs, SD.hi(d), SD.lo(d), acc)))

def sdst_classes(eos: List<&2, EO>, tys: List<&2, TY>, vs: List<&2, EC>, fixed: List<&2, Fd2>,
                 encs: List<&2, EC>, +acc: List<&2, String>) -> List<&2, String>:
  sdst_walk.go(sdst_targets(), eos, tys, vs, fixed, encs, acc)

# ================= INS-PART-3 =========================
# FOLD 4 -- THE `functools.partial` HELPERS, and the emitter itself.
#
# This is the only fold that reads `suffix_only_ops` to CHOOSE A CLASS rather
# than to restrict a set, and the only one that drops a row: `ADDTID` ops exist
# in BOTH the FLAT and GLOBAL enums so the PDF has one pseudocode entry for
# them, and only GLOBAL/VGLOBAL get a helper.
# ======================================================================

# `fmt not in base_encodings and fmt not in ("GLOBAL","SCRATCH","VGLOBAL","VSCRATCH")`

def not(b: Bool) -> Bool: Bool.not(b)

# `fmt in base_encodings`, i.e. `fmt in encodings AND get_base_fmt(fmt) == fmt`:
# a VARIANT encoding is in `encodings` too, and only the second half of the
# test rejects it.  VFLAT is in neither half here -- the fixture has VFLATOp but
# no VFLAT encoding -- so VFLAT gets no helpers while VGLOBAL/VSCRATCH do.

def helper_ok(+fmt: String, encs: List<&2, EC>) -> Bool:
  Bool.or(Bool.and(not(String.eq(EC.name(ec_get(fmt, encs)), "")), String.eq(get_base_fmt(fmt), fmt)),
    Bool.or(String.eq(fmt, "GLOBAL"), Bool.or(String.eq(fmt, "SCRATCH"),
      Bool.or(String.eq(fmt, "VGLOBAL"), String.eq(fmt, "VSCRATCH")))))

def drop_addtid(nm: String, +fmt: String) -> Bool:
  Bool.and(String.contains(nm, "ADDTID"), Bool.or(String.eq(fmt, "FLAT"), String.eq(fmt, "VFLAT")))

def helper_cls(+op: U32, +fmt: String, sgs: List<&2, SG>, +ss: List<&2, SS>, +sdst: List<&2, U32>) -> String:
  Bool.pick(String, Bool.and(String.eq(fmt, "VOP1"), u32_in(op, sdst)), fmt ++ "_SDST",
    Bool.pick(String, Bool.and(String.eq(fmt, "VOP3"), Bool.or(u32_in(op, sdst), U32.is_lt(op, 256))),
      fmt ++ "_SDST",
      Bool.pick(String, String.eq(op_to_suffix(ss, fmt, op), ""), fmt,
        fmt ++ op_to_suffix(ss, fmt, op))))

def helper_line(+op: U32, +nm: String, +fmt: String, +sgs: List<&2, SG>, ss: List<&2, SS>,
                tys: List<&2, TY>, eos: List<&2, EO>, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, drop_addtid(nm, fmt), acc,
    List.append(&2, String, acc, [String.to_lower(nm) ++ String.to_lower(op_msuf(fmt, op)) ++
      " = functools.partial(" ++ helper_cls(op, fmt, sgs, ss, sdst_of(sgs, fmt, Nil{})) ++ ", " ++
      fmt ++ "Op." ++ nm ++ op_msuf(fmt, op) ++ ")"]))

def helper_ops(os_: List<&2, OP>, +fmt: String, +ss: List<&2, SS>, +sgs: List<&2, SG>,
               +tys: List<&2, TY>, +eos: List<&2, EO>, +acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case +o <> +t: helper_ops(t, fmt, ss, sgs, tys, eos,
      helper_line(OP.op(o), OP.nm(o), fmt, sgs, ss, tys, eos, acc))

def helper_fmts(eos: List<&2, EO>, +encs: List<&2, EC>, +ss: List<&2, SS>, +sgs: List<&2, SG>,
                +tys: List<&2, TY>, +acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case +e <> +t: helper_fmts(t, encs, ss, sgs, tys,
      Bool.pick(List<&2, String>, helper_ok(EO.fmt(e), encs),
        helper_ops(sort_ops(EO.ops(e)), EO.fmt(e), ss, sgs, tys, Nil{}, acc), acc))

# `lines.append("# instruction helpers")` PRECEDES the loop, so the marker leads
# the block rather than closing it.

def helpers(+eos: List<&2, EO>, encs: List<&2, EC>, ss: List<&2, SS>, +tys: List<&2, TY>,
            +acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, List.append(&2, String, acc, ["# instruction helpers"]),
    helper_fmts(sort_eos(eos), encs, ss, sdst_ops(tys, eos), tys, Nil{}))

# ======================================================================
# `write_ins` -- the four folds, in order, behind the import header.
# ======================================================================

def write_ins.head.of(+encs: List<&2, EC>, +eos: List<&2, EO>, +arch: String,
                      +fixed: List<&2, Fd2>) -> List<&2, String>:
  ["# autogenerated from AMD ISA XML - do not edit", "# ruff: noqa: E501,F401",
   "from tinygrad.renderer.amd.dsl import " ++ String.join(dsl_reexport(encs, fixed, eos), ", "),
   "from tinygrad.runtime.autogen.amd." ++ arch ++ ".enum import " ++
     String.join(enum_names(eos), ", "),
   "import functools", ""]

# ===========================================================================
# THE GATE.
#
# EVERY `py=` LITERAL BELOW IS A ROW OF `.agents/slop/ga-oracle.txt`, WHICH
# CALLS generate.py's OWN FUNCTIONS -- `_strip_enc`, `_norm_field`,
# `_map_flat`, and the four emitters, whose emitted FILES are read back.  No
# `py=` here was typed by a human; `.agents/slop/ga_fix.py` splices them in
# from the oracle, and it REFUSES to emit a row whose name is not in the
# oracle file.  That is the rule five files in this project broke by hand
# (`cstyle` 17/215, `ops_nv` 33/219, `rdma` one hex digit, `amdev` 7/80,
# `ops_qcom` one table entry).
# ===========================================================================

# ---- THE FIXTURE.  Built by `.agents/slop/ga_fix.py` from the SAME dicts
# `ga-oracle.py` hands to `generate.write_ins`, so the port's fixture and
# CPython's input cannot drift apart.

def write_ins.head(encs: List<&2, EC>, +eos: List<&2, EO>, +arch: String) -> List<&2, String>:
  write_ins.head.of(encs, eos, arch, fixed_of(arch))

def write_ins.body.of(+encs: List<&2, EC>, +eos: List<&2, EO>, +ss: List<&2, SS>, +tys: List<&2, TY>,
                      +arch: String, +fixed: List<&2, Fd2>) -> List<&2, String>:
  # `List.append(x, A, xs, ys)` is `xs ++ ys`, so the HEADER IS THE FIRST
  # ARGUMENT and the class list the second.
  List.append(&2, String, write_ins.head.of(encs, eos, arch, fixed),
    sdst_classes(eos, tys, variants(encs), fixed, encs,
      variant_classes(variants(encs), encs, eos, ss, fixed,
        base_classes(bases(encs), encs, eos, tys, ss, fixed, Nil{}))))

def write_ins.body(+encs: List<&2, EC>, +eos: List<&2, EO>, +ss: List<&2, SS>, +tys: List<&2, TY>,
                   +arch: String) -> List<&2, String>:
  write_ins.body.of(encs, eos, ss, tys, arch, fixed_of(arch))

def write_ins(+encs: List<&2, EC>, +eos: List<&2, EO>, +ss: List<&2, SS>, +tys: List<&2, TY>,
              +arch: String) -> List<&2, String>:
  # the four folds, outermost LAST: helpers wraps sdst wraps variant wraps base
  helpers(eos, encs, ss, tys, write_ins.body(encs, eos, ss, tys, arch))

# ---- THE FIXTURE.  Built by `.agents/slop/ga_fix.py` from the SAME dicts
# `ga-oracle.py` hands to `generate.write_ins`, so the port's fixture and
# CPython's input cannot drift apart.

def fx_encs() -> List<&2, EC>:
  [EC.of("DPP", [Fld.of("encoding", 31, 31), Fld.of("op", 20, 17), Fld.of("vdst", 10, 3), Fld.of("src0", 2, 0)], "1", True{}), EC.of("FLAT", [Fld.of("encoding", 31, 31), Fld.of("op", 29, 18), Fld.of("seg", 17, 15), Fld.of("offset", 14, 0)], "1", True{}), EC.of("GLOBAL", [Fld.of("encoding", 31, 31), Fld.of("op", 29, 18), Fld.of("offset", 14, 0)], "1", True{}), EC.of("HWREG", [Fld.of("encoding", 16, 10), Fld.of("op", 9, 0)], "0", True{}), EC.of("MSG", [Fld.of("encoding", 17, 12), Fld.of("op", 11, 0)], "0", True{}), EC.of("SCRATCH", [Fld.of("encoding", 31, 31), Fld.of("op", 29, 18), Fld.of("offset", 13, 0)], "1", True{}), EC.of("SDWA", [Fld.of("encoding", 31, 31), Fld.of("opx", 16, 15), Fld.of("opy", 14, 13), Fld.of("src0", 8, 0)], "1", True{}), EC.of("SM", [Fld.of("encoding", 25, 25), Fld.of("op", 17, 16), Fld.of("saddr", 31, 25), Fld.of("sdst", 24, 18), Fld.of("sdata", 12, 6)], "1", True{}), EC.of("SOP1", [Fld.of("encoding", 23, 23), Fld.of("op", 22, 16), Fld.of("saddr", 31, 24), Fld.of("ssrc0", 15, 8), Fld.of("soffset", 7, 1), Fld.of("sdst", 6, 0)], "1", True{}), EC.of("SOPK", [Fld.of("encoding", 27, 27), Fld.of("op", 23, 16), Fld.of("sbase", 31, 26), Fld.of("srsrc", 15, 11), Fld.of("ssamp", 10, 6), Fld.of("simm16", 5, 0)], "1", True{}), EC.of("VOP1", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("vdst", 16, 9), Fld.of("clmp", 8, 7), Fld.of("src0", 6, 0)], "1", True{}), EC.of("VOP1_DPP16", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("dpp", 8, 0)], "1", True{}), EC.of("VOP1_DPP8", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("row", 8, 6), Fld.of("bank_mask", 5, 0)], "1", True{}), EC.of("VOP1_LIT", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("literal", 15, 0)], "1", True{}), EC.of("VOP1_SDWA", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("sdst", 9, 0)], "1", True{}), EC.of("VOP1_SDWA_SDST", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("sdst", 9, 0)], "1", True{}), EC.of("VOP2", [Fld.of("encoding", 31, 31), Fld.of("op", 25, 17), Fld.of("vdst", 16, 9), Fld.of("src0", 8, 0)], "1", True{}), EC.of("VOP3", [Fld.of("encoding", 31, 31), Fld.of("op", 22, 16), Fld.of("src0", 8, 0)], "1", True{}), EC.of("VOP3B", [Fld.of("encoding", 31, 31), Fld.of("op", 25, 17), Fld.of("src0", 8, 0)], "1", True{}), EC.of("VOP3P", [Fld.of("encoding", 31, 31), Fld.of("op", 30, 21), Fld.of("opsel_hi", 20, 19), Fld.of("opsel_hi2", 18, 17), Fld.of("vdst", 16, 9), Fld.of("vdsty", 8, 8), Fld.of("src0", 7, 0)], "1", True{}), EC.of("VOP3PX2", [Fld.of("encoding", 31, 31), Fld.of("op", 29, 26), Fld.of("x2encoding", 25, 20), Fld.of("vdst", 17, 10), Fld.of("src0", 9, 0)], "1", True{}), EC.of("VOP3P_MFMA", [Fld.of("encoding", 31, 31), Fld.of("op", 29, 18), Fld.of("vdst", 9, 6), Fld.of("src2", 5, 0)], "1", True{}), EC.of("VOPC", [Fld.of("encoding", 25, 25), Fld.of("op", 24, 17), Fld.of("src0", 8, 0)], "1", True{})]

def fx_eos() -> List<&2, EO>:
  [EO.of("DPP", [OP.of(0, "V_DOT2ACC_F32_F16")]), EO.of("FLAT", [OP.of(16, "FLAT_LOAD_DWORD"), OP.of(18, "FLAT_LOAD_BYTE"), OP.of(55, "FLAT_ATOMIC_CSUB_U32"), OP.of(84, "S_ADDTID")]), EO.of("GLOBAL", [OP.of(16, "GLOBAL_LOAD_DWORD"), OP.of(55, "GLOBAL_ATOMIC_CSUB_U32"), OP.of(84, "GLOBAL_ADDTID")]), EO.of("HWREG", [OP.of(1, "HWREG_VCCZ"), OP.of(16, "HWREG_SCC")]), EO.of("MSG", [OP.of(2, "MSG_GS_DONE"), OP.of(64, "MSG_NOP")]), EO.of("SCRATCH", [OP.of(17, "SCRATCH_LOAD_BYTE")]), EO.of("SDWA", [OP.of(0, "V_SDWA_F32_16")]), EO.of("SM", [OP.of(0, "S_NOP")]), EO.of("SOP1", [OP.of(21, "S_CNTNCK"), OP.of(80, "S_BARRIER_INIT")]), EO.of("SOPK", [OP.of(22, "S_SUBVECTOR_LOOP_BEGIN")]), EO.of("VFLAT", [OP.of(16, "VFLAT_LOAD_DWORD")]), EO.of("VGLOBAL", [OP.of(16, "VGLOBAL_LOAD_DWORD")]), EO.of("VOP1", [OP.of(0, "V_CNPY"), OP.of(4, "V_CABS_I32"), OP.of(6, "V_ABS_I32"), OP.of(256, "V_ADDTID"), OP.of(512, "V_DOT2ACC_F32_F16")]), EO.of("VOP1_DPP16", [OP.of(0, "V_DOT2ACC_F32_F16")]), EO.of("VOP1_DPP8", [OP.of(0, "V_DOT2ACC_F32_F16")]), EO.of("VOP1_LIT", [OP.of(0, "V_CNPY")]), EO.of("VOP1_SDST", [OP.of(4, "V_CABS_I32")]), EO.of("VOP1_SDWA", [OP.of(0, "V_SDWA_F32_16")]), EO.of("VOP1_SDWA_SDST", [OP.of(0, "V_SDWA_F32_16")]), EO.of("VOP2", [OP.of(0, "V_CNDMASK_B32"), OP.of(1, "V_DOT2ACC_F32_F16"), OP.of(768, "V_LOP3")]), EO.of("VOP3", [OP.of(0, "V_CMP_F32"), OP.of(255, "V_CMP_LT_F32"), OP.of(300, "V_ADD_F32"), OP.of(512, "V_MAD_F32"), OP.of(513, "V_FMA_F32")]), EO.of("VOP3B", [OP.of(0, "V_CMPX_F32")]), EO.of("VOP3P", [OP.of(0, "V_MFMA_F32_16X16X1F32"), OP.of(44, "V_MFMA_LD_SCALE_B32")]), EO.of("VOP3PX2", [OP.of(0, "V_MFMA_LD_SCALE_B32")]), EO.of("VOP3P_MFMA", [OP.of(0, "V_MFMA_F32_16X16X1F32")]), EO.of("VOP3_SDST", [OP.of(255, "V_CMP_LT_F32")]), EO.of("VOPC", [OP.of(64, "V_CMP_EQ_F32"), OP.of(65, "V_CMP_LT_F32"), OP.of(128, "V_CMPX_EQ_F32")]), EO.of("VSCRATCH", [OP.of(17, "VSCRATCH_LOAD_BYTE")])]

def fx_tys() -> List<&2, TY>:
  [TY{"FLAT_ATOMIC_CSUB_U32", "FLAT", [OI{"data", "FLAT", 32, "OPR_DATA"}]}, TY{"FLAT_LOAD_BYTE", "FLAT", [OI{"addr", "FLAT", 64, "OPR_ADDR"}]}, TY{"FLAT_LOAD_DWORD", "FLAT", [OI{"addr", "FLAT", 64, "OPR_ADDR"}, OI{"data", "FLAT", 32, "OPR_DATA"}]}, TY{"GLOBAL_ADDTID", "GLOBAL", [OI{"src0", "GLOBAL", 64, "OPR_SRC"}]}, TY{"GLOBAL_ATOMIC_CSUB_U32", "GLOBAL", [OI{"data", "GLOBAL", 32, "OPR_DATA"}]}, TY{"GLOBAL_LOAD_DWORD", "GLOBAL", [OI{"addr", "GLOBAL", 64, "OPR_ADDR"}, OI{"data", "GLOBAL", 32, "OPR_DATA"}]}, TY{"HWREG_VCCZ", "HWREG", [OI{"op", "None", 8, "OPR_HWREG"}]}, TY{"MSG_GS_DONE", "MSG", [OI{"op", "None", 8, "OPR_SENDMSG_RTN"}]}, TY{"SCRATCH_LOAD_BYTE", "SCRATCH", [OI{"addr", "SCRATCH", 64, "OPR_ADDR"}]}, TY{"S_ADDTID", "FLAT", [OI{"src0", "FLAT", 64, "OPR_SRC"}]}, TY{"S_BARRIER_INIT", "SOP1", [OI{"ssrc0", "SOP1", 8, "OPR_SREG_SRC"}]}, TY{"S_CNTNCK", "SOP1", [OI{"sdst", "None", 0, ""}]}, TY{"S_NOP", "SM", [OI{"sdata", "None", 0, ""}]}, TY{"S_SUBVECTOR_LOOP_BEGIN", "SOPK", [OI{"simm16", "None", 16, ""}]}, TY{"VFLAT_LOAD_DWORD", "VFLAT", [OI{"data", "VFLAT", 32, "OPR_DATA"}]}, TY{"VGLOBAL_LOAD_DWORD", "VGLOBAL", [OI{"data", "VGLOBAL", 32, "OPR_DATA"}]}, TY{"VSCRATCH_LOAD_BYTE", "VSCRATCH", [OI{"addr", "VSCRATCH", 64, "OPR_ADDR"}]}, TY{"V_ABS_I32", "VOP1", [OI{"vdst", "VOP1", 8, "OPR_VGPR"}]}, TY{"V_ADDTID", "VOP1", [OI{"src0", "VOP1", 32, "OPR_SRC"}]}, TY{"V_ADD_F32", "VOP3", [OI{"vdst", "VOP3", 8, "OPR_VGPR"}]}, TY{"V_CABS_I32", "VOP1", [OI{"src0", "VOP1", 32, "OPR_SRC_ABS"}, OI{"vdst", "VOP1", 8, "OPR_SREG"}]}, TY{"V_CMPX_EQ_F32", "VOPC", [OI{"src0", "VOPC", 32, "OPR_SRC"}]}, TY{"V_CMPX_F32", "VOP3B", [OI{"src0", "VOP3B", 32, "OPR_SRC"}]}, TY{"V_CMP_EQ_F32", "VOPC", [OI{"src0", "VOPC", 32, "OPR_SRC"}]}, TY{"V_CMP_F32", "VOP3", [OI{"src0", "VOP3", 32, "OPR_SRC"}]}, TY{"V_CMP_LT_F32", "VOP3", [OI{"src0", "VOP3", 32, "OPR_SRC_ABS"}]}, TY{"V_CMP_LT_F32", "VOPC", [OI{"src0", "VOPC", 32, "OPR_SRC_NEG"}]}, TY{"V_CNDMASK_B32", "VOP2", [OI{"vdst", "VOP2", 8, "OPR_VGPR"}]}, TY{"V_CNPY", "VOP1", [OI{"src0", "VOP1", 32, "OPR_SRC_NTZ"}, OI{"vdst", "VOP1", 8, "OPR_VGPR"}]}, TY{"V_DOT2ACC_F32_F16", "DPP", [OI{"vdst", "DPP", 8, "OPR_VGPR"}]}, TY{"V_DOT2ACC_F32_F16", "VOP1", [OI{"vdst", "VOP1", 8, "OPR_SREG"}]}, TY{"V_DOT2ACC_F32_F16", "VOP2", [OI{"vdst", "VOP2", 8, "OPR_SREG"}]}, TY{"V_FMA_F32", "VOP3", [OI{"vdst", "VOP3", 8, "OPR_VGPR"}]}, TY{"V_LOP3", "VOP2", [OI{"vdst", "VOP2", 8, "OPR_VGPR"}]}, TY{"V_MAD_F32", "VOP3", [OI{"vdst", "VOP3", 8, "OPR_VGPR"}]}, TY{"V_MFMA_F32_16X16X1F32", "VOP3P", [OI{"src0", "VOP3P", 32, "OPR_SRC_ABS"}, OI{"vdst", "VOP3P", 4, "OPR_VGPR"}]}, TY{"V_MFMA_LD_SCALE_B32", "VOP3P", [OI{"src0", "VOP3P", 32, "OPR_SRC"}]}, TY{"V_MFMA_LD_SCALE_B32", "VOP3PX2", [OI{"src0", "VOP3PX2", 32, "OPR_SRC"}]}, TY{"V_MFMA_LD_SCALE_B32", "VOP3P_MFMA", [OI{"src0", "VOP3P_MFMA", 32, "OPR_SRC"}]}, TY{"V_SDWA_F32_16", "SDWA", [OI{"src0", "SDWA", 32, "OPR_SRC"}]}]

def fx_fbs() -> List<&2, FB>:
  [FB{"BF16", 16}, FB{"FLOAT", 32}, FB{"FP16", 16}, FB{"NONE", 0}, FB{"UINT", 32}, FB{"VOP1", 32}, FB{"VOP1PP", 32}, FB{"VOP2", 32}, FB{"VOP3", 64}, FB{"VOP3P", 64}, FB{"VOPC", 32}]

def fx_ots() -> List<&2, String>:
  ["OPR_ADDR", "OPR_DATA", "OPR_HWREG", "OPR_SENDMSG_RTN", "OPR_SRC", "OPR_SRC_ABS", "OPR_SRC_NEG", "OPR_SRC_NTZ", "OPR_SREG", "OPR_SREG_SRC", "OPR_VGPR"]

# `suffix_only_ops`, the {suffix: {fmt: {opcode}}} table.  A FOURTH nested
# shape, because a dict of dicts of sets has no Bend spelling and the class
# folds need it three different ways (restrict the base class, widen the
# variant, choose the helper's class).

def fx_ssx() -> List<&2, SS>:
  [SS{"_LIT", [SG{"VOP1", [0]}]}, SS{"_MFMA", [SG{"VOP3P", [44]}]}]

# `pcode`, `{(name, opcode): pseudocode}`.  `extract_pcode` is WALL 5 (bend
# 2.0.34 has F32 and no F64), so the FIXTURE is the dict the oracle read
# back out of `G.extract_pcode`, decoded from the same `json.dumps` text.

def fx_ps() -> List<&2, PK>:
  [PK{"V_ADDTID", 256, "V_ADDTID()\nT0 = EXEC;"}, PK{"V_ADD_F32", 300, "V_ADD_F32(vdst, src0)\nÎ"}, PK{"V_CNPY", 0, "V_CNPY(dst, src0)\n{\ndst = src0;\n} // end"}]
# THE EMITTER ROWS ARE ONE ROW PER EMITTED FILE, the file JOINED by newline.
# A count row would be identical for a dropped member, a dropped alias, a
# swapped `default=NULL` and a reordered field; a string diff is not.  This is
# the renderer convention 2 applied to a GENERATOR: the answer is the file.
#
# AND ESCAPED TO ONE LINE, AND THE ESCAPE MUST BE PER LINE.  `gl` prints a
# WHOLE GENERATED FILE and the gate's row parser splits lane output on
# newlines, so before this one row became 335 fragments whose NAMES are the
# first token before an `=` inside the generated Python (`FLAT_LOAD_DWORD`,
# `encoding`, `saddr`, ...).  Measured 2026-10-03: 233 row names for 91 rows,
# 84 shared with the oracle, the other 149 naming text the oracle names
# `tag | line`.
#
# `cstyle.bend:1760`'s `esc_row` is `String.join(String.split(s, '\n'), "\\n")`
# and NEITHER HALF OF IT RUNS HERE, for two separate reasons, both measured.
#
# 1. `String.split` is one interpreter frame per CHARACTER
#    (references/bend/bend2/base.bend:2009) and the biggest file is 16,815
#    characters.  A probe survives 4,000 and dies at 8,000 with "the machine
#    stack overflowed".
# 2. `String.join` is O(total length) in stack depth, not O(line count):
#    `base.bend:1980` builds `String.append(h, ...)` where `h` is the prefix
#    SO FAR, so the last append walks all 16,815 of them.
#
# Measured on the real file: 12 runs of `String.join(got, "\\n")` gave 5
# successes.  THE ORIGINAL, WITH NO ESCAPE AT ALL AND A ONE-CHARACTER
# SEPARATOR, GAVE 5 OF 12 TOO -- this cliff predates the change and any lane
# on this port has been BROKEN about half the time for a reason that has
# nothing to do with rows.  A gate that fails 7 runs in 10 is not a gate.
#
# So: `esc.go` PREPENDS `[line, "\\n"]` per element, which is O(2) because
# `List.append` recurses over its FIRST argument (base.bend:822), and
# `String.concat` walks only the element it is handed, not a growing prefix
# (base.bend:1969).  177 lines in, depth is about 450 instead of 16,815.
# Probe: 6 of 6 runs, length 17,169 = 177 x (95 + 2).
#
# `write_*` RETURNS the file as a `List<&2, String>` (`write_enum`
# generate.py:276-282, `write_ins` :457, `write_operands` :469, `write_pcode`
# :494), so the per-line escape costs nothing -- there is no split to pay for.
# The TRAILING `\\n` is the shape: CPython writes `"\\n".join(lines)` with no
# final newline, so the escaped row is that text plus one, and ga-oracle.py's
# `R()` adds the same one.
#
# THE ONE BLIND SPOT, measured not guessed: `\` `n` is not injective against a
# real newline, and TWO of these files hold a literal `\` `n` inside a pcode
# body -- `write_pcode` emits `{code!r}` (generate.py:497), so CPython's own
# output has them.  A port that turned one into a REAL newline is invisible
# here; `.agents/slop/ga_gate.py` diffs the RAW text with a DOTALL parser and
# sees it, so the two lanes cover each other.
def esc.go(ls_: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ls_:
    case Nil{}: acc
    case +h <> t: esc.go(t, List.append(&2, String, [h, "\\n"], acc))

def esc_row(got: List<&2, String>) -> String: String.concat(esc.go(got, Nil{}))

def gl(nm: String, got: List<&2, String>, want: String) -> IO(Unit):
  g(nm, esc_row(got), want)

def main() -> IO(Unit):
  do IO<Unit>:
  g("strip_enc ENC_VOP1", strip_enc("ENC_VOP1"), "VOP1")
  g("strip_enc ENC_VOP2", strip_enc("ENC_VOP2"), "VOP2")
  g("strip_enc ENC_VOP3", strip_enc("ENC_VOP3"), "VOP3")
  g("strip_enc ENC_VOP1_INST_LITERAL", strip_enc("ENC_VOP1_INST_LITERAL"), "VOP1_LIT")
  g("strip_enc ENC_VOP1_VOP_DPP", strip_enc("ENC_VOP1_VOP_DPP"), "VOP1_DPP16")
  g("strip_enc ENC_VOP1_VOP_DPP8", strip_enc("ENC_VOP1_VOP_DPP8"), "VOP1_DPP8")
  g("strip_enc ENC_VOP1_VOP_SDWA", strip_enc("ENC_VOP1_VOP_SDWA"), "VOP1_SDWA")
  g("strip_enc ENC_VOP1_VOP_SDWA_SDST_ENC", strip_enc("ENC_VOP1_VOP_SDWA_SDST_ENC"), "VOP1_SDWA_SDST")
  g("strip_enc ENC_VOP3P_MFMA", strip_enc("ENC_VOP3P_MFMA"), "VOP3P_MFMA")
  g("strip_enc ENC_SOP1_NSA1", strip_enc("ENC_SOP1_NSA1"), "SOP1")
  g("strip_enc ENC_SOP1_NSA1_VOP_DPP8", strip_enc("ENC_SOP1_NSA1_VOP_DPP8"), "SOP1_DPP8")
  g("strip_enc ENC_VOP3_SDST_ENC", strip_enc("ENC_VOP3_SDST_ENC"), "VOP3_SDST_ENC")
  g("strip_enc ENC_VOPDXY", strip_enc("ENC_VOPDXY"), "VOPDXY")
  g("strip_enc ENC_VOPDXY_LIT", strip_enc("ENC_VOPDXY_LIT"), "VOPDXY_LIT")
  g("strip_enc ENC_VDS", strip_enc("ENC_VDS"), "VDS")
  g("strip_enc ENC_MIMG_MSG_RTN", strip_enc("ENC_MIMG_MSG_RTN"), "MIMG_MSG_RTN")
  g("strip_enc VOP3_SDST_ENC_DPP16", strip_enc("VOP3_SDST_ENC_DPP16"), "VOP3_SDST_ENC_DPP16")
  g("strip_enc ENC_VOP1PP", strip_enc("ENC_VOP1PP"), "VOP1PP")
  g("norm_field opsel_hi_2", norm_field("opsel_hi_2"), "opsel_hi2")
  g("norm_field op_sel_hi_2", norm_field("op_sel_hi_2"), "opsel_hi2")
  g("norm_field op_sel", norm_field("op_sel"), "opsel")
  g("norm_field bound_ctrl", norm_field("bound_ctrl"), "bc")
  g("norm_field tgt", norm_field("tgt"), "target")
  g("norm_field row_en", norm_field("row_en"), "row")
  g("norm_field unorm", norm_field("unorm"), "unrm")
  g("norm_field clamp", norm_field("clamp"), "clmp")
  g("norm_field wait_exp", norm_field("wait_exp"), "waitexp")
  g("norm_field simm32", norm_field("simm32"), "literal")
  g("norm_field dpp_ctrl", norm_field("dpp_ctrl"), "dpp")
  g("norm_field acc_cd", norm_field("acc_cd"), "acc_cd")
  g("norm_field acc", norm_field("acc"), "acc")
  g("norm_field dst_sel", norm_field("dst_sel"), "dst_sel")
  g("norm_field dst_unused", norm_field("dst_unused"), "dst_unused")
  g("norm_field src0_sel", norm_field("src0_sel"), "src0_sel")
  g("norm_field src1_sel", norm_field("src1_sel"), "src1_sel")
  g("norm_field encoding", norm_field("encoding"), "encoding")
  g("norm_field op", norm_field("op"), "op")
  g("norm_field vdst", norm_field("vdst"), "vdst")
  g("norm_field vdsty", norm_field("vdsty"), "vdsty")
  g("norm_field sbase", norm_field("sbase"), "sbase")
  g("norm_field srsrc", norm_field("srsrc"), "srsrc")
  g("norm_field ssamp", norm_field("ssamp"), "ssamp")
  g("norm_field sdst", norm_field("sdst"), "sdst")
  g("norm_field sdata", norm_field("sdata"), "sdata")
  g("norm_field soffset", norm_field("soffset"), "soffset")
  g("norm_field saddr", norm_field("saddr"), "saddr")
  g("norm_field ssrc0", norm_field("ssrc0"), "ssrc0")
  g("norm_field ssrc1", norm_field("ssrc1"), "ssrc1")
  g("norm_field src0", norm_field("src0"), "src0")
  g("norm_field src1", norm_field("src1"), "src1")
  g("norm_field offset", norm_field("offset"), "offset")
  g("norm_field src2", norm_field("src2"), "src2")
  g("norm_field src3", norm_field("src3"), "src3")
  g("norm_field opx", norm_field("opx"), "opx")
  g("norm_field opy", norm_field("opy"), "opy")
  g("norm_field vdstx", norm_field("vdstx"), "vdstx")
  g("norm_field vdata", norm_field("vdata"), "vdata")
  g("norm_field addr", norm_field("addr"), "addr")
  g("norm_field vaddr", norm_field("vaddr"), "vaddr")
  g("norm_field data", norm_field("data"), "data")
  g("norm_field src9", norm_field("src9"), "src9")
  g("norm_field ssrc8", norm_field("ssrc8"), "ssrc8")
  g("norm_field srcs", norm_field("srcs"), "srcs")
  g("norm_field opsel_hi", norm_field("opsel_hi"), "opsel_hi")
  g("norm_field opsel_hi2", norm_field("opsel_hi2"), "opsel_hi2")
  g("norm_field neg_hi", norm_field("neg_hi"), "neg_hi")
  g("norm_field waitex", norm_field("waitex"), "waitex")
  g("norm_field waitexpp", norm_field("waitexpp"), "waitexpp")
  g("map_flat FLAT_GLBL/FLAT_LOAD_DWORD", map_flat("FLAT_GLBL", "FLAT_LOAD_DWORD"), "GLOBAL")
  g("map_flat FLAT_GLOBAL/GLOBAL_LOAD_DWORD", map_flat("FLAT_GLOBAL", "GLOBAL_LOAD_DWORD"), "GLOBAL")
  g("map_flat FLAT_SCRATCH/SCRATCH_LOAD_DWORD", map_flat("FLAT_SCRATCH", "SCRATCH_LOAD_DWORD"), "SCRATCH")
  g("map_flat FLAT/FLAT_LOAD_DWORD", map_flat("FLAT", "FLAT_LOAD_DWORD"), "FLAT")
  g("map_flat VFLAT/FLAT_LOAD_DWORD", map_flat("VFLAT", "FLAT_LOAD_DWORD"), "VFLAT")
  g("map_flat VGLOBAL/GLOBAL_LOAD_DWORD", map_flat("VGLOBAL", "GLOBAL_LOAD_DWORD"), "VGLOBAL")
  g("map_flat VSCRATCH/SCRATCH_LOAD_DWORD", map_flat("VSCRATCH", "SCRATCH_LOAD_DWORD"), "VSCRATCH")
  g("map_flat FLAT/GLOBAL_ATOMIC_ADD", map_flat("FLAT", "GLOBAL_ATOMIC_ADD"), "GLOBAL")
  g("map_flat FLAT/SCRATCH_STORE_DWORD", map_flat("FLAT", "SCRATCH_STORE_DWORD"), "SCRATCH")
  g("map_flat VFLAT/VGLOBAL_ATOMIC_ADD", map_flat("VFLAT", "VGLOBAL_ATOMIC_ADD"), "VFLAT")
  g("map_flat VFLAT/VSCRATCH_STORE_DWORD", map_flat("VFLAT", "VSCRATCH_STORE_DWORD"), "VFLAT")
  g("map_flat VFLAT/VFLAT_LOAD_DWORD", map_flat("VFLAT", "VFLAT_LOAD_DWORD"), "VFLAT")
  g("map_flat FLAT/S_ADDTID", map_flat("FLAT", "S_ADDTID"), "FLAT")
  g("map_flat VGLOBAL/GLOBAL_ADDTID", map_flat("VGLOBAL", "GLOBAL_ADDTID"), "VGLOBAL")
  g("map_flat VOP1/V_CNPY", map_flat("VOP1", "V_CNPY"), "VOP1")
  g("map_flat VOP3/V_CMP_LT_F32", map_flat("VOP3", "V_CMP_LT_F32"), "VOP3")
  IO.print("")
  gl("enum rdna3", write_enum(fx_eos()), "# autogenerated from AMD ISA XML - do not edit\\nfrom tinygrad.runtime.autogen.amd.common import ReprEnum, Fmt, FMT_BITS, OpType  # noqa: F401\\n\\nclass DPPOp(ReprEnum):\\n  V_DOT2ACC_F32_F16 = 0\\n\\nclass FLATOp(ReprEnum):\\n  FLAT_LOAD_DWORD = 16\\n  FLAT_LOAD_BYTE = 18\\n  FLAT_ATOMIC_CSUB_U32 = 55\\n  S_ADDTID = 84\\n\\nclass GLOBALOp(ReprEnum):\\n  GLOBAL_LOAD_DWORD = 16\\n  GLOBAL_ATOMIC_CSUB_U32 = 55\\n  GLOBAL_ADDTID = 84\\n\\nclass HWREG(ReprEnum):\\n  HWREG_VCCZ = 1\\n  HWREG_SCC = 16\\n\\nclass MSG(ReprEnum):\\n  MSG_GS_DONE = 2\\n  MSG_NOP = 64\\n\\nclass SCRATCHOp(ReprEnum):\\n  SCRATCH_LOAD_BYTE = 17\\n\\nclass SDWAOp(ReprEnum):\\n  V_SDWA_F32_16 = 0\\n\\nclass SMOp(ReprEnum):\\n  S_NOP = 0\\n\\nclass SOP1Op(ReprEnum):\\n  S_CNTNCK = 21\\n  S_BARRIER_INIT = 80\\n\\nclass SOPKOp(ReprEnum):\\n  S_SUBVECTOR_LOOP_BEGIN = 22\\n\\nclass VFLATOp(ReprEnum):\\n  VFLAT_LOAD_DWORD = 16\\n\\nclass VGLOBALOp(ReprEnum):\\n  VGLOBAL_LOAD_DWORD = 16\\n\\nclass VOP1Op(ReprEnum):\\n  V_CNPY_E32 = 0\\n  V_CABS_I32_E32 = 4\\n  V_ABS_I32_E32 = 6\\n  V_ADDTID_E32 = 256\\n  V_DOT2ACC_F32_F16_E32 = 512\\n  V_CNPY = V_CNPY_E32\\n  V_CABS_I32 = V_CABS_I32_E32\\n  V_ABS_I32 = V_ABS_I32_E32\\n  V_ADDTID = V_ADDTID_E32\\n  V_DOT2ACC_F32_F16 = V_DOT2ACC_F32_F16_E32\\n\\nclass VOP1_DPP16Op(ReprEnum):\\n  V_DOT2ACC_F32_F16 = 0\\n\\nclass VOP1_DPP8Op(ReprEnum):\\n  V_DOT2ACC_F32_F16 = 0\\n\\nclass VOP1_LITOp(ReprEnum):\\n  V_CNPY = 0\\n\\nclass VOP1_SDSTOp(ReprEnum):\\n  V_CABS_I32 = 4\\n\\nclass VOP1_SDWAOp(ReprEnum):\\n  V_SDWA_F32_16 = 0\\n\\nclass VOP1_SDWA_SDSTOp(ReprEnum):\\n  V_SDWA_F32_16 = 0\\n\\nclass VOP2Op(ReprEnum):\\n  V_CNDMASK_B32_E32 = 0\\n  V_DOT2ACC_F32_F16_E32 = 1\\n  V_LOP3_E32 = 768\\n  V_CNDMASK_B32 = V_CNDMASK_B32_E32\\n  V_DOT2ACC_F32_F16 = V_DOT2ACC_F32_F16_E32\\n  V_LOP3 = V_LOP3_E32\\n\\nclass VOP3Op(ReprEnum):\\n  V_CMP_F32_E64 = 0\\n  V_CMP_LT_F32_E64 = 255\\n  V_ADD_F32_E64 = 300\\n  V_MAD_F32 = 512\\n  V_FMA_F32 = 513\\n  V_CMP_F32 = V_CMP_F32_E64\\n  V_CMP_LT_F32 = V_CMP_LT_F32_E64\\n  V_ADD_F32 = V_ADD_F32_E64\\n\\nclass VOP3BOp(ReprEnum):\\n  V_CMPX_F32 = 0\\n\\nclass VOP3POp(ReprEnum):\\n  V_MFMA_F32_16X16X1F32 = 0\\n  V_MFMA_LD_SCALE_B32 = 44\\n\\nclass VOP3PX2Op(ReprEnum):\\n  V_MFMA_LD_SCALE_B32 = 0\\n\\nclass VOP3P_MFMAOp(ReprEnum):\\n  V_MFMA_F32_16X16X1F32 = 0\\n\\nclass VOP3_SDSTOp(ReprEnum):\\n  V_CMP_LT_F32 = 255\\n\\nclass VOPCOp(ReprEnum):\\n  V_CMP_EQ_F32_E32 = 64\\n  V_CMP_LT_F32_E32 = 65\\n  V_CMPX_EQ_F32_E32 = 128\\n  V_CMP_EQ_F32 = V_CMP_EQ_F32_E32\\n  V_CMP_LT_F32 = V_CMP_LT_F32_E32\\n  V_CMPX_EQ_F32 = V_CMPX_EQ_F32_E32\\n\\nclass VSCRATCHOp(ReprEnum):\\n  VSCRATCH_LOAD_BYTE = 17\\n\\n")
  gl("operands rdna3", write_operands(fx_tys(), fx_eos(), "rdna3"), "# autogenerated from AMD ISA XML - do not edit\\nfrom tinygrad.runtime.autogen.amd.common import Fmt, OpType\\nfrom tinygrad.runtime.autogen.amd.rdna3.enum import DPPOp, FLATOp, GLOBALOp, HWREGOp, MSGOp, SCRATCHOp, SDWAOp, SMOp, SOP1Op, SOPKOp, VFLATOp, VGLOBALOp, VOP1Op, VOP2Op, VOP3BOp, VOP3Op, VOP3POp, VOP3PX2Op, VOPCOp, VSCRATCHOp\\n\\n# instruction operand info: {Op: {field: (Fmt, size_bits, OpType)}}\\nOPERANDS = {\\n  FLATOp.FLAT_ATOMIC_CSUB_U32: {\"data\": (Fmt.FLAT, 32, OpType.OPR_DATA)},\\n  FLATOp.FLAT_LOAD_BYTE: {\"addr\": (Fmt.FLAT, 64, OpType.OPR_ADDR)},\\n  FLATOp.FLAT_LOAD_DWORD: {\"addr\": (Fmt.FLAT, 64, OpType.OPR_ADDR), \"data\": (Fmt.FLAT, 32, OpType.OPR_DATA)},\\n  GLOBALOp.GLOBAL_ADDTID: {\"src0\": (Fmt.GLOBAL, 64, OpType.OPR_SRC)},\\n  GLOBALOp.GLOBAL_ATOMIC_CSUB_U32: {\"data\": (Fmt.GLOBAL, 32, OpType.OPR_DATA)},\\n  GLOBALOp.GLOBAL_LOAD_DWORD: {\"addr\": (Fmt.GLOBAL, 64, OpType.OPR_ADDR), \"data\": (Fmt.GLOBAL, 32, OpType.OPR_DATA)},\\n  HWREGOp.HWREG_VCCZ: {\"op\": (Fmt.None, 8, OpType.OPR_HWREG)},\\n  MSGOp.MSG_GS_DONE: {\"op\": (Fmt.None, 8, OpType.OPR_SENDMSG_RTN)},\\n  SCRATCHOp.SCRATCH_LOAD_BYTE: {\"addr\": (Fmt.SCRATCH, 64, OpType.OPR_ADDR)},\\n  FLATOp.S_ADDTID: {\"src0\": (Fmt.FLAT, 64, OpType.OPR_SRC)},\\n  SOP1Op.S_BARRIER_INIT: {\"ssrc0\": (Fmt.SOP1, 8, OpType.OPR_SREG_SRC)},\\n  SOP1Op.S_CNTNCK: {\"sdst\": (Fmt.None, 0, None)},\\n  SMOp.S_NOP: {\"sdata\": (Fmt.None, 0, None)},\\n  SOPKOp.S_SUBVECTOR_LOOP_BEGIN: {\"simm16\": (Fmt.None, 16, None)},\\n  VFLATOp.VFLAT_LOAD_DWORD: {\"data\": (Fmt.VFLAT, 32, OpType.OPR_DATA)},\\n  VGLOBALOp.VGLOBAL_LOAD_DWORD: {\"data\": (Fmt.VGLOBAL, 32, OpType.OPR_DATA)},\\n  VSCRATCHOp.VSCRATCH_LOAD_BYTE: {\"addr\": (Fmt.VSCRATCH, 64, OpType.OPR_ADDR)},\\n  VOP1Op.V_ABS_I32: {\"vdst\": (Fmt.VOP1, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_ADDTID: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_ADD_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_CABS_I32: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC_ABS), \"vdst\": (Fmt.VOP1, 8, OpType.OPR_SREG)},\\n  VOPCOp.V_CMPX_EQ_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC)},\\n  VOP3BOp.V_CMPX_F32: {\"src0\": (Fmt.VOP3B, 32, OpType.OPR_SRC)},\\n  VOPCOp.V_CMP_EQ_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_CMP_F32: {\"src0\": (Fmt.VOP3, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_CMP_LT_F32: {\"src0\": (Fmt.VOP3, 32, OpType.OPR_SRC_ABS)},\\n  VOPCOp.V_CMP_LT_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC_NEG)},\\n  VOP2Op.V_CNDMASK_B32: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_CNPY: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC_NTZ), \"vdst\": (Fmt.VOP1, 8, OpType.OPR_VGPR)},\\n  DPPOp.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.DPP, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.VOP1, 8, OpType.OPR_SREG)},\\n  VOP2Op.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_SREG)},\\n  VOP3Op.V_FMA_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP2Op.V_LOP3: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_VGPR)},\\n  VOP3Op.V_MAD_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP3POp.V_MFMA_F32_16X16X1F32: {\"src0\": (Fmt.VOP3P, 32, OpType.OPR_SRC_ABS), \"vdst\": (Fmt.VOP3P, 4, OpType.OPR_VGPR)},\\n  VOP3POp.V_MFMA_LD_SCALE_B32: {\"src0\": (Fmt.VOP3P, 32, OpType.OPR_SRC)},\\n  VOP3PX2Op.V_MFMA_LD_SCALE_B32: {\"src0\": (Fmt.VOP3PX2, 32, OpType.OPR_SRC)},\\n  SDWAOp.V_SDWA_F32_16: {\"src0\": (Fmt.SDWA, 32, OpType.OPR_SRC)},\\n}\\n")
  gl("operands cdna", write_operands(fx_tys(), fx_eos(), "cdna"), "# autogenerated from AMD ISA XML - do not edit\\nfrom tinygrad.runtime.autogen.amd.common import Fmt, OpType\\nfrom tinygrad.runtime.autogen.amd.cdna.enum import DPPOp, FLATOp, GLOBALOp, HWREGOp, MSGOp, SCRATCHOp, SDWAOp, SMOp, SOP1Op, SOPKOp, VFLATOp, VGLOBALOp, VOP1Op, VOP2Op, VOP3BOp, VOP3Op, VOP3POp, VOP3PX2Op, VOPCOp, VSCRATCHOp\\n\\n# instruction operand info: {Op: {field: (Fmt, size_bits, OpType)}}\\nOPERANDS = {\\n  FLATOp.FLAT_ATOMIC_CSUB_U32: {\"data\": (Fmt.FLAT, 32, OpType.OPR_DATA)},\\n  FLATOp.FLAT_LOAD_BYTE: {\"addr\": (Fmt.FLAT, 64, OpType.OPR_ADDR)},\\n  FLATOp.FLAT_LOAD_DWORD: {\"addr\": (Fmt.FLAT, 64, OpType.OPR_ADDR), \"data\": (Fmt.FLAT, 32, OpType.OPR_DATA)},\\n  GLOBALOp.GLOBAL_ADDTID: {\"src0\": (Fmt.GLOBAL, 64, OpType.OPR_SRC)},\\n  GLOBALOp.GLOBAL_ATOMIC_CSUB_U32: {\"data\": (Fmt.GLOBAL, 32, OpType.OPR_DATA)},\\n  GLOBALOp.GLOBAL_LOAD_DWORD: {\"addr\": (Fmt.GLOBAL, 64, OpType.OPR_ADDR), \"data\": (Fmt.GLOBAL, 32, OpType.OPR_DATA)},\\n  HWREGOp.HWREG_VCCZ: {\"op\": (Fmt.None, 8, OpType.OPR_HWREG)},\\n  MSGOp.MSG_GS_DONE: {\"op\": (Fmt.None, 8, OpType.OPR_SENDMSG_RTN)},\\n  SCRATCHOp.SCRATCH_LOAD_BYTE: {\"addr\": (Fmt.SCRATCH, 64, OpType.OPR_ADDR)},\\n  FLATOp.S_ADDTID: {\"src0\": (Fmt.FLAT, 64, OpType.OPR_SRC)},\\n  SOP1Op.S_BARRIER_INIT: {\"ssrc0\": (Fmt.SOP1, 8, OpType.OPR_SREG_SRC)},\\n  SOP1Op.S_CNTNCK: {\"sdst\": (Fmt.None, 0, None)},\\n  SMOp.S_NOP: {\"sdata\": (Fmt.None, 0, None)},\\n  SOPKOp.S_SUBVECTOR_LOOP_BEGIN: {\"simm16\": (Fmt.None, 16, None)},\\n  VFLATOp.VFLAT_LOAD_DWORD: {\"data\": (Fmt.VFLAT, 32, OpType.OPR_DATA)},\\n  VGLOBALOp.VGLOBAL_LOAD_DWORD: {\"data\": (Fmt.VGLOBAL, 32, OpType.OPR_DATA)},\\n  VSCRATCHOp.VSCRATCH_LOAD_BYTE: {\"addr\": (Fmt.VSCRATCH, 64, OpType.OPR_ADDR)},\\n  VOP1Op.V_ABS_I32: {\"vdst\": (Fmt.VOP1, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_ADDTID: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_ADD_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_CABS_I32: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC_ABS), \"vdst\": (Fmt.VOP1, 8, OpType.OPR_SREG)},\\n  VOPCOp.V_CMPX_EQ_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC)},\\n  VOP3BOp.V_CMPX_F32: {\"src0\": (Fmt.VOP3B, 32, OpType.OPR_SRC)},\\n  VOPCOp.V_CMP_EQ_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_CMP_F32: {\"src0\": (Fmt.VOP3, 32, OpType.OPR_SRC)},\\n  VOP3Op.V_CMP_LT_F32: {\"src0\": (Fmt.VOP3, 32, OpType.OPR_SRC_ABS)},\\n  VOPCOp.V_CMP_LT_F32: {\"src0\": (Fmt.VOPC, 32, OpType.OPR_SRC_NEG)},\\n  VOP2Op.V_CNDMASK_B32: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_CNPY: {\"src0\": (Fmt.VOP1, 32, OpType.OPR_SRC_NTZ), \"vdst\": (Fmt.VOP1, 8, OpType.OPR_VGPR)},\\n  DPPOp.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.DPP, 8, OpType.OPR_VGPR)},\\n  VOP1Op.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.VOP1, 8, OpType.OPR_SREG)},\\n  VOP2Op.V_DOT2ACC_F32_F16: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_SREG)},\\n  VOP3Op.V_FMA_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP2Op.V_LOP3: {\"vdst\": (Fmt.VOP2, 8, OpType.OPR_VGPR)},\\n  VOP3Op.V_MAD_F32: {\"vdst\": (Fmt.VOP3, 8, OpType.OPR_VGPR)},\\n  VOP3POp.V_MFMA_F32_16X16X1F32: {\"src0\": (Fmt.VOP3P, 32, OpType.OPR_SRC_ABS), \"vdst\": (Fmt.VOP3P, 4, OpType.OPR_VGPR)},\\n  VOP3POp.V_MFMA_LD_SCALE_B32: {\"src0\": (Fmt.VOP3P, 32, OpType.OPR_SRC)},\\n  VOP3PX2Op.V_MFMA_LD_SCALE_B32: {\"src0\": (Fmt.VOP3PX2, 32, OpType.OPR_SRC)},\\n  SDWAOp.V_SDWA_F32_16: {\"src0\": (Fmt.SDWA, 32, OpType.OPR_SRC)},\\n}\\n")
  gl("ins rdna3", write_ins(fx_encs(), fx_eos(), fx_ssx(), fx_tys(), "rdna3"), "# autogenerated from AMD ISA XML - do not edit\\n# ruff: noqa: E501,F401\\nfrom tinygrad.renderer.amd.dsl import BitField, DPP, DPP16, EXEC, EXECZ, EXEC_HI, EXEC_LO, EnumBitField, FixedBitField, INV_2PI, Inst, LIT, M0, NULL, OFF, SBaseField, SCC, SDWA, SGPRField, SRC_LDS_DIRECT, SRsrcField, SSrcField, SrcField, VCC, VCCZ, VCC_HI, VCC_LO, VDSTYField, VGPRField, s, src, ttmp, v\\nfrom tinygrad.runtime.autogen.amd.rdna3.enum import DPPOp, FLATOp, GLOBALOp, SCRATCHOp, SDWAOp, SMOp, SOP1Op, SOPKOp, VFLATOp, VGLOBALOp, VOP1Op, VOP1_DPP16Op, VOP1_DPP8Op, VOP1_LITOp, VOP1_SDSTOp, VOP1_SDWAOp, VOP1_SDWA_SDSTOp, VOP2Op, VOP3BOp, VOP3Op, VOP3POp, VOP3PX2Op, VOP3P_MFMAOp, VOP3_SDSTOp, VOPCOp, VSCRATCHOp, HWREG, MSG\\nimport functools\\n\\nclass FLAT(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, FLATOp, {FLATOp.FLAT_LOAD_DWORD, FLATOp.FLAT_LOAD_BYTE, FLATOp.FLAT_ATOMIC_CSUB_U32, FLATOp.S_ADDTID})\\n  offset = BitField(14, 0)\\n  seg = FixedBitField(17, 15, 0)\\n\\nclass GLOBAL(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, GLOBALOp, {GLOBALOp.GLOBAL_LOAD_DWORD, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32, GLOBALOp.GLOBAL_ADDTID})\\n  offset = BitField(12, 0)\\n  seg = FixedBitField(17, 15, 2)\\n\\nclass SCRATCH(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, SCRATCHOp, {SCRATCHOp.SCRATCH_LOAD_BYTE})\\n  offset = BitField(12, 0)\\n  seg = FixedBitField(17, 15, 1)\\n\\nclass GLOBAL(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, GLOBALOp, {GLOBALOp.GLOBAL_LOAD_DWORD, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32, GLOBALOp.GLOBAL_ADDTID})\\n  offset = BitField(12, 0)\\n\\nclass HWREG(Inst):\\n  encoding = FixedBitField(16, 10, 0b0)\\n  op = EnumBitField(9, 0, HWREGOp, {HWREGOp.HWREG_VCCZ, HWREGOp.HWREG_SCC})\\n\\nclass MSG(Inst):\\n  encoding = FixedBitField(17, 12, 0b0)\\n  op = EnumBitField(11, 0, MSGOp, {MSGOp.MSG_GS_DONE, MSGOp.MSG_NOP})\\n\\nclass SCRATCH(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, SCRATCHOp, {SCRATCHOp.SCRATCH_LOAD_BYTE})\\n  offset = BitField(12, 0)\\n\\nclass SM(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(17, 16, SMOp, {SMOp.S_NOP})\\n  sdst = SGPRField(24, 18)\\n  sdata = SGPRField(12, 6)\\n  saddr = SGPRField(31, 25, default=NULL)\\n\\nclass SOP1(Inst):\\n  encoding = FixedBitField(23, 23, 0b1)\\n  op = EnumBitField(22, 16, SOP1Op, {SOP1Op.S_CNTNCK, SOP1Op.S_BARRIER_INIT})\\n  sdst = SGPRField(6, 0)\\n  ssrc0 = SSrcField(15, 8)\\n  saddr = SSrcField(31, 24, default=NULL)\\n  soffset = SGPRField(7, 1, default=NULL)\\n\\nclass SOPK(Inst):\\n  encoding = FixedBitField(27, 27, 0b1)\\n  op = EnumBitField(23, 16, SOPKOp, {SOPKOp.S_SUBVECTOR_LOOP_BEGIN})\\n  sbase = SBaseField(31, 26)\\n  srsrc = SRsrcField(15, 11)\\n  ssamp = SRsrcField(10, 6)\\n  simm16 = BitField(5, 0)\\n\\nclass VOP1(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_ABS_I32, VOP1Op.V_ADDTID})\\n  vdst = VGPRField(16, 9)\\n  src0 = BitField(6, 0)\\n  clmp = BitField(8, 7)\\n\\nclass VOP2(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(25, 17, VOP2Op, {VOP2Op.V_CNDMASK_B32, VOP2Op.V_LOP3})\\n  vdst = VGPRField(16, 9)\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(22, 16, VOP3Op, {VOP3Op.V_CMP_F32, VOP3Op.V_CMP_LT_F32, VOP3Op.V_ADD_F32, VOP3Op.V_MAD_F32, VOP3Op.V_FMA_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3B(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(25, 17, VOP3BOp, {VOP3BOp.V_CMPX_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3P(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(30, 21, VOP3POp, {VOP3POp.V_MFMA_F32_16X16X1F32})\\n  vdst = VGPRField(16, 9)\\n  vdsty = VDSTYField(8, 8)\\n  src0 = BitField(7, 0)\\n  opsel_hi = BitField(20, 19, default=3)\\n  opsel_hi2 = BitField(18, 17, default=1)\\n\\nclass VOP3PX2(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 26, VOP3PX2Op, {VOP3PX2Op.V_MFMA_LD_SCALE_B32})\\n  vdst = VGPRField(17, 10)\\n  src0 = BitField(9, 0)\\n  x2encoding = BitField(25, 20)\\n\\nclass VOPC(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(24, 17, VOPCOp, {VOPCOp.V_CMP_EQ_F32, VOPCOp.V_CMP_LT_F32, VOPCOp.V_CMPX_EQ_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP1_DPP16(VOP1):\\n  dpp = BitField(8, 0)\\n\\nclass VOP1_DPP8(VOP1):\\n  row = BitField(8, 6)\\n  bank_mask = BitField(5, 0)\\n\\nclass VOP1_LIT(VOP1):\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_CNPY, VOP1Op.V_CABS_I32, VOP1Op.V_ABS_I32, VOP1Op.V_ADDTID, VOP1Op.V_DOT2ACC_F32_F16})\\n  literal = BitField(15, 0)\\n\\nclass VOP1_SDWA(VOP1):\\n  sdst = BitField(9, 0)\\n\\nclass VOP1_SDWA_SDST(VOP1):\\n  sdst = BitField(9, 0)\\n\\nclass VOP3P_MFMA(VOP3P):\\n  op = EnumBitField(30, 21, VOP3POp, {VOP3POp.V_MFMA_LD_SCALE_B32})\\n  src2 = BitField(5, 0)\\n\\nclass VOP1_SDST(VOP1):\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_CABS_I32, VOP1Op.V_DOT2ACC_F32_F16})\\n  vdst = SSrcField(24, 17)\\n\\nclass VOP1_SDST_LIT(VOP1_SDST):\\n  literal = BitField(15, 0)\\n\\n# instruction helpers\\nv_dot2acc_f32_f16 = functools.partial(DPP, DPPOp.V_DOT2ACC_F32_F16)\\nflat_load_dword = functools.partial(FLAT, FLATOp.FLAT_LOAD_DWORD)\\nflat_load_byte = functools.partial(FLAT, FLATOp.FLAT_LOAD_BYTE)\\nflat_atomic_csub_u32 = functools.partial(FLAT, FLATOp.FLAT_ATOMIC_CSUB_U32)\\nglobal_load_dword = functools.partial(GLOBAL, GLOBALOp.GLOBAL_LOAD_DWORD)\\nglobal_atomic_csub_u32 = functools.partial(GLOBAL, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32)\\nglobal_addtid = functools.partial(GLOBAL, GLOBALOp.GLOBAL_ADDTID)\\nhwreg_vccz = functools.partial(HWREG, HWREGOp.HWREG_VCCZ)\\nhwreg_scc = functools.partial(HWREG, HWREGOp.HWREG_SCC)\\nmsg_gs_done = functools.partial(MSG, MSGOp.MSG_GS_DONE)\\nmsg_nop = functools.partial(MSG, MSGOp.MSG_NOP)\\nscratch_load_byte = functools.partial(SCRATCH, SCRATCHOp.SCRATCH_LOAD_BYTE)\\nv_sdwa_f32_16 = functools.partial(SDWA, SDWAOp.V_SDWA_F32_16)\\ns_nop = functools.partial(SM, SMOp.S_NOP)\\ns_cntnck = functools.partial(SOP1, SOP1Op.S_CNTNCK)\\ns_barrier_init = functools.partial(SOP1, SOP1Op.S_BARRIER_INIT)\\ns_subvector_loop_begin = functools.partial(SOPK, SOPKOp.S_SUBVECTOR_LOOP_BEGIN)\\nvglobal_load_dword = functools.partial(VGLOBAL, VGLOBALOp.VGLOBAL_LOAD_DWORD)\\nv_cnpy_e32 = functools.partial(VOP1_LIT, VOP1Op.V_CNPY_E32)\\nv_cabs_i32_e32 = functools.partial(VOP1_SDST, VOP1Op.V_CABS_I32_E32)\\nv_abs_i32_e32 = functools.partial(VOP1, VOP1Op.V_ABS_I32_E32)\\nv_addtid_e32 = functools.partial(VOP1, VOP1Op.V_ADDTID_E32)\\nv_dot2acc_f32_f16_e32 = functools.partial(VOP1_SDST, VOP1Op.V_DOT2ACC_F32_F16_E32)\\nv_cndmask_b32_e32 = functools.partial(VOP2, VOP2Op.V_CNDMASK_B32_E32)\\nv_dot2acc_f32_f16_e32 = functools.partial(VOP2, VOP2Op.V_DOT2ACC_F32_F16_E32)\\nv_lop3_e32 = functools.partial(VOP2, VOP2Op.V_LOP3_E32)\\nv_cmp_f32_e64 = functools.partial(VOP3_SDST, VOP3Op.V_CMP_F32_E64)\\nv_cmp_lt_f32_e64 = functools.partial(VOP3_SDST, VOP3Op.V_CMP_LT_F32_E64)\\nv_add_f32_e64 = functools.partial(VOP3, VOP3Op.V_ADD_F32_E64)\\nv_mad_f32 = functools.partial(VOP3, VOP3Op.V_MAD_F32)\\nv_fma_f32 = functools.partial(VOP3, VOP3Op.V_FMA_F32)\\nv_cmpx_f32 = functools.partial(VOP3B, VOP3BOp.V_CMPX_F32)\\nv_mfma_f32_16x16x1f32 = functools.partial(VOP3P, VOP3POp.V_MFMA_F32_16X16X1F32)\\nv_mfma_ld_scale_b32 = functools.partial(VOP3P_MFMA, VOP3POp.V_MFMA_LD_SCALE_B32)\\nv_mfma_ld_scale_b32 = functools.partial(VOP3PX2, VOP3PX2Op.V_MFMA_LD_SCALE_B32)\\nv_cmp_eq_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMP_EQ_F32_E32)\\nv_cmp_lt_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMP_LT_F32_E32)\\nv_cmpx_eq_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMPX_EQ_F32_E32)\\nvscratch_load_byte = functools.partial(VSCRATCH, VSCRATCHOp.VSCRATCH_LOAD_BYTE)\\n")
  gl("ins cdna", write_ins(fx_encs(), fx_eos(), fx_ssx(), fx_tys(), "cdna"), "# autogenerated from AMD ISA XML - do not edit\\n# ruff: noqa: E501,F401\\nfrom tinygrad.renderer.amd.dsl import BitField, DPP, DPP16, EXEC, EXECZ, EXEC_HI, EXEC_LO, EnumBitField, FixedBitField, INV_2PI, Inst, LIT, M0, NULL, OFF, SBaseField, SCC, SDWA, SGPRField, SRC_LDS_DIRECT, SRsrcField, SSrcField, SrcField, VCC, VCCZ, VCC_HI, VCC_LO, VDSTYField, VGPRField, s, src, ttmp, v\\nfrom tinygrad.runtime.autogen.amd.cdna.enum import DPPOp, FLATOp, GLOBALOp, SCRATCHOp, SDWAOp, SMOp, SOP1Op, SOPKOp, VFLATOp, VGLOBALOp, VOP1Op, VOP1_DPP16Op, VOP1_DPP8Op, VOP1_LITOp, VOP1_SDSTOp, VOP1_SDWAOp, VOP1_SDWA_SDSTOp, VOP2Op, VOP3BOp, VOP3Op, VOP3POp, VOP3PX2Op, VOP3P_MFMAOp, VOP3_SDSTOp, VOPCOp, VSCRATCHOp, HWREG, MSG\\nimport functools\\n\\nclass FLAT(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, FLATOp, {FLATOp.FLAT_LOAD_DWORD, FLATOp.FLAT_LOAD_BYTE, FLATOp.FLAT_ATOMIC_CSUB_U32, FLATOp.S_ADDTID})\\n  offset = BitField(14, 0)\\n  seg = FixedBitField(17, 15, 0)\\n\\nclass GLOBAL(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, GLOBALOp, {GLOBALOp.GLOBAL_LOAD_DWORD, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32, GLOBALOp.GLOBAL_ADDTID})\\n  offset = BitField(12, 0)\\n  seg = FixedBitField(17, 15, 2)\\n\\nclass SCRATCH(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, SCRATCHOp, {SCRATCHOp.SCRATCH_LOAD_BYTE})\\n  offset = BitField(12, 0)\\n  seg = FixedBitField(17, 15, 1)\\n\\nclass GLOBAL(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, GLOBALOp, {GLOBALOp.GLOBAL_LOAD_DWORD, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32, GLOBALOp.GLOBAL_ADDTID})\\n  offset = BitField(12, 0)\\n\\nclass HWREG(Inst):\\n  encoding = FixedBitField(16, 10, 0b0)\\n  op = EnumBitField(9, 0, HWREGOp, {HWREGOp.HWREG_VCCZ, HWREGOp.HWREG_SCC})\\n\\nclass MSG(Inst):\\n  encoding = FixedBitField(17, 12, 0b0)\\n  op = EnumBitField(11, 0, MSGOp, {MSGOp.MSG_GS_DONE, MSGOp.MSG_NOP})\\n\\nclass SCRATCH(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 18, SCRATCHOp, {SCRATCHOp.SCRATCH_LOAD_BYTE})\\n  offset = BitField(12, 0)\\n\\nclass SM(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(17, 16, SMOp, {SMOp.S_NOP})\\n  sdst = SGPRField(24, 18)\\n  sdata = SGPRField(12, 6)\\n  saddr = SGPRField(31, 25, default=NULL)\\n\\nclass SOP1(Inst):\\n  encoding = FixedBitField(23, 23, 0b1)\\n  op = EnumBitField(22, 16, SOP1Op, {SOP1Op.S_CNTNCK, SOP1Op.S_BARRIER_INIT})\\n  sdst = SGPRField(6, 0)\\n  ssrc0 = SSrcField(15, 8)\\n  saddr = SSrcField(31, 24, default=NULL)\\n  soffset = SGPRField(7, 1, default=NULL)\\n\\nclass SOPK(Inst):\\n  encoding = FixedBitField(27, 27, 0b1)\\n  op = EnumBitField(23, 16, SOPKOp, {SOPKOp.S_SUBVECTOR_LOOP_BEGIN})\\n  sbase = SBaseField(31, 26)\\n  srsrc = SRsrcField(15, 11)\\n  ssamp = SRsrcField(10, 6)\\n  simm16 = BitField(5, 0)\\n\\nclass VOP1(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_ABS_I32, VOP1Op.V_ADDTID})\\n  vdst = VGPRField(16, 9)\\n  src0 = BitField(6, 0)\\n  clmp = BitField(8, 7)\\n\\nclass VOP2(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(25, 17, VOP2Op, {VOP2Op.V_CNDMASK_B32, VOP2Op.V_LOP3})\\n  vdst = VGPRField(16, 9)\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(22, 16, VOP3Op, {VOP3Op.V_CMP_F32, VOP3Op.V_CMP_LT_F32, VOP3Op.V_ADD_F32, VOP3Op.V_MAD_F32, VOP3Op.V_FMA_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3B(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(25, 17, VOP3BOp, {VOP3BOp.V_CMPX_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP3P(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(30, 21, VOP3POp, {VOP3POp.V_MFMA_F32_16X16X1F32})\\n  vdst = VGPRField(16, 9)\\n  vdsty = VDSTYField(8, 8)\\n  src0 = BitField(7, 0)\\n  opsel_hi = BitField(20, 19, default=3)\\n  opsel_hi2 = BitField(18, 17, default=1)\\n\\nclass VOP3PX2(Inst):\\n  encoding = FixedBitField(31, 31, 0b1)\\n  op = EnumBitField(29, 26, VOP3PX2Op, {VOP3PX2Op.V_MFMA_LD_SCALE_B32})\\n  vdst = VGPRField(17, 10)\\n  src0 = BitField(9, 0)\\n  x2encoding = FixedBitField(25, 20, 0b1101100)\\n\\nclass VOPC(Inst):\\n  encoding = FixedBitField(25, 25, 0b1)\\n  op = EnumBitField(24, 17, VOPCOp, {VOPCOp.V_CMP_EQ_F32, VOPCOp.V_CMP_LT_F32, VOPCOp.V_CMPX_EQ_F32})\\n  src0 = SrcField(8, 0)\\n\\nclass VOP1_DPP16(VOP1):\\n  dpp = BitField(8, 0)\\n\\nclass VOP1_DPP8(VOP1):\\n  row = BitField(8, 6)\\n  bank_mask = BitField(5, 0)\\n\\nclass VOP1_LIT(VOP1):\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_CNPY, VOP1Op.V_CABS_I32, VOP1Op.V_ABS_I32, VOP1Op.V_ADDTID, VOP1Op.V_DOT2ACC_F32_F16})\\n  literal = BitField(15, 0)\\n\\nclass VOP1_SDWA(VOP1):\\n  sdst = BitField(9, 0)\\n\\nclass VOP1_SDWA_SDST(VOP1):\\n  sdst = BitField(9, 0)\\n\\nclass VOP3P_MFMA(VOP3P):\\n  op = EnumBitField(30, 21, VOP3POp, {VOP3POp.V_MFMA_LD_SCALE_B32})\\n  src2 = BitField(5, 0)\\n\\nclass VOP1_SDST(VOP1):\\n  op = EnumBitField(24, 17, VOP1Op, {VOP1Op.V_CABS_I32, VOP1Op.V_DOT2ACC_F32_F16})\\n  vdst = SSrcField(24, 17)\\n\\nclass VOP1_SDST_LIT(VOP1_SDST):\\n  literal = BitField(15, 0)\\n\\n# instruction helpers\\nv_dot2acc_f32_f16 = functools.partial(DPP, DPPOp.V_DOT2ACC_F32_F16)\\nflat_load_dword = functools.partial(FLAT, FLATOp.FLAT_LOAD_DWORD)\\nflat_load_byte = functools.partial(FLAT, FLATOp.FLAT_LOAD_BYTE)\\nflat_atomic_csub_u32 = functools.partial(FLAT, FLATOp.FLAT_ATOMIC_CSUB_U32)\\nglobal_load_dword = functools.partial(GLOBAL, GLOBALOp.GLOBAL_LOAD_DWORD)\\nglobal_atomic_csub_u32 = functools.partial(GLOBAL, GLOBALOp.GLOBAL_ATOMIC_CSUB_U32)\\nglobal_addtid = functools.partial(GLOBAL, GLOBALOp.GLOBAL_ADDTID)\\nhwreg_vccz = functools.partial(HWREG, HWREGOp.HWREG_VCCZ)\\nhwreg_scc = functools.partial(HWREG, HWREGOp.HWREG_SCC)\\nmsg_gs_done = functools.partial(MSG, MSGOp.MSG_GS_DONE)\\nmsg_nop = functools.partial(MSG, MSGOp.MSG_NOP)\\nscratch_load_byte = functools.partial(SCRATCH, SCRATCHOp.SCRATCH_LOAD_BYTE)\\nv_sdwa_f32_16 = functools.partial(SDWA, SDWAOp.V_SDWA_F32_16)\\ns_nop = functools.partial(SM, SMOp.S_NOP)\\ns_cntnck = functools.partial(SOP1, SOP1Op.S_CNTNCK)\\ns_barrier_init = functools.partial(SOP1, SOP1Op.S_BARRIER_INIT)\\ns_subvector_loop_begin = functools.partial(SOPK, SOPKOp.S_SUBVECTOR_LOOP_BEGIN)\\nvglobal_load_dword = functools.partial(VGLOBAL, VGLOBALOp.VGLOBAL_LOAD_DWORD)\\nv_cnpy_e32 = functools.partial(VOP1_LIT, VOP1Op.V_CNPY_E32)\\nv_cabs_i32_e32 = functools.partial(VOP1_SDST, VOP1Op.V_CABS_I32_E32)\\nv_abs_i32_e32 = functools.partial(VOP1, VOP1Op.V_ABS_I32_E32)\\nv_addtid_e32 = functools.partial(VOP1, VOP1Op.V_ADDTID_E32)\\nv_dot2acc_f32_f16_e32 = functools.partial(VOP1_SDST, VOP1Op.V_DOT2ACC_F32_F16_E32)\\nv_cndmask_b32_e32 = functools.partial(VOP2, VOP2Op.V_CNDMASK_B32_E32)\\nv_dot2acc_f32_f16_e32 = functools.partial(VOP2, VOP2Op.V_DOT2ACC_F32_F16_E32)\\nv_lop3_e32 = functools.partial(VOP2, VOP2Op.V_LOP3_E32)\\nv_cmp_f32_e64 = functools.partial(VOP3_SDST, VOP3Op.V_CMP_F32_E64)\\nv_cmp_lt_f32_e64 = functools.partial(VOP3_SDST, VOP3Op.V_CMP_LT_F32_E64)\\nv_add_f32_e64 = functools.partial(VOP3, VOP3Op.V_ADD_F32_E64)\\nv_mad_f32 = functools.partial(VOP3, VOP3Op.V_MAD_F32)\\nv_fma_f32 = functools.partial(VOP3, VOP3Op.V_FMA_F32)\\nv_cmpx_f32 = functools.partial(VOP3B, VOP3BOp.V_CMPX_F32)\\nv_mfma_f32_16x16x1f32 = functools.partial(VOP3P, VOP3POp.V_MFMA_F32_16X16X1F32)\\nv_mfma_ld_scale_b32 = functools.partial(VOP3P_MFMA, VOP3POp.V_MFMA_LD_SCALE_B32)\\nv_mfma_ld_scale_b32 = functools.partial(VOP3PX2, VOP3PX2Op.V_MFMA_LD_SCALE_B32)\\nv_cmp_eq_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMP_EQ_F32_E32)\\nv_cmp_lt_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMP_LT_F32_E32)\\nv_cmpx_eq_f32_e32 = functools.partial(VOPC, VOPCOp.V_CMPX_EQ_F32_E32)\\nvscratch_load_byte = functools.partial(VSCRATCH, VSCRATCHOp.VSCRATCH_LOAD_BYTE)\\n")
  gl("pcode rdna3", write_pcode(fx_ps(), fx_eos(), "rdna3"), "# autogenerated from AMD ISA PDF - do not edit\\n# ruff: noqa: E501\\nfrom tinygrad.runtime.autogen.amd.rdna3.enum import VOP1Op, VOP1_LITOp, VOP3Op\\n\\nPCODE = {\\n  VOP1Op.V_CNPY_E32: 'V_CNPY(dst, src0)\\n{\\ndst = src0;\\n} // end',\\n  VOP1Op.V_ADDTID_E32: 'V_ADDTID()\\nT0 = EXEC;',\\n  VOP1_LITOp.V_CNPY: 'V_CNPY(dst, src0)\\n{\\ndst = src0;\\n} // end',\\n  VOP3Op.V_ADD_F32_E64: 'V_ADD_F32(vdst, src0)\\nÎ',\\n}\\n")
  gl("pcode cdna", write_pcode(fx_ps(), fx_eos(), "cdna"), "# autogenerated from AMD ISA PDF - do not edit\\n# ruff: noqa: E501\\nfrom tinygrad.runtime.autogen.amd.cdna.enum import VOP1Op, VOP1_LITOp, VOP3Op\\n\\nPCODE = {\\n  VOP1Op.V_CNPY_E32: 'V_CNPY(dst, src0)\\n{\\ndst = src0;\\n} // end',\\n  VOP1Op.V_ADDTID_E32: 'V_ADDTID()\\nT0 = EXEC;',\\n  VOP1_LITOp.V_CNPY: 'V_CNPY(dst, src0)\\n{\\ndst = src0;\\n} // end',\\n  VOP3Op.V_ADD_F32_E64: 'V_ADD_F32(vdst, src0)\\nÎ',\\n}\\n")
  gl("common", write_common(fx_fbs(), fx_ots()), "# autogenerated from AMD ISA XML - do not edit\\nfrom enum import Enum, auto\\n\\nclass ReprEnum(Enum):\\n  \"\"\"Enum with clean repr that roundtrips with eval().\"\"\"\\n  def __repr__(self): return f\"{type(self).__name__}.{self.name}\"\\n\\nclass Fmt(Enum):\\n  BF16 = auto()\\n  FLOAT = auto()\\n  FP16 = auto()\\n  NONE = auto()\\n  UINT = auto()\\n  VOP1 = auto()\\n  VOP1PP = auto()\\n  VOP2 = auto()\\n  VOP3 = auto()\\n  VOP3P = auto()\\n  VOPC = auto()\\n\\nFMT_BITS = {\\n  Fmt.BF16: 16,\\n  Fmt.FLOAT: 32,\\n  Fmt.FP16: 16,\\n  Fmt.NONE: 0,\\n  Fmt.UINT: 32,\\n  Fmt.VOP1: 32,\\n  Fmt.VOP1PP: 32,\\n  Fmt.VOP2: 32,\\n  Fmt.VOP3: 64,\\n  Fmt.VOP3P: 64,\\n  Fmt.VOPC: 32,\\n}\\n\\nclass OpType(Enum):\\n  OPR_ADDR = auto()\\n  OPR_DATA = auto()\\n  OPR_HWREG = auto()\\n  OPR_SENDMSG_RTN = auto()\\n  OPR_SRC = auto()\\n  OPR_SRC_ABS = auto()\\n  OPR_SRC_NEG = auto()\\n  OPR_SRC_NTZ = auto()\\n  OPR_SREG = auto()\\n  OPR_SREG_SRC = auto()\\n  OPR_VGPR = auto()\\n")
