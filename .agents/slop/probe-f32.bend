import Base

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["bits(1.0)=", U32.show(F32.bits(1.0)), " bits(3.5)=", U32.show(F32.bits(3.5)),
      " bits(0.5)=", U32.show(F32.bits(0.5)), " F32.show(1.0)=", F32.show(1.0)]))
