import Base
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def body(+i: U32, +u: X.Uop) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat([U32.show(i), ": ", X.opname.of(u),
    " dt=", U32.show(S.Dt.itemsize(X.Uop.dt(u))),
    " kind=", U32.show(X.Uop.kind(u)), " a=", U32.show(X.Uop.a(u)),
    " b=", U32.show(X.Uop.b(u)), " slot=", U32.show(X.Uop.slot(u)),
    " run=", U32.show(X.Uop.run(u)),
    " srcs=[", U32.show(X.Uop.src0(u)), ",", U32.show(X.Uop.src1(u)), "]"])),
    _ => IO.pure(Unit, Unit{}))

def dump(+us: List<&2, X.Uop>, +i: U32) -> IO(Unit):
  match us:
    case Nil{}: IO.pure(Unit, Unit{})
    case u <> t:
      IO.bind(Unit, Unit, body(i, u), _ => dump(t, U32.add(i, 1)))

def rep(m: Maybe<&2, X.Load>) -> IO(Unit):
  match m:
    case Some{+l}: dump(X.Load.us(l), 1)
    case None{}: say("REFUSED")

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def after(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => rep(X.Prog.parse(text(r))))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), after))
