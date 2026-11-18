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
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX

def cn_tap(+x: T.Tensor, +w: T.Tensor, +ky: U32, +kx: U32) -> T.Tensor:
  +p = MX.mxw_pad(x, [0, 0, 1, 1], [0, 0, 1, 1])
  T.tn_mul(MX.mxw_shrink(p, [0, 0, ky, kx], [1, 1, 28, 28]),
           MX.mxw_shrink(w, [0, 0, ky, kx], [1, 1, 1, 1]))

def cn_conv(+x: T.Tensor, +w: T.Tensor) -> T.Tensor:
  T.tn_add(T.tn_add(T.tn_add(cn_tap(x, w, 0, 0), cn_tap(x, w, 0, 1)),
                    T.tn_add(cn_tap(x, w, 0, 2), cn_tap(x, w, 1, 0))),
           T.tn_add(T.tn_add(cn_tap(x, w, 1, 1), cn_tap(x, w, 1, 2)),
                    T.tn_add(T.tn_add(cn_tap(x, w, 2, 0), cn_tap(x, w, 2, 1)), cn_tap(x, w, 2, 2))))

def cn_pool(+x: T.Tensor) -> T.Tensor:
  T.tn_maximum(T.tn_maximum(MX.mxw_shrink(x, [0, 0, 0, 0], [1, 1, 14, 14]),
                            MX.mxw_shrink(x, [0, 0, 0, 1], [1, 1, 14, 14])),
               T.tn_maximum(MX.mxw_shrink(x, [0, 0, 1, 0], [1, 1, 14, 14]),
                            MX.mxw_shrink(x, [0, 0, 1, 1], [1, 1, 14, 14])))

# the same realize substitution the fixture uses: dst <- op(inputs)
def pool_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +aft = RZ.rz_after(dst, cn_pool(x))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def conv_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 784, [1, 1, 28, 28])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +w = RZ.rz_input(T.Tensor.ar(x), 2, 9, [1, 1, 3, 3])
  +aft = RZ.rz_after(dst, cn_conv(x, w))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

def cn_src(+p: RZ.RZProg) -> String:
  +q = RZ.rz_rebuild(p, False{}, False{})
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["pool_c=", cn_src(pool_prog())]))
    IO.print(String.concat(["conv_c=", cn_src(conv_prog())]))
