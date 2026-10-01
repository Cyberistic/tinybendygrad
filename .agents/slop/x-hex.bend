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

# one `<nbytes> <hex>` line: the fold's ok, the stated nbytes, the hex length
def one(+k: U32, +s: String) -> IO(Unit):
  +hx = X.w(X.words(s), 1n)
  IO.bind(Unit, Unit, say(String.concat([U32.show(k), " hexlen=",
    U32.show(U32.from_nat(List.length(&2, String, X.words(hx)))), " chars=",
    U32.show(U32.from_nat(List.length(&2, Char, String.to_list(hx)))), " ok=",
    bs(X.bytes_ok(X.bytes_of(X.Prog.chars1(String.to_list(hx), Nil{}))))])),
    _ => IO.pure(Unit, Unit{}))

def step(ls: List<&2, String>, +k: U32) -> IO(Unit):
  match ls:
    case Nil{}: IO.pure(Unit, Unit{})
    case h <> t: IO.bind(Unit, Unit, one(k, h), _ => step(t, U32.add(k, 1)))

def go(pr: (File & Result<&1, &1, U32 & String, String>)) -> IO(Unit):
  (f, r) = pr
  IO.bind(Unit, Unit, File.close(f), _ => step(String.lines(text(r)), 0))

def path(m: Maybe<&2, X.Args>) -> String:
  match m:
    case Some{+a}: X.Args.path(a)
    case None{}: ""

def main() -> IO(Unit):
  do IO<Unit>:
    av : List<String> <- IO.args()
    IO.bind(File, Unit, IO.try(File, File.open(path(X.Args.of(av)), "r")),
      f => IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(f, 1073741824), go))