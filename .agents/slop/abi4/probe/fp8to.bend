import ../../../../tinybendygrad/dtype.bend as D

def main() -> IO(Unit):
  do IO<Unit>:
    v : F32 <- D.Dt.fp8_to(60, 0)
    IO.print("F32ROW fp8to = " ++ F32.show(v))
