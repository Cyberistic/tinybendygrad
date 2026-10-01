import Base

type Split is Data:
  Split{ks: List<&2, U32>, ds: List<&2, U32>}

def Split.ks(x: Split) -> List<&2, U32>:
  match x:
    case Split{ks, ds}: ks

def Split.ds(x: Split) -> List<&2, U32>:
  match x:
    case Split{ks, ds}: ds

def add(cls: U32, +s: U32, ks: List<&2, U32>, ds: List<&2, U32>) -> Split:
  match cls:
    case 0: Split{List.append(&2, U32, ks, [s]), ds}
    case 1: Split{ks, List.append(&2, U32, ds, [s])}
    case _: Split{ks, ds}

def pickc3(is_a: Bool) -> U32:
  match is_a:
    case True{} : 1
    case False{}: 2

def pickc2(is_k: Bool, is_a: Bool) -> U32:
  match is_k:
    case True{} : 0
    case False{}: pickc3(is_a)

def pickc(is_k: Bool, is_a: Bool) -> U32:
  pickc2(is_k, is_a)

def pick(is_k: Bool, is_a: Bool, +s: U32, +sp: Split) -> Split:
  add(pickc(is_k, is_a), s, Split.ks(sp), Split.ds(sp))

# a match on a LIST parameter inside a NUMERIC arm of another match
def go(fuel: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}    : acc
        case x <> rest: go(p, rest, List.append(&2, U32, acc, [x]))

# a match on a Data parameter inside a BOOL arm of another match
def dgo(is_k: Bool, sp: Split) -> Nat:
  match is_k:
    case True{} : 1n
    case False{}: match sp:
                   case Split{ks, ds}: List.length(&2, U32, ks)

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat(["ks=", U32.show(U32.from_nat(List.length(&2, U32, Split.ks(pick(True{}, False{}, 7, Split{Nil{}, Nil{}})))))]))
    b : Unit <- IO.print(String.concat(["go=", U32.show(U32.from_nat(List.length(&2, U32, go(3n, [1,2,3], Nil{}))))]))
    c : Unit <- IO.print(String.concat(["dgo=", U32.show(U32.from_nat(dgo(False{}, Split{[1,2], Nil{}})))]))
    IO.print("alive")