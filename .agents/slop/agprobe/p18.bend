import Base
type Ty is Data: Ty{kind: U32, nm: String}
def sz(t: Ty) -> U32:
  match t:
    case Ty{kind, nm}: U32.add(1, sz(Ty{kind, nm}))
