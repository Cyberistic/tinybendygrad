# `_rop` -- ops.py:624 and T.tn_rop. DOES IT BUILD `AReduce{op, len(axis)}`? The pool's
# REDUCE measured `num_axes = 0` with no range srcs, which lowers to ONE accumulate and an
# input read at a constant address.
import Base
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/mixin/movement.bend as MX
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangify.bend as RF
import ./../../../tinybendygrad/helpers.bend as H

def rop_num.a(a: O.Arg) -> String:
  match a:
    case O.AReduce{rop, num_axes}: String.concat(["n=", U32.show(num_axes)])
    case _: "not-a-reduce"

def rop() -> String:
  +x = RZ.rz_input(O.Arena.empty(), 0, 784, [1, 1, 28, 28])
  +r = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +f = T.tn_rop(T.Tensor.ar(r), T.Tensor.u(r), O.OpsMAX{}, [3, 5])
  String.concat(["node=", RF.rr_node_str(O.Found.ar(f), O.Found.i(f)),
                 " arg=", rop_num.a(O.Arena.arg(O.Found.ar(f), O.Found.i(f))),
                 " nsrc=", U32.show(O.Arena.nsrc(O.Found.ar(f), O.Found.i(f)))])

def pool_val(+x: T.Tensor) -> T.Tensor:
  +r = MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2])
  +sh = MX.mxw_shrink(r, [0, 0, 0, 0, 0, 0], [1, 1, 14, 1, 14, 1])
  +f = T.tn_rop(T.Tensor.ar(sh), T.Tensor.u(sh), O.OpsMAX{}, [3, 5])
  T.tn_new(O.Found.ar(f), O.Found.i(f))

def pool_prog() -> RZ.RZProg:
  +dst = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(dst), 1, 784, [1, 1, 28, 28])
  +aft = RZ.rz_after(dst, pool_val(x))
  +snk = RZ.rz_sink(O.Found.ar(aft), O.Found.i(aft))
  RZ.RZProg{O.Found.ar(snk), O.Found.i(snk)}

# IS `rz_rebuild` THE ONE THAT LOSES `num_axes`? Same program, with and without it.
def rop_dbg() -> String:
  +q = RZ.rz_rebuild(pool_prog(), False{}, False{})
  +ar = RZ.RZProg.ar(q)
  +red = O.Arena.src(ar, O.Arena.src(ar, O.Arena.src0(ar, RZ.RZProg.sink(q)), 1), 1)
  String.concat(["rebuild arg=", rop_num.a(O.Arena.arg(ar, red)),
                 " nsrc=", U32.show(O.Arena.nsrc(ar, red))])

def rop_raw() -> String:
  +q = pool_prog()
  +ar = RZ.RZProg.ar(q)
  +red = O.Arena.src(ar, O.Arena.src(ar, O.Arena.src0(ar, RZ.RZProg.sink(q)), 1), 1)
  String.concat(["raw arg=", rop_num.a(O.Arena.arg(ar, red)),
                 " nsrc=", U32.show(O.Arena.nsrc(ar, red))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["rop=", rop()]))
    IO.print(String.concat(["raw=", rop_raw()]))
    IO.print(String.concat(["rebuild=", rop_dbg()]))
