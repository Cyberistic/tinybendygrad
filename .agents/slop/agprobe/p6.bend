import Base
type TE is Data: TE{kind: U32, cty: String}
def at2(k: U32, xs: List<&2, TE>, fuel: Nat) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None{}
    case TE{kind, cty} <> rest: List.find.put(TE, TE{kind, cty}, at2(k, rest, fuel.pred), U32.is_eq(kind, k))
def at(k: U32, xs: List<&2, TE>) -> Maybe<&2, TE>: at2(k, xs, 4096n)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p6 ", Bool.show(Bool.is_true(at(1, [TE{1,"a"},TE{2,"b"}]))) ]))
