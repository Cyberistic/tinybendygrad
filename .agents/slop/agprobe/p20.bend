import Base
type Ty is Data: Ty{kind: U32, nm: String, kids: List<&2, Ty>}
def sz(t: Ty, n: U32) -> U32:
  match t:
    case Ty{kind, nm, kids}:
      match kids:
        case Nil{}: n
        case Ty{k, nn, ks} <> rest: U32.add(1, U32.add(sz(Ty{k, nn, ks}, n), sz(t, U32.add(n, 1))))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(sz(Ty{1,"a",[Ty{2,"b",Nil{}}, Ty{3,"c",Nil{}}]}, 0)))
