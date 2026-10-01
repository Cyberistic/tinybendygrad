import Base

# Q: a Bool-parameter match NESTED inside a numeric arm of another match?
def go(fuel: Nat, b: Bool, +ar: U32, +s: U32) -> U32:
  match fuel:
    case 0n   : s
    case 1n+p :
      match b:
        case True{} : go(p, Bool.or(b, U32.is_eq(ar, s)), ar, s)
        case False{}: s

# Q: a Bool-parameter match nested inside a LIST-arm of another match?
def lg(fuel: Nat, b: Bool, xs: List<&2, U32>, acc: U32) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p:
      match b:
        case True{} : lg(p, False{}, xs, U32.add(acc, 1))
        case False{}:
          match xs:
            case Nil{}    : acc
            case x <> rest: lg(p, True{}, rest, acc)

# Q: a three-way U32 class nested inside a numeric arm, one self-call per arm
def three(fuel: Nat, cls: U32, +u: U32, t: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match cls:
        case 0: three(p, 1, u, t, List.append(&2, U32, acc, [u]))
        case 1: three(p, 2, u, t, acc)
        case _: acc

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat(["go=", U32.show(go(5n, True{}, 0, 0))]))
    b : Unit <- IO.print(String.concat(["lg=", U32.show(lg(3n, True{}, [1,2,3], 0))]))
    c : Unit <- IO.print(String.concat(["three=", U32.show(U32.from_nat(List.length(&2, U32, three(3n, 0, 7, Nil{}, Nil{}))))]))
    IO.print("alive")