# shaders/buf-schedules.bend -- THE MINIMUM THAT SCHEDULES, and the control for `shader-run.bend`.
#
# `mxw_buf` + an elementwise add + `assign` + a SINK answers `kernels=1`. So THE BUFFER PATH
# IS NOT THE PROBLEM: the port schedules a buffer-formed elementwise graph. That is what makes
# `shader-run.bend`'s one-store kernel a statement about the SHADER's graph (PAD/SHRINK, and
# two reads of a buffer) rather than about the scheduler in general.
#
# IT IS A PROBE AND NOT A GATE: it asserts nothing. `shader-gate.py` is the gate.

import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/tensor.bend as T
import ../tinybendygrad/mixin/movement.bend as MX
import ../tinybendygrad/mixin/elementwise.bend as E
import ../tinybendygrad/schedule/rangify.bend as RNG
import ../tinybendygrad/schedule/__init__.bend as SCH

def rows() -> List<&2, String>:
  +a = MX.mxw_buf(O.Arena.empty(), 0, 256)
  +b = MX.mxw_buf(T.Tensor.ar(a), 1, 256)
  +s = E.ew_add(a, E.ETen{b}, False{})
  +st = T.tn_assign_store(T.Tensor.ar(s), T.Tensor.u(b), T.Tensor.u(s))
  +sk = O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])
  +kg = RNG.rr_kernel_graph(O.Found.ar(sk), O.Found.i(sk))
  +lin = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  [String.concat(["kernels=", U32.show(U32.from_nat(List.length(&2, U32, SCH.lin_kernels(lin))))])]

def put(rs: List<&2, String>) -> IO(Unit):
  match rs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +r <> rest:
      do IO<Unit>:
        x : Unit <- IO.print(r)
        y : Unit <- put(rest)
        IO.pure(Unit, y)

def main() -> IO(Unit): put(rows())
