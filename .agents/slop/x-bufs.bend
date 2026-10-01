import Base
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def one(+fs: List<&2, X.Buf>) -> IO(Unit):
  match fs:
    case Nil{}: say("  (end)")
    case f <> t:
      IO.bind(Unit, Unit, say(String.concat(["  buf base=", U32.show(X.Buf.base(f)),
        " w=", U32.show(X.Buf.w(f)), " e=", U32.show(X.Buf.e(f))])), _ => one(t))

def rep(m: Maybe<&2, X.Load>) -> IO(Unit):
  match m:
    case Some{+l}:
      IO.bind(Unit, Unit, say(String.concat(["nb=", U32.show(X.Load.nb(l)),
        " nfs=", U32.show(U32.from_nat(List.length(&2, X.Buf, X.Load.fs(l))))])), _ =>
        one(X.Load.fs(l)))
    case None{}: say("REFUSED")

def go(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
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
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), go))