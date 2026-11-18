# .agents/slop/browser/mnist-conv.bend -- conv2d AND max_pool2d AS EXPLICIT UOPS.
#
# conv2d(1->1, 3x3, stride 1, padding 1) on (1,1,28,28) written as NINE TAPS:
# pad, then a SHRINK per tap, times the weight's matching SHRINK, all summed. That is
# upstream's `sum(out, (0,1))` after im2col, spelled without im2col so every node is a
# movement op the port already has (`mxw_pad`/`mxw_shrink`/`tn_mul`/`tn_add`) -- the
# reason `nn_conv2d`'s own graph is walled here is `_pool`'s repeat/shrink/reshape chain,
# not the arithmetic.
#
# max_pool2d(2) on (1,1,28,28) written as FOUR SHRINKS and THREE `tn_maximum`s.
#
# BOTH are rendered through `runtime/device.bend`'s `compile_sink`.
import Base
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX

# A VALID 3x3 CONV (no padding): PAD needs `valid` + `pm_simplify_valid`, which is the
# other half of W3, and SHRINK alone lands first. Output is (1,1,26,26).
# BOTH BUILT THE WAY UPSTREAM BUILDS THEM -- ONE RESHAPE AND ONE REDUCE, NOT N SIBLINGS.
# `_pool` puts the window axes LAST with a reshape, SHRINKs them to one, and reduces MAX
# over them (`tinygrad/mixin/movement.py`'s `_pool`, and `nn_conv2d` does the same with a
# mul and a SUM). The difference is not cosmetic: N siblings of one input give the input
# N consumers, which is `indexing.py:249`'s MERGE branch (`_realize_axis`), and that is a
# different lane from the chain upstream actually produces.
def cn_pool(+x: T.Tensor) -> T.Tensor:
  +r = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +s = MX.mxw_shrink(r, [0, 0, 0, 0, 0, 0], [1, 1, 14, 1, 14, 1])
  +f = T.tn_rop(T.Tensor.ar(s), T.Tensor.u(s), O.OpsMAX{}, [3, 5])
  T.tn_new(O.Found.ar(f), O.Found.i(f))

# conv2d, 3x3, stride 1, NO padding: reshape to (1,1,26,3,26,3), SHRINK the window axes
# to one, times the weight's matching window, summed over the window.
def cn_conv(+x: T.Tensor, +w: T.Tensor) -> T.Tensor:
  +r = MX.mxw_reshape.go(x, [1, 1, 26, 3, 26, 3])
  +s = MX.mxw_shrink(r, [0, 0, 0, 0, 0, 0], [1, 1, 26, 1, 26, 1])
  +wr = MX.mxw_reshape.go(w, [1, 1, 1, 3, 1, 3])
  +m = T.tn_mul(s, wr)
  +f = T.tn_rop(T.Tensor.ar(m), T.Tensor.u(m), O.OpsADD{}, [3, 5])
  T.tn_new(O.Found.ar(f), O.Found.i(f))

# the same realize substitution the fixture uses: dst <- op(inputs)
def pool_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +aft = RZ.rz_after(dst, cn_pool(x))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def conv_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 676, [1, 1, 26, 26])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +w = RZ.rz_input(T.Tensor.ar(x), 2, 9, [1, 1, 3, 3])
  +aft = RZ.rz_after(dst, cn_conv(x, w))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def cn_src(+p: RZ.RZProg) -> String:
  +q = RZ.rz_rebuild(p, False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

# THE RANGEIFIED GRAPH, before the schedule: does the SHRINK consumer carry an
# INDEX(PARAM, ...) at all?
def pool_rr() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +r = RR.rr_run_rangeify(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(r), O.Found.i(r))

def pool_kg() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

# AFTER THE LOWERING PASSES (weak, reduce, alloc->buf): is the input still there?
def pool_low() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = DEV.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ar2 = O.Found.ar(lin)
  +k = SCH.sc_src0(ar2, O.Found.i(lin))
  +b = SCH.sc_src0(ar2, k)
  +l = DEV.body_low(ar2, b)
  RR.rr_dump(O.Found.ar(l), O.Found.i(l))

# THE LINEAR'S KERNELS: each entry's op, then its body root's op. This is the row the
# selection needs -- \`sc_src0(LINEAR)\` is a body only when the first entry IS a kernel.
def pool_lk.go(+ar: O.Arena, +xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: pool_lk.go(ar, t, List.append(&2, String, acc,
      [String.concat([RF.eng_op_name(O.Arena.op(ar, x)), ">",
        RF.eng_op_name(O.Arena.op(ar, SCH.sc_src0(ar, x)))])]))

def pool_lk() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(pool_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

# WHY NO CALL: \`sk_0\` answers no-rewrite when the open-range gate fails or the walk
# refuses something. Both are readable from the END that the split would wrap.
def pool_sk.take(p: (O.Arena & List<&2, U32> & List<&2, U32> & List<&2, U32> & Bool)) -> String:
  (ar, bs, rs, sn, bad) = p
  String.concat(["bufs=", U32.show(U32.from_nat(List.length(&2, U32, bs))),
                 " rngs=", U32.show(U32.from_nat(List.length(&2, U32, rs))),
                 " bad=", Bool.show(bad)])

def pool_sk() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kg)
  +sink = O.Found.i(kg)
  +aft = SCH.sc_src0(ar, sink)
  +end = SCH.sc_src(ar, aft, 1)
  String.concat(["open=", Bool.show(RF.sk_open(ar, end)), " ",
    pool_sk.take(RF.sk_walk(O.Arena.budget(ar), [end], (ar, Nil{}, Nil{}, Nil{}, False{})))])

# WHICH CONJUNCT OF `sk_open` FAILS: `Rng.ok`, or an axis that is not DEVICE?
def pool_rn.ax(+ar: O.Arena, +r: U32) -> String:
  Bool.pick(String, RF.rf_axis_is(ar, r, O.AXIS_DEVICE{}), "D", "L")

def pool_rn.go(+ar: O.Arena, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: pool_rn.go(ar, t, List.append(&2, String, acc, [pool_rn.ax(ar, r)]))

def pool_rn() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kg)
  +aft = SCH.sc_src0(ar, O.Found.i(kg))
  +end = SCH.sc_src(ar, aft, 1)
  +g = F.ranged(ar)
  +r = F.UOp.ranges(F.Ranged.ar(g), F.Ranged.rt(g), end)
  String.concat([Bool.show(F.Rng.ok(r)), "/",
    U32.show(U32.from_nat(List.length(&2, U32, F.Rng.rs(r)))), "/",
    String.join(pool_rn.go(F.Ranged.ar(g), F.Rng.rs(r), Nil{}), "")])

# IDENTITY, NOT COUNT: the arena indices of the END's ended ranges vs its OPEN ranges.
def pool_id.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: pool_id.go(t, List.append(&2, String, acc, [U32.show(x)]))

def pool_ids(+xs: List<&2, U32>) -> String: String.join(pool_id.go(xs, Nil{}), ",")

def pool_id() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kg)
  +aft = SCH.sc_src0(ar, O.Found.i(kg))
  +end = SCH.sc_src(ar, aft, 1)
  +g = F.ranged(ar)
  String.concat(["end=", U32.show(end),
    " srcs=[", pool_ids(O.Arena.srcs(ar, end)), "]",
    " ended=[", pool_ids(Maybe.default(&2, List<&2, U32>, F.UOp.ended_ranges(ar, F.UOp.fold(ar), end), Nil{})), "]",
    " open=[", pool_ids(F.Rng.rs(F.UOp.ranges(F.Ranged.ar(g), F.Ranged.rt(g), end))), "]"])

# EACH RANGE'S OWN IDENTITY: every RANGE in the kernel graph, its extent node, its axis
# id, and its position among the graph's nodes.
def rr_id(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{xs}: pool_ids(xs)
    case _: "-"

def pool_rngs(+ar: O.Arena, +ns: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case n <> t:
      pool_rngs(ar, t, Bool.pick(List<&2, U32>, O.eq_op(O.Arena.op(ar, n), O.OpsRANGE{}),
                                 List.append(&2, U32, acc, [n]), acc))

def pool_ar.go(+rs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t:
      pool_ar.go(t, ar, List.append(&2, String, acc,
        [String.concat([U32.show(r), "[", RR.rr_node_str(ar, O.Arena.src0(ar, r)), ",id=",
          rr_id(O.UOp.axis_id(O.Arena.arg(ar, r))), "]"])]))

def pool_ar(+ar: O.Arena, +ns: List<&2, U32>) -> String:
  String.join(pool_ar.go(pool_rngs(ar, ns, Nil{}), ar, Nil{}), " ")

def pool_ax() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kg)
  pool_ar(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(kg)))

# WHICH SIDE HOLDS WHICH RANGE: the RANGE nodes reachable from the STORE's two srcs.
def pool_side() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kg)
  +aft = SCH.sc_src0(ar, O.Found.i(kg))
  +end = SCH.sc_src(ar, aft, 1)
  +st = O.Arena.src0(ar, end)
  +ns0 = O.UOp.toposort(O.Arena.budget(ar), ar, O.Arena.src0(ar, st))
  +ns1 = O.UOp.toposort(O.Arena.budget(ar), ar, O.Arena.src(ar, st, 1))
  String.concat(["dst=", pool_ids(pool_rngs(ar, ns0, Nil{})),
                 " val=", pool_ids(pool_rngs(ar, ns1, Nil{}))])

# IS THE STORE's VALUE REALIZED BY RULE 3 (a WAR hazard)? `rr_war` is `ix_war_hit`, and
# `UOp.base` there is a NAMED WALL (`ix_base_miss` answers the node itself), so this is the
# rule most likely to fire on a graph that has no hazard at all.
def pool_war() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +sk = RZ.RZProg.sink(q)
  +aft = SCH.sc_src0(ar, sk)
  +end = SCH.sc_src(ar, aft, 1)
  +st = O.Arena.src0(ar, aft)
  +dst = O.Arena.src0(ar, st)
  +val = O.Arena.src(ar, st, 1)
  String.concat(["aft=", RR.rr_node_str(ar, aft), " st=", RR.rr_node_str(ar, st),
                 " isstore=", Bool.show(RR.rr_is_store(ar, st)),
                 " war=", Bool.show(RR.rr_war(ar, st)),
                 " dst=", U32.show(dst), " val=", U32.show(val), "\nrealize=",
                 String.join(RR.rr_real_row.go(IX.IxMap.es(RR.rr_realize(ar, sk)), ar, Nil{}), " ")])

# IS THE REDUCE IN THE RANGE MAP? `rr_ap_red_hit` needs the node in `rngm` and a
# non-zero `num_axes`; the conversion that turns the leading axes into RANGE srcs
# (`indexing.py:131`) is `rr_ap_red_new`, and it never fired.
# THE REDUCE's CONSUMERS, and its `num_axes`: `rr_p1` needs one consumer WITH RANGES for the
# node to enter the range map at all, and `rr_ap_red_hit` needs it there.
def pool_cons() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +sk = RZ.RZProg.sink(q)
  +aft = SCH.sc_src0(ar, sk)
  +st = SCH.sc_src(ar, aft, 1)
  +red = SCH.sc_src(ar, st, 1)
  +topo = O.UOp.toposort(O.Arena.budget(ar), ar, sk)
  String.concat(["num=", U32.show(RR.rr_ap_red_num(ar, red)),
                 " cons=", pool_ids(RR.rr_cons(ar, topo, red)),
                 " rdop=", RR.rr_node_str(ar, red)])

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["pool_rr=", pool_rr()]))
    _ : Unit <- IO.print(String.concat(["pool_kg=", pool_kg()]))
    _ : Unit <- IO.print(String.concat(["pool_cons=", pool_cons()]))
    _ : Unit <- IO.print(String.concat(["pool_war=", pool_war()]))
    _ : Unit <- IO.print(String.concat(["pool_side=", pool_side()]))
    _ : Unit <- IO.print(String.concat(["pool_ax=", pool_ax()]))
    _ : Unit <- IO.print(String.concat(["pool_id=", pool_id()]))
    _ : Unit <- IO.print(String.concat(["pool_rn=", pool_rn()]))
    _ : Unit <- IO.print(String.concat(["pool_sk=", pool_sk()]))
    _ : Unit <- IO.print(String.concat(["pool_lk=", pool_lk()]))
    _ : Unit <- IO.print(String.concat(["pool_low=", pool_low()]))
    _ : Unit <- IO.print(String.concat(["pool_c=", cn_src(pool_prog())]))
    IO.print(String.concat(["conv_c=", cn_src(conv_prog())]))
