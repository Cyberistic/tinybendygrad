import Base
def U32s.go(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: U32s.go(t, List.append(&2, String, acc, [U32.show(h)]))
def one(v: U32) -> List<&2, U32>: [v]
def go(fuel: List<&2, Nat>, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case Nil{}: acc
    case +k <> t: go(t, List.append(&2, U32, acc, one(U32.from_nat(k))))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["raw=", String.join(U32s.go(go(List.range(4n), Nil{}), Nil{}), ",")]))
    IO.print(String.concat(["rev=", String.join(U32s.go(List.reverse(&2, U32, go(List.range(4n), Nil{})), Nil{}), ",")]))
