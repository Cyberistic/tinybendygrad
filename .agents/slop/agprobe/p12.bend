import Base
type Ty is Data: Ty{kind: U32, nm: String, flag: Bool}
def at(ix: Nat, ts: List<&2, Ty>) -> Maybe<&2, Ty>: List.get(&2, Ty, ts, ix)
def step_of(m: Maybe<&2, Ty>, rest: Nat) -> String:
  match m:
    case None{}: "none"
    case Some{t}: go(t.kind, t.nm, rest)
def step(ix: Nat, ts: List<&2, Ty>, rest: Nat) -> String: step_of(at(ix, ts), rest)
def go(k: U32, n: String, rest: Nat) -> String: String.concat([U32.show(k), ":", n, ":", U32.show(rest)])
def pick(f: Bool, a: String, b: String) -> String:
  if f: String.concat(["on:", a]) else String.concat(["off:", b])
def flag_of(m: Maybe<&2, Ty>) -> String:
  match m:
    case None{}: "none"
    case Some{t}: pick(t.flag, t.nm, "off")
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(step(1n, [Ty{0,"z",False{}}, Ty{7,"Pair",True{}}], 4n))
    IO.print(flag_of(at(1n, [Ty{0,"z",False{}}, Ty{7,"Pair",True{}}])))
