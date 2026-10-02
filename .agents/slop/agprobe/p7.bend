import Base
type TE is Data: TE{kind: U32, cty: String}
def at3(k: U32, hv: Bool, r: Maybe<&2, TE>, xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: r
    case TE{kind, cty} <> rest:
      match hv:
        case True{}: Some{ TE{kind, cty} }
        case False{}: at3(k, U32.is_eq(kind, k), r, rest)
def at(k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>: at3(k, False{}, None{}, xs)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p7 ", Bool.show(Bool.is_true(at(1, [TE{1,"a"},TE{2,"b"}]))) ]))
