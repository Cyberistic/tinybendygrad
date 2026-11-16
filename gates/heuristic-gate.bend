# gates/heuristic-gate.bend -- the gate driver for `tinybendygrad/codegen/opt/heuristic.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/opt/heuristic.bend as P

import ./../tinybendygrad/codegen/opt/postrange.bend as PR
import ./../tinybendygrad/uop/ops.bend as O
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("group_up_plus", P.group_up(P.plus_k()))
    b : Unit <- row("group_up_red", P.group_up(P.reduce_k()))
    c : Unit <- row("group_up_mmm", P.group_up(P.matmul_k()))
    d : Unit <- row("group_max_py", P.group_max(P.plus_k()))
    e : Unit <- row("group_max_red", P.group_max(P.reduce_k()))
    f : Unit <- row("group_max_mmm", P.group_max(P.matmul_k()))
    g : Unit <- row("gfr_plus", P.group_for(P.plus_k()))
    h : Unit <- row("gfr_red", P.group_for(P.reduce_k()))
    i : Unit <- row("gfr_mmm", P.group_for(P.matmul_k()))
    row("shape_len_red", PR.Sched.shape_len(P.reduce_k()))
