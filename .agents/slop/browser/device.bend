# .agents/slop/browser/device.bend -- THE PORT's OWN DEVICE LANE, DRIVEN.
#
# schedule -> body toposort -> linearize -> kuconv -> render, ALL of it the port's own
# defs, called through `runtime/device.bend`'s `compile_sink` -- not a probe-local copy
# of the chain.
import Base
import ./../../../tinybendygrad/runtime/device.bend as DEV
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

def dev_src() -> String:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  DEV.Prog.src(DEV.compile_sink(O.Found.ar(kg), O.Found.i(kg)))

def main() -> IO(Unit):
  IO.print(String.concat(["dev_c=", dev_src()]))
