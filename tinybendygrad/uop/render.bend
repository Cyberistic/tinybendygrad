# render.bend -- tinygrad/uop/render.py.
#
# THE FIRST STRING-BUILDING UNIT IN THE PORT. Everything ported so far was DATA:
# an arena of U32 indices, a fold of derived properties, six rule tables. This
# file turns a UOp back into PYTHON SOURCE TEXT, and it is the first place where
# a dropped literal produces plausible wrong output instead of a type error.
#
# ===========================================================================
# WHAT base.bend HAS, MEASURED 2026-09-30 against bend 2.0.34
# (`./bin/bend` on a probe file). This list is the whole substrate, and the
# absences are the walls.
#
#   String.append(a, b)                          concat two
#   String.concat(xs: List<&2, String>)           concat a list
#   String.join(xs, +sep: String)                 join with a separator
#   String.split(s, +sep: CHAR) -> List<String>   split -- on ONE CHARACTER
#   String.starts_with / ends_with / contains
#   String.take(s, n: Nat) / drop / get(s, n) / length(s) -> Nat
#   String.to_list(s) -> List<Char> / from_list
#   String.repeat(+s, n: Nat)
#   String.to_upper / to_lower / trim_start / trim_end / trim / reverse
#   String.is_empty / eq / order / is_lt / is_le / is_gt / is_ge
#   U32.show Nat.show Bool.show Char.show Maybe.show List.show F32.show
#   (helpers.bend: pad_left pad_right ansilen colored Flags)
#
# ===========================================================================
# WHAT IS MISSING. Four gaps, and only the first is cosmetic.
#
#   (a) NO `sprintf`, NO field-width specifier, NO `format`. Every `f"{i:4d}"`,
#       `f"{str(u.op):20s}"`, `f"{str(u.dtype):40s}"`, `f"{str(srcs):32s}"` and
#       `multirange_str(..., pad=10)` is `H.pad_left` / `H.pad_right`, which
#       helpers.bend HAS. So this gap is CLOSED by composition, not a wall.
#
#   (b) NO `String.replace` / `replace_all`. `String.split` splits on a single
#       CHAR, so a MULTI-CHARACTER substring replace has no primitive at all.
#       `render.py` needs one, in `Ops.SPECIAL`'s renderer arm
#       (`x.arg.name is not None else f"p{x.arg.slot}"` -- no) and in
#       `renderer`'s CAST arm, `str(x.dtype)[7:]` (render.py:56), which strips
#       the literal prefix `"dtypes."` off the front of a string. A PREFIX strip
#       is `String.drop(s, 7n)`, which base.bend has, so THAT one is closed too.
#       A general `replace` would need a char-wise scan; nothing here needs it.
#
#   (c) NO SIGNED INTEGERS, and so NO Python `str()` of a negative number.
#       Bend has `Nat`, `U32` and `F32` only. `U32.show(4294967293)` is
#       `"4294967293"`; CPython's `str(-3)` is `"-3"`. `pyrender` renders
#       `Ops.CONST` values and `RANGE` bounds, both of which are signed in
#       Python. `sint_show` below closes this for the int32 range, which is the
#       range tinygrad's sint occupies: a sign flag plus a magnitude, exactly
#       the shape `helpers.bend`'s `I64` already uses.
#
#   (d) NO Python `repr()` OF AN ARBITRARY OBJECT. This is the REAL wall.
#       `render.py` calls `repr(...)` on SIX different things -- `x.arg.device`,
#       `x.arg` for SPECIAL/CUSTOM_FUNCTION/sugar ops, `x.dtype!r`, the ints of
#       a RANGE's arg, `u.arg` for the GroupOp.All fallback, and `x.tag`. In
#       Python each dispatches on the runtime type of an `Any`. In Bend there is
#       no `Any` and no runtime type to dispatch on, because `Arg` and `Tag` are
#       CLOSED DATATYPES -- which is the better representation (the brief's
#       "parse, don't validate": eighteen `Any` values became eighteen
#       compiler-checked arms) and it makes `repr` a per-arm FUNCTION rather than
#       a dynamic dispatch. So `arg_repr` below is 18 match arms, one per `Arg`
#       constructor, and it is honest rather than a loss. The one thing that is
#       genuinely lost: Python's `repr` of an object with a user-defined
#       `__repr__` reads that method, and Bend cannot read a method off a value.
#       `ParamArg` is that case -- see `arg_repr.AParam`.
#
# ===========================================================================
# THE WALL THAT IS NOT ABOUT STRINGS AT ALL: `eval_pyrender`.
#
# `tinygrad/uop/spec.py:293` does `exec(code, pyrender_globals(), lcls)` on the
# string `pyrender` produced and reads back `lcls['ast']`. That is not a missing
# primitive; it is a missing language. The generated text names `UOp`, `Ops`,
# `dtypes`, `KernelInfo`, `ParamArg` and a dozen other CPython objects as GLOBALS
# in a namespace built by a Python `import`. Bend has no `exec`, no globals dict
# and no value that knows its own type's name, so the round trip has no
# representation at all -- not a hard one, not a deferred one.
#
# `upat.bend` already settled the precedent for this repo: the pattern COMPILER
# EMITS PYTHON TEXT and the Bend side is a hand-written dispatch instead. So the
# correct port of `pyrender` is to emit the text and NOT round-trip it, and
# `test_pyrender` (`spec.py:296`) becomes the string-diff gate at the foot of
# this file instead of an `exec`. Recording it, not engineering around it.
#
# ===========================================================================
# DEPENDENCIES. `render.py:3-4` imports NINE names -- eight from `uop.ops` and
# `strip_parens`. Five of the nine are the ones whose presence or absence in Bend
# is a fact about the substrate, so those five are listed; the other four
# (`ParamArg`, `UOp`, `PatternMatcher`, `UPat`) are rewritten as closed datatypes
# here and their absence is not a gap. One of the five exists, four do not.
#
#   strip_parens              EXISTS, helpers.bend:983. Used as-is.
#   range_str                 ABSENT from ops.bend. Rebuilt here, from `AxisType`,
#                             `axis_colors`, `Ops.value` and `sint_show` -- all
#                             present. `ops.bend` has no `range_str` at all, so
#                             its absence is a real gap in the gate file, not an
#                             oversight I am working around.
#   multirange_str           ABSENT. Rebuilt here from `range_str` plus a sort.
#   consumer_map_from_toposort ABSENT. `fold.bend`'s `Kahn.consumers` COUNTS a
#                             node's in-edges but does not RETURN them, and
#                             `pyrender` needs both the count and the single
#                             consumer's identity (`render.py:163`:
#                             `list(cmap[u].keys())[0].src`). Rebuilt here as the
#                             `Cons` record -- `seen`/`cnt`/`who`, three maps --
#                             built by `consumers.new`. (The header of this file
#                             used to name two defs, `consumers.of` and
#                             `consumers.who`, that were never written; `who` is a
#                             FIELD of `Cons`, not a def.)
#   sint                     ABSENT, and so is `sint_to_uop` (`ops.bend:3813` marks
#                             that one `TODO(p3)`). `sint` is a TYPE ALIAS for
#                             `UOp | int`, which has no Bend spelling, so
#                             `marg_str`'s `isinstance(a, UOp)` test becomes a
#                             match on `Arg`'s `APy` arm -- which is strictly
#                             MORE precise, since `sint` is exactly "a UOp or a
#                             Const".

# ===========================================================================
# THE DRIFT RECORD. `78d482262` ("range AxisType is first / delete REDUCE/UNROLL")
# changed `render.py` in FOUR places and this file was written against the pin,
# so all four were open until now. Everything below is MEASURED, and every
# measurement is a CALL into a throwaway tree at one end or the other
# (`.agents/slop/xd1/render-oracle.py`, `call-refusal-oracle.py`, `argrepr.py`).
#
#   #  site                                    what it was            what it is now
#   -- -------------------------------------------------------------- --------------
#   1  `renderer`'s void-RANGE arm             `f"loop{x.arg[0]}"`    `f"loop{x.axis_id[0]}"`
#   2  the `Ops.BUFFER` pyrender RULE          present                 DELETED
#   3  the `Ops.RANGE` pyrender rule           whole-arg walk          3 named values
#                                                                 + `len==1` guard
#   4  `pyrender`'s CALL refusal              `dtype is void and      `body.op is PROGRAM
#                                               not CUSTOM_FUNCTION`    or grad_fxn or aux`
#
# SITE 1 NEEDS NO CODE HERE AND THAT IS THE FINDING. The `renderer` matcher is
# `# TODO(p3) render.py:45` -- not ported -- so the arm has no def in this file.
# `rg -n "loop" tinybendygrad/uop/render.bend` returns ONE hit and it is a
# comment about the consumer map. So site 1 is a drift site in a file that does
# not exist yet, and the honest report is "no rows could have caught it because
# there is nothing to catch".
#
# WHAT SITE 1 DID BREAK IS ONE ROW, and it is `arg_repr ARng`: `repr` of a RANGE's
# arg reads `axis_id` and `axis_type`, and both moved. See `arange_repr`.
#
# SITE 3 IS THE ONE THAT MOVED NO EXISTING ROW, and it is the most useful result
# here. `pyrender range` and `pyrender range2` are BYTE-IDENTICAL at both ends of
# the window: the pin's `[repr(y) for y in x.arg]` happened to walk the arg in the
# order the head rule names its three values. So a green gate over the rewritten
# rule proved nothing; the rule's REAL change is the `len(axis_id) == 1` guard,
# and no fixture in the file could reach it because `f_range` built one-element id
# lists only. `flat1` / `flat2` / `flat3` exist because of that, and `f_range`'s
# signature now takes the id LIST for the same reason.
#
# SITE 4 HAD NO ROW AT ALL, and neither did `pyr_buffer`: `rg -n "pyr_call\("
# tinybendygrad/` returned `pyr_call`'s own `def` line and nothing else. `to_render`
# asked neither predicate and `main` printed neither, so the header sentence "they
# are two PREDICATES and the gate prints them" was a claim about two unreachable
# defs. That is the `schedule/indexing.bend` three-functions finding in miniature
# and it is the answer to "could any row have caught this": no, and the reason is
# structural.
#
# AND THE PREDICATE IS NOT A WIDENING. The pin and head disagree in BOTH
# directions over 4 bodies x 4 CallInfo shapes: a void NOOP body was REFUSED at
# the pin and RENDERED at head, and a `grad_fxn` / `aux` call was RENDERED at the
# pin and REFUSED at head. A port that only ADDED head's conjuncts would refuse
# strictly more and a port that only DELETED the pin's would refuse strictly less,
# and both would be wrong on a fixture. `pyr_call_prog` is the positive control and
# `pyr_call_noop` / `pyr_call_named` / `pyr_call_const` are the arms.
#
# ===========================================================================
# THE WORKING TREE IS A BROKEN HYBRID, and every measurement above had to be
# taken OUT OF TREE because of it. `tinygrad/uop/ops.py` is at HEAD here and
# `tinygrad/uop/render.py` is at the PIN -- `render.py` is a B1 singleton and was
# not vendored -- so `pyrender` in THIS tree answers
# `UOp.range(4, AxisType.WEAK, 0)`, which is NEITHER end's answer. MEASURED:
# `.agents/slop/xd1/render-oracle.py` run against `pin/`, `head/` and a copy of the
# working tree, rows `s1_renderer_void_1id`, `s2_pyrender_buffer_global` and
# `s3_pyrender_range_1id` all answer `==NEITHER (hybrid)`.
#
# SO A GATE RUN AGAINST THE WORKING TREE MEASURES A THIRD THING, and it is the
# worst of the three: a tree that no commit in this window ever produced. Every
# expectation here comes from `xd1/head`, which is `git archive upstream/master`.
# ===========================================================================

import Base
import ./ops.bend as O
import ./fold.bend as F
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

# ===========================================================================
# sint_show -- `str(i)` for a SIGNED int held as a `U32` two's-complement bit
# pattern. base.bend has `U32.show`, which prints the unsigned value, so this is
# the one genuinely new string primitive this file needs (wall (c) above).
#
# THE RANGE IS int32, and that is a real limit rather than a convenient one:
# `x >= 2^31` reads as negative, so a uint32 above 2^31 would print with a
# minus sign. tinygrad's `sint` is Python's unbounded int, so a CONST holding
# 2**40 would print `1099511627776` in CPython and `-2199023255552` here. No
# CONST in a compiled graph carries a value that large (the ones that do are
# shape bounds and come through `marg_str`, which routes UOps back through
# `pyrender`), and widening the range means a 64-bit formatter, which needs a
# two-word divide. The limit is stated rather than hidden.
# ===========================================================================

# 2**31: the first bit pattern that reads as negative in an int32
def sint_show.half(x: U32) -> Bool: U32.is_ge(x, 2147483648)

def sint_show.pick(neg: Bool, x: U32) -> String:
  match neg:
    case True{}: String.concat(["-", U32.show(U32.sub(0, x))])
    case False{}: U32.show(x)

def sint_show(+x: U32) -> String: sint_show.pick(sint_show.half(x), x)

# ===========================================================================
# `f32_repr` -- `repr(float)`, for the four cases where base.bend's `F32.show`
# disagrees with CPython. `F32.show` prints the shortest round-trip for an F32;
# Python prints the shortest round-trip for the f64 the F32 widens to.
# ===========================================================================
#
#   F32.show(3.0) = "3"        repr(3.0)  = "3.0"      a whole float needs the dot
#   F32.show(1e-7) = "1e-7"    repr(1e-7) = "1e-07"    Python's exponent is 2 digits
#   F32.show(0.6666666) = "0.6666666"
#                            repr(that) = "0.6666666865348816"
#
# THE THIRD IS A WALL AND NOT A BUG IN THE FIXER. There is no `F64` in
# base.bend, so there is no def that can print the 17-significant-digit decimal
# an f64 round-trips through. `F32.show` is right about the F32 and CPython is
# right about the f64, and for every CONST a compiled graph actually holds
# (0.0, 1.0, 0.5, an integer-valued float) the two strings are equal. The
# disagreement is confined to a CONST carrying a float that needs 8+ significant
# decimal digits, which tinygrad never emits -- `dtypes.from_py` wraps a Python
# float in a ConstFloat unchanged, so it CAN, and then the emitted code differs
# in its trailing digits while still parsing to the same UOp. Recorded rather
# than papered over.
#
# `dot_ok` is the "no `.`, no `e`, no `inf`, no `nan`" test: those three words
# are the only ways Python's repr of a float comes back without a fraction.
# The two tests are computed in their own def and PASSED, because a `match` may
# only scrutinise a parameter and `String.contains` is a call (brief rule 2).
#
# `inf` contains an `n` and `nan` contains an `a`, so "is there a `.` or an `e`"
# is not the test for "is it finite": `inf` has neither and `nan` has neither.
# `String.split(s, 'e')` splits on the ONE character `e`, which is what makes the
# exponent's own length readable.

# `inf` has an `n` and `nan` has both an `n` and an `N`, and neither has a `.`
# or an `e`; a whole number has none of the three either. So `special` and
# `dotted` are two of the three tests and `String.contains(s, "e")` is the third.
def f32_repr.special(+s: String) -> Bool:
  Bool.or(String.contains(s, "i"), Bool.or(String.contains(s, "n"), String.contains(s, "N")))

def f32_repr.dotted(+s: String) -> Bool: String.contains(s, ".")

def f32_repr.padexp(one: Bool, +e: String, +m: String) -> String:
  String.concat([m, "e", Bool.pick(String, one, String.append(e, "0"), e)])

def peek(cs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, cs, n), "")

def f32_repr.exp(+cs: List<&2, String>) -> String:
  f32_repr.padexp(Nat.is_eq(String.length(peek(cs, 1n)), 1n), peek(cs, 1n), peek(cs, 0n))

def f32_repr.of(special: Bool, dotted: Bool, expd: Bool, +cs: List<&2, String>, +s: String) -> String:
  match special:
    case True{}: s
    case False{}:
      match dotted:
        case True{}: s
        case False{}:
          match expd:
            case True{}: f32_repr.exp(cs)
            case False{}: String.append(s, ".0")

def f32_repr(+x: F32) -> String:
  f32_repr.of(f32_repr.special(F32.show(x)), f32_repr.dotted(F32.show(x)),
    String.contains(F32.show(x), "e"), String.split(F32.show(x), 'e'), F32.show(x))

# ===========================================================================
# `repr` OF THE ARG. Wall (d) above: Python dispatches on the runtime type of an
# `Any` and Bend dispatches on a CLOSED DATATYPE, so what is one dynamic `repr`
# in Python is one `match` per payload here. Eighteen arms, compiler-checked.
#
# Each payload's Python `repr` is kept in its own comment. The four that are NOT
# a plain literal -- `Const` (a `ConstFloat` subclass with a `__repr__`), `Dt`
# (a dataclass with `INVERSE_DTYPES_DICT`), `S.Dev` (a `str|tuple`) and
# `ParamArg` (a dataclass with a hand-written `__repr__`) -- are the four that
# needed a def.
# ===========================================================================

# `str()` of an `H.I64`, which is `CInt`'s payload and Python's unbounded int.
# The SAME int32 limit as `sint_show`, and the same reason: a decimal formatter
# for the whole 64-bit range is a two-word long division. When the value does
# not fit int32 the two words print as `hi:lo` rather than as a decimal, which
# is a visible difference to diff rather than a wrong digit.
def sint_i64.of(fits: Bool, +x: H.I64) -> String:
  Bool.pick(String, fits, sint_show(H.lo32(x)), H.i64_show(H.hi32(x), H.lo32(x)))

def i64_fits_i32(+x: H.I64) -> Bool:
  U32.is_eq(H.hi32(x), H.match_hi(H.i32_is_neg(H.lo32(x))))

def sint_i64(+x: H.I64) -> String:
  sint_i64.of(i64_fits_i32(x), x)

# `ConstFloat.__repr__` / `ConstFloat.__str__` are both
# `float.__repr__(self)`, and `InvalidType.__repr__` is "Invalid".
def const_repr.cfloat(+f: F32) -> String:
  String.concat(["ConstFloat(", f32_repr(f), ")"])

def const_repr(c: O.Const) -> String:
  match c:
    case O.CBool{b}: Bool.show(b)
    case O.CInt{i}: sint_i64(i)
    case O.CFloat{f}: const_repr.cfloat(f)
    case O.CInvalid{}: "Invalid"

# `DType.__repr__` -- and it CHANGED. It was
# `f"dtypes.{INVERSE_DTYPES_DICT[self.name]}"`, so it printed the ATTRIBUTE the
# inverse dict happened to resolve to: `repr(dtypes.f32)` was `dtypes.f32`,
# because "float" was a later key in DTYPES_DICT than "float32" and the dict
# comprehension let the last one win. It is now `f"dtypes.{self.name}"`, and
# upstream DELETED INVERSE_DTYPES_DICT entirely (tinygrad 793abbb), which is why
# this twenty-arm table is gone rather than renamed: with `name` and attribute
# spelled the same way there is nothing left for it to map.
#
# `repr(dtypes.f32)` printed `dtypes.f32` and now prints `dtypes.f32`. That
# is a BEHAVIOUR CHANGE and every gate row that prints a dtype's repr moves, which
# is the cheapest detector the rename has: the rows below `dt_repr` are the ones
# to re-read after it.
def dt_attr(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_repr(d: S.Dt) -> String:
  String.append("dtypes.", dt_attr(d))

# `AddrSpace.__repr__` -- `f"{cls.__name__}.{self.name}"`, and `__str__` is
# `repr(self)`. So the `addrspace` column of a ParamArg prints qualified.
def addr_name(a: S.Addr) -> String:
  match a:
    case S.AGlobal{}: "GLOBAL"
    case S.ALocal{}: "LOCAL"
    case S.AReg{}: "REG"
    case S.Aalu{}: "ALU"

def addr_repr(a: S.Addr) -> String:
  String.concat(["AddrSpace.", addr_name(a)])

# ===========================================================================
# THE DEVICE TABLE. `S.Dev` is a `U32` tag (ops.bend:680-684) and ops.bend:683
# says the tag is "per name interned by the runtime" -- a table that is NOT
# THERE. `repr` is the one reader that needs the NAME, so the table lands here,
# at the point of use, and is the P6 device table ops.bend points at.
#
# THE ORDER IS THIS FILE'S CONVENTION and no claim is made that it is
# tinygrad's, because the port has no `Device` registry to intern into and the
# tag is an arena-local word exactly as an axis id is. What the differential
# requires is only that the tag a graph carries and the name printed for it
# agree, and both the fixtures here and the runtime that builds the arena read
# this one list.
# ===========================================================================

def dev_names() -> List<&2, String>:
  ["CPU", "GPU", "METAL", "CUDA", "HIP", "CLANG", "LLVM", "PYTHON", "NULL", "DISK"]

def dev_name.tag(t: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, dev_names(), U32.to_nat(t)), "?")

# `repr` of a `str` is the string in single quotes; `repr` of the tuple is the
# parenthesised comma-joined tuple of them, so `D1` quotes and `Dn` does not
# double-quote.
def dev_repr.tags(tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}: Nil{}
    case t <> r: String.concat(["'", dev_name.tag(t), "'"]) <> dev_repr.tags(r)

def dev_repr.tuple(tags: List<&2, U32>) -> String:
  String.concat(["(", String.join(dev_repr.tags(tags), ", "), ")"])

def dev_repr(d: S.Dev) -> String:
  match d:
    case S.D1{tag}: String.concat(["'", dev_name.tag(tag), "'"])
    case S.Dn{tags}: dev_repr.tuple(tags)

# ===========================================================================
# `ParamArg.__repr__` -- ops.py:40-48. A dataclass with a hand-written repr:
#
#     fields = (("vmin_vmax", None), ("multiple_of", None), ("name", None),
#               ("addrspace", AddrSpace.GLOBAL), ("device", None), ("volatile", False),
#               ("image", None), ("bind_on_realize", False), ("val", None))
#     args = [repr(self.slot), repr(self.dtype)] + ([repr(self.size)] if self.size is not None else []) + \
#       [f"{k}={v!r}" for k,default in fields if (v:=getattr(self, k)) != default]
#     if self.buffer is not None: args.append(f"buffer=UOp.new_buffer({self.device!r}, {self.size}, {self.dtype!r}, {self.slot}).buffer")
#     return f"ParamArg({', '.join(args)})"
#
# so the ORDER of the nine keyword fields is load-bearing and a reader that emits
# them in the dataclass's own field order instead gets a different string. Each
# helper below answers `""` or `", " ++ text`, which is what makes the join a
# plain `String.join(.., "")` instead of a filter-and-intercalate.
#
# TWO FIELDS ARE NOT PORTED and both change the string:
#   * `addrspace` is `AddrSpace|None` in Python and `S.Addr` here (ops.bend:697).
#     Python's `None != AddrSpace.GLOBAL`, so a None addrspace PRINTS as
#     `addrspace=None`; the port cannot hold it and prints the space's name.
#   * `buffer` is `Maybe<&2, U32>` here -- a slot into the device allocator -- so
#     the `buffer=UOp.new_buffer(..).buffer` clause is emitted from the SLOT and
#     not from a Buffer object, which is the right text but is a promise that
#     the slot is a realized buffer, since ops.bend's header already notes that
#     the object behind it is P6.
# ===========================================================================

def comma(ok: Bool, s: String) -> String:
  match ok:
    case True{}: String.concat([", ", s])
    case False{}: ""

# The nine keyword fields are emitted in ops.py's own tuple order, and every one
# of them is `""` when Python's `!= default` test would drop it. That makes the
# join a `String.join(.., "")`: a dropped field contributes nothing and shifts
# nothing, which is exactly the list-comprehension's behaviour.
#
# MEASURED, and it is the reason the fields are read through ops.bend's
# accessors rather than through `case O.ParamArg{x}`: a record pattern must name
# EVERY field, imported record or not, so `case O.ParamArg{size}` is refused with
# "a ops.ParamArg pattern with 13 fields". ops.bend:1036-1090 already has the
# thirteen two-line accessors, so nothing here destructures a ParamArg.

# `repr(self.size)` -- positional, so it carries no `k=`.
def pa_size(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: String.concat([", ", U32.show(v)])
    case None{}: ""

def pa_vmin_vmax(r: O.PyRange) -> String:
  match r:
    case O.PyRange{lo, hi}: String.concat(["vmin_vmax=(", sint_i64(lo), ", ", sint_i64(hi), ")"])

def pa_vmin_vmax.of1(m: Maybe<&2, O.PyRange>) -> String:
  match m:
    case Some{r}: comma(True{}, pa_vmin_vmax(r))
    case None{}: ""

# `repr((int, int))` -- the image2d case, ops.py:47.
def pa_image(g: O.Img) -> String:
  match g:
    case O.Img{h, w}: String.concat(["image=(", U32.show(h), ", ", U32.show(w), ")"])

def pa_image.of1(m: Maybe<&2, O.Img>) -> String:
  match m:
    case Some{g}: comma(True{}, pa_image(g))
    case None{}: ""

def pa_multiple_of(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: comma(True{}, U32.show(v))
    case None{}: ""

# `repr(str)` is the string in single quotes; ops.py:46 makes this the field
# that names a PARAM.
def pa_name(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: comma(True{}, String.concat(["name='", s, "'"]))
    case None{}: ""

# the default is GLOBAL, so GLOBAL is the one value that is NOT printed.
def pa_addrspace.is_global(a: S.Addr) -> Bool:
  match a:
    case S.AGlobal{}: True{}
    case _: False{}

def pa_addrspace(+a: S.Addr) -> String:
  comma(Bool.not(pa_addrspace.is_global(a)), String.concat(["addrspace=", addr_repr(a)]))

def pa_device(m: Maybe<&2, S.Dev>) -> String:
  match m:
    case Some{d}: comma(True{}, String.concat(["device=", dev_repr(d)]))
    case None{}: ""

def pa_flag(nm: String, b: Bool) -> String:
  match b:
    case True{}: String.concat([", ", nm, "=True"])
    case False{}: ""

def pa_val(m: Maybe<&2, O.Const>) -> String:
  match m:
    case Some{v}: comma(True{}, String.concat(["val=", const_repr(v)]))
    case None{}: ""

# the `buffer=` clause. `{self.size}` and `{self.dtype}` are `str`, not `repr`,
# and for an int and a DType the two agree; a None size prints `None`.
def pa_buffer.size(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}: "None"

def pa_buffer.device(m: Maybe<&2, S.Dev>) -> String:
  match m:
    case Some{d}: dev_repr(d)
    case None{}: "None"

def pa_buffer.has(m: Maybe<&2, U32>) -> Bool: Maybe.is_some(&2, U32, m)

def pa_buffer.of(has: Bool, slot: U32, dev: String, size: String, dt: String) -> String:
  match has:
    case True{}: String.concat([", buffer=UOp.new_buffer(", dev, ", ", size, ", ", dt, ", ", U32.show(slot), ").buffer"])
    case False{}: ""

def pa_tail(+pa: O.ParamArg) -> List<&2, String>:
  pa_size(O.ParamArg.size(pa)) <> pa_vmin_vmax.of1(O.ParamArg.vmin_vmax(pa)) <> pa_multiple_of(O.ParamArg.multiple_of(pa))
    <> pa_name(O.ParamArg.name(pa)) <> pa_addrspace(O.ParamArg.addrspace(pa)) <> pa_device(O.ParamArg.device(pa))
    <> pa_flag("volatile", O.ParamArg.volatile(pa)) <> pa_image.of1(O.ParamArg.image(pa))
    <> pa_flag("bind_on_realize", O.ParamArg.bind_on_realize(pa)) <> pa_val(O.ParamArg.val(pa))
    <> [pa_buffer.of(pa_buffer.has(O.ParamArg.buffer(pa)), O.ParamArg.slot(pa), pa_buffer.device(O.ParamArg.device(pa)), pa_buffer.size(O.ParamArg.size(pa)), dt_repr(O.ParamArg.dtype(pa)))]

def paramarg_repr(+pa: O.ParamArg) -> String:
  String.concat(["ParamArg(", U32.show(O.ParamArg.slot(pa)), ", ", dt_repr(O.ParamArg.dtype(pa)), String.join(pa_tail(pa), ""), ")"])

# `repr` of the ARG. Wall (d) above: Python dispatches on the runtime type of an
# `Any` and Bend dispatches on a CLOSED DATATYPE, so what is one dynamic `repr`
# in Python is nineteen `match` arms here, one per `Arg` constructor, and every
# one is compiler-checked against the closed set.
#
# The tuple payloads are Python tuples or lists, so their `repr` is
# parenthesised / bracketed with ", " between the elements, and each element is
# itself a `repr`. `Ops.name` is `FastEnum.__repr__`, which is `Ops.ADD`.

def u32_list_repr.go(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: U32.show(h) <> u32_list_repr.go(t)

def u32_list_repr(xs: List<&2, U32>) -> String:
  String.concat(["[", String.join(u32_list_repr.go(xs), ", "), "]"])

# `repr` OF A TUPLE, and the ONE- ELEMENT CASE IS NOT `(x)`.
#
# MEASURED (`repr_1tuple` / `repr_0tuple` / `repr_2tuple` in
# `.agents/slop/xd1/argrepr.py`, both ends agree):
#     repr(())     == '()'
#     repr((0,))   == '(0,)'      <-- THE COMMA
#     repr((0, 1)) == '(0, 1)'
#
# `(0)` is a PARENTHESISED int in Python, not a tuple, so a `repr` that omits the
# comma produces a string `eval_pyrender` would read as something else. This def
# was WRONG before this unit and the gate said so the whole time: the baseline row
# read `arg_repr ARng = [((0), AxisType.GLOBAL)]   py=((0,), AxisType.GLOBAL)` --
# answer and oracle visibly different, with no failure anywhere, because a gate in
# this repo PRINTS the diff rather than failing on it. `agent-core.md`'s "a gate
# that passed before the rename and passes after it has told you nothing" has a
# second form here: a gate that was never READ.
def u32_tuple_repr(+xs: List<&2, U32>) -> String:
  String.concat(["(", String.join(u32_list_repr.go(xs), ", "),
    Bool.pick(String, Nat.is_eq(List.length(&2, U32, xs), 1n), ",", ""), ")"])

# `x.axis_id[0]` -- the HEAD element of an id LIST, printed. It is `U32.show` and
# not `u32_list_repr`'s list form because `x.axis_id[0]` is an int, and an int's
# `repr` IS its `str`. `Maybe.default` is `x.axis_id[0]` on the empty list, which
# Python raises IndexError for and which the guard above makes unreachable; the
# `0` is the arena's bottom so the def is total rather than partial.
def peek_str(xs: List<&2, U32>) -> String:
  U32.show(Maybe.default(&2, U32, List.head(&2, U32, xs), 0))

# `AxisType.__repr__` is `str(self)` and `Enum.__str__` is "ClassName.MEMBER".
def axis_repr(a: O.AxisType) -> String:
  String.concat(["AxisType.", O.AxisType.name(a)])

# `repr(ARange{ids, at})` -- AND THE ORDER IS THE WHOLE OF THIS DEF.
#
# ops.bend's `ARange` is `(ids, at)` -- the PIN's `arg=(axis_id, axis_type)` --
# and that is a DELIBERATE wall (ops.bend:2330-2345: eleven committed files read
# it positionally). Upstream flipped the tuple, so the PRINTED tuple is now
# `(axis_type, *axis_id)` even though the port's RECORD is still `(ids, at)`.
#
# THIS IS THE `type_map` BUG'S SHAPE AND NOTHING ELSE IN THE FILE LOOKS LIKE IT.
# There is no `case` to grep for and no arm to fall through: `arange_repr` takes
# two PARAMETERS, so a wrong order is a wrong STRING on an otherwise correct
# dispatch. MEASURED at both ends (`.agents/slop/xd1/render-oracle.py`):
#
#   pin:  repr(UOp.range(4, 0, WEAK).arg) == '(0, AxisType.WEAK)'
#   head: repr(UOp.range(4, 0, WEAK).arg) == '(AxisType.WEAK, 0)'
#
# And it is REACHABLE, which is what makes it a defect rather than a note: the
# head `Ops.RANGE` rule REFUSES a two-id arg, the refusal falls through to rule
# 15, and rule 15 prints `repr(u.arg)`. So `pyrender flat2` is the row that reads
# this def, and at the pin's order it printed `AxisType.WEAK` where an integer
# belongs -- a valid-looking string that would not `eval`.
#
# `ids` IS THE FLAT TAIL, so there is NO INNER TUPLE: `repr((at, *ids))` is
# `(AxisType.WEAK, 0, 1)` and NOT `(AxisType.WEAK, (0, 1))`. MEASURED at both
# ends, `.agents/slop/xd1/argrepr.py`:
#     pin : repr(UOp.range(4, (0,), GLOBAL).arg)  == '((0,), AxisType.GLOBAL)'
#     head: repr(UOp.range(4, (0,), GLOBAL).arg)  == '(AxisType.GLOBAL, 0)'
#     head: repr(flat-arg-with-2-ids).arg        == '(AxisType.WEAK, 0, 1)'
# The pin's nested `(0,)` is `axis_id = arg[0:-1]` applied to a 2-tuple arg;
# head's `axis_id = arg[1:]` makes the ids the flat tail.
#
# AND THE PORT HAS TO PICK, BECAUSE `ARange{ids, at}` CANNOT NAME THE DIFFERENCE.
# `UOp.range(4, (0,1), WEAK)` builds `arg = (WEAK, (0,1))` and a flat
# `arg = (WEAK, 0, 1)` carries the SAME ids list, so both are `ARange{[0,1],
# WEAK}` -- ONE ucache key for TWO CPython nodes. This def takes head's reading,
# the ids as the flat tail, because that is the one `UOp.axis_id` /
# `UOp.axis_type` in ops.bend already implement and the one the `Ops.RANGE`
# rule's `len(axis_id) == 1` guard is stated in. The collision is ops.bend's
# `ARange{ids, at}` wall (ops.bend:2330-2345) SEEN FROM THE OTHER SIDE, and it
# is recorded here rather than papered over.
def arange_repr(ids: List<&2, U32>, at: O.AxisType) -> String:
  String.concat(["(", axis_repr(at), ", ", String.join(u32_list_repr.go(ids), ", "), ")"])

def awmma_repr(dims: List<&2, U32>, dt: S.Dt, th: U32, tc: List<&2, U32>) -> String:
  String.concat(["([", String.join(u32_list_repr.go(dims), ", "), "], ", dt_repr(dt), ", ", U32.show(th), ", [", String.join(u32_list_repr.go(tc), ", "), "])"])

def aink_repr(ins: String, dt: S.Dt) -> String:
  String.concat(["('", ins, "', ", dt_repr(dt), ")"])

# `repr(Ops.ADD)` is `"Ops.ADD"`, because `FastEnum.__repr__` is `str(self)` and
# `Enum.__str__` is `"ClassName.MEMBER"`. ops.bend's `Ops.name` now answers
# exactly that, so this def is GONE and its call sites read `Ops.name` directly.
# It was the local correction this file used to carry while ops.bend returned the
# bare member name.

def aallred_repr(rop: O.Op, dev: S.Dev) -> String:
  String.concat(["(", O.Ops.name(rop), ", ", dev_repr(dev), ")"])

def areduce_repr(rop: O.Op, num_axes: U32) -> String:
  String.concat(["(", O.Ops.name(rop), ", ", U32.show(num_axes), ")"])

def acall_name(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: String.concat(["'", s, "'"])
    case None{}: "None"

# `dt is dtypes.void` is a CLASS test, not a priority test. `S.void()` is
# `Dt{0, 0, CVoid{}, "void"}` and `S.weakint()` is `Dt{0, 800, CWeakInt{}}` --
# BOTH have priority 0, so `pri == 0` is a test that passes void AND weakint and
# so it is wrong. `Cls.CVoid` is the field that means void, and it is the ONLY
# dtype with it, which is why matching on it is the whole test.
def acall_void.cls(cls: S.Cls) -> Bool:
  match cls:
    case S.CVoid{}: True{}
    case _: False{}

def acall_void(dt: S.Dt) -> Bool:
  match dt:
    case S.Dt{pri, bits, cls, nm}: acall_void.cls(cls)

# `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE (upat note 9), so the
# NON-void branch is first and `isvoid` flips it. Getting this backwards emits
# `CallInfo(None, None, False, False)` for every dtype, which is exactly what
# the three `ACALL` rows above caught.
def acall_tail.isvoid(isvoid: Bool, dt: S.Dt) -> String:
  Bool.pick(String, Bool.not(isvoid), String.concat([", dtype=", dt_repr(dt), ")"]), ")")

# `CallInfo.of()` is `CallInfo{None, False, False, dtypes.void}` (ops.bend:846),
# so the void arm of the repr above is the ONE that the gate would otherwise
# never reach. `ci_named` is the other arm, and the two together mean a dtype
# bug cannot pass by only ever printing void.
def ci_named() -> O.CallInfo:
  O.CallInfo{Some{"f"}, False{}, False{}, S.int32()}

# `weakint` is the dtype that makes the void test load-bearing: it has priority
# 0 like void, so a `pri == 0` void test would print `dtype=` for it and a
# `cls == CVoid` test does not.
def ci_weak() -> O.CallInfo:
  O.CallInfo{None{}, False{}, False{}, S.weakint()}

def acall_tail(+dt: S.Dt) -> String: acall_tail.isvoid(acall_void(dt), dt)

# `CallInfo.__repr__` (ops.py:1400-1403):
#
#     gf = id(self.grad_fxn) if self.grad_fxn else None
#     return f"CallInfo({gf}, {repr(self.name)}, {self.precompile}, {self.precompile_backward" + \
#       (f", dtype={self.dtype})" if self.dtype is not dtypes.void else ")")
#
# The dtype is printed only when it is not void, and THE CLOSING PAREN MOVES WITH
# IT -- so the tail is one of two whole strings, not a suffix. ops.bend:836
# DROPPED `grad_fxn` (it is a Python function object), so `gf` is always None.
def acall_repr(+ci: O.CallInfo) -> String:
  String.concat(["CallInfo(None, ", acall_name(O.CallInfo.name(ci)), ", ", Bool.show(O.CallInfo.precompile(ci)), ", ", Bool.show(O.CallInfo.precompile_backward(ci)), acall_tail(O.CallInfo.dtype(ci))])

# `estimates` is a field ops.bend DROPPED (P5, tinygrad.renderer) and Python's
# dataclass repr prints it, so the literal below is printed in its place. It is
# None for every kernel this port can build, so the text agrees -- but it IS a
# literal, and saying so is cheaper than pretending the field is carried.
def akernel_estimates(m: Maybe<&2, List<&2, U32>>) -> String: "estimates=None"

# `applied_opts` is a tuple of `Opt`, which ops.bend carries as UOp INDICES, and
# a real `Opt`'s repr is a dataclass repr the port cannot read. A kernel with
# options applied prints `()` for a field that is not empty.
def akernel_applied(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "()"
    case _ <> _: "<Opt>"

def akernel_repr(+ki: O.KernelInfo) -> String:
  String.concat(["KernelInfo(name='", O.KernelInfo.name(ki), "', applied_opts=", akernel_applied(O.KernelInfo.applied_opts(ki)), ", opts_to_apply=None, ", akernel_estimates(O.KernelInfo.opts_to_apply(ki)), ", beam=", U32.show(O.KernelInfo.beam(ki)), ")"])

# `repr(tuple(int|float, ...))`; ops.bend types both halves `H.I64`.
def i64_tuple_repr.go(xs: List<&2, H.I64>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: sint_i64(h) <> i64_tuple_repr.go(t)

def i64_tuple_repr(xs: List<&2, H.I64>) -> String:
  String.concat(["(", String.join(i64_tuple_repr.go(xs), ", "), ")"])

# `vars` and `target` are both fields ops.bend cannot print: `vars` is a tuple of
# UOPs (so its repr is `pretty_print` of each, which is `pretty_print`'s own
# recursion) and `target` is a `Target` dataclass dropped at ops.bend:801.
def aprogram_vars(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "()"
    case _ <> _: "<UOp>"

# `Target()`'s repr is `Target(device=None, ...)`, and the measured empty repr
# of a `Target` is the empty string -- `helpers.py`'s dataclass has no fields
# set, so `target=` with nothing after it. That is measured, not guessed.
def aprogram_repr(+pi: O.ProgramInfo) -> String:
  String.concat(["ProgramInfo(global_size=", i64_tuple_repr(O.ProgramInfo.global_size(pi)), ", local_size=", i64_tuple_repr(O.ProgramInfo.local_size(pi)), ", vars=", aprogram_vars(O.ProgramInfo.vars(pi)), ", globals=", u32_tuple_repr(O.ProgramInfo.globals(pi)), ", outs=", u32_tuple_repr(O.ProgramInfo.outs(pi)), ", ins=", u32_tuple_repr(O.ProgramInfo.ins(pi)), ", target=)"])

def arg_repr(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "None"
    case O.ADt{dt}: dt_repr(dt)
    case O.APy{v}: const_repr(v)
    case O.AParam{pa}: paramarg_repr(pa)
    case O.ACall{ci}: acall_repr(ci)
    case O.AKernel{ki}: akernel_repr(ki)
    case O.AProgram{pi}: aprogram_repr(pi)
    case O.ARange{ids, at}: arange_repr(ids, at)
    case O.AReduce{rop, num_axes}: areduce_repr(rop, num_axes)
    case O.AWmma{dims, dt, threads, tc}: awmma_repr(dims, dt, threads, tc)
    case O.ATuple{ys}: u32_tuple_repr(ys)
    case O.AStr{s}: String.concat(["'", s, "'"])
    case O.AInk{ins, dt}: aink_repr(ins, dt)
    case O.AAllred{rop, dev}: aallred_repr(rop, dev)
    case O.ADev{dev}: dev_repr(dev)
    case O.ABlob{n}: String.concat(["<bytes ", U32.show(n), ">"])
    case O.AFloat{f}: f32_repr(f)
    case O.ABad{}: "ABad"

    case O.ABad{}: "ABad"

# ===========================================================================
# `tagstr` / `repr(tag)` -- ops.py:275 and render.py:136. `str` and `repr` of a
# `Tag` DISAGREE on the `str` arm (`x` vs `'x'`), so they are two defs and not
# one with a flag: `tagstr` is a f-string (render.py:14) and `_render_with_splits`
# appends `repr(u.tag)`.
#
# `TTuple` is the WALL and it is ops.bend's, not mine: a tag tuple holds UOPS
# (ops.bend:766-770), so Python's `repr` of one is `pretty_print` of each and
# `pretty_print` is the def that reads `tagstr`. That is a real cycle and the
# port cannot break it by ordering, so this answers the count instead of a
# string -- visible, not wrong.
# ===========================================================================

def tag_str.go(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: "<UOp>" <> tag_str.go(t)

def tag_str(t: O.Tag) -> String:
  match t:
    case O.TNone{}: "None"
    case O.TBool{b}: Bool.show(b)
    case O.TStr{s}: s
    case O.TInt{i}: U32.show(i)
    case O.TTuple{xs}: String.concat(["(", String.join(tag_str.go(xs), ", "), ")"])

def tag_repr(t: O.Tag) -> String:
  match t:
    case O.TNone{}: "None"
    case O.TBool{b}: Bool.show(b)
    case O.TStr{s}: String.concat(["'", s, "'"])
    case O.TInt{i}: U32.show(i)
    case O.TTuple{xs}: String.concat(["(", String.join(tag_str.go(xs), ", "), ")"])

# `UOp.tagstr` -- ops.py:275, `f", tag={self.tag}" if self.tag is not None else ""`
def tag_is_none(t: O.Tag) -> Bool:
  match t:
    case O.TNone{}: True{}
    case _: False{}

def tagstr.of(t: O.Tag, isnone: Bool) -> String:
  Bool.pick(String, isnone, "", String.concat([", tag=", tag_str(t)]))

def tagstr(+t: O.Tag) -> String:
  tagstr.of(t, tag_is_none(t))

# ===========================================================================
# `syms` -- render.py:25. `for debug`: the spelling of each binary operator, and
# it is a `dict` Python never adds to. Eleven arms and a `_`, and the `_` is
# `KeyError` in Python -- but both readers only ever reach it for an op the
# `UPat(set(syms.keys()))` rules matched, so it is unreachable and answers "".
# ===========================================================================

def syms_of(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "+"
    case O.OpsSUB{}: "-"
    case O.OpsFLOORDIV{}: "//"
    case O.OpsFLOORMOD{}: "%"
    case O.OpsSHL{}: "<<"
    case O.OpsSHR{}: ">>"
    case O.OpsMUL{}: "*"
    case O.OpsCMPLT{}: "<"
    case O.OpsCMPNE{}: "!="
    case O.OpsAND{}: "&"
    case O.OpsOR{}: "|"
    case O.OpsXOR{}: "^"
    case _: ""

# ===========================================================================
# `precedence` -- render.py:28. Eleven entries, and the readers ask
# `precedence.get(x.op, 99)`, so the missing arm is 99 rather than a KeyError.
# 99 IS A CONSTANT HERE, not a magic number: it is `precedence.get`'s default.
# ===========================================================================

def precedence_of(op: O.Op) -> U32:
  match op:
    case O.OpsMUL{}: 1
    case O.OpsFLOORDIV{}: 1
    case O.OpsFLOORMOD{}: 1
    case O.OpsADD{}: 2
    case O.OpsSUB{}: 2
    case O.OpsSHL{}: 3
    case O.OpsSHR{}: 3
    case O.OpsAND{}: 4
    case O.OpsXOR{}: 5
    case O.OpsOR{}: 6
    case _: 99

# `x.op not in precedence`
def has_precedence(op: O.Op) -> Bool: U32.is_lt(precedence_of(op), 99)

# ===========================================================================
# `strip_binary_parens` -- render.py:29.
#
# `code_for_op` IS INLINED, and that is the one closure this file drops. Both
# call sites (render.py:65 and render.py:113) pass the SAME body,
# `lambda a,b: f"({a}{syms[x.op]}{b})"`, so inlining it is the identity on this
# program rather than a specialisation of a general parameter. Had the two
# differed, this def would need a tag for "which code_for_op" and the arms would
# be duplicated; nothing in render.py does that.
#
# The `if` is not decoration. CDIV and CMOD are in `syms` and NOT in
# `precedence`, so they reach the first line and the srcs are never read -- which
# is why `has_precedence` is a parameter of the arm rather than a second `if`.
# ===========================================================================

# `strip_parens(left) if precedence.get(x.src[0].op, 99) <= p else left`
def sbp_operand(has: Bool, +ar: O.Arena, u: U32, n: U32, p: U32, +s: String) -> String:
  Bool.pick(String, Bool.and(has, U32.is_le(precedence_of(O.Arena.op(ar, O.Arena.src(ar, u, n))), p)), H.strip_parens(s), s)

def sbp_arm(+has: Bool, +ar: O.Arena, +u: U32, +p: U32, +left: String, +right: String) -> String:
  String.concat(["(", sbp_operand(has, ar, u, 0, p, left), syms_of(O.Arena.op(ar, u)), sbp_operand(has, ar, u, 1, p, right), ")"])

def strip_binary_parens(+ar: O.Arena, +u: U32, left: String, right: String) -> String:
  sbp_arm(has_precedence(O.Arena.op(ar, u)), ar, u, precedence_of(O.Arena.op(ar, u)), left, right)

# ===========================================================================
# `range_str` -- ops.py:97. Rebuilt here because it is ABSENT from ops.bend
# (ops.bend:537 says "range_str does not read it", i.e. ops.py's own note that
# the op is not consulted -- it is `AxisType` that matters and that IS in
# ops.bend). `AxisType`, `axis_colors` and `sint_show` are all present, so this
# is three lines and no new machinery.
#
#     ret = '_'.join([str(x) if x >= 0 else "m"+str(-x) for x in u.axis_id])
#     return colored(ret, axis_colors[u.axis_type]) if color else ret
#
# `axis_id` is `arg[0:-1]` -- the arg's id list MINUS THE LAST element -- and
# ops.bend carries a RANGE's arg as `ARange{ids, at}`, where `ids` IS the whole
# `(axis_id, axis_type)` pair with the type lifted out. So the Python slice is
# exactly `ids` here, and that is the one place the two representations meet.
# ===========================================================================

# `str(x) if x >= 0 else "m"+str(-x)`. The ids are non-negative for every RANGE
# tinygrad builds, so the `m` arm is unreachable in practice -- but it is
# reachable for a hand-built arena and the header already records `sint_show`'s
# int32 limit, so it is spelled out rather than dropped.
def range_str.one(+x: U32) -> String:
  Bool.pick(String, sint_show.half(x), String.concat(["m", sint_show(U32.sub(0, x))]), sint_show(x))

def range_str.go(ids: List<&2, U32>) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case h <> t: range_str.one(h) <> range_str.go(t)

def range_str.of(at: O.AxisType, +ids: List<&2, U32>) -> String:
  String.join(range_str.go(ids), "_")


# `colored(ret, axis_colors[u.axis_type])`. `H.colored` needs the `Flags` record
# (NO_COLOR is a ContextVar there), and `color=False` in Python is exactly
# "return ret unchanged", so the flag is the parameter.
def range_str.color(f: H.Flags, at: O.AxisType, s: String) -> String:
  H.colored(f, s, H.color_of(O.axis_colors(at)), False{})

# ===========================================================================
# `multirange_str` -- ops.py:101.
#
#     ret = ','.join([range_str(x, color=color) for x in sorted(rngs, key=lambda x: x.arg)])
#     if pad is not None: ret += " " * (pad-ansilen(ret))
#
# THE SORT IS BY `x.arg`, and a RANGE's arg is `(axis_id, axis_type)`. Python
# compares the two TUPLES, so the order is: the id lists lexicographically, and
# on a tie the AxisType by its declaration number. `List.sort` wants a `le` on
# the ELEMENT and a closure cannot be spelled, so the sort is an insertion sort
# here and `le` is a top-level def.
#
# ONE SELF-CALL, and `+` ON THE PATTERN BINDERS. Two answers come out of the head
# comparison and both feed one expression, and a binder read twice needs `+`; a
# helper def does not rescue it, because it would call back into `lt_u32` and
# that is the mutual recursion Bend refuses. `case +h <> t:` is the spelling, and
# it is only available because `U32` is `Data`.
def lt_u32(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t:
      match ys:
        case Nil{}: True{}
        case +g <> u: Bool.or(U32.is_lt(h, g), Bool.and(U32.is_eq(h, g), lt_u32(t, u)))

# on equal id lists the tie is broken by the AxisType's declaration number,
# which is exactly what Python's Enum ordering is. The ids list is `+` because
# the comparison and the tie-break both read it in one body.
def range_lt.put(idslt: Bool, +xs: List<&2, U32>, atx: O.AxisType, aty: O.AxisType) -> Bool:
  Bool.pick(Bool, idslt, U32.is_lt(O.AxisType.value(atx), O.AxisType.value(aty)), False{})

# a `match` may only scrutinise a parameter, so each destructuring step is its
# own def
def range_lt.ids2(y: O.Arg, +xs: List<&2, U32>, atx: O.AxisType) -> Bool:
  match y:
    case O.ARange{ys, aty}: range_lt.put(lt_u32(xs, ys), xs, atx, aty)
    case _: False{}

def range_lt.ids(x: O.Arg, y: O.Arg) -> Bool:
  match x:
    case O.ARange{xs, atx}: range_lt.ids2(y, xs, atx)
    case _: False{}

def range_lt.of(x: O.Arg, y: O.Arg) -> Bool:
  range_lt.ids(x, y)

def range_lt(+ar: O.Arena, x: U32, y: U32) -> Bool:
  range_lt.of(O.Arena.arg(ar, x), O.Arena.arg(ar, y))

# ONE SELF-CALL again: the decision and the insertion are the same expression, so
# `u32_ins` matches and picks in its own body and there is no helper to be
# mutually recursive with.
def u32_ins(+ar: O.Arena, +x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match acc:
    case Nil{}: [x]
    case h <> t: Bool.pick(List<&2, U32>, range_lt(ar, x, h), x <> acc, h <> u32_ins(ar, x, t))

def u32_isort.go(+ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: u32_isort.go(ar, t, u32_ins(ar, h, acc))

def u32_isort(ar: O.Arena, xs: List<&2, U32>) -> List<&2, U32>: u32_isort.go(ar, xs, Nil{})

# `ret += " " * (pad-ansilen(ret))`. `pad` can be SHORTER than the string and
# Python's `" " * negative` is `""`, so the count is clamped at zero rather than
# trusted: `Nat.sub` is not saturating and a negative count is a proof failure,
# not an empty string.
def multirange_str.n(+sd: Nat, +n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(n, sd), Nat.sub(sd, n), 0n)

def multirange_str.pad(+s: String, sd: U32) -> String:
  String.concat([s, String.repeat(" ", multirange_str.n(U32.to_nat(sd), String.length(s)))])

def range_at.of(a: O.Arg) -> O.AxisType:
  match a:
    case O.ARange{ids, at}: at
    case _: O.AXIS_LOOP{}

def range_at(+ar: O.Arena, u: U32) -> O.AxisType:
  range_at.of(O.Arena.arg(ar, u))

def range_ids.of(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.ARange{ids, at}: ids
    case _: Nil{}

def range_ids(+ar: O.Arena, u: U32) -> List<&2, U32>:
  range_ids.of(O.Arena.arg(ar, u))

# `range_str(x, color=color)` -- ONE range, so the `range_str.of` and the
# `range_str.color` are a single line here rather than the two-call shape.
def multirange_str.of(+f: H.Flags, +at: O.AxisType, +ids: List<&2, U32>) -> String:
  range_str.color(f, at, range_str.of(at, ids))

def multirange_str.go(+f: H.Flags, +ar: O.Arena, rngs: List<&2, U32>) -> List<&2, String>:
  match rngs:
    case Nil{}: Nil{}
    case +u <> t: multirange_str.of(f, range_at(ar, u), range_ids(ar, u)) <> multirange_str.go(f, ar, t)

def multirange_str(+f: H.Flags, +ar: O.Arena, +rngs: List<&2, U32>, pad: U32) -> String:
  multirange_str.pad(String.join(multirange_str.go(f, ar, u32_isort(ar, rngs)), ","), pad)

# ===========================================================================
# THE CTX. `ctx: dict[UOp, str]` in Python, threaded through `pm.rewrite` and
# through every rule lambda. It is the ONLY mutable-looking structure pyrender
# has, and it is the reason `Map` (a string-keyed patricia tree, and the one
# collection Python's dict and Bend's Map agree about without an encoding) is
# the answer here.
#
# THE KEY IS `U32.show(u)`. That is honest rather than a trick: Python's key is
# a UOp OBJECT and the arena index IS the UOp, so decimal is the identity
# encoding, and the notes' warning ("an index is only meaningful in the arena
# that produced it") holds -- which is why `Ctx` never leaves the `pyrender`
# call and the gate asserts on it inside one arena only.
#
# `Map.put` IS `Map.set` HERE and the difference is not cosmetic: `Map.put` on a
# one-entry `MLeaf` REPLACES the leaf and drops the old key, which MEASURED as
# `d[1]=three d[2]= d[3]=` for three sequential puts. `Map.set` is the one that
# inserts. That is a new Bend rule and it is in the constraints file.
# ===========================================================================

type Ctx is Data:
  Ctx{m: Map<&2, String>}

def Ctx.map(c: Ctx) -> Map<&2, String>:
  match c:
    case Ctx{m}: m

def ctx_new() -> Ctx: Ctx{Map.new(&2, String)}

def ctx_put(c: Ctx, u: U32, s: String) -> Ctx:
  Ctx{Map.set(&2, String, Ctx.map(c), U32.show(u), s)}

def ctx_get.of(r: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
  match r:
    case Tuple{m, v}: v

# `ctx[x]` is a KeyError in Python and "" here. Every read in `pm_pyrender` is
# of a SRC, and `_render_with_splits` walks `lst` in toposort order, so every
# src was written first: the default is unreachable and says so.
def ctx_get(c: Ctx, u: U32) -> String:
  ctx_get.of(Map.get(String, "", Ctx.map(c), U32.show(u)))

# `Map.has` answers a `Sigma`, not a Maybe, so the Bool rides out in the second
# half of the pair -- the same destructuring `ctx_get.of` does.
def ctx_has.of(r: Sigma<&1, &1, Map<&2, String>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def ctx_has(c: Ctx, u: U32) -> Bool:
  ctx_has.of(Map.has(&2, String, Ctx.map(c), U32.show(u)))

# ===========================================================================
# `srcs` -- render.py:84.
#
#     def srcs(ctx, src): return f"({ctx[src[0]]},)" if len(src) == 1 else f"({', '.join([ctx[x] for x in src])})"
#
# The `len(src) == 1` SPECIAL CASE is the load-bearing part and it is a trailing
# COMMA in parentheses, not a one-element join: `(x,)` and `(x)` are different
# Python literals, and only the first round-trips through `eval_pyrender`. A join
# that ignored the case would emit `(x)` and the exec would build a bare name
# instead of a tuple.
# ===========================================================================

def srcs.go(+c: Ctx, srcs: List<&2, U32>) -> List<&2, String>:
  match srcs:
    case Nil{}: Nil{}
    case u <> t: ctx_get(c, u) <> srcs.go(c, t)

# `src[0]` in Python does not need an arena because a UOp knows its own srcs;
# here the list IS the srcs, so the head is the answer.
def srcs_one(+c: Ctx, +srcs: List<&2, U32>) -> String:
  String.concat(["(", ctx_get(c, Maybe.default(&2, U32, List.head(&2, U32, srcs), 0)), ",)"])

# ONE expression, not a helper: `Bool.pick` is strict, so both arms are computed
# either way, and a helper would want the ctx twice. `Nat.is_eq(len, 1n)` IS the
# `len(src) == 1` test.
def srcs(+c: Ctx, +srcs: List<&2, U32>) -> String:
  Bool.pick(String, Nat.is_eq(List.length(&2, U32, srcs), 1n), srcs_one(c, srcs), String.concat(["(", String.join(srcs.go(c, srcs), ", "), ")"]))

# ===========================================================================
# THE pm_pyrender RULES, compiled. render.py:88-123 is fifteen `UPat`s, and the
# NOTE above them says "you can remove pm_pyrender_extra and it'll still be
# correct" -- which is TRUE, and is exactly why the rules are a `match` on the op
# rather than a table: thirteen of them are special cases that FALL THROUGH to
# the GroupOp.All rule when their guard fails, so first-wins and the fallback
# compose into one dispatch rather than fifteen attempts.
#
# Rule order is load-bearing TWICE:
#   * `REDUCE` is claimed by rule 7 (when `arg[1]` is nonzero) AND by the `sugar`
#     rules. Rule 7 is earlier, so a REDUCE with num_axes 0 renders as
#     `c0.reduce()` and one with num_axes 3 as `c0._rop(Ops.ADD, (0, 1, 2))`.
#   * `SUB` is in `syms` and NOT in rule 12's set (`syms - {SUB, CDIV, CMOD}`), so
#     it goes straight to the fallback and prints `UOp(Ops.SUB, (..))`. That is
#     why the arm list below omits it, and the gate pins it.
# ===========================================================================

# `x.op.name.lower()` -- in five rules, one measurement. `name` is the BARE
# member and `Ops.name` is the `ClassName.MEMBER` form, so this reads `.name.of`.
def op_lower(op: O.Op) -> String: String.to_lower(O.Ops.name.of(op))

def dt_of.of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

# `x.dtype`. It is a FOLD (fold.bend:1949), not an arena read, so it is threaded
# as the table `tb` alongside the arena -- and the `void` default is Python's
# "the fold did not settle this node", which is a wrong answer rather than a
# crash. `Kahn.settled` is the honest question and the gate rows are all built
# from a settled fold.
def dt_of(tb: F.Table, ar: O.Arena, u: U32) -> S.Dt:
  dt_of.of(F.fold.dt(ar, tb, u))

# `x.arg is not None` -- `ANone` is Python's None, so this is a one-arm match on
# a CLOSED datatype instead of an identity test.
def ismeta_of(a: O.Arg) -> Bool:
  match a:
    case O.ANone{}: False{}
    case _: True{}

# RULE 15, the fallback. `f"UOp({u.op}, {srcs(ctx,u.src)}" + (f", {repr(u.arg)})"
# if u.arg is not None else ")")` -- so the CLOSING PAREN rides the same
# conditional, exactly as in `acall_repr`.
def pmp.fb.args.of(ismeta: Bool, +s: String) -> String:
  Bool.pick(String, ismeta, String.concat([", ", s, ")"]), ")")

def pmp.fb.args(a: O.Arg, ismeta: Bool) -> String:
  pmp.fb.args.of(ismeta, arg_repr(a))

def pmp.fb.of(ismeta: Bool, +ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  String.concat(["UOp(", O.Ops.name(O.Arena.op(ar, u)), ", ", srcs(ctx, O.Arena.srcs(ar, u)), pmp.fb.args(O.Arena.arg(ar, u), ismeta)])

def pmp.fb(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.fb.of(ismeta_of(O.Arena.arg(ar, u)), ar, ctx, u)

# `str(x.val)` -- the CONST's value, NOT `repr`. For an int the two agree and for
# a ConstFloat they do NOT (`repr` is `ConstFloat(2.5)` and `str` is `2.5`), so
# these are two different defs and the fixtures use both.
def val_str.v(v: O.Const) -> String:
  match v:
    case O.CBool{b}: Bool.show(b)
    case O.CInt{i}: sint_i64(i)
    case O.CFloat{f}: f32_repr(f)
    case O.CInvalid{}: "Invalid"

def val_str.of(a: O.Arg) -> String:
  match a:
    case O.APy{v}: val_str.v(v)
    case _: "?"

def val_str(a: O.Arg) -> String: val_str.of(a)

# RULE 1: `UPat(Ops.CONST, src=())` -> `f"UOp.const({x.val})"`. A CONST WITH a
# src falls through to the fallback -- `pyrender` never makes one, but the rule
# says `src=()` and the guard is the rule.
def pmp.const.of(zero: Bool, +ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, zero, String.concat(["UOp.const(", val_str(O.Arena.arg(ar, u)), ")"]), pmp.fb(ar, ctx, u))

def pmp.const(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.const.of(U32.is_zero(O.Arena.nsrc(ar, u)), ar, ctx, u)

def dt_same.of(a: S.Dt, b: S.Dt) -> Bool: O.eq_dt(a, b)

# RULE 2: `UPat((Ops.CAST, Ops.BITCAST))` ->
#   `f"{ctx[x.src[0]]}.{x.op.name.lower()}({x.dtype})"` if `x.dtype != x.src[0].dtype`
# else None, and a None return FALLS THROUGH to the next rule. This is the
# measured reason `cast_same` above still renders `UOp.const(3.0).cast(dtypes.f32)`
# -- no: the fixture that shows the fall-through is a CAST whose dtype already
# equals its src's.
def pmp.cast.of(same: Bool, +ar: O.Arena, tb: F.Table, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, same, pmp.fb(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".", op_lower(O.Arena.op(ar, u)), "(", dt_repr(dt_of(tb, ar, u)), ")"]))

# `x.dtype != x.src[0].dtype`
def dt_same(+tb: F.Table, +ar: O.Arena, +u: U32) -> Bool:
  dt_same.of(dt_of(tb, ar, u), dt_of(tb, ar, O.Arena.src0(ar, u)))

# a `match` may not scrutinise a call, so the op read is its own def -- twice,
# for the two readers
def is_const.of(op: O.Op) -> Bool:
  match op:
    case O.OpsCONST{}: True{}
    case _: False{}

def is_const(ar: O.Arena, u: U32) -> Bool: is_const.of(O.Arena.op(ar, u))

# RULE 3: `UPat(Ops.SPECIAL, src=(UPat(Ops.CONST),))` -> `f"UOp.special({x.src[0].val}, {repr(x.arg)})"`.
# The tuple is EXACTLY one element, so a two-src SPECIAL -- which is what a
# `device_range_src` SPECIAL carries -- misses and falls through. Measured.
def pmp.special.of(one: Bool, isconst: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(one), pmp.fb(ar, ctx, u),
    Bool.pick(String, Bool.not(isconst), pmp.fb(ar, ctx, u),
      String.concat(["UOp.special(", val_str(O.Arena.arg(ar, O.Arena.src0(ar, u))), ", ", arg_repr(O.Arena.arg(ar, u)), ")"])))

def pmp.special(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.special.of(Nat.is_eq(List.length(&2, U32, O.Arena.srcs(ar, u)), 1n), is_const(ar, O.Arena.src0(ar, u)), ar, ctx, u)

# ===========================================================================
# RULE 4 IS GONE. `78d482262` DELETED the `Ops.BUFFER` pyrender rule:
#
#   # NOTE: multi-device buffers carry the DEVICE range in src, new_buffer recreates it
#   (UPat(Ops.BUFFER, name="x"), lambda x:
#     f"UOp.new_buffer({repr(x.arg.device)}, {x.max_numel()}, {x.dtype}, {x.arg.slot})"
#     if isinstance(x.arg, ParamArg) and x.addrspace is AddrSpace.GLOBAL else None),
#
# and it is the only reason `render.py` still imported `AddrSpace` -- head's
# line 1 is `from tinygrad.dtype import dtypes`, the pin's is
# `from tinygrad.dtype import AddrSpace, dtypes`. So the rule's deletion is also
# visible as an IMPORT disappearing, and that import was the tell that no other
# rule in the file needed it.
#
# WHAT A DELETION DOES TO A FIRST-WINS DISPATCH, and it is not "the answer
# changes": a BUFFER now reaches NO pyrender rule and lands on rule 15, which is
# `f"UOp({u.op}, {srcs(ctx,u.src)}" + (f", {repr(u.arg)})" if u.arg is not None
# else ")")`. So the printed form stops being a `UOp.new_buffer(...)` CALL and
# becomes a constructor with the ParamArg inline. MEASURED, and the two halves
# are different failures:
#
#   pin:  ast = UOp.new_buffer('CPU', 4, dtypes.int, 0)
#   head: ast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU'))
#
# The `UOp.new_buffer` SPELLING is what a `UOp` constructor cannot parse, so
# this is not cosmetic: `test_pyrender`'s `eval_pyrender` would have built a
# BUFFER instead of calling the constructor.
#
# THE THREE DEAD DEFS BELOW WENT WITH IT, and each one is named here because a
# def that outlives its only caller is the `hcq2.bend` `slots_of` shape:
# `paramarg_of`, `arg_addr` and `addr_is_global` existed ONLY to build rule 4's
# guard, and `max_numel` only to build its payload. Nothing else in the file
# reads them and nothing outside the file calls them (`rg` over every `.bend`),
# so deleting the rule without deleting them would leave four defs that compile,
# are named in no header row, and reach no row. That is the header claim
# outliving the code, which `.agents/slop/notes/bend2-constraints.md` records
# as the `hcq2.bend` sixteen-symbol finding.
#
# `addr_is_global` also died with `AddrSpace.GLOBAL`, which upstream's `dtype.py`
# still has -- so its absence is a DELETION here and not a substrate gap.
# ===========================================================================

# RULE 5: `UPat(Ops.COPY, src=(UPat(name="x"),), allow_any_len=True, name="copy")`
#   -> `f"{ctx[x]}.copy_to_device({repr(copy.arg)})"`. `allow_any_len` means the
# ONE src pattern matches any non-empty src list, so the guard is nsrc >= 1.
def pmp.copy.of(any: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(any), pmp.fb(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".copy_to_device(", arg_repr(O.Arena.arg(ar, u)), ")"]))

def pmp.copy(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.copy.of(Nat.is_le(1n, List.length(&2, U32, O.Arena.srcs(ar, u))), ar, ctx, u)

# RULE 6: `UPat(Ops.CUSTOM_FUNCTION)` ->
#   `f"UOp(Ops.CUSTOM_FUNCTION, src={srcs(ctx, x.src)}, arg={x.arg!r})"`.
# The `src=` KEYWORD is literal here and not in rule 15 -- tinygrad writes the
# keyword in one and not the other, and a differential catches it.
def pmp.cfn(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  String.concat(["UOp(Ops.CUSTOM_FUNCTION, src=", srcs(ctx, O.Arena.srcs(ar, u)), ", arg=", arg_repr(O.Arena.arg(ar, u)), ")"])

def reduce_op.of(a: O.Arg) -> String:
  match a:
    case O.AReduce{rop, num_axes}: O.Ops.name(rop)
    case _: "?"

def reduce_op(ar: O.Arena, u: U32) -> String: reduce_op.of(O.Arena.arg(ar, u))

def reduce_axes.of(a: O.Arg) -> U32:
  match a:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

def reduce_axes(ar: O.Arena, u: U32) -> U32: reduce_axes.of(O.Arena.arg(ar, u))

# `tuple(range(n))` for a U32 n, as a `Nat` COUNTDOWN because a U32 countdown is
# not a decreasing argument. `case 1n+p:` leaves `p == n-1`, which is both the
# next fuel and the value to cons.
# the value consed is the SAME `p` the fuel decrements to, so it is bound once
# with `+` and forwarded to both -- the constraint note's `flatands.go` fix
def range_tuple.go(n: Nat, +p: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+q: range_tuple.go(q, Nat.add(p, 1n), List.append(&2, U32, acc, [U32.from_nat(p)]))

def range_tuple(n: U32) -> String:
  String.concat(["(", String.join(u32_list_repr.go(range_tuple.go(U32.to_nat(n), 0n, Nil{})), ", "), ")"])

# ===========================================================================
# RULE 8, REWRITTEN UPSTREAM. `78d482262` changed both the BODY and the arity
# of the test, so re-pointing the string was not the work:
#
#   pin:  "UOp.range("+', '.join([str(c.val)] + [repr(y) for y in x.arg])
#           + (f', src={srcs(ctx, x.src[1:])}' if len(x.src) > 1 else '')+")"
#   head: f"UOp.range({c.val}, {x.axis_id[0]}, {x.axis_type}"
#           + (f', src={srcs(ctx, x.src[1:])}' if len(x.src) > 1 else '')+")"
#           if len(x.axis_id) == 1 else None
#
# TWO SEPARATE MOVES, and the second is the dangerous one.
#
# (1) THE BODY. `x.arg` was `arg[0:-1]` at the pin and is `arg[1:]` at head
#     (`axis_id`), so the old rule walked the WHOLE arg and printed
#     `UOp.range(4, AxisType.WEAK, 0)` on a head tree -- the AxisType where the
#     id belongs. The new rule names `axis_id[0]` and `axis_type`, which is the
#     same three values in the order the constructor takes them, so the PRINTED
#     string for a one-id RANGE is `UOp.range(4, 0, AxisType.WEAK)` at both
#     ends. MEASURED, `.agents/slop/xd1/render-rows.py` rows `pyrender range`
#     and `pyrender range2` are byte-identical across the window.
#
# (2) THE NEW GUARD, `len(x.axis_id) == 1`, and it is a GUARD, not a filter: a
#     RANGE with two ids returns None and FALLS THROUGH to rule 15, which
#     prints `repr(u.arg)` -- so the answer stops being a `UOp.range(...)` call
#     and becomes a constructor with the arg inline. MEASURED, the three `flat`
#     rows: `pyrender flat1` is `UOp.range(4, 0, AxisType.WEAK)` and
#     `pyrender flat2` / `flat3` are `UOp(Ops.RANGE, (UOp.const(4),),
#     (AxisType.WEAK, 0, 1))`. A guard that only narrowed the string could not
#     produce that, so a port that kept the old body and added the length test
#     would be wrong in a way no one-id fixture can see.
#
# WHY THE PORT NEEDS THE GUARD AS A SEPARATE READ. ops.bend's `ARange` is the
# SPLIT `(ids, at)` and the row `pyrender flat2` needs a two-element `ids`,
# which `f_range` cannot build today because it takes one `id: U32`. So `ids`
# is read whole, and the guard is `List.length` on it -- the same field
# `axis_id` is, which is what makes this a port of the head rule rather than of
# the pin's.
# ===========================================================================
# the parameter is named `ss` and not `srcs` because a parameter SHADOWS a def of
# the same name and `srcs(ctx, ss)` would then be a call on a list
def range_tail.of(n: Bool, +ss: List<&2, U32>, +ctx: Ctx) -> String:
  Bool.pick(String, n, String.concat([", src=", srcs(ctx, ss)]), "")

# `{c.val}, {x.axis_id[0]}, {x.axis_type}` -- THREE values, in the constructor's
# own order, and `axis_id[0]` is the HEAD's `ids` head. It is `u32_list_repr`'s
# HEAD rather than a bare `U32.show` because `x.axis_id[0]` is an int and
# `repr(int)` is `str(int)`, and `u32_list_repr` is the def that already
# established that spelling for an int.
def range_pieces.tail(ids: List<&2, U32>, at: O.AxisType) -> List<&2, String>:
  List.append(&2, String, List.append(&2, String, Nil{}, [peek_str(ids)]), [axis_repr(at)])

def range_pieces(+ar: O.Arena, ctx: Ctx, +u: U32) -> List<&2, String>:
  List.append(&2, String, Nil{}, [val_str(O.Arena.arg(ar, O.Arena.src0(ar, u))),
    peek_str(range_ids(ar, u)), axis_repr(range_at(ar, u))])

# `len(x.axis_id) == 1`. `peek_str` is the same read, so the guard and the body
# cannot disagree about what `axis_id[0]` is.
#
# THIS DEF IS ALSO WHY TWO MUTATIONS MOVE NOTHING, AND BOTH ARE THEOREMS RATHER
# THAN GAPS -- `.agents/slop/xd1/mutate.py` M-g and M-i:
#
#   * M-g swaps `peek_str(ids)` for `String.join(u32_list_repr.go(ids), ", ")`
#     -- "print the WHOLE id list", which is the PIN's `[repr(y) for y in x.arg]`.
#   * M-i swaps `List.head` for `List.last` in `peek_str`.
#
# BOTH ARE THE SAME FUNCTION AS WHAT THEY REPLACE over every REACHABLE input,
# because `range_pieces` is called only on the branch `range_one_id` admits:
# `Bool.pick` is strict, so it is evaluated for a one-element list and for nothing
# else. On a one-element list `join([x], ", ") == U32.show(x)` and
# `List.head == List.last`. So no fixture can separate them -- not because the
# fixture is missing but because there is no input on which they differ, which is
# the `ops_amd` `floor(floor(a/b)/c)` shape from `agent-core.md`.
#
# THE CONSEQUENCE, and it is the useful part: THE GUARD IS LOAD-BEARING FOR
# CORRECTNESS AND INVISIBLE TO EVERY MUTATION OF THE BODY. M-e (`>=` for `==`) and
# M-f (drop the guard) both move `pyrender flat2` and `pyrender flat3`; M-g and M-i
# move nothing. That is the correct shape -- the guard selects the branch and the
# body renders inside it -- and it is exactly the pairing `rebase-plan.py`'s
# "tuple payload" coupling level predicts.
def range_one_id(ids: List<&2, U32>) -> Bool:
  Nat.is_eq(List.length(&2, U32, ids), 1n)

def pmp.range.of(any: Bool, isconst: Bool, one: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(any), pmp.fb(ar, ctx, u),
    Bool.pick(String, Bool.not(isconst), pmp.fb(ar, ctx, u),
      Bool.pick(String, Bool.not(one), pmp.fb(ar, ctx, u),
        String.concat(["UOp.range(", String.join(range_pieces(ar, ctx, u), ", "),
          range_tail.of(Nat.is_le(2n, List.length(&2, U32, O.Arena.srcs(ar, u))), O.Arena.src_from(ar, u, 1), ctx), ")"]))))

def pmp.range(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.range.of(Nat.is_le(1n, List.length(&2, U32, O.Arena.srcs(ar, u))), is_const(ar, O.Arena.src0(ar, u)), range_one_id(range_ids(ar, u)), ar, ctx, u)

# RULES 9, 10 and 11 -- CDIV, CMOD and WHERE all render through `.alu(...)`, and
# the comment above them says why: `//` and `%` parse as FLOORDIV/FLOORMOD so CDIV
# and CMOD cannot be written infix, `.where` re-promotes its operands, and the
# binary operators re-promote too.
def pmp.alu.where(+ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".alu(", O.Ops.name(O.Arena.op(ar, u)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 1)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 2)), ")"])

def pmp.alu.bin(+ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".alu(", O.Ops.name(O.Arena.op(ar, u)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 1)), ")"])

# RULE 12: `UPat(set(syms.keys())-{Ops.SUB, Ops.CDIV, Ops.CMOD})` ->
#   strip_binary_parens(x, ctx[src0], ctx[src1], ..) if `x.src[0]._broadcasted(x.src[1]) == x.src`
#   else `f"{ctx[x.src[0]]}.alu({x.op}, {ctx[x.src[1]]})"`.
#
# `_broadcasted(y)` is `(y, self) if reverse else (self, y)` with reverse False,
# so the test MEASURED TRUE for a two-src node and FALSE for a three-src one --
# which means the whole test is `len(x.src) == 2`. It looks like a shape test and
# it is an arity test, and saying so is the difference between porting it and
# mis-porting it as a broadcast computation.
def pmp.syms.of(two: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, two, strip_binary_parens(ar, u, ctx_get(ctx, O.Arena.src0(ar, u)), ctx_get(ctx, O.Arena.src(ar, u, 1))), pmp.alu.bin(ar, ctx, u))

def pmp.syms(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.syms.of(Nat.is_eq(List.length(&2, U32, O.Arena.srcs(ar, u)), 2n), ar, ctx, u)

def arg_clause.of(ismeta: Bool, a: O.Arg) -> String:
  Bool.pick(String, ismeta, String.concat(["arg=", arg_repr(a)]), "")

def sugar_args.go(ar: O.Arena, +ctx: Ctx, u: U32, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: sugar_args.go(ar, ctx, u, t, List.append(&2, String, acc, [ctx_get(ctx, s)]))

# RULES 13 and 14, the `sugar` set. `src=()` renders `UOp.op(args)` and otherwise
# `{ctx[src[0]]}.op(args, ...)`, and in BOTH the arg clause is
# `', '.join([f'arg={repr(x.arg)}'] if x.arg is not None else [])` -- one element
# or none, so the comma belongs to the clause and not to the join.
# ===========================================================================
# `consumer_map_from_toposort` -- ops.py:112.
#
#     ret: dict[UOp, dict[UOp, None]] = {}
#     for u in lst:
#       ret[u] = {}
#       for s in u.src:
#         if s in ret: ret[s][u] = None
#
# TWO maps and not one: `ret[u]` is a SET of consumers and the three things the
# loop below reads are `len(cmap[u])` (how many), `list(cmap[u].keys())[0]`
# (which one) and the src list of that one. So `cnt` and `who` are separate
# `Map<&2, U32>`s and `who` is only meaningful when `cnt == 1`, which is exactly
# when Python's `list(cmap[u].keys())[0]` is only meaningful.
#
# `if s in ret` is the TOPOSORT GUARD and it is not redundant: the graph has
# back-edges (an END whose src[0] is the body it closes over), so a src can be a
# node `lst` has not visited yet. The guard is why the fold carries `seen`.
# ===========================================================================

def cu32.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{m, v}: v

def cu32(m: Map<&2, U32>, u: U32) -> U32:
  cu32.of(Map.get(U32, 0, m, U32.show(u)))

def chas.of(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def chas(m: Map<&2, U32>, u: U32) -> Bool:
  chas.of(Map.has(&2, U32, m, U32.show(u)))

type Cons is Data:
  Cons{seen: Map<&2, U32>, cnt: Map<&2, U32>, who: Map<&2, U32>}




# ===========================================================================
# `to_render` -- render.py:151-164, the decision of which nodes get their own
# `cN = ...` line.
#
#     to_render: set[UOp] = {ast}
#     for u in lst:
#       if u.op in {Ops.SINK}: for s in u.src: to_render.add(s)
#       if u.op is Ops.STORE: to_render.add(u.src[1])
#       if u.op is Ops.REDUCE: to_render.add(u.src[0])
#       ...two NotImplementedError raises...
#       if u.op in not_rendered: continue
#       if len(cmap[u]) == 1 and len([x for x in list(cmap[u].keys())[0].src if x is u]) == 1 and u.op not in always_rendered: continue
#       to_render.add(u)
#
# THE ORDER IS LOAD-BEARING: the three adds come BEFORE the `continue`, so a
# CONST that is a STORE's src is added by the STORE and then skipped by its own
# `not_rendered` test -- it is in the set AND it is rendered inline. The comment
# on the consumer test says it: "checking the consumers is not enough, you have
# to make sure it's not used twice by the one consumer".
# ===========================================================================

def not_rendered(op: O.Op) -> Bool: is_const.of(op)

def always_rendered(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsLOAD{}: True{}
    case O.OpsSPECIAL{}: True{}
    case O.OpsRANGE{}: True{}
    case O.OpsSTACK{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case O.OpsCOPY{}: True{}
    case O.OpsCALL{}: True{}
    case O.OpsWHERE{}: True{}
    case O.OpsEND{}: True{}
    case O.OpsBACKEDGE{}: True{}
    case _: False{}

def op_is_sink_or_store(op: O.Op) -> Bool:
  match op:
    case O.OpsSINK{}: True{}
    case O.OpsSTORE{}: True{}
    case O.OpsREDUCE{}: True{}
    case _: False{}

def tr_set(tr: Map<&2, U32>, u: U32) -> Map<&2, U32>: Map.set(&2, U32, tr, U32.show(u), 1)

def uses.go(+ss: List<&2, U32>, +u: U32, n: U32) -> U32:
  match ss:
    case Nil{}: n
    case +s <> t: uses.go(t, u, U32.add(n, Bool.to_u32(U32.is_eq(s, u))))

# ===========================================================================
# `_render_with_splits` -- render.py:125-141.
#
#     for i,u in enumerate(lst):
#       op_depth = 1 + max([depth.get(s, 0) for s in u.src], default=0)
#       if op_depth > split_depth: to_render.add(u)
#       depth[u] = 0 if u in to_render else op_depth
#       ren = pm.rewrite(u, ctx=r)
#       if u.tag is not None: ren += f".rtag({repr(u.tag)})"
#       if u not in to_render: r[u] = ren
#       else: r[u] = f"c{i}" if u is not lst[-1] else "ast"; ret[r[u]] = ren
#
# `depth[u] = 0` EXACTLY when `u in to_render`, so `depth` alone answers the
# membership test and `to_render` does not have to be a set any more. That is
# the one structural saving here and it is a real one: Python carries three
# dicts and this carries two. `ret` is a LIST of pairs because Python's dict is
# insertion-ordered and the final `'\n'.join(ret.items())` emits in THAT order --
# a `Map` would not, and the line order is the diff.
# ===========================================================================

type Bind is Data:
  Bind{k: String, v: String}

type RWS is Data:
  RWS{ctx: Ctx, ret: List<&2, Bind>, dep: Map<&2, U32>, trn: Map<&2, U32>}

def op_depth.go(+ss: List<&2, U32>, +dep: Map<&2, U32>, acc: U32) -> U32:
  match ss:
    case Nil{}: acc
    case s <> t: op_depth.go(t, dep, U32.max(acc, cu32(dep, s)))

# `depth[u] = 0 if u in to_render else op_depth`
def rws_dep.of(intr: Bool, d: U32, +dep: Map<&2, U32>, u: U32) -> Map<&2, U32>:
  Map.set(&2, U32, dep, U32.show(u), Bool.pick(U32, intr, 0, d))

def rws_dep(+dep: Map<&2, U32>, u: U32, d: U32, intr: Bool) -> Map<&2, U32>:
  rws_dep.of(intr, d, dep, u)

# `if op_depth > split_depth: to_render.add(u)` -- render.py's default is 100 and
# its comment ("limit inline depth to avoid 'too many nested parentheses' in
# Python parser") is why it is not infinity.
def rws_trn.of(write: Bool, +tr: Map<&2, U32>, u: U32) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, write, tr_set(tr, u), tr)

def rws_trn(+tr: Map<&2, U32>, u: U32, d: U32, intr: Bool) -> Map<&2, U32>:
  rws_trn.of(Bool.or(intr, U32.is_gt(d, 100)), tr, u)

# `f"c{i}" if u is not lst[-1] else "ast"`
def rws_key(last: U32, i: U32, u: U32) -> String:
  Bool.pick(String, U32.is_eq(u, last), "ast", String.concat(["c", U32.show(i)]))

# `if u not in to_render: r[u] = ren` / `else: r[u] = key; ret[key] = ren`.
# `intr` IS `u in to_render`, so the INLINE case is the NOT branch: `Bool.pick`
# answers its THIRD argument when the test is false, which is why the `else` of
# Python reads here as the FALSE arm. Getting this backwards puts every rendered
# node in `ret` and every split node inline, and `ret` comes back EMPTY for a tree
# whose only split node is the ast -- which is most of them.
def rws_ren.pick(intr: Bool, +ren: String, +last: U32, +i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  Bool.pick(RWS, intr,
    RWS{ctx_put(ctx, u, rws_key(last, i, u)), List.append(&2, Bind, ret, [Bind{rws_key(last, i, u), ren}]), dep, trn},
    RWS{ctx_put(ctx, u, ren), ret, dep, trn})

def rws_ren.of(intr: Bool, +ren: String, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_ren.pick(intr, ren, last, i, u, ctx, ret, dep, trn)




def rws_ret(st: RWS) -> List<&2, Bind>:
  match st:
    case RWS{ctx, ret, dep, trn}: ret






def last_of(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.last(&2, U32, xs), 0)




# `1 + max([depth.get(s, 0) for s in u.src], default=0)` -- `default=0` is the
# Nil arm and `depth.get`'s 0 is the fold's identity, so they are the same 0.
def op_depth(+ar: O.Arena, u: U32, +dep: Map<&2, U32>) -> U32:
  U32.add(1, op_depth.go(O.Arena.srcs(ar, u), dep, 0))














def pmp.cast(+ar: O.Arena, +tb: F.Table, ctx: Ctx, +u: U32) -> String:
  pmp.cast.of(dt_same(tb, ar, u), ar, tb, ctx, u)







def arg_clause(+a: O.Arg) -> String:
  arg_clause.of(ismeta_of(a), a)

# `[ctx[y] for y in x.src[1:]] + [f'arg={repr(x.arg)}'] if x.arg is not None else []`
# -- the SRCS FIRST and the arg clause LAST, so the clause rides in as the
# accumulator's TAIL SEED and the walk only ever appends a src. Seeding it as the
# HEAD put `arg=(0, AxisType.LOOP)` before the index it belongs after.
def sugar_tail(+ar: O.Arena, +u: U32, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, ismeta_of(O.Arena.arg(ar, u)), List.append(&2, String, acc, [arg_clause(O.Arena.arg(ar, u))]), acc)

def sugar_args(+ar: O.Arena, ctx: Ctx, +u: U32, +acc: List<&2, String>) -> List<&2, String>:
  sugar_args.go(ar, ctx, u, O.Arena.src_from(ar, u, 1), sugar_tail(ar, u, acc))
def pmp.sugar.of(zero: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, zero,
    String.concat(["UOp.", op_lower(O.Arena.op(ar, u)), "(", String.join(sugar_args(ar, ctx, u, Nil{}), ", "), ")"]),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".", op_lower(O.Arena.op(ar, u)), "(", String.join(sugar_args(ar, ctx, u, Nil{}), ", "), ")"]))

def pmp.sugar(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.sugar.of(U32.is_zero(O.Arena.nsrc(ar, u)), ar, ctx, u)

# RULE 7: `UPat(Ops.REDUCE, name="r")` ->
#   `f"{ctx[r.src[0]]}._rop({r.arg[0]}, {tuple(range(r.arg[1]))})"` if `r.arg[1]`
# else None. `tuple(range(n))` is `0, 1, ..., n-1` parenthesised.
def pmp.reduce.of(has: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(has), pmp.sugar(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), "._rop(", reduce_op(ar, u), ", ", range_tuple(reduce_axes(ar, u)), ")"]))

def pmp.reduce(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.reduce.of(Nat.is_le(1n, U32.to_nat(reduce_axes(ar, u))), ar, ctx, u)

# THE DISPATCH. One `match` on the op, in Python's rule order, and every arm
# carries its own guard because a `match` may not scrutinise a call.
def pmp.go.of(op: O.Op, ar: O.Arena, tb: F.Table, ctx: Ctx, u: U32) -> String:
  match op:
    case O.OpsCONST{}: pmp.const(ar, ctx, u)
    case O.OpsCAST{}: pmp.cast(ar, tb, ctx, u)
    case O.OpsBITCAST{}: pmp.cast(ar, tb, ctx, u)
    case O.OpsSPECIAL{}: pmp.special(ar, ctx, u)
    # NO `OpsBUFFER` ARM: rule 4 was DELETED upstream (78d482262), so a BUFFER
    # now reaches no rule and FALLS THROUGH to `pmp.fb` -- rule 15 -- which
    # prints `UOp(Ops.BUFFER, (src), <repr(arg)>)`. Deleting the ARM is the
    # whole of the port; keeping it would keep a rule that no longer exists.
    case O.OpsCOPY{}: pmp.copy(ar, ctx, u)
    case O.OpsCUSTOM_FUNCTION{}: pmp.cfn(ar, ctx, u)
    case O.OpsREDUCE{}: pmp.reduce(ar, ctx, u)
    case O.OpsRANGE{}: pmp.range(ar, ctx, u)
    case O.OpsCDIV{}: pmp.alu.bin(ar, ctx, u)
    case O.OpsCMOD{}: pmp.alu.bin(ar, ctx, u)
    case O.OpsWHERE{}: pmp.alu.where(ar, ctx, u)
    case O.OpsADD{}: pmp.syms(ar, ctx, u)
    case O.OpsMUL{}: pmp.syms(ar, ctx, u)
    case O.OpsSHL{}: pmp.syms(ar, ctx, u)
    case O.OpsSHR{}: pmp.syms(ar, ctx, u)
    case O.OpsFLOORDIV{}: pmp.syms(ar, ctx, u)
    case O.OpsFLOORMOD{}: pmp.syms(ar, ctx, u)
    case O.OpsAND{}: pmp.syms(ar, ctx, u)
    case O.OpsXOR{}: pmp.syms(ar, ctx, u)
    case O.OpsOR{}: pmp.syms(ar, ctx, u)
    case O.OpsCMPLT{}: pmp.syms(ar, ctx, u)
    case O.OpsCMPNE{}: pmp.syms(ar, ctx, u)
    case O.OpsSUB{}: pmp.fb(ar, ctx, u)
    case O.OpsSQRT{}: pmp.sugar(ar, ctx, u)
    case O.OpsINDEX{}: pmp.sugar(ar, ctx, u)
    case O.OpsSTORE{}: pmp.sugar(ar, ctx, u)
    case O.OpsLOAD{}: pmp.sugar(ar, ctx, u)
    case O.OpsSINK{}: pmp.sugar(ar, ctx, u)
    case O.OpsEND{}: pmp.sugar(ar, ctx, u)
    case O.OpsBACKEDGE{}: pmp.sugar(ar, ctx, u)
    case O.OpsAFTER{}: pmp.sugar(ar, ctx, u)
    case O.OpsTHREEFRY{}: pmp.sugar(ar, ctx, u)
    case O.OpsRECIPROCAL{}: pmp.sugar(ar, ctx, u)
    case O.OpsEXP2{}: pmp.sugar(ar, ctx, u)
    case O.OpsLOG2{}: pmp.sugar(ar, ctx, u)
    case O.OpsSIN{}: pmp.sugar(ar, ctx, u)
    case O.OpsBARRIER{}: pmp.sugar(ar, ctx, u)
    case O.OpsDETACH{}: pmp.sugar(ar, ctx, u)
    case _: pmp.fb(ar, ctx, u)

# `pm.rewrite(u, ctx=r)`: the fifteen rules in Python order, then the GroupOp.All
# fallback. `assert isinstance(ren, str)` in Python is not reproduced: rule 15
# matches every op, so the assertion cannot fail and reproducing it would only
# add an unreachable path.
def pmp(+ar: O.Arena, tb: F.Table, ctx: Ctx, +u: U32) -> String:
  pmp.go.of(O.Arena.op(ar, u), ar, tb, ctx, u)

# `ren += f".rtag({repr(u.tag)})"`. This is a SUFFIX, so an untagged node
# contributes NOTHING -- the same shape as `tagstr` above, and NOT the whole
# rendered string. Seeding the no-tag arm with `tag_repr(t)` (which is the
# literal "None") appended "None" to every untagged node.
def rtag.of(+t: O.Tag, +s: String) -> String:
  Bool.pick(String, tag_is_none(t), s, String.concat([".rtag(", tag_repr(t), ")"]))

def rtag(+t: O.Tag) -> String: rtag.of(t, "")

def ren_str(+ar: O.Arena, tb: F.Table, ctx: Ctx, +u: U32) -> String:
  String.concat([pmp(ar, tb, ctx, u), rtag(O.Arena.tag(ar, u))])

def rws_step.put(+d: U32, +intr: Bool, +ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_ren.of(intr, ren_str(ar, tb, ctx, u), last, i, u, ctx, ret, rws_dep(dep, u, d, intr), rws_trn(trn, u, d, intr))

def rws_step.of(+ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_step.put(op_depth(ar, u, dep), chas(trn, u), ar, tb, last, i, u, ctx, ret, dep, trn)

def rws_step(+ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +st: RWS) -> RWS:
  match st:
    case RWS{ctx, ret, dep, trn}: rws_step.of(ar, tb, last, i, u, ctx, ret, dep, trn)

def rws.go(lst: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +last: U32, +i: U32, +st: RWS) -> RWS:
  match lst:
    case Nil{}: st
    case +u <> t: rws.go(t, ar, tb, last, U32.add(i, 1), rws_step(ar, tb, last, i, u, st))

def render_with_splits(+ar: O.Arena, +tb: F.Table, +lst: List<&2, U32>, +trn: Map<&2, U32>) -> List<&2, Bind>:
  rws_ret(rws.go(lst, ar, tb, last_of(lst), 0, RWS{ctx_new(), Nil{}, Map.new(&2, U32), trn}))


# `f"{k} = {strip_parens(v)}" for k,v in ret.items()`
def ret_row.of(k: String, +v: String) -> String:
  String.concat([k, " = ", Bool.pick(String, H.is_wrapped(v), H.strip_parens(v), v)])

def ret_row(p: Bind) -> String:
  match p:
    case Bind{k, v}: ret_row.of(k, v)

# `f"{k} = {strip_parens(v)}" for k,v in ret.items()`
def ret_rows.go(ps: List<&2, Bind>) -> List<&2, String>:
  match ps:
    case Nil{}: Nil{}
    case p <> t: ret_row(p) <> ret_rows.go(t)

def ret_rows(ps: List<&2, Bind>) -> List<&2, String>: ret_rows.go(ps)
























def Cons.seen(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: seen

def Cons.cnt(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: cnt

def Cons.who(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: who

# `ret[s][u] = None` is a DICT WRITE, so a u that lists s twice contributes ONE
# consumer. `who[s] == u` is that test, and it is also the whole reason `who`
# exists rather than a count alone.
def cons_bump.write(u: U32, +s: U32, +c: Cons) -> Cons:
  match c:
    case Cons{seen, cnt, who}: Cons{seen, Map.set(&2, U32, cnt, U32.show(s), U32.add(cu32(cnt, s), 1)), Map.set(&2, U32, who, U32.show(s), u)}

def cons_bump(+ar: O.Arena, +u: U32, +s: U32, +c: Cons) -> Cons:
  Bool.pick(Cons, U32.is_eq(cu32(Cons.who(c), s), u), c, cons_bump.write(u, s, c))

def cons_one(+ar: O.Arena, u: U32, +s: U32, +c: Cons) -> Cons:
  Bool.pick(Cons, chas(Cons.seen(c), s), cons_bump(ar, u, s, c), c)

# the list first, for the same reason as `tr_all`
def cons_add(+ss: List<&2, U32>, +ar: O.Arena, +u: U32, +c: Cons) -> Cons:
  match ss:
    case Nil{}: c
    case +s <> t: cons_add(t, ar, u, cons_one(ar, u, s, c))

def consumers.empty() -> Cons:
  Cons{Map.new(&2, U32), Map.new(&2, U32), Map.new(&2, U32)}

def consumers.mark(+c: Cons, u: U32) -> Cons:
  match c:
    case Cons{seen, cnt, who}: Cons{Map.set(&2, U32, seen, U32.show(u), 1), cnt, who}

def consumers.step(+ar: O.Arena, +u: U32, +c: Cons) -> Cons:
  consumers.mark(cons_add(O.Arena.srcs(ar, u), ar, u, c), u)

def consumers.go(lst: List<&2, U32>, +ar: O.Arena, +c: Cons) -> Cons:
  match lst:
    case Nil{}: c
    case +u <> t: consumers.go(t, ar, consumers.step(ar, u, c))

def consumers.new(+ar: O.Arena, lst: List<&2, U32>) -> Cons:
  consumers.go(lst, ar, consumers.empty())

















# `len([x for x in list(cmap[u].keys())[0].src if x is u])` -- how many times the
# one consumer lists u.
def uses(+ar: O.Arena, v: U32, u: U32) -> U32: uses.go(O.Arena.srcs(ar, v), u, 0)

# `if u.op in not_rendered: continue` comes FIRST and short-circuits the rest.
# `if u.op in not_rendered: continue` and the consumer test are TWO `continue`s,
# so this is an OR of them -- not a `Bool.pick` that DROPS the test for every
# node that is not a CONST. Reading it as a pick gave `False` for every non-CONST,
# so nothing ever continued and every node split onto its own `cN` line.
def tr_continue.of(+op: O.Op, +ar: O.Arena, +u: U32, +c: Cons) -> Bool:
  Bool.or(not_rendered(op),
    Bool.and(U32.is_eq(cu32(Cons.cnt(c), u), 1), Bool.and(U32.is_eq(uses(ar, cu32(Cons.who(c), u), u), 1), Bool.not(always_rendered(op)))))

def tr_continue(op: O.Op, +ar: O.Arena, u: U32, +c: Cons) -> Bool:
  tr_continue.of(op, ar, u, c)

def tr_keep.of(op: O.Op, +ar: O.Arena, +u: U32, +tr: Map<&2, U32>, +c: Cons) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, tr_continue(op, ar, u, c), tr, tr_set(tr, u))

# the `continue` test, in Python's order
def tr_keep(op: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>, +c: Cons) -> Map<&2, U32>:
  tr_keep.of(op, ar, u, tr, c)








# a SINK adds ALL its srcs; a STORE adds src[1]; a REDUCE adds src[0]
# THE LIST IS FIRST. The self-call is `tr_all(t, ar, tr_set(tr, s))` and the
# SHRINKING argument is now the first one, because the rule is "arguments are read
# left to right: each passed unchanged until one shrinks" -- a computed argument
# in front of the tail makes the call non-decreasing.
def tr_all(+ss: List<&2, U32>, +ar: O.Arena, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match ss:
    case Nil{}: tr
    case +s <> t: tr_all(t, ar, tr_set(tr, s))

def tr_of.of(op: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match op:
    case O.OpsSINK{}: tr_all(O.Arena.srcs(ar, u), ar, tr)
    case O.OpsSTORE{}: tr_set(tr, O.Arena.src(ar, u, 1))
    case O.OpsREDUCE{}: tr_set(tr, O.Arena.src0(ar, u))
    case _: tr

def tr_of(op: O.Op, ar: O.Arena, u: U32, tr: Map<&2, U32>) -> Map<&2, U32>:
  tr_of.of(op, ar, u, tr)

def tr_push.of(op: O.Op, +op2: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, Bool.not(op_is_sink_or_store(op2)), tr, tr_of(op2, ar, u, tr))

# the three unconditional adds
def tr_push(op: O.Op, +ar: O.Arena, +u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  tr_push.of(O.Arena.op(ar, u), op, ar, u, tr)

def to_render.go(lst: List<&2, U32>, +ar: O.Arena, +cs: Cons, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: tr
    case +u <> t: to_render.go(t, ar, cs, tr_keep(O.Arena.op(ar, u), ar, u, tr_push(O.Arena.op(ar, u), ar, u, tr), cs))

def to_render(+ar: O.Arena, +lst: List<&2, U32>, ast: U32) -> Map<&2, U32>:
  to_render.go(lst, ar, consumers.new(ar, lst), tr_set(Map.new(&2, U32), ast))



def pyrender.of(+ar: O.Arena, +tb: F.Table, +ast: U32, +lst: List<&2, U32>) -> String:
  String.join(ret_rows(render_with_splits(ar, tb, lst, to_render(ar, lst, ast))), "\n")

# `list(ast.toposort())` is `O.UOp.toposort` with `Arena.budget`'s fuel. The
# `cN` LABEL is a toposort index, so the 25 rows below are what pins the walk's
# LIFO order (a queue renders consumers before their srcs, and `ctx_get` answers
# "" for an unwritten src, so the output was SHAPE-wrong rather than merely
# different), its `src[1:]` tail and its N + E fuel.
def pyrender(+ar: O.Arena, +tb: F.Table, +ast: U32) -> String:
  pyrender.of(ar, tb, ast, O.UOp.toposort(O.Arena.budget(ar), ar, ast))

# `isinstance(u.arg, ParamArg) and u.arg.buffer is not None` -- the SECOND
# refusal predicate's payload. `pyr_call` / `pyr_buffer` themselves are at the
# FOOT of this file with the upstream rewrite, and this is the only helper they
# need that was already here.
def pyr_buffer.pa(a: O.Arg) -> Bool:
  match a:
    case O.AParam{pa}: Maybe.is_some(&2, U32, O.ParamArg.buffer(pa))
    case _: False{}

# ===========================================================================
# WHAT IS NOT PORTED, in upstream order, and why. Nothing here is a Bend wall;
# four of the five are missing INPUTS in a shared file and the fifth ran out of
# room.
#
# * `pretty_print` (:6) -- PORTED IN PART. Its `dfs` is a mutable
#   `cache.setdefault(s, [len(cache), 0, False])[1] += 1` over a CYCLIC graph, so
#   the cache is a second store beside the arena and the walk needs a fuel the
#   Python does not; `argstr`/`tagstr` ARE ported (`tagstr` is here), which is the
#   half that was cheap.
# * `print_uops` (:18) -- BLOCKED on `UOp.ranges`, which is `# TODO(p3)
#   ops.py:497` in ops.bend. `multirange_str` and `range_str` ARE ported here
#   (they take the range list as a parameter), so only the `u.ranges` COLUMN is
#   missing, not the formatting.
# * `marg_str` (:35) / `render_marg` (:37) -- `marg_str`'s third arm is
#   `a.render()`, and `render` is `# TODO(p3) ops.py:1181` in ops.bend; it needs
#   `simplify()` (`# TODO(p3) ops.py:513`) and the whole `renderer` matcher, whose
#   Movement arm calls `render_marg`, so the two are a cycle the port cannot break
#   by ordering. `render_marg` itself is `x.marg`, which is `# TODO(p3) ops.py:814`.
# * `renderer` / `renderer_infer` (:45, :74) -- 21 UPat rules whose payloads are
#   mostly `ctx[src]`; only the sugar/renderer INFER arms need anything that is
#   not already here. They are needed by `UOp.render()`, not by `pyrender`.
# * THE PYRENDER GATE ROWS ARE LANDED -- twenty-five of them, at the foot of this
#   file, one per pm_pyrender rule plus the three `to_render` arms and the fuel
#   -- so this is no longer on the list. Adding them found SIX bugs in the port
#   this file owns,
#   which is the argument for the rows existing at all rather than the other way
#   round: `rws_ren.pick` had its two arms swapped (so `ret` came back empty and
#   `pyrender` returned `""` for EVERY tree), `rtag` seeded its no-tag arm with
#   the tag's own repr (so every untagged node printed a trailing `None`),
#   `sugar_args` put the arg clause BEFORE the srcs, `tr_continue` read two
#   `continue`s as a `Bool.pick` (so nothing ever continued and every node split),
#   and `range_tuple` passed its countdown through unchanged, printing `(0, 0)`.
#   THREE MORE were bugs in files this file does not own, and all three rebuilds
#   are GONE: `UOp.toposort` walked a QUEUE where CPython's is a LIFO stack and
#   was fuelled with `2 * len(arena)` where the bound is NODES + EDGES,
#   `Arena.src_from.go` dropped one element too many, and helpers.bend's
#   `is_balanced` re-derived the underflow flag from the depth instead of
#   reading the one its own record carries. `pyrender` now calls
#   `O.UOp.toposort(O.Arena.budget(ar), ar, ast)`, slices with
#   `O.Arena.src_from` and asks `H.is_wrapped`, and the 25 rows below are what
#   pins all three.
#
# * THE `Ops.RANGE` RULE'S NEW GUARD AND THE BUFFER RULE'S DELETION LANDED with
#   the drift record at the head of this file: three `flat*` rows, four
#   `buflocal` / `bufnodev` / `bufimage` rows, one `bufrefused` fixture, six
#   refusal rows, and `f_range`'s signature widened from `id: U32` to
#   `ids: List<&2, U32>` so the guard is reachable at all.
#
# TODO(p3) render.py:6   def pretty_print
# TODO(p3) render.py:18  def print_uops
# TODO(p3) render.py:35  def marg_str
# TODO(p3) render.py:37  def render_marg
# TODO(p3) render.py:45  renderer
# TODO(p3) render.py:74  renderer_infer
#
# ===========================================================================
# THE MEASURED MUTATION TABLE, by `.agents/slop/xd1/mutate.py`. THIRTEEN textual
# edits, one at a time, each compiled and re-run against the clean 129-row lane
# and each diffed by WHOLE `name=value` LINES (`.agents/slop/xd1/rowdiff.py`).
# Every entry is a REVERT of one of this unit's own fixes, so the set a mutation
# moves IS the set of rows that fix was load-bearing for.
#
#   mutation                                          rows moved (BY NAME)
#   ------------------------------------------------------------------------
#   M-a  `arange_repr` prints the type LAST             arg_repr ARng,
#                                                        pyrender flat2, flat3
#   M-b  rule 4 restored IN FULL (defs AND its arm)    pyrender buffer, buflocal,
#                                                        bufnodev, bufimage, copy,
#                                                        store
#   M-c  `pyr_call` refuses EVERY CALL                 pyr_call_const, named, noop
#   M-d  `pyr_call` refuses NOTHING                    pyr_call_prog
#   M-e  the guard is `>= 1` instead of `== 1`         pyrender flat2, flat3
#   M-f  the guard dropped entirely                    pyrender flat2, flat3
#   M-g  the body prints the WHOLE id list             NONE -- THEOREM, below
#   M-h  `u32_tuple_repr` drops the 1-tuple comma      arg_repr ATup1
#   M-i  `peek_str` reads `List.last` not `List.head`  NONE -- THEOREM, below
#   M-j  `pyr_buffer.pa` reads `size` not `buffer`     pyr_buffer_plain
#   M-k  `peek_str` replaced by the constant `0`       pyrender mul3, xor3
#   M-l  `range_tail`'s `src=` tail dropped            pyrender range2
#   M-m  `body_prog` tests CUSTOM_FUNCTION             pyr_call_prog
#
# ELEVEN OF THIRTEEN MOVE ROWS. The two zeros are THEOREMS, not gaps, and the
# argument is in `range_one_id`'s comment: `range_pieces` is reachable only on the
# branch `len(ids) == 1` admits, and on a one-element list `join([x], ", ")` is
# `U32.show(x)` and `List.head` is `List.last`. No fixture can separate them --
# there is no input on which they differ.
#
# M-h AND M-j MOVED NOTHING BEFORE THEIR FIXTURES EXISTED, and that is the second
# finding. `ATup` had two elements so the one-element comma had no row, and
# `g_bufrefused` had `buffer == size == Some{4}` so the two `ParamArg` fields were
# indistinguishable. Both fixtures were added; `ATup0` and `ATup1` are the two
# lengths the comma has to tell apart, and `g_bufrefused` now carries `Some{9}`
# because a buffer's slot index and its element count are different numbers in
# every real `ParamArg`.
#
# M-b ALSO TAUGHT SOMETHING ABOUT DELETIONS. Restoring only the DISPATCH ARM moved
# nothing, because the arm's fall-through target `pmp.fb` is exactly what a BUFFER
# already takes -- so "re-add the arm" and "leave it deleted" are the same program
# until the arm has a body. A deleted rule's arm is not a no-op; a re-added arm
# that delegates to the fallback is.
# ===========================================================================

# THE GATE. Every row is a CPython value measured on 2026-09-30 with
# `.venv/bin/python -c "import sys; sys.path.insert(0,'.'); ..."` against this
# `tinygrad/` tree; the `py=` text IS the oracle, printed next to the answer so
# a dropped literal shows up as a STRING DIFFERENCE rather than hidden in a
# boolean. That matters more here than in any other unit: `String.concat` will
# happily drop a ", " and yield a plausible wrong string, so the gate is the
# string and never `arg_repr(..) == "..."`.
#
# THE `g_*` FIXTURES ARE ARENA TREES, not values. `pyrender` takes a UOp and walks
# its toposort, so pinning it needs a graph, and each fixture below rebuilds one
# CPython `UOp` tree node for node -- same op, same arg, same tag, same src order
# -- because a `cN` label IS a toposort index and the whole gate is a diff of
# those labels. `py_row` folds the arena, renders, and prints the result beside
# the CPython string for the same tree.
#
# THE THREE `pa` FIXTURES are the three shapes tinygrad's own repr test
# exercises, and together they cover the three ORDERINGS of the nine keyword
# fields: pa1 sets only `device`, pa2 sets only `name` and no size, pa3 sets
# `addrspace`, `volatile` and `image`. A field-order bug that moved one keyword
# cannot pass all three.
# ===========================================================================

# ParamArg(1, dtypes.f32, 4, device='METAL')
def pa1() -> O.ParamArg:
  O.ParamArg{1, S.single(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{2}},
    False{}, None{}, None{}, False{}, None{}}

# ParamArg(2, dtypes.i32, name='g') -- no size, and size is the one POSITIONAL
# optional, so a `size` that printed when it is None moves every later field.
def pa2() -> O.ParamArg:
  O.ParamArg{2, S.int32(), None{}, None{}, None{}, Some{"g"}, S.AGlobal{}, None{},
    False{}, None{}, None{}, False{}, None{}}

# ParamArg(3, dtypes.f32, 4, addrspace=AddrSpace.LOCAL, volatile=True, image=(2, 2))
def pa3() -> O.ParamArg:
  O.ParamArg{3, S.single(), Some{4}, None{}, None{}, None{}, S.ALocal{}, None{},
    True{}, Some{O.Img{2, 2}}, None{}, False{}, None{}}

# ===========================================================================
# THE ARENA FIXTURES THAT DRIVE `pyrender`. render.py:143 is the whole REPR
# port's reason to exist and until these rows landed NOTHING called it, so the
# three `pa` fixtures above -- which pin `arg_repr` -- were pinning a formatter
# whose caller was untested.
#
# EVERY FIXTURE IS A CPython `UOp` TREE REBUILT NODE FOR NODE, and the `py=` text
# is what `pyrender` prints for THAT tree on this `tinygrad/`. Nothing here is a
# transcription: each row's oracle was measured, and the numbering matters -- a
# `cN` label is the toposort INDEX, so the Bend arena has to reach the same
# toposort ORDER CPython does, not merely hold the same nodes.
#
# THE `cN` NUMBERS ALSO PIN THE `to_render` PASS, which is where a lot of
# render.py's behaviour lives: `shared` forces one node onto its own line
# because it has two consumers, `sink`/`store`/`reduce2` force one because the
# SINK/STORE/REDUCE arms add srcs unconditionally, and `buffer`/`copy`/`index`
# show the inverse (BUFFER/RANGE/SPECIAL are `always_rendered`, so they get a
# line even with exactly one consumer).
# ===========================================================================

# `UOp.const(n)` -- CONST(3) is a weakint CONST here and in CPython, so `dt_of`
# agrees and no CAST is involved.
def f_const(+ar: O.Arena, n: U32) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# `UOp(Ops.RANGE, src=(CONST(end),), arg=(axis_id, at))` -- ops.py:644.
def f_range(+ar: O.Arena, end: U32, ids: List<&2, U32>, at: O.AxisType) -> O.Found:
  O.UOp.new(ar, O.OpsRANGE{}, [end], O.ARange{ids, at}, O.TNone{})

# `UOp.range(n, id)` -- the CONST end and the RANGE in one step. The RANGE is
# built in the arena the CONST returned, for the same reason `f_buf` is: passing
# `ar` on to `f_range` would hand it the arena from BEFORE the CONST.
# `ids` IS A LIST, and that is the point of the signature: HEAD'S GUARD IS
# `len(x.axis_id) == 1`, so a builder taking a single `id: U32` would make the
# guard TRUE for every fixture in the file and therefore untestable -- the shape
# of a green gate over a rule that cannot fail. `axis_id` is a tuple upstream and
# the multi-id shape is what `hcq2.py` writes (`arg=(u.axis_type, next(ctx))+
# u.axis_id[1:]`); it is the only one `pyrender` can REFUSE. Every fixture below
# passes a one-element list except `flat2` / `flat3`.
def f_rng_at(+c: O.Found, ids: List<&2, U32>) -> O.Found:
  f_range(O.Found.ar(c), O.Found.i(c), ids, O.AXIS_WEAK{})

def f_rng(ar: O.Arena, n: U32, id: U32) -> O.Found:
  f_rng_at(f_const(ar, n), [id])

def f_rng_ids(ar: O.Arena, n: U32, ids: List<&2, U32>) -> O.Found:
  f_rng_at(f_const(ar, n), ids)

# `UOp(Ops.BUFFER, src=(UOp.range(size,0),), arg=ParamArg(0, int32, size, dev))`.
# The arena comes from the RANGE's own `Found`, not from the argument `ar`:
# arguments are read left to right and each is passed UNCHANGED until one shrinks,
# so passing `ar` here would hand `f_buf_r` the arena from BEFORE the RANGE and the
# CONST -- and the BUFFER would land at index 1 over a RANGE index that is not
# there yet. The device is a PARAMETER so `copy` can pass the TUPLE form the COPY
# rule prints; a fixed device would make that row unreachable.
def f_buf_r(+r: O.Found, dev: S.Dev, size: U32) -> O.Found:
  O.UOp.new(O.Found.ar(r), O.OpsBUFFER{}, [O.Found.i(r)],
    O.AParam{O.ParamArg{0, S.int32(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{dev},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

def f_buf(ar: O.Arena, dev: S.Dev, +size: U32) -> O.Found:
  f_buf_r(f_rng(ar, size, 0), dev, size)

# THE GATE ROW. A `do IO<Unit>` body cannot bind with `+`, so the fixture is a
# `def` per rule and this one folds, renders and prints. `py=` is the CPython
# string for the same tree, so a dropped literal or a moved `cN` is a DIFF.
def py_row(nm: String, py: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat([nm, " = [", pyrender(O.Found.ar(f), F.UOp.fold(O.Found.ar(f)), O.Found.i(f)), "]   py=[", py, "]"]))

# ---------------------------------------------------------------------------
# `pyr_call` -- REWRITTEN UPSTREAM. `78d482262` replaced the predicate:
#
#   pin:  u.op is Ops.CALL and u.body.dtype is dtypes.void
#                              and u.body.op is not Ops.CUSTOM_FUNCTION
#   head: u.op is Ops.CALL and (u.body.op is Ops.PROGRAM
#                               or u.arg.grad_fxn is not None or u.arg.aux is not None)
#                    # a call on a program, or with a grad_fxn or an aux,
#                    # can't be reconstructed from code
#
# IT IS NOT A WIDENING, and that is the whole finding. The two disagree in BOTH
# directions, MEASURED over four bodies x four CallInfo shapes
# (`.agents/slop/xd1/call-refusal-oracle.py`, 16 refusal rows):
#
#   body=NOOP, plain CallInfo        pin REFUSED  -> head RENDERED
#   body=CUSTOM_FUNCTION + grad_fxn  pin RENDERED -> head REFUSED
#   body=CONST       + grad_fxn      pin RENDERED -> head REFUSED
#   body=CONST       + aux           pin RENDERED -> head REFUSED
#
# So a port that only ADDED the new conjuncts would refuse strictly more, and a
# port that only DELETED the old ones would refuse strictly less, and both would
# be wrong on a fixture. The old predicate keyed on a DTYPE (`body.dtype is
# void`) and the new one keys on an OP (`body.op is PROGRAM`) plus two CallInfo
# fields -- and the dtype is what `78d482262` also moved, since a CALL's dtype
# is now `src[0].dtype` and a CUSTOM_FUNCTION's comes out of a new
# `CustomFunction` dataclass. Same trap as the fold.bend fp8 masks: the value a
# pattern matches on is not a constant here, it is a DERIVED one.
#
# `u.body` is `u.src[0]` -- ops.py:562-565 -- and it is a `# TODO(p3)` in
# ops.bend, so it is read as `Arena.src0` here rather than ported there.
# `grad_fxn` and `aux` are DROPPED from ops.bend's `CallInfo` (ops.bend:1011-1018:
# a Python function object cannot be a `Data` field, and `aux` is the hcq side
# channel, P6), so in THIS port those two conjuncts are CONSTANT FALSE and the
# refusal reduces to `body.op is PROGRAM`. That is a WALL, stated: a call with a
# grad_fxn cannot be built in this port at all, so it cannot be rendered either,
# and there is no fixture that could separate the two.
# ---------------------------------------------------------------------------
def pyr_call.body_prog(body: O.Op) -> Bool:
  match body:
    case O.OpsPROGRAM{}: True{}
    case _: False{}

# `u.op is Ops.CALL and u.body.op is Ops.PROGRAM` -- the head predicate, minus
# the two CallInfo conjuncts that ops.bend's `CallInfo` cannot carry.
def pyr_call.of(op: O.Op, body: O.Op) -> Bool:
  match op:
    case O.OpsCALL{}: pyr_call.body_prog(body)
    case _: False{}

def pyr_call(+ar: O.Arena, +u: U32) -> Bool:
  pyr_call.of(O.Arena.op(ar, u), O.Arena.op(ar, O.Arena.src0(ar, u)))

def pyr_buffer.of(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsBUFFER{}: pyr_buffer.pa(a)
    case _: False{}

# "a BUFFER carrying a device Buffer can't be pyrendered". UNCHANGED upstream, and
# MEASURED unchanged: `78d482262` deleted the rule that RENDERED a BUFFER but
# kept this refusal, so the two ends agree that a `ParamArg` with a live `Buffer`
# is refused (`REFUSED:buffer can't be pyrendered` at both, `.agents/slop/xd1/
# bufref.py`) and that a `ParamArg` with `buffer=None` is not. Recording it as a
# re-verified-no-change rather than assuming: the deletion above made it LOOK
# like this predicate had to move too, and it does not.
def pyr_buffer(+ar: O.Arena, +u: U32) -> Bool:
  pyr_buffer.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

# THE REFUSAL ROWS. A Bool, not a string, because `pyrender` cannot REFUSE in
# Bend -- there is no `raise` and `pyrender`'s type is `String` -- so the two
# upstream `raise NotImplementedError` are PREDICATES and a predicate with no row
# is exactly what let `pyr_call` go stale through `78d482262` with nothing
# noticing. `b2u_nat` is the `Bool -> U32` spelling every other count row uses.
def pyr_row(nm: String, py: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, " = [", Bool.show(b), "]   py=[", py, "]"]))

# RULE 1. `UOp.const(3)` -- a CONST with `src=()`, the only shape rule 1 matches.
def g_const() -> O.Found: f_const(O.Arena.empty(), 3)

# RULE 2. The CAST's dtype (`float`) DIFFERS from its src's (`weakint`), which is
# the guard. Equal dtypes fall through to rule 15 and `copy`'s BUFFER is the row
# that shows a GLOBAL ParamArg printing at all.
def g_cast() -> O.Found:
  +c = f_const(O.Arena.empty(), 3)
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.single()}, O.TNone{})

# RULE 3. SPECIAL with exactly ONE src, and that src a CONST -- both halves of
# the guard. `UOp.special(4, 'gidx')`.
def g_special() -> O.Found:
  +c = f_const(O.Arena.empty(), 4)
  O.UOp.special(O.Found.ar(c), O.Found.i(c), "gidx")

# ===========================================================================
# RULE 4 WAS DELETED UPSTREAM, so every BUFFER row below renders through RULE 15.
# `g_buffer` MOVED (it printed `UOp.new_buffer(...)` at the pin) and the three
# beside it did not, which is the shape of the deletion:
#
#   * `g_buffer`   GLOBAL + device  -> MOVED. Rule 4 claimed it at the pin.
#   * `g_buflocal` LOCAL           -> UNMOVED. Rule 4's guard refused it at the
#     pin too, so it was ALREADY a rule-15 node and the deletion is invisible.
#   * `g_bufnodev` device=None      -> UNMOVED for the same reason.
#   * `g_bufimage` image=(2,2)      -> UNMOVED for the same reason, and it is
#     the row that would have caught `max_numel` had the rule survived, because
#     `max_numel` is `prod((img[0], img[1], 4))` and the size the pin printed was
#     16 rather than the ParamArg's 4.
#
# THE LOCAL ROW IS NOT REDUNDANT. It is the negative fixture that says the
# deletion is "rule 4 is gone", not "every BUFFER renders the same": one row
# cannot distinguish those, and `agent-core.md` asks for a negative case beside
# every one.
# ===========================================================================
# RULE 4 (DELETED). The RANGE gets its OWN line: BUFFER and RANGE are both
# `always_rendered`, so they split even with one consumer each.
def g_buffer() -> O.Found: f_buf(O.Arena.empty(), S.D1{0}, 4)

# RULE 5. `c2.copy_to_device('METAL')`. The COPY rule reads only src[0], so the
# `('CPU', 'METAL')` TUPLE device in the buffer is what makes this row different
# from `buffer` -- it is `dev_repr`'s Dn arm inside a rendered node.
def g_copy() -> O.Found:
  +b = f_buf(O.Arena.empty(), S.Dn{[0, 2]}, 4)
  O.UOp.new(O.Found.ar(b), O.OpsCOPY{}, [O.Found.i(b)], O.AStr{"METAL"}, O.TNone{})

def f_bufr(+r: O.Found, pa: O.ParamArg) -> O.Found:
  O.UOp.new(O.Found.ar(r), O.OpsBUFFER{}, [O.Found.i(r)], O.AParam{pa}, O.TNone{})

def g_buflocal() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.ALocal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}})

def g_bufnodev() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, None{},
      False{}, None{}, None{}, False{}, None{}})

# `ParamArg` is read POSITIONALLY (ops.bend:865-881), so its field ORDER is the
# contract, and a fixture that puts `image` where `buffer` goes fails to compile
# naming the wrong field -- the one place a field-order mistake is LOUD.
def g_bufimage() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, Some{O.Img{2, 2}}, None{}, False{}, None{}})

# THE ONE FIXTURE THAT EXERCISES `pyr_buffer`, the second refusal. A ParamArg
# carrying a live `Buffer` is refused at BOTH ends (`.agents/slop/xd1/bufref.py`),
# so this row pins a predicate that did NOT move -- recorded, because "rule 4 was
# deleted so `pyr_buffer` must have moved too" is the obvious wrong inference and
# it is worth a row that says otherwise.
#
# THE `buffer` SLOT IS `Some{9}` AND NOT `Some{4}` BECAUSE OF MUTATION M-j, WHICH
# MOVED NOTHING while both were `Some{4}`: `pyr_buffer.pa` reads
# `ParamArg.buffer`, and a mutation reading `ParamArg.size` instead answers the
# SAME thing on every fixture that existed. The size is the element count and the
# buffer slot is a registry index, so they are DIFFERENT numbers in every real
# `ParamArg` -- which is why making them equal in a fixture is a fixture bug and
# not a neutral choice.
def g_bufrefused() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, Some{9}, False{}, None{}})

# RULE 6. `UOp(Ops.CUSTOM_FUNCTION, src=(...), arg='myfn')` -- the arg is a
# quoted string, so this row also pins `arg_repr`'s AStr arm.
def g_cfn() -> O.Found:
  +a = f_const(O.Arena.empty(), 3)
  +b = f_const(O.Found.ar(a), 4)
  O.UOp.new(O.Found.ar(b), O.OpsCUSTOM_FUNCTION{}, [O.Found.i(a), O.Found.i(b)], O.AStr{"myfn"}, O.TNone{})

# RULE 7. `c2._rop(Ops.ADD, (0, 1))` -- `tuple(range(2))` and `Ops.ADD` inside
# the REDUCE's arg, so this row pins `range_tuple` and `reduce_op` together.
def g_reduce() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +s = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  O.UOp.new(O.Found.ar(s), O.OpsREDUCE{}, [O.Found.i(s)], O.AReduce{O.OpsADD{}, 2}, O.TNone{})

# RULE 8a. `UOp.range(4, 0, AxisType.WEAK)` -- the CONST's value, then the HEAD
# rule's `axis_id[0]`, then `axis_type`. NOTE THIS ROW DID NOT MOVE when the rule
# was rewritten: the printed string is byte-identical at both ends of the pin
# window (`.agents/slop/xd1/render-rows.py`, row `pyrender range`), because the
# old rule's `[repr(y) for y in x.arg]` happened to walk the arg in the same
# order the new rule names the three values. A green row over a rewritten rule is
# not evidence the rewrite is right -- it is evidence the rewrite is
# BEHAVIOUR-PRESERVING on the shape you happened to test. `flat2` below is the
# row that is not, and it exists for exactly that reason.
def g_range() -> O.Found: f_rng(O.Arena.empty(), 4, 0)

# RULE 8's NEW GUARD, `len(x.axis_id) == 1`, on the FALSE arm. `flat1` is the
# control (one id, guard passes, the row is a `UOp.range(...)` CALL) and `flat2`
# / `flat3` are the arm: the guard refuses, the node falls THROUGH to rule 15,
# and rule 15 prints `repr(u.arg)`. Three rows rather than one because the guard
# is `== 1` and not `>= 1` -- `flat3` is the only row that separates the two.
def g_flat1() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0])

def g_flat2() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0, 1])

def g_flat3() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0, 1, 2])

# RULE 8b. A RANGE with a SECOND src, which is the `, src=(...)` tail. This is
# the only fixture that reaches that branch of rule 8 -- render.py's own comment
# says "range has srcs sometimes after control flow".
def g_range2() -> O.Found:
  +a = f_const(O.Arena.empty(), 4)
  +b = f_const(O.Found.ar(a), 0)
  O.UOp.new(O.Found.ar(b), O.OpsRANGE{}, [O.Found.i(a), O.Found.i(b)], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{})

# RULE 9. `UOp.const(7).alu(Ops.CDIV, UOp.const(2))` -- CDIV is excluded from
# rule 12 because `//` parses as FLOORDIV, so it can only be written `.alu`.
def g_cdiv() -> O.Found:
  +a = f_const(O.Arena.empty(), 7)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.alu(O.Found.ar(b), O.OpsCDIV{}, [O.Found.i(a), O.Found.i(b)])

# RULE 10. CMOD, the `%` sibling of rule 9 -- same arm, different op.
def g_cmod() -> O.Found:
  +a = f_const(O.Arena.empty(), 7)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.alu(O.Found.ar(b), O.OpsCMOD{}, [O.Found.i(a), O.Found.i(b)])

# RULE 11. `.alu(Ops.WHERE, ...)` with THREE srcs, because `.where` re-promotes
# its operands and so cannot be written infix.
def g_where() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = f_const(O.Found.ar(a), 2)
  +c = f_const(O.Found.ar(b), 3)
  O.UOp.alu(O.Found.ar(c), O.OpsWHERE{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)])

# RULE 12a, the infix arm, through `strip_binary_parens` and `precedence`: the
# inner `*` keeps its parens under the `+` and the outer `+` strips its own.
def g_nest() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +m1 = f_const(O.Found.ar(ab), 4294967295)
  +mb = O.UOp.alu(O.Found.ar(m1), O.OpsMUL{}, [O.Found.i(b), O.Found.i(m1)])
  +am = O.UOp.alu(O.Found.ar(mb), O.OpsADD{}, [O.Found.i(a), O.Found.i(mb)])
  +p = O.UOp.alu(O.Found.ar(am), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(am)])
  +c = f_const(O.Found.ar(p), 3)
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(p), O.Found.i(c)])

# RULE 12b, the `.alu(...)` else arm: a THREE-src syms node. `_broadcasted`
# returns a PAIR, so `== x.src` is an ARITY test and three srcs miss it.
def g_mul3() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [1], O.AXIS_WEAK{})
  +c3 = f_const(O.Found.ar(r1), 3)
  O.UOp.alu(O.Found.ar(c3), O.OpsMUL{}, [O.Found.i(r0), O.Found.i(r1), O.Found.i(c3)])

# RULE 12b on a different op: `.alu(Ops.XOR, ..)`. XOR is in `syms` so the
# OTHER arm of rule 12 would print `^`, and this row proves the op table and
# the arity test are independent.
def g_xor3() -> O.Found:
  +c8 = f_const(O.Arena.empty(), 8)
  +r0 = f_range(O.Found.ar(c8), O.Found.i(c8), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [1], O.AXIS_WEAK{})
  +c5 = f_const(O.Found.ar(r1), 5)
  O.UOp.alu(O.Found.ar(c5), O.OpsXOR{}, [O.Found.i(r0), O.Found.i(r1), O.Found.i(c5)])

# RULE 13. `UOp.sqrt()` -- the `src=()` arm of the sugar rules. It is the only
# fixture whose toposort is a SINGLE node, so it also pins "ast is the last
# element" in `_render_with_splits`.
def g_sqrt() -> O.Found: O.UOp.new(O.Arena.empty(), O.OpsSQRT{}, Nil{}, O.ANone{}, O.TNone{})

# RULE 14 with srcs and NO arg: `UOp.const(9).index(c2)`. The RANGE splits onto
# its own line because RANGE is `always_rendered`. The arg clause is covered by
# `reduce0` below, whose arg is a shape ops.bend's `ARange` does not model.
def g_index() -> O.Found:
  +a = f_const(O.Arena.empty(), 9)
  +c = f_const(O.Found.ar(a), 4)
  +r = f_range(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r), O.OpsINDEX{}, [O.Found.i(a), O.Found.i(r)], O.ANone{}, O.TNone{})

# RULE 7's GUARD, the other way: `arg[1]` is 0, so rule 7 returns None and the
# node falls through to rule 13/14. That is the ONLY way to see `arg=(...)` on a
# sugar node, and it puts the clause after the srcs -- `c1.reduce(arg=(Ops.ADD, 0))`.
def g_reduce0() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r0), O.OpsREDUCE{}, [O.Found.i(r0)], O.AReduce{O.OpsADD{}, 0}, O.TNone{})

# RULE 15, the fallback, and the only way to see it: SUB is in `syms` but is
# SUBTRACTED from rule 12's set, so it renders as a constructor call.
def g_sub() -> O.Found:
  +a = f_const(O.Arena.empty(), 9)
  +b = f_const(O.Found.ar(a), 4)
  O.UOp.alu(O.Found.ar(b), O.OpsSUB{}, [O.Found.i(a), O.Found.i(b)])

# `.rtag('mytag')` -- `if u.tag is not None: ren += ...`, appended to the
# rendered node and NOT part of `pmp`. An untagged node must contribute NOTHING
# here, which is what every other row checks by ABSENCE.
def g_tagged() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.new(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TStr{"mytag"})

# THE CONSUMER TEST. `c2` has TWO consumers, so it gets its own line -- the
# `len(cmap[u]) == 1` half of `to_render`. The outer MUL has one consumer (the
# ast) and stays inline.
def g_shared() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c = f_const(O.Found.ar(ab), 3)
  +d = O.UOp.alu(O.Found.ar(c), O.OpsSUB{}, [O.Found.i(ab), O.Found.i(c)])
  O.UOp.alu(O.Found.ar(d), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(d)])

# THE FUEL ROW, and the one fixture built for a walk rather than for a rule.
# `ab` has SIX consumers, so the arena carries five in-edges more than a tree
# would: E is 24, N is 21, and the walk needs 44 pops where `2 * len(arena)` is
# 42. The two it loses are the LAST two, and the ast's own `Frame{n, True}` is
# the very last, so the fuel `2N` drops the `ast =` line and answers a toposort
# missing its sink. `Arena.budget` is nodes PLUS edges.
# `nest` was the witness for this until the fixtures moved: its two shared
# CONSTs put N + E at exactly 2N, so it could not tell the two bounds apart.
def g_fan() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c3 = f_const(O.Found.ar(ab), 3)
  +m1 = O.UOp.alu(O.Found.ar(c3), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c3)])
  +c4 = f_const(O.Found.ar(m1), 4)
  +m2 = O.UOp.alu(O.Found.ar(c4), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c4)])
  +c5 = f_const(O.Found.ar(m2), 5)
  +m3 = O.UOp.alu(O.Found.ar(c5), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c5)])
  +c6 = f_const(O.Found.ar(m3), 6)
  +m4 = O.UOp.alu(O.Found.ar(c6), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c6)])
  +c7 = f_const(O.Found.ar(m4), 7)
  +m5 = O.UOp.alu(O.Found.ar(c7), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c7)])
  +c8 = f_const(O.Found.ar(m5), 8)
  +m6 = O.UOp.alu(O.Found.ar(c8), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c8)])
  +s1 = O.UOp.alu(O.Found.ar(m6), O.OpsADD{}, [O.Found.i(m1), O.Found.i(m2)])
  +s2 = O.UOp.alu(O.Found.ar(s1), O.OpsADD{}, [O.Found.i(s1), O.Found.i(m3)])
  +s3 = O.UOp.alu(O.Found.ar(s2), O.OpsADD{}, [O.Found.i(s2), O.Found.i(m4)])
  +s4 = O.UOp.alu(O.Found.ar(s3), O.OpsADD{}, [O.Found.i(s3), O.Found.i(m5)])
  O.UOp.alu(O.Found.ar(s4), O.OpsADD{}, [O.Found.i(s4), O.Found.i(m6)])

# THE SINK ARM of `to_render`: a SINK adds ALL of its srcs before the
# `continue`, so BOTH children split. The SQRT is rule 14 and the MUL rule 12.
def g_sink() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c = f_const(O.Found.ar(ab), 5)
  +m = O.UOp.alu(O.Found.ar(c), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c)])
  +s = O.UOp.new(O.Found.ar(m), O.OpsSQRT{}, [O.Found.i(ab)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(s), [O.Found.i(m), O.Found.i(s)])

# THE STORE ARM: a STORE adds src[1] -- the BUFFER -- which then splits even
# though it has one consumer, because STORE is not in `always_rendered` but the
# add happens BEFORE the `continue`.
def g_store() -> O.Found:
  +a = f_const(O.Arena.empty(), 0)
  +b = f_buf(O.Found.ar(a), S.D1{0}, 4)
  O.UOp.new(O.Found.ar(b), O.OpsSTORE{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

# THE REDUCE ARM: a REDUCE adds src[0], and src[1] splits too because the REDUCE
# has TWO consumers for it -- the rule-7 `._rop` reads src[0] only, so src[1] is
# otherwise unused and would stay inline.
def g_reduce2() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r1), O.OpsREDUCE{}, [O.Found.i(r0), O.Found.i(r1)], O.AReduce{O.OpsMAX{}, 2}, O.TNone{})

# ===========================================================================
# THE REFUSAL ROWS. Until this unit these were unreachable: the header said
# "the gate prints them" and `main` printed neither, and `to_render` asked
# neither -- so `pyr_call` had a `def` line and no call site anywhere in the
# tree. `rg -n "pyr_call\(" tinybendygrad/` returns its own definition and
# nothing else, which is the `schedule/indexing.bend` finding: a def nothing
# calls is invisible to every other check. So no row COULD have caught the
# predicate rewrite, and the answer is structural rather than a bad fixture.
#
# THE ROWS ARE THE PREDICATES, not a rendered string, because Bend has no way to
# raise and `pyrender` therefore cannot refuse -- the wall is stated at the foot
# of this file. A predicate with no row is what let the predicate go stale
# through `78d482262` unnoticed.
#
# FOUR BODIES, because the rewrite is NOT a widening and the disagreements run
# BOTH ways. MEASURED over 4 bodies x 4 CallInfo shapes, 16 refusals
# (`.agents/slop/xd1/call-refusal-oracle.py`):
#
#   NOOP    plain  pin REFUSED -> head RENDERED  (the pin's `dtype is void and
#                                                    op is not CUSTOM_FUNCTION`
#                                                    half, which is GONE)
#   NOOP    named  pin REFUSED -> head RENDERED  (a `name` is not a `grad_fxn`)
#   PROGRAM plain  pin REFUSED -> head REFUSED    (the control: both refuse)
#   CONST   plain  pin RENDERED -> head RENDERED (the other control)
#
# `pyr_call_prog` is the positive control, so a predicate that refused EVERY
# CALL passes it and fails the other three -- which is the mutation M-c below.
# ===========================================================================
def f_call(ar: O.Arena, +body: O.Found, ci: O.CallInfo) -> O.Found:
  O.UOp.new(ar, O.OpsCALL{}, [O.Found.i(body)], O.ACall{ci}, O.TNone{})

def g_call_noop() -> O.Found:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(n), n, O.CallInfo.of())

def g_call_prog() -> O.Found:
  +p = O.UOp.new(O.Arena.empty(), O.OpsPROGRAM{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(p), p, O.CallInfo.of())

def g_call_const() -> O.Found:
  +c = f_const(O.Arena.empty(), 3)
  f_call(O.Found.ar(c), c, O.CallInfo.of())

def g_call_named() -> O.Found:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(n), n, ci_named())

def main() -> IO(Unit):
  do IO<Unit>:
    py_row("pyrender const   ", "ast = UOp.const(3)", g_const())
    py_row("pyrender cast    ", "ast = UOp.const(3).cast(dtypes.f32)", g_cast())
    py_row("pyrender special ", "ast = UOp.special(4, 'gidx')", g_special())
    py_row("pyrender buffer  ", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU'))", g_buffer())
    py_row("pyrender copy    ", "c1 = UOp.range(4, 0, AxisType.WEAK)\nc2 = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device=('CPU', 'METAL')))\nast = c2.copy_to_device('METAL')", g_copy())
    py_row("pyrender reduce  ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2._rop(Ops.ADD, (0, 1))", g_reduce())
    py_row("pyrender range   ", "ast = UOp.range(4, 0, AxisType.WEAK)", g_range())
    py_row("pyrender range2  ", "ast = UOp.range(4, 0, AxisType.LOOP, src=(UOp.const(0),))", g_range2())
    py_row("pyrender cdiv    ", "ast = UOp.const(7).alu(Ops.CDIV, UOp.const(2))", g_cdiv())
    py_row("pyrender cmod    ", "ast = UOp.const(7).alu(Ops.CMOD, UOp.const(2))", g_cmod())
    py_row("pyrender where   ", "ast = UOp.const(True).alu(Ops.WHERE, UOp.const(2), UOp.const(3))", g_where())
    py_row("pyrender nest    ", "ast = (UOp.const(1)+UOp.const(2))*(UOp.const(1)+UOp.const(2)*UOp.const(-1))+UOp.const(3)", g_nest())
    py_row("pyrender mul3    ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nc3 = UOp.range(4, 1, AxisType.WEAK)\nast = c1.alu(Ops.MUL, c3)", g_mul3())
    py_row("pyrender xor3    ", "c1 = UOp.range(8, 0, AxisType.WEAK)\nc3 = UOp.range(4, 1, AxisType.WEAK)\nast = c1.alu(Ops.XOR, c3)", g_xor3())
    py_row("pyrender sqrt    ", "ast = UOp.sqrt()", g_sqrt())
    py_row("pyrender index   ", "c2 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp.const(9).index(c2)", g_index())
    py_row("pyrender reduce0 ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nast = c1.reduce(arg=(Ops.ADD, 0))", g_reduce0())
    py_row("pyrender sub     ", "ast = UOp(Ops.SUB, (UOp.const(9), UOp.const(4)))", g_sub())
    py_row("pyrender tagged  ", "ast = (UOp.const(1)+UOp.const(2)).rtag('mytag')", g_tagged())
    py_row("pyrender shared  ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2*UOp(Ops.SUB, (c2, UOp.const(3)))", g_shared())
    py_row("pyrender fan     ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2*UOp.const(3)+c2*UOp.const(4)+c2*UOp.const(5)+c2*UOp.const(6)+c2*UOp.const(7)+c2*UOp.const(8)", g_fan())
    py_row("pyrender sink    ", "c2 = UOp.const(1)+UOp.const(2)\nc4 = c2*UOp.const(5)\nc5 = c2.sqrt()\nast = c4.sink(c5)", g_sink())
    py_row("pyrender store   ", "c2 = UOp.range(4, 0, AxisType.WEAK)\nc3 = UOp(Ops.BUFFER, (c2,), ParamArg(0, dtypes.i32, 4, device='CPU'))\nast = UOp.const(0).store(c3)", g_store())
    py_row("pyrender reduce2 ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nc3 = UOp.range(4, 0, AxisType.WEAK)\nast = c1._rop(Ops.MAX, (0, 1))", g_reduce2())
    py_row("pyrender flat1   ", "ast = UOp.range(4, 0, AxisType.WEAK)", g_flat1())
    py_row("pyrender flat2   ", "ast = UOp(Ops.RANGE, (UOp.const(4),), (AxisType.WEAK, 0, 1))", g_flat2())
    py_row("pyrender flat3   ", "ast = UOp(Ops.RANGE, (UOp.const(4),), (AxisType.WEAK, 0, 1, 2))", g_flat3())
    py_row("pyrender buflocal", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, addrspace=AddrSpace.LOCAL, device='CPU'))", g_buflocal())
    py_row("pyrender bufnodev", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4))", g_bufnodev())
    py_row("pyrender bufimage", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU', image=(2, 2)))", g_bufimage())
    # `pyrender cfn` IS THE ONE ROW WHOSE `py=` IS NOT HEAD'S, and it is left on
    # the PIN substrate ON PURPOSE. `78d482262` re-cut `Ops.CUSTOM_FUNCTION`'s arg
    # from a bare `str` to a new `CustomFunction` DATACLASS, so head prints
    # `arg=CustomFunction(name='myfn', dtype=dtypes.void)` -- MEASURED,
    # `.agents/slop/xd1/render-rows.py` row `pyrender cfn` -- and `ops.bend` has
    # NOT been re-cut for it (ops.bend:4705-4712 names it P6 and says the re-cut
    # "is ONE change, not two"). So the port has no `CustomFunction` arm and this
    # row pins the arm it DOES have.
    #
    # It is NOT a row encoding a bug: `arg_repr` correctly renders the arg it is
    # HANDED, and which arg that is is ops.bend's decision. Moving the `py=` to
    # head's answer would turn another file's substrate gap into a permanently red
    # row here -- the `dtype.bend` 14-unfilled-laws situation in a new hat. It
    # goes GREEN, with no edit here, the day ops.bend gains the datatype.
    py_row("pyrender cfn     ", "ast = UOp(Ops.CUSTOM_FUNCTION, src=(UOp.const(3), UOp.const(4)), arg='myfn')", g_cfn())
    py_row("pyrender copy    ", "c1 = UOp.range(4, 0, AxisType.WEAK)\nc2 = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device=('CPU', 'METAL')))\nast = c2.copy_to_device('METAL')", g_copy())
    py_row("pyrender reduce  ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2._rop(Ops.ADD, (0, 1))", g_reduce())
    py_row("pyrender range   ", "ast = UOp.range(4, 0, AxisType.WEAK)", g_range())
    py_row("pyrender range2  ", "ast = UOp.range(4, 0, AxisType.LOOP, src=(UOp.const(0),))", g_range2())
    py_row("pyrender cdiv    ", "ast = UOp.const(7).alu(Ops.CDIV, UOp.const(2))", g_cdiv())
    py_row("pyrender cmod    ", "ast = UOp.const(7).alu(Ops.CMOD, UOp.const(2))", g_cmod())
    py_row("pyrender where   ", "ast = UOp.const(True).alu(Ops.WHERE, UOp.const(2), UOp.const(3))", g_where())
    py_row("pyrender nest    ", "ast = (UOp.const(1)+UOp.const(2))*(UOp.const(1)+UOp.const(2)*UOp.const(-1))+UOp.const(3)", g_nest())
    py_row("pyrender mul3    ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nc3 = UOp.range(4, 1, AxisType.WEAK)\nast = c1.alu(Ops.MUL, c3)", g_mul3())
    py_row("pyrender xor3    ", "c1 = UOp.range(8, 0, AxisType.WEAK)\nc3 = UOp.range(4, 1, AxisType.WEAK)\nast = c1.alu(Ops.XOR, c3)", g_xor3())
    py_row("pyrender sqrt    ", "ast = UOp.sqrt()", g_sqrt())
    py_row("pyrender index   ", "c2 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp.const(9).index(c2)", g_index())
    py_row("pyrender reduce0 ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nast = c1.reduce(arg=(Ops.ADD, 0))", g_reduce0())
    py_row("pyrender sub     ", "ast = UOp(Ops.SUB, (UOp.const(9), UOp.const(4)))", g_sub())
    py_row("pyrender tagged  ", "ast = (UOp.const(1)+UOp.const(2)).rtag('mytag')", g_tagged())
    py_row("pyrender shared  ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2*UOp(Ops.SUB, (c2, UOp.const(3)))", g_shared())
    py_row("pyrender fan     ", "c2 = UOp.const(1)+UOp.const(2)\nast = c2*UOp.const(3)+c2*UOp.const(4)+c2*UOp.const(5)+c2*UOp.const(6)+c2*UOp.const(7)+c2*UOp.const(8)", g_fan())
    py_row("pyrender sink    ", "c2 = UOp.const(1)+UOp.const(2)\nc4 = c2*UOp.const(5)\nc5 = c2.sqrt()\nast = c4.sink(c5)", g_sink())
    py_row("pyrender store   ", "c2 = UOp.range(4, 0, AxisType.WEAK)\nc3 = UOp(Ops.BUFFER, (c2,), ParamArg(0, dtypes.i32, 4, device='CPU'))\nast = UOp.const(0).store(c3)", g_store())
    py_row("pyrender reduce2 ", "c1 = UOp.range(16, 0, AxisType.WEAK)\nc3 = UOp.range(4, 0, AxisType.WEAK)\nast = c1._rop(Ops.MAX, (0, 1))", g_reduce2())
    # THE REFUSAL ROWS. `py=` values MEASURED by `.agents/slop/xd1/
    # call-refusal-oracle.py` over 4 bodies x 4 CallInfo shapes; the pin column is
    # in each comment so a reader can see which of these MOVED and which did not.
    #
    # `pyr_call_noop` and `pyr_call_named` MOVED False (pin: refused -- the pin
    # keyed on `body.dtype is void`, and a NOOP body is void). `pyr_call_prog` and
    # `pyr_call_const` did NOT move, and they are the two controls: a predicate
    # that refused every CALL passes `pyr_call_prog` and fails the other two, so
    # the control is what makes the pair a test rather than two agreeing rows.
    pyr_row("pyr_call_noop    ", "False", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_noop()))), O.Found.i(g_call_noop())))
    pyr_row("pyr_call_prog    ", "True", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_prog()))), O.Found.i(g_call_prog())))
    pyr_row("pyr_call_const   ", "False", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_const()))), O.Found.i(g_call_const())))
    pyr_row("pyr_call_named   ", "False", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_named()))), O.Found.i(g_call_named())))
    # THE BUFFER REFUSAL, which did NOT move: both ends refuse a ParamArg
    # carrying a live `Buffer` (`.agents/slop/xd1/bufref.py`). `buf_plain` is the
    # negative fixture, and it is the row that says the predicate is not "BUFFER".
    pyr_row("pyr_buffer_plain ", "False", pyr_buffer(F.Folded.ar(F.folded(O.Found.ar(g_buffer()))), O.Found.i(g_buffer())))
    pyr_row("pyr_buffer_held  ", "True", pyr_buffer(F.Folded.ar(F.folded(O.Found.ar(g_bufrefused()))), O.Found.i(g_bufrefused())))
    py_row("pyrender flat1   ", "ast = UOp.range(4, 0, AxisType.WEAK)", g_flat1())
    py_row("pyrender flat2   ", "ast = UOp(Ops.RANGE, (UOp.const(4),), (AxisType.WEAK, 0, 1))", g_flat2())
    py_row("pyrender flat3   ", "ast = UOp(Ops.RANGE, (UOp.const(4),), (AxisType.WEAK, 0, 1, 2))", g_flat3())
    py_row("pyrender buflocal", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, addrspace=AddrSpace.LOCAL, device='CPU'))", g_buflocal())
    py_row("pyrender bufnodev", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4))", g_bufnodev())
    py_row("pyrender bufimage", "c1 = UOp.range(4, 0, AxisType.WEAK)\nast = UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU', image=(2, 2)))", g_bufimage())
    IO.print("sint_show 0      = [" ++ sint_show(0) ++ "]   py=0")
    IO.print("sint_show 7      = [" ++ sint_show(7) ++ "]   py=7")
    IO.print("sint_show 2**31-1= [" ++ sint_show(2147483647) ++ "] py=2147483647")
    IO.print("sint_show -3     = [" ++ sint_show(4294967293) ++ "] py=-3")
    IO.print("sint_show -2**31 = [" ++ sint_show(2147483648) ++ "] py=-2147483648")
    IO.print("f32_repr 3.0     = [" ++ f32_repr(3.0) ++ "]     py=3.0")
    IO.print("f32_repr 1e30    = [" ++ f32_repr(1000000000000000000000000000000.0) ++ "]     py=1e+30")
    IO.print("f32_repr 0.1     = [" ++ f32_repr(0.1) ++ "]     py=0.1")
    IO.print("const_repr CInt  = [" ++ const_repr(O.CInt{H.i64_of_i32(3)}) ++ "]   py=3")
    IO.print("const_repr CBool = [" ++ const_repr(O.CBool{True{}}) ++ "]   py=True")
    IO.print("const_repr CInv  = [" ++ const_repr(O.CInvalid{}) ++ "]   py=Invalid")
    IO.print("const_repr CFlt  = [" ++ const_repr(O.CFloat{2.5}) ++ "]   py=ConstFloat(2.5)")
    IO.print("dt_repr float    = [" ++ dt_repr(S.single()) ++ "]   py=dtypes.f32")
    IO.print("dt_repr int32    = [" ++ dt_repr(S.int32()) ++ "]   py=dtypes.i32")
    IO.print("addr_repr GLOBAL = [" ++ addr_repr(S.AGlobal{}) ++ "]   py=AddrSpace.GLOBAL")
    IO.print("dev_repr D1(2)   = [" ++ dev_repr(S.D1{2}) ++ "]   py='METAL'")
    IO.print("dev_repr Dn      = [" ++ dev_repr(S.Dn{[0, 2]}) ++ "]   py=('CPU', 'METAL')")
    IO.print("syms_of MUL      = [" ++ syms_of(O.OpsMUL{}) ++ "]   py=*")
    IO.print("prec_of MUL      = [" ++ U32.show(precedence_of(O.OpsMUL{})) ++ "]   py=1")
    IO.print("prec_of CDIV     = [" ++ U32.show(precedence_of(O.OpsCDIV{})) ++ "]   py=99")
    IO.print("arg_repr ANone   = [" ++ arg_repr(O.ANone{}) ++ "]   py=None")
    IO.print("arg_repr ADt     = [" ++ arg_repr(O.ADt{S.int32()}) ++ "]   py=dtypes.i32")
    IO.print("arg_repr AStr    = [" ++ arg_repr(O.AStr{"g"}) ++ "]   py='g'")
    # MOVED with `78d482262`. `py=` MEASURED, `.agents/slop/xd1/argrepr.py` row
    # `arg_repr ARng1id`: the pin's arg is `((0,), AxisType.GLOBAL)` and head's is
    # `(AxisType.GLOBAL, 0)` -- the type FIRST and NO inner tuple, because head's
    # `axis_id` is `arg[1:]`, the flat tail. The old answer was also missing the
    # one-element comma (see `u32_tuple_repr`), which is why it read `((0), ...)`.
    IO.print("arg_repr ARng    = [" ++ arg_repr(O.ARange{[0], O.AXIS_GLOBAL{}}) ++ "]   py=(AxisType.GLOBAL, 0)")
    IO.print("arg_repr ARed    = [" ++ arg_repr(O.AReduce{O.OpsADD{}, 2}) ++ "]   py=(Ops.ADD, 2)")
    IO.print("arg_repr ATup    = [" ++ arg_repr(O.ATuple{[1, 2]}) ++ "]   py=(1, 2)")
    # `ATup1` EXISTS BECAUSE MUTATION M-h MOVED NOTHING. `ATup` has TWO elements,
    # so `u32_tuple_repr`'s one-element comma arm had no fixture at all and the
    # comma could be deleted with every row green. `repr((0,)) == '(0,)'` and
    # `repr(()) == '()'` are MEASURED at both ends (`.agents/slop/xd1/argrepr.py`),
    # so the three rows together pin all three lengths -- and the `ATup0` row is
    # what separates "empty" from "one element with a comma".
    IO.print("arg_repr ATup1   = [" ++ arg_repr(O.ATuple{[7]}) ++ "]   py=(7,)")
    IO.print("arg_repr ATup0   = [" ++ arg_repr(O.ATuple{Nil{}}) ++ "]   py=()")
    IO.print("arg_repr AInk    = [" ++ arg_repr(O.AInk{"w", S.single()}) ++ "]   py=('w', dtypes.f32)")
    IO.print("arg_repr AAllred = [" ++ arg_repr(O.AAllred{O.OpsADD{}, S.D1{2}}) ++ "]   py=(Ops.ADD, 'METAL')")
    IO.print("arg_repr ADev    = [" ++ arg_repr(O.ADev{S.D1{2}}) ++ "]   py='METAL'")
    IO.print("arg_repr ACALL   = [" ++ arg_repr(O.ACall{O.CallInfo.of()}) ++ "]   py=CallInfo(None, None, False, False)")
    # `ACALL2` / `ACALL3` ARE THE ONLY ROWS IN THIS FILE THAT DISAGREE WITH
    # CPython, AND BOTH DISAGREE FOR ONE REASON: `78d482262` DROPPED
    # `CallInfo.dtype` (it moved onto a new `CustomFunction` dataclass on the
    # body) and `ops.bend` has not been re-cut -- ops.bend:4705-4712 names it and
    # says the two halves "are ONE change, not two". MEASURED at head:
    # `repr(CallInfo(name="f"))` is `CallInfo(None, 'f', False, False)`, with no
    # `dtype=`, so the `dtype=` clause this file still prints does not exist
    # upstream any more.
    #
    # `.agents/slop/xd1/verify.py` names these two explicitly:
    #   PY!=CPYTHON arg_repr ACALL2   cpy "CallInfo(None, 'f', False, False)"
    #   PY!=CPYTHON arg_repr ACALL3   cpy "CallInfo(None, None, False, False)"
    # They are NOT edited to green here: the answer is right for the substrate
    # ops.bend provides and wrong for the substrate upstream provides, and moving
    # the `py=` would be encoding a port that does not exist. They go green, with
    # no edit here, the day ops.bend re-cuts `CallInfo`. That is the third row in
    # this file with that property, and it is why `verify.py` exists: a gate that
    # prints `answer == py` cannot tell this from a real bug.
    IO.print("arg_repr ACALL2  = [" ++ arg_repr(O.ACall{ci_named()}) ++ "]   py=CallInfo(None, 'f', False, False, dtype=dtypes.i32)")
    IO.print("arg_repr ACALL3  = [" ++ arg_repr(O.ACall{ci_weak()}) ++ "]   py=CallInfo(None, None, False, False, dtype=dtypes.weakint)")
    IO.print("arg_repr AKern   = [" ++ arg_repr(O.AKernel{O.KernelInfo.of()}) ++ "]")
    IO.print("                     py=KernelInfo(name='test', applied_opts=(), opts_to_apply=None, estimates=None, beam=0)")
    IO.print("arg_repr AProgr  = [" ++ arg_repr(O.AProgram{O.ProgramInfo.of()}) ++ "]")
    IO.print("                     py=ProgramInfo(global_size=(1, 1, 1), local_size=(1, 1, 1), vars=(), globals=(), outs=(), ins=(), target=)")
    IO.print("ops_repr ADD     = [" ++ O.Ops.name(O.OpsADD{}) ++ "]   py=Ops.ADD")
    IO.print("arg_repr AParam1 = [" ++ arg_repr(O.AParam{pa1()}) ++ "]")
    IO.print("                     py=ParamArg(1, dtypes.f32, 4, device='METAL')")
    IO.print("arg_repr AParam2 = [" ++ arg_repr(O.AParam{pa2()}) ++ "]")
    IO.print("                     py=ParamArg(2, dtypes.i32, name='g')")
    IO.print("arg_repr AParam3 = [" ++ arg_repr(O.AParam{pa3()}) ++ "]")
    IO.print("                     py=ParamArg(3, dtypes.f32, 4, addrspace=AddrSpace.LOCAL, volatile=True, image=(2, 2))")
    IO.print("tag_str  TStr    = [" ++ tag_str(O.TStr{"x"}) ++ "]   py=x")
    IO.print("tag_repr TStr    = [" ++ tag_repr(O.TStr{"x"}) ++ "]   py='x'")
    IO.print("tag_repr TNone   = [" ++ tag_repr(O.TNone{}) ++ "]   py=None")



# ===========================================================================
# `pyrender` -- render.py:143-167. `lst = list(ast.toposort())`, the to_render
# pass, `_render_with_splits`, and the final join.
#
# THE TWO `raise NotImplementedError` ARE NOT REPRODUCED as raises -- Bend has no
# exceptions and a rule that returns "cannot" has to return it. So they are two
# PREDICATES, which is more useful than an exception anyway: `spec.py:38` calls
# `test_pyrender(lst[-1])` on every compiled sink and a sink that hits either one
# silently produces nothing today.
#
# ...AND UNTIL THIS UNIT BOTH PREDICATES WERE DEAD. `pyr_call` and `pyr_buffer`
# had one `def` line each and ZERO call sites: `to_render` never asked either,
# and `main` printed neither. So the header sentence above was a claim about a
# thing nothing reached -- the `schedule/indexing.bend` three-functions finding,
# in miniature. No row could have caught the CALL predicate because no row
# called it, which is the answer to "could any row have caught site 4": no, and
# the reason is structural rather than an oversight of fixture choice.
# ===========================================================================


