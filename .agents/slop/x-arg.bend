import Base
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def words.go(ws: List<&2, String>) -> IO(Unit):
  match ws:
    case Nil{}: IO.pure(Unit, Unit{})
    case h <> t: IO.bind(Unit, Unit, say(String.concat(["  w=[", h, "]"])), _ => words.go(t))

def kstr(m: Maybe<&2, X.Arg>) -> String:
  match m:
    case Some{+g}: String.concat(["kind=", U32.show(X.Arg.kind(g)), " x=", U32.show(X.Arg.x(g)),
      " y=", U32.show(X.Arg.y(g))])
    case None{}: "NONE"

def probe(+s: String) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["[", s, "] -> ", kstr(X.Arg.of(s))])), _ => IO.pure(Unit, Unit{}))

def main() -> IO(Unit):
  IO.bind(Unit, Unit, words.go(X.words("1: PARAM float k:param:64:g")), _ =>
    IO.bind(Unit, Unit, probe("k:param:64:g"), _ =>
      IO.bind(Unit, Unit, probe("f:00000040"), _ =>
        IO.bind(Unit, Unit, probe("c:5"), _ =>
          IO.bind(Unit, Unit, probe("-"), _ =>
            IO.bind(Unit, Unit, probe("k:vec:4"), _ =>
              IO.bind(Unit, Unit, probe("k:idx:0"), _ => IO.pure(Unit, Unit{}))))))))