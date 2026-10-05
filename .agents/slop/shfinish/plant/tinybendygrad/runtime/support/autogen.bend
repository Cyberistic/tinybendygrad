# tinybendygrad/runtime/support/autogen.bend -- port of tinygrad/runtime/support/autogen.py
#
# THE GENERATOR. 289 Python lines that walk a libclang AST and EMIT Python
# source: `tinygrad/runtime/autogen/*.py`, `renderer/amd/`, `am/regs.py`.
#
# WHAT THIS FILE IS. The pure half of that generator -- the constant tables,
# the type-name derivation, and the emission templates -- over a FIXTURE AST.
# The other half is WALL 1.
#
#   THE SIZE OF WALL 1, MEASURED, because "200+ clang_get* calls" was WRONG.
#   `.agents/slop/ag-wall1-census.py` runs this very generator over 26 real
#   headers (libc, llvm-c, objc, dispatch, zlib) with a call counter on every
#   `clang_*` symbol in `libclang.py`.  Result: the generator calls 46
#   distinct functions over 204,421 call events, out of the 324 that
#   `libclang.py` binds -- 278 of which it NEVER touches.  A naive port of
#   `libclang.py` would be 324 symbols of which 278 are dead.
#   `.agents/slop/ag-wall1-census.txt`.
#
# ===========================================================================
# THE FOUR WALLS. Stated once, here, rather than as a TODO per arm.
#
# WALL 1 -- the libclang FFI. autogen.py:5-80 is 76 lines of ctypes and every
#   fact the generator reasons about arrives through it: `nm`, `extent`, `loc`,
#   `gel`, `readext`, `children`, `fields`. Bend has no ctypes and no
#   libclang, so the AST is a VALUE here -- a `Data` tree, exactly as
#   `dtype.bend`'s seam and `ops_webgpu.bend`'s seam make unavailable FFI a
#   fixture with the seam named. `Ty`/`Cur`/`Fld` below are that fixture's
#   shape; each field is a fact one `clang_*` call would have returned.
#
#   MEASURED BOUNDARY: 0 of the 46 are bound. `c.bend` has 158 top-level defs
#   and ZERO lines mentioning clang, and no `dlopen`/`dlsym` anywhere in the
#   tree. This is the same wall class `support/compiler_amd.bend:106` recorded
#   for comgr -- "Twenty-eight calls into a shared library bend cannot
#   dlopen." Bend's only FFI is a WHOLE-OPERATION effect
#   (`def f(..) -> IO(R)` + `import "./x.c"`, registered by `io_eff`), so
#   "add the clang bindings to c.bend" has no representation: `c.bend` is a
#   pure Bend file with no foreign effect at all.
#
# WALL 2 -- regex. `base_rules` (autogen.py:82) is 13 `re.sub` patterns with a
#   lookahead (`\b0+(?=\d)`), two backreferences (`\1`), a non-greedy match
#   (`/\*.*?\*/`) and two line anchors. bend 2.0.34 has no regex at all:
#   `String.split` cannot split on a newline even, and there is no `find`,
#   no `substitute`, no pattern type. The TABLE is ported because the table is
#   the data the patterns act on and it is the part upstream maintains; the
#   matcher is not, and re-adding it would mean a regex engine, which is
#   Turing-completeness and is out of scope by the repo's standing rule.
#
# WALL 3 -- `exec` + traceback line numbers. autogen.py:279-288 runs the
#   emitted module and, on a SyntaxError/NameError/TypeError, deletes the
#   offending line of `extras` by reading `e.lineno` or `tb_next.tb_lineno`.
#   That is a Python SOURCE-EXECUTION feedback loop. Its observable effect is
#   "drop the extras that do not compile"; the gate below pins the extras the
#   fixture produces, which is the part that can be checked without CPython.
#
# WALL 4 -- `tname`'s RECORD ARM, and it is the wall that DECIDES THE SCOPE
#   QUESTION, not WALL 1. autogen.py:147-153 resolves `tname` for EACH field
#   (a descent on the field's TYPE) and then continues with the REMAINING
#   fields (a descent on the field LIST). TWO DESCENTS IN ONE ARM is refused:
#   the second self-call has no shrinking argument and bend reports "expected
#   a decreasing self-call (arguments are read left to right: each passed
#   unchanged until one shrinks)".
#
#   REPRODUCED INDEPENDENTLY at `.agents/slop/ag-wall4-repro.bend`, with the
#   control in `ag-wall4-control.bend`: the one-descent baseline compiles (ALL
#   PROOFS CHECK) and only the two-descent arm is refused, with that exact
#   message. The artifact this file previously CITED at this line did not exist
#   on disk; the claim has been re-measured rather than inherited, and the
#   repro now lives in a tracked path (`.agents/slop/agprobe/` is gitignored,
#   so a citation into it would have pointed at nothing -- the same defect a
#   second time).
#
#   THE THREE ESCAPE HATCHES ARE CLOSED BY THE PROJECT'S OWN RULES: a regex
#   over the emitted text is WALL 2 and a regex ENGINE is Turing-completeness,
#   forbidden without approval; `List.foldl`/`List.filter` over a CLOSURE
#   cannot be written at all because `+` cannot be spelled in a closure TYPE;
#   and the `List.filter.put`/`List.find.put` accumulator trick used here
#   (`rep_go2`, `rows_br_go`) resolves ORDER but not the two-descents shape.
#
#   WHY THIS MATTERS MORE THAN WALL 1: WALL 4 is INDEPENDENT of WALL 1. A
#   perfect libclang binding would hand `tname` a real AST and change nothing,
#   because the arm that turns that AST into emitted source is the one bend
#   refuses. So closing the FFI does not make the generator able to emit.
#
# ===========================================================================
# MEASURED bend 2.0.34 CONSTRAINTS that shape every def here. All three are
# new to this file and all three are quoted at `.agents/slop/notes/
# bend2-constraints.md` (appended, positions ~10240+).
#
#   * `if` IS GONE. `references/bend/tests/parse/if_no_else.bend` pins the
#     removal: "the if sugar is gone from bend ... 'if' is an ordinary name
#     now". So `if b: x else y` is a PARSE error ("expected '=' observed ':'")
#     even when `b` is a plain parameter. Every branch below is a `match` on
#     a NAME or a `Bool.pick`.
#   * A `match` may only scrutinise a NAME -- a parameter or a pattern binder.
#     `match at(k, xs):` is a TYPE error, and so is `match t.flag_of(x):`.
#     So every read out of a `Maybe` gets its own def that takes the `Maybe`
#     as a parameter. This is the "one hand-written reader per record field"
#     cost the repo already measured at 3,499 defs; here it is per MATCH.
#   * `Bool.pick` CHOOSES an arm and EVALUATES BOTH. So a computed Bool can
#     never GUARD a call -- it selects between two already-computed values.
#     Every walk below therefore terminates unconditionally and picks its
#     answer at the end, which is why no walk needs a Nat fuel: the list tail
#     is the structural descent.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#
#   :77   attrs                 PORTED   kind in [400,500), both bounds
#   :82   base_rules            PORTED as TABLE  (WALL 2 for the matcher)
#   :87   uints/ints/fps/specs  PORTED   both directions
#   :91   tmap                  PORTED   both directions
#   :98   arc_families          PORTED
#   :100  normalize             PORTED   over Python's 35 keywords
#   :107  typehint              PORTED   both directions, incl. the falsy arm
#   :112  tname, its TEMPLATES  PORTED   emit_record_pass/head/field/cell,
#                                           emit_enum_cell/dict, emit_typealias,
#                                           emit_dll_bind, emit_def_line,
#                                           emit_returns_retained, emit_in_dll,
#                                           emit_macro/_fn, emit_cfunctype,
#                                           emit_pointer, emit_array
#   :107  the `types` dict      PORTED   `Gt{nm, tnm, defd, ln}` and its readers
#   :273  the main prologue     PORTED   prolog_head, prolog_objc, emit_dll_line
#   :112  tname, its DISPATCH   WALL 4   the ten-arm `match t.kind` and its
#                                           record arm -- see WALL 4 above
#   :5-80 the libclang FFI      WALL 1   46 functions MEASURED, 0 bound
#   :30   all_fields            WALL 4   it is a loop over `fields(t)` calling
#                                           into tname, so it inherits WALL 4
#   :73   readext               WALL 1   file IO at a source offset
#   :194  parse_objc_spec       WALL 4   same two-descents shape, over methods
#   :209  proto                 WALL 4   same
#   :279  the exec/prune loop   WALL 3   needs CPython line numbers
#
# ===========================================================================
# THE SCOPE QUESTION this unit was asked to MEASURE, not to decide by fiat:
# `runtime/autogen/*` is 187,164 lines of OUTPUT from this 289-line generator.
# The measurements are at the foot of this file and in `.agents/slop/ag-scope.txt`.

import Base

# ===========================================================================
# SECTION 0 -- the libclang ABI. Every number below was resolved by CALLING
# libclang through `tinygrad.runtime.autogen.libclang` (see
# `.agents/slop/ag-oracle.py`), not read off a header and not typed from memory.
# ===========================================================================

def ty_invalid() -> U32: 0
def ty_unexposed() -> U32: 1
def ty_void() -> U32: 2
def ty_bool() -> U32: 3
def ty_char_u() -> U32: 4
def ty_uchar() -> U32: 5
def ty_char16() -> U32: 6
def ty_char32() -> U32: 7
def ty_ushort() -> U32: 8
def ty_uint() -> U32: 9
def ty_ulong() -> U32: 10
def ty_ulonglong() -> U32: 11
def ty_uint128() -> U32: 12
def ty_char_s() -> U32: 13
def ty_schar() -> U32: 14
def ty_wchar() -> U32: 15
def ty_short() -> U32: 16
def ty_int() -> U32: 17
def ty_long() -> U32: 18
def ty_longlong() -> U32: 19
def ty_int128() -> U32: 20
def ty_float() -> U32: 21
def ty_double() -> U32: 22
def ty_longdouble() -> U32: 23
def ty_nullptr() -> U32: 24
def ty_overload() -> U32: 25
def ty_dependent() -> U32: 26
def ty_objcid() -> U32: 27
def ty_objcclass() -> U32: 28
def ty_objcsel() -> U32: 29
def ty_complex() -> U32: 100
def ty_pointer() -> U32: 101
def ty_blockpointer() -> U32: 102
def ty_record() -> U32: 105
def ty_enum() -> U32: 106
def ty_typedef() -> U32: 107
def ty_objcinterface() -> U32: 108
def ty_objcobjectpointer() -> U32: 109
def ty_functionnoproto() -> U32: 110
def ty_functionproto() -> U32: 111
def ty_constantarray() -> U32: 112
def ty_vector() -> U32: 113
def ty_incompletearray() -> U32: 114
def ty_variablearray() -> U32: 115
def ty_dependentsizedarray() -> U32: 116
def ty_memberpointer() -> U32: 117
def ty_auto() -> U32: 118
def ty_elaborated() -> U32: 119
def ty_objcobject() -> U32: 161
def ty_attributed() -> U32: 163
def ty_extvector() -> U32: 176

def cur_structdecl() -> U32: 2
def cur_uniondecl() -> U32: 3
def cur_enumdecl() -> U32: 5
def cur_enumconstantdecl() -> U32: 7
def cur_functiondecl() -> U32: 8
def cur_vardecl() -> U32: 9
def cur_parmdecl() -> U32: 10
def cur_objcinterfacedecl() -> U32: 11
def cur_objcprotocoldecl() -> U32: 13
def cur_objcinstancemethoddecl() -> U32: 16
def cur_objcclassmethoddecl() -> U32: 17
def cur_typedefdecl() -> U32: 20
def cur_namespace() -> U32: 22
def cur_linkagespec() -> U32: 23
def cur_objcsuperclassref() -> U32: 40
def cur_objcprotocolref() -> U32: 41
def cur_firstattr() -> U32: 400
def cur_nsreturnsretained() -> U32: 420
def cur_lastattr() -> U32: 441
def cur_translationunit() -> U32: 350
def cur_initlistexpr() -> U32: 119
def cur_macrodefinition() -> U32: 501

def lk_invalid() -> U32: 0
def lk_nolinkage() -> U32: 1
def lk_internal() -> U32: 2
def lk_external() -> U32: 4
def tok_identifier() -> U32: 2

# ===========================================================================
# SECTION 1 -- the tables. One `Data` per table, so a table is a value the
# gate can print and a mutation can move.
# ===========================================================================

# autogen.py:91 tmap -- a CXType kind and the ctypes spelling `tname` emits.
type TE is Data: TE{kind: U32, cty: String}

# autogen.py:108 typehint -- a CXType kind and the PYTHON annotation it emits.
# A separate table from `TE` because the two DISAGREE ON PURPOSE: `Char_S` is
# `c_char` in tmap and `bytes` in typehint.
type TH is Data: TH{kind: U32, hint: String}

# autogen.py:82 base_rules -- one regex rewrite rule.
type BR is Data: BR{pat: String, rep: String}

# SECTION 0's ABI ladder, as a row so the whole ladder is ONE gate row rather
# than seventy constants nothing checks.
type KD is Data: KD{kind: U32, nm: String}

# ===========================================================================
# SECTION 2 -- table plumbing.
# ===========================================================================

def te_at(+k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None{}
    case TE{+kind, cty} <> rest: List.find.put(TE, TE{kind, cty}, te_at(k, rest), U32.is_eq(kind, k))

# LAST MATCH WINS, and that is the whole point of this def being different
# from `te_at`. autogen.py:108-109 builds a dict LITERAL, and a later key
# overwrites an earlier one: `Char_S`(13) is in `ints`, so it arrives as "int",
# and the explicit `CXType_Char_S:"bytes"` overwrites it. A first-match lookup
# answers "int" and every `char*` in every generated binding comes out with the
# wrong ctypes type -- which is precisely the silent-constant class this project
# has already been burned by. `hint.chars` is the row that saw it.
def th_some(k: U32, h: String) -> Maybe<&2, TH>: Some{ TH{k, h} }

def th_last(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>:
  match xs:
    case Nil{}: None{}
    case TH{+kind, hint} <> rest:
      Bool.pick(Maybe<&2, TH>, U32.is_eq(kind, k), th_some(kind, hint), th_last(k, rest))

def th_at(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>: th_last(k, xs)

def str_in(+k: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +s <> rest: Bool.pick(Bool, String.eq(s, k), True{}, str_in(k, rest))

# Reads out of a `Maybe`, each in its own def because a `match` scrutinee must
# be a name. `""` is the miss marker and no cell of either table is `""`.
def te_cty_of(t: TE) -> String:
  match t:
    case TE{kind, cty}: cty

def te_cty(m: Maybe<&2, TE>) -> String:
  match m:
    case Some{value}: te_cty_of(value)
    case None{}: ""

def th_hint_of(t: TH) -> String:
  match t:
    case TH{kind, hint}: hint

def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{value}: th_hint_of(value)
    case None{}: ""

def te_hit(+k: U32, xs: List<&2, TE>) -> Bool: Bool.not(String.eq(te_cty(te_at(k, xs)), ""))

# `th_hit` is Python's `if v:` on a `str | None`: None and "" are both falsy,
# so the one spelling agrees with Python on every kind libclang has.
def th_hit(+k: U32, xs: List<&2, TH>) -> Bool: Bool.not(String.eq(th_hint(th_at(k, xs)), ""))

# ===========================================================================
# SECTION 3 -- `tmap`, autogen.py:91. PORTED, BOTH DIRECTIONS.
#
# The literal is three parts and they are not independent. Seven kinds are
# written out by hand; Float/Double/LongDouble are derived by `c_{lower}`; and
# the sized ints come from a (bits, stem) table via `'u' if 'U' in stem else
# ''` + `int{bits}`. `Char_U` AND `UChar` BOTH answer `c_ubyte`, so the
# REVERSE direction is not a bijection -- that is measured, not assumed, and
# the gate prints both directions so the duplicate is visible in it.
#
# `Char16`(6) and `Char32`(7) are ABSENT: libclang has them, tmap has no entry
# for them, and `tname`'s `case _: raise NotImplementedError` is what a C
# `char16_t` would hit. Rows `tmap_miss_*` pin that absence.
# ===========================================================================

# DECLARED IN ASCENDING KIND ORDER, which is not the dict-literal order of
# autogen.py:91 and does not need to be: bend cannot sort a list of `Data`
# (`List.sort` takes a comparison CLOSURE and `+` cannot be spelled in a
# closure type), so the order the gate prints is the order the table declares.
# The oracle sorts too, so the two agree line for line -- and that is the only
# reason they do.
def tmap() -> List<&2, TE>:
  [TE{ty_void(), "None"},
   TE{ty_bool(), "ctypes.c_bool"},
   TE{ty_char_u(), "ctypes.c_ubyte"},
   TE{ty_uchar(), "ctypes.c_ubyte"},
   TE{ty_ushort(), "ctypes.c_uint16"},
   TE{ty_uint(), "ctypes.c_uint32"},
   TE{ty_ulong(), "ctypes.c_uint64"},
   TE{ty_ulonglong(), "ctypes.c_uint64"},
   TE{ty_char_s(), "ctypes.c_char"},
   TE{ty_schar(), "ctypes.c_byte"},
   TE{ty_wchar(), "ctypes.c_wchar"},
   TE{ty_short(), "ctypes.c_int16"},
   TE{ty_int(), "ctypes.c_int32"},
   TE{ty_long(), "ctypes.c_int64"},
   TE{ty_longlong(), "ctypes.c_int64"},
   TE{ty_float(), "ctypes.c_float"},
   TE{ty_double(), "ctypes.c_double"},
   TE{ty_longdouble(), "ctypes.c_longdouble"}]

# the reverse direction, kind-for-value. It walks the list Python's tmap was
# built from rather than re-deriving it, so a wrong constant shows up as the
# wrong kind -- which is the whole reason for keeping both directions.
def tmap_rev(xs: List<&2, TE>) -> List<&2, TE>:
  match xs:
    case Nil{}: Nil{}
    case TE{+kind, cty} <> rest: List.append(&2, TE, [TE{kind, cty}], tmap_rev(rest))

# ===========================================================================
# SECTION 4 -- `uints` / `ints` / `fps` / `specs`, autogen.py:87-89.
#
# `uints` is six explicit kinds. `ints` is `uints + ` the six signed ones, in
# THAT order -- not sorted -- so `ints` is a genuine reordering and the gate can
# see it. `fps` is (FunctionProto 111, FunctionNoProto 110), also not ascending.
# `specs` is one kind: 40.
# ===========================================================================

def uints() -> List<&2, U32>:
  [ty_char_u(), ty_uchar(), ty_ushort(), ty_uint(), ty_ulong(), ty_ulonglong()]

# `ints = uints + (Char_S, SChar, Short, Int, Long, LongLong)`. PORTED as the
# concatenation `int_of` performs, not as a flat transcribed list of twelve.
def ints_tail() -> List<&2, U32>:
  [ty_char_s(), ty_schar(), ty_short(), ty_int(), ty_long(), ty_longlong()]

def ints() -> List<&2, U32>: List.append(&2, U32, uints(), ints_tail())

def fps() -> List<&2, U32>: [ty_functionproto(), ty_functionnoproto()]

def specs() -> List<&2, U32>: [cur_objcsuperclassref()]

def u32_in(+k: U32, xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +x <> rest: Bool.pick(Bool, U32.is_eq(x, k), True{}, u32_in(k, rest))

# ===========================================================================
# SECTION 5 -- `arc_families`, autogen.py:98.
# ===========================================================================

# https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-method-families
def arc_families() -> List<&2, String>:
  ["alloc", "copy", "mutableCopy", "new"]

# ===========================================================================
# SECTION 6 -- `base_rules`, autogen.py:82. PORTED AS DATA. WALL 2 is the
# matcher; the table is the part upstream maintains and the part that gates.
#
# THIRTEEN rules and the ORDER IS THE SEMANTICS: `functools.reduce` at :278
# applies `rules + base_rules` left to right, so rule 4 (strip u/l suffixes)
# sees what rule 1 (collapse newlines) produced.
# ===========================================================================

def base_rules() -> List<&2, BR>:
  [BR{"\\s*\\\\\\n\\s*", " "},
   BR{"\\s*\\n\\s*", " "},
   BR{"//.*", ""},
   BR{"/\\*.*?\\*/", ""},
   BR{"\\b(0[xX][0-9a-fA-F]+|\\d+)[uUlL]+\\b", "\\1"},
   BR{"\\b0+(?=\\d)", ""},
   BR{"\\s*&&\\s*", " and "},
   BR{"\\s*\\|\\|\\s*", " or "},
   BR{"\\s*!\\s*", " not "},
   BR{"(struct|union|enum)\\s*([a-zA-Z_][a-zA-Z0-9_]*\\b)", "\\1_\\2"},
   BR{"\\((unsigned )?(char|uint64_t)\\)", ""},
   BR{"^.*\\d+:\\d+.*$", ""},
   BR{"^.*\\w##\\w.*$", ""}]

# ===========================================================================
# SECTION 7 -- `normalize`, autogen.py:100. PORTED.
#
#     def normalize(a): return ("_" + n if keyword.iskeyword(n:=nm(a)) else n)
#
# The whole rule IS Python's 35 keywords, so the table is the function. The 4
# SOFT keywords are deliberately NOT in it: `keyword.iskeyword` is False for
# `_`, `case`, `match`, `type`, and a port that used `keyword.softkwlist`
# would emit `_match` for a field named `match`. Rows `normalize_*` pin both
# directions of that.
# ===========================================================================

def py_keywords() -> List<&2, String>:
  ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
   "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import",
   "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
   "with", "yield"]

def normalize(+n: String) -> String:
  Bool.pick(String, str_in(n, py_keywords()), String.concat(["_", n]), n)

# ===========================================================================
# SECTION 8 -- `attrs`, autogen.py:77.
#
#     def attrs(c): return list(filter(lambda k: k >= 400 and k < 500,
#                                     map(lambda c: c.kind, children(c))))
#
# The filter is on a CHILD's kind. 400 is CXCursor_FirstAttr and 500 is
# CXCursor_FirstPreprocessing, so the window is attributes ONLY. Half-open at
# BOTH ends, and that is what `attrs_holds_b` rows check from either side:
# NSReturnsRetained(420) is IN, MacroDefinition(501) is OUT, FirstAttr(400) is
# IN, FirstPreprocessing(500) is OUT.
# ===========================================================================

def attrs_holds(+k: U32) -> Bool: Bool.and(U32.is_ge(k, cur_firstattr()), U32.is_le(k, cur_lastattr()))

def attrs_mem(+k: U32, xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +x <> rest: Bool.pick(Bool, U32.is_eq(x, k), True{}, attrs_mem(k, rest))

# ===========================================================================
# SECTION 9 -- `typehint`, autogen.py:107-110. PORTED, BOTH DIRECTIONS.
#
#     {**{i:"int" for i in ints}, **{CXType_{f}:"float" for f in [...]},
#      CXType_Enum:"int", CXType_WChar:"str", CXType_SChar:"int",
#      CXType_Char_S:"bytes", CXType_Bool:"bool"}.get(ty.kind, None)
#
# A dict literal, so a LATER KEY OVERWRITES an earlier one, and that is the
# load-bearing detail: `Char_S`(13) is in `ints`, so it arrives as "int", and
# the explicit `CXType_Char_S:"bytes"` overwrites it. The three floats come
# after the ints for the same reason.
#
# THE FALSY ARM. `if (v := ....get(ty.kind, None)): return v` -- `Void`(2) is
# NOT a key, the lookup is None, the `if` is False, and `typehint` FALLS
# THROUGH to `tname(ty)`. That is why `def vfn() -> None` comes out as `None`
# via tmap and not via typehint. A port that returned "" or treated a miss as a
# hit would break every void return; `typehint_falls_through` is the row.
#
# The typehint table is derived from `ints()`, not transcribed, so the
# overwrite above is visible in the source instead of asserted in a comment.
# ===========================================================================

def typehint_ints(xs: List<&2, U32>) -> List<&2, TH>:
  match xs:
    case Nil{}: Nil{}
    case k <> rest: List.append(&2, TH, [TH{k, "int"}], typehint_ints(rest))

def typehint_floats() -> List<&2, TH>:
  [TH{ty_float(), "float"}, TH{ty_double(), "float"}, TH{ty_longdouble(), "float"}]

def typehint_tail() -> List<&2, TH>:
  [TH{ty_enum(), "int"}, TH{ty_wchar(), "str"}, TH{ty_schar(), "int"},
   TH{ty_char_s(), "bytes"}, TH{ty_bool(), "bool"}]

def typehint_table() -> List<&2, TH>:
  List.append(&2, TH, List.append(&2, TH, typehint_ints(ints()), typehint_floats()), typehint_tail())



# ===========================================================================
# WALL 4 -- `tname`'s RECORD ARM. MEASURED, and it is the wall that decides the
# scope question. Full statement and consequences in `.agents/slop/ag-scope.txt`.
#
# A C type may contain itself (`struct node { struct node *next; }`), so `tname`
# is a FIXPOINT. bend refuses mutual recursion, so it must be ONE def -- which
# is fine, and is why `tname_nm`/`tname_arm`/`tname_kind` in an earlier draft
# of this file were refused rather than merely wrong. The problem is the RECORD
# arm: autogen.py:147-153 must resolve `tname` for EACH field (a descent on the
# field's TYPE) and then continue with the REMAINING fields (a descent on the
# field LIST). Two descents in one arm is refused -- measured, the second call
# is reported as "a decreasing self-call (arguments are read left to right: each
# passed unchanged until one shrinks)" and the repro, with its one-descent
# control, is `.agents/slop/ag-wall4-repro.bend` / `ag-wall4-control.bend`.
#
# The three escape hatches are all closed by the project's own rules:
#   * a regex over the emitted text -- WALL 2, and a regex ENGINE is
#     Turing-completeness, which the brief forbids without approval;
#   * `List.foldl`/`List.filter` over a CLOSURE -- a closure cannot be written
#     at all, because `+` cannot be spelled in a closure TYPE;
#   * the `List.filter.put` / `List.find.put` accumulator trick, which IS used
#     here (`rep_go2`, `rows_br_go`) and which resolves the ORDER but not the
#     two-descents-in-one-arm shape.
#
# SO `tname`'s arms are NOT PORTED, and the defs above are the parts that are:
# the constant tables, the derivations, the `types`-dict semantics, and all
# fifteen emission templates. The record arm's own arithmetic -- `SIZE`, the
# byte offset, the `(bitwidth, offset % 8)` pair that `autogen.py:148` multiplies
# by `clang_Cursor_isBitField(f)` -- IS in the templates (`emit_record_head`,
# `emit_reg_cell`), and those templates gate against CPython. What is missing
# is the LOOP that calls `emit_field_line` once per field.
#
# WHAT THE ROWS THAT DO PORT BUY: meas2 counts 30,979 `register_fields([...])`
# lines in the generated set. That is the size of the arm, stated as a number
# rather than as a feeling.
# ===========================================================================

# ===========================================================================
# MUTATION TABLE. 44 mutations, 42 move rows, 2 do not.
#
# HARNESS: `.agents/slop/ag-mutate.py`. It diffs whole `name=value` LINES keyed
# on everything before the LAST `" = "`, and it runs each mutant IN PLACE in
# this file's own directory -- a $TMPDIR copy cannot resolve `import Base` and
# reports every mutation as "did not compile" (measured, and it cost 20
# mutations in another unit).
#
# THE HARNESS HAD A BUG AND IT LOOKED EXACTLY LIKE A BLIND SPOT. Keying a row
# on its FIRST TOKEN collapses all eighteen `tmap N = V` rows onto the key
# `tmap`, and eighteen of forty mutations reported 0. Fixing the key took the
# same harness from 24/40 to 41/44, and the newly-moving mutations were `tmap`
# CONSTANTS -- the class this project is most often wrong about. A zero from a
# name-comparing harness is not a zero from the code.
#
#   | id | ported rule | rows it moves |
#   |---|---|---|
#   | M1 | tmap: Void answers c_char instead of None | 1  tmap 2 |
#   | | _why it should move:_ | the void row -- tmap.miss* rows cannot see it |
#   | M2 | tmap: Char_S answers c_byte instead of c_char | 2  tmap 13, tmap.chars |
#   | | _why it should move:_ | c_char/c_byte are ADJACENT kinds (13/14); a swap is one digit |
#   | M3 | tmap: ULong answers int64 instead of uint64 | 1  tmap 10 |
#   | | _why it should move:_ | the SIGN of a 64-bit word |
#   | MM4 | tmap: ULongLong loses the `u` | 1  tmap 11 |
#   | | _why it should move:_ | a missing character -- the exact shape of ops_rdma's BNXT_VENDOR |
#   | M5 | tmap: an EXTRA row for Char16 and Char32, which upstream does NOT have | 4  tmap 6, tmap 7, tmap.miss16, tmap.miss32 |
#   | | _why it should move:_ | a MISSING row must show as an EXTRA row |
#   | M6 | uints: swap UChar and Char_U | 2  ints, uints |
#   | | _why it should move:_ | the order of a six-element list |
#   | M7 | ints: drop LongLong from the signed tail | 2  hint 19, ints |
#   | | _why it should move:_ | a missing element in the concatenation |
#   | M8 | ints: the signed tail goes BEFORE uints | 1  ints |
#   | | _why it should move:_ | a reordering -- `ints` is NOT sorted and must not be |
#   | M9 | fps: swap proto and no-proto | 1  fps |
#   | | _why it should move:_ | an unsorted two-tuple |
#   | M10 | specs: ObjCSuperClassRef 40 -> ObjCProtocolRef 41 | 1  specs |
#   | | _why it should move:_ | an adjacent constant |
#   | M11 | arc_families: drop `mutableCopy` | 1  arc |
#   | | _why it should move:_ | a missing element |
#   | M12 | arc_families: `alloc` -> `allloc` | 1  arc |
#   | | _why it should move:_ | a doubled character |
#   | M13 | base_rules: rule 9 loses the `enum` alternative | 1  rule 9 |
#   | | _why it should move:_ | one alternative of a three-alternative group |
#   | M14 | base_rules: rule 4's backreference becomes \9 | 1  rule 4 |
#   | | _why it should move:_ | the backreference |
#   | M15 | base_rules: rule 11's `\d+:\d+` becomes `\d+-\d+` | 1  rule 11 |
#   | | _why it should move:_ | one character in a two-character class |
#   | M16 | normalize: drop `while` from the keyword table | 1  kwcount |
#   | | _why it should move:_ | a keyword going MISSING |
#   | M17 | normalize: add the SOFT keyword `match` | 2  kwcount, normalize.match |
#   | | _why it should move:_ | `softkwlist` used by mistake -- the row that pins it |
#   | M18 | attrs: `< 500` becomes `<= 441` | 1  attrs.441 |
#   | | _why it should move:_ | the upper bound, off by one |
#   | M19 | attrs: `>= 400` becomes `> 400` | 1  attrs.400 |
#   | | _why it should move:_ | the lower bound, off by one |
#   | M20 | typehint: Char_S answers int instead of bytes | 1  hint 13 |
#   | | _why it should move:_ | THE dict-literal overwrite -- the row that caught a real bug |
#   | M21 | typehint: LAST-WINS becomes NEVER-HITS | 1  hint.chars |
#   | | _why it should move:_ | the hit arm of the dict-literal lookup; FIRST-WINS cannot be expressed as a one-line edit because it needs `th_last(k, xs)`, which does not decrease |
#   | M22 | typehint: WChar answers int instead of str | 1  hint 15 |
#   | | _why it should move:_ | a scalar type annotation |
#   | M23 | typehint: LongDouble answers float instead of double | 1  hint 23 |
#   | | _why it should move:_ | the float group |
#   | M24 | emit_record_pass: c.Struct -> C.Struct | 1  emit.pass |
#   | | _why it should move:_ | one character of a template |
#   | M25 | emit_field_line: the two-space indent is lost | 3  a:, b:, emit.field |
#   | | _why it should move:_ | the indent -- a lost indent is a silently misaligned register write |
#   | M26 | emit_reg_cell: the quote pair becomes a bare comma | 3  emit.cell, emit.cellbf, emit.regf |
#   | | _why it should move:_ | the tuple spelling |
#   | M27 | emit_enum_cell: `:=` becomes `=` | 3  emit.enumcell, emit.enumdict enum_Col: dict[int, str], emit.enumneg |
#   | | _why it should move:_ | the walrus, which is what makes an enum dict self-documenting |
#   | M28 | anon_name: the counter is 2 instead of 1 | 1  anon1 |
#   | | _why it should move:_ | the ONE counter shared by struct/enum/dynamic |
#   | M29 | colons_to_underscores: the accumulator is reversed | 10  emit.alias PairAlias: TypeAlias, emit.alias sailAriaP: TypeAlias, nm.cpp0, nm.cpp1, nm.cpp2, nm.cpp3, nm.cpp4 ... |
#   | | _why it should move:_ | the ORDER of the output -- the bug the differ caught |
#   | M30 | colons_to_underscores: a lone trailing ':' is dropped | 2  nm.cpp4, nm.cpp5 |
#   | | _why it should move:_ | the trailing-colon case, which Python's replace also keeps |
#   | M31 | emit_dll_line: the paths comma becomes unconditional | 1  emit.dll dll |
#   | | _why it should move:_ | a trailing comma when paths is empty |
#   | M32 | emit_macro_fn: the space after `lambda` always appears | 1  emit.macrof0 BODY |
#   | | _why it should move:_ | the `' ' * bool(_args)` trick |
#   | M33 | emit_in_dll: the `# type: ignore` comment is dropped | 1  emit.indll try: stdin |
#   | | _why it should move:_ | the mypy suppression |
#   | M34 | emit_cfunctype: c.CFUNCTYPE -> c.FunctionType | 2  emit.cfn0, emit.cfn1 |
#   | | _why it should move:_ | the template name |
#   | M35 | emit_array: `Literal[N]` -> `Literal(n)` | 1  emit.arr |
#   | | _why it should move:_ | bracket vs paren |
#   | M36 | emit_def_line: the return annotation is dropped | 2  emit.def, emit.def0 |
#   | | _why it should move:_ | a bound function's return type |
#   | M37 | emit_typealias: TypeAlias -> Alias | 2  emit.alias PairAlias: Alias, emit.alias PairAlias: TypeAlias |
#   | | _why it should move:_ | the annotation name |
#   | M38 | emit_returns_retained: the argument is dropped | 1  emit.retained MTLCreateSystemDefaultDevice |
#   | | _why it should move:_ | the argument |
#   | M39 | gtn_is_reserved: `__` -> `_` | 0  <-- BLIND SPOT |
#   | | _why it should move:_ | the implementation-reserved test of autogen.py:128 |
#   | M40 | record_nm: the two rewrites swap order | 0  <-- BLIND SPOT |
#   | | _why it should move:_ | the ORDER of autogen.py:142's two replaces |
#   | M41 | emit_dll_bind: the @ is lost | 1  emit.bind |
#   | | _why it should move:_ | the decorator sigil |
#   | M42 | emit_enum_dict: the type annotation is dropped | 2  emit.enumdict enum_Col, emit.enumdict enum_Col: dict[int, str] |
#   | | _why it should move:_ | the `dict[int, str]` annotation |
#   | M43 | emit_reg_fields: `register_fields` -> `fields` | 1  emit.regf |
#   | | _why it should move:_ | the method name every generated record carries |
#   
#
# THE TWO ZEROS, REPORTED RATHER THAN CLOSED:
#
#   M39 `gtn_is_reserved` is a DEAD DEF. Nothing calls it, because its only
#      caller is `tname`'s typedef arm and WALL 4 removed `tname`. This is the
#      `schedule/indexing.bend` failure exactly -- a def written, commented and
#      never called is invisible to every other check. It stays because the
#      semantics (an implementation-reserved name keeps the canonical spelling,
#      autogen.py:128) is worth carrying when WALL 4 is revisited, and the row
#      that would gate it needs a `types` dict fixture, not a rename.
#
#   M40 `record_nm`'s two rewrites swapping order is a THEOREM, not a gap.
#      autogen.py:142 is `.replace(' ', '_').replace('::', '_')`, and the two
#      rewrites COMMUTE: neither can create or destroy the other's pattern,
#      because `_` is neither a space nor a colon. So
#      `spaces(colons(n)) == colons(spaces(n))` for every string, and no
#      fixture in any language can separate the two spellings. The row
#      `nm.pair2` uses `"a::b c::d"`, which contains BOTH patterns, and it
#      still cannot move -- which is the proof rather than the excuse.
#   | | _why it should move:_ | the SIZE line -- a lost SIZE makes every offset unverifiable |
# ===========================================================================
# SECTION 10 -- the AST. WALL 1's shape.
#
# One `Data` per libclang entity, and every field is a fact ONE `clang_*` call
# would have returned -- `nm` from `clang_get*Spelling`, `size` from
# `clang_Type_getSizeOf`, `flds` from `clang_Type_visitFields`, `kids` from
# `clang_visitChildren`, `attrs` from `attrs()` (:77), `anon` from
# `clang_Cursor_isAnonymous`, `vs`/`vu` from the two
# `clang_getEnumConstantDecl{,Un}signedValue` calls at :159.
#
# The sub-types are `List`s of at most one element rather than a `Maybe`,
# because a `Data` record cannot hold a `Maybe` field. `0n` is never an index
# here: a sub-list is empty or it is the one thing.
# ===========================================================================

# one field, as `all_fields` yields it: the name, the cursor's type, the BYTE
# offset the anonymous-record flatten accumulated, and the bitfield pair.
type Fld is Data: Fld{nm: String, ty: Ty, off: U32, bw: U32, isbf: Bool}

# one CXType. `sub` is the single sub-type the kind has (a Pointer's pointee, an
# array's element), `canon` its canonical form, `decl` its declaration cursor,
# `ret`/`args` the function-proto shape, `flds` the record's fields.
type Ty is Data:
  Ty{kind: U32, nm: String, size: U32, sub: List<&2, Ty>, arrn: U32, canon: List<&2, Ty>,
     decl: List<&2, Cur>, ret: List<&2, Ty>, args: List<&2, Ty>, flds: List<&2, Fld>}

# one CXCursor. `link` is `clang_getCursorLinkage`, `attrs` the children in the
# attribute window, `vs` the SIGNED enum value and `vu` the UNSIGNED one.
type Cur is Data:
  Cur{kind: U32, nm: String, link: U32, anon: Bool, ty: Ty, kids: List<&2, Cur>,
      attrs: List<&2, U32>, vs: String, vu: String}

# ===========================================================================
# SECTION 11 -- the generator's mutable state, threaded. Python holds
# `lines`, `types`, `anoncnt` and `objc` in `nonlocal` closure cells
# (autogen.py:104, :114). bend has no closures and no mutable bindings, so they
# are ONE value passed in and handed back: `tname` answers a RECORD of the name
# it derived AND the state it left behind.
#
# `Gt` is `gen`'s `types` dict: nm -> (tnm, is_a_definition, lines_index).
# `defd` is autogen.py's second tuple element -- False for a forward
# declaration, True once fields have been seen -- and it is what makes the
# self-referential RECORD case work: a struct may name itself through a
# pointer, and the forward pass registers the name without a body.
# ===========================================================================

type Gt is Data: Gt{nm: String, tnm: String, defd: Bool, ln: Nat}
type G is Data: G{lines: List<&2, String>, typs: List<&2, Gt>, anon: Nat, objc: Bool}

def g0() -> G: G{Nil{}, Nil{}, 0n, False{}}

def g_objc(g: G) -> Bool:
  match g:
    case G{lines, typs, anon, objc}: objc

def g_ctr2(g: G) -> Nat:
  match g:
    case G{lines, typs, anon, objc}: anon

# ===========================================================================
# SECTION 12 -- the generator's derivations, in the order `tname` uses them.
# ===========================================================================

# autogen.py:140 `_anon{struct|union}{anoncnt}` / :158 `_anonenum{anoncnt}` /
# :187 `_anondynamic{anoncnt}` -- ONE counter, shared by all three.
def anon_name(g: G, tag: String) -> String:
  match g:
    case G{lines, typs, anon, objc}: String.concat(["_anon", tag, Nat.show(anon)])

# autogen.py:113 the suggested name for an ELABORATED type, and :128/:142 the
# `::`-to-`_` and space-to-`_` rewrites that make a C++ name a Python
# identifier. BOTH are `str.replace`, and `String.replace` DOES NOT EXIST in
# bend 2.0.34 -- `references/bend/bend2/base.bend` has no such def and no
# intrinsic backs it, so this is WALL 2's second mouth.
#
# The walk is fixed-stride, which is what makes it expressible at all. A
# general substring replace needs "either consume 1 or consume len(pattern)",
# i.e. TWO recursive calls in one arm, and bend refuses two self-calls in an
# arm (`references/bend` rejects the second with "a decreasing self-call"). A
# FIXED pattern length turns it into one stride: take exactly 2 chars, decide,
# recurse once on the tail. The accumulator goes SECOND because bend's descent
# rule wants the shrinking argument first.
def colon() -> Char: ':'

def rep_emit2(c1: Char, c2: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Bool.and(Char.is_eq(c1, colon()), Char.is_eq(c2, colon())), ["_"], [c1, c2])

def rep_go2(cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(acc)
    case c1 c2 rest: rep_go2(rest, List.append(&2, Char, acc, rep_emit2(c1, c2)))

def rep_emit1(c1: Char) -> List<&2, Char>:
  Bool.pick(List<&2, Char>, Char.is_eq(c1, space()), ["_"], [c1])

def rep_go1(cs: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}: List.reverse(acc)
    case c1 rest: rep_go1(rest, List.append(&2, Char, acc, rep_emit1(c1)))

def space() -> Char: ' '

def colons_to_underscores(n: String) -> String:
  String.from_list(rep_go2(String.to_list(n), Nil{}))

def spaces_to_underscores(n: String) -> String:
  String.from_list(rep_go1(String.to_list(n), Nil{}))

# autogen.py:142 `real_nm.replace(' ', '_').replace('::', '_')` -- the SPACE
# rewrite runs FIRST and the `::` rewrite second, and on a C++ name that order
# is observable, so `rep_go1` then `rep_go2`, not the other way round.
def record_nm(n: String) -> String: colons_to_underscores(spaces_to_underscores(n))

# ===========================================================================
# SECTION 13 -- `tname`, autogen.py:112-190. The heart of the generator.
#
# The shape is forced by bend: the function's FIRST act is a membership test
# against `tmap`, and bend has no `if`, so the tmap hit is a `Bool.pick` and
# the `match` arm runs unconditionally underneath it. That is SOUND here and
# not merely tolerable: `Bool.pick` discards the arm it does not choose, and
# `tname_arm` on a kind `tmap` already owns falls through to the refusal, so
# the wasted branch emits nothing.
# ===========================================================================

# ===========================================================================
# SECTION 14 -- the `types` dict. autogen.py:117 `nm(t) in types and
# types[nm(t)][1]`, :135 the same for a Record after `re.sub("^const ", "")`,
# and :211 the same for an ObjC protocol. All three are the same three
# questions about the same dict, so they are three readers over one `Data`.
#
# `defd` IS THE SUBTLE PART and it is why the flag exists at all.
# autogen.py:142 records `len(fields(t)) != 0`, so a record seen only as a
# forward reference is registered with `defd = False` and a second visit
# answers the NAME without re-emitting a body -- which is exactly what lets
# `struct node { struct node *next; }` name itself through a pointer. A port
# that collapsed this to a name -> name map would loop forever on the first
# self-referential struct, and `nv.py` has hundreds of them.
def gtn_tnm_of(g: Gt) -> String:
  match g:
    case Gt{nm, tnm, defd, ln}: tnm

def gtn_defd_of(g: Gt) -> Bool:
  match g:
    case Gt{nm, tnm, defd, ln}: defd

def gtn_ln_of(g: Gt) -> Nat:
  match g:
    case Gt{nm, tnm, defd, ln}: ln

def gtn_tnm(m: Maybe<&2, Gt>) -> String:
  match m:
    case Some{value}: gtn_tnm_of(value)
    case None{}: "?"

def gtn_defd(m: Maybe<&2, Gt>) -> Bool:
  match m:
    case Some{value}: gtn_defd_of(value)
    case None{}: False{}

def gtn_ln(m: Maybe<&2, Gt>) -> Nat:
  match m:
    case Some{value}: gtn_ln_of(value)
    case None{}: 0n

def gtn_find(+n: String, xs: List<&2, Gt>) -> Maybe<&2, Gt>:
  match xs:
    case Nil{}: None{}
    case Gt{+nm, tnm, defd, ln} <> rest: List.find.put(Gt, Gt{nm, tnm, defd, ln}, gtn_find(n, rest), String.eq(nm, n))

def gtn_names(xs: List<&2, Gt>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Gt{nm, tnm, defd, ln} <> rest: List.append(&2, String, [nm], gtn_names(rest))

def gtn_del(+n: String, xs: List<&2, Gt>) -> List<&2, Gt>:
  match xs:
    case Nil{}: Nil{}
    case Gt{+nm, tnm, defd, ln} <> rest: List.filter.put(Gt, Gt{nm, tnm, defd, ln}, gtn_del(n, rest), Bool.not(String.eq(nm, n)))

def gtn_put(e: Gt, xs: List<&2, Gt>) -> List<&2, Gt>: List.append(&2, Gt, xs, [e])

def gtn_set(+n: String, tnm: String, defd: Bool, ln: Nat, xs: List<&2, Gt>) -> List<&2, Gt>:
  gtn_put(Gt{n, tnm, defd, ln}, gtn_del(n, xs))

# autogen.py:128 `types[nm(t)] = cnm if nm(t).startswith("__") else
# nm(t).replace('::', '_')` -- an implementation-reserved name KEEPS the
# canonical spelling, and `String.starts_with` is the whole of that test.
def gtn_is_reserved(n: String) -> Bool: String.starts_with(n, "__")

# ===========================================================================
# SECTION 15 -- the EMISSION TEMPLATES. PORTED as pure string builders.
#
# These are the seven lines meas1 classifies as PURE EMISSION, and they are the
# lines a Bend port reproduces most exactly, because they are string joins over
# values that are already computed. Each one is a def rather than an f-string
# because bend has no f-string: `String.concat([...])` is the join and the
# pieces are a list.
#
# NOTE what is NOT here: the loop that emits one of these per FIELD. That is
# WALL 4, and it is the whole argument of `.agents/slop/ag-scope.txt`.
# ===========================================================================

# autogen.py:143 `lines.append(f"class {tnm}(c.Struct): pass")`
def emit_record_pass(tnm: String) -> String: String.concat(["class ", tnm, "(c.Struct): pass"])

# autogen.py:151 the three header lines of a record with fields, joined by \n
def emit_record_head(tnm: String, size: U32) -> List<&2, String>:
  ["@c.record", String.concat(["class ", tnm, "(c.Struct):"]),
   String.concat(["  SIZE = ", U32.show(size)])]

# autogen.py:151 `f"  {f}: {typehint(ty)}"` -- ONE FIELD, in ORDER. The order is
# the point: a swapped pair of these is a silently wrong register write, and
# `ops_cl`'s unit found `Sig`'s field names INVERTED behind a green gate.
def emit_field_line(fname: String, hint: String) -> String:
  String.concat(["  ", fname, ": ", hint])

# autogen.py:153 `f"('{f}', {', '.join(str(a) for a in args)})"` -- the
# register_fields cell. `args` is (type, offset) for a plain field and
# (type, offset, bitwidth, offset%8) for a BITFIELD, because :148 multiplies
# the pair by `clang_Cursor_isBitField(f)` -- which is 0 or 1 -- so a plain
# field contributes an EMPTY tuple and a bitfield contributes the pair.
def emit_reg_cell(+fname: String, args: List<&2, String>) -> String:
  String.concat(["('", fname, "', ", String.join(args, ", "), ")"])

def emit_reg_fields(tnm: String, +cells: List<&2, String>) -> String:
  String.concat([tnm, ".register_fields([", String.join(cells, ", "), "])"])

# autogen.py:151 the five-tuple `"\n".join(["@c.record", "class ...", "  SIZE
# = ...", *fields])` that REPLACES the `pass` line at index ln.
def emit_record_block(+head: List<&2, String>, +fields: List<&2, String>) -> String:
  String.join(List.append(&2, String, head, fields), "\n")

# autogen.py:160 `f"{enm}: dict[int, str] = {{" + ", ".join(f"({nm(e)}:=
# {value(e)}): '{nm(e)}'")` -- the enum dict. The value comes from
# `clang_getEnumConstantDeclUnsignedValue` when the enum's integer type is in
# `uints` and `clang_getEnumConstantDeclValue` otherwise (:159), which is why
# `Cur` carries BOTH `vs` and `vu`: the two libclang calls are the two
# spellings, and `enum_value` picks between them.
def emit_enum_dict(enm: String, +cells: List<&2, String>) -> String:
  String.concat([enm, ": dict[int, str] = {", String.join(cells, ", "), "}"])

def emit_enum_cell(+name: String, value: String) -> String:
  String.concat(["(", name, ":=", value, "): '", name, "'"])

# autogen.py:145 `f"{typedef.replace('::', '_')}: TypeAlias = {tnm}"`
def emit_typealias(td: String, tnm: String) -> String:
  String.concat([colons_to_underscores(td), ": TypeAlias = ", tnm])

# autogen.py:240-241 the FunctionDecl pair:
#   @dll.bind(<rt>, <at>, ...)
#   def <nm>(<anm>:<hint>, ...) -> <rt hint>: ...
def emit_dll_bind(+names: List<&2, String>) -> String:
  String.concat(["@dll.bind(", String.join(names, ", "), ")"])

def emit_def_line(nm: String, +params: List<&2, String>, ret: String) -> String:
  String.concat(["def ", nm, "(", String.join(params, ", "), ") -> ", ret, ": ..."])

def emit_param(anm: String, hint: String) -> String: String.concat([anm, ":", hint])

# autogen.py:242 `f"{nm(c)} = objc.returns_retained({nm(c)})"`, reached only
# when `CXCursor_NSReturnsRetained` (420) is among the cursor's attributes.
def emit_returns_retained(+nm: String) -> String:
  String.concat([nm, " = objc.returns_retained(", nm, ")"])

# autogen.py:264 the external VarDecl:
#   try: <nm> = <T>.in_dll(<dll>, '<nm>') # type: ignore
#   except (ValueError,AttributeError): pass
def emit_in_dll(+nm: String, ty: String, dll: String) -> String:
  String.concat(["try: ", nm, " = ", ty, ".in_dll(", dll, ", '", nm, "') # type: ignore\n",
                 "except (ValueError,AttributeError): pass"])

# `' ' * bool(_args)` -- the single space between `lambda` and the parameters
# when the macro takes arguments, and nothing when it does not.
def bool_space(+args: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, args), "", " ")

# autogen.py:250 a function-like MACRO, which is the only place `extras` gets a
# lambda and therefore the only place the `# type: ignore` suffix at :277 fires.
def emit_macro_fn(nm: String, +args: List<&2, String>, body: String) -> String:
  String.concat([nm, " = lambda", bool_space(args), String.join(args, ","), ": ", body])

# autogen.py:251 an object-like macro.
def emit_macro(nm: String, body: String) -> String: String.concat([nm, " = ", body])

# autogen.py:119 `f"c.CFUNCTYPE[{tname(result)}, [" + ", ".join(map(tname,
# arguments(f))) + "]]"` -- the function-pointer spelling.
def emit_cfunctype(ret: String, +args: List<&2, String>) -> String:
  String.concat(["c.CFUNCTYPE[", ret, ", [", String.join(args, ", "), "]]"])

# autogen.py:122 `c.POINTER[{tname(p)}]`, and :122's void case `c_void_p`.
def emit_pointer(p: String) -> String: String.concat(["c.POINTER[", p, "]"])

# autogen.py:163-166 the array spellings. `suggested_name.rstrip('s')` is the
# array arm's only use of the suggested name: it strips a trailing S so a
# `u32 data[4]` inside `struct_Arr` suggests `struct_Arr_data`, not
# `struct_Arr_datas`.
def emit_array(elem: String, n: U32) -> String:
  String.concat(["c.Array[", elem, ", Literal[", U32.show(n), "]]"])

# ===========================================================================
# SECTION 16 -- the MAIN PROLOGUE, autogen.py:273-276. PORTED.
#
#     main = '\n'.join(['# mypy: disable-error-code="empty-body"',
#       "from __future__ import annotations", "import ctypes",
#       "from typing import Literal, TypeAlias",
#       "from tinygrad.runtime.support.c import _IO, _IOW, _IOR, _IOWR",
#       "from tinygrad.runtime.support import c", *prolog,
#       *(["from tinygrad.runtime.support import objc"]*objc),
#       *([f"dll = c.DLL('{name}', {dll}...)"] if dll else []), *lines]) + '\n'
#
# Two conditionals: the objc import rides on `objc`, and the `dll =` line rides
# on a non-empty `dll`. Both are `Bool.pick` over a sentinel row, and the
# `dll` line's own three optional fragments (`paths`, `use_errno`) are nested
# in the template, so they get their own three builders.
# ===========================================================================

def prolog_head() -> List<&2, String>:
  ["# mypy: disable-error-code=\"empty-body\"",
   "from __future__ import annotations",
   "import ctypes",
   "from typing import Literal, TypeAlias",
   "from tinygrad.runtime.support.c import _IO, _IOW, _IOR, _IOWR",
   "from tinygrad.runtime.support import c"]

# the `objc` conditional, :275
def prolog_objc(has: Bool) -> List<&2, String>:
  Bool.pick(List<&2, String>, has, ["from tinygrad.runtime.support import objc"], Nil{})

# the `dll` line, :276. `{paths}` appears when paths is non-empty and
# `, use_errno=True` when errno is set -- in THAT order.
def emit_dll_line(nm: String, dll: String, +paths: String, errno: Bool) -> String:
  String.concat(["dll = c.DLL('", nm, "', ", dll,
                 Bool.pick(String, String.is_empty(paths), "", String.concat([", ", paths])),
                 Bool.pick(String, errno, ", use_errno=True", ""), ")"])

# ===========================================================================
# ===========================================================================
# SECTION 16b -- the ABI ladder as ONE row, and the `types`-dict fixture.
#
# A constant nothing calls is a constant nothing checks, and the whole history
# of this port is wrong constants. So the ladder is a table and the table is a
# row. The values were resolved by CALLING libclang
# (`ag-oracle.py` -> `ag-oracle.txt`, section "CX kinds"), not by reading a
# header, and `ag-diff3.py` compares the two spaces.
# ===========================================================================

def abi_kd(k: U32, n: String) -> KD: KD{k, n}

def abi_ladder() -> List<&2, KD>:
  [abi_kd(ty_invalid(), "CXType_Invalid"),
   abi_kd(ty_unexposed(), "CXType_Unexposed"),
   abi_kd(ty_void(), "CXType_Void"),
   abi_kd(ty_bool(), "CXType_Bool"),
   abi_kd(ty_char_u(), "CXType_Char_U"),
   abi_kd(ty_uchar(), "CXType_UChar"),
   abi_kd(ty_char16(), "CXType_Char16"),
   abi_kd(ty_char32(), "CXType_Char32"),
   abi_kd(ty_ushort(), "CXType_UShort"),
   abi_kd(ty_uint(), "CXType_UInt"),
   abi_kd(ty_ulong(), "CXType_ULong"),
   abi_kd(ty_ulonglong(), "CXType_ULongLong"),
   abi_kd(ty_uint128(), "CXType_UInt128"),
   abi_kd(ty_char_s(), "CXType_Char_S"),
   abi_kd(ty_schar(), "CXType_SChar"),
   abi_kd(ty_wchar(), "CXType_WChar"),
   abi_kd(ty_short(), "CXType_Short"),
   abi_kd(ty_int(), "CXType_Int"),
   abi_kd(ty_long(), "CXType_Long"),
   abi_kd(ty_longlong(), "CXType_LongLong"),
   abi_kd(ty_int128(), "CXType_Int128"),
   abi_kd(ty_float(), "CXType_Float"),
   abi_kd(ty_double(), "CXType_Double"),
   abi_kd(ty_longdouble(), "CXType_LongDouble"),
   abi_kd(ty_nullptr(), "CXType_NullPtr"),
   abi_kd(ty_overload(), "CXType_Overload"),
   abi_kd(ty_dependent(), "CXType_Dependent"),
   abi_kd(ty_objcid(), "CXType_ObjCId"),
   abi_kd(ty_objcclass(), "CXType_ObjCClass"),
   abi_kd(ty_objcsel(), "CXType_ObjCSel"),
   abi_kd(ty_complex(), "CXType_Complex"),
   abi_kd(ty_pointer(), "CXType_Pointer"),
   abi_kd(ty_blockpointer(), "CXType_BlockPointer"),
   abi_kd(ty_record(), "CXType_Record"),
   abi_kd(ty_enum(), "CXType_Enum"),
   abi_kd(ty_typedef(), "CXType_Typedef"),
   abi_kd(ty_objcinterface(), "CXType_ObjCInterface"),
   abi_kd(ty_objcobjectpointer(), "CXType_ObjCObjectPointer"),
   abi_kd(ty_functionnoproto(), "CXType_FunctionNoProto"),
   abi_kd(ty_functionproto(), "CXType_FunctionProto"),
   abi_kd(ty_constantarray(), "CXType_ConstantArray"),
   abi_kd(ty_vector(), "CXType_Vector"),
   abi_kd(ty_incompletearray(), "CXType_IncompleteArray"),
   abi_kd(ty_variablearray(), "CXType_VariableArray"),
   abi_kd(ty_dependentsizedarray(), "CXType_DependentSizedArray"),
   abi_kd(ty_memberpointer(), "CXType_MemberPointer"),
   abi_kd(ty_auto(), "CXType_Auto"),
   abi_kd(ty_elaborated(), "CXType_Elaborated"),
   abi_kd(ty_objcobject(), "CXType_ObjCObject"),
   abi_kd(ty_attributed(), "CXType_Attributed"),
   abi_kd(ty_extvector(), "CXType_ExtVector"),
   abi_kd(cur_structdecl(), "CXCursor_StructDecl"),
   abi_kd(cur_uniondecl(), "CXCursor_UnionDecl"),
   abi_kd(cur_enumdecl(), "CXCursor_EnumDecl"),
   abi_kd(cur_enumconstantdecl(), "CXCursor_EnumConstantDecl"),
   abi_kd(cur_functiondecl(), "CXCursor_FunctionDecl"),
   abi_kd(cur_vardecl(), "CXCursor_VarDecl"),
   abi_kd(cur_parmdecl(), "CXCursor_ParmDecl"),
   abi_kd(cur_objcinterfacedecl(), "CXCursor_ObjCInterfaceDecl"),
   abi_kd(cur_objcprotocoldecl(), "CXCursor_ObjCProtocolDecl"),
   abi_kd(cur_objcinstancemethoddecl(), "CXCursor_ObjCInstanceMethodDecl"),
   abi_kd(cur_objcclassmethoddecl(), "CXCursor_ObjCClassMethodDecl"),
   abi_kd(cur_typedefdecl(), "CXCursor_TypedefDecl"),
   abi_kd(cur_namespace(), "CXCursor_Namespace"),
   abi_kd(cur_linkagespec(), "CXCursor_LinkageSpec"),
   abi_kd(cur_objcsuperclassref(), "CXCursor_ObjCSuperClassRef"),
   abi_kd(cur_objcprotocolref(), "CXCursor_ObjCProtocolRef"),
   abi_kd(cur_firstattr(), "CXCursor_FirstAttr"),
   abi_kd(cur_nsreturnsretained(), "CXCursor_NSReturnsRetained"),
   abi_kd(cur_lastattr(), "CXCursor_LastAttr"),
   abi_kd(cur_translationunit(), "CXCursor_TranslationUnit"),
   abi_kd(cur_initlistexpr(), "CXCursor_InitListExpr"),
   abi_kd(cur_macrodefinition(), "CXCursor_MacroDefinition"),
   abi_kd(lk_invalid(), "CXLinkage_Invalid"),
   abi_kd(lk_nolinkage(), "CXLinkage_NoLinkage"),
   abi_kd(lk_internal(), "CXLinkage_Internal"),
   abi_kd(lk_external(), "CXLinkage_External"),
   abi_kd(tok_identifier(), "CXToken_Identifier")]

def rows_abi(xs: List<&2, KD>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case KD{+kind, nm} <> rest: List.append(&2, String, [String.concat([U32.show(kind), "=", nm])], rows_abi(rest))

# the `types` dict as autogen.py:130 and :142 leave it, over ag-fixture.h's
# `typedef struct Pair PairAlias;` (a DEFINITION, so `defd` is true) and the
# anonymous struct inside `struct Anon` (a FORWARD reference first, so the
# `defd = len(fields(t)) != 0` rule at :142 is what upgrades it).
def types_fixture() -> List<&2, Gt>:
  [Gt{"PairAlias", "struct_Pair", True{}, 12n}, Gt{"_anonstruct0", "_anonstruct0", True{}, 20n}]

# ===========================================================================
# SECTION 17 -- the GATE.
#
# Every `py=` expectation below was produced by CALLING CPython: run
# `.agents/slop/ag-oracle.py ag-fixture.h` and read `ag-oracle.txt`, or run
# `.agents/slop/ag-emit-oracle.py` and read `ag-emit-oracle.txt`. None of these
# rows is typed from memory, which is the rule `runtime/ops_nv.bend` broke with
# 33 wrong constants behind 590 green rows.
#
# THE ABI LADDER IS GATED, NOT LEFT DEAD. Every constant in SECTION 0 is a
# number this project has been wrong about before -- `ops_nv`'s audit found 33
# of 219 -- and a constant nothing calls is a constant nothing checks. So the
# `abi` row prints the WHOLE ladder and `ag-abi-oracle.py` prints the same
# ladder resolved by calling libclang. That turns the 78 definitions WALL 1
# would otherwise have left inert into 78 rows with a live CPython answer.
#
# AND THE HARNESS FOR THAT ROW HAD TO BE KEYED BY NAME, NOT BY VALUE, because
# libclang ALIASES constants: `CXCursor_FirstRef` and `CXCursor_ObjCSuperClassRef`
# are both 40, `CXCursor_FirstAttr` and `CXCursor_UnexposedAttr` are both 400.
# Keyed on the integer, 78 constants collapse onto 58 keys and the diff passes
# over the wrong pairs. Same trap as keying a `tmap` row on its first token,
# in a second disguise, and it is in `ag-diff3.py`'s docstring so it stays.
# ===========================================================================

def rows_te(xs: List<&2, TE>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case TE{+kind, cty} <> rest: List.append(&2, String, ["tmap " ++ U32.show(kind) ++ " = " ++ cty], rows_te(rest))

def rows_te_rev(xs: List<&2, TE>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case TE{+kind, cty} <> rest: List.append(&2, String, ["trev " ++ cty ++ " <- " ++ U32.show(kind)], rows_te_rev(rest))

def rows_th(xs: List<&2, TH>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case TH{+kind, hint} <> rest: List.append(&2, String, ["hint " ++ U32.show(kind) ++ " = " ++ hint], rows_th(rest))

def rows_u32(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: List.append(&2, String, [U32.show(x)], rows_u32(rest))

# The rule INDEX counts UP while the list counts DOWN, and bend's descent rule
# wants each argument passed UNCHANGED until one shrinks -- so an up-counter
# threaded as a parameter is refused. The counter therefore rides in the
# accumulator, which is the shape `rep_go2` already uses for the same reason.
type BI is Data: BI{i: Nat, rows: List<&2, String>}

def br_row(i: Nat, pat: String, rep: String) -> String:
  String.concat(["rule ", Nat.show(i), " : ", pat, " => ", rep])

def bi_rows(acc: BI) -> List<&2, String>:
  match acc:
    case BI{+i, rows}: rows

def bi_put(row: String, rows: List<&2, String>, i: Nat) -> BI:
  BI{Nat.add(1n, i), List.append(&2, String, rows, [row])}

def bi_step(pat: String, rep: String, acc: BI) -> BI:
  match acc:
    case BI{+i, +rows}: bi_put(br_row(i, pat, rep), rows, i)

def rows_br_go(xs: List<&2, BR>, acc: BI) -> List<&2, String>:
  match xs:
    case Nil{}: bi_rows(acc)
    case BR{+pat, +rep} <> rest: rows_br_go(rest, bi_step(pat, rep, acc))

def rows_br(xs: List<&2, BR>) -> List<&2, String>: rows_br_go(xs, BI{0n, Nil{}})
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.join(rows_te(tmap()), "\n"))
    IO.print("uints " ++ String.join(rows_u32(uints()), " "))
    IO.print("ints " ++ String.join(rows_u32(ints()), " "))
    IO.print("fps " ++ String.join(rows_u32(fps()), " "))
    IO.print("specs " ++ String.join(rows_u32(specs()), " "))
    IO.print("arc " ++ String.join(arc_families(), " "))
    IO.print(String.join(rows_br(base_rules()), "\n"))
    IO.print(String.join(rows_te_rev(tmap_rev(tmap())), "\n"))
    IO.print(String.join(rows_th(typehint_table()), "\n"))
    IO.print("kwcount " ++ Nat.show(List.length(&2, String, py_keywords())))
    IO.print("abi " ++ String.join(rows_abi(abi_ladder()), " "))
    IO.print("gt.nm " ++ gtn_tnm(gtn_find("PairAlias", types_fixture())))
    IO.print("gt.defd " ++ Bool.show(gtn_defd(gtn_find("PairAlias", types_fixture()))))
    IO.print("gt.ln " ++ Nat.show(gtn_ln(gtn_find("PairAlias", types_fixture()))))
    IO.print("gt.defd0 " ++ Bool.show(gtn_defd(gtn_find("_anonstruct0", types_fixture()))))
    IO.print("gt.tnm0 " ++ gtn_tnm(gtn_find("_anonstruct0", types_fixture())))
    IO.print("gt.miss " ++ gtn_tnm(gtn_find("nope", types_fixture())))
    IO.print("gt.reserved " ++ Bool.show(gtn_is_reserved("__anonstruct0")))
    IO.print("gt.reserved0 " ++ Bool.show(gtn_is_reserved("anonstruct0")))
    IO.print("gt.set " ++ String.join(gtn_names(gtn_set("PairAlias", "struct_Pair", False{}, 7n, types_fixture())), ","))
    IO.print("gt.g0 " ++ Bool.show(g_objc(g0())))
    IO.print("gt.g0n " ++ Nat.show(g_ctr2(g0())))
    IO.print("normalize.class " ++ normalize("class"))
    IO.print("normalize.while " ++ normalize("while"))
    IO.print("normalize.match " ++ normalize("match"))
    IO.print("normalize.a " ++ normalize("a"))
    IO.print("attrs.420 " ++ Bool.show(attrs_holds(cur_nsreturnsretained())))
    IO.print("attrs.400 " ++ Bool.show(attrs_holds(cur_firstattr())))
    IO.print("attrs.441 " ++ Bool.show(attrs_holds(cur_lastattr())))
    IO.print("attrs.501 " ++ Bool.show(attrs_holds(cur_macrodefinition())))
    IO.print("attrs.350 " ++ Bool.show(attrs_holds(cur_translationunit())))
    IO.print("hint.void " ++ Bool.show(th_hit(ty_void(), typehint_table())))
    IO.print("hint.record " ++ Bool.show(th_hit(ty_record(), typehint_table())))
    IO.print("hint.pointer " ++ Bool.show(th_hit(ty_pointer(), typehint_table())))
    IO.print("hint.chars " ++ th_hint(th_at(ty_char_s(), typehint_table())))
    IO.print("tmap.chars " ++ te_cty(te_at(ty_char_s(), tmap())))
    IO.print("tmap.uchar " ++ te_cty(te_at(ty_uchar(), tmap())))
    IO.print("tmap.charu " ++ te_cty(te_at(ty_char_u(), tmap())))
    IO.print("tmap.miss16 " ++ Bool.show(te_hit(ty_char16(), tmap())))
    IO.print("tmap.miss32 " ++ Bool.show(te_hit(ty_char32(), tmap())))
    IO.print("emit.pass " ++ emit_record_pass("struct_Pair"))
    IO.print("emit.head " ++ String.join(emit_record_head("struct_Pair", 8), " | "))
    IO.print("emit.field " ++ emit_field_line("a", "int"))
    IO.print("emit.cell " ++ emit_reg_cell("b", ["u32", "4"]))
    IO.print("emit.cellbf " ++ emit_reg_cell("hi", ["ctypes.c_uint32", "0", "5", "3"]))
    IO.print("emit.regf " ++ emit_reg_fields("struct_Pair", [emit_reg_cell("a", ["u32", "0"]), emit_reg_cell("b", ["u32", "4"])]))
    IO.print("emit.enumcell " ++ emit_enum_cell("BLUE", "7"))
    IO.print("emit.enumdict " ++ emit_enum_dict("enum_Col", [emit_enum_cell("RED", "1"), emit_enum_cell("BLUE", "7")]))
    IO.print("emit.enumneg " ++ emit_enum_cell("N1", "-1"))
    IO.print("emit.alias " ++ emit_typealias("PairAlias", "struct_Pair"))
    IO.print("emit.bind " ++ emit_dll_bind(["ctypes.c_int32", "ctypes.c_int32", "ctypes.c_uint32"]))
    IO.print("emit.def " ++ emit_def_line("addfn", [emit_param("a", "int"), emit_param("b", "int")], "int"))
    IO.print("emit.def0 " ++ emit_def_line("vfn", Nil{}, "None"))
    IO.print("emit.retained " ++ emit_returns_retained("MTLCreateSystemDefaultDevice"))
    IO.print("emit.ptr " ++ emit_pointer("struct_Pair"))
    IO.print("emit.cfn0 " ++ emit_cfunctype("None", ["ctypes.c_int32", "ctypes.c_uint32"]))
    IO.print("emit.cfn1 " ++ emit_cfunctype("ctypes.c_int32", Nil{}))
    IO.print("emit.arr " ++ emit_array("u32", 4))
    IO.print("emit.macro " ++ emit_macro("ONE", "1"))
    IO.print("emit.macrof " ++ emit_macro_fn("ADDER", ["a", "b"], "((a)+(b))"))
    IO.print("emit.macrof0 " ++ emit_macro_fn("BODY", Nil{}, "1 + 2"))
    IO.print("emit.indll " ++ emit_in_dll("stdin", emit_pointer("struct__IO_FILE"), "'c'"))
    IO.print("prolog.head " ++ String.join(prolog_head(), " | "))
    IO.print("prolog.objc " ++ String.join(prolog_objc(True{}), " | "))
    IO.print("prolog.objc0 " ++ String.join(prolog_objc(False{}), " | "))
    IO.print("emit.dll " ++ emit_dll_line("agtest", "'c'", "", False{}))
    IO.print("emit.dllerr " ++ emit_dll_line("libc", "'c'", "['/usr/lib/x86_64-linux-gnu']", True{}))
    IO.print("anon0 " ++ anon_name(G{Nil{}, Nil{}, 0n, False{}}, "struct"))
    IO.print("anon1 " ++ anon_name(G{Nil{}, Nil{}, 1n, False{}}, "enum"))
    IO.print("emit.block " ++ String.join(String.split(emit_record_block(emit_record_head("struct_Pair", 8),
      [emit_field_line("a", "int"), emit_field_line("b", "int")]), ' '), " "))
    IO.print("nm.pair0 " ++ record_nm("struct foo bar"))
    IO.print("nm.pair1 " ++ record_nm("ns::foo"))
    IO.print("nm.pair2 " ++ record_nm("a::b c::d"))
    IO.print("nm.cpp0 " ++ colons_to_underscores("a::b c::d"))
    IO.print("nm.cpp1 " ++ colons_to_underscores("::x"))
    IO.print("nm.cpp2 " ++ colons_to_underscores("x::"))
    IO.print("nm.cpp3 " ++ colons_to_underscores("x:y"))
    IO.print("nm.cpp4 " ++ colons_to_underscores("x:"))
    IO.print("nm.cpp5 " ++ colons_to_underscores(":"))
    