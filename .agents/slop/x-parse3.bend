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

# walk the parse fold one line at a time and name the line where `ok` goes False
def step(ls: List<&2, String>, +k: U32, +b: X.Build) -> IO(Unit):
  match ls:
    case Nil{}: say(String.concat(["END ok=", bs(X.Build.ok(b)), " nu=", U32.show(X.Build.nu(b)),
      " nb=", U32.show(X.Build.nb(b)), " slot=", U32.show(X.Build.slot(b))]))
    case h <> t:
      +b2 = X.Prog.parse.at(h, k, b)
      IO.bind(Unit, Unit, say(String.concat([U32.show(k), " ok=", bs(X.Build.ok(b2)),
        " nu=", U32.show(X.Build.nu(b2)), " nb=", U32.show(X.Build.nb(b2)),
        " slot=", U32.show(X.Build.slot(b2))])), _ => step(t, U32.add(k, 1), b2))

def go(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => step(String.lines(text(r)), 0, X.Build.blank()))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), go))