import Base
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def bs(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

def step(ls: List<&2, String>, +k: U32, +b: X.Build) -> IO(Unit):
  match ls:
    case Nil{}: IO.pure(Unit, Unit{})
    case h <> t:
      IO.bind(Unit, Unit, say(String.concat(["k=", U32.show(k), " ok=",
        bs(X.Build.ok(b)), " nu=", U32.show(X.Build.nu(b)), " nb=", U32.show(X.Build.nb(b)),
        " pn=", U32.show(X.Build.pn(b)), " slot=", U32.show(X.Build.slot(b)),
        " nbp=", U32.show(X.Build.nbp(b)), " sbn=", U32.show(X.Build.sbn(b)),
        " bp=", U32.show(U32.from_nat(List.length(&2, U32, X.Build.bp(b)))),
        " | ", String.take(h, 40)])),
        _ => step(t, X.Prog.parse.k(h, k), X.Prog.parse.at(h, k, b)))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def after(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
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
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), after))
