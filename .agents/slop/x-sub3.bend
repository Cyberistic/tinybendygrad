import Base
import ../../tinybendygrad/uop/ops.bend as O

# the question: can a Data record hold a List<&2, U32> field, read many times?
type Uop is Data:
  Uop{op: O.Op, dt: U32, kind: U32, a: U32, b: U32, slot: U32, run: U32, ns: U32, srcs: List<&2, U32>}

def Uop.slot(u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, ns, srcs}: slot

def Uop.run(u: Uop) -> U32:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, ns, srcs}: run

def Uop.srcs(u: Uop) -> List<&2, U32>:
  match u:
    case Uop{op, dt, kind, a, b, slot, run, ns, srcs}: srcs

def Uop.nsrc(u: Uop) -> U32:
  U32.from_nat(List.length(&2, U32, Uop.srcs(u)))

def Uop.src0(u: Uop) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Uop.srcs(u), 0n), 0)

def Uop.src1(u: Uop) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Uop.srcs(u), 1n), 0)

def show(+u: Uop) -> String:
  String.concat(["nsrc=", U32.show(Uop.nsrc(u)), " s0=", U32.show(Uop.src0(u)),
                 " s1=", U32.show(Uop.src1(u)), " slot=", U32.show(Uop.slot(u)), " run=", U32.show(Uop.run(u))])

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(show(Uop{O.OpsADD{}, 5, 0, 1, 2, 40, 4, 0, [3, 7]}))
    return Unit{}