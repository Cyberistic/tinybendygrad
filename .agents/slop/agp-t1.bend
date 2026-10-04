import Base
law CX:
  Type
def f() -> IO(CX):
  do IO<CX>:
    IO.die(CX, 0, "no libclang")
