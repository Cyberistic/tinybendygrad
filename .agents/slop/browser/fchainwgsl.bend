# .agents/slop/browser/fchainwgsl.bend -- THE FOUR FORWARD-CHAIN KERNELS, RENDERED TO WGSL BY THE
# PORT's OWN WGSL LANE: `wgsl_walk.bend` walks the kernel, `wgsl.bend` assembles the module.
#
# The kernels are the SAME ones `fchainc.bend` renders to C, from ONE `kg()` and ONE `schedule`, so
# the WGSL and the C describe one graph. `@workgroup_size(1)` and one dispatch: every kernel here is
# a scalar loop nest over `Lidx`, so one invocation runs the whole program.
import Base
import ./../../../tinybendygrad/renderer/wgsl.bend as V
import ./../../../tinybendygrad/renderer/wgsl_walk.bend as W
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/uop/ops.bend as O
import ./ku2r.bend as K2
import ./fchainl.bend as FC

# `Scan{sz, half}`: `sz` is `@workgroup_size`, `half` is the `enable f16;` line. This chain is
# float32 throughout, so f16 stays off.
def scan1() -> V.Scan: V.Scan{[1], False{}}

def emit(p: (O.Arena & List<&2, C.KU>), +i: U32, +acc: List<&2, String>) -> (O.Arena & List<&2, String>):
  (+ar, +ks) = p
  +w = W.walk(K2.ku2r_l(ks))
  (ar, List.append(&2, String, acc,
        [String.concat(["--w", U32.show(i), "\n",
                        V.render_kernel(W.Wk.nm(w), W.Wk.body(w), W.Wk.bufs(w), scan1())])]))

def step(p: (O.Arena & List<&2, String>), +k: U32, +i: U32) -> (O.Arena & List<&2, String>):
  (+ar, +acc) = p
  emit(DEV.body_kus(ar, k), i, acc)

def go(+ks: List<&2, U32>, p: (O.Arena & List<&2, String>), +i: U32) -> (O.Arena & List<&2, String>):
  match ks:
    case Nil{}: p
    case k <> t: go(t, step(p, k, i), U32.add(i, 1))

def all(p: (O.Arena & List<&2, String>)) -> String:
  (ar, acc) = p
  String.join(acc, "\n")

def chain_wgsl() -> String:
  +k = FC.kg()
  +lin = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  all(go(SCH.lin_kernels(lin), (SCH.lin_ar(lin), Nil{}), 0))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["chain_w=", chain_wgsl()]))
