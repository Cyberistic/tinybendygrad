import Base
def w(fuel: Nat, total: Nat, idx: U32, acc: String) -> String:
  match fuel:
    case 0n: acc
    case Succ{q}: w(q, total, U32.add(idx, 1), String.concat([acc, "x"]))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(w(3n, 9n, 0, ""))
