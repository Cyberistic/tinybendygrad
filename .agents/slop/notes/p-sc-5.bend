import Base

type Split is Data:
  Split{ks: List<&2, U32>, ds: List<&2, U32>}

# A: Num match nested in a List arm -- REFUSED (measured)
# C: List match nested in a List arm
def c(fuel: Nat, xs: List<&2, U32>, ys: List<&2, U32>) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      match xs:
        case Nil{}    : 0
        case x <> rest:
          match ys:
            case Nil{}    : c(p, rest, ys)
            case y <> s   : c(p, rest, s)

# D: Num match nested in a Data arm
def d(fuel: Nat, sp: Split, cls: U32) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      match sp:
        case Split{ks, ds}:
          match cls:
            case 0: d(p, Split{ks, ds}, 1)
            case _: d(p, Split{ks, ds}, 0)

# E: TWO-SCRUTINEE with a numeric first and a literal second
def e(fuel: Nat, cls: U32, +u: U32, t: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel cls:
    case 0n _     : acc
    case 1n+p 0   : e(p, 1, u, t, List.append(&2, U32, acc, [u]))
    case 1n+p _   : e(p, 0, u, t, acc)

def main() -> IO(Unit):
  do IO<Unit>:
    c2 : Unit <- IO.print(String.concat(["c=", U32.show(c(2n, [1,2], [3,4]))]))
    d2 : Unit <- IO.print(String.concat(["d=", U32.show(d(2n, Split{[1], Nil{}}, 0))]))
    e2 : Unit <- IO.print(String.concat(["e=", U32.show(U32.from_nat(List.length(&2, U32, e(3n, 0, 7, Nil{}, Nil{}))))]))
    IO.print("alive")