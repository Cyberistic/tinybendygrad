# .agents/slop/ag-emit.bend -- THE EMITTER for tinybendygrad/runtime/autogen/libclang.bend
#
# ===========================================================================
# WHAT THIS IS.  A Bend program that emits a Bend file, from a DATA file, using
# the emission TEMPLATE of `tinygrad/runtime/support/autogen.py:240-241`:
#
#     lines.extend([f"@dll.bind({', '.join([tname(at) for at in [rt] + ats])})",
#                   f"def {nm(c)}({', '.join([f'{anm}:{typehint(at)}' ...])}) -> {typehint(rt)}: ..."])
#
# Two lines per FunctionDecl: the `@dll.bind` ABI payload, then the `def`.
# The census -- how many generated defs match that template, over how many
# generated defs -- is at `.agents/slop/ag-libclang.meta`.
#
# WHY IT NEEDS NO LIBCLANG.  The template's inputs are the RESULT NAME, the
# ORDERED parameter names, each parameter's ABI type, and the return type.  All
# four are already enumerated, as data, in `tinygrad/runtime/autogen/
# libclang.py`, which is the generator's own committed output for this header.
# So the FFI that autogen.py needs in order to walk an AST is replaced by
# reading the list.  WALL 1 blocks deriving a list; it does not block reading one.
#
# INPUT   .agents/slop/ag-libclang.tramp   one row per `@dll.bind` def:
#            name|retbind|rethint|[pname|pbind|phint]*
#         produced by `.agents/slop/ag-libclang-rows.py`, the ONE reader of
#         libclang.py.  `|` is the separator because no ctypes spelling and no
#         Python annotation in libclang.py contains one, and because
#         `String.split` in bend takes a single Char.
# OUTPUT  tinybendygrad/runtime/autogen/libclang.bend
#         ./bin/bend .agents/slop/ag-emit.bend -o ag-emit.bin && ./ag-emit.bin \
#           > tinybendygrad/runtime/autogen/libclang.bend
#
# SEVEN MEASURED bend 2.0.35 CONSTRAINTS shape every def below.  All are quoted
# at `.agents/slop/notes/bend2-constraints.md`.
#
#   1. DECLARATION ORDER IS LOAD-BEARING.  A def must PRECEDE every def it uses,
#      and mutual recursion is refused outright:
#        expected : a filled definition (an unfilled law is a dead claim)
#      This file is written in topological order.  `.agents/slop/ag-order.py`
#      CHECKS that order -- and its first three releases each corrupted the file
#      while reporting success, so its output is read, not trusted.
#   2. A def may call ITSELF and nothing else.  Every recursion here is
#      self-recursion over a STRUCTURALLY SHRINKING argument.
#   3. A self-call's arguments are read left to right and each must be passed
#      UNCHANGED until one shrinks.  In `group.go(rest, group.step(g, c))` the
#      LIST is therefore first: with the state first, the first argument is
#      computed and not shrinking, and the call is refused.
#   4. A `match` may only scrutinise a PARAMETER or a FIELD, never a computed
#      value, so every computed discriminator is bound by the caller.
#   5. A PARAMETER IS LINEAR unless marked `+`.  `String` and `List` parameters
#      read more than once carry `+`.  When a parameter shares a name with a
#      record FIELD the error names the FIELD's name, not the parameter's:
#      `def ty_in(s: String, ups: String)` reports `expected : ups`, and the
#      PARAMETER was renamed rather than the field.
#   6. `List.map`, `List.filter`, `List.sort` and `List.foldl` all take a closure,
#      and a closure type cannot spell `+`.  Nothing here reflects over a list.
#   7. `List.append(a, A, xs, ys)` is `xs ++ ys`, so it APPENDS `ys`.  Four walks
#      here wanted a prepend and were first written as if it appended the other
#      way, which silently REVERSED the trampoline order, the parameter order,
#      and the reconstructed `@dll.bind` payload.  `agent-core.md` records the
#      same trap as a head/tail swap.
#
# AND THE ONE THAT COST THE MOST TIME, because it is the trap this project has
# already been caught by twice:
#
#   `Bool.pick` CHOOSES an arm and EVALUATES BOTH.  A guard written with it is
#   not a guard.  It cost three separate silent wrong answers here:
#     * a blank-line skip in `trs_map` became 2^N -- twenty-one rows outlasted
#       the session;
#     * `ty_add.at` returned the REPLACED row instead of prepending it to the
#       tail, which DROPS every row behind it: the emitted type table had FIVE
#       rows where 76 spellings want seventy-odd, and a table that is too SHORT
#       reads as tidy rather than wrong;
#     * threading the replacement spelling through the whole tail added a SECOND
#       row for the same type and the table grew to 852.
#   A `match` on a Bool PARAMETER evaluates one arm, which is what a guard needs.
# ===========================================================================
import Base

# ===========================================================================
# SECTION 1 -- THE TYPES.
#
# `Ty` is the type table: one row per Bend type name, carrying every upstream
# spelling that resolves to it.  The mapping is MANY-TO-ONE and that is not an
# accident -- `typehint` and `tmap` deliberately disagree about the same value.
# autogen.py:108-109 spells `CXType_Int` as the annotation `int`;
# autogen.py:94-95 spells it as the ctypes ABI type `ctypes.c_int32`.  One Bend
# name, two upstream spellings, so the row holds a spelling SET: one row per
# spelling would collide on `I32`, and one row per Bend name without the set
# would drop the annotation the verifier has to check.
#
# `Pm` and `Tr` hold RAW upstream spellings.  Encoding them at construction time
# loses the spelling, and `Ty.ups` IS the spelling set -- a table built from
# encoded names records `Ptr_CChar` as its own upstream spelling.  `enc` is
# applied where a Bend NAME is needed and nowhere else.
#
# `Pb` is one ABI type in BOTH spellings, because the type row is keyed on the
# Bend name and carries the upstream spelling, and one `String` cannot hold two.
#
# `Gs` exists because autogen.py:239 groups each parameter's three facts --
# NAME, ABI type, `typehint` annotation -- out of a flat cell list, and the state
# has to travel through several defs.  A `Nat` parameter cannot carry it: an
# up-counter threaded as a parameter is the descent bend refuses.
# ===========================================================================

type Ty is Data: Ty{bend: String, ups: String}

type Pm is Data: Pm{nm: String, ty: String, hint: String}

type Trr is Data: Trr{nm: String, rb: String, rh: String, cells: List<&2, String>}

type Tr is Data: Tr{nm: String, rty: String, ret: String, ps: List<&2, Pm>}

type Pb is Data: Pb{bend: String, up: String}

type Gs is Data: Gs{st: Nat, nm: String, ty: String, hd: String, acc: List<&2, Pm>}

def ty(+b: String, +u: String) -> Ty: Ty{b, u}

def ty_bend(+t: Ty) -> String:
  match t:
    case Ty{bend, ups}: bend

def ty_ups(+t: Ty) -> String:
  match t:
    case Ty{bend, ups}: ups

def ty_le(+x: Ty, +y: Ty) -> Bool: String.is_le(ty_bend(x), ty_bend(y))

# autogen.py:91 tmap and :108 typehint, resolved to Bend names.  Every entry is a
# spelling that APPEARS in libclang.py; `ag-libclang.ty` is the census, and the
# emitted `ty_*` rows are checked for completeness against it.
def ty_prims() -> List<&2, Ty>:
  [ty("U32", "ctypes.c_uint32"),
   ty("I32", "ctypes.c_int32,int"),
   ty("I64", "ctypes.c_int64,time_t"),
   ty("U64", "ctypes.c_uint64,size_t"),
   ty("F64", "ctypes.c_double,float"),
   ty("CVoidP", "ctypes.c_void_p"),
   ty("CChar", "ctypes.c_char,bytes"),
   ty("CBool", "ctypes.c_bool,bool"),
   ty("CWChar", "ctypes.c_wchar,str"),
   ty("Unit", "None")]

# membership over a COMMA-joined spelling set.  Substring search would be wrong:
# `c.POINTER[CXString]` contains `CXString`, and an empty set contains
# everything.
def ty_in(+s: String, +set: String) -> Bool:
  Bool.or(String.eq(s, set), String.contains(String.concat([",", set, ","]), String.concat([",", s, ","])))

def enc_prim.find(+xs: List<&2, Ty>, +s: String) -> Maybe<&2, Ty>:
  match xs:
    case Nil{}: None{}
    case Ty{bend, ups} <> rest: List.find.put(Ty, Ty{bend, ups}, enc_prim.find(rest, s), ty_in(s, ups))

def enc_prim.of(+m: Maybe<&2, Ty>, +s: String) -> String:
  match m:
    case Some{value}: ty_bend(value)
    case None{}: s

def enc_prim(+s: String) -> String: enc_prim.of(enc_prim.find(ty_prims(), s), s)

# `String.drop(s, n)` drops n LEADING chars and base.bend has NO `drop_end`, so
# the trailing characters come off by keeping a prefix.  Dropping them from the
# FRONT instead costs ten characters of `c.POINTER[` and yields
# `Ptr_types.c_char]` -- a name that still typechecks, so nothing complains.
def enc_strip.go(+d: String, suf: Nat) -> String:
  String.take(d, Nat.sub(String.length(d), suf))

def enc_strip(+s: String, pre: Nat, suf: Nat) -> String:
  enc_strip.go(String.drop(s, pre), suf)

def enc_bracketed(+s: String) -> Bool: Bool.and(String.starts_with(s, "["), String.ends_with(s, "]"))

# the `[...]` around a CFUNCTYPE's argument list carries no name of its own, so
# it is stripped here rather than in the splitter
def enc_arg(+s: String) -> String: Bool.pick(String, enc_bracketed(s), enc_strip(s, 1n, 1n), s)

# base.bend:2061 already has `String.trim`, so there is nothing to write here.
# What IS worth recording is that the obvious two-def split --
# `def go(s, space) = Bool.pick(String, space, go(drop(s,1n)), s)` -- is refused as
# MUTUAL recursion with the `trim` wrapper, because `go` and `trim` are two names
# and bend allows only SELF recursion.
def enc_trim(+s: String) -> String: String.trim(s)

def enc_fn_parts.put(+s: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(s), acc, List.append(&2, String, acc, [s]))

# NO `List.reverse` at the end: the accumulator is appended to in SPLIT order,
# which is already the order autogen.py:119 writes -- result type, then the
# arguments -- and reversing it turned `c.CFUNCTYPE[None, [ctypes.c_void_p]]` into
# `Fn__CVoidP_Unit`.
def enc_fn_parts.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> rest: enc_fn_parts.go(rest, enc_fn_parts.put(enc_trim(h), acc))

# the RESULT type then the ARGUMENT types of a `c.CFUNCTYPE[...]`, brackets off
def enc_fn_parts(+s: String) -> List<&2, String>:
  enc_fn_parts.go(String.split(enc_trim(enc_strip(s, 12n, 1n)), ','), Nil{})

# ===========================================================================
# SECTION 2 -- `enc0`/`enc1`/`enc2`: THE DEPTH BOUND IS MEASURED, AND IT IS WHY
# THIS IS A CHAIN AND NOT A WALK.
#
# Over ALL 1156 type nodes in `libclang.py` -- every annotation, every
# `register_fields` cell, not only the 324 trampolines' -- the deepest compound
# spelling is `c.POINTER[c.POINTER[CXIdxAttrInfo]]`, depth TWO, and no
# `c.CFUNCTYPE` argument is itself a `c.CFUNCTYPE`.  So `enc2` handles depth 2,
# `enc1` depth 1 and `enc0` a bare leaf, and `enc2` is the entry.  The verifier
# RE-MEASURES that bound, so a depth-3 spelling arriving later turns the gate red
# rather than silently truncating.
#
# WHY NOT A SELF-RECURSIVE WALK.  bend accepts a self-call only when each argument
# is passed UNCHANGED until one shrinks, so a walk over a queue it must also GROW
# is refused: `go(pop(qt, q), xs, ...)` reports "expected a decreasing self-call"
# because `pop(qt, q)` is neither `pend` nor visibly smaller, even though `qt`
# is.  Two lists do not help -- `go(xs, pop(qt, q), acc)` is refused the same
# way.  Four shapes were probed; only the CHAIN compiles.
#
# `_` separates segments and is NOT emitted straight after a segment that already
# ends in one.  That is what makes `Ptr_` + `Ptr_` + `CXIdxAttrInfo` come out as
# `Ptr_Ptr_CXIdxAttrInfo` and not `Ptr__Ptr_CXIdxAttrInfo` -- a name that still
# typechecks, so a gate comparing only lengths would pass it.
# ===========================================================================

def enc0(+s: String) -> String: enc_prim(s)

def enc1.ptr(+s: String) -> String: String.concat(["Ptr_", enc0(enc_strip(s, 10n, 1n))])

# the accumulator is the name built so far; every part contributes a leading `_`,
# so the separator is never doubled, and the accumulator starts at `Fn`.
def enc1.fn.parts(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case p <> tail: enc1.fn.parts(tail, String.concat([acc, "_", enc0(enc_arg(p))]))

def enc1.fn(+s: String) -> String: enc1.fn.parts(enc_fn_parts(s), "Fn")

def enc1(+s: String) -> String:
  Bool.pick(String, String.starts_with(s, "c.POINTER["), enc1.ptr(s),
    Bool.pick(String, String.starts_with(s, "c.CFUNCTYPE["), enc1.fn(s), enc0(s)))

def enc2.ptr(+s: String) -> String: String.concat(["Ptr_", enc1(enc_strip(s, 10n, 1n))])

def enc2.fn.parts(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case p <> tail: enc2.fn.parts(tail, String.concat([acc, "_", enc1(enc_arg(p))]))

def enc2.fn(+s: String) -> String: enc2.fn.parts(enc_fn_parts(s), "Fn")

def enc2(+s: String) -> String:
  Bool.pick(String, String.starts_with(s, "c.POINTER["), enc2.ptr(s),
    Bool.pick(String, String.starts_with(s, "c.CFUNCTYPE["), enc2.fn(s), enc1(s)))

# THE ENTRY.  Depth 2, measured over every type node in the header.
def enc(+s: String) -> String: enc2(s)

# ===========================================================================
# SECTION 3 -- one row to one `Trr`, then one `Trr` to one `Tr`.
#
# Two passes because a parameter is THREE cells and bend has no triple
# constructor to destructure with.  Pass one takes the three leading cells; pass
# two groups the rest in threes.  Neither pass threads an index, so neither can
# be off by one on a 0-arity row.
# ===========================================================================

def trr_nm(+t: Trr) -> String:
  match t:
    case Trr{nm, rb, rh, cells}: nm

def trr_rb(+t: Trr) -> String:
  match t:
    case Trr{nm, rb, rh, cells}: rb

def trr_rh(+t: Trr) -> String:
  match t:
    case Trr{nm, rb, rh, cells}: rh

def trr_cells(+t: Trr) -> List<&2, String>:
  match t:
    case Trr{nm, rb, rh, cells}: cells

def parse_row.h(+r1: List<&2, String>, +acc: Trr) -> Trr:
  match r1:
    case Nil{}: acc
    case rh <> r2: Trr{trr_nm(acc), trr_rb(acc), rh, r2}

def parse_row.b(+r0: List<&2, String>, +acc: Trr) -> Trr:
  match r0:
    case Nil{}: acc
    case rb <> r1: parse_row.h(r1, Trr{trr_nm(acc), rb, "", Nil{}})

def parse_row.at(+cs: List<&2, String>) -> Trr:
  match cs:
    case Nil{}: Trr{"", "", "", Nil{}}
    case n0 <> r0: parse_row.b(r0, Trr{n0, "", "", Nil{}})

def parse_row(+line: String) -> Trr: parse_row.at(String.split(line, '|'))

# ===========================================================================
# SECTION 4 -- grouping a row's cells into parameters.
#
# Grouping in THREES cannot be a nest of three mutually recursive defs: bend
# allows a def to call ITSELF and not another def, so `group` -> `group.b` ->
# `group.h` -> `group` is refused.  The stage therefore rides in the ACCUMULATOR
# (`Gs.st`: 0 waiting for a name, 1 for the ABI type, 2 for the annotation) and
# `group.go` is the single self-recursive def, over the shrinking cell list.
#
# The stage is a PARAMETER of `group.step.at` and `group.flush.at`, not a
# computed `g.st`, because a `match` may only scrutinise a parameter or a field.
# ===========================================================================

def pm(+n: String, +t: String, +h: String) -> Pm: Pm{n, t, h}

def pm_nm(+p: Pm) -> String:
  match p:
    case Pm{nm, ty, hint}: nm

def pm_ty(+p: Pm) -> String:
  match p:
    case Pm{nm, ty, hint}: ty

def pm_hint(+p: Pm) -> String:
  match p:
    case Pm{nm, ty, hint}: hint

def gs(st: Nat, nm: String, ty: String, hd: String, acc: List<&2, Pm>) -> Gs: Gs{st, nm, ty, hd, acc}

def gs_st(g: Gs) -> Nat:
  match g:
    case Gs{st, nm, ty, hd, acc}: st

def gs_nm(g: Gs) -> String:
  match g:
    case Gs{st, nm, ty, hd, acc}: nm

def gs_ty(g: Gs) -> String:
  match g:
    case Gs{st, nm, ty, hd, acc}: ty

def gs_hd(g: Gs) -> String:
  match g:
    case Gs{st, nm, ty, hd, acc}: hd

def gs_acc(g: Gs) -> List<&2, Pm>:
  match g:
    case Gs{st, nm, ty, hd, acc}: acc

def group.at(+g: Gs, st: Nat) -> Gs: gs(st, gs_nm(g), gs_ty(g), gs_hd(g), gs_acc(g))

# ONE cell in: stage 0 takes a NAME, stage 1 the ABI type, stage 2 the annotation
# AND closes the parameter.
def group.step.at(st: Nat, +g: Gs, +c: String) -> Gs:
  match st:
    case 0n: gs(1n, c, gs_ty(g), gs_hd(g), gs_acc(g))
    case 1n: gs(2n, gs_nm(g), c, gs_hd(g), gs_acc(g))
    case _s: gs(0n, gs_nm(g), gs_ty(g), c, List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), c)]))

# A truncated final triple still yields its parameter.  autogen.py:239 spells the
# fallback `'_' + str(i)`, and a row read from a truncated file is exactly the
# case where a silently dropped parameter would be invisible.
def group.flush.at(st: Nat, +g: Gs) -> List<&2, Pm>:
  match st:
    case 0n: gs_acc(g)
    case 1n: List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), "")])
    case _s: List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), gs_hd(g))])

def group.step(+g: Gs, +c: String) -> Gs: group.step.at(gs_st(g), g, c)

def group.flush(+g: Gs) -> List<&2, Pm>: group.flush.at(gs_st(g), g)

# THE CELL LIST COMES FIRST, THE STATE SECOND.  bend reads a self-call's arguments
# left to right and wants each passed UNCHANGED until one shrinks.  With the state
# first, the first argument is `group.step(g, c)` -- computed, and not shrinking --
# so the call is refused even though `rest` shrinks.
def group.go(+cs: List<&2, String>, +g: Gs) -> List<&2, Pm>:
  match cs:
    case Nil{}: group.flush(g)
    case c <> rest: group.go(rest, group.step(g, c))

def group(+cs: List<&2, String>) -> List<&2, Pm>: group.go(cs, gs(0n, "", "", "", Nil{}))

def tr_nm(+t: Tr) -> String:
  match t:
    case Tr{nm, rty, ret, ps}: nm

def tr_rty(+t: Tr) -> String:
  match t:
    case Tr{nm, rty, ret, ps}: rty

def tr_ret(+t: Tr) -> String:
  match t:
    case Tr{nm, rty, ret, ps}: ret

def tr_ps(+t: Tr) -> List<&2, Pm>:
  match t:
    case Tr{nm, rty, ret, ps}: ps

def to_tr(+t: Trr) -> Tr: Tr{trr_nm(t), trr_rb(t), trr_rh(t), group(trr_cells(t))}

# ===========================================================================
# SECTION 5 -- THE TEMPLATE.  autogen.py:240-241, in Bend.
#
# The emitted `def` carries the upstream signature in Bend types and answers
# `None{}`: THE REFUSAL IS IN THE TYPE.  `None` is deliberately not the null
# value of the ABI type -- a predicate returns `0`, and `0` is `False`, so a
# null-valued refusal would be indistinguishable from a real answer.
# ===========================================================================

def emit_param(+p: Pm) -> String: String.concat([pm_nm(p), ": ", enc(pm_ty(p))])

def emit_params(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, [emit_param(p)], emit_params(rest))

# the `@dll.bind(...)` payload of autogen.py:240, RECONSTRUCTED from the same row
# rather than stored beside it.  A template check has to catch a body that calls
# the WRONG GETTER AT THE RIGHT ARITY, and a stored second copy of the payload
# could not.
def emit_binds.go(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, [enc(pm_ty(p))], emit_binds.go(rest))

def emit_binds(+t: Tr) -> List<&2, String>:
  List.append(&2, String, [enc(tr_rty(t))], emit_binds.go(tr_ps(t)))

def emit_binds_up.go(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, [pm_hint(p)], emit_binds_up.go(rest))

def emit_binds_up(+t: Tr) -> List<&2, String>:
  List.append(&2, String, [tr_ret(t)], emit_binds_up.go(tr_ps(t)))

def emit_def(+t: Tr) -> String:
  String.concat(["def ", tr_nm(t), "(", String.join(emit_params(tr_ps(t)), ", "),
                 ") -> Maybe<&2, ", enc(tr_rty(t)), ">:\n  None{}\n"])

def emit_bind(+t: Tr) -> String: String.concat([tr_nm(t), " = ", String.join(emit_binds(t), ", ")])

def emit_bind_up(+t: Tr) -> String: String.concat([tr_nm(t), " = ", String.join(emit_binds_up(t), ", ")])

# ===========================================================================
# SECTION 6 -- the type-row fold.
# ===========================================================================

def pb(+b: String, +u: String) -> Pb: Pb{b, u}

def pb_bend(+p: Pb) -> String:
  match p:
    case Pb{bend, up}: bend

def pb_up(+p: Pb) -> String:
  match p:
    case Pb{bend, up}: up

# THREE THINGS THIS GETS WRONG IF IT IS WRITTEN NAIVELY, all measured here:
#   * the replaced row must be PREPENDED TO THE TAIL, not returned alone --
#     returning the one-element list drops every row behind it, and the symptom
#     is a type table of FIVE rows where libclang.py's 76 spellings want
#     seventy-odd.  A table that is too SHORT reads as tidy, not wrong;
#   * when the HEAD matches, the tail must be left ALONE, so the recursion is
#     handed the ORIGINAL rest as well as the rebuilt one and the match uses the
#     original -- threading `up` through the whole tail adds a SECOND row for the
#     same type and the table grew to 852 rows;
#   * the untouched rest and the rebuilt tail are two PARAMETERS, because
#     `Bool.pick` evaluates both arms and the condition cannot be held in a
#     `let`.  `ty_add.at` is therefore non-recursive and `ty_add.put` is the
#     single self-recursive def.
def ty_add.at(hit: Bool, +cur: Ty, +rest: List<&2, Ty>, +tail: List<&2, Ty>, +up: String) -> List<&2, Ty>:
  Bool.pick(List<&2, Ty>, hit,
            List.append(&2, Ty, [Ty{ty_bend(cur), String.concat([ty_ups(cur), ",", up])}], rest),
            List.append(&2, Ty, [cur], tail))

def ty_add.put(+xs: List<&2, Ty>, +b: String, +up: String) -> List<&2, Ty>:
  match xs:
    case Nil{}: [Ty{b, up}]
    case Ty{bend, ups} <> rest: ty_add.at(String.eq(bend, b), Ty{bend, ups}, rest, ty_add.put(rest, b, up), up)

def ty_add(+xs: List<&2, Ty>, +b: String, +up: String) -> List<&2, Ty>: ty_add.put(xs, b, up)

# Every ABI type a row mentions, the return first then each parameter -- the order
# autogen.py:240 builds `[rt] + ats` in -- each as a (BEND NAME, UPSTREAM
# SPELLING) PAIR, because the type row is keyed on the Bend name and its `ups`
# column is the upstream spelling SET.
# TWO PAIRS PER TYPE: the ctypes spelling AND the `typehint` annotation, because
# `Ty.ups` is the SET of upstream spellings that resolve to a Bend name and `int`
# is one of them (autogen.py:108-109).  With only the ctypes spelling the emitted
# table has no `int` anywhere and 169 return rows have no spelling their
# annotation can be checked against.
# TWO PAIRS PER TYPE: the ctypes spelling AND the `typehint` annotation, because
# `Ty.ups` is the SET of upstream spellings that resolve to a Bend name and `int`
# is one of them (autogen.py:108-109).  With only the ctypes spelling the emitted
# table has no `int` anywhere and 169 return rows have no spelling their
# annotation can be checked against.
def tr_binds.go(+xs: List<&2, Pm>, +rb: String, +rh: String) -> List<&2, Pb>:
  match xs:
    case Nil{}: List.append(&2, Pb, [pb(enc(rb), rb)], [pb(enc(rh), rh)])
    case p <> rest:
      List.append(&2, Pb,
                  List.append(&2, Pb, [pb(enc(pm_ty(p)), pm_ty(p))], [pb(enc(pm_hint(p)), pm_hint(p))]),
                  tr_binds.go(rest, pm_ty(p), pm_hint(p)))


def tr_bends(+t: Tr) -> List<&2, Pb>: tr_binds.go(tr_ps(t), tr_rty(t), tr_ret(t))
def tys_go(+xs: List<&2, Pb>, +acc: List<&2, Ty>) -> List<&2, Ty>:
  match xs:
    case Nil{}: acc
    case p <> rest: tys_go(rest, ty_add(acc, pb_bend(p), pb_up(p)))

# `tys_sort(rest)` FIRST, then insert the head.  Inserting the head into the
# UNSORTED tail -- `tys_sort.ins(rest, h)` -- is not insertion sort: it returns as
# soon as one element happens to compare less, so `[c,a,e,b,d,f]` came out as
# `[a,c,e,b,d,f]`.  Over libclang.py's seventy-odd type names that left five rows
# in the emitted table.
def tys_sort.ins(+xs: List<&2, Ty>, +t: Ty) -> List<&2, Ty>:
  match xs:
    case Nil{}: [t]
    case h <> rest:
      Bool.pick(List<&2, Ty>, ty_le(t, h),
                List.append(&2, Ty, [t], xs),
                List.append(&2, Ty, [h], tys_sort.ins(rest, t)))

def tys_sort(+xs: List<&2, Ty>) -> List<&2, Ty>:
  match xs:
    case Nil{}: Nil{}
    case h <> rest: tys_sort.ins(tys_sort(rest), h)

def trs_fold(+xs: List<&2, Tr>, +acc: List<&2, Ty>) -> List<&2, Ty>:
  match xs:
    case Nil{}: tys_sort(acc)
    case t <> rest: trs_fold(rest, tys_go(tr_bends(t), acc))

# NO BLANK-LINE GUARD HERE, and that is deliberate.  `String.lines` KEEPS the
# empty string after a file's final newline, so a 324-row file yields 325 rows and
# the extra one parses to an empty NAME -- emitting it produced `type  is Data:`
# and `def ty_()`, and both typecheck.  The two fixes are a guard or a trim, and
# the GUARD costs 2^N: `Bool.pick` evaluates both arms, so
# `Bool.pick(..., is_empty(l), trs_map(rest), ... trs_map(rest))` walks the tail
# TWICE per row and 21 rows outlasted the session.  Routing the guard through a
# second def is refused -- `trs_map.at` and `trs_map` are two names and bend
# allows only SELF recursion -- so the caller trims instead.
def trs_map(+xs: List<&2, String>) -> List<&2, Tr>:
  match xs:
    case Nil{}: Nil{}
    case l <> rest: List.append(&2, Tr, [to_tr(parse_row(l))], trs_map(rest))

# ===========================================================================
# SECTION 7 -- THE EMITTED TEXT.
# ===========================================================================

def emit_ty(+t: Ty) -> String: String.concat(["type ", ty_bend(t), " is Data:\n  ", ty_bend(t), "{}\n"])

def emit_ty_row(+t: Ty) -> String:
  String.concat(["def ty_", ty_bend(t), "() -> Ty: Ty{\"", ty_bend(t), "\", \"", ty_ups(t), "\"}\n"])

def emit_head(+nt: Nat, +ntr: Nat) -> String: String.concat([
"# GENERATED FILE -- DO NOT EDIT.  Emitted by `.agents/slop/ag-emit.bend` from\n",
"# `tinygrad/runtime/autogen/libclang.py` via `.agents/slop/ag-libclang.tramp`.\n",
"# Regenerate:\n",
"#   ./bin/bend .agents/slop/ag-emit.bend -o .agents/slop/ag-emit.bin\n",
"#   .agents/slop/ag-emit.bin > tinybendygrad/runtime/autogen/libclang.bend\n",
"#\n",
"# Port of `tinygrad/runtime/autogen/libclang.py`: the ", Nat.show(ntr), " `@dll.bind`\n",
"# trampolines `tinygrad/runtime/support/autogen.py:240-241` emits, over ",
  Nat.show(nt), " distinct ABI\n",
"# types, driven from the ENUMERATED LIST rather than from a live libclang AST.\n",
"# One template, applied ", Nat.show(ntr), " times.\n",
"#\n",
"# COVERAGE, NOT FUNCTION.  No def below executes a libclang call.  Every body\n",
"# is `None{}` and the refusal is in the TYPE, so a caller cannot read a refused\n",
"# call as a returned value.  bend has no per-function FFI: its only form is a\n",
"# whole-operation effect -- a `def` returning IO plus an `import` of a C file --\n",
"# which for this header would mean ", Nat.show(ntr), " C files and ", Nat.show(ntr), " hand-written shims.\n",
"# See `tinybendygrad/runtime/support/autogen.bend` WALL 1.\n",
"#\n",
"# NOT COVERED, and not claimed: the 41 struct RECORDS and their 130 fields --\n",
"# field ORDER, OFFSETS and bitfield slices; the 47 enum dicts and their 845\n",
"# constants; the 32 `TypeAlias` lines.  What is checked here is the FUNCTION\n",
"# TRAMPOLINE template and nothing else.  A name-and-arity check cannot see a\n",
"# wrong field offset.\n",
"import Base\n\n"])

def emit_tail() -> String: String.concat([
"\n",
"# ===========================================================================\n",
"# THE GATE.  A def nothing calls is invisible to every other check, so the\n",
"# count and the reconstructed ABI payload are printed here and diffed by\n",
"# `.agents/slop/ag-tramp-verify.py` against libclang.py read by CPython.\n",
"# ===========================================================================\n",
"\n",
"def tramp_count() -> Nat: List.length(&2, Ty, tramp_rows())\n",
"\n",
"def main() -> IO(Unit):\n",
"  do IO<Unit>:\n",
"    IO.print(\"tramps \" ++ Nat.show(tramp_count()))\n",
"    IO.print(\"types \" ++ Nat.show(List.length(&2, Ty, ty_rows())))\n",
"    IO.print(\"bind \" ++ bind(clang_createIndex))\n",
"    IO.print(\"bindu \" ++ bindu(clang_createIndex))\n",
"    IO.print(\"arity \" ++ Nat.show(arity(clang_getFileContents)))\n",
"    IO.print(\"arity0 \" ++ Nat.show(arity(clang_getTranslationUnitCursor)))\n"])

# ===========================================================================
# SECTION 8 -- the IO walks.
#
# `IO.bind(A, B, m, f)` types `f` as `A -> IO(B)` where `A` is the type `m`
# PRODUCES, and both arguments are `Type`, never `Quant`.  `IO.bind(&2, Ty, Unit,
# ...)` is wrong twice over, and the `&2` reports itself as
# `expected : Type / observed : Quant` on the LIST PARAMETER -- a message naming
# the argument three defs away from the mistake.
# ===========================================================================

# The tuple destructuring cannot sit inside a `do` block -- it is a binding, not a
# bind -- so the close is a second def, which is `sz.bend`'s `sz.closed` too.
# `File` is a `law`, hence a Type and not Data, so this parameter CANNOT be `+`.
def read_lines.go(m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (ff, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(ff)
    IO.pure(String, s)

# The `m : ... <- File.read(f, ...)` bind is what makes this work: an EFFECTFUL
# call cannot be an ARGUMENT (`expected : File & Result<..> / observed : IO(..)`),
# and `f` is needed twice -- once to read, once to close -- which the pair `m`
# carries.  This is `sz.bend`'s `sz.read`/`sz.closed` split exactly.
def read_lines(path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1073741824)
    read_lines.go(m)

def emit_tys(+xs: List<&2, Ty>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(Unit, Unit, IO.print(emit_ty(t)),
        _ => IO.bind(Unit, Unit, IO.print(emit_ty_row(t)), _ => emit_tys(rest)))

def emit_defs(+xs: List<&2, Tr>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(Unit, Unit, IO.print(emit_def(t)), _ => emit_defs(rest))

# The `do` block binds `raw` but NOT `trs` or `tys`: a `do`-block binder takes a
# `Type`, and `List<&2, Tr>` is not one -- it reports `expected : Type / observed
# : Quant`, naming the quantifier rather than the binder.  `String` is fine
# (`sz.bend` binds `f : File` the same way), so only the String is bound.







def main.ty(+trs: List<&2, Tr>, +tys: List<&2, Ty>) -> IO(Unit):
  IO.bind(Unit, Unit,
          IO.print(emit_head(List.length(&2, Ty, tys), List.length(&2, Tr, trs))),
    _ => IO.bind(Unit, Unit, emit_tys(tys), _ => emit_defs(trs)))

def main.rows(+trs: List<&2, Tr>) -> IO(Unit): main.ty(trs, trs_fold(trs, Nil{}))

def main.go(+lines: List<&2, String>) -> IO(Unit): main.rows(trs_map(lines))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : String <- read_lines(".agents/slop/ag-libclang.tramp")
    main.go(String.lines(String.trim(raw)))
