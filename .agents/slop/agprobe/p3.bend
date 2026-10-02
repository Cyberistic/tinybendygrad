import Base
def le(x: U32, y: U32) -> U32: U32.le(x, y)
def lt(x: U32, y: U32) -> U32: U32.lt(x, y)
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(le(1,2)))
    IO.print(U32.show(lt(1,2)))
    IO.print(Bool.show(Bool.or(True{}, False{})))
