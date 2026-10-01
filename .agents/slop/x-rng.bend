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

def line(+p: X.Prog) -> IO(Unit):
  +u = X.Uop.at(X.Prog.us(p), X.Prog.pc(p))
  IO.bind(Unit, Unit, say(String.concat([U32.show(X.Prog.pc(p)), " ",
    X.opname.of(u), " cur=", U32.show(X.Prog.cur(p, u)), " trip=", U32.show(X.Prog.trip(p, u)),
    " seen=", bs(X.Prog.seen(p, u)), " slot=", U32.show(X.Uop.slot(u)), " run=", U32.show(X.Uop.run(u)), " loop=", U32.show(X.Prog.loop(p, X.Prog.pc(p))),
    " bad=", bs(X.Prog.bad(p)), " i=", U32.show(X.Prog.store.i(p, u, 0)),
    " e=", U32.show(X.Buf.e(X.Prog.buf(p, u))), " ptr=", X.elemname(X.Prog.src(p, u, 0n))])),
    _ => IO.pure(Unit, Unit{}))

# step at most 40 times, printing the pc and the RANGE's state each step
def seek(+steps: Nat, +p: X.Prog) -> IO(Unit):
  match steps:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+j: IO.bind(Unit, Unit, line(p), _ => seek(j, X.Prog.step(p)))

def go(ld: Maybe<&2, X.Load>) -> IO(Unit):
  match ld:
    case Some{+l}: seek(200n, X.Prog.of(blank(), l))
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