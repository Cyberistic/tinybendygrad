import Base
type Ty is Data: Ty{kind: U32, nm: String, kids: List<&2, Ty>}
def sz(t: Ty) -> U32:
  match t:
    case Ty{kind, nm, kids}:
      match kids:
        case Nil{}: 1
        case Ty{k, n, ks} <> rest: U32.add(1, sz(Ty{k, n, ks}))
def leaf() -> Ty: Ty{0, "", Nil{}}
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(sz(Ty{1,"a",[Ty{2,"b",Nil{}}, Ty{3,"c",Nil{}}]})))
    IO.print(U32.show(sz(leaf())))
