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

def rs_n() -> Nat: 63n
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

# `CONST(value)`. `UOp.const` mints `APy{CInt}`, and a CONST's VALUE is in no node shape
# at all -- `decomp_graph_census-gate.py`'s own footer names that hole and the `f2f_dt[fr]`
# fixture defect that lived in it. `var` and `res` are exactly the readers whose subject is
# a bound value, so here it is printed.
def rs_cval.cint(i: H.I64) -> String:
  U32.show(H.lo32(i))

def rs_cval.go(v: O.Const) -> String:
  match v:
    case O.CInt{i}: rs_cval.cint(i)
    case _: "f"

def rs_cval(+a: O.Arg) -> String:
  match a:
    case O.APy{v}: rs_cval.go(v)
    case _: "?"

# THE CONST TEST IS THE OP, not the arg: `UOp.const` mints `APy{CInt}` and a
# `custom_function` body mints `APy{CustomFunction}`, so matching the arg would call a
# float a constant. CPython's `u.op is Ops.CONST` is the same test.
def rs_s1.go(+ar: O.Arena, +u: U32, is_const: Bool) -> String:
  Bool.pick(String, is_const,
            String.concat(["CONST(", String.concat([rs_cval(O.Arena.arg(ar, u)), ")"])]),
            String.concat([O.Ops.name.of(O.Arena.op(ar, u)), "/", U32.show(O.Arena.nsrc(ar, u))]))

def rs_s1(ar: O.Arena, +u: U32) -> String:
  +a = ar
  rs_s1.go(a, u, O.op_is(a, u, O.OpsCONST{}))

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

def rs_join2.add(first: Bool, +acc: String, +s: String) -> String:
  match first:
    case True{}: s
    case False{}: String.concat([acc, ",", s])

def rs_cone_sig(f: Nat, +ar: O.Arena, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match f:
    case 0n: rs_join.dash(first, acc)
    case 1n+q:
      match xs:
        case Nil{}: rs_join.dash(first, acc)
        case +h <> t:
          s = rs_join2.add(first, acc, rs_s1(ar, h))
          rs_cone_sig(q, ar, t, s, False{})

# `oi`'s two index lists. `-` for empty on BOTH sides, so an empty `outs` and an absent
# one are the same row -- which is what CPython's `()` prints.
# `-` FOR AN EMPTY LIST AND NOT `none`, and the difference is CPython's: realize.py:24-27
# answers `()` and `tuple(range(...))`, so an empty `outs` prints `-`. `rs_join.dash`'s
# `none` is the LIST drivers' spelling (`dst is None`), and reusing it here made ten `oi`
# rows read as divergences that were a dash.
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
# first new node, so `main_arena`'s index map (realize.bend:1373-1401) still reads true
# and the census cannot silently renumber the port's fixture. `O.UOp.new` returns the
# GROWN arena inside an `O.Found`, so each node chains on `O.Found.ar` of the last --
# handing back a bare index would be the stale-arena self-loop.
def rs_cpu() -> S.Dev:
  S.D1{0}

def rs_zf() -> O.PyRange:
  O.PyRange{H.i64_of_i32(0), H.i64_of_i32(4)}

def rs_buf(slot: U32, nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{16}, None{}, None{}, Some{nm}, S.AGlobal{},
             Some{rs_cpu()}, False{}, None{}, Some{0}, False{}, None{}}

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

# The 20 new nodes, in slot order 42..61. `main_arena` has no MSELECT, no GETADDR, no
# MSTACK, no SHRINK, no SINK without a KernelInfo, no PROGRAM whose kernel is unnamed and
# no MSELECT in an `outs` slot, so `rz_arm`'s MSELECT/SHRINK/MSTACK arms, HEAD's GETADDR
# arm, `gcc_sink`'s and `gcc_pick.prog`'s DEFAULT arms, `gn_prog`'s default arm and
# `get_call_written_bufs`'s MSELECT wall would ALL be unreachable rows without them.
#
# THE SRC LISTS ARE LITERAL INDICES, and that is the same invariant `main_arena` states
# for itself: node k is at index k because the ORDER of the `UOp.new` calls IS the arena.
# It holds only while every node here is DISTINCT -- `UOp.new` hash-conses, so a repeat
# would take no slot and renumber everything after it. `arena_n` is the guard: it reads
# 62, and a hash-consed node makes it 61 and takes the lane red.
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

# THE ARENA. `main_arena`'s 42 slots, index for index, plus the twenty above chained onto
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
  O.Found.ar(e63)

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
def rs_d_beam.go(+f: O.Found, fired: Bool) -> String:
  Bool.pick(String, fired,
            String.concat(["1:", String.concat([rs_cone_sig(rs_fuel(O.Found.ar(f)), O.Found.ar(f),
                                                            rs_cone(O.Found.ar(f), [O.Found.i(f)]),
                                                            "", True{})]),
                           ":b=", U32.show(RZ.rz_kernel_beam(O.Arena.arg(O.Found.ar(f),
                                                                          O.Arena.src(O.Found.ar(f), O.Found.i(f), 0))))]),
            "0")

def rs_d_flat(ar: O.Arena, +n: U32) -> String:
  +a = ar
  +v = RZ.flatten_rewrite(a, n)
  rs_d_flat.go(RZ.rz_lin_new(a, n), Bool.not(rs_vskip(v)))

def rs_d_val(ar: O.Arena, n: U32) -> String:
  rs_bl(RZ.va_claim(ar, n))

# THE VERDICT IS THE JUDGE **AND** THE ANSWER'S INDEX, and the second half is new since
# the `ret is not uop` fix. `RZ.beam_rewrite` is `realize.bend`'s JUDGE (it answers a
# `Verdict`, never a node) and `RZ.bm_new` is the BODY; CPython's `PatternMatcher.rewrite`
# returns the body's node or `None`, so a faithful driver asks BOTH: did the rule fire, and
# did it produce something other than the node it was handed? `bm_new` applies
# `M.hop_self` now, so "nothing" IS index 0 and the test is one comparison.
# MEASURED, the two contexts this driver exists for: at ctx 7 the answer is a NEW node on
# both sides and the two lanes agree byte for byte; at ctx 0 every replacement is the
# identity, the port now answers index 0 and so does CPython.
def rs_d_beam(ar: O.Arena, +n: U32, ctx: U32) -> String:
  +a = ar
  +v = RZ.beam_rewrite(a, n)
  +f = RZ.bm_new(a, n, ctx)
  rs_d_beam.go(f, Bool.and(Bool.not(rs_vskip(v)), U32.is_ne(O.Found.i(f), 0)))

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
# 2 header rows + 15 bottoms + 12 arm-coverage rows + 15 drivers x 61 nodes = 944.
def rs_prod() -> U32:
  U32.mul(U32.from_nat(rs_n()), U32.from_nat(rs_drv_n()))

def rs_cnt() -> U32:
  (U32.add(rs_prod(), U32.add(U32.from_nat(rs_drv_n()),
                              U32.add(U32.from_nat(rs_arms_n()), 2))))

# THE ARENA IS REBUILT ONCE PER SECTION, not once per row: the rows that GROW it
# (`res`, `var`, `flat`, `beam`, `bea0`) take a COPY and grow that, and the six readers
# that do not are read-only throughout. `decomp_graph_census.bend` rebuilds per row
# because EVERY `l2i` call grows; here that would be 915 arenas for no safety at all.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- rs_putl(rs_put("arena_n", U32.show(rs_arena_n(rs_arena()))))
    b : Unit <- rs_putl(rs_put("rows", U32.show(rs_cnt())))
    c : Unit <- rs_putl(rs_bottoms(rs_drv_n(), rs_arena(), 0, Nil{}))
    d : Unit <- rs_putl(rs_arms_go(rs_arms_n(), rs_arena(), 0, Nil{}))
    e : Unit <- rs_putl(rs_drvs_go(rs_drv_n(), rs_arena(), 0, Nil{}))
    return Unit{}