import Base
type Reg is Data:
  Reg{is_list: Bool, nm: String}
def Reg.l(r: Reg) -> Bool:
  match r:
    case Reg{is_list, nm}: is_list
def Reg.nm(r: Reg) -> String:
  match r:
    case Reg{is_list, nm}: nm
def mk(i: U32) -> Reg: Reg{False{}, String.concat(["%r", U32.show(i)])}
def mkg(i: U32) -> Reg: Reg{True{}, String.concat(["{", Reg.nm(mk(i)), ",}"])}
def showg(+r: Reg) -> String: String.concat([Bool.pick(String, Reg.l(r), "L", "S"), Reg.nm(r)])
def probe.maybe(m: Maybe<&2, Reg>) -> String:
  match m:
    case Some{r}: showg(r)
    case None{}: "NONE"
def probe(xs: List<&2, Reg>, i: U32) -> String: probe.maybe(List.get(&2, Reg, xs, U32.to_nat(i)))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([probe([mk(0), mkg(1)], 0), " ", probe([mk(0), mkg(1)], 1), " ",
      probe([mk(0), mkg(1)], 2), " ", probe([mk(0), mkg(1)], 7)]))