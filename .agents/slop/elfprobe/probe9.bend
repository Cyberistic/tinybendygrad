import Base
type S3 is Data:
  S3{a: U32, b: U32}
def S3.of(a: U32, b: U32) -> S3: S3{a, b}
def S3.f(w: S3) -> U32:
  match w:
    case S3{a, b}: U32.add(a, b)
def cell(v: U32) -> List<&2, U32>: [v]
def go.at(+t: List<&2, U32>, +v: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, cell(v))
def go(fuel: List<&2, U32>, +w: S3, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case Nil{}: List.reverse(&2, U32, acc)
    case +k <> t: go.at(t, S3.f(w), acc)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.show(go(List.range(5n), S3.of(1, 2), Nil{})))
