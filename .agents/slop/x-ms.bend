import Base
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def text(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+t}: t
    case Fail{_}: ""

def get(ms: List<&2, U32>, +k: Nat, +at: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ms, k), 999)

def rep(m: Maybe<&2, X.Load>) -> IO(Unit):
  match m:
    case Some{+l}:
      IO.bind(Unit, Unit, say(String.concat(["n=", U32.show(X.Load.n(l)),
        " nms=", U32.show(U32.from_nat(List.length(&2, U32, X.Load.ms(l))))])), _ =>
        IO.bind(Unit, Unit, say(String.concat(["ms[0..3] = ",
          U32.show(get(X.Load.ms(l), 0n, 0)), " ", U32.show(get(X.Load.ms(l), 1n, 0)), " ",
          U32.show(get(X.Load.ms(l), 2n, 0)), " ", U32.show(get(X.Load.ms(l), 3n, 0))])),
          _ => IO.bind(Unit, Unit, say(String.concat(["ms[60..67] = ",
            U32.show(get(X.Load.ms(l), 60n, 0)), " ", U32.show(get(X.Load.ms(l), 61n, 0)), " ",
            U32.show(get(X.Load.ms(l), 62n, 0)), " ", U32.show(get(X.Load.ms(l), 63n, 0)), " | ",
            U32.show(get(X.Load.ms(l), 64n, 0)), " ", U32.show(get(X.Load.ms(l), 65n, 0)), " ",
            U32.show(get(X.Load.ms(l), 66n, 0)), " ", U32.show(get(X.Load.ms(l), 67n, 0))])),
            _ => IO.pure(Unit, Unit{}))))
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