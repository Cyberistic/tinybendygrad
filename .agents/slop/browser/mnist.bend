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

def main() -> IO(Unit):
  IO.print(String.concat(["mn_c=", mn_src()]))
