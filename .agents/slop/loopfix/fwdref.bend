# A THREE-LINE PROBE, and it exists because the layout of the fix depends on it: the
# shared `() ` rule has to call `late()` and `dt_of_nil()`, and whether bend lets a def
# call a def defined LATER in the same file decides whether the shared rule can live
# beside the ops it serves or has to live below `late()`.
import Base

def early(a: U32) -> U32:
  later(a)

def later(a: U32) -> U32:
  a

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(U32.show(early(1)))
    IO.pure(Unit, Unit{})