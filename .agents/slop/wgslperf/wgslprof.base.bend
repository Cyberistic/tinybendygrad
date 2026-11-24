import Base
# .agents/slop/wgslperf/wgslprof.bend -- A **COPY** OF `.agents/slop/browser/fchainwgsl.bend`, **UNCHANGED**,
# **AND **THE **PROFILE **IS **IN **THE **COMPILED **JS** (⇒⇒† AND **AND **THE **PHASES **ARE **THE
# **COMPILED **FORM's **OWN **CALLS**).
#
# **⇒⇒† AND **WHY **A **COPY **AND **NOT **THE **ORIGINAL**: **THE **ORIGINAL **IS **IN
# **`.agents/slop/browser/`**, **⇒⇒† AND **AND **THAT **DIRECTORY **IS **READ-ONLY** (⇒⇒† AND **AND **THE
# **ORCHESTRATOR's **RULE**)** -- **⇒⇒† AND **AND **THE **PROFILE **NEEDS **NO **CHANGE **TO **THE
# **DRIVER **AT **ALL** (⇒⇒† AND **THE **CLOCKS **GO **IN **THE **COMPILED **JS**)**.
#
# **⇒⇒† AND **AND **THE **DRIVER **IS **BYTE-IDENTICAL **TO **THE **ORIGINAL** (⇒⇒† AND **AND **THE
# **OUTPUT **MUST **BE **THE **SAME **WGSL**, **⇒⇒† AND **AND **THAT **IS **WHAT **THE **PROFILE **CHECKS
# **BY **THE **BYTES**)**
import ./../../../tinybendygrad/renderer/wgsl.bend as V
import ./../../../tinybendygrad/renderer/wgsl_walk.bend as W
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/uop/ops.bend as O
import ../browser/ku2r.bend as K2
import ../browser/fchainl.bend as FC

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
