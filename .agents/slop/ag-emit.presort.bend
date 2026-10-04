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
# ORDERED parameter names, each parameter's ABI type, and the return type. All
# four are already enumerated, as data, in `tinygrad/runtime/autogen/
# libclang.py`, which is the generator's own committed output for this header.
# So the FFI that autogen.py needs in order to walk an AST is replaced by
# reading the list. WALL 1 blocks deriving a list; it does not block reading one.
#
# INPUT   .agents/slop/ag-libclang.tramp   one row per `@dll.bind` def:
#            name|retbind|rethint|[pname|pbind|phint]*
#         produced by `.agents/slop/ag-libclang-rows.py`, the ONE reader of
#         libclang.py.  `|` is the separator because no ctypes spelling and no
#         Python annotation in libclang.py contains one, and because
#         `String.split` in bend takes a single Char.
# OUTPUT  tinybendygrad/runtime/autogen/libclang.bend
#         ./bin/bend .agents/slop/ag-emit.bend > tinybendygrad/runtime/autogen/libclang.bend
#
# FIVE MEASURED bend 2.0.35 CONSTRAINTS shape every def below. All of them are
# quoted at `.agents/slop/notes/bend2-constraints.md`.
#
#   1. DECLARATION ORDER IS LOAD-BEARING.  A def must PRECEDE every def it uses,
#      and mutual recursion is refused outright:
#        expected : a filled definition (an unfilled law is a dead claim)
#      This file is therefore emitted in topological order, and
#      `.agents/slop/ag-order.py` checks the order rather than trusting it.
#   2. A def may call ITSELF and nothing else.  Every recursion here is
#      self-recursion over a STRUCTURALLY SHRINKING argument, which is the only
#      shape bend accepts.
#   3. A `match` may only scrutinise a PARAMETER or a FIELD, never a computed
#      value, so a computed discriminator is bound by the caller.
#   4. A PARAMETER IS LINEAR unless it is marked `+`.  `String` and `List`
#      parameters that are read twice carry `+`; without it the file is refused
#      with "consumed more than once", and the name it names is not always the
#      one you would guess -- a parameter sharing a name with a record FIELD
#      (`ups`) reports the field's name, not the parameter's.
#   5. `List.map`, `List.filter`, `List.sort` and `List.foldl` all take a closure,
#      and a closure type cannot spell `+`.  Nothing here reflects over a list.
# ===========================================================================
import Base

# ===========================================================================
# SECTION 1 -- THE TYPE TABLE.  One row per Bend type name, carrying every
# upstream spelling that resolves to it.
#
# The mapping is MANY-TO-ONE, and that is not an accident: `typehint` and `tmap`
# deliberately disagree about the same value. autogen.py:108-109 spells
# `CXType_Int` as the annotation `int`; autogen.py:94-95 spells it as the ctypes
# ABI type `ctypes.c_int32`. One Bend name, two upstream spellings -- so the
# row holds a spelling SET. One row per spelling would collide on `I32`; one
# row per Bend name without the set would drop the annotation the verifier has
# to check.
#
# `U32` is the ONE real Bend type in the table (base.bend:57, a 32-bit word,
# which is exactly `ctypes.c_uint32`). Every other row is an EMPTY Data named
# for the C width it stands for, because bend 2.0.35 declares only `U32` and
# `F32` -- no signed integer, no 64-bit integer, no F64 -- and an empty value
# is the only honest thing a REFUSED trampoline can return.
# ===========================================================================

type Ty is Data: Ty{bend: String, ups: String}

type Pm is Data: Pm{nm: String, ty: String, hint: String}

type Trr is Data: Trr{nm: String, rb: String, rh: String, cells: List<&2, String>}

type Tr is Data: Tr{nm: String, rty: String, ret: String, ps: List<&2, Pm>}

# autogen.py:239 groups each parameter's three facts -- NAME, ABI type, the
# `typehint` annotation -- and a group needs a state because those three arrive
# in a flat cell list. The state is a RECORD, so a walk can carry it through
# several defs; a `Nat` parameter cannot, because an up-counter threaded as a
# parameter is exactly the descent bend refuses.
type Gs is Data: Gs{st: Nat, nm: String, ty: String, hd: String, acc: List<&2, Pm>}

def ty(+b: String, +u: String) -> Ty: Ty{b, u}

def ty_bend(+t: Ty) -> String:
  match t:
    case Ty{bend, ups}: bend

def ty_ups(+t: Ty) -> String:
  match t:
    case Ty{bend, ups}: ups

def ty_le(+x: Ty, +y: Ty) -> Bool: String.is_le(ty_bend(x), ty_bend(y))

# autogen.py:91 tmap and :108 typehint, resolved to Bend names. Every entry is a
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

def ty_all_ups.go(+xs: List<&2, Ty>) -> String:
  match xs:
    case Nil{}: ""
    case Ty{bend, ups} <> rest: String.concat([ups, "|", ty_all_ups.go(rest)])

def ty_all_ups() -> String: String.concat(["|", ty_all_ups.go(ty_prims()), "|"])

# membership over a COMMA-joined spelling set. Substring search would be wrong:
# `c.POINTER[CXString]` contains `CXString`, and an empty set contains
# everything.
def ty_in(+s: String, +set: String) -> Bool:
  Bool.or(String.eq(s, set), String.contains(String.concat([",", set, ","]), String.concat([",", s, ","])))

# ===========================================================================
# SECTION 2 -- `enc`, the ctypes spelling -> Bend name function.
#
# Three arms and a table, and the identity arm is the identity because every
# remaining spelling in libclang.py is already a valid Bend identifier
# (`CXCursor`, `size_t`, `struct_CXUnsavedFile`, `IndexerCallbacks`).
#
# THE BRACKET SPLIT IS MEASURED, NOT A HOPE. `c.CFUNCTYPE[None,
# [ctypes.c_void_p]]` wants a bracket-aware top-level comma split, and a
# bracket-aware scan is a descent with an accumulator -- the shape WALL 4
# refuses elsewhere in this port. Splitting on `,` and dropping the empties is
# equivalent HERE for a checkable reason: a CFUNCTYPE argument is a ctypes
# spelling, and the only ctypes spellings that contain a comma are CFUNCTYPE
# spellings, which do not nest in this header. What turns that argument into a
# CHECKED claim is that the emitted `ty_Fn_*` rows are compared by the verifier
# against the CFUNCTYPE spellings read out of libclang.py.
# ===========================================================================

# `String.drop(s, n)` drops n LEADING chars.
def enc_strip(+s: String, pre: Nat, suf: Nat) -> String: String.drop(String.drop(s, pre), suf)

def enc_bracketed(+s: String) -> Bool: Bool.and(String.starts_with(s, "["), String.ends_with(s, "]"))

def enc_arg(+s: String) -> String: Bool.pick(String, enc_bracketed(s), enc_strip(s, 1n, 1n), s)

# base.bend:2061 already has `String.trim`, so there is nothing to write here.
# What IS worth recording is that the obvious two-def split --
# `def go(s, space) = Bool.pick(String, space, go(drop(s,1n)), s)` -- is refused
# as MUTUAL recursion with the `trim` wrapper, because `go` and `trim` are two
# names and bend allows only SELF recursion.
def enc_trim(+s: String) -> String: String.trim(s)

def enc_fn_parts.put(+s: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(s), acc, List.append(&2, String, acc, [s]))

# segments are joined with `_`, but not after a prefix that already ends in one,
# and not at the very start. That is `enc_sep`, and getting it wrong turns
# `Fn_None_Ptr_void_p` into `Fn__None__Ptr...` -- a NAME that still typechecks,
# so a gate comparing only lengths would pass it.
def enc_sep(+acc: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(acc), String.ends_with(acc, "_")), "", "_")

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

def enc_prim.find(+xs: List<&2, Ty>, +s: String) -> Maybe<&2, Ty>:
  match xs:
    case Nil{}: None{}
    case Ty{bend, ups} <> rest: List.find.put(Ty, Ty{bend, ups}, enc_prim.find(rest, s), ty_in(s, ups))

def enc_prim.of(+m: Maybe<&2, Ty>, +s: String) -> String:
  match m:
    case Some{value}: ty_bend(value)
    case None{}: s

def enc_prim(+s: String) -> String: enc_prim.of(enc_prim.find(ty_prims(), s), s)

def enc_fn_parts.go(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> rest: enc_fn_parts.go(rest, enc_fn_parts.put(enc_trim(h), acc))

# the RESULT type then the ARGUMENT types of a `c.CFUNCTYPE[... ]`, brackets off
def enc_fn_parts(+s: String) -> List<&2, String>:
  enc_fn_parts.go(String.split(enc_trim(enc_strip(s, 12n, 1n)), ','), Nil{})

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

def parse_row.at(+cs: List<&2, String>) -> Trr:
  match cs:
    case Nil{}: Trr{"", "", "", Nil{}}
    case n0 <> r0: parse_row.b(r0, Trr{n0, "", "", Nil{}})

def parse_row.b(+r0: List<&2, String>, +acc: Trr) -> Trr:
  match r0:
    case Nil{}: acc
    case rb <> r1: parse_row.h(r1, Trr{trr_nm(acc), rb, "", Nil{}})

def parse_row.h(+r1: List<&2, String>, +acc: Trr) -> Trr:
  match r1:
    case Nil{}: acc
    case rh <> r2: Trr{trr_nm(acc), trr_rb(acc), rh, r2}

def parse_row(+line: String) -> Trr: parse_row.at(String.split(line, '|'))

# ===========================================================================
# SECTION 3 -- grouping a row's cells into parameters, then `enc` on top.
#
# Grouping in THREES cannot be a nest of three mutually recursive defs: bend
# allows a def to call ITSELF and not another def, so `group` -> `group.b` ->
# `group.h` -> `group` is refused as mutual recursion. The stage therefore rides
# in the ACCUMULATOR (`Gs.st`: 0 waiting for a name, 1 for the ABI type, 2 for
# the annotation) and `group.go` is the single self-recursive def, over the
# shrinking cell list.
#
# The stage is a PARAMETER of `group.step.at` and `group.flush.at`, not a
# computed `g.st`, because a `match` may only scrutinise a parameter or a field.
# ===========================================================================

def group.at(g: Gs, st: Nat) -> Gs: gs(st, gs_nm(g), gs_ty(g), gs_hd(g), gs_acc(g))

# ONE cell in: stage 0 takes a NAME, stage 1 the ABI type, stage 2 the
# annotation AND closes the parameter.
def group.step.at(st: Nat, +g: Gs, +c: String) -> Gs:
  match st:
    case 0n: gs(1n, c, gs_ty(g), gs_hd(g), gs_acc(g))
    case 1n: gs(2n, gs_nm(g), c, gs_hd(g), gs_acc(g))
    case _s: gs(0n, gs_nm(g), gs_ty(g), c, List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), c)]))

# A truncated final triple still yields its parameter. autogen.py:239 spells the
# fallback `'_' + str(i)`, and a row read from a truncated file is exactly the
# case where a silently dropped parameter would be invisible.
def group.flush.at(st: Nat, +g: Gs) -> List<&2, Pm>:
  match st:
    case 0n: gs_acc(g)
    case 1n: List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), "")])
    case _s: List.append(&2, Pm, gs_acc(g), [pm(gs_nm(g), gs_ty(g), gs_hd(g))])

def group.step(+g: Gs, +c: String) -> Gs: group.step.at(gs_st(g), g, c)

def group.flush(+g: Gs) -> List<&2, Pm>: group.flush.at(gs_st(g), g)

def group.go(+g: Gs, +cs: List<&2, String>) -> List<&2, Pm>:
  match cs:
    case Nil{}: group.flush(g)
    case c <> rest: group.go(group.step(g, c), rest)

def group(+cs: List<&2, String>) -> List<&2, Pm>: group.go(gs(0n, "", "", "", Nil{}), cs)

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

def to_tr(+t: Trr) -> Tr: Tr{trr_nm(t), enc(trr_rb(t)), enc(trr_rh(t)), group(trr_cells(t))}

# ===========================================================================
# SECTION 4 -- THE TEMPLATE. autogen.py:240-241, in Bend.
#
# The emitted `def` carries the upstream signature in Bend types and answers
# `None{}`: THE REFUSAL IS IN THE TYPE. `None` is deliberately not the null
# value of the ABI type -- a predicate returns `0`, and `0` is `False`, so a
# null-valued refusal would be indistinguishable from a real answer.
# ===========================================================================

def emit_param(+p: Pm) -> String: String.concat([pm_nm(p), ": ", pm_ty(p)])

def emit_params(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, emit_params(rest), [emit_param(p)])

# the `@dll.bind(...)` payload of autogen.py:240, RECONSTRUCTED from the same
# row rather than stored beside it. A template check has to be able to catch a
# body that calls the WRONG GETTER AT THE RIGHT ARITY, and a stored second copy
# of the payload could not.
def emit_binds.go(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, emit_binds.go(rest), [pm_ty(p)])

def emit_binds(+t: Tr) -> List<&2, String>:
  List.append(&2, String, emit_binds.go(tr_ps(t)), [tr_rty(t)])

def emit_binds_up.go(+xs: List<&2, Pm>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case p <> rest: List.append(&2, String, emit_binds_up.go(rest), [pm_hint(p)])

def emit_binds_up(+t: Tr) -> List<&2, String>:
  List.append(&2, String, emit_binds_up.go(tr_ps(t)), [tr_ret(t)])

def emit_def(+t: Tr) -> String:
  String.concat(["def ", tr_nm(t), "(", String.join(emit_params(tr_ps(t)), ", "),
                 ") -> Maybe<&2, ", tr_rty(t), ">:\n  None{}\n"])

def emit_bind(+t: Tr) -> String: String.concat([tr_nm(t), " = ", String.join(emit_binds(t), ", ")])

def emit_bind_up(+t: Tr) -> String: String.concat([tr_nm(t), " = ", String.join(emit_binds_up(t), ", ")])

# ===========================================================================
# SECTION 5 -- `enc_go`, THE TYPE-NAME WALK, and the type-row fold.
# ===========================================================================

def ty_find(+xs: List<&2, Ty>, +b: String) -> Maybe<&2, Ty>:
  match xs:
    case Nil{}: None{}
    case Ty{bend, ups} <> rest: List.find.put(Ty, Ty{bend, ups}, ty_find(rest, b), String.eq(bend, b))

def ty_add.put(+found: Maybe<&2, Ty>, +acc: List<&2, Ty>, b: String) -> List<&2, Ty>:
  match found:
    case Some{value}: List.append(&2, Ty, acc, [Ty{b, String.concat([ty_ups(value), ",", b])}])
    case None{}: List.append(&2, Ty, acc, [Ty{b, b}])

def ty_add(+xs: List<&2, Ty>, +b: String) -> List<&2, Ty>: ty_add.put(ty_find(xs, b), xs, b)

# `c.CFUNCTYPE[None, [ctypes.c_void_p]]` puts the RESULT type first and the
# ARGUMENT types in a bracketed list, so `enc_fn_parts` returns
# `[None, ctypes.c_void_p]` and this walks it onto the FRONT of the queue in
# order. `List.append(&2, String, [x], rest)` PREPENDS, which is what the queue
# wants and is the opposite of what a reader expects from an append.
def enc_push.fn(+parts: List<&2, String>, +rest: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}: rest
    case h <> tail: enc_push.fn(tail, List.append(&2, String, [enc_arg(h)], rest))

# `Bool.pick` CHOOSES an arm and EVALUATES BOTH, so `enc_fn_parts` runs on a
# POINTER spelling too and its result is discarded. That is safe here because
# both arms are total -- no parse, no failure, no effect -- and it is the reason
# this is two lines rather than a `match` on a computed Bool.
def enc_push(+h: String, +rest: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.starts_with(h, "c.POINTER["),
            List.append(&2, String, [enc_strip(h, 10n, 1n)], rest),
            Bool.pick(List<&2, String>, String.starts_with(h, "c.CFUNCTYPE["),
                      enc_push.fn(enc_fn_parts(h), rest),
                      rest))

# The segment a spelling contributes: a PREFIX for the two compound forms, and
# the resolved name for everything else. A prefix is a complete segment because
# `enc_sep` suppresses the `_` after a string ending in `_`, which is what makes
# `Ptr_` + `Ptr_` + `CChar` come out as `Ptr_Ptr_CChar` and not `Ptr_CChar`.
def enc_seg(+h: String) -> String:
  Bool.pick(String, String.starts_with(h, "c.POINTER["), "Ptr_",
    Bool.pick(String, String.starts_with(h, "c.CFUNCTYPE["), "Fn_", enc_prim(h)))

def enc_cat(+h: String, +acc: String) -> String: String.concat([acc, enc_sep(acc), enc_seg(h)])

def enc_go(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> rest: enc_go(enc_push(h, rest), enc_cat(h, acc))

def enc(+s: String) -> String: enc_go([s], "")

# every ABI type a row mentions, the return first, then each parameter -- the
# order autogen.py:240 builds `[rt] + ats` in.
def tr_bends(+t: Tr) -> List<&2, String>:
  List.append(&2, String, emit_binds.go(tr_ps(t)), [tr_rty(t)])

def tys_go(+xs: List<&2, String>, +acc: List<&2, Ty>) -> List<&2, Ty>:
  match xs:
    case Nil{}: acc
    case b <> rest: tys_go(rest, ty_add(acc, b))

# insertion sort on the Bend name. `List.sort` needs a closure, and a closure
# type cannot spell `+`.
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
    case h <> rest: tys_sort.ins(rest, h)

# ===========================================================================
# SECTION 6 -- THE EMITTED TEXT.
# ===========================================================================

def emit_head(+nt: Nat, +ntr: Nat) -> String: String.concat([
"# GENERATED FILE -- DO NOT EDIT.  Emitted by `.agents/slop/ag-emit.bend` from\n",
"# `tinygrad/runtime/autogen/libclang.py` via `.agents/slop/ag-libclang.tramp`.\n",
"# Regenerate:\n",
"#   ./bin/bend .agents/slop/ag-emit.bend > tinybendygrad/runtime/autogen/libclang.bend\n",
"#\n",
"# Port of `tinygrad/runtime/autogen/libclang.py`: the ", U32.show(ntr), " `@dll.bind`\n",
"# trampolines `tinygrad/runtime/support/autogen.py:240-241` emits, over ",
  U32.show(nt), " distinct ABI\n",
"# types, driven from the ENUMERATED LIST rather than from a live libclang AST.\n",
"# One template, applied ", U32.show(ntr), " times.\n",
"#\n",
"# COVERAGE, NOT FUNCTION.  No def below executes a libclang call.  Every body\n",
"# is `None{}` and the refusal is in the TYPE, so a caller cannot read a refused\n",
"# call as a returned value.  bend has no per-function FFI: its only form is a\n",
"# whole-operation effect -- a `def` returning IO plus an `import` of a C file --\n",
"# which for this header would mean ", U32.show(ntr), " C files and ", U32.show(ntr), " hand-written shims.\n",
"# See `tinybendygrad/runtime/support/autogen.bend` WALL 1.\n",
"#\n",
"# NOT COVERED, and not claimed: the 41 struct RECORDS and their 130 fields --\n",
"# field ORDER, OFFSETS and bitfield slices; the 47 enum dicts and their 845\n",
"# constants; the 32 `TypeAlias` lines.  What is checked here is the FUNCTION\n",
"# TRAMPOLINE template and nothing else.  A name-and-arity check cannot see a\n",
"# wrong field offset.\n",
"import Base\n\n"])

def emit_ty(+t: Ty) -> String: String.concat(["type ", ty_bend(t), " is Data:\n  ", ty_bend(t), "{}\n"])

def emit_ty_row(+t: Ty) -> String:
  String.concat(["def ty_", ty_bend(t), "() -> Ty: Ty{\"", ty_bend(t), "\", \"", ty_ups(t), "\"}\n"])

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
# SECTION 7 -- the walks.
# ===========================================================================

# the tuple destructuring cannot sit inside a `do` block -- it is a binding, not
# a bind -- so the close is a second def, which is `sz.bend`'s `sz.closed` too.
def read_lines.go(+m: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (ff, r) = m
  do IO<String>:
    s : String <- IO.pass(String, r)
    u : Unit <- File.close(ff)
    IO.pure(String, s)

def read_lines(+path: String) -> IO(String):
  do IO<String>:
    f : File <- IO.try(File, File.open(path, "r"))
    read_lines.go(File.read(f, 4294967295))

def trs_map(+xs: List<&2, String>) -> List<&2, Tr>:
  match xs:
    case Nil{}: Nil{}
    case l <> rest: List.append(&2, Tr, trs_map(rest), [to_tr(parse_row(l))])

def trs_fold(+xs: List<&2, Tr>, +acc: List<&2, Ty>) -> List<&2, Ty>:
  match xs:
    case Nil{}: tys_sort(acc)
    case t <> rest: trs_fold(rest, tys_go(tr_bends(t), acc))

def emit_tys(+xs: List<&2, Ty>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(&2, Ty, Unit, emit_ty(t),
        _ => IO.bind(&2, Ty, Unit, emit_ty_row(t), _ => emit_tys(rest)))

def emit_defs(+xs: List<&2, Tr>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(&2, Tr, Unit, IO.print(emit_def(t)), _ => emit_defs(rest))

def main() -> IO(Unit):
  do IO<Unit>:
    raw : String <- read_lines(".agents/slop/ag-libclang.tramp")
    trs : List<&2, Tr> <- IO.pure(&2, Tr, trs_map(String.lines(raw)))
    tys : List<&2, Ty> <- IO.pure(&2, Ty, trs_fold(trs, Nil{}))
    IO.print(emit_head(List.length(&2, Ty, tys), List.length(&2, Tr, trs)))
    IO.bind(&2, Ty, Unit, emit_tys(tys), _ => emit_defs(trs))
    IO.print(emit_tail())