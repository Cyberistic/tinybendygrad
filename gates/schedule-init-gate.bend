# gates/schedule-init-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/__init__.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/schedule/__init__.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/codegen/__init__.bend as CG

def schedule_vars(+ar: O.Arena, +big_sink: U32, +linear: U32) -> P.SVar:
  +r = P.sv_kernels(P.sc_srcs(ar, linear), P.SVar{ar, Nil{}, Nil{}, False{}})
  P.sv_binds(P.sc_src_from(P.SVar.ar(r), big_sink, 1), r)


# --- THE GATE ROWS ------------------------------------------------------
#
# Three fixtures, built in the arena with the same construction ORDER as
# `.agents/slop/notes/sched-truth.py`, so every index below is that file's index
# and `fx*_nodes` says how many there are. `fx1` and `fx2` are the Python's;
# `fx3` is the nested-AFTER chain `sched-truth.py` builds for `buf_uop`, and
# `BAD` is an AFTER with a SINK source, which `_split_after` DROPS here and
# which Python raises on.
#
#   fx1     0 NOOP 1 C1  2 SPa  3 A1   4 SPb  5 B1   6 C0   7 ST1  8 BODY1
#          9 C2  10 ST2 11 BODY2 12 VB 13 K1 14 K2 15 E2 16 AF1 17 AF2 18 SINKA
#          19 TOP1 20 BAD            (so `fx1_nodes`=21 and `fx1_topo`=19)
#   THE TABLE IS A READING, NOT A CONTRACT.  It was written against the
#   substrate of 2026-10-07, whose `param_src` DROPPED the size CONST and the
#   PARAM's STACK (uop/ops.bend:3095 symbol=param_src); `UOp.new.param` interns BOTH
#   (uop/ops.bend:2774 symbol=UOp.new.param), so every index after the first PARAM moved and 18
#   rows were reading the WRONG NODE.  The rows no longer READ this table: they
#   read GRAPH POSITIONS (`fx1.a()`, `fx2.kb()`, ...), which cannot move.  The
#   three `fx*_nodes` rows are the only rows that still count arena slots, and
#   they are port-only bookkeeping.
#   fx2     1 C1  2 SPa  3 A2   4 SPx  5 X2   6 C0   7 ST1  8 BODY1  9 C2
#          10 ST2 11 BODY2 12 C3 13 ST3 14 BODY3 15 Ka 16 Kb 17 Kc 18 AFa 19 AFb
#          20 AFc 21 SINKA 22 TOP2
#   fx3     1 C1  2 SPa  3 A3   4 C0   5 C3   6 ST3  7 BODY3 8 K3 9 AG1 10 AG2
#          11 SINKA 12 TOP3 13 AG3 (AFTER(AG2, AG1), unreachable)
#   fx4     1 C1 2 SPa 3 A4 4 C0 5 C1 6 STAGE 7 MSTACK
#   fx5     1 C1  2 SPa  3 A5   4 C0   5 ST1  6 BODY1  7 C2   8 ST2  9 BODY2 10 Ka
#          11 AFa 12 Kb 13 AFb 14 SINKA 15 TOP5  (so `fx5_nodes`=16, `fx5_topo`=15)
#
# `Vu` and `BAD` are interned and NOT reachable from the sink, which is why
# `fx1_nodes` is 21 while `fx1_topo` is Python's 19.
# ===========================================================================
# `ParamArg(slot=0, dtype=int32, size=4, name='a', device='CPU')`. The port
# interned device NAMES as `S.D1{tag}`, and tag 0 stands for CPU.
def g_pb(+slot: U32, +nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, Some{nm}, S.AGlobal{},
    Some{S.D1{0}}, False{}, None{}, None{}, False{}, None{}}

# `UOp.variable("v", 0, 10, dtype=int32)` and `.bind(3)`. The slot is `None` in
# Python's `-1`; nothing in this file reads a slot, so it is 0 here.
def g_pv(+nm: String, val: Maybe<&2, O.Const>) -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(10)}},
    Some{1}, Some{nm}, S.Aalu{}, None{}, False{}, None{}, None{}, False{}, val}

# `UOp._buffer` (ops.py:831) is `src=(shape_to_shape_arg((size,)),)+device_range_src(device)`,
# and `device_range_src` (:829) is `()` for a SINGLE STRING device -- so a BUFFER's src is ONE
# CONST and THERE IS NO SPECIAL. MEASURED 2026-11-03 by `gates/schedsched-oracle.py`: the
# SPECIAL form gave a gated toposort of `CONST SPECIAL BUFFER ...` where CPython's own `_buffer`
# gives `CONST BUFFER ...`, and every `fx*_topo` row moved by one. This comment used to describe
# the SPECIAL form, which the code never built, and the oracle was written to match the COMMENT
# rather than the code. The bare SPECIAL it also minted was a DEAD NODE in every fixture.
def g_buf(+slot: U32, +nm: String, ar: O.Arena) -> O.Found:
  O.UOp.new.param(ar, O.OpsBUFFER{}, Some{4}, O.AParam{g_pb(slot, nm)}, O.TNone{})

# `UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(UOp.const(0), UOp.const(n))),))`
def g_body(+n: U32, ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +cn = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(n)})
  +st = O.UOp.new(O.Found.ar(cn), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(cn)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])

# fx1: A1 <- K1, then AF1(AFTER(A1,K1)), AF2(AFTER(AF1, E2(K2))) where
# K2 = CALL(body(2), B1, v-bound-3), and TOP1 = SINK(AF2, SINK(A1)).
def fx1() -> O.Found:
  +a = g_buf(0, "a", O.Arena.empty())
  +b = g_buf(1, "b", O.Found.ar(a))
  +d1 = g_body(1, O.Found.ar(b))
  +d2 = g_body(2, O.Found.ar(d1))
  +vb = O.UOp.new.param(O.Found.ar(d2), O.OpsPARAM{}, None{}, O.AParam{g_pv("v", Some{O.CInt{H.i64_of_i32(3)}})}, O.TNone{})
  +k1 = O.UOp.new(O.Found.ar(vb), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +k2 = O.UOp.new(O.Found.ar(k1), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(b), O.Found.i(vb)], O.ANone{}, O.TNone{})
  +e2 = O.UOp.new(O.Found.ar(k2), O.OpsEND{}, [O.Found.i(k2)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(e2), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k1)], O.ANone{}, O.TNone{})
  +f2 = O.UOp.new(O.Found.ar(f1), O.OpsAFTER{}, [O.Found.i(f1), O.Found.i(e2)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(f2), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(f2), O.Found.i(sa)])

# fx2: three kernels on TWO states, A2 written twice. Ka and Kb both write A2, so
# Kb READS the state AFa superseded and Ka must run AFTER it -- the WAR edge.
def fx2() -> O.Found:
  +a = g_buf(0, "a2", O.Arena.empty())
  +x = g_buf(1, "x2", O.Found.ar(a))
  +d1 = g_body(1, O.Found.ar(x))
  +d2 = g_body(2, O.Found.ar(d1))
  +d3 = g_body(3, O.Found.ar(d2))
  +ka = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +kb = O.UOp.new(O.Found.ar(ka), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(a)], O.ANone{}, O.TNone{})
  +kc = O.UOp.new(O.Found.ar(kb), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(x)], O.ANone{}, O.TNone{})
  +fa = O.UOp.new(O.Found.ar(kc), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(ka)], O.ANone{}, O.TNone{})
  +fb = O.UOp.new(O.Found.ar(fa), O.OpsAFTER{}, [O.Found.i(fa), O.Found.i(kb)], O.ANone{}, O.TNone{})
  +fc = O.UOp.new(O.Found.ar(fb), O.OpsAFTER{}, [O.Found.i(x), O.Found.i(kc)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(fc), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(fb), O.Found.i(fc), O.Found.i(sa)])

# fx3: AG1(AFTER(A3,K3)), AG2(AFTER(AG1,K3)) -- the nested AFTER chain, and the
# `AFTER(AFTER(...))` case `sched-truth.py` builds for `buf_uop`.
def fx3() -> O.Found:
  +a = g_buf(0, "a3", O.Arena.empty())
  +d3 = g_body(3, O.Found.ar(a))
  +k3 = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(a)], O.ANone{}, O.TNone{})
  +g1 = O.UOp.new(O.Found.ar(k3), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k3)], O.ANone{}, O.TNone{})
  +g2 = O.UOp.new(O.Found.ar(g1), O.OpsAFTER{}, [O.Found.i(g1), O.Found.i(k3)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(g2), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(g2), O.Found.i(sa)])

# fx5: the RAW-dep path and the backward-slice suppression, which no other fixture
# reaches. `Kb` reads BOTH A5 and `AFa`, so `AFa` is a read state that is an AFTER
# and `Ka = AFa`'s kernel becomes a RAW producer of `Kb` (__init__.py:52-56). And
# because `Kb` reads `AFa`, `Ka` is in `Kb.backward_slice`, so the WAR candidate
# (Kb, Ka) that A5's write proposes is SUPPRESSED (__init__.py:63) -- drop that
# test and `in_degree` never reaches zero and nothing is linearized at all.
def fx5() -> O.Found:
  +a = g_buf(0, "a5", O.Arena.empty())
  +d1 = g_body(1, O.Found.ar(a))
  +d2 = g_body(2, O.Found.ar(d1))
  +ka = O.UOp.new(O.Found.ar(d2), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +fa = O.UOp.new(O.Found.ar(ka), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(ka)], O.ANone{}, O.TNone{})
  +kb = O.UOp.new(O.Found.ar(fa), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(a), O.Found.i(fa)], O.ANone{}, O.TNone{})
  +fb = O.UOp.new(O.Found.ar(kb), O.OpsAFTER{}, [O.Found.i(fa), O.Found.i(kb)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(fb), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(fb), O.Found.i(sa)])

# fx4: the two ops that `buf_uop`'s stop set adds to `{BUFFER, ALLOC, PARAM}` and
# that no other fixture has. `MSTACK(a, a)` is Python's `UOp(Ops.MSTACK, src=(a,
# a))` and `STAGE(c0, c1)` its two-source form.
def fx4() -> O.Found:
  +a = g_buf(0, "a4", O.Arena.empty())
  +c0 = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  +st = O.UOp.new(O.Found.ar(c1), O.OpsSTAGE{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(st), O.OpsMSTACK{}, [O.Found.i(a), O.Found.i(a)], O.ANone{}, O.TNone{})

# ===========================================================================
# THE fixture addresses.  A node is named by its PLACE in the graph and NEVER
# by its arena index.
#
# WHY, MEASURED.  The arena is a MOVING TARGET: `UOp.new.param` interns the
# shape node that the old `param_src` DROPPED (uop/ops.bend:3086 symbol=param_src
# and uop/ops.bend:2774 symbol=UOp.new.param), so one substrate change moved every index after the first
# PARAM.  The port's rows were ADDRESSED by index and 18 of them went on
# reading the WRONG NODE -- `unwrap_A1` answered 9 (a CONST) where CPython
# answers 1 (a BUFFER) -- and the gate did not see it because its CPython
# oracle is gone (see the header).  A graph position cannot move.
#
# The addresses below are therefore DERIVED, and every row that used an index
# now reads a name.  `fx1.bad` and `fx3.after_after` intern ONE node into the
# fixture's arena, so their srcs are addresses in THAT arena -- and they are
# derived the same way.
# ===========================================================================
def fx1.ar() -> O.Arena: O.Found.ar(fx1())
def fx1.top() -> U32: O.Found.i(fx1())
def fx2.ar() -> O.Arena: O.Found.ar(fx2())
def fx2.top() -> U32: O.Found.i(fx2())
def fx3.ar() -> O.Arena: O.Found.ar(fx3())
def fx3.top() -> U32: O.Found.i(fx3())
def fx5.ar() -> O.Arena: O.Found.ar(fx5())
def fx5.top() -> U32: O.Found.i(fx5())
def fx4.ar() -> O.Arena: O.Found.ar(fx4())
def fx4.ms() -> U32: O.Found.i(fx4())

# fx1: TOP = SINK(AF2, SA); AF2 = AFTER(AF1, E2); AF1 = AFTER(A1, K1);
# E2 = END(K2); K1 = CALL(body1, A1); K2 = CALL(body2, B1, VB).
def fx1.af2() -> U32: P.sc_src0(fx1.ar(), fx1.top())
def fx1.sa() -> U32: P.sc_src(fx1.ar(), fx1.top(), 1)
def fx1.af1() -> U32: P.sc_src0(fx1.ar(), fx1.af2())
def fx1.e2() -> U32: P.sc_src(fx1.ar(), fx1.af2(), 1)
def fx1.a() -> U32: P.sc_src0(fx1.ar(), fx1.af1())
def fx1.k1() -> U32: P.sc_src(fx1.ar(), fx1.af1(), 1)
def fx1.k2() -> U32: P.sc_src0(fx1.ar(), fx1.e2())
def fx1.b() -> U32: P.sc_src(fx1.ar(), fx1.k2(), 1)
def fx1.vb() -> U32: P.sc_src(fx1.ar(), fx1.k2(), 2)

# fx2: TOP = SINK(AFB, AFC, SA); AFB = AFTER(AFa, KB); AFC = AFTER(X, KC);
# AFa = AFTER(A, KA).
def fx2.afb() -> U32: P.sc_src0(fx2.ar(), fx2.top())
def fx2.afc() -> U32: P.sc_src(fx2.ar(), fx2.top(), 1)
def fx2.fa() -> U32: P.sc_src0(fx2.ar(), fx2.afb())
def fx2.kb() -> U32: P.sc_src(fx2.ar(), fx2.afb(), 1)
def fx2.ka() -> U32: P.sc_src(fx2.ar(), fx2.fa(), 1)

# fx3: TOP = SINK(AG2, SA); AG2 = AFTER(AG1, K3); AG1 = AFTER(A3, K3).
def fx3.ag2() -> U32: P.sc_src0(fx3.ar(), fx3.top())
def fx3.ag1() -> U32: P.sc_src0(fx3.ar(), fx3.ag2())

# fx5: TOP = SINK(AFb, SA); AFb = AFTER(AFa, KB); AFa = AFTER(A5, KA).
def fx5.afb() -> U32: P.sc_src0(fx5.ar(), fx5.top())
def fx5.afa() -> U32: P.sc_src0(fx5.ar(), fx5.afb())
def fx5.kb() -> U32: P.sc_src(fx5.ar(), fx5.afb(), 1)
def fx5.ka() -> U32: P.sc_src(fx5.ar(), fx5.afa(), 1)

# `UOp(Ops.AFTER, src=(A1, K1, UOp(Ops.SINK, src=(A1,))))` -- the AFTER whose
# third source `_split_after` DROPS here and which Python raises on. Interned in
# fx1's arena and deliberately NOT reachable from the sink. The srcs are graph
# positions, not arena indices: `fx1.a()`, `fx1.k1()`, `fx1.sa()`.
def fx1.bad() -> O.Found:
  O.UOp.new(O.Found.ar(fx1()), O.OpsAFTER{}, [fx1.a(), fx1.k1(), fx1.sa()], O.ANone{}, O.TNone{})

# BAD's arena -- one node longer than `fx1.ar()`, because BAD is interned into it.
def fx1.arb() -> O.Arena: O.Found.ar(fx1.bad())

# `fx3.after_after` -- an AFTER whose SECOND source is an AFTER, so `_split_after`
#'s dep half is exercised. Interned in fx3's arena, not reachable from the sink.
def fx3.after_after() -> O.Found:
  O.UOp.new(O.Found.ar(fx3()), O.OpsAFTER{}, [fx3.ag2(), fx3.ag1()], O.ANone{}, O.TNone{})

def fx3.arb() -> O.Arena: O.Found.ar(fx3.after_after())
def fx3.aa() -> U32: O.Found.i(fx3.after_after())

# THE UNBOUND VARIABLE.  `Vu` was interned in fx1's arena and NOT reachable
# from the sink, so it had no graph position -- and an arena index is exactly
# the thing this section removes.  It is built HERE, by the SAME constructor
# the fixture used (`g_pv("v", None{})`), in its own arena, and the row asks
# its question there.  The ANSWER is the same question: is an unbound
# variable a bound one?
def fx1.vu() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, None{}, O.AParam{g_pv("v", None{})}, O.TNone{})

# THE STAGE of fx4 is the other unreachable node, and it gets the same
# treatment: built by itself, in its own arena.
def fx4.st() -> O.Found:
  +a = g_buf(0, "a4b", O.Arena.empty())
  +c0 = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTAGE{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

# ===========================================================================
# THE edge fixtures.  THE three the schedule can meet, AND two witnesses.
#
# fx0 EMPTY.  A sink with no AFTERs at all.  CPython answers a LINEAR with NO
# srcs and NO error: `create_schedule` on an empty schedule is a schedule of
# zero kernels, and a port that treats it as an error fails a real input.
#
# fx7 THE `src_without_body` WITNESS.  An AFTER that lives ONLY inside a CALL's
# body -- the shape an INLINE call has (ops.py:547: `self.body.op is Ops.SINK
# and self.body.arg is None`, so the body's SINK carries NO KernelInfo and the
# GATE cannot exclude it).  CPython's toposort never descends into a CALL's
# body, so it schedules ONE kernel; a port that walks all srcs schedules TWO.
# An extra kernel is a REORDER.
#
# fx8 THE `gate_kernel_sink` WITNESS.  A SINK whose arg IS a KernelInfo --
# which is what a kernel body is.  CPython's gate REJECTS it, so the subtree
# under it is never visited and its kernel is NEVER scheduled: zero kernels.
# A port whose gate says True for every SINK schedules one.
# ===========================================================================
def fx0() -> O.Found:
  O.UOp.sink(O.Arena.empty(), Nil{})

def fx7() -> O.Found:
  +a = g_buf(0, "a7", O.Arena.empty())
  +a2 = g_buf(1, "a7b", O.Found.ar(a))
  +d1 = g_body(1, O.Found.ar(a2))
  +d3 = g_body(3, O.Found.ar(d1))
  +k1 = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(k1), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k1)], O.ANone{}, O.TNone{})
  +k3 = O.UOp.new(O.Found.ar(f1), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(a2)], O.ANone{}, O.TNone{})
  +g = O.UOp.new(O.Found.ar(k3), O.OpsAFTER{}, [O.Found.i(a2), O.Found.i(k3)], O.ANone{}, O.TNone{})
  +body2 = O.UOp.sink(O.Found.ar(g), [O.Found.i(g)])
  +k2 = O.UOp.new(O.Found.ar(body2), O.OpsCALL{}, [O.Found.i(body2), O.Found.i(a2)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(k2), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(f1), O.Found.i(k2), O.Found.i(sa)])

def fx8() -> O.Found:
  +a = g_buf(0, "a8", O.Arena.empty())
  +d1 = g_body(1, O.Found.ar(a))
  +k1 = O.UOp.new(O.Found.ar(d1), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(k1), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k1)], O.ANone{}, O.TNone{})
  +kin = O.UOp.new(O.Found.ar(f1), O.OpsSINK{}, [O.Found.i(f1)], O.AKernel{O.KernelInfo.of()}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(kin), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(kin), O.Found.i(sa)])

# fx9 THE `sc_kdeps.of` END WITNESS.  `create_schedule` reads a kernel's BUFFER DEPS off
# `k.src[0].src[1:]` when `k` is an END (`__init__.py:47`, because an END wraps a CALL and
# the CALL holds the srcs), and off `k.src[1:]` otherwise.  The two arms are ONE line apart and
# until this fixture NO row told them apart: MEASURED 2026-11-03, replacing the END arm with
# `P.sc_src_from(ar, k, 1)` -- the END's own srcs, which is empty -- moved ZERO rows out of 111.
#
# The shape that separates them needs an END whose kernel READS a state that a LATER write
# supersedes, where the writing kernel is NOT already in the END's backward slice.  Then the WAR
# pass is the only thing that can order them: `writes[b] = [(fb, (kb,))]` and `reads` contains
# `(ge, ey, b)` only if the END arm found `b`.  So the CORRECT arm makes `kb` run AFTER `ey`
# (marks 3 then 2 -> 32) and the broken arm lets the queue seed in insertion order, `kb` first
# (marks 2 then 3 -> 23).  THE LINEARIZATION ORDER IS THE ROW.
def fx9() -> O.Found:
  +b = g_buf(0, "b9", O.Arena.empty())
  +d2 = g_body(2, O.Found.ar(b))
  +d3 = g_body(3, O.Found.ar(d2))
  +kb = O.UOp.new(O.Found.ar(d3), O.OpsCALL{}, [O.Found.i(d2), O.Found.i(b)], O.ANone{}, O.TNone{})
  +fb = O.UOp.new(O.Found.ar(kb), O.OpsAFTER{}, [O.Found.i(b), O.Found.i(kb)], O.ANone{}, O.TNone{})
  +ky = O.UOp.new(O.Found.ar(fb), O.OpsCALL{}, [O.Found.i(d3), O.Found.i(b)], O.ANone{}, O.TNone{})
  +ey = O.UOp.new(O.Found.ar(ky), O.OpsEND{}, [O.Found.i(ky)], O.ANone{}, O.TNone{})
  +ge = O.UOp.new(O.Found.ar(ey), O.OpsAFTER{}, [O.Found.i(fb), O.Found.i(ey)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(ge), [O.Found.i(b)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(ge), O.Found.i(sa)])

# fx10 THE `sc_gate.of` LINEAR WITNESS.  `gate_kernel_sink` rejects a LINEAR (`ops.py:1916`), so
# a LINEAR reachable from the sink STOPS the walk and its whole subtree is never scheduled: zero
# kernels.  MEASURED 2026-11-03: flipping that arm to `True{}` moved ZERO rows out of 111,
# because no fixture had a LINEAR in the walk.  This one does -- and it is the third member of
# the same family as fx8 (the KernelInfo SINK): a node the gate must REFUSE.
def fx10() -> O.Found:
  +a = g_buf(0, "a10", O.Arena.empty())
  +d1 = g_body(1, O.Found.ar(a))
  +k1 = O.UOp.new(O.Found.ar(d1), O.OpsCALL{}, [O.Found.i(d1), O.Found.i(a)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(k1), O.OpsAFTER{}, [O.Found.i(a), O.Found.i(k1)], O.ANone{}, O.TNone{})
  +ln = O.UOp.new(O.Found.ar(f1), O.OpsLINEAR{}, [O.Found.i(f1)], O.ANone{}, O.TNone{})
  +sa = O.UOp.sink(O.Found.ar(ln), [O.Found.i(a)])
  O.UOp.sink(O.Found.ar(sa), [O.Found.i(ln), O.Found.i(sa)])

# fx11/fx12 THE `schedule_vars` FIXTURES -- `used_vars` and `var_vals`, `__init__.py:279-291`.
#
# `big_sink.src[0]` IS `lin` HERE AND NOT A SINK, and that is deliberate: upstream's
# `big_sink` is a CALL whose `src[0]` is the tensor-graph SINK, and `schedule_vars` reads
# ONLY `src[1:]` -- so wiring `src[0]` to the LINEAR is what makes the LINEAR reachable from
# ONE fixture entry point without `schedule_vars` ever looking at it.
#
# fx11 has FOUR bound vars in `src[1:]` and TWO names in the schedule: `v`=3 and `w`=2 are
# read by the kernel body, `u`=5 is not, and `w`=2 appears a SECOND time with the SAME value.
# So one fixture answers three questions: `v` and `w` LAND, `u` is SKIPPED, and a repeat bind
# with an equal value is NOT a mismatch -- which is what separates
# `var_vals.get(nm, val) != val` from `nm in var_vals`.
def sv_var(+ar: O.Arena, nm: String, val: U32) -> O.Found:
  O.UOp.new.param(ar, O.OpsPARAM{}, None{}, O.AParam{g_pv(nm, Some{O.CInt{H.i64_of_i32(val)}})}, O.TNone{})

def sv_body(+ar: O.Arena, +vb: U32, +vw: U32) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +sm = O.UOp.alu(O.Found.ar(c0), O.OpsADD{}, [vb, vw])
  +st = O.UOp.new(O.Found.ar(sm), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(sm)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])

def svfx_ok() -> O.Found:
  +vb = sv_var(O.Arena.empty(), "v", 3)
  +vw = sv_var(O.Found.ar(vb), "w", 2)
  +vu = sv_var(O.Found.ar(vw), "u", 5)
  +w2 = sv_var(O.Found.ar(vu), "w", 2)
  +b = g_buf(0, "sb", O.Found.ar(w2))
  +bd = sv_body(O.Found.ar(b), O.Found.i(vb), O.Found.i(vw))
  +k1 = O.UOp.new(O.Found.ar(bd), O.OpsCALL{}, [O.Found.i(bd), O.Found.i(b)], O.ANone{}, O.TNone{})
  +lin = O.UOp.new(O.Found.ar(k1), O.OpsLINEAR{}, [O.Found.i(k1)], O.ANone{}, O.TNone{})
  # THE last SRC IS a bound-LOOKING variable that is not bound, AND it is named `v` ON
  # PURPOSE: `if b.is_bound_var` is the loop's FIRST test, and an unbound `u` would be
  # skipped by `not in used_vars` too, so it would be a src that no row could tell apart
  # from an absent one. Named `v`, breaking that test OVERWRITES the answer `v`=3 and sets
  # `bad` -- two rows red from one src.
  # `O.Found.ar(lin)` AND NOT `O.Found.ar(w2)`: `nv` mints, and an arena is a VALUE, so
  # building it from the SMALLER arena `w2` left it holding `next=8` while `lin` sits at
  # index 12 -- MEASURED, `bs.src0` read `12:NOOP`, and every `sv_ok_*` row answered 0 for a
  # reason that had nothing to do with `schedule_vars`. THE FIFTH TIME THIS SESSION.
  +nv = O.UOp.new.param(O.Found.ar(lin), O.OpsPARAM{}, None{}, O.AParam{g_pv("v", None{})}, O.TNone{})
  +bs = O.UOp.new(O.Found.ar(nv), O.OpsCALL{},
    [O.Found.i(lin), O.Found.i(vb), O.Found.i(vu), O.Found.i(vw), O.Found.i(w2), O.Found.i(nv)],
    O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(bs), [O.Found.i(bs)])

# fx12 is the MISMATCH: one name, two values. Python RAISES here and a raise cannot be a row,
# so the port carries `bad` and the row is that flag.
def svfx_bad() -> O.Found:
  +vb = sv_var(O.Arena.empty(), "v", 3)
  +v7 = sv_var(O.Found.ar(vb), "v", 7)
  +b = g_buf(0, "sb2", O.Found.ar(v7))
  +bd = sv_body(O.Found.ar(b), O.Found.i(vb), O.Found.i(vb))
  +k1 = O.UOp.new(O.Found.ar(bd), O.OpsCALL{}, [O.Found.i(bd), O.Found.i(b)], O.ANone{}, O.TNone{})
  +lin = O.UOp.new(O.Found.ar(k1), O.OpsLINEAR{}, [O.Found.i(k1)], O.ANone{}, O.TNone{})
  +bs = O.UOp.new(O.Found.ar(lin), O.OpsCALL{},
    [O.Found.i(lin), O.Found.i(vb), O.Found.i(v7)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(bs), [O.Found.i(bs)])

# `r = r * 10 + x`, and `mark` is `k.src[0].src[0].src[1].val` -- the STORE's
# value CONST. `H` has `i32 -> i64` and no way back, so the DIGIT is picked by
# equality; the fixture only ever stores 1, 2 or 3.
def gate.digit.pick(hit: Bool, acc: U32, n: U32) -> U32:
  match hit:
    case True{} : n
    case False{}: acc

def gate.digit(+i: H.I64) -> U32:
  gate.digit.pick(O.eq_i64(i, H.i64_of_i32(1)),
    gate.digit.pick(O.eq_i64(i, H.i64_of_i32(2)),
      gate.digit.pick(O.eq_i64(i, H.i64_of_i32(3)), 0, 3), 2), 1)

def gate.val.c(c: O.Const) -> H.I64:
  match c:
    case O.CInt{i}: i
    case _         : H.i64_of_i32(0)

# the CONST's arg is `APy{Const}`, so the `.val` is one `match` deeper than the
# node read above it.
def gate.val(arg: O.Arg) -> H.I64:
  match arg:
    case O.APy{c}: gate.val.c(c)
    case _        : H.i64_of_i32(0)

def gate.mark(+ar: O.Arena, k: U32) -> U32:
  gate.digit(gate.val(P.sc_arg(ar, P.sc_src(ar, P.sc_src0(ar, P.sc_src0(ar, k)), 1))))
def gate.marks.go(ks: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ks:
    case Nil{}     : acc
    case k <> rest : gate.marks.go(rest, ar, U32.add(U32.mul(acc, 10), gate.mark(ar, k)))


def gate.marks(+ar: O.Arena, ks: List<&2, U32>) -> U32:
  gate.marks.go(ks, ar, 0)
# the length of `P.Split`'s two halves, for the `_split_after` rows
def gate.ks(+ar: O.Arena, a: U32) -> U32:
  U32.from_nat(List.length(&2, U32, P.Split.ks(P.sc_split(ar, a))))

def gate.ds(+ar: O.Arena, a: U32) -> U32:
  U32.from_nat(List.length(&2, U32, P.Split.ds(P.sc_split(ar, a))))

# the TOTAL child edges, which is one for fx2 and zero for fx1 -- the edge the
# WAR pass added and the one the linearization turns on.
def kids_n.go(+ks: List<&2, P.Kid>, acc: U32) -> U32:
  match ks:
    case Nil{}           : acc
    case P.Kid{k, vs} <> t : kids_n.go(t, U32.add(acc, U32.from_nat(List.length(&2, U32, vs))))

def kids_n(c: P.Ctx) -> U32:
  kids_n.go(P.Ctx.kids(c), 0)

def b2u(b: Bool) -> U32:
  match b:
    case True{} : 1
    case False{}: 0

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ===========================================================================
# THE ROWS. Every expectation below is `sched-truth.py`'s printed output, and the
# comment over each block is that output.
# ===========================================================================
def t_unwrap_A1() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_unwrap(fx1.ar(), fx1.a())))
def t_unwrap_B1() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_unwrap(fx1.ar(), fx1.b())))
def t_unwrap_Vb() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_unwrap(fx1.ar(), fx1.vb())))
def t_unwrap_AF1() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_unwrap(fx1.ar(), fx1.af1())))
def t_unwrap_AF2() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_unwrap(fx1.ar(), fx1.af2())))
def t_unwrap_bad() -> U32: P.gate.code(P.sc_op(fx1.arb(), P.sc_unwrap(fx1.arb(), O.Found.i(fx1.bad()))))

# sched-truth.py: `split_A1 ks=0 ds=0` .. `split_AG2 ks=1 ds=0` and
# `split_bad RAISED`. BAD's sources are K1 (a CALL) and a SINK, so the kernels
# half is 1 and the SINK is DROPPED where Python raises -- `split_bad_ks` pins
# the drop, and `split_AF2_ds=0` pins the AFTER half of a real one.
def t_split_A1() -> U32: gate.ks(fx1.ar(), fx1.a())
def t_split_AF1() -> U32: gate.ks(fx1.ar(), fx1.af1())
def t_split_AF2() -> U32: gate.ks(fx1.ar(), fx1.af2())
def t_split_AG1() -> U32: gate.ks(fx3.ar(), fx3.ag1())
def t_split_AG2() -> U32: gate.ks(fx3.ar(), fx3.ag2())
def t_split_bad() -> U32: gate.ks(fx1.arb(), O.Found.i(fx1.bad()))
def t_split_AF2_ds() -> U32: gate.ds(fx1.ar(), fx1.af2())

# `states_A1 1 ['BUFFER']`, `states_AF2 1 ['AFTER']`, `states_AG2 1 ['AFTER']`
def t_states_A1() -> U32: U32.from_nat(List.length(&2, U32, P.sc_states(P.sc_fuel(fx1.ar()), fx1.ar(), fx1.a())))
def t_states_AF2() -> U32: U32.from_nat(List.length(&2, U32, P.sc_states(P.sc_fuel(fx1.ar()), fx1.ar(), fx1.af2())))
def t_states_AG2() -> U32: U32.from_nat(List.length(&2, U32, P.sc_states(P.sc_fuel(fx3.ar()), fx3.ar(), fx3.ag2())))

# `bufuop_A1 1 bufuop_AF1 1 bufuop_AF2 1 / bufuop_AG1 1 bufuop_AG2 1 bufuop_Vb 3`
def t_bu_A1() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_buf_uop(fx1.ar(), fx1.a())))
def t_bu_AF1() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_buf_uop(fx1.ar(), fx1.af1())))
def t_bu_AF2() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_buf_uop(fx1.ar(), fx1.af2())))
def t_bu_Vb() -> U32: P.gate.code(P.sc_op(fx1.ar(), P.sc_buf_uop(fx1.ar(), fx1.vb())))
def t_bu_AG1() -> U32: P.gate.code(P.sc_op(fx3.ar(), P.sc_buf_uop(fx3.ar(), fx3.ag1())))
def t_bu_AG2() -> U32: P.gate.code(P.sc_op(fx3.ar(), P.sc_buf_uop(fx3.ar(), fx3.ag2())))

# `bv_Vb 1 bv_Vu 0 bv_A1 0` -- and the bound var is a CALL's src[2]
def t_bv_Vb() -> U32: b2u(P.sc_is_bound_var(fx1.ar(), fx1.vb()))
def t_bv_Vu() -> U32: b2u(P.sc_is_bound_var(O.Found.ar(fx1.vu()), O.Found.i(fx1.vu())))
def t_bv_A1() -> U32: b2u(P.sc_is_bound_var(fx1.ar(), fx1.a()))
def t_bv_K2src2() -> U32: b2u(P.sc_is_bound_var(fx1.ar(), P.sc_src(fx1.ar(), fx1.k2(), 2)))

# `bs_K2_K1 0 bs_E2_K2 1 bs_K1_K2 0 bs_Kb_Ka 0`
def t_bs_K2_K1() -> U32: b2u(P.sc_in_bs(fx1.ar(), fx1.k2(), fx1.k1()))
def t_bs_E2_K2() -> U32: b2u(P.sc_in_bs(fx1.ar(), fx1.e2(), fx1.k2()))
def t_bs_K1_K2() -> U32: b2u(P.sc_in_bs(fx1.ar(), fx1.k1(), fx1.k2()))
def t_bs_Kb_Ka() -> U32: b2u(P.sc_in_bs(fx2.ar(), fx2.kb(), fx2.ka()))

# fx1: `topo_n 19 lin_n 2 lin_op LINEAR / marks 12 nsrcs 22 /
#        lin_src_ops [['SINK','BUFFER'],['SINK','BUFFER']]`
# fx2: `topo_n 22 lin_n 3 lin_op LINEAR / marks 231 nsrcs 222`
def t_fx1_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx1.ar()), fx1.ar(), fx1.top())))
def t_fx2_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx2.ar()), fx2.ar(), fx2.top())))
def t_fx1_nodes() -> U32: O.Arena.next(fx1.ar())
def t_fx2_nodes() -> U32: O.Arena.next(fx2.ar())

# THE ARENA IS `P.Lin.ar`, NOT `fx1.ar()`: `k.replace(src=...)` interned the
# linearized kernels, so they live at indices past `fx1.ar()`'s end and reading
# them from the fixture's arena answers the bottom node (code 99). `lin_n` is the
# only row here that does not need it, because it is a length.
def t_fx1.lin.of(+l: P.Lin) -> U32:
  U32.from_nat(List.length(&2, U32, P.Lin.out(l)))

def t_fx2.lin.of(+l: P.Lin) -> U32:
  U32.from_nat(List.length(&2, U32, P.Lin.out(l)))

def t_fx1.lin.op(+f: O.Found) -> U32:
  P.gate.code(P.sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx2.lin.op(+f: O.Found) -> U32:
  P.gate.code(P.sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx1.lin.marks(+l: P.Lin) -> U32:
  gate.marks(P.Lin.ar(l), P.Lin.out(l))

def t_fx2.lin.marks(+l: P.Lin) -> U32:
  gate.marks(P.Lin.ar(l), P.Lin.out(l))

def t_fx1.lin.nsrcs(+l: P.Lin) -> U32:
  P.gate.nsrcs(P.Lin.ar(l), P.Lin.out(l))

def t_fx2.lin.nsrcs(+l: P.Lin) -> U32:
  P.gate.nsrcs(P.Lin.ar(l), P.Lin.out(l))

def t_fx1.lin.ops(+l: P.Lin) -> U32:
  P.gate.ops(P.Lin.ar(l), P.Lin.out(l))

def t_fx2.lin.ops(+l: P.Lin) -> U32:
  P.gate.ops(P.Lin.ar(l), P.Lin.out(l))

def t_fx1_lin_op() -> U32: t_fx1.lin.op(P.linear(P.schedule(fx1.ar(), fx1.top())))
def t_fx2_lin_op() -> U32: t_fx2.lin.op(P.linear(P.schedule(fx2.ar(), fx2.top())))
def t_fx1_marks() -> U32: t_fx1.lin.marks(P.schedule(fx1.ar(), fx1.top()))
def t_fx2_marks() -> U32: t_fx2.lin.marks(P.schedule(fx2.ar(), fx2.top()))
def t_fx1_nsrcs() -> U32: t_fx1.lin.nsrcs(P.schedule(fx1.ar(), fx1.top()))
def t_fx2_nsrcs() -> U32: t_fx2.lin.nsrcs(P.schedule(fx2.ar(), fx2.top()))
def t_fx1_ops() -> U32: t_fx1.lin.ops(P.schedule(fx1.ar(), fx1.top()))
def t_fx2_ops() -> U32: t_fx2.lin.ops(P.schedule(fx2.ar(), fx2.top()))
def t_fx1_lin_n() -> U32: t_fx1.lin.of(P.schedule(fx1.ar(), fx1.top()))
def t_fx2_lin_n() -> U32: t_fx2.lin.of(P.schedule(fx2.ar(), fx2.top()))


# `_split_after`'s DEP half: `AG2` is `AFTER(AG1, K3)`, so its sources are a
# kernel; `AG3` is `AFTER(AG2, AG1)`, so its sources are an AFTER, and Python's
# partition puts AG1 in `deps` and nothing in `kernels`.
def t_split_AG3_ks() -> U32: gate.ks(fx3.arb(), fx3.aa())
def t_split_AG3_ds() -> U32: gate.ds(fx3.arb(), fx3.aa())

# `buf_uop` on the two ops its stop set adds. With the wider stop set the walk
# answers the node itself; without it the walk descends to the BUFFER and both
# print 1.
def t_bu_STAGE() -> U32: P.gate.code(P.sc_op(O.Found.ar(fx4.st()), P.sc_buf_uop(O.Found.ar(fx4.st()), O.Found.i(fx4.st()))))
def t_bu_MSTACK() -> U32: P.gate.code(P.sc_op(fx4.ar(), P.sc_buf_uop(fx4.ar(), fx4.ms())))

# THE count rows. THE writes' KERNEL lists, summed: fx1 1+1, fx2 1+1+1, fx3 1+0.
# fx3's zero is the `prev_kernels` filter -- `AG2 = AFTER(AG1, K3)` and K3 is
# already a kernel of AG1, so AG2 supersedes nothing new -- and `COUNT_fx3_wrks`
# is the only row in the file that sees that filter.
def wrks_n.go(+ws: List<&2, P.Wrt>, acc: U32) -> U32:
  match ws:
    case Nil{}           : acc
    case P.Wrt{a, ks} <> t : wrks_n.go(t, U32.add(acc, U32.from_nat(List.length(&2, U32, ks))))

def wrks_n.go2(+ws: List<&2, P.Wrn>, acc: U32) -> U32:
  match ws:
    case Nil{}           : acc
    case P.Wrn{s, vs} <> t : wrks_n.go2(t, wrks_n.go(vs, acc))

def wrks_n(c: P.Ctx) -> U32:
  wrks_n.go2(P.Ctx.wrns(c), 0)

def t_fx3_wrns() -> U32: U32.from_nat(List.length(&2, P.Wrn, P.Ctx.wrns(P.pass2(fx3.ar(), P.pass1(fx3.ar(), fx3.top())))))
def t_fx3_wrks() -> U32: wrks_n(P.pass2(fx3.ar(), P.pass1(fx3.ar(), fx3.top())))

def t_fx3.lin.marks(+l: P.Lin) -> U32:
  gate.marks(P.Lin.ar(l), P.Lin.out(l))

def t_fx3.lin.of(+l: P.Lin) -> U32:
  U32.from_nat(List.length(&2, U32, P.Lin.out(l)))

def t_fx5_nodes() -> U32: O.Arena.next(fx5.ar())
def t_fx5_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx5.ar()), fx5.ar(), fx5.top())))
def t_fx5_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.op(+f: O.Found) -> U32:
  P.gate.code(P.sc_op(O.Found.ar(f), O.Found.i(f)))

def t_fx5_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx5.ar(), fx5.top())))
def t_fx5_marks() -> U32: t_fx3.lin.marks(P.schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.nsrcs(+l: P.Lin) -> U32:
  P.gate.nsrcs(P.Lin.ar(l), P.Lin.out(l))

def t_fx5_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx5.ar(), fx5.top()))
def t_fx3.lin.ops(+l: P.Lin) -> U32:
  P.gate.ops(P.Lin.ar(l), P.Lin.out(l))

def t_fx5_ops() -> U32: t_fx3.lin.ops(P.schedule(fx5.ar(), fx5.top()))



def t_fx5_kids() -> U32: U32.from_nat(List.length(&2, P.Kid, P.Ctx.kids(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))))
def t_fx5_degs() -> U32: U32.from_nat(List.length(&2, P.Dep, P.Ctx.degs(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))))
def t_fx5_wrns() -> U32: U32.from_nat(List.length(&2, P.Wrn, P.Ctx.wrns(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))))
def t_fx5_rds() -> U32: U32.from_nat(List.length(&2, P.Rd, P.Ctx.rds(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))))
def t_fx5_zero() -> U32: U32.from_nat(List.length(&2, U32, P.zero(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))))
def t_fx5_cyc() -> U32: U32.from_nat(P.cycles(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top()))))
def t_fx5_kidn() -> U32: kids_n(P.pass2(fx5.ar(), P.pass1(fx5.ar(), fx5.top())))

# `Ka in Kb.backward_slice` -- the predicate that suppresses the WAR edge here.
def t_bs_Ka_Kb() -> U32: b2u(P.sc_in_bs(fx5.ar(), fx5.kb(), fx5.ka()))

def t_fx3_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx3.ar(), fx3.top()))
def t_fx3_marks() -> U32: t_fx3.lin.marks(P.schedule(fx3.ar(), fx3.top()))
# THE THREE ROWS fx3 NEVER PRINTED.  CPython answers all three (10, 2, 71) and
# the port did not ask: a fixture with a row for its MARK and its COUNT and
# none for its ORDER is a fixture whose ORDER is unpinned.
def t_fx3_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx3.ar()), fx3.ar(), fx3.top())))
def t_fx3_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx3.ar(), fx3.top())))
def t_fx3_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx3.ar(), fx3.top()))
def t_fx3_ops() -> U32: t_fx3.lin.ops(P.schedule(fx3.ar(), fx3.top()))

# THE COUNT ROWS. `n_children n_in_degree n_writes n_reads n_zero cycle`:
#   fx1 `0 2 2 3 2 0`   fx2 `1 3 3 3 2 1`
# `zero_deg_order` is `11` for both and `deg_K fx1 {'CALL':0,'END':0}` /
# `{'CALL':0}` for fx2 -- so the SUM of the degrees is a row too, because a
# wrong `in_degree` that still has the right KEY SET would slip past the count.
def t_fx1_kids() -> U32: U32.from_nat(List.length(&2, P.Kid, P.Ctx.kids(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))))
def t_fx1_degs() -> U32: U32.from_nat(List.length(&2, P.Dep, P.Ctx.degs(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))))
def t_fx1_wrns() -> U32: U32.from_nat(List.length(&2, P.Wrn, P.Ctx.wrns(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))))
def t_fx1_rds() -> U32: U32.from_nat(List.length(&2, P.Rd, P.Ctx.rds(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))))
def t_fx1_zero() -> U32: U32.from_nat(List.length(&2, U32, P.zero(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))))
def t_fx1_cyc() -> U32: U32.from_nat(P.cycles(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top()))))
def t_fx1_kids_n() -> U32: kids_n(P.pass2(fx1.ar(), P.pass1(fx1.ar(), fx1.top())))
def t_fx2_kids() -> U32: U32.from_nat(List.length(&2, P.Kid, P.Ctx.kids(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))))
def t_fx2_degs() -> U32: U32.from_nat(List.length(&2, P.Dep, P.Ctx.degs(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))))
def t_fx2_wrns() -> U32: U32.from_nat(List.length(&2, P.Wrn, P.Ctx.wrns(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))))
def t_fx2_rds() -> U32: U32.from_nat(List.length(&2, P.Rd, P.Ctx.rds(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))))
def t_fx2_zero() -> U32: U32.from_nat(List.length(&2, U32, P.zero(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))))
def t_fx2_cyc() -> U32: U32.from_nat(P.cycles(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top()))))
def t_fx2_kids_n() -> U32: kids_n(P.pass2(fx2.ar(), P.pass1(fx2.ar(), fx2.top())))

# ===========================================================================
# THE toposort'S own order -- the REORDER arm, as a ROW.
#
# CPython's toposort (ops.py:289-301) pushes `reversed(node.src)` and pops the
# LAST element, so the FIRST src is popped first.  `fx2_topo_marks` is that
# order (123 = Ka,Kb,Kc) and `fx2_marks` is the LINEAR order (231 = Kb,Kc,Ka):
# THE same three kernels, IN a different order, BECAUSE a war edge puts Ka
# AFTER the kernel that reads the state Ka SUPERSEDES.  The two rows are a
# PAIR, and a port that linearized in the toposort order would answer 123 for
# `fx2_marks` -- at which point the pair collapses into one row and the
# REORDER IS INVISIBLE.  That is the whole reason both are printed.
# ===========================================================================
# THE mark must be readable, OR the row is not producible. Upstream's `UOp.val`
# (ops.py:252-257) ASSERTS on anything that is not a CONST, a GETADDR or a CAST --
# it never answers 0. So a kernel whose mark CANNOT be read has NO MARK, and a
# fold that puts a digit in for it is asserting a value that does not exist.
#
# MEASURED 2026-10-22, AND this is the row that caught it. `fx7` is the
# `src_without_body` WITNESS: its second kernel's body is a SINK and not a body, so
# the mark node on that kernel is a CALL -- unreadable. The port's `gate.val`
# answers 0 for a node with no value, so the fold put a DIGIT 0 in and the port
# answered `fx7_topo_marks=10` where CPython's own toposort answers 1, because
# CPython SKIPS the kernel whose mark cannot be read. AN ABSENT VALUE FOLDED IN
# AS 0 IS THE ABSENT VALUE. The filter below now asks the MARK, not the kernel's
# op alone, and the fold skips what it cannot read.
#
# THE mark node is the same path `gate.mark` READS: a kernel's `src[0].src[0].src[1]`,
# on the UNWRAPPED kernel (`kernel`, the linearizer's own unwrap, so an END's kernel
# is its src[0] -- the same unwrap `topo_kernels` does on the CPython side).
def gate.markreadable(+ar: O.Arena, k: U32) -> Bool:
  +m = P.sc_src(ar, P.sc_src0(ar, P.sc_src0(ar, P.kernel(ar, k))), 1)
  Bool.or(P.sc_is(ar, m, O.OpsCONST{}), P.sc_is(ar, m, O.OpsCAST{}))

def gate.kkeep.of(op: O.Op) -> Bool:
  match op:
    case O.OpsCALL{}: True{}
    case O.OpsEND{}  : True{}
    case _           : False{}

def gate.kput(hit: Bool, acc: List<&2, U32>, k: U32) -> List<&2, U32>:
  match hit:
    case True{} : List.append(&2, U32, acc, [k])
    case False{}: acc

def gate.kkeep(+ar: O.Arena, +ks: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ks:
    case Nil{}     : acc
    case k <> rest : gate.kkeep(ar, rest, gate.kput(Bool.and(gate.kkeep.of(P.sc_op(ar, k)), gate.markreadable(ar, k)), acc, k))

# `gate.mark` reads a CALL's body; an END's kernel is its src[0], so the END
# is unwrapped FIRST (`kernel`, the linearizer's own unwrap).
def gate.kmark(+ar: O.Arena, k: U32) -> U32:
  gate.mark(ar, P.kernel(ar, k))

def gate.topo_marks.go(ks: List<&2, U32>, +ar: O.Arena, acc: U32) -> U32:
  match ks:
    case Nil{}     : acc
    case k <> rest : gate.topo_marks.go(rest, ar, U32.add(U32.mul(acc, 10), gate.kmark(ar, k)))

def gate.topo_marks(+ar: O.Arena, ks: List<&2, U32>) -> U32:
  gate.topo_marks.go(gate.kkeep(ar, ks, Nil{}), ar, 0)

def t_fx1_topo_marks() -> U32: gate.topo_marks(fx1.ar(), P.sc_topo_of(O.Arena.budget(fx1.ar()), fx1.ar(), fx1.top()))
def t_fx2_topo_marks() -> U32: gate.topo_marks(fx2.ar(), P.sc_topo_of(O.Arena.budget(fx2.ar()), fx2.ar(), fx2.top()))
def t_fx3_topo_marks() -> U32: gate.topo_marks(fx3.ar(), P.sc_topo_of(O.Arena.budget(fx3.ar()), fx3.ar(), fx3.top()))
def t_fx5_topo_marks() -> U32: gate.topo_marks(fx5.ar(), P.sc_topo_of(O.Arena.budget(fx5.ar()), fx5.ar(), fx5.top()))

# ===========================================================================
# THE EDGE ROWS.  EMPTY, the `src_without_body` WITNESS and the
# `gate_kernel_sink` WITNESS.
# ===========================================================================
def fx0.ar() -> O.Arena: O.Found.ar(fx0())
def fx0.top() -> U32: O.Found.i(fx0())
def fx7.ar() -> O.Arena: O.Found.ar(fx7())
def fx7.top() -> U32: O.Found.i(fx7())
def fx8.ar() -> O.Arena: O.Found.ar(fx8())
def fx8.top() -> U32: O.Found.i(fx8())
def fx8.kin() -> U32: P.sc_src0(fx8.ar(), fx8.top())
def fx8.sa() -> U32: P.sc_src(fx8.ar(), fx8.top(), 1)

# EMPTY.  CPython: `fx0_lin_n=0 fx0_lin_op=10 fx0_marks=0 fx0_nsrcs=0 fx0_ops=0`.
def t_fx0_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx0.ar()), fx0.ar(), fx0.top())))
def t_fx0_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx0.ar(), fx0.top()))
def t_fx0_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx0.ar(), fx0.top())))
def t_fx0_marks() -> U32: t_fx3.lin.marks(P.schedule(fx0.ar(), fx0.top()))
def t_fx0_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx0.ar(), fx0.top()))
def t_fx0_ops() -> U32: t_fx3.lin.ops(P.schedule(fx0.ar(), fx0.top()))

# THE `src_without_body` WITNESS.  CPython schedules ONE kernel; a port that
# descends into a CALL's body schedules TWO.
def t_fx7_topo_marks() -> U32: gate.topo_marks(fx7.ar(), P.sc_topo_of(O.Arena.budget(fx7.ar()), fx7.ar(), fx7.top()))
def t_fx7_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx7.ar()), fx7.ar(), fx7.top())))
def t_fx7_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx7.ar(), fx7.top()))
def t_fx7_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx7.ar(), fx7.top())))
def t_fx7_marks() -> U32: t_fx3.lin.marks(P.schedule(fx7.ar(), fx7.top()))
def t_fx7_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx7.ar(), fx7.top()))
def t_fx7_ops() -> U32: t_fx3.lin.ops(P.schedule(fx7.ar(), fx7.top()))

# THE `gate_kernel_sink` WITNESS.  CPython schedules ZERO kernels.
def t_fx8_topo_marks() -> U32: gate.topo_marks(fx8.ar(), P.sc_topo_of(O.Arena.budget(fx8.ar()), fx8.ar(), fx8.top()))
def t_fx8_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx8.ar()), fx8.ar(), fx8.top())))
def t_fx8_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx8.ar(), fx8.top()))
def t_fx8_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx8.ar(), fx8.top())))
def t_fx8_marks() -> U32: t_fx3.lin.marks(P.schedule(fx8.ar(), fx8.top()))
def t_fx8_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx8.ar(), fx8.top()))
def t_fx8_ops() -> U32: t_fx3.lin.ops(P.schedule(fx8.ar(), fx8.top()))

# THE GATE ITSELF, on the two SINKS of `fx8`: the one carrying a `KernelInfo`
# is NOT gated (0) and the plain one IS (1).  Without the arm the first is 1.
def t_gate_ki() -> U32: b2u(P.sc_gate(fx8.ar(), fx8.kin()))
def t_gate_plain() -> U32: b2u(P.sc_gate(fx8.ar(), fx8.sa()))

# ===========================================================================
# THE two arms that moved zero rows.  Each gets a DIRECT reader as well as an
# end-to-end one, because a direct reader says WHICH arm and the end-to-end one
# says that it MATTERS: `kdeps_*` is `create_schedule`'s `kernel_deps` line and
# `gate_lin` is `gate_kernel_sink`'s LINEAR arm.  MEASURED 2026-11-03: with only
# fx0..fx8 in the tree, breaking either arm moved 0 of 111 rows.
# ===========================================================================
def fx9.ar() -> O.Arena: O.Found.ar(fx9())
def fx9.top() -> U32: O.Found.i(fx9())
def fx10.ar() -> O.Arena: O.Found.ar(fx10())
def fx10.top() -> U32: O.Found.i(fx10())
def fx10.ln() -> U32: P.sc_src0(fx10.ar(), fx10.top())

# `k.src[0].src[1:]` for an END, `k.src[1:]` for a CALL.  fx1's `e2` wraps
# `k2 = CALL(body, b, vb)`, so the END arm answers 2 and the broken arm answers 0;
# `k2` itself answers 2 either way, which is why the CALL row alone cannot see it.
def t_kdeps_E2() -> U32: U32.from_nat(List.length(&2, U32, P.sc_kdeps(fx1.ar(), fx1.e2())))
def t_kdeps_K2() -> U32: U32.from_nat(List.length(&2, U32, P.sc_kdeps(fx1.ar(), fx1.k2())))

# THE `sc_kdeps.of` END WITNESS.  Correct arm: `kb` runs AFTER `ey` (marks 32).
# Broken arm: the queue seeds in insertion order and `kb` runs first (marks 23).
def t_fx9_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx9.ar()), fx9.ar(), fx9.top())))
def t_fx9_topo_marks() -> U32: gate.topo_marks(fx9.ar(), P.sc_topo_of(O.Arena.budget(fx9.ar()), fx9.ar(), fx9.top()))
def t_fx9_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx9.ar(), fx9.top()))
def t_fx9_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx9.ar(), fx9.top())))
def t_fx9_marks() -> U32: t_fx3.lin.marks(P.schedule(fx9.ar(), fx9.top()))
def t_fx9_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx9.ar(), fx9.top()))
def t_fx9_ops() -> U32: t_fx3.lin.ops(P.schedule(fx9.ar(), fx9.top()))

# THE `sc_gate.of` LINEAR WITNESS.  CPython schedules ZERO kernels here: the
# LINEAR stops the walk and `f1`'s subtree is never visited.
def t_gate_lin() -> U32: b2u(P.sc_gate(fx10.ar(), fx10.ln()))
def t_fx10_topo() -> U32: U32.from_nat(List.length(&2, U32, P.sc_topo_of(O.Arena.budget(fx10.ar()), fx10.ar(), fx10.top())))
def t_fx10_topo_marks() -> U32: gate.topo_marks(fx10.ar(), P.sc_topo_of(O.Arena.budget(fx10.ar()), fx10.ar(), fx10.top()))
def t_fx10_lin_n() -> U32: t_fx3.lin.of(P.schedule(fx10.ar(), fx10.top()))
def t_fx10_lin_op() -> U32: t_fx3.lin.op(P.linear(P.schedule(fx10.ar(), fx10.top())))
def t_fx10_marks() -> U32: t_fx3.lin.marks(P.schedule(fx10.ar(), fx10.top()))
def t_fx10_nsrcs() -> U32: t_fx3.lin.nsrcs(P.schedule(fx10.ar(), fx10.top()))
def t_fx10_ops() -> U32: t_fx3.lin.ops(P.schedule(fx10.ar(), fx10.top()))

# ===========================================================================
# THE TWELVE'S ROWS. Every expectation is `sb-oracle.py`'s printed output and
# NONE is typed. Run `sh checks/sb-gate.sh`, which diffs
# whole `name=value` LINES and never row names.
#
# `gate.code` gains ALLOC and PROGRAM. Both are NEW codes no base row reads, so
# the 81 rows are unaffected -- and `sb-gate.sh` re-checks that on every run
# rather than taking it. `usb_SA_A` NEEDS the ALLOC code: a BUFFER and an ALLOC
# are different `unsharded_base` answers and a boolean row cannot tell them
# apart. `ab_body_C_PROG` needs the PROGRAM code.
# ===========================================================================
# ===========================================================================
# THE `schedule_vars` ROWS -- seven, over THREE arms and one NON-arm.
#
#   sv_ok_n     TWO names landed, so `u` was skipped and the repeat `w` added no third.
#   sv_ok_bad   0: a repeat bind with an EQUAL value is not a mismatch. THE ROW that
#               separates `var_vals.get(nm, val) != val` from `nm in var_vals`.
#   sv_ok_v     `v` answers 3.
#   sv_ok_w     `w` answers 2 -- the FIRST value; answering 7 would mean the mismatch was
#               read off the wrong entry.
#   sv_ok_skip  `u` is ABSENT, so the `continue` fired.
#   sv_bad_n    ONE name: the second bind added no second entry.
#   sv_bad_bad  1: `v` bound 3 then 7.
# ===========================================================================
def svfx_ok.ar() -> O.Arena: O.Found.ar(svfx_ok())
def svfx_ok.top() -> U32: O.Found.i(svfx_ok())
def svfx_ok.bs() -> U32: P.sc_src0(svfx_ok.ar(), svfx_ok.top())
def svfx_ok.lin() -> U32: P.sc_src0(svfx_ok.ar(), svfx_ok.bs())
def svfx_bad.ar() -> O.Arena: O.Found.ar(svfx_bad())
def svfx_bad.top() -> U32: O.Found.i(svfx_bad())
def svfx_bad.bs() -> U32: P.sc_src0(svfx_bad.ar(), svfx_bad.top())
def svfx_bad.lin() -> U32: P.sc_src0(svfx_bad.ar(), svfx_bad.bs())

def sv_ok_r() -> P.SVar: schedule_vars(svfx_ok.ar(), svfx_ok.bs(), svfx_ok.lin())
def sv_bad_r() -> P.SVar: schedule_vars(svfx_bad.ar(), svfx_bad.bs(), svfx_bad.lin())
def sv_n(+r: P.SVar) -> U32: U32.from_nat(List.length(&2, P.VVal, P.SVar.vs(r)))
def sv_is_arg(+r: P.SVar, +nm: String, +c: O.Const) -> U32: b2u(O.eq_const(P.sv_get(P.SVar.vs(r), nm, O.CInvalid{}), c))
def sv_i32(n: U32) -> O.Const: O.CInt{H.i64_of_i32(n)}

def t_sv_ok_n() -> U32: sv_n(sv_ok_r())
def t_sv_ok_bad() -> U32: b2u(P.SVar.bad(sv_ok_r()))
def t_sv_ok_v() -> U32: sv_is_arg(sv_ok_r(), "v", sv_i32(3))
def t_sv_ok_w() -> U32: sv_is_arg(sv_ok_r(), "w", sv_i32(2))
def t_sv_ok_skip() -> U32: b2u(O.eq_const(P.sv_get(P.SVar.vs(sv_ok_r()), "u", O.CInvalid{}), O.CInvalid{}))
def t_sv_bad_n() -> U32: sv_n(sv_bad_r())
def t_sv_bad_bad() -> U32: b2u(P.SVar.bad(sv_bad_r()))



def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("unwrap_A1", t_unwrap_A1())
    b : Unit <- row("unwrap_B1", t_unwrap_B1())
    c : Unit <- row("unwrap_Vb", t_unwrap_Vb())
    d : Unit <- row("unwrap_AF1", t_unwrap_AF1())
    e : Unit <- row("unwrap_AF2", t_unwrap_AF2())
    f : Unit <- row("unwrap_bad", t_unwrap_bad())
    g : Unit <- row("split_A1_ks", t_split_A1())
    h : Unit <- row("split_AF1_ks", t_split_AF1())
    i : Unit <- row("split_AF2_ks", t_split_AF2())
    j : Unit <- row("split_AG1_ks", t_split_AG1())
    k : Unit <- row("split_AG2_ks", t_split_AG2())
    l : Unit <- row("split_AF2_ds", t_split_AF2_ds())
    m : Unit <- row("split_bad_ks", t_split_bad())
    n : Unit <- row("states_A1", t_states_A1())
    o : Unit <- row("states_AF2", t_states_AF2())
    p : Unit <- row("states_AG2", t_states_AG2())
    q : Unit <- row("bufuop_A1", t_bu_A1())
    r : Unit <- row("bufuop_AF1", t_bu_AF1())
    s : Unit <- row("bufuop_AF2", t_bu_AF2())
    t : Unit <- row("bufuop_Vb", t_bu_Vb())
    u : Unit <- row("bufuop_AG1", t_bu_AG1())
    v : Unit <- row("bufuop_AG2", t_bu_AG2())
    w : Unit <- row("bv_Vb", t_bv_Vb())
    x : Unit <- row("bv_Vu", t_bv_Vu())
    y : Unit <- row("bv_A1", t_bv_A1())
    z : Unit <- row("bv_K2src2", t_bv_K2src2())
    a2 : Unit <- row("bs_K2_K1", t_bs_K2_K1())
    b2 : Unit <- row("bs_E2_K2", t_bs_E2_K2())
    c2 : Unit <- row("bs_K1_K2", t_bs_K1_K2())
    d2 : Unit <- row("bs_Kb_Ka", t_bs_Kb_Ka())
    e2 : Unit <- row("fx1_nodes", t_fx1_nodes())
    f2 : Unit <- row("fx1_topo", t_fx1_topo())
    g2 : Unit <- row("fx1_lin_n", t_fx1_lin_n())
    h2 : Unit <- row("fx1_lin_op", t_fx1_lin_op())
    i2 : Unit <- row("fx1_marks", t_fx1_marks())
    j2 : Unit <- row("fx1_nsrcs", t_fx1_nsrcs())
    k2 : Unit <- row("fx1_ops", t_fx1_ops())
    l2 : Unit <- row("fx2_nodes", t_fx2_nodes())
    m2 : Unit <- row("fx2_topo", t_fx2_topo())
    n2 : Unit <- row("fx2_lin_n", t_fx2_lin_n())
    o2 : Unit <- row("fx2_lin_op", t_fx2_lin_op())
    p2 : Unit <- row("fx2_marks", t_fx2_marks())
    q2 : Unit <- row("fx2_nsrcs", t_fx2_nsrcs())
    r2 : Unit <- row("fx2_ops", t_fx2_ops())
    s2 : Unit <- row("COUNT_fx1_kids", t_fx1_kids())
    t2 : Unit <- row("COUNT_fx1_degs", t_fx1_degs())
    u2 : Unit <- row("COUNT_fx1_wrns", t_fx1_wrns())
    v2 : Unit <- row("COUNT_fx1_rds", t_fx1_rds())
    w2 : Unit <- row("COUNT_fx1_zero", t_fx1_zero())
    x2 : Unit <- row("COUNT_fx1_cyc", t_fx1_cyc())
    y2 : Unit <- row("COUNT_fx1_kidn", t_fx1_kids_n())
    z2 : Unit <- row("COUNT_fx2_kids", t_fx2_kids())
    a3 : Unit <- row("COUNT_fx2_degs", t_fx2_degs())
    b3 : Unit <- row("COUNT_fx2_wrns", t_fx2_wrns())
    c3 : Unit <- row("COUNT_fx2_rds", t_fx2_rds())
    d3 : Unit <- row("COUNT_fx2_zero", t_fx2_zero())
    e3 : Unit <- row("COUNT_fx2_cyc", t_fx2_cyc())
    row("split_AG3_ks", t_split_AG3_ks())
    row("split_AG3_ds", t_split_AG3_ds())
    row("bufuop_STAGE", t_bu_STAGE())
    row("bufuop_MSTACK", t_bu_MSTACK())
    row("COUNT_fx3_wrns", t_fx3_wrns())
    row("COUNT_fx3_wrks", t_fx3_wrks())
    row("fx3_lin_n", t_fx3_lin_n())
    row("fx3_marks", t_fx3_marks())
    row("fx3_topo", t_fx3_topo())
    row("fx3_lin_op", t_fx3_lin_op())
    row("fx3_nsrcs", t_fx3_nsrcs())
    row("fx3_ops", t_fx3_ops())
    row("fx1_topo_marks", t_fx1_topo_marks())
    row("fx2_topo_marks", t_fx2_topo_marks())
    row("fx3_topo_marks", t_fx3_topo_marks())
    row("fx5_topo_marks", t_fx5_topo_marks())
    row("fx0_topo", t_fx0_topo())
    row("fx0_lin_n", t_fx0_lin_n())
    row("fx0_lin_op", t_fx0_lin_op())
    row("fx0_marks", t_fx0_marks())
    row("fx0_nsrcs", t_fx0_nsrcs())
    row("fx0_ops", t_fx0_ops())
    row("fx7_topo_marks", t_fx7_topo_marks())
    row("fx7_topo", t_fx7_topo())
    row("fx7_lin_n", t_fx7_lin_n())
    row("fx7_lin_op", t_fx7_lin_op())
    row("fx7_marks", t_fx7_marks())
    row("fx7_nsrcs", t_fx7_nsrcs())
    row("fx7_ops", t_fx7_ops())
    row("fx8_topo_marks", t_fx8_topo_marks())
    row("fx8_topo", t_fx8_topo())
    row("fx8_lin_n", t_fx8_lin_n())
    row("fx8_lin_op", t_fx8_lin_op())
    row("fx8_marks", t_fx8_marks())
    row("fx8_nsrcs", t_fx8_nsrcs())
    row("fx8_ops", t_fx8_ops())
    row("gate_ki", t_gate_ki())
    row("gate_plain", t_gate_plain())
    row("fx5_nodes", t_fx5_nodes())
    row("fx5_topo", t_fx5_topo())
    row("fx5_lin_n", t_fx5_lin_n())
    row("fx5_lin_op", t_fx5_lin_op())
    row("fx5_marks", t_fx5_marks())
    row("fx5_nsrcs", t_fx5_nsrcs())
    row("fx5_ops", t_fx5_ops())
    row("bs_Ka_Kb", t_bs_Ka_Kb())
    row("COUNT_fx5_kids", t_fx5_kids())
    row("COUNT_fx5_degs", t_fx5_degs())
    row("COUNT_fx5_wrns", t_fx5_wrns())
    row("COUNT_fx5_rds", t_fx5_rds())
    row("COUNT_fx5_zero", t_fx5_zero())
    row("COUNT_fx5_cyc", t_fx5_cyc())
    row("COUNT_fx5_kidn", t_fx5_kidn())
    row("COUNT_fx2_kidn", t_fx2_kids_n())
    row("kdeps_E2", t_kdeps_E2())
    row("kdeps_K2", t_kdeps_K2())
    row("fx9_topo_marks", t_fx9_topo_marks())
    row("fx9_topo", t_fx9_topo())
    row("fx9_lin_n", t_fx9_lin_n())
    row("fx9_lin_op", t_fx9_lin_op())
    row("fx9_marks", t_fx9_marks())
    row("fx9_nsrcs", t_fx9_nsrcs())
    row("fx9_ops", t_fx9_ops())
    row("gate_lin", t_gate_lin())
    row("fx10_topo_marks", t_fx10_topo_marks())
    row("fx10_topo", t_fx10_topo())
    row("fx10_lin_n", t_fx10_lin_n())
    row("fx10_lin_op", t_fx10_lin_op())
    row("fx10_marks", t_fx10_marks())
    row("fx10_nsrcs", t_fx10_nsrcs())
    row("fx10_ops", t_fx10_ops())
    row("sv_ok_n", t_sv_ok_n())
    row("sv_ok_bad", t_sv_ok_bad())
    row("sv_ok_v", t_sv_ok_v())
    row("sv_ok_w", t_sv_ok_w())
    row("sv_ok_skip", t_sv_ok_skip())
    row("sv_bad_n", t_sv_bad_n())
    row("sv_bad_bad", t_sv_bad_bad())
