# .agents/slop/browser/tstepc.bend -- THE WHOLE TRAINING STEP, RENDERED TO C.
#
# forward (conv -> relu -> pool -> linear) -> `sum((y-t)^2)` -> `tn_backward` -> SGD, and then SIX
# STORES so the answer is a program and not a signature: out, loss, gw1, gw2, w1_new, w2_new.
# The render lane is `fchainc.bend`'s, unchanged: one `kg()`, one `schedule`, `DEV.body_kus` ->
# `DEV.program` per kernel.
#
# ONE MONOTONE ARENA (row 62's lesson): the inputs are created first on one chain, and every operand is
# RE-WRAPPED at the latest arena before it is reshaped, permuted, multiplied or subtracted -- otherwise
# `tn_mul`'s `Arena.merge` shifts one fork's ids and the graph is silently about other nodes.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX
import ./../../../tinybendygrad/mixin/gradient.bend as G
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/base.bend as FB
import ./../../../tinybendygrad/helpers.bend as H

def gv.of(m: Maybe<&2, G.GSlot>) -> U32:
  match m:
    case Some{s}: G.GSlot.v_of(s)
    case _: 0

def gv(+g: G.Grads, +k: U32) -> U32: gv.of(G.gslot(g, k))

# `w - lr*g`, with `lr = 0.1f` (0x3dcccccd): MUL then SUB, and SUB is `ADD(x, MUL(y,-1))` upstream.
# `lr` IS MINTED, so every wrapper after it must read `O.Found.ar(lr)` -- the arena that CONTAINS lr.
# `T.Tensor.ar(gt)` is the arena from BEFORE lr existed, so `T.tn_new(it, O.Found.i(lr))` interned an
# INDEX PAST THE END (a NOOP), and `tn_mul(gt, lrt)` was a shape MISMATCH against that NOOP: shapeless,
# which is what killed the store. (Orchestrator's catch; MEASURED as `sh_w2n=:0:` with `sh_g2=:2:49x10`
# in the same arena.)
def sgd.mk(+ar: O.Arena, +w: U32, +g: U32) -> T.Tensor:
  +lr = O.UOp.const(ar, O.CFloat{FB.F32.from_bits(1036831949)})
  +a1 = O.Found.ar(lr)
  +gt = T.tn_new(a1, g)
  +lrt = MX.mxw_bcast(T.tn_new(a1, O.Found.i(lr)), IX.rr_dims(a1, F.Folded.t(F.folded(a1)), g))
  +sc = T.tn_mul(gt, lrt)
  T.tn_sub(T.tn_new(T.Tensor.ar(sc), w), sc)

type TP is Data:
  TP{prog: RZ.RZProg, out: U32, lt: U32, g1: U32, g2: U32, w1n: U32, w2n: U32, ws: U32, csg: G.Grads}

def TP.prog(x: TP) -> RZ.RZProg:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: prog
def TP.out(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: out
def TP.lt(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: lt
def TP.g1(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: g1
def TP.g2(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: g2
def TP.w1n(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: w1n
def TP.w2n(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: w2n
def TP.ws(x: TP) -> U32:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: ws
def TP.csg(x: TP) -> G.Grads:
  match x:
    case TP{prog, out, lt, g1, g2, w1n, w2n, ws, csg}: csg

def tprog() -> TP:
  # --- the four inputs, one chain -----------------------------------------------------------------
  +x0 = RZ.rz_input(O.Arena.empty(), 1, 784, [1, 1, 28, 28])
  +w1_0 = RZ.rz_input(T.Tensor.ar(x0), 2, 4, [1, 1, 2, 2])
  +w2_0 = RZ.rz_input(T.Tensor.ar(w1_0), 6, 490, [49, 10])
  +t_0 = RZ.rz_input(T.Tensor.ar(w2_0), 7, 10, [1, 10])
  +ar0 = T.Tensor.ar(t_0)
  +x = T.tn_new(ar0, T.Tensor.u(x0))
  +w1 = T.tn_new(ar0, T.Tensor.u(w1_0))
  +w2 = T.tn_new(ar0, T.Tensor.u(w2_0))
  # --- forward ------------------------------------------------------------------------------------
  +xs = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +ws = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(xs), T.Tensor.u(w1)), [1, 1, 1, 2, 1, 2])
  +c1 = T.tn_mul(xs, ws)
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +v1 = MX.mxw_reshape(T.tn_new(O.Found.ar(f1), O.Found.i(f1)), [1, 1, 14, 14])
  +a2 = T.tn_relu(v1)
  +v2 = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(a2), T.Tensor.u(a2)), [1, 1, 7, 2, 7, 2])
  +f3 = T.tn_rop(T.Tensor.ar(v2), T.Tensor.u(v2), O.OpsMAX{}, [3, 5])
  +p3 = T.tn_new(O.Found.ar(f3), O.Found.i(f3))
  +lhs = MX.mxw_reshape.go(p3, [1, 1, 49])
  +w2r = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(lhs), T.Tensor.u(w2)), [1, 49, 10])
  +rhs = MX.mxw_permute.go(T.tn_new(T.Tensor.ar(w2r), T.Tensor.u(w2r)), [0, 2, 1])
  +c4 = T.tn_mul(lhs, rhs)
  +f4 = T.tn_rop(T.Tensor.ar(c4), T.Tensor.u(c4), O.OpsADD{}, [2])
  +out = T.tn_new(O.Found.ar(f4), O.Found.i(f4))
  +t = T.tn_new(T.Tensor.ar(out), T.Tensor.u(t_0))
  +d = T.tn_sub(out, t)
  +sq = T.tn_square(d)
  +loss = T.tn_rop(T.Tensor.ar(sq), T.Tensor.u(sq), O.OpsADD{}, [1])
  +lt = T.tn_new(O.Found.ar(loss), O.Found.i(loss))
  # --- backward + SGD -----------------------------------------------------------------------------
  +tg: List<&2, U32> = [T.Tensor.u(w1), T.Tensor.u(w2)]
  +seed = O.UOp.const(T.Tensor.ar(lt), O.CFloat{FB.F32.from_bits(1065353216)})
  +cs = G.compute_gradient(T.Tensor.u(lt), O.Found.i(seed), tg, O.Found.ar(seed))
  +ga = G.CState.ar_of(cs)
  +g1 = gv(G.CState.g_of(cs), T.Tensor.u(w1))
  +g2 = gv(G.CState.g_of(cs), T.Tensor.u(w2))
  +w1n = sgd.mk(ga, T.Tensor.u(w1), g1)
  +w2n = sgd.mk(T.Tensor.ar(w1n), T.Tensor.u(w2), g2)
  # --- SIX STORES, each on the arena the previous one grew ------------------------------------------
  +dout = RZ.rz_input(T.Tensor.ar(w2n), 10, 10, [1, 10])
  +ao = RZ.rz_after(dout, T.tn_new(T.Tensor.ar(dout), T.Tensor.u(out)))
  +dls = RZ.rz_input(O.Found.ar(ao), 11, 1, [1])
  +als = RZ.rz_after(dls, T.tn_new(T.Tensor.ar(dls), T.Tensor.u(lt)))
  +dg1 = RZ.rz_input(O.Found.ar(als), 12, 4, [1, 1, 2, 2])
  +ag1 = RZ.rz_after(dg1, T.tn_new(T.Tensor.ar(dg1), g1))
  +dg2 = RZ.rz_input(O.Found.ar(ag1), 13, 490, [49, 10])
  +ag2 = RZ.rz_after(dg2, T.tn_new(T.Tensor.ar(dg2), g2))
  +dn1 = RZ.rz_input(O.Found.ar(ag2), 14, 4, [1, 1, 2, 2])
  +an1 = RZ.rz_after(dn1, T.tn_new(T.Tensor.ar(dn1), T.Tensor.u(w1n)))
  +dn2 = RZ.rz_input(O.Found.ar(an1), 15, 490, [49, 10])
  +an2 = RZ.rz_after(dn2, T.tn_new(T.Tensor.ar(dn2), T.Tensor.u(w2n)))
  +snk = O.UOp.sink(O.Found.ar(an2),
    [O.Found.i(ao), O.Found.i(als), O.Found.i(ag1), O.Found.i(ag2), O.Found.i(an1), O.Found.i(an2)])
  TP{RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)},
     T.Tensor.u(out), T.Tensor.u(lt), g1, g2, T.Tensor.u(w1n), T.Tensor.u(w2n), T.Tensor.u(ws), G.CState.g_of(cs)}

def dims.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: dims.go(t, List.append(&2, String, acc, [U32.show(x)]))

def sh(+ar: O.Arena, +u: U32) -> String:
  +ds = IX.rr_dims(ar, F.Folded.t(F.folded(ar)), u)
  String.concat([":", U32.show(U32.from_nat(List.length(&2, U32, ds))), ":", String.join(dims.go(ds, Nil{}), "x")])

def kg() -> O.Found:
  +q = RZ.rz_rebuild(TP.prog(tprog()), False{}, False{})
  RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))

def mk_emit(p: (O.Arena & List<&2, C.KU>), +i: U32, +acc: List<&2, String>) -> (O.Arena & List<&2, String>):
  (ar, +kus) = p
  (ar, List.append(&2, String, acc,
        [String.concat(["--k", U32.show(i), "\n", DEV.Prog.src(DEV.program("k", kus))])]))

def mk_step(p: (O.Arena & List<&2, String>), +k: U32, +i: U32) -> (O.Arena & List<&2, String>):
  (+ar, +acc) = p
  mk_emit(DEV.body_kus(ar, k), i, acc)

def mk_go(+ks: List<&2, U32>, p: (O.Arena & List<&2, String>), +i: U32) -> (O.Arena & List<&2, String>):
  match ks:
    case Nil{}: p
    case k <> t: mk_go(t, mk_step(p, k, i), U32.add(i, 1))

def mk_all(p: (O.Arena & List<&2, String>)) -> String:
  (ar, acc) = p
  String.join(acc, "\n")

def chain_c() -> String:
  +k = kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  mk_all(mk_go(SCH.lin_kernels(lin), (SCH.lin_ar(lin), Nil{}), 0))

# --- DIAGNOSTICS: what `kg()` and `schedule()` actually returned -----------------------------------
def cnt.go(+ar: O.Arena, +ns: List<&2, U32>, +want: O.Op, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case n <> t: cnt.go(ar, t, want, U32.add(acc, Bool.to_u32(O.eq_op(O.Arena.op(ar, n), want))))

def cnt(+ar: O.Arena, +ns: List<&2, U32>, want: O.Op) -> U32: cnt.go(ar, ns, want, 0)

def lk1(+ar: O.Arena, +ks: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ks:
    case Nil{}: String.join(acc, " ")
    case k <> t:
      lk1(ar, t, List.append(&2, String, acc,
        [String.concat([RF.eng_op_name(O.Arena.op(ar, k)), ">",
                        RF.eng_op_name(O.Arena.op(ar, SCH.sc_src0(ar, k)))])]))

# WHICH STORE SLOTS SURVIVE. A STORE's dst is `INDEX(BUFFER(ParamArg{slot}))`, so the slot is two srcs
# down and it is the only thing that says WHICH of the six went missing.
def mslot(m: Maybe<&2, U32>) -> Maybe<&2, String>:
  match m:
    case Some{v}: Some{U32.show(v)}
    case _: None{}

def slot_of.pick(isix: Bool, +ar: O.Arena, +st: U32) -> String:
  match isix:
    case True{}:
      +b = O.Arena.src0(ar, O.Arena.src0(ar, st))
      Maybe.default(&2, String, mslot(RZ.rz_param_slot(ar, b)), "?")
    case False{}: "?"

def slot_of(+ar: O.Arena, +st: U32) -> String:
  slot_of.pick(O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, st)), O.OpsINDEX{}), ar, st)

def slots.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ns:
    case Nil{}: String.join(acc, ",")
    case n <> t:
      slots.go(ar, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, n), O.OpsSTORE{}),
        List.append(&2, String, acc, [slot_of(ar, n)]), acc))

# THE `g1` CHILD WALK: the op of g1 and of each of its srcs, with each SHAPE's rank -- the first `0`
# is the node whose shape the fold cannot read, which is what makes `g1` (and `w1_new`) shapeless.
def kids.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: String.join(acc, ",")
    case h <> t:
      kids.go(ar, t, List.append(&2, String, acc,
        [String.concat([RF.eng_op_name(O.Arena.op(ar, h)), "/",
                        U32.show(U32.from_nat(List.length(&2, U32, IX.rr_dims(ar, F.Folded.t(F.folded(ar)), h))))])]))

# THE STACK WALK: g1's src[1] is the shape arg greshape minted. Its OP says which form ds took
# (a bare CONST for a one-element ds, a STACK otherwise), dshow reads its own fold-shape, stkids
# reads each child's sym_dim, and mshow is marg(ar, g1) -- the very read reshape_ds makes.
def symshow.of(m: Maybe<&1, O.Sint>) -> String:
  match m:
    case Some{O.SI{+v}}: String.concat(["SI", H.i64_text(v)])
    case Some{O.SU{+s}}: String.concat(["SU", U32.show(s)])
    case None{}: "?"

def symshow(+ar: O.Arena, +u: U32) -> String:
  symshow.of(F.sym_dim(ar, u))

def dshow.go(ds: List<&2, U32>, +acc: String) -> String:
  match ds:
    case Nil{}: acc
    case d <> t: dshow.go(t, String.concat([acc, "x", U32.show(d)]))

def dshow(+ar: O.Arena, +u: U32) -> String:
  dshow.go(IX.rr_dims(ar, F.Folded.t(F.folded(ar)), u), "")

def sshow.go(ds: List<&2, O.Sint>, +acc: String) -> String:
  match ds:
    case Nil{}: acc
    case d <> t:
      match d:
        case O.SI{+v}: sshow.go(t, String.concat([acc, "x", H.i64_text(v)]))
        case O.SU{+s}: sshow.go(t, String.concat([acc, "xSU", U32.show(s)]))

def mshow.of(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{ds}: String.concat(["[", sshow.go(ds, ""), "]"])
    case None{}: "None"

def mshow(+ar: O.Arena, +u: U32) -> String:
  mshow.of(F.marg(ar, u))

def stkids.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: String.join(acc, ",")
    case h <> t:
      stkids.go(ar, t, List.append(&2, String, acc,
        [String.concat([RF.eng_op_name(O.Arena.op(ar, h)), "=", symshow(ar, h)])]))

def g1row(+ar: O.Arena, +u: U32) -> String:
  +sk = O.Arena.src(ar, u, 1)
  String.concat([RF.eng_op_name(O.Arena.op(ar, u)), "[", kids.go(ar, O.Arena.srcs(ar, u), Nil{}), "]",
                 " sk=", RF.eng_op_name(O.Arena.op(ar, sk)), "{", dshow(ar, sk), "}",
                 " kids=", stkids.go(ar, O.Arena.srcs(ar, sk), Nil{}),
                 " mul=", dshow(ar, O.Arena.src0(ar, u)),
                 " marg=", mshow(ar, u)])

def store_of.op(fuel: Nat, +ar: O.Arena, +x: U32, op: O.Op) -> U32:
  match fuel:
    case 0n: x
    case 1n+p:
      match op:
        case O.OpsCALL{}: store_of.op(p, ar, O.Arena.src0(ar, x), O.Arena.op(ar, O.Arena.src0(ar, x)))
        case O.OpsSINK{}: store_of.op(p, ar, O.Arena.src0(ar, x), O.Arena.op(ar, O.Arena.src0(ar, x)))
        case O.OpsEND{}: store_of.op(p, ar, O.Arena.src0(ar, x), O.Arena.op(ar, O.Arena.src0(ar, x)))
        case _: x

def store_of(+ar: O.Arena, +x: U32) -> U32:
  store_of.op(4n, ar, x, O.Arena.op(ar, x))

def skgo.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: String.join(acc, ",")
    case h <> t:
      skgo.go(ar, t, List.append(&2, String, acc,
        [U32.show(Bool.pick(U32, RF.sk_open(ar, O.Arena.src(ar, h, 1)), 1, 0))]))

def afts.go(+ar: O.Arena, +ss: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ss:
    case Nil{}: String.join(acc, ",")
    case h <> t:
      afts.go(ar, t, List.append(&2, String, acc,
        [String.concat([RF.eng_op_name(O.Arena.op(ar, h)), ">",
                        RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, h))), ">",
                        RF.eng_op_name(O.Arena.op(ar, O.Arena.src(ar, h, 1)))])]))

def gshape.none.of(m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case Some{ds}: False{}
    case _: True{}

def gshape.none(+ar: O.Arena, +u: U32) -> Bool:
  gshape.none.of(G.gshape(ar, u))

def pairs.go(+ar: O.Arena, +ks: List<&2, U32>, +vs: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ks vs:
    case Nil{} Nil{}: String.join(acc, "|")
    case k <> kt v <> vt:
      pairs.go(ar, kt, vt, List.append(&2, String, acc,
        [String.concat([RF.eng_op_name(O.Arena.op(ar, k)), "=", RF.eng_op_name(O.Arena.op(ar, v)), ":", dshow(ar, v)])]))
    case _ _: String.join(acc, "|")

def badg.go(+ar: O.Arena, +ks: List<&2, U32>, +vs: List<&2, U32>, +acc: List<&2, String>) -> String:
  match ks vs:
    case Nil{} Nil{}: String.join(acc, ";")
    case k <> kt v <> vt:
      badg.go(ar, kt, vt, Bool.pick(List<&2, String>, gshape.none(ar, v),
        List.append(&2, String, acc, [String.concat([RF.eng_op_name(O.Arena.op(ar, k)), "=", RF.eng_op_name(O.Arena.op(ar, v))])]), acc))
    case _ _: String.join(acc, ";")

def gshs.of(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{ds}: dshow.go(ds, "")
    case _: "None"

def gshs(+ar: O.Arena, +u: U32) -> String:
  gshs.of(G.gshape(ar, u))

def diag() -> String:
  # (1) the STOREs BEFORE the kernel split, and (2) the SHAPES of the six stored values. A store whose
  # value has no shape is a store `rz_rebuild`/`rr_kernel_graph` drops, and the difference between these
  # two counts is where.
  +tp = tprog()
  +cha = RZ.RZProg.ar(TP.prog(tp))
  +q = RZ.rz_rebuild(TP.prog(tp), False{}, False{})
  +qa = RZ.RZProg.ar(q)
  +qs = RZ.RZProg.sink(q)
  +ns0 = O.UOp.toposort(O.Arena.budget(qa), qa, qs)
  +k = kg()
  +ka = O.Found.ar(k)
  +ns = O.UOp.toposort(O.Arena.budget(ka), ka, O.Found.i(k))
  +lin = SCH.schedule(ka, O.Found.i(k))
  +p_ck: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(1)})
  +p_cv: O.Found = O.UOp.const(O.Found.ar(p_ck), O.CFloat{FB.F32.from_bits(1)})
  +p_pa: O.Arena = O.Found.ar(p_cv)
  +p_k: U32 = O.Found.i(p_ck)
  +p_v: U32 = O.Found.i(p_cv)
  +p_s: G.CState = G.CState{p_pa, G.Grads{Nil{}, Nil{}}, 0, 0}
  +p_c: G.CState = G.cg_edge.guard(Some{[1, 1, 1, 2, 1, 2]}, Some{[1, 1, 14, 2, 14, 2]}, p_s, p_k, p_v)
  +p_a: O.Arena = G.CState.ar_of(p_c)
  +p_r: U32 = gv(G.CState.g_of(p_c), p_k)
  +q_ck: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(1)})
  +q_cv: O.Found = O.UOp.const(O.Found.ar(q_ck), O.CFloat{FB.F32.from_bits(1)})
  +q_s: G.CState = G.CState{O.Found.ar(q_cv), G.Grads{Nil{}, Nil{}}, 0, 0}
  +q_c: G.CState = G.cg_edge.eq([1, 1, 1, 2, 1, 2], [1, 1, 14, 2, 14, 2], q_s, O.Found.i(q_ck), O.Found.i(q_cv))
  +q_a: O.Arena = G.CState.ar_of(q_c)
  +q_r: U32 = gv(G.CState.g_of(q_c), O.Found.i(q_ck))
  +w_ck: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(1)})
  +w_cv: O.Found = O.UOp.const(O.Found.ar(w_ck), O.CFloat{FB.F32.from_bits(1)})
  +w_s: G.CState = G.CState{O.Found.ar(w_cv), G.Grads{Nil{}, Nil{}}, 0, 0}
  +w_c: G.CState = G.cg_edge.axes(False{}, [1, 1, 1, 2, 1, 2], [1, 1, 14, 2, 14, 2], w_s, O.Found.i(w_ck), O.Found.i(w_cv))
  +w_a: O.Arena = G.CState.ar_of(w_c)
  +w_r: U32 = gv(G.CState.g_of(w_c), O.Found.i(w_ck))
  +y_ck: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(1)})
  +y_cv: O.Found = O.UOp.const(O.Found.ar(y_ck), O.CFloat{FB.F32.from_bits(1)})
  +y_s: G.CState = G.CState{O.Found.ar(y_cv), G.Grads{Nil{}, Nil{}}, 0, 0}
  +y_c: G.CState = G.cg_edge.diff(True{}, [1, 1, 1, 2, 1, 2], [1, 1, 14, 2, 14, 2], y_s, O.Found.i(y_ck), O.Found.i(y_cv))
  +y_a: O.Arena = G.CState.ar_of(y_c)
  +y_r: U32 = gv(G.CState.g_of(y_c), O.Found.i(y_ck))
  +h_ck: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(1)})
  +h_cv: O.Found = O.UOp.const(O.Found.ar(h_ck), O.CFloat{FB.F32.from_bits(1)})
  +h_ar: O.Arena = O.Found.ar(h_cv)
  +h_f: O.Found = G.gedge.rop.hasrd([2, 4], h_ar, O.Found.i(h_cv), [2, 4], [1, 1, 14, 2, 14, 2])
  +x_ax: Maybe<&2, List<&2, U32>> = G.gbaxes.of(False{}, [1, 1, 1, 2, 1, 2], [1, 1, 14, 2, 14, 2])
  +s_f: O.Found = O.shape_arg_found(O.Found.ar(h_f), [1, 1, 1, 2, 1, 2])
  +z_f: O.Found = G.cg_edge.rshp(False{}, O.Found.ar(h_f), O.Found.i(h_f), [1, 1, 1, 2, 1, 2])
  +n_ka: O.Found = O.UOp.const(O.Arena.empty(), O.CFloat{FB.F32.from_bits(2)})
  +n_va: O.Found = O.UOp.const(O.Found.ar(n_ka), O.CFloat{FB.F32.from_bits(3)})
  +n_s: G.CState = G.CState{O.Found.ar(n_va), G.Grads{Nil{}, Nil{}}, 0, 0}
  +n_c: G.CState = G.cg_puts.put(n_s, O.Found.i(n_ka), O.Found.i(n_va))
  +n_r: U32 = gv(G.CState.g_of(n_c), O.Found.i(n_ka))
  String.concat(["tsc.reb_store=", U32.show(cnt(qa, ns0, O.OpsSTORE{})),
                 " sh_out=", sh(cha, TP.out(tp)),
                 " sh_lt=", sh(cha, TP.lt(tp)),
                 " sh_g1=", sh(cha, TP.g1(tp)),
                 " gsh_ws=", gshs(cha, TP.ws(tp)),
                 " gsh_mul=", gshs(cha, O.Arena.src0(cha, TP.g1(tp))),
                 " gsh_g1=", gshs(cha, TP.g1(tp)),
                 " sh_g2=", sh(cha, TP.g2(tp)),
                 " sh_w1n=", sh(cha, TP.w1n(tp)),
                 " sh_w2n=", sh(cha, TP.w2n(tp)),
                 " g1=", g1row(cha, TP.g1(tp)),
                 " reb_slots=", slots.go(qa, ns0, Nil{}),
                 " kg_slots=", slots.go(ka, ns, Nil{}),
                 " tsc.kg_n=", U32.show(U32.from_nat(List.length(&2, U32, ns))),
                 " sink_nsrc=", U32.show(O.Arena.nsrc(ka, O.Found.i(k))),
                 " kg_store=", U32.show(cnt(ka, ns, O.OpsSTORE{})),
                 " kg_index=", U32.show(cnt(ka, ns, O.OpsINDEX{})),
                 " kg_red=", U32.show(cnt(ka, ns, O.OpsREDUCE{})),
                 " nk=", U32.show(U32.from_nat(List.length(&2, U32, SCH.lin_kernels(lin)))),
                 " lk=", lk1(SCH.lin_ar(lin), SCH.lin_kernels(lin), Nil{}),
                 " probe=", RF.eng_op_name(O.Arena.op(p_a, p_r)),
                 " peq=", U32.show(Bool.pick(U32, O.eq_u32([1, 1, 1, 2, 1, 2], [1, 1, 14, 2, 14, 2]), 9, 0)),
                 " peqc=", U32.show(Bool.pick(U32, O.eq_u32([1, 1], [1, 1]), 9, 0)),
                 " pnext=", U32.show(O.Arena.next(p_a)),
                 " qprobe=", RF.eng_op_name(O.Arena.op(q_a, q_r)),
                 " qnext=", U32.show(O.Arena.next(q_a)),
                 " wprobe=", RF.eng_op_name(O.Arena.op(w_a, w_r)), " wn=", U32.show(O.Arena.next(w_a)),
                 " yprobe=", RF.eng_op_name(O.Arena.op(y_a, y_r)), " yn=", U32.show(O.Arena.next(y_a)),
                 " bax=", gshs.of(x_ax),
                 " hasrd=", U32.show(O.Found.i(h_f)), " hnext=", U32.show(O.Arena.next(O.Found.ar(h_f))),
                 " hrop=", RF.eng_op_name(O.Arena.op(O.Found.ar(h_f), O.Found.i(h_f))),
                 " sk=", U32.show(O.Found.i(s_f)),
                 " rshp=", U32.show(O.Found.i(z_f)), " zrop=", RF.eng_op_name(O.Arena.op(O.Found.ar(z_f), O.Found.i(z_f))),
                 " nk=", U32.show(O.Found.i(n_ka)), " nv=", U32.show(O.Found.i(n_va)), " nr=", U32.show(n_r),
                 " pk=", U32.show(p_k), " pv=", U32.show(p_v), " pr=", U32.show(p_r),
                 " badg=", badg.go(cha, G.Grads.ks_of(TP.csg(tp)), G.Grads.vs_of(TP.csg(tp)), Nil{}),
                 " dimR=", dshow(O.Found.ar(z_f), O.Found.i(z_f)),
                 " dimRed=", dshow(O.Found.ar(h_f), O.Found.i(h_f)),
                 " dimPer=", dshow(O.Found.ar(h_f), O.Arena.src(O.Found.ar(h_f), O.Found.i(h_f), 0)),
                 " pairs=", pairs.go(cha, G.Grads.ks_of(TP.csg(tp)), G.Grads.vs_of(TP.csg(tp)), Nil{}),
                 " sinkk=", kids.go(ka, O.Arena.srcs(ka, O.Found.i(k)), Nil{}),
                 " afts=", afts.go(ka, O.Arena.srcs(ka, O.Found.i(k)), Nil{}),
                 " skopen=", skgo.go(ka, O.Arena.srcs(ka, O.Found.i(k)), Nil{})])

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["tsc_diag=", diag()]))
    IO.print(String.concat(["tstep_c=", chain_c()]))
