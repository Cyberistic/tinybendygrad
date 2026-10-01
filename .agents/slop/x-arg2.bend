import Base
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/runtime/executor.bend as X

def say(s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def maybe0(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 999999

def showb(+b: X.Build) -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["hex 00004040 -> ", U32.show(maybe0(X.Arg.hex("00004040"))),
    "   want 1073741824"])), _ => IO.pure(Unit, Unit{}))

def showa() -> IO(Unit):
  IO.bind(Unit, Unit, say(String.concat(["hex 00000040 -> ", U32.show(maybe0(X.Arg.hex("00000040"))),
    "   want 1073741824"])), _ => showb(X.Build.blank()))

def main() -> IO(Unit):
  do IO<Unit>:
    showa()
