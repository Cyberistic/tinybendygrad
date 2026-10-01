import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S

# Q1: construct ops.bend's exported `Topo` / `Frame` records from another file?
def q1.go(a: O.Arena, t: O.Topo) -> U32:
  match t:
    case O.Topo{cache, stack, calls}: U32.from_nat(List.length(&2, O.Frame, stack))

def q1b() -> U32:
  q1.go(O.Arena.empty(), O.Topo{Nil{}, [O.Frame{5, True{}}], True{}})

# Q2: a self-call on a LIST TAIL where the accumulator is a `Data` record of lists
type Acc is Data:
  Acc{es: List<&2, O.PMEntry>}

def Acc.es(x: Acc) -> List<&2, O.PMEntry>:
  match x:
    case Acc{es}: es

def q2.go(ts: List<&2, O.PMEntry>, +a: Acc) -> Acc:
  match ts:
    case Nil{}: a
    case e <> t: q2.go(t, Acc{List.append(&2, O.PMEntry, Acc.es(a), [e])})

def q2() -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, Acc.es(q2.go([O.PMEntry{0, Nil{}, Nil{}}], Acc{Nil{}}))))

# Q3: `List.foldl` with a TOP-LEVEL def as the template (not a lambda)
def q3.add(a: U32, b: U32) -> U32:
  U32.add(a, b)

def q3(xs: List<&2, U32>) -> U32:
  List.foldl(&2, U32, U32, q3.add, xs, 0)

def q3v() -> U32:
  q3([1, 2, 3])

# Q5: a def whose ONLY self-call is a list-tail descent, accumulator `+`
def q5.go(+ar: O.Arena, +xs: List<&2, U32>, +acc: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: U32.from_nat(List.length(&2, U32, acc))
    case x <> t: q5.go(ar, t, List.append(&2, U32, acc, [O.Arena.src0(ar, x)]))

# Q6: does `List.get` on a `List<&2, O.Frame>` of length 0 answer None, and does
# `Maybe.default` on a `Maybe<&2, U32>` work -- i.e. can I index a list by U32?
def q6.get(xs: List<&2, U32>, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(n)), 0)

def q6v() -> U32:
  q6.get([7, 8, 9], 1)

# Q7: a fold carrying BOTH a `+` list and a Nat countdown, with a Bool decided by
# a computed value -- the shape every set-algebra fold wants.
def q7(+ar: O.Arena, +self: U32) -> Bool:
  List.contains(U32, U32.is_eq, O.UOp.toposort(O.Arena.budget(ar), ar, self), self)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat(["q1b=", U32.show(q1b())]))
    b : Unit <- IO.print(String.concat(["q2=", U32.show(q2())]))
    c : Unit <- IO.print(String.concat(["q3=", U32.show(q3v())]))
    d : Unit <- IO.print(String.concat(["q6=", U32.show(q6v())]))
    IO.print("alive")