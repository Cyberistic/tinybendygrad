import Base
def go(f: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: List.reverse(&2, U32, acc)
    case Succ{q}: go(q, List.append(&2, U32, List.append(&2, U32, [U32.from_nat(q)], Nil{}), acc))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.show(go(4n, Nil{})))
