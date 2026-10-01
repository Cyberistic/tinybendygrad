import Base
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def bs(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def blank() -> X.Args: X.Args{"", 1, 1, 1, Nil{}, True{}}

def rep(+k: Nat, +r: X.Prog, +bad: Bool) -> IO(Unit):
  match bad:
    case True{}:
      +u = X.Uop.at(X.Prog.us(r), X.Prog.pc(r))
      IO.bind(Unit, Unit, say(String.concat(["fuel=", X.show.k(k), " bad=T pc=",
        U32.show(X.Prog.pc(r)), " op=", X.opname.of(u),
        " oob=", bs(X.Prog.oob(r, u, 0, 1n)),
        " store.i=", U32.show(X.Prog.store.i(r, u, 0)),
        " e=", U32.show(X.Buf.e(X.Prog.buf(r, u))),
        " run=", U32.show(X.Uop.run(u))])),
        _ => IO.pure(Unit, Unit{}))
    case False{}: IO.pure(Unit, Unit{})

# the fuels are 1..120, each from a FRESH machine so the answer is the fuel alone
def step(+k: Nat, +p: X.Prog) -> IO(Unit):
  match k:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+j: IO.bind(Unit, Unit, rep(k, X.run(k, p), X.Prog.bad(X.run(k, p))), _ => step(j, X.Prog.reset(p)))

def go(ld: Maybe<&2, X.Load>) -> IO(Unit):
  match ld:
    case Some{+l}: step(75n, X.Prog.of(blank(), l))
    case None{}: say("REFUSED")

def after(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => go(X.Prog.parse(text(r))))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), after))