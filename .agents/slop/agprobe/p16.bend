import Base
type Ty is Data: Ty{kind: U32, nm: String, sub: List<&1, Ty>}
def head(xs: List<&1, Ty>) -> Ty:
  match xs:
    case Ty{kind, nm, sub} <> _: Ty{kind, nm, sub}
def sz(t: Ty) -> U32:
  match t:
    case Ty{kind, nm, sub}:
      match sub:
        case Nil{}: 1
        case _: U32.add(1, sz(head(sub)))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(sz(Ty{1,"a",[Ty{2,"b",[Ty{3,"c",Nil{}}]}]})))
