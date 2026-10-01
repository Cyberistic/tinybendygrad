import Base
import ./a.bend as A
def b.go(x: A.AA) -> U32: A.a.get(x)
def b.main() -> IO(Unit):
  do IO<Unit>: IO.print(String.concat(["b=", U32.show(b.go(A.a.make()))]))
