import Base
type Ty is Data: Ty{kind: U32, nm: String, sub: List<&1, Ty>}
# self-call on a structurally-smaller sub-record of the SAME parameter
def sz(t: Ty) -> U32:
  match t.sub:
    case Nil{}: 1
    case Ty{kind, nm, sub} <> rest: U32.add(1, sz(sz_of(rest)))
def sz_of(xs: List<&1, Ty>) -> Ty:
  match xs:
    case Ty{kind, nm, sub} <> _: Ty{kind, nm, sub}
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(sz(Ty{1,"a",[Ty{2,"b",[Ty{3,"c",Nil{}}]}]})))
