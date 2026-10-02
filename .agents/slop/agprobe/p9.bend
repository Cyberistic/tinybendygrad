import Base
type TE is Data: TE{kind: U32, cty: String}
def at(k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None{}
    case TE{kind, cty} <> rest: List.find.put(TE, TE{kind, cty}, at(k, rest), U32.is_eq(kind, k))
def cty_of(k: U32, xs: List<&2, TE>) -> String:
  match at(k, xs):
    case Some{cty}: cty
    case None{}: "MISS"
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p9 ", cty_of(1, [TE{1,"a"},TE{2,"b"}]), " ", cty_of(9, [TE{1,"a"}])]))
