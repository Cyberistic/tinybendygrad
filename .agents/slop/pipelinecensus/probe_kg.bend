# probe_kg.bend -- THE DECISIVE MEASUREMENT FOR THE PIPELINE CENSUS.
#
# QUESTION. `.agents/slop/chain/GAP.md` says `run_rangeify` is the one absent stage, and
# `rangeify.bend`'s `eng_stages()` spells stage 1 as `Stg{0, Nil{}}` -- an EMPTY table --
# with the comment "NOT PORTED".  `schedule/rangify.bend` has `rr_kernel_graph`, which is
# the port's own `get_kernel_graph` (run_rangeify + the engine's six table stages).
#
# SO: DOES `schedule()` ANSWER A NON-ZERO KERNEL LIST WHEN IT IS HANDED THE RANGEIFIED
# ROOT, AND ZERO WHEN IT IS HANDED THE UN-RANGEIFIED ONE?  THREE ROWS, ONE PROGRAM.
#
# THE PROGRAM IS THE PORT's OWN `schedule/realize.bend`'s `rz_built()` -- the same
# fixture `gates/realize-gate.bend` and `.agents/slop/chain/chain.bend` use, so the
# comparison is against measurements that already exist and not against a new graph.
import Base
import ./../../../tinybendygrad/schedule/rangify.bend as P
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangeify.bend as RG
import ./../../../tinybendygrad/uop/ops.bend as O

def row(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

# THE RANGEIFIED GRAPH, from the port's own driver, dumped in the engine's spelling.
def kg_dump() -> String:
  +q = RZ.rz_built()
  +k = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RG.eng_dump(O.Found.ar(k), O.Found.i(k))

# THE KERNEL COUNT, on the RANGEIFIED root.  This is the hop `eng_stages()` cannot
# make: it hands `schedule()` the un-rangeified root.
def kg_lin_n() -> U32:
  +q = RZ.rz_built()
  +k = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  U32.from_nat(List.length(&2, U32, SCH.Lin.out(SCH.schedule(O.Found.ar(k), O.Found.i(k)))))

# THE CONTROL.  The same `schedule()` on the UN-rangeified sink -- the root the engine
# hands it today.  It must be 0, or `kg_lin_n` measures nothing.
def base_lin_n() -> U32:
  +q = RZ.rz_built()
  U32.from_nat(List.length(&2, U32, SCH.Lin.out(SCH.schedule(RZ.RZProg.ar(q), RZ.RZProg.sink(q)))))

def main() -> IO(Unit):
  do IO<Unit>:
    row("kg_dump", kg_dump())
    row("kg_lin_n", U32.show(kg_lin_n()))
    row("base_lin_n", U32.show(base_lin_n()))
