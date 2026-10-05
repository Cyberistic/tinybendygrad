import Base

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- F32.add(1.5, 1.0)
    IO.print("F32ROW p = " ++ F32.show(v))
