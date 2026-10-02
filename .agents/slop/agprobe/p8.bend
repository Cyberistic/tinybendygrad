import Base
type TE is Data: TE{kind: U32, cty: String}
def at(k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None{}
    case TE{kind, cty} <> rest:
      if U32.is_eq(kind, k): Some{ TE{kind, cty} }
      else at(k, rest)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p8 ", Bool.show(Bool.is_true(at(1, [TE{1,"a"},TE{2,"b"}]))) ]))
