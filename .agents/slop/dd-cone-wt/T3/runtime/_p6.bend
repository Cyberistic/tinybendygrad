import Base
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["b1=", U32.show(F32.bits(41.666666666666664)), " b2=", U32.show(F32.bits(0.001)), " b3=", U32.show(F32.bits(0.000000001))]))
