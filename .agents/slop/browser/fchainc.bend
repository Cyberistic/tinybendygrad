# .agents/slop/browser/fchain.bend -- THE FOUR-KERNEL FORWARD CHAIN, measured WITHOUT the render
# lane. `runtime/device.bend` is mid-edit by another unit (`body_low` calls an undefined
# `add_loads`), so this file imports only what `schedule` and the range map need: `fc_lk` (the
# LINEAR's kernel list) and `end_rows` (each END's ended/open set) are exactly the rows the END
# widening must move, and neither one renders C.
import Base
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/renderer/cstyle.bend as C

# conv2x2 -> relu -> max_pool2x2 -> linear(49->10), four stores chained through AFTERs, with the
# ARENA RULE at every step: each dst is created FIRST and everything after it runs on its arena.
def fchain_prog() -> RZ.RZProg:
  +h1 = RZ.rz_input(O.Arena.empty(), 0, 196, [1, 1, 14, 14])
  +x = RZ.rz_input(T.Tensor.ar(h1), 1, 784, [1, 1, 28, 28])
  +w1 = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +c1 = T.tn_mul(MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2]), MX.mxw_reshape.go(w1, [1, 1, 1, 2, 1, 2]))
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +a1 = RZ.rz_after(h1, T.tn_new(O.Found.ar(f1), O.Found.i(f1)))
  +h2 = RZ.rz_input(O.Found.ar(a1), 3, 196, [1, 1, 14, 14])
  +v1 = MX.mxw_reshape(T.tn_new(T.Tensor.ar(h2), O.Found.i(a1)), [1, 1, 14, 14])
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

def kg() -> O.Found:
  +q = RZ.rz_rebuild(fchain_prog(), False{}, False{})
  RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))


# THE RENDER OF ALL FOUR KERNELS, WITH ONE `kg()` AND ONE `schedule`: the fixture is ~30 s per build
# (MEASURED: `fchain.bend`'s two rows take 26-37 s), so the kernels are rendered from ONE LINEAR.
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

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["chain_c=", chain_c()]))
