# probe_chain.bend -- DOES THE FIXTURE -> KU CHAIN IMPORT, AND WHAT DOES IT ANSWER?
#
# Cheap questions first, before the lane is built on them: does `linrender.bend`'s
# `lin_build()` import as a def (it has its own `main`, which an import must NOT run),
# how many KUs come back, and what ARE the port's own buffer names and kernel name?
#
#   ./bin/bend .agents/slop/execgap/probe_chain.bend
import Base
import ./../linrender/linrender.bend as LR
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/ops.bend as O

def bufs.go(+bs: List<&2, C.BArg>, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case b <> t: bufs.go(t, List.append(&2, String, acc, [C.BArg.name(b)]))

def row(+nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def main() -> IO(Unit):
  do IO<Unit>:
    +ks : List<&2, C.KU> = LR.lin_build()
    +s : C.St = C._render(C.dev_clang(), ks)
    Unit <- row("n_ku", U32.show(U32.from_nat(List.length(&2, C.KU, ks))))
    Unit <- row("name", C.St.name(s))
    Unit <- row("bufs", String.join(bufs.go(C.St.bufs(s), Nil{}), ","))
    Unit <- row("c_len", U32.show(U32.from_nat(String.length(C.render(C.dev_clang(), True{}, ks)))))
    return Unit{}
