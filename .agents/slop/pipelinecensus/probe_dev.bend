# probe_dev.bend -- CAN THE PORT's OWN `Device` LANE BE REACHED FROM A PROGRAM?
#
# `runtime/device.bend:427` `compile_sink(+ar, sink) -> Prog` is the lane's entry: it calls
# `schedule()` -> `body_low` -> `linearize` -> `kuconv` -> `render`, i.e. the whole port's
# own arena -> C path in ONE def.  IT HAS NO CALLER IN THE TREE.
#
# THIS PROBE IS THE CALLER.  It asks the two questions a caller would:
#   1. DOES THE MODULE IMPORT?  `./bin/bend tinybendygrad/runtime/device.bend --check-only`
#      exits 1 with "4 defs rely on unsafe or foreign code", so the port's own compiler
#      refuses to emit it -- and an unimportable lane cannot be wired.
#   2. IF IT DOES, DOES `compile_sink` PRODUCE C FOR THE RANGEIFIED PROGRAM?
#
# THE INPUT IS THE PORT's OWN RANGEIFIED GRAPH (`rangify.bend`'s `rr_kernel_graph`), so a
# success here is the port's own program -> the port's own C, with no hand-built fixture.
import Base
import ./../../../tinybendygrad/runtime/device.bend as D
import ./../../../tinybendygrad/schedule/rangify.bend as P
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

def row(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def c_src() -> String:
  +q = RZ.rz_built()
  +k = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  D.Prog.src(D.compile_sink(O.Found.ar(k), O.Found.i(k)))

def main() -> IO(Unit):
  do IO<Unit>:
    row("c_src", c_src())
