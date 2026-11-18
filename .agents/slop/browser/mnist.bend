# .agents/slop/browser/mnist.bend -- AN MNIST LAYER, SCHEDULED AND RENDERED.
#
# THE MODEL: the fc layer of `nn/mnist_cnn.bend` -- `Linear(392, 10)` over a flattened
# 28x28 image -- built as EXPLICIT UOPS in the shape `realize.bend`'s `rz_program` uses
# (that builder is a (4,3)@(3,5) dot; this one is (1,392)@(392,10)). The weights are a
# 3920-element buffer, the activation a 1x392 one, and the output 1x10.
#
# WHY NOT conv2d/pool YET, stated: `Tensor.max_pool2d`'s `repeat`/`shrink_to`/`reshape`/
# `permute` chain (`mixin/movement.py:608-616`) is shape-only in this port and
# `Tensor.realize` is a `TODO(p3)`, so a conv builder has to be written against `mxw_*`
# by hand. The fc layer exercises the whole lane -- build, rebuild, rangeify, schedule,
# weak, reduce, linearize, kuconv, render -- on real MNIST shapes.
import Base
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/schedule/rangeify.bend as RF

def mn_dot_x(+lhs: T.Tensor) -> T.Tensor: MX.mxw_reshape.go(lhs, [1, 1, 392])
def mn_dot_w(+rhs: T.Tensor) -> T.Tensor: MX.mxw_permute.go(MX.mxw_reshape.go(rhs, [1, 392, 10]), [0, 2, 1])

def mn_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 10, [1, 10])
  +lhs = RZ.rz_input(T.Tensor.ar(dst), 1, 392, [1, 392])
  +rhs = RZ.rz_input(T.Tensor.ar(lhs), 2, 3920, [392, 10])
  +val = T.tn_mul(mn_dot_x(lhs), mn_dot_w(rhs))
  +red = RZ.rz_reduce(val)
  +aft = RZ.rz_after(dst, red)
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def mn_built() -> RZ.RZProg: RZ.rz_rebuild(mn_prog(), False{}, False{})

def mn_src() -> String:
  +q = mn_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

# THE LINEARISED ORDER, one KU per position -- the row that says where the two RANGEs and
# the three ENDs sit relative to the two accumulator stores.
def mn_op(+k: C.KU) -> String: RF.eng_op_name(C.KU.op(k))

def mn_sig.go(+ks: List<&2, C.KU>, +i: U32, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: mn_sig.go(t, U32.add(i, 1), List.append(&2, String, acc, [String.concat([U32.show(i), ":", mn_op(k)])]))

def mn_sig(p: (O.Arena & List<&2, C.KU>)) -> String:
  (ar, kus) = p
  String.join(mn_sig.go(kus, 0, Nil{}), " ")

def mn_ku() -> String:
  +q = mn_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +lin = DEV.schedule(O.Found.ar(kg), O.Found.i(kg))
  +ar2 = O.Found.ar(lin)
  mn_sig(DEV.body_kus(ar2, SCH.sc_src0(ar2, O.Found.i(lin))))

# THE SAME ENTRY ON THE STANDALONE FC's GRAPH: how many ranges does its MUL carry, and how many
# index srcs does its INDEX get? (`INDEX:none:PARAM,CONST,CONST,RANGE,RANGE` is the rendered C's
# shape, so `in=` should be FOUR positions for the fc and ONE for the chained kernel.)
def fci_row() -> String:
  +q = mn_built()
  +ar = RZ.RZProg.ar(q)
  +sk = RZ.RZProg.sink(q)
  +st = SCH.sc_src(ar, SCH.sc_src0(ar, sk), 1)
  +v = SCH.sc_src(ar, st, 1)
  +m = SCH.sc_src0(ar, v)
  String.concat(["st=", RR.rr_node_str(ar, st), "[", RR.rr_rngm_row(ar, sk, st), "]",
                 " v=", RR.rr_node_str(ar, v), "[", RR.rr_rngm_row(ar, sk, v), "]",
                 " v.src0=", RR.rr_node_str(ar, m), "[", RR.rr_rngm_row(ar, sk, m), "]"])

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["fci_row=", fci_row()]))
    _ : Unit <- IO.print(String.concat(["mn_ku=", mn_ku()]))
    IO.print(String.concat(["mn_c=", mn_src()]))
