import Base
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def body(+i: U32, +u: X.Uop) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["line ", U32.show(i), " -> ",
    X.opname.of(u), " nsrc=", U32.show(X.Uop.nsrc(u)),
    " slot=", U32.show(X.Uop.slot(u)), " run=", U32.show(X.Uop.run(u)),
    " src0=", U32.show(X.Uop.src0(u)), " src1=", U32.show(X.Uop.src1(u))])),
    _ => IO.pure(Unit, Unit{}))

def none(i: U32) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["line ", U32.show(i), " -> NONE"])), _ => IO.pure(Unit, Unit{}))

def dump(+us: List<&2, X.Uop>, +i: U32) -> IO(Unit):
  match us:
    case Nil{}: IO.pure(Unit, Unit{})
    case u <> t:
      IO.bind(Unit, Unit, say(String.concat(["uop ", U32.show(i), " ", X.opname.of(u),
        " slot=", U32.show(X.Uop.slot(u)), " run=", U32.show(X.Uop.run(u))])),
        _ => dump(t, U32.add(i, 1)))

def rep(m: Maybe<&2, X.Load>) -> IO(Unit):
  match m:
    case Some{+l}: dump(X.Load.us(l), 0)
    case None{}: say("REFUSED")

def one(+i: U32, +m: Maybe<&2, X.Uop>) -> IO(Unit):
  match m:
    case Some{+u}: body(i, u)
    case None{}: none(i)

def step(ls: List<&2, String>, +k: U32) -> IO(Unit):
  match ls:
    case Nil{}: IO.pure(Unit, Unit{})
    case h <> t: IO.bind(Unit, Unit, one(k, X.Uop.line(h, 0)), _ => step(t, U32.add(k, 1)))

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
