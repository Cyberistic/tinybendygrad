import Base
type TE is Data: TE{kind: U32, cty: String}
def f(xs: List<&2, TE>) -> Maybe<&2, TE>:
  match xs:
    case Nil{}: None
    case TE{kind, cty} <> rest: Some{ TE{kind, cty} }
def g(xs: List<&2, TE>) -> String:
  match xs:
    case Nil{}: ""
    case TE{cty} <> rest: cty
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p1 ", Bool.show(Bool.is_true(f([TE{1,"a"}]))), " g=", g([TE{1,"a"}])]))
