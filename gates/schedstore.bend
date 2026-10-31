# schedstore.bend -- the PORT lane of the `is_store_after` / `collect_stores` /
# `canonicalize_alloc` / `lower_sink_to_linear` / `copy_kernel_to_store` /
# `simplify_copy_kernel` / `assert_all_same_devices` / `apply_binds` parity
# gate.
#
#   .venv/bin/python gates/schedstore-gate.py
#
# WHAT IT MEASURES. `tinygrad/schedule/__init__.py:82-301` is the region the
# port's header DEFERS, and these are EIGHT of its TWELVE rule bodies:
#
#     def is_store_after(u:UOp) -> bool:
#       return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
#                                     or u.src[1].op is Ops.STORE)
#
#     def collect_stores(ctx:CallifyCtx, u:UOp):
#       if is_store_after(u): ctx.stores.append(u)
#
#     def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
#       if b.arg.slot >= 0 and b not in ctx.allocs:
#         ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
#       return ctx.allocs.get(b)
#
# IT IS THE RULE THE PORT'S OWN HEADER CALLED "the clearest case" of the ctx
# DICT: `CallifyCtx` is a dataclass of a list, a dict, a set and another list.
#
# AND THE PORT ALREADY HAS ALL EIGHT BODIES -- `tinybendygrad/schedule/__init__.bend`
# has `is_store_after` at :1231, `collect_stores` at :1376, `canonicalize_alloc`
# at :1833, `lower_sink_to_linear` at :1443, `copy_kernel_to_store` at :1549,
# `simplify_copy_kernel.ok` at :1575, `assert_all_same_devices` at :1669 and
# `apply_binds` at :1717 -- AND ZERO ROWS GATED THEM. MEASURED 2026-10-30, on
# the port's own output: the port emits 111 rows and 0 of them are
# `isa_*`/`cs_*`/`ca_*`. A rule body that no row reads is a body that no gate
# can go red on, so this lane is what makes the ported bodies TESTABLE AT ALL
# -- AND IT FOUND A REAL DEFECT: `ca_slot3` was the port's `none` where
# CPython's is `-2`. IT FOUND TWO MORE ON 2026-10-31, IN BODIES THAT STILL HAD
# NO ROW: `copy_kernel_to_store` REWROTE WITH THE WRONG POLARITY, and
# `assert_all_same_devices` DEDUPED THE NODES AND NOT THE DEVICES.
#
# THE CTX DICT IS NOT THE WALL. THE PORT'S `CallifyCtx` IS A `Data` RECORD OF
# FOUR APPEND-ONLY LISTS, and `collect_stores` returns the ctx AND the answer
# TOGETHER (`Cw`) because Python's one-call-one-side-effect signature cannot be
# spelled in Bend. THE PORT'S OWN HEADER SAYS IT: "FIVE of the twelve take NO
# ctx at all ... and the TWO that do take one take the SAME `CallifyCtx` whose
# `dict` field is one of four and is not the load-bearing one".
#
# THE ROWS. Fifty: ten `isa_*` over the predicate, five `cs_*` over the
# `collect_stores` ctx, ten `ca_*` over the `canonicalize_alloc` ctx, and
# TWENTY-FIVE OVER THE OTHER FIVE BODIES -- four `lsl_*`, six `cks_*`, six
# `sck_*`, six `ads_*` and three `ab_*`.
# The predicate is the interesting one because its FOUR CLAUSES are four different
# arms of the same `or`:
#
#   isa_SA_buffer_call   AFTER(BUFFER, CALL)   -> 1  (src[0] is not an ALLOC)
#   isa_SA_buffer_store  AFTER(BUFFER, STORE)  -> 1  (the src[1] arm)
#   isa_SA_alloc_call    AFTER(ALLOC, CALL)    -> 0  (the ALLOC arm, alone)
#   isa_SA_alloc_store   AFTER(ALLOC, STORE)   -> 1  (the ALLOC arm AND src[1])
#   isa_SA_buffer_end    AFTER(BUFFER, END)    -> 1  (src[1] is not a STORE)
#   isa_SA_sink_call     AFTER(SINK, CALL)     -> 1  (a SINK is not an ALLOC)
#   isa_K                a CALL                -> 0  (not an AFTER)
#
# `isa_SA_alloc_call` IS THE ROW THAT PINS THE `unsharded_base` WALK'S STOP
# SET: an ALLOC is not in `GroupOp.Movement`, so `unsharded_base(ALLOC)` is the
# ALLOC itself, and the port's `UOp.unsharded_base` peels ONLY on a Movement op
# or DETACH or UNSHARD. A port that peeled on the ALLOC would answer 1 here.
#
# `isa_SA_reshape_alloc` IS THE ROW THAT MAKES THE GATE FALSIFIABLE, AND IT IS
# THE ROW THE FIRST SEVEN COULD NOT HAVE FOUND. `unsharded_base` is a WALK,
# and a walk over an ALLOC is the IDENTITY -- so `isa_SA_alloc_call` reads the
# same under `src[0].op` and under `src[0].unsharded_base.op`, and a gate
# built only from the DIRECT children CANNOT SEE THE WALK AT ALL. MEASURED
# 2026-10-30: with `src[0].op` in place of `src[0].unsharded_base.op`, this
# gate was GREEN on all fifteen rows it then had. `isa_SA_reshape_alloc`'s
# `src[0]` IS A `RESHAPE`, so `unsharded_base` peels it to the ALLOC
# underneath and upstream answers 0 -- while `src[0].op` reads RESHAPE and
# answers 1. THE WALK IS THE DIFFERENCE AND THIS IS THE ROW THAT SEES IT.
#
# THE `cs_*` ROWS. `collect_stores` APPENDS and never dedups, so the stores
# list is in CALL ORDER and its length is the count of AFTERs that fire. The
# other three fields are the IDENTITY rows: a port that wrote `replacements`
# or `allocs` or `views` instead would answer 1 where CPython answers 0.
#
# THE `ca_*` ROWS. `-1 - len(ctx.allocs)` is the SLOT SEQUENCE, so the slots
# are -1, -2, ... and NOT 0, -1, ...; the `b not in ctx.allocs` GUARD makes a
# second call on the same `b` return the STORED node (`ca_slot3`); and
# `slot >= 0` leaves an ALREADY-CANONICAL slot alone and answers `none`
# (`ca_neg_none`). THE SLOT IS PRINTED AS A SIGNED DECIMAL BECAUSE THE PORT'S
# SLOT IS A `U32` AND PYTHON'S IS AN `int`, AND `slot_text` IS THE ONE PLACE
# THE TWO NUMBER SYSTEMS MEET.
#
# THE OTHER TWENTY-FIVE. THE PORT'S SIDE IS NOT UPSTREAM'S SIDE -- upstream's
# `graph_rewrite` is a PATTERN-MATCHER REWRITER the port does not have -- so
# NO ROW HERE IS "the port's output == upstream's output". EVERY ROW ASKS A
# QUESTION BOTH LANES CAN ANSWER, AND THE TWO LANES ARE THE SAME FIXTURE.
# MEASURED 2026-10-31: EVERY ONE OF THE ELEVEN BREAKS BELOW MOVES A ROW.
#
#   break                                              rows moved
#   ------------------------------------------------  -----------
#   `copy_kernel_to_store`'s polarity                    6 of 50
#   `assert_all_same_devices`'s device dedup             2 of 50
#   `assert_all_same_devices`'s `>= 2` threshold          1 of 50
#   `lower_sink_to_linear`'s `precompile` conjunct       1 of 50
#   `lower_sink_to_linear`'s `KernelInfo` conjunct       1 of 50
#   `lower_sink_to_linear`'s `body is SINK` conjunct      1 of 50
#   `apply_binds`'s arm 1 / arm 2                        2 of 50
#   `apply_binds`'s arm 3                                1 of 50
#   `apply_binds.of`'s body-op read                      2 of 50
#   `cks_dev.eq`'s `None == None`                        2 of 50
#   the `disk` set's membership test                     2 of 50

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as SP
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/schedule/__init__.bend as S

def row(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def b2s(b: Bool) -> String:
  match b:
    case True{} : "1"
    case False{}: "0"

# `ParamArg(slot, dtype, name=..., device=...)` -- the port's own `g_pb` shape,
# and CPU is `SP.D1{0}` because the port interned device NAMES as TAGS.
def pb(slot: U32, nm: String) -> O.ParamArg:
  O.ParamArg{slot, SP.int32(), None{}, None{}, Some{nm}, SP.AGlobal{},
    Some{SP.D1{0}}, False{}, None{}, None{}, False{}, None{}}

# A BUFFER with a size CONST src, the way `g_buf` builds one.
def buf(slot: U32, nm: String, ar: O.Arena) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(z), O.OpsBUFFER{}, [O.Found.i(z)], O.AParam{pb(slot, nm)}, O.TNone{})

# An ALLOC -- `Ops.ALLOC` with a `ParamArg`, the same shape as the BUFFER.
def alloc(slot: U32, nm: String, ar: O.Arena) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(z), O.OpsALLOC{}, [O.Found.i(z)], O.AParam{pb(slot, nm)}, O.TNone{})

# `UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(c0, cn)),))` -- the kernel body.
def body(n: U32, ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +cn = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(n)})
  +st = O.UOp.new(O.Found.ar(cn), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(cn)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])

# ===========================================================================
# THE FIXTURE.  ONE arena, built in ONE order, so every node has an index.
#
#   bufB   BUFFER
#   alA    ALLOC
#   bod    SINK (the kernel body)
#   call   CALL(bod, bufB)
#   end    END(call)
#   store  STORE(bufB, c1)
#   rsA    RESHAPE(alA, c4)          -- a MOVEMENT op over an ALLOC
#   rsB    RESHAPE(bufB, c4)          -- a MOVEMENT op over a BUFFER
#   stAl   STORE(alA, c1)
#   SA_B   AFTER(bufB, call)
#   SA_S   AFTER(bufB, store)
#   SA_A   AFTER(alA, call)
#   SA_AS  AFTER(alA, store)
#   SA_E   AFTER(bufB, end)
#   SA_SK  AFTER(bod, call)
#   SA_RSA AFTER(rsA, call)           -- THE DISCRIMINATING FIXTURE
#   SA_RSB AFTER(rsB, call)
#   SA_RSAST AFTER(rsA, stAl)
#
# THE INDICES LIVE IN A RECORD AND NOT IN A CHAIN OF LOOKUPS, because the
# AFTERs do NOT NEST: every AFTER's `src[0]` is a buffer, an alloc, a sink or
# a movement op, so there is no path from the top node down to the other
# AFTERs. A record is the only shape that can name sixteen siblings.
#
# `SA_S` AND `SA_A` ARE `AFTER`s THAT UPSTREAM'S `is_store_after` ACCEPTS, and
# `SA_AS` is one it accepts ONLY because its `src[1]` is a STORE.
#
# `SA_A` IS AN AFTER OVER AN ALLOC, and `SA_B` IS AN AFTER OVER A BUFFER, so
# the pair is the ALLOC arm of the `or` on its own.
#
# `SA_RSA` IS THE ROW THAT MAKES THE GATE FALSIFIABLE, AND IT IS THE ROW THE
# FIRST SIX COULD NOT HAVE FOUND. `unsharded_base` is a WALK, and a walk over
# an ALLOC is the IDENTITY -- so `isa_SA_alloc_call` reads the same under
# `src[0].op` and under `src[0].unsharded_base.op`, and a gate built only from
# the direct children CANNOT SEE THE WALK AT ALL. MEASURED 2026-10-30: with
# `src[0].op` in place of `src[0].unsharded_base.op`, this gate was GREEN on
# all twelve rows. `SA_RSA`'s `src[0]` IS A `RESHAPE`, so `unsharded_base`
# peels it to the ALLOC underneath and upstream answers 0 -- while `src[0].op`
# reads RESHAPE and answers 1. THE WALK IS THE DIFFERENCE AND THIS IS THE ROW
# THAT SEES IT.
# ===========================================================================
type Fx is Data:
  Fx{ar: O.Arena, bufB: U32, alA: U32, bod: U32, call: U32, end: U32, store: U32,
     rsA: U32, rsB: U32, stAl: U32, saB: U32, saS: U32, saA: U32, saAs: U32,
     saE: U32, saSk: U32, saRsa: U32, saRsb: U32, saRsast: U32}

def Fx.ar(x: Fx) -> O.Arena:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: ar

def Fx.bufB(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: bufB

def Fx.alA(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: alA

def Fx.bod(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: bod

def Fx.call(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: call

def Fx.end(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: end

def Fx.store(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: store

def Fx.rsA(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: rsA

def Fx.rsB(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: rsB

def Fx.stAl(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: stAl

def Fx.saB(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saB

def Fx.saS(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saS

def Fx.saA(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saA

def Fx.saAs(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saAs

def Fx.saE(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saE

def Fx.saSk(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saSk

def Fx.saRsa(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saRsa

def Fx.saRsb(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saRsb

def Fx.saRsast(x: Fx) -> U32:
  match x:
    case Fx{ar, bufB, alA, bod, call, end, store, rsA, rsB, stAl, saB, saS, saA,
            saAs, saE, saSk, saRsa, saRsb, saRsast}: saRsast

def fx() -> Fx:
  +b = buf(0, "a", O.Arena.empty())
  +al = alloc(1, "al", O.Found.ar(b))
  +bd = body(1, O.Found.ar(al))
  +cl = O.UOp.new(O.Found.ar(bd), O.OpsCALL{}, [O.Found.i(bd), O.Found.i(b)], O.ANone{}, O.TNone{})
  +en = O.UOp.new(O.Found.ar(cl), O.OpsEND{}, [O.Found.i(cl)], O.ANone{}, O.TNone{})
  +c1 = O.UOp.const(O.Found.ar(en), O.CInt{H.i64_of_i32(1)})
  +c4 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(4)})
  +sto = O.UOp.new(O.Found.ar(c4), O.OpsSTORE{}, [O.Found.i(b), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +rsa = O.UOp.new(O.Found.ar(sto), O.OpsRESHAPE{}, [O.Found.i(al), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +rsb = O.UOp.new(O.Found.ar(rsa), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +stal = O.UOp.new(O.Found.ar(rsb), O.OpsSTORE{}, [O.Found.i(al), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +sab = O.UOp.new(O.Found.ar(stal), O.OpsAFTER{}, [O.Found.i(b), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +sas = O.UOp.new(O.Found.ar(sab), O.OpsAFTER{}, [O.Found.i(b), O.Found.i(sto)], O.ANone{}, O.TNone{})
  +saa = O.UOp.new(O.Found.ar(sas), O.OpsAFTER{}, [O.Found.i(al), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +saas = O.UOp.new(O.Found.ar(saa), O.OpsAFTER{}, [O.Found.i(al), O.Found.i(sto)], O.ANone{}, O.TNone{})
  +sae = O.UOp.new(O.Found.ar(saas), O.OpsAFTER{}, [O.Found.i(b), O.Found.i(en)], O.ANone{}, O.TNone{})
  +sask = O.UOp.new(O.Found.ar(sae), O.OpsAFTER{}, [O.Found.i(bd), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +sarst = O.UOp.new(O.Found.ar(sask), O.OpsAFTER{}, [O.Found.i(rsa), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +srsb = O.UOp.new(O.Found.ar(sarst), O.OpsAFTER{}, [O.Found.i(rsb), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +srsast = O.UOp.new(O.Found.ar(srsb), O.OpsAFTER{}, [O.Found.i(rsa), O.Found.i(stal)], O.ANone{}, O.TNone{})
  Fx{O.Found.ar(srsast), O.Found.i(b), O.Found.i(al), O.Found.i(bd), O.Found.i(cl),
     O.Found.i(en), O.Found.i(sto), O.Found.i(rsa), O.Found.i(rsb), O.Found.i(stal),
     O.Found.i(sab), O.Found.i(sas), O.Found.i(saa), O.Found.i(saas), O.Found.i(sae),
     O.Found.i(sask), O.Found.i(sarst), O.Found.i(srsb), O.Found.i(srsast)}

# ===========================================================================
# THE SEVEN PREDICATE ROWS. `is_store_after` is the PORT'S OWN DEF, so a
# revert of the port's body moves these rows and the gate goes RED.
# ===========================================================================
def isa_b() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saB(fx())))
def isa_s() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saS(fx())))
def isa_a() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saA(fx())))
def isa_as() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saAs(fx())))
def isa_e() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saE(fx())))
def isa_sk() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saSk(fx())))
def isa_k() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.call(fx())))
def isa_rsa() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saRsa(fx())))
def isa_rsb() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saRsb(fx())))
def isa_rsast() -> String: b2s(S.is_store_after(Fx.ar(fx()), Fx.saRsast(fx())))

# ===========================================================================
# THE CTX. `collect_stores` APPENDS to `ctx.stores` and answers None; the port
# spells that `Cw{c, None{}}` because a rule body must return a node.
#
# THE PORT'S `CallifyCtx` HAS FOUR FIELDS AND ONLY `stores` IS WRITTEN HERE,
# so the other three are the IDENTITY rows: a port that wrote `replacements`
# or `allocs` or `views` instead would answer 1 where CPython answers 0.
#
# THE CALL ORDER: SA_B, SA_S, SA_A, SA_AS, SA_E, SA_SK, the three RESHAPE
# AFTERs, and the CALL. Nine AFTERs and one CALL, and CPython's stores list
# holds SEVEN of them -- SA_B, SA_S, SA_AS, SA_E, SA_SK, SA_RSB and SA_RSAST
# -- because SA_A is the ALLOC arm with a CALL and SA_RSA is the RESHAPE arm
# over an ALLOC.
# ===========================================================================
def calls() -> List<&2, U32>:
  [Fx.saB(fx()), Fx.saS(fx()), Fx.saA(fx()), Fx.saAs(fx()), Fx.saE(fx()), Fx.saSk(fx()),
   Fx.saRsa(fx()), Fx.saRsb(fx()), Fx.saRsast(fx()), Fx.call(fx())]

def ctx() -> S.CallifyCtx:
  S.cs_run(S.callify_ctx(), Fx.ar(fx()), calls())

def count(l: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, l))

def counta(l: List<&2, S.Aa>) -> U32:
  U32.from_nat(List.length(&2, S.Aa, l))

def cs_reps() -> String: U32.show(count(S.CallifyCtx.replacements(ctx())))
def cs_allocs() -> String: U32.show(counta(S.CallifyCtx.allocs(ctx())))
def cs_views() -> String: U32.show(count(S.CallifyCtx.views(ctx())))
def cs_stores() -> String: U32.show(count(S.CallifyCtx.stores(ctx())))

# THE STORES' OPS, IN ORDER: "AFTER,AFTER,AFTER". CPython prints the same
# three ops in the same order, so this row pins the APPEND ORDER and the COUNT
# together -- a port that REVERSED the list would print the same string here,
# so the ORDER row is `cs_ord`, which prints the ARENA INDEXES.
def opname.of(op: O.Op) -> String:
  match op:
    case O.OpsAFTER{}: "AFTER"
    case O.OpsCALL{} : "CALL"
    case O.OpsEND{}  : "END"
    case O.OpsSTORE{}: "STORE"
    case O.OpsSINK{} : "SINK"
    case O.OpsBUFFER{}: "BUFFER"
    case O.OpsALLOC{}: "ALLOC"
    case _           : "?"

def opname(ar: O.Arena, i: U32) -> String:
  opname.of(O.Arena.op(ar, i))

def ops2(l: List<&2, U32>) -> String:
  match l:
    case Nil{}     : ""
    case x <> rest : String.concat([opname(Fx.ar(fx()), x), ",", ops2(rest)])

def cs_ord() -> String: ops2(S.CallifyCtx.stores(ctx()))

# ===========================================================================
# `canonicalize_alloc` -- __init__.py:231-233. THE SECOND AND LAST OF THE
# TWO ctx BODIES, AND THE ONE THAT WRITES THE ctx's `dict` FIELD:
#
#     def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
#       if b.arg.slot >= 0 and b not in ctx.allocs:
#         ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
#       return ctx.allocs.get(b)
#
# THREE THINGS ARE THE PORT AND ALL THREE HAVE A ROW:
#   * `-1 - len(ctx.allocs)`, so the slots are -1, -2, ... and NOT 0, -1, ...
#     (`ca_slot1`/`ca_slot2`, ONE ROW APART, from fixtures whose incoming slots
#     are 7 and 9 -- so a port that dropped the `-1-` would answer 0 and 1).
#   * the `b not in ctx.allocs` GUARD, so a second call on the same `b` writes
#     nothing and returns the SAME node (`ca_n3`, `ca_repeat`).
#   * `slot >= 0`, so a slot that is ALREADY canonical is left alone and the
#     answer is `None{}` (`ca_neg_none`, `ca_neg_n`).
#
# **`ParamArg.slot` IS A `U32` AND PYTHON'S IS AN `int`.** That is the whole
# difficulty of the third clause: `slot >= 0` is TRUE for every Python int, so
# the only thing it can be excluding is a NEGATIVE slot, and in a `U32` the
# negative range is the TOP half. `ca_neg_*` uses an incoming slot of `-3`,
# which this file writes as `4294967293`, and the canonical slots are written
# as `-1 - len`, which is `4294967295 - len`. A port that read `>= 0` as
# `!= 0` would answer the same for every slot the gate holds, because none of
# them is 0 -- so `ca_slot1` and `ca_neg_none` are the pair that separates the
# two readings.
#
# THE SLOT IS PRINTED AS A SIGNED DECIMAL so the two lanes print the SAME
# string: upstream's `slot` is a Python `int` and prints `-1`, and the port's
# is a `U32` that holds `4294967295`. `slot_text` is that translation, and it
# is the ONE place the two lanes' number systems meet.
# ===========================================================================
# THE SLOT IS A SIGNED DECIMAL, AND THE SIGN IS THE TOP HALF OF THE `U32`:
# `slot < 0` is `slot < 2**31` on the port's side. THE NEGATIVE VALUE IS
# `0 - slot`, WHICH WRAPS: `0 - 4294967295` is 1, so `-1` PRINTS `-1` AND NOT
# `-0`. `4294967295 - slot` WOULD PRINT `-0` FOR `-1`, WHICH IS WHY IT IS
# `U32.sub(0, slot)` AND NOT THE OTHER ONE.
def slot_text.of(small: Bool, s: U32) -> String:
  match small:
    case True{} : U32.show(s)
    case False{}: String.concat(["-", U32.show(U32.sub(0, s))])

def slot_text(+s: U32) -> String:
  slot_text.of(U32.is_lt(s, 2147483648), s)

# THE ALLOC FIXTURE.  `al7` HAS SLOT 7, `al9` HAS SLOT 9, AND `al9b` IS
# `al9` BUILT AGAIN -- SO THE ARENA INTERNS IT ONCE AND BOTH NAMES ARE ONE
# INDEX, WHICH IS UPSTREAM'S `ucache` AND IS WHAT MAKES THE
# `b not in ctx.allocs` GUARD REACHABLE. `alneg` HAS SLOT -3, WRITTEN AS
# `4294967293`, AND IS ALREADY CANONICAL.
type Ca is Data:
  Ca{ar: O.Arena, al7: U32, al9: U32, al9b: U32, alneg: U32}

def Ca.ar(x: Ca) -> O.Arena:
  match x:
    case Ca{ar, al7, al9, al9b, alneg}: ar

def Ca.al7(x: Ca) -> U32:
  match x:
    case Ca{ar, al7, al9, al9b, alneg}: al7

def Ca.al9(x: Ca) -> U32:
  match x:
    case Ca{ar, al7, al9, al9b, alneg}: al9

def Ca.al9b(x: Ca) -> U32:
  match x:
    case Ca{ar, al7, al9, al9b, alneg}: al9b

def Ca.alneg(x: Ca) -> U32:
  match x:
    case Ca{ar, al7, al9, al9b, alneg}: alneg

def ca() -> Ca:
  +a7 = alloc(7, "al", O.Arena.empty())
  +a9 = alloc(9, "al", O.Found.ar(a7))
  +a9b = alloc(9, "al", O.Found.ar(a9))
  +aneg = alloc(4294967293, "al", O.Found.ar(a9b))
  Ca{O.Found.ar(aneg), O.Found.i(a7), O.Found.i(a9), O.Found.i(a9b), O.Found.i(aneg)}

# THE SLOT OF A CANONICALIZED ALLOC, or "none" when there is no answer --
# upstream's `None` and the port's `None{}` in one spelling. `S.ca_arg.slot`
# IS THE PORT'S OWN READER AND IT ANSWERS `Maybe<&2, U32>`, SO THE TWO LANES
# COMPARE THE SAME THING: A SLOT.
def ca_slot.of(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{s}: slot_text(s)
    case None{}  : "none"

# THE ANSWER'S SLOT, and the ANSWER IS A NEW NODE: `canonicalize_alloc`
# interns `b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))`, so the
# answer lives in a GROWN ARENA and the INPUT's slot is not the answer's.
# READING THE INPUT'S SLOT IS THE BUG THIS ROW EXISTS TO CATCH, and it reads
# `7` where upstream reads `-1`.
# THE ctx AND THE ARENA, because `canonicalize_alloc` GROWS THE ARENA -- the
# canonicalized ALLOC is a NEW node -- and a ctx without its arena cannot
# answer for the next call.
type CaS is Data:
  CaS{c: S.CallifyCtx, ar: O.Arena, a: Maybe<&2, O.Found>}

def CaS.c(x: CaS) -> S.CallifyCtx:
  match x:
    case CaS{c, ar, a}: c

def CaS.ar(x: CaS) -> O.Arena:
  match x:
    case CaS{c, ar, a}: ar

def CaS.a(x: CaS) -> Maybe<&2, O.Found>:
  match x:
    case CaS{c, ar, a}: a

# THE ANSWER'S INDEX, or the BOTTOM when there is no answer -- upstream's
# `None` and the port's `None{}` in one spelling.
def CaS.i.of(m: Maybe<&2, O.Found>) -> U32:
  match m:
    case Some{f}: O.Found.i(f)
    case None{}  : 0

def CaS.i(x: CaS) -> U32:
  CaS.i.of(CaS.a(x))

def Ca.slot(+x: CaS) -> String:
  ca_slot.of(S.ca_arg.slot(O.Arena.arg(CaS.ar(x), CaS.i(x))))

# `canonicalize_alloc(ctx, ar, b)` -- the port's own def. THE ANSWER IS A NEW
# NODE, SO THE GROWN ARENA IS INSIDE IT: `CaPut.a` is a `Maybe<&2, O.Found>`
# and the `Found`'s OWN arena is the grown one. WHEN THERE IS NO ANSWER --
# the already-canonical case -- THE ARENA IS UNCHANGED, SO THE INPUT'S ARENA
# IS THE ANSWER'S.
def ca_step.of(p: S.CaPut, ar: O.Arena) -> CaS:
  match p:
    case S.CaPut{c2, a2}:
      match a2:
        case Some{+f}: CaS{c2, O.Found.ar(f), a2}
        case None{}   : CaS{c2, ar, a2}

def ca_step(c: S.CallifyCtx, +ar: O.Arena, b: U32) -> CaS:
  ca_step.of(S.canonicalize_alloc(c, ar, b), ar)

# THE FOUR CALLS, IN UPSTREAM'S ORDER, AND EACH ONE THREADS THE ARENA.
def ca_s1() -> CaS: ca_step(S.callify_ctx(), Ca.ar(ca()), Ca.al7(ca()))
def ca_s2() -> CaS: ca_step(CaS.c(ca_s1()), CaS.ar(ca_s1()), Ca.al9(ca()))
def ca_s3() -> CaS: ca_step(CaS.c(ca_s2()), CaS.ar(ca_s2()), Ca.al9b(ca()))
def ca_s4() -> CaS: ca_step(CaS.c(ca_s3()), CaS.ar(ca_s3()), Ca.alneg(ca()))

def ca_slot1() -> String: Ca.slot(ca_s1())
def ca_slot2() -> String: Ca.slot(ca_s2())
def ca_slot3() -> String: Ca.slot(ca_s3())
def ca_neg_none() -> String: Ca.slot(ca_s4())
def ca_n1() -> String: U32.show(counta(S.CallifyCtx.allocs(CaS.c(ca_s1()))))
def ca_n2() -> String: U32.show(counta(S.CallifyCtx.allocs(CaS.c(ca_s2()))))
def ca_n3() -> String: U32.show(counta(S.CallifyCtx.allocs(CaS.c(ca_s3()))))
def ca_n4() -> String: U32.show(counta(S.CallifyCtx.allocs(CaS.c(ca_s4()))))
def ca_reps() -> String: U32.show(count(S.CallifyCtx.replacements(CaS.c(ca_s4()))))
def ca_views() -> String: U32.show(count(S.CallifyCtx.views(CaS.c(ca_s4()))))

# ===========================================================================
# THE FIVE BODIES THAT HAD NO ROW. MEASURED 2026-10-31.
#
# `lower_sink_to_linear`, `copy_kernel_to_store`, `simplify_copy_kernel`,
# `assert_all_same_devices` and `apply_binds` were all PORTED and all had NO
# ROW anywhere, so NO GATE COULD GO RED ON ANY OF THEM.
#
# THE PORT'S SIDE IS NOT UPSTREAM'S SIDE -- upstream's `graph_rewrite` is a
# PATTERN-MATCHER REWRITER the port does not have -- so no row here is "the
# port's output == upstream's output". Every row asks a QUESTION BOTH SIDES
# CAN ANSWER, and the two lanes are the same fixture.
#
#   lsl_*  DID THE GUARD HOLD? upstream's `lower_sink_to_linear` returns None
#          EXACTLY when the guard fires, so the row is "did it return None".
#          The port's `lower_sink_to_linear` answers `None{}` on the same
#          condition -- and the wall (`function.key`, `schedule_cache`) is
#          BEYOND the guard, which is the whole of the ported body.
#   cks_*  DID `copy_kernel_to_store` REWRITE?
#   sck_*  DID `simplify_copy_kernel` RETURN NONE? -- THE GUARD, which is
#          the same line as `cks_*`'s but over the OTHER rule.
#   ads_*  THE DEVICE COUNT AND THE RAISE.
#   ab_*  WHICH ARM of `apply_binds`.
#
# THE DEVICES ARE TAGS ON THE PORT'S SIDE: TAG 0 IS CPU AND TAG 1 IS DISK, and
# the port's `disk` parameter is the SET OF DISK TAGS. Every row below passes
# `[1]`, so the only variable in the `cks_*`/`sck_*` rows is the device PAIR.
# ===========================================================================

def pbn(slot: U32, nm: String, dev: Maybe<&2, SP.Dev>) -> O.ParamArg:
  O.ParamArg{slot, SP.int32(), None{}, None{}, Some{nm}, SP.AGlobal{},
    dev, False{}, None{}, None{}, False{}, None{}}

# THE TWO DEVICES: CPU IS TAG 0 AND DISK IS TAG 1.
def pbc(slot: U32, nm: String) -> O.ParamArg:
  pbn(slot, nm, Some{SP.D1{0}})

def pbd(slot: U32, nm: String) -> O.ParamArg:
  pbn(slot, nm, Some{SP.D1{1}})

def pbx(slot: U32, nm: String) -> O.ParamArg:
  pbn(slot, nm, None{})

# ---------------------------------------------------------------------------
# THE `cks_*`/`sck_*` FIXTURE. SIX BUFFERS: cpu/cpu, disk/disk and none/none,
# and the CALL that carries them.
# ---------------------------------------------------------------------------
type Ck is Data:
  Ck{ar: O.Arena, c0: U32, c1: U32, d0: U32, d1: U32, x0: U32, x1: U32, cl: U32}

def Ck.ar(x: Ck) -> O.Arena:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: ar

def Ck.c0(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: c0

def Ck.c1(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: c1

def Ck.d0(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: d0

def Ck.d1(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: d1

def Ck.x0(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: x0

def Ck.x1(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: x1

def Ck.cl(x: Ck) -> U32:
  match x:
    case Ck{ar, c0, c1, d0, d1, x0, x1, cl}: cl

def ckbuf(slot: U32, nm: String, pa: O.ParamArg, ar: O.Arena) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(z), O.OpsBUFFER{}, [O.Found.i(z)], O.AParam{pa}, O.TNone{})

def ck() -> Ck:
  +b0 = ckbuf(0, "a", pbc(0, "a"), O.Arena.empty())
  +b1 = ckbuf(1, "b", pbc(1, "b"), O.Found.ar(b0))
  +d0 = ckbuf(2, "a", pbd(2, "a"), O.Found.ar(b1))
  +d1 = ckbuf(3, "b", pbd(3, "b"), O.Found.ar(d0))
  +x0 = ckbuf(4, "a", pbx(4, "a"), O.Found.ar(d1))
  +x1 = ckbuf(5, "b", pbx(5, "b"), O.Found.ar(x0))
  +bd = O.UOp.sink(O.Found.ar(x1), [])
  +cl = O.UOp.new(O.Found.ar(bd), O.OpsCALL{}, [O.Found.i(bd), O.Found.i(b0), O.Found.i(b1)],
                  O.ANone{}, O.TNone{})
  Ck{O.Found.ar(cl), O.Found.i(b0), O.Found.i(b1), O.Found.i(d0), O.Found.i(d1),
     O.Found.i(x0), O.Found.i(x1), O.Found.i(cl)}

# THE DISK SET: TAG 1. CONSTANT FOR EVERY ROW, so the only variable is the
# DEVICE PAIR.
def ckdisk() -> List<&2, U32>: [1]

def cks_rewrote(dst: U32, src: U32) -> Bool:
  Maybe.is_some(&2, O.Found, S.copy_kernel_to_store(ckdisk(), Ck.ar(ck()), Ck.cl(ck()), dst, src))

def cks_same() -> String: b2s(cks_rewrote(Ck.c0(ck()), Ck.c1(ck())))
def cks_diff() -> String: b2s(cks_rewrote(Ck.c0(ck()), Ck.d1(ck())))
def cks_disk() -> String: b2s(cks_rewrote(Ck.d0(ck()), Ck.c1(ck())))
def cks_diskdisk() -> String: b2s(cks_rewrote(Ck.d0(ck()), Ck.d1(ck())))
def cks_none() -> String: b2s(cks_rewrote(Ck.x0(ck()), Ck.x1(ck())))
def cks_nonecpu() -> String: b2s(cks_rewrote(Ck.x0(ck()), Ck.c1(ck())))

# `simplify_copy_kernel`'s GUARD: 1 means upstream returned None.
def sck_same() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.c0(ck()), Ck.c1(ck())))
def sck_diff() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.c0(ck()), Ck.d1(ck())))
def sck_disk() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.d0(ck()), Ck.c1(ck())))
def sck_diskdisk() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.d0(ck()), Ck.d1(ck())))
def sck_none() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.x0(ck()), Ck.x1(ck())))
def sck_nonecpu() -> String: b2s(S.simplify_copy_kernel.ok(ckdisk(), Ck.ar(ck()), Ck.x0(ck()), Ck.c1(ck())))

# ---------------------------------------------------------------------------
# THE `lsl_*` FIXTURE. FOUR CALLS, ONE PER CONJUNCT OF THE GUARD:
#   sinkT  CALL(SINK,  precompile=True)   -- the guard HOLDS
#   sinkF  CALL(SINK,  precompile=False)  -- the guard FAILS on `precompile`
#   sinkK  CALL(SINK(KernelInfo), True)   -- the guard FAILS on the KernelInfo
#   linT   CALL(LINEAR, precompile=True)  -- the guard FAILS on `body is SINK`
#
# THE PORT'S `lower_sink_to_linear` ANSWERS `None{}` WHERE UPSTREAM'S GUARD
# SENDS IT HOME, so THE ROW IS "IS IT None".
# ---------------------------------------------------------------------------
def lsl_ci(pre: Bool) -> O.CallInfo:
  O.CallInfo{None{}, pre, False{}, SP.void()}

def lsl_sinkcall(pre: Bool, ar: O.Arena) -> O.Found:
  +sk = O.UOp.sink(ar, [])
  O.UOp.new(O.Found.ar(sk), O.OpsCALL{}, [O.Found.i(sk)], O.ACall{lsl_ci(pre)}, O.TNone{})

def lsl_kerncall(ar: O.Arena) -> O.Found:
  +sk = O.UOp.new(ar, O.OpsSINK{}, [], O.AKernel{O.KernelInfo.of()}, O.TNone{})
  O.UOp.new(O.Found.ar(sk), O.OpsCALL{}, [O.Found.i(sk)], O.ACall{lsl_ci(True{})}, O.TNone{})

def lsl_lincall(ar: O.Arena) -> O.Found:
  +ln = O.UOp.new(ar, O.OpsLINEAR{}, [], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(ln), O.OpsCALL{}, [O.Found.i(ln)], O.ACall{lsl_ci(True{})}, O.TNone{})

type Ll is Data:
  Ll{ar: O.Arena, sinkT: U32, sinkF: U32, kerT: U32, linT: U32}

def Ll.ar(x: Ll) -> O.Arena:
  match x:
    case Ll{ar, sinkT, sinkF, kerT, linT}: ar

def Ll.sinkT(x: Ll) -> U32:
  match x:
    case Ll{ar, sinkT, sinkF, kerT, linT}: sinkT

def Ll.sinkF(x: Ll) -> U32:
  match x:
    case Ll{ar, sinkT, sinkF, kerT, linT}: sinkF

def Ll.kerT(x: Ll) -> U32:
  match x:
    case Ll{ar, sinkT, sinkF, kerT, linT}: kerT

def Ll.linT(x: Ll) -> U32:
  match x:
    case Ll{ar, sinkT, sinkF, kerT, linT}: linT

def ll() -> Ll:
  +a = lsl_sinkcall(True{}, O.Arena.empty())
  +b = lsl_sinkcall(False{}, O.Found.ar(a))
  +c = lsl_kerncall(O.Found.ar(b))
  +d = lsl_lincall(O.Found.ar(c))
  Ll{O.Found.ar(d), O.Found.i(a), O.Found.i(b), O.Found.i(c), O.Found.i(d)}

# THE ROW IS "DID THE GUARD HOLD", and the two lanes spell it the same way:
# UPSTREAM REWRITES IFF THE GUARD HOLDS, so the lane prints 1 for "it
# rewrote"; the port's `lower_sink_to_linear` answers `Some{fn}` IFF THE GUARD
# HOLDS, so the port prints 1 for "it is not None".
def lsl_held(i: U32) -> Bool:
  Maybe.is_some(&2, U32, S.lower_sink_to_linear(Ll.ar(ll()), i))

def lsl_sink() -> String: b2s(lsl_held(Ll.sinkT(ll())))
def lsl_pre() -> String: b2s(lsl_held(Ll.sinkF(ll())))
def lsl_ki() -> String: b2s(lsl_held(Ll.kerT(ll())))
def lsl_body() -> String: b2s(lsl_held(Ll.linT(ll())))

# ---------------------------------------------------------------------------
# THE `ads_*` FIXTURE. THREE SINKS: TWO PARAMS ON ONE DEVICE, TWO PARAMS ON TWO
# DEVICES, AND ONE PARAM WITH NO DEVICE.
# ---------------------------------------------------------------------------
def ads_param(slot: U32, nm: String, dev: Maybe<&2, SP.Dev>, ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, [], O.AParam{pbn(slot, nm, dev)}, O.TNone{})

type Ad is Data:
  Ad{ar: O.Arena, same: U32, diff: U32, none: U32}

def Ad.ar(x: Ad) -> O.Arena:
  match x:
    case Ad{ar, same, diff, none}: ar

def Ad.same(x: Ad) -> U32:
  match x:
    case Ad{ar, same, diff, none}: same

def Ad.diff(x: Ad) -> U32:
  match x:
    case Ad{ar, same, diff, none}: diff

def Ad.none(x: Ad) -> U32:
  match x:
    case Ad{ar, same, diff, none}: none

def ad() -> Ad:
  +p0 = ads_param(0, "p", Some{SP.D1{0}}, O.Arena.empty())
  +p1 = ads_param(1, "q", Some{SP.D1{0}}, O.Found.ar(p0))
  +s1 = O.UOp.sink(O.Found.ar(p1), [O.Found.i(p0), O.Found.i(p1)])
  +q0 = ads_param(0, "p", Some{SP.D1{0}}, O.Found.ar(s1))
  +q1 = ads_param(1, "q", Some{SP.D1{1}}, O.Found.ar(q0))
  +s2 = O.UOp.sink(O.Found.ar(q1), [O.Found.i(q0), O.Found.i(q1)])
  +r0 = ads_param(0, "p", None{}, O.Found.ar(s2))
  +s3 = O.UOp.sink(O.Found.ar(r0), [O.Found.i(r0)])
  Ad{O.Found.ar(s3), O.Found.i(s1), O.Found.i(s2), O.Found.i(s3)}

def ads_n(a: S.Ads) -> U32:
  U32.from_nat(List.length(&2, SP.Dev, S.Ads.ds(a)))

def ads_same_n() -> String: U32.show(ads_n(S.assert_all_same_devices(Ad.ar(ad()), Ad.same(ad()))))
def ads_same_raises() -> String: b2s(S.assert_all_same_devices.raises(S.assert_all_same_devices(Ad.ar(ad()), Ad.same(ad()))))
def ads_diff_n() -> String: U32.show(ads_n(S.assert_all_same_devices(Ad.ar(ad()), Ad.diff(ad()))))
def ads_diff_raises() -> String: b2s(S.assert_all_same_devices.raises(S.assert_all_same_devices(Ad.ar(ad()), Ad.diff(ad()))))
def ads_none_n() -> String: U32.show(ads_n(S.assert_all_same_devices(Ad.ar(ad()), Ad.none(ad()))))
def ads_none_raises() -> String: b2s(S.assert_all_same_devices.raises(S.assert_all_same_devices(Ad.ar(ad()), Ad.none(ad()))))

# ---------------------------------------------------------------------------
# THE `ab_*` FIXTURE. THREE `si`s: A CALL WHOSE BODY IS A LINEAR (ARM 1), A
# CALL WHOSE BODY IS A PROGRAM (ARM 2), AND A PARAM (ARM 3).
# ---------------------------------------------------------------------------
def ab_arm1call(ar: O.Arena) -> O.Found:
  +ln = O.UOp.new(ar, O.OpsLINEAR{}, [], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(ln), O.OpsCALL{}, [O.Found.i(ln)], O.ANone{}, O.TNone{})

def ab_arm2call(ar: O.Arena) -> O.Found:
  +pg = O.UOp.new(ar, O.OpsPROGRAM{}, [], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(pg), O.OpsCALL{}, [O.Found.i(pg)], O.ANone{}, O.TNone{})

def ab_arm3param(ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, [],
    O.AParam{O.ParamArg{0, SP.single(), None{}, None{}, None{}, SP.AGlobal{},
      None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

type Ab is Data:
  Ab{ar: O.Arena, a1: U32, a2: U32, a3: U32}

def Ab.ar(x: Ab) -> O.Arena:
  match x:
    case Ab{ar, a1, a2, a3}: ar

def Ab.a1(x: Ab) -> U32:
  match x:
    case Ab{ar, a1, a2, a3}: a1

def Ab.a2(x: Ab) -> U32:
  match x:
    case Ab{ar, a1, a2, a3}: a2

def Ab.a3(x: Ab) -> U32:
  match x:
    case Ab{ar, a1, a2, a3}: a3

def ab() -> Ab:
  +x = ab_arm1call(O.Arena.empty())
  +y = ab_arm2call(O.Found.ar(x))
  +z = ab_arm3param(O.Found.ar(y))
  Ab{O.Found.ar(z), O.Found.i(x), O.Found.i(y), O.Found.i(z)}

def ab_arm1() -> String: U32.show(S.apply_binds(Ab.ar(ab()), Ab.a1(ab())))
def ab_arm2() -> String: U32.show(S.apply_binds(Ab.ar(ab()), Ab.a2(ab())))
def ab_arm3() -> String: U32.show(S.apply_binds(Ab.ar(ab()), Ab.a3(ab())))

def main() -> IO(Unit):
  do IO<Unit>:
    row("isa_SA_buffer_call", isa_b())
    row("isa_SA_buffer_store", isa_s())
    row("isa_SA_alloc_call", isa_a())
    row("isa_SA_alloc_store", isa_as())
    row("isa_SA_buffer_end", isa_e())
    row("isa_SA_sink_call", isa_sk())
    row("isa_K", isa_k())
    row("isa_SA_reshape_alloc", isa_rsa())
    row("isa_SA_reshape_buffer", isa_rsb())
    row("isa_SA_reshape_alloc_store", isa_rsast())
    row("cs_reps", cs_reps())
    row("cs_allocs", cs_allocs())
    row("cs_views", cs_views())
    row("cs_stores", cs_stores())
    row("cs_ord", cs_ord())
    row("ca_slot1", ca_slot1())
    row("ca_slot2", ca_slot2())
    row("ca_slot3", ca_slot3())
    row("ca_neg_none", ca_neg_none())
    row("ca_n1", ca_n1())
    row("ca_n2", ca_n2())
    row("ca_n3", ca_n3())
    row("ca_n4", ca_n4())
    row("ca_reps", ca_reps())
    row("ca_views", ca_views())
    row("lsl_sink", lsl_sink())
    row("lsl_pre", lsl_pre())
    row("lsl_ki", lsl_ki())
    row("lsl_body", lsl_body())
    row("cks_same", cks_same())
    row("cks_diff", cks_diff())
    row("cks_disk", cks_disk())
    row("cks_diskdisk", cks_diskdisk())
    row("cks_none", cks_none())
    row("cks_nonecpu", cks_nonecpu())
    row("sck_same", sck_same())
    row("sck_diff", sck_diff())
    row("sck_disk", sck_disk())
    row("sck_diskdisk", sck_diskdisk())
    row("sck_none", sck_none())
    row("sck_nonecpu", sck_nonecpu())
    row("ads_same_n", ads_same_n())
    row("ads_same_raises", ads_same_raises())
    row("ads_diff_n", ads_diff_n())
    row("ads_diff_raises", ads_diff_raises())
    row("ads_none_n", ads_none_n())
    row("ads_none_raises", ads_none_raises())
    row("ab_arm1", ab_arm1())
    row("ab_arm2", ab_arm2())
    row("ab_arm3", ab_arm3())
