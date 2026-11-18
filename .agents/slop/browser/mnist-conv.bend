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
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/weak.bend as WK
import ./../../../tinybendygrad/codegen/kernel.bend as KR

# A VALID 3x3 CONV (no padding): PAD needs `valid` + `pm_simplify_valid`, which is the
# other half of W3, and SHRINK alone lands first. Output is (1,1,26,26).
# BOTH BUILT THE WAY UPSTREAM BUILDS THEM -- ONE RESHAPE AND ONE REDUCE, NOT N SIBLINGS.
# `_pool` puts the window axes LAST with a reshape, SHRINKs them to one, and reduces MAX
# over them (`tinygrad/mixin/movement.py`'s `_pool`, and `nn_conv2d` does the same with a
# mul and a SUM). The difference is not cosmetic: N siblings of one input give the input
# N consumers, which is `indexing.py:249`'s MERGE branch (`_realize_axis`), and that is a
# different lane from the chain upstream actually produces.
# NO SHRINK, AND THAT IS THE WHOLE OF IT: `_rop` drops an axis whose extent is 1
# (`ops.py:627`: `reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1))`), so
# a shrink-to-1 followed by a reduce over those axes is NOT a reduce -- MEASURED, the
# port's `tn_rop` then answers `AReduce{MAX, 0}` with no range srcs, which lowers to ONE
# accumulate and an input read at a constant address (`data1_784+0`). Upstream's `_pool`
# keeps the window axes at their real extent and reduces over THEM.
def cn_pool(+x: T.Tensor) -> T.Tensor:
  +r = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +f = T.tn_rop(T.Tensor.ar(r), T.Tensor.u(r), O.OpsMAX{}, [3, 5])
  T.tn_new(O.Found.ar(f), O.Found.i(f))

# THE CONV, AND ITS WINDOW IS 2x2 AND NOT 3x3, BECAUSE A 3x3 WINDOW IS NOT A RESHAPE.
# `reshape((1,1,28,28) -> (1,1,26,3,26,3))` is 784 elements into 6084 -- it is not a view
# at all, and the port's shape fold answers `none` for it (MEASURED, .agents/slop/browser/
# rop.rows: `dr=none` for that reshape, `dw=6` for the weight's). Upstream's 3x3 conv is
# `_pool` over an EXPAND/PAD chain (its trace is `EXPAND(3,3,1,1,28,28)` then a
# RESHAPE `(1,1,2,29,2,29)`), which is W3's PAD half -- not ported. A 2x2, stride-2 window
# IS a clean reshape (28 = 14*2), so the conv's ARITHMETIC -- a windowed MUL and a SUM
# reduce over the window axes -- is exercised here without padding, and the 3x3 case is
# recorded as blocked on PAD rather than on the reduce.
def cn_conv(+x: T.Tensor, +w: T.Tensor) -> T.Tensor:
  +r = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +wr = MX.mxw_reshape.go(w, [1, 1, 1, 2, 1, 2])
  +m = T.tn_mul(r, wr)
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
  +dst = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +w = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
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

# THE LINEARISED KU ORDER FOR THE POOL: where the init store, the reduce loop and the
# update store sit, and what the init store's VALUE is.
def pc_op(+k: C.KU) -> String: RF.eng_op_name(C.KU.op(k))

def pc_sig.go(+ks: List<&2, C.KU>, +i: U32, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: pc_sig.go(t, U32.add(i, 1), List.append(&2, String, acc, [String.concat([U32.show(i), ":", pc_op(k)])]))

def pc_arg.a(a: C.KUArg) -> String:
  match a:
    case C.KAConst{v}: String.concat(["const=", C.ku_const_repr(v)])
    case _: "arg=-"

def pc_arg(+k: C.KU) -> String: pc_arg.a(C.KU.arg(k))

def pc_sig2.go(+ks: List<&2, C.KU>, +i: U32, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      pc_sig2.go(t, U32.add(i, 1),
        Bool.pick(List<&2, String>, Bool.or(O.eq_op(C.KU.op(k), O.OpsCONST{}), O.eq_op(C.KU.op(k), O.OpsSTORE{})),
          List.append(&2, String, acc, [String.concat([U32.show(i), ":", pc_op(k), "@", pc_arg(k)])]), acc))

def pc_pair(p: (O.Arena & List<&2, C.KU>)) -> String:
  (ar, +kus) = p
  String.concat([String.join(pc_sig.go(kus, 0, Nil{}), " "),
                 " |args ", String.join(pc_sig2.go(kus, 0, Nil{}), " ")])

def pool_ku() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +a2 = SCH.lin_ar(lin)
  pc_pair(DEV.body_kus(a2, SCH.sc_src0(a2, Maybe.default(&2, U32, List.head(&2, U32, SCH.lin_kernels(lin)), 0))))

# THE LOWERED BODY, DUMPED: what is the init STORE's src[1]?
def pool_low2() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +a2 = SCH.lin_ar(lin)
  +k = SCH.sc_src0(a2, Maybe.default(&2, U32, List.head(&2, U32, SCH.lin_kernels(lin)), 0))
  +l = DEV.body_low(a2, SCH.sc_src0(a2, k))
  RR.rr_dump(O.Found.ar(l), O.Found.i(l))

# WHICH PASS TURNS THE INIT STORE'S VALUE FROM A CONST INTO A BUFFER?
# the FIRST store in the body whose dst is not a buffer-index, and its value's op.
def pc_val.rw(+ar: O.Arena, +ns: List<&2, U32>, acc: String) -> String:
  match ns:
    case Nil{}: acc
    case x <> t:
      pc_val.rw(ar, t, Bool.pick(String, O.eq_op(O.Arena.op(ar, x), O.OpsSTORE{}),
        String.concat([RF.eng_op_name(O.Arena.op(ar, x)), "(", RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, x))), ",",
                       RF.eng_op_name(O.Arena.op(ar, O.Arena.src(ar, x, 1))), ")" ]), acc))

def pc_val(+ar: O.Arena, +f: O.Found) -> String:
  pc_val.rw(O.Found.ar(f), O.UOp.toposort(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)), "")

def pc_seq(n: U32, +ar: O.Arena, +b: U32) -> String:
  match n:
    case 0: pc_val(ar, WK.wk_commit(ar, b))
    case 1: pc_val(ar, KR.lower_reduce_all(ar, b))
    case 2: pc_val(ar, DEV.late_apply(ar, b))
    case _: pc_val(ar, KR.alloc_to_buf_all(ar, b))

def pc_stage(n: U32) -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +a2 = SCH.lin_ar(lin)
  +k = SCH.sc_src0(a2, Maybe.default(&2, U32, List.head(&2, U32, SCH.lin_kernels(lin)), 0))
  pc_seq(n, a2, SCH.sc_src0(a2, k))

# IS THE -inf IDENTITY IN THE LOWERED BODY AT ALL?
def pc_isfloat(a: O.Arg) -> Bool:
  match a:
    case O.APy{O.CFloat{f}}: True{}
    case _: False{}

def pc_cnt.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t:
      pc_cnt.go(ar, t, Bool.pick(U32, Bool.and(O.eq_op(O.Arena.op(ar, x), O.OpsCONST{}), pc_isfloat(O.Arena.arg(ar, x))),
                                 U32.add(acc, 1), acc))

def pc_cnt(+ar: O.Arena, +f: O.Found) -> U32:
  pc_cnt.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(f)), 0)

def pool_fcnt() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +a2 = SCH.lin_ar(lin)
  +k = SCH.sc_src0(a2, Maybe.default(&2, U32, List.head(&2, U32, SCH.lin_kernels(lin)), 0))
  +before = pc_cnt(a2, DEV.body_low(a2, SCH.sc_src0(a2, k)))
  +after = pc_cnt(O.Found.ar(DEV.body_low(a2, SCH.sc_src0(a2, k))), DEV.body_low(a2, SCH.sc_src0(a2, k)))
  String.concat(["fcnt_after_low=", U32.show(before), "/", U32.show(after)])

def pc_lr2(m: Maybe<&2, O.Found>, red: U32) -> String:
  match m:
    case Some{+f}:
      String.concat(["red=", U32.show(red), " fcnt=", U32.show(pc_cnt(O.Found.ar(f), f)),
                     " dump=", RR.rr_dump(O.Found.ar(f), O.Found.i(f))])
    case None{}: String.concat(["red=", U32.show(red), " NONE"])

# `lower_reduce` ON THE REAL NODE: does its answer carry the -inf const?
def pc_firstred.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t:
      pc_firstred.go(ar, t, Bool.pick(U32, Bool.and(U32.is_eq(acc, 0), O.eq_op(O.Arena.op(ar, x), O.OpsREDUCE{})), x, acc))

def pc_lr() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +a2 = SCH.lin_ar(lin)
  +k = SCH.sc_src0(a2, Maybe.default(&2, U32, List.head(&2, U32, SCH.lin_kernels(lin)), 0))
  +body = WK.wk_commit(a2, SCH.sc_src0(a2, k))
  +ar = O.Found.ar(body)
  +red = pc_firstred.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(body)), 0)
  pc_lr2(KR.lower_reduce(ar, red), red)

# THE CONV'S KERNEL GRAPH AND ITS LINEAR'S KERNEL LIST, the same two rows that found the
# pool's missing CALL.
def cv_kg() -> String:
  +q = RZ.rz_rebuild(conv_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

def cv_lk.go(+ar: O.Arena, +xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: cv_lk.go(ar, t, List.append(&2, String, acc,
      [String.concat([RF.eng_op_name(O.Arena.op(ar, x)), ">", RF.eng_op_name(O.Arena.op(ar, SCH.sc_src0(ar, x)))])]))

def cv_lk() -> String:
  +q = RZ.rz_rebuild(conv_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(cv_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

# THE SPATIAL STACK OF THE FORWARD PASS, AS ONE KERNEL: conv2x2 -> ReLU -> max_pool2x2.
# (1,1,28,28) -conv-> (1,1,14,14) -relu-> (1,1,14,14) -pool-> (1,1,7,7) = 49 elements.
# `T.tn_relu` is the port's own (tensor.bend:508), i.e. `maximum(t, 0)`, which is the ALU MAX
# the late table rewrites into CMPLT+WHERE.
def fw_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 49, [1, 1, 7, 7])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +w = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +aft = RZ.rz_after(dst, cn_pool(T.tn_relu(cn_conv(x, w))))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def fw_c() -> String:
  +q = RZ.rz_rebuild(fw_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

def fw_kg() -> String:
  +q = RZ.rz_rebuild(fw_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

def fw_lk.go(+ar: O.Arena, +xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: fw_lk.go(ar, t, List.append(&2, String, acc,
      [String.concat([RF.eng_op_name(O.Arena.op(ar, x)), ">", RF.eng_op_name(O.Arena.op(ar, SCH.sc_src0(ar, x)))])]))

def fw_lk() -> String:
  +q = RZ.rz_rebuild(fw_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(fw_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

# THE STORE's RANGE-MAP ENTRY, for the pool (WORKS) and for the fused stack (does not). The
# value's entry is printed beside it: in the pool it is a REDUCE, in fw a WHERE over one.
def st_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  +sk = RZ.RZProg.sink(pr)
  +st = SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1)
  +v = SCH.sc_src(ar, st, 1)
  String.concat(["st(", RR.rr_node_str(ar, st), ": ", RR.rr_rngm_row(ar, sk, st),
                 ") v(", RR.rr_node_str(ar, v), ": ", RR.rr_rngm_row(ar, sk, v), ")"])

# THE REALIZE MAP ITSELF: a STORE not in it takes `rr_p1.none` and its entry is empty.
def rl_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  +sk = RZ.RZProg.sink(pr)
  String.join(RR.rr_real_row.go(IX.IxMap.es(RR.rr_realize(ar, sk)), ar, Nil{}), " ")

# THE STORE's FOLD SHAPE -- `rr_p1.real` mints one range per dim of it, so an empty answer
# means an empty OUT and therefore no END.
def sd_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  +sk = RZ.RZProg.sink(pr)
  +st = SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1)
  +dst = SCH.sc_src0(ar, st)
  +tb = F.Folded.t(F.folded(ar))
  String.concat(["dst=", RR.rr_node_str(ar, dst),
                 " dst_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, dst)),
                 " st_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, st))])

# DOES THE FOLD TRUNCATE? `Kahn.run` returns a PARTIAL table when its fuel runs out, and the
# fuel is `next + edges` -- so a graph with more work than that leaves a suffix UNKNOWN.
def fd_shape.m(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Bool:
  match m:
    case Some{Some{ds}}: True{}
    case _: False{}

def fd_shape(+ar: O.Arena, +tb: F.Table, +n: U32) -> Bool: fd_shape.m(F.fold.shape(ar, tb, n))

def fd_cnt.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t: fd_cnt.go(ar, tb, t, Bool.pick(U32, fd_shape(ar, tb, x), U32.add(acc, 1), acc))

def fd_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  +sk = RZ.RZProg.sink(pr)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sk)
  +tb = F.folded(ar)
  String.concat(["nodes=", U32.show(U32.from_nat(List.length(&2, U32, ns))),
                 " shaped=", U32.show(fd_cnt.go(F.Folded.ar(tb), F.Folded.t(tb), ns, 0)),
                 " next=", U32.show(O.Arena.next(ar)), " edges=", U32.show(O.Arena.edges(ar))])

def rm_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  RR.rr_rmap_row(ar, RZ.RZProg.sink(pr))

# DOES THE EXPAND-REALIZE CLAUSE (`indexing.py:288`) FIRE? `rr_p3.exp` adds the ranges an
# all-int-shape EXPAND broadcasts over, so its PRODUCER inherits a non-empty ending_ranges and
# `rr_p2` realizes the producer. The pool output has a unit axis, so broadcasting it is a legal
# EXPAND and it is the smallest graph that exercises the clause.
def xp_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 392, [2, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  # `marg` FOR `EXPAND` IS THE NEW LEADING DIMS, NOT THE FULL TARGET (`ops.py:412`'s
  # `_shape` is `tuple(self.marg) + ps`, and `apply_movement_op`'s arm is
  # `rngs = rngs[len(arg):]`). Passing the full shape makes `len(arg) == len(rngs)` and the
  # slice removes EVERYTHING -- MEASURED, that is the empty `inp` in the row above.
  +aft = RZ.rz_after(dst, MX.mxw_expand(cn_pool(x), [2]))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def xp_lk() -> String:
  +q = RZ.rz_rebuild(xp_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(fw_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

def xp_kg() -> String:
  +q = RZ.rz_rebuild(xp_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

# THE STAGED NODE's OWN ENTRY: `rr_ap_stage_src` builds `STAGE(s, *closed)` from the value's
# OUT positions, so an empty `out` is a one-src STAGE -- and `bufferize_to_store`'s pattern is a
# STRICT TWO-SRC stage.
def xp_val_row() -> String:
  +ar = RZ.RZProg.ar(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +sk = RZ.RZProg.sink(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +st = SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1)
  +v = SCH.sc_src(ar, st, 1)
  +o = SCH.sc_src0(ar, v)
  String.concat(["v=", RR.rr_node_str(ar, v), " [", RR.rr_rngm_row(ar, sk, v), "]",
                 " src0=", RR.rr_node_str(ar, o), " [", RR.rr_rngm_row(ar, sk, o), "]"])

# THE EXPAND's SHAPE: upstream's `_shape` for EXPAND is `marg ++ src_shape` (ops.py:412), so
# `apply_movement_op`'s `rngs[len(arg):]` leaves the source's part. If the fold answers only
# the target shape, that slice removes EVERYTHING -- which is the empty `inp` measured above.
def xp_dims() -> String:
  +ar = RZ.RZProg.ar(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +sk = RZ.RZProg.sink(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +tb = F.Folded.t(F.folded(ar))
  +v = SCH.sc_src(ar, SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1), 1)
  +s0 = SCH.sc_src0(ar, v)
  String.concat(["v_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, v)),
                 " marg=", RR.rr_dims_str(RR.rr_marg(ar, v)),
                 " src_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, s0)),
                 " nsrc=", U32.show(O.Arena.nsrc(ar, v))])

# IS THE CLOSED LIST ONE ENTRY PER DIM? `flatten_bufferize` zips `x.shape` with the STAGE's
# closed srcs, so a short list would make the collapse wrong rather than merely absent.
def xp_len() -> String:
  +ar = RZ.RZProg.ar(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +sk = RZ.RZProg.sink(RZ.rz_rebuild(xp_prog(), False{}, False{}))
  +tb = F.Folded.t(F.folded(ar))
  +v = SCH.sc_src(ar, SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1), 1)
  +r = SCH.sc_src0(ar, v)
  String.concat(["red_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, r)),
                 " n=", U32.show(U32.from_nat(List.length(&2, U32, IX.rr_dims(ar, tb, r)))),
                 " out=", RR.rr_rngm_row(ar, sk, r)])

# `rr_new.all` ON THE REDUCE'S OWN DIMS: one entry per dim, or not?
def nw_row() -> String:
  +n = RR.rr_new.all([1, 1, 14, 14], [IX.ix_rg_c0()], Nil{})
  String.concat(["rs=", RR.rr_dims_str(RR.RrRs.rs(n)),
                 " tbl=", U32.show(U32.from_nat(List.length(&2, IX.IxRange, RR.RrRs.tbl(n))))])

def tp_uniq.go(+ns: List<&2, U32>, +seen: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case x <> t:
      tp_uniq.go(t, seen, Bool.pick(List<&2, U32>, F.mem_u32(seen, x), acc,
        List.append(&2, U32, acc, [x])))

def tp_uniq(+ns: List<&2, U32>, +seen: List<&2, U32>) -> List<&2, U32>: tp_uniq.go(ns, seen, Nil{})

# DOES THE TOPOSORT YIELD A NODE TWICE? The `ends` flag list is indexed by POSITION in the
# reversed toposort, so a duplicate shifts every position after it -- and it would also explain
# `rr_cons` answering 32 consumers for a node with one.
def tp_row(+pr: RZ.RZProg) -> String:
  +ar = RZ.RZProg.ar(pr)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, RZ.RZProg.sink(pr))
  +u = tp_uniq(ns, Nil{})
  String.concat(["n=", U32.show(U32.from_nat(List.length(&2, U32, ns))),
                 " uniq=", U32.show(U32.from_nat(List.length(&2, U32, u)))])

# THE WINDOW BROADCAST upstream's own chains carry: `EXPAND (3,3,1,1,28,28)`, i.e. marg
# `(3,3)` over a `(1,1,28,28)` source -- a SIX-dim `_shape` whose trailing part is the whole
# source. (The `xp` probe above is a BATCH broadcast and produces a shape/range mismatch that
# CPython truncates on too, so it cannot be the shape to tune `flatten_bufferize` against.)
def xw_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 784, [1, 1, 28, 28])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +e = MX.mxw_expand(x, [3, 3])
  +f = T.tn_rop(T.Tensor.ar(e), T.Tensor.u(e), O.OpsADD{}, [0, 1])
  +v = T.tn_new(O.Found.ar(f), O.Found.i(f))
  +aft = RZ.rz_after(dst, v)
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def xw_row() -> String:
  +ar = RZ.RZProg.ar(RZ.rz_rebuild(xw_prog(), False{}, False{}))
  +sk = RZ.RZProg.sink(RZ.rz_rebuild(xw_prog(), False{}, False{}))
  +tb = F.Folded.t(F.folded(ar))
  +st = SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1)
  +v = SCH.sc_src(ar, st, 1)
  +r = SCH.sc_src0(ar, v)
  String.concat(["rm=", rm_row(RZ.rz_rebuild(xw_prog(), False{}, False{})),
                 " red_dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, r)),
                 " red=", RR.rr_rngm_row(ar, sk, r),
                 " kg=", RR.rr_dump(O.Found.ar(RR.rr_kernel_graph(ar, sk)), O.Found.i(RR.rr_kernel_graph(ar, sk)))])

def xw_c() -> String:
  +q = RZ.rz_rebuild(xw_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

def xw_lk() -> String:
  +q = RZ.rz_rebuild(xw_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(fw_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

# THE TWO-KERNEL FORWARD CHAIN, BUILT IN STAGES SO EACH TYPE IS CHECKED BEFORE THE NEXT: a
# window sum into a hidden buffer, then a linear layer that reads that buffer. `h`'s node
# index stays valid in the after-chain's arena because an augmented arena is a superset.
def fwd_prog() -> RZ.RZProg:
  # ONE CHAIN, NO FORKS: every `rz_input` takes the PREVIOUS tensor's arena, and the AFTERs are
  # built last. MEASURED: two `rz_input`s on the SAME arena are two SIBLING copies whose node
  # indices collide, which is what made the weight fold to a lone CONST.
  +h = RZ.rz_input(O.Arena.empty(), 0, 784, [1, 1, 28, 28])
  +o = RZ.rz_input(T.Tensor.ar(h), 2, 10, [1, 10])
  +x = RZ.rz_input(T.Tensor.ar(o), 1, 784, [1, 1, 28, 28])
  +w = RZ.rz_input(T.Tensor.ar(x), 3, 7840, [784, 10])
  +e = MX.mxw_expand(x, [3, 3])
  +f1 = T.tn_rop(T.Tensor.ar(e), T.Tensor.u(e), O.OpsADD{}, [0, 1])
  +a1 = RZ.rz_after(h, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  # THE REAL READ: the hidden buffer through its AFTER. The control (a PARAM-shaped view on slot 5)
  # is what proved the AFTER was the blocker; with `handle_after` ported this must split too.
  +hf = T.tn_new(O.Found.ar(a1), O.Found.i(a1))
  +lhs = MX.mxw_reshape.go(hf, [1, 1, 784])
  +rhs = MX.mxw_permute.go(MX.mxw_reshape.go(w, [1, 784, 10]), [0, 2, 1])
  +m = T.tn_mul(lhs, rhs)
  +f2 = T.tn_rop(T.Tensor.ar(m), T.Tensor.u(m), O.OpsADD{}, [2])
  +a2 = RZ.rz_after(o, T.tn_new(O.Found.ar(f2), O.Found.i(f2)))
  +snk = O.UOp.sink(O.Found.ar(a2), [O.Found.i(a1), O.Found.i(a2)])
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def mk_emit(p: (O.Arena & List<&2, C.KU>), +i: U32, +acc: List<&2, String>) -> (O.Arena & List<&2, String>):
  (ar, +kus) = p
  (ar, List.append(&2, String, acc,
        [String.concat(["--k", U32.show(i), ":", DEV.Prog.src(DEV.program("k", kus))])]))

def mk_step(p: (O.Arena & List<&2, String>), +k: U32, +i: U32) -> (O.Arena & List<&2, String>):
  (+ar, +acc) = p
  mk_emit(DEV.body_kus(ar, k), i, acc)

def mk_one.go(+ks: List<&2, U32>, p: (O.Arena & List<&2, String>), +i: U32) -> (O.Arena & List<&2, String>):
  match ks:
    case Nil{}: p
    case k <> t: mk_one.go(t, mk_step(p, k, i), U32.add(i, 1))

def mk_fin(p: (O.Arena & List<&2, String>)) -> String:
  (ar, acc) = p
  String.join(acc, "\n")

def fwd_c() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  mk_fin(mk_one.go(SCH.lin_kernels(lin), (SCH.lin_ar(lin), Nil{}), 0))

def fwd_lk() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(fw_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

def fwd_kg() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

# WHY `flatten_bufferize` DOES NOT FIRE: the guard, the counts, and the reshape's own answer,
# measured on the PRE-ENGINE graph (the engine runs after it).
def fbd_find.go(+ar: O.Arena, +ns: List<&2, U32>, +acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t:
      fbd_find.go(ar, t, Bool.pick(U32, Bool.and(U32.is_zero(acc), O.eq_op(O.Arena.op(ar, x), O.OpsSTAGE{})), x, acc))

def fbd_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kb = RR.rr_run_rangeify(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kb)
  +tb = F.Folded.t(F.folded(ar))
  +st = fbd_find.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(kb)), 0)
  String.concat(["st=", RR.rr_node_str(ar, st),
                 " closed=", U32.show(RF.fb_closed(ar, st)),
                 " vdims=", U32.show(U32.from_nat(List.length(&2, U32, RF.fb_vdims(ar, tb, st)))),
                 " guard=", Bool.show(RF.fb_ok.guard(ar, tb, st))])

# A SHAPE WALK: every node reachable from the staged value, with the dims the fold answers.
# The FIRST node with none is where the chain breaks.
def sw_rows.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      sw_rows.go(ar, tb, t, List.append(&2, String, acc,
        [String.concat([RR.rr_node_str(ar, x), " dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, x))])]))

def sw_row() -> List<&2, String>:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kb = RR.rr_run_rangeify(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kb)
  +tb = F.Folded.t(F.folded(ar))
  +st = fbd_find.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(kb)), 0)
  +v = O.Arena.src0(ar, st)
  sw_rows.go(ar, tb, O.UOp.toposort(O.Arena.budget(ar), ar, v), Nil{})

# UNKNOWN vs EMPTY: `rr_dims` answers `[]` for BOTH, so the shape's OWN Maybe is printed.
def sh_kind.m(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{Some{ds}}: String.concat(["dims=", U32.show(U32.from_nat(List.length(&2, O.Sint, ds)))])
    case Some{None{}}: "SHAPE-NONE"
    case None{}: "UNKNOWN"

def sh_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +kb = RR.rr_run_rangeify(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +ar = O.Found.ar(kb)
  +tb = F.Folded.t(F.folded(ar))
  +st = fbd_find.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(kb)), 0)
  +v = O.Arena.src0(ar, st)
  +rd = O.Arena.src0(ar, v)
  +sk = O.Found.i(kb)
  String.concat(["v=", RR.rr_node_str(ar, v), " ", sh_kind.m(F.fold.shape(ar, tb, v)), "[", RR.rr_rngm_row(ar, sk, v), "]",
                 " | RED=", RR.rr_node_str(ar, rd), " ", sh_kind.m(F.fold.shape(ar, tb, rd)), "[", RR.rr_rngm_row(ar, sk, rd), "]",
                 " | RD.src0=", RR.rr_node_str(ar, O.Arena.src0(ar, rd)), " ", sh_kind.m(F.fold.shape(ar, tb, O.Arena.src0(ar, rd))), "[", RR.rr_rngm_row(ar, sk, O.Arena.src0(ar, rd)), "]"])

# THE PRE-APPLY value of the SECOND store: is it already scalar BEFORE rangeify touches it?
# (The rngm rows above were measured against the POST-apply root -- `tbl=3` says so -- and are
# therefore junk; this row reads the tensor graph only.)
def pv_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +tb = F.Folded.t(F.folded(ar))
  +sk = RZ.RZProg.sink(q)
  +aft2 = SCH.sc_src(ar, sk, 1)
  +st2 = SCH.sc_src(ar, aft2, 1)
  +v2 = SCH.sc_src(ar, st2, 1)
  String.concat(["aft2=", RR.rr_node_str(ar, aft2), " dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, aft2)),
                 " | st2=", RR.rr_node_str(ar, st2), " dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, st2)),
                 " | v2=", RR.rr_node_str(ar, v2), " dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, v2))])

# THE CORRECTLY-WIRED COMPARISON: the range map of the PRE-APPLY sink, for the pre-apply value
# and its two INDEX srcs -- what `rr_ap_bcast` will hand the index builder.
def pm_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +sk = RZ.RZProg.sink(q)
  +aft2 = SCH.sc_src(ar, sk, 1)
  +st2 = SCH.sc_src(ar, aft2, 1)
  +v2 = SCH.sc_src(ar, st2, 1)
  +m = SCH.sc_src0(ar, v2)
  String.concat(["st2[", RR.rr_rngm_row(ar, sk, st2), "]",
                 " v2[", RR.rr_rngm_row(ar, sk, v2), "]",
                 " v2.src0[", RR.rr_rngm_row(ar, sk, m), "]",
                 " v2.src0.src0[", RR.rr_rngm_row(ar, sk, SCH.sc_src0(ar, m)), "]"])

# EVERY STORE IN THE PRE-APPLY GRAPH, identified BY ITS DST rather than by sink position:
# dst dims, its range-map entry, and the value's dims.
def st_rows.go(+ar: O.Arena, +tb: F.Table, +sk: U32, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      st_rows.go(ar, tb, sk, t, Bool.pick(List<&2, String>, O.eq_op(O.Arena.op(ar, x), O.OpsSTORE{}),
        List.append(&2, String, acc,
          [String.concat(["dst=", RR.rr_dims_str(IX.rr_dims(ar, tb, O.Arena.src0(ar, x))),
                          " val=", RR.rr_dims_str(IX.rr_dims(ar, tb, O.Arena.src(ar, x, 1))),
                          "[", RR.rr_rngm_row(ar, sk, x), "]"])]), acc))

def st_rows() -> List<&2, String>:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +tb = F.Folded.t(F.folded(ar))
  +sk = RZ.RZProg.sink(q)
  st_rows.go(ar, tb, sk, O.UOp.toposort(O.Arena.budget(ar), ar, sk), Nil{})

def sk_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  RR.rr_dump(RZ.RZProg.ar(q), RZ.RZProg.sink(q))

# THE BUFFER NODE ITSELF: `mxw_buf` mints it as `O.UOp.new.param(ar, BUFFER, Some{size}, ...)`
# (`movement.bend:1109`) with NO srcs supplied. If that `Some{size}` is the ARITY, every buffer is
# a node whose src list is longer than what the arena holds.
def buf_row() -> String:
  +t1 = RZ.rz_input(O.Arena.empty(), 2, 10, [1, 10])
  +b1 = SCH.sc_src0(T.Tensor.ar(t1), T.Tensor.u(t1))
  +t2 = RZ.rz_input(T.Tensor.ar(t1), 3, 7840, [784, 10])
  +b2 = SCH.sc_src0(T.Tensor.ar(t2), T.Tensor.u(t2))
  String.concat(["b10=", RR.rr_node_str(T.Tensor.ar(t1), T.Tensor.u(t1)),
                 " nsrc=", U32.show(O.Arena.nsrc(T.Tensor.ar(t1), T.Tensor.u(t1))),
                 " buf=", RR.rr_node_str(T.Tensor.ar(t1), b1),
                 " buf_nsrc=", U32.show(O.Arena.nsrc(T.Tensor.ar(t1), b1)),
                 " | b7840 buf_nsrc=", U32.show(O.Arena.nsrc(T.Tensor.ar(t2), b2))])

# `T.Tensor.u(o)` AGAINST `Arena.src0(the second store)` -- the two numbers the last commit named.
# This REPEATS the fixture's tail, because the ids are what is in question.
def fwd_ids() -> String:
  +h = RZ.rz_input(O.Arena.empty(), 0, 784, [1, 1, 28, 28])
  +x = RZ.rz_input(T.Tensor.ar(h), 1, 784, [1, 1, 28, 28])
  +e = MX.mxw_expand(x, [3, 3])
  +f1 = T.tn_rop(T.Tensor.ar(e), T.Tensor.u(e), O.OpsADD{}, [0, 1])
  +a1 = RZ.rz_after(h, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  +o = RZ.rz_input(O.Found.ar(a1), 2, 10, [1, 10])
  # THE REAL READ: the hidden buffer through its AFTER. The control (a PARAM-shaped view on slot 5)
  # is what proved the AFTER was the blocker; with `handle_after` ported this must split too.
  +hf = T.tn_new(O.Found.ar(a1), O.Found.i(a1))
  # THE ARENA MUST BE CHAINED, NOT FORKED: `o` was built on `a1`'s arena and returned a GROWN one,
  # and building `w` on `a1`'s again made the two SIBLING copies -- `o`'s nodes and `w`'s nodes then
  # occupied the same indices, and the MUL mixed them (MEASURED: the weight folded to a lone CONST).
  +w = RZ.rz_input(T.Tensor.ar(o), 3, 7840, [784, 10])
  +lhs = MX.mxw_reshape.go(hf, [1, 1, 784])
  +rhs = MX.mxw_permute.go(MX.mxw_reshape.go(w, [1, 784, 10]), [0, 2, 1])
  +m = T.tn_mul(lhs, rhs)
  +f2 = T.tn_rop(T.Tensor.ar(m), T.Tensor.u(m), O.OpsADD{}, [2])
  +a2 = RZ.rz_after(o, T.tn_new(O.Found.ar(f2), O.Found.i(f2)))
  +ar = O.Found.ar(a2)
  +st = O.Arena.src(ar, O.Found.i(a2), 1)
  String.concat(["o_u=", U32.show(T.Tensor.u(o)), " o=", RR.rr_node_str(ar, T.Tensor.u(o)),
                 " | w_u=", U32.show(T.Tensor.u(w)), " w=", RR.rr_node_str(ar, T.Tensor.u(w)),
                 " | st=", RR.rr_node_str(ar, st),
                 " st.src0_u=", U32.show(O.Arena.src0(ar, st)),
                 " st.src0=", RR.rr_node_str(ar, O.Arena.src0(ar, st)),
                 " | w_sub=", RR.rr_dump(ar, T.Tensor.u(w)),
                 " | o_sub=", RR.rr_dump(ar, T.Tensor.u(o))])

# `mxw_buf` AND `mxw_reshape.go`, EACH ON ITS OWN, for the weight's slot and size.
def mb_row() -> String:
  +ar = O.Arena.empty()
  +b = MX.mxw_buf(ar, 3, 7840)
  +r = MX.mxw_reshape.go(b, [784, 10])
  String.concat(["buf_u=", U32.show(T.Tensor.u(b)), " buf=", RR.rr_node_str(T.Tensor.ar(b), T.Tensor.u(b)),
                 " buf_dump=", RR.rr_dump(T.Tensor.ar(b), T.Tensor.u(b)),
                 " | res_u=", U32.show(T.Tensor.u(r)), " res=", RR.rr_node_str(T.Tensor.ar(r), T.Tensor.u(r)),
                 " res_dump=", RR.rr_dump(T.Tensor.ar(r), T.Tensor.u(r))])

# `rz_input(..., [1,10])` ON AN EMPTY ARENA BESIDE THE SAME CALL ON A NON-EMPTY ONE. If the second
# answers a bare BUFFER where the first answers a RESHAPE, the suspect is `mxw_stk`'s shape STACK.
def rz_row() -> String:
  +t1 = RZ.rz_input(O.Arena.empty(), 2, 10, [1, 10])
  +t2 = RZ.rz_input(T.Tensor.ar(t1), 2, 10, [1, 10])
  +t3 = RZ.rz_input(T.Tensor.ar(t2), 2, 10, [1, 10])
  String.concat(["empty=", RR.rr_node_str(T.Tensor.ar(t1), T.Tensor.u(t1)), " {", RR.rr_dump(T.Tensor.ar(t1), T.Tensor.u(t1)), "}",
                 " after1=", RR.rr_node_str(T.Tensor.ar(t2), T.Tensor.u(t2)), " {", RR.rr_dump(T.Tensor.ar(t2), T.Tensor.u(t2)), "}",
                 " after2=", RR.rr_node_str(T.Tensor.ar(t3), T.Tensor.u(t3)), " {", RR.rr_dump(T.Tensor.ar(t3), T.Tensor.u(t3)), "}"])

# THE REDUCE's num_axes AND ITS RANGE MAP ENTRY, PRE-APPLY, for the linear's reduce.
def rd_row.go(+ar: O.Arena, +ns: List<&2, U32>, acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t: rd_row.go(ar, t, Bool.pick(U32, O.eq_op(O.Arena.op(ar, x), O.OpsREDUCE{}), x, acc))

def rd_row() -> String:
  +q = RZ.rz_rebuild(fwd_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +tb = F.Folded.t(F.folded(ar))
  +sk = RZ.RZProg.sink(q)
  +rd = rd_row.go(ar, O.UOp.toposort(O.Arena.budget(ar), ar, sk), 0)
  String.concat(["red=", RR.rr_node_str(ar, rd), " num=", U32.show(RR.rr_ap_red_num(ar, rd)),
                 " nsrc=", U32.show(O.Arena.nsrc(ar, rd)),
                 " dims=", RR.rr_dims_str(IX.rr_dims(ar, tb, rd)),
                 " [", RR.rr_rngm_row(ar, sk, rd), "]"])

# THE FULL FORWARD CHAIN, as FOUR stores chained through AFTERs on the intermediate buffers --
# the path `handle_after` now supports:
#
#   h1(196) <- conv2x2(x 28x28, w1 2x2)      h2(196) <- relu(h1)
#   h3(49)  <- pool2x2(h2 14x14)             y(10)   <- linear(h3 49, w2 49x10)
#
# Every `rz_input` takes the PREVIOUS tensor's arena (a fork makes sibling copies whose indices
# collide), and each `rz_after` feeds the next.
def fchain_prog() -> RZ.RZProg:
  # THE ARENA RULE at every step: a node minted on arena X is readable only in an arena that
  # CONTAINS X, so each dst is created FIRST and everything after it runs on `T.Tensor.ar(dst)`.
  +h1 = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(h1), 1, 784, [1, 1, 28, 28])
  +w1 = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +c1 = T.tn_mul(MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2]), MX.mxw_reshape.go(w1, [1, 1, 1, 2, 1, 2]))
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +a1 = RZ.rz_after(h1, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  +h2 = RZ.rz_input(O.Found.ar(a1), 3, 196, [1, 1, 14, 14])
  +v1 = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(h2), O.Found.i(a1)), [1, 1, 14, 14])
  +a2 = RZ.rz_after(h2, T.tn_relu(v1))
  +h3 = RZ.rz_input(O.Found.ar(a2), 4, 49, [1, 1, 7, 7])
  +v2 = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(h3), O.Found.i(a2)), [1, 1, 7, 2, 7, 2])
  +f3 = T.tn_rop(T.Tensor.ar(v2), T.Tensor.u(v2), O.OpsMAX{}, [3, 5])
  +a3 = RZ.rz_after(h3, T.tn_new(O.Found.ar(f3), O.Found.i(f3)))
  +y = RZ.rz_input(O.Found.ar(a3), 5, 10, [1, 10])
  +w2 = RZ.rz_input(T.Tensor.ar(y), 6, 490, [49, 10])
  +lhs = MX.mxw_reshape.go(T.tn_new(T.Tensor.ar(w2), O.Found.i(a3)), [1, 1, 49])
  +rhs = MX.mxw_permute.go(MX.mxw_reshape.go(w2, [1, 49, 10]), [0, 2, 1])
  +c4 = T.tn_mul(lhs, rhs)
  +f4 = T.tn_rop(T.Tensor.ar(c4), T.Tensor.u(c4), O.OpsADD{}, [2])
  +a4 = RZ.rz_after(y, T.tn_new(O.Found.ar(f4), O.Found.i(f4)))
  +snk = O.UOp.sink(O.Found.ar(a4), [O.Found.i(a1), O.Found.i(a2), O.Found.i(a3), O.Found.i(a4)])
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def fc_lk() -> String:
  +q = RZ.rz_rebuild(fchain_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ks = SCH.lin_kernels(lin)
  String.concat([U32.show(U32.from_nat(List.length(&2, U32, ks))), "/",
    String.join(fw_lk.go(SCH.lin_ar(lin), ks, Nil{}), " ")])

def fc_c() -> String:
  +q = RZ.rz_rebuild(fchain_prog(), False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  mk_fin(mk_one.go(SCH.lin_kernels(lin), (SCH.lin_ar(lin), Nil{}), 0))

def fchain_dump() -> String:
  +q = RZ.rz_rebuild(fchain_prog(), False{}, False{})
  RR.rr_dump(RZ.RZProg.ar(q), RZ.RZProg.sink(q))

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
    _ : Unit <- IO.print(String.concat(["pc_lr=", pc_lr()]))
    _ : Unit <- IO.print(String.concat(["pool_fcnt=", pool_fcnt()]))
    _ : Unit <- IO.print(String.concat(["st0=", pc_stage(0)]))
    _ : Unit <- IO.print(String.concat(["st1=", pc_stage(1)]))
    _ : Unit <- IO.print(String.concat(["st2=", pc_stage(2)]))
    _ : Unit <- IO.print(String.concat(["st3=", pc_stage(3)]))
    _ : Unit <- IO.print(String.concat(["pool_low2=", pool_low2()]))
    _ : Unit <- IO.print(String.concat(["pool_fd=", fd_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_fd=", fd_row(RZ.rz_rebuild(fw_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["pool_sd=", sd_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_sd=", sd_row(RZ.rz_rebuild(fw_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["pool_rl=", rl_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_rl=", rl_row(RZ.rz_rebuild(fw_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["xp_rm=", rm_row(RZ.rz_rebuild(xp_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["rd_row=", rd_row()]))
    _ : Unit <- IO.print(String.concat(["rz_row=", rz_row()]))
    _ : Unit <- IO.print(String.concat(["mb_row=", mb_row()]))
    _ : Unit <- IO.print(String.concat(["fwd_ids=", fwd_ids()]))
    _ : Unit <- IO.print(String.concat(["buf_row=", buf_row()]))
    _ : Unit <- IO.print(String.concat(["sk_row=", sk_row()]))
    _ : Unit <- IO.print(String.concat(["st_rows=", String.join(st_rows(), " | ")]))
    _ : Unit <- IO.print(String.concat(["pm_row=", pm_row()]))
    _ : Unit <- IO.print(String.concat(["pv_row=", pv_row()]))
    _ : Unit <- IO.print(String.concat(["sh_row=", sh_row()]))
    _ : Unit <- IO.print(String.concat(["sw_row=", String.join(sw_row(), " | ")]))
    _ : Unit <- IO.print(String.concat(["fbd_row=", fbd_row()]))
    _ : Unit <- IO.print(String.concat(["fchain_dump=", fchain_dump()]))
    _ : Unit <- IO.print(String.concat(["fc_lk=", fc_lk()]))
    _ : Unit <- IO.print(String.concat(["fc_c=", fc_c()]))
    _ : Unit <- IO.print(String.concat(["fwd_lk=", fwd_lk()]))
    _ : Unit <- IO.print(String.concat(["fwd_kg=", fwd_kg()]))
    _ : Unit <- IO.print(String.concat(["fwd_c=", fwd_c()]))
    _ : Unit <- IO.print(String.concat(["xw_lk=", xw_lk()]))
    _ : Unit <- IO.print(String.concat(["xw_c=", xw_c()]))
    _ : Unit <- IO.print(String.concat(["xw_row=", xw_row()]))
    _ : Unit <- IO.print(String.concat(["tp_xp=", tp_row(RZ.rz_rebuild(xp_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["tp_pool=", tp_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["nw_row=", nw_row()]))
    _ : Unit <- IO.print(String.concat(["xp_len=", xp_len()]))
    _ : Unit <- IO.print(String.concat(["xp_dims=", xp_dims()]))
    _ : Unit <- IO.print(String.concat(["xp_val=", xp_val_row()]))
    _ : Unit <- IO.print(String.concat(["xp_lk=", xp_lk()]))
    _ : Unit <- IO.print(String.concat(["xp_kg=", xp_kg()]))
    _ : Unit <- IO.print(String.concat(["pool_rm=", rm_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_rm=", rm_row(RZ.rz_rebuild(fw_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["pool_st=", st_row(RZ.rz_rebuild(pool_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_st=", st_row(RZ.rz_rebuild(fw_prog(), False{}, False{}))]))
    _ : Unit <- IO.print(String.concat(["fw_c=", fw_c()]))
    _ : Unit <- IO.print(String.concat(["fw_lk=", fw_lk()]))
    _ : Unit <- IO.print(String.concat(["fw_kg=", fw_kg()]))
    _ : Unit <- IO.print(String.concat(["conv_kg=", cv_kg()]))
    _ : Unit <- IO.print(String.concat(["conv_lk=", cv_lk()]))
    _ : Unit <- IO.print(String.concat(["pool_ku=", pool_ku()]))
    _ : Unit <- IO.print(String.concat(["pool_c=", cn_src(pool_prog())]))
    IO.print(String.concat(["conv_c=", cn_src(conv_prog())]))
