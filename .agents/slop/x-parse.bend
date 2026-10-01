import Base
import ../../tinybendygrad/runtime/executor.bend as X

def join(ws: List<&2, String>) -> String:
  X.Prog.out.join(List.reverse(&2, String, ws), "|")

def okstr(m: Maybe<&2, X.Uop>) -> String:
  match m:
    case Some{_}: "yes"
    case None{}: "NO"

def say(ln: U32, s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(String.concat([U32.show(ln), ": ", s])),
    _ => IO.pure(Unit, Unit{}))

def one(ln: U32, +l: String) -> IO(Unit):
  ws = X.words(l)
  IO.bind(Unit, Unit, say(ln, String.concat(["[", join(ws), "] ", okstr(X.Uop.line(l, 0))])),
    _ => IO.pure(Unit, Unit{}))

def shows(ls: List<&2, String>, +k: U32) -> IO(Unit):
  match ls:
    case Nil{}: IO.pure(Unit, Unit{})
    case h <> t: IO.bind(Unit, Unit, one(k, h), _ => shows(t, U32.add(k, 1)))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def go(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => shows(String.lines(text(r)), 1))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), go))