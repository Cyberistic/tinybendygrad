import Base

type Prog is Data:
  Prog{vs: List<&2, U32>, pc: U32}

def Prog.pc(p: Prog) -> U32:
  match p:
    case Prog{vs, pc}: pc

def Prog.n(_: Prog) -> U32: 8

def Prog.step(pr: Prog) -> Prog:
  Prog{List.set(&2, U32, pr.vs, U32.to_nat(Prog.pc(pr)), U32.add(Prog.pc(pr), 1)), U32.add(Prog.pc(pr), 1)}

# a TWO-def cycle: walk matches the Nat fuel, walk.at matches the done Bool
def walk(f: Nat, pr: Prog) -> Maybe<&1, Prog>:
  match f:
    case 0n: None{}
    case 1n+p: walk.at(pr, U32.is_ge(Prog.pc(pr), Prog.n(pr)), p)

def walk.at(pr: Prog, done: Bool, f: Nat) -> Maybe<&1, Prog>:
  match done:
    case True{}: Some{pr}
    case False{}: walk(f, Prog.step(pr))

def show(m: Maybe<&1, Prog>) -> String:
  match m:
    case Some{pr}: String.concat(["pc=", U32.show(Prog.pc(pr))])
    case None{}: "fuel"

def q3(a: U32, b: U32) -> String:
  match U32.is_ge(a, b):
    case True{}: "ge"
    case False{}: "lt"

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(show(walk(100n, Prog{List.replicate(U32, 8n, 0), 0})))
    b : Unit <- IO.print(q3(3, 4))
    return Unit{}