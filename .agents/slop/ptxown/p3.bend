import Base
type Rg is Data:
  Rg{is_list: Bool, parts: List<&2, String>}
def Rg.p(r: Rg) -> List<&2, String>:
  match r:
    case Rg{is_list, parts}: parts
def has_rg(+r: Rg) -> Bool: Bool.not(List.is_empty(&2, String, Rg.p(r)))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.pick(String, has_rg(Rg{False{}, ["a"]}), "H", "-"))
