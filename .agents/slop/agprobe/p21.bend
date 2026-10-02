import Base
type TH is Data: TH{kind: U32, hint: String}
def th_at(+k: U32, xs: List<&2, TH>) -> Maybe<&2, TH>:
  match xs:
    case Nil{}: None{}
    case TH{+kind, hint} <> rest: List.find.put(TH, TH{kind, hint}, th_at(k, rest), U32.is_eq(kind, k))
def th_hint_of(t: TH) -> String:
  match t:
    case TH{kind, hint}: hint
def th_hint(m: Maybe<&2, TH>) -> String:
  match m:
    case Some{value}: th_hint_of(value)
    case None{}: ""
def th_hit(+k: U32, xs: List<&2, TH>) -> Bool: Bool.not(String.eq(th_hint(th_at(k, xs)), ""))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Bool.show(th_hit(1, [TH{1,"int"}])))
