# gates/realize-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/realize.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/realize.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/schedule/__init__.bend as SCH

def rz_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))
def rz_row_consts() -> String:
  +q = P.rz_built()
  String.join(P.rz_consts.go(O.Arena.budget(P.RZProg.ar(q)), [P.RZProg.sink(q)], P.RZProg.ar(q),
                           Nil{}, P.RZProg.sink(q), Nil{}), ",")
def rz_row_dump0() -> String:
  +p0 = P.rz_program()
  P.rz_dump(P.RZProg.ar(p0), P.RZProg.sink(p0))
def rz_row_dump() -> String:
  +q = P.rz_built()
  P.rz_dump(P.RZProg.ar(q), P.RZProg.sink(q))
def rz_row_nodes() -> String:
  +q = P.rz_built()
  U32.show(P.rz_nodes(q))
# the port's own scheduler, on the port's own sink. `SCH.schedule` is
# `create_schedule` (`schedule/__init__.bend:1128 symbol=schedule`), and it wants a SINK OF
# AFTERs WHOSE SECOND SRC IS A KERNEL -- a CALL or an END -- because
# `_split_after` (`schedule/__init__.bend:462 symbol=sc_split`) partitions the AFTER's srcs
# into kernels and dependencies.
# the port's own scheduler, on the port's own sink. `SCH.schedule` is
# `create_schedule` (`schedule/__init__.bend:1128 symbol=schedule`), and it wants a SINK OF
# AFTERs WHOSE SECOND SRC IS A KERNEL -- a CALL or an END -- because
# `_split_after` (`schedule/__init__.bend:462 symbol=sc_split`) partitions the AFTER's srcs
# into kernels and dependencies.
def rz_row_lin() -> String:
  +q = P.rz_built()
  +l = SCH.schedule(P.RZProg.ar(q), P.RZProg.sink(q))
  U32.show(U32.from_nat(List.length(&2, U32, SCH.Lin.out(l))))
# the port's own engine, on the port's own sink. - and this row moved to
# `rangify.bend` ON 2026-10-30, AND THE MOVE IS THE POINT:
# `realize.bend` IMPORTS `rangeify.bend` (THE ENGINE) AND `rangify.bend` IMPORTS
# `realize.bend` (THE FIXTURE), - SO `rangeify.bend` COULD NOT IMPORT
# `rangify.bend` -- WHICH IS WHERE `run_rangeify` LIVES -- AND THE ENGINE's
# stage 1 was an empty table. - and the MOVE makes the edge one-way:
# `rangify.bend` -> `rangeify.bend`, AND `rangeify.bend` -> NOTHING BACK.
def rz_row_params() -> String:
  +q = P.rz_built()
  String.join(P.rz_params.go(O.Arena.budget(P.RZProg.ar(q)), [P.RZProg.sink(q)], P.RZProg.ar(q),
                           Nil{}, P.RZProg.sink(q), Nil{}), ",")
def rz_row_plant() -> String:
  +q = P.rz_plant()
  P.rz_dump(P.RZProg.ar(q), P.RZProg.sink(q))
def rz_row_plant_params() -> String:
  +q = P.rz_plant2()
  String.join(P.rz_params.go(O.Arena.budget(P.RZProg.ar(q)), [P.RZProg.sink(q)], P.RZProg.ar(q),
                           Nil{}, P.RZProg.sink(q), Nil{}), ",")
def main() -> IO(Unit):
  do IO<Unit>:
    rz_row.line("rz_dump", rz_row_dump())
    rz_row.line("rz_consts", rz_row_consts())
    rz_row.line("rz_params", rz_row_params())
    rz_row.line("rz_nodes", rz_row_nodes())
    rz_row.line("rz_dump0", rz_row_dump0())
    rz_row.line("rz_lin_n", rz_row_lin())
    rz_row.line("rz_plant_dump", rz_row_plant())
    rz_row.line("rz_plant_params", rz_row_plant_params())
