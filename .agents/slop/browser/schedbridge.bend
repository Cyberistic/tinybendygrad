# .agents/slop/browser/schedbridge.bend -- THE BRIDGE, AS A MEASUREMENT.
#
# THE QUESTION: **DOES THE PORT's OWN `schedule()` PRODUCE KERNELS ONCE
# `run_rangeify` HAS RUN?**
#
# THE BACKGROUND, MEASURED:
#   * `realize.bend`'s `rz_lin_n=0` -- the port's own `schedule()` on the port's
#     own sink answers ZERO kernels, because the sink's AFTER has a STORE as its
#     second src and `_split_after` (`schedule/__init__.bend:467`) partitions an
#     AFTER's srcs into KERNELS and dependencies, and a STORE IS NOT A KERNEL.
#   * `rangify.bend`'s `rr_kg` -- the port's own `run_rangeify` AND THEN THE
#     ENGINE's SIX STAGES -- answers a graph whose AFTER's SECOND SRC IS AN
#     **`END`**, AND `sc_is_kernel` (`schedule/__init__.bend:276`) COUNTS `END`.
#
# **=> SO THE HYPOTHESIS IS: THE RANGEIFIED GRAPH SCHEDULES, AND THE
# UNRANGEIFIED ONE DOES NOT.** THIS FILE ASKS IT.
#
# THE COMPOSITION IS HERE AND NOT IN `schedule/__init__.bend`, AND THE REASON IS
# AN IMPORT CYCLE, NOT A PREFERENCE:
#   `schedule/rangify.bend`  imports `schedule/realize.bend` (the FIXTURE) and
#                             `schedule/rangeify.bend` (the ENGINE);
#   `schedule/realize.bend` imports `schedule/__init__.bend` (the SCHEDULER);
#   **=> SO `schedule/__init__.bend` CANNOT IMPORT `schedule/rangify.bend`** --
#   it would close the cycle. **=> AND A FILE THAT IMPORTS BOTH IS THE ONLY
#   PLACE THE COMPOSITION CAN LIVE**, which is upstream's shape too:
#   `create_schedule(get_kernel_graph(prepare_rangeify(function)))`
#   (`tinygrad/schedule/__init__.py:132`) -- the `get_kernel_graph` COMPOSITION
#   is a CALLER's job, not `create_schedule`'s.
import Base
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

# THE TWO SCHEDULER CALLS, AND THE QUESTION IS THE DIFFERENCE BETWEEN THEM.
#
# (a) THE PORT's OWN SINK, SCHEDULED AS-IS. This is `realize.bend`'s `rz_lin_n`.
def bridge_lin_raw() -> String:
  +q = RZ.rz_built()
  +l = SCH.schedule(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  U32.show(U32.from_nat(List.length(&2, U32, SCH.Lin.out(l))))

# (b) THE SAME SINK, RANGEIFIED AND THEN SCHEDULED. `rr_kernel_graph` is the
# port's own `get_kernel_graph` -- `run_rangeify` AND the six stages -- and it
# answers the REBUILT ROOT, which is the graph the scheduler wants.
def bridge_lin_ranged() -> String:
  +q = RZ.rz_built()
  +k = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  U32.show(U32.from_nat(List.length(&2, U32, SCH.Lin.out(l))))

# AND THE GRAPH EACH ONE SCHEDULES, IN THE SCHEDULER's OWN SPELLING, so a
# reader can see WHY they differ rather than being told they do.
def bridge_dump_ranged() -> String:
  +q = RZ.rz_built()
  +k = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(k), O.Found.i(k))

# THE PORT's OWN KERNEL FINGERPRINT: `SCH.gate.ops(ar, Lin.out(l))` IS THE
# SCHEDULER's OWN ROW FOR "WHAT IS IN THE LINEARIZED KERNELS", and it is a
# DIGIT OVER THE OPS -- so the port's answer is ONE NUMBER and CPython's is
# ONE NUMBER, and the comparison is over the two.
def bridge_ops() -> String:
  +q = RZ.rz_built()
  +k = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  U32.show(SCH.gate.ops(SCH.Lin.ar(l), SCH.Lin.out(l)))

# AND THE KERNEL's OWN OP AND SRC COUNT, WHICH IS WHAT EXPLAINS A FINGERPRINT
# MISMATCH. CPython's kernel is a `CALL` (upstream's `split_kernels` turned the
# `END` into a `CALL`), and the port's is an `END` -- **=> AND THE PORT's
# ENGINE's STAGE 6 IS `split_kernels` (`rangeify.py:359`), WHICH IS IN THE
# `eng_stages()` LIST AT INDEX 6.** So a mismatch here is a question about
# WHETHER THAT STAGE FIRED, and the row answers it by NAMING the op.
def bridge_kops.go(+ks: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      bridge_kops.go(t, ar, List.append(&2, String, acc,
        [String.concat([U32.show(SCH.gate.code(SCH.sc_op(ar, k))), ":", U32.show(SCH.gate.nsrcs(ar, [k]))])]))

def bridge_kernel_ops() -> String:
  +q = RZ.rz_built()
  +k = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(k), O.Found.i(k))
  +outs = SCH.Lin.out(l)
  +ar = SCH.Lin.ar(l)
  String.join(bridge_kops.go(outs, ar, Nil{}), ",")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["bridge_lin_raw=", bridge_lin_raw()]))
    IO.print(String.concat(["bridge_lin_ranged=", bridge_lin_ranged()]))
    IO.print(String.concat(["bridge_dump_ranged=", bridge_dump_ranged()]))
    IO.print(String.concat(["bridge_ops=", bridge_ops()]))
    IO.print(String.concat(["bridge_kernel_ops=", bridge_kernel_ops()]))
