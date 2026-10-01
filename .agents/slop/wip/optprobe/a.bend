import Base
type AA is Data: AA{x: U32}
def a.make() -> AA:
  AA{x: 3}
def a.get(a: AA) -> U32:
  a.x
def a.main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["a=", U32.show(a.get(a.make()))]))
