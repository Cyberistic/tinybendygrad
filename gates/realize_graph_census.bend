# realize_graph_census.bend -- A GRAPH CENSUS over `tinybendygrad/engine/realize.bend`,
# the port of `tinygrad/engine/realize.py`, driven through the port's OWN defs.
#
#   .venv/bin/python gates/realize_graph_census-gate.py
#
# THE POPULATION IS THE (DRIVER, NODE) PRODUCT AND BOTH AXES ARE DISCOVERED. A ROW is a
# pair. NODE ranges over this file's ARENA -- `realize.bend`'s `main_arena` (its 42
# slots, index for index) PLUS the 19 nodes this file chains onto it, each named by the
# dispatch arm it exists for, because `main_arena` has no `MSELECT`, no `GETADDR`, no
# `MSTACK` and no SINK-without-a-`KernelInfo` and four of realize's ladders dispatch on
# exactly those. DRIVER ranges over the port's own group-[a] entry points: the eight
# whose signature `(fuel: Nat, )?+ar: O.Arena` INTERSECTS the names `realize.py` itself
# defines (`get_call_arg_uops`, `resolve_params`, `get_call_outs_ins`,
# `get_call_written_bufs`, `get_call_kernels`, `get_call_name`, `get_call_var_uops`,
# `_get_call_to_compile`), the three more that own a `case O.Ops*` arm with no name in
# `realize.py` (`rz_est_of`/`rz_nbytes_of`/`has_dnum` -- `estimate_uop` and
# `unwrap_multi`), and the three `*_table` defs (`grep -c '^def [a-z]*_table'` = 3).
# FIFTEEN, and the gate re-measures that intersection on every run.
#
# EVERY PAIR IS EMITTED, refusals included, so the two lanes carry the same row count BY
# CONSTRUCTION: 15 x 60 = 900 driver rows, 12 arm-coverage rows and 15 bottom rows =
# 927. The bottom rows exist because `Arena.empty` spends slot 0 on `bottom()` and CPython
# has no such node, so there is nothing to compare and the row says so rather than
# hiding it.
#
# THE CALL-ONLY RULE IS CPYTHON'S, APPLIED ON BOTH SIDES. `UOp.body` (ops.py:562) RAISES
# for a non-CALL, and nine of realize's readers read `call.body` or `call.src[1]`, so a
# driver over a non-CALL node has no CPython answer to compare. Both lanes answer the
# literal `notacall` there, decided by the node's OWN op tag -- the fixture's fact, not a
# list -- so the refusal is a byte-identical row and not an exclusion list.
#
# THE PRINTER IS DEEPER THAN `Rng.sig`. `Rng.sig` (ops.bend:5897) prints a toposort COUNT,
# the top op and a 3-op src PREFIX; `rng_graph_census-gate.py` records the node-swap that
# hid behind it (`gr_10` printed identically on both sides until a deep printer was used)
# and `md_graph_census` answered with an ` arg=` suffix. `rs_cone` is the answer's WHOLE
# cone, DFS pre-order, parent before child, src[0] first, each arena node ONCE -- and
# `rs_s2` gives every VIEW op one more level, because `SHRINK(resolved, 0, 2)` and
# `SHRINK(b0, 0, 2)` are both `SHRINK/3` and `realize.py:131`'s `inputs[b.arg.slot]` is
# exactly that difference. CONST VALUES are printed too, for the two drivers whose
# subject IS a bound value.
#
# THE STALE-ARENA TRAP IS THE TRAP THIS TREE HAS FALLEN IN NINE PLACES, so both lanes
# read their answers off the ANSWER'S OWN ARENA and not off the one handed in:
# `resolve_params` and `get_call_var_uops` grow it, and they answer `RZ.RList{ar, xs}`
# for exactly that reason. Every reader below takes `RList.ar(r)` / `O.Found.ar(f)`.
#
# DEF ORDER IS THE BEND TRAP, not a style note: a def must be defined BEFORE its caller.
import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/engine/realize.bend as RZ

# ============================================================ the printers

def rs_n() -> Nat: 65n
def rs_drv_n() -> Nat: 15n
def rs_arms_n() -> Nat: 12n


# THE CONE FUEL. `Arena.budget` is `next(ar) + edges(ar)`, which bounds both walks here,
# and it is the FIRST def because Bend requires a def to exist before its callers do.
def rs_fuel(ar: O.Arena) -> Nat:
  O.Arena.budget(ar)

def rs_put(nm: String, s: String) -> List<&2, String>:
  [String.concat([nm, "=", s])]

# `cat` PREPENDS, so a fold that appends each src in order leaves src[0] at the head and
# popping the head is DFS pre-order with src[0] first -- the order CPython's `cone`
# walks (`for s in v.src: go(s)`). The cone list is built by PREPENDING each visited node
# and `List.reverse`d once at the end, so the walk itself is O(1) per node.
def rs_cat(h: U32, st: List<&2, U32>) -> List<&2, U32>:
  h <> st

# A NODE ALREADY VISITED IS NOT PUSHED AND NOT LISTED TWICE. Unconditional, this listed a
# shared node once per parent -- `decomp`'s `dd_rs` header records the measurement, and
# CPython's `cone` dedups by `id`.
def rs_add(hit: Bool, u: U32, seen: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}: seen
    case False{}: rs_cat(u, seen)

def rs_push(f: Nat, srcs: List<&2, U32>, st: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: st
    case 1n+q:
      match srcs:
        case Nil{}: st
        case s <> t: rs_cat(s, rs_push(q, t, st))

def rs_has(f: Nat, xs: List<&2, U32>, +u: U32) -> Bool:
  match f:
    case 0n: False{}
    case 1n+q:
      match xs:
        case Nil{}: False{}
        case h <> t: Bool.or(U32.is_eq(h, u), rs_has(q, t, u))

def rs_go(f: Nat, +ar: O.Arena, +st: List<&2, U32>, +seen: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: seen
    case 1n+q:
      match st:
        case Nil{}: seen
        case +u <> rest:
          hit = rs_has(rs_fuel(ar), seen, u)
          st2 = rs_push(rs_fuel(ar), O.Arena.srcs(ar, u), rest)
          rs_go(q, ar, st2, rs_add(hit, u, seen))

def rs_cone.go(+ar: O.Arena, f: Nat, roots: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, rs_go(f, ar, roots, Nil{}))

def rs_cone(ar: O.Arena, roots: List<&2, U32>) -> List<&2, U32>:
  +a = ar
  rs_cone.go(a, rs_fuel(a), roots)

# A CONST's VALUE, and a `ParamArg`'s BOUND VALUE are in no node shape at all --
# `decomp_graph_census-gate.py`'s own footer names that hole and the `f2f_dt[fr]`
# fixture defect that lived in it. `var` and `res` are exactly the readers whose subject is
# a bound value, so here it is printed: `APy{CInt}` and `ParamArg.val`.
def rs_cval.cint(i: H.I64) -> String:
  U32.show(H.lo32(i))

def rs_cval.go(v: O.Const) -> String:
  match v:
    case O.CInt{i}: rs_cval.cint(i)
    case _: "f"

def rs_opt_str(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "-"

def rs_opt_const(m: Maybe<&2, O.Const>) -> String:
  match m:
    case Some{v}: rs_cval.go(v)
    case _: "-"

def rs_pay.box(s: String) -> String:
  String.concat(["[", s, "]"])

# THE COMMA JOIN AND THE `-` FOR AN EMPTY LIST, HERE BECAUSE THE `arg` PAYLOAD BELOW IS THE
# FIRST READER. `oi`'s two index lists and `ProgramInfo`'s four are all `rs_ids`, and both
# `-` FOR AN EMPTY LIST AND NOT `none`: `realize.py:24-27` answers `()` and
# `tuple(range(...))`, so an empty `outs` prints `-`, while `rs_join.dash`'s `none` is the
# LIST drivers' spelling (`dst is None`) and reusing it here made ten `oi` rows read as
# divergences that were a dash.
def rs_join2.add(first: Bool, +acc: String, +s: String) -> String:
  match first:
    case True{}: s
    case False{}: String.concat([acc, ",", s])

def rs_ids.dash(first: Bool, acc: String) -> String:
  match first:
    case True{}: "-"
    case False{}: acc

def rs_ids(f: Nat, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match f:
    case 0n: rs_ids.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: rs_ids.dash(first, acc)
        case +h <> t:
          s = rs_join2.add(first, acc, U32.show(h))
          rs_ids(q, t, s, False{})

# `ProgramInfo.vars` IS A LIST OF NODES, NOT OF INTEGERS, so `rs_ids` cannot print it and
# the var is resolved through ITS OWN `ParamArg`. THE NAME AND NOT THE SLOT, because
# `realize.py:18`'s `bound = {s.expr: ...}` keys on `s.expr` -- THE NAME (ops.py's
# `UOp.expr`) -- so a PROGRAM holding the wrong variable is invisible unless the name is
# printed. `vars` is in NO node shape otherwise: it is not a `src` of the PROGRAM.
def rs_pay.paname(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: rs_opt_str(O.ParamArg.name(pa))
    case _: "-"

def rs_pay.var(f: Nat, +ar: O.Arena, xs: List<&2, U32>, +acc: String, first: Bool) -> String:
  match f:
    case 0n: rs_ids.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: rs_ids.dash(first, acc)
        case +h <> t:
          s = rs_join2.add(first, acc, rs_pay.paname(O.Arena.arg(ar, h)))
          rs_pay.var(q, ar, t, s, False{})

# VARS ; GLOBALS ; OUTS ; INS -- `realize.py:24-27`'s two lists, `realize.py:18`'s `vars`
# and `realize.py:139`'s `globals`. `global_size`/`local_size` are `4,1,1`/`1,1,1` on all
# nine PROGRAMs and no `realize.py` reader touches them. THE DESTRUCTURING IS NOT STYLE: a
# record holding `List<&2, ...>` is AFFINE, so `O.ProgramInfo.globals(pi)` after
# `O.ProgramInfo.vars(pi)` is `consumed more than once` -- MEASURED, that is the error.
def rs_pay.pi(+ar: O.Arena, pi: O.ProgramInfo) -> String:
  match pi:
    case O.ProgramInfo{gs, ls, vars, globals, outs, ins}:
      g = rs_ids(rs_fuel(ar), globals, "", True{})
      o = rs_ids(rs_fuel(ar), outs, "", True{})
      i = rs_ids(rs_fuel(ar), ins, "", True{})
      v = rs_pay.var(rs_fuel(ar), ar, vars, "", True{})
      String.concat([v, ";", g, ";", o, ";", i])

# `Ops.RANGE`'s arg is `(axis_type, *dims)` (`ops.py:201`'s key) and this port spells it
# `ARange{ids, at}`. `d` or `-` for the axis -- ONE Bool, which is `crp_graph_census.bend`'s
# `addrstr` for `AddrSpace` and is honest about the rest: the other seven CPython axes and
# this port's two bend-only ones (`AXIS_REDUCE`, `AXIS_UNROLL`) ALL print `-`, and this
# fixture has exactly ONE RANGE, so nothing here can be wrong.
#
# `Ops.BITCAST`'s `ADt` arm IS crp's, verbatim, and it reads the dtype's name through
# `fold.bend:5891`'s `dt_nm` -- already imported as `F` -- because `spec.bend` has NO reader
# for `Dt{..., nm}` (`jit.bend:435` records that as the blocker it was) and `dt_nm` is the
# one the tree has. It is tinygrad's own `DType.name`, so `apay`'s `a.name` is the same
# string and not a translation.
def rs_pay.ax(at: O.AxisType) -> String:
  Bool.pick(String, O.eq_axis(at, O.AXIS_DEVICE{}), "d", "-")

# A `ParamArg` IS AFFINE, so `O.ParamArg.name(pa)` and `O.ParamArg.val(pa)` in ONE
# expression is `consumed more than once` -- MEASURED -- and `O.AParam` binds its ONE field
# (`pa`) rather than the record's thirteen, so the record is destructured in a NESTED
# match. Both halves are `PArg.of` (`realize.bend:231`), verbatim.
def rs_pay.pa(pa: O.ParamArg) -> String:
  match pa:
    case O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device,
                    volatile, image, buffer, bind_on_realize, val}:
      rs_pay.box(String.concat([rs_opt_str(name), ":", rs_opt_const(val)]))

def rs_pay.ki(ki: O.KernelInfo) -> String:
  match ki:
    case O.KernelInfo{name, applied_opts, opts_to_apply, beam}:
      rs_pay.box(String.concat([name, ":", U32.show(beam)]))

# THE `arg` PAYLOAD, IN BRACKETS, ON EVERY NODE WHOSE ARG IS NOT `None`. THE HOLE IT FILLS
# IS MEASURED, NOT ASSERTED: over this fixture's own 65 nodes the previous token spelled
# **32 DISTINCT TOKENS FOR 65 NODES** -- 147 of the 2080 node pairs printed IDENTICALLY
# (fifteen CALLs as `CALL/3`, seven PROGRAMs as `PROGRAM/1`, `k1`/`k2`/the bodyless SINK as
# `SINK/0`, a bound and an unbound var as `PARAM/0@2`); MEASURED after, 60 tokens and 8
# pairs, and every one of the eight is a pair whose TWO ARGS ARE EQUAL
# (`.agents/slop/realizegaps/collide.py`).
#
# THE SPELLING IS THE SIBLING'S: `crp_graph_census.bend`'s `tok.arg` prints `OP/NSRC[TARGET]`
# and `md_graph_census.bend` appends ` arg=`, and the bracket is the one that travels PER
# NODE rather than on a root. THE TEST IS ON THE ARG AND NOT ON THE OP -- so an op that
# ever grows one of these is printed by this and not by a list of ops that would rot beside
# it -- and it needs no `Ops.CONST` conjunct here, because this port's `Arg` is a
# 24-CONSTRUCTOR SUM (`ops.bend:1190`) with a separate `APy` and `AInt`. CPython's `arg` is
# `Any`, so the oracle's ladder DOES need `u.op is Ops.CONST` to tell a CONST's bare `int`
# from an MSELECT's shard index; that asymmetry is the price of `Any`.
#
# `ANone{}` PRINTS NOTHING, and so do the two pairs the payload cannot close: the four
# PROGRAMs whose `ProgramInfo` is EQUAL (they differ in `src[0]`), and the four LINEARs
# whose arg is `None`. Printing `src[0]` on every node would close them and is NOT this
# change -- `rs_s2`'s view rule is a separate decision about arity.
def rs_pay(a: O.Arg, ar: O.Arena) -> String:
  match a:
    case O.ANone{}: ""
    case O.ADt{dt}: rs_pay.box(F.dt_nm(dt))
    case O.APy{v}: rs_pay.box(rs_cval.go(v))
    # NAME : VAL. `slot` is `@<slot>` below, `name` is `s.expr` AND `has_dnum`'s
    # `_device_num` test, `val` is `is_bound_var` (`ops.py:1023`) AND
    # `UOp.const(s.arg.val)` (`realize.py:18`). NINE FIELDS OMITTED, each named in the
    # oracle's `apay`: `device` has NO SHARED SPELLING (a CPython NAME against a port TAG,
    # and CPython has no `str -> int` device index to compare one against --
    # `device_vocab_holds`), and the other
    # eight are constant across all nineteen of this fixture's `ParamArg`s (MEASURED: every
    # `dtype` is `dtypes.i32`, `addrspace` is GLOBAL on the eleven buffer args and ALU on
    # the four var args, `size` is `16` or absent).
    case O.AParam{pa}: rs_pay.pa(pa)
    case O.ACustom{cf}: rs_pay.box(O.CustomFunction.name(cf))
    case O.ACall{ci}: rs_pay.box(rs_opt_str(O.CallInfo.name(ci)))
    # NAME : BEAM, AND THE BEAM IS WHY THIS ARM IS HERE: `rz_kernel_beam` reads it and
    # `pm_beam` writes it, so `k1` (beam 0) and `k2` (beam 2) printed `SINK/0` ALIKE in every
    # cone, and `gates/realize_graph_census-mutate.py`'s `X5` -- `k2`'s beam 2 -> 5 -- was
    # declared VACUOUS for exactly that reason. `estimates` IS ABSENT DELIBERATELY: `ops.bend`
    # DROPS the field (`Estimates` is `renderer/__init__.py:16`, P5) and every SINK here
    # carries `None` on CPython's side, so there is nothing to compare.
    case O.AKernel{ki}: rs_pay.ki(ki)
    # THE ARENA IS MOVED IN, NOT COPIED, AND ONLY ON THIS ARM: `ProgramInfo.vars` IS A LIST
    # OF NODES, so resolving a var's name needs the arena, and `+a = ar` (the `rs_cone`
    # idiom, `realize_graph_census.bend:116`) is how an affine value is turned linear where a
    # `match` arm may not carry a linear binder of its own.
    case O.AProgram{pi}:
      +ar2 = ar
      rs_pay.box(rs_pay.pi(ar2, pi))
    case O.ARange{ids, at}: rs_pay.box(String.concat([rs_pay.ax(at),
                                                     rs_ids(rs_fuel(ar), ids, "", True{})]))
    case O.AStr{s}: rs_pay.box(s)
    # `Ops.GETADDR`'s `arg` IS A DEVICE AND NEITHER LANE CAN SPELL IT. CPython's is
    # `str|tuple[str, ...]` (`ops.py:611`, and `ops.py:844`'s `self.device`), this port's is
    # `ADev{S.D1{tag}}` / `ADev{S.Dn{tags}}` (`ops.bend:7815` mints `ADev{dev}`) -- and
    # CPYTHON HAS NO `str -> int` DEVICE INDEX for a tag to be checked
    # against (`device_vocab_holds` measures that every run: `hasattr(Device,'tag')` is False),
    # so a tag printed here would be compared against a NAME
    # the other lane cannot produce from a tag. MEASURED, printing it anyway answers `[?]`
    # here and `[CPU]` there and takes FIVE rows red: `arg_51`, `arg_63`, `beam_51`,
    # `beam_63` and `res_51`. SO THIS ARM PRINTS NOTHING, and the blindness is the SAME ONE
    # Box 1 names: a GETADDR over the WRONG DEVICE prints identically. It is also why
    # `ParamArg.device` is omitted above -- one fact, two sites.
    case O.ADev{dev}: ""
    # THE BYTES THEMSELVES, comma-joined by the `rs_ids` `oi` already uses, and NOT a
    # length: `List.length` is `Quant` and this is a `List<&2, U32>`, while `rs_ids` folds
    # the affine list and prints every byte. `b'a'` is `[97]` on CPython and `[97]` here.
    case O.ABlob{bs}: rs_pay.box(rs_ids(rs_fuel(ar), bs, "", True{}))
    case O.AInt{i}: rs_pay.box(U32.show(i))
    # AN ARG KIND NEITHER LANE SPELLS, bracketed as `?`. `argkinds_hold` in the gate
    # requires that no promoted lane contains one, so a fixture node carrying an unspelled
    # kind is a RED RUN rather than a silently degenerate token. `ABad` is the arena's
    # bottom and `ANone` is above, so neither reaches here.
    case _: rs_pay.box("?")

# THE `@<slot>` SUFFIX, THE PARAM/BUFFER SLOT, AND IT IS THE `arg=` REPAIR ON THIS
# DRIVER'S OWN SUBJECT. `realize.py:131` is `inputs[b.arg.slot]`, so the SLOT is the
# mechanism every `res` row exercises -- and it is in NO node shape: `PARAM/0` and
# `PARAM/1` printed alike, and this lane's `inputs` are `(b1, b0)`, two BUFFERs of slot 1
# and slot 0, which printed alike too. MEASURED: a port reading `slot`, `slot+1` or a
# literal `0` answers `BUFFER/1` on every `res` row and agrees with CPython on all 63.
# `md_graph_census` closed the same shape of hole with an ` arg=` suffix; this is that
# suffix and it is the ONE `ParamArg` field `res`, `arg` and `wbuf` can all read.
#
# THE OP GUARD IS THE POINT: the arg of a non-PARAM/BUFFER is an `AProgram`, an `AKernel`,
# an `AInt` (MSELECT), an `ADev` (GETADDR) -- none of which is a `ParamArg`, so reading
# `.slot` off them would print a slot for a node that has none. CPython guards with
# `isinstance(u.arg, ParamArg)` and so does the oracle's `s1`.
def rs_s1.slot(op: O.Op, sl: U32, s: String) -> String:
  match op:
    case O.OpsPARAM{}: String.concat([s, "@", U32.show(sl)])
    case O.OpsBUFFER{}: String.concat([s, "@", U32.show(sl)])
    case _: s

def rs_pslot.go(a: O.Arg) -> U32:
  match a:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: 0

# `OP/arity` + `@<slot>` + `[<the Arg payload>]` -- ONE SHAPE, and the CONST value is the
# `APy` payload like every other arg's, so `rs_s1.go`'s `is_const` Bool (which existed only
# because a `match` may not scrutinise a computed value) is gone.
def rs_s1.base(+ar: O.Arena, +u: U32) -> String:
  String.concat([O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u))])

def rs_s1(ar: O.Arena, +u: U32) -> String:
  +a = ar
  String.concat([rs_s1.slot(O.Arena.op(a, u), rs_pslot.go(O.Arena.arg(a, u)),
                            rs_s1.base(a, u)),
                 rs_pay(O.Arena.arg(a, u), a)])

# THE FIVE `_resolve` VIEW OPS -- realize.py:129-131 plus HEAD's `Ops.GETADDR`.
def rs_is_view(+op: O.Op) -> Bool:
  match op:
    case O.OpsMSELECT{}: True{}
    case O.OpsSHRINK{}: True{}
    case O.OpsBITCAST{}: True{}
    case O.OpsMSTACK{}: True{}
    case O.OpsGETADDR{}: True{}
    case _: False{}

def rs_s2(+ar: O.Arena, +u: U32) -> String:
  Bool.pick(String, rs_is_view(O.Arena.op(ar, u)),
            String.concat([rs_s1(ar, u), "<-", rs_s1(ar, O.Arena.src(ar, u, 0))]),
            rs_s1(ar, u))

def rs_join.add(first: Bool, +acc: String, +s: String) -> String:
  match first:
    case True{}: s
    case False{}: String.concat([acc, "+", s])

def rs_join.dash(first: Bool, acc: String) -> String:
  match first:
    case True{}: "none"
    case False{}: acc

def rs_lst(f: Nat, +ar: O.Arena, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match f:
    case 0n: rs_join.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: rs_join.dash(first, acc)
        case +h <> t:
          s = rs_join.add(first, acc, rs_s2(ar, h))
          rs_lst(q, ar, t, s, False{})

def rs_cone_sig(f: Nat, +ar: O.Arena, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match f:
    case 0n: rs_join.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: rs_join.dash(first, acc)
        case +h <> t:
          s = rs_join2.add(first, acc, rs_s1(ar, h))
          rs_cone_sig(q, ar, t, s, False{})

def rs_bl(b: Bool) -> String:
  Bool.pick(String, b, "1", "0")

# `show_v` (realize.bend:1649) spells `VTrue` 1, `VFalse` 0 and `VSkip` 9, and `VSkip` IS
# `rewrite`'s `None`. This lane spells it `0` because the oracle's `rewrite_sig` maps `None`
# AND the `ret is uop` identity of `ops.py:1618` to `"0"`, and a census that renamed one
# lane's spelling would be comparing a lane against a lane it had itself edited.
def rs_vskip(v: O.Verdict) -> Bool:
  match v:
    case O.VSkip{}: True{}
    case _: False{}

# ==================================================================== the arena

# `rs_ext` CHAINS ONTO `main_arena`'s arena rather than rebuilding it: slot 42 is the
# first new node, so `main_arena`'s index map (realize.bend:1485-1507) still reads true
# and the census cannot silently renumber the port's fixture. `O.UOp.new` returns the
# GROWN arena inside an `O.Found`, so each node chains on `O.Found.ar` of the last --
# handing back a bare index would be the stale-arena self-loop.
def rs_cpu() -> S.Dev:
  S.D1{0}

def rs_zf() -> O.PyRange:
  O.PyRange{H.i64_of_i32(0), H.i64_of_i32(4)}

# `rs_buf` WITH THE DEVICE AS A PARAMETER, because `rs_x64` needs a `Dn` and a
# `ParamArg` field cannot be chosen by a caller that was handed the tag. The 13 fields
# are `main_arena`'s `buf_arg` (`realize.bend:1552`) index for index; only the 8th moves.
def rs_buf_dev(slot: U32, nm: String, d: S.Dev) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{16}, None{}, None{}, Some{nm}, S.AGlobal{},
             Some{d}, False{}, None{}, Some{0}, False{}, None{}}

def rs_buf(slot: U32, nm: String) -> O.ParamArg:
  rs_buf_dev(slot, nm, rs_cpu())

def rs_var(slot: U32, nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, Some{rs_zf()}, Some{1}, Some{nm}, S.Aalu{},
             None{}, False{}, None{}, Some{0}, False{}, None{}}

def rs_bnd(slot: U32, nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, Some{rs_zf()}, Some{1}, Some{nm}, S.Aalu{},
             None{}, False{}, None{}, Some{0}, False{}, Some{O.CInt{H.i64_of_i32(4)}}}

def rs_ci(nm: String) -> O.CallInfo:
  O.CallInfo{Some{nm}, False{}, False{}, S.void()}

def rs_ki(nm: String, beam: U32) -> O.KernelInfo:
  O.KernelInfo{nm, Nil{}, None{}, beam}

def rs_pi(gs: List<&2, U32>, vars: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>) -> O.ProgramInfo:
  O.ProgramInfo{[H.i64_of_i32(4), H.i64_of_i32(1), H.i64_of_i32(1)],
               [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], vars, gs, outs, ins}

# `AInt` is MSELECT's shard index (`UOp.mselect`, ops.py:769) and `ADev` is `GETADDR`'s
# device (ops.py:844); `UOp.new_buffer` mints them, and this file builds the nodes
# directly because it is a fixture, not a reimplementation of a reader.
def rs_call(nm: String, +ar: O.Arena, src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsCALL{}, src, O.ACall{rs_ci(nm)}, O.TNone{})

# The 22 new nodes, in slot order 42..63, plus `rs_x64`/`rs_x65` after them. `main_arena`
# has no MSELECT, no GETADDR, no
# MSTACK, no SHRINK, no SINK without a KernelInfo, no PROGRAM whose kernel is unnamed and
# no MSELECT in an `outs` slot, so `rz_arm`'s MSELECT/SHRINK/MSTACK arms, HEAD's GETADDR
# arm, `gcc_sink`'s and `gcc_pick.prog`'s DEFAULT arms, `gn_prog`'s default arm and
# `get_call_written_bufs`'s MSELECT wall would ALL be unreachable rows without them.
#
# ... has no MULTI-DEVICE buffer either, so `len()` was only ever tested on lists of
# length 0 and 1 -- `rs_x64`/`rs_x65` are that node.
#
# THE SRC LISTS ARE LITERAL INDICES, and that is the same invariant `main_arena` states
# for itself: node k is at index k because the ORDER of the `UOp.new` calls IS the arena.
# It holds only while every node here is DISTINCT -- `UOp.new` hash-conses, so a repeat
# would take no slot and renumber everything after it. `arena_n` is the guard: it reads
# 66, and a hash-consed node makes it 65 and takes the lane red.
def rs_x42(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})

def rs_x43(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})

def rs_x44(+ar: O.Arena) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})

def rs_x45(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsSHRINK{}, [9, 43, 44], O.ANone{}, O.TNone{})

def rs_x46(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsMSELECT{}, [9], O.AInt{0}, O.TNone{})

def rs_x47(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsGETADDR{}, [9], O.ADev{S.D1{0}}, O.TNone{})

def rs_x48(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsMSTACK{}, [2, 3], O.ANone{}, O.TNone{})

def rs_x49(+ar: O.Arena) -> O.Found:
  rs_call("vs", ar, [7, 3, 45])

def rs_x50(+ar: O.Arena) -> O.Found:
  rs_call("vm", ar, [7, 3, 46])

def rs_x51(+ar: O.Arena) -> O.Found:
  rs_call("vg", ar, [7, 3, 47])

def rs_x52(+ar: O.Arena) -> O.Found:
  rs_call("vk", ar, [7, 3, 48])

def rs_x53(+ar: O.Arena) -> O.Found:
  rs_call("ss", ar, [7, 7])

def rs_x54(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsSINK{}, Nil{}, O.ANone{}, O.TNone{})

def rs_x55(+ar: O.Arena) -> O.Found:
  rs_call("nk", ar, [54, 2])

def rs_x56(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsPROGRAM{}, [54], O.AProgram{rs_pi([0, 1], Nil{}, [0], [1])}, O.TNone{})

def rs_x57(+ar: O.Arena) -> O.Found:
  rs_call("nb", ar, [56, 9, 10])

def rs_x58(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsLINEAR{}, [52, 49], O.ANone{}, O.TNone{})

def rs_x59(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsPROGRAM{}, [7], O.AProgram{rs_pi([0, 1, 2], Nil{}, [2], [1])}, O.TNone{})

def rs_x60(+ar: O.Arena) -> O.Found:
  rs_call("mb", ar, [59, 9, 10, 46])

def rs_x61(+ar: O.Arena) -> O.Found:
  rs_call("vb", ar, [7, 2, 41])

# THE GETADDR OVER A **PARAM**, AND IT IS THE POINT OF THE NODE. `ops.py:844` builds
# `UOp(Ops.GETADDR, src=(self,), ...)` and `self` is a PARAM as often as a BUFFER. A
# GETADDR over a BUFFER is INVISIBLE on this census: HEAD's `_resolve` recurses into
# `src[0]`, `_resolve(BUFFER)` returns it unchanged, the rebuilt GETADDR is
# content-identical and hash-conses -- MEASURED: with only node 47 in the fixture,
# `res_51` AGREES on both sides. Over a PARAM, `inputs[b.arg.slot]` fires and the two
# sides part, which is the whole vendored-drift answer.
def rs_x62(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsGETADDR{}, [2], O.ADev{S.D1{0}}, O.TNone{})

# AND THE CALL CARRIES THE THIRD CONSTANT TOO, so that NO SLOT IN THIS ARENA IS
# UNREFERENCED. MEASURED before this line: the census fixture had ONE dead node, slot
# 42's `CONST 1`, which nothing referenced -- a root-walking printer cannot see that,
# and this lane ROWS EVERY SLOT BY INDEX rather than walking from a root, so it could:
# `res_42` was a row answering a node nothing in the graph points at. Every other
# unreferenced slot is a CALL or a LINEAR, which are realize.py's own ROOTS
# (`run_linear` iterates `linear.src`, `lower_and_compile` walks `linear.toposort()`),
# so "unreferenced" is a fact about roots and not about garbage.
def rs_x63(+ar: O.Arena) -> O.Found:
  rs_call("vv", ar, [7, 3, 62, 42])

# THE MULTI-DEVICE BUFFER, AND IT IS THE ROW `kern` HAD NO ANSWER FOR. `realize.py:41` is
# `[(d, call, None) for d in to_tuple(call.src[1].device)]` and `to_tuple`
# (`helpers.py:52`) is `x if isinstance(x, tuple) else (x,)` -- so a device that is a
# TUPLE puts MORE THAN ONE KERNEL in the answer, and `helpers.py:52` answers `(None,)` for
# a `None` device rather than the empty tuple. EVERY device in `main_arena` and in the
# twenty nodes above is a scalar `S.D1`, so all 22 `kern_*` rows were lists of length 0 or
# 1 and `len()` -- which is all `rs_d_kern` prints -- was only ever tested on a list that
# could not surprise it. MEASURED, `.venv/bin/python`, calling `realize.py`'s own
# `get_call_kernels` on a `ParamArg(device=("DISK","CPU"))`: n=2, first fields
# `('DISK','CPU')`. No device is OPENED: `ParamArg.device` is `str | tuple[str, ...]`, so a
# name is data and not hardware.
#
# **AND THE TWO TAGS ARE DISTINCT ON PURPOSE.** `S.Dn{[6, 0]}` is DISK and "not DISK",
# and `device.bend:344`'s `tag_of` gives DISK the tag 6 and everything else 0 -- so a bug
# that emitted one device twice, or dropped one, moves the count, and the tags differ.
# WHAT IT STILL CANNOT SEE IS STATED AT `rs_d_kern` AND MEASURED IN THE GATE.
def rs_duo() -> S.Dev:
  S.Dn{[6, 0]}

def rs_x64(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, [1], O.AParam{rs_buf_dev(3, "g2", rs_duo())}, O.TNone{})

# THE CALL WHOSE `src[1]` IS IT, so `kern` has a row with TWO devices in the answer.
def rs_x65(+ar: O.Arena) -> O.Found:
  rs_call("dm", ar, [11, 64])

# THE ARENA. `main_arena`'s 42 slots, index for index, plus the twenty-two above chained onto
# its arena -- `O.UOp.new` returns the GROWN arena inside an `O.Found`, so handing back a
# bare index would be the stale-arena self-loop this tree has found in nine places.
def rs_arena() -> O.Arena:
  +l = RZ.main_arena()
  +e42 = rs_x42(RZ.Land.ar(l))
  +e43 = rs_x43(O.Found.ar(e42))
  +e44 = rs_x44(O.Found.ar(e43))
  +e45 = rs_x45(O.Found.ar(e44))
  +e46 = rs_x46(O.Found.ar(e45))
  +e47 = rs_x47(O.Found.ar(e46))
  +e48 = rs_x48(O.Found.ar(e47))
  +e49 = rs_x49(O.Found.ar(e48))
  +e50 = rs_x50(O.Found.ar(e49))
  +e51 = rs_x51(O.Found.ar(e50))
  +e52 = rs_x52(O.Found.ar(e51))
  +e53 = rs_x53(O.Found.ar(e52))
  +e54 = rs_x54(O.Found.ar(e53))
  +e55 = rs_x55(O.Found.ar(e54))
  +e56 = rs_x56(O.Found.ar(e55))
  +e57 = rs_x57(O.Found.ar(e56))
  +e58 = rs_x58(O.Found.ar(e57))
  +e59 = rs_x59(O.Found.ar(e58))
  +e60 = rs_x60(O.Found.ar(e59))
  +e61 = rs_x61(O.Found.ar(e60))
  +e62 = rs_x62(O.Found.ar(e61))
  +e63 = rs_x63(O.Found.ar(e62))
  +e64 = rs_x64(O.Found.ar(e63))
  +e65 = rs_x65(O.Found.ar(e64))
  O.Found.ar(e65)

# `inputs` ARE THE TWO BUFFERs IN REVERSE -- slot 0 answers the g1 BUFFER, slot 1 the g0
# one -- and that is a PRINTER decision and not a convenience. `g0` and `g1` are both
# `PARAM/0`, so a slot lookup of either prints `PARAM/0` and `realize.py:131`'s
# `inputs[b.arg.slot]` becomes INVISIBLE: MEASURED, with `inputs=(g1, g0)` the GETADDR row
# `res_63` AGREED on both sides and the whole vendored-drift answer hid inside one row.
# Over two BUFFERs, slot 0 answers a BUFFER, the port's un-resolved GETADDR answers a
# PARAM, and the two part. realize.bend's own `res_slot0`/`res_slot1` rows use `(g1, g0)`
# and would not have caught it; that is the difference between a fixture and a claim.
def rs_inputs() -> List<&2, U32>:
  [10, 9]

# ==================================================================== the drivers
#
# FIFTEEN, in the ORDER the oracle prints them, because `gatekit` diffs the lanes LINE BY
# LINE and the order is part of the contract. `0 arg` ... `14 dnum`.

def rs_is_call(ar: O.Arena, n: U32) -> Bool:
  O.op_is(ar, n, O.OpsCALL{})

# THE NINE CALL-ONLY DRIVERS, and CPython's reason for each: `UOp.body` (ops.py:562)
# raises for a non-CALL, and `_resolve`'s `inputs[b.arg.slot]` and `estimate_uop`'s
# `prod(call.src[1].shape)` both read `src[1]`. `arg`, `res`, `flat`, `val`, `beam` and
# `bea0` answer for EVERY node, which is why `arg` is the row that finds realize.py:15's
# raw `call.src[1:]` against the port's op-CONDITIONAL `Arena.src_without_body`.
def rs_call_only(drv: U32) -> Bool:
  match drv:
    case 0: False{}
    case 1: True{}
    case 2: False{}
    case 3: False{}
    case 4: False{}
    case 5: False{}
    case 6: False{}
    case 7: True{}
    case 8: True{}
    case 9: True{}
    case 10: True{}
    case 11: True{}
    case 12: True{}
    case 13: True{}
    case _: True{}

def rs_d_flat.go(+f: O.Found, fired: Bool) -> String:
  Bool.pick(String, fired,
            String.concat(["1:", rs_cone_sig(rs_fuel(O.Found.ar(f)), O.Found.ar(f),
                                            rs_cone(O.Found.ar(f), [O.Found.i(f)]), "", True{})]),
            "0")

# `pm_beam`'s ANSWER WITH THE BEAM, because a cone cannot see it: realize.py:219 is
# `sink.replace(arg=replace(sink.arg, beam=ctx))`, and `KernelInfo.beam` is in NO node
# shape, so `beam 2 -> 7` rewrites a cone that prints identically. MEASURED on the oracle
# lane: with the suffix nowhere, `beam_24` read as a port divergence on a graph the two
# sides agreed about node for node. This is the `arg=` repair, on the driver's own subject.
# `11` IS THIS PREFIX AND NOT `1`, and the second digit is the point of Box 3: the whole
# answer is `<claim><fired>` and only a CLAIMED, NEW node reaches this branch. Its `fired`
# parameter is GONE because there is now exactly one way in -- `rs_d_beam.fired.go` -- and
# `Bool.pick` would have evaluated this arm's `rs_cone` for the refused nodes too.
def rs_d_beam.go(+f: O.Found) -> String:
  String.concat(["11:", String.concat([rs_cone_sig(rs_fuel(O.Found.ar(f)), O.Found.ar(f),
                                                 rs_cone(O.Found.ar(f), [O.Found.i(f)]),
                                                 "", True{})]),
                         ":b=", U32.show(RZ.rz_kernel_beam(O.Arena.arg(O.Found.ar(f),
                                                                    O.Arena.src(O.Found.ar(f), O.Found.i(f), 0))))])

def rs_d_flat(ar: O.Arena, +n: U32) -> String:
  +a = ar
  +v = RZ.flatten_rewrite(a, n)
  rs_d_flat.go(RZ.rz_lin_new(a, n), Bool.not(rs_vskip(v)))

# `pm_validate` is `PatternMatcher([...]) + pm_flatten_linear` (realize.py:214) and
# `PatternMatcher.__add__` is `PatternMatcher(self.patterns+more.patterns)` (ops.py:1611),
# so `pm_validate.rewrite` tries tag 0 and THEN TAG 1 ON THE SAME NODE. This driver asked
# tag 0's claim ALONE, which is why it answered `0` at `val_27` where CPython answered the
# flatten cone: node 27 is a LINEAR, tag 0 does not claim it, and tag 1 is the rewrite that
# DOES fire. The body was already in the port: this arm reaches it through `rs_d_flat` ->
# `flatten_rewrite` -> `fl_0`, because a `Verdict` alone cannot print a cone.
#
# IT DOES **NOT** GO THROUGH `va_1`, WHICH IS TAG 1'S OWN ENTRY, AND THAT IS A SEPARATE
# FINDING: `va_1` and `va_0` are DEAD DEFS called by NOTHING. MEASURED -- replacing
# `va_1`'s body with `VSkip` leaves the gate GREEN and moves ZERO of the 974 rows. This
# fix does not revive them and does not pretend to: it needed the rewrite's NODE, and
# `va_1` answers a `Verdict`.
#
# THE TAG-0 BRANCH STILL ANSWERS THE CLAIM BIT, because `_validate`'s `UOp.new_buffer` is a
# P6 device call and its `store_call` is `TODO(p3)` (`param_like` absent), so there is no
# graph to print. THE CLAIM IS A `.go` PARAMETER, NOT A `Bool.pick`: `match` refuses a
# computed scrutinee (MEASURED, "a match cannot scrutinize a computed value: give it its
# own def"). THE TWO ARMS ARE NOT INTERCHANGEABLE EITHER. MEASURED, dispatching tag 1
# unconditionally moves exactly these ten rows and NOTHING else: it answers `0` on all of
# them, where tag 0 DID claim and DID fire and built a graph the port cannot build, so the
# eager form turns the claim bit into "no rewrite" about a rule that rewrote. It moves
# nothing else because `rz_find.mint` hash-conses and the `flat` driver has already minted
# those nodes for all 63 -- the arena does NOT shift, so `@<slot>` is NOT the reason.
def rs_d_val.go(c: Bool, +ar: O.Arena, +n: U32) -> String:
  match c:
    case True{}: "1"
    case False{}: rs_d_flat(ar, n)

def rs_d_val(ar: O.Arena, +n: U32) -> String:
  +a = ar
  rs_d_val.go(RZ.va_claim(a, n), a, n)

# THE VERDICT IS THE JUDGE **AND** THE ANSWER'S INDEX, and the second half is new since
# the `ret is not uop` fix. `RZ.beam_rewrite` is `realize.bend`'s JUDGE (it answers a
# `Verdict`, never a node) and `RZ.bm_new` is the BODY; CPython's `PatternMatcher.rewrite`
# returns the body's node or `None`, so a faithful driver asks BOTH: did the rule fire, and
# did it produce something other than the node it was handed? `bm_new` applies
# `M.hop_self` now, so "nothing" IS index 0 and the test is one comparison.
# MEASURED, the two contexts this driver exists for: at ctx 7 the answer is a NEW node on
# both sides and the two lanes agree byte for byte; at ctx 0 every replacement is the
# identity, the port now answers index 0 and so does CPython.
#
# **AND THE TWO ANSWERS ARE NOW TWO BITS, NOT ONE.** The single `"0"` this printer used to
# emit for `Bool.and(not vskip, index != 0)` was TRUE OF TWO DIFFERENT WORLDS: "the rule
# did not claim this node" and "the rule claimed it and every replacement was the
# identity". MEASURED, both were printed `0`: `beam_1` (a CONST, `rz_claim` false) and
# `bea0_23` (a SINK already carrying beam 0, `rz_claim` true and the rewrite the identity).
# That collapse is what made mutation `V2` -- `rz_kernel_beam`'s no-`KernelInfo` default
# `0` -> `1` -- move ZERO of the 974 rows at rc=0: the default is read only by `bm_zero`,
# the CLAIM, and on the one node that reads it (`cNk`, a CALL over a bodyless SINK) the
# claim is the only thing that changes while the answer stays "no rewrite". So the row is
# `<claim><fired>`: `00` not claimed, `10` claimed and the rewrite was the identity, `11`
# claimed and it produced a new node. `V2` moves `beam_55` and `bea0_55` now, and `V4`
# (`bm_zero` always true) moves `beam_24`/`bea0_24`.
def rs_d_beam.fired.go(+f: O.Found, is_zero: Bool) -> String:
  match is_zero:
    case True{}: "10"
    case False{}: rs_d_beam.go(f)

# THE BODY RUNS ONLY WHERE THE JUDGE HELD. The previous version called `RZ.bm_new` on
# EVERY node and folded the claim into a `Bool.and`, which ran `pm_beam`'s body over nodes
# its own judge had refused -- and `rs_d_beam` is not a CALL-only driver, so that was a
# body over a CONST. `Bool.pick` evaluates both arms (the reason `rs_d_val` passes the
# claim as a `.go` PARAMETER) and `match` refuses a computed scrutinee (the reason
# `is_zero` and `skipped` are parameters and not calls), so BOTH gates are `.go`
# parameters. CPython needs no repair here: `PatternMatcher.rewrite`
# (`ops.py:1613-1619`) calls the body INSIDE `if (ret:=match(uop, ctx)) is not None`, so
# the oracle lane was right and the PORT lane was the sloppy one.
def rs_d_beam.fired(+ar: O.Arena, n: U32, ctx: U32) -> String:
  +f = RZ.bm_new(ar, n, ctx)
  rs_d_beam.fired.go(f, U32.is_eq(O.Found.i(f), 0))

def rs_d_beam.claim(+ar: O.Arena, n: U32, ctx: U32, skipped: Bool) -> String:
  match skipped:
    case True{}: "00"
    case False{}: rs_d_beam.fired(ar, n, ctx)

def rs_d_beam(ar: O.Arena, +n: U32, ctx: U32) -> String:
  +a = ar
  +v = RZ.beam_rewrite(a, n)
  rs_d_beam.claim(a, n, ctx, rs_vskip(v))

def rs_d_arg(ar: O.Arena, n: U32) -> String:
  +a = ar
  +l = RZ.get_call_arg_uops(a, n)
  rs_lst(rs_fuel(a), a, l, "", True{})

def rs_rl(+r: RZ.RList) -> String:
  +a = RZ.RList.ar(r)
  +xs = RZ.RList.xs(r)
  rs_lst(rs_fuel(a), a, xs, "", True{})

def rs_d_var(ar: O.Arena, +n: U32) -> String:
  +a = ar
  +prg = RZ.rz_body(a, n)
  rs_rl(RZ.get_call_var_uops(a, n, prg))

def rs_d_res(ar: O.Arena, +n: U32) -> String:
  +a = ar
  +ins = rs_inputs()
  rs_rl(RZ.resolve_params(RZ.rz_res_fuel(a), a, n, ins))

def rs_d_oi.go(+ar: O.Arena, +o: RZ.OutsIns) -> String:
  +outs = RZ.OutsIns.outs(o)
  +ins = RZ.OutsIns.ins(o)
  String.concat(["o=", String.concat([rs_ids(rs_fuel(ar), outs, "", True{}), ";i=",
                                      rs_ids(rs_fuel(ar), ins, "", True{})])])

def rs_d_oi(ar: O.Arena, n: U32) -> String:
  +a = ar
  rs_d_oi.go(a, RZ.get_call_outs_ins(a, n))

def rs_d_wbuf(ar: O.Arena, n: U32) -> String:
  +a = ar
  +l = RZ.get_call_written_bufs(a, n)
  rs_lst(rs_fuel(a), a, l, "", True{})

# WHY IT IS `len()` AND NOT THE LIST, WITH THE MEASUREMENT THAT SETTLES IT.
# `get_call_kernels` (realize.bend:679) already answers a LIST OF DEVICE TAGS --
# `dev_tags` returns `D1{tag}` -> `[tag]` and `Dn{tags}` -> `tags`, and the port's own
# comment at that def says the NAME behind each tag is `helpers.bend`'s DEV parse, "P6" --
# so the LIST is right there and this printer throws it away. IT IS THE RIGHT THING TO
# THROW AWAY, AND THE GATE MEASURES WHY, in `kern_blind_holds` over `device_vocab_holds`:
#   * `S.D1`'s tag is NOT an index into a device table, AND THIS IS NOW CHECKED RATHER THAN
#     QUOTED. An earlier revision of this comment justified it by naming `Device.tag` in
#     `uop/spec.bend:1488` -- a symbol that DOES NOT EXIST in this tree's CPython, so a
#     driver was quoting a paragraph that named nothing. `device_vocab_holds` now re-measures
#     the premise in CPython on every run: `hasattr(Device, 'tag')` is False, `ParamArg.device`
#     (`uop/ops.py:34`) is `str|tuple[str, ...]|None`, `ALL_DEVICES` (`device.py:20`) is a
#     `list[str]`, and `Device.__getitem__` (`device.py:29`) is keyed by STRING -- SO CPython
#     HAS NO `str -> int` DEVICE INDEX, and a `U32 -> String` table is the PORT'S OWN to mint.
#   * the port's ONLY tag/name function, `device.bend:344 tag_of`, is a THREE-VALUED
#     SENTINEL -- DISK 6, NPY 10, PYTHON 13, EVERYTHING ELSE 0 -- built to decide
#     `ALLOW_DEVICE_USAGE`, and it puts CPU, METAL, AMD, NV, CUDA, QCOM, CL, DSP, WEBGPU
#     and every typo on the same 0. `device_vocab_holds` reads its arm list out of
#     `device.bend`'s CODE every run, so if it grows an arm this wall goes RED.
#   * and there is a SECOND tag space that disagrees with it: `schedule/memory.bend:999`
#     is `disk() = S.D1{1}` where `tag_of("DISK")` is 6, which `uop/validate.bend:2532`
#     records and refuses to arbitrate.
# So printing a tag would print a sentinel that no name can be checked against, and a row
# that LOOKED like it tested the index while testing three values IS A GUARD THAT AGREES
# WITH ITS SUBJECT. `len()` is the one projection of the answer that does not depend on a
# tag space neither side has, and `rs_x64`/`rs_x65` make it a list of TWO devices so the
# count is tested on a list that can surprise it. THE RESIDUAL, stated rather than hidden:
# an ORDER SWAP or a WRONG-BUT-EQUAL TAG inside `Dn{[6, 0]}` is invisible, because the port
# has no vocabulary to be wrong in.
def rs_d_kern(ar: O.Arena, n: U32) -> String:
  U32.show(U32.from_nat(List.length(&2, U32, RZ.get_call_kernels(ar, n))))

def rs_maybe_s(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "none"

def rs_d_name(ar: O.Arena, n: U32) -> String:
  rs_maybe_s(RZ.get_call_name(ar, n))

def rs_d_est(ar: O.Arena, n: U32) -> String:
  rs_bl(RZ.rz_est_of(ar, n))

def rs_d_nb(ar: O.Arena, n: U32) -> String:
  U32.show(RZ.rz_nbytes_of(ar, n))

def rs_d_gcc(ar: O.Arena, n: U32) -> String:
  rs_bl(RZ.has_u32(RZ._get_call_to_compile(ar, n)))

def rs_d_dnum(ar: O.Arena, n: U32) -> String:
  rs_bl(RZ.has_dnum(ar, n))

def rs_d.go(ar: O.Arena, drv: U32, n: U32) -> String:
  match drv:
    case 0: rs_d_arg(ar, n)
    case 1: rs_d_nb(ar, n)
    case 2: rs_d_res(ar, n)
    case 3: rs_d_flat(ar, n)
    case 4: rs_d_val(ar, n)
    case 5: rs_d_beam(ar, n, 7)
    case 6: rs_d_beam(ar, n, 0)
    case 7: rs_d_oi(ar, n)
    case 8: rs_d_wbuf(ar, n)
    case 9: rs_d_kern(ar, n)
    case 10: rs_d_name(ar, n)
    case 11: rs_d_est(ar, n)
    case 12: rs_d_var(ar, n)
    case 13: rs_d_gcc(ar, n)
    case _: rs_d_dnum(ar, n)

def rs_d(ar: O.Arena, drv: U32, +n: U32) -> String:
  +a = ar
  +d = drv
  Bool.pick(String, Bool.and(rs_call_only(d), Bool.not(rs_is_call(a, n))), "notacall",
            rs_d.go(a, d, n))

# ==================================================== the bottom and the arm coverage

# THE DRIVER NAMES, IN THE ORACLE'S ORDER. `gatekit` diffs the lanes LINE BY LINE, so the
# order is part of the contract and it is the oracle's, read off its `if __main__` block.
def rs_drv_name(drv: U32) -> String:
  match drv:
    case 0: "arg"
    case 1: "nb"
    case 2: "res"
    case 3: "flat"
    case 4: "val"
    case 5: "beam"
    case 6: "bea0"
    case 7: "oi"
    case 8: "wbuf"
    case 9: "kern"
    case 10: "name"
    case 11: "est"
    case 12: "var"
    case 13: "gcc"
    case _: "dnum"

# SLOT 0 IS `Arena.bottom()` and CPython HAS NO SUCH NODE. The oracle answers `bottom` and
# this lane answers whatever the port really answers, so the divergence is declared and
# PINNED rather than hidden -- and `no_bottom_value` says the port never answers a VALUE
# there, which is the shape a stale-arena self-loop would take.
def rs_bottom(ar: O.Arena, drv: U32) -> List<&2, String>:
  +d = drv
  rs_put(String.concat(["b_", rs_drv_name(d)]), rs_d(ar, d, 0))

# THE ARM COVERAGE. `arm_<OP>` is the NUMBER OF FIXTURE NODES carrying that tag, measured
# on this lane's own arena; the oracle measures the same count on its own mirror. A tag
# with no node is an arm no row can reach, and `arms_all_reached` is what says so.
def rs_tag_of(drv: U32) -> String:
  match drv:
    case 0: "PROGRAM"
    case 1: "STORE"
    case 2: "CUSTOM_FUNCTION"
    case 3: "RANGE"
    case 4: "PARAM"
    case 5: "SINK"
    case 6: "LINEAR"
    case 7: "MSELECT"
    case 8: "SHRINK"
    case 9: "BITCAST"
    case 10: "MSTACK"
    case _: "GETADDR"

def rs_one(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

# THE TWELVE ARM COUNTERS. Twelve defs and not one, and the reason is MEASURED rather
# than taste: a single `rs_count(ar, tag, n)` that `match`es the TAG and recurses on `n`
# needs `tag` twice per step -- once to match, once to pass on -- and Bend refuses that
# with `expected : tag / observed : tag (consumed more than once)`, because a `match`
# scrutinee CONSUMES. `dc_l2i_go`'s `+i` survives two uses only because `U32.add(i, 1)`
# READS it while `dc_l2i_pick(+i)` is passed the incremented copy. So the op is a LITERAL
# at each call site and the twelve share nothing but `rs_one`.

def rs_hit_program(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsPROGRAM{}))

def rs_cnt_program(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_program(ar, n)
      rs_cnt_program(q, ar, k, U32.add(acc, s))


def rs_hit_store(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsSTORE{}))

def rs_cnt_store(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_store(ar, n)
      rs_cnt_store(q, ar, k, U32.add(acc, s))


def rs_hit_custom_function(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsCUSTOM_FUNCTION{}))

def rs_cnt_custom_function(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_custom_function(ar, n)
      rs_cnt_custom_function(q, ar, k, U32.add(acc, s))


def rs_hit_range(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsRANGE{}))

def rs_cnt_range(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_range(ar, n)
      rs_cnt_range(q, ar, k, U32.add(acc, s))


def rs_hit_param(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsPARAM{}))

def rs_cnt_param(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_param(ar, n)
      rs_cnt_param(q, ar, k, U32.add(acc, s))


def rs_hit_sink(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsSINK{}))

def rs_cnt_sink(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_sink(ar, n)
      rs_cnt_sink(q, ar, k, U32.add(acc, s))


def rs_hit_linear(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsLINEAR{}))

def rs_cnt_linear(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_linear(ar, n)
      rs_cnt_linear(q, ar, k, U32.add(acc, s))


def rs_hit_mselect(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsMSELECT{}))

def rs_cnt_mselect(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_mselect(ar, n)
      rs_cnt_mselect(q, ar, k, U32.add(acc, s))


def rs_hit_shrink(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsSHRINK{}))

def rs_cnt_shrink(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_shrink(ar, n)
      rs_cnt_shrink(q, ar, k, U32.add(acc, s))


def rs_hit_bitcast(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsBITCAST{}))

def rs_cnt_bitcast(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_bitcast(ar, n)
      rs_cnt_bitcast(q, ar, k, U32.add(acc, s))


def rs_hit_mstack(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsMSTACK{}))

def rs_cnt_mstack(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_mstack(ar, n)
      rs_cnt_mstack(q, ar, k, U32.add(acc, s))


def rs_hit_getaddr(ar: O.Arena, n: U32) -> U32:
  rs_one(O.op_is(ar, n, O.OpsGETADDR{}))

def rs_cnt_getaddr(f: Nat, +ar: O.Arena, +n: U32, acc: U32) -> U32:
  match f:
    case 0n: acc
    case 1n+q:
      +k = U32.add(n, 1)
      s = rs_hit_getaddr(ar, n)
      rs_cnt_getaddr(q, ar, k, U32.add(acc, s))


# `arm_<OP>` is the NUMBER OF FIXTURE NODES carrying that tag, measured on THIS lane's
# own arena; the oracle measures the same count on its own mirror. A tag with no node is an
# arm no row can reach, and `arms_all_reached` in the gate is what says so.
# `arm_<OP>` is the NUMBER OF FIXTURE NODES carrying that tag, measured on THIS
# lane's own arena; the oracle measures the same count on its own mirror. A tag with
# no node is an arm no row can reach, and `arms_all_reached` in the gate says so.
def rs_arms.tag(ar: O.Arena, tag: U32, f: Nat) -> List<&2, String>:
  match tag:
    case 0: rs_put("arm_PROGRAM", U32.show(rs_cnt_program(f, ar, 1, 0)))
    case 1: rs_put("arm_STORE", U32.show(rs_cnt_store(f, ar, 1, 0)))
    case 2: rs_put("arm_CUSTOM_FUNCTION", U32.show(rs_cnt_custom_function(f, ar, 1, 0)))
    case 3: rs_put("arm_RANGE", U32.show(rs_cnt_range(f, ar, 1, 0)))
    case 4: rs_put("arm_PARAM", U32.show(rs_cnt_param(f, ar, 1, 0)))
    case 5: rs_put("arm_SINK", U32.show(rs_cnt_sink(f, ar, 1, 0)))
    case 6: rs_put("arm_LINEAR", U32.show(rs_cnt_linear(f, ar, 1, 0)))
    case 7: rs_put("arm_MSELECT", U32.show(rs_cnt_mselect(f, ar, 1, 0)))
    case 8: rs_put("arm_SHRINK", U32.show(rs_cnt_shrink(f, ar, 1, 0)))
    case 9: rs_put("arm_BITCAST", U32.show(rs_cnt_bitcast(f, ar, 1, 0)))
    case 10: rs_put("arm_MSTACK", U32.show(rs_cnt_mstack(f, ar, 1, 0)))
    case _: rs_put("arm_GETADDR", U32.show(rs_cnt_getaddr(f, ar, 1, 0)))

def rs_arms.row(ar: O.Arena, tag: U32) -> List<&2, String>:
  +a = ar
  rs_arms.tag(a, tag, rs_fuel(a))

def rs_arms_go(f: Nat, ar: O.Arena, +tag: U32, acc: List<&2, String>) -> List<&2, String>:
  match f:
    case 0n: acc
    case 1n+q:
      +a = ar
      +t = U32.add(tag, 1)
      rs_arms_go(q, a, t, List.append(&2, String, acc, rs_arms.row(a, tag)))

def rs_putl(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("")
    case x <> t:
      do IO<Unit>:
        a : Unit <- IO.print(x)
        b : Unit <- rs_putl(t)
        return Unit{}

def rs_bottoms(f: Nat, +ar: O.Arena, drv: U32, acc: List<&2, String>) -> List<&2, String>:
  match f:
    case 0n: acc
    case 1n+q:
      +d = drv
      rs_bottoms(q, ar, (U32.add(d, 1) : U32),
                 List.append(&2, String, acc, rs_bottom(ar, d)))

def rs_nodes_go(f: Nat, +ar: O.Arena, drv: U32, +n: U32, acc: List<&2, String>) -> List<&2, String>:
  match f:
    case 0n: acc
    case 1n+q:
      +a = ar
      +d = drv
      +k = U32.add(n, 1)
      rs_nodes_go(q, a, d, k,
                  List.append(&2, String, acc,
                    rs_put(String.concat([rs_drv_name(d), "_", U32.show(n)]), rs_d(a, d, n))))

def rs_drvs_go(f: Nat, +ar: O.Arena, drv: U32, acc: List<&2, String>) -> List<&2, String>:
  match f:
    case 0n: acc
    case 1n+q:
      +a = ar
      +d = drv
      rs_drvs_go(q, a, (U32.add(d, 1) : U32),
                 List.append(&2, String, acc, rs_nodes_go(rs_n(), a, d, 1, Nil{})))

def rs_arena_n(ar: O.Arena) -> U32:
  U32.from_nat(List.length(&2, O.Node, O.Arena.nodes(ar)))

# `rows` IS THE COUNT, PRINTED, so a lane that stopped emitting a row cannot pass
# unnoticed. It is `arena_n`'s sibling and realize.bend's own `gate_count` is the same
# idea: Bend has no assertion form, so the row count IS the check on the gate itself.
# 2 header rows + 15 bottoms + 12 arm-coverage rows + 15 drivers x 65 nodes = 1004.
def rs_prod() -> U32:
  U32.mul(U32.from_nat(rs_n()), U32.from_nat(rs_drv_n()))

def rs_cnt() -> U32:
  (U32.add(rs_prod(), U32.add(U32.from_nat(rs_drv_n()),
                              U32.add(U32.from_nat(rs_arms_n()), 2))))

# THE ARENA IS REBUILT ONCE PER SECTION, not once per row: the rows that GROW it
# (`res`, `var`, `flat`, `beam`, `bea0`) take a COPY and grow that, and the six readers
# that do not are read-only throughout. `decomp_graph_census.bend` rebuilds per row
# because EVERY `l2i` call grows; here that would be 1005 arenas for no safety at all.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- rs_putl(rs_put("arena_n", U32.show(rs_arena_n(rs_arena()))))
    b : Unit <- rs_putl(rs_put("rows", U32.show(rs_cnt())))
    c : Unit <- rs_putl(rs_bottoms(rs_drv_n(), rs_arena(), 0, Nil{}))
    d : Unit <- rs_putl(rs_arms_go(rs_arms_n(), rs_arena(), 0, Nil{}))
    e : Unit <- rs_putl(rs_drvs_go(rs_drv_n(), rs_arena(), 0, Nil{}))
    return Unit{}