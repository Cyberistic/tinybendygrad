import Base
def i2(i: U32) -> U32: U32.add(i, 1)
def cell(i: U32) -> List<&2, U32>: [i]
def go(f: Nat, i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: List.reverse(&2, U32, acc)
    case Succ{q}: go2(q, i2(i), acc)
def go2(f: Nat, i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match f:
    case 0n: List.reverse(&2, U32, acc)
    case Succ{p}: go2(p, i2(i), List.append(&2, U32, cell(i), acc))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.show(go(4n, 0, Nil{})))
