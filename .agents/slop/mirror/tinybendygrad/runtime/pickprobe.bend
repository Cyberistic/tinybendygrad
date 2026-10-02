import Base
def t(x: U32, c: Bool) -> U32: Bool.pick(U32, c, 111, 222)
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print("pick(true,111,222)=" ++ U32.show(t(0, True{})))
    b : Unit <- IO.print("pick(false,111,222)=" ++ U32.show(t(0, False{})))
    return a
