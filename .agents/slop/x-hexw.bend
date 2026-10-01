import Base
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def dump(+l: X.Load) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["arena word0 = ", U32.show(X.Mem.ld4(X.Load.ms(l), 0)),
    "   want 1065353216 (1.0f)"])), _ => IO.pure(Unit, Unit{}))

def go(m: Maybe<&2, X.Load>) -> IO(Unit):
  match m:
    case Some{+l}: dump(l)
    case None{}: say("REFUSED")

def main() -> IO(Unit):
  do IO<Unit>:
    go(X.Prog.parse("bendexec1 2 1\n1: PARAM float k:param:8:g\n2: SINK void - 1\n8 0000803f\n"))
